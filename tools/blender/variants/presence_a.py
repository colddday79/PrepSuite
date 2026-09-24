"""Variant A, "Orrery": the most restrained reading of the PrepSuite presence.

A luminous armillary sphere. Seven hairline latitude bands of long dashes describe the globe (the far side
recedes with depth); two bold tapered crescents orbit in inclined planes around a hot gold core with a thin
iris ring; a few sparks; one faint tick-mark ring facing the viewer. Core and crescents are the brightest tier,
the bands the middle tier, everything else faint.

Run headless:
    Blender -b --factory-startup --python-exit-code 1 --python presence_a.py -- [options]

Options: --out DIR  --res PX  --samples N  --frame F  --animation  --seconds S  --fps N  --still NAME  --no-render
Writes presence.blend (open it in Blender to orbit the model) and a PNG still or an MP4 loop.
"""

import argparse
import math
import os
import random
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DEFAULT = "/Users/macintosh/Documents/PrepSuite/tools/blender/out/a"

# Scene-linear colours, graded with the Standard view transform. Standard keeps a hue exactly where it is put
# while every channel stays at or below 1.0, so the brightest parts are sized to clip only in red
# (orange -> gold), never all three channels (white). Green stays >= 0.4x red so nothing drifts to salmon.
GOLD = (1.0, 0.56, 0.13)
SWEEP = (1.0, 0.50, 0.10)
EQUATOR = (1.0, 0.47, 0.09)
AMBER = (1.0, 0.40, 0.065)
DEEP = (1.0, 0.40, 0.07)
HOT = (1.0, 0.62, 0.24)
BLUE = (0.08, 0.45, 1.0)

CAM_LOC = Vector((0.0, -4.6, 0.25))
SPHERE_R = 1.0


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--out", default=OUT_DEFAULT)
    p.add_argument("--res", type=int, default=1080)
    p.add_argument("--samples", type=int, default=64)
    p.add_argument("--frame", type=int, default=1)
    p.add_argument("--animation", action="store_true")
    p.add_argument("--seconds", type=float, default=12.0)
    p.add_argument("--fps", type=int, default=30)
    p.add_argument("--seed", type=int, default=11)
    p.add_argument("--still", default="presence_still.png")
    p.add_argument("--no-render", action="store_true")
    return p.parse_args(argv)


# ---------- materials ----------

def _base_material(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    try:
        m.surface_render_method = "BLENDED"
    except (AttributeError, TypeError):
        pass
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    add = nt.nodes.new("ShaderNodeAddShader")
    nt.links.new(em.outputs[0], add.inputs[0])
    nt.links.new(tr.outputs[0], add.inputs[1])
    nt.links.new(add.outputs[0], out.inputs["Surface"])
    return m, nt, em


def _math(nt, op, *args):
    n = nt.nodes.new("ShaderNodeMath")
    n.operation = op
    for i, v in enumerate(args):
        if isinstance(v, (int, float)):
            n.inputs[i].default_value = float(v)
        else:
            nt.links.new(v, n.inputs[i])
    return n.outputs[0]


def _depth_factor(nt, far_gain, near_w=0.35, far_w=0.45):
    """1.0 across the near hemisphere, dropping to far_gain just past the silhouette, so the globe reads front to back."""
    cam = nt.nodes.new("ShaderNodeCameraData")
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.interpolation_type = "SMOOTHSTEP"
    mr.clamp = True
    d = CAM_LOC.length
    nt.links.new(cam.outputs["View Distance"], mr.inputs[0])
    mr.inputs[1].default_value = d - near_w
    mr.inputs[2].default_value = d + far_w
    mr.inputs[3].default_value = 1.0
    mr.inputs[4].default_value = far_gain
    return mr.outputs[0]


def _facing_factor(nt, power):
    """Bright along a stroke's centre line, soft at its edges: a filament of light, not a flat tube."""
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.5
    return _math(nt, "POWER", _math(nt, "SUBTRACT", 1.0, lw.outputs["Facing"]), power)


def _arc_factor(nt, span, power, floor):
    """For an arc centred on local +X: full strength mid-arc, fading to `floor` at both tips."""
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs[0])
    ang = _math(nt, "ARCTAN2", sep.outputs["Y"], sep.outputs["X"])
    c = _math(nt, "MAXIMUM", _math(nt, "COSINE", _math(nt, "MULTIPLY", ang, math.pi / span)), 0.0)
    return _math(nt, "MULTIPLY_ADD", _math(nt, "POWER", c, power), 1.0 - floor, floor)


