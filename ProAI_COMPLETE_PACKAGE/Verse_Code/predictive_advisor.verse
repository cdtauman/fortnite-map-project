# ============================================================================
# FILE: predictive_advisor.verse — Trend Analysis, Prediction & Anti-Stagnation
# LOCATION: Content/ (root)
# PHASE: 4
#
# ARCHITECTURE:
#   The predictive advisor is the "sports scientist" of the analytics stack.
#   It doesn't compute raw metrics (that's the analytics_engine) — it
#   interprets them over time, detecting patterns that a single-round
#   snapshot would miss:
#
#   1. STAGNATION DETECTION — ELO plateau over N rounds → volatility inject
#   2. FRUSTRATION DETECTION — Consecutive losses + degrading performance
#   3. METRIC TREND ANALYSIS — DPS/accuracy/headshot/reaction rolling slopes
#   4. PERFORMANCE ANOMALY — Sudden skill drop (fatigue, tilt, distraction)
#   5. IMPROVEMENT VELOCITY — How fast the player is getting better
#   6. WEAKNESS IDENTIFICATION — Which metric is the player's worst relative
#      to their bracket expectation
#
#   Results are written into a player_trend struct that the coach_controller
#   and difficulty_mapper consume. The advisor never changes game state
#   directly — it only produces signals for other modules to act on.
#
# ROLLING WINDOW:
#   All analysis operates on the last N rounds from MetricsHistory[].
#   Window sizes are configurable:
#     Short window (3 rounds)  — catches acute changes (tilt, fatigue)
#     Medium window (5 rounds) — ELO stagnation and trend detection
#     Long window (10 rounds)  — baseline establishment and anomaly detection
# ============================================================================
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }

