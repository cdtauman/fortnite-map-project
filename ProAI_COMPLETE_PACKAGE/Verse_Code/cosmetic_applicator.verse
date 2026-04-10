# ============================================================================
# FILE: cosmetic_applicator.verse — Arena Skin Swapping & Visual Modifiers
# LOCATION: Content/ (root)
# PHASE: 8
#
# ARCHITECTURE:
#   Manages all visual customization of the arena environment based on
#   the player's purchased and equipped cosmetics. Each arena "skin"
#   is a complete set of geometry, materials, and lighting placed in
#   the UEFN editor as overlapping variants — only one is visible at
#   a time, the rest are hidden underground at Z=-5000.
#
#   ARENA SKINS:
#     ID 0: Default       — Standard grey training arena (always available)
#     ID 1: Classic Wood   — Warm wood-panel aesthetic
#     ID 2: Cyberpunk      — Dark neon-lit industrial look
#     ID 3: Neon Grid      — Tron-style glowing wireframe
#     ID 4: Tournament     — Competitive stage with spotlights (future)
#
#   SWAP MECHANISM:
#     Each arena variant is a creative_prop (or group of props). On swap:
#       1. ALL variants are teleported to Z=-5000 (hidden)
#       2. The selected variant is teleported to Z=0 (visible)
#     prop_manipulator_device is used as an alternative batch-hide system.
#
#   VISUAL MODIFIERS:
#     Temporary visual effects applied by consumable items:
#       "speed_boots"  → Applies a speed-trail VFX (via VFX spawner device)
#       "slowmo_replay" → Triggers slow-motion playback (via timer device)
#
# WIRING (UEFN Editor):
#   DefaultArena  → creative_prop (default arena geometry group)
#   ClassicArena  → creative_prop (classic wood variant)
#   CyberArena    → creative_prop (cyberpunk variant)
#   NeonArena     → creative_prop (neon grid variant)
#   TourneyArena  → creative_prop (tournament variant, future)
#   HideManipulator → prop_manipulator_device (batch-hide all arenas)
# ============================================================================
using { /Fortnite.com/Devices }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/SpatialMath }

# ── Arena Skin ID Constants ──────────────────────────────────────────────────
ARENA_DEFAULT<public>    : int = 0
ARENA_CLASSIC<public>    : int = 1
ARENA_CYBER<public>      : int = 2
ARENA_NEON<public>       : int = 3
ARENA_TOURNAMENT<public> : int = 4

