using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/SpatialMath }

coach_combat_frame := struct:
    At : float = 0.0
    PlayerPosition : vector3 = vector3{}
    OpponentPosition : vector3 = vector3{}
    PlayerView : rotation = IdentityRotation()
    OpponentView : rotation = IdentityRotation()
    PlayerHealth : float = 0.0
    PlayerShield : float = 0.0
    OpponentHealth : float = 0.0
    OpponentShield : float = 0.0
    PlayerCrouched : logic = false
    VisibleToOpponent : ?logic = false
    FightTime : float = 0.0

# Coaching records are separate from the opponent's permitted observation feed.
coach_combat_history := class:
    var Frames<private> : []coach_combat_frame = array{}
    var Cursor<private> : int = 0
    var Latest<private> : ?coach_combat_frame = false
    var LastBucket<private> : int = -1
    var LastIndex<private> : int = -1
    var Focus<private> : coach_review_focus = coach_review_focus{}
    var FocusFrames<private> : []coach_combat_frame = array{}
    var SelectedFocus<private> : ?coach_review_focus = false
    var SelectedFrames<private> : []coach_combat_frame = array{}

    Reset():void =
        set Frames = array{}
        set Cursor = 0
        set Latest = false
        set LastBucket = -1
        set LastIndex = -1
        set Focus = coach_review_focus{}
        set FocusFrames = array{}
        ClearReviewSelection()

    Add(Frame : coach_combat_frame):void =
        AppendFocusFrame(Frame)
        # Damage snapshots update the current 100ms bucket instead of shrinking the 90s history.
        if (Bucket := Floor[Frame.FightTime * 10.0]):
            if (Bucket = LastBucket and LastIndex >= 0):
                if (set Frames[LastIndex] = Frame) {}
                set Latest = option{Frame}
                return
            set LastBucket = Bucket
        if (Frames.Length < 900):
            set Frames += array{Frame}
            set LastIndex = Frames.Length - 1
        else:
            if (set Frames[Cursor] = Frame) {}
            set LastIndex = Cursor
            set Cursor += 1
            if (Cursor >= 900):
                set Cursor = 0
        set Latest = option{Frame}

    LatestFrame()<transacts>:?coach_combat_frame = Latest

    ReviewFocus()<transacts>:coach_review_focus =
        if (Selected := SelectedFocus?):
            return Selected
        return Focus

    RecordedFocusFrames()<transacts>:[]coach_combat_frame =
        if (SelectedFocus?):
            return SelectedFrames
        return FocusFrames

    ClearReviewSelection():void =
        set SelectedFocus = false
        set SelectedFrames = array{}

    # Player-selected attributed damage is a review anchor, not a new claim
    # about why it happened. Preserve the automatically retained focus clip.
    SelectReviewMoment(Moment : coach_moment):logic =
        if (Moment.Kind <> 2 or Moment.Amount <= 0.0):
            return false
        Timeline := OrderedFrames()
        if (FirstSample := Timeline[0], LatestSample := Timeline[Timeline.Length - 1], Moment.At >= FirstSample.At, Moment.At <= LatestSample.At):
            Clip := ActiveWindow(Moment.FightTime, 3.0, 1.0)
            if (Clip.Length = 0):
                return false
            var Snapshot : ?coach_combat_frame = false
            var ClosestDistance : float = 0.16
            for (Frame : Clip, Frame.At <= Moment.At):
                Delta := Moment.At - Frame.At
                if (Delta < ClosestDistance):
                    set Snapshot = option{Frame}
                    set ClosestDistance = Delta
            set SelectedFocus = option{coach_review_focus{At := Moment.At, Damage := Moment.Amount, HasDamageMoment := true, WasVisible := Moment.Visibility, FightTime := Moment.FightTime, Snapshot := Snapshot}}
            set SelectedFrames = Clip
            return true
        return false

    # Keep one bounded focus clip independently of the rolling 90-second buffer.
    # Amount is an attributed native damage event, not a shot count or edit diagnosis.
    RecordIncomingFocus(Amount : float, At : float, FightTime : float, Visibility : ?logic):void =
        if (Amount <= Focus.Damage):
            return
        var Snapshot : ?coach_combat_frame = false
        if (Frame := Latest?, Frame.At <= At, At - Frame.At <= 0.05):
            set Snapshot = option{Frame}
        set Focus = coach_review_focus{At := At, Damage := Amount, HasDamageMoment := true, WasVisible := Visibility, FightTime := FightTime, Snapshot := Snapshot}
        set FocusFrames = ActiveWindow(FightTime, 3.0, 0.0)

    AppendFocusFrame<private>(Frame : coach_combat_frame):void =
        if (not Focus.HasDamageMoment? or Frame.At < Focus.At or Frame.FightTime < Focus.FightTime or Frame.FightTime > Focus.FightTime + 1.0):
            return
        LastFocusIndex := FocusFrames.Length - 1
        if (Previous := FocusFrames[LastFocusIndex], Bucket := Floor[Frame.FightTime * 10.0], PreviousBucket := Floor[Previous.FightTime * 10.0], Bucket = PreviousBucket):
            if (set FocusFrames[LastFocusIndex] = Frame) {}
            return
        if (FocusFrames.Length < 48):
            set FocusFrames += array{Frame}

    Around(At : float, Before : float, After : float)<transacts>:[]coach_combat_frame =
        var Selected : []coach_combat_frame = array{}
        for (Frame : OrderedFrames(), Frame.At >= At - Before, Frame.At <= At + After):
            set Selected += array{Frame}
        return Selected

    ActiveWindow(At : float, Before : float, After : float)<transacts>:[]coach_combat_frame =
        var Selected : []coach_combat_frame = array{}
        for (Frame : OrderedFrames(), Frame.FightTime >= At - Before, Frame.FightTime <= At + After):
            set Selected += array{Frame}
        return Selected

    OrderedFrames<private>()<transacts>:[]coach_combat_frame =
        var Selected : []coach_combat_frame = array{}
        if (Frames.Length = 0):
            return Selected
        if (Frames.Length < 900):
            return Frames
        else:
            for (Index := Cursor..Frames.Length - 1, Frame := Frames[Index]):
                set Selected += array{Frame}
            if (Cursor > 0):
                for (Index := 0..Cursor - 1, Frame := Frames[Index]):
                    set Selected += array{Frame}
        return Selected

