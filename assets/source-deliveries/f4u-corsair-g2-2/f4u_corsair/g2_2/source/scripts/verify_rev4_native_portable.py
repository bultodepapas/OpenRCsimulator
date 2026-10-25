"""Portable read-only F4U g2 native contract audit.

Run in Blender 5.2.2 (the only runtime dependency):
  blender -b -t 2 --factory-startup --disable-autoexec --python verify_rev4_native_portable.py -- \
    --candidate source/aircraft_game.blend --metadata metadata.json \
    --gear-reference source/scripts/gear-reference.json --out checks/native_portable.json

Requires only the packaged candidate, metadata and gear-reference JSON. It does not open g1 or R59.
"""
import bpy, json, math, sys, argparse, hashlib
from pathlib import Path
from mathutils import Matrix, Vector

VALID_SECTIONS={'core','wing_left','wing_right','wing_center','horizontal_tail','vertical_tail','engine','propeller','gear','canopy'}
REQUIRED_PARENT={
 'aileron_left_hinge':'F4UCorsair','aileron_right_hinge':'F4UCorsair',
 'flap_left_1_hinge':'F4UCorsair','flap_left_2_hinge':'F4UCorsair','flap_left_3_hinge':'F4UCorsair',
 'flap_right_1_hinge':'F4UCorsair','flap_right_2_hinge':'F4UCorsair','flap_right_3_hinge':'F4UCorsair',
 'elevator_hinge':'F4UCorsair','rudder_hinge':'F4UCorsair',
 'thrust_frame':'F4UCorsair','propeller_spin':'thrust_frame'}
REQUIRED_CHILD={
 'aileron_left_hinge':'aileron_left','aileron_right_hinge':'aileron_right',
 'flap_left_1_hinge':'flap_left_1','flap_left_2_hinge':'flap_left_2','flap_left_3_hinge':'flap_left_3',
 'flap_right_1_hinge':'flap_right_1','flap_right_2_hinge':'flap_right_2','flap_right_3_hinge':'flap_right_3',
 'elevator_hinge':'elevator','rudder_hinge':'rudder','thrust_frame':'propeller_spin','propeller_spin':'propeller_rotor'}
GEAR_HELPERS={f'gear_{kind}_{role}' for role in ('left','right','tail') for kind in ('compression','spin','wheel')}|{'gear_steer_tail'}
LINKS={'gear_retraction_link_left':('gear_fold_left','gear'),'gear_retraction_link_right':('gear_fold_right','gear')}

def args_parse():
    raw=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    ap=argparse.ArgumentParser()
    for n in ('candidate','metadata','gear-reference','out'):ap.add_argument('--'+n,required=True)
    return ap.parse_args(raw)
def sha256(p):
    h=hashlib.sha256()
    with Path(p).open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
    return h.hexdigest()
def mat_list(m):return [[float(m[r][c]) for c in range(4)] for r in range(4)]
def max_matrix_delta(a,b):return max(abs(float(a[r][c])-float(b[r][c])) for r in range(4) for c in range(4))
def rotation_delta_deg(a,b):
    qa=a.to_quaternion();qb=b.to_quaternion();dot=abs(float(qa.dot(qb)))
    return math.degrees(2.0*math.acos(max(-1.0,min(1.0,dot))))
def outward_share(obj):
    mesh=obj.data;mesh.calc_loop_triangles();total=outward=0.0
    for tri in mesh.loop_triangles:
        a,b,c=(obj.matrix_world @ mesh.vertices[i].co for i in tri.vertices)
        normal=(b-a).cross(c-a);area=.5*normal.length
        if area<=0:continue
        center=(a+b+c)/3.0
        if normal.dot(Vector((center.x,0.0,center.z)))>0:outward+=area
        total+=area
    return outward/total if total else 0.0

