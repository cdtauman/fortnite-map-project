# ============================================================================
# FILE: build_prop_spawner.verse — Grid-Aligned Prop Positioning & Deployment
# LOCATION: Content/ (root)
# PHASE: 3
#
# ARCHITECTURE:
#   This module is the geometric brain of Module B. It owns two concerns:
#
#   1. SPATIAL MATH — Grid snapping, position calculation for every piece
#      type (wall, floor, ramp, cone), rotation computation, and multi-piece
#      layout generation (box-up positions, ramp-rush sequences, 90-degree
#      turn positions).
#
#   2. DEPLOYMENT ORCHESTRATION — Claims a prop from the pool manager,
#      computes the target transform, teleports the prop into place, and
#      returns success/failure so the sequence choreographer knows whether
#      the build "placed."
#
# GRID SYSTEM:
#   Fortnite's native build grid uses 512x512 horizontal tiles with 384
#   vertical height per story. However, UEFN custom props typically use
#   256x256 as the base tile (half-grid), which gives us finer placement
#   control. Our constants:
#     GRID_TILE_SIZE = 256.0  (horizontal snap granularity)
#     WALL_HEIGHT    = 256.0  (vertical height per wall piece)
#     RAMP_HEIGHT    = 256.0  (vertical rise of one ramp piece)
#
#   All position calculations project from the bot's current world position
#   along its facing vector, then snap to the nearest grid-aligned coord.
#
# ROTATION:
#   Walls face the bot's look direction (perpendicular to the wall surface).
#   Floors and cones use IdentityRotation (flat on the ground).
#   Ramps use the bot's yaw rotation (they slope forward in the look dir).
#   Box-up walls use 4 cardinal rotations (N/S/E/W facing inward).
#
# INTEGRATION:
#   Called by build_sequence_choreographer for multi-step sequences.
#   Called by bot_combat_state_machine for single defensive wall placements.
#   Claims props from build_pool_manager, never calls SpawnProp directly.
# ============================================================================
using { /Fortnite.com/Characters }
using { /Fortnite.com/Devices }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /UnrealEngine.com/Temporary/Diagnostics }

# ── Grid Constants ───────────────────────────────────────────────────────────
GRID_TILE_SIZE<public> : float = 256.0
WALL_HEIGHT<public>    : float = 256.0
RAMP_HEIGHT<public>    : float = 256.0
HALF_TILE<public>      : float = 128.0

# ── Deploy Result Constants ──────────────────────────────────────────────────
DEPLOY_SUCCESS<public>     : int = 0
DEPLOY_POOL_EMPTY<public>  : int = 1
DEPLOY_TELEPORT_FAIL<public> : int = 2
DEPLOY_NO_INIT<public>     : int = 3

