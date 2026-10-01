"""PrepSuite assistant: a friendly robot with a glass face screen and a headset.

Design: a glossy ceramic head and a satin body (two finishes, warm off-white), a deep black visor with
one soft reflection, a slim egg body with a shadow-gap parting line, one-piece flipper arms, and muted
anodised accents. The ear rings are the only lights.

The face (eyes and mouth) is NOT rendered here. The app draws it live on the visor so the mouth moves with the
voice and the eyes blink, look and react. This script renders the parts that stay still, per colour variant:

  <variant>_body.png   the robot, lights dimmed, visor matte dark (RGBA, transparent background)
  <variant>_glass.png  only the visor's reflections, on black (the app draws it over the face)
  <variant>_glow.png   only the lights (the ear rings), on black, no bloom
  <variant>_beauty.png everything together for previews (visor reflective, lights on)
  face.json            the visor outline in normalised image coordinates, for clipping the live face

Then export_assistant.py turns them into the app's WebP layers in assets/assistant/.

Run headless (1536 px, 128 samples takes about 20 minutes for all four on an M3):
    Blender -b --factory-startup --python-exit-code 1 --python assistant.py -- --res 1536 --samples 128
    python3 export_assistant.py <out dir>

Options: --out DIR  --res PX  --samples N  --variants nova,sol,iris,mint  --passes body,glass,glow,beauty
         --pose idle|wave  --no-render
"""

import argparse
import json
import math
import os
import sys

import bmesh
import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Euler, Matrix, Vector

OUT_DEFAULT = "/Users/macintosh/Documents/PrepSuite/tools/blender/out/assistant"
HDRI = os.path.join(os.path.dirname(bpy.app.binary_path), "..", "Resources",
                    f"{bpy.app.version[0]}.{bpy.app.version[1]}", "datafiles", "studiolights", "world", "studio.exr")

# Geometry (Blender units). Z up, the robot faces -Y, the camera looks along +Y.
HEAD_C = Vector((0.0, 0.0, 1.55))
HEAD_R = (1.0, 0.88, 0.86)
VISOR_W, VISOR_H, VISOR_N = 0.76, 0.50, 3.1      # superellipse half-width, half-height, exponent
VISOR_ZC = HEAD_C.z - 0.03
RECESS = 0.955                                    # recess floor, as a scale of the head
VISOR_S = 0.982                                   # visor surface, as a scale of the head
BODY_C = Vector((0.0, 0.0, -0.02))
BODY_R = (0.61, 0.56, 0.72)                        # a slim upright egg, not a ball

# Linear-light colours per variant: accent (satin anodised metal, kept muted: slate blue, champagne,
# lavender grey, sage), glow (the only emissive colour: the ear rings and the live face), rim tint.
VARIANTS = {
    "nova": dict(accent=(0.16, 0.27, 0.48), glow=(0.05, 0.62, 1.0), rim=(0.35, 0.65, 1.0)),
    "sol": dict(accent=(0.69, 0.52, 0.26), glow=(1.0, 0.50, 0.10), rim=(1.0, 0.72, 0.42)),
    "iris": dict(accent=(0.37, 0.31, 0.55), glow=(0.52, 0.30, 1.0), rim=(0.62, 0.48, 1.0)),
    "mint": dict(accent=(0.27, 0.48, 0.37), glow=(0.06, 1.0, 0.66), rim=(0.40, 1.0, 0.80)),
}

EMIT_BODY = 1.6      # lights in the body pass: on, but not blooming
EMIT_GLOW = 9.0      # lights in the glow pass
EMIT_BEAUTY = 5.0


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--out", default=OUT_DEFAULT)
    p.add_argument("--res", type=int, default=1280)
    p.add_argument("--samples", type=int, default=256)
    p.add_argument("--variants", default="nova,sol,iris,mint")
    p.add_argument("--passes", default="body,glass,glow")
    p.add_argument("--pose", default="idle")
    p.add_argument("--no-render", action="store_true")
    p.add_argument("--view", default="AgX")
    p.add_argument("--look", default="AgX - Medium High Contrast")
    p.add_argument("--exposure", type=float, default=-0.3)
    p.add_argument("--tag", default="")
    p.add_argument("--wave", action="store_true")
    return p.parse_args(argv)


# ---------------------------------------------------------------------------
# Mesh helpers
# ---------------------------------------------------------------------------

