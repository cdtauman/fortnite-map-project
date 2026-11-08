using { /Fortnite.com/UI }
using { /Verse.org/Assets }
using { /Verse.org/Colors }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /UnrealEngine.com/Temporary/UI }

# A small authored alphabet keeps the selected Hebrew UI independent of the client fallback font.
# Canonical content remains a localizable message. Other text uses the native text widget.
CoachEmptyText<localizes>:message = ""

coach_font_glyph := struct:
    Symbol : string
    Image : ?texture = false
    Advance : float = 0.0
    RTL : logic = false
    Latin : logic = false
    BreakLine : logic = false

var CoachFonts : weak_map(session, coach_font) = map{}

CoachFontForSession():coach_font =
    if (Existing := CoachFonts[GetSession()]):
        return Existing
    Font := coach_font{}
    if (set CoachFonts[GetSession()] = Font) {}
    return Font

coach_text_line := struct:
    Letters : []coach_font_glyph = array{}
    Width : float = 0.0

coach_text_lines := class:
    Limit : float
    Space : coach_font_glyph
    var Lines : []coach_text_line = array{}
    var Letters : []coach_font_glyph = array{}
    var Width : float = 0.0

    AddWord(Word : []coach_font_glyph):void =
        var WordWidth : float = 0.0
        for (Letter : Word):
            set WordWidth += Letter.Advance
        if (Letters.Length > 0, Width + Space.Advance + WordWidth > Limit):
            Flush()
        if (Letters.Length > 0):
            set Letters += array{Space}
            set Width += Space.Advance
        set Letters += Word
        set Width += WordWidth

    Flush():void =
        set Lines += array{coach_text_line{Letters := Letters, Width := Width}}
        set Letters = array{}
        set Width = 0.0

coach_text_run := struct:
    Letters : []coach_font_glyph
    RTL : logic

CoachReadGlyph(Font : coach_font, Text : string, Index : int)<transacts>:?coach_font_glyph =
    for (Size : array{3, 2, 1}):
        if (Key := Text.Slice[Index, Index + Size], Glyph := Font.Glyphs[Key]):
            return option{Glyph}
    return false

CoachVisualLetters(Letters : []coach_font_glyph)<transacts>:[]coach_font_glyph =
    # The authored alphabet has no combining marks. Keep complete Latin/number runs in order.
    var Runs : []coach_text_run = array{}
    var Current : []coach_font_glyph = array{}
    var Direction : logic = true
    for (Letter : Letters):
        var NextDirection : logic = Direction
        if (Letter.RTL?):
            set NextDirection = true
        else if (Letter.Latin?):
            set NextDirection = false
        if (NextDirection <> Direction, Current.Length > 0):
            set Runs += array{coach_text_run{Letters := Current, RTL := Direction}}
            set Current = array{}
        set Direction = NextDirection
        set Current += array{Letter}
    if (Current.Length > 0):
        set Runs += array{coach_text_run{Letters := Current, RTL := Direction}}
    var Visual : []coach_font_glyph = array{}
    for (Offset := 0..Runs.Length - 1, Run := Runs[Runs.Length - Offset - 1]):
        if (Run.RTL?):
            for (Index := 0..Run.Letters.Length - 1, Letter := Run.Letters[Run.Letters.Length - Index - 1]):
                set Visual += array{Letter}
        else:
            set Visual += Run.Letters
    return Visual

