using { /Fortnite.com/Devices }
using { /Fortnite.com/Characters }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/SpatialMath }

# Experiment N1 (temporary fixture): can scene queries see structures the player builds and edits?
# Moves the first player into the free-build arena once, then every 0.5s:
#  - overlap box around the player: entities hit and hit counts per entity
#  - 5x5 grid of short sweeps along the view direction: how many are blocked (edit openings)
# Prints only when a signature changes.
n1_build_scan_device := class(creative_device):
    @editable
    Enabled : logic = true

    @editable
    ArenaPosition : vector3 = vector3{X := 45056.0, Y := 0.0, Z := 400.0}

    OnBegin<override>()<suspends>:void =
        if (not Enabled?):
            return
        Print("N1 fixture started")
        var Moved : logic = false
        var LastBox : string = ""
        var LastGrid : string = ""
        var Tick : int = 0
        loop:
            Sleep(0.5)
            set Tick += 1
            if (Root := GetSimulationEntity[], Player := GetPlayspace().GetPlayers()[0], Char := Player.GetFortCharacter[]):
                if (not Moved?):
                    if (Char.TeleportTo[ArenaPosition, IdentityRotation()]):
                        Print("N1 moved player to free-build arena")
                    else:
                        Print("N1 teleport rejected")
                    set Moved = true
                    Sleep(2.0)
                else:
                    Body := Char.GetTransform().Translation
                    BoxText := ScanBox(Root, Body)
                    if (BoxText <> LastBox):
                        set LastBox = BoxText
                        Print("N1 box t={Tick} {BoxText}")
                    GridText := ScanGrid(Root, Char)
                    if (GridText <> LastGrid):
                        set LastGrid = GridText
                        Print("N1 grid t={Tick} {GridText}")

    Profile()<transacts>:collision_profile =
        collision_profile{Channel := CollisionChannels.dynamic{}, GetChannelInteraction := CoachStructureInteraction}

    ScanBox(Root : entity, Center : vector3)<transacts>:string =
        Box := collision_box{Extents := FromVector3(vector3{X := 700.0, Y := 700.0, Z := 450.0}), CollisionProfile := Profile()}
        Pose := transform{Translation := Center + vector3{Z := 150.0}}
        var Entities : []entity = array{}
        var Counts : []int = array{}
        var Total : int = 0
        for (Hit : Root.FindOverlapHits(FromTransform(Pose), Box)):
            set Total += 1
            Target := Hit.TargetComponent.Entity
            var Found : logic = false
            for (Index -> Known : Entities, Known = Target):
                set Found = true
                if (Old := Counts[Index]):
                    if (set Counts[Index] = Old + 1) {}
            if (not Found?):
                set Entities += array{Target}
                set Counts += array{1}
        var Text : string = "entities={Entities.Length} hits={Total}"
        for (Index -> Item : Entities, Count := Counts[Index]):
            At := FromVector3(Item.GetGlobalTransform().Translation)
            set Text += " [{Cm(At.X)},{Cm(At.Y)},{Cm(At.Z)}]x{Count}"
        Text

    ScanGrid(Root : entity, Char : fort_character)<transacts>:string =
        Eye := Char.GetViewLocation()
        View := Char.GetViewRotation()
        Forward := View.GetLocalForward()
        Right := View.GetLocalRight()
        Up := View.GetLocalUp()
        Sphere := collision_sphere{Radius := 2.0, CollisionProfile := Profile()}
        Offsets : []float = array{-120.0, -60.0, 0.0, 60.0, 120.0}
        var Blocked : int = 0
        var Mask : string = ""
        for (Row -> Vertical : Offsets, Column -> Horizontal : Offsets):
            Start := Eye + Right * Horizontal - Up * Vertical
            var Hit : logic = false
            for (Sweep : Root.FindSweepHits(FromVector3(Forward * 450.0), FromTransform(transform{Translation := Start}), Sphere)):
                set Hit = true
            if (Hit?):
                set Blocked += 1
                set Mask += "#"
            else:
                set Mask += "."
            if (Column = 4):
                set Mask += "/"
        "blocked={Blocked} mask={Mask}"

    Cm(Value : float)<transacts>:int =
        if (Rounded := Round[Value / 10.0]):
            return Rounded * 10
        0
