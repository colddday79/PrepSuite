"""PrepSuite presence, Gold Radiance: the final orrery globe given a body of light and a majestic heart.

Same globe as presence_final.py (hairline latitude bands of long dashes with depth fade, faint meridians, two
tapered gold crescents, an arc-reactor heart, a few data blocks, an outer tick ring), pushed toward radiance:

* Body of light: nested facing-lit halo shells fill the sphere with a soft gold atmosphere, brightest round the
  heart and falling away outward, and a thin fresnel limb lights the silhouette like a planet's atmosphere,
  brighter on the upper left for form.
* Majestic heart: about twice its former size on screen and layered like an instrument: a hot cream-gold heart
  in a strong glow, ten coils, a fine 96-tick bezel, an outer segmented collar, two thin counter-rotating gyro
  rings at slight tilts, and a corona of faint tapered light rays.
* Richer crescents: each gains a parallel companion hairline, a warm glow sheath and tips that break into sparks.
* Bands a little thicker and brighter in front, shading from deep amber behind to pale gold in front.
* Tighter frame: the globe fills ~80% of the square; the tick ring stays inside the edge.

Run headless:
    Blender -b --factory-startup --python-exit-code 1 --python gold_radiance.py -- [options]

Options: --out DIR  --res PX  --samples N  --frame F  --animation  --seconds S  --fps N  --still NAME  --no-render
Writes presence.blend (open it in Blender to orbit the model) and a PNG still or an MP4 loop.
Every moving part turns by a whole symmetry sector per loop (the crescents by one full orbit) with LINEAR keys,
so any loop length is seamless.
"""

import argparse
import math
import os
import random
import sys

import bpy
from mathutils import Quaternion, Vector

OUT_DEFAULT = "/Users/macintosh/Documents/PrepSuite/tools/blender/out/models/gold_radiance"

# Scene-linear colours, graded with the Standard view transform. Red clips first, so a bright line shows a pale
# gold centre and gold edges; what decides the displayed centre is green x intensity. Lines that peak above ~1.4
# (bands, crescents, fine highlights) therefore use orange ratios (LINE, SWEEP) so they land on pale gold, and
# only the heart is allowed enough green and blue to reach cream. Dim glows use the GOLD/AMBER ratios directly.
GOLD = (1.0, 0.56, 0.13)
PALE = (1.0, 0.62, 0.19)      # pale gold for dim light (limb, heart glow)
LINE = (1.0, 0.41, 0.075)     # bright near-side lines: displays pale gold at their peak
SWEEP = (1.0, 0.47, 0.092)
EMBER = (1.0, 0.40, 0.06)     # warm crescent sheath
EQUATOR = (1.0, 0.40, 0.072)
AMBER = (1.0, 0.40, 0.065)
DEEP = (1.0, 0.32, 0.045)     # far-side deep amber
HOT = (1.0, 0.62, 0.24)
CREAM = (1.0, 0.69, 0.33)
REACTOR = (1.0, 0.60, 0.16)
BLUE = (0.08, 0.45, 1.0)

CAM_LOC = Vector((0.0, -4.6, 0.25))
SPHERE_R = 1.0
FULL = 2 * math.pi
GLOBE_FILL = 0.80             # silhouette diameter as a fraction of the square frame

# Depth windows (camera distance either side of the sphere centre). Globe lines hold full strength across the
# face of the sphere and fade toward the silhouette and the far side; the crescents fade more gently.
GLOBE_FADE = (0.62, 0.18)
SWEEP_FADE = (0.35, 0.45)

# Globe lines that pass in front of or behind the heart dim inside this aperture (distance from the view axis),
# so the heart always has clear air around it: (fully dimmed within, full strength beyond, dimmed level).
CLEAR = (0.30, 0.46, 0.14)

REACTOR_NORMAL = (0.30, -0.85, 0.42)
GYRO_NORMAL = (0.163, -0.62, 0.768)
LIGHT_DIR = (-0.62, -0.25, 0.74)   # the limb is brightest on the upper left, facing slightly toward the viewer


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


def _math(nt, op, *args):
    n = nt.nodes.new("ShaderNodeMath")
    n.operation = op
    for i, v in enumerate(args):
        if isinstance(v, (int, float)):
            n.inputs[i].default_value = float(v)
        else:
            nt.links.new(v, n.inputs[i])
    return n.outputs[0]


