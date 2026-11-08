"""Align the main opponent's authoring configuration with the scripted arena.

Only the spawner's yaw and the owned guard modifier's leash setting change.
No game, upload, source compilation, read-only bypass or construction-gate change.
"""
import asyncio,copy,json,math,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'.local'))
from editor_api import long_client,call,ROOT

M='/eda26a53-42c0-4b9e-8f62-31719aef6889'
def decoded(value):return json.loads(value) if isinstance(value,str) else value

async def main():
    output=ROOT/'opponent169-authoring.json'
    if output.exists():raise RuntimeError('Authoring record already exists; inspect before any continuation')
    actors=json.loads((ROOT/'academy-actors.json').read_text(encoding='utf-8'))
    wiring=json.loads((ROOT/'npc-components169.json').read_text(encoding='utf-8'))
    layout=json.loads((ROOT.parent/'uefn/arena-layout.json').read_text(encoding='utf-8'))
    arena=next(a for a in layout['arenas'] if a['mode']=='Personal')
    player_start=[a+b for a,b in zip(arena['center'],arena['spawn_offset'])]
    spawner=actors['PCL_Coach_NPC_Spawner']
    record={'scope':__doc__,'gameplay_launched':False}
    def persist():output.write_text(json.dumps(record,indent=2),encoding='utf-8')
    async with long_client() as c:
        if await call(c,'EditorToolset.LevelToolset','GetCurrentLevel',{})!=M+'/ProCoachLab':raise RuntimeError('Unexpected level')
        if await call(c,'ValkyrieFortniteToolset.SessionToolset','GetGameState',{})!='Unconnected':raise RuntimeError('Expected disconnected editor')
        definition=decoded(await call(c,'EditorToolset.ObjectToolset','GetProperties',{'instance':wiring['NPCCharacterDefinitionComponent']['ref'],'properties':['nPCCharacterDefinition','nPCCharacterModifiers']}))
        if definition['nPCCharacterDefinition']['refPath']!=M+'/NPC/CoachOpponent.CoachOpponent':raise RuntimeError('The selected definition changed')
        if any('GuardBehavior' in r['refPath'] for r in definition['nPCCharacterModifiers']):raise RuntimeError('Resolve the behavior override before changing its base setting')
        asset=definition['nPCCharacterDefinition']
        actor_def=decoded(await call(c,'EditorToolset.ObjectToolset','GetProperties',{'instance':asset,'properties':['behavior']}))
        modifier=actor_def['behavior']
        if not modifier['refPath'].startswith(asset['refPath']+':'):raise RuntimeError('The modifier is not owned by the selected definition')
        record['script_binding']=decoded(await call(c,'EditorToolset.ObjectToolset','GetProperties',{'instance':wiring['NPCBehaviorScriptComponent']['ref'],'properties':['nPCBehaviorScript']}))
        if '.coach_opponent_behavior_' not in record['script_binding']['nPCBehaviorScript']['refPath']:raise RuntimeError('Unexpected assigned behavior script')
        record['before']={'transform':await call(c,'EditorToolset.ActorToolset','GetActorTransform',{'actor':spawner}),'behavior':decoded(await call(c,'EditorToolset.ObjectToolset','GetProperties',{'instance':modifier,'properties':['bEnableLeash','leashDistance','accuracy','bCanBeDownButNotOut']}))}
        target=copy.deepcopy(record['before']['transform']);p=target['location']
        target['rotation']['yaw']=math.degrees(math.atan2(player_start[1]-p['y'],player_start[0]-p['x']))
        record['target_transform']=target;record['definition']=asset;record['modifier']=modifier;persist()
        await call(c,'EditorToolset.ActorToolset','SetActorTransform',{'actor':spawner,'xform':target,'bWorldSpace':True})
        record['pose_authored']=True;persist()
        await call(c,'EditorToolset.ObjectToolset','SetProperties',{'instance':modifier,'values':json.dumps({'bEnableLeash':False})})
        record['leash_authored']=True;persist()
        record['after']={'transform':await call(c,'EditorToolset.ActorToolset','GetActorTransform',{'actor':spawner}),'behavior':decoded(await call(c,'EditorToolset.ObjectToolset','GetProperties',{'instance':modifier,'properties':['bEnableLeash','leashDistance','accuracy','bCanBeDownButNotOut']}))}
        actual=record['after']
        if abs((actual['transform']['rotation']['yaw']-target['rotation']['yaw']+180)%360-180)>.1 or actual['behavior']['bEnableLeash'] is not False:raise RuntimeError('Configuration readback differs')
        for name in ['leashDistance','accuracy','bCanBeDownButNotOut']:
            if actual['behavior'][name]!=record['before']['behavior'][name]:raise RuntimeError('An unrelated behavior setting changed')
        await call(c,'EditorToolset.AssetToolset','SaveAsset',{'assetPath':asset['refPath']})
        await call(c,'EditorToolset.LevelToolset','SaveActor',{'actor':spawner})
        record['saved_definition_and_actor']=True;persist()
    (ROOT.parent/'uefn/opponent-setup.json').write_text(json.dumps({'scope':'Editor configuration evidence, not runtime behavior or pro-quality acceptance.','spawner':spawner,'definition':asset,'script_binding':record['script_binding'],'transform':record['after']['transform'],'guard_settings':record['after']['behavior'],'movement_authority':'Scripted arena targets and action cancellation; native guard leash disabled.','restoration_record':'.local/opponent169-authoring.json'},indent=2),encoding='utf-8')
    print(json.dumps({'yaw':record['after']['transform']['rotation']['yaw'],'guard_settings':record['after']['behavior'],'saved_definition_and_actor':record['saved_definition_and_actor']}),flush=True)

if __name__=='__main__':asyncio.run(main())
