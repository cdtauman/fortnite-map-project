"""Keep Verse arrival positions aligned with the environment authoring data."""
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
data=json.loads((ROOT/'uefn/arena-layout.json').read_text(encoding='utf-8'))
def vector(values):
    return 'vector3{'+', '.join(f'{axis} := {float(value):.1f}' for axis,value in zip('XYZ',values))+'}'
lines=['using { /UnrealEngine.com/Temporary/SpatialMath }','','# Coordinates are maintained in arena-layout.json, in Unreal XYZ centimeters.','CoachArenaCenter(Mode : coach_mode)<computes>:vector3 =']
for arena in data['arenas']:
    lines += [f"    if (Mode = coach_mode.{arena['mode']}):",'        return '+vector(arena['center'])]
lines += ['    return '+vector(data['hub_center']),'','CoachPlayerStart(Mode : coach_mode)<computes>:vector3 =','    Center := CoachArenaCenter(Mode)']
for arena in data['arenas']:
    lines += [f"    if (Mode = coach_mode.{arena['mode']}):",'        return Center + '+vector(arena['spawn_offset'])]
lines += ['    return Center + vector3{Z := 100.0}']
duel_half=float(data['duel_start_half_separation_cm'])
lines += ['', 'CoachDuelStart(Index : int)<computes>:vector3 =', '    return CoachArenaCenter(coach_mode.Duel) + vector3{X := Clamp(Index, 0, 1) * '+f'{duel_half*2:.1f} - {duel_half:.1f}'+', Z := 100.0}']
lines += ['', 'CoachArenaHalfExtent(Mode : coach_mode)<computes>:float =']
for arena in data['arenas']:
    lines += [f"    if (Mode = coach_mode.{arena['mode']}):", f"        return {float(arena['half_extent']):.1f}"]
lines += ['    return 2200.0', '', 'CoachArenaCeiling()<computes>:float =', f"    return {float(data['enclosure_top']):.1f}"]
course=data['edit_course']
lines += ['', 'CoachCourseChainX()<computes>:float =', f"    return CoachArenaCenter(coach_mode.EditTraining).X + {float(course['chain_lane_offset']):.1f}"]
lines += ['', 'CoachCourseWallX()<computes>:float =', f"    return CoachArenaCenter(coach_mode.EditTraining).X + {float(course['wall_lane_offset']):.1f}", '', 'CoachCourseTripleX()<computes>:float =', f"    return CoachArenaCenter(coach_mode.EditTraining).X + {float(course['triple_lane_offset']):.1f}"]
lines += ['', 'CoachCourseStaging()<computes>:vector3 =', '    return CoachArenaCenter(coach_mode.EditTraining) + '+vector(course['staging_offset']), '', 'CoachCourseContains(Position : vector3)<computes>:logic =', '    Center := CoachArenaCenter(coach_mode.EditTraining)', f"    if (Abs(Position.X - Center.X) < {float(course['interaction_half_width']):.1f} and Abs(Position.Y - Center.Y) < {float(course['interaction_half_depth']):.1f}):", '        return true', '    return false']
(ROOT/'uefn/Verse/coach_arena_layout.verse').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print('Arena positions written from the shared layout data.')
