# ProAI Training Map — Competitive AI Practice for Fortnite Creative

> A 24/7 AI-driven competitive training environment built entirely in UEFN/Verse.
> 35+ production Verse files. Zero external dependencies. Pure in-engine architecture.

---

## What This Is

ProAI Training Map is a fully autonomous competitive practice island for Fortnite Creative. A player joins, fights an AI bot that adapts to their skill level in real time, receives metric-driven coaching feedback after every round, and returns days later to find their ELO, analytics history, and purchased cosmetics exactly where they left them.

Every system — from the ELO calculator's Taylor-series exponentiation to the quest tracker's integer bitfield compression — was designed to run within UEFN's hard constraints: 4 persistent weak_maps, ~100 active spawned props, zero HTTP calls, and no external databases.

---

## Core Systems

### Adaptive ELO & Difficulty Scaling

The analytics engine computes a composite performance score from DPS, accuracy, headshot ratio, reaction time, and edit speed after every round. The ELO calculator updates the player's rating using a full Elo expected-probability model with bracket-aware K-factor selection (K=48 for placement rounds, K=64 during volatility injection, K=32 standard, K=16 for stabilized veterans). The probability function `1 / (1 + 10^((BotELO - PlayerELO) / 400))` requires `10^x` — which Verse doesn't provide — so the calculator implements an 8-term Taylor series expansion of `e^(x·ln10)` with exponent clamping to `[-3, 3]` for numerical stability.

The difficulty mapper then translates the new ELO into concrete bot parameters using smooth linear interpolation within five brackets (Beginner through Elite). A player at 1400 ELO doesn't get a hard step-change from "Advanced settings" — they get 37.5% of the way between Advanced and Pro parameters, producing reaction times, aim variance, build speed, strafe intensity, and aggression levels that feel natural and progressive.

### AI Bot with Structured Concurrency

The bot's runtime is a layered concurrent system built on Verse's `race` and `branch` expressions:

```
bot_behavior_base (npc_behavior)
  └─ race:
       ├─ CombatLifecycle
       │    ├─ branch: AimTrackingLoop (continuous focus retry)
       │    └─ foreground: bot_combat_state_machine.RunCombatLoop()
       │         ├─ COMBAT_APPROACH    (navigate toward player)
       │         ├─ COMBAT_ENGAGE_CLOSE (perpendicular strafe + shotgun)
       │         ├─ COMBAT_ENGAGE_MID   (AR burst at range)
       │         ├─ COMBAT_DISENGAGE    (retreat vector + defensive wall)
       │         └─ COMBAT_BUILD_AGGRO  (box-up or ramp-rush sequence)
       └─ WaitForDeath (instant cleanup on elimination)
```

Five sub-modules (`bot_navigation`, `bot_focus_aim`, `bot_weapon_controller`, `bot_combat_state_machine`, `build_sequence_choreographer`) are plain classes initialized via `Init()` because `npc_behavior` cannot hold `@editable` references. All use post-38.10 movement APIs (`using { /Fortnite.com/AI/movement_types }` with bare `Running`/`Walking`).

### Object-Pooled Build Simulation

NPCs cannot access Fortnite's native build API (HC-01). All building is simulated with pre-placed props and `TeleportTo`:

- **Build Pool Manager**: 4 typed pools (wall, floor, ramp, cone) of `creative_prop` references placed in the editor and teleported to Z=-5000 staging at startup. Claims deploy props to calculated grid positions; exhaustion triggers FIFO reclaim of the oldest active prop. `ReclaimAll` yields every 4 teleports to spread frame load.
- **Build Prop Spawner**: Grid-aligned position math (`GRID_TILE_SIZE=256`) with snap functions, directional wall placement, and multi-piece layout calculators for box-ups (4 walls + floor + cone), ramp rushes (floor + ramp + wall), 90-degree retakes, and defensive covers.
- **Edit State Manager**: The "edit illusion" uses clusters of 2-3 overlapping prop variants (full wall, window edit, door edit) swapped via TeleportTo — hide one at staging, show another at position — synchronized with the build_animation_sync module's phase-precise timing.

### Build Animation Sync

Every build gesture is modeled as three phases: WINDUP (arm raises, 40%), THROW (arm swings, 30%), RECOVERY (arm returns, 30%). The prop deploys at the exact end of the THROW phase:

