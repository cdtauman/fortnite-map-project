using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/SpatialMath }

coach_mode := enum:
    Hub
    Personal
    Duel
    FreeBuild
    EditTraining

coach_phase := enum:
    Ready
    Preparing
    Fighting
    Review
    Lesson

coach_style := enum:
    Balanced
    Pressure
    Patient

coach_personality := enum:
    Supportive
    Direct
    Analytical

coach_timing := enum:
    DuringAndAfter
    AfterOnly

coach_round_record := class<final><persistable>:
    Won : logic = false
    DamageDealt : float = 0.0
    DamageTaken : float = 0.0
    ActiveSeconds : float = 0.0
    Challenge : float = 0.45

coach_profile := class<final><persistable>:
    SchemaVersion : int = 3
    CompletedRounds : int = 0
    WonRounds : int = 0
    Challenge : float = 0.45
    LeftEvidence : float = 0.0
    RightEvidence : float = 0.0
    Personality : int = 0
    Timing : int = 0
    TextLanguage : int = 0
    VoiceEnabled : logic = true
    CompletedLessons : int = 0
    OpponentStyle : int = 0
    HumanSamples : float = 0.0
    HumanSuccesses : float = 0.0
    HumanForward : float = 0.0
    HumanLateral : float = 0.0
    HumanCrouch : float = 0.0
    CompletedDrills : int = 0
    BestWallRoute : float = 0.0
    BestTripleRoute : float = 0.0
    BestWallSegments : []float = array{}
    BestTripleSegments : []float = array{}
    BestChainRoute : float = 0.0
    BestChainSegments : []float = array{}
    LastRecommendedLesson : int = 0
    RecentOutgoingShare : float = 0.5
    RecentRounds : []coach_round_record = array{}
    TacticTrials : []float = array{}
    TacticValues : []float = array{}
    CompletedCoverSessions : int = 0
    CompletedAngleSessions : int = 0
    TrainingPlan : coach_training_plan = coach_training_plan{}
    # Five slot choices (catalog index or -1); see coach_duel_match.verse.
    DuelLoadout : []int = array{}
    # 1V1 career totals (spec v1 step 2.7).
    DuelRounds : int = 0
    DuelRoundWins : int = 0
    DuelMatches : int = 0
    DuelMatchWins : int = 0

var CoachProfiles : weak_map(player, coach_profile) = map{}

CopyCoachProfile<constructor>(Source : coach_profile)<transacts> := coach_profile:
    SchemaVersion := Source.SchemaVersion
    CompletedRounds := Source.CompletedRounds
    WonRounds := Source.WonRounds
    Challenge := Source.Challenge
    LeftEvidence := Source.LeftEvidence
    RightEvidence := Source.RightEvidence
    Personality := Source.Personality
    Timing := Source.Timing
    TextLanguage := Source.TextLanguage
    VoiceEnabled := Source.VoiceEnabled
    CompletedLessons := Source.CompletedLessons
    OpponentStyle := Source.OpponentStyle
    HumanSamples := Source.HumanSamples
    HumanSuccesses := Source.HumanSuccesses
    HumanForward := Source.HumanForward
    HumanLateral := Source.HumanLateral
    HumanCrouch := Source.HumanCrouch
    CompletedDrills := Source.CompletedDrills
    BestWallRoute := Source.BestWallRoute
    BestTripleRoute := Source.BestTripleRoute
    BestWallSegments := Source.BestWallSegments
    BestTripleSegments := Source.BestTripleSegments
    BestChainRoute := Source.BestChainRoute
    BestChainSegments := Source.BestChainSegments
    LastRecommendedLesson := Source.LastRecommendedLesson
    RecentOutgoingShare := Source.RecentOutgoingShare
    RecentRounds := Source.RecentRounds
    TacticTrials := Source.TacticTrials
    TacticValues := Source.TacticValues
    CompletedCoverSessions := Source.CompletedCoverSessions
    CompletedAngleSessions := Source.CompletedAngleSessions
    TrainingPlan := Source.TrainingPlan
    DuelLoadout := Source.DuelLoadout
    DuelRounds := Source.DuelRounds
    DuelRoundWins := Source.DuelRoundWins
    DuelMatches := Source.DuelMatches
    DuelMatchWins := Source.DuelMatchWins

LoadCoachProfile(Player : player)<transacts>:coach_profile =
    if (Player.IsActive[], Existing := CoachProfiles[Player]):
        return Existing
    return coach_profile{}

