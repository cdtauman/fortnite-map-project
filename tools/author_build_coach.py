"""Place the four hologram props for the live build coach (spec v1 step 4.1) and wire them to
coach_portal_device.HoloWall/HoloFloor/HoloRamp/HoloCone + BuildCoachConfigured.
Editor authoring only. Idempotent via .local/build-coach-authoring.json."""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sync_verse import call, ROOT

PORTAL = {"refPath": "/eda26a53-42c0-4b9e-8f62-31719aef6889/ProCoachLab.ProCoachLab:PersistentLevel.VerseDevice_C_UAID_30E3A4101075351203_1174112206"}
KIT = "/eda26a53-42c0-4b9e-8f62-31719aef6889/Art/TeachingKit/"
LEDGER = os.path.join(ROOT, ".local", "build-coach-authoring.json")


def main():
    ledger = json.load(open(LEDGER, encoding="utf-8")) if os.path.exists(LEDGER) else {"actors": {}}
    for i, kind in enumerate(["Wall", "Floor", "Ramp", "Cone"]):
        label = "PCL_BuildCoach_Holo" + kind
        if label not in ledger["actors"]:
            ref = call("EditorToolset.LevelToolset", "AddToSceneFromAsset", {
                "assetPath": KIT + "PCL_BP_Holo" + kind + ".PCL_BP_Holo" + kind, "name": label,
                "xform": {"location": {"x": 45056 + i * 600, "y": -3000, "z": -2500},
                          "rotation": {"pitch": 0, "yaw": 0, "roll": 0}, "scale": {"x": 1, "y": 1, "z": 1}}})
            ledger["actors"][label] = ref["refPath"] if isinstance(ref, dict) else ref
            json.dump(ledger, open(LEDGER, "w", encoding="utf-8"), indent=1)
        path = ledger["actors"][label]
        call("EditorToolset.LevelToolset", "SetActorFolder", {"actor": {"refPath": path}, "folderPath": "ProCoachLab/BuildCoach"})
        call("EditorToolset.LevelToolset", "SaveActor", {"actor": {"refPath": path}})
        call("ValkyrieFortniteToolset.DeviceToolset", "SetDeviceProperty",
             {"device": PORTAL, "propertyName": "Holo" + kind, "value": json.dumps({"refPath": path})})
    call("ValkyrieFortniteToolset.DeviceToolset", "SetDeviceProperty",
         {"device": PORTAL, "propertyName": "BuildCoachConfigured", "value": "true"})
    call("EditorToolset.LevelToolset", "SaveActor", {"actor": PORTAL})
    back = json.loads(call("ValkyrieFortniteToolset.DeviceToolset", "GetDeviceProperties", {"device": PORTAL,
        "propertyNames": ["HoloWall", "HoloFloor", "HoloRamp", "HoloCone", "BuildCoachConfigured"]}))
    ledger["portal_readback"] = back
    ok = all(back["Holo" + k]["refPath"] == ledger["actors"]["PCL_BuildCoach_Holo" + k] for k in ["Wall", "Floor", "Ramp", "Cone"])
    ledger["verified"] = ok and back["BuildCoachConfigured"] is True
    json.dump(ledger, open(LEDGER, "w", encoding="utf-8"), indent=1)
    print("wired:", ledger["verified"])


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
