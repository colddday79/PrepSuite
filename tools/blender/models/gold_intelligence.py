"""PrepSuite presence, "Gold Intelligence": the owner's gold globe (variants/presence_final.py), made alive.

Identity is kept exactly: the same seven dashed latitude bands (same random dash layout), the two faint meridians,
the two tapered crescents, the arc-reactor heart, the tick ring, the sparks, the black void and the Standard view.
On top of that the globe now visibly thinks:

* Comet pulses. Seven pulses run along six latitude bands and two surge through the crescents. Each is the band's
  own dashes flaring hot gold behind the head (a "wake" computed in the band shader, relative to the pulse's empty),
  a fine filament bridging the gaps, and a cream-gold head with a short trailing glow. Whole turns per loop.
* Abstract readouts. Four small HUD clusters printed on the front of the sphere: a paragraph of glyph-like dashes
  (tokens, never readable text), a likelihood histogram, a bullet list and a small voice waveform, with corner
  brackets. The histogram and waveform bars step through new heights while the loop plays.
* A refined measuring ring. An outer hairline plus an inner tick band (minor, major and cardinal ticks) with a
  few brighter active arcs, turning slowly against the globe, and one bright marker orbiting the other way.
* A 1.5x arc-reactor core with an extra counter-rotating segmented ring, a soft corona and a heart that breathes
  twice per loop, bloomed harder than the rest so it anchors the composition.
* Slightly thicker bands with a depth colour ramp (deep amber far side -> pale gold near side), a fine companion
  hairline riding the main crescent, a faint silhouette glow, and a tighter frame (globe ~80% of the square).

Run headless:
    Blender -b --factory-startup --python-exit-code 1 --python gold_intelligence.py -- [options]

Options: --out DIR  --res PX  --samples N  --frame F  --animation  --seconds S  --fps N  --still NAME  --no-render
Diagnostics: --no-bloom (raw render), --bloom "thr,str,size;..." and --black LEVEL override the compositor.
Writes presence.blend (open it in Blender to orbit the model) and a PNG still or an MP4 loop. Every moving part
turns by whole symmetry sectors (or whole turns) per loop and every rotation key is forced LINEAR (the bars step
on CONSTANT keys, the heart breathes on keys that rest at the seam), so frame 1 equals frame N+1.
"""

import argparse
import math
import os
import random
import sys

import bpy
from mathutils import Matrix, Vector

OUT_DEFAULT = "/Users/macintosh/Documents/PrepSuite/tools/blender/out/models/gold_intelligence"

# Scene-linear colours, graded with the Standard view transform. Standard keeps a hue where it is put while every
# channel stays at or below 1.0, so the brightest parts are sized to clip only in red (orange -> gold), and only
# pulse heads and the heart are allowed to reach cream. Green stays >= 0.3x red so nothing drifts to red/salmon.
GOLD = (1.0, 0.56, 0.13)
SWEEP = (1.0, 0.50, 0.10)
EQUATOR = (1.0, 0.47, 0.09)
AMBER = (1.0, 0.40, 0.065)
DEEP = (1.0, 0.40, 0.07)
EMBER = (1.0, 0.30, 0.042)       # far side of the globe: deep amber
NEAR_EQ = (1.0, 0.53, 0.115)     # near side of the equator: pale gold
NEAR_BAND = (1.0, 0.47, 0.09)    # near side of the other bands
HOT = (1.0, 0.62, 0.24)          # small accents only
WAKE = (1.0, 0.58, 0.10)         # a band lit up behind a passing pulse: hot gold
CREAM = (1.0, 0.66, 0.12)        # only at pulse heads (low blue, so stacked light clips to cream, not white)
HEART = (1.0, 0.64, 0.17)        # the centre of the heart
REACTOR = (1.0, 0.60, 0.16)
BLUE = (0.08, 0.45, 1.0)

CAM_LOC = Vector((0.0, -4.6, 0.25))
LENS = 64.5                      # 50 mm framed the globe at 62% of the square; 64.5 mm frames it at ~80%
SPHERE_R = 1.0
FULL = 2 * math.pi
GLOBE_TILT = 23.0

# Depth windows (camera distance either side of the sphere centre). Globe lines hold full strength across the
# face of the sphere and fade toward the silhouette and the far side; the crescents fade more gently.
GLOBE_FADE = (0.62, 0.18)
SWEEP_FADE = (0.35, 0.45)

# Globe lines that pass in front of or behind the heart dim inside this aperture (distance from the view axis),
# so the "face" always has clear air around it: (fully dimmed within, full strength beyond, dimmed level).
CLEAR = (0.31, 0.47, 0.12)
PULSE_CLEAR = (0.26, 0.40, 0.30)

# The arc-reactor heart, 1.5x the size it had in presence_final (0.8).
CORE_SCALE = 1.2
REACTOR_NORMAL = (0.30, -0.85, 0.42)
GYRO_NORMAL = (0.163, -0.62, 0.768)


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--out", default=OUT_DEFAULT)
    p.add_argument("--res", type=int, default=1080)
    p.add_argument("--samples", type=int, default=64)
    p.add_argument("--frame", type=int, default=1)
    p.add_argument("--animation", action="store_true")
    p.add_argument("--seconds", type=float, default=16.0)
    p.add_argument("--fps", type=int, default=30)
    p.add_argument("--seed", type=int, default=11)
    p.add_argument("--still", default="still.png")
    p.add_argument("--no-render", action="store_true")
    p.add_argument("--no-bloom", action="store_true")  # diagnostics: the raw render
    p.add_argument("--black", type=float, default=None)
    p.add_argument("--bloom", default="")  # diagnostics: "threshold,strength,size;..." overrides BLOOM
    return p.parse_args(argv)


# ---------- materials ----------