def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def mesh_object(name, build):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    build(bm)
    bm.to_mesh(mesh)
    bm.free()
    return link(bpy.data.objects.new(name, mesh))


def smooth(obj, sharp_deg=None):
    """Smooth shading; with sharp_deg, edges sharper than that angle stay crisp (booleaned seams)."""
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    for f in bm.faces:
        f.smooth = True
    if sharp_deg is not None:
        limit = math.radians(sharp_deg)
        for e in bm.edges:
            if e.is_manifold and e.calc_face_angle(0.0) > limit:
                e.smooth = False
    bm.to_mesh(mesh)
    bm.free()


def ellipsoid(name, radii, center, segments=128, rings=72):
    def build(bm):
        bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=1.0)
        for v in bm.verts:
            v.co = Vector((v.co.x * radii[0], v.co.y * radii[1], v.co.z * radii[2])) + Vector(center)
    obj = mesh_object(name, build)
    smooth(obj)
    return obj


def superellipse(wx, wz, n, count, zc=0.0):
    pts = []
    for i in range(count):
        t = 2 * math.pi * i / count
        c, s = math.cos(t), math.sin(t)
        pts.append((wx * math.copysign(abs(c) ** (2 / n), c), zc + wz * math.copysign(abs(s) ** (2 / n), s)))
    return pts


def prism(name, outline, y0, y1):
    """A closed prism: the XZ outline extruded from y0 to y1."""
    def build(bm):
        front = [bm.verts.new((x, y0, z)) for x, z in outline]
        back = [bm.verts.new((x, y1, z)) for x, z in outline]
        bm.faces.new(front)
        bm.faces.new(back[::-1])
        n = len(outline)
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((front[i], back[i], back[j], front[j]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return mesh_object(name, build)


def cylinder(name, radius, depth, segments=96):
    def build(bm):
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
                              radius1=radius, radius2=radius, depth=depth)
    obj = mesh_object(name, build)
    smooth(obj, 40)
    return obj


def torus(name, major, minor, major_seg=160, minor_seg=32, keep=None):
    """A torus in the XY plane; `keep(v)` can drop vertices to make an arc."""
    def build(bm):
        rings = []
        for i in range(major_seg):
            a = 2 * math.pi * i / major_seg
            ring = []
            for j in range(minor_seg):
                b = 2 * math.pi * j / minor_seg
                r = major + minor * math.cos(b)
                ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a), minor * math.sin(b))))
            rings.append(ring)
        for i in range(major_seg):
            for j in range(minor_seg):
                i2, j2 = (i + 1) % major_seg, (j + 1) % minor_seg
                bm.faces.new((rings[i][j], rings[i2][j], rings[i2][j2], rings[i][j2]))
        if keep:
            doomed = [v for v in bm.verts if not keep(v.co)]
            bmesh.ops.delete(bm, geom=doomed, context="VERTS")
    obj = mesh_object(name, build)
    smooth(obj)
    return obj


def apply_boolean(target, cutter, operation):
    mod = target.modifiers.new("bool", "BOOLEAN")
    mod.operation = operation
    mod.object = cutter
    mod.solver = "EXACT"
    try:
        mod.material_mode = "TRANSFER"
    except (AttributeError, TypeError):
        pass
    dg = bpy.context.evaluated_depsgraph_get()
    evaluated = target.evaluated_get(dg)
    mesh = bpy.data.meshes.new_from_object(evaluated, preserve_all_data_layers=True, depsgraph=dg)
    target.modifiers.clear()
    old = target.data
    target.data = mesh
    bpy.data.meshes.remove(old)


def remove(obj):
    data = obj.data
    bpy.data.objects.remove(obj, do_unlink=True)
    if data is not None and data.users == 0:
        bpy.data.meshes.remove(data)


