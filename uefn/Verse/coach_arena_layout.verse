using { /UnrealEngine.com/Temporary/SpatialMath }

# Coordinates are maintained in arena-layout.json, in Unreal XYZ centimeters.
CoachArenaCenter(Mode : coach_mode)<computes>:vector3 =
    if (Mode = coach_mode.Personal):
        return vector3{X := 0.0, Y := 0.0, Z := 0.0}
    if (Mode = coach_mode.Duel):
        return vector3{X := 0.0, Y := 45056.0, Z := 0.0}
    if (Mode = coach_mode.FreeBuild):
        return vector3{X := 45056.0, Y := 0.0, Z := 0.0}
    if (Mode = coach_mode.EditTraining):
        return vector3{X := -45056.0, Y := 0.0, Z := 0.0}
    return vector3{X := 0.0, Y := -7000.0, Z := 0.0}

CoachPlayerStart(Mode : coach_mode)<computes>:vector3 =
    Center := CoachArenaCenter(Mode)
    if (Mode = coach_mode.Personal):
        return Center + vector3{X := -1536.0, Y := 0.0, Z := 100.0}
    if (Mode = coach_mode.Duel):
        return Center + vector3{X := -768.0, Y := 0.0, Z := 100.0}
    if (Mode = coach_mode.FreeBuild):
        return Center + vector3{X := 0.0, Y := 0.0, Z := 100.0}
    if (Mode = coach_mode.EditTraining):
        return Center + vector3{X := 0.0, Y := 0.0, Z := 100.0}
    return Center + vector3{Z := 100.0}

CoachDuelStart(Index : int)<computes>:vector3 =
    return CoachArenaCenter(coach_mode.Duel) + vector3{X := Clamp(Index, 0, 1) * 1536.0 - 768.0, Z := 100.0}

CoachArenaHalfExtent(Mode : coach_mode)<computes>:float =
    if (Mode = coach_mode.Personal):
        return 3072.0
    if (Mode = coach_mode.Duel):
        return 5120.0
    if (Mode = coach_mode.FreeBuild):
        return 8192.0
    if (Mode = coach_mode.EditTraining):
        return 4096.0
    return 2200.0

CoachArenaCeiling()<computes>:float =
    return 24576.0

CoachCourseChainX()<computes>:float =
    return CoachArenaCenter(coach_mode.EditTraining).X + 1024.0

CoachCourseWallX()<computes>:float =
    return CoachArenaCenter(coach_mode.EditTraining).X + -1024.0

CoachCourseTripleX()<computes>:float =
    return CoachArenaCenter(coach_mode.EditTraining).X + 0.0

CoachCourseStaging()<computes>:vector3 =
    return CoachArenaCenter(coach_mode.EditTraining) + vector3{X := 2850.0, Y := 2850.0, Z := 100.0}

CoachCourseContains(Position : vector3)<computes>:logic =
    Center := CoachArenaCenter(coach_mode.EditTraining)
    if (Abs(Position.X - Center.X) < 2200.0 and Abs(Position.Y - Center.Y) < 1650.0):
        return true
    return false
