"""Author the personal arena's perimeter architecture through public editor tools.

Decorative owned meshes and existing materials only; no game, upload or Verse build.
"""
import asyncio,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'.local'))
from editor_api import long_client,call,ROOT
from build_academy_scene import MOUNT,FOLDER,pose

def layout(mode='Personal'):
    arena=next(a for a in json.loads((ROOT.parent/'uefn/arena-layout.json').read_text(encoding='utf-8'))['arenas'] if a['mode']==mode)
    cx,cy,cz=arena['center'];half=arena['half_extent']
    parts=[]
    for side,axis,sign in [('N','y',1),('S','y',-1),('E','x',1),('W','x',-1)]:
        def add(name,along,z,width,height,depth,inset,material):
            x,y=(cx+along,cy+sign*(half-inset)) if axis=='y' else (cx+sign*(half-inset),cy+along)
            sx,sy=(width/100,depth/100) if axis=='y' else (depth/100,width/100)
            parts.append({'name':'PCL_'+mode+'Finish_'+side+'_'+name,'mode':mode,'side':side,'transform':pose(x,y,cz+z,sx,sy,height/100),'material':material,'collision':'NoCollision'})
        add('Wall',0,384,half*2,768,24,44,'Stone')
        intervals=max(1,round(half*2/1024))
        for i in range(intervals+1):
            add('Rib_'+str(i),-half+i*half*2/intervals,384,12,768,20,70,'Graphite')
        add('Cap',0,784,half*2,32,28,70,'Metal')
        add('Accent',0,765,half*2-128,4,3,88,arena['accent'])
        add('Plinth',0,70,half*2,140,22,72,'Graphite')
    return parts

SCRIPT='''import json
async def level():
    return (await execute_tool('EditorToolset.LevelToolset.GetCurrentLevel','{}'))['returnValue']
async def state():
    return (await execute_tool('ValkyrieFortniteToolset.SessionToolset.GetGameState','{}'))['returnValue']
async def add(part):
    return (await execute_tool('EditorToolset.LevelToolset.AddToSceneFromAsset',json.dumps({'assetPath':FOLDER+'/PCL_SM_BevelledBlock.PCL_SM_BevelledBlock','name':part['name'],'xform':part['transform']})))['returnValue']
async def components(actor):
    return (await execute_tool('EditorToolset.ActorToolset.GetComponents',json.dumps({'actor':actor})))['returnValue']
async def configure(component,material):
    return await execute_tool('EditorToolset.ObjectToolset.SetProperties',json.dumps({'instance':component,'values':json.dumps({'overrideMaterials':[MATERIALS[material]],'castShadow':False,'bodyInstance':{'collisionEnabled':'NoCollision'}})}))
async def save(actor):
    return await execute_tool('EditorToolset.LevelToolset.SaveActor',json.dumps({'actor':actor}))
async def run():
    current_level=await level()
    current_state=await state()
    if current_level!=MOUNT+'/ProCoachLab' or current_state!='Unconnected':raise RuntimeError('Expected disconnected ProCoachLab editor')
    rows=[]
    for part in PARTS:
        actor=await add(part)
        comps=await components(actor)
        component=next(r for r in comps if r['refPath'].endswith('.StaticMeshComponent0'))
        await configure(component,part['material'])
        await save(actor)
        rows.append({'name':part['name'],'actor':actor,'component':component})
    return {'actors':rows}
'''

async def main():
    output=ROOT/'personal-finish173-authoring.json'
    if output.exists():raise RuntimeError('Authoring record exists; inspect current actors before continuation')
    parts=layout()
    actors_path=ROOT/'academy-actors.json';actors=json.loads(actors_path.read_text(encoding='utf-8'))
    if any(p['name'] in actors for p in parts):raise RuntimeError('Perimeter actor names already exist')
    materials=json.loads((ROOT.parent/'uefn/academy-layout.json').read_text(encoding='utf-8'))['materials']
    record={'scope':__doc__,'gameplay_launched':False,'actors':[]}
    def persist():output.write_text(json.dumps(record,indent=2),encoding='utf-8')
    persist()
    async with long_client() as c:
        for side in ['N','S','E','W']:
            payload='MOUNT='+repr(MOUNT)+'\nFOLDER='+repr(FOLDER)+'\nMATERIALS='+repr(materials)+'\nPARTS='+repr([p for p in parts if p['side']==side])+'\n'+SCRIPT
            rows=await call(c,'editor_toolset.toolsets.programmatic.ProgrammaticToolset','execute_tool_script',{'script':{'content':payload,'language':'Python'}})
            if isinstance(rows,str):rows=json.loads(rows)
            rows=rows['actors']
            record['actors']+=rows
            for r in rows:actors[r['name']]=r['actor']
            actors_path.write_text(json.dumps(actors,indent=2),encoding='utf-8');persist()
            print('Perimeter side saved: '+side,flush=True)
        code='''import unreal,json
rows=[]
for row in ROWS:
    actor=unreal.load_object(None,row['actor']['refPath'])
    component=unreal.load_object(None,row['component']['refPath'])
    if actor is None or component is None:raise RuntimeError('Authored component missing')
    collision=component.get_editor_property('body_instance').get_editor_property('collision_enabled')
    if collision!=unreal.CollisionEnabled.NO_COLLISION:raise RuntimeError('Expected decorative collision policy')
    rows.append({'name':row['name'],'material':component.get_material(0).get_path_name(),'collision':str(collision)})
print(json.dumps({'actors':rows,'save':unreal.EditorLoadingAndSavingUtils.save_dirty_packages(True,True)}))
'''
        result=await call(c,'editor_toolset.toolsets.python_scripting.PythonScriptingTools','execute_python',{'script':{'content':'ROWS='+repr(record['actors'])+'\n'+code,'language':'Python'}})
        record['readback']=json.loads(result);persist()
    (ROOT.parent/'uefn/personal-environment-finish.json').write_text(json.dumps({'scope':'Editor perimeter architecture; final client readability, navigation and performance pending.','parts':parts,'record':'.local/personal-finish173-authoring.json','policy':'Existing gameplay boundaries and open arena center; all added mesh components configured NoCollision.'},ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'authored':len(record['actors']),'save':record['readback']['save']}),flush=True)

if __name__=='__main__':asyncio.run(main())
