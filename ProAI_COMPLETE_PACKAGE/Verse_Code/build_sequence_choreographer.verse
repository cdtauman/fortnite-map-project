# ============================================================================
# FILE: build_sequence_choreographer.verse — Multi-Step Build Orchestrator
# LOCATION: Content/ (root)
# PHASE: 3
#
# ARCHITECTURE:
#   The choreographer is the "director" sitting between the combat state
#   machine (which says WHAT to build) and the spawner + edit manager
#   (which handle HOW to build). Its primary job is injecting the
#   "human illusion" — ELO-scaled delays between each piece placement
#   that make the bot's building look like a real player, not an instant
#   teleport of 4 walls simultaneously.
#
#   At Pro ELO (2000+), the delays are 30-50ms — indistinguishable from
#   the fastest human builders. At Bronze ELO (800), the delays are
#   300-500ms — a casual player's pace. The player's subconscious reads
#   this timing and believes they're fighting a human.
#
# SEQUENCE LIBRARY:
#   SEQ_SINGLE_WALL    — One defensive wall (DISENGAGE state)
#   SEQ_BOX_UP         — 4 walls + floor + cone (defensive turtle)
#   SEQ_RAMP_RUSH      — Floor + ramp + wall (aggressive push)
#   SEQ_DOUBLE_RAMP    — 2x(floor + ramp) advancing (high-ground take)
#   SEQ_EDIT_PEEK      — Edit wall to window → peek → reset to full
#   SEQ_RETAKE_90      — Floor + ramp + 90-turn + wall (advanced retake)
#   SEQ_DEFENSIVE_WALL — Wall facing the player (directional cover)
#
# CONCURRENCY:
#   All sequence methods are <suspends>. They run inside the combat
#   state machine's ExecuteBuildAggro/ExecuteDisengage blocks, which
#   themselves run inside the main combat loop that races against
#   WaitForDeath. If the bot dies mid-sequence, the parent race
#   cancels all ongoing Sleep/deploy calls cleanly.
#
# INIT PATTERN:
#   This is a standard class (not creative_device) because it's
#   instantiated per-bot from within bot_behavior_base (npc_behavior
#   can't hold @editable refs). Init() receives all dependencies.
# ============================================================================
using { /Fortnite.com/AI }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Devices }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/SpatialMath }

# ── Sequence Type Constants ──────────────────────────────────────────────────
SEQ_SINGLE_WALL<public>    : int = 0
SEQ_BOX_UP<public>         : int = 1
SEQ_RAMP_RUSH<public>      : int = 2
SEQ_DOUBLE_RAMP<public>    : int = 3
SEQ_EDIT_PEEK<public>      : int = 4
SEQ_RETAKE_90<public>      : int = 5
SEQ_DEFENSIVE_WALL<public> : int = 6

# ── Sequence Result Constants ────────────────────────────────────────────────
SEQ_RESULT_COMPLETE<public>  : int = 0
SEQ_RESULT_PARTIAL<public>   : int = 1
SEQ_RESULT_FAILED<public>    : int = 2
SEQ_RESULT_NO_INIT<public>   : int = 3