coach_text_label := class:
    DefaultText : message = CoachEmptyText
    DefaultTextColor : color = color{R := 1.0, G := 1.0, B := 1.0}
    DefaultTextSize : float = 18.0
    DefaultJustification : text_justification = text_justification.Left
    var AutoWrap : logic = false
    var WrapWidth : float = 0.0
    Root : overlay = overlay{}
    var Child : ?widget = false
    var Current : ?message = false
    var OverrideJustification : ?text_justification = false
    var LastText : string = ""
    var LastWidth : float = -1.0
    var LastJustification : ?text_justification = false

    GetWidget():widget =
        if (not Child?):
            SetText(DefaultText)
        return Root

    SetJustification(Value : text_justification):void =
        if (Previous := OverrideJustification?, Previous = Value):
            return
        set OverrideJustification = option{Value}
        if (Text := Current?):
            SetText(Text)

    SetText(Value : message):void =
        Text := Localize(Value)
        var Alignment : text_justification = DefaultJustification
        if (Selected := OverrideJustification?):
            set Alignment = Selected
        if (Child?, Text = LastText, WrapWidth = LastWidth, Previous := LastJustification?, Previous = Alignment):
            return
        set Current = option{Value}
        set LastText = Text
        set LastWidth = WrapWidth
        set LastJustification = option{Alignment}
        if (Previous := Child?):
            Root.RemoveWidget(Previous)
        Font := CoachFontForSession()
        var Letters : []coach_font_glyph = array{}
        var HasHebrew : logic = false
        var Index : int = 0
        loop:
            if (Index >= Text.Length):
                break
            if (Glyph := CoachReadGlyph(Font, Text, Index)?):
                set Letters += array{Glyph}
                set Index += Glyph.Symbol.Length
                if (Glyph.RTL?):
                    set HasHebrew = true
            else:
                if (Missing := Font.Glyphs["?"]):
                    set Letters += array{Missing}
                set Index += 1
        if (not HasHebrew?):
            Native := text_block{DefaultText := Value, DefaultTextColor := DefaultTextColor, DefaultTextSize := DefaultTextSize, DefaultJustification := Alignment}
            set Native.AutoWrap = AutoWrap
            set Native.WrapWidth = WrapWidth
            Root.AddWidget(overlay_slot{Widget := Native})
            set Child = option{Native}
            return
        # Slate sizes are points; the artwork reference is pixels at 96 DPI.
        Scale := DefaultTextSize / 48.0
        var Limit : float = 100000.0
        if (AutoWrap?, WrapWidth > 0.0):
            set Limit = WrapWidth / Scale
        if (Space := Font.Glyphs[" "]):
            Builder := coach_text_lines{Limit := Limit, Space := Space}
            var Word : []coach_font_glyph = array{}
            for (Letter : Letters):
                if (Letter.Symbol = " " or Letter.BreakLine?):
                    if (Word.Length > 0):
                        Builder.AddWord(Word)
                        set Word = array{}
                    if (Letter.BreakLine?):
                        Builder.Flush()
                else:
                    set Word += array{Letter}
            if (Word.Length > 0):
                Builder.AddWord(Word)
            Builder.Flush()
            var Width : float = 1.0
            for (Line : Builder.Lines):
                set Width = Max(Width, Line.Width * Scale)
            if (AutoWrap?, WrapWidth > 0.0):
                set Width = WrapWidth
            Height := Max(1, Builder.Lines.Length) * 84.0 * Scale
            Chart := canvas{}
            GlyphCanvas := canvas{}
            Chart.AddWidget(canvas_slot{Offsets := margin{Right := Width, Bottom := Height}, Widget := GlyphCanvas})
            for (Row -> Line : Builder.Lines):
                var X : float = 0.0
                if (Alignment = text_justification.Right):
                    set X = Width - Line.Width * Scale
                else if (Alignment = text_justification.Center):
                    set X = (Width - Line.Width * Scale) / 2.0
                for (Letter : CoachVisualLetters(Line.Letters)):
                    if (Image := Letter.Image?, Letter.Symbol <> " "):
                        GlyphCanvas.AddWidget(canvas_slot{Offsets := margin{Left := X - Scale, Top := Row * 84.0 * Scale, Right := 128.0 * Scale, Bottom := 128.0 * Scale}, Widget := texture_block{DefaultImage := Image, DefaultTint := DefaultTextColor, DefaultDesiredSize := vector2{X := 128.0 * Scale, Y := 128.0 * Scale}}})
                    set X += Letter.Advance * Scale
            Root.AddWidget(overlay_slot{Widget := Chart})
            set Child = option{Chart}

coach_action_button := class:
    Label : message
    Width : float = 488.0
    Background : color_block = color_block{DefaultColor := color{R := 0.045, G := 0.075, B := 0.11}, DefaultDesiredSize := vector2{X := 488.0, Y := 54.0}}
    var Native : ?button = false

    GetButton():button =
        if (Existing := Native?):
            return Existing
        Background.SetDesiredSize(vector2{X := Width, Y := 54.0})
        Text := coach_text_label{DefaultText := Label, DefaultTextSize := 18.0, DefaultJustification := text_justification.Center}
        set Text.AutoWrap = true
        set Text.WrapWidth = Width - 32.0
        Button := button{Slot := button_slot{Widget := overlay{Slots := array{
            overlay_slot{Widget := Background},
            overlay_slot{Widget := Text.GetWidget(), HorizontalAlignment := horizontal_alignment.Center, VerticalAlignment := vertical_alignment.Center, Padding := margin{Left := 16.0, Right := 16.0, Top := 10.0, Bottom := 10.0}}
        }}}}
        set Native = option{Button}
        return Button

    BindFocus():[]cancelable =
        Button := GetButton()
        return array{Button.HighlightEvent().Subscribe(Highlight), Button.UnhighlightEvent().Subscribe(Unhighlight)}

    Highlight(Event : widget_message):void =
        Background.SetColor(color{R := 0.025, G := 0.27, B := 0.3})

    Unhighlight(Event : widget_message):void =
        Background.SetColor(color{R := 0.045, G := 0.075, B := 0.11})
