"""Import authored signs and place them on the academy's portal and return panels."""
import asyncio,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'.local'))
from editor_api import Client,call
from build_academy_scene import pose,MOUNT,FOLDER

def sign_placements(layout):
    specs=[]
    for index,mode in enumerate(['Personal','Duel','FreeBuild','EditTraining']):
        specs.append(('PCL_Wayfinding_Gate_'+mode,'PCL_Sign_'+mode,pose(1440,-8500+index*1000,500,6,1,3,90)))
    for arena in layout['arenas']:
        x,y,z=arena['center'];half=arena['half_extent']
        specs.append(('PCL_Wayfinding_Return_'+arena['mode'],'PCL_Sign_Return',pose(x-half+95,y,z+220,3,1,1.5,-90)))
    specs.append(('PCL_Wayfinding_Academy','PCL_Sign_Academy',pose(-2195,-7000,480,9,1,4.5,-90)))
    specs.append(('PCL_Wayfinding_Overview','PCL_Sign_Academy',pose(0,-4850,520,14,1,7,180)))
    return specs

async def main():
    source=ROOT/'uefn/Art/AcademySigns'
    signs=json.loads((source/'signs.json').read_text(encoding='utf-8'))
    path=ROOT/'.local/academy-signs-authored.json'
    ledger=json.loads(path.read_text()) if path.exists() else {'textures':{},'materials':{},'panels':{}}
    actors_path=ROOT/'.local/academy-actors.json';actors=json.loads(actors_path.read_text())
    layout=json.loads((ROOT/'uefn/arena-layout.json').read_text(encoding='utf-8'))
    def save():
        path.write_text(json.dumps(ledger,indent=2),encoding='utf-8')
        actors_path.write_text(json.dumps(actors,indent=2),encoding='utf-8')
    async with Client('http://127.0.0.1:8000/mcp',mode='legacy') as c:
        for sign in signs:
            name=sign['name'];mode=sign['mode']
            if name not in ledger['textures']:
                refs=await call(c,'EditorToolset.TextureToolset','ImportFile',{'folderPath':MOUNT+'/Art/AcademySigns','assetName':name,'sourceFile':str((source/sign['file']).resolve())})
                texture=refs[0]
                await call(c,'EditorToolset.ObjectToolset','SetProperties',{'instance':texture,'values':json.dumps({'lodGroup':'TEXTUREGROUP_UI','compressionSettings':'TC_EditorIcon','mipGenSettings':'TMGS_NoMipmaps'})})
                await call(c,'EditorToolset.AssetToolset','SaveAsset',{'assetPath':texture['refPath']})
                ledger['textures'][name]=texture;save()
            if name not in ledger['materials']:
                material=await call(c,'EditorToolset.MaterialToolset','CreateMaterial',{'folderPath':MOUNT+'/Art/AcademySigns','assetName':name+'_Material'})
                await call(c,'EditorToolset.ObjectToolset','SetProperties',{'instance':material,'values':json.dumps({'shadingModel':'MSM_Unlit','twoSided':True})})
                classes=await call(c,'EditorToolset.MaterialToolset','ListExpressionClasses',{'materialOrFunction':material,'search':'TextureSample'})
                cls=next(x for x in classes if x['refPath'].endswith('.MaterialExpressionTextureSample'))
                node=await call(c,'EditorToolset.MaterialToolset','AddExpression',{'materialOrFunction':material,'expressionClass':cls,'x':-300,'y':0})
                await call(c,'EditorToolset.ObjectToolset','SetProperties',{'instance':node,'values':json.dumps({'texture':ledger['textures'][name]})})
                await call(c,'EditorToolset.MaterialToolset','ConnectToOutput',{'expression':node,'outputName':'RGB','materialProperty':'MP_EmissiveColor'})
                await call(c,'EditorToolset.MaterialToolset','Recompile',{'materialOrFunction':material})
                await call(c,'EditorToolset.AssetToolset','SaveAsset',{'assetPath':material['refPath']})
                ledger['materials'][name]=material;save()
        specs=sign_placements(layout)
        for label,material_key,xform in specs:
            if label in ledger['panels']:
                await call(c,'EditorToolset.ActorToolset','SetActorTransform',{'actor':actors[label],'xform':xform})
                await call(c,'EditorToolset.LevelToolset','SaveActor',{'actor':actors[label]})
                continue
            if label not in actors:
                actors[label]=await call(c,'EditorToolset.LevelToolset','AddToSceneFromAsset',{'assetPath':FOLDER+'/PCL_SM_HorizonPanel.PCL_SM_HorizonPanel','name':label,'xform':xform});save()
            components=await call(c,'EditorToolset.ActorToolset','GetComponents',{'actor':actors[label]})
            mesh=next(x for x in components if x['refPath'].endswith('.StaticMeshComponent0'))
            await call(c,'EditorToolset.ObjectToolset','SetProperties',{'instance':mesh,'values':json.dumps({'overrideMaterials':[ledger['materials'][material_key]],'castShadow':False,'bodyInstance':{'collisionEnabled':'NoCollision'}})})
            await call(c,'EditorToolset.LevelToolset','SaveActor',{'actor':actors[label]})
            ledger['panels'][label]=actors[label];save()
        for label,text in [('PCL_Menu_Personal','מאמן אישי'),('PCL_Menu_Duel','אחד על אחד'),('PCL_Menu_Free','בנייה חופשית'),('PCL_Menu_Edits','אימון עריכות')]:
            await call(c,'ValkyrieFortniteToolset.DeviceToolset','SetClassicDeviceOption',{'devicePath':actors[label],'optionName':'Interaction Text','value':text})
            await call(c,'EditorToolset.LevelToolset','SaveActor',{'actor':actors[label]})
    print('Placed bilingual wayfinding panels',len(ledger['panels']),'no gameplay launched',flush=True)

if __name__=='__main__':asyncio.run(main())