def _smooth(nt, value, a, b, lo=0.0, hi=1.0):
    """Smoothstep map of `value` from [a, b] to [lo, hi], clamped."""
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.interpolation_type = "SMOOTHSTEP"
    mr.clamp = True
    nt.links.new(value, mr.inputs[0])
    mr.inputs[1].default_value = a
    mr.inputs[2].default_value = b
    mr.inputs[3].default_value = lo
    mr.inputs[4].default_value = hi
    return mr.outputs[0]


def _mix_rgb(nt, fac, a, b):
    """Colour `a` at fac 0, `b` at fac 1."""
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    sock = {s.identifier: s for s in mix.inputs}
    sock["A_Color"].default_value = (*a, 1.0)
    sock["B_Color"].default_value = (*b, 1.0)
    if isinstance(fac, (int, float)):
        sock["Factor_Float"].default_value = float(fac)
    else:
        nt.links.new(fac, sock["Factor_Float"])
    return next(s for s in mix.outputs if s.identifier == "Result_Color")


def _nearness(nt, window):
    """1.0 nearer than (centre - near_w), 0.0 beyond (centre + far_w), smooth in between."""
    cam = nt.nodes.new("ShaderNodeCameraData")
    d = CAM_LOC.length
    return _smooth(nt, cam.outputs["View Distance"], d - window[0], d + window[1], 1.0, 0.0)


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
    return _smooth(nt, length.outputs["Value"], r0, r1, floor, 1.0)


def _arc_factor(nt, span, power, floor):
    """For an arc centred on local +X: full strength mid-arc, fading to `floor` at both tips."""
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs[0])
    ang = _math(nt, "ARCTAN2", sep.outputs["Y"], sep.outputs["X"])
    c = _math(nt, "MAXIMUM", _math(nt, "COSINE", _math(nt, "MULTIPLY", ang, math.pi / span)), 0.0)
    return _math(nt, "MULTIPLY_ADD", _math(nt, "POWER", c, power), 1.0 - floor, floor)


def _radius(nt):
    """Distance from the object's own origin."""
    tc = nt.nodes.new("ShaderNodeTexCoord")
    ln = nt.nodes.new("ShaderNodeVectorMath")
    ln.operation = "LENGTH"
    nt.links.new(tc.outputs["Object"], ln.inputs[0])
    return ln.outputs["Value"]


def emissive(name, color, strength, far_gain=None, facing=None, arc=None, window=GLOBE_FADE, clear=None,
             far_color=None, fade=None, outer_color=None):
    """Emission + transparency. `far_color` shades the colour toward the far side (depth); `fade` is a radial
    window (r_in0, r_in1, r_out, power) in object space; `outer_color` = (r0, r1, colour) tints outward."""
    m, nt, em = _base_material(name)
    near = None
    if far_gain is not None or far_color is not None:
        near = _nearness(nt, window)
    col = None
    if far_color is not None:
        col = _mix_rgb(nt, near, far_color, color)
    elif outer_color is not None:
        r0, r1, oc = outer_color
        col = _mix_rgb(nt, _smooth(nt, _radius(nt), r0, r1), color, oc)
    if col is not None:
        nt.links.new(col, em.inputs["Color"])
    else:
        em.inputs["Color"].default_value = (*color, 1.0)
    factors = []
    if clear:
        factors.append(_clear_factor(nt, *clear))
    if far_gain is not None:
        factors.append(_math(nt, "MULTIPLY_ADD", near, 1.0 - far_gain, far_gain))
    if facing:
        factors.append(_facing_factor(nt, facing))
    if arc:
        factors.append(_arc_factor(nt, *arc))
    if fade:
        r_in0, r_in1, r_out, power = fade
        r = _radius(nt)
        factors.append(_math(nt, "MULTIPLY", _smooth(nt, r, r_in0, r_in1),
                             _math(nt, "POWER", _smooth(nt, r, r_in1, r_out, 1.0, 0.0), power)))
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
    nt.links.new(_mix_rgb(nt, cool.outputs["Fac"], GOLD, BLUE), em.inputs["Color"])
    s = _math(nt, "MULTIPLY", glow.outputs["Fac"], strength)
    s = _math(nt, "MULTIPLY", s, _math(nt, "MULTIPLY_ADD", _nearness(nt, (0.6, 0.8)), 1.0 - far_gain, far_gain))
    s = _math(nt, "MULTIPLY", s, _clear_factor(nt, *CLEAR))
    nt.links.new(s, em.inputs["Strength"])
    return m