# Online imitation of visible, time-separated movement preceding confirmed player damage.
# This learns movement preferences, not unobserved edits or professional mechanics.
coach_human_pattern_model := class:
    var Samples : float = 0.0
    var Successes : float = 0.0
    var Forward : float = 0.0
    var Lateral : float = 0.0
    var Crouch : float = 0.0
    var RecentForward : float = 0.0
    var RecentLateral : float = 0.0
    var RecentCrouch : float = 0.0
    var RecentAt : float = -100.0
    var LastRewardAt : float = -100.0
    var StudyFrame : ?coach_combat_frame = false

    ResetObservation():void =
        set StudyFrame = false
        set RecentAt = -100.0
        set LastRewardAt = -100.0

    ObserveVisibleFrame(Current : coach_combat_frame):void =
        # Visibility discontinuities must be handled before the movement sampling interval.
        # Otherwise a brief hidden/unknown frame can be skipped and bridged by visible endpoints.
        var VisibleNow : logic = false
        if (Visible := Current.VisibleToOpponent?, Visible?):
            set VisibleNow = true
        if (not VisibleNow?):
            set StudyFrame = false
            set RecentAt = -100.0
            return
        if (Previous := StudyFrame?):
            if (Current.At <= Previous.At):
                set StudyFrame = false
                set RecentAt = -100.0
                return
            if (Current.At - Previous.At < 0.15):
                return
            Observe(Previous, Current)
        set StudyFrame = option{Current}

    Observe(Previous : coach_combat_frame, Current : coach_combat_frame):void =
        # An invalid candidate interval cannot leave an older movement eligible for a new hit.
        set RecentAt = -100.0
        if (Visible := Current.VisibleToOpponent?, Visible?, BeforeVisible := Previous.VisibleToOpponent?, BeforeVisible?):
            DeltaTime := Current.At - Previous.At
            Delta := Current.PlayerPosition - Previous.PlayerPosition
            if (DeltaTime < 0.15 or DeltaTime > 0.5 or Distance(Current.PlayerPosition, Previous.PlayerPosition) > 1200.0):
                return
            ToOpponent := Current.OpponentPosition - Current.PlayerPosition
            if (Direction := vector3{X := ToOpponent.X, Y := ToOpponent.Y}.MakeUnitVector[]):
                Right := vector3{X := -Direction.Y, Y := Direction.X}
                set Samples = Min(200.0, Samples + 1.0)
                set RecentForward = Clamp(DotProduct(Delta, Direction) / DeltaTime, -1000.0, 1000.0)
                set RecentLateral = Clamp(DotProduct(Delta, Right) / DeltaTime, -1000.0, 1000.0)
                set RecentCrouch = 0.0
                if (Current.PlayerCrouched?):
                    set RecentCrouch = 1.0
                set RecentAt = Current.At

    RewardObservedPattern(At : float):void =
        if (At - RecentAt > 0.6 or At < RecentAt or At - LastRewardAt < 0.25):
            return
        set LastRewardAt = At
        set Successes = Min(100.0, Successes + 1.0)
        set Forward = Forward * 0.85 + RecentForward * 0.15
        set Lateral = Lateral * 0.85 + RecentLateral * 0.15
        set Crouch = Crouch * 0.85 + RecentCrouch * 0.15

    Confidence()<transacts>:float =
        return Min(Clamp((Samples - 20.0) / 60.0, 0.0, 1.0), Clamp((Successes - 2.0) / 12.0, 0.0, 1.0))

coach_review_focus := struct:
    At : float = 0.0
    Damage : float = 0.0
    HasDamageMoment : logic = false
    WasVisible : ?logic = false
    FightTime : float = 0.0
    Snapshot : ?coach_combat_frame = false

