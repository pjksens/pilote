# Outils communs : scène, feutrine, yeux, rendu (Blender 5, Cycles).
import bpy, bmesh, math, sys, os
from mathutils import Vector

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    s = bpy.context.scene
    s.render.engine = 'CYCLES'
    s.render.film_transparent = True
    s.render.image_settings.file_format = 'PNG'
    s.render.image_settings.color_mode = 'RGBA'
    s.render.resolution_x = s.render.resolution_y = 1024
    s.cycles.samples = int(os.environ.get("SAMPLES", "160"))
    s.cycles.use_denoising = True
    s.cycles.max_bounces = 6
    s.view_settings.view_transform = 'Standard'
    s.view_settings.look = 'None'
    try:
        p = bpy.context.preferences.addons['cycles'].preferences
        p.compute_device_type = 'METAL'
        p.get_devices()
        for d in p.devices: d.use = True
        s.cycles.device = 'GPU'
    except Exception as e:
        print("GPU indisponible", e)
    return s

def felt(name, color, rough=0.95, bump=0.7, scale=260, sheen=1.0, sss=0.12):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; b = nt.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    for k, v in (("Sheen Weight", sheen * 0.6), ("Sheen Roughness", 0.45), ("Subsurface Weight", sss), ("Specular IOR Level", 0.15)):
        if k in b.inputs: b.inputs[k].default_value = v
    if "Sheen Tint" in b.inputs:
        lite = tuple(min(1, c * 0.8 + 0.2) for c in color)
        b.inputs["Sheen Tint"].default_value = (*lite, 1)
    if "Subsurface Radius" in b.inputs:
        b.inputs["Subsurface Radius"].default_value = (0.05, 0.05, 0.05)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    n1 = nt.nodes.new("ShaderNodeTexNoise"); n1.inputs["Scale"].default_value = scale; n1.inputs["Detail"].default_value = 8; n1.inputs["Roughness"].default_value = 0.7
    n2 = nt.nodes.new("ShaderNodeTexNoise"); n2.inputs["Scale"].default_value = scale * 0.2; n2.inputs["Detail"].default_value = 4
    mix = nt.nodes.new("ShaderNodeMath"); mix.operation = 'ADD'
    mul = nt.nodes.new("ShaderNodeMath"); mul.operation = 'MULTIPLY'; mul.inputs[1].default_value = 0.35
    nt.links.new(tc.outputs["Object"], n1.inputs["Vector"]); nt.links.new(tc.outputs["Object"], n2.inputs["Vector"])
    nt.links.new(n2.outputs["Fac"], mul.inputs[0]); nt.links.new(n1.outputs["Fac"], mix.inputs[0]); nt.links.new(mul.outputs[0], mix.inputs[1])
    # velours : bords éclaircis + grain de couleur
    lw = nt.nodes.new("ShaderNodeLayerWeight"); lw.inputs["Blend"].default_value = 0.35
    mc = nt.nodes.new("ShaderNodeMix"); mc.data_type = 'RGBA'
    mc.inputs["A"].default_value = (*color, 1)
    mc.inputs["B"].default_value = (*[min(1, x * 0.55 + 0.45) for x in color], 1)
    nt.links.new(lw.outputs["Facing"], mc.inputs["Factor"])
    mc.inputs["Factor"].default_value = 0.0
    nt.links.remove(mc.inputs["Factor"].links[0]) if mc.inputs["Factor"].links else None
    pw = nt.nodes.new("ShaderNodeMath"); pw.operation = 'POWER'; pw.inputs[1].default_value = 3.0
    nt.links.new(lw.outputs["Facing"], pw.inputs[0])
    cl = nt.nodes.new("ShaderNodeMath"); cl.operation = 'MULTIPLY'; cl.inputs[1].default_value = 0.45
    nt.links.new(pw.outputs[0], cl.inputs[0]); nt.links.new(cl.outputs[0], mc.inputs["Factor"])
    nt.links.new(mc.outputs["Result"], b.inputs["Base Color"])
    bp = nt.nodes.new("ShaderNodeBump"); bp.inputs["Strength"].default_value = bump; bp.inputs["Distance"].default_value = 0.03
    nt.links.new(mix.outputs[0], bp.inputs["Height"]); nt.links.new(bp.outputs["Normal"], b.inputs["Normal"])
    return m

