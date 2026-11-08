using { /Fortnite.com/Devices }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Playspaces }
using { /Fortnite.com/Teams }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/SpatialMath }

# One explicitly authorized, isolated physics comparison. Never enables product gates.
coach_core_trial160_device := class(creative_device):
    @editable
    Enabled : logic = false
    @editable
    Structures : coach_structure_device = coach_structure_device{}
    @editable
    ControlBlast : explosive_device = explosive_device{}
    @editable
    EditedBlast : explosive_device = explosive_device{}
    var Props : []creative_prop = array{}
    var Ending : logic = false
    Geometry : coach_geometry_query = coach_geometry_query{}

    OnBegin<override>()<suspends>:void =
        if (not Enabled?):
            return
        if (Structures.CandidateCombatEnabled? or Structures.QueryCoverageConfirmed? or Structures.HealthContinuityConfirmed? or Structures.NativeSlotInteroperationConfirmed?):
            Print("PCL|core160|not_run|product_gates_not_clear")
            return
        Print("PCL|core160|begin|one_sequence|no_player_input|product_gates_false")
        race:
            RunSequence()
            block:
                Sleep(45.0)
                Print("PCL|core160|deadline|sequence_incomplete")
        Cleanup()
        Print("PCL|core160|finished|props_removed|native_owner_slot_edit_and_pro_quality_unmeasured")

    OnEnd<override>():void =
        set Ending = true
        Cleanup()

    Cleanup():void =
        for (Prop : Props, Prop.IsValid[]):
            Prop.Dispose()
        set Props = array{}

    Spawn(Kind : coach_piece_kind, Position : vector3):?creative_prop =
        Pose := Structures.GridTransform(Kind, Position, 0.0)
        Result := SpawnProp(Structures.AssetFor(Kind), Pose.Translation, Pose.Rotation)
        if (Prop := Result(0)?, Result(1) = spawn_prop_result.Ok, Prop.IsValid[]):
            set Props += array{Prop}
            return option{Prop}
        Print("PCL|core160|spawn_not_applied")
        return false

    Sample(Root : entity, Kind : coach_piece_kind, Position : vector3)<transacts>:int =
        if (Kind = coach_piece_kind.Wall):
            return Geometry.SampleWall(Root, Position, 0.0).Occupied
        var Count : int = 0
        for (X : array{-170.0, 0.0, 170.0}, Y : array{-170.0, 0.0, 170.0}):
            Start := Position + vector3{X := X, Y := Y, Z := 450.0}
            if (Geometry.SegmentOccupied(Root, Start, Start - vector3{Z := 490.0})?):
                set Count += 1
        return Count

    ShapeCase(Root : entity, Kind : coach_piece_kind, Index : int, Shape : coach_piece_shape)<suspends>:logic =
        Position := vector3{X := Index * 1024.0 - 1536.0, Y := 768.0, Z := 2048.0}
        Empty := Sample(Root, Kind, Position)
        if (Empty <> 0):
            Print("PCL|core160|shape_not_run|case={Index}|baseline={Empty}")
            return false
        Candidate := Spawn(Kind, Position)
        if (Prop := Candidate?, Solid := Structures.ShapeMesh(Kind, coach_piece_shape.Solid)?, Edited := Structures.ShapeMesh(Kind, Shape)?):
            Sleep(0.3)
            Before := Sample(Root, Kind, Position)
            Prop.SetMesh(Edited)
            Sleep(0.3)
            Partial := Sample(Root, Kind, Position)
            Prop.SetMesh(Solid)
            Sleep(0.3)
            After := Sample(Root, Kind, Position)
            Print("PCL|core160|shape|case={Index}|empty={Empty}|solid={Before}|edited={Partial}|reset={After}|same_creative_prop_reference")
            Prop.Dispose()
            Sleep(0.15)
            Gone := Sample(Root, Kind, Position)
            Print("PCL|core160|shape_cleanup|case={Index}|cells={Gone}")
            return logic{Before = 9 and Partial < Before and After = Before and Gone = 0}
        return false

    RunSequence()<suspends>:void =
        if (Root := GetSimulationEntity[]):
            for (Index -> Kind : array{coach_piece_kind.Wall, coach_piece_kind.FloorPiece, coach_piece_kind.Ramp, coach_piece_kind.Cone}):
                var Shape : coach_piece_shape = coach_piece_shape.Window
                if (Kind = coach_piece_kind.FloorPiece):
                    set Shape = coach_piece_shape.FloorHalf
                else if (Kind = coach_piece_kind.Ramp):
                    set Shape = coach_piece_shape.RampHalf
                else if (Kind = coach_piece_kind.Cone):
                    set Shape = coach_piece_shape.ConeRaised
                Applied := ShapeCase(Root, Kind, Index, Shape)
                if (not Applied?):
                    Print("PCL|core160|stopped|shape_condition_not_met|case={Index}")
                    return
            var Instigator : ?agent = false
            var Attempt : int = 0
            loop:
                if (Ending? or Attempt >= 50):
                    return
                for (Player : GetPlayspace().GetPlayers(), Body := Player.GetFortCharacter[], Body.IsActive[]):
                    set Instigator = option{Player}
                if (Instigator?):
                    break
                Sleep(0.2)
                set Attempt += 1
            if (Source := Instigator?):
                Teams := GetPlayspace().GetTeamCollection()
                if (FirstTeam := Teams.GetTeams()[0], Teams.IsOnTeam[Source, FirstTeam]):
                    Print("PCL|core160|damage_instigator|native_team_one|no_team_change")
                else:
                    Print("PCL|core160|damage_not_run|instigator_team_not_one")
                    return
                ControlPosition := vector3{X := -1024.0, Y := -1536.0, Z := 2048.0}
                EditedPosition := vector3{X := 1024.0, Y := -1536.0, Z := 2048.0}
                ControlCandidate := Spawn(coach_piece_kind.Wall, ControlPosition)
                EditedCandidate := Spawn(coach_piece_kind.Wall, EditedPosition)
                if (Control := ControlCandidate?, Subject := EditedCandidate?):
                    Sleep(0.3)
                    ControlBlast.Explode(Source)
                    EditedBlast.Explode(Source)
                    Sleep(0.25)
                    if (not Control.IsValid[] or not Subject.IsValid[]):
                        Print("PCL|core160|damage_inconclusive|initial_pulse_not_partial")
                        return
                    Subject.SetMesh(Structures.WallWindowMesh)
                    Sleep(0.2)
                    Window := Geometry.SampleWall(Root, EditedPosition, 0.0).Occupied
                    Subject.SetMesh(Structures.WallSolidMesh)
                    Sleep(0.2)
                    Reset := Geometry.SampleWall(Root, EditedPosition, 0.0).Occupied
                    Print("PCL|core160|damaged_transition|window={Window}|reset={Reset}|no_health_write")
                    var ControlEnd : int = 0
                    var SubjectEnd : int = 0
                    var Pulse : int = 2
                    loop:
                        if (Ending? or Pulse > 12):
                            break
                        Sleep(1.15)
                        ControlBlast.Reset()
                        EditedBlast.Reset()
                        ControlBlast.Explode(Source)
                        EditedBlast.Explode(Source)
                        Sleep(0.15)
                        if (ControlEnd = 0 and not Control.IsValid[]):
                            set ControlEnd = Pulse
                        if (SubjectEnd = 0 and not Subject.IsValid[]):
                            set SubjectEnd = Pulse
                        Print("PCL|core160|damage_pulse|pulse={Pulse}|control_end={ControlEnd}|edited_end={SubjectEnd}")
                        if (ControlEnd > 0 and SubjectEnd > 0):
                            break
                        set Pulse += 1
                    Print("PCL|core160|damage_result|control_end={ControlEnd}|edited_end={SubjectEnd}|matched_native_explosions|no_numeric_hp_or_owner_read")
                    return
            Print("PCL|core160|damage_not_run|instigator_or_assets_unavailable")
