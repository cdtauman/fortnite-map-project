"""Author the owned prop candidate; native build-slot behavior is not established by this file."""

import unreal

ROOT = globals().get('TRAINING_ASSET_ROOT', '/eda26a53-42c0-4b9e-8f62-31719aef6889/Art/TrainingKit')
if not ROOT.startswith('/eda26a53-42c0-4b9e-8f62-31719aef6889/Art/'):
    raise RuntimeError('The construction kit must be an owned project folder')
PATH = ROOT + '/PCL_BP_' + globals().get('TRAINING_ASSET_NAME', 'TrainingWall')
IS_DEMO = globals().get('TRAINING_IS_DEMO', False)
IS_COMBAT = globals().get('TRAINING_IS_COMBAT', False)
MESH_NAME = globals().get('TRAINING_MESH_NAME', 'WallSolid')
KIND = globals().get('TRAINING_BUILDING_TYPE', 'WALL')
MESH_PATH = globals().get('TRAINING_MESH_PATH', ROOT + '/PCL_SM_' + MESH_NAME)
if not MESH_PATH.startswith('/eda26a53-42c0-4b9e-8f62-31719aef6889/Art/'):
    raise RuntimeError('The training mesh must be an owned project asset')
mesh = unreal.EditorAssetLibrary.load_asset(MESH_PATH)
if mesh is None:
    raise RuntimeError('Import the reviewed wall mesh first')
blueprint = unreal.EditorAssetLibrary.load_asset(PATH)
if blueprint is None:
    blueprint = unreal.BlueprintEditorLibrary.create_blueprint_asset_with_parent(PATH, unreal.BuildingProp)
if blueprint is None:
    raise RuntimeError('Blueprint creation did not return an asset')
if not unreal.BlueprintEditorLibrary.compile_blueprint(blueprint):
    raise RuntimeError('The prop Blueprint did not compile')
defaults = unreal.get_default_object(blueprint.generated_class())
if not defaults.get_path_name().startswith(PATH):
    raise RuntimeError('Refusing to edit defaults outside the owned Blueprint')
blueprint.modify()
defaults.modify()
desired = {
    'static_mesh': mesh,
    'can_be_damaged': IS_COMBAT and not IS_DEMO,
    'resource_type': unreal.FortResourceType.WOOD,
    'building_type': unreal.FortBuildingType.PROP if IS_DEMO else getattr(unreal.FortBuildingType, KIND),
    'building_placement_type': unreal.PlacementType.FREE if IS_DEMO else unreal.PlacementType.GRID,
    'dynamic_building_placement_type': unreal.DynamicBuildingPlacementType.COUNTS_TOWARDS_BOUNDS,
    'destroy_on_player_building_placement': False,
    'register_with_structural_grid': not IS_DEMO,
    'bIsPlayerBuildable': not IS_DEMO,
    'forcibly_structurally_supported': False,
    'bAllowTeamDamage': not IS_COMBAT,
}
if not IS_DEMO:
    team_type=type(defaults.get_editor_property('team'))
    wanted_team='humanpvpteam2' if IS_COMBAT else 'humanpvpteam1'
    team_key=next(name for name in dir(team_type) if name.replace('_','').lower()==wanted_team)
    desired['team']=getattr(team_type,team_key)
for key, value in desired.items():
    if defaults.get_editor_property(key) != value:
        defaults.set_editor_property(key, value)
if not IS_DEMO:
    initial_keys = defaults.get_editor_property('AttributeInitKeys')
    if len(initial_keys) != 2:
        raise RuntimeError('Inspect the current prop initialization-key layout before authoring')
    if all(str(entry.get_editor_property(field)) in ('', 'None')
           for entry in initial_keys
           for field in ('attribute_init_category', 'attribute_init_sub_category')):
        # This initializes generic prop attributes; it does not establish player-build health values.
        defaults.set_editor_property('AttributeInitKeys', [
            unreal.FortAttributeInitializationKey(attribute_init_category='PropWood', attribute_init_sub_category='2')
            for _ in range(2)
        ])
component = defaults.get_editor_property('static_mesh_component')
if component is not None and component.get_outermost() == defaults.get_outermost():
    component.set_static_mesh(mesh)
print('Authored prop Blueprint: ' + blueprint.get_path_name())
print('Grid registration, ownership, health continuity and collision require final gameplay validation.')
