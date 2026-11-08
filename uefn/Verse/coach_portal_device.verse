using { /Fortnite.com/AI }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Devices }
using { /Fortnite.com/Game }
using { /Fortnite.com/Playspaces }
using { /Fortnite.com/Teams }
using { /Fortnite.com/UI }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /UnrealEngine.com/Conversations }
using { /UnrealEngine.com/Temporary/UI }

coach_player_body_state := class<unique>:
    Character : fort_character
    ModeGeneration : int
    var Active : logic = true
    var LoadoutRequested : logic = false

coach_portal_device := class(creative_device):
    @editable
    OpponentSpawner : npc_spawner_device = npc_spawner_device{}
    @editable
    BaselineSpawner : guard_spawner_device = guard_spawner_device{}
    @editable
    UseCustomNPC : logic = false
    @editable
    SpeakerSpawner : npc_spawner_device = npc_spawner_device{}
    @editable
    VoiceReady : logic = false
    @editable
    LoadoutGranter : item_granter_device = item_granter_device{}
    @editable
    SpawnPadOne : player_spawner_device = player_spawner_device{}
    @editable
    SpawnPadTwo : player_spawner_device = player_spawner_device{}
    @editable
    DuelPreparationZone : mutator_zone_device = mutator_zone_device{}
    @editable
    DuelPreparationConfigured : logic = false
    @editable
    PersonalPreparationZone : mutator_zone_device = mutator_zone_device{}
    @editable
    PersonalPreparationConfigured : logic = false
    @editable
    MenuButton : button_device = button_device{}
    @editable
    MenuPersonal : button_device = button_device{}
    @editable
    MenuDuel : button_device = button_device{}
    @editable
    MenuFreeBuild : button_device = button_device{}
    @editable
    MenuEdits : button_device = button_device{}
    @editable
    WalkInEntrancesConfigured : logic = false
    @editable
    PersonalEntrance : volume_device = volume_device{}
    @editable
    DuelEntrance : volume_device = volume_device{}
    @editable
    FreeBuildEntrance : volume_device = volume_device{}
    @editable
    EditsEntrance : volume_device = volume_device{}
    @editable
    LessonButton : button_device = button_device{}
    @editable
    HubButton : button_device = button_device{}
    @editable
    ArenaControls : coach_arena_controls_device = coach_arena_controls_device{}
    @editable
    Structures : coach_structure_device = coach_structure_device{}
    @editable
    CoachInput : input_trigger_device = input_trigger_device{}
    @editable
    PersonalReset : explosive_device = explosive_device{}
    @editable
    DuelReset : explosive_device = explosive_device{}
    @editable
    FreeReset : explosive_device = explosive_device{}
    @editable
    EditReset : explosive_device = explosive_device{}
    @editable
    PersonalResetUpper : explosive_device = explosive_device{}
    @editable
    DuelResetUpper : explosive_device = explosive_device{}
    @editable
    FreeResetUpper : explosive_device = explosive_device{}
    @editable
    EditResetUpper : explosive_device = explosive_device{}
    @editable
    Course : coach_course_device = coach_course_device{}
    @editable
    Commerce : coach_commerce_device = coach_commerce_device{}
    @editable
    DemoOne : coach_demo_device = coach_demo_device{}
    @editable
    DemoTwo : coach_demo_device = coach_demo_device{}

    Runtime : coach_runtime = coach_runtime{}
    RoundFlow : coach_personal_round_flow = coach_personal_round_flow{}
    PersonalFlow : coach_personal_start_flow = coach_personal_start_flow{}
    ArenaAccess : coach_arena_access = coach_arena_access{}
    DuelFlow : coach_duel_round_flow = coach_duel_round_flow{}
    var Views : [player]coach_player_view = map{}
    var PlayerBindings : [player][]cancelable = map{}
    var PlayerBodies : [player]coach_player_body_state = map{}
    var Subscriptions : []cancelable = array{}
    var OpponentBindings : []cancelable = array{}
    var Opponent : ?fort_character = false
    var BaselineController : ?coach_opponent_behavior = false
    var EncounterSerial : int = 0
    var Ending : logic = false
    var ResetBusy : [int]logic = map{}
    var DuelRestarting : logic = false
    var DuelWins : [player]int = map{}
    var LessonStations : [player]coach_demo_device = map{}

    OnBegin<override>()<suspends>:void =
        if (PersonalPreparationConfigured?):
            PersonalPreparationZone.Disable()
        GetPlayspace().GetHUDController().HideElements(array{creative_hud_identifier_minimap{}, creative_hud_identifier_map_prompts{}})
        if (set CoachRuntime[GetSession()] = Runtime) {}
        set Runtime.Structures = option{Structures}
        set Course.Portal = option{Self}
        spawn { ObserveCombatFrames() }
        set Subscriptions = array{
            GetPlayspace().PlayerAddedEvent().Subscribe(OnPlayerAdded),
            GetPlayspace().PlayerRemovedEvent().Subscribe(OnPlayerRemoved),
            SpawnPadOne.SpawnedEvent.Subscribe(OnPlayerSpawned),
            SpawnPadTwo.SpawnedEvent.Subscribe(OnPlayerSpawned),
            MenuButton.InteractedWithEvent.Subscribe(OnMenu),
            MenuPersonal.InteractedWithEvent.Subscribe(OnPersonal),
            MenuDuel.InteractedWithEvent.Subscribe(OnDuel),
            MenuFreeBuild.InteractedWithEvent.Subscribe(OnFreeBuild),
            MenuEdits.InteractedWithEvent.Subscribe(OnEdits),
            LessonButton.InteractedWithEvent.Subscribe(OnLesson),
            HubButton.InteractedWithEvent.Subscribe(OnHub),
            CoachInput.PressedEvent.Subscribe(OnMenu),
            OpponentSpawner.SpawnedEvent.Subscribe(OnOpponentSpawned),
            SpeakerSpawner.SpawnedEvent.Subscribe(OnSpeakerSpawned),
            BaselineSpawner.SpawnedEvent.Subscribe(OnOpponentSpawned)
        }
        for (Button : array{MenuPersonal, MenuDuel, MenuFreeBuild, MenuEdits}):
            Button.Enable()
        if (WalkInEntrancesConfigured?):
            set Subscriptions += array{
                PersonalEntrance.AgentEntersEvent.Subscribe(OnPersonalEntrance),
                DuelEntrance.AgentEntersEvent.Subscribe(OnDuelEntrance),
                FreeBuildEntrance.AgentEntersEvent.Subscribe(OnFreeBuildEntrance),
                EditsEntrance.AgentEntersEvent.Subscribe(OnEditsEntrance)
            }
        ArenaControls.Bind(Self)
        for (Player : GetPlayspace().GetPlayers()):
            OnPlayerAdded(Player)
        Print("PCL|portal|ready", ?Duration := 0.0)
        loop:
            if (Ending?):
                return
            for (Player -> Training : Runtime.Players, not Training.Closed?):
                ObservePlayerBody(Player, Training)
                if (Player.IsActive[], GetSimulationElapsedTime() - Training.LastCheckpoint >= 15.0):
                    Training.SavePreferences()
                    set Training.LastCheckpoint = GetSimulationElapsedTime()
                if (View := Views[Player]):
                    View.UpdateHUD(Training)
            Sleep(0.5)

    VisibilityFor(Player : player)<transacts>:?logic =
        if (Character := Opponent?, Body := Character.GetEntity[], Awareness := Body.GetComponent[npc_awareness_component], PlayerCharacter := Player.GetFortCharacter[], PlayerEntity := PlayerCharacter.GetEntity[]):
            for (Info : Awareness.DetectedTargets, Info.Target = PlayerEntity):
                return option{Info.HasLineOfSight}
            return option{false}
        return false

    ObserveCombatFrames()<suspends>:void =
        var LastAt : float = -100.0
        var LastGeneration : int = -1
        loop:
            if (Ending?):
                return
            if (Training := Runtime.ActiveTrainee?, not Training.Closed?, Training.Phase = coach_phase.Fighting, not Training.Paused?, Student := Training.Owner.GetFortCharacter[], Student.IsActive[], Rival := Opponent?, Rival.IsActive[]):
                Now := GetSimulationElapsedTime()
                Visible := VisibilityFor(Training.Owner)
                var Crouched : logic = false
                if (Student.IsCrouching[]):
                    set Crouched = true
                Frame := coach_combat_frame{
                    At := Now, FightTime := Training.ActiveElapsed(Now),
                    PlayerPosition := Student.GetTransform().Translation,
                    OpponentPosition := Rival.GetTransform().Translation,
                    PlayerView := Student.GetViewRotation(), OpponentView := Rival.GetViewRotation(),
                    PlayerHealth := Student.GetHealth(), PlayerShield := Student.GetShield(),
                    OpponentHealth := Rival.GetHealth(), OpponentShield := Rival.GetShield(),
                    PlayerCrouched := Crouched, VisibleToOpponent := Visible
                }
                if (LastGeneration = Training.Generation and Now - LastAt <= 0.3):
                    if (Seen := Visible?):
                        Training.ObserveExposure(Seen, Clamp(Now - LastAt, 0.0, 0.25))
                else:
                    set Training.ExposureRun = 0.0
                    Training.HumanPatterns.ResetObservation()
                    Training.Habits.ResetObservation()
                Training.History.Add(Frame)
                Training.HumanPatterns.ObserveVisibleFrame(Frame)
                Training.Habits.ObserveVisibleFrame(Frame)
                Training.Practice.Observe(Frame)
                Training.CheckpointPlanPractice()
                if (Training.Practice.Completed? and not Training.Practice.CompletionShown?):
                    ShowFocusedSummary(Training.Owner)
                set LastAt = Now
                set LastGeneration = Training.Generation
            else:
                set LastGeneration = -1
            Sleep(0.1)

    OnEnd<override>():void =
        set Ending = true
        set Runtime.Ending = true
        ClearOpponent()
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        for (Player -> Bindings : PlayerBindings):
            for (Binding : Bindings):
                Binding.Cancel()
        for (Player -> Training : Runtime.Players):
            ReleaseLessonStation(Player)
            Training.SavePreferences()
            if (Voice := Training.VoiceLink?):
                Voice.Dispose()
            set Training.Closed = true
            set Training.Generation += 1
            if (View := Views[Player]):
                View.Dispose()

    AppendCombatSnapshot(Training : coach_training_session):void =
        if (not Training.Closed?, not Training.Paused?, Training.Phase = coach_phase.Fighting, Student := Training.Owner.GetFortCharacter[], Rival := Opponent?):
            Now := GetSimulationElapsedTime()
            var Crouched : logic = false
            if (Student.IsCrouching[]):
                set Crouched = true
            Training.History.Add(coach_combat_frame{
                At := Now, FightTime := Training.ActiveElapsed(Now),
                PlayerPosition := Student.GetTransform().Translation, OpponentPosition := Rival.GetTransform().Translation,
                PlayerView := Student.GetViewRotation(), OpponentView := Rival.GetViewRotation(),
                PlayerHealth := Student.GetHealth(), PlayerShield := Student.GetShield(),
                OpponentHealth := Rival.GetHealth(), OpponentShield := Rival.GetShield(),
                PlayerCrouched := Crouched, VisibleToOpponent := VisibilityFor(Training.Owner)
            })

    OnPlayerAdded(Player : player):void =
        if (Runtime.Players[Player]):
            return
        Training := coach_training_session{Owner := Player}
        Training.Initialize()
        View := coach_player_view{Owner := Self, Player := Player}
        if (set Runtime.Players[Player] = Training, set Views[Player] = View):
            Commerce.Join(Player)
            CoachInput.Register(Player)
            View.EnsureHUD()
            spawn { InitializePlayer(Player) }

    InitializePlayer(Player : player)<suspends>:void =
        for (Attempt := 0..39):
            if (Ending?):
                return
            if (Training := Runtime.Players[Player], not Training.Closed?, Character := Player.GetFortCharacter[], Character.IsActive[], UI := GetPlayerUI[Player]):
                ObservePlayerBody(Player, Training)
                if (Training.Mode = coach_mode.Hub and Training.Phase = coach_phase.Ready):
                    MovePlayer(Player, CoachPlayerStart(coach_mode.Hub))
                    Character.SetVulnerability(false)
                    if (View := Views[Player]):
                        View.SetCaption(CoachLanguage("Welcome. Walk through a training gate, use its button, or open the coach menu.", "ברוך הבא. עבור בשער כדי להיכנס לאימון, השתמש בכפתור הכניסה או פתח את תפריט המאמן.", Training.HebrewText))
                return
            Sleep(0.1)

    OnPlayerRemoved(Player : player):void =
        ArenaAccess.Release(Player)
        ReleaseLessonStation(Player)
        Commerce.Leave(Player)
        Course.Release(Player)
        LeaveDuel(Player)
        Structures.EndDemo(Player)
        CoachInput.Unregister(Player)
        if (Training := Runtime.Players[Player]):
            if (Voice := Training.VoiceLink?):
                Voice.Dispose()
            set Training.Closed = true
            set Training.Generation += 1
            if (Current := Runtime.ActiveTrainee?, Current.Owner = Player):
                ClearOpponent()
                if (VoiceReady?):
                    SpeakerSpawner.DespawnAll(false)
                set Runtime.ActiveTrainee = false
        if (Bindings := PlayerBindings[Player]):
            for (Binding : Bindings):
                Binding.Cancel()
        if (View := Views[Player]):
            View.Dispose()
        var RemainingPlayers : [player]coach_training_session = map{}
        var RemainingViews : [player]coach_player_view = map{}
        var RemainingBindings : [player][]cancelable = map{}
        var RemainingBodies : [player]coach_player_body_state = map{}
        var RemainingWins : [player]int = map{}
        for (Other -> Value : Runtime.Players, Other <> Player):
            if (set RemainingPlayers[Other] = Value) {}
        for (Other -> Value : Views, Other <> Player):
            if (set RemainingViews[Other] = Value) {}
        for (Other -> Value : PlayerBindings, Other <> Player):
            if (set RemainingBindings[Other] = Value) {}
        for (Other -> Value : PlayerBodies, Other <> Player):
            if (set RemainingBodies[Other] = Value) {}
        for (Other -> Value : DuelWins, Other <> Player):
            if (set RemainingWins[Other] = Value) {}
        set Runtime.Players = RemainingPlayers
        set Views = RemainingViews
        set PlayerBindings = RemainingBindings
        set PlayerBodies = RemainingBodies
        set DuelWins = RemainingWins

    OnPlayerSpawned(Agent : agent):void =
        if (Player := player[Agent]):
            OnPlayerAdded(Player)
            if (Training := Runtime.Players[Player]):
                ObservePlayerBody(Player, Training)

    # Spawn-pad events can arrive before a live body is available, and other
    # respawn routes need not use these two pads. Share one body lifecycle.
    ObservePlayerBody(Player : player, Training : coach_training_session):void =
        if (Ending? or Training.Closed? or not Player.IsActive[]):
            return
        if (Character := Player.GetFortCharacter[], Character.IsActive[]):
            if (Previous := PlayerBodies[Player], Previous.Character = Character, Previous.Active?):
                return
            State := coach_player_body_state{Character := Character, ModeGeneration := Training.Generation}
            if (set PlayerBodies[Player] = State) {}
            else:
                return
            BindPlayer(Player)
            spawn { RestoreSpawnedBody(Player, State) }
        else if (Previous := PlayerBodies[Player]):
            set Previous.Active = false

    PlayerBodyCurrent(Player : player, State : coach_player_body_state)<transacts>:logic =
        if (not Ending?, State.Active?, Player.IsActive[], Current := PlayerBodies[Player], Current = State, Training := Runtime.Players[Player], not Training.Closed?, Body := Player.GetFortCharacter[], Body = State.Character, Body.IsActive[]):
            return true
        return false

    MarkPlayerBodyInactive(Player : player, Character : fort_character):void =
        if (State := PlayerBodies[Player], State.Character = Character):
            set State.Active = false

    RestoreSpawnedBody(Player : player, State : coach_player_body_state)<suspends>:void =
        # Defer off the spawn callback and retain the exact live body. A late
        # notification never grants a second loadout to the same active life.
        Sleep(0.1)
        if (not PlayerBodyCurrent(Player, State)? or State.LoadoutRequested?):
            return
        set State.LoadoutRequested = true
        LoadoutGranter.GrantItem(Player)
        Print("PCL|player_body|loadout_requested|inventory_acceptance_pending", ?Duration := 0.0)
        # A newer mode/round owns its transfer and staging. Do not replay an
        # old respawn transition over a selection made during the delay.
        if (PlayerBodyCurrent(Player, State)?, Training := Runtime.Players[Player], Training.Generation = State.ModeGeneration):
            if (Training.Phase = coach_phase.Review):
                if (Character := Player.GetFortCharacter[]):
                    Character.SetVulnerability(false)
                if (View := Views[Player]):
                    View.CloseMenu()
            else if (Training.Mode = coach_mode.Hub):
                MovePlayer(Player, CoachPlayerStart(coach_mode.Hub))
                if (Character := Player.GetFortCharacter[]):
                    Character.SetVulnerability(false)
            else if (Training.Mode <> coach_mode.Personal):
                EnterMode(Player, Training.Mode)
            else if (Training.Phase = coach_phase.Lesson):
                ShowLesson(Player)

    BindPlayer(Player : player):void =
        if (Previous := PlayerBindings[Player]):
            for (Binding : Previous):
                Binding.Cancel()
        if (Character := Player.GetFortCharacter[]):
            Sink := coach_player_combat_sink{Owner := Self, Player := Player, Character := Character}
            Bindings := array{
                Character.DamagedEvent().Subscribe(Sink.OnDamage),
                Character.DamagedShieldEvent().Subscribe(Sink.OnDamage),
                Character.EliminatedEvent().Subscribe(Sink.OnEliminated)
            }
            if (set PlayerBindings[Player] = Bindings) {}

    ClearOpponent():void =
        if (PersonalPreparationConfigured?):
            PersonalPreparationZone.Disable()
        Structures.ResetEncounter()
        set EncounterSerial += 1
        for (Binding : OpponentBindings):
            Binding.Cancel()
        set OpponentBindings = array{}
        if (Controller := BaselineController?):
            Controller.OnEnd()
        set BaselineController = false
        set Opponent = false
        OpponentSpawner.DespawnAll(false)
        BaselineSpawner.Despawn()

    RestoreRoundVitals(Body : fort_character):void =
        # The same opening state applies to trainee, rival and both duelists.
        # Difficulty changes execution, never an unannounced health advantage.
        Body.SetMaxHealth(100.0)
        Body.SetMaxShield(100.0)
        Body.SetHealth(100.0)
        Body.SetShield(100.0)

    RoundVitalsReady(Body : fort_character)<transacts>:logic =
        if (Body.IsActive[], Abs(Body.GetMaxHealth() - 100.0) < 0.1, Abs(Body.GetMaxShield() - 100.0) < 0.1, Abs(Body.GetHealth() - 100.0) < 0.1, Abs(Body.GetShield() - 100.0) < 0.1):
            return true
        return false

    OpponentLoadoutPrepared(Body : fort_character)<transacts>:logic =
        if (Body.IsActive[], Owner := Body.GetAgent[]):
            var Candidate : ?coach_opponent_behavior = BaselineController
            if (UseCustomNPC?):
                set Candidate = false
                if (Native := Owner.GetNPCBehavior[], Controller := coach_opponent_behavior[Native]):
                    set Candidate = option{Controller}
            if (Controller := Candidate?, not Controller.Ending?, Bound := Controller.ControlledCharacter?, Bound = Body, Controller.CombatSight?, Controller.Equipment.RangedReady(Owner)?):
                return true
        return false

    StartPersonal(Player : player, ?PreserveExercise : logic = false, ?ExerciseGoal : int = 0, ?PlanRevision : int = -1, ?PlanApplication : logic = false):void =
        if (Active := Runtime.ActiveTrainee?, Active.Owner <> Player, not Active.Closed?, Active.Mode = coach_mode.Personal):
            if (View := Views[Player], Training := Runtime.Players[Player]):
                View.ShowMenu(CoachLanguage("Coach in session", "המאמן באימון", Training.HebrewText), CoachLanguage("Use free build or edit training while this session finishes.", "אפשר להתאמן בבנייה ובעריכות עד שהאימון יסתיים.", Training.HebrewText), array{coach_menu_entry{Label := CoachLanguage("Back", "חזרה", Training.HebrewText), Action := 20}})
            return
        Acquired := AcquireMode(Player, coach_mode.Personal)
        if (not Acquired?):
            return
        if (Training := Runtime.Players[Player], View := Views[Player]):
            Course.Release(Player)
            LeaveDuel(Player)
            EndLesson(Player)
            ClearOpponent()
            RoundFlow.Cancel(Training)
            set Training.Generation += 1
            set Training.Mode = coach_mode.Personal
            set Training.Phase = coach_phase.Preparing
            set Training.Paused = true
            Training.Tactics.Cancel()
            Training.Practice.ResetObservation()
            set Runtime.ActiveTrainee = option{Training}
            if (Character := Player.GetFortCharacter[], Character.IsActive[]):
                Character.SetVulnerability(false)
                Character.PutInStasis(stasis_args{AllowTurning := true, AllowFalling := true})
            View.CloseMenu()
            set PersonalFlow.Countdown = 0
            View.SetCaption(CoachLanguage("Preparing your training round.", "מכין את סיבוב האימון שלך.", Training.HebrewText))
            spawn { PersonalFlow.Prepare(Self, Training, Training.Generation, PreserveExercise, ExerciseGoal, PlanRevision, PlanApplication) }

    OnOpponentSpawned(Agent : agent):void =
        Print("PCL|personal|spawn_notification_received", ?Duration := 0.0)
        if (Character := Agent.GetFortCharacter[], Training := Runtime.ActiveTrainee?, Training.Mode = coach_mode.Personal, Training.Phase = coach_phase.Fighting or Training.Phase = coach_phase.Preparing):
            if (Current := Opponent?, Current = Character):
                return
            set Opponent = option{Character}
            if (Training.Phase = coach_phase.Preparing):
                Character.SetVulnerability(false)
                Character.PutInStasis(stasis_args{AllowTurning := false, AllowFalling := true})
            RestoreRoundVitals(Character)
            Sink := coach_opponent_combat_sink{Owner := Self, Character := Character, Ticket := EncounterSerial}
            set OpponentBindings = array{
                Character.DamagedEvent().Subscribe(Sink.OnDamage),
                Character.DamagedShieldEvent().Subscribe(Sink.OnDamage),
                Character.EliminatedEvent().Subscribe(Sink.OnEliminated)
            }
            if (not UseCustomNPC?):
                if (Body := Character.GetEntity[], Actions := Body.GetComponent[guard_actions_component], Awareness := Body.GetComponent[npc_awareness_component]):
                    Controller := coach_opponent_behavior{}
                    set BaselineController = option{Controller}
                    spawn { Controller.Run(Character, Actions, Awareness) }
            Print("PCL|personal|opponent_bound|encounter={EncounterSerial}", ?Duration := 0.0)

    AwaitOpponentBinding(Ticket : int)<suspends>:void =
        # Reconcile only agents owned by this spawner if its notification was missed.
        for (Attempt := 0..79):
            Sleep(0.1)
            if (Ending? or Ticket <> EncounterSerial):
                return
            if (Current := Opponent?, Current.IsActive[]):
                return
            if (Training := Runtime.ActiveTrainee?, Training.Phase = coach_phase.Fighting or Training.Phase = coach_phase.Preparing):
                for (Agent : OpponentSpawner.GetAgents(), Character := Agent.GetFortCharacter[], Character.IsActive[]):
                    OnOpponentSpawned(Agent)
                    Print("PCL|personal|owned_spawner_reconciled|encounter={Ticket}|attempt={Attempt}", ?Duration := 0.0)
                    return
            else:
                return
        Print("PCL|personal|spawn_binding_wait_expired|encounter={Ticket}", ?Duration := 0.0)

    OnSpeakerSpawned(Agent : agent):void =
        if:
            Training := Runtime.ActiveTrainee?
            not Training.Closed?
            View := Views[Training.Owner]
            Character := Agent.GetFortCharacter[]
            Body := Character.GetEntity[]
            Root := GetSimulationEntity[]
        then:
            var Persona : ?persona_component = false
            if (Existing := Body.GetComponent[persona_component]):
                set Persona = option{Existing}
            else:
                Created := persona_component{Entity := Body}
                Body.AddComponents(array{Created})
                set Persona = option{Created}
            if (Component := Persona?):
                Voice := coach_voice_link{Training := Training, Root := Root, Speaker := Agent, Persona := Component, View := View}
                Voice.Connect()
                set Training.VoiceLink = option{Voice}
                if (Training.Timing = coach_timing.DuringAndAfter):
                    Voice.Say(CoachMessage("Welcome the player to personal training in one sentence. Explain that they can pause for a focused lesson. Speak English."), true)

    PausePersonal(Player : player):void =
        if (Training := Runtime.ActiveTrainee?, Training.Owner = Player, Training.Phase = coach_phase.Fighting):
            if (not Training.Paused?):
                set Training.PauseStartedAt = GetSimulationElapsedTime()
            set Training.Paused = true
            Training.Tactics.Cancel()
            Training.Practice.ResetObservation()
            set Training.Generation += 1
            if (Character := Player.GetFortCharacter[]):
                Character.SetVulnerability(false)
            if (Character := Opponent?, Character.IsActive[]):
                Character.PutInStasis(stasis_args{AllowTurning := false, AllowFalling := true})
                Character.SetVulnerability(false)

    ResumePersonal(Player : player):void =
        if (Training := Runtime.ActiveTrainee?, Training.Owner = Player, Training.Phase = coach_phase.Fighting or Training.Phase = coach_phase.Lesson and Training.LessonFromFight?, ActiveOpponent := Opponent?, ActiveOpponent.IsActive[]):
            Course.Release(Player)
            EndLesson(Player)
            if (Training.PauseStartedAt >= 0.0):
                set Training.PausedTotal += Max(0.0, GetSimulationElapsedTime() - Training.PauseStartedAt)
                set Training.PauseStartedAt = -1.0
            set Training.Phase = coach_phase.Fighting
            set Training.Paused = false
            set Training.Generation += 1
            if (Character := Player.GetFortCharacter[]):
                Character.SetVulnerability(true)
            if (Character := Opponent?, Character.IsActive[]):
                Character.ReleaseFromStasis()
                Character.SetVulnerability(true)
            if (View := Views[Player]):
                View.CloseMenu()

    FinishPersonal(Won : logic):void =
        if (Training := Runtime.ActiveTrainee?, Training.Phase = coach_phase.Fighting):
            RoundFlow.Finish(Self, Training, Won)

    InterruptPersonal():void =
        if (Training := Runtime.ActiveTrainee?, Training.Phase = coach_phase.Fighting):
            RoundFlow.Interrupt(Self, Training)

    MovePlayer(Player : player, Position : vector3):void =
        if (Character := Player.GetFortCharacter[], Character.TeleportTo[Position, IdentityRotation()]):
            return
        Print("PCL|portal|teleport_unconfirmed", ?Duration := 0.0)

    RestorePlayer(Player : player):void =
        if (Character := Player.GetFortCharacter[]):
            Character.ReleaseFromStasis()
            Character.SetVulnerability(true)
            Character.SetHealth(Character.GetMaxHealth())
            Character.SetShield(Character.GetMaxShield())

    SetPlayerTeam(Player : player, Index : int):void =
        Collection := GetPlayspace().GetTeamCollection()
        if (Team := Collection.GetTeams()[Index], Collection.AddToTeam[Player, Team]) {}

    ExitPersonal(Player : player):void =
        EndLesson(Player)
        if (Training := Runtime.ActiveTrainee?, Training.Owner = Player):
            set Training.Generation += 1
            ClearOpponent()
            if (Voice := Training.VoiceLink?):
                Voice.Dispose()
            set Training.VoiceLink = false
            if (VoiceReady?):
                SpeakerSpawner.DespawnAll(false)
            set Runtime.ActiveTrainee = false

    AcquireMode(Player : player, Mode : coach_mode):logic =
        if (Mode = coach_mode.EditTraining, Owner := Course.CurrentOwner?, Owner <> Player):
            if (View := Views[Player], Training := Runtime.Players[Player]):
                View.SetCaption(CoachLanguage("Edit training is occupied. Choose another entrance for now.", "אזור העריכות תפוס כרגע. אפשר לבחור כניסה אחרת בינתיים.", Training.HebrewText))
            return false
        if (ArenaAccess.TryEnter(Player, Mode)?):
            return true
        if (View := Views[Player], Training := Runtime.Players[Player]):
            View.SetCaption(CoachLanguage("This area is in use. Your current training continues; choose another entrance or return later.", "האזור תפוס כרגע. האימון הנוכחי ממשיך; אפשר לבחור אזור אחר או לחזור בהמשך.", Training.HebrewText))
        return false

    EnterMode(Player : player, Mode : coach_mode):void =
        Acquired := AcquireMode(Player, Mode)
        if (not Acquired?):
            return
        Course.Release(Player, ?KeepReservation := logic{Mode = coach_mode.EditTraining})
        if (Mode <> coach_mode.Duel):
            LeaveDuel(Player)
        ExitPersonal(Player)
        if (Training := Runtime.Players[Player], View := Views[Player]):
            set Training.Mode = Mode
            set Training.Phase = coach_phase.Ready
            set Training.Paused = false
            set Training.Generation += 1
            if (Mode <> coach_mode.Duel):
                RestorePlayer(Player)
            if (Mode <> coach_mode.Duel):
                SetPlayerTeam(Player, 0)
            if (Mode = coach_mode.FreeBuild):
                MovePlayer(Player, CoachPlayerStart(coach_mode.FreeBuild))
            else if (Mode = coach_mode.EditTraining):
                MovePlayer(Player, CoachPlayerStart(coach_mode.EditTraining))
            else if (Mode = coach_mode.Duel):
                Duelists := DuelFlow.Participants(Self, ?Except := option{Player}).Length
                SetPlayerTeam(Player, Min(Duelists, 1))
                MovePlayer(Player, CoachDuelStart(Duelists))
                LoadoutGranter.GrantItem(Player)
                if (Character := Player.GetFortCharacter[]):
                    Character.SetVulnerability(false)
            else:
                MovePlayer(Player, CoachPlayerStart(coach_mode.Hub))
            if (Mode <> coach_mode.Personal and Mode <> coach_mode.Duel, Character := Player.GetFortCharacter[]):
                Character.SetVulnerability(false)
            View.CloseMenu()
            if (Mode = coach_mode.Duel):
                DuelFlow.Join(Self)
            if (Mode = coach_mode.EditTraining):
                ShowEditPractice(Player)

    OnMenu(Agent : agent):void =
        if (Player := player[Agent]):
            if (Training := Runtime.Players[Player], Training.Mode = coach_mode.Personal, Training.Phase = coach_phase.Preparing):
                EnterMode(Player, coach_mode.Hub)
                ShowHub(Player)
                return
            if (Training := Runtime.Players[Player], Training.Mode = coach_mode.Personal, Training.Phase = coach_phase.Review):
                ShowReview(Player)
                return
            Course.Pause(Player)
            PausePersonal(Player)
            ShowHub(Player)

    OnLesson(Agent : agent):void =
        if (Player := player[Agent]):
            PausePersonal(Player)
            ShowLesson(Player)

    OnHub(Agent : agent):void =
        if (Player := player[Agent]):
            EnterMode(Player, coach_mode.Hub)
            ShowHub(Player)

    OnPersonal(Agent : agent):void =
        if (Player := player[Agent]):
            Print("PCL|portal|entry_requested|mode=personal", ?Duration := 0.0)
            StartPersonal(Player)

    OnDuel(Agent : agent):void =
        if (Player := player[Agent]):
            Print("PCL|portal|entry_requested|mode=duel", ?Duration := 0.0)
            EnterMode(Player, coach_mode.Duel)

    OnFreeBuild(Agent : agent):void =
        if (Player := player[Agent]):
            Print("PCL|portal|entry_requested|mode=free_build", ?Duration := 0.0)
            EnterMode(Player, coach_mode.FreeBuild)

    OnEdits(Agent : agent):void =
        if (Player := player[Agent]):
            Print("PCL|portal|entry_requested|mode=edits", ?Duration := 0.0)
            EnterMode(Player, coach_mode.EditTraining)

    LobbyEntranceCurrent(Agent : agent)<transacts>:logic =
        if (not Ending?, Player := player[Agent], Player.IsActive[], Training := Runtime.Players[Player], not Training.Closed?, Training.Mode = coach_mode.Hub, Training.Phase = coach_phase.Ready):
            return true
        return false

    OnPersonalEntrance(Agent : agent):void =
        if (LobbyEntranceCurrent(Agent)?):
            OnPersonal(Agent)

    OnDuelEntrance(Agent : agent):void =
        if (LobbyEntranceCurrent(Agent)?):
            OnDuel(Agent)

    OnFreeBuildEntrance(Agent : agent):void =
        if (LobbyEntranceCurrent(Agent)?):
            OnFreeBuild(Agent)

    OnEditsEntrance(Agent : agent):void =
        if (LobbyEntranceCurrent(Agent)?):
            OnEdits(Agent)

    HandleAction(Player : player, Action : int):void =
        if (Ending? or not Player.IsActive[]):
            return
        if (Action = 0):
            StartPersonal(Player)
        else if (Action = 1):
            EnterMode(Player, coach_mode.Duel)
        else if (Action = 2):
            EnterMode(Player, coach_mode.FreeBuild)
        else if (Action = 3):
            EnterMode(Player, coach_mode.EditTraining)
        else if (Action = 4):
            ShowSettings(Player)
        else if (Action = 5):
            ResumePersonal(Player)
        else if (Action = 6):
            ShowLesson(Player)
        else if (Action = 7):
            EnterMode(Player, coach_mode.Hub)
            ShowHub(Player)
        else if (Action = 8):
            EnterMode(Player, coach_mode.Hub)
            if (View := Views[Player]):
                View.CloseMenu()
        else if (Action >= 10 and Action <= 16):
            UpdateSettings(Player, Action)
        else if (Action = 20):
            ShowHub(Player)
        else if (Action = 21):
            if (Training := Runtime.Players[Player]):
                set Training.LessonPlaying = false
                set Training.LessonStep = Max(0, Training.LessonStep - 1)
                set Training.LessonProgress = 0.0
                set Training.LessonSeek = true
            ShowLesson(Player)
        else if (Action = 22):
            if (Training := Runtime.Players[Player]):
                set Training.LessonPlaying = false
                set Training.LessonStep = Min(CoachLessonSteps(Training.LessonIndex) - 1, Training.LessonStep + 1)
                set Training.LessonProgress = 0.0
                set Training.LessonSeek = true
            ShowLesson(Player)
        else if (Action = 23):
            if (Training := Runtime.Players[Player]):
                if (Training.LessonPlaying?):
                    set Training.LessonPlaying = false
                else:
                    set Training.LessonPlaying = true
            ShowLesson(Player)
        else if (Action = 24):
            if (Training := Runtime.Players[Player]):
                if (Training.LessonDiagram?):
                    set Training.LessonDiagram = false
                else:
                    set Training.LessonDiagram = true
            ShowLesson(Player)
        else if (Action = 30):
            if (Training := Runtime.Players[Player]):
                ResetArea(Player, Training.Mode)
                if (Training.Mode = coach_mode.Personal and Training.Paused?):
                    ResumePersonal(Player)
                if (View := Views[Player]):
                    View.CloseMenu()
        else if (Action = 31):
            if (Course.IsActiveFor(Player)?):
                Course.Resume(Player)
                if (View := Views[Player]):
                    View.CloseMenu()
            else if (Training := Runtime.Players[Player], Training.Mode = coach_mode.Personal and Training.Paused?):
                ResumePersonal(Player)
            else if (View := Views[Player]):
                View.CloseMenu()
        else if (Action = 40 or Action = 41 or Action = 43):
            var Kind : coach_course_kind = coach_course_kind.PrecisionWalls
            if (Action = 41):
                set Kind = coach_course_kind.TripleSequence
            else if (Action = 43):
                set Kind = coach_course_kind.TripleChain
            Course.Start(Player, Kind)
        else if (Action = 42):
            ShowEditPractice(Player)
        else if (Action >= 44 and Action <= 46):
            var Kind : coach_course_kind = coach_course_kind.PrecisionWalls
            if (Action = 45):
                set Kind = coach_course_kind.TripleSequence
            else if (Action = 46):
                set Kind = coach_course_kind.TripleChain
            TryLessonCourse(Player, ?SelectedKind := option{Kind})
        else if (Action = 47):
            if (Training := Runtime.Players[Player], Training.Phase = coach_phase.Lesson):
                ShowLesson(Player)
        else if (Action = 50):
            ShowMomentAnalysis(Player)
        else if (Action = 58):
            if (Training := Runtime.Players[Player], Training.Phase = coach_phase.Review):
                Training.History.ClearReviewSelection()
                ShowMomentAnalysis(Player)
        else if (Action = 59):
            ShowReviewMomentChoices(Player)
        else if (Action >= 110 and Action <= 113):
            if (Training := Runtime.Players[Player], Training.Phase = coach_phase.Review, View := Views[Player], Moment := View.ReviewMomentChoices[Action - 110]):
                Selected := Training.History.SelectReviewMoment(Moment)
                if (Selected?):
                    ShowMomentAnalysis(Player)
                else:
                    View.SetCaption(CoachLanguage("The position samples for that moment are no longer available. Choose another moment.", "דגימות המיקום של הרגע הזה כבר אינן זמינות. בחר רגע אחר.", Training.HebrewText))
        else if (Action = 57):
            if (Commerce.AllowsAdvancedFeatures(Player)?, Training := Runtime.Players[Player], Latest := Training.History.LatestFrame()?, View := Views[Player]):
                set View.ReplayFrames = Training.History.ActiveWindow(Latest.FightTime, 90.0, 0.0)
                set View.ReplayIndex = 0
                set View.ReplayPlaying = false
                ShowRecordedReview(Player, false)
        else if (Action >= 51 and Action <= 55):
            if (View := Views[Player]):
                if (Action = 51):
                    set View.ReplayPlaying = false
                    if (Current := View.ReplayFrames[View.ReplayIndex]):
                        var Selected : int = 0
                        for (Index -> Frame : View.ReplayFrames, Frame.FightTime <= Current.FightTime - 0.5):
                            set Selected = Index
                        set View.ReplayIndex = Selected
                else if (Action = 52):
                    set View.ReplayPlaying = false
                    if (Current := View.ReplayFrames[View.ReplayIndex]):
                        var Selected : int = View.ReplayFrames.Length - 1
                        for (Index -> Frame : View.ReplayFrames, Frame.FightTime >= Current.FightTime + 0.5):
                            set Selected = Min(Selected, Index)
                        set View.ReplayIndex = Selected
                else if (Action = 53):
                    if (View.ReplayPlaying?):
                        set View.ReplayPlaying = false
                    else:
                        if (View.ReplayIndex >= View.ReplayFrames.Length - 1):
                            set View.ReplayIndex = 0
                        set View.ReplayPlaying = true
                else if (Action = 54):
                    set View.ReplaySpeed = Max(0.25, View.ReplaySpeed - 0.25)
                else:
                    set View.ReplaySpeed = Min(2.0, View.ReplaySpeed + 0.25)
            ShowRecordedReview(Player, false)
        else if (Action = 56):
            ShowReview(Player)
        else if (Action = 60):
            ShowProgress(Player)
        else if (Action = 61):
            ShowRoundHistory(Player)
        else if (Action = 70):
            ShowLessonLibrary(Player)
        else if (Action >= 71 and Action <= 73):
            SelectLesson(Player, Action - 71)
        else if (Action = 74):
            TryLessonCourse(Player)
        else if (Action = 75):
            ShowRecordedReview(Player, true)
        else if (Action = 76):
            StartFocusedPractice(Player, 1)
        else if (Action = 77):
            StartFocusedPractice(Player, 2)
        else if (Action = 78):
            if (Training := Runtime.Players[Player], Training.Phase = coach_phase.Review, Training.Practice.Goal > 0, not Training.Practice.Completed?):
                StartPersonal(Player, ?PreserveExercise := true)
                if (View := Views[Player]):
                    View.SetCaption(Training.Practice.Instruction(Training.HebrewText))
        else if (Action = 79):
            if (Training := Runtime.Players[Player], Training.Phase = coach_phase.Review):
                Recommendation := CoachRecommendLesson(Training)
                SelectLesson(Player, Recommendation.Lesson)
        else if (Action = 80):
            spawn { Commerce.OpenOffers(Player) }
        else if (Action = 90):
            SaveCurrentTrainingPlan(Player, false)
        else if (Action = 91):
            ShowTrainingPlan(Player)
        else if (Action = 92):
            ContinueTrainingPlan(Player)
        else if (Action = 93):
            StartPlanPractice(Player)
        else if (Action = 94):
            if (Training := Runtime.Players[Player], Training.Profile.TrainingPlan.Stage > 0):
                SelectLesson(Player, Training.Profile.TrainingPlan.Lesson)
        else if (Action = 96):
            SaveCurrentTrainingPlan(Player, true)

    ShowHub(Player : player):void =
        if (Training := Runtime.Players[Player], View := Views[Player]):
            H := Training.HebrewText
            var Entries : []coach_menu_entry = array{}
            if (Training.Mode <> coach_mode.Hub and Training.Mode <> coach_mode.Personal or Course.IsActiveFor(Player)?):
                set Entries += array{coach_menu_entry{Label := CoachLanguage("Continue practicing", "המשך תרגול", H), Action := 31}}
            if (Training.Mode = coach_mode.Personal and Training.Paused? and (Training.Phase = coach_phase.Fighting or Training.Phase = coach_phase.Lesson and Training.LessonFromFight?)):
                set Entries += array{
                    coach_menu_entry{Label := CoachLanguage("Resume training", "המשך אימון", H), Action := 5},
                    coach_menu_entry{Label := CoachLanguage("Pause for a lesson", "עצירה לשיעור", H), Action := 6}
                }
            set Entries += array{
                coach_menu_entry{Label := CoachLanguage("Personal coach", "מאמן אישי", H), Action := 0},
                coach_menu_entry{Label := CoachLanguage("1V1", "אחד על אחד", H), Action := 1},
                coach_menu_entry{Label := CoachLanguage("Free build", "בנייה חופשית", H), Action := 2},
                coach_menu_entry{Label := CoachLanguage("Edit training", "אימון עריכות", H), Action := 3},
                coach_menu_entry{Label := CoachLanguage("Coach preferences", "העדפות המאמן", H), Action := 4},
                coach_menu_entry{Label := CoachLanguage("Your training progress", "ההתקדמות שלך באימון", H), Action := 60},
                coach_menu_entry{Label := CoachLanguage("My training plan", "תוכנית האימון שלי", H), Action := 91},
                coach_menu_entry{Label := CoachLanguage("Explore the academy", "סיור באקדמיה", H), Action := 8}
            }
            if (Training.Mode <> coach_mode.Hub):
                set Entries += array{coach_menu_entry{Label := CoachLanguage("Reset builds in this area", "איפוס הבנייה באזור הזה", H), Action := 30}}
            if (Training.Mode = coach_mode.EditTraining):
                set Entries += array{coach_menu_entry{Label := CoachLanguage("Choose an edit course", "בחירת מסלול עריכות", H), Action := 42}}
            if (Commerce.HasCatalog()? and Training.Mode = coach_mode.Hub):
                set Entries += array{coach_menu_entry{Label := CoachLanguage("Training content details", "פרטי תוכן נוסף לאימון", H), Action := 80}}
            View.ShowMenu(CoachLanguage("Your next level starts here", "האימון הבא שלך מתחיל כאן", H), CoachLanguage("Fight with purpose. Learn one useful change. Bring it into your next round.", "הילחם עם מטרה. למד שינוי מועיל אחד ויישם אותו בסיבוב הבא.", H), Entries)

    ShowReview(Player : player):void =
        if (Training := Runtime.Players[Player], View := Views[Player]):
            RoundFlow.Cancel(Training)
            H := Training.HebrewText
            Out := CoachNumber(Training.OutgoingDamage)
            Inc := CoachNumber(Training.IncomingDamage)
            var Entries : []coach_menu_entry = array{
                coach_menu_entry{Label := CoachLanguage("Another round", "סיבוב נוסף", H), Action := 0},
                coach_menu_entry{Label := CoachLanguage("Review the moment", "ניתוח הרגע", H), Action := 50},
                coach_menu_entry{Label := CoachLanguage("Choose a damage moment", "בחירת רגע פגיעה", H), Action := 59},
                coach_menu_entry{Label := CoachLanguage("Recommended lesson", "השיעור המומלץ", H), Action := 79},
                coach_menu_entry{Label := CoachLanguage("Back to lobby", "חזרה ללובי", H), Action := 7},
                coach_menu_entry{Label := CoachLanguage("Coach settings", "הגדרות המאמן", H), Action := 4}
            }
            if (Commerce.AllowsAdvancedFeatures(Player)?):
                set Entries += array{coach_menu_entry{Label := CoachLanguage("Explore the last 90 seconds", "צפייה ב־90 השניות האחרונות", H), Action := 57}}
            if (Training.Practice.Goal > 0 and not Training.Practice.Completed?):
                set Entries = array{coach_menu_entry{Label := CoachLanguage("Continue exercise / {Training.Practice.Progress}/5", "המשך התרגול / {Training.Practice.Progress}/5", H), Action := 78}} + Entries
            View.ShowMenu(CoachLanguage("Your next move", "איך ממשיכים?", H), CoachLanguage("Damage dealt {Out} / taken {Inc}. Choose another round, a review or a focused lesson.", "נזק שהסבת: {Out} | שספגת: {Inc}. בחר סיבוב נוסף, ניתוח או שיעור ממוקד.", H), Entries)

    ShowProgress(Player : player):void =
        if (Training := Runtime.Players[Player], View := Views[Player]):
            H := Training.HebrewText
            Profile := Training.Profile
            Losses := Max(0, Profile.CompletedRounds - Profile.WonRounds)
            var WallTime : string = "—"
            var TripleTime : string = "—"
            var ChainTime : string = "—"
            if (Profile.BestWallRoute > 0.0):
                set WallTime = CoachElapsedText(Profile.BestWallRoute)
            if (Profile.BestTripleRoute > 0.0):
                set TripleTime = CoachElapsedText(Profile.BestTripleRoute)
            if (Profile.BestChainRoute > 0.0):
                set ChainTime = CoachElapsedText(Profile.BestChainRoute)
            var Entries : []coach_menu_entry = array{
                coach_menu_entry{Label := CoachLanguage("Continue my training plan", "המשך תוכנית האימון שלי", H), Action := 91},
                coach_menu_entry{Label := CoachLanguage("Continue my last lesson", "המשך מהשיעור האחרון", H), Action := 6},
                coach_menu_entry{Label := CoachLanguage("Choose a lesson", "בחירת שיעור", H), Action := 70},
                coach_menu_entry{Label := CoachLanguage("Personal training", "אימון אישי", H), Action := 0},
                coach_menu_entry{Label := CoachLanguage("Back", "חזרה", H), Action := 20}
            }
            if (Commerce.AllowsAdvancedFeatures(Player)?):
                set Entries += array{coach_menu_entry{Label := CoachLanguage("Recent personal rounds", "הקרבות האישיים האחרונים", H), Action := 61}}
            View.ShowMenu(CoachLanguage("Keep building your level", "המשך לבנות את הרמה שלך", H), CoachLanguage("Personal rounds: {Profile.CompletedRounds}\nWon {Profile.WonRounds} / Lost {Losses}\nPractice routes completed: {Profile.CompletedDrills}\nFive walls, best: {WallTime}\nTriple route, best: {TripleTime}\nLinked triples, best: {ChainTime}\nShort-opening exercises: {Profile.CompletedCoverSessions}\nAngle-change exercises: {Profile.CompletedAngleSessions}\nYour progress and coach preferences are saved for your next visit.", "קרבות אישיים: {Profile.CompletedRounds}\nניצחונות {Profile.WonRounds} / הפסדים {Losses}\nמסלולי תרגול שהושלמו: {Profile.CompletedDrills}\nחמישה קירות, שיא: {WallTime}\nמסלול טריפל, שיא: {TripleTime}\nטריפלים רצופים, שיא: {ChainTime}\nתרגולי פתיחות קצרות: {Profile.CompletedCoverSessions}\nתרגולי שינוי זוויות: {Profile.CompletedAngleSessions}\nההתקדמות והעדפות המאמן נשמרות לביקור הבא.", H), Entries)

    ShowRoundHistory(Player : player):void =
        if (Commerce.AllowsAdvancedFeatures(Player)?, Training := Runtime.Players[Player], View := Views[Player]):
            H := Training.HebrewText
            var English : string = "Result / Dealt / Taken / Active time\n"
            var Hebrew : string = "תוצאה / נזק שהסבת / שספגת / זמן קרב פעיל\n"
            for (Record : Training.Profile.RecentRounds):
                var EResult : string = "Lost"
                var HResult : string = "הפסד"
                if (Record.Won?):
                    set EResult = "Won"
                    set HResult = "ניצחון"
                Dealt := CoachNumber(Record.DamageDealt)
                Taken := CoachNumber(Record.DamageTaken)
                Duration := CoachElapsedText(Record.ActiveSeconds)
                set English += "\n{EResult} / {Dealt} / {Taken} / {Duration}"
                set Hebrew += "\n{HResult} / {Dealt} / {Taken} / {Duration}"
            if (Training.Profile.RecentRounds.Length = 0):
                set English += "\nComplete a personal round to start your history."
                set Hebrew += "\nהשלם קרב אישי כדי להתחיל את ההיסטוריה שלך."
            View.ShowMenu(CoachLanguage("Your last ten rounds", "עשרת הקרבות האחרונים שלך", H), CoachLanguage(English, Hebrew, H), array{
                coach_menu_entry{Label := CoachLanguage("Back to progress", "חזרה להתקדמות", H), Action := 60},
                coach_menu_entry{Label := CoachLanguage("Another personal round", "קרב אישי נוסף", H), Action := 0}
            })

    ShowLessonLibrary(Player : player):void =
        if (Training := Runtime.Players[Player], View := Views[Player]):
            View.ShowMenu(CoachLanguage("Choose your focus", "בחר את המיקוד שלך", Training.HebrewText), CoachLanguage("Practice one useful change at a time, then apply it in a fight.", "תרגל שינוי מועיל אחד בכל פעם, ואז יישם אותו בקרב.", Training.HebrewText), array{
                coach_menu_entry{Label := CoachLanguage("Protected openings", "פתיחות מוגנות", Training.HebrewText), Action := 71},
                coach_menu_entry{Label := CoachLanguage("Timing and angle changes", "שינוי תזמון וזוויות", Training.HebrewText), Action := 72},
                coach_menu_entry{Label := CoachLanguage("Edit, move and reset", "עריכה, תנועה ואיפוס", Training.HebrewText), Action := 73},
                coach_menu_entry{Label := CoachLanguage("Back", "חזרה", Training.HebrewText), Action := 20}
            })

    SaveCurrentTrainingPlan(Player : player, Replace : logic):void =
        if (Training := Runtime.Players[Player], Training.Phase = coach_phase.Review, View := Views[Player]):
            Plan := Training.Profile.TrainingPlan
            H := Training.HebrewText
            if (not Replace? and Plan.Stage > 0 and Plan.Stage < 4):
                View.ShowMenu(CoachLanguage("Keep your focus", "שמור על המיקוד שלך", H), CoachLanguage("You have an active plan. Continue it, or replace it with this round's recommendation.", "יש לך תוכנית פעילה. אפשר להמשיך אותה או להחליף אותה בהמלצה מהקרב הזה.", H), array{
                    coach_menu_entry{Label := CoachLanguage("Continue the saved plan", "המשך התוכנית השמורה", H), Action := 91},
                    coach_menu_entry{Label := CoachLanguage("Replace with this recommendation", "החלפה בהמלצה הזאת", H), Action := 96}
                })
                return
            Training.SaveTrainingPlan()
            ShowTrainingPlan(Player)

    ShowTrainingPlan(Player : player):void =
        if (Training := Runtime.Players[Player], View := Views[Player]):
            if (Training.Mode = coach_mode.Personal and Training.Phase = coach_phase.Preparing):
                EnterMode(Player, coach_mode.Hub)
            RoundFlow.Cancel(Training)
            PausePersonal(Player)
            Plan := Training.Profile.TrainingPlan
            H := Training.HebrewText
            if (Plan.Stage <= 0):
                View.ShowMenu(CoachLanguage("My training plan", "תוכנית האימון שלי", H), CoachLanguage("Finish a personal round, open its analysis, and save the recommendation you want to work on.", "סיים קרב אישי, פתח את הניתוח ושמור את ההמלצה שעליה תרצה לעבוד.", H), array{
                    coach_menu_entry{Label := CoachLanguage("Start a personal round", "התחלת קרב אישי", H), Action := 0},
                    coach_menu_entry{Label := CoachLanguage("Back", "חזרה", H), Action := 20}
                })
                return
            var Next : message = CoachLanguage("Study my lesson", "לימוד השיעור שלי", H)
            if (Plan.Stage = 2):
                set Next = CoachLanguage("Continue my exercise", "המשך התרגול שלי", H)
            else if (Plan.Stage = 3):
                set Next = CoachLanguage("Start my application round", "התחלת קרב היישום שלי", H)
            else if (Plan.Stage = 4):
                set Next = CoachLanguage("Another personal round", "קרב אישי נוסף", H)
            var Entries : []coach_menu_entry = array{coach_menu_entry{Label := Next, Action := 92}}
            if (Plan.Stage = 1):
                set Entries += array{coach_menu_entry{Label := CoachLanguage("Ready to practice", "מוכן לתרגול", H), Action := 93}}
            else:
                set Entries += array{coach_menu_entry{Label := CoachLanguage("Watch the lesson again", "צפייה חוזרת בשיעור", H), Action := 94}}
            set Entries += array{coach_menu_entry{Label := CoachLanguage("Back", "חזרה", H), Action := 20}}
            View.ShowMenu(CoachLanguage("My training plan", "תוכנית האימון שלי", H), CoachTrainingPlanText(Plan, H), Entries)

    ContinueTrainingPlan(Player : player):void =
        if (Training := Runtime.Players[Player]):
            Plan := Training.Profile.TrainingPlan
            if (Plan.Stage = 1):
                SelectLesson(Player, Plan.Lesson)
            else if (Plan.Stage = 2):
                StartPlanPractice(Player)
            else if (Plan.Stage = 3):
                StartPersonal(Player, ?PlanRevision := Plan.Revision, ?PlanApplication := true)
            else if (Plan.Stage = 4):
                StartPersonal(Player)
            else:
                ShowTrainingPlan(Player)

    StartPlanPractice(Player : player):void =
        if (Training := Runtime.Players[Player], Training.Profile.TrainingPlan.Stage = 1 or Training.Profile.TrainingPlan.Stage = 2):
            Training.PreparePlanPractice()
            Plan := Training.Profile.TrainingPlan
            StartPersonal(Player, ?ExerciseGoal := Plan.Lesson + 1, ?PlanRevision := Plan.Revision)

    ShowReviewMomentChoices(Player : player):void =
        if (Training := Runtime.Players[Player], Training.Phase = coach_phase.Review, View := Views[Player]):
            RoundFlow.Cancel(Training)
            H := Training.HebrewText
            set View.ReviewMomentChoices = array{}
            var Entries : []coach_menu_entry = array{}
            if (Latest := Training.History.LatestFrame()?):
                Timeline := Training.History.ActiveWindow(Latest.FightTime, 90.0, 0.0)
                if (First := Timeline[0]):
                    var Before : float = Latest.At + 0.01
                    # At most four recent anchors, separated so one damage
                    # burst does not fill the whole menu. No mistake ranking.
                    for (Choice := 0..3):
                        var Candidate : ?coach_moment = false
                        var CandidateAt : float = -1.0
                        for (Moment : Training.Moments, Moment.Kind = 2, Moment.Amount > 0.0, Moment.At >= First.At, Moment.At <= Latest.At, Moment.At < Before):
                            if (Moment.At > CandidateAt):
                                set Candidate = option{Moment}
                                set CandidateAt = Moment.At
                        if (Moment := Candidate?):
                            set View.ReviewMomentChoices += array{Moment}
                            Seconds := CoachElapsedText(Moment.FightTime)
                            Damage := CoachNumber(Moment.Amount)
                            set Entries += array{coach_menu_entry{Label := CoachLanguage("At {Seconds} / {Damage} damage", "בזמן {Seconds} / {Damage} נזק", H), Action := 110 + Choice}}
                            set Before = Moment.At - 0.75
            var Description : message = CoachLanguage("Choose a recorded hit to inspect spacing and timing and see the related practice suggestion.", "בחר פגיעה שנרשמה כדי לבחון מרחקים ותזמון ולקבל הצעת תרגול בהקשר שלה.", H)
            Focus := Training.History.ReviewFocus()
            if (Focus.HasDamageMoment?):
                set Entries += array{coach_menu_entry{Label := CoachLanguage("Largest recorded hit", "הפגיעה הגדולה שנשמרה", H), Action := 58}}
                if (View.ReviewMomentChoices.Length = 0):
                    set Description = CoachLanguage("No recent hit has position samples in the current timeline. You can return to the largest retained hit.", "לא נשמרו בציר הזמן הנוכחי דגימות מיקום של פגיעה אחרונה. אפשר לחזור לפגיעה הגדולה שנשמרה.", H)
            else:
                set Entries += array{coach_menu_entry{Label := CoachLanguage("View round data", "צפייה בנתוני הסיבוב", H), Action := 50}}
                set Description = CoachLanguage("No incoming damage moment was recorded. You can view the round data or choose a technique to practice.", "לא נרשם רגע שבו ספגת נזק. אפשר לצפות בנתוני הסיבוב או לבחור טכניקה לתרגול.", H)
            set Entries += array{coach_menu_entry{Label := CoachLanguage("Back to round review", "חזרה לסיכום הקרב", H), Action := 56}}
            View.ShowMenu(CoachLanguage("Choose a moment to understand", "בחר רגע שתרצה להבין", H), Description, Entries)

    ShowRecordedReview(Player : player, Restart : logic):void =
        if (Training := Runtime.Players[Player], Training.Phase = coach_phase.Review, View := Views[Player]):
            if (Restart?):
                Focus := CoachReviewFocus(Training)
                var At : float = Focus.FightTime
                if (not Focus.HasDamageMoment?, Latest := Training.History.LatestFrame()?):
                    set At = Latest.FightTime
                set View.ReplayFrames = Training.History.ActiveWindow(At, 3.0, 1.0)
                if (Focus.HasDamageMoment?):
                    set View.ReplayFrames = Training.History.RecordedFocusFrames()
                set View.ReplayIndex = 0
                set View.ReplayPlaying = false
            if (View.ReplayFrames.Length = 0):
                View.SetCaption(CoachLanguage("No position samples are available for this moment.", "אין דגימות מיקום זמינות לרגע הזה.", Training.HebrewText))
                return
            if (Frame := View.ReplayFrames[View.ReplayIndex]):
                set View.ReplayClock = Frame.At
            set View.ReplaySerial += 1
            H := Training.HebrewText
            View.ShowMenu(CoachLanguage("Study one exchange", "בחן חילופי ירי אחדים", H), CoachLanguage("Blue: you. Orange: coach. Dots indicate movement and view direction. Positions and health were sampled during the fight. Use this view to compare spacing and timing.", "כחול: אתה. כתום: המאמן. הנקודות מציגות תנועה וכיוון הסתכלות. המיקומים והבריאות נדגמו בקרב. השווה את המרחקים והתזמון.", H), array{
                coach_menu_entry{Label := CoachLanguage("Play / pause", "הפעלה / עצירה", H), Action := 53},
                coach_menu_entry{Label := CoachLanguage("Back half a second", "חצי שנייה אחורה", H), Action := 51},
                coach_menu_entry{Label := CoachLanguage("Forward half a second", "חצי שנייה קדימה", H), Action := 52},
                coach_menu_entry{Label := CoachLanguage("Slower / {View.ReplaySpeed}x", "לאט יותר / {View.ReplaySpeed}x", H), Action := 54},
                coach_menu_entry{Label := CoachLanguage("Faster", "מהר יותר", H), Action := 55},
                coach_menu_entry{Label := CoachLanguage("Practice the recommended lesson", "תרגול השיעור המומלץ", H), Action := 79},
                coach_menu_entry{Label := CoachLanguage("Choose another moment", "בחירת רגע אחר", H), Action := 59},
                coach_menu_entry{Label := CoachLanguage("Back to round review", "חזרה לסיכום הקרב", H), Action := 56}
            }, ?LessonPanel := true)
            set View.ReplayOpen = true
            View.ShowRecordedMoment(Training.StartedAt, H)
            spawn { RunRecordedReview(Training, View, View.ReplaySerial) }

    ShowMomentAnalysis(Player : player):void =
        if (Training := Runtime.Players[Player], Training.Phase = coach_phase.Review, View := Views[Player]):
            H := Training.HebrewText
            Recommendation := CoachRecommendLesson(Training)
            var PracticeAction : int = 76
            if (Recommendation.Lesson = 1):
                set PracticeAction = 77
            View.ShowMenu(CoachLanguage("One moment. One useful change.", "רגע אחד. שינוי מועיל אחד.", H), CoachReviewEvidence(Training), array{
                coach_menu_entry{Label := CoachLanguage("Watch the recommended lesson", "צפייה בשיעור המומלץ", H), Action := 79},
                coach_menu_entry{Label := CoachLanguage("Save this as my training plan", "שמירה כתוכנית האימון שלי", H), Action := 90},
                coach_menu_entry{Label := CoachLanguage("Try the focused fight exercise", "תרגול ממוקד בקרב", H), Action := PracticeAction},
                coach_menu_entry{Label := CoachLanguage("Inspect recorded positions", "בחינת דגימות המיקום", H), Action := 75},
                coach_menu_entry{Label := CoachLanguage("Choose another moment", "בחירת רגע אחר", H), Action := 59},
                coach_menu_entry{Label := CoachLanguage("Choose another technique", "בחירת טכניקה אחרת", H), Action := 70},
                coach_menu_entry{Label := CoachLanguage("Back to round review", "חזרה לסיכום הקרב", H), Action := 56}
            })
            if (Voice := Training.VoiceLink?):
                Voice.Review()

    RunRecordedReview(Training : coach_training_session, View : coach_player_view, Serial : int)<suspends>:void =
        var PreviousAt : float = GetSimulationElapsedTime()
        loop:
            if (Ending? or Training.Closed? or not View.ReplayOpen? or View.ReplaySerial <> Serial or Training.Phase <> coach_phase.Review):
                return
            Now := GetSimulationElapsedTime()
            if (View.ReplayPlaying?):
                set View.ReplayClock += Clamp(Now - PreviousAt, 0.0, 0.3) * View.ReplaySpeed
                if (Current := View.ReplayFrames[View.ReplayIndex], Next := View.ReplayFrames[View.ReplayIndex + 1], Next.At - Current.At > 0.4, View.ReplayClock > Current.At + 0.1):
                    set View.ReplayClock = Next.At
                var Changed : logic = false
                loop:
                    if (Next := View.ReplayFrames[View.ReplayIndex + 1], Next.At <= View.ReplayClock):
                        set View.ReplayIndex += 1
                        set Changed = true
                    else:
                        break
                if (View.ReplayIndex >= View.ReplayFrames.Length - 1):
                    set View.ReplayPlaying = false
                if (Changed?):
                    View.ShowRecordedMoment(Training.StartedAt, Training.HebrewText)
            set PreviousAt = Now
            Sleep(0.1)

    ShowCourseResult(Player : player, Kind : coach_course_kind, Summary : message, ?FromLesson : logic = false):void =
        if (Training := Runtime.Players[Player], View := Views[Player]):
            H := Training.HebrewText
            var Retry : int = 40
            if (Kind = coach_course_kind.TripleSequence):
                set Retry = 41
            else if (Kind = coach_course_kind.TripleChain):
                set Retry = 43
            var Entries : []coach_menu_entry = array{
                coach_menu_entry{Label := CoachLanguage("Try the same route again", "חזרה על אותו מסלול", H), Action := Retry},
                coach_menu_entry{Label := CoachLanguage("Choose another route", "בחירת מסלול אחר", H), Action := 42},
                coach_menu_entry{Label := CoachLanguage("Back to lobby", "חזרה ללובי", H), Action := 7}
            }
            if (FromLesson? and Training.Phase = coach_phase.Lesson):
                set Retry = 44
                if (Kind = coach_course_kind.TripleSequence):
                    set Retry = 45
                else if (Kind = coach_course_kind.TripleChain):
                    set Retry = 46
                set Entries = array{
                    coach_menu_entry{Label := CoachLanguage("Repeat this lesson's route", "חזרה על מסלול השיעור", H), Action := Retry},
                    coach_menu_entry{Label := CoachLanguage("Return to the lesson", "חזרה לשיעור", H), Action := 47}
                }
                if (Kind = coach_course_kind.TripleSequence):
                    set Entries += array{coach_menu_entry{Label := CoachLanguage("Next: three linked triple edits", "השלב הבא: שלוש עליות טריפל", H), Action := 46}}
                if (Training.Mode = coach_mode.Personal, Training.LessonFromFight?, Rival := Opponent?, Rival.IsActive[]):
                    set Entries += array{coach_menu_entry{Label := CoachLanguage("Resume the paused fight", "המשך הקרב המושהה", H), Action := 5}}
                set Entries += array{coach_menu_entry{Label := CoachLanguage("Return to the academy", "חזרה לאקדמיה", H), Action := 7}}
            View.ShowMenu(CoachLanguage("Your practice result", "תוצאת התרגול שלך", H), Summary, Entries)

    ShowEditPractice(Player : player):void =
        if (Training := Runtime.Players[Player], View := Views[Player]):
            H := Training.HebrewText
            View.ShowMenu(CoachLanguage("Make every edit count", "תן משמעות לכל עריכה", H), CoachLanguage("Practice clean openings and resets. The timer starts when you move through the start line; it measures the route, not individual edit accuracy.", "תרגל פתיחות נקיות ואיפוסים. השעון מתחיל בחציית קו הזינוק ומודד את המסלול, לא את הדיוק של כל עריכה.", H), array{
                coach_menu_entry{Label := CoachLanguage("Five-wall precision route", "מסלול דיוק בחמישה קירות", H), Action := 40},
                coach_menu_entry{Label := CoachLanguage("Floor, cone and wall sequence", "רצף רצפה, גג וקיר", H), Action := 41},
                coach_menu_entry{Label := CoachLanguage("Advanced: three linked triple edits", "מתקדם: שלוש עליות טריפל רצופות", H), Action := 43},
                coach_menu_entry{Label := CoachLanguage("Watch a focused lesson", "צפייה בשיעור ממוקד", H), Action := 6},
                coach_menu_entry{Label := CoachLanguage("Practice freely", "תרגול חופשי", H), Action := 31},
                coach_menu_entry{Label := CoachLanguage("Return to the academy", "חזרה לאקדמיה", H), Action := 7}
            })

    ShowSettings(Player : player):void =
        if (Training := Runtime.Players[Player], View := Views[Player]):
            H := Training.HebrewText
            var Personality : string = "Supportive"
            if (Training.Personality = coach_personality.Direct):
                set Personality = "Direct"
            else if (Training.Personality = coach_personality.Analytical):
                set Personality = "Analytical"
            var Timing : string = "During and after"
            if (Training.Timing = coach_timing.AfterOnly):
                set Timing = "After the round"
            var Voice : string = "On"
            if (not Training.VoiceEnabled?):
                set Voice = "Off"
            if (H?):
                set Personality = "תומך"
                if (Training.Personality = coach_personality.Direct):
                    set Personality = "ישיר"
                else if (Training.Personality = coach_personality.Analytical):
                    set Personality = "אנליטי"
                set Timing = "תוך כדי ובסיום"
                if (Training.Timing = coach_timing.AfterOnly):
                    set Timing = "בסיום הקרב"
                set Voice = "פעיל"
                if (not Training.VoiceEnabled?):
                    set Voice = "כבוי"
            var Style : string = "Balanced"
            if (Training.Style = coach_style.Pressure):
                set Style = "Pressure"
            else if (Training.Style = coach_style.Patient):
                set Style = "Patient"
            if (H?):
                set Style = "מאוזן"
                if (Training.Style = coach_style.Pressure):
                    set Style = "לוחץ"
                else if (Training.Style = coach_style.Patient):
                    set Style = "סבלני"
            View.ShowMenu(CoachLanguage("Coach preferences", "העדפות המאמן", H), CoachLanguage("Choose how you want to train. Your preferences are saved with your profile.", "בחר איך תרצה להתאמן. ההעדפות נשמרות בפרופיל שלך.", H), array{
                coach_menu_entry{Label := CoachLanguage("Personality: {Personality}", "אופי: {Personality}", H), Action := 10},
                coach_menu_entry{Label := CoachLanguage("Coaching: {Timing}", "הדרכה: {Timing}", H), Action := 11},
                coach_menu_entry{Label := CoachLanguage("Text: English", "טקסט: עברית", H), Action := 12},
                coach_menu_entry{Label := CoachLanguage("Voice: {Voice}", "קול: {Voice}", H), Action := 13},
                coach_menu_entry{Label := CoachLanguage("Style: {Style}", "סגנון: {Style}", H), Action := 14},
                coach_menu_entry{Label := CoachLanguage("Back", "חזרה", H), Action := 20}
            })

    UpdateSettings(Player : player, Action : int):void =
        if (Training := Runtime.Players[Player]):
            if (Action = 10):
                if (Training.Personality = coach_personality.Supportive):
                    set Training.Personality = coach_personality.Direct
                else if (Training.Personality = coach_personality.Direct):
                    set Training.Personality = coach_personality.Analytical
                else:
                    set Training.Personality = coach_personality.Supportive
            else if (Action = 11):
                if (Training.Timing = coach_timing.AfterOnly):
                    set Training.Timing = coach_timing.DuringAndAfter
                else:
                    set Training.Timing = coach_timing.AfterOnly
            else if (Action = 12):
                if (Training.HebrewText?):
                    set Training.HebrewText = false
                else:
                    set Training.HebrewText = true
            else if (Action = 13):
                if (Training.VoiceEnabled?):
                    set Training.VoiceEnabled = false
                else:
                    set Training.VoiceEnabled = true
            else if (Action = 14):
                if (Training.Style = coach_style.Balanced):
                    set Training.Style = coach_style.Pressure
                else if (Training.Style = coach_style.Pressure):
                    set Training.Style = coach_style.Patient
                else:
                    set Training.Style = coach_style.Balanced
            else if (Action = 15):
                set Training.LessonSpeed = Max(0.25, Training.LessonSpeed - 0.25)
            else if (Action = 16):
                set Training.LessonSpeed = Min(2.0, Training.LessonSpeed + 0.25)
            Training.SavePreferences()
            if (Voice := Training.VoiceLink?):
                Voice.ApplyPreferences()
            if (Action >= 15):
                ShowLesson(Player)
            else:
                ShowSettings(Player)

    SelectLesson(Player : player, Lesson : int):void =
        if (Training := Runtime.Players[Player]):
            set Training.LessonIndex = Clamp(Lesson, 0, 2)
            set Training.LessonStep = 0
            set Training.LessonPlaying = true
            set Training.LessonProgress = 0.0
            set Training.LessonSeek = true
            if (Training.Phase = coach_phase.Lesson):
                set Training.LessonSerial += 1
                spawn { RunLesson(Training, Training.LessonSerial) }
            Training.SavePreferences()
            ShowLesson(Player)

    ShowLesson(Player : player):void =
        if (Training := Runtime.Players[Player], View := Views[Player]):
            if (Training.Mode = coach_mode.Personal and Training.Phase = coach_phase.Preparing):
                EnterMode(Player, coach_mode.Hub)
            if (Training.Mode = coach_mode.Duel):
                EnterMode(Player, coach_mode.Hub)
            PausePersonal(Player)
            Course.Release(Player)
            if (Training.Phase <> coach_phase.Lesson):
                set Training.LessonFromFight = false
                if (Training.Mode = coach_mode.Personal and Training.Phase = coach_phase.Fighting):
                    set Training.LessonFromFight = true
                if (Training.Mode = coach_mode.EditTraining):
                    Course.Release(Player)
                    MovePlayer(Player, CoachCourseStaging())
                set Training.LessonStep = 0
                set Training.LessonPlaying = true
                set Training.LessonProgress = 0.0
                set Training.LessonSeek = true
                set Training.LessonSerial += 1
                if (Character := Player.GetFortCharacter[]):
                    set Training.LessonReturn = option{Character.GetTransform()}
                set Training.Phase = coach_phase.Lesson
                spawn { RunLesson(Training, Training.LessonSerial) }
            set Training.Phase = coach_phase.Lesson
            Acquired := AcquireLessonStation(Player)
            if (not Acquired?):
                set Training.LessonPlaying = false
                View.SetCaption(CoachLanguage("The teaching bay is preparing. Press Play to try again.", "עמדת הלימוד מתכוננת. לחץ הפעלה כדי לנסות שוב.", Training.HebrewText))
            H := Training.HebrewText
            var Playback : message = CoachLanguage("Play demonstration", "הפעל הדגמה", H)
            if (Training.LessonPlaying?):
                set Playback = CoachLanguage("Pause demonstration", "עצור הדגמה", H)
            var Entries : []coach_menu_entry = array{
                coach_menu_entry{Label := Playback, Action := 23},
                coach_menu_entry{Label := CoachLanguage("Previous step", "השלב הקודם", H), Action := 21},
                coach_menu_entry{Label := CoachLanguage("Next step", "השלב הבא", H), Action := 22},
                coach_menu_entry{Label := CoachLanguage("Slower / {Training.LessonSpeed}x", "לאט יותר / {Training.LessonSpeed}x", H), Action := 15},
                coach_menu_entry{Label := CoachLanguage("Faster", "מהר יותר", H), Action := 16}
            }
            Plan := Training.Profile.TrainingPlan
            if (Plan.Stage = 1 or Plan.Stage = 2, Plan.Lesson = Training.LessonIndex):
                set Entries = array{coach_menu_entry{Label := CoachLanguage("Continue my plan: practice", "המשך התוכנית שלי: תרגול", H), Action := 93}} + Entries
            if (Training.LessonIndex = 0):
                set Entries += array{coach_menu_entry{Label := CoachLanguage("Practice short openings in a fight", "תרגול פתיחות קצרות בקרב", H), Action := 76}}
            else if (Training.LessonIndex = 1):
                set Entries += array{coach_menu_entry{Label := CoachLanguage("Practice angle changes in a fight", "תרגול שינוי זוויות בקרב", H), Action := 77}}
            else if (Training.LessonIndex = 2):
                set Entries += array{coach_menu_entry{Label := CoachLanguage("Advanced: three linked triple edits", "מתקדם: שלוש עליות טריפל רצופות", H), Action := 46}}
            if (Training.Mode = coach_mode.Personal, Training.LessonFromFight?, LiveOpponent := Opponent?, LiveOpponent.IsActive[]):
                set Entries += array{coach_menu_entry{Label := CoachLanguage("Resume paused fight", "המשך הקרב שנעצר", H), Action := 5}}
            set Entries += array{
                coach_menu_entry{Label := CoachLanguage("Toggle technique diagram", "הצגה או הסתרה של התרשים", H), Action := 24},
                coach_menu_entry{Label := CoachLanguage("Try the edit course", "נסה עכשיו במסלול העריכות", H), Action := 74},
                coach_menu_entry{Label := CoachLanguage("Choose another technique", "בחירת טכניקה אחרת", H), Action := 70},
                coach_menu_entry{Label := CoachLanguage("Apply it in a new round", "יישום בסיבוב חדש", H), Action := 0},
                coach_menu_entry{Label := CoachLanguage("Return to the academy", "חזרה לאקדמיה", H), Action := 7}
            }
            View.ShowMenu(CoachLanguage("One change. Better fights.", "שינוי אחד. קרבות טובים יותר.", H), CoachLessonText(Training.LessonIndex, Training.LessonStep, H), Entries, ?LessonPanel := true)
            set View.LessonPanelVisible = true
            if (Training.LessonDiagram?):
                View.ShowLessonPlan(Training.LessonIndex, Training.LessonStep, H)
            PresentLessonFrame(Player)

    AcquireLessonStation(Player : player):logic =
        if (Existing := LessonStations[Player], Owner := Existing.CurrentOwner?, Owner = Player):
            ExistingPosition := Existing.Acquire(Player)
            if (ExistingPosition?):
                return true
            return false
        for (Station : array{DemoOne, DemoTwo}):
            Position := Station.Acquire(Player)
            if (Location := Position?, set LessonStations[Player] = Station):
                MovePlayer(Player, Location)
                return true
        return false

    ReleaseLessonStation(Player : player):void =
        if (Station := LessonStations[Player]):
            Station.Release(Player)
        var Remaining : [player]coach_demo_device = map{}
        for (Other -> Station : LessonStations, Other <> Player):
            if (set Remaining[Other] = Station) {}
        set LessonStations = Remaining

    PresentLessonFrame(Player : player):void =
        if (Training := Runtime.Players[Player], Station := LessonStations[Player], View := Views[Player]):
            Active := logic{Training.LessonPlaying? and View.LessonPanelVisible?}
            Station.Present(Player, Training.LessonIndex, Training.LessonStep, Active, Training.LessonSpeed, Training.LessonProgress / CoachLessonDuration(Training.LessonIndex, Training.LessonStep), ?Seek := Training.LessonSeek)
            set Training.LessonSeek = false

    StartFocusedPractice(Player : player, GoalKind : int):void =
        StartPersonal(Player, ?ExerciseGoal := Clamp(GoalKind, 1, 2))

    ShowFocusedSummary(Player : player):void =
        if (Training := Runtime.ActiveTrainee?, Training.Owner = Player, Training.Practice.Completed?, not Training.Practice.CompletionShown?, View := Views[Player]):
            set Training.Practice.CompletionShown = true
            Training.RecordFocusedSession(Training.Practice.Goal)
            PausePersonal(Player)
            H := Training.HebrewText
            var Action : int = 76
            if (Training.Practice.Goal = 2):
                set Action = 77
            var Entries : []coach_menu_entry = array{
                coach_menu_entry{Label := CoachLanguage("Repeat the focused exercise", "חזרה על התרגול הממוקד", H), Action := Action},
                coach_menu_entry{Label := CoachLanguage("Choose another technique", "בחירת טכניקה אחרת", H), Action := 70},
                coach_menu_entry{Label := CoachLanguage("Return to the academy", "חזרה לאקדמיה", H), Action := 7}
            }
            if (Training.Profile.TrainingPlan.Stage = 3):
                set Entries = array{coach_menu_entry{Label := CoachLanguage("Next step in my plan", "השלב הבא בתוכנית שלי", H), Action := 91}} + Entries
            if (Training.Phase = coach_phase.Fighting, Rival := Opponent?, Rival.IsActive[]):
                set Entries = array{coach_menu_entry{Label := CoachLanguage("Continue this fight", "המשך הקרב הזה", H), Action := 5}} + Entries
            else:
                set Entries = array{coach_menu_entry{Label := CoachLanguage("Apply it in another fight", "יישום בקרב נוסף", H), Action := 0}} + Entries
            View.ShowMenu(CoachLanguage("Five controlled exchanges", "חמישה חילופים מבוקרים", H), CoachLanguage("Five qualifying exchanges were recorded. Each ended with a return out of the opponent's sight or elimination within the exercise's sight-time target. This measures sight intervals and damage, not edit accuracy or overall mastery.", "נרשמו חמישה חילופים תקפים. כל אחד הסתיים בחזרה מחוץ לטווח הראייה או בחיסול בתוך יעד הזמן של התרגול. נמדדים חלונות ראייה ונזק, לא דיוק עריכות או שליטה כוללת.", H), Entries)

    TryLessonCourse(Player : player, ?SelectedKind : ?coach_course_kind = false):void =
        if (Training := Runtime.Players[Player], Training.Phase = coach_phase.Lesson):
            var Kind : coach_course_kind = coach_course_kind.PrecisionWalls
            if (Training.LessonIndex = 2):
                set Kind = coach_course_kind.TripleSequence
            if (Selected := SelectedKind?):
                set Kind = Selected
            Course.Start(Player, Kind, ?ReturnAfter := true)
            if (Course.IsActiveFor(Player)?):
                set Training.LessonCourseActive = true
                set Training.LessonPlaying = false
                Structures.EndDemo(Player)
                ReleaseLessonStation(Player)
            else:
                ShowLesson(Player)

    RunLesson(Training : coach_training_session, Serial : int)<suspends>:void =
        var PreviousStep : int = Training.LessonStep
        loop:
            if (Ending? or Training.Closed? or Serial <> Training.LessonSerial or Training.Phase <> coach_phase.Lesson):
                return
            if (Training.LessonStep <> PreviousStep):
                set Training.LessonProgress = 0.0
                set PreviousStep = Training.LessonStep
            if (Training.LessonPlaying?, View := Views[Training.Owner], View.LessonPanelVisible?):
                set Training.LessonProgress += 0.05 * Clamp(Training.LessonSpeed, 0.25, 2.0)
                Duration := CoachLessonDuration(Training.LessonIndex, Training.LessonStep)
                if (Training.LessonProgress >= Duration, Station := LessonStations[Training.Owner], Station.MotionReady?):
                    set Training.LessonProgress = 0.0
                    set Training.LessonStep += 1
                    if (Training.LessonStep >= CoachLessonSteps(Training.LessonIndex)):
                        set Training.LessonStep = 0
                    set PreviousStep = Training.LessonStep
                    View.UpdateDescription(CoachLessonText(Training.LessonIndex, Training.LessonStep, Training.HebrewText))
                    if (Training.LessonDiagram?):
                        View.ShowLessonPlan(Training.LessonIndex, Training.LessonStep, Training.HebrewText)
                else if (Training.LessonProgress > Duration + 4.0):
                    set Training.LessonPlaying = false
                    View.SetCaption(CoachLanguage("The demonstrator paused. Choose a step and press Play to retry.", "המדגים נעצר. בחר שלב ולחץ הפעלה כדי לנסות שוב.", Training.HebrewText))
            PresentLessonFrame(Training.Owner)
            Sleep(0.05)

    EndLesson(Player : player):void =
        ReleaseLessonStation(Player)
        Structures.EndDemo(Player)
        if (Training := Runtime.Players[Player]):
            set Training.LessonSerial += 1
            set Training.LessonPlaying = false
            set Training.LessonFromFight = false
            if (Pose := Training.LessonReturn?, Character := Player.GetFortCharacter[]):
                if (Character.TeleportTo[Pose.Translation, Pose.Rotation]) {}
            set Training.LessonReturn = false

    ResetArea(Player : player, Mode : coach_mode):void =
        if (not ArenaAccess.Holds(Player, Mode)?):
            return
        if (Mode = coach_mode.EditTraining):
            Course.Start(Player, Course.CurrentKind)
            return
        if (ArenaControls.Configured?):
            ArenaControls.ResetOwned(Player, Mode)
            return
        var Index : int = 0
        var Device : explosive_device = PersonalReset
        var Upper : explosive_device = PersonalResetUpper
        if (Mode = coach_mode.Duel):
            set Index = 1
            set Device = DuelReset
            set Upper = DuelResetUpper
        else if (Mode = coach_mode.FreeBuild):
            set Index = 2
            set Device = FreeReset
            set Upper = FreeResetUpper
        else if (Mode = coach_mode.EditTraining):
            set Index = 3
            set Device = EditReset
            set Upper = EditResetUpper
        else if (Mode <> coach_mode.Personal):
            return
        if (Busy := ResetBusy[Index], Busy?):
            return
        if (set ResetBusy[Index] = true):
            Device.Explode(Player)
            Upper.Explode(Player)
            spawn { RearmReset(Device, Upper, Index) }

    RearmReset(Device : explosive_device, Upper : explosive_device, Index : int)<suspends>:void =
        Sleep(1.1)
        if (not Ending?):
            Device.Reset()
            Upper.Reset()
            if (set ResetBusy[Index] = false) {}

    LeaveDuel(Player : player):void =
        if (Leaving := Runtime.Players[Player], Leaving.Mode = coach_mode.Duel):
            DuelFlow.Leave(Self, option{Player})

    DuelResetReady()<transacts>:logic =
        if (ArenaControls.Configured?):
            if (Busy := ArenaControls.Busy[coach_mode.Duel], Busy?):
                return false
        else if (Busy := ResetBusy[1], Busy?):
            return false
        return true

    PersonalResetReady()<transacts>:logic =
        if (ArenaControls.Configured?):
            if (Busy := ArenaControls.Busy[coach_mode.Personal], Busy?):
                return false
        else if (Busy := ResetBusy[0], Busy?):
            return false
        return true

    FinishDuel(Player : player, Killer : ?fort_character):void =
        DuelFlow.Finish(Self, Player, Killer)

