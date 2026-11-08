"""Extend the owned academy perimeter kit to the three other training modes.

Public editor authoring only. No gameplay, fixture activation or source compilation.
"""
import asyncio,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'.local'))
from editor_api import long_client,call,ROOT
from author_personal_environment import layout,SCRIPT,MOUNT,FOLDER

async def main():
    output=ROOT/'training-perimeters177-authoring.json'
    if output.exists():raise RuntimeError('Authoring record exists; inspect current actors before continuation')
    modes=['Duel','FreeBuild','EditTraining']
    parts=[p for mode in modes for p in layout(mode)]
    actor_path=ROOT/'academy-actors.json';actors=json.loads(actor_path.read_text(encoding='utf-8'))
    if any(p['name'] in actors for p in parts):raise RuntimeError('Some target actor names already exist')
    materials=json.loads((ROOT.parent/'uefn/academy-layout.json').read_text(encoding='utf-8'))['materials']
    record={'scope':__doc__,'gameplay_launched':False,'actors':[],'groups':[]}
    def persist():output.write_text(json.dumps(record,indent=2),encoding='utf-8')
    persist()
    async with long_client() as c:
        for mode in modes:
            for side in ['N','S','E','W']:
                group=[p for p in parts if p['mode']==mode and p['side']==side]
                payload='MOUNT='+repr(MOUNT)+'\nFOLDER='+repr(FOLDER)+'\nMATERIALS='+repr(materials)+'\nPARTS='+repr(group)+'\n'+SCRIPT
                result=await call(c,'editor_toolset.toolsets.programmatic.ProgrammaticToolset','execute_tool_script',{'script':{'content':payload,'language':'Python'}})
                if isinstance(result,str):result=json.loads(result)
                rows=result['actors'];record['actors']+=rows
                record['groups'].append({'mode':mode,'side':side,'count':len(rows)})
                for r in rows:actors[r['name']]=r['actor']
                actor_path.write_text(json.dumps(actors,indent=2),encoding='utf-8');persist()
                print(mode+' perimeter side saved: '+side,flush=True)
        expected={p['name']:materials[p['material']]['refPath'] for p in parts}
        code='''import unreal,json
rows=[]
for row in ROWS:
    actor=unreal.load_object(None,row['actor']['refPath'])
    component=unreal.load_object(None,row['component']['refPath'])
    if actor is None or component is None:raise RuntimeError('Authored actor/component missing')
    collision=component.get_editor_property('body_instance').get_editor_property('collision_enabled')
    if collision!=unreal.CollisionEnabled.NO_COLLISION:raise RuntimeError('Decorative collision setting differs')
    material=component.get_material(0).get_path_name()
    if material!=EXPECTED[row['name']]:raise RuntimeError('Unexpected material: '+row['name'])
    rows.append({'name':row['name'],'material':material,'collision':str(collision)})
print(json.dumps({'actors':rows,'save':unreal.EditorLoadingAndSavingUtils.save_dirty_packages(True,True)}))
'''
        result=await call(c,'editor_toolset.toolsets.python_scripting.PythonScriptingTools','execute_python',{'script':{'content':'ROWS='+repr(record['actors'])+'\nEXPECTED='+repr(expected)+'\n'+code,'language':'Python'}})
        record['readback']=json.loads(result);persist()
    path=ROOT.parent/'uefn/training-perimeter-layout.json'
    path.write_text(json.dumps({'scope':'Editor-authored decorative perimeter kit; client quality/navigation/performance acceptance pending.','parts':parts,'counts':{mode:sum(p['mode']==mode for p in parts) for mode in modes},'record':'.local/training-perimeters177-authoring.json','policy':'No gameplay boundary changes or new center obstacles. All added components configured NoCollision and no cast shadows.'},ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'authored':len(record['actors']),'readback':len(record['readback']['actors']),'save':record['readback']['save']}),flush=True)

if __name__=='__main__':asyncio.run(main())
