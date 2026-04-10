# ============================================================================
# FILE: bot_difficulty_profile.verse — ELO-Driven Parameter Container
# LOCATION: Content/ (root)
# PHASE: 2 (struct defined), Phase 4 (values written by difficulty_mapper)
#
# ARCHITECTURE:
#   This is the single data contract between Module C (which writes the
#   values based on ELO) and Module A + B (which read the values to
#   calibrate bot behavior). Every sub-system in the bot reads from
#   one shared instance of this class:
#
#     bot_behavior_base     → reads all fields at init, hot-reloads mid-fight
#     bot_navigation        → reads ChaseRetargetInterval, NavTimeout
#     bot_focus_aim         → reads AimZOffset, AimVariance
#     bot_weapon_controller → reads ReactionTimeMs, AggressionLevel
#     bot_combat_state_machine → reads AggressionLevel, ChaseRetargetInterval
#     build_sequence_choreographer → reads BuildPlayRate
#     build_animation_sync  → reads BuildPlayRate
#     edit_state_manager    → reads BuildPlayRate (edit speed scaling)
#
#   The difficulty_mapper writes all fields simultaneously after each
#   round via MapDifficulty(ELO, Profile). The analytics_engine triggers
#   this write at EndRoundTracking.
#
# FIELD RANGES (from spec §5.4):
#   ReactionTimeMs:       40.0 (Elite) → 800.0 (Beginner)
#   AimZOffset:           30.0 (chest) → 55.0 (perfect head)
#   AimVariance:          0.0 (perfect) → 25.0 (very sloppy)
#   BuildPlayRate:        0.45 (very slow) → 1.5 (tournament speed)
#   AggressionLevel:      0 (passive) → 4 (berserker)
#   ChaseRetargetInterval: 0.08 (frame-perfect) → 0.65 (sluggish)
#   NavTimeout:           3.0 (tight) → 5.0 (generous)
#   EditSpeedMultiplier:  0.5 (slow edits) → 2.0 (instant edits)
#   StrafeIntensity:      0.0 (stands still) → 1.0 (maximum juke)
#   BuildProbability:     0.0 (never builds) → 1.0 (always builds when able)
# ============================================================================
using { /Verse.org/Simulation }