def bevel(obj, width, segments=3, angle=35):
    mod = obj.modifiers.new("bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(angle)
    mod.harden_normals = False
    return mod


def aim(obj, direction, up=Vector((0, 0, 1))):
    """Point the object's local +Z along `direction`."""
    obj.rotation_euler = Vector(direction).to_track_quat("Z", "Y").to_euler()


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

def principled(name, color, roughness=0.3, metallic=0.0, coat=0.0, coat_rough=0.05, emission=None, strength=0.0,
               subsurface=0.0, specular=0.5):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Coat Weight"].default_value = coat
    bsdf.inputs["Coat Roughness"].default_value = coat_rough
    bsdf.inputs["Specular IOR Level"].default_value = specular
    if subsurface:
        bsdf.inputs["Subsurface Weight"].default_value = subsurface
        bsdf.inputs["Subsurface Radius"].default_value = (0.2, 0.2, 0.25)
        bsdf.inputs["Subsurface Scale"].default_value = 0.05
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def set_input(mat, name, value):
    mat.node_tree.nodes.get("Principled BSDF").inputs[name].default_value = value


class Materials:
    def __init__(self):
        # Lacquered ceramic: a soft white base under a glossy clear coat, kept below 0.8 so the key light
        # shapes it instead of clipping it to flat white.
        # Two finishes, like a designed product: a glossy ceramic head and a satin body. Warm off-white
        # (about #ECEAE4), kept below 0.8 so the light shapes it instead of clipping it flat.
        self.shell = principled("Shell", (0.74, 0.725, 0.69), roughness=0.2, coat=0.5, coat_rough=0.04,
                                subsurface=0.04)
        self.satin = principled("Satin", (0.74, 0.725, 0.69), roughness=0.45, subsurface=0.05)
        self.accent = principled("Accent", (0.02, 0.23, 1.0), roughness=0.3, coat=0.15)
        # Dark trim: the visor gasket, the neck and the shadow gap at the waist.
        self.gasket = principled("Gasket", (0.010, 0.011, 0.014), roughness=0.55)
        self.visor = principled("Visor", (0.006, 0.008, 0.016), roughness=0.05, coat=1.0, coat_rough=0.015,
                                specular=0.8)
        self.visor_matte = principled("VisorMatte", (0.004, 0.005, 0.010), roughness=0.9, specular=0.0)
        self.light = principled("Light", (0.0, 0.0, 0.0), roughness=0.5, emission=(0.05, 0.62, 1.0),
                                strength=EMIT_BODY)
        self.core = principled("Core", (0.0, 0.0, 0.0), roughness=0.5, emission=(0.6, 0.9, 1.0),
                               strength=EMIT_BODY * 1.4)
        self.black = principled("Black", (0.0, 0.0, 0.0), roughness=1.0, specular=0.0)

    def variant(self, v):
        # Satin anodised metal: it catches the light softly instead of reading as toy plastic or bling.
        set_input(self.accent, "Base Color", (*v["accent"], 1.0))
        set_input(self.accent, "Metallic", 1.0)
        set_input(self.accent, "Roughness", 0.35)
        set_input(self.accent, "Coat Weight", 0.0)
        glow = v["glow"]
        set_input(self.light, "Emission Color", (*glow, 1.0))
        hot = tuple(min(1.0, 0.55 + 0.45 * c) for c in glow)
        set_input(self.core, "Emission Color", (*hot, 1.0))

    def emission(self, strength):
        set_input(self.light, "Emission Strength", strength)
        set_input(self.core, "Emission Strength", strength * 1.4)


# ---------------------------------------------------------------------------
# The robot
# ---------------------------------------------------------------------------

def build_head(m):
    head = ellipsoid("Head", HEAD_R, HEAD_C)
    head.data.materials.append(m.shell)

    y0, y1 = HEAD_C.y - 2.0, HEAD_C.y
    recess = prism("RecessCut", superellipse(VISOR_W * 1.045, VISOR_H * 1.07, VISOR_N, 192, VISOR_ZC), y0, y1)
    floor = ellipsoid("RecessFloor", tuple(r * RECESS for r in HEAD_R), HEAD_C)
    apply_boolean(recess, floor, "DIFFERENCE")
    remove(floor)
    recess.data.materials.append(m.gasket)
    apply_boolean(head, recess, "DIFFERENCE")
    remove(recess)
    smooth(head, 38)
    bevel(head, 0.016, 4, 38)    # a soft inward fillet into the thin dark gasket

    visor = prism("Visor", superellipse(VISOR_W, VISOR_H, VISOR_N, 192, VISOR_ZC), y0, y1)
    surface = ellipsoid("VisorSurface", tuple(r * VISOR_S for r in HEAD_R), HEAD_C)
    apply_boolean(visor, surface, "INTERSECT")
    remove(surface)
    visor.data.materials.clear()
    visor.data.materials.append(m.visor)
    smooth(visor, 38)
    bevel(visor, 0.008, 3, 38)
    return head, visor


def build_headset(m):
    parts = []
    for side in (-1, 1):
        # The ear cups sit partly inside the head; their thin ring is the robot's only glowing part.
        cup = cylinder(f"EarCup{side}", 0.265, 0.22)
        cup.rotation_euler = (0, math.radians(90), 0)
        cup.location = (side * 0.97, 0.02, HEAD_C.z - 0.02)
        cup.data.materials.append(m.shell)
        bevel(cup, 0.045, 4, 30)

        cap = cylinder(f"EarCap{side}", 0.2, 0.06)
        cap.rotation_euler = (0, math.radians(90), 0)
        cap.location = (side * 1.09, 0.02, HEAD_C.z - 0.02)
        cap.data.materials.append(m.accent)
        bevel(cap, 0.02, 3, 30)

        ring = torus(f"EarRing{side}", 0.232, 0.01)
        ring.rotation_euler = (0, math.radians(90), 0)
        ring.location = (side * 1.083, 0.02, HEAD_C.z - 0.02)
        ring.data.materials.append(m.light)
        parts += [cup, cap, ring]

    # The band over the head, leaning back so it never crosses the visor.
    band = torus("Band", 1.1, 0.038, minor_seg=24, keep=lambda co: co.y > 0.02)
    band.scale = (1.0, 0.9, 1.0)
    band.rotation_euler = (math.radians(90 - 14), 0, 0)
    band.location = (0, 0.06, HEAD_C.z + 0.02)
    band.data.materials.append(m.accent)
    parts.append(band)
    return parts


def build_body(m):
    def build(bm):
        bmesh.ops.create_uvsphere(bm, u_segments=128, v_segments=72, radius=1.0)
        for v in bm.verts:
            x, y, z = v.co
            taper = 1.0 - 0.16 * max(0.0, z)          # an egg: narrower at the shoulders
            flat = 1.0 - 0.08 * max(0.0, z) ** 2      # a softer top, with no crease
            v.co = Vector((x * BODY_R[0] * taper, y * BODY_R[1] * taper, z * BODY_R[2] * flat)) + BODY_C
    body = mesh_object("Body", build)
    smooth(body)
    body.data.materials.append(m.satin)

    # A real parting line instead of a hoop around the waist: a dark shadow gap cut into the shell.
    seam_z = BODY_C.z - 0.06
    rel = (seam_z - BODY_C.z) / BODY_R[2]
    seam_r = BODY_R[0] * math.sqrt(1 - rel * rel)
    groove = torus("GrooveCut", seam_r, 0.016, minor_seg=24)
    groove.location = (0, 0, seam_z)
    groove.scale = (1.0, BODY_R[1] / BODY_R[0], 1.0)
    groove.data.materials.append(m.gasket)
    apply_boolean(body, groove, "DIFFERENCE")
    remove(groove)
    smooth(body, 40)
    bevel(body, 0.006, 2, 40)

    # One narrow dark neck, mostly in the head's shadow, so the head seems to float.
    top = BODY_C.z + BODY_R[2] * 0.92
    column = cylinder("NeckColumn", 0.15, HEAD_C.z - HEAD_R[2] - top + 0.2)
    column.location = (0, 0.02, (top + HEAD_C.z - HEAD_R[2]) / 2)
    column.data.materials.append(m.gasket)
    return [body, column]


def _pivot(name, location, parent=None):
    empty = bpy.data.objects.new(name, None)
    link(empty)
    empty.location = location
    if parent is not None:
        empty.parent = parent
        bpy.context.view_layer.update()
        empty.matrix_parent_inverse = parent.matrix_world.inverted()
    return empty


def _attach(objs, pivot):
    bpy.context.view_layer.update()
    for o in objs:
        o.parent = pivot
        o.matrix_parent_inverse = pivot.matrix_world.inverted()


def flipper(name, length, rx, ry):
    """One smooth tapered arm, its top at the origin, hanging down -Z: full at the shoulder, a soft
    rounded tip. No elbows, cuffs or thumbs."""
    def build(bm):
        bmesh.ops.create_uvsphere(bm, u_segments=64, v_segments=40, radius=1.0)
        for v in bm.verts:
            x, y, z = v.co
            t = (1 - z) / 2                      # 0 at the top, 1 at the tip
            taper = 1.0 - 0.28 * t * t
            v.co = Vector((x * rx * taper, y * ry * taper, (z - 1) * length / 2))
    obj = mesh_object(name, build)
    smooth(obj)
    return obj


def build_arms(m, pose, rig=False):
    """Two flipper arms hanging close to the body, a little different left and right so the pose is not
    stiff. With rig=True the screen-right arm hangs from a shoulder pivot for the wave."""
    parts = []
    pivots = None
    for side in (-1, 1):
        shoulder = Vector((side * 0.585, -0.04, BODY_C.z + 0.3))
        if pose == "wave" and side == 1:
            hang = Vector((0.85, -0.2, 0.5)).normalized()
        else:
            out = 0.3 if side < 0 else 0.24
            hang = Vector((side * out, -0.16 if side < 0 else -0.1, -0.94)).normalized()
        arm = flipper(f"Arm{side}", 0.62, 0.105, 0.088)
        arm.location = shoulder
        arm.rotation_euler = hang.to_track_quat("-Z", "Y").to_euler()
        arm.data.materials.append(m.satin)
        parts.append(arm)
        if rig and side == 1:
            sp = _pivot("ShoulderPivot", shoulder)
            ep = _pivot("ElbowPivot", shoulder, sp)
            _attach([arm], ep)
            pivots = (sp, ep)
    return parts, pivots


def animate_wave(pivots, frames=40):
    """Raise the arm to the side, wave the forearm two and a half times, lower it. Smooth keys."""
    sp, ep = pivots
    raise_y = math.radians(-107.5)
    up = math.radians(-60.5)
    keys = [
        (1, 0.0, 0.0),
        (9, raise_y, up),
        (13, raise_y, up - math.radians(20)),
        (17, raise_y, up + math.radians(20)),
        (21, raise_y, up - math.radians(20)),
        (25, raise_y, up + math.radians(20)),
        (29, raise_y, up - math.radians(8)),
        (33, raise_y, up),
        (frames, 0.0, 0.0),
    ]
    for f, s_rot, e_rot in keys:
        sp.rotation_euler = (0, s_rot, 0)
        ep.rotation_euler = (0, e_rot, 0)
        sp.keyframe_insert("rotation_euler", frame=f)
        ep.keyframe_insert("rotation_euler", frame=f)
    scene = bpy.context.scene
    scene.frame_start = 1
    scene.frame_end = frames
    scene.render.fps = 24


def build(pose, rig=False):
    m = Materials()
    head, visor = build_head(m)
    parts = [head, visor]
    parts += build_headset(m)
    parts += build_body(m)
    arms, pivots = build_arms(m, pose, rig)
    parts += arms
    return m, visor, pivots


# ---------------------------------------------------------------------------
# Scene
# ---------------------------------------------------------------------------

def setup_world(scene):
    world = bpy.data.worlds.new("Studio")
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    env = nt.nodes.new("ShaderNodeTexEnvironment")
    mapping = nt.nodes.new("ShaderNodeMapping")
    coords = nt.nodes.new("ShaderNodeTexCoord")
    hdri = nt.nodes.new("ShaderNodeBackground")
    black = nt.nodes.new("ShaderNodeBackground")
    mix = nt.nodes.new("ShaderNodeMixShader")
    path = nt.nodes.new("ShaderNodeLightPath")
    try:
        env.image = bpy.data.images.load(os.path.normpath(HDRI))
    except RuntimeError:
        print("HDRI missing:", HDRI)
    mapping.inputs["Rotation"].default_value = (0, 0, math.radians(200))
    nt.links.new(coords.outputs["Generated"], mapping.inputs["Vector"])
    nt.links.new(mapping.outputs["Vector"], env.inputs["Vector"])
    nt.links.new(env.outputs["Color"], hdri.inputs["Color"])
    hdri.inputs["Strength"].default_value = 0.3
    black.inputs["Color"].default_value = (0, 0, 0, 1)
    # Reflections see a soft vertical gradient (no hot spots on the visor); lighting uses the HDRI.
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    sky = nt.nodes.new("ShaderNodeBackground")
    glossy_mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(coords.outputs["Generated"], sep.inputs["Vector"])
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    # The body sees a soft bright sky in its reflections (so the satin metal and the clear coat read);
    # the glass pass dims it (sky_for_glass) so the visor stays deep black.
    ramp.color_ramp.elements[0].position = 0.45
    ramp.color_ramp.elements[0].color = (0.0, 0.0, 0.0, 1)
    ramp.color_ramp.elements[1].position = 1.0
    ramp.color_ramp.elements[1].color = (0.6, 0.64, 0.72, 1)
    hdri["sky_ramp"] = ramp.name
    nt.links.new(ramp.outputs["Color"], sky.inputs["Color"])
    sky.inputs["Strength"].default_value = 1.0
    nt.links.new(path.outputs["Is Glossy Ray"], glossy_mix.inputs["Fac"])
    nt.links.new(hdri.outputs["Background"], glossy_mix.inputs[1])
    nt.links.new(sky.outputs["Background"], glossy_mix.inputs[2])
    nt.links.new(path.outputs["Is Camera Ray"], mix.inputs["Fac"])
    nt.links.new(glossy_mix.outputs["Shader"], mix.inputs[1])
    nt.links.new(black.outputs["Background"], mix.inputs[2])
    nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])
    scene.world = world
    return hdri


