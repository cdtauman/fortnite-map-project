"""Runs inside the editor (execute_python), spec v1 step 4.1.
Creates PCL_M_Hologram (translucent unlit cyan) and PCL_BP_Holo{Wall,Floor,Ramp,Cone}
as duplicates of the owned TeachingKit demo pieces with NoCollision and the hologram material,
so scene queries only ever see the player's real build pieces. Idempotent."""
FOLDER = "/eda26a53-42c0-4b9e-8f62-31719aef6889/Art/TeachingKit"
MAT = FOLDER + "/PCL_M_Hologram"
EAL = unreal.EditorAssetLibrary
MEL = unreal.MaterialEditingLibrary

if not EAL.does_asset_exist(MAT):
    tools = unreal.AssetToolsHelpers.get_asset_tools()
    mat = tools.create_asset("PCL_M_Hologram", FOLDER, unreal.Material, unreal.MaterialFactoryNew())
    mat.set_editor_property("blend_mode", unreal.BlendMode.BLEND_TRANSLUCENT)
    mat.set_editor_property("shading_model", unreal.MaterialShadingModel.MSM_UNLIT)
    mat.set_editor_property("two_sided", True)
    color = MEL.create_material_expression(mat, unreal.MaterialExpressionConstant3Vector, -400, 0)
    color.set_editor_property("constant", unreal.LinearColor(0.15, 0.95, 1.0, 1.0))
    glow = MEL.create_material_expression(mat, unreal.MaterialExpressionMultiply, -200, 0)
    boost = MEL.create_material_expression(mat, unreal.MaterialExpressionConstant, -400, 120)
    boost.set_editor_property("r", 3.0)
    MEL.connect_material_expressions(color, "", glow, "A")
    MEL.connect_material_expressions(boost, "", glow, "B")
    MEL.connect_material_property(glow, "", unreal.MaterialProperty.MP_EMISSIVE_COLOR)
    opacity = MEL.create_material_expression(mat, unreal.MaterialExpressionConstant, -400, 240)
    opacity.set_editor_property("r", 0.35)
    MEL.connect_material_property(opacity, "", unreal.MaterialProperty.MP_OPACITY)
    MEL.recompile_material(mat)
    EAL.save_asset(MAT)
    print("created material")
mat = EAL.load_asset(MAT)

subs = unreal.get_engine_subsystem(unreal.SubobjectDataSubsystem)
for kind in ["Wall", "Floor", "Ramp", "Cone"]:
    src = FOLDER + "/PCL_BP_Demo" + kind
    dst = FOLDER + "/PCL_BP_Holo" + kind
    if not EAL.does_asset_exist(dst):
        EAL.duplicate_asset(src, dst)
    bp = EAL.load_asset(dst)
    for handle in subs.k2_gather_subobject_data_for_blueprint(bp):
        data = unreal.SubobjectDataBlueprintFunctionLibrary.get_data(handle)
        comp = unreal.SubobjectDataBlueprintFunctionLibrary.get_object(data)
        if isinstance(comp, unreal.StaticMeshComponent) and comp.static_mesh:
            comp.set_collision_profile_name("NoCollision")
            comp.set_collision_enabled(unreal.CollisionEnabled.NO_COLLISION)
            comp.set_editor_property("cast_shadow", False)
            mats = comp.get_materials()
            comp.set_editor_property("override_materials", [mat for _ in mats])
            print(kind, comp.static_mesh.get_name(), comp.get_collision_enabled(), len(mats))
    unreal.BlueprintEditorLibrary.compile_blueprint(bp)
    EAL.save_asset(dst)
print("done")
