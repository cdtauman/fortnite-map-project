<div dir="rtl" align="right">

# 🎮 המדריך האולטימטיבי — ProAI Training Map V2
## UEFN v40.00+ | מדריך מלא מאפס עד מפה עובדת
## 35 קבצי Verse · 6 מודולים · פרסיסטנס מלא · מאמן AI

> **⚡ מעודכן לגרסה 40.00 (מרץ 2026)** — כולל Home Panel חדש, Book of Verse, Verse Fields ב-UMG, Debug Commands, Mobile Preview, ותוכן Star Wars.

---

# 📋 תוכן עניינים

1. [התקנת UEFN](#-פרק-1-התקנת-uefn)
2. [יצירת פרויקט חדש](#-פרק-2-יצירת-פרויקט-חדש)
3. [הכרת המסך](#-פרק-3-הכרת-המסך)
4. [יצירת קבצי Verse](#-פרק-4-יצירת-קבצי-verse)
5. [בניית הארנה](#-פרק-5-בניית-הארנה)
6. [הגדרת הבוט](#-פרק-6-הגדרת-הבוט)
7. [הגדרת השחקן](#-פרק-7-הגדרת-השחקן)
8. [הנחת Devices בסצנה](#-פרק-8-הנחת-devices-בסצנה)
9. [חיווט @editable — המדריך המלא](#-פרק-9-חיווט-editable--המדריך-המלא)
10. [הגדרת Pool Props לבנייה](#-פרק-10-הגדרת-pool-props-לבנייה)
11. [הגדרת חנות ו-XP](#-פרק-11-הגדרת-חנות-ו-xp)
12. [בדיקה ראשונה](#-פרק-12-בדיקה-ראשונה)
13. [פתרון בעיות](#-פרק-13-פתרון-בעיות)
14. [צ'קליסט סופי](#-פרק-14-צקליסט-סופי)

---

# 🖥️ פרק 1: התקנת UEFN

## 1.1 — התקנת Epic Games Launcher
1. פתח דפדפן → `www.epicgames.com` → לחץ **Download**
2. הפעל את הקובץ שהורדת → **Next** → **Install** → **Finish**
3. כתוב מייל וסיסמה (או צור חשבון חדש)

## 1.2 — התקנת Fortnite (חובה!)
1. ב-Launcher → **Store** → חפש `Fortnite` → **Get** → **Install**
2. המתן — Fortnite גדול (~30-80 GB)

## 1.3 — התקנת UEFN
1. **Store** → חפש `UEFN` → **Get** → **Install** (~20 GB)
2. אחרי ההתקנה, UEFN יופיע ב-**Library**

## 1.4 — פתיחה ראשונה
1. **Library** → **Unreal Editor for Fortnite** → **Launch**
2. אשר תנאי שימוש → **Accept**
3. **🆕 v40:** בפתיחה הראשונה תראה את ה-**Home Panel** המעוצב מחדש — הוא כולל עכשיו גישה מהירה לחדשות, תיעוד, תבניות (כולל תבניות Star Wars חדשות), ו-**Book of Verse** (כלי עזר חדש ללימוד Verse)

---

# 📂 פרק 2: יצירת פרויקט חדש

## 2.1 — בחירת תבנית
1. לחץ **Island Templates** → מצא **Blank** (אי ריק) → לחץ עליו
> **🆕 v40:** בנוסף ל-Blank, יש עכשיו תבניות Star Wars (Lightsabers & Force Powers, Team Conquest, Narrative RPG) — **אל תשתמש בהן** לפרויקט ProAI. בחר **Blank**.

## 2.2 — שם הפרויקט
1. בשדה **Project Name** כתוב: `ProAI_TrainingMap`
2. לחץ **Create** → המתן 30-120 שניות

## 2.3 — הפעלת Asset Reflection
1. **סגור את UEFN לגמרי**
2. מצא את קובץ הפרויקט: `ProAI_TrainingMap.uplugin`
   - מיקום: `C:\Users\[שם]\AppData\Local\UEFN\...`
3. פתח ב-Notepad → מצא את שורת `VersePath` → הוסף מתחתיה:
   ```json
   "EnableVerseAssetReflection": true
   ```
4. שמור → פתח UEFN מחדש

## 2.4 — שמירה ראשונה
- **Ctrl+S** → **Save Selected**

---

# 🗺️ פרק 3: הכרת המסך

| אזור | מיקום | תפקיד |
|-------|-------|--------|
| **Home Panel** | מסך פתיחה | 🆕 עוצב מחדש ב-v40 — חדשות, תבניות, Book of Verse |
| **Viewport** | מרכז | העולם שלך בתלת-מימד |
| **Outliner** | ימין למעלה | רשימת כל האובייקטים בסצנה |
| **Details Panel** | ימין למטה | הגדרות האובייקט הנבחר |
| **Content Drawer** | למטה | כל הקבצים והנכסים בפרויקט (שם ישן: Content Browser) |
| **Toolbar** | למעלה | כפתורי שמירה, Build, Launch |

> **🆕 v40 — שינוי שם:** מה שנקרא בעבר **Content Browser** נקרא עכשיו **Content Drawer** ברוב הממשק. שני השמות עדיין עובדים, אבל במדריך הזה נשתמש ב-**Content Drawer**.

> **🆕 v40 — Book of Verse:** כלי עזר מובנה חדש ללימוד Verse. נגיש דרך ה-Home Panel או דרך תפריט **Help**. מכיל דוגמאות קוד, הסברים, ו-API reference מלא.

**ניווט ב-Viewport:**
- גלגלת עכבר = זום פנימה/חוצה
- לחיצה ימנית + תזוזה = סיבוב מבט
- לחיצה ימנית + WASD = טיסה חופשית

**קיצורים חשובים:**
- **W** = הזזה, **E** = סיבוב, **R** = שינוי גודל
- **Ctrl+S** = שמירה
- **Ctrl+Shift+B** = Build Verse Code
- **Alt+P** = Launch Session (הרצה)

**🆕 v39.40+ — Debug Commands:**
- שינוי View Mode, טלפורט לנקודת כוונת, שינוי צוות ומחלקה — זמינים דרך **Debug Commands** (ניתנים לקשירת קיצורים)

---

# 📝 פרק 4: יצירת קבצי Verse

## 4.1 — פתיחת Verse Explorer
1. תפריט עליון → **Verse** → **Verse Explorer**
2. ייפתח פאנל בצד ימין עם עץ תיקיות

## 4.2 — יצירת 35 קבצים
**חזור על השלבים האלה עבור כל קובץ:**

1. **לחץ ימני** על **שם הפרויקט** (למעלה ב-Verse Explorer)
2. **Add new Verse file to project**
3. **Template:** בחר **Create Empty** (עבור כולם **חוץ מ-`bot_behavior_base`** — שם בחר **NPC Behavior Basic**)
4. **Device Name:** כתוב את השם **בדיוק** — אותיות קטנות, קווים תחתונים, **בלי `.verse`**
5. לחץ **Create**

> **⚠️ שינוי מ-v39:** בגרסאות ישנות לחצת ימני על **Content**. מ-v39+ לוחצים ימני על **שם הפרויקט**. הכפתור השתנה ל-**"Add new Verse file to project"** במקום "Create New Verse File".

### רשימת כל 35 הקבצים:

**Core (3):**
```
event_bus
game_manager
arena_controller
```

**Module A — Bot AI (6):**
```
bot_behavior_base          ← NPC Behavior Basic!
bot_combat_state_machine
bot_navigation
bot_focus_aim
bot_weapon_controller
bot_difficulty_profile
```

**Module B — Build Simulation (5):**
```
build_pool_manager
build_prop_spawner
edit_state_manager
build_sequence_choreographer
build_animation_sync
```

**Module C — Analytics & ELO (6):**
```
metric_definitions
analytics_engine
elo_calculator
difficulty_mapper
predictive_advisor
session_aggregator
```

**Module D — Persistence (5):**
```
data_schema_v1
data_schema_v2
migration_v1_to_v2
data_validator
persistence_manager
```

**Module E — Coach (3):**
```
feedback_templates
coach_controller
coach_game_bridge
```

**Module F — Economy (4):**
```
shop_manager
inventory_controller
cosmetic_applicator
xp_reward_system
```

**UI (3):**
```
hud_binding
scorecard_renderer
shop_ui_controller
```

## 4.3 — העתקת קוד
1. פתח את הקובץ מתיקיית `Verse_Code/` ב-Notepad
2. **Ctrl+A** (בחר הכל) → **Ctrl+C** (העתק)
3. ב-VS Code — **Ctrl+A** → **Ctrl+V** (הדבק)
4. **Ctrl+S** (שמור)
5. חזור על 35 פעמים

## 4.4 — Build Verse
1. **Ctrl+Shift+B** (או: תפריט **Verse** → **Build Verse Code**)
2. **יעד: אפס שגיאות** ← חובה!
3. אם יש שגיאות — קרא את ההודעה ב-Output Log, תקן, ובנה מחדש
4. בהצלחה — סימן ✅ ירוק יופיע ליד כפתור **Verse** בטולבר

> **🆕 v40 — Book of Verse:** אם אתה חדש ב-Verse ויש שגיאות שאתה לא מבין, פתח את **Book of Verse** מה-Home Panel — יש שם הסברים מלאים לכל syntax ו-API.

---

# 🏟️ פרק 5: בניית הארנה

## 5.1 — רצפה
1. ב-Content Drawer, חפש: `Floor` או `Platform`
2. בחר **אריח רצפה גדול** (מהספריית Fortnite Props)
3. גרור ל-Viewport → מקם ב-`X:0, Y:0, Z:0`
4. ב-Details Panel → **Scale:** `20, 20, 1`
5. ⚠️ **חובה:** השתמש ב-**Traditional Geometry** — לא Scene Graph. אחרת NavMesh לא יעבוד (HC-03)

> **הערה v40:** ניתן לבנות ארנות גם בסגנון Star Wars (Hoth, Tatooine) עם הנכסים החדשים — אבל **לצורך הפרויקט הזה, השתמש ב-Traditional Geometry בלבד** כדי להבטיח NavMesh תקין.

## 5.2 — NavMesh
1. תפריט **Build** → **Build Navigation**
2. תפריט **Show** → **Navigation** → סמן ☑
3. ודא: כיסוי **ירוק** על כל שטח הרצפה
4. אם אין ירוק — הרצפה לא מסוג Traditional Geometry. החלף

## 5.3 — קירות גבול (אופציונלי)
- הנח קוביות גבוהות בארבעת צדדי הארנה כדי שהבוט לא ייפול

---

# 🤖 פרק 6: הגדרת הבוט

## 6.1 — NPC Character Definition
1. **Content Drawer** → לחץ ימני → **AI** → **NPC Character Definition**
2. שם: `BP_CombatBot_Base` (ב-Content root)
3. פתח בלחיצה כפולה

## 6.2 — הגדרות NPC
| שדה | ערך |
|------|------|
| Body / Skin | כל skin זמין |
| **Behavior Type** | **Guard** (חובה — מאפשר ירי) |
| **Behavior Script** | `bot_behavior_base` (ה-Verse class שלנו) |
| Weapon / Equipment | Pump Shotgun |

4. **שמור** (Ctrl+S)

> **🆕 v39+ — NPC Scene Graph Components:** Epic הוסיפה אפשרות חדשה לשליטה ב-NPC דרך **Scene Graph Components** המחוברים לישויות NPC. זה נותן שליטה גרנולרית יותר על AI. **לפרויקט הזה, המשך להשתמש בשיטת ה-Behavior Script הקלאסית** — היא עובדת מצוין ומתאימה לצרכים שלנו.

> **🆕 v40 — Star Wars NPCs:** יש עכשיו דמויות Star Wars זמינות (Luke, Vader, Mando ועוד) — אל תשתמש בהן לבוט הקרבי, הן דורשות Hero Device ולא מתאימות לארכיטקטורה שלנו.

## 6.3 — NPC Spawner
1. ב-Content Drawer חפש `NPC Spawner`
2. **גרור ל-Viewport** → מקם **במרכז הארנה**
3. ב-Details Panel:

| שדה | ערך |
|------|------|
| NPC Character Definition | `BP_CombatBot_Base` |
| Spawn on Game Start | **Disabled** (כבוי) |
| Auto Respawn | **Disabled** |
| Max Spawn Count | `1` |

## 6.4 — בוט חלופי (למעבר סגנון ע"י המאמן)
1. צור **NPC Character Definition** נוסף: `BP_CombatBot_Alt`
2. הגדר עם skin אחר ו-AR במקום Shotgun
3. Behavior Script = `bot_behavior_base`
4. הנח **NPC Spawner נוסף** → Character Definition = `BP_CombatBot_Alt`
5. Spawn on Game Start = **Disabled**

---

# 👤 פרק 7: הגדרת השחקן

## 7.1 — Player Spawner
1. חפש `Player Spawner` או `Player Spawn Pad`
2. גרור ל-Viewport → מקם **בקצה הארנה** (הרחק מה-NPC Spawner)
3. כוון (לחץ **E**) שהחץ מצביע לכיוון ה-NPC Spawner

## 7.2 — Item Granter
1. חפש `Item Granter` → גרור ליד ה-Player Spawner
2. ב-Details Panel:
   - Item to Grant → `Pump Shotgun`
   - Number of Items → `1`
   - Grant on Game Start → **Enabled** ☑

## 7.3 — Island Settings
1. ב-Outliner, חפש `IslandSettings` → לחץ עליו
2. ב-Details Panel:
   - Down But Not Out → **Off**
   - Player Respawn → **Respawn After Delay**

---

# 📦 פרק 8: הנחת Devices בסצנה

## 8.1 — למה
כל `creative_device` בקוד **חייב** להיות כאובייקט פיזי בסצנה. בלי זה, הקוד לא ירוץ.

## 8.2 — איך
אחרי Build Verse מוצלח, ב-Content Drawer תראה **קוביות כחולות** — אלה ה-devices.

> **🆕 v40 — שימו לב:** אם devices לא מופיעים ב-Content Drawer אחרי Build, בצע **Ctrl+Shift+B** שוב. יש באג ידוע ב-v40 שלפעמים דורש build כפול. בדוק גם שאין בעיית זיכרון (v40 צורך יותר RAM — מומלץ לפחות 16GB).

## 8.3 — רשימת כל ה-Devices להנחה

**גרור כל אחד מה-Content Drawer ל-Viewport. מקם בפינת הארנה — הם בלתי נראים במשחק.**

| # | שם ב-Content Drawer | סוג |
|---|---|---|
| 1 | `event_bus` | Core |
| 2 | `game_manager` | Core |
| 3 | `arena_controller` | Core |
| 4 | `analytics_engine` | Module C |
| 5 | `persistence_manager` | Module D |
| 6 | `coach_controller` | Module E |
| 7 | `coach_game_bridge` | Module E |
| 8 | `hud_binding` | UI |
| 9 | `scorecard_renderer` | UI |
| 10 | `build_pool_manager` | Module B |
| 11 | `edit_state_manager` | Module B |
| 12 | `shop_manager` | Module F |
| 13 | `shop_ui_controller` | Module F |
| 14 | `xp_reward_system` | Module F |
| 15 | `cosmetic_applicator` | Module F |

**⚠️ שים לב:** קבצים שהם plain class (לא `creative_device`) **לא** צריכים להיות בסצנה. הם פועלים כמחלקות פנימיות. רשימת קבצים שאינם devices:

```
bot_behavior_base (npc_behavior — מנוהל ע"י NPC Spawner)
bot_combat_state_machine, bot_navigation, bot_focus_aim,
bot_weapon_controller, bot_difficulty_profile, build_prop_spawner,
build_sequence_choreographer, build_animation_sync, metric_definitions,
elo_calculator, difficulty_mapper, predictive_advisor, session_aggregator,
data_schema_v1, data_schema_v2, migration_v1_to_v2, data_validator,
feedback_templates, inventory_controller
```

## 8.4 — Devices נוספים מ-UEFN (לא מקוד)
גרור גם את אלה מספריית Fortnite:

| # | חפש ב-Content Drawer | תפקיד |
|---|---|---|
| 16 | `HUD Message Device` | הודעות מאמן על המסך |
| 17 | `Button Device` × 5 | כפתור חנות #1-4 + כפתור "קרא למאמן" |
| 18 | `Item Granter Device` (נוסף) | עזרה בתסכול (healing items) |
| 19 | `Accolades Device` × 6 | XP: Win, Loss, Headshot, RankUp, Session, Streak |

**שמור: Ctrl+S**

---

# 🔌 פרק 9: חיווט @editable — המדריך המלא

## 9.0 — איך עושים חיווט

**כל חיווט עובד אותו דבר:**
1. **בחר** device ב-Viewport (מסגרת כתומה)
2. ב-**Details Panel** (ימין), גלול למטה לאזור ה-Verse properties
3. ליד כל property יש **dropdown** (חץ ▼) → לחץ עליו
4. **בחר** את ה-device הנכון מהרשימה
5. הערך משתנה — מחובר!

**⚠️ אם ה-dropdown ריק:** ה-device לא בסצנה. חזור לפרק 8.

---

## 9.1 — game_manager (הליבה — 7 חיווטים)

**בחר את `game_manager` ב-Viewport → ב-Details Panel:**

| Property | חבר ל- | הסבר |
|----------|---------|-------|
| **EventBus** | `event_bus` | אפיק האירועים המרכזי |
| **ArenaCtrl** | `arena_controller` | שליטה בארנה ובבוט |
| **Analytics** | `analytics_engine` | מערכת המדידה |
| **Persistence** | `persistence_manager` | שמירת נתונים |
| **Coach** | `coach_controller` | מאמן AI |
| **HUD** | `hud_binding` | ממשק חי |
| **Scorecard** | `scorecard_renderer` | כרטיס תוצאות |

**פרמטרי זמן (שדות מספריים — לא dropdowns):**

| Property | ערך לבדיקה | ערך ייצור |
|----------|-----------|----------|
| LobbyWaitSeconds | `2` | `5` |
| CountdownSeconds | `2` | `3` |
| RoundDurationSeconds | `15` | `60` |
| PostRoundDisplaySeconds | `2` | `5` |
| ResetCooldownSeconds | `1` | `1.5` |

---

## 9.2 — arena_controller (6 חיווטים)

| Property | חבר ל- | הסבר |
|----------|---------|-------|
| **EventBus** | `event_bus` | אפיק אירועים |
| **BotSpawner** | NPC Spawner device (הראשי) | ⚠️ ה-NPC Spawner — לא BP_CombatBot! |
| **PlayerSpawnPad** | Player Spawner device | נקודת ספאון שחקן |
| **BuildPoolRef** | `build_pool_manager` | מאגר אובייקטי בנייה |
| **AltBotSpawner** | NPC Spawner device (החלופי) | לשינוי סגנון בוט ע"י המאמן |
| **ArenaBoundaryZone** | Barrier device (אופציונלי) | גבולות ארנה |

**פרמטרים:**
- `BotSpawnSettleTime` → `0.5`
- `DespawnSettleTime` → `0.3`
- `UseAltBotSpawner` → `false`
- `EnableBoundaryZone` → `false` (אלא אם הנחת barrier)

---

## 9.3–9.14 — שאר החיווטים

> **ללא שינוי מגרסה קודמת** — כל החיווטים של analytics_engine, persistence_manager, coach_controller, coach_game_bridge, hud_binding, scorecard_renderer, build_pool_manager, edit_state_manager, shop_manager, shop_ui_controller, xp_reward_system, cosmetic_applicator **זהים לחלוטין** לגרסה הקודמת. ראה את הטבלאות המפורטות בגרסה המקורית (חלקים 9.3–9.14).

**סיכום מהיר:**
- `analytics_engine` → 1 חיווט (EventBus)
- `persistence_manager` → 1 חיווט (EventBus)
- `coach_controller` → 4 חיווטים (EventBus, AnalyticsRef, CoachHUD, PersistenceRef)
- `coach_game_bridge` → 7 חיווטים (EventBus, AnalyticsRef, ArenaCtrlRef, PersistRef, CoachRef, FrustrationAid, CoachCallButton)
- `hud_binding` → 2 חיווטים (EventBus, AnalyticsRef)
- `scorecard_renderer` → 2 חיווטים (EventBus, AnalyticsRef)
- `build_pool_manager` → 1 חיווט + 4 מערכים (EventBus + WallProps/FloorProps/RampProps/ConeProps)
- `edit_state_manager` → 2 חיווטים + 2 מערכים (EventBus, PoolManagerRef + WindowVariantProps/DoorVariantProps)
- `shop_manager` → 5+ חיווטים (EventBus, PersistenceRef, CosmeticRef, Buttons)
- `shop_ui_controller` → 4 חיווטים (ShopMgr, PersistMgr, ShopTerminalBtn, CloseShopBtn)
- `xp_reward_system` → 8 חיווטים (EventBus, AnalyticsRef, 6× Accolades)
- `cosmetic_applicator` → 5 חיווטים (DefaultArena, ClassicArena, CyberArena, NeonArena, TourneyArena)

---

## 🗺️ מפת חיווטים — סיכום ויזואלי

```
                    event_bus
                       │
    ┌──────────────────┼──────────────────────────────┐
    │         │        │        │        │        │   │
    ▼         ▼        ▼        ▼        ▼        ▼   ▼
game_mgr  arena_ctrl  analytics  persist  coach   hud  xp
    │         │                    │       │
    ├─arena   ├─BotSpawner         │       ├─analytics
    ├─analytics├─PlayerSpawn       │       ├─CoachHUD
    ├─persist ├─BuildPool          │       ├─persist
    ├─coach                        │
    ├─hud                coach_bridge
    └─scorecard            ├─analytics
                           ├─arena_ctrl
                           ├─persist
                           ├─coach
                           ├─FrustrationAid
                           └─CoachCallBtn
```

---

# 🧱 פרק 10: הגדרת Pool Props לבנייה

## 10.1 — מה צריך
מערכת הבנייה של הבוט לא משתמשת ב-SpawnProp — היא מעבירה props קיימים ממיקום מוסתר (Z=-5000) למיקום הרצוי. צריך להניח props **מראש** ולחבר אותם ל-`build_pool_manager`.

## 10.2 — הכנת Wall Props
1. ב-Content Drawer חפש `Wall` (ספריית Fortnite)
2. בחר אריח קיר → גרור ל-Viewport **10 פעמים** (10 עותקים)
3. לכל אחד: ב-Details Panel → Location Z = `-5000` (מתחת לקרקע)
4. חזור ל-`build_pool_manager` → ב-Details → **WallProps** → לחץ **+** 10 פעמים
5. גרור כל prop בנפרד לתוך ה-slot המתאים ברשימה

## 10.3 — חזור על זה עבור:
- **FloorProps** — 6 אריחי רצפה
- **RampProps** — 6 רמפות
- **ConeProps** — 4 חרוטים

## 10.4 — ווריאנטים לעריכה
עבור `edit_state_manager`:
1. הנח 5 קירות עם חלון ("Window Wall") ב-Z=-5000
2. הנח 5 קירות עם דלת ("Door Wall") ב-Z=-5000
3. חבר ל-**WindowVariantProps** ו-**DoorVariantProps**

---

# 🛒 פרק 11: הגדרת חנות ו-XP

## 11.1 — טרמינל חנות
1. הנח **5 Button Devices** באזור הלובי — ליד ה-Player Spawner
2. תייג כל אחד (שנה Label ב-Details):
   - Button 1: "Analytics Pass — 800 V-Bucks"
   - Button 2: "Cyber Arena — 300 V-Bucks"
   - Button 3: "Neon Arena — 300 V-Bucks"
   - Button 4: "5 Tokens — 250 V-Bucks"
   - Button 5: "Call Coach"
3. חבר כל אחד ל-shop_manager / coach_game_bridge (ראה חיווטים 9.11, 9.6)

> **🆕 v39+ — In-Island Transactions:** מערכת העסקאות בתוך האי **פעילה** מ-9 בינואר 2026. אם אתה מתכנן למכור באמת ב-V-Bucks, עיין בתיעוד הרשמי של **In-Island Transactions** ב-Creator Portal ובדוק שאתה עומד בכל הדרישות.

## 11.2 — Accolades Devices
1. הנח **6 Accolades Devices** (ספריית Fortnite)
2. ב-Details Panel של כל אחד, הגדר XP Amount:

| Accolade | XP Amount |
|----------|-----------|
| Win | 8000 |
| Loss | 3000 |
| Headshot | 5000 |
| RankUp | 15000 |
| Session | 10000 |
| Streak | 12000 |

3. חבר ל-xp_reward_system (ראה חיווט 9.13)

## 11.3 — Item Granter לתסכול
1. הנח **Item Granter נוסף** (בנפרד מזה של השחקן)
2. הגדר: Item = Small Shield Potion, Count = 3
3. Grant on Game Start = **Disabled**
4. חבר ל-coach_game_bridge → FrustrationAid

---

# ▶️ פרק 12: בדיקה ראשונה

## 12.1 — לפני ההרצה
1. **Ctrl+Shift+B** — Build Verse → אפס שגיאות
2. **Ctrl+S** — שמור הכל
3. **Build** → **Build Navigation** (אם שינית את הרצפה)

## 12.2 — הרצה
1. לחץ **Launch Session** (כפתור ירוק בטולבר) או **Alt+P**
2. המתן — Fortnite ייפתח ותיכנס לאי שלך

> **🆕 v39+ — Mobile Preview:** אפשר להריץ בדיקה במצב מובייל ישירות מ-UEFN, כדי לראות איך המפה נראית במכשירים ניידים.

## 12.3 — מה לבדוק

| # | בדוק | מצופה |
|---|------|-------|
| 1 | הבוט מופיע אחרי ספירה לאחור | COUNTDOWN → FIGHT |
| 2 | הבוט רודף ויורה | תנועה + ירי |
| 3 | הריגת הבוט מסיימת סבב | POST_ROUND scorecard |
| 4 | הודעת מאמן מופיעה | טקסט צהוב למטה |
| 5 | ELO משתנה | מספר ב-status bar |
| 6 | סבב חדש מתחיל אוטומטית | RESET → LOBBY → COUNTDOWN |
| 7 | נתונים חיים ב-HUD | DPS, ACC, HS% |

## 12.4 — סיום בדיקה
- Escape → End Game → חזור ל-UEFN

> **🆕 v39.40+ — Debug Commands:** במהלך בדיקה, אפשר להשתמש ב-Debug Commands לטלפורט, שינוי צוות, ושינוי View Mode.

---

# ❗ פרק 13: פתרון בעיות

| # | בעיה | פתרון |
|---|------|-------|
| 1 | Build Verse נכשל | קרא שגיאות ב-Output Log. בדוק ש-35 קבצים קיימים בשמות נכונים. 🆕 השתמש ב-Book of Verse להבנת שגיאות |
| 2 | Device לא מופיע ב-Content Drawer | Ctrl+Shift+B ← Build Verse Code. 🆕 v40: לפעמים צריך build כפול |
| 3 | הבוט לא מופיע | בדוק NPC Spawner → Character Definition = BP_CombatBot_Base |
| 4 | הבוט לא זז | Build → Build Navigation. בדוק NavMesh ירוק |
| 5 | הבוט לא יורה | BP_CombatBot_Base → Behavior Type = Guard |
| 6 | הסבב לא נגמר | arena_controller → BotSpawner = NPC Spawner |
| 7 | @editable ריק ב-dropdown | ה-device לא בסצנה — גרור אותו |
| 8 | "Unknown identifier" | קובץ חסר — ודא שכל 35 נוצרו |
| 9 | "Duplicate definition" | קובץ כפול — מחק את הכפילות |
| 10 | Pool props לא מופיעים | בדוק WallProps/FloorProps/RampProps/ConeProps ב-build_pool_manager |
| 11 | אין XP | ודא ש-Accolades Devices מחוברים ל-xp_reward_system |
| 12 | חנות לא עובדת | ודא ש-Button Devices מחוברים ל-shop_manager |
| 13 | ELO לא נשמר בין sessions | ודא ש-persistence_manager בסצנה ומחובר EventBus |
| 14 | מאמן לא מדבר | ודא coach_controller → CoachHUD = HUD Message Device |
| 15 | HUD ריק | ודא hud_binding → AnalyticsRef = analytics_engine |
| 16 | 🆕 UEFN אוכל יותר מדי RAM | באג ידוע ב-v40 — סגור תוכנות אחרות. מומלץ 16GB+ RAM |
| 17 | 🆕 UMG Widget קורס בקומפילציה | באג ידוע ב-v40 — שמור לפני Compile, אל תעתיק overlay עם Verse Fields בין widgets |

---

# 🎯 פרק 14: צ'קליסט סופי

```
שלב 0 — תשתית:
[ ] UEFN v40+ + Fortnite מותקנים
[ ] פרויקט ProAI_TrainingMap נוצר
[ ] uplugin: EnableVerseAssetReflection = true

שלב 1 — קוד:
[ ] 35 קבצי Verse נוצרו (Add new Verse file to project)
[ ] תוכן כל קובץ הודבק מהזיפ
[ ] Build Verse = אפס שגיאות

שלב 2 — ארנה:
[ ] רצפה Traditional Geometry (Scale 20,20,1)
[ ] Build Navigation → NavMesh ירוק
[ ] קירות גבול (אופציונלי)

שלב 3 — בוט:
[ ] BP_CombatBot_Base: Guard, Shotgun, bot_behavior_base
[ ] BP_CombatBot_Alt: Guard, AR, bot_behavior_base (אופציונלי)
[ ] NPC Spawner ראשי: Spawn on Start = Disabled
[ ] NPC Spawner חלופי (אופציונלי)

שלב 4 — שחקן:
[ ] Player Spawner מונח ומכוון
[ ] Item Granter: Pump Shotgun, Grant on Start
[ ] Island Settings: DBNO = Off

שלב 5 — Devices:
[ ] 15 creative devices מהקוד → בסצנה
[ ] 1 HUD Message Device → בסצנה
[ ] 5 Button Devices → בסצנה
[ ] 6 Accolades Devices → בסצנה
[ ] 1 Item Granter (healing) → בסצנה

שלב 6 — חיווטים (47 סה"כ):
[ ] game_manager → 7 חיווטים
[ ] arena_controller → 6 חיווטים
[ ] analytics_engine → 1 חיווט
[ ] persistence_manager → 1 חיווט
[ ] coach_controller → 4 חיווטים
[ ] coach_game_bridge → 7 חיווטים
[ ] hud_binding → 2 חיווטים
[ ] scorecard_renderer → 2 חיווטים
[ ] build_pool_manager → 1 + 4 מערכים
[ ] edit_state_manager → 2 + 2 מערכים
[ ] shop_manager → 7 חיווטים
[ ] shop_ui_controller → 4 חיווטים
[ ] xp_reward_system → 8 חיווטים
[ ] cosmetic_applicator → 5 חיווטים

שלב 7 — Pool Props:
[ ] 10 Wall Props ב-Z=-5000 → מחוברים ל-WallProps[]
[ ] 6 Floor Props ב-Z=-5000 → מחוברים ל-FloorProps[]
[ ] 6 Ramp Props ב-Z=-5000 → מחוברים ל-RampProps[]
[ ] 4 Cone Props ב-Z=-5000 → מחוברים ל-ConeProps[]
[ ] 5 Window Variants ב-Z=-5000 → WindowVariantProps[]
[ ] 5 Door Variants ב-Z=-5000 → DoorVariantProps[]

שלב 8 — בדיקה:
[ ] Launch Session עובד
[ ] סבב שלם: LOBBY→COUNTDOWN→FIGHT→POST→RESET
[ ] בוט רודף ויורה
[ ] ELO משתנה
[ ] HUD מציג נתונים חיים
[ ] הודעת מאמן מופיעה
[ ] 5 סבבים רצופים ← ללא קריסה
[ ] 🆕 Mobile Preview — בדיקה במצב מובייל (אופציונלי)
```

---

**🎉 אם כל הצ'קליסט מסומן — המפה שלך פועלת!**

ראה `03_ADDENDUM_HEBREW_V40.md` עבור:
- הגדרת NPC מאמן (Persona Device — כעת זמין!)
- יצירת UMG Widget Blueprints (עם **Verse Fields** — יציב מ-v38+)
- הגדרת ווריאנטים קוסמטיים
- מבחני עומס (100 סבבים)
- **🆕 תוכן Star Wars ב-v40**
- **🆕 באגים ידועים ב-v40 ועקיפות**

</div>
