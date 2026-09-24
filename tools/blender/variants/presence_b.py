"""Direction B, "Data sphere": the PrepSuite presence as a distilled JARVIS-style amber hologram.

Two coherent systems instead of a tangle of random tilts:
  * the GLOBE (one axis): an outer shell of fragmented amber latitude arcs carrying a few tangent
    data panels, plus a fine inner cage of short ticks around the core;
  * the ORBIT (one plane): a single big tapered crescent riding a faint full orbit track, echoed by
    two sparse concentric data rings.
Electric blue is a whisper: two fragments per globe sector plus a few sparks (~3 % of strokes).
Every stroke fades with camera depth (far hemisphere at ~1/3, tinted toward deep ember), so the sphere
reads in 3D. The Standard view transform keeps amber saturated: over-driven strokes drift toward gold,
and only the small core reaches white.

Run headless:
    Blender -b --factory-startup --python-exit-code 1 --python presence_b.py -- [options]

Options: --out DIR  --name STEM  --res PX  --samples N  --frame F  --animation  --seconds S  --fps N
         --seed N  --no-render
Writes presence.blend (open it in Blender to orbit the model) and a PNG still or an MP4 loop.
"""

import argparse
import math
import os
import random
import sys

import bpy
from mathutils import Vector

DEFAULT_OUT = "/Users/macintosh/Documents/PrepSuite/tools/blender/out/b"

# ---------- palette (scene-linear, tuned for the Standard view transform) ----------
GOLD = (1.0, 0.62, 0.16)
LIGHT = (1.0, 0.50, 0.10)  # bright tier: light amber, not yellow
AMBER = (1.0, 0.40, 0.055)
EMBER = (0.85, 0.27, 0.035)
DEEP = (0.72, 0.17, 0.02)  # far-side tint: the back of the sphere sinks into deep ember
HOT = (1.0, 0.48, 0.09)  # the crescent
BLUE = (0.08, 0.45, 1.0)
BLUE_DEEP = (0.03, 0.20, 0.70)
CORE = (1.0, 0.80, 0.52)

# ---------- composition ----------
CAM_LOC = Vector((0.0, -4.6, 0.0))
CAM_DIST = CAM_LOC.length
CAM_FWD = (-CAM_LOC).normalized()
FAR_LEVEL = 0.33  # brightness of the far hemisphere relative to the near one
GLOBE_AXIS = (22.0, 7.0)  # tilt toward camera, then roll in the image plane (degrees)
ORBIT_AXIS = (27.0, -33.0)  # ~0.45 ellipse ratio: the crescent reads as an orbit, never edge-on
CRESCENT_AT_STILL = -40.0  # crescent centre angle in its plane at the still frame (-90 = nearest the camera)

# (near colour, far colour, strength) per tier; bevel multipliers per stroke weight
TIERS = {
    "bright": (LIGHT, AMBER, 1.1),
    "mid": (AMBER, DEEP, 0.82),
    "dim": (EMBER, DEEP, 0.50),
    "blue": (BLUE, BLUE_DEEP, 0.8),
}
WEIGHTS = {"line": 1.0, "fine": 0.62}


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--out", default=DEFAULT_OUT)
    p.add_argument("--name", default="presence_still")
    p.add_argument("--res", type=int, default=1080)
    p.add_argument("--samples", type=int, default=64)
    p.add_argument("--frame", type=int, default=40)
    p.add_argument("--animation", action="store_true")
    p.add_argument("--seconds", type=float, default=8.0)
    p.add_argument("--fps", type=int, default=30)
    p.add_argument("--seed", type=int, default=11)
    p.add_argument("--no-render", action="store_true")
    return p.parse_args(argv)


# ---------- materials ----------

def _out(node, identifier):
    return next(s for s in node.outputs if s.identifier == identifier)


