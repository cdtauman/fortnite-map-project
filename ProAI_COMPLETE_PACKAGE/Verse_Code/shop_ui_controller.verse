# ============================================================================
# FILE: shop_ui_controller.verse — Shop Menu UI via Canvas API
# LOCATION: Content/ (root)
# PHASE: 8
#
# ARCHITECTURE:
#   Creates and manages the in-game shop overlay using Verse's
#   canvas + button API. The shop is triggered when the player
#   interacts with a physical "Shop Terminal" button_device placed
#   near the arena lobby area.
#
#   The UI displays:
#     - Product list with names, prices, and owned status
#     - Token balance
#     - Analytics Pass status
#     - Currently equipped arena skin
#
#   Purchase flow:
#     Player interacts with terminal → Shop opens →
#     Player interacts with a product button → shop_manager.ProcessPurchaseFlow →
#     UI refreshes to show updated inventory
#
# WIRING (UEFN Editor):
#   ShopMgr          → shop_manager device
#   PersistMgr       → persistence_manager device
#   ShopTerminalBtn  → button_device (physical terminal in lobby)
#   CloseShopBtn     → button_device (close button near terminal)
# ============================================================================
using { /Fortnite.com/Devices }
using { /Fortnite.com/Game }
using { /Fortnite.com/UI }
using { /Verse.org/Simulation }
using { /Verse.org/Colors }
using { /Verse.org/Colors/NamedColors }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/UI }
using { /UnrealEngine.com/Temporary/SpatialMath }

