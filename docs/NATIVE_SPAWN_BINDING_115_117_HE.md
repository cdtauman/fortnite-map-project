# חיבור נכס קיר מקורי ובדיקת רישום פנימי — 115–117

7 בנובמבר2026, UEFN43.00 CL59596594. היעד נשאר חידוש חלקים מקוריים אחרי הרס ואינטראקציה אמינה עם השחקן. לא בוצע משחק חדש בסבב הזה; המשחק האחרון הוא114. אין כאן מסקנת אי־אפשרות שלSpawnProp או בנייה מקורית.

## מה נבדק

נכס `PCL_BP_GridWallCandidate` נמצא תקין; בדיקתPython ציבורית אישרה שה־CDO שלו הואBuildingWall. נקראו בלבד:Team2,‏ SLOT_Wall,‏ bIsPlayerBuildable=True,‏ bPlayerPlaced=False, רישום מבניTrue, תמיכה כפויהFalse ו־bAllowTeamDamage=True. שניAttributeInitKeys ריקים. לא שונו ברירות המחדל, ולא נוסה שוב השדהbPlayerPlaced שנדחה בעבר ב־CDO.

נבדקו שתי השערות כתיבה שונות עלSpawnedWallAsset של מכשיר הבריאות הפרטי והכבוי בלבד:

| סבב | פעולה | תוצאה |
|---|---|---|
|115 | SetProperties לעטיפתAssetForEditor, ואחריהSetDeviceProperty לשדה ההורה ושמירתActor | קריאה מיידית הציגהGridWallCandidate_C. אחרי קומפילציה וקריאה מחודשת עםDetails, חזרה הבחירה המקוריתPlayerBuildablePropCandidate_C. אין חיבור מקורי מתמיד. |
|116 | set_editor_property ציבורי עםnotify_mode=ALWAYS, תחתScopedEditorTransaction ושמירתActor | אותו הבדל בין קריאה מיידית לקריאה אחרי קומפילציה. אין חיבור מקורי מתמיד. |

המקורות ו־hashes שלArt/NPC ב־115–116 זהים ל־114. לא בוצעוcook אוSpawnProp עם המחלקה המקורית ולכן אין תוצאת runtime חיובית או שלילית להקצאה הזאת. אין להסיק מהאיפוס מסנן מחלקות מסוים או מגבלת פלטפורמה כללית. ההבחנה בין ערך עורך זמני לבין ערך שנשמר ונכנס למשחק נשארת מחייבת.

הראיות המקומיות: `.local/native-spawn115-readonly.json`,‏ `native-spawn115-binding.json`,‏ `native-spawn115-postcompile.json`,‏ `native-notify116-readonly.json`,‏ `native-notify116-binding.json`,‏ `native-notify116-postcompile.json`. שגיאת קריאה שלparent_class ב־Blueprint נשמרה ביומן; בדיקתisinstance הציבורית החליפה אותה ולא שינתה נכס.

## מצב הבורר והשליטה

SelectAssets דרךMCP הסתיימה בפסק זמן; הקריאה הציבוריתsync_browser_to_objects התבקשה, אך20 קריאותGetSelectedAssets נותרו ריקות. אין מכאן טענה שהבחירה לא תיתכן במסך. בדיקתAPI מותקן מצאהclose_all_editors_for_asset, והוא סגר חלונית אחת שלCoachParticipantCandidate אחרי אימות שהיא נקייה. הנכס לא שונה.

לחיצות קצרות דרך כלי השליטה לא סגרו את חלונות העזר שנצפו; לא בוצעה בחירת נכס מאומתת בבורר. השליטה אופסה ושוחררה. נשאלה בשיחה בקשה יחידה למשתמש לסגור רקMessage Log ו־Session Inspector, כדי להשאיר את החלון הראשי פנוי. זו הכנת עורך ולא בדיקת משחק. אין לחזור על אותן לחיצות/הודעותALWAYS בלי נתון או מסלול חדש. הבחירה המקורית נשארהPlayerBuildablePropCandidate_C; לא שונו מסנני מחלקות או נכסים מוגנים.

## קוד117

`coach_live_piece` קיבל זהותunique מקומית. SetShape בודק כעת שהחלק קיים ברשימתPieces הפעילה, שהמפגש והגרסה תואמים, ואם ישNativeLease — שהוא שייך למאגר של אותו מנהל, פעיל ותואם למפגש. נתיב המאגר דוחה גם חלק שאין לוlease מתאים. זו הגנה על רישום הקוד הפנימי; אינה בעלותFortnite מקורית או בדיקת משתמש. הקריאות הרגילות משתמשות בחלקים שהוחזרו מ־TryPlace/FindOwnedPiece. הבנייה117 חזרה ללא אבחונים; השינוי עדיין לא הורץ במשחק.

אימות117 עבר149 הפניות,18 מקורות תואמים ו־56/56 נכסים תקינים ללא אזהרות, מפה שמורה.14 דגלי הבריאות ו־3 דגלי המבנה כבויים, משכים וסף0, ארבעת השעריםFalse והמאגר הראשי כבוי וריק;‏ Connected/CanStart. [checkpoint117](NPC_VISUAL_CHECKPOINT_117.json) מציין במפורש שמקור העורך שונה מהמקור שהורץ ב־114 ונדרשת העלאה לפני הרצה. אין משחק115–117 או שליטה פעילה.

## מקורות שנבדקו מחדש

- [SpawnProp](https://dev.epicgames.com/documentation/en-us/fortnite/verse-api/fortnitedotcom/devices/spawnprop) ו־[creative_prop_asset](https://dev.epicgames.com/documentation/en-us/fortnite/verse-api/fortnitedotcom/devices/creative_prop_asset): חוזה הקצאה ותוצאת הצלחה/כישלון; אינם ראיה שהמחלקה המקומית נשמרה או נוצרה.
- [Python בעורך](https://dev.epicgames.com/documentation/unreal-engine/scripting-the-unreal-editor-using-python): הפעלת הודעות שינוי דרךset_editor_property. החתימה והערכיםALWAYS/DEFAULT/NEVER אומתו גם ב־API המותקן; ההתנהגות המקומית אחרי קומפילציה גוברת על הנחה שמספיקה הודעה בלבד.
- [תבנית בנייה פרוצדורלית](https://dev.epicgames.com/documentation/en-us/fortnite/procedural-building-template-in-unreal-editor-for-fortnite): משתמשת במערכת בנייה וב־building prop meshes; אינה הוכחת סמנטיקת בעלות/משבצת של קיר שחקן.
- [דיווח43.00 עלNPC ובנייה מקורית](https://forums.unrealengine.com/t/uefn-43-00-can-npcs-use-native-building-wall-replacement-edits-and-resets/2850177): עדות היוצר לניסויים שלו, לא של הפרויקט; דרישתו להימנע מחלופות אינה מחליפה את אישור המשתמש שלנו לחלופות פנימיות.

המשך: לאחר פינוי חלונות העזר, לבדוק בחירה דרך הבורר המקורי ושמירה/קומפילציה/cook לפני ניסוי הקצאה. אם הבורר מסנן או דוחה את הנכס, לשמור את התוצאה המדויקת ולחקור חלופה נתמכת, בלי לכפות בחירה או לשנות מסנני פלטפורמה. נשמר היקףR01–R25 והמשחק הפיזי נשאר לסוף; המטרה אינה שלמה.
