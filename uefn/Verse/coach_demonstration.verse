using { /Fortnite.com/AI }
using { /Fortnite.com/Armory }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Devices }
using { /Fortnite.com/Itemization }
using { /UnrealEngine.com/Itemization }
using { /Verse.org/Assets }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/SpatialMath }

var CoachDemoStations : weak_map(session, []coach_demo_device) = map{}

# Authored teaching geometry and a native character, separate from encounter building semantics.
coach_demo_device := class(creative_device):
    @editable
    Wall : creative_prop = creative_prop{}
    @editable
    FloorPart : creative_prop = creative_prop{}
    @editable
    Cone : creative_prop = creative_prop{}
    @editable
    Ramp : creative_prop = creative_prop{}
    @editable
    Landing : creative_prop = creative_prop{}
    @editable
    TargetMarker : creative_prop = creative_prop{}
    @editable
    CursorMarker : creative_prop = creative_prop{}
    @editable
    Spawner : npc_spawner_device = npc_spawner_device{}
    @editable
    Camera : gameplay_camera_fixed_point_device = gameplay_camera_fixed_point_device{}
    @editable
    Rate25 : movement_modulator_device = movement_modulator_device{}
    @editable
    Rate50 : movement_modulator_device = movement_modulator_device{}
    @editable
    Rate75 : movement_modulator_device = movement_modulator_device{}
    @editable
    Rate100 : movement_modulator_device = movement_modulator_device{}
    @editable
    Rate125 : movement_modulator_device = movement_modulator_device{}
    @editable
    Rate150 : movement_modulator_device = movement_modulator_device{}
    @editable
    Rate175 : movement_modulator_device = movement_modulator_device{}
    @editable
    Rate200 : movement_modulator_device = movement_modulator_device{}

    var SpeedEffects : []movement_modulator_device = array{}

    var CurrentOwner : ?player = false
    var Avatar : ?agent = false
    var Revision : int = 0
    var Lesson : int = -1
    var Step : int = -1
    var Substep : int = -1
    var Playing : logic = false
    var Speed : float = 1.0
    var NeedsSeek : logic = true
    var MotionReady : logic = false
    var ShotKey : int = -1
    var Ready : logic = false
    var Ending : logic = false
    var AvailableAfter : float = 0.0
    var SpawnBinding : ?cancelable = false
    var SpawnRequestedAt : float = -100.0
    var SpawnGeneration : int = 0
    var SpawnAttempts : int = 0
    var ViewingCharacter : ?fort_character = false

    OnBegin<override>()<suspends>:void =
        var Stations : []coach_demo_device = array{}
        if (Existing := CoachDemoStations[GetSession()]):
            set Stations = Existing
        if (set CoachDemoStations[GetSession()] = Stations + array{Self}) {}
        set SpeedEffects = array{Rate25, Rate50, Rate75, Rate100, Rate125, Rate150, Rate175, Rate200}
        set SpawnBinding = option{Spawner.SpawnedEvent.Subscribe(OnAvatarSpawned)}
        var Valid : int = 0
        for (Part : array{Wall, FloorPart, Cone, Ramp, Landing, TargetMarker, CursorMarker}, Part.IsValid[]):
            set Part.CanBeDamaged = false
            Part.Hide()
            set Valid += 1
        if (Valid = 7 and SpeedEffects.Length = 8):
            set Ready = true

    OnEnd<override>():void =
        set Ending = true
        if (Player := CurrentOwner?):
            Release(Player)
        if (Binding := SpawnBinding?):
            Binding.Cancel()

    Acquire(Player : player):?vector3 =
        if (Ending? or not Ready? or GetSimulationElapsedTime() < AvailableAfter):
            return false
        if (Owner := CurrentOwner?):
            if (Owner = Player):
                PrepareViewer(Player)
                var Alive : logic = false
                if (Agent := Avatar?, Character := Agent.GetFortCharacter[], Character.IsActive[]):
                    set Alive = true
                if (not Alive? and GetSimulationElapsedTime() - SpawnRequestedAt > 2.0):
                    set NeedsSeek = true
                    set Revision += 1
                    RequestAvatar()
                return option{GetTransform().Translation + vector3{X := 1000.0, Y := 200.0, Z := 100.0}}
            return false
        set CurrentOwner = option{Player}
        set Revision += 1
        set Lesson = -1
        set Step = -1
        set Substep = -1
        set MotionReady = false
        set NeedsSeek = true
        set SpawnAttempts = 0
        RequestAvatar()
        PrepareViewer(Player)
        return option{GetTransform().Translation + vector3{X := 1000.0, Y := 200.0, Z := 100.0}}

    PrepareViewer(Player : player):void =
        if (Character := Player.GetFortCharacter[]):
            if (Previous := ViewingCharacter?, Previous = Character):
                return
            Camera.RemoveFrom(Player)
            Camera.Enable()
            Camera.AddTo(Player)
            Character.Hide()
            Character.SetVulnerability(false)
            Character.PutInStasis(stasis_args{AllowTurning := false, AllowFalling := false})
            set ViewingCharacter = option{Character}

    Release(Player : player):void =
        if (Owner := CurrentOwner?, Owner = Player):
            set Revision += 1
            set Playing = false
            set CurrentOwner = false
            set Avatar = false
            set SpawnGeneration += 1
            set SpawnAttempts = 0
            set AvailableAfter = GetSimulationElapsedTime() + 0.5
            Camera.RemoveFrom(Player)
            set ViewingCharacter = false
            if (Character := Player.GetFortCharacter[]):
                Character.ReleaseFromStasis()
                Character.Show()
            Spawner.DespawnAll(false)
            for (Part : array{Wall, FloorPart, Cone, Ramp, Landing, TargetMarker, CursorMarker}, Part.IsValid[]):
                Part.Hide()

    OnAvatarSpawned(Agent : agent):void =
        if (not CurrentOwner? or Ending?):
            return
        if (Character := Agent.GetFortCharacter[], Character.IsActive[]):
            for (Owned : Spawner.GetAgents(), Owned = Agent):
                if (Previous := Avatar?, Previous = Agent):
                    return
                set Avatar = option{Agent}
                Character.SetVulnerability(false)
                set Revision += 1
                set NeedsSeek = true
                return

    RequestAvatar():void =
        if (Ending? or not CurrentOwner? or SpawnAttempts >= 2):
            return
        set SpawnAttempts += 1
        set SpawnGeneration += 1
        set SpawnRequestedAt = GetSimulationElapsedTime()
        set Avatar = false
        set MotionReady = false
        Spawner.Reset()
        Spawner.Spawn()
        spawn { AwaitAvatar(SpawnGeneration) }

    AwaitAvatar(Ticket : int)<suspends>:void =
        for (Attempt := 0..79):
            Sleep(0.1)
            if (Ending? or not CurrentOwner? or Ticket <> SpawnGeneration):
                return
            if (Current := Avatar?, Character := Current.GetFortCharacter[], Character.IsActive[]):
                return
            for (Owned : Spawner.GetAgents(), Character := Owned.GetFortCharacter[], Character.IsActive[]):
                OnAvatarSpawned(Owned)
                return

    Present(Player : player, Topic : int, Phase : int, Active : logic, Rate : float, Fraction : float, ?Seek : logic = false):void =
        if (Owner := CurrentOwner?, Owner = Player):
            var NextSubstep : int = 0
            if (Topic = 0 and Phase = 2 and Fraction >= 0.35):
                set NextSubstep = 1
            SceneChanged := logic{Lesson <> Topic or Step <> Phase or Substep <> NextSubstep}
            if (SceneChanged? or Playing <> Active or Speed <> Rate or Seek?):
                set Revision += 1
                set MotionReady = false
            if (Seek? or Lesson <> Topic or Step <> Phase and (Phase = 0 or Phase = 5)):
                set NeedsSeek = true
                set ShotKey = -1
            set Lesson = Topic
            set Step = Phase
            set Substep = NextSubstep
            set Playing = Active
            set Speed = Clamp(Rate, 0.25, 2.0)
            if (SceneChanged?):
                ApplyScene()

    PosePart(Part : creative_prop, Local : vector3, Shape : mesh):void =
        if (Part.IsValid[]):
            Part.SetMesh(Shape)
            if (Part.TeleportTo[GetTransform().Translation + Local, IdentityRotation()]) {}
            Part.Show()

    ApplyScene():void =
        if (Lesson = 2):
            PosePart(Ramp, vector3{}, Art.GridKit.PCL_SM_GridRamp_asset)
            PosePart(FloorPart, vector3{Z := 384.0}, Art.GridKit.PCL_SM_GridFloor_asset)
            PosePart(Cone, vector3{Z := 384.0}, Art.GridKit.PCL_SM_GridCone_asset)
            PosePart(Wall, vector3{Y := 512.0, Z := 384.0}, Art.GridKit.PCL_SM_GridWallSolid_asset)
            PosePart(Landing, vector3{Y := 512.0, Z := 384.0}, Art.GridKit.PCL_SM_GridFloor_asset)
            if (Step >= 1 and Step <= 4):
                FloorPart.SetMesh(Art.GridKit.PCL_SM_GridFloorHalf_asset)
            if (Step >= 2 and Step <= 4):
                Cone.SetMesh(Art.TeachingKit.PCL_SM_TeachingConeRaisedLeft_asset)
            if (Step >= 3 and Step <= 4):
                Wall.SetMesh(Art.TeachingKit.PCL_SM_TeachingWallSide_asset)
            if (TargetMarker.TeleportTo[GetTransform().Translation + vector3{X := -170.0, Y := 1000.0, Z := 550.0}, IdentityRotation()]) {}
            TargetMarker.Show()
        else:
            for (Part : array{FloorPart, Cone, Ramp, Landing}, Part.IsValid[]):
                Part.Hide()
            PosePart(Wall, vector3{Y := 256.0}, Art.GridKit.PCL_SM_GridWallSolid_asset)
            if (Lesson = 0 and (Step = 1 or Step = 2 and Substep = 0)):
                Wall.SetMesh(Art.GridKit.PCL_SM_GridWallWindow_asset)
            if (TargetMarker.TeleportTo[GetTransform().Translation + vector3{Y := 850.0, Z := 180.0}, IdentityRotation()]) {}
            TargetMarker.Show()
        if (CursorMarker.TeleportTo[GetTransform().Translation + FocusLocal(), IdentityRotation()]) {}
        CursorMarker.SetMaterial(Art.PCL_MI_Cyan{})
        TargetMarker.SetMaterial(Art.PCL_MI_Amber{})
        CursorMarker.Show()
        if (Lesson = 0 and Step = 2 or Lesson = 1 and Step = 3 or Lesson = 2 and Step = 4):
            CursorMarker.Hide()

    TargetLocal()<transacts>:vector3 =
        if (Lesson = 2):
            if (Step = 1):
                return vector3{X := -170.0, Y := 130.0, Z := 197.5}
            if (Step = 2):
                return vector3{X := -170.0, Y := 330.0, Z := 347.5}
            if (Step = 3):
                return vector3{X := -170.0, Y := 600.0, Z := 484.0}
            if (Step = 4):
                return vector3{X := -170.0, Y := 800.0, Z := 484.0}
            return vector3{X := -170.0, Y := -180.0, Z := 100.0}
        if (Lesson = 1):
            if (Step = 1):
                return vector3{X := 340.0, Y := 100.0, Z := 100.0}
            if (Step = 3):
                return vector3{X := -340.0, Y := 100.0, Z := 100.0}
        else if (Step = 1 or Step = 2 and Substep = 0):
            return vector3{Y := 40.0, Z := 100.0}
        return vector3{Y := -120.0, Z := 100.0}

    StartLocal()<transacts>:vector3 =
        if (Lesson = 2):
            if (Step = 2):
                return vector3{X := -170.0, Y := 130.0, Z := 197.5}
            if (Step = 3):
                return vector3{X := -170.0, Y := 330.0, Z := 347.5}
            if (Step = 4):
                return vector3{X := -170.0, Y := 600.0, Z := 484.0}
            return vector3{X := -170.0, Y := -180.0, Z := 100.0}
        return vector3{Y := -120.0, Z := 100.0}

    FocusLocal()<transacts>:vector3 =
        if (Lesson = 2):
            if (Step = 1):
                return vector3{X := -128.0, Y := 200.0, Z := 405.0}
            if (Step = 2):
                return vector3{X := -128.0, Y := 250.0, Z := 610.0}
            if (Step = 3):
                return vector3{X := -170.0, Y := 512.0, Z := 600.0}
            return vector3{X := -170.0, Y := 1000.0, Z := 550.0}
        return vector3{Y := 850.0, Z := 180.0}

    UsesPlan()<transacts>:logic =
        if (Lesson = 2 and Step <> 4):
            return true
        return false

    WantsShot()<transacts>:logic =
        if (Lesson = 0 and Step = 2 and Substep = 0 or Lesson = 1 and Step = 3 or Lesson = 2 and Step = 4):
            return true
        return false

    IsAssigned(Agent : agent)<transacts>:logic =
        if (CurrentOwner?, Assigned := Avatar?, Assigned = Agent, not Ending?):
            return true
        return false

    WatchCommand(Ticket : int, Agent : agent, Character : fort_character, Behavior : coach_demonstrator_behavior)<suspends>:void =
        loop:
            if (Ending? or Behavior.Ending? or Ticket <> Revision or not Playing? or not IsAssigned(Agent)? or not Character.IsActive[]):
                return
            Sleep(0.03)

    DriveAvatar(Agent : agent, Character : fort_character, Actions : guard_actions_component, Behavior : coach_demonstrator_behavior)<suspends>:void =
        var LastCommand : int = -1
        var LastRate : float = -1.0
        var Effect : ?movement_modulator_device = false
        defer:
            Actions.StopNavigation()
            Behavior.Equipment.DisposeBuildPlan()
            if (Current := Effect?, Character.IsActive[]):
                Current.Deactivate(Agent)
        loop:
            if (Ending? or Behavior.Ending? or not IsAssigned(Agent)? or not Character.IsActive[]):
                return
            if (NeedsSeek? and Lesson >= 0):
                Character.ReleaseFromStasis()
                if (Character.TeleportTo[GetTransform().Translation + StartLocal(), MakeRotationFromYawPitchRollDegrees(90.0, 0.0, 0.0)]):
                    set NeedsSeek = false
                if (Body := Character.GetEntity[]):
                    if (UsesPlan()?):
                        Equipped := Behavior.Equipment.EquipBuildPlan(Agent)
                    else:
                        Equipped := Behavior.Equipment.SelectWeapon(Agent, 1500.0)
            if (not Playing? or Lesson < 0):
                Character.PutInStasis(stasis_args{AllowTurning := false, AllowFalling := false})
                Actions.StopNavigation()
            else if (LastCommand <> Revision):
                set LastCommand = Revision
                Ticket := Revision
                Character.ReleaseFromStasis()
                if (LastRate <> Speed, Index := Round[Speed * 4.0] - 1, Next := SpeedEffects[Index]):
                    if (Previous := Effect?):
                        Previous.Deactivate(Agent)
                    Next.Activate(Agent)
                    set Actions.MovementSpeedMultiplier = 1.0
                    if (Speed < 0.5):
                        set Actions.MovementSpeedMultiplier = 0.5
                    set Effect = option{Next}
                    set LastRate = Speed
                if (Body := Character.GetEntity[]):
                    var Equipped : logic = false
                    if (UsesPlan()?):
                        set Equipped = Behavior.Equipment.EquipBuildPlan(Agent)
                    else:
                        set Equipped = Behavior.Equipment.SelectWeapon(Agent, 1500.0)
                    if (Equipped?):
                        race:
                            block:
                                Goal := GetTransform().Translation + TargetLocal()
                                BeganAt := GetSimulationElapsedTime()
                                BeganPosition := Character.GetTransform().Translation
                                var Reached : logic = false
                                for (Attempt := 0..3, not Reached?):
                                    Result := Actions.NavigateTo(MakeNavigationTarget(Goal), ?MovementType := movement_type.Running, ?ReachRadius := 60.0, ?AllowPartialPath := false)
                                    if (Result.GetSuccess[], Distance(Character.GetTransform().Translation, Goal) < 160.0):
                                        set Reached = true
                                    else:
                                        Sleep(0.3)
                                if (Reached? and Ticket = Revision):
                                    Elapsed := GetSimulationElapsedTime() - BeganAt
                                    Travel := Distance(BeganPosition, Character.GetTransform().Translation)
                                    Print("PCL|lesson3d|arrived|topic={Lesson}|step={Step}|rate={Speed}|seconds={Elapsed}|travel_cm={Travel}", ?Duration := 0.0)
                                    var CanContinue : logic = true
                                    if (WantsShot()?):
                                        Requested := RequestDemonstrationShot(Agent)
                                        set CanContinue = Requested
                                    set MotionReady = CanContinue
                                else:
                                    Print("PCL|lesson3d|navigation_unconfirmed", ?Duration := 0.0)
                                loop:
                                    Sleep(0.1)
                            CoachFocusPointCompanion(Actions, GetTransform().Translation + FocusLocal())
                            WatchCommand(Ticket, Agent, Character, Behavior)
                    else:
                        Print("PCL|lesson3d|equipment_unconfirmed", ?Duration := 0.0)
                Actions.StopNavigation()
            Sleep(0.05)

    RequestDemonstrationShot(Owner : agent)<suspends>:logic =
        Key := Lesson * 100 + Step * 10 + Substep
        if (ShotKey = Key):
            return true
        for (Inventory : Owner.FindDescendantComponents(inventory_component), Item : Inventory.GetItems()):
            if (Component := Item.GetComponent[item_component], Component.IsEquipped[], Weapon := Item.GetComponent[fort_trace_weapon_component]):
                set ShotKey = Key
                Weapon.BeginFire()
                defer:
                    Weapon.EndFire()
                Print("PCL|lesson3d|native_fire_requested|hit_unconfirmed", ?Duration := 0.0)
                Sleep(0.08)
                return true
        Print("PCL|lesson3d|weapon_component_unconfirmed", ?Duration := 0.0)
        return false

coach_demonstrator_behavior := class(npc_behavior):
    var Ending : logic = false
    Equipment : coach_equipment = coach_equipment{}

    OnBegin<override>()<suspends>:void =
        if (Agent := GetAgent[], Character := Agent.GetFortCharacter[], Body := Character.GetEntity[], Actions := Body.GetComponent[guard_actions_component]):
            Character.SetVulnerability(false)
            LoadoutReady := Equipment.InitializeNPCLoadout(Agent)
            for (Attempt := 0..99):
                if (Ending?):
                    return
                if (Stations := CoachDemoStations[GetSession()]):
                    for (Station : Stations, Assigned := Station.Avatar?, Assigned = Agent):
                        Station.DriveAvatar(Agent, Character, Actions, Self)
                        return
                Sleep(0.1)
            Print("PCL|lesson3d|station_binding_unconfirmed", ?Duration := 0.0)

    OnEnd<override>():void =
        set Ending = true
        Equipment.DisposeBuildPlan()
        LoadoutRemoved := Equipment.DisposeLoadout()