# ══════════════════════════════════════════════════════════════════════════════
# PREDICTIVE ADVISOR
# ══════════════════════════════════════════════════════════════════════════════
predictive_advisor<public> := class:

    Logger<private> : log = log{Channel := log_adv_ch}

    # ── Stagnation Configuration ─────────────────────────────────────────────
    # If ELO changes by less than this over the stagnation window, trigger.
    var StagnationThreshold<public>   : int = 25
    # How many rounds to look back for stagnation check.
    var StagnationWindowSize<public>  : int = 5
    # Cooldown: after volatility injection, skip N rounds before re-checking.
    var VolatilityCooldownRounds<public> : int = 3
    var RoundsSinceLastVolatility<private> : int = 999

    # ── Frustration Configuration ────────────────────────────────────────────
    # Consecutive losses needed to trigger frustration signal.
    var FrustrationLossThreshold<public> : int = 3
    # Performance degradation threshold: if metric drops by this % from
    # baseline, the player is tilting, not just losing to a better bot.
    var DegradationPctThreshold<public> : float = 20.0

    # ── Trend Analysis Configuration ─────────────────────────────────────────
    # Minimum history length needed for trend calculation.
    var MinTrendWindowSize<public>    : int = 3
    # Threshold for considering a metric "changed" vs "stable".
    var DPSTrendThreshold<public>     : float = 5.0
    var AccuracyTrendThreshold<public>: float = 3.0
    var ReactionTrendThreshold<public>: float = 30.0
    var EditSpeedTrendThreshold<public>: float = 0.2

    # ── Anomaly Detection Configuration ──────────────────────────────────────
    # If a metric drops by more than this percentage from the baseline
    # in a single round, flag as anomaly (possible fatigue/tilt).
    var AnomalyDropPct<public>        : float = 35.0

    # ══════════════════════════════════════════════════════════════════════════
    # STAGNATION DETECTION
    # Returns true if the player's ELO hasn't meaningfully changed over
    # the stagnation window. This triggers volatility injection in the
    # ELO calculator (K-factor boost) and bot behavior diversification.
    #
    # Also respects a cooldown: after injecting volatility, we wait
    # a few rounds to see if it helped before triggering again.
    # ══════════════════════════════════════════════════════════════════════════
    ShouldInjectVolatility<public>(History : []round_metrics, CurrentELO : int) : logic =
        # Respect cooldown
        if (RoundsSinceLastVolatility < VolatilityCooldownRounds):
            set RoundsSinceLastVolatility += 1
            return false

        # Need enough history
        if (History.Length < StagnationWindowSize):
            set RoundsSinceLastVolatility += 1
            return false

        # Compare current ELO against ELO from N rounds ago
        WindowStart := History.Length - StagnationWindowSize
        if (OldMetrics := History[WindowStart]):
            OldELO := OldMetrics.PlayerELO
            Diff := AbsInt(CurrentELO - OldELO)

            if (Diff < StagnationThreshold):
                # Additional check: is the player actually performing consistently
                # (stable plateau) vs wildly oscillating (which might look stagnant
                # in net change but is actually volatile)?
                Oscillation := CalcELOOscillation(History, StagnationWindowSize)

                if (Oscillation < StagnationThreshold * 2):
                    # True stagnation: low net change AND low oscillation
                    set RoundsSinceLastVolatility = 0
                    Logger.Print("ADVISOR: Stagnation detected. Net ELO change: {Diff}, Oscillation: {Oscillation} over {StagnationWindowSize} rounds.")
                    return true
                else:
                    # Oscillating: net is small but individual rounds swing a lot
                    # This isn't stagnation — the player is engaged, just inconsistent
                    Logger.Print("ADVISOR: ELO appears stagnant (net:{Diff}) but oscillation is high ({Oscillation}). Not stagnating.")

        set RoundsSinceLastVolatility += 1
        false

    # ══════════════════════════════════════════════════════════════════════════
    # FRUSTRATION DETECTION
    # Two-criteria system: the player must be LOSING AND performing worse.
    # A player who loses 3 rounds but maintains high DPS and accuracy is
    # just facing a tough bot — that's not frustration, it's challenge.
    # A player who loses 3 rounds AND their metrics are declining is tilting.
    #
    # This distinction matters because the response is different:
    #   Challenge → coach says "you're playing well, bot is just tough"
    #   Frustration → coach says "let's take a break" + difficulty ease
    # ══════════════════════════════════════════════════════════════════════════
    DetectFrustration<public>(History : []round_metrics) : logic =
        if (History.Length < FrustrationLossThreshold):
            return false

        # Check for consecutive losses at the tail of history
        ConsecutiveLosses := CountConsecutiveTailLosses(History)
        if (ConsecutiveLosses < FrustrationLossThreshold):
            return false

        # Player IS on a loss streak. Now check if performance is degrading.
        # Compare the loss-streak rounds against the pre-streak baseline.
        BaselineEnd := History.Length - ConsecutiveLosses
        if (BaselineEnd < 2):
            # Not enough baseline data — use loss count alone
            if (ConsecutiveLosses >= 5):
                Logger.Print("ADVISOR: Frustration — {ConsecutiveLosses} consecutive losses (no baseline for degradation check).")
                return true
            return false

        # Compute baseline averages (rounds before the loss streak)
        BaselineDPS := CalcAverageDPS(History, 0, BaselineEnd)
        BaselineAcc := CalcAverageAccuracy(History, 0, BaselineEnd)

        # Compute loss-streak averages
        StreakDPS := CalcAverageDPS(History, BaselineEnd, History.Length)
        StreakAcc := CalcAverageAccuracy(History, BaselineEnd, History.Length)

        # Check for degradation
        DPSDegraded := IsMetricDegraded(BaselineDPS, StreakDPS, DegradationPctThreshold)
        AccDegraded := IsMetricDegraded(BaselineAcc, StreakAcc, DegradationPctThreshold)

        if (DPSDegraded?):
            if (AccDegraded?):
                Logger.Print("ADVISOR: Frustration — {ConsecutiveLosses} losses + DPS AND accuracy degradation.")
                return true

        # Even without dual degradation, 5+ losses is a strong frustration signal
        if (ConsecutiveLosses >= 5):
            Logger.Print("ADVISOR: Frustration — {ConsecutiveLosses} consecutive losses (partial degradation).")
            return true

        false

    # Legacy overload: accepts a plain integer for backward compatibility
    DetectFrustration<public>(ConsecutiveLosses : int) : logic =
        if (ConsecutiveLosses >= FrustrationLossThreshold):
            Logger.Print("ADVISOR: Frustration signal — {ConsecutiveLosses} consecutive losses.")
            return true
        false

    # ══════════════════════════════════════════════════════════════════════════
    # METRIC TREND ANALYSIS
    # Each returns TREND_IMPROVING (+1), TREND_STABLE (0), or TREND_DECLINING (-1).
    # Uses a simple slope comparison: average of recent N/2 rounds vs older N/2.
    # ══════════════════════════════════════════════════════════════════════════

    CalcDPSTrend<public>(History : []round_metrics) : int =
        CalcMetricTrend(History, MetricExtractorDPS(), DPSTrendThreshold)

    CalcAccuracyTrend<public>(History : []round_metrics) : int =
        CalcMetricTrend(History, MetricExtractorAccuracy(), AccuracyTrendThreshold)

    CalcHeadshotTrend<public>(History : []round_metrics) : int =
        CalcMetricTrend(History, MetricExtractorHeadshot(), AccuracyTrendThreshold)

    CalcReactionTimeTrend<public>(History : []round_metrics) : int =
        # Reaction time is INVERTED: lower = better, so we negate
        RawTrend := CalcMetricTrend(History, MetricExtractorReaction(), ReactionTrendThreshold)
        0 - RawTrend

    CalcEditSpeedTrend<public>(History : []round_metrics) : int =
        CalcMetricTrend(History, MetricExtractorEditSpeed(), EditSpeedTrendThreshold)

    # ══════════════════════════════════════════════════════════════════════════
    # FULL TREND REPORT
    # Computes all trends and packages them into a player_trend struct.
    # Called by analytics_engine at EndRoundTracking.
    # ══════════════════════════════════════════════════════════════════════════
    ComputeFullTrend<public>(History : []round_metrics, CurrentELO : int, ConsecutiveLosses : int) : player_trend =
        Trend := player_trend{}

        set Trend.DPSTrend = CalcDPSTrend(History)
        set Trend.AccuracyTrend = CalcAccuracyTrend(History)
        set Trend.HeadshotTrend = CalcHeadshotTrend(History)
        set Trend.ReactionTimeTrend = CalcReactionTimeTrend(History)
        set Trend.BuildSpeedTrend = CalcEditSpeedTrend(History)

        # Compute ELO trend from history
        set Trend.ELOTrend = CalcELOTrend(History)

        # Overall trend: weighted average of individual trends
        TrendSum := Trend.DPSTrend + Trend.AccuracyTrend + Trend.HeadshotTrend + Trend.ReactionTimeTrend + Trend.BuildSpeedTrend
        if (TrendSum >= 3):
            set Trend.OverallTrend = TREND_IMPROVING
        else if (TrendSum <= -3):
            set Trend.OverallTrend = TREND_DECLINING
        else:
            set Trend.OverallTrend = TREND_STABLE

        # Stagnation and frustration flags
        set Trend.IsStagnating = ShouldInjectVolatility(History, CurrentELO)
        set Trend.IsFrustrated = DetectFrustration(History)
        set Trend.ShouldInjectVolatility = Trend.IsStagnating

        Logger.Print("ADVISOR: Trend report — DPS:{Trend.DPSTrend} Acc:{Trend.AccuracyTrend} HS:{Trend.HeadshotTrend} React:{Trend.ReactionTimeTrend} Edit:{Trend.BuildSpeedTrend} Overall:{Trend.OverallTrend}")

        Trend

    # ══════════════════════════════════════════════════════════════════════════
    # PERFORMANCE ANOMALY DETECTION
    # Checks if the most recent round's metrics are dramatically worse
    # than the player's rolling baseline. Flags fatigue, tilt, or AFK.
    # ══════════════════════════════════════════════════════════════════════════
    DetectPerformanceAnomaly<public>(History : []round_metrics) : logic =
        if (History.Length < 4):
            return false

        # Baseline: average of all rounds except the last
        BaselineDPS := CalcAverageDPS(History, 0, History.Length - 1)
        BaselineAcc := CalcAverageAccuracy(History, 0, History.Length - 1)

        # Latest round
        if (Latest := History[History.Length - 1]):
            DPSDrop := CalcDropPct(BaselineDPS, Latest.DPS)
            AccDrop := CalcDropPct(BaselineAcc, Latest.AccuracyPct)

            if (DPSDrop > AnomalyDropPct):
                if (AccDrop > AnomalyDropPct):
                    Logger.Print("ADVISOR: ANOMALY — DPS dropped {DPSDrop}% and Accuracy dropped {AccDrop}% from baseline.")
                    return true
        false

    # ══════════════════════════════════════════════════════════════════════════
    # WEAKNESS IDENTIFICATION
    # Returns the metric name where the player is weakest relative to
    # their ELO bracket's expected baseline. Used by the coach to give
    # targeted advice: "Your headshot% is below average for your bracket."
    # ══════════════════════════════════════════════════════════════════════════
    IdentifyWeakestMetric<public>(History : []round_metrics, PlayerELO : int) : string =
        if (History.Length < 3):
            return "None"

        # Get the player's actual averages from recent history
        RecentDPS := CalcAverageDPS(History, MaxInt(0, History.Length - 5), History.Length)
        RecentAcc := CalcAverageAccuracy(History, MaxInt(0, History.Length - 5), History.Length)
        RecentHS := CalcAverageHeadshot(History, MaxInt(0, History.Length - 5), History.Length)
        RecentReaction := CalcAverageReaction(History, MaxInt(0, History.Length - 5), History.Length)

        # Expected baselines per bracket (approximate midpoint targets)
        var ExpDPS : float = 50.0
        var ExpAcc : float = 40.0
        var ExpHS : float = 15.0
        var ExpReaction : float = 500.0

        if (PlayerELO >= 2000):
            set ExpDPS = 120.0
            set ExpAcc = 70.0
            set ExpHS = 50.0
            set ExpReaction = 150.0
        else if (PlayerELO >= 1600):
            set ExpDPS = 100.0
            set ExpAcc = 60.0
            set ExpHS = 35.0
            set ExpReaction = 250.0
        else if (PlayerELO >= 1200):
            set ExpDPS = 80.0
            set ExpAcc = 50.0
            set ExpHS = 25.0
            set ExpReaction = 350.0
        else if (PlayerELO >= 800):
            set ExpDPS = 60.0
            set ExpAcc = 40.0
            set ExpHS = 15.0
            set ExpReaction = 450.0

        # Calculate deficit percentage for each metric
        DPSDeficit := CalcDeficitPct(RecentDPS, ExpDPS)
        AccDeficit := CalcDeficitPct(RecentAcc, ExpAcc)
        HSDeficit := CalcDeficitPct(RecentHS, ExpHS)
        # Reaction is inverted: higher = worse
        var ReactionDeficit : float = 0.0
        if (ExpReaction > 0.1):
            if (RecentReaction > ExpReaction):
                set ReactionDeficit = ((RecentReaction - ExpReaction) / ExpReaction) * 100.0

        # Find the worst deficit
        var WorstMetric : string = "DPS"
        var WorstDeficit : float = DPSDeficit

        if (AccDeficit > WorstDeficit):
            set WorstMetric = "Accuracy"
            set WorstDeficit = AccDeficit
        if (HSDeficit > WorstDeficit):
            set WorstMetric = "Headshot%"
            set WorstDeficit = HSDeficit
        if (ReactionDeficit > WorstDeficit):
            set WorstMetric = "ReactionTime"
            set WorstDeficit = ReactionDeficit

        Logger.Print("ADVISOR: Weakest metric: {WorstMetric} (deficit: {WorstDeficit}%)")
        WorstMetric

    # ══════════════════════════════════════════════════════════════════════════
    # IMPROVEMENT VELOCITY
    # Returns a float representing how quickly the player is improving.
    # Positive = getting better. Zero = stable. Negative = declining.
    # Computed as the sum of all positive metric trends minus negatives.
    # ══════════════════════════════════════════════════════════════════════════
    CalcImprovementVelocity<public>(History : []round_metrics) : float =
        DPS := CalcDPSTrend(History) * 1.0
        Acc := CalcAccuracyTrend(History) * 1.0
        HS := CalcHeadshotTrend(History) * 1.0
        React := CalcReactionTimeTrend(History) * 1.0
        Edit := CalcEditSpeedTrend(History) * 1.0
        DPS + Acc + HS + React + Edit

    # ══════════════════════════════════════════════════════════════════════════
    # PRIVATE: Generic Trend Calculator
    # Splits the history into two halves and compares their averages.
    # ══════════════════════════════════════════════════════════════════════════
    CalcMetricTrend<private>(History : []round_metrics, Extractor : int, Threshold : float) : int =
        if (History.Length < MinTrendWindowSize):
            return TREND_STABLE

        # Split into older half and recent half
        var MidPoint : int = 0
        if (Half := History.Length / 2):
            set MidPoint = Floor(Half)
            
        OlderAvg := ExtractAverage(History, 0, MidPoint, Extractor)
        RecentAvg := ExtractAverage(History, MidPoint, History.Length, Extractor)

        Diff := RecentAvg - OlderAvg
        if (Diff > Threshold):
            return TREND_IMPROVING
        else if (Diff < (0.0 - Threshold)):
            return TREND_DECLINING
        TREND_STABLE

    # ══════════════════════════════════════════════════════════════════════════
    # PRIVATE: Metric Extractors (encoded as int IDs for generic dispatch)
    # ══════════════════════════════════════════════════════════════════════════
    MetricExtractorDPS<private>() : int = 0
    MetricExtractorAccuracy<private>() : int = 1
    MetricExtractorHeadshot<private>() : int = 2
    MetricExtractorReaction<private>() : int = 3
    MetricExtractorEditSpeed<private>() : int = 4

    ExtractMetricValue<private>(M : round_metrics, Extractor : int) : float =
        if (Extractor = 0):
            return M.DPS
        else if (Extractor = 1):
            return M.AccuracyPct
        else if (Extractor = 2):
            return M.HeadshotPct
        else if (Extractor = 3):
            return M.ReactionTimeMs
        else if (Extractor = 4):
            return M.EditSpeed
        0.0

    ExtractAverage<private>(History : []round_metrics, StartIdx : int, EndIdx : int, Extractor : int) : float =
        var Total : float = 0.0
        var Count : int = 0
        var Idx : int = 0
        for (M : History):
            if (Idx >= StartIdx):
                if (Idx < EndIdx):
                    set Total += ExtractMetricValue(M, Extractor)
                    set Count += 1
            set Idx += 1
        if (Count > 0):
            return Total / (Count * 1.0)
        0.0

    # ══════════════════════════════════════════════════════════════════════════
    # PRIVATE: Specific Metric Averagers (for frustration/anomaly checks)
    # ══════════════════════════════════════════════════════════════════════════
    CalcAverageDPS<private>(History : []round_metrics, StartIdx : int, EndIdx : int) : float =
        ExtractAverage(History, StartIdx, EndIdx, MetricExtractorDPS())

    CalcAverageAccuracy<private>(History : []round_metrics, StartIdx : int, EndIdx : int) : float =
        ExtractAverage(History, StartIdx, EndIdx, MetricExtractorAccuracy())

    CalcAverageHeadshot<private>(History : []round_metrics, StartIdx : int, EndIdx : int) : float =
        ExtractAverage(History, StartIdx, EndIdx, MetricExtractorHeadshot())

    CalcAverageReaction<private>(History : []round_metrics, StartIdx : int, EndIdx : int) : float =
        ExtractAverage(History, StartIdx, EndIdx, MetricExtractorReaction())

    # ══════════════════════════════════════════════════════════════════════════
    # PRIVATE: ELO-Specific Analysis
    # ══════════════════════════════════════════════════════════════════════════
    CalcELOTrend<private>(History : []round_metrics) : int =
        if (History.Length < MinTrendWindowSize):
            return TREND_STABLE
            
        var MidPoint : int = 0
        if (Half := History.Length / 2):
            set MidPoint = Floor(Half)
            
        OlderELO := ExtractAverage(History, 0, MidPoint, -1)
        RecentELO := ExtractAverage(History, MidPoint, History.Length, -1)
        # Manual ELO extraction since it's an int field
        var OlderTotal : int = 0
        var OlderCount : int = 0
        var RecentTotal : int = 0
        var RecentCount : int = 0
        var Idx : int = 0
        for (M : History):
            if (Idx < MidPoint):
                set OlderTotal += M.PlayerELO
                set OlderCount += 1
            else:
                set RecentTotal += M.PlayerELO
                set RecentCount += 1
            set Idx += 1
        var OAvg : float = 0.0
        var RAvg : float = 0.0
        if (OlderCount > 0):
            set OAvg = (OlderTotal * 1.0) / (OlderCount * 1.0)
        if (RecentCount > 0):
            set RAvg = (RecentTotal * 1.0) / (RecentCount * 1.0)
        Diff := RAvg - OAvg
        if (Diff > 15.0):
            return TREND_IMPROVING
        else if (Diff < -15.0):
            return TREND_DECLINING
        TREND_STABLE

    CalcELOOscillation<private>(History : []round_metrics, WindowSize : int) : int =
        # Sum of absolute ELO changes within the window
        var StartIdx : int = History.Length - WindowSize
        if (StartIdx < 0):
            set StartIdx = 0
        var TotalChange : int = 0
        var PrevELO : int = 0
        var IsFirst : logic = true
        var Idx : int = 0
        for (M : History):
            if (Idx >= StartIdx):
                if (IsFirst?):
                    set PrevELO = M.PlayerELO
                    set IsFirst = false
                else:
                    set TotalChange += AbsInt(M.PlayerELO - PrevELO)
                    set PrevELO = M.PlayerELO
            set Idx += 1
        TotalChange

    # ══════════════════════════════════════════════════════════════════════════
    # PRIVATE: Loss Streak Counter
    # ══════════════════════════════════════════════════════════════════════════
    CountConsecutiveTailLosses<private>(History : []round_metrics) : int =
        var Count : int = 0
        var Idx : int = History.Length - 1
        loop:
            if (Idx < 0):
                break
            if (M := History[Idx]):
                if (M.Outcome = OUTCOME_BOT_WIN):
                    set Count += 1
                else:
                    break
            set Idx -= 1
        Count

    # ══════════════════════════════════════════════════════════════════════════
    # PRIVATE: Math Utilities
    # ══════════════════════════════════════════════════════════════════════════
    AbsInt<private>(Value : int) : int =
        if (Value < 0):
            return Value * -1
        Value

    MaxInt<private>(A : int, B : int) : int =
        if (A > B):
            return A
        B

    CalcDropPct<private>(Baseline : float, Current : float) : float =
        if (Baseline > 0.1):
            if (Current < Baseline):
                return ((Baseline - Current) / Baseline) * 100.0
        0.0

    CalcDeficitPct<private>(Actual : float, Expected : float) : float =
        if (Expected > 0.1):
            if (Actual < Expected):
                return ((Expected - Actual) / Expected) * 100.0
        0.0

    IsMetricDegraded<private>(Baseline : float, Current : float, ThresholdPct : float) : logic =
        Drop := CalcDropPct(Baseline, Current)
        if (Drop > ThresholdPct):
            return true
        false

log_adv_ch := class(log_channel):