"""Author the lobby sign hierarchy using existing owned artwork, without gameplay."""
import argparse,asyncio,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'.local'))
from editor_api import long_client,call,ROOT
from author_academy_signs import sign_placements
from build_academy_scene import MOUNT,FOLDER

def text_source(value):
    for wrapper in ['NSLOCTEXT','LOCTEXT']:
        if value.startswith(wrapper+'(') and value.endswith(')'):
            fields=json.loads('['+value[len(wrapper)+1:-1]+']')
            if len(fields)!=(3 if wrapper=='NSLOCTEXT' else 2) or not all(isinstance(x,str) for x in fields):raise RuntimeError('Unexpected localized text representation')
            return fields[-1]
    return value

async def readback_and_save(c,record,actors,specs,prompts):
    record['transforms']={}
    for label,material,target in specs:
        actual=await call(c,'EditorToolset.ActorToolset','GetActorTransform',{'actor':actors[label]})
        for group in ['location','rotation','scale']:
            for axis,expected in target[group].items():
                delta=actual[group][axis]-expected
                if group=='rotation':delta=(delta+180)%360-180
                if abs(delta)>0.1:raise RuntimeError('Sign transform differs from the authored target')
        record['transforms'][label]=actual
    record['prompts']={};record['prompt_sources']={}
    for label,text in prompts:
        options=await call(c,'ValkyrieFortniteToolset.DeviceToolset','ListClassicDeviceOptions',{'devicePath':actors[label]})
        option=next(o for o in options if o['name']==record['before'][label]['option'])
        record['prompts'][label]=option['currentValue']
        record['prompt_sources'][label]=text_source(option['currentValue'])
        if record['prompt_sources'][label]!=text:raise RuntimeError('Interaction text source differs')
    record['save']=await call(c,'editor_toolset.toolsets.python_scripting.PythonScriptingTools','execute_python',{'script':{'content':'import unreal\nprint(unreal.EditorLoadingAndSavingUtils.save_dirty_packages(True,True))','language':'Python'}})

def save_layout(specs,prompts):
    (ROOT.parent/'uefn/lobby-wayfinding.json').write_text(json.dumps({'scope':'Prepared sign hierarchy; final gameplay appearance and native prompt Hebrew rendering unverified.','panels':[{'name':n,'material':m,'transform':p} for n,m,p in specs],'prompts':dict(prompts),'restoration_record':'.local/wayfinding166-authoring.json'},ensure_ascii=False,indent=2),encoding='utf-8')

