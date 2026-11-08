using { /Fortnite.com/AI }
using { /Fortnite.com/Abilities }
using { /Fortnite.com/Armory }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Devices }
using { /Fortnite.com/Game }
using { /Fortnite.com/Itemization }
using { /Fortnite.com/Playspaces }
using { /Fortnite.com/Teams }
using { /Fortnite.com/UI }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /UnrealEngine.com/Itemization }
using { /UnrealEngine.com/Temporary/UI }

CoachProbeLog(Text : string):void =
    Print(Text, ?Duration := 0.0)

# Private damage comparisons; owned allocations are disposed only during cleanup.
coach_health_probe_device := class(creative_device):
    @editable
    VisualToolCaptureSeconds : float = 0.0
    @editable
    VisualRifleCaptureSeconds : float = 0.0
    @editable
    VisualNativeCaptureSeconds : float = 0.0
    @editable
    VisualUseViewportCamera : logic = false
    @editable
    VisualCaptureCamera : gameplay_camera_fixed_point_device = gameplay_camera_fixed_point_device{}
    @editable
    VisualPortal : coach_portal_device = coach_portal_device{}
    @editable
    Enabled : logic = false
    @editable
    AutoRun : logic = false
    @editable
    LearningObservationOnly : logic = false
    @editable
    ParticipantInventoryOnly : logic = false
    @editable
    ParticipantBuildAction : logic = false
    @editable
    ParticipantItemAuditOnly : logic = false
    @editable
    ParticipantWoodGranter : item_granter_device = item_granter_device{}
    @editable
    ParticipantSpawner : npc_spawner_device = npc_spawner_device{}
    @editable
    Structures : coach_structure_device = coach_structure_device{}
    @editable
    ControlWall : creative_prop = creative_prop{}
    @editable
    EditedWall : creative_prop = creative_prop{}
    @editable
    ControlBlast : explosive_device = explosive_device{}
    @editable
    EditedBlast : explosive_device = explosive_device{}
    @editable
    ControlMonitor : prop_manipulator_device = prop_manipulator_device{}
    @editable
    EditedMonitor : prop_manipulator_device = prop_manipulator_device{}
    @editable
    PositiveWall : creative_prop = creative_prop{}
    @editable
    PositiveBlast : explosive_device = explosive_device{}
    @editable
    PositiveMonitor : prop_manipulator_device = prop_manipulator_device{}
    @editable
    CalibrationObjective : objective_device = objective_device{}
    @editable
    CalibrationBlast : explosive_device = explosive_device{}
    @editable
    CalibrationNativeTimer : logic = false
    @editable
    UseWeaponCalibration : logic = false
    @editable
    UseCharacterTargetControl : logic = false
    @editable
    NPCEquippedAttackControl : logic = false
    @editable
    NativeBuildToolReference : logic = false
    @editable
    NativeBuildToolLease : logic = false
    @editable
    NativeBuildCameraBypass : logic = false
    @editable
    NativeBuildMenuOnly : logic = false
    @editable
    CalibrationAimOffset : vector3 = vector3{Z := 200.0}
    @editable
    MeshChangeAfterPlayerHits : int = 0
    @editable
    IsolatedWallControl : logic = false
    @editable
    SpawnedWallControl : logic = false
    @editable
    NativeTeamWallControl : logic = false
    @editable
    NativeWallTransitionControl : logic = false
    @editable
    NativeWallTransitionCase : int = 0
    @editable
    SpawnedWallAsset : creative_prop_asset = DefaultCreativePropAsset
    @editable
    CalibrationShooter : npc_spawner_device = npc_spawner_device{}
    @editable
    CalibrationPlayerTeleporter : teleporter_device = teleporter_device{}
    @editable
    CalibrationNoFireZone : mutator_zone_device = mutator_zone_device{}

    var Ending : logic = false
    var InitializationComplete : logic = false
    var ControlBlasts : int = 0
    var EditedBlasts : int = 0
    var ControlDamageEvents : int = 0
    var EditedDamageEvents : int = 0
    var ControlDestroyedEvents : int = 0
    var EditedDestroyedEvents : int = 0
    var PositiveBlasts : int = 0
    var PositiveDamageEvents : int = 0
    var PositiveDestroyedEvents : int = 0
    var CalibrationBlasts : int = 0
    var CalibrationDamageEvents : int = 0
    var ObjectivePlayerHits : int = 0
    var ControlPlayerHits : int = 0
    var LastControlWallPosition : ?vector3 = false
    var ControlMeshChanged : logic = false
    var SpawnedControlWall : ?creative_prop = false
    var SpawnedWallGeneration : int = 0
    var ObservedSpawnedWallDeaths : int = 0
    var PlayerControlReadyCount : int = 0
    var TeamWallShotPoseFailures : int = 0
    var TeamWallOriginalTeams : []tuple(agent, team) = array{}
    var TransitionPhase : int = 0
    var TransitionPending : logic = false
    var TransitionDone : logic = false
    var TransitionFailed : logic = false
    TransitionPool : coach_native_piece_pool = coach_native_piece_pool{}
    RequiredPlayerAimAlignment : float = 0.9995
    var ChangedTeamAgent : ?agent = false
    var OriginalTeam : ?team = false
    var Bindings : []cancelable = array{}
    var Shooter : ?agent = false
    var CombatTarget : ?agent = false
    var CombatDamageEvents : int = 0
    var CombatHitsByShooter : int = 0
    var PlayerTeleports : int = 0
    var ProbeRifle : ?entity = false
    var NativeToolLease : ?coach_native_build_tool_lease = false
    var NativeBuildAttackObservation : ?coach_native_build_attack_observation = false
    var CalibratedPlayer : ?agent = false
    var PlayerTargetHits : int = 0
    Geometry : coach_geometry_query = coach_geometry_query{}
    var LearningCheckFailures : int = 0

    OnBegin<override>()<suspends>:void =
        if (not Enabled?):
            HideWalls()
            CalibrationObjective.Hide()
            set InitializationComplete = true
            return
        if (Structures.CandidateCombatEnabled? or Structures.QueryCoverageConfirmed? or Structures.HealthContinuityConfirmed? or Structures.NativeSlotInteroperationConfirmed?):
            CoachProbeLog("PCL|health_probe|not_started|acceptance_gates_not_clear")
            return
        if (ParticipantInventoryOnly?):
            HideWalls()
            CalibrationObjective.Hide()
            set InitializationComplete = true
            if (AutoRun?):
                RunParticipantInventoryProbe()
                CoachProbeLog("PCL|health_probe|automatic_sequence_finished|participant_inventory_only|results_require_review")
            return
        if (LearningObservationOnly?):
            HideWalls()
            CalibrationObjective.Hide()
            set InitializationComplete = true
            if (AutoRun?):
                RunLearningObservationChecks()
                CoachProbeLog("PCL|health_probe|automatic_sequence_finished|learning_checks_only|failures={LearningCheckFailures}|no_character_item_or_weapon_actions")
            return
        set Bindings = array{
            ControlBlast.ExplodedEvent.Subscribe(OnControlBlast),
            EditedBlast.ExplodedEvent.Subscribe(OnEditedBlast),
            ControlMonitor.DamagedEvent.Subscribe(OnControlDamage),
            EditedMonitor.DamagedEvent.Subscribe(OnEditedDamage),
            ControlMonitor.DestroyedEvent.Subscribe(OnControlDestroyed),
            EditedMonitor.DestroyedEvent.Subscribe(OnEditedDestroyed),
            PositiveBlast.ExplodedEvent.Subscribe(OnPositiveBlast),
            PositiveMonitor.DamagedEvent.Subscribe(OnPositiveDamage),
            PositiveMonitor.DestroyedEvent.Subscribe(OnPositiveDestroyed),
            CalibrationBlast.ExplodedEvent.Subscribe(OnCalibrationBlast),
            CalibrationObjective.DamagedEvent().Subscribe(OnCalibrationDamage),
            CalibrationShooter.SpawnedEvent.Subscribe(OnShooterSpawned),
            CalibrationPlayerTeleporter.TeleportedEvent.Subscribe(OnCalibrationPlayerTeleported)
        }
        ControlMonitor.Enable()
        EditedMonitor.Enable()
        PositiveMonitor.Enable()
        CalibrationObjective.Show()
        CalibrationObjective.SetInvulnerable(false)
        if (ControlWall.IsValid[]):
            ControlWall.Show()
        if (EditedWall.IsValid[]):
            EditedWall.Show()
        if (PositiveWall.IsValid[]):
            PositiveWall.Show()
        CoachProbeLog("PCL|health_probe|ready|combat_gates=false|health_interface_probe=true|ordinary_prop_control_unvalidated=true")
        set InitializationComplete = true
        if (AutoRun?):
            RunAutomaticSequence()

    OnEnd<override>():void =
        set Ending = true
        if (ParticipantInventoryOnly?):
            ParticipantSpawner.DespawnAll(false)
            ParticipantSpawner.Disable()
        TransitionPool.RetireAll()
        if (Wall := SpawnedControlWall?, Wall.IsValid[]):
            Wall.Dispose()
        CalibrationPlayerTeleporter.Disable()
        for (Binding : Bindings):
            Binding.Cancel()
        RestoreTeam()
        TeamWallRestored := RestoreTeamWallTeams()
        RemoveProbeRifle()
        NativeLeaseRestored := RestoreNativeToolLease()
        if (UseWeaponCalibration? and NativeLeaseRestored? and TeamWallRestored?):
            CalibrationShooter.DespawnAll(false)
            CalibrationShooter.Disable()
        if (Enabled?):
            ControlMonitor.Disable()
            EditedMonitor.Disable()
            PositiveMonitor.Disable()
        HideWalls()
        CalibrationObjective.Hide()

    RunParticipantInventoryProbe()<suspends>:void =
        var TestSubjects : []agent = array{}
        CoachProbeLog("PCL|health_probe|participant_inventory_waiting|expected_test_subjects=1")
        for (Tick := 1..50, TestSubjects.Length = 0):
            if (Ending?):
                return
            for (Candidate : GetPlayspace().GetParticipants()):
                var Human : logic = false
                for (Player : GetPlayspace().GetPlayers(), Player = Candidate):
                    set Human = true
                if (not Human?):
                    set TestSubjects += array{Candidate}
            if (TestSubjects.Length = 0):
                Sleep(0.2)
        if (TestSubjects.Length <> 1):
            CoachProbeLog("PCL|health_probe|participant_inventory_not_run|test_subject_count={TestSubjects.Length}|expected=1")
            return
        ParticipantSpawner.Disable()
        ParticipantSpawner.DespawnAll(false)
        ParticipantSpawner.Reset()
        defer:
            ParticipantSpawner.DespawnAll(false)
            ParticipantSpawner.Disable()
        CoachProbeLog("PCL|health_probe|participant_inventory_begin|human_players={GetPlayspace().GetPlayers().Length}|participants={GetPlayspace().GetParticipants().Length}|guard_control_and_configured_test_participant|no_spawner_behavior_or_inventory_override")
        ParticipantSpawner.Enable()
        ParticipantSpawner.Spawn()
        var Subject : ?agent = false
        for (Tick := 1..50, not Subject?):
            if (Ending?):
                return
            Agents := ParticipantSpawner.GetAgents()
            if (Agents.Length > 1):
                CoachProbeLog("PCL|health_probe|participant_inventory_not_run|multiple_spawned_agents")
                return
            if (Owner := Agents[0]):
                set Subject = option{Owner}
            else:
                Sleep(0.2)
        if (Owner := Subject?, TestSubject := TestSubjects[0]):
            CoachProbeLog("PCL|health_probe|participant_spawn_observed|owned_agents={ParticipantSpawner.GetAgents().Length}")
            for (Tick := 1..8):
                Sleep(0.5)
                if (Ending?):
                    return
                SampleParticipantInventory(Owner, "guard_control", Tick)
                SampleParticipantInventory(TestSubject, "test_participant", Tick)
            if (ParticipantItemAuditOnly?):
                RunParticipantItemAudit(TestSubject, Owner)
            else if (ParticipantBuildAction?):
                RunParticipantBuildAction(TestSubject, Owner)
            ParticipantSpawner.DespawnAll(false)
            ParticipantSpawner.Disable()
            for (Tick := 1..20, ParticipantSpawner.GetAgents().Length > 0):
                Sleep(0.1)
            var StillRegistered : int = 0
            for (Current : GetPlayspace().GetParticipants(), Current = Owner):
                set StillRegistered += 1
            var TestRegistered : int = 0
            for (Current : GetPlayspace().GetParticipants(), Current = TestSubject):
                set TestRegistered += 1
            CoachProbeLog("PCL|health_probe|participant_inventory_cleanup|owned_agents={ParticipantSpawner.GetAgents().Length}|guard_still_registered={StillRegistered}|test_still_registered={TestRegistered}|test_lifetime_ends_with_game_stop")
        else:
            CoachProbeLog("PCL|health_probe|participant_inventory_not_run|no_spawn_within_ten_seconds")

    RunParticipantItemAudit(Owner : agent, Guard : agent)<suspends>:void =
        CoachProbeLog("PCL|health_probe|participant_item_audit_begin|no_grants_transfers_attack_fire_or_build_commands")
        for (Subject -> Label : map{Owner => "participant", Guard => "guard"}):
            var Index : int = 0
            for (Inventory : Subject.FindDescendantComponents(inventory_component)):
                var Kind : string = "fort_other"
                if (fort_inventory_build_hotbar_component[Inventory]):
                    set Kind = "build_recipe"
                else if (fort_inventory_weapon_hotbar_component[Inventory]):
                    set Kind = "weapon_hotbar"
                else if (fort_inventory_harvest_tool_component[Inventory]):
                    set Kind = "harvest_tool"
                for (Value : Inventory.GetItems(), Item := Value.GetComponent[item_component]):
                    set Index += 1
                    CoachNativeItemActionAudit(Item, Label, Kind, Index, "initial")
        var OriginalEquipped : []item_component = array{}
        for (Inventory : Owner.FindDescendantComponents(inventory_component), Value : Inventory.GetItems(), Item := Value.GetComponent[item_component], Item.IsEquipped[]):
            set OriginalEquipped += array{Item}
        SelectionSnapshot := CoachCaptureNativeItemSelection(Owner)
        defer:
            MatchingItems := CoachRestoreNativeItemSelection(SelectionSnapshot)
            var Restored : int = 0
            for (Item : OriginalEquipped, Item.IsEquipped[]):
                set Restored += 1
            var BuildToolsEquipped : int = 0
            for (Inventory : Owner.FindDescendantComponents(fort_inventory_build_hotbar_component), Value : Inventory.GetItems(), Item := Value.GetComponent[item_component], Item.IsEquipped[]):
                set BuildToolsEquipped += 1
            CoachProbeLog("PCL|health_probe|participant_item_audit_equipment_restored|original={OriginalEquipped.Length}|restored={Restored}|build_tools_equipped={BuildToolsEquipped}|snapshot_items={SelectionSnapshot.Length}|matching_items={MatchingItems}|all_captured_parent_and_equipped_states_checked")
        var BuildIndex : int = 0
        for (Inventory : Owner.FindDescendantComponents(fort_inventory_build_hotbar_component), Value : Inventory.GetItems(), Item := Value.GetComponent[item_component]):
            set BuildIndex += 1
            Result := Item.Equip()
            Sleep(0.25)
            var Accepted : int = 0
            var Equipped : int = 0
            var Parent : int = 0
            if (Result.GetSuccess[]):
                set Accepted = 1
            if (Item.IsEquipped[]):
                set Equipped = 1
            if (Item.GetParentInventory[] = Inventory):
                set Parent = 1
            CoachProbeLog("PCL|health_probe|participant_item_audit_equip|index={BuildIndex}|accepted={Accepted}|equipped={Equipped}|parent={Parent}")
            CoachNativeItemActionAudit(Item, "participant", "build_recipe", BuildIndex, "equipped")
        if (Root := GetSimulationEntity[]):
            Control := assault_rifle_template{}
            Root.AddEntities(array{Control})
            defer:
                Control.RemoveFromParent()
                CoachProbeLog("PCL|health_probe|participant_item_audit_control_removed|public_template|never_granted_equipped_or_fired")
            Sleep(0.25)
            if (Item := Control.GetComponent[item_component]):
                CoachNativeItemActionAudit(Item, "public_rifle_control", "unmodified_assault_rifle_template", 1, "unowned_control")
            else:
                CoachProbeLog("PCL|health_probe|participant_item_audit_abort|public_rifle_item_missing")
                return
        CoachProbeLog("PCL|health_probe|participant_item_audit_finished|no_native_activation_or_internal_GAS_claim")

    RunParticipantBuildAction(Builder : agent, Target : agent)<suspends>:void =
        ResourcesBefore := CoachNativeResourceCounts(Builder)
        if (ResourcesBefore(0) <> 0):
            CoachProbeLog("PCL|health_probe|participant_action_abort|unexpected_initial_resources")
            return
        if (Character := Builder.GetFortCharacter[], Character.IsActive[], Body := Character.GetEntity[], Actions := Body.GetComponent[guard_actions_component], TargetCharacter := Target.GetFortCharacter[], TargetCharacter.IsActive[], TargetBody := TargetCharacter.GetEntity[], Root := GetSimulationEntity[]):
            Teams := GetPlayspace().GetTeamCollection()
            if (BuilderTeam := Teams.GetTeam[Builder], TargetTeam := Teams.GetTeam[Target], Friendly := Teams.GetTeams()[0], Enemy := Teams.GetTeams()[1]):
                BuilderPose := Character.GetTransform()
                TargetPose := TargetCharacter.GetTransform()
                TargetMaxHealth := TargetCharacter.GetMaxHealth()
                TargetHealth := TargetCharacter.GetHealth()
                TargetShield := TargetCharacter.GetShield()
                var BuilderVulnerable : logic = false
                var TargetVulnerable : logic = false
                if (Character.IsVulnerable[]):
                    set BuilderVulnerable = true
                if (TargetCharacter.IsVulnerable[]):
                    set TargetVulnerable = true
                var OriginalEquipped : []item_component = array{}
                for (Inventory : Builder.FindDescendantComponents(inventory_component), Value : Inventory.GetItems(), Item := Value.GetComponent[item_component], Item.IsEquipped[]):
                    set OriginalEquipped += array{Item}
                SelectionSnapshot := CoachCaptureNativeItemSelection(Builder)
                defer:
                    ParticipantWoodGranter.Disable()
                    TargetCharacter.ReleaseFromStasis()
                    TargetCharacter.SetMaxHealth(TargetMaxHealth)
                    TargetCharacter.SetHealth(TargetHealth)
                    TargetCharacter.SetShield(TargetShield)
                    TargetCharacter.SetVulnerability(TargetVulnerable)
                    Character.SetVulnerability(BuilderVulnerable)
                    var RestoredTeams : int = 0
                    if (Teams.AddToTeam[Builder, BuilderTeam]):
                        set RestoredTeams += 1
                    if (Teams.AddToTeam[Target, TargetTeam]):
                        set RestoredTeams += 1
                    MatchingItems := CoachRestoreNativeItemSelection(SelectionSnapshot)
                    CoachProbeLog("PCL|health_probe|participant_action_selection_restored|snapshot_items={SelectionSnapshot.Length}|matching_items={MatchingItems}|all_captured_parent_and_equipped_states_checked")
                    var RestoredEquipment : int = 0
                    for (Item : OriginalEquipped, Item.IsEquipped[]):
                        set RestoredEquipment += 1
                    var RemovedResources : int = 0
                    for (Inventory : Builder.FindDescendantComponents(fort_inventory_resources_component), Value : Inventory.GetItems()):
                        Removed := Inventory.RemoveItem(Value)
                        if (Removed.GetSuccess[]):
                            set RemovedResources += 1
                    var RestoredPoses : int = 0
                    if (Character.TeleportTo[BuilderPose.Translation, BuilderPose.Rotation]):
                        set RestoredPoses += 1
                    if (TargetCharacter.TeleportTo[TargetPose.Translation, TargetPose.Rotation]):
                        set RestoredPoses += 1
                    Remaining := CoachNativeResourceCounts(Builder)
                    CoachProbeLog("PCL|health_probe|participant_action_cleanup|teams={RestoredTeams}|original_equipped={OriginalEquipped.Length}|equipped_restored={RestoredEquipment}|poses={RestoredPoses}|removed_granted_resource_items={RemovedResources}|remaining_resources={Remaining(2)}|no_human_state_mutated")
                var AssignedTeams : int = 0
                if (Teams.AddToTeam[Builder, Friendly]):
                    set AssignedTeams += 1
                if (Teams.AddToTeam[Target, Enemy]):
                    set AssignedTeams += 1
                if (AssignedTeams <> 2):
                    CoachProbeLog("PCL|health_probe|participant_action_abort|team_assignment")
                    return
                Character.SetVulnerability(false)
                TargetCharacter.SetMaxHealth(5000.0)
                TargetCharacter.SetHealth(5000.0)
                TargetCharacter.SetShield(0.0)
                TargetCharacter.PutInStasis(stasis_args{AllowTurning := false, AllowFalling := false})
                TargetCharacter.SetVulnerability(true)
                var PlacedCharacters : int = 0
                if (Character.TeleportTo[vector3{X := -5120.0, Y := -3072.0, Z := 96.0}, MakeRotationFromYawPitchRollDegrees(90.0, 0.0, 0.0)]):
                    set PlacedCharacters += 1
                if (TargetCharacter.TeleportTo[vector3{X := -5120.0, Y := -2400.0, Z := 96.0}, IdentityRotation()]):
                    set PlacedCharacters += 1
                if (PlacedCharacters <> 2):
                    CoachProbeLog("PCL|health_probe|participant_action_abort|placement")
                    return
                var PoseReady : int = 0
                for (Tick := 1..40, PoseReady < 2):
                    Sleep(0.2)
                    BuilderPosition := Character.GetTransform().Translation
                    TargetPosition := TargetCharacter.GetTransform().Translation
                    BuilderError := Distance(BuilderPosition, vector3{X := -5120.0, Y := -3072.0, Z := 96.0})
                    TargetError := Distance(TargetPosition, vector3{X := -5120.0, Y := -2400.0, Z := 96.0})
                    CoachProbeLog("PCL|health_probe|participant_action_pose|tick={Tick}|builder_x={BuilderPosition.X}|builder_y={BuilderPosition.Y}|builder_z={BuilderPosition.Z}|target_x={TargetPosition.X}|target_y={TargetPosition.Y}|target_z={TargetPosition.Z}|builder_error={BuilderError}|target_error={TargetError}")
                    if (BuilderError <= 150.0 and TargetError <= 150.0):
                        set PoseReady += 1
                    else:
                        set PoseReady = 0
                if (PoseReady < 2):
                    CoachProbeLog("PCL|health_probe|participant_action_abort|pose_not_stable_within150cm")
                    return
                ParticipantWoodGranter.Enable()
                ParticipantWoodGranter.GrantItem(Builder)
                Sleep(0.5)
                Resources := CoachNativeResourceCounts(Builder)
                CoachProbeLog("PCL|health_probe|participant_action_grant|resource_items={Resources(0)}|known_stacks={Resources(1)}|total={Resources(2)}|expected_wood500")
                if (Resources(0) <> 1 or Resources(1) <> 1 or Resources(2) <> 500):
                    CoachProbeLog("PCL|health_probe|participant_action_abort|resource_grant_not_observed")
                    return
                var Selected : ?tuple(item_component, inventory_component) = false
                for (Inventory : Builder.FindDescendantComponents(fort_inventory_build_hotbar_component), Value : Inventory.GetItems(), Item := Value.GetComponent[item_component], not Selected?):
                    set Selected = option{(Item, Inventory)}
                if (Pair := Selected?, Pair(0).GetParentInventory[] = Pair(1)):
                    Tool := Pair(0)
                    Equipped := Tool.Equip()
                    if (not Equipped.GetSuccess[] or not Tool.IsEquipped[]):
                        CoachProbeLog("PCL|health_probe|participant_action_abort|initial_equip_unconfirmed")
                        return
                    var Detected : logic = false
                    race:
                        block:
                            for (Tick := 1..80, not Detected?):
                                if (HasHostileTargetLOS(Builder, TargetCharacter)?):
                                    set Detected = true
                                if (Mod[Tick, 20] = 0):
                                    BuilderPosition := Character.GetTransform().Translation
                                    TargetPosition := TargetCharacter.GetTransform().Translation
                                    CoachProbeLog("PCL|health_probe|participant_action_detection_pose|tick={Tick}|builder_x={BuilderPosition.X}|builder_y={BuilderPosition.Y}|builder_z={BuilderPosition.Z}|target_x={TargetPosition.X}|target_y={TargetPosition.Y}|target_z={TargetPosition.Z}")
                                Sleep(0.1)
                        block:
                            Actions.Focus(TargetBody, ?LockFocus := true)
                            loop:
                                Sleep(0.1)
                    if (not Detected? or not HasHostileTargetLOS(Builder, TargetCharacter)?):
                        var TargetEntries : int = 0
                        var VisibleEntries : int = 0
                        var HostileEntries : int = 0
                        var NativeHostile : int = 0
                        if (Awareness := Body.GetComponent[npc_awareness_component]):
                            for (Info : Awareness.DetectedTargets):
                                set TargetEntries += 1
                                if (Info.HasLineOfSight?):
                                    set VisibleEntries += 1
                                if (Info.Attitude = team_attitude.Hostile):
                                    set HostileEntries += 1
                        if (Teams.GetTeamAttitude[Builder, Target] = team_attitude.Hostile):
                            set NativeHostile = 1
                        CoachProbeLog("PCL|health_probe|participant_action_perception|entries={TargetEntries}|visible={VisibleEntries}|hostile={HostileEntries}|native_team_hostile={NativeHostile}|distance={Distance(Character.GetTransform().Translation, TargetCharacter.GetTransform().Translation)}")
                        CoachProbeLog("PCL|health_probe|participant_action_abort|hostile_current_los_unconfirmed")
                        return
                    if (not Tool.IsEquipped[]):
                        Refresh := Tool.Equip()
                        CoachProbeLog("PCL|health_probe|participant_action_single_equip_refresh|after_detection")
                        if (not Refresh.GetSuccess[] or not Tool.IsEquipped[]):
                            CoachProbeLog("PCL|health_probe|participant_action_abort|single_refresh_unconfirmed")
                            return
                    if (not Tool.GetParentInventory[] = Pair(1) or not Tool.IsEquipped[]):
                        CoachProbeLog("PCL|health_probe|participant_action_abort|final_item_precondition")
                        return
                    Center := Character.GetTransform().Translation
                    Baseline := CoachNativeStructureBodies(Root, Center, Body, TargetBody)
                    CoachProbeLog("PCL|health_probe|participant_action_ready|own_native_tool=1|kind_unverified|hostile_los=1|baseline_bodies={Baseline.Length}|resource_total={CoachNativeResourceCounts(Builder)(2)}|no_camera_or_custom_geometry_created")
                    race:
                        block:
                            var Returned : int = 0
                            defer:
                                CoachProbeLog("PCL|health_probe|participant_action_task_unwound|result_observed={Returned}")
                            CoachProbeLog("PCL|health_probe|participant_action_request|single_public_Attack|no_BeginFire_direct_Damage_or_simulated_build")
                            Result := Actions.Attack(TargetBody)
                            set Returned = 1
                            var Success : int = 0
                            if (Result.GetSuccess[]):
                                set Success = 1
                            CoachProbeLog("PCL|health_probe|participant_action_returned|success={Success}|not_placement_proof")
                            loop:
                                Sleep(0.1)
                        block:
                            for (Tick := 1..40):
                                Sleep(0.2)
                                Current := CoachNativeStructureBodies(Root, Center, Body, TargetBody)
                                var Added : int = 0
                                for (Value : Current):
                                    var Known : logic = false
                                    for (Existing : Baseline, Existing = Value):
                                        set Known = true
                                    if (not Known?):
                                        set Added += 1
                                        Position := FromTransform(Value.GetGlobalTransform()).Translation
                                        CoachProbeLog("PCL|health_probe|participant_action_body|tick={Tick}|x={Position.X}|y={Position.Y}|z={Position.Z}|native_class_slot_owner_unverified")
                                var EquippedNow : int = 0
                                var ParentNow : int = 0
                                if (Tool.IsEquipped[]):
                                    set EquippedNow = 1
                                if (Tool.GetParentInventory[] = Pair(1)):
                                    set ParentNow = 1
                                CurrentResources := CoachNativeResourceCounts(Builder)
                                CoachProbeLog("PCL|health_probe|participant_action_sample|tick={Tick}|equipped={EquippedNow}|parent={ParentNow}|bodies={Current.Length}|new_bodies={Added}|resources={CurrentResources(2)}|target_health={TargetCharacter.GetHealth()}|collision_census_not_native_build_proof")
                    CoachProbeLog("PCL|health_probe|participant_action_finished|bounded_eight_second_window|native_placement_edit_ownership_gates_unchanged")
                else:
                    CoachProbeLog("PCL|health_probe|participant_action_abort|own_build_recipe_missing")
            else:
                CoachProbeLog("PCL|health_probe|participant_action_abort|original_teams_unavailable")
        else:
            CoachProbeLog("PCL|health_probe|participant_action_abort|active_character_actions_or_root_unavailable")

    SampleParticipantInventory(Owner : agent, Role : string, Tick : int):void =
        var IsPlayer : int = 0
        var Registered : int = 0
        var HumanListed : int = 0
        var Behavior : int = 0
        if (player[Owner]):
            set IsPlayer = 1
        if (Owner.GetNPCBehavior[]):
            set Behavior = 1
        for (Current : GetPlayspace().GetParticipants(), Current = Owner):
            set Registered += 1
        for (Current : GetPlayspace().GetPlayers(), Current = Owner):
            set HumanListed += 1
        if (Character := Owner.GetFortCharacter[], Character.IsActive[], Body := Character.GetEntity[]):
            var Actions : int = 0
            var GuardActions : int = 0
            var Awareness : int = 0
            var GuardAwareness : int = 0
            if (Body.GetComponent[npc_actions_component]):
                set Actions = 1
            if (Body.GetComponent[guard_actions_component]):
                set GuardActions = 1
            if (Body.GetComponent[npc_awareness_component]):
                set Awareness = 1
            if (Body.GetComponent[guard_awareness_component]):
                set GuardAwareness = 1
            var Inventories : int = 0
            var Items : int = 0
            var ParentMatches : int = 0
            var BuildHotbars : int = 0
            var BuildTools : int = 0
            var ResourceItems : int = 0
            var ResourceTotal : int = 0
            for (Inventory : Owner.FindDescendantComponents(inventory_component)):
                set Inventories += 1
                for (Value : Inventory.GetItems(), Item := Value.GetComponent[item_component]):
                    set Items += 1
                    if (Item.GetParentInventory[] = Inventory):
                        set ParentMatches += 1
            for (Inventory : Owner.FindDescendantComponents(fort_inventory_build_hotbar_component)):
                set BuildHotbars += 1
                set BuildTools += Inventory.GetItems().Length
            for (Inventory : Owner.FindDescendantComponents(fort_inventory_resources_component), Value : Inventory.GetItems()):
                set ResourceItems += 1
                if (Stack := Value.GetComponent[stackable_component]):
                    set ResourceTotal += Stack.StackSize
            CoachProbeLog("PCL|health_probe|participant_inventory_sample|role={Role}|tick={Tick}|character_entity=1|is_player={IsPlayer}|registered={Registered}|human_listed={HumanListed}|behavior={Behavior}|npc_actions={Actions}|guard_actions={GuardActions}|awareness={Awareness}|guard_awareness={GuardAwareness}|inventories={Inventories}|items={Items}|parent_matches={ParentMatches}|build_hotbars={BuildHotbars}|build_tools={BuildTools}|resource_items={ResourceItems}|resource_total={ResourceTotal}")
            if (Tick = 1):
                LogNativeBuildInventory(Owner, Role)
        else:
            CoachProbeLog("PCL|health_probe|participant_inventory_sample|role={Role}|tick={Tick}|character_entity=0|is_player={IsPlayer}|registered={Registered}|human_listed={HumanListed}|behavior={Behavior}")

    LearningFrame(At : float, X : float, Visibility : ?logic):coach_combat_frame =
        return coach_combat_frame{At := At, PlayerPosition := vector3{X := X}, OpponentPosition := vector3{X := 2000.0}, VisibleToOpponent := Visibility}

    CheckLearning(Name : string, Passed : logic):void =
        if (Passed?):
            CoachProbeLog("PCL|health_probe|learning_check|case={Name}|passed=1")
        else:
            set LearningCheckFailures += 1
            CoachProbeLog("PCL|health_probe|learning_check|case={Name}|passed=0")

    # Deterministic event sequences against the actual learning class; no character or item access.
    RunLearningObservationChecks():void =
        set LearningCheckFailures = 0
        Positive := coach_human_pattern_model{}
        Positive.ObserveVisibleFrame(LearningFrame(1.0, 0.0, option{true}))
        Positive.ObserveVisibleFrame(LearningFrame(1.2, 100.0, option{true}))
        CheckLearning("visible_pair_learns", logic{Positive.Samples = 1.0 and Positive.RecentAt = 1.2})
        Positive.RewardObservedPattern(1.3)
        Positive.RewardObservedPattern(1.4)
        CheckLearning("reward_is_time_separated", logic{Positive.Successes = 1.0 and Positive.Forward > 0.0})

        Hidden := coach_human_pattern_model{}
        Hidden.ObserveVisibleFrame(LearningFrame(10.0, 0.0, option{true}))
        Hidden.ObserveVisibleFrame(LearningFrame(10.1, 40.0, option{false}))
        Hidden.ObserveVisibleFrame(LearningFrame(10.2, 80.0, option{true}))
        CheckLearning("short_hidden_gap_not_bridged", logic{Hidden.Samples = 0.0})
        Hidden.ObserveVisibleFrame(LearningFrame(10.4, 120.0, option{true}))
        Hidden.RewardObservedPattern(10.45)
        CheckLearning("visible_learning_recovers", logic{Hidden.Samples = 1.0 and Hidden.Successes = 1.0})

        Unknown := coach_human_pattern_model{}
        Unknown.ObserveVisibleFrame(LearningFrame(20.0, 0.0, option{true}))
        Unknown.ObserveVisibleFrame(LearningFrame(20.1, 40.0, false))
        Unknown.ObserveVisibleFrame(LearningFrame(20.2, 80.0, option{true}))
        CheckLearning("short_unknown_gap_not_bridged", logic{Unknown.Samples = 0.0})

        VisibilityCases : []?logic = array{option{false}, false}
        for (Index -> Visibility : VisibilityCases):
            Lost := coach_human_pattern_model{}
            Lost.ObserveVisibleFrame(LearningFrame(30.0, 0.0, option{true}))
            Lost.ObserveVisibleFrame(LearningFrame(30.2, 100.0, option{true}))
            Lost.ObserveVisibleFrame(LearningFrame(30.25, 120.0, Visibility))
            Lost.RewardObservedPattern(30.3)
            if (Index = 0):
                CheckLearning("hidden_cancels_pending_reward", logic{Lost.Successes = 0.0})
            else:
                CheckLearning("unknown_cancels_pending_reward", logic{Lost.Successes = 0.0})

        Gap := coach_human_pattern_model{}
        Gap.ObserveVisibleFrame(LearningFrame(40.0, 0.0, option{true}))
        Gap.ObserveVisibleFrame(LearningFrame(40.2, 100.0, option{true}))
        Gap.ObserveVisibleFrame(LearningFrame(40.72, 150.0, option{true}))
        Gap.RewardObservedPattern(40.74)
        CheckLearning("long_gap_cancels_pending_reward", logic{Gap.Successes = 0.0})

        Teleported := coach_human_pattern_model{}
        Teleported.ObserveVisibleFrame(LearningFrame(50.0, 0.0, option{true}))
        Teleported.ObserveVisibleFrame(LearningFrame(50.2, 100.0, option{true}))
        Teleported.ObserveVisibleFrame(LearningFrame(50.4, 1800.0, option{true}))
        Teleported.RewardObservedPattern(50.45)
        CheckLearning("teleport_cancels_pending_reward", logic{Teleported.Successes = 0.0})

        Reordered := coach_human_pattern_model{}
        Reordered.ObserveVisibleFrame(LearningFrame(60.0, 0.0, option{true}))
        Reordered.ObserveVisibleFrame(LearningFrame(60.2, 100.0, option{true}))
        Reordered.ObserveVisibleFrame(LearningFrame(60.1, 50.0, option{true}))
        Reordered.RewardObservedPattern(60.25)
        CheckLearning("reordered_frame_cancels_pending_reward", logic{Reordered.Successes = 0.0})

        Positive.ResetObservation()
        Positive.RewardObservedPattern(1.5)
        CheckLearning("reset_cancels_pending_reward", logic{Positive.Successes = 1.0 and not Positive.StudyFrame?})

    HideWalls():void =
        if (ControlWall.IsValid[]):
            ControlWall.Hide()
        if (EditedWall.IsValid[]):
            EditedWall.Hide()
        if (PositiveWall.IsValid[]):
            PositiveWall.Hide()

    ControlTarget()<transacts>:creative_prop =
        if (NativeWallTransitionControl? and TransitionPhase = 2):
            return EditedWall
        if (Wall := SpawnedControlWall?):
            return Wall
        return ControlWall

    AllocateControlWall():logic =
        if (SpawnedWallGeneration >= 2 or not ControlWall.IsValid[]):
            return false
        OriginalPose := ControlWall.GetTransform()
        Result := SpawnProp(SpawnedWallAsset, OriginalPose)
        if (Wall := Result(0)?, Result(1) = spawn_prop_result.Ok):
            Wall.SetMesh(Structures.WallSolidMesh)
            set Wall.CanBeDamaged = true
            Wall.Show()
            set SpawnedControlWall = option{Wall}
            set SpawnedWallGeneration += 1
            set LastControlWallPosition = option{OriginalPose.Translation}
            var Damageable : int = 0
            if (Wall.CanBeDamaged?):
                set Damageable = 1
            CoachProbeLog("PCL|health_probe|spawned_wall_allocated|generation={SpawnedWallGeneration}|can_be_damaged={Damageable}|native_picker_asset|no_health_write|not_native_build_edit")
            return true
        CoachProbeLog("PCL|health_probe|spawned_wall_allocation_failed|generation={SpawnedWallGeneration}|status={CoachSpawnStatus(Result(1))}")
        return false

    ObserveSpawnedWallLifetime(Weapon : fort_trace_weapon_component)<suspends>:void =
        if (SpawnedWallControl?, Wall := SpawnedControlWall?, not Wall.IsValid[], ObservedSpawnedWallDeaths < SpawnedWallGeneration):
            set ObservedSpawnedWallDeaths = SpawnedWallGeneration
            Weapon.EndFire()
            CoachProbeLog("PCL|health_probe|spawned_wall_became_invalid|generation={SpawnedWallGeneration}|native_fire_only|no_Dispose_or_Damage_during_trial")
            LogCalibrationWallState("spawned_destroyed_before_replacement")
            if (SpawnedWallGeneration < 2, not NativeTeamWallControl?):
                Allocated := AllocateControlWall()
                Sleep(0.25)
                LogCalibrationWallState("spawned_replacement_settled")
                if (not Allocated?):
                    CoachProbeLog("PCL|health_probe|spawned_wall_replacement_failed")
            Weapon.BeginFire()

    RestoreTeam():void =
        if (Agent := ChangedTeamAgent?, Previous := OriginalTeam?):
            if (GetPlayspace().GetTeamCollection().AddToTeam[Agent, Previous]):
                set ChangedTeamAgent = false
                set OriginalTeam = false
                CoachProbeLog("PCL|health_probe|instigator_team_restored")
            else:
                CoachProbeLog("PCL|health_probe|instigator_team_restore_failed")

    ReadHealth(Value : creative_prop)<transacts>:string =
        if (Health := healthful[Value]):
            Current := Health.GetHealth()
            Maximum := Health.GetMaxHealth()
            return "{Current}/{Maximum}"
        return "healthful_cast_unavailable"

    OnControlBlast(Agent : agent):void =
        set ControlBlasts += 1

    OnEditedBlast(Agent : agent):void =
        set EditedBlasts += 1

    OnControlDamage(Agent : agent):void =
        if (NativeWallTransitionControl? and TransitionPhase <> 1):
            CoachProbeLog("PCL|health_probe|native_transition_unexpected_callback|source=control_damage|phase={TransitionPhase}")
            return
        RecordMeasuredWallDamage(Agent)

    RecordMeasuredWallDamage(Agent : agent):void =
        set ControlDamageEvents += 1
        var ByPlayer : int = 0
        if (Owner := CalibratedPlayer?, Owner = Agent):
            set ByPlayer = 1
            set ControlPlayerHits += 1
        CoachProbeLog("PCL|health_probe|control_wall_damage|by_player={ByPlayer}|events={ControlDamageEvents}|player_hits={ControlPlayerHits}|agent_callback")
        if (NativeWallTransitionControl?):
            if (ByPlayer = 1, ControlPlayerHits = 3, not TransitionPending?, not TransitionDone?, not TransitionFailed?):
                set TransitionPending = true
                if (Rifle := ProbeRifle?, Weapon := Rifle.GetComponent[fort_trace_weapon_component]):
                    Weapon.EndFire()
                    CoachProbeLog("PCL|health_probe|native_transition_pause_requested|phase={TransitionPhase}|player_hits={ControlPlayerHits}|native_fire_stop_requested")
                else:
                    set TransitionFailed = true
                    CoachProbeLog("PCL|health_probe|native_transition_not_run|rifle_unavailable_at_pause")
            return
        if (ByPlayer = 1, MeshChangeAfterPlayerHits > 0, ControlPlayerHits >= MeshChangeAfterPlayerHits, not ControlMeshChanged?, ControlWall.IsValid[]):
            set ControlMeshChanged = true
            LogCalibrationWallState("mesh_change_before")
            ControlWall.SetMesh(Structures.WallWindowMesh)
            CoachProbeLog("PCL|health_probe|control_wall_mesh_changed|after_player_hits={ControlPlayerHits}|same_reference|shape=window|no_health_write")
            LogCalibrationWallState("mesh_change_immediate")
            spawn { ObserveChangedWallCollision() }

    ObserveChangedWallCollision()<suspends>:void =
        Sleep(0.2)
        if (not Ending?):
            LogCalibrationWallState("mesh_change_settled")

    OnEditedDamage(Agent : agent):void =
        set EditedDamageEvents += 1
        if (NativeWallTransitionControl?):
            if (TransitionPhase = 2):
                RecordMeasuredWallDamage(Agent)
            else:
                CoachProbeLog("PCL|health_probe|native_transition_unexpected_callback|source=edited_damage|phase={TransitionPhase}")

    OnControlDestroyed(Agent : agent):void =
        if (NativeWallTransitionControl? and TransitionPhase <> 1):
            CoachProbeLog("PCL|health_probe|native_transition_unexpected_callback|source=control_destroyed|phase={TransitionPhase}")
            return
        RecordMeasuredWallDestroyed(Agent)

    RecordMeasuredWallDestroyed(Agent : agent):void =
        set ControlDestroyedEvents += 1
        var ByPlayer : int = 0
        if (Owner := CalibratedPlayer?, Owner = Agent):
            set ByPlayer = 1
        CoachProbeLog("PCL|health_probe|control_wall_destroyed|by_player={ByPlayer}|events={ControlDestroyedEvents}")

    OnEditedDestroyed(Agent : agent):void =
        set EditedDestroyedEvents += 1
        if (NativeWallTransitionControl?):
            if (TransitionPhase = 2):
                RecordMeasuredWallDestroyed(Agent)
            else:
                CoachProbeLog("PCL|health_probe|native_transition_unexpected_callback|source=edited_destroyed|phase={TransitionPhase}")

    OnPositiveBlast(Agent : agent):void =
        set PositiveBlasts += 1

    OnPositiveDamage(Agent : agent):void =
        set PositiveDamageEvents += 1

    OnPositiveDestroyed(Agent : agent):void =
        set PositiveDestroyedEvents += 1

    OnCalibrationBlast(Agent : agent):void =
        set CalibrationBlasts += 1

    OnCalibrationDamage(Result : damage_result):void =
        set CalibrationDamageEvents += 1
        var ByPlayer : int = 0
        if (Owner := CalibratedPlayer?, Instigator := Result.Instigator?, Instigator.GetInstigatorAgent[] = Owner):
            set ByPlayer = 1
            if (Result.Amount > 0.0):
                set ObjectivePlayerHits += 1
        CoachProbeLog("PCL|health_probe|calibration_damage_event|amount={Result.Amount}|by_player={ByPlayer}|player_hits={ObjectivePlayerHits}")

    OnShooterSpawned(Agent : agent):void =
        if (Shooter?):
            set CombatTarget = option{Agent}
            CoachProbeLog("PCL|health_probe|weapon_combat_target_spawned")
        else:
            set Shooter = option{Agent}
            CoachProbeLog("PCL|health_probe|weapon_shooter_spawned")

    OnCalibrationPlayerTeleported(Agent : agent):void =
        set PlayerTeleports += 1
        CoachProbeLog("PCL|health_probe|native_player_teleport_event|count={PlayerTeleports}")

    OnCombatTargetDamaged(Result : damage_result):void =
        set CombatDamageEvents += 1
        var ByShooter : int = 0
        if (Agent := Shooter?, Instigator := Result.Instigator?, Instigator.GetInstigatorAgent[] = Agent):
            set ByShooter = 1
            if (Result.Amount > 0.0):
                set CombatHitsByShooter += 1
        CoachProbeLog("PCL|health_probe|combat_target_damage|amount={Result.Amount}|by_shooter={ByShooter}")

    OnPlayerTargetDamaged(Result : damage_result):void =
        var ByPlayer : int = 0
        if (Owner := CalibratedPlayer?, Instigator := Result.Instigator?, Instigator.GetInstigatorAgent[] = Owner):
            set ByPlayer = 1
            if (Result.Amount > 0.0):
                set PlayerTargetHits += 1
        CoachProbeLog("PCL|health_probe|player_target_damage|amount={Result.Amount}|by_player={ByPlayer}|player_hits={PlayerTargetHits}")

    LogPlayerShotQuery(Character : fort_character, Aim : vector3, CharacterTarget : ?fort_character):void =
        if (Root := GetSimulationEntity[], OwnerBody := Character.GetEntity[]):
            Start := Character.GetViewLocation()
            Sphere := collision_sphere{Radius := 1.0, CollisionProfile := CollisionProfiles.DynamicOverlapAll}
            var Count : int = 0
            var Nearest : float = 1000000.0
            var NearestIsTarget : int = 0
            for (Hit : Root.FindSweepHits(FromVector3(Aim - Start), FromTransform(transform{Translation := Start}), Sphere)):
                HitEntity := Hit.TargetComponent.Entity
                var Ignore : logic = false
                if (HitEntity = OwnerBody):
                    set Ignore = true
                for (Ancestor : HitEntity.FindAncestorEntities(entity), Ancestor = OwnerBody):
                    set Ignore = true
                if (Rifle := ProbeRifle?):
                    if (HitEntity = Rifle):
                        set Ignore = true
                    for (Ancestor : HitEntity.FindAncestorEntities(entity), Ancestor = Rifle):
                        set Ignore = true
                if (not Ignore?):
                    var IsTarget : int = 0
                    if (Target := CharacterTarget?, TargetBody := Target.GetEntity[]):
                        if (HitEntity = TargetBody):
                            set IsTarget = 1
                        for (Ancestor : HitEntity.FindAncestorEntities(entity), Ancestor = TargetBody):
                            set IsTarget = 1
                    Position : vector3 = FromVector3(Hit.ContactPosition)
                    Range := Distance(Start, Position)
                    set Count += 1
                    if (Range < Nearest):
                        set Nearest = Range
                        set NearestIsTarget = IsTarget
                    if (Count <= 8):
                        CoachProbeLog("PCL|health_probe|player_view_query_hit|index={Count}|distance_cm={Range}|x={Position.X}|y={Position.Y}|z={Position.Z}|target_entity={IsTarget}")
            CoachProbeLog("PCL|health_probe|player_view_query_summary|count={Count}|nearest_cm={Nearest}|nearest_is_target={NearestIsTarget}|all_channel_overlap_sphere|query_not_native_ballistic_trace")

    FindProbeWeapon(Body : entity)<transacts>:?fort_trace_weapon_component =
        for (Inventory : Body.FindDescendantComponents(inventory_component), Item : Inventory.GetItems()):
            if (Component := Item.GetComponent[item_component], Component.IsEquipped[], Weapon := Item.GetComponent[fort_trace_weapon_component]):
                return option{Weapon}
        return false

    LogInventoryScope(Name : string, Body : entity):void =
        var Direct : int = 0
        var Descendants : int = 0
        var Hotbars : int = 0
        var Items : int = 0
        var TraceWeapons : int = 0
        var RangedItems : int = 0
        var Resources : int = 0
        var ResourceStacks : int = 0
        var ResourceQuantity : int = 0
        var ResourceInventories : int = 0
        if (Body.GetComponent[inventory_component]):
            set Direct = 1
        for (Inventory : Body.FindDescendantComponents(inventory_component)):
            set Descendants += 1
            for (Item : Inventory.GetItems()):
                set Items += 1
                if (Item.GetComponent[fort_trace_weapon_component]):
                    set TraceWeapons += 1
                if (Component := Item.GetComponent[item_component]):
                    for (Category : Component.Categories, Category = FortniteItemCategories.WeaponRanged):
                        set RangedItems += 1
                    for (Category : Component.Categories, Category = FortniteItemCategories.Resource):
                        set Resources += 1
                        if (Stack := Item.GetComponent[stackable_component]):
                            set ResourceStacks += 1
                            set ResourceQuantity += Stack.StackSize
        for (Inventory : Body.FindDescendantComponents(fort_inventory_weapon_hotbar_component)):
            set Hotbars += 1
        for (Inventory : Body.FindDescendantComponents(fort_inventory_resources_component)):
            set ResourceInventories += 1
        CoachProbeLog("PCL|health_probe|inventory_scope|name={Name}|direct={Direct}|descendants={Descendants}|hotbars={Hotbars}|items={Items}|trace_weapons={TraceWeapons}|ranged_items={RangedItems}|resources={Resources}|resource_stacks={ResourceStacks}|resource_quantity={ResourceQuantity}|resource_inventories={ResourceInventories}")

    AddProbeRifle(Body : entity):logic =
        if (Root := Body.GetSimulationEntity[]):
            Rifle := assault_rifle_template{}
            Root.AddEntities(array{Rifle})
            set ProbeRifle = option{Rifle}
            var HasItem : int = 0
            var HasTrace : int = 0
            if (Rifle.GetComponent[item_component]):
                set HasItem = 1
            if (Rifle.GetComponent[fort_trace_weapon_component]):
                set HasTrace = 1
            CoachProbeLog("PCL|health_probe|rifle_components|item={HasItem}|trace={HasTrace}")
            for (Child : Body.GetEntities(), Inventory := Child.GetComponent[inventory_component]):
                Added := Inventory.AddItemDistribute(Rifle)
                if (Added.GetSuccess[], Item := Rifle.GetComponent[item_component]):
                    CoachProbeLog("PCL|health_probe|weapon_add_returned_ok")
                    Equipped := Item.Equip()
                    if (Equipped.GetSuccess[]):
                        CoachProbeLog("PCL|health_probe|weapon_native_template_equipped|firing_unconfirmed")
                        return true
                    else if (Errors := Equipped.GetError[]):
                        CoachProbeLog("PCL|health_probe|weapon_equip_rejected|error_count={Errors.Length}")
                else if (Errors := Added.GetError[]):
                    CoachProbeLog("PCL|health_probe|weapon_add_rejected|error_count={Errors.Length}")
            RemoveProbeRifle()
        else:
            CoachProbeLog("PCL|health_probe|weapon_add_not_run|simulation_root_unavailable")
        return false

    RemoveProbeRifle():void =
        if (Rifle := ProbeRifle?):
            Removed := CoachRemoveOwnedItem(Rifle)
            if (Removed?):
                set ProbeRifle = false

    RestorePlayerEquipment(Items : []item_component):void =
        for (PreviousItem : Items):
            if (not PreviousItem.IsEquipped[]):
                Restored := PreviousItem.Equip()
                if (not Restored.GetSuccess[]):
                    CoachProbeLog("PCL|health_probe|player_control_equipment_restore_failed")

    LogCalibrationWallState(Phase : string):void =
        ActiveWall := ControlTarget()
        var Valid : int = 0
        var Cells : int = -1
        var Position : vector3 = vector3{}
        var Health : string = "unavailable"
        var HasPosition : logic = false
        if (ActiveWall.IsValid[]):
            set Valid = 1
            set Position = ActiveWall.GetTransform().Translation
            set LastControlWallPosition = option{Position}
            set HasPosition = true
            set Health = ReadHealth(ActiveWall)
        else if (Previous := LastControlWallPosition?):
            set Position = Previous
            set HasPosition = true
        if (HasPosition?, Root := GetSimulationEntity[]):
            Sample := Geometry.SampleWall(Root, Position, 90.0)
            set Cells = Sample.Occupied
        CoachProbeLog("PCL|health_probe|control_wall_state|phase={Phase}|valid={Valid}|cells={Cells}|x={Position.X}|y={Position.Y}|z={Position.Z}|health={Health}|damage_events={ControlDamageEvents}|player_hits={ControlPlayerHits}|destroyed_events={ControlDestroyedEvents}|query_yaw=90")

    SampleNativeFire(Weapon : fort_trace_weapon_component, Character : fort_character, Phase : string, ?CharacterTarget : ?fort_character = false)<suspends>:void =
        ItemPosition : vector3 = FromTransform(Weapon.Entity.GetGlobalTransform()).Translation
        CoachProbeLog("PCL|health_probe|weapon_entity_pose|phase={Phase}|x={ItemPosition.X}|y={ItemPosition.Y}|z={ItemPosition.Z}|entity_pose_not_native_muzzle")
        LogCalibrationWallState("{Phase}_before")
        if (NativeTeamWallControl? or NativeWallTransitionControl?):
            EntryPoseReady := CheckTeamWallShotPose(Character, Phase)
            if (not EntryPoseReady?):
                return
        Weapon.BeginFire()
        defer:
            Weapon.EndFire()
            LogCalibrationWallState("{Phase}_after")
        if (NativeWallTransitionControl?):
            Started := AwaitNativeTransitionFiring(Weapon, Character, true, "{Phase}_begin")
            if (not Started?):
                set TransitionFailed = true
                CoachProbeLog("PCL|health_probe|native_transition_not_run|firing_start_unconfirmed")
                return
        for (Tick := 1..20):
            Sleep(0.25)
            if (Ending? or not Character.IsActive[]):
                return
            if (NativeTeamWallControl? or NativeWallTransitionControl?):
                ShotPoseReady := CheckTeamWallShotPose(Character, Phase)
                if (not ShotPoseReady?):
                    return
            if (NativeWallTransitionControl? and TransitionPending?):
                TransitionSucceeded := PerformNativeWallTransition(Weapon, Character)
                if (not TransitionSucceeded? or Ending? or not Character.IsActive[]):
                    return
                Weapon.BeginFire()
                Resumed := AwaitNativeTransitionFiring(Weapon, Character, true, "transition_resume")
                if (not Resumed?):
                    set TransitionFailed = true
                    CoachProbeLog("PCL|health_probe|native_transition_not_run|firing_resume_unconfirmed")
                    return
            ObserveSpawnedWallLifetime(Weapon)
            var Firing : int = 0
            var Holstered : int = 0
            var Simulating : int = 0
            var NoFireZone : int = 0
            var TargetHealth : float = -1.0
            if (Target := CharacterTarget?):
                set TargetHealth = Target.GetHealth()
            if (Agent := Character.GetAgent[], CalibrationNoFireZone.IsInVolume[Agent]):
                set NoFireZone = 1
            if (Weapon.IsFiring[]):
                set Firing = 1
            if (Weapon.IsHolstered?):
                set Holstered = 1
            if (Weapon.IsSimulating[]):
                set Simulating = 1
            var WallValid : int = 0
            if (ControlTarget().IsValid[]):
                set WallValid = 1
            CoachProbeLog("PCL|health_probe|weapon_sample|phase={Phase}|tick={Tick}|is_firing={Firing}|holstered={Holstered}|simulating={Simulating}|no_fire_zone={NoFireZone}|shot_cost={Weapon.ShotAmmoCost}|objective_health={CalibrationObjective.GetHealth()}|damage_events={CalibrationDamageEvents}|objective_player_hits={ObjectivePlayerHits}|character_health={TargetHealth}|player_hits={PlayerTargetHits}|wall_valid={WallValid}|wall_damage_events={ControlDamageEvents}|wall_player_hits={ControlPlayerHits}|wall_destroyed_events={ControlDestroyedEvents}")

    SampleNativeCombat(Target : fort_character, Phase : string, Ticks : int)<suspends>:void =
        for (Tick := 1..Ticks):
            Sleep(0.25)
            if (Ending? or not Target.IsActive[]):
                CoachProbeLog("PCL|health_probe|combat_sample_stopped|phase={Phase}|target_inactive")
                return
            Position := Target.GetTransform().Translation
            var Alert : int = -1
            var NoFireZone : int = 0
            var SourcePosition : vector3 = vector3{}
            if (Agent := Shooter?, Character := Agent.GetFortCharacter[], Body := Character.GetEntity[], Awareness := Body.GetComponent[guard_awareness_component], TargetBody := Target.GetEntity[]):
                set SourcePosition = Character.GetTransform().Translation
                if (CalibrationNoFireZone.IsInVolume[Agent]):
                    set NoFireZone = 1
                Level := Awareness.GetAlertLevel(TargetBody)
                if (Level = guard_alert_level.Unaware):
                    set Alert = 0
                else if (Level = guard_alert_level.Suspicious):
                    set Alert = 1
                else if (Level = guard_alert_level.LostTarget):
                    set Alert = 2
                else if (Level = guard_alert_level.Alerted):
                    set Alert = 3
            CoachProbeLog("PCL|health_probe|combat_sample|phase={Phase}|tick={Tick}|native_loadout_only|alert={Alert}|no_fire_zone={NoFireZone}|source_x={SourcePosition.X}|source_y={SourcePosition.Y}|source_z={SourcePosition.Z}|target_health={Target.GetHealth()}|damage_events={CombatDamageEvents}|source_hits={CombatHitsByShooter}|target_x={Position.X}|target_y={Position.Y}|target_z={Position.Z}")

    RunNPCCombatControl(Attacker : agent, Actions : guard_actions_component, ?Viewer : ?agent = false)<suspends>:void =
        CalibrationShooter.Spawn()
        for (Attempt := 0..99):
            if (Ending?):
                return
            if (Target := CombatTarget?, TargetCharacter := Target.GetFortCharacter[], TargetCharacter.IsActive[], TargetBody := TargetCharacter.GetEntity[], AttackerCharacter := Attacker.GetFortCharacter[], AttackerBody := AttackerCharacter.GetEntity[], Awareness := AttackerBody.GetComponent[npc_awareness_component]):
                Teams := GetPlayspace().GetTeamCollection()
                if (PreviousTeam := Teams.GetTeam[Target], EnemyTeam := Teams.GetTeams()[1], Teams.AddToTeam[Target, EnemyTeam], Attitude := Teams.GetTeamAttitude[Attacker, Target], Attitude = team_attitude.Hostile):
                    defer:
                        TargetCharacter.ReleaseFromStasis()
                        TargetCharacter.SetVulnerability(false)
                        if (Teams.AddToTeam[Target, PreviousTeam]):
                            CoachProbeLog("PCL|health_probe|combat_target_team_restore_returned_ok")
                        else:
                            CoachProbeLog("PCL|health_probe|combat_target_team_restore_failed")
                    if (TargetCharacter.TeleportTo[vector3{X := -2848.0, Y := -2400.0, Z := 96.0}, IdentityRotation()]) {}
                    else:
                        CoachProbeLog("PCL|health_probe|combat_control_not_run|target_placement_rejected")
                        return
                    TargetPosition := TargetCharacter.GetTransform().Translation
                    CoachProbeLog("PCL|health_probe|combat_target_pose|x={TargetPosition.X}|y={TargetPosition.Y}|z={TargetPosition.Z}")
                    TargetCharacter.SetMaxHealth(5000.0)
                    TargetCharacter.SetHealth(5000.0)
                    if (VisualNativeCaptureSeconds > 0.0):
                        TargetCharacter.SetMaxHealth(50000.0)
                        TargetCharacter.SetHealth(50000.0)
                    TargetCharacter.SetShield(0.0)
                    TargetCharacter.PutInStasis(stasis_args{AllowTurning := false, AllowFalling := false})
                    TargetCharacter.SetVulnerability(true)
                    set CombatDamageEvents = 0
                    set CombatHitsByShooter = 0
                    Binding := TargetCharacter.DamagedEvent().Subscribe(OnCombatTargetDamaged)
                    defer:
                        Binding.Cancel()
                    CoachProbeLog("PCL|health_probe|combat_control_ready|hostile_team_confirmed|target_health={TargetCharacter.GetHealth()}|initialization_before_measurement")
                    var Detected : logic = false
                    race:
                        block:
                            for (Wait := 0..79, not Detected?):
                                for (Info : Awareness.DetectedTargets, Info.Target = TargetBody or Info.Target = Target, Info.Attitude = team_attitude.Hostile, Info.HasLineOfSight?):
                                    set Detected = true
                                    var Hostile : int = 0
                                    var Visible : int = 0
                                    if (Info.Attitude = team_attitude.Hostile):
                                        set Hostile = 1
                                    if (Info.HasLineOfSight?):
                                        set Visible = 1
                                    CoachProbeLog("PCL|health_probe|combat_detection_state|native_hostile={Hostile}|has_los={Visible}")
                                Sleep(0.1)
                            if (Detected?):
                                CoachProbeLog("PCL|health_probe|combat_target_detected|baseline_without_attack_request")
                                SampleNativeCombat(TargetCharacter, "detected_baseline", 8)
                            else:
                                CoachProbeLog("PCL|health_probe|combat_control_not_run|hostile_line_of_sight_not_confirmed")
                        block:
                            Actions.Focus(TargetBody, ?LockFocus := true)
                            loop:
                                Sleep(0.1)
                    if (Detected? and TargetCharacter.IsActive[]):
                        if (VisualNativeCaptureSeconds > 0.0):
                            if (VisualUseViewportCamera?):
                                if (ViewerAgent := Viewer?, player[ViewerAgent]):
                                    RunNativeVisualViewport(Attacker, AttackerCharacter, TargetCharacter, TargetBody, Actions, ViewerAgent)
                                else:
                                    CoachProbeLog("PCL|health_probe|native_visual_camera_not_run|player_viewer_missing")
                            else:
                                RunNativeVisualWindow(Attacker, AttackerCharacter, TargetCharacter, TargetBody, Actions)
                            CoachProbeLog("PCL|health_probe|npc_native_visual_finished|target_health={TargetCharacter.GetHealth()}|source_hits={CombatHitsByShooter}|native_original_inventory_only")
                            return
                        CoachProbeLog("PCL|health_probe|combat_attack_request|no_BeginFire_or_direct_Damage")
                        race:
                            block:
                                Result := Actions.Attack(TargetBody)
                                if (Result.GetSuccess[]):
                                    CoachProbeLog("PCL|health_probe|combat_attack_returned_ok")
                                else:
                                    CoachProbeLog("PCL|health_probe|combat_attack_returned_error")
                                loop:
                                    Sleep(0.1)
                            SampleNativeCombat(TargetCharacter, "guard_attack", 48)
                        Actions.StopNavigation()
                        for (Pulse := 1..10, TargetCharacter.IsActive[]):
                            race:
                                block:
                                    Result := Actions.Attack(TargetBody)
                                    loop:
                                        Sleep(0.05)
                                Sleep(0.35)
                            Sleep(0.15)
                            CoachProbeLog("PCL|health_probe|combat_attack_pulse|index={Pulse}|target_health={TargetCharacter.GetHealth()}|damage_events={CombatDamageEvents}|source_hits={CombatHitsByShooter}")
                        Actions.StopNavigation()
                else:
                    CoachProbeLog("PCL|health_probe|combat_control_not_run|hostile_team_unconfirmed")
                return
            Sleep(0.1)
        CoachProbeLog("PCL|health_probe|combat_control_not_run|target_unavailable")

    RunNativeVisualWindow(Attacker : agent, Character : fort_character, Target : fort_character, TargetBody : entity, Actions : guard_actions_component)<suspends>:void =
        Position := Character.GetTransform().Translation
        Actions.Tether(FromVector3(Position), 75.0)
        defer:
            Actions.Untether()
        race:
            CoachHoldAttackWindow(Actions, Character, TargetBody, Clamp(VisualNativeCaptureSeconds, 0.0, 40.0) + 2.0)
            WaitForNativeVisualCapture(Attacker, Target, VisualNativeCaptureSeconds)
        CoachReleaseHold(Actions, "native_visual_parent")

    RunNativeVisualViewport(Attacker : agent, Character : fort_character, Target : fort_character, TargetBody : entity, Actions : guard_actions_component, Viewer : agent)<suspends>:void =
        if (Player := player[Viewer], View := VisualPortal.Views[Player], UI := GetPlayerUI[Player], Menu := View.Menu?):
            UI.RemoveWidget(Menu)
            CoachProbeLog("PCL|health_probe|native_visual_menu_suspended|same_widget_retained|subscriptions_retained")
            defer:
                if (Current := View.Menu?, Current = Menu):
                    UI.AddWidget(Menu, player_ui_slot{InputMode := ui_input_mode.All})
                    CoachProbeLog("PCL|health_probe|native_visual_menu_restored|same_widget=1")
                else:
                    CoachProbeLog("PCL|health_probe|native_visual_menu_restore_skipped|menu_changed_or_disposed")
            RunNativeVisualCamera(Attacker, Character, Target, TargetBody, Actions, Viewer)
        else:
            RunNativeVisualCamera(Attacker, Character, Target, TargetBody, Actions, Viewer)

    RunNativeVisualCamera(Attacker : agent, Character : fort_character, Target : fort_character, TargetBody : entity, Actions : guard_actions_component, Viewer : agent)<suspends>:void =
        Actions.StopNavigation()
        Position := Character.GetTransform().Translation
        Actions.Tether(FromVector3(Position), 75.0)
        defer:
            Actions.Untether()
        race:
            CoachHoldAttackWindow(Actions, Character, TargetBody, Clamp(VisualNativeCaptureSeconds, 0.0, 40.0) + 4.0)
            RunNativeVisualCameraPose(Attacker, Character, Target, Viewer)
        CoachReleaseHold(Actions, "native_visual_parent")

    RunNativeVisualCameraPose(Attacker : agent, Character : fort_character, Target : fort_character, Viewer : agent)<suspends>:void =
        Sleep(0.25)
        SavedPose := VisualCaptureCamera.GetTransform()
        Placed := PlaceNativeVisualCamera(Character, Target, "initial_after_hold")
        if (Placed?):
            defer:
                VisualCaptureCamera.RemoveFrom(Viewer)
                if (VisualCaptureCamera.TeleportTo[SavedPose]):
                    CoachProbeLog("PCL|health_probe|native_visual_camera_restored|removed_from_viewer=1|transform_restored=1")
                else:
                    CoachProbeLog("PCL|health_probe|native_visual_camera_restore_failed|transform_unconfirmed")
            VisualCaptureCamera.AddTo(Viewer)
            CoachProbeLog("PCL|health_probe|native_visual_camera_added|owned_hold_already_running|temporary_player_camera_stack_only|no_player_teleport_or_input")
            Sleep(1.0)
            Reframed := PlaceNativeVisualCamera(Character, Target, "reframed_after_blend")
            if (not Reframed?):
                CoachProbeLog("PCL|health_probe|native_visual_camera_not_run|reframe_rejected")
                return
            Sleep(0.25)
            WaitForNativeVisualCapture(Attacker, Target, VisualNativeCaptureSeconds)
        else:
            CoachProbeLog("PCL|health_probe|native_visual_camera_not_run|camera_placement_rejected")

    PlaceNativeVisualCamera(Character : fort_character, Target : fort_character, Phase : string, ?UseCharacterFacing : logic = false):logic =
        Position := Character.GetTransform().Translation
        var FlatDelta : vector3 = Target.GetTransform().Translation - Position
        var FacingFlag : int = 0
        if (UseCharacterFacing?):
            set FlatDelta = Character.GetTransform().Rotation.GetLocalForward()
            set FacingFlag = 1
        if (Forward := (vector3{X := FlatDelta.X, Y := FlatDelta.Y}).MakeUnitVector[]):
            Side := vector3{X := -Forward.Y, Y := Forward.X}
            CameraPosition := Position + Forward * 224.0 + Side * 112.0 + vector3{Z := 70.0}
            AimDelta := Position + vector3{Z := 20.0} - CameraPosition
            Yaw := ArcTan(AimDelta.Y, AimDelta.X) * 180.0 / PiFloat
            Pitch := ArcTan(AimDelta.Z, Sqrt(AimDelta.X * AimDelta.X + AimDelta.Y * AimDelta.Y)) * 180.0 / PiFloat
            if (VisualCaptureCamera.TeleportTo[CameraPosition, MakeRotationFromYawPitchRollDegrees(Yaw, Pitch, 0.0)]):
                CoachProbeLog("PCL|health_probe|native_visual_camera_placed|phase={Phase}|npc_x={Position.X}|npc_y={Position.Y}|npc_z={Position.Z}|x={CameraPosition.X}|y={CameraPosition.Y}|z={CameraPosition.Z}|yaw={Yaw}|pitch={Pitch}|camera_from_character_facing={FacingFlag}")
                return true
        return false

    WaitForNativeVisualCapture(Attacker : agent, Target : fort_character, Seconds : float)<suspends>:void =
        if (Character := Attacker.GetFortCharacter[]):
            Position := Character.GetTransform().Translation
            TargetPosition := Target.GetTransform().Translation
            Duration := Clamp(Seconds, 0.0, 40.0)
            var Route : string = "offscreen"
            if (VisualUseViewportCamera?):
                set Route = "game_viewport"
            CoachProbeLog("PCL|health_probe|npc_visual_capture_ready|phase=native_original|x={Position.X}|y={Position.Y}|z={Position.Z}|target_x={TargetPosition.X}|target_y={TargetPosition.Y}|target_z={TargetPosition.Z}|duration={Duration}|time={GetSimulationElapsedTime()}|capture_route={Route}|native_original_inventory_only")
            Started := GetSimulationElapsedTime()
            loop:
                Sleep(1.0)
                if (Ending? or not Target.IsActive[]):
                    return
                var EquippedRanged : int = 0
                for (Inventory : Attacker.FindDescendantComponents(inventory_component), Item : Inventory.GetItems(), Component := Item.GetComponent[item_component], Component.IsEquipped[]):
                    for (Category : Component.Categories, Category = FortniteItemCategories.WeaponRanged):
                        set EquippedRanged += 1
                CoachProbeLog("PCL|health_probe|npc_native_visual_status|elapsed={GetSimulationElapsedTime() - Started}|ranged_items={CountRangedItems(Attacker)}|equipped_ranged={EquippedRanged}|target_health={Target.GetHealth()}|source_hits={CombatHitsByShooter}")
                if (GetSimulationElapsedTime() - Started >= Duration):
                    break
            CoachProbeLog("PCL|health_probe|npc_visual_capture_finished|phase=native_original|time={GetSimulationElapsedTime()}")

    LogNativeBuildInventory(Owner : agent, Label : string):void =
        var Index : int = 0
        for (Inventory : Owner.FindDescendantComponents(inventory_component)):
            set Index += 1
            var Kind : string = "inventory"
            if (fort_inventory_component[Inventory]):
                set Kind = "fort_inventory"
            if (fort_inventory_build_hotbar_component[Inventory]):
                set Kind = "build_hotbar"
            if (fort_inventory_weapon_hotbar_component[Inventory]):
                set Kind = "weapon_hotbar"
            if (fort_inventory_harvest_tool_component[Inventory]):
                set Kind = "harvest_tool"
            if (fort_inventory_resources_component[Inventory]):
                set Kind = "resources"
            var Equipped : int = 0
            var ParentMatches : int = 0
            for (Value : Inventory.GetItems(), Item := Value.GetComponent[item_component]):
                if (Item.IsEquipped[]):
                    set Equipped += 1
                if (Item.GetParentInventory[] = Inventory):
                    set ParentMatches += 1
            CoachProbeLog("PCL|health_probe|native_build_inventory|owner={Label}|index={Index}|kind={Kind}|items={Inventory.GetItems().Length}|equipped={Equipped}|parent_matches={ParentMatches}")

    RunNativeBuildToolReference(Owner : agent, Attacker : agent):void =
        var Snapshot : []tuple(item_component, inventory_component, int) = array{}
        for (Subject : array{Owner, Attacker}, Inventory : Subject.FindDescendantComponents(inventory_component), Value : Inventory.GetItems(), Item := Value.GetComponent[item_component]):
            var Equipped : int = 0
            if (Item.IsEquipped[]):
                set Equipped = 1
            set Snapshot += array{(Item, Inventory, Equipped)}
        LogNativeBuildInventory(Owner, "player_before")
        LogNativeBuildInventory(Attacker, "guard_before")
        var Hotbars : int = 0
        var Tools : int = 0
        var Roots : int = 0
        for (Child : Attacker.GetEntities(), Inventory := Child.GetComponent[inventory_component]):
            set Roots += 1
        CoachProbeLog("PCL|health_probe|native_build_topology|guard_direct_inventory_roots={Roots}|query_only_no_items_moved")
        for (Source : Owner.FindDescendantComponents(fort_inventory_build_hotbar_component)):
            set Hotbars += 1
            for (Value : Source.GetItems(), Item := Value.GetComponent[item_component]):
                set Tools += 1
                var Removable : int = 0
                var ParentMatches : int = 0
                if ((Source.CanRemoveItem(Value)).GetSuccess[]):
                    set Removable = 1
                if (Item.GetParentInventory[] = Source):
                    set ParentMatches = 1
                var DestinationIndex : int = 0
                for (Child : Attacker.GetEntities(), Destination := Child.GetComponent[inventory_component]):
                    set DestinationIndex += 1
                    Acceptance := Destination.CanAddItemDistribute(Value, ?AllowMergeItems := false)
                    var Accepted : int = 0
                    var ErrorCount : int = 0
                    if (Acceptance.GetSuccess[]):
                        set Accepted = 1
                    if (Errors := Acceptance.GetError[]):
                        set ErrorCount = Errors.Length
                    CoachProbeLog("PCL|health_probe|native_build_item_preflight|tool={Tools}|destination={DestinationIndex}|can_remove={Removable}|parent_matches={ParentMatches}|can_add_distribute={Accepted}|add_errors={ErrorCount}|no_transfer_or_equip")
        LogNativeBuildInventory(Owner, "player_after")
        LogNativeBuildInventory(Attacker, "guard_after")
        var Unchanged : int = 0
        for (Entry : Snapshot):
            var EquippedNow : int = 0
            if (Entry(0).IsEquipped[]):
                set EquippedNow = 1
            if (Entry(0).GetParentInventory[] = Entry(1), EquippedNow = Entry(2)):
                set Unchanged += 1
        CoachProbeLog("PCL|health_probe|native_build_reference_finished|source_hotbars={Hotbars}|source_tools={Tools}|snapshot_items={Snapshot.Length}|unchanged_identity_parent_equipped={Unchanged}|inventory_queries_only|no_placement_edit_or_reset_requested")

    RestoreNativeToolLease():logic =
        if (Lease := NativeToolLease?):
            Restored := Lease.Restore()
            if (not Restored?):
                CoachProbeLog("PCL|health_probe|native_tool_lease_cleanup_pending|npc_retained_before_despawn")
                return false
            set NativeToolLease = false
        return true

    RunNativeBuildToolLease(Owner : agent, Attacker : agent)<suspends>:void =
        var Snapshot : []tuple(item_component, inventory_component, int) = array{}
        var GuardEquipped : []item_component = array{}
        var GuardRanged : []item_component = array{}
        for (Subject : array{Owner, Attacker}, Inventory : Subject.FindDescendantComponents(inventory_component), Value : Inventory.GetItems(), Item := Value.GetComponent[item_component]):
            if (Subject = Attacker):
                for (Category : Item.Categories, Category = FortniteItemCategories.WeaponRanged):
                    set GuardRanged += array{Item}
            var Equipped : int = 0
            if (Item.IsEquipped[]):
                set Equipped = 1
                if (Subject = Attacker):
                    set GuardEquipped += array{Item}
            set Snapshot += array{(Item, Inventory, Equipped)}
        var SourceChoice : ?inventory_component = false
        var ToolChoice : ?item_component = false
        for (Source : Owner.FindDescendantComponents(fort_inventory_build_hotbar_component), Value : Source.GetItems(), Item := Value.GetComponent[item_component], not Item.IsEquipped[], not ToolChoice?):
            set SourceChoice = option{Source}
            set ToolChoice = option{Item}
        var RootChoice : ?inventory_component = false
        var Roots : int = 0
        var ExistingHotbars : int = 0
        for (Existing : Attacker.FindDescendantComponents(fort_inventory_build_hotbar_component)):
            set ExistingHotbars += 1
        for (Child : Attacker.GetEntities(), Inventory := Child.GetComponent[inventory_component]):
            set Roots += 1
            set RootChoice = option{Inventory}
        if (Roots <> 1 or ExistingHotbars <> 0 or NativeToolLease?):
            CoachProbeLog("PCL|health_probe|native_tool_lease_not_run|roots={Roots}|existing_hotbars={ExistingHotbars}|topology_guard")
            return
        if (Source := SourceChoice?, Tool := ToolChoice?, Root := RootChoice?):
            Container := entity{}
            Destination := fort_inventory_build_hotbar_component{Entity := Container}
            Container.AddComponents(array{Destination})
            Lease := coach_native_build_tool_lease{Source := Source, Tool := Tool, Container := Container, Destination := Destination, GuardEquipped := GuardEquipped, SourceCount := Source.GetItems().Length}
            set NativeToolLease = option{Lease}
            Trace := coach_native_tool_phase_trace{Tool := Tool, Destination := Destination, Source := Source, GuardEquipped := GuardEquipped, GuardSubject := Attacker, OriginalRanged := GuardRanged}
            TraceBinding := Tool.ChangeEquippedEvent.Subscribe(Trace.OnEquipped)
            defer:
                Trace.Mark("cleanup_begin")
                TraceBinding.Cancel()
                CoachProbeLog("PCL|health_probe|native_tool_phase_trace_stopped|subscriptions=1")
                Restored := RestoreNativeToolLease()
                var CleanupOK : int = 0
                var RepeatOK : int = 0
                if (Restored?):
                    set CleanupOK = 1
                    Repeated := Lease.Restore()
                    if (Repeated?):
                        set RepeatOK = 1
                var Unchanged : int = 0
                for (Entry : Snapshot):
                    var EquippedNow : int = 0
                    if (Entry(0).IsEquipped[]):
                        set EquippedNow = 1
                    if (Entry(0).GetParentInventory[] = Entry(1), EquippedNow = Entry(2)):
                        set Unchanged += 1
                var HotbarsAfter : int = 0
                for (Remaining : Attacker.FindDescendantComponents(fort_inventory_build_hotbar_component)):
                    set HotbarsAfter += 1
                var ToolGuardsAfter : int = 0
                if (Tool.Entity.GetComponent[coach_tool_hold_component]):
                    set ToolGuardsAfter = 1
                var RangedGuardsAfter : int = 0
                for (Original : GuardRanged, Original.Entity.GetComponent[coach_tool_hold_component]):
                    set RangedGuardsAfter += 1
                CoachProbeLog("PCL|health_probe|native_tool_lease_snapshot|items={Snapshot.Length}|unchanged_identity_parent_equipped={Unchanged}|source_count={Source.GetItems().Length}|cleanup_ok={CleanupOK}|repeat_cleanup_ok={RepeatOK}|guard_hotbars_after={HotbarsAfter}|tool_hold_guards_after={ToolGuardsAfter}|ranged_hold_guards_after={RangedGuardsAfter}|cleanup_checked_before_outer_despawn")
            Root.Entity.AddEntities(array{Container})
            Sleep(0.25)
            CoachProbeLog("PCL|health_probe|native_tool_lease_hotbar|items={Destination.GetItems().Length}|under_guard_inventory_root")
            if (Ending? or Destination.GetItems().Length <> 0):
                return
            if (Tool.IsEquipped[] or not Tool.GetParentInventory[] = Source):
                CoachProbeLog("PCL|health_probe|native_tool_lease_not_run|source_changed_during_setup|no_transfer")
                return
            CanRemove := Source.CanRemoveItem(Tool.Entity)
            CanAdd := Destination.CanAddItem(Tool.Entity, ?AllowMergeItems := false)
            if (not CanRemove.GetSuccess[] or not CanAdd.GetSuccess[]):
                CoachProbeLog("PCL|health_probe|native_tool_lease_not_run|direct_preflight_rejected|no_transfer")
                return
            set Lease.TransferAttempted = true
            Added := Destination.AddItem(Tool.Entity, ?AllowMergeItems := false)
            if (not Added.GetSuccess[]):
                CoachProbeLog("PCL|health_probe|native_tool_lease_add_rejected")
                return
            if (not Tool.GetParentInventory[] = Destination):
                CoachProbeLog("PCL|health_probe|native_tool_lease_parent_unconfirmed")
                return
            CoachProbeLog("PCL|health_probe|native_tool_lease_transferred|same_item_parent_matches=1|source_count={Source.GetItems().Length}|destination_count={Destination.GetItems().Length}")
            var HeldActions : ?guard_actions_component = false
            if (VisualNativeCaptureSeconds > 0.0 and VisualUseViewportCamera?, Character := Attacker.GetFortCharacter[], Body := Character.GetEntity[], Actions := Body.GetComponent[guard_actions_component]):
                Trace.Mark("before_stop_navigation")
                Actions.StopNavigation()
                Trace.Mark("after_stop_navigation")
                Trace.Mark("before_tether")
                Actions.Tether(FromVector3(Character.GetTransform().Translation), 75.0)
                Trace.Mark("after_tether")
                set HeldActions = option{Actions}
            defer:
                if (Held := HeldActions?):
                    Held.Untether()
                    Held.StopNavigation()
            if (HeldActions?):
                Trace.Mark("navigation_settle_before_tool_equip")
                Sleep(1.25)
                Trace.Mark("navigation_settled_before_tool_equip")
            if (Ending?):
                return
            for (Previous : GuardEquipped, Previous.IsEquipped[]):
                Released := Previous.Unequip()
                if (not Released.GetSuccess[]):
                    CoachProbeLog("PCL|health_probe|native_tool_lease_not_run|guard_release_rejected")
                    return
            Parked := Lease.ParkNativeRanged(Attacker, GuardRanged)
            if (not Parked? or CountRangedItems(Attacker) <> 0):
                CoachProbeLog("PCL|health_probe|native_tool_lease_not_run|original_ranged_parking_incomplete")
                return
            Trace.Mark("original_ranged_parked_before_tool_equip")
            Locked := Lease.LockNativeTool(Attacker, GuardRanged)
            if (not Locked?):
                CoachProbeLog("PCL|health_probe|native_tool_lease_not_run|query_guard_install_refused")
                return
            Equipped := Tool.Equip()
            if (not Equipped.GetSuccess[]):
                CoachProbeLog("PCL|health_probe|native_tool_lease_equip_rejected")
                return
            CoachProbeLog("PCL|health_probe|native_tool_lease_equip_ok|native_build_tool|render_unverified")
            CoachNativeBuildAbilityAudit(Tool, "initial_equip")
            Trace.Mark("short_window_start")
            for (Tick := 1..8):
                Sleep(0.25)
                if (Ending?):
                    return
                Lease.ObserveParkingState("short_hold")
                Trace.Record("short_sample")
                var EquippedFlag : int = 0
                var ParentFlag : int = 0
                if (Tool.IsEquipped[]):
                    set EquippedFlag = 1
                if (Tool.GetParentInventory[] = Destination):
                    set ParentFlag = 1
                CoachProbeLog("PCL|health_probe|native_tool_lease_sample|tick={Tick}|equipped={EquippedFlag}|parent_matches={ParentFlag}|source_count={Source.GetItems().Length}|destination_count={Destination.GetItems().Length}|no_placement_edit_or_reset")
            Trace.Mark("short_window_end")
            if (VisualNativeCaptureSeconds > 0.0 and VisualUseViewportCamera?, Viewer := player[Owner], Character := Attacker.GetFortCharacter[], Target := Owner.GetFortCharacter[], HeldActions?):
                RunNativeBuildAttackTrial(Viewer, Attacker, Tool, Destination, Trace)
            else if (VisualNativeCaptureSeconds > 0.0):
                if (NativeBuildMenuOnly?):
                    if (Viewer := player[Owner], View := VisualPortal.Views[Viewer], UI := GetPlayerUI[Viewer], Menu := View.Menu?):
                        Trace.Mark("menu_only_before_remove")
                        UI.RemoveWidget(Menu)
                        Trace.Mark("menu_only_after_remove")
                        CoachProbeLog("PCL|health_probe|native_tool_menu_only_suspended|same_widget_retained|no_other_setup")
                        defer:
                            if (Current := View.Menu?, Current = Menu):
                                Trace.Mark("menu_only_before_restore")
                                UI.AddWidget(Menu, player_ui_slot{InputMode := ui_input_mode.All})
                                Trace.Mark("menu_only_after_restore")
                                CoachProbeLog("PCL|health_probe|native_tool_menu_only_restored|same_widget=1")
                        RunNativeToolIdleWindow(Tool, Destination, Trace)
                    else:
                        CoachProbeLog("PCL|health_probe|native_tool_menu_only_not_run|viewer_menu_missing")
                else:
                    RunNativeToolIdleWindow(Tool, Destination, Trace)
        else:
            CoachProbeLog("PCL|health_probe|native_tool_lease_not_run|source_tool_or_root_missing")

    RunNativeBuildAttackTrial(Viewer : player, Attacker : agent, Tool : item_component, Destination : inventory_component, Trace : coach_native_tool_phase_trace)<suspends>:void =
        CalibrationShooter.Spawn()
        for (Attempt := 0..99):
            if (Ending?):
                return
            if (Target := CombatTarget?, Target <> Attacker, TargetCharacter := Target.GetFortCharacter[], TargetCharacter.IsActive[], TargetBody := TargetCharacter.GetEntity[], Character := Attacker.GetFortCharacter[], Body := Character.GetEntity[], Actions := Body.GetComponent[guard_actions_component], Awareness := Body.GetComponent[npc_awareness_component], Root := GetSimulationEntity[]):
                Teams := GetPlayspace().GetTeamCollection()
                if (PreviousTeam := Teams.GetTeam[Target], EnemyTeam := Teams.GetTeams()[1], Teams.AddToTeam[Target, EnemyTeam], Teams.GetTeamAttitude[Attacker, Target] = team_attitude.Hostile):
                    defer:
                        set NativeBuildAttackObservation = false
                        TargetCharacter.ReleaseFromStasis()
                        TargetCharacter.SetVulnerability(false)
                        if (Teams.AddToTeam[Target, PreviousTeam]):
                            CoachProbeLog("PCL|health_probe|native_build_attack_target_restored|team=1|stasis_released=1|vulnerability_false=1")
                        else:
                            CoachProbeLog("PCL|health_probe|native_build_attack_target_restore_failed")
                    var TargetPlaced : logic = false
                    if (TargetCharacter.TeleportTo[vector3{X := -2848.0, Y := -2400.0, Z := 96.0}, IdentityRotation()]):
                        set TargetPlaced = true
                    if (not TargetPlaced?):
                        CoachProbeLog("PCL|health_probe|native_build_attack_not_run|target_placement_rejected")
                        return
                    TargetCharacter.SetMaxHealth(5000.0)
                    TargetCharacter.SetHealth(5000.0)
                    TargetCharacter.SetShield(0.0)
                    TargetCharacter.PutInStasis(stasis_args{AllowTurning := false, AllowFalling := false})
                    TargetCharacter.SetVulnerability(true)
                    set CombatDamageEvents = 0
                    set CombatHitsByShooter = 0
                    Binding := TargetCharacter.DamagedEvent().Subscribe(OnCombatTargetDamaged)
                    defer:
                        Binding.Cancel()
                        CoachProbeLog("PCL|health_probe|native_build_attack_damage_subscription_stopped|count=1")
                    var Detected : logic = false
                    Trace.Mark("build_attack_before_detection_focus")
                    race:
                        block:
                            for (Wait := 0..79, not Detected?):
                                for (Info : Awareness.DetectedTargets, Info.Target = TargetBody or Info.Target = Target, Info.Attitude = team_attitude.Hostile, Info.HasLineOfSight?):
                                    set Detected = true
                                Sleep(0.1)
                        block:
                            Actions.Focus(TargetBody, ?LockFocus := true)
                            loop:
                                Sleep(0.1)
                    Trace.Mark("build_attack_after_detection_focus")
                    Resources := CoachNativeResourceCounts(Attacker)
                    CoachProbeLog("PCL|health_probe|native_build_attack_resources|items={Resources(0)}|known_stacks={Resources(1)}|total={Resources(2)}|read_only|selected_build_tool_kind_unverified")
                    LiveLOS := HasHostileTargetLOS(Attacker, TargetCharacter)
                    var DetectedFlag : int = 0
                    var LOSFlag : int = 0
                    var ToolFlag : int = 0
                    var ParentFlag : int = 0
                    if (Detected?):
                        set DetectedFlag = 1
                    if (LiveLOS?):
                        set LOSFlag = 1
                    if (Tool.IsEquipped[]):
                        set ToolFlag = 1
                    if (Tool.GetParentInventory[] = Destination):
                        set ParentFlag = 1
                    CoachProbeLog("PCL|health_probe|native_build_attack_preconditions|detected={DetectedFlag}|current_hostile_los={LOSFlag}|tool_equipped={ToolFlag}|parent_matches={ParentFlag}|before_single_refresh")
                    if (not Detected? or not LiveLOS? or ParentFlag <> 1 or Resources(0) = 0 or Resources(1) <> Resources(0) or Resources(2) < 10):
                        CoachProbeLog("PCL|health_probe|native_build_attack_not_run|detection_parent_or_resource_precondition_unconfirmed")
                        return
                    if (not Tool.IsEquipped[]):
                        CoachProbeLog("PCL|health_probe|native_build_attack_single_tool_refresh|after_detection|no_repeated_equip")
                        Refreshed := Tool.Equip()
                        if (not Refreshed.GetSuccess[] or not Tool.IsEquipped[]):
                            CoachProbeLog("PCL|health_probe|native_build_attack_not_run|single_tool_refresh_failed")
                            return
                    Trace.Mark("build_attack_final_precondition")
                    if (not Tool.IsEquipped[] or not Tool.GetParentInventory[] = Destination):
                        CoachProbeLog("PCL|health_probe|native_build_attack_not_run|final_tool_precondition_unconfirmed")
                        return
                    CoachNativeBuildAbilityAudit(Tool, "attack_precondition")
                    Center := Character.GetTransform().Translation
                    Before := CoachNativeStructureBodies(Root, Center, Body, TargetBody)
                    Observation := coach_native_build_attack_observation{Root := Root, Center := Center, AttackerBody := Body, TargetBody := TargetBody, Baseline := Before, Target := TargetCharacter, Attacker := Attacker, Tool := Tool, Destination := Destination, Camera := VisualCaptureCamera}
                    set NativeBuildAttackObservation = option{Observation}
                    CoachProbeLog("PCL|health_probe|native_build_attack_ready|hostile_detected_los=1|tool_equipped=1|target_health={TargetCharacter.GetHealth()}|baseline_bodies={Before.Length}|fixed_half_width=1024|fixed_height=1536|native_building_not_assumed")
                    race:
                        block:
                            var Returned : int = 0
                            defer:
                                CoachProbeLog("PCL|health_probe|native_build_attack_task_unwound|result_observed={Returned}")
                            Started := GetSimulationElapsedTime()
                            CoachProbeLog("PCL|health_probe|native_build_attack_request|target_detected=1|single_public_Attack|no_BeginFire_or_direct_Damage")
                            Result := Actions.Attack(TargetBody)
                            set Returned = 1
                            var Success : int = 0
                            var ErrorCode : int = 0
                            if (Result.GetSuccess[]):
                                set Success = 1
                            else if (Error := Result.GetError[]):
                                if (Error = ai_action_error_type.Failure):
                                    set ErrorCode = 1
                                else if (Error = ai_action_error_type.Canceled):
                                    set ErrorCode = 2
                                else if (Error = ai_action_error_type.Disallowed):
                                    set ErrorCode = 3
                                else:
                                    set ErrorCode = -1
                            CoachProbeLog("PCL|health_probe|native_build_attack_returned|success={Success}|error_code={ErrorCode}|elapsed={GetSimulationElapsedTime() - Started}|not_placement_proof")
                            loop:
                                Sleep(0.1)
                        block:
                            RunNativeToolVisualViewport(Tool, Destination, Character, TargetCharacter, Viewer, Trace)
                            Observation.AfterCameraRestore()
                else:
                    CoachProbeLog("PCL|health_probe|native_build_attack_not_run|hostile_team_unconfirmed")
                return
            Sleep(0.1)
        CoachProbeLog("PCL|health_probe|native_build_attack_not_run|target_unavailable")

    RunNativeToolIdleWindow(Tool : item_component, Destination : inventory_component, Trace : coach_native_tool_phase_trace)<suspends>:void =
        Trace.Mark("neutral_idle_wait")
        Started := GetSimulationElapsedTime()
        Duration := Clamp(VisualNativeCaptureSeconds, 0.0, 40.0)
        var MenuMode : int = 0
        if (NativeBuildMenuOnly?):
            set MenuMode = 1
        CoachProbeLog("PCL|health_probe|native_tool_idle_started|duration={Duration}|menu_only_control={MenuMode}|no_navigation_tether_camera_focus_or_attack_changes")
        loop:
            Sleep(1.0)
            if (Ending?):
                return
            if (Lease := NativeToolLease?):
                Lease.ObserveParkingState("idle_hold")
            Trace.Record("idle_sample")
            var IdleEquipped : int = 0
            var IdleParent : int = 0
            if (Tool.IsEquipped[]):
                set IdleEquipped = 1
            if (Tool.GetParentInventory[] = Destination):
                set IdleParent = 1
            CoachProbeLog("PCL|health_probe|native_tool_idle_status|elapsed={GetSimulationElapsedTime() - Started}|equipped={IdleEquipped}|parent_matches={IdleParent}|source_count={Trace.Source.GetItems().Length}|destination_count={Destination.GetItems().Length}")
            if (GetSimulationElapsedTime() - Started >= Duration):
                break
        Trace.Mark("neutral_idle_finished")

    RunNativeToolVisualViewport(Tool : item_component, Destination : inventory_component, Character : fort_character, Target : fort_character, Viewer : player, Trace : coach_native_tool_phase_trace)<suspends>:void =
        if (View := VisualPortal.Views[Viewer], UI := GetPlayerUI[Viewer], Menu := View.Menu?):
            Trace.Mark("before_menu_remove")
            UI.RemoveWidget(Menu)
            Trace.Mark("after_menu_remove")
            CoachProbeLog("PCL|health_probe|native_tool_visual_menu_suspended|same_widget_retained")
            defer:
                if (Current := View.Menu?, Current = Menu):
                    Trace.Mark("before_menu_restore")
                    UI.AddWidget(Menu, player_ui_slot{InputMode := ui_input_mode.All})
                    Trace.Mark("after_menu_restore")
                    CoachProbeLog("PCL|health_probe|native_tool_visual_menu_restored|same_widget=1")
            RunNativeToolVisualCamera(Tool, Destination, Character, Target, Viewer, Trace)
        else:
            RunNativeToolVisualCamera(Tool, Destination, Character, Target, Viewer, Trace)

    RunNativeToolVisualCamera(Tool : item_component, Destination : inventory_component, Character : fort_character, Target : fort_character, Viewer : player, Trace : coach_native_tool_phase_trace)<suspends>:void =
        Trace.Mark("before_settle_wait")
        Sleep(0.25)
        Trace.Mark("after_settle_wait")
        SavedPose := VisualCaptureCamera.GetTransform()
        Trace.Mark("before_initial_camera_placement")
        Placed := PlaceNativeVisualCamera(Character, Target, "native_build_tool_initial", ?UseCharacterFacing := true)
        Trace.Mark("after_initial_camera_placement")
        if (not Placed?):
            CoachProbeLog("PCL|health_probe|native_tool_visual_not_run|initial_camera_rejected")
            return
        defer:
            if (not NativeBuildCameraBypass?):
                VisualCaptureCamera.RemoveFrom(Viewer)
            if (VisualCaptureCamera.TeleportTo[SavedPose]):
                var BypassCode : int = 0
                if (NativeBuildCameraBypass?):
                    set BypassCode = 1
                CoachProbeLog("PCL|health_probe|native_visual_camera_restored|phase=native_build_tool|transform_restored=1|camera_activation_bypass={BypassCode}")
            else:
                CoachProbeLog("PCL|health_probe|native_visual_camera_restore_failed|phase=native_build_tool")
        Trace.Mark("before_camera_add")
        if (not NativeBuildCameraBypass?):
            VisualCaptureCamera.AddTo(Viewer)
        else:
            CoachProbeLog("PCL|health_probe|native_tool_camera_stack_bypassed|no_AddTo_or_RemoveFrom|other_setup_unchanged")
        Trace.Mark("after_camera_add")
        Trace.Mark("before_camera_blend_wait")
        Sleep(1.0)
        Trace.Mark("after_camera_blend_wait")
        Reframed := PlaceNativeVisualCamera(Character, Target, "native_build_tool_reframed", ?UseCharacterFacing := true)
        Trace.Mark("after_camera_reframe")
        if (not Reframed?):
            CoachProbeLog("PCL|health_probe|native_tool_visual_not_run|camera_reframe_rejected")
            return
        Sleep(0.25)
        Trace.Mark("before_visual_ready")
        Position := Character.GetTransform().Translation
        TargetPosition := Target.GetTransform().Translation
        Duration := Clamp(VisualNativeCaptureSeconds, 0.0, 40.0)
        var CapturePhase : string = "native_build_tool"
        if (NativeBuildAttackObservation?):
            set CapturePhase = "native_build_attack"
        if (NativeBuildCameraBypass?):
            CoachProbeLog("PCL|health_probe|native_tool_setup_control_ready|duration={Duration}|camera_stack_inactive|no_image_requested")
        else:
            CoachProbeLog("PCL|health_probe|npc_visual_capture_ready|phase={CapturePhase}|x={Position.X}|y={Position.Y}|z={Position.Z}|target_x={TargetPosition.X}|target_y={TargetPosition.Y}|target_z={TargetPosition.Z}|duration={Duration}|time={GetSimulationElapsedTime()}|capture_route=game_viewport|native_item_inventory_lease|camera_from_body_facing")
        defer:
            if (NativeBuildCameraBypass?):
                CoachProbeLog("PCL|health_probe|native_tool_setup_control_finished|camera_stack_inactive")
            else:
                CoachProbeLog("PCL|health_probe|npc_visual_capture_finished|phase={CapturePhase}|time={GetSimulationElapsedTime()}")
        Started := GetSimulationElapsedTime()
        var SampleIndex : int = 0
        loop:
            Sleep(1.0)
            if (Ending? or not Character.IsActive[]):
                return
            if (Lease := NativeToolLease?):
                Lease.ObserveParkingState("visual_hold")
            Trace.Record("visual_sample")
            set SampleIndex += 1
            if (Observation := NativeBuildAttackObservation?):
                Observation.Sample(SampleIndex, CombatDamageEvents, CombatHitsByShooter)
            var Equipped : int = 0
            var ParentMatches : int = 0
            if (Tool.IsEquipped[]):
                set Equipped = 1
            if (Tool.GetParentInventory[] = Destination):
                set ParentMatches = 1
            CoachProbeLog("PCL|health_probe|native_tool_visual_status|elapsed={GetSimulationElapsedTime() - Started}|equipped={Equipped}|parent_matches={ParentMatches}|destination_count={Destination.GetItems().Length}|no_placement_edit_or_reset")
            if (GetSimulationElapsedTime() - Started >= Duration):
                break

    CountRangedItems(Owner : agent)<transacts>:int =
        var Count : int = 0
        for (Inventory : Owner.FindDescendantComponents(inventory_component), Item : Inventory.GetItems(), Component := Item.GetComponent[item_component]):
            for (Category : Component.Categories, Category = FortniteItemCategories.WeaponRanged):
                set Count += 1
        return Count

    HasHostileTargetLOS(Attacker : agent, Target : fort_character)<transacts>:logic =
        if (Body := Attacker.GetFortCharacter[].GetEntity[], Awareness := Body.GetComponent[npc_awareness_component], TargetBody := Target.GetEntity[], TargetAgent := Target.GetAgent[]):
            for (Info : Awareness.DetectedTargets, Info.Target = TargetBody or Info.Target = TargetAgent, Info.HasLineOfSight?, Info.Attitude = team_attitude.Hostile):
                return true
        return false

    DriveVisibleNativeFire(Attacker : agent, Target : fort_character, Weapon : fort_trace_weapon_component)<suspends>:void =
        var Requested : logic = false
        Weapon.EndFire()
        defer:
            Weapon.EndFire()
        loop:
            if (Ending? or not Target.IsActive[]):
                return
            Visible := HasHostileTargetLOS(Attacker, Target)
            if (Visible? and not CalibrationNoFireZone.IsInVolume[Attacker]):
                if (not Requested?):
                    Weapon.BeginFire()
                    set Requested = true
            else:
                Weapon.EndFire()
                set Requested = false
            Sleep(0.1)

    SampleEquippedNPC(Attacker : agent, Target : fort_character, Weapon : fort_trace_weapon_component, Phase : string, Ticks : int)<suspends>:void =
        for (Tick := 1..Ticks):
            Sleep(0.25)
            if (Ending? or not Target.IsActive[]):
                return
            var Firing : int = 0
            var Holstered : int = 0
            var Equipped : int = 0
            var Visible : int = 0
            var NoFireZone : int = 0
            var ShooterPosition : vector3 = vector3{}
            var AimDot : float = -2.0
            TargetPosition := Target.GetTransform().Translation
            if (ShooterCharacter := Attacker.GetFortCharacter[]):
                set ShooterPosition = ShooterCharacter.GetTransform().Translation
                TowardTarget := Target.GetViewLocation() - ShooterCharacter.GetViewLocation()
                if (Direction := TowardTarget.MakeUnitVector[]):
                    set AimDot = DotProduct(ShooterCharacter.GetViewRotation().GetLocalForward(), Direction)
            if (Weapon.IsFiring[]):
                set Firing = 1
            if (Weapon.IsHolstered?):
                set Holstered = 1
            if (Item := Weapon.Entity.GetComponent[item_component], Item.IsEquipped[]):
                set Equipped = 1
            if (CalibrationNoFireZone.IsInVolume[Attacker]):
                set NoFireZone = 1
            if (HasHostileTargetLOS(Attacker, Target)?):
                set Visible = 1
            CoachProbeLog("PCL|health_probe|npc_equipped_sample|phase={Phase}|tick={Tick}|equipped={Equipped}|holstered={Holstered}|is_firing={Firing}|hostile_los={Visible}|no_fire_zone={NoFireZone}|ranged_items={CountRangedItems(Attacker)}|target_health={Target.GetHealth()}|damage_events={CombatDamageEvents}|source_hits={CombatHitsByShooter}|shooter_x={ShooterPosition.X}|shooter_y={ShooterPosition.Y}|shooter_z={ShooterPosition.Z}|target_x={TargetPosition.X}|target_y={TargetPosition.Y}|target_z={TargetPosition.Z}|view_aim_dot={AimDot}|view_not_ballistic_ray")

    EquipPlanFromNPCBehavior(Attacker : agent)<suspends>:logic =
        if (Behavior := coach_damage_shooter_behavior[Attacker.GetNPCBehavior[]]):
            if (Previous := Behavior.PendingToolRequest?, not Previous.Done?):
                CoachProbeLog("PCL|health_probe|npc_tool_owner_request_rejected|already_pending")
                return false
            Request := coach_tool_probe_request{Owner := Attacker}
            defer:
                if (not Request.Done?):
                    set Request.Canceled = true
            set Behavior.PendingToolRequest = option{Request}
            for (Attempt := 0..39):
                if (Request.Done?):
                    return Request.Success
                Sleep(0.05)
            CoachProbeLog("PCL|health_probe|npc_tool_owner_request_timeout")
        else:
            CoachProbeLog("PCL|health_probe|npc_tool_owner_request_rejected|behavior_unavailable")
        return false

    SampleBuildPlanWindow(Equipment : coach_equipment, Attacker : agent, Target : fort_character, Weapon : fort_trace_weapon_component, Cycle : int)<suspends>:void =
        Trace := coach_tool_transition_trace{Equipment := Equipment, Weapon := Weapon, Cycle := Cycle}
        if (Plan := Equipment.BuildPlan?, PlanItem := Plan.GetComponent[item_component], PlanWeapon := Plan.GetComponent[fort_weapon_component], RifleItem := Weapon.Entity.GetComponent[item_component]):
            PlanEquipBinding := PlanItem.ChangeEquippedEvent.Subscribe(Trace.OnPlanEquipped)
            PlanHolsterBinding := PlanWeapon.HolsterChangedEvent.Subscribe(Trace.OnPlanHolster)
            RifleEquipBinding := RifleItem.ChangeEquippedEvent.Subscribe(Trace.OnRifleEquipped)
            RifleHolsterBinding := Weapon.HolsterChangedEvent.Subscribe(Trace.OnRifleHolster)
            defer:
                PlanEquipBinding.Cancel()
                PlanHolsterBinding.Cancel()
                RifleEquipBinding.Cancel()
                RifleHolsterBinding.Cancel()
            Trace.Record("before_request")
            SampleTracedBuildPlanWindow(Equipment, Attacker, Target, Weapon, Cycle, Trace)
        else:
            CoachProbeLog("PCL|health_probe|npc_tool_trace_not_run|missing_item_or_weapon_component")

    SampleTracedBuildPlanWindow(Equipment : coach_equipment, Attacker : agent, Target : fort_character, Weapon : fort_trace_weapon_component, Cycle : int, Trace : coach_tool_transition_trace)<suspends>:void =
        var Reused : int = 0
        if (Equipment.BuildPlan?):
            set Reused = 1
        Held := EquipPlanFromNPCBehavior(Attacker)
        Trace.Record("after_request")
        var EquipRequestOK : int = 0
        if (Held?):
            set EquipRequestOK = 1
        Age := GetSimulationElapsedTime() - Equipment.LastPlanAttempt
        CoachProbeLog("PCL|health_probe|npc_build_plan_request|cycle={Cycle}|equip_ok={EquipRequestOK}|existing_plan={Reused}|age_since_create_attempt={Age}|production_equipment_module")
        if (Cycle = 1, Plan := Equipment.BuildPlan?, Item := Plan.GetComponent[item_component]):
            var WasEquipped : int = 0
            if (Item.IsEquipped[]):
                set WasEquipped = 1
            Control := Item.Unequip()
            var Rejected : int = 0
            if (not Control.GetSuccess[]):
                set Rejected = 1
            var Vetoes : int = 0
            if (Lock := Equipment.BuildPlanLock?):
                set Vetoes = Lock.VetoCount
            CoachProbeLog("PCL|health_probe|npc_build_plan_lock_control|was_equipped={WasEquipped}|explicit_unequip_rejected={Rejected}|veto_count={Vetoes}")
            if (RifleItem := Weapon.Entity.GetComponent[item_component]):
                RifleControl := RifleItem.Equip()
                var RifleRejected : int = 0
                if (not RifleControl.GetSuccess[]):
                    set RifleRejected = 1
                var RifleVetoes : int = 0
                if (Gate := Equipment.ManagedRifleGate?):
                    set RifleVetoes = Gate.VetoCount
                CoachProbeLog("PCL|health_probe|npc_rifle_equip_lock_control|explicit_rifle_equip_rejected={RifleRejected}|rifle_veto_count={RifleVetoes}|while_tool_intended")
        if (Cycle = 1):
            WaitForVisualCapture(Equipment, Attacker, Target, Weapon, "tool", VisualToolCaptureSeconds)
        for (Tick := 1..20):
            Sleep(0.05)
            if (Ending? or not Target.IsActive[]):
                return
            Trace.Record("poll")
            var PlanEquipped : int = 0
            var RifleEquipped : int = 0
            var RifleFiring : int = 0
            var Locked : int = 0
            var Vetoes : int = 0
            var RifleGateActive : int = 0
            var RifleVetoes : int = 0
            var RifleQueries : int = 0
            if (Gate := Equipment.ManagedRifleGate?):
                if (Gate.Locked?):
                    set RifleGateActive = 1
                set RifleVetoes = Gate.VetoCount
                set RifleQueries = Gate.EquipQueries
            if (Lock := Equipment.BuildPlanLock?):
                if (Lock.Locked?):
                    set Locked = 1
                set Vetoes = Lock.VetoCount
            if (Plan := Equipment.BuildPlan?, Item := Plan.GetComponent[item_component], Item.IsEquipped[]):
                set PlanEquipped = 1
            if (Item := Weapon.Entity.GetComponent[item_component], Item.IsEquipped[]):
                set RifleEquipped = 1
            if (Weapon.IsFiring[]):
                set RifleFiring = 1
            CoachProbeLog("PCL|health_probe|npc_build_plan_sample|cycle={Cycle}|tick={Tick}|plan_equipped={PlanEquipped}|rifle_equipped={RifleEquipped}|rifle_firing={RifleFiring}|ranged_items={CountRangedItems(Attacker)}|target_health={Target.GetHealth()}|source_hits={CombatHitsByShooter}|lock_active={Locked}|veto_count={Vetoes}|rifle_gate_active={RifleGateActive}|rifle_veto_count={RifleVetoes}|rifle_equip_queries={RifleQueries}|pose_not_visually_verified")
            if (Cycle = 2, Tick = 5, Intent := Equipment.BuildPlanIntent?, Lock := Equipment.BuildPlanLock?, Gate := Equipment.ManagedRifleGate?, RifleItem := Weapon.Entity.GetComponent[item_component]):
                var IntentActive : int = 0
                if (Intent.Active?):
                    set IntentActive = 1
                CoachProbeLog("PCL|health_probe|npc_tool_forced_switch_before|active={IntentActive}|ticks={Intent.Ticks}|subscriptions={Intent.Subscriptions.Length}|private_positive_control")
                # Preserve intent while allowing exactly this explicit native swap.
                set Lock.Locked = false
                set Gate.Locked = false
                var ReleasedOK : int = 0
                if (Plan := Equipment.BuildPlan?, PlanItem := Plan.GetComponent[item_component]):
                    Released := PlanItem.Unequip()
                    if (Released.GetSuccess[]):
                        set ReleasedOK = 1
                Forced := RifleItem.Equip()
                set Lock.Locked = true
                set Gate.Locked = true
                var ForcedOK : int = 0
                if (Forced.GetSuccess[]):
                    set ForcedOK = 1
                var ErrorCount : int = -1
                if (Errors := Forced.GetError[]):
                    set ErrorCount = Errors.Length
                CoachProbeLog("PCL|health_probe|npc_tool_forced_switch|unequip_ok={ReleasedOK}|equip_ok={ForcedOK}|errors={ErrorCount}|attempts={Intent.Attempts}|intent_not_reset")
                Trace.Record("after_forced_switch")

    WaitForVisualCapture(Equipment : coach_equipment, Attacker : agent, Target : fort_character, Weapon : fort_trace_weapon_component, Phase : string, Seconds : float)<suspends>:void =
        if (Seconds <= 0.0):
            return
        if (VisualUseViewportCamera?):
            if (Viewer := GetPlayspace().GetPlayers()[0], Character := Attacker.GetFortCharacter[]):
                RunManagedVisualViewport(Equipment, Attacker, Character, Target, Weapon, Phase, Seconds, Viewer)
            else:
                CoachProbeLog("PCL|health_probe|managed_visual_camera_not_run|viewer_or_character_unavailable")
        else:
            SampleVisualCaptureWindow(Equipment, Attacker, Target, Weapon, Phase, Seconds)

    RunManagedVisualViewport(Equipment : coach_equipment, Attacker : agent, Character : fort_character, Target : fort_character, Weapon : fort_trace_weapon_component, Phase : string, Seconds : float, Viewer : player)<suspends>:void =
        if (View := VisualPortal.Views[Viewer], UI := GetPlayerUI[Viewer], Menu := View.Menu?):
            UI.RemoveWidget(Menu)
            CoachProbeLog("PCL|health_probe|managed_visual_menu_suspended|phase={Phase}|same_widget_retained")
            defer:
                if (Current := View.Menu?, Current = Menu):
                    UI.AddWidget(Menu, player_ui_slot{InputMode := ui_input_mode.All})
                    CoachProbeLog("PCL|health_probe|managed_visual_menu_restored|phase={Phase}|same_widget=1")
            RunManagedVisualCamera(Equipment, Attacker, Character, Target, Weapon, Phase, Seconds, Viewer)
        else:
            RunManagedVisualCamera(Equipment, Attacker, Character, Target, Weapon, Phase, Seconds, Viewer)

    RunManagedVisualCamera(Equipment : coach_equipment, Attacker : agent, Character : fort_character, Target : fort_character, Weapon : fort_trace_weapon_component, Phase : string, Seconds : float, Viewer : player)<suspends>:void =
        # The build-cycle owner already stopped navigation and tethered the NPC.
        Sleep(0.25)
        SavedPose := VisualCaptureCamera.GetTransform()
        Placed := PlaceNativeVisualCamera(Character, Target, "managed_{Phase}_initial")
        if (Placed?):
            defer:
                VisualCaptureCamera.RemoveFrom(Viewer)
                if (VisualCaptureCamera.TeleportTo[SavedPose]):
                    CoachProbeLog("PCL|health_probe|managed_visual_camera_restored|phase={Phase}|transform_restored=1")
                else:
                    CoachProbeLog("PCL|health_probe|managed_visual_camera_restore_failed|phase={Phase}")
            VisualCaptureCamera.AddTo(Viewer)
            Sleep(1.0)
            Reframed := PlaceNativeVisualCamera(Character, Target, "managed_{Phase}_reframed")
            if (not Reframed?):
                CoachProbeLog("PCL|health_probe|managed_visual_camera_not_run|phase={Phase}|reframe_rejected")
                return
            Sleep(0.25)
            SampleVisualCaptureWindow(Equipment, Attacker, Target, Weapon, Phase, Seconds)
        else:
            CoachProbeLog("PCL|health_probe|managed_visual_camera_not_run|phase={Phase}|placement_rejected")

    SampleVisualCaptureWindow(Equipment : coach_equipment, Attacker : agent, Target : fort_character, Weapon : fort_trace_weapon_component, Phase : string, Seconds : float)<suspends>:void =
        if (Character := Attacker.GetFortCharacter[]):
            Position := Character.GetTransform().Translation
            TargetPosition := Target.GetTransform().Translation
            Duration := Clamp(Seconds, 0.0, 40.0)
            var Route : string = "offscreen"
            if (VisualUseViewportCamera?):
                set Route = "game_viewport"
            CoachProbeLog("PCL|health_probe|npc_visual_capture_ready|phase={Phase}|x={Position.X}|y={Position.Y}|z={Position.Z}|target_x={TargetPosition.X}|target_y={TargetPosition.Y}|target_z={TargetPosition.Z}|duration={Duration}|time={GetSimulationElapsedTime()}|capture_route={Route}|private_diagnostic_camera_only")
            Started := GetSimulationElapsedTime()
            loop:
                Sleep(1.0)
                if (Ending? or not Target.IsActive[]):
                    return
                var PlanEquipped : int = 0
                if (Plan := Equipment.BuildPlan?, Item := Plan.GetComponent[item_component], Item.IsEquipped[]):
                    set PlanEquipped = 1
                var RifleEquipped : int = 0
                if (Item := Weapon.Entity.GetComponent[item_component], Item.IsEquipped[]):
                    set RifleEquipped = 1
                var Firing : int = 0
                if (Weapon.IsFiring[]):
                    set Firing = 1
                var RootMeshVisible : int = -1
                var RootMeshEnabled : int = -1
                var MapPose : int = -1
                var TorchPose : int = -1
                if (Plan := Equipment.BuildPlan?):
                    if (Mesh := Plan.GetComponent[mesh_component]):
                        set RootMeshVisible = 0
                        set RootMeshEnabled = 0
                        if (Mesh.Visible?):
                            set RootMeshVisible = 1
                        if (Mesh.IsEnabled[]):
                            set RootMeshEnabled = 1
                    if (Pose := Plan.GetComponent[fort_item_owner_pose_modifier_component]):
                        set MapPose = 0
                        set TorchPose = 0
                        if (fort_character_pose_modifier_map[Pose.EquippedPose?]):
                            set MapPose = 1
                        if (fort_character_pose_modifier_fire_torch[Pose.EquippedPose?]):
                            set TorchPose = 1
                CoachProbeLog("PCL|health_probe|npc_plan_visual_components|phase={Phase}|root_mesh_visible={RootMeshVisible}|root_mesh_enabled={RootMeshEnabled}|map_pose={MapPose}|torch_pose={TorchPose}")
                CoachProbeLog("PCL|health_probe|npc_visual_capture_status|phase={Phase}|elapsed={GetSimulationElapsedTime() - Started}|plan_equipped={PlanEquipped}|rifle_equipped={RifleEquipped}|firing={Firing}|target_health={Target.GetHealth()}")
                if (GetSimulationElapsedTime() - Started >= Duration):
                    break
            CoachProbeLog("PCL|health_probe|npc_visual_capture_finished|phase={Phase}|time={GetSimulationElapsedTime()}")

    RunBuildPlanCycle(Equipment : coach_equipment, Attacker : agent, Character : fort_character, Target : fort_character, Weapon : fort_trace_weapon_component, Actions : guard_actions_component, NativeTarget : entity, Cycle : int)<suspends>:void =
        Position := Character.GetTransform().Translation
        Actions.Tether(FromVector3(Position), 75.0)
        defer:
            Actions.Untether()
        Weapon.EndFire()
        Actions.StopNavigation()
        SampleBuildPlanWindow(Equipment, Attacker, Target, Weapon, Cycle)
        Selected := Equipment.SelectWeapon(Attacker, Distance(Character.GetTransform().Translation, Target.GetTransform().Translation))
        var SelectedOK : int = 0
        var PlanStillEquipped : int = 0
        var LockedAfterSelect : int = 0
        var RifleGateAfterSelect : int = 0
        if (Gate := Equipment.ManagedRifleGate?, Gate.Locked?):
            set RifleGateAfterSelect = 1
        if (Lock := Equipment.BuildPlanLock?, Lock.Locked?):
            set LockedAfterSelect = 1
        if (Selected?):
            set SelectedOK = 1
        if (Plan := Equipment.BuildPlan?, Item := Plan.GetComponent[item_component], Item.IsEquipped[]):
            set PlanStillEquipped = 1
        PhaseName := "build_plan_return_{Cycle}"
        CoachProbeLog("PCL|health_probe|npc_equipped_focus_request|phase={PhaseName}|select_ok={SelectedOK}|plan_still_equipped={PlanStillEquipped}|lock_after_select={LockedAfterSelect}|rifle_gate_after_select={RifleGateAfterSelect}|shared_hold_window|no_explicit_beginfire")
        if (Cycle = 1):
            WaitForVisualCapture(Equipment, Attacker, Target, Weapon, "rifle", VisualRifleCaptureSeconds)
        race:
            CoachHoldAttackWindow(Actions, Character, NativeTarget, 5.0)
            SampleEquippedNPC(Attacker, Target, Weapon, PhaseName, 16)
        CoachReleaseHold(Actions, "build_cycle_parent")

    RunEquippedNPCAttackControl(Attacker : agent, Actions : guard_actions_component)<suspends>:void =
        var Equipment : coach_equipment = coach_equipment{}
        if (Behavior := coach_damage_shooter_behavior[Attacker.GetNPCBehavior[]]):
            set Equipment = Behavior.Equipment
        else:
            CoachProbeLog("PCL|health_probe|npc_equipped_not_run|owned_behavior_equipment_unavailable")
            return
        var ParkedCount : int = 0
        defer:
            Equipment.DisposeBuildPlan()
            Cleaned := Equipment.DisposeLoadout()
            if (Cleaned?):
                CleanupAgain := Equipment.DisposeLoadout()
                if (CleanupAgain?, CountRangedItems(Attacker) = ParkedCount, not Equipment.ManagedRifle?, not Equipment.ManagedRifleGate?, not Equipment.BuildPlan?, not Equipment.BuildPlanLock?, not Equipment.BuildPlanIntent?):
                    CoachProbeLog("PCL|health_probe|npc_equipped_cleanup|parked={ParkedCount}|restored={ParkedCount}|original_ranged_items_returned_before_despawn|managed_rifle_removed=1|idempotent_cleanup=1|tool_lock_removed=1|rifle_gate_removed=1")
                else:
                    CoachProbeLog("PCL|health_probe|npc_equipped_cleanup_failed|restored_inventory_count_or_repeat_cleanup_unconfirmed")
            else:
                CoachProbeLog("PCL|health_probe|npc_equipped_cleanup_failed|equipment_cleanup_pending")
        RifleAdded := Equipment.InitializeNPCLoadout(Attacker)
        if (not RifleAdded?):
            CoachProbeLog("PCL|health_probe|npc_equipped_not_run|owned_rifle_unavailable")
            return
        set ParkedCount = Equipment.ParkedRanged.Length
        InitializedAgain := Equipment.InitializeNPCLoadout(Attacker)
        Selected := Equipment.SelectWeapon(Attacker, 1500.0)
        if (not InitializedAgain? or not Selected?):
            CoachProbeLog("PCL|health_probe|npc_equipped_not_run|repeat_initialization_or_weapon_selection_failed")
            return
        if (CountRangedItems(Attacker) <> 1):
            CoachProbeLog("PCL|health_probe|npc_equipped_not_run|owned_rifle_isolation_unconfirmed")
            return
        Prepared := Equipment.PrepareBuildPlan(Attacker)
        var PreparedOK : int = 0
        var PreparedEquipped : int = 0
        if (Prepared?):
            set PreparedOK = 1
        if (Plan := Equipment.BuildPlan?, Item := Plan.GetComponent[item_component], Item.IsEquipped[]):
            set PreparedEquipped = 1
        CoachProbeLog("PCL|health_probe|npc_build_plan_prepared|prepare_ok={PreparedOK}|plan_equipped={PreparedEquipped}|ranged_items={CountRangedItems(Attacker)}|before_target_spawn|no_tool_equip_request")
        CoachProbeLog("PCL|health_probe|npc_equipped_inventory|parked={ParkedCount}|ranged_items={CountRangedItems(Attacker)}|owned_rifle_only|production_equipment_module")
        CalibrationShooter.Spawn()
        for (Attempt := 0..99):
            if (Ending?):
                return
            if (TargetAgent := CombatTarget?, Target := TargetAgent.GetFortCharacter[], Target.IsActive[], TargetBody := Target.GetEntity[], AttackerCharacter := Attacker.GetFortCharacter[], AttackerBody := AttackerCharacter.GetEntity[], Awareness := AttackerBody.GetComponent[npc_awareness_component], Rifle := Equipment.ManagedRifle?, Weapon := Rifle.GetComponent[fort_trace_weapon_component]):
                Teams := GetPlayspace().GetTeamCollection()
                if (PreviousTeam := Teams.GetTeam[TargetAgent], EnemyTeam := Teams.GetTeams()[1], Teams.AddToTeam[TargetAgent, EnemyTeam], Attitude := Teams.GetTeamAttitude[Attacker, TargetAgent], Attitude = team_attitude.Hostile):
                    defer:
                        Weapon.EndFire()
                        Actions.StopNavigation()
                        Target.ReleaseFromStasis()
                        Target.SetVulnerability(false)
                        if (Teams.AddToTeam[TargetAgent, PreviousTeam]):
                            CoachProbeLog("PCL|health_probe|npc_equipped_target_team_restored")
                        else:
                            CoachProbeLog("PCL|health_probe|npc_equipped_cleanup_failed|target_team_restore_rejected")
                    if (Target.TeleportTo[vector3{X := -2848.0, Y := -2400.0, Z := 96.0}, IdentityRotation()]) {}
                    else:
                        CoachProbeLog("PCL|health_probe|npc_equipped_not_run|target_placement_rejected")
                        return
                    Target.SetMaxHealth(5000.0)
                    Target.SetHealth(5000.0)
                    Target.SetShield(0.0)
                    Target.PutInStasis(stasis_args{AllowTurning := false, AllowFalling := false})
                    Target.SetVulnerability(true)
                    set CombatDamageEvents = 0
                    set CombatHitsByShooter = 0
                    Binding := Target.DamagedEvent().Subscribe(OnCombatTargetDamaged)
                    defer:
                        Binding.Cancel()
                    var Detected : logic = false
                    var NativeTarget : entity = TargetBody
                    race:
                        block:
                            for (Wait := 0..79, not Detected?):
                                for (Info : Awareness.DetectedTargets, Info.Target = TargetBody or Info.Target = TargetAgent, Info.Attitude = team_attitude.Hostile, Info.HasLineOfSight?):
                                    set Detected = true
                                    set NativeTarget = Info.Target
                                Sleep(0.1)
                        block:
                            Actions.Focus(TargetBody, ?LockFocus := true)
                            loop:
                                Sleep(0.1)
                    if (not Detected?):
                        CoachProbeLog("PCL|health_probe|npc_equipped_not_run|hostile_detection_unconfirmed")
                        return
                    var MatchesBody : int = 0
                    var MatchesAgent : int = 0
                    if (NativeTarget = TargetBody):
                        set MatchesBody = 1
                    if (NativeTarget = TargetAgent):
                        set MatchesAgent = 1
                    CoachProbeLog("PCL|health_probe|npc_equipped_target_identity|body_match={MatchesBody}|agent_match={MatchesAgent}|action_target_is_exact_awareness_target")
                    CoachProbeLog("PCL|health_probe|npc_equipped_ready|hostile_detected=1|damage={Weapon.Damage}|fire_rate={Weapon.FireRate}|shot_cost={Weapon.ShotAmmoCost}|no_direct_damage")
                    SampleEquippedNPC(Attacker, Target, Weapon, "detected_baseline", 8)
                    for (Cycle := 1..3):
                        if (Ending? or not Target.IsActive[]):
                            return
                        RunBuildPlanCycle(Equipment, Attacker, AttackerCharacter, Target, Weapon, Actions, NativeTarget, Cycle)
                    Weapon.EndFire()
                    Actions.StopNavigation()
                    CleanupHeld := EquipPlanFromNPCBehavior(Attacker)
                    Sleep(0.5)
                    var CleanupPlanEquipped : int = 0
                    var CleanupLocked : int = 0
                    if (Plan := Equipment.BuildPlan?, Item := Plan.GetComponent[item_component], Item.IsEquipped[]):
                        set CleanupPlanEquipped = 1
                    if (Lock := Equipment.BuildPlanLock?, Lock.Locked?):
                        set CleanupLocked = 1
                    CoachProbeLog("PCL|health_probe|npc_build_plan_cleanup_ready|plan_equipped={CleanupPlanEquipped}|lock_active={CleanupLocked}|cleanup_from_tool_intended")
                    CoachProbeLog("PCL|health_probe|npc_equipped_finished|target_health={Target.GetHealth()}|source_hits={CombatHitsByShooter}|no_direct_damage_or_legacy_attack_phase")
                else:
                    CoachProbeLog("PCL|health_probe|npc_equipped_not_run|hostile_team_unconfirmed")
                return
            Sleep(0.1)
        CoachProbeLog("PCL|health_probe|npc_equipped_not_run|target_or_owned_rifle_unavailable")

    RunPlayerCharacterTargetControl(Owner : agent, Carrier : agent, Weapon : fort_trace_weapon_component)<suspends>:void =
        CalibrationShooter.Spawn()
        for (Attempt := 0..99):
            if (Ending?):
                return
            if (Target := CombatTarget?, TargetCharacter := Target.GetFortCharacter[], TargetCharacter.IsActive[], CarrierCharacter := Carrier.GetFortCharacter[], PlayerCharacter := Owner.GetFortCharacter[], PlayerCharacter.IsActive[]):
                Teams := GetPlayspace().GetTeamCollection()
                if (CarrierTeam := Teams.GetTeam[Carrier], TargetTeam := Teams.GetTeam[Target], OwnerTeam := Teams.GetTeam[Owner], EnemyTeam := Teams.GetTeams()[1], EnemyTeam <> OwnerTeam, Teams.AddToTeam[Carrier, EnemyTeam], Teams.AddToTeam[Target, EnemyTeam]):
                    var WasVulnerable : logic = false
                    if (PlayerCharacter.IsVulnerable[]):
                        set WasVulnerable = true
                    PlayerCharacter.SetVulnerability(false)
                    CarrierCharacter.SetVulnerability(false)
                    CarrierCharacter.PutInStasis(stasis_args{AllowTurning := false, AllowFalling := false})
                    defer:
                        TargetCharacter.SetVulnerability(false)
                        TargetCharacter.ReleaseFromStasis()
                        CarrierCharacter.ReleaseFromStasis()
                        PlayerCharacter.SetVulnerability(WasVulnerable)
                        if (Teams.AddToTeam[Carrier, CarrierTeam], Teams.AddToTeam[Target, TargetTeam]):
                            CoachProbeLog("PCL|health_probe|player_target_teams_restore_returned_ok")
                        else:
                            CoachProbeLog("PCL|health_probe|player_target_teams_restore_failed")
                        if (WasVulnerable?):
                            if (PlayerCharacter.IsVulnerable[]):
                                CoachProbeLog("PCL|health_probe|player_vulnerability_restore_confirmed|vulnerable=1")
                            else:
                                CoachProbeLog("PCL|health_probe|player_vulnerability_restore_failed")
                        else:
                            if (PlayerCharacter.IsVulnerable[]):
                                CoachProbeLog("PCL|health_probe|player_vulnerability_restore_failed")
                            else:
                                CoachProbeLog("PCL|health_probe|player_vulnerability_restore_confirmed|vulnerable=0")
                    if (Teams.GetTeamAttitude[Owner, Target] = team_attitude.Hostile, Teams.GetTeamAttitude[Carrier, Target] = team_attitude.Friendly):
                        CoachProbeLog("PCL|health_probe|player_target_native_teams_confirmed")
                    else:
                        CoachProbeLog("PCL|health_probe|player_target_not_run|team_relationship_unconfirmed")
                        return
                    if (TargetCharacter.TeleportTo[vector3{X := -1536.0, Y := -2400.0, Z := 96.0}, IdentityRotation()]) {}
                    else:
                        CoachProbeLog("PCL|health_probe|player_target_not_run|target_placement_rejected")
                        return
                    TargetCharacter.PutInStasis(stasis_args{AllowTurning := false, AllowFalling := false})
                    TargetCharacter.SetMaxHealth(5000.0)
                    TargetCharacter.SetHealth(5000.0)
                    TargetCharacter.SetShield(0.0)
                    TargetCharacter.SetVulnerability(true)
                    set CalibratedPlayer = option{Owner}
                    set PlayerTargetHits = 0
                    Binding := TargetCharacter.DamagedEvent().Subscribe(OnPlayerTargetDamaged)
                    defer:
                        Binding.Cancel()
                        set CalibratedPlayer = false
                    Position := TargetCharacter.GetTransform().Translation
                    CoachProbeLog("PCL|health_probe|player_target_ready|health={TargetCharacter.GetHealth()}|x={Position.X}|y={Position.Y}|z={Position.Z}|hostile_to_player|carrier_friendly_to_target|no_guard_Attack_request")
                    CalibrationShooter.Disable()
                    RunPlayerWeaponControl(Owner, Weapon, ?CharacterTarget := option{TargetCharacter})
                    CoachProbeLog("PCL|health_probe|player_target_finished|health={TargetCharacter.GetHealth()}|player_hits={PlayerTargetHits}|no_direct_damage_called")
                else:
                    CoachProbeLog("PCL|health_probe|player_target_not_run|teams_unavailable")
                return
            Sleep(0.1)
        CoachProbeLog("PCL|health_probe|player_target_not_run|target_unavailable")

    CheckTeamWallShotPose(Character : fort_character, Phase : string):logic =
        var PositionDistance : float = -1.0
        if (Character.IsActive[]):
            set PositionDistance = Distance(Character.GetTransform().Translation, vector3{X := -1536.0, Y := -4096.0, Z := 96.0})
            if (PositionDistance <= 150.0):
                return true
        set TeamWallShotPoseFailures += 1
        CoachProbeLog("PCL|health_probe|team_wall_shot_pose_rejected|phase={Phase}|position_distance={PositionDistance}|unchanged_150cm_guard|no_further_fire")
        return false

    AwaitTeamWallPlayerPose(Owner : agent, Character : fort_character, Stage : string)<suspends>:logic =
        var Consecutive : int = 0
        var Ready : logic = false
        for (Pass := 1..12, not Ready?):
            Sleep(0.25)
            if (Ending? or not Character.IsActive[]):
                return false
            Body := Character.GetTransform().Translation
            PositionDistance := Distance(Body, vector3{X := -1536.0, Y := -4096.0, Z := 96.0})
            ViewDistance := Distance(Character.GetViewLocation(), Body)
            Velocity := Character.GetLinearVelocity()
            Speed := Sqrt(Velocity.Forward * Velocity.Forward + Velocity.Left * Velocity.Left + Velocity.Up * Velocity.Up)
            var Crouching : int = 0
            var Grounded : int = 0
            var SourceDistance : float = -1.0
            if (Character.IsCrouching[]):
                set Crouching = 1
            if (Character.IsOnGround[]):
                set Grounded = 1
            if (Source := Shooter?, SourceCharacter := Source.GetFortCharacter[], SourceCharacter.IsActive[]):
                set SourceDistance = Distance(SourceCharacter.GetTransform().Translation, vector3{X := -1536.0, Y := -4096.0, Z := 96.0})
            if (PositionDistance <= 150.0, ViewDistance <= 500.0, Speed <= 0.05):
                set Consecutive += 1
            else:
                set Consecutive = 0
                if (PositionDistance > 150.0):
                    CalibrationPlayerTeleporter.Teleport(Owner)
            CoachProbeLog("PCL|health_probe|team_wall_pose_sample|stage={Stage}|pass={Pass}|position_distance={PositionDistance}|view_body_distance={ViewDistance}|speed_meters={Speed}|crouching={Crouching}|grounded={Grounded}|source_destination_distance={SourceDistance}|consecutive={Consecutive}")
            if (Consecutive >= 2):
                set Ready = true
        return Ready

    RunPlayerWeaponControl(Owner : agent, Weapon : fort_trace_weapon_component, ?CharacterTarget : ?fort_character = false)<suspends>:void =
        if (Character := Owner.GetFortCharacter[], Character.IsActive[], Rifle := ProbeRifle?, Item := Rifle.GetComponent[item_component], PreviousInventory := Item.GetParentInventory[]):
            PreviousCalibratedPlayer := CalibratedPlayer
            set CalibratedPlayer = option{Owner}
            set ObjectivePlayerHits = 0
            set ControlPlayerHits = 0
            defer:
                set CalibratedPlayer = PreviousCalibratedPlayer
            OriginalTransform := Character.GetTransform()
            OriginalView := Character.GetViewRotation()
            OriginalCost := Weapon.ShotAmmoCost
            var PreviousEquipped : []item_component = array{}
            for (Inventory : Owner.FindDescendantComponents(inventory_component)):
                EquippedItems := Inventory.GetEquippedItems()
                for (Previous : EquippedItems, PreviousItem := Previous.GetComponent[item_component]):
                    set PreviousEquipped += array{PreviousItem}
            defer:
                CalibrationPlayerTeleporter.Disable()
                if (Current := ProbeRifle?, Current = Rifle):
                    Weapon.SetShotAmmoCost(OriginalCost)
                RestorePlayerEquipment(PreviousEquipped)
                RemoveProbeRifle()
                if (Character.IsActive[]):
                    if (Character.TeleportTo[OriginalTransform.Translation, OriginalView]):
                        CoachProbeLog("PCL|health_probe|player_control_position_restore_returned_ok")
                    else:
                        CoachProbeLog("PCL|health_probe|player_control_position_restore_failed")
                var RemovedFlag : int = 0
                if (not ProbeRifle?):
                    set RemovedFlag = 1
                CoachProbeLog("PCL|health_probe|player_control_cleanup|previous_equipped={PreviousEquipped.Length}|owned_rifle_removed={RemovedFlag}")
            Removed := PreviousInventory.RemoveItem(Rifle)
            if (not Removed.GetSuccess[]):
                CoachProbeLog("PCL|health_probe|player_control_not_run|rifle_transfer_rejected")
                return
            var Added : logic = false
            for (Child : Owner.GetEntities(), Inventory := Child.GetComponent[inventory_component], not Added?):
                Result := Inventory.AddItemDistribute(Rifle)
                if (Result.GetSuccess[]):
                    set Added = true
            if (not Added?):
                CoachProbeLog("PCL|health_probe|player_control_not_run|inventory_rejected")
                return
            Equipped := Item.Equip()
            if (not Equipped.GetSuccess[]):
                CoachProbeLog("PCL|health_probe|player_control_not_run|equip_rejected")
                return
            CalibrationPlayerTeleporter.Enable()
            if (CalibrationPlayerTeleporter.TeleportTo[vector3{X := -1536.0, Y := -4096.0, Z := 96.0}, MakeRotationFromYawPitchRollDegrees(0.0, 0.0, 0.0)]):
                CalibrationPlayerTeleporter.Teleport(Owner)
            else:
                CoachProbeLog("PCL|health_probe|player_control_not_run|placement_rejected")
                return
            for (PlacementPass := 1..3):
                Immediate := Character.GetTransform().Translation
                CoachProbeLog("PCL|health_probe|player_placement_sample|pass={PlacementPass}|x={Immediate.X}|y={Immediate.Y}|z={Immediate.Z}")
                Sleep(0.35)
                if (Distance(Character.GetTransform().Translation, vector3{X := -1536.0, Y := -4096.0, Z := 96.0}) > 150.0):
                    CalibrationPlayerTeleporter.Teleport(Owner)
            Sleep(0.35)
            for (ViewPass := 1..12, Distance(Character.GetViewLocation(), Character.GetTransform().Translation) > 500.0):
                CoachProbeLog("PCL|health_probe|player_view_wait|pass={ViewPass}|view_body_distance={Distance(Character.GetViewLocation(), Character.GetTransform().Translation)}|placement_guard_unchanged")
                Sleep(0.5)
            if (NativeTeamWallControl? or NativeWallTransitionControl?):
                PlacementReady := AwaitTeamWallPlayerPose(Owner, Character, "post_placement")
                if (not PlacementReady?):
                    CoachProbeLog("PCL|health_probe|player_control_not_run|position_not_stable|unchanged_guard")
                    return
            ActualPosition := Character.GetTransform().Translation
            ActualView := Character.GetViewLocation()
            Velocity := Character.GetLinearVelocity()
            CoachProbeLog("PCL|health_probe|player_control_pose|body_x={ActualPosition.X}|body_y={ActualPosition.Y}|body_z={ActualPosition.Z}|view_x={ActualView.X}|view_y={ActualView.Y}|view_z={ActualView.Z}")
            CoachProbeLog("PCL|health_probe|player_control_velocity|forward={Velocity.Forward}|left={Velocity.Left}|up={Velocity.Up}|meters_per_second")
            if (Distance(ActualPosition, vector3{X := -1536.0, Y := -4096.0, Z := 96.0}) > 150.0):
                CoachProbeLog("PCL|health_probe|player_control_not_run|actual_position_mismatch")
                return
            if (Distance(ActualView, ActualPosition) > 500.0):
                CoachProbeLog("PCL|health_probe|player_control_not_run|view_position_not_ready")
                return
            var Aim : vector3 = CalibrationObjective.GetTransform().Translation + CalibrationAimOffset
            if (Target := CharacterTarget?):
                set Aim = Target.GetTransform().Translation + vector3{Z := 40.0}
            Delta := Aim - Character.GetViewLocation()
            Yaw := ArcTan(Delta.Y, Delta.X) * 180.0 / PiFloat
            Pitch := ArcTan(Delta.Z, Sqrt(Delta.X * Delta.X + Delta.Y * Delta.Y)) * 180.0 / PiFloat
            if (CalibrationPlayerTeleporter.TeleportTo[vector3{X := -1536.0, Y := -4096.0, Z := 96.0}, MakeRotationFromYawPitchRollDegrees(Yaw, Pitch, 0.0)]):
                CalibrationPlayerTeleporter.Teleport(Owner)
            else:
                CoachProbeLog("PCL|health_probe|player_control_not_run|aim_placement_rejected")
                return
            Sleep(0.75)
            var AimReady : logic = false
            for (AimPass := 1..8, not AimReady?):
                NextDelta := Aim - Character.GetViewLocation()
                if (DesiredDirection := NextDelta.MakeUnitVector[]):
                    CurrentAlignment := DotProduct(DesiredDirection, Character.GetViewRotation().GetLocalForward())
                    if (CurrentAlignment >= RequiredPlayerAimAlignment):
                        set AimReady = true
                    else:
                        NextYaw := ArcTan(NextDelta.Y, NextDelta.X) * 180.0 / PiFloat
                        NextPitch := ArcTan(NextDelta.Z, Sqrt(NextDelta.X * NextDelta.X + NextDelta.Y * NextDelta.Y)) * 180.0 / PiFloat
                        if (CalibrationPlayerTeleporter.TeleportTo[vector3{X := -1536.0, Y := -4096.0, Z := 96.0}, MakeRotationFromYawPitchRollDegrees(NextYaw, NextPitch, 0.0)]):
                            CalibrationPlayerTeleporter.Teleport(Owner)
                        Sleep(0.25)
            if (NativeTeamWallControl? or NativeWallTransitionControl?):
                AimedPoseReady := AwaitTeamWallPlayerPose(Owner, Character, "post_aim")
                if (not AimedPoseReady?):
                    CoachProbeLog("PCL|health_probe|player_control_not_run|aimed_position_not_stable|unchanged_guard")
                    return
            FinalView := Character.GetViewLocation()
            FinalForward := Character.GetViewRotation().GetLocalForward()
            CoachProbeLog("PCL|health_probe|player_final_view|x={FinalView.X}|y={FinalView.Y}|z={FinalView.Z}|forward_x={FinalForward.X}|forward_y={FinalForward.Y}|forward_z={FinalForward.Z}")
            if (AimDirection := (Aim - Character.GetViewLocation()).MakeUnitVector[]):
                Alignment := DotProduct(AimDirection, Character.GetViewRotation().GetLocalForward())
                CoachProbeLog("PCL|health_probe|player_actual_aim|alignment={Alignment}|native_teleports={PlayerTeleports}")
                if (Alignment < RequiredPlayerAimAlignment):
                    CoachProbeLog("PCL|health_probe|player_control_not_run|actual_aim_mismatch")
                    return
            else:
                return
            if (CalibrationNoFireZone.IsInVolume[Owner]):
                CoachProbeLog("PCL|health_probe|player_control_not_run|native_no_fire_zone_contains_owner")
                return
            set PlayerControlReadyCount += 1
            CoachProbeLog("PCL|health_probe|player_control_ready|same_owned_rifle|view_yaw={Yaw}|view_pitch={Pitch}|no_client_input")
            LogPlayerShotQuery(Character, Aim, CharacterTarget)
            if (Target := CharacterTarget?):
                CoachProbeLog("PCL|health_probe|player_target_baseline|before={Target.GetHealth()}|no_BeginFire")
                Sleep(2.0)
                CoachProbeLog("PCL|health_probe|player_target_baseline_end|health={Target.GetHealth()}|player_hits={PlayerTargetHits}")
            SampleNativeFire(Weapon, Character, "player_native_cost", ?CharacterTarget := CharacterTarget)
            if (NativeWallTransitionControl? and TransitionFailed?):
                CoachProbeLog("PCL|health_probe|native_transition_zero_cost_skipped|previous_phase_failed|no_fire_restart")
                return
            Weapon.SetShotAmmoCost(0)
            SampleNativeFire(Weapon, Character, "player_zero_cost", ?CharacterTarget := CharacterTarget)
            Weapon.EndFire()
            RestorePlayerEquipment(PreviousEquipped)
            Sleep(0.5)
        else:
            CoachProbeLog("PCL|health_probe|player_control_not_run|owner_or_owned_rifle_unavailable")

    RestoreTeamWallTeams():logic =
        if (TeamWallOriginalTeams.Length = 0):
            return true
        Teams := GetPlayspace().GetTeamCollection()
        var Pending : []tuple(agent, team) = array{}
        for (Index -> Entry : TeamWallOriginalTeams):
            Subject := Entry(0)
            Previous := Entry(1)
            if (not Teams.IsOnTeam[Subject, Previous]):
                if (Teams.AddToTeam[Subject, Previous]) {}
            if (Teams.IsOnTeam[Subject, Previous]):
                CoachProbeLog("PCL|health_probe|team_wall_team_restored|subject={Index}")
            else:
                set Pending += array{Entry}
                CoachProbeLog("PCL|health_probe|team_wall_team_restore_failed|subject={Index}")
        set TeamWallOriginalTeams = Pending
        if (Pending.Length = 0):
            return true
        return false

    AssignWallProbeTeam(Owner : agent, Source : agent, Desired : team, Name : string):logic =
        Teams := GetPlayspace().GetTeamCollection()
        for (Subject : array{Owner, Source}):
            if (not Teams.IsOnTeam[Subject, Desired]):
                if (Teams.AddToTeam[Subject, Desired]) {}
            if (not Teams.IsOnTeam[Subject, Desired]):
                CoachProbeLog("PCL|health_probe|team_wall_not_run|phase={Name}|team_assignment_unconfirmed")
                return false
        for (Index -> Value : Teams.GetTeams(), Value = Desired):
            CoachProbeLog("PCL|health_probe|team_wall_team_confirmed|phase={Name}|owner_and_source_zero_based_team={Index}")
        return true

    RunWallTeamWeaponPhase(Owner : agent, Weapon : fort_trace_weapon_component, Name : string)<suspends>:logic =
        Before := PlayerControlReadyCount
        BeforePoseFailures := TeamWallShotPoseFailures
        CoachProbeLog("PCL|health_probe|team_wall_phase_begin|phase={Name}|objective_health={CalibrationObjective.GetHealth()}|damage={Weapon.Damage}|fire_rate={Weapon.FireRate}|environment_multiplier={Weapon.EnvironmentalDamageMultiplier}|no_health_write")
        LogCalibrationWallState("{Name}_before")
        RunPlayerWeaponControl(Owner, Weapon)
        ReadyDelta := PlayerControlReadyCount - Before
        PoseFailureDelta := TeamWallShotPoseFailures - BeforePoseFailures
        LogCalibrationWallState("{Name}_after")
        CoachProbeLog("PCL|health_probe|team_wall_phase_end|phase={Name}|ready_delta={ReadyDelta}|pose_failures_delta={PoseFailureDelta}|objective_health={CalibrationObjective.GetHealth()}|objective_player_hits={ObjectivePlayerHits}|wall_damage_events={ControlDamageEvents}|wall_player_hits={ControlPlayerHits}|wall_destroyed_events={ControlDestroyedEvents}|allocations={SpawnedWallGeneration}|observed_invalid={ObservedSpawnedWallDeaths}")
        if (ReadyDelta = 1, PoseFailureDelta = 0):
            return true
        return false

    CheckNativeTransitionGeometry(Stage : string, Origin : vector3, ExpectedHere : int, ExpectedMoved : int):logic =
        if (Root := GetSimulationEntity[]):
            Here := Geometry.SampleWall(Root, Origin, 90.0)
            Moved := Geometry.SampleWall(Root, Origin + vector3{X := 1024.0}, 90.0)
            CoachProbeLog("PCL|health_probe|native_transition_geometry|phase={TransitionPhase}|stage={Stage}|here={Here.Occupied}|moved={Moved.Occupied}|expected_here={ExpectedHere}|expected_moved={ExpectedMoved}|query_yaw=90")
            if (Here.Occupied = ExpectedHere, Moved.Occupied = ExpectedMoved):
                return true
        return false

    AwaitNativeTransitionFiring(Weapon : fort_trace_weapon_component, Character : fort_character, Desired : logic, Stage : string)<suspends>:logic =
        var Consecutive : int = 0
        for (Pass := 1..20, Consecutive < 2):
            if (Ending? or not Character.IsActive[]):
                return false
            var Firing : int = 0
            if (Weapon.IsFiring[]):
                set Firing = 1
            var Matches : logic = false
            if (Desired? and Firing = 1):
                set Matches = true
            else if (not Desired? and Firing = 0):
                set Matches = true
            if (Matches?):
                set Consecutive += 1
            else:
                set Consecutive = 0
            CoachProbeLog("PCL|health_probe|native_transition_fire_state|phase={TransitionPhase}|stage={Stage}|pass={Pass}|is_firing={Firing}|wall_events={ControlDamageEvents}|player_hits={ControlPlayerHits}|objective_health={CalibrationObjective.GetHealth()}|consecutive={Consecutive}")
            if (not Desired? and (ControlPlayerHits <> 3 or ControlDamageEvents <> 3)):
                CoachProbeLog("PCL|health_probe|native_transition_not_run|damage_during_fire_stop_wait")
                return false
            if (Consecutive < 2):
                Sleep(0.05)
        if (Consecutive >= 2):
            return true
        return false

    PerformNativeWallTransition(Weapon : fort_trace_weapon_component, Character : fort_character)<suspends>:logic =
        set TransitionPending = false
        Wall := ControlTarget()
        Phase := TransitionPhase
        var TransformDirty : logic = false
        var MeshDirty : logic = false
        var Success : logic = false
        defer:
            if (not Success?):
                set TransitionFailed = true
        if (Wall.IsValid[], Phase > 0, Phase <= 2, NativeWallTransitionCase >= 1, NativeWallTransitionCase <= 3):
            Original := Wall.GetTransform()
            BeforeObjective := CalibrationObjective.GetHealth()
            BeforeEvents := ControlDamageEvents
            Weapon.EndFire()
            Idle := AwaitNativeTransitionFiring(Weapon, Character, false, "transition_stop")
            if (not Idle? or ControlPlayerHits <> 3):
                CoachProbeLog("PCL|health_probe|native_transition_not_run|pause_not_clean|phase={Phase}|hits={ControlPlayerHits}")
                return false
            InitialGeometry := CheckNativeTransitionGeometry("pause_before", Original.Translation, 9, 0)
            if (not InitialGeometry?):
                return false
            CoachProbeLog("PCL|health_probe|native_transition_pause_begin|phase={Phase}|case={NativeWallTransitionCase}|player_hits={ControlPlayerHits}|wall_events={BeforeEvents}|objective_health={BeforeObjective}|is_firing=0|no_health_write")
            defer:
                if (Wall.IsValid[]):
                    if (MeshDirty?):
                        Wall.SetMesh(Structures.WallSolidMesh)
                    if (TransformDirty?):
                        if (Wall.TeleportTo[Original]) {}
            if (Phase = 1):
                if (NativeWallTransitionCase = 3):
                    Sleep(0.8)
                else:
                    Sleep(0.4)
            else:
                if (NativeWallTransitionCase = 1 or NativeWallTransitionCase = 3):
                    set TransformDirty = true
                    MovedPose := transform{Translation := Original.Translation + vector3{X := 1024.0}, Rotation := Original.Rotation, Scale := Original.Scale}
                    if (Wall.TeleportTo[MovedPose]) {}
                    else:
                        CoachProbeLog("PCL|health_probe|native_transition_not_run|move_rejected")
                        return false
                    Sleep(0.2)
                    if (Ending? or not Wall.IsValid[]):
                        return false
                    MovedGeometry := CheckNativeTransitionGeometry("moved", Original.Translation, 0, 9)
                    if (not MovedGeometry?):
                        return false
                    if (Wall.TeleportTo[Original]):
                        set TransformDirty = false
                    else:
                        CoachProbeLog("PCL|health_probe|native_transition_not_run|return_rejected")
                        return false
                    Sleep(0.2)
                    if (Ending? or not Wall.IsValid[]):
                        return false
                    ReturnedGeometry := CheckNativeTransitionGeometry("returned", Original.Translation, 9, 0)
                    if (not ReturnedGeometry?):
                        return false
                if (NativeWallTransitionCase = 2 or NativeWallTransitionCase = 3):
                    set MeshDirty = true
                    Wall.SetMesh(Structures.WallWindowMesh)
                    Sleep(0.2)
                    if (Ending? or not Wall.IsValid[]):
                        return false
                    WindowGeometry := CheckNativeTransitionGeometry("window", Original.Translation, 8, 0)
                    if (not WindowGeometry?):
                        return false
                    Wall.SetMesh(Structures.WallSolidMesh)
                    set MeshDirty = false
                    Sleep(0.2)
                    if (Ending? or not Wall.IsValid[]):
                        return false
                    ResetGeometry := CheckNativeTransitionGeometry("solid_reset", Original.Translation, 9, 0)
                    if (not ResetGeometry?):
                        return false
            if (Ending? or not Wall.IsValid[] or TransitionPhase <> Phase):
                return false
            FinalGeometry := CheckNativeTransitionGeometry("pause_after", Original.Translation, 9, 0)
            if (not FinalGeometry? or ControlDamageEvents <> BeforeEvents or CalibrationObjective.GetHealth() <> BeforeObjective or Weapon.IsFiring[]):
                CoachProbeLog("PCL|health_probe|native_transition_not_run|pause_contaminated|phase={Phase}|wall_events={ControlDamageEvents}|objective_health={CalibrationObjective.GetHealth()}")
                return false
            set TransitionDone = true
            set Success = true
            CoachProbeLog("PCL|health_probe|native_transition_pause_end|phase={Phase}|case={NativeWallTransitionCase}|player_hits={ControlPlayerHits}|wall_events={ControlDamageEvents}|objective_health={CalibrationObjective.GetHealth()}|same_reference|no_health_write")
            return true
        CoachProbeLog("PCL|health_probe|native_transition_not_run|wall_phase_or_case_unavailable")
        return false

    RunNativeTransitionPhase(Owner : agent, Source : agent, Phase : int)<suspends>:logic =
        set TransitionPhase = Phase
        set TransitionPending = false
        set TransitionDone = false
        set TransitionFailed = false
        set ControlDamageEvents = 0
        set ControlDestroyedEvents = 0
        BeforeReady := PlayerControlReadyCount
        BeforePoseFailures := TeamWallShotPoseFailures
        Added := AddProbeRifle(Source)
        if (Added?, Rifle := ProbeRifle?, Weapon := Rifle.GetComponent[fort_trace_weapon_component]):
            CoachProbeLog("PCL|health_probe|native_transition_phase_begin|phase={Phase}|case={NativeWallTransitionCase}|damage={Weapon.Damage}|fire_rate={Weapon.FireRate}|environment_multiplier={Weapon.EnvironmentalDamageMultiplier}|objective_health={CalibrationObjective.GetHealth()}|no_wall_health_write")
            LogCalibrationWallState("native_transition_{Phase}_before")
            RunPlayerWeaponControl(Owner, Weapon)
            ReadyDelta := PlayerControlReadyCount - BeforeReady
            PoseDelta := TeamWallShotPoseFailures - BeforePoseFailures
            var Invalid : int = 0
            var Completed : int = 0
            if (not ControlTarget().IsValid[]):
                set Invalid = 1
            if (TransitionDone? and not TransitionFailed?):
                set Completed = 1
            LogCalibrationWallState("native_transition_{Phase}_after")
            CoachProbeLog("PCL|health_probe|native_transition_phase_end|phase={Phase}|ready_delta={ReadyDelta}|pose_failures_delta={PoseDelta}|transition_completed={Completed}|wall_invalid={Invalid}|wall_damage_events={ControlDamageEvents}|wall_player_hits={ControlPlayerHits}|wall_destroyed_events={ControlDestroyedEvents}|objective_player_hits={ObjectivePlayerHits}|objective_health={CalibrationObjective.GetHealth()}")
            if (ReadyDelta = 1, PoseDelta = 0, Completed = 1, Invalid = 1, ControlDestroyedEvents = 1, ObjectivePlayerHits > 0):
                return true
        else:
            CoachProbeLog("PCL|health_probe|native_transition_not_run|rifle_unavailable")
        return false

    RunNativeWallTransitionPair(Owner : agent, Source : agent)<suspends>:void =
        Teams := GetPlayspace().GetTeamCollection()
        if (ControlWall.IsValid[], EditedWall.IsValid[], TeamOne := Teams.GetTeams()[0], Teams.IsOnTeam[Owner, TeamOne], Teams.IsOnTeam[Source, TeamOne], NativeWallTransitionCase >= 1, NativeWallTransitionCase <= 3):
            if (ControlDamageEvents <> 0 or EditedDamageEvents <> 0 or ControlDestroyedEvents <> 0 or EditedDestroyedEvents <> 0 or CalibrationObjective.GetHealth() <> 5000.0):
                CoachProbeLog("PCL|health_probe|native_transition_not_run|initial_baseline_contaminated")
                return
            TargetPose := ControlWall.GetTransform()
            var Snapshot : []tuple(item_component, inventory_component, int) = array{}
            for (Inventory : Owner.FindDescendantComponents(inventory_component), Value : Inventory.GetItems(), Item := Value.GetComponent[item_component]):
                var Equipped : int = 0
                if (Item.IsEquipped[]):
                    set Equipped = 1
                set Snapshot += array{(Item, Inventory, Equipped)}
            defer:
                RemoveProbeRifle()
                TransitionPool.RetireAll()
                set TransitionPhase = 0
                var Unchanged : int = 0
                for (Entry : Snapshot, Item := Entry(0), Inventory := Entry(1), Item.GetParentInventory[] = Inventory):
                    if (Entry(2) = 1, not Item.IsEquipped[]):
                        Reequipped := Item.Equip()
                    else if (Entry(2) = 0, Item.IsEquipped[]):
                        Unequipped := Item.Unequip()
                    var Equipped : int = 0
                    if (Item.IsEquipped[]):
                        set Equipped = 1
                    if (Equipped = Entry(2)):
                        set Unchanged += 1
                CoachProbeLog("PCL|health_probe|native_transition_cleanup|player_snapshot_items={Snapshot.Length}|unchanged_identity_parent_equipped={Unchanged}|no_original_items_recreated")
            ControlWall.SetMesh(Structures.WallSolidMesh)
            EditedWall.SetMesh(Structures.WallSolidMesh)
            EditedWall.Hide()
            ControlWall.Show()
            Sleep(0.25)
            ControlRan := RunNativeTransitionPhase(Owner, Source, 1)
            if (not ControlRan?):
                CoachProbeLog("PCL|health_probe|native_transition_not_run|pause_control_incomplete")
                return
            TransitionPool.Register(array{EditedWall}, coach_piece_kind.Wall)
            TransitionPool.Seal()
            Allocation := TransitionPool.Acquire(coach_piece_kind.Wall, TargetPose, 118)
            if (Lease := Allocation?, Lease.State = coach_pool_piece_state.Active):
                CoachProbeLog("PCL|health_probe|native_transition_pool_acquired|remaining={TransitionPool.Available(coach_piece_kind.Wall)}|active_lease=1|no_respawn_or_health_write")
                Sleep(0.25)
                ChangedRan := RunNativeTransitionPhase(Owner, Source, 2)
                var ChangedReady : int = 0
                if (ChangedRan?):
                    set ChangedReady = 1
                CoachProbeLog("PCL|health_probe|native_transition_pair_finished|changed_phase_completed={ChangedReady}|case={NativeWallTransitionCase}|native_owner_edit_and_slots_unmeasured")
            else:
                CoachProbeLog("PCL|health_probe|native_transition_not_run|native_pool_allocation_failed")
        else:
            CoachProbeLog("PCL|health_probe|native_transition_not_run|two_walls_player_team_one_or_case_unavailable")

    RunNativeTeamWallControl(Owner : agent, Source : agent)<suspends>:void =
        Teams := GetPlayspace().GetTeamCollection()
        Wall := ControlTarget()
        if (not IsolatedWallControl? or TeamWallOriginalTeams.Length <> 0):
            CoachProbeLog("PCL|health_probe|team_wall_not_run|isolation_or_cleanup_precondition")
            return
        if (Wall.IsValid[], OriginalOwner := Teams.GetTeam[Owner], OriginalSource := Teams.GetTeam[Source], Friendly := Teams.GetTeams()[1], Enemy := Teams.GetTeams()[0], Friendly <> Enemy):
            var Snapshot : []tuple(item_component, inventory_component, int) = array{}
            for (Inventory : Owner.FindDescendantComponents(inventory_component), Value : Inventory.GetItems(), Item := Value.GetComponent[item_component]):
                var Equipped : int = 0
                if (Item.IsEquipped[]):
                    set Equipped = 1
                set Snapshot += array{(Item, Inventory, Equipped)}
            set TeamWallOriginalTeams = array{(Owner, OriginalOwner), (Source, OriginalSource)}
            defer:
                if (Wall.IsValid[]):
                    Wall.Show()
                TeamsRestored := RestoreTeamWallTeams()
                var RestoredFlag : int = 0
                if (TeamsRestored?):
                    set RestoredFlag = 1
                var Unchanged : int = 0
                for (Entry : Snapshot, Item := Entry(0), Inventory := Entry(1), Item.GetParentInventory[] = Inventory):
                    if (Entry(2) = 1, not Item.IsEquipped[]):
                        Reequipped := Item.Equip()
                    else if (Entry(2) = 0, Item.IsEquipped[]):
                        Unequipped := Item.Unequip()
                    var CurrentEquipped : int = 0
                    if (Item.IsEquipped[]):
                        set CurrentEquipped = 1
                    if (CurrentEquipped = Entry(2)):
                        set Unchanged += 1
                CoachProbeLog("PCL|health_probe|team_wall_cleanup|teams_restored={RestoredFlag}|player_snapshot_items={Snapshot.Length}|unchanged_identity_parent_equipped={Unchanged}|no_original_items_recreated")
            SameTeam := AssignWallProbeTeam(Owner, Source, Friendly, "same_team_visible")
            if (not SameTeam?):
                return
            RemoveProbeRifle()
            AddedSame := AddProbeRifle(Source)
            var RanSame : logic = false
            if (AddedSame?, SameRifle := ProbeRifle?, SameWeapon := SameRifle.GetComponent[fort_trace_weapon_component]):
                set RanSame = RunWallTeamWeaponPhase(Owner, SameWeapon, "same_team_visible")
            if (not RanSame? or not Wall.IsValid[] or CalibrationObjective.GetHealth() <> 5000.0):
                CoachProbeLog("PCL|health_probe|team_wall_not_run|same_team_visible_prerequisite_failed")
                return
            Wall.Hide()
            Sleep(0.25)
            BeforePositive := CalibrationObjective.GetHealth()
            AddedPositive := AddProbeRifle(Source)
            if (AddedPositive?, PositiveRifle := ProbeRifle?, PositiveWeapon := PositiveRifle.GetComponent[fort_trace_weapon_component]):
                RanPositive := RunWallTeamWeaponPhase(Owner, PositiveWeapon, "same_team_hidden_positive")
                if (not RanPositive? or CalibrationObjective.GetHealth() >= BeforePositive or ObjectivePlayerHits < 1):
                    CoachProbeLog("PCL|health_probe|team_wall_not_run|same_team_firing_positive_control_failed")
                    return
            else:
                CoachProbeLog("PCL|health_probe|team_wall_not_run|positive_rifle_unavailable")
                return
            if (not Wall.IsValid[]):
                CoachProbeLog("PCL|health_probe|team_wall_not_run|wall_invalid_after_positive_control")
                return
            Wall.Show()
            Sleep(0.25)
            OtherTeam := AssignWallProbeTeam(Owner, Source, Enemy, "opposing_team_visible")
            if (not OtherTeam?):
                return
            AddedEnemy := AddProbeRifle(Source)
            if (AddedEnemy?, EnemyRifle := ProbeRifle?, EnemyWeapon := EnemyRifle.GetComponent[fort_trace_weapon_component]):
                RanEnemy := RunWallTeamWeaponPhase(Owner, EnemyWeapon, "opposing_team_visible")
                var Invalid : int = 0
                var Ready : int = 0
                if (not Wall.IsValid[]):
                    set Invalid = 1
                if (RanEnemy?):
                    set Ready = 1
                CoachProbeLog("PCL|health_probe|team_wall_trial_finished|opposing_phase_ready={Ready}|wall_invalid={Invalid}|allocations={SpawnedWallGeneration}|observed_invalid={ObservedSpawnedWallDeaths}|not_native_owner_edit_or_slot_acceptance")
            else:
                CoachProbeLog("PCL|health_probe|team_wall_not_run|opposing_rifle_unavailable")
        else:
            CoachProbeLog("PCL|health_probe|team_wall_not_run|wall_or_two_teams_unavailable")

    RunWeaponComparison(Owner : agent)<suspends>:void =
        defer:
            RemoveProbeRifle()
            NativeLeaseRestored := RestoreNativeToolLease()
            if (NativeLeaseRestored?):
                CalibrationShooter.DespawnAll(false)
                CalibrationShooter.Disable()
        CalibrationShooter.Reset()
        CalibrationShooter.Enable()
        CalibrationShooter.Spawn()
        for (Attempt := 0..99):
            if (Ending?):
                return
            if (Agent := Shooter?, Character := Agent.GetFortCharacter[], Character.IsActive[], Body := Character.GetEntity[], Actions := Body.GetComponent[guard_actions_component]):
                Teams := GetPlayspace().GetTeamCollection()
                if (OwnerTeam := Teams.GetTeam[Owner], Teams.IsOnTeam[Agent, OwnerTeam]):
                    CoachProbeLog("PCL|health_probe|weapon_shooter_friendly_team_confirmed")
                else:
                    CoachProbeLog("PCL|health_probe|weapon_not_run|friendly_team_unconfirmed")
                    return
                Character.SetVulnerability(false)
                LogInventoryScope("character", Body)
                LogInventoryScope("agent", Agent)
                if (Character.TeleportTo[vector3{X := -2848.0, Y := -3072.0, Z := 96.0}, MakeRotationFromYawPitchRollDegrees(0.0, 0.0, 0.0)]) {}
                else:
                    CoachProbeLog("PCL|health_probe|weapon_not_run|shooter_placement_failed")
                    return
                Selected := (coach_equipment{}).SelectWeapon(Agent, 1500.0)
                var SelectedFlag : int = 0
                if (Selected?):
                    set SelectedFlag = 1
                CoachProbeLog("PCL|health_probe|initial_ranged_selection|selected={SelectedFlag}|before_template_addition")
                if (NativeBuildToolReference?):
                    RunNativeBuildToolReference(Owner, Agent)
                    if (NativeBuildToolLease?):
                        RunNativeBuildToolLease(Owner, Agent)
                    return
                if (VisualNativeCaptureSeconds > 0.0):
                    CoachProbeLog("PCL|health_probe|npc_native_visual_inventory|ranged_items={CountRangedItems(Agent)}|before_any_custom_item_creation_or_inventory_removal")
                    RunNPCCombatControl(Agent, Actions, ?Viewer := option{Owner})
                    return
                if (NPCEquippedAttackControl?):
                    RunEquippedNPCAttackControl(Agent, Actions)
                    return
                if (UseCharacterTargetControl?):
                    Added := AddProbeRifle(Agent)
                    if (Added?, Rifle := ProbeRifle?, Weapon := Rifle.GetComponent[fort_trace_weapon_component]):
                        CoachProbeLog("PCL|health_probe|player_target_rifle_stats|damage={Weapon.Damage}|fire_rate={Weapon.FireRate}|range={Weapon.MaxRange}|shot_cost={Weapon.ShotAmmoCost}")
                        RunPlayerCharacterTargetControl(Owner, Agent, Weapon)
                    else:
                        CoachProbeLog("PCL|health_probe|player_target_not_run|owned_rifle_unavailable")
                    return
                if (IsolatedWallControl?):
                    Character.PutInStasis(stasis_args{AllowTurning := false, AllowFalling := false})
                    defer:
                        Character.ReleaseFromStasis()
                    if (NativeWallTransitionControl?):
                        CalibrationShooter.Disable()
                        RunNativeWallTransitionPair(Owner, Agent)
                        CoachProbeLog("PCL|health_probe|isolated_wall_finished|objective_health={CalibrationObjective.GetHealth()}|no_direct_damage_called|no_acceptance_gate_changed")
                        return
                    Added := AddProbeRifle(Agent)
                    if (Added?, Rifle := ProbeRifle?, Weapon := Rifle.GetComponent[fort_trace_weapon_component]):
                        CalibrationShooter.Disable()
                        if (SpawnedWallControl?):
                            ControlMonitor.Disable()
                            ControlWall.Hide()
                            Allocated := AllocateControlWall()
                            if (not Allocated?):
                                return
                            Sleep(0.25)
                            LogCalibrationWallState("spawned_initial_settled")
                        CoachProbeLog("PCL|health_probe|isolated_wall_baseline|wall_damage_events={ControlDamageEvents}|wall_destroyed_events={ControlDestroyedEvents}|objective_health={CalibrationObjective.GetHealth()}|no_hostile_spawn_or_NPC_fire")
                        if (ControlDamageEvents <> 0 or ControlDestroyedEvents <> 0 or CalibrationObjective.GetHealth() <> 5000.0):
                            CoachProbeLog("PCL|health_probe|player_control_not_run|wall_baseline_contaminated")
                            return
                        if (NativeTeamWallControl?):
                            RunNativeTeamWallControl(Owner, Agent)
                        else:
                            RunPlayerWeaponControl(Owner, Weapon)
                        if (SpawnedWallControl?):
                            CoachProbeLog("PCL|health_probe|spawned_wall_trial_finished|allocations={SpawnedWallGeneration}|observed_invalid={ObservedSpawnedWallDeaths}|no_native_slot_acceptance")
                        CoachProbeLog("PCL|health_probe|isolated_wall_finished|objective_health={CalibrationObjective.GetHealth()}|no_direct_damage_called|no_acceptance_gate_changed")
                    else:
                        CoachProbeLog("PCL|health_probe|player_control_not_run|isolated_owned_rifle_unavailable")
                    return
                RunNPCCombatControl(Agent, Actions)
                if (not FindProbeWeapon(Agent)?):
                    Added := AddProbeRifle(Agent)
                Sleep(0.5)
                if (Rifle := ProbeRifle?, Weapon := Rifle.GetComponent[fort_trace_weapon_component]):
                    NativeCost := Weapon.ShotAmmoCost
                    defer:
                        if (Current := ProbeRifle?, Current = Rifle):
                            Weapon.SetShotAmmoCost(NativeCost)
                    CoachProbeLog("PCL|health_probe|weapon_ready|health={CalibrationObjective.GetHealth()}|damage={Weapon.Damage}|environment_multiplier={Weapon.EnvironmentalDamageMultiplier}|fire_rate={Weapon.FireRate}|range={Weapon.MaxRange}")
                    Aim := CalibrationObjective.GetTransform().Translation + CalibrationAimOffset
                    race:
                        block:
                            Sleep(0.75)
                            SampleNativeFire(Weapon, Character, "npc_native_cost")
                            Weapon.SetShotAmmoCost(0)
                            SampleNativeFire(Weapon, Character, "npc_zero_cost")
                        block:
                            Focused := Actions.Focus(FromVector3(Aim), ?LockFocus := true)
                            loop:
                                Sleep(0.1)
                    Weapon.SetShotAmmoCost(NativeCost)
                    CalibrationShooter.Disable()
                    RunPlayerWeaponControl(Owner, Weapon)
                    CoachProbeLog("PCL|health_probe|weapon_comparison_finished|objective_health={CalibrationObjective.GetHealth()}|no_direct_damage_called|no_acceptance_gate_changed")
                else:
                    CoachProbeLog("PCL|health_probe|weapon_not_run|equipped_trace_weapon_unavailable")
                return
            Sleep(0.1)
        CoachProbeLog("PCL|health_probe|weapon_not_run|shooter_unavailable")

    LogPosition(Name : string, Object : creative_object):void =
        Position := Object.GetTransform().Translation
        CoachProbeLog("PCL|health_probe|runtime_position|name={Name}|x={Position.X}|y={Position.Y}|z={Position.Z}")

    LogFixturePositions(Stage : string):void =
        if (ControlWall.IsValid[]):
            LogPosition("{Stage}_control_wall", ControlWall)
        if (EditedWall.IsValid[]):
            LogPosition("{Stage}_edited_wall", EditedWall)
        if (PositiveWall.IsValid[]):
            LogPosition("{Stage}_positive_wall", PositiveWall)
        LogPosition("{Stage}_control_blast", ControlBlast)
        LogPosition("{Stage}_edited_blast", EditedBlast)
        LogPosition("{Stage}_positive_blast", PositiveBlast)
        LogPosition("{Stage}_calibration_objective", CalibrationObjective)
        LogPosition("{Stage}_calibration_blast", CalibrationBlast)

    RunAutomaticSequence()<suspends>:void =
        for (Attempt := 0..49):
            if (Ending?):
                return
            for (Player : GetPlayspace().GetPlayers(), Character := Player.GetFortCharacter[], Character.IsActive[]):
                if (UseWeaponCalibration?):
                    RunWeaponComparison(Player)
                else:
                    RunComparison(Player)
                CoachProbeLog("PCL|health_probe|automatic_sequence_finished|results_require_review")
                return
            Sleep(0.2)
        CoachProbeLog("PCL|health_probe|automatic_sequence_not_run|player_unavailable")

    RunComparison(Agent : agent)<suspends>:void =
        defer:
            RestoreTeam()
        if (not ControlWall.IsValid[] or not EditedWall.IsValid[] or not PositiveWall.IsValid[]):
            CoachProbeLog("PCL|health_probe|comparison_not_run|wall_unavailable")
            return
        ControlPosition := ControlWall.GetTransform().Translation
        EditedPosition := EditedWall.GetTransform().Translation
        PositivePosition := PositiveWall.GetTransform().Translation
        LogFixturePositions("initial")
        CoachProbeLog("PCL|health_probe|calibration_initial|health={CalibrationObjective.GetHealth()}|max_health={CalibrationObjective.GetMaxHealth()}")
        Teams := GetPlayspace().GetTeamCollection()
        if (CurrentTeam := Teams.GetTeam[Agent], DesiredTeam := Teams.GetTeams()[0]):
            for (Index -> Existing : Teams.GetTeams(), Existing = CurrentTeam):
                CoachProbeLog("PCL|health_probe|original_instigator_team|zero_based_index={Index}")
            if (CurrentTeam <> DesiredTeam):
                if (Teams.AddToTeam[Agent, DesiredTeam]):
                    set ChangedTeamAgent = option{Agent}
                    set OriginalTeam = option{CurrentTeam}
                    CoachProbeLog("PCL|health_probe|instigator_team_temporarily_set|zero_based_index=0|fixture_targets_team=2")
                else:
                    CoachProbeLog("PCL|health_probe|comparison_not_run|instigator_team_not_set")
                    return
        else:
            CoachProbeLog("PCL|health_probe|comparison_not_run|instigator_team_unavailable")
            return
        var ControlDamageFlag : int = 0
        var EditedDamageFlag : int = 0
        var PositiveDamageFlag : int = 0
        if (ControlWall.CanBeDamaged?):
            set ControlDamageFlag = 1
        if (EditedWall.CanBeDamaged?):
            set EditedDamageFlag = 1
        if (PositiveWall.CanBeDamaged?):
            set PositiveDamageFlag = 1
        CoachProbeLog("PCL|health_probe|damage_flags|control={ControlDamageFlag}|edited={EditedDamageFlag}|positive={PositiveDamageFlag}")
        InitialControlHealth := ReadHealth(ControlWall)
        InitialEditedHealth := ReadHealth(EditedWall)
        InitialPositiveHealth := ReadHealth(PositiveWall)
        CoachProbeLog("PCL|health_probe|initial_health_interface|control={InitialControlHealth}|edited={InitialEditedHealth}|positive={InitialPositiveHealth}")
        if (Root := GetSimulationEntity[]):
            InitialA := Geometry.SampleWall(Root, ControlPosition, 90.0)
            InitialB := Geometry.SampleWall(Root, EditedPosition, 90.0)
            InitialC := Geometry.SampleWall(Root, PositivePosition, 90.0)
            CoachProbeLog("PCL|health_probe|initial|control_cells={InitialA.Occupied}|edited_cells={InitialB.Occupied}|positive_cells={InitialC.Occupied}")
            if (InitialA.Occupied <> 9 or InitialB.Occupied <> 9 or InitialC.Occupied <> 9):
                CoachProbeLog("PCL|health_probe|comparison_not_run|initial_geometry_mismatch")
                return
        else:
            CoachProbeLog("PCL|health_probe|comparison_not_run|query_unavailable")
            return
        var ControlDeathPulse : int = 0
        var EditedDeathPulse : int = 0
        var PositiveDeathPulse : int = 0
        for (Pulse := 1..8):
            if (Ending? or not Agent.GetFortCharacter[].IsActive[]):
                CoachProbeLog("PCL|health_probe|comparison_canceled|owner_inactive")
                return
            # The native reset cooldown starts at the previous explosion.
            # Wait before Reset; waiting afterwards cannot make an early Reset valid.
            Sleep(1.1)
            if (Ending?):
                return
            ControlBlast.Reset()
            EditedBlast.Reset()
            PositiveBlast.Reset()
            # Leave the first calibration explosion in its native initial state.
            # A native-timer run makes no Verse Reset/Explode calls on this source.
            if (not CalibrationNativeTimer? and Pulse > 1):
                CalibrationBlast.Reset()
            Sleep(0.2)
            if (Ending?):
                return
            if (Pulse = 1 or Pulse = 2):
                LogFixturePositions("reset_{Pulse}")
            if (ControlWall.IsValid[]):
                ControlBlast.Explode(Agent)
            if (EditedWall.IsValid[]):
                EditedBlast.Explode(Agent)
            if (PositiveWall.IsValid[]):
                PositiveBlast.Explode(Agent)
            if (not CalibrationNativeTimer?):
                CalibrationBlast.Explode(Agent)
            Sleep(0.25)
            CoachProbeLog("PCL|health_probe|calibration_pulse|index={Pulse}|health={CalibrationObjective.GetHealth()}|blasts={CalibrationBlasts}|damage_events={CalibrationDamageEvents}")
            var ControlValid : int = 0
            var EditedValid : int = 0
            var PositiveValid : int = 0
            var ControlHealth : string = "disposed"
            var EditedHealth : string = "disposed"
            var PositiveHealth : string = "disposed"
            if (ControlWall.IsValid[]):
                set ControlValid = 1
                set ControlHealth = ReadHealth(ControlWall)
            else if (ControlDeathPulse = 0):
                set ControlDeathPulse = Pulse
            if (EditedWall.IsValid[]):
                set EditedValid = 1
                set EditedHealth = ReadHealth(EditedWall)
            else if (EditedDeathPulse = 0):
                set EditedDeathPulse = Pulse
            if (PositiveWall.IsValid[]):
                set PositiveValid = 1
                set PositiveHealth = ReadHealth(PositiveWall)
            else if (PositiveDeathPulse = 0):
                set PositiveDeathPulse = Pulse
            CoachProbeLog("PCL|health_probe|pulse|index={Pulse}|control_valid={ControlValid}|edited_valid={EditedValid}|positive_valid={PositiveValid}|control_blasts={ControlBlasts}|edited_blasts={EditedBlasts}|positive_blasts={PositiveBlasts}|control_damage_events={ControlDamageEvents}|edited_damage_events={EditedDamageEvents}|positive_damage_events={PositiveDamageEvents}|control_destroyed_events={ControlDestroyedEvents}|edited_destroyed_events={EditedDestroyedEvents}|positive_destroyed_events={PositiveDestroyedEvents}")
            CoachProbeLog("PCL|health_probe|health_interface|pulse={Pulse}|control={ControlHealth}|edited={EditedHealth}|positive={PositiveHealth}")
            if (Root := GetSimulationEntity[]):
                A := Geometry.SampleWall(Root, ControlPosition, 90.0)
                B := Geometry.SampleWall(Root, EditedPosition, 90.0)
                C := Geometry.SampleWall(Root, PositivePosition, 90.0)
                CoachProbeLog("PCL|health_probe|query|pulse={Pulse}|control_cells={A.Occupied}|edited_cells={B.Occupied}|positive_cells={C.Occupied}")
            if (ControlDeathPulse > 0 and EditedDeathPulse > 0 and PositiveDeathPulse > 0):
                CoachProbeLog("PCL|health_probe|destruction_comparison|control_pulse={ControlDeathPulse}|edited_pulse={EditedDeathPulse}|positive_pulse={PositiveDeathPulse}|no_acceptance_gate_changed")
                return
            if (EditedWall.IsValid[]):
                if (Pulse = 1):
                    EditedWall.SetMesh(Structures.WallWindowMesh)
                    CoachProbeLog("PCL|health_probe|mesh_requested|after_pulse=1|shape=window|same_reference")
                else if (Pulse = 2):
                    EditedWall.SetMesh(Structures.WallExitMesh)
                    CoachProbeLog("PCL|health_probe|mesh_requested|after_pulse=2|shape=passage|same_reference")
                else if (Pulse = 3):
                    EditedWall.SetMesh(Structures.WallSolidMesh)
                    CoachProbeLog("PCL|health_probe|mesh_requested|after_pulse=3|shape=solid|same_reference")
        CoachProbeLog("PCL|health_probe|comparison_bounded|control_pulse={ControlDeathPulse}|edited_pulse={EditedDeathPulse}|positive_pulse={PositiveDeathPulse}|eight_pulses_only|no_acceptance_gate_changed")
        BeforeDirect := CalibrationObjective.GetHealth()
        CalibrationObjective.Damage(7.0)
        Sleep(0.25)
        CoachProbeLog("PCL|health_probe|calibration_direct_damage|before={BeforeDirect}|after={CalibrationObjective.GetHealth()}|requested=7|not_wall_health_evidence")