```
SpawnMoment = BaseDuration × (WindupPct + ThrowPct) / PlayRate
```

At PlayRate 1.5 (Pro bracket), props materialize in 0.30s. At PlayRate 0.5 (Beginner), 0.91s. The choreographer pre-calculates total sequence durations for timeouts without playing any animations.

### Canvas-Driven HUD

All UI is rendered from Verse code using the `player_ui` + `canvas` + `text_block` API — no Widget Blueprint dependency for core functionality:

- **Live Combat Stats** (top-left): DPS, accuracy, headshot% — updates every 500ms during fights
- **Status Bar** (top-right): ELO with bracket progress percentage, round number, W/L/D record
- **Coach Message** (bottom-center): Post-round feedback with auto-hide timer
- **Post-Round Scorecard**: Full-screen overlay with outcome, ELO delta, all metrics, and coach commentary

All display values are simultaneously exposed as public variables for optional UMG Widget Blueprint binding (dual-mode display).

### Predictive Coaching Intelligence

The predictive advisor analyzes the player's rolling metric history to detect:

- **Stagnation**: ELO plateau detection with oscillation analysis (distinguishes true stagnation from volatile but engaged play). Triggers volatility injection (K-factor boost) with cooldown.
- **Frustration**: Two-criteria system requiring consecutive losses AND performance degradation vs pre-streak baseline. A player who loses but maintains high DPS gets challenge encouragement; a player whose metrics are declining gets difficulty easing + break suggestion.
- **Metric Trends**: Five independent trend channels (DPS, accuracy, headshot%, reaction time, edit speed) computed by splitting history into halves and comparing averages.
- **Weakness Identification**: Compares the player's recent averages against bracket-expected baselines and returns the specific metric name where they're furthest below par.
- **Performance Anomaly**: Detects sudden single-round drops (fatigue, tilt, AFK) by comparing against rolling baseline.

The coach controller evaluates 10 trigger conditions in priority order (frustration > comeback > milestone > stagnation > fatigue > weakness > improvement > standard), delivers one message per round through multiple channels, and rotates through 3-5 template variants per category to avoid repetition.

### 4-Slot Persistent Storage

All player data persists across sessions using exactly 4 `weak_map` allocations (the engine maximum):

| Slot | Store | Data | Budget |
|------|-------|------|--------|
| 1 | `AnalyticsStore` | Lifetime averages (DPS, HS%, accuracy, reaction), session/round counts, build/edit totals, consistency score | ~80 bytes |
| 2 | `RatingStore` | ELO, peak/lowest ELO, W/L/D counts, training minutes, best win streak, version tag, last-played timestamp | ~80 bytes |
| 3 | `ProgressionStore` | Quest bitfield (32 flags), milestones, highest bracket, daily challenges, total quests completed | ~40 bytes |
| 4 | `EconomyStore` | Analytics Pass ownership, arena skins bitfield, challenge tokens, equipped skin, V-Bucks spent, purchase count | ~48 bytes |

All fields are primitives (int, float, logic) — zero strings, zero arrays. Quest states are compressed into integer bitfields using approximated bitwise operations (`BitShiftLeft`, `BitwiseAnd`, `BitwiseOr` via integer math). Schema versioning uses the Optional Fields pattern with `migration_v1_to_v2.verse` for safe evolution.

The data validator sanitizes every load: ELO clamped to [0, 5000], PeakELO ≥ CurrentELO, non-negative counts, percentage ranges [0, 100]. The persistence manager caches all 4 slots in memory at load and writes both cache and weak_map on every save, with auto-save on every round end via event bus listener.

### In-Island Economy

The shop system implements the complete In-Island Transaction pipeline:

1. **Validation**: Product existence check + durable duplicate prevention
2. **Payment**: In-Island Transaction API integration point (simulated for development)
3. **Fulfillment**: Inventory controller grants the item
4. **Persistence**: Immediate Slot 4 save
5. **Side Effects**: Auto-equip cosmetics, arena skin swap
6. **Telemetry**: Revenue tracking

Physical `button_device` props at a shop terminal trigger purchases via `InteractedWithEvent.Await()` listeners. The XP reward system distributes accolades within Epic's safe range (30K-200K per 10-minute block) with budget tracking and automatic cap enforcement.

