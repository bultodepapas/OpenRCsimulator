"""Generate one frozen, textured MakeHuman crowd pose as glTF 2.0.

Run through Blender 5.2.2 with MPFB 2.0.18 installed. The script changes no
Blender preferences; it redirects MPFB's in-process user-data preference to
the explicit directory supplied on the command line.
"""

import argparse
import importlib
import json
import math
import os
import sys
from pathlib import Path

import bpy
import addon_utils
from mathutils import Matrix, Quaternion, Vector


def parse_arguments():
    if '--' not in sys.argv:
        raise RuntimeError('Pass --pose, --mpfb-user-data and --output-dir after Blender --')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pose', choices=('standing', 'seated', 'pilot', 'working'), required=True)
    parser.add_argument('--mpfb-user-data', required=True, type=Path,
                        help='MPFB user-data directory containing the installed CC0 system assets in data/')
    parser.add_argument('--output-dir', required=True, type=Path)
    parser.add_argument('--pose-file', type=Path,
                        help='Optional BVH override; defaults to the pinned source included in assets/scenery/population/source/')
    parser.add_argument('--outfit', type=Path,
                        help='SC-HUM-07 outfit JSON (tools/scenery/population/outfits/); omitted = the LU-21 person exactly')
    parser.add_argument('--save-posed', type=Path,
                        help='Also save the posed rig and meshes (before the static bake) to this .blend, for review')
    parser.add_argument('--transmitter', type=Path,
                        help='SC-HUM-01 owner transmitter .blend for the pilot pose; defaults to the Radiolink T12D delivery')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    args.mpfb_user_data = args.mpfb_user_data.resolve()
    args.output_dir = args.output_dir.resolve()
    if not (args.mpfb_user_data / 'data').is_dir():
        parser.error('--mpfb-user-data must contain a data/ directory with MakeHuman system assets installed')
    repo_root = Path(__file__).resolve().parents[3]
    default_pose = 'anrico_sitting03' if args.pose == 'seated' else 'standing02'
    pose_directory = repo_root / 'assets/scenery/population/source/poses' / default_pose
    args.pose_file = (args.pose_file or (pose_directory / (default_pose + '.bvh'))).resolve()
    args.transmitter = (args.transmitter or (repo_root / 'assets/source-deliveries/radiolink-t12d/Radiolink_T12D.blend')).resolve()
    if not args.pose_file.is_file():
        parser.error('Pose BVH does not exist: ' + str(args.pose_file))
    args.output_dir.mkdir(parents=True, exist_ok=True)
    return args


ARGS = parse_arguments()
stage = str(ARGS.output_dir)
user_home = str(ARGS.mpfb_user_data)

# The LU-21 person. An outfit file overrides any of these keys; the defaults reproduce the frozen meshes.
LU21_OUTFIT = {
    'id': None,
    'macros': None,
    'proxy': 'male1591.proxy',
    'skin': 'middleage_caucasian_male.mhmat',
    'assets': [
        ['eyes', 'low-poly.mhclo', 'Eyes'],
        ['eyebrows', 'eyebrow001.mhclo', 'Eyebrows'],
        ['hair', 'short01.mhclo', 'Hair'],
        ['clothes', 'male_casualsuit04.mhclo', 'Clothes'],
        ['clothes', 'shoes02.mhclo', 'Clothes'],
    ],
    'decimate': {'male1591': 0.70, 'male_casualsuit04': 0.80, 'shoes02': 0.50, 'short01': 0.35},
    'image_max_edge': {'skins': 1024, 'clothes': 1024, 'hair': 512, 'eyes': 256, 'other': 512},
    # 'all': normalize standing poses to 1.75 m including hair (LU-21); 'natural': keep the macro height.
    'height': 'all',
}
OUTFIT = dict(LU21_OUTFIT)
if ARGS.outfit:
    OUTFIT.update(json.loads(ARGS.outfit.read_text()))
    print('OUTFIT=' + json.dumps(OUTFIT, sort_keys=True))
name_stem = 'person_' + (OUTFIT['id'] + '_' if OUTFIT['id'] else '')

def preference(name):
    if name == 'mpfb_user_data':
        return user_home
    if name == 'mpfb_shelf_label':
        return 'MPFB Research'
    if name == 'mh_auto_user_data':
        return False
    return None

def mesh_stats(objects):
    dg = bpy.context.evaluated_depsgraph_get()
    out = []
    total = 0
    for obj in objects:
        if obj.type != 'MESH':
            continue
        evaluated = obj.evaluated_get(dg)
        mesh = evaluated.to_mesh()
        mesh.calc_loop_triangles()
        tris = len(mesh.loop_triangles)
        total += tris
        out.append({'name': obj.name, 'vertices': len(mesh.vertices), 'triangles': tris, 'materials': [m.name if m else None for m in obj.data.materials]})
        evaluated.to_mesh_clear()
    return total, out

