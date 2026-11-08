using { /Verse.org/Simulation }

# Each authored training resource has explicit ownership. The lobby is shared.
# A second practice room can be added without changing combat or presentation state.
coach_arena_access := class:
    var Reservations : [coach_mode][]player = map{}

    Capacity(Mode : coach_mode)<computes>:int =
        if (Mode = coach_mode.Hub):
            return 100
        if (Mode = coach_mode.Duel):
            return 2
        return 1

    TryEnter(Player : player, Mode : coach_mode)<transacts>:logic =
        Granted := TryReserve(Player, Mode)
        if (Granted?):
            ReleaseExcept(Player, option{Mode})
            return true
        return false

    # A lesson may borrow the edit course while retaining its paused personal encounter.
    TryReserve(Player : player, Mode : coach_mode)<transacts>:logic =
        var Occupants : []player = array{}
        if (Existing := Reservations[Mode]):
            for (Other : Existing, Other <> Player, Other.IsActive[]):
                set Occupants += array{Other}
        if (Occupants.Length >= Capacity(Mode)):
            return false
        if (set Reservations[Mode] = Occupants + array{Player}):
            return true
        return false

    Holds(Player : player, Mode : coach_mode)<transacts>:logic =
        if (Occupants := Reservations[Mode]):
            for (Other : Occupants, Other = Player):
                return true
        return false

    ReleaseMode(Player : player, Mode : coach_mode)<transacts>:void =
        var Remaining : []player = array{}
        if (Existing := Reservations[Mode]):
            for (Other : Existing, Other <> Player):
                set Remaining += array{Other}
        if (set Reservations[Mode] = Remaining) {}

    Release(Player : player)<transacts>:void =
        ReleaseExcept(Player, false)

    ReleaseExcept<private>(Player : player, KeepMode : ?coach_mode)<transacts>:void =
        var Remaining : [coach_mode][]player = map{}
        for (Mode -> Occupants : Reservations):
            var Keep : []player = array{}
            for (Other : Occupants):
                if (Other <> Player):
                    set Keep += array{Other}
                else if (Retained := KeepMode?, Retained = Mode):
                    set Keep += array{Other}
            if (Keep.Length > 0, set Remaining[Mode] = Keep) {}
        set Reservations = Remaining
