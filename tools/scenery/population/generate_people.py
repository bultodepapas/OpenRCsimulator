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
from mathutils import Vector


def parse_arguments():
    if '--' not in sys.argv:
        raise RuntimeError('Pass --pose, --mpfb-user-data and --output-dir after Blender --')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pose', choices=('standing', 'seated', 'pilot'), required=True)
    parser.add_argument('--mpfb-user-data', required=True, type=Path,
                        help='MPFB user-data directory containing the installed CC0 system assets in data/')
    parser.add_argument('--output-dir', required=True, type=Path)
    parser.add_argument('--pose-file', type=Path,
                        help='Optional BVH override; defaults to the pinned source included in assets/scenery/population/source/')
    parser.add_argument('--outfit', type=Path,
                        help='SC-HUM-07 outfit JSON (tools/scenery/population/outfits/); omitted = the LU-21 person exactly')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    args.mpfb_user_data = args.mpfb_user_data.resolve()
    args.output_dir = args.output_dir.resolve()
    if not (args.mpfb_user_data / 'data').is_dir():
        parser.error('--mpfb-user-data must contain a data/ directory with MakeHuman system assets installed')
    repo_root = Path(__file__).resolve().parents[3]
    default_pose = 'anrico_sitting03' if args.pose == 'seated' else 'standing02'
    pose_directory = repo_root / 'assets/scenery/population/source/poses' / default_pose
    args.pose_file = (args.pose_file or (pose_directory / (default_pose + '.bvh'))).resolve()
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

source_scale = 1.75 / 1.6594
# MPFB works in metres; LU-21 rescaled its androgynous default to 1.75 m. Natural outfits keep metres.
pose_scale = 1.0 if OUTFIT['height'] == 'natural' else source_scale
radio_obj = None
if pose_kind == 'seated':
    # The CC0 Anrico chair pose supplies both legs and arms; move its pelvis
    # to the field bench height before the final adult-scale bake.
    hip = rig.pose.bones['root'].head.z
    rig.location.z += (0.45 / pose_scale) - hip
elif pose_kind == 'pilot':
    # Hold a compact two-stick transmitter just ahead of the abdomen.
    for side, sign in [('L', 1.0), ('R', -1.0)]:
        reset_pose_bones([part + '.' + side for part in ['clavicle', 'shoulder01', 'upperarm01', 'upperarm02', 'lowerarm01', 'lowerarm02']])
        make_ik_target('RadioHand_' + side, (sign * 0.145 / pose_scale, -0.27 / pose_scale, 1.065 / pose_scale), 'lowerarm02.' + side, 4, (sign * 0.36 / pose_scale, 0.22 / pose_scale, 1.15 / pose_scale))
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, -0.265 / pose_scale, 1.015 / pose_scale))
    radio_obj = bpy.context.object
    radio_obj.name = 'RC_Transmitter'
    radio_obj.dimensions = (0.23 / pose_scale, 0.09 / pose_scale, 0.15 / pose_scale)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    radio_mat = bpy.data.materials.new('RC_Transmitter_Matte_Dark')
    radio_mat.diffuse_color = (0.015, 0.02, 0.03, 1.0)
    radio_mat.use_nodes = True
    radio_mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value = (0.015, 0.02, 0.03, 1.0)
    radio_mat.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value = 0.82
    radio_obj.data.materials.append(radio_mat)
    radio_parts = [radio_obj]
    for side, sign in [('Left', 1.0), ('Right', -1.0)]:
        bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.014 / pose_scale, depth=0.04 / pose_scale, location=(sign * 0.055 / pose_scale, -0.265 / pose_scale, (1.015 + 0.09) / pose_scale))
        part = bpy.context.object
        part.name = 'RC_Stick_' + side
        part.data.materials.append(radio_mat)
        radio_parts.append(part)
    bpy.ops.object.select_all(action='DESELECT')
    for part in radio_parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = radio_obj
    bpy.ops.object.join()
    bevel = radio_obj.modifiers.new('Radio housing edge bevel', 'BEVEL')
    bevel.width = 0.008 / pose_scale
    bevel.segments = 2
bpy.context.view_layer.update()
for bone_name in ['root', 'pelvis.L', 'pelvis.R', 'upperleg02.L', 'upperleg02.R', 'lowerleg01.L', 'lowerleg01.R', 'foot.L', 'foot.R', 'lowerarm02.L', 'lowerarm02.R']:
    bone = rig.pose.bones.get(bone_name)
    if bone:
        print('POSE_BONE=' + bone_name + ':HEAD:' + str(tuple(round(v, 4) for v in (rig.matrix_world @ bone.head))) + ':TAIL:' + str(tuple(round(v, 4) for v in (rig.matrix_world @ bone.tail))))

# Reduce embedded images for a small compatibility-renderer asset.
for image in list(bpy.data.images):
    if image.source != 'FILE' or image.size[0] <= 0 or image.size[1] <= 0:
        continue
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
if radio_obj is not None:
    export_objects.append(radio_obj)

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