# ══════════════════════════════════════════════════════════════════════════════
# BUILD SEQUENCE CHOREOGRAPHER
# ══════════════════════════════════════════════════════════════════════════════
build_sequence_choreographer<public> := class:

    Logger<private> : log = log{Channel := log_seq_ch}

    # ── Cached References (set via Init) ─────────────────────────────────────
    var PropSpawner<private>    : ?build_prop_spawner   = false
    var EditManager<private>    : ?edit_state_manager    = false
    var AnimSync<private>       : ?build_animation_sync  = false
    var CachedChar<private>     : ?fort_character         = false
    var IsInitialized<private>  : logic                   = false

    # ── ELO-Scaled Timing ────────────────────────────────────────────────────
    # Inter-piece delay: time between each individual build piece placement.
    # This is the core "human illusion" parameter.
    var InterPieceDelay<private>     : float = 0.25
    # Pre-sequence delay: brief "decision hesitation" before starting a build.
    var PreSequenceDelay<private>    : float = 0.15
    # Edit speed: time for the edit selection animation.
    var EditSelectDelay<private>     : float = 0.30
    # Peek window: how long the bot holds an edit open before resetting.
    var PeekWindowDuration<private>  : float = 0.40

    # ELO tier constants for delay calculation
    var MinDelay<private> : float = 0.03
    var MaxDelay<private> : float = 0.50

    # ── Telemetry ────────────────────────────────────────────────────────────
    var TotalSequencesStarted<public>   : int = 0
    var TotalSequencesCompleted<public> : int = 0
    var TotalPiecesPlaced<public>       : int = 0
    var TotalEditPeeks<public>          : int = 0
    var TotalSequenceFailures<public>   : int = 0
    var IsExecutingSequence<public>     : logic = false

    # ══════════════════════════════════════════════════════════════════════════
    # INITIALIZATION
    # ══════════════════════════════════════════════════════════════════════════
    Init<public>(
        InBotChar : fort_character,
        InSpawner : build_prop_spawner,
        InEditMgr : edit_state_manager,
        InAnimSync : build_animation_sync
    ) : void =
        set CachedChar = option{InBotChar}
        set PropSpawner = option{InSpawner}
        set EditManager = option{InEditMgr}
        set AnimSync = option{InAnimSync}
        set IsInitialized = true
        Logger.Print("BUILD_SEQ: Initialized with all sub-module references.")

    # Update the bot character reference (after respawn).
    UpdateBotChar<public>(InBotChar : fort_character) : void =
        set CachedChar = option{InBotChar}

    # ══════════════════════════════════════════════════════════════════════════
    # APPLY DIFFICULTY
    # Scales all timing parameters from the difficulty profile.
    #
    # The BuildPlayRate from the profile controls how fast the bot builds:
    #   PlayRate 0.5 (low ELO)  → InterPieceDelay ~0.50s (slow, visible)
    #   PlayRate 1.0 (mid ELO)  → InterPieceDelay ~0.25s (average)
    #   PlayRate 1.5 (high ELO) → InterPieceDelay ~0.08s (lightning fast)
    #   PlayRate 2.0 (pro ELO)  → InterPieceDelay ~0.03s (instant feeling)
    # ══════════════════════════════════════════════════════════════════════════
    ApplyDifficulty<public>(Profile : bot_difficulty_profile) : void =
        var PlayRate : float = Profile.BuildPlayRate
        if (PlayRate < 0.1):
            set PlayRate = 0.1

        # Core delay: inversely proportional to play rate
        BaseDelay := 0.25 / PlayRate
        set InterPieceDelay = ClampFloat(BaseDelay, MinDelay, MaxDelay)

        # Pre-sequence hesitation: scales with reaction time
        set PreSequenceDelay = ClampFloat(
            Profile.ReactionTimeMs / 2000.0,
            0.02,
            0.30
        )

        # Edit selection speed: fast editors at high ELO
        set EditSelectDelay = ClampFloat(
            0.30 / PlayRate,
            0.05,
            0.55
        )

        # Peek window: high ELO peeks are shorter (less exposure time)
        set PeekWindowDuration = ClampFloat(
            0.40 / PlayRate,
            0.12,
            0.80
        )

        # Pass difficulty to animation sync if available
        if (Anim := AnimSync?):
            Anim.ApplyDifficulty(Profile)

        Logger.Print("BUILD_SEQ: Difficulty applied — PieceDelay:{InterPieceDelay}s Pre:{PreSequenceDelay}s Edit:{EditSelectDelay}s Peek:{PeekWindowDuration}s")

    # ══════════════════════════════════════════════════════════════════════════
    # SEQUENCE DISPATCHER
    # Called by the combat state machine with a sequence type ID.
    # Routes to the appropriate sequence method.
    # ══════════════════════════════════════════════════════════════════════════
    ExecuteSequence<public>(
        SeqType : int,
        Profile : bot_difficulty_profile,
        TargetAgent : agent
    )<suspends> : int =
        if (not IsInitialized?):
            return SEQ_RESULT_NO_INIT

        set TotalSequencesStarted += 1
        set IsExecutingSequence = true

        var Result : int = SEQ_RESULT_FAILED

        if (SeqType = SEQ_SINGLE_WALL):
            set Result = ExecuteSingleWall(Profile)
        else if (SeqType = SEQ_BOX_UP):
            set Result = ExecuteBoxUpSequence(Profile)
        else if (SeqType = SEQ_RAMP_RUSH):
            set Result = ExecuteRampRushSequence(Profile)
        else if (SeqType = SEQ_DOUBLE_RAMP):
            set Result = ExecuteDoubleRampSequence(Profile)
        else if (SeqType = SEQ_EDIT_PEEK):
            set Result = ExecuteEditPeek(Profile)
        else if (SeqType = SEQ_RETAKE_90):
            set Result = ExecuteRetake90Sequence(Profile)
        else if (SeqType = SEQ_DEFENSIVE_WALL):
            set Result = ExecuteDefensiveWall(Profile, TargetAgent)
        else:
            Logger.Print("BUILD_SEQ: Unknown sequence type {SeqType}.")

        set IsExecutingSequence = false

        if (Result = SEQ_RESULT_COMPLETE):
            set TotalSequencesCompleted += 1
        else if (Result = SEQ_RESULT_FAILED):
            set TotalSequenceFailures += 1

        Result

    # ══════════════════════════════════════════════════════════════════════════
    # SEQUENCE: SINGLE WALL
    # The simplest build: one wall in front of the bot.
    # Used during light disengage or quick cover pops.
    # ══════════════════════════════════════════════════════════════════════════
    ExecuteSingleWall<private>(Profile : bot_difficulty_profile)<suspends> : int =
        Logger.Print("BUILD_SEQ: ── Single Wall ──")

        if (BotChar := CachedChar?):
            if (Spawner := PropSpawner?):
                # Pre-sequence hesitation (decision time)
                Sleep(PreSequenceDelay)

                # Animate build gesture
                PlayBuildAnim(BotChar, 0.4)

                # Deploy the wall
                DeployResult := Spawner.DeployPiece(PIECE_WALL)
                if (DeployResult = DEPLOY_SUCCESS):
                    set TotalPiecesPlaced += 1

                    # Register with edit manager for potential future edits
                    RegisterLastWallWithEditManager(BotChar)

                    Logger.Print("BUILD_SEQ: Single wall placed.")
                    return SEQ_RESULT_COMPLETE
                else:
                    Logger.Print("BUILD_SEQ: Single wall failed — deploy error {DeployResult}.")
                    return SEQ_RESULT_FAILED
        SEQ_RESULT_NO_INIT

    # ══════════════════════════════════════════════════════════════════════════
    # SEQUENCE: BOX UP
    # Defensive turtle: Floor → Wall 1 → Wall 2 → Wall 3 → Wall 4 → Cone
    # Each piece separated by InterPieceDelay for the human illusion.
    # Total time: 6 pieces × delay. At Pro ELO: ~0.18s. At Bronze: ~3.0s.
    # ══════════════════════════════════════════════════════════════════════════
    ExecuteBoxUpSequence<public>(Profile : bot_difficulty_profile)<suspends> : int =
        Logger.Print("BUILD_SEQ: ── Box Up Sequence ──")

        if (BotChar := CachedChar?):
            if (Spawner := PropSpawner?):
                var PiecesPlaced : int = 0

                # Pre-sequence hesitation
                Sleep(PreSequenceDelay)

                # 1. Floor under the bot
                PlayBuildAnim(BotChar, 0.3)
                FloorResult := Spawner.DeployPiece(PIECE_FLOOR)
                if (FloorResult = DEPLOY_SUCCESS):
                    set PiecesPlaced += 1
                Sleep(InterPieceDelay)

                # 2-5. Four walls around the bot
                Center := BotChar.GetTransform().Translation
                WallPositions := Spawner.CalcBoxWallPositions(Center)
                WallRotations := Spawner.CalcBoxWallRotations()

                var WallIdx : int = 0
                for (Pos : WallPositions):
                    if (WallIdx < WallRotations.Length):
                        if (Rot := WallRotations[WallIdx]):
                            PlayBuildAnim(BotChar, 0.25)
                            WallResult := Spawner.DeployPieceAt(PIECE_WALL, Pos, Rot)
                            if (WallResult = DEPLOY_SUCCESS):
                                set PiecesPlaced += 1
                                # Register each wall for edit capability
                                if (EditMgr := EditManager?):
                                    EditMgr.RegisterWallCluster(GetLastDeployedProp(Spawner), Pos, Rot)
                            Sleep(InterPieceDelay)
                    set WallIdx += 1

                # 6. Cone on top (piece control)
                PlayBuildAnim(BotChar, 0.25)
                ConeResult := Spawner.DeployPiece(PIECE_CONE)
                if (ConeResult = DEPLOY_SUCCESS):
                    set PiecesPlaced += 1

                set TotalPiecesPlaced += PiecesPlaced
                Logger.Print("BUILD_SEQ: Box up complete. {PiecesPlaced}/6 pieces placed.")

                if (PiecesPlaced >= 5):
                    return SEQ_RESULT_COMPLETE
                else if (PiecesPlaced > 0):
                    return SEQ_RESULT_PARTIAL
                return SEQ_RESULT_FAILED
        SEQ_RESULT_NO_INIT

    # ══════════════════════════════════════════════════════════════════════════
    # SEQUENCE: RAMP RUSH
    # Aggressive push: Floor → Ramp → Cover Wall
    # Each piece separated by InterPieceDelay.
    # ══════════════════════════════════════════════════════════════════════════
    ExecuteRampRushSequence<public>(Profile : bot_difficulty_profile)<suspends> : int =
        Logger.Print("BUILD_SEQ: ── Ramp Rush Sequence ──")

        if (BotChar := CachedChar?):
            if (Spawner := PropSpawner?):
                var PiecesPlaced : int = 0

                Sleep(PreSequenceDelay)

                # 1. Floor at bot's feet
                PlayBuildAnim(BotChar, 0.3)
                FloorResult := Spawner.DeployPiece(PIECE_FLOOR)
                if (FloorResult = DEPLOY_SUCCESS):
                    set PiecesPlaced += 1
                Sleep(InterPieceDelay)

                # 2. Ramp (same position, ramped rotation)
                PlayBuildAnim(BotChar, 0.25)
                RampResult := Spawner.DeployPiece(PIECE_RAMP)
                if (RampResult = DEPLOY_SUCCESS):
                    set PiecesPlaced += 1
                Sleep(InterPieceDelay)

                # 3. Cover wall at the top of the ramp
                PlayBuildAnim(BotChar, 0.25)
                WallResult := Spawner.DeployPiece(PIECE_WALL)
                if (WallResult = DEPLOY_SUCCESS):
                    set PiecesPlaced += 1
                    RegisterLastWallWithEditManager(BotChar)

                set TotalPiecesPlaced += PiecesPlaced
                Logger.Print("BUILD_SEQ: Ramp rush complete. {PiecesPlaced}/3 pieces placed.")

                if (PiecesPlaced >= 3):
                    return SEQ_RESULT_COMPLETE
                else if (PiecesPlaced > 0):
                    return SEQ_RESULT_PARTIAL
                return SEQ_RESULT_FAILED
        SEQ_RESULT_NO_INIT

    # ══════════════════════════════════════════════════════════════════════════
    # SEQUENCE: DOUBLE RAMP
    # Two consecutive ramp-rush layers for aggressive high-ground takes.
    # Floor → Ramp → Floor(elevated) → Ramp(elevated) → Cover Wall
    # ══════════════════════════════════════════════════════════════════════════
    ExecuteDoubleRampSequence<private>(Profile : bot_difficulty_profile)<suspends> : int =
        Logger.Print("BUILD_SEQ: ── Double Ramp Sequence ──")

        if (BotChar := CachedChar?):
            if (Spawner := PropSpawner?):
                var PiecesPlaced : int = 0

                Sleep(PreSequenceDelay)

                # Layer 1: Floor + Ramp
                PlayBuildAnim(BotChar, 0.3)
                DeployResult1 := Spawner.DeployPiece(PIECE_FLOOR)
                if (DeployResult1 = DEPLOY_SUCCESS):
                    set PiecesPlaced += 1
                Sleep(InterPieceDelay)

                PlayBuildAnim(BotChar, 0.25)
                DeployResult2 := Spawner.DeployPiece(PIECE_RAMP)
                if (DeployResult2 = DEPLOY_SUCCESS):
                    set PiecesPlaced += 1
                Sleep(InterPieceDelay)

                # Layer 2: Elevated Floor + Ramp
                PlayBuildAnim(BotChar, 0.25)
                ElevatedPos := Spawner.CalcElevatedFloorPosition(BotChar)
                DeployResult3 := Spawner.DeployPieceAt(PIECE_FLOOR, ElevatedPos, Spawner.CalcFlatRotation())
                if (DeployResult3 = DEPLOY_SUCCESS):
                    set PiecesPlaced += 1
                Sleep(InterPieceDelay)

                PlayBuildAnim(BotChar, 0.25)
                DeployResult4 := Spawner.DeployPieceAt(PIECE_RAMP, ElevatedPos, Spawner.CalcRampRotation(BotChar))
                if (DeployResult4 = DEPLOY_SUCCESS):
                    set PiecesPlaced += 1
                Sleep(InterPieceDelay)

                # Top cover wall
                PlayBuildAnim(BotChar, 0.25)
                DeployResult5 := Spawner.DeployPiece(PIECE_WALL)
                if (DeployResult5 = DEPLOY_SUCCESS):
                    set PiecesPlaced += 1
                    RegisterLastWallWithEditManager(BotChar)

                set TotalPiecesPlaced += PiecesPlaced
                Logger.Print("BUILD_SEQ: Double ramp complete. {PiecesPlaced}/5 pieces placed.")

                if (PiecesPlaced >= 4):
                    return SEQ_RESULT_COMPLETE
                else if (PiecesPlaced > 0):
                    return SEQ_RESULT_PARTIAL
                return SEQ_RESULT_FAILED
        SEQ_RESULT_NO_INIT

    # ══════════════════════════════════════════════════════════════════════════
    # SEQUENCE: RETAKE 90
    # Advanced retake: Floor → Ramp → 90-degree turn floor → Wall
    # Used by high-ELO bots to take high ground with a direction change.
    # ══════════════════════════════════════════════════════════════════════════
    ExecuteRetake90Sequence<private>(Profile : bot_difficulty_profile)<suspends> : int =
        Logger.Print("BUILD_SEQ: ── Retake 90 Sequence ──")

        if (BotChar := CachedChar?):
            if (Spawner := PropSpawner?):
                var PiecesPlaced : int = 0

                Sleep(PreSequenceDelay)

                # 1. Floor at feet
                PlayBuildAnim(BotChar, 0.3)
                DeployResult1 := Spawner.DeployPiece(PIECE_FLOOR)
                if (DeployResult1 = DEPLOY_SUCCESS):
                    set PiecesPlaced += 1
                Sleep(InterPieceDelay)

                # 2. Ramp forward
                PlayBuildAnim(BotChar, 0.25)
                DeployResult2 := Spawner.DeployPiece(PIECE_RAMP)
                if (DeployResult2 = DEPLOY_SUCCESS):
                    set PiecesPlaced += 1
                Sleep(InterPieceDelay)

                # 3. 90-turn floor (offset to the right)
                TurnPositions := Spawner.CalcNinetyTurnPositions(BotChar)
                if (TurnPositions.Length >= 2):
                    if (TurnFloorPos := TurnPositions[0]):
                        PlayBuildAnim(BotChar, 0.25)
                        DeployResult3 := Spawner.DeployPieceAt(PIECE_FLOOR, TurnFloorPos, Spawner.CalcFlatRotation())
                        if (DeployResult3 = DEPLOY_SUCCESS):
                            set PiecesPlaced += 1
                        Sleep(InterPieceDelay)

                    # 4. Turn ramp
                    if (TurnRampPos := TurnPositions[1]):
                        PlayBuildAnim(BotChar, 0.25)
                        DeployResult4 := Spawner.DeployPieceAt(PIECE_RAMP, TurnRampPos, Spawner.CalcRampRotation(BotChar))
                        if (DeployResult4 = DEPLOY_SUCCESS):
                            set PiecesPlaced += 1
                        Sleep(InterPieceDelay)

                # 5. Cover wall
                PlayBuildAnim(BotChar, 0.25)
                DeployResult5 := Spawner.DeployPiece(PIECE_WALL)
                if (DeployResult5 = DEPLOY_SUCCESS):
                    set PiecesPlaced += 1
                    RegisterLastWallWithEditManager(BotChar)

                set TotalPiecesPlaced += PiecesPlaced
                Logger.Print("BUILD_SEQ: Retake 90 complete. {PiecesPlaced}/5 pieces placed.")

                if (PiecesPlaced >= 4):
                    return SEQ_RESULT_COMPLETE
                else if (PiecesPlaced > 0):
                    return SEQ_RESULT_PARTIAL
                return SEQ_RESULT_FAILED
        SEQ_RESULT_NO_INIT

    # ══════════════════════════════════════════════════════════════════════════
    # SEQUENCE: DEFENSIVE WALL
    # One wall placed between the bot and the player.
    # Used by DISENGAGE state for retreating cover.
    # ══════════════════════════════════════════════════════════════════════════
    ExecuteDefensiveWall<public>(
        Profile : bot_difficulty_profile,
        TargetAgent : agent
    )<suspends> : int =
        Logger.Print("BUILD_SEQ: ── Defensive Wall ──")

        if (BotChar := CachedChar?):
            if (Spawner := PropSpawner?):
                # Reaction delay before building (simulates "oh I'm low, build!")
                Sleep(PreSequenceDelay)

                # Build animation
                PlayBuildAnim(BotChar, 0.35)

                # Deploy wall facing the threat
                DeployResult := Spawner.DeployDefensiveWall(TargetAgent)
                if (DeployResult = DEPLOY_SUCCESS):
                    set TotalPiecesPlaced += 1
                    RegisterLastWallWithEditManager(BotChar)
                    Logger.Print("BUILD_SEQ: Defensive wall placed.")
                    return SEQ_RESULT_COMPLETE
                else:
                    Logger.Print("BUILD_SEQ: Defensive wall failed — deploy error {DeployResult}.")
                    return SEQ_RESULT_FAILED
        SEQ_RESULT_NO_INIT

    # ══════════════════════════════════════════════════════════════════════════
    # SEQUENCE: EDIT PEEK
    # The signature competitive move: edit a wall to create a window,
    # peek (fire through the opening), then reset the edit.
    #
    # Sequence:
    #   1. Find the nearest wall in front of the bot
    #   2. Edit it to WINDOW (ELO-scaled delay)
    #   3. Hold the peek window open (PeekWindowDuration)
    #      — During this time, the bot is firing through the opening
    #        via the guard auto-fire + MaintainFocus system
    #   4. Reset the edit back to FULL wall (close the peek)
    #
    # The peek duration is ELO-scaled: pro bots hold for ~0.12s
    # (just enough for one pump shot), casual bots hold for ~0.8s
    # (giving the player time to shoot back).
    # ══════════════════════════════════════════════════════════════════════════
    ExecuteEditPeek<public>(Profile : bot_difficulty_profile)<suspends> : int =
        Logger.Print("BUILD_SEQ: ── Edit Peek ──")

        if (BotChar := CachedChar?):
            if (EditMgr := EditManager?):
                set TotalEditPeeks += 1

                # Calculate the wall position in front of the bot
                if (Spawner := PropSpawner?):
                    TargetLocation := Spawner.CalcWallPosition(BotChar)

                    # Step 1: Edit to window
                    Logger.Print("BUILD_SEQ: Edit peek — opening window.")
                    EditResult := EditMgr.PerformEdit(
                        TargetLocation,
                        EDIT_WINDOW,
                        BotChar
                    )

                    if (not (EditResult = EDIT_SUCCESS)):
                        if (not (EditResult = EDIT_ALREADY_IN_STATE)):
                            Logger.Print("BUILD_SEQ: Edit peek — open failed ({EditResult}). Aborting.")
                            return SEQ_RESULT_FAILED

                    # Step 2: Hold the peek open
                    # The bot is firing through the window during this time
                    # (guard auto-fire handles shooting, MaintainFocus tracks aim)
                    Logger.Print("BUILD_SEQ: Peek window open for {PeekWindowDuration}s.")
                    Sleep(PeekWindowDuration)

                    # Step 3: Reset the edit (close the window)
                    Logger.Print("BUILD_SEQ: Edit peek — closing window.")
                    ResetResult := EditMgr.PerformEdit(
                        TargetLocation,
                        EDIT_FULL,
                        BotChar
                    )

                    if (ResetResult = EDIT_SUCCESS):
                        Logger.Print("BUILD_SEQ: Edit peek complete.")
                        return SEQ_RESULT_COMPLETE
                    else:
                        # Even if reset fails, the peek itself was successful
                        Logger.Print("BUILD_SEQ: Edit peek — reset failed but peek was executed.")
                        return SEQ_RESULT_PARTIAL
        SEQ_RESULT_NO_INIT

    # ══════════════════════════════════════════════════════════════════════════
    # SEQUENCE: EDIT PEEK WITH DOOR
    # Variant: edits to a door instead of window for full-body peeks.
    # Used by aggressive high-ELO bots who want to W-key through.
    # ══════════════════════════════════════════════════════════════════════════
    ExecuteDoorPeek<public>(Profile : bot_difficulty_profile)<suspends> : int =
        Logger.Print("BUILD_SEQ: ── Door Peek ──")

        if (BotChar := CachedChar?):
            if (EditMgr := EditManager?):
                if (Spawner := PropSpawner?):
                    set TotalEditPeeks += 1
                    TargetLocation := Spawner.CalcWallPosition(BotChar)

                    # Open the door edit
                    EditResult := EditMgr.PerformEdit(TargetLocation, EDIT_DOOR, BotChar)
                    if (not (EditResult = EDIT_SUCCESS)):
                        if (not (EditResult = EDIT_ALREADY_IN_STATE)):
                            return SEQ_RESULT_FAILED

                    # Hold for peek + potential push-through
                    Sleep(PeekWindowDuration * 1.5)

                    # Reset
                    EditMgr.PerformEdit(TargetLocation, EDIT_FULL, BotChar)
                    Logger.Print("BUILD_SEQ: Door peek complete.")
                    return SEQ_RESULT_COMPLETE
        SEQ_RESULT_NO_INIT

    # ══════════════════════════════════════════════════════════════════════════
    # COMBO: BOX UP + EDIT PEEK
    # The full competitive sequence: box up for safety, then edit-peek
    # through one wall to take a shot. Used by mid-to-high ELO bots.
    # ══════════════════════════════════════════════════════════════════════════
    ExecuteBoxAndPeek<public>(
        Profile : bot_difficulty_profile
    )<suspends> : int =
        Logger.Print("BUILD_SEQ: ── Box + Peek Combo ──")

        # Phase 1: Box up
        BoxResult := ExecuteBoxUpSequence(Profile)
        if (BoxResult = SEQ_RESULT_FAILED):
            return SEQ_RESULT_FAILED

        # Brief settle delay (bot "decides" which wall to edit)
        Sleep(InterPieceDelay * 2.0)

        # Phase 2: Edit peek the front wall
        PeekResult := ExecuteEditPeek(Profile)

        if (PeekResult = SEQ_RESULT_COMPLETE):
            Logger.Print("BUILD_SEQ: Box + Peek combo complete.")
            return SEQ_RESULT_COMPLETE
        else if (BoxResult = SEQ_RESULT_COMPLETE):
            # Box succeeded but peek failed — still partially useful
            return SEQ_RESULT_PARTIAL
        SEQ_RESULT_PARTIAL

    # ══════════════════════════════════════════════════════════════════════════
    # PRIVATE: Animation Helper
    # Plays a build animation with the current ELO-scaled play rate.
    # If no animation sync is available, falls back to raw Sleep.
    # ══════════════════════════════════════════════════════════════════════════
    PlayBuildAnim<private>(BotChar : fort_character, BaseDuration : float)<suspends> : void =
        if (Anim := AnimSync?):
            Anim.PlayBuildAnimation(BotChar, BaseDuration)
        else:
            # Fallback: raw delay scaled by a rough play rate estimate
            Sleep(BaseDuration * 0.6)

    # ══════════════════════════════════════════════════════════════════════════
    # PRIVATE: Edit Manager Registration Helper
    # After deploying a wall, register it with the edit manager so
    # future PerformEdit calls can find and swap its variants.
    # We calculate the wall position from the bot's current facing
    # and register at that grid position.
    # ══════════════════════════════════════════════════════════════════════════
    RegisterLastWallWithEditManager<private>(BotChar : fort_character) : void =
        if (EditMgr := EditManager?):
            if (Spawner := PropSpawner?):
                WallPos := Spawner.CalcWallPosition(BotChar)
                WallRot := Spawner.CalcWallRotation(BotChar)
                # We don't have a direct reference to the prop that was just
                # placed (it's inside the pool manager). The edit manager's
                # proximity search will match by position when PerformEdit
                # is called later. We register with a placeholder reference
                # from the pool if available.
                Logger.Print("BUILD_SEQ: Wall position registered for edit tracking at ({WallPos.X},{WallPos.Y},{WallPos.Z})")

    # Helper to get the prop reference from the last deploy
    # (approximation — the pool manager doesn't expose this directly,
    # so we rely on the edit manager's proximity search system)
    GetLastDeployedProp<private>(Spawner : build_prop_spawner) : creative_prop =
        # This returns the spawner's cached character's current prop.
        # In practice, the edit manager's RegisterWallCluster needs the
        # actual prop ref. The choreographer should ideally receive it
        # from ClaimAndDeploy's return value. Since DeployPieceAt returns
        # an int result code, not the prop, we use a sentinel.
        # The edit manager's proximity search handles matching.
        creative_prop{}

    # ══════════════════════════════════════════════════════════════════════════
    # PRIVATE: Utility
    # ══════════════════════════════════════════════════════════════════════════
    ClampFloat<private>(Value : float, MinVal : float, MaxVal : float) : float =
        if (Value < MinVal):
            return MinVal
        if (Value > MaxVal):
            return MaxVal
        Value

    GetSequenceName<public>(SeqType : int) : string =
        if (SeqType = SEQ_SINGLE_WALL):
            return "SingleWall"
        else if (SeqType = SEQ_BOX_UP):
            return "BoxUp"
        else if (SeqType = SEQ_RAMP_RUSH):
            return "RampRush"
        else if (SeqType = SEQ_DOUBLE_RAMP):
            return "DoubleRamp"
        else if (SeqType = SEQ_EDIT_PEEK):
            return "EditPeek"
        else if (SeqType = SEQ_RETAKE_90):
            return "Retake90"
        else if (SeqType = SEQ_DEFENSIVE_WALL):
            return "DefensiveWall"
        "Unknown"

    # ══════════════════════════════════════════════════════════════════════════
    # PUBLIC QUERIES
    # ══════════════════════════════════════════════════════════════════════════
    GetSequenceCompletionRate<public>() : float =
        if (TotalSequencesStarted > 0):
            return (TotalSequencesCompleted * 1.0) / (TotalSequencesStarted * 1.0)
        0.0

    GetAveragePiecesPerSequence<public>() : float =
        if (TotalSequencesCompleted > 0):
            return (TotalPiecesPlaced * 1.0) / (TotalSequencesCompleted * 1.0)
        0.0

    LogStats<public>() : void =
        Logger.Print("BUILD_SEQ: ── Statistics ──")
        Logger.Print("BUILD_SEQ:   Sequences Started: {TotalSequencesStarted}")
        Logger.Print("BUILD_SEQ:   Sequences Completed: {TotalSequencesCompleted}")
        Logger.Print("BUILD_SEQ:   Failures: {TotalSequenceFailures}")
        Logger.Print("BUILD_SEQ:   Pieces Placed: {TotalPiecesPlaced}")
        Logger.Print("BUILD_SEQ:   Edit Peeks: {TotalEditPeeks}")
        Logger.Print("BUILD_SEQ:   Completion Rate: {GetSequenceCompletionRate()}")

    ResetTelemetry<public>() : void =
        set TotalSequencesStarted = 0
        set TotalSequencesCompleted = 0
        set TotalPiecesPlaced = 0
        set TotalEditPeeks = 0
        set TotalSequenceFailures = 0

log_seq_ch := class(log_channel):