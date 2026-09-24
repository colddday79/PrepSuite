"""PrepSuite presence, model 3: "Resonance".

The AI as a living voice made of language. A closed band of light, woven from ~80 fine parallel filaments, runs
along a (2,3) torus knot (a trefoil): one unbroken line of speech with no beginning and no end. The band is
narrow and calm where the voice is quiet and fans open into a shimmering silk sheet where it "speaks"; there the
filaments carry a travelling waveform (a lateral sway plus an out-of-plane ripple, phase-shifted across the band),
so the sheet reads as sound. Where the band twists edge-on it collapses to a bright line. Short token strokes
("words") peel off the outer side of the speaking lobe and drift outward, fading as they go.

Palette: deep teal (far) -> aqua -> pearl (near, loud), with a rose-gold sheen wherever the sheet faces the viewer.

Motion (Geometry Nodes + one keyframed spin, all periodic in a 16 s loop): the speech bursts flow along the band,
the carrier ripple travels through them, the band breathes, the tokens are re-emitted on a cycle and the whole
form turns once about its own axis.

Run headless:
    Blender -b --factory-startup --python-exit-code 1 --python resonance.py -- [options]
Options: --out DIR  --res PX  --samples N  --frame F  --animation  --seconds S  --fps N  --still NAME  --no-render
"""

import argparse
import math
import os
import random
import sys

import bpy
import numpy as np
from mathutils import Vector

OUT_DEFAULT = "/Users/macintosh/Documents/PrepSuite/tools/blender/out/models/resonance"

CAM_LOC = Vector((0.0, -4.6, 0.25))
TAU = 2 * math.pi

# Scene-linear colours for the Standard view transform. Red stays low in the cool tones so that even where many
# filaments stack additively they clip toward pale aqua / pearl, never to flat white.
DEEP_TEAL = (0.0, 0.085, 0.11)
TEAL = (0.0, 0.34, 0.38)
AQUA = (0.05, 0.72, 0.68)
PEARL = (0.46, 0.86, 0.80)
ROSE = (1.0, 0.46, 0.34)
PEACH = (1.0, 0.64, 0.46)

# ---- the path: a (P, Q) torus knot; its axis is local Z ----
P_WIND, Q_WIND = 2, 3
KNOT_R, KNOT_r, KNOT_Z = 0.72, 0.36, 1.0
TWIST_K, TWIST_0 = 0, 0.0          # band width follows the tube radial: face-on at the lobes, edge-on at crossings

# ---- the band ----
STRANDS = 84
STRAYS = 5                         # a few loose threads just outside the band
ALONG = 1600                       # samples per filament
HW_Q, HW_L = 0.045, 0.105          # band half-width, quiet vs speaking
Q0 = 0.24                          # quiet loudness
FIL_RADIUS = 0.0015
# speaking regions on the knot: (centre phi, concentration, amplitude)
LOUD = [(0.20, 6.0, 1.0), (4 * math.pi / 3 + 0.25, 7.0, 0.22)]

# ---- waveform (integer frequencies and integer cycles per loop, so the loop is seamless) ----
WORDS = [(11, 0.60, 0.4), (17, 0.40, 1.9), (26, 0.25, 0.8)]  # (freq along knot, weight, phase)
WORD_POWER = 1.3
# voices: the filaments split into groups that each trace their own sine through the speaking region, crossing
# one another like the lines of a voice waveform. (freq along knot, cycles per loop, phase, amplitude scale)
VOICES = [(31, 6, 0.0, 1.0), (37, 7, 2.2, 0.62), (0, 0, 0.0, 0.0), (34, 8, 4.1, 0.85), (43, 9, 1.1, 0.42)]
VOICE_AMP = 0.105
WORD_TRAVEL = 1                    # speech pattern flows once around the knot per loop
LAT = (57, 12, 0.12, 0.9)          # lateral sway: freq, cycles/loop, amplitude (x half-width x loudness), spread
RIP = (33, 9, 0.034, 2.3)          # out-of-plane ripple: freq, cycles/loop, amplitude, spread across band
BREATH = (2, 1, 0.08)              # slow width breathing: freq, cycles/loop, amount

# ---- tokens ----
GLYPH_CYCLES = 1                   # each token is re-emitted once per loop

