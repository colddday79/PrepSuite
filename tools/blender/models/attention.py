"""PrepSuite presence, model 2: "Attention".

How a language model thinks, drawn as a sphere. ~170 token nodes sit on a Fibonacci sphere (small ice-blue points
with soft halos, a few brighter or larger). Curved attention arcs leave the surface and bow outward between tokens.
The strongest arcs, in warm gold, all converge on a single query token on the front hemisphere, which glows as the
focal point: the moment the model attends. Weaker ice-blue arcs also reach the query, a few secondary "heads"
elsewhere gather their own faint arcs, and everything else stays quiet. A few latitude hairlines and one faint
facing tick ring keep a little of the original globe's DNA.

Hierarchy: query node and gold arcs brightest, ice arcs medium, tokens / hairlines / ring faint.

Run headless:
    Blender -b --factory-startup --python-exit-code 1 --python attention.py -- [options]

Options: --out DIR  --res PX  --samples N  --frame F  --animation  --seconds S  --fps N  --still NAME  --no-render
Writes presence.blend and a PNG still (or an MP4 loop with --animation).

Motion (seamless at any loop length): the sphere sways gently about the vertical (a pure sine, so the query stays
in front); light pulses run along every arc toward the token it feeds, a whole number of times per loop; the tick
ring turns by one major-tick sector; the query node breathes twice per loop.
"""

import argparse
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

OUT_DEFAULT = "/Users/macintosh/Documents/PrepSuite/tools/blender/out/models/attention"

# Scene-linear colours for the Standard view transform. Ice keeps red well below blue so even the brightest
# ice stroke clips only in blue (stays tinted), gold clips only in red (stays gold).
ICE = (0.16, 0.55, 1.0)
ICE_DEEP = (0.07, 0.33, 1.0)
GOLD = (1.0, 0.54, 0.12)
HOT = (1.0, 0.62, 0.20)

CAM_LOC = Vector((0.0, -4.6, 0.25))
R = 0.84                     # token sphere radius
TILT = 23.0                  # globe tilt toward the viewer (deg), as in presence_final
N_TOKENS = 170
FULL = 2 * math.pi

TOKEN_FADE = (0.50, 0.22)    # depth window for things on the sphere
ARC_FADE = (0.80, 0.45)      # arcs rise off the surface, so a wider window

# The query token, placed in world space (camera looks along +Y): upper left of centre on the front face.
QUERY_WORLD = Vector((-0.30, -0.87, 0.36)).normalized()

# Gold attention arcs into the query: (bearing around the query in screen terms, deg ccw from right;
# angular distance to the key token, deg; weight 0..1). Composed as a fan that sweeps mostly across the sphere.
GOLD_ARCS = [
    (-62, 90, 1.00),
    (-16, 106, 0.70),
    (-108, 80, 0.60),
    (26, 84, 0.50),
    (-150, 62, 0.44),
    (190, 44, 0.38),
    (-40, 54, 0.32),
    (104, 46, 0.28),
    (-34, 132, 0.22),
    (146, 64, 0.20),
]

# Weaker ice arcs into the query: (bearing, distance, weight)
ICE_TO_QUERY = [
    (-84, 88, 0.15),
    (124, 32, 0.13),
    (48, 70, 0.13),
    (4, 58, 0.12),
]

# Secondary heads: (world direction, [(bearing, distance, weight), ...]) -- faint, short, so the sphere feels alive.
HEADS = [
    (Vector((0.55, -0.66, -0.50)), [(90, 30, 0.22), (160, 40, 0.18), (10, 26, 0.16), (-70, 34, 0.14)]),
    (Vector((0.84, -0.24, 0.48)), [(200, 30, 0.18), (250, 40, 0.15), (130, 28, 0.13)]),
    (Vector((-0.62, -0.42, -0.66)), [(40, 30, 0.16), (100, 38, 0.14), (-30, 26, 0.12)]),
    (Vector((0.10, 0.85, 0.30)), [(0, 34, 0.16), (120, 30, 0.14), (240, 38, 0.14)]),
]

