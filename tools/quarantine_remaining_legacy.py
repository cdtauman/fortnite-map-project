"""Reversibly remove the inventoried remaining manual builds from play areas."""
import asyncio,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'.local'))
from editor_api import long_client,call,ROOT
M='/eda26a53-42c0-4b9e-8f62-31719aef6889'

async def main():
    manifest_path=ROOT.parent/'uefn/legacy-remainder-quarantine.json'
    if manifest_path.exists():raise RuntimeError('Legacy remainder already inventoried; inspect before repeating')
    rows=[r for r in json.loads((ROOT/'legacy187-inventory.json').read_text()) if not r['archived']]
    if len(rows)!=23 or any(not r['label'].startswith('PBWA_') or r['layers'] or r['parent'] for r in rows):raise RuntimeError('Legacy candidate inventory changed')
    report={'scope':'Reversible quarantine of23 manually authored legacy pieces; protect the current course and all named product actors.','actors':[]}
    async with long_client() as c:
        if await call(c,'EditorToolset.LevelToolset','GetCurrentLevel',{})!=M+'/ProCoachLab':raise RuntimeError('Unexpected project')
        if await call(c,'ValkyrieFortniteToolset.SessionToolset','GetGameState',{})=='Running':raise RuntimeError('Stop the failing match before clearing old builds')
        layer=json.loads((ROOT.parent/'uefn/course-runtime.json').read_text())['layer']['refPath']
        protected=await call(c,'EditorToolset.LevelToolset','GetActorsInDataLayer',{'assetPath':layer})
        if {r['actor'] for r in rows}&{r['actorPath'] for r in protected}:raise RuntimeError('A candidate belongs to the live course')
        report['protected_course_count']=len(protected)
        code='ROWS='+repr(rows)+'''\nimport unreal,json
result=[]
for i,row in enumerate(ROWS):
    actor=unreal.load_object(None,row['actor'])
    if actor is None or actor.get_actor_label()!=row['label'] or actor.get_class().get_path_name()!=row['class']:raise RuntimeError('Legacy identity changed')
    if actor.get_attach_parent_actor() is not None or list(actor.get_editor_property('data_layer_assets')):raise RuntimeError('Legacy actor became protected')
    p=actor.get_actor_location();r=actor.get_actor_rotation();s=actor.get_actor_scale3d()
    if any(abs(a-b)>.1 for a,b in zip([p.x,p.y,p.z],row['location'])):raise RuntimeError('Legacy actor moved since inspection')
    original={'location':dict(x=p.x,y=p.y,z=p.z),'rotation':dict(pitch=r.pitch,yaw=r.yaw,roll=r.roll),'scale':dict(x=s.x,y=s.y,z=s.z)}
    target=dict(original);target['location']=dict(x=-90000-(i%8)*1024,y=-90000-(i//8)*1024,z=-20480)
    result.append({'label':row['label'],'actor':{'refPath':row['actor']},'class':row['class'],'original':original,'original_hidden':actor.get_editor_property('hidden'),'original_collision_enabled':actor.get_actor_enable_collision(),'quarantine':target})
print(json.dumps(result))
'''
        raw=await call(c,'editor_toolset.toolsets.python_scripting.PythonScriptingTools','execute_python',{'script':{'content':code,'language':'Python'}})
        report['actors']=json.loads(raw.strip())
        manifest_path.write_text(json.dumps(report,indent=2),encoding='utf-8')
        for row in report['actors']:
            p=row['quarantine']['location']
            if not -100000<=p['x']<=-90000 or not -100000<=p['y']<=-90000 or p['z']!=-20480:raise RuntimeError('Archive target outside the named quarantine area')
            await call(c,'EditorToolset.ActorToolset','SetActorTransform',{'actor':row['actor'],'xform':row['quarantine'],'bWorldSpace':True})
        code='ROWS='+repr(report['actors'])+'''\nimport unreal,json
result=[]
for row in ROWS:
    actor=unreal.load_object(None,row['actor']['refPath']);actor.modify()
    actor.set_actor_hidden_in_game(True)
    actor.set_actor_enable_collision(False)
    p=actor.get_actor_location();target=row['quarantine']['location']
    hidden=actor.get_editor_property('hidden');collision=actor.get_actor_enable_collision()
    if not hidden or collision or abs(p.x-target['x'])>.1 or abs(p.y-target['y'])>.1 or abs(p.z-target['z'])>.1:raise RuntimeError('Legacy quarantine readback differs')
    result.append({'actor':row['actor'],'hidden':hidden,'collision':collision,'location':[p.x,p.y,p.z]})
print(json.dumps({'readback':result,'save':unreal.EditorLoadingAndSavingUtils.save_dirty_packages(True,True)}))
'''
        raw=await call(c,'editor_toolset.toolsets.python_scripting.PythonScriptingTools','execute_python',{'script':{'content':code,'language':'Python'}})
        report.update(json.loads(raw.strip()))
    manifest_path.write_text(json.dumps(report,indent=2),encoding='utf-8')
    (ROOT/'legacy187-authoring.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps({'quarantined':len(report['readback']),'course_members_protected':report['protected_course_count'],'save':report['save']}),flush=True)

if __name__=='__main__':asyncio.run(main())
