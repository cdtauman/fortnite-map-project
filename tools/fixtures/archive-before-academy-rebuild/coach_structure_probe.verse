using { /Fortnite.com/Devices }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Itemization }
using { /Fortnite.com/Playspaces }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Itemization }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/SpatialMath }

CoachProbeMessage<localizes>(Text : string):message = "{Text}"

CoachSpawnStatus(Result : spawn_prop_result)<computes>:string =
    if (Result = spawn_prop_result.Ok):
        return "ok"
    if (Result = spawn_prop_result.InvalidAsset):
        return "invalid_asset"
    if (Result = spawn_prop_result.InvalidSpawnPoint):
        return "invalid_spawn_point"
    if (Result = spawn_prop_result.SpawnPointOutOfBounds):
        return "out_of_bounds"
    if (Result = spawn_prop_result.TooManyProps):
        return "too_many_props"
    return "unknown_error"

# Private final-test fixture. It never enables the encounter's acceptance gates.
coach_structure_probe_device := class(creative_device):
    @editable
    Enabled : logic = false
    @editable
    AutoRun : logic = false
    @editable
    Structures : coach_structure_device = coach_structure_device{}
    @editable
    ResetControl : button_device = button_device{}
    @editable
    ShapeControl : button_device = button_device{}
    @editable
    PreplacedWall : creative_prop = creative_prop{}
    @editable
    NativePoolControl : logic = false
    @editable
    NativePoolWallOne : creative_prop = creative_prop{}
    @editable
    NativePoolWallTwo : creative_prop = creative_prop{}
    @editable
    PoolFixtureInitializer : coach_health_probe_device = coach_health_probe_device{}

    var Ending : logic = false
    var Owner : ?agent = false
    var Pieces : []creative_prop = array{}
    var Wall : ?creative_prop = false
    var Serial : int = 0
    var Shape : int = 0
    var ShapeRevision : int = 0
    var Bindings : []cancelable = array{}
    var PreplacedOriginal : ?transform = false
    Geometry : coach_geometry_query = coach_geometry_query{}
    NativePool : coach_native_piece_pool = coach_native_piece_pool{}

    OnBegin<override>()<suspends>:void =
        if (not Enabled?):
            return
        if (Structures.CandidateCombatEnabled? or Structures.QueryCoverageConfirmed? or Structures.HealthContinuityConfirmed? or Structures.NativeSlotInteroperationConfirmed?):
            Print("PCL|structure_probe|not_started|acceptance_gates_not_clear")
            return
        if (NativePoolControl?):
            if (AutoRun?):
                spawn { RunNativePoolSequence() }
            return
        ResetControl.SetInteractionText(CoachProbeMessage("Reset structure check"))
        ShapeControl.SetInteractionText(CoachProbeMessage("Next wall shape / sample"))
        ResetControl.Enable()
        ShapeControl.Enable()
        set Bindings = array{
            ResetControl.InteractedWithEvent.Subscribe(OnReset),
            ShapeControl.InteractedWithEvent.Subscribe(OnShape),
            GetPlayspace().PlayerRemovedEvent().Subscribe(OnPlayerLeft)
        }
        Print("PCL|structure_probe|ready|combat_gates=false|runtime_semantics_unverified")
        if (AutoRun?):
            spawn { RunAutomaticSequence() }

    RunAutomaticSequence()<suspends>:void =
        for (Attempt := 0..49):
            if (Ending?):
                return
            for (Player : GetPlayspace().GetPlayers(), Character := Player.GetFortCharacter[], Character.IsActive[]):
                OnReset(Player)
                Ticket := Serial
                for (Stage := 0..2):
                    Sleep(1.0)
                    if (Ending? or Ticket <> Serial):
                        return
                    OnShape(Player)
                Sleep(0.4)
                RunPreplacedSequence(Ticket)
                Print("PCL|structure_probe|automatic_sequence_finished|generation={Ticket}|results_require_review")
                return
            Sleep(0.2)
        Print("PCL|structure_probe|automatic_sequence_not_run|player_unavailable")

    OnEnd<override>():void =
        set Ending = true
        NativePool.RetireAll()
        RestorePreplaced()
        ClearPieces()
        for (Binding : Bindings):
            Binding.Cancel()
        if (Enabled?):
            ResetControl.Disable()
            ShapeControl.Disable()

    RunNativePoolSequence()<suspends>:void =
        defer:
            NativePool.RetireAll()
        if (not NativePoolWallOne.IsValid[] or not NativePoolWallTwo.IsValid[] or Structures.UseNativePiecePool?):
            Print("PCL|structure_probe|automatic_sequence_not_run|pool_requires_two_private_walls_and_main_disabled")
            return
        if (PoolFixtureInitializer.Enabled?):
            Print("PCL|structure_probe|automatic_sequence_not_run|shared_fixture_health_probe_enabled")
            return
        var FixtureReady : logic = false
        var Attempt : int = 0
        loop:
            if (Ending?):
                return
            if (PoolFixtureInitializer.InitializationComplete?):
                set FixtureReady = true
                break
            set Attempt += 1
            if (Attempt >= 40):
                break
            Sleep(0.05)
        if (not FixtureReady?):
            Print("PCL|structure_probe|automatic_sequence_not_run|shared_fixture_initialization_timeout")
            return
        Print("PCL|structure_probe|native_pool_fixture_ready|health_initialization_complete=1|health_enabled=0")
        InvalidPool := coach_native_piece_pool{}
        InvalidPool.Register(array{NativePoolWallOne, NativePoolWallOne}, coach_piece_kind.Wall)
        InvalidPool.Seal()
        Pose := transform{Translation := vector3{X := -2560.0, Y := -8192.0}, Rotation := MakeRotationFromYawPitchRollDegrees(90.0, 0.0, 0.0)}
        # GridKit walls lie in local XZ. Actor yaw90 makes the wall normal world X;
        # SampleWall yaw0 sweeps world X. Parking actors remain at their original yaw0.
        QueryYaw := 0.0
        Rejected := InvalidPool.Acquire(coach_piece_kind.Wall, Pose, 112)
        if (Rejected? or InvalidPool.ConfigurationValid?):
            Print("PCL|structure_probe|automatic_sequence_not_run|duplicate_pool_not_rejected")
            return
        NativePool.Register(array{NativePoolWallOne, NativePoolWallTwo}, coach_piece_kind.Wall)
        NativePool.Seal()
        if (not NativePool.ConfigurationValid? or NativePool.Available(coach_piece_kind.Wall) <> 2):
            Print("PCL|structure_probe|automatic_sequence_not_run|pool_configuration_invalid")
            return
        Print("PCL|structure_probe|native_pool_registered|available=2|duplicate_configuration_rejected=1")
        FirstAllocation := NativePool.Acquire(coach_piece_kind.Wall, Pose, 112)
        if (Lease := FirstAllocation?, Root := GetSimulationEntity[]):
            for (Stage := 0..3):
                if (Ending? or not Lease.Prop.IsValid[]):
                    return
                if (Stage = 1):
                    Lease.Prop.SetMesh(Structures.WallWindowMesh)
                else if (Stage = 2):
                    Lease.Prop.SetMesh(Structures.WallExitMesh)
                else:
                    Lease.Prop.SetMesh(Structures.WallSolidMesh)
                Sleep(0.2)
                if (Ending? or not Lease.Prop.IsValid[]):
                    return
                Old := Geometry.SampleWall(Root, Lease.Parking.Translation, 90.0)
                Current := Geometry.SampleWall(Root, Pose.Translation, QueryYaw)
                Print("PCL|structure_probe|native_pool_shape|stage={Stage}|old_cells={Old.Occupied}|new_cells={Current.Occupied}|same_lease=1|query_yaw={QueryYaw}|native_edit_not_invoked")
            NativePool.RetireEncounter(113)
            if (Lease.State <> coach_pool_piece_state.Active):
                Print("PCL|structure_probe|automatic_sequence_not_run|wrong_encounter_retired_lease")
                return
            NativePool.RetireEncounter(112)
            Sleep(0.2)
            if (Ending? or not Lease.Prop.IsValid[]):
                return
            FirstAfter := Geometry.SampleWall(Root, Pose.Translation, QueryYaw)
            ParkingError := Distance(Lease.Prop.GetTransform().Translation, Lease.Parking.Translation)
            var Spent : int = 0
            if (Lease.State = coach_pool_piece_state.Spent):
                set Spent = 1
            Print("PCL|structure_probe|native_pool_retired|cells={FirstAfter.Occupied}|parking_error={ParkingError}|state_spent={Spent}|available={NativePool.Available(coach_piece_kind.Wall)}|wrong_encounter_ignored=1")
            SecondPose := transform{Translation := Pose.Translation + vector3{X := 1024.0}, Rotation := Pose.Rotation}
            SecondAllocation := NativePool.Acquire(coach_piece_kind.Wall, SecondPose, 114)
            if (Second := SecondAllocation?, Second <> Lease):
                Sleep(0.2)
                if (Ending? or not Second.Prop.IsValid[]):
                    return
                SecondCells := Geometry.SampleWall(Root, SecondPose.Translation, QueryYaw)
                ThirdAllocation := NativePool.Acquire(coach_piece_kind.Wall, Pose, 115)
                if (ThirdAllocation?):
                    Print("PCL|structure_probe|automatic_sequence_not_run|pool_overallocated")
                    return
                Print("PCL|structure_probe|native_pool_second|cells={SecondCells.Occupied}|distinct_lease=1|third_rejected=1|available={NativePool.Available(coach_piece_kind.Wall)}")
                NativePool.RetireAll()
                Sleep(0.2)
                FinalCells := Geometry.SampleWall(Root, SecondPose.Translation, QueryYaw)
                FourthAllocation := NativePool.Acquire(coach_piece_kind.Wall, Pose, 116)
                if (FourthAllocation?):
                    Print("PCL|structure_probe|automatic_sequence_not_run|spent_pool_reissued")
                    return
                Print("PCL|structure_probe|native_pool_finished|cells={FinalCells.Occupied}|available={NativePool.Available(coach_piece_kind.Wall)}|spent_not_reissued=1|no_heal_dispose_or_damage|native_slots_and_ownership_unmeasured")
                Print("PCL|structure_probe|automatic_sequence_finished|native_pool|results_require_review")
                return
        Print("PCL|structure_probe|automatic_sequence_not_run|pool_allocation_or_root_unavailable")

    OnPlayerLeft(Player : player):void =
        if (Current := Owner?, Current = Player):
            RestorePreplaced()
            ClearPieces()
            set Owner = false

    RestorePreplaced():void =
        if (Original := PreplacedOriginal?, PreplacedWall.IsValid[]):
            PreplacedWall.SetMesh(Structures.WallSolidMesh)
            if (PreplacedWall.TeleportTo[Original]):
                set PreplacedOriginal = false
                Print("PCL|structure_probe|preplaced_restored")
            else:
                Print("PCL|structure_probe|preplaced_restore_failed")

    # Isolated comparison: move an existing owned wall and change its mesh.
    # This does not invoke native editing or establish structural-grid updates.
    RunPreplacedSequence(Ticket : int)<suspends>:void =
        if (Ending? or Ticket <> Serial or not PreplacedWall.IsValid[]):
            return
        Original := PreplacedWall.GetTransform()
        set PreplacedOriginal = option{Original}
        Destination := transform{
            Translation := GetTransform().Translation + vector3{X := -2560.0},
            Rotation := Original.Rotation,
            Scale := Original.Scale
        }
        if (PreplacedWall.TeleportTo[Destination]):
            Sleep(0.2)
            if (Ending? or Ticket <> Serial):
                RestorePreplaced()
                return
            if (Root := GetSimulationEntity[]):
                Old := Geometry.SampleWall(Root, Original.Translation, 90.0)
                New := Geometry.SampleWall(Root, Destination.Translation, 90.0)
                Print("PCL|structure_probe|preplaced_moved|old={Old.Occupied}|new={New.Occupied}|health_and_grid_unmeasured")
            for (Stage := 1..3):
                if (Ending? or Ticket <> Serial or not PreplacedWall.IsValid[]):
                    RestorePreplaced()
                    return
                if (Stage = 1):
                    PreplacedWall.SetMesh(Structures.WallWindowMesh)
                else if (Stage = 2):
                    PreplacedWall.SetMesh(Structures.WallExitMesh)
                else:
                    PreplacedWall.SetMesh(Structures.WallSolidMesh)
                Sleep(0.2)
                if (Root := GetSimulationEntity[], not Ending?, Ticket = Serial):
                    Result := Geometry.SampleWall(Root, Destination.Translation, 90.0)
                    Print("PCL|structure_probe|preplaced_mesh|stage={Stage}|occupied={Result.Occupied}|native_edit_not_invoked")
        else:
            Print("PCL|structure_probe|preplaced_move_failed")
        RestorePreplaced()

    OwnsControl(Agent : agent)<transacts>:logic =
        if (Current := Owner?):
            if (Current = Agent):
                return true
            return false
        return true

    ClearPieces():void =
        RestorePreplaced()
        set Serial += 1
        set ShapeRevision += 1
        set Wall = false
        for (Prop : Pieces, Prop.IsValid[]):
            Prop.Dispose()
        set Pieces = array{}

    WallPosition()<transacts>:vector3 =
        return GetTransform().Translation + vector3{X := 256.0}

    DemoPosition()<transacts>:vector3 =
        return GetTransform().Translation + vector3{X := 4096.0}

    OnReset(Agent : agent):void =
        if (Ending? or not Enabled? or not OwnsControl(Agent)?):
            return
        set Owner = option{Agent}
        ClearPieces()
        set Shape = 0
        Origin := GetTransform().Translation
        for (Index -> Kind : array{coach_piece_kind.Wall, coach_piece_kind.FloorPiece, coach_piece_kind.Ramp, coach_piece_kind.Cone}):
            var Center : vector3 = Origin + vector3{X := Index * 1024.0}
            if (Index = 0):
                set Center = WallPosition()
            Pose := Structures.GridTransform(Kind, Center, 0.0)
            Result := SpawnProp(Structures.AssetFor(Kind), Pose.Translation, Pose.Rotation)
            Status := CoachSpawnStatus(Result(1))
            Print("PCL|structure_probe|spawn|generation={Serial}|kind={Index}|result={Status}")
            if (Prop := Result(0)?, Result(1) = spawn_prop_result.Ok, Prop.IsValid[]):
                set Pieces += array{Prop}
                Actual := Prop.GetTransform()
                Print("PCL|structure_probe|spawn_transform|generation={Serial}|kind={Index}|x={Actual.Translation.X}|y={Actual.Translation.Y}|z={Actual.Translation.Z}")
                if (Index = 0):
                    set Wall = option{Prop}
        DemoResult := SpawnProp(Structures.DemoAsset, DemoPosition(), MakeRotationFromYawPitchRollDegrees(0.0, 0.0, 0.0))
        DemoStatus := CoachSpawnStatus(DemoResult(1))
        Print("PCL|structure_probe|demo_spawn|result={DemoStatus}|building_prop_control_only")
        if (Demo := DemoResult(0)?, DemoResult(1) = spawn_prop_result.Ok, Demo.IsValid[]):
            set Pieces += array{Demo}
        spawn { SampleAfterUpdate(Serial, ShapeRevision) }
        spawn { WatchLifetime(Serial) }
        spawn { WatchBuildInventory(Agent, Serial) }

    OnShape(Agent : agent):void =
        if (Ending? or not Enabled? or not OwnsControl(Agent)?):
            return
        if (Prop := Wall?, Prop.IsValid[]):
            set ShapeRevision += 1
            set Shape += 1
            if (Shape > 2):
                set Shape = 0
            if (Shape = 1):
                Prop.SetMesh(Structures.WallWindowMesh)
            else if (Shape = 2):
                Prop.SetMesh(Structures.WallExitMesh)
            else:
                Prop.SetMesh(Structures.WallSolidMesh)
            # Keep this exact prop reference; no respawn, healing or synthetic damage.
            Print("PCL|structure_probe|shape_requested|generation={Serial}|command={ShapeRevision}|shape={Shape}|health_unmeasured")
            spawn { SampleAfterUpdate(Serial, ShapeRevision) }
        else:
            Print("PCL|structure_probe|wall_missing|reset_required")
            spawn { SampleAfterUpdate(Serial, ShapeRevision) }

    SampleAfterUpdate(Ticket : int, Command : int)<suspends>:void =
        ExpectedShape := Shape
        Sleep(0.2)
        if (Ending? or Ticket <> Serial or Command <> ShapeRevision):
            return
        if (Root := GetSimulationEntity[]):
            Result := Geometry.SampleWall(Root, WallPosition(), 0.0)
            Empty := Geometry.SampleWall(Root, WallPosition() + vector3{Y := 768.0}, 0.0)
            var Mask : string = ""
            for (Cell : Result.Cells):
                if (Cell?):
                    set Mask += "1"
                else:
                    set Mask += "0"
            Print("PCL|structure_probe|query|generation={Ticket}|command={Command}|shape={ExpectedShape}|occupied={Result.Occupied}|mask={Mask}|control={Empty.Occupied}")
            Demo := Geometry.SampleWall(Root, DemoPosition(), 0.0)
            Print("PCL|structure_probe|demo_query|generation={Ticket}|command={Command}|occupied={Demo.Occupied}|generated_class_binding_control")
            if (PreplacedWall.IsValid[]):
                Placed := Geometry.SampleWall(Root, PreplacedWall.GetTransform().Translation, 90.0)
                Print("PCL|structure_probe|preplaced_course_wall|generation={Ticket}|command={Command}|occupied={Placed.Occupied}")
            else:
                Print("PCL|structure_probe|preplaced_course_wall_unavailable|generation={Ticket}")
        else:
            Print("PCL|structure_probe|query_unavailable|generation={Ticket}")

    WatchLifetime(Ticket : int)<suspends>:void =
        var LastCount : int = -1
        loop:
            if (Ending? or Ticket <> Serial):
                return
            var Count : int = 0
            for (Prop : Pieces, Prop.IsValid[]):
                set Count += 1
            if (Count <> LastCount):
                Print("PCL|structure_probe|valid_props|generation={Ticket}|count={Count}")
                set LastCount = Count
            Sleep(0.2)

    ReadBuildInventory(Agent : agent)<transacts>:string =
        if (Character := Agent.GetFortCharacter[], Body := Character.GetEntity[]):
            var Slots : int = 0
            var Equipped : string = ""
            for (Hotbar : Body.FindDescendantComponents(fort_inventory_build_hotbar_component), Item : Hotbar.GetItems()):
                set Slots += 1
                if (Component := Item.GetComponent[item_component], Component.IsEquipped[]):
                    set Equipped += "1"
                else:
                    set Equipped += "0"
            return "slots={Slots}|equipped_mask={Equipped}"
        return "unavailable"

    WatchBuildInventory(Agent : agent, Ticket : int)<suspends>:void =
        var Previous : string = ""
        loop:
            if (Ending? or Ticket <> Serial or not OwnsControl(Agent)?):
                return
            Current := ReadBuildInventory(Agent)
            if (Current <> Previous):
                At := GetSimulationElapsedTime()
                # An equipped item is not proof of placement, editing or input timing.
                Print("PCL|structure_probe|build_inventory|generation={Ticket}|at={At}|{Current}")
                set Previous = Current
            Sleep(0.2)