def _base_material(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    try:
        m.surface_render_method = "BLENDED"
    except (AttributeError, TypeError):
        pass
    try:
        m.cycles.emission_sampling = "NONE"  # nothing in the scene is lit, so skip building a light tree
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


def _math(nt, op, *args, clamp=False):
    n = nt.nodes.new("ShaderNodeMath")
    n.operation = op
    n.use_clamp = clamp
    for i, v in enumerate(args):
        if isinstance(v, (int, float)):
            n.inputs[i].default_value = float(v)
        else:
            nt.links.new(v, n.inputs[i])
    return n.outputs[0]


def _mix_rgb(nt, fac, a, b):
    """Colour a where fac is 0, b where fac is 1."""
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    sock = {s.identifier: s for s in mix.inputs}
    sock["A_Color"].default_value = (*a, 1.0)
    sock["B_Color"].default_value = (*b, 1.0)
    nt.links.new(fac, sock["Factor_Float"])
    return next(s for s in mix.outputs if s.identifier == "Result_Color")


def _ramp(nt, fac, stops):
    """A colour ramp through (position, colour) stops."""
    node = nt.nodes.new("ShaderNodeValToRGB")
    els = node.color_ramp.elements
    els[0].position, els[0].color = stops[0][0], (*stops[0][1], 1.0)
    els[1].position, els[1].color = stops[-1][0], (*stops[-1][1], 1.0)
    for pos, col in stops[1:-1]:
        e = els.new(pos)
        e.color = (*col, 1.0)
    nt.links.new(fac, node.inputs["Fac"])
    return node.outputs["Color"]


def _depth_factor(nt, far_gain, near_w, far_w):
    """1.0 nearer than (centre - near_w), far_gain beyond (centre + far_w), smooth in between."""
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


def _clear_factor(nt, r0, r1, floor):
    """`floor` within r0 of the camera's line of sight through the heart, 1.0 beyond r1."""
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    rel = nt.nodes.new("ShaderNodeVectorMath")
    rel.operation = "SUBTRACT"
    nt.links.new(geo.outputs["Position"], rel.inputs[0])
    rel.inputs[1].default_value = tuple(CAM_LOC)
    cross = nt.nodes.new("ShaderNodeVectorMath")
    cross.operation = "CROSS_PRODUCT"
    nt.links.new(rel.outputs["Vector"], cross.inputs[0])
    cross.inputs[1].default_value = tuple((-CAM_LOC).normalized())
    length = nt.nodes.new("ShaderNodeVectorMath")
    length.operation = "LENGTH"
    nt.links.new(cross.outputs["Vector"], length.inputs[0])
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.interpolation_type = "SMOOTHSTEP"
    mr.clamp = True
    nt.links.new(length.outputs["Value"], mr.inputs[0])
    mr.inputs[1].default_value = r0
    mr.inputs[2].default_value = r1
    mr.inputs[3].default_value = floor
    mr.inputs[4].default_value = 1.0
    return mr.outputs[0]


def _local_angle(nt, obj=None):
    """Angle about local Z of the shading point, in `obj`'s space (or the shaded object's own space)."""
    tc = nt.nodes.new("ShaderNodeTexCoord")
    if obj is not None:
        tc.object = obj
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs[0])
    return _math(nt, "ARCTAN2", sep.outputs["Y"], sep.outputs["X"])


def _arc_factor(nt, span, power, floor, obj=None):
    """For an arc centred on local +X: full strength mid-arc, fading to `floor` at both tips."""
    ang = _local_angle(nt, obj)
    c = _math(nt, "MAXIMUM", _math(nt, "COSINE", _math(nt, "MULTIPLY", ang, math.pi / span)), 0.0)
    return _math(nt, "MULTIPLY_ADD", _math(nt, "POWER", c, power), 1.0 - floor, floor)


def _apply_strength(nt, em, strength, factors):
    s = float(strength) if isinstance(strength, (int, float)) else strength
    for f in factors:
        s = _math(nt, "MULTIPLY", f, s)
    if isinstance(s, float):
        em.inputs["Strength"].default_value = s
    else:
        nt.links.new(s, em.inputs["Strength"])


def emissive(name, color, strength, far_gain=None, facing=None, arc=None, window=GLOBE_FADE, clear=None,
             far_color=None):
    """Emission + transparency. With far_color the hue also slides from far_color (far side) to color (near)."""
    m, nt, em = _base_material(name)
    if far_color is not None:
        nt.links.new(_mix_rgb(nt, _depth_factor(nt, 0.0, *window), far_color, color), em.inputs["Color"])
    else:
        em.inputs["Color"].default_value = (*color, 1.0)
    factors = []
    if clear:
        factors.append(_clear_factor(nt, *clear))
    if far_gain is not None:
        factors.append(_depth_factor(nt, far_gain, *window))
    if facing:
        factors.append(_facing_factor(nt, facing))
    if arc:
        factors.append(_arc_factor(nt, *arc))
    _apply_strength(nt, em, strength, factors)
    return m


PULSE_RAMP = [(0.0, EMBER), (0.45, AMBER), (0.8, GOLD), (0.94, WAKE), (1.0, CREAM)]


def pulse_material(name, tail, direction, strength, far_gain=None, window=GLOBE_FADE, clear=PULSE_CLEAR,
                   host=None, host_arc=None, power=1.6, facing=0.4):
    """A comet: the head sits at local angle 0 and the tail trails `tail` radians behind it (against `direction`).
    Brightness and colour both ramp from a dim deep-amber tail to a cream-gold head. With `host`, the pulse also
    takes on the host crescent's taper, measured in the host's own space, so it fades in and out at the tips."""
    m, nt, em = _base_material(name)
    t = _math(nt, "MULTIPLY_ADD", _local_angle(nt), direction / tail, 1.0, clamp=True)
    nt.links.new(_ramp(nt, t, PULSE_RAMP), em.inputs["Color"])
    factors = [_math(nt, "POWER", t, power)]
    if clear:
        factors.append(_clear_factor(nt, *clear))
    if far_gain is not None:
        factors.append(_depth_factor(nt, far_gain, *window))
    if facing:
        factors.append(_facing_factor(nt, facing))
    if host is not None:
        factors.append(_arc_factor(nt, *host_arc, obj=host))
    _apply_strength(nt, em, strength, factors)
    return m


def bead_material(name, strength, far_gain=None, window=GLOBE_FADE, clear=None, host=None, host_arc=None,
                  inner=CREAM, outer=GOLD, falloff=1.3):
    """A pulse head: a tiny sphere, cream at its centre, gold at its rim, soft-edged."""
    m, nt, em = _base_material(name)
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.5
    cosv = _math(nt, "SUBTRACT", 1.0, lw.outputs["Facing"])
    nt.links.new(_mix_rgb(nt, _math(nt, "POWER", cosv, 2.0), outer, inner), em.inputs["Color"])
    factors = [_math(nt, "POWER", cosv, falloff)]
    if clear:
        factors.append(_clear_factor(nt, *clear))
    if far_gain is not None:
        factors.append(_depth_factor(nt, far_gain, *window))
    if host is not None:
        factors.append(_arc_factor(nt, *host_arc, obj=host))
    _apply_strength(nt, em, strength, factors)
    return m


