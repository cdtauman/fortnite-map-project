using { /Fortnite.com/Characters }
using { /Fortnite.com/Devices }
using { /Verse.org/Random }
using { /Verse.org/Simulation }

# 1V1 match rules and loadout choice (spec v1, docs/RESEARCH_1V1_RULES_HE.md).
# Defaults copy the popular build-fight maps: first to 5, 100 health + 100 shield,
# free weapon choice per slot. Infinite build resources and reserve ammo come from
# the island settings. Every round restores vitals, so health siphon would never
# matter in a 1V1 and is intentionally not offered.

coach_weapon := struct<computes>:
    English : string
    Hebrew : string
    Slot : int

# Order must match coach_portal_device.WeaponGranters (one granter per entry),
# authored by tools/author_duel_loadout.py from uefn/duel-loadout.json.
CoachWeaponCatalog : []coach_weapon = array{
    coach_weapon{English := "Pump Shotgun", Hebrew := "שוטגאן פאמפ", Slot := 0},
    coach_weapon{English := "Tactical Shotgun", Hebrew := "שוטגאן טקטי", Slot := 0},
    coach_weapon{English := "Charge Shotgun", Hebrew := "שוטגאן טעינה", Slot := 0},
    coach_weapon{English := "Combat Shotgun", Hebrew := "שוטגאן קרבי", Slot := 0},
    coach_weapon{English := "Drum Shotgun", Hebrew := "שוטגאן תוף", Slot := 0},
    coach_weapon{English := "Heavy Shotgun", Hebrew := "שוטגאן כבד", Slot := 0},
    coach_weapon{English := "Double Barrel Shotgun", Hebrew := "שוטגאן קנה כפול", Slot := 0},
    coach_weapon{English := "Assault Rifle", Hebrew := "רובה סער", Slot := 1},
    coach_weapon{English := "Heavy Assault Rifle", Hebrew := "רובה סער כבד", Slot := 1},
    coach_weapon{English := "Scoped Assault Rifle", Hebrew := "רובה סער עם כוונת", Slot := 1},
    coach_weapon{English := "Tactical Assault Rifle", Hebrew := "רובה סער טקטי", Slot := 1},
    coach_weapon{English := "Burst Assault Rifle", Hebrew := "רובה סער צרורות", Slot := 1},
    coach_weapon{English := "Light Machine Gun", Hebrew := "מקלע קל", Slot := 1},
    coach_weapon{English := "Drum Gun", Hebrew := "רובה תוף", Slot := 1},
    coach_weapon{English := "Rapid Fire SMG", Hebrew := "תת־מקלע מהיר", Slot := 2},
    coach_weapon{English := "Submachine Gun", Hebrew := "תת־מקלע", Slot := 2},
    coach_weapon{English := "Compact SMG", Hebrew := "תת־מקלע קומפקטי", Slot := 2},
    coach_weapon{English := "Burst SMG", Hebrew := "תת־מקלע צרורות", Slot := 2},
    coach_weapon{English := "Bolt-Action Sniper", Hebrew := "צלפים בריח", Slot := 3},
    coach_weapon{English := "Heavy Sniper", Hebrew := "צלפים כבד", Slot := 3},
    coach_weapon{English := "Hunting Rifle", Hebrew := "רובה ציד", Slot := 3},
    coach_weapon{English := "Semi-Auto Sniper", Hebrew := "צלפים חצי־אוטומטי", Slot := 3},
    coach_weapon{English := "Hand Cannon", Hebrew := "הנד קאנון", Slot := 4},
    coach_weapon{English := "Suppressed Pistol", Hebrew := "אקדח עם משתיק", Slot := 4},
    coach_weapon{English := "Revolver", Hebrew := "אקדח תופי", Slot := 4}
}

CoachWeaponSlotCount : int = 5

# Plain-string language pick, for labels assembled before they become a message.
CoachPick(English : string, Hebrew : string, UseHebrew : logic)<transacts>:string =
    if (UseHebrew?):
        return Hebrew
    English

