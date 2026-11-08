using { /Fortnite.com/Characters }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/SpatialMath }

# Post-round 1V1 review (spec v1 section 6). Every statement is computed from samples of
# both duelists taken every 0.2s: health+shield, height and distance. Damage is the measured
# drop in health+shield, not the damage event (who-hit-whom is experiment N2, still pending),
# so the text says "you took" rather than "they hit you", and never claims edits or aim.

coach_duel_round_summary := struct<computes>:
    Won : logic = false
    LostHeightFirst : logic = false
    LowerShare : float = 0.0
    Dealt : float = 0.0
    Taken : float = 0.0

coach_duel_review := struct<computes>:
    English : string = ""
    Hebrew : string = ""
    # 0 = height (90s / retakes), 1 = close fights (box / edits), 2 = pressure (ramp rush)
    Drill : int = -1

coach_duel_recorder := class:
    var Players : []player = array{}
    var Times : []float = array{}
    var VitalsA : []float = array{}
    var VitalsB : []float = array{}
    var HeightA : []float = array{}
    var HeightB : []float = array{}
    var Spacing : []float = array{}
    var StartedAt : float = 0.0
    var Ticket : int = -1
    var History : [player][]coach_duel_round_summary = map{}
    var Reviews : [player]coach_duel_review = map{}

    Reset(Duelists : []player, RoundTicket : int):void =
        set Players = Duelists
        set Times = array{}
        set VitalsA = array{}
        set VitalsB = array{}
        set HeightA = array{}
        set HeightB = array{}
        set Spacing = array{}
        set StartedAt = GetSimulationElapsedTime()
        set Ticket = RoundTicket

    Sample(First : fort_character, Second : fort_character):void =
        if (Times.Length >= 1500):
            return
        A := First.GetTransform().Translation
        B := Second.GetTransform().Translation
        set Times += array{GetSimulationElapsedTime() - StartedAt}
        set VitalsA += array{First.GetHealth() + First.GetShield()}
        set VitalsB += array{Second.GetHealth() + Second.GetShield()}
        set HeightA += array{A.Z}
        set HeightB += array{B.Z}
        set Spacing += array{Distance(A, B)}

    # Runs while the round with this ticket is being fought.
    Record(Flow : coach_duel_round_flow, RoundTicket : int, Bodies : []fort_character)<suspends>:void =
        loop:
            if (Ticket <> RoundTicket or Flow.Generation <> RoundTicket or Flow.Phase <> coach_duel_phase.Fighting):
                return
            if (First := Bodies[0], Second := Bodies[1], First.IsActive[], Second.IsActive[]):
                Sample(First, Second)
            Sleep(0.2)

    Series(Index : int, Vitals : logic)<transacts>:[]float =
        if (Index = 0):
            if (Vitals?):
                return VitalsA
            return HeightA
        if (Vitals?):
            return VitalsB
        HeightB

    # Builds and stores a review for each duelist. Loser gets a final zero sample.
    Analyze(Loser : player, Scored : logic):void =
        if (Times.Length < 3):
            return
        for (Index -> Player : Players):
            Other := 1 - Index
            var Mine : []float = Series(Index, true)
            var Theirs : []float = Series(Other, true)
            var Won : logic = false
            if (Player = Loser):
                set Mine += array{0.0}
            else:
                set Theirs += array{0.0}
                if (Scored?):
                    set Won = true
            Review := Build(Player, Index, Mine, Theirs, Won)
            if (set Reviews[Player] = Review) {}

    Seconds(Value : float):string = CoachElapsedText(Value)

    Meters(Value : float)<transacts>:int =
        if (Rounded := Round[Value / 100.0]):
            return Rounded
        0

    Build(Player : player, Index : int, Mine : []float, Theirs : []float, Won : logic):coach_duel_review =
        MyHeight := Series(Index, false)
        TheirHeight := Series(1 - Index, false)
        Count := Min(Times.Length, Min(MyHeight.Length, TheirHeight.Length))
        var English : string = ""
        var Hebrew : string = ""
        var Drill : int = -1
        # 1. Biggest damage burst taken inside 1.5 seconds.
        var BestBurst : float = 0.0
        var BurstAt : int = -1
        for (Start := 0..Count - 1):
            var Sum : float = 0.0
            if (T0 := Times[Start]):
                for (Step := Start + 1..Mine.Length - 1, Before := Mine[Step - 1], After := Mine[Step]):
                    var Inside : logic = false
                    if (T := Times[Step]):
                        if (T - T0 <= 1.5):
                            set Inside = true
                    else:
                        # Final death sample has no time of its own: it belongs to the last window.
                        if (Step = Mine.Length - 1):
                            set Inside = true
                    if (Inside? and After < Before):
                        set Sum += Before - After
            if (Sum > BestBurst):
                set BestBurst = Sum
                set BurstAt = Start
        if (BestBurst >= 30.0, T := Times[BurstAt], Mz := MyHeight[BurstAt], Tz := TheirHeight[BurstAt], Gap := Spacing[BurstAt]):
            Below := Meters(Tz - Mz)
            Dist := Meters(Gap)
            Amount := CoachNumber(BestBurst)
            Lead := if (Won?) then "Closest call" else "Where you lost"
            LeadH := if (Won?) then "הרגע הכי מסוכן" else "איפה הפסדת"
            if (Below >= 2):
                set English += "{Lead}: at {Seconds(T)} you took {Amount} damage in 1.5s while {Below}m below your opponent ({Dist}m away)."
                set Hebrew += "{LeadH}: ב־{Seconds(T)} ספגת {Amount} נזק תוך 1.5 שניות כשהיית {Below} מטר מתחת ליריב (מרחק {Dist} מטר)."
                set Drill = 0
            else:
                set English += "{Lead}: at {Seconds(T)} you took {Amount} damage in 1.5s at {Dist}m range."
                set Hebrew += "{LeadH}: ב־{Seconds(T)} ספגת {Amount} נזק תוך 1.5 שניות ממרחק {Dist} מטר."
                if (Dist <= 6):
                    set Drill = 1
        # 2. Missed opportunity: opponent at 40% or less, no damage dealt for 2.5s or more.
        var OpponentStart : float = 200.0
        if (First := Theirs[0]):
            set OpponentStart = Max(1.0, First)
        var RunStart : int = -1
        var BestRun : float = 0.0
        var BestRunAt : int = -1
        for (Step := 1..Count - 1, Previous := Theirs[Step - 1], Now := Theirs[Step], T := Times[Step]):
            if (Now <= OpponentStart * 0.4 and Now >= Previous and Now > 0.0):
                if (RunStart < 0):
                    set RunStart = Step
                if (T0 := Times[RunStart], T - T0 > BestRun):
                    set BestRun = T - T0
                    set BestRunAt = RunStart
            else:
                set RunStart = -1
        if (BestRun >= 2.5, T := Times[BestRunAt], Low := Theirs[BestRunAt], Gap := Spacing[BestRunAt]):
            Left := CoachNumber(Low)
            Dist := Meters(Gap)
            Span := CoachNumber(BestRun)
            set English += "\nMissed chance: at {Seconds(T)} your opponent was down to {Left} health+shield, and for {Span}s you dealt no damage ({Dist}m away)."
            set Hebrew += "\nהזדמנות שפספסת: ב־{Seconds(T)} ליריב נשארו {Left} חיים ומגן, ובמשך {Span} שניות לא פגעת בו (מרחק {Dist} מטר)."
            if (Drill < 0):
                set Drill = 2
        # 3. Height: who lost height first, and share of time spent lower.
        var Lower : int = 0
        var Decided : logic = false
        var LostFirst : logic = false
        for (Step := 0..Count - 1, Mz := MyHeight[Step], Tz := TheirHeight[Step]):
            if (Tz - Mz > 150.0):
                set Lower += 1
            if (not Decided? and Abs(Tz - Mz) > 300.0):
                set Decided = true
                if (Tz > Mz):
                    set LostFirst = true
        LowerShare := (Lower * 1.0) / Max(1.0, Count * 1.0)
        var Dealt : float = 0.0
        var Taken : float = 0.0
        for (Step := 1..Theirs.Length - 1, Before := Theirs[Step - 1], After := Theirs[Step], After < Before):
            set Dealt += Before - After
        for (Step := 1..Mine.Length - 1, Before := Mine[Step - 1], After := Mine[Step], After < Before):
            set Taken += Before - After
        Summary := coach_duel_round_summary{Won := Won, LostHeightFirst := LostFirst, LowerShare := LowerShare, Dealt := Dealt, Taken := Taken}
        var Past : []coach_duel_round_summary = array{}
        if (Stored := History[Player]):
            set Past = Stored
        set Past += array{Summary}
        if (set History[Player] = Past) {}
        # 4. Repeated pattern across this visit's rounds.
        var LostFirstRounds : int = 0
        for (Entry : Past, Entry.LostHeightFirst?):
            set LostFirstRounds += 1
        if (Past.Length >= 3 and LostFirstRounds * 2 >= Past.Length):
            set English += "\nPattern: in {LostFirstRounds} of {Past.Length} rounds you were the first to lose height."
            set Hebrew += "\nדפוס חוזר: ב־{LostFirstRounds} מתוך {Past.Length} סיבובים איבדת גובה ראשון."
            set Drill = 0
        else if (LostFirst?):
            Share := CoachNumber(LowerShare * 100.0)
            set English += "\nHeight: your opponent took height first; you were lower {Share}% of the round."
            set Hebrew += "\nגובה: היריב השיג גובה ראשון; היית נמוך ממנו {Share}% מהסיבוב."
            if (Drill < 0):
                set Drill = 0
        # 5. Trend: damage dealt compared with this visit's earlier rounds.
        DealtNow := CoachNumber(Dealt)
        TakenNow := CoachNumber(Taken)
        set English += "\nThis round: dealt {DealtNow} / took {TakenNow}."
        set Hebrew += "\nהסיבוב הזה: הסבת {DealtNow} נזק / ספגת {TakenNow}."
        if (Past.Length >= 2):
            var Sum : float = 0.0
            for (Step := 0..Past.Length - 2, Earlier := Past[Step]):
                set Sum += Earlier.Dealt
            Average := CoachNumber(Sum / ((Past.Length - 1) * 1.0))
            set English += " Your earlier average this visit: {Average} dealt."
            set Hebrew += " הממוצע שלך בסיבובים הקודמים בביקור הזה: {Average} נזק."
        if (English = ""):
            set English = "Not enough was measured this round for a review."
            set Hebrew = "בסיבוב הזה לא נמדד מספיק בשביל ניתוח."
        coach_duel_review{English := English, Hebrew := Hebrew, Drill := Drill}

    Forget(Player : player):void =
        var KeptHistory : [player][]coach_duel_round_summary = map{}
        var KeptReviews : [player]coach_duel_review = map{}
        for (Other -> Value : History, Other <> Player):
            if (set KeptHistory[Other] = Value) {}
        for (Other -> Value : Reviews, Other <> Player):
            if (set KeptReviews[Other] = Value) {}
        set History = KeptHistory
        set Reviews = KeptReviews

CoachDuelDrillName(Drill : int, Hebrew : logic)<transacts>:string =
    if (Drill = 0):
        return CoachPick("Height: 90s and high-ground retakes", "גובה: 90 מעלות ולקיחת גובה בחזרה", Hebrew)
    if (Drill = 1):
        return CoachPick("Close fights: box edits and peeks", "קרב צמוד: עריכות והצצות מתוך קופסה", Hebrew)
    if (Drill = 2):
        return CoachPick("Pressure: ramp rush when they are low", "לחץ: ריצת רמפות כשהיריב חלש", Hebrew)
    CoachPick("Free build warm-up", "חימום בבנייה חופשית", Hebrew)
