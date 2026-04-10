# ============================================================================
# FILE: coach_game_bridge.verse — Coach → Game State Action Bridge
# LOCATION: Content/ (root)
# PHASE: 6
#
# ARCHITECTURE:
#   Translates coaching decisions into concrete game-state changes.
#   The coach_controller decides WHAT should happen ("reduce difficulty",
#   "spawn practice aids", "unlock advanced drills"). This bridge
#   module executes HOW — it holds @editable references to the actual
#   devices and modules that need to change.
#
#   SUPPORTED ACTIONS (from spec §7.4):
#     1. DIFFICULTY ADJUSTMENT — Ease or intensify the bot after
#        frustration/stagnation detection.
#     2. AID SPAWN — Grant extra materials or health items during
#        frustration to help the player regain confidence.
#     3. BEHAVIOR SWITCH — Change the bot's combat style (e.g., from
#        aggressive box-fight to passive AR-poke) to target weaknesses.
#     4. DRILL UNLOCK — Open gated training modules when the player
#        shows consistent improvement in specific mechanics.
#     5. ARENA MODIFIER — Temporary environmental changes for specific
#        practice scenarios (slow-mo, low-gravity).
#
# WIRING (UEFN Editor):
#   EventBus        → event_bus device
#   AnalyticsRef    → analytics_engine device
#   ArenaCtrlRef    → arena_controller device
#   PersistRef      → persistence_manager device
#   CoachRef        → coach_controller device
#   FrustrationAid  → item_granter_device (grants healing items)
#   CoachCallButton → button_device (lobby "Call Coach" button)
# ============================================================================
using { /Fortnite.com/Devices }
using { /Fortnite.com/Game }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }

# ── Action Type Constants ────────────────────────────────────────────────────
BRIDGE_ACTION_EASE_DIFFICULTY<public>   : int = 0
BRIDGE_ACTION_BOOST_DIFFICULTY<public>  : int = 1
BRIDGE_ACTION_SPAWN_AID<public>        : int = 2
BRIDGE_ACTION_SWITCH_BOT_STYLE<public> : int = 3
BRIDGE_ACTION_UNLOCK_DRILL<public>     : int = 4
BRIDGE_ACTION_APPLY_MODIFIER<public>   : int = 5

