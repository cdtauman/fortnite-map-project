# ============================================================================
# FILE: data_schema_v1.verse — Persistable Data Class Definitions (V1)
# LOCATION: Content/ (root)
# PHASE: 5
#
# ARCHITECTURE:
#   Defines the data classes stored in Verse's persistent weak_maps.
#   The project uses exactly 4 weak_map slots (HC-05 constraint):
#
#     Slot 1: AnalyticsStore   → player_analytics_data_v1
#     Slot 2: RatingStore      → player_rating_data_v1
#     Slot 3: ProgressionStore → player_progression_data_v1
#     Slot 4: EconomyStore     → player_economy_data_v1
#
# DESIGN RULES (from spec §6.3, §6.4):
#   - All classes are <final><persistable> — required by Verse serialization.
#   - All fields use primitive types (int, float, logic) — no strings,
#     no arrays, no nested objects (serialization budget).
#   - Integer representations wherever possible (ELO as int, not float).
#   - Quest states compressed into bitfield integers.
#   - No field can be added or removed after deployment (HC-06).
#     Future changes require a V2 schema + migration function.
#   - Default values are the "new player" profile — a fresh account
#     gets these values automatically when the weak_map returns no data.
#
# SERIALIZATION BUDGET:
#   Each slot target: <512 bytes per player.
#     Slot 1: 5 fields × 8 bytes = ~40 bytes ✓
#     Slot 2: 8 fields × 8 bytes = ~64 bytes ✓
#     Slot 3: 5 fields × 8 bytes = ~40 bytes ✓
#     Slot 4: 6 fields × 8 bytes = ~48 bytes ✓
#   Total: ~192 bytes per player — well within budget.
# ============================================================================
using { /Verse.org/Simulation }

# ══════════════════════════════════════════════════════════════════════════════
# SLOT 1: ANALYTICS STORE — Rolling performance averages
# Written by: analytics_engine (via persistence_manager) at session end.
# Read by: analytics_engine on player join to establish baseline.
# ══════════════════════════════════════════════════════════════════════════════
player_analytics_data_v1<public> := class<final><persistable>:
    # Lifetime average DPS across all sessions.
    AvgDPS<public> : float = 0.0
    # Lifetime average headshot percentage.
    AvgHeadshotPct<public> : float = 0.0
    # Lifetime average accuracy percentage.
    AvgAccuracyPct<public> : float = 0.0
    # Lifetime average first-hit reaction time (ms).
    AvgReactionMs<public> : float = 0.0
    # Total number of sessions played (for running average calc).
    TotalSessions<public> : int = 0
    # Total number of rounds played across all sessions.
    TotalRounds<public> : int = 0
    # Average round duration in seconds.
    AvgRoundDurationSec<public> : float = 0.0
    # Total builds placed across all sessions (for build frequency stats).
    TotalBuildsPlaced<public> : int = 0
    # Total edits performed across all sessions.
    TotalEditsPerformed<public> : int = 0
    # DPS consistency score (0-100, from session_aggregator).
    ConsistencyScore<public> : float = 50.0

# ══════════════════════════════════════════════════════════════════════════════
# SLOT 2: RATING & SOCIAL PROFILE — ELO, win/loss, training time
# Written by: persistence_manager at round end and session end.
# Read by: analytics_engine on join to set starting ELO.
# ══════════════════════════════════════════════════════════════════════════════
player_rating_data_v1<public> := class<final><persistable>:
    # Current ELO rating.
    ELO<public> : int = 1000
    # Highest ELO ever achieved.
    PeakELO<public> : int = 1000
    # Lowest ELO recorded (for range tracking).
    LowestELO<public> : int = 1000
    # Total wins across all sessions.
    TotalWins<public> : int = 0
    # Total losses across all sessions.
    TotalLosses<public> : int = 0
    # Total draws across all sessions.
    TotalDraws<public> : int = 0
    # Total training time in minutes (integer for budget savings).
    TotalTrainingMinutes<public> : int = 0
    # Longest win streak ever achieved.
    BestWinStreak<public> : int = 0
    # Schema version tag (for migration detection).
    Version<public> : int = 1
    # Timestamp of last session (simulation ticks, not real time).
    LastPlayedTimestamp<public> : int = 0

# ══════════════════════════════════════════════════════════════════════════════
# SLOT 3: PROGRESSION & QUEST JOURNAL — Quests, milestones, unlocks
# Written by: coach_game_bridge on quest completion events.
# Read by: coach_controller to check unlock state.
# ══════════════════════════════════════════════════════════════════════════════
player_progression_data_v1<public> := class<final><persistable>:
    # Bitfield: each bit = one quest completion flag (up to 32 quests).
    # Bit 0 = "Win 5 rounds", Bit 1 = "Reach 1200 ELO", etc.
    QuestBitfield<public> : int = 0
    # Count of milestones reached (bracket promotions, achievements).
    MilestonesReached<public> : int = 0
    # Highest ELO bracket ever reached (0-4, maps to bracket enum).
    HighestBracket<public> : int = 0
    # Daily challenge completion bitfield (reset daily, 8 challenges max).
    DailyChallenges<public> : int = 0
    # Total quests completed lifetime (for progression tracking).
    TotalQuestsCompleted<public> : int = 0

# ══════════════════════════════════════════════════════════════════════════════
# SLOT 4: ECONOMY & INVENTORY LEDGER — Purchases, tokens, cosmetics
# Written by: shop_manager on purchase events.
# Read by: inventory_controller on join, cosmetic_applicator for skins.
# ══════════════════════════════════════════════════════════════════════════════
player_economy_data_v1<public> := class<final><persistable>:
    # Whether the player owns the Analytics Pass (premium metrics).
    HasAnalyticsPass<public> : logic = false
    # Bitfield: each bit = one arena skin owned (up to 32 skins).
    ArenaSkinsOwned<public> : int = 0
    # Consumable challenge tokens balance.
    ChallengeTokens<public> : int = 0
    # Currently equipped arena skin ID (0 = default).
    EquippedArenaSkin<public> : int = 0
    # Total V-Bucks spent (for analytics, not displayed to player).
    TotalVBucksSpent<public> : int = 0
    # Number of distinct purchases made.
    TotalPurchaseCount<public> : int = 0
