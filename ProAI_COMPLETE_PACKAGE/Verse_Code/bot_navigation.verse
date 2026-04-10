# ============================================================================
# FILE: bot_navigation.verse — Navigation Subsystem & Movement Utilities
# LOCATION: Content/ (root)
# PHASE: 2
#
# ARCHITECTURE:
#   Provides all movement logic for the bot. Two usage patterns:
#
#   PATTERN A — Cached refs (Init-based):
#     Call Init(Agent, Char) once. Then use NavigateToTarget(),
#     MoveToPosition(), etc. without passing Nav/BotChar each time.
#
#   PATTERN B — Explicit params (stateless):
#     Pass Nav, BotChar explicitly to NavigateToAgent(),
#     NavigateToPosition(). Used by the combat state machine where
#     references are passed through from the behavior base.
#
#   Both patterns are fully supported. The state machine (Mission 3)
#   uses Pattern B. Bot_behavior_base can use Init + Pattern A for
#   convenience calls.
#
# POST-38.10 FIX:
#   movement_types must be imported as a separate submodule:
#     using { /Fortnite.com/AI/movement_types }
#   Then reference Running directly (not movement_types.Running).
#
# NAVMESH NOTE (HC-03):
#   All arena surfaces where bots navigate MUST be built with
#   traditional geometry props (not Scene Graph). Scene Graph objects
#   do not register on the NavMesh. Place invisible collision boxes
#   beneath any visual-only geometry.
# ============================================================================
using { /Fortnite.com/AI }
using { /Fortnite.com/AI/movement_types }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Game }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/SpatialMath }

# ── Navigation Result Constants ──────────────────────────────────────────────
NAV_SUCCESS<public>      : int = 0
NAV_TIMEOUT<public>      : int = 1
NAV_UNREACHABLE<public>  : int = 2
NAV_BOT_DEAD<public>     : int = 3
NAV_NO_INTERFACE<public> : int = 4

