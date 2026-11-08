using { /Fortnite.com/Devices }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Marketplace }
using { /UnrealEngine.com/Temporary/Diagnostics }

# Abstract scopes avoid querying the root entitlement type, which never completes.
# Concrete products belong in an explicitly reviewed catalog.
coach_market_entitlement := class<abstract><castable>(entitlement) {}
coach_plus_entitlement := class<abstract><castable>(coach_market_entitlement) {}

coach_access_state := enum:
    Loading
    Owned
    NotOwned
    Unavailable

coach_purchase_tracker := class:
    Owner : coach_commerce_device
    Player : player
    var State : coach_access_state = coach_access_state.Loading
    var Subscription : ?cancelable = false
    var Revision : int = 0
    var Refreshing : logic = false
    var Pending : logic = false
    var DialogOpen : logic = false
    var Closed : logic = false

    Connect():void =
        Changes := GetEntitlementsChangedEvent(Player, coach_plus_entitlement)
        Listener := Changes.Subscribe(OnChanged)
        set Subscription = option{Listener}
        RequestRefresh()

    OnChanged(Event : tuple(player, []entitlement_change(coach_plus_entitlement))):void =
        if (Event(0) = Player, not Closed?):
            set Revision += 1
            set State = coach_access_state.Loading
            RequestRefresh()

    RequestRefresh():void =
        if (Closed?):
            return
        set Pending = true
        if (not Refreshing?):
            set Refreshing = true
            spawn { RefreshLoop() }

    RefreshLoop()<suspends>:void =
        defer:
            set Refreshing = false
        loop:
            if (Closed? or not Player.IsActive[] or not Pending?):
                return
            set Pending = false
            Ticket := Revision
            var Received : logic = false
            race:
                block:
                    Purchases := GetPurchasedEntitlements(Player, coach_plus_entitlement)
                    if (not Closed?, Player.IsActive[], Ticket = Revision):
                        var Owns : logic = false
                        for (Purchase : Purchases, Purchase(1) > 0):
                            set Owns = true
                        set State = coach_access_state.NotOwned
                        if (Owns?):
                            set State = coach_access_state.Owned
                        set Received = true
                Sleep(10.0)
                WatchClosed()
            if (not Received?, Ticket = Revision, not Closed?):
                set State = coach_access_state.Unavailable
                Print("PCL|commerce|entitlement_status_unconfirmed", ?Duration := 0.0)

    WatchClosed()<suspends>:void =
        loop:
            if (Closed? or not Owner.Enabled? or not Player.IsActive[]):
                return
            Sleep(0.1)

    Dispose():void =
        set Closed = true
        set Revision += 1
        if (Current := Subscription?):
            Current.Cancel()
        set Subscription = false

coach_commerce_device := class(creative_device):
    @editable
    Enabled : logic = false
    @editable
    Offers : []entitlement_offer = array{}

    var Trackers : [player]coach_purchase_tracker = map{}

    OnEnd<override>():void =
        for (Player -> Tracker : Trackers):
            Tracker.Dispose()
        set Trackers = map{}

    Join(Player : player):void =
        if (not Enabled? or Trackers[Player]):
            return
        Tracker := coach_purchase_tracker{Owner := Self, Player := Player}
        if (set Trackers[Player] = Tracker):
            Tracker.Connect()

    Leave(Player : player):void =
        if (Tracker := Trackers[Player]):
            Tracker.Dispose()
        var Remaining : [player]coach_purchase_tracker = map{}
        for (Other -> Tracker : Trackers, Other <> Player):
            if (set Remaining[Other] = Tracker) {}
        set Trackers = Remaining

    AllowsAdvancedFeatures(Player : player)<transacts>:logic =
        # During authoring, content remains available without fabricating a purchase.
        if (not Enabled?):
            return true
        if (Tracker := Trackers[Player], not Tracker.Closed?, Tracker.State = coach_access_state.Owned):
            return true
        return false

    HasCatalog()<transacts>:logic =
        if (Enabled? and Offers.Length > 0):
            return true
        return false

    OpenOffers(Player : player)<suspends>:void =
        if (not HasCatalog()? or not Player.IsActive[]):
            return
        Join(Player)
        if (Tracker := Trackers[Player], not Tracker.Closed?, not Tracker.DialogOpen?):
            set Tracker.DialogOpen = true
            defer:
                set Tracker.DialogOpen = false
            Catalog : []offer = for (Entry : Offers) { Entry }
            ShowOffersDialog(Player, Catalog, ?Title := CoachMessage("ProCoachLab training content"))
            Tracker.RequestRefresh()
