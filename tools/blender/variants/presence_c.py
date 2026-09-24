"""PrepSuite presence, variant C: "Gyroscope core".

An arc-reactor heart held inside a holographic gimbal. Three engraved rings on three axes (an
upright meridian gimbal, the app's 60-tick measuring ring on the equator, an inclined data ring),
a hot gold core (ten coils, a counter-rotating tick bezel, one small gyro ring), a sparse cloud
of orbiting motes, and a dim dotted shell that only lights up at the limb, so the silhouette
still reads as a sphere. Light is hot at the heart and cools outward (Khronos PBR Neutral keeps
the amber saturated); the one electric-blue element is the cursor sweeping the measuring ring.

Run headless:
    Blender -b --factory-startup --python-exit-code 1 --python presence_c.py -- [options]

Options: --out DIR  --res PX  --samples N  --frame F  --animation  --seconds S  --fps N  --no-render
Writes presence.blend (open it in Blender to orbit the model) and a PNG still or an MP4 loop.
"""

import argparse
import math
import os
import random
import sys

import bpy
from mathutils import Vector

OUT_DIR = "/Users/macintosh/Documents/PrepSuite/tools/blender/out/c"

# Scene-linear colours. Orange tones keep green >= 0.4x red so nothing drifts pink; the deep
# ember is only used where the light has almost died away.
HOT = (1.0, 0.60, 0.22)      # the heart; pushed hard it rolls off to warm cream, never blue-white
GOLD = (1.0, 0.62, 0.16)
AMBER = (1.0, 0.42, 0.06)
EMBER = (0.75, 0.14, 0.02)
BLUE = (0.08, 0.45, 1.0)     # the single cool accent

CAM_LOC = Vector((0.0, -4.6, 0.25))
CAM_DIST = CAM_LOC.length
FULL = 2 * math.pi
TILT = math.radians(18)      # the polar axis leans toward the camera so the equator opens up

# Ring normals in the tilted globe frame.
# Meridian gimbal: normal built from screen axes so its long axis stands exactly upright on screen.
GIMBAL_NORMAL = (0.835, -0.55 * math.cos(math.radians(18)), 0.55 * math.sin(math.radians(18)))
MEASURE_NORMAL = (0.0, 0.0, 1.0)                                                # equator
DATA_NORMAL = (-0.366, -0.233, 0.901)                                           # ecliptic, ~26 deg off
# Core ring normals in world space (the core is not tilted).
REACTOR_NORMAL = (0.30, -0.85, 0.42)
INNER_A_NORMAL = (0.163, -0.62, 0.768)
CURSOR_DEG = 255.0
GIMBAL_SPIN_DEG = 25.0   # keeps the four lit cells off the cardinal points


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--out", default=OUT_DIR)
    p.add_argument("--res", type=int, default=1080)
    p.add_argument("--samples", type=int, default=64)
    p.add_argument("--frame", type=int, default=1)
    p.add_argument("--animation", action="store_true")
    p.add_argument("--seconds", type=float, default=8.0)
    p.add_argument("--fps", type=int, default=30)
    p.add_argument("--seed", type=int, default=11)
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


def _math(nt, op, a, b):
    node = nt.nodes.new("ShaderNodeMath")
    node.operation = op
    for i, v in enumerate((a, b)):
        if isinstance(v, (int, float)):
            node.inputs[i].default_value = v
        else:
            nt.links.new(v, node.inputs[i])
    return node.outputs[0]


def _depth_fade(nt, far):
    """1.0 on the near side of the sphere, `far` on the far side: the back of every ring recedes."""
    cam = nt.nodes.new("ShaderNodeCameraData")
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.clamp = True
    mr.inputs["From Min"].default_value = CAM_DIST - 1.15
    mr.inputs["From Max"].default_value = CAM_DIST + 1.15
    mr.inputs["To Min"].default_value = 1.0
    mr.inputs["To Max"].default_value = far
    nt.links.new(cam.outputs["View Z Depth"], mr.inputs["Value"])
    return mr.outputs["Result"]


def emissive(name, color, strength, far=0.3):
    m, nt, em = _base_material(name)
    em.inputs["Color"].default_value = (*color, 1.0)
    if far is None:
        em.inputs["Strength"].default_value = strength
    else:
        nt.links.new(_math(nt, "MULTIPLY", _depth_fade(nt, far), strength), em.inputs["Strength"])
    m["preview"] = [*color, strength, 1.0 if far is None else far]
    return m