LATITUDES = (-30.0, 0.0, 28.0)   # kept clear of the query token (latitude ~43 in globe space)
SWIRL = math.radians(75.0)   # how far every arc into the query swings round it (same sense for all)
CURL = 0.9                   # >1 puts more of the swing near the query
SPIN = -20.0                 # extra bearing offset for every key (deg)


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
    p.add_argument("--seed", type=int, default=7)
    p.add_argument("--still", default="still.png")
    p.add_argument("--no-render", action="store_true")
    p.add_argument("--swirl", type=float, default=None, help="override SWIRL (deg)")
    p.add_argument("--spin", type=float, default=None, help="rotate every key bearing round the query (deg)")
    p.add_argument("--curl", type=float, default=None, help="override CURL")
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
        m.cycles.emission_sampling = "NONE"
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


def _attr(nt, name):
    a = nt.nodes.new("ShaderNodeAttribute")
    a.attribute_name = name
    return a.outputs["Fac"]


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


def _facing(nt):
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.5
    return _math(nt, "SUBTRACT", 1.0, lw.outputs["Facing"])


def _mix_colour(nt, fac, a, b):
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    sock = {s.identifier: s for s in mix.inputs}
    sock["A_Color"].default_value = (*a, 1.0)
    sock["B_Color"].default_value = (*b, 1.0)
    if isinstance(fac, float):
        sock["Factor_Float"].default_value = fac
    else:
        nt.links.new(fac, sock["Factor_Float"])
    return next(s for s in mix.outputs if s.identifier == "Result_Color")


def _set_strength(nt, em, s):
    if isinstance(s, float):
        em.inputs["Strength"].default_value = s
    else:
        nt.links.new(s, em.inputs["Strength"])


def emissive(name, color, strength, far_gain=None, facing=None, window=TOKEN_FADE):
    m, nt, em = _base_material(name)
    em.inputs["Color"].default_value = (*color, 1.0)
    s = float(strength)
    if far_gain is not None:
        s = _math(nt, "MULTIPLY", _depth_factor(nt, far_gain, *window), s)
    if facing:
        s = _math(nt, "MULTIPLY", _math(nt, "POWER", _facing(nt), facing), s)
    _set_strength(nt, em, s)
    return m


CLOCKS = []   # Value nodes keyed 0 -> 1 over the loop


def _clock(nt):
    v = nt.nodes.new("ShaderNodeValue")
    v.name = "Clock"
    v.outputs[0].default_value = 0.0
    CLOCKS.append(v)
    return v.outputs[0]


def arc_material(gain, tail, far_gain):
    """One material for every arc. Per-vertex attributes: t (0 at the key token, 1 at the token it feeds),
    b (base brightness incl. the along-arc profile), amp (pulse strength), phase, rate (pulses per loop),
    warm (0 ice, 1 gold). A comet-shaped pulse runs toward the fed token."""
    m, nt, em = _base_material("Arcs")
    t = _attr(nt, "t")
    b = _attr(nt, "b")
    amp = _attr(nt, "amp")
    phase = _attr(nt, "phase")
    rate = _attr(nt, "rate")
    warm = _attr(nt, "warm")
    clock = _clock(nt)
    head = _math(nt, "FRACT", _math(nt, "MULTIPLY_ADD", clock, rate, phase))
    d = _math(nt, "FRACT", _math(nt, "SUBTRACT", head, t))           # 0 at the pulse head, grows behind it
    front = _math(nt, "MINIMUM", _math(nt, "MULTIPLY", d, 30.0), 1.0)
    comet = _math(nt, "MULTIPLY", front, _math(nt, "EXPONENT", _math(nt, "MULTIPLY", d, -1.0 / tail)))
    s = _math(nt, "MULTIPLY", b, _math(nt, "MULTIPLY_ADD", amp, comet, 1.0))
    s = _math(nt, "MULTIPLY", s, _depth_factor(nt, far_gain, *ARC_FADE))
    s = _math(nt, "MULTIPLY", s, _math(nt, "POWER", _facing(nt), 0.6))
    s = _math(nt, "MULTIPLY", s, gain)
    _set_strength(nt, em, s)
    nt.links.new(_mix_colour(nt, warm, ICE, GOLD), em.inputs["Color"])
    return m


