# תצפית עורך120 — בורר קיר וסוגParticipant

עדכון תלות123: קריאה חדשה של Type ו־IsDirty דרך החיבור הרשמי עדיין מחזירה CoachGuardType ו־False, עם Connected/CanStart. ממתינה אותה בחירה ידנית שהוכנה ב־120; תיקון הלמידה העצמאי121–122 הושלם בלי לשנות אותה. אין ריצת משחק123 או שינוי קוד. זו הפעם השלישית ברצף העבודה שבה אותה תלות נותרה פתוחה; לאחר סיום התיקון העצמאי לא זוהה צעד יעיל נוסף במסלול הקריטי שאינו תלוי בה. המטרה מסומנת כחסומה, לא כהושלמה.

בבדיקה123 נקראו מחדש רשימת כלי MCP והתיעוד הרשמי. חיפוש מדויק כיסה Participant עם Character Type, שינויי43.00, בעיות בחירה מדווחות ו־Custom Test Player. [Character Definitions](https://dev.epicgames.com/documentation/fortnite/using-npc-character-definitions-in-unreal-editor-for-fortnite?lang=en-US) עדיין מציג Participant ללא פירוט של פעולות בנייה; [Debug Settings](https://dev.epicgames.com/documentation/fortnite/debug-settings-in-fortnite-creative?lang=en-US) מציג בחירת Character Definition עבור שחקן בדיקה, ומבהיר שהגדרות האבחון אינן משפיעות על אי מפורסם. נבדקו גם [הערות43.00](https://dev.epicgames.com/documentation/en-us/fortnite/43-00-fortnite-ecosystem-updates-and-release-notes). לא זוהתה במשטחים שנבדקו פעולה ייעודית חדשה לבחירת הסוג. אין מכאן מסקנת היעדר API כללית, דחיית המחלקה בידי העורך או הוכחת אי־אפשרות לבניית הבוט.

לאחר תגובת המשתמש: לקרוא את הסוג בפועל ולבדוק את הנכס לפני חיבור Spawner פרטי. אם הבחירה נשארה Guard, לתעד את תוצאת הפעולה הידנית המדויקת ולבחור חקירה מבחינה חדשה; לא לחזור על לחיצות, הודעות שינוי, כפיית מחלקות או בנאים שנפסלו. יתר דרישות R01–R25 נשארות פתוחות; אין להחליף את יעד המוצר בגלל התלות הזאת. המצב המאומת האחרון הוא checkpoint122.

7 בנובמבר 2026, UEFN43.00 CL59596594. זו תצפית עורך בלבד; המשחק האחרון וה־checkpoint האחרון נשארים119. לא נוצרה ריצת120, לא השתנו קובצי Verse או נכסי Art/NPC ולא נפתח אף שער בנייה. המטרה R01–R25 פתוחה.

## הבורר המקורי של הקיר

תצפית Windows חדשה הראתה שה־Message Log כבר אינו פתוח, אך Session Inspector עדיין מכסה את החלון הראשי. הוא נסגר דרך חלון העזר שהוחזר בפועל ו־screenshot משלו. לא נעשהAlt+F4. בשדהSpawnedWallAsset של מכשיר הבריאות הפרטי והכבוי נפתח הבורר המקורי.

חיפוש `PCL_BP_GridWallCandidate` הסתיים בהודעתNo results. חיפושGrid הציג נכסי ספרייה; חיפושPCL הציג, בין היתר,PlayerBuildablePropCandidate,DamageSpawnWall ו־DamageControl. זו בקרה חיובית שהבורר מקבל נכסים מסוימים מאותה תיקיית פרויקט, לא הוכחת סיבת הסינון של המועמד המקורי ולא מסקנת אי־אפשרות כללית. לא בוצעה בחירה או שינוי מסננים. הבורר נסגר, חיבור המחשב אופס, ובקריאה חוזרת הבחירה נשארהPlayerBuildablePropCandidate_C.

התוצאה מקדמת מעבר מבדיקות כתיבה מיידיות115–116 לבדיקת הבורר עצמו; אין לחזור להודעותALWAYS, לשינויAssetForEditor או לכפיית מחלקה. לא נצפהSpawnProp עםGridWallCandidate. Native pool119 ממשיך להיות ראיה נפרדת על מופע שהוצב מראש.

## סוג הדמות

העותק הפרטיCoachParticipantCandidate נבדק נקי ותקין ונפתח דרךMCP. צילום של עורך הנכס עצמו הציגGuard. הרשימה נפתחה ובהCustom,Guard,Participant,Wildlife. לחיצה עלParticipant לא שינתה את הערך הנצפה, וגם ניסיון חיפוש ממוקד סגר את הרשימה בלי שינוי נצפה. פקודות קלט לחלון המשני עלולות לשנות מיקוד; זו אפשרות הסבר בלבד, לא שורש תקלה שהוכח. אין ראיה מכאן שהעורך דחה את המחלקה, ואין להכריח יצירת אובייקט, לשנות מסנן או להחליף מסלול דרךבנאי.

השליטה שוחררה מיד לאחר סיום הניסיון. `.local/participant120-after-ui.json` מאמתGuard,נכס נקי/תקין וכלhashיArt/NPC זהים להכנת119,Connected/CanStart. `.local/native-picker120-before-participant.json` מכיל גם בדיקת בחירת הקיר וגיבוי העותק לפני הניסיון. לא נכתב נכס ראשי.

ממתינה בקשת משתמש אחת חדשה: בחלון CoachParticipantCandidate לבחור Type→Participant ולשמור Ctrl+S, ואז לדווח מה מוצג. זו הגדרת עורך ולא בדיקת משחק. בקשת סגירת חלונות העזר הישנה נפתרה ואינה נדרשת. אין להמשיך בפעולות התלויות בבחירת Participant לפני תשובה או תצפית מוסמכת חדשה שהסוג השתנה. אין לחזור על לחיצות/מיקוד/חיפוש ברשימה ללא מסלול שונה ומבחין.

## מחקר מדויק והחלופות

נחפשו כעת ארבעה כיוונים: creative_prop_asset עם Building Blueprint,‏ SpawnProp עם BuildingWall, המרת BuildingProp ודיווחי43.00 על בנייה מקורית. נבדקו [SpawnProp](https://dev.epicgames.com/documentation/en-us/fortnite/verse-api/fortnitedotcom/devices/spawnprop) ו־[Procedural Building](https://dev.epicgames.com/documentation/en-us/fortnite/procedural-building-template-in-unreal-editor-for-fortnite). התבנית מתארת מיפוי @editable ל־BuildingProp; היא אינה מוכיחה הקצאת קיר שחקן מקורי. חיפוש בקובץ Assets.digest המקומי לא מצא שיקוף של GridWallCandidate או creative_prop_asset מתאים לחלופה ישירה בקוד. זו תוצאת הקובץ המותקן, לא מסקנה כללית על כל גרסה.

[Character Definitions](https://dev.epicgames.com/documentation/fortnite/using-npc-character-definitions-in-unreal-editor-for-fortnite?lang=en-US) מציג Participant ללא תיאור מפורט. הרשימה המקומית מאשרת שהוא מוצג, אך אינה מוכיחה פעולת בנייה או התאמה לפרסום. החלופה המיידית היא בחירה ידנית בודדת בממשק באותו עותק; לא בוצעה עקיפת מסנן.

במקביל נחפשו Player Input, מתכוני בנייה, fort_item ופעולות Participant. נבדק מודול Input/Character ב־digest המקומי: יש WeaponPrimary/Secondary,‏ Reload,‏ Traversal ו־Interact/Move, עם סימוני Experimental בחלקם. [Player Input](https://dev.epicgames.com/documentation/fortnite/player-input-in-verse-in-unreal-editor-for-fortnite?lang=en-US) מתאר אירועים ומיפויים; אינו מוכיח הפעלה אוטונומית של בנייה מקורית. מערכת בנייה משותפת מותאמת היא חלופה אפשרית למחקר, אך התחושה, הביצועים והשיתוף עם בנייה מקורית טרם אומתו. דרישת המוצר לא הוחלפה.

החיפוש נעצר כעת מפני שהתיעוד ומשטחי העורך שנבדקו אינם מספקים ראיה חדשה לפעולת בנייה. הבדיקה המבחינה הבאה היא סוג Participant שנשמר באמת ועובר אימות לפני שינוי Spawner פרטי. אין מכאן הבטחת בנייה או הורדת דרישות.
