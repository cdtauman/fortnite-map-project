using { /Fortnite.com/Characters }
using { /Fortnite.com/Devices }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/SpatialMath }

# Live build coach (spec v1 section 5, step 4.1). A cyan hologram shows exactly where the next
# piece goes on the 512cm / 384cm build grid in front of the player. A piece counts as built
# when a scene overlap query of that cell finds a new object (experiment N1: player-built pieces
# are visible to scene queries). Edit steps are confirmed by a fixed 3x3 ray probe through the
# wall that must open (N1 showed openings; this fixed-position probe is still unverified in game).
# Grid conventions: uefn/grid-conventions.json. Drill list: docs/RESEARCH_BUILD_DRILLS_HE.md.

coach_drill_step := struct<computes>:
    # 0 wall, 1 floor, 2 ramp, 3 cone (roof), 4 edit an opening in a wall
    Kind : int = 0
    Forward : int = 0
    Right : int = 0
    Level : int = 0
    # 0 forward, 1 right, 2 back, 3 left: wall normal, ramp uphill, or the wall side to edit
    Side : int = 0

coach_drill := struct<computes>:
    Code : string = ""
    English : string = ""
    Hebrew : string = ""
    Steps : []coach_drill_step = array{}

CoachDrills : []coach_drill = array{
    coach_drill{Code := "B1", English := "Wall + ramp", Hebrew := "קיר ורמפה", Steps := array{
        coach_drill_step{Kind := 0, Side := 0},
        coach_drill_step{Kind := 2, Side := 0}}},
    coach_drill{Code := "B3", English := "Ramp rush", Hebrew := "ריצת רמפות", Steps := array{
        coach_drill_step{Kind := 2, Side := 0},
        coach_drill_step{Kind := 2, Forward := 1, Level := 1, Side := 0},
        coach_drill_step{Kind := 2, Forward := 2, Level := 2, Side := 0}}},
    coach_drill{Code := "B4", English := "90s (two levels)", Hebrew := "90 מעלות (שתי קומות)", Steps := array{
        coach_drill_step{Kind := 0, Side := 0},
        coach_drill_step{Kind := 2, Side := 0},
        coach_drill_step{Kind := 0, Level := 1, Side := 1},
        coach_drill_step{Kind := 2, Level := 1, Side := 1}}},
    coach_drill{Code := "B6", English := "Box up", Hebrew := "קופסה", Steps := array{
        coach_drill_step{Kind := 0, Side := 0},
        coach_drill_step{Kind := 0, Side := 1},
        coach_drill_step{Kind := 0, Side := 2},
        coach_drill_step{Kind := 0, Side := 3},
        coach_drill_step{Kind := 3, Level := 1}}},
    coach_drill{Code := "B9", English := "Box, then edit out", Hebrew := "קופסה ויציאה בעריכה", Steps := array{
        coach_drill_step{Kind := 0, Side := 0},
        coach_drill_step{Kind := 0, Side := 1},
        coach_drill_step{Kind := 0, Side := 2},
        coach_drill_step{Kind := 0, Side := 3},
        coach_drill_step{Kind := 4, Side := 0}}},
    coach_drill{Code := "I4", English := "Cone cover over a ramp", Hebrew := "גג קונוס מעל רמפה", Steps := array{
        coach_drill_step{Kind := 2, Side := 0},
        coach_drill_step{Kind := 3, Level := 1},
        coach_drill_step{Kind := 0, Forward := 1, Side := 0}}}
}

CoachDegrees(Value : float)<transacts>:float = Value * PiFloat / 180.0

CoachYawDirection(Yaw : float)<transacts>:vector3 =
    vector3{X := Cos(CoachDegrees(Yaw)), Y := Sin(CoachDegrees(Yaw)), Z := 0.0}

