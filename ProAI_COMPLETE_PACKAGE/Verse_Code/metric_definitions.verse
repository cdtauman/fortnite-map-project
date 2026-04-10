# ============================================================================
# FILE: metric_definitions.verse — Data Structs for All Tracked Metrics
# LOCATION: Content/ (root)
# PHASE: 4
#
# ARCHITECTURE:
#   Pure data — zero logic. Every struct here is consumed by multiple
#   modules across the entire project:
#
#     round_metrics      → Written by analytics_engine each round.
#                           Read by predictive_advisor, session_aggregator,
#                           coach_controller, hud_binding, persistence.
#
#     session_summary    → Compiled by session_aggregator from round history.
#                           Written to persistence (Module D Slot 1).
#                           Read by coach_controller for trend feedback.
#
#     combat_snapshot    → High-frequency combat data sampled during fights.
#                           Written by the analytics background loop.
#                           Read by weapon_controller and coach for live DPS.
#
#     build_performance  → Aggregated building metrics per round.
#                           Written by build event listeners.
#                           Read by coach for build-speed feedback.
#
#     player_trend       → Rolling trend analysis result.
#                           Written by predictive_advisor.
#                           Read by coach_controller and difficulty_mapper.
#
# DESIGN RULES:
#   - All fields are `var` with defaults so structs can be initialized empty.
#   - All fields are <public> so any module can read/write.
#   - No `<persistable>` here — persistence uses its own schema classes
#     (data_schema_v1/v2) to control serialization independently.
#   - No dependencies on any other project file.
# ============================================================================
using { /Verse.org/Simulation }

# ── Trend Direction Constants ────────────────────────────────────────────────
TREND_IMPROVING<public>  : int = 1
TREND_STABLE<public>     : int = 0
TREND_DECLINING<public>  : int = -1

# -- Outcome Constants --
OUTCOME_NONE<public>       : int = 0
OUTCOME_PLAYER_WIN<public> : int = 1
OUTCOME_BOT_WIN<public>    : int = 2
OUTCOME_DRAW<public>       : int = 3

# -- Game State Constants --
STATE_LOBBY<public>       : int = 0
STATE_COUNTDOWN<public>   : int = 1
STATE_COMBAT<public>      : int = 2
STATE_FIGHT<public>       : int = 2
STATE_POST_ROUND<public>  : int = 3
STATE_RESET<public>       : int = 4
STATE_RESETTING<public>   : int = 4
STATE_IDLE<public>        : int = 5

# ══════════════════════════════════════════════════════════════════════════════
# ROUND METRICS — Complete snapshot of one round's performance
# Written at EndRoundTracking, stored in rolling history array.
# ══════════════════════════════════════════════════════════════════════════════
round_metrics<public> := class:
    # ── Damage Metrics ───────────────────────────────────────────────────────
    # Total damage the player dealt to the bot this round.
    var DamageDealt<public>         : float = 0.0
    # Total damage the bot dealt to the player this round.
    var DamageTaken<public>         : float = 0.0
    # Computed DPS: DamageDealt / RoundDurationSec.
    var DPS<public>                 : float = 0.0

    # ── Accuracy Metrics ─────────────────────────────────────────────────────
    # Total shots the player landed on the bot.
    var PlayerShotsHit<public>      : int = 0
    # Total shots the player fired (hit + miss).
    var PlayerShotsFired<public>    : int = 0
    # Headshot count out of PlayerShotsHit.
    var PlayerHeadshots<public>     : int = 0
    # Headshot percentage: PlayerHeadshots / PlayerShotsHit * 100.
    var HeadshotPct<public>         : float = 0.0
    # Accuracy percentage: PlayerShotsHit / PlayerShotsFired * 100.
    var AccuracyPct<public>         : float = 0.0

    # ── Bot Combat Metrics (what the bot did to the player) ──────────────────
    var BotDamageDealt<public>      : float = 0.0
    var BotShotsHit<public>         : int = 0
    var BotHeadshots<public>        : int = 0

    # ── Reaction & Timing ────────────────────────────────────────────────────
    # Time from round start to first player damage event (ms).
    var ReactionTimeMs<public>      : float = 0.0
    # Average time between consecutive player damage events (ms).
    var AvgTimeBetweenHitsMs<public>: float = 0.0

    # ── Build Metrics ────────────────────────────────────────────────────────
    # Total build pieces deployed by the bot this round.
    var BuildsPlaced<public>        : int = 0
    # Total bot builds destroyed by the player.
    var BuildsDestroyed<public>     : int = 0
    # Total edits performed by the bot.
    var EditsPerformed<public>      : int = 0
    # Fastest single edit time by the bot (ms).
    var FastestEditMs<public>       : float = 0.0
    # Edits per second across the round.
    var EditSpeed<public>           : float = 0.0

    # ── Round Context ────────────────────────────────────────────────────────
    # Total round duration in seconds.
    var RoundDurationSec<public>    : float = 0.0
    # Outcome: OUTCOME_PLAYER_WIN / OUTCOME_BOT_WIN / OUTCOME_DRAW.
    var Outcome<public>             : int = 0
    # Player's ELO at round start.
    var PlayerELO<public>           : int = 1000
    # Bot's ELO (difficulty target) at round start.
    var BotELO<public>              : int = 1000
    # Round number within the session.
    var RoundNumber<public>         : int = 0
    # Timestamp when the round started (simulation time).
    var RoundStartTimestamp<public> : float = 0.0