StoreCoachProfile(Player : player, Profile : coach_profile):logic =
    if (Player.IsActive[], FitsInPlayerMap[Profile], set CoachProfiles[Player] = Profile):
        return true
    Print("PCL|profile|save_unconfirmed", ?Duration := 0.0)
    return false

coach_moment := struct:
    At : float = 0.0
    Kind : int = 0
    Amount : float = 0.0
    Visibility : ?logic = false
    FightTime : float = 0.0

# Only uninterrupted visible movement feeds the habit model, independently of tactic duration.
coach_habit_model := class:
    var Left : float = 0.0
    var Right : float = 0.0
    var LastAt : float = -100.0
    var PreviousFrame : ?coach_combat_frame = false
    var AnchorFrame : ?coach_combat_frame = false

    ResetObservation():void =
        set PreviousFrame = false
        set AnchorFrame = false

    ObserveVisibleFrame(Current : coach_combat_frame):void =
        var VisibleNow : logic = false
        if (Visible := Current.VisibleToOpponent?, Visible?):
            set VisibleNow = true
        if (not VisibleNow?):
            ResetObservation()
            return
        if (Previous := PreviousFrame?):
            Gap := Current.At - Previous.At
            if (Gap <= 0.0 or Gap > 0.3 or Distance(Current.PlayerPosition, Previous.PlayerPosition) > 1200.0):
                # Do not bridge a missing frame or a discontinuous position.
                set AnchorFrame = false
        set PreviousFrame = option{Current}
        if (Anchor := AnchorFrame?):
            Interval := Current.At - Anchor.At
            if (Interval >= 0.6):
                if (Interval <= 1.0):
                    ToPlayer := Current.PlayerPosition - Current.OpponentPosition
                    if (Direction := vector3{X := ToPlayer.X, Y := ToPlayer.Y}.MakeUnitVector[]):
                        RightAxis := vector3{X := -Direction.Y, Y := Direction.X}
                        ObserveLateral(DotProduct(Current.PlayerPosition - Anchor.PlayerPosition, RightAxis), Current.At)
                set AnchorFrame = option{Current}
        else:
            set AnchorFrame = option{Current}

    ObserveLateral<private>(SignedMovement : float, At : float):void =
        if (At - LastAt < 0.6 or Abs(SignedMovement) < 48.0):
            return
        set LastAt = At
        set Left *= 0.96
        set Right *= 0.96
        if (SignedMovement < 0.0):
            set Left += 1.0
        else:
            set Right += 1.0

    Confidence()<transacts>:float =
        Samples := Left + Right
        return Clamp((Samples - 3.0) / 15.0, 0.0, 1.0)

    # Smoothed probability, not certainty about the player's next move.
    LeftProbability()<transacts>:float =
        return (Left + 2.0) / (Left + Right + 4.0)

