using { /Fortnite.com/Characters }
using { /Fortnite.com/Devices }
using { /Verse.org/Simulation }
using { /Verse.org/SceneGraph }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /UnrealEngine.com/Temporary/Diagnostics }

coach_course_kind := enum:
    PrecisionWalls
    TripleSequence
    TripleChain

CoachCourseSectionCount(Kind : coach_course_kind)<computes>:int =
    if (Kind = coach_course_kind.PrecisionWalls):
        return 5
    return 3

CoachElapsedText(Elapsed : float):string =
    Whole := CoachNumber(Max(0.0, Elapsed))
    Tenth := CoachNumber(Max(0.0, Elapsed) * 10.0) - Whole * 10
    return "{Whole}.{Tenth}s"

CoachCourseSegmentsValid(Kind : coach_course_kind, Elapsed : float, Segments : []float)<transacts>:logic =
    Expected := CoachCourseSectionCount(Kind)
    if (Segments.Length <> Expected or Elapsed <= 0.0):
        return false
    var Total : float = 0.0
    for (Value : Segments):
        if (Value <= 0.0):
            return false
        set Total += Value
    return logic{Abs(Total - Elapsed) <= 0.1}

CoachCourseBestSegments(Current : []float, Previous : []float)<transacts>:[]float =
    var Result : []float = array{}
    for (Index -> Value : Current):
        var Best : float = Value
        if (Old := Previous[Index], Old > 0.0):
            set Best = Min(Old, Value)
        set Result += array{Best}
    return Result

CoachCourseResultText(Elapsed : float, Segments : []float, Previous : []float, H : logic):message =
    Time := CoachElapsedText(Elapsed)
    var E : string = "Route: {Time}\nSections, including movement:"
    var Hebrew : string = "זמן מסלול: {Time}\nמקטעים, כולל תנועה:"
    var LargestGap : float = 0.1
    var Focus : int = 0
    for (Index -> Value : Segments):
        Number := Index + 1
        Split := CoachElapsedText(Value)
        set E += " {Number}: {Split}"
        set Hebrew += " {Number}: {Split}"
        if (Old := Previous[Index], Old > 0.0, Value - Old > LargestGap):
            set LargestGap = Value - Old
            set Focus = Number
    if (Focus > 0):
        Gap := CoachElapsedText(LargestGap)
        set E += "\nNext focus: section {Focus}, {Gap} above your best for that section."
        set Hebrew += "\nמיקוד לחזרה הבאה: מקטע {Focus}, איטי ב־{Gap} מהשיא שלך במקטע הזה."
    else if (Previous.Length = 0):
        set E += "\nYour first segment reference. These are route times, not individual edit accuracy."
        set Hebrew += "\nנקודת הייחוס הראשונה למקטעים. אלה זמני מסלול, לא דיוק של עריכות בודדות."
    else:
        set E += "\nNo section was more than 0.1s above its previous best."
        set Hebrew += "\nאף מקטע לא היה איטי ביותר מ־0.1שנ׳ מהשיא הקודם שלו."
    return CoachLanguage(E, Hebrew, H)

