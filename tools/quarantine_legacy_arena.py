"""Reversibly isolate explicitly inventoried old personal-arena or lobby pieces.

No actor/source deletion, gameplay or session operation. --restore returns the
same actors to their archived transforms and actor-level visibility/collision.
"""
import argparse,asyncio,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'.local'))
from editor_api import long_client,call,ROOT

M='/eda26a53-42c0-4b9e-8f62-31719aef6889'

async def main(restore,lobby=False,balconies=False):
    manifest_name='legacy-personal-balconies-quarantine.json' if balconies else 'legacy-lobby-quarantine.json' if lobby else 'legacy-personal-quarantine.json'
    record_prefix='balconies173' if balconies else 'lobby165' if lobby else 'legacy161'
    archive_y=(-60000,-54000) if balconies else (-48000,-42000) if lobby else (-30000,-25000)
    manifest=json.loads((ROOT.parent/'uefn'/manifest_name).read_text(encoding='utf-8'))
    actors=manifest['actors']
    record={'scope':'Reversible legacy actor transform/visibility/collision authoring only; no gameplay or deletion.','restore':restore,'steps':[],'gameplay_launched':False}
    path=ROOT/(record_prefix+('-restoration.json' if restore else '-authoring.json'))
    if path.exists():record['previous_attempts']=[json.loads(path.read_text(encoding='utf-8'))]
    def persist():path.write_text(json.dumps(record,indent=2),encoding='utf-8')
    for row in actors:
        p=row['quarantine']['location']
        if not row['label'].startswith('PBWA_') or not row['actor']['refPath'].startswith(M+'/ProCoachLab.ProCoachLab:PersistentLevel.'):
            raise RuntimeError('Unexpected actor identity in the manifest')
        if abs(p['x'])>4096 or not archive_y[0]<=p['y']<=archive_y[1]:
            raise RuntimeError('Target is outside the named archive strip')
    async with long_client() as c:
        level=await call(c,'EditorToolset.LevelToolset','GetCurrentLevel',{})
        state=await call(c,'ValkyrieFortniteToolset.SessionToolset','GetGameState',{})
        if level!=M+'/ProCoachLab' or state!='Unconnected':raise RuntimeError('Open ProCoachLab with the session disconnected before authoring')
        layer=json.loads((ROOT.parent/'uefn/course-runtime.json').read_text(encoding='utf-8'))['layer']['refPath']
        protected=await call(c,'EditorToolset.LevelToolset','GetActorsInDataLayer',{'assetPath':layer})
        protected_paths={x['actorPath'] for x in protected}
        if any(row['actor']['refPath'] in protected_paths for row in actors):raise RuntimeError('A legacy candidate belongs to the active course')
        preflight='ROWS='+repr(actors)+'''\nimport unreal,json
objects=[]
for row in ROWS:
    actor=unreal.load_object(None,row['actor']['refPath'])
    if actor is None or actor.get_actor_label()!=row['label'] or actor.get_class().get_path_name()!=row['class']:raise RuntimeError('Actor identity changed')
    if actor.get_attach_parent_actor() is not None or list(actor.get_editor_property('data_layer_assets')):raise RuntimeError('Protected attachment or layer membership')
    p=actor.get_actor_location()
    def near(pose):return abs(p.x-pose['location']['x'])<0.1 and abs(p.y-pose['location']['y'])<0.1 and abs(p.z-pose['location']['z'])<0.1
    if not near(row['original']) and not near(row['quarantine']):raise RuntimeError('Actor moved since inspection; do not overwrite newer work')
    objects.append(actor)
print(json.dumps({'identities_confirmed':len(objects)}))
'''
        record['preflight']=await call(c,'editor_toolset.toolsets.python_scripting.PythonScriptingTools','execute_python',{'script':{'content':preflight,'language':'Python'}})
        persist()
        flag_code='ROWS='+repr(actors)+'\nRESTORE='+repr(restore)+'''\nimport unreal,json
changed=[]
for row in ROWS:
    actor=unreal.load_object(None,row['actor']['refPath'])
    actor.modify()
    actor.set_actor_hidden_in_game(row['original_hidden'] if RESTORE else True)
    actor.set_actor_enable_collision(row['original_collision_enabled'] if RESTORE else False)
    changed.append(row['actor']['refPath'])
print(json.dumps({'flags_authored':len(changed)}))
'''
        record['flags']=await call(c,'editor_toolset.toolsets.python_scripting.PythonScriptingTools','execute_python',{'script':{'content':flag_code,'language':'Python'}})
        persist()
        for row in actors:
            target=row['original' if restore else 'quarantine']
            await call(c,'EditorToolset.ActorToolset','SetActorTransform',{'actor':row['actor'],'xform':target,'bWorldSpace':True})
            record['steps'].append({'label':row['label'],'target':target});persist()
        readback='ROWS='+repr(actors)+'\nRESTORE='+repr(restore)+'''\nimport unreal,json
rows=[]
for row in ROWS:
    actor=unreal.load_object(None,row['actor']['refPath']);p=actor.get_actor_location()
    target=row['original' if RESTORE else 'quarantine']['location']
    hidden=actor.get_editor_property('hidden');collision=actor.get_actor_enable_collision()
    if abs(p.x-target['x'])>0.1 or abs(p.y-target['y'])>0.1 or abs(p.z-target['z'])>0.1:raise RuntimeError('Authored transform did not match')
    if hidden!=(row['original_hidden'] if RESTORE else True) or collision!=(row['original_collision_enabled'] if RESTORE else False):raise RuntimeError('Authored flags did not match')
    rows.append({'label':row['label'],'location':[p.x,p.y,p.z],'hidden':hidden,'collision_enabled':collision})
print(json.dumps(rows))
'''
        record['readback']=json.loads(await call(c,'editor_toolset.toolsets.python_scripting.PythonScriptingTools','execute_python',{'script':{'content':readback,'language':'Python'}}))
        record['save']=await call(c,'editor_toolset.toolsets.python_scripting.PythonScriptingTools','execute_python',{'script':{'content':'import unreal\nprint(unreal.EditorLoadingAndSavingUtils.save_dirty_packages(True,True))','language':'Python'}})
        record['protected_course_count']=len(protected_paths);persist()
    print(json.dumps({'authored':len(record['readback']),'restore':restore,'course_members_protected':record['protected_course_count'],'save':record['save']}),flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--restore',action='store_true')
    group=parser.add_mutually_exclusive_group()
    group.add_argument('--lobby',action='store_true',help='Use the separately inventoried lobby manifest and archive strip')
    group.add_argument('--balconies',action='store_true',help='Use the separately inventoried three personal-arena balconies')
    args=parser.parse_args()
    asyncio.run(main(args.restore,args.lobby,args.balconies))
