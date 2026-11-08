"""Create the dedicated coach definition once; configure it through editor tools afterward."""

import unreal

PACKAGE = '/eda26a53-42c0-4b9e-8f62-31719aef6889/NPC'
NAME = 'CoachOpponent'
PATH = PACKAGE + '/' + NAME

existing = unreal.EditorAssetLibrary.load_asset(PATH)
if existing is not None:
    if not isinstance(existing, unreal.NPCCharacterDefinition):
        raise RuntimeError('The target name is occupied by a different asset type')
    print('Existing coach definition retained: ' + existing.get_path_name())
else:
    created = unreal.AssetToolsHelpers.get_asset_tools().create_asset(
        asset_name=NAME,
        package_path=PACKAGE,
        asset_class=unreal.NPCCharacterDefinition,
        factory=unreal.NPCCharacterDefinitionFactory(),
        overwrite_existing=False,
    )
    if created is None:
        raise RuntimeError('NPC definition creation did not return an asset')
    print('Created coach definition: ' + created.get_path_name())
