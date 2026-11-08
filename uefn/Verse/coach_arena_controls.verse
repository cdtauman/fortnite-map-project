using { /Fortnite.com/Devices }
using { /Verse.org/Simulation }

# Scene resources and their cleanup belong to this device, not to menus or combat decisions.
coach_arena_controls_device := class(creative_device):
    @editable
    Configured : logic = false
    @editable
    PersonalReset01 : explosive_device = explosive_device{}
    @editable
    PersonalReset02 : explosive_device = explosive_device{}
    @editable
    PersonalReset03 : explosive_device = explosive_device{}
    @editable
    PersonalReset04 : explosive_device = explosive_device{}
    @editable
    PersonalReset05 : explosive_device = explosive_device{}
    @editable
    PersonalReset06 : explosive_device = explosive_device{}
    @editable
    PersonalReset07 : explosive_device = explosive_device{}
    @editable
    PersonalReset08 : explosive_device = explosive_device{}
    @editable
    PersonalReset09 : explosive_device = explosive_device{}
    @editable
    DuelReset01 : explosive_device = explosive_device{}
    @editable
    DuelReset02 : explosive_device = explosive_device{}
    @editable
    DuelReset03 : explosive_device = explosive_device{}
    @editable
    DuelReset04 : explosive_device = explosive_device{}
    @editable
    DuelReset05 : explosive_device = explosive_device{}
    @editable
    FreeBuildReset01 : explosive_device = explosive_device{}
    @editable
    FreeBuildReset02 : explosive_device = explosive_device{}
    @editable
    FreeBuildReset03 : explosive_device = explosive_device{}
    @editable
    PersonalReturn : button_device = button_device{}
    @editable
    DuelReturn : button_device = button_device{}
    @editable
    FreeBuildReturn : button_device = button_device{}
    @editable
    EditTrainingReturn : button_device = button_device{}

    var Portal : ?coach_portal_device = false
    var Bindings : []cancelable = array{}
    var Busy : [coach_mode]logic = map{}
    var Ending : logic = false

    Bind(Owner : coach_portal_device):void =
        if (not Configured?):
            return
        set Portal = option{Owner}
        for (Binding : Bindings):
            Binding.Cancel()
        set Bindings = array{}
        for (Control : array{PersonalReturn, DuelReturn, FreeBuildReturn, EditTrainingReturn}):
            set Bindings += array{Control.InteractedWithEvent.Subscribe(Owner.OnHub)}

    ResetsFor(Mode : coach_mode)<transacts>:[]explosive_device =
        if (Mode = coach_mode.Personal):
            return array{PersonalReset01, PersonalReset02, PersonalReset03, PersonalReset04, PersonalReset05, PersonalReset06, PersonalReset07, PersonalReset08, PersonalReset09}
        if (Mode = coach_mode.Duel):
            return array{DuelReset01, DuelReset02, DuelReset03, DuelReset04, DuelReset05}
        if (Mode = coach_mode.FreeBuild):
            return array{FreeBuildReset01, FreeBuildReset02, FreeBuildReset03}
        return array{}

    ResetOwned(Player : player, Mode : coach_mode):void =
        if (not Configured? or Ending?):
            return
        if (Owner := Portal?, Owner.ArenaAccess.Holds(Player, Mode)?):
            if (AlreadyBusy := Busy[Mode], AlreadyBusy?):
                return
            Devices := ResetsFor(Mode)
            if (Devices.Length = 0):
                return
            if (set Busy[Mode] = true):
                for (Device : Devices):
                    Device.Explode(Player)
                spawn { Rearm(Mode, Devices) }

    Rearm(Mode : coach_mode, Devices : []explosive_device)<suspends>:void =
        Sleep(1.1)
        if (not Ending?):
            for (Device : Devices):
                Device.Reset()
            if (set Busy[Mode] = false) {}

    OnEnd<override>():void =
        set Ending = true
        for (Binding : Bindings):
            Binding.Cancel()
        set Bindings = array{}
        set Portal = false
