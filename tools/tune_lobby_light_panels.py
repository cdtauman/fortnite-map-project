"""Narrow the eight existing lobby ceiling light panels; preserve their poses."""
import asyncio,json,math,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'.local'))
from editor_api import long_client,call,ROOT
M='/eda26a53-42c0-4b9e-8f62-31719aef6889'
L='EditorToolset.LevelToolset'
A='EditorToolset.ActorToolset'
async def main():
    path=ROOT/'lobby203-authoring.json'
    if path.exists():raise RuntimeError('Inspect the saved result instead of replaying authoring')
    layout=json.loads((ROOT.parent/'uefn/environment-finish-layout.json').read_text(encoding='utf-8'))
    original=json.loads((ROOT/'environment146-authoring.json').read_text(encoding='utf-8'))
    parts=[p for p in layout['parts'] if p['name'].startswith('PCL_Finish_CeilingPanel_')]
    if len(parts)!=8:raise RuntimeError('Expected only the eight existing ceiling panels')
    report={'scope':'Eight existing decorative light-panel scales only; no collision, gameplay, device wiring or source changes','actors':[],'complete':False}
    def save():path.write_text(json.dumps(report,indent=2),encoding='utf-8')
    async with long_client() as c:
        if await call(c,L,'GetCurrentLevel',{})!=M+'/ProCoachLab':raise RuntimeError('Unexpected level')
        if await call(c,'ValkyrieFortniteToolset.SessionToolset','GetGameState',{})!='Unconnected':raise RuntimeError('Game must remain stopped')
        matches=await call(c,L,'FindActors',{'filter':{'name':'PCL_Finish_CeilingPanel_'}})
        for part in parts:
            found=[a for a in matches if a['label']==part['name']]
            ref=original['geometry'][part['name']]
            if len(found)!=1 or found[0]['actorPath']!=ref['refPath']:raise RuntimeError('Panel identity changed')
            pose=await call(c,A,'GetActorTransform',{'actor':ref})
            if any(abs(pose['scale'][k]-part['transform']['scale'][k])>0.001 for k in ['x','y','z']):raise RuntimeError('Panel scale changed independently')
            if math.dist([pose['location'][k] for k in ['x','y','z']],[part['transform']['location'][k] for k in ['x','y','z']])>1:raise RuntimeError('Panel moved independently')
            new=json.loads(json.dumps(pose));new['scale']['x']=4.2;new['scale']['y']=0.7
            report['actors'].append({'label':part['name'],'actor':ref,'before':pose,'target':new})
        save()
        for row in report['actors']:
            await call(c,A,'SetActorTransform',{'actor':row['actor'],'xform':row['target'],'bWorldSpace':True})
            row['after']=await call(c,A,'GetActorTransform',{'actor':row['actor']});save()
            if any(abs(row['after']['scale'][k]-row['target']['scale'][k])>0.001 for k in ['x','y','z']):raise RuntimeError('Panel readback differs')
            row['save_actor']=await call(c,L,'SaveActor',{'actor':row['actor']});save()
            if row['save_actor'] is False:raise RuntimeError('Panel save rejected')
        report['save']=await call(c,'editor_toolset.toolsets.python_scripting.PythonScriptingTools','execute_python',{'script':{'content':'import unreal\nprint(unreal.EditorLoadingAndSavingUtils.save_dirty_packages(True,True))','language':'Python'}})
        report['complete']=report['save']=='True\n';save()
        if not report['complete']:raise RuntimeError('Final save did not complete')
    print(json.dumps({'changed_panels':len(report['actors']),'save':report['save']}),flush=True)
asyncio.run(main())
