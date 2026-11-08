using { /Fortnite.com/Itemization }
using { /Fortnite.com/Armory }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Items }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Itemization }
using { /UnrealEngine.com/Temporary/Diagnostics }

coach_weapon_role := enum:
    Rifle
    Shotgun
    NativeRanged

coach_fire_cadence := struct:
    Role : coach_weapon_role
    Pulse : float
    Recovery : float

CoachRemoveOwnedItem(ItemEntity : entity):logic =
    if (Weapon := ItemEntity.GetComponent[fort_trace_weapon_component]):
        Weapon.EndFire()
    if (Item := ItemEntity.GetComponent[item_component]):
        if (Item.IsEquipped[]):
            Unequipped := Item.Unequip()
            if (not Unequipped.GetSuccess[]):
                Print("PCL|equipment|owned_item_retained|unequip_rejected", ?Duration := 0.0)
                return false
        if (Inventory := Item.GetParentInventory[]):
            Removed := Inventory.RemoveItem(ItemEntity)
            if (not Removed.GetSuccess[]):
                Print("PCL|equipment|owned_item_retained|inventory_removal_rejected", ?Duration := 0.0)
                return false
    ItemEntity.RemoveFromParent()
    return true

# Native inventory operations; no fabricated shots, damage or client input.
coach_tool_hold_component := class<final_super>(component):
    var Locked : logic = false
    var OwnerInventory : ?inventory_component = false
    var VetoCount : int = 0
    var BlockEquip : logic = false
    var NPCOwner : ?agent = false
    var EquipQueries : int = 0

    OnReceive<override>(Event : scene_event):logic =
        if (EquipQuery := equip_item_query_event[Event], EquipQuery.Item.Entity = Entity):
            set EquipQueries += 1
            if (Locked?, BlockEquip?, Owner := NPCOwner?, CurrentInventory := EquipQuery.Item.GetParentInventory[]):
                for (Inventory : Owner.FindDescendantComponents(inventory_component), Inventory = CurrentInventory):
                    EquipQuery.AddError(equip_item_error{})
                    set VetoCount += 1
                    return false
        if (Locked?, not BlockEquip?, Inventory := OwnerInventory?, Query := unequip_item_query_event[Event], Query.Item.Entity = Entity, Query.Item.GetParentInventory[] = Inventory):
            Query.AddError(unequip_item_error{})
            set VetoCount += 1
        return false

# Private opt-in experiment: native callbacks record intent loss; the next
# post-physics callback reconciles outside the inventory event stack.
coach_tool_intent_component := class<final_super>(component):
    var Active : logic = false
    var Pending : logic = false
    var Attempts : int = 0
    var Ticks : int = 0
    var LostAt : float = 0.0
    var Subscriptions : []cancelable = array{}
    var RangedItem : ?item_component = false

    Start(RifleItem : item_component):void =
        Stop()
        set RangedItem = option{RifleItem}
        if (PlanItem := Entity.GetComponent[item_component], Rifle := RifleItem.Entity.GetComponent[fort_weapon_component]):
            set Subscriptions = array{
                PlanItem.ChangeEquippedEvent.Subscribe(OnEquipmentChanged),
                RifleItem.ChangeEquippedEvent.Subscribe(OnEquipmentChanged),
                Rifle.HolsterChangedEvent.Subscribe(OnHolsterChanged),
                TickEvents.PostPhysics.Subscribe(Reconcile)
            }

    SetIntent(Hold : logic):void =
        set Active = Hold
        set Pending = false
        set Attempts = 0

    OnEquipmentChanged(Change : change_equipped_result):void =
        MarkLoss()

    OnHolsterChanged(Empty : tuple()):void =
        MarkLoss()

    MarkLoss():void =
        if (Active?, not Pending?, Item := Entity.GetComponent[item_component], not Item.IsEquipped[]):
            set Pending = true
            set LostAt = GetSimulationElapsedTime()

    Reconcile(DeltaTime : float):void =
        set Ticks += 1
        if (Active?, Pending?):
            set Pending = false
            if (Attempts >= 8):
                set Active = false
                Print("PCL|equipment|tool_reconcile_budget_exhausted", ?Duration := 0.0)
                return
            if (Item := Entity.GetComponent[item_component], Item.GetParentInventory[], not Item.IsEquipped[]):
                set Attempts += 1
                if (RifleItem := RangedItem?, RifleItem.IsEquipped[]):
                    if (Weapon := RifleItem.Entity.GetComponent[fort_trace_weapon_component]):
                        Weapon.EndFire()
                    Released := RifleItem.Unequip()
                    if (not Released.GetSuccess[]):
                        Print("PCL|equipment|tool_reconcile_release_rejected|attempt={Attempts}", ?Duration := 0.0)
                        return
                Result := Item.Equip()
                var Success : int = 0
                if (Result.GetSuccess[]):
                    set Success = 1
                Print("PCL|equipment|tool_reconcile|attempt={Attempts}|success={Success}|delay={GetSimulationElapsedTime() - LostAt}|post_physics|render_unverified", ?Duration := 0.0)

    Stop():void =
        set Active = false
        set Pending = false
        if (Subscriptions.Length > 0):
            Print("PCL|equipment|tool_intent_stopped|subscriptions={Subscriptions.Length}|ticks={Ticks}|attempts={Attempts}", ?Duration := 0.0)
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        set RangedItem = false

    OnEndSimulation<override>():void =
        Stop()