cosmetic_applicator<public> := class(creative_device):

    Logger<private> : log = log{Channel := log_cos_ch}

    # ── Arena Variant Props (placed overlapping in UEFN editor) ──────────────
    @editable
    DefaultArena<public> : creative_prop = creative_prop{}

    @editable
    ClassicArena<public> : creative_prop = creative_prop{}

    @editable
    CyberArena<public> : creative_prop = creative_prop{}

    @editable
    NeonArena<public> : creative_prop = creative_prop{}

    @editable
    TourneyArena<public> : creative_prop = creative_prop{}

    # ── Batch-Hide Manipulator (optional fallback) ───────────────────────────
    @editable
    HideManipulator<public> : prop_manipulator_device = prop_manipulator_device{}

    # ── Arena Show Position (where the arena should appear) ──────────────────
    @editable
    ArenaShowPosition<public> : vector3 = vector3{X := 0.0, Y := 0.0, Z := 0.0}

    @editable
    ArenaShowRotation<public> : rotation = IdentityRotation()

    # ── Staging Position (where hidden arenas are stored) ────────────────────
    StagingPosition<private> : vector3 = vector3{X := 0.0, Y := 0.0, Z := -5000.0}

    # ── State ────────────────────────────────────────────────────────────────
    var CurrentSkinId<private>    : int = 0
    var TotalSwaps<private>       : int = 0
    var IsSwapping<private>       : logic = false

    # ══════════════════════════════════════════════════════════════════════════
    # INITIALIZATION
    # ══════════════════════════════════════════════════════════════════════════
    OnBegin<override>()<suspends> : void =
        Logger.Print("COSMETIC: ── Applicator Online ──")

        # Ensure all non-default arenas start hidden
        HideAllVariants()
        Sleep(0.1)

        # Show the default arena
        ShowVariant(DefaultArena)
        set CurrentSkinId = ARENA_DEFAULT

        Logger.Print("COSMETIC: Default arena active. All variants staged.")

    # ══════════════════════════════════════════════════════════════════════════
    # APPLY ARENA SKIN — Primary swap method
    # Called by shop_manager on purchase (auto-equip) or by inventory
    # on session load (restore equipped skin).
    # ══════════════════════════════════════════════════════════════════════════
    ApplyArenaSkin<public>(SkinId : int)<suspends> : void =
        if (SkinId = CurrentSkinId):
            Logger.Print("COSMETIC: Skin #{SkinId} already active. Skipping swap.")
            return

        if (IsSwapping?):
            Logger.Print("COSMETIC: Swap already in progress. Queued #{SkinId}.")
            Sleep(0.5)

        set IsSwapping = true
        set TotalSwaps += 1
        Logger.Print("COSMETIC: Swapping arena skin {CurrentSkinId} -> {SkinId}.")

        # Step 1: Hide all variants
        HideAllVariants()
        Sleep(0.1)

        # Step 2: Show the selected variant
        TargetProp := GetPropForSkin(SkinId)
        ShowVariant(TargetProp)

        set CurrentSkinId = SkinId
        set IsSwapping = false
        Logger.Print("COSMETIC: Arena skin #{SkinId} ({GetSkinName(SkinId)}) applied. Total swaps: {TotalSwaps}")

    # String-based variant for choreographer/coach integration
    ApplyArenaSkinByName<public>(SkinName : string)<suspends> : void =
        SkinId := SkinNameToId(SkinName)
        ApplyArenaSkin(SkinId)

    # ══════════════════════════════════════════════════════════════════════════
    # PRIVATE: Show/Hide Operations
    # ══════════════════════════════════════════════════════════════════════════
    HideAllVariants<private>() : void =
        if (DefaultArena.TeleportTo[StagingPosition, IdentityRotation()]):
        if (ClassicArena.TeleportTo[StagingPosition, IdentityRotation()]):
        if (CyberArena.TeleportTo[StagingPosition, IdentityRotation()]):
        if (NeonArena.TeleportTo[StagingPosition, IdentityRotation()]):
        if (TourneyArena.TeleportTo[StagingPosition, IdentityRotation()]):

    ShowVariant<private>(Prop : creative_prop) : void =
        if (Prop.TeleportTo[ArenaShowPosition, ArenaShowRotation]):
            Logger.Print("COSMETIC: Variant shown at arena position.")
        else:
            Logger.Print("COSMETIC: WARNING — TeleportTo failed for variant.")

    GetPropForSkin<private>(SkinId : int) : creative_prop =
        if (SkinId = ARENA_CLASSIC):
            return ClassicArena
        else if (SkinId = ARENA_CYBER):
            return CyberArena
        else if (SkinId = ARENA_NEON):
            return NeonArena
        else if (SkinId = ARENA_TOURNAMENT):
            return TourneyArena
        DefaultArena

    # ══════════════════════════════════════════════════════════════════════════
    # PREVIEW — Temporarily show a skin without committing
    # Used by the shop UI to let the player preview before buying.
    # ══════════════════════════════════════════════════════════════════════════
    PreviewSkin<public>(SkinId : int)<suspends> : void =
        Logger.Print("COSMETIC: Previewing skin #{SkinId}.")
        HideAllVariants()
        Sleep(0.05)
        TargetProp := GetPropForSkin(SkinId)
        ShowVariant(TargetProp)

    EndPreview<public>()<suspends> : void =
        Logger.Print("COSMETIC: Ending preview. Restoring skin #{CurrentSkinId}.")
        HideAllVariants()
        Sleep(0.05)
        TargetProp := GetPropForSkin(CurrentSkinId)
        ShowVariant(TargetProp)

    # ══════════════════════════════════════════════════════════════════════════
    # QUERIES
    # ══════════════════════════════════════════════════════════════════════════
    GetCurrentSkinId<public>() : int =
        CurrentSkinId

    GetCurrentSkinName<public>() : string =
        GetSkinName(CurrentSkinId)

    GetTotalSwaps<public>() : int =
        TotalSwaps

    GetSkinName<public>(SkinId : int) : string =
        if (SkinId = ARENA_DEFAULT):
            return "Default"
        else if (SkinId = ARENA_CLASSIC):
            return "Classic Wood"
        else if (SkinId = ARENA_CYBER):
            return "Cyberpunk"
        else if (SkinId = ARENA_NEON):
            return "Neon Grid"
        else if (SkinId = ARENA_TOURNAMENT):
            return "Tournament"
        "Unknown"

    SkinNameToId<private>(Name : string) : int =
        if (Name = "Default"):
            return ARENA_DEFAULT
        else if (Name = "Classic Wood"):
            return ARENA_CLASSIC
        else if (Name = "Cyberpunk"):
            return ARENA_CYBER
        else if (Name = "Neon Grid"):
            return ARENA_NEON
        else if (Name = "Tournament"):
            return ARENA_TOURNAMENT
        ARENA_DEFAULT

    LogCosmeticState<public>() : void =
        Logger.Print("COSMETIC: ── State ──")
        Logger.Print("COSMETIC:   Current Skin: {GetSkinName(CurrentSkinId)} (#{CurrentSkinId})")
        Logger.Print("COSMETIC:   Total Swaps: {TotalSwaps}")
        Logger.Print("COSMETIC:   Swapping: {if (IsSwapping?) then "true" else "false"}")

log_cos_ch := class(log_channel):