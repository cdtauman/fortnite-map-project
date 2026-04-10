# ============================================================================
# FILE: analytics_engine.verse — Real-Time Data Processing & Metric Computation
# LOCATION: Content/ (root)
# PHASE: 4
#
# ARCHITECTURE:
#   The analytics engine is the map's central nervous system. It operates
#   in two modes simultaneously:
#
#   MODE 1 — Event-Driven Ingestion (Background Listeners):
#     Branched loops in OnBegin continuously await event bus signals:
#       - PlayerDamageEvent → accumulate damage, track headshots
#       - BotDamageEvent → accumulate damage taken
#       - BuildPlacedEvent → count builds
#       - EditPerformedEvent → count edits, track speed
#       - RoundStartEvent → reset accumulators
#       - RoundEndEvent → finalize metrics, update ELO
#     Each listener runs independently — no listener blocks another.
#
#   MODE 2 — Periodic Computation (Tick Loop):
#     A 0.5s loop computes derived metrics (DPS, accuracy %) from
#     the raw accumulators, writes a combat_snapshot, and updates
#     the event bus shared state for the HUD to read.
#
#   At round end, EndRoundTracking finalizes all metrics, pushes
#   them to the rolling history, recalculates ELO via the
#   elo_calculator sub-module, runs the predictive_advisor for
#   trend analysis, and dispatches AnalyticsUpdatedEvent so the
#   coach, HUD, and persistence modules all react.
#
# WIRING (UEFN Editor):
#   EventBus → event_bus device
# ============================================================================
using { /Fortnite.com/Devices }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Game }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/SpatialMath }

