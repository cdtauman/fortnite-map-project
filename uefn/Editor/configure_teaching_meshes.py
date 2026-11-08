"""Apply the reviewed build settings to the owned teaching mesh family."""
import unreal
s=unreal.get_editor_subsystem(unreal.StaticMeshEditorSubsystem)
root='/eda26a53-42c0-4b9e-8f62-31719aef6889/Art/'
for folder,names in [('GridKit',['PCL_SM_Grid'+n for n in ['WallSolid','WallWindow','WallExit','Floor','FloorHalf','Ramp','RampHalf','Cone']]),('TeachingKit',['PCL_SM_TeachingWallSide','PCL_SM_TeachingConeRaisedLeft'])]:
 for name in names:
  m=unreal.EditorAssetLibrary.load_asset(root+folder+'/'+name)
  if m is None:raise RuntimeError('Owned mesh missing')
  b=s.get_lod_build_settings(m,0)
  b.set_editor_property('recompute_normals',True)
  b.set_editor_property('compute_weighted_normals',True)
  s.set_lod_build_settings(m,0,b)
  print('weighted_normals='+m.get_path_name())
