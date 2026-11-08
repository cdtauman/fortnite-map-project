"""Author owned grid-aligned geometry in Unreal XYZ centimeters."""

from pathlib import Path
import json
from build_training_meshes import Mesh


class GridMesh(Mesh):
    def __init__(self):
        super().__init__()
        self.material = 'Board'
        self.materials = []

    def add(self, vertices, faces):
        super().add(vertices, faces)
        self.materials.extend([self.material] * len(faces))

    def obj(self, path):
        lines = ['# Owned grid kit; centimeters, source XYZ.', 'mtllib GridKit.mtl', 's off']
        for x, y, z in self.vertices:
            # The inspected OBJ pipeline mirrors Y on import. Asymmetric floor bounds verify this.
            lines.append(f'v {x:g} {-y:g} {z:g}')
        current = None
        for face, material in zip(self.faces, self.materials):
            if current != material:
                lines.append('usemtl ' + material)
                current = material
            lines.append('f ' + ' '.join(str(i + 1) for i in face))
        path.write_text('\n'.join(lines) + '\n', encoding='utf-8')


def wall(opening=None):
    mesh = GridMesh()
    # A continuous backing surface prevents decorative plank seams from becoming bullet holes.
    spans = [(-256, 256, 0, 384)]
    if opening == 'Window':
        spans = [(-256, -85.3333, 0, 384), (85.3333, 256, 0, 384),
                 (-85.3333, 85.3333, 0, 128), (-85.3333, 85.3333, 256, 384)]
    elif opening == 'Exit':
        spans = [(-256, -96, 0, 384), (96, 256, 0, 384), (-96, 96, 300, 384)]
    for x0, x1, z0, z1 in spans:
        mesh.material = 'Board'
        mesh.box((x0, -10, z0), (x1, 10, z1))
        # Narrow raised planks, bounded by the same opening as the backing surface.
        x = x0
        plank = 0
        while x < x1 - .1:
            mesh.material = 'Board' if plank % 2 else 'Trim'
            mesh.box((x + .5, 10, z0), (min(x + 62, x1 - .1), 14, z1))
            x += 64
            plank += 1
    mesh.material = 'Grain'
    for z in [28, 350]:
        for x0, x1, z0, z1 in spans:
            if z0 <= z and z + 8 <= z1:
                mesh.box((x0, -18, z), (x1, -10, z + 8))
    return mesh


def floor(half=False):
    mesh = GridMesh()
    x0 = 0 if half else -256
    mesh.box((x0, 0, -16), (256, 512, 0))
    for y in range(0, 512, 64):
        mesh.material = 'Trim' if y % 128 else 'Board'
        mesh.box((x0, y + 1, 0), (256, y + 62, 4))
    return mesh


def ramp(half=False):
    mesh = GridMesh()
    x0 = 0 if half else -256
    mesh.add([(x0, 0, 0), (256, 0, 0), (x0, 512, 0), (256, 512, 0),
              (x0, 512, 384), (256, 512, 384)],
             [(0, 2, 3, 1), (0, 1, 5, 4), (0, 4, 2), (1, 3, 5), (2, 4, 5, 3)])
    for step in range(16):
        mesh.material = 'Trim' if step % 2 else 'Board'
        mesh.box((x0, step * 32, step * 24), (256, step * 32 + 32, step * 24 + 24))
    return mesh


def cone():
    mesh = GridMesh()
    mesh.add([(-256, 0, 0), (256, 0, 0), (256, 512, 0), (-256, 512, 0), (0, 256, 192)],
             [(0, 3, 2, 1), (0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)])
    return mesh


def main():
    target = Path('uefn/Art/GridKit')
    target.mkdir(parents=True, exist_ok=True)
    material_text = '\n'.join(f'newmtl {name}\nKd {r} {g} {b}\n' for name, r, g, b in [
        ('Board', .43, .27, .12), ('Trim', .52, .34, .17), ('Grain', .21, .12, .055)])
    (target/'GridKit.mtl').write_text(material_text, encoding='utf-8')
    meshes = {'WallSolid': wall(), 'WallWindow': wall('Window'), 'WallExit': wall('Exit'),
              'Floor': floor(), 'FloorHalf': floor(True), 'Ramp': ramp(), 'RampHalf': ramp(True), 'Cone': cone()}
    manifest = {'units': 'centimeters', 'source_axes': 'Unreal XYZ', 'obj_y_up': False, 'obj_y_flipped': True,
                'wall_plane': 'XZ; wall center at X=0,Y=0; base Z=0',
                'horizontal_piece_origin': 'X centered; Y rear edge, extends 0..512',
                'ramp_rise': '+Y to Z=384', 'cone_height': 192,
                'scope': 'Independently authored source geometry. Native edit/slot compatibility remains unverified.', 'meshes': {}}
    for name, mesh in meshes.items():
        mesh.obj(target/(name + '.obj'))
        manifest['meshes'][name] = {'bounds': {
            'min': [min(v[i] for v in mesh.vertices) for i in range(3)],
            'max': [max(v[i] for v in mesh.vertices) for i in range(3)]},
            'triangles': sum(len(face) - 2 for face in mesh.faces)}
    (target/'dimensions.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print('Authored', len(meshes), 'owned grid meshes')


if __name__ == '__main__':
    main()
