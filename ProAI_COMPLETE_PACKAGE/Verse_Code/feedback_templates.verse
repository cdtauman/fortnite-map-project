# ============================================================================
# FILE: feedback_templates.verse — Parameterized Coaching Message Library
# LOCATION: Content/ (root)
# PHASE: 6
#
# ARCHITECTURE:
#   This module is the coach's "voice" — it owns every string the coach
#   can say. The coach_controller decides WHEN to speak and WHICH category;
#   this module decides WHAT to say within that category.
#
#   DESIGN PRINCIPLES:
#     1. METRIC-SPECIFIC — Every message references at least one concrete
#        number from the player's performance. "Good job" is worthless;
#        "82 DPS with 34% headshots — solid aggression" is coaching.
#     2. ACTIONABLE — Most messages include a specific tip the player can
#        apply immediately. Not "aim better" but "pre-aim before editing."
#     3. VARIED — Multiple templates per category prevent the coach from
#        sounding like a broken record. Selection is index-based using the
#        round number modulo to rotate through options.
#     4. TONE — Direct, respectful, competitive. Like a real coach: firm
#        but supportive. Never condescending, never generic motivational.
#
#   MESSAGE CATEGORIES:
#     ROUND_WIN          — Victory feedback with metric highlights
#     ROUND_LOSS         — Defeat analysis with improvement focus
#     FRUSTRATION        — Tilt detection response with difficulty easing
#     ELO_MILESTONE      — Bracket promotion celebration
#     SESSION_LONG       — Wellness nudge for extended sessions
#     STAGNATION         — Plateau detection with volatility notice
#     WEAKNESS_SPECIFIC  — Targeted coaching for the player's worst metric
#     IMPROVEMENT        — Recognition when a metric trends upward
#     COMEBACK           — Encouragement after breaking a loss streak
#     WELCOME_BACK       — Returning player greeting with progress reminder
# ============================================================================
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }

# ── Feedback Category Constants ──────────────────────────────────────────────
FEEDBACK_ROUND_WIN<public>         : int = 0
FEEDBACK_ROUND_LOSS<public>        : int = 1
FEEDBACK_FRUSTRATION<public>       : int = 2
FEEDBACK_ELO_MILESTONE<public>     : int = 3
FEEDBACK_SESSION_LONG<public>      : int = 4
FEEDBACK_STAGNATION<public>        : int = 5
FEEDBACK_WEAKNESS<public>          : int = 6
FEEDBACK_IMPROVEMENT<public>       : int = 7
FEEDBACK_COMEBACK<public>          : int = 8
FEEDBACK_WELCOME_BACK<public>      : int = 9

