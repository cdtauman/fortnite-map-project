"""Create scoped reset volumes and physical return controls; defer Verse wiring until compilation."""
import asyncio,json,math,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'.local'))
from editor_api import Client,call
from build_academy_scene import pose

async def main():
    actor_path=ROOT/'.local/academy-actors.json';actors=json.loads(actor_path.read_text())
    catalog=json.loads((ROOT/'.local/device-catalog-all.json').read_text())
    layout=json.loads((ROOT/'uefn/arena-layout.json').read_text(encoding='utf-8'))
    path=ROOT/'.local/arena-reset-network.json'
    ledger=json.loads(path.read_text()) if path.exists() else {'resets':{},'returns':{},'completed':[],'binding_plan':{}}
    def save():
        actor_path.write_text(json.dumps(actors,indent=2),encoding='utf-8')
        path.write_text(json.dumps(ledger,indent=2),encoding='utf-8')
    assets={x['displayName']:x['assetPath'] for x in catalog}
    async with Client('http://127.0.0.1:8000/mcp',mode='legacy') as c:
        reset_values=await call(c,'ValkyrieFortniteToolset.DeviceToolset','GetClassicDeviceOptionValues',{'devicePath':actors['PCL_Arena_Reset'],'optionName':'Blast Radius'})
        radii=sorted((float(x['value']),x['value']) for x in reset_values)
        async def place(label,asset,xform):
            existing=ledger['resets'].get(label) or ledger['returns'].get(label)
            if existing:actors[label]=existing
            if label not in actors:
                actors[label]=await call(c,'ValkyrieFortniteToolset.DeviceToolset','PlaceDevice',{'assetPath':assets[asset],'transform':xform})
                await call(c,'EditorToolset.ActorToolset','SetLabel',{'actor':actors[label],'label':label});save()
            else:
                await call(c,'EditorToolset.ActorToolset','SetActorTransform',{'actor':actors[label],'xform':xform})
                await call(c,'EditorToolset.LevelToolset','SaveActor',{'actor':actors[label]})
            return actors[label]
        async def configure(label,ref,values):
            if label in ledger['completed']:return
            for key,value in values.items():
                await call(c,'ValkyrieFortniteToolset.DeviceToolset','SetClassicDeviceOption',{'devicePath':ref['refPath'],'optionName':key,'value':value})
            await call(c,'EditorToolset.LevelToolset','SaveActor',{'actor':ref})
            ledger['completed'].append(label);save()
        for arena in layout['arenas']:
            mode=arena['mode'];cx,cy,cz=arena['center'];half=arena['half_extent']
            if mode in ['Personal','Duel','FreeBuild']:
                requested={'Personal':9.0,'Duel':15.0,'FreeBuild':25.0}[mode]
                radius,stored=next(pair for pair in radii if pair[0]>=requested) if radii else (requested,format(requested,'.6f'))
                if mode=='Personal' and radius>9.0:
                    raise ValueError('A larger personal reset would overlap the lobby; author a spatial grid instead.')
                vertical=math.sqrt((radius*512)**2-2*half**2)
                count=math.ceil(layout['enclosure_top']/(2*vertical*.98))
                spacing=layout['enclosure_top']/count
                refs=[]
                for index in range(count):
                    label=f'PCL_ResetNetwork_{mode}_{index:02}'
                    ref=await place(label,'PID_Device_ExplosiveBarrel',pose(cx,cy,cz+(index+.5)*spacing))
                    ledger['resets'][label]=ref;save()
                    await configure(label,ref,{'Can be Damaged':'False','Blast Radius':stored,'Player Damage':'0.000000','Structure Damage':'100000.000000','Damage Indestructible Buildings':'False','Visible During Game':'False','Play Audio / VFX':'False','Play Audio':'False','Knockback':'None','Collision During Games':'Off','Show Health Bar':'False','Has Timed Detonation From Game Start':'False','Explode on Proximity':'False'})
                    refs.append(ref)
                ledger['binding_plan'][{'Personal':'PersonalResetDevices','Duel':'DuelResetDevices','FreeBuild':'FreeResetDevices'}[mode]]=refs;save()
            label='PCL_Return_'+mode
            ref=await place(label,'PID_Device_Button',pose(cx-half+180,cy,cz+110))
            await configure(label,ref,{'VisibleDuringGame':'False','InteractionRadius':'2.000000','Interaction Text':'חזרה ללובי'})
            ledger['returns'][label]=ref;save()
        ledger['binding_plan']['ArenaReturnButtons']=list(ledger['returns'].values());save()
    print('Prepared reset network',len(ledger['resets']),'and returns',len(ledger['returns']),'no gameplay launched',flush=True)

if __name__=='__main__':asyncio.run(main())