async def main():
    actors_path=ROOT/'academy-actors.json'
    signs_path=ROOT/'academy-signs-authored.json'
    actors=json.loads(actors_path.read_text(encoding='utf-8'))
    signs=json.loads(signs_path.read_text(encoding='utf-8'))
    layout=json.loads((ROOT.parent/'uefn/arena-layout.json').read_text(encoding='utf-8'))
    specs=[x for x in sign_placements(layout) if x[0].startswith('PCL_Wayfinding_Gate_') or x[0]=='PCL_Wayfinding_Overview']
    prompts=[('PCL_Menu_Personal','מאמן אישי'),('PCL_Menu_Duel','אחד על אחד'),('PCL_Menu_Free','בנייה חופשית'),('PCL_Menu_Edits','אימון עריכות')]
    path=ROOT/'wayfinding166-authoring.json'
    if path.exists():raise RuntimeError('Existing authoring record: inspect its state before retrying')
    record={'scope':'Lobby sign placement and Hebrew interaction text authoring only, using existing owned textures. No game/session/upload, input or final visual acceptance.','before':{},'steps':[],'gameplay_launched':False}
    def persist():path.write_text(json.dumps(record,indent=2,ensure_ascii=False),encoding='utf-8')
    async with long_client() as c:
        if await call(c,'EditorToolset.LevelToolset','GetCurrentLevel',{})!=MOUNT+'/ProCoachLab':raise RuntimeError('Unexpected level')
        if await call(c,'ValkyrieFortniteToolset.SessionToolset','GetGameState',{})!='Unconnected':raise RuntimeError('Expected disconnected editor')
        for label,material,target in specs:
            if label in actors:
                record['before'][label]={'actor':actors[label],'transform':await call(c,'EditorToolset.ActorToolset','GetActorTransform',{'actor':actors[label]})}
        option_names={}
        for label,text in prompts:
            options=await call(c,'ValkyrieFortniteToolset.DeviceToolset','ListClassicDeviceOptions',{'devicePath':actors[label]})
            option=next(o for o in options if o['displayName']=='Interaction Text' or o['name']=='Interaction Text')
            if not option['bIsActive'] or (option['maxLength'] and len(text)>option['maxLength']):raise RuntimeError('Interaction option is not ready')
            option_names[label]=option['name']
            record['before'][label]={'actor':actors[label],'option':option['name'],'value':option['currentValue']}
        persist()
        for label,material,target in specs:
            if label not in actors:
                actors[label]=await call(c,'EditorToolset.LevelToolset','AddToSceneFromAsset',{'assetPath':FOLDER+'/PCL_SM_HorizonPanel.PCL_SM_HorizonPanel','name':label,'xform':target})
                actors_path.write_text(json.dumps(actors,indent=2),encoding='utf-8')
                record['steps'].append({'label':label,'created':actors[label]});persist()
                components=await call(c,'EditorToolset.ActorToolset','GetComponents',{'actor':actors[label]})
                mesh=next(x for x in components if x['refPath'].endswith('.StaticMeshComponent0'))
                await call(c,'EditorToolset.ObjectToolset','SetProperties',{'instance':mesh,'values':json.dumps({'overrideMaterials':[signs['materials'][material]],'castShadow':False,'bodyInstance':{'collisionEnabled':'NoCollision'}})})
            else:
                await call(c,'EditorToolset.ActorToolset','SetActorTransform',{'actor':actors[label],'xform':target,'bWorldSpace':True})
            signs['panels'][label]=actors[label]
            signs_path.write_text(json.dumps(signs,indent=2),encoding='utf-8')
            record['steps'].append({'label':label,'target':target});persist()
        for label,text in prompts:
            await call(c,'ValkyrieFortniteToolset.DeviceToolset','SetClassicDeviceOption',{'devicePath':actors[label],'optionName':option_names[label],'value':text})
            record['steps'].append({'label':label,'interaction_text':text});persist()
        await readback_and_save(c,record,actors,specs,prompts)
        persist()
    save_layout(specs,prompts)
    print(json.dumps({'panels':len(specs),'prompts':record['prompts'],'save':record['save']},ensure_ascii=False),flush=True)

async def finish():
    path=ROOT/'wayfinding166-authoring.json'
    record=json.loads(path.read_text(encoding='utf-8'))
    if record.get('save'):raise RuntimeError('Authoring is already saved; do not repeat')
    actors=json.loads((ROOT/'academy-actors.json').read_text(encoding='utf-8'))
    layout=json.loads((ROOT.parent/'uefn/arena-layout.json').read_text(encoding='utf-8'))
    specs=[x for x in sign_placements(layout) if x[0].startswith('PCL_Wayfinding_Gate_') or x[0]=='PCL_Wayfinding_Overview']
    prompts=[(x['label'],x['interaction_text']) for x in record['steps'] if 'interaction_text' in x]
    if len(prompts)!=4 or not all(any(s.get('label')==n and s.get('target')==p for s in record['steps']) for n,m,p in specs):raise RuntimeError('Authoring did not reach the expected completion point')
    async with long_client() as c:
        if await call(c,'EditorToolset.LevelToolset','GetCurrentLevel',{})!=MOUNT+'/ProCoachLab':raise RuntimeError('Unexpected level')
        if await call(c,'ValkyrieFortniteToolset.SessionToolset','GetGameState',{})!='Unconnected':raise RuntimeError('Expected disconnected editor')
        await readback_and_save(c,record,actors,specs,prompts)
    record['readback_note']='Initial literal comparison stopped on NSLOCTEXT serialization. Completion decoded its source string and read existing authored state; placements/options were not repeated.'
    path.write_text(json.dumps(record,indent=2,ensure_ascii=False),encoding='utf-8')
    save_layout(specs,prompts)
    print(json.dumps({'panels':len(specs),'prompt_sources':record['prompt_sources'],'save':record['save']},ensure_ascii=False),flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--finish',action='store_true',help='Read back and save the existing166 authoring, without repeating mutations')
    asyncio.run(finish() if parser.parse_args().finish else main())
