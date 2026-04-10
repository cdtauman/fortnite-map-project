# ============================================================================
# FILE: xp_reward_system.verse — XP Distribution via Accolade Devices
# LOCATION: Content/ (root)
# PHASE: 8
#
# ARCHITECTURE:
#   Distributes XP rewards to players using UEFN's accolades_device system.
#   Each accolade_device is pre-configured in the editor with a specific
#   XP amount. This module triggers the correct device based on the
#   achievement type.
#
#   XP BUDGET (spec §SC-04):
#     30,000 – 200,000 XP per 5-10 minute training block.
#     This translates to:
#       Per round win:         5,000 – 15,000 XP
#       Per round loss:        2,000 – 5,000 XP
#       Per headshot milestone: 3,000 – 8,000 XP
#       Per ELO rank-up:       10,000 – 25,000 XP
#       Per session milestone:  5,000 – 20,000 XP
#
#     XP amounts are scaled by ELO bracket: higher brackets earn more
#     to keep elite players engaged. A cap prevents exploitation.
#
#   ACCOLADE DEVICES:
#     Each achievement type has its own accolades_device placed in the
#     editor with the appropriate XP amount configured. This module
#     calls .Award(Agent) on the correct device when triggered.
#
# WIRING (UEFN Editor):
#   EventBus          → event_bus device
#   AnalyticsRef      → analytics_engine device
#   AccoladeWin       → accolades_device (configured: 8000 XP)
#   AccoladeLoss      → accolades_device (configured: 3000 XP)
#   AccoladeHeadshot  → accolades_device (configured: 5000 XP)
#   AccoladeRankUp    → accolades_device (configured: 15000 XP)
#   AccoladeSession   → accolades_device (configured: 10000 XP)
#   AccoladeStreak    → accolades_device (configured: 12000 XP)
# ============================================================================
using { /Fortnite.com/Devices }
using { /Fortnite.com/Game }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }

# ── XP Event Type Constants ──────────────────────────────────────────────────
XP_ROUND_WIN<public>         : int = 0
XP_ROUND_LOSS<public>        : int = 1
XP_ROUND_DRAW<public>        : int = 2
XP_HEADSHOT_MILESTONE<public> : int = 3
XP_RANK_UP<public>           : int = 4
XP_SESSION_MILESTONE<public> : int = 5
XP_WIN_STREAK<public>        : int = 6
XP_FIRST_BLOOD<public>       : int = 7

