using { /Verse.org/Simulation }

# Edit-course leaderboard (spec v1 step 2.4). UEFN has no first-party cross-server
# leaderboard and Verse cannot read player display names, so the board ranks the saved
# personal bests of everyone currently on the island and marks the viewer's own row.

CoachCourseBest(Profile : coach_profile, Kind : int)<transacts>:float =
    if (Kind = 0):
        return Profile.BestWallRoute
    if (Kind = 1):
        return Profile.BestTripleRoute
    Profile.BestChainRoute

CoachCourseTitle(Kind : int, Hebrew : logic)<transacts>:string =
    if (Kind = 0):
        return CoachPick("Five-wall precision", "דיוק בחמישה קירות", Hebrew)
    if (Kind = 1):
        return CoachPick("Floor, cone and wall", "רצפה, גג וקיר", Hebrew)
    CoachPick("Linked triple edits", "טריפלים רצופים", Hebrew)

# Ascending insertion sort; boards hold at most one entry per player on the island.
CoachSortTimes(Times : []float)<transacts>:[]float =
    var Sorted : []float = array{}
    for (Value : Times):
        var Next : []float = array{}
        var Placed : logic = false
        for (Existing : Sorted):
            if (not Placed? and Value < Existing):
                set Next += array{Value}
                set Placed = true
            set Next += array{Existing}
        if (not Placed?):
            set Next += array{Value}
        set Sorted = Next
    Sorted

# Builds one course section: top five times and the viewer's own rank.
CoachLeaderboardSection(Kind : int, Mine : float, Others : []float, Hebrew : logic):string =
    Title := CoachCourseTitle(Kind, Hebrew)
    var All : []float = Others
    if (Mine > 0.0):
        set All += array{Mine}
    Sorted := CoachSortTimes(All)
    var Text : string = "{Title}"
    if (Sorted.Length = 0):
        return Text + CoachPick("\n   No times yet. Finish the course to set the first one.", "\n   אין זמנים עדיין. סיים את המסלול כדי לקבוע את הראשון.", Hebrew)
    var MyRank : int = 0
    for (Index -> Value : Sorted):
        if (MyRank = 0 and Mine > 0.0 and Value = Mine):
            set MyRank = Index + 1
        if (Index < 5):
            You := if (MyRank = Index + 1) then CoachPick("  ← you", "  ← אתה", Hebrew) else ""
            set Text += "\n   {Index + 1}. {CoachElapsedText(Value)}{You}"
    if (MyRank > 5):
        set Text += CoachPick("\n   You: #{MyRank} of {Sorted.Length} ({CoachElapsedText(Mine)})", "\n   אתה: מקום {MyRank} מתוך {Sorted.Length} ({CoachElapsedText(Mine)})", Hebrew)
    else if (MyRank = 0):
        set Text += CoachPick("\n   Your time: not set yet.", "\n   הזמן שלך: עדיין אין.", Hebrew)
    Text
