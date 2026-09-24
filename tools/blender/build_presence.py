"""Builds the PrepSuite presence: an amber holographic data sphere.

Run headless:
    Blender -b --factory-startup --python-exit-code 1 --python build_presence.py -- [options]

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

HERE = os.path.dirname(os.path.abspath(__file__))

# Scene-linear colours. Amber carries the identity; cyan is a sparse cool accent for depth.
AMBER = (1.0, 0.36, 0.05)
GOLD = (1.0, 0.60, 0.17)
EMBER = (0.85, 0.16, 0.025)
CYAN = (0.10, 0.50, 1.0)
CORE = (1.0, 0.72, 0.36)


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--out", default=os.path.join(HERE, "out"))
    p.add_argument("--res", type=int, default=1080)
    p.add_argument("--samples", type=int, default=64)
    p.add_argument("--frame", type=int, default=40)
    p.add_argument("--animation", action="store_true")
    p.add_argument("--seconds", type=float, default=8.0)
    p.add_argument("--fps", type=int, default=30)
    p.add_argument("--seed", type=int, default=7)
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


def emissive(name, color, strength):
    m, _, em = _base_material(name)
    em.inputs["Color"].default_value = (*color, 1.0)
    em.inputs["Strength"].default_value = strength
    return m


def spark_material(strength):
    m, nt, em = _base_material("Sparks")
    glow = nt.nodes.new("ShaderNodeAttribute")
    glow.attribute_name = "glow"
    cool = nt.nodes.new("ShaderNodeAttribute")
    cool.attribute_name = "cool"
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    sock = {s.identifier: s for s in mix.inputs}
    sock["A_Color"].default_value = (*GOLD, 1.0)
    sock["B_Color"].default_value = (*CYAN, 1.0)
    nt.links.new(cool.outputs["Fac"], sock["Factor_Float"])
    nt.links.new(next(s for s in mix.outputs if s.identifier == "Result_Color"), em.inputs["Color"])
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    mul.inputs[1].default_value = strength
    nt.links.new(glow.outputs["Fac"], mul.inputs[0])
    nt.links.new(mul.outputs[0], em.inputs["Strength"])
    return m


def halo_material(color, strength, falloff):
    """Brightest where the surface faces the camera, so a sphere reads as soft volumetric light."""
    m, nt, em = _base_material("Halo")
    em.inputs["Color"].default_value = (*color, 1.0)
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.5
    inv = nt.nodes.new("ShaderNodeMath")
    inv.operation = "SUBTRACT"
    inv.inputs[0].default_value = 1.0
    nt.links.new(lw.outputs["Facing"], inv.inputs[1])
    pw = nt.nodes.new("ShaderNodeMath")
    pw.operation = "POWER"
    pw.inputs[1].default_value = falloff
    nt.links.new(inv.outputs[0], pw.inputs[0])
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    mul.inputs[1].default_value = strength
    nt.links.new(pw.outputs[0], mul.inputs[0])
    nt.links.new(mul.outputs[0], em.inputs["Strength"])
    return m


# ---------- geometry helpers ----------

def link(ob, parent):
    bpy.context.scene.collection.objects.link(ob)
    ob.parent = parent
    return ob


def curve_object(name, splines, bevel, material, parent):
    """splines: list of (points, radii). Radii scale the bevel per point, which gives tapered strokes."""
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = bevel
    cu.bevel_resolution = 1
    cu.use_fill_caps = False
    for pts, radii in splines:
        radii = radii or flat(len(pts))
        sp = cu.splines.new("POLY")
        sp.points.add(len(pts) - 1)
        for i, (p, r) in enumerate(zip(pts, radii)):
            sp.points[i].co = (p.x, p.y, p.z, 1.0)
            sp.points[i].radius = r
    cu.materials.append(material)
    return link(bpy.data.objects.new(name, cu), parent)


def arc(radius, height, a0, a1, step_deg=1.0):
    n = max(2, int(abs(a1 - a0) / math.radians(step_deg)) + 1)
    return [
        Vector((radius * math.cos(a0 + (a1 - a0) * i / (n - 1)), radius * math.sin(a0 + (a1 - a0) * i / (n - 1)), height))
        for i in range(n)
    ]


def meridian(radius, lon, t0, t1, step_deg=1.0):
    n = max(2, int(abs(t1 - t0) / math.radians(step_deg)) + 1)
    pts = []
    for i in range(n):
        t = t0 + (t1 - t0) * i / (n - 1)
        pts.append(Vector((radius * math.cos(t) * math.cos(lon), radius * math.cos(t) * math.sin(lon), radius * math.sin(t))))
    return pts


def dash_pattern(rng, symmetry, min_len, max_len, min_gap, max_gap):
    """Dashes for one sector, repeated `symmetry` times, so rotating by 360/symmetry loops seamlessly."""
    sector = 2 * math.pi / symmetry
    base = []
    a = math.radians(rng.uniform(0, max_gap))
    while True:
        length = math.radians(rng.uniform(min_len, max_len))
        if a + length > sector - math.radians(1.0):
            break
        base.append((a, a + length))
        a += length + math.radians(rng.uniform(min_gap, max_gap))
    return [(s + k * sector, e + k * sector) for k in range(symmetry) for (s, e) in base]


def flat(n):
    return [1.0] * n


def tapered(n, floor=0.25):
    return [floor + (1 - floor) * math.sin(math.pi * i / (n - 1)) ** 0.7 for i in range(n)]


# ---------- the presence ----------

class Buckets:
    """Collects dashes per (tier) so each tier becomes one curve object with one material."""

    def __init__(self):
        self.items = {}

    def add(self, key, pts, radii=None):
        self.items.setdefault(key, []).append((pts, radii or flat(len(pts))))


def pick_tier(rng, cyan_chance):
    if rng.random() < cyan_chance:
        return "cyan"
    r = rng.random()
    return "bright" if r < 0.2 else ("mid" if r < 0.65 else "dim")


def build_shell(name, parent, rng, radius, latitudes, symmetry, dash, meridians, cyan_chance, bevel, mats):
    shell = link(bpy.data.objects.new(name, None), parent)
    shell.empty_display_size = 0.1
    b = Buckets()
    for lat in latitudes:
        phi = math.radians(lat)
        for s, e in dash_pattern(rng, symmetry, *dash):
            b.add(pick_tier(rng, cyan_chance), arc(radius * math.cos(phi), radius * math.sin(phi), s, e))
    for k in range(meridians):
        lon = 2 * math.pi * k / meridians
        t = math.radians(-78)
        while t < math.radians(78):
            length = math.radians(rng.uniform(6, 30))
            b.add(pick_tier(rng, cyan_chance * 0.5), meridian(radius, lon, t, min(t + length, math.radians(78))))
            t += length + math.radians(rng.uniform(4, 22))
    for tier, splines in b.items.items():
        curve_object(f"{name}.{tier}", splines, bevel * (1.35 if tier == "bright" else 1.0), mats[tier], shell)
    return shell


def build_sparks(parent, rng, count, radii, mat):
    verts, faces, glow, cool = [], [], [], []
    for _ in range(count):
        d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()
        shell_r = rng.choice(radii)
        c = d * (shell_r + rng.gauss(0, 0.025))
        s = rng.uniform(0.0025, 0.0075)
        base = len(verts)
        for off in ((s, 0, 0), (-s, 0, 0), (0, s, 0), (0, -s, 0), (0, 0, s), (0, 0, -s)):
            verts.append(c + Vector(off))
        for f in ((0, 2, 4), (2, 1, 4), (1, 3, 4), (3, 0, 4), (2, 0, 5), (1, 2, 5), (3, 1, 5), (0, 3, 5)):
            faces.append(tuple(base + i for i in f))
        g = rng.random() ** 2.2
        is_cool = 1.0 if rng.random() < 0.1 else 0.0
        glow.extend([0.25 + 2.5 * g] * 6)
        cool.extend([is_cool] * 6)
    me = bpy.data.meshes.new("Sparks")
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.attributes.new("glow", "FLOAT", "POINT").data.foreach_set("value", glow)
    me.attributes.new("cool", "FLOAT", "POINT").data.foreach_set("value", cool)
    me.materials.append(mat)
    return link(bpy.data.objects.new("Sparks", me), parent)


def build_core(parent, rng):
    core = link(bpy.data.objects.new("Core", None), parent)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.05, segments=32, ring_count=16)
    heart = bpy.context.active_object
    bpy.ops.object.shade_smooth()
    heart.name = "Core.heart"
    heart.data.materials.append(emissive("Heart", CORE, 22.0))
    heart.parent = core
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.24, segments=48, ring_count=24)
    halo = bpy.context.active_object
    bpy.ops.object.shade_smooth()
    halo.name = "Core.halo"
    halo.data.materials.append(halo_material(GOLD, 3.2, 3.0))
    halo.parent = core

    iris = [arc(0.115, 0.0, 0, 2 * math.pi, 1.0)]
    iris += [arc(0.15, 0.0, s, e) for s, e in dash_pattern(rng, 6, 8, 26, 5, 12)]
    curve_object("Core.iris", [(p, flat(len(p))) for p in iris], 0.0035, emissive("Iris", GOLD, 9.0), core)
    return core


def build_sweeps(parent):
    """The two bold crescents that give the sphere its sense of motion."""
    sweeps = link(bpy.data.objects.new("Sweeps", None), parent)
    mat = emissive("Sweep", GOLD, 7.5)
    specs = [(0.46, math.radians(-40), math.radians(210), (0.35, 0.9, 0.0)), (0.7, math.radians(150), math.radians(335), (-0.6, -0.25, 0.4))]
    for i, (r, a0, a1, rot) in enumerate(specs):
        pts = arc(r, 0.0, a0, a1, 0.8)
        holder = link(bpy.data.objects.new(f"Sweep.{i}", None), sweeps)
        holder.rotation_euler = rot
        curve_object(f"Sweep.{i}.stroke", [(pts, tapered(len(pts), 0.15))], 0.011, mat, holder)
    return sweeps


def build_spokes(parent, rng, mat):
    splines = []
    for _ in range(44):
        d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()
        r0 = rng.uniform(0.2, 0.3)
        r1 = r0 + rng.uniform(0.06, 0.2)
        splines.append(([d * r0, d * r1], [0.4, 1.0]))
    return curve_object("Spokes", splines, 0.0022, mat, parent)


def build_hud_ring(parent, mat, faint_mat):
    """An outer measuring ring with tick marks, echoing the tick ring on the app's voice screen."""
    ring = link(bpy.data.objects.new("HudRing", None), parent)
    r = 1.16
    curve_object("HudRing.line", [(arc(r, 0.0, 0, 2 * math.pi, 0.8), None)], 0.0016, faint_mat, ring)
    ticks = []
    for i in range(72):
        a = 2 * math.pi * i / 72
        length = 0.045 if i % 6 == 0 else 0.02
        d = Vector((math.cos(a), math.sin(a), 0.0))
        ticks.append(([d * r, d * (r + length)], None))
    curve_object("HudRing.ticks", [(p, flat(2)) for p, _ in ticks], 0.0018, mat, ring)
    return ring