# ══════════════════════════════════════════════════════════════════════════════
# BOT NAVIGATION CLASS
# ══════════════════════════════════════════════════════════════════════════════
bot_navigation<public> := class:

    Logger<private> : log = log{Channel := log_nav_ch}

    # ── Cached References (set via Init) ─────────────────────────────────────
    var CachedAgent<private>    : ?agent          = false
    var CachedChar<private>     : ?fort_character  = false
    var CachedNav<private>      : ?navigatable     = false
    var IsInitialized<private>  : logic            = false

    # ── Configuration ────────────────────────────────────────────────────────
    var DefaultReachRadius<public>  : float = 150.0
    var DefaultNavTimeout<public>   : float = 4.0
    var DefaultMoveSprint<public>   : logic = true

    # ── Telemetry ────────────────────────────────────────────────────────────
    var TotalNavAttempts<public>    : int = 0
    var TotalNavSuccesses<public>   : int = 0
    var TotalNavTimeouts<public>    : int = 0
    var TotalNavFailures<public>    : int = 0

    # ══════════════════════════════════════════════════════════════════════════
    # INITIALIZATION
    # Call once from bot_behavior_base after acquiring Agent + FortCharacter.
    # Extracts and caches the navigatable interface.
    # ══════════════════════════════════════════════════════════════════════════
    Init<public>(InAgent : agent, InChar : fort_character) : logic =
        set CachedAgent = option{InAgent}
        set CachedChar = option{InChar}

        # Extract the navigatable interface from the FortCharacter
        if (Nav := InChar.GetNavigatable[]):
            set CachedNav = option{Nav}
            set IsInitialized = true
            Logger.Print("NAV: Initialized. Navigatable interface acquired.")
            return true
        else:
            Logger.Print("NAV: ERROR — GetNavigatable[] failed. Bot cannot move.")
            set IsInitialized = false
            return false

    # ══════════════════════════════════════════════════════════════════════════
    # PATTERN A: CACHED-REF NAVIGATION METHODS
    # Use after calling Init(). No need to pass Nav/BotChar.
    # ══════════════════════════════════════════════════════════════════════════

    # Navigate toward a world position using cached references.
    # Returns a result code (NAV_SUCCESS, NAV_TIMEOUT, etc.)
    MoveToPosition<public>(TargetPos : vector3)<suspends> : int =
        set TotalNavAttempts += 1
        if (BotChar := CachedChar?):
            if (Nav := CachedNav?):
                if (BotChar.IsActive[]):
                    NavTarget := MakeNavigationTarget(TargetPos)
                    var NavResult : int = NAV_TIMEOUT
                    race:
                        block:
                            Nav.NavigateTo(
                                NavTarget,
                                ?MovementType := Running,
                                ?ReachRadius := DefaultReachRadius,
                                ?AllowPartialPath := true
                            )
                            set TotalNavSuccesses += 1
                            set NavResult = NAV_SUCCESS
                        block:
                            Sleep(DefaultNavTimeout)
                            Nav.StopNavigation()
                            set TotalNavTimeouts += 1
                            Logger.Print("NAV: MoveToPosition timed out after {DefaultNavTimeout}s.")
                    NavResult
                else:
                    NAV_BOT_DEAD
            else:
                NAV_NO_INTERFACE
        else:
            NAV_NO_INTERFACE

    # Navigate toward a target agent using cached references.
    MoveToAgent<public>(Target : agent)<suspends> : int =
        set TotalNavAttempts += 1
        if (BotChar := CachedChar?):
            if (Nav := CachedNav?):
                if (BotChar.IsActive[]):
                    NavTarget := MakeNavigationTarget(Target)
                    var NavResult2 : int = NAV_TIMEOUT
                    race:
                        block:
                            Nav.NavigateTo(
                                NavTarget,
                                ?MovementType := Running,
                                ?ReachRadius := DefaultReachRadius,
                                ?AllowPartialPath := true
                            )
                            set TotalNavSuccesses += 1
                            set NavResult2 = NAV_SUCCESS
                        block:
                            Sleep(DefaultNavTimeout)
                            Nav.StopNavigation()
                            set TotalNavTimeouts += 1
                    NavResult2
                else:
                    NAV_BOT_DEAD
            else:
                NAV_NO_INTERFACE
        else:
            NAV_NO_INTERFACE

    # Navigate toward a world position with a custom timeout.
    MoveToPositionTimed<public>(TargetPos : vector3, TimeoutSec : float)<suspends> : int =
        set TotalNavAttempts += 1
        if (BotChar := CachedChar?):
            if (Nav := CachedNav?):
                if (BotChar.IsActive[]):
                    NavTarget := MakeNavigationTarget(TargetPos)
                    var NavResult3 : int = NAV_TIMEOUT
                    race:
                        block:
                            Nav.NavigateTo(
                                NavTarget,
                                ?MovementType := Running,
                                ?ReachRadius := DefaultReachRadius,
                                ?AllowPartialPath := true
                            )
                            set TotalNavSuccesses += 1
                            set NavResult3 = NAV_SUCCESS
                        block:
                            Sleep(TimeoutSec)
                            Nav.StopNavigation()
                            set TotalNavTimeouts += 1
                    NavResult3
                else:
                    NAV_BOT_DEAD
            else:
                NAV_NO_INTERFACE
        else:
            NAV_NO_INTERFACE

    # Walk (not sprint) to a position — used for tactical repositioning.
    WalkToPosition<public>(TargetPos : vector3, TimeoutSec : float)<suspends> : int =
        set TotalNavAttempts += 1
        if (BotChar := CachedChar?):
            if (Nav := CachedNav?):
                if (BotChar.IsActive[]):
                    NavTarget := MakeNavigationTarget(TargetPos)
                    var NavResult : int = NAV_TIMEOUT
                    race:
                        block:
                            Nav.NavigateTo(
                                NavTarget,
                                ?MovementType := Walking,
                                ?ReachRadius := DefaultReachRadius,
                                ?AllowPartialPath := true
                            )
                            set TotalNavSuccesses += 1
                            set NavResult = NAV_SUCCESS
                        block:
                            Sleep(TimeoutSec)
                            Nav.StopNavigation()
                            set TotalNavTimeouts += 1
                    NavResult
                else:
                    NAV_BOT_DEAD
            else:
                NAV_NO_INTERFACE
        else:
            NAV_NO_INTERFACE

    # Stop all navigation immediately using cached interface.
    StopMovement<public>() : void =
        if (Nav := CachedNav?):
            Nav.StopNavigation()
            Logger.Print("NAV: Movement stopped.")

    # ══════════════════════════════════════════════════════════════════════════
    # PATTERN B: EXPLICIT-PARAM NAVIGATION METHODS
    # Called by the combat state machine (Mission 3), which passes
    # Nav, BotChar, Target explicitly from bot_behavior_base.
    # These are the backward-compatible signatures.
    # ══════════════════════════════════════════════════════════════════════════

    # Navigate to a specific world position with timeout.
    # Returns true on success, false on timeout or failure.
    NavigateToPosition<public>(
        Nav : navigatable,
        BotChar : fort_character,
        Position : vector3,
        TimeoutSec : float
    )<suspends> : logic =
        set TotalNavAttempts += 1
        if (BotChar.IsActive[]):
            NavTarget := MakeNavigationTarget(Position)
            var NavResult : logic = false
            race:
                block:
                    Nav.NavigateTo(
                        NavTarget,
                        ?MovementType := Running,
                        ?ReachRadius := DefaultReachRadius,
                        ?AllowPartialPath := true
                    )
                    set TotalNavSuccesses += 1
                    set NavResult = true
                block:
                    Sleep(TimeoutSec)
                    Nav.StopNavigation()
                    set TotalNavTimeouts += 1
            return NavResult
        # Bot is dead — graceful failure, sleep briefly to prevent tight loop
        Sleep(0.1)
        set TotalNavFailures += 1
        false

    # Navigate to a player agent with timeout.
    NavigateToAgent<public>(
        Nav : navigatable,
        BotChar : fort_character,
        Target : agent,
        TimeoutSec : float
    )<suspends> : logic =
        set TotalNavAttempts += 1
        if (BotChar.IsActive[]):
            NavTarget := MakeNavigationTarget(Target)
            var NavResult : logic = false
            race:
                block:
                    Nav.NavigateTo(
                        NavTarget,
                        ?MovementType := Running,
                        ?ReachRadius := DefaultReachRadius,
                        ?AllowPartialPath := true
                    )
                    set TotalNavSuccesses += 1
                    set NavResult = true
                block:
                    Sleep(TimeoutSec)
                    Nav.StopNavigation()
                    set TotalNavTimeouts += 1
            return NavResult
        Sleep(0.1)
        set TotalNavFailures += 1
        false

    # Navigate to a position at walking speed (for disengage/repositioning).
    WalkToPositionExplicit<public>(
        Nav : navigatable,
        BotChar : fort_character,
        Position : vector3,
        TimeoutSec : float
    )<suspends> : logic =
        set TotalNavAttempts += 1
        if (BotChar.IsActive[]):
            NavTarget := MakeNavigationTarget(Position)
            var NavResult : logic = false
            race:
                block:
                    Nav.NavigateTo(
                        NavTarget,
                        ?MovementType := Walking,
                        ?ReachRadius := DefaultReachRadius,
                        ?AllowPartialPath := true
                    )
                    set TotalNavSuccesses += 1
                    set NavResult = true
                block:
                    Sleep(TimeoutSec)
                    Nav.StopNavigation()
                    set TotalNavTimeouts += 1
            return NavResult
        Sleep(0.1)
        set TotalNavFailures += 1
        false

    # ══════════════════════════════════════════════════════════════════════════
    # SPATIAL UTILITIES — Pure math, no navigation calls
    # ══════════════════════════════════════════════════════════════════════════

    # Calculate a position offset from the bot's facing direction.
    # Used by build system to compute wall/ramp placement positions.
    GetForwardOffset<public>(BotChar : fort_character, Dist : float) : vector3 =
        BotPos := BotChar.GetTransform().Translation
        BotRot := BotChar.GetViewRotation()
        Forward := BotRot.GetLocalForward()
        vector3{
            X := BotPos.X + (Forward.X * Dist),
            Y := BotPos.Y + (Forward.Y * Dist),
            Z := BotPos.Z
        }

    # Get a position to the right of the bot's facing direction.
    GetRightOffset<public>(BotChar : fort_character, Dist : float) : vector3 =
        BotPos := BotChar.GetTransform().Translation
        BotRot := BotChar.GetViewRotation()
        Right := BotRot.GetLocalRight()
        vector3{
            X := BotPos.X + (Right.X * Dist),
            Y := BotPos.Y + (Right.Y * Dist),
            Z := BotPos.Z
        }

    # Euclidean distance between the bot and a target agent.
    GetDistanceToAgent<public>(BotChar : fort_character, Target : agent) : float =
        if (TargetChar := Target.GetFortCharacter[]):
            BotPos := BotChar.GetTransform().Translation
            TargetPos := TargetChar.GetTransform().Translation
            DX := BotPos.X - TargetPos.X
            DY := BotPos.Y - TargetPos.Y
            DZ := BotPos.Z - TargetPos.Z
            return Sqrt((DX * DX) + (DY * DY) + (DZ * DZ))
        99999.0

    # Horizontal-only distance (ignores Z). Useful for range checks
    # on flat arenas where height difference is irrelevant.
    GetHorizontalDistanceToAgent<public>(BotChar : fort_character, Target : agent) : float =
        if (TargetChar := Target.GetFortCharacter[]):
            BotPos := BotChar.GetTransform().Translation
            TargetPos := TargetChar.GetTransform().Translation
            DX := BotPos.X - TargetPos.X
            DY := BotPos.Y - TargetPos.Y
            return Sqrt((DX * DX) + (DY * DY))
        99999.0

    # Distance between two arbitrary world positions.
    GetDistanceBetween<public>(A : vector3, B : vector3) : float =
        DX := A.X - B.X
        DY := A.Y - B.Y
        DZ := A.Z - B.Z
        Sqrt((DX * DX) + (DY * DY) + (DZ * DZ))

    # Normalized direction vector from bot to target.
    GetDirectionToAgent<public>(BotChar : fort_character, Target : agent) : vector3 =
        if (TargetChar := Target.GetFortCharacter[]):
            BotPos := BotChar.GetTransform().Translation
            TargetPos := TargetChar.GetTransform().Translation
            DX := TargetPos.X - BotPos.X
            DY := TargetPos.Y - BotPos.Y
            DZ := TargetPos.Z - BotPos.Z
            Len := Sqrt((DX * DX) + (DY * DY) + (DZ * DZ))
            if (Len > 0.1):
                return vector3{X := DX / Len, Y := DY / Len, Z := DZ / Len}
        vector3{X := 0.0, Y := 0.0, Z := 0.0}

    # Check if the bot is within a specified range of the target.
    IsWithinRange<public>(BotChar : fort_character, Target : agent, Range : float) : logic =
        Dist := GetDistanceToAgent(BotChar, Target)
        if (Dist <= Range):
            return true
        false

    # ══════════════════════════════════════════════════════════════════════════
    # TELEMETRY
    # ══════════════════════════════════════════════════════════════════════════
    GetNavSuccessRate<public>() : float =
        if (TotalNavAttempts > 0):
            return (TotalNavSuccesses * 1.0) / (TotalNavAttempts * 1.0)
        0.0

    ResetTelemetry<public>() : void =
        set TotalNavAttempts = 0
        set TotalNavSuccesses = 0
        set TotalNavTimeouts = 0
        set TotalNavFailures = 0

log_nav_ch := class(log_channel):