<div dir="rtl" align="right">

# 📎 נספח מתקדם — ProAI Training Map V2
## מאמן AI · Widget Blueprints · ווריאנטים קוסמטיים · עריכת קירות · מבחני עומס
## **מעודכן ל-UEFN v40.00+ (מרץ 2026)**

> **⚡ עדכוני v40:** Persona Device זמין, Verse Fields ב-UMG יציב (מ-v38+), תוכן Star Wars חדש, Book of Verse, Mobile Preview, באגים ידועים ועקיפות.

---

# 📋 תוכן עניינים

1. [הגדרת NPC מאמן](#-1-הגדרת-npc-מאמן)
2. [יצירת UMG Widget Blueprints](#-2-יצירת-umg-widget-blueprints)
3. [הגדרת ווריאנטים קוסמטיים לארנה](#-3-הגדרת-ווריאנטים-קוסמטיים-לארנה)
4. [מערכת עריכת קירות — הסבר ויזואלי](#-4-מערכת-עריכת-קירות)
5. [מבחני עומס ואיתור באגים](#-5-מבחני-עומס)
6. [אופטימיזציה וביצועים](#-6-אופטימיזציה)
7. [פרסום האי](#-7-פרסום)
8. [🆕 חידושי v40 — Star Wars, כלים חדשים ובאגים ידועים](#-8-חידושי-v40)

---

# 🤖 1. הגדרת NPC מאמן

## 1.1 — למה
מערכת `coach_controller` מייצרת טקסט מאמן אחרי כל סבב. ניתן להציג אותו גם דרך NPC פיזי בארנה — ה"מאמן".

## 1.2 — NPC Character Definition למאמן
1. **Content Drawer** → לחץ ימני → **AI** → **NPC Character Definition**
2. שם: `BP_CoachNPC`
3. פתח ב-double-click

| שדה | ערך |
|------|------|
| Body / Skin | skin **שונה** מהבוט הקרבי (כדי שהשחקן יזהה) |
| **Behavior Type** | **Custom** (לא Guard — המאמן לא יורה!) |
| Weapon | **ריק** — אין נשק |

4. שמור

## 1.3 — NPC Spawner למאמן
1. הנח **NPC Spawner** חדש → **בקצה הארנה** (לא באמצע!)
2. ב-Details Panel:
   - NPC Character Definition → `BP_CoachNPC`
   - **Spawn on Game Start:** **Enabled** (המאמן תמיד שם)
   - Auto Respawn → **Enabled**

## 1.4 — Persona Device

> **🆕 v40: Persona Device זמין ויציב!** Epic הרחיבה את מערכת ה-AI הדיאלוגית שהחלה עם Darth Vader NPC ב-Battle Royale ופתחה אותה ליוצרים.

1. חפש `Persona Device` ב-Content Drawer
2. **גרור** ל-Viewport → מקם ליד ה-NPC Spawner של המאמן
3. ב-Details Panel:
   - **Attached NPC Spawner** → NPC Spawner של המאמן
   - **Personality Prompt:**
     ```
     You are a competitive Fortnite coach. You are direct, specific,
     and metric-driven. You reference ELO, DPS, headshot ratio, and
     reaction time. You never use generic motivational phrases. You
     give one specific improvement tip after every round.
     ```
   - **🆕 v40:** אפשר עכשיו גם לבחור **סוג קול ומסירה** (Voice Type / Delivery) — בחר קול מקצועי ואנרגטי
4. שמור

**⚠️ גם בלי Persona Device**, מערכת `coach_controller` עדיין מציגה הודעות דרך:
- `HUD Message Device` (טקסט על המסך)
- `hud_binding` (canvas-driven HUD)
- Output Log (לדיבוג)

---

# 🖼️ 2. יצירת UMG Widget Blueprints

## 2.0 — למה
מערכת ה-HUD שלנו (`hud_binding`, `scorecard_renderer`) כבר עובדת עם **Canvas API בקוד Verse**. ה-Widget Blueprints הם **אופציונליים** — שכבה ויזואלית נוספת שמאפשרת עיצוב מדויק יותר בעורך הגרפי.

מודול `hud_binding` מעדכן משתנים ציבוריים (`DisplayELO`, `DisplayDPS`, `DisplayHSPct` וכו') כל 500ms. Widget Blueprints יכולים לקרוא מהם.

> **🆕 v38+ — Verse Fields ב-UMG:** מ-v38.00 (נובמבר 2025) יש תמיכה רשמית ויציבה ב-**Verse Fields** ב-UMG Widgets. זה מאפשר לבנות UI דינמי שמתעדכן אוטומטית מ-Verse בלי קוד ידני.
>
> **🆕 v39.40+ — Verse Fields Event Type:** מ-v39.40 (פברואר 2026) יש סוג חדש של Verse Fields שמאפשר ליצור **widgets אינטראקטיביים** שמגיבים לקלט המשתמש (לחיצות, שינויים).

## 2.1 — איך יוצרים Widget Blueprint
1. ב-Content Drawer → לחץ ימני → **User Interface** → **Widget Blueprint**
2. תן שם → לחץ כפול לפתיחה
3. ייפתח עורך ויזואלי עם: **Palette** (שמאל), **Designer** (מרכז), **Details** (ימין)

## 2.2 — Widget #1: `WBP_HUD_LiveStats`
**תפקיד:** תצוגה קטנה בפינת המסך — ELO, ניצחונות, DPS

1. צור Widget Blueprint בשם `WBP_HUD_LiveStats`
2. מ-Palette, גרור 4 רכיבי **Text** ל-Designer:
   - `ELO: 1000`  (Font Size: 18, צבע: לבן)
   - `Round: 1`
   - `W: 0 | L: 0 | D: 0`
   - `DPS: 0.0 | ACC: 0% | HS: 0%`
3. סדר בפינה שמאלית עליונה של המסך
4. **Binding באמצעות Verse Fields (v38+):**
   - בחר Text → Details → **Binding** → בחר **Verse Field**
   - הגדר את ה-View Binding Class ל-`hud_binding`
   - קשר כל Text ל-property המתאים:
     - Text #1 → `DisplayELO`
     - Text #2 → `DisplayRound`
     - Text #3 → `DisplayRecord`
     - Text #4 → `DisplayDPS`
5. שמור

> **⚠️ v40 באג ידוע:** העתקה של overlays עם Verse Fields בין widgets עלולה לגרום לקריסה. **שמור לפני כל Compile** ואל תעתיק — צור מחדש.

## 2.3 — Widget #2: `WBP_PostRound_Scorecard`
**תפקיד:** מסך מלא בסוף כל סבב

| רכיב | תוכן | Font Size |
|-------|-------|-----------|
| Text (מרכז) | "VICTORY" / "DEFEAT" | 48 |
| Text | ELO + שינוי ("+32") | 28 |
| Text | DPS | 20 |
| Text | Headshot % | 20 |
| Text | Reaction Time | 20 |
| Text | הודעת מאמן | 16, צהוב |
| Image/Panel | רקע שחור, Opacity 0.7 | — |

**Binding עם Verse Fields:** קשר לשדות של `scorecard_renderer`:
- `RoundResultText`, `ELOChangeDisplay`, `DPSText`, `HeadshotText`, `CoachFeedbackText`

## 2.4 — Widget #3: `WBP_CoachDialogue`
**תפקיד:** בועת טקסט כשהמאמן מדבר

1. רכיב **Image** כרקע (מלבן מעוגל, צבע כהה, Opacity 0.8)
2. רכיב **Text** מעל (Font Size: 16, לבן)
3. מקם בתחתית המסך, מרכז
4. Binding: `hud_binding` → `DisplayCoachMsg`

## 2.5 — Widget #4: `WBP_Shop_MainMenu`
**תפקיד:** ממשק חנות

1. **Text:** "TRAINING SHOP" (Font Size: 36)
2. **Text** × 4 (מוצרים):
   - "[1] Analytics Pass — 800 V-Bucks"
   - "[2] Cyber Arena — 300 V-Bucks"
   - "[3] Neon Arena — 300 V-Bucks"
   - "[4] 5 Tokens — 250 V-Bucks"
3. **Text:** יתרת Tokens
4. **🆕 v39.40+ — Verse Fields Event Type:** אפשר עכשיו להוסיף **כפתורי UMG אינטראקטיביים** שמחוברים ישירות ל-Verse דרך events — מה שמאפשר לבנות UI חנות מתקדם יותר בלי Button Devices פיזיים
5. שמור

**⚠️ חשוב:** ה-Widget Blueprints הם **אופציונליים**. מערכת ה-Canvas בקוד Verse (hud_binding, scorecard_renderer, shop_ui_controller) כבר מציגה את כל המידע ללא Widget Blueprints. צור אותם רק אם אתה רוצה שליטה ויזואלית מדויקת יותר.

---

# 🎨 3. הגדרת ווריאנטים קוסמטיים לארנה

## 3.1 — איך עובד `cosmetic_applicator`
מערכת הקוסמטיקה מחליפה את מראה הארנה כולה. כל "סקין" הוא **קבוצת props** שונה. רק אחת מהן גלויה בכל רגע — השאר מוסתרות ב-Z=-5000.

## 3.2 — הכנת ווריאנט Cyberpunk
1. בנה ארנה שנייה (אותו גודל) מ-props בסגנון אחר
   - חפש ב-Content Drawer: `Neon`, `Metal`, `Industrial`
   - או שנה חומרים (Materials) על props קיימים
2. קבץ את כל ה-props של הווריאנט → בחר הכל → **Right-click** → **Group**
3. ב-Details Panel: Location Z = `-5000` (מוסתר)
4. חבר ל-`cosmetic_applicator` → **CyberArena**

## 3.3 — חזור עבור Neon Grid
- סגנון: קווים זוהרים, רשת, Tron-style
- חבר ל-**NeonArena**

> **🆕 v40 — Star Wars Arena Variant:** אפשר עכשיו ליצור ווריאנט Star Wars! חפש ב-Content Drawer נכסים כמו `Death Star`, `Hoth`, `Tatooine` מספריית Star Wars החדשה. חבר ל-`TourneyArena` או הוסף slot חדש.

## 3.4 — Default Arena
- הארנה שכבר בנית היא ה-Default
- חבר ל-**DefaultArena**

## 3.5 — פרמטרים חשובים
| Property | ערך |
|----------|------|
| **ArenaShowPosition** | `X:0, Y:0, Z:0` (מיקום הארנה הפעילה) |
| **ArenaShowRotation** | Identity (0,0,0) |

## 3.6 — תצוגה מקדימה
מערכת `cosmetic_applicator` תומכת ב-**Preview** — כשהשחקן גולש בחנות, הוא רואה את הסקין לפני הקנייה. הקוד מנהל את זה אוטומטית דרך `PreviewSkin()` / `EndPreview()`.

---

# 🧱 4. מערכת עריכת קירות

## 4.1 — איך עובד ה"אשליית עריכה"
בוטים ב-UEFN **לא יכולים** לערוך בניינים (HC-01). במקום זה, אנחנו משתמשים באשליה:

```
 [קיר מלא]     →  [קיר עם חלון]     →  [קיר מלא]
 (full_wall)       (window_variant)      (full_wall)
    גלוי             מוסתר               גלוי

        ╔═══════════╗
        ║  EDIT:    ║
        ║  הסתר את  ║  ← TeleportTo Z=-5000
        ║  הקיר     ║
        ║  הראה את  ║  ← TeleportTo מיקום הארנה
        ║  החלון    ║
        ╚═══════════╝
```

## 4.2 — Cluster (אשכול)
כל "עריכה" דורשת **אשכול** של 2-3 props חופפים:
- **Full Wall** — הגרסה הרגילה
- **Window Wall** — קיר עם חלון (ווריאנט #1)
- **Door Wall** — קיר עם דלת (ווריאנט #2)

## 4.3 — הכנה מעשית
1. מצא prop של קיר עם חלון → הנח 5 עותקים ב-Z=-5000
2. מצא prop של קיר עם דלת → הנח 5 עותקים ב-Z=-5000
3. חבר ל-`edit_state_manager`:
   - **WindowVariantProps[]** → 5 חלונות
   - **DoorVariantProps[]** → 5 דלתות

## 4.4 — מה הקוד עושה
`edit_state_manager.PerformEdit()`:
1. מחפש את ה-cluster הקרוב ביותר למיקום הבקשה
2. מחשב `EditDelay = BaseEditDelaySec / CurrentPlayRate`
3. ממתין (Sleep)
4. **מסתיר** את הווריאנט הנוכחי (TeleportTo Z=-5000)
5. **מראה** את הווריאנט החדש (TeleportTo מיקום הארנה)
6. מדווח ל-Event Bus → analytics_engine סופר edits

## 4.5 — תיאום עם אנימציה
`build_animation_sync.PlayEditAnimation()` מחשב את הרגע המדויק שבו ה-swap צריך לקרות:

```
SwapMoment = BaseEditDuration × (SelectPct + ConfirmPct) / PlayRate
```

ב-PlayRate 1.0: ה-swap ב-0.34 שניות.
ב-PlayRate 1.5 (Pro): ה-swap ב-0.22 שניות.

---

# 🧪 5. מבחני עומס

## 5.1 — מבחן 50 סבבים
1. Launch Session
2. שחק 50 סבבים רצופים
3. **בדוק:**
   - [ ] אין קריסות
   - [ ] בוט מופיע בכל סבב
   - [ ] Pool props חוזרים (FIFO)
   - [ ] NavMesh עובד — בוט לא נתקע
   - [ ] ELO משתנה
   - [ ] HUD מתעדכן

## 5.2 — מבחן 100 סבבים (Stress Test)
1. הגדר `RoundDurationSeconds = 10` (סבבים קצרים)
2. שחק 100 סבבים
3. **בדוק:**
   - [ ] אין lag מצטבר (memory leak)
   - [ ] Pool לא נגמר (FIFO reclaim עובד)
   - [ ] Output Log — אין שגיאות חוזרות
   - [ ] persistence_manager — שמירות מצליחות

> **🆕 v40 — אזהרת זיכרון:** יש באג ידוע ב-v40 שגורם לצריכת זיכרון גבוהה. אם UEFN מגיע ל-90%+ RAM, **סגור ופתח מחדש** לפני מבחני עומס ארוכים. מומלץ מאוד 16GB+ RAM.

## 5.3 — מבחן disconnect
1. שחק 5 סבבים → יצא מהאי (Escape → End Game)
2. חזור לאי
3. **בדוק:**
   - [ ] ELO נשמר — אותו מספר כמו לפני היציאה
   - [ ] W/L/D record תקין
   - [ ] סקין ארנה שהוצב עדיין פעיל

## 5.4 — מבחן frustration path
1. תפסיד 5+ סבבים ברציפות (עמוד ותן לבוט לירות)
2. **בדוק:**
   - [ ] הודעת מאמן על תסכול מופיעה
   - [ ] קושי יורד (ELO מוקטן זמנית)
   - [ ] Item Granter נותן healing
   - [ ] בסבב הבא — הבוט יותר קל

## 5.5 — מבחן stagnation path
1. שחק 10 סבבים ברמה דומה (נצח פעם, הפסד פעם)
2. **בדוק:**
   - [ ] הודעת stagnation מופיעה
   - [ ] volatility injection — שינוי ELO גדול יותר בסבבים הבאים

## 5.6 — 🆕 מבחן מובייל (v39+)
1. Launch Session עם **Mobile Preview** מופעל
2. שחק 3-5 סבבים
3. **בדוק:**
   - [ ] HUD קריא במסך קטן
   - [ ] כפתורים נגישים
   - [ ] ביצועים סבירים (אין lag חמור)

---

# ⚡ 6. אופטימיזציה

## 6.1 — Pool Size
- **ברירת מחדל:** 10 קירות, 6 רצפות, 6 רמפות, 4 חרוטים = **26 props**
- **מקסימום מומלץ:** 80 props (מתוך ~100 ceiling)
- אם צריך יותר → הקטן את מספר ה-props פר סוג והגדל FIFO reclaim

## 6.2 — ReclaimAll Yield
`build_pool_manager.ReclaimAll()` מבצע yield כל 4 teleports. אם יש lag בסוף סבב, הגדל ל-yield כל 2.

## 6.3 — Analytics Update Rate
`analytics_engine.PeriodicComputeLoop` רץ כל 0.5 שניות. אם יש lag — שנה ל-1.0 שניות.

## 6.4 — HUD Refresh Rate
`hud_binding` מתעדכן כל 0.5 שניות. אפשר להוריד ל-1.0 שניות אם צריך.

## 6.5 — 🆕 v40 — ניהול זיכרון
- v40 צורך **יותר RAM** מגרסאות קודמות (באג ידוע)
- מומלץ: **סגור כרטיסיות דפדפן ותוכנות מיותרות** לפני עבודה ב-UEFN
- אם RAM מגיע ל-90%+: שמור, סגור UEFN, ופתח מחדש
- Epic ציינו שהם עובדים על תיקון

---

# 🚀 7. פרסום

## 7.1 — לפני פרסום
1. החזר את `RoundDurationSeconds` ל-`60`
2. החזר את `LobbyWaitSeconds` ל-`5`
3. ודא שכל Pool Props ב-Z=-5000 (לא גלויים)
4. הסתר את de-Verse devices (אם גלויים) — הם כבר בלתי נראים כברירת מחדל

## 7.2 — Island Settings לפרסום
| שדה | ערך |
|------|------|
| Island Name | ProAI Training Map |
| Description | "AI-powered competitive training. Adaptive ELO. Real-time coaching." |
| Max Players | 1 (solo training) |
| Allow Respawn | Yes |

> **🆕 v39.40+ — תמונות נוספות:** אפשר עכשיו להציג **מספר תמונות** של האי בדף ה-Island Details — הוסף screenshots מסבבים שונים, HUD, חנות, ומאמן.

## 7.3 — פרסום
1. **File** → **Publish**
2. מלא את הפרטים (שם, תיאור, תמונה)
3. לחץ **Publish**
4. קבל **Island Code** — שתף עם שחקנים!

> **🆕 v40 — Star Wars Islands:** אם השתמשת בנכסי Star Wars, שים לב שפרסום ייפתח החל מ-**1 במאי 2026** (בזמן ל-Star Wars Day).

## 7.4 — גיבוי
1. **שמור** (Ctrl+S)
2. צור גיבוי: `ProAI_Complete_V2_Final_YYYYMMDD`
3. שמור בנפרד מהפרויקט הראשי

---

# 🌟 8. חידושי v40 — Star Wars, כלים חדשים ובאגים ידועים

## 8.1 — תוכן Star Wars (חדש ב-v40)
v40.00 הביא את אחד העדכונים הגדולים ביותר לתוכן ב-UEFN:

**תבניות חדשות:**
- **Lightsabers & Force Powers** — מערכת קרב עם חרבות אור וכוחות (Push, Heal, Mind Trick, Barrier, Detection)
- **Team Conquest** — לחימה בקנה מידה גדול על Tatooine עם Hero Device
- **Narrative RPG** — סיפור עם מערכת שיחות ו-NPC

**נכסים חדשים:**
- דמויות: Luke Skywalker, Darth Vader, Princess Leia, The Mandalorian, Chewbacca, Emperor Palpatine, Rey Skywalker
- כלי רכב: Speeder Bikes, AT-AT (ניתנים להתאמה דרך Spawner Devices)
- יצורים: Jawas, Tauntauns (רכיבים)
- סביבות: First Order Base, Nevarro City, Death Star, Republic Outpost
- רקעים: D'Qar, Hoth, Nevarro, Tatooine, Ion Cannon, Star Destroyer
- HUD מותאם אישית בסגנון Star Wars

**Hero Device:** מאפשר לשחקנים להפוך לגיבורים/נבלים עם יכולות ייחודיות.

**Force Powers (מופרדים מחרבות אור):** Push, Heal, Barrier, Mind Trick, Detection — ניתנים להקצאה עצמאית.

> **לפרויקט ProAI:** אפשר להשתמש בנכסי Star Wars כ**ווריאנט קוסמטי** לארנה (ראה סעיף 3), אבל **אל תשתמש ב-Hero Device** כתחליף למערכת הבוט שלנו — הארכיטקטורה לא תואמת.

## 8.2 — Book of Verse (חדש ב-v40)
כלי עזר מובנה חדש ללימוד ולעיון ב-Verse:
- **API Reference** מלא — כל הפונקציות, classes, ו-modules
- **דוגמאות קוד** מעשיות
- **הסברים** של concepts מרכזיים
- נגיש דרך **Home Panel** או **Help** → **Book of Verse**

## 8.3 — Home Panel מעוצב מחדש (v40)
- עיצוב חדש עם גישה מהירה יותר
- קישורים ישירים לתיעוד, Book of Verse, תבניות, וחדשות
- הצגת תבניות Star Wars בולטת

## 8.4 — Carryable Spawner — תמיכה בפיזיקה (v40)
- ה-Carryable Spawner Device תומך עכשיו בפיזיקה
- רלוונטי אם תרצה להוסיף אובייקטים נישאים לארנה בעתיד

## 8.5 — באגים ידועים ב-v40

| באג | תיאור | עקיפה |
|-----|-------|-------|
| **זיכרון** | צריכת RAM גבוהה מאוד (90%+) | סגור תוכנות, 16GB+ RAM, ריסטארט UEFN |
| **Build כפול** | Devices לא מופיעים אחרי Build Verse | בצע Ctrl+Shift+B פעמיים |
| **UMG Crash** | קריסה בקומפילציית widget עם Verse Fields | שמור לפני Compile, אל תעתיק overlays |
| **Scene Events** | Live Edit session עלול להיכשל עם Scene Events מסוימים | הסר references בעייתיים (ראה תיעוד Epic) |

---

# 📊 נספח: טבלת ה-ELO Brackets

| Bracket | טווח ELO | Reaction (ms) | Aim Variance | Build Rate | Aggression |
|---------|----------|---------------|-------------|-----------|------------|
| **Beginner** | 0-800 | 800→600 | 25→15 | 0.45→0.60 | 0 (פסיבי) |
| **Intermediate** | 800-1200 | 600→350 | 15→8 | 0.60→0.85 | 1 (זהיר) |
| **Advanced** | 1200-1600 | 350→200 | 8→3 | 0.85→1.0 | 2 (מאוזן) |
| **Pro** | 1600-2000 | 200→100 | 3→1 | 1.0→1.25 | 3 (תוקפני) |
| **Elite** | 2000+ | 100→40 | 1→0 | 1.25→1.5 | 4 (ברזרקר) |

**חישוב:** `difficulty_mapper` משתמש באינטרפולציה ליניארית **בתוך** כל bracket. שחקן ב-1400 ELO (50% דרך Advanced) מקבל:
- Reaction: 275ms
- Aim Variance: 5.5
- Build Rate: 0.925

---

# 📊 נספח: מפת קבצים לפי מודול

```
Core (3 קבצים):
  event_bus.verse              ← 14 ערוצי event, Dispatch/Listen API
  game_manager.verse           ← מכונת מצבים 5-שלבית, race 3-כיווני
  arena_controller.verse       ← spawn/despawn בוט, ניקוי ארנה

Module A — Bot AI (6 קבצים):
  bot_behavior_base.verse      ← נקודת כניסה npc_behavior, race/branch
  bot_combat_state_machine.verse ← 5 מצבי קרב
  bot_navigation.verse         ← NavMesh דו-תבניתי
  bot_focus_aim.verse          ← מעקב ראש + variance
  bot_weapon_controller.verse  ← Shotgun/AR, LCG פסאודו-רנדומי
  bot_difficulty_profile.verse ← 10 פרמטרים מותאמי-ELO

Module B — Build Simulation (5 קבצים):
  build_pool_manager.verse     ← Object Pool + FIFO reclaim
  build_prop_spawner.verse     ← מתמטיקת רשת 256×256
  edit_state_manager.verse     ← אשליית עריכה (swap ווריאנטים)
  build_sequence_choreographer.verse ← box-up, ramp-rush, retake
  build_animation_sync.verse   ← תיאום 3-פאזי (windup/throw/recovery)

Module C — Analytics & ELO (6 קבצים):
  metric_definitions.verse     ← 25 שדות round_metrics
  analytics_engine.verse       ← 6 branch listeners + compute loop
  elo_calculator.verse         ← Taylor series 8-term ל-Pow10
  difficulty_mapper.verse      ← ELO → פרמטרים (Lerp 5 brackets)
  predictive_advisor.verse     ← stagnation, frustration, trends
  session_aggregator.verse     ← סיכום session + cross-session delta

Module D — Persistence (5 קבצים):
  data_schema_v1.verse         ← 4 persistable classes (V1)
  data_schema_v2.verse         ← 4 persistable classes (V2)
  migration_v1_to_v2.verse     ← העברה בטוחה V1→V2
  data_validator.verse         ← sanitization + telemetry
  persistence_manager.verse    ← 4 weak_maps + cache layer + auto-save

Module E — Coach (3 קבצים):
  feedback_templates.verse     ← 10 קטגוריות × 3-5 ווריאנטים
  coach_controller.verse       ← 10 triggers בסדר עדיפות
  coach_game_bridge.verse      ← coach → game state changes

Module F — Economy (4 קבצים):
  shop_manager.verse           ← קטלוג מוצרים + pipeline קנייה
  inventory_controller.verse   ← bitfield ownership + consume
  cosmetic_applicator.verse    ← swap ארנה + preview
  xp_reward_system.verse       ← accolades + budget enforcement

UI (3 קבצים):
  hud_binding.verse            ← Canvas HUD + Verse Fields UMG binding (v38+)
  scorecard_renderer.verse     ← overlay תוצאות
  shop_ui_controller.verse     ← UI חנות + terminal listener
```

---

**סה"כ: 35 קבצים · ~8,500 שורות Verse · 6 מודולים · ארכיטקטורה מלאה**

*מסמך זה מעודכן לגרסה v40.00 — מרץ 2026.*

</div>
