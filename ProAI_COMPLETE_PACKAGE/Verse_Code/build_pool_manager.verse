# ============================================================================
# FILE: build_pool_manager.verse — Object Pool Lifecycle Manager
# LOCATION: Content/ (root)
# PHASE: 3
#
# ARCHITECTURE:
#   Implements the "Recycled Memory Cluster Pattern" from the spec (§4.6).
#   All build-piece props are PRE-PLACED in the UEFN editor at Z=-5000
#   (underground staging) and wired to the @editable arrays here.
#   We never call SpawnProp() at runtime — we only TeleportTo() existing
#   props between the staging area and the arena surface. This completely
#   sidesteps the ~100 SpawnProp limit (HC-02).
#
# POOL SIZING (from spec §4.6):
#   Per bot instance: 12 walls, 6 floors, 4 ramps, 4 cones = 26 props
#   With 2 concurrent bots: 52 total, safely under ~100 limit.
#
# LIFECYCLE:
#   INIT    → OnBegin: wrap editor props into pool_entry structs,
#              confirm all are at staging position, mark available.
#   DEPLOY  → ClaimAndDeploy: find free entry, TeleportTo target
#              position, mark active, stamp deploy order.
#   RECLAIM → ReclaimProp: TeleportTo staging, mark available.
#   FIFO    → If pool is exhausted, reclaim the OLDEST active entry
#              (lowest DeployOrder) to make room.
#   RESET   → ReclaimAll: teleport every active entry back to staging.
#
# WIRING (UEFN Editor):
#   EventBus   → event_bus device
#   WallProps  → 12 wall creative_prop instances (pre-placed at Z=-5000)
#   FloorProps → 6 floor creative_prop instances
#   RampProps  → 4 ramp creative_prop instances
#   ConeProps  → 4 cone creative_prop instances
# ============================================================================
using { /Fortnite.com/Devices }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/SpatialMath }

# ── Piece Type Constants ─────────────────────────────────────────────────────
PIECE_WALL<public>  : int = 0
PIECE_FLOOR<public> : int = 1
PIECE_RAMP<public>  : int = 2
PIECE_CONE<public>  : int = 3

# ── Pool Entry — Tracks one physical prop in the pool ────────────────────────
pool_entry<public> := class:
    # Whether this prop is currently deployed in the arena
    var IsActive<public>    : logic = false
    # Monotonic counter stamped at deploy time — used for FIFO ordering
    var DeployOrder<public> : int = 0
    # The piece type this entry belongs to (for cross-pool searches)
    var PieceType<public>   : int = 0
    # The physical prop reference (wired from @editable in the editor)
    Prop<public>            : creative_prop
    # World position where this prop was last deployed (for analytics)
    var LastDeployPosition<public> : vector3 = vector3{X := 0.0, Y := 0.0, Z := 0.0}
    # Simulation time when this prop was last deployed
    var DeployTimestamp<public> : float = 0.0

