"""Integrate one intended Verse source batch through the local editor.

Writes source, compiles once and saves packages. Does not upload or run a game.
"""
import argparse,asyncio,hashlib,json,sys
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'.local'))
from editor_api import long_client,call,ROOT

MOUNT='/eda26a53-42c0-4b9e-8f62-31719aef6889'


async def main(args):
    if Path(args.record).name!=args.record or not args.record.endswith('.json'):
        raise ValueError('Record must be a JSON filename inside .local')
    sources=[]
    for name in args.files:
        if Path(name).name!=name or not name.endswith('.verse'):
            raise ValueError('Choose a filename from uefn/Verse')
        content=(ROOT.parent/'uefn/Verse'/name).read_text(encoding='utf-8')
        sources.append({'name':name,'content':content})
    path=ROOT/args.record
    record={'scope':'Source authoring/compilation only; no gameplay/session/upload/probe.','sources':{s['name']:hashlib.sha256(s['content'].encode()).hexdigest() for s in sources},'gameplay_launched':False}
    if path.exists():
        before=json.loads(path.read_text(encoding='utf-8'))
        record['previous_compilations']=before.get('previous_compilations',[])+[{'sources':before.get('sources'),'compiler':before.get('compiler')}]
    path.write_text(json.dumps(record,indent=2),encoding='utf-8')
    script='''import json
async def current_level():
    return (await execute_tool('EditorToolset.LevelToolset.GetCurrentLevel','{}'))['returnValue']
async def game_state():
    return (await execute_tool('ValkyrieFortniteToolset.SessionToolset.GetGameState','{}'))['returnValue']
async def write_source(path,content):
    return await execute_tool('VerseToolset.VerseToolset.WriteFile',json.dumps({'path':path,'content':content,'bCreateIfMissing':CREATE_MISSING}))
async def compile_sources():
    return (await execute_tool('VerseToolset.VerseToolset.BuildAll','{}'))['returnValue']
async def save_packages():
    return (await execute_tool('editor_toolset.toolsets.python_scripting.PythonScriptingTools.execute_python',json.dumps({'script':{'content':'import unreal\\nprint(unreal.EditorLoadingAndSavingUtils.save_dirty_packages(True,True))','language':'Python'}})))['returnValue']
async def run():
    level=await current_level()
    state=await game_state()
    if level!=MOUNT+'/ProCoachLab' or state=='Running':
        raise RuntimeError('Open ProCoachLab with the game stopped before authoring')
    for source in SOURCES:await write_source(MOUNT+'/'+source['name'],source['content'])
    diagnostics=await compile_sources()
    if diagnostics:return {'compiler':diagnostics}
    return {'compiler':[],'save':await save_packages()}
'''
    payload='MOUNT='+repr(MOUNT)+'\nSOURCES='+repr(sources)+'\nCREATE_MISSING='+repr(args.create_missing)+'\n'+script
    async with long_client() as c:
        result=await call(c,'editor_toolset.toolsets.programmatic.ProgrammaticToolset','execute_tool_script',{'script':{'content':payload,'language':'Python'}})
    if isinstance(result,str):result=json.loads(result)
    record.update(result)
    path.write_text(json.dumps(record,indent=2),encoding='utf-8')
    print(json.dumps(result),flush=True)
    return 1 if result.get('compiler') else 0


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--record',required=True)
    parser.add_argument('--create-missing',action='store_true')
    parser.add_argument('files',nargs='+')
    raise SystemExit(asyncio.run(main(parser.parse_args())))