def spark_material(strength, far_gain):
    m, nt, em = _base_material("Sparks")
    glow = nt.nodes.new("ShaderNodeAttribute")
    glow.attribute_name = "glow"
    cool = nt.nodes.new("ShaderNodeAttribute")
    cool.attribute_name = "cool"
    nt.links.new(_mix_rgb(nt, cool.outputs["Fac"], GOLD, BLUE), em.inputs["Color"])
    s = _math(nt, "MULTIPLY", glow.outputs["Fac"], strength)
    s = _math(nt, "MULTIPLY", s, _depth_factor(nt, far_gain, 0.6, 0.8))
    s = _math(nt, "MULTIPLY", s, _clear_factor(nt, *CLEAR))
    nt.links.new(s, em.inputs["Strength"])
    return m


def halo_material(name, inner, outer, strength, falloff, breathe=None):
    """Brightest where the surface faces the camera, so a sphere reads as soft volumetric light.
    The colour runs from `inner` at the centre to `outer` at the rim: hot in the middle, cooler out.
    `breathe` is a list collecting (node socket, amplitude) pairs to animate."""
    m, nt, em = _base_material(name)
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.5
    cosv = _math(nt, "SUBTRACT", 1.0, lw.outputs["Facing"])
    s = _math(nt, "MULTIPLY", _math(nt, "POWER", cosv, falloff), strength)
    if breathe is not None:
        value = nt.nodes.new("ShaderNodeValue")
        value.outputs[0].default_value = 1.0
        breathe.append((m, value))
        s = _math(nt, "MULTIPLY", s, value.outputs[0])
    nt.links.new(s, em.inputs["Strength"])
    nt.links.new(_mix_rgb(nt, cosv, outer, inner), em.inputs["Color"])
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


def frame(name, parent, normal):
    """A holder whose local Z is `normal`, with a child that spins in that plane (for the loop)."""
    holder = empty(name, parent)
    holder.rotation_mode = "QUATERNION"
    holder.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(Vector(normal).normalized())
    return empty(f"{name}.spin", holder)


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


def plates(name, segs, r_in, r_out, material, parent, step_deg=0.75):
    """Flat annular cells in the local XY plane (the reactor coils)."""
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


def steps(a0, a1, step_deg):
    n = max(2, int(abs(a1 - a0) / math.radians(step_deg)) + 1)
    return [a0 + (a1 - a0) * i / (n - 1) for i in range(n)]


def arc(radius, height, a0, a1, step_deg=1.0):
    return [Vector((radius * math.cos(a), radius * math.sin(a), height)) for a in steps(a0, a1, step_deg)]


def sph(r, lat, lon):
    return Vector((r * math.cos(lat) * math.cos(lon), r * math.cos(lat) * math.sin(lon), r * math.sin(lat)))


def ring(radius, step_deg=0.6):
    """A closed circle (used with closed=True, so there is no doubled seam point)."""
    n = int(360 / step_deg)
    return [Vector((radius * math.cos(FULL * i / n), radius * math.sin(FULL * i / n), 0.0)) for i in range(n)]


def radial(r0, r1, a):
    d = Vector((math.cos(a), math.sin(a), 0.0))
    return [d * r0, d * r1]


def dash_sector(rng, symmetry, min_len, max_len, min_gap, max_gap):
    """Long dashes (degrees) for one sector of 360/symmetry, plus a random phase for the whole band."""
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
    return phase, sector, base


def replicate(phase, sector, base, symmetry):
    """Repeat one sector around the circle, so turning by 360/symmetry per loop is seamless."""
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


def comet_radii(angles, tail, nose):
    """Per-point radius for a comet whose head is at angle 0: thin at the tail, full just behind the head,
    with a rounded nose over the last `nose` radians."""
    out = []
    for a in angles:
        d = abs(a)
        t = max(0.0, 1.0 - d / tail)
        r = 0.08 + 0.92 * t ** 1.4
        if d < nose:
            r *= math.sqrt(max(0.0, 1.0 - ((nose - d) / nose) ** 2))
        out.append(max(r, 0.02))
    return out


def facing_quat():
    """Rotation that turns an object's local +Z toward the camera (for rings that must stay perfectly round)."""
    return CAM_LOC.normalized().to_track_quat("Z", "Y")


def uv_sphere(name, radius, material, parent, segments=48, rings=24, location=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, segments=segments, ring_count=rings)
    ob = bpy.context.active_object
    bpy.ops.object.shade_smooth()
    ob.name = name
    ob.data.materials.append(material)
    ob.parent = parent
    ob.location = location
    return ob


# ---------- the presence ----------

# latitude (deg), symmetry, dash (min_len, max_len, min_gap, max_gap in deg), strength, bevel
# (the owner's dash layout and brightness; strokes ~1.15x thicker, and the tighter frame adds another 1.3x)
BANDS = [
    (0, 6, (44, 56, 3, 5), 0.85, 0.0039),
    (20, 5, (18, 46, 4, 9), 0.62, 0.0032),
    (-20, 5, (18, 46, 4, 9), 0.62, 0.0032),
    (40, 4, (20, 52, 5, 11), 0.50, 0.0030),
    (-40, 4, (20, 52, 5, 11), 0.50, 0.0030),
    (60, 3, (24, 62, 6, 14), 0.40, 0.0028),
    (-60, 3, (24, 62, 6, 14), 0.40, 0.0028),
]
BAND_FAR = 0.08
BLUE_BAND = 60          # one short electric-blue dash per sector of this band (3 of ~60 dashes)
MERIDIANS = (-32.0, -148.0)   # static, 58 deg either side of the meridian that faces the viewer (-90)

# Comet pulses on the bands: latitude, head longitude at frame 1 (deg; the front of the globe faces -90),
# direction (+1 carries the front of the globe to the right), whole turns per loop, tail (arc length), strength.
BAND_PULSES = [
    (0, -40.0, 1, 2, 1.10, 1.12),
    (0, 112.0, -1, 3, 0.85, 1.00),
    (20, -160.0, -1, 2, 0.78, 0.80),
    (-20, -128.0, -1, 1, 0.72, 0.95),
    (40, -48.0, 1, 1, 0.62, 0.90),
    (-40, -108.0, 1, 2, 0.62, 0.72),
    (60, -150.0, -1, 1, 0.46, 0.66),
]
PULSE_FAR = 0.1

# Pulses running through the crescents: crescent, head angle at frame 1 (deg, in the crescent's own frame, 0 =
# its widest point), direction, whole turns per loop relative to the crescent, tail (radians), strength.
SWEEP_PULSES = [
    ("Outer", 42.0, 1, 2, 1.05, 1.15),
    ("Inner", -34.0, -1, 3, 1.25, 1.00),
]

