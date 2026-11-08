"""Author the 1V1 loadout granters (spec v1 step 2.2). Editor authoring only, no game.

Creates one Item Granter per weapon in uefn/duel-loadout.json (order == CoachWeaponCatalog in
uefn/Verse/coach_duel_match.verse) plus one "Clear Items" granter, configures them, saves them,
and wires coach_portal_device.WeaponGranters / LoadoutClear / DuelLoadoutConfigured.
Idempotent: progress is kept in .local/duel-loadout-authoring.json.
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sync_verse import call, ROOT

PORTAL = "/eda26a53-42c0-4b9e-8f62-31719aef6889/ProCoachLab.ProCoachLab:PersistentLevel.VerseDevice_C_UAID_30E3A4101075351203_1174112206"
GRANTER_ASSET = "/CreativeCoreDevices/SetupAssets/PID_Device_ItemGranter.PID_Device_ItemGranter"
WOOD = "/Game/Items/ResourcePickups/WoodItemData.WoodItemData"
LEDGER = os.path.join(ROOT, ".local", "duel-loadout-authoring.json")
LAYOUT = os.path.join(ROOT, "uefn", "duel-loadout.json")


def option(device, name, value):
    call("ValkyrieFortniteToolset.DeviceToolset", "SetClassicDeviceOption",
         {"devicePath": device, "optionName": name, "value": value})


def author(label, item, quantity, clear, index, ledger):
    if label in ledger["granters"]:
        return ledger["granters"][label]
    xform = {"location": {"x": -2400 + index * 150, "y": -12500, "z": -1500},
             "rotation": {"pitch": 0, "yaw": 0, "roll": 0}, "scale": {"x": 1, "y": 1, "z": 1}}
    ref = call("ValkyrieFortniteToolset.DeviceToolset", "PlaceDevice",
               {"assetPath": {"refPath": GRANTER_ASSET}, "transform": xform})
    path = ref["refPath"]
    ledger["granters"][label] = path
    json.dump(ledger, open(LEDGER, "w", encoding="utf-8"), indent=1)
    call("EditorToolset.ObjectToolset", "SetProperties", {"instance": {"refPath": path + ".PickupItemList"},
         "values": json.dumps({"itemListData": [{"itemDefinition": {"refPath": item}, "itemQuantity": quantity}]})})
    for name, value in [("OnGrantAction", "Clear Items" if clear else "Keep All"), ("Grant", "All Items"),
                        ("GrantCondition", "Always"), ("bEquipGrantedItem", "False"),
                        ("DropItemsAtPlayerLocation", "Never"), ("EnabledOnGameStart", "True"),
                        ("bGrantOnGameStart", "False"), ("bGrantOnTimer", "False"), ("PlayAudio", "False")]:
        option(path, name, value)
    if not clear:
        option(path, "SpareWeaponAmmo", "999")

    call("EditorToolset.LevelToolset", "SetActorFolder", {"actor": {"refPath": path}, "folderPath": "ProCoachLab/DuelLoadout"})
    call("EditorToolset.LevelToolset", "SaveActor", {"actor": {"refPath": path}})
    readback = json.loads(call("EditorToolset.ObjectToolset", "GetProperties",
                               {"instance": {"refPath": path + ".PickupItemList"}, "properties": ["itemListData"]}))
    got = readback["itemListData"][0]["itemDefinition"]["refPath"]
    if got != item:
        raise RuntimeError(f"{label}: item readback {got} != {item}")
    ledger["verified"][label] = got
    json.dump(ledger, open(LEDGER, "w", encoding="utf-8"), indent=1)
    print("granter", label, "ok")
    return path


def main():
    weapons = json.load(open(LAYOUT, encoding="utf-8"))["weapons"]
    ledger = json.load(open(LEDGER, encoding="utf-8")) if os.path.exists(LEDGER) else {"granters": {}, "verified": {}}
    clear = author("PCL_Duel_LoadoutClear", WOOD, 1, True, 0, ledger)
    paths = [author("PCL_Duel_Weapon_%02d" % i, w["path"], 1, False, i + 1, ledger) for i, w in enumerate(weapons)]
    device = {"refPath": PORTAL}
    call("ValkyrieFortniteToolset.DeviceToolset", "SetDeviceProperty",
         {"device": device, "propertyName": "WeaponGranters", "value": json.dumps([{"refPath": p} for p in paths])})
    call("ValkyrieFortniteToolset.DeviceToolset", "SetDeviceProperty",
         {"device": device, "propertyName": "LoadoutClear", "value": json.dumps({"refPath": clear})})
    call("ValkyrieFortniteToolset.DeviceToolset", "SetDeviceProperty",
         {"device": device, "propertyName": "DuelLoadoutConfigured", "value": "true"})
    call("EditorToolset.LevelToolset", "SaveActor", {"actor": device})
    back = call("ValkyrieFortniteToolset.DeviceToolset", "GetDeviceProperties",
                {"device": device, "propertyNames": ["WeaponGranters", "LoadoutClear", "DuelLoadoutConfigured"]})
    ledger["portal_readback"] = back
    json.dump(ledger, open(LEDGER, "w", encoding="utf-8"), indent=1)
    print("portal wired:", str(back)[:400])


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