coach_training_session := class:
    Owner : player
    Habits : coach_habit_model = coach_habit_model{}
    HumanPatterns : coach_human_pattern_model = coach_human_pattern_model{}
    Tactics : coach_tactic_learner = coach_tactic_learner{}
    Practice : coach_exchange_practice = coach_exchange_practice{}
    History : coach_combat_history = coach_combat_history{}
    var Profile : coach_profile = coach_profile{}
    var Mode : coach_mode = coach_mode.Hub
    var Phase : coach_phase = coach_phase.Ready
    var Style : coach_style = coach_style.Balanced
    var Personality : coach_personality = coach_personality.Supportive
    var Timing : coach_timing = coach_timing.DuringAndAfter
    var HebrewText : logic = false
    var LastRoundWon : logic = false
    var LastRoundInterrupted : logic = false
    var AwaitingNextRound : logic = false
    var NextRoundAt : float = -1.0
    var VoiceEnabled : logic = true
    var VoiceLink : ?coach_voice_link = false
    var Challenge : float = 0.45
    var Generation : int = 0
    var Paused : logic = false
    var Closed : logic = false
    var StartedAt : float = 0.0
    var PauseStartedAt : float = -1.0
    var PausedTotal : float = 0.0
    var LastAdjustment : float = 0.0
    var OutgoingDamage : float = 0.0
    var IncomingDamage : float = 0.0
    var AdjustedOutgoing : float = 0.0
    var AdjustedIncoming : float = 0.0
    var UnattributedDamage : float = 0.0
    var VisibleSeconds : float = 0.0
    var ExposureRun : float = 0.0
    var LongestExposure : float = 0.0
    var LessonIndex : int = 0
    var LessonStep : int = 0
    var LessonSpeed : float = 1.0
    var LessonPlaying : logic = false
    var LessonSerial : int = 0
    var LessonProgress : float = 0.0
    var LessonSeek : logic = true
    var LessonDiagram : logic = false
    var LessonReturn : ?transform = false
    var LessonFromFight : logic = false
    var LessonCourseActive : logic = false
    var LastCheckpoint : float = 0.0
    var Moments : []coach_moment = array{}
    var MomentCursor : int = 0
    var PlanPracticeRevision : int = -1
    var PlanApplicationRevision : int = -1

    Initialize():void =
        set Profile = LoadCoachProfile(Owner)
        # Spec v1 (2026-11-09): English is the default UI language and Hebrew is opt-in.
        # Versions before 3 stored a language the player never chose, so they restart in English.
        if (Profile.SchemaVersion < 3):
            set Profile = coach_profile{SchemaVersion := 3, TextLanguage := 0, CopyCoachProfile<constructor>(Profile)}
        Tactics.Initialize(Profile.TacticTrials, Profile.TacticValues)
        set Challenge = Clamp(Profile.Challenge, 0.1, 0.9)
        set Habits.Left = Clamp(Profile.LeftEvidence, 0.0, 25.0)
        set Habits.Right = Clamp(Profile.RightEvidence, 0.0, 25.0)
        if (Profile.Personality = 1):
            set Personality = coach_personality.Direct
        else if (Profile.Personality = 2):
            set Personality = coach_personality.Analytical
        if (Profile.Timing = 1):
            set Timing = coach_timing.AfterOnly
        if (Profile.TextLanguage = 1):
            set HebrewText = true
        else:
            set HebrewText = false
        if (Profile.OpponentStyle = 1):
            set Style = coach_style.Pressure
        else if (Profile.OpponentStyle = 2):
            set Style = coach_style.Patient
        set VoiceEnabled = Profile.VoiceEnabled
        set LessonIndex = Clamp(Profile.LastRecommendedLesson, 0, 2)
        set HumanPatterns.Samples = Clamp(Profile.HumanSamples, 0.0, 200.0)
        set HumanPatterns.Successes = Clamp(Profile.HumanSuccesses, 0.0, 100.0)
        set HumanPatterns.Forward = Clamp(Profile.HumanForward, -1000.0, 1000.0)
        set HumanPatterns.Lateral = Clamp(Profile.HumanLateral, -1000.0, 1000.0)
        set HumanPatterns.Crouch = Clamp(Profile.HumanCrouch, 0.0, 1.0)

    BeginRound(?PreserveExercise : logic = false):void =
        PreviousPlanPractice := PlanPracticeRevision
        set PlanPracticeRevision = -1
        set PlanApplicationRevision = -1
        set AwaitingNextRound = false
        set LastRoundInterrupted = false
        set NextRoundAt = -1.0
        set Generation += 1
        set Mode = coach_mode.Personal
        set Phase = coach_phase.Fighting
        set Paused = false
        set StartedAt = GetSimulationElapsedTime()
        set PauseStartedAt = -1.0
        set PausedTotal = 0.0
        set LastAdjustment = 0.0
        set OutgoingDamage = 0.0
        set IncomingDamage = 0.0
        set AdjustedOutgoing = 0.0
        set AdjustedIncoming = 0.0
        set UnattributedDamage = 0.0
        set VisibleSeconds = 0.0
        set ExposureRun = 0.0
        set LongestExposure = 0.0
        set Moments = array{}
        set MomentCursor = 0
        History.Reset()
        HumanPatterns.ResetObservation()
        Tactics.Cancel()
        if (PreserveExercise? and Practice.Goal > 0 and not Practice.Completed?):
            Practice.ResetObservation()
            if (PreviousPlanPractice = Profile.TrainingPlan.Revision and Profile.TrainingPlan.Stage = 2):
                set PlanPracticeRevision = PreviousPlanPractice
        else:
            Practice.Stop()
        set LessonFromFight = false

    ActiveElapsed(At : float)<transacts>:float =
        var Pauses : float = PausedTotal
        if (PauseStartedAt >= 0.0):
            set Pauses += Max(0.0, At - PauseStartedAt)
        return Max(0.0, At - StartedAt - Pauses)

    RecordDamage(Outgoing : logic, Amount : float, At : float, Visibility : ?logic):void =
        if (Closed? or Paused? or Phase <> coach_phase.Fighting or Amount <= 0.0):
            return
        Tactics.ObserveDamage(Outgoing, Amount, At, Generation)
        if (Outgoing?):
            set OutgoingDamage += Amount
            HumanPatterns.RewardObservedPattern(At)
            Practice.RecordHit(At)
            AddMoment(coach_moment{At := At, Kind := 1, Amount := Amount, Visibility := Visibility, FightTime := ActiveElapsed(At)})
        else:
            set IncomingDamage += Amount
            AddMoment(coach_moment{At := At, Kind := 2, Amount := Amount, Visibility := Visibility, FightTime := ActiveElapsed(At)})
            History.RecordIncomingFocus(Amount, At, ActiveElapsed(At), Visibility)

    AddMoment(Moment : coach_moment):void =
        if (Moments.Length < 64):
            set Moments += array{Moment}
        else:
            if (set Moments[MomentCursor] = Moment) {}
            set MomentCursor += 1
            if (MomentCursor >= 64):
                set MomentCursor = 0

    ObserveExposure(IsVisible : logic, Delta : float):void =
        if (Paused? or Phase <> coach_phase.Fighting):
            return
        if (IsVisible?):
            set VisibleSeconds += Delta
            set ExposureRun += Delta
            set LongestExposure = Max(LongestExposure, ExposureRun)
        else:
            set ExposureRun = 0.0

    AdaptChallenge(At : float, ?RoundEnded : logic = false):void =
        if (Closed? or Paused? or Mode <> coach_mode.Personal or Phase <> coach_phase.Fighting):
            return
        ActiveAt := ActiveElapsed(At)
        WindowOutgoing := OutgoingDamage - AdjustedOutgoing
        WindowIncoming := IncomingDamage - AdjustedIncoming
        if (WindowIncoming + WindowOutgoing < 40.0):
            return
        if (not RoundEnded? and ActiveAt - LastAdjustment < 5.0):
            return
        set LastAdjustment = ActiveAt
        set AdjustedOutgoing = OutgoingDamage
        set AdjustedIncoming = IncomingDamage
        Share := WindowOutgoing / Max(1.0, WindowIncoming + WindowOutgoing)
        # A bounded training adjustment, separate from any claim to a competitive skill rating.
        set Challenge = Clamp(Challenge + Clamp(Share - 0.45, -0.3, 0.3) * 0.08, 0.1, 0.9)

    ReactionDelay()<transacts>:float =
        return 0.60 - Challenge * 0.45

    RecommendLesson()<transacts>:int =
        Recommendation := CoachRecommendLesson(Self)
        return Recommendation.Lesson

    FinishRound(Won : logic):void =
        if (Phase <> coach_phase.Fighting or Closed?):
            return
        set LastRoundInterrupted = false
        # A fast round must not discard its unused attributed exchange. The
        # consumed damage counters prevent crediting an earlier window twice.
        AdaptChallenge(GetSimulationElapsedTime(), ?RoundEnded := true)
        Plan := Profile.TrainingPlan
        if (Plan.Stage = 3 and PlanApplicationRevision = Plan.Revision and OutgoingDamage + IncomingDamage > 0.0):
            set Profile = coach_profile{TrainingPlan := coach_training_plan{Stage := 4, CompletedPlans := Plan.CompletedPlans + 1, CopyCoachTrainingPlan<constructor>(Plan)}, CopyCoachProfile<constructor>(Profile)}
        set PlanApplicationRevision = -1
        Tactics.Finish(GetSimulationElapsedTime(), Generation)
        set Phase = coach_phase.Review
        set Paused = true
        set Generation += 1
        set LessonIndex = RecommendLesson()
        var NextOutgoingShare : float = Profile.RecentOutgoingShare
        if (OutgoingDamage + IncomingDamage > 0.0):
            set NextOutgoingShare = Profile.RecentOutgoingShare * 0.75 + (OutgoingDamage / (OutgoingDamage + IncomingDamage)) * 0.25
        var WinIncrement : int = 0
        if (Won?):
            set WinIncrement = 1
        var Recent : []coach_round_record = array{}
        for (Index := Max(0, Profile.RecentRounds.Length - 9)..Profile.RecentRounds.Length - 1, Record := Profile.RecentRounds[Index]):
            set Recent += array{Record}
        set Recent += array{coach_round_record{Won := Won, DamageDealt := OutgoingDamage, DamageTaken := IncomingDamage, ActiveSeconds := ActiveElapsed(GetSimulationElapsedTime()), Challenge := Challenge}}
        set Profile = coach_profile:
            RecentRounds := Recent
            CompletedRounds := Profile.CompletedRounds + 1
            WonRounds := Profile.WonRounds + WinIncrement
            HumanSamples := HumanPatterns.Samples
            HumanSuccesses := HumanPatterns.Successes
            HumanForward := HumanPatterns.Forward
            HumanLateral := HumanPatterns.Lateral
            HumanCrouch := HumanPatterns.Crouch
            TacticTrials := Tactics.Trials
            TacticValues := Tactics.Values
            Challenge := Challenge
            LeftEvidence := Habits.Left
            RightEvidence := Habits.Right
            LastRecommendedLesson := LessonIndex
            RecentOutgoingShare := NextOutgoingShare
            CopyCoachProfile<constructor>(Profile)
        Saved := StoreCoachProfile(Owner, Profile)

    # An environmental/self/third-party elimination is not evidence that the
    # trainee won or lost to this opponent. Preserve completed observations,
    # but discard the unfinished exchange and do not score the interruption.
    InterruptRound():void =
        if (Phase <> coach_phase.Fighting or Closed?):
            return
        Tactics.Cancel()
        HumanPatterns.ResetObservation()
        Habits.ResetObservation()
        Practice.ResetObservation()
        set LastRoundInterrupted = true
        set LastRoundWon = false
        set PauseStartedAt = GetSimulationElapsedTime()
        set Phase = coach_phase.Review
        set Paused = true
        set Generation += 1
        SavePreferences()

    SavePreferences():void =
        var PersonalityIndex : int = 0
        var TimingIndex : int = 0
        var LanguageIndex : int = 0
        var StyleIndex : int = 0
        if (Personality = coach_personality.Direct):
            set PersonalityIndex = 1
        else if (Personality = coach_personality.Analytical):
            set PersonalityIndex = 2
        if (Timing = coach_timing.AfterOnly):
            set TimingIndex = 1
        if (HebrewText?):
            set LanguageIndex = 1
        if (Style = coach_style.Pressure):
            set StyleIndex = 1
        else if (Style = coach_style.Patient):
            set StyleIndex = 2
        set Profile = coach_profile:
            SchemaVersion := 3
            Challenge := Challenge
            LeftEvidence := Habits.Left
            RightEvidence := Habits.Right
            Personality := PersonalityIndex
            Timing := TimingIndex
            TextLanguage := LanguageIndex
            VoiceEnabled := VoiceEnabled
            OpponentStyle := StyleIndex
            LastRecommendedLesson := LessonIndex
            HumanSamples := HumanPatterns.Samples
            HumanSuccesses := HumanPatterns.Successes
            HumanForward := HumanPatterns.Forward
            HumanLateral := HumanPatterns.Lateral
            HumanCrouch := HumanPatterns.Crouch
            TacticTrials := Tactics.Trials
            TacticValues := Tactics.Values
            CopyCoachProfile<constructor>(Profile)
        Saved := StoreCoachProfile(Owner, Profile)

    RecordDuelRound(WonRound : logic, MatchOver : logic):void =
        var RoundWins : int = Profile.DuelRoundWins
        var Matches : int = Profile.DuelMatches
        var MatchWins : int = Profile.DuelMatchWins
        if (WonRound?):
            set RoundWins += 1
        if (MatchOver?):
            set Matches += 1
            if (WonRound?):
                set MatchWins += 1
        set Profile = coach_profile:
            DuelRounds := Profile.DuelRounds + 1
            DuelRoundWins := RoundWins
            DuelMatches := Matches
            DuelMatchWins := MatchWins
            CopyCoachProfile<constructor>(Profile)
        Saved := StoreCoachProfile(Owner, Profile)

    SaveDuelLoadout(Loadout : []int):void =
        set Profile = coach_profile{DuelLoadout := Loadout, CopyCoachProfile<constructor>(Profile)}
        Saved := StoreCoachProfile(Owner, Profile)

    RecordDrill(Kind : coach_course_kind, Elapsed : float, ?Segments : []float = array{}):void =
        if (Elapsed <= 0.0 or Closed?):
            return
        var BestWall : float = Profile.BestWallRoute
        var BestTriple : float = Profile.BestTripleRoute
        var BestChain : float = Profile.BestChainRoute
        var WallSegments : []float = Profile.BestWallSegments
        var TripleSegments : []float = Profile.BestTripleSegments
        var ChainSegments : []float = Profile.BestChainSegments
        if (Kind = coach_course_kind.PrecisionWalls):
            if (BestWall <= 0.0 or Elapsed < BestWall):
                set BestWall = Elapsed
            if (CoachCourseSegmentsValid(Kind, Elapsed, Segments)?):
                set WallSegments = CoachCourseBestSegments(Segments, WallSegments)
        else if (Kind = coach_course_kind.TripleSequence):
            if (BestTriple <= 0.0 or Elapsed < BestTriple):
                set BestTriple = Elapsed
            if (CoachCourseSegmentsValid(Kind, Elapsed, Segments)?):
                set TripleSegments = CoachCourseBestSegments(Segments, TripleSegments)
        else:
            if (BestChain <= 0.0 or Elapsed < BestChain):
                set BestChain = Elapsed
            if (CoachCourseSegmentsValid(Kind, Elapsed, Segments)?):
                set ChainSegments = CoachCourseBestSegments(Segments, ChainSegments)
        set Profile = coach_profile:
            CompletedDrills := Profile.CompletedDrills + 1
            BestWallRoute := BestWall
            BestTripleRoute := BestTriple
            BestWallSegments := WallSegments
            BestTripleSegments := TripleSegments
            BestChainRoute := BestChain
            BestChainSegments := ChainSegments
            CopyCoachProfile<constructor>(Profile)
        SavePreferences()

    RecordFocusedSession(GoalKind : int):void =
        Plan := Profile.TrainingPlan
        if (Plan.Stage = 2 and PlanPracticeRevision = Plan.Revision and GoalKind = Plan.Lesson + 1 and Practice.Completed?):
            set Profile = coach_profile{TrainingPlan := coach_training_plan{Stage := 3, PracticeProgress := 5, CopyCoachTrainingPlan<constructor>(Plan)}, CopyCoachProfile<constructor>(Profile)}
            set PlanPracticeRevision = -1
        if (GoalKind = 1):
            set Profile = coach_profile{CompletedCoverSessions := Profile.CompletedCoverSessions + 1, CopyCoachProfile<constructor>(Profile)}
        else if (GoalKind = 2):
            set Profile = coach_profile{CompletedAngleSessions := Profile.CompletedAngleSessions + 1, CopyCoachProfile<constructor>(Profile)}
        SavePreferences()

    SaveTrainingPlan():void =
        Recommendation := CoachRecommendLesson(Self)
        Previous := Profile.TrainingPlan
        Plan := coach_training_plan{Revision := Previous.Revision + 1, Stage := 1, Lesson := Recommendation.Lesson, Reason := CoachPlanReasonCode(Recommendation.Reason), SourceRound := Profile.CompletedRounds, CompletedPlans := Previous.CompletedPlans}
        set Profile = coach_profile{TrainingPlan := Plan, CopyCoachProfile<constructor>(Profile)}
        set PlanPracticeRevision = -1
        set PlanApplicationRevision = -1
        SavePreferences()

    PreparePlanPractice():void =
        Plan := Profile.TrainingPlan
        if (Plan.Stage = 1):
            set Profile = coach_profile{TrainingPlan := coach_training_plan{Stage := 2, CopyCoachTrainingPlan<constructor>(Plan)}, CopyCoachProfile<constructor>(Profile)}
            SavePreferences()

    BindPlanRound(Revision : int, Application : logic):void =
        Plan := Profile.TrainingPlan
        if (Revision < 0 or Revision <> Plan.Revision):
            return
        if (Plan.Stage = 3 and Application? and Practice.Goal = 0):
            set PlanApplicationRevision = Revision
        else if (Plan.Stage = 2 and not Application? and Practice.Goal = Plan.Lesson + 1):
            set PlanPracticeRevision = Revision
            set Practice.Progress = Clamp(Plan.PracticeProgress, 0, 4)

    CheckpointPlanPractice():void =
        Plan := Profile.TrainingPlan
        if (Plan.Stage = 2 and PlanPracticeRevision = Plan.Revision and Practice.Goal = Plan.Lesson + 1):
            Progress := Clamp(Practice.Progress, 0, 4)
            if (Progress > Plan.PracticeProgress):
                set Profile = coach_profile{TrainingPlan := coach_training_plan{PracticeProgress := Progress, CopyCoachTrainingPlan<constructor>(Plan)}, CopyCoachProfile<constructor>(Profile)}
                SavePreferences()

coach_runtime := class:
    var Players : [player]coach_training_session = map{}
    var ActiveTrainee : ?coach_training_session = false
    var Ending : logic = false
    var Structures : ?coach_structure_device = false

var CoachRuntime : weak_map(session, coach_runtime) = map{}