def token_material(gain, far_gain):
    m, nt, em = _base_material("Tokens")
    s = _math(nt, "MULTIPLY", _attr(nt, "glow"), gain)
    s = _math(nt, "MULTIPLY", s, _depth_factor(nt, far_gain, *TOKEN_FADE))
    _set_strength(nt, em, s)
    nt.links.new(_mix_colour(nt, _attr(nt, "warm"), ICE, GOLD), em.inputs["Color"])
    return m


def token_halo_material(gain, falloff, far_gain):
    m, nt, em = _base_material("TokenHalos")
    s = _math(nt, "MULTIPLY", _attr(nt, "glow"), gain)
    s = _math(nt, "MULTIPLY", s, _math(nt, "POWER", _facing(nt), falloff))
    s = _math(nt, "MULTIPLY", s, _depth_factor(nt, far_gain, *TOKEN_FADE))
    _set_strength(nt, em, s)
    nt.links.new(_mix_colour(nt, _attr(nt, "warm"), ICE, GOLD), em.inputs["Color"])
    return m


def halo_material(name, inner, outer, strength, falloff, breathe=0.0):
    """Soft volumetric point of light: brightest facing the camera, colour hot at the centre, cooler at the rim.
    `breathe` modulates the strength twice per loop (seamless)."""
    m, nt, em = _base_material(name)
    cosv = _facing(nt)
    s = _math(nt, "MULTIPLY", _math(nt, "POWER", cosv, falloff), strength)
    if breathe:
        wave = _math(nt, "SINE", _math(nt, "MULTIPLY", _clock(nt), 2 * FULL))
        s = _math(nt, "MULTIPLY", s, _math(nt, "MULTIPLY_ADD", wave, breathe, 1.0))
    _set_strength(nt, em, s)
    nt.links.new(_mix_colour(nt, cosv, outer, inner), em.inputs["Color"])
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
        radii = radii or [1.0] * len(pts)
        sp = cu.splines.new("POLY")
        sp.points.add(len(pts) - 1)
        for i, (p, r) in enumerate(zip(pts, radii)):
            sp.points[i].co = (p.x, p.y, p.z, 1.0)
            sp.points[i].radius = r
        sp.use_cyclic_u = closed
    cu.materials.append(material)
    return link(bpy.data.objects.new(name, cu), parent)


def mesh_object(name, verts, faces, attrs, material, parent):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    for key, values in attrs.items():
        me.attributes.new(key, "FLOAT", "POINT").data.foreach_set("value", values)
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    me.materials.append(material)
    return link(bpy.data.objects.new(name, me), parent)


def unit_icosphere(subdiv):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    verts = [v.co.copy() for v in bm.verts]
    faces = [tuple(v.index for v in f.verts) for f in bm.faces]
    bm.free()
    return verts, faces


def ring(radius, step_deg=0.5):
    n = int(360 / step_deg)
    return [Vector((radius * math.cos(FULL * i / n), radius * math.sin(FULL * i / n), 0.0)) for i in range(n)]


def slerp(a, b, t):
    th = a.angle(b)
    if th < 1e-6:
        return a.copy()
    s = math.sin(th)
    return (a * math.sin((1 - t) * th) + b * math.sin(t * th)) / s


def fibonacci(n):
    golden = math.pi * (3.0 - math.sqrt(5.0))
    pts = []
    for i in range(n):
        z = 1.0 - 2.0 * (i + 0.5) / n
        r = math.sqrt(max(0.0, 1.0 - z * z))
        pts.append(Vector((r * math.cos(golden * i), r * math.sin(golden * i), z)))
    return pts