shop_ui_controller<public> := class(creative_device):

    Logger<private> : log = log{Channel := log_shopui_ch}

    # ── Editable References ──────────────────────────────────────────────────
    @editable
    ShopMgr<public> : shop_manager = shop_manager{}

    @editable
    PersistMgr<public> : persistence_manager = persistence_manager{}

    @editable
    ShopTerminalBtn<public> : button_device = button_device{}

    @editable
    CloseShopBtn<public> : button_device = button_device{}

    # ── Canvas UI ────────────────────────────────────────────────────────────
    var ShopTitleText<private>     : text_block = text_block{}
    var Product1Text<private>      : text_block = text_block{}
    var Product2Text<private>      : text_block = text_block{}
    var Product3Text<private>      : text_block = text_block{}
    var Product4Text<private>      : text_block = text_block{}
    var StatusText<private>        : text_block = text_block{}
    var FeedbackText<private>      : text_block = text_block{}

    var ShopCanvas<private>        : ?canvas = false
    var IsShopOpen<public>         : logic = false
    var IsCanvasCreated<private>   : logic = false

    # ── Display State ────────────────────────────────────────────────────────
    var LastPurchaseResult<public>  : string = ""
    var TokenBalance<public>       : int = 0
    var HasPass<public>            : logic = false

    # ══════════════════════════════════════════════════════════════════════════
    # INITIALIZATION
    # ══════════════════════════════════════════════════════════════════════════
    OnBegin<override>()<suspends> : void =
        Logger.Print("SHOP_UI: Controller online.")

        # Create UI canvas when player joins
        branch:
            WaitAndCreateShopCanvas()

        # Listen for shop terminal interaction (open)
        branch:
            ListenShopTerminal()

        # Listen for close button
        branch:
            ListenCloseButton()

    # ══════════════════════════════════════════════════════════════════════════
    # CANVAS CREATION
    # ══════════════════════════════════════════════════════════════════════════
    WaitAndCreateShopCanvas<private>()<suspends> : void =
        loop:
            AllPlayers := GetPlayspace().GetPlayers()
            if (Player := AllPlayers[0]):
                CreateShopCanvas(Player)
                break
            Sleep(0.5)

    CreateShopCanvas<private>(Player : player) : void =
        if (PlayerUI := GetPlayerUI[Player]):
            set ShopTitleText = text_block{DefaultText := StringToMessage(""), DefaultTextColor := NamedColors.White}
            set Product1Text = text_block{DefaultText := StringToMessage(""), DefaultTextColor := NamedColors.White}
            set Product2Text = text_block{DefaultText := StringToMessage(""), DefaultTextColor := NamedColors.White}
            set Product3Text = text_block{DefaultText := StringToMessage(""), DefaultTextColor := NamedColors.White}
            set Product4Text = text_block{DefaultText := StringToMessage(""), DefaultTextColor := NamedColors.White}
            set StatusText = text_block{DefaultText := StringToMessage(""), DefaultTextColor := NamedColors.Silver}
            set FeedbackText = text_block{DefaultText := StringToMessage(""), DefaultTextColor := NamedColors.Yellow}

            NewCanvas := canvas:
                Slots := array:
                    canvas_slot:
                        Anchors := anchors{Minimum := vector2{X := 0.30, Y := 0.10}, Maximum := vector2{X := 0.30, Y := 0.10}}
                        Offsets := margin{Top := 0.0, Left := 0.0, Bottom := 0.0, Right := 0.0}
                        SizeToContent := true
                        Widget := ShopTitleText
                    canvas_slot:
                        Anchors := anchors{Minimum := vector2{X := 0.20, Y := 0.25}, Maximum := vector2{X := 0.20, Y := 0.25}}
                        Offsets := margin{Top := 0.0, Left := 0.0, Bottom := 0.0, Right := 0.0}
                        SizeToContent := true
                        Widget := Product1Text
                    canvas_slot:
                        Anchors := anchors{Minimum := vector2{X := 0.20, Y := 0.35}, Maximum := vector2{X := 0.20, Y := 0.35}}
                        Offsets := margin{Top := 0.0, Left := 0.0, Bottom := 0.0, Right := 0.0}
                        SizeToContent := true
                        Widget := Product2Text
                    canvas_slot:
                        Anchors := anchors{Minimum := vector2{X := 0.20, Y := 0.45}, Maximum := vector2{X := 0.20, Y := 0.45}}
                        Offsets := margin{Top := 0.0, Left := 0.0, Bottom := 0.0, Right := 0.0}
                        SizeToContent := true
                        Widget := Product3Text
                    canvas_slot:
                        Anchors := anchors{Minimum := vector2{X := 0.20, Y := 0.55}, Maximum := vector2{X := 0.20, Y := 0.55}}
                        Offsets := margin{Top := 0.0, Left := 0.0, Bottom := 0.0, Right := 0.0}
                        SizeToContent := true
                        Widget := Product4Text
                    canvas_slot:
                        Anchors := anchors{Minimum := vector2{X := 0.20, Y := 0.70}, Maximum := vector2{X := 0.20, Y := 0.70}}
                        Offsets := margin{Top := 0.0, Left := 0.0, Bottom := 0.0, Right := 0.0}
                        SizeToContent := true
                        Widget := StatusText
                    canvas_slot:
                        Anchors := anchors{Minimum := vector2{X := 0.20, Y := 0.80}, Maximum := vector2{X := 0.20, Y := 0.80}}
                        Offsets := margin{Top := 0.0, Left := 0.0, Bottom := 0.0, Right := 0.0}
                        SizeToContent := true
                        Widget := FeedbackText

            set ShopCanvas = option{NewCanvas}
            PlayerUI.AddWidget(NewCanvas)
            set IsCanvasCreated = true
            ClearShopDisplay()
            Logger.Print("SHOP_UI: Canvas created (starts hidden).")

    # ══════════════════════════════════════════════════════════════════════════
    # TERMINAL LISTENERS
    # ══════════════════════════════════════════════════════════════════════════
    ListenShopTerminal<private>()<suspends> : void =
        loop:
            InteractingAgent := ShopTerminalBtn.InteractedWithEvent.Await()
            if (Player := player[InteractingAgent]):
                OpenShop(Player)

    ListenCloseButton<private>()<suspends> : void =
        loop:
            CloseShopBtn.InteractedWithEvent.Await()
            CloseShop()

    # ══════════════════════════════════════════════════════════════════════════
    # OPEN / CLOSE SHOP
    # ══════════════════════════════════════════════════════════════════════════
    OpenShop<public>(Player : player) : void =
        set IsShopOpen = true
        RefreshShopDisplay()
        Logger.Print("SHOP_UI: Shop opened.")

    CloseShop<public>() : void =
        set IsShopOpen = false
        ClearShopDisplay()
        Logger.Print("SHOP_UI: Shop closed.")

    # ══════════════════════════════════════════════════════════════════════════
    # REFRESH DISPLAY — Update all product text with current inventory state
    # ══════════════════════════════════════════════════════════════════════════
    RefreshShopDisplay<private>() : void =
        if (not IsCanvasCreated?):
            return

        Inv := ShopMgr.Inventory

        ShopTitleText.SetText(StringToMessage("=== TRAINING SHOP ==="))

        # Product 1: Analytics Pass
        var PassStatus : string = "BUY"
        if (Inv.HasAnalyticsPass?):
            set PassStatus = "OWNED"
        Product1Text.SetText(StringToMessage(
            "[1] Advanced Analytics Pass — 800 V-Bucks [{PassStatus}]"
        ))

        # Product 2: Cyberpunk Arena
        var CyberStatus : string = "BUY"
        Owned2 := Inv.IsSkinOwned(2)
        if (Owned2?):
            set CyberStatus = "OWNED"
        Product2Text.SetText(StringToMessage(
            "[2] Cyberpunk Arena Skin — 300 V-Bucks [{CyberStatus}]"
        ))

        # Product 3: Neon Arena
        var NeonStatus : string = "BUY"
        Owned3 := Inv.IsSkinOwned(3)
        if (Owned3?):
            set NeonStatus = "OWNED"
        Product3Text.SetText(StringToMessage(
            "[3] Neon Grid Arena Skin — 300 V-Bucks [{NeonStatus}]"
        ))

        # Product 4: Challenge Tokens
        Product4Text.SetText(StringToMessage(
            "[4] 5 Challenge Tokens — 250 V-Bucks [Balance: {Inv.ChallengeTokens}]"
        ))

        # Status line
        var SkinName : string = "Default"
        if (Inv.EquippedArenaSkin = 2):
            set SkinName = "Cyberpunk"
        else if (Inv.EquippedArenaSkin = 3):
            set SkinName = "Neon Grid"
        StatusText.SetText(StringToMessage(
            "Tokens: {Inv.ChallengeTokens} | Arena: {SkinName} | Pass: {PassStatus}"
        ))

        FeedbackText.SetText(StringToMessage(
            "Interact with a Buy Button at the terminal to purchase."
        ))

    ClearShopDisplay<private>() : void =
        if (not IsCanvasCreated?):
            return
        EmptyMsg := StringToMessage("")
        ShopTitleText.SetText(EmptyMsg)
        Product1Text.SetText(EmptyMsg)
        Product2Text.SetText(EmptyMsg)
        Product3Text.SetText(EmptyMsg)
        Product4Text.SetText(EmptyMsg)
        StatusText.SetText(EmptyMsg)
        FeedbackText.SetText(EmptyMsg)

    # ══════════════════════════════════════════════════════════════════════════
    # PURCHASE FEEDBACK — Called after shop_manager processes a buy
    # ══════════════════════════════════════════════════════════════════════════
    ShowPurchaseResult<public>(Message : string) : void =
        set LastPurchaseResult = Message
        if (IsCanvasCreated?):
            FeedbackText.SetText(StringToMessage(Message))
        RefreshShopDisplay()
        Logger.Print("SHOP_UI: {Message}")

    HandlePurchaseRequest<public>(Player : player, ProductId : int) : void =
        Success := ShopMgr.ProcessPurchase(ProductId)
        if (Success?):
            ShowPurchaseResult("Purchase successful! Item unlocked.")
            ExportData := ShopMgr.Inventory.ExportToData()
            PersistMgr.SaveEconomyData(Player, ExportData)
        else:
            ShowPurchaseResult("Purchase failed — item may already be owned.")

    StringToMessage<localizes><private>(Text : string) : message =
        "{Text}"

log_shopui_ch := class(log_channel):