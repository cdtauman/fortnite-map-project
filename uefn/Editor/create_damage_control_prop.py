"""Create a normal owned BuildingProp as a positive damage control."""
import unreal

ROOT = '/eda26a53-42c0-4b9e-8f62-31719aef6889'
PATH = ROOT + '/Art/Investigations/PCL_BP_DamageControl'
asset = unreal.EditorAssetLibrary.load_asset(PATH)
if asset is None:
    asset = unreal.BlueprintEditorLibrary.create_blueprint_asset_with_parent(PATH, unreal.BuildingProp)
if asset is None or unreal.BlueprintEditorLibrary.get_blueprint_parent_class(asset) != unreal.BuildingProp.static_class():
    raise RuntimeError('Expected an owned BuildingProp Blueprint from the registered factory')
if not unreal.BlueprintEditorLibrary.compile_blueprint(asset):
    raise RuntimeError('Damage control Blueprint failed to compile')
defaults = unreal.get_default_object(asset.generated_class())
if not defaults.get_path_name().startswith(PATH):
    raise RuntimeError('Refusing to change a foreign class default object')
mesh = unreal.EditorAssetLibrary.load_asset(ROOT + '/Art/GridKit/PCL_SM_GridWallSolid')
if mesh is None:
    raise RuntimeError('Missing owned solid wall mesh')
defaults.modify()
defaults.set_editor_properties({
    'static_mesh': mesh,
    'resource_type': unreal.FortResourceType.WOOD,
    'can_be_damaged': True,
    'building_type': unreal.FortBuildingType.PROP,
    'register_with_structural_grid': False,
    'is_player_buildable': False,
    'destroy_on_player_building_placement': False,
    'team_index': 2,
})
component = defaults.get_editor_property('static_mesh_component')
if component is None or component.get_outermost() != defaults.get_outermost():
    raise RuntimeError('Unexpected mesh component ownership')
component.set_static_mesh(mesh)
print('Created ordinary damage control: ' + asset.get_path_name())
print('This is a BuildingProp calibration target, not native building proof.')