def facing_quat():
    return CAM_LOC.normalized().to_track_quat("Z", "Y")


# ---------- tube meshes (tapered strokes with per-vertex attributes) ----------

class Tubes:
    def __init__(self, sides=6):
        self.sides = sides
        self.verts, self.faces = [], []
        self.attrs = {}

    def add(self, pts, radii, point_attrs):
        n = len(pts)
        tangents = []
        for i in range(n):
            a = pts[max(0, i - 1)]
            b = pts[min(n - 1, i + 1)]
            tangents.append((b - a).normalized())
        ref = Vector((0, 0, 1)) if abs(tangents[0].z) < 0.9 else Vector((1, 0, 0))
        nrm = tangents[0].cross(ref).normalized()
        base = len(self.verts)
        for i in range(n):
            if i > 0:
                nrm = tangents[i - 1].rotation_difference(tangents[i]) @ nrm
                nrm = (nrm - tangents[i] * nrm.dot(tangents[i])).normalized()
            bin_ = tangents[i].cross(nrm)
            for k in range(self.sides):
                a = FULL * k / self.sides
                self.verts.append(pts[i] + (nrm * math.cos(a) + bin_ * math.sin(a)) * radii[i])
            for key, values in point_attrs.items():
                self.attrs.setdefault(key, []).extend([values[i]] * self.sides)
        s = self.sides
        for i in range(n - 1):
            r0 = base + i * s
            r1 = r0 + s
            for k in range(s):
                k1 = (k + 1) % s
                self.faces.append((r0 + k, r0 + k1, r1 + k1, r1 + k))

    def build(self, name, material, parent):
        return mesh_object(name, self.verts, self.faces, self.attrs, material, parent)


# ---------- the design ----------

def tilt_matrix():
    return Matrix.Rotation(math.radians(TILT), 3, "X")


def to_local(world_dir):
    return (tilt_matrix().inverted() @ world_dir).normalized()


def around(centre_world, bearing_deg, dist_deg):
    """A world direction `dist_deg` away from `centre_world`, at a screen-style bearing (0 = screen right, ccw)."""
    c = centre_world.normalized()
    e1 = (Vector((1, 0, 0)) - c * c.x).normalized()
    e2 = c.cross(e1)
    if e2.z < 0:
        e2 = -e2
    b, d = math.radians(bearing_deg), math.radians(dist_deg)
    tang = e1 * math.cos(b) + e2 * math.sin(b)
    return (c * math.cos(d) + tang * math.sin(d)).normalized()


def nearest(tokens, direction, taken):
    best, best_d = None, 9.0
    for i, p in enumerate(tokens):
        if i in taken:
            continue
        d = p.angle(direction)
        if d < best_d:
            best, best_d = i, d
    return best


def arc_path(a, b, lift, twist=0.0, curl=None):
    """From token a to token b, bowing outward off the sphere. With `twist`, the path swings round b's axis as it
    closes in (bearing turns by `twist` radians, most of it near b), so arcs into one token read as a flow spiralling
    into a focus rather than as meridians meeting at a pole."""
    curl = CURL if curl is None else curl
    th = a.angle(b)
    n = max(16, int(math.degrees(th) / 1.0))
    e1 = (a - b * a.dot(b)).normalized()
    e2 = b.cross(e1)
    pts = []
    for i in range(n + 1):
        t = i / n
        rho = th * (1.0 - t)
        beta = twist * t ** curl
        d = b * math.cos(rho) + (e1 * math.cos(beta) + e2 * math.sin(beta)) * math.sin(rho)
        pts.append(d * (R * (1.0 + lift * math.sin(math.pi * t) ** 0.85)))
    return pts


def lift_for(th):
    return min(0.30, 0.05 + 0.11 * th)


