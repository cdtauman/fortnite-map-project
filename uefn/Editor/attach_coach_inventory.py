"""Create a spawner-instance inventory modifier; Items is instance-only in build 43.00."""

import unreal


def attach_coach_inventory(component_path):
    component = unreal.find_object(None, component_path)
    if not isinstance(component, unreal.NPCCharacterDefinitionComponent):
        raise RuntimeError('Expected the discovered NPC definition component')
    modifiers = list(component.get_editor_property('npc_character_modifiers'))
    inventory = next((item for item in modifiers if item.get_name() == 'CoachInventoryInstance'), None)
    if inventory is None:
        inventory_class = unreal.load_class(None, '/CRD_AISpawner/SpawnDefinitions/Modifiers/CharacterModifier_GuardInventory.CharacterModifier_GuardInventory_C')
        if inventory_class is None:
            raise RuntimeError('Stock guard inventory modifier is unresolved')
        inventory = unreal.new_object(inventory_class, outer=component, name='CoachInventoryInstance')
        modifiers.append(inventory)
        component.set_editor_property('npc_character_modifiers', modifiers)
    # Assigning an instanced modifier can reconstruct the Blueprint component.
    component = unreal.find_object(None, component_path)
    inventory = next(item for item in component.get_editor_property('npc_character_modifiers') if item.get_name() == 'CoachInventoryInstance')
    if not inventory.get_path_name().startswith(component_path + '.'):
        raise RuntimeError('Inventory is outside the owned component')
    definitions = [
        ('/Game/Athena/Items/Weapons/WID_Assault_Auto_Athena_R_Ore_T03', 1),
        ('/Game/Athena/Items/Weapons/WID_Shotgun_Standard_Athena_SR_Ore_T03', 1),
        ('/Game/Items/ResourcePickups/WoodItemData', 500),
        ('/Game/Athena/Items/Ammo/AthenaAmmoDataBulletsMedium', 500),
    ]
    loaded = [(unreal.EditorAssetLibrary.load_asset(path), quantity) for path, quantity in definitions]
    if any(item is None for item, quantity in loaded):
        raise RuntimeError('A configured loadout item is unresolved')
    inventory.modify()
    # Let the public setter enforce instance-only editability. Do not mutate
    # an array view to evade a template/default-object restriction.
    inventory.set_editor_property('items', [
        unreal.CharacterModifierInventoryItem(item_definition=item, item_quantity=quantity)
        for item, quantity in loaded
    ])
    print(inventory.get_path_name())