def build(seed):
    rng = random.Random(seed)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene

    mats = {
        "bright": emissive("Shell.bright", GOLD, 9.0),
        "mid": emissive("Shell.mid", AMBER, 4.2),
        "dim": emissive("Shell.dim", EMBER, 1.8),
        "cyan": emissive("Shell.cyan", CYAN, 3.2),
    }

    root = bpy.data.objects.new("Presence", None)
    scene.collection.objects.link(root)
    root.rotation_euler = (math.radians(14), math.radians(-8), 0.0)

    outer = build_shell("Outer", root, rng, 1.0, [-64, -46, -27, -9, 9, 27, 46, 64], 4, (5, 34, 3, 18), 8, 0.06, 0.0036, mats)
    middle = build_shell("Middle", root, rng, 0.78, [-48, -24, 0, 24, 48], 6, (4, 22, 4, 16), 0, 0.03, 0.0042, mats)
    middle.rotation_euler = (math.radians(28), 0.0, math.radians(10))
    inner = build_shell("Inner", root, rng, 0.56, [-60, -40, -20, 0, 20, 40, 60], 8, (2, 9, 2, 8), 0, 0.0, 0.003, mats)
    inner.rotation_euler = (0.0, math.radians(-22), 0.0)

    build_sparks(root, rng, 1300, [1.0, 1.0, 0.78, 0.56, 1.12], spark_material(3.0))
    build_core(root, rng)
    sweeps = build_sweeps(root)
    build_spokes(root, rng, mats["dim"])
    hud = build_hud_ring(root, emissive("Hud", AMBER, 3.0), emissive("HudFaint", EMBER, 1.2))
    hud.rotation_euler = (math.radians(4), 0.0, 0.0)
    return scene, {"outer": outer, "middle": middle, "inner": inner, "sweeps": sweeps, "hud": hud}