coach_tool_transition_trace := class:
    Equipment : coach_equipment
    Weapon : fort_trace_weapon_component
    Cycle : int

    OnPlanEquipped(Change : change_equipped_result):void =
        if (Change.IsItemEquipped?):
            Record("plan_equipped_event_1")
        else:
            Record("plan_equipped_event_0")

    OnRifleEquipped(Change : change_equipped_result):void =
        if (Change.IsItemEquipped?):
            Record("rifle_equipped_event_1")
        else:
            Record("rifle_equipped_event_0")

    OnPlanHolster(Empty : tuple()):void =
        Record("plan_holster_event")

    OnRifleHolster(Empty : tuple()):void =
        Record("rifle_holster_event")

    Record(Reason : string):void =
        var PlanEquipped : int = -1
        var PlanHolstered : int = -1
        var RifleEquipped : int = -1
        var RifleHolstered : int = 0
        var RifleFiring : int = 0
        var ParentMatches : int = -1
        if (Plan := Equipment.BuildPlan?, Item := Plan.GetComponent[item_component]):
            set PlanEquipped = 0
            if (Item.IsEquipped[]):
                set PlanEquipped = 1
            if (Lock := Equipment.BuildPlanLock?, Expected := Lock.OwnerInventory?):
                set ParentMatches = 0
                if (Item.GetParentInventory[] = Expected):
                    set ParentMatches = 1
            if (BaseWeapon := Plan.GetComponent[fort_weapon_component]):
                set PlanHolstered = 0
                if (BaseWeapon.IsHolstered?):
                    set PlanHolstered = 1
        if (Item := Weapon.Entity.GetComponent[item_component]):
            set RifleEquipped = 0
            if (Item.IsEquipped[]):
                set RifleEquipped = 1
        if (Weapon.IsHolstered?):
            set RifleHolstered = 1
        if (Weapon.IsFiring[]):
            set RifleFiring = 1
        CoachProbeLog("PCL|health_probe|npc_tool_transition|cycle={Cycle}|reason={Reason}|time={GetSimulationElapsedTime()}|plan_equipped={PlanEquipped}|plan_holstered={PlanHolstered}|rifle_equipped={RifleEquipped}|rifle_holstered={RifleHolstered}|rifle_firing={RifleFiring}|plan_parent_matches_lock={ParentMatches}|callback_or_poll_not_rendered_pose")