bpy.utils.refresh_script_paths()
addon_utils.modules_refresh()
mpfb = importlib.import_module('bl_ext.blender_org.mpfb')
mpfb.get_preference = preference
mpfb.register()
prefix = 'bl_ext.blender_org.mpfb.services.'
HumanService = importlib.import_module(prefix + 'humanservice').HumanService
AssetService = importlib.import_module(prefix + 'assetservice').AssetService
ExportService = importlib.import_module(prefix + 'exportservice').ExportService
ObjectService = importlib.import_module(prefix + 'objectservice').ObjectService
TargetService = importlib.import_module(prefix + 'targetservice').TargetService
AnimationService = importlib.import_module(prefix + 'animationservice').AnimationService

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

if OUTFIT['macros'] is None:
    human = HumanService.create_human()
else:
    macros = TargetService.get_default_macro_info_dict()
    macros.update({k: v for k, v in OUTFIT['macros'].items() if k != 'race'})
    macros['race'].update(OUTFIT['macros'].get('race', {}))
    human = HumanService.create_human(macro_detail_dict=macros)
print('BASE_DIMENSIONS=' + str(tuple(round(v, 4) for v in human.dimensions)))
print('BASE_TRIANGLES=' + str(mesh_stats([human])[0]))

rig = HumanService.add_builtin_rig(human, 'default')

# Replace the detailed source surface with the official CC0 low-poly proxy
# (LU-21: the 1,591-triangle male). This keeps a recognizable face and hands
# while avoiding the 15k-triangle base body. Use the same skin material on the proxy.
proxy_path = AssetService.find_asset_absolute_path(OUTFIT['proxy'], asset_subdir='proxymeshes')
if not proxy_path:
    raise RuntimeError('missing proxy ' + OUTFIT['proxy'])
body_proxy = HumanService.add_mhclo_asset(proxy_path, human, asset_type='Proxymeshes', subdiv_levels=0, material_type='NONE')
skin = AssetService.find_asset_absolute_path(OUTFIT['skin'], asset_subdir='skins')
if not skin:
    raise RuntimeError('missing skin asset ' + OUTFIT['skin'])
HumanService.set_character_skin(skin, human, bodyproxy=body_proxy, skin_type='GAMEENGINE')

assets = [tuple(entry) for entry in OUTFIT['assets']]
for subdir, filename, asset_type in assets:
    path = AssetService.find_asset_absolute_path(filename, asset_subdir=subdir)
    if not path:
        raise RuntimeError('missing asset ' + subdir + '/' + filename)
    HumanService.add_mhclo_asset(path, human, asset_type=asset_type, material_type='GAMEENGINE', subdiv_levels=0)

pose_kind = ARGS.pose
pose_path = str(ARGS.pose_file)
# An outfit may name a CC0 pose from the pinned MPFB pose packs per pose kind (an explicit --pose-file wins).
outfit_pose = OUTFIT.get('pose_files', {}).get(pose_kind)
if outfit_pose and '--pose-file' not in sys.argv:
    pose_path = str(ARGS.mpfb_user_data / 'data' / 'poses' / outfit_pose / (outfit_pose + '.bvh'))
    if not os.path.isfile(pose_path):
        raise RuntimeError('missing outfit pose ' + pose_path)
addon_utils.enable('io_anim_bvh', default_set=False, persistent=False)
AnimationService.import_bvh_file_as_pose(rig, pose_path)
print('POSE=' + pose_kind + ':' + pose_path)

def make_ik_target(name, location, end_bone, chain_count, pole_location=None):
    target = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(target)
    target.location = location
    target.empty_display_type = 'SPHERE'
    target.empty_display_size = 0.025
    constraint = rig.pose.bones[end_bone].constraints.new('IK')
    constraint.name = name + '_IK'
    constraint.target = target
    constraint.chain_count = chain_count
    constraint.iterations = 100
    constraint.use_stretch = False
    constraint.use_tail = True
    pole = None
    if pole_location is not None:
        pole = bpy.data.objects.new(name + '_pole', None)
        bpy.context.scene.collection.objects.link(pole)
        pole.location = pole_location
        pole.empty_display_type = 'CIRCLE'
        pole.empty_display_size = 0.02
        constraint.pole_target = pole
        # Mirrored pole directions keep the elbows bent symmetrically.
        constraint.pole_angle = math.pi if name.endswith('_L') else 0.0
    return target

def reset_pose_bones(names):
    for name in names:
        bone = rig.pose.bones.get(name)
        if bone:
            bone.rotation_mode = 'QUATERNION'
            bone.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
            bone.location = (0.0, 0.0, 0.0)

def bend_pose_bone(name, degrees):
    """Rotate a posed bone forward about its local X axis (positive leans the body toward -Y, its front)."""
    bone = rig.pose.bones.get(name)
    if bone is None:
        raise RuntimeError('missing bone ' + name)
    bone.rotation_mode = 'QUATERNION'
    bone.rotation_quaternion = bone.rotation_quaternion @ Quaternion((1.0, 0.0, 0.0), math.radians(degrees))

