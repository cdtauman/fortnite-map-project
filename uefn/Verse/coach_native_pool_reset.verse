using { /Fortnite.com/Devices }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }

coach_native_pool_tag := class(tag){}
coach_native_pool_wall_tag := class(coach_native_pool_tag){}
coach_native_pool_floor_tag := class(coach_native_pool_tag){}
coach_native_pool_ramp_tag := class(coach_native_pool_tag){}
coach_native_pool_cone_tag := class(coach_native_pool_tag){}

coach_native_pool_snapshot := class:
    Walls : []creative_prop = array{}
    Floors : []creative_prop = array{}
    Ramps : []creative_prop = array{}
    Cones : []creative_prop = array{}

    All()<transacts>:[]creative_prop = Walls + Floors + Ramps + Cones

# A candidate reset of a dedicated native-actor layer between encounters.
# Fresh discovery does not establish restored health or native ownership.
coach_native_pool_reset_device := class(creative_device):
    @editable
    Enabled : logic = false
    @editable
    UnloadPool : cinematic_sequence_device = cinematic_sequence_device{}
    @editable
    LoadPool : cinematic_sequence_device = cinematic_sequence_device{}
    @editable
    WallCount : int = 16
    @editable
    FloorCount : int = 16
    @editable
    RampCount : int = 16
    @editable
    ConeCount : int = 16
    var Busy : logic = false
    var Ending : logic = false

    OnEnd<override>():void =
        set Ending = true
        UnloadPool.Stop()
        LoadPool.Stop()

    Discover()<transacts>:?coach_native_pool_snapshot =
        var Walls : []creative_prop = array{}
        var Floors : []creative_prop = array{}
        var Ramps : []creative_prop = array{}
        var Cones : []creative_prop = array{}
        for (Object : FindCreativeObjectsWithTag(coach_native_pool_tag)):
            if (Prop := creative_prop[Object]):
                if (Prop.IsValid[]):
                    var Kinds : int = 0
                    if (Object.ContainsTag[coach_native_pool_wall_tag]):
                        set Kinds += 1
                    if (Object.ContainsTag[coach_native_pool_floor_tag]):
                        set Kinds += 1
                    if (Object.ContainsTag[coach_native_pool_ramp_tag]):
                        set Kinds += 1
                    if (Object.ContainsTag[coach_native_pool_cone_tag]):
                        set Kinds += 1
                    if (Kinds <> 1):
                        return false
                    if (Object.ContainsTag[coach_native_pool_wall_tag]):
                        set Walls += array{Prop}
                    else if (Object.ContainsTag[coach_native_pool_floor_tag]):
                        set Floors += array{Prop}
                    else if (Object.ContainsTag[coach_native_pool_ramp_tag]):
                        set Ramps += array{Prop}
                    else:
                        set Cones += array{Prop}
            else:
                return false
        return option{coach_native_pool_snapshot{Walls := Walls, Floors := Floors, Ramps := Ramps, Cones := Cones}}

    Complete(Snapshot : coach_native_pool_snapshot)<transacts>:logic =
        if (WallCount > 0 and FloorCount > 0 and RampCount > 0 and ConeCount > 0 and Snapshot.Walls.Length = WallCount and Snapshot.Floors.Length = FloorCount and Snapshot.Ramps.Length = RampCount and Snapshot.Cones.Length = ConeCount):
            return true
        return false

    OldObjectsGone(Snapshot : coach_native_pool_snapshot)<transacts>:logic =
        for (Prop : Snapshot.All(), Prop.IsValid[]):
            return false
        # A removed object must also disappear from the live tagged inventory.
        for (Object : FindCreativeObjectsWithTag(coach_native_pool_tag), Prop := creative_prop[Object], Prop.IsValid[]):
            return false
        return true

    PlayLayerSequence(Sequence : cinematic_sequence_device)<suspends>:logic =
        Sequence.Stop()
        Sequence.SetPlaybackFrame(0)
        Sequence.SetPlayRate(1.0)
        StartedAt := GetSimulationElapsedTime()
        EarliestStop := Max(0.0, Sequence.GetSequenceLength() - 0.15)
        Sequence.Play()
        var Finished : logic = false
        race:
            block:
                loop:
                    Sequence.StoppedEvent.Await()
                    if (GetSimulationElapsedTime() - StartedAt >= EarliestStop):
                        set Finished = true
                        break
            Sleep(8.0)
        if (not Finished?):
            Sequence.Stop()
        return Finished

    # Finish the load request even if the requesting trainee leaves. The caller
    # alone decides whether the returned pool still belongs to its encounter.
    Rebuild()<suspends>:?coach_native_piece_pool =
        if (not Enabled? or Busy? or Ending?):
            return false
        set Busy = true
        defer:
            set Busy = false
        var Before : coach_native_pool_snapshot = coach_native_pool_snapshot{}
        if (Found := Discover()?):
            set Before = Found
        else:
            return false
        # Missing/destroyed entries are expected before restoration. Excess or
        # ambiguous tags are not allowed to hide unrelated actors in the bank.
        if (Before.Walls.Length > WallCount or Before.Floors.Length > FloorCount or Before.Ramps.Length > RampCount or Before.Cones.Length > ConeCount):
            return false
        Unloaded := PlayLayerSequence(UnloadPool)
        var Removed : logic = false
        var UnloadAttempt : int = 0
        loop:
            if (OldObjectsGone(Before)?):
                set Removed = true
                break
            if (UnloadAttempt >= 23):
                break
            Sleep(0.1)
            set UnloadAttempt += 1
        if (Ending?):
            return false
        Loaded := PlayLayerSequence(LoadPool)
        if (not Unloaded? or not Removed? or not Loaded? or Ending?):
            return false
        for (Attempt := 0..23):
            if (Fresh := Discover()?, Complete(Fresh)?):
                Pool := coach_native_piece_pool{}
                Pool.Register(Fresh.Walls, coach_piece_kind.Wall)
                Pool.Register(Fresh.Floors, coach_piece_kind.FloorPiece)
                Pool.Register(Fresh.Ramps, coach_piece_kind.Ramp)
                Pool.Register(Fresh.Cones, coach_piece_kind.Cone)
                Pool.Seal()
                if (Pool.ConfigurationValid?):
                    return option{Pool}
                return false
            Sleep(0.1)
        return false