def mote_material(strength, far=0.3):
    """Per-mote brightness from the `glow` attribute; dim motes lean amber, bright ones gold."""
    m, nt, em = _base_material("Motes")
    glow = nt.nodes.new("ShaderNodeAttribute")
    glow.attribute_name = "glow"
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.clamp_factor = True
    sock = {s.identifier: s for s in mix.inputs}
    sock["A_Color"].default_value = (*AMBER, 1.0)
    sock["B_Color"].default_value = (*GOLD, 1.0)
    nt.links.new(_math(nt, "MULTIPLY", glow.outputs["Fac"], 0.7), sock["Factor_Float"])
    nt.links.new(next(s for s in mix.outputs if s.identifier == "Result_Color"), em.inputs["Color"])
    level = _math(nt, "MULTIPLY", glow.outputs["Fac"], strength)
    nt.links.new(_math(nt, "MULTIPLY", level, _depth_fade(nt, far)), em.inputs["Strength"])
    m["preview"] = [*GOLD, strength, far]
    return m


def halo_material(name, inner, outer, strength, falloff):
    """Brightest where the surface faces the camera, so a sphere reads as soft volumetric light.
    The colour runs from `inner` at the centre to `outer` at the rim: hot in the middle, cooler out."""
    m, nt, em = _base_material(name)
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.5
    cosv = _math(nt, "SUBTRACT", 1.0, lw.outputs["Facing"])
    nt.links.new(_math(nt, "MULTIPLY", _math(nt, "POWER", cosv, falloff), strength), em.inputs["Strength"])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    sock = {s.identifier: s for s in mix.inputs}
    sock["A_Color"].default_value = (*outer, 1.0)
    sock["B_Color"].default_value = (*inner, 1.0)
    nt.links.new(cosv, sock["Factor_Float"])
    nt.links.new(next(s for s in mix.outputs if s.identifier == "Result_Color"), em.inputs["Color"])
    m["halo"] = [*inner, *outer, strength, falloff]
    return m


def _limb_factor(nt, k):
    """(1 - |P.I|)^k with P the direction from the centre: 0 face-on, 1 on the silhouette."""
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    norm = nt.nodes.new("ShaderNodeVectorMath")
    norm.operation = "NORMALIZE"
    nt.links.new(geo.outputs["Position"], norm.inputs[0])
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    nt.links.new(norm.outputs["Vector"], dot.inputs[0])
    nt.links.new(geo.outputs["Incoming"], dot.inputs[1])
    return _math(nt, "POWER", _math(nt, "SUBTRACT", 1.0, _math(nt, "ABSOLUTE", dot.outputs["Value"], 0.0)), k)


def limb_material(name, color, strength, k):
    """For the shell: dots (or a smooth skin) light up only where they turn edge-on to the viewer,
    so the sphere's silhouette is drawn and its face stays dark."""
    m, nt, em = _base_material(name)
    em.inputs["Color"].default_value = (*color, 1.0)
    nt.links.new(_math(nt, "MULTIPLY", _limb_factor(nt, k), strength), em.inputs["Strength"])
    m["limb"] = [*color, strength, k]
    return m


def make_materials():
    return {
        "shell": limb_material("Shell.dots", AMBER, 0.85, 12.0),
        "rim": limb_material("Shell.rim", AMBER, 0.035, 9.0),
        "gimbal_edge": emissive("Gimbal.edge", AMBER, 0.34),
        "gimbal_tick": emissive("Gimbal.tick", AMBER, 0.22),
        "gimbal_major": emissive("Gimbal.major", AMBER, 0.55),
        "gimbal_cell": emissive("Gimbal.cell", GOLD, 0.5),
        "measure_line": emissive("Measure.line", AMBER, 0.58),
        "measure_faint": emissive("Measure.faint", AMBER, 0.24),
        "measure_tick": emissive("Measure.tick", AMBER, 0.58),
        "measure_major": emissive("Measure.major", GOLD, 0.95),
        "cursor": emissive("Cursor", BLUE, 1.3, far=0.5),
        "data_edge": emissive("Data.edge", AMBER, 0.62),
        "data_tick": emissive("Data.tick", AMBER, 0.45),
        "data_cell": emissive("Data.cell", GOLD, 1.05),
        "reactor": emissive("Reactor", GOLD, 0.9, far=None),
        "reactor_rim": emissive("Reactor.rim", GOLD, 0.8, far=None),
        "inner": emissive("Inner", AMBER, 0.7, far=0.6),
        "inner_tick": emissive("Inner.tick", AMBER, 0.42, far=0.6),
        "motes": mote_material(1.0),
    }


