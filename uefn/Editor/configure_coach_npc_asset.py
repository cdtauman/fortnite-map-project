"""Configure owned NPC instanced objects that the generic asset tools do not create."""

import unreal

ASSET = '/eda26a53-42c0-4b9e-8f62-31719aef6889/NPC/CoachOpponent'
GUARD_TYPE = '/NPCDefault/Types/CharacterType_Guard.CharacterType_Guard_C'
WEAPON = '/Game/Athena/Items/Weapons/WID_Assault_Auto_Athena_R_Ore_T03'
INVENTORY_TYPE = '/CRD_AISpawner/SpawnDefinitions/Modifiers/CharacterModifier_GuardInventory.CharacterModifier_GuardInventory_C'

definition = unreal.EditorAssetLibrary.load_asset(ASSET)
guard_class = unreal.load_class(None, GUARD_TYPE)
weapon = unreal.EditorAssetLibrary.load_asset(WEAPON)
if not isinstance(definition, unreal.NPCCharacterDefinition) or guard_class is None or weapon is None:
    raise RuntimeError('Required project definition, stock guard type or weapon is unresolved')

if definition.get_editor_property('type').get_class() != guard_class:
    definition.set_editor_property('type', unreal.new_object(guard_class, outer=definition, name='CoachGuardType'))

# Items is instance-only in this build. Use the spawner's additional modifier instance.
modifiers = list(definition.get_editor_property('modifiers'))
retained = [item for item in modifiers if item.get_name() != 'CoachInventory']
if len(retained) != len(modifiers):
    definition.set_editor_property('modifiers', retained)
print('Configured owned guard definition: ' + definition.get_path_name())
