"""Create independent visual states for the authored teaching sequence."""
from pathlib import Path
import json
from build_grid_meshes import GridMesh


def wall_side():
    mesh = GridMesh()
    mesh.box((-256 / 3, -10, 0), (256, 10, 384))
    for index in range(6):
        x0 = -256 / 3 + index * (512 / 9)
        mesh.material = 'Trim' if index % 2 else 'Board'
        mesh.box((x0 + .5, 10, 0), (min(256, x0 + 55), 14, 384))
    return mesh


def roof_left_raised():
    mesh = GridMesh()

    def slab(y0, y1, lower, upper):
        def height(x):
            return (256 - x) * .75
        vertices = [(x, y, height(x) + z) for z in [upper, lower]
                    for x, y in [(-256, y0), (256, y0), (256, y1), (-256, y1)]]
        mesh.add(vertices, [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1),
                            (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)])
    slab(0, 512, -12, 0)
    for index in range(8):
        mesh.material = 'Trim' if index % 2 else 'Board'
        slab(index * 64 + 1, index * 64 + 62, 0, 4)
    return mesh


def main():
    target = Path('uefn/Art/TeachingKit')
    target.mkdir(parents=True, exist_ok=True)
    (target/'GridKit.mtl').write_bytes(Path('uefn/Art/GridKit/GridKit.mtl').read_bytes())
    meshes = {'WallSide': wall_side(), 'ConeRaisedLeft': roof_left_raised()}
    manifest = {'units': 'centimeters', 'source_axes': 'Unreal XYZ', 'obj_y_flipped': True,
                'scope': 'Owned visual teaching states. Correspondence to native edit tile selections must be verified in the final gameplay checks.', 'meshes': {}}
    for name, mesh in meshes.items():
        mesh.obj(target/(name+'.obj'))
        manifest['meshes'][name] = {'bounds': {'min': [min(v[i] for v in mesh.vertices) for i in range(3)], 'max': [max(v[i] for v in mesh.vertices) for i in range(3)]}, 'triangles': sum(len(f)-2 for f in mesh.faces)}
    (target/'dimensions.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
    print('Created two teaching states; native edit correspondence remains unverified')


if __name__ == '__main__':
    main()
