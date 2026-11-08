# הכרעת המשך הליבה — מצב והכנה מוגבלת

8 בנובמבר2026. קריאה חדשה דרך MCP ב־14:54UTC מאשרת ProCoachLab פתוח, סשן Disconnected ומשחק Unconnected. כל ארבעת שערי הבנייה, UseNativePiecePool, RenewNativePoolBetweenRounds ו־Enabled של הבקר כבויים; שני רצפי המאגר מחוברים וספירתו הצפויה16 מכל סוג. ראיה: `.local/core193-readiness.json`. לכן הבנייה/העריכה של היריב אינן פעילות במוצר, ואין להציג את ההכנות188–192 כבוט פרו.

## המחקר שרוענן

נבדקו ארבע זוויות: פעולות NPC ב־43.00, API הצבה/עריכה, תזוזת props ורישום מבני, ודיווחי יוצרים מהגרסה. נפתחו מחדש [מלאי כלי הבנייה](https://dev.epicgames.com/documentation/en-us/fortnite/verse-api/fortnitedotcom/itemization/fort_inventory_build_hotbar_component), [פעולות NPC](https://dev.epicgames.com/documentation/en-us/fortnite/verse-api/fortnitedotcom/ai/npc_actions_component), [Teleporter](https://dev.epicgames.com/documentation/en-us/fortnite/verse-api/fortnitedotcom/devices/teleporter_device), [תבנית בנייה פרוצדורלית](https://dev.epicgames.com/documentation/fortnite/procedural-building-template-in-unreal-editor-for-fortnite) ו־[הערות43.00](https://dev.epicgames.com/documentation/en-us/fortnite/43-00-fortnite-ecosystem-updates-and-release-notes). התיעוד תומך במלאי, פעולות, שינוע props ובנייה פרוצדורלית; הוא אינו ראיית ריצה של בנייה מקורית, בעלות/משבצת או המשכיות בריאות בפרויקט. לא אומת מסלול חדש שמכריע אותן. התוצאות חזרו לממשקים ולדיווחים שכבר זוהו, ולכן הופסקה הרחבת החיפוש. אין כאן קביעה של חוסר אפשרות כללית.

## מה הוכן

מתקן נזק חדש ונפרד, בלי לחזור על ארבע בדיקות הצורה שכבר עברו185. מקורו ב־`tools/fixtures/core-damage/coach_damage_acceptance193.verse`; החוזה והפריסה בקובץ JSON הצמוד. ברירת המחדל כבויה, עד60שניות משחק ורצף אחד בלבד.

לפני השוואת שינוי צורה הוא דורש קיר ביקורת מאותו נכס, הרשאת נזק במופע, אישורי ExplodedEvent של המקור הנכון, הרס נצפה והיעלמות התנגשות. כישלון הביקורת מפסיק את ההשוואה. רק אחריה נוצרים שני קירות חדשים, אחד משתנה לחלון וחוזר, ומשווים נקודות הרס. [Epic מתעדת ExplodedEvent](https://dev.epicgames.com/documentation/en-us/fortnite/verse-api/fortnitedotcom/devices/explosive_device) כאירוע פיצוץ עם agent; עצם האירוע עדיין אינו הוכחת נזק, ולכן נדרשת הביקורת בנפרד.

זהו תיקון לפער הראיות185, שבו לא נאספו אישורי פיצוץ או ביקורת נזק חיובית. אין הבטחה שהמתקן החדש יצליח, ואם הביקורת נכשלת אין ניסיון חוזר אוטומטי. תוצאה טובה תהיה השוואה כמותית גסה בלבד, ללא HP מספרי, בעלות, משבצת, NPC או איכות פרו.

המקור נכתב זמנית בעורך לצורך קומפילציה בלבד, בלי להציב Actor. לאחר תיקון שימוש no_rollback בתנאי, הקומפילציה ריקה; המקור הזמני הוסר, קומפילציית הניקוי ריקה, השמירהTrue ומערכת קובצי המקור המקורית שוחזרה. ראיות: `.local/core193-compile-authoring.json` ו־`.local/core193-compile-correction.json`. קובצי המוצר נשארו בגרסאות192/191/190. אין מתקן193 במפה או מקורו בעורך, ואין תהליך משחק/בדיקה שנשלח193 וממתין.

## הרשאה וסדר העבודה

הוראת המשתמש לדחות בדיקות משחק לסוף עדיין חלה, ואישור185 נוצל. ההכנה אינה אישור להפעיל. כדי להשתמש במתקן לפני השלמת יתר ההכנה דרוש אישור מפורש לשינוי סדר העבודה. אין לפרש המשך מטרה אוטומטי או היעדר תשובה כאישור, ואין להפעיל source/fixture176 הישן. הבקשה היא למנגנון אחד מוגבל, ללא עכבר או בדיקה ידנית של המשתמש; היא אינה מסמנת את הפרויקט גמור או מקטינה את האפיון.

בקשת האישור הוגשה באמצעות שאלת משתמש אסינכרונית במהלך193. ההגשה התקבלה, אך טרם נצפתה תשובה. אין לפרש accepted של כלי השאלה כהסכמת המשתמש. אין לשלוח שאלה כפולה או להתחיל משחק בזמן ההמתנה.