coach_native_tool_phase_trace := class:
    Tool : item_component
    Destination : inventory_component
    Source : inventory_component
    GuardEquipped : []item_component
    GuardSubject : agent
    OriginalRanged : []item_component
    var Phase : string = "lease_setup"

    Mark(Name : string):void =
        set Phase = Name
        Record("phase")

    OnEquipped(Change : change_equipped_result):void =
        var PayloadEquipped : int = 0
        if (Change.IsItemEquipped?):
            set PayloadEquipped = 1
        CoachProbeLog("PCL|health_probe|native_tool_phase_equipped_event|phase={Phase}|payload_equipped={PayloadEquipped}|time={GetSimulationElapsedTime()}")
        Record("equipment_event")

    Record(Reason : string):void =
        var CurrentItems : int = 0
        var CurrentRanged : int = 0
        var CurrentEquipped : int = 0
        var NewRanged : int = 0
        var OriginalRangedInGuard : int = 0
        for (Inventory : GuardSubject.FindDescendantComponents(inventory_component), Value : Inventory.GetItems(), Item := Value.GetComponent[item_component]):
            set CurrentItems += 1
            var IsRanged : int = 0
            var IsOriginal : int = 0
            var IsEquipped : int = 0
            for (Category : Item.Categories, Category = FortniteItemCategories.WeaponRanged):
                set IsRanged = 1
            for (Original : OriginalRanged, Original = Item):
                set IsOriginal = 1
            if (Item.IsEquipped[]):
                set IsEquipped = 1
                set CurrentEquipped += 1
            if (IsRanged = 1):
                set CurrentRanged += 1
                if (IsOriginal = 1):
                    set OriginalRangedInGuard += 1
                else:
                    set NewRanged += 1
            if (IsRanged = 1 or IsEquipped = 1):
                var Holstered : int = -1
                if (Weapon := Value.GetComponent[fort_weapon_component]):
                    set Holstered = 0
                    if (Weapon.IsHolstered?):
                        set Holstered = 1
                CoachProbeLog("PCL|health_probe|native_tool_guard_item_detail|phase={Phase}|reason={Reason}|item_index={CurrentItems}|ranged={IsRanged}|known_original_ranged={IsOriginal}|equipped={IsEquipped}|weapon_holstered={Holstered}|read_only")
        CoachProbeLog("PCL|health_probe|native_tool_guard_inventory_current|phase={Phase}|reason={Reason}|items={CurrentItems}|ranged={CurrentRanged}|new_ranged={NewRanged}|original_ranged_in_guard={OriginalRangedInGuard}|equipped={CurrentEquipped}|read_only")
        var Equipped : int = 0
        var ParentMatches : int = 0
        var OriginalGuardEquipped : int = 0
        if (Tool.IsEquipped[]):
            set Equipped = 1
        if (Tool.GetParentInventory[] = Destination):
            set ParentMatches = 1
        for (Previous : GuardEquipped, Previous.IsEquipped[]):
            set OriginalGuardEquipped += 1
        CoachProbeLog("PCL|health_probe|native_tool_phase_state|phase={Phase}|reason={Reason}|equipped={Equipped}|parent_matches={ParentMatches}|original_guard_equipped_now={OriginalGuardEquipped}|source_count={Source.GetItems().Length}|destination_count={Destination.GetItems().Length}|time={GetSimulationElapsedTime()}|read_only")