def halo_material(name, inner, outer, strength, falloff, lit_lo=None):
    """Brightest where the surface faces the camera, so a sphere reads as soft volumetric light.
    The colour runs from `inner` at the centre to `outer` at the rim: hot in the middle, cooler out.
    With `lit_lo`, the side away from LIGHT_DIR drops to that fraction, so the volume has form."""
    m, nt, em = _base_material(name)
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.5
    cosv = _math(nt, "SUBTRACT", 1.0, lw.outputs["Facing"])
    s = _math(nt, "MULTIPLY", _math(nt, "POWER", cosv, falloff), strength)
    if lit_lo is not None:
        s = _math(nt, "MULTIPLY", s, _math(nt, "MULTIPLY_ADD", _lit_side(nt), 1.0 - lit_lo, lit_lo))
    nt.links.new(s, em.inputs["Strength"])
    nt.links.new(_mix_rgb(nt, cosv, outer, inner), em.inputs["Color"])
    return m


def _lit_side(nt):
    """0..1: how far a point of a sphere centred on the origin faces LIGHT_DIR (position-based, so the back faces
    of a shell agree with the front ones)."""
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    nrm = nt.nodes.new("ShaderNodeVectorMath")
    nrm.operation = "NORMALIZE"
    nt.links.new(geo.outputs["Position"], nrm.inputs[0])
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    nt.links.new(nrm.outputs["Vector"], dot.inputs[0])
    dot.inputs[1].default_value = tuple(Vector(LIGHT_DIR).normalized())
    return _math(nt, "POWER", _math(nt, "MULTIPLY_ADD", dot.outputs["Value"], 0.5, 0.5), 1.4)


def limb_material(name, strength, power, lo, dim, lit):
    """A fresnel shell: light only where the surface turns away at the silhouette, so a sphere gets a thin
    atmospheric limb. Brightness and colour swing with the outward direction: `lit` toward LIGHT_DIR, `dim`
    (at `lo` of full strength) on the far side. Uses the position, not the normal, so back faces agree."""
    m, nt, em = _base_material(name)
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.5
    rim = _math(nt, "POWER", lw.outputs["Facing"], power)
    t = _lit_side(nt)
    side = _math(nt, "MULTIPLY_ADD", t, 1.0 - lo, lo)
    nt.links.new(_math(nt, "MULTIPLY", _math(nt, "MULTIPLY", rim, side), strength), em.inputs["Strength"])
    nt.links.new(_mix_rgb(nt, t, dim, lit), em.inputs["Color"])
    return m


def haze_material(name, strength, rise, fall, lo, dim, lit):
    """A soft ring of light straddling the silhouette of the sphere inside this shell: F^rise * (1-F)^fall on
    the fresnel term F, normalised to peak at 1, so it swells just inside the limb and dies just outside it."""
    m, nt, em = _base_material(name)
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.5
    f = lw.outputs["Facing"]
    peak_f = rise / (rise + fall)
    norm = 1.0 / (peak_f ** rise * (1.0 - peak_f) ** fall)
    ring_ = _math(nt, "MULTIPLY", _math(nt, "POWER", f, rise), _math(nt, "POWER", _math(nt, "SUBTRACT", 1.0, f), fall))
    t = _lit_side(nt)
    side = _math(nt, "MULTIPLY_ADD", t, 1.0 - lo, lo)
    nt.links.new(_math(nt, "MULTIPLY", _math(nt, "MULTIPLY", ring_, side), strength * norm), em.inputs["Strength"])
    nt.links.new(_mix_rgb(nt, t, dim, lit), em.inputs["Color"])
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


def tilted(normal, hint, degrees):
    """`normal` tipped by `degrees` about the axis normal x hint (a slight gyro tilt off the reactor plane)."""
    n = Vector(normal).normalized()
    axis = n.cross(Vector(hint)).normalized()
    return Quaternion(axis, math.radians(degrees)) @ n


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
    """Flat annular cells in the local XY plane (the reactor coils, the collar)."""
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


def facing_quat():
    """Rotation that turns an object's local +Z toward the camera (for rings that must stay perfectly round)."""
    return CAM_LOC.normalized().to_track_quat("Z", "Y")


