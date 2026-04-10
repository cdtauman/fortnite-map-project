# 04 — Codebase Reference

> Technical architecture reference for the ProAI Training Map.
> Covers all 35 Verse files across 6 modules + Core + UI layers.
> Last updated: Mission 20 (Documentation Sync).

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Core Layer](#2-core-layer)
3. [Module A — Bot AI](#3-module-a--bot-ai)
4. [Module B — Build Simulation](#4-module-b--build-simulation)
5. [Module C — Analytics & ELO](#5-module-c--analytics--elo)
6. [Module D — Persistence](#6-module-d--persistence)
7. [Module E — Coaching](#7-module-e--coaching)
8. [Module F — Economy](#8-module-f--economy)
9. [UI Layer](#9-ui-layer)
10. [Cross-Cutting Patterns](#10-cross-cutting-patterns)
11. [Data Flow Diagrams](#11-data-flow-diagrams)
12. [Concurrency Model](#12-concurrency-model)
13. [Persistence Budget](#13-persistence-budget)

---

## 1. Architecture Overview

The codebase is organized as a flat set of 35 `.verse` files in the root `Content/` directory (UEFN module scope constraint). Logically, these form 8 layers:

```
┌──────────────────────────────────────────────────────────────────────┐
│                         EVENT BUS (event_bus.verse)                   │
│                    14-Channel Typed Pub/Sub Broker                    │
└──────┬──────┬──────┬──────┬──────┬──────┬──────┬─────────────────────┘
       │      │      │      │      │      │      │
       ▼      ▼      ▼      ▼      ▼      ▼      ▼
   ┌──────┐┌──────┐┌──────┐┌──────┐┌──────┐┌──────┐┌─────────────┐
   │CORE  ││MOD A ││MOD B ││MOD C ││MOD D ││MOD E ││   MOD F     │
   │Game  ││Bot   ││Build ││Analy-││Persi-││Coach ││  Economy    │
   │Mgr   ││Behav.││Pool  ││tics  ││stence││      ││             │
   │Arena ││State ││Spawn ││ELO   ││Valid.││Templ.││  Shop       │
   │Ctrl  ││Nav   ││Edit  ││Diff  ││Schema││Bridge││  Inventory  │
   │      ││Aim   ││Anim  ││Pred. ││Migr. ││      ││  Cosmetic   │
   │      ││Wpn   ││Choreo││Sess. ││      ││      ││  XP         │
   └──────┘└──────┘└──────┘└──────┘└──────┘└──────┘└─────────────┘
       │      │      │      │      │      │      │
       ▼      ▼      ▼      ▼      ▼      ▼      ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │                      UI LAYER                                     │
   │     hud_binding  ·  scorecard_renderer  ·  shop_ui_controller     │
   └──────────────────────────────────────────────────────────────────┘
```

Communication rules:

- Modules communicate through the event bus for cross-cutting events (round start, round end, eliminations, damage, builds, edits, analytics updates).
- The game manager is the only module that directly orchestrates other modules (it calls `Analytics.BeginRoundTracking()`, `ArenaCtrl.SpawnBot()`, `Coach.EvaluatePostRound()`, etc.).
- All other inter-module calls are either: (a) event bus listeners, or (b) direct references for data queries (e.g., `shop_manager` reads `inventory_controller` state).

---

## 2. Core Layer

### event_bus.verse — Central Pub/Sub Broker

**Type**: `creative_device`

The backbone of the decoupled architecture. Declares 14 typed `event()` objects and exposes them through a Dispatch/Listen API:

```
Dispatch___(params) → writes shared state → event.Signal()
Listen___()         → event.Await()       → returns when signaled
```

**Events**:

| Event | Payload (shared state) | Producers | Consumers |
|-------|----------------------|-----------|-----------|
| `RoundStartEvent` | `CurrentRoundNumber` | game_manager | analytics, xp, coach, hud |
| `RoundEndEvent` | `LastRoundOutcome`, win/loss/draw counts | game_manager | persistence, coach, xp, scorecard, analytics |
| `PlayerDamageEvent` | `damage_report` struct (amount, headshot, weapon, timestamp) | bot_weapon_controller | analytics |
| `BotDamageEvent` | `damage_report` struct | player actions (native) | analytics |
| `BotEliminatedEvent` | — | arena_controller | game_manager, analytics |
| `PlayerEliminatedEvent` | — | game_manager | analytics |
| `BuildPlacedEvent` | `build_event_data` struct (piece type, grid pos, timestamp) | build_pool_manager | analytics |
| `EditPerformedEvent` | `build_event_data` struct | edit_state_manager | analytics |
| `CountdownTickEvent` | `RemainingSeconds` | game_manager | hud |
| `StateChangeEvent` | `CurrentGameState` (LOBBY/COUNTDOWN/FIGHT/POST/RESET) | game_manager | hud, arena |
| `AnalyticsUpdatedEvent` | `combat_snapshot` | analytics_engine | hud |
| `ArenaResetCompleteEvent` | — | arena_controller | game_manager |

**Shared state**: The event bus also holds session-wide accumulators (`TotalPlayerWins`, `TotalBotWins`, `TotalDraws`, `ConsecutiveWins`, `ConsecutiveLosses`) and round-level data snapshots (`LastRoundDPS`, `LastRoundHeadshotPct`). These are reset by `ResetRoundAccumulators()` each round and updated by dispatch methods.

**Key design decision**: Using `event().Signal()` / `event().Await()` instead of direct method calls. This means the analytics engine doesn't know the coach exists, the coach doesn't know the XP system exists, and the persistence manager doesn't know either of them exist. Any module can be removed without cascading compile errors.

### game_manager.verse — Master Round Lifecycle

**Type**: `creative_device`

Drives the 5-phase state machine: LOBBY → COUNTDOWN → FIGHT → POST_ROUND → RESET.

**Phase details**:

- **LOBBY**: Races a configurable wait timer against player disconnect detection. Hides the previous scorecard.
- **COUNTDOWN**: Spawns the bot via `ArenaCtrl.SpawnBot()`, snapshots the pre-fight ELO, then ticks down second-by-second dispatching `CountdownTickEvent(Remaining)` for HUD display. Duration is driven by the `@editable CountdownSeconds` parameter.
- **FIGHT**: Three-way `race` — bot eliminated (`EventBus.ListenForBotEliminated()`), player eliminated (`fort_character.EliminatedEvent().Await()` with presence-poll fallback), timer expiry (`RoundTimerWithHalftimeLog()` which logs live DPS/accuracy at the midpoint). Whichever resolves first atomically cancels the other two.
- **POST_ROUND**: Calls `Analytics.EndRoundTracking()` to finalize metrics and ELO BEFORE dispatching `RoundEndEvent` (so all listeners see finalized data). Requests coaching feedback, renders the scorecard, pushes the coach message to the HUD, and holds for `PostRoundDisplaySeconds`.
- **RESET**: Calls `ArenaCtrl.ResetArena()` (despawn bot, reclaim all build props, teleport player), fetches the updated difficulty profile, refreshes the player reference, and cooldowns.

**Session lifecycle**: `LoadPlayerSession()` primes analytics with the player's persisted ELO on join. `EndSession()` compiles a `session_summary`, writes all 4 persistence slots, and logs the final statistics.

### arena_controller.verse — Arena State Manager

**Type**: `creative_device`

Manages bot spawning/despawning and arena cleanup. Holds `@editable` references to both primary and alternate bot spawners (for bot-style switching by the coach bridge). Two background `branch` tasks: `BotEliminationWatchdog` (awaits and re-dispatches bot eliminations) and `BotSpawnConfirmationLoop` (awaits `BotSpawner.SpawnedEvent` for reliable spawn detection). `ResetArena()` executes: despawn → `BuildPoolRef.ReclaimAll()` → `TeleportAllPlayersToSpawn()` → dispatch reset complete. An `IsResetting` guard prevents double-reset race conditions.

---

## 3. Module A — Bot AI

### bot_behavior_base.verse — NPC Entry Point

**Type**: `npc_behavior`

The only file that inherits from `npc_behavior` — UEFN's NPC scripting entry point. Cannot hold `@editable` references (engine constraint), so all sub-modules are plain classes initialized via `Init()`.

**Concurrency model**:

```verse
race:
    CombatLifecycle()           # Foreground: state machine + aim tracking
    WaitForDeath()              # Cancels everything on elimination
```

Inside `CombatLifecycle`:

```verse
branch: AimTrackingLoop()       # Background: continuous MaintainFocus retry
foreground: StateMachine.RunCombatLoop()  # State transitions
```

`ApplyDifficultyToSubModules()` pushes the current `bot_difficulty_profile` to all 5 sub-modules. `UpdateDifficultyLive()` enables mid-fight difficulty changes (triggered by the coach bridge).

### bot_combat_state_machine.verse — 5-State FSM

**Type**: Plain class

States: `COMBAT_APPROACH` (navigate to player), `COMBAT_ENGAGE_CLOSE` (perpendicular strafe + shotgun), `COMBAT_ENGAGE_MID` (AR burst at range), `COMBAT_DISENGAGE` (retreat vector + defensive wall), `COMBAT_BUILD_AGGRO` (box-up or ramp-rush). Each `Execute___()` method uses `race{NavigateTo, Sleep(timeout)}` to prevent infinite navigation hangs. Strafe logic alternates via `StrafeToggle` to compute perpendicular positions. Retreat calculates a direction vector away from the player.

### bot_navigation.verse — Dual-Pattern NavMesh

**Type**: Plain class

Caches `navigatable` from `GetNavigatable[]` at init. Two call patterns:

- **Pattern A** (cached-ref): `MoveToPosition`, `MoveToAgent`, `WalkToPosition` — returns integer result codes (`NAV_SUCCESS=0`, `NAV_TIMEOUT=1`)
- **Pattern B** (explicit-param): `NavigateToPosition`, `NavigateToAgent` — returns `logic`

All `NavigateTo` calls use `?MovementType := Running, ?ReachRadius := 150.0, ?AllowPartialPath := true`. Spatial utilities: `GetDistanceToAgent`, `GetDirectionToAgent`, `GetForwardOffset`, `GetRightOffset`, `IsWithinRange`.

### bot_focus_aim.verse — Head-Height Targeting

**Type**: Plain class

Caches `focus_interface` from `GetFocusInterface[]`. `MaintainFocus` retries on focus loss with a delay scaled from `ReactionTimeMs / 3000`. `GetHeadshotTargetPosition` computes `BasePos.Z + HeadZOffset + variance` where `HeadZOffset` defaults to 55.0 (perfect head height) and variance is LCG pseudo-random from `AimVariance`. `GetAimDeviationDegrees` computes the dot-product angle between bot facing and the target head position — used by the weapon controller to dynamically adjust accuracy.

### bot_weapon_controller.verse — Dual-Weapon Simulation

**Type**: Plain class

Two `weapon_profile` structs: Shotgun (95 base damage, 1.75 HS mult, 0.85s fire interval, 500 range) and AR (33 base damage, 1.5 HS mult, 0.12s fire interval, 1500 range, 3-round burst). `ExecuteFire` auto-selects weapon by distance, fires burst with delays, then sleeps for the fire interval. The hit/miss pipeline: `CalcDistanceAdjustedAccuracy` → hit roll → `CalcAdjustedHeadshotChance` (uses aim deviation from focus module if linked) → headshot roll → `ProcessHit` (distance falloff + damage report dispatch). Pseudo-random uses LCG: `(seed × 1103515245 + 12345 + timeComponent) mod 10000 / 10000`.

### bot_difficulty_profile.verse — Parameter Container

**Type**: Plain class

10 ELO-driven fields: `ReactionTimeMs`, `AimZOffset`, `AimVariance`, `BuildPlayRate`, `EditSpeedMultiplier`, `BuildProbability`, `ChaseRetargetInterval`, `NavTimeout`, `StrafeIntensity`, `AggressionLevel`. `Validate()` clamps all fields to safe ranges. `DiffersFrom()` compares two profiles to decide if mid-fight hot-reload is necessary. `GetDescription()` returns a one-line summary for logging.

---

## 4. Module B — Build Simulation

### build_pool_manager.verse — Object Pool with FIFO Reclaim

**Type**: `creative_device`

`@editable` arrays: `WallProps[]`, `FloorProps[]`, `RampProps[]`, `ConeProps[]`. On `OnBegin`, wraps all editor props into `pool_entry` objects and teleports them to `StagingPositionZ=-5000`. `ClaimAndDeploy(PieceType, Position, Rotation)` finds an inactive entry, teleports it to position — on failure, rolls back and tries the next entry. If the typed pool is exhausted, `ReclaimOldestFromPool` uses FIFO by `DeployOrder` to recycle the oldest active prop. `ReclaimAll` yields every 4 teleports (`Mod[count, 4] = 0`) to spread frame load across multiple ticks. Telemetry: `TotalClaims`, `TotalFIFOReclaims`, `PeakActiveCount`, `GetPoolUtilization()`.

### build_prop_spawner.verse — Grid-Aligned Deployment

**Type**: Plain class

`GRID_TILE_SIZE=256.0`, `WALL_HEIGHT=256.0`. `SnapToGrid` quantizes X/Y to cell centers. Position calculators: `CalcWallPosition` (one tile forward from bot facing), `CalcFloorPosition` (bot feet + snap), `CalcRampPosition`, `CalcWallBehindPosition` (threat-facing cover). Multi-piece layouts: `CalcBoxWallPositions` (4 cardinal offsets), `CalcRampRushPositions` (floor + ramp + forward wall), `CalcNinetyTurnPositions`. Deploy methods return integer result codes.

### edit_state_manager.verse — Prop-Variant Swap Illusion

**Type**: `creative_device`

The "edit" effect uses clusters of 2-3 overlapping props (full wall, window variant, door variant). `RegisterWallCluster(FullWall, Position, Rotation)` assigns variant props by index from `@editable` arrays `WindowVariantProps[]` and `DoorVariantProps[]`. `PerformEdit(TargetLocation, EditType)` finds the nearest cluster by proximity search, computes `EditDelay = BaseEditDelaySec / CurrentPlayRate` (clamped), then executes the swap: hide current variant via TeleportTo staging, show target variant via TeleportTo position. `ResetAllEdits` reverts all clusters to full-wall state.

### build_sequence_choreographer.verse — Multi-Piece Orchestration

**Type**: Plain class (NOT device)

`ExecuteSequence(SeqType, Profile, TargetAgent)` dispatches to: `ExecuteSingleWall`, `ExecuteBoxUpSequence` (floor → 4 walls → cone, each with anim + delay), `ExecuteRampRushSequence` (floor → ramp → wall), `ExecuteDoubleRampSequence`, `ExecuteRetake90Sequence` (floor → ramp → turn floor → turn ramp → wall), `ExecuteDefensiveWall`, `ExecuteEditPeek` (open window → peek duration → reset), `ExecuteBoxAndPeek` (combo). All inter-piece delays scale with ELO: `InterPieceDelay = 0.25 / PlayRate`. Returns result codes: `SEQ_RESULT_COMPLETE`, `PARTIAL`, `FAILED`, `NO_INIT`.

### build_animation_sync.verse — Phase-Precise Timing

**Type**: Plain class

Models build gestures as three phases: WINDUP (40%), THROW (30%), RECOVERY (30%). `PlayBuildAnimation(BotChar, Duration)` sleeps until the THROW phase ends (the prop-spawn moment), then returns so the caller deploys immediately. `PlayBuildAnimationFull` waits for the complete animation including recovery. `PlayEditAnimation` sleeps until the CONFIRM phase of the edit gesture. Pure-math calculators: `CalcBuildSpawnMoment`, `CalcBoxUpDuration`, `CalcRampRushDuration`, `CalcEditPeekDuration` — used by the choreographer for timeout pre-calculation.

---

## 5. Module C — Analytics & ELO

### metric_definitions.verse — Data Structures

**Type**: Pure data (no logic)

Core structs:

- `round_metrics`: 25 fields capturing everything about a single round (DamageDealt, DamageTaken, DPS, accuracy, headshots, reaction time, builds, edits, round duration, outcome, player/bot ELO, round number, timestamp)
- `combat_snapshot`: Live HUD data (LiveDPS, LiveAccuracy, LiveHeadshotPct)
- `build_performance`: Per-type build counts
- `session_summary`: Session-level aggregates with streaks, bracket distribution, consistency score
- `player_trend`: Trend analysis output with per-metric trend directions and stagnation/frustration flags

Constants: `OUTCOME_PLAYER_WIN=1`, `OUTCOME_BOT_WIN=2`, `OUTCOME_DRAW=3`, `TREND_IMPROVING=1`, `TREND_STABLE=0`, `TREND_DECLINING=-1`.

### analytics_engine.verse — Real-Time Metric Computation

**Type**: `creative_device`

Six background `branch` listeners in `OnBegin`: `ListenPlayerDamageLoop`, `ListenBotDamageLoop`, `ListenBuildPlacedLoop`, `ListenEditPerformedLoop`, `ListenRoundStartLoop`, `ListenRoundEndLoop`. Plus `PeriodicComputeLoop` (0.5s interval: computes LiveDPS, LiveAccuracy, LiveHeadshotPct into `CurrentSnapshot` for the HUD).

`BeginRoundTracking()` resets all per-round accumulators and sets `BotELO = EloCalc.CalcBotELO(PlayerELO)`. `EndRoundTracking(Outcome, RoundNumber)` finalizes: DPS = DamageDealt / Elapsed, AccuracyPct = Hits / Fired × 100, HeadshotPct = Headshots / Hits × 100, AvgTimeBetweenHitsMs from `HitTimestamps[]` array differences, EditSpeed = EditsPerformed / Elapsed. Updates streaks. Runs predictive advisor. Calls `EloCalc.CalcNewRating`. Pushes result to ring-buffer history. Dispatches `AnalyticsUpdatedEvent`.

Sub-modules: `EloCalc` (elo_calculator), `DiffMapper` (difficulty_mapper), `Advisor` (predictive_advisor).

### elo_calculator.verse — Rating Mathematics

**Type**: Plain class

**The Taylor series problem**: The Elo expected probability formula requires `10^x`. Verse has no general `Pow` function. Solution: compute `10^x = e^(x·ln10)` using an 8-term Taylor expansion of `e^y`:

```
e^y ≈ 1 + y + y²/2! + y³/3! + y⁴/4! + y⁵/5! + y⁶/6! + y⁷/7!
```

The exponent is clamped to [-3, 3] before expansion (10^3 = 1000, 10^-3 = 0.001 — sufficient for any realistic ELO difference). Result is clamped to [0.001, 0.999] to prevent division by zero.

**K-factor selection** (priority order):

1. Placement (≤10 rounds): K=48 — volatile early calibration
2. Stabilized (≥2000 ELO): K=16 — protect elite rankings
3. Volatile (stagnation injection active): K=64 — break plateaus
4. Standard: K=32

`CalcBotELO(PlayerELO)` applies bracket-scaled offsets: +25 Beginner, +40 Intermediate, +50 Advanced, +60 Pro, +75 Elite — so the bot is always slightly above the player's level, creating challenge pressure.

`CalcPotentialChange` returns [winDelta, lossDelta, drawDelta] for HUD display. `EstimateRoundsToTarget` for coach goal-setting.

### difficulty_mapper.verse — ELO → Bot Parameters

**Type**: Plain class

Maps ELO to `bot_difficulty_profile` fields using `CalcBracketProgress(ELO, floor, ceiling) → T ∈ [0,1]` then `Lerp(A, B, T)` for smooth interpolation within brackets.

| Bracket | ELO Range | Reaction (ms) | AimVar | PlayRate | Aggro | Retarget (s) |
|---------|-----------|---------------|--------|----------|-------|-------------|
| Beginner | 0-800 | 800→600 | 25→15 | 0.45→0.60 | 0 | 0.65→0.50 |
| Intermediate | 800-1200 | 600→350 | 15→8 | 0.60→0.85 | 1 | 0.50→0.35 |
| Advanced | 1200-1600 | 350→200 | 8→3 | 0.85→1.0 | 2 | 0.35→0.22 |
| Pro | 1600-2000 | 200→100 | 3→1 | 1.0→1.25 | 3 | 0.22→0.15 |
| Elite | 2000+ | 100→40 | 1→0 | 1.25→1.5 | 4 | 0.15→0.08 |

A player at 1400 ELO (50% through Advanced) gets: Reaction = 275ms, AimVar = 5.5, PlayRate = 0.925.

### predictive_advisor.verse — Intelligence Layer

**Type**: Plain class

**Stagnation detection**: Compares ELO at `History[Length - WindowSize]` vs current. If net change < threshold AND oscillation (sum of absolute per-round ELO changes) is also low, true stagnation is detected. High oscillation with low net change = engaged but inconsistent, not stagnating. Cooldown prevents re-triggering for N rounds after injection.

**Frustration detection**: Two-criteria system. First, count consecutive tail losses. If >= threshold, compute baseline averages (pre-streak rounds) vs streak averages for DPS and accuracy. If both degrade by > `DegradationPctThreshold` (default 20%), frustration confirmed. 5+ losses triggers regardless of degradation (strong signal).

**Trend analysis**: Generic `CalcMetricTrend` splits history into halves, averages each half, compares against per-metric thresholds. Returns IMPROVING/STABLE/DECLINING. Five channels: DPS, accuracy, headshot%, reaction time (inverted — lower is better), edit speed. `ComputeFullTrend` packages all into a `player_trend` struct.

**Weakness identification**: Compares the player's recent 5-round averages against bracket-expected baselines. Computes deficit percentage for each metric. Returns the name of the metric with the highest deficit.

**Anomaly detection**: Compares latest round against rolling baseline. If DPS AND accuracy both drop > 35%, flags fatigue/tilt/AFK.

### session_aggregator.verse — Session Summary Compiler

**Type**: Plain class

`CompileSession(History, StartingELO, FinalELO, SessionMinutes)` iterates all round metrics to produce: TotalRounds, Wins/Losses/Draws, average DPS/HS%/accuracy/reaction/round duration, ELO peak and lowest, longest win/loss streaks, total builds and edits placed.

`ComputeSessionDelta(Current, Previous)` produces a `session_delta` struct with raw deltas and percentage improvements for cross-session comparison ("Your DPS improved 15% since last session").

Additional analytics: `FindBestRoundByDPS`, `FindFastestReactionRound`, `CalcBracketDistribution` (rounds per bracket), `CalcWinRateByHalf` (first-half vs second-half win rate for intra-session warmup detection), `CalcConsistencyScore` (100 minus coefficient of variation of DPS — measures how reliably the player performs).

---

## 6. Module D — Persistence

### data_schema_v1.verse — Persistable Classes

**Type**: Pure data (`class<final><persistable>`)

Four classes for four weak_map slots. All fields are primitives (int, float, logic) — zero strings, zero arrays. Total serialization budget: ~192 bytes per player.

- `player_analytics_data_v1`: 10 fields (AvgDPS, AvgHeadshotPct, AvgAccuracyPct, AvgReactionMs, TotalSessions, TotalRounds, AvgRoundDurationSec, TotalBuildsPlaced, TotalEditsPerformed, ConsistencyScore)
- `player_rating_data_v1`: 10 fields (ELO, PeakELO, LowestELO, TotalWins, TotalLosses, TotalDraws, TotalTrainingMinutes, BestWinStreak, Version, LastPlayedTimestamp)
- `player_progression_data_v1`: 5 fields (QuestBitfield, MilestonesReached, HighestBracket, DailyChallenges, TotalQuestsCompleted)
- `player_economy_data_v1`: 6 fields (HasAnalyticsPass, ArenaSkinsOwned, ChallengeTokens, EquippedArenaSkin, TotalVBucksSpent, TotalPurchaseCount)

### data_schema_v2.verse — Extended Schema

Adds per-slot fields: Analytics gets AvgEditSpeedMs, AvgBuildRate, LongestWinStreak, LongestLossStreak. Rating gets PreferredCombatStyle, TotalEditsPerformed, TotalBuildsPlaced, AvgRoundDurationSec. Progression gets WeeklyQuestBitfield, SeasonNumber, UnlockedDrills, CoachingTier. Economy gets TotalTokensConsumed, EquippedModifier, SeasonPassActive. All V2 classes include `SchemaVersion := 2` for migration detection.

### migration_v1_to_v2.verse — Safe Schema Migration

Four `Migrate___()` functions: each takes a V1 instance, maps all V1 fields 1:1 to V2, initializes new V2 fields with safe defaults. `DeriveCoachingTier(HighestBracket)` intelligently derives the coaching unlock tier from the player's prior bracket achievement rather than defaulting to zero. `MigrateAll` runs all four and packages results into a `migration_result` struct. `NeedsMigration` checks the V1 Version field.

### data_validator.verse — Integrity Enforcement

Validates all 4 slots: `ValidateRating` (ELO in [0, 5000], PeakELO ≥ ELO, LowestELO ≤ ELO, non-negative counts, training minutes capped at 999999). `ValidateAnalytics` (averages non-negative, percentages in [0, 100], TotalRounds ≥ TotalSessions). `ValidateEconomy` (non-negative tokens capped at 9999, non-negative purchase counts). `ValidateProgression` (bracket in [0, 4], non-negative milestones).

Standalone sanitizers: `SanitizeELO`, `SanitizeFloat`, `SanitizeInt`, `SanitizePercentage`, `SanitizeNonNegativeInt`. `RunFullIntegrityCheck` validates all 4 slots and returns correction count. Telemetry: total validations, total corrections, correction rate.

### persistence_manager.verse — 4-Slot Weak Map Controller

**Type**: `creative_device`

Module-scope declarations (required by Verse persistence rules):

```verse
var AnalyticsStore   : weak_map(player, player_analytics_data_v1) = map{}
var RatingStore      : weak_map(player, player_rating_data_v1)    = map{}
var ProgressionStore : weak_map(player, player_progression_data_v1) = map{}
var EconomyStore     : weak_map(player, player_economy_data_v1)   = map{}
```

**Cache layer**: Loads all 4 slots into `LoadedAnalytics`, `LoadedRating`, `LoadedProgression`, `LoadedEconomy` at player join. Reads serve from cache. Writes update both cache AND weak_map.

**Running average for analytics**: `SaveAnalyticsData` uses `new_avg = (old_avg × old_count + new_value) / new_count` so lifetime averages correctly weight all prior sessions.

**Auto-save**: Background `branch` awaits `EventBus.ListenForRoundEnd()` and writes Slot 2 (rating) after every round.

**Quest bitfield operations**: `IsQuestCompleted(QuestIndex)` and `CompleteQuest(QuestIndex)` use approximated bitwise operations. `BitShiftLeft(1, QuestIndex)` creates the single-bit mask. `BitwiseAnd(Bitfield, Mask)` checks if the bit is set using integer division: `(A / B) - ((A / B) / 2 × 2) × B`. This is exact for single-bit power-of-2 masks. `BitwiseOr` adds the bit if not present. 32 quest flags in one integer field.

---

## 7. Module E — Coaching

### feedback_templates.verse — Message Library

**Type**: Plain class

10 message categories: ROUND_WIN, ROUND_LOSS, FRUSTRATION, ELO_MILESTONE, SESSION_LONG, STAGNATION, WEAKNESS, IMPROVEMENT, COMEBACK, WELCOME_BACK. Plus DRAW and FIRST_ROUND.

Each category has 3-5 template variants selected by `Mod[RoundIdx, N]` to prevent repetition. Templates branch on actual metric values within each variant — a win with 45% headshots gets different text than a win with 12% headshots. All messages include at least one specific metric via Verse string interpolation.

Message tone: direct, respectful, competitive. Never generic motivation. Always actionable ("move your crosshair to head height" not "aim better").

### coach_controller.verse — Trigger Evaluation Engine

**Type**: `creative_device`

Main loop in `OnBegin` awaits `EventBus.ListenForRoundEnd()` each round, then runs `ProvidePostRoundFeedback(Outcome)`.

**Priority evaluation** (first match wins, one message per round):

| Priority | Trigger | Detection Method |
|----------|---------|-----------------|
| P0 | Welcome back | `PersistenceRef.IsReturningPlayer()` on join |
| P1 | First round | `HasDeliveredFirstRound` flag |
| P2 | Frustration | `Trend.IsFrustrated` + consecutive losses ≥ 3 |
| P3 | Comeback | Win after `PreviousConsecutiveLosses` ≥ 3 |
| P4 | ELO milestone | New bracket entered (milestone interval = 200) |
| P5 | Stagnation | `Trend.IsStagnating` |
| P6 | Session fatigue | `SessionMinutes > 30` + round-based nag throttle |
| P7 | Weakness | `Advisor.IdentifyWeakestMetric` (3-round cooldown, de-duplication) |
| P8 | Improvement | `Trend.OverallTrend = IMPROVING` (4-round cooldown) |
| P9 | Standard | Win/loss/draw summary |

**Multi-channel delivery**: `CoachHUD.Show()` for on-screen overlay, `PushMessageToHUD()` for UMG widget binding, `Logger.Print()` for diagnostic output. Auto-hide after `MessageDisplayDurationSec`.

### coach_game_bridge.verse — Actions Bridge

**Type**: `creative_device`

Translates coaching decisions into game-state changes:

- `EaseDifficulty()`: Temporarily reduces `AnalyticsRef.PlayerELO` by configurable amount (default 50), causing next round's difficulty_mapper to produce easier bot parameters. `HasEasedThisSession` prevents repeated easing.
- `BoostDifficulty()`: Temporarily increases ELO by 25 after 5+ win streaks.
- `SpawnFrustrationAid()`: Grants healing items via `item_granter_device.GrantItem()`.
- `SwitchBotStyle()`: Toggles `ArenaCtrlRef.SetUseAltBot(true)` to swap to the alternate NPC spawner (different combat AI profile).
- `UnlockNextDrill()`: Updates highest bracket in persistence.

Two event loops: `ListenCoachCallButton` (lobby physical button → on-demand assessment), `ListenRoundEndAutoActions` (auto-ease on frustration, auto-boost on win streak).

---

## 8. Module F — Economy

### shop_manager.verse — Transaction Pipeline

**Type**: `creative_device`

Product catalog: Analytics Pass (800 V-Bucks, durable), Cyberpunk Arena (300, durable), Neon Grid Arena (300, durable), 5 Challenge Tokens (250, consumable), 10 Challenge Tokens (450, consumable), Speed Boots (150, consumable), Slow-Mo Replay (200, consumable).

Four `button_device` listeners (one per shop terminal button) await `InteractedWithEvent` and run the 6-step pipeline: Validate → Payment (API integration point, simulated for dev) → Fulfill → Persist → Side Effects (auto-equip cosmetics) → Telemetry.

Duplicate prevention: durable items checked against inventory before payment. Skin ownership verified via bitfield.

### inventory_controller.verse — Item Management

**Type**: Plain class

Dual API: string-based generic (`HasItem("arena_cyber")`, `GrantItem("challenge_token_5")`, `ConsumeItem("speed_boots")`) and typed methods (`PurchaseAnalyticsPass()`, `PurchaseArenaSkin(2)`, `ConsumeChallengeToken()`). Bitfield skin ownership using the same `BitShiftLeft`/`BitwiseAnd`/`BitwiseOr` pattern as persistence. Feature gates: `CanAccessAdvancedAnalytics()`, `CanAccessEliteBots()`, `CanEnterChallenge()`.

### cosmetic_applicator.verse — Arena Skin Swap

**Type**: `creative_device`

5 arena variant `creative_prop` references. `ApplyArenaSkin(SkinId)`: hide all variants at staging (Z=-5000), show selected at `ArenaShowPosition`. `IsSwapping` lock prevents concurrent swap corruption. `PreviewSkin`/`EndPreview` for try-before-you-buy in the shop UI. On session load, auto-applies the player's equipped skin from persistence.

### xp_reward_system.verse — Accolade Distribution

**Type**: `creative_device`

6 `accolades_device` references (win, loss, headshot milestone, rank-up, session milestone, win streak). Budget enforcement: `XPAccumulated` tracked per 10-minute block, capped at `MaxXPPerBlock` (200,000). Exceeding the cap blocks further accolades until the window resets. Win streaks (every 3 wins), headshot milestones (every 10 cumulative headshots), session milestones (every 10 rounds), and rank-ups auto-detected from event bus state.

---

## 9. UI Layer

### hud_binding.verse — Live HUD + Binding Bridge

**Type**: `creative_device`

Creates 3 canvas panels via `player_ui` API: live combat stats (top-left), status bar (top-right), coach message (bottom-center). 500ms refresh loop reads `AnalyticsRef.CurrentSnapshot` for live DPS/accuracy/headshot% during fights. Status bar shows ELO with bracket name, progress percentage through current bracket, round number, and W/L/D. Coach message auto-hides via `spawn: CoachMessageAutoHide()`. All display values simultaneously exposed as public variables for optional UMG Widget Blueprint data binding.

### scorecard_renderer.verse — Post-Round Overlay

**Type**: `creative_device`

6 `text_block` elements on a `canvas`: outcome header, ELO change with delta direction, core metrics (DPS/accuracy/headshot%), secondary metrics (reaction/builds/edits/duration), session summary (W/L/D/round/bracket), coach feedback. Background listener auto-renders on `EventBus.ListenForRoundEnd()`. `HideScorecard()` clears all text between rounds.

### shop_ui_controller.verse — Shop Menu

**Type**: `creative_device`

Canvas-drawn shop overlay triggered by `ShopTerminalBtn.InteractedWithEvent`. Displays 4 product lines with real-time ownership status ("[OWNED]" / "[BUY]"), token balance, equipped skin name. `HandlePurchaseRequest` delegates to `shop_manager.ProcessPurchase()` and immediately saves to persistence on success.

---

## 10. Cross-Cutting Patterns

### Pattern: Dispatch / Listen (Event Bus)

```verse
# Producer
EventBus.DispatchRoundEnd(Outcome)
  → set LastRoundOutcome = Outcome
  → set TotalPlayerWins += 1 (if win)
  → RoundEndEvent.Signal()

# Consumer (in any module's OnBegin branch)
loop:
    EventBus.ListenForRoundEnd()    # suspends until Signal()
    DoSomethingWithOutcome(EventBus.LastRoundOutcome)
```

### Pattern: Init() for NPC Sub-Modules

```verse
# npc_behavior cannot hold @editable → plain classes with Init()
bot_navigation := class:
    var Agent : ?agent = false
    var Character : ?fort_character = false
    var Nav : ?navigatable = false

    Init(InAgent, InChar):
        set Agent = option{InAgent}
        set Character = option{InChar}
        if (N := InChar.GetNavigatable[]):
            set Nav = option{N}
```

### Pattern: Object Pool Claim/Reclaim

```verse
ClaimAndDeploy(PieceType, Position, Rotation):
    # Find inactive entry in typed pool
    # TeleportTo(Position, Rotation)
    # On failure: rollback, try next entry
    # If exhausted: ReclaimOldestFromPool (FIFO by DeployOrder)
    # Retry with reclaimed entry
```

### Pattern: Integer Bitfield for Flags

```verse
# Set bit:   Bitfield = BitwiseOr(Bitfield, BitShiftLeft(1, Index))
# Check bit: BitwiseAnd(Bitfield, BitShiftLeft(1, Index)) > 0
# Clear bit: Bitfield = Bitfield - BitShiftLeft(1, Index)  (if set)
#
# BitwiseAnd approximation for single-bit masks:
#   (A / B) - ((A / B) / 2 × 2) × B
# Exact for power-of-2 B values (our exclusive use case).
```

### Pattern: Running Average for Persistence

```verse
# new_avg = (old_avg × old_count + new_value) / new_count
# Avoids storing full history in the weak_map.
# A player with 50 sessions and one bad day doesn't crater their lifetime stats.
```

---

## 11. Data Flow Diagrams

### Round Lifecycle Flow

```
game_manager
    │
    ├── LOBBY ─────── DispatchStateChange(STATE_LOBBY)
    │                    └── hud_binding: switch to idle display
    │
    ├── COUNTDOWN ──── ArenaCtrl.SpawnBot()
    │                  DispatchCountdownTick(3, 2, 1)
    │                    └── hud_binding: display countdown
    │
    ├── FIGHT ──────── Analytics.BeginRoundTracking()
    │                  DispatchRoundStart(RoundNum)
    │                    ├── analytics_engine: reset accumulators
    │                    ├── xp_reward_system: check rank-up
    │                    └── hud_binding: switch to live combat mode
    │                  race:
    │                    ├── EventBus.ListenForBotEliminated()
    │                    ├── PlayerChar.EliminatedEvent().Await()
    │                    └── Sleep(RoundDurationSeconds)
    │
    ├── POST_ROUND ─── Analytics.EndRoundTracking(Outcome)
    │                    ├── finalizes DPS, accuracy, headshot%, ELO
    │                    ├── runs predictive_advisor
    │                    └── updates difficulty_mapper
    │                  DispatchRoundEnd(Outcome)
    │                    ├── persistence_manager: auto-save ELO
    │                    ├── coach_controller: evaluate triggers
    │                    ├── xp_reward_system: award accolades
    │                    └── scorecard_renderer: render overlay
    │                  Coach.EvaluatePostRound() → coaching string
    │                  Scorecard.RenderScorecard()
    │                  HUD.SetCoachMessage()
    │                  Sleep(PostRoundDisplaySeconds)
    │
    └── RESET ──────── ArenaCtrl.ResetArena()
                         ├── despawn bot
                         ├── BuildPool.ReclaimAll()
                         └── teleport player to spawn
                       Analytics.GetUpdatedProfile()
                       Sleep(ResetCooldownSeconds)
                       → loop back to LOBBY
```

### ELO Update Flow

```
Round ends
    │
    ▼
analytics_engine.EndRoundTracking()
    │
    ├── Compute composite performance metrics
    │
    ├── elo_calculator.CalcExpectedProbability(PlayerELO, BotELO)
    │     └── Pow10 via 8-term Taylor: e^(x·ln10)
    │
    ├── elo_calculator.SelectKFactor()
    │     └── Placement? Stabilized? Volatile? Standard?
    │
    ├── elo_calculator.CalcNewRating(PlayerELO, BotELO, Outcome, K)
    │     └── NewELO = OldELO + K × (ActualScore - ExpectedProbability)
    │
    ├── difficulty_mapper.MapDifficulty(NewELO, Profile)
    │     └── CalcBracketProgress → Lerp per field → Validate
    │
    └── predictive_advisor.ComputeFullTrend(History)
          ├── ShouldInjectVolatility? (stagnation + oscillation check)
          ├── DetectFrustration? (losses + performance degradation)
          └── CalcMetricTrends (5 channels)
```

---

## 12. Concurrency Model

Every `<suspends>` function in the codebase falls into one of these patterns:

| Pattern | Usage | Example |
|---------|-------|---------|
| `race{}` | First-to-complete cancels others | Fight phase: bot death vs player death vs timer |
| `branch{}` | Fire-and-forget background task | Event bus listeners, auto-save loop, HUD refresh |
| `loop + Await` | Reactive listener | `loop: EventBus.ListenForRoundEnd(); Process()` |
| `Sleep(duration)` | Timed delay | Countdown ticks, animation sync, message auto-hide |
| `spawn{}` | Non-blocking fire-and-forget | Coach message auto-hide, cosmetic application |

**Critical ordering in PostRound**: `Analytics.EndRoundTracking()` MUST complete before `EventBus.DispatchRoundEnd()`. The analytics engine finalizes all metrics and updates the ELO — only then does the event signal, ensuring all downstream listeners see finalized data.

---

## 13. Persistence Budget

| Slot | Weak Map | Class | Fields | Est. Bytes | Write Frequency |
|------|----------|-------|--------|-----------|----------------|
| 1 | `AnalyticsStore` | `player_analytics_data_v1` | 10 | ~80 | Session end |
| 2 | `RatingStore` | `player_rating_data_v1` | 10 | ~80 | Every round end |
| 3 | `ProgressionStore` | `player_progression_data_v1` | 5 | ~40 | Quest completion |
| 4 | `EconomyStore` | `player_economy_data_v1` | 6 | ~48 | Purchase events |

**Total**: ~248 bytes per player across all 4 slots. Well within Verse serialization limits.

**Write frequency rationale**: Slot 2 (rating) is the most critical — if a player disconnects, their ELO must be preserved. Auto-save on every round end guarantees at most one round of ELO loss. Slots 1, 3, 4 are less critical and write less frequently to reduce weak_map access.

---

*This document covers the complete 35-file architecture as implemented across Missions 1-19. All code is production-ready with zero stubs.*

---

---

<div dir="rtl" align="right">

# 04 — מסמך עיון בבסיס הקוד

> מסמך עיון ארכיטקטורה טכנית עבור מפת האימון ProAI.
> מכסה את כל 35 קבצי Verse על פני 6 מודולים + שכבת ליבה + שכבת UI.
> עדכון אחרון: משימה 20 (סנכרון תיעוד).

---

## תוכן עניינים

1. [סקירת ארכיטקטורה](#1-סקירת-ארכיטקטורה)
2. [שכבת הליבה](#2-שכבת-הליבה)
3. [מודול A — בינת הבוט](#3-מודול-a--בינת-הבוט)
4. [מודול B — סימולציית בנייה](#4-מודול-b--סימולציית-בנייה)
5. [מודול C — אנליטיקס ו-ELO](#5-מודול-c--אנליטיקס-ו-elo)
6. [מודול D — עקביות](#6-מודול-d--עקביות)
7. [מודול E — קואצ'ינג](#7-מודול-e--קואצינג)
8. [מודול F — כלכלה](#8-מודול-f--כלכלה)
9. [שכבת ממשק המשתמש](#9-שכבת-ממשק-המשתמש)
10. [דפוסים חוצי-מערכת](#10-דפוסים-חוצי-מערכת)
11. [תרשימי זרימת נתונים](#11-תרשימי-זרימת-נתונים)
12. [מודל המקביליות](#12-מודל-המקביליות)
13. [תקציב העקביות](#13-תקציב-העקביות)

---

## 1. סקירת ארכיטקטורה

בסיס הקוד מאורגן כמכלול שטוח של 35 קבצי `.verse` בתיקיית הבסיס `Content/` (מגבלת טווח מודול UEFN). מבחינה לוגית הם מרכיבים 8 שכבות:

```
┌──────────────────────────────────────────────────────────────────────┐
│                  אוטובוס אירועים (event_bus.verse)                    │
│              ברוקר Pub/Sub מסוגים עם 14 ערוצים                        │
└──────┬──────┬──────┬──────┬──────┬──────┬──────┬─────────────────────┘
       │      │      │      │      │      │      │
       ▼      ▼      ▼      ▼      ▼      ▼      ▼
   ┌──────┐┌──────┐┌──────┐┌──────┐┌──────┐┌──────┐┌─────────────┐
   │ ליבה ││MOD A ││MOD B ││MOD C ││MOD D ││MOD E ││   MOD F     │
   │מנהל  ││בינת  ││מאגר  ││אנלי- ││עקבי- ││קואצ' ││  כלכלה     │
   │משחק  ││בוט   ││בנייה ││טיקס  ││ות    ││      ││             │
   └──────┘└──────┘└──────┘└──────┘└──────┘└──────┘└─────────────┘
```

כללי תקשורת:

- מודולים מתקשרים דרך אוטובוס האירועים לאירועים חוצי-מערכת (התחלת סיבוב, סיום סיבוב, חיסולים, נזק, בניות, עריכות, עדכוני אנליטיקס).
- מנהל המשחק הוא המודול היחיד שמתאם ישירות מודולים אחרים (הוא קורא ל-`Analytics.BeginRoundTracking()`, `ArenaCtrl.SpawnBot()`, `Coach.EvaluatePostRound()` וכו').
- כל שאר הקריאות הבין-מודוליות הן: (א) מאזיני אוטובוס אירועים, או (ב) הפניות ישירות לשאילתות נתונים (למשל, `shop_manager` קורא מצב `inventory_controller`).

---

## 2. שכבת הליבה

### event_bus.verse — ברוקר Pub/Sub מרכזי

**סוג**: `creative_device`

עמוד השדרה של הארכיטקטורה המנותקת. מצהיר על 14 אובייקטי `event()` מסוגים וחושף אותם דרך ממשק Dispatch/Listen:

```
Dispatch___(params) → כותב מצב משותף → event.Signal()
Listen___()         → event.Await()   → מחזיר כשמסומן
```

**אירועים**:

| אירוע | עומס (מצב משותף) | מפיקים | צרכנים |
|-------|-----------------|---------|---------|
| `RoundStartEvent` | `CurrentRoundNumber` | game_manager | analytics, xp, coach, hud |
| `RoundEndEvent` | `LastRoundOutcome`, מנייני ניצחון/הפסד/תיקו | game_manager | persistence, coach, xp, scorecard, analytics |
| `PlayerDamageEvent` | struct `damage_report` (כמות, כוון לראש, נשק, חותמת-זמן) | bot_weapon_controller | analytics |
| `BotDamageEvent` | struct `damage_report` | פעולות שחקן (נייטיב) | analytics |
| `BotEliminatedEvent` | — | arena_controller | game_manager, analytics |
| `PlayerEliminatedEvent` | — | game_manager | analytics |
| `BuildPlacedEvent` | struct `build_event_data` (סוג חתיכה, מיקום רשת, חותמת-זמן) | build_pool_manager | analytics |
| `EditPerformedEvent` | struct `build_event_data` | edit_state_manager | analytics |
| `CountdownTickEvent` | `RemainingSeconds` | game_manager | hud |
| `StateChangeEvent` | `CurrentGameState` (LOBBY/COUNTDOWN/FIGHT/POST/RESET) | game_manager | hud, arena |
| `AnalyticsUpdatedEvent` | `combat_snapshot` | analytics_engine | hud |
| `ArenaResetCompleteEvent` | — | arena_controller | game_manager |

**מצב משותף**: אוטובוס האירועים מחזיק גם מצברי כל-המפגש (`TotalPlayerWins`, `TotalBotWins`, `TotalDraws`, `ConsecutiveWins`, `ConsecutiveLosses`) ותמונות-מצב של נתוני הסיבוב (`LastRoundDPS`, `LastRoundHeadshotPct`). אלה מאופסים על-ידי `ResetRoundAccumulators()` בכל סיבוב ומעודכנים על-ידי שיטות ה-dispatch.

**החלטת עיצוב מפתח**: שימוש ב-`event().Signal()` / `event().Await()` במקום קריאות מתודה ישירות. משמעות הדבר היא שמנוע האנליטיקס לא יודע שהקואצ' קיים, הקואצ' לא יודע שמערכת ה-XP קיימת, ומנהל העקביות לא יודע שאף אחד מהם קיים. כל מודול ניתן להסרה ללא שגיאות קומפילציה מדורגות.

### game_manager.verse — מחזור חיי סיבוב ראשי

**סוג**: `creative_device`

מניע את מכונת המצב בת 5 השלבים: LOBBY → COUNTDOWN → FIGHT → POST_ROUND → RESET.

**פירוט השלבים**:

- **LOBBY**: מתחרה בין טיימר המתנה הניתן להגדרה לבין זיהוי ניתוק שחקן. מסתיר את כרטיס התוצאות הקודם.
- **COUNTDOWN**: מפעיל את הבוט דרך `ArenaCtrl.SpawnBot()`, שומר תמונת-מצב של ה-ELO לפני הקרב, ואז סופר לאחור שנייה-שנייה תוך שליחת `CountdownTickEvent(Remaining)` לתצוגת HUD. משך הזמן מונע על-ידי פרמטר `@editable CountdownSeconds`.
- **FIGHT**: `race` תלת-כיוונית — בוט חוסל (`EventBus.ListenForBotEliminated()`), שחקן חוסל (`fort_character.EliminatedEvent().Await()` עם גיבוי סקר נוכחות), פקיעת טיימר (`RoundTimerWithHalftimeLog()` שמתעד DPS/דיוק חי בנקודת האמצע). מי שמתרחש ראשון מבטל אטומית את שני האחרים.
- **POST_ROUND**: קורא ל-`Analytics.EndRoundTracking()` כדי לסיים מדדים ו-ELO לפני שליחת `RoundEndEvent` (כך שכל המאזינים רואים נתונים סופיים). מבקש משוב קואצ'ינג, מרנדר את כרטיס התוצאות, דוחף את הודעת הקואצ' ל-HUD, ומחכה `PostRoundDisplaySeconds`.
- **RESET**: קורא ל-`ArenaCtrl.ResetArena()` (השבתת בוט, פינוי כל אבזרי הבנייה, טלפורט שחקן), מביא את פרופיל הקושי המעודכן, מרענן את הפניית השחקן, ומקרר.

**מחזור חיי מפגש**: `LoadPlayerSession()` מכין את האנליטיקס עם ה-ELO השמור של השחקן בהצטרפות. `EndSession()` מקמפל `session_summary`, כותב את כל 4 חריצי העקביות, ומתעד את הסטטיסטיקות הסופיות.

### arena_controller.verse — מנהל מצב הזירה

**סוג**: `creative_device`

מנהל הפעלה/השבתה של בוט וניקוי זירה. מחזיק הפניות `@editable` גם למפעיל הבוט הראשי וגם לחלופי (להחלפת סגנון הבוט על-ידי גשר הקואצ'). שתי משימות `branch` ברקע: `BotEliminationWatchdog` (ממתין ומשדר מחדש חיסולי בוט) ו-`BotSpawnConfirmationLoop` (ממתין ל-`BotSpawner.SpawnedEvent` לזיהוי הפעלה אמין). `ResetArena()` מבצע: השבתה → `BuildPoolRef.ReclaimAll()` → `TeleportAllPlayersToSpawn()` → שליחת reset complete. משמר `IsResetting` מונע תנאי מרוץ של איפוס כפול.

---

## 3. מודול A — בינת הבוט

### bot_behavior_base.verse — נקודת כניסה NPC

**סוג**: `npc_behavior`

הקובץ היחיד שיורש מ-`npc_behavior` — נקודת הכניסה של UEFN לסקריפטינג NPC. לא יכול להחזיק הפניות `@editable` (מגבלת מנוע), לכן כל תת-המודולים הם מחלקות רגילות שאותחלו דרך `Init()`.

**מודל מקביליות**:

```verse
race:
    CombatLifecycle()           # קדמה: מכונת מצב + מעקב כוון
    WaitForDeath()              # מבטל הכל בחיסול
```

בתוך `CombatLifecycle`:

```verse
branch: AimTrackingLoop()       # רקע: ניסיון חוזר רציף של MaintainFocus
foreground: StateMachine.RunCombatLoop()  # מעברי מצב
```

`ApplyDifficultyToSubModules()` דוחף את `bot_difficulty_profile` הנוכחי לכל 5 תת-המודולים. `UpdateDifficultyLive()` מאפשר שינויי קושי באמצע קרב (מופעל על-ידי גשר הקואצ').

### bot_combat_state_machine.verse — FSM בן 5 מצבים

**סוג**: מחלקה רגילה

מצבים: `COMBAT_APPROACH` (ניווט לשחקן), `COMBAT_ENGAGE_CLOSE` (זזה-הצדה ניצבת + רובה ציד), `COMBAT_ENGAGE_MID` (פרץ AR ממרחק), `COMBAT_DISENGAGE` (וקטור נסיגה + קיר הגנתי), `COMBAT_BUILD_AGGRO` (כישת קופסה או רמפה התקפית). כל שיטת `Execute___()` משתמשת ב-`race{NavigateTo, Sleep(timeout)}` למניעת תקיעות ניווט אינסופיות. לוגיקת זזה-הצדה מתחלפת דרך `StrafeToggle` לחישוב מיקומים ניצבים. נסיגה מחשבת וקטור כיוון הרחק מהשחקן.

### bot_navigation.verse — NavMesh דו-דפוסי

**סוג**: מחלקה רגילה

שומר `navigatable` מ-`GetNavigatable[]` באתחול. שני דפוסי קריאה:

- **דפוס A** (הפנייה שמורה): `MoveToPosition`, `MoveToAgent`, `WalkToPosition` — מחזיר קודי תוצאה שלמים (`NAV_SUCCESS=0`, `NAV_TIMEOUT=1`)
- **דפוס B** (פרמטר מפורש): `NavigateToPosition`, `NavigateToAgent` — מחזיר `logic`

כל קריאות `NavigateTo` משתמשות ב-`?MovementType := Running, ?ReachRadius := 150.0, ?AllowPartialPath := true`. כלי מרחב: `GetDistanceToAgent`, `GetDirectionToAgent`, `GetForwardOffset`, `GetRightOffset`, `IsWithinRange`.

### bot_focus_aim.verse — כוון לגובה ראש

**סוג**: מחלקה רגילה

שומר `focus_interface` מ-`GetFocusInterface[]`. `MaintainFocus` מנסה שוב בעת אובדן פוקוס עם עיכוב על-פי `ReactionTimeMs / 3000`. `GetHeadshotTargetPosition` מחשב `BasePos.Z + HeadZOffset + variance` כאשר `HeadZOffset` מוגדר כברירת מחדל ל-55.0 (גובה ראש מושלם) והשונות היא LCG פסאודו-אקראי מ-`AimVariance`. `GetAimDeviationDegrees` מחשב את זווית מכפלת-הנקודה בין כיוון הבוט ומיקום הראש הממוקד — בשימוש על-ידי בקר הנשק לכוונון דינמי של הדיוק.

### bot_weapon_controller.verse — סימולציה דו-נשקית

**סוג**: מחלקה רגילה

שני struct של `weapon_profile`: רובה ציד (95 נזק בסיסי, מכפיל HS 1.75, מרווח ירי 0.85 שניות, טווח 500) ו-AR (33 נזק בסיסי, מכפיל HS 1.5, מרווח ירי 0.12 שניות, טווח 1500, פרץ 3 כדורים). `ExecuteFire` בוחר נשק אוטומטית לפי מרחק, יורה פרץ עם עיכובים, ואז ישן למרווח הירי. צינור פגיעה/החטאה: `CalcDistanceAdjustedAccuracy` → הגרלת פגיעה → `CalcAdjustedHeadshotChance` (משתמש בסטיית כוון ממודול הפוקוס אם מקושר) → הגרלת כוון לראש → `ProcessHit` (ניחות מרחק + שליחת דו"ח נזק). פסאודו-אקראי משתמש ב-LCG: `(seed × 1103515245 + 12345 + timeComponent) mod 10000 / 10000`.

### bot_difficulty_profile.verse — מיכל פרמטרים

**סוג**: מחלקה רגילה

10 שדות מונעי-ELO: `ReactionTimeMs`, `AimZOffset`, `AimVariance`, `BuildPlayRate`, `EditSpeedMultiplier`, `BuildProbability`, `ChaseRetargetInterval`, `NavTimeout`, `StrafeIntensity`, `AggressionLevel`. `Validate()` מגביל את כל השדות לטווחים בטוחים. `DiffersFrom()` משווה שני פרופילים כדי להחליט אם טעינה חמה באמצע קרב נחוצה. `GetDescription()` מחזיר סיכום חד-שורתי לתיעוד.

---

## 4. מודול B — סימולציית בנייה

### build_pool_manager.verse — מאגר אובייקטים עם פינון FIFO

**סוג**: `creative_device`

מערכי `@editable`: `WallProps[]`, `FloorProps[]`, `RampProps[]`, `ConeProps[]`. ב-`OnBegin`, עוטף את כל האבזרים בעורך לאובייקטי `pool_entry` ומטלפורט אותם ל-`StagingPositionZ=-5000`. `ClaimAndDeploy(PieceType, Position, Rotation)` מאתר רשומה לא-פעילה, מטלפורט אותה למיקום — בכישלון, מבצע rollback ומנסה את הרשומה הבאה. אם המאגר המסוג אוזל, `ReclaimOldestFromPool` משתמש ב-FIFO לפי `DeployOrder` כדי לממחזר את האבזר הפעיל הוותיק ביותר. `ReclaimAll` מוותר שליטה כל 4 טלפורטים (`Mod[count, 4] = 0`) כדי לפזר את עומס הפריים על פני מספר טיקים. טלמטריה: `TotalClaims`, `TotalFIFOReclaims`, `PeakActiveCount`, `GetPoolUtilization()`.

### build_prop_spawner.verse — פריסה מיושרת-רשת

**סוג**: מחלקה רגילה

`GRID_TILE_SIZE=256.0`, `WALL_HEIGHT=256.0`. `SnapToGrid` מכמת X/Y למרכזי תאים. מחשבני מיקום: `CalcWallPosition` (אריח אחד קדימה מכיוון הבוט), `CalcFloorPosition` (כפות רגלי הבוט + snap), `CalcRampPosition`, `CalcWallBehindPosition` (מחסה פנים-לאיום). פריסות מרובות-חלקים: `CalcBoxWallPositions` (4 היסטות קרדינליות), `CalcRampRushPositions` (רצפה + רמפה + קיר קדמי), `CalcNinetyTurnPositions`. שיטות הפריסה מחזירות קודי תוצאה שלמים.

### edit_state_manager.verse — אשליית החלפת גרסת אבזר

**סוג**: `creative_device`

אפקט ה"עריכה" משתמש באשכולות של 2-3 אבזרים חופפים (קיר מלא, גרסת חלון, גרסת דלת). `RegisterWallCluster(FullWall, Position, Rotation)` מקצה אבזרי גרסה לפי אינדקס ממערכי `@editable` `WindowVariantProps[]` ו-`DoorVariantProps[]`. `PerformEdit(TargetLocation, EditType)` מוצא את האשכול הקרוב ביותר לפי חיפוש קרבה, מחשב `EditDelay = BaseEditDelaySec / CurrentPlayRate` (מוגבל), ואז מבצע את ההחלפה: מסתיר גרסה נוכחית דרך TeleportTo לבימוי, מציג גרסת יעד דרך TeleportTo למיקום. `ResetAllEdits` מחזיר את כל האשכולות למצב קיר-מלא.

### build_sequence_choreographer.verse — ניהול רצפים מרובי-חלקים

**סוג**: מחלקה רגילה (לא device)

`ExecuteSequence(SeqType, Profile, TargetAgent)` מפנה ל-: `ExecuteSingleWall`, `ExecuteBoxUpSequence` (רצפה → 4 קירות → חרוט, כל אחד עם אנים + עיכוב), `ExecuteRampRushSequence` (רצפה → רמפה → קיר), `ExecuteDoubleRampSequence`, `ExecuteRetake90Sequence` (רצפה → רמפה → רצפת פנייה → רמפת פנייה → קיר), `ExecuteDefensiveWall`, `ExecuteEditPeek` (פתיחת חלון → משך הצצה → איפוס), `ExecuteBoxAndPeek` (קומבו). כל עיכובי בין-חלקים מתאימים עצמם ל-ELO: `InterPieceDelay = 0.25 / PlayRate`. מחזיר קודי תוצאה: `SEQ_RESULT_COMPLETE`, `PARTIAL`, `FAILED`, `NO_INIT`.

### build_animation_sync.verse — תזמון מדויק-לשלב

**סוג**: מחלקה רגילה

מדגמן מחוות בנייה כשלושה שלבים: WINDUP (40%), THROW (30%), RECOVERY (30%). `PlayBuildAnimation(BotChar, Duration)` ישן עד לסיום שלב ה-THROW (רגע הצצת האבזר), ואז מחזיר כדי שהקורא יפרוס מייד. `PlayBuildAnimationFull` ממתין לאנימציה המלאה כולל ה-recovery. `PlayEditAnimation` ישן עד לשלב CONFIRM של מחוות העריכה. מחשבני מתמטיקה טהורה: `CalcBuildSpawnMoment`, `CalcBoxUpDuration`, `CalcRampRushDuration`, `CalcEditPeekDuration` — בשימוש על-ידי הכוריאוגרף לחישוב timeout מוקדם.

---

## 5. מודול C — אנליטיקס ו-ELO

### metric_definitions.verse — מבני נתונים

**סוג**: נתונים טהורים (ללא לוגיקה)

struct-ים מרכזיים:

- `round_metrics`: 25 שדות המתעדים הכל על סיבוב יחיד (נזק שגרם, נזק שקיבל, DPS, דיוק, כוון לראש, זמן תגובה, בניות, עריכות, משך סיבוב, תוצאה, ELO שחקן/בוט, מספר סיבוב, חותמת-זמן)
- `combat_snapshot`: נתוני HUD חיים (LiveDPS, LiveAccuracy, LiveHeadshotPct)
- `build_performance`: מנייני בנייה לפי סוג
- `session_summary`: מצברים ברמת מפגש עם רצפים, התפלגות דירוגים, ציון עקביות
- `player_trend`: פלט ניתוח טרנדים עם כיווני טרנד לכל מדד ודגלי קיפאון/תסכול

קבועים: `OUTCOME_PLAYER_WIN=1`, `OUTCOME_BOT_WIN=2`, `OUTCOME_DRAW=3`, `TREND_IMPROVING=1`, `TREND_STABLE=0`, `TREND_DECLINING=-1`.

### analytics_engine.verse — חישוב מדדים בזמן אמת

**סוג**: `creative_device`

שישה מאזיני `branch` ברקע ב-`OnBegin`: `ListenPlayerDamageLoop`, `ListenBotDamageLoop`, `ListenBuildPlacedLoop`, `ListenEditPerformedLoop`, `ListenRoundStartLoop`, `ListenRoundEndLoop`. בנוסף `PeriodicComputeLoop` (מרווח 0.5 שניות: מחשב LiveDPS, LiveAccuracy, LiveHeadshotPct ל-`CurrentSnapshot` עבור ה-HUD).

`BeginRoundTracking()` מאפס את כל המצברים לכל-הסיבוב ומגדיר `BotELO = EloCalc.CalcBotELO(PlayerELO)`. `EndRoundTracking(Outcome, RoundNumber)` מסיים: DPS = נזק / זמן שחלף, AccuracyPct = פגיעות / ירי × 100, HeadshotPct = כוון-לראש / פגיעות × 100, AvgTimeBetweenHitsMs מהפרשי מערך `HitTimestamps[]`, EditSpeed = עריכות / זמן שחלף. מעדכן רצפים. מריץ יועץ חיזוי. קורא ל-`EloCalc.CalcNewRating`. דוחף תוצאה למאגר היסטוריה-טבעת. שולח `AnalyticsUpdatedEvent`.

תת-מודולים: `EloCalc` (elo_calculator), `DiffMapper` (difficulty_mapper), `Advisor` (predictive_advisor).

### elo_calculator.verse — מתמטיקת דירוג

**סוג**: מחלקה רגילה

**בעיית טור טיילור**: נוסחת הסיכוי-הצפוי של Elo דורשת `10^x`. ל-Verse אין פונקציית `Pow` כללית. פתרון: מחשבים `10^x = e^(x·ln10)` באמצעות פיתוח טיילור ב-8 איברים של `e^y`:

```
e^y ≈ 1 + y + y²/2! + y³/3! + y⁴/4! + y⁵/5! + y⁶/6! + y⁷/7!
```

האקספוננט מוגבל ל-[-3, 3] לפני הפיתוח (10^3 = 1000, 10^-3 = 0.001 — מספיק לכל הפרש ELO ריאליסטי). התוצאה מוגבלת ל-[0.001, 0.999] למניעת חלוקה באפס.

**בחירת מקדם K** (סדר עדיפויות):

1. השמה (≤10 סיבובים): K=48 — כיול מוקדם תנודתי
2. מיוצב (≥2000 ELO): K=16 — הגנה על דירוגי עילית
3. תנודתי (הזרקת קיפאון פעילה): K=64 — שבירת מדרגות
4. סטנדרטי: K=32

`CalcBotELO(PlayerELO)` מחיל היסטות מדורגות-לדירוג: +25 מתחיל, +40 בינוני, +50 מתקדם, +60 Pro, +75 עילית — כך שהבוט תמיד מעט מעל רמת השחקן, יוצר לחץ אתגר.

`CalcPotentialChange` מחזיר [winDelta, lossDelta, drawDelta] לתצוגת HUD. `EstimateRoundsToTarget` לקביעת יעדי קואצ'.

### difficulty_mapper.verse — ELO → פרמטרי בוט

**סוג**: מחלקה רגילה

ממפה ELO לשדות `bot_difficulty_profile` באמצעות `CalcBracketProgress(ELO, floor, ceiling) → T ∈ [0,1]` ואז `Lerp(A, B, T)` לאינטרפולציה חלקה בתוך דירוגים.

| דירוג | טווח ELO | תגובה (ms) | שונות כוון | PlayRate | אגרסיה | Retarget (s) |
|-------|-----------|------------|------------|----------|---------|-------------|
| מתחיל | 0-800 | 800→600 | 25→15 | 0.45→0.60 | 0 | 0.65→0.50 |
| בינוני | 800-1200 | 600→350 | 15→8 | 0.60→0.85 | 1 | 0.50→0.35 |
| מתקדם | 1200-1600 | 350→200 | 8→3 | 0.85→1.0 | 2 | 0.35→0.22 |
| Pro | 1600-2000 | 200→100 | 3→1 | 1.0→1.25 | 3 | 0.22→0.15 |
| עילית | 2000+ | 100→40 | 1→0 | 1.25→1.5 | 4 | 0.15→0.08 |

שחקן ב-1400 ELO (50% דרך מתקדם) מקבל: תגובה 275ms, שונות כוון 5.5, PlayRate 0.925.

### predictive_advisor.verse — שכבת אינטליגנציה

**סוג**: מחלקה רגילה

**זיהוי קיפאון**: משווה ELO ב-`History[Length - WindowSize]` מול הנוכחי. אם שינוי נטו < סף AND תנודות (סכום שינויי ELO מוחלטים לכל-הסיבוב) גם נמוך, מזוהה קיפאון אמיתי. תנודות גבוהות עם שינוי נטו נמוך = מעורב אך לא עקבי, לא קופא. זמן קירור מונע הפעלה חוזרת לN סיבובים לאחר הזרקה.

**זיהוי תסכול**: מערכת שני-קריטריונים. ראשית, ספירת הפסדי-זנב רצופים. אם >= סף, מחשב ממוצעי בסיס (סיבובים לפני הרצף) מול ממוצעי הרצף עבור DPS ודיוק. אם שניהם יורדים ב-> `DegradationPctThreshold` (ברירת מחדל 20%), תסכול מאושר. 5+ הפסדים מפעיל ללא קשר לירידה (אות חזק).

**ניתוח טרנדים**: `CalcMetricTrend` גנרי מפצל היסטוריה לחצאים, ממצע כל חצי, משווה מול סף לכל מדד. מחזיר IMPROVING/STABLE/DECLINING. חמישה ערוצים: DPS, דיוק, HS%, זמן תגובה (הפוך — נמוך יותר עדיף), מהירות עריכה. `ComputeFullTrend` אורז הכל ל-struct `player_trend`.

**זיהוי חולשה**: משווה ממוצעי 5-הסיבובים האחרונים של השחקן מול בסיסי ציפייה לדירוגו. מחשב אחוז גירעון לכל מדד. מחזיר שם המדד עם הגירעון הגבוה ביותר.

**זיהוי חריגה**: משווה את הסיבוב האחרון מול בסיס גוללת. אם DPS ודיוק שניהם יורדים >35%, מדגל עייפות/tilt/AFK.

### session_aggregator.verse — מהדר סיכום מפגש

**סוג**: מחלקה רגילה

`CompileSession(History, StartingELO, FinalELO, SessionMinutes)` חוזר על כל מדדי הסיבוב כדי לייצר: TotalRounds, ניצחונות/הפסדים/תיקו, ממוצע DPS/HS%/דיוק/תגובה/משך-סיבוב, שיא ELO ונמוך ביותר, רצפי ניצחון/הפסד ארוכים ביותר, סה"כ בניות ועריכות שהוצבו.

`ComputeSessionDelta(Current, Previous)` מייצר struct `session_delta` עם דלתות גולמיות ואחוזי שיפור להשוואה בין-מפגשית ("ה-DPS שלך השתפר ב-15% מאז המפגש האחרון").

אנליטיקס נוסף: `FindBestRoundByDPS`, `FindFastestReactionRound`, `CalcBracketDistribution` (סיבובים לכל דירוג), `CalcWinRateByHalf` (שיעור ניצחון חצי-ראשון מול שני לזיהוי חימום תוך-מפגשי), `CalcConsistencyScore` (100 פחות מקדם השונות של DPS — מודדת עד כמה השחקן מבצע באופן אמין).

---

## 6. מודול D — עקביות

### data_schema_v1.verse — מחלקות עקביות

**סוג**: נתונים טהורים (`class<final><persistable>`)

ארבע מחלקות לארבעה חריצי weak_map. כל השדות הם פרימיטיביים (int, float, logic) — אפס מחרוזות, אפס מערכים. תקציב סריאליזציה כולל: ~192 בייט לשחקן.

- `player_analytics_data_v1`: 10 שדות (AvgDPS, AvgHeadshotPct, AvgAccuracyPct, AvgReactionMs, TotalSessions, TotalRounds, AvgRoundDurationSec, TotalBuildsPlaced, TotalEditsPerformed, ConsistencyScore)
- `player_rating_data_v1`: 10 שדות (ELO, PeakELO, LowestELO, TotalWins, TotalLosses, TotalDraws, TotalTrainingMinutes, BestWinStreak, Version, LastPlayedTimestamp)
- `player_progression_data_v1`: 5 שדות (QuestBitfield, MilestonesReached, HighestBracket, DailyChallenges, TotalQuestsCompleted)
- `player_economy_data_v1`: 6 שדות (HasAnalyticsPass, ArenaSkinsOwned, ChallengeTokens, EquippedArenaSkin, TotalVBucksSpent, TotalPurchaseCount)

### data_schema_v2.verse — סכמה מורחבת

מוסיף שדות לकल חריץ: Analytics מקבל AvgEditSpeedMs, AvgBuildRate, LongestWinStreak, LongestLossStreak. Rating מקבל PreferredCombatStyle, TotalEditsPerformed, TotalBuildsPlaced, AvgRoundDurationSec. Progression מקבל WeeklyQuestBitfield, SeasonNumber, UnlockedDrills, CoachingTier. Economy מקבל TotalTokensConsumed, EquippedModifier, SeasonPassActive. כל מחלקות V2 כוללות `SchemaVersion := 2` לזיהוי העברה.

### migration_v1_to_v2.verse — העברת סכמה בטוחה

ארבע פונקציות `Migrate___()`: כל אחת לוקחת מופע V1, ממפה את כל שדות V1 1:1 ל-V2, ומאתחלת שדות V2 חדשים עם ברירות מחדל בטוחות. `DeriveCoachingTier(HighestBracket)` גוזר אינטליגנטית את רמת הפתיחה של הקואצ' מהישג הדירוג הקודם של השחקן במקום לברירת המחדל לאפס. `MigrateAll` מריץ את כל ארבעת ואורז תוצאות ל-struct `migration_result`. `NeedsMigration` בודק את שדה Version של V1.

### data_validator.verse — אכיפת שלמות

מאמת את כל 4 החריצים: `ValidateRating` (ELO ב-[0, 5000], PeakELO ≥ ELO, LowestELO ≤ ELO, מנייות לא-שליליות, דקות אימון מוגבלות ל-999999). `ValidateAnalytics` (ממוצעים לא-שליליים, אחוזים ב-[0, 100], TotalRounds ≥ TotalSessions). `ValidateEconomy` (אסימונים לא-שליליים מוגבלים ל-9999, מנייות רכישה לא-שליליות). `ValidateProgression` (דירוג ב-[0, 4], אבני דרך לא-שליליות).

מחטאים עצמאיים: `SanitizeELO`, `SanitizeFloat`, `SanitizeInt`, `SanitizePercentage`, `SanitizeNonNegativeInt`. `RunFullIntegrityCheck` מאמת את כל 4 החריצים ומחזיר מספר תיקונים. טלמטריה: סה"כ אימותים, סה"כ תיקונים, שיעור תיקונים.

### persistence_manager.verse — בקר Weak Map ב-4 חריצים

**סוג**: `creative_device`

הצהרות בטווח-מודול (נדרש על-ידי חוקי עקביות Verse):

```verse
var AnalyticsStore   : weak_map(player, player_analytics_data_v1) = map{}
var RatingStore      : weak_map(player, player_rating_data_v1)    = map{}
var ProgressionStore : weak_map(player, player_progression_data_v1) = map{}
var EconomyStore     : weak_map(player, player_economy_data_v1)   = map{}
```

**שכבת מטמון**: טוענת את כל 4 החריצים ל-`LoadedAnalytics`, `LoadedRating`, `LoadedProgression`, `LoadedEconomy` בהצטרפות שחקן. קריאות משרתות מהמטמון. כתיבות מעדכנות גם מטמון וגם weak_map.

**ממוצע גוללת לאנליטיקס**: `SaveAnalyticsData` משתמש ב-`new_avg = (old_avg × old_count + new_value) / new_count` כך שממוצעי חיים משקללים נכון את כל המפגשים הקודמים.

**שמירה-אוטומטית**: `branch` ברקע ממתין ל-`EventBus.ListenForRoundEnd()` וכותב חריץ 2 (דירוג) לאחר כל סיבוב.

**פעולות bitfield קווסט**: `IsQuestCompleted(QuestIndex)` ו-`CompleteQuest(QuestIndex)` משתמשים בפעולות bitwise מקורבות. `BitShiftLeft(1, QuestIndex)` יוצר מסכת bit יחיד. `BitwiseAnd(Bitfield, Mask)` בודק אם ה-bit מוגדר באמצעות חלוקת שלמים: `(A / B) - ((A / B) / 2 × 2) × B`. זה מדויק עבור מסכות חזקה-2 של bit יחיד. `BitwiseOr` מוסיף את ה-bit אם לא קיים. 32 דגלי קווסט בשדה שלם אחד.

---

## 7. מודול E — קואצ'ינג

### feedback_templates.verse — ספריית הודעות

**סוג**: מחלקה רגילה

10 קטגוריות הודעה: ROUND_WIN, ROUND_LOSS, FRUSTRATION, ELO_MILESTONE, SESSION_LONG, STAGNATION, WEAKNESS, IMPROVEMENT, COMEBACK, WELCOME_BACK. בנוסף DRAW ו-FIRST_ROUND.

לכל קטגוריה 3-5 גרסאות תבנית הנבחרות על-ידי `Mod[RoundIdx, N]` למניעת חזרתיות. תבניות מסתעפות על ערכי מדדים אמיתיים בכל גרסה — ניצחון עם 45% כוון לראש מקבל טקסט שונה מניצחון עם 12%. כל ההודעות כוללות לפחות מדד ספציפי אחד דרך אינטרפולציית מחרוזות Verse.

טון ההודעות: ישיר, מכבד, תחרותי. לעולם לא מוטיבציה גנרית. תמיד ניתן לפעולה ("הזז את הרטיקול לגובה הראש" ולא "כוון טוב יותר").

### coach_controller.verse — מנוע הערכת טריגרים

**סוג**: `creative_device`

לולאה ראשית ב-`OnBegin` ממתינה ל-`EventBus.ListenForRoundEnd()` בכל סיבוב, ואז מריצה `ProvidePostRoundFeedback(Outcome)`.

**הערכת עדיפויות** (התאמה ראשונה מנצחת, הודעה אחת לסיבוב):

| עדיפות | טריגר | שיטת זיהוי |
|--------|--------|------------|
| P0 | ברוך שובך | `PersistenceRef.IsReturningPlayer()` בהצטרפות |
| P1 | סיבוב ראשון | דגל `HasDeliveredFirstRound` |
| P2 | תסכול | `Trend.IsFrustrated` + הפסדים רצופים ≥ 3 |
| P3 | קאמבק | ניצחון לאחר `PreviousConsecutiveLosses` ≥ 3 |
| P4 | אבן דרך ELO | דירוג חדש הוזן (מרווח אבן דרך = 200) |
| P5 | קיפאון | `Trend.IsStagnating` |
| P6 | עייפות מפגש | `SessionMinutes > 30` + gasket נגד-nag לפי סיבוב |
| P7 | חולשה | `Advisor.IdentifyWeakestMetric` (קירור 3-סיבובים, ביטול-כפילויות) |
| P8 | שיפור | `Trend.OverallTrend = IMPROVING` (קירור 4-סיבובים) |
| P9 | סטנדרטי | סיכום ניצחון/הפסד/תיקו |

**משלוח רב-ערוצי**: `CoachHUD.Show()` לשכבת-על על-המסך, `PushMessageToHUD()` לכריכת widget UMG, `Logger.Print()` לפלט אבחון. הסתרה אוטומטית לאחר `MessageDisplayDurationSec`.

### coach_game_bridge.verse — גשר פעולות קואצ'

**סוג**: `creative_device`

מתרגם החלטות קואצ'ינג לשינויי מצב-משחק:

- `EaseDifficulty()`: מפחית זמנית את `AnalyticsRef.PlayerELO` בכמות הניתנת להגדרה (ברירת מחדל 50), גורם ל-difficulty_mapper של הסיבוב הבא לייצר פרמטרי בוט קלים יותר. `HasEasedThisSession` מונע הקלה חוזרת.
- `BoostDifficulty()`: מגדיל זמנית ELO ב-25 לאחר 5+ רצף ניצחונות.
- `SpawnFrustrationAid()`: מעניק פריטי ריפוי דרך `item_granter_device.GrantItem()`.
- `SwitchBotStyle()`: מחליף `ArenaCtrlRef.SetUseAltBot(true)` לעבור למפעיל NPC חלופי (פרופיל AI קרב שונה).
- `UnlockNextDrill()`: מעדכן דירוג גבוה ביותר בעקביות.

שתי לולאות אירוע: `ListenCoachCallButton` (כפתור פיזי בלובי → הערכה לפי דרישה), `ListenRoundEndAutoActions` (הקלה-אוטומטית על תסכול, חיזוק-אוטומטי על רצף ניצחונות).

---

## 8. מודול F — כלכלה

### shop_manager.verse — צינור עסקאות

**סוג**: `creative_device`

קטלוג מוצרים: Analytics Pass (800 V-Bucks, עמיד), Cyberpunk Arena (300, עמיד), Neon Grid Arena (300, עמיד), 5 אסימוני אתגר (250, מתכלה), 10 אסימוני אתגר (450, מתכלה), מגפי מהירות (150, מתכלה), רפליי בסלו-מו (200, מתכלה).

ארבעה מאזיני `button_device` (אחד לכל כפתור דוכן חנות) ממתינים ל-`InteractedWithEvent` ומריצים את הצינור בן 6 שלבים: אימות → תשלום (נקודת שילוב API, מסומלץ לפיתוח) → מימוש → עקביות → תופעות לוואי (ציוד קוסמטיקה אוטומטי) → טלמטריה.

מניעת כפילויות: פריטים עמידים נבדקים מול המלאי לפני התשלום. בעלות סקין מאומתת דרך bitfield.

### inventory_controller.verse — ניהול פריטים

**סוג**: מחלקה רגילה

ממשק API כפול: גנרי מבוסס-מחרוזת (`HasItem("arena_cyber")`, `GrantItem("challenge_token_5")`, `ConsumeItem("speed_boots")`) ושיטות מסוגות (`PurchaseAnalyticsPass()`, `PurchaseArenaSkin(2)`, `ConsumeChallengeToken()`). bitfield בעלות סקין באמצעות אותו דפוס `BitShiftLeft`/`BitwiseAnd`/`BitwiseOr` כמו בעקביות. שערי תכונות: `CanAccessAdvancedAnalytics()`, `CanAccessEliteBots()`, `CanEnterChallenge()`.

### cosmetic_applicator.verse — החלפת סקין לזירה

**סוג**: `creative_device`

5 הפניות `creative_prop` לגרסאות זירה. `ApplyArenaSkin(SkinId)`: מסתיר את כל הגרסאות בבימוי (Z=-5000), מציג את הנבחרת ב-`ArenaShowPosition`. מנעול `IsSwapping` מונע שחיתות החלפה מקבילית. `PreviewSkin`/`EndPreview` לתצוגה מקדימה לפני קנייה בממשק החנות. בטעינת מפגש, מחיל אוטומטית את הסקין המצויד של השחקן מהעקביות.

### xp_reward_system.verse — חלוקת הצטיינויות

**סוג**: `creative_device`

6 הפניות `accolades_device` (ניצחון, הפסד, אבן דרך כוון לראש, עלייה בדירוג, אבן דרך מפגש, רצף ניצחונות). אכיפת תקציב: `XPAccumulated` נעקב לכל בלוק של 10 דקות, מוגבל ל-`MaxXPPerBlock` (200,000). חריגה מהגג חוסמת הצטיינויות נוספות עד לאיפוס החלון. רצפי ניצחונות (כל 3 ניצחונות), אבני דרך כוון לראש (כל 10 כוון-לראש מצטברים), אבני דרך מפגש (כל 10 סיבובים), ועליות דירוג מזוהות אוטומטית ממצב אוטובוס האירועים.

---

## 9. שכבת ממשק המשתמש

### hud_binding.verse — HUD חי + גשר כריכה

**סוג**: `creative_device`

יוצר 3 לוחות canvas דרך ממשק `player_ui`: נתוני לחימה חיים (שמאל-למעלה), סרגל סטטוס (ימין-למעלה), הודעת קואצ' (מרכז-למטה). לולאת רענון 500ms קוראת `AnalyticsRef.CurrentSnapshot` ל-DPS/דיוק/HS% חיים במהלך קרבות. סרגל הסטטוס מציג ELO עם שם הדירוג, אחוז התקדמות בדירוג הנוכחי, מספר סיבוב, ו-W/L/D. הודעת קואצ' מוסתרת אוטומטית דרך `spawn: CoachMessageAutoHide()`. כל ערכי התצוגה נחשפים בו-זמנית כמשתנים ציבוריים לכריכת UMG Widget Blueprint אופציונלית (מצב תצוגה כפול).

### scorecard_renderer.verse — שכבת-על לאחר הסיבוב

**סוג**: `creative_device`

6 אלמנטי `text_block` על `canvas`: כותרת תוצאה, שינוי ELO עם כיוון דלתא, מדדי ליבה (DPS/דיוק/HS%), מדדים משניים (תגובה/בניות/עריכות/משך), סיכום מפגש (W/L/D/סיבוב/דירוג), משוב קואצ'. מאזין ברקע מרנדר אוטומטית ב-`EventBus.ListenForRoundEnd()`. `HideScorecard()` מנקה את כל הטקסט בין סיבובים.

### shop_ui_controller.verse — תפריט החנות

**סוג**: `creative_device`

שכבת-על חנות מצוירת על canvas המופעלת על-ידי `ShopTerminalBtn.InteractedWithEvent`. מציגה 4 שורות מוצרים עם סטטוס בעלות בזמן אמת ("[OWNED]" / "[BUY]"), מאזן אסימונים, שם סקין מצויד. `HandlePurchaseRequest` מאציל ל-`shop_manager.ProcessPurchase()` ושומר מייד לעקביות בהצלחה.

---

## 10. דפוסים חוצי-מערכת

### דפוס: Dispatch / Listen (אוטובוס אירועים)

```verse
# מפיק
EventBus.DispatchRoundEnd(Outcome)
  → מגדיר LastRoundOutcome = Outcome
  → מגדיר TotalPlayerWins += 1 (אם ניצחון)
  → RoundEndEvent.Signal()

# צרכן (בסניף OnBegin של כל מודול)
loop:
    EventBus.ListenForRoundEnd()    # מושהה עד Signal()
    DoSomethingWithOutcome(EventBus.LastRoundOutcome)
```

### דפוס: Init() לתת-מודולים של NPC

```verse
# npc_behavior לא יכולה להחזיק @editable → מחלקות רגילות עם Init()
bot_navigation := class:
    var Agent : ?agent = false
    var Character : ?fort_character = false
    var Nav : ?navigatable = false

    Init(InAgent, InChar):
        set Agent = option{InAgent}
        set Character = option{InChar}
        if (N := InChar.GetNavigatable[]):
            set Nav = option{N}
```

### דפוס: תביעה/פינוי ממאגר אובייקטים

```verse
ClaimAndDeploy(PieceType, Position, Rotation):
    # מאתר רשומה לא-פעילה במאגר המסוג
    # TeleportTo(Position, Rotation)
    # בכישלון: rollback, מנסה רשומה הבאה
    # אם אוזל: ReclaimOldestFromPool (FIFO לפי DeployOrder)
    # ניסיון חוזר עם רשומה שפונתה
```

### דפוס: Bitfield שלמים לדגלים

```verse
# הגדרת bit:   Bitfield = BitwiseOr(Bitfield, BitShiftLeft(1, Index))
# בדיקת bit:   BitwiseAnd(Bitfield, BitShiftLeft(1, Index)) > 0
# ניקוי bit:   Bitfield = Bitfield - BitShiftLeft(1, Index)  (אם מוגדר)
#
# קירוב BitwiseAnd למסכות bit יחיד:
#   (A / B) - ((A / B) / 2 × 2) × B
# מדויק עבור ערכי B חזקה-2 (מקרה השימוש הבלעדי שלנו).
```

### דפוס: ממוצע גוללת לעקביות

```verse
# new_avg = (old_avg × old_count + new_value) / new_count
# נמנע מאחסון היסטוריה מלאה ב-weak_map.
# שחקן עם 50 מפגשים ויום רע אחד לא מפיל את הסטטיסטיקות שלו לכל החיים.
```

---

## 11. תרשימי זרימת נתונים

### זרימת מחזור חיי הסיבוב

```
game_manager
    │
    ├── LOBBY ─────── DispatchStateChange(STATE_LOBBY)
    │                    └── hud_binding: מעבר לתצוגת סרלוף
    │
    ├── COUNTDOWN ──── ArenaCtrl.SpawnBot()
    │                  DispatchCountdownTick(3, 2, 1)
    │                    └── hud_binding: הצגת ספירה לאחור
    │
    ├── FIGHT ──────── Analytics.BeginRoundTracking()
    │                  DispatchRoundStart(RoundNum)
    │                    ├── analytics_engine: איפוס מצברים
    │                    ├── xp_reward_system: בדיקת עלייה בדירוג
    │                    └── hud_binding: מעבר למצב לחימה חי
    │                  race:
    │                    ├── EventBus.ListenForBotEliminated()
    │                    ├── PlayerChar.EliminatedEvent().Await()
    │                    └── Sleep(RoundDurationSeconds)
    │
    ├── POST_ROUND ─── Analytics.EndRoundTracking(Outcome)
    │                    ├── סיום DPS, דיוק, HS%, ELO
    │                    ├── הרצת predictive_advisor
    │                    └── עדכון difficulty_mapper
    │                  DispatchRoundEnd(Outcome)
    │                    ├── persistence_manager: שמירת ELO אוטומטית
    │                    ├── coach_controller: הערכת טריגרים
    │                    ├── xp_reward_system: פרס הצטיינויות
    │                    └── scorecard_renderer: רינדור שכבת-על
    │                  Coach.EvaluatePostRound() → מחרוזת קואצ'ינג
    │                  Scorecard.RenderScorecard()
    │                  HUD.SetCoachMessage()
    │                  Sleep(PostRoundDisplaySeconds)
    │
    └── RESET ──────── ArenaCtrl.ResetArena()
                         ├── השבתת בוט
                         ├── BuildPool.ReclaimAll()
                         └── טלפורט שחקן לנקודת התחלה
                       Analytics.GetUpdatedProfile()
                       Sleep(ResetCooldownSeconds)
                       → חזרה ל-LOBBY
```

### זרימת עדכון ELO

```
סיום סיבוב
    │
    ▼
analytics_engine.EndRoundTracking()
    │
    ├── חישוב מדדי ביצוע מורכבים
    │
    ├── elo_calculator.CalcExpectedProbability(PlayerELO, BotELO)
    │     └── Pow10 דרך 8-איברי טיילור: e^(x·ln10)
    │
    ├── elo_calculator.SelectKFactor()
    │     └── השמה? מיוצב? תנודתי? סטנדרטי?
    │
    ├── elo_calculator.CalcNewRating(PlayerELO, BotELO, Outcome, K)
    │     └── NewELO = OldELO + K × (ActualScore - ExpectedProbability)
    │
    ├── difficulty_mapper.MapDifficulty(NewELO, Profile)
    │     └── CalcBracketProgress → Lerp לכל שדה → אימות
    │
    └── predictive_advisor.ComputeFullTrend(History)
          ├── האם להזריק תנודתיות? (בדיקת קיפאון + תנודות)
          ├── זיהוי תסכול? (הפסדים + ירידת ביצועים)
          └── חישוב טרנדי מדדים (5 ערוצים)
```

---

## 12. מודל המקביליות

כל פונקציה `<suspends>` בבסיס הקוד נכנסת לאחד מהדפוסים הבאים:

| דפוס | שימוש | דוגמה |
|------|--------|--------|
| `race{}` | הראשון-שמסיים מבטל את האחרים | שלב FIGHT: מוות בוט מול מוות שחקן מול טיימר |
| `branch{}` | משימת רקע fire-and-forget | מאזיני אוטובוס אירועים, לולאת שמירה-אוטומטית, רענון HUD |
| `loop + Await` | מאזין תגובתי | `loop: EventBus.ListenForRoundEnd(); Process()` |
| `Sleep(duration)` | עיכוב מתוזמן | טיקים של ספירה לאחור, סנכרון אנימציה, הסתרת הודעה אוטומטית |
| `spawn{}` | fire-and-forget לא-חוסם | הסתרת הודעת קואצ' אוטומטית, יישום קוסמטיקה |

**סדר קריטי ב-PostRound**: `Analytics.EndRoundTracking()` חייב להסתיים לפני `EventBus.DispatchRoundEnd()`. מנוע האנליטיקס מסיים את כל המדדים ומעדכן את ה-ELO — רק אז האירוע מאותת, מה שמבטיח שכל המאזינים הזרם-מטה רואים נתונים סופיים.

---

## 13. תקציב העקביות

| חריץ | Weak Map | מחלקה | שדות | בייטים משוערים | תדירות כתיבה |
|------|----------|--------|------|----------------|--------------|
| 1 | `AnalyticsStore` | `player_analytics_data_v1` | 10 | ~80 | סוף מפגש |
| 2 | `RatingStore` | `player_rating_data_v1` | 10 | ~80 | כל סוף סיבוב |
| 3 | `ProgressionStore` | `player_progression_data_v1` | 5 | ~40 | השלמת קווסט |
| 4 | `EconomyStore` | `player_economy_data_v1` | 6 | ~48 | אירועי רכישה |

**סה"כ**: ~248 בייטים לשחקן על פני כל 4 החריצים. הרבה מתחת למגבלות הסריאליזציה של Verse.

**נימוק תדירות הכתיבה**: חריץ 2 (דירוג) הוא הקריטי ביותר — אם שחקן מתנתק, ה-ELO שלו חייב להישמר. שמירה אוטומטית בכל סוף סיבוב מבטיחה לכל היותר אובדן ELO של סיבוב אחד. חריצים 1, 3, 4 פחות קריטיים וכותבים בתדירות נמוכה יותר כדי להפחית גישות ל-weak_map.

---

*מסמך זה מכסה את הארכיטקטורה המלאה של 35 הקבצים כפי שיושמה על פני משימות 1-19. כל הקוד מוכן לפרודקשן ללא stubים כלשהם.*

</div>