def _base_material(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    try:
        m.surface_render_method = "BLENDED"
    except (AttributeError, TypeError):
        pass
    try:
        m.cycles.emission_sampling = "NONE"  # nothing here is lit, so skip building a light tree
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


def depth_factor(nt):
    """1 on the near face of the sphere, 0 on the far face, from the distance along the camera axis."""
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    rel = nt.nodes.new("ShaderNodeVectorMath")
    rel.operation = "SUBTRACT"
    nt.links.new(geo.outputs["Position"], rel.inputs[0])
    rel.inputs[1].default_value = tuple(CAM_LOC)
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    nt.links.new(rel.outputs["Vector"], dot.inputs[0])
    dot.inputs[1].default_value = tuple(CAM_FWD)
    ramp = nt.nodes.new("ShaderNodeMapRange")
    ramp.interpolation_type = "SMOOTHSTEP"
    ramp.inputs["From Min"].default_value = CAM_DIST + 0.75
    ramp.inputs["From Max"].default_value = CAM_DIST - 0.75
    ramp.inputs["To Min"].default_value = 0.0
    ramp.inputs["To Max"].default_value = 1.0
    nt.links.new(dot.outputs["Value"], ramp.inputs["Value"])
    return ramp.outputs["Result"]


def depth_level(nt, t, strength, far_level=FAR_LEVEL):
    lvl = nt.nodes.new("ShaderNodeMapRange")
    lvl.inputs["To Min"].default_value = far_level * strength
    lvl.inputs["To Max"].default_value = strength
    nt.links.new(t, lvl.inputs["Value"])
    return lvl.outputs["Result"]


def holo(name, near, far, strength, far_level=FAR_LEVEL):
    """Emissive stroke whose colour and brightness recede with depth."""
    m, nt, em = _base_material(name)
    t = depth_factor(nt)
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    sock = {s.identifier: s for s in mix.inputs}
    sock["A_Color"].default_value = (*far, 1.0)
    sock["B_Color"].default_value = (*near, 1.0)
    nt.links.new(t, sock["Factor_Float"])
    nt.links.new(_out(mix, "Result_Color"), em.inputs["Color"])
    nt.links.new(depth_level(nt, t, strength, far_level), em.inputs["Strength"])
    return m


def emissive(name, color, strength):
    m, _, em = _base_material(name)
    em.inputs["Color"].default_value = (*color, 1.0)
    em.inputs["Strength"].default_value = strength
    return m


def tier_materials(prefix, gain):
    return {k: holo(f"{prefix}.{k}", near, far, s * gain) for k, (near, far, s) in TIERS.items()}


def spark_material(strength):
    m, nt, em = _base_material("Sparks")
    t = depth_factor(nt)
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
    nt.links.new(_out(mix, "Result_Color"), em.inputs["Color"])
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    nt.links.new(glow.outputs["Fac"], mul.inputs[0])
    nt.links.new(depth_level(nt, t, strength), mul.inputs[1])
    nt.links.new(mul.outputs[0], em.inputs["Strength"])
    return m


def radial_material(name, color, strength, r0, r1):
    """Bright at radius r0 from the centre, gone by r1: energy lines that dissolve outward."""
    m, nt, em = _base_material(name)
    em.inputs["Color"].default_value = (*color, 1.0)
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    ln = nt.nodes.new("ShaderNodeVectorMath")
    ln.operation = "LENGTH"
    nt.links.new(geo.outputs["Position"], ln.inputs[0])
    fade = nt.nodes.new("ShaderNodeMapRange")
    fade.interpolation_type = "SMOOTHSTEP"
    fade.inputs["From Min"].default_value = r0
    fade.inputs["From Max"].default_value = r1
    fade.inputs["To Min"].default_value = strength
    fade.inputs["To Max"].default_value = 0.0
    nt.links.new(ln.outputs["Value"], fade.inputs["Value"])
    nt.links.new(fade.outputs["Result"], em.inputs["Strength"])
    return m


def halo_material(name, color, strength, falloff):
    """Brightest where the surface faces the camera, so a sphere reads as soft volumetric light."""
    m, nt, em = _base_material(name)
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


def empty(name, parent):
    ob = link(bpy.data.objects.new(name, None), parent)
    ob.empty_display_size = 0.1
    return ob


def axis_rig(name, parent, tilt_deg, roll_deg):
    """A fixed tilt (toward the camera, then a roll in the image plane) holding a child that spins about the tilted axis."""
    tilt = empty(name + ".tilt", parent)
    tilt.rotation_euler = (math.radians(tilt_deg), math.radians(roll_deg), 0.0)
    return tilt, empty(name, tilt)


def curve_object(name, splines, bevel, material, parent):
    """splines: list of (points, radii, cyclic). Radii scale the bevel per point, which gives tapered strokes."""
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = bevel
    cu.bevel_resolution = 1
    cu.use_fill_caps = False
    for pts, radii, cyclic in splines:
        radii = radii or flat(len(pts))
        sp = cu.splines.new("POLY")
        sp.points.add(len(pts) - 1)
        for i, (p, r) in enumerate(zip(pts, radii)):
            sp.points[i].co = (p.x, p.y, p.z, 1.0)
            sp.points[i].radius = r
        sp.use_cyclic_u = cyclic
    cu.materials.append(material)
    return link(bpy.data.objects.new(name, cu), parent)


def sph(r, lat, lon):
    return Vector((r * math.cos(lat) * math.cos(lon), r * math.cos(lat) * math.sin(lon), r * math.sin(lat)))


def _steps(a0, a1, step_deg):
    n = max(2, int(abs(a1 - a0) / math.radians(step_deg)) + 1)
    return [a0 + (a1 - a0) * i / (n - 1) for i in range(n)]


def parallel(r, lat, lon0, lon1, step_deg=1.0):
    return [sph(r, lat, lon) for lon in _steps(lon0, lon1, step_deg)]


def meridian(r, lon, lat0, lat1, step_deg=1.0):
    return [sph(r, lat, lon) for lat in _steps(lat0, lat1, step_deg)]


def flat(n):
    return [1.0] * n


def tapered(n, floor=0.1, power=0.8):
    return [floor + (1 - floor) * math.sin(math.pi * i / (n - 1)) ** power for i in range(n)]


def sector_fragments(rng, sector, long_len, short_len, gap, long_chance, tick_gap=1.6, margin=2.0):
    """Film-style rhythm inside one sector (degrees): long data arcs alternating with clusters of short ticks."""
    frags = []
    a = rng.uniform(0.0, gap[0])
    while True:
        if rng.random() < long_chance:
            pieces, kind = [rng.uniform(*long_len)], "long"
        else:
            pieces, kind = [rng.uniform(*short_len) for _ in range(rng.randint(2, 3))], "short"
        if a + sum(pieces) + tick_gap * (len(pieces) - 1) > sector - margin:
            return frags
        for p in pieces:
            frags.append((a, a + p, kind))
            a += p + tick_gap
        a += rng.uniform(*gap) - tick_gap


def replicated(symmetry, frags):
    """Repeat one sector around the circle, so spinning by 360/symmetry per loop is seamless (tiers included)."""
    sector = 360.0 / symmetry
    for k in range(symmetry):
        for s, e, *rest in frags:
            yield (math.radians(s + k * sector), math.radians(e + k * sector), *rest)


def pick_tier(rng, blue_chance, weights):
    if rng.random() < blue_chance:
        return "blue"
    r = rng.random() * sum(weights.values())
    for tier, w in weights.items():
        r -= w
        if r <= 0:
            return tier
    return "dim"


CENSUS = {}


class Buckets:
    """Collects strokes per (tier, weight) so each becomes one curve object with one material."""

    def __init__(self):
        self.items = {}

    def add(self, tier, weight, pts, radii=None, cyclic=False):
        self.items.setdefault((tier, weight), []).append((pts, radii, cyclic))

    def emit(self, name, parent, bevel, mats):
        for (tier, weight), splines in sorted(self.items.items()):
            CENSUS[tier] = CENSUS.get(tier, 0) + len(splines)
            scale = WEIGHTS[weight] * (1.25 if tier == "bright" else 1.0)
            curve_object(f"{name}.{tier}.{weight}", splines, bevel * scale, mats[tier], parent)


# ---------- the presence ----------

def build_globe(parent, rng):
    """Outer shell: seven fragmented latitudes on one axis, paired track lines, and tangent data panels."""
    _, spin = axis_rig("Globe", parent, *GLOBE_AXIS)
    sym, r = 6, 1.0
    sector = 360.0 / sym
    b = Buckets()
    long_w = {"bright": 0.14, "mid": 0.56, "dim": 0.30}
    short_w = {"bright": 0.34, "mid": 0.40, "dim": 0.26}
    belt_w = {"bright": 0.34, "mid": 0.56, "dim": 0.10}
    blue_lats = (21, -42)
    for lat in (-63, -42, -21, 0, 21, 42, 63):
        polar = abs(lat) > 60
        gap = (14, 26) if polar else (8, 20)
        frags = []
        for s, e, kind in sector_fragments(rng, sector, (10, 30), (1.6, 5.0), gap, 0.6):
            w = belt_w if lat == 0 else (long_w if kind == "long" else short_w)
            frags.append([s, e, pick_tier(rng, 0.0, w)])
        if lat in blue_lats and frags:
            min(frags, key=lambda f: abs(f[1] - f[0] - 12.0))[2] = "blue"
        for s, e, tier in replicated(sym, frags):
            b.add(tier, "line", parallel(r, math.radians(lat), s, e))

    # paired "track" lines riding just above two latitudes, like the film's double rails
    for lat in (-21, 42):
        frags = [(s, e, "bright" if rng.random() < 0.4 else "dim")
                 for s, e, _ in sector_fragments(rng, sector, (5, 12), (1.2, 3.0), (16, 30), 0.35)]
        for s, e, tier in replicated(sym, frags):
            b.add(tier, "fine", parallel(r, math.radians(lat + 1.7), s, e))

    # tangent data panels between the latitudes: short parallel "text" lines, one block with a left rule
    bands = rng.sample([-52.5, -31.5, -10.5, 10.5, 31.5, 52.5], 2)
    blocks = []
    for j, band in enumerate(bands):
        lon0 = rng.uniform(4, sector / 2 - 12) + j * sector / 2
        lines = [rng.uniform(3.0, 10.0) for _ in range(rng.randint(3, 4) if j == 0 else rng.randint(2, 3))]
        blocks.append((band + 1.8, lon0, lines, j == 0))
    for k in range(sym):
        off = k * sector
        for lat_top, lon0, lines, ruled in blocks:
            lo = math.radians(off + lon0)
            for i, length in enumerate(lines):
                lat = math.radians(lat_top - i * 1.25)
                b.add("bright" if i == 0 else "mid", "fine",
                      parallel(r, lat, lo, lo + math.radians(length / math.cos(lat))))
            if ruled:
                rule_lo = lo - math.radians(1.6)
                b.add("mid", "fine", meridian(r, rule_lo, math.radians(lat_top + 0.5),
                                              math.radians(lat_top - 1.25 * (len(lines) - 1) - 0.5)))

    b.emit("Globe", spin, 0.0034, tier_materials("Outer", 1.0))
    return spin


def build_inner(parent, rng):
    """A fine cage of short ticks close around the core, on the globe's axis, spinning the other way."""
    _, spin = axis_rig("Inner", parent, *GLOBE_AXIS)
    sym, r = 12, 0.40
    b = Buckets()
    weights = {"bright": 0.08, "mid": 0.32, "dim": 0.60}
    for lat in (-48, -16, 16, 48):
        frags = [(s, e, pick_tier(rng, 0.0, weights))
                 for s, e, _ in sector_fragments(rng, 360.0 / sym, (5, 10), (1.4, 3.2), (5, 12), 0.3, tick_gap=1.8)]
        for s, e, tier in replicated(sym, frags):
            b.add(tier, "fine", parallel(r, math.radians(lat), s, e))
    b.emit("Inner", spin, 0.0026, tier_materials("Inner", 0.62))
    return spin


def build_orbit(parent, rng):
    """The orbit plane: two sparse concentric data rings, a faint full track,
    and the crescent. Keeping them coplanar means nothing in this system ever crosses the core."""
    tilt = empty("Orbit.tilt", parent)
    tilt.rotation_euler = (math.radians(ORBIT_AXIS[0]), math.radians(ORBIT_AXIS[1]), 0.0)

    middle = empty("Middle", tilt)
    sym = 8
    b = Buckets()
    weights = {"bright": 0.12, "mid": 0.40, "dim": 0.48}
    rings = []
    for r in (0.62, 0.74):
        frags = [[s, e, pick_tier(rng, 0.0, weights)]
                 for s, e, _ in sector_fragments(rng, 360.0 / sym, (10, 26), (1.6, 4.0), (9, 20), 0.6)]
        rings.append((r, frags))
    for r, frags in rings:
        for s, e, tier in replicated(sym, frags):
            b.add(tier, "line", parallel(r, 0.0, s, e))
    b.emit("Middle", middle, 0.0032, tier_materials("Middle", 0.72))

    track_r = 0.90
    curve_object("Orbit.track", [(parallel(track_r, 0.0, 0.0, 2 * math.pi), None, True)], 0.0013,
                 holo("Orbit.track", AMBER, DEEP, 0.24), tilt)

    crescent = empty("Crescent", tilt)
    main = parallel(track_r, 0.0, math.radians(-118), math.radians(118), 0.6)
    strokes = [
        ("Crescent.main", main, tapered(len(main), 0.04, 1.0), 0.013, holo("Crescent", HOT, AMBER, 1.3)),
    ]
    inner = parallel(track_r - 0.022, 0.0, math.radians(-78), math.radians(70), 0.8)
    outer = parallel(track_r + 0.026, 0.0, math.radians(-40), math.radians(52), 0.8)
    echo = holo("Crescent.echo", GOLD, DEEP, 0.95)
    strokes.append(("Crescent.inner", inner, tapered(len(inner), 0.2, 0.6), 0.0024, echo))
    strokes.append(("Crescent.outer", outer, tapered(len(outer), 0.2, 0.6), 0.0020, echo))
    for name, pts, radii, bevel, mat in strokes:
        curve_object(name, [(pts, radii, False)], bevel, mat, crescent)
    return middle, crescent


def build_core(parent, rng):
    core = empty("Core", parent)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.022, segments=32, ring_count=16)
    heart = bpy.context.active_object
    bpy.ops.object.shade_smooth()
    heart.name = "Core.heart"
    heart.data.materials.append(emissive("Heart", CORE, 14.0))
    heart.parent = core

    for name, radius, mat in (("Core.halo", 0.19, halo_material("Halo", GOLD, 0.6, 3.0)),
                              ("Core.nebula", 0.92, halo_material("Nebula", AMBER, 0.012, 4.0))):
        bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, segments=48, ring_count=24)
        ob = bpy.context.active_object
        bpy.ops.object.shade_smooth()
        ob.name = name
        ob.data.materials.append(mat)
        ob.parent = core

    # a camera-facing iris: one hairline circle and a broken ring, so the core reads as an eye
    iris = empty("Core.iris", core)
    iris.rotation_euler = (math.radians(90), 0.0, 0.0)
    ring = [(parallel(0.068, 0.0, 0.0, 2 * math.pi), None, True)]
    dashes = [(parallel(0.098, 0.0, s, e), None, False)
              for s, e, _ in replicated(6, sector_fragments(rng, 60.0, (14, 26), (3, 6), (6, 12), 0.6))]
    curve_object("Core.iris.ring", ring, 0.0016, emissive("Iris", GOLD, 1.4), iris)
    curve_object("Core.iris.dashes", dashes, 0.0022, emissive("IrisDash", AMBER, 1.0), iris)
    return core