### Event Bus Architecture

The `event_bus.verse` device is the central nervous system — 14 typed `event()` channels with the Dispatch/Listen pattern:

```
DispatchRoundStart(RoundNum)  →  RoundStartEvent.Signal()
ListenForRoundEnd()           →  RoundEndEvent.Await()
```

Every module subscribes to the events it cares about. The game manager dispatches. No module calls another module's methods directly for cross-cutting concerns. This decoupling means you can remove the entire coaching system, the shop, or the XP system without touching a single line in the game manager or analytics engine.

---

## File Manifest

```
Content/
├── event_bus.verse                    Core — 14-channel pub/sub broker
├── game_manager.verse                 Core — Master round lifecycle (5-phase state machine)
├── arena_controller.verse             Core — Bot spawn/despawn, arena reset orchestration
│
├── bot_behavior_base.verse            Module A — NPC behavior entry point (race/branch concurrency)
├── bot_combat_state_machine.verse     Module A — 5-state combat FSM
├── bot_navigation.verse               Module A — Dual-pattern NavMesh movement
├── bot_focus_aim.verse                Module A — Focus tracking with head-height targeting
├── bot_weapon_controller.verse        Module A — Shotgun/AR profiles, LCG hit simulation
├── bot_difficulty_profile.verse       Module A — ELO-driven parameter container (10 fields)
│
├── build_pool_manager.verse           Module B — Object pool with FIFO overflow reclaim
├── build_prop_spawner.verse           Module B — Grid-aligned deployment math
├── edit_state_manager.verse           Module B — Prop-variant swap illusion for edits
├── build_sequence_choreographer.verse Module B — Multi-piece sequence orchestration
├── build_animation_sync.verse         Module B — Phase-precise timing calculator
│
├── metric_definitions.verse           Module C — 25-field round_metrics + supporting structs
├── analytics_engine.verse             Module C — Real-time metric computation (6 branch listeners)
├── elo_calculator.verse               Module C — Expected probability, K-factor, Taylor Pow10
├── difficulty_mapper.verse            Module C — ELO → bot parameters (5-bracket interpolation)
├── predictive_advisor.verse           Module C — Trend analysis, frustration, stagnation
├── session_aggregator.verse           Module C — Session summary compiler + cross-session delta
│
├── data_schema_v1.verse               Module D — Persistable class definitions (4 slots)
├── data_schema_v2.verse               Module D — V2 schema with expanded fields
├── migration_v1_to_v2.verse           Module D — Safe schema migration with field derivation
├── data_validator.verse               Module D — Integrity checks, sanitization, telemetry
├── persistence_manager.verse          Module D — 4 weak_maps, cache layer, auto-save
│
├── feedback_templates.verse           Module E — 10-category rotated coaching messages
├── coach_controller.verse             Module E — Priority-based trigger evaluation (P0-P9)
├── coach_game_bridge.verse            Module E — Coach decisions → game state actions
│
├── shop_manager.verse                 Module F — Product catalog, transaction pipeline
├── inventory_controller.verse         Module F — String-based item API + bitfield ownership
├── cosmetic_applicator.verse          Module F — Arena skin swap with preview system
├── xp_reward_system.verse             Module F — Accolade-based XP with budget enforcement
│
├── hud_binding.verse                  UI — Canvas-driven live HUD + UMG binding bridge
├── scorecard_renderer.verse           UI — Post-round scorecard overlay
└── shop_ui_controller.verse           UI — Shop menu canvas + terminal listeners
```

35 files. ~8,500 lines of production Verse.

---

## Engine Constraints Respected

| ID | Constraint | How We Handle It |
|----|-----------|-----------------|
| HC-01 | NPCs cannot use native build/edit API | Prop-based illusion with TeleportTo swap |
| HC-02 | ~100 active spawned prop ceiling | Object pooling with FIFO reclaim, never SpawnProp at runtime |
| HC-03 | Dynamic props invisible to NavMesh | Traditional geometry props as NavMesh proxy layers |
| HC-04 | No HTTP/Web API calls | All data self-contained via Verse Persistence |
| HC-05 | Maximum 4 persistent weak_maps | 4-slot partitioned storage with serialization budgeting |
| HC-06 | Persistent structs immutable after deploy | Optional Fields pattern + migration functions |
| HC-07 | Island memory limits | Pooled props counted at budget time, staging at Z=-5000 |

