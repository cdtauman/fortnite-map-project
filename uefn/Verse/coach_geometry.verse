using { /Verse.org/SceneGraph }
using { /UnrealEngine.com/Temporary/SpatialMath }

CoachStructureInteraction(Channel : collision_channel)<computes>:collision_interaction =
    if (CollisionChannels.avatar[Channel] or CollisionChannels.camera[Channel]):
        return collision_interaction.Ignore
    return collision_interaction.Overlap

coach_wall_sample := struct:
    Cells : []logic = array{}
    Occupied : int = 0

# Nine physical query samples, not native edit input or an ownership event.
coach_geometry_query := class:
    SegmentOccupied(Root : entity, Start : vector3, Finish : vector3)<transacts>:logic =
        Sphere := collision_sphere{Radius := 2.0, CollisionProfile := collision_profile{Channel := CollisionChannels.dynamic{}, GetChannelInteraction := CoachStructureInteraction}}
        for (Hit : Root.FindSweepHits(FromVector3(Finish - Start), FromTransform(transform{Translation := Start}), Sphere)):
            return true
        return false

    SampleWall(Root : entity, Position : vector3, Yaw : float)<transacts>:coach_wall_sample =
        Sphere := collision_sphere{
            Radius := 2.0,
            CollisionProfile := collision_profile{Channel := CollisionChannels.dynamic{}, GetChannelInteraction := CoachStructureInteraction}
        }
        Rotation := MakeRotationFromYawPitchRollDegrees(Yaw, 0.0, 0.0)
        var Cells : []logic = array{}
        var Count : int = 0
        for (Row := 0..2, Column := 0..2):
            Local := vector3{X := -32.0, Y := -170.0 + Column * 170.0, Z := 64.0 + Row * 128.0}
            Start := transform{Translation := Position + Rotation.RotateVector(Local)}
            Delta := Rotation.RotateVector(vector3{X := 64.0})
            var Occupied : logic = false
            for (Hit : Root.FindSweepHits(FromVector3(Delta), FromTransform(Start), Sphere)):
                set Occupied = true
            set Cells += array{Occupied}
            if (Occupied?):
                set Count += 1
        return coach_wall_sample{Cells := Cells, Occupied := Count}

    # Match the authored wall cells, including the opening, rather than only
    # counting hits. Other geometry filling the opening must reject the route.
    WallMatchesShape(Root : entity, Position : vector3, Yaw : float, Shape : coach_piece_shape)<transacts>:logic =
        if (Shape <> coach_piece_shape.Solid and Shape <> coach_piece_shape.Window and Shape <> coach_piece_shape.Door and Shape <> coach_piece_shape.SidePassage):
            return false
        Sample := SampleWall(Root, Position, Yaw)
        if (Sample.Cells.Length <> 9):
            return false
        for (Index -> Occupied : Sample.Cells):
            var Expected : logic = true
            if (Shape = coach_piece_shape.Window and Index = 4):
                set Expected = false
            else if (Shape = coach_piece_shape.Door and (Index = 1 or Index = 4)):
                set Expected = false
            else if (Shape = coach_piece_shape.SidePassage and (Index = 0 or Index = 3 or Index = 6)):
                set Expected = false
            if (Occupied <> Expected):
                return false
        return true
