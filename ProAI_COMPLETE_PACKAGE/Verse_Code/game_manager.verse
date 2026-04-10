# ============================================================================
# FILE: game_manager.verse — Master Round Lifecycle Orchestrator (Final)
# LOCATION: Content/ (root)
# PHASE: 1 → 9 (Integration Pass)
#
# ARCHITECTURE:
#   The single top-level orchestrator that drives the entire map. Every
#   module we built across 18 missions connects through this file:
#
#     Core:      event_bus (Dispatch API), arena_controller
#     Module A:  bot difficulty profile (read from analytics each round)
#     Module B:  build pool (reclaim via arena_controller)
#     Module C:  analytics_engine (BeginRoundTracking, EndRoundTracking,
#                GetUpdatedProfile), predictive_advisor, difficulty_mapper
#     Module D:  persistence_manager (auto-save via event bus listener,
#                load on join, save on session end)
#     Module E:  coach_controller (ProvidePostRoundFeedback),
#                coach_game_bridge (auto-actions)
#     Module F:  xp_reward_system (accolades via event bus listener),
#                shop_manager (inventory load), cosmetic_applicator
#     UI:        hud_binding (live stats), scorecard_renderer (post-round)
#
#   STATE MACHINE:
#     LOBBY → COUNTDOWN → FIGHT → POST_ROUND → RESET → (loop)
#
#   CONCURRENCY MODEL:
#     The FIGHT phase uses a clean three-way race:
#       race:
#         block: EventBus.ListenForBotEliminated()    → PLAYER_WIN
#         block: WaitForActivePlayerEliminated()       → BOT_WIN
#         block: RoundTimerWithHalftimeLog()           → DRAW
#     No polling. No busy-wait. Pure event-driven structured concurrency.
#
# WIRING (UEFN Editor):
#   EventBus       → event_bus device
#   ArenaCtrl      → arena_controller device
#   Analytics      → analytics_engine device
#   Persistence    → persistence_manager device
#   Coach          → coach_controller device
#   HUD            → hud_binding device
#   Scorecard      → scorecard_renderer device
# ============================================================================
using { /Fortnite.com/Devices }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Game }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/SpatialMath }