coach_player_combat_sink := class:
    Owner : coach_portal_device
    Player : player
    Character : fort_character

    OnDamage(Result : damage_result):void =
        if:
            Current := Player.GetFortCharacter[]
            Current = Character
            Training := Owner.Runtime.ActiveTrainee?
            Training.Owner = Player
            Guard := Owner.Opponent?
            GuardAgent := Guard.GetAgent[]
            Instigator := Result.Instigator?
            Instigator.GetInstigatorAgent[] = GuardAgent
        then:
            Owner.AppendCombatSnapshot(Training)
            Training.RecordDamage(false, Result.Amount, GetSimulationElapsedTime(), Owner.VisibilityFor(Player))

    OnEliminated(Result : elimination_result):void =
        if (Current := Player.GetFortCharacter[], Current <> Character):
            return
        if (Result.EliminatedCharacter = Character):
            Owner.MarkPlayerBodyInactive(Player, Character)
        if (Result.EliminatedCharacter = Character, Training := Owner.Runtime.ActiveTrainee?, Training.Owner = Player):
            if (Killer := Result.EliminatingCharacter?, Rival := Owner.Opponent?, Killer = Rival):
                Owner.FinishPersonal(false)
            else:
                Owner.InterruptPersonal()
        if (Result.EliminatedCharacter = Character):
            Owner.FinishDuel(Player, Result.EliminatingCharacter)