def taper(n, floor=0.06, power=0.55, bias=0.0):
    """Pointed at both ends; `bias` > 0 carries more width toward the fed token (t = 1)."""
    out = []
    for i in range(n):
        t = i / (n - 1)
        out.append((floor + (1 - floor) * math.sin(math.pi * t) ** power) * (1.0 - bias + bias * t))
    return out


def build(seed):
    rng = random.Random(seed)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    CLOCKS.clear()
    scene = bpy.context.scene

    root = bpy.data.objects.new("Presence", None)
    scene.collection.objects.link(root)
    sway = empty("Sway", root)
    globe = empty("Globe", sway)
    globe.rotation_euler = (math.radians(TILT), 0.0, 0.0)

    tokens = fibonacci(N_TOKENS)
    taken = set()

    # the query token sits exactly where the composition wants it
    q_local = to_local(QUERY_WORLD)
    qi = nearest(tokens, q_local, taken)
    tokens[qi] = q_local
    taken.add(qi)
    Q = tokens[qi]

    glow = [0.0] * N_TOKENS
    size = [0.0] * N_TOKENS
    for i, p in enumerate(tokens):
        # gentle spotlight around the query, random variation elsewhere
        near = max(0.0, p.dot(Q)) ** 3
        glow[i] = 0.22 + 0.45 * rng.random() ** 2.2 + 0.35 * near
        size[i] = 0.0062 + 0.0022 * rng.random()
    for i in rng.sample(range(N_TOKENS), 9):
        size[i] *= 1.45
        glow[i] += 0.35

    tubes = Tubes(6)

    def add_arc(key_i, target, weight, warm, width, profile, amp, rate, twist=0.0):
        K = tokens[key_i]
        th = K.angle(target)
        pts = arc_path(K, target, lift_for(th), twist)
        n = len(pts)
        radii = [width * r for r in taper(n, bias=0.25 if warm else 0.1)]
        ts = [i / (n - 1) for i in range(n)]
        b = [weight * profile(t) for t in ts]
        tubes.add(pts, radii, {
            "t": ts, "b": b, "amp": [amp] * n, "phase": [rng.random()] * n,
            "rate": [float(rate)] * n, "warm": [1.0 if warm else 0.0] * n,
        })

    # gold arcs: the strongest attention, converging on the query
    for bearing, dist, w in GOLD_ARCS:
        ki = nearest(tokens, to_local(around(QUERY_WORLD, bearing + SPIN, dist)), taken)
        taken.add(ki)
        add_arc(ki, Q, w ** 1.3, True, 0.0009 + 0.0046 * w ** 1.5, lambda t: 0.40 + 0.60 * t ** 1.5, 1.1, 1 + (ki % 2), SWIRL)
        glow[ki] += 0.8 * w + 0.3            # the attended tokens light up with their weight
        size[ki] = max(size[ki], 0.0080 + 0.0045 * w)

    # weaker ice arcs into the query
    for bearing, dist, w in ICE_TO_QUERY:
        ki = nearest(tokens, to_local(around(QUERY_WORLD, bearing + SPIN, dist)), taken)
        taken.add(ki)
        add_arc(ki, Q, w, False, 0.0014, lambda t: 0.40 + 0.60 * t, 0.8, 1, SWIRL)
        glow[ki] += 0.2

    # secondary heads, faint
    for head_world, arcs in HEADS:
        hi = nearest(tokens, to_local(head_world.normalized()), taken)
        taken.add(hi)
        H = tokens[hi]
        glow[hi] += 0.45
        size[hi] = max(size[hi], 0.0085)
        for bearing, dist, w in arcs:
            ki = nearest(tokens, to_local(around(head_world.normalized(), bearing, dist)), taken)
            taken.add(ki)
            add_arc(ki, H, w, False, 0.0013, lambda t: 0.5 + 0.5 * t, 0.7, 1)
            glow[ki] += 0.12

    tubes.build("Arcs", arc_material(gain=1.25, tail=0.16, far_gain=0.10), globe)

    # tokens (the query is drawn separately)
    core_v, core_f = unit_icosphere(1)
    halo_v, halo_f = unit_icosphere(2)
    cv, cf, hv, hf = [], [], [], []
    cattr = {"glow": [], "warm": []}
    hattr = {"glow": [], "warm": []}
    for i, p in enumerate(tokens):
        if i == qi:
            continue
        c = p * R
        base = len(cv)
        cv += [c + v * size[i] for v in core_v]
        cf += [tuple(base + j for j in f) for f in core_f]
        cattr["glow"] += [glow[i]] * len(core_v)
        cattr["warm"] += [0.0] * len(core_v)
        base = len(hv)
        hv += [c + v * size[i] * 2.6 for v in halo_v]
        hf += [tuple(base + j for j in f) for f in halo_f]
        hattr["glow"] += [glow[i]] * len(halo_v)
        hattr["warm"] += [0.0] * len(halo_v)
    mesh_object("Tokens", cv, cf, cattr, token_material(0.95, 0.14), globe)
    mesh_object("TokenHalos", hv, hf, hattr, token_halo_material(0.10, 3.5, 0.10), globe)

    build_query(globe, Q * R)
    build_hairlines(globe)
    ring_spin = build_ring(root)
    return scene, sway, ring_spin