game_manager<public> := class(creative_device):

    Logger<private> : log = log{Channel := log_gm_ch}

    # ══════════════════════════════════════════════════════════════════════════
    # EDITABLE REFERENCES — Wired in UEFN editor Details panel
    # ══════════════════════════════════════════════════════════════════════════

    # ── Core Layer ───────────────────────────────────────────────────────────
    @editable
    EventBus<public> : event_bus = event_bus{}

    @editable
    ArenaCtrl<public> : arena_controller = arena_controller{}

    # ── Module C: Analytics ──────────────────────────────────────────────────
    @editable
    Analytics<public> : analytics_engine = analytics_engine{}

    # ── Module D: Persistence ────────────────────────────────────────────────
    @editable
    Persistence<public> : persistence_manager = persistence_manager{}

    # ── Module E: Coach ──────────────────────────────────────────────────────
    @editable
    Coach<public> : coach_controller = coach_controller{}

    # ── UI Layer ─────────────────────────────────────────────────────────────
    @editable
    HUD<public> : hud_binding = hud_binding{}

    @editable
    Scorecard<public> : scorecard_renderer = scorecard_renderer{}

    # ══════════════════════════════════════════════════════════════════════════
    # TUNABLE TIMING PARAMETERS — Exposed in Details panel
    # ══════════════════════════════════════════════════════════════════════════
    @editable
    LobbyWaitSeconds<public> : float = 5.0

    @editable
    CountdownSeconds<public> : float = 3.0

    @editable
    RoundDurationSeconds<public> : float = 60.0

    @editable
    PostRoundDisplaySeconds<public> : float = 5.0

    @editable
    ResetCooldownSeconds<public> : float = 1.5

    @editable
    AutoStartFirstRound<public> : logic = true

    @editable
    MaxRoundsPerSession<public> : int = 999

    # ══════════════════════════════════════════════════════════════════════════
    # INTERNAL STATE
    # ══════════════════════════════════════════════════════════════════════════
    var CurrentRound<private>         : int = 0
    var RoundOutcome<private>         : int = 0
    var PreFightELO<private>          : int = 1000
    var IsRunning<private>            : logic = true
    var ActivePlayerAgent<private>    : ?agent = false
    var ActivePlayerRef<private>      : ?player = false
    var SessionStartTime<private>     : float = 0.0

    # ══════════════════════════════════════════════════════════════════════════
    # ENTRY POINT
    # ══════════════════════════════════════════════════════════════════════════
    OnBegin<override>()<suspends> : void =
        set SessionStartTime = GetSimulationElapsedTime()
        Logger.Print("GAME_MGR: ══════════════════════════════════════════")
        Logger.Print("GAME_MGR:   Pro AI Training Map — ONLINE")
        Logger.Print("GAME_MGR: ══════════════════════════════════════════")
        Logger.Print("GAME_MGR: Config — Lobby:{LobbyWaitSeconds}s Countdown:{CountdownSeconds}s Round:{RoundDurationSeconds}s Post:{PostRoundDisplaySeconds}s Reset:{ResetCooldownSeconds}s")

        # Phase 0: Wait for at least one player to be present
        WaitForPlayerJoin()

        # Phase 0.5: Load persistent data for the player
        LoadPlayerSession()

        if (AutoStartFirstRound?):
            Logger.Print("GAME_MGR: Auto-start enabled. Beginning match loop.")

        # ── Master Game Loop ─────────────────────────────────────────────────
        # Runs indefinitely until the island shuts down or MaxRounds is hit.
        loop:
            if (not IsRunning?):
                Logger.Print("GAME_MGR: Loop paused. Waiting for resume.")
                Sleep(1.0)
            else if (CurrentRound >= MaxRoundsPerSession):
                Logger.Print("GAME_MGR: Max rounds ({MaxRoundsPerSession}) reached. Session complete.")
                EndSession()
                set IsRunning = false
                Sleep(1.0)
            else:
                set CurrentRound += 1
                Logger.Print("GAME_MGR: ════════════ ROUND {CurrentRound} ════════════")

                RunLobbyPhase()
                RunCountdownPhase()
                RunFightPhase()
                RunPostRoundPhase()
                RunResetPhase()

    # ══════════════════════════════════════════════════════════════════════════
    # PHASE 0: WAIT FOR PLAYER
    # Blocks until a valid, active player character is on the island.
    # ══════════════════════════════════════════════════════════════════════════
    WaitForPlayerJoin<private>()<suspends> : void =
        Logger.Print("GAME_MGR: Waiting for player to join...")
        loop:
            AllPlayers := GetPlayspace().GetPlayers()
            if (PlayerAgent := AllPlayers[0]):
                if (PC := PlayerAgent.GetFortCharacter[]):
                    if (PC.IsActive[]):
                        set ActivePlayerAgent = option{PlayerAgent}
                        # Cache the player reference for persistence calls
                        if (P := player[PlayerAgent]):
                            set ActivePlayerRef = option{P}
                        Logger.Print("GAME_MGR: Player detected and active.")
                        break
            Sleep(0.5)

    # ══════════════════════════════════════════════════════════════════════════
    # PHASE 0.5: LOAD PLAYER SESSION
    # Reads persistent data (ELO, inventory, progression) and primes
    # all modules with the returning player's state.
    # ══════════════════════════════════════════════════════════════════════════
    LoadPlayerSession<private>() : void =
        if (P := ActivePlayerRef?):
            # Load ELO from persistence → analytics engine
            LoadedELO := Persistence.LoadPlayerData(P)
            set Analytics.PlayerELO = LoadedELO
            set PreFightELO = LoadedELO
            Logger.Print("GAME_MGR: Player session loaded. ELO: {LoadedELO}")
        else:
            Logger.Print("GAME_MGR: No player ref for session load. Using defaults.")

    # ══════════════════════════════════════════════════════════════════════════
    # PHASE 1: LOBBY
    # Brief pause between rounds. The HUD shows stats, the coach can
    # speak, and the player has time to process the last round.
    # Races the lobby timer against a disconnect detector.
    # ══════════════════════════════════════════════════════════════════════════
    RunLobbyPhase<private>()<suspends> : void =
        EventBus.DispatchStateChange(STATE_LOBBY)
        Logger.Print("GAME_MGR: [LOBBY] Waiting {LobbyWaitSeconds}s...")

        # Hide the previous round's scorecard
        Scorecard.HideScorecard()

        race:
            block:
                Sleep(LobbyWaitSeconds)
            block:
                WaitForPlayerDisconnect()
                Logger.Print("GAME_MGR: [LOBBY] Player disconnected. Pausing loop.")
                set IsRunning = false

    # ══════════════════════════════════════════════════════════════════════════
    # PHASE 2: COUNTDOWN
    # Spawns the bot, then ticks down second by second.
    # Each tick dispatches CountdownTickEvent so the HUD can display
    # "3... 2... 1... FIGHT!"
    # ══════════════════════════════════════════════════════════════════════════
    RunCountdownPhase<private>()<suspends> : void =
        EventBus.DispatchStateChange(STATE_COUNTDOWN)
        Logger.Print("GAME_MGR: [COUNTDOWN] Spawning bot...")

        # Trigger bot spawn via arena controller
        ArenaCtrl.SpawnBot()

        # Snapshot the player's ELO before the fight starts
        # (used after the round to show the delta on the scorecard)
        set PreFightELO = Analytics.GetPlayerELO()

        # Tick countdown from CountdownSeconds down to 1
        var Remaining : int = 1
        if (Rem := Floor[CountdownSeconds]):
            set Remaining = Rem
        if (Remaining < 1):
            set Remaining = 1

        loop:
            if (Remaining <= 0):
                break
            EventBus.DispatchCountdownTick(Remaining)
            Logger.Print("GAME_MGR: [COUNTDOWN] {Remaining}...")
            Sleep(1.0)
            set Remaining -= 1

        Logger.Print("GAME_MGR: >>> FIGHT! <<<")

    # ══════════════════════════════════════════════════════════════════════════
    # PHASE 3: FIGHT
    # The core combat phase. Three concurrent exit conditions race:
    #   Path A: Bot eliminated      → PLAYER_WIN
    #   Path B: Player eliminated   → BOT_WIN
    #   Path C: Timer expires       → DRAW
    #
    # Uses event-driven awaits (NOT polling) for eliminations.
    # The analytics engine's background listeners are already running
    # from its own OnBegin — they track damage, builds, and edits
    # in real time throughout this phase.
    # ══════════════════════════════════════════════════════════════════════════
    RunFightPhase<private>()<suspends> : void =
        set RoundOutcome = OUTCOME_NONE

        # Tell analytics to start a fresh round of metric tracking
        Analytics.BeginRoundTracking()

        # Dispatch round start — wakes all listeners across all modules:
        #   analytics_engine: resets accumulators
        #   hud_binding: switches to live combat stats mode
        #   xp_reward_system: checks for rank-up
        #   coach_controller: (no action on start, waits for end)
        EventBus.DispatchRoundStart(CurrentRound)

        Logger.Print("GAME_MGR: [FIGHT] Round {CurrentRound} active. Duration: {RoundDurationSeconds}s. ELO: {PreFightELO}")

        # ── Three-Way Race ───────────────────────────────────────────────────
        # Whichever path completes first cancels the other two.
        race:
            block:
                # PATH A: Bot eliminated — Player wins
                EventBus.ListenForBotEliminated()
                set RoundOutcome = OUTCOME_PLAYER_WIN
                Logger.Print("GAME_MGR: [FIGHT] Bot eliminated -> PLAYER WIN")

            block:
                # PATH B: Player eliminated — Bot wins
                WaitForActivePlayerEliminated()
                set RoundOutcome = OUTCOME_BOT_WIN
                EventBus.DispatchPlayerEliminated()
                Logger.Print("GAME_MGR: [FIGHT] Player eliminated -> BOT WIN")

            block:
                # PATH C: Round timer expires — Draw
                RoundTimerWithHalftimeLog()
                set RoundOutcome = OUTCOME_DRAW
                Logger.Print("GAME_MGR: [FIGHT] Timer expired -> DRAW")

        Logger.Print("GAME_MGR: [FIGHT] Concluded. Outcome: {GetOutcomeName(RoundOutcome)}")

    # ══════════════════════════════════════════════════════════════════════════
    # PHASE 4: POST-ROUND
    # The results phase. Every downstream module reacts to RoundEndEvent:
    #   analytics_engine: finalizes metrics, updates ELO
    #   coach_controller: evaluates triggers, delivers feedback
    #   persistence_manager: auto-saves ELO to Slot 2
    #   xp_reward_system: awards accolades
    #   scorecard_renderer: displays the full stats overlay
    #   hud_binding: updates binding variables
    # ══════════════════════════════════════════════════════════════════════════
    RunPostRoundPhase<private>()<suspends> : void =
        # Tell analytics to finalize all metrics and recalculate ELO.
        # This MUST happen before DispatchRoundEnd because the event bus
        # snapshot is populated by analytics, and all listeners read it.
        Analytics.EndRoundTracking(RoundOutcome, CurrentRound)

        # Get the new ELO after analytics processed the round
        NewELO := Analytics.GetPlayerELO()
        Metrics := Analytics.CurrentMetrics

        # Dispatch round end — this wakes:
        #   persistence_manager.AutoSaveOnRoundEndLoop
        #   coach_controller.ListenForRoundEnd loop
        #   xp_reward_system.ListenForRoundEndLoop
        #   scorecard_renderer.ListenForRoundEnd loop
        EventBus.DispatchRoundEnd(RoundOutcome, CurrentRound)

        # Render the scorecard on the player's screen
        CoachMessage := Coach.EvaluatePostRound(
            RoundOutcome,
            NewELO,
            Metrics.DPS,
            Metrics.HeadshotPct,
            EventBus.ConsecutiveLosses,
            EventBus.GetSessionDurationMinutes()
        )
        Scorecard.RenderScorecard(RoundOutcome, PreFightELO, NewELO, Metrics, CoachMessage)

        # Push the coach message to the HUD overlay
        HUD.SetCoachMessage(CoachMessage)

        # Log the round summary
        Logger.Print("GAME_MGR: [POST] ── Round {CurrentRound} Summary ──")
        Logger.Print("GAME_MGR: [POST]   Outcome: {GetOutcomeName(RoundOutcome)}")
        Logger.Print("GAME_MGR: [POST]   ELO: {PreFightELO} -> {NewELO} ({ELODeltaString(PreFightELO, NewELO)})")
        Logger.Print("GAME_MGR: [POST]   DPS: {Metrics.DPS} | Accuracy: {Metrics.AccuracyPct}% | HS: {Metrics.HeadshotPct}%")
        Logger.Print("GAME_MGR: [POST]   Reaction: {Metrics.ReactionTimeMs}ms | Builds: {Metrics.BuildsPlaced} | Edits: {Metrics.EditsPerformed}")
        Logger.Print("GAME_MGR: [POST]   Session: W:{EventBus.TotalPlayerWins} L:{EventBus.TotalBotWins} D:{EventBus.TotalDraws}")
        Logger.Print("GAME_MGR: [POST]   Streaks: Wins:{EventBus.ConsecutiveWins} Losses:{EventBus.ConsecutiveLosses}")
        Logger.Print("GAME_MGR: [POST] Displaying for {PostRoundDisplaySeconds}s...")

        # Hold the scorecard on screen
        Sleep(PostRoundDisplaySeconds)

    # ══════════════════════════════════════════════════════════════════════════
    # PHASE 5: RESET
    # Cleans the arena and prepares for the next round:
    #   1. Despawn bot, reclaim all build props, teleport player to spawn
    #   2. Get the updated difficulty profile from analytics (new ELO)
    #   3. Refresh the player reference (handles respawn edge cases)
    #   4. Brief cooldown before looping back to LOBBY
    # ══════════════════════════════════════════════════════════════════════════
    RunResetPhase<private>()<suspends> : void =
        EventBus.DispatchStateChange(STATE_RESETTING)
        Logger.Print("GAME_MGR: [RESET] Cleaning arena...")

        # Step 1: Arena cleanup (despawn bot, reclaim props, teleport player)
        ArenaCtrl.ResetArena()

        # Step 2: Get the updated difficulty profile for next round's bot
        # The analytics engine recalculated ELO in PostRound; now the
        # difficulty_mapper translates that ELO into concrete bot parameters.
        UpdatedProfile := Analytics.GetUpdatedProfile()
        Logger.Print("GAME_MGR: [RESET] Next round profile — Reaction:{UpdatedProfile.ReactionTimeMs}ms Aggro:{UpdatedProfile.AggressionLevel} BuildRate:{UpdatedProfile.BuildPlayRate}")

        # Step 3: Brief cooldown
        Sleep(ResetCooldownSeconds)

        # Step 4: Refresh player reference for next round
        RefreshPlayerReference()

        Logger.Print("GAME_MGR: [RESET] Complete. Looping to LOBBY.")

    # ══════════════════════════════════════════════════════════════════════════
    # FIGHT PHASE HELPERS
    # ══════════════════════════════════════════════════════════════════════════

    # Subscribes to the player's fort_character EliminatedEvent.
    # Falls back to a presence-check poll if the reference is stale.
    WaitForActivePlayerEliminated<private>()<suspends> : void =
        if (PlayerAgent := ActivePlayerAgent?):
            if (PC := PlayerAgent.GetFortCharacter[]):
                PC.EliminatedEvent().Await()
                return

        # Fallback: poll for player absence
        Logger.Print("GAME_MGR: Player ref unavailable — falling back to presence poll.")
        loop:
            var PlayerActive : logic = false
            AllPlayers := GetPlayspace().GetPlayers()
            for (P : AllPlayers):
                if (PC := P.GetFortCharacter[]):
                    if (PC.IsActive[]):
                        set PlayerActive = true
            if (not PlayerActive?):
                break
            Sleep(0.15)

    # Round timer with a halftime log for debugging.
    RoundTimerWithHalftimeLog<private>()<suspends> : void =
        HalfTime := RoundDurationSeconds / 2.0
        Sleep(HalfTime)
        Logger.Print("GAME_MGR: [FIGHT] ── Halftime ({HalfTime}s remaining) ──")
        Logger.Print("GAME_MGR: [FIGHT]   Live DPS: {Analytics.GetCurrentDPS()} | Live Acc: {Analytics.GetCurrentAccuracy()}%")
        Sleep(HalfTime)

    # ══════════════════════════════════════════════════════════════════════════
    # PLAYER MANAGEMENT
    # ══════════════════════════════════════════════════════════════════════════

    # Refreshes the cached player agent reference between rounds.
    # Handles respawn edge cases where the character object changes.
    RefreshPlayerReference<private>() : void =
        AllPlayers := GetPlayspace().GetPlayers()
        if (PlayerAgent := AllPlayers[0]):
            set ActivePlayerAgent = option{PlayerAgent}
            if (P := player[PlayerAgent]):
                set ActivePlayerRef = option{P}
            Logger.Print("GAME_MGR: Player reference refreshed.")
        else:
            set ActivePlayerAgent = false
            set ActivePlayerRef = false
            Logger.Print("GAME_MGR: WARNING — No player found during refresh. Pausing.")
            set IsRunning = false

    # Suspends until no active player characters remain on the island.
    WaitForPlayerDisconnect<private>()<suspends> : void =
        loop:
            AllPlayers := GetPlayspace().GetPlayers()
            if (AllPlayers.Length = 0):
                break
            var AnyActive : logic = false
            for (P : AllPlayers):
                if (PC := P.GetFortCharacter[]):
                    if (PC.IsActive[]):
                        set AnyActive = true
            if (not AnyActive?):
                break
            Sleep(1.0)

    # ══════════════════════════════════════════════════════════════════════════
    # SESSION END — Save all data and clean up
    # Called when max rounds are reached or the player disconnects.
    # ══════════════════════════════════════════════════════════════════════════
    EndSession<private>() : void =
        Logger.Print("GAME_MGR: ══════════════════════════════════════════")
        Logger.Print("GAME_MGR:   SESSION ENDING")
        Logger.Print("GAME_MGR: ══════════════════════════════════════════")

        SessionMinutes := EventBus.GetSessionDurationMinutes()
        FinalELO := Analytics.GetPlayerELO()
        PeakELO := Analytics.GetPeakELO()

        # Compile session summary
        Summary := Analytics.CompileSessionSummary(SessionMinutes)

        # Save all persistent data
        if (P := ActivePlayerRef?):
            Persistence.SaveRatingData(
                P,
                FinalELO,
                PeakELO,
                EventBus.TotalPlayerWins,
                EventBus.TotalBotWins,
                EventBus.TotalDraws,
                Floor[SessionMinutes] or 0
            )

            Persistence.SaveAnalyticsData(
                P,
                Summary.AvgDPS,
                Summary.AvgHeadshotPct,
                Summary.AvgAccuracyPct,
                Summary.AvgReactionMs,
                CurrentRound,
                Summary.TotalBuildsPlaced,
                Summary.TotalEditsPerformed,
                0.0
            )

            Persistence.SaveAllPlayerData()

        Logger.Print("GAME_MGR: Session complete.")
        Logger.Print("GAME_MGR:   Rounds Played: {CurrentRound}")
        Logger.Print("GAME_MGR:   Final ELO: {FinalELO} (Peak: {PeakELO})")
        Logger.Print("GAME_MGR:   Record: W:{EventBus.TotalPlayerWins} L:{EventBus.TotalBotWins} D:{EventBus.TotalDraws}")
        Logger.Print("GAME_MGR:   Duration: {SessionMinutes} minutes")

    # ══════════════════════════════════════════════════════════════════════════
    # PUBLIC API — External control from other modules
    # ══════════════════════════════════════════════════════════════════════════

    # Pause/resume the match loop (used by shop_manager, coach_game_bridge).
    SetRunning<public>(ShouldRun : logic) : void =
        set IsRunning = ShouldRun
        if (ShouldRun?):
            Logger.Print("GAME_MGR: Match loop RESUMED.")
        else:
            Logger.Print("GAME_MGR: Match loop PAUSED.")

    GetCurrentRound<public>() : int =
        CurrentRound

    GetSessionDurationMinutes<public>() : float =
        (GetSimulationElapsedTime() - SessionStartTime) / 60.0

    IsMatchRunning<public>() : logic =
        IsRunning

    # ══════════════════════════════════════════════════════════════════════════
    # UTILITY
    # ══════════════════════════════════════════════════════════════════════════
    GetOutcomeName<private>(Outcome : int) : string =
        if (Outcome = OUTCOME_PLAYER_WIN):
            return "PLAYER_WIN"
        else if (Outcome = OUTCOME_BOT_WIN):
            return "BOT_WIN"
        else if (Outcome = OUTCOME_DRAW):
            return "DRAW"
        "NONE"

    ELODeltaString<private>(Before : int, After : int) : string =
        Delta := After - Before
        if (Delta >= 0):
            return "+{Delta}"
        "{Delta}"

log_gm_ch := class(log_channel):