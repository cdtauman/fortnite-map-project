"""Place and wire disabled native-pool controls; no playback or upload."""
import asyncio,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'.local'))
from editor_api import long_client,call,ROOT
M='/eda26a53-42c0-4b9e-8f62-31719aef6889'

async def main():
    path=ROOT/'native-pool188-controls.json'
    if path.exists():raise RuntimeError('Inspect existing controller stage; do not replay')
    bank=json.loads((ROOT/'native-pool188-placement.json').read_text())
    if not bank.get('finished'):raise RuntimeError('Bank not saved')
    runtime=json.loads((ROOT/'native-pool188-runtime-assets.json').read_text())
    ap=ROOT/'academy-actors.json';actors=json.loads(ap.read_text())
    report={'scope':__doc__,'controllers':{},'gameplay_launched':False}
    def save():
        path.write_text(json.dumps(report,indent=2),encoding='utf-8')
        ap.write_text(json.dumps(actors,indent=2),encoding='utf-8')
    async with long_client() as c:
        if await call(c,'EditorToolset.LevelToolset','GetCurrentLevel',{})!=M+'/ProCoachLab':raise RuntimeError('Unexpected level')
        found=await call(c,'EditorToolset.LevelToolset','FindActors',{'filter':{'name':'PCL_NativePool_Control'}})
        if found:raise RuntimeError('Unexpected existing controls')
        save()
        for i,kind in enumerate(['Unload','Load','Restorer']):
            label='PCL_NativePool_Control_'+kind
            asset={'refPath':M+'/_Verse.coach_native_pool_reset_device'} if kind=='Restorer' else {'refPath':'/CRD_CinematicSequence/SetupAssets/PID_CP_Devices_Cinematic.PID_CP_Devices_Cinematic'}
            pose={'location':{'x':-59000,'y':-62000+i*256,'z':-8064},'rotation':{'pitch':0,'yaw':0,'roll':0},'scale':{'x':1,'y':1,'z':1}}
            report['pending_label']=label;save()
            ref=await call(c,'ValkyrieFortniteToolset.DeviceToolset','PlaceDevice',{'assetPath':asset,'transform':pose})
            report['controllers'][kind]={'actor':ref};actors[label]=ref;save()
            await call(c,'EditorToolset.ActorToolset','SetLabel',{'actor':ref,'label':label})
            if kind!='Restorer':
                # Use the ordinary editable-property API. Never mutate a
                # rejected reference through a struct view or foreign default.
                values={'sequence':runtime['sequences'][kind]['asset'],'bLoopPlayback':False,'bAutoPlay':False,'visibility':'Everyone','bLevelSequenceActorAlwaysRelevant':True,'finishCompletionStateOverride':'ForceKeepState','showHUDDuringCinematic':'Show','disablePlayerInput':'No'}
                report['controllers'][kind]['set_result']=await call(c,'EditorToolset.ObjectToolset','SetProperties',{'instance':ref,'values':json.dumps(values)});save()
                if not report['controllers'][kind]['set_result']:raise RuntimeError('Public cinematic configuration rejected; stop here')
                report['controllers'][kind]['readback']=json.loads(await call(c,'EditorToolset.ObjectToolset','GetProperties',{'instance':ref,'properties':list(values)}));save()
            await call(c,'EditorToolset.LevelToolset','SaveActor',{'actor':ref})
        device=report['controllers']['Restorer']['actor']
        bindings={'Enabled':False,'UnloadPool':report['controllers']['Unload']['actor'],'LoadPool':report['controllers']['Load']['actor'],'WallCount':16,'FloorCount':16,'RampCount':16,'ConeCount':16}
        for name,value in bindings.items():await call(c,'ValkyrieFortniteToolset.DeviceToolset','SetDeviceProperty',{'device':device,'propertyName':name,'value':json.dumps(value)})
        report['restorer_readback']=json.loads(await call(c,'ValkyrieFortniteToolset.DeviceToolset','GetDeviceProperties',{'device':device,'propertyNames':list(bindings)}));save()
        structure=actors['PCL_Structure_Director']
        report['structure_before']=json.loads(await call(c,'ValkyrieFortniteToolset.DeviceToolset','GetDeviceProperties',{'device':structure,'propertyNames':['NativePoolRestorer','RenewNativePoolBetweenRounds','UseNativePiecePool','QueryCoverageConfirmed','HealthContinuityConfirmed','NativeSlotInteroperationConfirmed','CandidateCombatEnabled']}));save()
        for name,value in {'NativePoolRestorer':device,'RenewNativePoolBetweenRounds':False}.items():await call(c,'ValkyrieFortniteToolset.DeviceToolset','SetDeviceProperty',{'device':structure,'propertyName':name,'value':json.dumps(value)})
        report['structure_after']=json.loads(await call(c,'ValkyrieFortniteToolset.DeviceToolset','GetDeviceProperties',{'device':structure,'propertyNames':list(report['structure_before'])}));save()
        for ref in [device,structure]:await call(c,'EditorToolset.LevelToolset','SaveActor',{'actor':ref})
        report['save']=await call(c,'editor_toolset.toolsets.python_scripting.PythonScriptingTools','execute_python',{'script':{'content':'import unreal\nprint(unreal.EditorLoadingAndSavingUtils.save_dirty_packages(True,True))','language':'Python'}})
        report['finished']=True;report.pop('pending_label',None);save()
    layout_path=ROOT.parent/'uefn/native-pool-bank.json';layout=json.loads(layout_path.read_text());layout['controllers']={k:v['actor'] for k,v in report['controllers'].items()};layout['structure']=structure;layout_path.write_text(json.dumps(layout,indent=2),encoding='utf-8')
    print(json.dumps({'finished':True,'controllers':3,'restorer':report['restorer_readback'],'structure':report['structure_after'],'save':report['save']}),flush=True)

if __name__=='__main__':asyncio.run(main())
