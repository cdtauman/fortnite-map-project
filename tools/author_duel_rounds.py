"""Author the owned duel preparation zone and integrate round-flow sources.

Run only for an intended authoring change. No game/session/upload is started.
"""
import asyncio,hashlib,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'.local'))
from editor_api import long_client,call,ROOT

M='/eda26a53-42c0-4b9e-8f62-31719aef6889'
async def main():
    actors=json.loads((ROOT/'academy-actors.json').read_text())
    names=['coach_duel_flow.verse','coach_portal_device.verse','coach_ui.verse']
    sources=[{'name':n,'content':(ROOT.parent/'uefn/Verse'/n).read_text(encoding='utf-8')} for n in names]
    path=ROOT/'duel-rounds-authoring.json'
    record={'scope':'Duel round lifecycle, admission zone and countdown source/editor authoring; no gameplay/session/upload/probe.','sources':{s['name']:hashlib.sha256(s['content'].encode()).hexdigest() for s in sources},'gameplay_launched':False}
    if path.exists():
        before=json.loads(path.read_text())
        record['previous_compilations']=before.get('previous_compilations',[])+[{'sources':before.get('sources'),'compiler':before.get('compiler')}]
    options={'EnabledOnPhase':'Gameplay Only','ZoneWidth':'22.000000','ZoneDepth':'22.000000','ZoneHeight':'100.000000','ZoneVisibleDuringGame':'False','bAllowBuilding':'False','bAllowEditing':'False','bAllowWeaponFire':'False','EnableVFX':'False'}
    script='''import json
async def write_source(path,content):
    return await execute_tool('VerseToolset.VerseToolset.WriteFile',json.dumps({'path':path,'content':content,'bCreateIfMissing':True}))
async def compile_sources():
    return (await execute_tool('VerseToolset.VerseToolset.BuildAll','{}'))['returnValue']
async def set_option(device,name,value):
    return await execute_tool('ValkyrieFortniteToolset.DeviceToolset.SetClassicDeviceOption',json.dumps({'devicePath':device,'optionName':name,'value':value}))
async def set_binding(device,name,value):
    return await execute_tool('ValkyrieFortniteToolset.DeviceToolset.SetDeviceProperty',json.dumps({'device':device,'propertyName':name,'value':json.dumps(value)}))
async def save_actor(actor):
    return await execute_tool('EditorToolset.LevelToolset.SaveActor',json.dumps({'actor':actor}))
async def save_packages():
    return (await execute_tool('editor_toolset.toolsets.python_scripting.PythonScriptingTools.execute_python',json.dumps({'script':{'content':'import unreal\\nprint(unreal.EditorLoadingAndSavingUtils.save_dirty_packages(True,True))','language':'Python'}})))['returnValue']
async def run():
    for name,value in OPTIONS.items():await set_option(ZONE,name,value)
    await save_actor(ZONE)
    for source in SOURCES:await write_source(MOUNT+'/'+source['name'],source['content'])
    diagnostics=await compile_sources()
    if diagnostics:return {'compiler':diagnostics,'zone_options':OPTIONS}
    await set_binding(PORTAL,'DuelPreparationZone',ZONE)
    await set_binding(PORTAL,'DuelPreparationConfigured',True)
    await save_actor(PORTAL)
    return {'compiler':[],'zone_options':OPTIONS,'configured':True,'save':await save_packages()}
'''
    async with long_client() as c:
        level=await call(c,'EditorToolset.LevelToolset','GetCurrentLevel',{})
        state=await call(c,'ValkyrieFortniteToolset.SessionToolset','GetGameState',{})
        if level!=M+'/ProCoachLab' or state=='Running':
            raise RuntimeError('Open ProCoachLab with the game stopped before authoring')
        label='PCL_Duel_Preparation_Zone'
        matches=await call(c,'EditorToolset.LevelToolset','FindActors',{'filter':{'name':label}})
        existing=next((a for a in matches if a['label']==label),None)
        if existing:
            zone={'refPath':existing['actorPath']}
        else:
            catalog=await call(c,'ValkyrieFortniteToolset.DeviceToolset','ListDeviceAssets',{'nameFilter':'Mutator'})
            asset=next(x['assetPath'] for x in catalog if x['displayName']=='PID_Device_Mutator')
            pose={'location':{'x':0,'y':45056,'z':0},'rotation':{'pitch':0,'yaw':0,'roll':0},'scale':{'x':1,'y':1,'z':1}}
            zone=await call(c,'ValkyrieFortniteToolset.DeviceToolset','PlaceDevice',{'assetPath':asset,'transform':pose})
            await call(c,'EditorToolset.ActorToolset','SetLabel',{'actor':zone,'label':label})
        actors[label]=zone
        (ROOT/'academy-actors.json').write_text(json.dumps(actors,indent=2),encoding='utf-8')
        record['zone']=zone
        payload='MOUNT='+repr(M)+'\nSOURCES='+repr(sources)+'\nOPTIONS='+repr(options)+'\nZONE='+repr(zone)+'\nPORTAL='+repr(actors['PCL_Portal_Director'])+'\n'+script
        result=await call(c,'editor_toolset.toolsets.programmatic.ProgrammaticToolset','execute_tool_script',{'script':{'content':payload,'language':'Python'}})
    if isinstance(result,str):result=json.loads(result)
    record.update(result)
    path.write_text(json.dumps(record,indent=2),encoding='utf-8')
    print(json.dumps(result),flush=True)
asyncio.run(main())
