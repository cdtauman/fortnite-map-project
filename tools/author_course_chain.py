"""Prepare a linked three-ascent edit course from existing owned course actors.

Uses the public editor duplicate operation. No gameplay, playback, native flag
overrides, CDO changes or deletion. Native edit/reset acceptance remains pending.
"""
import asyncio,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'.local'))
from editor_api import long_client,call,ROOT

M='/eda26a53-42c0-4b9e-8f62-31719aef6889'

def plan(actors,course):
    arenas=json.loads((ROOT.parent/'uefn/arena-layout.json').read_text(encoding='utf-8'))
    arena=next(a for a in arenas['arenas'] if a['mode']=='EditTraining')
    lane_x=arena['center'][0]+arenas['edit_course']['chain_lane_offset']
    templates={r['label'].removeprefix('PCL_Triple_'):r for r in course['parts'] if r['label'].startswith('PCL_Triple_')}
    specs=[]
    for stage in range(3):
        y=-1280+stage*512;z=stage*384
        for name,kind,py,pz in [('Ramp','Ramp',y,z),('Floor','Floor',y,z+384),('Cone','Cone',y,z+384),('Wall','Wall',y+512,z+384),('Landing','Floor',y+512,z+384)]:
            specs.append({'label':f'PCL_Chain_{stage+1}_{name}','kind':kind,'source':templates[name]['actorPath'],'native':True,'target':{'location':{'x':lane_x,'y':py,'z':pz},'rotation':{'pitch':0,'yaw':0,'roll':0},'scale':{'x':1,'y':1,'z':1}}})
    for name,x,z,sx,sy,sz in [('Left',lane_x-304,832,.24,23.04,16.64),('Right',lane_x+304,832,.24,23.04,16.64),('Ceiling',lane_x,1664,6.32,23.04,.16)]:
        specs.append({'label':'PCL_Chain_Lane_'+name,'source':actors['PCL_Triple_Lane_'+name]['refPath'],'native':False,'target':{'location':{'x':x,'y':-512,'z':z},'rotation':{'pitch':0,'yaw':0,'roll':0},'scale':{'x':sx,'y':sy,'z':sz}}})
    return specs

