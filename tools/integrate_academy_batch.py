"""Apply a complete source/resource authoring batch through the editor's native batch API.

Does not launch Fortnite, upload, start a session, or execute acceptance fixtures.
"""
import asyncio,hashlib,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'.local'))
from editor_api import Client,call
from build_academy_scene import MOUNT,pose

async def main():
    environment=json.loads((ROOT/'.local/batch-authoring-environment.json').read_text())
    if 'execute_tool' not in environment['instructions']:raise RuntimeError('Read the current batch execution instructions first.')
    sources=[{'name':p.name,'content':p.read_text(encoding='utf-8')} for p in sorted((ROOT/'uefn/Verse').glob('*.verse'))]
    actors_path=ROOT/'.local/academy-actors.json';actors=json.loads(actors_path.read_text())
    network=json.loads((ROOT/'.local/arena-reset-network.json').read_text())
    bindings={}
    for mode in ['Personal','Duel','FreeBuild']:
        refs=sorted((label,ref) for label,ref in network['resets'].items() if label.startswith('PCL_ResetNetwork_'+mode+'_'))
        for index,(_,ref) in enumerate(refs):bindings[f'{mode}Reset{index+1:02}']=ref
    for mode in ['Personal','Duel','FreeBuild','EditTraining']:
        bindings[mode+'Return']=network['returns']['PCL_Return_'+mode]
    script='''import json
async def write_source(path, content):
    return await execute_tool('VerseToolset.VerseToolset.WriteFile',json.dumps({'path':path,'content':content,'bCreateIfMissing':True}))
async def compile_sources():
    return (await execute_tool('VerseToolset.VerseToolset.BuildAll','{}'))['returnValue']
async def find_controls():
    return (await execute_tool('EditorToolset.LevelToolset.FindActors',json.dumps({'filter':{'name':'PCL_Arena_Controls'}})))['returnValue']
async def place_controls(asset, transform):
    return (await execute_tool('ValkyrieFortniteToolset.DeviceToolset.PlaceDevice',json.dumps({'assetPath':asset,'transform':transform})))['returnValue']
async def label_actor(actor, label):
    return await execute_tool('EditorToolset.ActorToolset.SetLabel',json.dumps({'actor':actor,'label':label}))
async def set_binding(actor, name, value):
    return await execute_tool('ValkyrieFortniteToolset.DeviceToolset.SetDeviceProperty',json.dumps({'device':actor,'propertyName':name,'value':json.dumps(value)}))
async def save_actor(actor):
    return await execute_tool('EditorToolset.LevelToolset.SaveActor',json.dumps({'actor':actor}))
async def save_packages():
    return await execute_tool('editor_toolset.toolsets.python_scripting.PythonScriptingTools.execute_python',json.dumps({'script':{'content':'import unreal\\nprint(unreal.EditorLoadingAndSavingUtils.save_dirty_packages(True, True))','language':'Python'}}))
async def run():
    for source in SOURCES:
        await write_source(MOUNT+'/'+source['name'],source['content'])
    diagnostics=await compile_sources()
    if diagnostics:return {'compiler':diagnostics,'gameplay_launched':False}
    existing=[x for x in await find_controls() if x['label']=='PCL_Arena_Controls']
    controller={'refPath':existing[0]['actorPath']} if existing else await place_controls({'refPath':MOUNT+'/_Verse.coach_arena_controls_device'},TRANSFORM)
    await label_actor(controller,'PCL_Arena_Controls')
    for name,value in BINDINGS.items():
        await set_binding(controller,name,value)
    await set_binding(PORTAL,'ArenaControls',controller)
    await set_binding(controller,'Configured',True)
    await save_actor(controller)
    await save_actor(PORTAL)
    saved=await save_packages()
    return {'compiler':[],'sources':len(SOURCES),'bindings':len(BINDINGS),'controller':controller,'save':saved,'gameplay_launched':False}
'''
    script='MOUNT='+repr(MOUNT)+'\nSOURCES='+repr(sources)+'\nBINDINGS='+repr(bindings)+'\nPORTAL='+repr(actors['PCL_Portal_Director'])+'\nTRANSFORM='+repr(pose(-300,-7100,-200))+'\n'+script
    async with Client('http://127.0.0.1:8000/mcp',mode='legacy') as c:
        result=await call(c,'editor_toolset.toolsets.programmatic.ProgrammaticToolset','execute_tool_script',{'script':{'content':script,'language':'Python'}})
    if isinstance(result,str):result=json.loads(result)
    result['scope']='Source compilation and editor resource bindings only; no game launch or acceptance.'
    result['source_hashes']={x['name']:hashlib.sha256(x['content'].encode('utf-8')).hexdigest() for x in sources}
    (ROOT/'.local/academy-batch-integration.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    if 'controller' in result:
        actors['PCL_Arena_Controls']=result['controller']
        actors_path.write_text(json.dumps(actors,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ['source_hashes','save']},ensure_ascii=True),flush=True)

if __name__=='__main__':asyncio.run(main())
