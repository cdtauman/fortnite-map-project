using { /Verse.org/Random }
using { /Verse.org/Simulation }

CoachTacticContext(RangeCm : float, HeightDifference : float)<computes>:int =
    if (HeightDifference > 150.0):
        if (RangeCm > 1400.0):
            return 5
        if (RangeCm > 700.0):
            return 4
        return 3
    if (RangeCm > 1400.0):
        return 2
    if (RangeCm > 700.0):
        return 1
    return 0

CoachTacticCode(Tactic : coach_tactic)<computes>:int =
    if (Tactic = coach_tactic.HoldAngle):
        return 0
    if (Tactic = coach_tactic.CloseDistance):
        return 1
    if (Tactic = coach_tactic.ChangeAngle):
        return 2
    if (Tactic = coach_tactic.LearnedMovement):
        return 3
    if (Tactic = coach_tactic.GainHeight):
        return 4
    if (Tactic = coach_tactic.DefensiveBox):
        return 5
    return -1

CoachTacticFromCode(Code : int)<computes>:coach_tactic =
    if (Code = 1):
        return coach_tactic.CloseDistance
    if (Code = 2):
        return coach_tactic.ChangeAngle
    if (Code = 3):
        return coach_tactic.LearnedMovement
    if (Code = 4):
        return coach_tactic.GainHeight
    if (Code = 5):
        return coach_tactic.DefensiveBox
    return coach_tactic.HoldAngle