# name, radius, span (deg), tilt (deg; + = seen from above, near side low), screen angle (deg, ccw),
# peak bevel, strength, orbit direction
SWEEPS = [
    ("Outer", 0.80, 220, 26, 32, 0.019, 1.30, 1),
    ("Inner", 0.46, 210, -32, 45, 0.014, 1.30, -1),
]

# HUD readouts printed on the front of the sphere: name, centre latitude and longitude (deg, globe space), layout.
READOUTS = [
    ("A", 50.0, -128.0, "text"),
    ("B", 50.0, -57.0, "graph"),
    ("C", -8.0, -121.0, "list"),
    ("D", -10.5, -57.0, "wave"),
]

READOUT_SCALE = 1.4     # layouts are drawn in arc degrees, then scaled up to hold at phone size
RING_R = 1.165          # the measuring ring's outer hairline (the tick band sits inside it)


def build_globe(parent, rng):
    """The sphere: latitude bands tilted toward the viewer so they open into nested ellipses, held by two faint
    meridians. Each band turns by its own symmetry sector per loop, alternating direction like orrery gears."""
    globe = empty("Globe", parent)
    globe.rotation_euler = (math.radians(GLOBE_TILT), 0.0, 0.0)
    spinners, bands = [], {}
    for i, (lat, symmetry, dash, strength, bevel) in enumerate(BANDS):
        phi = math.radians(lat)
        near = NEAR_EQ if lat == 0 else NEAR_BAND
        mat = emissive(f"Band{lat:+d}", near, strength, far_gain=BAND_FAR, facing=0.5, clear=CLEAR, far_color=EMBER)
        phase, sector, base = dash_sector(rng, symmetry, *dash)
        splines = []
        for s, e in replicate(phase, sector, base, symmetry):
            pts = arc(SPHERE_R * math.cos(phi), SPHERE_R * math.sin(phi), s, e, 0.75)
            splines.append((pts, dash_radii(len(pts), 4)))
        band = curve_object(f"Band{lat:+d}", splines, bevel, mat, globe)
        if lat == BLUE_BAND:
            build_blue_dashes(band, lat, phase, sector, base, symmetry, bevel)
        direction = 1 if i % 2 == 0 else -1
        spinners.append((band, direction * FULL / symmetry))
        bands[lat] = band
    build_meridians(globe)
    return globe, spinners, bands


def build_blue_dashes(band, lat, phase, sector, base, symmetry, bevel):
    """A whisper of electric blue: one short dash set into the widest gap of each sector of this band."""
    gaps = [(base[i][1], base[i + 1][0]) for i in range(len(base) - 1)] + [(base[-1][1], sector + base[0][0])]
    g0, g1 = max(gaps, key=lambda g: g[1] - g[0])
    length = min(6.5, g1 - g0 - 3.0)
    if length < 2.0:
        return None
    mid = (g0 + g1) / 2
    phi = math.radians(lat)
    splines = []
    for k in range(symmetry):
        s = math.radians(phase + mid - length / 2 + k * sector)
        e = math.radians(phase + mid + length / 2 + k * sector)
        pts = arc(SPHERE_R * math.cos(phi), SPHERE_R * math.sin(phi), s, e, 0.5)
        splines.append((pts, dash_radii(len(pts), 3)))
    mat = emissive(f"{band.name}.blue", BLUE, 0.6, far_gain=BAND_FAR, facing=0.5, clear=CLEAR)
    return curve_object(f"{band.name}.blue", splines, bevel, mat, band)


def build_meridians(globe):
    """Two very faint meridian hairlines that lock the bands into reading as latitudes (static, so seamless)."""
    splines = []
    for lon in MERIDIANS:
        L = math.radians(lon)
        pts = [sph(SPHERE_R, t, L) for t in steps(math.radians(-84), math.radians(84), 0.75)]
        splines.append((pts, dash_radii(len(pts), 14)))
    mat = emissive("Meridian", AMBER, 0.18, far_gain=BAND_FAR, facing=0.5, clear=CLEAR, far_color=EMBER)
    return curve_object("Meridians", splines, 0.0018, mat, globe)


def comet(name, parent, radius, height, tail, direction, bevel, mat, bead_r, bead_mat, nose_deg=1.6):
    """A comet stroke in `parent`'s XY plane: head at local angle 0, tail trailing against `direction`."""
    angles = steps(-direction * tail, 0.0, 0.4)
    pts = [Vector((radius * math.cos(a), radius * math.sin(a), height)) for a in angles]
    stroke = curve_object(name, [(pts, comet_radii(angles, tail, math.radians(nose_deg)))], bevel, mat, parent)
    if bead_mat is not None:
        uv_sphere(f"{name}.head", bead_r, bead_mat, parent, 24, 12, location=(radius, 0.0, height))
    return stroke


def add_wake(mat, spin, tail, direction, gain, color=WAKE, power=2.2, lead_soft_deg=1.2):
    """Light up an existing stroke behind a passing pulse. `spin` carries the pulse head at its local angle 0, so
    the stroke's own points, measured in the pulse's frame, say how far behind the head they are: the dashes flare
    hot gold as the head passes and cool back down along the tail. Works while both turn at different speeds."""
    nt = mat.node_tree
    em = next(n for n in nt.nodes if n.type == "EMISSION")
    lead = _math(nt, "MULTIPLY", _local_angle(nt, spin), float(direction))   # > 0 ahead of the head
    t = _math(nt, "MULTIPLY_ADD", lead, 1.0 / tail, 1.0, clamp=True)
    front = nt.nodes.new("ShaderNodeMapRange")
    front.clamp = True
    nt.links.new(lead, front.inputs[0])
    front.inputs[1].default_value = 0.0
    front.inputs[2].default_value = math.radians(lead_soft_deg)
    front.inputs[3].default_value = 1.0
    front.inputs[4].default_value = 0.0
    w = _math(nt, "MULTIPLY", _math(nt, "POWER", t, power), front.outputs[0])

    s_in = em.inputs["Strength"]
    old = s_in.links[0].from_socket if s_in.is_linked else float(s_in.default_value)
    nt.links.new(_math(nt, "MULTIPLY", _math(nt, "MULTIPLY_ADD", w, gain, 1.0), old), s_in)

    c_in = em.inputs["Color"]
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    sock = {s.identifier: s for s in mix.inputs}
    if c_in.is_linked:
        nt.links.new(c_in.links[0].from_socket, sock["A_Color"])
    else:
        sock["A_Color"].default_value = tuple(c_in.default_value)
    sock["B_Color"].default_value = (*color, 1.0)
    nt.links.new(_math(nt, "MULTIPLY", w, 0.9), sock["Factor_Float"])
    nt.links.new(next(s for s in mix.outputs if s.identifier == "Result_Color"), c_in)


