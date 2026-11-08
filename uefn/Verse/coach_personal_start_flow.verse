using { /Fortnite.com/Characters }
using { /Fortnite.com/Devices }
using { /Fortnite.com/Playspaces }
using { /Fortnite.com/Teams }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/SpatialMath }

# Preparation owns its generation; a cancelled request never unlocks a new round.
coach_personal_start_flow := class:
    var Countdown : int = 0

    Current(Portal : coach_portal_device, Training : coach_training_session, Ticket : int)<transacts>:logic =
        if (not Portal.Ending?, not Training.Closed?, Training.Owner.IsActive[], Training.Generation = Ticket, Training.Mode = coach_mode.Personal, Training.Phase = coach_phase.Preparing, Portal.ArenaAccess.Holds(Training.Owner, coach_mode.Personal)?, Active := Portal.Runtime.ActiveTrainee?, Active.Owner = Training.Owner):
            return true
        return false

    Fail(Portal : coach_portal_device, Training : coach_training_session, Ticket : int):void =
        if (Current(Portal, Training, Ticket)?):
            set Countdown = 0
            Portal.EnterMode(Training.Owner, coach_mode.Hub)
            if (View := Portal.Views[Training.Owner]):
                View.ShowMenu(CoachLanguage("Round preparation stopped", "הכנת הסיבוב נעצרה", Training.HebrewText), CoachLanguage("The round did not start. You can retry or choose another training entrance.", "הקרב לא התחיל. אפשר לנסות שוב או לבחור כניסה אחרת לאימון.", Training.HebrewText), array{
                    coach_menu_entry{Label := CoachLanguage("Try personal training again", "ניסיון נוסף באימון האישי", Training.HebrewText), Action := 0},
                    coach_menu_entry{Label := CoachLanguage("Choose another mode", "בחירת מצב אחר", Training.HebrewText), Action := 20}
                })

    Stage(Portal : coach_portal_device, Training : coach_training_session):?fort_character =
        Collection := Portal.GetPlayspace().GetTeamCollection()
        Position := CoachPlayerStart(coach_mode.Personal)
        if (Body := Training.Owner.GetFortCharacter[], Body.IsActive[], Team := Collection.GetTeams()[0], Collection.AddToTeam[Training.Owner, Team], Body.TeleportTo[Position, IdentityRotation()], Distance(Body.GetTransform().Translation, Position) < 100.0):
            Body.SetVulnerability(false)
            Body.PutInStasis(stasis_args{AllowTurning := true, AllowFalling := true})
            Portal.RestoreRoundVitals(Body)
            return option{Body}
        return false

    BodiesCurrent(Portal : coach_portal_device, Training : coach_training_session, Ticket : int, Body : fort_character, Rival : fort_character)<transacts>:logic =
        if (Current(Portal, Training, Ticket)?, CurrentBody := Training.Owner.GetFortCharacter[], CurrentBody = Body, Body.IsActive[], CurrentRival := Portal.Opponent?, CurrentRival = Rival, Rival.IsActive[], Portal.PersonalPreparationZone.IsInVolume[Training.Owner], Distance(Body.GetTransform().Translation, CoachPlayerStart(coach_mode.Personal)) < 150.0, Portal.RoundVitalsReady(Body)?, Portal.RoundVitalsReady(Rival)?, Portal.OpponentLoadoutPrepared(Rival)?):
            return true
        return false

    Prepare(Portal : coach_portal_device, Training : coach_training_session, Ticket : int, PreserveExercise : logic, ExerciseGoal : int, PlanRevision : int, PlanApplication : logic)<suspends>:void =
        if (not Current(Portal, Training, Ticket)?):
            return
        if (not Portal.PersonalPreparationConfigured?):
            Fail(Portal, Training, Ticket)
            return
        Portal.PersonalPreparationZone.Enable()
        var Ready : logic = false
        var BodyAttempt : int = 0
        loop:
            if (BodyAttempt >= 60):
                break
            if (not Current(Portal, Training, Ticket)?):
                return
            if (Body := Training.Owner.GetFortCharacter[], Body.IsActive[], Portal.PersonalResetReady()? ):
                set Ready = true
                break
            Sleep(0.2)
            set BodyAttempt += 1
        if (not Ready?):
            Fail(Portal, Training, Ticket)
            return
        Portal.ResetArea(Training.Owner, coach_mode.Personal)
        Sleep(1.2)
        var ResetComplete : logic = false
        var ResetAttempt : int = 0
        loop:
            if (ResetAttempt >= 20):
                break
            if (not Current(Portal, Training, Ticket)?):
                return
            if (Portal.PersonalResetReady()? ):
                set ResetComplete = true
                break
            Sleep(0.1)
            set ResetAttempt += 1
        if (not ResetComplete?):
            Fail(Portal, Training, Ticket)
            return
        if (Structures := Portal.Runtime.Structures?):
            PoolTicket := Structures.Encounter
            PoolReady := Structures.PrepareNativePool(PoolTicket)
            if (not Current(Portal, Training, Ticket)?):
                return
            if (not PoolReady?):
                Fail(Portal, Training, Ticket)
                return
        var Student : ?fort_character = false
        var StageAttempt : int = 0
        loop:
            if (StageAttempt >= 5):
                break
            if (not Current(Portal, Training, Ticket)?):
                return
            set Student = Stage(Portal, Training)
            if (Student?):
                break
            Sleep(0.2)
            set StageAttempt += 1
        if (Body := Student?):
            Portal.LoadoutGranter.GrantItem(Training.Owner)
            if (Portal.UseCustomNPC?):
                Portal.OpponentSpawner.Reset()
                Portal.OpponentSpawner.Spawn()
                spawn { Portal.AwaitOpponentBinding(Portal.EncounterSerial) }
            else:
                Portal.BaselineSpawner.Reset()
                Portal.BaselineSpawner.Spawn()
            var OpponentReady : ?fort_character = false
            var OpponentAttempt : int = 0
            loop:
                if (OpponentAttempt >= 80):
                    break
                if (not Current(Portal, Training, Ticket)?):
                    return
                if (Rival := Portal.Opponent?, Portal.OpponentLoadoutPrepared(Rival)?):
                    # Apply the shared opening state after controller/loadout
                    # initialization as well as on the original spawn path.
                    Portal.RestoreRoundVitals(Rival)
                    if (BodiesCurrent(Portal, Training, Ticket, Body, Rival)?):
                        set OpponentReady = option{Rival}
                        break
                Sleep(0.1)
                set OpponentAttempt += 1
            if (Rival := OpponentReady?):
                for (Index := 0..2):
                    if (not BodiesCurrent(Portal, Training, Ticket, Body, Rival)?):
                        Fail(Portal, Training, Ticket)
                        return
                    set Countdown = 3 - Index
                    Sleep(1.0)
                if (not BodiesCurrent(Portal, Training, Ticket, Body, Rival)?):
                    Fail(Portal, Training, Ticket)
                    return
                set Countdown = 0
                Portal.PersonalPreparationZone.Disable()
                Training.BeginRound(?PreserveExercise := PreserveExercise)
                if (ExerciseGoal > 0):
                    Training.Practice.Start(ExerciseGoal, Training.Challenge)
                Training.BindPlanRound(PlanRevision, PlanApplication)
                Body.ReleaseFromStasis()
                Body.SetVulnerability(true)
                Rival.ReleaseFromStasis()
                Rival.SetVulnerability(true)
                if (View := Portal.Views[Training.Owner]):
                    View.CloseMenu()
                    if (Training.Practice.Goal > 0):
                        View.SetCaption(Training.Practice.Instruction(Training.HebrewText))
                    else:
                        View.SetCaption(CoachLanguage("Fight!", "הקרב התחיל!", Training.HebrewText))
                if (Portal.VoiceReady?, not Training.VoiceLink?):
                    Portal.SpeakerSpawner.Reset()
                    Portal.SpeakerSpawner.Spawn()
                return
        Fail(Portal, Training, Ticket)
