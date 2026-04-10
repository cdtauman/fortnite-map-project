# ============================================================================
# FILE: hud_binding.verse — Code-Driven HUD via Verse UI API
# LOCATION: Content/ (root)
# PHASE: 7
#
# ARCHITECTURE:
#   This module creates and manages the live HUD overlay entirely from
#   Verse code using the player_ui + canvas API. No Widget Blueprint
#   required for the core stats — this is the pure-code fallback that
#   works on every UEFN version.
#
#   THREE HUD PANELS:
#     1. LIVE COMBAT STATS (top-left) — DPS, Accuracy%, Headshot%
#        Updates every 0.5s from analytics_engine.CurrentSnapshot.
#        Only visible during FIGHT state.
#
#     2. STATUS BAR (top-right) — ELO, Bracket, Round #, W/L/D
#        Updates every 0.5s from event_bus shared state.
#        Always visible.
#
#     3. COACH MESSAGE (bottom-center) — Latest coach feedback
#        Shown when SetCoachMessage() is called, auto-hides after delay.
#
#   DUAL DISPLAY MODE:
#     If the UEFN version supports UMG Widget Blueprint data binding,
#     the public Display___ variables are also kept updated so editor-
#     created widgets can bind to them. This module drives BOTH the
#     code-drawn canvas AND the UMG binding layer simultaneously.
#
# WIRING (UEFN Editor):
#   EventBus     → event_bus device
#   AnalyticsRef → analytics_engine device
# ============================================================================
using { /Fortnite.com/Devices }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Game }
using { /Fortnite.com/UI }
using { /Verse.org/Simulation }
using { /Verse.org/Colors }
using { /Verse.org/Colors/NamedColors }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/UI }
using { /UnrealEngine.com/Temporary/SpatialMath }