---

## Setup

1. Create a new UEFN project from the blank island template
2. Create all 35 `.verse` files in the root `Content/` folder
3. Paste code from each file
4. `Ctrl+Shift+B` — Build Verse Code (target: zero errors)
5. Follow the UEFN Editor Checklist in the repository for device placement and wiring
6. Launch Session → verify full round lifecycle

---

## Architecture Principles

- **Zero stubs**: Every method is complete, functional, tested against the spec
- **Event-driven**: Modules communicate through the event bus, never through direct method coupling
- **Structured concurrency**: `race` for competing conditions, `branch` for parallel tasks, `loop` for reactive listeners
- **Fail gracefully**: Every persistence load is validated. Every pool claim has a FIFO fallback. Every nav call has a timeout
- **Budget everything**: XP per block, props per pool, bytes per weak_map slot, corrections per validation pass

---

## License

Proprietary. All rights reserved.

---

---

<div dir="rtl" align="right">

# ProAI Training Map — סביבת אימון תחרותית עם בינה מלאכותית לפורטנייט Creative

> סביבת אימון תחרותית אוטומטית לחלוטין, מונעת בינה מלאכותית, שנבנתה כולה ב-UEFN/Verse.
> מעל 35 קבצי Verse פרודקשן. אפס תלויות חיצוניות. ארכיטקטורה טהורה בתוך המנוע.

---

## מה זה בעצם

ProAI Training Map היא אי תרגול תחרותי עצמאי לחלוטין עבור פורטנייט Creative. השחקן מצטרף, נלחם בבוט AI שמתאים את עצמו לרמתו בזמן אמת, מקבל משוב קואצ'ינג מבוסס-מספרים לאחר כל סיבוב, וחוזר ימים אחר כך כדי למצוא את ה-ELO שלו, היסטוריית האנליטיקס שלו והקוסמטיקות שרכש — בדיוק במקום שבו השאיר אותם.

כל מערכת — החל מחישוב טור טיילור בחישוב ה-ELO ועד לדחיסת מצב הקווסטים לשדה bit יחיד — תוכננה לפעול בתוך המגבלות הקשיחות של UEFN: 4 weak_maps עקביות, כ-100 אבזרים פעילים במקביל, אפס קריאות HTTP, ואין מסדי נתונים חיצוניים.

---

## מערכות ליבה

### ELO ותאמת רמת קושי

מנוע האנליטיקס מחשב ציון ביצוע מורכב מ-DPS, אחוז פגיעות, אחוז כוון לראש, זמן תגובה ומהירות עריכה — לאחר כל סיבוב. מחשבון ה-ELO מעדכן את הדירוג של השחקן באמצעות מודל Elo מלא לסיכוי-צפוי, עם בחירת מקדם K מותאמת-דירוג (K=48 לסיבובי כיול, K=64 בזמן הזרקת תנודתיות, K=32 רגיל, K=16 לוותיקים מיוצבים). פונקציית הסיכוי `1 / (1 + 10^((BotELO - PlayerELO) / 400))` דורשת חישוב `10^x` — דבר שVerseלא מספקת — ולכן המחשבון מממש פיתוח טור טיילור ב-8 איברים של `e^(x·ln10)` עם חסימת האקספוננט ל-`[-3, 3]` לייצוב מספרי.

ממיר הקושי מתרגם את ה-ELO החדש לפרמטרים קונקרטיים של הבוט באמצעות אינטרפולציה לינארית חלקה בתוך חמישה רמות (מתחיל ועד עילית). שחקן ב-1400 ELO לא מקבל קפיצה חדה ל"הגדרות Advanced" — הוא מקבל 37.5% מהדרך בין פרמטרי Advanced ל-Pro, מה שמייצר זמני תגובה, שונות כוון, מהירות בנייה, עוצמת זזה-הצדה ורמות אגרסיביות שמרגישות טבעיות וקדמתיות.

### בוט AI עם מקביליות מובנית

סביבת ריצה של הבוט היא מערכת מקבילית מרובדת הבנויה על הביטויים `race` ו-`branch` של Verse:

