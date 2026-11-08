using { /Fortnite.com/AI }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Devices }
using { /Fortnite.com/Game }
using { /Fortnite.com/Playspaces }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }

# First integration slice: a real opponent, cancellable action probes and measured combat events.
coach_lab_device := class(creative_device):

    @editable
    Enabled : logic = true

    @editable
    OpponentSpawner : guard_spawner_device = guard_spawner_device{}

    @editable
    ResetControl : button_device = button_device{}

    @editable
    ActionControl : button_device = button_device{}

    @editable
    LoadoutGranter : item_granter_device = item_granter_device{}

    @editable
    SpawnPadOne : player_spawner_device = player_spawner_device{}

    @editable
    SpawnPadTwo : player_spawner_device = player_spawner_device{}

    var Generation : int = 0
    var RunningActionProbe : logic = false
    var Ending : logic = false
    var Opponent : ?fort_character = false
    var Subscriptions : []cancelable = array{}
    var CharacterBindings : [fort_character][]cancelable = map{}
    var SpawnObserved : [player]logic = map{}
    var VisibleTarget : ?npc_target_info = false
    var LastVisibility : logic = false

    OnBegin<override>()<suspends>:void =
        if (not Enabled?):
            return
        set Ending = false
        set Subscriptions += array{
            OpponentSpawner.SpawnedEvent.Subscribe(OnOpponentSpawned),
            OpponentSpawner.AlertedEvent.Subscribe(OnAlerted),
            OpponentSpawner.TargetLostEvent.Subscribe(OnTargetLost),
            ResetControl.InteractedWithEvent.Subscribe(OnReset),
            ActionControl.InteractedWithEvent.Subscribe(OnToggleActions),
            SpawnPadOne.SpawnedEvent.Subscribe(OnPlayerSpawned),
            SpawnPadTwo.SpawnedEvent.Subscribe(OnPlayerSpawned),
            LoadoutGranter.ItemGrantedEvent.Subscribe(OnItemGranted)
        }
        spawn { WatchPlayers() }
        spawn { GrantExistingPlayers() }
        Print("PCL|boot|probe=P01|version=4|mode=observe", ?Duration := 0.0)
        Sleep(1.0)
        RestartOpponent()

    OnEnd<override>():void =
        set Ending = true
        set Generation += 1
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        for (Character -> Bindings : CharacterBindings):
            for (Subscription : Bindings):
                Subscription.Cancel()

    # The lab has two players at most. This also catches replacement characters after respawn.
    WatchPlayers()<suspends>:void =
        loop:
            if (Ending?):
                return
            for (Player : GetPlayspace().GetPlayers()):
                if (Character := Player.GetFortCharacter[], Character.IsActive[]):
                    BindCharacter(Character)
            Sleep(0.2)

    OnPlayerSpawned(Agent : agent):void =
        if (Player := player[Agent], Character := Player.GetFortCharacter[]):
            if (set SpawnObserved[Player] = true) {}
            BindCharacter(Character)
            Print("PCL|player_spawn|loadout_request", ?Duration := 0.0)
            LoadoutGranter.GrantItem(Player)

    # Bootstrap players already present when the device begins; normal lives use SpawnedEvent.
    GrantExistingPlayers()<suspends>:void =
        Sleep(0.5)
        for (Player : GetPlayspace().GetPlayers()):
            if (Ending?):
                return
            if (not SpawnObserved[Player]?):
                OnPlayerSpawned(Player)

    OnItemGranted(Agent : agent):void =
        Print("PCL|loadout|item_granted", ?Duration := 0.0)

    BindCharacter(Character : fort_character):void =
        PruneCharacterBindings()
        if (CharacterBindings[Character]):
            return
        Bindings := array{
            Character.DamagedEvent().Subscribe(OnActualDamage),
            Character.DamagedShieldEvent().Subscribe(OnActualDamage),
            Character.EliminatedEvent().Subscribe(OnActualElimination)
        }
        if (set CharacterBindings[Character] = Bindings):
            Print("PCL|character_bind", ?Duration := 0.0)
        else:
            for (Subscription : Bindings):
                Subscription.Cancel()

    PruneCharacterBindings():void =
        var ActiveBindings : [fort_character][]cancelable = map{}
        for (Character -> Bindings : CharacterBindings):
            if (Character.IsActive[]):
                if (set ActiveBindings[Character] = Bindings) {}
            else:
                for (Subscription : Bindings):
                    Subscription.Cancel()
        set CharacterBindings = ActiveBindings

    RestartOpponent():void =
        set Generation += 1
        set VisibleTarget = false
        set LastVisibility = false
        set Opponent = false
        OpponentSpawner.Despawn()
        OpponentSpawner.Reset()
        OpponentSpawner.Spawn()
        Print("PCL|reset|generation={Generation}", ?Duration := 0.0)

    OnReset(Instigator : agent):void =
        RestartOpponent()

    OnToggleActions(Instigator : agent):void =
        if (RunningActionProbe?):
            set RunningActionProbe = false
            Print("PCL|mode|observe", ?Duration := 0.0)
        else:
            set RunningActionProbe = true
            Print("PCL|mode|bounded_attack_probe", ?Duration := 0.0)

    OnOpponentSpawned(Agent : agent):void =
        if (Character := Agent.GetFortCharacter[]):
            set Opponent = option{Character}
            BindCharacter(Character)
            Print("PCL|spawn|generation={Generation}|native_guard=true", ?Duration := 0.0)
            spawn { RunOpponentProbe(Character, Generation) }

    RunOpponentProbe(Character : fort_character, Ticket : int)<suspends>:void =
        Sleep(0.1)
        if (Ending? or Ticket <> Generation):
            return
        if (not Character.IsActive[]):
            return
        if:
            Body := Character.GetEntity[]
            Actions := Body.GetComponent[guard_actions_component]
            Awareness := Body.GetComponent[npc_awareness_component]
        then:
            Sink := coach_awareness_sink{Owner := Self, Character := Character, Ticket := Ticket}
            SeenSubscription := Awareness.SeeTargetEvent.Subscribe(Sink.OnSeen)
            LostSubscription := Awareness.ForgetTargetEvent.Subscribe(Sink.OnForgotten)
            defer:
                SeenSubscription.Cancel()
                LostSubscription.Cancel()
            Print("PCL|components|guard_actions=true|awareness=true", ?Duration := 0.0)
            loop:
                if (Ending? or Ticket <> Generation):
                    return
                if (not Character.IsActive[]):
                    return
                if (Info := VisibleTarget?):
                    if (Info.HasLineOfSight?):
                        if (not LastVisibility?):
                            Print("PCL|visibility|visible=true", ?Duration := 0.0)
                        set LastVisibility = true
                        if (RunningActionProbe?):
                            # A request is logged separately from damage. Completion is not a claimed hit.
                            Print("PCL|action_request|attack", ?Duration := 0.0)
                            race:
                                Actions.Attack(Info.Target)
                                Sleep(0.35)
                    else:
                        if (LastVisibility?):
                            Print("PCL|visibility|visible=false", ?Duration := 0.0)
                        set LastVisibility = false
                Sleep(0.25)
        else:
            Print("PCL|components|unverified|reason=component_lookup_failed", ?Duration := 0.0)

    OnSeen(Info : npc_target_info):void =
        set VisibleTarget = option{Info}
        Print("PCL|perception|target_seen", ?Duration := 0.0)

    OnForgotten(Target : entity):void =
        if (Info := VisibleTarget?, Info.Target = Target):
            set VisibleTarget = false
            set LastVisibility = false
            Print("PCL|perception|target_forgotten", ?Duration := 0.0)

    OnAlerted(Interaction : device_ai_interaction_result):void =
        Print("PCL|perception|guard_alerted", ?Duration := 0.0)

    OnTargetLost(Interaction : device_ai_interaction_result):void =
        Print("PCL|perception|guard_target_lost", ?Duration := 0.0)

    OnActualDamage(Result : damage_result):void =
        if (Victim := fort_character[Result.Target], Guard := Opponent?, Victim = Guard):
            Print("PCL|actual_damage|victim=opponent|amount={Result.Amount}", ?Duration := 0.0)
        else:
            Print("PCL|actual_damage|victim=player|amount={Result.Amount}", ?Duration := 0.0)

    OnActualElimination(Result : elimination_result):void =
        Print("PCL|actual_elimination", ?Duration := 0.0)

# Delayed callbacks belong to the guard generation that registered them.
coach_awareness_sink := class:
    Owner : coach_lab_device
    Character : fort_character
    Ticket : int

    OnSeen(Info : npc_target_info):void =
        if (not Owner.Ending?, Ticket = Owner.Generation, Character.IsActive[]):
            Owner.OnSeen(Info)

    OnForgotten(Target : entity):void =
        if (not Owner.Ending?, Ticket = Owner.Generation, Character.IsActive[]):
            Owner.OnForgotten(Target)
