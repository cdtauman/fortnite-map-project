using { /Fortnite.com/AI }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Teams }
using { /Verse.org/Random }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/SpatialMath }

# Focus can return before a combat/movement window ends. Only the sibling
# action, timeout or cancellation watcher may finish that window.
CoachFocusCompanion(Actions : guard_actions_component, Target : entity)<suspends>:void =
    Actions.Focus(Target, ?LockFocus := true)
    Print("PCL|combat_action|focus_request_returned|action_window_continues", ?Duration := 0.0)
    loop:
        Sleep(0.1)

coach_hold_trace := class:
    var Entered : logic = false
    var DeferredReleaseReached : logic = false

CoachFocusPointCompanion(Actions : guard_actions_component, Position : vector3)<suspends>:void =
    Actions.Focus(FromVector3(Position), ?LockFocus := true)
    # A focus result does not own the lifetime of the accompanying movement/lesson.
    loop:
        Sleep(0.1)

CoachHoldAttackWindow(Actions : guard_actions_component, Character : fort_character, Target : entity, Duration : float, ?Trace : ?coach_hold_trace = false)<suspends>:void =
    Position := Character.GetTransform().Translation
    if (State := Trace?):
        set State.Entered = true
    Actions.Tether(FromVector3(Position), 75.0)
    Print("PCL|combat_action|tether_begin|x={Position.X}|y={Position.Y}|z={Position.Z}|radius=75", ?Duration := 0.0)
    defer:
        if (State := Trace?):
            set State.DeferredReleaseReached = true
        Actions.Untether()
        Print("PCL|combat_action|tether_released", ?Duration := 0.0)
    race:
        CoachFocusCompanion(Actions, Target)
        block:
            Result := Actions.Attack(Target)
            loop:
                Sleep(0.1)
        Sleep(Duration)

CoachReleaseHold(Actions : guard_actions_component, Scope : string):void =
    Actions.Untether()
    Print("PCL|combat_action|owner_release|scope={Scope}", ?Duration := 0.0)

coach_tactic := enum:
    HoldAngle
    CloseDistance
    ChangeAngle
    Disengage
    SearchLastSeen
    GainHeight
    LearnedMovement
    DefensiveBox

