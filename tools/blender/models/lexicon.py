"""PrepSuite presence, model 1: "Lexicon". A globe written in language, with a voice at its heart.

The globe keeps the DNA of presence_final.py (a sphere read through tilted latitude bands, front bright and far
side faint, one sweeping crescent, a luminous centre) but every band is now a line of real text: PrepSuite's own
interview questions, set in the app's serif (Newsreader) and wrapped around the sphere. Under each line a hairline
is broken into TOKENS, the units a language model reads and writes; a few key tokens are marked in deep teal, the
way a model attends to the words that matter.

A thin meridian of light is the caret. It sweeps around the globe, and the text it has just passed glows while the
text ahead of it waits dim: the model writing its question, line by line, in real time. At the centre, a radial
voiceprint (a small champagne nucleus inside fine bars whose lengths follow a speech envelope, teal peak marks at
the tips) says that the words are spoken aloud.

Run headless:
    Blender -b --factory-startup --python-exit-code 1 --python lexicon.py -- [options]

Options: --out DIR  --res PX  --samples N  --frame F  --animation  --seconds S  --fps N  --still NAME  --no-render
Writes presence.blend and a PNG still (or an MP4 loop). Every part turns by a whole symmetry sector per loop (the
caret by one full turn), so any loop length is seamless; 16 s keeps the text drifting at a few degrees a second.
"""

import argparse
import math
import os
import random
import sys

import bpy
from mathutils import Vector

OUT_DEFAULT = "/Users/macintosh/Documents/PrepSuite/tools/blender/out/models/lexicon"
FONT_PATH = "/Users/macintosh/Documents/PrepSuite/app/src/main/res/font/newsreader.ttf"

# Scene-linear colours for the Standard view transform. Champagne and pale brass carry the text; a deep teal is the
# only secondary. Bright parts are sized so only red clips (champagne), never all three channels (white).
TEXT = (0.92, 0.62, 0.30)       # pale brass
CHAMPAGNE = (1.0, 0.68, 0.34)   # highlighted tokens, caret
NUCLEUS = (1.0, 0.60, 0.26)
VOICE = (1.0, 0.58, 0.25)
TEAL = (0.015, 0.36, 0.30)      # deep teal: key tokens
TEAL_TIP = (0.015, 0.40, 0.33)  # voiceprint envelope

CAM_LOC = Vector((0.0, -4.6, 0.25))
SPHERE_R = 1.10
GLOBE_TILT = 23.0
FULL = 2 * math.pi

# Depth windows (camera distance either side of the sphere centre): full strength across the face of the sphere,
# fading toward the silhouette and the far side.
GLOBE_FADE = (0.66, 0.22)
CARET_FADE = (0.40, 0.55)
TEXT_FAR = 0.055

# Text that passes in front of or behind the voiceprint dims inside this aperture around the line of sight.
CLEAR = (0.36, 0.48, 0.10)

# The voiceprint: bar count and the radius of its baseline circle. It turns once per loop (one sector).
VOICE_BARS = 96
VOICE_RADIUS = 0.20
VOICE_REACH = 0.16

# Type: world units per em (x-height of Newsreader = 0.336 em, so about 1 degree of latitude on the sphere).
EM = 0.052
UNDERLINE_Y = -0.27       # em, just under the descenders
TOKEN_GAP = 0.09          # em trimmed from each end of a token's underline, so tokens read as separate units
SENTENCE_GAP = (1.4, 3.2)  # em between questions (min, max)

# The caret wakes the text it passes: text behind it glows and settles back over TRAIL_SPAN degrees.
TRAIL_SPAN = 160.0
TRAIL_AHEAD = 0.5
TRAIL_PEAK = 1.25
DIAL = True


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
    p.add_argument("--seed", type=int, default=5)
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
    """`floor` within r0 of the camera's line of sight through the centre, 1.0 beyond r1."""
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


