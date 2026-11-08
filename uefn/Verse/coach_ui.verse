using { /Fortnite.com/UI }
using { /Verse.org/Colors }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /UnrealEngine.com/Temporary/UI }

CoachMessage<localizes>(Text : string):message = "{Text}"

CoachLanguage(English : string, Hebrew : string, UseHebrew : logic):message =
    if (UseHebrew?):
        return CoachMessage(Hebrew)
    return CoachMessage(English)

CoachNumber(Value : float):int =
    if (Number := Floor[Value]):
        return Number
    return 0

coach_menu_entry := struct:
    Label : message
    Action : int

coach_menu_action := class:
    Owner : coach_portal_device
    Player : player
    Action : int

    OnClick(Event : widget_message):void =
        if (Event.Player = Player):
            Owner.HandleAction(Player, Action)

coach_menu_page_action := class:
    View : coach_player_view
    Page : int

    OnClick(Event : widget_message):void =
        if (Event.Player = View.Player):
            View.ShowStoredPage(Page)

coach_player_view := class:
    Owner : coach_portal_device
    Player : player
    var Menu : ?widget = false
    var HUD : ?widget = false
    var MenuSubscriptions : []cancelable = array{}
    var HUDText : ?coach_text_label = false
    var Caption : ?widget = false
    var CaptionText : ?coach_text_label = false
    var CaptionUntil : float = 0.0
    var MenuDescription : ?coach_text_label = false
    var MomentPlot : ?widget = false
    var ReplayFrames : []coach_combat_frame = array{}
    var ReviewMomentChoices : []coach_moment = array{}
    var ReplayIndex : int = 0
    var ReplaySerial : int = 0
    var ReplayOpen : logic = false
    var ReplayPlaying : logic = false
    var ReplaySpeed : float = 1.0
    var ReplayClock : float = 0.0
    var LessonPanelVisible : logic = false
    var MenuHeading : ?message = false
    var CurrentDescription : ?message = false
    var MenuEntries : []coach_menu_entry = array{}
    var MenuIsLesson : logic = false

    CloseMenu():void =
        set ReplayOpen = false
        set LessonPanelVisible = false
        CloseMoment()
        for (Subscription : MenuSubscriptions):
            Subscription.Cancel()
        set MenuSubscriptions = array{}
        if (UI := GetPlayerUI[Player], Previous := Menu?):
            UI.RemoveWidget(Previous)
        set Menu = false
        set MenuDescription = false

    CloseMoment():void =
        if (UI := GetPlayerUI[Player], Previous := MomentPlot?):
            UI.RemoveWidget(Previous)
        set MomentPlot = false

    PlotPosition(Position : vector3)<transacts>:vector2 =
        HalfExtent := CoachArenaHalfExtent(coach_mode.Personal)
        return vector2{X := 320.0 + Clamp(Position.X, -HalfExtent, HalfExtent) / HalfExtent * 250.0, Y := 285.0 - Clamp(Position.Y, -HalfExtent, HalfExtent) / HalfExtent * 170.0}

    ShowRecordedMoment(StartedAt : float, H : logic):void =
        CloseMoment()
        if (UI := GetPlayerUI[Player], Frame := ReplayFrames[ReplayIndex]):
            Cyan := color{R := 0.1, G := 0.9, B := 0.95}
            Amber := color{R := 1.0, G := 0.6, B := 0.15}
            Chart := canvas{}
            Chart.AddWidget(canvas_slot{Offsets := margin{Right := 640.0, Bottom := 540.0}, Widget := color_block{DefaultColor := color{R := 0.01, G := 0.02, B := 0.04}, DefaultOpacity := 0.97}})
            Heading := CoachLanguage("RECORDED POSITIONS / TOP VIEW", "מיקומים שנרשמו / מבט מלמעלה", H)
            Chart.AddWidget(canvas_slot{Offsets := margin{Left := 28.0, Top := 20.0}, SizeToContent := true, Widget := (coach_text_label{DefaultText := Heading, DefaultTextColor := Cyan, DefaultTextSize := 20.0}).GetWidget()})
            Time := CoachElapsedText(Frame.FightTime)
            Chart.AddWidget(canvas_slot{Offsets := margin{Left := 28.0, Top := 56.0}, SizeToContent := true, Widget := (coach_text_label{DefaultText := CoachLanguage("Time {Time}   /   {ReplaySpeed}x", "זמן {Time}   /   {ReplaySpeed}x", H), DefaultTextColor := color{R := 1.0, G := 1.0, B := 1.0}, DefaultTextSize := 18.0}).GetWidget()})
            for (Grid := 0..4):
                Chart.AddWidget(canvas_slot{Offsets := margin{Left := 64.0 + Grid * 128.0, Top := 102.0, Right := 1.0, Bottom := 366.0}, Widget := color_block{DefaultColor := color{R := 0.12, G := 0.17, B := 0.22}}})
                Chart.AddWidget(canvas_slot{Offsets := margin{Left := 45.0, Top := 115.0 + Grid * 85.0, Right := 550.0, Bottom := 1.0}, Widget := color_block{DefaultColor := color{R := 0.12, G := 0.17, B := 0.22}}})
            for (Index := Max(0, ReplayIndex - 10)..ReplayIndex, Past := ReplayFrames[Index]):
                P := PlotPosition(Past.PlayerPosition)
                O := PlotPosition(Past.OpponentPosition)
                Chart.AddWidget(canvas_slot{Offsets := margin{Left := P.X - 2.0, Top := P.Y - 2.0, Right := 4.0, Bottom := 4.0}, Widget := color_block{DefaultColor := Cyan, DefaultOpacity := 0.3}})
                Chart.AddWidget(canvas_slot{Offsets := margin{Left := O.X - 2.0, Top := O.Y - 2.0, Right := 4.0, Bottom := 4.0}, Widget := color_block{DefaultColor := Amber, DefaultOpacity := 0.3}})
            PlayerPoint := PlotPosition(Frame.PlayerPosition)
            OpponentPoint := PlotPosition(Frame.OpponentPosition)
            Chart.AddWidget(canvas_slot{Offsets := margin{Left := PlayerPoint.X - 6.0, Top := PlayerPoint.Y - 6.0, Right := 12.0, Bottom := 12.0}, Widget := color_block{DefaultColor := Cyan}})
            Chart.AddWidget(canvas_slot{Offsets := margin{Left := OpponentPoint.X - 6.0, Top := OpponentPoint.Y - 6.0, Right := 12.0, Bottom := 12.0}, Widget := color_block{DefaultColor := Amber}})
            for (Index := 1..3):
                P := PlotPosition(Frame.PlayerPosition + Frame.PlayerView.GetLocalForward() * (Index * 90.0))
                O := PlotPosition(Frame.OpponentPosition + Frame.OpponentView.GetLocalForward() * (Index * 90.0))
                Chart.AddWidget(canvas_slot{Offsets := margin{Left := P.X - 1.5, Top := P.Y - 1.5, Right := 3.0, Bottom := 3.0}, Widget := color_block{DefaultColor := Cyan}})
                Chart.AddWidget(canvas_slot{Offsets := margin{Left := O.X - 1.5, Top := O.Y - 1.5, Right := 3.0, Bottom := 3.0}, Widget := color_block{DefaultColor := Amber}})
            PlayerHealth := CoachNumber(Frame.PlayerHealth + Frame.PlayerShield)
            OpponentHealth := CoachNumber(Frame.OpponentHealth + Frame.OpponentShield)
            PlayerZ := CoachNumber(Frame.PlayerPosition.Z / 100.0)
            OpponentZ := CoachNumber(Frame.OpponentPosition.Z / 100.0)
            Chart.AddWidget(canvas_slot{Offsets := margin{Left := 28.0, Top := 475.0}, SizeToContent := true, Widget := (coach_text_label{DefaultText := CoachLanguage("YOU  {PlayerHealth} HP+Shield / height {PlayerZ}m", "אתה  {PlayerHealth} חיים ומגן / גובה {PlayerZ}מ׳", H), DefaultTextColor := Cyan, DefaultTextSize := 16.0}).GetWidget()})
            Chart.AddWidget(canvas_slot{Offsets := margin{Left := 28.0, Top := 505.0}, SizeToContent := true, Widget := (coach_text_label{DefaultText := CoachLanguage("COACH  {OpponentHealth} HP+Shield / height {OpponentZ}m", "מאמן  {OpponentHealth} חיים ומגן / גובה {OpponentZ}מ׳", H), DefaultTextColor := Amber, DefaultTextSize := 16.0}).GetWidget()})
            Root := canvas{Slots := array{canvas_slot{Anchors := anchors{Minimum := vector2{X := 0.72, Y := 0.5}, Maximum := vector2{X := 0.72, Y := 0.5}}, Alignment := vector2{X := 0.5, Y := 0.5}, SizeToContent := true, Widget := Chart}}}
            UI.AddWidget(Root, player_ui_slot{InputMode := ui_input_mode.None, ZOrder := 45})
            set MomentPlot = option{Root}

    Dispose():void =
        CloseMenu()
        if (UI := GetPlayerUI[Player], Previous := HUD?):
            UI.RemoveWidget(Previous)
        set HUD = false
        set HUDText = false
        if (UI := GetPlayerUI[Player], Previous := Caption?):
            UI.RemoveWidget(Previous)
        set Caption = false
        set CaptionText = false

    SetCaption(Message : message):void =
        if (not Caption?):
            if (UI := GetPlayerUI[Player]):
                Text := coach_text_label{DefaultTextColor := color{R := 1.0, G := 1.0, B := 1.0}, DefaultTextSize := 18.0, DefaultJustification := text_justification.Center}
                set Text.AutoWrap = true
                set Text.WrapWidth = 600.0
                Root := canvas{Slots := array{canvas_slot{
                    Anchors := anchors{Minimum := vector2{X := 0.5, Y := 0.83}, Maximum := vector2{X := 0.5, Y := 0.83}},
                    Alignment := vector2{X := 0.5, Y := 0.5}, SizeToContent := true,
                    Widget := overlay{Slots := array{
                        overlay_slot{Widget := color_block{DefaultColor := color{R := 0.01, G := 0.02, B := 0.04}, DefaultOpacity := 0.88, DefaultDesiredSize := vector2{X := 640.0, Y := 72.0}}},
                        overlay_slot{Widget := Text.GetWidget(), Padding := margin{Left := 20.0, Right := 20.0, Top := 12.0, Bottom := 12.0}}
                    }}
                }}}
                UI.AddWidget(Root, player_ui_slot{InputMode := ui_input_mode.None, ZOrder := 10})
                set Caption = option{Root}
                set CaptionText = option{Text}
        if (Text := CaptionText?, Root := Caption?):
            Text.SetText(Message)
            Root.SetVisibility(widget_visibility.Visible)
            set CaptionUntil = GetSimulationElapsedTime() + 9.0

    UpdateDescription(Description : message):void =
        set CurrentDescription = option{Description}
        if (Text := MenuDescription?):
            Text.SetText(Description)

    ShowStoredPage(Page : int):void =
        WasReplay := ReplayOpen
        if (Heading := MenuHeading?, Description := CurrentDescription?):
            ShowMenu(Heading, Description, MenuEntries, ?LessonPanel := MenuIsLesson, ?Page := Page)
        if (WasReplay?, Training := Owner.Runtime.Players[Player], Training.Phase = coach_phase.Review):
            set ReplayOpen = true
            ShowRecordedMoment(Training.StartedAt, Training.HebrewText)
        if (MenuIsLesson?, Training := Owner.Runtime.Players[Player], Training.Phase = coach_phase.Lesson, Training.LessonDiagram?):
            ShowLessonPlan(Training.LessonIndex, Training.LessonStep, Training.HebrewText)

    # A technique diagram, separate from sampled combat positions and from native edit input.
    ShowLessonPlan(Lesson : int, Step : int, H : logic):void =
        CloseMoment()
        if (UI := GetPlayerUI[Player]):
            Cyan := color{R := 0.1, G := 0.9, B := 0.95}
            Amber := color{R := 1.0, G := 0.6, B := 0.15}
            Dim := color{R := 0.16, G := 0.23, B := 0.3}
            White := color{R := 0.85, G := 0.9, B := 0.95}
            Chart := canvas{}
            Chart.AddWidget(canvas_slot{Offsets := margin{Right := 640.0, Bottom := 520.0}, Widget := color_block{DefaultColor := color{R := 0.01, G := 0.02, B := 0.04}, DefaultOpacity := 0.97}})
            Chart.AddWidget(canvas_slot{Offsets := margin{Left := 28.0, Top := 24.0}, SizeToContent := true, Widget := (coach_text_label{DefaultText := CoachLanguage("TECHNIQUE PLAN", "תרשים הטכניקה", H), DefaultTextColor := Cyan, DefaultTextSize := 24.0}).GetWidget()})
            Count := CoachLessonSteps(Lesson)
            Chart.AddWidget(canvas_slot{Offsets := margin{Left := 28.0, Top := 65.0}, SizeToContent := true, Widget := (coach_text_label{DefaultText := CoachLanguage("STEP {Step + 1} / {Count}", "שלב {Step + 1} / {Count}", H), DefaultTextColor := White, DefaultTextSize := 18.0}).GetWidget()})
            if (Lesson = 2):
                for (Piece := 0..2):
                    Left := 48.0 + Piece * 196.0
                    var Active : logic = false
                    if (Step = Piece + 1):
                        set Active = true
                    var Tint : color = Dim
                    if (Active?):
                        set Tint = Cyan
                    else if (Step > Piece + 1):
                        set Tint = White
                    if (Piece = 0):
                        for (Row := 0..1, Column := 0..1):
                            Chart.AddWidget(canvas_slot{Offsets := margin{Left := Left + Column * 60.0, Top := 170.0 + Row * 60.0, Right := 56.0, Bottom := 56.0}, Widget := color_block{DefaultColor := Tint}})
                    else if (Piece = 1):
                        for (Row := 0..23):
                            Width := 6.0 + Row * 5.0
                            Chart.AddWidget(canvas_slot{Offsets := margin{Left := Left + 60.0 - Width * 0.5, Top := 168.0 + Row * 5.0, Right := Width, Bottom := 5.0}, Widget := color_block{DefaultColor := Tint}})
                    else:
                        for (Row := 0..2, Column := 0..2):
                            Chart.AddWidget(canvas_slot{Offsets := margin{Left := Left + Column * 40.0, Top := 170.0 + Row * 40.0, Right := 36.0, Bottom := 36.0}, Widget := color_block{DefaultColor := Tint}})
                    var Label : message = CoachLanguage("1. FLOOR", "1. רצפה", H)
                    if (Piece = 1):
                        set Label = CoachLanguage("2. CONE", "2. קונוס", H)
                    else if (Piece = 2):
                        set Label = CoachLanguage("3. WALL", "3. קיר", H)
                    Chart.AddWidget(canvas_slot{Offsets := margin{Left := Left, Top := 315.0}, SizeToContent := true, Widget := (coach_text_label{DefaultText := Label, DefaultTextColor := Tint, DefaultTextSize := 20.0}).GetWidget()})
                    if (Active?):
                        Chart.AddWidget(canvas_slot{Offsets := margin{Left := Left, Top := 350.0, Right := 120.0, Bottom := 4.0}, Widget := color_block{DefaultColor := Cyan}})
                Instruction := coach_text_label{DefaultText := CoachLanguage("Confirm each opening, then select the next piece. Try the native course to practice the complete movement.", "אשר כל פתח ובחר את החלק הבא. עבור למסלול כדי לתרגל את הרצף והתנועה בכפתורים הרגילים.", H), DefaultTextColor := White, DefaultTextSize := 20.0}
                set Instruction.AutoWrap = true
                set Instruction.WrapWidth = 560.0
                Chart.AddWidget(canvas_slot{Offsets := margin{Left := 32.0, Top := 405.0}, SizeToContent := true, Widget := Instruction.GetWidget()})
            else:
                # Top-down illustration: cyan is the trainee; amber is the opponent.
                Chart.AddWidget(canvas_slot{Offsets := margin{Left := 100.0, Top := 275.0, Right := 280.0, Bottom := 20.0}, Widget := color_block{DefaultColor := White}})
                var PlayerX : float = 220.0
                var PlayerY : float = 335.0
                if (Step = 1):
                    set PlayerX = 410.0
                    set PlayerY = 265.0
                else if (Lesson = 1 and Step >= 2):
                    set PlayerX = 70.0
                    set PlayerY = 265.0
                Chart.AddWidget(canvas_slot{Offsets := margin{Left := PlayerX, Top := PlayerY, Right := 18.0, Bottom := 18.0}, Widget := color_block{DefaultColor := Cyan}})
                Chart.AddWidget(canvas_slot{Offsets := margin{Left := 320.0, Top := 150.0, Right := 18.0, Bottom := 18.0}, Widget := color_block{DefaultColor := Amber}})
                Chart.AddWidget(canvas_slot{Offsets := margin{Left := 100.0, Top := 305.0}, SizeToContent := true, Widget := (coach_text_label{DefaultText := CoachLanguage("COVER", "מחסה", H), DefaultTextColor := White, DefaultTextSize := 18.0}).GetWidget()})
                Instruction := coach_text_label{DefaultText := CoachLanguage("Cyan: you    Amber: opponent\nChoose a protected position, open an angle, then return to safety.", "תכלת: אתה    כתום: היריב\nבחר עמדה מוגנת, פתח זווית וחזור למקום בטוח.", H), DefaultTextColor := White, DefaultTextSize := 20.0}
                set Instruction.AutoWrap = true
                set Instruction.WrapWidth = 560.0
                Chart.AddWidget(canvas_slot{Offsets := margin{Left := 32.0, Top := 405.0}, SizeToContent := true, Widget := Instruction.GetWidget()})
            Root := canvas{Slots := array{canvas_slot{Anchors := anchors{Minimum := vector2{X := 0.72, Y := 0.5}, Maximum := vector2{X := 0.72, Y := 0.5}}, Alignment := vector2{X := 0.5, Y := 0.5}, SizeToContent := true, Widget := Chart}}}
            UI.AddWidget(Root, player_ui_slot{InputMode := ui_input_mode.None, ZOrder := 45})
            set MomentPlot = option{Root}

    ShowMenu(Heading : message, Description : message, Entries : []coach_menu_entry, ?LessonPanel : logic = false, ?Page : int = 0):void =
        CloseMenu()
        set MenuHeading = option{Heading}
        set CurrentDescription = option{Description}
        set MenuEntries = Entries
        set MenuIsLesson = LessonPanel
        set LessonPanelVisible = LessonPanel
        if (UI := GetPlayerUI[Player]):
            var PageCount : int = 1
            if (Count := Ceil[Entries.Length * 1.0 / 4.0]):
                set PageCount = Max(1, Count)
            CurrentPage := Clamp(Page, 0, PageCount - 1)
            Content := stack_box{Orientation := orientation.Vertical}
            var Justification : text_justification = text_justification.Left
            var H : logic = false
            if (Training := Owner.Runtime.Players[Player], Training.HebrewText?):
                set Justification = text_justification.Right
                set H = true
            Content.AddWidget(stack_box_slot{
                Widget := (coach_text_label{DefaultText := CoachLanguage("PROCOACH / TRAINING", "האקדמיה לאימון אישי", H), DefaultTextColor := color{R := 0.13, G := 0.85, B := 0.85}, DefaultTextSize := 13.0, DefaultJustification := Justification}).GetWidget(),
                Padding := margin{Bottom := 14.0}
            })
            HeadingText := coach_text_label{DefaultText := Heading, DefaultTextColor := color{R := 1.0, G := 1.0, B := 1.0}, DefaultTextSize := 24.0, DefaultJustification := Justification}
            set HeadingText.AutoWrap = true
            set HeadingText.WrapWidth = 420.0
            Content.AddWidget(stack_box_slot{
                Widget := HeadingText.GetWidget(),
                Padding := margin{Bottom := 12.0}
            })
            DescriptionText := coach_text_label{DefaultText := Description, DefaultTextColor := color{R := 0.7, G := 0.77, B := 0.85}, DefaultTextSize := 16.0, DefaultJustification := Justification}
            set MenuDescription = option{DescriptionText}
            set DescriptionText.AutoWrap = true
            var PanelWidth : float = 560.0
            var AnchorX : float = 0.5
            var AlignX : float = 0.5
            if (LessonPanel?):
                set PanelWidth = 500.0
                set AnchorX = 0.02
                set AlignX = 0.0
            set DescriptionText.WrapWidth = PanelWidth - 72.0
            Content.AddWidget(stack_box_slot{Widget := DescriptionText.GetWidget(), Padding := margin{Bottom := 22.0}})
            var FirstButton : ?widget = false
            for (Index -> Entry : Entries, Index >= CurrentPage * 4, Index < (CurrentPage + 1) * 4):
                ButtonSkin := coach_action_button{Label := Entry.Label, Width := PanelWidth - 72.0}
                Button := ButtonSkin.GetButton()
                set MenuSubscriptions += ButtonSkin.BindFocus()
                Handler := coach_menu_action{Owner := Owner, Player := Player, Action := Entry.Action}
                set MenuSubscriptions += array{Button.OnClick().Subscribe(Handler.OnClick)}
                Content.AddWidget(stack_box_slot{Widget := Button, Padding := margin{Top := 4.0, Bottom := 4.0}})
                if (not FirstButton?):
                    set FirstButton = option{Button}
            if (PageCount > 1):
                Navigation := stack_box{Orientation := orientation.Horizontal}
                if (CurrentPage > 0):
                    PreviousSkin := coach_action_button{Label := CoachLanguage("Previous", "הקודם", H), Width := 165.0}
                    Previous := PreviousSkin.GetButton()
                    set MenuSubscriptions += PreviousSkin.BindFocus()
                    PreviousHandler := coach_menu_page_action{View := Self, Page := CurrentPage - 1}
                    set MenuSubscriptions += array{Previous.OnClick().Subscribe(PreviousHandler.OnClick)}
                    Navigation.AddWidget(stack_box_slot{Widget := Previous})
                Navigation.AddWidget(stack_box_slot{Widget := (coach_text_label{DefaultText := CoachMessage("{CurrentPage + 1} / {PageCount}"), DefaultTextColor := color{R := 0.7, G := 0.77, B := 0.85}, DefaultTextSize := 16.0}).GetWidget(), Padding := margin{Left := 16.0, Right := 16.0, Top := 12.0}})
                if (CurrentPage + 1 < PageCount):
                    NextSkin := coach_action_button{Label := CoachLanguage("More options", "אפשרויות נוספות", H), Width := 180.0}
                    Next := NextSkin.GetButton()
                    set MenuSubscriptions += NextSkin.BindFocus()
                    NextHandler := coach_menu_page_action{View := Self, Page := CurrentPage + 1}
                    set MenuSubscriptions += array{Next.OnClick().Subscribe(NextHandler.OnClick)}
                    Navigation.AddWidget(stack_box_slot{Widget := Next})
                Content.AddWidget(stack_box_slot{Widget := Navigation, Padding := margin{Top := 10.0}})
            Panel := overlay{Slots := array{
                overlay_slot{Widget := color_block{DefaultColor := color{R := 0.018, G := 0.028, B := 0.05}, DefaultOpacity := 0.96, DefaultDesiredSize := vector2{X := PanelWidth, Y := 500.0}}},
                overlay_slot{Widget := Content, Padding := margin{Left := 36.0, Right := 36.0, Top := 28.0, Bottom := 28.0}}
            }}
            Root := canvas{Slots := array{canvas_slot{
                Anchors := anchors{Minimum := vector2{X := AnchorX, Y := 0.5}, Maximum := vector2{X := AnchorX, Y := 0.5}},
                Alignment := vector2{X := AlignX, Y := 0.5}, SizeToContent := true, Widget := Panel
            }}}
            UI.AddWidget(Root, player_ui_slot{InputMode := ui_input_mode.All, ZOrder := 50})
            if (Button := FirstButton?):
                UI.SetFocus(Button)
            set Menu = option{Root}

    EnsureHUD():void =
        if (HUD?):
            return
        if (UI := GetPlayerUI[Player]):
            Text := coach_text_label{DefaultText := CoachMessage("האקדמיה לאימון אישי"), DefaultTextColor := color{R := 0.8, G := 1.0, B := 1.0}, DefaultTextSize := 16.0}
            set Text.AutoWrap = true
            set Text.WrapWidth = 354.0
            Root := canvas{Slots := array{canvas_slot{
                Anchors := anchors{Minimum := vector2{X := 0.02, Y := 0.17}, Maximum := vector2{X := 0.02, Y := 0.17}},
                SizeToContent := true,
                Widget := overlay{Slots := array{
                    overlay_slot{Widget := color_block{DefaultColor := color{R := 0.02, G := 0.03, B := 0.05}, DefaultOpacity := 0.88, DefaultDesiredSize := vector2{X := 390.0, Y := 104.0}}},
                    overlay_slot{Widget := Text.GetWidget(), Padding := margin{Left := 18.0, Right := 18.0, Top := 12.0, Bottom := 12.0}}
                }}
            }}}
            UI.AddWidget(Root, player_ui_slot{InputMode := ui_input_mode.None, ZOrder := 5})
            set HUD = option{Root}
            set HUDText = option{Text}

    UpdateHUD(Training : coach_training_session):void =
        EnsureHUD()
        if (Root := Caption?, GetSimulationElapsedTime() > CaptionUntil):
            Root.SetVisibility(widget_visibility.Collapsed)
        if (Text := HUDText?):
            if (Training.HebrewText?):
                Text.SetJustification(text_justification.Right)
            else:
                Text.SetJustification(text_justification.Left)
            Outgoing := CoachNumber(Training.OutgoingDamage)
            Incoming := CoachNumber(Training.IncomingDamage)
            if (Owner.Course.IsActiveFor(Player)?):
                Text.SetText(Owner.Course.StatusFor(Player, Training.HebrewText))
            else if (Training.Mode = coach_mode.Personal and Training.Phase = coach_phase.Preparing):
                Seconds := Owner.PersonalFlow.Countdown
                if (Seconds > 0):
                    Text.SetText(CoachLanguage("PERSONAL TRAINING\nStarts in {Seconds}", "אימון אישי\nמתחילים בעוד {Seconds}", Training.HebrewText))
                else:
                    Text.SetText(CoachLanguage("PERSONAL TRAINING\nPreparing the arena and opponent.", "אימון אישי\nמכין את הזירה והיריב.", Training.HebrewText))
            else if (Training.Phase = coach_phase.Fighting):
                if (Training.Practice.Goal > 0):
                    Text.SetText(Training.Practice.Status(Training.HebrewText))
                else if (Training.Profile.TrainingPlan.Stage = 3 and Training.PlanApplicationRevision = Training.Profile.TrainingPlan.Revision):
                    Focus := CoachPlanFocusName(Training.Profile.TrainingPlan.Lesson, Training.HebrewText)
                    Text.SetText(CoachLanguage("APPLICATION: {Focus}\nDamage dealt {Outgoing} / taken {Incoming}", "יישום: {Focus}\nנזק שהסבת {Outgoing} / שספגת {Incoming}", Training.HebrewText))
                else:
                    Text.SetText(CoachLanguage("PERSONAL TRAINING\nDamage dealt {Outgoing}  /  Taken {Incoming}", "אימון אישי\nנזק שהסבת {Outgoing}  /  שספגת {Incoming}", Training.HebrewText))
            else if (Training.Phase = coach_phase.Lesson):
                Text.SetText(CoachLanguage("FOCUSED LESSON\nWatch, practice, return to the fight", "שיעור ממוקד\nצפה, תרגל וחזור לקרב", Training.HebrewText))
            else if (Training.Mode = coach_mode.Personal and Training.Phase = coach_phase.Review):
                var ResultEnglish : string = "ROUND COMPLETE"
                var ResultHebrew : string = "הסיבוב הסתיים"
                if (Training.LastRoundInterrupted?):
                    set ResultEnglish = "ROUND INTERRUPTED"
                    set ResultHebrew = "הסיבוב נקטע, ללא תוצאה"
                else if (Training.LastRoundWon?):
                    set ResultEnglish = "ROUND WON"
                    set ResultHebrew = "ניצחת בסיבוב"
                if (Training.AwaitingNextRound?):
                    Remaining := CoachNumber(Max(0.0, Training.NextRoundAt - GetSimulationElapsedTime()) + 0.99)
                    Text.SetText(CoachLanguage("{ResultEnglish}\nDealt {Outgoing} / taken {Incoming}\nNext round in {Remaining}s. Coach menu: review or pause.", "{ResultHebrew}\nנזק שהסבת: {Outgoing} | שספגת: {Incoming}\nסיבוב נוסף בעוד {Remaining} שנ׳. תפריט המאמן: ניתוח או עצירה.", Training.HebrewText))
                else:
                    Text.SetText(CoachLanguage("{ResultEnglish}\nDealt {Outgoing} / taken {Incoming}\nOpen the coach menu to continue.", "{ResultHebrew}\nנזק שהסבת: {Outgoing} | שספגת: {Incoming}\nפתח את תפריט המאמן להמשך.", Training.HebrewText))
            else if (Training.Mode = coach_mode.FreeBuild):
                Text.SetText(CoachLanguage("FREE BUILD\nUnlimited materials. Find your rhythm.", "בנייה חופשית\nחומרים ללא הגבלה. תרגל בקצב שלך.", Training.HebrewText))
            else if (Training.Mode = coach_mode.EditTraining):
                Text.SetText(Owner.Course.StatusFor(Player, Training.HebrewText))
            else if (Training.Mode = coach_mode.Duel):
                var Count : int = 0
                for (Other -> OtherSession : Owner.Runtime.Players, OtherSession.Mode = coach_mode.Duel, not OtherSession.Closed?):
                    set Count += 1
                if (Count < 2):
                    Text.SetText(CoachLanguage("1V1\nWaiting for a second player.", "קרב אחד על אחד\nממתין לשחקן שני.", Training.HebrewText))
                else if (Owner.DuelFlow.Phase = coach_duel_phase.Countdown):
                    Seconds := Owner.DuelFlow.Countdown
                    Text.SetText(CoachLanguage("1V1\nStarts in {Seconds}", "קרב אחד על אחד\nמתחילים בעוד {Seconds}", Training.HebrewText))
                else if (Owner.DuelRestarting?):
                    Text.SetText(CoachLanguage("1V1\nPreparing the next round.", "קרב אחד על אחד\nמתכוננים לסיבוב הבא.", Training.HebrewText))
                else:
                    var Wins : int = 0
                    if (Value := Owner.DuelWins[Player]):
                        set Wins = Value
                    Text.SetText(CoachLanguage("1V1\nSession wins: {Wins}", "קרב אחד על אחד\nניצחונות במפגש: {Wins}", Training.HebrewText))
            else:
                Text.SetText(CoachLanguage("PROCOACH\nChoose a training entrance.", "האקדמיה לאימון אישי\nבחר כניסה לאימון.", Training.HebrewText))