TILT_X, TILT_Y, SPIN0 = 71.0, -10.0, 0.0    # degrees: the knot's axis leans ~21 deg off the view axis
ROLL = -28.0                       # degrees about the view axis: places the speaking lobe near 1 o'clock
ROOT_OFFSET = (0.0, 0.0, -0.06)


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
    return p.parse_args(argv)


# ======================= knot geometry (numpy) =======================

def _norm(a):
    return a / np.linalg.norm(a, axis=-1, keepdims=True)


def knot_frame(phi):
    """Centre line C, tangent T, band-width direction W and band normal V for knot parameter phi."""
    p, q = P_WIND, Q_WIND
    cq, sq = np.cos(q * phi), np.sin(q * phi)
    cp, sp = np.cos(p * phi), np.sin(p * phi)
    rad = KNOT_R + KNOT_r * cq
    C = np.stack([rad * cp, rad * sp, KNOT_r * KNOT_Z * sq], -1)
    drad = -KNOT_r * q * sq
    dC = np.stack([drad * cp - rad * p * sp, drad * sp + rad * p * cp, KNOT_r * KNOT_Z * q * cq], -1)
    T = _norm(dC)
    tube = np.stack([cq * cp, cq * sp, KNOT_Z * sq], -1)
    N0 = _norm(tube - (tube * T).sum(-1, keepdims=True) * T)
    B0 = np.cross(T, N0)
    th = (TWIST_K * phi + TWIST_0)[..., None]
    W = np.cos(th) * N0 + np.sin(th) * B0
    V = np.cross(T, W)
    return C, T, W, V


def region(phi):
    r = np.zeros_like(phi)
    for centre, kappa, amp in LOUD:
        r = np.maximum(r, amp * np.exp(kappa * (np.cos(phi - centre) - 1.0)))
    return r


def words_np(phi, tau=0.0):
    s = sum(w * np.sin(f * phi - TAU * f * WORD_TRAVEL * tau + ph) for f, w, ph in WORDS)
    return np.clip(0.5 + 0.4 * s, 0.0, 1.0) ** WORD_POWER


def env_np(phi, tau=0.0):
    return Q0 + (1 - Q0) * region(phi) * words_np(phi, tau)


# ======================= shader helpers =======================

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


def _set(nt, sock, v):
    if isinstance(v, (int, float)):
        sock.default_value = float(v)
    elif isinstance(v, (tuple, list, Vector)):
        sock.default_value = tuple(v)
    else:
        nt.links.new(v, sock)


def _m(nt, op, a, b=0.0, c=0.0):
    n = nt.nodes.new("ShaderNodeMath")
    n.operation = op
    for i, v in enumerate((a, b, c)):
        _set(nt, n.inputs[i], v)
    return n.outputs[0]


def _attr(nt, name, out="Fac"):
    n = nt.nodes.new("ShaderNodeAttribute")
    n.attribute_name = name
    return n.outputs[out]


def _smooth(nt, x, a, b, lo=0.0, hi=1.0):
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.interpolation_type = "SMOOTHSTEP"
    mr.clamp = True
    _set(nt, mr.inputs[0], x)
    mr.inputs[1].default_value = a
    mr.inputs[2].default_value = b
    mr.inputs[3].default_value = lo
    mr.inputs[4].default_value = hi
    return mr.outputs[0]


def _near(nt, near_w, far_w):
    """1 at the front of the form, 0 at the back (camera distance around the centre)."""
    cam = nt.nodes.new("ShaderNodeCameraData")
    d = CAM_LOC.length
    return _smooth(nt, cam.outputs["View Distance"], d + far_w, d - near_w)


def _mix(nt, fac, a, b):
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    sock = {s.identifier: s for s in mix.inputs}
    _set(nt, sock["Factor_Float"], fac)
    _set(nt, sock["A_Color"], a if not isinstance(a, tuple) else (*a, 1.0))
    _set(nt, sock["B_Color"], b if not isinstance(b, tuple) else (*b, 1.0))
    return next(s for s in mix.outputs if s.identifier == "Result_Color")