coach_native_build_tool_lease := class:
    Source : inventory_component
    Tool : item_component
    Container : entity
    Destination : fort_inventory_build_hotbar_component
    GuardEquipped : []item_component
    SourceCount : int
    var Closed : logic = false
    var TransferAttempted : logic = false
    var QueryGuards : []coach_tool_hold_component = array{}
    var ParkingContainer : ?entity = false
    var ParkingInventory : ?inventory_component = false
    var ParkedRanged : []tuple(item_component, inventory_component) = array{}

    ObserveParkingState(Phase : string):void =
        var ParentMatches : int = 0
        var Equipped : int = 0
        if (Inventory := ParkingInventory?):
            for (Pair : ParkedRanged):
                if (Pair(0).GetParentInventory[] = Inventory):
                    set ParentMatches += 1
                if (Pair(0).IsEquipped[]):
                    set Equipped += 1
            CoachProbeLog("PCL|health_probe|native_tool_ranged_parking_status|phase={Phase}|tracked={ParkedRanged.Length}|parent_matches={ParentMatches}|equipped={Equipped}|parking_count={Inventory.GetItems().Length}|no_inventory_mutation")

    ParkNativeRanged(Attacker : agent, Items : []item_component):logic =
        if (ParkingContainer? or ParkedRanged.Length > 0 or Items.Length = 0):
            return false
        if (Root := Attacker.GetSimulationEntity[]):
            Parking := entity{}
            Inventory := inventory_component{Entity := Parking}
            Parking.AddComponents(array{Inventory})
            set ParkingContainer = option{Parking}
            set ParkingInventory = option{Inventory}
            Root.AddEntities(array{Parking})
            for (Item : Items):
                if (Original := Item.GetParentInventory[], not Item.IsEquipped[]):
                    var OriginalUnderGuard : logic = false
                    for (Owned : Attacker.FindDescendantComponents(inventory_component), Owned = Original):
                        set OriginalUnderGuard = true
                    if (not OriginalUnderGuard?):
                        return false
                    CanRemove := Original.CanRemoveItem(Item.Entity)
                    CanAdd := Inventory.CanAddItem(Item.Entity, ?AllowMergeItems := false)
                    if (not CanRemove.GetSuccess[] or not CanAdd.GetSuccess[]):
                        return false
                    # Track before mutation so every partial-transfer path can restore.
                    set ParkedRanged += array{(Item, Original)}
                    Removed := Original.RemoveItem(Item.Entity)
                    if (not Removed.GetSuccess[]):
                        CoachProbeLog("PCL|health_probe|native_tool_ranged_explicit_remove_rejected")
                        return false
                    if (Item.GetParentInventory[] = Original):
                        CoachProbeLog("PCL|health_probe|native_tool_ranged_explicit_remove_parent_uncleared")
                        return false
                    CoachProbeLog("PCL|health_probe|native_tool_ranged_explicit_remove|index={ParkedRanged.Length}|success=1|original_parent_cleared=1|before_parking_add")
                    Added := Inventory.AddItem(Item.Entity, ?AllowMergeItems := false)
                    if (not Added.GetSuccess[] or not Item.GetParentInventory[] = Inventory):
                        return false
                else:
                    return false
            var StillUnderGuard : int = 0
            for (Owned : Attacker.FindDescendantComponents(inventory_component), Owned = Inventory):
                set StillUnderGuard += 1
            CoachProbeLog("PCL|health_probe|native_tool_ranged_parked|same_items={ParkedRanged.Length}|parking_count={Inventory.GetItems().Length}|parking_in_guard_hierarchy={StillUnderGuard}|outside_guard_inventory|no_item_deleted_or_copied")
            if (StillUnderGuard <> 0 or Inventory.GetItems().Length <> Items.Length):
                return false
            return true
        return false

    RestoreParkedRanged():logic =
        Before := ParkedRanged.Length
        var Pending : []tuple(item_component, inventory_component) = array{}
        for (Pair : ParkedRanged):
            if (not Pair(0).GetParentInventory[] = Pair(1)):
                Returned := Pair(1).AddItem(Pair(0).Entity, ?AllowMergeItems := false)
                if (not Returned.GetSuccess[]):
                    set Pending += array{Pair}
                else if (not Pair(0).GetParentInventory[] = Pair(1)):
                    set Pending += array{Pair}
        set ParkedRanged = Pending
        if (Pending.Length > 0):
            CoachProbeLog("PCL|health_probe|native_tool_ranged_return_pending|remaining={Pending.Length}|npc_retained")
            return false
        if (Inventory := ParkingInventory?, Inventory.GetItems().Length <> 0):
            return false
        if (Parking := ParkingContainer?):
            Parking.RemoveFromParent()
            set ParkingContainer = false
            set ParkingInventory = false
            CoachProbeLog("PCL|health_probe|native_tool_ranged_restored|same_items={Before}|parking_empty=1|parking_removed=1|remaining=0")
        return true

    LockNativeTool(Attacker : agent, GuardRanged : []item_component):logic =
        if (QueryGuards.Length > 0 or not Tool.GetParentInventory[] = Destination):
            return false
        for (Item : array{Tool} + GuardRanged, Item.Entity.GetComponent[coach_tool_hold_component]):
            return false
        ToolGuard := coach_tool_hold_component{Entity := Tool.Entity, Locked := true, OwnerInventory := option{Destination}}
        set QueryGuards += array{ToolGuard}
        Tool.Entity.AddComponents(array{ToolGuard})
        for (Item : GuardRanged):
            GearGuard := coach_tool_hold_component{Entity := Item.Entity, Locked := true, BlockEquip := true, NPCOwner := option{Attacker}}
            set QueryGuards += array{GearGuard}
            Item.Entity.AddComponents(array{GearGuard})
        CoachProbeLog("PCL|health_probe|native_tool_query_guards_installed|count={QueryGuards.Length}|tool=1|ranged={GuardRanged.Length}|public_inventory_query_veto|no_repeated_equip")
        return true

    ReleaseQueryGuards():logic =
        if (QueryGuards.Length = 0):
            return true
        var Vetoes : int = 0
        var EquipQueries : int = 0
        for (Gate : QueryGuards):
            set Gate.Locked = false
            set Vetoes += Gate.VetoCount
            set EquipQueries += Gate.EquipQueries
            Gate.RemoveFromEntity()
        var Remaining : int = 0
        for (Gate : QueryGuards, Current := Gate.Entity.GetComponent[coach_tool_hold_component], Current = Gate):
            set Remaining += 1
        CoachProbeLog("PCL|health_probe|native_tool_query_guards_released|count={QueryGuards.Length}|remaining={Remaining}|vetoes={Vetoes}|equip_queries={EquipQueries}|before_native_item_return")
        if (Remaining <> 0):
            return false
        set QueryGuards = array{}
        return true

    Restore():logic =
        GuardsRemoved := ReleaseQueryGuards()
        if (not GuardsRemoved?):
            return false
        if (Closed?):
            return true
        if (TransferAttempted? or not Tool.GetParentInventory[] = Source):
            if (Tool.IsEquipped[]):
                Released := Tool.Unequip()
                if (not Released.GetSuccess[]):
                    return false
        if (not Tool.GetParentInventory[] = Source):
            Returned := Source.AddItem(Tool.Entity, ?AllowMergeItems := false)
            if (not Returned.GetSuccess[]):
                return false
        if (not Tool.GetParentInventory[] = Source or Source.GetItems().Length <> SourceCount):
            return false
        GearRestored := RestoreParkedRanged()
        if (not GearRestored?):
            return false
        for (Previous : GuardEquipped, not Previous.IsEquipped[]):
            Equipped := Previous.Equip()
            if (not Equipped.GetSuccess[]):
                return false
        if (Destination.GetItems().Length <> 0):
            return false
        Container.RemoveFromParent()
        set Closed = true
        CoachProbeLog("PCL|health_probe|native_tool_lease_restored|same_item_source_parent=1|source_count={Source.GetItems().Length}|temporary_inventory_empty_remove_requested=1|original_guard_equipment_restored=1")
        return true

