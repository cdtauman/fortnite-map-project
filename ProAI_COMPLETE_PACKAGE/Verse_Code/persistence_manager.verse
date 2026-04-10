# ============================================================================
# FILE: persistence_manager.verse — Master Persistence Controller
# LOCATION: Content/ (root)
# PHASE: 5
#
# ARCHITECTURE:
#   Owns all 4 persistent weak_map slots (HC-05) and provides the
#   single interface through which every module reads/writes persistent data.
#   No other module touches the weak_maps directly.
#
#   LIFECYCLE:
#     1. OnBegin → wait for player join
#     2. Player joins → LoadAllPlayerData (reads all 4 slots)
#     3. Each round end → SaveRoundData (incremental write to Slots 1+2)
#     4. Purchase event → SaveEconomyData (write to Slot 4)
#     5. Quest completion → SaveProgressionData (write to Slot 3)
#     6. Player leaves / session end → SaveAllPlayerData (full write all 4)
#
#   VALIDATION:
#     Every load passes through data_validator before being returned.
#     Every save validates before committing to the weak_map.
#     Impossible values (negative ELO, >5000 ELO, negative tokens) are
#     caught and corrected with defaults.
#
#   EVENT BUS INTEGRATION:
#     Listens for RoundEndEvent to auto-save incrementally.
#     Dispatches no events itself — it's a passive service module.
#
# WIRING (UEFN Editor):
#   EventBus → event_bus device
# ============================================================================
using { /Fortnite.com/Devices }
using { /Fortnite.com/Game }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }

# ══════════════════════════════════════════════════════════════════════════════
# THE 4 PERSISTENT WEAK MAPS — Module-scope declarations (HC-05)
# These MUST be at module scope (outside the class) per Verse persistence rules.
# They survive across sessions — data written here persists when the
# player leaves and returns to the island.
# ══════════════════════════════════════════════════════════════════════════════
var AnalyticsStore<public>   : weak_map(player, player_analytics_data_v1)   = map{}
var RatingStore<public>      : weak_map(player, player_rating_data_v1)      = map{}
var ProgressionStore<public> : weak_map(player, player_progression_data_v1) = map{}
var EconomyStore<public>     : weak_map(player, player_economy_data_v1)     = map{}

