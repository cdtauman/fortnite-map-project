using { /Fortnite.com/Devices }
using { /Fortnite.com/Characters }
using { /Verse.org/SceneGraph }
using { /Verse.org/Assets }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/SpatialMath }

coach_piece_shape := enum:
    Solid
    Window
    Door
    SidePassage
    FloorHalf
    RampHalf
    ConeRaised

coach_piece_kind := enum:
    Wall
    FloorPiece
    Ramp
    Cone

coach_build_outcome := enum:
    Applied
    Occupied
    Stale
    AssetUnavailable
    InteroperabilityUnverified
    BudgetReached
    OutOfArena
    ResourceUnavailable
    Cooldown
    PoolExhausted
    InvalidShape
    OutOfReach

coach_pool_piece_state := enum:
    Available
    Reserved
    Active
    Spent
    Lost

# A live reference does not establish that its geometry stayed at the planned
# position. Check the authored pose before committing or continuing a skill.
CoachCombatPropMatchesPose(Prop : creative_prop, Expected : transform)<transacts>:logic =
    if (not Prop.IsValid[]):
        return false
    Actual := Prop.GetTransform()
    if (Distance(Actual.Translation, Expected.Translation) > 5.0 or Distance(Actual.Scale, Expected.Scale) > 0.01):
        return false
    Forward := vector3{X := 1.0}
    Up := vector3{Z := 1.0}
    if (DotProduct(Actual.Rotation.RotateVector(Forward), Expected.Rotation.RotateVector(Forward)) < 0.9998 or DotProduct(Actual.Rotation.RotateVector(Up), Expected.Rotation.RotateVector(Up)) < 0.9998):
        return false
    return true

# One allocation per physical actor per game. Returning a damaged actor never heals or reissues it.
coach_native_piece_lease := class<unique>:
    Prop : creative_prop
    Kind : coach_piece_kind
    Parking : transform
    var State : coach_pool_piece_state = coach_pool_piece_state.Available
    var Encounter : int = -1

coach_native_piece_pool := class:
    var Entries : []coach_native_piece_lease = array{}
    var Sealed : logic = false
    var ConfigurationValid : logic = true

    Register(Props : []creative_prop, Kind : coach_piece_kind):void =
        if (Sealed?):
            return
        for (Prop : Props):
            if (Prop.IsValid[]):
                Parking := Prop.GetTransform()
                var AmbiguousParking : logic = false
                # creative_prop is not comparable. Editor preflight must check distinct actor refs;
                # runtime additionally rejects duplicate/coincident parking locations.
                for (Entry : Entries, Distance(Entry.Parking.Translation, Parking.Translation) < 1.0):
                    set AmbiguousParking = true
                if (AmbiguousParking?):
                    set ConfigurationValid = false
                else:
                    set Entries += array{coach_native_piece_lease{Prop := Prop, Kind := Kind, Parking := Parking}}
                    Prop.Hide()
            else:
                set ConfigurationValid = false

    Seal():void =
        set Sealed = true

    Available(Kind : coach_piece_kind)<transacts>:int =
        var Count : int = 0
        for (Entry : Entries, Entry.Kind = Kind, Entry.State = coach_pool_piece_state.Available, Entry.Prop.IsValid[]):
            set Count += 1
        return Count

    Contains(Lease : coach_native_piece_lease)<transacts>:logic =
        for (Entry : Entries, Entry = Lease):
            return true
        return false

    Acquire(Kind : coach_piece_kind, Pose : transform, Encounter : int):?coach_native_piece_lease =
        if (not Sealed? or not ConfigurationValid?):
            return false
        for (Entry : Entries, Entry.Kind = Kind, Entry.State = coach_pool_piece_state.Available):
            if (not Entry.Prop.IsValid[]):
                set Entry.State = coach_pool_piece_state.Lost
            else:
                set Entry.State = coach_pool_piece_state.Reserved
                set Entry.Encounter = Encounter
                if (Entry.Prop.TeleportTo[Pose], CoachCombatPropMatchesPose(Entry.Prop, Pose)?):
                    # Combat damage is an instance policy. Do not infer it
                    # from the Blueprint default or reset the actor's health.
                    set Entry.Prop.CanBeDamaged = true
                    if (Entry.Prop.CanBeDamaged?):
                        Entry.Prop.Show()
                        set Entry.State = coach_pool_piece_state.Active
                        return option{Entry}
                # A failed move consumes the entry; no uncertain actor may be leased again.
                Retire(Entry)
        return false

    Retire(Lease : coach_native_piece_lease):void =
        if (not Contains(Lease)?):
            return
        if (Lease.Prop.IsValid[]):
            Lease.Prop.Hide()
            if (Lease.Prop.TeleportTo[Lease.Parking]):
                set Lease.State = coach_pool_piece_state.Spent
            else:
                set Lease.State = coach_pool_piece_state.Lost
        else:
            set Lease.State = coach_pool_piece_state.Lost

    RetireEncounter(Encounter : int):void =
        for (Entry : Entries, Entry.Encounter = Encounter, Entry.State = coach_pool_piece_state.Active or Entry.State = coach_pool_piece_state.Reserved):
            Retire(Entry)

    RetireAll():void =
        for (Entry : Entries, Entry.State = coach_pool_piece_state.Active or Entry.State = coach_pool_piece_state.Reserved):
            Retire(Entry)

