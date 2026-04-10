# ============================================================================
# FILE: inventory_controller.verse — Player Inventory & Ownership Manager
# LOCATION: Content/ (root)
# PHASE: 8
#
# ARCHITECTURE:
#   Manages the player's in-memory inventory state during a session.
#   This is the runtime mirror of persistence Slot 4 (Economy).
#   On session start, LoadFromData() hydrates from persistence.
#   On purchase/consumption, the inventory updates in-memory AND
#   triggers a persistence save via shop_manager → persistence_manager.
#
#   OWNERSHIP TRACKING:
#     Durable items (passes, skins) use boolean flags or bitfield integers.
#     Consumable items (tokens, modifiers) use integer balances.
#     The bitfield pattern compresses up to 32 items per integer field.
#
#   ITEM ID SYSTEM:
#     Items are identified by string IDs for readability in choreographer
#     and coach code, but stored as integer flags internally for
#     persistence efficiency. The mapping is:
#       "analytics_pass"   → HasAnalyticsPass (bool)
#       "arena_cyber"      → ArenaSkinsOwned bit 1
#       "arena_neon"       → ArenaSkinsOwned bit 2
#       "arena_classic"    → ArenaSkinsOwned bit 3 (future)
#       "arena_tournament" → ArenaSkinsOwned bit 4 (future)
#       "challenge_token"  → ChallengeTokens (int balance)
#       "speed_boots"      → ModifierCharges[0] (int balance)
#       "slowmo_replay"    → ModifierCharges[1] (int balance)
# ============================================================================
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }

