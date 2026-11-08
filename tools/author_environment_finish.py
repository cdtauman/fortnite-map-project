"""Prepare academy surface detail, ceiling architecture and local lighting.

Uses public editor authoring APIs only. Does not launch a session or game.
"""
import asyncio,json,sys
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'.local'))
from editor_api import long_client,call,ROOT
from build_academy_scene import MOUNT,FOLDER,pose


def ceiling_layout():
    parts=[]
    def add(name,xform,material):
        parts.append({'name':'PCL_Finish_'+name,'transform':xform,'material':material})
    # Shallow panels stay above the existing 932 cm light bands and gate headings.
    for i,y in enumerate([-8500,-7500,-6500,-5500]):
        add('CeilingInset_'+str(i),pose(0,y,1036,45,8.6,.24),'Graphite')
        for j,x in enumerate([-1500,-500,500,1500]):
            add('CeilingBaffle_'+str(i)+'_'+str(j),pose(x,y,1008,.12,8.2,.38),'Metal')
        for j,x in enumerate([-1050,1050]):
            add('CeilingPanel_'+str(i)+'_'+str(j),pose(x,y,1018,4.2,.7,.12),'Light')
        # A recessed mode-colour spine connects each entrance to its ceiling bay.
        add('GateCanopy_'+str(i),pose(1820,y,710,7.4,7.4,.20),'Graphite')
        add('GateCanopyEdge_'+str(i),pose(1450,y,700,.045,6.6,.045),'Teal' if i%2==0 else 'Gold')
    # West wall framing gives the welcome sign a deliberate focal plane.
    for name,x,y,z,sx,sy,sz,mat in [
        ('WelcomeFrameTop',-2220,-7000,760,.25,16,.22,'Metal'),
        ('WelcomeFrameBottom',-2220,-7000,200,.25,16,.22,'Metal'),
        ('WelcomeFrameLeft',-2220,-7800,480,.25,.22,5.6,'Metal'),
        ('WelcomeFrameRight',-2220,-6200,480,.25,.22,5.6,'Metal'),
        ('WelcomeLine',-2202,-7000,735,.04,14.5,.04,'Teal'),
    ]:
        add(name,pose(x,y,z,sx,sy,sz),mat)
    return parts


