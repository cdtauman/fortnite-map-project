# ============================================================================
# FILE: bot_behavior_base.verse — Root NPC Combat Behavior Orchestrator
# LOCATION: Content/ (root)
# PHASE: 2 (navigation + aim), evolves through Phase 4
#
# ARCHITECTURE:
#   This is the entry point for ALL bot intelligence. It inherits
#   npc_behavior and is assigned as the Behavior Script on the NPC
#   Character Definition asset in the UEFN editor.
#
#   OnBegin() fires when the NPC spawns. It:
#     1. Acquires Agent + FortCharacter + engine interfaces
#     2. Instantiates sub-module classes (nav, aim, weapon, state machine)
#     3. Applies the current difficulty profile to all sub-modules
#     4. Launches concurrent background tasks (aim, state machine)
#     5. Races the main combat loop against the death listener
#
#   OnEnd() fires on despawn/elimination — cleanup signal.
#
# CONCURRENCY MODEL:
#   branch → MaintainFocus (continuous aim tracking, never blocks main)
#   branch → State machine evaluation + execution loop
#   race   → CombatLifecycle vs WaitForDeath
#            Whichever completes first cancels the other.
#
# NOTE: npc_behavior cannot hold @editable references. Sub-modules
#   are plain Verse classes, not creative_devices.
# ============================================================================
using { /Fortnite.com/AI }
using { /Fortnite.com/AI/movement_types }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Game }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /Fortnite.com/Playspaces }
using { /Fortnite.com/Devices }
using { /Verse.org/Simulation/Tags }

bot_game_manager_tag<public> := class(tag){}