coach_equipment := class:
    var EnableToolQueryGuards : logic = false
    var EnableToolIntentReconciliation : logic = false
    var BuildPlanIntent : ?coach_tool_intent_component = false
    var BuildPlan : ?entity = false
    var BuildPlanLock : ?coach_tool_hold_component = false
    var LastPlanAttempt : float = -100.0
    var LastRanged : ?item_component = false
    var ManagedRifle : ?entity = false
    var ManagedShotgun : ?entity = false
    var ManagedRifleGate : ?coach_tool_hold_component = false
    var ManagedShotgunGate : ?coach_tool_hold_component = false
    var ManagedResourceBag : ?entity = false
    var ManagedWood : ?entity = false
    var ManagedShells : ?entity = false
    var ShellsPreparationAttempted : logic = false
    var ShellsProvisioned : logic = false
    var StockPreparationAttempted : logic = false
    var ParkedRanged : []tuple(entity, inventory_component) = array{}

    # NPC-only inventory replacement. Keep original objects for rollback and teardown.
    InitializeNPCLoadout(Owner : agent):logic =
        if (player[Owner]):
            return false
        if (Rifle := ManagedRifle?, Item := Rifle.GetComponent[item_component], Item.GetParentInventory[], Shotgun := ManagedShotgun?, CloseItem := Shotgun.GetComponent[item_component], CloseItem.GetParentInventory[]):
            return true
        if (ParkedRanged.Length > 0 or ManagedRifle? or ManagedShotgun?):
            return false
        var Candidates : []tuple(entity, inventory_component) = array{}
        for (Inventory : Owner.FindDescendantComponents(inventory_component), Original : Inventory.GetItems(), Item := Original.GetComponent[item_component]):
            for (Category : Item.Categories, Category = FortniteItemCategories.WeaponRanged):
                set Candidates += array{(Original, Inventory)}
        for (Pair : Candidates):
            if (Item := Pair(0).GetComponent[item_component], Item.IsEquipped[]):
                Unequipped := Item.Unequip()
                if (not Unequipped.GetSuccess[]):
                    UnequipRollback := DisposeLoadout()
                    Print("PCL|equipment|loadout_not_ready|original_unequip_rejected", ?Duration := 0.0)
                    return false
            Removed := Pair(1).RemoveItem(Pair(0))
            if (not Removed.GetSuccess[]):
                RemovalRollback := DisposeLoadout()
                Print("PCL|equipment|loadout_not_ready|original_removal_rejected", ?Duration := 0.0)
                return false
            set ParkedRanged += array{Pair}
        if (Root := Owner.GetSimulationEntity[]):
            Rifle := assault_rifle_template{}
            Root.AddEntities(array{Rifle})
            set ManagedRifle = option{Rifle}
            if (EnableToolQueryGuards?):
                Gate := coach_tool_hold_component{Entity := Rifle, BlockEquip := true, NPCOwner := option{Owner}}
                Rifle.AddComponents(array{Gate})
                set ManagedRifleGate = option{Gate}
            Shotgun := shotgun_template{}
            Root.AddEntities(array{Shotgun})
            set ManagedShotgun = option{Shotgun}
            if (EnableToolQueryGuards?):
                Gate := coach_tool_hold_component{Entity := Shotgun, BlockEquip := true, NPCOwner := option{Owner}}
                Shotgun.AddComponents(array{Gate})
                set ManagedShotgunGate = option{Gate}
            RifleAdded := DistributeManagedWeapon(Owner, Rifle)
            ShotgunAdded := DistributeManagedWeapon(Owner, Shotgun)
            if (RifleAdded?, ShotgunAdded?):
                Equipped := SelectWeapon(Owner, 1500.0)
                if (Equipped?):
                    ShellsReady := InitializeShotgunAmmo(Owner)
                    StockReady := InitializeConstructionStock(Owner)
                    Print("PCL|equipment|npc_loadout_prepared|parked={ParkedRanged.Length}|rifle_and_shotgun|firing_requires_gameplay_acceptance", ?Duration := 0.0)
                    return true
        AddRollback := DisposeLoadout()
        Print("PCL|equipment|loadout_not_ready|owned_rifle_add_or_equip_rejected", ?Duration := 0.0)
        return false

    DistributeManagedWeapon(Owner : agent, Weapon : entity):logic =
        for (Child : Owner.GetEntities(), Inventory := Child.GetComponent[inventory_component]):
            Added := Inventory.AddItemDistribute(Weapon)
            if (Added.GetSuccess[]):
                if (Item := Weapon.GetComponent[item_component], Item.GetParentInventory[]):
                    return true
                return false
        return false

    # Use public runtime item/inventory operations. The editor's instance-only
    # Items restriction is respected; no template array or flags are mutated.
    InitializeShotgunAmmo(Owner : agent):logic =
        if (player[Owner]):
            return false
        if (ShellsPreparationAttempted?):
            return ShellsProvisioned
        set ShellsPreparationAttempted = true
        if (Root := Owner.GetSimulationEntity[]):
            Shells := AmmoShells_BR_PreSeason_Common{}
            Root.AddEntities(array{Shells})
            set ManagedShells = option{Shells}
            if (Stack := Shells.GetComponent[stackable_component]):
                Stack.SetMaxStackSize(option{500})
                Stack.SetStackSize(500)
                for (Inventory : Owner.FindDescendantComponents(fort_inventory_ammo_component), Stack.StackSize = 500):
                    Added := Inventory.AddItem(Shells)
                    if (Added.GetSuccess[]):
                        set ShellsProvisioned = true
                        if (Item := Shells.GetComponent[item_component], Item.GetParentInventory[]):
                            return true
                        # A native stack merge may consume the source entity.
                        # Remove only that source, never an existing destination stack.
                        Shells.RemoveFromParent()
                        set ManagedShells = false
                        return true
            Released := DisposeShotgunAmmo()
        return false

    DisposeShotgunAmmo():logic =
        if (Shells := ManagedShells?):
            Released := CoachRemoveOwnedItem(Shells)
            if (not Released?):
                return false
        set ManagedShells = false
        set ShellsProvisioned = false
        return true

    InitializeConstructionStock(Owner : agent):logic =
        if (player[Owner]):
            return false
        if (Wood := ManagedWood?, Item := Wood.GetComponent[item_component], Item.GetParentInventory[]):
            return true
        if (ManagedResourceBag? or ManagedWood?):
            return false
        if (StockPreparationAttempted?):
            return false
        set StockPreparationAttempted = true
        if (Character := Owner.GetFortCharacter[], Body := Character.GetEntity[]):
            Bag := entity{}
            Inventory := fort_inventory_resources_component{Entity := Bag}
            Bag.AddComponents(array{Inventory})
            Body.AddEntities(array{Bag})
            set ManagedResourceBag = option{Bag}
            Wood := Wood_BR_PreSeason_Common{}
            Bag.AddEntities(array{Wood})
            set ManagedWood = option{Wood}
            if (Stack := Wood.GetComponent[stackable_component]):
                Stack.SetMaxStackSize(option{999})
                Stack.SetStackSize(999)
                Added := Inventory.AddItem(Wood)
                if (Added.GetSuccess[], Stack.StackSize = 999):
                    return true
            Released := DisposeConstructionStock()
        return false

    DisposeConstructionStock():logic =
        if (Wood := ManagedWood?):
            Released := CoachRemoveOwnedItem(Wood)
            if (not Released?):
                return false
        set ManagedWood = false
        if (Bag := ManagedResourceBag?):
            Bag.RemoveFromParent()
        set ManagedResourceBag = false
        return true

    DisposeLoadout():logic =
        SetBuildPlanLock(false)
        if (Rifle := ManagedRifle?):
            Removed := CoachRemoveOwnedItem(Rifle)
            if (not Removed?):
                return false
            set ManagedRifle = false
            set ManagedRifleGate = false
        if (Shotgun := ManagedShotgun?):
            Removed := CoachRemoveOwnedItem(Shotgun)
            if (not Removed?):
                return false
            set ManagedShotgun = false
            set ManagedShotgunGate = false
        StockRemoved := DisposeConstructionStock()
        if (not StockRemoved?):
            return false
        ShellsRemoved := DisposeShotgunAmmo()
        if (not ShellsRemoved?):
            return false
        var Pending : []tuple(entity, inventory_component) = array{}
        for (Pair : ParkedRanged):
            Restored := Pair(1).AddItemDistribute(Pair(0))
            if (not Restored.GetSuccess[]):
                set Pending += array{Pair}
        set ParkedRanged = Pending
        set LastRanged = false
        if (Pending.Length > 0):
            Print("PCL|equipment|loadout_cleanup_pending|items={Pending.Length}", ?Duration := 0.0)
            return false
        return true

    RememberRanged(Owner : agent):void =
        for (Inventory : Owner.FindDescendantComponents(inventory_component), Item : Inventory.GetItems(), Component := Item.GetComponent[item_component], Component.IsEquipped[]):
            for (Category : Component.Categories, Category = FortniteItemCategories.WeaponRanged):
                set LastRanged = option{Component}

    EquipBuildPlan(Owner : agent):logic =
        if (player[Owner]):
            return false
        StopFiring(Owner)
        RememberRanged(Owner)
        Prepared := PrepareBuildPlan(Owner)
        if (not Prepared?):
            return false
        if (Existing := BuildPlan?, Item := Existing.GetComponent[item_component]):
            SetBuildPlanLock(true)
            if (Item.IsEquipped[]):
                return true
            Equipped := Item.Equip()
            if (Equipped.GetSuccess[]):
                return true
            SetBuildPlanLock(false)
            return false
        return false

    BuildPlanEquipped(Owner : agent)<transacts>:logic =
        if (Plan := BuildPlan?, Item := Plan.GetComponent[item_component], Item.IsEquipped[], Parent := Item.GetParentInventory[]):
            for (Inventory : Owner.FindDescendantComponents(inventory_component), Inventory = Parent):
                return true
        return false

    ReleaseConstruction(Owner : agent):void =
        SetBuildPlanLock(false)
        if (Plan := BuildPlan?, Item := Plan.GetComponent[item_component], Item.IsEquipped[]):
            Released := Item.Unequip()
            if (not Released.GetSuccess[]):
                return
        if (Previous := LastRanged?, Parent := Previous.GetParentInventory[]):
            for (Inventory : Owner.FindDescendantComponents(inventory_component), Inventory = Parent):
                if (Previous.IsEquipped[]):
                    return
                Restored := Previous.Equip()
                return

    PrepareBuildPlan(Owner : agent):logic =
        if (player[Owner]):
            return false
        if (Existing := BuildPlan?, Item := Existing.GetComponent[item_component], Item.GetParentInventory[]):
            return true
        if (BuildPlan?):
            return false
        if (GetSimulationElapsedTime() - LastPlanAttempt < 1.0):
            return false
        set LastPlanAttempt = GetSimulationElapsedTime()
        if (Root := Owner.GetSimulationEntity[]):
            Plan := Art.CoachTools.PCL_BuildPlan{}
            Root.AddEntities(array{Plan})
            set BuildPlan = option{Plan}
            if (EnableToolQueryGuards?):
                Lock := coach_tool_hold_component{Entity := Plan}
                Plan.AddComponents(array{Lock})
                set BuildPlanLock = option{Lock}
            # Preserve the prefab's authored grip/pose rather than installing an empty override.
            for (Child : Owner.GetEntities(), Inventory := Child.GetComponent[inventory_component]):
                Added := Inventory.AddItemDistribute(Plan)
                if (Added.GetSuccess[]):
                    if (Item := Plan.GetComponent[item_component]):
                        if (EnableToolIntentReconciliation?, Rifle := ManagedRifle?, RifleItem := Rifle.GetComponent[item_component]):
                            Intent := coach_tool_intent_component{Entity := Plan}
                            Plan.AddComponents(array{Intent})
                            Intent.Start(RifleItem)
                            set BuildPlanIntent = option{Intent}
                        Print("PCL|equipment|plan_prepared|equip_not_requested|npc_pose_unverified", ?Duration := 0.0)
                        return true
                    return false
            DisposeBuildPlan()
        return false

    SetBuildPlanLock(Hold : logic):void =
        if (Intent := BuildPlanIntent?):
            Intent.SetIntent(Hold)
        if (Lock := BuildPlanLock?):
            set Lock.Locked = false
            set Lock.OwnerInventory = false
            if (Hold?, Plan := BuildPlan?, Item := Plan.GetComponent[item_component], Inventory := Item.GetParentInventory[]):
                set Lock.OwnerInventory = option{Inventory}
                set Lock.Locked = true
        if (Gate := ManagedRifleGate?):
            set Gate.Locked = false
            if (Hold?, Lock := BuildPlanLock?, Lock.Locked?):
                set Gate.Locked = true
        if (Gate := ManagedShotgunGate?):
            set Gate.Locked = false
            if (Hold?, Lock := BuildPlanLock?, Lock.Locked?):
                set Gate.Locked = true

    DisposeBuildPlan():void =
        SetBuildPlanLock(false)
        if (Intent := BuildPlanIntent?):
            Intent.Stop()
        if (Plan := BuildPlan?):
            Removed := CoachRemoveOwnedItem(Plan)
            if (not Removed?):
                return
        set BuildPlan = false
        set BuildPlanLock = false
        set BuildPlanIntent = false

    ConfigureAim(Owner : agent, Challenge : float):void =
        # Models aim error on the opponent's own item instances. Damage and fire rate stay native.
        Spread := 1.0 + (1.0 - Clamp(Challenge, 0.0, 1.0)) * 3.5
        for (Inventory : Owner.FindDescendantComponents(inventory_component), Item : Inventory.GetItems()):
            if (Weapon := Item.GetComponent[fort_trace_weapon_component]):
                Weapon.SetIdleSpreadMultiplier(Spread)
                Weapon.SetMovingSpreadMultiplier(Spread)
                Weapon.SetCrouchingSpreadMultiplier(Spread)

    IsEquippedBy(WeaponEntity : entity, Owner : agent)<transacts>:logic =
        if (Item := WeaponEntity.GetComponent[item_component], Item.IsEquipped[], Parent := Item.GetParentInventory[]):
            for (Inventory : Owner.FindDescendantComponents(inventory_component), Parent = Inventory):
                return true
        return false

    CurrentWeaponRole(Owner : agent)<transacts>:coach_weapon_role =
        if (Weapon := ManagedShotgun?, IsEquippedBy(Weapon, Owner)?):
            return coach_weapon_role.Shotgun
        if (Weapon := ManagedRifle?, IsEquippedBy(Weapon, Owner)?):
            return coach_weapon_role.Rifle
        return coach_weapon_role.NativeRanged

    RangedReady(Owner : agent)<transacts>:logic =
        if (player[Owner] or BuildPlanEquipped(Owner)?):
            return false
        if (ManagedRifle? or ManagedShotgun?):
            return logic{CurrentWeaponRole(Owner) <> coach_weapon_role.NativeRanged}
        for (Inventory : Owner.FindDescendantComponents(inventory_component), Weapon : Inventory.GetItems(), Item := Weapon.GetComponent[item_component], Item.IsEquipped[]):
            for (Category : Item.Categories, Category = FortniteItemCategories.WeaponRanged):
                return true
        return false

    StopFiring(Owner : agent):void =
        if (player[Owner]):
            return
        for (Candidate : array{ManagedRifle, ManagedShotgun}, WeaponEntity := Candidate?, Weapon := WeaponEntity.GetComponent[fort_trace_weapon_component]):
            Weapon.EndFire()

    # Some(false) is observed non-firing; None means this loadout has no trace feedback.
    # Neither value identifies magazine contents or a reload state.
    NativeFiringState(Owner : agent)<transacts>:?logic =
        for (Candidate : array{ManagedRifle, ManagedShotgun}, WeaponEntity := Candidate?, IsEquippedBy(WeaponEntity, Owner)?, Weapon := WeaponEntity.GetComponent[fort_trace_weapon_component]):
            return option{logic{Weapon.IsFiring[]}}
        return false

    WeaponStartupAllowance(Owner : agent, ShortOpening : logic)<transacts>:float =
        if (ShortOpening?):
            return 0.35
        for (Candidate : array{ManagedRifle, ManagedShotgun}, WeaponEntity := Candidate?, IsEquippedBy(WeaponEntity, Owner)?, Weapon := WeaponEntity.GetComponent[fort_trace_weapon_component]):
            return Clamp(Weapon.ReloadTime + 0.35, 0.5, 4.5)
        return 0.35

    # Trigger opportunity windows are derived from the equipped weapon's native
    # rate. They are not shot counters and never change weapon damage/fire rate.
    FireCadence(Owner : agent, Challenge : float, Style : coach_style)<transacts>:coach_fire_cadence =
        Role := CurrentWeaponRole(Owner)
        Level := Clamp(Challenge, 0.0, 1.0)
        var Rate : float = 5.0
        if (Role = coach_weapon_role.Shotgun, WeaponEntity := ManagedShotgun?, Weapon := WeaponEntity.GetComponent[fort_trace_weapon_component]):
            set Rate = Max(0.25, Weapon.FireRate)
        else if (Role = coach_weapon_role.Rifle, WeaponEntity := ManagedRifle?, Weapon := WeaponEntity.GetComponent[fort_trace_weapon_component]):
            set Rate = Max(0.25, Weapon.FireRate)
        var Pulse : float = Clamp((3.0 + Level * 2.0) / Rate, 0.18, 0.65)
        var Recovery : float = 0.12 + (1.0 - Level) * 0.25
        if (Role = coach_weapon_role.Shotgun):
            set Pulse = Clamp(0.85 / Rate, 0.18, 0.85)
            set Recovery = Max(0.12, 1.0 / Rate - Pulse + 0.08 + (1.0 - Level) * 0.15)
        if (Style = coach_style.Patient):
            set Recovery += 0.12
        else if (Style = coach_style.Pressure):
            set Recovery = Max(0.08, Recovery - 0.04)
        return coach_fire_cadence{Role := Role, Pulse := Pulse, Recovery := Recovery}

    SelectWeapon(Owner : agent, RangeCm : float):logic =
        SetBuildPlanLock(false)
        if (Plan := BuildPlan?, PlanItem := Plan.GetComponent[item_component], PlanItem.IsEquipped[]):
            Released := PlanItem.Unequip()
            if (not Released.GetSuccess[]):
                Print("PCL|equipment|tool_release_before_rifle_rejected", ?Duration := 0.0)
                return false
            Print("PCL|equipment|tool_release_before_rifle_ok", ?Duration := 0.0)
        var Selected : ?item_component = false
        var BestScore : float = -1.0
        var NativeFallback : ?item_component = false
        var FallbackScore : int = -1
        # Weapon roles avoid comparing shotgun pellet damage with rifle shot damage.
        # Retain a selected shotgun through the middle band to avoid rapid swapping.
        var CloseRange : logic = false
        if (RangeCm <= 850.0):
            set CloseRange = true
        if (Shotgun := ManagedShotgun?, CloseItem := Shotgun.GetComponent[item_component], CloseItem.IsEquipped[], RangeCm < 1150.0):
            set CloseRange = true
        if (CloseRange?, ShellsProvisioned?, Shotgun := ManagedShotgun?, CloseItem := Shotgun.GetComponent[item_component], CloseItem.GetParentInventory[]):
            set Selected = option{CloseItem}
        else if (Rifle := ManagedRifle?, RifleItem := Rifle.GetComponent[item_component], RifleItem.GetParentInventory[]):
            set Selected = option{RifleItem}
        for (Inventory : Owner.FindDescendantComponents(inventory_component), Item : Inventory.GetItems()):
            if (Component := Item.GetComponent[item_component], Weapon := Item.GetComponent[fort_trace_weapon_component]):
                var Score : float = Weapon.FireRate
                if (RangeCm < 900.0):
                    set Score = Weapon.Damage
                if (not ManagedRifle? and not ManagedShotgun? and Score > BestScore):
                    set BestScore = Score
                    set Selected = option{Component}
            if (Component := Item.GetComponent[item_component]):
                for (Category : Component.Categories, Category = FortniteItemCategories.WeaponRanged):
                    var Score : int = 0
                    if (Previous := LastRanged?, Previous = Component):
                        set Score = 1
                    if (Component.IsEquipped[]):
                        set Score = 2
                    if (Score > FallbackScore):
                        set FallbackScore = Score
                        set NativeFallback = option{Component}
        # Legacy native ranged items were observed without trace-weapon components.
        # Keep the equipped/previous ranged item when those statistics are unavailable.
        if (not Selected?):
            set Selected = NativeFallback
        if (Component := Selected?):
            if (Component.IsEquipped[]):
                set LastRanged = option{Component}
                return true
            StopFiring(Owner)
            Result := Component.Equip()
            if (Result.GetSuccess[]):
                set LastRanged = option{Component}
                Print("PCL|equipment|native_equip_returned_ok", ?Duration := 0.0)
                return true
            if (Errors := Result.GetError[]):
                Print("PCL|equipment|native_equip_rejected|errors={Errors.Length}", ?Duration := 0.0)
        return false

    # Debit wood by prefab identity; other materials in the same inventory are not a substitute.
    CanAffordWood(Owner : agent, Cost : int)<transacts>:logic =
        if (Cost <= 0):
            return false
        for (Inventory : Owner.FindDescendantComponents(fort_inventory_resources_component)):
            for (Item : Inventory.GetItems(), Wood_BR_PreSeason_Common[Item], Stack := Item.GetComponent[stackable_component], Stack.StackSize >= Cost):
                return true
        return false

    ConsumeWood(Owner : agent, Cost : int):logic =
        if (Cost <= 0):
            return false
        for (Inventory : Owner.FindDescendantComponents(fort_inventory_resources_component)):
            for (Item : Inventory.GetItems(), Wood_BR_PreSeason_Common[Item], Stack := Item.GetComponent[stackable_component], Stack.StackSize >= Cost):
                Remaining := Stack.StackSize - Cost
                if (Remaining > 0):
                    Stack.SetStackSize(Remaining)
                    if (Stack.StackSize = Remaining):
                        return true
                else:
                    Removed := Inventory.RemoveItem(Item)
                    if (Removed.GetSuccess[]):
                        Item.RemoveFromParent()
                        return true
        return false
