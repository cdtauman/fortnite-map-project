# ============================================================================
# FILE: bot_combat_state_machine.verse — Combat State Decision Engine
# LOCATION: Content/ (root)
# PHASE: 2 (basic states), Phase 3 (build states added)
#
# ARCHITECTURE:
#   Owns the continuous evaluate-decide-execute loop that drives all bot
#   combat behavior. Each tick:
#     1. Read distance to player + bot health
#     2. Evaluate → pick a state (APPROACH, ENGAGE_CLOSE, etc.)
#     3. Execute that state's action for one "tick" duration
#     4. Loop
#
# CONCURRENCY CONTRACT:
#   This class's RunCombatLoop() is called from bot_behavior_base's
#   CombatLifecycle as the FOREGROUND task. MaintainFocus (aim) runs
#   in a BACKGROUND branch, so NavigateTo here does NOT block aiming.
#
#   Within each state execution, we use race blocks to ensure:
#     - Navigation has a timeout (never blocks forever)
#     - State re-evaluation happens at Profile.ChaseRetargetInterval
#     - The bot remains responsive even if NavigateTo stalls
#
# GUARD AUTO-FIRE NOTE:
#   The NPC Character Definition is set to Behavior Type "Guard", which
#   means the engine handles auto-firing at hostile targets (the player).
#   We don't call a "fire" API — the guard behavior shoots automatically
#   when the player is in range and line-of-sight. The weapon_controller
#   module tracks analytics (DPS, headshots) but does not trigger shots.
#   The Focus interface (MaintainFocus) ensures the bot aims at the head,
#   which the guard auto-fire system uses as its targeting reference.
# ============================================================================
using { /Fortnite.com/AI }
using { /Fortnite.com/AI/movement_types }
using { /Fortnite.com/Characters }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/SpatialMath }

# ── Combat State Constants ───────────────────────────────────────────────────
COMBAT_APPROACH<public>      : int = 0
COMBAT_ENGAGE_CLOSE<public>  : int = 1
COMBAT_ENGAGE_MID<public>    : int = 2
COMBAT_DISENGAGE<public>     : int = 3
COMBAT_BUILD_AGGRO<public>   : int = 4