WAKE_GAIN = 1.9


def build_band_pulses(globe, bands):
    """Hot comets riding the latitude bands. Each hangs on its own empty that turns about the globe's axis by whole
    turns per loop, so the loop is seamless. A pulse is three things: the band's own dashes flaring behind it (the
    wake), a fine filament that bridges the gaps, and a cream-gold head with a soft halo. On the far side all of
    it fades to deep amber like the bands."""
    spinners = []
    for i, (lat, lon, direction, turns, length, strength) in enumerate(BAND_PULSES):
        phi = math.radians(lat)
        r, h = SPHERE_R * math.cos(phi) * 1.003, SPHERE_R * math.sin(phi) * 1.003
        tail = length / r
        spin = empty(f"Pulse{i}", globe)
        spin.rotation_euler = (0.0, 0.0, math.radians(lon))
        add_wake(bands[lat].data.materials[0], spin, tail * 1.1, direction, WAKE_GAIN * strength)
        bevel = 0.0075 if lat == 0 else 0.0062
        mat = pulse_material(f"Pulse{i}", tail, direction, 1.5 * strength, far_gain=PULSE_FAR, power=1.8)
        bead = bead_material(f"Pulse{i}.head", 0.95 * strength, far_gain=PULSE_FAR, clear=PULSE_CLEAR)
        comet(f"Pulse{i}.stroke", spin, r, h, tail, direction, bevel, mat, 0.0105, bead)
        halo = bead_material(f"Pulse{i}.halo", 0.38 * strength, far_gain=PULSE_FAR, clear=PULSE_CLEAR,
                             inner=GOLD, outer=AMBER, falloff=2.6)
        glow = uv_sphere(f"Pulse{i}.halo", 0.03, halo, spin, 24, 12, location=(r, -direction * 0.028, h))
        glow.scale = (1.0, 2.6, 1.0)
        spinners.append((spin, direction * turns * FULL))
    return spinners


def build_sweeps(parent):
    """Two bold crescents, each orbiting in its own inclined plane; their widest, brightest part faces the viewer.
    The main crescent carries a fine companion hairline just inside it."""
    sweeps = empty("Sweeps", parent)
    spinners, strokes = [], {}
    for name, r, span, tilt, screen, bevel, strength, direction in SWEEPS:
        holder = empty(f"Sweep.{name}", sweeps)
        holder.rotation_euler = (math.radians(tilt), math.radians(-screen), 0.0)
        span_r = math.radians(span)
        pts = arc(r, 0.0, -span_r / 2, span_r / 2, 0.5)
        mat = emissive(f"Sweep.{name}", SWEEP, strength, far_gain=0.3, facing=1.0, arc=(span_r, 1.2, 0.0), window=SWEEP_FADE)
        stroke = curve_object(f"Sweep.{name}.stroke", [(pts, crescent_radii(len(pts)))], bevel, mat, holder)
        stroke.rotation_euler = (0.0, 0.0, -math.pi / 2)
        spinners.append((stroke, direction * FULL))
        strokes[name] = (stroke, r, span_r, direction)
        if name == "Outer":
            comp_span = math.radians(176)
            cpts = arc(r - 0.034, 0.0, -comp_span / 2 + math.radians(10), comp_span / 2 + math.radians(10), 0.5)
            cmat = emissive("Sweep.Outer.companion", GOLD, 1.0, far_gain=0.3, facing=0.5,
                            arc=(math.radians(200), 1.0, 0.0), window=SWEEP_FADE)
            curve_object("Sweep.Outer.companion", [(cpts, dash_radii(len(cpts), 30))], 0.0019, cmat, stroke)
    return sweeps, spinners, strokes


def build_sweep_pulses(strokes):
    """A comet running through each crescent. It rides on an empty parented to the crescent, turning whole turns
    per loop relative to it, and takes the crescent's taper so it appears at one tip and dies at the other."""
    spinners = []
    for name, angle, direction, turns, tail, strength in SWEEP_PULSES:
        stroke, r, span_r, _ = strokes[name]
        spin = empty(f"{stroke.name}.pulse", stroke)
        spin.rotation_euler = (0.0, 0.0, math.radians(angle))
        host_arc = (span_r, 0.9, 0.0)
        add_wake(stroke.data.materials[0], spin, tail * 1.1, direction, 0.42 * strength)
        mat = pulse_material(f"{name}.pulse", tail, direction, 0.85 * strength, far_gain=0.35, window=SWEEP_FADE,
                             clear=None, host=stroke, host_arc=host_arc, facing=0.6)
        bead = bead_material(f"{name}.pulse.head", 0.8 * strength, far_gain=0.35, window=SWEEP_FADE,
                             host=stroke, host_arc=host_arc)
        comet(f"{name}.pulse.stroke", spin, r, 0.0, tail, direction, 0.0075 if name == "Outer" else 0.0064,
              mat, 0.0125, bead)
        halo = bead_material(f"{name}.pulse.halo", 0.32 * strength, far_gain=0.35, window=SWEEP_FADE,
                             host=stroke, host_arc=host_arc, inner=GOLD, outer=AMBER, falloff=2.6)
        glow = uv_sphere(f"{name}.pulse.halo", 0.034, halo, spin, 24, 12, location=(r, -direction * 0.03, 0.0))
        glow.scale = (1.0, 2.6, 1.0)
        spinners.append((spin, direction * turns * FULL))
    return spinners


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
            loose.append((rand_dir() * SPHERE_R * rng.uniform(0.98, 1.05), 0.005, 0.9, 1.0 if i == 3 else 0.0))
            continue
        loose.append((rand_dir() * SPHERE_R * rng.uniform(0.97, 1.07), rng.uniform(0.003, 0.0055), 0.12 + 0.8 * rng.random() ** 3, 0.0))
    for i in range(9):
        if i == 4:
            loose.append((rand_dir() * rng.uniform(0.5, 0.7), 0.0045, 0.8, 1.0))
            continue
        loose.append((rand_dir() * rng.uniform(0.24, 0.72), rng.uniform(0.0025, 0.0045), 0.12 + 0.6 * rng.random() ** 2, 0.0))
    spark_mesh("Sparks", loose, mat, globe)

    for key in ("Outer", "Inner"):
        stroke, r, span, _ = strokes[key]
        riders = []
        for _ in range(5):
            a = rng.uniform(-0.38, 0.38) * span
            rr = r + rng.uniform(-0.04, 0.05)
            riders.append((Vector((rr * math.cos(a), rr * math.sin(a), rng.uniform(-0.03, 0.03))), rng.uniform(0.003, 0.005), 0.3 + 0.9 * rng.random() ** 2, 0.0))
        spark_mesh(f"{stroke.name}.sparks", riders, mat, stroke)


