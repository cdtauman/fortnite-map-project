"""Author the personal-round admission volume through public editor tools.

Source compilation is a separate intended batch. No game or session is started.
"""
import asyncio,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'.local'))
from editor_api import long_client,call,ROOT

M='/eda26a53-42c0-4b9e-8f62-31719aef6889'

async def main():
    actors=json.loads((ROOT/'academy-actors.json').read_text(encoding='utf-8'))
    options={'EnabledOnPhase':'Gameplay Only','ZoneWidth':'14.000000','ZoneDepth':'14.000000','ZoneHeight':'100.000000','ZoneVisibleDuringGame':'False','bAllowBuilding':'False','bAllowEditing':'False','bAllowWeaponFire':'False','EnableVFX':'False'}
    record={'scope':'Personal-round preparation volume and director bindings; no game/session/upload/probe.','gameplay_launched':False,'options':options}
    async with long_client() as c:
        level=await call(c,'EditorToolset.LevelToolset','GetCurrentLevel',{})
        state=await call(c,'ValkyrieFortniteToolset.SessionToolset','GetGameState',{})
        if level!=M+'/ProCoachLab' or state=='Running':
            raise RuntimeError('Open ProCoachLab with the game stopped before authoring')
        label='PCL_Personal_Preparation_Zone'
        matches=await call(c,'EditorToolset.LevelToolset','FindActors',{'filter':{'name':label}})
        existing=next((a for a in matches if a['label']==label),None)
        if existing:
            zone={'refPath':existing['actorPath']}
        else:
            catalog=await call(c,'ValkyrieFortniteToolset.DeviceToolset','ListDeviceAssets',{'nameFilter':'Mutator'})
            asset=next(x['assetPath'] for x in catalog if x['displayName']=='PID_Device_Mutator')
            pose={'location':{'x':0,'y':0,'z':0},'rotation':{'pitch':0,'yaw':0,'roll':0},'scale':{'x':1,'y':1,'z':1}}
            zone=await call(c,'ValkyrieFortniteToolset.DeviceToolset','PlaceDevice',{'assetPath':asset,'transform':pose})
            await call(c,'EditorToolset.ActorToolset','SetLabel',{'actor':zone,'label':label})
        actors[label]=zone
        (ROOT/'academy-actors.json').write_text(json.dumps(actors,indent=2),encoding='utf-8')
        record['zone']=zone
        for name,value in options.items():
            await call(c,'ValkyrieFortniteToolset.DeviceToolset','SetClassicDeviceOption',{'devicePath':zone,'optionName':name,'value':value})
        await call(c,'EditorToolset.LevelToolset','SaveActor',{'actor':zone})
        for name,value in {'PersonalPreparationZone':zone,'PersonalPreparationConfigured':True}.items():
            await call(c,'ValkyrieFortniteToolset.DeviceToolset','SetDeviceProperty',{'device':actors['PCL_Portal_Director'],'propertyName':name,'value':json.dumps(value)})
        await call(c,'EditorToolset.LevelToolset','SaveActor',{'actor':actors['PCL_Portal_Director']})
        record['configured']=True
        record['save']=await call(c,'editor_toolset.toolsets.python_scripting.PythonScriptingTools','execute_python',{'script':{'content':'import unreal\nprint(unreal.EditorLoadingAndSavingUtils.save_dirty_packages(True,True))','language':'Python'}})
    (ROOT/'personal-zone156-authoring.json').write_text(json.dumps(record,indent=2),encoding='utf-8')
    print(json.dumps(record),flush=True)

if __name__=='__main__':asyncio.run(main())