# ══════════════════════════════════════════════════════════════════════════════
# COMBAT STATE MACHINE
# ══════════════════════════════════════════════════════════════════════════════
bot_combat_state_machine<public> := class:

    Logger<private> : log = log{Channel := log_csm_ch}

    # ── Current State ────────────────────────────────────────────────────────
    var CurrentState<public>    : int = 0
    var PreviousState<public>   : int = 0
    var TickCount<private>      : int = 0
    var StateEntryTime<private> : float = 0.0

    # ── Range Thresholds (tuned by difficulty) ───────────────────────────────
    var CloseRangeThreshold<public>    : float = 500.0
    var MidRangeThreshold<public>      : float = 1500.0
    var BuildAggroThreshold<public>    : float = 800.0

    # ── Health Thresholds ────────────────────────────────────────────────────
    var DisengageHealthPct<public>     : float = 0.30
    var CriticalHealthPct<public>      : float = 0.15

    # ── Aggression (from Profile) ────────────────────────────────────────────
    var AggressionLevel<private>       : int = 1
    var ReactionTimeMs<private>        : float = 500.0
    var ChaseRetargetInterval<private> : float = 0.3
    var NavTimeout<private>            : float = 4.0

    # ── Strafe Parameters ────────────────────────────────────────────────────
    var StrafeDistance<private>         : float = 300.0
    var StrafeToggle<private>          : logic = false

    # ── Disengage Parameters ─────────────────────────────────────────────────
    var DisengageRetreatDistance<private> : float = 800.0
    var DisengageMinTime<private>        : float = 2.0

    # ══════════════════════════════════════════════════════════════════════════
    # APPLY DIFFICULTY
    # Called by bot_behavior_base when the Profile is set or updated.
    # ══════════════════════════════════════════════════════════════════════════
    ApplyDifficulty<public>(Profile : bot_difficulty_profile) : void =
        set AggressionLevel = Profile.AggressionLevel
        set ReactionTimeMs = Profile.ReactionTimeMs
        set ChaseRetargetInterval = Profile.ChaseRetargetInterval
        set NavTimeout = Profile.NavTimeout

        # Scale thresholds based on aggression:
        # High aggression → tighter close range (bot pushes harder)
        # Low aggression → wider close range (bot fights from further)
        if (AggressionLevel >= 3):
            set CloseRangeThreshold = 600.0
            set MidRangeThreshold = 1800.0
            set DisengageHealthPct = 0.15
            set StrafeDistance = 200.0
        else if (AggressionLevel = 2):
            set CloseRangeThreshold = 500.0
            set MidRangeThreshold = 1500.0
            set DisengageHealthPct = 0.25
            set StrafeDistance = 300.0
        else:
            set CloseRangeThreshold = 400.0
            set MidRangeThreshold = 1200.0
            set DisengageHealthPct = 0.35
            set StrafeDistance = 400.0

        Logger.Print("CSM: Difficulty applied — Aggro:{AggressionLevel} Close:{CloseRangeThreshold} Mid:{MidRangeThreshold} Disengage HP:{DisengageHealthPct}")

    # ══════════════════════════════════════════════════════════════════════════
    # MAIN COMBAT LOOP
    # Called by bot_behavior_base as the foreground suspending task.
    # Runs continuously until the bot dies (cancelled by parent race).
    #
    # Each iteration:
    #   1. Compute distance to player
    #   2. Evaluate → decide state
    #   3. Execute that state's movement/action for one tick
    #   4. Brief pause (reaction time simulation), then loop
    # ══════════════════════════════════════════════════════════════════════════
    RunCombatLoop<public>(
        Nav : navigatable,
        BotChar : fort_character,
        Target : agent,
        NavModule : bot_navigation,
        AimModule : bot_focus_aim,
        WeaponModule : bot_weapon_controller,
        Profile : bot_difficulty_profile
    )<suspends> : void =
        Logger.Print("CSM: ── Combat loop started. ──")

        # Initial reaction delay — simulates the bot "noticing" the player
        InitialReactionSec := ReactionTimeMs / 1000.0
        Sleep(InitialReactionSec)
        Logger.Print("CSM: Initial reaction delay ({InitialReactionSec}s) complete. Engaging.")

        loop:
            # ── Guard: bot still alive? ──────────────────────────────────────
            if (not BotChar.IsActive[]):
                Logger.Print("CSM: Bot no longer active. Exiting loop.")
                break

            set TickCount += 1

            # ── 1. Compute distance to target ────────────────────────────────
            Dist := NavModule.GetDistanceToAgent(BotChar, Target)

            # ── 2. Compute bot health percentage ─────────────────────────────
            BotHealthPct := GetHealthPercentage(BotChar)

            # ── 3. Evaluate state ────────────────────────────────────────────
            NewState := EvaluateState(Dist, BotHealthPct, Profile)

            # ── 4. Execute the current state's action ────────────────────────
            # Each Execute___() is suspending and runs for one "tick" worth
            # of movement before returning control. NavigateTo inside each
            # state races against a retarget timer so we never block forever.
            if (NewState = COMBAT_APPROACH):
                ExecuteApproach(Nav, BotChar, Target, NavModule)
            else if (NewState = COMBAT_ENGAGE_CLOSE):
                ExecuteEngageClose(Nav, BotChar, Target, NavModule, WeaponModule)
            else if (NewState = COMBAT_ENGAGE_MID):
                ExecuteEngageMid(Nav, BotChar, Target, NavModule, WeaponModule)
            else if (NewState = COMBAT_DISENGAGE):
                ExecuteDisengage(Nav, BotChar, Target, NavModule)
            else if (NewState = COMBAT_BUILD_AGGRO):
                ExecuteBuildAggro(Nav, BotChar, Target, NavModule)

            # ── 5. Micro-pause between ticks ─────────────────────────────────
            # This is NOT a reaction delay per-shot. It's the retarget
            # interval — how often the bot re-evaluates its tactical state.
            Sleep(ChaseRetargetInterval)

    # ══════════════════════════════════════════════════════════════════════════
    # STATE EVALUATOR
    # Pure decision logic — no side effects except state variable updates.
    # Priority order: Critical Health → Low Health → Close → Mid → Far
    # ══════════════════════════════════════════════════════════════════════════
    EvaluateState<public>(
        DistanceToPlayer : float,
        BotHealthPct : float,
        Profile : bot_difficulty_profile
    ) : int =
        set PreviousState = CurrentState

        # Priority 1: Critical health — always disengage unless max aggro
        if (BotHealthPct < CriticalHealthPct):
            if (AggressionLevel >= 3):
                # Berserker mode: critically wounded but keeps pushing
                set CurrentState = COMBAT_ENGAGE_CLOSE
            else:
                set CurrentState = COMBAT_DISENGAGE

        # Priority 2: Low health threshold
        else if (BotHealthPct < DisengageHealthPct):
            if (AggressionLevel >= 2):
                # Moderate aggression: push through moderate damage
                if (DistanceToPlayer < CloseRangeThreshold):
                    set CurrentState = COMBAT_ENGAGE_CLOSE
                else:
                    set CurrentState = COMBAT_DISENGAGE
            else:
                set CurrentState = COMBAT_DISENGAGE

        # Priority 3: Close range — shotgun engagement
        else if (DistanceToPlayer < CloseRangeThreshold):
            # Check if we should build-aggro (take high ground) at medium-close
            if (DistanceToPlayer > BuildAggroThreshold):
                if (AggressionLevel >= 2):
                    if (Profile.BuildPlayRate > 0.5):
                        set CurrentState = COMBAT_BUILD_AGGRO
                    else:
                        set CurrentState = COMBAT_ENGAGE_CLOSE
                else:
                    set CurrentState = COMBAT_ENGAGE_CLOSE
            else:
                set CurrentState = COMBAT_ENGAGE_CLOSE

        # Priority 4: Mid range — AR engagement
        else if (DistanceToPlayer < MidRangeThreshold):
            set CurrentState = COMBAT_ENGAGE_MID

        # Priority 5: Far away — approach
        else:
            set CurrentState = COMBAT_APPROACH

        # Log state transitions
        if (not (CurrentState = PreviousState)):
            set StateEntryTime = GetSimulationElapsedTime()
            Logger.Print("CSM: [{TickCount}] State {PreviousState} -> {CurrentState} | Dist:{DistanceToPlayer} HP:{BotHealthPct}")

        CurrentState

    # ══════════════════════════════════════════════════════════════════════════
    # STATE EXECUTORS
    # Each runs for one "tick" then returns. NavigateTo always races against
    # a timeout so it never blocks the evaluation loop.
    # ══════════════════════════════════════════════════════════════════════════

    # ── APPROACH: Sprint toward the player ───────────────────────────────────
    # Used when the player is far away. Full speed, direct path.
    ExecuteApproach<private>(
        Nav : navigatable,
        BotChar : fort_character,
        Target : agent,
        NavModule : bot_navigation
    )<suspends> : void =
        # Navigate directly toward the target player with timeout
        NavModule.NavigateToAgent(Nav, BotChar, Target, NavTimeout)

    # ── ENGAGE_CLOSE: Strafe combat at shotgun range ─────────────────────────
    # The bot is within close range. Instead of running straight at the
    # player (which makes it easy to hit), the bot strafes laterally
    # while the guard auto-fire system shoots.
    #
    # The strafe alternates left/right each tick for unpredictability.
    # Meanwhile, MaintainFocus (running in background branch) keeps
    # the bot aimed at the player's head — producing the realistic
    # "strafe-and-shoot" behavior described in the spec.
    ExecuteEngageClose<private>(
        Nav : navigatable,
        BotChar : fort_character,
        Target : agent,
        NavModule : bot_navigation,
        WeaponModule : bot_weapon_controller
    )<suspends> : void =
        # Calculate a strafe position perpendicular to the player
        StrafePos := CalcStrafePosition(BotChar, Target)

        # Race: strafe movement vs quick retarget timer
        # This ensures the bot doesn't commit to a full strafe path
        # if the player moves drastically
        race:
            block:
                NavModule.NavigateToPosition(Nav, BotChar, StrafePos, 1.5)
            block:
                Sleep(ChaseRetargetInterval * 2.0)

        # Toggle strafe direction for next tick
        if (StrafeToggle?):
            set StrafeToggle = false
        else:
            set StrafeToggle = true

    # ── ENGAGE_MID: Advance while maintaining shooting distance ──────────────
    # The bot pushes toward the player but stops at close-range threshold
    # boundary, maintaining AR-effective distance.
    ExecuteEngageMid<private>(
        Nav : navigatable,
        BotChar : fort_character,
        Target : agent,
        NavModule : bot_navigation,
        WeaponModule : bot_weapon_controller
    )<suspends> : void =
        # Navigate toward the player, but the state evaluator will
        # transition to ENGAGE_CLOSE once we cross the threshold
        race:
            block:
                NavModule.NavigateToAgent(Nav, BotChar, Target, NavTimeout)
            block:
                # Re-evaluate after a shorter interval at mid-range
                Sleep(ChaseRetargetInterval * 1.5)

    # ── DISENGAGE: Retreat from the player ───────────────────────────────────
    # Bot health is low. Navigate AWAY from the player to create distance.
    # In Phase 3+, this state will also trigger defensive builds via Module B.
    ExecuteDisengage<private>(
        Nav : navigatable,
        BotChar : fort_character,
        Target : agent,
        NavModule : bot_navigation
    )<suspends> : void =
        # Calculate a retreat position: opposite direction from the player
        RetreatPos := CalcRetreatPosition(BotChar, Target)

        race:
            block:
                NavModule.NavigateToPosition(Nav, BotChar, RetreatPos, NavTimeout)
            block:
                # Minimum disengage time before re-evaluating
                Sleep(DisengageMinTime)

        Logger.Print("CSM: Disengage tick complete.")

    # ── BUILD_AGGRO: Offensive build sequence ────────────────────────────────
    # The bot wants to take high ground or box the player.
    # In Phase 2, this is a placeholder that advances toward the player.
    # In Phase 3+, it delegates to build_sequence_choreographer to execute
    # ramp rushes, 90s, or box-up sequences while simultaneously moving.
    ExecuteBuildAggro<private>(
        Nav : navigatable,
        BotChar : fort_character,
        Target : agent,
        NavModule : bot_navigation
    )<suspends> : void =
        Logger.Print("CSM: BUILD_AGGRO — advancing for build play.")

        # Phase 2 behavior: aggressive advance toward the player
        # Phase 3+ will replace this body with:
        #   sync:
        #       block: NavModule.NavigateToAgent(...)
        #       block: BuildChoreographer.ExecuteSequence(...)
        race:
            block:
                NavModule.NavigateToAgent(Nav, BotChar, Target, NavTimeout)
            block:
                Sleep(1.5)

    # ══════════════════════════════════════════════════════════════════════════
    # POSITION CALCULATORS
    # ══════════════════════════════════════════════════════════════════════════

    # Calculate a strafe position perpendicular to the player-bot axis.
    # Alternates left/right based on StrafeToggle.
    CalcStrafePosition<private>(
        BotChar : fort_character,
        Target : agent
    ) : vector3 =
        BotPos := BotChar.GetTransform().Translation
        if (TargetChar := Target.GetFortCharacter[]):
            TargetPos := TargetChar.GetTransform().Translation

            # Vector from bot to player
            DX := TargetPos.X - BotPos.X
            DY := TargetPos.Y - BotPos.Y

            # Perpendicular vector (rotate 90 degrees)
            # Left: (-DY, DX)  Right: (DY, -DX)
            # Normalize then scale by StrafeDistance
            Len := Sqrt((DX * DX) + (DY * DY))
            if (Len > 1.0):
                NX := DX / Len
                NY := DY / Len
                if (StrafeToggle?):
                    # Strafe left
                    return vector3{
                        X := BotPos.X + (0.0 - NY) * StrafeDistance,
                        Y := BotPos.Y + NX * StrafeDistance,
                        Z := BotPos.Z
                    }
                else:
                    # Strafe right
                    return vector3{
                        X := BotPos.X + NY * StrafeDistance,
                        Y := BotPos.Y + (0.0 - NX) * StrafeDistance,
                        Z := BotPos.Z
                    }
        # Fallback: just stay put
        BotPos

    # Calculate a retreat position directly away from the player.
    CalcRetreatPosition<private>(
        BotChar : fort_character,
        Target : agent
    ) : vector3 =
        BotPos := BotChar.GetTransform().Translation
        if (TargetChar := Target.GetFortCharacter[]):
            TargetPos := TargetChar.GetTransform().Translation

            # Vector from player to bot (away direction)
            DX := BotPos.X - TargetPos.X
            DY := BotPos.Y - TargetPos.Y

            # Normalize and scale
            Len := Sqrt((DX * DX) + (DY * DY))
            if (Len > 1.0):
                NX := DX / Len
                NY := DY / Len
                return vector3{
                    X := BotPos.X + NX * DisengageRetreatDistance,
                    Y := BotPos.Y + NY * DisengageRetreatDistance,
                    Z := BotPos.Z
                }
        # Fallback: move forward from facing direction
        BotRot := BotChar.GetViewRotation()
        Forward := BotRot.GetLocalForward()
        vector3{
            X := BotPos.X + Forward.X * DisengageRetreatDistance,
            Y := BotPos.Y + Forward.Y * DisengageRetreatDistance,
            Z := BotPos.Z
        }

    # ══════════════════════════════════════════════════════════════════════════
    # HEALTH UTILITY
    # ══════════════════════════════════════════════════════════════════════════
    GetHealthPercentage<private>(BotChar : fort_character) : float =
        if:
            MaxHP := BotChar.GetMaxHealth()
            MaxHP > 0.0
        then:
            CurrentHP := BotChar.GetHealth()
            return CurrentHP / MaxHP
        1.0

    # ══════════════════════════════════════════════════════════════════════════
    # PUBLIC QUERIES
    # ══════════════════════════════════════════════════════════════════════════
    GetStateName<public>() : string =
        if (CurrentState = COMBAT_APPROACH). return "APPROACH"
        else if (CurrentState = COMBAT_ENGAGE_CLOSE). return "ENGAGE_CLOSE"
        else if (CurrentState = COMBAT_ENGAGE_MID). return "ENGAGE_MID"
        else if (CurrentState = COMBAT_DISENGAGE). return "DISENGAGE"
        else if (CurrentState = COMBAT_BUILD_AGGRO). return "BUILD_AGGRO"
        else. return "UNKNOWN"

    GetTickCount<public>() : int =
        TickCount

    GetTimeInCurrentState<public>() : float =
        GetSimulationElapsedTime() - StateEntryTime

    DidStateChange<public>() : logic =
        if (CurrentState = PreviousState):
            false
        else:
            true

log_csm_ch := class(log_channel){}