# SC-HUM-07-R1 hands, tuned through the Blender MCP on posed rigs (--save-posed). MPFB's default rig flexes a finger
# about its local Z axis (+ on the left hand, - on the right) and tucks the thumb toward the index about local -X on
# both sides. Flexion per finger (thumb to little) and joint (1-3), in degrees: relaxed for hanging or resting
# hands, grip for hands holding a transmitter or working on a model.
FINGERS_RELAXED = ((8, 10, 12), (12, 20, 10), (16, 25, 12), (20, 30, 14), (24, 34, 16))
FINGERS_GRIP = ((10, 14, 14), (22, 30, 18), (26, 34, 20), (30, 38, 22), (34, 42, 24))
THUMB_TUCK_RELAXED_DEG = -15.0
THUMB_TUCK_GRIP_DEG = -10.0
# Seated hands rest on the thighs: along the hip-to-knee line, lifted to the top of the thigh.
SEAT_HAND_ALONG_THIGH = 0.55
SEAT_HAND_LIFT_M = 0.10
# SC-HUM-07-R4/R5: CC0 standing02 and standing03 hold the arms out in an A (wrists 0.13-0.15 m outside the shoulders);
# relaxed arms hang beside the thighs: wrist this far outside the shoulder joint, slightly ahead of the hip.
ARM_HANG_OUT_M = 0.055
ARM_HANG_AHEAD_M = 0.03
ARM_HANG_POSES = ('standing02.bvh', 'standing03.bvh')  # standing04 keeps its hand on the hip
EYEBROW_FROM_HAIR = 0.8  # brows a little darker than the hair (SC-HUM-07-R5)

def pose_fingers(side, curl, thumb_tuck_deg):
    """Replace the source pose's fingers. The CC0 standing BVH bends only the outer joints, which reads as a claw."""
    flex = 1.0 if side == 'L' else -1.0
    for finger in range(1, 6):
        for joint in range(1, 4):
            bone = rig.pose.bones['finger%d-%d.%s' % (finger, joint, side)]
            bone.rotation_mode = 'QUATERNION'
            rotation = Quaternion((0.0, 0.0, 1.0), math.radians(flex * curl[finger - 1][joint - 1]))
            if finger == 1 and joint == 1:
                rotation = Quaternion((1.0, 0.0, 0.0), math.radians(thumb_tuck_deg)) @ rotation
            bone.rotation_quaternion = rotation

FINGER_REST_GAP_M = 0.0025  # SC-HUM-07-R7: fingertips rest this far outside the held object's surface

def fit_fingers_to_surface(objects):
    """Scale each finger's flexion (0-2x its preset, in 0.05 steps) so its tip rests FINGER_REST_GAP_M outside the
    surface of `objects` (world-space meshes), never inside. Measured on the posed rig through the Blender MCP."""
    import bmesh
    from mathutils.bvhtree import BVHTree
    surface = bmesh.new()
    for obj in objects:
        mesh = obj.data.copy()
        mesh.transform(obj.matrix_world)
        surface.from_mesh(mesh)
        bpy.data.meshes.remove(mesh)
    tree = BVHTree.FromBMesh(surface)
    report = {}
    for side in ('L', 'R'):
        for finger in range(2, 6):
            bones = [rig.pose.bones['finger%d-%d.%s' % (finger, joint, side)] for joint in (1, 2, 3)]
            preset = [bone.rotation_quaternion.copy() for bone in bones]
            def apply(scale):
                for bone, rotation in zip(bones, preset):
                    bone.rotation_quaternion = Quaternion(rotation.axis, rotation.angle * scale)
                bpy.context.view_layer.update()
                tip = rig.matrix_world @ bones[2].tail
                location, normal, _index, distance = tree.find_nearest(tip)
                outside = location is not None and (tip - location).dot(normal) >= 0.0
                return (abs(distance - FINGER_REST_GAP_M) if outside else distance + 1.0), distance
            best = min((apply(step / 20.0)[0], step / 20.0) for step in range(41))
            _error, distance = apply(best[1])
            report['%s%d' % (side, finger)] = [best[1], round(distance * 1000.0, 1)]
    print('FINGER_FIT=' + json.dumps(report, sort_keys=True))

def aim_bone(bone_name, world_point):
    target = bpy.data.objects.new('Aim_' + bone_name, None)
    bpy.context.scene.collection.objects.link(target)
    target.location = world_point
    rig.pose.bones[bone_name].constraints.new('DAMPED_TRACK').target = target

# SC-HUM-01 transmitter hold, in metres. Source frame (owner model): width X, face toward -Y, up +Z.
TRANSMITTER_ROOT = 'T12D_root'
TRANSMITTER_GIMBALS = ('Stick_Izq_eje', 'Stick_Der_eje')  # their midpoint is the hold reference
TRANSMITTER_HOLD = (0.0, -0.255, 1.11)  # gimbal midpoint in the pose frame (pilot faces -Y)
TRANSMITTER_TILT_DEG = 35.0  # face elevation above horizontal, toward the pilot's eyes
# Right hand in the source frame (the left mirrors X): wrist below the side of the rear grip, the hand
# pointing up along the grip with the fingers curled behind it, the thumb tip on the gimbal stick.
TRANSMITTER_WRIST = (0.10, 0.04, 0.02)
TRANSMITTER_KNUCKLES = (0.085, 0.035, 0.12)
TRANSMITTER_THUMB = (0.05, -0.034, 0.10)
TRANSMITTER_MIN_PART_M = 0.010  # screws, LEDs, knobs and printed marks are below a pixel at field range
TRANSMITTER_TRIANGLES = 560  # keeps each pilot within the 8,000-triangle person cap; Godot adds automatic LODs
TRANSMITTER_PART_FLOOR = 8  # triangles a small part keeps (a four-sided stick)