def area(name, loc, target, size, energy, color=(1, 1, 1), size_y=None):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.color = color
    if size_y is None:
        data.shape = "DISK"
        data.size = size
    else:
        data.shape = "RECTANGLE"
        data.size = size
        data.size_y = size_y
    obj = link(bpy.data.objects.new(name, data))
    obj.location = loc
    aim(obj, Vector(loc) - Vector(target))
    obj.visible_camera = False
    return obj


def setup_lights():
    target = (0, 0, 1.0)
    lights = {
        "key": area("Key", (-3.4, -4.2, 4.4), target, 4.0, 430, (1.0, 0.975, 0.95)),
        "fill": area("Fill", (3.8, -3.6, 1.2), target, 3.5, 40, (0.93, 0.96, 1.0)),
        "top": area("Top", (0.0, 0.8, 5.5), target, 3.0, 110),
        "rim_l": area("RimL", (-3.2, 3.0, 2.6), target, 1.6, 900),
        "rim_r": area("RimR", (3.2, 3.0, 2.2), target, 1.6, 900),
        "strip": area("Strip", (-1.5, -3.6, 3.4), (0, 0, 1.6), 2.6, 220, (1, 1, 1), size_y=0.22),
        "under": area("Under", (0.0, -2.5, -2.0), target, 2.0, 25),
    }
    for name in ("key", "fill", "top", "under"):
        lights[name].visible_glossy = False
        lights[name].data.specular_factor = 0.0
    return lights