bot_difficulty_profile<public> := class:

    # ── Core Combat Parameters ───────────────────────────────────────────────
    # Time before the bot "notices" the player and begins acting (ms).
    # Lower = faster reactions = harder bot.
    var ReactionTimeMs<public>        : float = 500.0

    # Vertical offset from center-mass for aim targeting (Unreal units).
    # 55.0 = perfect head height. 30.0 = chest/belly hits.
    var AimZOffset<public>            : float = 55.0

    # Random scatter applied to the calculated aim point (Unreal units).
    # 0.0 = pixel-perfect. 25.0 = shots land all over the body.
    var AimVariance<public>           : float = 10.0

    # ── Build & Edit Parameters ──────────────────────────────────────────────
    # Animation playback speed multiplier for build/edit sequences.
    # 1.0 = real-time. 1.5 = faster than human. 0.5 = very slow.
    var BuildPlayRate<public>         : float = 0.85

    # Multiplier for edit animation speed specifically.
    # Separate from BuildPlayRate so edits can scale independently.
    var EditSpeedMultiplier<public>   : float = 1.0

    # Probability [0.0, 1.0] that the bot will build when the combat
    # state machine considers it appropriate. 0.0 = never builds.
    var BuildProbability<public>      : float = 0.5

    # ── Movement Parameters ──────────────────────────────────────────────────
    # How often (seconds) the bot re-evaluates its navigation target.
    # Lower = more responsive pathfinding = harder to juke.
    var ChaseRetargetInterval<public> : float = 0.3

    # Maximum seconds a single NavigateTo call runs before timeout.
    var NavTimeout<public>            : float = 4.0

    # Strafe intensity during close-range combat [0.0, 1.0].
    # 0.0 = runs straight at you. 1.0 = maximum lateral movement.
    var StrafeIntensity<public>       : float = 0.5

    # ── Behavior Parameters ──────────────────────────────────────────────────
    # Overall aggression tier controlling state machine decisions.
    # 0 = passive (mostly reacts, rarely initiates)
    # 1 = cautious (approaches carefully, builds defensively)
    # 2 = balanced (mixes offense and defense, uses edits)
    # 3 = aggressive (pushes hard, ramp rushes, W-keys after edits)
    # 4 = berserker (plays through low health, frame-perfect edits)
    var AggressionLevel<public>       : int = 1

    # ══════════════════════════════════════════════════════════════════════════
    # RESET — Restore all parameters to mid-range defaults.
    # Called between sessions or when the analytics system detects
    # corrupt profile data.
    # ══════════════════════════════════════════════════════════════════════════
    ResetToDefault<public>() : void =
        set ReactionTimeMs = 500.0
        set AimZOffset = 55.0
        set AimVariance = 10.0
        set BuildPlayRate = 0.85
        set EditSpeedMultiplier = 1.0
        set BuildProbability = 0.5
        set ChaseRetargetInterval = 0.3
        set NavTimeout = 4.0
        set StrafeIntensity = 0.5
        set AggressionLevel = 1

    # ══════════════════════════════════════════════════════════════════════════
    # COPY — Create a snapshot of the current profile for comparison.
    # Used by the coach to show "before vs after" difficulty changes.
    # ══════════════════════════════════════════════════════════════════════════
    CopyTo<public>(Target : bot_difficulty_profile) : void =
        set Target.ReactionTimeMs = ReactionTimeMs
        set Target.AimZOffset = AimZOffset
        set Target.AimVariance = AimVariance
        set Target.BuildPlayRate = BuildPlayRate
        set Target.EditSpeedMultiplier = EditSpeedMultiplier
        set Target.BuildProbability = BuildProbability
        set Target.ChaseRetargetInterval = ChaseRetargetInterval
        set Target.NavTimeout = NavTimeout
        set Target.StrafeIntensity = StrafeIntensity
        set Target.AggressionLevel = AggressionLevel

    # ══════════════════════════════════════════════════════════════════════════
    # VALIDATE — Clamp all fields to safe ranges.
    # Called after MapDifficulty to catch any interpolation overshoots.
    # ══════════════════════════════════════════════════════════════════════════
    Validate<public>() : void =
        set ReactionTimeMs = ClampF(ReactionTimeMs, 20.0, 1000.0)
        set AimZOffset = ClampF(AimZOffset, 0.0, 80.0)
        set AimVariance = ClampF(AimVariance, 0.0, 40.0)
        set BuildPlayRate = ClampF(BuildPlayRate, 0.1, 3.0)
        set EditSpeedMultiplier = ClampF(EditSpeedMultiplier, 0.2, 3.0)
        set BuildProbability = ClampF(BuildProbability, 0.0, 1.0)
        set ChaseRetargetInterval = ClampF(ChaseRetargetInterval, 0.05, 1.0)
        set NavTimeout = ClampF(NavTimeout, 1.0, 10.0)
        set StrafeIntensity = ClampF(StrafeIntensity, 0.0, 1.0)
        if (AggressionLevel < 0):
            set AggressionLevel = 0
        if (AggressionLevel > 4):
            set AggressionLevel = 4

    # ══════════════════════════════════════════════════════════════════════════
    # COMPARISON — Check if two profiles differ meaningfully.
    # Used by bot_behavior_base to decide whether to hot-reload mid-fight.
    # ══════════════════════════════════════════════════════════════════════════
    DiffersFrom<public>(Other : bot_difficulty_profile) : logic =
        if (not (AggressionLevel = Other.AggressionLevel)):
            return true
        if (AbsF(ReactionTimeMs - Other.ReactionTimeMs) > 10.0):
            return true
        if (AbsF(AimVariance - Other.AimVariance) > 1.0):
            return true
        if (AbsF(BuildPlayRate - Other.BuildPlayRate) > 0.05):
            return true
        false

    # ══════════════════════════════════════════════════════════════════════════
    # DESCRIPTION — Human-readable summary for logging and coach.
    # ══════════════════════════════════════════════════════════════════════════
    GetDescription<public>() : string =
        "Reaction:{ReactionTimeMs}ms Aim:{AimZOffset}+/-{AimVariance} Build:{BuildPlayRate}x Edit:{EditSpeedMultiplier}x Aggro:{AggressionLevel} Strafe:{StrafeIntensity}"

    # ── Private Utilities ────────────────────────────────────────────────────
    ClampF<private>(Value : float, MinVal : float, MaxVal : float)<transacts> : float =
        if (Value < MinVal):
            return MinVal
        if (Value > MaxVal):
            return MaxVal
        Value

    AbsF<private>(Value : float)<transacts> : float =
        if (Value < 0.0):
            return Value * -1.0
        Value