def _ramp(nt, fac, stops):
    n = nt.nodes.new("ShaderNodeValToRGB")
    cr = n.color_ramp
    cr.interpolation = "EASE"
    cr.elements[0].position, cr.elements[0].color = stops[0][0], (*stops[0][1], 1.0)
    cr.elements[1].position, cr.elements[1].color = stops[-1][0], (*stops[-1][1], 1.0)
    for pos, col in stops[1:-1]:
        e = cr.elements.new(pos)
        e.color = (*col, 1.0)
    _set(nt, n.inputs["Fac"], fac)
    return n.outputs["Color"]


def ribbon_material(strength):
    """Hue by nearness and loudness (deep teal -> aqua -> pearl), rose-gold sheen where the sheet faces the viewer.
    Strength is scaled by sheet facing and band width so edge-on folds glow as lines without blowing out."""
    m, nt, em = _base_material("Ribbon")
    vt = nt.nodes.new("ShaderNodeVectorTransform")
    vt.vector_type = "VECTOR"
    vt.convert_from = "OBJECT"
    vt.convert_to = "WORLD"
    nt.links.new(_attr(nt, "bnorm", "Vector"), vt.inputs["Vector"])
    nrm = nt.nodes.new("ShaderNodeVectorMath")
    nrm.operation = "NORMALIZE"
    nt.links.new(vt.outputs["Vector"], nrm.inputs[0])
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    nt.links.new(nrm.outputs["Vector"], dot.inputs[0])
    nt.links.new(geo.outputs["Incoming"], dot.inputs[1])
    facing = _m(nt, "ABSOLUTE", dot.outputs["Value"])

    env = _attr(nt, "env")
    hwn = _attr(nt, "hwn")
    gain = _attr(nt, "gain")
    edge = _attr(nt, "edge")
    near = _near(nt, 0.55, 0.75)

    # thin-film style: edge-on aqua, turning through pearl to rose-gold where the sheet faces the viewer;
    # the sheen is strongest where the voice is loud, and everything cools to deep teal toward the back
    sheet = _ramp(nt, _m(nt, "MULTIPLY", facing, _m(nt, "MULTIPLY_ADD", env, 0.35, 0.65)),
                  [(0.0, AQUA), (0.42, AQUA), (0.62, PEARL), (0.80, PEACH), (1.0, ROSE)])
    col = _mix(nt, _m(nt, "POWER", near, 0.8), DEEP_TEAL, sheet)
    nt.links.new(col, em.inputs["Color"])

    s = _m(nt, "MULTIPLY", gain, edge)
    s = _m(nt, "MULTIPLY", s, _m(nt, "POWER", hwn, 0.85))
    s = _m(nt, "MULTIPLY", s, _m(nt, "MULTIPLY_ADD", env, 0.8, 0.2))
    s = _m(nt, "MULTIPLY", s, _m(nt, "POWER", _m(nt, "MAXIMUM", facing, 0.06), 0.8))
    s = _m(nt, "MULTIPLY", s, _m(nt, "MULTIPLY_ADD", near, 0.88, 0.12))
    s = _m(nt, "MULTIPLY", s, strength)
    nt.links.new(s, em.inputs["Strength"])
    return m


def glyph_material(strength):
    """Warm pearl strokes: fade in as they leave the band, fade out with distance, and each dissolves at its own
    moment (attribute 'dis'), so a line of text breaks up as it drifts away."""
    m, nt, em = _base_material("Tokens")
    life = _attr(nt, "life")
    fade = _m(nt, "MULTIPLY", _smooth(nt, life, 0.0, 0.06), _m(nt, "POWER", _m(nt, "SUBTRACT", 1.0, life), 1.2))
    x = _m(nt, "MINIMUM", _m(nt, "MAXIMUM", _m(nt, "DIVIDE", _m(nt, "SUBTRACT", _attr(nt, "dis"), life), 0.12), 0.0), 1.0)
    fade = _m(nt, "MULTIPLY", fade, _m(nt, "MULTIPLY", _m(nt, "MULTIPLY", x, x), _m(nt, "MULTIPLY_ADD", x, -2.0, 3.0)))
    near = _near(nt, 0.6, 0.8)
    col = _mix(nt, _attr(nt, "warm"), PEARL, PEACH)
    nt.links.new(col, em.inputs["Color"])
    s = _m(nt, "MULTIPLY", fade, _m(nt, "MULTIPLY_ADD", near, 0.75, 0.25))
    s = _m(nt, "MULTIPLY", s, _attr(nt, "gain"))
    s = _m(nt, "MULTIPLY", s, strength)
    nt.links.new(s, em.inputs["Strength"])
    return m


