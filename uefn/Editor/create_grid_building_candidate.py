"""Author owned building-class candidates through the registered Blueprint factory."""
import unreal


def create_grid_building_candidate(kind):
    root = '/eda26a53-42c0-4b9e-8f62-31719aef6889/Art/Investigations'
    options = {
        'Wall': (unreal.BuildingWall, 'WallSolid'),
        'Floor': (unreal.BuildingFloor, 'Floor'),
        'Ramp': (unreal.BuildingStairs, 'Ramp'),
        'Cone': (unreal.BuildingRoof, 'Cone'),
    }
    parent, mesh_name = options[kind]
    path = root + '/PCL_BP_Grid' + kind + 'Candidate'
    asset = unreal.EditorAssetLibrary.load_asset(path)
    if asset is None:
        asset = unreal.BlueprintEditorLibrary.create_blueprint_asset_with_parent(path, parent)
    if asset is None:
        raise RuntimeError('The registered factory did not accept this building parent')
    if unreal.BlueprintEditorLibrary.get_blueprint_parent_class(asset) != parent.static_class():
        raise RuntimeError('Unexpected candidate parent')
    if not unreal.BlueprintEditorLibrary.compile_blueprint(asset):
        raise RuntimeError('Candidate compilation failed')
    defaults = unreal.get_default_object(asset.generated_class())
    if not defaults.get_path_name().startswith(path):
        raise RuntimeError('Refusing to edit a foreign class default object')
    mesh = unreal.EditorAssetLibrary.load_asset('/eda26a53-42c0-4b9e-8f62-31719aef6889/Art/GridKit/PCL_SM_Grid' + mesh_name)
    if mesh is None:
        raise RuntimeError('Missing owned mesh')
    defaults.modify()
    for key, value in {
        'static_mesh': mesh,
        'resource_type': unreal.FortResourceType.WOOD,
        'is_player_buildable': True,
        'register_with_structural_grid': True,
        'destroy_on_player_building_placement': False,
        'can_be_damaged': True,
        'team_index': 2,
    }.items():
        if defaults.get_editor_property(key) != value:
            defaults.set_editor_property(key, value)
    component = defaults.get_editor_property('static_mesh_component')
    if component is None or component.get_outermost() != defaults.get_outermost():
        raise RuntimeError('Unexpected mesh component ownership')
    component.set_static_mesh(mesh)
    print('candidate=' + asset.get_path_name())
    print('parent=' + parent.static_class().get_path_name())
    print('player_buildable=' + str(defaults.get_editor_property('is_player_buildable')))
    print('Runtime placement, native edits, ownership, damage and publication remain acceptance tests.')