def setup_reflector():
    """A soft window seen only in reflections: one graded highlight across the top of the visor and a
    soft sheen on the head, instead of hard light dots."""
    mesh = bpy.data.meshes.new("Reflector")
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=1.0)
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new("Reflector", mesh))
    obj.location = (-0.55, -1.7, 4.3)
    obj.scale = (1.5, 0.75, 1.0)
    obj.rotation_euler = (Vector((0.0, -0.6, 1.75)) - obj.location).to_track_quat("Z", "Y").to_euler()

    mat = bpy.data.materials.new("ReflectorLight")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    coords = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    along = nt.nodes.new("ShaderNodeValToRGB")
    across = nt.nodes.new("ShaderNodeValToRGB")
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    nt.links.new(coords.outputs["Generated"], sep.inputs["Vector"])
    # Bright along the far edge, fading to nothing toward the robot; soft at both ends.
    nt.links.new(sep.outputs["Y"], along.inputs["Fac"])
    along.color_ramp.interpolation = "EASE"
    along.color_ramp.elements[0].position = 0.0
    along.color_ramp.elements[0].color = (0, 0, 0, 1)
    along.color_ramp.elements[1].position = 0.6
    along.color_ramp.elements[1].color = (1, 1, 1, 1)
    e = along.color_ramp.elements.new(0.82)
    e.color = (1, 1, 1, 1)
    e = along.color_ramp.elements.new(1.0)
    e.color = (0, 0, 0, 1)
    nt.links.new(sep.outputs["X"], across.inputs["Fac"])
    across.color_ramp.interpolation = "EASE"
    across.color_ramp.elements[0].color = (0, 0, 0, 1)
    across.color_ramp.elements[0].position = 0.0
    across.color_ramp.elements[1].color = (1, 1, 1, 1)
    across.color_ramp.elements[1].position = 0.3
    e = across.color_ramp.elements.new(0.7)
    e.color = (1, 1, 1, 1)
    e = across.color_ramp.elements.new(1.0)
    e.color = (0, 0, 0, 1)
    nt.links.new(along.outputs["Color"], mul.inputs[0])
    nt.links.new(across.outputs["Color"], mul.inputs[1])
    nt.links.new(mul.outputs["Value"], emit.inputs["Strength"])
    emit.inputs["Color"].default_value = (2.2, 2.3, 2.5, 1)
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    obj.data.materials.append(mat)
    for attr in ("visible_camera", "visible_diffuse", "visible_shadow", "visible_transmission",
                 "visible_volume_scatter"):
        setattr(obj, attr, False)
    obj.visible_glossy = True
    return obj, emit