def _trail_factor(nt, caret):
    """Longitude behind the caret (read in the caret's own frame, so it follows the caret as it turns):
    PEAK just behind it, settling to AHEAD over TRAIL_SPAN degrees; everything ahead of it waits at AHEAD."""
    tc = nt.nodes.new("ShaderNodeTexCoord")
    tc.object = caret
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs[0])
    a = _math(nt, "ARCTAN2", sep.outputs["Y"], sep.outputs["X"])
    behind = _math(nt, "LESS_THAN", a, 0.0)
    u = _math(nt, "MAXIMUM", _math(nt, "MULTIPLY_ADD", a, 1.0 / math.radians(TRAIL_SPAN), 1.0), 0.0)
    g = _math(nt, "MULTIPLY", _math(nt, "POWER", u, 2.2), behind)
    return _math(nt, "MULTIPLY_ADD", g, TRAIL_PEAK - TRAIL_AHEAD, TRAIL_AHEAD)


def _radial_factor(nt, r0, r1, v0, v1):
    """Along the voiceprint bars: v0 at radius r0 from the centre, v1 at r1."""
    tc = nt.nodes.new("ShaderNodeTexCoord")
    ln = nt.nodes.new("ShaderNodeVectorMath")
    ln.operation = "LENGTH"
    nt.links.new(tc.outputs["Object"], ln.inputs[0])
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.clamp = True
    nt.links.new(ln.outputs["Value"], mr.inputs[0])
    mr.inputs[1].default_value = r0
    mr.inputs[2].default_value = r1
    mr.inputs[3].default_value = v0
    mr.inputs[4].default_value = v1
    return mr.outputs[0]


def emissive(name, color, strength, far_gain=None, facing=None, window=GLOBE_FADE, clear=None, trail=None,
             radial=None):
    m, nt, em = _base_material(name)
    em.inputs["Color"].default_value = (*color, 1.0)
    factors = []
    if clear:
        factors.append(_clear_factor(nt, *clear))
    if far_gain is not None:
        factors.append(_depth_factor(nt, far_gain, *window))
    if facing:
        factors.append(_facing_factor(nt, facing))
    if trail is not None:
        factors.append(_trail_factor(nt, trail))
    if radial:
        factors.append(_radial_factor(nt, *radial))
    s = float(strength)
    for f in factors:
        s = _math(nt, "MULTIPLY", f, s)
    if isinstance(s, float):
        em.inputs["Strength"].default_value = s
    else:
        nt.links.new(s, em.inputs["Strength"])
    return m


def halo_material(name, inner, outer, strength, falloff):
    """Brightest where the surface faces the camera, so a small sphere reads as a soft point of light.
    A ray crosses both the front and the back of the sphere, so the centre gets twice `strength`."""
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


def curve_object(name, splines, bevel, materials, parent, closed=False):
    """splines: list of (points, radii, material index). Radii scale the bevel per point (tapered strokes).
    A stroke is a thin tube, so a ray through its middle picks up its emission twice (front and back wall)."""
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = bevel
    cu.bevel_resolution = 2
    cu.use_fill_caps = False
    for spline in splines:
        pts, radii = spline[0], spline[1] or [1.0] * len(spline[0])
        sp = cu.splines.new("POLY")
        sp.points.add(len(pts) - 1)
        for i, (p, r) in enumerate(zip(pts, radii)):
            sp.points[i].co = (p.x, p.y, p.z, 1.0)
            sp.points[i].radius = r
        sp.use_cyclic_u = closed
        sp.material_index = spline[2] if len(spline) > 2 else 0
    for m in materials if isinstance(materials, (list, tuple)) else [materials]:
        cu.materials.append(m)
    return link(bpy.data.objects.new(name, cu), parent)


