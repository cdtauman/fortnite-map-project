"""Finish the dedicated disabled bank from the inspected first owned actor.

No game/session/upload or sequence evaluation. Never replay a partial batch.
"""
import asyncio,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'.local'))
from editor_api import long_client,call,ROOT
M='/eda26a53-42c0-4b9e-8f62-31719aef6889'

async def main():
    path=ROOT/'native-pool188-placement.json'
    report=json.loads(path.read_text())
    finish_only='--finish' in sys.argv
    if report.get('finished'):raise RuntimeError('Bank already finished; do not replay')
    if finish_only:
        if len(report['actors'])!=64 or len(report.get('layer_members',[]))!=64:raise RuntimeError('Expected the fully placed bank')
    elif report.get('remaining_requested') or len(report['actors'])!=1:raise RuntimeError('Inspect existing stage before continuation')
    first=report['actors'][0]['readback']
    if first['spatially_loaded'] or 'UNLOADED' not in first['initial_state'] or not first['save']:raise RuntimeError('First actor/layer preparation incomplete')
    assets=json.loads((ROOT/'native-pool186-bank-authoring.json').read_text())['assets']
    runtime=json.loads((ROOT/'native-pool188-runtime-assets.json').read_text())
    specs=[]
    for kind_index,kind in enumerate(['Wall','Floor','Ramp','Cone']):
        for i in range(16):
            if kind=='Wall' and i==0:continue
            specs.append({'kind':kind,'index':i+1,'label':f'PCL_NativePool_{kind}_{i+1:02}','pose':{'location':{'x':-60000+(i%8)*1024,'y':-60000+kind_index*3072+(i//8)*1024,'z':-8064},'rotation':{'pitch':0,'yaw':0,'roll':0},'scale':{'x':1,'y':1,'z':1}}})
    def save():path.write_text(json.dumps(report,indent=2),encoding='utf-8')
    async with long_client() as c:
        if await call(c,'EditorToolset.LevelToolset','GetCurrentLevel',{})!=M+'/ProCoachLab':raise RuntimeError('Unexpected level')
        found=await call(c,'EditorToolset.LevelToolset','FindActors',{'filter':{'name':'PCL_NativePool_'}})
        if {r['actorPath'] for r in found}!={r['actor']['refPath'] for r in report['actors']}:raise RuntimeError('Unexpected pre-existing pool actor')
        if not finish_only:
            report['remaining_requested']=True;save()
            for row in specs:
                report['pending_label']=row['label'];save()
                row['actor']=await call(c,'EditorToolset.LevelToolset','AddToSceneFromClass',{'actorType':{'refPath':assets[row['kind']]['class']},'name':row['label'],'xform':row['pose']})
                report['actors'].append(row);save()
                await call(c,'EditorToolset.ActorToolset','SetLabel',{'actor':row['actor'],'label':row['label']})
                if row['index']==16:print('Placed '+row['kind']+' bank',flush=True)
            await call(c,'EditorToolset.LevelToolset','AddActorsToDataLayer',{'actors':[r['actor'] for r in report['actors']],'assetPath':runtime['layer']['refPath'].split('.')[0]})
        report['layer_members']=await call(c,'EditorToolset.LevelToolset','GetActorsInDataLayer',{'assetPath':runtime['layer']['refPath']});save()
        code='ROWS='+repr(report['actors'])+'\nLAYER='+repr(runtime['layer']['refPath'])+'''\nimport unreal,json
result=[]
for row in ROWS:
    actor=unreal.load_object(None,row['actor']['refPath'])
    if actor is None or actor.get_actor_label()!=row['label']:raise RuntimeError('Pool actor identity differs')
    if actor.get_attach_parent_actor() is not None:raise RuntimeError('Unexpected attached pool actor')
    layers=[x.get_path_name() for x in actor.get_editor_property('data_layer_assets')]
    if layers!=[LAYER]:raise RuntimeError('Unexpected pool layer membership')
    actor.modify()
    actor.set_editor_property('is_spatially_loaded',False)
    p=actor.get_actor_location();target=row['pose']['location']
    if any(abs(getattr(p,k)-target[k])>.1 for k in ['x','y','z']):raise RuntimeError('Pool parking differs')
    tags=[]
    for component in actor.get_components_by_class(unreal.VerseTagMarkupComponent):
        tags += [i.get_editor_property('internal_tag').get_path_name() for i in component.get_editor_property('internal_tags').get_editor_property('internal_tags')]
    expected=actor.get_class().get_path_name().split('/Art/')[0]+'/_Verse.coach_native_pool_'+row['kind'].lower()+'_tag'
    if tags!=[expected]:raise RuntimeError('Pool kind tag differs')
    if not actor.get_editor_property('bCanBeDamaged'):raise RuntimeError('Owned bank damage flag differs')
    result.append({'actor':row['actor'],'kind':row['kind'],'spatially_loaded':actor.get_editor_property('is_spatially_loaded'),'tags':tags,'location':[p.x,p.y,p.z]})
print(json.dumps({'actors':result,'save':unreal.EditorLoadingAndSavingUtils.save_dirty_packages(True,True)}))
'''
        report['readback']=json.loads(await call(c,'editor_toolset.toolsets.python_scripting.PythonScriptingTools','execute_python',{'script':{'content':code,'language':'Python'}}))
        report.pop('pending_label',None);report['finished']=True;save()
    refs={r['actor']['refPath'] for r in report['actors']}
    if len(refs)!=64 or len(report['layer_members'])!=64:raise RuntimeError('Bank inventory differs')
    (ROOT.parent/'uefn/native-pool-bank.json').write_text(json.dumps({'scope':__doc__,'layer':runtime['layer'],'sequences':{k:v['asset'] for k,v in runtime['sequences'].items()},'initial_runtime_state':'Unloaded','parts':report['actors'],'enabled':False},indent=2),encoding='utf-8')
    print(json.dumps({'parts':64,'layer_members':len(report['layer_members']),'save':report['readback']['save'],'enabled':False}),flush=True)

if __name__=='__main__':asyncio.run(main())
