# ============================================================================
# FILE: difficulty_mapper.verse — ELO Bracket → Bot Parameter Translation
# LOCATION: Content/ (root)
# PHASE: 4
#
# ARCHITECTURE:
#   Translates a raw ELO integer into the concrete behavioral parameters
#   stored in bot_difficulty_profile. Every Module A sub-system reads
#   these parameters to calibrate its behavior.
#
#   The mapper uses LINEAR INTERPOLATION within each bracket rather than
#   hard steps. This means a player at ELO 1150 gets slightly different
#   parameters than one at ELO 850 — the transition feels smooth, not
#   like a sudden gear shift.
#
# BRACKET TABLE (from spec §5.4):
#   ┌──────────────────┬──────────────┬───────────┬──────────┬───────────┬────────┐
#   │ Bracket          │ Reaction(ms) │ AimVar    │ PlayRate │ Aggro     │ Retgt  │
#   ├──────────────────┼──────────────┼───────────┼──────────┼───────────┼────────┤
#   │ 0-800   Beginner │ 800-600      │ 25-15     │ 0.45-0.6 │ 0         │ 0.6    │
#   │ 800-1200 Intmed  │ 600-350      │ 15-8      │ 0.6-0.85 │ 1         │ 0.4    │
#   │ 1200-1600 Adv    │ 350-200      │ 8-3       │ 0.85-1.0 │ 2         │ 0.25   │
#   │ 1600-2000 Pro    │ 200-100      │ 3-1       │ 1.0-1.25 │ 3         │ 0.15   │
#   │ 2000+    Elite   │ 100-50       │ 1-0       │ 1.25-1.5 │ 4         │ 0.10   │
#   └──────────────────┴──────────────┴───────────┴──────────┴───────────┴────────┘
#
# INTERPOLATION:
#   Within each bracket, parameters are linearly interpolated based on
#   the player's position within the bracket. For example:
#     ELO 1000 (bottom of Intermediate): parameters match bracket floor
#     ELO 1100 (midpoint): parameters are halfway between floor and ceiling
#     ELO 1199 (top): parameters approach the next bracket's floor
#
# AGGRESSION LEVELS:
#   0 = Passive: bot mostly reacts, rarely initiates
#   1 = Cautious: bot approaches carefully, builds defensively
#   2 = Balanced: bot mixes offense and defense, uses edits
#   3 = Aggressive: bot pushes hard, ramp rushes, W-keys after edits
#   4 = Berserker: bot plays through low health, frame-perfect edits
# ============================================================================
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }

# ══════════════════════════════════════════════════════════════════════════════
# DIFFICULTY MAPPER
# ══════════════════════════════════════════════════════════════════════════════
difficulty_mapper<public> := class:

    Logger<private> : log = log{Channel := log_diff_ch}

    # ══════════════════════════════════════════════════════════════════════════
    # MAP DIFFICULTY — Primary entry point
    # Takes a player ELO and writes the complete difficulty parameter set
    # into the provided bot_difficulty_profile instance.
    # Uses linear interpolation within each bracket for smooth scaling.
    # ══════════════════════════════════════════════════════════════════════════
    MapDifficulty<public>(PlayerELO : int, Profile : bot_difficulty_profile) : void =
        # Clamp ELO to valid range
        var ELO : int = PlayerELO
        if (ELO < 0):
            set ELO = 0
        if (ELO > 3000):
            set ELO = 3000

        if (ELO < 800):
            MapBeginner(ELO, Profile)
        else if (ELO < 1200):
            MapIntermediate(ELO, Profile)
        else if (ELO < 1600):
            MapAdvanced(ELO, Profile)
        else if (ELO < 2000):
            MapPro(ELO, Profile)
        else:
            MapElite(ELO, Profile)

        Logger.Print("DIFF_MAP: ELO {PlayerELO} -> Bracket:{GetBracketName(PlayerELO)} Reaction:{Profile.ReactionTimeMs}ms AimVar:{Profile.AimVariance} PlayRate:{Profile.BuildPlayRate} Aggro:{Profile.AggressionLevel}")

    # ══════════════════════════════════════════════════════════════════════════
    # BRACKET MAPPERS — Each applies interpolated parameters
    # ══════════════════════════════════════════════════════════════════════════

    # ── BEGINNER (0-800) ─────────────────────────────────────────────────────
    # Slow reactions, wide aim scatter, sluggish builds, passive behavior.
    # The bot feels like a casual player who just learned to build.
    MapBeginner<private>(ELO : int, Profile : bot_difficulty_profile) : void =
        T := CalcBracketProgress(ELO, 0, 800)

        set Profile.ReactionTimeMs     = LerpF(800.0, 600.0, T)
        set Profile.AimZOffset         = LerpF(30.0, 40.0, T)
        set Profile.AimVariance        = LerpF(25.0, 15.0, T)
        set Profile.BuildPlayRate      = LerpF(0.45, 0.60, T)
        set Profile.AggressionLevel    = 0
        set Profile.ChaseRetargetInterval = LerpF(0.65, 0.50, T)
        set Profile.NavTimeout         = 5.0

    # ── INTERMEDIATE (800-1200) ──────────────────────────────────────────────
    # Moderate reactions, tightening aim, learning to build and edit.
    # The bot uses basic edits and simple piece control.
    MapIntermediate<private>(ELO : int, Profile : bot_difficulty_profile) : void =
        T := CalcBracketProgress(ELO, 800, 1200)

        set Profile.ReactionTimeMs     = LerpF(600.0, 350.0, T)
        set Profile.AimZOffset         = LerpF(40.0, 48.0, T)
        set Profile.AimVariance        = LerpF(15.0, 8.0, T)
        set Profile.BuildPlayRate      = LerpF(0.60, 0.85, T)
        set Profile.AggressionLevel    = 1
        set Profile.ChaseRetargetInterval = LerpF(0.50, 0.35, T)
        set Profile.NavTimeout         = 4.5

    # ── ADVANCED (1200-1600) ─────────────────────────────────────────────────
    # Fast reactions, precise aim (mostly headshots), real-speed builds.
    # The bot executes complex edits, retakes, and trades.
    MapAdvanced<private>(ELO : int, Profile : bot_difficulty_profile) : void =
        T := CalcBracketProgress(ELO, 1200, 1600)

        set Profile.ReactionTimeMs     = LerpF(350.0, 200.0, T)
        set Profile.AimZOffset         = LerpF(48.0, 53.0, T)
        set Profile.AimVariance        = LerpF(8.0, 3.0, T)
        set Profile.BuildPlayRate      = LerpF(0.85, 1.0, T)
        set Profile.AggressionLevel    = 2
        set Profile.ChaseRetargetInterval = LerpF(0.35, 0.22, T)
        set Profile.NavTimeout         = 4.0

    # ── PRO (1600-2000) ──────────────────────────────────────────────────────
    # Sub-200ms reactions, sniper-level precision, faster-than-human builds.
    # The bot plays full piece control with prediction plays.
    MapPro<private>(ELO : int, Profile : bot_difficulty_profile) : void =
        T := CalcBracketProgress(ELO, 1600, 2000)

        set Profile.ReactionTimeMs     = LerpF(200.0, 100.0, T)
        set Profile.AimZOffset         = LerpF(53.0, 55.0, T)
        set Profile.AimVariance        = LerpF(3.0, 1.0, T)
        set Profile.BuildPlayRate      = LerpF(1.0, 1.25, T)
        set Profile.AggressionLevel    = 3
        set Profile.ChaseRetargetInterval = LerpF(0.22, 0.15, T)
        set Profile.NavTimeout         = 3.5

    # ── ELITE (2000+) ────────────────────────────────────────────────────────
    # Frame-perfect reactions, zero aim variance, tournament-speed builds.
    # The bot uses adaptive counter-strategies and berserker aggression.
    MapElite<private>(ELO : int, Profile : bot_difficulty_profile) : void =
        # Elite continues scaling up to ELO 3000 for the very best players
        T := CalcBracketProgress(ELO, 2000, 3000)

        set Profile.ReactionTimeMs     = LerpF(100.0, 40.0, T)
        set Profile.AimZOffset         = 55.0
        set Profile.AimVariance        = LerpF(1.0, 0.0, T)
        set Profile.BuildPlayRate      = LerpF(1.25, 1.5, T)
        set Profile.AggressionLevel    = 4
        set Profile.ChaseRetargetInterval = LerpF(0.15, 0.08, T)
        set Profile.NavTimeout         = 3.0

    # ══════════════════════════════════════════════════════════════════════════
    # QUICK PROFILE — Returns a new profile without requiring a pre-existing one
    # Convenience wrapper for callers who don't want to pre-allocate.
    # ══════════════════════════════════════════════════════════════════════════
    CreateProfileForELO<public>(PlayerELO : int) : bot_difficulty_profile =
        NewProfile := bot_difficulty_profile{}
        MapDifficulty(PlayerELO, NewProfile)
        NewProfile

    # ══════════════════════════════════════════════════════════════════════════
    # COMPARISON — Generate profiles for two ELOs to show progression
    # Used by coach: "Here's how the bot changes from your current rank to the next."
    # ══════════════════════════════════════════════════════════════════════════
    GetNextBracketPreview<public>(PlayerELO : int) : bot_difficulty_profile =
        # Find the next bracket boundary
        var TargetELO : int = PlayerELO + 200
        if (PlayerELO < 800):
            set TargetELO = 800
        else if (PlayerELO < 1200):
            set TargetELO = 1200
        else if (PlayerELO < 1600):
            set TargetELO = 1600
        else if (PlayerELO < 2000):
            set TargetELO = 2000
        else:
            set TargetELO = PlayerELO + 200

        CreateProfileForELO(TargetELO)

    # ══════════════════════════════════════════════════════════════════════════
    # BRACKET INFO — Queries for UI and coach
    # ══════════════════════════════════════════════════════════════════════════
    GetBracketName<public>(PlayerELO : int) : string =
        if (PlayerELO < 800):
            return "Beginner"
        else if (PlayerELO < 1200):
            return "Intermediate"
        else if (PlayerELO < 1600):
            return "Advanced"
        else if (PlayerELO < 2000):
            return "Pro"
        "Elite"

    GetBracketFloor<public>(PlayerELO : int) : int =
        if (PlayerELO < 800):
            return 0
        else if (PlayerELO < 1200):
            return 800
        else if (PlayerELO < 1600):
            return 1200
        else if (PlayerELO < 2000):
            return 1600
        2000

    GetBracketCeiling<public>(PlayerELO : int) : int =
        if (PlayerELO < 800):
            return 800
        else if (PlayerELO < 1200):
            return 1200
        else if (PlayerELO < 1600):
            return 1600
        else if (PlayerELO < 2000):
            return 2000
        3000

    # Progress within current bracket as a percentage [0.0, 1.0].
    # Used by HUD for a bracket progress bar.
    GetBracketProgressPct<public>(PlayerELO : int) : float =
        BracketFloor := GetBracketFloor(PlayerELO)
        Ceiling := GetBracketCeiling(PlayerELO)
        CalcBracketProgress(PlayerELO, BracketFloor, Ceiling)

    # ELO needed to reach the next bracket.
    GetELOToNextBracket<public>(PlayerELO : int) : int =
        Ceiling := GetBracketCeiling(PlayerELO)
        Remaining := Ceiling - PlayerELO
        if (Remaining < 0):
            return 0
        Remaining

    # ══════════════════════════════════════════════════════════════════════════
    # PRIVATE: Interpolation Math
    # ══════════════════════════════════════════════════════════════════════════

    # Calculate how far through a bracket the player is [0.0, 1.0].
    # 0.0 = at bracket floor, 1.0 = at bracket ceiling.
    CalcBracketProgress<private>(ELO : int, FloorELO : int, CeilingELO : int) : float =
        Range := (CeilingELO - FloorELO) * 1.0
        if (Range < 1.0):
            return 0.0
        Progress := ((ELO - FloorELO) * 1.0) / Range
        # Clamp to [0, 1]
        if (Progress < 0.0):
            return 0.0
        if (Progress > 1.0):
            return 1.0
        Progress

    # Linear interpolation between two values based on T [0, 1].
    # At T=0 returns A, at T=1 returns B.
    LerpF<private>(A : float, B : float, T : float) : float =
        A + (B - A) * T

log_diff_ch := class(log_channel):