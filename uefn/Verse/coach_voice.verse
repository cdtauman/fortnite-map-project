using { /Fortnite.com/AI }
using { /Fortnite.com/Characters }
using { /Verse.org/AgentGroup }
using { /Verse.org/Chat }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Conversations }
using { /UnrealEngine.com/Temporary/Diagnostics }

coach_voice_member_info := class(has_voice_member_info) {}

coach_voice_action := enum:
    NoChange
    ChangeStyle
    OpenLesson
    ResumeFight

coach_voice_command := struct:
    Action : coach_voice_action = coach_voice_action.NoChange
    Style : coach_style = coach_style.Balanced
    LessonIndex : int = 0

CoachPersonaMessage(Training : coach_training_session):message =
    var Tone : string = "Warm, encouraging and calm."
    if (Training.Personality = coach_personality.Direct):
        set Tone = "Direct, concise and respectful."
    else if (Training.Personality = coach_personality.Analytical):
        set Tone = "Precise, analytical and easy to understand."
    return CoachMessage("You are ProCoach, a Fortnite personal training coach. {Tone} Speak English. Give one useful action at a time. Use only measured gameplay facts supplied by the game. Never invent an edit, headshot, accuracy, build ownership or replay. When a fact is unknown, explain a general technique without saying the player made that mistake. Do not claim to watch footage. Stay within Fortnite training. The player can pause for a lesson and choose whether you speak during the fight or after it. Do not promise ranks or competitive results.")