hud_binding<public> := class(creative_device):

    Logger<private> : log = log{Channel := log_hud_ch}

    # ── Editable References ──────────────────────────────────────────────────
    @editable
    EventBus<public> : event_bus = event_bus{}

    @editable
    AnalyticsRef<public> : analytics_engine = analytics_engine{}

    @editable
    CoachMessageDurationSec<public> : float = 5.0

    # ── UMG Binding Layer (public vars for Widget Blueprint binding) ─────────
    var DisplayELO<public>         : int = 1000
    var DisplayBracket<public>     : string = "Beginner"
    var DisplayWins<public>        : int = 0
    var DisplayLosses<public>      : int = 0
    var DisplayDraws<public>       : int = 0
    var DisplayRound<public>       : int = 0
    var DisplayDPS<public>         : float = 0.0
    var DisplayAccuracy<public>    : float = 0.0
    var DisplayHSPct<public>       : float = 0.0
    var DisplayReactionMs<public>  : float = 0.0
    var DisplayCoachMsg<public>    : string = ""
    var DisplayGameState<public>   : string = "LOBBY"

    # ── Canvas UI Elements ───────────────────────────────────────────────────
    var StatsTextBlock<private>    : text_block = text_block{}
    var StatusTextBlock<private>   : text_block = text_block{}
    var CoachTextBlock<private>    : text_block = text_block{}
    var IsCanvasCreated<private>   : logic = false
    var IsCoachMsgVisible<private> : logic = false

    # ── Difficulty Mapper (for bracket name lookup) ──────────────────────────
    var DiffMapper<private> : difficulty_mapper = difficulty_mapper{}

    # ══════════════════════════════════════════════════════════════════════════
    # INITIALIZATION
    # ══════════════════════════════════════════════════════════════════════════
    OnBegin<override>()<suspends> : void =
        Logger.Print("HUD: ── Binding Bridge Online ──")

        # Wait for a player to exist before creating UI
        branch:
            WaitForPlayerAndCreateUI()

        # Main data-refresh loop — runs for the entire session
        loop:
            RefreshAllDisplayData()
            Sleep(0.5)

    # ══════════════════════════════════════════════════════════════════════════
    # UI CREATION — Build canvas widgets for the first player
    # ══════════════════════════════════════════════════════════════════════════
    WaitForPlayerAndCreateUI<private>()<suspends> : void =
        loop:
            AllPlayers := GetPlayspace().GetPlayers()
            if (Player := AllPlayers[0]):
                CreateHUDForPlayer(Player)
                break
            Sleep(0.5)

    CreateHUDForPlayer<private>(Player : player) : void =
        if (PlayerUI := GetPlayerUI[Player]):
            # ── Live Combat Stats Text (top-left) ────────────────────────────
            set StatsTextBlock = text_block{
                DefaultText := StringToMessage("DPS: 0.0 | ACC: 0% | HS: 0%"),
                DefaultTextColor := NamedColors.White
            }

            StatsCanvas := canvas:
                Slots := array:
                    canvas_slot:
                        Anchors := anchors{Minimum := vector2{X := 0.02, Y := 0.03}, Maximum := vector2{X := 0.02, Y := 0.03}}
                        Offsets := margin{Top := 0.0, Left := 0.0, Bottom := 0.0, Right := 0.0}
                        SizeToContent := true
                        Widget := StatsTextBlock

            # ── Status Bar Text (top-right) ──────────────────────────────────
            set StatusTextBlock = text_block{
                DefaultText := StringToMessage("ELO: 1000 | Round 0 | W:0 L:0"),
                DefaultTextColor := NamedColors.White
            }

            StatusCanvas := canvas:
                Slots := array:
                    canvas_slot:
                        Anchors := anchors{Minimum := vector2{X := 0.65, Y := 0.03}, Maximum := vector2{X := 0.65, Y := 0.03}}
                        Offsets := margin{Top := 0.0, Left := 0.0, Bottom := 0.0, Right := 0.0}
                        SizeToContent := true
                        Widget := StatusTextBlock

            # ── Coach Message Text (bottom-center) ───────────────────────────
            set CoachTextBlock = text_block{
                DefaultText := StringToMessage(""),
                DefaultTextColor := NamedColors.Yellow
            }

            CoachCanvas := canvas:
                Slots := array:
                    canvas_slot:
                        Anchors := anchors{Minimum := vector2{X := 0.15, Y := 0.85}, Maximum := vector2{X := 0.15, Y := 0.85}}
                        Offsets := margin{Top := 0.0, Left := 0.0, Bottom := 0.0, Right := 0.0}
                        SizeToContent := true
                        Widget := CoachTextBlock

            # ── Add all canvases to player UI ────────────────────────────────
            PlayerUI.AddWidget(StatsCanvas)
            PlayerUI.AddWidget(StatusCanvas)
            PlayerUI.AddWidget(CoachCanvas)

            set IsCanvasCreated = true
            Logger.Print("HUD: Canvas UI created for player.")
        else:
            Logger.Print("HUD: WARNING — Could not get player_ui. Canvas not created.")

    # ══════════════════════════════════════════════════════════════════════════
    # DATA REFRESH — Reads latest data from analytics + event bus
    # Updates both the canvas text blocks AND the public binding vars.
    # ══════════════════════════════════════════════════════════════════════════
    RefreshAllDisplayData<private>() : void =
        # Read from analytics engine snapshot
        Snapshot := AnalyticsRef.CurrentSnapshot
        PlayerELO := AnalyticsRef.GetPlayerELO()

        # Update binding variables
        set DisplayELO = PlayerELO
        set DisplayBracket = DiffMapper.GetBracketName(PlayerELO)
        set DisplayWins = EventBus.TotalPlayerWins
        set DisplayLosses = EventBus.TotalBotWins
        set DisplayDraws = EventBus.TotalDraws
        set DisplayRound = EventBus.CurrentRoundNumber
        set DisplayDPS = Snapshot.LiveDPS
        set DisplayAccuracy = Snapshot.LiveAccuracy
        set DisplayHSPct = Snapshot.LiveHeadshotPct
        set DisplayGameState = GetStateName(EventBus.CurrentGameState)

        # Update canvas text blocks if created
        if (IsCanvasCreated?):
            # Live stats panel (only meaningful during fights)
            if (EventBus.CurrentGameState = STATE_FIGHT):
                # Round DPS and accuracy to 1 decimal for readability
                DPSRounded := RoundToOneDecimal(Snapshot.LiveDPS)
                AccRounded := RoundToOneDecimal(Snapshot.LiveAccuracy)
                HSRounded := RoundToOneDecimal(Snapshot.LiveHeadshotPct)
                StatsTextBlock.SetText(StringToMessage(
                    "DPS: {DPSRounded} | ACC: {AccRounded}% | HS: {HSRounded}%"
                ))
            else:
                # Show last round's final stats during non-fight phases
                StatsTextBlock.SetText(StringToMessage(
                    "DPS: {RoundToOneDecimal(EventBus.LastRoundDPS)} | HS: {RoundToOneDecimal(EventBus.LastRoundHeadshotPct)}%"
                ))

            # Status bar (always visible)
            BracketProgress := DiffMapper.GetBracketProgressPct(PlayerELO)
            ProgressPct := RoundToOneDecimal(BracketProgress * 100.0)
            StatusTextBlock.SetText(StringToMessage(
                "{DisplayBracket} {PlayerELO} ELO ({ProgressPct}%) | R{DisplayRound} | W:{DisplayWins} L:{DisplayLosses} D:{DisplayDraws}"
            ))

    # ══════════════════════════════════════════════════════════════════════════
    # COACH MESSAGE — Push/clear coach text on the HUD
    # Called by coach_controller to display post-round feedback.
    # Auto-hides after CoachMessageDurationSec via a branched timer.
    # ══════════════════════════════════════════════════════════════════════════
    SetCoachMessage<public>(Msg : string) : void =
        set DisplayCoachMsg = Msg
        set IsCoachMsgVisible = true

        if (IsCanvasCreated?):
            CoachTextBlock.SetText(StringToMessage(Msg))

        Logger.Print("HUD: Coach -> {Msg}")

        # Auto-hide via branch (non-blocking)
        spawn:
            CoachMessageAutoHide()

    CoachMessageAutoHide<private>()<suspends> : void =
        Sleep(CoachMessageDurationSec)
        ClearCoachMessage()

    ClearCoachMessage<public>() : void =
        set DisplayCoachMsg = ""
        set IsCoachMsgVisible = false
        if (IsCanvasCreated?):
            CoachTextBlock.SetText(StringToMessage(""))

    # ══════════════════════════════════════════════════════════════════════════
    # POST-ROUND SCORECARD — Full stats overlay for end-of-round display
    # Called by game_manager during POST_ROUND phase.
    # ══════════════════════════════════════════════════════════════════════════
    ShowPostRoundScorecard<public>(
        Outcome : int,
        PreviousELO : int,
        NewELO : int,
        Metrics : round_metrics,
        CoachMessage : string
    ) : void =
        # Format the outcome string
        var OutcomeStr : string = "DRAW"
        if (Outcome = OUTCOME_PLAYER_WIN):
            set OutcomeStr = "VICTORY"
        else if (Outcome = OUTCOME_BOT_WIN):
            set OutcomeStr = "DEFEAT"

        # Format ELO change with direction indicator
        ELODelta := NewELO - PreviousELO
        var ELOChangeStr : string = "{NewELO} ({ELODelta})"
        if (ELODelta > 0):
            set ELOChangeStr = "{NewELO} (+{ELODelta})"

        # Build the full scorecard text
        ScorecardText := "{OutcomeStr} | {ELOChangeStr} ELO\nDPS: {RoundToOneDecimal(Metrics.DPS)} | ACC: {RoundToOneDecimal(Metrics.AccuracyPct)}% | HS: {RoundToOneDecimal(Metrics.HeadshotPct)}%\nReaction: {RoundToOneDecimal(Metrics.ReactionTimeMs)}ms | Builds: {Metrics.BuildsPlaced} | Edits: {Metrics.EditsPerformed}\n{CoachMessage}"

        if (IsCanvasCreated?):
            StatsTextBlock.SetText(StringToMessage(ScorecardText))

        Logger.Print("HUD: Scorecard — {OutcomeStr} ELO:{ELOChangeStr}")

    # ══════════════════════════════════════════════════════════════════════════
    # UTILITY
    # ══════════════════════════════════════════════════════════════════════════
    GetStateName<private>(State : int) : string =
        if (State = STATE_LOBBY):
            return "LOBBY"
        else if (State = STATE_COUNTDOWN):
            return "COUNTDOWN"
        else if (State = STATE_FIGHT):
            return "FIGHT"
        else if (State = STATE_POST_ROUND):
            return "POST-ROUND"
        else if (State = STATE_RESETTING):
            return "RESETTING"
        "UNKNOWN"

    RoundToOneDecimal<private>(Value : float) : float =
        Shifted := Value * 10.0
        Floored := Floor[Shifted] or 0
        (Floored * 1.0) / 10.0

    StringToMessage<localizes><private>(Text : string) : message =
        "{Text}"

    # ══════════════════════════════════════════════════════════════════════════
    # PUBLIC QUERIES
    # ══════════════════════════════════════════════════════════════════════════
    IsHUDCreated<public>() : logic =
        IsCanvasCreated

    IsCoachMessageVisible<public>() : logic =
        IsCoachMsgVisible

    GetDisplayState<public>() : string =
        DisplayGameState

log_hud_ch := class(log_channel):