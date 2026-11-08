using { /Fortnite.com/Characters }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }

# Round completion owns its restart task. Menus, mode changes and new generations cancel it.
coach_personal_round_flow := class:
    RestartDelay : float = 3.0

    Cancel(Training : coach_training_session):void =
        set Training.AwaitingNextRound = false
        set Training.NextRoundAt = -1.0

    Finish(Portal : coach_portal_device, Training : coach_training_session, Won : logic):void =
        if (Training.Phase <> coach_phase.Fighting or Training.Closed?):
            return
        Training.FinishRound(Won)
        set Training.LastRoundWon = Won
        ScheduleRestart(Portal, Training)
        if (Voice := Training.VoiceLink?):
            Voice.RoundResult(Won)
        Print("PCL|round_flow|result|generation={Training.Generation}|modal=0|restart_seconds={RestartDelay}", ?Duration := 0.0)

    Interrupt(Portal : coach_portal_device, Training : coach_training_session):void =
        if (Training.Phase <> coach_phase.Fighting or Training.Closed?):
            return
        Training.InterruptRound()
        ScheduleRestart(Portal, Training)
        if (View := Portal.Views[Training.Owner]):
            View.SetCaption(CoachLanguage("Round interrupted. No win or loss recorded.", "הסיבוב נקטע. לא נרשם ניצחון או הפסד.", Training.HebrewText))
        Print("PCL|round_flow|interrupted|generation={Training.Generation}|scored=0|modal=0", ?Duration := 0.0)

    ScheduleRestart(Portal : coach_portal_device, Training : coach_training_session):void =
        set Training.AwaitingNextRound = true
        set Training.NextRoundAt = GetSimulationElapsedTime() + RestartDelay
        if (Character := Training.Owner.GetFortCharacter[], Character.IsActive[]):
            Character.SetVulnerability(false)
        if (Character := Portal.Opponent?, Character.IsActive[]):
            Character.PutInStasis(stasis_args{AllowTurning := false, AllowFalling := true})
            Character.SetVulnerability(false)
        if (View := Portal.Views[Training.Owner]):
            View.CloseMenu()
            View.UpdateHUD(Training)
        spawn { RestartWhenReady(Portal, Training, Training.Generation) }

    RestartWhenReady(Portal : coach_portal_device, Training : coach_training_session, Ticket : int)<suspends>:void =
        Sleep(RestartDelay)
        # Wait for a fresh character after a loss; do not start another fight against a dead body.
        for (Attempt := 0..119):
            if (Portal.Ending? or Training.Closed? or Training.Generation <> Ticket or Training.Mode <> coach_mode.Personal or Training.Phase <> coach_phase.Review or not Training.AwaitingNextRound?):
                return
            if (View := Portal.Views[Training.Owner], View.Menu?):
                Cancel(Training)
                return
            if (Training.Owner.IsActive[], Character := Training.Owner.GetFortCharacter[], Character.IsActive[]):
                Cancel(Training)
                Print("PCL|round_flow|restart|generation={Ticket}|respawn_wait={Attempt}", ?Duration := 0.0)
                Plan := Training.Profile.TrainingPlan
                if (Training.LastRoundInterrupted?, Plan.Stage = 3, Training.PlanApplicationRevision = Plan.Revision):
                    Portal.StartPersonal(Training.Owner, ?PreserveExercise := true, ?PlanRevision := Plan.Revision, ?PlanApplication := true)
                else:
                    Portal.StartPersonal(Training.Owner, ?PreserveExercise := true)
                return
            Sleep(0.1)
        Cancel(Training)
        Print("PCL|round_flow|restart_wait_expired|manual_continue_available", ?Duration := 0.0)