def ball(name, radius, material, parent, subdivisions=5):
    """A smooth icosphere: even tessellation, so facing-based glows have no pole pinch."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=radius)
    ob = bpy.context.active_object
    bpy.ops.object.shade_smooth()
    ob.name = name
    ob.data.materials.append(material)
    ob.parent = parent
    return ob


# ---------- the presence ----------

# latitude (deg), symmetry, dash (min_len, max_len, min_gap, max_gap in deg), strength, bevel
BANDS = [
    (0, 6, (44, 56, 3, 5), 0.94, 0.0046),
    (20, 5, (18, 46, 4, 9), 0.74, 0.0037),
    (-20, 5, (18, 46, 4, 9), 0.74, 0.0037),
    (40, 4, (20, 52, 5, 11), 0.60, 0.0034),
    (-40, 4, (20, 52, 5, 11), 0.60, 0.0034),
    (60, 3, (24, 62, 6, 14), 0.48, 0.0031),
    (-60, 3, (24, 62, 6, 14), 0.48, 0.0031),
]
BAND_FAR = 0.07
BLUE_BAND = 60          # one short electric-blue dash per sector of this band: the whisper of blue
MERIDIANS = (-32.0, -148.0)   # static, 58 deg either side of the meridian that faces the viewer (-90)

# Film-style "text blocks": (top line latitude, band it rides, longitude of the first copy, line lengths in deg,
# left rule). Each block repeats with its band's symmetry, so riding the band keeps the loop seamless.
DATA_BLOCKS = [
    (29.0, 20, -118.0, (7.0, 4.5, 6.0), True),
    (-26.0, -20, -70.0, (5.0, 8.0), False),
]

# The body of light: (radius, strength per surface, facing falloff, inner colour, outer colour, unlit-side floor).
ATMOSPHERE = [
    (0.50, 0.034, 3.0, GOLD, AMBER, None),
    (0.78, 0.009, 2.6, GOLD, AMBER, 0.55),
    (0.985, 0.0036, 2.2, AMBER, DEEP, 0.3),
]
LIMB = (1.012, 0.38, 5.0, 0.12)    # radius, strength, fresnel power, strength on the unlit side
HAZE = (1.06, 0.026, 20.0, 12.0)   # radius, strength, rise and fall exponents: a soft ring straddling the limb

# name, radius, span (deg), tilt (deg; + = seen from above, near side low), screen angle (deg, ccw),
# peak bevel, strength, orbit direction, companion offset (radius), companion span (fraction)
SWEEPS = [
    ("Outer", 0.80, 220, 26, 32, 0.020, 1.30, 1, 0.044, 0.74),
    ("Inner", 0.48, 210, -32, 45, 0.015, 1.30, -1, 0.034, 0.66),
]

RAY_SYMMETRY = 6
RAYS_PER_SECTOR = 8
RAY_R0 = 0.24


def build_globe(parent, rng):
    """The sphere: latitude bands tilted toward the viewer so they open into nested ellipses, held by two faint
    meridians. Each band turns by its own symmetry sector per loop, alternating direction like orrery gears."""
    globe = empty("Globe", parent)
    globe.rotation_euler = (math.radians(23), 0.0, 0.0)
    spinners, bands = [], {}
    for i, (lat, symmetry, dash, strength, bevel) in enumerate(BANDS):
        phi = math.radians(lat)
        near = EQUATOR if lat == 0 else LINE
        mat = emissive(f"Band{lat:+d}", near, strength, far_gain=BAND_FAR, facing=0.5, clear=CLEAR, far_color=DEEP)
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
    build_data_blocks(bands)
    return globe, spinners


def build_blue_dashes(band, lat, phase, sector, base, symmetry, bevel):
    """A whisper of electric blue: one short dash set into the widest gap of each sector of this band."""
    gaps = [(base[i][1], base[i + 1][0]) for i in range(len(base) - 1)] + [(base[-1][1], sector + base[0][0])]
    g0, g1 = max(gaps, key=lambda g: g[1] - g[0])
    length = min(5.5, g1 - g0 - 3.0)
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
    mat = emissive(f"{band.name}.blue", BLUE, 0.42, far_gain=BAND_FAR, facing=0.5, clear=CLEAR)
    return curve_object(f"{band.name}.blue", splines, bevel * 0.8, mat, band)


def build_meridians(globe):
    """Two very faint meridian hairlines that lock the bands into reading as latitudes (static, so seamless)."""
    splines = []
    for lon in MERIDIANS:
        L = math.radians(lon)
        pts = [sph(SPHERE_R, t, L) for t in steps(math.radians(-84), math.radians(84), 0.75)]
        splines.append((pts, dash_radii(len(pts), 14)))
    mat = emissive("Meridian", AMBER, 0.2, far_gain=BAND_FAR, facing=0.5, clear=CLEAR, far_color=DEEP)
    return curve_object("Meridians", splines, 0.0019, mat, globe)


def build_data_blocks(bands):
    """A light touch of the film's data texture: small blocks of parallel hairlines lying on the sphere."""
    for lat_top, band_lat, lon0, lines, ruled in DATA_BLOCKS:
        band = bands[band_lat]
        symmetry = next(k for lat, k, *_ in BANDS if lat == band_lat)
        head, body = [], []
        for k in range(symmetry):
            lo = math.radians(lon0 + k * 360.0 / symmetry)
            for i, length in enumerate(lines):
                lat = math.radians(lat_top - i * 1.4)
                pts = [sph(SPHERE_R, lat, lo + t) for t in steps(0.0, math.radians(length / math.cos(lat)), 0.5)]
                (head if i == 0 else body).append((pts, None))
            if ruled:
                rule = lo - math.radians(1.6)
                top, bottom = lat_top + 0.5, lat_top - 1.4 * (len(lines) - 1) - 0.5
                body.append(([sph(SPHERE_R, t, rule) for t in steps(math.radians(bottom), math.radians(top), 0.25)], None))
        name = f"Data{band_lat:+d}"
        curve_object(f"{name}.head", head, 0.0019, emissive(f"{name}.head", LINE, 0.68, far_gain=BAND_FAR, clear=CLEAR, far_color=DEEP), band)
        curve_object(f"{name}.body", body, 0.0017, emissive(f"{name}.body", AMBER, 0.5, far_gain=BAND_FAR, clear=CLEAR, far_color=DEEP), band)


