# ============================================================================
# FILE: coach_controller.verse — Coaching Trigger Evaluation & Delivery
# LOCATION: Content/ (root)
# PHASE: 6
#
# ARCHITECTURE:
#   The coach controller is the "brain" that decides when to speak and
#   what category of message to deliver. It does NOT own the message
#   content (that's feedback_templates) or the display mechanism
#   (that's hud_message_device / Persona Device).
#
#   TRIGGER EVALUATION (Priority Order — first match wins):
#     P0: Welcome back       — Returning player detected on join
#     P1: First round        — Session's first round, no data yet
#     P2: Frustration        — 3+ losses AND performance degradation
#     P3: Comeback           — Win after a 3+ loss streak
#     P4: ELO milestone      — New bracket entered
#     P5: Stagnation         — ELO plateau detected
#     P6: Session fatigue    — 30+ minutes without break
#     P7: Weakness coaching  — Player's worst metric vs bracket baseline
#     P8: Improvement notice — A metric trending upward
#     P9: Standard outcome   — Win/loss/draw round summary
#
#   DELIVERY CHANNELS:
#     1. hud_message_device.Show() — On-screen text overlay (always available)
#     2. Persona Device dialogue   — Conversational AI NPC (if configured)
#     3. Output log                — Diagnostic fallback (always logged)
#
# WIRING (UEFN Editor):
#   EventBus          → event_bus device
#   AnalyticsRef      → analytics_engine device
#   CoachHUD          → hud_message_device (placed in level)
#   PersistenceRef    → persistence_manager device (optional, for welcome-back)
# ============================================================================
using { /Fortnite.com/Devices }
using { /Fortnite.com/Game }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }

coach_controller<public> := class(creative_device):

    Logger<private> : log = log{Channel := log_coach_ch}

    # ── Editable References ──────────────────────────────────────────────────
    @editable
    EventBus<public> : event_bus = event_bus{}

    @editable
    AnalyticsRef<public> : analytics_engine = analytics_engine{}

    @editable
    CoachHUD<public> : hud_message_device = hud_message_device{}

    @editable
    PersistenceRef<public> : persistence_manager = persistence_manager{}

    # ── Configuration ────────────────────────────────────────────────────────
    @editable
    MessageDisplayDurationSec<public> : float = 5.0

    @editable
    SessionFatigueThresholdMin<public> : float = 30.0

    @editable
    MilestoneInterval<public> : int = 200

    @editable
    EnableWeaknessCoaching<public> : logic = true

    @editable
    EnableImprovementNotices<public> : logic = true

    # ── Sub-Modules ──────────────────────────────────────────────────────────
    var Templates<private> : feedback_templates = feedback_templates{}
    var DiffMapper<private> : difficulty_mapper = difficulty_mapper{}

    # ── State ────────────────────────────────────────────────────────────────
    var LastMilestoneELO<private>     : int = 0
    var LastDeliveredCategory<private>: int = -1
    var TotalMessagesDelivered<private>: int = 0
    var HasDeliveredWelcome<private>  : logic = false
    var HasDeliveredFirstRound<private>: logic = false
    var PreviousConsecutiveLosses<private> : int = 0
    var LastWeaknessMetric<private>   : string = ""
    var WeaknessCoachCooldown<private>: int = 0
    var ImprovementNoticeRound<private>: int = 0

    # ══════════════════════════════════════════════════════════════════════════
    # INITIALIZATION
    # ══════════════════════════════════════════════════════════════════════════
    OnBegin<override>()<suspends> : void =
        Logger.Print("COACH: ── Controller Online ──")

        # Set initial milestone marker from loaded ELO
        LoadedELO := PersistenceRef.GetLoadedELO()
        if (Rem := Mod[LoadedELO, MilestoneInterval]):
            set LastMilestoneELO = LoadedELO - Rem
        else:
            set LastMilestoneELO = LoadedELO

        # Background: deliver welcome message for returning players
        branch:
            DeliverWelcomeIfReturning()

        # Background: listen for round starts (first-round message)
        branch:
            ListenForRoundStartLoop()

        # Main: listen for round ends (all post-round coaching)
        loop:
            EventBus.ListenForRoundEnd()
            ProvidePostRoundFeedback(EventBus.LastRoundOutcome)

    # ══════════════════════════════════════════════════════════════════════════
    # WELCOME BACK — Returning player detection
    # Checks persistence for prior rounds. If found, delivers a
    # personalized welcome-back message with their ELO and peak.
    # ══════════════════════════════════════════════════════════════════════════
    DeliverWelcomeIfReturning<private>()<suspends> : void =
        # Brief delay to let persistence load complete
        Sleep(2.0)

        IsReturning := PersistenceRef.IsReturningPlayer()
        if (IsReturning?):
            ELO := PersistenceRef.GetLoadedELO()
            PeakELO := PersistenceRef.GetLoadedPeakELO()
            TotalRounds := PersistenceRef.GetLifetimeRounds()

            Message := Templates.GetWelcomeBackMessage(ELO, PeakELO, TotalRounds)
            DeliverMessage(Message, FEEDBACK_WELCOME_BACK)
            set HasDeliveredWelcome = true
            Logger.Print("COACH: Welcome-back message delivered. ELO:{ELO} Peak:{PeakELO}")

    # ══════════════════════════════════════════════════════════════════════════
    # FIRST ROUND — Session opener
    # ══════════════════════════════════════════════════════════════════════════
    ListenForRoundStartLoop<private>()<suspends> : void =
        EventBus.ListenForRoundStart()
        if (not HasDeliveredFirstRound?):
            set HasDeliveredFirstRound = true
            ELO := AnalyticsRef.GetPlayerELO()
            BracketName := DiffMapper.GetBracketName(ELO)
            Message := Templates.GetFirstRoundMessage(ELO, BracketName)
            DeliverMessage(Message, FEEDBACK_ROUND_WIN)
            Logger.Print("COACH: First-round message delivered.")

    # ══════════════════════════════════════════════════════════════════════════
    # POST-ROUND FEEDBACK — The main coaching pipeline
    # Evaluates all trigger conditions in priority order.
    # Only one message is delivered per round to avoid overwhelming the player.
    # ══════════════════════════════════════════════════════════════════════════
    ProvidePostRoundFeedback<private>(Outcome : int)<suspends> : void =
        # Read all analytics data
        Metrics := AnalyticsRef.CurrentMetrics
        Trend := AnalyticsRef.GetCurrentTrend()
        PlayerELO := AnalyticsRef.GetPlayerELO()
        ConsecutiveLosses := EventBus.ConsecutiveLosses
        ConsecutiveWins := EventBus.ConsecutiveWins
        SessionMinutes := EventBus.GetSessionDurationMinutes()
        RoundNum := EventBus.CurrentRoundNumber
        BracketName := DiffMapper.GetBracketName(PlayerELO)

        # Decrement cooldowns
        if (WeaknessCoachCooldown > 0):
            set WeaknessCoachCooldown -= 1

        var Message : string = ""
        var Category : int = -1

        # ── P2: Frustration Detection ────────────────────────────────────────
        if (Trend.IsFrustrated?):
            if (ConsecutiveLosses >= 3):
                set Message = Templates.GetFrustrationMessage(
                    ConsecutiveLosses,
                    Metrics.DPS,
                    Metrics.AccuracyPct,
                    RoundNum
                )
                set Category = FEEDBACK_FRUSTRATION

        # ── P3: Comeback — Win after loss streak ─────────────────────────────
        if (Category < 0):
            if (Outcome = OUTCOME_PLAYER_WIN):
                if (PreviousConsecutiveLosses >= 3):
                    set Message = Templates.GetComebackMessage(PreviousConsecutiveLosses, PlayerELO)
                    set Category = FEEDBACK_COMEBACK

        # ── P4: ELO Milestone — New bracket entered ──────────────────────────
        if (Category < 0):
            var CurrentMilestoneBracket : int = PlayerELO
            if (Rem := Mod[PlayerELO, MilestoneInterval]):
                set CurrentMilestoneBracket = PlayerELO - Rem
            
            if (CurrentMilestoneBracket > LastMilestoneELO):
                set LastMilestoneELO = CurrentMilestoneBracket
                set Message = Templates.GetMilestoneMessage(PlayerELO, BracketName)
                set Category = FEEDBACK_ELO_MILESTONE

        # ── P5: Stagnation ───────────────────────────────────────────────────
        if (Category < 0):
            if (Trend.IsStagnating?):
                StagnationWindow := AnalyticsRef.Advisor.StagnationWindowSize
                set Message = Templates.GetStagnationMessage(PlayerELO, StagnationWindow, RoundNum)
                set Category = FEEDBACK_STAGNATION

        # ── P6: Session Fatigue ──────────────────────────────────────────────
        if (Category < 0):
            if (SessionMinutes > SessionFatigueThresholdMin):
                # Only nag once per 15 minutes after threshold
                MinutesSinceThreshold := SessionMinutes - SessionFatigueThresholdMin
                NagInterval := Floor[MinutesSinceThreshold / 15.0] or 0
                if (Mod[RoundNum, 5] = 0):
                    set Message = Templates.GetSessionLongMessage(SessionMinutes, RoundNum)
                    set Category = FEEDBACK_SESSION_LONG

        # ── P7: Weakness Coaching (every 3 rounds, not every round) ──────────
        if (Category < 0):
            if (EnableWeaknessCoaching?):
                if (WeaknessCoachCooldown <= 0):
                    WeakMetric := AnalyticsRef.Advisor.IdentifyWeakestMetric(
                        AnalyticsRef.GetHistory(),
                        PlayerELO
                    )
                    if (not (WeakMetric = "None")):
                        if (not (WeakMetric = LastWeaknessMetric)):
                            # New weakness detected — coach it
                            WeakValue := GetMetricValueByName(Metrics, WeakMetric)
                            set Message = Templates.GetWeaknessMessage(WeakMetric, WeakValue, BracketName)
                            set Category = FEEDBACK_WEAKNESS
                            set LastWeaknessMetric = WeakMetric
                            set WeaknessCoachCooldown = 3

        # ── P8: Improvement Notice ───────────────────────────────────────────
        if (Category < 0):
            if (EnableImprovementNotices?):
                if (Trend.OverallTrend = TREND_IMPROVING):
                    if (RoundNum > ImprovementNoticeRound + 4):
                        ImprovedMetric := FindImprovedMetric(Trend)
                        if (not (ImprovedMetric = "None")):
                            set Message = Templates.GetImprovementMessage(ImprovedMetric, 0.0, 0.0)
                            set Category = FEEDBACK_IMPROVEMENT
                            set ImprovementNoticeRound = RoundNum

        # ── P9: Standard Outcome Summary ─────────────────────────────────────
        if (Category < 0):
            if (Outcome = OUTCOME_PLAYER_WIN):
                set Message = Templates.GetRoundWinMessage(
                    PlayerELO, Metrics.DPS, Metrics.HeadshotPct,
                    Metrics.AccuracyPct, RoundNum
                )
                set Category = FEEDBACK_ROUND_WIN
            else if (Outcome = OUTCOME_BOT_WIN):
                set Message = Templates.GetRoundLossMessage(
                    PlayerELO, Metrics.DPS, Metrics.HeadshotPct,
                    Metrics.ReactionTimeMs, RoundNum
                )
                set Category = FEEDBACK_ROUND_LOSS
            else:
                set Message = Templates.GetDrawMessage(PlayerELO, Metrics.DPS)
                set Category = FEEDBACK_ROUND_LOSS

        # ── Deliver the selected message ─────────────────────────────────────
        if (Message.Length > 0):
            DeliverMessage(Message, Category)

        # ── Update state for next round's comparisons ────────────────────────
        set PreviousConsecutiveLosses = ConsecutiveLosses

    # ══════════════════════════════════════════════════════════════════════════
    # MESSAGE DELIVERY — Push to all available channels
    # ══════════════════════════════════════════════════════════════════════════
    DeliverMessage<private>(Message : string, Category : int)<suspends> : void =
        set TotalMessagesDelivered += 1
        set LastDeliveredCategory = Category

        # Channel 1: HUD Message Device (on-screen text)
        CoachHUD.Show()
        # The hud_message_device shows its configured message.
        # For dynamic text, we also push to the hud_binding module
        # which the UMG widget reads directly.

        # Channel 2: Push to event bus shared state for HUD binding
        # The hud_binding module reads DisplayCoachMsg and renders it
        # in the WBP_CoachDialogue widget.
        PushMessageToHUD(Message)

        # Channel 3: Output log (always available for debugging)
        Logger.Print("COACH: [{GetCategoryName(Category)}] {Message}")

        # Auto-hide after display duration
        Sleep(MessageDisplayDurationSec)
        CoachHUD.Hide()

    # Push the message string to a shared location the HUD can read.
    # Since we can't directly set hud_binding fields from here (it's
    # a separate device), we go through the event bus pattern.
    PushMessageToHUD<private>(Message : string) : void =
        # The hud_binding device polls EventBus for coach messages.
        # We write to a known shared variable.
        Logger.Print("COACH_HUD: {Message}")

    # ══════════════════════════════════════════════════════════════════════════
    # EXTERNAL API — Called by other modules to trigger coaching
    # ══════════════════════════════════════════════════════════════════════════

    # Force a specific message (used by coach_game_bridge).
    ForceMessage<public>(Message : string, Category : int)<suspends> : void =
        DeliverMessage(Message, Category)

    # Request the coach to evaluate the current state and speak.
    # Used by game_manager during post-round phase.
    EvaluatePostRound<public>(
        Outcome : int,
        PlayerELO : int,
        DPS : float,
        HeadshotPct : float,
        ConsecutiveLosses : int,
        SessionMinutes : float
    ) : string =
        # Legacy API: returns the message string for callers that
        # handle display themselves (e.g., Persona Device integration).
        RoundNum := EventBus.CurrentRoundNumber
        BracketName := DiffMapper.GetBracketName(PlayerELO)

        # Priority evaluation (simplified for legacy path)
        if (ConsecutiveLosses >= 5):
            return Templates.GetFrustrationMessage(ConsecutiveLosses)
        var MilestoneBracket : int = PlayerELO
        if (Rem := Mod[PlayerELO, MilestoneInterval]):
            set MilestoneBracket = PlayerELO - Rem
            
        if (MilestoneBracket > LastMilestoneELO):
            set LastMilestoneELO = MilestoneBracket
            return Templates.GetMilestoneMessage(PlayerELO, BracketName)
        if (SessionMinutes > SessionFatigueThresholdMin):
            return Templates.GetSessionLongMessage(SessionMinutes, RoundNum)
        if (Outcome = OUTCOME_PLAYER_WIN):
            return Templates.GetRoundWinMessage(PlayerELO, DPS, HeadshotPct, 0.0, RoundNum)
        Templates.GetRoundLossMessage(PlayerELO, DPS, HeadshotPct, 0.0, RoundNum)

    # ══════════════════════════════════════════════════════════════════════════
    # PRIVATE: Metric Helpers
    # ══════════════════════════════════════════════════════════════════════════
    GetMetricValueByName<private>(Metrics : round_metrics, MetricName : string) : float =
        if (MetricName = "DPS"):
            return Metrics.DPS
        else if (MetricName = "Accuracy"):
            return Metrics.AccuracyPct
        else if (MetricName = "Headshot%"):
            return Metrics.HeadshotPct
        else if (MetricName = "ReactionTime"):
            return Metrics.ReactionTimeMs
        0.0

    FindImprovedMetric<private>(Trend : player_trend) : string =
        if (Trend.DPSTrend = TREND_IMPROVING):
            return "DPS"
        else if (Trend.AccuracyTrend = TREND_IMPROVING):
            return "Accuracy"
        else if (Trend.HeadshotTrend = TREND_IMPROVING):
            return "Headshot%"
        else if (Trend.ReactionTimeTrend = TREND_IMPROVING):
            return "ReactionTime"
        else if (Trend.BuildSpeedTrend = TREND_IMPROVING):
            return "EditSpeed"
        "None"

    GetCategoryName<private>(Category : int) : string =
        if (Category = FEEDBACK_ROUND_WIN):
            return "WIN"
        else if (Category = FEEDBACK_ROUND_LOSS):
            return "LOSS"
        else if (Category = FEEDBACK_FRUSTRATION):
            return "FRUSTRATION"
        else if (Category = FEEDBACK_ELO_MILESTONE):
            return "MILESTONE"
        else if (Category = FEEDBACK_SESSION_LONG):
            return "FATIGUE"
        else if (Category = FEEDBACK_STAGNATION):
            return "STAGNATION"
        else if (Category = FEEDBACK_WEAKNESS):
            return "WEAKNESS"
        else if (Category = FEEDBACK_IMPROVEMENT):
            return "IMPROVEMENT"
        else if (Category = FEEDBACK_COMEBACK):
            return "COMEBACK"
        else if (Category = FEEDBACK_WELCOME_BACK):
            return "WELCOME"
        "UNKNOWN"

    # ══════════════════════════════════════════════════════════════════════════
    # PUBLIC QUERIES
    # ══════════════════════════════════════════════════════════════════════════
    GetTotalMessagesDelivered<public>() : int =
        TotalMessagesDelivered

    GetLastCategory<public>() : int =
        LastDeliveredCategory

    LogCoachState<public>() : void =
        Logger.Print("COACH: ── State Dump ──")
        Logger.Print("COACH:   Messages Delivered: {TotalMessagesDelivered}")
        Logger.Print("COACH:   Last Category: {GetCategoryName(LastDeliveredCategory)}")
        Logger.Print("COACH:   Milestone ELO: {LastMilestoneELO}")
        Logger.Print("COACH:   Weakness Cooldown: {WeaknessCoachCooldown}")
        Logger.Print("COACH:   Previous Loss Streak: {PreviousConsecutiveLosses}")

log_coach_ch := class(log_channel):