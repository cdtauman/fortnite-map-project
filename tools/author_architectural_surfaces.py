"""Import the owned stone surface and assign academy/arena finish materials.

Uses public editor authoring APIs. No session, upload or game is started.
"""
import asyncio,hashlib,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'.local'))
from editor_api import long_client,call,ROOT

M='/eda26a53-42c0-4b9e-8f62-31719aef6889'
FOLDER=M+'/Art/ArchitecturalSurfaces'
SOURCE=ROOT.parent/'uefn/Art/ArchitecturalSurfaces/PCL_T_StoneAlbedo_1024_v1.png'

AUTHOR_CODE='''import unreal,json
lib=unreal.MaterialEditingLibrary
tools=unreal.AssetToolsHelpers.get_asset_tools()
unreal.EditorAssetLibrary.make_directory(FOLDER)
texture=unreal.EditorAssetLibrary.load_asset(TEXTURE_PATH)
if texture is None:raise RuntimeError('Imported texture is not available')
texture.modify()
texture.set_editor_property('lod_group',unreal.TextureGroup.TEXTUREGROUP_WORLD)
texture.set_editor_property('compression_settings',unreal.TextureCompressionSettings.TC_DEFAULT)
texture.set_editor_property('max_texture_size',1024)
texture.set_editor_property('mip_gen_settings',unreal.TextureMipGenSettings.TMGS_FROM_TEXTURE_GROUP)
texture.set_editor_property('never_stream',False)
texture.set_editor_property('srgb',True)
texture.set_editor_property('address_x',unreal.TextureAddress.TA_WRAP)
texture.set_editor_property('address_y',unreal.TextureAddress.TA_WRAP)
name='PCL_M_ArchitecturalStone'
material=unreal.EditorAssetLibrary.load_asset(FOLDER+'/'+name)
if material is None:material=tools.create_asset(name,FOLDER,unreal.Material,unreal.MaterialFactoryNew())
if material is None:raise RuntimeError('Stone material was not created')
lib.delete_all_material_expressions(material)
def node(cls,x,y,**properties):
    item=lib.create_material_expression(material,cls,x,y)
    if item is None:raise RuntimeError('Material expression was not created')
    for key,value in properties.items():item.set_editor_property(key,value)
    return item
def wire(source,destination,pin='',output=''):
    if not lib.connect_material_expressions(source,output,destination,pin):raise RuntimeError('Material connection rejected: '+pin)
def mask(x,y,r=False,g=False,b=False):
    return node(unreal.MaterialExpressionComponentMask,x,y,r=r,g=g,b=b,a=False)
world=node(unreal.MaterialExpressionWorldPosition,-1500,0)
scale=node(unreal.MaterialExpressionScalarParameter,-1500,180,parameter_name='TileSizeCm',default_value=256.0)
coords=node(unreal.MaterialExpressionDivide,-1300,0)
wire(world,coords,'A');wire(scale,coords,'B')
normal=node(unreal.MaterialExpressionPixelNormalWS,-1500,600)
absolute=node(unreal.MaterialExpressionAbs,-1300,600);wire(normal,absolute)
weights=[];terms=[]
for index,(uv_channels,weight_channels) in enumerate([
    ({'g':True,'b':True},{'r':True}),
    ({'r':True,'b':True},{'g':True}),
    ({'r':True,'g':True},{'b':True}),
]):
    uv=mask(-1100,index*200,**uv_channels);wire(coords,uv)
    weight=mask(-1100,700+index*150,**weight_channels);wire(absolute,weight)
    sample=node(unreal.MaterialExpressionTextureSample,-850,index*200,texture=texture)
    wire(uv,sample,'UVs')
    term=node(unreal.MaterialExpressionMultiply,-600,index*200)
    wire(sample,term,'A',output='RGB');wire(weight,term,'B')
    weights.append(weight);terms.append(term)
def sum_three(items,x,y):
    first=node(unreal.MaterialExpressionAdd,x,y);wire(items[0],first,'A');wire(items[1],first,'B')
    result=node(unreal.MaterialExpressionAdd,x+150,y);wire(first,result,'A');wire(items[2],result,'B')
    return result
colour=sum_three(terms,-400,200)
weight_total=sum_three(weights,-400,650)
blend=node(unreal.MaterialExpressionDivide,0,200);wire(colour,blend,'A');wire(weight_total,blend,'B')
tint=node(unreal.MaterialExpressionVectorParameter,0,450,parameter_name='Tint',default_value=unreal.LinearColor(.90,.94,.97,1))
base=node(unreal.MaterialExpressionMultiply,200,200);wire(blend,base,'A');wire(tint,base,'B',output='RGB')
rough=node(unreal.MaterialExpressionScalarParameter,200,500,parameter_name='Roughness',default_value=.82)
ambient=node(unreal.MaterialExpressionMultiply,400,100,const_b=.04);wire(base,ambient,'A')
for expression,prop in [(base,unreal.MaterialProperty.MP_BASE_COLOR),(rough,unreal.MaterialProperty.MP_ROUGHNESS),(ambient,unreal.MaterialProperty.MP_EMISSIVE_COLOR)]:
    if not lib.connect_material_property(expression,'',prop):raise RuntimeError('Material output connection rejected')
lib.layout_material_expressions(material)
instance_name='PCL_MI_Stone_Lobby'
instance=unreal.EditorAssetLibrary.load_asset(FOLDER+'/'+instance_name)
if instance is None:instance=tools.create_asset(instance_name,FOLDER,unreal.MaterialInstanceConstant,unreal.MaterialInstanceConstantFactoryNew())
lib.set_material_instance_parent(instance,material)
lib.set_material_instance_scalar_parameter_value(instance,'TileSizeCm',256.0)
old_stone=MOUNT+'/Art/AcademyKit/PCL_MI_Academy_Stone.PCL_MI_Academy_Stone'
lobby_floor=unreal.EditorAssetLibrary.load_asset(MOUNT+'/Art/AcademyKit/PCL_MI_Floor_Lobby')
training_floor=unreal.EditorAssetLibrary.load_asset(MOUNT+'/Art/AcademyKit/PCL_MI_Floor_Training')
if lobby_floor is None or training_floor is None:raise RuntimeError('Architectural floor materials are missing')
platforms={'PCL_Hub_Platform','PCL_Personal_Platform','PCL_Duel_Platform','PCL_Free_Platform','PCL_Edit_Platform','PCL_Lesson_One_Platform','PCL_Lesson_Two_Platform'}
assignments=[]
for actor in unreal.get_editor_subsystem(unreal.EditorActorSubsystem).get_all_level_actors():
    label=actor.get_actor_label()
    if not label.startswith(('PCL_Academy_','PCL_Finish_')) and label not in platforms:continue
    for component in actor.get_components_by_class(unreal.StaticMeshComponent):
        for slot,old in enumerate(component.get_materials()):
            chosen=None
            if label in platforms:chosen=lobby_floor if label=='PCL_Hub_Platform' else training_floor
            elif old is not None and old.get_path_name()==old_stone:chosen=instance
            if chosen is None:continue
            actor.modify();component.modify()
            assignments.append({'label':label,'component':component.get_path_name(),'slot':slot,'before':old.get_path_name() if old else None,'after':chosen.get_path_name()})
            component.set_material(slot,chosen)
print(json.dumps({'material':material.get_path_name(),'instance':instance.get_path_name(),'texture':texture.get_path_name(),'texture_settings':{'power_of_two_mode':str(texture.get_editor_property('power_of_two_mode')),'max_texture_size':texture.get_editor_property('max_texture_size'),'never_stream':texture.get_editor_property('never_stream'),'mip_gen_settings':str(texture.get_editor_property('mip_gen_settings'))},'assignments':assignments}))
'''

