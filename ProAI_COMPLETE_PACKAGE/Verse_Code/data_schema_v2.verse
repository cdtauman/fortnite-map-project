# ============================================================================
# FILE: data_schema_v2.verse — Persistable Data Class Definitions (V2)
# LOCATION: Content/ (root)
# PHASE: 5+
#
# ARCHITECTURE:
#   V2 schema extends V1 with additional fields that were identified as
#   needed after the initial deployment. Per the Version Migration Pattern
#   (spec §6.3, HC-06), we CANNOT modify V1 classes after deployment.
#   Instead, we create V2 classes and run migration_v1_to_v2 to transform
#   old data into the new format.
#
#   V2 ADDITIONS:
#     Rating (Slot 2):
#       + AvgRoundDurationSec — Tracks average fight length
#       + PreferredCombatStyle — Integer enum for favored playstyle
#       + TotalEditsPerformed — Lifetime edit count
#       + TotalBuildsPlaced — Lifetime build count
#       + SchemaVersion = 2 — Explicit version tag for migration detection
#
#     Progression (Slot 3):
#       + WeeklyQuestBitfield — Separate weekly challenges from permanent
#       + SeasonNumber — Which season's quests are active
#       + UnlockedDrills — Bitfield for unlocked training drill modules
#       + CoachingTier — How much coaching feedback is unlocked (0-3)
#
#     Analytics (Slot 1):
#       + AvgEditSpeedMs — Track editing performance over time
#       + AvgBuildRate — Builds per minute lifetime average
#       + LongestWinStreak — Persistence of best streak
#       + LongestLossStreak — Persistence of worst streak
#
#     Economy (Slot 4):
#       + TotalTokensConsumed — Track usage for engagement analytics
#       + EquippedModifier — Currently active gameplay modifier ID
#       + SeasonPassActive — Whether the seasonal pass is active
#
# MIGRATION:
#   V1 data is read by migration_v1_to_v2.verse, mapped to V2 fields,
#   and V2 is saved. V1 fields are left in place (we can't delete them)
#   but are no longer read by any module after migration.
# ============================================================================
using { /Verse.org/Simulation }

# ══════════════════════════════════════════════════════════════════════════════
# SLOT 1: ANALYTICS STORE V2
# ══════════════════════════════════════════════════════════════════════════════
player_analytics_data_v2<public> := class<final><persistable>:
    # Carried from V1
    AvgDPS<public>              : float = 0.0
    AvgHeadshotPct<public>      : float = 0.0
    AvgAccuracyPct<public>      : float = 0.0
    AvgReactionMs<public>       : float = 0.0
    TotalSessions<public>       : int = 0
    TotalRounds<public>         : int = 0
    AvgRoundDurationSec<public> : float = 0.0
    TotalBuildsPlaced<public>   : int = 0
    TotalEditsPerformed<public> : int = 0
    ConsistencyScore<public>    : float = 50.0
    # New in V2
    AvgEditSpeedMs<public>      : float = 0.0
    AvgBuildRate<public>        : float = 0.0
    LongestWinStreak<public>    : int = 0
    LongestLossStreak<public>   : int = 0
    SchemaVersion<public>       : int = 2

# ══════════════════════════════════════════════════════════════════════════════
# SLOT 2: RATING & SOCIAL PROFILE V2
# ══════════════════════════════════════════════════════════════════════════════
player_rating_data_v2<public> := class<final><persistable>:
    # Carried from V1
    ELO<public>                  : int = 1000
    PeakELO<public>              : int = 1000
    LowestELO<public>            : int = 1000
    TotalWins<public>            : int = 0
    TotalLosses<public>          : int = 0
    TotalDraws<public>           : int = 0
    TotalTrainingMinutes<public> : int = 0
    BestWinStreak<public>        : int = 0
    LastPlayedTimestamp<public>   : int = 0
    # New in V2
    PreferredCombatStyle<public> : int = 0
    TotalEditsPerformed<public>  : int = 0
    TotalBuildsPlaced<public>    : int = 0
    AvgRoundDurationSec<public>  : float = 0.0
    SchemaVersion<public>        : int = 2

# ══════════════════════════════════════════════════════════════════════════════
# SLOT 3: PROGRESSION & QUEST JOURNAL V2
# ══════════════════════════════════════════════════════════════════════════════
player_progression_data_v2<public> := class<final><persistable>:
    # Carried from V1
    QuestBitfield<public>         : int = 0
    MilestonesReached<public>     : int = 0
    HighestBracket<public>        : int = 0
    DailyChallenges<public>       : int = 0
    TotalQuestsCompleted<public>  : int = 0
    # New in V2
    WeeklyQuestBitfield<public>   : int = 0
    SeasonNumber<public>          : int = 1
    UnlockedDrills<public>        : int = 0
    CoachingTier<public>          : int = 0
    SchemaVersion<public>         : int = 2

# ══════════════════════════════════════════════════════════════════════════════
# SLOT 4: ECONOMY & INVENTORY V2
# ══════════════════════════════════════════════════════════════════════════════
player_economy_data_v2<public> := class<final><persistable>:
    # Carried from V1
    HasAnalyticsPass<public>     : logic = false
    ArenaSkinsOwned<public>      : int = 0
    ChallengeTokens<public>      : int = 0
    EquippedArenaSkin<public>    : int = 0
    TotalVBucksSpent<public>     : int = 0
    TotalPurchaseCount<public>   : int = 0
    # New in V2
    TotalTokensConsumed<public>  : int = 0
    EquippedModifier<public>     : int = 0
    SeasonPassActive<public>     : logic = false
    SchemaVersion<public>        : int = 2