```
bot_behavior_base (npc_behavior)
  └─ race:
       ├─ CombatLifecycle
       │    ├─ branch: AimTrackingLoop (ניסיון חוזר של פוקוס רציף)
       │    └─ foreground: bot_combat_state_machine.RunCombatLoop()
       │         ├─ COMBAT_APPROACH    (ניווט לעבר השחקן)
       │         ├─ COMBAT_ENGAGE_CLOSE (זזה-הצדה ניצבת + רובה ציד)
       │         ├─ COMBAT_ENGAGE_MID   (פרץ AR ממרחק)
       │         ├─ COMBAT_DISENGAGE    (נסיגה + קיר הגנתי)
       │         └─ COMBAT_BUILD_AGGRO  (כישת קופסה או רמפה התקפית)
       └─ WaitForDeath (ניקוי מיידי בסילוק)
```

חמישה תת-מודולים (`bot_navigation`, `bot_focus_aim`, `bot_weapon_controller`, `bot_combat_state_machine`, `build_sequence_choreographer`) הם מחלקות רגילות שאותחלו דרך `Init()` מכיוון ש-`npc_behavior` לא יכולה להחזיק הפניות `@editable`. כולן משתמשות בממשקי תנועה של גרסה 38.10+ (`using { /Fortnite.com/AI/movement_types }` עם `Running`/`Walking` ישיר).

### סימולציית בנייה עם מאגר אובייקטים

NPCים לא יכולים לגשת ל-API הבנייה הנייטיב של פורטנייט (HC-01). כל הבנייה מסומלצת עם אבזרים שהוצבו מראש ו-`TeleportTo`:

- **מנהל מאגר הבנייה**: 4 מאגרים מסוגים (קיר, רצפה, רמפה, חרוט) של הפניות `creative_prop` שהוצבו בעורך ועברו טלפורט ל-Z=-5000 בהפעלה. תביעות מציבות אבזרים למיקומי רשת מחושבים; ריקון המאגר מפעיל פינון FIFO של האבזר הפעיל הוותיק ביותר. `ReclaimAll` מוותר שליטה כל 4 טלפורטים כדי לפזר את עומס הפריים.
- **ממקם האבזרים**: חישוב מיקום מיושר-רשת (`GRID_TILE_SIZE=256`) עם פונקציות snap, מיקום קיר כיווני, ומחשבני פריסה מרובת-חלקים לכישות קופסה (4 קירות + רצפה + חרוט), מהלכי רמפה (רצפה + רמפה + קיר), פניות 90 מעלות ומחסות הגנתיים.
- **מנהל מצב העריכה**: "אשליית העריכה" משתמשת באשכולות של 2-3 גרסאות חופפות של אבזרים (קיר מלא, גרסת חלון, גרסת דלת) שמוחלפות דרך TeleportTo — מסתירים אחת בבימוי, מציגים אחרת במיקום — מסונכרן עם תזמון התאמה-לשלב של מודול `build_animation_sync`.

### סנכרון אנימציית בנייה

כל מחווה בנייה מדוגמנת כשלושה שלבים: WINDUP (הרמת זרוע, 40%), THROW (נפנוף זרוע, 30%), RECOVERY (החזרת זרוע, 30%). האבזר מופיע בדיוק בסיום שלב ה-THROW:

```
SpawnMoment = BaseDuration × (WindupPct + ThrowPct) / PlayRate
```

ב-PlayRate 1.5 (רמת Pro), אבזרים מופיעים תוך 0.30 שנייה. ב-PlayRate 0.5 (מתחיל), תוך 0.91 שנייה. הכוריאוגרף מחשב מראש את משכי הרצף הכוללים לתזמות ללא הרצת אנימציות.

### תצוגת HUD מבוססת Canvas

כל ממשק המשתמש מרונדר מקוד Verse באמצעות ממשק ה-`player_ui` + `canvas` + `text_block` — ללא תלות ב-Widget Blueprint לפונקציונליות ליבה:

