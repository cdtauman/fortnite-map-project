using { /Fortnite.com/Devices }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Game }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }

# Experiment N2 (temporary fixture): does DamagedEvent identify who damaged whom?
# Subscribes to every participant's character (players and AI) and prints target, amount,
# instigator, source kind and the health/shield read right after the event.
n2_damage_source_device := class(creative_device):
    @editable
    Enabled : logic = true

    var Watched : []agent = array{}

    OnBegin<override>()<suspends>:void =
        if (not Enabled?):
            return
        Print("N2 fixture started")
        loop:
            for (Agent : GetPlayspace().GetParticipants(), Character := Agent.GetFortCharacter[]):
                var Known : logic = false
                for (Seen : Watched, Seen = Agent):
                    set Known = true
                if (not Known?):
                    set Watched += array{Agent}
                    Sink := n2_damage_sink{Device := Self, Target := Agent}
                    Character.DamagedEvent().Subscribe(Sink.OnDamage)
                    Print("N2 watching {Label(Agent)}")
            Sleep(1.0)

    Label(Agent : agent)<transacts>:string =
        var Index : int = 0
        for (I -> Seen : Watched, Seen = Agent):
            set Index = I
        if (player[Agent]):
            return "P{Index}"
        "NPC{Index}"

n2_damage_sink := class:
    Device : n2_damage_source_device
    Target : agent

    OnDamage(Result : damage_result):void =
        var By : string = "none"
        if (Instigator := Result.Instigator?):
            if (Agent := Instigator.GetInstigatorAgent[]):
                set By = Device.Label(Agent)
            else:
                set By = "instigator-without-agent"
        var Source : string = "none"
        if (Causer := Result.Source?):
            if (Player := player[Causer]):
                set Source = "player"
            else if (Character := fort_character[Causer]):
                set Source = "character"
            else:
                set Source = "other"
        var After : string = "?"
        if (Character := Target.GetFortCharacter[]):
            set After = "hp={Character.GetHealth()} sh={Character.GetShield()}"
        Print("N2 dmg target={Device.Label(Target)} amount={Result.Amount} by={By} source={Source} weak={if (Result.IsWeakpointDamage?) then 1 else 0} {After}")
