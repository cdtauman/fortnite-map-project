# Stages record workflow, not mastery: 0 none, 1 lesson, 2 practice,
# 3 application round, 4 sequence completed.
coach_training_plan := class<final><persistable>:
    Revision : int = 0
    Stage : int = 0
    Lesson : int = 0
    Reason : int = 0
    SourceRound : int = 0
    PracticeProgress : int = 0
    CompletedPlans : int = 0

CopyCoachTrainingPlan<constructor>(Source : coach_training_plan)<transacts> := coach_training_plan:
    Revision := Source.Revision
    Stage := Source.Stage
    Lesson := Source.Lesson
    Reason := Source.Reason
    SourceRound := Source.SourceRound
    PracticeProgress := Source.PracticeProgress
    CompletedPlans := Source.CompletedPlans

CoachPlanReasonCode(Reason : coach_lesson_reason)<computes>:int =
    if (Reason = coach_lesson_reason.HeightDisadvantage):
        return 1
    if (Reason = coach_lesson_reason.LongSightInterval):
        return 2
    if (Reason = coach_lesson_reason.LateralPreference):
        return 3
    return 0

CoachPlanFocusName(Lesson : int, H : logic)<computes>:string =
    if (H?):
        if (Lesson = 1):
            return "שינוי תזמון וזוויות"
        return "פתיחות מוגנות"
    if (Lesson = 1):
        return "Timing and angles"
    return "Protected openings"

CoachTrainingPlanText(Plan : coach_training_plan, H : logic):message =
    Name := CoachPlanFocusName(Plan.Lesson, H)
    var Reason : string = "A general practice starting point."
    var Step : string = "1 / 3: study the lesson, then choose when you are ready to practice."
    if (Plan.Reason = 1):
        set Reason = "The coach was higher near the selected hit in round {Plan.SourceRound}."
    else if (Plan.Reason = 2):
        set Reason = "A long sight interval preceded the selected hit in round {Plan.SourceRound}."
    else if (Plan.Reason = 3):
        set Reason = "Observed movement history favored one side when this plan was chosen."
    if (Plan.Stage = 2):
        set Step = "2 / 3: five qualifying exchanges. Saved progress: {Plan.PracticeProgress}/5."
    else if (Plan.Stage = 3):
        set Step = "3 / 3: try the technique in a separate round without the exercise counter."
    else if (Plan.Stage = 4):
        set Step = "Sequence completed: a focused exercise and a separate application round were recorded. This does not establish mastery."
    if (H?):
        set Reason = "נקודת פתיחה כללית לתרגול."
        set Step = "1 / 3: למד את השיעור ובחר מתי אתה מוכן לתרגול."
        if (Plan.Reason = 1):
            set Reason = "המאמן היה גבוה יותר סמוך לפגיעה שנבחרה בסיבוב {Plan.SourceRound}."
        else if (Plan.Reason = 2):
            set Reason = "לפני הפגיעה שנבחרה בסיבוב {Plan.SourceRound} נמדד רצף ראייה ממושך."
        else if (Plan.Reason = 3):
            set Reason = "בעת בחירת התוכנית, היסטוריית התנועה שנצפתה נטתה לצד אחד."
        if (Plan.Stage = 2):
            set Step = "2 / 3: חמישה חילופים תקפים. התקדמות שנשמרה: {Plan.PracticeProgress}/5."
        else if (Plan.Stage = 3):
            set Step = "3 / 3: נסה ליישם את הטכניקה בסיבוב נפרד, בלי מונה התרגול."
        else if (Plan.Stage = 4):
            set Step = "הרצף הושלם: נרשמו תרגול ממוקד וקרב יישום נפרד. אין בכך הוכחה לשליטה בטכניקה."
    return CoachMessage("{Name}\n{Reason}\n\n{Step}")
