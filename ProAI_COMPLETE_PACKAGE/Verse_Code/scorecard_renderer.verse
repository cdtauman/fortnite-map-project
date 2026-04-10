# ============================================================================
# FILE: scorecard_renderer.verse — Post-Round Scorecard UI via Canvas API
# LOCATION: Content/ (root)
# PHASE: 7
#
# ARCHITECTURE:
#   Renders a full-screen post-round scorecard overlay using Verse's
#   canvas + text_block API. The scorecard appears during STATE_POST_ROUND
#   and disappears when the arena resets.
#
#   LAYOUT:
#     ┌──────────────────────────────────────────────┐
#     │                                              │
#     │              ★ VICTORY ★                     │  ← Outcome (large)
#     │           1425 ELO (+18)                     │  ← ELO change
#     │                                              │
#     │   DPS: 87.3    ACC: 62%    HS: 34%           │  ← Core metrics
#     │   Reaction: 312ms    Builds: 6   Edits: 3   │  ← Secondary metrics
#     │                                              │
#     │   W: 8  L: 3  D: 1  |  Bracket: Advanced    │  ← Session summary
#     │                                              │
#     │   "Your DPS improved — keep that pressure."  │  ← Coach feedback
#     │                                              │
#     └──────────────────────────────────────────────┘
#
# WIRING (UEFN Editor):
#   EventBus     → event_bus device
#   AnalyticsRef → analytics_engine device
# ============================================================================
using { /Fortnite.com/Devices }
using { /Fortnite.com/Game }
using { /Fortnite.com/UI }
using { /Verse.org/Simulation }
using { /Verse.org/Colors }
using { /Verse.org/Colors/NamedColors }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/UI }
using { /UnrealEngine.com/Temporary/SpatialMath }

