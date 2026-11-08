"""Prepare owned, non-damageable teaching props and a dedicated neutral demonstrator."""
import unreal

MOUNT = '/eda26a53-42c0-4b9e-8f62-31719aef6889'
ROOT = MOUNT + '/Art/TeachingKit'
ASSETS = {
    'Wall': MOUNT + '/Art/GridKit/PCL_SM_GridWallSolid',
    'Floor': MOUNT + '/Art/GridKit/PCL_SM_GridFloor',
    'Ramp': MOUNT + '/Art/GridKit/PCL_SM_GridRamp',
    'Cone': MOUNT + '/Art/GridKit/PCL_SM_GridCone',
    'Marker': '/Engine/BasicShapes/Sphere',
}

for kind, mesh_path in ASSETS.items():
    path = ROOT + '/PCL_BP_Demo' + kind
    asset = unreal.EditorAssetLibrary.load_asset(path)
    if asset is None:
        asset = unreal.BlueprintEditorLibrary.create_blueprint_asset_with_parent(path, unreal.BuildingProp)
    if asset is None or unreal.BlueprintEditorLibrary.get_blueprint_parent_class(asset) != unreal.BuildingProp.static_class():
        raise RuntimeError('Unexpected teaching asset parent: ' + path)
    if not unreal.BlueprintEditorLibrary.compile_blueprint(asset):
        raise RuntimeError('Teaching prop did not compile: ' + path)
    defaults = unreal.get_default_object(asset.generated_class())
    if not defaults.get_path_name().startswith(path):
        raise RuntimeError('Refusing to modify foreign defaults')
    mesh = unreal.EditorAssetLibrary.load_asset(mesh_path)
    if mesh is None:
        raise RuntimeError('The reviewed mesh is unresolved')
    defaults.modify()
    for key, value in {'static_mesh': mesh, 'can_be_damaged': False,
                       'building_type': unreal.FortBuildingType.PROP,
                       'building_placement_type': unreal.PlacementType.FREE,
                       'destroy_on_player_building_placement': False,
                       'register_with_structural_grid': False,
                       'team_index': 0}.items():
        if defaults.get_editor_property(key) != value:
            defaults.set_editor_property(key, value)
    component = defaults.get_editor_property('static_mesh_component')
    if component is None or component.get_outermost() != defaults.get_outermost():
        raise RuntimeError('Unexpected teaching mesh component ownership')
    component.set_static_mesh(mesh)
    if kind == 'Marker':
        component.set_collision_enabled(unreal.CollisionEnabled.NO_COLLISION)
    print('teaching_prop=' + asset.get_path_name())

npc_path = MOUNT + '/NPC/CoachDemonstrator'
definition = unreal.EditorAssetLibrary.load_asset(npc_path)
if definition is None:
    definition = unreal.EditorAssetLibrary.duplicate_asset(MOUNT + '/NPC/CoachSpeaker', npc_path)
if not isinstance(definition, unreal.NPCCharacterDefinition):
    raise RuntimeError('Expected owned NPC definition')
cosmetic = next((m for m in definition.get_editor_property('modifiers') if 'GuardSpawn' in m.get_name()), None)
if cosmetic is not None:
    candidate = unreal.EditorAssetLibrary.load_asset('/Game/Athena/Items/Cosmetics/Characters/CID_005_Athena_Commando_M_Default')
    if candidate is not None:
        cosmetic.set_editor_property('character_cosmetic', candidate)
        print('demonstrator_cosmetic=' + candidate.get_path_name())
print('demonstrator_definition=' + definition.get_path_name())
print('Native animation, speed scaling, firing and edit correspondence still require final gameplay checks.')
