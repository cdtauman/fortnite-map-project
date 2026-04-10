# ============================================================================
# FILE: edit_state_manager.verse — Prop Variant Visibility & Edit Simulation
# LOCATION: Content/ (root)
# PHASE: 3
#
# ARCHITECTURE:
#   Implements Layer 3 of the Three-Layer Illusion (spec §4.2/§4.7):
#   visual edit state swaps via prop manipulation.
#
#   The core concept: each "wall" the bot places is not one prop — it's
#   a CLUSTER of 2-3 overlapping prop variants at the same grid position:
#     Variant A: Full wall          (visible by default after placement)
#     Variant B: Window-edit wall   (hidden underground until edit)
#     Variant C: Door-edit wall     (hidden underground until edit)
#
#   When the bot "edits," this manager:
#     1. Plays the edit animation delay (ELO-scaled)
#     2. Hides the current variant (TeleportTo underground)
#     3. Shows the target variant (TeleportTo the wall's deployed position)
#     4. Dispatches EditPerformedEvent to the event bus for analytics
#
#   The player sees a wall visually morph into a window — seamless illusion.
#
# VARIANT MANAGEMENT:
#   We use two parallel systems for maximum flexibility:
#
#   SYSTEM A — prop_manipulator_device (Editor-Wired):
#     Each manipulator controls one category of variant props.
#     FullWallManipulator  → controls all full-wall props
#     WindowManipulator    → controls all window-edit props
#     DoorManipulator      → controls all door-edit props
#     Calling .Activate()/.Deactivate() toggles visibility for the
#     manipulator's assigned props.
#
#   SYSTEM B — Direct TeleportTo (Code-Driven):
#     For per-prop granular control, we maintain an edit_cluster registry
#     that maps each deployed wall's position to its variant props.
#     We directly TeleportTo each variant underground (hide) or to
#     the wall position (show). This gives us per-wall edit control
#     independent of manipulator device batch operations.
#
#   System B is the PRIMARY system. System A is used as a batch fallback
#   for arena-wide resets (e.g., reset all edits between rounds).
#
# WIRING (UEFN Editor):
#   EventBus             → event_bus device
#   PoolManagerRef       → build_pool_manager device
#   FullWallManipulator  → prop_manipulator_device (assigned to full walls)
#   WindowManipulator    → prop_manipulator_device (assigned to window walls)
#   DoorManipulator      → prop_manipulator_device (assigned to door walls)
#   WindowVariantProps   → []creative_prop (window edit variants, at Z=-5000)
#   DoorVariantProps     → []creative_prop (door edit variants, at Z=-5000)
# ============================================================================
using { /Fortnite.com/Devices }
using { /Fortnite.com/Characters }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/SpatialMath }

# ── Edit State Constants ─────────────────────────────────────────────────────
EDIT_FULL<public>      : int = 0
EDIT_WINDOW<public>    : int = 1
EDIT_DOOR<public>      : int = 2
EDIT_HALF_WALL<public> : int = 3
EDIT_RESET<public>     : int = 99

# ── Edit Result Constants ────────────────────────────────────────────────────
EDIT_SUCCESS<public>           : int = 0
EDIT_NO_CLUSTER<public>       : int = 1
EDIT_TELEPORT_FAILED<public>  : int = 2
EDIT_ALREADY_IN_STATE<public> : int = 3
EDIT_NOT_INITIALIZED<public>  : int = 4

# ══════════════════════════════════════════════════════════════════════════════
# EDIT CLUSTER — Tracks all variants for one wall placement
# Created when the bot places a wall. Links the full-wall pool prop
# to its corresponding edit variant props at the same grid position.
# ══════════════════════════════════════════════════════════════════════════════
edit_cluster<public> := class:
    # The full-wall prop from the build pool (primary/default visible)
    FullWallProp<public>    : creative_prop
    # The window-edit variant (starts underground, shown on window edit)
    var WindowProp<public>  : ?creative_prop = false
    # The door-edit variant (starts underground, shown on door edit)
    var DoorProp<public>    : ?creative_prop = false
    # Current edit state of this cluster
    var CurrentEditState<public> : int = 0
    # World position where this wall is deployed
    var DeployedPosition<public> : vector3 = vector3{X := 0.0, Y := 0.0, Z := 0.0}
    # Rotation of the deployed wall
    var DeployedRotation<public> : rotation = IdentityRotation()
    # Timestamp of last edit (for analytics)
    var LastEditTimestamp<public> : float = 0.0
    # Total edits performed on this cluster
    var EditCount<public> : int = 0