# ======================= geometry-node helpers =======================

class GN:
    def __init__(self, name, loop_frames):
        t = bpy.data.node_groups.new(name, "GeometryNodeTree")
        try:
            t.is_modifier = True
        except AttributeError:
            pass
        t.interface.new_socket(name="Geometry", in_out="INPUT", socket_type="NodeSocketGeometry")
        t.interface.new_socket(name="Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry")
        self.t = t
        self.inp = t.nodes.new("NodeGroupInput")
        self.out = t.nodes.new("NodeGroupOutput")
        st = t.nodes.new("GeometryNodeInputSceneTime")
        # loop phase in [0, 1): frame 1 -> 0, frame loop+1 -> 1 (== 0)
        self.tau = self.math("DIVIDE", self.math("SUBTRACT", st.outputs["Frame"], 1.0), float(loop_frames))

    def set(self, sock, v):
        _set(self.t, sock, v)

    def math(self, op, a, b=0.0, c=0.0):
        return _m(self.t, op, a, b, c)

    def vmath(self, op, a, b=None, scale=None):
        n = self.t.nodes.new("ShaderNodeVectorMath")
        n.operation = op
        self.set(n.inputs[0], a)
        if b is not None:
            self.set(n.inputs[1], b)
        if scale is not None:
            self.set(n.inputs[3], scale)
        return n.outputs[1] if op in ("DOT_PRODUCT", "LENGTH", "DISTANCE") else n.outputs[0]

    def attr(self, name, vec=False):
        n = self.t.nodes.new("GeometryNodeInputNamedAttribute")
        n.data_type = "FLOAT_VECTOR" if vec else "FLOAT"
        n.inputs["Name"].default_value = name
        return n.outputs["Attribute"]

    def wave(self, x, freq, cycles, phase):
        """sin(freq * x - TAU * cycles * tau + phase); phase may be a socket."""
        arg = self.math("MULTIPLY_ADD", x, float(freq), self.math("MULTIPLY_ADD", self.tau, -TAU * cycles, phase))
        return self.math("SINE", arg)

    def store(self, geo, name, value):
        n = self.t.nodes.new("GeometryNodeStoreNamedAttribute")
        n.data_type = "FLOAT"
        n.domain = "POINT"
        self.set(n.inputs["Geometry"], geo)
        n.inputs["Name"].default_value = name
        self.set(n.inputs["Value"], value)
        return n.outputs[0]

    def finish(self, geo, position, radius, material):
        sp = self.t.nodes.new("GeometryNodeSetPosition")
        self.set(sp.inputs["Geometry"], geo)
        self.set(sp.inputs["Position"], position)
        rad = self.t.nodes.new("GeometryNodeSetCurveRadius")
        self.set(rad.inputs["Curve"], sp.outputs[0])
        self.set(rad.inputs["Radius"], radius)
        sm = self.t.nodes.new("GeometryNodeSetMaterial")
        self.set(sm.inputs["Geometry"], rad.outputs[0])
        sm.inputs["Material"].default_value = material
        self.set(self.out.inputs[0], sm.outputs[0])