def mesh_object(name, verts, faces, materials, parent, face_mats=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    for m in materials:
        me.materials.append(m)
    if face_mats:
        me.polygons.foreach_set("material_index", face_mats)
    me.update()
    return link(bpy.data.objects.new(name, me), parent)


def steps(a0, a1, step_deg):
    n = max(2, int(abs(a1 - a0) / math.radians(step_deg)) + 1)
    return [a0 + (a1 - a0) * i / (n - 1) for i in range(n)]


def sph(r, lat, lon):
    return Vector((r * math.cos(lat) * math.cos(lon), r * math.cos(lat) * math.sin(lon), r * math.sin(lat)))


def ring(radius, step_deg=0.6):
    n = int(360 / step_deg)
    return [Vector((radius * math.cos(FULL * i / n), radius * math.sin(FULL * i / n), 0.0)) for i in range(n)]


def taper(n, floor=0.0, power=1.0):
    return [floor + (1 - floor) * math.sin(math.pi * i / (n - 1)) ** power for i in range(n)]


def facing_quat():
    """Rotation that turns an object's local +Z toward the camera (for discs that must stay perfectly round)."""
    return CAM_LOC.normalized().to_track_quat("Z", "Y")


def uv_sphere(name, radius, material, parent, segments=48, rings=24):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, segments=segments, ring_count=rings)
    ob = bpy.context.active_object
    bpy.ops.object.shade_smooth()
    ob.name = name
    ob.data.materials.append(material)
    ob.parent = parent
    return ob


# ---------- type ----------

class Type:
    """Glyph outlines and advances from a real font, via temporary Blender text objects."""

    def __init__(self, path, resolution=3):
        self.font = bpy.data.fonts.load(path)
        self.resolution = resolution
        self._glyphs = {}
        self._adv = {}
        self._l = self._outline("l")[2]

    def _outline(self, s):
        cu = bpy.data.curves.new("_type", "FONT")
        cu.body = s
        cu.font = self.font
        cu.size = 1.0
        cu.resolution_u = self.resolution
        ob = bpy.data.objects.new("_type", cu)
        bpy.context.scene.collection.objects.link(ob)
        dg = bpy.context.evaluated_depsgraph_get()
        me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
        verts = [(v.co.x, v.co.y) for v in me.vertices]
        faces = [tuple(p.vertices) for p in me.polygons]
        xmax = max((x for x, _ in verts), default=0.0)
        bpy.data.objects.remove(ob)
        bpy.data.curves.remove(cu)
        bpy.data.meshes.remove(me)
        return verts, faces, xmax

    def glyphs(self, s):
        if s not in self._glyphs:
            self._glyphs[s] = self._outline(s)[:2] if s.strip() else ([], [])
        return self._glyphs[s]

    def advance(self, s):
        """Pen advance of s (a trailing 'l' makes spaces and side bearings count)."""
        if s not in self._adv:
            self._adv[s] = self._outline(s + "l")[2] - self._l
        return self._adv[s]


# Interview questions, split into tokens the way a language model's tokenizer would ("|" marks a boundary; a
# token's leading space belongs to it). "*" marks a key token (deep teal), "^" a highlighted one (brighter).
QUESTIONS = [
    "Tell| me| about| a| time| you| led| a| *team| through| a| diff|icult| *change|.",
    "What| is| the| hardest| *decision| you| have| made|,| and| ^why|?",
    "Walk| me| through| a| *project| you| are| most| ^proud| of|.",
    "How| do| you| handle| dis|agreement| with| your| *manager|?",
    "Describe| a| time| you| *failed|,| and| what| you| ^learned|.",
    "How| would| you| *prior|it|ize| compet|ing| dead|lines|?",
    "Tell| me| about| a| time| you| worked| through| *ambig|uity|.",
    "Why| do| you| want| this| *role|?",
    "What| would| your| *stake|holders| say| about| ^you|?",
    "Where| do| you| see| yourself| in| five| *years|?",
    "What| is| a| *risk| you| took| that| paid| off|?",
    "Tell| me| about| your|self|.",
]

KIND = {"": 0, "*": 1, "^": 2}   # glyph material slots: text, key (teal), highlight

