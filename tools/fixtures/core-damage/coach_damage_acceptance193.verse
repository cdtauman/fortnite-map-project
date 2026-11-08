using { /Fortnite.com/Devices }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Playspaces }
using { /Fortnite.com/Teams }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/SpatialMath }

# Dormant acceptance specimen. No actor is placed by compiling this source.
coach_damage_acceptance193_device := class(creative_device):
    @editable
    Enabled : logic = false
    @editable
    Structures : coach_structure_device = coach_structure_device{}
    @editable
    ControlBlast : explosive_device = explosive_device{}
    @editable
    SubjectBlast : explosive_device = explosive_device{}
    @editable
    Origin : vector3 = vector3{X := 12288.0, Y := 12288.0, Z := 4096.0}
    var Props : []creative_prop = array{}
    var Listeners : []cancelable = array{}
    var Source : ?agent = false
    var ControlAcks : int = 0
    var SubjectAcks : int = 0
    var Ending : logic = false
    Geometry : coach_geometry_query = coach_geometry_query{}

    OnBegin<override>()<suspends>:void =
        if (not Enabled?):
            return
        if (Structures.CandidateCombatEnabled? or Structures.QueryCoverageConfirmed? or Structures.HealthContinuityConfirmed? or Structures.NativeSlotInteroperationConfirmed?):
            Print("PCL|damage193|not_run|production_gates_not_clear")
            return
        set Listeners = array{ControlBlast.ExplodedEvent.Subscribe(OnControlBlast), SubjectBlast.ExplodedEvent.Subscribe(OnSubjectBlast)}
        Print("PCL|damage193|begin|one_sequence|positive_control_required|no_player_input")
        race:
            RunSequence()
            block:
                Sleep(60.0)
                Print("PCL|damage193|inconclusive|deadline")
        Cleanup()
        Print("PCL|damage193|finished|props_removed|no_product_gate_change")

    OnEnd<override>():void =
        set Ending = true
        Cleanup()

    Cleanup():void =
        for (Listener : Listeners):
            Listener.Cancel()
        set Listeners = array{}
        for (Prop : Props, Prop.IsValid[]):
            Prop.Dispose()
        set Props = array{}

    OnControlBlast(Instigator : agent):void =
        if (Expected := Source?, Instigator = Expected):
            set ControlAcks += 1

    OnSubjectBlast(Instigator : agent):void =
        if (Expected := Source?, Instigator = Expected):
            set SubjectAcks += 1

    AwaitAcks(ControlBefore : int, SubjectBefore : int, Pair : logic)<suspends>:logic =
        for (Attempt := 0..10):
            if (Ending?):
                return false
            if (ControlAcks > ControlBefore + 1 or Pair? and SubjectAcks > SubjectBefore + 1):
                return false
            if (ControlAcks = ControlBefore + 1 and (not Pair? or SubjectAcks = SubjectBefore + 1)):
                return true
            Sleep(0.05)
        return false

    SpawnWall(Position : vector3):?creative_prop =
        Pose := Structures.GridTransform(coach_piece_kind.Wall, Position, 0.0)
        Result := SpawnProp(Structures.WallAsset, Pose.Translation, Pose.Rotation)
        if (Prop := Result(0)?, Result(1) = spawn_prop_result.Ok, CoachCombatPropMatchesPose(Prop, Pose)?):
            set Props += array{Prop}
            set Prop.CanBeDamaged = true
            if (Prop.CanBeDamaged?):
                return option{Prop}
        else if (Prop := Result(0)?, Prop.IsValid[]):
            set Props += array{Prop}
        Print("PCL|damage193|not_run|spawn_or_instance_policy_rejected")
        return false

    PositiveControl(Root : entity, Position : vector3, Instigator : agent)<suspends>:logic =
        Candidate := SpawnWall(Position)
        if (Prop := Candidate?):
            Sleep(0.3)
            if (Geometry.SampleWall(Root, Position, 0.0).Occupied <> 9):
                Print("PCL|damage193|not_run|positive_control_geometry")
                return false
            for (Pulse := 1..12):
                Sleep(1.15)
                ControlBlast.Reset()
                Before := ControlAcks
                ControlBlast.Explode(Instigator)
                Acknowledged := AwaitAcks(Before, SubjectAcks, false)
                if (not Acknowledged?):
                    Print("PCL|damage193|inconclusive|positive_control_missing_ack|pulse={Pulse}")
                    return false
                Sleep(0.2)
                if (not Prop.IsValid[]):
                    Empty := Geometry.SampleWall(Root, Position, 0.0).Occupied
                    Print("PCL|damage193|positive_control_destroyed|pulse={Pulse}|remaining_cells={Empty}")
                    return logic{Empty = 0}
            Print("PCL|damage193|inconclusive|positive_control_not_destroyed|comparison_not_run")
        return false

    Compare(Root : entity, ControlPosition : vector3, SubjectPosition : vector3, Instigator : agent)<suspends>:void =
        ControlCandidate := SpawnWall(ControlPosition)
        SubjectCandidate := SpawnWall(SubjectPosition)
        if (Control := ControlCandidate?, Subject := SubjectCandidate?):
            Sleep(0.3)
            if (Geometry.SampleWall(Root, ControlPosition, 0.0).Occupied <> 9 or Geometry.SampleWall(Root, SubjectPosition, 0.0).Occupied <> 9):
                Print("PCL|damage193|inconclusive|comparison_initial_geometry")
                return
            var ControlEnd : int = 0
            var SubjectEnd : int = 0
            for (Pulse := 1..12):
                Sleep(1.15)
                ControlBlast.Reset()
                SubjectBlast.Reset()
                ControlBefore := ControlAcks
                SubjectBefore := SubjectAcks
                ControlBlast.Explode(Instigator)
                SubjectBlast.Explode(Instigator)
                Acknowledged := AwaitAcks(ControlBefore, SubjectBefore, true)
                if (not Acknowledged?):
                    Print("PCL|damage193|inconclusive|comparison_missing_ack|pulse={Pulse}")
                    return
                Sleep(0.2)
                if (ControlEnd = 0 and not Control.IsValid[]):
                    set ControlEnd = Pulse
                if (SubjectEnd = 0 and not Subject.IsValid[]):
                    set SubjectEnd = Pulse
                if (Pulse = 1):
                    if (ControlEnd > 0 or SubjectEnd > 0):
                        Print("PCL|damage193|inconclusive|no_partial_damage_interval")
                        return
                    Subject.SetMesh(Structures.WallWindowMesh)
                    Sleep(0.2)
                    WindowCells := Geometry.SampleWall(Root, SubjectPosition, 0.0).Occupied
                    Subject.SetMesh(Structures.WallSolidMesh)
                    Sleep(0.2)
                    ResetCells := Geometry.SampleWall(Root, SubjectPosition, 0.0).Occupied
                    if (WindowCells <> 8 or ResetCells <> 9):
                        Print("PCL|damage193|inconclusive|transition_geometry|window={WindowCells}|reset={ResetCells}")
                        return
                Print("PCL|damage193|pulse|pulse={Pulse}|control_end={ControlEnd}|subject_end={SubjectEnd}")
                if (ControlEnd > 0 and SubjectEnd > 0):
                    ControlCells := Geometry.SampleWall(Root, ControlPosition, 0.0).Occupied
                    SubjectCells := Geometry.SampleWall(Root, SubjectPosition, 0.0).Occupied
                    Print("PCL|damage193|result|control_end={ControlEnd}|subject_end={SubjectEnd}|control_cells={ControlCells}|subject_cells={SubjectCells}|quantized_only|no_numeric_hp_owner_or_slot_proof")
                    return
            Print("PCL|damage193|inconclusive|comparison_not_destroyed")

    RunSequence()<suspends>:void =
        if (Root := GetSimulationEntity[]):
            var Instigator : ?agent = false
            for (Attempt := 0..49):
                if (not Instigator?):
                    for (Player : GetPlayspace().GetPlayers(), Body := Player.GetFortCharacter[], Body.IsActive[]):
                        set Instigator = option{Player}
                    if (not Instigator?):
                        Sleep(0.2)
            if (Agent := Instigator?):
                Teams := GetPlayspace().GetTeamCollection()
                if (FirstTeam := Teams.GetTeams()[0], Teams.IsOnTeam[Agent, FirstTeam]):
                    set Source = option{Agent}
                else:
                    Print("PCL|damage193|not_run|instigator_team_not_one")
                    return
                ControlPosition := Origin + vector3{X := -1024.0, Y := -1536.0}
                SubjectPosition := Origin + vector3{X := 1024.0, Y := -1536.0}
                if (Geometry.SampleWall(Root, ControlPosition, 0.0).Occupied <> 0 or Geometry.SampleWall(Root, SubjectPosition, 0.0).Occupied <> 0):
                    Print("PCL|damage193|not_run|baseline_occupied")
                    return
                if (Distance(ControlBlast.GetTransform().Translation, ControlPosition + vector3{Z := 128.0}) > 25.0 or Distance(SubjectBlast.GetTransform().Translation, SubjectPosition + vector3{Z := 128.0}) > 25.0):
                    Print("PCL|damage193|not_run|blast_positions_not_authored")
                    return
                Ready := PositiveControl(Root, ControlPosition, Agent)
                if (Ready?):
                    Compare(Root, ControlPosition, SubjectPosition, Agent)
                return
        Print("PCL|damage193|not_run|simulation_or_instigator_missing")
