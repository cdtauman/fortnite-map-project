"""Prepare mirrored owned duel ramps and retire the old shared starting block.

Public editor authoring, not gameplay or native-building acceptance.
"""
import argparse,asyncio,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'.local'))
from editor_api import long_client,call,ROOT
from build_academy_scene import MOUNT,FOLDER,pose

def obj(value):return json.loads(value) if isinstance(value,str) else value

async def main(finish=False):
    output=ROOT/'duel-start178-authoring.json'
    if output.exists() and not finish:raise RuntimeError('Authoring record exists; inspect current state before continuation')
    if finish and not output.exists():raise RuntimeError('No partial authoring record')
    actors_path=ROOT/'academy-actors.json';actors=json.loads(actors_path.read_text(encoding='utf-8'))
    base=MOUNT+'/Art/Investigations/PCL_BP_GridRampCandidate'
    target=FOLDER+'/PCL_BP_DuelStartingRamp'
    defaults={'refPath':target+'.Default__PCL_BP_DuelStartingRamp_C'}
    center=next(a['center'] for a in json.loads((ROOT.parent/'uefn/arena-layout.json').read_text(encoding='utf-8'))['arenas'] if a['mode']=='Duel')
    cx,cy,cz=center
    ramps=[{'name':'PCL_Duel_StartingRamp_Left','transform':pose(cx-512,cy,cz,yaw=-90)},{'name':'PCL_Duel_StartingRamp_Right','transform':pose(cx+512,cy,cz,yaw=90)}]
    if not finish and any(r['name'] in actors for r in ramps):raise RuntimeError('Ramp actor names already exist')
    settings={'bDoNotBlockBuildings':True,'bStructurallySupportOverlappingActors':True,'bCanBeDamaged':False,'bForceBlockBuildings':False,'bDestroyOnPlayerBuildingPlacement':False}
    record=json.loads(output.read_text(encoding='utf-8')) if finish else {'scope':__doc__,'gameplay_launched':False,'ramps':[],'original_markers':{}}
    if 'save' in record:raise RuntimeError('This authoring batch is already complete')
    def persist():output.write_text(json.dumps(record,indent=2),encoding='utf-8')
    async with long_client() as c:
        if await call(c,'EditorToolset.LevelToolset','GetCurrentLevel',{})!=MOUNT+'/ProCoachLab':raise RuntimeError('Unexpected level')
        if await call(c,'ValkyrieFortniteToolset.SessionToolset','GetGameState',{})!='Unconnected':raise RuntimeError('Expected disconnected editor')
        if not finish:
            found=await call(c,'EditorToolset.AssetToolset','FindAssets',{'filter':{'folderPath':FOLDER,'name':'PCL_BP_DuelStartingRamp','maxResults':2}})
            if found:raise RuntimeError('Target asset exists; inspect instead of overwriting')
            persist()
            await call(c,'EditorToolset.AssetToolset','Duplicate',{'path':base,'newPath':target})
            record['asset']=target;persist()
            await call(c,'EditorToolset.ObjectToolset','SetProperties',{'instance':defaults,'values':json.dumps(settings)})
            record['defaults']=obj(await call(c,'EditorToolset.ObjectToolset','GetProperties',{'instance':defaults,'properties':list(settings)+['bPlayerPlaced','bIsPlayerBuildable']}))
            if any(record['defaults'][k]!=v for k,v in settings.items()) or record['defaults']['bPlayerPlaced'] or not record['defaults']['bIsPlayerBuildable']:raise RuntimeError('Unexpected ramp template state')
            await call(c,'EditorToolset.AssetToolset','SaveAsset',{'assetPath':target});persist()
            for ramp in ramps:
                actor=await call(c,'EditorToolset.LevelToolset','AddToSceneFromAsset',{'assetPath':target,'name':ramp['name'],'xform':ramp['transform']})
                actors[ramp['name']]=actor
                record['ramps'].append(dict(ramp,actor=actor))
                actors_path.write_text(json.dumps(actors,indent=2),encoding='utf-8');persist()
                await call(c,'EditorToolset.LevelToolset','SaveActor',{'actor':actor})
        if len(record['ramps'])!=2 or any(actors.get(r['name'])!=r['actor'] for r in record['ramps']):raise RuntimeError('Partial ramp identities changed')
        compile_code='import unreal\na=unreal.EditorAssetLibrary.load_asset('+repr(target)+')\nprint(unreal.BlueprintEditorLibrary.compile_blueprint(a))'
        record['blueprint_compile']=await call(c,'editor_toolset.toolsets.python_scripting.PythonScriptingTools','execute_python',{'script':{'content':compile_code,'language':'Python'}});persist()
        if record['blueprint_compile'].strip()!='True':raise RuntimeError('Owned ramp Blueprint compile did not succeed')
        for ramp in record['ramps']:
            await call(c,'EditorToolset.ObjectToolset','SetProperties',{'instance':ramp['actor'],'values':json.dumps({'bCanBeDamaged':False})})
            await call(c,'EditorToolset.ActorToolset','SetActorTransform',{'actor':ramp['actor'],'xform':ramp['transform'],'bWorldSpace':True})
            await call(c,'EditorToolset.LevelToolset','SaveActor',{'actor':ramp['actor']})
        surface=json.loads((ROOT.parent/'uefn/academy-layout.json').read_text(encoding='utf-8'))['materials']['Stone']['refPath']
        surface_code='''import unreal,json
asset=unreal.EditorAssetLibrary.load_asset(ASSET);mat=unreal.EditorAssetLibrary.load_asset(MATERIAL)
if asset is None or mat is None:raise RuntimeError('Owned surface asset missing')
objects=[unreal.get_default_object(asset.generated_class())]+[unreal.load_object(None,r['actor']['refPath']) for r in RAMPS]
for a in objects:
    if a is None:raise RuntimeError('Ramp object missing')
    a.modify()
    for component in a.get_components_by_class(unreal.StaticMeshComponent):
        if component.get_num_materials()==0:continue
        component.modify()
        for index in range(component.get_num_materials()):component.set_material(index,mat)
        component.set_editor_property('cast_shadow',False)
print(json.dumps({'material':mat.get_path_name()}))
'''
        record['surface_configuration']=await call(c,'editor_toolset.toolsets.python_scripting.PythonScriptingTools','execute_python',{'script':{'content':'ASSET='+repr(target)+'\nMATERIAL='+repr(surface)+'\nRAMPS='+repr(record['ramps'])+'\n'+surface_code,'language':'Python'}});persist()
        code='''import unreal,json
rows=[]
for row in RAMPS:
    a=unreal.load_object(None,row['actor']['refPath'])
    if a is None:raise RuntimeError('Ramp actor missing')
    values={k:a.get_editor_property(k) for k in ['bCanBeDamaged','bPlayerPlaced','bIsPlayerBuildable','bDoNotBlockBuildings','bStructurallySupportOverlappingActors']}
    if values['bCanBeDamaged'] or values['bPlayerPlaced'] or not all(values[k] for k in ['bIsPlayerBuildable','bDoNotBlockBuildings','bStructurallySupportOverlappingActors']):raise RuntimeError('Ramp instance flags differ from its owned defaults')
    center,extent=a.get_actor_bounds(False)
    rows.append({'name':row['name'],'class':a.get_class().get_path_name(),'flags':values,'bounds_center':[center.x,center.y,center.z],'bounds_extent':[extent.x,extent.y,extent.z]})
block=unreal.load_object(None,BLOCK['refPath'])
print(json.dumps({'ramps':rows,'block_original_hidden':block.get_editor_property('hidden'),'block_original_collision':block.get_actor_enable_collision()}))
'''
        record['readback']=json.loads(await call(c,'editor_toolset.toolsets.python_scripting.PythonScriptingTools','execute_python',{'script':{'content':'RAMPS='+repr(record['ramps'])+'\nBLOCK='+repr(actors['PCL_Duel_Start_Block'])+'\n'+code,'language':'Python'}}));persist()
        record['original_block_transform']=await call(c,'EditorToolset.ActorToolset','GetActorTransform',{'actor':actors['PCL_Duel_Start_Block']});persist()
        # Both ramps exist before changing the old start surface.
        retired=json.loads(json.dumps(record['original_block_transform']));retired['location']['z']=cz-500
        await call(c,'EditorToolset.ActorToolset','SetActorTransform',{'actor':actors['PCL_Duel_Start_Block'],'xform':retired,'bWorldSpace':True})
        block_code='''import unreal,json
a=unreal.load_object(None,BLOCK['refPath']);a.modify()
a.set_actor_hidden_in_game(True);a.set_actor_enable_collision(False)
print(json.dumps({'hidden':a.get_editor_property('hidden'),'collision':a.get_actor_enable_collision()}))
'''
        record['retired_block']=json.loads(await call(c,'editor_toolset.toolsets.python_scripting.PythonScriptingTools','execute_python',{'script':{'content':'BLOCK='+repr(actors['PCL_Duel_Start_Block'])+'\n'+block_code,'language':'Python'}}))
        await call(c,'EditorToolset.LevelToolset','SaveActor',{'actor':actors['PCL_Duel_Start_Block']});persist()
        for index,x in enumerate([-768,768]):
            name='PCL_Environment_Duel_StartMark_'+str(index)
            before=await call(c,'EditorToolset.ActorToolset','GetActorTransform',{'actor':actors[name]})
            record['original_markers'][name]=before;persist()
            moved=json.loads(json.dumps(before));moved['location']['x']=cx+x
            await call(c,'EditorToolset.ActorToolset','SetActorTransform',{'actor':actors[name],'xform':moved,'bWorldSpace':True})
            await call(c,'EditorToolset.LevelToolset','SaveActor',{'actor':actors[name]})
        record['save']=await call(c,'editor_toolset.toolsets.python_scripting.PythonScriptingTools','execute_python',{'script':{'content':'import unreal\nprint(unreal.EditorLoadingAndSavingUtils.save_dirty_packages(True,True))','language':'Python'}});persist()
    (ROOT.parent/'uefn/duel-start-layout.json').write_text(json.dumps({'scope':'Editor-authored static start ramps. Native building attachment, controls and fair multiplayer start are not runtime accepted.','ramps':ramps,'asset':target,'default_policy':settings,'player_offsets_xyz_cm':[[-768,0,100],[768,0,100]],'old_block':actors['PCL_Duel_Start_Block'],'restoration_record':'.local/duel-start178-authoring.json','source_geometry':'GridKit ramp; local Y0..512, X-256..256, Z0..384.'},ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'ramps':len(record['ramps']),'readback':record['readback'],'save':record['save']}),flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--finish',action='store_true',help='Continue the inspected pair without duplicating any asset or actor')
    asyncio.run(main(parser.parse_args().finish))