def setup_camera(scene):
    data = bpy.data.cameras.new("Camera")
    data.lens = 85
    data.sensor_width = 36
    cam = link(bpy.data.objects.new("Camera", data))
    cam.location = (0.0, -9.2, 1.5)
    aim(cam, Vector((0, 0, 0.92)) - cam.location)
    cam.rotation_euler = (Vector((0, 0, 0.92)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    return cam


def setup_render(scene, res, samples, view="Standard", look="None", exposure=0.0):
    scene.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "METAL"
    prefs.get_devices()
    for d in prefs.devices:
        d.use = True
    scene.cycles.device = "GPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    try:
        scene.cycles.denoiser = "OPENIMAGEDENOISE"
    except TypeError:
        pass
    scene.render.resolution_x = res
    scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = view
    try:
        scene.view_settings.look = look
    except TypeError:
        print("look not available:", look)
    scene.view_settings.exposure = exposure
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_depth = "8"


def setup_bloom(scene, enabled):
    if not enabled:
        scene.compositing_node_group = None
        return
    tree = bpy.data.node_groups.get("AssistantGlow")
    if tree is None:
        tree = bpy.data.node_groups.new("AssistantGlow", "CompositorNodeTree")
        tree.interface.new_socket(name="Image", in_out="OUTPUT", socket_type="NodeSocketColor")
        layers = tree.nodes.new("CompositorNodeRLayers")
        out = tree.nodes.new("NodeGroupOutput")
        src = layers.outputs["Image"]
        for threshold, strength, size in ((0.4, 0.35, 0.22), (0.9, 0.2, 0.4)):
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
            tree.links.new(src, node.inputs["Image"])
            src = node.outputs["Image"]
        tree.links.new(src, out.inputs[0])
    scene.compositing_node_group = tree


# ---------------------------------------------------------------------------
# Passes
# ---------------------------------------------------------------------------

def swap_materials(mapping):
    """mapping: material -> replacement (or None to keep). Returns an undo list."""
    undo = []
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        for slot in obj.material_slots:
            if slot.material in mapping and mapping[slot.material] is not None:
                undo.append((slot, slot.material))
                slot.material = mapping[slot.material]
    return undo


def restore(undo):
    for slot, mat in undo:
        slot.material = mat


def render_pass(scene, m, lights, hdri, name, path, animate=False):
    rim_lights = (lights["rim_l"], lights["rim_r"])
    hidden = []
    if name == "body":
        scene.render.film_transparent = True
        m.emission(EMIT_BODY)
        undo = swap_materials({m.visor: m.visor_matte})
        setup_bloom(scene, False)
    elif name == "beauty":
        scene.render.film_transparent = True
        m.emission(EMIT_BEAUTY)
        undo = []
        setup_bloom(scene, False)
    elif name == "glass":
        scene.render.film_transparent = False
        m.emission(0.0)
        # Only the reflector card and the dim sky: one soft highlight, no hard light dots.
        hidden = list(lights.values())
        # The studio HDRI reaches the visor through direct light sampling as two bright dots; the glass
        # pass needs only the reflector, so the HDRI is off while it renders.
        hdri_strength = hdri.inputs["Strength"].default_value
        hdri.inputs["Strength"].default_value = 0.0
        sky = scene.world.node_tree.nodes[hdri["sky_ramp"]].color_ramp.elements
        sky_was = (sky[0].position, tuple(sky[1].color))
        sky[0].position = 0.8
        sky[1].color = (0.12, 0.13, 0.15, 1)
        undo = swap_materials({mat: m.black for mat in (m.shell, m.satin, m.accent, m.gasket, m.light, m.core)})
        setup_bloom(scene, False)
    elif name == "glow":
        scene.render.film_transparent = False
        m.emission(EMIT_GLOW)
        undo = swap_materials({mat: m.black for mat in (m.shell, m.satin, m.accent, m.gasket, m.visor)})
        # No compositor bloom: export_assistant.py adds a tight, controlled halo, so the light never
        # washes colour over the white shell.
        setup_bloom(scene, False)
    else:
        raise ValueError(name)
    for light in lights.values():
        light.hide_render = light in hidden
    view = (scene.view_settings.view_transform, scene.view_settings.look, scene.view_settings.exposure)
    if name == "glow":
        scene.view_settings.view_transform = "Standard"
        scene.view_settings.look = "None"
        scene.view_settings.exposure = 0.0
    scene.render.image_settings.color_mode = "RGBA" if scene.render.film_transparent else "RGB"
    if animate:
        scene.render.filepath = path.replace(".png", "_")
        bpy.ops.render.render(animation=True)
    else:
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
    restore(undo)
    scene.view_settings.view_transform, scene.view_settings.look, scene.view_settings.exposure = view
    if name == "glass":
        hdri.inputs["Strength"].default_value = hdri_strength
        sky[0].position, sky[1].color = sky_was[0], sky_was[1]
    print("WROTE", path)


def export_face(scene, cam, path):
    """The visor outline, projected into normalised image coordinates (origin top-left)."""
    bpy.context.view_layer.update()
    pts = []
    for x, z in superellipse(VISOR_W, VISOR_H, VISOR_N, 96, VISOR_ZC):
        rx, ry, rz = (r * VISOR_S for r in HEAD_R)
        dx, dz = x / rx, (z - HEAD_C.z) / rz
        y = HEAD_C.y - ry * math.sqrt(max(0.0, 1 - dx * dx - dz * dz))
        co = world_to_camera_view(scene, cam, Vector((x, y, z)))
        pts.append((round(co.x, 5), round(1 - co.y, 5)))
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    centre = world_to_camera_view(scene, cam, Vector((0, HEAD_C.y - HEAD_R[1] * VISOR_S, VISOR_ZC)))
    data = {
        "outline": pts,
        "bounds": [min(xs), min(ys), max(xs), max(ys)],
        "centre": [round(centre.x, 5), round(1 - centre.y, 5)],
    }
    with open(path, "w") as f:
        json.dump(data, f)
    print("FACE", data["bounds"], data["centre"])


def rim_colour(v):
    """Mostly cool neutral rims, with a quarter of the variant's tint: separation, not gamer RGB."""
    return tuple(0.75 * n + 0.25 * c for n, c in zip((0.85, 0.9, 1.0), v["rim"]))


def main():
    a = parse_args()
    os.makedirs(a.out, exist_ok=True)
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    scene = bpy.context.scene
    m, visor, pivots = build(a.pose, rig=a.wave)
    if a.wave:
        animate_wave(pivots)
    hdri = setup_world(scene)
    lights = setup_lights()
    setup_reflector()
    cam = setup_camera(scene)
    setup_render(scene, a.res, a.samples, a.view, a.look, a.exposure)
    export_face(scene, cam, os.path.join(a.out, "face.json"))
    first = a.variants.split(",")[0]
    m.variant(VARIANTS[first])
    for light in (lights["rim_l"], lights["rim_r"]):
        light.data.color = rim_colour(VARIANTS[first])
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(a.out, "assistant.blend"))
    if a.no_render:
        return
    for name in a.variants.split(","):
        v = VARIANTS[name]
        m.variant(v)
        for light in (lights["rim_l"], lights["rim_r"]):
            light.data.color = rim_colour(v)
        lights["under"].data.color = tuple(0.6 + 0.4 * c for c in v["glow"])
        suffix = "" if a.pose == "idle" else f"_{a.pose}"
        if a.wave:
            suffix = "_wave"
        for p in a.passes.split(","):
            render_pass(scene, m, lights, hdri, p, os.path.join(a.out, f"{name}{suffix}{a.tag}_{p}.png"), animate=a.wave)


main()