# latitude (deg), candidate symmetries, first question index, strength
BANDS = [
    (60, (3,), 7, 0.85),
    (38, (3, 4), 1, 0.95),
    (1, (4, 3), 0, 1.0),
    (-22, (4, 3), 4, 1.0),
    (-44, (3, 4), 8, 0.9),
]


def parse_question(q):
    tokens = []
    for raw in q.split("|"):
        lead = raw[: len(raw) - len(raw.lstrip(" "))]
        body = raw.lstrip(" ")
        mark = body[0] if body[:1] in ("*", "^") else ""
        tokens.append((lead, body[len(mark):], KIND[mark]))
    return tokens


def question_width(tt, tokens):
    return sum(tt.advance(lead + body) for lead, body, _ in tokens)


def layout_band(tt, lat, symmetries, first):
    """Fill one symmetry sector of a band with whole questions. Returns (symmetry, x-scale, placed tokens) where
    each placed token is (pen x in em, lead, body, kind); the sector's em width maps exactly onto 360/k degrees."""
    circumference_em = FULL * SPHERE_R * math.cos(math.radians(lat)) / EM
    best = None
    for k in symmetries:
        target = circumference_em / k
        for shift in range(4):          # starting a little later in the list is fine if it sets more evenly
            for n in range(1, 6):
                qs = [QUESTIONS[(first + shift + i) % len(QUESTIONS)] for i in range(n)]
                toks = [parse_question(q) for q in qs]
                text_w = sum(question_width(tt, t) for t in toks)
                gap = min(max((target - text_w) / n, SENTENCE_GAP[0]), SENTENCE_GAP[1])
                scale = target / (text_w + n * gap)
                score = abs(math.log(scale)) + 0.02 * symmetries.index(k) + 0.01 * shift
                if best is None or score < best[0]:
                    best = (score, k, scale, toks, gap)
    _, k, scale, toks, gap = best
    placed, pen = [], 0.0
    for q in toks:
        for lead, body, kind in q:
            placed.append((pen + (tt.advance(lead) if lead else 0.0), lead, body, kind))
            pen += tt.advance(lead + body)
        pen += gap
    return k, scale, placed


# ---------- the presence ----------

def build_caret(globe):
    """The caret: a thin tapered meridian of light just above the text, turning once around the globe per loop."""
    holder = empty("Caret", globe)
    spin = empty("Caret.spin", holder)
    spin.rotation_euler = (0.0, 0.0, math.radians(-56.0))   # front of the globe is longitude -90
    r = SPHERE_R * 1.012
    lats = steps(math.radians(-74), math.radians(74), 0.4)
    pts = [sph(r, t, 0.0) for t in lats]
    mat = emissive("Caret", CHAMPAGNE, 0.44, far_gain=0.18, facing=0.8, window=CARET_FADE, clear=(0.30, 0.40, 0.10))
    curve_object("Caret.stroke", [(pts, taper(len(pts), 0.03, 0.9))], 0.0055, mat, spin)
    glow = emissive("Caret.glow", CHAMPAGNE, 0.06, far_gain=0.1, facing=2.0, window=CARET_FADE, clear=(0.30, 0.40, 0.10))
    curve_object("Caret.glow", [(pts, taper(len(pts), 0.0, 1.4))], 0.020, glow, spin)
    return spin