def animate(scene, parts, seconds, fps):
    """Each part turns by exactly one symmetry sector per loop, so the last frame meets the first."""
    bpy.context.preferences.edit.keyframe_new_interpolation_type = "LINEAR"
    frames = int(seconds * fps)
    scene.frame_start = 1
    scene.frame_end = frames
    scene.render.fps = fps
    turns = {"outer": 2 * math.pi / 4, "middle": -2 * math.pi / 6, "inner": 2 * math.pi / 8, "sweeps": 2 * math.pi, "hud": -2 * math.pi / 72 * 6}
    for key, delta in turns.items():
        ob = parts[key]
        base = ob.rotation_euler.z
        ob.rotation_euler.z = base
        ob.keyframe_insert(data_path="rotation_euler", index=2, frame=1)
        ob.rotation_euler.z = base + delta
        ob.keyframe_insert(data_path="rotation_euler", index=2, frame=frames + 1)


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
    scene.cycles.transparent_max_bounces = 96
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

    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Punchy"

    cam_data = bpy.data.cameras.new("Camera")
    cam_data.lens = 50
    cam = bpy.data.objects.new("Camera", cam_data)
    scene.collection.objects.link(cam)
    cam.location = (0.0, -4.6, 0.25)
    direction = Vector((0, 0, 0)) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam


def setup_bloom(scene):
    tree = bpy.data.node_groups.new("PresenceComposite", "CompositorNodeTree")
    tree.interface.new_socket(name="Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    layers = tree.nodes.new("CompositorNodeRLayers")
    out = tree.nodes.new("NodeGroupOutput")
    wide = tree.nodes.new("CompositorNodeGlare")
    tight = tree.nodes.new("CompositorNodeGlare")
    for node, strength, size in ((wide, 0.55, 0.95), (tight, 0.35, 0.55)):
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
        node.inputs["Threshold"].default_value = 0.6
        node.inputs["Strength"].default_value = strength
        node.inputs["Size"].default_value = size
    tree.links.new(layers.outputs["Image"], tight.inputs["Image"])
    tree.links.new(tight.outputs[0], wide.inputs["Image"])
    tree.links.new(wide.outputs[0], out.inputs[0])
    scene.compositing_node_group = tree
    print("BLOOM", wide.inputs["Type"].default_value, wide.inputs["Quality"].default_value)


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
