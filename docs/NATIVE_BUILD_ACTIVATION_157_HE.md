# הפעלת כלי בנייה מקוריים — מחקר ממוקד157

רענון מוגבל 203, 8 בנובמבר 2026: נקראו שוב ה־digests המותקנים וממשקי הקלט והמלאי, ועמודי [Player Input](https://dev.epicgames.com/documentation/fortnite/how-to-add-player-input-in-verse-in-unreal-editor-for-fortnite), [Build Hotbar](https://dev.epicgames.com/documentation/en-us/fortnite/verse-api/fortnitedotcom/itemization/fort_inventory_build_hotbar_component) ו־[43.00](https://dev.epicgames.com/documentation/en-us/fortnite/43-00-fortnite-ecosystem-updates-and-release-notes). התיעוד שנקרא תומך באירועי קלט שחקן ובניהול מלאי; לא התקבלה ראיה חדשה להפעלת בנייה/עריכה מקורית בידי היריב. נבדקה גם חלופה של יצירה במיקום באמצעות Sequencer/שכבות: [תיעוד UEFN](https://dev.epicgames.com/documentation/fortnite/streaming-and-hlods-in-unreal-editor-for-fortnite) מאשר טעינה/הפעלה/פריקה של שכבות בזמן ריצה, אך לא סיפק הוכחה חדשה להקצאת חלק מקורי במיקום חופשי, ברישום ובבעלות הנדרשים. לא נוצרו שכבות או מתקני ניסוי חדשים ולא הורץ משחק. שאלות החיפוש כיסו API/קלט, רשימות גרסה, דיווחי יוצרים וחלופות Sequencer/שכבות; הן חזרו למשטחים שכבר נחקרו. החקירה נעצרה, ללא מסקנת אי־אפשרות. אין לחזור עליה בלי שינוי API, דוגמה מפורשת חדשה או ראיית מנוע חדשה מורשית. ליבת W2 נשארת פתוחה; גימור הלובי 203 הוא עבודה נפרדת ב־W1/W3, ולא פתרון לליבה.

8בנובמבר2026. השאלה: האם GuardאוParticipantיכול להפעיל את כלי הבנייה המקוריים שבמלאיו כדי להציב חלק בבעלות מתאימה, לערוך ולאפס אותו בזמן קרב באי בר־פרסום? ציוד כלי, תקיפה, התחלת יכולת ושינוי גאומטריה הם ראיות נפרדות.

ה־digestשנקרא נמצא תחת `Saved/VerseProject/ProCoachLab/Digests/BuiltIn`ומזדהה כ־43.00,CL59596594. נבדקוFortnite.digest.verseו־UnrealEngine.digest.verse, לרבות מחלקות מלאי הבנייה, פעולותGuard,Inputו־Abilities. לא הופעלו משחק, בדיקת מנוע, דגליDebugאו אבחוןParticipant. ניסויי131–133ההיסטוריים לא הורצו מחדש; נשמרה ההוראה שלא לשנות שערי קבלה או לעקוף מסננים.

## זוויות החיפוש שבוצעו

- יכולת נוכחית: `site.dev.epicgames.com fortnite NPC native building edit Participant input abilities Verse 43.00`.
- ממשקים קשורים: `site.dev.epicgames.com fortnite fort_inventory_build_hotbar_component build ability activate input`; גם `build ActivateAbility`ו־`NPC build wall edit ability component Verse`.
- היסטוריית גרסה: נקראו42.40ו־43.00, במיוחד הפיכתAbilitiesלניתנות לפרסום ושינוייUse/SpecHandle.
- דיווח ממקור ראשון: נפתחה מחדש שאלת43.00עלNPC,כלי בנייה, החלפת קיר, עריכה ואיפוס. זהו תיאור ניסויים של הכותב; לא תשובתEpicשמכריעה יכולת כללית.
- חלופה: נבדקוFortnite Template AbilitiesוהחתימותUse/MakeAbility/ability_contextהמקומיות, לצד המועמדים הקיימים של גאומטריה ומאגר חלקים.

## מקורות ומסקנות מצומצמות

| מקור שנקרא | מה הוא תומך בו | מה הוא אינו מוכיח כאן |
|---|---|---|
| [מלאי כלי הבנייה](https://dev.epicgames.com/documentation/en-us/fortnite/verse-api/fortnitedotcom/itemization/fort_inventory_build_hotbar_component) | ניהול פריטים וציודם במלאי המתאים | קריאה שביצעה הצבה/עריכה/איפוס מקוריים בידי היריב |
| [פעולותGuard](https://dev.epicgames.com/documentation/en-us/fortnite/verse-api/fortnitedotcom/ai/guard_actions_component) | Attackעל יעד שזוהה,תנועה,מבט ועמידה | Attackכפקודת אישור לבנייה או עריכה |
| [Template Abilities](https://dev.epicgames.com/documentation/fortnite/fortnite-template-abilities-in-unreal-editor-for-fortnite) | יכולות עם קלט,שאילתת יעד ורצף אפקטים; פריטים מעניקים יכולות | חשיפת פעולות הבנייה המקוריות דרך אותו מסלול |
| [42.40](https://dev.epicgames.com/documentation/en-us/fortnite/42-40-fortnite-ecosystem-updates-and-release-notes) | Abilitiesיצאו מ־Experimental; שינויים מתועדים ב־Use,אנימציה וביטול | שכל יכולת פנימית שלFortniteאומתכון בנייה ניתן להפעלה ציבורית כזאת |
| [43.00](https://dev.epicgames.com/documentation/fortnite/43-00-fortnite-ecosystem-updates-and-release-notes) | עדכוניAPIויכולות,לרבותpipelineנזק נפרד עם מעמד משלו | פתרון מאומת למשבצת/בעלות/עריכתNPCבפרויקט |
| [דיווח43.00](https://forums.unrealengine.com/t/uefn-43-00-can-npcs-use-native-building-wall-replacement-edits-and-resets/2850177) | תצפיות מצומצמות על ציוד וניסיונות הכותב | היעדר יכולת גורף או הוכחה לכל וריאצייתParticipant/יכולת |

עמודAPIשנוסה עבור `fort_item_ability_component`לא נפתח בכלי הרשת. לכן לא הוסקה מסקנה מהכשל בפתיחתו; תפקידו כהענקת יכולות מפריט נלמד מעמודTemplate Abilitiesוהחתימות המקומיות. ב־digestמופיעSpecHandleציבורי, אך עצם קיומו אינו הוכחה לקישור ולהפעלה של יכולת הבנייה הפנימית. לא נוצרוhandlesמאולצים, לא שונוCDOזרים ולא הוחלפו דגלי גישה.

## החלטה והמשך

המסלול המדויק **טרם אומת**. אין כאן קביעה שבנייה מקורית בידיNPCבלתי אפשרית, ואין ראיה חדשה שמצדיקה חזרה על ניסויי ציוד/Attackהיסטוריים. החיפושים חזרו לאותם ממשקי מלאי/פעולות/יכולות ולא הדגימו את החיבור החסר, ולכן נעצרה ההרחבה.

ארבעת שערי הבנייה נשאריםFalse. המועמד עםSetMeshנשאר מועמד גאומטרי, והמאגר נשאר הקצאה סופית שלא הוכח חידושה; שניהם דורשים קבלת אינטראקציה מול בניית השחקן. מידע שיצדיק פתיחה מחדש: דוגמה ציבורית מפורשת להפעלת מתכון בנייה/עריכה בידיNPC, שינויAPIרלוונטי, או ראיית משחק ממוקדת במסגרת הקבלה המורשית.

במקביל,157משפר את הכנת תוכנית הבנייה הקיימת: ספירת חלקים חסרים, שימוש בחלקים רשומים שכבר קיימים, תקציב חומרים/חלקים ומלאי מאגר לפי סוג. השיפור אינו פותר או מוכיח את שאלת ההפעלה המקורית, ואינו משנה את יעד המוצר.
