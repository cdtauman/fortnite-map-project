"""Check the authored route's spatial contract without starting a game."""
import argparse
import json
import math
from pathlib import Path


def verify(layout, kit):
    pieces = {p['label']: p for p in layout['pieces']}
    if len(pieces) != 10:
        raise ValueError('The course must contain ten uniquely named pieces')

    def location(name):
        piece = pieces['PCL_Triple_' + name]
        t = piece['transform']
        if any(abs(t['rotation'][axis]) > .001 for axis in ['yaw', 'pitch', 'roll']):
            raise ValueError('This straight-route contract requires zero piece rotation')
        if any(abs(t['scale'][axis] - 1) > .001 for axis in ['x', 'y', 'z']):
            raise ValueError('Course pieces must retain their measured grid scale')
        return [t['location'][axis] for axis in ['x', 'y', 'z']]

    ramp, floor, cone, wall, landing = [location(n) for n in ['Ramp', 'Floor', 'Cone', 'Wall', 'Landing']]
    bounds = kit['meshes']['Ramp']['bounds']
    ramp_end_y = ramp[1] + bounds['max'][1]
    ramp_top_z = ramp[2] + bounds['max'][2]
    expected = {
        'all_pieces_share_lane_center': all(math.isclose(p[0], ramp[0], abs_tol=.01) for p in [floor, cone, wall, landing]),
        'floor_overhead_on_ramp_cell': math.isclose(floor[1], ramp[1], abs_tol=.01) and math.isclose(floor[2], ramp_top_z, abs_tol=.01),
        'cone_above_same_floor_cell': floor == cone,
        'wall_at_ramp_exit': math.isclose(wall[1], ramp_end_y, abs_tol=.01) and math.isclose(wall[2], ramp_top_z, abs_tol=.01),
        'landing_beyond_exit': landing == wall,
    }
    failures = [key for key, passed in expected.items() if not passed]
    if failures:
        raise ValueError('Spatial contract failed: ' + ', '.join(failures))
    return {'scope': 'Authored dimensions and layout only; native edit, collision, traversal and runtime reset remain unverified.', 'checks': expected}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--layout', type=Path, default=Path('uefn/course-layout.json'))
    parser.add_argument('--kit', type=Path, default=Path('uefn/Art/GridKit/dimensions.json'))
    parser.add_argument('--result', type=Path)
    args = parser.parse_args()
    result = verify(json.loads(args.layout.read_text()), json.loads(args.kit.read_text()))
    if args.result:
        args.result.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print('Course geometry:', len(result['checks']), 'spatial checks passed; no game started')


if __name__ == '__main__':
    main()
