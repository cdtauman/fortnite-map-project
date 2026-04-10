# ============================================================================
# FILE: migration_v1_to_v2.verse — V1 → V2 Schema Migration Functions
# LOCATION: Content/ (root)
# PHASE: 5+
#
# ARCHITECTURE:
#   Per the Version Migration Pattern (spec §6.3), when a player loads
#   in with V1 data (detected by checking if V2 exists or by reading
#   the Version/SchemaVersion field), the persistence_manager calls these
#   migration functions to transform V1 → V2.
#
#   MIGRATION RULES:
#     1. All V1 fields are mapped to their V2 equivalents 1:1.
#     2. New V2 fields are initialized with safe defaults.
#     3. No data is lost — V1 values are preserved exactly.
#     4. The SchemaVersion field is set to 2 on the output.
#     5. After migration, the persistence_manager saves V2 and stops
#        reading V1. V1 data remains in the weak_map but is stale.
#
#   MIGRATION LOG:
#     V1 → V2 Changes:
#       Analytics: +AvgEditSpeedMs, +AvgBuildRate, +LongestWinStreak,
#                  +LongestLossStreak, +SchemaVersion
#       Rating:    +PreferredCombatStyle, +TotalEditsPerformed,
#                  +TotalBuildsPlaced, +AvgRoundDurationSec, +SchemaVersion
#       Progression: +WeeklyQuestBitfield, +SeasonNumber, +UnlockedDrills,
#                    +CoachingTier, +SchemaVersion
#       Economy:   +TotalTokensConsumed, +EquippedModifier,
#                  +SeasonPassActive, +SchemaVersion
# ============================================================================
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }

migration_v1_to_v2<public> := class:

    Logger<private> : log = log{Channel := log_migrate_ch}

    # ══════════════════════════════════════════════════════════════════════════
    # MIGRATE ANALYTICS — Slot 1: V1 → V2
    # ══════════════════════════════════════════════════════════════════════════
    MigrateAnalytics<public>(V1 : player_analytics_data_v1) : player_analytics_data_v2 =
        Logger.Print("MIGRATE: Analytics V1 -> V2. Sessions:{V1.TotalSessions} Rounds:{V1.TotalRounds}")

        Result := player_analytics_data_v2{
            # Direct carry-over
            AvgDPS := V1.AvgDPS,
            AvgHeadshotPct := V1.AvgHeadshotPct,
            AvgAccuracyPct := V1.AvgAccuracyPct,
            AvgReactionMs := V1.AvgReactionMs,
            TotalSessions := V1.TotalSessions,
            TotalRounds := V1.TotalRounds,
            AvgRoundDurationSec := V1.AvgRoundDurationSec,
            TotalBuildsPlaced := V1.TotalBuildsPlaced,
            TotalEditsPerformed := V1.TotalEditsPerformed,
            ConsistencyScore := V1.ConsistencyScore,
            # New V2 fields — safe defaults
            AvgEditSpeedMs := 0.0,
            AvgBuildRate := 0.0,
            LongestWinStreak := 0,
            LongestLossStreak := 0,
            SchemaVersion := 2
        }

        Logger.Print("MIGRATE: Analytics migration complete.")
        Result

    # ══════════════════════════════════════════════════════════════════════════
    # MIGRATE RATING — Slot 2: V1 → V2
    # ══════════════════════════════════════════════════════════════════════════
    MigrateRating<public>(V1 : player_rating_data_v1) : player_rating_data_v2 =
        Logger.Print("MIGRATE: Rating V1 -> V2. ELO:{V1.ELO} Peak:{V1.PeakELO}")

        Result := player_rating_data_v2{
            # Direct carry-over
            ELO := V1.ELO,
            PeakELO := V1.PeakELO,
            LowestELO := V1.LowestELO,
            TotalWins := V1.TotalWins,
            TotalLosses := V1.TotalLosses,
            TotalDraws := V1.TotalDraws,
            TotalTrainingMinutes := V1.TotalTrainingMinutes,
            BestWinStreak := V1.BestWinStreak,
            LastPlayedTimestamp := V1.LastPlayedTimestamp,
            # New V2 fields — safe defaults
            PreferredCombatStyle := 0,
            TotalEditsPerformed := 0,
            TotalBuildsPlaced := 0,
            AvgRoundDurationSec := 0.0,
            SchemaVersion := 2
        }

        Logger.Print("MIGRATE: Rating migration complete. ELO preserved: {Result.ELO}")
        Result

    # ══════════════════════════════════════════════════════════════════════════
    # MIGRATE PROGRESSION — Slot 3: V1 → V2
    # ══════════════════════════════════════════════════════════════════════════
    MigrateProgression<public>(V1 : player_progression_data_v1) : player_progression_data_v2 =
        Logger.Print("MIGRATE: Progression V1 -> V2. Quests:{V1.QuestBitfield} Milestones:{V1.MilestonesReached}")

        Result := player_progression_data_v2{
            # Direct carry-over
            QuestBitfield := V1.QuestBitfield,
            MilestonesReached := V1.MilestonesReached,
            HighestBracket := V1.HighestBracket,
            DailyChallenges := V1.DailyChallenges,
            TotalQuestsCompleted := V1.TotalQuestsCompleted,
            # New V2 fields — safe defaults
            WeeklyQuestBitfield := 0,
            SeasonNumber := 1,
            UnlockedDrills := 0,
            CoachingTier := DeriveCoachingTier(V1.HighestBracket),
            SchemaVersion := 2
        }

        Logger.Print("MIGRATE: Progression migration complete. CoachingTier derived: {Result.CoachingTier}")
        Result

    # ══════════════════════════════════════════════════════════════════════════
    # MIGRATE ECONOMY — Slot 4: V1 → V2
    # ══════════════════════════════════════════════════════════════════════════
    MigrateEconomy<public>(V1 : player_economy_data_v1) : player_economy_data_v2 =
        Logger.Print("MIGRATE: Economy V1 -> V2. Pass:{if (V1.HasAnalyticsPass?) then "true" else "false"} Tokens:{V1.ChallengeTokens}")

        Result := player_economy_data_v2{
            # Direct carry-over
            HasAnalyticsPass := V1.HasAnalyticsPass,
            ArenaSkinsOwned := V1.ArenaSkinsOwned,
            ChallengeTokens := V1.ChallengeTokens,
            EquippedArenaSkin := V1.EquippedArenaSkin,
            TotalVBucksSpent := V1.TotalVBucksSpent,
            TotalPurchaseCount := V1.TotalPurchaseCount,
            # New V2 fields — safe defaults
            TotalTokensConsumed := 0,
            EquippedModifier := 0,
            SeasonPassActive := false,
            SchemaVersion := 2
        }

        Logger.Print("MIGRATE: Economy migration complete.")
        Result

    # ══════════════════════════════════════════════════════════════════════════
    # FULL MIGRATION — Run all 4 slots at once
    # Returns true if all migrations succeeded.
    # ══════════════════════════════════════════════════════════════════════════
    MigrateAll<public>(
        AnalyticsV1 : player_analytics_data_v1,
        RatingV1 : player_rating_data_v1,
        ProgressionV1 : player_progression_data_v1,
        EconomyV1 : player_economy_data_v1
    ) : migration_result =
        Logger.Print("MIGRATE: ══ Full V1 → V2 Migration Started ══")

        AnalyticsV2 := MigrateAnalytics(AnalyticsV1)
        RatingV2 := MigrateRating(RatingV1)
        ProgressionV2 := MigrateProgression(ProgressionV1)
        EconomyV2 := MigrateEconomy(EconomyV1)

        Result := migration_result{
            Analytics := AnalyticsV2,
            Rating := RatingV2,
            Progression := ProgressionV2,
            Economy := EconomyV2,
            WasMigrated := true,
            SourceVersion := 1,
            TargetVersion := 2
        }

        Logger.Print("MIGRATE: ══ Full Migration Complete ══")
        Result

    # ══════════════════════════════════════════════════════════════════════════
    # DETECTION — Check if migration is needed
    # ══════════════════════════════════════════════════════════════════════════
    NeedsMigration<public>(V1Rating : player_rating_data_v1) : logic =
        # If the Version field is 1 (or absent/default), migration is needed
        if (V1Rating.Version <= 1):
            return true
        false

    # ══════════════════════════════════════════════════════════════════════════
    # PRIVATE: Derivation Helpers
    # Some V2 fields can be intelligently derived from V1 data rather
    # than defaulting to zero.
    # ══════════════════════════════════════════════════════════════════════════

    # Derive coaching tier from highest bracket achieved:
    # Bracket 0-1 → Tier 0 (basic feedback only)
    # Bracket 2   → Tier 1 (+ weakness coaching)
    # Bracket 3   → Tier 2 (+ predictive alerts)
    # Bracket 4   → Tier 3 (full coaching suite)
    DeriveCoachingTier<private>(HighestBracket : int) : int =
        if (HighestBracket >= 4):
            return 3
        else if (HighestBracket >= 3):
            return 2
        else if (HighestBracket >= 2):
            return 1
        0

log_migrate_ch := class(log_channel):

# ══════════════════════════════════════════════════════════════════════════════
# MIGRATION RESULT — Packages all 4 migrated slots for the persistence manager
# ══════════════════════════════════════════════════════════════════════════════
migration_result<public> := class:
    Analytics<public>     : player_analytics_data_v2 = player_analytics_data_v2{}
    Rating<public>        : player_rating_data_v2 = player_rating_data_v2{}
    Progression<public>   : player_progression_data_v2 = player_progression_data_v2{}
    Economy<public>       : player_economy_data_v2 = player_economy_data_v2{}
    var WasMigrated<public>  : logic = false
    var SourceVersion<public>: int = 0
    var TargetVersion<public>: int = 0