CoachWeaponSlotName(Slot : int, Hebrew : logic)<transacts>:string =
    if (Slot = 0):
        return CoachPick("Shotgun", "שוטגאן", Hebrew)
    if (Slot = 1):
        return CoachPick("Assault rifle", "רובה סער", Hebrew)
    if (Slot = 2):
        return CoachPick("SMG", "תת־מקלע", Hebrew)
    if (Slot = 3):
        return CoachPick("Sniper", "צלפים", Hebrew)
    CoachPick("Pistol", "אקדח", Hebrew)

# Default loadout: Pump Shotgun + Assault Rifle, other slots empty.
CoachDefaultLoadout()<transacts>:[]int = array{0, 7, -1, -1, -1}

# Returns a full five-slot loadout; invalid or missing entries fall back to the default.
CoachNormalizeLoadout(Saved : []int)<transacts>:[]int =
    Default := CoachDefaultLoadout()
    var Result : []int = array{}
    for (Slot := 0..CoachWeaponSlotCount - 1):
        var Choice : int = -1
        if (Fallback := Default[Slot]):
            set Choice = Fallback
        if (Saved.Length = CoachWeaponSlotCount, Stored := Saved[Slot]):
            if (Stored = -1):
                set Choice = -1
            else if (Weapon := CoachWeaponCatalog[Stored], Weapon.Slot = Slot):
                set Choice = Stored
        set Result += array{Choice}
    Result

# Next catalog entry for a slot, cycling through "none" (-1) after the last weapon.
# The shotgun slot never becomes empty: every build fight needs a close-range weapon.
CoachNextWeapon(Slot : int, Current : int)<transacts>:int =
    var Seen : logic = false
    if (Current = -1):
        set Seen = true
    for (Index -> Weapon : CoachWeaponCatalog, Weapon.Slot = Slot):
        if (Seen?):
            return Index
        if (Index = Current):
            set Seen = true
    if (Slot = 0):
        for (Index -> Weapon : CoachWeaponCatalog, Weapon.Slot = Slot):
            return Index
    -1

CoachRandomLoadout()<transacts>:[]int =
    var Result : []int = array{}
    for (Slot := 0..CoachWeaponSlotCount - 1):
        var Options : []int = array{}
        for (Index -> Weapon : CoachWeaponCatalog, Weapon.Slot = Slot):
            set Options += array{Index}
        # Shotgun and rifle are always filled; the other slots are filled about half the time.
        var Choice : int = -1
        if (Slot <= 1 or GetRandomInt(0, 1) = 1):
            if (Picked := Options[GetRandomInt(0, Options.Length - 1)]):
                set Choice = Picked
        set Result += array{Choice}
    Result

CoachWeaponLabel(Choice : int, Hebrew : logic)<transacts>:string =
    if (Weapon := CoachWeaponCatalog[Choice]):
        return CoachPick(Weapon.English, Weapon.Hebrew, Hebrew)
    CoachPick("None", "ללא", Hebrew)

CoachFirstToOptions : []int = array{3, 5, 7, 10, 0}

# Shared by both duelists; changes apply from the next round.
coach_duel_settings := class:
    var TargetIndex : int = 1
    var VitalsIndex : int = 0

    Target()<transacts>:int =
        if (Value := CoachFirstToOptions[TargetIndex]):
            return Value
        5

    TargetLabel(Hebrew : logic)<transacts>:string =
        Value := Target()
        if (Value = 0):
            return CoachPick("Endless", "ללא סוף", Hebrew)
        CoachPick("First to {Value}", "הראשון ל־{Value}", Hebrew)

    NextTarget():void =
        set TargetIndex = Mod[TargetIndex + 1, CoachFirstToOptions.Length] or 0

    MaxHealth()<transacts>:float =
        if (VitalsIndex = 2):
            return 200.0
        100.0

    MaxShield()<transacts>:float =
        if (VitalsIndex = 1):
            return 0.0
        100.0

    VitalsLabel(Hebrew : logic)<transacts>:string =
        if (VitalsIndex = 1):
            return CoachPick("100 health, no shield", "100 חיים, בלי מגן", Hebrew)
        if (VitalsIndex = 2):
            return CoachPick("200 health + 100 shield", "200 חיים + 100 מגן", Hebrew)
        CoachPick("100 health + 100 shield", "100 חיים + 100 מגן", Hebrew)

    NextVitals():void =
        set VitalsIndex = Mod[VitalsIndex + 1, 3] or 0