def uv_sphere(name, radius, material, parent, location, segments=40, rings=20):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, segments=segments, ring_count=rings)
    ob = bpy.context.active_object
    bpy.ops.object.shade_smooth()
    ob.name = name
    ob.data.materials.append(material)
    ob.parent = parent
    ob.location = location
    return ob


def build_query(globe, pos):
    """The attending token: a hot gold point in a gold glow."""
    q = empty("Query", globe)
    q.location = pos
    uv_sphere("Query.heart", 0.020, halo_material("Query.heart", HOT, GOLD, 0.95, 1.2, breathe=0.12), q, (0, 0, 0), 32, 16)
    uv_sphere("Query.glow", 0.060, halo_material("Query.glow", GOLD, GOLD, 0.45, 2.6, breathe=0.18), q, (0, 0, 0))
    uv_sphere("Query.aura", 0.17, halo_material("Query.aura", GOLD, GOLD, 0.026, 3.5, breathe=0.25), q, (0, 0, 0))


def build_hairlines(globe):
    splines = []
    for lat in LATITUDES:
        phi = math.radians(lat)
        splines.append(([Vector((R * math.cos(phi) * math.cos(a), R * math.cos(phi) * math.sin(a), R * math.sin(phi)))
                         for a in (FULL * i / 480 for i in range(480))], None))
    return curve_object("Latitudes", splines, 0.0011, emissive("Latitude", ICE_DEEP, 0.16, far_gain=0.12, facing=0.5), globe, closed=True)


def build_ring(parent):
    """One faint tick ring facing the viewer, a quiet echo of the original presence."""
    holder = empty("Ring", parent)
    holder.rotation_mode = "QUATERNION"
    holder.rotation_quaternion = facing_quat()
    spin = empty("Ring.spin", holder)
    r = 1.10
    curve_object("Ring.line", [(ring(r), None)], 0.0012, emissive("RingLine", ICE_DEEP, 0.10), spin, closed=True)
    minor, major = [], []
    for i in range(144):
        a = FULL * i / 144
        d = Vector((math.cos(a), math.sin(a), 0.0))
        if i % 12 == 0:
            major.append(([d * r, d * (r + 0.036)], None))
        else:
            minor.append(([d * r, d * (r + 0.013)], None))
    curve_object("Ring.ticks", minor, 0.0012, emissive("RingTick", ICE_DEEP, 0.16), spin)
    curve_object("Ring.major", major, 0.0015, emissive("RingMajor", ICE, 0.22), spin)
    return spin


# ---------- animation ----------