CoachCaptureNativeItemSelection(Owner : agent)<transacts>:[]tuple(item_component, inventory_component, int) =
    var Snapshot : []tuple(item_component, inventory_component, int) = array{}
    for (Inventory : Owner.FindDescendantComponents(inventory_component), Value : Inventory.GetItems(), Item := Value.GetComponent[item_component]):
        var Known : logic = false
        for (Entry : Snapshot, Entry(0) = Item):
            set Known = true
        if (not Known?):
            var Equipped : int = 0
            if (Item.IsEquipped[]):
                set Equipped = 1
            set Snapshot += array{(Item, Inventory, Equipped)}
    return Snapshot

CoachRestoreNativeItemSelection(Snapshot : []tuple(item_component, inventory_component, int)):int =
    for (Entry : Snapshot, Entry(2) = 0, Entry(0).IsEquipped[]):
        Result := Entry(0).Unequip()
    for (Entry : Snapshot, Entry(2) = 1, not Entry(0).IsEquipped[]):
        Result := Entry(0).Equip()
    var Matching : int = 0
    for (Entry : Snapshot, Entry(0).GetParentInventory[] = Entry(1)):
        var Equipped : int = 0
        if (Entry(0).IsEquipped[]):
            set Equipped = 1
        if (Equipped = Entry(2)):
            set Matching += 1
    return Matching