def bead(name="perle"):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.005, 0.005, 0.008, 1)
    b.inputs["Roughness"].default_value = 0.12
    return m

def glossy(name, color, rough=0.1, alpha=1.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1); b.inputs["Roughness"].default_value = rough
    return m

def smooth(o, sub=2):
    for p in o.data.polygons: p.use_smooth = True
    if sub:
        m = o.modifiers.new("sub", 'SUBSURF'); m.levels = sub; m.render_levels = sub

def sphere(name, loc=(0,0,0), scale=(1,1,1), mat=None, seg=64, rot=(0,0,0)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=seg//2, radius=1, location=loc, rotation=rot)
    o = bpy.context.active_object; o.name = name; o.scale = scale
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    for p in o.data.polygons: p.use_smooth = True
    if mat: o.data.materials.append(mat)
    return o

def torus(name, loc, major, minor, mat, rot=(0,0,0), scale=(1,1,1)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=64, minor_segments=24, location=loc, rotation=rot)
    o = bpy.context.active_object; o.name = name; o.scale = scale
    for p in o.data.polygons: p.use_smooth = True
    o.data.materials.append(mat); return o

def drop_body(name, mat, tip=0.55, seg=96):
    """Boule dont le haut est étiré en goutte à pointe arrondie."""
    o = sphere(name, mat=mat, seg=seg)
    for v in o.data.vertices:
        x, y, z = v.co
        if z > -0.2:
            t = (z + 0.2) / 1.2
            k = 1 - 0.50 * (t ** 1.6)            # rétrécit vers le haut
            v.co.x *= k; v.co.y *= k
            v.co.z = -0.2 + (z + 0.2) * (1 + tip * t * 0.6)
    o.data.update()
    return o

def eyes(spread=0.30, z=0.05, y=-0.94, size=0.085, mat=None, body_y=None):
    out = []
    for sx in (-1, 1):
        out.append(sphere("oeil", (sx * spread, y, z), (size, size * 0.55, size * 1.18), mat, seg=32))
    return out

def finish(s, frame_loc=(0, 0, 1.0), ortho=3.6, cam_z=None, cam_dist=12, elev=14, ground_z=0.0):
    # sol récepteur d'ombre
    bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, ground_z))
    g = bpy.context.active_object; g.is_shadow_catcher = True
    # lumières studio douces
    def area(name, loc, energy, size, color=(1, 1, 1)):
        d = bpy.data.lights.new(name, 'AREA'); d.energy = energy; d.size = size; d.color = color
        o = bpy.data.objects.new(name, d); bpy.context.collection.objects.link(o); o.location = loc
        t = o.constraints.new('TRACK_TO'); tgt = bpy.data.objects.new(name + "t", None); tgt.location = frame_loc
        bpy.context.collection.objects.link(tgt); t.target = tgt; t.track_axis = 'TRACK_NEGATIVE_Z'; t.up_axis = 'UP_Y'
    area("key", (-4, -6, 7), 1100, 4, (1, 0.97, 0.94))
    area("fill", (6, -5, 3), 350, 8, (0.92, 0.95, 1))
    area("rim", (0, 6, 6), 500, 5)
    area("top", (0, -1, 10), 200, 3)
    w = bpy.data.worlds.new("w"); s.world = w; w.use_nodes = True
    bg = w.node_tree.nodes["Background"]; bg.inputs[0].default_value = (0.9, 0.92, 1, 1); bg.inputs[1].default_value = 0.18
    # caméra
    cd = bpy.data.cameras.new("cam"); cd.type = 'ORTHO'; cd.ortho_scale = ortho
    c = bpy.data.objects.new("cam", cd); bpy.context.collection.objects.link(c); s.camera = c
    e = math.radians(elev)
    c.location = (frame_loc[0], frame_loc[1] - cam_dist * math.cos(e), frame_loc[2] + cam_dist * math.sin(e))
    t = c.constraints.new('TRACK_TO'); tgt = bpy.data.objects.new("ct", None); tgt.location = frame_loc
    bpy.context.collection.objects.link(tgt); t.target = tgt; t.track_axis = 'TRACK_NEGATIVE_Z'; t.up_axis = 'UP_Y'

def render(s, out):
    s.render.filepath = out
    bpy.ops.render.render(write_still=True)
