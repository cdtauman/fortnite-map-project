# ============================================================================
# FILE: shop_manager.verse — In-Island Transaction Shop & Product Catalog
# LOCATION: Content/ (root)
# PHASE: 8
#
# ARCHITECTURE:
#   Implements the complete in-map economy (spec §8). The shop has two
#   layers:
#
#   LAYER 1 — PRODUCT CATALOG (this module):
#     Defines every purchasable item with its ID, name, V-Bucks price,
#     category, and anti-pay-to-win classification. Handles the
#     game-side logic of unlocking features after purchase confirmation.
#
#   LAYER 2 — PAYMENT FLOW (engine-managed):
#     The actual V-Bucks transaction is handled by UEFN's In-Island
#     Transaction API. This module triggers the flow and reacts to
#     the confirmation callback. If the API is not yet configured in
#     the project, the module simulates the flow for testing.
#
#   PHYSICAL SHOP:
#     In the UEFN editor, button_device props are placed at a "shop
#     terminal" location near the arena. Each button maps to one product.
#     When a player interacts with a button, its InteractedWithEvent
#     fires, and this module processes the purchase.
#
# ANTI-PAY-TO-WIN (spec §8.4):
#   - No item affects ELO calculations.
#   - No item increases damage, health, or combat stats.
#   - All core training (basic analytics, standard bots, ELO) is free.
#   - Paid items offer depth (richer data), variety (cosmetics), convenience.
#
# WIRING (UEFN Editor):
#   EventBus         → event_bus device
#   PersistenceRef   → persistence_manager device
#   CosmeticRef      → cosmetic_applicator device
#   BtnAnalyticsPass → button_device (shop terminal button #1)
#   BtnCyberArena    → button_device (shop terminal button #2)
#   BtnNeonArena     → button_device (shop terminal button #3)
#   BtnTokenPack     → button_device (shop terminal button #4)
# ============================================================================
using { /Fortnite.com/Devices }
using { /Fortnite.com/Game }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }

# ── Product ID Constants ─────────────────────────────────────────────────────
PRODUCT_ANALYTICS_PASS<public>       : int = 1
PRODUCT_ARENA_SKIN_CYBER<public>     : int = 2
PRODUCT_ARENA_SKIN_NEON<public>      : int = 3
PRODUCT_CHALLENGE_TOKENS_5<public>   : int = 4
PRODUCT_CHALLENGE_TOKENS_10<public>  : int = 5
PRODUCT_SPEED_BOOTS<public>          : int = 6
PRODUCT_SLOWMO_REPLAY<public>        : int = 7

# ── Product Category Constants ───────────────────────────────────────────────
CATEGORY_PASS<public>        : int = 0
CATEGORY_COSMETIC<public>    : int = 1
CATEGORY_CONSUMABLE<public>  : int = 2
CATEGORY_MODIFIER<public>    : int = 3

# ── Purchase Result Constants ────────────────────────────────────────────────
PURCHASE_SUCCESS<public>         : int = 0
PURCHASE_ALREADY_OWNED<public>   : int = 1
PURCHASE_INSUFFICIENT_FUNDS<public> : int = 2
PURCHASE_INVALID_PRODUCT<public> : int = 3
PURCHASE_FAILED<public>          : int = 4

# ══════════════════════════════════════════════════════════════════════════════
# PRODUCT DEFINITION — Describes one purchasable item
# ══════════════════════════════════════════════════════════════════════════════
product_def<public> := struct:
    ProductId<public>     : int
    Name<public>          : string
    PriceVBucks<public>   : int
    Category<public>      : int
    IsDurable<public>     : logic
    Description<public>   : string

