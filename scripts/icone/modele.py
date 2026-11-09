# L'icône de Pilote : boule en feutrine bleu électrique, avion en papier orange en feutrine posé sur la tête.
# blender -b -P scripts/icone/modele.py -- scripts/icone/tmp/rendu.png   (Blender 5, Cycles ; voir common.py)
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *
out = sys.argv[sys.argv.index("--") + 1]
s = reset()
body_m = felt("bleu", (0.02, 0.15, 1.0)); orange = felt("orange", (1.0, 0.36, 0.04), bump=0.25, scale=700)
body = sphere("corps", (0, 0, 1.0), (1.05, 0.98, 0.95), body_m, seg=96)
# avion : nez, queue, bouts d'ailes, quille
V = [(1.1, 0, 0.0),    # 0 nez (vers +X)
     (-0.7, 0.62, 0.2), (-0.7, -0.62, 0.2),   # 1,2 bouts d'ailes
     (-0.6, 0, 0.04),    # 3 arrière centre (pli)
     (-0.55, 0, -0.34)]  # 4 quille
F = [(0, 1, 3), (0, 3, 2), (0, 3, 4)]
mesh = bpy.data.meshes.new("avion"); mesh.from_pydata(V, [], F); mesh.update()
pl = bpy.data.objects.new("avion", mesh); bpy.context.collection.objects.link(pl); mesh.materials.append(orange)
pl.rotation_euler = (math.radians(10), math.radians(-24), math.radians(-28)); pl.scale = (1.15, 1.15, 1.15)
pl.location = (0.0, 0.0, 2.15)
bpy.context.view_layer.objects.active = pl
sd = pl.modifiers.new("sol", 'SOLIDIFY'); sd.thickness = 0.09; sd.offset = 0
bv = pl.modifiers.new("bev", 'BEVEL'); bv.width = 0.035; bv.segments = 4
for p in mesh.polygons: p.use_smooth = True
sb = pl.modifiers.new("sub", 'SUBSURF'); sb.levels = 2; sb.render_levels = 2
bm_ = bead(); eyes(0.31, 0.95, -0.93, 0.09, bm_)
finish(s, frame_loc=(0, 0, 1.45), ortho=4.0)
render(s, out)