# ---------- geometry helpers ----------

def link(ob, parent):
    bpy.context.scene.collection.objects.link(ob)
    ob.parent = parent
    return ob


def empty(name, parent):
    ob = link(bpy.data.objects.new(name, None), parent)
    ob.empty_display_size = 0.1
    return ob


def frame(name, parent, normal, spin=0.0):
    """A holder whose local Z is `normal`, with a child that spins in that plane (for the loop)."""
    holder = empty(name, parent)
    holder.rotation_mode = "QUATERNION"
    holder.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(Vector(normal).normalized())
    spinner = empty(f"{name}.spin", holder)
    spinner.rotation_euler = (0.0, 0.0, spin)
    return spinner


def flat(n):
    return [1.0] * n


def curve_object(name, splines, bevel, material, parent):
    """splines: list of (points, radii[, cyclic]). Radii scale the bevel per point for tapered strokes."""
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = bevel
    cu.bevel_resolution = 1
    cu.use_fill_caps = False
    for spec in splines:
        pts, radii = spec[0], spec[1] or flat(len(spec[0]))
        sp = cu.splines.new("POLY")
        sp.points.add(len(pts) - 1)
        for i, (p, r) in enumerate(zip(pts, radii)):
            sp.points[i].co = (p.x, p.y, p.z, 1.0)
            sp.points[i].radius = r
        sp.use_cyclic_u = len(spec) > 2 and bool(spec[2])
    cu.materials.append(material)
    return link(bpy.data.objects.new(name, cu), parent)


def arc(radius, a0, a1, step_deg=0.75, z=0.0):
    n = max(2, int(abs(a1 - a0) / math.radians(step_deg)) + 1)
    return [Vector((radius * math.cos(a0 + (a1 - a0) * i / (n - 1)), radius * math.sin(a0 + (a1 - a0) * i / (n - 1)), z)) for i in range(n)]


def ring_pts(radius, step_deg=0.75, z=0.0):
    """A closed circle without the duplicated end point (use with a cyclic spline)."""
    n = int(360 / step_deg)
    return [Vector((radius * math.cos(FULL * i / n), radius * math.sin(FULL * i / n), z)) for i in range(n)]


def radial(r0, r1, a):
    d = Vector((math.cos(a), math.sin(a), 0.0))
    return [d * r0, d * r1]


def plates(name, segs, r_in, r_out, material, parent, step_deg=0.75):
    """Flat annular cells in the local XY plane: the lit 'data' blocks and the reactor coils."""
    verts, faces = [], []
    for a0, a1 in segs:
        n = max(2, int(abs(a1 - a0) / math.radians(step_deg)) + 1)
        base = len(verts)
        for i in range(n):
            a = a0 + (a1 - a0) * i / (n - 1)
            c, s = math.cos(a), math.sin(a)
            verts += [(r_in * c, r_in * s, 0.0), (r_out * c, r_out * s, 0.0)]
        faces += [(base + 2 * i, base + 2 * i + 1, base + 2 * i + 3, base + 2 * i + 2) for i in range(n - 1)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.materials.append(material)
    return link(bpy.data.objects.new(name, me), parent)


OCTA = ((0, 2, 4), (2, 1, 4), (1, 3, 4), (3, 0, 4), (2, 0, 5), (1, 2, 5), (3, 1, 5), (0, 3, 5))


def octa_cloud(name, centers, sizes, glows, material, parent):
    verts, faces, glow = [], [], []
    for c, s, g in zip(centers, sizes, glows):
        base = len(verts)
        for off in ((s, 0, 0), (-s, 0, 0), (0, s, 0), (0, -s, 0), (0, 0, s), (0, 0, -s)):
            verts.append((c.x + off[0], c.y + off[1], c.z + off[2]))
        faces += [tuple(base + i for i in f) for f in OCTA]
        glow += [g] * 6
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.attributes.new("glow", "FLOAT", "POINT").data.foreach_set("value", glow)
    me.materials.append(material)
    return link(bpy.data.objects.new(name, me), parent)


def sphere(name, radius, material, parent):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, segments=48, ring_count=24)
    ob = bpy.context.active_object
    bpy.ops.object.shade_smooth()
    ob.name = name
    ob.data.materials.append(material)
    ob.parent = parent
    return ob