def build_spokes(parent, rng):
    """Faint radial energy lines that dissolve outward from the core."""
    splines = []
    n = 36
    golden = math.pi * (3 - math.sqrt(5))
    for i in range(n):
        z = 1 - 2 * (i + 0.5) / n
        rad = math.sqrt(1 - z * z)
        d = Vector((rad * math.cos(golden * i), rad * math.sin(golden * i), z))
        r0 = rng.uniform(0.12, 0.15)
        r1 = r0 + rng.uniform(0.08, 0.24)
        splines.append(([d * r0, d * (r0 + r1) / 2, d * r1], [1.0, 0.7, 0.35], False))
    return curve_object("Spokes", splines, 0.0009, radial_material("Spokes", AMBER, 0.34, 0.12, 0.34), parent)


def build_sparks(parent, rng, mat):
    """A sparse, uneven dust: mostly on the outer shell, a few drifting outside and inside."""
    verts, faces, glow, cool = [], [], [], []
    groups = ((95, 0.99, 1.03), (26, 1.07, 1.32), (30, 0.45, 0.85))
    for count, r0, r1 in groups:
        for _ in range(count):
            d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()
            c = d * rng.uniform(r0, r1)
            s = rng.uniform(0.0022, 0.0055)
            base = len(verts)
            for off in ((s, 0, 0), (-s, 0, 0), (0, s, 0), (0, -s, 0), (0, 0, s), (0, 0, -s)):
                verts.append(c + Vector(off))
            for f in ((0, 2, 4), (2, 1, 4), (1, 3, 4), (3, 0, 4), (2, 0, 5), (1, 2, 5), (3, 1, 5), (0, 3, 5)):
                faces.append(tuple(base + i for i in f))
            g = rng.random() ** 2.6
            glow.extend([0.2 + 1.5 * g] * 6)
            cool.extend([1.0 if rng.random() < 0.08 else 0.0] * 6)
    me = bpy.data.meshes.new("Sparks")
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.attributes.new("glow", "FLOAT", "POINT").data.foreach_set("value", glow)
    me.attributes.new("cool", "FLOAT", "POINT").data.foreach_set("value", cool)
    me.materials.append(mat)
    return link(bpy.data.objects.new("Sparks", me), parent)