# ---------- readouts ----------

class Patch:
    """Arc-degree coordinates (x east, y north) around an anchor on the sphere, so marks lie on its surface."""

    def __init__(self, lat, lon, radius=1.004):
        self.lat, self.lon, self.r = math.radians(lat), math.radians(lon), radius

    def _latlon(self, x, y):
        la = self.lat + math.radians(y)
        return la, self.lon + math.radians(x) / math.cos(la)

    def at(self, x, y):
        return sph(self.r, *self._latlon(x, y))

    def line(self, x0, y0, x1, y1, step=0.2):
        n = max(2, int(max(abs(x1 - x0), abs(y1 - y0)) / step) + 1)
        return [self.at(x0 + (x1 - x0) * i / (n - 1), y0 + (y1 - y0) * i / (n - 1)) for i in range(n)]

    def basis(self, x, y):
        """Location plus a rotation whose X is east, Y north and Z the outward normal."""
        la, lo = self._latlon(x, y)
        n = Vector((math.cos(la) * math.cos(lo), math.cos(la) * math.sin(lo), math.sin(la)))
        e = Vector((-math.sin(lo), math.cos(lo), 0.0))
        north = n.cross(e)
        rot = Matrix((e, north, n)).transposed().to_euler()
        return n * self.r, rot


def glyph_row(rng, x0, width, y, p_long=0.6):
    """Dashes that read as a line of text or tokens without being text: word-length and letter-length marks."""
    segs, x = [], x0
    while True:
        length = rng.uniform(0.9, 2.5) if rng.random() < p_long else rng.uniform(0.3, 0.65)
        if x + length > x0 + width:
            break
        segs.append((x, y, x + length, y))
        x += length + rng.uniform(0.42, 0.62)
    return segs


def bracket(x, y, sx, sy, leg=0.9):
    """A corner mark at (x, y) whose legs run toward sx, sy (+1/-1)."""
    return [(x, y, x + sx * leg, y), (x, y, x, y + sy * leg * 0.8)]


def layout(kind, rng):
    """Marks in arc degrees: tiers 'hi' (headers, bullets), 'body' (glyph rows), 'faint' (rules, tracks),
    'hot' (one accent), 'frame' (corner brackets) and 'bars' (x, y, max height, highlighted, centred, steps per
    loop) for the animated bars."""
    t = {"hi": [], "body": [], "faint": [], "hot": [], "frame": [], "bars": []}
    if kind == "text":
        # a header, a hairline rule, then three ragged rows: reads as a paragraph without being text
        t["hi"] += glyph_row(rng, 0.0, 6.2, 0.0, 0.8)
        t["hot"].append((6.9, 0.0, 7.35, 0.0))
        t["faint"].append((0.0, -0.75, 8.6, -0.75))
        for i, w in enumerate((8.6, 7.4, 5.2)):
            t["body"] += glyph_row(rng, 0.0, w, -1.55 * (i + 1) - 0.1)
        t["frame"] += bracket(-0.8, 0.9, 1, -1) + bracket(9.3, -5.5, -1, 1)
    elif kind == "graph":
        # a histogram of token likelihoods: bars on a baseline, one highlighted, a label above
        t["faint"].append((-0.2, 0.0, 6.9, 0.0))
        for i in range(9):
            t["bars"].append((0.35 + 0.78 * i, 0.3, rng.uniform(0.9, 3.2), i == 6, False, 40))
        t["hi"] += glyph_row(rng, 0.0, 4.4, 4.3, 0.7)
        t["frame"] += bracket(-0.8, 5.2, 1, -1) + bracket(7.6, -0.9, -1, 1)
        for i in range(0, 10, 3):
            x = 0.35 + 0.78 * i - 0.39
            t["faint"].append((x, -0.25, x, -0.6))
    elif kind == "list":
        for i, w in enumerate((6.8, 4.9, 6.0)):
            y = -1.55 * i
            (t["hot"] if i == 0 else t["hi"]).append((0.0, y, 0.42, y))
            t["body"] += glyph_row(rng, 1.1, w, y)
        t["faint"].append((-0.75, 0.55, -0.75, -3.65))
    elif kind == "wave":
        # the voice: a small symmetric waveform on a centre line that keeps changing while the loop plays
        t["hi"] += glyph_row(rng, 0.0, 4.2, 2.5, 0.7)
        t["faint"].append((-0.4, 0.0, 10.2, 0.0))
        for i in range(14):
            env = math.sin(math.pi * (i + 0.5) / 14) ** 0.8
            t["bars"].append((0.2 + 0.72 * i, 0.0, (0.7 + 2.5 * env) * rng.uniform(0.65, 1.0), i == 8, True, 80))
        t["frame"] += bracket(-1.0, 1.9, 1, -1) + bracket(10.8, -1.9, -1, 1)
    return t


