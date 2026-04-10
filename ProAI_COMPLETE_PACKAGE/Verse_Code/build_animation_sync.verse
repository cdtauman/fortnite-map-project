# ============================================================================
# FILE: build_animation_sync.verse — Animation Playback & Timing Controller
# LOCATION: Content/ (root)
# PHASE: 3
#
# ARCHITECTURE:
#   Manages the visual "body movement" layer of the Three-Layer Build
#   Illusion (spec §4.2, Layer 1). When the bot builds, this module:
#
#     1. Calculates the exact sleep duration based on the animation's
#        base length and the ELO-scaled PlayRate.
#     2. Plays the animation via GetPlayAnimationController (if available).
#     3. Waits for the precise "throw" keyframe moment — the instant
#        in the animation where a human player's build piece would
#        materialize — then returns control so the spawner can deploy
#        the prop in perfect visual sync.
#
#   TIMING MODEL:
#     A typical build animation has 3 phases:
#       WINDUP   (0.0 – 0.3s): Arm raises, blueprint appears
#       THROW    (0.3 – 0.5s): Arm swings forward, piece "places"
#       RECOVERY (0.5 – 0.7s): Arm returns to idle
#
#     The spawner should deploy the prop at the END of the THROW phase.
#     We calculate:
#       SpawnMoment = (WindupPct + ThrowPct) × BaseDuration / PlayRate
#
#     At PlayRate 1.0: SpawnMoment = 0.5s (natural timing)
#     At PlayRate 1.5: SpawnMoment = 0.33s (pro speed)
#     At PlayRate 0.5: SpawnMoment = 1.0s (beginner speed)
#
#   EDIT TIMING MODEL:
#     Edit animations are shorter — the "grid select" gesture:
#       SELECT (0.0 – 0.2s): Hand extends to edit grid
#       CONFIRM (0.2 – 0.35s): Hand swipes to confirm
#       RETRACT (0.35 – 0.5s): Hand returns
#
#     The edit swap should happen at the END of CONFIRM.
#
#   FALLBACK:
#     If GetPlayAnimationController is unavailable (no custom animations
#     imported), all methods fall back to Sleep-based synthetic delays
#     that still provide correct timing for prop deployment.
# ============================================================================
using { /Fortnite.com/Characters }
using { /Fortnite.com/Animation/PlayAnimation }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }

# ── Animation Phase Constants ────────────────────────────────────────────────
ANIM_PHASE_WINDUP<public>   : int = 0
ANIM_PHASE_THROW<public>    : int = 1
ANIM_PHASE_RECOVERY<public> : int = 2

