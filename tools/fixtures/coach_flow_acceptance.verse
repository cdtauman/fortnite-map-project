using { /Fortnite.com/Armory }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Devices }
using { /Fortnite.com/Game }
using { /Fortnite.com/Itemization }
using { /Fortnite.com/UI }
using { /Verse.org/Colors }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Itemization }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /UnrealEngine.com/Temporary/UI }

CoachAcceptanceHebrew<localizes>:message = "בדיקת עברית ישירה: שלום 123"

# Temporary private-session fixture. Kept outside the production source mirror.
coach_flow_acceptance_device := class(creative_device):
    @editable
    Enabled : logic = false
    @editable
    Portal : coach_portal_device = coach_portal_device{}

    Log(Result : logic, Case : string):void =
        var Passed : int = 0
        if (Result?):
            set Passed = 1
        Print("PCL|flow_acceptance|case={Case}|passed={Passed}", ?Duration := 0.0)

    Weapons(Player : player)<transacts>:int =
        var Count : int = 0
        if (Character := Player.GetFortCharacter[], Body := Character.GetEntity[]):
            for (Inventory : Body.FindDescendantComponents(inventory_component), Item : Inventory.GetItems(), Component := Item.GetComponent[item_component]):
                for (Category : Component.Categories, Category = FortniteItemCategories.WeaponRanged):
                    set Count += 1
        return Count

    WaitForFight(Player : player)<suspends>:logic =
        for (Attempt := 0..79):
            if (Training := Portal.Runtime.Players[Player], Training.Phase = coach_phase.Fighting, Opponent := Portal.Opponent?, Opponent.IsActive[], Character := Player.GetFortCharacter[], Character.IsActive[]):
                Character.SetVulnerability(false)
                return true
            Sleep(0.1)
        return false

    WaitForRespawn(Player : player, Ticket : int)<suspends>:logic =
        for (Attempt := 0..159):
            if (Training := Portal.Runtime.Players[Player], Training.Generation > Ticket, Training.Phase = coach_phase.Fighting, Fresh := Player.GetFortCharacter[], Fresh.IsActive[]):
                return true
            Sleep(0.1)
        return false

    OnBegin<override>()<suspends>:void =
        if (not Enabled?):
            return
        for (Attempt := 0..119):
            if (Player := GetPlayspace().GetPlayers()[0], Training := Portal.Runtime.Players[Player], View := Portal.Views[Player], Character := Player.GetFortCharacter[], Character.IsActive[]):
                Sleep(1.0)
                Run(Player, Training, View)
                return
            Sleep(0.25)
        Print("PCL|flow_acceptance|no_ready_player", ?Duration := 0.0)

    Run(Player : player, Training : coach_training_session, View : coach_player_view)<suspends>:void =
        Log(Training.HebrewText, "hebrew_default")
        var LobbyClear : logic = true
        if (View.Menu?):
            set LobbyClear = false
        Log(LobbyClear, "lobby_no_forced_menu")
        Portal.StartPersonal(Player)
        Ready := WaitForFight(Player)
        Log(Ready, "first_opponent_ready")
        if (not Ready?):
            Portal.EnterMode(Player, coach_mode.Hub)
            Print("PCL|flow_acceptance|finished|aborted_before_combat", ?Duration := 0.0)
            return
        InitialWeapons := Weapons(Player)
        Log(logic{InitialWeapons >= 2}, "initial_ranged_loadout")
        Print("PCL|flow_acceptance|initial_weapon_count={InitialWeapons}", ?Duration := 0.0)
        Ticket := Training.Generation
        if (Opponent := Portal.Opponent?):
            Opponent.Damage(damage_args{Amount := 2000.0, Instigator := option{Player.GetInstigator()}})
        Sleep(0.2)
        var ResultClear : logic = false
        if (Training.Phase = coach_phase.Review, Training.AwaitingNextRound?, not View.Menu?):
            set ResultClear = true
        Log(ResultClear, "native_elimination_nonmodal_result")
        Sleep(3.5)
        Restarted := WaitForFight(Player)
        var Advanced : logic = false
        if (Restarted?, Training.Generation > Ticket):
            set Advanced = true
        Log(Advanced, "automatic_next_round")
        if (not Advanced?):
            Portal.EnterMode(Player, coach_mode.Hub)
            Print("PCL|flow_acceptance|finished|aborted_before_retry", ?Duration := 0.0)
            return
        if (Opponent := Portal.Opponent?):
            Opponent.Damage(damage_args{Amount := 2000.0, Instigator := option{Player.GetInstigator()}})
        Sleep(0.2)
        Portal.ShowReview(Player)
        ReviewTicket := Training.Generation
        Sleep(3.5)
        var Cancelled : logic = false
        if (Training.Phase = coach_phase.Review, Training.Generation = ReviewTicket, not Training.AwaitingNextRound?, View.Menu?):
            set Cancelled = true
        Log(Cancelled, "requested_review_cancels_restart")
        Portal.StartPersonal(Player)
        RespawnReady := WaitForFight(Player)
        if (RespawnReady?, Character := Player.GetFortCharacter[], Opponent := Portal.Opponent?, Agent := Opponent.GetAgent[]):
            DeathTicket := Training.Generation
            Character.SetVulnerability(true)
            Character.Damage(damage_args{Amount := 2000.0, Instigator := option{Agent.GetInstigator()}})
            Sleep(1.0)
            Respawned := WaitForRespawn(Player, DeathTicket)
            Log(Respawned, "loss_respawn_and_retry")
            Count := Weapons(Player)
            Log(logic{Count >= 2 and Count >= InitialWeapons}, "respawn_ranged_loadout")
            Print("PCL|flow_acceptance|respawn_weapon_count={Count}", ?Duration := 0.0)
        Portal.EnterMode(Player, coach_mode.Hub)
        View.CloseMenu()
        View.SetCaption(CoachAcceptanceHebrew)
        Print("PCL|flow_acceptance|finished|returned_to_hub", ?Duration := 0.0)
