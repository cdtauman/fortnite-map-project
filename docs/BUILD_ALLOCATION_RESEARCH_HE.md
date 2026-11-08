# חידוש מלאי חלקי הבנייה — מחקר ממוקד

נבדק ב־7 בנובמבר2026, מול UEFN43.00 CL59596594. השאלה היא יצירה חוזרת בזמן משחק של חלק שנהרס, עם התנגשות, נזק ובעלות תקינים. יצירת נכס בעורך ושחזור בתחילת סיבוב אינם ממלאים את הדרישה.

נבדקו בנפרד מסלולי מכשירים, ממשקי Verse, שינויים בגרסאות ודיווחי מפתחים. חיפושי המכשירים כללו Level Instance/Level Loader, איפוס Prop Mover, SpawnProp, Prop Manipulator, prop_spawner_base_device ומנגנון ההריסה בתבנית LEGO PvP Extraction. תוצאות חיפוש אינן תוצאת מנוע.

| מסלול | ראיה שנקראה | מה עדיין דורש הוכחה |
|---|---|---|
| Level Instance ו־Level Loader | התיעוד הרשמי מתאר שמירת קבוצת מבנים והפעלה/כיבוי. | זמינות בתצורת UEFN הנוכחית, שחזור חלק שנהרס, הפניה חדשה, מיקום ומשבצת. לא נמצא שם התחייבות לאיפוס חיים. חיפוש בשמות המדויקים ב־digest המקומי לא החזיר מחלקה; זו תוצאת חיפוש מקומית, לא מסקנת אי־אפשרות. |
| SpawnProp עם נכס פרטי שנבחר במבחר המקורי | החוזה הרשמי מחזיר creative_prop ותוצאת יצירה. בסבב03 נכס LessonWall פרטי נוצר ונקרא9/9.47 הוסיף שני מחזורי יצירה/אי־תקפות של עותק עם מפתחות אתחול תקינים, במהלך ירי מקורי; geometry9→0→9→0. | HP מספרי/התאמה לבריאות שחקן, עריכת שחקן, רישום ברשת ותחרות על מקום. מחזור החיים אומת רק למועמד הפרטי ולתצורה של47. המוניטור של הקיר המוצב אינו מוכיח שיופעל על מופע שנוצר בזמן המשחק. |
| prop_spawner_base_device | API רשמי מתאר SpawnObject ו־DestroyAllSpawnedObjects. ה־digest המקומי מסמן את מחלקת הבסיס abstract/epic_internal; נגזרות הפיזיקה מוצגות בנפרד. | מכשיר קונקרטי שמקבל נכס קיר פרטי דרך מסלול נתמך ומחזיר יכולות נדרשות. עצם קיום מחלקת בסיס אינו הוכחת מסלול קירות. |
| תבנית LEGO PvP Extraction | דף Epic מתאר מנהל destructible props והגדרות auto-respawn/timer לכל הגדרה. | קריאת המימוש וההבדל בין שחזור ישות לבין הצגה חוזרת של prop, ונאמנות למבנה Fortnite רגיל. התבנית לא יובאה ולא הורצה בניסוי הזה. |
| Prop Mover/Prop Manipulator | החוזים מתארים איפוס מיקום ושחזור בריאות של props מושפעים. | יצירה מחדש של הפניה שכבר הפכה ללא תקפה. לא להציג Reset או RestoreHealth כהוכחת respawn בלי הרצה. |

**עדכון47–48:** קיימת כעת תוצאת מחזור חיים של prop שנוצר בזמן משחק, כולל הקצאה מחדש והתנגשות, לאחר אתחול מאפייני הנכס. ארבעת נכסי הקרב נוצרים עם ההפניות והצורות הנכונות. [תיקון האתחול](PROP_HEALTH_INIT_FIX_HE.md) מפריד בין התוצאה לבין HP מספרי, בעלות, משבצות ועריכה מקורית שעדיין אינם מוכחים. לא הוכחה מערכת מלאי בלתי מוגבלת, ביצועים או פרסום.

מקורות: [Level Instance](https://dev.epicgames.com/documentation/fortnite/using-level-instance-devices-in-fortnite-creative), [Level Loader](https://dev.epicgames.com/documentation/fortnite/using-level-loader-devices-in-fortnite-creative), [Devices ו־SpawnProp](https://dev.epicgames.com/documentation/fortnite/verse-api/fortnitedotcom/devices), [בסיס Prop Spawner](https://dev.epicgames.com/documentation/en-us/fortnite/verse-api/fortnitedotcom/devices/prop_spawner_base_device), [מנהל props בתבנית LEGO](https://dev.epicgames.com/documentation/fortnite/lego-pvp-extraction-template-in-unreal-editor-for-fortnite?lang=en-US), [Prop Mover](https://dev.epicgames.com/documentation/fortnite/using-prop-mover-devices-in-fortnite-creative?lang=en-US), [Prop Manipulator](https://dev.epicgames.com/documentation/fortnite/verse-api/fortnitedotcom/devices/prop_manipulator_device), [עדכון43.00](https://dev.epicgames.com/documentation/en-us/fortnite/43-00-fortnite-ecosystem-updates-and-release-notes).

החיפוש נעצר בנקודה שבה הממשקים הכלליים חוזרים על אותם חוזים וההכרעה דורשת ניסוי קטן או קריאת תבנית. דיווחי פורום ישנים על זמינות Level Loader אינם קביעה על43.00. אין כאן חסם פלטפורמה מוכח ואין הסקה על פרסום.
