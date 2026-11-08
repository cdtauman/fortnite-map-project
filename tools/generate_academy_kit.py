"""Build the small, owned architectural mesh kit in Unreal centimeters."""
from pathlib import Path
import math

DEST = Path(__file__).resolve().parents[1] / 'uefn' / 'Art' / 'AcademyKit'

class Mesh:
    def __init__(self):
        self.vertices=[]
        self.faces=[]
    def vertex(self,x,y,z):
        self.vertices.append((x,y,z))
        return len(self.vertices)
    def face(self,indices,material='Body'):
        self.faces.append((indices,material))
    def write(self,name):
        path=DEST/(name+'.obj')
        lines=['# Units: centimeters','o '+name]
        lines += ['v %.6f %.6f %.6f'%v for v in self.vertices]
        lines += ['s off']
        current=None
        for indices,material in self.faces:
            if material!=current:
                lines.append('usemtl '+material)
                current=material
            lines.append('f '+' '.join(map(str,indices)))
        path.write_text('\n'.join(lines)+'\n',encoding='ascii')
        return {'name':name,'vertices':len(self.vertices),'faces':len(self.faces),'path':str(path)}

def bevelled_block():
    mesh=Mesh()
    rings=[]
    for z,inset in [(-50,4),(-46,0),(46,0),(50,4)]:
        x=y=50-inset
        r=max(0.5,4-inset)
        points=[(-x+r,-y),(x-r,-y),(x,-y+r),(x,y-r),(x-r,y),(-x+r,y),(-x,y-r),(-x,-y+r)]
        rings.append([mesh.vertex(a,b,z) for a,b in points])
    for lower,upper in zip(rings,rings[1:]):
        for i in range(8):
            j=(i+1)%8
            mesh.face([lower[i],lower[j],upper[j],upper[i]])
    mesh.face(list(reversed(rings[0])))
    mesh.face(rings[-1])
    return mesh.write('PCL_SM_BevelledBlock')

def portal_arch():
    mesh=Mesh()
    paths=[]
    for y in [-22,22]:
        side=[]
        for radius in [210,174]:
            points=[(radius,0),(radius,280)]
            points += [(radius*math.cos(math.pi*i/24),280+radius*math.sin(math.pi*i/24)) for i in range(1,25)]
            points += [(-radius,0)]
            side.append([mesh.vertex(x,y,z) for x,z in points])
        paths.append(side)
    front,back=paths
    for i in range(len(front[0])-1):
        j=i+1
        mesh.face([front[0][i],front[0][j],front[1][j],front[1][i]])
        mesh.face([back[0][j],back[0][i],back[1][i],back[1][j]])
        mesh.face([back[0][i],back[0][j],front[0][j],front[0][i]])
        mesh.face([front[1][i],front[1][j],back[1][j],back[1][i]],'Accent')
    for i in [0,len(front[0])-1]:
        face=[front[0][i],front[1][i],back[1][i],back[0][i]]
        mesh.face(face if i==0 else list(reversed(face)))
    return mesh.write('PCL_SM_PortalArch')

def horizon_panel():
    path=DEST/'PCL_SM_HorizonPanel.obj'
    path.write_text('# Units: centimeters\no PCL_SM_HorizonPanel\nv -50 0 -50\nv 50 0 -50\nv 50 0 50\nv -50 0 50\nvt 0 0\nvt 1 0\nvt 1 1\nvt 0 1\nusemtl Horizon\ns off\nf 1/1 2/2 3/3 4/4\nf 4/4 3/3 2/2 1/1\n',encoding='ascii')
    return {'name':'PCL_SM_HorizonPanel','vertices':4,'faces':2,'path':str(path)}

if __name__=='__main__':
    DEST.mkdir(parents=True,exist_ok=True)
    for result in [bevelled_block(),portal_arch(),horizon_panel()]:
        print(result)
