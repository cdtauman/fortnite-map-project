"""Re-import the academy sign PNGs over the existing Texture2D assets and switch the lobby
button prompts to English (spec v1: English UI by default). Editor authoring only; no game.

Usage: python tools/update_sign_textures.py [--prompts-only]
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sync_verse import call, ROOT

MOUNT = "/eda26a53-42c0-4b9e-8f62-31719aef6889"
SIGNS = os.path.join(ROOT, "uefn", "Art", "AcademySigns")
PROMPTS = [("PCL_Menu_Personal", "Personal Coach"), ("PCL_Menu_Duel", "1V1 Arena"),
           ("PCL_Menu_Free", "Free Build"), ("PCL_Menu_Edits", "Edit Training")]


def main():
    if "--prompts-only" not in sys.argv:
        # TextureToolset.ImportFile refuses existing assets, so reimport through editor Python
        # (AssetImportTask with replace_existing) from an ASCII staging folder.
        import shutil
        os.makedirs(r"C:/tmp/pcl_signs", exist_ok=True)
        for sign in json.load(open(os.path.join(SIGNS, "signs.json"), encoding="utf-8")):
            shutil.copy(os.path.join(SIGNS, sign["file"]), r"C:/tmp/pcl_signs/" + sign["file"])
        script = open(os.path.join(ROOT, "tools", "reimport_sign_textures_editor.py"), encoding="utf-8").read()
        print(call("editor_toolset.toolsets.python_scripting.PythonScriptingTools", "execute_python",
                   {"script": {"content": script, "language": "Python"}}))
    actors = json.load(open(os.path.join(ROOT, ".local", "academy-actors.json"), encoding="utf-8"))
    for label, text in PROMPTS:
        call("ValkyrieFortniteToolset.DeviceToolset", "SetClassicDeviceOption",
             {"devicePath": actors[label], "optionName": "Interaction Text", "value": text})
        call("EditorToolset.LevelToolset", "SaveActor", {"actor": actors[label]})
        print(label, "prompt ->", text)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
