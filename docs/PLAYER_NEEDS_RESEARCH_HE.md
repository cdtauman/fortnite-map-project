# מחקר ראשוני — צרכי שחקנים וגבולות הראיות

נבדק: **6 בנובמבר 2026**. מחקר שולחני קטן: שלושה דיוני שחקנים שנפתחו, דף מפה של יוצר ותיעוד רשמי רלוונטי. זהו מדגם נוחות ממוקד, לא מחקר שוק מייצג, מדידת ביקוש או אימות של מודל עסקי. תאריכי פרסום יחסיים שהוצגו בחיפוש ובדפים לא היו עקביים, ולכן אינם בסיס לדירוג עדכניות כאן.

## מה שחקנים מתארים

| תצפית מהמדגם | מקור | השערת מוצר לבדיקה |
|---|---|---|
| קושי ליישם מכניקות שנלמדו בתרגילים כשמופעל לחץ בקרב אמיתי. | [Help with getting better at fighting](https://www.reddit.com/r/FortniteCompetitive/comments/1v460jc/help_with_getting_better_at_fighting/) | לקשר כל תרגיל לחזרה לקרב עם אותו סוג החלטה/לחץ. |
| רצון במבנה והכוונה מדויקת למה לתרגל, לצד קושי להבין מדוע מהלך מקצועי עובד. | [Guidance on how to improve as an average player](https://www.reddit.com/r/FortniteCompetitive/comments/1umbtey/guidance_on_how_to_improve_as_an_average_player/) | המלצה אישית על חולשה ודוגמה טקטית, עם הסבר שאפשר לפעול לפיו. |
| אימון איטי וחזרות רבות עדיין מלווים בפספוסי עריכה וקושי בתזמון ובמיקום הכוונת. | [How can I stop missing my edits?](https://www.reddit.com/r/FortniteCompetitive/comments/1taoeof/how_can_i_stop_missing_my_edits/) | לזהות איזה מרכיב ברצף נכשל ולפרק אותו לתרגול, במקום רק להוריד מהירות. |

התגובות בדיונים מכילות עצות שונות ולעיתים סותרות. הן מספקות שפה ובעיות למחקר נוסף; אין להתייחס לכל עצה מקצועית שם כאמת מוכחת או כהסכמה של כלל השחקנים.

## דוגמת היצע קיים

דף היוצר של [Jivan — How to Build Map](https://www.fortnite.com/@jivantv/6483-9631-9857) מתאר שיעורי בנייה, עריכות, תעלות, מהלכי גובה ו־1V1, וכן תרגיל בנייה חופשית עם בוטים. זהו תיאור של היוצר, לא בדיקת משחק שבוצעה כאן. הוא מלמד שאוסף מצבי אימון והדרכות הוא חלק מההיצע הקיים; אין בו כשלעצמו ראיה למאמן אישי לומד במתכונת המבוקשת.

השערת הבידול שלנו: לחבר קרב אישי, אבחון מבוסס אירוע, הסבר, הדגמה, תרגיל וחזרה לקרב במסלול אחד שמכיר את השחקן. זוהי מסקנת תכנון מתוך החזון והמדגם, לא הוכחה שאין מוצר אחר שעושה זאת.

## בדיקת יכולות תומכות — ללא מסקנות של אי־אפשרות

- [Replays](https://dev.epicgames.com/documentation/en-us/fortnite/replays-feature-in-fortnite-creative) מתארים צפייה במשחק מוקלט מזוויות שונות. עדיין צריך להוכיח את הדרך להציע צפייה אוטומטית ברגע מסוים מתוך אי פעיל; קיום Replay כשלעצמו אינו מוכיח את השילוב הזה.
- [Cinematic Sequence Device API](https://dev.epicgames.com/documentation/en-us/fortnite/verse-api/fortnitedotcom/devices/cinematic_sequence_device) מתעד שליטה בזמן/פריים ובקצב של רצף. זה בסיס לחקירת הדגמות מחוברות לתוכן, ולא ראיה להקלטה אוטומטית של קרב חי או לשינוי כל סימולציית המשחק.
- [LLM Characters as Gameplay Drivers](https://dev.epicgames.com/documentation/fortnite/llm-characters-as-gameplay-drivers-in-fortnite) מתאר Structured Output וחיבור תגובות למנגנוני משחק. הוא תומך בחקירת מאמן אינטראקטיבי; הבנת הקרב תלויה במידע אמין שנזין לו.
- [LLM Caption UI](https://dev.epicgames.com/documentation/fortnite/llm-caption-ui-in-fortnite) מתאר חיבור דיבור המאמן לכתוביות. בחירת שפה, איכות התשובות והשהיה ייבדקו בנפרד.
- [Guard Actions](https://dev.epicgames.com/documentation/fortnite/verse-api/fortnitedotcom/ai/guard_actions_component) נבדק כמקור לפעולות הקרב המתועדות. לא אומתה כאן יכולת בנייה/עריכה מלאה של בוט.
- [Persona](https://dev.epicgames.com/documentation/fortnite/developing-personas-overview-in-unreal-editor-for-fortnite) ו־[Verse Persistence](https://dev.epicgames.com/documentation/en-us/fortnite/using-persistable-data-in-verse) הם משטחים נפרדים לשיחה ולפרופיל מתמשך. יש לתכנן את החיבור, ולא להניח שזיכרון השיחה הוא הזיכרון האישי של המאמן.

## המשך מחקר מוצע

### עדכון שפות — 6 בנובמבר 2026

המשתמש בחר באנגלית קולית תחילה, עם יעד לעברית בטקסט והרחבת קול לשפות נוספות בהמשך. נבדקו מחדש תיעוד השפות, תיעוד הלוקליזציה, כתוביות וחיפושים ממוקדים על Hebrew/RTL/גופנים ב־UEFN.

ה־[FAQ הרשמי של LLM Conversations](https://dev.epicgames.com/documentation/fortnite/llm-conversations-in-unreal-editor-for-fortnite) מתאר תגובות באנגלית במערכת השיחה המובנית. זו מסקנה בהיקף המערכת המתועדת, ולא מסקנה שכל דרך קולית אחרת בשפה נוספת בלתי אפשרית. טקסט עברי, תרגום של משוב דינמי ושיחה קולית רב־לשונית הם מסלולי בדיקה נפרדים. תיעוד RTL כללי של Unreal Engine אינו הוכחה מספקת להתנהגות ב־UEFN.

הניסוי המוצע לשלב המימוש: משפט עברי עם מספרים ומונחי משחק באנגלית, ווידג׳ט לקוח, שיחה קצרה באנגלית וכתוביות. נבדוק קריאות, כיוון, תזמון ונתיב תרגום לפני הבטחות תמיכה רחבות.

### המשך מחקר עם שחקנים

לאחר בחירת חוויית הליבה: להשוות כמה מפות בפועל, לדבר עם שחקנים מכמה רמות ולבדוק אבטיפוס של קרב → אבחון → תרגיל. שאלות המחקר: האם ההסבר מובן; האם התרגיל מתאים לטעות; האם השיפור עובר חזרה לקרב; והאם השחקן רוצה לחזור לאימון אישי נוסף.
