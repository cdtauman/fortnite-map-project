using { /Fortnite.com/Characters }
using { /Fortnite.com/Devices }
using { /Fortnite.com/Playspaces }
using { /Fortnite.com/Teams }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/SpatialMath }

coach_duel_phase := enum:
    Waiting
    Preparing
    Countdown
    Fighting

# One generation owns staging, protection, countdown and round admission.
coach_duel_round_flow := class:
    var Phase : coach_duel_phase = coach_duel_phase.Waiting
    var Generation : int = 0
    var Countdown : int = 0

    Participants(Portal : coach_portal_device, ?Except : ?player = false)<transacts>:[]player =
        var Result : []player = array{}
        for (Player -> Training : Portal.Runtime.Players, Player.IsActive[], not Training.Closed?, Training.Mode = coach_mode.Duel, Portal.ArenaAccess.Holds(Player, coach_mode.Duel)?):
            var Skip : logic = false
            if (Leaving := Except?, Leaving = Player):
                set Skip = true
            if (not Skip?):
                set Result += array{Player}
        return Result

    Protect(Portal : coach_portal_device, Players : []player, Freeze : logic):void =
        for (Player : Players, Character := Player.GetFortCharacter[], Character.IsActive[]):
            Character.SetVulnerability(false)
            if (Freeze?):
                Character.PutInStasis(stasis_args{AllowTurning := true, AllowFalling := true})
            else:
                Character.ReleaseFromStasis()

    Join(Portal : coach_portal_device):void =
        Players := Participants(Portal)
        if (Portal.DuelPreparationConfigured?):
            Portal.DuelPreparationZone.Enable()
        if (Players.Length <> 2):
            Leave(Portal, false)
            return
        # A join/respawn supersedes any task that captured the previous body.
        Begin(Portal, 0.0)

    Leave(Portal : coach_portal_device, Leaving : ?player):void =
        set Generation += 1
        set Phase = coach_duel_phase.Waiting
        set Countdown = 0
        set Portal.DuelRestarting = false
        if (Player := Leaving?, Body := Player.GetFortCharacter[]):
            Body.ReleaseFromStasis()
        if (Portal.DuelPreparationConfigured?):
            Portal.DuelPreparationZone.Enable()
        Players := Participants(Portal, ?Except := Leaving)
        Protect(Portal, Players, false)
        for (Player : Players, Training := Portal.Runtime.Players[Player]):
            set Training.Phase = coach_phase.Ready
            if (View := Portal.Views[Player]):
                View.SetCaption(CoachLanguage("Waiting for a second player.", "ממתין לשחקן שני.", Training.HebrewText))

    Begin(Portal : coach_portal_device, Delay : float):void =
        set Generation += 1
        set Phase = coach_duel_phase.Preparing
        set Countdown = 0
        set Portal.DuelRestarting = true
        Players := Participants(Portal)
        Protect(Portal, Players, true)
        for (Player : Players, Training := Portal.Runtime.Players[Player]):
            set Training.Phase = coach_phase.Ready
        if (not Portal.DuelPreparationConfigured?):
            Leave(Portal, false)
            return
        Portal.DuelPreparationZone.Enable()
        spawn { Prepare(Portal, Generation, Delay) }

    Current(Portal : coach_portal_device, Ticket : int)<transacts>:logic =
        if (Portal.Ending? or Ticket <> Generation or Participants(Portal).Length <> 2):
            return false
        return true

    Stage(Portal : coach_portal_device, Players : []player):logic =
        Collection := Portal.GetPlayspace().GetTeamCollection()
        for (Index -> Player : Players):
            if (Character := Player.GetFortCharacter[], Character.IsActive[], Team := Collection.GetTeams()[Index], Collection.AddToTeam[Player, Team]):
                Position := CoachDuelStart(Index)
                Facing := MakeRotationFromYawPitchRollDegrees(Index * 180.0, 0.0, 0.0)
                if (Character.TeleportTo[Position, Facing], Distance(Character.GetTransform().Translation, Position) < 100.0):
                    Portal.RestoreDuelVitals(Character)
                else:
                    return false
            else:
                return false
        return true

    BodiesCurrent(Portal : coach_portal_device, Ticket : int, Players : []player, Bodies : []fort_character)<transacts>:logic =
        if (not Current(Portal, Ticket)? or Bodies.Length <> 2):
            return false
        for (Index -> Player : Players):
            if (Original := Bodies[Index], Body := Player.GetFortCharacter[], Body = Original, Body.IsActive[], Portal.DuelPreparationZone.IsInVolume[Player], Portal.DuelVitalsReady(Body)?) {}
            else:
                return false
        return true

    WatchBodies(Portal : coach_portal_device, Ticket : int, Players : []player, Bodies : []fort_character)<suspends>:void =
        loop:
            if (not BodiesCurrent(Portal, Ticket, Players, Bodies)?):
                return
            Sleep(0.05)

    Prepare(Portal : coach_portal_device, Ticket : int, Delay : float)<suspends>:void =
        defer:
            if (Ticket = Generation and Phase <> coach_duel_phase.Fighting):
                Leave(Portal, false)
        Sleep(Delay)
        var Ready : logic = false
        var AliveAttempt : int = 0
        loop:
            if (AliveAttempt >= 60 or not Current(Portal, Ticket)?):
                return
            var Alive : int = 0
            for (Player : Participants(Portal), Body := Player.GetFortCharacter[], Body.IsActive[]):
                set Alive += 1
            if (Alive = 2 and Portal.DuelResetReady()?):
                set Ready = true
                break
            Sleep(0.2)
            set AliveAttempt += 1
        if (not Ready?):
            return
        Players := Participants(Portal)
        Protect(Portal, Players, true)
        if (FirstPlayer := Players[0]):
            Portal.ResetArea(FirstPlayer, coach_mode.Duel)
        Sleep(1.2)
        if (not Current(Portal, Ticket)?):
            return
        var Staged : logic = false
        var StageAttempt : int = 0
        loop:
            if (StageAttempt >= 5 or not Current(Portal, Ticket)?):
                return
            StagedNow := Stage(Portal, Players)
            if (StagedNow?):
                set Staged = true
                break
            Sleep(0.2)
            set StageAttempt += 1
        if (not Staged?):
            return
        var Bodies : []fort_character = array{}
        for (Player : Players, Body := Player.GetFortCharacter[], Body.IsActive[]):
            set Bodies += array{Body}
            Portal.GrantDuelLoadout(Player)
            if (View := Portal.Views[Player]):
                View.CloseMenu()
        var VolumeAttempt : int = 0
        loop:
            if (not Current(Portal, Ticket)?):
                return
            if (BodiesCurrent(Portal, Ticket, Players, Bodies)?):
                break
            if (VolumeAttempt >= 20):
                return
            Sleep(0.1)
            set VolumeAttempt += 1
        set Phase = coach_duel_phase.Countdown
        for (Index := 0..2):
            if (not BodiesCurrent(Portal, Ticket, Players, Bodies)?):
                return
            set Countdown = 3 - Index
            race:
                Sleep(1.0)
                WatchBodies(Portal, Ticket, Players, Bodies)
        if (not BodiesCurrent(Portal, Ticket, Players, Bodies)?):
            return
        Portal.DuelPreparationZone.Disable()
        set Phase = coach_duel_phase.Fighting
        set Countdown = 0
        set Portal.DuelRestarting = false
        for (Index -> Player : Players, Body := Bodies[Index], Training := Portal.Runtime.Players[Player]):
            set Training.Phase = coach_phase.Fighting
            Body.ReleaseFromStasis()
            Body.SetVulnerability(true)
            if (View := Portal.Views[Player]):
                View.SetCaption(CoachLanguage("Fight!", "הקרב התחיל!", Training.HebrewText))

    Say(Portal : coach_portal_device, Player : player, English : string, Hebrew : string):void =
        if (Training := Portal.Runtime.Players[Player], View := Portal.Views[Player]):
            View.SetCaption(CoachLanguage(English, Hebrew, Training.HebrewText))

    # Scores the round for the attributed winner and ends the match at the chosen target
    # (first to N). The next round, or the next match, starts automatically.
    Finish(Portal : coach_portal_device, Loser : player, Killer : ?fort_character):void =
        if (Phase <> coach_duel_phase.Fighting or Participants(Portal).Length <> 2):
            return
        if (Training := Portal.Runtime.Players[Loser], Training.Mode = coach_mode.Duel, Portal.ArenaAccess.Holds(Loser, coach_mode.Duel)?):
            if (Character := Killer?, Agent := Character.GetAgent[], Winner := player[Agent], Winner <> Loser, Winning := Portal.Runtime.Players[Winner], Winning.Mode = coach_mode.Duel, Portal.ArenaAccess.Holds(Winner, coach_mode.Duel)?):
                var Wins : int = 1
                if (Previous := Portal.DuelWins[Winner]):
                    set Wins = Previous + 1
                if (set Portal.DuelWins[Winner] = Wins) {}
                var Other : int = 0
                if (Value := Portal.DuelWins[Loser]):
                    set Other = Value
                Target := Portal.DuelSettings.Target()
                TargetEnglish := Portal.DuelSettings.TargetLabel(false)
                TargetHebrew := Portal.DuelSettings.TargetLabel(true)
                if (Target > 0 and Wins >= Target):
                    Say(Portal, Winner, "You won the match {Wins}-{Other}! A new match starts now.", "ניצחת במשחק {Wins}-{Other}! משחק חדש מתחיל עכשיו.")
                    Say(Portal, Loser, "Match lost {Other}-{Wins}. A new match starts now.", "הפסדת במשחק {Other}-{Wins}. משחק חדש מתחיל עכשיו.")
                    if (set Portal.DuelWins[Winner] = 0, set Portal.DuelWins[Loser] = 0) {}
                else:
                    Say(Portal, Winner, "Round won. Score {Wins}-{Other} ({TargetEnglish})", "ניצחת בסיבוב. תוצאה {Wins}-{Other} ({TargetHebrew})")
                    Say(Portal, Loser, "Round lost. Score {Other}-{Wins} ({TargetEnglish})", "הפסדת בסיבוב. תוצאה {Other}-{Wins} ({TargetHebrew})")
            Begin(Portal, 2.0)
