"""Author separated training spaces and migrate the existing course and devices."""
import asyncio,copy,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'.local'))
from editor_api import Client,call,ROOT
from build_academy_scene import pose,MOUNT,FOLDER

async def horizon_material(c):
    path=FOLDER+'/PCL_M_Horizon'
    found=await call(c,'EditorToolset.AssetToolset','FindAssets',{'filter':{'folderPath':FOLDER,'name':'PCL_M_Horizon','maxResults':1}})
    material={'refPath':found[0]} if found else await call(c,'EditorToolset.MaterialToolset','CreateMaterial',{'folderPath':FOLDER,'assetName':'PCL_M_Horizon'})
    if (ROOT/'recovery138-horizon-ready.json').exists():return material
    await call(c,'EditorToolset.ObjectToolset','SetProperties',{'instance':material,'values':json.dumps({'shadingModel':'MSM_Unlit'})})
    nodes={}
    existing=await call(c,'EditorToolset.MaterialToolset','GetExpressions',{'materialOrFunction':material})
    for i,(name,kind) in enumerate([('uv','TextureCoordinate'),('height','ComponentMask'),('low','VectorParameter'),('high','VectorParameter'),('blend','LinearInterpolate')]):
        suffix='MaterialExpression'+kind+('_1' if name=='high' else '_0')
        reused=next((x for x in existing if x['refPath'].endswith(':'+suffix)),None)
        if reused:
            nodes[name]=reused
            continue
        classes=await call(c,'EditorToolset.MaterialToolset','ListExpressionClasses',{'materialOrFunction':material,'search':kind})
        cls=next(x for x in classes if x['refPath'].endswith('.MaterialExpression'+kind))
        nodes[name]=await call(c,'EditorToolset.MaterialToolset','AddExpression',{'materialOrFunction':material,'expressionClass':cls,'x':-800+i*160,'y':0})
    await call(c,'EditorToolset.ObjectToolset','SetProperties',{'instance':nodes['height'],'values':json.dumps({'r':False,'g':True,'b':False,'a':False})})
    for name,param,color in [('low','HorizonLow',[.28,.38,.45]),('high','HorizonHigh',[.045,.16,.26])]:
        await call(c,'EditorToolset.ObjectToolset','SetProperties',{'instance':nodes[name],'values':json.dumps({'parameterName':param,'defaultValue':dict(zip(['r','g','b','a'],color+[1]))})})
    for a,b,pin in [('uv','height','None'),('height','blend','Alpha'),('low','blend','A'),('high','blend','B')]:
        await call(c,'EditorToolset.MaterialToolset','ConnectExpressions',{'fromExpression':nodes[a],'fromOutputName':'RGB' if a in ['low','high'] else '', 'toExpression':nodes[b],'toInputName':pin})
    await call(c,'EditorToolset.MaterialToolset','ConnectToOutput',{'expression':nodes['blend'],'outputName':'','materialProperty':'MP_EmissiveColor'})
    await call(c,'EditorToolset.MaterialToolset','LayoutExpressions',{'materialOrFunction':material})
    await call(c,'EditorToolset.MaterialToolset','Recompile',{'materialOrFunction':material})
    await call(c,'EditorToolset.AssetToolset','SaveAsset',{'assetPath':material['refPath']})
    (ROOT/'recovery138-horizon-ready.json').write_text(json.dumps({'material':material,'nodes':nodes},indent=2),encoding='utf-8')
    return material

def role(label):
    if label.startswith(('PCL_Duel_','PCL_Trim_Duel_')) or label=='PCL_Sign_Duel':return 'Duel'
    if label.startswith(('PCL_Free_','PCL_Trim_Free_')) or label=='PCL_Sign_Free':return 'FreeBuild'
    if label.startswith(('PCL_Edit_','PCL_Triple_','PCL_Course_','PCL_Trim_Edit_')) or label=='PCL_Sign_Edits':return 'EditTraining'
    return None