CoachReviewFocus(Training : coach_training_session)<transacts>:coach_review_focus =
    return Training.History.ReviewFocus()

coach_review_context := struct:
    HasPositionSample : logic = false
    RangeCm : float = 0.0
    OpponentHeightAdvantage : float = 0.0
    VisibleRun : float = 0.0

CoachReviewContext(Training : coach_training_session)<transacts>:coach_review_context =
    Focus := CoachReviewFocus(Training)
    var Closest : ?coach_combat_frame = Focus.Snapshot
    var ClosestDistance : float = 0.16
    var VisibleRun : float = 0.0
    var PreviousAt : float = -100.0
    var PreviousVisible : logic = false
    if (Focus.HasDamageMoment?):
        for (Frame : Training.History.RecordedFocusFrames(), Frame.At >= Focus.At - 2.0, Frame.At <= Focus.At):
            Delta := Abs(Frame.At - Focus.At)
            if (not Focus.Snapshot?, Delta < ClosestDistance):
                set Closest = option{Frame}
                set ClosestDistance = Delta
            if (Frame.At <= Focus.At + 0.03):
                if (Visible := Frame.VisibleToOpponent?, Visible?):
                    if (PreviousVisible? and Frame.At - PreviousAt <= 0.25):
                        set VisibleRun += Max(0.0, Frame.At - PreviousAt)
                    else:
                        set VisibleRun = 0.0
                    set PreviousVisible = true
                else:
                    set VisibleRun = 0.0
                    set PreviousVisible = false
                set PreviousAt = Frame.At
        if (Focus.At - PreviousAt > 0.25):
            set VisibleRun = 0.0
        if (Frame := Closest?):
            return coach_review_context{HasPositionSample := true, RangeCm := Distance(Frame.PlayerPosition, Frame.OpponentPosition), OpponentHeightAdvantage := Frame.OpponentPosition.Z - Frame.PlayerPosition.Z, VisibleRun := Min(2.0, VisibleRun)}
    return coach_review_context{}

CoachReviewEvidence(Training : coach_training_session):message =
    Focus := CoachReviewFocus(Training)
    H := Training.HebrewText
    Outgoing := CoachNumber(Training.OutgoingDamage)
    Incoming := CoachNumber(Training.IncomingDamage)
    if (Focus.HasDamageMoment?):
        Seconds := CoachElapsedText(Focus.FightTime)
        Amount := CoachNumber(Focus.Damage)
        var English : string = "Damage dealt {Outgoing} / Taken {Incoming}\nFocus moment: around {Seconds}, your opponent dealt {Amount} damage."
        var Hebrew : string = "נזק שהסבת {Outgoing} / שספגת {Incoming}\nרגע למיקוד: בסביבות {Seconds}, היריב הסב לך {Amount} נזק."
        Context := CoachReviewContext(Training)
        if (Context.HasPositionSample?):
            Range := CoachNumber(Context.RangeCm / 100.0)
            set English += "\nRecorded distance: about {Range}m."
            set Hebrew += "\nהמרחק שנרשם: כ־{Range}מ׳."
            if (Context.OpponentHeightAdvantage > 200.0):
                Height := CoachNumber(Context.OpponentHeightAdvantage / 100.0)
                set English += " The coach was about {Height}m higher. Try a protected angle before pushing toward that height."
                set Hebrew += " המאמן היה גבוה ממך בכ־{Height}מ׳. נסה זווית מוגנת לפני התקדמות לעבר הגובה הזה."
            else if (Context.VisibleRun >= 1.5):
                Duration := CoachElapsedText(Context.VisibleRun)
                set English += " You stayed in the opponent's sight for at least {Duration} before the hit. Practice a shorter opening and a safe return."
                set Hebrew += " נשארת בטווח הראייה של היריב לפחות {Duration} לפני הפגיעה. תרגל פתיחה קצרה וחזרה לעמדה בטוחה."
            else:
                set English += " Compare the positions and timing, then try one controlled opening."
                set Hebrew += " השווה עמדות ותזמון, ואז נסה פתיחה מבוקרת אחת."
        else:
            set English += "\nNearby position samples are unavailable. Choose a general technique without assuming which edit caused the hit."
            set Hebrew += "\nדגימות המיקום שסביב הרגע אינן זמינות. בחר טכניקה כללית בלי להסיק איזו עריכה גרמה לפגיעה."
        set English += "\n\n" + CoachRecommendationSummary(Training, false)
        set Hebrew += "\n\n" + CoachRecommendationSummary(Training, true)
        return CoachLanguage(English, Hebrew, H)
    EnglishRecommendation := CoachRecommendationSummary(Training, false)
    HebrewRecommendation := CoachRecommendationSummary(Training, true)
    return CoachLanguage("Damage dealt {Outgoing} / Taken {Incoming}\nNo incoming damage moment was recorded.\n\n{EnglishRecommendation}", "נזק שהסבת {Outgoing} / שספגת {Incoming}\nלא נרשם רגע שבו ספגת נזק מהיריב.\n\n{HebrewRecommendation}", H)