def build_text(globe, caret, rng):
    """Five lines of text around the sphere, each with its token rule underneath. All lines drift the same way
    (right to left across the face, like reading) at speeds set by their symmetry."""
    tt = Type(FONT_PATH)
    common = dict(far_gain=TEXT_FAR, clear=CLEAR, trail=caret)
    glyph_mats = [
        emissive("Text", TEXT, 1.15, **common),
        emissive("Text.key", TEAL, 1.1, **common),
        emissive("Text.highlight", CHAMPAGNE, 1.35, **common),
    ]
    rule_mats = [
        emissive("Rule", TEXT, 0.55, **common),
        emissive("Rule.key", TEAL_TIP, 1.2, **common),
        emissive("Rule.highlight", CHAMPAGNE, 0.9, **common),
    ]
    spinners = []
    for lat, symmetries, first, strength in BANDS:
        k, scale, placed = layout_band(tt, lat, symmetries, first)
        phi = math.radians(lat)
        lon_per_em = EM * scale / (SPHERE_R * math.cos(phi))
        phase = rng.uniform(0.0, FULL / k)
        verts, faces, fmats, rules = [], [], [], []

        def to_sphere(x, y, lon0):
            return sph(SPHERE_R, phi + y * EM / SPHERE_R, lon0 + x * lon_per_em)

        for j in range(k):
            lon0 = phase + j * FULL / k
            for pen, lead, body, kind in placed:
                gv, gf = tt.glyphs(body)
                base = len(verts)
                verts += [to_sphere(pen + x, y, lon0) for x, y in gv]
                faces += [tuple(base + i for i in f) for f in gf]
                fmats += [kind] * len(gf)
                if gv:
                    x0 = min(x for x, _ in gv) + TOKEN_GAP
                    x1 = max(x for x, _ in gv) - TOKEN_GAP
                    if x1 - x0 < 0.05:
                        x0, x1 = (x0 + x1) / 2 - 0.03, (x0 + x1) / 2 + 0.03
                    a0, a1 = lon0 + (pen + x0) * lon_per_em, lon0 + (pen + x1) * lon_per_em
                    lat_r = phi + UNDERLINE_Y * EM / SPHERE_R
                    pts = [sph(SPHERE_R, lat_r, a) for a in steps(a0, a1, 0.4)]
                    rules.append((pts, None, kind))
        band = mesh_object(f"Line{lat:+d}", verts, faces, glyph_mats, globe, fmats)
        curve_object(f"Line{lat:+d}.tokens", rules, 0.0011 * strength, rule_mats, band)
        spinners.append((band, -FULL / k))
        print(f"LINE lat={lat} k={k} scale={scale:.3f} tokens={len(placed)} verts={len(verts)}")
    return spinners


def speech_envelope(n, rng):
    """Bar levels (0..1) for n bars around the circle: a smooth, irregular contour (a few harmonics with random
    phases, sharpened so it has distinct voiced peaks over quieter stretches), closed around the circle."""
    terms = [(k, rng.uniform(0.0, FULL), 1.0 / k ** 0.75) for k in range(2, 11)]
    raw = [sum(amp * math.cos(k * FULL * i / n + ph) for k, ph, amp in terms) for i in range(n)]
    lo, hi = min(raw), max(raw)
    return [((v - lo) / (hi - lo)) ** 1.7 for v in raw]


def build_voiceprint(parent, rng):
    """The voice: a small champagne nucleus, a clear gap, then a ring of fine radial hairlines rising from a crisp
    base circle, their lengths a speech envelope; the outer part of every bar is deep teal, so the envelope is drawn
    in teal around a champagne body. It faces the viewer, so it always reads as a clean dial."""
    holder = empty("Voice", parent)
    holder.rotation_mode = "QUATERNION"
    holder.rotation_quaternion = facing_quat()
    uv_sphere("Voice.nucleus", 0.019, halo_material("Nucleus", NUCLEUS, VOICE, 0.42, 1.4), holder, 32, 16)
    uv_sphere("Voice.glow", 0.13, halo_material("Voice.glow", VOICE, VOICE, 0.05, 7.0), holder)

    spin = empty("Voice.spin", holder)
    n, r0, l_min, l_max = VOICE_BARS, VOICE_RADIUS, 0.012, VOICE_REACH
    env = speech_envelope(n, rng)
    bars, tips = [], []
    for i, e in enumerate(env):
        a = FULL * i / n
        d = Vector((math.cos(a), math.sin(a), 0.0))
        length = l_min + (l_max - l_min) * e
        split = r0 + 0.70 * length
        bars.append(([d * r0, d * split], None))
        tips.append(([d * (split + 0.003), d * (r0 + length)], None))
    curve_object("Voice.bars", bars, 0.0013,
                 emissive("Voice.bars", VOICE, 1.05, radial=(r0, r0 + l_max, 1.0, 0.62)), spin)
    curve_object("Voice.peaks", tips, 0.0013, emissive("Voice.peaks", TEAL_TIP, 0.62), spin)
    curve_object("Voice.base", [(ring(r0 - 0.012, 0.4), None)], 0.0009, emissive("Voice.base", VOICE, 0.45), spin,
                 closed=True)
    return [(spin, FULL)]   # one turn per loop: the envelope has no repeat, so it needs the whole circle