CoachNativeItemActionAudit(Item : item_component, Owner : string, Kind : string, Index : int, Phase : string):void =
    var DirectWeapon : int = 0
    var DescendantWeapons : int = 0
    var DirectTrace : int = 0
    var DescendantTrace : int = 0
    var DirectAbility : int = 0
    var DescendantAbilities : int = 0
    var InventoryAbilities : int = 0
    var EquippedAbilities : int = 0
    var AbilityComponents : []fort_item_ability_component = array{}
    if (Item.Entity.GetComponent[fort_weapon_component]):
        set DirectWeapon = 1
    for (Component : Item.Entity.FindDescendantComponents(fort_weapon_component)):
        set DescendantWeapons += 1
    if (Item.Entity.GetComponent[fort_trace_weapon_component]):
        set DirectTrace = 1
    for (Component : Item.Entity.FindDescendantComponents(fort_trace_weapon_component)):
        set DescendantTrace += 1
    if (Component := Item.Entity.GetComponent[fort_item_ability_component]):
        set DirectAbility = 1
        set AbilityComponents += array{Component}
    for (Component : Item.Entity.FindDescendantComponents(fort_item_ability_component)):
        set DescendantAbilities += 1
        var Known : logic = false
        for (Existing : AbilityComponents, Existing = Component):
            set Known = true
        if (not Known?):
            set AbilityComponents += array{Component}
    for (Component : AbilityComponents):
        for (Ability : Component.ItemAbilities, Ability?):
            set InventoryAbilities += 1
        for (Ability : Component.ItemEquippedAbilities, Ability?):
            set EquippedAbilities += 1
    CoachProbeLog("PCL|health_probe|participant_item_action_surface|owner={Owner}|kind={Kind}|index={Index}|phase={Phase}|weapon_direct={DirectWeapon}|weapon_descendants={DescendantWeapons}|trace_direct={DirectTrace}|trace_descendants={DescendantTrace}|ability_direct={DirectAbility}|ability_descendants={DescendantAbilities}|inventory_abilities={InventoryAbilities}|equipped_abilities={EquippedAbilities}|public_components_only|not_internal_GAS_or_native_item_action_inventory")

