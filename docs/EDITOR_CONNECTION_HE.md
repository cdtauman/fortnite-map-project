# התחלת עבודה וחיבור לעורך

עודכן: 8 בנובמבר 2026. הוראות ההרצה ההיסטוריות בהמשך כפופות ל־AGENTS.md: כעת מותרת הכנת מקור/נכסים וחיווט; אין להפעיל משחק או ניסוי נוסף. החריג החד־פעמי נוצל160.

## התוכנה הנדרשת

להתקין דרך Epic Games Launcher את **Unreal Editor for Fortnite (UEFN)**. Fortnite הקיים משמש לבדיקת האי. Unreal Engine הרגיל ותוספיו אינם דרישת ההתקנה המופיעה במדריך UEFN הרשמי.

[מדריך ההתקנה הרשמי](https://dev.epicgames.com/documentation/en-us/fortnite/install-and-launch-fortnite-creative-and-unreal-editor-for-fortnite).

## חיבור MCP הרשמי

כאשר העורך פתוח:

1. לפתוח `Edit → Editor Preferences`.
2. לעבור ל־`Agentic Workflows → Model Context Protocol`.
3. להפעיל `Start Server` אם הוא אינו פועל.
4. להפעיל `Generate Client Config` עבור הלקוח הזמין בתפריט.
5. להשתמש בכתובת שבקובץ שנוצר, ולא לנחש נתיב HTTP או לשנות הגדרות אבטחה. המדריך הנוכחי מתאר קובץ `.mcp.json` בתיקיית `Fortnite/FortniteGame`.

זה המסלול המתועד. בהמשך אותו יום זוהה שרת MCP מקומי פעיל בעורך על `http://127.0.0.1:8000/mcp`, והחיבור אומת באמצעות גילוי סכמות, זיהוי ProCoachLab, כתיבת Verse, קומפילציה, הצבת נכסים ושמירתם. לא נדרשה הפעלת קלט בממשק כדי לבצע את עבודת המפה.

[תיעוד UEFN MCP](https://dev.epicgames.com/documentation/fortnite/uefn-mcp).

## כלי מקומי לפרויקט

### קריאת חיווט NPC — ממצא169

בספאונר הראשי, `GetComponents` מחזיר את `NPCBehaviorScriptComponent` ואת `NPCCharacterDefinitionComponent`. דרך `ObjectToolset.GetProperties` על הרכיבים הציבוריים נקראו `nPCBehaviorScript`, `nPCCharacterDefinition` ו־`nPCCharacterModifiers`; תכונות אלה אינן באותו נתיב על Actor הספאונר. כישלון קריאה על אובייקט שגוי או רשימת Classic ריקה אינם מסקנה שאין API. משם נקראו נכס CoachOpponent, מאפיין ההתנהגות ונתוני החיים, ללא גישה לרכיב התצוגה הפרטי. ראיות: `.local/npc-components169.json`, `.local/npc-wiring169.json`.

`tools/author_opponent_setup.py` כבר השלים שינוי כיוון ו־Leash ושמירה; אין להריצו שוב אוטומטית. אין לשנות דרך נתיב זה את Items שנדחה כ־template-only או לעקוף הרשאות/סינון מחלקות. שיוך סקריפט בעורך אינו הוכחת הפעלתו בזמן משחק.

### תצורת נכס לעומת מופע — ממצא178

בעותק הרמפה שבבעלות הפרויקט, קריאתCDOהראתה bCanBeDamaged=Falseאבל שני המופעים שהוצבו דיווחוTrue. ההבדל תוקן באמצעות SetPropertiesהציבורי על המופעים ונקראFalse; אין להסיק שתצורתCDOמוכיחה את מצב המופע. לאחר שלבי התצורה נראו גם גבולות שהוסטו ביחס להצבה הראשונה; הוחלה שוב תנוחת הפריסה הרגילה, ונקראו תנוחה וגבולות סופיים. לא בודדה הסיבה לשינוי בין פעולות התצורה, ואין לייחסו ל־APIמסוים. הרישום `final_placement` ב־`.local/duel-start178-authoring.json` הוא ראיית הפריסה האחרונה. זו קריאת מצב עורך, לא ניסוי משחק או היתר לעקוף setterשנדחה.

`tools/uefn_mcp.py` משתמש ב־SDK הרשמי ומקבל כתובת loopback מפורשת. הוא מאפשר גילוי זהות העורך וסכמות כלים, ובהמשך קריאה לכלי שנבדק בשמו המדויק. אין בו שירות מתווך חדש, שרת ציבורי או שמירת מפתחות. הוא אינו יודע להקים מפה בלי עורך מחובר.

הפעלת גילוי מ־PowerShell, עם הכתובת האמיתית במקום `EDITOR_URL`:

```powershell
.\.venv-uefn\Scripts\python.exe -X utf8 tools\uefn_mcp.py --url EDITOR_URL discover
```

קריאה לכלי תבוצע לאחר קריאת הסכמה ותוך שימוש בקובץ JSON מקומי עבור הארגומנטים:

```powershell
.\.venv-uefn\Scripts\python.exe -X utf8 tools\uefn_mcp.py --url EDITOR_URL call EXACT_TOOL_NAME --arguments-file .local\arguments.json
```

הדוגמאות הן תבניות פקודה; השמות והכתובת חייבים להגיע מגילוי אמיתי. `discover` אינו מפעיל כלי עריכה. פעולת `call` יכולה לשנות את הפרויקט בהתאם לכלי שנבחר. אחרי timeout או שגיאת תעבורה יש לבדוק מצב לפני ניסיון חוזר.

תיקיות `.local` ו־`.venv-uefn` מוחרגות מ־Git. אין לשמור קובצי חיבור המכילים סודות במאגר.

[SDK רשמי — לקוח](https://py.sdk.modelcontextprotocol.io/client/).

## בדיקות שבוצעו

הותקן SDK רשמי בגרסה 2.3.0 בסביבה המקומית המבודדת. עברו שתי בדיקות אינטגרציה: גילוי כלי, קריאה עם טקסט עברי וטיפול בשגיאת כלי מול שרת SDK בזיכרון; ואימות שהכתובת המתקבלת היא מקומית וללא סודות ב־URL. בבדיקת שגיאת כלי נמצא ותוקן מצב שבו תשובת `isError` הייתה עלולה להתקבל כתוצאה תקינה.

הבדיקות אינן חיבור HTTP לעורך ואינן קומפילציה או משחק. הפעלה לבדיקה חוזרת:

```powershell
.\.venv-uefn\Scripts\python.exe -X utf8 -m unittest discover -s tools -p test_uefn_mcp.py -v
```

בנוסף להן בוצעו לאחר מכן בדיקות מול העורך האמיתי: UEFN 43.00 CL-59596594 ניהל פרוטוקול 2025-11-25. הלקוח הותאם ל־`mode="legacy"` ועבר שוב את בדיקות ה־SDK. בקשות auto שהתעכבו בזמן פתיחת הפרויקט הושוו לבקשת HTTP ישירה ולמצב legacy שהצליחו. בקשות עריכה מבוצעות כעת ברצף, עם בדיקה אחרי כל שינוי.

`GetSessionStatus` החזיר `Connected`, `GetGameState` החזיר `Running`, והתקבלו אירועי Verse מהקרב. הפרטים וההיקף המדויק נמצאים ב־[מצב הבנייה](BUILD_STATE_HE.md). אלה ראיות לפרויקט הזה; יש לגלות ולאמת חיבור מחדש לאחר החלפת עורך או גרסה.

## סדר התחלת הפיתוח

אחרי החיבור נזהה גרסה ופרויקט, ניצור זירת ניסוי חדשה ונריץ P01–P05 מ־[חבילת ניסויי הבוט](BOT_CORE_PROBES_HE.md). רק לאחר קומפילציה ותצפית במשחק נסמן יכולות כעובדות. קוד יוצר/חנות עשוי להיות רלוונטי לפרסום ולמוצר בהמשך; הוא אינו משמש כתובת חיבור לעורך.