coach_voice_link := class:
    Training : coach_training_session
    Root : entity
    Speaker : agent
    Persona : persona_component
    View : coach_player_view
    Group : agent_group(coach_voice_member_info) = agent_group(coach_voice_member_info){}
    var Channel : ?voice_channel(coach_voice_member_info) = false
    var Subscriptions : []cancelable = array{}
    var Speech : ?cancelable = false
    var LastPromptAt : float = -100.0
    var Closed : logic = false
    var CommandsUntil : float = -100.0

    Connect():void =
        Persona.GetAISession().ClearHistory()
        PlayerAdded := Group.AddMember(Training.Owner, coach_voice_member_info{})
        SpeakerAdded := Group.AddMember(Speaker, coach_voice_member_info{})
        if (not PlayerAdded.GetSuccess[] or not SpeakerAdded.GetSuccess[]):
            Print("PCL|voice|membership_unconfirmed", ?Duration := 0.0)
            return
        NewChannel := voice_channel(coach_voice_member_info){Name := CoachLanguage("Personal coach", "מאמן אישי", Training.HebrewText), Group := Group}
        Registered := Root.AddChatChannel(NewChannel)
        if (Registered.GetSuccess[]):
            set Channel = option{NewChannel}
            set Persona.PromptInterruptionRule = persona_interruption_rule.InterruptOnPromptStart
            ApplyPreferences()
            set Subscriptions = array{
                Persona.StartSayEvent.Subscribe(OnSpeechStarted),
                Persona.CommitSayEvent.Subscribe(OnSpeechCommitted),
                Persona.PromptFailureEvent.Subscribe(OnPromptFailure),
                Persona.StopHearEvent.Subscribe(OnPlayerPromptFinished),
                Persona.GetAISession().RegisterAction(prompt_binding_definition{
                    Name := CoachMessage("Change personal training settings"),
                    Description := CoachMessage("Use only when the player explicitly requests a different opponent style, a lesson, or resuming the paused fight. Never act on hypothetical advice or a game-generated coaching prompt. Styles: Balanced, Pressure, Patient. LessonIndex: 0 protected openings, 1 timing and angles, 2 edit/move/reset. Otherwise emit NoChange.")
                }, false, coach_voice_command, OnVoiceCommand)
            }
            Print("PCL|voice|channel_registered", ?Duration := 0.0)
        else:
            Print("PCL|voice|channel_registration_unconfirmed", ?Duration := 0.0)

    ApplyPreferences():void =
        Personality := CoachPersonaMessage(Training)
        if (Persona.SetPersonality[Personality]) {}
        if (Persona.SetVoice[terns_voice{}]) {}
        if (Current := Channel?):
            if (Training.VoiceEnabled?):
                Added := Group.AddMember(Training.Owner, coach_voice_member_info{})
                Training.Owner.SetConversationTarget(Persona, Current)
                Current.Enable()
            else:
                StopSpeech()
                Removed := Group.RemoveMember(Training.Owner)
                if (Training.Owner.IsActive[], Target := Training.Owner.GetConversationTarget[], Target(0) = Persona):
                    Training.Owner.ClearConversationTarget()

    Say(Instructions : message, Force : logic):void =
        if (Closed? or Training.Closed? or not Training.VoiceEnabled?):
            return
        Now := GetSimulationElapsedTime()
        if (not Force? and Now - LastPromptAt < 18.0):
            return
        if (Force? and Now - LastPromptAt < 1.0):
            return
        set LastPromptAt = Now
        if (Current := Channel?, Persona.PromptToTalk[Instructions, Current]):
            return
        else:
            Print("PCL|voice|prompt_unconfirmed", ?Duration := 0.0)

    RoundResult(Won : logic):void =
        Outgoing := CoachNumber(Training.OutgoingDamage)
        Incoming := CoachNumber(Training.IncomingDamage)
        var Result : string = "Round lost."
        if (Won?):
            set Result = "Round won."
        Say(CoachMessage("Say only this short factual result in English: {Result} Damage dealt {Outgoing}, taken {Incoming}. No advice, invented terrain, technique diagnosis or extra sentence."), true)

    Review():void =
        Outgoing := CoachNumber(Training.OutgoingDamage)
        Incoming := CoachNumber(Training.IncomingDamage)
        Focus := CoachReviewFocus(Training)
        At := CoachNumber(Focus.FightTime)
        Amount := CoachNumber(Focus.Damage)
        Context := CoachReviewContext(Training)
        var PositionFacts : string = "No position sample is available for this event."
        if (Context.HasPositionSample?):
            Range := CoachNumber(Context.RangeCm / 100.0)
            Height := CoachNumber(Context.OpponentHeightAdvantage / 100.0)
            Exposure := CoachElapsedText(Context.VisibleRun)
            set PositionFacts = "Near-event samples: distance about {Range} meters; opponent minus player height about {Height} meters; last consecutive observed sight interval {Exposure}. These are sampled facts, not proof of an edit error or causation."
        Recommendation := CoachRecommendationSummary(Training, false)
        Say(CoachMessage("The player requested analysis. Measured player damage dealt: {Outgoing}. Damage taken from the opponent: {Incoming}. Largest recorded incoming damage event: {Amount}, around {At} active seconds; zero means none recorded. {PositionFacts} Agreed recommendation: {Recommendation} Review in the selected coach personality. Use the agreed focus; do not choose a different lesson. Do not invent an edit, a shot count, or a cause. Use English, under thirty words."), true)

    StopSpeech():void =
        if (Current := Speech?):
            Current.Cancel()
        set Speech = false

    OnSpeechStarted(Event : tuple(?agent, cancelable)):void =
        if (Closed? or not Training.VoiceEnabled?):
            Event(1).Cancel()
        else if (Training.Timing = coach_timing.AfterOnly, Training.Phase = coach_phase.Fighting, not Event(0)?):
            Event(1).Cancel()
        else:
            set Speech = option{Event(1)}

    OnSpeechCommitted(Event : tuple(?agent, message)):void =
        if (not Closed?, Training.VoiceEnabled?):
            if (Training.HebrewText?):
                # Localized coaching context, explicitly distinct from the English transcript.
                if (Training.Phase = coach_phase.Review):
                    if (Training.LastRoundInterrupted?):
                        View.SetCaption(CoachMessage("הסיבוב נקטע. לא נרשם ניצחון או הפסד."))
                    else:
                        Outgoing := CoachNumber(Training.OutgoingDamage)
                        Incoming := CoachNumber(Training.IncomingDamage)
                        View.SetCaption(CoachMessage("הסיבוב הסתיים. נזק שהסבת: {Outgoing}; נזק שספגת: {Incoming}."))
                else if (Training.Phase = coach_phase.Lesson):
                    View.SetCaption(CoachLessonText(Training.LessonIndex, Training.LessonStep, true))
                else:
                    View.SetCaption(CoachMessage("המאמן מדבר באנגלית. להסבר בעברית אפשר לפתוח את תפריט המאמן."))
            else:
                View.SetCaption(Event(1))

    OnPlayerPromptFinished(Agent : agent):void =
        if (Agent = Training.Owner, not Closed?, Training.VoiceEnabled?):
            set CommandsUntil = GetSimulationElapsedTime() + 12.0

    OnVoiceCommand(Command : coach_voice_command):void =
        if (Closed? or Training.Closed? or not Training.VoiceEnabled? or GetSimulationElapsedTime() > CommandsUntil or Command.Action = coach_voice_action.NoChange):
            return
        set CommandsUntil = -100.0
        if (Command.Action = coach_voice_action.ChangeStyle):
            set Training.Style = Command.Style
            Training.SavePreferences()
        else if (Command.Action = coach_voice_action.OpenLesson):
            View.Owner.SelectLesson(Training.Owner, Command.LessonIndex)
        else if (Command.Action = coach_voice_action.ResumeFight):
            if (Training.Phase = coach_phase.Review or Training.Phase = coach_phase.Lesson and not Training.LessonFromFight?):
                View.Owner.StartPersonal(Training.Owner)
            else:
                View.Owner.ResumePersonal(Training.Owner)

    OnPromptFailure(Error : ai_error):void =
        # Keep lesson text available without exposing service errors in the player flow.
        Print("PCL|voice|response_unconfirmed", ?Duration := 0.0)

    Dispose():void =
        set Closed = true
        StopSpeech()
        if (Training.Owner.IsActive[], Target := Training.Owner.GetConversationTarget[], Target(0) = Persona):
            Training.Owner.ClearConversationTarget()
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        if (Current := Channel?):
            Removed := Root.RemoveChatChannel(Current)
        set Channel = false
        PlayerRemoved := Group.RemoveMember(Training.Owner)
        SpeakerRemoved := Group.RemoveMember(Speaker)

# A separate, noncombat body lets the coach continue speaking after an opponent is eliminated.
coach_speaker_behavior := class(npc_behavior):
    var Ending : logic = false

    OnBegin<override>()<suspends>:void =
        if (Agent := GetAgent[], Character := Agent.GetFortCharacter[], Body := GetEntity[], Actions := Body.GetComponent[guard_actions_component]):
            Character.SetVulnerability(false)
            Character.PutInStasis(stasis_args{AllowTurning := true, AllowFalling := true})
            loop:
                if (Ending? or not Character.IsActive[]):
                    return
                Actions.Idle(?Duration := 0.5)

    OnEnd<override>():void =
        set Ending = true