CoachNativeBuildAbilityAudit(Tool : item_component, Phase : string):void =
    var Components : []fort_item_ability_component = array{}
    if (Direct := Tool.Entity.GetComponent[fort_item_ability_component]):
        set Components += array{Direct}
    for (Value : Tool.Entity.FindDescendantComponents(fort_item_ability_component)):
        var Known : logic = false
        for (Existing : Components, Existing = Value):
            set Known = true
        if (not Known?):
            set Components += array{Value}
    var InventoryAbilities : int = 0
    var EquippedAbilities : int = 0
    for (Value : Components):
        for (Slot : Value.ItemAbilities, Slot?):
            set InventoryAbilities += 1
        for (Slot : Value.ItemEquippedAbilities, Slot?):
            set EquippedAbilities += 1
    CoachProbeLog("PCL|health_probe|native_build_tool_public_abilities|phase={Phase}|components={Components.Length}|inventory_abilities={InventoryAbilities}|equipped_abilities={EquippedAbilities}|read_only|not_internal_GAS_inventory")

CoachNativeResourceCounts(Owner : agent)<transacts>:tuple(int, int, int) =
    var Items : int = 0
    var Known : int = 0
    var Total : int = 0
    for (Inventory : Owner.FindDescendantComponents(inventory_component), Value : Inventory.GetItems(), Item := Value.GetComponent[item_component], Category : Item.Categories, Category = FortniteItemCategories.Resource):
        set Items += 1
        if (Stack := Value.GetComponent[stackable_component]):
            set Known += 1
            set Total += Stack.StackSize
    return (Items, Known, Total)