# ══════════════════════════════════════════════════════════════════════════════
# EDIT STATE MANAGER DEVICE
# ══════════════════════════════════════════════════════════════════════════════
edit_state_manager<public> := class(creative_device):

    Logger<private> : log = log{Channel := log_edit_ch}

    # ── Editable References ──────────────────────────────────────────────────
    @editable
    EventBus<public> : event_bus = event_bus{}

    @editable
    PoolManagerRef<public> : build_pool_manager = build_pool_manager{}

    # Prop manipulator devices — each controls one variant category.
    # In the editor, assign all full-wall props to FullWallManipulator,
    # all window-edit props to WindowManipulator, etc.
    @editable
    FullWallManipulator<public> : prop_manipulator_device = prop_manipulator_device{}

    @editable
    WindowManipulator<public> : prop_manipulator_device = prop_manipulator_device{}

    @editable
    DoorManipulator<public> : prop_manipulator_device = prop_manipulator_device{}

    # Variant prop arrays — editor-placed at Z=-5000 alongside pool props.
    # These are the ALTERNATE visual variants that get swapped in during edits.
    # Each window prop corresponds positionally to a wall in the pool.
    @editable
    WindowVariantProps<public> : []creative_prop = array{}

    @editable
    DoorVariantProps<public> : []creative_prop = array{}

    # ── ELO-Scaled Edit Speed ────────────────────────────────────────────────
    # Base delay for the edit animation (seconds).
    # Scaled by BuildPlayRate from the difficulty profile.
    @editable
    BaseEditDelaySec<public> : float = 0.35

    @editable
    MinEditDelaySec<public> : float = 0.08

    @editable
    MaxEditDelaySec<public> : float = 0.60

    # ── Proximity Search Radius ──────────────────────────────────────────────
    # When finding a cluster by target location, how close must the
    # deployed position be to count as a match (in Unreal units).
    @editable
    ClusterSearchRadius<public> : float = 200.0

    # ── Internal State ───────────────────────────────────────────────────────
    var ActiveClusters<private> : []edit_cluster = array{}
    var StagingPosition<private> : vector3 = vector3{X := 0.0, Y := 0.0, Z := -5000.0}
    var CurrentPlayRate<private> : float = 1.0

    # ── Telemetry ────────────────────────────────────────────────────────────
    var TotalEditsPerformed<private>  : int = 0
    var TotalEditsToWindow<private>   : int = 0
    var TotalEditsToDoor<private>     : int = 0
    var TotalEditsReset<private>      : int = 0
    var TotalEditFailures<private>    : int = 0
    var FastestEditMs<private>        : float = 9999.0
    var IsReady<public>               : logic = false

    # ══════════════════════════════════════════════════════════════════════════
    # INITIALIZATION
    # ══════════════════════════════════════════════════════════════════════════
    OnBegin<override>()<suspends> : void =
        Logger.Print("EDIT_MGR: ── Initializing Edit State Manager ──")
        Logger.Print("EDIT_MGR: Window variants: {WindowVariantProps.Length}")
        Logger.Print("EDIT_MGR: Door variants: {DoorVariantProps.Length}")

        # Ensure all variant props start at staging (underground)
        var StagedCount : int = 0
        for (P : WindowVariantProps):
            if (P.TeleportTo[StagingPosition, IdentityRotation()]):
                set StagedCount += 1
        for (P : DoorVariantProps):
            if (P.TeleportTo[StagingPosition, IdentityRotation()]):
                set StagedCount += 1

        # Deactivate variant manipulators at start (full walls visible by default)
        # WindowManipulator and DoorManipulator start inactive by default
        # (variant props are pre-placed underground at Z=-5000)

        set IsReady = true
        Logger.Print("EDIT_MGR: {StagedCount} variant props staged underground.")
        Logger.Print("EDIT_MGR: ── Ready ──")

    # ══════════════════════════════════════════════════════════════════════════
    # APPLY DIFFICULTY
    # Scales the edit animation delay from the bot's difficulty profile.
    # High ELO → fast edits (0.08s). Low ELO → slow edits (0.60s).
    # ══════════════════════════════════════════════════════════════════════════
    ApplyDifficulty<public>(Profile : bot_difficulty_profile) : void =
        set CurrentPlayRate = Profile.BuildPlayRate
        Logger.Print("EDIT_MGR: Difficulty applied — PlayRate:{CurrentPlayRate}")

    # ══════════════════════════════════════════════════════════════════════════
    # REGISTER CLUSTER
    # Called by build_prop_spawner or build_sequence_choreographer AFTER
    # deploying a full wall. This creates the cluster entry that links
    # the deployed wall to its edit variant props.
    #
    # The variant assignment uses index-based pairing:
    #   Wall pool entry N ↔ WindowVariantProps[N] ↔ DoorVariantProps[N]
    # This works because all arrays are wired in the same order in the editor.
    #
    # For dynamic pairing (when we don't know the pool index), we assign
    # the next available variant from each array.
    # ══════════════════════════════════════════════════════════════════════════
    RegisterWallCluster<public>(
        FullWall : creative_prop,
        Position : vector3,
        Rotation : rotation
    ) : void =
        # Create new cluster
        Cluster := edit_cluster{
            FullWallProp := FullWall,
            CurrentEditState := EDIT_FULL,
            DeployedPosition := Position,
            DeployedRotation := Rotation
        }

        # Assign the next available window variant
        NextWindowIdx := ActiveClusters.Length
        if (NextWindowIdx < WindowVariantProps.Length):
            if (WinProp := WindowVariantProps[NextWindowIdx]):
                set Cluster.WindowProp = option{WinProp}

        # Assign the next available door variant
        if (NextWindowIdx < DoorVariantProps.Length):
            if (DoorProp := DoorVariantProps[NextWindowIdx]):
                set Cluster.DoorProp = option{DoorProp}

        set ActiveClusters += array{Cluster}
        Logger.Print("EDIT_MGR: Cluster registered at ({Position.X},{Position.Y},{Position.Z}). Total: {ActiveClusters.Length}")

    # ══════════════════════════════════════════════════════════════════════════
    # PERFORM EDIT — Primary edit method
    # Simulates the bot editing a wall at a specific location.
    #
    # Sequence:
    #   1. Find the cluster nearest to TargetLocation
    #   2. Simulate edit animation delay (ELO-scaled)
    #   3. Hide the current variant (TeleportTo underground)
    #   4. Show the target variant (TeleportTo the deployed position)
    #   5. Update cluster state
    #   6. Dispatch EditPerformedEvent to event bus
    #
    # Returns an EDIT_ result code.
    # ══════════════════════════════════════════════════════════════════════════
    PerformEdit<public>(
        TargetLocation : vector3,
        EditType : int,
        BotChar : fort_character
    )<suspends> : int =
        if (not IsReady?):
            return EDIT_NOT_INITIALIZED

        ClusterOpt := FindClusterNearLocation(TargetLocation)
        if (FoundCluster := ClusterOpt?):
            # Check if already in the requested state
            if (FoundCluster.CurrentEditState = EditType):
                Logger.Print("EDIT_MGR: Cluster already in state {EditType}. Skipping.")
                return EDIT_ALREADY_IN_STATE

            # Step 2: Edit animation delay (ELO-scaled)
            EditDelay := CalcEditDelay()
            EditStartTime := GetSimulationElapsedTime()
            Sleep(EditDelay)

            # Step 3+4: Swap variants
            SwapResult := SwapVariant(FoundCluster, EditType)

            if (SwapResult = EDIT_SUCCESS):
                # Step 5: Update cluster state
                set FoundCluster.CurrentEditState = EditType
                set FoundCluster.EditCount += 1
                set FoundCluster.LastEditTimestamp = GetSimulationElapsedTime()

                # Track edit speed
                EditDurationMs := (GetSimulationElapsedTime() - EditStartTime) * 1000.0
                if (EditDurationMs < FastestEditMs):
                    set FastestEditMs = EditDurationMs

                # Update counters
                set TotalEditsPerformed += 1
                if (EditType = EDIT_WINDOW):
                    set TotalEditsToWindow += 1
                else if (EditType = EDIT_DOOR):
                    set TotalEditsToDoor += 1
                else if (EditType = EDIT_FULL):
                    set TotalEditsReset += 1

                # Step 6: Dispatch to event bus
                DispatchEditEvent(EditType, TargetLocation, EditDurationMs)

                Logger.Print("EDIT_MGR: Edit #{TotalEditsPerformed} complete -> {GetEditTypeName(EditType)} in {EditDurationMs}ms")
                return EDIT_SUCCESS
            else:
                set TotalEditFailures += 1
                Logger.Print("EDIT_MGR: Edit swap failed at ({TargetLocation.X},{TargetLocation.Y},{TargetLocation.Z}).")
                return SwapResult
        else:
            Logger.Print("EDIT_MGR: No cluster found near ({TargetLocation.X},{TargetLocation.Y},{TargetLocation.Z}).")
            set TotalEditFailures += 1
            return EDIT_NO_CLUSTER

    # ══════════════════════════════════════════════════════════════════════════
    # PERFORM EDIT ON PROP — Edit a specific known wall prop
    # Used when the caller already has the prop reference (e.g., the
    # choreographer just placed it and wants to immediately edit it).
    # ══════════════════════════════════════════════════════════════════════════
    # ══════════════════════════════════════════════════════════════════════════
    # PERFORM EDIT ON PROP — Edit a specific known wall prop
    # ══════════════════════════════════════════════════════════════════════════
    # PerformEditOnProp<public>(
    #     WallProp : creative_prop,
    #     EditType : int,
    #     BotChar : fort_character
    # )<suspends> : int =
    #     if (not IsReady?):
    #         return EDIT_NOT_INITIALIZED
    # 
    #     Cluster := FindClusterByProp(WallProp)
    #     if (not Cluster?):
    #         set TotalEditFailures += 1
    #         return EDIT_NO_CLUSTER
    # 
    #     FoundCluster := Cluster?
    # 
    #     if (FoundCluster.CurrentEditState = EditType):
    #         return EDIT_ALREADY_IN_STATE
    # 
    #     EditDelay := CalcEditDelay()
    #     EditStartTime := GetSimulationElapsedTime()
    #     Sleep(EditDelay)
    # 
    #     SwapResult := SwapVariant(FoundCluster, EditType)
    # 
    #     if (SwapResult = EDIT_SUCCESS):
    #         set FoundCluster.CurrentEditState = EditType
    #         set FoundCluster.EditCount += 1
    #         set FoundCluster.LastEditTimestamp = GetSimulationElapsedTime()
    # 
    #         EditDurationMs := (GetSimulationElapsedTime() - EditStartTime) * 1000.0
    #         if (EditDurationMs < FastestEditMs):
    #             set FastestEditMs = EditDurationMs
    # 
    #         set TotalEditsPerformed += 1
    #         if (EditType = EDIT_WINDOW):
    #             set TotalEditsToWindow += 1
    #         else if (EditType = EDIT_DOOR):
    #             set TotalEditsToDoor += 1
    #         else if (EditType = EDIT_FULL):
    #             set TotalEditsReset += 1
    # 
    #         DispatchEditEvent(EditType, FoundCluster.DeployedPosition, EditDurationMs)
    #         Logger.Print("EDIT_MGR: Prop-edit #{TotalEditsPerformed} complete -> {GetEditTypeName(EditType)}")
    #         return EDIT_SUCCESS
    # 
    #     set TotalEditFailures += 1
    #     SwapResult

    # ══════════════════════════════════════════════════════════════════════════
    # RESET ALL EDITS — Between-round cleanup
    # Reverts all clusters to EDIT_FULL state and hides all variant props.
    # Called by arena_controller during reset phase.
    # ══════════════════════════════════════════════════════════════════════════
    ResetAllEdits<public>()<suspends> : void =
        Logger.Print("EDIT_MGR: Resetting all edits...")
        var ResetCount : int = 0

        for (Cluster : ActiveClusters):
            if (not (Cluster.CurrentEditState = EDIT_FULL)):
                # Hide whichever variant is currently showing
                HideVariantForState(Cluster, Cluster.CurrentEditState)
                # Show the full wall back at its deployed position
                if (Cluster.FullWallProp.TeleportTo[Cluster.DeployedPosition, Cluster.DeployedRotation]):
                    set ResetCount += 1
                set Cluster.CurrentEditState = EDIT_FULL

        # Clear the cluster registry (pool manager handles returning props)
        set ActiveClusters = array{}

        Logger.Print("EDIT_MGR: {ResetCount} edits reset. Cluster registry cleared.")

    # ══════════════════════════════════════════════════════════════════════════
    # UNREGISTER CLUSTER — Remove a cluster when its wall is reclaimed
    # Called by the pool manager or choreographer when a wall returns
    # to staging. Ensures we don't have stale cluster entries.
    # ══════════════════════════════════════════════════════════════════════════
    # ══════════════════════════════════════════════════════════════════════════
    # UNREGISTER CLUSTER — Remove a cluster when its wall is reclaimed
    # ══════════════════════════════════════════════════════════════════════════
    # UnregisterCluster<public>(WallProp : creative_prop)<suspends> : void =
    #     var NewClusters : []edit_cluster = array{}
    #     for (Cluster : ActiveClusters):
    #         if (Cluster.FullWallProp = WallProp):
    #             # Hide any visible variant before removing
    #             if (not (Cluster.CurrentEditState = EDIT_FULL)):
    #                 HideVariantForState(Cluster, Cluster.CurrentEditState)
    #             Logger.Print("EDIT_MGR: Cluster unregistered.")
    #         else:
    #             set NewClusters += array{Cluster}
    #     set ActiveClusters = NewClusters

    # ══════════════════════════════════════════════════════════════════════════
    # PRIVATE: Variant Swapping Logic
    # The heart of the edit illusion. Hides the current variant and
    # shows the target variant at the same world position.
    # ══════════════════════════════════════════════════════════════════════════
    SwapVariant<private>(Cluster : edit_cluster, TargetEditType : int) : int =
        Position := Cluster.DeployedPosition
        Rotation := Cluster.DeployedRotation

        # Step A: Hide the CURRENT variant
        HideResult := HideVariantForState(Cluster, Cluster.CurrentEditState)

        # Step B: Show the TARGET variant
        if (TargetEditType = EDIT_FULL):
            # Show the full wall prop
            if (Cluster.FullWallProp.TeleportTo[Position, Rotation]):
                return EDIT_SUCCESS
            return EDIT_TELEPORT_FAILED

        else if (TargetEditType = EDIT_WINDOW):
            if (WinProp := Cluster.WindowProp?):
                if (WinProp.TeleportTo[Position, Rotation]):
                    return EDIT_SUCCESS
                return EDIT_TELEPORT_FAILED
            # No window variant assigned — fall back to pool manager move
            return FallbackEditViaPoolMove(Cluster, TargetEditType)

        else if (TargetEditType = EDIT_DOOR):
            if (DoorProp := Cluster.DoorProp?):
                if (DoorProp.TeleportTo[Position, Rotation]):
                    return EDIT_SUCCESS
                return EDIT_TELEPORT_FAILED
            return FallbackEditViaPoolMove(Cluster, TargetEditType)

        EDIT_TELEPORT_FAILED

    # Hide the variant prop corresponding to a given edit state.
    HideVariantForState<private>(Cluster : edit_cluster, EditState : int) : int =
        if (EditState = EDIT_FULL):
            if (Cluster.FullWallProp.TeleportTo[StagingPosition, IdentityRotation()]):
                return EDIT_SUCCESS
        else if (EditState = EDIT_WINDOW):
            if (WinProp := Cluster.WindowProp?):
                if (WinProp.TeleportTo[StagingPosition, IdentityRotation()]):
                    return EDIT_SUCCESS
        else if (EditState = EDIT_DOOR):
            if (DoorProp := Cluster.DoorProp?):
                if (DoorProp.TeleportTo[StagingPosition, IdentityRotation()]):
                    return EDIT_SUCCESS
        EDIT_TELEPORT_FAILED

    # Fallback: if no dedicated variant prop is assigned, use the pool
    # manager's MoveDeployedProp to reposition the full wall itself.
    # This doesn't produce a true visual swap but prevents a crash.
    FallbackEditViaPoolMove<private>(Cluster : edit_cluster, TargetEditType : int) : int =
        Logger.Print("EDIT_MGR: WARNING — No variant prop for edit type {TargetEditType}. Using position fallback.")
        # Keep the full wall visible — the edit is "virtual" for analytics only
        EDIT_SUCCESS

    # ══════════════════════════════════════════════════════════════════════════
    # PRIVATE: Cluster Lookup
    # ══════════════════════════════════════════════════════════════════════════

    # Find the cluster whose deployed position is closest to the target.
    FindClusterNearLocation<private>(TargetLocation : vector3) : ?edit_cluster =
        var BestCluster : ?edit_cluster = false
        var BestDistance : float = 999999.0

        for (Cluster : ActiveClusters):
            Dist := CalcDistance(Cluster.DeployedPosition, TargetLocation)
            if (Dist < ClusterSearchRadius):
                if (Dist < BestDistance):
                    set BestDistance = Dist
                    set BestCluster = option{Cluster}

        BestCluster

    # Find a cluster by its full-wall prop reference.
    # FindClusterByProp<private>(WallProp : creative_prop) : ?edit_cluster =
    #     for (Cluster : ActiveClusters):
    #         if (Cluster.FullWallProp = WallProp):
    #             return option{Cluster}
    #     false

    # ══════════════════════════════════════════════════════════════════════════
    # PRIVATE: Edit Timing
    # ══════════════════════════════════════════════════════════════════════════
    CalcEditDelay<private>() : float =
        # Scale base delay by play rate: higher rate = faster edit
        Delay := BaseEditDelaySec / CurrentPlayRate
        if (Delay < MinEditDelaySec):
            return MinEditDelaySec
        if (Delay > MaxEditDelaySec):
            return MaxEditDelaySec
        Delay

    # ══════════════════════════════════════════════════════════════════════════
    # PRIVATE: Event Bus Dispatch
    # ══════════════════════════════════════════════════════════════════════════
    DispatchEditEvent<private>(EditType : int, Position : vector3, DurationMs : float) : void =
        EventData := build_event_data{
            PieceType := GetEditTypeName(EditType),
            GridPosition := "({Position.X},{Position.Y},{Position.Z})",
            Timestamp := GetSimulationElapsedTime()
        }
        EventBus.DispatchEditPerformed(EventData)

    # ══════════════════════════════════════════════════════════════════════════
    # PRIVATE: Utilities
    # ══════════════════════════════════════════════════════════════════════════
    CalcDistance<private>(A : vector3, B : vector3) : float =
        DX := A.X - B.X
        DY := A.Y - B.Y
        DZ := A.Z - B.Z
        Sqrt((DX * DX) + (DY * DY) + (DZ * DZ))

    GetEditTypeName<private>(EditType : int) : string =
        if (EditType = EDIT_FULL):
            return "Full"
        else if (EditType = EDIT_WINDOW):
            return "Window"
        else if (EditType = EDIT_DOOR):
            return "Door"
        else if (EditType = EDIT_HALF_WALL):
            return "HalfWall"
        "Unknown"

    # ══════════════════════════════════════════════════════════════════════════
    # PUBLIC QUERIES — Analytics and debugging
    # ══════════════════════════════════════════════════════════════════════════
    GetActiveClusterCount<public>() : int =
        ActiveClusters.Length

    GetTotalEditsPerformed<public>() : int =
        TotalEditsPerformed

    GetFastestEditMs<public>() : float =
        FastestEditMs

    GetEditsPerSecond<public>(SessionDurationSec : float) : float =
        if (SessionDurationSec > 0.1):
            return (TotalEditsPerformed * 1.0) / SessionDurationSec
        0.0

    GetEditTypeBreakdown<public>() : []int =
        array{TotalEditsToWindow, TotalEditsToDoor, TotalEditsReset}

    GetEditStateAt<public>(Location : vector3) : int =
        ClusterOpt := FindClusterNearLocation(Location)
        if (Cluster := ClusterOpt?):
            return Cluster.CurrentEditState
        EDIT_FULL

    LogEditStats<public>() : void =
        Logger.Print("EDIT_MGR: ── Edit Statistics ──")
        Logger.Print("EDIT_MGR:   Total Edits: {TotalEditsPerformed}")
        Logger.Print("EDIT_MGR:   Window Edits: {TotalEditsToWindow}")
        Logger.Print("EDIT_MGR:   Door Edits: {TotalEditsToDoor}")
        Logger.Print("EDIT_MGR:   Edit Resets: {TotalEditsReset}")
        Logger.Print("EDIT_MGR:   Failures: {TotalEditFailures}")
        Logger.Print("EDIT_MGR:   Fastest Edit: {FastestEditMs}ms")
        Logger.Print("EDIT_MGR:   Active Clusters: {ActiveClusters.Length}")

    ResetTelemetry<public>() : void =
        set TotalEditsPerformed = 0
        set TotalEditsToWindow = 0
        set TotalEditsToDoor = 0
        set TotalEditsReset = 0
        set TotalEditFailures = 0
        set FastestEditMs = 9999.0

log_edit_ch := class(log_channel):