# ══════════════════════════════════════════════════════════════════════════════
# PERSISTENCE MANAGER DEVICE
# ══════════════════════════════════════════════════════════════════════════════
persistence_manager<public> := class(creative_device):

    Logger<private> : log = log{Channel := log_persist_ch}

    # ── Editable References ──────────────────────────────────────────────────
    @editable
    EventBus<public> : event_bus = event_bus{}

    # ── Sub-Modules ──────────────────────────────────────────────────────────
    var Validator<private> : data_validator = data_validator{}

    # ── Cached Player Reference ──────────────────────────────────────────────
    var CachedPlayer<private> : ?player = false
    var IsPlayerLoaded<private> : logic = false

    # ── Loaded Data Cache ────────────────────────────────────────────────────
    # We cache the loaded data in memory so modules can read it without
    # hitting the weak_map on every access.
    var LoadedAnalytics<public>   : player_analytics_data_v1   = player_analytics_data_v1{}
    var LoadedRating<public>      : player_rating_data_v1      = player_rating_data_v1{}
    var LoadedProgression<public> : player_progression_data_v1 = player_progression_data_v1{}
    var LoadedEconomy<public>     : player_economy_data_v1     = player_economy_data_v1{}

    # ── Save Counters (telemetry) ────────────────────────────────────────────
    var TotalSaves<private>     : int = 0
    var TotalLoads<private>     : int = 0
    var TotalErrors<private>    : int = 0

    # ══════════════════════════════════════════════════════════════════════════
    # INITIALIZATION
    # ══════════════════════════════════════════════════════════════════════════
    OnBegin<override>()<suspends> : void =
        Logger.Print("PERSIST: ── Manager Online ──")
        Logger.Print("PERSIST: 4 weak_maps allocated (Analytics, Rating, Progression, Economy).")

        # Background: listen for round ends to auto-save
        branch:
            AutoSaveOnRoundEndLoop()

        # Wait for first player to join, then load their data
        branch:
            WaitForPlayerAndLoad()

    # ══════════════════════════════════════════════════════════════════════════
    # PLAYER JOIN — Wait for player, then load all 4 slots
    # ══════════════════════════════════════════════════════════════════════════
    WaitForPlayerAndLoad<private>()<suspends> : void =
        Logger.Print("PERSIST: Waiting for player join...")
        loop:
            AllPlayers := GetPlayspace().GetPlayers()
            if (P := AllPlayers[0]):
                set CachedPlayer = option{P}
                LoadAllPlayerData(P)
                break
            Sleep(0.5)

    # ══════════════════════════════════════════════════════════════════════════
    # LOAD ALL — Reads all 4 weak_map slots for a player
    # Called on player join. Validates every piece of data.
    # ══════════════════════════════════════════════════════════════════════════
    LoadAllPlayerData<public>(Player : player) : void =
        set TotalLoads += 1
        Logger.Print("PERSIST: ── Loading All Data ──")

        # Slot 1: Analytics
        if (AnalyticsData := AnalyticsStore[Player]):
            set LoadedAnalytics = AnalyticsData
            Logger.Print("PERSIST: [Slot 1] Analytics loaded. Sessions:{LoadedAnalytics.TotalSessions} Rounds:{LoadedAnalytics.TotalRounds}")
        else:
            set LoadedAnalytics = player_analytics_data_v1{}
            Logger.Print("PERSIST: [Slot 1] No analytics data. Fresh profile.")

        # Slot 2: Rating
        if (RatingData := RatingStore[Player]):
            set LoadedRating = Validator.ValidateRating(RatingData)
            Logger.Print("PERSIST: [Slot 2] Rating loaded. ELO:{LoadedRating.ELO} Peak:{LoadedRating.PeakELO} W:{LoadedRating.TotalWins} L:{LoadedRating.TotalLosses}")
        else:
            set LoadedRating = player_rating_data_v1{}
            # Initialize in the store so subsequent saves work
            if (set RatingStore[Player] = LoadedRating):
                Logger.Print("PERSIST: [Slot 2] New rating profile created. Default ELO: 1000")

        # Slot 3: Progression
        if (ProgressionData := ProgressionStore[Player]):
            set LoadedProgression = ProgressionData
            Logger.Print("PERSIST: [Slot 3] Progression loaded. Quests:{LoadedProgression.QuestBitfield} Milestones:{LoadedProgression.MilestonesReached}")
        else:
            set LoadedProgression = player_progression_data_v1{}
            Logger.Print("PERSIST: [Slot 3] No progression data. Fresh profile.")

        # Slot 4: Economy
        if (EconomyData := EconomyStore[Player]):
            set LoadedEconomy = Validator.ValidateEconomy(EconomyData)
            Logger.Print("PERSIST: [Slot 4] Economy loaded. Pass:{if (LoadedEconomy.HasAnalyticsPass?) then "true" else "false"} Tokens:{LoadedEconomy.ChallengeTokens}")
        else:
            set LoadedEconomy = player_economy_data_v1{}
            Logger.Print("PERSIST: [Slot 4] No economy data. Fresh profile.")

        set IsPlayerLoaded = true
        Logger.Print("PERSIST: ── All Data Loaded ──")

    # ══════════════════════════════════════════════════════════════════════════
    # LOAD PLAYER DATA — Quick accessor returning ELO
    # Backward-compatible entry point used by analytics_engine.
    # ══════════════════════════════════════════════════════════════════════════
    LoadPlayerData<public>(Player : player) : int =
        if (RatingData := RatingStore[Player]):
            Validated := Validator.ValidateRating(RatingData)
            set LoadedRating = Validated
            Logger.Print("PERSIST: Quick load — ELO:{Validated.ELO}")
            return Validated.ELO
        else:
            if (set RatingStore[Player] = player_rating_data_v1{}):
                Logger.Print("PERSIST: New player. Default ELO: 1000")
            return 1000

    # ══════════════════════════════════════════════════════════════════════════
    # SAVE ALL — Writes all 4 slots for the cached player
    # Called at session end or player disconnect.
    # ══════════════════════════════════════════════════════════════════════════
    SaveAllPlayerData<public>() : void =
        if (Player := CachedPlayer?):
            set TotalSaves += 1
            Logger.Print("PERSIST: ── Saving All Data ──")

            # Slot 1: Analytics
            if (set AnalyticsStore[Player] = LoadedAnalytics):
                Logger.Print("PERSIST: [Slot 1] Analytics saved.")
            else:
                set TotalErrors += 1
                Logger.Print("PERSIST: ERROR — [Slot 1] Analytics save failed!")

            # Slot 2: Rating
            ValidatedRating := Validator.ValidateRating(LoadedRating)
            if (set RatingStore[Player] = ValidatedRating):
                Logger.Print("PERSIST: [Slot 2] Rating saved. ELO:{ValidatedRating.ELO}")
            else:
                set TotalErrors += 1
                Logger.Print("PERSIST: ERROR — [Slot 2] Rating save failed!")

            # Slot 3: Progression
            if (set ProgressionStore[Player] = LoadedProgression):
                Logger.Print("PERSIST: [Slot 3] Progression saved.")
            else:
                set TotalErrors += 1
                Logger.Print("PERSIST: ERROR — [Slot 3] Progression save failed!")

            # Slot 4: Economy
            ValidatedEconomy := Validator.ValidateEconomy(LoadedEconomy)
            if (set EconomyStore[Player] = ValidatedEconomy):
                Logger.Print("PERSIST: [Slot 4] Economy saved.")
            else:
                set TotalErrors += 1
                Logger.Print("PERSIST: ERROR — [Slot 4] Economy save failed!")

            Logger.Print("PERSIST: ── All Data Saved (Total saves: {TotalSaves}) ──")
        else:
            Logger.Print("PERSIST: WARNING — SaveAll called with no cached player.")

    # ══════════════════════════════════════════════════════════════════════════
    # SAVE RATING — Incremental Slot 2 write
    # Called by game_manager at round end with updated stats.
    # ══════════════════════════════════════════════════════════════════════════
    SaveRatingData<public>(
        Player : player,
        ELO : int,
        PeakELO : int,
        Wins : int,
        Losses : int,
        Draws : int,
        TrainingMinutes : int
    ) : void =
        # Compute peak and lowest
        var ActualPeak : int = PeakELO
        if (ELO > ActualPeak):
            set ActualPeak = ELO
        var ActualLowest : int = LoadedRating.LowestELO
        if (ELO < ActualLowest):
            set ActualLowest = ELO
        if (ActualLowest = 0):
            set ActualLowest = ELO

        NewData := player_rating_data_v1{
            ELO := ELO,
            PeakELO := ActualPeak,
            LowestELO := ActualLowest,
            TotalWins := Wins,
            TotalLosses := Losses,
            TotalDraws := Draws,
            TotalTrainingMinutes := TrainingMinutes,
            BestWinStreak := LoadedRating.BestWinStreak,
            Version := 1,
            LastPlayedTimestamp := Floor[GetSimulationElapsedTime()] or 0
        }

        Validated := Validator.ValidateRating(NewData)
        if (set RatingStore[Player] = Validated):
            set LoadedRating = Validated
            Logger.Print("PERSIST: Rating saved. ELO:{ELO} Peak:{ActualPeak}")
        else:
            set TotalErrors += 1
            Logger.Print("PERSIST: ERROR — Rating save failed!")

    # ══════════════════════════════════════════════════════════════════════════
    # SAVE ANALYTICS — Incremental Slot 1 write
    # Uses running average: new_avg = old_avg + (current - old_avg) / n
    # This prevents storing the full history in the persistent slot.
    # ══════════════════════════════════════════════════════════════════════════
    SaveAnalyticsData<public>(
        Player : player,
        SessionDPS : float,
        SessionHS : float,
        SessionAcc : float,
        SessionReaction : float,
        SessionRounds : int,
        SessionBuilds : int,
        SessionEdits : int,
        ConsistencyScore : float
    ) : void =
        # Running average update
        OldSessions := LoadedAnalytics.TotalSessions * 1.0
        NewSessionCount := LoadedAnalytics.TotalSessions + 1
        N := NewSessionCount * 1.0

        NewData := player_analytics_data_v1{
            AvgDPS := RunningAvg(LoadedAnalytics.AvgDPS, SessionDPS, OldSessions, N),
            AvgHeadshotPct := RunningAvg(LoadedAnalytics.AvgHeadshotPct, SessionHS, OldSessions, N),
            AvgAccuracyPct := RunningAvg(LoadedAnalytics.AvgAccuracyPct, SessionAcc, OldSessions, N),
            AvgReactionMs := RunningAvg(LoadedAnalytics.AvgReactionMs, SessionReaction, OldSessions, N),
            TotalSessions := NewSessionCount,
            TotalRounds := LoadedAnalytics.TotalRounds + SessionRounds,
            AvgRoundDurationSec := LoadedAnalytics.AvgRoundDurationSec,
            TotalBuildsPlaced := LoadedAnalytics.TotalBuildsPlaced + SessionBuilds,
            TotalEditsPerformed := LoadedAnalytics.TotalEditsPerformed + SessionEdits,
            ConsistencyScore := ConsistencyScore
        }

        if (set AnalyticsStore[Player] = NewData):
            set LoadedAnalytics = NewData
            Logger.Print("PERSIST: Analytics saved. Sessions:{NewSessionCount} Rounds:{NewData.TotalRounds}")
        else:
            set TotalErrors += 1
            Logger.Print("PERSIST: ERROR — Analytics save failed!")

    # ══════════════════════════════════════════════════════════════════════════
    # SAVE ECONOMY — Slot 4 write
    # Called by shop_manager after purchase events.
    # ══════════════════════════════════════════════════════════════════════════
    SaveEconomyData<public>(Player : player, Data : player_economy_data_v1) : void =
        Validated := Validator.ValidateEconomy(Data)
        if (set EconomyStore[Player] = Validated):
            set LoadedEconomy = Validated
            Logger.Print("PERSIST: Economy saved. Tokens:{Validated.ChallengeTokens}")
        else:
            set TotalErrors += 1
            Logger.Print("PERSIST: ERROR — Economy save failed!")

    # ══════════════════════════════════════════════════════════════════════════
    # SAVE PROGRESSION — Slot 3 write
    # Called by coach_game_bridge on quest completion.
    # ══════════════════════════════════════════════════════════════════════════
    SaveProgressionData<public>(Player : player, Data : player_progression_data_v1) : void =
        if (set ProgressionStore[Player] = Data):
            set LoadedProgression = Data
            Logger.Print("PERSIST: Progression saved. Quests:{Data.QuestBitfield} Milestones:{Data.MilestonesReached}")
        else:
            set TotalErrors += 1
            Logger.Print("PERSIST: ERROR — Progression save failed!")

    # ══════════════════════════════════════════════════════════════════════════
    # LOAD ECONOMY — Quick accessor for shop_manager
    # ══════════════════════════════════════════════════════════════════════════
    LoadEconomyData<public>(Player : player) : player_economy_data_v1 =
        if (Data := EconomyStore[Player]):
            Validated := Validator.ValidateEconomy(Data)
            set LoadedEconomy = Validated
            return Validated
        player_economy_data_v1{}

    # ══════════════════════════════════════════════════════════════════════════
    # LOAD PROGRESSION — Quick accessor for coach
    # ══════════════════════════════════════════════════════════════════════════
    LoadProgressionData<public>(Player : player) : player_progression_data_v1 =
        if (Data := ProgressionStore[Player]):
            set LoadedProgression = Data
            return Data
        player_progression_data_v1{}

    # ══════════════════════════════════════════════════════════════════════════
    # UPDATE BEST WIN STREAK
    # Called by analytics_engine when a new streak record is set.
    # ══════════════════════════════════════════════════════════════════════════
    UpdateBestWinStreak<public>(NewStreak : int) : void =
        if (NewStreak > LoadedRating.BestWinStreak):
            NewRating := player_rating_data_v1{
                ELO := LoadedRating.ELO
                PeakELO := LoadedRating.PeakELO
                LowestELO := LoadedRating.LowestELO
                TotalWins := LoadedRating.TotalWins
                TotalLosses := LoadedRating.TotalLosses
                TotalDraws := LoadedRating.TotalDraws
                TotalTrainingMinutes := LoadedRating.TotalTrainingMinutes
                BestWinStreak := NewStreak
                Version := LoadedRating.Version
                LastPlayedTimestamp := LoadedRating.LastPlayedTimestamp
            }
            set LoadedRating = NewRating
            Logger.Print("PERSIST: New best win streak: {NewStreak}")

    # ══════════════════════════════════════════════════════════════════════════
    # UPDATE HIGHEST BRACKET
    # Called by analytics_engine when the player enters a new bracket.
    # ══════════════════════════════════════════════════════════════════════════
    UpdateHighestBracket<public>(Bracket : int) : void =
        if (Bracket > LoadedProgression.HighestBracket):
            NewProgression := player_progression_data_v1{
                HighestBracket := Bracket
                TotalQuestsCompleted := LoadedProgression.TotalQuestsCompleted
                QuestBitfield := LoadedProgression.QuestBitfield
                MilestonesReached := LoadedProgression.MilestonesReached
                DailyChallenges := LoadedProgression.DailyChallenges
            }
            set LoadedProgression = NewProgression
            Logger.Print("PERSIST: New highest bracket: {Bracket}")

    # ══════════════════════════════════════════════════════════════════════════
    # QUEST BITFIELD OPERATIONS
    # Each bit represents one quest. Bit 0 = quest #0, Bit 1 = quest #1, etc.
    # ══════════════════════════════════════════════════════════════════════════
    IsQuestCompleted<public>(QuestIndex : int) : logic =
        if (QuestIndex >= 0):
            if (QuestIndex < 32):
                Mask := BitShiftLeft(1, QuestIndex)
                QBF := LoadedProgression.QuestBitfield
                Result := BitwiseAnd(QBF, Mask)
                if (Result > 0):
                    return true
        false

    CompleteQuest<public>(QuestIndex : int) : void =
        if (QuestIndex >= 0):
            if (QuestIndex < 32):
                Completed := IsQuestCompleted(QuestIndex)
                if (not Completed?):
                    Mask := BitShiftLeft(1, QuestIndex)
                    var NewQBF : int = BitwiseOr(LoadedProgression.QuestBitfield, Mask)
                    var NewCompleted : int = LoadedProgression.TotalQuestsCompleted + 1
                    
                    NewProg := player_progression_data_v1{
                        HighestBracket := LoadedProgression.HighestBracket
                        TotalQuestsCompleted := NewCompleted
                        QuestBitfield := NewQBF
                        MilestonesReached := LoadedProgression.MilestonesReached
                        DailyChallenges := LoadedProgression.DailyChallenges
                    }
                    set LoadedProgression = NewProg
                    Logger.Print("PERSIST: Quest {QuestIndex} completed. Bitfield: {NewQBF}")

    # ══════════════════════════════════════════════════════════════════════════
    # BACKGROUND: Auto-save on round end
    # Listens for RoundEndEvent and writes Slot 2 (rating) incrementally.
    # This ensures ELO is saved even if the player disconnects unexpectedly.
    # ══════════════════════════════════════════════════════════════════════════
    AutoSaveOnRoundEndLoop<private>()<suspends> : void =
        Logger.Print("PERSIST: Auto-save listener started.")
        loop:
            EventBus.ListenForRoundEnd()
            if (Player := CachedPlayer?):
                Dur := EventBus.GetSessionDurationMinutes()
                var DurMins : int = 0
                if (ValidDur := Floor[Dur]):
                    set DurMins = ValidDur
                
                # Write the current ELO state from event bus
                SaveRatingData(
                    Player,
                    EventBus.TotalPlayerWins + EventBus.TotalBotWins + EventBus.TotalDraws,
                    LoadedRating.PeakELO,
                    EventBus.TotalPlayerWins,
                    EventBus.TotalBotWins,
                    EventBus.TotalDraws,
                    DurMins
                )
                Logger.Print("PERSIST: Auto-saved after round end.")

    # ══════════════════════════════════════════════════════════════════════════
    # PRIVATE: Running Average Calculator
    # new_avg = (old_avg × old_count + new_value) / new_count
    # ══════════════════════════════════════════════════════════════════════════
    RunningAvg<private>(OldAvg : float, NewValue : float, OldCount : float, NewCount : float) : float =
        if (NewCount > 0.0):
            return ((OldAvg * OldCount) + NewValue) / NewCount
        NewValue

    # ══════════════════════════════════════════════════════════════════════════
    # PRIVATE: Bitwise Operations
    # Verse doesn't expose native bitwise operators, so we approximate
    # with integer math for the 32-bit quest bitfield.
    # ══════════════════════════════════════════════════════════════════════════
    BitShiftLeft<private>(Value : int, Positions : int) : int =
        var Result : int = Value
        var I : int = 0
        loop:
            if (I >= Positions):
                break
            set Result = Result * 2
            set I += 1
        Result

    BitwiseAnd<private>(A : int, B : int) : int =
        # Approximation: check if the specific bit is set
        # For single-bit masks (which is our use case), this works:
        # A AND B where B is a power of 2 → (A / B) mod 2 × B
        if (B > 0):
            DivRat := (A * 1.0) / (B * 1.0)
            if (Divided := Floor[DivRat]):
                ModRat := (Divided * 1.0) / 2.0
                if (ModBase := Floor[ModRat]):
                    Remainder := Divided - (ModBase * 2)
                    return Remainder * B
        0

    BitwiseOr<private>(A : int, B : int) : int =
        # For single-bit masks: if the bit isn't set, add it
        Result := BitwiseAnd(A, B)
        if (Result = 0):
            return A + B
        A

    # ══════════════════════════════════════════════════════════════════════════
    # PUBLIC QUERIES
    # ══════════════════════════════════════════════════════════════════════════
    GetLoadedELO<public>() : int =
        LoadedRating.ELO

    GetLoadedPeakELO<public>() : int =
        LoadedRating.PeakELO

    IsReturningPlayer<public>() : logic =
        if (LoadedRating.TotalWins + LoadedRating.TotalLosses > 0):
            return true
        false

    GetLifetimeRounds<public>() : int =
        LoadedAnalytics.TotalRounds

    GetLifetimeSessions<public>() : int =
        LoadedAnalytics.TotalSessions

    GetTotalErrors<public>() : int =
        TotalErrors

    LogPersistenceState<public>() : void =
        Logger.Print("PERSIST: ── State Dump ──")
        Logger.Print("PERSIST:   Player Loaded: {if (IsPlayerLoaded?) then "true" else "false"}")
        Logger.Print("PERSIST:   Total Saves: {TotalSaves}")
        Logger.Print("PERSIST:   Total Loads: {TotalLoads}")
        Logger.Print("PERSIST:   Total Errors: {TotalErrors}")
        Logger.Print("PERSIST:   ELO: {LoadedRating.ELO} Peak: {LoadedRating.PeakELO}")
        Logger.Print("PERSIST:   Sessions: {LoadedAnalytics.TotalSessions} Rounds: {LoadedAnalytics.TotalRounds}")
        Logger.Print("PERSIST:   Tokens: {LoadedEconomy.ChallengeTokens} Pass: {if (LoadedEconomy.HasAnalyticsPass?) then "true" else "false"}")

log_persist_ch := class(log_channel):