# The route records ordered physical progress. It does not fabricate native edit events.
coach_course_device := class(creative_device):
    @editable
    LayerConfigured : logic = false
    @editable
    UnloadCourse : cinematic_sequence_device = cinematic_sequence_device{}
    @editable
    LoadCourse : cinematic_sequence_device = cinematic_sequence_device{}
    @editable
    CourseReset : explosive_device = explosive_device{}
    @editable
    UpperReset : explosive_device = explosive_device{}
    @editable
    CourseBoundary : barrier_device = barrier_device{}

    var Portal : ?coach_portal_device = false
    var CurrentOwner : ?player = false
    var CurrentKind : coach_course_kind = coach_course_kind.PrecisionWalls
    var WorldResetting : logic = false
    var Serial : int = 0
    var Loading : logic = false
    var Armed : logic = false
    var Running : logic = false
    var Paused : logic = false
    var PausedAt : float = 0.0
    var Step : int = 0
    var StartedAt : float = 0.0
    var ResetAvailableAt : float = 0.0
    Geometry : coach_geometry_query = coach_geometry_query{}
    var ReturnToLesson : logic = false
    var Ending : logic = false
    var SegmentTimes : []float = array{}
    var LastSplitElapsed : float = 0.0
    var PreviousPosition : ?vector3 = false
    var PreviousSampleAt : float = 0.0
    var RecordEligible : logic = true

    OnBegin<override>()<suspends>:void =
        CourseBoundary.RemoveAllFromIgnoreList()
        CourseBoundary.Disable()
        loop:
            if (Ending?):
                return
            if (Player := CurrentOwner?, not Loading?, not Paused?, Character := Player.GetFortCharacter[], Character.IsActive[]):
                UpdateProgress(Player, Character.GetTransform().Translation)
            Sleep(0.05)

    OnEnd<override>():void =
        set Ending = true
        set Serial += 1
        UnloadCourse.Stop()
        LoadCourse.Stop()

    IsActiveFor(Player : player)<transacts>:logic =
        if (Owner := CurrentOwner?, Owner = Player):
            return true
        return false

    Start(Player : player, Kind : coach_course_kind, ?ReturnAfter : logic = false):void =
        if (not LayerConfigured? or WorldResetting?):
            if (Host := Portal?, View := Host.Views[Player], Training := Host.Runtime.Players[Player]):
                View.SetCaption(CoachLanguage("The practice area is preparing. Choose the course again in a moment.", "אזור התרגול בהכנה. בחר שוב את המסלול בעוד רגע.", Training.HebrewText))
            return
        if (Other := CurrentOwner?, Other <> Player):
            if (Host := Portal?, View := Host.Views[Player], Training := Host.Runtime.Players[Player]):
                View.SetCaption(CoachLanguage("The practice course is in use. Lessons and free build are available.", "מסלול התרגול תפוס כרגע. אפשר לצפות בשיעור או להתאמן בבנייה חופשית.", Training.HebrewText))
            return
        if (Loading?):
            return
        if (Host := Portal?):
            Granted := Host.ArenaAccess.TryReserve(Player, coach_mode.EditTraining)
            if (not Granted?):
                if (View := Host.Views[Player], Training := Host.Runtime.Players[Player]):
                    View.SetCaption(CoachLanguage("The edit area is reserved by another player. Your current training is preserved.", "אזור העריכות בשימוש של שחקן אחר. האימון הנוכחי שלך נשמר.", Training.HebrewText))
                return
        set CurrentOwner = option{Player}
        set CurrentKind = Kind
        set ReturnToLesson = ReturnAfter
        set Serial += 1
        set Loading = true
        set Paused = false
        set Running = false
        set Armed = false
        set Step = 0
        set SegmentTimes = array{}
        set LastSplitElapsed = 0.0
        set PreviousPosition = false
        set RecordEligible = true
        CourseBoundary.RemoveAllFromIgnoreList()
        CourseBoundary.AddToIgnoreList(Player)
        spawn { Prepare(Player, Serial) }

    Prepare(Player : player, Ticket : int)<suspends>:void =
        if (Ticket <> Serial or Ending?):
            return
        if (Character := Player.GetFortCharacter[], Character.TeleportTo[CoachCourseStaging(), MakeRotationFromYawPitchRollDegrees(90.0, 0.0, 0.0)]):
            Sleep(0.0)
        else:
            FailStart(Player)
            return
        if (Ticket <> Serial or Ending?):
            return
        Restored := RestoreCourseWorld(Player)
        if (Ticket <> Serial or Ending?):
            return
        if (not Restored?):
            FailStart(Player)
            return
        loop:
            if (Ticket <> Serial or Ending?):
                return
            if (not Paused?):
                break
            Sleep(0.1)
        var StartPosition : vector3 = vector3{X := CoachCourseWallX(), Y := -1450.0, Z := 100.0}
        if (CurrentKind = coach_course_kind.TripleSequence):
            set StartPosition.X = CoachCourseTripleX()
        else if (CurrentKind = coach_course_kind.TripleChain):
            set StartPosition.X = CoachCourseChainX()
        if (Character := Player.GetFortCharacter[], Character.TeleportTo[StartPosition, MakeRotationFromYawPitchRollDegrees(90.0, 0.0, 0.0)]):
            set PreviousPosition = option{Character.GetTransform().Translation}
            set PreviousSampleAt = GetSimulationElapsedTime()
            set Loading = false
            set Armed = true
            if (not Paused?, Host := Portal?, View := Host.Views[Player]):
                View.CloseMenu()
        else:
            FailStart(Player)

    PlayLayerSequence(Sequence : cinematic_sequence_device)<suspends>:logic =
        Sequence.Stop()
        Sequence.SetPlaybackFrame(0)
        Sequence.SetPlayRate(1.0)
        PlaybackStartedAt := GetSimulationElapsedTime()
        EarliestStop := Max(0.0, Sequence.GetSequenceLength() - 0.15)
        Sequence.Play()
        var Finished : logic = false
        race:
            block:
                loop:
                    Sequence.StoppedEvent.Await()
                    if (GetSimulationElapsedTime() - PlaybackStartedAt >= EarliestStop):
                        set Finished = true
                        break
            Sleep(8.0)
        if (not Finished?):
            Sequence.Stop()
        return Finished

    # Always finish restoring the shared world even when its requesting player
    # leaves. Native actors live in the layer, with no persistent actor references.
    RestoreCourseWorld(Player : player)<suspends>:logic =
        if (WorldResetting? or Ending?):
            return false
        set WorldResetting = true
        defer:
            set WorldResetting = false
        Unloaded := PlayLayerSequence(UnloadCourse)
        if (Ending?):
            return false
        Sleep(Max(0.0, ResetAvailableAt - GetSimulationElapsedTime()))
        if (Player.IsActive[]):
            CourseReset.Explode(Player)
            UpperReset.Explode(Player)
            set ResetAvailableAt = GetSimulationElapsedTime() + 1.2
            spawn { RearmReset() }
        Sleep(0.25)
        Loaded := PlayLayerSequence(LoadCourse)
        if (not Unloaded? or not Loaded? or Ending?):
            return false
        for (Attempt := 0..23):
            if (Ending?):
                return false
            if (CourseGeometryReady()?):
                return true
            Sleep(0.25)
        return false

    CourseGeometryReady()<transacts>:logic =
        if (Root := GetSimulationEntity[]):
            if (CurrentKind = coach_course_kind.PrecisionWalls):
                for (Index := 0..4):
                    Sample := Geometry.SampleWall(Root, vector3{X := CoachCourseWallX(), Y := -768.0 + Index * 512.0}, 90.0)
                    if (Sample.Occupied <> 9):
                        return false
            else if (CurrentKind = coach_course_kind.TripleSequence):
                return TripleGeometryReady(Root, CoachCourseTripleX(), -1280.0, 0.0)
            else:
                for (Stage := 0..2):
                    if (not TripleGeometryReady(Root, CoachCourseChainX(), -1280.0 + Stage * 512.0, Stage * 384.0)?):
                        return false
            return true
        return false

    TripleGeometryReady(Root : entity, LaneX : float, BaseY : float, BaseZ : float)<transacts>:logic =
        ExitWall := Geometry.SampleWall(Root, vector3{X := LaneX, Y := BaseY + 512.0, Z := BaseZ + 384.0}, 90.0)
        if (ExitWall.Occupied <> 9):
            return false
        for (OffsetX : array{-170.0, 170.0}, OffsetY : array{85.0, 425.0}, OriginY : array{BaseY, BaseY + 512.0}):
            FloorSweepStart := vector3{X := LaneX + OffsetX, Y := OriginY + OffsetY, Z := BaseZ + 352.0}
            if (not Geometry.SegmentOccupied(Root, FloorSweepStart, FloorSweepStart + vector3{Z := 24.0})?):
                return false
        for (Height : array{BaseZ, BaseZ + 384.0}):
            ProfileSweepStart := vector3{X := LaneX, Y := BaseY + 256.0, Z := Height + 224.0}
            if (not Geometry.SegmentOccupied(Root, ProfileSweepStart, ProfileSweepStart - vector3{Z := 64.0})?):
                return false
        return true

    RearmReset()<suspends>:void =
        Sleep(1.1)
        if (not Ending?):
            CourseReset.Reset()
            UpperReset.Reset()

    FailStart(Player : player):void =
        ReturnAfter := ReturnToLesson
        Release(Player)
        if (ReturnAfter?, Host := Portal?):
            Host.ShowLesson(Player)
        if (Host := Portal?, View := Host.Views[Player], Training := Host.Runtime.Players[Player]):
            View.SetCaption(CoachLanguage("The course could not start. Return to the practice menu and try again.", "המסלול לא התחיל. חזור לתפריט התרגול ונסה שוב.", Training.HebrewText))

    Release(Player : player, ?KeepReservation : logic = false):void =
        if (Current := CurrentOwner?, Current = Player):
            set Serial += 1
            set CurrentOwner = false
            set Loading = false
            set Armed = false
            set Running = false
            set PreviousPosition = false
            set Paused = false
            set ReturnToLesson = false
            if (Host := Portal?, Training := Host.Runtime.Players[Player]):
                set Training.LessonCourseActive = false
                # A mode transfer may already have reserved this area as its destination.
                if (not KeepReservation? and Training.Mode <> coach_mode.EditTraining):
                    Host.ArenaAccess.ReleaseMode(Player, coach_mode.EditTraining)
            CourseBoundary.RemoveAllFromIgnoreList()
            if (Host := Portal?, Character := Player.GetFortCharacter[]):
                Position := Character.GetTransform().Translation
                if (CoachCourseContains(Position)?):
                    Host.MovePlayer(Player, CoachCourseStaging())

    Pause(Player : player):void =
        if (Owner := CurrentOwner?, Owner = Player, not Paused?):
            set Paused = true
            set PausedAt = GetSimulationElapsedTime()

    Resume(Player : player):void =
        if (Owner := CurrentOwner?, Owner = Player, Paused?):
            if (Running?):
                set StartedAt += GetSimulationElapsedTime() - PausedAt
            if (Character := Player.GetFortCharacter[]):
                set PreviousPosition = option{Character.GetTransform().Translation}
                set PreviousSampleAt = GetSimulationElapsedTime()
            set Paused = false

    MarkStep():void =
        Elapsed := GetSimulationElapsedTime() - StartedAt
        Duration := Elapsed - LastSplitElapsed
        if (Duration <= 0.0):
            set RecordEligible = false
        set SegmentTimes += array{Max(0.0, Duration)}
        set LastSplitElapsed = Elapsed
        set Step += 1

    UpdateProgress(Player : player, Position : vector3):void =
        Now := GetSimulationElapsedTime()
        if (Previous := PreviousPosition?, Armed?):
            if (Distance(Previous, Position) > 600.0 or Now - PreviousSampleAt > 0.35):
                # Continue practice after missing data, but do not invent a record.
                set RecordEligible = false
        set PreviousPosition = option{Position}
        set PreviousSampleAt = Now
        var CenterX : float = CoachCourseWallX()
        var MaximumZ : float = 220.0
        if (CurrentKind = coach_course_kind.TripleSequence):
            set CenterX = CoachCourseTripleX()
            set MaximumZ = 760.0
        else if (CurrentKind = coach_course_kind.TripleChain):
            set CenterX = CoachCourseChainX()
            set MaximumZ = 1500.0
        if (Abs(Position.X - CenterX) > 220.0 or Position.Y < -1550.0 or Position.Y > 1600.0 or Position.Z < -20.0 or Position.Z > MaximumZ):
            ReturnAfter := ReturnToLesson
            Release(Player)
            if (ReturnAfter?, Host := Portal?):
                Host.ShowLesson(Player)
            return
        if (Armed? and not Running? and Position.Y > -1330.0):
            set Running = true
            set StartedAt = GetSimulationElapsedTime()
        if (not Running?):
            return
        if (CurrentKind = coach_course_kind.PrecisionWalls):
            for (Index := 0..4):
                if (Step = Index and Position.Y > -644.0 + Index * 512.0):
                    MarkStep()
            if (Step = 5):
                Complete(Player)
        else if (CurrentKind = coach_course_kind.TripleSequence):
            if (Step = 0 and Position.Y > -1030.0 and Position.Z > 200.0):
                MarkStep()
            if (Step = 1 and Position.Y > -800.0 and Position.Z > 350.0):
                MarkStep()
            if (Step = 2 and Position.Y > -512.0 and Position.Z > 350.0):
                MarkStep()
                Complete(Player)

        else:
            # One section per ascent, including its exit wall. Native editing
            # itself is not inferred from crossing these physical thresholds.
            for (Stage := 0..2):
                if (Step = Stage and Position.Y > -668.0 + Stage * 512.0 and Position.Z > 450.0 + Stage * 384.0):
                    MarkStep()
            if (Step = 3):
                Complete(Player)

    Complete(Player : player):void =
        Elapsed := GetSimulationElapsedTime() - StartedAt
        ReturnAfter := ReturnToLesson
        var Summary : message = CoachMessage("")
        var TimedResult : logic = false
        if (Host := Portal?, Training := Host.Runtime.Players[Player], View := Host.Views[Player]):
            var Previous : []float = Training.Profile.BestWallSegments
            if (CurrentKind = coach_course_kind.TripleSequence):
                set Previous = Training.Profile.BestTripleSegments
            else if (CurrentKind = coach_course_kind.TripleChain):
                set Previous = Training.Profile.BestChainSegments
            set Summary = CoachLanguage("Practice finished. Timing was interrupted, so no personal record was added. Reset and repeat for a measured result.", "התרגול הסתיים. המדידה נקטעה ולכן לא נוסף שיא אישי. אפס וחזור על המסלול לקבלת תוצאה מדודה.", Training.HebrewText)
            if (RecordEligible?, CoachCourseSegmentsValid(CurrentKind, Elapsed, SegmentTimes)?):
                set TimedResult = true
                set Summary = CoachCourseResultText(Elapsed, SegmentTimes, Previous, Training.HebrewText)
                Training.RecordDrill(CurrentKind, Elapsed, ?Segments := SegmentTimes)
            Host.MovePlayer(Player, CoachCourseStaging())
            if (TimedResult?):
                View.SetCaption(CoachLanguage("Practice route: {CoachElapsedText(Elapsed)}", "מסלול התרגול: {CoachElapsedText(Elapsed)}", Training.HebrewText))
            else:
                View.SetCaption(CoachLanguage("Practice finished. Timing interrupted; no record added.", "התרגול הסתיים. המדידה נקטעה ולא נוסף שיא.", Training.HebrewText))
        Release(Player)
        if (Host := Portal?):
            Host.ShowCourseResult(Player, CurrentKind, Summary, ?FromLesson := ReturnAfter)

    StatusFor(Player : player, H : logic):message =
        if (Owner := CurrentOwner?, Owner = Player):
            if (Loading?):
                return CoachLanguage("EDIT PRACTICE\nPreparing your course", "אימון עריכות\nמכין את המסלול", H)
            if (Paused?):
                return CoachLanguage("EDIT PRACTICE\nPaused in the coach menu", "אימון עריכות\nהתרגול נעצר בתפריט המאמן", H)
            if (Running?):
                Elapsed := CoachElapsedText(GetSimulationElapsedTime() - StartedAt)
                Total := CoachCourseSectionCount(CurrentKind)
                return CoachLanguage("EDIT PRACTICE  {Step}/{Total}\n{Elapsed}", "אימון עריכות  {Step}/{Total}\n{Elapsed}", H)
            return CoachLanguage("EDIT PRACTICE\nMove forward when you are ready", "אימון עריכות\nהתקדם כשתהיה מוכן", H)
        return CoachLanguage("EDIT PRACTICE\nOpen the coach menu to choose a course", "אימון עריכות\nפתח את תפריט המאמן ובחר מסלול", H)