# ══════════════════════════════════════════════════════════════════════════════
# COMBAT SNAPSHOT — High-frequency combat data for live HUD updates
# Written every 0.5s by the analytics background loop.
# ══════════════════════════════════════════════════════════════════════════════
combat_snapshot<public> := class:
    var LiveDPS<public>             : float = 0.0
    var LiveAccuracy<public>        : float = 0.0
    var LiveHeadshotPct<public>     : float = 0.0
    var LiveDistanceToBot<public>   : float = 0.0
    var CurrentCombatState<public>  : int = 0
    var ElapsedFightSec<public>     : float = 0.0
    var Timestamp<public>           : float = 0.0

# ══════════════════════════════════════════════════════════════════════════════
# BUILD PERFORMANCE — Aggregated building stats per round
# ══════════════════════════════════════════════════════════════════════════════
build_performance<public> := class:
    var TotalPiecesPlaced<public>   : int = 0
    var WallsPlaced<public>         : int = 0
    var FloorsPlaced<public>        : int = 0
    var RampsPlaced<public>         : int = 0
    var ConesPlaced<public>         : int = 0
    var EditsPerformed<public>      : int = 0
    var WindowEdits<public>         : int = 0
    var DoorEdits<public>           : int = 0
    var EditResets<public>          : int = 0
    var AvgEditSpeedMs<public>      : float = 0.0
    var PeakBuildBurstRate<public>  : float = 0.0

# ══════════════════════════════════════════════════════════════════════════════
# SESSION SUMMARY — Compiled from round history at session end
# Written to persistence for cross-session tracking.
# ══════════════════════════════════════════════════════════════════════════════
session_summary<public> := class:
    var TotalRounds<public>         : int = 0
    var Wins<public>                : int = 0
    var Losses<public>              : int = 0
    var Draws<public>               : int = 0
    var AvgDPS<public>              : float = 0.0
    var AvgHeadshotPct<public>      : float = 0.0
    var AvgAccuracyPct<public>      : float = 0.0
    var AvgReactionMs<public>       : float = 0.0
    var AvgRoundDurationSec<public> : float = 0.0
    var StartingELO<public>         : int = 1000
    var FinalELO<public>            : int = 1000
    var PeakELO<public>             : int = 1000
    var LowestELO<public>           : int = 1000
    var SessionDurationMin<public>  : float = 0.0
    var TotalBuildsPlaced<public>   : int = 0
    var TotalEditsPerformed<public> : int = 0
    var LongestWinStreak<public>    : int = 0
    var LongestLossStreak<public>   : int = 0

# ══════════════════════════════════════════════════════════════════════════════
# PLAYER TREND — Rolling trend analysis result
# Written by predictive_advisor, read by coach and difficulty_mapper.
# ══════════════════════════════════════════════════════════════════════════════
player_trend<public> := class:
    var DPSTrend<public>            : int = 0
    var AccuracyTrend<public>       : int = 0
    var HeadshotTrend<public>       : int = 0
    var ReactionTimeTrend<public>   : int = 0
    var BuildSpeedTrend<public>     : int = 0
    var ELOTrend<public>            : int = 0
    var OverallTrend<public>        : int = 0
    var IsStagnating<public>        : logic = false
    var IsFrustrated<public>        : logic = false
    var ShouldInjectVolatility<public> : logic = false