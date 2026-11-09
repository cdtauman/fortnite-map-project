# תוכנית פרימיום: "ProCoach Plus"

נכתב ב־9 בנובמבר 2026 (צעד 4.3 ב־[GOAL_V1_HE.md](GOAL_V1_HE.md)). **שום חיוב לא מופעל.** coach_commerce_device נשאר `Enabled=false`, והקטלוג נשאר ריק. הפעלה דורשת את ההחלטה שלך, את התנאים של Epic, ונתוני שחקנים אחרי ההשקה (אפיון סעיף 9: "אחרי שיש שחקנים").

## מה Epic מתירה (מחקר עדכני)

- **מה מוכרים:** פריטים, יכולות משחק או נכסים, תמורת V-Bucks. כל הצעה מוגדרת כ־entitlement ב־Verse.
- **מה אסור:** אסור למכור קוסמטיקה רגילה של Fortnite, כמו תלבושות וריקודים, כי היא נשארת בחנות של Epic. אסור גם למכור XP או לרמוז על XP.
- **גלגלי פרסים:** אסורים מאז 20 בינואר 2026. אקראיות בתשלום דורשת חשיפת סיכויים. אנחנו לא מוכרים שום דבר אקראי.
- **פריט שמשפיע על המשחק:** חייבים לחשוף בבירור מה הוא עושה.
- **מי יכול למכור:** יוצר בן 18 ומעלה שנמצא ב־Developer Program. הרכישה תקפה רק באי שבו נקנתה. חלות הגבלות לפי אזור ולפי פלטפורמה.
- **חלוקת ההכנסות:** 100% מערך ה־V-Bucks עד סוף 2026, ואחר כך 50%. המקורות לא מסכימים אם המעבר הוא בסוף 2026 או ב־31 בינואר 2027, ולכן צריך לבדוק ב־Developer Rules סעיף 4.4.

## מה כולל Plus

**עיקרון:** הבסיס תמיד חינמי ושימושי (אפיון סעיף 9). Plus לא נותן יתרון בקרב 1V1 מול שחקן אחר. הוא נותן עומק בלמידה.

| תכונה | מצב בקוד |
|---|---|
| היסטוריית עשרת הקרבות האחרונים מול הבוט | קיים, ומוגבל דרך `Commerce.AllowsAdvancedFeatures` |
| "Explore the last 90 seconds", צפייה במיקומים שנרשמו | קיים, ומוגבל באותו אופן |
| תרגילי מאמן בנייה מתקדמים (I ו־P במחקר) | יתווספו בהמשך. התרגילים הקיימים (B1–B9, I4) יישארו חינמיים |
| סקירת 1V1 מורחבת עם היסטוריה בין ביקורים | הסקירה הבסיסית חינמית. הרחבה, אם תוחלט, תיבנה אחר כך |

**טקסט חשיפה מוצע:** "ProCoach Plus unlocks extra training history and advanced drills. It does not change weapons, health or building in 1V1 fights."

## מה צריך ממך כדי להפעיל

1. להיות ב־Developer Program, בגיל 18 ומעלה, ולאשר את התנאים.
2. להחליט על מחיר ב־V-Bucks ועל פריט אחד קבוע (durable) בשם "ProCoach Plus".
3. לתת אישור מפורש להפעיל חיוב. אחריו אגדיר entitlement קונקרטי שיורש מ־`coach_plus_entitlement`, ואמלא את הקטלוג.
4. **לפני כל זה:** להשיק חינם ולמדוד. האפיון קובע פרימיום רק אחרי שיש שחקנים.

## מקורות

- [In-island transactions overview](https://dev.epicgames.com/documentation/fortnite/in-island-transactions-overview-in-fortnite)
- [Fortnite news: sell in-game items](https://www.fortnite.com/news/fortnite-developers-will-soon-be-able-to-sell-in-game-items)
- [Tools for in-island transactions](https://www.fortnite.com/news/tools-for-in-island-transactions-now-available-to-fortnite-developers)
- [Prize wheel ban](https://www.techloy.com/epic-games-bans-prize-wheel-and-loot-box-sales-in-fortnite-creator-islands/)