# ══════════════════════════════════════════════════════════════════════════════
# FEEDBACK TEMPLATES
# ══════════════════════════════════════════════════════════════════════════════
feedback_templates<public> := class:

    Logger<private> : log = log{Channel := log_tmpl_ch}

    # ══════════════════════════════════════════════════════════════════════════
    # ROUND WIN — Victory with metric highlights
    # ══════════════════════════════════════════════════════════════════════════
    GetRoundWinMessage<public>(ELO : int, DPS : float, HeadshotPct : float, AccuracyPct : float, RoundIdx : int) : string =
        Variant := Mod[RoundIdx, 5] or 0

        if (Variant = 0):
            return "Clean round. {ELO} ELO, {DPS} DPS, {HeadshotPct}% headshots. Keep stacking wins."
        else if (Variant = 1):
            if (HeadshotPct > 40.0):
                return "Nasty. {HeadshotPct}% headshot accuracy at {ELO} ELO. Your aim is dialed in."
            return "Win secured. {AccuracyPct}% accuracy — solid shot discipline. Rating: {ELO}."
        else if (Variant = 2):
            if (DPS > 80.0):
                return "{DPS} DPS — you were relentless. {ELO} ELO. That aggression is working."
            return "Smart fight. Controlled damage at {DPS} DPS. Rating: {ELO}."
        else if (Variant = 3):
            return "Another one down. {ELO} ELO. {HeadshotPct}% HS, {AccuracyPct}% accuracy. Consistent."
        "Good round at {ELO} ELO. {DPS} DPS with {HeadshotPct}% headshots."

    # ══════════════════════════════════════════════════════════════════════════
    # ROUND LOSS — Defeat analysis with improvement focus
    # ══════════════════════════════════════════════════════════════════════════
    GetRoundLossMessage<public>(ELO : int, DPS : float, HeadshotPct : float, ReactionMs : float, RoundIdx : int) : string =
        Variant := Mod[RoundIdx, 5] or 0

        if (Variant = 0):
            if (DPS < 30.0):
                return "Rating: {ELO}. {DPS} DPS is low — you need to land more shots. Pre-aim before peeking."
            return "Close fight. {ELO} ELO. {DPS} DPS, {HeadshotPct}% HS. Try pre-aiming before opening edits."
        else if (Variant = 1):
            if (ReactionMs > 500.0):
                return "{ReactionMs}ms to first shot — too slow. Start aiming before the round starts. Rating: {ELO}."
            return "Lost at {ELO} ELO. {ReactionMs}ms reaction is decent but {DPS} DPS needs work. Hit your shots."
        else if (Variant = 2):
            return "Tough one. {HeadshotPct}% headshots at {ELO} ELO. Focus on crosshair placement at head height before engaging."
        else if (Variant = 3):
            if (HeadshotPct < 10.0):
                return "Only {HeadshotPct}% headshots. You are body-shotting. Move your crosshair up to head height. Rating: {ELO}."
            return "Loss at {ELO}. {DPS} DPS, {HeadshotPct}% HS. The bot outpaced you — try building cover earlier."
        "Rating dropped to {ELO}. {DPS} DPS this round. Reset, focus, go again."

    # ══════════════════════════════════════════════════════════════════════════
    # FRUSTRATION — Tilt detection with difficulty easing
    # ══════════════════════════════════════════════════════════════════════════
    GetFrustrationMessage<public>(ConsecutiveLosses : int, DPS : float, AccuracyPct : float, RoundIdx : int) : string =
        Variant := Mod[RoundIdx, 4] or 0

        if (Variant = 0):
            return "{ConsecutiveLosses} losses. Your accuracy dropped to {AccuracyPct}% — that is tilt showing. Dialing the bot back. Take a breath."
        else if (Variant = 1):
            return "Rough streak. {ConsecutiveLosses} in a row, {DPS} DPS. I am easing the difficulty. Focus on one thing: crosshair placement."
        else if (Variant = 2):
            return "{ConsecutiveLosses} straight losses. Your DPS fell to {DPS}. Bot difficulty reduced. Slow down, hit your first shot clean."
        "Tough stretch — {ConsecutiveLosses} losses. {AccuracyPct}% accuracy is below your baseline. Bot eased back. Reset and rebuild rhythm."

    # Legacy overload for backward compatibility
    GetFrustrationMessage<public>(ConsecutiveLosses : int) : string =
        "{ConsecutiveLosses} losses in a row. Adjusting difficulty down. Focus on one mechanic at a time."

    # ══════════════════════════════════════════════════════════════════════════
    # ELO MILESTONE — Bracket promotion
    # ══════════════════════════════════════════════════════════════════════════
    GetMilestoneMessage<public>(NewELO : int, BracketName : string) : string =
        if (NewELO >= 2000):
            return "Elite bracket. {NewELO} ELO. Sub-100ms reactions, zero aim variance. Welcome to the top."
        else if (NewELO >= 1600):
            return "Pro bracket unlocked. {NewELO} ELO. Bot reaction time under 200ms. You earned this, {BracketName}."
        else if (NewELO >= 1200):
            return "{BracketName} bracket — {NewELO} ELO. Builds are real-speed now. Let us see what you can do."
        "{BracketName} bracket reached. {NewELO} ELO. Bot difficulty increased. Show me you belong here."

    # Legacy overload
    GetMilestoneMessage<public>(NewELO : int) : string =
        "Milestone: {NewELO} ELO. Bot difficulty increased. Show me you belong here."

    # ══════════════════════════════════════════════════════════════════════════
    # SESSION LONG — Wellness nudge
    # ══════════════════════════════════════════════════════════════════════════
    GetSessionLongMessage<public>(Minutes : float, RoundIdx : int) : string =
        Variant := Mod[RoundIdx, 3] or 0

        if (Variant = 0):
            return "{Minutes} minutes training. Your reaction time degrades after 30. Short break, then come back sharper."
        else if (Variant = 1):
            return "Been grinding {Minutes} minutes. Diminishing returns start around 30. A 5-minute break actually improves performance."
        "Session at {Minutes} minutes. Take a breather — I will be here when you get back."

    # Legacy overload
    GetSessionLongMessage<public>(Minutes : float) : string =
        "Training for {Minutes} minutes. Short breaks improve reaction time. I will be here."

    # ══════════════════════════════════════════════════════════════════════════
    # STAGNATION — Plateau detection
    # ══════════════════════════════════════════════════════════════════════════
    GetStagnationMessage<public>(CurrentELO : int, RoundsStagnant : int, RoundIdx : int) : string =
        Variant := Mod[RoundIdx, 3] or 0

        if (Variant = 0):
            return "ELO stuck at {CurrentELO} for {RoundsStagnant} rounds. Injecting volatility — wins and losses count more now. Push through."
        else if (Variant = 1):
            return "Plateau detected at {CurrentELO}. Next few rounds weight heavier. Try changing your approach — if you are boxing, try ramp rushing."
        "Rating flatlined at {CurrentELO}. Switching up the bot's style to break the pattern. Adapt and overcome."

    # Legacy overload
    GetStagnationMessage<public>() : string =
        "Rating plateaued. Injecting volatility — next rounds weight more heavily. Push through."

    # ══════════════════════════════════════════════════════════════════════════
    # WEAKNESS-SPECIFIC — Targeted coaching for worst metric
    # ══════════════════════════════════════════════════════════════════════════
    GetWeaknessMessage<public>(WeakMetric : string, MetricValue : float, BracketName : string) : string =
        if (WeakMetric = "DPS"):
            return "Your DPS ({MetricValue}) is below {BracketName} average. You need to deal damage faster — shoot first, build second."
        else if (WeakMetric = "Accuracy"):
            return "Accuracy at {MetricValue}% — below {BracketName} standard. Slow down your shots. One clean hit beats three misses."
        else if (WeakMetric = "Headshot%"):
            return "{MetricValue}% headshots — below {BracketName} average. Move your default crosshair position up. Head level, always."
        else if (WeakMetric = "ReactionTime"):
            return "{MetricValue}ms first-shot reaction — slow for {BracketName}. Pre-aim where the bot will be, not where it is."
        "Your {WeakMetric} needs work for {BracketName} bracket. Focus on improving that specific mechanic."

    # ══════════════════════════════════════════════════════════════════════════
    # IMPROVEMENT — Recognizing positive trends
    # ══════════════════════════════════════════════════════════════════════════
    GetImprovementMessage<public>(ImprovedMetric : string, OldValue : float, NewValue : float) : string =
        if (ImprovedMetric = "DPS"):
            return "DPS trending up — {OldValue} to {NewValue}. Your aggression is paying off."
        else if (ImprovedMetric = "Headshot%"):
            return "Headshot rate climbing — {OldValue}% to {NewValue}%. That crosshair discipline is showing."
        else if (ImprovedMetric = "ReactionTime"):
            return "First-shot reaction improved — {OldValue}ms down to {NewValue}ms. You are reading the fight faster."
        "Your {ImprovedMetric} is trending up. Keep doing what you are doing."

    # ══════════════════════════════════════════════════════════════════════════
    # COMEBACK — Breaking a loss streak
    # ══════════════════════════════════════════════════════════════════════════
    GetComebackMessage<public>(PreviousLosses : int, ELO : int) : string =
        if (PreviousLosses >= 5):
            return "There it is. {PreviousLosses}-loss streak broken. {ELO} ELO. That is mental resilience right there."
        "Back in the win column after {PreviousLosses} losses. {ELO} ELO. Momentum is yours."

    # ══════════════════════════════════════════════════════════════════════════
    # WELCOME BACK — Returning player greeting
    # ══════════════════════════════════════════════════════════════════════════
    GetWelcomeBackMessage<public>(ELO : int, PeakELO : int, TotalRounds : int) : string =
        if (TotalRounds > 100):
            return "Welcome back. {ELO} ELO, {TotalRounds} lifetime rounds. Peak was {PeakELO}. Let us push past that."
        else if (TotalRounds > 20):
            return "Back for more. {ELO} ELO, peak {PeakELO}. You know the drill — warm up, then grind."
        "Welcome back. Your rating: {ELO}. Let us pick up where you left off."

    # ══════════════════════════════════════════════════════════════════════════
    # DRAW / TIMEOUT — Round ended by timer
    # ══════════════════════════════════════════════════════════════════════════
    GetDrawMessage<public>(ELO : int, DPS : float) : string =
        if (DPS < 20.0):
            return "Draw — timer ran out. Only {DPS} DPS. You need to push more aggressively. Rating: {ELO}."
        "Time ran out. {DPS} DPS — you were fighting but not finishing. Close the distance and commit to your shots. {ELO} ELO."

    # ══════════════════════════════════════════════════════════════════════════
    # FIRST ROUND — Session opener
    # ══════════════════════════════════════════════════════════════════════════
    GetFirstRoundMessage<public>(ELO : int, BracketName : string) : string =
        "First round. {BracketName} bracket, {ELO} ELO. Warm up, find your rhythm. I will have feedback after this one."

log_tmpl_ch := class(log_channel):