coach_game_bridge<public> := class(creative_device):

    Logger<private> : log = log{Channel := log_bridge_ch}

    # ── Editable References ──────────────────────────────────────────────────
    @editable
    EventBus<public> : event_bus = event_bus{}

    @editable
    AnalyticsRef<public> : analytics_engine = analytics_engine{}

    @editable
    ArenaCtrlRef<public> : arena_controller = arena_controller{}

    @editable
    PersistRef<public> : persistence_manager = persistence_manager{}

    @editable
    CoachRef<public> : coach_controller = coach_controller{}

    @editable
    FrustrationAid<public> : item_granter_device = item_granter_device{}

    @editable
    CoachCallButton<public> : button_device = button_device{}

    # ── Configuration ────────────────────────────────────────────────────────
    @editable
    FrustrationELOReduction<public> : int = 50

    @editable
    BoostELOIncrease<public> : int = 25

    # ── State ────────────────────────────────────────────────────────────────
    var TotalActionsExecuted<private>   : int = 0
    var LastActionType<private>         : int = -1
    var HasEasedThisSession<private>    : logic = false
    var DifficultyOverrideActive<private> : logic = false

    # ══════════════════════════════════════════════════════════════════════════
    # INITIALIZATION
    # ══════════════════════════════════════════════════════════════════════════
    OnBegin<override>()<suspends> : void =
        Logger.Print("BRIDGE: ── Coach Game Bridge Online ──")

        # Listen for the "Call Coach" lobby button
        branch:
            ListenCoachCallButton()

        # Listen for round ends to evaluate auto-actions
        branch:
            ListenRoundEndAutoActions()

        Logger.Print("BRIDGE: All listeners active.")

    # ══════════════════════════════════════════════════════════════════════════
    # LOBBY BUTTON — "Call Coach" physical interaction
    # When pressed, the coach delivers an on-demand assessment.
    # ══════════════════════════════════════════════════════════════════════════
    ListenCoachCallButton<private>()<suspends> : void =
        loop:
            InteractingAgent := CoachCallButton.InteractedWithEvent.Await()
            Logger.Print("BRIDGE: Coach Call button pressed.")

            # Deliver an on-demand coaching message
            PlayerELO := AnalyticsRef.GetPlayerELO()
            Trend := AnalyticsRef.GetCurrentTrend()
            History := AnalyticsRef.GetHistory()

            if (Trend.IsFrustrated?):
                CoachRef.ForceMessage(
                    "I can see you are struggling. Let me ease the bot difficulty. Focus on fundamentals.",
                    FEEDBACK_FRUSTRATION
                )
                ExecuteAction(BRIDGE_ACTION_EASE_DIFFICULTY)
            else if (Trend.IsStagnating?):
                CoachRef.ForceMessage(
                    "Your ELO has plateaued. I am switching the bot's style to challenge you differently.",
                    FEEDBACK_STAGNATION
                )
                ExecuteAction(BRIDGE_ACTION_SWITCH_BOT_STYLE)
            else:
                WeakMetric := AnalyticsRef.Advisor.IdentifyWeakestMetric(History, PlayerELO)
                CoachRef.ForceMessage(
                    "Your weakest area right now is {WeakMetric}. Focus your next few rounds on that.",
                    FEEDBACK_WEAKNESS
                )

    # ══════════════════════════════════════════════════════════════════════════
    # AUTO-ACTIONS — Evaluated after every round end
    # The bridge checks the advisor's signals and takes automatic action
    # without the player needing to press a button.
    # ══════════════════════════════════════════════════════════════════════════
    ListenRoundEndAutoActions<private>()<suspends> : void =
        loop:
            EventBus.ListenForRoundEnd()
            Trend := AnalyticsRef.GetCurrentTrend()

            # Auto-ease on frustration (first time only per session)
            if (Trend.IsFrustrated?):
                if (not HasEasedThisSession?):
                    Logger.Print("BRIDGE: Auto-action — Frustration detected. Easing difficulty.")
                    ExecuteAction(BRIDGE_ACTION_EASE_DIFFICULTY)
                    ExecuteAction(BRIDGE_ACTION_SPAWN_AID)
                    set HasEasedThisSession = true

            # Auto-boost when player is on a strong win streak
            if (EventBus.ConsecutiveWins >= 5):
                if (not DifficultyOverrideActive?):
                    Logger.Print("BRIDGE: Auto-action — 5+ win streak. Boosting difficulty.")
                    ExecuteAction(BRIDGE_ACTION_BOOST_DIFFICULTY)

    # ══════════════════════════════════════════════════════════════════════════
    # EXECUTE ACTION — Route to the correct game-state change
    # ══════════════════════════════════════════════════════════════════════════
    ExecuteAction<public>(ActionType : int) : void =
        set TotalActionsExecuted += 1
        set LastActionType = ActionType

        if (ActionType = BRIDGE_ACTION_EASE_DIFFICULTY):
            EaseDifficulty()
        else if (ActionType = BRIDGE_ACTION_BOOST_DIFFICULTY):
            BoostDifficulty()
        else if (ActionType = BRIDGE_ACTION_SPAWN_AID):
            SpawnFrustrationAid()
        else if (ActionType = BRIDGE_ACTION_SWITCH_BOT_STYLE):
            SwitchBotStyle()
        else if (ActionType = BRIDGE_ACTION_UNLOCK_DRILL):
            UnlockNextDrill()
        else if (ActionType = BRIDGE_ACTION_APPLY_MODIFIER):
            Logger.Print("BRIDGE: Modifier action — placeholder for future implementation.")
        else:
            Logger.Print("BRIDGE: Unknown action type {ActionType}.")

    # ══════════════════════════════════════════════════════════════════════════
    # ACTION: EASE DIFFICULTY
    # Temporarily lowers the bot's effective ELO by subtracting from the
    # player's ELO read by the analytics engine. Resets next session.
    # ══════════════════════════════════════════════════════════════════════════
    EaseDifficulty<private>() : void =
        CurrentELO := AnalyticsRef.GetPlayerELO()
        var AdjustedELO : int = CurrentELO - FrustrationELOReduction
        if (AdjustedELO < 100):
            set AdjustedELO = 100

        # Update the analytics engine's ELO directly
        # This causes the next round's difficulty_mapper to produce easier params
        set AnalyticsRef.PlayerELO = AdjustedELO
        set DifficultyOverrideActive = true

        Logger.Print("BRIDGE: Difficulty eased. ELO {CurrentELO} -> {AdjustedELO} (temp reduction: {FrustrationELOReduction}).")

    # ══════════════════════════════════════════════════════════════════════════
    # ACTION: BOOST DIFFICULTY
    # Temporarily increases difficulty for players on win streaks.
    # ══════════════════════════════════════════════════════════════════════════
    BoostDifficulty<private>() : void =
        CurrentELO := AnalyticsRef.GetPlayerELO()
        AdjustedELO := CurrentELO + BoostELOIncrease

        set AnalyticsRef.PlayerELO = AdjustedELO
        set DifficultyOverrideActive = true

        Logger.Print("BRIDGE: Difficulty boosted. ELO {CurrentELO} -> {AdjustedELO} (boost: +{BoostELOIncrease}).")

    # ══════════════════════════════════════════════════════════════════════════
    # ACTION: SPAWN FRUSTRATION AID
    # Grants the player healing items via an item_granter_device.
    # This gives them a tangible "the coach is helping" feeling.
    # ══════════════════════════════════════════════════════════════════════════
    SpawnFrustrationAid<private>() : void =
        AllPlayers := GetPlayspace().GetPlayers()
        for (Player : AllPlayers):
            FrustrationAid.GrantItem(Player)
        Logger.Print("BRIDGE: Frustration aid granted to all players.")

    # ══════════════════════════════════════════════════════════════════════════
    # ACTION: SWITCH BOT STYLE
    # Toggles the arena controller to use the alternate bot spawner,
    # which has a different NPC Character Definition (different combat
    # style). Used to break stagnation by forcing the player to adapt
    # to a new pattern.
    # ══════════════════════════════════════════════════════════════════════════
    SwitchBotStyle<private>() : void =
        # Toggle between primary and alternate bot spawners
        IsSpawned := ArenaCtrlRef.IsBotCurrentlySpawned()
        if (IsSpawned?):
            Logger.Print("BRIDGE: Cannot switch bot style mid-fight. Queued for next round.")
            ArenaCtrlRef.SetUseAltBot(true)
        else:
            ArenaCtrlRef.SetUseAltBot(true)
            Logger.Print("BRIDGE: Bot style switched to ALTERNATE for next spawn.")

    # ══════════════════════════════════════════════════════════════════════════
    # ACTION: UNLOCK DRILL
    # Marks the next locked training drill as unlocked in persistence.
    # The coach announces the unlock.
    # ══════════════════════════════════════════════════════════════════════════
    UnlockNextDrill<private>() : void =
        CurrentBracket := AnalyticsRef.EloCalc.GetBracket(AnalyticsRef.GetPlayerELO())
        PersistRef.UpdateHighestBracket(CurrentBracket)
        Logger.Print("BRIDGE: Drill unlock triggered for bracket {CurrentBracket}.")

    # ══════════════════════════════════════════════════════════════════════════
    # PUBLIC: Reset Overrides — Called between sessions
    # ══════════════════════════════════════════════════════════════════════════
    ResetOverrides<public>() : void =
        set DifficultyOverrideActive = false
        set HasEasedThisSession = false
        Logger.Print("BRIDGE: All overrides reset.")

    # ══════════════════════════════════════════════════════════════════════════
    # TELEMETRY
    # ══════════════════════════════════════════════════════════════════════════
    LogBridgeStats<public>() : void =
        Logger.Print("BRIDGE: ── Statistics ──")
        Logger.Print("BRIDGE:   Actions Executed: {TotalActionsExecuted}")
        Logger.Print("BRIDGE:   Last Action: {LastActionType}")
        Logger.Print("BRIDGE:   Eased This Session: {if (HasEasedThisSession?) then "true" else "false"}")
        Logger.Print("BRIDGE:   Override Active: {if (DifficultyOverrideActive?) then "true" else "false"}")

log_bridge_ch := class(log_channel):