# Six visible situations and six eligible tactics. These are exchange outcomes, not skill ratings.
coach_tactic_learner := class:
    var Trials : []float = array{}
    var Values : []float = array{}
    var ActiveSlot : int = -1
    var ActiveRound : int = -1
    var BeganAt : float = -1.0
    var Inflicted : float = 0.0
    var Suffered : float = 0.0
    var WindowSeconds : float = 3.0
    var ConstructionEpisode : logic = false

    Initialize(SavedTrials : []float, SavedValues : []float):void =
        Cancel()
        set Trials = array{}
        set Values = array{}
        for (Slot := 0..35):
            var Count : float = 0.0
            var Value : float = 0.0
            var TrialSlot : int = Slot
            var ValueSlot : int = Slot
            if (Context := Floor[Slot * 1.0 / 6.0]):
                Code := Slot - Context * 6
                # Retain the previous four-tactic profile without shifting contexts into other actions.
                if (SavedTrials.Length = 24):
                    set TrialSlot = -1
                    if (Code < 4):
                        set TrialSlot = Context * 4 + Code
                if (SavedValues.Length = 24):
                    set ValueSlot = -1
                    if (Code < 4):
                        set ValueSlot = Context * 4 + Code
            if (Saved := SavedTrials[TrialSlot]):
                set Count = Clamp(Saved, 0.0, 25.0)
            if (Saved := SavedValues[ValueSlot]):
                set Value = Clamp(Saved, -1.0, 1.0)
            set Trials += array{Count}
            set Values += array{Value}

    Choose(Context : int, RangeCm : float, Style : coach_style, HumanConfidence : float, LateralConfidence : float, ?AscentReady : logic = false, ?BoxReady : logic = false, ?UnderPressure : logic = false)<transacts>:coach_tactic =
        var Best : int = 0
        var BestScore : float = -10.0
        Explore := GetRandomFloat(0.0, 1.0)
        for (Code := 0..5):
            var Eligible : logic = true
            if (Code = 1 and RangeCm < 700.0):
                set Eligible = false
            if (Code = 3 and HumanConfidence < 0.4):
                set Eligible = false
            if (Code = 4 and not AscentReady?):
                set Eligible = false
            if (Code = 5 and not BoxReady?):
                set Eligible = false
            if (Code = 4 and RangeCm > 1800.0):
                set Eligible = false
            if (Code = 5 and (not UnderPressure? or RangeCm > 1600.0)):
                set Eligible = false
            if (Eligible?, Count := Trials[Clamp(Context, 0, 5) * 6 + Code], Value := Values[Clamp(Context, 0, 5) * 6 + Code]):
                Confidence := Clamp(Count / 5.0, 0.0, 1.0)
                var Score : float = Value * Confidence + 0.15 / (Count + 1.0) + GetRandomFloat(0.0, 0.08)
                if (Style = coach_style.Pressure):
                    if (Code = 1):
                        set Score += 0.18
                    else if (Code = 4):
                        set Score += 0.08
                    else if (Code = 0):
                        set Score -= 0.1
                else if (Style = coach_style.Patient):
                    if (Code = 0):
                        set Score += 0.15
                    else if (Code = 5):
                        set Score += 0.08
                    else if (Code = 1):
                        set Score -= 0.18
                if (Code = 2 and LateralConfidence > 0.25):
                    set Score += 0.1
                if (Explore < 0.2):
                    set Score = GetRandomFloat(0.0, 1.0)
                if (Score > BestScore):
                    set BestScore = Score
                    set Best = Code
        return CoachTacticFromCode(Best)

    Begin(Context : int, Tactic : coach_tactic, At : float, RoundTicket : int):void =
        Cancel()
        Code := CoachTacticCode(Tactic)
        if (Code < 0 or Context < 0 or Context > 5):
            return
        set ActiveSlot = Context * 6 + Code
        set ActiveRound = RoundTicket
        set BeganAt = At
        if (Code = 4 or Code = 5):
            # The protected skill may take eight seconds before its first
            # follow-up exchange. Keep a bounded window for the whole action.
            set WindowSeconds = 12.0
            set ConstructionEpisode = true

    ObserveDamage(PlayerOutgoing : logic, Amount : float, At : float, RoundTicket : int):void =
        if (ActiveSlot < 0 or RoundTicket <> ActiveRound or At < BeganAt or At - BeganAt > WindowSeconds or Amount <= 0.0):
            return
        if (PlayerOutgoing?):
            set Suffered += Min(Amount, 250.0)
        else:
            set Inflicted += Min(Amount, 250.0)

    IncludeWeaponStartup(Seconds : float):void =
        if (ActiveSlot >= 0 and not ConstructionEpisode?):
            # Permit the native action's bounded startup without dropping a late exchange.
            set WindowSeconds = Max(WindowSeconds, Min(8.0, 3.0 + Max(0.0, Seconds)))

    Finish(At : float, RoundTicket : int):void =
        # A completed construction request alone is not a combat outcome.
        if (ConstructionEpisode? and Inflicted + Suffered <= 0.0):
            Cancel()
            return
        if (ActiveSlot >= 0 and ActiveRound = RoundTicket and At >= BeganAt and At - BeganAt <= WindowSeconds):
            if (At - BeganAt >= 0.3 or Inflicted + Suffered > 0.0):
                if (Context := Floor[ActiveSlot * 1.0 / 6.0]):
                    # Bounded decay makes an old preference reversible after the player changes style.
                    for (Code := 0..5, Count := Trials[Context * 6 + Code]):
                        if (set Trials[Context * 6 + Code] = Count * 0.96) {}
                if (Count := Trials[ActiveSlot], Previous := Values[ActiveSlot]):
                    NewCount := Min(25.0, Count + 1.0)
                    Reward := Clamp((Inflicted - Suffered) / Max(40.0, Inflicted + Suffered), -1.0, 1.0)
                    NewValue := Previous + (Reward - Previous) / Max(1.0, NewCount)
                    if (set Trials[ActiveSlot] = NewCount, set Values[ActiveSlot] = NewValue) {}
        Cancel()

    Cancel():void =
        set ActiveSlot = -1
        set ActiveRound = -1
        set BeganAt = -1.0
        set Inflicted = 0.0
        set Suffered = 0.0
        set WindowSeconds = 3.0
        set ConstructionEpisode = false