inventory_controller<public> := class:

    Logger<private> : log = log{Channel := log_inv_ch}

    # ── Durable Ownership ────────────────────────────────────────────────────
    var HasAnalyticsPass<public>     : logic = false
    var ArenaSkinsOwned<public>      : int = 0
    var EquippedArenaSkin<public>    : int = 0

    # ── Consumable Balances ──────────────────────────────────────────────────
    var ChallengeTokens<public>      : int = 0
    var SpeedBootsCharges<public>    : int = 0
    var SlowMoReplayCharges<public>  : int = 0

    # ── Transaction History ──────────────────────────────────────────────────
    var TotalPurchaseCount<public>   : int = 0
    var TotalVBucksSpent<public>     : int = 0
    var TotalTokensConsumed<public>  : int = 0

    # ── Session Tracking ─────────────────────────────────────────────────────
    var SessionPurchaseCount<private>: int = 0
    var IsLoaded<private>            : logic = false

    # ══════════════════════════════════════════════════════════════════════════
    # LOAD / EXPORT — Persistence bridge
    # ══════════════════════════════════════════════════════════════════════════
    LoadFromData<public>(Data : player_economy_data_v1) : void =
        set HasAnalyticsPass = Data.HasAnalyticsPass
        set ArenaSkinsOwned = Data.ArenaSkinsOwned
        set ChallengeTokens = Data.ChallengeTokens
        set EquippedArenaSkin = Data.EquippedArenaSkin
        set TotalVBucksSpent = Data.TotalVBucksSpent
        set TotalPurchaseCount = Data.TotalPurchaseCount
        set IsLoaded = true
        Logger.Print("INVENTORY: Loaded. Pass:{if (HasAnalyticsPass?) then "true" else "false"} Skins:{ArenaSkinsOwned} Tokens:{ChallengeTokens} Skin:{EquippedArenaSkin}")

    ExportToData<public>() : player_economy_data_v1 =
        player_economy_data_v1{
            HasAnalyticsPass := HasAnalyticsPass,
            ArenaSkinsOwned := ArenaSkinsOwned,
            ChallengeTokens := ChallengeTokens,
            EquippedArenaSkin := EquippedArenaSkin,
            TotalVBucksSpent := TotalVBucksSpent,
            TotalPurchaseCount := TotalPurchaseCount
        }

    # ══════════════════════════════════════════════════════════════════════════
    # GENERIC ITEM API — String-based for readability
    # ══════════════════════════════════════════════════════════════════════════
    HasItem<public>(ItemID : string) : logic =
        if (ItemID = "analytics_pass"):
            return HasAnalyticsPass
        else if (ItemID = "arena_cyber"):
            return IsSkinOwned(2)
        else if (ItemID = "arena_neon"):
            return IsSkinOwned(3)
        else if (ItemID = "arena_classic"):
            return IsSkinOwned(4)
        else if (ItemID = "arena_tournament"):
            return IsSkinOwned(5)
        else if (ItemID = "challenge_token"):
            if (ChallengeTokens > 0):
                return true
            return false
        else if (ItemID = "speed_boots"):
            if (SpeedBootsCharges > 0):
                return true
            return false
        else if (ItemID = "slowmo_replay"):
            if (SlowMoReplayCharges > 0):
                return true
            return false
        false

    GrantItem<public>(ItemID : string) : logic =
        if (ItemID = "analytics_pass"):
            return PurchaseAnalyticsPass()
        else if (ItemID = "arena_cyber"):
            return PurchaseArenaSkin(2)
        else if (ItemID = "arena_neon"):
            return PurchaseArenaSkin(3)
        else if (ItemID = "arena_classic"):
            return PurchaseArenaSkin(4)
        else if (ItemID = "arena_tournament"):
            return PurchaseArenaSkin(5)
        else if (ItemID = "challenge_token"):
            return PurchaseChallengeTokens(1)
        else if (ItemID = "challenge_token_5"):
            return PurchaseChallengeTokens(5)
        else if (ItemID = "challenge_token_10"):
            return PurchaseChallengeTokens(10)
        else if (ItemID = "speed_boots"):
            set SpeedBootsCharges += 1
            Logger.Print("INVENTORY: Speed Boots granted. Charges: {SpeedBootsCharges}")
            return true
        else if (ItemID = "slowmo_replay"):
            set SlowMoReplayCharges += 1
            Logger.Print("INVENTORY: Slow-Mo Replay granted. Charges: {SlowMoReplayCharges}")
            return true
        Logger.Print("INVENTORY: Unknown item ID: {ItemID}")
        false

    ConsumeItem<public>(ItemID : string) : logic =
        if (ItemID = "challenge_token"):
            return ConsumeChallengeToken()
        else if (ItemID = "speed_boots"):
            return ConsumeSpeedBoots()
        else if (ItemID = "slowmo_replay"):
            return ConsumeSlowMoReplay()
        Logger.Print("INVENTORY: Cannot consume non-consumable item: {ItemID}")
        false

    GetItemBalance<public>(ItemID : string) : int =
        if (ItemID = "challenge_token"):
            return ChallengeTokens
        else if (ItemID = "speed_boots"):
            return SpeedBootsCharges
        else if (ItemID = "slowmo_replay"):
            return SlowMoReplayCharges
        0

    # ══════════════════════════════════════════════════════════════════════════
    # TYPED PURCHASE METHODS — Called by shop_manager
    # ══════════════════════════════════════════════════════════════════════════
    PurchaseAnalyticsPass<public>() : logic =
        if (HasAnalyticsPass?):
            Logger.Print("INVENTORY: Analytics Pass already owned.")
            return false
        set HasAnalyticsPass = true
        set TotalPurchaseCount += 1
        set SessionPurchaseCount += 1
        Logger.Print("INVENTORY: Analytics Pass purchased.")
        true

    PurchaseArenaSkin<public>(SkinId : int) : logic =
        Owned := IsSkinOwned(SkinId)
        if (Owned?):
            Logger.Print("INVENTORY: Arena skin #{SkinId} already owned.")
            return false
        # Set the bit for this skin ID
        SkinBit := BitShiftLeft(1, SkinId)
        set ArenaSkinsOwned = ArenaSkinsOwned + SkinBit
        set TotalPurchaseCount += 1
        set SessionPurchaseCount += 1
        Logger.Print("INVENTORY: Arena skin #{SkinId} purchased. Bitfield: {ArenaSkinsOwned}")
        true

    PurchaseChallengeTokens<public>(Count : int) : logic =
        if (Count <= 0):
            return false
        set ChallengeTokens += Count
        set TotalPurchaseCount += 1
        set SessionPurchaseCount += 1
        Logger.Print("INVENTORY: {Count} challenge tokens purchased. Total: {ChallengeTokens}")
        true

    # ══════════════════════════════════════════════════════════════════════════
    # CONSUMPTION METHODS
    # ══════════════════════════════════════════════════════════════════════════
    ConsumeChallengeToken<public>() : logic =
        if (ChallengeTokens > 0):
            set ChallengeTokens -= 1
            set TotalTokensConsumed += 1
            Logger.Print("INVENTORY: Token consumed. Remaining: {ChallengeTokens}")
            return true
        Logger.Print("INVENTORY: No challenge tokens available!")
        false

    ConsumeSpeedBoots<private>() : logic =
        if (SpeedBootsCharges > 0):
            set SpeedBootsCharges -= 1
            Logger.Print("INVENTORY: Speed Boots consumed. Remaining: {SpeedBootsCharges}")
            return true
        Logger.Print("INVENTORY: No Speed Boots charges!")
        false

    ConsumeSlowMoReplay<private>() : logic =
        if (SlowMoReplayCharges > 0):
            set SlowMoReplayCharges -= 1
            Logger.Print("INVENTORY: Slow-Mo Replay consumed. Remaining: {SlowMoReplayCharges}")
            return true
        Logger.Print("INVENTORY: No Slow-Mo Replay charges!")
        false

    # ══════════════════════════════════════════════════════════════════════════
    # SKIN MANAGEMENT
    # ══════════════════════════════════════════════════════════════════════════
    IsSkinOwned<public>(SkinId : int) : logic =
        SkinBit := BitShiftLeft(1, SkinId)
        ASO := ArenaSkinsOwned
        Result := BitwiseAnd(ASO, SkinBit)
        if (Result > 0):
            return true
        false

    EquipSkin<public>(SkinId : int) : logic =
        if (SkinId = 0):
            # Default skin — always available
            set EquippedArenaSkin = 0
            Logger.Print("INVENTORY: Default arena skin equipped.")
            return true
        Owned := IsSkinOwned(SkinId)
        if (Owned?):
            set EquippedArenaSkin = SkinId
            Logger.Print("INVENTORY: Arena skin #{SkinId} equipped.")
            return true
        Logger.Print("INVENTORY: Cannot equip unowned skin #{SkinId}.")
        false

    GetOwnedSkinCount<public>() : int =
        var Count : int = 0
        var Bit : int = 1
        loop:
            if (Bit > 32):
                break
            ASO := ArenaSkinsOwned
            Mask := BitShiftLeft(1, Bit)
            Result := BitwiseAnd(ASO, Mask)
            if (Result > 0):
                set Count += 1
            set Bit += 1
        Count

    # ══════════════════════════════════════════════════════════════════════════
    # FEATURE GATES — Other modules check these to gate premium content
    # ══════════════════════════════════════════════════════════════════════════
    CanAccessAdvancedAnalytics<public>() : logic =
        HasAnalyticsPass

    CanAccessEliteBots<public>() : logic =
        HasAnalyticsPass

    CanEnterChallenge<public>() : logic =
        if (ChallengeTokens > 0):
            return true
        false

    HasActiveModifier<public>(ModifierName : string) : logic =
        if (ModifierName = "speed_boots"):
            if (SpeedBootsCharges > 0):
                return true
        else if (ModifierName = "slowmo_replay"):
            if (SlowMoReplayCharges > 0):
                return true
        false

    # ══════════════════════════════════════════════════════════════════════════
    # BITWISE UTILITIES
    # ══════════════════════════════════════════════════════════════════════════
    BitShiftLeft<private>(Value : int, Positions : int) : int =
        var Result : int = Value
        var I : int = 0
        loop:
            if (I >= Positions):
                break
            set Result = Result * 2
            set I += 1
        Result

    BitwiseAnd<private>(A : int, B : int) : int =
        if (B > 0):
            DivRat := (A * 1.0) / (B * 1.0)
            if (Divided := Floor[DivRat]):
                ModRat := (Divided * 1.0) / 2.0
                if (ModBase := Floor[ModRat]):
                    Remainder := Divided - (ModBase * 2)
                    return Remainder * B
        0

    # ══════════════════════════════════════════════════════════════════════════
    # TELEMETRY
    # ══════════════════════════════════════════════════════════════════════════
    LogInventory<public>() : void =
        Logger.Print("INVENTORY: ── State ──")
        Logger.Print("INVENTORY:   Pass: {if (HasAnalyticsPass?) then "true" else "false"}")
        Logger.Print("INVENTORY:   Skins Owned: {ArenaSkinsOwned} Equipped: {EquippedArenaSkin}")
        Logger.Print("INVENTORY:   Tokens: {ChallengeTokens} Consumed: {TotalTokensConsumed}")
        Logger.Print("INVENTORY:   Speed Boots: {SpeedBootsCharges}")
        Logger.Print("INVENTORY:   Slow-Mo: {SlowMoReplayCharges}")
        Logger.Print("INVENTORY:   Purchases: {TotalPurchaseCount} Session: {SessionPurchaseCount}")

log_inv_ch := class(log_channel):