# ---------- the presence ----------

def build_shell(parent, M):
    """The implied sphere: an even lattice of fine dots that only light up near the silhouette,
    over a barely-there rim glow. Brightness depends on the view, not the dots, so it can stay still."""
    shell = empty("Shell", parent)
    R, n = 1.12, 1500
    golden = math.pi * (3 - math.sqrt(5))
    jitter = random.Random(3)
    centers = []
    for i in range(n):   # a Fibonacci lattice, jittered so no rows show at the limb
        z = max(-1.0, min(1.0, 1 - 2 * (i + 0.5) / n + jitter.uniform(-0.4, 0.4) / n))
        rr = math.sqrt(1 - z * z)
        a = golden * i + jitter.uniform(-0.35, 0.35) * math.sqrt(4 * math.pi / n)
        centers.append(Vector((rr * math.cos(a), rr * math.sin(a), z)) * R)
    octa_cloud("Shell.dots", centers, [0.0032] * n, [1.0] * n, M["shell"], shell)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=R, segments=128, ring_count=64)
    rim = bpy.context.active_object
    bpy.ops.object.shade_smooth()
    rim.name = "Shell.rim"
    rim.data.materials.append(M["rim"])
    rim.parent = shell
    return shell


def build_gimbal(parent, M):
    """Outer meridian gimbal: an engraved rail, ruler ticks between its edges, four lit cells."""
    r, hw = 1.0, 0.026
    spin = frame("Gimbal", parent, GIMBAL_NORMAL, spin=math.radians(GIMBAL_SPIN_DEG))
    curve_object("Gimbal.edges", [(ring_pts(r - hw), None, True), (ring_pts(r + hw), None, True)], 0.0018, M["gimbal_edge"], spin)
    minor, major = [], []
    for i in range(72):
        a = FULL * i / 72
        if i % 6 == 0:
            major.append((radial(r - hw, r + hw + 0.035, a), None))
        elif i % 18 not in (7, 8, 9, 10):   # leave the cells clean
            minor.append((radial(r - hw * 0.5, r + hw * 0.5, a), None))
    curve_object("Gimbal.ticks", minor, 0.0014, M["gimbal_tick"], spin)
    curve_object("Gimbal.major", major, 0.0017, M["gimbal_major"], spin)
    cells = [(math.radians(90 * k + 37), math.radians(90 * k + 53)) for k in range(4)]
    plates("Gimbal.cells", cells, r - hw + 0.007, r + hw - 0.007, M["gimbal_cell"], spin)
    return spin


def build_measure(parent, M):
    """The app's 60-tick measuring ring laid on the equator; a blue cursor sweeps it once a loop."""
    r = 0.88
    spin = frame("Measure", parent, MEASURE_NORMAL)
    curve_object("Measure.line", [(ring_pts(r), None, True)], 0.0018, M["measure_line"], spin)
    curve_object("Measure.inner", [(ring_pts(r - 0.022), None, True)], 0.0012, M["measure_faint"], spin)
    minor = [(radial(r, r + 0.03, FULL * i / 60), None) for i in range(60) if i % 5]
    major = [(radial(r - 0.022, r + 0.06, FULL * i / 60), None) for i in range(0, 60, 5)]
    curve_object("Measure.ticks", minor, 0.0015, M["measure_tick"], spin)
    curve_object("Measure.major", major, 0.002, M["measure_major"], spin)

    cursor = frame("Cursor", parent, MEASURE_NORMAL, spin=math.radians(CURSOR_DEG))
    trail = arc(r - 0.011, -math.radians(34), 0.0, 0.5)
    taper = [0.06 + 0.94 * (i / (len(trail) - 1)) ** 2.2 for i in range(len(trail))]
    curve_object("Cursor.trail", [(trail, taper)], 0.0034, M["cursor"], cursor)
    curve_object("Cursor.head", [(radial(r - 0.03, r + 0.075, 0.0), None)], 0.0022, M["cursor"], cursor)
    return spin, cursor