async def main():
    layout_path=ROOT.parent/'uefn/arena-layout.json'
    layout=json.loads(layout_path.read_text(encoding='utf-8'))
    actors_path=ROOT/'academy-actors.json';actors=json.loads(actors_path.read_text())
    materials=json.loads((ROOT.parent/'uefn/academy-layout.json').read_text(encoding='utf-8'))['materials']
    ledger_path=ROOT/'recovery138-arena-migration.json'
    ledger=json.loads(ledger_path.read_text()) if ledger_path.exists() else {'moved':{},'authored':{}}
    def save():ledger_path.write_text(json.dumps(ledger,indent=2)+'\n',encoding='utf-8')
    arenas={x['mode']:x for x in layout['arenas']}
    async with Client('http://127.0.0.1:8000/mcp',mode='legacy') as c:
        assert await call(c,'ValkyrieFortniteToolset.SessionToolset','GetGameState',{})!='Running'
        horizon=await horizon_material(c)
        materials['Horizon']=horizon
        # Ambient material response keeps the architecture legible without a dense light rig.
        for name,color in [('Stone',[.10,.09,.075]),('Metal',[.025,.03,.035]),('Teal',[.01,1.6,1.8]),('Gold',[.6,.19,.012])]:
            await call(c,'EditorToolset.MaterialInstanceToolset','SetVectorParameter',{'instance':materials[name],'name':'Glow','value':dict(zip(['r','g','b','a'],color+[1]))})
            await call(c,'EditorToolset.AssetToolset','SaveAsset',{'assetPath':materials[name]['refPath']})
        extra_roles={}
        raw=await call(c,'ValkyrieFortniteToolset.DeviceToolset','GetDeviceProperties',{'device':actors['PCL_Portal_Director'],'propertyNames':['DuelReset','DuelResetUpper','FreeReset','FreeResetUpper','EditReset','EditResetUpper']})
        props=json.loads(raw) if isinstance(raw,str) else raw
        for field,ref in props.items():
            if ref and ref.get('refPath'):
                extra_roles[ref['refPath']]='Duel' if field.startswith('Duel') else 'FreeBuild' if field.startswith('Free') else 'EditTraining'
        for label,actor in list(actors.items()):
            mode=extra_roles.get(actor['refPath']) or role(label)
            if not mode:continue
            prior=ledger['moved'].get(label)
            desc=arenas[mode]
            applied_center=(prior or {}).get('target_center',desc.get('authored_center',desc['previous_center']))
            if prior and prior['saved'] and applied_center==desc['center']:continue
            if prior and not prior['saved'] and prior.get('target_center')==desc['center']:
                old,new=prior['old'],prior['new']
            else:
                old=await call(c,'EditorToolset.ActorToolset','GetActorTransform',{'actor':actor})
                new=copy.deepcopy(old)
                for axis,index in zip('xyz',range(3)):
                    new['location'][axis]+=desc['center'][index]-applied_center[index]
            ledger['moved'][label]={'actor':actor,'old':old,'new':new,'mode':mode,'target_center':desc['center'],'saved':False};save()
            await call(c,'EditorToolset.ActorToolset','SetActorTransform',{'actor':actor,'xform':new})
            await call(c,'EditorToolset.LevelToolset','SaveActor',{'actor':actor})
            ledger['moved'][label]['saved']=True;save()
        specs=[]
        spaces=[dict(name=a['mode'],center=a['center'],half=a['half_extent'],height=layout['enclosure_top'],accent=a['accent']) for a in layout['arenas']]
        spaces += [dict(name=a['name'],center=a['center'],half=a['half_extent'],height=a['height'],accent='Teal') for a in layout['teaching_bays']]
        for space in spaces:
            name=space['name'];cx,cy,cz=space['center'];h=space['half'];top=space['height'];span=2*h+200
            def add(suffix,xform,mat,shape='Cube',collision=False):
                specs.append(dict(name='PCL_Environment_'+name+'_'+suffix,transform=xform,material=mat,shape=shape,collision=collision))
            add('Foundation',pose(cx,cy,cz-50,span/100,span/100,1),'Floor',collision=True)
            add('Ceiling',pose(cx,cy,cz+top+50,span/100,span/100,1),'Horizon',collision=True)
            for side,x,y,sx,sy,yaw in [('N',cx,cy+h+50,span/100,1,0),('S',cx,cy-h-50,span/100,1,0),('E',cx+h+50,cy,1,span/100,90),('W',cx-h-50,cy,1,span/100,90)]:
                add('Boundary_'+side,pose(x,y,cz+top/2,sx,sy,top/100),'Graphite',collision=True)
                px=x+(66 if side=='W' else -66 if side=='E' else 0)
                py=y+(66 if side=='S' else -66 if side=='N' else 0)
                add('Backdrop_'+side,pose(px,py,cz+top/2,(span-100)/100,1,top/100,yaw),'Horizon','Panel')
                add('LowBand_'+side,pose(x,y,cz+140,sx,sy,2.8),'Metal','Block')
                add('LightBand_'+side,pose(px,py,cz+220,sx if side in ['N','S'] else .04,sy if side in ['E','W'] else .04,.045),space['accent'])
            for x in [-h+240,h-240]:
                add('FloorSide_'+str(x),pose(cx+x,cy,cz+1.2,.04,(2*h-480)/100,.025),space['accent'])
            for y in [-h+240,h-240]:
                add('FloorEnd_'+str(y),pose(cx,cy+y,cz+1.2,(2*h-480)/100,.04,.025),space['accent'])
            if name=='FreeBuild':
                for i in range(-15,16):
                    add('GridX_'+str(i),pose(cx+i*512,cy,cz+.5,.015,155,.01),'Metal')
                    add('GridY_'+str(i),pose(cx,cy+i*512,cz+.5,155,.015,.01),'Metal')
            if name=='Duel':
                for i,x in enumerate([-512,512]):
                    add('StartMark_'+str(i),pose(cx+x,cy,cz+1.5,4,4,.02),space['accent'])
        meshes={'Cube':'/Engine/BasicShapes/Cube.Cube','Block':FOLDER+'/PCL_SM_BevelledBlock.PCL_SM_BevelledBlock','Panel':FOLDER+'/PCL_SM_HorizonPanel.PCL_SM_HorizonPanel'}
        for i,spec in enumerate(specs):
            name=spec['name']
            if name not in actors:
                actors[name]=await call(c,'EditorToolset.LevelToolset','AddToSceneFromAsset',{'assetPath':meshes[spec['shape']],'name':name,'xform':spec['transform']})
                actors_path.write_text(json.dumps(actors,indent=2),encoding='utf-8')
            else:await call(c,'EditorToolset.ActorToolset','SetActorTransform',{'actor':actors[name],'xform':spec['transform']})
            comps=await call(c,'EditorToolset.ActorToolset','GetComponents',{'actor':actors[name]})
            mesh=next(x for x in comps if x['refPath'].endswith('.StaticMeshComponent0'))
            props={'overrideMaterials':[materials[spec['material']]],'castShadow':False,'bodyInstance':{'collisionEnabled':'QueryAndPhysics' if spec['collision'] else 'NoCollision'}}
            await call(c,'EditorToolset.ObjectToolset','SetProperties',{'instance':mesh,'values':json.dumps(props)})
            await call(c,'EditorToolset.LevelToolset','SaveActor',{'actor':actors[name]})
            ledger['authored'][name]=actors[name];save()
            if i%20==0:print('Training environments authored',i+1,'/',len(specs),flush=True)
        layout['authored_environments']=specs
        layout['environment_materials']=materials
        for arena in layout['arenas']:arena['authored_center']=list(arena['center'])
        layout_path.write_text(json.dumps(layout,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        course_path=ROOT.parent/'uefn/course-layout.json'
        course=json.loads(course_path.read_text(encoding='utf-8-sig'))
        if course.get('origin_center')!=arenas['EditTraining']['center']:
            dx=arenas['EditTraining']['center'][0]-course.get('origin_center',arenas['EditTraining']['previous_center'])[0]
            for group in ['pieces','triple_corridor']:
                for part in course.get(group,[]):part['transform']['location']['x']+=dx
            course['origin_center']=arenas['EditTraining']['center']
            course_path.write_text(json.dumps(course,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        print('Four separated modes and two teaching rooms authored; no game session started.',flush=True)

if __name__=='__main__':asyncio.run(main())
