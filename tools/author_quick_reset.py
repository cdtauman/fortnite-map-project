"""Author the free-build quick-reset input trigger (spec v1 step 2.5). Editor authoring only.
Places one Input Trigger on Place Marker (Custom 13), HUD text "Reset builds", registered
players only, and wires coach_portal_device.QuickResetInput / QuickResetConfigured.
Idempotent via .local/quick-reset-authoring.json."""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sync_verse import call, ROOT

PORTAL = {"refPath": "/eda26a53-42c0-4b9e-8f62-31719aef6889/ProCoachLab.ProCoachLab:PersistentLevel.VerseDevice_C_UAID_30E3A4101075351203_1174112206"}
LEDGER = os.path.join(ROOT, ".local", "quick-reset-authoring.json")


def main():
    ledger = json.load(open(LEDGER, encoding="utf-8")) if os.path.exists(LEDGER) else {}
    if "device" not in ledger:
        assets = call("ValkyrieFortniteToolset.DeviceToolset", "ListDeviceAssets", {"nameFilter": "InputTrigger"})
        asset = next(a for a in assets if "CRD_InputTrigger" in a["assetPath"]["refPath"])
        ref = call("ValkyrieFortniteToolset.DeviceToolset", "PlaceDevice", {"assetPath": asset["assetPath"], "transform": {
            "location": {"x": -2400, "y": -12800, "z": -1500}, "rotation": {"pitch": 0, "yaw": 0, "roll": 0},
            "scale": {"x": 1, "y": 1, "z": 1}}})
        ledger["device"] = ref["refPath"]
        json.dump(ledger, open(LEDGER, "w", encoding="utf-8"), indent=1)
    path = ledger["device"]
    for name, value in [("Input Type", "Creative Input Action"), ("CreativeInput", "Custom 13 (Place Marker)"),
                        ("Consume Input", "True"), ("Show On HUD", "True"),
                        ("HUD Description", "Reset builds {input}"), ("Enabled at Game Start", "True"),
                        ("RegisteredPlayerBehavior", "Require Registered")]:
        call("ValkyrieFortniteToolset.DeviceToolset", "SetClassicDeviceOption",
             {"devicePath": path, "optionName": name, "value": value})
    call("EditorToolset.LevelToolset", "SetActorFolder", {"actor": {"refPath": path}, "folderPath": "ProCoachLab/Controls"})
    call("EditorToolset.LevelToolset", "SaveActor", {"actor": {"refPath": path}})
    options = {o["name"]: o["currentValue"] for o in call("ValkyrieFortniteToolset.DeviceToolset", "ListClassicDeviceOptions", {"devicePath": path})}
    ledger["options"] = options
    call("ValkyrieFortniteToolset.DeviceToolset", "SetDeviceProperty",
         {"device": PORTAL, "propertyName": "QuickResetInput", "value": json.dumps({"refPath": path})})
    call("ValkyrieFortniteToolset.DeviceToolset", "SetDeviceProperty",
         {"device": PORTAL, "propertyName": "QuickResetConfigured", "value": "true"})
    call("EditorToolset.LevelToolset", "SaveActor", {"actor": PORTAL})
    ledger["portal"] = json.loads(call("ValkyrieFortniteToolset.DeviceToolset", "GetDeviceProperties",
                                       {"device": PORTAL, "propertyNames": ["QuickResetInput", "QuickResetConfigured"]}))
    json.dump(ledger, open(LEDGER, "w", encoding="utf-8"), indent=1)
    print("input:", options.get("CreativeInput"), "| hud:", options.get("HUD Description"))
    print("portal:", ledger["portal"])


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
