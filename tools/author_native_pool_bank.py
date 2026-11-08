"""Author a separate native-part bank through public editor APIs.

No gameplay, sequence evaluation, production enable or source-asset modification.
"""
import asyncio,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'.local'))
from editor_api import long_client,call,ROOT
M='/eda26a53-42c0-4b9e-8f62-31719aef6889'
FOLDER=M+'/Art/NativePool'

async def main():
    path=ROOT/'native-pool186-bank-authoring.json'
    if path.exists():raise RuntimeError('Bank authoring already recorded; inspect its exact stage before continuation')
    record={'scope':'Owned native bank asset preparation only; disabled runtime path and no native gameplay acceptance.','assets':{},'gameplay_launched':False}
    def persist():path.write_text(json.dumps(record,indent=2),encoding='utf-8')
    async with long_client() as c:
        if await call(c,'EditorToolset.LevelToolset','GetCurrentLevel',{})!=M+'/ProCoachLab':raise RuntimeError('Unexpected level')
        record['existing_game_state']=await call(c,'ValkyrieFortniteToolset.SessionToolset','GetGameState',{})
        # This phase only creates separate Blueprint assets. It does not place
        # actors, change the source Blueprints or upload to an existing session.
        for kind in ['Wall','Floor','Ramp','Cone']:
            target=FOLDER+'/PCL_BP_NativePool'+kind
            code='MOUNT='+repr(M)+'\nKIND='+repr(kind)+'\nTARGET='+repr(target)+'''\nimport unreal,json
source=MOUNT+'/Art/Investigations/PCL_BP_Course'+KIND
if unreal.EditorAssetLibrary.does_asset_exist(TARGET):raise RuntimeError('Unexpected existing bank asset')
asset=unreal.EditorAssetLibrary.duplicate_asset(source,TARGET)
if asset is None:raise RuntimeError('Public duplication failed')
obj=unreal.get_default_object(asset.generated_class())
if not obj.get_path_name().startswith(TARGET+'.'):raise RuntimeError('Refusing foreign defaults')
asset.modify();obj.modify()
team_type=type(obj.get_editor_property('team'))
team_key=next(key for key in dir(team_type) if key.replace('_','').lower()=='humanpvpteam2')
before={key:str(obj.get_editor_property(key)) for key in ['team','bCanBeDamaged','bAllowTeamDamage','bPlayerPlaced','bIsPlayerBuildable','bForciblyStructurallySupported']}
obj.set_editor_property('team',getattr(team_type,team_key))
obj.set_editor_property('bCanBeDamaged',True)
obj.set_editor_property('bAllowTeamDamage',False)
if not unreal.BlueprintEditorLibrary.compile_blueprint(asset):raise RuntimeError('Owned bank Blueprint compilation failed')
if not unreal.EditorAssetLibrary.save_loaded_asset(asset,only_if_is_dirty=False):raise RuntimeError('Owned bank asset save failed')
print(json.dumps({'asset':asset.get_path_name(),'class':asset.generated_class().get_path_name(),'parent':unreal.BlueprintEditorLibrary.get_blueprint_parent_class(asset).get_path_name(),'before':before}))
'''
            raw=await call(c,'editor_toolset.toolsets.python_scripting.PythonScriptingTools','execute_python',{'script':{'content':code,'language':'Python'}})
            row=json.loads(raw.strip());record['assets'][kind]=row;persist()
            component=await call(c,'EditorToolset.ActorToolset','AddComponent',{'owner':{'refPath':row['asset']},'componentType':{'refPath':'/Script/VerseTags.VerseTagMarkupComponent'},'name':'PoolPartTag'})
            row['tag_component']=component;persist()
            code='MOUNT='+repr(M)+'\nTARGET='+repr(target)+'\nKIND='+repr(kind)+'\nCOMPONENT='+repr(component['refPath'])+'''\nimport unreal,json
asset=unreal.EditorAssetLibrary.load_asset(TARGET)
component=unreal.find_object(None,COMPONENT)
if component is None or component.get_outermost()!=asset.get_outermost():raise RuntimeError('Expected owned tag component template')
tag_class=unreal.load_class(None,MOUNT+'/_Verse.coach_native_pool_'+KIND.lower()+'_tag')
if tag_class is None:raise RuntimeError('Compiled tag class was not loaded')
info=unreal.VerseTagTypeInfo()
info.set_editor_property('internal_tag',tag_class)
container=unreal.VerseTagTypeInfoContainer()
container.set_editor_property('internal_tags',[info])
component.modify()
component.set_editor_property('internal_tags',container)
if not unreal.BlueprintEditorLibrary.compile_blueprint(asset):raise RuntimeError('Tagged bank compilation failed')
if not unreal.EditorAssetLibrary.save_loaded_asset(asset,only_if_is_dirty=False):raise RuntimeError('Tagged bank save failed')
current=unreal.get_default_object(asset.generated_class())
after={key:str(current.get_editor_property(key)) for key in ['team','bCanBeDamaged','bAllowTeamDamage','bPlayerPlaced','bIsPlayerBuildable','bForciblyStructurallySupported']}
print(json.dumps({'tag':tag_class.get_path_name(),'after':after,'saved':True}))
'''
            raw=await call(c,'editor_toolset.toolsets.python_scripting.PythonScriptingTools','execute_python',{'script':{'content':code,'language':'Python'}})
            row.update(json.loads(raw.strip()));persist()
            print('Prepared tagged native bank asset '+kind,flush=True)
        record['assets_finished']=True;persist()
    print(json.dumps({'assets_finished':True,'count':len(record['assets']),'gameplay_launched':False}),flush=True)

if __name__=='__main__':asyncio.run(main())