def import_transmitter(path):
    """Append the transmitter's visible parts as frozen mesh objects, one per material, in its source frame.
    Returns (objects, frame): frame maps the source frame to the pose frame (gimbal midpoint, then tilt)."""
    if not path.is_file():
        raise RuntimeError('missing transmitter ' + str(path))
    with bpy.data.libraries.load(str(path), link=False) as (source, target):
        target.objects = list(source.objects)
    loaded = [obj for obj in target.objects if obj is not None]
    by_name = {obj.name: obj for obj in loaded}
    if TRANSMITTER_ROOT not in by_name or not all(name in by_name for name in TRANSMITTER_GIMBALS):
        raise RuntimeError('transmitter needs ' + TRANSMITTER_ROOT + ' and ' + ', '.join(TRANSMITTER_GIMBALS))
    for obj in loaded:
        bpy.context.scene.collection.objects.link(obj)
    def under_root(obj):
        while obj.parent is not None:
            obj = obj.parent
        return obj.name == TRANSMITTER_ROOT
    bpy.context.view_layer.update()
    gimbal_mid = (by_name[TRANSMITTER_GIMBALS[0]].matrix_world.translation + by_name[TRANSMITTER_GIMBALS[1]].matrix_world.translation) * 0.5
    def evaluated_copy(obj):
        return bpy.data.meshes.new_from_object(obj.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    frozen = []
    source_triangles = 0
    for obj in loaded:
        if obj.type not in ('MESH', 'CURVE') or not under_root(obj) or max(obj.dimensions) < TRANSMITTER_MIN_PART_M:
            continue
        for modifier in list(obj.modifiers):
            if modifier.type in ('BEVEL', 'WEIGHTED_NORMAL'):
                obj.modifiers.remove(modifier)  # edge rounding is invisible at field range
        mesh = evaluated_copy(obj)
        mesh.transform(obj.matrix_world)
        if not mesh.uv_layers:
            mesh.uv_layers.new()  # untextured parts become atlas swatches; the merge still reads a UV set
        part = bpy.data.objects.new('RC_Transmitter_' + obj.name, mesh)
        bpy.context.scene.collection.objects.link(part)
        source_triangles += sum(len(poly.vertices) - 2 for poly in mesh.polygons)
        # Merge coplanar faces first (no shape change), so the collapse below spends nothing on flat panels.
        planar = part.modifiers.new('Transmitter planar merge', 'DECIMATE')
        planar.decimate_type = 'DISSOLVE'
        planar.angle_limit = math.radians(5.0)
        planar.delimit = {'MATERIAL'}
        part.modifiers.new('Transmitter triangles', 'TRIANGULATE')
        part.data = evaluated_copy(part)
        part.modifiers.clear()
        frozen.append(part)
    for obj in loaded:
        bpy.data.objects.remove(obj, do_unlink=True)
    def triangle_count(objects):
        return sum(len(poly.vertices) - 2 for obj in objects for poly in obj.data.polygons)
    # Share the budget by surface area: the housing that is seen keeps its outline; small parts keep a floor.
    areas = {part.name: sum(poly.area for poly in part.data.polygons) for part in frozen}
    total_area = sum(areas.values())
    for part in frozen:
        target = max(TRANSMITTER_PART_FLOOR, TRANSMITTER_TRIANGLES * areas[part.name] / total_area)
        if target < triangle_count([part]):
            collapse = part.modifiers.new('Transmitter detail reduction', 'DECIMATE')
            collapse.ratio = target / triangle_count([part])
            part.data = evaluated_copy(part)
            part.modifiers.clear()
    bpy.ops.object.select_all(action='DESELECT')
    for part in frozen:
        part.select_set(True)
    bpy.context.view_layer.objects.active = frozen[0]
    bpy.ops.object.join()
    joined = bpy.context.object
    joined.name = 'RC_Transmitter'
    for material in joined.data.materials:
        if material and not material.name.startswith('RC_Transmitter_'):
            material.name = 'RC_Transmitter_' + material.name  # merge_people_atlas: rigid transmitter class
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.separate(type='MATERIAL')  # one glTF primitive per part
    bpy.ops.object.mode_set(mode='OBJECT')
    parts = [obj for obj in bpy.context.scene.objects if obj.name.startswith('RC_Transmitter')]
    print('TRANSMITTER=' + json.dumps({'source': str(path), 'source_triangles': source_triangles,
                                      'triangles': sum(len(p.vertices) - 2 for o in parts for p in o.data.polygons),
                                      'parts': len(parts)}, sort_keys=True))
    # Face from -Y to +Y (toward the pilot), tilt its top away by the face elevation, gimbals at the hold point.
    frame = (Matrix.Translation(TRANSMITTER_HOLD) @ Matrix.Rotation(math.radians(TRANSMITTER_TILT_DEG), 4, 'X')
             @ Matrix.Rotation(math.pi, 4, 'Z') @ Matrix.Translation(-gimbal_mid))
    return parts, frame

source_scale = 1.75 / 1.6594
# MPFB works in metres; LU-21 rescaled its androgynous default to 1.75 m. Natural outfits keep metres.
pose_scale = 1.0 if OUTFIT['height'] == 'natural' else source_scale
radio_parts = []
if ARGS.outfit:
    for side in ('L', 'R'):
        pose_fingers(side, FINGERS_RELAXED, THUMB_TUCK_RELAXED_DEG)
if pose_kind == 'seated':
    # The CC0 Anrico chair pose supplies both legs and arms; move its pelvis
    # to the field bench height before the final adult-scale bake.
    hip = rig.pose.bones['root'].head.z
    rig.location.z += (0.45 / pose_scale) - hip
    if ARGS.outfit:
        # Both hands rest on the thighs (the Anrico pose raises one hand beside the head, a frozen wave).
        bpy.context.view_layer.update()
        for side, sign in [('L', 1.0), ('R', -1.0)]:
            reset_pose_bones([part + '.' + side for part in ['clavicle', 'shoulder01', 'upperarm01', 'upperarm02', 'lowerarm01', 'lowerarm02']])
            hip_joint = rig.matrix_world @ rig.pose.bones['upperleg02.' + side].head
            knee = rig.matrix_world @ rig.pose.bones['lowerleg01.' + side].head
            rest = hip_joint.lerp(knee, SEAT_HAND_ALONG_THIGH) + Vector((sign * 0.005, 0.0, SEAT_HAND_LIFT_M / pose_scale))
            make_ik_target('SeatHand_' + side, tuple(rest), 'lowerarm02.' + side, 4, (sign * 0.45 / pose_scale, 0.25 / pose_scale, rest.z + 0.25 / pose_scale))
            aim_bone('wrist.' + side, knee + Vector((sign * 0.02, -0.06, 0.02)) / pose_scale)
elif pose_kind == 'pilot':
    # SC-HUM-01: the owner's transmitter, face tilted up toward the eyes, thumbs on the gimbals and the
    # wrists just outside its rear grips (IK). Both are placed from the transmitter frame, not by hand.
    radio_parts, radio_frame = import_transmitter(ARGS.transmitter)
    for side, sign in [('L', 1.0), ('R', -1.0)]:
        reset_pose_bones([part + '.' + side for part in ['clavicle', 'shoulder01', 'upperarm01', 'upperarm02', 'lowerarm01', 'lowerarm02']])
        # The pose faces -Y, so the pilot's left hand (+X) holds the transmitter's -X (left) side.
        wrist = radio_frame @ Vector((-sign * TRANSMITTER_WRIST[0], TRANSMITTER_WRIST[1], TRANSMITTER_WRIST[2]))
        make_ik_target('RadioHand_' + side, tuple(wrist / pose_scale), 'lowerarm02.' + side, 4, (sign * 0.36 / pose_scale, 0.22 / pose_scale, 1.15 / pose_scale))
        # Aim the hand and the thumb at grip points; curl the other fingers behind the grip.
        targets = {}
        for bone_name, point in [('wrist.' + side, TRANSMITTER_KNUCKLES), ('finger1-1.' + side, TRANSMITTER_THUMB)]:
            target = bpy.data.objects.new('RadioAim_' + bone_name, None)
            bpy.context.scene.collection.objects.link(target)
            target.location = radio_frame @ Vector((-sign * point[0], point[1], point[2])) / pose_scale
            targets[bone_name] = target
        rig.pose.bones['wrist.' + side].constraints.new('DAMPED_TRACK').target = targets['wrist.' + side]
        pose_fingers(side, FINGERS_GRIP, THUMB_TUCK_GRIP_DEG)
        # SC-HUM-07-R7: the thumb tip rests on the stick tip (IK over its three joints), not just aims at it.
        thumb = rig.pose.bones['finger1-3.' + side].constraints.new('IK')
        thumb.target = targets['finger1-1.' + side]
        thumb.chain_count = 3
        thumb.use_tail = True
        thumb.iterations = 200
    for part in radio_parts:
        part.data.transform(Matrix.Scale(1.0 / pose_scale, 4) @ radio_frame)
    fit_fingers_to_surface(radio_parts)
elif pose_kind == 'standing' and ARGS.outfit and os.path.basename(pose_path) in ARM_HANG_POSES:
    # Hang the arms beside the thighs (IK), elbows bending back toward a pole behind the shoulder.
    bpy.context.view_layer.update()
    for side, sign in [('L', 1.0), ('R', -1.0)]:
        shoulder = rig.matrix_world @ rig.pose.bones['upperarm01.' + side].head
        hip_joint = rig.matrix_world @ rig.pose.bones['upperleg02.' + side].head
        wrist = rig.matrix_world @ rig.pose.bones['wrist.' + side].head
        hang = Vector((shoulder.x + sign * ARM_HANG_OUT_M / pose_scale, hip_joint.y - ARM_HANG_AHEAD_M / pose_scale, wrist.z))
        make_ik_target('ArmHang_' + side, tuple(hang), 'lowerarm02.' + side, 4,
                       (shoulder.x, shoulder.y + 0.60 / pose_scale, (shoulder.z + hang.z) / 2))
elif pose_kind == 'working':
    # SC-HUM-06: standing at a 0.90 m pit table working on a model: a slight forward lean, eyes on the
    # work and both hands on the model in front (IK). Procedural placement of the CC0 standing pose only.
    for bone_name, degrees in [('spine04', 7.0), ('spine03', 7.0), ('neck02', 12.0), ('head', 14.0)]:
        bend_pose_bone(bone_name, degrees)
    for side, sign in [('L', 1.0), ('R', -1.0)]:
        reset_pose_bones([part + '.' + side for part in ['clavicle', 'shoulder01', 'upperarm01', 'upperarm02', 'lowerarm01', 'lowerarm02']])
        make_ik_target('WorkHand_' + side, (sign * 0.17 / pose_scale, -0.44 / pose_scale, 1.08 / pose_scale), 'lowerarm02.' + side, 4,
                       (sign * 0.45 / pose_scale, 0.10 / pose_scale, 1.05 / pose_scale))
        if ARGS.outfit:
            pose_fingers(side, FINGERS_GRIP, THUMB_TUCK_GRIP_DEG)
    if ARGS.outfit:
        # Palms down on the model, fingers forward: aim each hand ahead of and below where the IK left the wrist.
        bpy.context.view_layer.update()
        for side, sign in [('L', 1.0), ('R', -1.0)]:
            wrist = rig.matrix_world @ rig.pose.bones['wrist.' + side].head
            aim_bone('wrist.' + side, wrist + Vector((-sign * 0.04, -0.16, -0.07)) / pose_scale)
bpy.context.view_layer.update()
if ARGS.save_posed:
    bpy.ops.wm.save_as_mainfile(filepath=str(ARGS.save_posed), copy=True)
for bone_name in ['root', 'pelvis.L', 'pelvis.R', 'upperleg02.L', 'upperleg02.R', 'lowerleg01.L', 'lowerleg01.R', 'foot.L', 'foot.R', 'lowerarm02.L', 'lowerarm02.R']:
    bone = rig.pose.bones.get(bone_name)
    if bone:
        print('POSE_BONE=' + bone_name + ':HEAD:' + str(tuple(round(v, 4) for v in (rig.matrix_world @ bone.head))) + ':TAIL:' + str(tuple(round(v, 4) for v in (rig.matrix_world @ bone.tail))))

def patch_image(image, patches):
    """Cover regions of a source texture with fabric copied from just below, feathered at the edges (a CC0 shirt's
    MakeHuman logo, SC-HUM-07-R1). Each patch is [x0, y0, x1, y1, dy] in fractions of the image, top-left origin."""
    import numpy
    width, height = image.size
    pixels = numpy.empty(width * height * 4, dtype=numpy.float32)
    image.pixels.foreach_get(pixels)
    rgba = pixels.reshape(height, width, 4)[::-1]  # Blender rows start at the bottom
    for x0, y0, x1, y1, dy in patches:
        a, b, c, d = int(x0 * width), int(y0 * height), int(x1 * width), int(y1 * height)
        offset = int(dy * height)
        feather = max(1, min(c - a, d - b) // 6)
        ramp_x = numpy.minimum(numpy.arange(c - a) + 1, numpy.arange(c - a)[::-1] + 1) / feather
        ramp_y = numpy.minimum(numpy.arange(d - b) + 1, numpy.arange(d - b)[::-1] + 1) / feather
        weight = numpy.clip(numpy.minimum(ramp_y[:, None], ramp_x[None, :]), 0.0, 1.0)[..., None]
        rgba[b:d, a:c] = rgba[b:d, a:c] * (1.0 - weight) + rgba[b + offset:d + offset, a:c] * weight
    image.pixels.foreach_set(rgba[::-1].reshape(-1))
    image.update()

def opaque_mean_rgb(image):
    """Mean colour of the image's opaque pixels, in its stored encoding."""
    import numpy
    pixels = numpy.empty(image.size[0] * image.size[1] * 4, dtype=numpy.float32)
    image.pixels.foreach_get(pixels)
    rgba = pixels.reshape(-1, 4)
    opaque = rgba[:, 3] > 0.5
    return rgba[opaque, :3].mean(axis=0) if opaque.any() else None

def recolour_image(image, rgb):
    """Replace the colour of every pixel, keeping its alpha (the shape of a strand texture)."""
    import numpy
    pixels = numpy.empty(image.size[0] * image.size[1] * 4, dtype=numpy.float32)
    image.pixels.foreach_get(pixels)
    rgba = pixels.reshape(-1, 4)
    rgba[:, :3] = rgb
    image.pixels.foreach_set(rgba.reshape(-1))
    image.update()

def image_files():
    return [image for image in bpy.data.images if image.source == 'FILE' and image.size[0] > 0 and image.size[1] > 0]

def image_path(image):
    return image.filepath.lower().replace('\\', '/')

if ARGS.outfit:
    # SC-HUM-07-R5: MakeHuman eyebrows are near-black strands for any hair colour, and its default brown iris
    # reads red at 1080p. Brows take the hair's mean colour, darkened; an outfit may name a CC0 iris texture.
    hair = [opaque_mean_rgb(image) for image in image_files() if '/hair/' in image_path(image) and 'diffuse' in image_path(image)]
    hair = [rgb for rgb in hair if rgb is not None]
    for image in image_files():
        if '/eyebrows/' in image_path(image) and hair:
            recolour_image(image, hair[0] * EYEBROW_FROM_HAIR)
            print('EYEBROW_TINT=' + image.name + ':' + str([round(float(c), 3) for c in hair[0] * EYEBROW_FROM_HAIR]))
        if '/eyes/' in image_path(image) and OUTFIT.get('eye_texture'):
            image.filepath = str(ARGS.mpfb_user_data / 'data' / 'eyes' / 'materials' / OUTFIT['eye_texture'])
            image.reload()
            print('EYE_TEXTURE=' + image.name + ':' + OUTFIT['eye_texture'])

# Reduce embedded images for a small compatibility-renderer asset.
for image in list(bpy.data.images):
    if image.source != 'FILE' or image.size[0] <= 0 or image.size[1] <= 0:
        continue
    patches = OUTFIT.get('texture_patches', {}).get(os.path.basename(image.filepath))
    if patches:
        patch_image(image, patches)
        print('PATCHED_IMAGE=' + image.name + ':' + str(len(patches)))
    path = image.filepath.lower().replace('\\', '/')
    edges = OUTFIT['image_max_edge']
    if '/skins/' in path:
        max_edge = edges['skins']
    elif '/clothes/' in path or '/shoes/' in path:
        max_edge = edges['clothes']
    elif '/hair/' in path:
        max_edge = edges['hair']
    elif '/eyes/' in path or '/eyebrows/' in path or '/eyelashes/' in path:
        max_edge = edges['eyes']
    else:
        max_edge = edges['other']
    largest = max(image.size[0], image.size[1])
    if largest > max_edge:
        new_width = max(1, round(image.size[0] * max_edge / largest))
        new_height = max(1, round(image.size[1] * max_edge / largest))
        image.scale(new_width, new_height)
        print('RESIZED_IMAGE=' + image.name + ':' + str(new_width) + 'x' + str(new_height))

# Stage a glTF export with MPFB's own duplicate-and-clean pipeline.
export_root = ExportService.create_character_copy(human, name_suffix='_export')
export_base = ObjectService.find_object_of_type_amongst_nearest_relatives(export_root, 'Basemesh')
ExportService.bake_modifiers_remove_helpers(export_base, bake_masks=True, bake_subdiv=True, remove_helpers=True, also_proxy=True)
export_objects = [export_root] + ObjectService.get_list_of_children(export_root)
export_objects += radio_parts

# Freeze the already posed rig into ordinary mesh data; runtime animation,
# skeletons and unused body surfaces are not needed for a scenery crowd.
depsgraph = bpy.context.evaluated_depsgraph_get()
static_meshes = []
for obj in list(export_objects):
    if obj.type != 'MESH' or obj == export_base:
        continue
    for key, ratio in OUTFIT['decimate'].items():
        if key in obj.name:
            decimate = obj.modifiers.new('Export detail reduction', 'DECIMATE')
            decimate.ratio = ratio
            break
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(depsgraph)
    baked = bpy.data.meshes.new_from_object(evaluated, preserve_all_data_layers=True, depsgraph=depsgraph)
    baked.name = obj.name + '_static'
    world = obj.matrix_world.copy()
    obj.data = baked
    obj.parent = None
    obj.matrix_world = world
    for modifier in list(obj.modifiers):
        obj.modifiers.remove(modifier)
    static_meshes.append(obj)

# Center the feet at Y=0 and the body on X/Z. A 180 degree Blender-Z turn
# changes the source model's -Y front so the glTF/Godot front is -Z.
all_world = []
for obj in static_meshes:
    world = obj.matrix_world.copy()
    for vertex in obj.data.vertices:
        all_world.append(world @ vertex.co)
if not all_world:
    raise RuntimeError('no static meshes produced')
min_x = min(v.x for v in all_world)
max_x = max(v.x for v in all_world)
min_y = min(v.y for v in all_world)
max_y = max(v.y for v in all_world)
min_z = min(v.z for v in all_world)
max_z = max(v.z for v in all_world)
height_scale = 1.0 if OUTFIT['height'] == 'natural' else (source_scale if pose_kind == 'seated' else 1.75 / (max_z - min_z))
center_x = (min_x + max_x) * 0.5
center_y = (min_y + max_y) * 0.5
for obj in static_meshes:
    world = obj.matrix_world.copy()
    for vertex in obj.data.vertices:
        p = world @ vertex.co
        vertex.co = (-(p.x - center_x) * height_scale, -(p.y - center_y) * height_scale, (p.z - min_z) * height_scale)
    obj.location = (0, 0, 0)
    obj.rotation_euler = (0, 0, 0)
    obj.scale = (1, 1, 1)
    obj.parent = None
export_objects = static_meshes
print('STATIC_BOUNDS_BLENDER=' + json.dumps({'x': [-((max_x-min_x)*height_scale/2), (max_x-min_x)*height_scale/2], 'front_y': [-((max_y-min_y)*height_scale/2), (max_y-min_y)*height_scale/2], 'z': [0.0, (max_z-min_z)*height_scale]}, sort_keys=True))
triangles, detail = mesh_stats(export_objects)
print('EXPORT_TRIANGLES=' + str(triangles))
print('EXPORT_OBJECTS=' + json.dumps(detail, sort_keys=True))
print('EXPORT_OBJECT_COUNT=' + str(len(export_objects)))
print('MATERIAL_COUNT=' + str(len({m.name for o in export_objects if o.type == 'MESH' for m in o.data.materials if m})))
images = []
for image in bpy.data.images:
    if image.source == 'FILE' and image.size[0] > 0 and image.size[1] > 0:
        images.append({'name': image.name, 'width': int(image.size[0]), 'height': int(image.size[1]), 'filepath': bpy.path.abspath(image.filepath), 'packed': bool(image.packed_file)})
print('IMAGES=' + json.dumps(images, sort_keys=True))

# Set a one-frame keyed standing pose so the glTF contains the posed rig state.
if rig.animation_data is None:
    rig.animation_data_create()
standing_action = bpy.data.actions.new('Standing02')
rig.animation_data.action = standing_action
scene = bpy.context.scene
scene.frame_set(1)
for bone in rig.pose.bones:
    bone.keyframe_insert(data_path='rotation_euler', frame=1, group=bone.name)
    bone.keyframe_insert(data_path='location', frame=1, group=bone.name)
scene.frame_start = 1
scene.frame_end = 1

bpy.utils.refresh_script_paths()
addon_utils.modules_refresh()
try:
    addon_utils.enable('io_scene_gltf2', default_set=False, persistent=False)
except Exception as exc:
    print('GLTF_ENABLE=' + repr(exc))
if not hasattr(bpy.ops.export_scene, 'gltf'):
    raise RuntimeError('Blender GLB exporter unavailable')

bpy.ops.object.select_all(action='DESELECT')
for obj in export_objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = export_root
out_dir = stage
out_gltf = os.path.join(out_dir, name_stem + pose_kind + '.gltf')
bpy.ops.export_scene.gltf(filepath=out_gltf, export_format='GLTF_SEPARATE', use_selection=True, export_animations=False, export_apply=True, export_image_format='AUTO')
print('GLTF_BYTES=' + str(os.path.getsize(out_gltf)))
print('GLTF_PATH=' + out_gltf)

# Preview exactly the exported static meshes in a disposable Eevee render.
for obj in list(bpy.context.scene.objects):
    if obj not in static_meshes:
        bpy.data.objects.remove(obj, do_unlink=True)
for obj in static_meshes:
    obj.select_set(False)
floor_mat = bpy.data.materials.new('preview_floor')
floor_mat.diffuse_color = (0.18, 0.2, 0.22, 1.0)
floor_mat.use_nodes = True
floor_mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value = (0.18, 0.2, 0.22, 1.0)
bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, -0.02))
floor = bpy.context.object
floor.name = 'preview_floor'
floor.data.materials.append(floor_mat)
scene = bpy.context.scene
scene.render.engine = 'BLENDER_EEVEE'
scene.render.resolution_x = 640
scene.render.resolution_y = 800
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.filepath = os.path.join(stage, name_stem + pose_kind + '_preview.png')
scene.render.film_transparent = False
scene.world.color = (0.045, 0.055, 0.07)
scene.view_settings.view_transform = 'AgX'
cam_data = bpy.data.cameras.new('preview_camera')
cam = bpy.data.objects.new('preview_camera', cam_data)
scene.collection.objects.link(cam)
cam.location = (0, 5.5, 1.65)
target = Vector((0, 0, 0.82))
cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()
cam_data.type = 'ORTHO'
cam_data.ortho_scale = 2.0
scene.camera = cam
for name, loc, power, size in [
    ('key', (0, 3.4, 3.2), 500, 3.0),
    ('fill', (-3, 1.4, 1.8), 210, 3.5),
    ('rim', (0.5, 2.0, 3.0), 350, 2.0),
]:
    lamp_data = bpy.data.lights.new(name, 'AREA')
    lamp_data.energy = power
    lamp_data.shape = 'DISK'
    lamp_data.size = size
    lamp = bpy.data.objects.new(name, lamp_data)
    scene.collection.objects.link(lamp)
    lamp.location = loc
    lamp.rotation_euler = (target - lamp.location).to_track_quat('-Z', 'Y').to_euler()
scene.render.image_settings.color_mode = 'RGBA'
bpy.ops.render.render(write_still=True)
print('PREVIEW=' + scene.render.filepath)

blend_path = os.path.join(stage, name_stem + pose_kind + '.blend')
bpy.ops.wm.save_as_mainfile(filepath=blend_path)
print('BLEND_BYTES=' + str(os.path.getsize(blend_path)))