# ══════════════════════════════════════════════════════════════════════════════
# BUILD POOL MANAGER DEVICE
# ══════════════════════════════════════════════════════════════════════════════
build_pool_manager<public> := class(creative_device):

    Logger<private> : log = log{Channel := log_pool_ch}

    # ── Editable References ──────────────────────────────────────────────────
    # Place these props in the UEFN editor at Z=-5000 (underground staging).
    # Then wire each array in the Details panel of this device.
    @editable
    EventBus<public> : event_bus = event_bus{}

    @editable
    WallProps<public> : []creative_prop = array{}

    @editable
    FloorProps<public> : []creative_prop = array{}

    @editable
    RampProps<public> : []creative_prop = array{}

    @editable
    ConeProps<public> : []creative_prop = array{}

    # ── Staging Configuration ────────────────────────────────────────────────
    # Underground position where all inactive props are stored.
    # Must be far enough below the arena that players never see them.
    @editable
    StagingPositionZ<public> : float = -5000.0

    # ── Internal Pool Arrays ─────────────────────────────────────────────────
    var WallPool<private>  : []pool_entry = array{}
    var FloorPool<private> : []pool_entry = array{}
    var RampPool<private>  : []pool_entry = array{}
    var ConePool<private>  : []pool_entry = array{}

    # Flat combined array of ALL entries for cross-pool operations
    var AllEntries<private> : []pool_entry = array{}

    # ── Counters ─────────────────────────────────────────────────────────────
    # Monotonic deploy counter — never resets during a session.
    # Each deploy stamps the entry with this value, then increments.
    # FIFO reclaim finds the entry with the lowest DeployOrder.
    var GlobalDeployCounter<private> : int = 0

    # ── Telemetry ────────────────────────────────────────────────────────────
    var TotalClaims<private>         : int = 0
    var TotalReclaims<private>       : int = 0
    var TotalFIFOReclaims<private>   : int = 0
    var TotalReclaimAlls<private>    : int = 0
    var TotalDeployFailures<private> : int = 0
    var PeakActiveCount<private>     : int = 0
    var IsPoolReady<public>          : logic = false

    # ══════════════════════════════════════════════════════════════════════════
    # INITIALIZATION
    # Wraps all editor-placed props into pool_entry structs, ensures
    # they're all at the staging position, and marks them available.
    # ══════════════════════════════════════════════════════════════════════════
    OnBegin<override>()<suspends> : void =
        Logger.Print("POOL_MGR: ── Initializing Object Pools ──")
        Logger.Print("POOL_MGR: Editor props — W:{WallProps.Length} F:{FloorProps.Length} R:{RampProps.Length} C:{ConeProps.Length}")

        StagingPos := GetStagingPosition()

        # Build typed pool arrays from editor references
        set WallPool = for (P : WallProps):
            pool_entry{IsActive := false, DeployOrder := 0, PieceType := PIECE_WALL, Prop := P}
        set FloorPool = for (P : FloorProps):
            pool_entry{IsActive := false, DeployOrder := 0, PieceType := PIECE_FLOOR, Prop := P}
        set RampPool = for (P : RampProps):
            pool_entry{IsActive := false, DeployOrder := 0, PieceType := PIECE_RAMP, Prop := P}
        set ConePool = for (P : ConeProps):
            pool_entry{IsActive := false, DeployOrder := 0, PieceType := PIECE_CONE, Prop := P}

        # Build flat combined array for cross-pool operations
        set AllEntries = array{}
        for (E : WallPool):
            set AllEntries += array{E}
        for (E : FloorPool):
            set AllEntries += array{E}
        for (E : RampPool):
            set AllEntries += array{E}
        for (E : ConePool):
            set AllEntries += array{E}

        TotalProps := AllEntries.Length
        Logger.Print("POOL_MGR: Total pool entries: {TotalProps}")

        # Ensure all props are at the staging position
        # (They should already be placed there in the editor, but this
        # guarantees it in case someone moved one accidentally.)
        var StagedCount : int = 0
        for (Entry : AllEntries):
            if (Entry.Prop.TeleportTo[StagingPos, IdentityRotation()]):
                set StagedCount += 1

        set IsPoolReady = true
        Logger.Print("POOL_MGR: {StagedCount}/{TotalProps} props confirmed at staging.")
        Logger.Print("POOL_MGR: ── Pools Ready ──")
        Logger.Print("POOL_MGR:   Walls: {WallPool.Length}")
        Logger.Print("POOL_MGR:   Floors: {FloorPool.Length}")
        Logger.Print("POOL_MGR:   Ramps: {RampPool.Length}")
        Logger.Print("POOL_MGR:   Cones: {ConePool.Length}")

    # ══════════════════════════════════════════════════════════════════════════
    # CLAIM AND DEPLOY — Primary deployment method
    # Finds an available prop of the requested type, teleports it to
    # the target position, and marks it active.
    #
    # If no props are available, FIFO reclaims the oldest active entry
    # of that type, then retries the claim.
    #
    # Returns the prop on success, false on failure (should never happen
    # unless all props are in a failed TeleportTo state).
    # ══════════════════════════════════════════════════════════════════════════
    ClaimAndDeploy<public>(
        PieceType : int,
        Position : vector3,
        Rotation : rotation
    )<suspends> : ?creative_prop =
        set TotalClaims += 1
        Pool := GetPoolByType(PieceType)

        # Attempt 1: find an inactive entry
        ClaimResult := TryClaimFromPool(Pool, Position, Rotation, PieceType)
        if (Claimed := ClaimResult?):
            UpdatePeakActive()
            DispatchBuildPlacedEvent(PieceType, Position)
            return option{Claimed}

        # Pool exhausted — FIFO reclaim the oldest active entry
        Logger.Print("POOL_MGR: Pool exhausted for type {GetTypeName(PieceType)}. Triggering FIFO reclaim.")
        set TotalFIFOReclaims += 1
        ReclaimOldestFromPool(Pool)

        # Small yield to let TeleportTo settle before re-claiming
        Sleep(0.0)

        # Attempt 2: retry after reclaim
        RetryResult := TryClaimFromPool(Pool, Position, Rotation, PieceType)
        if (Retried := RetryResult?):
            UpdatePeakActive()
            DispatchBuildPlacedEvent(PieceType, Position)
            Logger.Print("POOL_MGR: FIFO reclaim successful. Deployed {GetTypeName(PieceType)} after overflow.")
            return option{Retried}

        # Both attempts failed — this should be extremely rare
        set TotalDeployFailures += 1
        Logger.Print("POOL_MGR: CRITICAL — Deploy failed for type {GetTypeName(PieceType)} after FIFO reclaim!")
        false

    # ══════════════════════════════════════════════════════════════════════════
    # CLAIM BY STRING TYPE — Convenience wrapper accepting string names
    # Used by build_sequence_choreographer which works with string labels.
    # ══════════════════════════════════════════════════════════════════════════
    ClaimByName<public>(
        TypeName : string,
        Position : vector3,
        Rotation : rotation
    )<suspends> : ?creative_prop =
        PieceType := TypeNameToInt(TypeName)
        ClaimAndDeploy(PieceType, Position, Rotation)

    # ══════════════════════════════════════════════════════════════════════════
    # RECLAIM SINGLE PROP — Return one prop to staging
    # Searches all pools to find the matching entry, marks it inactive,
    # and teleports it underground.
    # ══════════════════════════════════════════════════════════════════════════
    # ReclaimProp<public>(Prop : creative_prop)<suspends> : void =
    #     set TotalReclaims += 1
    #     StagingPos := GetStagingPosition()
    # 
    #     for (Entry : AllEntries):
    #         if (Entry.Prop = Prop):
    #             if (Entry.IsActive?):
    #                 set Entry.IsActive = false
    #                 set Entry.DeployOrder = 0
    #                 if (Entry.Prop.TeleportTo[StagingPos, IdentityRotation()]):
    #                     Logger.Print("POOL_MGR: Reclaimed {GetTypeName(Entry.PieceType)} prop.")
    #                 else:
    #                     Logger.Print("POOL_MGR: WARNING — TeleportTo staging failed during reclaim.")
    #             return
    #     Logger.Print("POOL_MGR: WARNING — ReclaimProp called for unknown prop reference.")

    # ══════════════════════════════════════════════════════════════════════════
    # RECLAIM ALL — Arena reset: return every active prop to staging
    # Called by arena_controller between rounds.
    # Uses Sleep(0.0) between teleports to yield to the engine and
    # prevent frame spikes from teleporting 26+ props in one tick.
    # ══════════════════════════════════════════════════════════════════════════
    ReclaimAll<public>()<suspends> : void =
        set TotalReclaimAlls += 1
        StagingPos := GetStagingPosition()
        var ReclaimedCount : int = 0

        Logger.Print("POOL_MGR: ── ReclaimAll #{TotalReclaimAlls} ──")

        for (Entry : AllEntries):
            if (Entry.IsActive?):
                set Entry.IsActive = false
                set Entry.DeployOrder = 0
                if (Entry.Prop.TeleportTo[StagingPos, IdentityRotation()]):
                    set ReclaimedCount += 1
                # Yield every 4 props to spread teleports across frames
                if (Mod[ReclaimedCount, 4] = 0):
                    Sleep(0.0)

        set TotalReclaims += ReclaimedCount
        Logger.Print("POOL_MGR: ReclaimAll complete. {ReclaimedCount} props returned to staging.")

    # ══════════════════════════════════════════════════════════════════════════
    # RECLAIM BY TYPE — Return all active props of a specific type
    # Used when the bot "destroys" all its walls but keeps floors.
    # ══════════════════════════════════════════════════════════════════════════
    ReclaimByType<public>(PieceType : int)<suspends> : void =
        Pool := GetPoolByType(PieceType)
        StagingPos := GetStagingPosition()
        var ReclaimedCount : int = 0

        for (Entry : Pool):
            if (Entry.IsActive?):
                set Entry.IsActive = false
                set Entry.DeployOrder = 0
                if (Entry.Prop.TeleportTo[StagingPos, IdentityRotation()]):
                    set ReclaimedCount += 1
                    set TotalReclaims += 1

        Logger.Print("POOL_MGR: Reclaimed {ReclaimedCount} {GetTypeName(PieceType)} props.")

    # ══════════════════════════════════════════════════════════════════════════
    # RECLAIM OLDEST — Public FIFO for external callers
    # Reclaims the single oldest active prop ACROSS ALL POOLS.
    # Used by build_sequence_choreographer when global pool pressure
    # is high but the caller doesn't know which type to sacrifice.
    # ══════════════════════════════════════════════════════════════════════════
    ReclaimOldestGlobal<public>()<suspends> : void =
        var OldestOrder : int = 999999
        var OldestEntry : ?pool_entry = false

        for (Entry : AllEntries):
            if (Entry.IsActive?):
                if (Entry.DeployOrder < OldestOrder):
                    set OldestOrder = Entry.DeployOrder
                    set OldestEntry = option{Entry}

        if (Oldest := OldestEntry?):
            set Oldest.IsActive = false
            set Oldest.DeployOrder = 0
            StagingPos := GetStagingPosition()
            if (Oldest.Prop.TeleportTo[StagingPos, IdentityRotation()]):
                set TotalFIFOReclaims += 1
                set TotalReclaims += 1
                Logger.Print("POOL_MGR: Global FIFO reclaimed oldest (order {OldestOrder}, type {GetTypeName(Oldest.PieceType)}).")
        else:
            Logger.Print("POOL_MGR: Global FIFO — no active props to reclaim.")

    # ══════════════════════════════════════════════════════════════════════════
    # MOVE DEPLOYED PROP — Reposition an already-active prop
    # Used by edit_state_manager to shift props during edit transitions
    # without going through claim/reclaim cycles.
    # ══════════════════════════════════════════════════════════════════════════
    # MoveDeployedProp<public>(
    #     Prop : creative_prop,
    #     NewPosition : vector3,
    #     NewRotation : rotation
    # ) : logic =
    #     for (Entry : AllEntries):
    #         if (Entry.Prop = Prop):
    #             if (Entry.IsActive?):
    #                 if (Entry.Prop.TeleportTo[NewPosition, NewRotation]):
    #                     set Entry.LastDeployPosition = NewPosition
    #                     return true
    #                 else:
    #                     Logger.Print("POOL_MGR: WARNING — MoveDeployedProp TeleportTo failed.")
    #                     return false
    #     Logger.Print("POOL_MGR: WARNING — MoveDeployedProp called for unknown/inactive prop.")
    #     false

    # ══════════════════════════════════════════════════════════════════════════
    # PRIVATE: Claim helpers
    # ══════════════════════════════════════════════════════════════════════════

    # Scan a pool for the first inactive entry, deploy it, return the prop.
    TryClaimFromPool<private>(
        Pool : []pool_entry,
        Position : vector3,
        Rotation : rotation,
        PieceType : int
    ) : ?creative_prop =
        for (Entry : Pool):
            if (not Entry.IsActive?):
                set GlobalDeployCounter += 1
                set Entry.IsActive = true
                set Entry.DeployOrder = GlobalDeployCounter
                set Entry.LastDeployPosition = Position
                set Entry.DeployTimestamp = GetSimulationElapsedTime()
                if (Entry.Prop.TeleportTo[Position, Rotation]):
                    Logger.Print("POOL_MGR: Deployed {GetTypeName(PieceType)} #{GlobalDeployCounter}.")
                    return option{Entry.Prop}
                else:
                    # TeleportTo failed — roll back and try next entry
                    set Entry.IsActive = false
                    set Entry.DeployOrder = 0
                    Logger.Print("POOL_MGR: TeleportTo failed for entry. Trying next.")
        # No available entry found
        false

    # FIFO: find and reclaim the oldest active entry within a specific pool.
    ReclaimOldestFromPool<private>(Pool : []pool_entry) : void =
        var OldestOrder : int = 999999
        var OldestEntry : ?pool_entry = false

        for (Entry : Pool):
            if (Entry.IsActive?):
                if (Entry.DeployOrder < OldestOrder):
                    set OldestOrder = Entry.DeployOrder
                    set OldestEntry = option{Entry}

        if (Oldest := OldestEntry?):
            set Oldest.IsActive = false
            set Oldest.DeployOrder = 0
            StagingPos := GetStagingPosition()
            if (Oldest.Prop.TeleportTo[StagingPos, IdentityRotation()]):
                set TotalFIFOReclaims += 1
                Logger.Print("POOL_MGR: FIFO reclaimed pool-local oldest (order {OldestOrder}).")
            else:
                Logger.Print("POOL_MGR: WARNING — FIFO reclaim TeleportTo failed.")
        else:
            Logger.Print("POOL_MGR: WARNING — FIFO reclaim requested but pool has no active entries.")

    # ══════════════════════════════════════════════════════════════════════════
    # PRIVATE: Event Bus Integration
    # ══════════════════════════════════════════════════════════════════════════
    DispatchBuildPlacedEvent<private>(PieceType : int, Position : vector3) : void =
        EventData := build_event_data{
            PieceType := GetTypeName(PieceType),
            GridPosition := "({Position.X},{Position.Y},{Position.Z})",
            Timestamp := GetSimulationElapsedTime()
        }
        EventBus.DispatchBuildPlaced(EventData)

    # ══════════════════════════════════════════════════════════════════════════
    # PRIVATE: Utility Methods
    # ══════════════════════════════════════════════════════════════════════════

    GetStagingPosition<private>() : vector3 =
        vector3{X := 0.0, Y := 0.0, Z := StagingPositionZ}

    GetPoolByType<private>(PieceType : int) : []pool_entry =
        if (PieceType = PIECE_WALL):
            return WallPool
        else if (PieceType = PIECE_FLOOR):
            return FloorPool
        else if (PieceType = PIECE_RAMP):
            return RampPool
        ConePool

    GetTypeName<private>(PieceType : int) : string =
        if (PieceType = PIECE_WALL):
            return "Wall"
        else if (PieceType = PIECE_FLOOR):
            return "Floor"
        else if (PieceType = PIECE_RAMP):
            return "Ramp"
        else if (PieceType = PIECE_CONE):
            return "Cone"
        "Unknown"

    TypeNameToInt<private>(TypeName : string) : int =
        if (TypeName = "Wall"):
            return PIECE_WALL
        else if (TypeName = "Floor"):
            return PIECE_FLOOR
        else if (TypeName = "Ramp"):
            return PIECE_RAMP
        else if (TypeName = "Cone"):
            return PIECE_CONE
        PIECE_WALL

    UpdatePeakActive<private>() : void =
        var CurrentActive : int = 0
        for (Entry : AllEntries):
            if (Entry.IsActive?):
                set CurrentActive += 1
        if (CurrentActive > PeakActiveCount):
            set PeakActiveCount = CurrentActive

    # ══════════════════════════════════════════════════════════════════════════
    # PUBLIC QUERIES — Read pool state for analytics and debugging
    # ══════════════════════════════════════════════════════════════════════════

    # Count of currently active (deployed) props of a specific type.
    GetActiveCount<public>(PieceType : int) : int =
        Pool := GetPoolByType(PieceType)
        var Count : int = 0
        for (Entry : Pool):
            if (Entry.IsActive?):
                set Count += 1
        Count

    # Count of available (inactive) props of a specific type.
    GetAvailableCount<public>(PieceType : int) : int =
        Pool := GetPoolByType(PieceType)
        var Count : int = 0
        for (Entry : Pool):
            if (not Entry.IsActive?):
                set Count += 1
        Count

    # Total active across all types.
    GetTotalActiveCount<public>() : int =
        var Count : int = 0
        for (Entry : AllEntries):
            if (Entry.IsActive?):
                set Count += 1
        Count

    # Total pool capacity across all types.
    GetTotalPoolSize<public>() : int =
        AllEntries.Length

    # Pool utilization as a percentage [0.0, 1.0].
    GetPoolUtilization<public>() : float =
        Total := AllEntries.Length
        if (Total > 0):
            Active := GetTotalActiveCount()
            return (Active * 1.0) / (Total * 1.0)
        0.0

    # Whether a specific type's pool is fully exhausted.
    IsPoolExhausted<public>(PieceType : int) : logic =
        Available := GetAvailableCount(PieceType)
        if (Available <= 0):
            return true
        false

    # The peak number of simultaneously active props this session.
    GetPeakActiveCount<public>() : int =
        PeakActiveCount

    # Full telemetry dump for debug logging.
    LogPoolStats<public>() : void =
        Logger.Print("POOL_MGR: ── Pool Statistics ──")
        Logger.Print("POOL_MGR:   Total Claims: {TotalClaims}")
        Logger.Print("POOL_MGR:   Total Reclaims: {TotalReclaims}")
        Logger.Print("POOL_MGR:   FIFO Reclaims: {TotalFIFOReclaims}")
        Logger.Print("POOL_MGR:   ReclaimAll Calls: {TotalReclaimAlls}")
        Logger.Print("POOL_MGR:   Deploy Failures: {TotalDeployFailures}")
        Logger.Print("POOL_MGR:   Peak Active: {PeakActiveCount}")
        Logger.Print("POOL_MGR:   Current Active: {GetTotalActiveCount()}")
        Logger.Print("POOL_MGR:   Pool Size: {GetTotalPoolSize()}")
        Logger.Print("POOL_MGR:   Utilization: {GetPoolUtilization()}")
        Logger.Print("POOL_MGR:   Walls: {GetActiveCount(PIECE_WALL)}/{WallPool.Length}")
        Logger.Print("POOL_MGR:   Floors: {GetActiveCount(PIECE_FLOOR)}/{FloorPool.Length}")
        Logger.Print("POOL_MGR:   Ramps: {GetActiveCount(PIECE_RAMP)}/{RampPool.Length}")
        Logger.Print("POOL_MGR:   Cones: {GetActiveCount(PIECE_CONE)}/{ConePool.Length}")

    # Reset telemetry counters (called between sessions, not rounds).
    ResetTelemetry<public>() : void =
        set TotalClaims = 0
        set TotalReclaims = 0
        set TotalFIFOReclaims = 0
        set TotalReclaimAlls = 0
        set TotalDeployFailures = 0
        set PeakActiveCount = 0

log_pool_ch := class(log_channel):