def main():
    a=args_parse();cand=Path(a.candidate);meta_path=Path(a.metadata);gear_path=Path(a.gear_reference)
    meta=json.loads(meta_path.read_text(encoding='utf-8'));gear_ref=json.loads(gear_path.read_text(encoding='utf-8'))
    bpy.ops.wm.open_mainfile(filepath=str(cand),load_ui=False)
    scene=bpy.context.scene;col=bpy.data.collections.get('EXPORT_aircraft')
    objs=list(col.objects) if col else list(bpy.data.objects);by={o.name:o for o in objs}
    checks=[]
    def check(label,ok,detail=None):checks.append({'name':label,'ok':bool(ok),'detail':detail})

    expected_nodes=meta.get('nodes',{});expected_mesh={r['node']:r for r in meta.get('meshes',[])}
    check('EXPORT_aircraft collection exists',col is not None)
    check('native node names exactly match current metadata',set(by)==set(expected_nodes),{'actual_only':sorted(set(by)-set(expected_nodes)),'metadata_only':sorted(set(expected_nodes)-set(by))})
    check('node names are ASCII and unique',len(by)==len(objs) and all(n.isascii() for n in by),{'nodes':len(objs)})
    check('no cameras or lights in exported collection',all(o.type not in {'CAMERA','LIGHT'} for o in objs),[o.name for o in objs if o.type in {'CAMERA','LIGHT'}])

    invalid=[];cross=[];transform=[];constraints=[];drivers=[];mesh_rows=[];material_names=set();total_tri=total_surfaces=0
    for o in objs:
        sec=o.get('openrc_section')
        # thrust_frame is the fixed thrust-axis datum between the root and the
        # articulated propeller_spin pivot. The handoff preflight explicitly
        # requires it to remain untagged; it is not a detachable section.
        if o.name not in {'F4UCorsair','thrust_frame'} and sec not in VALID_SECTIONS:invalid.append({'node':o.name,'section':sec})
        p=o.parent
        while p:
            ps=p.get('openrc_section')
            if ps and sec and ps!=sec:cross.append({'child':o.name,'ancestor':p.name,'child_section':sec,'ancestor_section':ps})
            p=p.parent
        if any(abs(float(s)-1.0)>1e-6 for s in o.scale) or o.matrix_local.to_3x3().determinant()<=0:
            transform.append({'node':o.name,'scale':list(o.scale),'det':float(o.matrix_local.to_3x3().determinant())})
        if o.constraints:constraints.append({'node':o.name,'constraints':[c.name for c in o.constraints]})
        if o.animation_data and o.animation_data.drivers:drivers.append({'node':o.name,'count':len(o.animation_data.drivers)})
        exp=expected_nodes.get(o.name,{})
        actual_parent=o.parent.name if o.parent else None
        if actual_parent!=exp.get('parent') or sec!=exp.get('section'):
            cross.append({'node':o.name,'metadata_parent':exp.get('parent'),'actual_parent':actual_parent,'metadata_section':exp.get('section'),'actual_section':sec,'kind':'metadata'} )
        if o.type=='MESH':
            me=o.data;me.calc_loop_triangles();tris=len(me.loop_triangles);used=sorted({p.material_index for p in me.polygons if p.material_index<len(me.materials) and me.materials[p.material_index]})
            names=sorted({me.materials[i].name for i in used})
            material_names.update(names);surfaces=len(used);total_tri+=tris;total_surfaces+=surfaces
            mesh_rows.append({'node':o.name,'triangles':tris,'surfaces':surfaces,'section':sec,'used_materials':names})

    check('every node and mesh/pivot has valid openrc_section',not invalid,invalid[:50])
    check('static thrust_frame datum remains untagged', 'thrust_frame' in by and by['thrust_frame'].get('openrc_section') is None, {'section':by['thrust_frame'].get('openrc_section') if 'thrust_frame' in by else 'missing'})
    check('no detachable ancestor crosses section and parents/tags match metadata',not cross,cross[:50])
    check('unit positive node transforms',not transform,transform[:50])
    check('no constraints or drivers',not constraints and not drivers,{'constraints':constraints[:10],'drivers':drivers[:10]})
    mesh_errors=[]
    if set(row['node'] for row in mesh_rows)!=set(expected_mesh):mesh_errors.append({'native_only':sorted(set(r['node'] for r in mesh_rows)-set(expected_mesh)),'metadata_only':sorted(set(expected_mesh)-set(r['node'] for r in mesh_rows))})
    for row in mesh_rows:
        exp=expected_mesh.get(row['node'],{})
        for key in ('triangles','surfaces','section'):
            if row.get(key)!=exp.get(key):mesh_errors.append({'node':row['node'],'field':key,'native':row.get(key),'metadata':exp.get(key)})
    check('native per-mesh counts and sections match metadata',not mesh_errors,mesh_errors[:50])
    check('native aggregate counts match metadata',total_tri==int(meta.get('triangle_count',-1)) and total_surfaces==int(meta.get('surface_count',-1)) and len(material_names)==int(meta.get('material_count',-1)) and len(mesh_rows)==len(expected_mesh),{'triangles':total_tri,'metadata_triangles':meta.get('triangle_count'),'surfaces':total_surfaces,'metadata_surfaces':meta.get('surface_count'),'materials':len(material_names),'metadata_materials':meta.get('material_count'),'meshes':len(mesh_rows)})
    check('Revision 4 geometry and package budgets',300000<=total_tri<=350000 and total_tri<=450000 and total_surfaces<=70 and len(material_names)<=16 and int(meta.get('glb_bytes',10**12))<=30000000,{'triangles':total_tri,'surfaces':total_surfaces,'materials':len(material_names),'glb_bytes':meta.get('glb_bytes')})
    check('native source SHA-256 matches current metadata',sha256(cand)==meta.get('source_blend_sha256'),{'actual':sha256(cand),'metadata':meta.get('source_blend_sha256')})
    check('metric metre scene and saved neutral frame 0',scene.unit_settings.system=='METRIC' and abs(scene.unit_settings.scale_length-1)<1e-9 and scene.frame_current==0,{'unit_system':scene.unit_settings.system,'scale_length':scene.unit_settings.scale_length,'frame_current':scene.frame_current})
    root=by.get('F4UCorsair');root_delta=max_matrix_delta(root.matrix_world,Matrix.Identity(4)) if root else float('inf')
    check('root identity',root is not None and root_delta<1e-7,{'max_matrix_delta':root_delta})
    required=set(REQUIRED_PARENT)|set(REQUIRED_CHILD)|GEAR_HELPERS|{x['node'] for x in meta.get('gear',{}).get('carriers',[])}|set(LINKS)
    missing=sorted(required-set(by))
    parent_errors=[{'node':n,'actual':by[n].parent.name if by[n].parent else None,'expected':p} for n,p in REQUIRED_PARENT.items() if n in by and (by[n].parent.name if by[n].parent else None)!=p]
    child_errors=[{'node':child,'actual_parent':by[child].parent.name if by[child].parent else None,'expected_parent':hinge} for hinge,child in REQUIRED_CHILD.items() if child in by and (by[child].parent.name if by[child].parent else None)!=hinge]
    for n,(p,s) in LINKS.items():
        if n in by and (by[n].type!='MESH' or by[n].parent is None or by[n].parent.name!=p or by[n].get('openrc_section')!=s):child_errors.append({'node':n,'type':by[n].type,'parent':by[n].parent.name if by[n].parent else None,'section':by[n].get('openrc_section'),'expected':[p,s]})
    check('required pivots/helpers and Revision 4 link parents',not missing and not parent_errors and not child_errors,{'missing':missing,'parent_errors':parent_errors,'child_errors':child_errors})
    check('Naval 308 is first/default livery',meta.get('default_livery')=='midnight' and bool(meta.get('liveries')) and meta['liveries'][0].get('id')=='midnight' and meta['liveries'][0].get('name')=='Naval 308' and meta['liveries'][0].get('default') is True,{'default':meta.get('default_livery'),'first':meta.get('liveries',[None])[0]})
    action=bpy.data.actions.get('GearRetract');gear=meta.get('gear',{});gear_nodes={x.get('node') for x in gear.get('carriers',[])}
    animated={o.name:o.animation_data.action.name for o in objs if o.animation_data and o.animation_data.action}
    check('GearRetract action range and assigned carriers',action is not None and list(action.frame_range)==[0.0,100.0] and bool(animated) and set(animated.values())=={'GearRetract'} and set(animated).issubset(gear_nodes),{'range':list(action.frame_range) if action else None,'animated':animated,'metadata_carriers':sorted(gear_nodes)})
    check('metadata declares 101 GearRetract samples at frame 100',gear.get('action')=='GearRetract' and gear.get('samples')==101 and meta.get('runtime_export_frame')==100,{'gear':{'action':gear.get('action'),'samples':gear.get('samples')},'runtime_export_frame':meta.get('runtime_export_frame')})

    # Compare all listed gear carriers at every integer frame against the packaged external reference.
    ref_errors=[];max_t=max_a=0.0;sample_count=0
    if action:
        for name,frames in gear_ref.items():
            obj=by.get(name)
            if obj is None or len(frames)!=101:
                ref_errors.append({'node':name,'error':'missing node or reference does not have 101 frames','reference_frames':len(frames)})
                continue
            for f,rows in enumerate(frames):
                scene.frame_set(f);bpy.context.view_layer.update();actual=obj.rotation_quaternion;expected_matrix=Matrix(rows);expected=expected_matrix.to_quaternion()
                dt=(obj.location-expected_matrix.translation).length;dot=abs(float(actual.dot(expected)))/max(math.sqrt(float(actual.dot(actual))*float(expected.dot(expected))),1e-30);da=math.degrees(2.0*math.acos(max(-1.0,min(1.0,dot))))
                max_t=max(max_t,dt);max_a=max(max_a,da);sample_count+=1
                if dt>1e-5 or da>0.01:ref_errors.append({'node':name,'frame':f,'translation_m':dt,'rotation_deg':da})
    check('all carrier GearRetract samples match packaged gear reference within 0.01mm/0.01deg',sample_count==len(gear_ref)*101 and not ref_errors,{'carriers':len(gear_ref),'samples':sample_count,'max_translation_m':max_t,'max_rotation_deg':max_a,'violations':ref_errors[:25]})

    # Frame 100 native matrices are compared to the package sidecar used for GLB export.
    scene.frame_set(100);bpy.context.view_layer.update();matrix_errors=[]
    for name,rec in expected_nodes.items():
        obj=by.get(name)
        if obj is None:continue
        if 'rest_matrix_local' in rec and max_matrix_delta(obj.matrix_local,Matrix(rec['rest_matrix_local']))>1e-6:matrix_errors.append({'node':name,'matrix':'local','delta':max_matrix_delta(obj.matrix_local,Matrix(rec['rest_matrix_local']))})
        if 'rest_matrix_blender' in rec and max_matrix_delta(obj.matrix_world,Matrix(rec['rest_matrix_blender']))>1e-6:matrix_errors.append({'node':name,'matrix':'world','delta':max_matrix_delta(obj.matrix_world,Matrix(rec['rest_matrix_blender']))})
    check('frame-100 native node matrices match metadata',not matrix_errors,matrix_errors[:30])
    fus=by.get('fuselage_core');share=outward_share(fus) if fus and fus.type=='MESH' else 0.0
    check('fuselage winding is outward',share>=0.60,{'area_weighted_outward_share':share})

    scene.frame_set(0);bpy.context.view_layer.update()
    report={'audit':'F4U g2 portable native Revision 4 audit','read_only':True,'blender_version':bpy.app.version_string,
      'dependencies':['candidate aircraft_game.blend','metadata.json','gear-reference.json'],'not_required':['g1 aircraft blend','R59 source blend'],
      'inputs':{'candidate':{'path':str(cand.resolve()),'sha256':sha256(cand)},'metadata':str(meta_path.resolve()),'gear_reference':str(gear_path.resolve())},
      'counts':{'triangles':total_tri,'mesh_nodes':len(mesh_rows),'surfaces':total_surfaces,'materials':len(material_names)},
      'gear_reference':{'carriers':len(gear_ref),'samples':sample_count,'max_translation_m':max_t,'max_rotation_deg':max_a},
      'checks_passed':sum(x['ok'] for x in checks),'checks_total':len(checks),'ok':all(x['ok'] for x in checks),'checks':checks}
    out=Path(a.out);out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    print('G2_PORTABLE_NATIVE_AUDIT',json.dumps({'ok':report['ok'],'checks_passed':report['checks_passed'],'checks_total':report['checks_total'],'counts':report['counts'],'gear_reference':report['gear_reference'],'report':str(out)},ensure_ascii=False),flush=True)
    return 0 if report['ok'] else 1

sys.exit(main())