def build_atmosphere(parent):
    """The body of light: nested facing-lit shells sum to a soft gold volume that is brightest round the heart
    and falls away outward, and a fresnel limb traces the silhouette like a planet's atmosphere."""
    atmo = empty("Atmosphere", parent)
    for i, (r, strength, falloff, inner, outer, lit_lo) in enumerate(ATMOSPHERE):
        ball(f"Atmosphere.{i}", r, halo_material(f"Atmosphere.{i}", inner, outer, strength, falloff, lit_lo), atmo)
    r, strength, power, lo = LIMB
    ball("Limb", r, limb_material("Limb", strength, power, lo, DEEP, PALE), atmo, 6)
    r, strength, rise, fall = HAZE
    ball("Haze", r, haze_material("Haze", strength, rise, fall, lo, DEEP, GOLD), atmo, 6)
    return atmo


def build_sweeps(parent, rng):
    """Two bold crescents, each orbiting in its own inclined plane; their widest, brightest part faces the viewer.
    Each carries a warm glow sheath, a fine companion hairline outside it, and tips that break into sparks."""
    sweeps = empty("Sweeps", parent)
    spinners, strokes = [], []
    for name, r, span, tilt, screen, bevel, strength, direction, c_off, c_frac in SWEEPS:
        holder = empty(f"Sweep.{name}", sweeps)
        holder.rotation_euler = (math.radians(tilt), math.radians(-screen), 0.0)
        span_r = math.radians(span)
        pts = arc(r, 0.0, -span_r / 2, span_r / 2, 0.5)
        mat = emissive(f"Sweep.{name}", SWEEP, strength, far_gain=0.3, facing=1.3, arc=(span_r, 1.2, 0.0), window=SWEEP_FADE)
        stroke = curve_object(f"Sweep.{name}.stroke", [(pts, crescent_radii(len(pts)))], bevel, mat, holder)
        stroke.rotation_euler = (0.0, 0.0, -math.pi / 2)

        sheath = emissive(f"Sweep.{name}.sheath", EMBER, 0.095, far_gain=0.3, facing=2.2, arc=(span_r, 1.6, 0.0), window=SWEEP_FADE)
        curve_object(f"Sweep.{name}.sheath", [(pts, crescent_radii(len(pts), 0.02, 1.0))], bevel * 3.8, sheath, stroke)

        c_span = span_r * c_frac
        c_pts = arc(r + c_off, 0.0, -c_span / 2, c_span / 2, 0.5)
        hair = emissive(f"Sweep.{name}.hair", (1.0, 0.44, 0.08), 0.8, far_gain=0.3, facing=0.7, arc=(c_span, 1.1, 0.0), window=SWEEP_FADE)
        curve_object(f"Sweep.{name}.hair", [(c_pts, crescent_radii(len(c_pts), 0.1, 0.8))], 0.0024, hair, stroke)

        spinners.append((stroke, direction * FULL))
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
    """Sparse: a light dusting on the sphere, motes suspended in the light inside, riders on each crescent,
    and a trail of dwindling sparks beyond each crescent tip."""
    mat = spark_material(1.0, 0.3)

    def rand_dir():
        return Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()

    loose = []
    for i in range(24):
        if i == 3:
            loose.append((rand_dir() * SPHERE_R * rng.uniform(0.98, 1.05), 0.005, 0.8, 1.0))
            continue
        loose.append((rand_dir() * SPHERE_R * rng.uniform(0.97, 1.07), rng.uniform(0.003, 0.0055), 0.14 + 0.8 * rng.random() ** 3, 0.0))
    for i in range(22):
        loose.append((rand_dir() * rng.uniform(0.3, 0.9), rng.uniform(0.0022, 0.004), 0.1 + 0.5 * rng.random() ** 2, 0.0))
    spark_mesh("Sparks", loose, mat, globe)

    for stroke, r, span in strokes:
        riders = []
        for _ in range(5):
            a = rng.uniform(-0.38, 0.38) * span
            rr = r + rng.uniform(-0.04, 0.05)
            riders.append((Vector((rr * math.cos(a), rr * math.sin(a), rng.uniform(-0.03, 0.03))), rng.uniform(0.003, 0.005), 0.3 + 0.9 * rng.random() ** 2, 0.0))
        for side in (-1, 1):
            a = span / 2 - math.radians(6.0)
            for j in range(6):
                a += math.radians(rng.uniform(1.6, 4.2) * (1 + 0.15 * j))
                rr = r + rng.uniform(-0.008, 0.010) * (1 + 0.4 * j)
                z = rng.uniform(-0.006, 0.006) * (1 + 0.4 * j)
                riders.append((Vector((rr * math.cos(side * a), rr * math.sin(side * a), z)),
                               0.0058 * 0.86 ** j, 1.0 * 0.78 ** j * rng.uniform(0.7, 1.0), 0.0))
        spark_mesh(f"{stroke.name}.sparks", riders, mat, stroke)