MATERIAL_CODE='''import unreal,json
folder=FOLDER
lib=unreal.MaterialEditingLibrary
asset_tools=unreal.AssetToolsHelpers.get_asset_tools()
path=folder+'/PCL_M_ArchitecturalFloor'
material=unreal.EditorAssetLibrary.load_asset(path)
if material is None:
    material=asset_tools.create_asset('PCL_M_ArchitecturalFloor',folder,unreal.Material,unreal.MaterialFactoryNew())
if material is None:raise RuntimeError('Floor material creation did not return an asset')
lib.delete_all_material_expressions(material)
def node(cls,x,y,**props):
    n=lib.create_material_expression(material,cls,x,y)
    if n is None:raise RuntimeError('Material expression creation failed: '+str(cls))
    for k,v in props.items():n.set_editor_property(k,v)
    return n
def wire(a,b,pin='',output=''):
    if not lib.connect_material_expressions(a,output,b,pin):raise RuntimeError('Material connection failed: '+pin)
world=node(unreal.MaterialExpressionWorldPosition,-1400,0)
spacing=node(unreal.MaterialExpressionScalarParameter,-1400,200,parameter_name='TileSizeCm',default_value=512.0)
divide=node(unreal.MaterialExpressionDivide,-1200,0)
wire(world,divide,'A');wire(spacing,divide,'B')
fraction=node(unreal.MaterialExpressionFrac,-1050,0);wire(divide,fraction)
center=node(unreal.MaterialExpressionSubtract,-900,0,const_b=.5);wire(fraction,center,'A')
absolute=node(unreal.MaterialExpressionAbs,-750,0);wire(center,absolute)
x=node(unreal.MaterialExpressionComponentMask,-600,-50,r=True,g=False,b=False,a=False)
y=node(unreal.MaterialExpressionComponentMask,-600,100,r=False,g=True,b=False,a=False)
wire(absolute,x);wire(absolute,y)
maximum=node(unreal.MaterialExpressionMax,-450,0);wire(x,maximum,'A');wire(y,maximum,'B')
edge=node(unreal.MaterialExpressionSubtract,-300,0,const_b=.496);wire(maximum,edge,'A')
gain=node(unreal.MaterialExpressionMultiply,-150,0,const_b=250.0);wire(edge,gain,'A')
clamp=node(unreal.MaterialExpressionClamp,0,0,min_default=0.0,max_default=1.0);wire(gain,clamp)
tile=node(unreal.MaterialExpressionVectorParameter,-150,250,parameter_name='TileTint',default_value=unreal.LinearColor(.12,.16,.20,1))
seam=node(unreal.MaterialExpressionVectorParameter,-150,400,parameter_name='SeamTint',default_value=unreal.LinearColor(.055,.075,.095,1))
blend=node(unreal.MaterialExpressionLinearInterpolate,200,200)
wire(tile,blend,'A',output='RGB');wire(seam,blend,'B',output='RGB');wire(clamp,blend,'Alpha')
rough=node(unreal.MaterialExpressionConstant,200,400,r=.82)
ambient=node(unreal.MaterialExpressionMultiply,400,100,const_b=.12);wire(blend,ambient,'A')
for expr,prop in [(blend,unreal.MaterialProperty.MP_BASE_COLOR),(rough,unreal.MaterialProperty.MP_ROUGHNESS),(ambient,unreal.MaterialProperty.MP_EMISSIVE_COLOR)]:
    if not lib.connect_material_property(expr,'',prop):raise RuntimeError('Material output connection failed')
lib.layout_material_expressions(material)
lib.recompile_material(material)
instances={}
for name,size,tint,seam_tint in [
    ('Lobby',256.0,(.22,.25,.28,1),(.08,.105,.13,1)),
    ('Training',512.0,(.105,.145,.19,1),(.065,.095,.13,1)),
]:
    asset_name='PCL_MI_Floor_'+name
    instance=unreal.EditorAssetLibrary.load_asset(folder+'/'+asset_name)
    if instance is None:instance=asset_tools.create_asset(asset_name,folder,unreal.MaterialInstanceConstant,unreal.MaterialInstanceConstantFactoryNew())
    lib.set_material_instance_parent(instance,material)
    lib.set_material_instance_scalar_parameter_value(instance,'TileSizeCm',size)
    lib.set_material_instance_vector_parameter_value(instance,'TileTint',unreal.LinearColor(*tint))
    lib.set_material_instance_vector_parameter_value(instance,'SeamTint',unreal.LinearColor(*seam_tint))
    instances[name]=instance
actors=unreal.get_editor_subsystem(unreal.EditorActorSubsystem).get_all_level_actors()
changed=[]
for actor in actors:
    label=actor.get_actor_label()
    if label=='PCL_Academy_Foundation':selected=instances['Lobby']
    elif label.startswith('PCL_Environment_') and label.endswith('_Foundation'):selected=instances['Training']
    else:continue
    actor.modify()
    for component in actor.get_components_by_class(unreal.StaticMeshComponent):
        component.modify();component.set_material(0,selected)
    changed.append(label)
print(json.dumps({'material':material.get_path_name(),'instances':{k:v.get_path_name() for k,v in instances.items()},'floors':changed}))
'''


LIGHT_CODE='''import unreal,json
sub=unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
actors={a.get_actor_label():a for a in sub.get_all_level_actors()}
authored=[]
for i,y in enumerate([-8500,-7500,-6500,-5500]):
    for j,x in enumerate([-1050,1050]):
        label='PCL_Finish_LobbyLight_'+str(i)+'_'+str(j)
        a=actors.get(label)
        if a is None:a=sub.spawn_actor_from_class(unreal.SpotLight,unreal.Vector(x,y,975),unreal.Rotator(-90,0,0))
        if a is None:raise RuntimeError('Spot light creation failed: '+label)
        a.set_actor_label(label)
        a.modify()
        light=a.get_component_by_class(unreal.SpotLightComponent)
        light.modify()
        light.set_mobility(unreal.ComponentMobility.MOVABLE)
        light.set_intensity_units(unreal.LightUnits.LUMENS)
        light.set_intensity(3200.0)
        light.set_light_color(unreal.LinearColor(1,.94,.84,1))
        light.set_attenuation_radius(1600.0)
        light.set_inner_cone_angle(48.0)
        light.set_outer_cone_angle(68.0)
        light.set_cast_shadows(False)
        light.set_editor_property('volumetric_scattering_intensity',0.0)
        authored.append({'label':label,'path':a.get_path_name(),'lumens':3200,'radius_cm':1600,'shadows':False})
print(json.dumps({'lights':authored}))
'''


