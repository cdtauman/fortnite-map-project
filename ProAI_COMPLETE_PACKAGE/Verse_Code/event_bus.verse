# ============================================================================
# FILE: event_bus.verse — Central Event Dispatcher (Pub/Sub Broker)
# LOCATION: Content/ (root)
# PHASE: 1
#
# ARCHITECTURE:
#   14-channel typed pub/sub broker. Producers call Dispatch___(),
#   consumers await ListenFor___(). Shared state fields aggregate
#   session counters that any module can read.
# ============================================================================
using { /Fortnite.com/Devices }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }

# -- Data Structs --
damage_report<public> := struct:
    DamageAmount<public> : float = 0.0
    IsHeadshot<public>   : logic = false
    WeaponTag<public>    : string = ""
    Timestamp<public>    : float = 0.0

build_event_data<public> := struct:
    PieceType<public>     : string = ""
    GridPosition<public>  : string = ""
    Timestamp<public>     : float = 0.0

# -- Event Bus Device --
event_bus<public> := class(creative_device):

    Logger<private> : log = log{Channel := log_eb_ch}

    # -- Events --
    RoundStartEvent<private>     : event() = event(){}
    RoundEndEvent<private>       : event() = event(){}
    PlayerDamageEvent<private>   : event() = event(){}
    BotDamageEvent<private>      : event() = event(){}
    BuildPlacedEvent<private>    : event() = event(){}
    EditPerformedEvent<private>  : event() = event(){}
    BotEliminatedEvent<private>  : event() = event(){}
    PlayerEliminatedEvent<private> : event() = event(){}
    StateChangeEvent<private>    : event() = event(){}
    AnalyticsUpdatedEvent<private> : event() = event(){}
    ArenaResetCompleteEvent<private> : event() = event(){}
    CoachMessageEvent<private>   : event() = event(){}
    ShopPurchaseEvent<private>   : event() = event(){}
    XPAwardedEvent<private>      : event() = event(){}

    # -- Shared State (writable by producers, readable by all) --
    var CurrentRoundNumber<public>    : int = 0
    var LastRoundOutcome<public>      : int = 0
    var ConsecutiveWins<public>       : int = 0
    var ConsecutiveLosses<public>     : int = 0
    var TotalPlayerWins<public>       : int = 0
    var TotalBotWins<public>          : int = 0
    var TotalDraws<public>            : int = 0
    var CurrentGameState<public>      : int = 0
    var LastRoundDPS<public>          : float = 0.0
    var LastRoundHeadshotPct<public>  : float = 0.0
    var SessionStartTime<public>     : float = 0.0

    # -- Damage report storage --
    var LastPlayerDamageReport<public> : damage_report = damage_report{}
    var LastBotDamageReport<public>    : damage_report = damage_report{}
    var LastBuildEvent<public>         : build_event_data = build_event_data{}

    # -- Bot State --
    var BotIsAlive<public>         : logic = false
    var RoundPlayerHeadshots<public> : int = 0

    # -- Session accumulator --
    var SessionTotalPlayerDamage<public> : float = 0.0
    var SessionTotalBotDamage<public>    : float = 0.0
    var SessionTotalBuilds<public>       : int = 0
    var SessionTotalEdits<public>        : int = 0

    # ======================================================================
    # INITIALIZATION
    # ======================================================================
    OnBegin<override>()<suspends> : void =
        set SessionStartTime = GetSimulationElapsedTime()
        Logger.Print("EVENT_BUS: -- Online --")

    # ======================================================================
    # DISPATCH METHODS (producers call these)
    # ======================================================================
    DispatchRoundStart<public>(RoundNum : int) : void =
        set CurrentRoundNumber = RoundNum
        RoundStartEvent.Signal()
        Logger.Print("EVENT_BUS: RoundStart #{RoundNum}")

    DispatchRoundEnd<public>(Outcome : int, PlayerELO : int) : void =
        set LastRoundOutcome = Outcome
        if (Outcome = 1):
            set TotalPlayerWins += 1
            set ConsecutiveWins += 1
            set ConsecutiveLosses = 0
        else if (Outcome = 2):
            set TotalBotWins += 1
            set ConsecutiveLosses += 1
            set ConsecutiveWins = 0
        else:
            set TotalDraws += 1
            set ConsecutiveWins = 0
            set ConsecutiveLosses = 0
        RoundEndEvent.Signal()
        Logger.Print("EVENT_BUS: RoundEnd outcome={Outcome} ELO={PlayerELO}")

    DispatchPlayerDamage<public>(Report : damage_report) : void =
        set LastPlayerDamageReport = Report
        set SessionTotalPlayerDamage += Report.DamageAmount
        PlayerDamageEvent.Signal()

    DispatchBotDamage<public>(Report : damage_report) : void =
        set LastBotDamageReport = Report
        set SessionTotalBotDamage += Report.DamageAmount
        BotDamageEvent.Signal()

    DispatchBuildPlaced<public>(Data : build_event_data) : void =
        set LastBuildEvent = Data
        set SessionTotalBuilds += 1
        BuildPlacedEvent.Signal()

    DispatchEditPerformed<public>(Data : build_event_data) : void =
        set SessionTotalEdits += 1
        EditPerformedEvent.Signal()

    DispatchBotEliminated<public>() : void =
        BotEliminatedEvent.Signal()
        Logger.Print("EVENT_BUS: BotEliminated")

    DispatchPlayerEliminated<public>() : void =
        PlayerEliminatedEvent.Signal()
        Logger.Print("EVENT_BUS: PlayerEliminated")

    DispatchStateChange<public>(NewState : int) : void =
        set CurrentGameState = NewState
        StateChangeEvent.Signal()
        Logger.Print("EVENT_BUS: StateChange -> {NewState}")

    DispatchAnalyticsUpdated<public>(DPS : float, HeadshotPct : float, ReactionMs : float, EditSpeed : float) : void =
        set LastRoundDPS = DPS
        set LastRoundHeadshotPct = HeadshotPct
        AnalyticsUpdatedEvent.Signal()

    DispatchArenaResetComplete<public>() : void =
        ArenaResetCompleteEvent.Signal()
        Logger.Print("EVENT_BUS: ArenaResetComplete")

    DispatchCoachMessage<public>(Msg : string) : void =
        CoachMessageEvent.Signal()

    DispatchShopPurchase<public>(ItemID : int) : void =
        ShopPurchaseEvent.Signal()

    DispatchXPAwarded<public>(Amount : int) : void =
        XPAwardedEvent.Signal()

    DispatchCountdownTick<public>(SecondsRemaining : int) : void =
        Logger.Print("EVENT_BUS: CountdownTick {SecondsRemaining}s")

    # ======================================================================
    # LISTEN METHODS (consumers await these)
    # ======================================================================
    ListenForRoundStart<public>()<suspends> : void =
        RoundStartEvent.Await()

    ListenForRoundEnd<public>()<suspends> : void =
        RoundEndEvent.Await()

    ListenForPlayerDamage<public>()<suspends> : void =
        PlayerDamageEvent.Await()

    ListenForBotDamage<public>()<suspends> : void =
        BotDamageEvent.Await()

    ListenForBuildPlaced<public>()<suspends> : void =
        BuildPlacedEvent.Await()

    ListenForEditPerformed<public>()<suspends> : void =
        EditPerformedEvent.Await()

    ListenForBotEliminated<public>()<suspends> : void =
        BotEliminatedEvent.Await()

    ListenForPlayerEliminated<public>()<suspends> : void =
        PlayerEliminatedEvent.Await()

    ListenForStateChange<public>()<suspends> : void =
        StateChangeEvent.Await()

    ListenForAnalyticsUpdated<public>()<suspends> : void =
        AnalyticsUpdatedEvent.Await()

    ListenForArenaResetComplete<public>()<suspends> : void =
        ArenaResetCompleteEvent.Await()

    ListenForCoachMessage<public>()<suspends> : void =
        CoachMessageEvent.Await()

    # ======================================================================
    # UTILITY
    # ======================================================================
    GetSessionDurationMinutes<public>() : float =
        (GetSimulationElapsedTime() - SessionStartTime) / 60.0

    ResetSessionCounters<public>() : void =
        set SessionTotalPlayerDamage = 0.0
        set SessionTotalBotDamage = 0.0
        set SessionTotalBuilds = 0
        set SessionTotalEdits = 0

log_eb_ch := class(log_channel):