def build_core(parent):
    """The arc-reactor heart, about twice its former size on screen and layered like an instrument: a hot
    cream-gold heart in a strong glow, ten coils between two rims, a fine 96-tick bezel turning against the
    coils, an outer segmented collar, and two thin gyro rings tipped slightly off the reactor plane."""
    core = empty("Core", parent)
    ball("Core.heart", 0.064, halo_material("Heart", CREAM, GOLD, 0.62, 1.8), core, 4)
    ball("Core.corona", 0.14, halo_material("Corona", HOT, GOLD, 0.13, 2.4), core, 4)
    ball("Core.glow", 0.38, halo_material("Glow", GOLD, AMBER, 0.09, 3.4), core, 4)

    reactor = frame("Reactor", core, REACTOR_NORMAL)
    coils = [(math.radians(36 * k + 3), math.radians(36 * k + 33)) for k in range(10)]
    plates("Reactor.coils", coils, 0.118, 0.170,
           emissive("Reactor.coils", REACTOR, 1.02, fade=(0.0, 0.05, 0.26, 1.0), outer_color=(0.12, 0.17, (1.0, 0.52, 0.11))), reactor)
    curve_object("Reactor.inner", [(ring(0.106), None)], 0.0013, emissive("Reactor.inner", REACTOR, 0.7), reactor, closed=True)
    curve_object("Reactor.rim", [(ring(0.186), None)], 0.0017, emissive("Reactor.rim", REACTOR, 0.85), reactor, closed=True)

    bezel = frame("Bezel", core, REACTOR_NORMAL)
    fine, major = [], []
    for i in range(96):
        a = FULL * i / 96
        if i % 8 == 0:
            major.append((radial(0.199, 0.228, a), None))
        else:
            fine.append((radial(0.201, 0.216 if i % 4 == 0 else 0.210, a), None))
    curve_object("Bezel.ticks", fine, 0.0010, emissive("Bezel", GOLD, 0.6), bezel)
    curve_object("Bezel.major", major, 0.0014, emissive("Bezel.major", (1.0, 0.5, 0.11), 0.7), bezel)

    collar = frame("Collar", core, REACTOR_NORMAL)
    segs = []
    for k in range(12):
        a = 30.0 * k
        segs += [(math.radians(a + 1.0), math.radians(a + 21.0)), (math.radians(a + 23.0), math.radians(a + 29.0))]
    plates("Collar.segments", segs, 0.240, 0.251, emissive("Collar", GOLD, 0.55), collar)

    gyro_a = frame("GyroA", core, tilted(REACTOR_NORMAL, (0.0, 0.0, 1.0), 17.0))
    arcs = [(arc(0.292, 0.0, math.radians(120 * k + 5), math.radians(120 * k + 113), 0.6), None) for k in range(3)]
    curve_object("GyroA.line", arcs, 0.0015, emissive("GyroA", GOLD, 0.6, far_gain=0.4, window=(0.3, 0.3)), gyro_a)
    beads = [(radial(0.281, 0.303, math.radians(120 * k + a)), None) for k in range(3) for a in (5.0, 113.0)]
    curve_object("GyroA.beads", beads, 0.0017, emissive("GyroA.beads", (1.0, 0.5, 0.11), 0.68, far_gain=0.4, window=(0.3, 0.3)), gyro_a)

    gyro_b = frame("GyroB", core, tilted(REACTOR_NORMAL, (1.0, 0.0, 0.0), -14.0))
    dashes = [(arc(0.330, 0.0, math.radians(45 * k + 4), math.radians(45 * k + 33), 0.6), None) for k in range(8)]
    curve_object("GyroB.dashes", dashes, 0.0019, emissive("GyroB", AMBER, 0.62, far_gain=0.35, window=(0.3, 0.3)), gyro_b)

    # coils and collar one way, bezel and gyro A the other, gyro B against A: each by one symmetry sector per loop
    return [(reactor, -FULL / 10), (bezel, FULL / 12), (collar, -FULL / 12), (gyro_a, FULL / 3), (gyro_b, -FULL / 8)]