def emissive(name, color, strength, far_gain=None, facing=None, arc=None):
    m, nt, em = _base_material(name)
    em.inputs["Color"].default_value = (*color, 1.0)
    factors = []
    if far_gain is not None:
        factors.append(_depth_factor(nt, far_gain))
    if facing:
        factors.append(_facing_factor(nt, facing))
    if arc:
        factors.append(_arc_factor(nt, *arc))
    s = float(strength)
    for f in factors:
        s = _math(nt, "MULTIPLY", f, s)
    if isinstance(s, float):
        em.inputs["Strength"].default_value = s
    else:
        nt.links.new(s, em.inputs["Strength"])
    return m


def spark_material(strength, far_gain):
    m, nt, em = _base_material("Sparks")
    glow = nt.nodes.new("ShaderNodeAttribute")
    glow.attribute_name = "glow"
    cool = nt.nodes.new("ShaderNodeAttribute")
    cool.attribute_name = "cool"
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    sock = {s.identifier: s for s in mix.inputs}
    sock["A_Color"].default_value = (*GOLD, 1.0)
    sock["B_Color"].default_value = (*BLUE, 1.0)
    nt.links.new(cool.outputs["Fac"], sock["Factor_Float"])
    nt.links.new(next(s for s in mix.outputs if s.identifier == "Result_Color"), em.inputs["Color"])
    s = _math(nt, "MULTIPLY", glow.outputs["Fac"], strength)
    s = _math(nt, "MULTIPLY", s, _depth_factor(nt, far_gain, 0.6, 0.8))
    nt.links.new(s, em.inputs["Strength"])
    return m


def halo_material(name, color, strength, falloff):
    """Brightest where the surface faces the camera, so a sphere reads as soft volumetric light."""
    m, nt, em = _base_material(name)
    em.inputs["Color"].default_value = (*color, 1.0)
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.5
    inv = _math(nt, "SUBTRACT", 1.0, lw.outputs["Facing"])
    nt.links.new(_math(nt, "MULTIPLY", _math(nt, "POWER", inv, falloff), strength), em.inputs["Strength"])
    return m


# ---------- geometry helpers ----------

def link(ob, parent):
    bpy.context.scene.collection.objects.link(ob)
    ob.parent = parent
    return ob


def empty(name, parent):
    ob = bpy.data.objects.new(name, None)
    ob.empty_display_size = 0.1
    return link(ob, parent)


def curve_object(name, splines, bevel, material, parent, closed=False):
    """splines: list of (points, radii). Radii scale the bevel per point, which gives tapered strokes."""
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = bevel
    cu.bevel_resolution = 2
    cu.use_fill_caps = False
    for pts, radii in splines:
        radii = radii or flat(len(pts))
        sp = cu.splines.new("POLY")
        sp.points.add(len(pts) - 1)
        for i, (p, r) in enumerate(zip(pts, radii)):
            sp.points[i].co = (p.x, p.y, p.z, 1.0)
            sp.points[i].radius = r
        sp.use_cyclic_u = closed
    cu.materials.append(material)
    return link(bpy.data.objects.new(name, cu), parent)


def arc(radius, height, a0, a1, step_deg=1.0):
    n = max(2, int(abs(a1 - a0) / math.radians(step_deg)) + 1)
    return [
        Vector((radius * math.cos(a0 + (a1 - a0) * i / (n - 1)), radius * math.sin(a0 + (a1 - a0) * i / (n - 1)), height))
        for i in range(n)
    ]


def ring(radius, step_deg=0.6):
    """A closed circle (used with closed=True, so there is no doubled seam point)."""
    n = int(360 / step_deg)
    return [Vector((radius * math.cos(2 * math.pi * i / n), radius * math.sin(2 * math.pi * i / n), 0.0)) for i in range(n)]


def dash_pattern(rng, symmetry, min_len, max_len, min_gap, max_gap):
    """Long dashes for one sector, repeated `symmetry` times, so turning by 360/symmetry loops seamlessly."""
    sector = 360.0 / symmetry
    phase = rng.uniform(0, sector)
    base, a = [], 0.0
    while True:
        room = sector - a - min_gap
        if room < min_len:
            break
        length = min(rng.uniform(min_len, max_len), room)
        base.append((a, a + length))
        a += length + rng.uniform(min_gap, max_gap)
    return [
        (math.radians(phase + s + k * sector), math.radians(phase + e + k * sector))
        for k in range(symmetry)
        for (s, e) in base
    ]


def flat(n):
    return [1.0] * n


