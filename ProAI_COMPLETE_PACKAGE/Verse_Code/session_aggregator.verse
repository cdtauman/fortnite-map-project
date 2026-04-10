# ============================================================================
# FILE: session_aggregator.verse — Session Summary Compiler & Cross-Session Analytics
# LOCATION: Content/ (root)
# PHASE: 4+5
#
# ARCHITECTURE:
#   Compiles per-round metrics into a comprehensive session_summary struct
#   that serves as the persistence payload for Module D. This is the bridge
#   between the real-time analytics (Module C) and the long-term storage
#   (Module D Slot 1).
#
#   The aggregator also computes cross-session comparison data when given
#   a previous session_summary from persistence — enabling the coach to
#   say "Your DPS improved 12% since last session."
#
# INPUT:  []round_metrics (rolling history from analytics_engine)
# OUTPUT: session_summary (ready for persistence_manager.SaveAnalyticsData)
#
# ADDITIONAL FEATURES:
#   - Streak tracking (longest win/loss streaks within the session)
#   - Bracket distribution (how many rounds at each ELO bracket)
#   - Best/worst round identification
#   - Cross-session delta computation
# ============================================================================
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }

# ══════════════════════════════════════════════════════════════════════════════
# SESSION AGGREGATOR
# ══════════════════════════════════════════════════════════════════════════════
session_aggregator<public> := class:

    Logger<private> : log = log{Channel := log_agg_ch}

    # ══════════════════════════════════════════════════════════════════════════
    # PRIMARY: Compile Session Summary
    # Takes the complete round history and produces a session_summary
    # struct ready for persistence.
    #
    # Parameters:
    #   History        — All round_metrics from this session
    #   StartingELO    — Player's ELO when the session started
    #   FinalELO       — Player's ELO at session end
    #   SessionMinutes — Total session duration in minutes
    # ══════════════════════════════════════════════════════════════════════════
    CompileSession<public>(
        History : []round_metrics,
        StartingELO : int,
        FinalELO : int,
        SessionMinutes : float
    ) : session_summary =
        Summary := session_summary{}
        set Summary.TotalRounds = History.Length
        set Summary.StartingELO = StartingELO
        set Summary.FinalELO = FinalELO
        set Summary.SessionDurationMin = SessionMinutes
        set Summary.PeakELO = StartingELO
        set Summary.LowestELO = StartingELO

        # ── Accumulators ─────────────────────────────────────────────────────
        var TotalDPS : float = 0.0
        var TotalHeadshotPct : float = 0.0
        var TotalAccuracyPct : float = 0.0
        var TotalReactionMs : float = 0.0
        var TotalRoundDuration : float = 0.0
        var TotalBuilds : int = 0
        var TotalEdits : int = 0

        # ── Streak Tracking ──────────────────────────────────────────────────
        var CurrentWinStreak : int = 0
        var CurrentLossStreak : int = 0
        var BestWinStreak : int = 0
        var BestLossStreak : int = 0

        # ── Iterate All Rounds ───────────────────────────────────────────────
        for (M : History):
            # Win/Loss/Draw counting
            if (M.Outcome = OUTCOME_PLAYER_WIN):
                set Summary.Wins += 1
                set CurrentWinStreak += 1
                set CurrentLossStreak = 0
                if (CurrentWinStreak > BestWinStreak):
                    set BestWinStreak = CurrentWinStreak
            else if (M.Outcome = OUTCOME_BOT_WIN):
                set Summary.Losses += 1
                set CurrentLossStreak += 1
                set CurrentWinStreak = 0
                if (CurrentLossStreak > BestLossStreak):
                    set BestLossStreak = CurrentLossStreak
            else:
                set Summary.Draws += 1
                set CurrentWinStreak = 0
                set CurrentLossStreak = 0

            # Metric accumulation
            set TotalDPS += M.DPS
            set TotalHeadshotPct += M.HeadshotPct
            set TotalAccuracyPct += M.AccuracyPct
            set TotalReactionMs += M.ReactionTimeMs
            set TotalRoundDuration += M.RoundDurationSec
            set TotalBuilds += M.BuildsPlaced
            set TotalEdits += M.EditsPerformed

            # ELO extremes
            if (M.PlayerELO > Summary.PeakELO):
                set Summary.PeakELO = M.PlayerELO
            if (M.PlayerELO < Summary.LowestELO):
                set Summary.LowestELO = M.PlayerELO

        # ── Compute Averages ─────────────────────────────────────────────────
        Count := History.Length * 1.0
        if (Count > 0.0):
            set Summary.AvgDPS = TotalDPS / Count
            set Summary.AvgHeadshotPct = TotalHeadshotPct / Count
            set Summary.AvgAccuracyPct = TotalAccuracyPct / Count
            set Summary.AvgReactionMs = TotalReactionMs / Count
            set Summary.AvgRoundDurationSec = TotalRoundDuration / Count

        # ── Streaks and Builds ───────────────────────────────────────────────
        set Summary.LongestWinStreak = BestWinStreak
        set Summary.LongestLossStreak = BestLossStreak
        set Summary.TotalBuildsPlaced = TotalBuilds
        set Summary.TotalEditsPerformed = TotalEdits

        Logger.Print("AGGREGATOR: ── Session Compiled ──")
        Logger.Print("AGGREGATOR:   Rounds: {Summary.TotalRounds} (W:{Summary.Wins} L:{Summary.Losses} D:{Summary.Draws})")
        Logger.Print("AGGREGATOR:   ELO: {Summary.StartingELO} -> {Summary.FinalELO} (Peak:{Summary.PeakELO} Low:{Summary.LowestELO})")
        Logger.Print("AGGREGATOR:   Avg DPS: {Summary.AvgDPS} | Avg HS%: {Summary.AvgHeadshotPct} | Avg Acc%: {Summary.AvgAccuracyPct}")
        Logger.Print("AGGREGATOR:   Avg Reaction: {Summary.AvgReactionMs}ms | Avg Round: {Summary.AvgRoundDurationSec}s")
        Logger.Print("AGGREGATOR:   Builds: {Summary.TotalBuildsPlaced} | Edits: {Summary.TotalEditsPerformed}")
        Logger.Print("AGGREGATOR:   Streaks: Win {Summary.LongestWinStreak} | Loss {Summary.LongestLossStreak}")
        Logger.Print("AGGREGATOR:   Duration: {Summary.SessionDurationMin} minutes")

        Summary

    # ══════════════════════════════════════════════════════════════════════════
    # CROSS-SESSION DELTA
    # Compares the current session summary against a previous one
    # (loaded from persistence). Returns a delta struct the coach can
    # use: "Your DPS improved by 15% since last session!"
    # ══════════════════════════════════════════════════════════════════════════
    ComputeSessionDelta<public>(
        Current : session_summary,
        Previous : session_summary
    ) : session_delta =
        Delta := session_delta{}

        # ELO change
        set Delta.ELOChange = Current.FinalELO - Previous.FinalELO

        # Metric deltas (positive = improvement)
        set Delta.DPSDelta = Current.AvgDPS - Previous.AvgDPS
        set Delta.HeadshotDelta = Current.AvgHeadshotPct - Previous.AvgHeadshotPct
        set Delta.AccuracyDelta = Current.AvgAccuracyPct - Previous.AvgAccuracyPct
        # Reaction: negative delta = improvement (faster)
        set Delta.ReactionDelta = Previous.AvgReactionMs - Current.AvgReactionMs

        # Win rate comparison
        var CurrentWinRate : float = 0.0
        var PreviousWinRate : float = 0.0
        if (Current.TotalRounds > 0):
            set CurrentWinRate = (Current.Wins * 100.0) / (Current.TotalRounds * 1.0)
        if (Previous.TotalRounds > 0):
            set PreviousWinRate = (Previous.Wins * 100.0) / (Previous.TotalRounds * 1.0)
        set Delta.WinRateDelta = CurrentWinRate - PreviousWinRate

        # Percentage improvements
        if (Previous.AvgDPS > 0.1):
            set Delta.DPSImprovementPct = (Delta.DPSDelta / Previous.AvgDPS) * 100.0
        if (Previous.AvgHeadshotPct > 0.1):
            set Delta.HeadshotImprovementPct = (Delta.HeadshotDelta / Previous.AvgHeadshotPct) * 100.0
        if (Previous.AvgReactionMs > 0.1):
            set Delta.ReactionImprovementPct = (Delta.ReactionDelta / Previous.AvgReactionMs) * 100.0

        # Did the player reach a new peak?
        set Delta.IsNewPeakELO = false
        if (Current.PeakELO > Previous.PeakELO):
            set Delta.IsNewPeakELO = true

        Logger.Print("AGGREGATOR: Session delta — ELO:{Delta.ELOChange} DPS:{Delta.DPSDelta} HS:{Delta.HeadshotDelta} WinRate:{Delta.WinRateDelta}")
        Delta

    # ══════════════════════════════════════════════════════════════════════════
    # BEST/WORST ROUND IDENTIFICATION
    # Returns the index (0-based) of the best and worst rounds by DPS.
    # Used by the post-round scorecard to highlight peak performance.
    # ══════════════════════════════════════════════════════════════════════════
    FindBestRoundByDPS<public>(History : []round_metrics) : int =
        var BestIdx : int = 0
        var BestDPS : float = 0.0
        var Idx : int = 0
        for (M : History):
            if (M.DPS > BestDPS):
                set BestDPS = M.DPS
                set BestIdx = Idx
            set Idx += 1
        BestIdx

    FindWorstRoundByDPS<public>(History : []round_metrics) : int =
        var WorstIdx : int = 0
        var WorstDPS : float = 999999.0
        var Idx : int = 0
        for (M : History):
            if (M.DPS < WorstDPS):
                set WorstDPS = M.DPS
                set WorstIdx = Idx
            set Idx += 1
        WorstIdx

    FindBestRoundByAccuracy<public>(History : []round_metrics) : int =
        var BestIdx : int = 0
        var BestAcc : float = 0.0
        var Idx : int = 0
        for (M : History):
            if (M.AccuracyPct > BestAcc):
                set BestAcc = M.AccuracyPct
                set BestIdx = Idx
            set Idx += 1
        BestIdx

    FindFastestReactionRound<public>(History : []round_metrics) : int =
        var BestIdx : int = 0
        var FastestMs : float = 999999.0
        var Idx : int = 0
        for (M : History):
            if (M.ReactionTimeMs > 0.1):
                if (M.ReactionTimeMs < FastestMs):
                    set FastestMs = M.ReactionTimeMs
                    set BestIdx = Idx
            set Idx += 1
        BestIdx

    # ══════════════════════════════════════════════════════════════════════════
    # BRACKET DISTRIBUTION
    # Counts how many rounds the player spent at each ELO bracket.
    # Returns an array of 5 ints: [Beginner, Intermediate, Advanced, Pro, Elite]
    # Used by the progress panel to show bracket time distribution.
    # ══════════════════════════════════════════════════════════════════════════
    CalcBracketDistribution<public>(History : []round_metrics) : []int =
        var Beginner : int = 0
        var Intermediate : int = 0
        var Advanced : int = 0
        var Pro : int = 0
        var Elite : int = 0

        for (M : History):
            if (M.PlayerELO < 800):
                set Beginner += 1
            else if (M.PlayerELO < 1200):
                set Intermediate += 1
            else if (M.PlayerELO < 1600):
                set Advanced += 1
            else if (M.PlayerELO < 2000):
                set Pro += 1
            else:
                set Elite += 1

        array{Beginner, Intermediate, Advanced, Pro, Elite}

    # ══════════════════════════════════════════════════════════════════════════
    # WIN RATE BY HALF
    # Compares first-half vs second-half win rate to detect improvement
    # within a single session. If second-half win rate > first-half,
    # the player is warming up / adapting.
    # ══════════════════════════════════════════════════════════════════════════
    CalcWinRateByHalf<public>(History : []round_metrics) : []float =
        if (History.Length < 4):
            return array{0.0, 0.0}

        var MidPoint : int = 0
        if (Half := History.Length / 2):
            set MidPoint = Floor(Half)
            
        var FirstHalfWins : int = 0
        var SecondHalfWins : int = 0
        var Idx : int = 0

        for (M : History):
            if (M.Outcome = OUTCOME_PLAYER_WIN):
                if (Idx < MidPoint):
                    set FirstHalfWins += 1
                else:
                    set SecondHalfWins += 1
            set Idx += 1

        var FirstHalfRate : float = 0.0
        var SecondHalfRate : float = 0.0
        if (MidPoint > 0):
            set FirstHalfRate = (FirstHalfWins * 100.0) / (MidPoint * 1.0)
        SecondHalfSize := History.Length - MidPoint
        if (SecondHalfSize > 0):
            set SecondHalfRate = (SecondHalfWins * 100.0) / (SecondHalfSize * 1.0)

        array{FirstHalfRate, SecondHalfRate}

    # ══════════════════════════════════════════════════════════════════════════
    # CONSISTENCY SCORE
    # Measures how consistent the player's DPS is across rounds.
    # Returns a float [0.0, 100.0] where 100 = perfectly consistent.
    # Computed as 100 - (coefficient of variation * 100).
    # Consistency is a key competitive skill — a player who hits 80 DPS
    # every round is more dangerous than one who alternates 40 and 120.
    # ══════════════════════════════════════════════════════════════════════════
    CalcConsistencyScore<public>(History : []round_metrics) : float =
        if (History.Length < 3):
            return 0.0

        # Calculate mean DPS
        var TotalDPS : float = 0.0
        for (M : History):
            set TotalDPS += M.DPS
        Mean := TotalDPS / (History.Length * 1.0)

        if (Mean < 0.1):
            return 0.0

        # Calculate variance
        var SumSquaredDiff : float = 0.0
        for (M : History):
            Diff := M.DPS - Mean
            set SumSquaredDiff += Diff * Diff
        Variance := SumSquaredDiff / (History.Length * 1.0)

        # Standard deviation
        StdDev := Sqrt(Variance)

        # Coefficient of variation (0 = perfect consistency)
        CV := StdDev / Mean

        # Convert to score (0-100 where 100 = perfect)
        Score := (1.0 - CV) * 100.0
        if (Score < 0.0):
            return 0.0
        if (Score > 100.0):
            return 100.0
        Score

log_agg_ch := class(log_channel):

# ══════════════════════════════════════════════════════════════════════════════
# SESSION DELTA — Cross-session comparison data
# Produced by ComputeSessionDelta, consumed by the coach for feedback.
# ══════════════════════════════════════════════════════════════════════════════
session_delta<public> := class:
    var ELOChange<public>              : int = 0
    var DPSDelta<public>               : float = 0.0
    var HeadshotDelta<public>          : float = 0.0
    var AccuracyDelta<public>          : float = 0.0
    var ReactionDelta<public>          : float = 0.0
    var WinRateDelta<public>           : float = 0.0
    var DPSImprovementPct<public>      : float = 0.0
    var HeadshotImprovementPct<public> : float = 0.0
    var ReactionImprovementPct<public> : float = 0.0
    var IsNewPeakELO<public>           : logic = false