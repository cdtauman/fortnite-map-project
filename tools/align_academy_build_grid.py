"""Align the authored arenas and course lanes to the island's 512 cm build grid.

Editor transforms only. Does not start a session or test gameplay.
"""
import asyncio,copy,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'.local'))
from editor_api import long_client,call
from author_academy_signs import sign_placements

def mode_for(label):
    for mode,short,sign in [('Duel','Duel','Duel'),('FreeBuild','Free','Free'),('EditTraining','Edit','Edits')]:
        if label.startswith(('PCL_'+short+'_','PCL_Trim_'+short+'_','PCL_Environment_'+mode+'_','PCL_ResetNetwork_'+mode+'_')) or label in ['PCL_Sign_'+sign,'PCL_Return_'+mode]:return mode
    if label.startswith(('PCL_Triple_','PCL_Course_')):return 'EditTraining'
    return None

async def batch(c,script):
    result=await call(c,'editor_toolset.toolsets.programmatic.ProgrammaticToolset','execute_tool_script',{'script':{'content':script,'language':'Python'}})
    return json.loads(result) if isinstance(result,str) else result

async def main():
    path=ROOT/'.local/arena-grid-alignment141.json'
    if path.exists():
        record=json.loads(path.read_text())
        if record.get('complete'):
            print('Grid alignment already authored; no repeat performed.');return
    else:
        layout=json.loads((ROOT/'uefn/arena-layout.json').read_text(encoding='utf-8'))
        updated=copy.deepcopy(layout)
        before={a['mode']:a['center'] for a in layout['arenas']}
        for arena in updated['arenas']:
            arena['center']=[round(v/step)*step for v,step in zip(arena['center'],[512,512,384])]
        updated['build_grid']={'x':512,'y':512,'z':384}
        updated['layout_revision']=2
        record={'before_centers':before,'layout':updated,'complete':False}
        path.write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
    layout=record['layout'];after={a['mode']:a['center'] for a in layout['arenas']}
    course=json.loads((ROOT/'uefn/course-layout.json').read_text(encoding='utf-8'))
    course_labels={x['label'] for group in ['pieces','triple_corridor'] for x in course.get(group,[])}
    async with long_client() as c:
        if 'moves' not in record:
            script='''import json
async def find_actors():
    return (await execute_tool('EditorToolset.LevelToolset.FindActors',json.dumps({'filter':{'name':'PCL_'}})))['returnValue']
async def get_pose(actor):
    return (await execute_tool('EditorToolset.ActorToolset.GetActorTransform',json.dumps({'actor':actor})))['returnValue']
async def run():
    result=[]
    for actor in await find_actors():
        label=actor['label']
        if any(label.startswith(prefix) for prefix in PREFIXES) or label in LABELS:
            ref={'refPath':actor['actorPath']}
            result.append({'label':label,'actor':ref,'before':await get_pose(ref)})
    return {'actors':result}
'''
            prefixes=['PCL_Duel_','PCL_Free_','PCL_Edit_','PCL_Triple_','PCL_Course_','PCL_Trim_Duel_','PCL_Trim_Free_','PCL_Trim_Edit_','PCL_Environment_Duel_','PCL_Environment_FreeBuild_','PCL_Environment_EditTraining_','PCL_ResetNetwork_Duel_','PCL_ResetNetwork_FreeBuild_']
            signs={label:pose for label,_,pose in sign_placements(layout)}
            data=await batch(c,'PREFIXES='+repr(prefixes)+'\nLABELS='+repr(list(signs)+['PCL_Sign_Duel','PCL_Sign_Free','PCL_Sign_Edits','PCL_Return_Duel','PCL_Return_FreeBuild','PCL_Return_EditTraining'])+'\n'+script)
            moves=[]
            for item in data['actors']:
                label=item['label'];new=copy.deepcopy(item['before'])
                if label in signs:new=signs[label]
                elif mode:=mode_for(label):
                    delta=[a-b for a,b in zip(after[mode],record['before_centers'][mode])]
                    for axis,difference in zip('xyz',delta):new['location'][axis]+=difference
                    if label in course_labels:new['location']['x']+=168
                else:continue
                if new!=item['before']:
                    moves.append(dict(item,after=new))
            record['moves']=moves
            path.write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
        script='''import json
async def set_pose(actor, pose):
    return await execute_tool('EditorToolset.ActorToolset.SetActorTransform',json.dumps({'actor':actor,'xform':pose}))
async def save_actor(actor):
    return await execute_tool('EditorToolset.LevelToolset.SaveActor',json.dumps({'actor':actor}))
async def run():
    for move in MOVES:
        await set_pose(move['actor'],move['after'])
        await save_actor(move['actor'])
    return {'authored':len(MOVES),'gameplay_launched':False}
'''
        record['applied']=await batch(c,'MOVES='+repr(record['moves'])+'\n'+script)
    # Keep the source authoring recipes and their cached world-space data aligned.
    for spec in layout.get('authored_environments',[]):
        mode=mode_for(spec['name'])
        if mode:
            for axis,a,b in zip('xyz',after[mode],record['before_centers'][mode]):spec['transform']['location'][axis]+=a-b
    for arena in layout['arenas']:arena['authored_center']=list(arena['center'])
    (ROOT/'uefn/arena-layout.json').write_text(json.dumps(layout,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for group in ['pieces','triple_corridor']:
        for piece in course.get(group,[]):
            piece['transform']['location']['x']+=after['EditTraining'][0]-record['before_centers']['EditTraining'][0]+168
    course['origin_center']=after['EditTraining']
    (ROOT/'uefn/course-layout.json').write_text(json.dumps(course,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    record['complete']=True
    path.write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'moved_and_saved':len(record['moves']),'centers':after,'gameplay_launched':False}),flush=True)

if __name__=='__main__':asyncio.run(main())