def build_rays(parent, rng):
    """A corona of faint light rays: thin tapered radial strokes of varying length in the plane facing the
    viewer, emerging from behind the heart's rings and fading out long before the sphere."""
    holder = empty("Rays", parent)
    holder.rotation_mode = "QUATERNION"
    holder.rotation_quaternion = facing_quat()
    spin = empty("Rays.spin", holder)
    sector = FULL / RAY_SYMMETRY
    base = []
    for i in range(RAYS_PER_SECTOR):
        a = (i + rng.uniform(0.2, 0.8)) * sector / RAYS_PER_SECTOR
        if i == 0:
            length, width = rng.uniform(0.80, 0.90), 1.0
        elif i in (3, 6):
            length, width = rng.uniform(0.58, 0.70), rng.uniform(0.65, 0.85)
        else:
            length, width = rng.uniform(0.40, 0.54), rng.uniform(0.4, 0.7)
        base.append((a, length, width))
    splines = []
    for k in range(RAY_SYMMETRY):
        for a, length, width in base:
            d = Vector((math.cos(a + k * sector), math.sin(a + k * sector), 0.0))
            n = 36
            pts, radii = [], []
            for j in range(n):
                t = j / (n - 1)
                pts.append(d * (RAY_R0 + (length - RAY_R0) * t))
                radii.append(width * min(1.0, 0.35 + 0.65 * t / 0.1) * (1.0 - t) ** 1.3)
            splines.append((pts, radii))
    mat = emissive("Rays", GOLD, 0.3, facing=1.6, fade=(RAY_R0, RAY_R0 + 0.12, 0.9, 2.4), outer_color=(0.3, 0.7, AMBER))
    curve_object("Rays.strokes", splines, 0.0042, mat, spin)
    return spin, FULL / RAY_SYMMETRY


def build_hud_ring(parent):
    """One faint measuring ring facing the viewer, echoing the tick ring on the app's voice screen."""
    holder = empty("HudRing", parent)
    holder.rotation_mode = "QUATERNION"
    holder.rotation_quaternion = facing_quat()
    spin = empty("HudRing.spin", holder)
    r = 1.12
    curve_object("HudRing.line", [(ring(r, 0.5), None)], 0.0015, emissive("HudLine", DEEP, 0.12), spin, closed=True)
    minor, major = [], []
    for i in range(120):
        a = FULL * i / 120
        d = Vector((math.cos(a), math.sin(a), 0.0))
        if i % 10 == 0:
            major.append(([d * r, d * (r + 0.042)], None))
        else:
            minor.append(([d * r, d * (r + 0.016)], None))
    curve_object("HudRing.ticks", minor, 0.0017, emissive("HudTick", DEEP, 0.2), spin)
    curve_object("HudRing.major", major, 0.0019, emissive("HudMajor", GOLD, 0.34), spin)
    return spin, FULL / 12