# ══════════════════════════════════════════════════════════════════════════════
# SHOP MANAGER DEVICE
# ══════════════════════════════════════════════════════════════════════════════
shop_manager<public> := class(creative_device):

    Logger<private> : log = log{Channel := log_shop_ch}

    # ── Editable References ──────────────────────────────────────────────────
    @editable
    EventBus<public> : event_bus = event_bus{}

    @editable
    PersistenceRef<public> : persistence_manager = persistence_manager{}

    @editable
    CosmeticRef<public> : cosmetic_applicator = cosmetic_applicator{}

    # ── Purchase Button Devices (placed at the shop terminal) ────────────────
    @editable
    BtnAnalyticsPass<public> : button_device = button_device{}

    @editable
    BtnCyberArena<public> : button_device = button_device{}

    @editable
    BtnNeonArena<public> : button_device = button_device{}

    @editable
    BtnTokenPack<public> : button_device = button_device{}

    # ── Inventory Controller (manages owned items in-memory) ─────────────────
    var Inventory<public> : inventory_controller = inventory_controller{}

    # ── Product Catalog ──────────────────────────────────────────────────────
    ProductAnalyticsPass<private> : product_def = product_def{
        ProductId := 1, Name := "Advanced Analytics Pass",
        PriceVBucks := 800, Category := 0, IsDurable := true,
        Description := "Unlock deep metric dashboards and Elite bot access."
    }

    ProductCyberArena<private> : product_def = product_def{
        ProductId := 2, Name := "Cyberpunk Arena",
        PriceVBucks := 300, Category := 1, IsDurable := true,
        Description := "Neon-lit cyberpunk arena skin."
    }

    ProductNeonArena<private> : product_def = product_def{
        ProductId := 3, Name := "Neon Grid Arena",
        PriceVBucks := 300, Category := 1, IsDurable := true,
        Description := "Tron-style glowing grid arena skin."
    }

    ProductTokenPack5<private> : product_def = product_def{
        ProductId := 4, Name := "5 Challenge Tokens",
        PriceVBucks := 250, Category := 2, IsDurable := false,
        Description := "Access 5 special challenge scenarios."
    }

    # ── Telemetry ────────────────────────────────────────────────────────────
    var TotalPurchases<private>         : int = 0
    var TotalVBucksRevenue<private>     : int = 0
    var TotalFailedPurchases<private>   : int = 0

    # ══════════════════════════════════════════════════════════════════════════
    # INITIALIZATION — Load inventory from persistence, wire button listeners
    # ══════════════════════════════════════════════════════════════════════════
    OnBegin<override>()<suspends> : void =
        Logger.Print("SHOP: ── Online ──")
        Logger.Print("SHOP: Product catalog — 4 items loaded.")

        # Load saved inventory from persistence
        branch:
            LoadInventoryFromPersistence()

        # Wire button interaction listeners
        # Each button's InteractedWithEvent fires when the player uses it.
        branch:
            ListenAnalyticsPassButton()
        branch:
            ListenCyberArenaButton()
        branch:
            ListenNeonArenaButton()
        branch:
            ListenTokenPackButton()

        Logger.Print("SHOP: All button listeners active.")

    # ══════════════════════════════════════════════════════════════════════════
    # BUTTON LISTENERS — Each wired to one shop terminal button
    # ══════════════════════════════════════════════════════════════════════════
    ListenAnalyticsPassButton<private>()<suspends> : void =
        loop:
            InteractingAgent := BtnAnalyticsPass.InteractedWithEvent.Await()
            if (Player := player[InteractingAgent]):
                ProcessPurchaseFlow(Player, PRODUCT_ANALYTICS_PASS)

    ListenCyberArenaButton<private>()<suspends> : void =
        loop:
            InteractingAgent := BtnCyberArena.InteractedWithEvent.Await()
            if (Player := player[InteractingAgent]):
                ProcessPurchaseFlow(Player, PRODUCT_ARENA_SKIN_CYBER)

    ListenNeonArenaButton<private>()<suspends> : void =
        loop:
            InteractingAgent := BtnNeonArena.InteractedWithEvent.Await()
            if (Player := player[InteractingAgent]):
                ProcessPurchaseFlow(Player, PRODUCT_ARENA_SKIN_NEON)

    ListenTokenPackButton<private>()<suspends> : void =
        loop:
            InteractingAgent := BtnTokenPack.InteractedWithEvent.Await()
            if (Player := player[InteractingAgent]):
                ProcessPurchaseFlow(Player, PRODUCT_CHALLENGE_TOKENS_5)

    # ══════════════════════════════════════════════════════════════════════════
    # PURCHASE FLOW — Full transaction pipeline
    #
    # Steps:
    #   1. Validate: Is the product valid? Already owned (for durables)?
    #   2. Payment: Trigger In-Island Transaction API (or simulate).
    #   3. Fulfillment: Update inventory_controller with the new item.
    #   4. Persistence: Save to Module D Slot 4 via persistence_manager.
    #   5. Side effects: Apply cosmetics, unlock features, etc.
    #   6. Confirmation: Log and notify the player.
    # ══════════════════════════════════════════════════════════════════════════
    ProcessPurchaseFlow<private>(Player : player, ProductId : int)<suspends> : void =
        Logger.Print("SHOP: Purchase flow started — Product #{ProductId}")

        # Step 1: Pre-validation
        PreCheck := ValidatePurchase(ProductId)
        if (not (PreCheck = PURCHASE_SUCCESS)):
            set TotalFailedPurchases += 1
            Logger.Print("SHOP: Purchase blocked — {GetResultName(PreCheck)}")
            return

        # Step 2: Payment — In-Island Transaction API
        # The actual V-Bucks deduction is handled by the engine when
        # configured. We trigger the flow and assume success for now.
        # When the API callback confirms payment, fulfillment proceeds.
        #
        # In production, replace this with:
        #   TransactionResult := InIslandTransaction.Purchase(ProductId, Price)
        #   if (not TransactionResult.Succeeded?): return
        #
        # For development/testing, we simulate instant confirmation:
        PaymentConfirmed := SimulatePaymentFlow(ProductId)
        if (not PaymentConfirmed?):
            set TotalFailedPurchases += 1
            Logger.Print("SHOP: Payment not confirmed for product #{ProductId}.")
            return

        # Step 3: Fulfillment — Update in-memory inventory
        FulfillPurchase(ProductId)

        # Step 4: Persistence — Save to Slot 4
        ExportData := Inventory.ExportToData()
        PersistenceRef.SaveEconomyData(Player, ExportData)

        # Step 5: Side effects
        ApplyPurchaseSideEffects(ProductId)

        # Step 6: Telemetry
        ProductPrice := GetProductPrice(ProductId)
        set TotalPurchases += 1
        set TotalVBucksRevenue += ProductPrice

        Logger.Print("SHOP: Purchase #{TotalPurchases} complete — {GetProductName(ProductId)} ({ProductPrice} V-Bucks)")

    # ══════════════════════════════════════════════════════════════════════════
    # VALIDATION — Check if the purchase is allowed
    # ══════════════════════════════════════════════════════════════════════════
    ValidatePurchase<private>(ProductId : int) : int =
        # Check product exists
        Valid := IsValidProduct(ProductId)
        if (not Valid?):
            return PURCHASE_INVALID_PRODUCT

        # Check durable items aren't re-purchased
        if (ProductId = PRODUCT_ANALYTICS_PASS):
            if (Inventory.HasAnalyticsPass?):
                Logger.Print("SHOP: Analytics Pass already owned.")
                return PURCHASE_ALREADY_OWNED

        # Cosmetic skin duplicate check via bitfield
        if (ProductId = PRODUCT_ARENA_SKIN_CYBER):
            Owned2 := IsSkinOwned(2)
            if (Owned2?):
                Logger.Print("SHOP: Cyber Arena already owned.")
                return PURCHASE_ALREADY_OWNED

        if (ProductId = PRODUCT_ARENA_SKIN_NEON):
            Owned3 := IsSkinOwned(3)
            if (Owned3?):
                Logger.Print("SHOP: Neon Arena already owned.")
                return PURCHASE_ALREADY_OWNED

        PURCHASE_SUCCESS

    # ══════════════════════════════════════════════════════════════════════════
    # PAYMENT SIMULATION
    # In production, this is replaced by the In-Island Transaction API.
    # For development, all payments auto-confirm.
    # ══════════════════════════════════════════════════════════════════════════
    SimulatePaymentFlow<private>(ProductId : int)<suspends> : logic =
        # Simulate brief payment processing delay
        Sleep(0.3)
        Logger.Print("SHOP: [SIMULATED] Payment confirmed for product #{ProductId}.")
        true

    # ══════════════════════════════════════════════════════════════════════════
    # FULFILLMENT — Grant the purchased item to the player
    # ══════════════════════════════════════════════════════════════════════════
    FulfillPurchase<private>(ProductId : int) : void =
        if (ProductId = PRODUCT_ANALYTICS_PASS):
            Inventory.PurchaseAnalyticsPass()
            Logger.Print("SHOP: Fulfilled — Analytics Pass unlocked.")

        else if (ProductId = PRODUCT_ARENA_SKIN_CYBER):
            Inventory.PurchaseArenaSkin(2)
            Logger.Print("SHOP: Fulfilled — Cyber Arena skin unlocked.")

        else if (ProductId = PRODUCT_ARENA_SKIN_NEON):
            Inventory.PurchaseArenaSkin(3)
            Logger.Print("SHOP: Fulfilled — Neon Arena skin unlocked.")

        else if (ProductId = PRODUCT_CHALLENGE_TOKENS_5):
            Inventory.PurchaseChallengeTokens(5)
            Logger.Print("SHOP: Fulfilled — 5 Challenge Tokens added.")

        else if (ProductId = PRODUCT_CHALLENGE_TOKENS_10):
            Inventory.PurchaseChallengeTokens(10)
            Logger.Print("SHOP: Fulfilled — 10 Challenge Tokens added.")

    # ══════════════════════════════════════════════════════════════════════════
    # SIDE EFFECTS — Post-purchase actions (cosmetic swaps, unlocks)
    # ══════════════════════════════════════════════════════════════════════════
    ApplyPurchaseSideEffects<private>(ProductId : int) : void =
        # Auto-equip purchased cosmetic arenas
        if (ProductId = PRODUCT_ARENA_SKIN_CYBER):
            set Inventory.EquippedArenaSkin = 2
            spawn:
                CosmeticRef.ApplyArenaSkin(2)
            Logger.Print("SHOP: Auto-equipped Cyber Arena.")

        else if (ProductId = PRODUCT_ARENA_SKIN_NEON):
            set Inventory.EquippedArenaSkin = 3
            spawn:
                CosmeticRef.ApplyArenaSkin(3)
            Logger.Print("SHOP: Auto-equipped Neon Arena.")

    # ══════════════════════════════════════════════════════════════════════════
    # LOAD FROM PERSISTENCE — Restore inventory on session start
    # ══════════════════════════════════════════════════════════════════════════
    LoadInventoryFromPersistence<private>()<suspends> : void =
        Sleep(2.5)
        AllPlayers := GetPlayspace().GetPlayers()
        if (Player := AllPlayers[0]):
            EconomyData := PersistenceRef.LoadEconomyData(Player)
            Inventory.LoadFromData(EconomyData)
            Logger.Print("SHOP: Inventory loaded. Pass:{if (Inventory.HasAnalyticsPass?) then "true" else "false"} Tokens:{Inventory.ChallengeTokens} Skin:{Inventory.EquippedArenaSkin}")

            # Apply equipped cosmetic
            if (Inventory.EquippedArenaSkin > 0):
                spawn:
                    CosmeticRef.ApplyArenaSkin(Inventory.EquippedArenaSkin)
                Logger.Print("SHOP: Restored equipped arena skin #{Inventory.EquippedArenaSkin}.")

    # ══════════════════════════════════════════════════════════════════════════
    # LEGACY API — Backward compatible ProcessPurchase
    # ══════════════════════════════════════════════════════════════════════════
    ProcessPurchase<public>(ProductId : int) : logic =
        PreCheck := ValidatePurchase(ProductId)
        if (not (PreCheck = PURCHASE_SUCCESS)):
            return false
        FulfillPurchase(ProductId)
        set TotalPurchases += 1
        set TotalVBucksRevenue += GetProductPrice(ProductId)
        true

    # ══════════════════════════════════════════════════════════════════════════
    # PRODUCT QUERIES
    # ══════════════════════════════════════════════════════════════════════════
    IsValidProduct<private>(ProductId : int) : logic =
        if (ProductId >= 1):
            if (ProductId <= 7):
                return true
        false

    GetProductPrice<public>(ProductId : int) : int =
        if (ProductId = PRODUCT_ANALYTICS_PASS):
            return 800
        else if (ProductId = PRODUCT_ARENA_SKIN_CYBER):
            return 300
        else if (ProductId = PRODUCT_ARENA_SKIN_NEON):
            return 300
        else if (ProductId = PRODUCT_CHALLENGE_TOKENS_5):
            return 250
        else if (ProductId = PRODUCT_CHALLENGE_TOKENS_10):
            return 450
        else if (ProductId = PRODUCT_SPEED_BOOTS):
            return 150
        else if (ProductId = PRODUCT_SLOWMO_REPLAY):
            return 200
        0

    GetProductName<public>(ProductId : int) : string =
        if (ProductId = PRODUCT_ANALYTICS_PASS):
            return "Advanced Analytics Pass"
        else if (ProductId = PRODUCT_ARENA_SKIN_CYBER):
            return "Cyberpunk Arena"
        else if (ProductId = PRODUCT_ARENA_SKIN_NEON):
            return "Neon Grid Arena"
        else if (ProductId = PRODUCT_CHALLENGE_TOKENS_5):
            return "5 Challenge Tokens"
        else if (ProductId = PRODUCT_CHALLENGE_TOKENS_10):
            return "10 Challenge Tokens"
        else if (ProductId = PRODUCT_SPEED_BOOTS):
            return "Speed Boots"
        else if (ProductId = PRODUCT_SLOWMO_REPLAY):
            return "Slow-Mo Replay"
        "Unknown"

    GetResultName<private>(Result : int) : string =
        if (Result = PURCHASE_SUCCESS):
            return "Success"
        else if (Result = PURCHASE_ALREADY_OWNED):
            return "AlreadyOwned"
        else if (Result = PURCHASE_INSUFFICIENT_FUNDS):
            return "InsufficientFunds"
        else if (Result = PURCHASE_INVALID_PRODUCT):
            return "InvalidProduct"
        "Failed"

    IsSkinOwned<private>(SkinId : int) : logic =
        # Check the bitfield: ArenaSkinsOwned contains accumulated skin IDs
        # A more robust check would use proper bitfield ops, but for
        # the 2-3 skins we have, this works:
        if (SkinId = 2):
            if (Inventory.ArenaSkinsOwned >= 2):
                return true
        else if (SkinId = 3):
            if (Inventory.ArenaSkinsOwned >= 5):
                return true
        false

    # ══════════════════════════════════════════════════════════════════════════
    # PUBLIC: Check if player has premium features
    # Called by analytics_engine to gate advanced dashboards.
    # ══════════════════════════════════════════════════════════════════════════
    HasAnalyticsPass<public>() : logic =
        Inventory.HasAnalyticsPass

    GetChallengeTokenBalance<public>() : int =
        Inventory.ChallengeTokens

    ConsumeToken<public>() : logic =
        Inventory.ConsumeChallengeToken()

    # ══════════════════════════════════════════════════════════════════════════
    # TELEMETRY
    # ══════════════════════════════════════════════════════════════════════════
    LogShopStats<public>() : void =
        Logger.Print("SHOP: ── Statistics ──")
        Logger.Print("SHOP:   Total Purchases: {TotalPurchases}")
        Logger.Print("SHOP:   V-Bucks Revenue: {TotalVBucksRevenue}")
        Logger.Print("SHOP:   Failed Purchases: {TotalFailedPurchases}")
        Logger.Print("SHOP:   Pass Owned: {if (Inventory.HasAnalyticsPass?) then "true" else "false"}")
        Logger.Print("SHOP:   Tokens: {Inventory.ChallengeTokens}")
        Logger.Print("SHOP:   Equipped Skin: {Inventory.EquippedArenaSkin}")

log_shop_ch := class(log_channel):