# Assign to an NPC Spawner's behavior override; the lab guard remains a separate baseline.
coach_opponent_behavior := class(npc_behavior):
    var Ending : logic = false
    var ControlledCharacter : ?fort_character = false
    var LastSeenAt : float = -100.0
    var LastSeenPosition : vector3 = vector3{}
    var LastRound : int = -1
    var SeenTarget : ?npc_target_info = false
    var OwnCover : ?coach_live_piece = false
    var CoverChangedAt : float = -100.0
    var CoverFireRetryAt : float = -100.0
    var LastObstacleAttempt : float = -100.0
    Equipment : coach_equipment = coach_equipment{}
    var CrouchIntent : logic = false
    var HoldPending : logic = false
    var CombatSight : ?npc_awareness_component = false
    var RecoverySide : float = 1.0
    var RecoverySideAt : float = -100.0
    var StalledGeneration : int = -1
    var StalledAt : float = -100.0
    var StalledBody : vector3 = vector3{}
    var StalledThreat : vector3 = vector3{}
    var StalledAttempts : int = 0
    AscentRetry : coach_build_retry_state = coach_build_retry_state{}
    BoxRetry : coach_build_retry_state = coach_build_retry_state{}

    OnBegin<override>()<suspends>:void =
        for (Attempt := 0..39):
            Bound := TryBindAndRun()
            if (Bound?):
                return
            if (Ending?):
                return
            Sleep(0.1)
        Print("PCL|opponent|controller_binding_unconfirmed", ?Duration := 0.0)

    TryBindAndRun()<suspends>:logic =
        if:
            Agent := GetAgent[]
            Character := Agent.GetFortCharacter[]
            Body := GetEntity[]
            Actions := Body.GetComponent[guard_actions_component]
            Awareness := Body.GetComponent[npc_awareness_component]
        then:
            LoadoutReady := Equipment.InitializeNPCLoadout(Agent)
            if (not LoadoutReady?):
                Print("PCL|opponent|custom_loadout_not_ready|inspect_equipment_result|custom_aim_unconfirmed", ?Duration := 0.0)
            ToolPrepared := Equipment.PrepareBuildPlan(Agent)
            if (not ToolPrepared?):
                Print("PCL|opponent|build_plan_preparation_pending", ?Duration := 0.0)
            Print("PCL|opponent|controller_ready", ?Duration := 0.0)
            Run(Character, Actions, Awareness)
            return true
        return false

    OnEnd<override>():void =
        set Ending = true
        set ControlledCharacter = false
        set CombatSight = false
        if (Body := GetEntity[], Actions := Body.GetComponent[guard_actions_component]):
            ReleaseOwnedHold(Actions, "npc_end")
            Actions.StopNavigation()
        Equipment.DisposeBuildPlan()
        LoadoutRemoved := Equipment.DisposeLoadout()

    Run(Character : fort_character, Actions : guard_actions_component, Awareness : npc_awareness_component)<suspends>:void =
        if (Ending? or not Character.IsActive[]):
            return
        set ControlledCharacter = option{Character}
        set CombatSight = option{Awareness}
        if (Owner := Character.GetAgent[]):
            PreparedWeapon := Equipment.SelectWeapon(Owner, 1500.0)
        defer:
            set ControlledCharacter = false
            set CombatSight = false
            ReleaseOwnedHold(Actions, "controller_end")
            Actions.StopNavigation()
        loop:
            if (Ending? or not Character.IsActive[]):
                return
            if:
                Runtime := CoachRuntime[GetSession()]
                not Runtime.Ending?
                Training := Runtime.ActiveTrainee?
                not Training.Closed?
                Training.Mode = coach_mode.Personal
                Training.Phase = coach_phase.Fighting
                not Training.Paused?
            then:
                if (LastRound <> Training.Generation):
                    set LastRound = Training.Generation
                    set LastSeenAt = -100.0
                    set SeenTarget = false
                    set LastObstacleAttempt = -100.0
                    set CoverFireRetryAt = -100.0
                    set StalledAttempts = 0
                    AscentRetry.Clear()
                    BoxRetry.Clear()
                Ticket := Training.Generation
                if (Structures := Runtime.Structures?, Body := Character.GetEntity[], InventoryOwner := Character.GetAgent[]):
                    set Structures.BuilderBody = option{Body}
                    set Structures.BuilderAgent = option{InventoryOwner}
                UpdateCover(Runtime, Training, Character)
                Peeked := TryCoverPeek(Runtime, Training, Character, Actions)
                if (Peeked?):
                    Sleep(0.1)
                if (not Peeked?):
                    set SeenTarget = VisibleTrainingTarget(Training)
                    if (Observed := SeenTarget?):
                        set LastSeenAt = GetSimulationElapsedTime()
                        set LastSeenPosition = FromVector3(Observed.LastKnownPosition)
                    if (SeenTarget?):
                        Training.AdaptChallenge(GetSimulationElapsedTime())
                        if (Training.Timing = coach_timing.DuringAndAfter, Training.ExposureRun > 2.0, Voice := Training.VoiceLink?):
                            Voice.Say(CoachMessage("Give one brief general reminder to use cover between shots. Do not state an exact mistake or invented combat event. Speak English."), false)
                        Sleep(Training.ReactionDelay())
                        if (not Ending?, Ticket = Training.Generation, not Training.Paused?, FreshInfo := VisibleTrainingTarget(Training)?):
                            set LastSeenAt = GetSimulationElapsedTime()
                            set LastSeenPosition = FromVector3(FreshInfo.LastKnownPosition)
                            Tactic := SelectTactic(Training, Character)
                            Context := CoachTacticContext(Distance(Character.GetTransform().Translation, LastSeenPosition), LastSeenPosition.Z - Character.GetTransform().Translation.Z)
                            Training.Tactics.Begin(Context, Tactic, GetSimulationElapsedTime(), Ticket)
                            set Actions.MovementSpeedMultiplier = 0.8 + Training.Challenge * 0.2
                            var SightRequirement : ?npc_target_info = option{FreshInfo}
                            if (Tactic = coach_tactic.GainHeight or Tactic = coach_tactic.DefensiveBox):
                                # A short construction sequence may continue from the last seen position.
                                set SightRequirement = false
                            Completed := race:
                                block:
                                    ExecuteVisibleTactic(Tactic, Training, Character, Actions, FreshInfo)
                                    true
                                block:
                                    WatchCancellation(Training, Ticket, Character, SightRequirement)
                                    false
                            # The surviving owner also releases construction;
                            # cleanup in a canceled skill child is insufficient.
                            if (Tactic = coach_tactic.GainHeight or Tactic = coach_tactic.DefensiveBox):
                                if (Owner := Character.GetAgent[]):
                                    Equipment.ReleaseConstruction(Owner)
                            ReleaseOwnedHold(Actions, "tactic_parent")
                            # Lost sight can cancel a tactic while the same round
                            # remains active. It is not a completed learning trial.
                            if (Completed?, not Ending?, Ticket = Training.Generation, not Training.Closed?, not Training.Paused?, Training.Phase = coach_phase.Fighting, Character.IsActive[]):
                                Training.Tactics.Finish(GetSimulationElapsedTime(), Ticket)
                            else:
                                Training.Tactics.Cancel()
                            Actions.StopNavigation()
                            if (CrouchIntent? and Character.IsActive[]):
                                race:
                                    block:
                                        Standing := Actions.StandUp()
                                    Sleep(0.2)
                                set CrouchIntent = false
                    else:
                        if (InventoryOwner := Character.GetAgent[]):
                            Selected := Equipment.SelectWeapon(InventoryOwner, 1500.0)
                        Pressured := TryPressureDetectedObstacle(Runtime, Training, Character, Actions)
                        Reacquired := VisibleTrainingTarget(Training)
                        # Search only where the target was seen, with a bounded memory horizon.
                        if (not Pressured? and not Reacquired? and GetSimulationElapsedTime() - LastSeenAt < 3.0):
                            race:
                                block:
                                    Outcome := Actions.NavigateTo(MakeNavigationTarget(LastSeenPosition), ?ReachRadius := 150.0, ?AllowPartialPath := true)
                                Sleep(0.6)
                                WatchCancellation(Training, Ticket, Character, false)
                            Actions.StopNavigation()
                        else if (not Pressured? and not Reacquired?):
                            # Patrol a bounded area using our own position, never the hidden player's pose.
                            Current := Character.GetTransform().Translation
                            Limit := CoachArenaHalfExtent(coach_mode.Personal) - 320.0
                            Patrol := vector3{X := Clamp(Current.X + GetRandomFloat(-600.0, 600.0), -Limit, Limit), Y := Clamp(Current.Y + GetRandomFloat(-600.0, 600.0), -Limit, Limit), Z := Current.Z}
                            race:
                                block:
                                    Outcome := Actions.NavigateTo(MakeNavigationTarget(Patrol), ?ReachRadius := 120.0, ?AllowPartialPath := true)
                                Sleep(0.8)
                                WatchCancellation(Training, Ticket, Character, false)
                            Actions.StopNavigation()
            else:
                Actions.StopNavigation()
                Actions.Idle(?Duration := 0.25)
            Sleep(0.1)

    # Resolve the current native observation on every authorization. A remembered
    # target identity/position does not authorize firing through lost sight.
    VisibleTrainingTarget(Training : coach_training_session)<transacts>:?npc_target_info =
        if (not Ending?, not Training.Closed?, not Training.Paused?, Training.Mode = coach_mode.Personal, Training.Phase = coach_phase.Fighting, Sight := CombatSight?, TargetCharacter := Training.Owner.GetFortCharacter[], TargetCharacter.IsActive[], TargetBody := TargetCharacter.GetEntity[]):
            for (Observed : Sight.DetectedTargets, Observed.HasLineOfSight?, Observed.Attitude = team_attitude.Hostile):
                if (Observed.Target = TargetBody or Observed.Target = Training.Owner):
                    return option{Observed}
        return false

    # An obstacle report authorizes only this bounded request against this
    # entity. It is not evidence of wall type, ownership, an edit or destruction.
    ObstacleActionCurrent(Training : coach_training_session, Character : fort_character, Sight : guard_awareness_component, Obstacle : entity, Generation : int)<transacts>:logic =
        if (Ending? or Training.Closed? or Training.Paused? or Training.Mode <> coach_mode.Personal or Training.Phase <> coach_phase.Fighting or Training.Generation <> Generation or not Character.IsActive[] or GetSimulationElapsedTime() - LastSeenAt > 3.0):
            return false
        if (VisibleTrainingTarget(Training)?):
            return false
        if (Current := Sight.DetectedObstacle?, Current = Obstacle):
            for (Target : Sight.DetectedTargets, Target.Target = Obstacle):
                return false
            Position := FromVector3(Obstacle.GetGlobalTransform().Translation)
            HalfExtent := CoachArenaHalfExtent(coach_mode.Personal) - 32.0
            Range := Distance(Character.GetTransform().Translation, Position)
            if (Abs(Position.X) <= HalfExtent and Abs(Position.Y) <= HalfExtent and Position.Z >= 0.0 and Position.Z <= CoachArenaCeiling() and Range >= 100.0 and Range <= 1500.0):
                return true
        return false

    WatchDetectedObstacle(Training : coach_training_session, Character : fort_character, Sight : guard_awareness_component, Obstacle : entity, Generation : int)<suspends>:void =
        loop:
            if (not ObstacleActionCurrent(Training, Character, Sight, Obstacle, Generation)?):
                return
            Sleep(0.05)

    # Native requests against a guard-reported obstacle; no assumption of wall type or destruction.
    TryPressureDetectedObstacle(Runtime : coach_runtime, Training : coach_training_session, Character : fort_character, Actions : guard_actions_component)<suspends>:logic =
        Now := GetSimulationElapsedTime()
        if (Now - LastSeenAt > 3.0 or Now - LastObstacleAttempt < 1.2):
            return false
        if (Structures := Runtime.Structures?, Structures.CombatReady()?, Body := Character.GetEntity[], InventoryOwner := Character.GetAgent[], GuardSight := Body.GetComponent[guard_awareness_component], Obstacle := GuardSight.DetectedObstacle?):
            Generation := Training.Generation
            if (Obstacle = Body or not ObstacleActionCurrent(Training, Character, GuardSight, Obstacle, Generation)?):
                return false
            Position := Character.GetTransform().Translation
            TargetPosition := FromVector3(Obstacle.GetGlobalTransform().Translation)
            # Only a single nearby ledger entry may be treated as our obstacle.
            # An ambiguous proxy never grants ownership of an arbitrary player structure.
            var OwnedObstacle : ?coach_live_piece = false
            var OwnedMatches : int = 0
            for (Piece : Structures.Pieces, Piece.Prop.IsValid[], Distance(Piece.Position, TargetPosition) < 320.0):
                set OwnedObstacle = option{Piece}
                set OwnedMatches += 1
            if (OwnedMatches = 1, Piece := OwnedObstacle?):
                if (Threat := (LastSeenPosition - Position).MakeUnitVector[], Route := (TargetPosition - Position).MakeUnitVector[], DotProduct(Threat, Route) > 0.3):
                    set LastObstacleAttempt = Now
                    return OpenTrackedRoute(Training, Character, Actions, Structures, Piece)
                return false
            if (OwnedMatches > 1):
                return false
            ToThreat := LastSeenPosition - Position
            ToObstacle := TargetPosition - Position
            if (Threat := ToThreat.MakeUnitVector[], Direction := ToObstacle.MakeUnitVector[], DotProduct(Threat, Direction) > 0.65):
                if (not ObstacleActionCurrent(Training, Character, GuardSight, Obstacle, Generation)?):
                    return false
                Selected := Equipment.SelectWeapon(InventoryOwner, 1500.0)
                if (not Selected?):
                    return false
                set LastObstacleAttempt = Now
                Equipment.ConfigureAim(InventoryOwner, Training.Challenge)
                Print("PCL|opponent|detected_obstacle_attack_requested|destruction_unconfirmed", ?Duration := 0.0)
                var RequestFailed : logic = false
                race:
                    block:
                        Result := Actions.Attack(Obstacle)
                        if (Result.GetSuccess[]):
                            Print("PCL|opponent|obstacle_action_returned_ok|destruction_unconfirmed", ?Duration := 0.0)
                        else:
                            set RequestFailed = true
                            Print("PCL|opponent|obstacle_action_returned_error", ?Duration := 0.0)
                    CoachFocusCompanion(Actions, Obstacle)
                    Sleep(0.65)
                    WatchCancellation(Training, Generation, Character, false)
                    WatchDetectedObstacle(Training, Character, GuardSight, Obstacle, Generation)
                Actions.StopNavigation()
                Equipment.StopFiring(InventoryOwner)
                return logic{not RequestFailed?}
        return false

    # Candidate geometry edits stay within our encounter ledger. Navigation success
    # is separate from applying the shape; no player build is edited by this route.
    OpenTrackedRoute(Training : coach_training_session, Character : fort_character, Actions : guard_actions_component, Structures : coach_structure_device, Piece : coach_live_piece)<suspends>:logic =
        if (Distance(Character.GetTransform().Translation, Piece.Position) > 700.0):
            return false
        Generation := Training.Generation
        Encounter := Structures.Encounter
        Position := Character.GetTransform().Translation
        Pose := Piece.Prop.GetTransform()
        var Shape : coach_piece_shape = coach_piece_shape.Door
        var Goal : vector3 = Piece.Position + vector3{Z := 100.0}
        if (Piece.Kind = coach_piece_kind.Wall):
            Normal := MakeRotationFromYawPitchRollDegrees(Piece.Yaw, 0.0, 0.0).RotateVector(vector3{X := 1.0})
            var Sign : float = 1.0
            if (DotProduct(Position - Piece.Position, Normal) > 0.0):
                set Sign = -1.0
            set Goal = Goal + Normal * Sign * 200.0
        else:
            set Goal = Pose.Translation + Pose.Rotation.RotateVector(vector3{X := -170.0, Y := 256.0}) + vector3{Z := 100.0}
            if (Piece.Kind = coach_piece_kind.Ramp):
                if (Position.Z > Piece.Position.Z + 180.0):
                    return false
                set Shape = coach_piece_shape.RampHalf
            else if (Piece.Kind = coach_piece_kind.Cone):
                if (Position.Z > Piece.Position.Z + 180.0):
                    return false
                set Shape = coach_piece_shape.ConeRaised
            else:
                if (Position.Z >= Piece.Position.Z or LastSeenPosition.Z < Piece.Position.Z):
                    return false
                var HasRamp : logic = false
                for (Ramp : Structures.Pieces, Ramp.Kind = coach_piece_kind.Ramp, Ramp.Encounter = Encounter, Ramp.Prop.IsValid[], Distance(Ramp.Position + vector3{Z := 384.0}, Piece.Position) < 32.0):
                    set HasRamp = true
                if (not HasRamp?):
                    return false
                set Shape = coach_piece_shape.FloorHalf
        Ready := PrepareBuildTool(Training, Character, ?RequiresMaterials := false)
        if (not Ready? or Generation <> Training.Generation or Encounter <> Structures.Encounter):
            return false
        defer:
            Actions.StopNavigation()
            if (Owner := Character.GetAgent[]):
                Equipment.ReleaseConstruction(Owner)
        Opened := Structures.SetShape(Piece, Shape, Piece.Revision)
        if (Opened <> coach_build_outcome.Applied):
            return false
        Confirmed := ConfirmWallAction(Training, Character, Structures, Piece, Generation, Encounter, Piece.Revision)
        if (not Confirmed?):
            return false
        if (Piece.Kind = coach_piece_kind.Wall):
            set CoverChangedAt = GetSimulationElapsedTime()
        race:
            block:
                Motion := Actions.NavigateTo(MakeNavigationTarget(Goal), ?MovementType := movement_type.Running, ?ReachRadius := 65.0, ?AllowPartialPath := false)
                if (Motion.GetSuccess[], Distance(Character.GetTransform().Translation, Goal) < 160.0):
                    Print("PCL|opponent|tracked_route_reached|native_edit_acceptance_pending", ?Duration := 0.0)
            Sleep(0.85)
            WatchCancellation(Training, Generation, Character, false)
        return true

    UpdateCover(Runtime : coach_runtime, Training : coach_training_session, Character : fort_character)<suspends>:void =
        if (Structures := Runtime.Structures?, Structures.CombatReady()?):
            Now := GetSimulationElapsedTime()
            if (Piece := OwnCover?):
                if (not Piece.Prop.IsValid[] or Piece.Encounter <> Structures.Encounter or Distance(Character.GetTransform().Translation, Piece.Position) > 850.0):
                    set OwnCover = false
                else if (Now - CoverChangedAt >= 1.0):
                    var Next : coach_piece_shape = coach_piece_shape.Solid
                    if (Now - LastSeenAt >= 3.0):
                        # Leave an exit after losing sight instead of sealing ourselves in forever.
                        set Next = coach_piece_shape.Door
                    if (Piece.Shape <> Next):
                        Generation := Training.Generation
                        Encounter := Structures.Encounter
                        Revision := Piece.Revision
                        Ready := PrepareBuildTool(Training, Character, ?RequiresMaterials := false)
                        if (Ready?):
                            defer:
                                if (Owner := Character.GetAgent[]):
                                    Equipment.ReleaseConstruction(Owner)
                            if (CoverActionCurrent(Training, Character, Structures, Piece, Generation, Encounter, Revision)?):
                                Outcome := Structures.SetShape(Piece, Next, Revision)
                                if (Outcome = coach_build_outcome.Applied):
                                    set CoverChangedAt = GetSimulationElapsedTime()
                                    Confirmed := ConfirmWallAction(Training, Character, Structures, Piece, Generation, Encounter, Piece.Revision)
                                    if (not Confirmed?):
                                        return
            else if (Character.GetHealth() + Character.GetShield() < 140.0 and Now - LastSeenAt < 0.8):
                Generation := Training.Generation
                Encounter := Structures.Encounter
                Ready := PrepareBuildTool(Training, Character)
                defer:
                    if (Owner := Character.GetAgent[]):
                        Equipment.ReleaseConstruction(Owner)
                if (Ready? and Generation = Training.Generation and Encounter = Structures.Encounter and not Training.Closed? and not Training.Paused? and Training.Phase = coach_phase.Fighting and Character.IsActive[]):
                    Result := Structures.TryDefend(Character.GetTransform().Translation, LastSeenPosition)
                    if (Result(0) = coach_build_outcome.Applied, Piece := Result(1)?):
                        set OwnCover = option{Piece}
                        set CoverChangedAt = Now
                        Confirmed := ConfirmWallAction(Training, Character, Structures, Piece, Generation, Encounter, Piece.Revision)

    CoverActionCurrent(Training : coach_training_session, Character : fort_character, Structures : coach_structure_device, Piece : coach_live_piece, Generation : int, Encounter : int, Revision : int)<transacts>:logic =
        if (Ending? or Training.Closed? or Training.Paused? or Training.Phase <> coach_phase.Fighting or Generation <> Training.Generation or Encounter <> Structures.Encounter or Piece.Encounter <> Encounter or Piece.Revision <> Revision or not Piece.Prop.IsValid[] or not Structures.IsTrackedPiece(Piece)? or not Character.IsActive[]):
            return false
        if (not Structures.CombatReady()? or not Structures.PiecePlacementCurrent(Piece)?):
            return false
        return true

    WatchCoverAction(Training : coach_training_session, Character : fort_character, Structures : coach_structure_device, Piece : coach_live_piece, Generation : int, Encounter : int, Revision : int)<suspends>:void =
        loop:
            if (not CoverActionCurrent(Training, Character, Structures, Piece, Generation, Encounter, Revision)?):
                return
            Sleep(0.05)

    ConfirmWallAction(Training : coach_training_session, Character : fort_character, Structures : coach_structure_device, Piece : coach_live_piece, Generation : int, Encounter : int, Revision : int)<suspends>:logic =
        if (not CoverActionCurrent(Training, Character, Structures, Piece, Generation, Encounter, Revision)?):
            return false
        if (Piece.Kind <> coach_piece_kind.Wall):
            return true
        var Confirmed : logic = false
        race:
            block:
                set Confirmed = Structures.AwaitWallShape(Piece, Revision)
            WatchCoverAction(Training, Character, Structures, Piece, Generation, Encounter, Revision)
        return logic{Confirmed? and CoverActionCurrent(Training, Character, Structures, Piece, Generation, Encounter, Revision)?}

    PrepareWindowPosition(Training : coach_training_session, Character : fort_character, Actions : guard_actions_component, Structures : coach_structure_device, Piece : coach_live_piece, Generation : int, Encounter : int)<suspends>:logic =
        Revision := Piece.Revision
        if (not CoverActionCurrent(Training, Character, Structures, Piece, Generation, Encounter, Revision)? or Piece.Kind <> coach_piece_kind.Wall or Piece.Shape <> coach_piece_shape.Solid):
            return false
        Candidate := CoachWindowPeekPose(Piece.Position, Piece.Yaw, Character.GetTransform().Translation, Character.GetViewLocation(), LastSeenPosition)
        if (Pose := Candidate?):
            Limit := CoachArenaHalfExtent(coach_mode.Personal) - 160.0
            if (Abs(Pose.X) > Limit or Abs(Pose.Y) > Limit):
                return false
            var Reached : logic = false
            race:
                block:
                    Motion := Actions.NavigateTo(MakeNavigationTarget(Pose), ?MovementType := movement_type.Running, ?ReachRadius := 30.0, ?AllowPartialPath := false)
                    if (Motion.GetSuccess[], Distance(Character.GetTransform().Translation, Pose) < 75.0):
                        set Reached = true
                CoachFocusPointCompanion(Actions, LastSeenPosition)
                Sleep(1.3)
                WatchCoverAction(Training, Character, Structures, Piece, Generation, Encounter, Revision)
            Actions.StopNavigation()
            if (Reached? and CoverActionCurrent(Training, Character, Structures, Piece, Generation, Encounter, Revision)?):
                # Validate the actual view ray, rather than crediting a path
                # result whose reach radius left the eye below the sill.
                if (Owner := Character.GetAgent[], Equipment.BuildPlanEquipped(Owner)?, CoachWindowSightFits(Piece.Position, Piece.Yaw, Character.GetViewLocation(), LastSeenPosition)?):
                    return true
        return false

    # Opening a window is an action opportunity. Only fresh native sight may authorize the shot.
    TryCoverPeek(Runtime : coach_runtime, Training : coach_training_session, Character : fort_character, Actions : guard_actions_component)<suspends>:logic =
        if (Structures := Runtime.Structures?, Structures.CombatReady()?, Piece := OwnCover?, Piece.Prop.IsValid[], Piece.Encounter = Structures.Encounter):
            Now := GetSimulationElapsedTime()
            if (Now < CoverFireRetryAt or Now - CoverChangedAt < 0.7 or Now - LastSeenAt > 2.5 or Distance(Character.GetTransform().Translation, Piece.Position) > 700.0):
                return false
            Generation := Training.Generation
            Encounter := Structures.Encounter
            Ready := PrepareBuildTool(Training, Character, ?RequiresMaterials := false)
            if (not Ready?):
                return false
            defer:
                Actions.StopNavigation()
                if (Owner := Character.GetAgent[]):
                    Equipment.StopFiring(Owner)
                    Equipment.ReleaseConstruction(Owner)
            Positioned := PrepareWindowPosition(Training, Character, Actions, Structures, Piece, Generation, Encounter)
            if (not Positioned? or GetSimulationElapsedTime() - LastSeenAt > 3.0):
                return false
            Opened := Structures.SetShape(Piece, coach_piece_shape.Window, Piece.Revision)
            if (Opened <> coach_build_outcome.Applied):
                return false
            set CoverChangedAt = GetSimulationElapsedTime()
            OpenRevision := Piece.Revision
            Confirmed := ConfirmWallAction(Training, Character, Structures, Piece, Generation, Encounter, OpenRevision)
            if (not Confirmed?):
                ResetPeekCover(Training, Character, Structures, Piece, Generation, Encounter, OpenRevision)
                return true
            var WeaponReady : logic = false
            if (InventoryOwner := Character.GetAgent[]):
                set WeaponReady = Equipment.SelectWeapon(InventoryOwner, Distance(Character.GetTransform().Translation, LastSeenPosition))
                Equipment.ConfigureAim(InventoryOwner, Training.Challenge)
            if (not WeaponReady?):
                ResetPeekCover(Training, Character, Structures, Piece, Generation, Encounter, OpenRevision)
                return true
            race:
                Sleep(0.14 + (1.0 - Training.Challenge) * 0.15)
                WatchCoverAction(Training, Character, Structures, Piece, Generation, Encounter, OpenRevision)
            if (not CoverActionCurrent(Training, Character, Structures, Piece, Generation, Encounter, OpenRevision)?):
                return true
            var Opportunity : ?coach_fire_cadence = false
            race:
                block:
                    set Opportunity = FireVisibleBurst(Training, Character, Actions, ?ShortOpening := true)
                WatchCoverAction(Training, Character, Structures, Piece, Generation, Encounter, OpenRevision)
            ReleaseOwnedHold(Actions, "cover_action_window")
            if (Owner := Character.GetAgent[]):
                Equipment.StopFiring(Owner)
            if (not CoverActionCurrent(Training, Character, Structures, Piece, Generation, Encounter, OpenRevision)?):
                return true
            ResetPeekCover(Training, Character, Structures, Piece, Generation, Encounter, OpenRevision)
            if (not Opportunity?, Generation = Training.Generation, Owner := Character.GetAgent[]):
                set CoverFireRetryAt = GetSimulationElapsedTime() + Equipment.WeaponStartupAllowance(Owner, false)
            if (Cadence := Opportunity?):
                race:
                    Sleep(Cadence.Recovery)
                    WatchCancellation(Training, Generation, Character, false)
            return true
        return false

    ResetPeekCover(Training : coach_training_session, Character : fort_character, Structures : coach_structure_device, Piece : coach_live_piece, Generation : int, Encounter : int, Revision : int)<suspends>:void =
        if (not CoverActionCurrent(Training, Character, Structures, Piece, Generation, Encounter, Revision)? or Piece.Shape <> coach_piece_shape.Window):
            return
        Ready := PrepareBuildTool(Training, Character, ?RequiresMaterials := false)
        if (Ready?):
            defer:
                if (Owner := Character.GetAgent[]):
                    Equipment.ReleaseConstruction(Owner)
            if (CoverActionCurrent(Training, Character, Structures, Piece, Generation, Encounter, Revision)?, Piece.Shape = coach_piece_shape.Window):
                Closed := Structures.SetShape(Piece, coach_piece_shape.Solid, Revision)
                if (Closed = coach_build_outcome.Applied):
                    set CoverChangedAt = GetSimulationElapsedTime()
                    Confirmed := ConfirmWallAction(Training, Character, Structures, Piece, Generation, Encounter, Piece.Revision)

    WatchRangedEquipment(Character : fort_character, Role : coach_weapon_role)<suspends>:void =
        loop:
            if (Owner := Character.GetAgent[]):
                if (not Equipment.RangedReady(Owner)? or Equipment.CurrentWeaponRole(Owner) <> Role):
                    return
            else:
                return
            Sleep(0.03)

    # This requests a bounded native attack opportunity, never a reported shot
    # count. Only the actual damage pipeline can credit a hit to the learner.
    FireVisibleBurst(Training : coach_training_session, Character : fort_character, Actions : guard_actions_component, ?ShortOpening : logic = false, ?GroundTactic : ?coach_tactic = false)<suspends>:?coach_fire_cadence =
        Ticket := Training.Generation
        if (Observed := VisibleTrainingTarget(Training)?, Owner := Character.GetAgent[]):
            Range := Distance(Character.GetTransform().Translation, FromVector3(Observed.LastKnownPosition))
            Selected := Equipment.SelectWeapon(Owner, Range)
            if (not Selected?):
                return false
            Equipment.ConfigureAim(Owner, Training.Challenge)
            Sleep(0.08)
            if (Ending? or Training.Paused? or Ticket <> Training.Generation or not Character.IsActive[] or not Equipment.RangedReady(Owner)?):
                return false
            if (Current := VisibleTrainingTarget(Training)?):
                set LastSeenAt = GetSimulationElapsedTime()
                set LastSeenPosition = FromVector3(Current.LastKnownPosition)
                Cadence := Equipment.FireCadence(Owner, Training.Challenge, Training.Style)
                var FireDestination : ?vector3 = false
                if (not ShortOpening?, Cadence.Role = coach_weapon_role.Rifle, MotionTactic := GroundTactic?, MotionTactic <> coach_tactic.HoldAngle, not Character.IsInAir[], Range > 600.0 and Range < 2200.0):
                    set FireDestination = PlanGroundFireMotion(Training, Character, LastSeenPosition, MotionTactic)
                var HasNativeFeedback : logic = false
                if (State := Equipment.NativeFiringState(Owner)?):
                    set HasNativeFeedback = true
                var ObservedFiring : logic = false
                DamageBefore := Training.IncomingDamage
                defer:
                    ReleaseOwnedHold(Actions, "burst_scope")
                    Actions.StopNavigation()
                    Equipment.StopFiring(Owner)
                if (HasNativeFeedback?):
                    Allowance := Equipment.WeaponStartupAllowance(Owner, ShortOpening)
                    Training.Tactics.IncludeWeaponStartup(Allowance)
                    BeganAt := GetSimulationElapsedTime()
                    SurvivalBefore := Character.GetHealth() + Character.GetShield()
                    var FirstFireAt : float = -1.0
                    race:
                        FireAttackWindow(Actions, Character, Current.Target, Allowance + Cadence.Pulse + 0.1, FireDestination)
                        block:
                            loop:
                                Now := GetSimulationElapsedTime()
                                if (Firing := Equipment.NativeFiringState(Owner)?, Firing?):
                                    set ObservedFiring = true
                                    if (FirstFireAt < 0.0):
                                        set FirstFireAt = Now
                                if (FirstFireAt >= 0.0):
                                    if (Now - FirstFireAt >= Cadence.Pulse):
                                        break
                                else if (Now - BeganAt >= Allowance or SurvivalBefore - Character.GetHealth() - Character.GetShield() >= 40.0):
                                    break
                                Sleep(0.02)
                        WatchCancellation(Training, Ticket, Character, option{Current})
                        WatchRangedEquipment(Character, Cadence.Role)
                else:
                    race:
                        FireAttackWindow(Actions, Character, Current.Target, Cadence.Pulse, FireDestination)
                        WatchCancellation(Training, Ticket, Character, option{Current})
                        WatchRangedEquipment(Character, Cadence.Role)
                # Explicit parent release complements cleanup when an enclosing race cancels.
                ReleaseOwnedHold(Actions, "observed_burst_window")
                Actions.StopNavigation()
                Equipment.StopFiring(Owner)
                if (HasNativeFeedback? and not ObservedFiring? and Training.IncomingDamage <= DamageBefore):
                    Print("PCL|opponent|attack_window_without_observed_fire|reload_and_magazine_unknown", ?Duration := 0.0)
                    return false
                return option{Cadence}
        return false

    RecoverAfterBurst(Tactic : coach_tactic, Training : coach_training_session, Character : fort_character, Actions : guard_actions_component, Cadence : coach_fire_cadence)<suspends>:void =
        Ticket := Training.Generation
        defer:
            Actions.StopNavigation()
        if (Tactic <> coach_tactic.HoldAngle, not Character.IsInAir[], Current := VisibleTrainingTarget(Training)?):
            Position := Character.GetTransform().Translation
            Delta := FromVector3(Current.LastKnownPosition) - Position
            if (Forward := vector3{X := Delta.X, Y := Delta.Y}.MakeUnitVector[]):
                UpdateCombatSide(Training)
                Right := vector3{X := -Forward.Y, Y := Forward.X}
                Travel := Clamp(Cadence.Recovery * 450.0, 60.0, 180.0)
                var Destination : vector3 = Position + Right * RecoverySide * Travel
                if (Tactic = coach_tactic.Disengage):
                    set Destination = Destination - Forward * Travel * 0.6
                Limit := CoachArenaHalfExtent(coach_mode.Personal) - 160.0
                set Destination.X = Clamp(Destination.X, -Limit, Limit)
                set Destination.Y = Clamp(Destination.Y, -Limit, Limit)
                race:
                    block:
                        Motion := Actions.NavigateTo(MakeNavigationTarget(Destination), ?MovementType := movement_type.Running, ?ReachRadius := 35.0, ?AllowPartialPath := true)
                        loop:
                            Sleep(0.05)
                    CoachFocusCompanion(Actions, Current.Target)
                    Sleep(Cadence.Recovery)
                    WatchCancellation(Training, Ticket, Character, option{Current})
                return
        race:
            Sleep(Cadence.Recovery)
            WatchCancellation(Training, Ticket, Character, false)

    HoldAttack(Actions : guard_actions_component, Character : fort_character, Target : entity, Duration : float)<suspends>:void =
        set HoldPending = true
        CoachHoldAttackWindow(Actions, Character, Target, Duration)

    UpdateCombatSide(Training : coach_training_session):void =
        Now := GetSimulationElapsedTime()
        if (Now - RecoverySideAt > 1.2 - Training.Challenge * 0.5):
            set RecoverySide = 1.0
            if (Training.Habits.Confidence() > 0.25):
                if (Training.Habits.LeftProbability() > 0.5):
                    set RecoverySide = -1.0
            else if (GetRandomFloat(0.0, 1.0) < 0.5):
                set RecoverySide = -1.0
            set RecoverySideAt = Now

    PlanGroundFireMotion(Training : coach_training_session, Character : fort_character, TargetPosition : vector3, Tactic : coach_tactic):?vector3 =
        Position := Character.GetTransform().Translation
        Delta := TargetPosition - Position
        if (Forward := vector3{X := Delta.X, Y := Delta.Y}.MakeUnitVector[]):
            UpdateCombatSide(Training)
            Right := vector3{X := -Forward.Y, Y := Forward.X}
            Travel := 100.0 + 60.0 * Clamp(Training.Challenge, 0.0, 1.0)
            var Destination : vector3 = Position + Right * RecoverySide * Travel
            if (Tactic = coach_tactic.Disengage):
                set Destination = Destination - Forward * Travel * 0.6
            Limit := CoachArenaHalfExtent(coach_mode.Personal) - 160.0
            set Destination.X = Clamp(Destination.X, -Limit, Limit)
            set Destination.Y = Clamp(Destination.Y, -Limit, Limit)
            if (Distance(Destination, Position) > 60.0):
                return option{Destination}
        return false

    FireAttackWindow(Actions : guard_actions_component, Character : fort_character, Target : entity, Duration : float, Destination : ?vector3)<suspends>:void =
        if (Position := Destination?):
            ReleaseOwnedHold(Actions, "ground_fire_motion")
            defer:
                Actions.StopNavigation()
            race:
                CoachFocusCompanion(Actions, Target)
                block:
                    Requested := Actions.Attack(Target)
                    loop:
                        Sleep(0.1)
                block:
                    Motion := Actions.NavigateTo(MakeNavigationTarget(Position), ?MovementType := movement_type.Running, ?ReachRadius := 35.0, ?AllowPartialPath := true)
                    # Early completion of one native request cannot end the fire window.
                    loop:
                        Sleep(0.1)
                Sleep(Duration)
        else:
            HoldAttack(Actions, Character, Target, Duration)

    ReleaseOwnedHold(Actions : guard_actions_component, Scope : string):void =
        if (HoldPending?):
            set HoldPending = false
            CoachReleaseHold(Actions, Scope)

    PrepareBuildTool(Training : coach_training_session, Character : fort_character, ?RequiresMaterials : logic = true)<suspends>:logic =
        Ticket := Training.Generation
        if (InventoryOwner := Character.GetAgent[]):
            if (RequiresMaterials?, not Equipment.CanAffordWood(InventoryOwner, 10)?):
                return false
            Held := Equipment.EquipBuildPlan(InventoryOwner)
            if (Held?):
                Sleep(0.12)
                if (not Ending?, Character.IsActive[], not Training.Paused?, Training.Phase = coach_phase.Fighting, Training.Generation = Ticket, Equipment.BuildPlanEquipped(InventoryOwner)?):
                    return true
            Equipment.ReleaseConstruction(InventoryOwner)
        return false

    SelectTactic(Training : coach_training_session, Character : fort_character)<transacts>:coach_tactic =
        Range := Distance(Character.GetTransform().Translation, LastSeenPosition)
        var AscentReady : logic = false
        var BoxReady : logic = false
        if (Runtime := CoachRuntime[GetSession()], Structures := Runtime.Structures?, Structures.CombatReady()? ):
            Position := Character.GetTransform().Translation
            Now := GetSimulationElapsedTime()
            if (Structures.PlanAvailability(CoachAscentPlan(Position, LastSeenPosition), Structures.Encounter) = coach_build_outcome.Applied, AscentRetry.Ready(Training.Generation, Structures.Encounter, Position, LastSeenPosition, Now)?):
                set AscentReady = true
            if (Structures.PlanAvailability(CoachBoxPlan(Position, LastSeenPosition), Structures.Encounter) = coach_build_outcome.Applied, BoxRetry.Ready(Training.Generation, Structures.Encounter, Position, LastSeenPosition, Now)?):
                set BoxReady = true
        if (Character.GetHealth() + Character.GetShield() < 60.0 and Range < 1600.0):
            return coach_tactic.Disengage
        if (Character.GetHealth() + Character.GetShield() < 100.0 and Range < 1600.0):
            if (BoxReady?):
                return coach_tactic.DefensiveBox
            return coach_tactic.Disengage
        if (AscentReady?, LastSeenPosition.Z - Character.GetTransform().Translation.Z > 250.0 and Range < 1800.0):
            return coach_tactic.GainHeight
        if (Range > 1800.0):
            return coach_tactic.CloseDistance
        Context := CoachTacticContext(Range, LastSeenPosition.Z - Character.GetTransform().Translation.Z)
        UnderPressure := logic{Character.GetHealth() + Character.GetShield() < 145.0}
        return Training.Tactics.Choose(Context, Range, Training.Style, Training.HumanPatterns.Confidence(), Training.Habits.Confidence(), ?AscentReady := AscentReady, ?BoxReady := BoxReady, ?UnderPressure := UnderPressure)

    ExecuteVisibleTactic(Tactic : coach_tactic, Training : coach_training_session, Character : fort_character, Actions : guard_actions_component, Info : npc_target_info)<suspends>:void =
        Ticket := Training.Generation
        var StructureEncounter : int = -1
        if (Runtime := CoachRuntime[GetSession()], Structures := Runtime.Structures?):
            set StructureEncounter = Structures.Encounter
        if (Tactic = coach_tactic.GainHeight):
            Ascended := AscendTowardLastSeen(Training, Character, Actions)
            if (Ascended?):
                AscentRetry.Clear()
                EngageAfterConstruction(Training, Character, Actions)
                return
            Training.Tactics.Cancel()
            RememberBuildFailure(Training, Character, AscentRetry, Ticket, StructureEncounter)
            RecoverFailedConstruction(coach_tactic.ChangeAngle, Training, Character, Actions, Ticket)
            return
        if (Tactic = coach_tactic.DefensiveBox):
            Protected := BuildDefensiveBox(Training, Character, Actions)
            if (Protected?):
                BoxRetry.Clear()
                EngageAfterConstruction(Training, Character, Actions)
                return
            Training.Tactics.Cancel()
            RememberBuildFailure(Training, Character, BoxRetry, Ticket, StructureEncounter)
            RecoverFailedConstruction(coach_tactic.Disengage, Training, Character, Actions, Ticket)
            return
        if (Tactic = coach_tactic.LearnedMovement and Training.HumanPatterns.Crouch > 0.45):
            set CrouchIntent = true
            race:
                ExecuteGroundTactic(Tactic, Training, Character, Actions, Info)
                block:
                    Stance := Actions.Crouch()
                    loop:
                        Sleep(0.25)
        else:
            ExecuteGroundTactic(Tactic, Training, Character, Actions, Info)

    RememberBuildFailure(Training : coach_training_session, Character : fort_character, Retry : coach_build_retry_state, Ticket : int, StructureEncounter : int):void =
        if (not Ending?, not Training.Closed?, not Training.Paused?, Training.Phase = coach_phase.Fighting, Training.Generation = Ticket, Character.IsActive[], Runtime := CoachRuntime[GetSession()], Structures := Runtime.Structures?, Structures.Encounter = StructureEncounter):
            Retry.RecordFailure(Ticket, StructureEncounter, Character.GetTransform().Translation, LastSeenPosition, GetSimulationElapsedTime())
            Print("PCL|opponent|construction_replan|failures={Retry.Failures}|local_retry_backoff", ?Duration := 0.0)

    RecoverFailedConstruction(Fallback : coach_tactic, Training : coach_training_session, Character : fort_character, Actions : guard_actions_component, Ticket : int)<suspends>:void =
        # A fallback is a different action, never a successful sample for the failed skill.
        if (Training.Generation = Ticket, not Ending?, Character.IsActive[], Current := VisibleTrainingTarget(Training)?):
            set LastSeenAt = GetSimulationElapsedTime()
            set LastSeenPosition = FromVector3(Current.LastKnownPosition)
            race:
                ExecuteGroundTactic(Fallback, Training, Character, Actions, Current)
                WatchCancellation(Training, Ticket, Character, option{Current})
            ReleaseOwnedHold(Actions, "construction_replan")
            Actions.StopNavigation()

    EngageAfterConstruction(Training : coach_training_session, Character : fort_character, Actions : guard_actions_component)<suspends>:void =
        Ticket := Training.Generation
        defer:
            Actions.StopNavigation()
            if (Owner := Character.GetAgent[]):
                Equipment.StopFiring(Owner)
        if (Ending? or Training.Closed? or Training.Paused? or Training.Phase <> coach_phase.Fighting or not Character.IsActive[]):
            return
        # A closed box may hide the trainee. Its last observed position may
        # plan an opening, but only reacquired native sight can authorize fire.
        if (Observed := VisibleTrainingTarget(Training)?):
            set LastSeenAt = GetSimulationElapsedTime()
            set LastSeenPosition = FromVector3(Observed.LastKnownPosition)
        race:
            block:
                var Peeked : logic = false
                if (Runtime := CoachRuntime[GetSession()]):
                    set Peeked = TryCoverPeek(Runtime, Training, Character, Actions)
                if (not Peeked?, Current := VisibleTrainingTarget(Training)?):
                    set LastSeenAt = GetSimulationElapsedTime()
                    set LastSeenPosition = FromVector3(Current.LastKnownPosition)
                    Opportunity := FireVisibleBurst(Training, Character, Actions)
                    if (Cadence := Opportunity?):
                        RecoverAfterBurst(coach_tactic.HoldAngle, Training, Character, Actions, Cadence)
            Sleep(3.0)
            WatchCancellation(Training, Ticket, Character, false)

    GroundDetourNeeded(Training : coach_training_session, Position : vector3, Threat : vector3)<transacts>:logic =
        if (StalledAttempts > 0 and StalledGeneration = Training.Generation and GetSimulationElapsedTime() - StalledAt < 6.0 and Distance(Position, StalledBody) < 256.0 and Distance(Threat, StalledThreat) < 512.0):
            return true
        return false

    RememberGroundRoute(Training : coach_training_session, Character : fort_character, Ticket : int, StartedAt : float, Start : vector3, Goal : vector3, Threat : vector3, Rejected : logic, Interrupted : logic):void =
        if (Interrupted? or Ending? or Training.Closed? or Training.Paused? or Training.Phase <> coach_phase.Fighting or Training.Generation <> Ticket or not Character.IsActive[]):
            return
        if (Current := VisibleTrainingTarget(Training)?):
            ObservedPosition := FromVector3(Current.LastKnownPosition)
            Position := Character.GetTransform().Translation
            if (Distance(ObservedPosition, Threat) >= 512.0):
                return
            var LittleProgress : logic = false
            if (GetSimulationElapsedTime() - StartedAt >= 0.35 and Distance(Position, Start) < 60.0):
                set LittleProgress = true
            if (Distance(Position, Goal) > 135.0 and (Rejected? or LittleProgress?)):
                if (not GroundDetourNeeded(Training, Position, ObservedPosition)?):
                    set StalledAttempts = 0
                # Cycle both sides without getting pinned to a saturated counter.
                if (StalledAttempts = 1):
                    set StalledAttempts = 2
                else:
                    set StalledAttempts = 1
                set StalledGeneration = Ticket
                set StalledAt = GetSimulationElapsedTime()
                set StalledBody = Position
                set StalledThreat = ObservedPosition
                # Failed movement is not a completed tactical exchange.
                Training.Tactics.Cancel()
            else if (Distance(Position, Goal) <= 135.0 or Distance(Position, Start) >= 60.0):
                set StalledAttempts = 0

    ExecuteGroundTactic(Tactic : coach_tactic, Training : coach_training_session, Character : fort_character, Actions : guard_actions_component, Info : npc_target_info)<suspends>:void =
        Ticket := Training.Generation
        defer:
            Actions.StopNavigation()
            if (Owner := Character.GetAgent[]):
                Equipment.StopFiring(Owner)
        Position := Character.GetTransform().Translation
        Delta := LastSeenPosition - Position
        var WeaponReady : logic = false
        if (InventoryOwner := Character.GetAgent[]):
            set WeaponReady = Equipment.SelectWeapon(InventoryOwner, Distance(Position, LastSeenPosition))
            Equipment.ConfigureAim(InventoryOwner, Training.Challenge)
        if (not WeaponReady?):
            return
        if (Direction := vector3{X := Delta.X, Y := Delta.Y}.MakeUnitVector[]):
            var Destination : vector3 = Position
            var Move : logic = false
            if (Tactic = coach_tactic.CloseDistance or Tactic = coach_tactic.GainHeight):
                set Destination = Position + Direction * 450.0
                if (LastSeenPosition.Z > Position.Z + 120.0):
                    set Destination.Z = Min(LastSeenPosition.Z, Position.Z + 384.0)
                set Move = true
            else if (Tactic = coach_tactic.Disengage):
                set Destination = Position - Direction * 450.0
                set Move = true
            else if (Tactic = coach_tactic.ChangeAngle):
                var Side : float = 1.0
                if (Training.Habits.Confidence() > 0.25):
                    if (Training.Habits.LeftProbability() > 0.5):
                        set Side = -1.0
                else if (GetRandomFloat(0.0, 1.0) < 0.5):
                    set Side = -1.0
                set Destination = Position + vector3{X := -Direction.Y, Y := Direction.X} * (Side * 320.0)
                set Move = true
            else if (Tactic = coach_tactic.LearnedMovement):
                Pattern := Training.HumanPatterns
                Right := vector3{X := -Direction.Y, Y := Direction.X}
                set Destination = Position + Direction * Clamp(Pattern.Forward * 0.4, -280.0, 280.0) + Right * Clamp(Pattern.Lateral * 0.4, -280.0, 280.0)
                set Move = true
            if (Move?):
                ThreatAnchor := LastSeenPosition
                if (GroundDetourNeeded(Training, Position, ThreatAnchor)?):
                    var Side : float = -1.0
                    if (StalledAttempts = 2):
                        set Side = 1.0
                    Right := vector3{X := -Direction.Y, Y := Direction.X}
                    set Destination = Position + Right * Side * 320.0
                    if (Tactic = coach_tactic.Disengage):
                        set Destination = Destination - Direction * 180.0
                    else if (Tactic = coach_tactic.CloseDistance):
                        set Destination = Destination + Direction * 120.0
                Limit := CoachArenaHalfExtent(coach_mode.Personal) - 160.0
                set Destination.X = Clamp(Destination.X, -Limit, Limit)
                set Destination.Y = Clamp(Destination.Y, -Limit, Limit)
                StartedAt := GetSimulationElapsedTime()
                var RouteRejected : logic = false
                var RouteInterrupted : logic = false
                race:
                    block:
                        Outcome := Actions.NavigateTo(MakeNavigationTarget(Destination), ?MovementType := movement_type.Running, ?ReachRadius := 80.0, ?AllowPartialPath := true)
                        if (Success := Outcome.GetSuccess[]):
                            if (Success = navigation_action_success_type.PartiallyReached):
                                set RouteRejected = true
                        else if (Error := Outcome.GetError[]):
                            if (Error = navigation_action_error_type.Interrupted):
                                set RouteInterrupted = true
                            else if (Error = navigation_action_error_type.Blocked or Error = navigation_action_error_type.Unreachable or Error = navigation_action_error_type.Invalid):
                                set RouteRejected = true
                    CoachFocusCompanion(Actions, Info.Target)
                    Sleep(0.7)
                    block:
                        if (Destination.Z > Position.Z + 120.0, not Character.IsInAir[]):
                            Sleep(0.08)
                            Jumped := Actions.Jump()
                        loop:
                            Sleep(0.1)
                Actions.StopNavigation()
                RememberGroundRoute(Training, Character, Ticket, StartedAt, Position, Destination, ThreatAnchor, RouteRejected, RouteInterrupted)
        Opportunity := FireVisibleBurst(Training, Character, Actions, ?GroundTactic := option{Tactic})
        if (Cadence := Opportunity?):
            RecoverAfterBurst(Tactic, Training, Character, Actions, Cadence)
        else:
            Training.Tactics.Cancel()

    BuildSkillCurrent(Training : coach_training_session, Character : fort_character, Structures : coach_structure_device, State : coach_build_skill_state)<transacts>:logic =
        if (Ending? or Training.Closed? or Training.Paused? or Training.Phase <> coach_phase.Fighting or State.Generation <> Training.Generation or State.Encounter <> Structures.Encounter or not Character.IsActive[] or GetSimulationElapsedTime() - State.StartedAt > 8.0 or GetSimulationElapsedTime() - LastSeenAt > 6.0):
            return false
        if (Distance(LastSeenPosition, State.ThreatAnchor) > 1024.0):
            return false
        if (Cell := State.InteriorCell?, not CoachBoxContainsBody(Cell, Character.GetTransform().Translation)?):
            return false
        if (Owner := Character.GetAgent[], Equipment.BuildPlanEquipped(Owner)?):
            for (Slot -> Binding : State.Pieces):
                if (not Structures.PiecePlacementCurrent(Binding.Piece)? or not Structures.IsTrackedPiece(Binding.Piece)? or Binding.Piece.Encounter <> State.Encounter or Binding.Piece.Revision <> Binding.ExpectedRevision):
                    return false
            return true
        return false

    WatchBuildSkill(Training : coach_training_session, Character : fort_character, Structures : coach_structure_device, State : coach_build_skill_state)<suspends>:void =
        loop:
            if (not BuildSkillCurrent(Training, Character, Structures, State)?):
                return
            Sleep(0.05)

    ExecuteBuildPlan(Training : coach_training_session, Character : fort_character, Actions : guard_actions_component, Structures : coach_structure_device, Steps : []coach_build_step, Skill : string, ?InteriorCell : ?vector3 = false)<suspends>:logic =
        if (Structures.PlanAvailability(Steps, Structures.Encounter) <> coach_build_outcome.Applied):
            return false
        Limit := CoachArenaHalfExtent(coach_mode.Personal) - 320.0
        for (Step : Steps):
            if (Abs(Step.Position.X) > Limit or Abs(Step.Position.Y) > Limit or Step.Position.Z < 0.0 or Step.Position.Z + 384.0 > CoachArenaCeiling()):
                return false
        State := coach_build_skill_state{Generation := Training.Generation, Encounter := Structures.Encounter, StartedAt := GetSimulationElapsedTime(), ThreatAnchor := LastSeenPosition}
        Ready := PrepareBuildTool(Training, Character, ?RequiresMaterials := false)
        if (not Ready?):
            return false
        defer:
            Actions.StopNavigation()
            if (Owner := Character.GetAgent[]):
                Equipment.ReleaseConstruction(Owner)
        Interval := 0.34 - Training.Challenge * 0.18
        for (Index -> Step : Steps):
            if (not BuildSkillCurrent(Training, Character, Structures, State)?):
                return false
            if (Step.Operation = coach_build_step_kind.Move):
                var Reached : logic = false
                race:
                    block:
                        Motion := Actions.NavigateTo(MakeNavigationTarget(Step.Position), ?MovementType := movement_type.Running, ?ReachRadius := 55.0, ?AllowPartialPath := false)
                        if (Motion.GetSuccess[], Distance(Character.GetTransform().Translation, Step.Position) < 135.0):
                            set Reached = true
                    Sleep(Step.Timeout)
                    WatchBuildSkill(Training, Character, Structures, State)
                Actions.StopNavigation()
                if (not Reached? or not BuildSkillCurrent(Training, Character, Structures, State)?):
                    return false
                if (Cell := InteriorCell?):
                    if (not CoachBoxContainsBody(Cell, Character.GetTransform().Translation)?):
                        return false
                    set State.InteriorCell = option{Cell}
            else:
                # Turn toward the actual piece while holding the plan. A focus
                # callback returning never ends the preparation interval early.
                race:
                    CoachFocusPointCompanion(Actions, Step.Position + vector3{Z := 100.0})
                    Sleep(Interval)
                    WatchBuildSkill(Training, Character, Structures, State)
                if (not BuildSkillCurrent(Training, Character, Structures, State)?):
                    return false
                if (Step.Operation = coach_build_step_kind.Place):
                    var Owned : ?coach_live_piece = Structures.FindOwnedPiece(Step.Kind, Step.Position, Step.Yaw, State.Encounter)
                    if (not Owned?):
                        Result := Structures.TryPlace(Step.Kind, Step.Position, Step.Yaw, State.Encounter, Interval)
                        if (Result(0) <> coach_build_outcome.Applied):
                            return false
                        set Owned = Result(1)
                    if (Piece := Owned?):
                        if (Step.MustBeSolid?, Piece.Shape <> coach_piece_shape.Solid):
                            Reset := Structures.SetShape(Piece, coach_piece_shape.Solid, Piece.Revision)
                            if (Reset <> coach_build_outcome.Applied):
                                return false
                        Binding := coach_skill_piece{Piece := Piece, ExpectedRevision := Piece.Revision}
                        if (set State.Pieces[Step.Slot] = Binding) {}
                        else:
                            return false
                        Confirmed := ConfirmWallAction(Training, Character, Structures, Piece, State.Generation, State.Encounter, Binding.ExpectedRevision)
                        if (not Confirmed?):
                            return false
                    else:
                        return false
                else if (Binding := State.Pieces[Step.Slot]):
                    Edited := Structures.SetShape(Binding.Piece, Step.Shape, Binding.ExpectedRevision)
                    if (Edited <> coach_build_outcome.Applied):
                        return false
                    set Binding.ExpectedRevision = Binding.Piece.Revision
                    Confirmed := ConfirmWallAction(Training, Character, Structures, Binding.Piece, State.Generation, State.Encounter, Binding.ExpectedRevision)
                    if (not Confirmed?):
                        return false
                else:
                    return false
            Print("PCL|opponent|build_skill_step_applied|skill={Skill}|step={Index}|native_semantics_acceptance_pending", ?Duration := 0.0)
        return BuildSkillCurrent(Training, Character, Structures, State)

    AscendTowardLastSeen(Training : coach_training_session, Character : fort_character, Actions : guard_actions_component)<suspends>:logic =
        if (Runtime := CoachRuntime[GetSession()], Structures := Runtime.Structures?, Structures.CombatReady()?):
            Position := Character.GetTransform().Translation
            return ExecuteBuildPlan(Training, Character, Actions, Structures, CoachAscentPlan(Position, LastSeenPosition), "protected_ascent")
        return false

    BuildDefensiveBox(Training : coach_training_session, Character : fort_character, Actions : guard_actions_component)<suspends>:logic =
        if (Runtime := CoachRuntime[GetSession()], Structures := Runtime.Structures?, Structures.CombatReady()? and GetSimulationElapsedTime() - LastSeenAt < 2.0):
            Position := Character.GetTransform().Translation
            if (Cell := CoachBuildCell(Position)?):
                Encounter := Structures.Encounter
                Plan := CoachBoxPlan(Position, LastSeenPosition)
                Built := ExecuteBuildPlan(Training, Character, Actions, Structures, Plan, "defensive_box", ?InteriorCell := option{Cell})
                if (not Built? or Encounter <> Structures.Encounter or not CoachBoxContainsBody(Cell, Character.GetTransform().Translation)?):
                    return false
                # Commit the new cover only after all four walls and the roof
                # remain live, solid and tracked in this exact encounter.
                var SolidParts : int = 0
                var NextCover : ?coach_live_piece = false
                var BestThreatAlignment : float = -1.0
                ThreatDelta := LastSeenPosition - Cell
                var ThreatDirection : vector3 = vector3{}
                if (Direction := vector3{X := ThreatDelta.X, Y := ThreatDelta.Y}.MakeUnitVector[]):
                    set ThreatDirection = Direction
                for (Step : Plan, Step.Operation = coach_build_step_kind.Place):
                    if (Piece := Structures.FindOwnedPiece(Step.Kind, Step.Position, Step.Yaw, Encounter)?):
                        if (Piece.Shape <> coach_piece_shape.Solid):
                            return false
                        set SolidParts += 1
                        if (Step.Kind = coach_piece_kind.Wall):
                            Alignment := DotProduct((Step.Position - Cell) / 256.0, ThreatDirection)
                            if (Alignment > BestThreatAlignment):
                                set BestThreatAlignment = Alignment
                                set NextCover = option{Piece}
                    else:
                        return false
                if (SolidParts = 5, Cover := NextCover?):
                    set OwnCover = option{Cover}
                    set CoverChangedAt = GetSimulationElapsedTime()
                    return true
        return false

    WatchCancellation(Training : coach_training_session, Ticket : int, Character : fort_character, Target : ?npc_target_info)<suspends>:void =
        loop:
            if (Ending? or Training.Closed? or Training.Paused? or Ticket <> Training.Generation or Training.Phase <> coach_phase.Fighting or not Character.IsActive[]):
                return
            Observation := VisibleTrainingTarget(Training)
            if (Current := Observation?):
                set LastSeenAt = GetSimulationElapsedTime()
                set LastSeenPosition = FromVector3(Current.LastKnownPosition)
            else if (Target?):
                return
            Sleep(0.05)
