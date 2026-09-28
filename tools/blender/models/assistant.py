"""PrepSuite assistant: a friendly robot with a glass face screen, a headset and an arc-reactor heart.

The face (eyes and mouth) is NOT rendered here. The app draws it live on the visor so the mouth moves with the
voice and the eyes blink, look and react. This script renders the parts that stay still, per colour variant:

  <variant>_body.png   the robot, lights dimmed, visor matte dark (RGBA, transparent background)
  <variant>_glass.png  only the visor's reflections, on black (the app adds it over the face with Plus/Screen)
  <variant>_glow.png   only the lights (ear rings, heart, seams) with bloom, on black (added, pulsing with state)
  <variant>_beauty.png everything together for previews (visor reflective, lights on)
  face.json            the visor outline in normalised image coordinates, for clipping the live face

Run headless:
    Blender -b --factory-startup --python-exit-code 1 --python assistant.py -- [options]

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
BODY_C = Vector((0.0, 0.0, 0.03))
BODY_R = (0.66, 0.60, 0.70)

# Linear-light colours per variant: accent (plastic or metal), glow (emission), rim light tint.
VARIANTS = {
    "nova": dict(accent=(0.018, 0.23, 1.0), metal=0.0, glow=(0.05, 0.62, 1.0), rim=(0.35, 0.65, 1.0)),
    "sol": dict(accent=(1.0, 0.62, 0.22), metal=1.0, glow=(1.0, 0.50, 0.10), rim=(1.0, 0.72, 0.42)),
    "iris": dict(accent=(0.22, 0.10, 1.0), metal=0.0, glow=(0.52, 0.30, 1.0), rim=(0.62, 0.48, 1.0)),
    "mint": dict(accent=(0.0, 0.52, 0.34), metal=0.0, glow=(0.06, 1.0, 0.66), rim=(0.40, 1.0, 0.80)),
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
    p.add_argument("--view", default="Standard")
    p.add_argument("--look", default="None")
    p.add_argument("--exposure", type=float, default=-0.15)
    p.add_argument("--tag", default="")
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
        self.shell = principled("Shell", (0.84, 0.86, 0.89), roughness=0.34, coat=0.5, coat_rough=0.07,
                                subsurface=0.06)
        self.accent = principled("Accent", (0.02, 0.23, 1.0), roughness=0.3, coat=0.15)
        self.gasket = principled("Gasket", (0.028, 0.031, 0.038), roughness=0.38, metallic=0.55)
        self.visor = principled("Visor", (0.006, 0.008, 0.016), roughness=0.05, coat=1.0, coat_rough=0.015,
                                specular=0.8)
        self.visor_matte = principled("VisorMatte", (0.004, 0.005, 0.010), roughness=0.9, specular=0.0)
        self.light = principled("Light", (0.0, 0.0, 0.0), roughness=0.5, emission=(0.05, 0.62, 1.0),
                                strength=EMIT_BODY)
        self.core = principled("Core", (0.0, 0.0, 0.0), roughness=0.5, emission=(0.6, 0.9, 1.0),
                               strength=EMIT_BODY * 1.4)
        self.black = principled("Black", (0.0, 0.0, 0.0), roughness=1.0, specular=0.0)

    def variant(self, v):
        set_input(self.accent, "Base Color", (*v["accent"], 1.0))
        set_input(self.accent, "Metallic", v["metal"])
        set_input(self.accent, "Roughness", 0.24 if v["metal"] else 0.3)
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
    recess = prism("RecessCut", superellipse(VISOR_W * 1.065, VISOR_H * 1.095, VISOR_N, 192, VISOR_ZC), y0, y1)
    floor = ellipsoid("RecessFloor", tuple(r * RECESS for r in HEAD_R), HEAD_C)
    apply_boolean(recess, floor, "DIFFERENCE")
    remove(floor)
    recess.data.materials.append(m.gasket)
    apply_boolean(head, recess, "DIFFERENCE")
    remove(recess)
    smooth(head, 38)
    bevel(head, 0.006, 2, 38)

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
        cup = cylinder(f"EarCup{side}", 0.31, 0.24)
        cup.rotation_euler = (0, math.radians(90), 0)
        cup.location = (side * 1.03, 0.02, HEAD_C.z - 0.02)
        cup.data.materials.append(m.shell)
        bevel(cup, 0.05, 4, 30)

        cap = cylinder(f"EarCap{side}", 0.235, 0.07)
        cap.rotation_euler = (0, math.radians(90), 0)
        cap.location = (side * 1.16, 0.02, HEAD_C.z - 0.02)
        cap.data.materials.append(m.accent)
        bevel(cap, 0.022, 3, 30)

        ring = torus(f"EarRing{side}", 0.272, 0.013)
        ring.rotation_euler = (0, math.radians(90), 0)
        ring.location = (side * 1.155, 0.02, HEAD_C.z - 0.02)
        ring.data.materials.append(m.light)

        dot = cylinder(f"EarDot{side}", 0.075, 0.04)
        dot.rotation_euler = (0, math.radians(90), 0)
        dot.location = (side * 1.2, 0.02, HEAD_C.z - 0.02)
        dot.data.materials.append(m.gasket)
        parts += [cup, cap, ring, dot]

    # The band over the head, leaning back so it never crosses the visor.
    band = torus("Band", 1.08, 0.062, keep=lambda co: co.y > 0.02)
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
            flat = 0.92 if z > 0.55 else 1.0
            v.co = Vector((x * BODY_R[0] * taper, y * BODY_R[1] * taper, z * BODY_R[2] * flat)) + BODY_C
    body = mesh_object("Body", build)
    smooth(body)
    body.data.materials.append(m.shell)

    top = BODY_C.z + BODY_R[2] * 0.92
    column = cylinder("NeckColumn", 0.19, HEAD_C.z - HEAD_R[2] - top + 0.16)
    column.location = (0, 0, (top + HEAD_C.z - HEAD_R[2]) / 2)
    column.data.materials.append(m.gasket)
    neck = torus("Neck", 0.23, 0.045)
    neck.location = (0, 0.0, top - 0.01)
    neck.data.materials.append(m.gasket)
    glow = torus("NeckLight", 0.195, 0.012)
    glow.location = (0, 0.0, top + 0.035)
    glow.data.materials.append(m.light)

    seam = torus("Seam", BODY_R[0] * 1.0, 0.012)
    seam.location = (0, 0, BODY_C.z - 0.05)
    seam.scale = (1.0, BODY_R[1] / BODY_R[0], 1.0)
    seam.data.materials.append(m.light)

    band = torus("WaistBand", BODY_R[0] * 0.99, 0.045, minor_seg=24)
    band.location = (0, 0, BODY_C.z - 0.05)
    band.scale = (1.0, BODY_R[1] / BODY_R[0], 1.0)
    band.data.materials.append(m.accent)
    return [body, column, neck, glow, seam, band]


def build_core(m):
    """The arc-reactor heart on the chest: a nod to the gold hologram."""
    z = BODY_C.z + 0.3
    rel = (z - BODY_C.z) / BODY_R[2]
    taper = 1.0 - 0.16 * max(0.0, rel)
    y = BODY_C.y - BODY_R[1] * taper * math.sqrt(max(0.0, 1 - rel * rel))
    normal = Vector((0, -1.0, 0.42)).normalized()
    origin = Vector((0, y + 0.005, z))

    parts = []
    socket = cylinder("CoreSocket", 0.17, 0.05)
    socket.data.materials.append(m.gasket)
    bezel = torus("CoreBezel", 0.17, 0.028)
    bezel.data.materials.append(m.accent)
    heart = cylinder("CoreHeart", 0.06, 0.03)
    heart.data.materials.append(m.core)
    parts += [socket, bezel, heart]
    for i in range(10):
        seg = mesh_object(f"CoreSeg{i}", lambda bm: bmesh.ops.create_cube(bm, size=1.0))
        seg.scale = (0.022, 0.05, 0.02)
        a = 2 * math.pi * i / 10
        seg.location = (0.108 * math.cos(a), 0.108 * math.sin(a), 0.015)
        seg.rotation_euler = (0, 0, a + math.pi / 2)
        seg.data.materials.append(m.light)
        parts.append(seg)
    pivot = bpy.data.objects.new("Core", None)
    link(pivot)
    for p in parts:
        p.parent = pivot
    pivot.location = origin
    aim(pivot, normal)
    return parts + [pivot]


def capsule(name, start, end, radius):
    start, end = Vector(start), Vector(end)
    d = end - start
    cyl = cylinder(name, radius, d.length, segments=64)
    cyl.location = (start + end) / 2
    aim(cyl, d)
    caps = []
    for i, p in enumerate((start, end)):
        cap = ellipsoid(f"{name}Cap{i}", (radius, radius, radius), p, segments=48, rings=24)
        caps.append(cap)
    return [cyl] + caps


def build_arms(m, pose):
    """Two-part arms with a soft elbow bend, mitten hands with a thumb, and accent cuffs."""
    parts = []
    for side in (-1, 1):
        shoulder = Vector((side * 0.58, -0.06, BODY_C.z + 0.28))
        joint = ellipsoid(f"Shoulder{side}", (0.105, 0.105, 0.105), shoulder, segments=48, rings=24)
        joint.data.materials.append(m.gasket)
        if pose == "wave" and side == 1:
            upper = Vector((0.75, -0.15, 0.25)).normalized()
            fore = Vector((0.25, -0.2, 0.95)).normalized()
        else:
            upper = Vector((side * 0.55, -0.1, -0.83)).normalized()
            fore = Vector((side * 0.18, -0.5, -0.85)).normalized()
        elbow = shoulder + upper * 0.3
        wrist = elbow + fore * 0.24
        segments = capsule(f"Upper{side}", shoulder + upper * 0.08, elbow, 0.08)
        segments += capsule(f"Fore{side}", elbow, wrist, 0.074)
        for a in segments:
            a.data.materials.append(m.shell)
        cuff = torus(f"Cuff{side}", 0.08, 0.024)
        cuff.location = wrist
        aim(cuff, fore)
        cuff.data.materials.append(m.accent)
        hand = ellipsoid(f"Hand{side}", (0.105, 0.135, 0.16), (0, 0, 0), segments=64, rings=32)
        hand.location = wrist + fore * 0.12
        aim(hand, fore)
        hand.data.materials.append(m.shell)
        thumb = ellipsoid(f"Thumb{side}", (0.045, 0.05, 0.075), (0, 0, 0), segments=32, rings=16)
        thumb.location = wrist + fore * 0.08 + Vector((-side * 0.085, -0.07, 0.0))
        aim(thumb, (fore + Vector((-side * 0.6, -0.3, 0))).normalized())
        thumb.data.materials.append(m.shell)
        parts += [joint, cuff, hand, thumb] + segments
    return parts


def build(pose):
    m = Materials()
    head, visor = build_head(m)
    parts = [head, visor]
    parts += build_headset(m)
    parts += build_body(m)
    parts += build_core(m)
    parts += build_arms(m, pose)
    return m, visor


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
    ramp.color_ramp.elements[0].position = 0.5
    ramp.color_ramp.elements[0].color = (0.0, 0.0, 0.0, 1)
    ramp.color_ramp.elements[1].position = 1.0
    ramp.color_ramp.elements[1].color = (0.55, 0.6, 0.7, 1)
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
        "key": area("Key", (-3.4, -4.2, 4.4), target, 3.0, 520, (1.0, 0.975, 0.95)),
        "fill": area("Fill", (3.8, -3.6, 1.2), target, 3.5, 70, (0.93, 0.96, 1.0)),
        "top": area("Top", (0.0, 0.8, 5.5), target, 3.0, 150),
        "rim_l": area("RimL", (-3.2, 3.0, 2.6), target, 1.6, 900),
        "rim_r": area("RimR", (3.2, 3.0, 2.2), target, 1.6, 900),
        "strip": area("Strip", (-1.5, -3.6, 3.4), (0, 0, 1.6), 2.6, 220, (1, 1, 1), size_y=0.22),
        "under": area("Under", (0.0, -2.5, -2.0), target, 2.0, 50),
    }
    for name in ("key", "fill", "top", "under"):
        lights[name].visible_glossy = False
    return lights


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
        for threshold, strength, size in ((0.3, 0.5, 0.35), (0.8, 0.45, 0.6)):
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


def render_pass(scene, m, lights, hdri, name, path):
    rim_lights = (lights["rim_l"], lights["rim_r"])
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
        undo = swap_materials({mat: m.black for mat in (m.shell, m.accent, m.gasket, m.light, m.core)})
        setup_bloom(scene, False)
    elif name == "glow":
        scene.render.film_transparent = False
        m.emission(EMIT_GLOW)
        undo = swap_materials({mat: m.black for mat in (m.shell, m.accent, m.gasket, m.visor)})
        setup_bloom(scene, True)
    else:
        raise ValueError(name)
    for light in rim_lights:
        light.hide_render = False
    scene.render.image_settings.color_mode = "RGBA" if scene.render.film_transparent else "RGB"
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    restore(undo)
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


def main():
    a = parse_args()
    os.makedirs(a.out, exist_ok=True)
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    scene = bpy.context.scene
    m, visor = build(a.pose)
    hdri = setup_world(scene)
    lights = setup_lights()
    cam = setup_camera(scene)
    setup_render(scene, a.res, a.samples, a.view, a.look, a.exposure)
    export_face(scene, cam, os.path.join(a.out, "face.json"))
    first = a.variants.split(",")[0]
    m.variant(VARIANTS[first])
    for light in (lights["rim_l"], lights["rim_r"]):
        light.data.color = VARIANTS[first]["rim"]
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(a.out, "assistant.blend"))
    if a.no_render:
        return
    for name in a.variants.split(","):
        v = VARIANTS[name]
        m.variant(v)
        for light in (lights["rim_l"], lights["rim_r"]):
            light.data.color = v["rim"]
        suffix = "" if a.pose == "idle" else f"_{a.pose}"
        for p in a.passes.split(","):
            render_pass(scene, m, lights, hdri, p, os.path.join(a.out, f"{name}{suffix}{a.tag}_{p}.png"))


main()