- **נתוני לחימה חיים** (שמאל-למעלה): DPS, אחוז פגיעות, אחוז כוון לראש — מתעדכן כל 500ms במהלך קרבות
- **סרגל סטטוס** (ימין-למעלה): ELO עם אחוז התקדמות ברמה, מספר סיבוב, מאזן ניצחונות/הפסדים/תיקו
- **הודעת קואצ'** (מרכז-למטה): משוב לאחר הסיבוב עם טיימר הסתרה אוטומטית
- **כרטיס תוצאות לאחר הסיבוב**: שכבת-על מסך מלא עם תוצאה, שינוי ELO, כל המדדים ופרשנות הקואצ'

כל ערכי התצוגה נחשפים בו-זמנית כמשתנים ציבוריים לאפשרות כריכת UMG Widget Blueprint (מצב תצוגה כפול).

### אינטליגנציה קואצ'ינג חיזוית

היועץ החיזוי מנתח את היסטוריית המדדים הגוללת של השחקן כדי לזהות:

- **קיפאון**: זיהוי מדרגת ELO עם ניתוח תנודות (מבחין בין קיפאון אמיתי למשחק תנודתי אך מעורב). מפעיל הזרקת תנודתיות (דחיפת מקדם K) עם זמן קירור.
- **תסכול**: מערכת שני-קריטריונים הדורשת הפסדים רצופים AND ירידת ביצועים לעומת בסיס ה-Pre-streak. שחקן שמפסיד אך שומר על DPS גבוה מקבל עידוד לאתגר; שחקן שמדדיו יורדים מקבל הקלת קושי + הצעה להפסקה.
- **טרנדים במדדים**: חמישה ערוצי טרנד עצמאיים (DPS, אחוז פגיעות, אחוז כוון לראש, זמן תגובה, מהירות עריכה) המחושבים בפיצול ההיסטוריה לחצאים והשוואת ממוצעים.
- **זיהוי חולשה**: משווה ממוצעי 5 הסיבובים האחרונים של השחקן לבסיסי ציפייה ברמתו ומחזיר את שם המדד הספציפי בו הוא הכי מתחת לסטנדרט.
- **חריגת ביצועים**: מזהה ירידות חדות בסיבוב בודד (עייפות, tilt, AFK) בהשוואה לבסיס גוללת.

בקר הקואצ' מעריך 10 תנאי טריגר לפי סדר עדיפות (תסכול > קאמבק > אבן דרך > קיפאון > עייפות > חולשה > שיפור > סטנדרט), מעביר הודעה אחת לסיבוב דרך מספר ערוצים, ומסתובב בין 3-5 גרסאות תבנית לכל קטגוריה כדי להימנע מחזרתיות.

### אחסון עקבי ב-4 חריצים

כל נתוני השחקן נשמרים בין מפגשים באמצעות בדיוק 4 הקצאות `weak_map` (המקסימום של המנוע):

| חריץ | מאגר | נתונים | תקציב |
|------|-------|---------|--------|
| 1 | `AnalyticsStore` | ממוצעי חיים (DPS, HS%, אחוז פגיעות, תגובה), מנייני מפגש/סיבוב, סה"כ בניות/עריכות, ציון עקביות | ~80 בייט |
| 2 | `RatingStore` | ELO, ELO שיא/נמוך, ניצחונות/הפסדים/תיקו, דקות אימון, רצף ניצחונות מיטבי, תג גרסה, חותמת-זמן משחק אחרון | ~80 בייט |
| 3 | `ProgressionStore` | שדה bit של קווסטים (32 דגלים), אבני דרך, רמה גבוהה ביותר, אתגרים יומיים, סה"כ קווסטים שהושלמו | ~40 בייט |
| 4 | `EconomyStore` | בעלות Analytics Pass, שדה bit של סקינים לזירה, אסימוני אתגר, סקין מצויד, V-Bucks שהוצאו, מספר רכישות | ~48 בייט |

כל השדות הם פרימיטיביים (int, float, logic) — אפס מחרוזות, אפס מערכים. מצבי קווסט מדוחסים לשדות bit שלמים באמצעות פעולות bitwise מערוכות (`BitShiftLeft`, `BitwiseAnd`, `BitwiseOr` דרך חשבון שלמים). גרסאות הסכמה משתמשות בדפוס Optional Fields עם `migration_v1_to_v2.verse` לאבולוציה בטוחה.

