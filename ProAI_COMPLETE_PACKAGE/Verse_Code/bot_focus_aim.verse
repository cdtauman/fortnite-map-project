# ============================================================================
# FILE: bot_focus_aim.verse — Focus Interface & Headshot Offset Logic
# LOCATION: Content/ (root)
# PHASE: 2 (base), Phase 4 (ELO-driven variance)
#
# ARCHITECTURE:
#   Manages the bot's aiming behavior through two complementary systems:
#
#   1. ENGINE-LEVEL AIM (MaintainFocus):
#      The focus_interface.MaintainFocus(agent) call locks the bot's
#      upper-body orientation toward the target player. This is the
#      engine's built-in tracking — it works at center-of-mass by
#      default. It runs as a suspending background task and allows
#      the bot to aim independently of its movement direction,
#      producing natural strafe-and-shoot behavior.
#
#   2. ANALYTICAL AIM POINT (HeadZOffset):
#      The engine's MaintainFocus aims at center-mass. The guard
#      auto-fire system uses this aim direction as its firing reference.
#      The HeadZOffset is a mathematical calculation that tells
#      analytics (Module C) and the weapon controller where the
#      bot "intended" to aim — enabling headshot tracking and
#      precision metrics. At high ELO, the NPC Character Definition
#      should be configured with tighter aim accuracy in the editor
#      to complement this code-side offset.
#
#   3. AIM VARIANCE (ELO-scaled imprecision):
#      At low ELO, AimVariance introduces random scatter to the
#      calculated aim point, simulating inconsistent aim. At high
#      ELO, variance approaches zero, meaning the bot "intends"
#      perfect headshots. The actual hit registration is handled
#      by the guard auto-fire system, but this data feeds analytics.
#
# FOCUS API NOTE:
#   MaintainFocus(agent)<suspends> is the primary call. It suspends
#   until focus is lost (target eliminated, out of range, etc.).
#   We wrap it in a retry loop so that if focus drops momentarily
#   (e.g. target behind cover), it re-acquires automatically.
# ============================================================================
using { /Fortnite.com/AI }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Game }
using { /Verse.org/Simulation }
using { /Verse.org/Random }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/SpatialMath }