def ribbon_nodes(loop_frames, material):
    g = GN("ResonanceRibbon", loop_frames)
    phi, u, k = g.attr("phi"), g.attr("u"), g.attr("k")
    reg = g.attr("region")
    c, w, v = g.attr("c", True), g.attr("w", True), g.attr("bnorm", True)

    # speech bursts flowing along the knot, gated by the speaking regions
    s = None
    for f, wt, ph in WORDS:
        term = g.math("MULTIPLY", g.wave(phi, f, f * WORD_TRAVEL, ph), wt)
        s = term if s is None else g.math("ADD", s, term)
    words = g.math("POWER", g.math("MAXIMUM", g.math("MULTIPLY_ADD", s, 0.4, 0.5), 0.0), WORD_POWER)
    words = g.math("MINIMUM", words, 1.0)
    env = g.math("MULTIPLY_ADD", g.math("MULTIPLY", reg, words), 1.0 - Q0, Q0)

    bf, bc, ba = BREATH
    breath = g.math("MULTIPLY_ADD", g.wave(phi, bf, bc, 0.0), ba, 1.0)
    hw = g.math("MULTIPLY", g.math("MULTIPLY_ADD", env, HW_L - HW_Q, HW_Q), breath)

    lf, lc, la, lsp = LAT
    sway = g.wave(phi, lf, lc, g.math("MULTIPLY_ADD", u, lsp, g.math("MULTIPLY", k, 0.6)))
    lat = g.math("MULTIPLY", hw, g.math("MULTIPLY_ADD", g.math("MULTIPLY", sway, env), la, u))

    # each voice group: sin(gf * phi + gp - TAU * gc * tau), scaled by the speaking envelope
    arg = g.math("MULTIPLY_ADD", g.attr("gf"), phi,
                 g.math("MULTIPLY_ADD", g.attr("gc"), g.math("MULTIPLY", g.tau, -TAU), g.attr("gp")))
    amp = g.math("MULTIPLY", g.math("MULTIPLY", reg, g.math("MULTIPLY_ADD", words, 0.45, 0.55)),
                 g.math("MULTIPLY", g.attr("ga"), VOICE_AMP))
    lat = g.math("MULTIPLY_ADD", g.math("SINE", arg), amp, lat)

    rf, rc, ra, rsp = RIP
    rip = g.wave(phi, rf, rc, g.math("MULTIPLY", u, rsp))
    nor = g.math("MULTIPLY", g.math("MULTIPLY", rip, env), ra)

    pos = g.vmath("ADD", c, g.vmath("SCALE", w, scale=lat))
    pos = g.vmath("ADD", pos, g.vmath("SCALE", v, scale=nor))

    geo = g.inp.outputs[0]
    geo = g.store(geo, "env", env)
    geo = g.store(geo, "hwn", g.math("DIVIDE", hw, HW_L))
    g.finish(geo, pos, g.attr("rad"), material)
    return g.t


def glyph_nodes(loop_frames, material):
    g = GN("ResonanceTokens", loop_frames)
    life = g.math("FRACT", g.math("MULTIPLY_ADD", g.tau, float(GLYPH_CYCLES), g.attr("birth")))
    ease = g.math("SUBTRACT", 1.0, g.math("POWER", g.math("SUBTRACT", 1.0, life), 1.25))
    pos = g.vmath("ADD", g.attr("o", True), g.vmath("SCALE", g.attr("d", True), scale=ease))
    geo = g.store(g.inp.outputs[0], "life", life)
    g.finish(geo, pos, g.attr("rad"), material)
    return g.t


# ======================= scene objects =======================

def link(ob, parent):
    bpy.context.scene.collection.objects.link(ob)
    ob.parent = parent
    return ob


def empty(name, parent):
    ob = bpy.data.objects.new(name, None)
    ob.empty_display_size = 0.2
    return link(ob, parent)


def hair(name, sizes, positions, float_attrs, vec_attrs):
    """A hair-curves datablock (rendered by Cycles as true curves) with per-point attributes."""
    hc = bpy.data.hair_curves.new(name)
    hc.add_curves(list(sizes))
    hc.position_data.foreach_set("vector", np.ascontiguousarray(positions, dtype=np.float32).ravel())
    for key, arr in float_attrs.items():
        hc.attributes.new(key, "FLOAT", "POINT").data.foreach_set("value", np.ascontiguousarray(arr, dtype=np.float32))
    for key, arr in vec_attrs.items():
        hc.attributes.new(key, "FLOAT_VECTOR", "POINT").data.foreach_set(
            "vector", np.ascontiguousarray(arr, dtype=np.float32).ravel())
    return hc