CoachNativeStructureBodies(Root : entity, Center : vector3, AttackerBody : entity, TargetBody : entity)<transacts>:[]entity =
    Shape := collision_box{Extents := FromVector3(vector3{X := 1024.0, Y := 1024.0, Z := 768.0}), CollisionProfile := collision_profile{Channel := CollisionChannels.dynamic{}, GetChannelInteraction := CoachStructureInteraction}}
    Pose := FromTransform(transform{Translation := Center + vector3{Z := 512.0}})
    var Bodies : []entity = array{}
    for (Hit : Root.FindOverlapHits(Pose, Shape)):
        Value := Hit.TargetComponent.Entity
        var Ignore : logic = false
        if (Value = AttackerBody or Value = TargetBody):
            set Ignore = true
        for (Ancestor : Value.FindAncestorEntities(entity), Ancestor = AttackerBody or Ancestor = TargetBody):
            set Ignore = true
        for (Existing : Bodies, Existing = Value):
            set Ignore = true
        if (not Ignore?):
            set Bodies += array{Value}
    return Bodies

coach_participant_probe_behavior := class(npc_behavior):
    OnBegin<override>()<suspends>:void =
        if (Owner := GetAgent[], Character := Owner.GetFortCharacter[], Character.IsActive[]):
            CoachProbeLog("PCL|health_probe|participant_behavior_started|native_npc_behavior_context|no_equipment_or_action_commands")
        loop:
            Sleep(0.5)

    OnEnd<override>():void =
        CoachProbeLog("PCL|health_probe|participant_behavior_ended")

coach_native_build_attack_observation := class:
    Root : entity
    Center : vector3
    AttackerBody : entity
    TargetBody : entity
    Baseline : []entity
    Target : fort_character
    Attacker : agent
    Tool : item_component
    Destination : inventory_component
    Camera : gameplay_camera_fixed_point_device
    var ObservedNewBodies : []entity = array{}

    AfterCameraRestore():void =
        Current := CoachNativeStructureBodies(Root, Center, AttackerBody, TargetBody)
        var Present : int = 0
        for (Value : ObservedNewBodies, Existing : Current, Value = Existing):
            set Present += 1
        CoachProbeLog("PCL|health_probe|native_build_attack_after_camera_restore|bodies={Current.Length}|tracked_new_candidates={ObservedNewBodies.Length}|tracked_candidates_still_in_volume={Present}|read_only|existing_camera_restore_not_new_mutation")

    Sample(Tick : int, DamageEvents : int, SourceHits : int):void =
        Current := CoachNativeStructureBodies(Root, Center, AttackerBody, TargetBody)
        var Added : int = 0
        for (Value : Current):
            var Known : logic = false
            for (Existing : Baseline, Existing = Value):
                set Known = true
            if (not Known?):
                set Added += 1
                var CandidateID : int = 0
                for (Index -> Existing : ObservedNewBodies, Existing = Value):
                    set CandidateID = Index + 1
                if (CandidateID = 0):
                    set ObservedNewBodies += array{Value}
                    set CandidateID = ObservedNewBodies.Length
                Position := FromTransform(Value.GetGlobalTransform()).Translation
                CameraPosition := Camera.GetTransform().Translation
                var SourcePosition : vector3 = Center
                if (Character := Attacker.GetFortCharacter[]):
                    set SourcePosition = Character.GetTransform().Translation
                TargetPosition := Target.GetTransform().Translation
                var HasMesh : int = 0
                var HasItem : int = 0
                var HasInventory : int = 0
                var HasNPCActions : int = 0
                var AncestorNPCActions : int = 0
                if (Value.GetComponent[mesh_component]):
                    set HasMesh = 1
                if (Value.GetComponent[item_component]):
                    set HasItem = 1
                if (Value.GetComponent[inventory_component]):
                    set HasInventory = 1
                if (Value.GetComponent[npc_actions_component]):
                    set HasNPCActions = 1
                for (Ancestor : Value.FindAncestorEntities(entity), Ancestor.GetComponent[npc_actions_component]):
                    set AncestorNPCActions = 1
                CoachProbeLog("PCL|health_probe|native_build_attack_candidate|tick={Tick}|candidate={CandidateID}|x={Position.X}|y={Position.Y}|z={Position.Z}|camera_distance={Distance(Position, CameraPosition)}|attacker_distance={Distance(Position, SourcePosition)}|target_distance={Distance(Position, TargetPosition)}|mesh={HasMesh}|item={HasItem}|inventory={HasInventory}|npc_actions={HasNPCActions}|ancestor_npc_actions={AncestorNPCActions}|read_only|native_build_type_unverified")
        var Missing : int = 0
        for (Value : Baseline):
            var Present : logic = false
            for (Existing : Current, Existing = Value):
                set Present = true
            if (not Present?):
                set Missing += 1
        var Equipped : int = 0
        var ParentMatches : int = 0
        if (Tool.IsEquipped[]):
            set Equipped = 1
        if (Tool.GetParentInventory[] = Destination):
            set ParentMatches = 1
        Resources := CoachNativeResourceCounts(Attacker)
        CoachProbeLog("PCL|health_probe|native_build_attack_sample|tick={Tick}|tool_equipped={Equipped}|parent_matches={ParentMatches}|bodies={Current.Length}|new_bodies={Added}|missing_baseline={Missing}|resource_items={Resources(0)}|known_resource_stacks={Resources(1)}|resource_total={Resources(2)}|target_health={Target.GetHealth()}|damage_events={DamageEvents}|source_hits={SourceHits}|bounded_collision_census_not_native_type_or_slot_proof")

coach_tool_probe_request := class:
    Owner : agent
    var Done : logic = false
    var Success : logic = false
    var Canceled : logic = false

coach_damage_shooter_behavior := class(npc_behavior):
    Equipment : coach_equipment = coach_equipment{EnableToolQueryGuards := true, EnableToolIntentReconciliation := true}
    var PendingToolRequest : ?coach_tool_probe_request = false

    OnBegin<override>()<suspends>:void =
        CoachProbeLog("PCL|health_probe|private_behavior_started|owned_equipment_context")
        loop:
            if (Request := PendingToolRequest?, not Request.Done?):
                set PendingToolRequest = false
                if (not Request.Canceled?, Owner := GetAgent[], Owner = Request.Owner):
                    set Request.Success = Equipment.EquipBuildPlan(Owner)
                    var EquippedOK : int = 0
                    if (Request.Success?):
                        set EquippedOK = 1
                    CoachProbeLog("PCL|health_probe|npc_tool_owner_command|agent_match=1|equip_ok={EquippedOK}|from_npc_onbegin_coroutine")
                set Request.Done = true
            Sleep(0.05)

    OnEnd<override>():void =
        if (Request := PendingToolRequest?):
            set Request.Canceled = true
        Equipment.DisposeBuildPlan()
        Cleaned := Equipment.DisposeLoadout()