scorecard_renderer<public> := class(creative_device):

    Logger<private> : log = log{Channel := log_sc_ch}

    # ── Editable References ──────────────────────────────────────────────────
    @editable
    EventBus<public> : event_bus = event_bus{}

    @editable
    AnalyticsRef<public> : analytics_engine = analytics_engine{}

    # ── Canvas Elements ──────────────────────────────────────────────────────
    var OutcomeText<private>    : text_block = text_block{}
    var ELOChangeText<private>  : text_block = text_block{}
    var CoreMetricsText<private>: text_block = text_block{}
    var SecondaryText<private>  : text_block = text_block{}
    var SessionText<private>    : text_block = text_block{}
    var CoachText<private>      : text_block = text_block{}

    var ScorecardCanvas<private> : ?canvas = false
    var IsVisible<public>        : logic = false
    var IsCreated<private>       : logic = false

    # ── Display State (also readable by UMG widget bindings) ─────────────────
    var RoundResultText<public>     : string = ""
    var ELOChangeDisplay<public>    : string = ""
    var DPSText<public>             : string = ""
    var HeadshotText<public>        : string = ""
    var CoachFeedbackText<public>   : string = ""
    var WinLossText<public>         : string = ""

    # ── Difficulty Mapper (for bracket name) ─────────────────────────────────
    var DiffMapper<private> : difficulty_mapper = difficulty_mapper{}

    # ══════════════════════════════════════════════════════════════════════════
    # INITIALIZATION
    # ══════════════════════════════════════════════════════════════════════════
    OnBegin<override>()<suspends> : void =
        Logger.Print("SCORECARD: Renderer online.")

        # Wait for a player, then create the canvas
        branch:
            WaitAndCreateCanvas()

        # Listen for round ends to auto-render
        loop:
            EventBus.ListenForRoundEnd()
            Metrics := AnalyticsRef.CurrentMetrics
            PreviousELO := Metrics.PlayerELO
            NewELO := AnalyticsRef.GetPlayerELO()
            RenderScorecard(EventBus.LastRoundOutcome, PreviousELO, NewELO, Metrics, "")

    WaitAndCreateCanvas<private>()<suspends> : void =
        loop:
            AllPlayers := GetPlayspace().GetPlayers()
            if (Player := AllPlayers[0]):
                CreateScorecardCanvas(Player)
                break
            Sleep(0.5)

    # ══════════════════════════════════════════════════════════════════════════
    # CREATE CANVAS — Build all text blocks and position them
    # ══════════════════════════════════════════════════════════════════════════
    CreateScorecardCanvas<private>(Player : player) : void =
        if (PlayerUI := GetPlayerUI[Player]):
            set OutcomeText = text_block{
                DefaultText := StringToMessage(""),
                DefaultTextColor := NamedColors.White
            }
            set ELOChangeText = text_block{
                DefaultText := StringToMessage(""),
                DefaultTextColor := NamedColors.White
            }
            set CoreMetricsText = text_block{
                DefaultText := StringToMessage(""),
                DefaultTextColor := NamedColors.White
            }
            set SecondaryText = text_block{
                DefaultText := StringToMessage(""),
                DefaultTextColor := NamedColors.Silver
            }
            set SessionText = text_block{
                DefaultText := StringToMessage(""),
                DefaultTextColor := NamedColors.Silver
            }
            set CoachText = text_block{
                DefaultText := StringToMessage(""),
                DefaultTextColor := NamedColors.Yellow
            }

            NewCanvas := canvas:
                Slots := array:
                    canvas_slot:
                        Anchors := anchors{Minimum := vector2{X := 0.3, Y := 0.15}, Maximum := vector2{X := 0.3, Y := 0.15}}
                        Offsets := margin{Top := 0.0, Left := 0.0, Bottom := 0.0, Right := 0.0}
                        SizeToContent := true
                        Widget := OutcomeText
                    canvas_slot:
                        Anchors := anchors{Minimum := vector2{X := 0.35, Y := 0.25}, Maximum := vector2{X := 0.35, Y := 0.25}}
                        Offsets := margin{Top := 0.0, Left := 0.0, Bottom := 0.0, Right := 0.0}
                        SizeToContent := true
                        Widget := ELOChangeText
                    canvas_slot:
                        Anchors := anchors{Minimum := vector2{X := 0.2, Y := 0.40}, Maximum := vector2{X := 0.2, Y := 0.40}}
                        Offsets := margin{Top := 0.0, Left := 0.0, Bottom := 0.0, Right := 0.0}
                        SizeToContent := true
                        Widget := CoreMetricsText
                    canvas_slot:
                        Anchors := anchors{Minimum := vector2{X := 0.2, Y := 0.50}, Maximum := vector2{X := 0.2, Y := 0.50}}
                        Offsets := margin{Top := 0.0, Left := 0.0, Bottom := 0.0, Right := 0.0}
                        SizeToContent := true
                        Widget := SecondaryText
                    canvas_slot:
                        Anchors := anchors{Minimum := vector2{X := 0.2, Y := 0.60}, Maximum := vector2{X := 0.2, Y := 0.60}}
                        Offsets := margin{Top := 0.0, Left := 0.0, Bottom := 0.0, Right := 0.0}
                        SizeToContent := true
                        Widget := SessionText
                    canvas_slot:
                        Anchors := anchors{Minimum := vector2{X := 0.15, Y := 0.75}, Maximum := vector2{X := 0.15, Y := 0.75}}
                        Offsets := margin{Top := 0.0, Left := 0.0, Bottom := 0.0, Right := 0.0}
                        SizeToContent := true
                        Widget := CoachText

            set ScorecardCanvas = option{NewCanvas}
            PlayerUI.AddWidget(NewCanvas)
            set IsCreated = true

            # Start hidden
            ClearAllText()
            Logger.Print("SCORECARD: Canvas created.")

    # ══════════════════════════════════════════════════════════════════════════
    # RENDER SCORECARD — Populate all text fields with round data
    # ══════════════════════════════════════════════════════════════════════════
    RenderScorecard<public>(
        Outcome : int,
        PreviousELO : int,
        NewELO : int,
        Metrics : round_metrics,
        CoachMessage : string
    ) : void =
        set IsVisible = true

        # ── Outcome Header ───────────────────────────────────────────────────
        if (Outcome = OUTCOME_PLAYER_WIN):
            set RoundResultText = "VICTORY"
            OutcomeText.SetText(StringToMessage("VICTORY"))
        else if (Outcome = OUTCOME_BOT_WIN):
            set RoundResultText = "DEFEAT"
            OutcomeText.SetText(StringToMessage("DEFEAT"))
        else:
            set RoundResultText = "DRAW"
            OutcomeText.SetText(StringToMessage("DRAW"))

        # ── ELO Change ───────────────────────────────────────────────────────
        ELODelta := NewELO - PreviousELO
        BracketName := DiffMapper.GetBracketName(NewELO)
        if (ELODelta >= 0):
            set ELOChangeDisplay = "{NewELO} ELO (+{ELODelta}) — {BracketName}"
        else:
            set ELOChangeDisplay = "{NewELO} ELO ({ELODelta}) — {BracketName}"
        ELOChangeText.SetText(StringToMessage(ELOChangeDisplay))

        # ── Core Metrics ─────────────────────────────────────────────────────
        DPSRounded := RoundF(Metrics.DPS)
        AccRounded := RoundF(Metrics.AccuracyPct)
        HSRounded := RoundF(Metrics.HeadshotPct)
        set DPSText = "DPS: {DPSRounded}"
        set HeadshotText = "HS: {HSRounded}%"
        CoreMetricsText.SetText(StringToMessage(
            "DPS: {DPSRounded}    ACC: {AccRounded}%    HS: {HSRounded}%"
        ))

        # ── Secondary Metrics ────────────────────────────────────────────────
        ReactRounded := RoundF(Metrics.ReactionTimeMs)
        DurationRounded := RoundF(Metrics.RoundDurationSec)
        SecondaryText.SetText(StringToMessage(
            "Reaction: {ReactRounded}ms    Builds: {Metrics.BuildsPlaced}    Edits: {Metrics.EditsPerformed}    Duration: {DurationRounded}s"
        ))

        # ── Session Summary ──────────────────────────────────────────────────
        set WinLossText = "W:{EventBus.TotalPlayerWins} L:{EventBus.TotalBotWins} D:{EventBus.TotalDraws}"
        SessionText.SetText(StringToMessage(
            "W: {EventBus.TotalPlayerWins}  L: {EventBus.TotalBotWins}  D: {EventBus.TotalDraws}  |  Round {EventBus.CurrentRoundNumber}  |  {BracketName} Bracket"
        ))

        # ── Coach Feedback ───────────────────────────────────────────────────
        set CoachFeedbackText = CoachMessage
        if (CoachMessage.Length > 0):
            CoachText.SetText(StringToMessage(CoachMessage))
        else:
            CoachText.SetText(StringToMessage(""))

        Logger.Print("SCORECARD: Rendered — {RoundResultText} | {ELOChangeDisplay}")

    # ══════════════════════════════════════════════════════════════════════════
    # HIDE — Clear the scorecard between rounds
    # ══════════════════════════════════════════════════════════════════════════
    HideScorecard<public>() : void =
        set IsVisible = false
        ClearAllText()
        Logger.Print("SCORECARD: Hidden.")

    ClearAllText<private>() : void =
        EmptyMsg := StringToMessage("")
        OutcomeText.SetText(EmptyMsg)
        ELOChangeText.SetText(EmptyMsg)
        CoreMetricsText.SetText(EmptyMsg)
        SecondaryText.SetText(EmptyMsg)
        SessionText.SetText(EmptyMsg)
        CoachText.SetText(EmptyMsg)

    # ── Utility ──────────────────────────────────────────────────────────────
    RoundF<private>(Value : float) : float =
        Shifted := Value * 10.0
        Floored := Floor[Shifted] or 0
        (Floored * 1.0) / 10.0

    StringToMessage<localizes><private>(Text : string) : message =
        "{Text}"

log_sc_ch := class(log_channel):