def build_dial(parent):
    """A faint minute track just outside the globe, facing the viewer: the watch-dial frame of the page."""
    holder = empty("Dial", parent)
    holder.rotation_mode = "QUATERNION"
    holder.rotation_quaternion = facing_quat()
    spin = empty("Dial.spin", holder)
    r = 1.19
    curve_object("Dial.line", [(ring(r, 0.4), None)], 0.0011, emissive("Dial.line", TEXT, 0.10), spin, closed=True)
    minor, major = [], []
    for i in range(120):
        a = FULL * i / 120
        d = Vector((math.cos(a), math.sin(a), 0.0))
        (major if i % 10 == 0 else minor).append(([d * (r + 0.006), d * (r + (0.03 if i % 10 == 0 else 0.014))], None))
    curve_object("Dial.ticks", minor, 0.0012, emissive("Dial.ticks", TEXT, 0.14), spin)
    curve_object("Dial.major", major, 0.0014, emissive("Dial.major", CHAMPAGNE, 0.26), spin)
    return [(spin, -FULL / 12)]


def build(seed):
    rng = random.Random(seed)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene

    root = bpy.data.objects.new("Presence", None)
    scene.collection.objects.link(root)
    globe = empty("Globe", root)
    globe.rotation_euler = (math.radians(GLOBE_TILT), 0.0, 0.0)

    caret = build_caret(globe)
    spinners = [(caret, FULL)]
    spinners += build_text(globe, caret, rng)
    spinners += build_voiceprint(root, rng)
    if DIAL:
        spinners += build_dial(root)
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
        # The preference above is not honoured in background mode, so the keys would ease in and out (a stall at
        # every loop point). Force constant speed on the keys themselves.
        for fc in _fcurves(ob):
            for kp in fc.keyframe_points:
                kp.interpolation = "LINEAR"


def _fcurves(ob):
    ad = ob.animation_data
    try:
        return list(ad.action.fcurves)          # legacy actions
    except AttributeError:
        from bpy_extras import anim_utils       # layered actions (Blender 4.4+)
        return list(anim_utils.action_get_channelbag_for_slot(ad.action, ad.action_slot).fcurves)


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
    """A tight halation on the strokes plus a small glow that only the voiceprint and caret reach; a small black
    level afterwards keeps the background true black."""
    tree = bpy.data.node_groups.new("LexiconComposite", "CompositorNodeTree")
    tree.interface.new_socket(name="Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    layers = tree.nodes.new("CompositorNodeRLayers")
    out = tree.nodes.new("NodeGroupOutput")
    tight = _glare(tree, 0.22, 0.30, 0.24)
    glow = _glare(tree, 0.85, 0.32, 0.55)
    curves = tree.nodes.new("CompositorNodeCurveRGB")
    curves.inputs["Black Level"].default_value = (0.003, 0.003, 0.003, 1.0)
    tree.links.new(layers.outputs["Image"], tight.inputs["Image"])
    tree.links.new(tight.outputs["Image"], glow.inputs["Image"])
    tree.links.new(glow.outputs["Image"], curves.inputs["Image"])
    tree.links.new(curves.outputs["Image"], out.inputs[0])
    scene.compositing_node_group = tree


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