def build_data(parent, M):
    """Inclined data ring (the ecliptic): broken edge rails, a fine ruler, one lit cell per sector."""
    r, hw = 0.70, 0.021
    spin = frame("Data", parent, DATA_NORMAL)
    edges, ticks, cells = [], [], []
    for k in range(6):
        o = 60 * k

        def seg(a, b):
            return math.radians(o + a), math.radians(o + b)

        for a, b in ((1, 43), (46, 59)):
            edges.append((arc(r + hw, *seg(a, b)), None))
        for a, b in ((1, 20), (23, 59)):
            edges.append((arc(r - hw, *seg(a, b)), None))
        for j in range(15):
            ticks.append((radial(r + hw * 0.1, r + hw, math.radians(o + 4 + 1.8 * j)), None))
        cells.append(seg(47.5, 57.5))
    curve_object("Data.edges", edges, 0.0019, M["data_edge"], spin)
    curve_object("Data.ticks", ticks, 0.0012, M["data_tick"], spin)
    plates("Data.cells", cells, r - hw + 0.006, r + hw - 0.006, M["data_cell"], spin)
    return spin


def build_core(parent, M):
    """The arc-reactor heart: a hot soft ball, a gold glow, ten coils, a tick bezel and one gyro ring."""
    core = empty("Core", parent)
    sphere("Core.heart", 0.058, halo_material("Heart", HOT, GOLD, 2.6, 1.3), core)
    sphere("Core.glow", 0.19, halo_material("Glow", GOLD, AMBER, 0.3, 3.5), core)
    sphere("Core.aura", 0.58, halo_material("Aura", AMBER, EMBER, 0.06, 4.5), core)

    reactor = frame("Reactor", core, REACTOR_NORMAL)
    coils = [(math.radians(36 * k + 3), math.radians(36 * k + 33)) for k in range(10)]
    plates("Reactor.coils", coils, 0.098, 0.142, M["reactor"], reactor)
    curve_object("Reactor.rim", [(ring_pts(0.162), None, True)], 0.0016, M["reactor_rim"], reactor)

    # A tick bezel in the reactor's own plane, turning against the coils.
    inner_b = frame("Bezel", core, REACTOR_NORMAL)
    curve_object("Bezel.ticks", [(radial(0.182, 0.2 if i % 3 == 0 else 0.192, FULL * i / 36), None) for i in range(36)], 0.0013, M["inner_tick"], inner_b)

    # One small gyro ring on its own axis, open enough to clear the reactor face.
    inner_a = frame("InnerA", core, INNER_A_NORMAL)
    dashes = [(arc(0.262, math.radians(45 * k + 4), math.radians(45 * k + 31)), None) for k in range(8)]
    curve_object("InnerA.dashes", dashes, 0.0022, M["inner"], inner_a)
    return reactor, inner_a, inner_b


def build_motes(parent, rng, M):
    """A sparse orbiting cloud built from repeated sectors, so one sector's turn loops seamlessly."""
    def cloud(name, normal, copies, count, place):
        spin = frame(name, parent, normal)
        base = []
        for _ in range(count):
            a, rad, z = place()
            g = rng.random() ** 3
            size = 0.0022 + 0.0034 * g
            glow = 0.2 + 3.0 * g
            base.append((a, rad, z, size, glow))
        centers, sizes, glows = [], [], []
        for k in range(copies):
            for a, rad, z, size, glow in base:
                aa = a + FULL * k / copies
                centers.append(Vector((rad * math.cos(aa), rad * math.sin(aa), z)))
                sizes.append(size)
                glows.append(glow)
        octa_cloud(f"{name}.motes", centers, sizes, glows, M["motes"], spin)
        return spin

    def free():
        a = rng.uniform(0, FULL / 4)
        if rng.random() < 0.3:   # riding the equator just outside the measuring ring
            return a, rng.uniform(0.93, 1.06), rng.gauss(0, 0.018)
        dist = rng.uniform(0.42, 1.16)
        lat = math.asin(rng.uniform(-0.9, 0.9))
        return a, dist * math.cos(lat), dist * math.sin(lat)

    def orbit():
        return rng.uniform(0, FULL / 6), rng.uniform(0.63, 0.78), rng.gauss(0, 0.012)

    return cloud("MotesShell", MEASURE_NORMAL, 4, 28, free), cloud("MotesData", DATA_NORMAL, 6, 6, orbit)


