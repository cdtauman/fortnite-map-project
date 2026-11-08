using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/SpatialMath }

# A measured sight/damage exercise. It does not infer edits, cover ownership or shot accuracy.
coach_exchange_practice := class:
    var Goal : int = 0
    var Progress : int = 0
    var Completed : logic = false
    var CompletionShown : logic = false
    var LastFrame : ?coach_combat_frame = false
    var VisibleStartedAt : float = -1.0
    var HiddenStartedAt : float = -1.0
    var HadHiddenApproach : logic = false
    var HitAt : float = -1.0
    var HitPosition : vector3 = vector3{}
    var HitDirection : vector3 = vector3{}
    var ReturnStartedAt : float = -1.0
    var Pending : logic = false
    var PreviousPosition : ?vector3 = false
    var PreviousDirection : vector3 = vector3{}
    var OpeningBudget : float = 2.0
    var AngleDotLimit : float = 0.8
    var MinimumReposition : float = 200.0

    Start(GoalKind : int, Challenge : float):void =
        Stop()
        set Goal = Clamp(GoalKind, 1, 2)
        # Hold a stable target throughout the exercise even if round difficulty adapts.
        Difficulty := Clamp(Challenge, 0.1, 0.9)
        set OpeningBudget = 2.2 - Difficulty * 1.2
        set AngleDotLimit = 0.85 - Difficulty * 0.16
        set MinimumReposition = 150.0 + Difficulty * 100.0

    Stop():void =
        set Goal = 0
        set Progress = 0
        set Completed = false
        set CompletionShown = false
        set PreviousPosition = false
        ResetObservation()

    ResetObservation():void =
        set LastFrame = false
        set VisibleStartedAt = -1.0
        set HiddenStartedAt = -1.0
        set HadHiddenApproach = false
        set HitAt = -1.0
        set ReturnStartedAt = -1.0
        set Pending = false

    Observe(Frame : coach_combat_frame):void =
        if (Goal = 0 or Completed?):
            return
        if (Previous := LastFrame?):
            if (Frame.At <= Previous.At):
                return
            if (Frame.At - Previous.At > 0.25):
                ResetObservation()
        if (Visible := Frame.VisibleToOpponent?):
            if (Visible?):
                if (VisibleStartedAt < 0.0):
                    set HadHiddenApproach = false
                    if (HiddenStartedAt >= 0.0 and Frame.At - HiddenStartedAt >= 0.3):
                        set HadHiddenApproach = true
                    set VisibleStartedAt = Frame.At
                    set HitAt = -1.0
                set Pending = false
                set ReturnStartedAt = -1.0
                set HiddenStartedAt = -1.0
            else:
                if (HiddenStartedAt < 0.0):
                    set HiddenStartedAt = Frame.At
                if (VisibleStartedAt >= 0.0):
                    set Pending = false
                    if (HadHiddenApproach? and HitAt >= VisibleStartedAt and Frame.At - VisibleStartedAt <= OpeningBudget):
                        set Pending = true
                        set ReturnStartedAt = Frame.At
                    set VisibleStartedAt = -1.0
                    set HitAt = -1.0
                if (Pending? and Frame.At - ReturnStartedAt >= 0.3):
                    set Pending = false
                    ConfirmExchange()
            set LastFrame = option{Frame}
        else:
            ResetObservation()

    RecordHit(At : float):void =
        if (Goal = 0 or Completed? or VisibleStartedAt < 0.0 or not HadHiddenApproach?):
            return
        if (Frame := LastFrame?, At >= Frame.At, At - Frame.At <= 0.25, At - VisibleStartedAt <= OpeningBudget - 0.2):
            if (Direction := (Frame.PlayerPosition - Frame.OpponentPosition).MakeUnitVector[]):
                set HitAt = At
                set HitPosition = Frame.PlayerPosition
                set HitDirection = Direction

    ConfirmExchange():void =
        if (Goal = 2):
            if (Previous := PreviousPosition?):
                if (Distance(Previous, HitPosition) < MinimumReposition or DotProduct(PreviousDirection, HitDirection) > AngleDotLimit):
                    return
            else:
                set PreviousPosition = option{HitPosition}
                set PreviousDirection = HitDirection
                return
        set PreviousPosition = option{HitPosition}
        set PreviousDirection = HitDirection
        set Progress += 1
        if (Progress >= 5):
            set Completed = true

    FinishWithElimination(At : float):void =
        if (Goal > 0, not Completed?, HadHiddenApproach?, VisibleStartedAt >= 0.0, HitAt >= VisibleStartedAt, At >= HitAt, At - HitAt <= 0.3, At - VisibleStartedAt <= OpeningBudget):
            ConfirmExchange()
        ResetObservation()

    Instruction(H : logic):message =
        Budget := CoachElapsedText(OpeningBudget)
        if (Goal = 2):
            return CoachLanguage("Hit, then return out of sight or eliminate the opponent within {Budget}. Change position and angle between exchanges. The first qualifying exchange sets the reference. Progress can continue across rounds.", "פגע וחזור מחוץ לטווח הראייה או חסל את היריב בתוך {Budget}. שנה עמדה וזווית בין החילופים. החילוף התקף הראשון קובע את נקודת הייחוס. אפשר להמשיך את ההתקדמות בין סיבובים.", H)
        return CoachLanguage("Begin out of sight. Hit, then return out of sight or eliminate the opponent within {Budget}. Stay out of sight briefly between attempts. Complete five exchanges across one or more rounds.", "התחל מחוץ לטווח הראייה. פגע וחזור מחוץ לטווח הראייה או חסל את היריב בתוך {Budget}. הישאר לרגע מחוץ לטווח הראייה בין הניסיונות. השלם חמישה חילופים בסיבוב אחד או יותר.", H)

    Status(H : logic):message =
        Budget := CoachElapsedText(OpeningBudget)
        if (Goal = 2):
            return CoachLanguage("ANGLE PRACTICE  {Progress}/5\nSight interval target: {Budget}", "תרגול זוויות  {Progress}/5\nחלון ראייה עד {Budget}", H)
        return CoachLanguage("OPENING PRACTICE  {Progress}/5\nSight interval target: {Budget}", "תרגול פתיחות  {Progress}/5\nחלון ראייה עד {Budget}", H)