def build_ribbon(parent, rng, loop_frames):
    """Each filament is an open curve whose last point repeats the first (all modulation is periodic in phi)."""
    M = ALONG
    phi = np.linspace(0.0, TAU, M + 1)
    C, T, W, V = knot_frame(phi)
    reg = region(phi)

    base_u = np.linspace(-1.0, 1.0, STRANDS)
    spacing = 2.0 / (STRANDS - 1)
    us, ks, gains, edges_f, rads = [], [], [], [], []
    for i, u0 in enumerate(base_u):
        u = float(np.clip(u0 + rng.gauss(0.0, 0.3) * spacing, -1.0, 1.0))
        hero = rng.random() < 0.08
        us.append(u)
        ks.append(rng.random())
        gains.append((1.9 if hero else 1.0) * (0.55 + 0.45 * rng.random()))
        edges_f.append(0.5 + 0.5 * (1.0 - u * u))
        rads.append(FIL_RADIUS * (1.25 if hero else rng.uniform(0.85, 1.1)))
    for i in range(STRAYS):
        side = 1 if i % 2 == 0 else -1
        us.append(side * rng.uniform(1.12, 1.55))
        ks.append(rng.random())
        gains.append(0.35 + 0.3 * rng.random())
        edges_f.append(0.6)
        rads.append(FIL_RADIUS * 0.8)

    S = len(us)
    n = M + 1
    G = len(VOICES)
    groups = [min(G - 1, max(0, int((u + 1.0) / 2.0 * G))) for u in us]
    voice = {key: [VOICES[gi][j] for gi in groups] for j, key in enumerate(("gf", "gc", "gp", "ga"))}
    rep = lambda vals: np.repeat(np.asarray(vals, dtype=np.float64), n)
    me = hair(
        "Ribbon", [n] * S, np.tile(C, (S, 1)),
        {"phi": np.tile(phi, S), "u": rep(us), "k": rep(ks), "gain": rep(gains), "edge": rep(edges_f),
         "rad": rep(rads), "region": np.tile(reg, S), **{key: rep(v) for key, v in voice.items()}},
        {"c": np.tile(C, (S, 1)), "w": np.tile(W, (S, 1)), "bnorm": np.tile(V, (S, 1))},
    )
    ob = link(bpy.data.objects.new("Ribbon", me), parent)
    mat = ribbon_material(1.15)
    me.materials.append(mat)
    mod = ob.modifiers.new("Resonance", "NODES")
    mod.node_group = ribbon_nodes(loop_frames, mat)
    return ob


# tokens: arcs of word-length strokes that lift off the outer edge of the main speaking lobe and expand outward
TOKEN_ARCS = 4
TOKEN_SPAN = 0.36                  # arc extent in knot parameter around the lobe centre
TOKEN_DRIFT = 0.42                 # how far an arc travels over one life
TOKEN_LENGTHS = (0.022, 0.032, 0.044, 0.058, 0.076, 0.096)


def _knot_point(ph):
    C, T, W, V = (Vector(a[0]) for a in knot_frame(np.array([ph])))
    return C, T, W, V