def build(seed):
    rng = random.Random(seed)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene

    root = bpy.data.objects.new("Presence", None)
    scene.collection.objects.link(root)

    globe, spinners = build_globe(root, rng)
    build_atmosphere(root)
    _, sweep_spinners, strokes = build_sweeps(root, rng)
    spinners += sweep_spinners
    build_sparks(globe, strokes, rng)
    spinners += build_core(root)
    ray_spin, ray_turn = build_rays(root, rng)
    spinners.append((ray_spin, ray_turn))
    hud_spin, hud_turn = build_hud_ring(root)
    spinners.append((hud_spin, -hud_turn))
    return scene, spinners


def _fcurves(idblock):
    ad = idblock.animation_data
    if not ad or not ad.action:
        return []
    try:
        return list(ad.action.fcurves)
    except AttributeError:
        from bpy_extras import anim_utils
        return list(anim_utils.action_get_channelbag_for_slot(ad.action, ad.action_slot).fcurves)


def _make_linear(idblock):
    """Headless factory-startup runs ignore the LINEAR keyframe preference, so keys ease in and out and the
    loop stalls at the seam. Force every key linear."""
    for fc in _fcurves(idblock):
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
        fc.update()


def animate(scene, spinners, seconds, fps):
    """Each part turns by exactly one symmetry sector per loop, at constant speed, so the last frame meets the
    first."""
    bpy.context.preferences.edit.keyframe_new_interpolation_type = "LINEAR"
    frames = int(round(seconds * fps))
    scene.frame_start = 1
    scene.frame_end = frames
    scene.render.fps = fps
    worst = 0.0
    for ob, delta in spinners:
        base = ob.rotation_euler.z
        ob.keyframe_insert(data_path="rotation_euler", index=2, frame=1)
        ob.rotation_euler.z = base + delta
        ob.keyframe_insert(data_path="rotation_euler", index=2, frame=frames + 1)
        ob.rotation_euler.z = base
        _make_linear(ob)
        for fc in _fcurves(ob):
            quarter = fc.evaluate(1 + frames / 4) - base
            worst = max(worst, abs(quarter - delta / 4))
    print(f"LOOP {len(spinners)} spinners, {frames} frames, worst deviation from constant speed {worst:.2e} rad")


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
    scene.cycles.transparent_max_bounces = 128
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
    cam_data.sensor_fit = "HORIZONTAL"
    cam_data.sensor_width = 36.0
    d = CAM_LOC.length
    # the sphere's silhouette subtends R / sqrt(d^2 - R^2); size the lens so it fills GLOBE_FILL of the frame
    cam_data.lens = GLOBE_FILL * 18.0 * math.sqrt(d * d - SPHERE_R ** 2) / SPHERE_R
    cam = bpy.data.objects.new("Camera", cam_data)
    scene.collection.objects.link(cam)
    cam.location = CAM_LOC
    direction = Vector((0, 0, 0)) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    print(f"LENS {cam_data.lens:.2f} mm")


def _glare(tree, threshold, strength, size, smoothness=0.35):
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
    node.inputs["Smoothness"].default_value = smoothness
    node.inputs["Strength"].default_value = strength
    node.inputs["Size"].default_value = size
    return node


def setup_bloom(scene):
    """A tight halation on the lines, a medium glow the crescents and heart reach, and a wide soft bloom only the
    hottest light reaches. A small black level afterwards pulls the faint bloom tail back to true black."""
    tree = bpy.data.node_groups.new("PresenceComposite", "CompositorNodeTree")
    tree.interface.new_socket(name="Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    layers = tree.nodes.new("CompositorNodeRLayers")
    out = tree.nodes.new("NodeGroupOutput")
    tight = _glare(tree, 0.25, 0.48, 0.05)
    glow = _glare(tree, 0.7, 0.30, 0.16)
    wide = _glare(tree, 1.2, 0.24, 0.42, 0.6)
    curves = tree.nodes.new("CompositorNodeCurveRGB")
    curves.inputs["Black Level"].default_value = (0.0045, 0.0045, 0.0045, 1.0)
    tree.links.new(layers.outputs["Image"], tight.inputs["Image"])
    tree.links.new(tight.outputs["Image"], glow.inputs["Image"])
    tree.links.new(glow.outputs["Image"], wide.inputs["Image"])
    tree.links.new(wide.outputs["Image"], curves.inputs["Image"])
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
