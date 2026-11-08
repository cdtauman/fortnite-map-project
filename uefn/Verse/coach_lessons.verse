using { /Verse.org/Simulation }

coach_lesson_reason := enum:
    GeneralTechnique
    HeightDisadvantage
    LongSightInterval
    LateralPreference

coach_lesson_recommendation := struct:
    Lesson : int = 0
    Reason : coach_lesson_reason = coach_lesson_reason.GeneralTechnique

# One decision feeds the round, analysis, lesson button and spoken coaching.
CoachRecommendLesson(Training : coach_training_session)<transacts>:coach_lesson_recommendation =
    Context := CoachReviewContext(Training)
    if (Context.HasPositionSample? and Context.OpponentHeightAdvantage > 200.0):
        return coach_lesson_recommendation{Lesson := 1, Reason := coach_lesson_reason.HeightDisadvantage}
    if (Context.HasPositionSample? and Context.VisibleRun >= 1.5):
        return coach_lesson_recommendation{Lesson := 0, Reason := coach_lesson_reason.LongSightInterval}
    if (Training.Habits.Confidence() > 0.35 and Abs(Training.Habits.LeftProbability() - 0.5) > 0.18):
        return coach_lesson_recommendation{Lesson := 1, Reason := coach_lesson_reason.LateralPreference}
    return coach_lesson_recommendation{}

CoachRecommendationSummary(Training : coach_training_session, H : logic):string =
    Recommendation := CoachRecommendLesson(Training)
    if (Recommendation.Reason = coach_lesson_reason.HeightDisadvantage):
        if (H?):
            return "המיקוד המומלץ: שינוי תזמון וזוויות. היריב היה גבוה יותר סמוך לפגיעה שנבחרה; תרגל מעבר לעמדה אחרת לפני אתגור הזווית. היעד: חמישה חילופים תקפים של פגיעה וחזרה, עם שינוי עמדה וזווית."
        return "Suggested focus: timing and angles. The opponent was higher near the selected hit; practice repositioning before challenging that angle. Goal: five qualifying hit-and-return exchanges with changes of position and angle."
    if (Recommendation.Reason = coach_lesson_reason.LongSightInterval):
        if (H?):
            return "המיקוד המומלץ: פתיחות מוגנות. לפני הפגיעה נרשם רצף ראייה ממושך; תרגל הזדמנות קצרה וחזרה מחוץ לקו הראייה. היעד: חמישה חילופים תקפים של פגיעה וחזרה."
        return "Suggested focus: protected openings. A long sight interval was recorded before the hit; practice a short opportunity and return out of sight. Goal: five qualifying hit-and-return exchanges."
    if (Recommendation.Reason = coach_lesson_reason.LateralPreference):
        if (H?):
            return "המיקוד המומלץ: שינוי תזמון וזוויות. בהיסטוריית התנועה שנצפתה נמדדה נטייה לצד אחד; זו המלצה לפי דפוס, ולא הסיבה המוכחת לפגיעה המסוימת. היעד: חמישה חילופים תקפים מעמדות וזוויות משתנות."
        return "Suggested focus: timing and angles. Observed movement history favors one side. This pattern suggests practice; it does not establish the cause of this hit. Goal: five qualifying exchanges from changing positions and angles."
    if (H?):
        return "נקודת פתיחה לתרגול: פתיחות מוגנות. אין כאן אות מסוים שמצדיק אבחון טכניקה. היעד: חמישה חילופים תקפים של פגיעה וחזרה; אפשר לבחור כל שיעור אחר."
    return "Practice starting point: protected openings. There is no specific signal here to diagnose a technique. Goal: five qualifying hit-and-return exchanges; you can choose any other lesson."

CoachLessonSteps(Lesson : int)<computes>:int =
    if (Lesson = 2):
        return 7
    return 4

CoachLessonDuration(Lesson : int, Step : int)<computes>:float =
    if (Lesson = 2):
        return 3.5
    return 3.0