coach_drill_frame := class<final>:
    Origin : vector3 = vector3{}
    Yaw : float = 0.0

    CellCenter(Step : coach_drill_step)<transacts>:vector3 =
        Origin + CoachYawDirection(Yaw) * (512.0 * Step.Forward) + CoachYawDirection(Yaw + 90.0) * (512.0 * Step.Right) + vector3{Z := 384.0 * Step.Level}

    SideYaw(Step : coach_drill_step)<transacts>:float = Yaw + 90.0 * Step.Side

    # Where the hologram prop goes (mesh pivots per grid-conventions.json).
    PiecePose(Step : coach_drill_step)<transacts>:transform =
        Center := CellCenter(Step)
        Policy := SideYaw(Step)
        if (Step.Kind = 0 or Step.Kind = 4):
            return transform{Translation := Center + CoachYawDirection(Policy) * 256.0, Rotation := MakeRotationFromYawPitchRollDegrees(Policy + 90.0, 0.0, 0.0)}
        if (Step.Kind = 2):
            Mesh := Policy - 90.0
            return transform{Translation := Center - CoachYawDirection(Mesh + 90.0) * 256.0, Rotation := MakeRotationFromYawPitchRollDegrees(Mesh, 0.0, 0.0)}
        transform{Translation := Center - vector3{Y := 256.0}, Rotation := IdentityRotation()}

    # Slightly shrunk interior of the piece, so neighbouring pieces do not count.
    ProbePose(Step : coach_drill_step)<transacts>:transform =
        Center := CellCenter(Step)
        Policy := SideYaw(Step)
        Rotation := MakeRotationFromYawPitchRollDegrees(Policy, 0.0, 0.0)
        if (Step.Kind = 0):
            return transform{Translation := Center + CoachYawDirection(Policy) * 256.0 + vector3{Z := 192.0}, Rotation := Rotation}
        if (Step.Kind = 1):
            return transform{Translation := Center + vector3{Z := 4.0}, Rotation := Rotation}
        if (Step.Kind = 2):
            return transform{Translation := Center + vector3{Z := 192.0}, Rotation := Rotation}
        transform{Translation := Center + vector3{Z := 96.0}, Rotation := Rotation}

    ProbeExtent(Step : coach_drill_step)<transacts>:vector3 =
        if (Step.Kind = 0):
            return vector3{X := 20.0, Y := 200.0, Z := 150.0}
        if (Step.Kind = 1):
            return vector3{X := 200.0, Y := 200.0, Z := 20.0}
        if (Step.Kind = 2):
            return vector3{X := 150.0, Y := 150.0, Z := 40.0}
        vector3{X := 150.0, Y := 150.0, Z := 30.0}

