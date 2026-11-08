"""Author the academy lobby from the owned modular kit through the editor connection."""
import asyncio,json,sys
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'.local'))
from editor_api import Client,call,ROOT

MOUNT='/eda26a53-42c0-4b9e-8f62-31719aef6889'
FOLDER=MOUNT+'/Art/AcademyKit'

def pose(x,y,z,sx=1,sy=1,sz=1,yaw=0):
    return {'location':dict(x=x,y=y,z=z),'rotation':dict(pitch=0,yaw=yaw,roll=0),'scale':dict(x=sx,y=sy,z=sz)}

def layout():
    specs=[]
    def add(name,xform,material,shape='Block',collision=False,accent=None):
        specs.append(dict(name='PCL_Academy_'+name,transform=xform,material=material,shape=shape,collision=collision,accent=accent))
    add('Foundation',pose(0,-7000,-40,50,44,.8),'Floor','Cube',True)
    for name,x,y,sx,sy,mat in [('West',-2500,-7000,.8,44,'Stone'),('East',2500,-7000,.8,44,'Graphite'),('South',0,-9200,50,.8,'Stone'),('North',0,-4800,50,.8,'Stone')]:
        add('Wall_'+name,pose(x,y,500,sx,sy,10),mat,'Cube',True)
        add('WallCap_'+name,pose(x,y,1010,sx+(.25 if sx<1 else 0),sy+(.25 if sy<1 else 0),.3),'Metal')
    for i,y in enumerate([-8600,-7600,-6600,-5600]):
        for side,x in [('West',-2390),('East',2390)]:
            add(f'Pier_{side}_{i}',pose(x,y,470,1.2,1.5,9.4),'Stone')
            add(f'PierLight_{side}_{i}',pose(x+(66 if x<0 else -66),y,470,.035,.12,7.2),'Light')
        add(f'RoofRib_{i}',pose(0,y,1000,48,.25,.5),'Metal')
    for side,y in [('South',-9100),('North',-4900)]:
        add('CeilingBand_'+side,pose(0,y,955,48,.6,.45),'Stone')
        add('CeilingLight_'+side,pose(0,y+(35 if side=='South' else -35),932,47,.08,.06),'Light')
    for i in range(24):
        y=-8800+i*155
        add(f'WallSlat_{i}',pose(-2435,y,460,.35,.45,7.8),'Metal')
    for y in [-8950,-5050]:
        add('FloorEdge_'+str(abs(y)),pose(0,y,1.5,46,.045,.025),'Gold','Cube')
    for x in [-2200,2200]:
        add('FloorSide_'+str(x),pose(x,-7000,1.5,.045,38,.025),'Gold','Cube')
    for i,y in enumerate([-8500,-7500,-6500,-5500]):
        accent=['Teal','Gold','Teal','Gold'][i]
        add(f'Gate_{i}',pose(1900,y,14,yaw=90),'Stone','Arch',False,accent)
        add(f'GateBack_{i}',pose(2240,y,290,1.3,6.7,6),'Graphite')
        add(f'GateThreshold_{i}',pose(1840,y,6,7.8,7.4,.12),'Metal','Cube')
        add(f'GateThresholdLight_{i}',pose(1470,y,13,.055,6.4,.035),accent,'Cube')
        for z in [100,300,500]:
            add(f'GateInnerLight_{i}_{z}',pose(2150,y,z,.04,2.8,.045),accent,'Cube')
        add(f'GateHeading_{i}',pose(1880,y,615,.3,7,.9),'Graphite')
    add('WelcomePlinth',pose(-1300,-7000,65,6,7,1.3),'Graphite')
    add('WelcomeTop',pose(-1300,-7000,140,6.2,7.2,.2),'Stone')
    add('WelcomeGlow',pose(-981,-7000,90,.025,6.6,.06),'Teal','Cube')
    add('WelcomeBackdrop',pose(-2250,-7000,480,1,15,5),'Graphite')
    for side,y in [('South',-8950),('North',-5050)]:
        for i,x in enumerate([-1200,0,1200]):
            add(f'Bench_{side}_{i}',pose(x,y,48,8,2,1),'Graphite')
            add(f'BenchSeat_{side}_{i}',pose(x,y,103,8.2,2.2,.16),'Stone')
    return specs