async def main():
    path=ROOT/'stone153-authoring.json'
    record={'scope':'Owned texture/material and visible floor material authoring only; no gameplay/session/upload/probe.','source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'gameplay_launched':False}
    async with long_client() as c:
        level=await call(c,'EditorToolset.LevelToolset','GetCurrentLevel',{})
        state=await call(c,'ValkyrieFortniteToolset.SessionToolset','GetGameState',{})
        if level!=M+'/ProCoachLab' or state=='Running':raise RuntimeError('Open ProCoachLab with the game stopped before authoring')
        await call(c,'editor_toolset.toolsets.python_scripting.PythonScriptingTools','execute_python',{'script':{'content':'import unreal\nprint(unreal.EditorAssetLibrary.make_directory('+repr(FOLDER)+'))','language':'Python'}})
        found=await call(c,'EditorToolset.AssetToolset','FindAssets',{'filter':{'folderPath':FOLDER,'name':'PCL_T_StoneAlbedo_v1','maxResults':1}})
        if found:texture={'refPath':found[0]}
        else:
            imported=await call(c,'EditorToolset.TextureToolset','ImportFile',{'folderPath':FOLDER,'assetName':'PCL_T_StoneAlbedo_v1','sourceFile':str(SOURCE.resolve())})
            texture=imported[0]
        record['texture']=texture
        path.write_text(json.dumps(record,indent=2),encoding='utf-8')
        code='FOLDER='+repr(FOLDER)+'\nTEXTURE_PATH='+repr(texture['refPath'])+'\nMOUNT='+repr(M)+'\n'+AUTHOR_CODE
        result=await call(c,'editor_toolset.toolsets.python_scripting.PythonScriptingTools','execute_python',{'script':{'content':code,'language':'Python'}})
        record['authoring']=json.loads(result)
        path.write_text(json.dumps(record,indent=2),encoding='utf-8')
        record['material_recompile']=await call(c,'EditorToolset.MaterialToolset','Recompile',{'materialOrFunction':{'refPath':record['authoring']['material']}})
        record['save']=await call(c,'editor_toolset.toolsets.python_scripting.PythonScriptingTools','execute_python',{'script':{'content':'import unreal\nprint(unreal.EditorLoadingAndSavingUtils.save_dirty_packages(True,True))','language':'Python'}})
        path.write_text(json.dumps(record,indent=2),encoding='utf-8')
    assignments=record['authoring']['assignments']
    print(json.dumps({'surfaces_assigned':len(assignments),'platforms':[x['label'] for x in assignments if x['label'].endswith('_Platform')],'texture_settings':record['authoring']['texture_settings'],'material_recompile':record['material_recompile'],'save':record['save']}),flush=True)

if __name__=='__main__':asyncio.run(main())
