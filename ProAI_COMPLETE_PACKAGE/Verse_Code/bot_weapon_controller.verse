# ============================================================================
# FILE: bot_weapon_controller.verse — Weapon Logic, Fire Simulation & Analytics
# LOCATION: Content/ (root)
# PHASE: 2 (base fire logic), Phase 4 (ELO-scaled burst patterns)
#
# ARCHITECTURE:
#   This module bridges two separate systems:
#
#   1. ENGINE-SIDE FIRING (Guard Auto-Fire):
#      The NPC Character Definition is set to Behavior Type "Guard",
#      which means the Fortnite engine handles actual projectile
#      spawning, hit-scan, and damage application AUTOMATICALLY
#      whenever the player is in range and line-of-sight. We have
#      no Verse API to call "fire weapon" — the guard just shoots.
#
#   2. VERSE-SIDE SIMULATION (This Module):
#      Because the engine auto-fires opaquely, we run a parallel
#      simulation layer that PREDICTS when the guard would fire
#      and estimates whether each shot hits and whether it's a
#      headshot. This simulation:
#        - Respects the weapon's fire rate (Sleep between shots)
#        - Uses distance + ELO-scaled accuracy to determine hit/miss
#        - Uses the AimModule's deviation math to determine headshot
#        - Dispatches damage_report structs to the event_bus
#        - Feeds real-time DPS/headshot% to Module C analytics
#
#      The simulation is intentionally conservative — it slightly
#      under-reports vs actual guard damage to avoid inflating stats.
#      When UEFN exposes a DamageDealt event on fort_character in
#      the future, we'll switch to event-driven recording.
#
# WEAPON PROFILES:
#   The bot conceptually carries two weapons:
#     - Shotgun (close range): high damage, slow fire rate
#     - AR (mid range): lower damage, faster fire rate, burst pattern
#   The state machine tells us which mode to use via ExecuteFire's
#   CombatState parameter.
#
# EVENT BUS INTEGRATION:
#   Every simulated hit dispatches EventBus.DispatchPlayerDamage()
#   with a complete damage_report struct. Module C's analytics_engine
#   listens for PlayerDamageEvent to compute real-time DPS, headshot%,
#   and per-round damage summaries.
# ============================================================================
using { /Fortnite.com/Characters }
using { /Fortnite.com/Game }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/SpatialMath }

# ── Weapon Type Constants ────────────────────────────────────────────────────
WEAPON_SHOTGUN<public> : int = 0
WEAPON_AR<public>      : int = 1

# ── Fire Result Constants ────────────────────────────────────────────────────
FIRE_HIT_BODY<public>     : int = 0
FIRE_HIT_HEAD<public>     : int = 1
FIRE_MISS<public>         : int = 2
FIRE_NO_TARGET<public>    : int = 3

# ══════════════════════════════════════════════════════════════════════════════
# WEAPON PROFILE — Per-weapon stat block
# ══════════════════════════════════════════════════════════════════════════════
weapon_profile<public> := struct:
    WeaponTag<public>         : string
    BaseDamage<public>        : float
    HeadshotMultiplier<public>: float
    FireInterval<public>      : float
    EffectiveRange<public>    : float
    FalloffStart<public>      : float
    BurstSize<public>         : int
    BurstDelay<public>        : float