coach_live_piece := class<unique>:
    Prop : creative_prop
    Position : vector3
    Yaw : float
    Encounter : int
    Kind : coach_piece_kind = coach_piece_kind.Wall
    NativeLease : ?coach_native_piece_lease = false
    var Revision : int = 0
    var Shape : coach_piece_shape = coach_piece_shape.Solid
    var LastEditAt : float = -100.0

# Same-actor geometry candidate. Native ownership and health continuity require gameplay evidence.
coach_structure_device := class(creative_device):
    @editable
    WallAsset : creative_prop_asset = DefaultCreativePropAsset
    @editable
    FloorAsset : creative_prop_asset = DefaultCreativePropAsset
    @editable
    RampAsset : creative_prop_asset = DefaultCreativePropAsset
    @editable
    ConeAsset : creative_prop_asset = DefaultCreativePropAsset
    @editable
    DemoAsset : creative_prop_asset = DefaultCreativePropAsset
    @editable
    WallSolidMesh : mesh = Art.GridKit.PCL_SM_GridWallSolid_asset
    @editable
    WallWindowMesh : mesh = Art.GridKit.PCL_SM_GridWallWindow_asset
    @editable
    WallExitMesh : mesh = Art.GridKit.PCL_SM_GridWallExit_asset
    @editable
    DemoOne : creative_prop = creative_prop{}
    @editable
    DemoTwo : creative_prop = creative_prop{}
    @editable
    QueryCoverageConfirmed : logic = false
    @editable
    HealthContinuityConfirmed : logic = false
    @editable
    NativeSlotInteroperationConfirmed : logic = false
    @editable
    CandidateCombatEnabled : logic = false
    @editable
    EnforceResourceCosts : logic = true
    @editable
    UseNativePiecePool : logic = false
    @editable
    RenewNativePoolBetweenRounds : logic = false
    @editable
    NativePoolRestorer : coach_native_pool_reset_device = coach_native_pool_reset_device{}
    @editable
    NativeWallPool : []creative_prop = array{}
    @editable
    NativeFloorPool : []creative_prop = array{}
    @editable
    NativeRampPool : []creative_prop = array{}
    @editable
    NativeConePool : []creative_prop = array{}

    var Pieces : []coach_live_piece = array{}
    var LastBuildAt : float = -100.0
    var LastAttemptAt : float = -100.0
    var Encounter : int = 0
    var Demonstrations : [player]creative_prop = map{}
    var DemoOwners : [int]player = map{}
    var BuilderBody : ?entity = false
    var BuilderAgent : ?agent = false
    Equipment : coach_equipment = coach_equipment{}
    var NativePool : coach_native_piece_pool = coach_native_piece_pool{}

    CombatReady()<transacts>:logic =
        if (CandidateCombatEnabled? and QueryCoverageConfirmed? and HealthContinuityConfirmed? and NativeSlotInteroperationConfirmed?):
            return true
        return false

    OnBegin<override>()<suspends>:void =
        if (UseNativePiecePool?):
            NativePool.Register(NativeWallPool, coach_piece_kind.Wall)
            NativePool.Register(NativeFloorPool, coach_piece_kind.FloorPiece)
            NativePool.Register(NativeRampPool, coach_piece_kind.Ramp)
            NativePool.Register(NativeConePool, coach_piece_kind.Cone)
            NativePool.Seal()
        for (Prop : array{DemoOne, DemoTwo}, Prop.IsValid[]):
            set Prop.CanBeDamaged = false
            Prop.Hide()

    OnEnd<override>():void =
        ResetEncounter()
        for (Player -> Prop : Demonstrations, Prop.IsValid[]):
            Prop.Hide()

    ResetEncounter():void =
        NativePool.RetireEncounter(Encounter)
        set Encounter += 1
        for (Piece : Pieces, Piece.Prop.IsValid[]):
            if (not Piece.NativeLease?):
                Piece.Prop.Dispose()
        set Pieces = array{}
        set LastBuildAt = -100.0
        set LastAttemptAt = -100.0
        set BuilderBody = false
        set BuilderAgent = false

    PrepareNativePool(ExpectedEncounter : int)<suspends>:logic =
        if (ExpectedEncounter <> Encounter):
            return false
        if (not UseNativePiecePool? or not RenewNativePoolBetweenRounds?):
            return true
        # Only the round-preparation owner may replace a retired pool.
        for (Entry : NativePool.Entries, Entry.State = coach_pool_piece_state.Active or Entry.State = coach_pool_piece_state.Reserved):
            return false
        if (BuilderAgent? or BuilderBody?):
            return false
        Rebuilt := NativePoolRestorer.Rebuild()
        if (Replacement := Rebuilt?, ExpectedEncounter = Encounter, not BuilderAgent?, not BuilderBody?):
            set NativePool = Replacement
            return true
        return false

    PlacementClear(Kind : coach_piece_kind, Position : vector3, Yaw : float)<transacts>:logic =
        if (Root := GetSimulationEntity[]):
            if (Kind = coach_piece_kind.Ramp):
                # Interior wedge slices leave the legal floor/roof attachment seam
                # outside the query instead of treating the full cell as a solid box.
                Rotation := MakeRotationFromYawPitchRollDegrees(Yaw, 0.0, 0.0)
                for (Index := 0..15):
                    Along := -240.0 + Index * 32.0
                    Height := (Along + 256.0) * 0.75
                    HalfHeight := Max(2.0, (Height - 12.0) * 0.5)
                    SliceBox := collision_box{Extents := FromVector3(vector3{X := 14.0, Y := 228.0, Z := HalfHeight}), CollisionProfile := CollisionProfiles.DynamicOverlapAll}
                    SlicePose := transform{Translation := Position + Rotation.RotateVector(vector3{X := Along}) + vector3{Z := HalfHeight + 6.0}, Rotation := Rotation}
                    if (not InteriorClear(Root, SlicePose, SliceBox)?):
                        return false
                return true
            var Extent : vector3 = vector3{X := 13.0, Y := 228.0, Z := 178.0}
            var Offset : vector3 = vector3{Z := 192.0}
            if (Kind = coach_piece_kind.FloorPiece):
                set Extent = vector3{X := 228.0, Y := 228.0, Z := 6.0}
                set Offset = vector3{Z := -8.0}
            else if (Kind = coach_piece_kind.Ramp or Kind = coach_piece_kind.Cone):
                set Extent = vector3{X := 250.0, Y := 250.0, Z := 186.0}
                if (Kind = coach_piece_kind.Cone):
                    # Leave the shared edge outside this interior query so adjoining walls remain legal.
                    set Extent.X = 228.0
                    set Extent.Y = 228.0
                    set Extent.Z = 94.0
                    set Offset.Z = 100.0
            Box := collision_box{
                Extents := FromVector3(Extent),
                CollisionProfile := CollisionProfiles.DynamicOverlapAll
            }
            Pose := transform{Translation := Position + Offset, Rotation := MakeRotationFromYawPitchRollDegrees(Yaw, 0.0, 0.0)}
            return InteriorClear(Root, Pose, Box)
        return false

    InteriorClear(Root : entity, Pose : transform, Box : collision_box)<transacts>:logic =
        for (Hit : Root.FindOverlapHits(FromTransform(Pose), Box)):
            var IsBuilder : logic = false
            if (Body := BuilderBody?):
                if (Hit.TargetComponent.Entity = Body):
                    set IsBuilder = true
                for (Ancestor : Hit.TargetComponent.Entity.FindAncestorEntities(entity), Ancestor = Body):
                    set IsBuilder = true
            if (not IsBuilder?):
                return false
        return true

    # Policy positions describe cell centers; native-style horizontal meshes use a rear-edge pivot.
    GridTransform(Kind : coach_piece_kind, Center : vector3, Yaw : float)<transacts>:transform =
        if (Kind = coach_piece_kind.Wall):
            return transform{Translation := Center, Rotation := MakeRotationFromYawPitchRollDegrees(Yaw + 90.0, 0.0, 0.0)}
        var AssetYaw : float = Yaw
        if (Kind = coach_piece_kind.Ramp):
            set AssetYaw -= 90.0
        Rotation := MakeRotationFromYawPitchRollDegrees(AssetYaw, 0.0, 0.0)
        return transform{Translation := Center - Rotation.RotateVector(vector3{Y := 256.0}), Rotation := Rotation}

    TryDefend(Position : vector3, Threat : vector3):tuple(coach_build_outcome, ?coach_live_piece) =
        if (CellX := Round[Position.X / 512.0], CellY := Round[Position.Y / 512.0], Level := Floor[Position.Z / 384.0]):
            Delta := Threat - Position
            var Location : vector3 = vector3{X := CellX * 512.0, Y := CellY * 512.0, Z := Level * 384.0}
            var Yaw : float = 0.0
            if (Abs(Delta.X) >= Abs(Delta.Y)):
                if (Delta.X >= 0.0):
                    set Location.X += 256.0
                else:
                    set Location.X -= 256.0
            else:
                set Yaw = 90.0
                if (Delta.Y >= 0.0):
                    set Location.Y += 256.0
                else:
                    set Location.Y -= 256.0
            return TryPlace(coach_piece_kind.Wall, Location, Yaw, Encounter, 0.25)
        return (coach_build_outcome.AssetUnavailable, false)

    AssetFor(Kind : coach_piece_kind)<transacts>:creative_prop_asset =
        if (Kind = coach_piece_kind.FloorPiece):
            return FloorAsset
        if (Kind = coach_piece_kind.Ramp):
            return RampAsset
        if (Kind = coach_piece_kind.Cone):
            return ConeAsset
        return WallAsset

    # Reuse only tracked, live pieces from this encounter, never an unowned native structure.
    FindOwnedPiece(Kind : coach_piece_kind, Location : vector3, Yaw : float, ExpectedEncounter : int)<transacts>:?coach_live_piece =
        if (ExpectedEncounter <> Encounter):
            return false
        for (Piece : Pieces, Piece.Encounter = ExpectedEncounter, Piece.Kind = Kind, PiecePlacementCurrent(Piece)?, Distance(Piece.Position, Location) < 16.0, Abs(Piece.Yaw - Yaw) < 1.0):
            return option{Piece}
        return false

    # A ledger/resource snapshot before a multi-step skill, not a reservation or
    # a guarantee of collision, navigation, ownership or native edit semantics.
    PlanAvailability(Steps : []coach_build_step, ExpectedEncounter : int)<transacts>:coach_build_outcome =
        if (not CombatReady()?):
            return coach_build_outcome.InteroperabilityUnverified
        if (ExpectedEncounter <> Encounter):
            return coach_build_outcome.Stale
        if (Steps.Length = 0):
            return coach_build_outcome.AssetUnavailable
        var Missing : []coach_build_step = array{}
        for (Step : Steps, Step.Operation = coach_build_step_kind.Place):
            if (not FindOwnedPiece(Step.Kind, Step.Position, Step.Yaw, ExpectedEncounter)?):
                var Duplicate : logic = false
                for (Previous : Missing, Previous.Kind = Step.Kind, Distance(Previous.Position, Step.Position) < 16.0, Abs(Previous.Yaw - Step.Yaw) < 1.0):
                    set Duplicate = true
                if (not Duplicate?):
                    set Missing += array{Step}
        var LiveCount : int = 0
        for (Piece : Pieces, Piece.Prop.IsValid[]):
            set LiveCount += 1
        if (LiveCount + Missing.Length > 64):
            return coach_build_outcome.BudgetReached
        if (EnforceResourceCosts? and Missing.Length > 0):
            var Affordable : logic = false
            if (Owner := BuilderAgent?):
                set Affordable = Equipment.CanAffordWood(Owner, Missing.Length * 10)
            if (not Affordable?):
                return coach_build_outcome.ResourceUnavailable
        if (UseNativePiecePool?):
            if (not NativePool.Sealed? or not NativePool.ConfigurationValid?):
                return coach_build_outcome.PoolExhausted
            for (Kind : array{coach_piece_kind.Wall, coach_piece_kind.FloorPiece, coach_piece_kind.Ramp, coach_piece_kind.Cone}):
                var Needed : int = 0
                for (Step : Missing, Step.Kind = Kind):
                    set Needed += 1
                if (NativePool.Available(Kind) < Needed):
                    return coach_build_outcome.PoolExhausted
        return coach_build_outcome.Applied

    # Returns the engine spawn result separately from any claim about native structure semantics.
    TryPlace(Kind : coach_piece_kind, Location : vector3, Yaw : float, ExpectedEncounter : int, Interval : float):tuple(coach_build_outcome, ?coach_live_piece) =
        if (not CandidateCombatEnabled? or not QueryCoverageConfirmed? or not HealthContinuityConfirmed? or not NativeSlotInteroperationConfirmed?):
            return (coach_build_outcome.InteroperabilityUnverified, false)
        if (ExpectedEncounter <> Encounter):
            return (coach_build_outcome.Stale, false)
        if (not BuilderCanReach(Location)?):
            return (coach_build_outcome.OutOfReach, false)
        var HalfX : float = 256.0
        var HalfY : float = 256.0
        if (Kind = coach_piece_kind.Wall):
            if (Abs(Yaw) < 1.0 or Abs(Yaw) > 179.0):
                set HalfX = 12.0
            else:
                set HalfY = 12.0
        HalfExtent := CoachArenaHalfExtent(coach_mode.Personal) - 32.0
        if (Abs(Location.X) + HalfX > HalfExtent or Abs(Location.Y) + HalfY > HalfExtent or Location.Z < 0.0 or Location.Z + 384.0 > CoachArenaCeiling()):
            return (coach_build_outcome.OutOfArena, false)
        Now := GetSimulationElapsedTime()
        if (Now - LastAttemptAt < Clamp(Interval, 0.1, 1.0)):
            return (coach_build_outcome.Cooldown, false)
        var Live : []coach_live_piece = array{}
        for (Piece : Pieces, Piece.Prop.IsValid[]):
            set Live += array{Piece}
        set Pieces = Live
        if (Pieces.Length >= 64):
            return (coach_build_outcome.BudgetReached, false)
        for (Piece : Pieces, Distance(Piece.Position, Location) < 32.0):
            if (Piece.Kind = Kind or Piece.Kind <> coach_piece_kind.FloorPiece and Kind <> coach_piece_kind.FloorPiece):
                return (coach_build_outcome.Occupied, false)
        if (not PlacementClear(Kind, Location, Yaw)?):
            return (coach_build_outcome.Occupied, false)
        if (EnforceResourceCosts?):
            var Affordable : logic = false
            if (Owner := BuilderAgent?):
                set Affordable = Equipment.CanAffordWood(Owner, 10)
            if (not Affordable?):
                return (coach_build_outcome.ResourceUnavailable, false)
        set LastAttemptAt = Now
        Pose := GridTransform(Kind, Location, Yaw)
        if (UseNativePiecePool?):
            CandidateLease := NativePool.Acquire(Kind, Pose, Encounter)
            if (Lease := CandidateLease?):
                if (EnforceResourceCosts?):
                    var PoolPaid : logic = false
                    if (Owner := BuilderAgent?):
                        set PoolPaid = Equipment.ConsumeWood(Owner, 10)
                    if (not PoolPaid?):
                        NativePool.Retire(Lease)
                        return (coach_build_outcome.ResourceUnavailable, false)
                NativePiece := coach_live_piece{Prop := Lease.Prop, Position := Location, Yaw := Yaw, Encounter := Encounter, Kind := Kind, NativeLease := option{Lease}}
                set Pieces += array{NativePiece}
                set LastBuildAt = Now
                Print("PCL|structure|native_pool_placed|encounter={Encounter}|remaining={NativePool.Available(Kind)}|damage_enabled=true|health_unmeasured|native_grid_and_edit_require_evidence", ?Duration := 0.0)
                return (coach_build_outcome.Applied, option{NativePiece})
            return (coach_build_outcome.PoolExhausted, false)
        Result := SpawnProp(AssetFor(Kind), Pose.Translation, Pose.Rotation)
        if (Prop := Result(0)?, Result(1) = spawn_prop_result.Ok, Prop.IsValid[]):
            if (not CoachCombatPropMatchesPose(Prop, Pose)?):
                Prop.Dispose()
                Print("PCL|structure|spawn_transform_mismatch", ?Duration := 0.0)
                return (coach_build_outcome.AssetUnavailable, false)
            set Prop.CanBeDamaged = true
            if (not Prop.CanBeDamaged?):
                Prop.Dispose()
                return (coach_build_outcome.AssetUnavailable, false)
            if (EnforceResourceCosts?):
                var Paid : logic = false
                if (Owner := BuilderAgent?):
                    set Paid = Equipment.ConsumeWood(Owner, 10)
                if (not Paid?):
                    Prop.Dispose()
                    return (coach_build_outcome.ResourceUnavailable, false)
            Piece := coach_live_piece{Prop := Prop, Position := Location, Yaw := Yaw, Encounter := Encounter, Kind := Kind}
            set Pieces += array{Piece}
            set LastBuildAt = Now
            Print("PCL|structure|spawn_returned_ok|encounter={Encounter}|damage_enabled=true|health_unmeasured", ?Duration := 0.0)
            return (coach_build_outcome.Applied, option{Piece})
        Print("PCL|structure|spawn_rejected", ?Duration := 0.0)
        return (coach_build_outcome.AssetUnavailable, false)

    IsTrackedPiece(Piece : coach_live_piece)<transacts>:logic =
        for (Current : Pieces, Current = Piece):
            return true
        return false

    PiecePlacementCurrent(Piece : coach_live_piece)<transacts>:logic =
        return CoachCombatPropMatchesPose(Piece.Prop, GridTransform(Piece.Kind, Piece.Position, Piece.Yaw))

    # A mesh request is not a physics acknowledgement. Require two matching
    # observations on separate updates before movement or a peek can continue.
    AwaitWallShape(Piece : coach_live_piece, ExpectedRevision : int)<suspends>:logic =
        Query := coach_geometry_query{}
        var MatchedPrevious : logic = false
        for (Attempt := 0..5):
            if (Attempt = 0):
                Sleep(0.0)
            else:
                Sleep(0.03)
            if (not CombatReady()? or Piece.Kind <> coach_piece_kind.Wall or not IsTrackedPiece(Piece)? or Piece.Encounter <> Encounter or Piece.Revision <> ExpectedRevision or not PiecePlacementCurrent(Piece)?):
                return false
            if (Root := GetSimulationEntity[]):
                Matched := Query.WallMatchesShape(Root, Piece.Position, Piece.Yaw, Piece.Shape)
                if (Matched? and MatchedPrevious?):
                    return true
                set MatchedPrevious = Matched
            else:
                return false
        Print("PCL|structure|wall_shape_query_not_confirmed|revision={ExpectedRevision}", ?Duration := 0.0)
        return false

    BuilderCanReach(Position : vector3)<transacts>:logic =
        if (Owner := BuilderAgent?, Character := Owner.GetFortCharacter[], Character.IsActive[], Distance(Character.GetTransform().Translation, Position) <= 850.0):
            return true
        return false

    ShapeMesh(Kind : coach_piece_kind, Shape : coach_piece_shape)<transacts>:?mesh =
        if (Kind = coach_piece_kind.Wall):
            if (Shape = coach_piece_shape.Solid):
                return option{WallSolidMesh}
            if (Shape = coach_piece_shape.Window):
                return option{WallWindowMesh}
            if (Shape = coach_piece_shape.Door):
                return option{WallExitMesh}
            if (Shape = coach_piece_shape.SidePassage):
                return option{Art.TeachingKit.PCL_SM_TeachingWallSide_asset}
        else if (Kind = coach_piece_kind.FloorPiece):
            if (Shape = coach_piece_shape.Solid):
                return option{Art.GridKit.PCL_SM_GridFloor_asset}
            if (Shape = coach_piece_shape.FloorHalf):
                return option{Art.GridKit.PCL_SM_GridFloorHalf_asset}
        else if (Kind = coach_piece_kind.Ramp):
            if (Shape = coach_piece_shape.Solid):
                return option{Art.GridKit.PCL_SM_GridRamp_asset}
            if (Shape = coach_piece_shape.RampHalf):
                return option{Art.GridKit.PCL_SM_GridRampHalf_asset}
        else if (Kind = coach_piece_kind.Cone):
            if (Shape = coach_piece_shape.Solid):
                return option{Art.GridKit.PCL_SM_GridCone_asset}
            if (Shape = coach_piece_shape.ConeRaised):
                return option{Art.TeachingKit.PCL_SM_TeachingConeRaisedLeft_asset}
        return false

    # A conservative capsule envelope prevents closing a tracked opening over a pawn.
    PawnInsidePiece(Piece : coach_live_piece, Position : vector3)<transacts>:logic =
        Pose := Piece.Prop.GetTransform()
        Local := Pose.Rotation.UnrotateVector(Position - Pose.Translation)
        if (Piece.Kind = coach_piece_kind.Wall):
            if (Abs(Local.X) < 315.0 and Abs(Local.Y) < 95.0 and Local.Z > -220.0 and Local.Z < 480.0):
                return true
        else if (Abs(Local.X) < 315.0 and Local.Y > -60.0 and Local.Y < 572.0):
            if (Piece.Kind = coach_piece_kind.FloorPiece):
                if (Local.Z > -220.0 and Local.Z < 115.0):
                    return true
            else if (Local.Z > -220.0 and Local.Z < 480.0):
                return true
        return false

    ResetWouldEnclosePawn(Piece : coach_live_piece)<transacts>:logic =
        if (Owner := BuilderAgent?, Character := Owner.GetFortCharacter[], Character.IsActive[], PawnInsidePiece(Piece, Character.GetTransform().Translation)?):
            return true
        for (Player : GetPlayspace().GetPlayers(), Character := Player.GetFortCharacter[], Character.IsActive[], PawnInsidePiece(Piece, Character.GetTransform().Translation)?):
            return true
        return false

    SetShape(Piece : coach_live_piece, Shape : coach_piece_shape, ExpectedRevision : int):coach_build_outcome =
        if (not IsTrackedPiece(Piece)? or Piece.Encounter <> Encounter or Piece.Revision <> ExpectedRevision):
            return coach_build_outcome.Stale
        if (Lease := Piece.NativeLease?):
            if (not UseNativePiecePool? or not NativePool.Contains(Lease)? or Lease.State <> coach_pool_piece_state.Active or Lease.Encounter <> Encounter):
                return coach_build_outcome.Stale
        else if (UseNativePiecePool?):
            return coach_build_outcome.Stale
        if (not Piece.Prop.IsValid[]):
            return coach_build_outcome.AssetUnavailable
        if (not CombatReady()?):
            return coach_build_outcome.InteroperabilityUnverified
        if (not PiecePlacementCurrent(Piece)?):
            return coach_build_outcome.Stale
        if (not Piece.Prop.CanBeDamaged?):
            return coach_build_outcome.AssetUnavailable
        if (not BuilderCanReach(Piece.Position)?):
            return coach_build_outcome.OutOfReach
        if (NextMesh := ShapeMesh(Piece.Kind, Shape)?):
            if (Piece.Shape = Shape):
                return coach_build_outcome.Applied
            Now := GetSimulationElapsedTime()
            if (Now - Piece.LastEditAt < 0.12):
                return coach_build_outcome.Cooldown
            # Distinct openings are not ordered subsets: changing a door to a
            # window can add geometry even though neither shape is named Solid.
            var AddsGeometry : logic = logic{Shape = coach_piece_shape.Solid or Shape = coach_piece_shape.ConeRaised}
            if (Piece.Shape <> coach_piece_shape.Solid):
                set AddsGeometry = true
            if (AddsGeometry?, ResetWouldEnclosePawn(Piece)?):
                return coach_build_outcome.Occupied
            Piece.Prop.SetMesh(NextMesh)
            set Piece.Shape = Shape
            set Piece.Revision += 1
            set Piece.LastEditAt = Now
            return coach_build_outcome.Applied
        return coach_build_outcome.InvalidShape

    StartDemo(Player : player):?vector3 =
        if (Existing := Demonstrations[Player], Existing.IsValid[]):
            return option{Existing.GetTransform().Translation}
        for (Index -> Prop : array{DemoOne, DemoTwo}, Prop.IsValid[]):
            if (not DemoOwners[Index], set DemoOwners[Index] = Player, set Demonstrations[Player] = Prop):
                Prop.Show()
                return option{Prop.GetTransform().Translation}
        Print("PCL|lesson|demo_spawn_unconfirmed", ?Duration := 0.0)
        return false

    ApplyDemoStep(Player : player, Lesson : int, Step : int):void =
        if (Prop := Demonstrations[Player], Prop.IsValid[]):
            if (Lesson = 2):
                Prop.Hide()
                return
            Prop.Show()
            if (Step = 1 or Step = 3):
                Prop.SetMesh(Art.TrainingKit.PCL_SM_WallWindow_asset)
                Prop.SetMaterial(Art.PCL_MI_Cyan{})
            else:
                Prop.SetMesh(Art.TrainingKit.PCL_SM_WallSolid_asset)
                Prop.SetMaterial(Art.PCL_MI_White{})

    EndDemo(Player : player):void =
        if (Prop := Demonstrations[Player], Prop.IsValid[]):
            Prop.Hide()
        var Remaining : [player]creative_prop = map{}
        for (Other -> Prop : Demonstrations, Other <> Player):
            if (set Remaining[Other] = Prop) {}
        set Demonstrations = Remaining
        var Owners : [int]player = map{}
        for (Index -> Other : DemoOwners, Other <> Player):
            if (set Owners[Index] = Other) {}
        set DemoOwners = Owners
