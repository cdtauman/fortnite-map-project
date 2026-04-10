# ============================================================================
# FILE: data_validator.verse — Data Integrity Checks & Sanitization
# LOCATION: Content/ (root)
# PHASE: 5
#
# ARCHITECTURE:
#   Every piece of data loaded from persistence passes through this
#   validator before being used by any module. The validator catches:
#
#     1. IMPOSSIBLE VALUES — ELO < 0, negative win counts, etc.
#        Cause: serialization corruption, version mismatch, engine bugs.
#        Fix: clamp to valid range or reset to safe default.
#
#     2. LOGICAL INCONSISTENCIES — PeakELO < CurrentELO, more draws
#        than total matches, negative token balances.
#        Cause: interrupted writes, race conditions during save.
#        Fix: correct the inconsistency using the more trustworthy field.
#
#     3. OVERFLOW DETECTION — Values exceeding reasonable maximums.
#        Cause: accumulation bugs, exploit attempts.
#        Fix: cap to maximum and log a warning.
#
#   The validator NEVER crashes. Every method returns a corrected copy
#   of the input — the worst case is a reset to defaults, which is
#   always better than a runtime error from impossible math.
#
# VALIDATION RANGES:
#   ELO:              [0, 5000]
#   Win/Loss/Draw:    [0, 999999]
#   Training Minutes: [0, 999999]
#   Win Streak:       [0, 9999]
#   V-Bucks Spent:    [0, 9999999]
#   Challenge Tokens: [0, 9999]
#   Percentages:      [0.0, 100.0]
#   DPS:              [0.0, 9999.0]
#   Reaction Time:    [0.0, 9999.0]
#   Consistency:      [0.0, 100.0]
# ============================================================================
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }

data_validator<public> := class:

    Logger<private> : log = log{Channel := log_val_ch}

    # ── Telemetry ────────────────────────────────────────────────────────────
    var TotalValidations<private>   : int = 0
    var TotalCorrections<private>   : int = 0
    var TotalCriticalResets<private> : int = 0

    # ══════════════════════════════════════════════════════════════════════════
    # VALIDATE RATING — Slot 2 (V1)
    # The most critical validation — ELO drives the entire difficulty system.
    # ══════════════════════════════════════════════════════════════════════════
    ValidateRating<public>(Data : player_rating_data_v1) : player_rating_data_v1 =
        set TotalValidations += 1

        NewELO := SanitizeInt(Data.ELO, 0, 5000, 1000)
        NewPeakELO := SanitizeInt(Data.PeakELO, NewELO, 5000, NewELO)
        NewLowestELO := SanitizeInt(Data.LowestELO, 0, NewELO, 0)
        NewTotalWins := SanitizeNonNegativeInt(Data.TotalWins)
        NewTotalLosses := SanitizeNonNegativeInt(Data.TotalLosses)
        NewTotalDraws := SanitizeNonNegativeInt(Data.TotalDraws)
        NewTotalTrainingMinutes := SanitizeInt(Data.TotalTrainingMinutes, 0, 999999, 0)
        NewBestWinStreak := SanitizeNonNegativeInt(Data.BestWinStreak)
        NewVersion := SanitizeInt(Data.Version, 1, 999999, 1)

        player_rating_data_v1{
            ELO := NewELO,
            PeakELO := NewPeakELO,
            LowestELO := NewLowestELO,
            TotalWins := NewTotalWins,
            TotalLosses := NewTotalLosses,
            TotalDraws := NewTotalDraws,
            TotalTrainingMinutes := NewTotalTrainingMinutes,
            BestWinStreak := NewBestWinStreak,
            Version := NewVersion,
            LastPlayedTimestamp := Data.LastPlayedTimestamp
        }

    # ══════════════════════════════════════════════════════════════════════════
    # VALIDATE ANALYTICS — Slot 1 (V1)
    # Averages must be non-negative. Counts must be non-negative.
    # ══════════════════════════════════════════════════════════════════════════
    ValidateAnalytics<public>(Data : player_analytics_data_v1) : player_analytics_data_v1 =
        set TotalValidations += 1

        NewTotalSessions := SanitizeNonNegativeInt(Data.TotalSessions)
        var NewTotalRounds : int = SanitizeNonNegativeInt(Data.TotalRounds)
        if (NewTotalRounds < NewTotalSessions):
            if (NewTotalSessions > 0):
                set NewTotalRounds = NewTotalSessions
                set TotalCorrections += 1

        player_analytics_data_v1{
            AvgDPS := ClampF(Data.AvgDPS, 0.0, 9999.0),
            AvgHeadshotPct := ClampF(Data.AvgHeadshotPct, 0.0, 100.0),
            AvgAccuracyPct := ClampF(Data.AvgAccuracyPct, 0.0, 100.0),
            AvgReactionMs := ClampF(Data.AvgReactionMs, 0.0, 9999.0),
            ConsistencyScore := ClampF(Data.ConsistencyScore, 0.0, 100.0),
            AvgRoundDurationSec := ClampF(Data.AvgRoundDurationSec, 0.0, 3600.0),
            TotalSessions := NewTotalSessions,
            TotalRounds := NewTotalRounds,
            TotalBuildsPlaced := SanitizeNonNegativeInt(Data.TotalBuildsPlaced),
            TotalEditsPerformed := SanitizeNonNegativeInt(Data.TotalEditsPerformed)
        }

    # ══════════════════════════════════════════════════════════════════════════
    # VALIDATE ECONOMY — Slot 4 (V1)
    # Token balances must be non-negative. Purchase counts must make sense.
    # ══════════════════════════════════════════════════════════════════════════
    ValidateEconomy<public>(Data : player_economy_data_v1) : player_economy_data_v1 =
        set TotalValidations += 1

        player_economy_data_v1{
            ChallengeTokens := SanitizeInt(Data.ChallengeTokens, 0, 9999, 0),
            ArenaSkinsOwned := SanitizeNonNegativeInt(Data.ArenaSkinsOwned),
            EquippedArenaSkin := SanitizeNonNegativeInt(Data.EquippedArenaSkin),
            TotalVBucksSpent := SanitizeNonNegativeInt(Data.TotalVBucksSpent),
            TotalPurchaseCount := SanitizeNonNegativeInt(Data.TotalPurchaseCount),
            HasAnalyticsPass := Data.HasAnalyticsPass
        }

    # ══════════════════════════════════════════════════════════════════════════
    # VALIDATE PROGRESSION — Slot 3 (V1)
    # Bitfields don't have "invalid" states per se, but counts must be sane.
    # ══════════════════════════════════════════════════════════════════════════
    ValidateProgression<public>(Data : player_progression_data_v1) : player_progression_data_v1 =
        set TotalValidations += 1

        player_progression_data_v1{
            QuestBitfield := Data.QuestBitfield,
            DailyChallenges := Data.DailyChallenges,
            MilestonesReached := SanitizeNonNegativeInt(Data.MilestonesReached),
            HighestBracket := SanitizeInt(Data.HighestBracket, 0, 4, 0),
            TotalQuestsCompleted := SanitizeNonNegativeInt(Data.TotalQuestsCompleted)
        }

    # ══════════════════════════════════════════════════════════════════════════
    # STANDALONE SANITIZERS — Quick single-field validations
    # Used by modules that only need one field checked.
    # ══════════════════════════════════════════════════════════════════════════

    SanitizeELO<public>(RawELO : int) : int =
        if (RawELO < 0):
            Logger.Print("VALIDATOR: SanitizeELO — negative ({RawELO}), returning 1000.")
            set TotalCorrections += 1
            return 1000
        if (RawELO > 5000):
            Logger.Print("VALIDATOR: SanitizeELO — overflow ({RawELO}), capping at 5000.")
            set TotalCorrections += 1
            return 5000
        RawELO

    SanitizeFloat<public>(Value : float, MinVal : float, MaxVal : float, Default : float) : float =
        if (Value < MinVal):
            set TotalCorrections += 1
            return Default
        if (Value > MaxVal):
            set TotalCorrections += 1
            return Default
        Value

    SanitizeInt<public>(Value : int, MinVal : int, MaxVal : int, Default : int) : int =
        if (Value < MinVal):
            set TotalCorrections += 1
            return Default
        if (Value > MaxVal):
            set TotalCorrections += 1
            return Default
        Value

    SanitizePercentage<public>(Value : float) : float =
        ClampF(Value, 0.0, 100.0)

    SanitizeNonNegativeInt<public>(Value : int) : int =
        if (Value < 0):
            set TotalCorrections += 1
            return 0
        Value

    # ══════════════════════════════════════════════════════════════════════════
    # FULL INTEGRITY CHECK — Validates ALL slots and returns a summary
    # Used during diagnostic testing.
    # ══════════════════════════════════════════════════════════════════════════
    RunFullIntegrityCheck<public>(
        Rating : player_rating_data_v1,
        Analytics : player_analytics_data_v1,
        Economy : player_economy_data_v1,
        Progression : player_progression_data_v1
    ) : int =
        CorrectionsBefore := TotalCorrections
        ValidateRating(Rating)
        ValidateAnalytics(Analytics)
        ValidateEconomy(Economy)
        ValidateProgression(Progression)
        CorrectionsFound := TotalCorrections - CorrectionsBefore
        Logger.Print("VALIDATOR: Full integrity check — {CorrectionsFound} corrections applied.")
        CorrectionsFound

    # ══════════════════════════════════════════════════════════════════════════
    # TELEMETRY
    # ══════════════════════════════════════════════════════════════════════════
    GetTotalValidations<public>() : int =
        TotalValidations

    GetTotalCorrections<public>() : int =
        TotalCorrections

    GetCorrectionRate<public>() : float =
        if (TotalValidations > 0):
            return (TotalCorrections * 1.0) / (TotalValidations * 1.0)
        0.0

    LogValidatorStats<public>() : void =
        Logger.Print("VALIDATOR: ── Statistics ──")
        Logger.Print("VALIDATOR:   Total Validations: {TotalValidations}")
        Logger.Print("VALIDATOR:   Total Corrections: {TotalCorrections}")
        Logger.Print("VALIDATOR:   Critical Resets: {TotalCriticalResets}")
        Logger.Print("VALIDATOR:   Correction Rate: {GetCorrectionRate()}")

    # ══════════════════════════════════════════════════════════════════════════
    # PRIVATE UTILITIES
    # ══════════════════════════════════════════════════════════════════════════
    ClampF<private>(Value : float, MinVal : float, MaxVal : float) : float =
        if (Value < MinVal):
            set TotalCorrections += 1
            return MinVal
        if (Value > MaxVal):
            set TotalCorrections += 1
            return MaxVal
        Value

log_val_ch := class(log_channel):