async def main():
    record_path=ROOT/'course167-authoring.json'
    if record_path.exists():raise RuntimeError('Authoring record exists; inspect actual state before any continuation')
    actors_path=ROOT/'academy-actors.json';course_path=ROOT.parent/'uefn/course-runtime.json'
    actors=json.loads(actors_path.read_text(encoding='utf-8'));course=json.loads(course_path.read_text(encoding='utf-8'))
    specs=plan(actors,course)
    record={'scope':__doc__,'gameplay_launched':False,'specs':specs}
    record_path.write_text(json.dumps(record,indent=2),encoding='utf-8')
    code='SPECS='+repr(specs)+'\nMOUNT='+repr(M)+'''\nimport unreal,json
subsystem=unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
existing={a.get_actor_label() for a in subsystem.get_all_level_actors()}
sources={}
for row in SPECS:
    if row['label'] in existing:raise RuntimeError('A target label already exists; do not duplicate it')
    source=unreal.load_object(None,row['source'])
    if source is None or source.get_attach_parent_actor() is not None:raise RuntimeError('Missing or attached source')
    if row['native'] and not source.get_class().get_path_name().startswith(MOUNT+'/Art/Investigations/PCL_BP_Course'):raise RuntimeError('Unexpected native source class')
    sources[row['source']]=source
created=[]
for row in SPECS:
    source=sources[row['source']];p=source.get_actor_location();target=row['target']['location']
    actor=subsystem.duplicate_actor(source,offset=unreal.Vector(target['x']-p.x,target['y']-p.y,target['z']-p.z))
    if actor is None:raise RuntimeError('Public duplicate operation did not return an actor')
    actor.set_actor_label(row['label'])
    if not row['native']:
        scale=row['target']['scale'];actor.set_actor_scale3d(unreal.Vector(scale['x'],scale['y'],scale['z']))
    if actor.get_class()!=source.get_class():raise RuntimeError('Duplicated class differs')
    flags={}
    if row['native']:
        for key in ['team','bPlayerPlaced','bCanBeDamaged','bIsPlayerBuildable']:
            before=str(source.get_editor_property(key));after=str(actor.get_editor_property(key))
            if before!=after:raise RuntimeError('Duplication changed a native configuration flag; do not override it')
            flags[key]=after
    q=actor.get_actor_location()
    if abs(q.x-target['x'])>.1 or abs(q.y-target['y'])>.1 or abs(q.z-target['z'])>.1:raise RuntimeError('Duplicated position differs')
    created.append({'label':row['label'],'actor':{'refPath':actor.get_path_name()},'class':actor.get_class().get_path_name(),'native':row['native'],'flags':flags})
print(json.dumps(created))
'''
    async with long_client() as c:
        if await call(c,'EditorToolset.LevelToolset','GetCurrentLevel',{})!=M+'/ProCoachLab':raise RuntimeError('Unexpected level')
        if await call(c,'ValkyrieFortniteToolset.SessionToolset','GetGameState',{})!='Unconnected':raise RuntimeError('Expected disconnected editor')
        record['created']=json.loads(await call(c,'editor_toolset.toolsets.python_scripting.PythonScriptingTools','execute_python',{'script':{'content':code,'language':'Python'}}))
        record_path.write_text(json.dumps(record,indent=2),encoding='utf-8')
        for row in record['created']:actors[row['label']]=row['actor']
        actors_path.write_text(json.dumps(actors,indent=2),encoding='utf-8')
        native=[r for r in record['created'] if r['native']]
        await call(c,'EditorToolset.LevelToolset','AddActorsToDataLayer',{'actors':[r['actor'] for r in native],'assetPath':course['layer']['refPath'].split('.')[0]})
        members=await call(c,'EditorToolset.LevelToolset','GetActorsInDataLayer',{'assetPath':course['layer']['refPath']})
        member_paths={r['actorPath'] for r in members}
        if any(r['actor']['refPath'] not in member_paths for r in native):raise RuntimeError('A new course part is not in the reset layer')
        record['layer_members']=len(member_paths)
        record['reset_options']={}
        for label in ['PCL_Edit_Reset','PCL_Edit_Reset_Upper']:
            opts=await call(c,'ValkyrieFortniteToolset.DeviceToolset','ListClassicDeviceOptions',{'devicePath':actors[label]})
            record['reset_options'][label]=[o for o in opts if any(k in (o['name']+' '+o['displayName']).lower() for k in ['radius','player damage','structure damage','damage to indestructible'])]
        record['save']=await call(c,'editor_toolset.toolsets.python_scripting.PythonScriptingTools','execute_python',{'script':{'content':'import unreal\nprint(unreal.EditorLoadingAndSavingUtils.save_dirty_packages(True,True))','language':'Python'}})
        record_path.write_text(json.dumps(record,indent=2),encoding='utf-8')
    course['parts'] += [{'label':r['label'],'nativeClass':{'refPath':r['class']},'actorPath':r['actor']['refPath']} for r in native]
    course_path.write_text(json.dumps(course,indent=2),encoding='utf-8')
    lane_x=specs[0]['target']['location']['x']
    (ROOT.parent/'uefn/course-chain-layout.json').write_text(json.dumps({'scope':'Prepared three-ascent route, not native edit/reset or timing acceptance.','center_x':lane_x,'start':[lane_x,-1450,100],'stages':3,'sections':3,'parts':specs,'layer':course['layer']},indent=2),encoding='utf-8')
    print(json.dumps({'native_parts':len(native),'corridor_parts':len(record['created'])-len(native),'layer_members':record['layer_members'],'save':record['save'],'reset_options':{k:[{'name':o['name'],'value':o['currentValue']} for o in v] for k,v in record['reset_options'].items()}}),flush=True)

if __name__=='__main__':asyncio.run(main())