מאמת הנתונים מחטא כל טעינה: ELO מוגבל ל-[0, 5000], PeakELO ≥ CurrentELO, מנייות לא-שליליות, טווחי אחוז [0, 100]. מנהל העקביות שומר מטמון של כל 4 חריצים בזיכרון בטעינה וכותב גם מטמון וגם weak_map בכל שמירה, עם שמירה-אוטומטית בכל סוף סיבוב דרך מאזין אוטובוס האירועים.

### כלכלה בתוך האי

מערכת החנות מממשת את צינור העסקאות In-Island המלא:

1. **אימות**: בדיקת קיום מוצר + מניעת כפילויות עבור פריטים עמידים
2. **תשלום**: נקודת שילוב API של עסקת In-Island (מסומלץ לפיתוח)
3. **מימוש**: בקר המלאי מעניק את הפריט
4. **עקביות**: שמירה מיידית של חריץ 4
5. **תופעות לוואי**: ציוד קוסמטיקה אוטומטי, החלפת סקין לזירה
6. **טלמטריה**: מעקב הכנסות

אבזרי `button_device` פיזיים בדוכן חנות מפעילים רכישות דרך מאזיני `InteractedWithEvent.Await()`. מערכת תגמולי XP מחלקת פרסים בטווח הבטוח של Epic (30K-200K לכל בלוק של 10 דקות) עם מעקב תקציב ואכיפת גג אוטומטית.

### ארכיטקטורת אוטובוס האירועים

התקן `event_bus.verse` הוא מערכת העצבים המרכזית — 14 ערוצי `event()` מסוגים עם דפוס Dispatch/Listen:

```
DispatchRoundStart(RoundNum)  →  RoundStartEvent.Signal()
ListenForRoundEnd()           →  RoundEndEvent.Await()
```

כל מודול נרשם לאירועים שאכפת לו מהם. מנהל המשחק שולח. אף מודול לא קורא ישירות למתודות של מודול אחר בעניינים חוצי-מודולים. ניתוק זה אומר שאפשר להסיר את כל מערכת הקואצ'ינג, החנות, או מערכת ה-XP מבלי לגעת בשורה אחת במנהל המשחק או במנוע האנליטיקס.

---

## מניפסט הקבצים

```
Content/
├── event_bus.verse                    ליבה — ברוקר pub/sub בן 14 ערוצים
├── game_manager.verse                 ליבה — מחזור חיי סיבובים ראשי (מכונת מצב 5 שלבים)
├── arena_controller.verse             ליבה — הפעלה/השבתת בוט, ניהול איפוס הזירה
│
├── bot_behavior_base.verse            מודול A — נקודת כניסה התנהגות NPC (מקביליות race/branch)
├── bot_combat_state_machine.verse     מודול A — FSM לחימה בן 5 מצבים
├── bot_navigation.verse               מודול A — תנועת NavMesh דו-דפוסית
├── bot_focus_aim.verse                מודול A — מעקב פוקוס עם כוון לגובה ראש
├── bot_weapon_controller.verse        מודול A — פרופילי רובה ציד/AR, סימולציית פגיעה LCG
├── bot_difficulty_profile.verse       מודול A — מיכל פרמטרים מונע-ELO (10 שדות)
│
├── build_pool_manager.verse           מודול B — מאגר אובייקטים עם פינון FIFO בגלישה
├── build_prop_spawner.verse           מודול B — חשבון פריסה מיושר-רשת
├── edit_state_manager.verse           מודול B — אשליית החלפת גרסת אבזר לעריכות
├── build_sequence_choreographer.verse מודול B — ניהול רצפי חלקים מרובים
├── build_animation_sync.verse         מודול B — מחשבון תזמון מדויק-לשלב
│
├── metric_definitions.verse           מודול C — round_metrics בן 25 שדות + מבנים תומכים
├── analytics_engine.verse             מודול C — חישוב מדדים בזמן אמת (6 מאזיני branch)
├── elo_calculator.verse               מודול C — סיכוי צפוי, מקדם K, Taylor Pow10
├── difficulty_mapper.verse            מודול C — ELO → פרמטרי בוט (אינטרפולציה 5 רמות)
├── predictive_advisor.verse           מודול C — ניתוח טרנדים, תסכול, קיפאון
├── session_aggregator.verse           מודול C — מהדר סיכום מפגש + דלתא בין-מפגשים
│
├── data_schema_v1.verse               מודול D — הגדרות מחלקה עקבית (4 חריצים)
├── data_schema_v2.verse               מודול D — סכמת V2 עם שדות מורחבים
├── migration_v1_to_v2.verse           מודול D — העברה בטוחה עם גזירת שדות
├── data_validator.verse               מודול D — בדיקות שלמות, חיטוי, טלמטריה
├── persistence_manager.verse          מודול D — 4 weak_maps, שכבת מטמון, שמירה-אוטומטית
│
├── feedback_templates.verse           מודול E — הודעות קואצ'ינג מסתובבות ב-10 קטגוריות
├── coach_controller.verse             מודול E — הערכת טריגרים לפי עדיפות (P0-P9)
├── coach_game_bridge.verse            מודול E — החלטות קואצ' → פעולות מצב משחק
│
├── shop_manager.verse                 מודול F — קטלוג מוצרים, צינור עסקאות
├── inventory_controller.verse         מודול F — API פריטים מבוסס-מחרוזת + בעלות bitfield
├── cosmetic_applicator.verse          מודול F — החלפת סקין לזירה עם מערכת תצוגה מקדימה
├── xp_reward_system.verse             מודול F — XP מבוסס-פרסים עם אכיפת תקציב
│
├── hud_binding.verse                  UI — HUD חי מבוסס-Canvas + גשר כריכת UMG
├── scorecard_renderer.verse           UI — שכבת-על כרטיס תוצאות לאחר סיבוב
└── shop_ui_controller.verse           UI — Canvas תפריט חנות + מאזיני דוכן
```

