using { /UnrealEngine.com/Temporary/SpatialMath }

coach_build_step_kind := enum:
    Move
    Place
    Edit

coach_build_step := struct:
    Operation : coach_build_step_kind
    Position : vector3
    Slot : int = 0
    Kind : coach_piece_kind = coach_piece_kind.Wall
    Shape : coach_piece_shape = coach_piece_shape.Solid
    Yaw : float = 0.0
    MustBeSolid : logic = false
    Timeout : float = 2.2

CoachBuildCell(Position : vector3)<transacts>:?vector3 =
    if (CellX := Round[Position.X / 512.0], CellY := Round[Position.Y / 512.0], Level := Floor[Position.Z / 384.0]):
        return option{vector3{X := CellX * 512.0, Y := CellY * 512.0, Z := Level * 384.0}}
    return false

CoachBuildForward(Delta : vector3)<transacts>:tuple(vector3, float) =
    if (Abs(Delta.Y) > Abs(Delta.X)):
        if (Delta.Y < 0.0):
            return (vector3{Y := -1.0}, -90.0)
        return (vector3{Y := 1.0}, 90.0)
    if (Delta.X < 0.0):
        return (vector3{X := -1.0}, 180.0)
    return (vector3{X := 1.0}, 0.0)

CoachAscentPlan(Position : vector3, ObservedThreat : vector3)<transacts>:[]coach_build_step =
    if (Cell := CoachBuildCell(Position)?):
        Facing := CoachBuildForward(ObservedThreat - Position)
        # The next cell keeps the approach point on the current platform.
        return CoachProtectedAscent(Cell + Facing(0) * 512.0, Facing(0), Facing(1))
    return array{}

CoachBoxPlan(Position : vector3, ObservedThreat : vector3)<transacts>:[]coach_build_step =
    if (Cell := CoachBuildCell(Position)?):
        Facing := CoachBuildForward(ObservedThreat - Cell)
        Forward := Facing(0)
        Right := vector3{X := -Forward.Y, Y := Forward.X}
        # Settle inside the cell before enclosing it. The executor must confirm
        # arrival and keep the body inside throughout every following action.
        var Steps : []coach_build_step = array{coach_build_step{Operation := coach_build_step_kind.Move, Position := Cell + vector3{Z := 100.0}}}
        for (Slot -> Location : array{Cell + Forward * 256.0, Cell - Right * 256.0, Cell + Right * 256.0, Cell - Forward * 256.0}):
            var Yaw : float = 0.0
            if (Abs(Location.Y - Cell.Y) > 128.0):
                set Yaw = 90.0
            set Steps += array{coach_build_step{Operation := coach_build_step_kind.Place, Slot := Slot, Position := Location, Kind := coach_piece_kind.Wall, Yaw := Yaw, MustBeSolid := true}}
        return Steps + array{coach_build_step{Operation := coach_build_step_kind.Place, Slot := 4, Position := Cell + vector3{Z := 384.0}, Kind := coach_piece_kind.Cone, MustBeSolid := true}}
    return array{}

CoachBoxContainsBody(Cell : vector3, Position : vector3)<transacts>:logic =
    if (Abs(Position.X - Cell.X) < 160.0 and Abs(Position.Y - Cell.Y) < 160.0 and Position.Z - Cell.Z > 30.0 and Position.Z - Cell.Z < 190.0):
        return true
    return false

coach_skill_piece := class:
    Piece : coach_live_piece
    var ExpectedRevision : int = 0

coach_build_skill_state := class:
    Generation : int
    Encounter : int
    StartedAt : float
    ThreatAnchor : vector3 = vector3{}
    var Pieces : [int]coach_skill_piece = map{}
    var InteriorCell : ?vector3 = false

# Short-lived execution memory, separate from damage-based tactic learning.
# A failed local route does not disable the skill in a different situation.
coach_build_retry_state := class:
    var Generation : int = -1
    var Encounter : int = -1
    var FailedAt : float = -100.0
    var Failures : int = 0
    var BuilderPosition : vector3 = vector3{}
    var ObservedThreat : vector3 = vector3{}

    SameSituation(Ticket : int, StructureEncounter : int, Body : vector3, Threat : vector3)<transacts>:logic =
        if (Failures > 0 and Generation = Ticket and Encounter = StructureEncounter and Distance(Body, BuilderPosition) < 384.0 and Distance(Threat, ObservedThreat) < 512.0):
            return true
        return false

    Ready(Ticket : int, StructureEncounter : int, Body : vector3, Threat : vector3, At : float)<transacts>:logic =
        if (not SameSituation(Ticket, StructureEncounter, Body, Threat)?):
            return true
        if (At - FailedAt >= Min(6.0, Failures * 1.5)):
            return true
        return false

    RecordFailure(Ticket : int, StructureEncounter : int, Body : vector3, Threat : vector3, At : float):void =
        if (not SameSituation(Ticket, StructureEncounter, Body, Threat)?):
            set Failures = 0
        set Failures = Min(4, Failures + 1)
        set Generation = Ticket
        set Encounter = StructureEncounter
        set BuilderPosition = Body
        set ObservedThreat = Threat
        set FailedAt = At

    Clear():void =
        set Failures = 0
        set FailedAt = -100.0

