"""Sent to the editor's execute_python by tools/update_sign_textures.py: reimports the sign
PNGs from C:/tmp/pcl_signs over the existing Texture2D assets (replace_existing)."""
names = ["PCL_Sign_Personal", "PCL_Sign_Duel", "PCL_Sign_FreeBuild", "PCL_Sign_EditTraining",
         "PCL_Sign_Return", "PCL_Sign_Academy"]
folder = "/eda26a53-42c0-4b9e-8f62-31719aef6889/Art/AcademySigns"
tasks = []
for name in names:
    task = unreal.AssetImportTask()
    task.filename = "C:/tmp/pcl_signs/" + name + ".png"
    task.destination_path = folder
    task.destination_name = name
    task.replace_existing = True
    task.replace_existing_settings = False
    task.automated = True
    task.save = True
    tasks.append(task)
unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks(tasks)
for task in tasks:
    print(task.destination_name, list(task.imported_object_paths))
for name in names:
    tex = unreal.EditorAssetLibrary.load_asset(folder + "/" + name)
    print(name, tex.blueprint_get_size_x(), tex.blueprint_get_size_y(), tex.get_editor_property("lod_group"))
