# מאגר חלקים וחידוש בין קרבות — הכנת העורך

8 בנובמבר 2026, ProCoachLab, UEFN 43.00 CL59596594. ההכנה הושלמה בעורך; חידוש המאגר במשחק עדיין לא אומת. אין השלמת יריב פרו או פתיחת שער בנייה.

## מה נשמר

- 64 מופעים של ארבעת ה־Blueprint שנוצרו ב־186: 16 קירות, רצפות, רמפות וקונוסים. לכל מופע תג סוג יחיד, מיקום חניה ייחודי ותצורת נזק מקורית של הנכס שבבעלות הפרויקט.
- שכבת Runtime נפרדת `PCL_DL_NativePool`, עם 64 חברים בלבד, במצב התחלתי Unloaded. החלקים נמצאים באזור חניה תת־קרקעי מחוץ לזירות; `is_spatially_loaded=False` במופעים כדי שמצב השכבה יהיה תנאי הטעינה, ולא קרבת שחקן לאזור החניה. אין כאן טענת חיסכון בזיכרון.
- שני Level Sequence חדשים: פריקה למשך 90 פריימים, וטעינה במצב Loaded לפריימים 0–60 ואז Activated לפריימים 60–90, בקצב 30 פריימים לשנייה. הסעיפים מוגדרים Keep State.
- שני Cinematic Sequence Devices המחוברים לרצפים, ללא AutoPlay או לולאה, Everyone, ללא חסימת קלט, HUD גלוי ו־ForceKeepState.
- `coach_native_pool_reset_device` הוצב וחובר אל בקר המבנים, עם ספירה צפויה 16 מכל סוג. `Enabled=False`, `RenewNativePoolBetweenRounds=False`, `UseNativePiecePool=False` וכל ארבעת שערי הקבלה False.

המקור מ־186 כבר התקמפל ונשמר. ב־188 לא שונה מקור Verse ולכן לא הורצה קומפילציה חוזרת. מקור החידוש דורש היעלמות אובייקטים ישנים וגילוי מלא של מאגר חדש לפני מסירתו לקרב; זו הגנה כתובה, לא תוצאה נצפית. הבריאות, הבעלות ומשבצות הבנייה אינן נלמדות מספירת תגיות.

## ראיות

| היקף | רשומה |
|---|---|
| ארבעת הנכסים ותגיותיהם | `.local/native-pool186-bank-authoring.json` |
| מקור וקומפילציה קודמת | `.local/native-pool186-source-correction.json` |
| שכבה, רצפים ומצבי סעיפים | `.local/native-pool188-runtime-assets.json` |
| 64 מופעים, חברות שכבה, תגיות, חניה ושמירה True | `.local/native-pool188-placement.json` |
| חיבורי הבקרים, ההגדרות והשערים הכבויים | `.local/native-pool188-controls.json` |
| אימות עורך יחיד: 8 נבדקו, 8 תקינים, 0 שגיאות/אזהרות/דילוגים | `.local/native-pool188-validation.json` |
| פריסה וחיבורים לשחזור | `uefn/native-pool-bank.json` |

מתכונים שכבר הושלמו: `tools/author_native_pool_runtime.py`, `tools/finish_native_pool_bank.py --finish`, `tools/author_native_pool_controls.py`. אין להריץ שוב. בקריאת החברות הראשונה נעשה שימוש בשם Python שלא קיים במופע המותקן; ההצבה עצמה כבר הסתיימה. התיקון השתמש במאפיין הציבורי `data_layer_assets` ובמצב `--finish` בלבד, בלי להציב חלקים מחדש. כל 64 המופעים והחברות נקראו ונשמרו לאחר מכן.

לא נשלחו PushChanges, StartSession, StartGame, פקודת ניגון רצף או קלט מחשב. המשתמש יכול להמשיך בסשן שהועלה ב־187; ההכנה החדשה אינה קבלת משחק או מסירה.

## מחקר טרי והסיכון שנותר

[Epic מתעדת טעינה, הפעלה ופריקה של שכבות ב־UEFN דרך Sequencer](https://dev.epicgames.com/documentation/fortnite/streaming-and-hlods-in-unreal-editor-for-fortnite). [תיעוד ההתקן](https://dev.epicgames.com/documentation/en-us/fortnite/using-cinematic-sequence-device-in-unreal-editor-for-fortnite) מגדיר AutoPlay, קהל ושמירת מצב בסיום; הוא אינו מבטיח שחזור בריאות או בנייה מקורית לאחר הרס.

[הערות 43.00](https://dev.epicgames.com/documentation/en-us/fortnite/43-00-fortnite-ecosystem-updates-and-release-notes) נקראו. [דיון על חישוב הזיכרון ב־43.00, עם תשובת Epic](https://forums.unrealengine.com/t/uefn-43-00-publishing-memory-jumps-from-53-to-124-after-update/2848716) מבהיר ששכבה אינה הוכחה לתקציב זיכרון קטן; קבלת ביצועים וחישוב זיכרון נשארים במסירת הסיום.

[דיווחי יוצרים על התנגשויות בלתי נראות לאחר פריקה וטעינה](https://forums.unrealengine.com/t/data-layer-object-destruction-broken-and-invisible-collision-issues/2657519) כוללים תוצאות סותרות לגבי הפרדת זמנים ויצירת רצפים מחדש. אלו דיווחים היסטוריים, לא שחזור בגרסה המותקנת ולא פתרון מוכח. אין להוסיף השהיות חוזרות על סמך ניחוש. נדרשת קבלה של זהות האובייקטים, היעלמות התנגשות ישנה, חזרה לתנוחת מקור ונזק/הרס לפני שימוש במאגר.

הצעד הבא בליבת המוצר עדיין דורש הכרעת נזק/בריאות, משבצת ובעלות עם נאמנות לאינטראקציית השחקן. מנגנון חידוש מוכן אינו עוקף פערים אלה. אין הרשאה לסבב משחק נוסף; אישור185 נוצל.