# General technique steps; this is not a claim to reconstruct an unobserved edit.
CoachLessonText(Lesson : int, Step : int, H : logic):message =
    if (Lesson = 0):
        if (Step = 0):
            return CoachLanguage("COVER FIRST\nChoose a solid piece of cover before starting the exchange. Your goal is to have a safe way out.", "קודם מחסה\nבחר מחסה לפני חילופי הירי. המטרה היא שתהיה לך דרך בטוחה לסגת.", H)
        if (Step = 1):
            return CoachLanguage("OPEN A SMALL ANGLE\nShow only enough of your character to line up the shot. Stay close to the edge of cover.", "פתח זווית קטנה\nחשוף רק את מה שנדרש כדי לכוון. הישאר קרוב לשפת המחסה.", H)
        if (Step = 2):
            return CoachLanguage("ONE SHOT, THEN RESET\nTake your shot and return behind cover. Avoid turning one opportunity into a long exposed trade.", "ירייה וחזרה\nירה וחזור למחסה. אל תהפוך הזדמנות קצרה לחילופי ירי ממושכים וחשופים.", H)
        return CoachLanguage("PRACTICE WITH PURPOSE\nRepeat five controlled peeks. Then try the same decision in your next fight.", "תרגול עם מטרה\nחזור על חמש הצצות מבוקרות. אחר כך נסה לקבל את אותה החלטה בקרב הבא.", H)
    if (Lesson = 1):
        if (Step = 0):
            return CoachLanguage("CHOOSE A SECOND ANGLE\nFind two protected positions. When the opponent controls your current line or has height, change the angle before pushing. Avoid repeating the same exposed approach.", "בחר זווית שנייה\nמצא שתי עמדות מוגנות. כשהיריב שולט בקו הנוכחי או מחזיק גובה, שנה זווית לפני התקדמות. הימנע מחזרה על אותה גישה חשופה.", H)
        if (Step = 1):
            return CoachLanguage("CHANGE THE TIMING\nPause behind cover, reposition, and let the next opening come from a different angle.", "שנה את התזמון\nעצור במחסה, שנה עמדה ופתח את ההזדמנות הבאה מזווית אחרת.", H)
        if (Step = 2):
            return CoachLanguage("KEEP THE SAFE EXIT\nAn unpredictable move still needs cover. Do not cross an open lane only to be different.", "שמור על יציאה בטוחה\nגם מהלך לא צפוי צריך מחסה. אל תחצה שטח פתוח רק כדי לשנות.", H)
        return CoachLanguage("APPLY THE CHANGE\nAlternate two protected positions, then choose based on where the opponent is looking.", "יישם את השינוי\nהחלף בין שתי עמדות מוגנות ובחר לפי הכיוון שאליו היריב מסתכל.", H)
    if (Step = 0):
        return CoachLanguage("1 / 7 — SET UP THE ROUTE\nRamp toward a floor and cone above its exit, with a wall beyond them. This plan explains the order; practice uses your normal build and edit controls.", "1 / 7 — הכנת המסלול\nמדרגה לכיוון רצפה וקונוס מעל היציאה, וקיר מעבר להם. התרשים מסביר את הסדר; בתרגול משתמשים בכפתורי הבנייה והעריכה הרגילים שלך.", H)
    if (Step = 1):
        return CoachLanguage("2 / 7 — FLOOR FIRST\nOpen the floor on the side you plan to travel through. Confirm the edit before reaching the blocked exit. Keep your crosshair near the cone for the next selection.", "2 / 7 — קודם הרצפה\nפתח ברצפה את הצד שבו תרצה לעבור. אשר לפני שתגיע ליציאה החסומה. שמור את הכוונת קרוב לקונוס לבחירה הבאה.", H)
    if (Step = 2):
        return CoachLanguage("3 / 7 — CONE SECOND\nSelect the cone rather than editing the floor again. Open a route that lines up with the floor opening. Confirm, then move your crosshair toward the wall.", "3 / 7 — אחר כך הקונוס\nבחר את הקונוס במקום לערוך שוב את הרצפה. פתח מעבר שממשיך את הפתח ברצפה. אשר והעבר את הכוונת לכיוון הקיר.", H)
    if (Step = 3):
        return CoachLanguage("4 / 7 — WALL THIRD\nOpen a passable wall edit before running into the wall. Start slowly enough to select the intended piece and complete the opening.", "4 / 7 — הקיר שלישי\nפתח בקיר מעבר שאפשר לעבור בו לפני שתיתקע בו. התחל לאט מספיק כדי לבחור את החלק הנכון ולהשלים את הפתח.", H)
    if (Step = 4):
        return CoachLanguage("5 / 7 — MOVE THROUGH\nConnect the three confirmed edits with movement up the ramp and through the exit. If you collide, isolate that transition instead of repeating the whole sequence faster.", "5 / 7 — תנועה דרך המעבר\nחבר את שלוש העריכות שאושרו לתנועה במעלה המדרגה ודרך היציאה. אם נתקעת, תרגל את המעבר המסוים במקום לחזור מהר יותר על הכול.", H)
    if (Step = 5):
        return CoachLanguage("6 / 7 — REPEAT WITH CONTROL\nReset and repeat the same route. Aim for five clean repetitions at a comfortable pace before increasing speed. Playback controls the demonstration; your practice course runs at normal game speed.", "6 / 7 — חזרה בשליטה\nאפס וחזור על אותו מסלול. כוון לחמש חזרות נקיות בקצב נוח לפני הגברת המהירות. בקרי ההפעלה שולטים בהדגמה; מסלול התרגול פועל במהירות המשחק הרגילה.", H)
    return CoachLanguage("7 / 7 — PRACTICE, THEN CHOOSE\nTry the triple-sequence course. Use the technique in a fight when it gives you a protected route or useful angle. A damage event alone does not prove you needed a triple edit.", "7 / 7 — לתרגל ואז לבחור\nנסה את מסלול הרצף המשולש. השתמש בטכניקה בקרב כשהיא מספקת מעבר מוגן או זווית מועילה. פגיעה לבדה אינה מוכיחה שהיית צריך טריפל אדיט.", H)