# The owned GridKit window spans local tangent +/-85.33 cm and Z128..256.
# Solve the viewing ray at its wall plane, then leave a margin from the jambs.
# This plans a pose; native navigation, visibility and weapon collision still
# decide whether movement and firing can actually succeed.
CoachWindowSightFits(Wall : vector3, WallYaw : float, View : vector3, ObservedThreat : vector3)<transacts>:logic =
    Axis := MakeRotationFromYawPitchRollDegrees(WallYaw, 0.0, 0.0).RotateVector(vector3{X := 1.0})
    var Side : float = 1.0
    if (DotProduct(View - Wall, Axis) < 0.0):
        set Side = -1.0
    Normal := Axis * Side
    Tangent := vector3{X := -Normal.Y, Y := Normal.X}
    Depth := DotProduct(View - Wall, Normal)
    ThreatDepth := DotProduct(ObservedThreat - Wall, Normal)
    if (Depth < 60.0 or ThreatDepth >= -120.0):
        return false
    Fraction := Depth / (Depth - ThreatDepth)
    AtWindow := View + (ObservedThreat - View) * Fraction
    if (Abs(DotProduct(AtWindow - Wall, Tangent)) > 65.0 or AtWindow.Z < Wall.Z + 143.0 or AtWindow.Z > Wall.Z + 241.0):
        return false
    return true

CoachWindowPeekPose(Wall : vector3, WallYaw : float, Body : vector3, View : vector3, ObservedThreat : vector3)<transacts>:?vector3 =
    Axis := MakeRotationFromYawPitchRollDegrees(WallYaw, 0.0, 0.0).RotateVector(vector3{X := 1.0})
    var Side : float = 1.0
    if (DotProduct(Body - Wall, Axis) < 0.0):
        set Side = -1.0
    Normal := Axis * Side
    Tangent := vector3{X := -Normal.Y, Y := Normal.X}
    ThreatDepth := DotProduct(ObservedThreat - Wall, Normal)
    if (ThreatDepth >= -120.0 or Abs(Body.Z - Wall.Z - 100.0) > 110.0):
        return false
    StandOff := 180.0
    EyeOffset := View - Body
    Along := (StandOff + DotProduct(EyeOffset, Normal)) * DotProduct(ObservedThreat - Wall, Tangent) / ThreatDepth - DotProduct(EyeOffset, Tangent)
    if (Abs(Along) > 170.0):
        return false
    Pose := Wall + Normal * StandOff + Tangent * Along + vector3{Z := Body.Z - Wall.Z}
    if (not CoachWindowSightFits(Wall, WallYaw, Pose + EyeOffset, ObservedThreat)?):
        return false
    return option{Pose}

# Positions share the authored kit pivots. Execution must still establish
# physical passage, native slot/owner behavior and expert quality in final acceptance.
CoachProtectedAscent(Cell : vector3, Forward : vector3, Yaw : float)<transacts>:[]coach_build_step =
    Side := vector3{X := -Forward.Y, Y := Forward.X}
    Passage := Side * 170.0
    Ceiling := Cell + vector3{Z := 384.0}
    Landing := Ceiling + Forward * 512.0
    return array{
        coach_build_step{Operation := coach_build_step_kind.Move, Position := Cell - Forward * 340.0 + Passage + vector3{Z := 100.0}},
        coach_build_step{Operation := coach_build_step_kind.Place, Slot := 5, Kind := coach_piece_kind.Wall, Position := Cell - Side * 256.0, Yaw := Yaw + 90.0, MustBeSolid := true},
        coach_build_step{Operation := coach_build_step_kind.Place, Slot := 1, Kind := coach_piece_kind.FloorPiece, Position := Ceiling, Yaw := Yaw - 90.0},
        coach_build_step{Operation := coach_build_step_kind.Place, Slot := 3, Kind := coach_piece_kind.Wall, Position := Ceiling + Forward * 256.0, Yaw := Yaw + 180.0},
        coach_build_step{Operation := coach_build_step_kind.Place, Slot := 2, Kind := coach_piece_kind.Cone, Position := Ceiling, Yaw := Yaw - 90.0},
        coach_build_step{Operation := coach_build_step_kind.Edit, Slot := 1, Position := Ceiling, Shape := coach_piece_shape.FloorHalf},
        coach_build_step{Operation := coach_build_step_kind.Edit, Slot := 2, Position := Ceiling, Shape := coach_piece_shape.ConeRaised},
        coach_build_step{Operation := coach_build_step_kind.Edit, Slot := 3, Position := Ceiling + Forward * 256.0, Shape := coach_piece_shape.SidePassage},
        coach_build_step{Operation := coach_build_step_kind.Place, Slot := 0, Kind := coach_piece_kind.Ramp, Position := Cell, Yaw := Yaw, MustBeSolid := true},
        coach_build_step{Operation := coach_build_step_kind.Move, Position := Cell - Forward * 110.0 + Passage + vector3{Z := 209.5}},
        coach_build_step{Operation := coach_build_step_kind.Place, Slot := 4, Kind := coach_piece_kind.FloorPiece, Position := Landing, Yaw := Yaw - 90.0, MustBeSolid := true},
        coach_build_step{Operation := coach_build_step_kind.Move, Position := Cell + Forward * 120.0 + Passage + vector3{Z := 382.0}},
        coach_build_step{Operation := coach_build_step_kind.Move, Position := Cell + Forward * 420.0 + Passage + vector3{Z := 484.0}}
    }
