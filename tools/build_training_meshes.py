"""Author a small reusable training kit in centimeters, with explicit wall opening geometry."""

from pathlib import Path
import argparse
import json


class Mesh:
    def __init__(self):
        self.vertices = []
        self.faces = []

    def add(self, vertices, faces):
        offset = len(self.vertices)
        self.vertices.extend(vertices)
        self.faces.extend(tuple(index + offset for index in face) for face in faces)

    def box(self, lo, hi):
        x0, y0, z0 = lo
        x1, y1, z1 = hi
        self.add([(x0,y0,z0),(x1,y0,z0),(x1,y1,z0),(x0,y1,z0),
                  (x0,y0,z1),(x1,y0,z1),(x1,y1,z1),(x0,y1,z1)],
                 [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)])

    def obj(self, path, y_up=False):
        lines = ['# Training kit geometry; source dimensions are Unreal XYZ centimeters.', 's off']
        for x, y, z in self.vertices:
            if y_up:
                x, y, z = x, z, -y
            lines.append(f'v {x:g} {y:g} {z:g}')
        lines += ['f ' + ' '.join(str(index + 1) for index in face) for face in self.faces]
        path.write_text('\n'.join(lines) + '\n', encoding='utf-8')


def kit():
    meshes = {}
    solid = Mesh()
    solid.box((-12,-256,0), (12,256,384))
    meshes['WallSolid'] = solid
    window = Mesh()
    for lo, hi in [((-12,-256,0),(12,-96,384)),((-12,96,0),(12,256,384)),
                   ((-12,-96,0),(12,96,128)),((-12,-96,288),(12,96,384))]:
        window.box(lo, hi)
    meshes['WallWindow'] = window
    door = Mesh()
    for lo, hi in [((-12,-256,0),(12,-96,384)),((-12,96,0),(12,256,384)),
                   ((-12,-96,300),(12,96,384))]:
        door.box(lo, hi)
    meshes['WallDoor'] = door
    floor = Mesh()
    floor.box((-256,-256,-16),(256,256,0))
    meshes['Floor'] = floor
    ramp = Mesh()
    ramp.add([(-256,-256,0),(-256,256,0),(256,-256,0),(256,256,0),
              (256,-256,384),(256,256,384)],
             [(0,2,3,1),(0,1,5,4),(0,4,2),(1,3,5),(2,4,5,3)])
    meshes['Ramp'] = ramp
    cone = Mesh()
    cone.add([(-256,-256,0),(256,-256,0),(256,256,0),(-256,256,0),(0,0,384)],
             [(0,3,2,1),(0,1,4),(1,2,4),(2,3,4),(3,0,4)])
    meshes['Cone'] = cone
    return meshes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('uefn/Art/TrainingKit'))
    parser.add_argument('--obj-y-up', action='store_true')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    manifest = {'units': 'centimeters', 'source_axes': 'Unreal XYZ',
                'obj_y_up': args.obj_y_up, 'evidence': 'Source geometry only; imported bounds and gameplay collision require separate verification.', 'meshes': {}}
    for name, mesh in kit().items():
        mesh.obj(args.output / (name + '.obj'), args.obj_y_up)
        bounds = {'min': [min(v[i] for v in mesh.vertices) for i in range(3)],
                  'max': [max(v[i] for v in mesh.vertices) for i in range(3)]}
        manifest['meshes'][name] = {'vertices': len(mesh.vertices),
                                    'triangles': sum(len(face)-2 for face in mesh.faces), 'bounds': bounds}
    (args.output/'dimensions.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
    print('Authored', len(manifest['meshes']), 'training meshes')


if __name__ == '__main__':
    main()