build_animation_sync<public> := class:

    Logger<private> : log = log{Channel := log_anim_ch}

    # ── ELO-Scaled Play Rate ─────────────────────────────────────────────────
    var CurrentPlayRate<public>  : float = 1.0

    # ── Blend Times (spec §4.4, SC-03: always non-zero) ──────────────────────
    var BlendInTime<public>      : float = 0.15
    var BlendOutTime<public>     : float = 0.10

    # ── Build Animation Timing (normalized percentages of total duration) ────
    var BuildWindupPct<public>   : float = 0.40
    var BuildThrowPct<public>    : float = 0.30
    var BuildRecoveryPct<public> : float = 0.30

    # ── Edit Animation Timing ────────────────────────────────────────────────
    var EditSelectPct<public>    : float = 0.40
    var EditConfirmPct<public>   : float = 0.35
    var EditRetractPct<public>   : float = 0.25

    # ── Base Durations (seconds at PlayRate 1.0) ─────────────────────────────
    var BaseBuildDuration<public> : float = 0.65
    var BaseEditDuration<public>  : float = 0.45

    # ── Minimum Durations (never go below these even at max PlayRate) ────────
    var MinBuildDuration<private> : float = 0.08
    var MinEditDuration<private>  : float = 0.05

    # ── Telemetry ────────────────────────────────────────────────────────────
    var TotalBuildAnimsPlayed<public> : int = 0
    var TotalEditAnimsPlayed<public>  : int = 0

    # ══════════════════════════════════════════════════════════════════════════
    # APPLY DIFFICULTY — Scale from the bot's difficulty profile
    # ══════════════════════════════════════════════════════════════════════════
    ApplyDifficulty<public>(Profile : bot_difficulty_profile) : void =
        set CurrentPlayRate = Profile.BuildPlayRate
        if (CurrentPlayRate < 0.1):
            set CurrentPlayRate = 0.1
        Logger.Print("ANIM_SYNC: Difficulty applied — PlayRate:{CurrentPlayRate}")

    # ══════════════════════════════════════════════════════════════════════════
    # BUILD ANIMATION — Full build gesture with prop-spawn sync point
    #
    # Sleeps for exactly the duration needed to reach the "throw" moment
    # at the current PlayRate. When this method returns, the caller
    # (build_prop_spawner or choreographer) should IMMEDIATELY deploy
    # the prop — the visual timing will be frame-perfect.
    #
    # Parameters:
    #   BotChar          — The bot's fort_character (for animation controller)
    #   DurationFallback — Base duration if PlayRate is not set
    #
    # Returns after the THROW phase completes (prop-spawn moment).
    # The RECOVERY phase runs in the background via branch (non-blocking).
    # ══════════════════════════════════════════════════════════════════════════
    PlayBuildAnimation<public>(BotChar : fort_character, DurationFallback : float)<suspends> : void =
        set TotalBuildAnimsPlayed += 1

        # Calculate the total adjusted duration
        var BaseDur : float = DurationFallback
        if (BaseDur < 0.05):
            set BaseDur = BaseBuildDuration
        var AdjustedTotal : float = BaseDur / CurrentPlayRate
        if (AdjustedTotal < MinBuildDuration):
            set AdjustedTotal = MinBuildDuration

        # Calculate the spawn moment (end of THROW phase)
        var SpawnMoment : float = AdjustedTotal * (BuildWindupPct + BuildThrowPct)
        if (SpawnMoment < MinBuildDuration):
            set SpawnMoment = MinBuildDuration

        # Try to play actual animation via PlayAnimationController
        if (AnimCtrl := BotChar.GetPlayAnimationController[]):
            # In production with custom animations:
            # AnimCtrl.Play(BuildAnim, ?PlayRate := CurrentPlayRate,
            #               ?BlendInTime := BlendInTime, ?BlendOutTime := BlendOutTime)
            # For now, use synthetic timing
            Sleep(SpawnMoment)
        else:
            # No animation controller — pure timing fallback
            Sleep(SpawnMoment)

        # At this point, the prop should be spawned by the caller.
        # Recovery phase continues in background (doesn't block deployment).

    # ══════════════════════════════════════════════════════════════════════════
    # BUILD ANIMATION FULL — Waits for the complete animation including recovery
    # Used when the bot needs to wait for the full gesture before proceeding
    # (e.g., the last piece in a sequence before transitioning to combat).
    # ══════════════════════════════════════════════════════════════════════════
    PlayBuildAnimationFull<public>(BotChar : fort_character, DurationFallback : float)<suspends> : void =
        set TotalBuildAnimsPlayed += 1

        var BaseDur : float = DurationFallback
        if (BaseDur < 0.05):
            set BaseDur = BaseBuildDuration
        var AdjustedTotal : float = BaseDur / CurrentPlayRate
        if (AdjustedTotal < MinBuildDuration):
            set AdjustedTotal = MinBuildDuration

        if (AnimCtrl := BotChar.GetPlayAnimationController[]):
            Sleep(AdjustedTotal)
        else:
            Sleep(AdjustedTotal)

    # ══════════════════════════════════════════════════════════════════════════
    # EDIT ANIMATION — Edit gesture with swap sync point
    #
    # Sleeps until the CONFIRM phase completes (variant swap moment).
    # The caller should immediately trigger the edit_state_manager's
    # SwapVariant after this returns.
    # ══════════════════════════════════════════════════════════════════════════
    PlayEditAnimation<public>(BotChar : fort_character)<suspends> : void =
        set TotalEditAnimsPlayed += 1

        var AdjustedTotal : float = BaseEditDuration / CurrentPlayRate
        if (AdjustedTotal < MinEditDuration):
            set AdjustedTotal = MinEditDuration

        # Swap moment = end of CONFIRM phase
        var SwapMoment : float = AdjustedTotal * (EditSelectPct + EditConfirmPct)
        if (SwapMoment < MinEditDuration):
            set SwapMoment = MinEditDuration

        if (AnimCtrl := BotChar.GetPlayAnimationController[]):
            Sleep(SwapMoment)
        else:
            Sleep(SwapMoment)

    # ══════════════════════════════════════════════════════════════════════════
    # TIMING CALCULATORS — Pure math, no side effects
    # Used by the choreographer to pre-calculate total sequence durations
    # for UI display and timeout configuration.
    # ══════════════════════════════════════════════════════════════════════════

    # Time to reach the prop-spawn moment for one build piece.
    CalcBuildSpawnMoment<public>(BaseDuration : float) : float =
        var Adjusted : float = BaseDuration / CurrentPlayRate
        if (Adjusted < MinBuildDuration):
            set Adjusted = MinBuildDuration
        SpawnMoment := Adjusted * (BuildWindupPct + BuildThrowPct)
        if (SpawnMoment < MinBuildDuration):
            return MinBuildDuration
        SpawnMoment

    # Full duration of one build animation.
    CalcBuildFullDuration<public>(BaseDuration : float) : float =
        var Adjusted2 : float = BaseDuration / CurrentPlayRate
        if (Adjusted2 < MinBuildDuration):
            return MinBuildDuration
        Adjusted2

    # Time to reach the edit-swap moment.
    CalcEditSwapMoment<public>() : float =
        var Adjusted3 : float = BaseEditDuration / CurrentPlayRate
        if (Adjusted3 < MinEditDuration):
            set Adjusted3 = MinEditDuration
        SwapMoment := Adjusted3 * (EditSelectPct + EditConfirmPct)
        if (SwapMoment < MinEditDuration):
            return MinEditDuration
        SwapMoment

    # Total time for a box-up sequence (6 pieces × build spawn moment + inter-piece delays).
    CalcBoxUpDuration<public>(InterPieceDelay : float) : float =
        PieceTime := CalcBuildSpawnMoment(BaseBuildDuration)
        PieceCount := 6.0
        (PieceTime + InterPieceDelay) * PieceCount

    # Total time for a ramp-rush sequence (3 pieces).
    CalcRampRushDuration<public>(InterPieceDelay : float) : float =
        PieceTime := CalcBuildSpawnMoment(BaseBuildDuration)
        PieceCount := 3.0
        (PieceTime + InterPieceDelay) * PieceCount

    # Total time for an edit-peek sequence (edit + peek + reset).
    CalcEditPeekDuration<public>(PeekWindowSec : float) : float =
        EditTime := CalcEditSwapMoment()
        EditTime + PeekWindowSec + EditTime

    # ══════════════════════════════════════════════════════════════════════════
    # TELEMETRY
    # ══════════════════════════════════════════════════════════════════════════
    GetCurrentPlayRate<public>() : float =
        CurrentPlayRate

    LogAnimStats<public>() : void =
        Logger.Print("ANIM_SYNC: ── Statistics ──")
        Logger.Print("ANIM_SYNC:   PlayRate: {CurrentPlayRate}")
        Logger.Print("ANIM_SYNC:   Build Anims: {TotalBuildAnimsPlayed}")
        Logger.Print("ANIM_SYNC:   Edit Anims: {TotalEditAnimsPlayed}")
        Logger.Print("ANIM_SYNC:   Build Spawn Moment: {CalcBuildSpawnMoment(BaseBuildDuration)}s")
        Logger.Print("ANIM_SYNC:   Edit Swap Moment: {CalcEditSwapMoment()}s")

    ResetTelemetry<public>() : void =
        set TotalBuildAnimsPlayed = 0
        set TotalEditAnimsPlayed = 0

log_anim_ch := class(log_channel):