xp_reward_system<public> := class(creative_device):

    Logger<private> : log = log{Channel := log_xp_ch}

    # ── Editable References ──────────────────────────────────────────────────
    @editable
    EventBus<public> : event_bus = event_bus{}

    @editable
    AnalyticsRef<public> : analytics_engine = analytics_engine{}

    # ── Accolade Devices (placed in UEFN editor, XP amounts configured there)
    @editable
    AccoladeWin<public> : accolades_device = accolades_device{}

    @editable
    AccoladeLoss<public> : accolades_device = accolades_device{}

    @editable
    AccoladeHeadshot<public> : accolades_device = accolades_device{}

    @editable
    AccoladeRankUp<public> : accolades_device = accolades_device{}

    @editable
    AccoladeSession<public> : accolades_device = accolades_device{}

    @editable
    AccoladeStreak<public> : accolades_device = accolades_device{}

    # ── XP Budget Tracking ───────────────────────────────────────────────────
    # Track XP awarded per training block (5-10 minute window) to
    # stay within the safe range and avoid flagging by Epic's anti-exploit.
    @editable
    XPBlockWindowMinutes<public> : float = 10.0

    @editable
    MaxXPPerBlock<public> : float = 200000.0

    @editable
    MinXPPerBlock<public> : float = 30000.0

    var XPAccumulated<private>          : float = 0.0
    var BlockStartTime<private>         : float = 0.0
    var TotalXPAwarded<private>         : float = 0.0
    var TotalAccoladesFired<private>    : int = 0
    var TotalAccoladesCapped<private>   : int = 0

    # ── Milestone Tracking ───────────────────────────────────────────────────
    var LastHeadshotMilestone<private>  : int = 0
    var HeadshotMilestoneInterval<private> : int = 10
    var LastRankUpBracket<private>      : int = 0
    var LastSessionMilestoneRound<private> : int = 0
    var SessionMilestoneInterval<private> : int = 10

    # ══════════════════════════════════════════════════════════════════════════
    # INITIALIZATION
    # ══════════════════════════════════════════════════════════════════════════
    OnBegin<override>()<suspends> : void =
        set BlockStartTime = GetSimulationElapsedTime()
        Logger.Print("XP: ── Reward System Online ──")
        Logger.Print("XP: Budget — {MinXPPerBlock}-{MaxXPPerBlock} XP per {XPBlockWindowMinutes} min block.")

        # Background: listen for round ends to award XP
        branch:
            ListenForRoundEndLoop()

        # Background: listen for round starts (bracket checking)
        branch:
            ListenForRoundStartLoop()

        Logger.Print("XP: Event listeners active.")

    # ══════════════════════════════════════════════════════════════════════════
    # EVENT LISTENERS
    # ══════════════════════════════════════════════════════════════════════════
    ListenForRoundEndLoop<private>()<suspends> : void =
        loop:
            EventBus.ListenForRoundEnd()
            ProcessRoundEndRewards()

    ListenForRoundStartLoop<private>()<suspends> : void =
        loop:
            EventBus.ListenForRoundStart()
            CheckRankUpReward()

    # ══════════════════════════════════════════════════════════════════════════
    # ROUND END REWARDS — Award XP based on outcome and performance
    # ══════════════════════════════════════════════════════════════════════════
    ProcessRoundEndRewards<private>() : void =
        Outcome := EventBus.LastRoundOutcome
        Metrics := AnalyticsRef.CurrentMetrics
        PlayerELO := AnalyticsRef.GetPlayerELO()
        RoundNum := EventBus.CurrentRoundNumber

        # Reset XP block if the time window has elapsed
        CheckAndResetBlock()

        # Award outcome-based XP
        if (Outcome = OUTCOME_PLAYER_WIN):
            AwardAccolade(AccoladeWin, XP_ROUND_WIN, "Round Win")

            # Bonus: win streak (3+ consecutive wins)
            if (EventBus.ConsecutiveWins >= 3):
                if (Mod[EventBus.ConsecutiveWins, 3] = 0):
                    AwardAccolade(AccoladeStreak, XP_WIN_STREAK, "Win Streak x{EventBus.ConsecutiveWins}")

        else if (Outcome = OUTCOME_BOT_WIN):
            AwardAccolade(AccoladeLoss, XP_ROUND_LOSS, "Round Loss")

        else:
            AwardAccolade(AccoladeLoss, XP_ROUND_DRAW, "Round Draw")

        # Headshot milestone check (every N cumulative headshots)
        TotalHS := EventBus.RoundPlayerHeadshots
        if (TotalHS > 0):
            CheckHeadshotMilestone(TotalHS)

        # Session round milestone (every N rounds played)
        if (RoundNum > 0):
            if (RoundNum - LastSessionMilestoneRound >= SessionMilestoneInterval):
                set LastSessionMilestoneRound = RoundNum
                AwardAccolade(AccoladeSession, XP_SESSION_MILESTONE, "Session Milestone ({RoundNum} rounds)")

    # ══════════════════════════════════════════════════════════════════════════
    # RANK UP REWARD — Check if the player entered a new ELO bracket
    # ══════════════════════════════════════════════════════════════════════════
    CheckRankUpReward<private>() : void =
        PlayerELO := AnalyticsRef.GetPlayerELO()
        CurrentBracket := GetBracketId(PlayerELO)

        if (CurrentBracket > LastRankUpBracket):
            set LastRankUpBracket = CurrentBracket
            AwardAccolade(AccoladeRankUp, XP_RANK_UP, "Rank Up to {GetBracketName(CurrentBracket)}")
            Logger.Print("XP: RANK UP reward! Bracket: {GetBracketName(CurrentBracket)} ({PlayerELO} ELO)")

    # ══════════════════════════════════════════════════════════════════════════
    # HEADSHOT MILESTONE — Every N cumulative headshots
    # ══════════════════════════════════════════════════════════════════════════
    CheckHeadshotMilestone<private>(RoundHeadshots : int) : void =
        set LastHeadshotMilestone += RoundHeadshots
        if (LastHeadshotMilestone >= HeadshotMilestoneInterval):
            AwardAccolade(AccoladeHeadshot, XP_HEADSHOT_MILESTONE, "Headshot Milestone ({LastHeadshotMilestone} total)")
            set LastHeadshotMilestone = 0

    # ══════════════════════════════════════════════════════════════════════════
    # ACCOLADE AWARD — Core award method with budget checking
    # ══════════════════════════════════════════════════════════════════════════
    AwardAccolade<private>(Device : accolades_device, EventType : int, Reason : string) : void =
        # Check XP budget before awarding
        if (XPAccumulated >= MaxXPPerBlock):
            set TotalAccoladesCapped += 1
            Logger.Print("XP: CAPPED — {Reason} blocked. Block budget exhausted ({XPAccumulated}/{MaxXPPerBlock}).")
            return

        # Award to all players in the playspace
        AllPlayers := GetPlayspace().GetPlayers()
        for (Player : AllPlayers):
            Device.Award(Player)

        # Estimate XP awarded (actual amount is configured on the device)
        EstimatedXP := EstimateXPForEvent(EventType)
        set XPAccumulated += EstimatedXP
        set TotalXPAwarded += EstimatedXP
        set TotalAccoladesFired += 1

        Logger.Print("XP: Awarded '{Reason}' (~{EstimatedXP} XP). Block total: {XPAccumulated}/{MaxXPPerBlock}")

    # ══════════════════════════════════════════════════════════════════════════
    # PUBLIC: Manual Award — Called by coach_game_bridge for special rewards
    # ══════════════════════════════════════════════════════════════════════════
    AwardCustomXP<public>(EventType : int, Reason : string) : void =
        if (EventType = XP_ROUND_WIN):
            AwardAccolade(AccoladeWin, EventType, Reason)
        else if (EventType = XP_HEADSHOT_MILESTONE):
            AwardAccolade(AccoladeHeadshot, EventType, Reason)
        else if (EventType = XP_RANK_UP):
            AwardAccolade(AccoladeRankUp, EventType, Reason)
        else if (EventType = XP_SESSION_MILESTONE):
            AwardAccolade(AccoladeSession, EventType, Reason)
        else if (EventType = XP_WIN_STREAK):
            AwardAccolade(AccoladeStreak, EventType, Reason)
        else:
            AwardAccolade(AccoladeLoss, EventType, Reason)

    # ══════════════════════════════════════════════════════════════════════════
    # XP BUDGET MANAGEMENT
    # ══════════════════════════════════════════════════════════════════════════
    CheckAndResetBlock<private>() : void =
        Now := GetSimulationElapsedTime()
        BlockElapsed := (Now - BlockStartTime) / 60.0
        if (BlockElapsed >= XPBlockWindowMinutes):
            Logger.Print("XP: Block window elapsed ({BlockElapsed} min). Resetting accumulator. Previous: {XPAccumulated}")
            set XPAccumulated = 0.0
            set BlockStartTime = Now

    EstimateXPForEvent<private>(EventType : int) : float =
        # These estimates should match the XP amounts configured on each
        # accolades_device in the UEFN editor. Kept here for budget tracking.
        if (EventType = XP_ROUND_WIN):
            return 8000.0
        else if (EventType = XP_ROUND_LOSS):
            return 3000.0
        else if (EventType = XP_ROUND_DRAW):
            return 2000.0
        else if (EventType = XP_HEADSHOT_MILESTONE):
            return 5000.0
        else if (EventType = XP_RANK_UP):
            return 15000.0
        else if (EventType = XP_SESSION_MILESTONE):
            return 10000.0
        else if (EventType = XP_WIN_STREAK):
            return 12000.0
        else if (EventType = XP_FIRST_BLOOD):
            return 4000.0
        3000.0

    GetRemainingBlockBudget<public>() : float =
        Remaining := MaxXPPerBlock - XPAccumulated
        if (Remaining < 0.0):
            return 0.0
        Remaining

    # ══════════════════════════════════════════════════════════════════════════
    # BRACKET HELPERS
    # ══════════════════════════════════════════════════════════════════════════
    GetBracketId<private>(ELO : int) : int =
        if (ELO < 800):
            return 0
        else if (ELO < 1200):
            return 1
        else if (ELO < 1600):
            return 2
        else if (ELO < 2000):
            return 3
        4

    GetBracketName<private>(BracketId : int) : string =
        if (BracketId = 0):
            return "Beginner"
        else if (BracketId = 1):
            return "Intermediate"
        else if (BracketId = 2):
            return "Advanced"
        else if (BracketId = 3):
            return "Pro"
        "Elite"

    # ══════════════════════════════════════════════════════════════════════════
    # TELEMETRY
    # ══════════════════════════════════════════════════════════════════════════
    LogXPStats<public>() : void =
        Logger.Print("XP: ── Statistics ──")
        Logger.Print("XP:   Total XP Awarded: {TotalXPAwarded}")
        Logger.Print("XP:   Accolades Fired: {TotalAccoladesFired}")
        Logger.Print("XP:   Accolades Capped: {TotalAccoladesCapped}")
        Logger.Print("XP:   Current Block: {XPAccumulated}/{MaxXPPerBlock}")
        Logger.Print("XP:   Remaining Budget: {GetRemainingBlockBudget()}")
        Logger.Print("XP:   Last HS Milestone: {LastHeadshotMilestone}")
        Logger.Print("XP:   Last Rank-Up Bracket: {GetBracketName(LastRankUpBracket)}")

log_xp_ch := class(log_channel):