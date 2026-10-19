import bpy, json, os, math
from mathutils import Vector
source = os.path.abspath('tmp/house-tree-intake/source/jacaranda_tree_1k.blend')
bpy.ops.wm.open_mainfile(filepath=source)

def bbox_world(obj):
    pts = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    return [[min(p[i] for p in pts), max(p[i] for p in pts)] for i in range(3)]

def mat_maps(mat):
    if not mat or not mat.use_nodes or not mat.node_tree:
        return []
    out = []
    for node in mat.node_tree.nodes:
        if node.type == 'TEX_IMAGE' and node.image:
            img = node.image
            out.append({'node': node.name, 'image': img.name, 'filepath': img.filepath, 'packed': bool(img.packed_file), 'size': list(img.size)})
    return out

objects = []
for obj in bpy.data.objects:
    rec = {
      'name': obj.name, 'type': obj.type, 'parent': obj.parent.name if obj.parent else None,
      'collections': [c.name for c in obj.users_collection],
      'location': list(obj.location), 'dimensions': list(obj.dimensions),
      'world_bounds_xyz': bbox_world(obj), 'hide_render': obj.hide_render, 'hide_viewport': obj.hide_viewport,
      'materials': []
    }
    if obj.type == 'MESH' and obj.data:
        mesh = obj.data
        mesh.calc_loop_triangles()
        rec.update({'mesh_name': mesh.name, 'vertices': len(mesh.vertices), 'polygons': len(mesh.polygons), 'triangles': len(mesh.loop_triangles)})
        for slot in obj.material_slots:
            mat = slot.material
            rec['materials'].append({'name': mat.name if mat else None, 'maps': mat_maps(mat)})
    elif obj.type == 'EMPTY':
        rec['empty_type'] = obj.empty_display_type
    elif obj.type == 'CURVES':
        rec['curve_name'] = obj.data.name
    objects.append(rec)

collections = []
def walk(c, depth=0):
    collections.append({'name': c.name, 'depth': depth, 'objects': [o.name for o in c.objects], 'children': [ch.name for ch in c.children]})
    for child in c.children: walk(child, depth+1)
for c in bpy.data.collections:
    if c.name not in [ch.name for parent in bpy.data.collections for ch in parent.children]:
        walk(c)

nodegroups=[]
for ng in bpy.data.node_groups:
    nodegroups.append({'name': ng.name, 'type': ng.bl_idname, 'nodes': [{'name': n.name, 'type': n.bl_idname, 'label': n.label} for n in ng.nodes]})

images=[]
for img in bpy.data.images:
    images.append({'name':img.name,'filepath':img.filepath,'packed':bool(img.packed_file),'size':list(img.size),'source':img.source})

depsgraph=bpy.context.evaluated_depsgraph_get()
instances=[]
for inst in depsgraph.object_instances:
    if inst.is_instance:
        ob=inst.object
        instances.append({'object':ob.name,'type':ob.type,'parent':inst.parent.name if inst.parent else None,'matrix_translation':list(inst.matrix_world.translation)})
result = {'blend':source, 'blender':bpy.app.version_string,'scenes':[s.name for s in bpy.data.scenes], 'objects':objects,'collections':collections,'nodegroups':nodegroups,'images':images,'depsgraph_instance_count':len(instances),'instances':instances}
out='tmp/house-tree-intake/source/jacaranda_inspection.json'
with open(out,'w',encoding='utf-8') as f: json.dump(result,f,indent=2)
print('INSPECTION_JSON='+out)
print('BLENDER='+bpy.app.version_string)
print('OBJECT_COUNT='+str(len(objects))+' MESH_OBJECTS='+str(sum(1 for o in objects if o['type']=='MESH'))+' COLLECTIONS='+str(len(collections))+' NODEGROUPS='+str(len(nodegroups))+' IMAGES='+str(len(images))+' DEPSGRAPH_INSTANCES='+str(len(instances)))
for o in objects:
    if o['type']=='MESH': print('MESH',o['name'],'verts',o['vertices'],'faces',o['polygons'],'tris',o['triangles'],'collections',','.join(o['collections']),'bounds',json.dumps(o['world_bounds_xyz']))
for c in collections: print('COLLECTION',c['depth'],c['name'],'objects=',','.join(c['objects']),'children=',','.join(c['children']))
for i in images: print('IMAGE',i['name'],'packed=',i['packed'],'size=',i['size'],'path=',i['filepath'])
for ng in nodegroups: print('NODEGROUP',ng['name'],ng['type'],'nodes=',','.join(n['type'] for n in ng['nodes']))
for inst in instances: print('INSTANCE',inst)