def dash_radii(n, ramp):
    """Pointed, soft ends on every dash instead of blunt cuts."""
    k = max(1, min(ramp, (n - 1) // 2))
    return [0.2 + 0.8 * min(1.0, min(i, n - 1 - i) / k) for i in range(n)]


def crescent_radii(n, floor=0.04, power=1.2):
    return [floor + (1 - floor) * math.sin(math.pi * i / (n - 1)) ** power for i in range(n)]


def facing_quat():
    """Rotation that turns an object's local +Z toward the camera (for rings that must stay perfectly round)."""
    return CAM_LOC.normalized().to_track_quat("Z", "Y")


def uv_sphere(name, radius, material, parent, segments=48, rings=24):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, segments=segments, ring_count=rings)
    ob = bpy.context.active_object
    bpy.ops.object.shade_smooth()
    ob.name = name
    ob.data.materials.append(material)
    ob.parent = parent
    return ob


# ---------- the presence ----------

# latitude (deg), symmetry, dash (min_len, max_len, min_gap, max_gap in deg), strength, bevel
BANDS = [
    (0, 6, (44, 56, 3, 5), 0.85, 0.0034),
    (20, 5, (18, 46, 4, 9), 0.62, 0.0028),
    (-20, 5, (18, 46, 4, 9), 0.62, 0.0028),
    (40, 4, (20, 52, 5, 11), 0.50, 0.0026),
    (-40, 4, (20, 52, 5, 11), 0.50, 0.0026),
    (60, 3, (24, 62, 6, 14), 0.40, 0.0024),
    (-60, 3, (24, 62, 6, 14), 0.40, 0.0024),
]

# name, radius, span (deg), tilt (deg; + = seen from above, near side low), screen angle (deg, ccw),
# peak bevel, strength, orbit direction
SWEEPS = [
    ("Outer", 0.80, 220, 26, 32, 0.019, 1.30, 1),
    ("Inner", 0.40, 220, -32, -28, 0.014, 1.30, -1),
]


def build_globe(parent, rng):
    """The sphere itself: latitude bands only, tilted toward the viewer so they open into nested ellipses."""
    globe = empty("Globe", parent)
    globe.rotation_euler = (math.radians(23), math.radians(6), 0.0)
    spinners = []
    for i, (lat, symmetry, dash, strength, bevel) in enumerate(BANDS):
        phi = math.radians(lat)
        colour = EQUATOR if lat == 0 else AMBER
        mat = emissive(f"Band{lat:+d}", colour, strength, far_gain=0.14, facing=0.5)
        splines = []
        for s, e in dash_pattern(rng, symmetry, *dash):
            pts = arc(SPHERE_R * math.cos(phi), SPHERE_R * math.sin(phi), s, e, 0.75)
            splines.append((pts, dash_radii(len(pts), 4)))
        band = curve_object(f"Band{lat:+d}", splines, bevel, mat, globe)
        direction = 1 if i % 2 == 0 else -1
        spinners.append((band, direction * 2 * math.pi / symmetry))
    return globe, spinners


def build_sweeps(parent):
    """Two bold crescents, each orbiting in its own inclined plane; their widest, brightest part faces the viewer."""
    sweeps = empty("Sweeps", parent)
    spinners, strokes = [], []
    for name, r, span, tilt, screen, bevel, strength, direction in SWEEPS:
        holder = empty(f"Sweep.{name}", sweeps)
        holder.rotation_euler = (math.radians(tilt), math.radians(-screen), 0.0)
        span_r = math.radians(span)
        pts = arc(r, 0.0, -span_r / 2, span_r / 2, 0.5)
        mat = emissive(f"Sweep.{name}", SWEEP, strength, far_gain=0.3, facing=1.0, arc=(span_r, 1.2, 0.0))
        stroke = curve_object(f"Sweep.{name}.stroke", [(pts, crescent_radii(len(pts)))], bevel, mat, holder)
        stroke.rotation_euler = (0.0, 0.0, -math.pi / 2)
        spinners.append((stroke, direction * 2 * math.pi))
        strokes.append((stroke, r, span_r))
    return sweeps, spinners, strokes


def spark_mesh(name, sparks, mat, parent):
    """sparks: list of (centre, size, glow, cool). Each spark is a tiny octahedron."""
    verts, faces, glow, cool = [], [], [], []
    for c, s, g, k in sparks:
        base = len(verts)
        for off in ((s, 0, 0), (-s, 0, 0), (0, s, 0), (0, -s, 0), (0, 0, s), (0, 0, -s)):
            verts.append(c + Vector(off))
        for f in ((0, 2, 4), (2, 1, 4), (1, 3, 4), (3, 0, 4), (2, 0, 5), (1, 2, 5), (3, 1, 5), (0, 3, 5)):
            faces.append(tuple(base + i for i in f))
        glow.extend([g] * 6)
        cool.extend([k] * 6)
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.attributes.new("glow", "FLOAT", "POINT").data.foreach_set("value", glow)
    me.attributes.new("cool", "FLOAT", "POINT").data.foreach_set("value", cool)
    me.materials.append(mat)
    return link(bpy.data.objects.new(name, me), parent)


def build_sparks(globe, strokes, rng):
    """Very sparse: a light dusting on the sphere, a few inside, a few riding with each crescent."""
    mat = spark_material(1.0, 0.3)

    def rand_dir():
        return Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()

    loose = []
    for i in range(24):
        if i in (3, 11):
            loose.append((rand_dir() * SPHERE_R * rng.uniform(0.98, 1.05), 0.005, 0.9, 1.0))
            continue
        loose.append((rand_dir() * SPHERE_R * rng.uniform(0.97, 1.07), rng.uniform(0.003, 0.0055), 0.12 + 0.8 * rng.random() ** 3, 0.0))
    for i in range(9):
        if i == 4:
            loose.append((rand_dir() * rng.uniform(0.5, 0.7), 0.0045, 0.8, 1.0))
            continue
        loose.append((rand_dir() * rng.uniform(0.24, 0.72), rng.uniform(0.0025, 0.0045), 0.12 + 0.6 * rng.random() ** 2, 0.0))
    spark_mesh("Sparks", loose, mat, globe)

    for stroke, r, span in strokes:
        riders = []
        for _ in range(5):
            a = rng.uniform(-0.38, 0.38) * span
            rr = r + rng.uniform(-0.04, 0.05)
            riders.append((Vector((rr * math.cos(a), rr * math.sin(a), rng.uniform(-0.03, 0.03))), rng.uniform(0.003, 0.005), 0.3 + 0.9 * rng.random() ** 2, 0.0))
        spark_mesh(f"{stroke.name}.sparks", riders, mat, stroke)


def build_core(parent):
    core = empty("Core", parent)
    uv_sphere("Core.heart", 0.030, emissive("Heart", HOT, 0.7, facing=1.0), core, 32, 16)
    uv_sphere("Core.halo", 0.21, halo_material("Halo", GOLD, 0.5, 6.0), core)
    iris = empty("Core.iris", core)
    iris.rotation_mode = "QUATERNION"
    iris.rotation_quaternion = facing_quat()
    curve_object("Core.iris.ring", [(ring(0.125), None)], 0.0021, emissive("Iris", GOLD, 0.95, facing=0.5), iris, closed=True)
    return core


def build_hud_ring(parent):
    """One faint measuring ring facing the viewer, echoing the tick ring on the app's voice screen."""
    holder = empty("HudRing", parent)
    holder.rotation_mode = "QUATERNION"
    holder.rotation_quaternion = facing_quat()
    spin = empty("HudRing.spin", holder)
    r = 1.12
    curve_object("HudRing.line", [(ring(r, 0.5), None)], 0.0014, emissive("HudLine", DEEP, 0.10), spin, closed=True)
    minor, major = [], []
    for i in range(120):
        a = 2 * math.pi * i / 120
        d = Vector((math.cos(a), math.sin(a), 0.0))
        if i % 10 == 0:
            major.append(([d * r, d * (r + 0.042)], None))
        else:
            minor.append(([d * r, d * (r + 0.016)], None))
    curve_object("HudRing.ticks", minor, 0.0016, emissive("HudTick", DEEP, 0.16), spin)
    curve_object("HudRing.major", major, 0.0018, emissive("HudMajor", GOLD, 0.28), spin)
    return spin, 2 * math.pi / 12


def build(seed):
    rng = random.Random(seed)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene

    root = bpy.data.objects.new("Presence", None)
    scene.collection.objects.link(root)

    globe, spinners = build_globe(root, rng)
    _, sweep_spinners, strokes = build_sweeps(root)
    spinners += sweep_spinners
    build_sparks(globe, strokes, rng)
    build_core(root)
    hud_spin, hud_turn = build_hud_ring(root)
    spinners.append((hud_spin, -hud_turn))
    return scene, spinners


def animate(scene, spinners, seconds, fps):
    """Each part turns by exactly one symmetry sector per loop, so the last frame meets the first."""
    bpy.context.preferences.edit.keyframe_new_interpolation_type = "LINEAR"
    frames = int(round(seconds * fps))
    scene.frame_start = 1
    scene.frame_end = frames
    scene.render.fps = fps
    for ob, delta in spinners:
        base = ob.rotation_euler.z
        ob.keyframe_insert(data_path="rotation_euler", index=2, frame=1)
        ob.rotation_euler.z = base + delta
        ob.keyframe_insert(data_path="rotation_euler", index=2, frame=frames + 1)
        ob.rotation_euler.z = base


def setup_render(scene, res, samples):
    scene.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "METAL"
    prefs.get_devices()
    for d in prefs.devices:
        d.use = True
    scene.cycles.device = "GPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = False
    scene.cycles.max_bounces = 4
    scene.cycles.diffuse_bounces = 0
    scene.cycles.glossy_bounces = 0
    scene.cycles.transmission_bounces = 0
    scene.cycles.volume_bounces = 0
    scene.cycles.transparent_max_bounces = 64
    scene.render.resolution_x = res
    scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False

    world = bpy.data.worlds.new("Void")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs["Color"].default_value = (0.0, 0.0, 0.0, 1.0)
        bg.inputs["Strength"].default_value = 0.0
    scene.world = world

    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0

    cam_data = bpy.data.cameras.new("Camera")
    cam_data.lens = 50
    cam = bpy.data.objects.new("Camera", cam_data)
    scene.collection.objects.link(cam)
    cam.location = CAM_LOC
    direction = Vector((0, 0, 0)) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam


def _glare(tree, threshold, strength, size):
    node = tree.nodes.new("CompositorNodeGlare")
    for value in ("Bloom", "BLOOM"):
        try:
            node.inputs["Type"].default_value = value
            break
        except (TypeError, ValueError):
            continue
    for value in ("High", "HIGH"):
        try:
            node.inputs["Quality"].default_value = value
            break
        except (TypeError, ValueError):
            continue
    node.inputs["Threshold"].default_value = threshold
    node.inputs["Smoothness"].default_value = 0.35
    node.inputs["Strength"].default_value = strength
    node.inputs["Size"].default_value = size
    return node


def setup_bloom(scene):
    """A tight halation on the lines plus a medium glow that only the core and crescents reach.
    A small black level afterwards pulls the faint bloom tail back to true black."""
    tree = bpy.data.node_groups.new("PresenceComposite", "CompositorNodeTree")
    tree.interface.new_socket(name="Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    layers = tree.nodes.new("CompositorNodeRLayers")
    out = tree.nodes.new("NodeGroupOutput")
    tight = _glare(tree, 0.2, 0.42, 0.28)
    glow = _glare(tree, 0.9, 0.3, 0.5)
    curves = tree.nodes.new("CompositorNodeCurveRGB")
    curves.inputs["Black Level"].default_value = (0.0035, 0.0035, 0.0035, 1.0)
    tree.links.new(layers.outputs["Image"], tight.inputs["Image"])
    tree.links.new(tight.outputs["Image"], glow.inputs["Image"])
    tree.links.new(glow.outputs["Image"], curves.inputs["Image"])
    tree.links.new(curves.outputs["Image"], out.inputs[0])
    scene.compositing_node_group = tree
    print("BLOOM", tight.inputs["Type"].default_value, tight.inputs["Quality"].default_value)


def prepare_viewport():
    """So the saved .blend opens looking through the camera with the real render."""
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type != "VIEW_3D":
                continue
            for space in area.spaces:
                if space.type == "VIEW_3D":
                    space.shading.type = "RENDERED"
                    space.region_3d.view_perspective = "CAMERA"
                    space.overlay.show_overlays = False
                    try:
                        space.shading.use_compositor = "ALWAYS"
                    except (AttributeError, TypeError):
                        pass


def main():
    a = parse_args()
    os.makedirs(a.out, exist_ok=True)
    scene, spinners = build(a.seed)
    setup_render(scene, a.res, a.samples)
    setup_bloom(scene)
    animate(scene, spinners, a.seconds, a.fps)
    prepare_viewport()
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(a.out, "presence.blend"))
    if a.no_render:
        return
    if a.animation:
        scene.render.image_settings.file_format = "FFMPEG"
        scene.render.ffmpeg.format = "MPEG4"
        scene.render.ffmpeg.codec = "H264"
        scene.render.ffmpeg.constant_rate_factor = "HIGH"
        scene.render.filepath = os.path.join(a.out, "presence_loop.mp4")
        bpy.ops.render.render(animation=True)
    else:
        scene.frame_set(a.frame)
        scene.render.image_settings.file_format = "PNG"
        scene.render.filepath = os.path.join(a.out, a.still)
        bpy.ops.render.render(write_still=True)
    print("DONE", scene.render.filepath)


main()
