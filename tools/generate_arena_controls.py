"""Keep the editor's explicit arena bindings in one small runtime device."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
COUNTS={'Personal':9,'Duel':5,'FreeBuild':3}
def main():
    lines=['using { /Fortnite.com/Devices }','using { /Verse.org/Simulation }','', '# Scene resources and their cleanup belong to this device, not to menus or combat decisions.', 'coach_arena_controls_device := class(creative_device):','    @editable','    Configured : logic = false']
    for mode,count in COUNTS.items():
        for index in range(count):
            lines+=['    @editable',f'    {mode}Reset{index+1:02} : explosive_device = explosive_device{{}}']
    for mode in ['Personal','Duel','FreeBuild','EditTraining']:
        lines+=['    @editable',f'    {mode}Return : button_device = button_device{{}}']
    lines+=['','    var Portal : ?coach_portal_device = false','    var Bindings : []cancelable = array{}','    var Busy : [coach_mode]logic = map{}','    var Ending : logic = false','', '    Bind(Owner : coach_portal_device):void =','        if (not Configured?):','            return','        set Portal = option{Owner}','        for (Binding : Bindings):','            Binding.Cancel()','        set Bindings = array{}','        for (Control : array{PersonalReturn, DuelReturn, FreeBuildReturn, EditTrainingReturn}):','            set Bindings += array{Control.InteractedWithEvent.Subscribe(Owner.OnHub)}','', '    ResetsFor(Mode : coach_mode)<transacts>:[]explosive_device =']
    for mode,count in COUNTS.items():
        lines+=[f'        if (Mode = coach_mode.{mode}):','            return array{'+', '.join(f'{mode}Reset{index+1:02}' for index in range(count))+'}']
    lines+=['        return array{}','', '    ResetOwned(Player : player, Mode : coach_mode):void =','        if (not Configured? or Ending?):','            return','        if (Owner := Portal?, Owner.ArenaAccess.Holds(Player, Mode)?):','            if (AlreadyBusy := Busy[Mode], AlreadyBusy?):','                return','            Devices := ResetsFor(Mode)','            if (Devices.Length = 0):','                return','            if (set Busy[Mode] = true):','                for (Device : Devices):','                    Device.Explode(Player)','                spawn { Rearm(Mode, Devices) }','', '    Rearm(Mode : coach_mode, Devices : []explosive_device)<suspends>:void =','        Sleep(1.1)','        if (not Ending?):','            for (Device : Devices):','                Device.Reset()','            if (set Busy[Mode] = false) {}','', '    OnEnd<override>():void =','        set Ending = true','        for (Binding : Bindings):','            Binding.Cancel()','        set Bindings = array{}','        set Portal = false','']
    (ROOT/'uefn/Verse/coach_arena_controls.verse').write_text('\n'.join(lines),encoding='utf-8')
    print('Prepared arena resource controller',sum(COUNTS.values()),'reset bindings and four returns')
if __name__=='__main__':main()
