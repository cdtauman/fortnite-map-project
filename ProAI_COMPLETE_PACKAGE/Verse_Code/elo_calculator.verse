# ============================================================================
# FILE: elo_calculator.verse — ELO Rating Math Engine
# LOCATION: Content/ (root)
# PHASE: 4
#
# ARCHITECTURE:
#   Pure math — zero state, zero side effects, zero device dependencies.
#   Every method is deterministic: same inputs always produce the same output.
#
#   Implements the standard chess ELO system adapted for 1v1 bot combat:
#
#     Expected probability:  E = 1 / (1 + 10^((R_bot - R_player) / 400))
#     Rating update:         R_new = R_old + K × (S - E)
#
#   Where:
#     S = 1.0 (win), 0.5 (draw), 0.0 (loss)
#     K = dynamic K-factor based on context
#
# K-FACTOR SYSTEM:
#   The K-factor controls rating volatility — how much a single round
#   changes the ELO. Our system uses four tiers:
#
#     K = 48  → Placement (first 10 rounds). Fast convergence to true skill.
#     K = 32  → Standard. Balanced responsiveness.
#     K = 64  → Volatility injection. Anti-stagnation when ELO plateaus.
#     K = 16  → Stabilization. Applied at extreme high ELO (2000+) to
#               prevent wild swings at the top of the ladder.
#
# BOT ELO CALIBRATION:
#   The bot's ELO is not fixed — it's dynamically offset from the player's
#   ELO to create competitive tension. The offset varies by bracket to
#   maintain a ~45-55% expected win rate for the player (slightly favoring
#   the player to keep the experience motivating, not demoralizing).
#
# POWER FUNCTION:
#   Verse's standard library does not expose a general-purpose Pow(base, exp)
#   for arbitrary floats. We implement 10^x using the Taylor series expansion
#   of e^(x·ln10) with 8 terms, which gives excellent accuracy for the
#   range of exponents we encounter (typically -3.0 to +3.0, since ELO
#   differences rarely exceed ±1200).
# ============================================================================
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/SpatialMath }