def build_tokens(parent, rng, loop_frames):
    """Each arc is a 'line of text': strokes of word-like lengths separated by word gaps, laid along the outer edge
    of the speaking lobe. Every stroke drifts straight out from the knot's axis, so an arc widens as it rises, and
    strokes dissolve one by one at random points of their life, so older lines are sparser."""
    centre = LOUD[0][0]
    verts, orig, drift = [], [], []
    attrs = {k: [] for k in ("birth", "rad", "gain", "warm", "dis")}
    edge_off = HW_L * 0.95 + 0.03
    for i in range(TOKEN_ARCS):
        birth = (i + 0.12 + rng.uniform(-0.05, 0.05)) / TOKEN_ARCS
        span = TOKEN_SPAN * rng.uniform(0.75, 1.1)
        ph = centre - span / 2 + rng.uniform(-0.03, 0.03)
        end = centre + span / 2
        lift = rng.uniform(-0.02, 0.06)
        while ph < end:
            C, T, W, V = _knot_point(ph)
            speed = (Vector(knot_frame(np.array([ph + 1e-3]))[0][0]) - C).length / 1e-3
            L = rng.choice(TOKEN_LENGTHS)
            gap = rng.uniform(0.016, 0.026) + (0.05 if rng.random() < 0.12 else 0.0)
            ph1 = ph + L / speed
            if rng.random() > 0.3:
                pts = []
                for q in (ph, ph1):
                    Cq, _, _, _ = _knot_point(q)
                    out = Vector((Cq.x, Cq.y, 0.0)).normalized()
                    pts.append((Cq + out * edge_off, out))
                d = (pts[0][1] + pts[1][1]).normalized() * TOKEN_DRIFT * rng.uniform(0.85, 1.2) \
                    + Vector((0.0, 0.0, lift + rng.uniform(-0.01, 0.01)))
                for p_, _ in pts:
                    verts.append(tuple(p_))
                    orig.append(tuple(p_))
                    drift.append(tuple(d))
                vals = (("birth", (birth + rng.uniform(-0.03, 0.03)) % 1.0), ("rad", rng.uniform(0.0032, 0.0040)), ("gain", rng.uniform(0.75, 1.0)),
                        ("warm", rng.uniform(0.35, 1.0)), ("dis", rng.uniform(0.4, 1.02)))
                for key, val in vals:
                    attrs[key] += [val, val]
            ph = ph1 + gap / speed
    n = len(verts) // 2
    me = hair("Tokens", [2] * n, np.array(verts), attrs, {"o": np.array(orig), "d": np.array(drift)})
    ob = link(bpy.data.objects.new("Tokens", me), parent)
    mat = glyph_material(2.5)
    me.materials.append(mat)
    mod = ob.modifiers.new("Resonance", "NODES")
    mod.node_group = glyph_nodes(loop_frames, mat)
    return ob


def build(seed, loop_frames):
    rng = random.Random(seed)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    root = bpy.data.objects.new("Resonance", None)
    scene.collection.objects.link(root)
    root.location = ROOT_OFFSET
    root.rotation_euler = (0.0, math.radians(ROLL), 0.0)
    tilt = empty("Resonance.tilt", root)
    tilt.rotation_euler = (math.radians(TILT_X), math.radians(TILT_Y), 0.0)
    spin = empty("Resonance.spin", tilt)
    spin.rotation_euler = (0.0, 0.0, math.radians(SPIN0))
    build_ribbon(spin, rng, loop_frames)
    build_tokens(spin, rng, loop_frames)
    return scene, [(spin, TAU)]


def animate(scene, spinners, frames, fps):
    bpy.context.preferences.edit.keyframe_new_interpolation_type = "LINEAR"
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
    scene.cycles.transparent_max_bounces = 160
    scene.cycles_curves.shape = "RIBBONS"
    scene.cycles_curves.subdivisions = 2
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
    cam.rotation_euler = (Vector((0, 0, 0)) - cam.location).to_track_quat("-Z", "Y").to_euler()
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
    node.inputs["Smoothness"].default_value = 0.4
    node.inputs["Strength"].default_value = strength
    node.inputs["Size"].default_value = size
    return node


def setup_bloom(scene):
    """A tight halation that makes filaments read as light, a wider glow that only the edge-on folds reach, and a
    small black level so the bloom tail returns to true black."""
    tree = bpy.data.node_groups.new("ResonanceComposite", "CompositorNodeTree")
    tree.interface.new_socket(name="Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    layers = tree.nodes.new("CompositorNodeRLayers")
    out = tree.nodes.new("NodeGroupOutput")
    tight = _glare(tree, 0.25, 0.45, 0.3)
    glow = _glare(tree, 0.8, 0.28, 0.55)
    curves = tree.nodes.new("CompositorNodeCurveRGB")
    curves.inputs["Black Level"].default_value = (0.004, 0.004, 0.004, 1.0)
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
    a = parse_args()
    os.makedirs(a.out, exist_ok=True)
    frames = int(round(a.seconds * a.fps))
    scene, spinners = build(a.seed, frames)
    setup_render(scene, a.res, a.samples)
    setup_bloom(scene)
    animate(scene, spinners, frames, a.fps)
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
        scene.render.filepath = os.path.join(a.out, "resonance_loop.mp4")
        bpy.ops.render.render(animation=True)
    else:
        scene.frame_set(a.frame)
        scene.render.image_settings.file_format = "PNG"
        scene.render.filepath = os.path.join(a.out, a.still)
        bpy.ops.render.render(write_still=True)
    print("DONE", scene.render.filepath)


main()