def build(seed):
    rng = random.Random(seed)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    M = make_materials()

    root = empty("Presence", None)
    globe = empty("Globe", root)
    globe.rotation_euler = (TILT, 0.0, 0.0)

    parts = {"shell": build_shell(globe, M), "gimbal": build_gimbal(globe, M)}
    parts["measure"], parts["cursor"] = build_measure(globe, M)
    parts["data"] = build_data(globe, M)
    parts["reactor"], parts["inner_a"], parts["inner_b"] = build_core(root, M)
    parts["motes_shell"], parts["motes_data"] = build_motes(globe, rng, M)
    return scene, parts


def animate(scene, parts, seconds, fps):
    """Each part turns by exactly one symmetry sector per loop, so the last frame meets the first."""
    bpy.context.preferences.edit.keyframe_new_interpolation_type = "LINEAR"
    frames = int(seconds * fps)
    scene.frame_start = 1
    scene.frame_end = frames
    scene.render.fps = fps
    turns = {
        "gimbal": -FULL / 4, "measure": FULL / 12, "cursor": FULL,
        "data": FULL / 6, "reactor": -FULL / 10, "inner_a": FULL / 8, "inner_b": FULL / 12,
        "motes_shell": FULL / 4, "motes_data": FULL / 6,
    }
    for key, delta in turns.items():
        ob = parts[key]
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
    scene.cycles.filter_width = 1.2
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

    # PBR Neutral keeps mid-tones saturated (amber stays amber) and rolls the hot core off to warm
    # cream instead of clipping to lemon (Standard) or bleaching to white (AgX).
    for vt in ("Khronos PBR Neutral", "Standard"):
        try:
            scene.view_settings.view_transform = vt
            break
        except TypeError:
            continue
    scene.view_settings.look = "None"
    print("VIEW", scene.view_settings.view_transform)

    cam_data = bpy.data.cameras.new("Camera")
    cam_data.lens = 50
    cam = bpy.data.objects.new("Camera", cam_data)
    scene.collection.objects.link(cam)
    cam.location = CAM_LOC
    direction = Vector((0, 0, 0)) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam


def _glare(tree, kind, threshold, strength, size):
    node = tree.nodes.new("CompositorNodeGlare")
    for socket, values in (("Type", (kind, kind.upper().replace(" ", "_"))), ("Quality", ("High", "HIGH"))):
        for value in values:
            try:
                node.inputs[socket].default_value = value
                break
            except (TypeError, ValueError):
                continue
    node.inputs["Threshold"].default_value = threshold
    node.inputs["Strength"].default_value = strength
    node.inputs["Size"].default_value = size
    return node


def setup_bloom(scene):
    """Two tight glows, no veil: a small sheen on the lines and a heat bloom that only the heart,
    the reactor coils and the lit cells exceed. The background stays black."""
    tree = bpy.data.node_groups.new("PresenceComposite", "CompositorNodeTree")
    tree.interface.new_socket(name="Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    layers = tree.nodes.new("CompositorNodeRLayers")
    out = tree.nodes.new("NodeGroupOutput")
    sheen = _glare(tree, "Bloom", 0.3, 0.32, 0.06)
    heat = _glare(tree, "Bloom", 1.0, 0.5, 0.25)
    tree.links.new(layers.outputs["Image"], sheen.inputs["Image"])
    tree.links.new(sheen.outputs[0], heat.inputs["Image"])
    tree.links.new(heat.outputs[0], out.inputs[0])
    scene.compositing_node_group = tree
    print("BLOOM", heat.inputs["Type"].default_value, heat.inputs["Quality"].default_value)


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
    scene, parts = build(a.seed)
    setup_render(scene, a.res, a.samples)
    setup_bloom(scene)
    animate(scene, parts, a.seconds, a.fps)
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
        scene.render.filepath = os.path.join(a.out, "presence_still.png")
        bpy.ops.render.render(write_still=True)
    print("DONE", scene.render.filepath)


main()