coach_opponent_combat_sink := class:
    Owner : coach_portal_device
    Character : fort_character
    Ticket : int

    OnDamage(Result : damage_result):void =
        if:
            Ticket = Owner.EncounterSerial
            Current := Owner.Opponent?
            Current = Character
            Training := Owner.Runtime.ActiveTrainee?
            Instigator := Result.Instigator?
            Instigator.GetInstigatorAgent[] = Training.Owner
        then:
            Owner.AppendCombatSnapshot(Training)
            Training.RecordDamage(true, Result.Amount, GetSimulationElapsedTime(), Owner.VisibilityFor(Training.Owner))

    OnEliminated(Result : elimination_result):void =
        if (Result.EliminatedCharacter = Character, Ticket = Owner.EncounterSerial, Current := Owner.Opponent?, Current = Character):
            if (Training := Owner.Runtime.ActiveTrainee?, Training.Phase = coach_phase.Fighting, not Training.Paused?, Killer := Result.EliminatingCharacter?, Agent := Killer.GetAgent[], Agent = Training.Owner):
                Training.Practice.FinishWithElimination(GetSimulationElapsedTime())
                Owner.FinishPersonal(true)
            else if (Training := Owner.Runtime.ActiveTrainee?, Training.Phase = coach_phase.Fighting):
                Owner.InterruptPersonal()