bot_behavior_base<public> := class(npc_behavior):

    Logger<private> : log = log{Channel := log_bot_ch}

    # ── Difficulty Profile ───────────────────────────────────────────────────
    # Values are updated by Module C (difficulty_mapper) between rounds.
    # The profile is read by all sub-modules every tick.
    var Profile<public> : bot_difficulty_profile = bot_difficulty_profile{}

    # ── Sub-Module Instances ─────────────────────────────────────────────────
    var NavModule<private>    : bot_navigation            = bot_navigation{}
    var AimModule<private>    : bot_focus_aim              = bot_focus_aim{}
    var WeaponModule<private> : bot_weapon_controller      = bot_weapon_controller{}
    var StateMachine<private> : bot_combat_state_machine   = bot_combat_state_machine{}

    # ── Cached References (set during OnBegin, read by sub-modules) ──────────
    var CachedAgent<private>    : ?agent          = false
    var CachedChar<private>     : ?fort_character  = false
    var CachedNav<private>      : ?navigatable     = false
    var CachedFocus<private>    : ?focus_interface  = false
    var TargetPlayer<private>   : ?agent           = false

    # ── State Flags ──────────────────────────────────────────────────────────
    var IsAlive<private>        : logic = true
    var IsEngaged<private>      : logic = false

    # ══════════════════════════════════════════════════════════════════════════
    # ENTRY POINT — Fires when the NPC entity is spawned
    # ══════════════════════════════════════════════════════════════════════════
    OnBegin<override>()<suspends> : void =
        Logger.Print("BOT: ── Spawned. Initializing combat behavior. ──")
        set IsAlive = true

        # ── Step 1: Acquire Agent and FortCharacter ──────────────────────────
        if:
            BotAgent := GetAgent[]
            BotChar := BotAgent.GetFortCharacter[]
        then:
            set CachedAgent = option{BotAgent}
            set CachedChar = option{BotChar}
            Logger.Print("BOT: Agent and FortCharacter acquired.")

            # ── Step 2: Acquire engine interfaces ────────────────────────────
            if:
                Nav := BotChar.GetNavigatable[]
                Focus := BotChar.GetFocusInterface[]
            then:
                set CachedNav = option{Nav}
                set CachedFocus = option{Focus}
                Logger.Print("BOT: Navigatable and FocusInterface acquired.")

                # ── Step 3: Find the target player ───────────────────────────
                if (Target := FindTargetPlayer[]):
                    set TargetPlayer = option{Target}
                    Logger.Print("BOT: Target player locked.")

                    # ── Step 4: Apply difficulty to all sub-modules ──────────
                    ApplyDifficultyToSubModules()

                    # ── Step 5: Initialize weapon tracking ───────────────────
                    WeaponModule.BeginEngagement(GetSimulationElapsedTime())
                    set IsEngaged = true
                    Logger.Print("BOT: Sub-modules initialized. Difficulty applied.")
                    Logger.Print("BOT: Profile — Reaction:{Profile.ReactionTimeMs}ms Aim Z:{Profile.AimZOffset} Variance:{Profile.AimVariance} Aggro:{Profile.AggressionLevel}")

                    # ── Step 6: Launch concurrent combat systems ─────────────
                    # The entire bot lifecycle races against death.
                    # Inside CombatLifecycle, aim runs in a branch (background),
                    # and the state machine drives movement in the foreground.
                    race:
                        CombatLifecycle(Nav, Focus, BotChar, Target)
                        WaitForDeath(BotChar)

                    Logger.Print("BOT: ── Combat lifecycle ended. ──")
                else:
                    Logger.Print("BOT: ERROR — No valid player target found. Idling.")
                    IdleUntilDeath(BotChar)
            else:
                Logger.Print("BOT: ERROR — Nav/Focus interface unavailable. Idling.")
                IdleUntilDeath(BotChar)
        else:
            Logger.Print("BOT: CRITICAL — Agent acquisition failed!")

    # ══════════════════════════════════════════════════════════════════════════
    # CLEANUP — Fires when the NPC is eliminated or despawned
    # ══════════════════════════════════════════════════════════════════════════
    OnEnd<override>() : void =
        set IsAlive = false
        set IsEngaged = false
        Logger.Print("BOT: ── Eliminated / despawned. OnEnd fired. ──")

    # ══════════════════════════════════════════════════════════════════════════
    # COMBAT LIFECYCLE
    # This is the top-level concurrent structure that keeps the bot "alive"
    # and fighting. It runs three systems simultaneously:
    #
    #   [branch]  AimTrackingLoop   — Continuous MaintainFocus on player
    #   [branch]  ReactionDelayLoop — Simulates human reaction time
    #   [main]    StateMachineLoop  — Evaluates state, drives movement
    #
    # All three are cancelled atomically when WaitForDeath completes
    # in the parent race block.
    # ══════════════════════════════════════════════════════════════════════════
    CombatLifecycle<private>(
        Nav : navigatable,
        Focus : focus_interface,
        BotChar : fort_character,
        Target : agent
    )<suspends> : void =
        Logger.Print("BOT: CombatLifecycle started — aim, move, shoot concurrent.")

        # Background task: maintain continuous aim at the target player.
        # MaintainFocus is a suspending call that runs until cancelled.
        # It lets the bot's upper body track the player while legs move
        # independently — producing natural strafe-and-shoot behavior.
        branch:
            AimTrackingLoop(Focus, BotChar, Target)

        # Foreground: the state machine evaluation and execution loop.
        # This drives navigation, state transitions, and weapon timing.
        StateMachine.RunCombatLoop(
            Nav, BotChar, Target,
            NavModule, AimModule, WeaponModule,
            Profile
        )

    # ══════════════════════════════════════════════════════════════════════════
    # AIM TRACKING LOOP
    # Runs as a branched background task for the bot's entire life.
    # MaintainFocus(Target) is a single suspending call that continuously
    # orients the bot's aim toward the target. If the target becomes
    # invalid (eliminated, left), we catch and re-attempt.
    # ══════════════════════════════════════════════════════════════════════════
    AimTrackingLoop<private>(
        Focus : focus_interface,
        BotChar : fort_character,
        Target : agent
    )<suspends> : void =
        Logger.Print("BOT: AimTrackingLoop started.")
        loop:
            if (BotChar.IsActive[]):
                # MaintainFocus suspends until the focus target is lost
                # or the task is cancelled by the parent race
                Focus.MaintainFocus(Target)
                # If MaintainFocus returns (target lost), brief pause then retry
                Logger.Print("BOT: MaintainFocus returned — target may be lost. Retrying.")
                Sleep(0.2)
            else:
                Logger.Print("BOT: AimTrackingLoop — bot no longer active.")
                break

    # ══════════════════════════════════════════════════════════════════════════
    # DEATH LISTENER
    # Awaits the fort_character EliminatedEvent. When this fires, the
    # parent race block cancels CombatLifecycle and all its children.
    # ══════════════════════════════════════════════════════════════════════════
    WaitForDeath<private>(BotChar : fort_character)<suspends> : void =
        BotChar.EliminatedEvent().Await()
        set IsAlive = false
        Logger.Print("BOT: EliminatedEvent fired.")

    # ══════════════════════════════════════════════════════════════════════════
    # IDLE FALLBACK
    # If interfaces fail to acquire, the bot just waits to die rather
    # than crashing the behavior script.
    # ══════════════════════════════════════════════════════════════════════════
    IdleUntilDeath<private>(BotChar : fort_character)<suspends> : void =
        Logger.Print("BOT: Idle fallback — waiting for elimination.")
        BotChar.EliminatedEvent().Await()
        set IsAlive = false

    # ══════════════════════════════════════════════════════════════════════════
    # TARGET ACQUISITION
    # Finds the first active human player in the playspace.
    # Uses failable context (<decides><transacts>) for safe access.
    # ══════════════════════════════════════════════════════════════════════════
    FindTargetPlayer<private>()<decides><transacts> : agent =
        TaggedDevices := GetCreativeObjectsWithTag(bot_game_manager_tag{})
        Device := TaggedDevices[0]
        Playspace := Device.GetPlayspace()
        Players := Playspace.GetPlayers()
        HumanAgent := Players[0]
        PC := HumanAgent.GetFortCharacter[]
        PC.IsActive[]
        HumanAgent

    # ══════════════════════════════════════════════════════════════════════════
    # DIFFICULTY APPLICATION
    # Pushes the current Profile values into each sub-module so they
    # calibrate their behavior for the current ELO bracket.
    # ══════════════════════════════════════════════════════════════════════════
    ApplyDifficultyToSubModules<private>() : void =
        # Aim module: headshot offset and variance
        AimModule.ApplyDifficulty(Profile)

        # State machine: range thresholds and aggression-driven transitions
        StateMachine.ApplyDifficulty(Profile)

        Logger.Print("BOT: Difficulty profile applied to all sub-modules.")

    # ══════════════════════════════════════════════════════════════════════════
    # PUBLIC: Hot-reload difficulty mid-fight
    # Called by Module C if ELO adjusts during a round (rare, but possible
    # for anti-stagnation volatility injection).
    # ══════════════════════════════════════════════════════════════════════════
    UpdateDifficultyLive<public>(NewProfile : bot_difficulty_profile) : void =
        set Profile = NewProfile
        ApplyDifficultyToSubModules()
        Logger.Print("BOT: Live difficulty update applied.")

    # ══════════════════════════════════════════════════════════════════════════
    # PUBLIC QUERIES
    # ══════════════════════════════════════════════════════════════════════════
    GetIsAlive<public>() : logic =
        IsAlive

    GetCurrentState<public>() : int =
        StateMachine.CurrentState

    GetWeaponStats<public>() : bot_weapon_controller =
        WeaponModule

log_bot_ch := class(log_channel):