# ══════════════════════════════════════════════════════════════════════════════
# BOT FOCUS & AIM CLASS
# ══════════════════════════════════════════════════════════════════════════════
bot_focus_aim<public> := class:

    Logger<private> : log = log{Channel := log_aim_ch}

    # ── Cached References (set via Init) ─────────────────────────────────────
    var CachedAgent<private>    : ?agent           = false
    var CachedChar<private>     : ?fort_character   = false
    var CachedFocus<private>    : ?focus_interface   = false
    var IsInitialized<private>  : logic             = false

    # ── Aim Parameters (tuned by ELO via ApplyDifficulty) ────────────────────
    # HeadZOffset: vertical displacement from center-mass to head.
    # ~55 Unreal units targets the head/neck region of a standard
    # Fortnite character model. Positive = upward.
    var HeadZOffset<public>     : float = 55.0

    # AimVariance: random scatter radius applied to the aim point.
    # 0.0 = perfect aim (high ELO), 15.0+ = sloppy aim (low ELO).
    var AimVariance<public>     : float = 10.0

    # FocusRetryDelay: seconds to wait before re-attempting MaintainFocus
    # if focus is lost (target behind cover, brief LOS break).
    var FocusRetryDelay<public> : float = 0.15

    # ── Telemetry ────────────────────────────────────────────────────────────
    var TotalFocusAttempts<private>    : int = 0
    var TotalFocusLosses<private>      : int = 0
    var TotalAimSamples<private>       : int = 0

    # ══════════════════════════════════════════════════════════════════════════
    # INITIALIZATION
    # Called once from bot_behavior_base after acquiring Agent + FortCharacter.
    # Extracts and caches the focus_interface.
    # ══════════════════════════════════════════════════════════════════════════
    Init<public>(InAgent : agent, InChar : fort_character) : logic =
        set CachedAgent = option{InAgent}
        set CachedChar = option{InChar}

        if (Focus := InChar.GetFocusInterface[]):
            set CachedFocus = option{Focus}
            set IsInitialized = true
            Logger.Print("AIM: Initialized. FocusInterface acquired.")
            return true
        else:
            Logger.Print("AIM: ERROR — GetFocusInterface[] failed. Bot cannot aim.")
            set IsInitialized = false
            return false

    # ══════════════════════════════════════════════════════════════════════════
    # APPLY DIFFICULTY
    # Pushes ELO-derived values into the aim parameters.
    # Called by bot_behavior_base when the profile is set or updated.
    # ══════════════════════════════════════════════════════════════════════════
    ApplyDifficulty<public>(Profile : bot_difficulty_profile) : void =
        set HeadZOffset = Profile.AimZOffset
        set AimVariance = Profile.AimVariance

        # Scale focus retry delay by reaction time:
        # Faster reactions = quicker re-acquire after LOS break
        set FocusRetryDelay = Profile.ReactionTimeMs / 3000.0
        if (FocusRetryDelay < 0.05):
            set FocusRetryDelay = 0.05
        if (FocusRetryDelay > 0.5):
            set FocusRetryDelay = 0.5

        Logger.Print("AIM: Difficulty applied — ZOffset:{HeadZOffset} Variance:{AimVariance} RetryDelay:{FocusRetryDelay}")

    # ══════════════════════════════════════════════════════════════════════════
    # ACTIVE FOCUS — PRIMARY AIM METHOD
    # Suspending call that continuously tracks the target player.
    # Runs MaintainFocus in a retry loop so focus automatically
    # re-acquires if momentarily lost.
    #
    # This is called as a branched background task from
    # bot_behavior_base.AimTrackingLoop(). It runs for the bot's
    # entire lifetime and is cancelled by the parent race when
    # the bot dies.
    # ══════════════════════════════════════════════════════════════════════════
    StartFocusingOn<public>(TargetAgent : agent)<suspends> : void =
        Logger.Print("AIM: StartFocusingOn — beginning continuous focus tracking.")

        if (Focus := CachedFocus?):
            loop:
                if (BotChar := CachedChar?):
                    if (not BotChar.IsActive[]):
                        Logger.Print("AIM: Bot no longer active. Ending focus loop.")
                        break
                else:
                    break

                set TotalFocusAttempts += 1

                # MaintainFocus suspends until focus is lost or cancelled.
                # The engine handles smooth interpolation of the bot's
                # upper body to track the target. While this runs, the
                # bot's legs can move independently via NavigateTo.
                Focus.MaintainFocus(TargetAgent)

                # MaintainFocus returned — focus was lost
                set TotalFocusLosses += 1
                Logger.Print("AIM: Focus lost (attempt #{TotalFocusAttempts}). Retrying in {FocusRetryDelay}s.")

                # Brief delay before retry to prevent tight-loop spin
                # if the target is permanently obscured
                Sleep(FocusRetryDelay)
        else:
            Logger.Print("AIM: ERROR — No cached FocusInterface. Cannot aim.")

    # ══════════════════════════════════════════════════════════════════════════
    # FOCUS WITH EXPLICIT INTERFACE
    # Used by bot_behavior_base's AimTrackingLoop when passing the
    # focus_interface directly rather than relying on cached refs.
    # ══════════════════════════════════════════════════════════════════════════
    MaintainFocusOnTarget<public>(
        Focus : focus_interface,
        BotChar : fort_character,
        TargetAgent : agent
    )<suspends> : void =
        Logger.Print("AIM: MaintainFocusOnTarget — explicit interface mode.")
        loop:
            if (not BotChar.IsActive[]):
                break

            set TotalFocusAttempts += 1
            Focus.MaintainFocus(TargetAgent)

            set TotalFocusLosses += 1
            Logger.Print("AIM: Focus lost. Retrying.")
            Sleep(FocusRetryDelay)

    # ══════════════════════════════════════════════════════════════════════════
    # HEADSHOT TARGET CALCULATION
    # Returns the world-space position where the bot "intends" to aim:
    # the target player's position + HeadZOffset + random variance.
    #
    # This does NOT control where MaintainFocus points (that's engine-level).
    # It provides the calculated aim point for:
    #   - Analytics (Module C): track intended vs actual hit positions
    #   - Weapon controller: log whether the bot "tried" for a headshot
    #   - Coach (Module E): assess aim pattern quality
    # ══════════════════════════════════════════════════════════════════════════
    GetHeadshotTargetPosition<public>(TargetAgent : agent) : vector3 =
        set TotalAimSamples += 1

        if (TargetChar := TargetAgent.GetFortCharacter[]):
            BasePos := TargetChar.GetTransform().Translation

            # Apply head offset
            AimZ := BasePos.Z + HeadZOffset

            # Apply ELO-scaled variance
            VarianceX := GetRandomVariance()
            VarianceY := GetRandomVariance()
            VarianceZ := GetRandomVariance() * 0.5

            return vector3{
                X := BasePos.X + VarianceX,
                Y := BasePos.Y + VarianceY,
                Z := AimZ + VarianceZ
            }

        # Fallback: origin (should never happen in normal gameplay)
        vector3{X := 0.0, Y := 0.0, Z := 0.0}

    # Get the raw headshot position WITHOUT variance (perfect aim point).
    # Used for calculating ideal-vs-actual accuracy metrics.
    GetPerfectHeadshotPosition<public>(TargetAgent : agent) : vector3 =
        if (TargetChar := TargetAgent.GetFortCharacter[]):
            BasePos := TargetChar.GetTransform().Translation
            return vector3{
                X := BasePos.X,
                Y := BasePos.Y,
                Z := BasePos.Z + HeadZOffset
            }
        vector3{X := 0.0, Y := 0.0, Z := 0.0}

    # Get the center-mass position (where MaintainFocus actually aims).
    GetCenterMassPosition<public>(TargetAgent : agent) : vector3 =
        if (TargetChar := TargetAgent.GetFortCharacter[]):
            return TargetChar.GetTransform().Translation
        vector3{X := 0.0, Y := 0.0, Z := 0.0}

    # ══════════════════════════════════════════════════════════════════════════
    # AIM ANALYSIS UTILITIES
    # Used by analytics_engine (Module C) to compute precision metrics.
    # ══════════════════════════════════════════════════════════════════════════

    # Calculate the angular offset between the bot's current facing
    # direction and the ideal headshot position. Returns degrees.
    # Lower = better aim. Used for real-time aim quality scoring.
    GetAimDeviationDegrees<public>(TargetAgent : agent) : float =
        if:
            BotChar := CachedChar?
            TargetChar := TargetAgent.GetFortCharacter[]
        then:
            BotPos := BotChar.GetTransform().Translation
            HeadPos := GetPerfectHeadshotPosition(TargetAgent)

            # Direction from bot to head
            DX := HeadPos.X - BotPos.X
            DY := HeadPos.Y - BotPos.Y
            DZ := HeadPos.Z - BotPos.Z
            Len := Sqrt((DX * DX) + (DY * DY) + (DZ * DZ))

            if (Len > 0.1):
                # Bot's actual facing direction
                BotForward := BotChar.GetViewRotation().GetLocalForward()

                # Dot product for angle calculation
                NormDX := DX / Len
                NormDY := DY / Len
                NormDZ := DZ / Len
                Dot := (BotForward.X * NormDX) + (BotForward.Y * NormDY) + (BotForward.Z * NormDZ)

                # Clamp dot to [-1, 1] to avoid NaN from acos
                var ClampedDot : float = Dot
                if (ClampedDot > 1.0):
                    set ClampedDot = 1.0
                if (ClampedDot < -1.0):
                    set ClampedDot = -1.0

                # Convert to degrees: acos(dot) * (180 / pi)
                # Approximate: 1.0 - dot gives a reasonable deviation metric
                # where 0.0 = perfect alignment, 2.0 = opposite direction
                Deviation := (1.0 - ClampedDot) * 90.0
                return Deviation
        90.0

    # Calculate whether a shot from the bot's current facing would
    # land within "headshot range" (within HeadZOffset/2 of head position).
    IsAimingAtHead<public>(TargetAgent : agent) : logic =
        Deviation := GetAimDeviationDegrees(TargetAgent)
        # ~5 degrees of arc covers the head hitbox at typical engagement ranges
        if (Deviation < 5.0):
            return true
        false

    # ══════════════════════════════════════════════════════════════════════════
    # PRIVATE: RANDOM VARIANCE GENERATION
    # Produces a random float in range [-AimVariance, +AimVariance].
    # At high ELO, AimVariance is near zero → scatter is negligible.
    # At low ELO, AimVariance is ~15+ → significant scatter.
    # ══════════════════════════════════════════════════════════════════════════
    GetRandomVariance<private>() : float =
        if (AimVariance < 0.01):
            return 0.0
        # Generate a value in [0, 1], scale to [-Variance, +Variance]
        RawRandom := GetRandomFloatInRange(0.0, 1.0)
        (RawRandom * 2.0 * AimVariance) - AimVariance

    # Wrapper for random float generation.
    GetRandomFloatInRange<private>(MinVal : float, MaxVal : float) : float =
        Seed := GetSimulationElapsedTime() + (TotalAimSamples * 1.0)
        Range := MaxVal - MinVal
        # Simple pseudo-random based on simulation time + sample count
        # Verse doesn't expose a clean random float API, so we use
        # the fractional part of a high-frequency oscillation
        Frac := Seed - (Floor[Seed] or 0) * 1.0
        MinVal + (Frac * Range)

    # ══════════════════════════════════════════════════════════════════════════
    # TELEMETRY
    # ══════════════════════════════════════════════════════════════════════════
    GetFocusRetentionRate<public>() : float =
        if (TotalFocusAttempts > 0):
            Losses := TotalFocusLosses * 1.0
            Attempts := TotalFocusAttempts * 1.0
            return 1.0 - (Losses / Attempts)
        1.0

    GetTotalAimSamples<public>() : int =
        TotalAimSamples

    ResetTelemetry<public>() : void =
        set TotalFocusAttempts = 0
        set TotalFocusLosses = 0
        set TotalAimSamples = 0

log_aim_ch := class(log_channel):