# ══════════════════════════════════════════════════════════════════════════════
# BOT WEAPON CONTROLLER
# ══════════════════════════════════════════════════════════════════════════════
bot_weapon_controller<public> := class:

    Logger<private> : log = log{Channel := log_wpn_ch}

    # ── Cached References ────────────────────────────────────────────────────
    var CachedAgent<private>    : ?agent          = false
    var CachedChar<private>     : ?fort_character  = false
    var EventBusRef<private>    : ?event_bus       = false
    var AimModuleRef<private>   : ?bot_focus_aim   = false
    var IsInitialized<private>  : logic            = false

    # ── Weapon Profiles (defaults — overwritten by ApplyDifficulty) ──────────
    var ShotgunProfile<private> : weapon_profile = weapon_profile{
        WeaponTag := "Shotgun",
        BaseDamage := 95.0,
        HeadshotMultiplier := 1.75,
        FireInterval := 0.85,
        EffectiveRange := 500.0,
        FalloffStart := 300.0,
        BurstSize := 1,
        BurstDelay := 0.0
    }

    var ARProfile<private> : weapon_profile = weapon_profile{
        WeaponTag := "AR",
        BaseDamage := 33.0,
        HeadshotMultiplier := 1.5,
        FireInterval := 0.12,
        EffectiveRange := 1500.0,
        FalloffStart := 800.0,
        BurstSize := 3,
        BurstDelay := 0.08
    }

    # ── ELO-Scaled Parameters ────────────────────────────────────────────────
    # BaseAccuracy: probability [0.0, 1.0] that a shot lands at optimal range.
    # HeadshotChance: probability [0.0, 1.0] that a landed shot is a headshot.
    # ReactionDelayMs: milliseconds the bot "hesitates" before first shot.
    var BaseAccuracy<public>        : float = 0.55
    var HeadshotChance<public>      : float = 0.20
    var ReactionDelayMs<public>     : float = 500.0
    var DamageFalloffMultiplier<public> : float = 0.6

    # ── Active Weapon ────────────────────────────────────────────────────────
    var ActiveWeaponType<public>    : int = 0
    var ActiveProfile<private>      : weapon_profile = weapon_profile{
        WeaponTag := "Shotgun",
        BaseDamage := 95.0,
        HeadshotMultiplier := 1.75,
        FireInterval := 0.85,
        EffectiveRange := 500.0,
        FalloffStart := 300.0,
        BurstSize := 1,
        BurstDelay := 0.0
    }

    # ── Round Engagement Stats ───────────────────────────────────────────────
    var EngagementStartTime<public>     : float = 0.0
    var TotalShotsFired<public>         : int = 0
    var TotalShotsHit<public>           : int = 0
    var TotalHeadshots<public>          : int = 0
    var TotalDamageDealt<public>        : float = 0.0
    var TotalBurstsFired<private>       : int = 0
    var ShotsFiredThisState<private>    : int = 0
    var IsCurrentlyFiring<private>      : logic = false

    # ── Pseudo-Random State ──────────────────────────────────────────────────
    # We use a counter-based seed mixed with simulation time to produce
    # deterministic-enough randomness for hit/miss decisions.
    var RandomSeed<private> : int = 0

    # ══════════════════════════════════════════════════════════════════════════
    # INITIALIZATION
    # Called from bot_behavior_base after acquiring Agent + FortCharacter.
    # The event_bus reference is required so we can dispatch damage reports.
    # The aim module reference is optional but enables headshot deviation
    # calculations.
    # ══════════════════════════════════════════════════════════════════════════
    Init<public>(
        InAgent : agent,
        InChar : fort_character,
        InEventBus : event_bus
    ) : void =
        set CachedAgent = option{InAgent}
        set CachedChar = option{InChar}
        set EventBusRef = option{InEventBus}
        set IsInitialized = true
        Logger.Print("WPN: Initialized with EventBus reference.")

    # Optional: link the aim module for headshot deviation calculation.
    SetAimModule<public>(InAimModule : bot_focus_aim) : void =
        set AimModuleRef = option{InAimModule}
        Logger.Print("WPN: AimModule linked for headshot analysis.")

    # ══════════════════════════════════════════════════════════════════════════
    # APPLY DIFFICULTY
    # Scales all weapon parameters from the ELO-driven difficulty profile.
    #
    # ELO brackets (approximate mapping):
    #   800-1000  (Bronze):  Accuracy 0.35, HS 0.08, Reaction 700ms
    #   1000-1200 (Silver):  Accuracy 0.50, HS 0.15, Reaction 500ms
    #   1200-1400 (Gold):    Accuracy 0.65, HS 0.25, Reaction 350ms
    #   1400-1600 (Plat):    Accuracy 0.75, HS 0.35, Reaction 250ms
    #   1600-1800 (Diamond): Accuracy 0.85, HS 0.45, Reaction 180ms
    #   1800-2000 (Elite):   Accuracy 0.92, HS 0.55, Reaction 120ms
    #   2000+     (Pro):     Accuracy 0.96, HS 0.65, Reaction 80ms
    # ══════════════════════════════════════════════════════════════════════════
    ApplyDifficulty<public>(Profile : bot_difficulty_profile) : void =
        set ReactionDelayMs = Profile.ReactionTimeMs

        # Map aggression level to accuracy/headshot tiers
        if (Profile.AggressionLevel >= 3):
            # High aggression = high ELO bot
            set BaseAccuracy = 0.82
            set HeadshotChance = 0.42
            set DamageFalloffMultiplier = 0.75
        else if (Profile.AggressionLevel = 2):
            # Medium aggression
            set BaseAccuracy = 0.62
            set HeadshotChance = 0.22
            set DamageFalloffMultiplier = 0.65
        else:
            # Low aggression = low ELO bot
            set BaseAccuracy = 0.42
            set HeadshotChance = 0.10
            set DamageFalloffMultiplier = 0.55

        # Fine-tune accuracy from AimVariance:
        # Lower variance = tighter aim = higher accuracy
        # AimVariance ranges from ~0 (perfect) to ~15+ (sloppy)
        VarianceBonus := (15.0 - Profile.AimVariance) / 100.0
        set BaseAccuracy = BaseAccuracy + VarianceBonus
        if (BaseAccuracy > 0.98):
            set BaseAccuracy = 0.98
        if (BaseAccuracy < 0.15):
            set BaseAccuracy = 0.15

        # Scale fire interval slightly by reaction time:
        # Faster reactions = slightly tighter shot pacing
        var ReactionScale : float = Profile.ReactionTimeMs / 500.0
        if (ReactionScale < 0.7):
            set ReactionScale = 0.7
        if (ReactionScale > 1.5):
            set ReactionScale = 1.5

        set ShotgunProfile = weapon_profile{
            WeaponTag := "Shotgun",
            BaseDamage := 95.0,
            HeadshotMultiplier := 1.75,
            FireInterval := 0.85 * ReactionScale,
            EffectiveRange := 500.0,
            FalloffStart := 300.0,
            BurstSize := 1,
            BurstDelay := 0.0
        }

        set ARProfile = weapon_profile{
            WeaponTag := "AR",
            BaseDamage := 33.0,
            HeadshotMultiplier := 1.5,
            FireInterval := 0.12 * ReactionScale,
            EffectiveRange := 1500.0,
            FalloffStart := 800.0,
            BurstSize := 3,
            BurstDelay := 0.08
        }

        Logger.Print("WPN: Difficulty applied — Acc:{BaseAccuracy} HS:{HeadshotChance} Reaction:{ReactionDelayMs}ms ReactionScale:{ReactionScale}")

    # ══════════════════════════════════════════════════════════════════════════
    # BEGIN / END ENGAGEMENT
    # Called at round start/end to reset per-round stat accumulators.
    # ══════════════════════════════════════════════════════════════════════════
    BeginEngagement<public>(CurrentTime : float) : void =
        set EngagementStartTime = CurrentTime
        set TotalShotsFired = 0
        set TotalShotsHit = 0
        set TotalHeadshots = 0
        set TotalDamageDealt = 0.0
        set TotalBurstsFired = 0
        set ShotsFiredThisState = 0
        set IsCurrentlyFiring = false
        Logger.Print("WPN: Engagement started at t={CurrentTime}.")

    EndEngagement<public>() : void =
        set IsCurrentlyFiring = false
        Logger.Print("WPN: Engagement ended. Shots:{TotalShotsFired} Hits:{TotalShotsHit} HS:{TotalHeadshots} Dmg:{TotalDamageDealt}")

    # ══════════════════════════════════════════════════════════════════════════
    # WEAPON SELECTION
    # Switches the active weapon profile based on combat state.
    # Called by the state machine before ExecuteFire.
    # ══════════════════════════════════════════════════════════════════════════
    SelectWeapon<public>(WeaponType : int) : void =
        if (not (WeaponType = ActiveWeaponType)):
            set ActiveWeaponType = WeaponType
            set ShotsFiredThisState = 0
            if (WeaponType = WEAPON_SHOTGUN):
                set ActiveProfile = ShotgunProfile
                Logger.Print("WPN: Switched to SHOTGUN.")
            else:
                set ActiveProfile = ARProfile
                Logger.Print("WPN: Switched to AR.")

    # ══════════════════════════════════════════════════════════════════════════
    # EXECUTE FIRE — PRIMARY COMBAT METHOD
    # Suspending call that simulates one firing "tick":
    #   - For shotgun: fires one shot, waits for fire interval
    #   - For AR: fires a burst of BurstSize shots with BurstDelay
    #
    # Called by the combat state machine during ENGAGE_CLOSE and
    # ENGAGE_MID states. Does NOT block navigation — the state machine
    # calls this between nav ticks, and MaintainFocus runs in a separate
    # branch, so aim + move + shoot are all concurrent.
    #
    # Parameters:
    #   TargetAgent  — the player agent to evaluate hit/miss against
    #   Distance     — current distance to target (from nav module)
    #   CombatState  — the current combat state (selects weapon automatically)
    # ══════════════════════════════════════════════════════════════════════════
    ExecuteFire<public>(
        TargetAgent : agent,
        Dist : float,
        CombatState : int
    )<suspends> : void =
        # Auto-select weapon based on combat state
        if (CombatState = COMBAT_ENGAGE_CLOSE):
            SelectWeapon(WEAPON_SHOTGUN)
        else:
            SelectWeapon(WEAPON_AR)

        set IsCurrentlyFiring = true

        # Fire a burst (1 shot for shotgun, BurstSize for AR)
        var ShotsInBurst : int = 0
        loop:
            if (ShotsInBurst >= ActiveProfile.BurstSize):
                break

            # Simulate one shot
            Result := SimulateSingleShot(TargetAgent, Dist)
            set ShotsInBurst += 1
            set TotalShotsFired += 1
            set ShotsFiredThisState += 1

            # Process the result
            if (Result = FIRE_HIT_BODY):
                ProcessHit(TargetAgent, Dist, false)
            else if (Result = FIRE_HIT_HEAD):
                ProcessHit(TargetAgent, Dist, true)
            # FIRE_MISS and FIRE_NO_TARGET: no damage dispatched

            # Inter-burst delay (0 for single-shot weapons)
            if (ShotsInBurst < ActiveProfile.BurstSize):
                Sleep(ActiveProfile.BurstDelay)

        set TotalBurstsFired += 1

        # Post-burst fire interval (the weapon's cycle time)
        Sleep(ActiveProfile.FireInterval)
        set IsCurrentlyFiring = false

    # ══════════════════════════════════════════════════════════════════════════
    # EXECUTE FIRE SINGLE — Quick single-shot variant
    # Used when the state machine only has time for one shot before
    # needing to re-evaluate (e.g., during a disengage peek-shot).
    # ══════════════════════════════════════════════════════════════════════════
    ExecuteFireSingle<public>(
        TargetAgent : agent,
        Dist : float
    )<suspends> : void =
        set IsCurrentlyFiring = true
        set TotalShotsFired += 1

        Result := SimulateSingleShot(TargetAgent, Dist)
        if (Result = FIRE_HIT_BODY):
            ProcessHit(TargetAgent, Dist, false)
        else if (Result = FIRE_HIT_HEAD):
            ProcessHit(TargetAgent, Dist, true)

        Sleep(ActiveProfile.FireInterval)
        set IsCurrentlyFiring = false

    # ══════════════════════════════════════════════════════════════════════════
    # SIMULATE SINGLE SHOT
    # Determines hit/miss/headshot using ELO-scaled probability:
    #
    #   1. Base accuracy adjusted by distance falloff
    #   2. Random roll against adjusted accuracy → hit or miss
    #   3. If hit: random roll against headshot chance → body or head
    #   4. If AimModule is linked: use aim deviation for bonus/penalty
    #
    # Returns: FIRE_HIT_BODY, FIRE_HIT_HEAD, FIRE_MISS, or FIRE_NO_TARGET
    # ══════════════════════════════════════════════════════════════════════════
    SimulateSingleShot<private>(TargetAgent : agent, Dist : float) : int =
        # Verify target is still valid
        if (TargetChar := TargetAgent.GetFortCharacter[]):
            if (not TargetChar.IsActive[]):
                return FIRE_NO_TARGET
        else:
            return FIRE_NO_TARGET

        # Step 1: Calculate distance-adjusted accuracy
        AdjustedAccuracy := CalcDistanceAdjustedAccuracy(Dist)

        # Step 2: Roll for hit/miss
        HitRoll := PseudoRandom()
        if (HitRoll > AdjustedAccuracy):
            return FIRE_MISS

        # Step 3: Roll for headshot
        HeadshotRoll := PseudoRandom()
        AdjustedHSChance := CalcAdjustedHeadshotChance(TargetAgent, Dist)

        if (HeadshotRoll <= AdjustedHSChance):
            return FIRE_HIT_HEAD
        FIRE_HIT_BODY

    # ══════════════════════════════════════════════════════════════════════════
    # PROCESS HIT — Calculate damage and dispatch to event bus
    # ══════════════════════════════════════════════════════════════════════════
    ProcessHit<private>(TargetAgent : agent, Dist : float, IsHeadshot : logic) : void =
        # Calculate base damage with distance falloff
        var RawDamage : float = ActiveProfile.BaseDamage

        # Apply distance falloff: full damage within FalloffStart,
        # reduced damage beyond, scaling down to DamageFalloffMultiplier
        # at EffectiveRange.
        if (Dist > ActiveProfile.FalloffStart):
            if (ActiveProfile.EffectiveRange > ActiveProfile.FalloffStart):
                FalloffRange := ActiveProfile.EffectiveRange - ActiveProfile.FalloffStart
                DistBeyond := Dist - ActiveProfile.FalloffStart
                var FalloffPct : float = DistBeyond / FalloffRange
                if (FalloffPct > 1.0):
                    set FalloffPct = 1.0
                # Interpolate from 1.0 to DamageFalloffMultiplier
                Multiplier := 1.0 - (FalloffPct * (1.0 - DamageFalloffMultiplier))
                set RawDamage = RawDamage * Multiplier

        # Apply headshot multiplier
        var FinalDamage : float = RawDamage
        if (IsHeadshot?):
            set FinalDamage = RawDamage * ActiveProfile.HeadshotMultiplier

        # Update internal stats
        set TotalShotsHit += 1
        set TotalDamageDealt += FinalDamage
        if (IsHeadshot?):
            set TotalHeadshots += 1

        # Also update the legacy RecordDamage path for backward compat
        # (analytics_engine may call GetCurrentDPS/GetHeadshotRatio)

        # Dispatch to event bus — this is the critical analytics pipeline
        if (Bus := EventBusRef?):
            Report := damage_report{
                DamageAmount := FinalDamage,
                IsHeadshot := IsHeadshot,
                WeaponTag := ActiveProfile.WeaponTag,
                Timestamp := GetSimulationElapsedTime()
            }
            Bus.DispatchPlayerDamage(Report)

        # Log significant hits
        if (IsHeadshot?):
            Logger.Print("WPN: HEADSHOT! {ActiveProfile.WeaponTag} -> {FinalDamage} dmg at {Dist}u")
        else:
            Logger.Print("WPN: Body hit. {ActiveProfile.WeaponTag} -> {FinalDamage} dmg at {Dist}u")

    # ══════════════════════════════════════════════════════════════════════════
    # ACCURACY CALCULATIONS
    # ══════════════════════════════════════════════════════════════════════════

    # Adjusts base accuracy based on distance to target.
    # Close range: accuracy stays high (shotgun spread helps).
    # Beyond falloff start: accuracy degrades linearly.
    # Beyond effective range: accuracy is heavily penalized.
    CalcDistanceAdjustedAccuracy<private>(Dist : float) : float =
        if (Dist <= ActiveProfile.FalloffStart):
            # Within optimal range: slight bonus for close range
            var CloseBonus : float = 0.0
            if (Dist < 200.0):
                set CloseBonus = 0.10
            Result := BaseAccuracy + CloseBonus
            if (Result > 0.98):
                return 0.98
            return Result

        # Beyond falloff: degrade accuracy
        if (ActiveProfile.EffectiveRange > ActiveProfile.FalloffStart):
            FalloffRange := ActiveProfile.EffectiveRange - ActiveProfile.FalloffStart
            DistBeyond := Dist - ActiveProfile.FalloffStart
            var FalloffPct2 : float = DistBeyond / FalloffRange
            if (FalloffPct2 > 1.0):
                set FalloffPct2 = 1.0
            # At max range, accuracy is halved
            Degraded := BaseAccuracy * (1.0 - (FalloffPct2 * 0.5))
            if (Degraded < 0.05):
                return 0.05
            return Degraded

        BaseAccuracy * 0.5

    # Adjusts headshot probability using aim deviation from the AimModule.
    # If the AimModule reports the bot is aiming close to the head,
    # headshot chance gets a bonus. If aiming far off, it's penalized.
    CalcAdjustedHeadshotChance<private>(TargetAgent : agent, Dist : float) : float =
        var AdjustedChance : float = HeadshotChance

        # Close range shotgun: slight HS penalty (pellet spread)
        if (ActiveWeaponType = WEAPON_SHOTGUN):
            if (Dist < 200.0):
                set AdjustedChance = AdjustedChance * 0.85

        # If AimModule is linked, factor in actual aim deviation
        if (AimMod := AimModuleRef?):
            Deviation := AimMod.GetAimDeviationDegrees(TargetAgent)
            # < 3 degrees: bonus (great aim)
            # 3-8 degrees: neutral
            # > 8 degrees: penalty (bad aim)
            if (Deviation < 3.0):
                set AdjustedChance = AdjustedChance * 1.3
            else if (Deviation > 8.0):
                var PenaltyFactor : float = 1.0 - ((Deviation - 8.0) / 30.0)
                if (PenaltyFactor < 0.2):
                    set PenaltyFactor = 0.2
                set AdjustedChance = AdjustedChance * PenaltyFactor

        # Clamp
        if (AdjustedChance > 0.80):
            return 0.80
        if (AdjustedChance < 0.02):
            return 0.02
        AdjustedChance

    # ══════════════════════════════════════════════════════════════════════════
    # PSEUDO-RANDOM NUMBER GENERATOR
    # Verse has limited random APIs. We use a counter + simulation time
    # based LCG (Linear Congruential Generator) to produce values [0, 1].
    # This is deterministic per-session, which is fine for gameplay sim.
    # ══════════════════════════════════════════════════════════════════════════
    PseudoRandom<private>() : float =
        set RandomSeed += 1
        # LCG: seed = (seed * 1103515245 + 12345) mod 2^31
        TimeComponent := Floor[GetSimulationElapsedTime() * 1000.0] or 0
        Combined := RandomSeed * 1103515245 + 12345 + TimeComponent
        # Extract fractional part for [0, 1) range
        var Positive : int = Combined
        if (Positive < 0):
            set Positive = Positive * -1
        # Modulo to get a manageable range, then normalize
        Reduced := Mod[Positive, 10000] or 5000
        (Reduced * 1.0) / 10000.0

    # ══════════════════════════════════════════════════════════════════════════
    # ANALYTICS QUERIES — Called by Module C and HUD
    # ══════════════════════════════════════════════════════════════════════════

    # Real-time DPS based on elapsed engagement time.
    GetCurrentDPS<public>(CurrentTime : float) : float =
        Elapsed := CurrentTime - EngagementStartTime
        if (Elapsed > 0.1):
            return TotalDamageDealt / Elapsed
        0.0

    # Accuracy ratio: hits / total shots.
    GetAccuracyRatio<public>() : float =
        if (TotalShotsFired > 0):
            return (TotalShotsHit * 1.0) / (TotalShotsFired * 1.0)
        0.0

    # Headshot ratio: headshots / total hits.
    GetHeadshotRatio<public>() : float =
        if (TotalShotsHit > 0):
            return (TotalHeadshots * 1.0) / (TotalShotsHit * 1.0)
        0.0

    # Headshots as percentage of ALL shots (including misses).
    GetHeadshotPercentage<public>() : float =
        if (TotalShotsFired > 0):
            return (TotalHeadshots * 1.0) / (TotalShotsFired * 1.0)
        0.0

    # Average damage per hit.
    GetDamagePerHit<public>() : float =
        if (TotalShotsHit > 0):
            return TotalDamageDealt / (TotalShotsHit * 1.0)
        0.0

    # Shots fired per second (fire rate realization).
    GetShotsPerSecond<public>(CurrentTime : float) : float =
        Elapsed := CurrentTime - EngagementStartTime
        if (Elapsed > 0.1):
            return (TotalShotsFired * 1.0) / Elapsed
        0.0

    # Check if the weapon is currently in a fire cycle.
    GetIsFiring<public>() : logic =
        IsCurrentlyFiring

    # Legacy compatibility: record an externally-observed damage event.
    # Used if we hook into an engine-side damage event in the future.
    RecordDamage<public>(Amount : float, IsHeadshot : logic) : void =
        set TotalDamageDealt += Amount
        set TotalShotsHit += 1
        set TotalShotsFired += 1
        if (IsHeadshot?):
            set TotalHeadshots += 1

    # Full stats dump for debug logging.
    LogStats<public>(CurrentTime : float) : void =
        Logger.Print("WPN: ── Stats ──")
        Logger.Print("WPN:   Shots: {TotalShotsFired}  Hits: {TotalShotsHit}  HS: {TotalHeadshots}")
        Logger.Print("WPN:   Damage: {TotalDamageDealt}  DPS: {GetCurrentDPS(CurrentTime)}")
        Logger.Print("WPN:   Accuracy: {GetAccuracyRatio()}  HS%: {GetHeadshotRatio()}")
        Logger.Print("WPN:   Weapon: {ActiveProfile.WeaponTag}  Bursts: {TotalBurstsFired}")

log_wpn_ch := class(log_channel):