analytics_engine<public> := class(creative_device):

    Logger<private> : log = log{Channel := log_analytics_ch}

    # ── Editable References ──────────────────────────────────────────────────
    @editable
    EventBus<public> : event_bus = event_bus{}

    # ── Current Round Metrics (reset each round) ─────────────────────────────
    var CurrentMetrics<public>        : round_metrics = round_metrics{}
    var CurrentBuildPerf<public>      : build_performance = build_performance{}
    var CurrentSnapshot<public>       : combat_snapshot = combat_snapshot{}
    var CurrentTrend<public>          : player_trend = player_trend{}

    # ── Round Timing ─────────────────────────────────────────────────────────
    var RoundStartTime<private>       : float = 0.0
    var FirstDamageTimestamp<private>  : float = 0.0
    var LastDamageTimestamp<private>   : float = 0.0
    var HasRecordedFirstHit<private>  : logic = false
    var IsTrackingRound<private>      : logic = false

    # ── Rolling History (ring buffer, last N rounds) ─────────────────────────
    var MetricsHistory<public>        : []round_metrics = array{}

    @editable
    HistoryMaxSize<public>            : int = 10

    # ── ELO State ────────────────────────────────────────────────────────────
    var PlayerELO<public>             : int = 1000
    var BotELO<public>                : int = 1050
    var PeakELO<private>              : int = 1000
    var LowestELO<private>            : int = 1000
    var StartingSessionELO<private>   : int = 1000

    # ── Sub-Modules ──────────────────────────────────────────────────────────
    var EloCalc<public>               : elo_calculator = elo_calculator{}
    var DiffMapper<public>            : difficulty_mapper = difficulty_mapper{}
    var Advisor<public>               : predictive_advisor = predictive_advisor{}

    # ── Session Accumulators ─────────────────────────────────────────────────
    var SessionRoundsPlayed<private>  : int = 0
    var SessionTotalDamage<private>   : float = 0.0
    var SessionTotalBuilds<private>   : int = 0
    var SessionTotalEdits<private>    : int = 0
    var LongestWinStreak<private>     : int = 0
    var LongestLossStreak<private>    : int = 0
    var CurrentWinStreak<private>     : int = 0
    var CurrentLossStreak<private>    : int = 0

    # ── Hit Timing Accumulator (for average time between hits) ───────────────
    var HitTimestamps<private>        : []float = array{}
    var HitTimestampsMaxSize<private> : int = 50

    # ══════════════════════════════════════════════════════════════════════════
    # INITIALIZATION — Launch all background event listeners
    # ══════════════════════════════════════════════════════════════════════════
    OnBegin<override>()<suspends> : void =
        set StartingSessionELO = PlayerELO
        set PeakELO = PlayerELO
        set LowestELO = PlayerELO
        Logger.Print("ANALYTICS: ── Engine Online ──")
        Logger.Print("ANALYTICS: Starting ELO: {PlayerELO}")

        # Launch background event listeners — each runs independently
        branch:
            ListenPlayerDamageLoop()
        branch:
            ListenBotDamageLoop()
        branch:
            ListenBuildPlacedLoop()
        branch:
            ListenEditPerformedLoop()
        branch:
            ListenRoundStartLoop()
        branch:
            ListenRoundEndLoop()
        branch:
            PeriodicComputeLoop()

        Logger.Print("ANALYTICS: All listeners launched.")

    # ══════════════════════════════════════════════════════════════════════════
    # BACKGROUND LISTENERS — Event-driven data ingestion
    # Each runs in its own branch, awaiting the relevant event bus signal.
    # ══════════════════════════════════════════════════════════════════════════

    # ── Player Damage Listener ───────────────────────────────────────────────
    # Fires every time the bot's weapon controller dispatches a hit on the player.
    # We read the damage_report from the event bus shared state.
    ListenPlayerDamageLoop<private>()<suspends> : void =
        loop:
            EventBus.ListenForPlayerDamage()
            if (IsTrackingRound?):
                Report := EventBus.LastPlayerDamageReport
                Now := GetSimulationElapsedTime()

                # Accumulate raw damage
                set CurrentMetrics.DamageTaken += Report.DamageAmount
                set CurrentMetrics.BotDamageDealt += Report.DamageAmount
                set CurrentMetrics.BotShotsHit += 1
                if (Report.IsHeadshot?):
                    set CurrentMetrics.BotHeadshots += 1

    # ── Bot Damage Listener (player hitting the bot) ─────────────────────────
    # Fires every time the weapon controller's simulation (or a future
    # engine DamageDealt event) records the player dealing damage.
    ListenBotDamageLoop<private>()<suspends> : void =
        loop:
            EventBus.ListenForBotDamage()
            if (IsTrackingRound?):
                Report := EventBus.LastBotDamageReport
                Now := GetSimulationElapsedTime()

                # Accumulate player's damage output
                set CurrentMetrics.DamageDealt += Report.DamageAmount
                set CurrentMetrics.PlayerShotsHit += 1
                set CurrentMetrics.PlayerShotsFired += 1

                if (Report.IsHeadshot?):
                    set CurrentMetrics.PlayerHeadshots += 1

                # Track first-hit reaction time
                if (not HasRecordedFirstHit?):
                    set HasRecordedFirstHit = true
                    set FirstDamageTimestamp = Now
                    ReactionMs := (Now - RoundStartTime) * 1000.0
                    set CurrentMetrics.ReactionTimeMs = ReactionMs
                    Logger.Print("ANALYTICS: First hit reaction: {ReactionMs}ms")

                # Track hit timing for average-between-hits calc
                set LastDamageTimestamp = Now
                if (HitTimestamps.Length < HitTimestampsMaxSize):
                    set HitTimestamps += array{Now}

                set SessionTotalDamage += Report.DamageAmount

    # ── Build Placed Listener ────────────────────────────────────────────────
    ListenBuildPlacedLoop<private>()<suspends> : void =
        loop:
            EventBus.ListenForBuildPlaced()
            if (IsTrackingRound?):
                BuildData := EventBus.LastBuildEvent
                set CurrentMetrics.BuildsPlaced += 1
                set CurrentBuildPerf.TotalPiecesPlaced += 1
                set SessionTotalBuilds += 1

                # Track by type
                if (BuildData.PieceType = "Wall"):
                    set CurrentBuildPerf.WallsPlaced += 1
                else if (BuildData.PieceType = "Floor"):
                    set CurrentBuildPerf.FloorsPlaced += 1
                else if (BuildData.PieceType = "Ramp"):
                    set CurrentBuildPerf.RampsPlaced += 1
                else if (BuildData.PieceType = "Cone"):
                    set CurrentBuildPerf.ConesPlaced += 1

    # ── Edit Performed Listener ──────────────────────────────────────────────
    ListenEditPerformedLoop<private>()<suspends> : void =
        loop:
            EventBus.ListenForEditPerformed()
            if (IsTrackingRound?):
                EditData := EventBus.LastBuildEvent
                set CurrentMetrics.EditsPerformed += 1
                set CurrentBuildPerf.EditsPerformed += 1
                set SessionTotalEdits += 1

                # Track by edit type
                if (EditData.PieceType = "Window"):
                    set CurrentBuildPerf.WindowEdits += 1
                else if (EditData.PieceType = "Door"):
                    set CurrentBuildPerf.DoorEdits += 1
                else if (EditData.PieceType = "Full"):
                    set CurrentBuildPerf.EditResets += 1

    # ── Round Start Listener ─────────────────────────────────────────────────
    ListenRoundStartLoop<private>()<suspends> : void =
        loop:
            EventBus.ListenForRoundStart()
            BeginRoundTracking()

    # ── Round End Listener ───────────────────────────────────────────────────
    ListenRoundEndLoop<private>()<suspends> : void =
        loop:
            EventBus.ListenForRoundEnd()
            EndRoundTracking(EventBus.LastRoundOutcome, EventBus.CurrentRoundNumber)

    # ══════════════════════════════════════════════════════════════════════════
    # PERIODIC COMPUTE LOOP — Derived metric calculation every 0.5s
    # Computes DPS, accuracy%, headshot%, and writes a combat_snapshot
    # for the HUD to read. Runs only during active rounds.
    # ══════════════════════════════════════════════════════════════════════════
    PeriodicComputeLoop<private>()<suspends> : void =
        loop:
            Sleep(0.5)
            if (IsTrackingRound?):
                Now := GetSimulationElapsedTime()
                Elapsed := Now - RoundStartTime
                if (Elapsed > 0.1):
                    # Compute live DPS
                    set CurrentSnapshot.LiveDPS = CurrentMetrics.DamageDealt / Elapsed
                    set CurrentSnapshot.ElapsedFightSec = Elapsed

                    # Compute live accuracy
                    if (CurrentMetrics.PlayerShotsFired > 0):
                        set CurrentSnapshot.LiveAccuracy = (CurrentMetrics.PlayerShotsHit * 100.0) / (CurrentMetrics.PlayerShotsFired * 1.0)
                    else:
                        set CurrentSnapshot.LiveAccuracy = 0.0

                    # Compute live headshot %
                    if (CurrentMetrics.PlayerShotsHit > 0):
                        set CurrentSnapshot.LiveHeadshotPct = (CurrentMetrics.PlayerHeadshots * 100.0) / (CurrentMetrics.PlayerShotsHit * 1.0)
                    else:
                        set CurrentSnapshot.LiveHeadshotPct = 0.0

                    set CurrentSnapshot.Timestamp = Now

    # ══════════════════════════════════════════════════════════════════════════
    # BEGIN ROUND TRACKING — Reset accumulators for a new round
    # Called automatically by ListenRoundStartLoop.
    # ══════════════════════════════════════════════════════════════════════════
    BeginRoundTracking<public>() : void =
        set CurrentMetrics = round_metrics{}
        set CurrentBuildPerf = build_performance{}
        set CurrentSnapshot = combat_snapshot{}
        set RoundStartTime = GetSimulationElapsedTime()
        set FirstDamageTimestamp = 0.0
        set LastDamageTimestamp = 0.0
        set HasRecordedFirstHit = false
        set IsTrackingRound = true
        set HitTimestamps = array{}

        # Calculate bot ELO target for this round
        set BotELO = EloCalc.CalcBotELO(PlayerELO)

        set CurrentMetrics.PlayerELO = PlayerELO
        set CurrentMetrics.BotELO = BotELO
        set CurrentMetrics.RoundStartTimestamp = RoundStartTime
        set SessionRoundsPlayed += 1

        Logger.Print("ANALYTICS: Round tracking started. Player ELO:{PlayerELO} Bot ELO:{BotELO}")

    # ══════════════════════════════════════════════════════════════════════════
    # END ROUND TRACKING — Finalize all metrics and update ELO
    # Called automatically by ListenRoundEndLoop.
    # ══════════════════════════════════════════════════════════════════════════
    EndRoundTracking<public>(Outcome : int, RoundNumber : int) : void =
        set IsTrackingRound = false
        Now := GetSimulationElapsedTime()
        Elapsed := Now - RoundStartTime

        # ── Finalize round duration ──────────────────────────────────────────
        set CurrentMetrics.RoundDurationSec = Elapsed
        set CurrentMetrics.Outcome = Outcome
        set CurrentMetrics.RoundNumber = RoundNumber

        # ── Compute final DPS ────────────────────────────────────────────────
        if (Elapsed > 0.1):
            set CurrentMetrics.DPS = CurrentMetrics.DamageDealt / Elapsed
        else:
            set CurrentMetrics.DPS = 0.0

        # ── Compute final accuracy ───────────────────────────────────────────
        if (CurrentMetrics.PlayerShotsFired > 0):
            set CurrentMetrics.AccuracyPct = (CurrentMetrics.PlayerShotsHit * 100.0) / (CurrentMetrics.PlayerShotsFired * 1.0)
        else:
            set CurrentMetrics.AccuracyPct = 0.0

        # ── Compute final headshot % ─────────────────────────────────────────
        if (CurrentMetrics.PlayerShotsHit > 0):
            set CurrentMetrics.HeadshotPct = (CurrentMetrics.PlayerHeadshots * 100.0) / (CurrentMetrics.PlayerShotsHit * 1.0)
        else:
            set CurrentMetrics.HeadshotPct = 0.0

        # ── Compute average time between hits ────────────────────────────────
        if (HitTimestamps.Length >= 2):
            var TotalGap : float = 0.0
            var GapCount : int = 0
            var PrevTime : float = 0.0
            var IsFirst : logic = true
            for (T : HitTimestamps):
                if (IsFirst?):
                    set IsFirst = false
                    set PrevTime = T
                else:
                    Gap := T - PrevTime
                    set TotalGap += Gap
                    set GapCount += 1
                    set PrevTime = T
            if (GapCount > 0):
                set CurrentMetrics.AvgTimeBetweenHitsMs = (TotalGap / (GapCount * 1.0)) * 1000.0

        # ── Compute edit speed ───────────────────────────────────────────────
        if (Elapsed > 0.1):
            if (CurrentMetrics.EditsPerformed > 0):
                set CurrentMetrics.EditSpeed = (CurrentMetrics.EditsPerformed * 1.0) / Elapsed

        # ── Update streak tracking ───────────────────────────────────────────
        if (Outcome = OUTCOME_PLAYER_WIN):
            set CurrentWinStreak += 1
            set CurrentLossStreak = 0
            if (CurrentWinStreak > LongestWinStreak):
                set LongestWinStreak = CurrentWinStreak
        else if (Outcome = OUTCOME_BOT_WIN):
            set CurrentLossStreak += 1
            set CurrentWinStreak = 0
            if (CurrentLossStreak > LongestLossStreak):
                set LongestLossStreak = CurrentLossStreak
        else:
            set CurrentWinStreak = 0
            set CurrentLossStreak = 0

        # ── Run predictive advisor ───────────────────────────────────────────
        set CurrentTrend.IsStagnating = Advisor.ShouldInjectVolatility(MetricsHistory, PlayerELO)
        set CurrentTrend.IsFrustrated = Advisor.DetectFrustration(EventBus.ConsecutiveLosses)
        set CurrentTrend.DPSTrend = Advisor.CalcDPSTrend(MetricsHistory)
        set CurrentTrend.ShouldInjectVolatility = CurrentTrend.IsStagnating

        # ── Update ELO ───────────────────────────────────────────────────────
        IsVolatile := CurrentTrend.ShouldInjectVolatility
        NewELO := EloCalc.CalcNewRating(PlayerELO, BotELO, Outcome, RoundNumber, IsVolatile)
        Logger.Print("ANALYTICS: ELO {PlayerELO} -> {NewELO} (Outcome:{Outcome} Volatile:{if (IsVolatile?) then "true" else "false"})")
        set PlayerELO = NewELO

        # Track ELO extremes
        if (PlayerELO > PeakELO):
            set PeakELO = PlayerELO
        if (PlayerELO < LowestELO):
            set LowestELO = PlayerELO

        # ── Push to rolling history (ring buffer) ────────────────────────────
        if (MetricsHistory.Length >= HistoryMaxSize):
            var NewHistory : []round_metrics = array{}
            for (Idx -> M : MetricsHistory):
                if (Idx > 0):
                    set NewHistory += array{M}
            set MetricsHistory = NewHistory
        set MetricsHistory += array{CurrentMetrics}

        # ── Dispatch to event bus ────────────────────────────────────────────
        EventBus.DispatchAnalyticsUpdated(
            CurrentMetrics.DPS,
            CurrentMetrics.HeadshotPct,
            CurrentMetrics.ReactionTimeMs,
            CurrentMetrics.EditSpeed
        )

        # ── Log summary ──────────────────────────────────────────────────────
        Logger.Print("ANALYTICS: ── Round {RoundNumber} Summary ──")
        Logger.Print("ANALYTICS:   Duration: {Elapsed}s")
        Logger.Print("ANALYTICS:   DPS: {CurrentMetrics.DPS} | Accuracy: {CurrentMetrics.AccuracyPct}%")
        Logger.Print("ANALYTICS:   Headshot: {CurrentMetrics.HeadshotPct}% | Reaction: {CurrentMetrics.ReactionTimeMs}ms")
        Logger.Print("ANALYTICS:   Builds: {CurrentMetrics.BuildsPlaced} | Edits: {CurrentMetrics.EditsPerformed}")
        Logger.Print("ANALYTICS:   Damage Dealt: {CurrentMetrics.DamageDealt} | Taken: {CurrentMetrics.DamageTaken}")
        Logger.Print("ANALYTICS:   ELO: {PlayerELO} | Peak: {PeakELO} | History: {MetricsHistory.Length}")

    # ══════════════════════════════════════════════════════════════════════════
    # PUBLIC: Get Updated Difficulty Profile
    # Called by game_manager between rounds to get the new bot parameters
    # based on the player's current ELO.
    # ══════════════════════════════════════════════════════════════════════════
    GetUpdatedProfile<public>() : bot_difficulty_profile =
        NewProfile := bot_difficulty_profile{}
        DiffMapper.MapDifficulty(PlayerELO, NewProfile)
        NewProfile

    # ══════════════════════════════════════════════════════════════════════════
    # PUBLIC: Compile Session Summary
    # Called by persistence_manager at session end or on player leave.
    # ══════════════════════════════════════════════════════════════════════════
    CompileSessionSummary<public>(SessionMinutes : float) : session_summary =
        Summary := session_summary{}
        set Summary.TotalRounds = SessionRoundsPlayed
        set Summary.StartingELO = StartingSessionELO
        set Summary.FinalELO = PlayerELO
        set Summary.PeakELO = PeakELO
        set Summary.LowestELO = LowestELO
        set Summary.SessionDurationMin = SessionMinutes
        set Summary.LongestWinStreak = LongestWinStreak
        set Summary.LongestLossStreak = LongestLossStreak
        set Summary.TotalBuildsPlaced = SessionTotalBuilds
        set Summary.TotalEditsPerformed = SessionTotalEdits

        # Compute averages from history
        var TotalDPS : float = 0.0
        var TotalHS : float = 0.0
        var TotalAcc : float = 0.0
        var TotalReaction : float = 0.0
        var TotalDuration : float = 0.0

        for (M : MetricsHistory):
            if (M.Outcome = OUTCOME_PLAYER_WIN):
                set Summary.Wins += 1
            else if (M.Outcome = OUTCOME_BOT_WIN):
                set Summary.Losses += 1
            else:
                set Summary.Draws += 1

            set TotalDPS += M.DPS
            set TotalHS += M.HeadshotPct
            set TotalAcc += M.AccuracyPct
            set TotalReaction += M.ReactionTimeMs
            set TotalDuration += M.RoundDurationSec

        Count := MetricsHistory.Length * 1.0
        if (Count > 0.0):
            set Summary.AvgDPS = TotalDPS / Count
            set Summary.AvgHeadshotPct = TotalHS / Count
            set Summary.AvgAccuracyPct = TotalAcc / Count
            set Summary.AvgReactionMs = TotalReaction / Count
            set Summary.AvgRoundDurationSec = TotalDuration / Count

        Logger.Print("ANALYTICS: Session summary compiled. {Summary.TotalRounds} rounds, ELO {Summary.StartingELO}->{Summary.FinalELO}")
        Summary

    # ══════════════════════════════════════════════════════════════════════════
    # PUBLIC QUERIES
    # ══════════════════════════════════════════════════════════════════════════
    GetCurrentDPS<public>() : float =
        CurrentSnapshot.LiveDPS

    GetCurrentAccuracy<public>() : float =
        CurrentSnapshot.LiveAccuracy

    GetCurrentHeadshotPct<public>() : float =
        CurrentSnapshot.LiveHeadshotPct

    GetPlayerELO<public>() : int =
        PlayerELO

    GetPeakELO<public>() : int =
        PeakELO

    GetSessionRoundsPlayed<public>() : int =
        SessionRoundsPlayed

    GetCurrentTrend<public>() : player_trend =
        CurrentTrend

    GetHistory<public>() : []round_metrics =
        MetricsHistory

    IsPlayerFrustrated<public>() : logic =
        CurrentTrend.IsFrustrated

    IsELOStagnating<public>() : logic =
        CurrentTrend.IsStagnating

    # ══════════════════════════════════════════════════════════════════════════
    # DEBUG: Full stats dump
    # ══════════════════════════════════════════════════════════════════════════
    LogFullState<public>() : void =
        Logger.Print("ANALYTICS: ══ Full State Dump ══")
        Logger.Print("ANALYTICS:   Player ELO: {PlayerELO} (Peak:{PeakELO} Low:{LowestELO})")
        Logger.Print("ANALYTICS:   Session Rounds: {SessionRoundsPlayed}")
        Logger.Print("ANALYTICS:   Win Streak: {CurrentWinStreak} (Best:{LongestWinStreak})")
        Logger.Print("ANALYTICS:   Loss Streak: {CurrentLossStreak} (Worst:{LongestLossStreak})")
        Logger.Print("ANALYTICS:   History Size: {MetricsHistory.Length}/{HistoryMaxSize}")
        Logger.Print("ANALYTICS:   Tracking Active: {if (IsTrackingRound?) then "true" else "false"}")
        Logger.Print("ANALYTICS:   Trend — Stagnating:{if (CurrentTrend.IsStagnating?) then "true" else "false"} Frustrated:{if (CurrentTrend.IsFrustrated?) then "true" else "false"}")

log_analytics_ch := class(log_channel):