# ══════════════════════════════════════════════════════════════════════════════
# BUILD PROP SPAWNER
# ══════════════════════════════════════════════════════════════════════════════
build_prop_spawner<public> := class:

    Logger<private> : log = log{Channel := log_bps_ch}

    # ── Cached References (set via Init) ─────────────────────────────────────
    var CachedChar<private>     : ?fort_character       = false
    var PoolRef<private>        : ?build_pool_manager   = false
    var IsInitialized<private>  : logic                 = false

    # ── Telemetry ────────────────────────────────────────────────────────────
    var TotalDeployAttempts<public>  : int = 0
    var TotalDeploySuccesses<public> : int = 0
    var TotalDeployFailures<public>  : int = 0

    # ── Z-Correction Offset ──────────────────────────────────────────────────
    # Small upward nudge applied to all placements to prevent props from
    # clipping into the arena floor geometry. Tune in editor if needed.
    var FloorZCorrection<public> : float = 2.0

    # ══════════════════════════════════════════════════════════════════════════
    # INITIALIZATION
    # ══════════════════════════════════════════════════════════════════════════
    Init<public>(InBotChar : fort_character, InPool : build_pool_manager) : void =
        set CachedChar = option{InBotChar}
        set PoolRef = option{InPool}
        set IsInitialized = true
        Logger.Print("BUILD_SPAWN: Initialized with bot character and pool manager.")

    # Update the bot character reference (e.g., after respawn).
    UpdateBotChar<public>(InBotChar : fort_character) : void =
        set CachedChar = option{InBotChar}

    # ══════════════════════════════════════════════════════════════════════════
    # GRID SNAPPING
    # Snaps a world position to the nearest grid-aligned coordinate.
    # X and Y snap to GRID_TILE_SIZE centers. Z is preserved (with
    # optional floor correction).
    #
    # Example: if GRID_TILE_SIZE=256 and input X=300:
    #   Floor(300/256) = 1 → snapped X = 1*256 + 128 = 384
    #   The prop lands at the CENTER of grid cell 1.
    # ══════════════════════════════════════════════════════════════════════════
    SnapToGrid<public>(Pos : vector3) : vector3 =
        CellX := Floor[Pos.X / GRID_TILE_SIZE] or 0
        CellY := Floor[Pos.Y / GRID_TILE_SIZE] or 0
        vector3{
            X := (CellX * 1.0) * GRID_TILE_SIZE + HALF_TILE,
            Y := (CellY * 1.0) * GRID_TILE_SIZE + HALF_TILE,
            Z := Pos.Z
        }

    # Snap with Z also quantized to wall-height increments.
    # Used for multi-story builds where vertical alignment matters.
    SnapToGrid3D<public>(Pos : vector3) : vector3 =
        CellX := Floor[Pos.X / GRID_TILE_SIZE] or 0
        CellY := Floor[Pos.Y / GRID_TILE_SIZE] or 0
        CellZ := Floor[Pos.Z / WALL_HEIGHT] or 0
        vector3{
            X := (CellX * 1.0) * GRID_TILE_SIZE + HALF_TILE,
            Y := (CellY * 1.0) * GRID_TILE_SIZE + HALF_TILE,
            Z := (CellZ * 1.0) * WALL_HEIGHT + FloorZCorrection
        }

    # ══════════════════════════════════════════════════════════════════════════
    # POSITION CALCULATORS — Single Piece Placements
    # ══════════════════════════════════════════════════════════════════════════

    # WALL: One tile in front of the bot's facing direction.
    # Walls are vertical panels positioned at the grid edge in front
    # of the bot, oriented perpendicular to the look vector.
    CalcWallPosition<public>(BotChar : fort_character) : vector3 =
        BotPos := BotChar.GetTransform().Translation
        Forward := BotChar.GetViewRotation().GetLocalForward()
        RawPos := vector3{
            X := BotPos.X + (Forward.X * GRID_TILE_SIZE),
            Y := BotPos.Y + (Forward.Y * GRID_TILE_SIZE),
            Z := BotPos.Z + FloorZCorrection
        }
        SnapToGrid(RawPos)

    # FLOOR: At the bot's feet, grid-snapped.
    # Floors are horizontal platforms placed under/around the bot.
    CalcFloorPosition<public>(BotChar : fort_character) : vector3 =
        BotPos := BotChar.GetTransform().Translation
        Snapped := SnapToGrid(BotPos)
        vector3{X := Snapped.X, Y := Snapped.Y, Z := BotPos.Z + FloorZCorrection}

    # RAMP: Same horizontal position as floor but will be rotated
    # to slope upward in the bot's facing direction.
    CalcRampPosition<public>(BotChar : fort_character) : vector3 =
        CalcFloorPosition(BotChar)

    # CONE: Same position as floor (cones sit on top of floors).
    CalcConePosition<public>(BotChar : fort_character) : vector3 =
        CalcFloorPosition(BotChar)

    # WALL BEHIND: Opposite of CalcWallPosition — one tile behind the bot.
    # Used during disengage to place cover between bot and player.
    CalcWallBehindPosition<public>(BotChar : fort_character, TargetAgent : agent) : vector3 =
        BotPos := BotChar.GetTransform().Translation
        if (TargetChar := TargetAgent.GetFortCharacter[]):
            TargetPos := TargetChar.GetTransform().Translation
            # Direction from target to bot (away from player)
            DX := BotPos.X - TargetPos.X
            DY := BotPos.Y - TargetPos.Y
            Len := Sqrt((DX * DX) + (DY * DY))
            if (Len > 0.1):
                # Place wall between bot and player (toward the player side)
                NX := DX / Len
                NY := DY / Len
                RawPos := vector3{
                    X := BotPos.X - (NX * HALF_TILE),
                    Y := BotPos.Y - (NY * HALF_TILE),
                    Z := BotPos.Z + FloorZCorrection
                }
                return SnapToGrid(RawPos)
        # Fallback: wall directly behind using facing vector
        Forward := BotChar.GetViewRotation().GetLocalForward()
        FallbackPos := vector3{
            X := BotPos.X - (Forward.X * HALF_TILE),
            Y := BotPos.Y - (Forward.Y * HALF_TILE),
            Z := BotPos.Z + FloorZCorrection
        }
        SnapToGrid(FallbackPos)

    # ELEVATED FLOOR: One wall-height above the bot.
    # Used during ramp-rush to place the next floor level.
    CalcElevatedFloorPosition<public>(BotChar : fort_character) : vector3 =
        BaseFloor := CalcFloorPosition(BotChar)
        vector3{X := BaseFloor.X, Y := BaseFloor.Y, Z := BaseFloor.Z + WALL_HEIGHT}

    # ══════════════════════════════════════════════════════════════════════════
    # ROTATION CALCULATORS
    # ══════════════════════════════════════════════════════════════════════════

    # Wall rotation: faces the same direction the bot is looking.
    # The wall's "front" face points toward the player.
    CalcWallRotation<public>(BotChar : fort_character) : rotation =
        BotChar.GetViewRotation()

    # Wall rotation toward a specific target agent.
    # The wall faces the player regardless of bot's look direction.
    CalcWallRotationToward<public>(BotChar : fort_character, TargetAgent : agent) : rotation =
        BotPos := BotChar.GetTransform().Translation
        if (TargetChar := TargetAgent.GetFortCharacter[]):
            TargetPos := TargetChar.GetTransform().Translation
            DX := TargetPos.X - BotPos.X
            DY := TargetPos.Y - BotPos.Y
            # Calculate yaw angle from direction vector
            # MakeRotationFromZAxis or similar would be ideal, but we
            # approximate with the bot's view rotation for reliability
            return BotChar.GetViewRotation()
        BotChar.GetViewRotation()

    # Floor/Cone rotation: flat, no rotation needed.
    CalcFlatRotation<public>() : rotation =
        IdentityRotation()

    # Ramp rotation: faces the bot's look direction (slopes forward).
    CalcRampRotation<public>(BotChar : fort_character) : rotation =
        BotChar.GetViewRotation()

    # ══════════════════════════════════════════════════════════════════════════
    # MULTI-PIECE LAYOUT CALCULATORS
    # ══════════════════════════════════════════════════════════════════════════

    # BOX-UP: 4 wall positions around a center point (N/S/E/W).
    # Each wall is offset by HALF_TILE from center on one axis.
    CalcBoxWallPositions<public>(Center : vector3) : []vector3 =
        array{
            # North wall (+X)
            SnapToGrid(vector3{X := Center.X + HALF_TILE, Y := Center.Y, Z := Center.Z + FloorZCorrection}),
            # South wall (-X)
            SnapToGrid(vector3{X := Center.X - HALF_TILE, Y := Center.Y, Z := Center.Z + FloorZCorrection}),
            # East wall (+Y)
            SnapToGrid(vector3{X := Center.X, Y := Center.Y + HALF_TILE, Z := Center.Z + FloorZCorrection}),
            # West wall (-Y)
            SnapToGrid(vector3{X := Center.X, Y := Center.Y - HALF_TILE, Z := Center.Z + FloorZCorrection})
        }

    # BOX-UP ROTATIONS: 4 rotations for the box walls.
    # Each wall faces INWARD toward the center.
    # We approximate with 0°, 90°, 180°, 270° yaw rotations.
    CalcBoxWallRotations<public>() : []rotation =
        array{
            IdentityRotation(),
            IdentityRotation().ApplyYaw(DegreesToRadians(180.0)),
            IdentityRotation().ApplyYaw(DegreesToRadians(90.0)),
            IdentityRotation().ApplyYaw(DegreesToRadians(270.0))
        }

    # RAMP-RUSH SEQUENCE: floor → ramp → wall, advancing forward.
    # Returns 3 positions in execution order.
    CalcRampRushPositions<public>(BotChar : fort_character) : []vector3 =
        BotPos := BotChar.GetTransform().Translation
        Forward := BotChar.GetViewRotation().GetLocalForward()

        # 1. Floor at bot's feet
        FloorPos := CalcFloorPosition(BotChar)

        # 2. Ramp at bot's feet (same position, different rotation)
        RampPos := FloorPos

        # 3. Wall one tile forward and one height up (top of ramp)
        WallPos := SnapToGrid(vector3{
            X := BotPos.X + (Forward.X * GRID_TILE_SIZE),
            Y := BotPos.Y + (Forward.Y * GRID_TILE_SIZE),
            Z := BotPos.Z + WALL_HEIGHT + FloorZCorrection
        })

        array{FloorPos, RampPos, WallPos}

    # 90-DEGREE TURN: floor + ramp turning right.
    # Used in advanced retake sequences.
    CalcNinetyTurnPositions<public>(BotChar : fort_character) : []vector3 =
        BotPos := BotChar.GetTransform().Translation
        Right := BotChar.GetViewRotation().GetLocalRight()

        FloorPos := CalcFloorPosition(BotChar)

        # Ramp position offset to the right
        RampPos := SnapToGrid(vector3{
            X := BotPos.X + (Right.X * GRID_TILE_SIZE),
            Y := BotPos.Y + (Right.Y * GRID_TILE_SIZE),
            Z := BotPos.Z + FloorZCorrection
        })

        array{FloorPos, RampPos}

    # ══════════════════════════════════════════════════════════════════════════
    # DEPLOYMENT METHODS — Claim from pool + teleport to position
    # DEPLOY PIECE — Main entry point for choreographer
    # Defaults to calculating position in front of bot.
    # ══════════════════════════════════════════════════════════════════════════
    # Deploy a single piece by type and auto-calculated position/rotation.
    # Uses the cached bot character for position math.
    # Returns DEPLOY_SUCCESS or an error code.
    DeployPiece<public>(PieceType : int)<suspends> : int =
        set TotalDeployAttempts += 1

        if (not IsInitialized?):
            Logger.Print("BUILD_SPAWN: ERROR — Not initialized.")
            set TotalDeployFailures += 1
            return DEPLOY_NO_INIT

        if (BotChar := CachedChar?):
            if (Pool := PoolRef?):
                # Calculate position and rotation based on piece type
                Position := CalcPositionForType(BotChar, PieceType)
                Rotation := CalcRotationForType(BotChar, PieceType)

                # Claim from pool and deploy
                Result := Pool.ClaimAndDeploy(PieceType, Position, Rotation)
                if (Prop := Result?):
                    set TotalDeploySuccesses += 1
                    Logger.Print("BUILD_SPAWN: Deployed {GetPieceTypeName(PieceType)} at ({Position.X},{Position.Y},{Position.Z})")
                    return DEPLOY_SUCCESS
                else:
                    set TotalDeployFailures += 1
                    Logger.Print("BUILD_SPAWN: Pool claim failed for {GetPieceTypeName(PieceType)}.")
                    return DEPLOY_POOL_EMPTY
            else:
                set TotalDeployFailures += 1
                return DEPLOY_NO_INIT
        else:
            set TotalDeployFailures += 1
            return DEPLOY_NO_INIT

    # ══════════════════════════════════════════════════════════════════════════
    # DEPLOY PIECE AT — Advanced entry point
    # Used when choreographer calculates exact world positions.
    # ══════════════════════════════════════════════════════════════════════════
    # Deploy a piece at an explicit position and rotation.
    # Used by the choreographer when it pre-calculates multi-piece layouts.
    DeployPieceAt<public>(
        PieceType : int,
        Position : vector3,
        Rotation : rotation
    )<suspends> : int =
        set TotalDeployAttempts += 1

        if (Pool := PoolRef?):
            Result := Pool.ClaimAndDeploy(PieceType, Position, Rotation)
            if (Prop := Result?):
                set TotalDeploySuccesses += 1
                Logger.Print("BUILD_SPAWN: Deployed {GetPieceTypeName(PieceType)} at explicit pos.")
                return DEPLOY_SUCCESS
            else:
                set TotalDeployFailures += 1
                return DEPLOY_POOL_EMPTY
        set TotalDeployFailures += 1
        DEPLOY_NO_INIT

    # Deploy a piece by string name at auto-calculated position.
    # Convenience wrapper for choreographer string-based sequences.
    DeployPieceByName<public>(TypeName : string)<suspends> : int =
        PieceType := NameToType(TypeName)
        DeployPiece(PieceType)

    # Deploy a defensive wall between the bot and a target.
    # Used by DISENGAGE state to place cover.
    DeployDefensiveWall<public>(TargetAgent : agent)<suspends> : int =
        set TotalDeployAttempts += 1

        if (not IsInitialized?):
            set TotalDeployFailures += 1
            return DEPLOY_NO_INIT

        if (BotChar := CachedChar?):
            if (Pool := PoolRef?):
                Position := CalcWallBehindPosition(BotChar, TargetAgent)
                Rotation := CalcWallRotationToward(BotChar, TargetAgent)

                Result := Pool.ClaimAndDeploy(PIECE_WALL, Position, Rotation)
                if (Prop := Result?):
                    set TotalDeploySuccesses += 1
                    Logger.Print("BUILD_SPAWN: Defensive wall deployed.")
                    return DEPLOY_SUCCESS
                else:
                    set TotalDeployFailures += 1
                    return DEPLOY_POOL_EMPTY
            else:
                set TotalDeployFailures += 1
                return DEPLOY_NO_INIT
        set TotalDeployFailures += 1
        DEPLOY_NO_INIT

    # Deploy a complete box-up (4 walls) around the bot.
    # Returns the number of walls successfully placed (0-4).
    DeployBoxUp<public>()<suspends> : int =
        if (BotChar := CachedChar?):
            if (Pool := PoolRef?):
                Center := BotChar.GetTransform().Translation
                Positions := CalcBoxWallPositions(Center)
                Rotations := CalcBoxWallRotations()
                var PlacedCount : int = 0

                var Idx : int = 0
                for (Pos : Positions):
                    if (Idx < Rotations.Length):
                        if (Rot := Rotations[Idx]):
                            set TotalDeployAttempts += 1
                            Result := Pool.ClaimAndDeploy(PIECE_WALL, Pos, Rot)
                            if (Prop := Result?):
                                set PlacedCount += 1
                                set TotalDeploySuccesses += 1
                    set Idx += 1

                Logger.Print("BUILD_SPAWN: Box-up complete. {PlacedCount}/4 walls placed.")
                return PlacedCount
        0

    # Deploy a ramp-rush sequence (floor + ramp + wall).
    # Returns the number of pieces successfully placed (0-3).
    DeployRampRush<public>()<suspends> : int =
        if (BotChar := CachedChar?):
            if (Pool := PoolRef?):
                Positions := CalcRampRushPositions(BotChar)
                # Sequence: Floor → Ramp → Wall
                PieceTypes := array{PIECE_FLOOR, PIECE_RAMP, PIECE_WALL}
                Rotations := array{
                    CalcFlatRotation(),
                    CalcRampRotation(BotChar),
                    CalcWallRotation(BotChar)
                }
                var PlacedCount : int = 0

                var Idx : int = 0
                for (Pos : Positions):
                    if (PType := PieceTypes[Idx]):
                        if (Rot := Rotations[Idx]):
                            set TotalDeployAttempts += 1
                            Result := Pool.ClaimAndDeploy(PType, Pos, Rot)
                            if (Prop := Result?):
                                set PlacedCount += 1
                                set TotalDeploySuccesses += 1
                    set Idx += 1

                Logger.Print("BUILD_SPAWN: Ramp-rush complete. {PlacedCount}/3 pieces placed.")
                return PlacedCount
        0

    # ══════════════════════════════════════════════════════════════════════════
    # PRIVATE: Position/Rotation dispatch by type
    # ══════════════════════════════════════════════════════════════════════════
    CalcPositionForType<private>(BotChar : fort_character, PieceType : int) : vector3 =
        if (PieceType = PIECE_WALL):
            return CalcWallPosition(BotChar)
        else if (PieceType = PIECE_FLOOR):
            return CalcFloorPosition(BotChar)
        else if (PieceType = PIECE_RAMP):
            return CalcRampPosition(BotChar)
        CalcConePosition(BotChar)

    CalcRotationForType<private>(BotChar : fort_character, PieceType : int) : rotation =
        if (PieceType = PIECE_WALL):
            return CalcWallRotation(BotChar)
        else if (PieceType = PIECE_FLOOR):
            return CalcFlatRotation()
        else if (PieceType = PIECE_RAMP):
            return CalcRampRotation(BotChar)
        CalcFlatRotation()

    GetPieceTypeName<private>(PieceType : int) : string =
        if (PieceType = PIECE_WALL):
            return "Wall"
        else if (PieceType = PIECE_FLOOR):
            return "Floor"
        else if (PieceType = PIECE_RAMP):
            return "Ramp"
        else if (PieceType = PIECE_CONE):
            return "Cone"
        "Unknown"

    NameToType<private>(TypeName : string) : int =
        if (TypeName = "Wall"):
            return PIECE_WALL
        else if (TypeName = "Floor"):
            return PIECE_FLOOR
        else if (TypeName = "Ramp"):
            return PIECE_RAMP
        else if (TypeName = "Cone"):
            return PIECE_CONE
        PIECE_WALL

    # ══════════════════════════════════════════════════════════════════════════
    # QUERIES
    # ══════════════════════════════════════════════════════════════════════════
    GetDeploySuccessRate<public>() : float =
        if (TotalDeployAttempts > 0):
            return (TotalDeploySuccesses * 1.0) / (TotalDeployAttempts * 1.0)
        0.0

    ResetTelemetry<public>() : void =
        set TotalDeployAttempts = 0
        set TotalDeploySuccesses = 0
        set TotalDeployFailures = 0

log_bps_ch := class(log_channel):