async def main():
    parts=ceiling_layout()
    output=ROOT/'environment146-authoring.json'
    record=json.loads(output.read_text()) if output.exists() else {'geometry':{}}
    async with long_client() as c:
        level=await call(c,'EditorToolset.LevelToolset','GetCurrentLevel',{})
        if level!=MOUNT+'/ProCoachLab':raise RuntimeError('Open project is not ProCoachLab')
        state=await call(c,'ValkyrieFortniteToolset.SessionToolset','GetGameState',{})
        if state=='Running':raise RuntimeError('Stop the game before authoring')
        if not record.get('materials'):
            record['materials']=await call(c,'editor_toolset.toolsets.python_scripting.PythonScriptingTools','execute_python',{'script':{'content':'FOLDER='+repr(FOLDER)+'\n'+MATERIAL_CODE,'language':'Python'}})
            output.write_text(json.dumps(record,indent=2),encoding='utf-8')
            print('Architectural floor materials assigned',flush=True)
        actors_path=ROOT/'academy-actors.json'
        actors=json.loads(actors_path.read_text())
        materials=json.loads((ROOT.parent/'uefn/academy-layout.json').read_text(encoding='utf-8'))['materials']
        for i,part in enumerate(parts):
            name=part['name']
            if name in record['geometry']:continue
            if name not in actors:
                actors[name]=await call(c,'EditorToolset.LevelToolset','AddToSceneFromAsset',{'assetPath':FOLDER+'/PCL_SM_BevelledBlock.PCL_SM_BevelledBlock','name':name,'xform':part['transform']})
                actors_path.write_text(json.dumps(actors,indent=2),encoding='utf-8')
            else:await call(c,'EditorToolset.ActorToolset','SetActorTransform',{'actor':actors[name],'xform':part['transform']})
            components=await call(c,'EditorToolset.ActorToolset','GetComponents',{'actor':actors[name]})
            mesh=next(x for x in components if x['refPath'].endswith('.StaticMeshComponent0'))
            await call(c,'EditorToolset.ObjectToolset','SetProperties',{'instance':mesh,'values':json.dumps({'overrideMaterials':[materials[part['material']]],'castShadow':False,'bodyInstance':{'collisionEnabled':'NoCollision'}})})
            await call(c,'EditorToolset.LevelToolset','SaveActor',{'actor':actors[name]})
            record['geometry'][name]=actors[name]
            output.write_text(json.dumps(record,indent=2),encoding='utf-8')
            if i%10==0:print('Ceiling and entrance architecture',i+1,'/',len(parts),flush=True)
        if not record.get('lights'):
            record['lights']=await call(c,'editor_toolset.toolsets.python_scripting.PythonScriptingTools','execute_python',{'script':{'content':LIGHT_CODE,'language':'Python'}})
        record['save']=await call(c,'editor_toolset.toolsets.python_scripting.PythonScriptingTools','execute_python',{'script':{'content':'import unreal\nprint(unreal.EditorLoadingAndSavingUtils.save_dirty_packages(True,True))','language':'Python'}})
        record['gameplay_launched']=False
        output.write_text(json.dumps(record,indent=2),encoding='utf-8')
    (ROOT.parent/'uefn/environment-finish-layout.json').write_text(json.dumps({'scope':'Editor-authored surfaces and lobby architecture; final client quality and performance pending.','parts':parts,'lighting':{'count':8,'type':'SpotLight','lumens':3200,'radius_cm':1600,'shadows':False},'material':{'path':FOLDER+'/PCL_M_ArchitecturalFloor','world_aligned':True,'lobby_tile_cm':256,'training_tile_cm':512},'sources':['https://dev.epicgames.com/documentation/fortnite/talisman-environment-template-in-unreal-editor-for-fortnite','https://dev.epicgames.com/documentation/fortnite/environment-light-rig-device-in-unreal-editor-for-fortnite']},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'parts_saved':len(record['geometry']),'floors':record['materials'],'lights':record.get('lights'),'save':record.get('save')}),flush=True)

if __name__=='__main__':asyncio.run(main())