coach_build_coach := class:
    var Generation : int = 0
    var Owner : ?player = false

    Busy(Player : player)<transacts>:logic =
        if (Current := Owner?, Current <> Player):
            return true
        false

    Stop(Portal : coach_portal_device):void =
        set Generation += 1
        set Owner = false
        Portal.HideHolograms()

    Start(Portal : coach_portal_device, Player : player, DrillIndex : int, Pace : int):void =
        set Generation += 1
        set Owner = option{Player}
        Ticket := Generation
        spawn { Run(Portal, Player, Ticket, DrillIndex, Pace) }

    Entities(Root : entity, Pose : transform, Extent : vector3)<transacts>:[]entity =
        Box := collision_box{Extents := FromVector3(Extent), CollisionProfile := collision_profile{Channel := CollisionChannels.dynamic{}, GetChannelInteraction := CoachStructureInteraction}}
        var Found : []entity = array{}
        for (Hit : Root.FindOverlapHits(FromTransform(Pose), Box)):
            set Found += array{Hit.TargetComponent.Entity}
        Found

    # True when the probe sees an object that was not there when the step began and is not
    # the player's own body (N1: the body is also returned by scene queries).
    Built(Root : entity, Pose : transform, Extent : vector3, Baseline : []entity, Body : vector3)<transacts>:logic =
        for (Item : Entities(Root, Pose, Extent)):
            var Known : logic = false
            for (Old : Baseline, Old = Item):
                set Known = true
            if (not Known?):
                At := FromVector3(Item.GetGlobalTransform().Translation)
                if (Distance(At, Body) > 150.0):
                    return true
        false

    # Fixed 3x3 rays through the wall plane; fewer blocked rays means an opening was edited.
    WallBlocked(Root : entity, Frame : coach_drill_frame, Step : coach_drill_step)<transacts>:int =
        Policy := Frame.SideYaw(Step)
        Normal := CoachYawDirection(Policy)
        Along := CoachYawDirection(Policy + 90.0)
        Base := Frame.CellCenter(Step) + Normal * 256.0
        Sphere := collision_sphere{Radius := 2.0, CollisionProfile := collision_profile{Channel := CollisionChannels.dynamic{}, GetChannelInteraction := CoachStructureInteraction}}
        var Count : int = 0
        for (A : array{-150.0, 0.0, 150.0}, B : array{80.0, 192.0, 300.0}):
            RayStart := Base + Along * A + vector3{Z := B} - Normal * 60.0
            var Hit : logic = false
            for (Sweep : Root.FindSweepHits(FromVector3(Normal * 120.0), FromTransform(transform{Translation := RayStart}), Sphere)):
                set Hit = true
            if (Hit?):
                set Count += 1
        Count

    Run(Portal : coach_portal_device, Player : player, Ticket : int, DrillIndex : int, Pace : int)<suspends>:void =
        defer:
            if (Ticket = Generation):
                set Owner = false
                Portal.HideHolograms()
        if (Drill := CoachDrills[DrillIndex], Root := Portal.GetSimulationEntity[], Character := Player.GetFortCharacter[], Training := Portal.Runtime.Players[Player]):
            H := Training.HebrewText
            Feet := Character.GetTransform().Translation
            var Yaw : float = 0.0
            if (ViewYaw := Character.GetViewRotation().GetYawPitchRollDegrees()[0], Snapped := Round[ViewYaw / 90.0]):
                set Yaw = 90.0 * Snapped
            var Cx : float = Feet.X
            var Cy : float = Feet.Y
            var Cz : float = 0.0
            if (Ix := Floor[Feet.X / 512.0], Iy := Floor[Feet.Y / 512.0], Iz := Floor[(Feet.Z - 40.0) / 384.0]):
                set Cx = 512.0 * Ix + 256.0
                set Cy = 512.0 * Iy + 256.0
                set Cz = 384.0 * Iz
            Frame := coach_drill_frame{Origin := vector3{X := Cx, Y := Cy, Z := Cz}, Yaw := Yaw}
            Best := Training.DrillBest(DrillIndex)
            var Limit : float = 2.0 * Drill.Steps.Length
            if (Best > 0.0):
                set Limit = Best * 1.15
            Portal.ShowDrillCaption(Player, "{CoachPick("Get ready", "היכונו", H)}: {CoachPick(Drill.English, Drill.Hebrew, H)}")
            Sleep(1.5)
            StartedAt := GetSimulationElapsedTime()
            for (Index -> Step : Drill.Steps):
                if (Ticket <> Generation):
                    return
                Portal.HideHolograms()
                if (Step.Kind <> 4):
                    Portal.ShowHologram(Step.Kind, Frame.PiecePose(Step))
                Portal.ShowDrillCaption(Player, "{Index + 1}/{Drill.Steps.Length}  {CoachDrillStepText(Step, H)}")
                ProbePose := Frame.ProbePose(Step)
                Extent := Frame.ProbeExtent(Step)
                Baseline := Entities(Root, ProbePose, Extent)
                StartBlocked := WallBlocked(Root, Frame, Step)
                loop:
                    if (Ticket <> Generation or not Portal.InFreeBuild(Player)?):
                        return
                    if (Pace = 2 and GetSimulationElapsedTime() - StartedAt > Limit):
                        Portal.ShowDrillCaption(Player, CoachPick("Too slow for pressure mode. Try again or switch to normal.", "איטי מדי למצב לחץ. נסה שוב או עבור למצב רגיל.", H))
                        return
                    if (Body := Player.GetFortCharacter[]):
                        BodyAt := Body.GetTransform().Translation
                        if (Step.Kind = 4):
                            if (StartBlocked >= 5 and WallBlocked(Root, Frame, Step) < StartBlocked):
                                break
                        else if (Built(Root, ProbePose, Extent, Baseline, BodyAt)?):
                            break
                    Sleep(0.15)
            Elapsed := GetSimulationElapsedTime() - StartedAt
            Portal.HideHolograms()
            NewBest := Training.RecordDrillBest(DrillIndex, Elapsed)
            Time := CoachElapsedText(Elapsed)
            if (Pace = 0):
                Portal.ShowDrillCaption(Player, "{CoachPick("Done", "סיימת", H)}: {CoachPick(Drill.English, Drill.Hebrew, H)} ({Time}). {CoachPick("Next: try normal pace.", "הבא: נסה בקצב רגיל.", H)}")
            else if (NewBest?):
                Portal.ShowDrillCaption(Player, "{CoachPick("New best", "שיא חדש", H)}: {Time}!")
            else:
                Portal.ShowDrillCaption(Player, "{CoachPick("Time", "זמן", H)}: {Time} / {CoachPick("best", "שיא", H)} {CoachElapsedText(Training.DrillBest(DrillIndex))}")

CoachDrillStepText(Step : coach_drill_step, Hebrew : logic)<transacts>:string =
    if (Step.Kind = 0):
        return CoachPick("Build a WALL on the hologram", "בנה קיר במקום ההולוגרמה", Hebrew)
    if (Step.Kind = 1):
        return CoachPick("Build a FLOOR on the hologram", "בנה רצפה במקום ההולוגרמה", Hebrew)
    if (Step.Kind = 2):
        return CoachPick("Build a RAMP on the hologram", "בנה רמפה במקום ההולוגרמה", Hebrew)
    if (Step.Kind = 3):
        return CoachPick("Build a CONE (roof) on the hologram", "בנה גג קונוס במקום ההולוגרמה", Hebrew)
    CoachPick("EDIT the front wall: open a window or door", "ערוך את הקיר שמולך: פתח חלון או דלת", Hebrew)