def build_readouts(globe, rng):
    """Four small HUD clusters printed on the front of the sphere (static in globe space, so the bands turn under
    them like an instrument overlay). The bar graph steps through heights over the loop."""
    tiers = {
        "hi": (0.0024, emissive("Readout.hi", GOLD, 1.1, facing=0.25)),
        "body": (0.0021, emissive("Readout.body", AMBER, 0.8, facing=0.25)),
        "faint": (0.0016, emissive("Readout.faint", DEEP, 0.42, facing=0.25)),
        "hot": (0.0028, emissive("Readout.hot", HOT, 1.25, facing=0.25)),
        "frame": (0.0018, emissive("Readout.frame", GOLD, 0.75, facing=0.25)),
    }
    bar_mat = emissive("Readout.bar", GOLD, 0.95, facing=0.25)
    bar_hot = emissive("Readout.bar.hot", HOT, 1.25, facing=0.25)
    k = READOUT_SCALE
    bars = []
    for name, lat, lon, kind in READOUTS:
        marks = layout(kind, rng)
        xs = [v for key in ("hi", "body", "faint", "hot", "frame") for s in marks[key] for v in (s[0], s[2])]
        ys = [v for key in ("hi", "body", "faint", "hot", "frame") for s in marks[key] for v in (s[1], s[3])]
        xs += [b[0] for b in marks["bars"]]
        for x, y, hmax, _, centred, _ in marks["bars"]:
            ys += [y - hmax / 2, y + hmax / 2] if centred else [y, y + hmax]
        cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
        patch = Patch(lat, lon)
        holder = empty(f"Readout.{name}", globe)
        for key, (bevel, mat) in tiers.items():
            if not marks[key]:
                continue
            splines = [(patch.line((x0 - cx) * k, (y0 - cy) * k, (x1 - cx) * k, (y1 - cy) * k), None)
                       for x0, y0, x1, y1 in marks[key]]
            curve_object(f"Readout.{name}.{key}", splines, bevel, mat, holder)
        for j, (x, y, hmax, hot, centred, n_steps) in enumerate(marks["bars"]):
            loc, rot = patch.basis((x - cx) * k, (y - cy) * k)
            ends = [Vector((0, -0.5, 0)), Vector((0, 0.5, 0))] if centred else [Vector((0, 0, 0)), Vector((0, 1, 0))]
            bar = curve_object(f"Readout.{name}.bar{j}", [(ends, None)],
                               0.0034 if hot else 0.0030, bar_hot if hot else bar_mat, holder)
            bar.location, bar.rotation_euler = loc, rot
            unit = math.radians(1.0) * patch.r * k
            level, seq = rng.uniform(0.45, 1.0), []
            for _ in range(n_steps):
                level = min(1.0, max(0.22, level + rng.uniform(-0.35, 0.35) * (0.5 if rng.random() < 0.5 else 1.0)))
                seq.append(level * hmax * unit)
            seq[0] = (0.5 + 0.5 * math.sin(j * 1.7 + 0.4)) * 0.75 * hmax * unit + 0.25 * hmax * unit
            bar.scale = (1.0, seq[0], 1.0)
            bars.append((bar, seq))
    return bars


# ---------- the heart ----------

def build_core(parent, breathe):
    """The arc-reactor heart, 1.5x: a cream-gold core, ten coils and a rim, a tick bezel turning against the
    coils, a new segmented ring turning against the bezel, one small gyro ring on its own axis, a soft corona."""
    s = CORE_SCALE
    core = empty("Core", parent)
    uv_sphere("Core.heart", 0.058 * s, halo_material("Heart", HEART, GOLD, 0.66, 1.3, breathe), core, 32, 16)
    uv_sphere("Core.glow", 0.19 * s, halo_material("Glow", GOLD, AMBER, 0.25, 3.5, breathe), core)
    uv_sphere("Core.corona", 0.40 * s, halo_material("Corona", GOLD, AMBER, 0.028, 5.0, breathe), core)
    uv_sphere("Core.aura", 0.62, halo_material("Aura", AMBER, AMBER, 0.012, 4.5), core)

    reactor = frame("Reactor", core, REACTOR_NORMAL)
    coils = [(math.radians(36 * k + 3), math.radians(36 * k + 33)) for k in range(10)]
    plates("Reactor.coils", coils, 0.098 * s, 0.142 * s, emissive("Reactor.coils", REACTOR, 1.0), reactor)
    curve_object("Reactor.rim", [(ring(0.162 * s), None)], 0.0018, emissive("Reactor.rim", REACTOR, 0.9), reactor, closed=True)

    bezel = frame("Bezel", core, REACTOR_NORMAL)
    ticks = [(radial(0.182 * s, (0.2 if i % 3 == 0 else 0.192) * s, FULL * i / 36), None) for i in range(36)]
    curve_object("Bezel.ticks", ticks, 0.0015, emissive("Bezel", AMBER, 0.55), bezel)

    # new: a segmented ring of long and short cells (one pattern per quadrant), turning against the bezel
    segring = frame("Segring", core, REACTOR_NORMAL)
    cells = []
    for k in range(4):
        o = 90 * k
        cells += [(math.radians(o + a), math.radians(o + b)) for a, b in ((3, 41), (46, 59), (63, 67), (71, 86))]
    plates("Segring.cells", cells, 0.216 * s, 0.229 * s, emissive("Segring", REACTOR, 0.62), segring)

    gyro = frame("Gyro", core, GYRO_NORMAL)
    dashes = [(arc(0.262 * s, 0.0, math.radians(45 * k + 4), math.radians(45 * k + 31), 0.75), None) for k in range(8)]
    curve_object("Gyro.dashes", dashes, 0.0024, emissive("Gyro", AMBER, 0.66, far_gain=0.35, window=(0.26, 0.26)), gyro)
    # alternating from the centre out, each by whole symmetry sectors per loop
    return [(reactor, -FULL / 10), (bezel, FULL / 12), (segring, -FULL / 4), (gyro, FULL / 8)]


# ---------- the measuring ring ----------

def rim_material(name, color, strength, power):
    """Fresnel glow: nothing where the sphere faces the viewer, a soft line of light at its silhouette."""
    m, nt, em = _base_material(name)
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.5
    em.inputs["Color"].default_value = (*color, 1.0)
    nt.links.new(_math(nt, "MULTIPLY", _math(nt, "POWER", lw.outputs["Facing"], power), strength), em.inputs["Strength"])
    return m


def build_rim(globe):
    """A thin deep-amber atmosphere at the globe's silhouette, so it reads as a sphere of light, not a flat disc."""
    return uv_sphere("Globe.rim", SPHERE_R * 1.004, rim_material("Rim", AMBER, RIM_STRENGTH, RIM_POWER), globe, 96, 48)


RIM_STRENGTH = 0.045
RIM_POWER = 16.0