35 קבצים. כ-8,500 שורות Verse פרודקשן.

---

## מגבלות מנוע שנשמרו

| מזהה | מגבלה | כיצד מטפלים בה |
|------|--------|-----------------|
| HC-01 | NPCים לא יכולים להשתמש ב-API הבנייה/עריכה הנייטיב | אשליית אבזרים עם החלפה ב-TeleportTo |
| HC-02 | גג של כ-100 אבזרים שהופעלו פעילים | מאגר אובייקטים עם פינון FIFO, לעולם לא SpawnProp בזמן ריצה |
| HC-03 | אבזרים דינמיים בלתי-נראים ל-NavMesh | אבזרי גיאומטריה מסורתיים כשכבות proxy ל-NavMesh |
| HC-04 | אין קריאות HTTP/Web API | כל הנתונים עצמאיים דרך Verse Persistence |
| HC-05 | מקסימום 4 weak_maps עקביות | אחסון מחולק ל-4 חריצים עם תקצוב סריאליזציה |
| HC-06 | struct-ים עקביים בלתי-ניתנים לשינוי לאחר פריסה | דפוס Optional Fields + פונקציות העברה |
| HC-07 | מגבלות זיכרון האי | אבזרים במאגר נספרים בזמן תקצוב, בימוי ב-Z=-5000 |

---

## הגדרה

1. צור פרויקט UEFN חדש מתבנית האי הריק
2. צור את כל 35 קבצי `.verse` בתיקיית הבסיס `Content/`
3. הדבק קוד מכל קובץ
4. `Ctrl+Shift+B` — בנה קוד Verse (מטרה: אפס שגיאות)
5. עקוב אחר רשימת הבדיקה של עורך UEFN במאגר לצורך מיקום והחיווט של ההתקנים
6. הפעל מפגש → אמת מחזור חיי סיבוב מלא

---

## עקרונות ארכיטקטורה

- **אפס stubים**: כל מתודה שלמה, פונקציונלית, נבדקה מול המפרט
- **מונע-אירועים**: מודולים מתקשרים דרך אוטובוס האירועים, לעולם לא דרך קישור ישיר בין מתודות
- **מקביליות מובנית**: `race` לתנאים מתחרים, `branch` למשימות מקביליות, `loop` למאזינים תגובתיים
- **כישלון מבוקר**: כל טעינת עקביות מאומתת. לכל תביעת מאגר יש גיבוי FIFO. לכל קריאת ניווט יש timeout
- **תקציב לכל דבר**: XP לכל בלוק, אבזרים לכל מאגר, בייטים לכל חריץ weak_map, תיקונים לכל מעבר אימות

---

## רישיון

קנייני. כל הזכויות שמורות.

</div>
