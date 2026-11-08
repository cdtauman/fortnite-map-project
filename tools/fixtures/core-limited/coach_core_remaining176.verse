using { /Fortnite.com/Devices }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Playspaces }
using { /Fortnite.com/Teams }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/SpatialMath }

# Dormant preparation for authorized mechanism acceptance. Never enables product gates.
coach_core_remaining176_device := class(creative_device):
    @editable
    Enabled : logic = false
    @editable
    Structures : coach_structure_device = coach_structure_device{}
    @editable
    ControlBlast : explosive_device = explosive_device{}
    @editable
    EditedBlast : explosive_device = explosive_device{}
    @editable
    Origin : vector3 = vector3{X := 12288.0, Y := 12288.0, Z := 4096.0}
    var Props : []creative_prop = array{}
    var Ending : logic = false
    Geometry : coach_geometry_query = coach_geometry_query{}

    OnBegin<override>()<suspends>:void =
        if (not Enabled?):
            return
        if (Structures.CandidateCombatEnabled? or Structures.QueryCoverageConfirmed? or Structures.HealthContinuityConfirmed? or Structures.NativeSlotInteroperationConfirmed?):
            Print("PCL|core176|not_run|product_gates_not_clear")
            return
        Print("PCL|core176|begin|one_sequence|no_player_input|product_gates_false")
        race:
            RunSequence()
            block:
                Sleep(60.0)
                Print("PCL|core176|deadline|sequence_incomplete")
        Cleanup()
        Print("PCL|core176|finished|props_removed|native_owner_slot_edit_and_pro_quality_unmeasured")

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
        Print("PCL|core176|spawn_not_applied")
        return false

    Sample(Root : entity, Kind : coach_piece_kind, Position : vector3)<transacts>:int =
        if (Kind = coach_piece_kind.Wall):
            return Geometry.SampleWall(Root, Position, 0.0).Occupied
        var Count : int = 0
        for (X : array{-170.0, 0.0, 170.0}, Y : array{-170.0, 0.0, 170.0}):
            Start := Position + vector3{X := X, Y := Y, Z := 450.0}
            if (Geometry.SegmentOccupied(Root, Start, Start - vector3{Z := 490.0})?):
                set Count += 1
        if (Kind = coach_piece_kind.Cone):
            # Both roofs cover the same footprint. Horizontal cuts above the
            # solid cone's apex distinguish a raised roof without expecting a hole.
            for (Y : array{-170.0, 0.0, 170.0}):
                Start := Position + vector3{X := -300.0, Y := Y, Z := 256.0}
                if (Geometry.SegmentOccupied(Root, Start, Start + vector3{X := 600.0})?):
                    set Count += 1
        return Count

    ShapeCase(Root : entity, Kind : coach_piece_kind, Index : int, Shape : coach_piece_shape)<suspends>:logic =
        Position := Origin + vector3{X := Index * 1024.0 - 1536.0, Y := 768.0}
        Empty := Sample(Root, Kind, Position)
        if (Empty <> 0):
            Print("PCL|core176|shape_not_run|case={Index}|baseline={Empty}")
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
            Print("PCL|core176|shape|case={Index}|empty={Empty}|solid={Before}|edited={Partial}|reset={After}|same_creative_prop_reference")
            Prop.Dispose()
            Sleep(0.15)
            Gone := Sample(Root, Kind, Position)
            Print("PCL|core176|shape_cleanup|case={Index}|cells={Gone}")
            var ShapeChanged : logic = logic{Partial < Before}
            if (Kind = coach_piece_kind.Cone):
                set ShapeChanged = logic{Partial > Before}
            return logic{Before = 9 and ShapeChanged? and After = Before and Gone = 0}
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
                    Print("PCL|core176|shape_inconclusive_or_failed|case={Index}|other_cases_continue")
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
                    Print("PCL|core176|damage_instigator|native_team_one|no_team_change")
                else:
                    Print("PCL|core176|damage_not_run|instigator_team_not_one")
                    return
                ControlPosition := Origin + vector3{X := -1024.0, Y := -1536.0}
                EditedPosition := Origin + vector3{X := 1024.0, Y := -1536.0}
                ControlEmpty := Sample(Root, coach_piece_kind.Wall, ControlPosition)
                EditedEmpty := Sample(Root, coach_piece_kind.Wall, EditedPosition)
                if (ControlEmpty <> 0 or EditedEmpty <> 0):
                    Print("PCL|core176|damage_not_run|baseline_control={ControlEmpty}|baseline_edited={EditedEmpty}")
                    return
                if (Distance(ControlBlast.GetTransform().Translation, ControlPosition + vector3{Z := 128.0}) > 25.0 or Distance(EditedBlast.GetTransform().Translation, EditedPosition + vector3{Z := 128.0}) > 25.0):
                    Print("PCL|core176|damage_not_run|blast_positions_not_authored")
                    return
                ControlCandidate := Spawn(coach_piece_kind.Wall, ControlPosition)
                EditedCandidate := Spawn(coach_piece_kind.Wall, EditedPosition)
                if (Control := ControlCandidate?, Subject := EditedCandidate?):
                    Sleep(0.3)
                    ControlBlast.Explode(Source)
                    EditedBlast.Explode(Source)
                    Sleep(0.25)
                    if (not Control.IsValid[] or not Subject.IsValid[]):
                        Print("PCL|core176|damage_inconclusive|initial_pulse_destroyed_a_subject")
                        return
                    Subject.SetMesh(Structures.WallWindowMesh)
                    Sleep(0.2)
                    Window := Geometry.SampleWall(Root, EditedPosition, 0.0).Occupied
                    Subject.SetMesh(Structures.WallSolidMesh)
                    Sleep(0.2)
                    Reset := Geometry.SampleWall(Root, EditedPosition, 0.0).Occupied
                    Print("PCL|core176|damaged_transition|window={Window}|reset={Reset}|no_health_write")
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
                        Print("PCL|core176|damage_pulse|pulse={Pulse}|control_end={ControlEnd}|edited_end={SubjectEnd}")
                        if (ControlEnd > 0 and SubjectEnd > 0):
                            break
                        set Pulse += 1
                    Print("PCL|core176|damage_result|control_end={ControlEnd}|edited_end={SubjectEnd}|matched_native_explosions|no_numeric_hp_or_owner_read")
                    if (ControlEnd > 1 and SubjectEnd = ControlEnd):
                        Print("PCL|core176|damage_endpoint_match|quantized_comparison_only|no_product_gate_change")
                    else:
                        Print("PCL|core176|damage_endpoint_unmatched_or_inconclusive|no_product_gate_change")
                    return
            Print("PCL|core176|damage_not_run|instigator_or_assets_unavailable")