def build_hud_ring(parent):
    """A double measuring ring facing the viewer: an outer hairline with brighter active arcs, and an inner tick
    band (minor every 2 deg, major every 10, cardinal every 90). The ring turns slowly against the globe; a single
    bright marker orbits the other way along the hairline."""
    holder = empty("HudRing", parent)
    holder.rotation_mode = "QUATERNION"
    holder.rotation_quaternion = facing_quat()
    spin = empty("HudRing.spin", holder)
    curve_object("HudRing.line", [(ring(RING_R, 0.4), None)], 0.0015, emissive("HudLine", DEEP, 0.2), spin, closed=True)
    minor, major, cardinal = [], [], []
    for i in range(180):
        a = FULL * i / 180
        if i % 45 == 0:
            cardinal.append((radial(1.066, 1.128, a), None))
        elif i % 5 == 0:
            major.append((radial(1.078, 1.112, a), None))
        else:
            minor.append((radial(1.078, 1.094, a), None))
    curve_object("HudRing.minor", minor, 0.0014, emissive("HudMinor", DEEP, 0.2), spin)
    curve_object("HudRing.major", major, 0.0017, emissive("HudMajor", GOLD, 0.34), spin)
    curve_object("HudRing.cardinal", cardinal, 0.0022, emissive("HudCardinal", GOLD, 0.62), spin)
    bright, soft = [], []
    for k in range(4):
        o = 90 * k
        bright.append((arc(RING_R, 0.0, math.radians(o + 12), math.radians(o + 36), 0.4), None))
        soft.append((arc(RING_R, 0.0, math.radians(o + 57), math.radians(o + 61), 0.4), None))
        soft.append((arc(1.058, 0.0, math.radians(o + 66), math.radians(o + 79), 0.4), None))
    curve_object("HudRing.arcs", bright, 0.0026, emissive("HudArc", GOLD, 0.62), spin)
    curve_object("HudRing.arcs2", soft, 0.0019, emissive("HudArc2", GOLD, 0.42), spin)

    marker = empty("HudRing.marker", holder)
    marker.rotation_euler = (0.0, 0.0, math.radians(58))
    tail = math.radians(24)
    comet("HudRing.marker.tail", marker, RING_R, 0.0, tail, 1, 0.0036,
          pulse_material("HudMarker", tail, 1, 1.6, clear=None, facing=0.3), 0.0085,
          bead_material("HudMarker.head", 1.2))
    curve_object("HudRing.marker.needle", [(radial(1.062, 1.14, 0.0), None)], 0.0024,
                 emissive("HudNeedle", HOT, 1.05), marker)
    return [(spin, -FULL / 4), (marker, FULL)]


# ---------- assembly ----------

def build(seed):
    rng = random.Random(seed)          # the owner's layout: same sequence as presence_final
    rng2 = random.Random(seed * 7919 + 3)  # everything new
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene

    root = bpy.data.objects.new("Presence", None)
    scene.collection.objects.link(root)

    globe, spinners, bands = build_globe(root, rng)
    _, sweep_spinners, strokes = build_sweeps(root)
    spinners += sweep_spinners
    build_sparks(globe, strokes, rng)
    breathe = []
    spinners += build_core(root, breathe)
    build_rim(globe)
    spinners += build_hud_ring(root)
    spinners += build_band_pulses(globe, bands)
    spinners += build_sweep_pulses(strokes)
    bars = build_readouts(globe, rng2)
    return scene, spinners, bars, breathe


def _fcurves(idblock):
    ad = idblock.animation_data
    if not ad or not ad.action:
        return []
    try:
        return list(ad.action.fcurves)
    except AttributeError:
        from bpy_extras import anim_utils
        bag = anim_utils.action_get_channelbag_for_slot(ad.action, ad.action_slot)
        return list(bag.fcurves) if bag else []


def _set_interp(idblock, mode):
    for fc in _fcurves(idblock):
        for kp in fc.keyframe_points:
            kp.interpolation = mode


def animate(scene, spinners, bars, breathe, seconds, fps):
    """Each part turns by whole symmetry sectors (or whole turns) per loop with LINEAR keys, so the last frame
    meets the first without easing. The bar graph steps (CONSTANT keys on a grid that ends where it began), and
    the heart breathes twice per loop (smooth keys whose ends are both at rest, so the seam stays invisible)."""
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
        _set_interp(ob, "LINEAR")
    for ob, seq in bars:
        n = len(seq)
        for i, h in enumerate(seq + [seq[0]]):
            ob.scale[1] = h
            ob.keyframe_insert(data_path="scale", index=1, frame=1 + round(i * frames / n))
        ob.scale[1] = seq[0]
        _set_interp(ob, "CONSTANT")
    for mat, node in breathe:
        sock = node.outputs[0]
        for i, v in enumerate((1.0, 1.14, 1.0, 1.14, 1.0)):
            sock.default_value = v
            sock.keyframe_insert("default_value", frame=1 + round(i * frames / 4))
        sock.default_value = 1.0
    scene.frame_set(1)


def use_gpu(scene):
    """Metal on the Mac. A build without Metal (Linux, the bpy module in the cloud) renders on the CPU."""
    prefs = bpy.context.preferences.addons["cycles"].preferences
    try:
        prefs.compute_device_type = "METAL"
    except TypeError:
        scene.cycles.device = "CPU"
        print("DEVICE CPU")
        return
    prefs.get_devices()
    for d in prefs.devices:
        d.use = True
    scene.cycles.device = "GPU"
    print("DEVICE GPU", [d.name for d in prefs.devices])


def setup_render(scene, res, samples):
    scene.render.engine = "CYCLES"
    use_gpu(scene)
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

    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.35
    scene.view_settings.gamma = 1.0

    cam_data = bpy.data.cameras.new("Camera")
    cam_data.lens = LENS
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


# (threshold, strength, size) per glare pass, applied in sequence
BLOOM = [(0.2, 0.34, 0.28), (0.9, 0.3, 0.5), (1.1, 0.26, 0.6)]
BLACK_LEVEL = 0.006


def setup_bloom(scene, passes=None, black=None):
    """A tight halation on the lines, a medium glow for the crescents and pulses, and a wide, strong bloom that
    only the heart and the pulse heads reach. A small black level afterwards pulls the faint bloom tail back to
    true black (the app Screen-blends this over its stage)."""
    tree = bpy.data.node_groups.new("PresenceComposite", "CompositorNodeTree")
    tree.interface.new_socket(name="Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    layers = tree.nodes.new("CompositorNodeRLayers")
    out = tree.nodes.new("NodeGroupOutput")
    curves = tree.nodes.new("CompositorNodeCurveRGB")
    b = BLACK_LEVEL if black is None else black
    curves.inputs["Black Level"].default_value = (b, b, b, 1.0)
    src = layers.outputs["Image"]
    for threshold, strength, size in passes or BLOOM:
        node = _glare(tree, threshold, strength, size)
        tree.links.new(src, node.inputs["Image"])
        src = node.outputs["Image"]
    tree.links.new(src, curves.inputs["Image"])
    tree.links.new(curves.outputs["Image"], out.inputs[0])
    scene.compositing_node_group = tree
    print("BLOOM", passes or BLOOM)


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
    scene, spinners, bars, breathe = build(a.seed)
    setup_render(scene, a.res, a.samples)
    if not a.no_bloom:
        passes = [tuple(float(v) for v in p.split(",")) for p in a.bloom.split(";")] if a.bloom else None
        setup_bloom(scene, passes, a.black)
    animate(scene, spinners, bars, breathe, a.seconds, a.fps)
    prepare_viewport()
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(a.out, "presence.blend"))
    if a.no_render:
        return
    if a.animation:
        scene.render.image_settings.media_type = "VIDEO"
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