def _fcurve(idblock, data_path, index):
    ad = idblock.animation_data
    act = ad.action
    try:
        return act.fcurves.find(data_path, index=index)
    except AttributeError:
        from bpy_extras import anim_utils
        cb = anim_utils.action_get_channelbag_for_slot(act, ad.action_slot)
        return cb.fcurves.find(data_path, index=index)


def _make_linear(idblock):
    """Force linear keys: the LINEAR preference is not honoured for new keys in a headless factory-startup run,
    and eased keys would make the ring and every pulse stall at the loop seam."""
    ad = idblock.animation_data
    if not ad or not ad.action:
        return
    try:
        curves = list(ad.action.fcurves)
    except AttributeError:
        from bpy_extras import anim_utils
        curves = list(anim_utils.action_get_channelbag_for_slot(ad.action, ad.action_slot).fcurves)
    for fc in curves:
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"


def animate(scene, sway, ring_spin, seconds, fps):
    bpy.context.preferences.edit.keyframe_new_interpolation_type = "LINEAR"
    frames = int(round(seconds * fps))
    scene.frame_start = 1
    scene.frame_end = frames
    scene.render.fps = fps

    # gentle sway: a pure sine about the vertical, zero at frame 1, one period per loop
    sway.keyframe_insert(data_path="rotation_euler", index=2, frame=1)
    fc = _fcurve(sway, "rotation_euler", 2)
    mod = fc.modifiers.new("FNGENERATOR")
    mod.function_type = "SIN"
    mod.amplitude = math.radians(9.0)
    mod.phase_multiplier = FULL / frames
    mod.phase_offset = -FULL / frames
    mod.value_offset = 0.0

    # tick ring turns by one major-tick sector per loop
    ring_spin.keyframe_insert(data_path="rotation_euler", index=2, frame=1)
    ring_spin.rotation_euler.z = -FULL / 12
    ring_spin.keyframe_insert(data_path="rotation_euler", index=2, frame=frames + 1)
    ring_spin.rotation_euler.z = 0.0
    _make_linear(ring_spin)

    # shader clocks 0 -> 1 per loop (every pulse / breath is a whole number of cycles per loop)
    for v in CLOCKS:
        sock = v.outputs[0]
        sock.default_value = 0.0
        sock.keyframe_insert("default_value", frame=1)
        sock.default_value = 1.0
        sock.keyframe_insert("default_value", frame=frames + 1)
        sock.default_value = 0.0
        _make_linear(v.id_data)


# ---------- render ----------

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
    tree = bpy.data.node_groups.new("AttentionComposite", "CompositorNodeTree")
    tree.interface.new_socket(name="Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    layers = tree.nodes.new("CompositorNodeRLayers")
    out = tree.nodes.new("NodeGroupOutput")
    tight = _glare(tree, 0.25, 0.40, 0.25)
    glow = _glare(tree, 0.85, 0.30, 0.55)
    curves = tree.nodes.new("CompositorNodeCurveRGB")
    curves.inputs["Black Level"].default_value = (0.0035, 0.0035, 0.0035, 1.0)
    tree.links.new(layers.outputs["Image"], tight.inputs["Image"])
    tree.links.new(tight.outputs["Image"], glow.inputs["Image"])
    tree.links.new(glow.outputs["Image"], curves.inputs["Image"])
    tree.links.new(curves.outputs["Image"], out.inputs[0])
    scene.compositing_node_group = tree


def prepare_viewport():
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
    global SWIRL, CURL, SPIN
    a = parse_args()
    if a.swirl is not None:
        SWIRL = math.radians(a.swirl)
    if a.curl is not None:
        CURL = a.curl
    if a.spin is not None:
        SPIN = a.spin
    os.makedirs(a.out, exist_ok=True)
    scene, sway, ring_spin = build(a.seed)
    setup_render(scene, a.res, a.samples)
    setup_bloom(scene)
    animate(scene, sway, ring_spin, a.seconds, a.fps)
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