async def main():
    manifest_path=ROOT/'academy-actors.json'
    actors=json.loads(manifest_path.read_text(encoding='utf-8'))
    source_material=MOUNT+'/Art/PCL_M_Master.PCL_M_Master'
    palette={
        'Stone':([.68,.64,.55],[0,0,0]),
        'Floor':([.105,.135,.16],[0,0,0]),
        'Graphite':([.022,.032,.042],[0,0,0]),
        'Metal':([.28,.33,.35],[0,0,0]),
        'Teal':([.015,.4,.43],[.005,.18,.2]),
        'Gold':([.65,.32,.07],[.1,.035,.002]),
        'Light':([.8,.8,.73],[1.6,1.5,1.2]),
    }
    specs=layout()
    async with Client('http://127.0.0.1:8000/mcp',mode='legacy') as c:
        assert (await call(c,'EditorToolset.LevelToolset','GetCurrentLevel',{})).endswith('/ProCoachLab')
        assert await call(c,'ValkyrieFortniteToolset.SessionToolset','GetGameState',{})!='Running'
        materials={}
        for name,(tint,glow) in palette.items():
            asset='PCL_MI_Academy_'+name
            found=await call(c,'EditorToolset.AssetToolset','FindAssets',{'filter':{'folderPath':FOLDER,'name':asset,'maxResults':1}})
            material={'refPath':found[0]} if found else await call(c,'EditorToolset.MaterialInstanceToolset','Create',{'folderPath':FOLDER,'assetName':asset,'parent':{'refPath':source_material}})
            for key,values in [('Tint',tint),('Glow',glow)]:
                await call(c,'EditorToolset.MaterialInstanceToolset','SetVectorParameter',{'instance':material,'name':key,'value':dict(zip(['r','g','b','a'],values+[1]))})
            await call(c,'EditorToolset.AssetToolset','SaveAsset',{'assetPath':material['refPath']})
            materials[name]=material
        shapes={'Block':FOLDER+'/PCL_SM_BevelledBlock.PCL_SM_BevelledBlock','Arch':FOLDER+'/PCL_SM_PortalArch.PCL_SM_PortalArch','Cube':'/Engine/BasicShapes/Cube.Cube'}
        for i,spec in enumerate(specs):
            name=spec['name']
            if name not in actors:
                actors[name]=await call(c,'EditorToolset.LevelToolset','AddToSceneFromAsset',{'assetPath':shapes[spec['shape']],'name':name,'xform':spec['transform']})
                manifest_path.write_text(json.dumps(actors,indent=2),encoding='utf-8')
            else:
                await call(c,'EditorToolset.ActorToolset','SetActorTransform',{'actor':actors[name],'xform':spec['transform']})
            components=await call(c,'EditorToolset.ActorToolset','GetComponents',{'actor':actors[name]})
            mesh=next(x for x in components if x['refPath'].endswith('.StaticMeshComponent0'))
            values={'overrideMaterials':[materials[spec['material']]],'bodyInstance':{'collisionEnabled':'QueryAndPhysics' if spec['collision'] else 'NoCollision'}}
            if spec['accent']:values['overrideMaterials'].append(materials[spec['accent']])
            await call(c,'EditorToolset.ObjectToolset','SetProperties',{'instance':mesh,'values':json.dumps(values)})
            await call(c,'EditorToolset.LevelToolset','SaveActor',{'actor':actors[name]})
            if i%12==0:print('Lobby authored',i+1,'/',len(specs),flush=True)
        for i,(name,label) in enumerate([('PCL_Menu_Personal','מאמן אישי'),('PCL_Menu_Duel','קרב אחד על אחד'),('PCL_Menu_Free','בנייה חופשית'),('PCL_Menu_Edits','אימון עריכות')]):
            await call(c,'EditorToolset.ActorToolset','SetActorTransform',{'actor':actors[name],'xform':pose(1620,-8500+i*1000,90,yaw=180)})
            await call(c,'ValkyrieFortniteToolset.DeviceToolset','SetClassicDeviceOption',{'devicePath':actors[name],'optionName':'Interaction Text','value':label})
            await call(c,'EditorToolset.LevelToolset','SaveActor',{'actor':actors[name]})
        # Reuse the original entry framing rather than leaving overlapping cyan props.
        for name,x,y,z,sx,sy,sz in [('PCL_Hub_Pillar_Left',-500,-9100,400,1.2,1.2,8),('PCL_Hub_Pillar_Right',500,-9100,400,1.2,1.2,8),('PCL_Hub_Beam',0,-9100,840,11.2,1.2,.8)]:
            if name in actors:
                await call(c,'EditorToolset.ActorToolset','SetActorTransform',{'actor':actors[name],'xform':pose(x,y,z,sx,sy,sz)})
                await call(c,'EditorToolset.LevelToolset','SaveActor',{'actor':actors[name]})
        (ROOT.parent/'uefn/academy-layout.json').write_text(json.dumps({'scope':'Authored lobby architecture, not runtime or visual acceptance. Existing mode buttons moved into four physical gateways. Hebrew glyph rendering remains unresolved.','actors':specs,'materials':materials},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        print('Lobby authoring saved:',len(specs),'architectural objects and four mode entrances.',flush=True)

if __name__=='__main__':asyncio.run(main())