def build(seed):
    rng = random.Random(seed)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    root = bpy.data.objects.new("Presence", None)
    scene.collection.objects.link(root)

    globe = build_globe(root, rng)
    inner = build_inner(root, rng)
    middle, crescent = build_orbit(root, rng)
    build_core(root, rng)
    build_spokes(root, rng)
    build_sparks(root, rng, spark_material(1.2))
    total = sum(CENSUS.values())
    print("CENSUS", CENSUS, "total", total, "blue %.1f%%" % (100.0 * CENSUS.get("blue", 0) / max(1, total)))
    # (object, turn per loop, angle at the still frame or None)
    spins = [
        (globe, 2 * math.pi / 6, None),
        (inner, -2 * math.pi / 12, None),
        (middle, 2 * math.pi / 8, None),
        (crescent, -2 * math.pi, math.radians(CRESCENT_AT_STILL)),
    ]
    return scene, spins


def _fcurves(action):
    try:
        return list(action.fcurves)
    except AttributeError:
        curves = []
        for layer in getattr(action, "layers", []):
            for strip in layer.strips:
                for bag in getattr(strip, "channelbags", []):
                    curves.extend(bag.fcurves)
        return curves


def animate(scene, spins, seconds, fps, still_frame):
    """Each part turns by exactly one symmetry sector per loop, so the last frame meets the first."""
    bpy.context.preferences.edit.keyframe_new_interpolation_type = "LINEAR"
    frames = int(round(seconds * fps))
    scene.frame_start = 1
    scene.frame_end = frames
    scene.render.fps = fps
    for ob, delta, at_still in spins:
        base = 0.0 if at_still is None else at_still - delta * (still_frame - 1) / frames
        ob.rotation_euler.z = base
        ob.keyframe_insert(data_path="rotation_euler", index=2, frame=1)
        ob.rotation_euler.z = base + delta
        ob.keyframe_insert(data_path="rotation_euler", index=2, frame=frames + 1)
        for fc in _fcurves(ob.animation_data.action):
            for kp in fc.keyframe_points:
                kp.interpolation = "LINEAR"


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

    # Standard keeps amber saturated; AgX would bleach the bright tiers toward white/salmon.
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0
    print("VIEW", scene.view_settings.view_transform, scene.view_settings.look)

    cam_data = bpy.data.cameras.new("Camera")
    cam_data.lens = 50
    cam = bpy.data.objects.new("Camera", cam_data)
    scene.collection.objects.link(cam)
    cam.location = CAM_LOC
    cam.rotation_euler = CAM_FWD.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam


def _glare(tree, threshold, strength, size, smoothness, maximum=None, tint=(1.0, 1.0, 1.0), saturation=1.0):
    node = tree.nodes.new("CompositorNodeGlare")
    for sock, values in (("Type", ("Bloom", "BLOOM")), ("Quality", ("High", "HIGH"))):
        for value in values:
            try:
                node.inputs[sock].default_value = value
                break
            except (TypeError, ValueError):
                continue
    node.inputs["Threshold"].default_value = threshold
    node.inputs["Smoothness"].default_value = smoothness
    node.inputs["Strength"].default_value = strength
    node.inputs["Size"].default_value = size
    node.inputs["Saturation"].default_value = saturation
    node.inputs["Tint"].default_value = (*tint, 1.0)
    if maximum is not None:
        node.inputs["Clamp"].default_value = True
        node.inputs["Maximum"].default_value = maximum
    return node


def setup_bloom(scene):
    """A tight glow on the strokes plus a warm, compact bloom that only the core can trigger.
    Both stay small so the background remains black."""
    tree = bpy.data.node_groups.new("PresenceComposite", "CompositorNodeTree")
    tree.interface.new_socket(name="Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    layers = tree.nodes.new("CompositorNodeRLayers")
    out = tree.nodes.new("NodeGroupOutput")
    lines = _glare(tree, threshold=0.5, strength=0.22, size=0.14, smoothness=0.3, saturation=1.1)
    core = _glare(tree, threshold=1.5, strength=0.5, size=0.3, smoothness=0.2, maximum=6.0,
                  tint=(1.0, 0.7, 0.4), saturation=1.1)
    tree.links.new(layers.outputs["Image"], lines.inputs["Image"])
    tree.links.new(lines.outputs["Image"], core.inputs["Image"])
    tree.links.new(core.outputs["Image"], out.inputs[0])
    scene.compositing_node_group = tree
    print("BLOOM", core.inputs["Type"].default_value, core.inputs["Quality"].default_value)


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
    scene, spins = build(a.seed)
    setup_render(scene, a.res, a.samples)
    setup_bloom(scene)
    animate(scene, spins, a.seconds, a.fps, a.frame)
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
        scene.render.filepath = os.path.join(a.out, a.name + ".png")
        bpy.ops.render.render(write_still=True)
    print("DONE", scene.render.filepath)


main()