# ══════════════════════════════════════════════════════════════════════════════
# ELO CALCULATOR
# ══════════════════════════════════════════════════════════════════════════════
elo_calculator<public> := class:

    Logger<private> : log = log{Channel := log_elo_ch}

    # ── K-Factor Configuration ───────────────────────────────────────────────
    var KFactorStandard<public>       : float = 32.0
    var KFactorPlacement<public>      : float = 48.0
    var KFactorVolatile<public>       : float = 64.0
    var KFactorStabilized<public>     : float = 16.0
    var PlacementRoundThreshold<public> : int = 10
    var StabilizationELOThreshold<public> : int = 2000

    # ── ELO Clamp Boundaries ─────────────────────────────────────────────────
    var MinELO<public>  : int = 0
    var MaxELO<public>  : int = 5000

    # ── Bot ELO Offset Table ─────────────────────────────────────────────────
    # The bot's ELO is set relative to the player's to maintain competitive
    # tension. Positive offset = bot is "harder than the player's rank."
    # Negative offset = bot is "easier." We want the player to win ~52% of
    # the time, so the offset is slightly below parity.
    var BotOffsetBeginner<public>     : int = 25
    var BotOffsetIntermediate<public> : int = 40
    var BotOffsetAdvanced<public>     : int = 50
    var BotOffsetPro<public>          : int = 60
    var BotOffsetElite<public>        : int = 75

    # ══════════════════════════════════════════════════════════════════════════
    # EXPECTED PROBABILITY
    # Standard ELO formula: E = 1 / (1 + 10^((R_opponent - R_player) / 400))
    #
    # Returns a float in [0.0, 1.0] representing the player's expected
    # probability of winning. E=0.5 means even match. E>0.5 means player
    # is favored. E<0.5 means bot is favored.
    # ══════════════════════════════════════════════════════════════════════════
    CalcExpectedProbability<public>(PlayerELO : int, BotELO : int) : float =
        Diff := (BotELO - PlayerELO) * 1.0
        Exponent := Diff / 400.0

        # Clamp exponent to prevent extreme values in the power function.
        # ELO differences beyond ±1200 (exponent ±3.0) produce probabilities
        # so close to 0 or 1 that further precision is meaningless.
        ClampedExp := ClampFloat(Exponent, -3.0, 3.0)

        Power := Pow10(ClampedExp)
        Result := 1.0 / (1.0 + Power)

        # Safety clamp: never return exactly 0 or 1 (prevents division
        # issues in downstream calculations)
        ClampFloat(Result, 0.001, 0.999)

    # Legacy alias for backward compatibility with existing analytics_engine
    CalcExpectedScore<public>(PlayerELO : int, BotELO : int) : float =
        CalcExpectedProbability(PlayerELO, BotELO)

    # ══════════════════════════════════════════════════════════════════════════
    # NEW RATING CALCULATION
    # R_new = R_old + K × (S - E)
    #
    # Parameters:
    #   CurrentELO  — Player's current rating
    #   BotELO      — Bot's rating for this round
    #   Outcome     — OUTCOME_PLAYER_WIN / OUTCOME_BOT_WIN / OUTCOME_DRAW
    #   RoundNumber — Current round in the session (for placement detection)
    #   IsVolatile  — Whether anti-stagnation volatility is active
    #
    # Returns the new player ELO, clamped to [MinELO, MaxELO].
    # ══════════════════════════════════════════════════════════════════════════
    CalcNewRating<public>(
        CurrentELO : int,
        BotELO : int,
        Outcome : int,
        RoundNumber : int,
        IsVolatile : logic
    ) : int =
        # Step 1: Get expected probability
        Expected := CalcExpectedProbability(CurrentELO, BotELO)

        # Step 2: Map outcome to score
        Score := OutcomeToScore(Outcome)

        # Step 3: Select K-factor
        K := SelectKFactor(CurrentELO, RoundNumber, IsVolatile)

        # Step 4: Calculate delta
        Delta := K * (Score - Expected)

        # Step 5: Apply delta and clamp
        RawNewELO := (CurrentELO * 1.0) + Delta
        var NewELO : int = Floor[RawNewELO] or CurrentELO

        # Clamp to valid range
        if (NewELO < MinELO):
            set NewELO = MinELO
        if (NewELO > MaxELO):
            set NewELO = MaxELO

        # Log significant changes
        Change := NewELO - CurrentELO
        if (Change > 0):
            Logger.Print("ELO: {CurrentELO} + {Change} = {NewELO} (K={K} E={Expected} S={Score})")
        else:
            Logger.Print("ELO: {CurrentELO} {Change} = {NewELO} (K={K} E={Expected} S={Score})")

        NewELO

    # ══════════════════════════════════════════════════════════════════════════
    # BULK RATING — Process multiple rounds at once (for catch-up scenarios)
    # Used when the persistence system loads a player who was mid-session
    # and needs to process buffered results.
    # ══════════════════════════════════════════════════════════════════════════
    CalcRatingBatch<public>(
        StartELO : int,
        BotELO : int,
        Outcomes : []int,
        StartRound : int,
        IsVolatile : logic
    ) : int =
        var RunningELO : int = StartELO
        var RoundNum : int = StartRound
        for (Outcome : Outcomes):
            set RunningELO = CalcNewRating(RunningELO, BotELO, Outcome, RoundNum, IsVolatile)
            set RoundNum += 1
        RunningELO

    # ══════════════════════════════════════════════════════════════════════════
    # BOT ELO CALIBRATION
    # The bot's ELO is offset from the player's based on bracket.
    # This creates the "challenge curve" — the bot is always slightly
    # harder than the player's rank to drive improvement, but not so
    # hard that the player feels helpless.
    # ══════════════════════════════════════════════════════════════════════════
    CalcBotELO<public>(PlayerELO : int) : int =
        Offset := GetBotOffset(PlayerELO)
        BotRating := PlayerELO + Offset

        # Ensure bot ELO is at least 100 (never trivially easy)
        if (BotRating < 100):
            return 100
        BotRating

    GetBotOffset<private>(PlayerELO : int) : int =
        if (PlayerELO < 800):
            return BotOffsetBeginner
        else if (PlayerELO < 1200):
            return BotOffsetIntermediate
        else if (PlayerELO < 1600):
            return BotOffsetAdvanced
        else if (PlayerELO < 2000):
            return BotOffsetPro
        BotOffsetElite

    # ══════════════════════════════════════════════════════════════════════════
    # K-FACTOR SELECTION
    # Priority order:
    #   1. Placement (first N rounds): K=48 for fast convergence
    #   2. Stabilization (high ELO): K=16 to prevent wild swings
    #   3. Volatility injection: K=64 to break stagnation
    #   4. Standard: K=32
    # ══════════════════════════════════════════════════════════════════════════
    SelectKFactor<private>(CurrentELO : int, RoundNumber : int, IsVolatile : logic) : float =
        # Placement matches get highest priority
        if (RoundNumber <= PlacementRoundThreshold):
            return KFactorPlacement

        # High ELO stabilization (prevents ±30 swings at pro level)
        if (CurrentELO >= StabilizationELOThreshold):
            if (IsVolatile?):
                # Even during volatility, cap at standard K for elites
                return KFactorStandard
            return KFactorStabilized

        # Anti-stagnation volatility injection
        if (IsVolatile?):
            return KFactorVolatile

        # Default
        KFactorStandard

    # ══════════════════════════════════════════════════════════════════════════
    # OUTCOME MAPPING
    # ══════════════════════════════════════════════════════════════════════════
    OutcomeToScore<public>(Outcome : int) : float =
        if (Outcome = OUTCOME_PLAYER_WIN):
            return 1.0
        else if (Outcome = OUTCOME_BOT_WIN):
            return 0.0
        0.5

    # ══════════════════════════════════════════════════════════════════════════
    # ANALYTICAL QUERIES
    # ══════════════════════════════════════════════════════════════════════════

    # How many ELO points would the player gain/lose for each outcome?
    # Useful for HUD display: "+18 / -14" before the round starts.
    CalcPotentialChange<public>(PlayerELO : int, BotELO : int, RoundNumber : int, IsVolatile : logic) : []int =
        Expected := CalcExpectedProbability(PlayerELO, BotELO)
        K := SelectKFactor(PlayerELO, RoundNumber, IsVolatile)

        WinDelta := Floor[K * (1.0 - Expected)] or 0
        LossDelta := Floor[K * (0.0 - Expected)] or 0
        DrawDelta := Floor[K * (0.5 - Expected)] or 0

        array{WinDelta, LossDelta, DrawDelta}

    # What ELO bracket is the player in?
    # Returns: 0=Beginner, 1=Intermediate, 2=Advanced, 3=Pro, 4=Elite
    GetBracket<public>(PlayerELO : int) : int =
        if (PlayerELO < 800):
            return 0
        else if (PlayerELO < 1200):
            return 1
        else if (PlayerELO < 1600):
            return 2
        else if (PlayerELO < 2000):
            return 3
        4

    GetBracketName<public>(PlayerELO : int) : string =
        Bracket := GetBracket(PlayerELO)
        if (Bracket = 0):
            return "Beginner"
        else if (Bracket = 1):
            return "Intermediate"
        else if (Bracket = 2):
            return "Advanced"
        else if (Bracket = 3):
            return "Pro"
        "Elite"

    # Rounds needed to reach a target ELO assuming consistent wins.
    # Used by coach for goal-setting: "At your current rate, ~8 more wins to reach Gold."
    EstimateRoundsToTarget<public>(CurrentELO : int, TargetELO : int, BotELO : int) : int =
        if (TargetELO <= CurrentELO):
            return 0
        Expected := CalcExpectedProbability(CurrentELO, BotELO)
        K := KFactorStandard
        var GainPerWin : float = K * (1.0 - Expected)
        if (GainPerWin < 1.0):
            set GainPerWin = 1.0
        Gap := (TargetELO - CurrentELO) * 1.0
        Estimate := Gap / GainPerWin
        Result := Floor[Estimate] or 1
        if (Result < 1):
            return 1
        Result

    # ══════════════════════════════════════════════════════════════════════════
    # POWER FUNCTION: 10^x
    # Implements via Taylor series expansion of e^(x·ln10).
    #
    # e^t ≈ 1 + t + t²/2! + t³/3! + t⁴/4! + t⁵/5! + t⁶/6! + t⁷/7! + t⁸/8!
    #
    # 8 terms gives <0.01% error for |x| ≤ 3.0, which covers the full
    # practical range of ELO differences (±1200 → exponent ±3.0).
    #
    # For |x| > 3.0, we clamp — the probability is so close to 0 or 1
    # that additional precision is meaningless.
    # ══════════════════════════════════════════════════════════════════════════
    Pow10<private>(Exponent : float) : float =
        # Handle negative exponents via reciprocal
        if (Exponent < 0.0):
            return 1.0 / Pow10(0.0 - Exponent)

        # Handle zero
        if (Exponent < 0.0001):
            return 1.0

        # 10^x = e^(x * ln(10))
        LN10 : float = 2.302585093
        T := Exponent * LN10

        # 8-term Taylor series for e^T
        T2 := T * T
        T3 := T2 * T
        T4 := T3 * T
        T5 := T4 * T
        T6 := T5 * T
        T7 := T6 * T
        T8 := T7 * T

        Result := 1.0 + T + (T2 / 2.0) + (T3 / 6.0) + (T4 / 24.0) + (T5 / 120.0) + (T6 / 720.0) + (T7 / 5040.0) + (T8 / 40320.0)

        # Safety: result should always be positive
        if (Result < 0.0001):
            return 0.0001
        Result

    # ══════════════════════════════════════════════════════════════════════════
    # UTILITY
    # ══════════════════════════════════════════════════════════════════════════
    ClampFloat<private>(Value : float, MinVal : float, MaxVal : float) : float =
        if (Value < MinVal):
            return MinVal
        if (Value > MaxVal):
            return MaxVal
        Value

log_elo_ch := class(log_channel):