"""Author separate owned assets for the opponent and the player's practice course.

Run through the approved editor Python interface. Gameplay semantics require final acceptance.
"""
import unreal

MOUNT='/eda26a53-42c0-4b9e-8f62-31719aef6889'
result=[]
for kind in ['Wall','Floor','Ramp','Cone']:
    source_path=MOUNT+'/Art/TrainingKit/PCL_BP_Training'+kind
    combat_path=MOUNT+'/Art/CombatKit/PCL_BP_Coach'+kind
    source=unreal.EditorAssetLibrary.load_asset(source_path)
    if source is None:raise RuntimeError('Owned source missing: '+source_path)
    combat=unreal.EditorAssetLibrary.load_asset(combat_path)
    if combat is None:combat=unreal.EditorAssetLibrary.duplicate_asset(source_path,combat_path)
    if combat is None:raise RuntimeError('Owned duplication failed: '+combat_path)
    for asset,path,is_combat in [(combat,combat_path,True),(source,source_path,False)]:
        default=unreal.get_default_object(asset.generated_class())
        if not default.get_path_name().startswith(path+'.'):raise RuntimeError('Refusing foreign defaults')
        before={'team':str(default.get_editor_property('team')),'allow_team_damage':default.get_editor_property('bAllowTeamDamage'),'can_be_damaged':default.get_editor_property('can_be_damaged')}
        team_type=type(default.get_editor_property('team'))
        wanted='humanpvpteam2' if is_combat else 'humanpvpteam1'
        key=next(name for name in dir(team_type) if name.replace('_','').lower()==wanted)
        asset.modify();default.modify()
        default.set_editor_property('team',getattr(team_type,key))
        default.set_editor_property('bAllowTeamDamage',not is_combat)
        default.set_editor_property('can_be_damaged',is_combat)
        default.set_editor_property('bIsPlayerBuildable',True)
        if not unreal.BlueprintEditorLibrary.compile_blueprint(asset):raise RuntimeError('Owned compile failed: '+path)
        if not unreal.EditorAssetLibrary.save_loaded_asset(asset,only_if_is_dirty=False):raise RuntimeError('Owned save failed: '+path)
        saved=unreal.get_default_object(asset.generated_class())
        result.append({'kind':kind,'usage':'combat' if is_combat else 'training','asset':path,'class':asset.generated_class().get_path_name(),'before':before,'authored':{'team':str(saved.get_editor_property('team')),'allow_team_damage':saved.get_editor_property('bAllowTeamDamage'),'can_be_damaged':saved.get_editor_property('can_be_damaged'),'player_buildable':saved.get_editor_property('bIsPlayerBuildable'),'player_placed':saved.get_editor_property('bPlayerPlaced')}})
