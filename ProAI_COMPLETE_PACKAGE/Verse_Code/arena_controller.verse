# ============================================================================
# FILE: arena_controller.verse — Physical Arena Space Manager
# LOCATION: Content/ (root)
# PHASE: 1 (reset/spawn), Phase 3 (pool integration), Phase 6 (cosmetics)
#
# ARCHITECTURE:
#   Owns the physical arena lifecycle: bot spawning, bot despawning,
#   player teleportation, prop pool reclamation, and zone boundaries.
#   Called directly by game_manager for SpawnBot()/ResetArena().
#   Runs a background listener loop to also respond to event-bus
#   signals from other modules (e.g. cosmetic_applicator requesting
#   a mid-session arena swap).
#
# WIRING (UEFN Editor Details Panel):
#   EventBus         → event_bus device
#   BotSpawner        → NPC Spawner device (Spawn on Game Start: OFF)
#   PlayerSpawnPad    → Player Spawner device (center-arena)
#   BuildPoolRef      → build_pool_manager device
#   BotSpawnMarker    → (optional) a prop or device at the bot's spawn point
#   ArenaBoundaryZone → (optional) mutator_zone_device for kill boundary
# ============================================================================
using { /Fortnite.com/Devices }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Game }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/SpatialMath }

arena_controller<public> := class(creative_device):

    Logger<private> : log = log{Channel := log_arena_ch}

    # ── Editable References (wired in UEFN editor) ──────────────────────────
    @editable
    EventBus<public> : event_bus = event_bus{}

    @editable
    BotSpawner<public> : npc_spawner_device = npc_spawner_device{}

    @editable
    PlayerSpawnPad<public> : player_spawner_device = player_spawner_device{}

    @editable
    BuildPoolRef<public> : build_pool_manager = build_pool_manager{}

    # Optional: a second NPC spawner for variant bots (e.g. aggressive vs passive)
    @editable
    AltBotSpawner<public> : npc_spawner_device = npc_spawner_device{}

    @editable
    var UseAltBotSpawner<public> : logic = false

    # Optional: mutator zone covering the arena boundary for fall-off kills
    @editable
    ArenaBoundaryZone<public> : mutator_zone_device = mutator_zone_device{}

    @editable
    EnableBoundaryZone<public> : logic = false

    # Tunable: time to wait after enabling spawner before bot is "ready"
    @editable
    BotSpawnSettleTime<public> : float = 0.5

    # Tunable: time to wait after despawn before arena is considered clean
    @editable
    DespawnSettleTime<public> : float = 0.3

    # ── Cached Transforms ────────────────────────────────────────────────────
    var PlayerSpawnPosition<private>  : vector3  = vector3{X := 0.0, Y := 0.0, Z := 0.0}
    var PlayerSpawnRotation<private>  : rotation = IdentityRotation()
    var BotSpawnPosition<private>     : vector3  = vector3{X := 0.0, Y := 0.0, Z := 0.0}
    var BotSpawnRotation<private>     : rotation = IdentityRotation()

    # ── Internal State ───────────────────────────────────────────────────────
    var IsBotSpawned<private>         : logic = false
    var TotalBotsSpawned<private>     : int = 0
    var TotalResetsPerformed<private> : int = 0
    var IsResetting<private>          : logic = false

    # ══════════════════════════════════════════════════════════════════════════
    # INITIALIZATION
    # ══════════════════════════════════════════════════════════════════════════
    OnBegin<override>()<suspends> : void =
        CacheSpawnTransforms()
        EnsureSpawnersDisabledAtStart()

        if (EnableBoundaryZone?):
            ArenaBoundaryZone.Enable()
            Logger.Print("ARENA_CTRL: Boundary zone enabled.")

        Logger.Print("ARENA_CTRL: Initialized. Player spawn at ({PlayerSpawnPosition.X}, {PlayerSpawnPosition.Y}, {PlayerSpawnPosition.Z})")
        Logger.Print("ARENA_CTRL: Bot spawn at ({BotSpawnPosition.X}, {BotSpawnPosition.Y}, {BotSpawnPosition.Z})")

        # Background: listen for round-end events to auto-flag bot as despawned
        # This catches cases where the bot is eliminated mid-fight and the
        # npc_spawner fires its internal EliminatedEvent before we call ResetArena.
        branch:
            BotEliminationWatchdog()

        # Background: subscribe to the NPC spawner's SpawnedEvent to confirm
        # bot spawns and update the event bus BotIsAlive flag
        branch:
            BotSpawnConfirmationLoop()

    # ══════════════════════════════════════════════════════════════════════════
    # PUBLIC API: SpawnBot()
    # Called by game_manager during COUNTDOWN phase.
    # Enables the NPC spawner, waits for settle time, confirms spawn.
    # ══════════════════════════════════════════════════════════════════════════
    SpawnBot<public>()<suspends> : void =
        Logger.Print("ARENA_CTRL: SpawnBot() called.")

        # Safety: if a bot is somehow still alive from a bad reset, despawn first
        if (IsBotSpawned?):
            Logger.Print("ARENA_CTRL: WARNING — Stale bot detected. Force-despawning.")
            DespawnBot()

        # Select which spawner to use
        ActiveSpawner := GetActiveSpawner()

        # Enable the spawner — this triggers the NPC Character Definition
        # to instantiate the bot with its bot_behavior_base script
        ActiveSpawner.Enable()
        set IsBotSpawned = true
        set TotalBotsSpawned += 1

        # Allow the engine time to fully instantiate the NPC
        Sleep(BotSpawnSettleTime)

        # Update event bus so all modules know the bot is live
        EventBus.DispatchStateChange(STATE_COUNTDOWN)
        Logger.Print("ARENA_CTRL: Bot #{TotalBotsSpawned} spawned and active.")

    # ══════════════════════════════════════════════════════════════════════════
    # PUBLIC API: ResetArena()
    # Called by game_manager during RESET phase.
    # Full sequence: despawn bot → reclaim props → teleport player → signal done.
    # ══════════════════════════════════════════════════════════════════════════
    ResetArena<public>()<suspends> : void =
        if (IsResetting?):
            Logger.Print("ARENA_CTRL: Reset already in progress — skipping duplicate call.")
            return
        set IsResetting = true
        set TotalResetsPerformed += 1
        Logger.Print("ARENA_CTRL: ── Reset #{TotalResetsPerformed} Begin ──")

        # Step 1: Despawn the bot (disable spawner, clear flag)
        DespawnBot()
        Logger.Print("ARENA_CTRL: [1/4] Bot despawned.")

        # Step 2: Reclaim all deployed build props back to underground staging
        ReclaimAllBuildProps()
        Logger.Print("ARENA_CTRL: [2/4] Build props reclaimed.")

        # Step 3: Teleport all players back to spawn and restore health
        TeleportAllPlayersToSpawn()
        Logger.Print("ARENA_CTRL: [3/4] Players teleported to spawn.")

        # Step 4: Brief settle time for engine to finalize all teleports
        Sleep(DespawnSettleTime)

        # Signal completion — game_manager is waiting for this
        set IsResetting = false
        EventBus.DispatchArenaResetComplete()
        Logger.Print("ARENA_CTRL: ── Reset #{TotalResetsPerformed} Complete ──")

    # ══════════════════════════════════════════════════════════════════════════
    # PUBLIC API: ForceReset()
    # Emergency reset callable by any module (e.g. coach detecting a stuck state).
    # Skips the IsResetting guard by clearing it first.
    # ══════════════════════════════════════════════════════════════════════════
    ForceReset<public>()<suspends> : void =
        Logger.Print("ARENA_CTRL: FORCE RESET requested.")
        set IsResetting = false
        ResetArena()

    # ══════════════════════════════════════════════════════════════════════════
    # PRIVATE: Bot Lifecycle
    # ══════════════════════════════════════════════════════════════════════════
    DespawnBot<private>() : void =
        # Disable both spawners to ensure no stale NPCs linger
        BotSpawner.Disable()
        AltBotSpawner.Disable()
        set IsBotSpawned = false
        Logger.Print("ARENA_CTRL: Spawner(s) disabled. Bot despawned.")

    GetActiveSpawner<private>() : npc_spawner_device =
        if (UseAltBotSpawner?):
            return AltBotSpawner
        BotSpawner

    # ══════════════════════════════════════════════════════════════════════════
    # PRIVATE: Build Prop Reclamation
    # Delegates to build_pool_manager.ReclaimAll() which teleports all
    # active pool entries back to the underground staging area (Z=-5000).
    # ══════════════════════════════════════════════════════════════════════════
    ReclaimAllBuildProps<private>()<suspends> : void =
        Logger.Print("ARENA_CTRL: Requesting prop pool reclaim...")
        BuildPoolRef.ReclaimAll()
        Logger.Print("ARENA_CTRL: Prop pool reclaim complete.")

    # ══════════════════════════════════════════════════════════════════════════
    # PRIVATE: Player Teleportation & Health Restore
    # Moves every player back to the spawn pad transform.
    # Uses the cached position/rotation captured at OnBegin.
    # ══════════════════════════════════════════════════════════════════════════
    TeleportAllPlayersToSpawn<private>() : void =
        AllPlayers := GetPlayspace().GetPlayers()
        var PlayersProcessed : int = 0
        for (Player : AllPlayers):
            if (FC := Player.GetFortCharacter[]):
                # Teleport to spawn pad location
                if (FC.TeleportTo[PlayerSpawnPosition, PlayerSpawnRotation]):
                    set PlayersProcessed += 1
                    Logger.Print("ARENA_CTRL: Player teleported to spawn.")
                else:
                    Logger.Print("ARENA_CTRL: WARNING — TeleportTo failed for a player.")
        Logger.Print("ARENA_CTRL: {PlayersProcessed} player(s) repositioned.")

    # ══════════════════════════════════════════════════════════════════════════
    # PRIVATE: Cache Spawn Transforms
    # Reads the transforms of the editor-placed spawner devices at init.
    # These are immutable for the session lifetime.
    # ══════════════════════════════════════════════════════════════════════════
    CacheSpawnTransforms<private>() : void =
        # Player spawn from the player_spawner_device
        PlayerXform := PlayerSpawnPad.GetTransform()
        set PlayerSpawnPosition = PlayerXform.Translation
        set PlayerSpawnRotation = PlayerXform.Rotation

        # Bot spawn from the npc_spawner_device
        BotXform := BotSpawner.GetTransform()
        set BotSpawnPosition = BotXform.Translation
        set BotSpawnRotation = BotXform.Rotation

    EnsureSpawnersDisabledAtStart<private>() : void =
        BotSpawner.Disable()
        AltBotSpawner.Disable()
        Logger.Print("ARENA_CTRL: All spawners disabled at startup.")

    # ══════════════════════════════════════════════════════════════════════════
    # BACKGROUND: Bot Elimination Watchdog
    # Runs in a branch from OnBegin. Continuously listens for
    # BotEliminatedEvent on the event bus. When the bot dies mid-fight,
    # this updates IsBotSpawned immediately so ResetArena() knows
    # not to attempt a double-despawn.
    # ══════════════════════════════════════════════════════════════════════════
    BotEliminationWatchdog<private>()<suspends> : void =
        Logger.Print("ARENA_CTRL: Bot elimination watchdog started.")
        loop:
            EventBus.ListenForBotEliminated()
            set IsBotSpawned = false
            Logger.Print("ARENA_CTRL: Watchdog — bot elimination detected. Flag cleared.")

    # ══════════════════════════════════════════════════════════════════════════
    # BACKGROUND: Bot Spawn Confirmation Loop
    # Listens to the NPC spawner device's SpawnedEvent to confirm that
    # the engine actually instantiated the NPC. On confirmation, sets
    # the event bus BotIsAlive flag (redundant safety alongside
    # DispatchRoundStart setting it, but catches edge cases where
    # the spawner fires slightly after our Sleep settles).
    # ══════════════════════════════════════════════════════════════════════════
    BotSpawnConfirmationLoop<private>()<suspends> : void =
        Logger.Print("ARENA_CTRL: Spawn confirmation listener started.")
        loop:
            GetActiveSpawner().SpawnedEvent.Await()
            
            set EventBus.BotIsAlive = true
            set IsBotSpawned = true
            Logger.Print("ARENA_CTRL: SpawnedEvent confirmed — bot is live.")

    # ══════════════════════════════════════════════════════════════════════════
    # PUBLIC QUERIES — Other modules can read arena state
    # ══════════════════════════════════════════════════════════════════════════
    IsBotCurrentlySpawned<public>() : logic =
        IsBotSpawned

    IsCurrentlyResetting<public>() : logic =
        IsResetting

    GetPlayerSpawnPosition<public>() : vector3 =
        PlayerSpawnPosition

    GetPlayerSpawnRotation<public>() : rotation =
        PlayerSpawnRotation

    GetBotSpawnPosition<public>() : vector3 =
        BotSpawnPosition

    GetTotalResetsPerformed<public>() : int =
        TotalResetsPerformed

    GetTotalBotsSpawned<public>() : int =
        TotalBotsSpawned

    # ══════════════════════════════════════════════════════════════════════════
    # PUBLIC: Switch Bot Variant
    # Called by coach_game_bridge or difficulty_mapper to swap between
    # primary and alternate bot spawners mid-session.
    # ══════════════════════════════════════════════════════════════════════════
    SetUseAltBot<public>(UseAlt : logic) : void =
        set UseAltBotSpawner = UseAlt
        if (UseAlt?):
            Logger.Print("ARENA_CTRL: Next spawn will use ALTERNATE bot spawner.")
        else:
            Logger.Print("ARENA_CTRL: Next spawn will use PRIMARY bot spawner.")

log_arena_ch := class(log_channel):