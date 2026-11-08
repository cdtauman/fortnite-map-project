"""Repair the reported Nanite material fallbacks on owned academy assets.

Uses public material-authoring APIs; never starts a session or game.
"""
import asyncio,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'.local'))
from editor_api import long_client,call,ROOT

M='/eda26a53-42c0-4b9e-8f62-31719aef6889'
CODE='''import unreal,json
lib=unreal.MaterialEditingLibrary
usage=unreal.MaterialUsage.MATUSAGE_NANITE
targets=[MOUNT+'/Art/PCL_M_Master.PCL_M_Master']
for name in ['Academy','Duel','EditTraining','FreeBuild','Personal','Return']:
    targets.append(MOUNT+'/Art/AcademySigns/PCL_Sign_'+name+'_Material.PCL_Sign_'+name+'_Material')
materials=[]
record={'scope':'Owned material usage repair; no graph, actor, gameplay or session changes.','materials':[],'effective_usage':[]}
def persist():
    with open(JOURNAL,'w',encoding='utf-8') as stream:json.dump(record,stream,indent=2)
for path in targets:
    obj=unreal.EditorAssetLibrary.load_asset(path)
    if not isinstance(obj,unreal.Material) or not obj.get_path_name().startswith(MOUNT+'/Art/'):
        raise RuntimeError('Expected owned base material: '+path)
    materials.append(obj)
    record['materials'].append({'path':obj.get_path_name(),'before':bool(obj.get_editor_property('used_with_nanite'))})
persist()
with unreal.ScopedEditorTransaction('Enable Nanite usage on academy materials'):
    for obj,row in zip(materials,record['materials']):
        if not row['before']:
            obj.modify()
            lib.set_base_material_usage(obj,usage,True)
            row['compiler']=list(lib.recompile_material(obj))
            persist()
            if row['compiler']:raise RuntimeError('Material compiler diagnostics: '+obj.get_path_name())
        else:row['compiler']=[]
        row['after']=bool(obj.get_editor_property('used_with_nanite'))
        row['effective_usage']=bool(lib.has_material_usage(obj,usage))
        if not row['after'] or not row['effective_usage']:raise RuntimeError('Material usage was not enabled')
        row['saved']=bool(unreal.EditorAssetLibrary.save_loaded_asset(obj,only_if_is_dirty=False))
        persist()
        if not row['saved']:raise RuntimeError('Material save failed: '+obj.get_path_name())
for path in CHECK_PATHS:
    obj=unreal.EditorAssetLibrary.load_asset(path)
    enabled=bool(lib.has_material_usage(obj,usage))
    row={'path':path,'nanite':enabled}
    if isinstance(obj,unreal.MaterialInstanceConstant):row['override']=bool(lib.has_material_usage_override(obj,usage))
    record['effective_usage'].append(row)
persist()
if any(not row['nanite'] for row in record['effective_usage']):raise RuntimeError('A descendant still disables Nanite usage; inspect before changing it')
record['finished']=True
persist()
print(json.dumps(record))
'''

async def main():
    path=ROOT/'material184-authoring.json'
    if path.exists():raise RuntimeError('Existing repair journal: inspect it instead of replaying the batch')
    inspection=json.loads((ROOT/'material184-inspection.json').read_text())
    checks=[m['path'] for m in inspection['materials'] if m.get('root')==M+'/Art/PCL_M_Master.PCL_M_Master' or '/Art/AcademySigns/' in m['path']]
    payload='MOUNT='+repr(M)+'\nJOURNAL='+repr(str(path))+'\nCHECK_PATHS='+repr(checks)+'\n'+CODE
    async with long_client() as c:
        if await call(c,'EditorToolset.LevelToolset','GetCurrentLevel',{})!=M+'/ProCoachLab':raise RuntimeError('Unexpected project')
        if await call(c,'ValkyrieFortniteToolset.SessionToolset','GetGameState',{})=='Running':raise RuntimeError('Do not author during gameplay')
        raw=await call(c,'editor_toolset.toolsets.python_scripting.PythonScriptingTools','execute_python',{'script':{'content':payload,'language':'Python'}})
    record=json.loads(raw.strip())
    print(json.dumps({'changed':sum(not x['before'] for x in record['materials']),'saved':all(x['saved'] for x in record['materials']),'compiler_errors':sum(len(x['compiler']) for x in record['materials']),'effective_usage_readbacks':len(record['effective_usage']),'finished':record.get('finished',False)}),flush=True)

if __name__=='__main__':asyncio.run(main())
