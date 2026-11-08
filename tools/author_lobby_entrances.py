"""Make the four lobby entrances walk-in gateways with visible fallback buttons.

Authors and saves the local map only; no session upload or gameplay start.
"""
import asyncio,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'.local'))
from editor_api import long_client,call,ROOT
M='/eda26a53-42c0-4b9e-8f62-31719aef6889'
D='ValkyrieFortniteToolset.DeviceToolset'
A='EditorToolset.ActorToolset'
L='EditorToolset.LevelToolset'

async def main():
    path=ROOT/'entry187-authoring.json'
    if path.exists():raise RuntimeError('Inspect the recorded entrance authoring stage before resuming')
    actors=json.loads((ROOT/'academy-actors.json').read_text())
    catalog=json.loads((ROOT/'entry187-volume-catalog.json').read_text())
    asset=next(r['assetPath'] for r in catalog if r['displayName']=='PID_CP_Devices_Volume')
    report={'scope':'Local entrance map/wiring repair; no game/session/upload.','entrances':{}}
    def persist():
        path.write_text(json.dumps(report,indent=2),encoding='utf-8')
        (ROOT/'academy-actors.json').write_text(json.dumps(actors,indent=2),encoding='utf-8')
    def pose(x,y,z):return {'location':{'x':x,'y':y,'z':z},'rotation':{'pitch':0,'yaw':0,'roll':0},'scale':{'x':1,'y':1,'z':1}}
    async with long_client() as c:
        if await call(c,L,'GetCurrentLevel',{})!=M+'/ProCoachLab':raise RuntimeError('Unexpected level')
        if await call(c,'ValkyrieFortniteToolset.SessionToolset','GetGameState',{})=='Running':raise RuntimeError('Stop the failing match before authoring entrances')
        specs=[('Personal','PCL_Menu_Personal','PersonalEntrance'),('Duel','PCL_Menu_Duel','DuelEntrance'),('FreeBuild','PCL_Menu_Free','FreeBuildEntrance'),('Edits','PCL_Menu_Edits','EditsEntrance')]
        portal=actors['PCL_Portal_Director']
        for index,(mode,button_label,field) in enumerate(specs):
            y=-8500+index*1000
            label='PCL_Lobby_Entrance_'+mode
            if any(x['label']==label for x in await call(c,L,'FindActors',{'filter':{'name':label}})):raise RuntimeError('Unexpected entrance already exists')
            actor=await call(c,D,'PlaceDevice',{'assetPath':asset,'transform':pose(1900,y,192)})
            row={'actor':actor,'button':actors[button_label]};report['entrances'][mode]=row;actors[label]=actor;persist()
            await call(c,A,'SetLabel',{'actor':actor,'label':label})
            options=await call(c,D,'ListClassicDeviceOptions',{'devicePath':actor})
            row['before_options']=options;persist()
            by_label={x['displayName']:x for x in options}
            wanted={'Volume Width':'1.0','Volume Depth':'1.25','Volume Height':'1.0','Player Events Enabled':'True','Guard Events Enabled':'False','Visible in Game':'False'}
            for display,value in wanted.items():
                if display not in by_label:raise RuntimeError('Inspect actual volume option schema: '+display)
                await call(c,D,'SetClassicDeviceOption',{'devicePath':actor,'optionName':by_label[display]['name'],'value':value})
            await call(c,A,'SetActorTransform',{'actor':actor,'xform':pose(1900,y,192),'bWorldSpace':True})
            row['volume_pose']=await call(c,A,'GetActorTransform',{'actor':actor})
            row['options']=await call(c,D,'ListClassicDeviceOptions',{'devicePath':actor})
            actual={o['displayName']:o['currentValue'] for o in row['options']}
            for display,value in wanted.items():
                if actual[display]==value:continue
                try:
                    if float(actual[display])==float(value):continue
                except ValueError:pass
                raise RuntimeError('Volume option readback differs: '+display)
            await call(c,D,'SetDeviceProperty',{'device':portal,'propertyName':field,'value':json.dumps(actor)})
            button=actors[button_label]
            row['button_before']=await call(c,A,'GetActorTransform',{'actor':button})
            for name,value in [('VisibleDuringGame','True'),('EnabledAtGameStart','True'),('InteractionRadius','2.0')]:
                await call(c,D,'SetClassicDeviceOption',{'devicePath':button,'optionName':name,'value':value})
            button_pose=pose(1360,y,160)
            button_pose['rotation']['yaw']=180
            await call(c,A,'SetActorTransform',{'actor':button,'xform':button_pose,'bWorldSpace':True})
            row['button_pose']=await call(c,A,'GetActorTransform',{'actor':button})
            row['button_options']=await call(c,D,'ListClassicDeviceOptions',{'devicePath':button})
            await call(c,L,'SaveActor',{'actor':actor});await call(c,L,'SaveActor',{'actor':button})
            persist();print('Authored entrance '+mode,flush=True)
        fields=[field for _,_,field in specs]
        report['bindings']=await call(c,D,'GetDeviceProperties',{'device':portal,'propertyNames':fields})
        bindings=json.loads(report['bindings']) if isinstance(report['bindings'],str) else report['bindings']
        if any(bindings[field]!=report['entrances'][mode]['actor'] for mode,_,field in specs):raise RuntimeError('Entrance reference mismatch')
        await call(c,D,'SetDeviceProperty',{'device':portal,'propertyName':'WalkInEntrancesConfigured','value':'true'})
        await call(c,L,'SaveActor',{'actor':portal})
        report['save']=await call(c,'editor_toolset.toolsets.python_scripting.PythonScriptingTools','execute_python',{'script':{'content':'import unreal\nprint(unreal.EditorLoadingAndSavingUtils.save_dirty_packages(True,True))','language':'Python'}})
        report['finished']=True;persist()
    print(json.dumps({'finished':report['finished'],'entrances':len(report['entrances']),'save':report['save']}),flush=True)

if __name__=='__main__':asyncio.run(main())
