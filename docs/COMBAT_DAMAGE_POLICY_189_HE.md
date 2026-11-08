# הרשאת נזק במופע חלק קרבי

8 בנובמבר 2026, UEFN43.00 CL59596594. שינוי מקור אחד התקמפל ללא אבחונים ונשמר. אין תוצאת משחק חדשה.

## השינוי

קוד ההצבה הסתמך על תצורת הנכס כדי לאפשר נזק למופע. כעת `coach_building.verse` מגדיר במפורש `CanBeDamaged=true` וקורא את הדגל חזרה בכל חלק קרבי שהתקבל מ־SpawnProp או מהמאגר המקורי. מופע שאינו מאפשר נזק אינו מוחזר כהצבה מוצלחת: מופע שנוצר מוסר לפני צריכת משאב, ומופע מאגר נצרך ומוחזר לחניה לפי מדיניות הפרישה הקיימת. `SetShape` דוחה חלק שאינו מאפשר נזק לפני שינוי צורה. הדגמות השיעור ממשיכות לקבל דגל False במסלול הנפרד שלהן.

לא נכתבים חיים, לא נקראת RestoreHealth ולא מושב חלק משומש לשימוש נוסף באותו מאגר. היומן מבחין בין `damage_enabled=true` לבין `health_unmeasured`. זהו חוזה הרשאה במקור, לא מדידת נזק, בריאות או הוכחת המשכיות לאחר עריכה.

ראיה: `.local/combat-damage189-authoring.json`, מקור SHA256 `a2c6e5930f8d4469fb06a2233e6396abaa31e805331e1766ebbdca9ea2ff5628`, קומפילציה `[]`, שמירה True. לא הופעלו משחק, סשן, העלאה, מתקן מנגנון או קלט מחשב. כל שערי הבנייה נשארו False.

## מחקר ממוקד

הדרישה שנחקרה: נזק אמיתי לחלק שהבוט מציב, מדידת בריאותו והמשכיותה לאחר שינוי צורה, בלי להפוך תכונה ניסיונית לתלות של מסירת האי. נבדקו התיעוד הנוכחי, API של props ושל ממשקי בריאות, הערות43.00 וסיכוני ה־Pipeline, דיווחי יוצרים ונתיבי Objective/Prop Manipulator. לא נערך ניסוי מנוע.

- [creative_prop](https://dev.epicgames.com/documentation/en-us/fortnite/verse-api/fortnitedotcom/devices/creative_prop) מתעד הרשאת נזק. ה־digest המותקן מגדיר `var CanBeDamaged:logic`, והמקור שעושה בו שימוש התקמפל. שדה זה אינו כמות הנזק או HP.
- [Prop Manipulator API](https://dev.epicgames.com/documentation/en-us/fortnite/verse-api/fortnitedotcom/devices/prop_manipulator_device) מתעד אירועי נזק/הרס עם agent. אירוע כזה אינו מוכיח לבדו זהות חלק, כמות נזק או בריאות מספרית של חלק שזז. [דיון יוצרים על כמות הנזק](https://forums.unrealengine.com/t/how-to-determine-damage-amount-from-a-prop-manipulator-device-damagedevent/1571351) הוא עדות היסטורית, לא קביעה על כל חלופה בגרסה המותקנת.
- [objective_device](https://dev.epicgames.com/documentation/en-us/fortnite/verse-api/fortnitedotcom/devices/objective_device) חושף healthful. Objective נפרד יכול לשמש ביקורת מדידה, אך בריאותו אינה בריאותו של קיר הבוט. ההפרדה נשמרת; לא הוחלף חלק קרבי ביעד רק כדי לקבל מספר.
- [health_component](https://dev.epicgames.com/documentation/fortnite/verse-api/unrealenginedotcom/healthpipeline/health_component) מתעד בריכות בריאות ואירועי נזק. [הערות43.00](https://dev.epicgames.com/documentation/en-us/fortnite/43-00-fortnite-ecosystem-updates-and-release-notes) מסמנות את המערכת Experimental ואומרות שפרסום יתאפשר לאחר יציאתה משלב זה; ה־digest המקומי מסמן את הסוגים הנוגעים ב־experimental. לא שונתה הגדרת הפרויקט ולא נוספה תלות כזו.

ה־digest נקרא מתוך `AppData/Local/UnrealEditorFortnite/Saved/VerseProject/ProCoachLab/Digests/BuiltIn` באמצעות PowerShell/rg. תהליך Python המקומי לא ראה את אותו נתיב AppData, למרות ש־PowerShell קרא אותו; לא פורש הדבר כמחיקת הפרויקט או כשל בעורך ולא הופעלה תוכנה מחדש.

החיפוש נעצר כשהחזיר את אותם משטחי API שכבר זוהו, ללא נתיב מספרי מאומת נוסף לחלק הקרבי. המסקנה היא **בריאות מספרית והמשכיות עדיין לא אומתו**, לא חוסר אפשרות כללי. אין הצדקה לסבב חוזר של הפיצוצים185 ללא מידע חדש.

## הפער שנותר

בסבב185 לא התקבלה ביקורת חיובית לנזק, ולכן אין לייחס את תוצאתו לדגל שהיה כבוי: דגל המופע לא נקרא שם. גם שינוי189 אינו הוכחה לסיבת התוצאה. בקבלת הסיום נדרשים מקור נזק שפעל בפועל, ראיה לנזק באותו חלק, שינוי צורה ושימור/הרס תחת נזק נוסף. אישור פיצוץ, הרשאת נזק, HP, הרס והתנגשות הם ראיות נפרדות.
