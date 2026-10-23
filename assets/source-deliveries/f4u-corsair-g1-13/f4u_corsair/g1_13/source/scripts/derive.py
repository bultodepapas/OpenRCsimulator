"""Blender 5.2.2: --background --disable-autoexec --python derive.py -- --master R59.blend"""
import bpy,bmesh,json,math,sys,argparse,hashlib,re
from pathlib import Path
from mathutils import Matrix,Vector
P=Path(__file__).resolve().parents[2]
for sub in ['source','export','previews','textures/liveries']: (P/sub).mkdir(parents=True,exist_ok=True)
args=argparse.ArgumentParser();args.add_argument('--master',required=True);args.add_argument('--reference-cache');opts=args.parse_args(sys.argv[sys.argv.index('--')+1:]);MASTER=Path(opts.master).resolve()
assert bpy.app.version[:3]==(5,2,2),bpy.app.version_string
master_hash=hashlib.sha256(MASTER.read_bytes()).hexdigest();bpy.ops.wm.open_mainfile(filepath=str(MASTER));scene=bpy.context.scene;source_root=bpy.data.objects['F4U CORSAIR | avion completo'];all_source=list(bpy.data.objects);source_names=[o.name for o in all_source];used={};rig_sources={}
for o in all_source:
 if o.animation_data:o.animation_data.action=None
source_root.matrix_world=Matrix.Identity(4)
for key in ['flaps_deg','alerones_deg','compensador_deg','elevadores_deg','trim_elevadores_deg','timon_deg','trim_timon_deg','cowl_flaps_deg','tren_retraccion','gancho_cola_deg','compresion_amortiguador_derecha','compresion_amortiguador_izquierda']:source_root[key]=0.
for o in all_source:
 if o.name=='R51 | CONTROL ALAS':
  for s in ['derecha','izquierda']:o['plegado_'+s]=0.;o['bloqueo_'+s]=1.;o['puntal_'+s]=0.
 if o.name.startswith('CABINA | apertura'):o['apertura']=0.
 if o.name=='Motor radial | detalles frontales':o['giro_helice_grados']=0.
 if o.name=='R49 | CONTROL helice':o['paso_visual_deg']=0.
 o.update_tag()
bpy.context.view_layer.update()
# D0: actual centreline/root leading-edge vertices, not a rotated bounding box.
wing=bpy.data.objects['Ala derecha | gaviota invertida'];ev=wing.evaluated_get(bpy.context.evaluated_depsgraph_get());me=ev.to_mesh();wv=[ev.matrix_world@v.co for v in me.vertices];near=[v for v in wv if abs(v.y)<.055];d0x=min(v.x for v in near);ev.to_mesh_clear();d0z=bpy.data.objects['R49 | CONTROL helice'].matrix_world.translation.z;D0=Vector((d0x,0,d0z))
R=Matrix(((0,1,0),(-1,0,0),(0,0,1)));G=R.to_4x4();G.translation=-(R@D0)*.2
for i in range(3):
 for j in range(3):G[i][j]*=.2
def point(v):return G@Vector(v)
def rigid(m):
 loc=point(m.translation);q=(R@m.to_3x3().normalized()).to_quaternion();out=q.to_matrix().to_4x4();out.translation=loc;return out
def frame(p,x=(1,0,0),up=(0,0,1)):
 x=Vector(x).normalized();up=Vector(up);z=(up-x*up.dot(x)).normalized()
 if z.length<.01:z=x.orthogonal().normalized()
 y=z.cross(x).normalized();z=x.cross(y).normalized();m=Matrix((x,y,z)).transposed().to_4x4();m.translation=Vector(p);return m
col=bpy.data.collections.new('EXPORT_aircraft');scene.collection.children.link(col);refcol=bpy.data.collections.new('G1_REFERENCE')if opts.reference_cache else None;nodes={};parts={};articulations=[];raw_reference={};witness={};skin_names=[];detail_landmarks={}
def node(name,section=None,parent='F4UCorsair',world=None):
 o=bpy.data.objects.new(name,None);col.objects.link(o)
 if section:o['openrc_section']=section
 if parent:o.parent=nodes[parent]
 o.matrix_world=world or Matrix.Identity(4);o.empty_display_size=.025;nodes[name]=o;return o
node('F4UCorsair',parent=None);node('gear_root','gear');node('thrust_frame',parent='F4UCorsair',world=frame(point((-4.96,0,d0z)),(0,1,0),(0,0,1)));node('propeller_spin','propeller',parent='thrust_frame',world=nodes['thrust_frame'].matrix_world.copy())
def pivot(name,src,section,axis='Y',parent='F4UCorsair',direction='trailing_edge_down',range_deg=None):
 o=bpy.data.objects[src];m=o.matrix_world;ax=R@(m.to_3x3()@Vector({'Y':(0,1,0),'Z':(0,0,1)}[axis])).normalized();f=frame(point(m.translation),ax,(0,0,1)if axis=='Y'else(0,1,0));p=node(name,section,parent,f);rig_sources[src]=name
 articulations.append({'node':name,'parent':parent,'section':section,'pivot':list(p.location),'axis_local':[1,0,0],'positive':direction,'checked_range_degrees':range_deg,'rest_matrix_local':[list(row)for row in p.matrix_local]});return p
for s,role in [('izquierda','left'),('derecha','right')]:
 pivot('aileron_'+role+'_hinge','Superficie R9 | eje aleron '+s,'wing_'+role,range_deg=[-25,25])
 for i in [1,2,3]:pivot(f'flap_{role}_{i}_hinge',f'Bisagra articulada flap {s} {i}','wing_'+role if i==3 else'wing_center',range_deg=[0,50])
pivot('elevator_hinge','R11 | eje comun de elevadores','horizontal_tail',range_deg=[-25,25]);pivot('rudder_hinge','R12 | eje vertical del timon','vertical_tail','Z',direction='trailing_edge_to_pilot_right',range_deg=[-35,35])
carriers=[]
def carrier(name,src,parent='gear_root'):
 o=node(name,'gear',parent,rigid(bpy.data.objects[src].matrix_world));rig_sources[src]=name;carriers.append({'node':name,'source':src,'parent':parent});return o
wheel_specs={}
def source_vertices(name,evaluated=True):
 o=bpy.data.objects[name];ev=o.evaluated_get(bpy.context.evaluated_depsgraph_get());m=ev.to_mesh();vv=[ev.matrix_world@v.co for v in m.vertices];ev.to_mesh_clear();return vv
for s,role in [('izquierda','left'),('derecha','right')]:
 carrier('gear_fold_'+role,'R22 | eje retraccion '+s);carrier('gear_twist_'+role,'R22 | giro de rueda '+s,'gear_fold_'+role);carrier('gear_compression_'+role,'R22 | corredera oleo '+s,'gear_twist_'+role)
 for suffix,src in [('door_front','R23 | bisagra tapa frontal '),('door_inner','R22 | bisagra puerta interior '),('door_outer','R22 | bisagra puerta exterior ')]:carrier('gear_'+suffix+'_'+role,src+s)
 vv=source_vertices('R22 | neumatico principal '+s);lo=Vector([min(v[k]for v in vv)for k in range(3)]);hi=Vector([max(v[k]for v in vv)for k in range(3)]);center=(lo+hi)/2;rad=(hi.z-lo.z)/2
 node('gear_spin_'+role,'gear','gear_compression_'+role,frame(point(center),(1,0,0)));wheel_specs[role]={'source_center':list(center),'center':list(point(center)),'ground_contact':list(point(center-Vector((0,0,rad)))),'radius_m':rad*.2,'oleo_travel_m':.2*source_root.get('R28_oleo_stow_stroke',.10),'compression_axis_local':[0,0,1]}
carrier('gear_carrier_tail','R27 | pivote transversal pata')
for s,role in [('izquierda','left'),('derecha','right')]:
 for i in [1,2]:carrier(f'gear_door_tail_{role}_{i}',f'R27 | giro puerta {s} {i}')
vv=source_vertices('R27 | neumatico cola');lo=Vector([min(v[k]for v in vv)for k in range(3)]);hi=Vector([max(v[k]for v in vv)for k in range(3)]);center=(lo+hi)/2;rad=(hi.z-lo.z)/2
steer=Matrix(((1,0,0),(0,0,-1),(0,1,0))).to_4x4();steer.translation=point(center)+Vector((0,0,.04));node('gear_steer_tail','gear','gear_carrier_tail',steer);node('gear_compression_tail','gear','gear_steer_tail',frame(point(center)+Vector((0,0,.04))));node('gear_spin_tail','gear','gear_compression_tail',frame(point(center),(1,0,0)));wheel_specs['tail']={'source_center':list(center),'center':list(point(center)),'ground_contact':list(point(center-Vector((0,0,rad)))),'radius_m':rad*.2,'oleo_travel_m':.025,'compression_axis_local':[0,0,1],'travel_provenance':'g1 authored helper range; R59 tail assembly rigid'}
print('Sampling gear',len(carriers),flush=True);samples={c['node']:[]for c in carriers}
for f in range(101):
 source_root['tren_retraccion']=f/100;source_root.update_tag();bpy.context.view_layer.update();worlds={c['node']:rigid(bpy.data.objects[c['source']].matrix_world)for c in carriers}
 for c in carriers:
  parent=worlds[c['parent']]if c['parent']in worlds else nodes[c['parent']].matrix_world;samples[c['node']].append([list(row)for row in parent.inverted()@worlds[c['node']]])
source_root['tren_retraccion']=0.;source_root.update_tag();bpy.context.view_layer.update()
# Plain exportable materials. Original paint, marks and reference images never enter this scene.
mats={}
def material(n,c,metal=0,rough=.45,alpha=1):
 m=bpy.data.materials.new(n);m.use_nodes=True;p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');p.inputs['Base Color'].default_value=(*c,alpha);p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough;m.diffuse_color=(*c,alpha);m.use_backface_culling=alpha==1
 if alpha<1:m.surface_render_method='DITHERED';p.inputs['Alpha'].default_value=alpha
 mats[n]=m;return m
for n in ['paint_body','paint_wing','paint_wing_tip','paint_tail']:material(n,(.025,.055,.095),.12,.28)
material('alloy',(.32,.36,.39),.75,.35);material('rubber',(.012,.015,.019),0,.75);material('cockpit',(.045,.065,.05),.15,.65);material('glass',(.30,.52,.63),0,.12,.20);material('engine_dark',(.075,.085,.09),.7,.5);material('nav_left',(.65,.012,.01),.1,.25);material('nav_right',(.01,.42,.08),.1,.25)
def specs(name,section,parent,items,budget,painted=False):
 entries=[]
 for item in items:
  src,mat=item if isinstance(item,tuple)else(item,'paint_body')
  if src in bpy.data.objects:entries.append((src,mat))
 assert entries,name
 parts[name]={'section':section,'parent':parent,'sources':entries,'budget':budget,'painted':painted}
 return parts[name]
specs('fuselage_core','core','F4UCorsair',[('Fuselaje | volumen continuo','paint_body'),('Mastil de antena','paint_body'),('R25 | asiento carenado del mastil','paint_body'),('Parabrisas R7 | arco fijo','paint_body'),('Parabrisas R7 | asiento inferior','paint_body'),('Parabrisas R7 | montante de panel','paint_body')],8000,True)
specs('windshield_glass','core','F4UCorsair',[(f'Parabrisas R7 | cristal {s}','glass')for s in ['frontal','derecho','izquierdo']],550)
specs('cockpit_interior','core','F4UCorsair',[(n,'cockpit')for n in ['Asiento R7 | cubeta conformada','Asiento R7 | cojin','Asiento R7 | respaldo acolchado','Tablero R7 | panel principal','Tablero R7 | visera','Cockpit R7 | piso central','Cockpit R7 | consola -1','Cockpit R7 | consola 1']],2200)
specs('canopy_glass','canopy','F4UCorsair',[('Cubierta R7 | acrilico curvo','glass')],1200)
specs('canopy_frame','canopy','F4UCorsair',[(n,'paint_body')for n in ['Cubierta R7 | arco delantero','Cubierta R7 | arco posterior','Cubierta R7 | faldon inferior','Cubierta R7 | faldon inferior.001']],850,True)
specs('wing_center_fixed','wing_center','F4UCorsair',[(n,'paint_wing')for n in ['Ala izquierda | gaviota invertida','Ala derecha | gaviota invertida','Carenado suave de raiz izquierdo','Carenado suave de raiz derecho','R20 | labio y conducto izquierda','R20 | labio y conducto derecha']]+[(f'R22 | techo curvo pozo {s}','cockpit')for s in ['izquierda','derecha']],9500,True)
for s,role in [('izquierda','left'),('derecha','right')]:
 specs('wing_'+role+'_fixed','wing_'+role,'F4UCorsair',[(f'R51 | Panel exterior {s}','paint_wing'),('Luz de posicion R8 | '+s,'nav_'+role)]+([('R26 | cristal curvo luz','glass')]if role=='left'else[]),5200,True)
 specs('aileron_'+role,'wing_'+role,'aileron_'+role+'_hinge',[(f'Aleron R8 | {s}','paint_wing'),(f'R10 | aleta equilibrio {s}','paint_wing')]+([('Compensador R9 | aleron izquierdo','paint_wing')]if role=='left'else[]),1700,True)
 for i in [1,2,3]:specs(f'flap_{role}_{i}','wing_'+role if i==3 else'wing_center',f'flap_{role}_{i}_hinge',[(f'Flap articulado {s} {i}','paint_wing')],1100,True)
specs('stabilizer_fixed','horizontal_tail','F4UCorsair',[(f'Estabilizador {s}','paint_tail')for s in ['izquierdo','derecho']],2500,True)
specs('fin_fixed','vertical_tail','F4UCorsair',[('R12 | deriva fija','paint_tail')],1500,True)
specs('elevator','horizontal_tail','elevator_hinge',[(f'R11 | {n} {s}','paint_tail')for s in ['izquierdo','derecho']for n in ['elevador','compensador']],2200,True)
specs('rudder','vertical_tail','rudder_hinge',[('R12 | timon articulado','paint_tail'),('R12 | compensador de direccion','paint_tail')],2200,True)
specs('cowl','engine','F4UCorsair',[('Capot radial | boca abierta y labio redondeado','paint_body')]+[(f'R14 | compuerta curva {i:02d}','paint_body')for i in range(1,17)],5000,True)
engine_names=[o.name for o in all_source if o.name.startswith('R42 | Culata aluminio ')and int(o.name.rsplit(' ',1)[1])<=9]+['R42 | Reductor frontal escalonado']
specs('engine_face','engine','F4UCorsair',[(n,'engine_dark')for n in engine_names],4000)
specs('exhaust_stacks','engine','F4UCorsair',[(f'R43 | Escape unido {s} {i}','engine_dark')for s in [-1,1]for i in [1,2,3]],1600)
specs('propeller_rotor','propeller','propeller_spin',[(f'Helice F4U-1D | pala {i}','rubber')for i in [1,2,3]]+[('Tapa hidromatica | perfil alargado','alloy'),('Buje | cuerpo fundido continuo','alloy')],5400)
for s,role in [('izquierda','left'),('derecha','right')]:
 specs('gear_strut_'+role,'gear','gear_twist_'+role,[(f'R22 | cuerpo amortiguador {s}','alloy'),(f'R23 | extension cuerpo oleo {s}','alloy')],750)
 specs('gear_lower_'+role,'gear','gear_compression_'+role,[(f'R22 | vastago oleo {s}','alloy'),(f'R22 | munon rueda {s}','alloy'),(f'R23 | fundicion inferior pata {s}','alloy')],750)
 specs('gear_wheel_'+role,'gear','gear_spin_'+role,[(f'R22 | neumatico principal {s}','rubber'),(f'R22 | aro llanta {s}','alloy'),(f'R23 | cara llanta fundida {s}','alloy')],2900)
 for suffix,old in [('front','puerta solidaria a pata'),('inner','puerta pozo interior'),('outer','puerta pozo exterior')]:specs(f'gear_door_{suffix}_mesh_{role}','gear',f'gear_door_{suffix}_{role}',[(f'R22 | {old} {s}','paint_wing')],650,True)
specs('gear_tail_strut','gear','gear_carrier_tail',[('R27 | cuerpo amortiguador','alloy')],250)
specs('gear_tail_fork','gear','gear_compression_tail',[(n,'alloy')for n in ['R27 | vastago oleo','R27 | portahorquilla','R27 | horquilla fundida -1','R27 | horquilla fundida 1']],400)
specs('gear_wheel_tail','gear','gear_spin_tail',[(n,'rubber'if'neumatico'in n else'alloy')for n in ['R27 | neumatico cola','R27 | llanta embutida -1','R27 | llanta embutida 1']],1500)
for s,role in [('izquierda','left'),('derecha','right')]:
 for i in [1,2]:specs(f'gear_door_tail_mesh_{role}_{i}','gear',f'gear_door_tail_{role}_{i}',[(f'R27 | compuerta {s} {i}','paint_body')],300,True)
def mesh_part(name,spec):
 parent=nodes[spec['parent']];inv=parent.matrix_world.inverted();vertices=[];faces=[];face_mats=[];slots=[];raw=[]
 for src,mat in spec['sources']:
  o=bpy.data.objects[src];used[src]=name
  # Reject duplicate use: a moving source must belong to exactly one game part.
  flags=[]
  for mod in o.modifiers:
   if mod.type in {'SUBSURF','BEVEL'}:flags.append((mod,mod.show_viewport));mod.show_viewport=False
  bpy.context.view_layer.update();ev=o.evaluated_get(bpy.context.evaluated_depsgraph_get());me=ev.to_mesh();M=G@ev.matrix_world;vv=[M@v.co for v in me.vertices]
  if src.startswith('Helice F4U-1D |'):vv=[v+R@Vector((-.17,0,0))*.2 for v in vv]
  if src.startswith('Luz de posicion R8 |')or src=='R26 | cristal curvo luz':detail_landmarks[src]=list(sum(vv,Vector())/len(vv))
  if src.startswith('R43 | Escape unido'):
   end=min(v.y for v in vv);rim=[v for v in vv if v.y<end+.002];detail_landmarks[src]=list(sum(rim,Vector())/len(rim))
  if name in ['fuselage_core','wing_center_fixed','wing_left_fixed','wing_right_fixed','stabilizer_fixed','fin_fixed','elevator','rudder','cowl','propeller_rotor']:raw.extend(vv)
  start=len(vertices);vertices.extend(inv@v for v in vv)
  if mat not in slots:slots.append(mat)
  for poly in me.polygons:faces.append(tuple(start+i for i in poly.vertices));face_mats.append(slots.index(mat))
  ev.to_mesh_clear()
  for mod,old in flags:mod.show_viewport=old
 me=bpy.data.meshes.new(name+'_mesh');me.from_pydata(vertices,[],faces);me.update();obj=bpy.data.objects.new(name,me);col.objects.link(obj);obj.parent=parent;obj.matrix_basis=Matrix.Identity(4);obj['openrc_section']=spec['section'];obj['g1_sources']=json.dumps([n for n,m in spec['sources']],ensure_ascii=False)
 for mat in slots:me.materials.append(mats[mat])
 for p,mi in zip(me.polygons,face_mats):p.material_index=mi;p.use_smooth=True
 bm=bmesh.new();bm.from_mesh(me);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-7);bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=1e-8);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free();me.update()
 count=sum(len(p.vertices)-2 for p in me.polygons)
 if refcol is not None and (spec['painted']or name=='propeller_rotor'):
  refobj=bpy.data.objects.new('reference_'+name,me.copy());refcol.objects.link(refobj);refobj.matrix_world=parent.matrix_world.copy()
 if count>spec['budget']:
  mod=obj.modifiers.new('g1 local surface reduction','DECIMATE');mod.ratio=spec['budget']/count;mod.use_collapse_triangulate=True;bpy.context.view_layer.objects.active=obj;obj.select_set(True);bpy.ops.object.modifier_apply(modifier=mod.name);obj.select_set(False)
 obj.data.set_sharp_from_angle(angle=math.radians(50));nodes[name]=obj
 if spec['painted']:skin_names.append(name)
 if raw:raw_reference[name]=[[list(v)for v in raw[::max(1,len(raw)//15000)]],len(raw)]
 print('PART',name,len(obj.data.vertices),sum(len(p.vertices)-2 for p in obj.data.polygons),flush=True)
 return obj
for name,spec in parts.items():mesh_part(name,spec)
if refcol is not None:
 bpy.data.libraries.write(str(Path(opts.reference_cache).resolve()),{refcol})
 for obj in list(refcol.objects):bpy.data.objects.remove(obj,do_unlink=True)
 bpy.data.collections.remove(refcol)
# Distinct tip paint slot is assigned to existing outer-skin faces, never a decal shell.
for name in ['wing_left_fixed','wing_right_fixed']:
 o=nodes[name];o.data.materials.append(mats['paint_wing_tip']);index=len(o.data.materials)-1
 for p in o.data.polygons:
  if p.material_index==0 and abs((o.matrix_world@p.center).x)>1.12:p.material_index=index
# One GearRetract action with one independent slot per rigid carrier.
action=bpy.data.actions.new('GearRetract');action.use_fake_user=True
for spec in carriers:
 o=nodes[spec['node']];o.animation_data_create();slot=action.slots.new(id_type='OBJECT',name=o.name);o.animation_data.action=action;o.animation_data.action_slot=slot;o.rotation_mode='QUATERNION';last=None
 for f,mat in enumerate(samples[o.name]):
  M=Matrix(mat);loc,q,scale=M.decompose()
  if last is not None and q.dot(last)<0:q.negate()
  last=q.copy();o.location=loc;o.rotation_quaternion=q;o.scale=(1,1,1);o.keyframe_insert(data_path='location',frame=f);o.keyframe_insert(data_path='rotation_quaternion',frame=f)
 for layer in action.layers:
  for strip in layer.strips:
   if strip.type=='KEYFRAME':
    try:
     for fc in strip.channelbag(slot).fcurves:
      for key in fc.keyframe_points:key.interpolation='LINEAR'
    except:pass
# Delete source content only from the derived in-memory scene.
game_scene=bpy.data.scenes.new('F4UCorsair_g1');game_scene.collection.children.link(col);bpy.context.window.scene=game_scene
for o in all_source:bpy.data.objects.remove(o,do_unlink=True)
for old in list(bpy.data.scenes):
 if old!=game_scene:bpy.data.scenes.remove(old)
for collection in list(bpy.data.collections):
 if collection!=col:bpy.data.collections.remove(collection)
for act in list(bpy.data.actions):
 if act!=action:bpy.data.actions.remove(act)
for im in list(bpy.data.images):bpy.data.images.remove(im)
for m in list(bpy.data.materials):
 if m.name not in mats:bpy.data.materials.remove(m)
for t in list(bpy.data.texts):bpy.data.texts.remove(t)
bpy.ops.outliner.orphans_purge(do_local_ids=True,do_linked_ids=True,do_recursive=True)
game_scene.unit_settings.system='METRIC';game_scene.unit_settings.scale_length=1;game_scene.frame_start=0;game_scene.frame_end=100;game_scene.frame_set(0);bpy.context.view_layer.update()
# Shared UVMap: disjoint rectangles across all painted parts, smart islands inside each rectangle.
painted=[nodes[n]for n in skin_names];areas=[sum(p.area for p in o.data.polygons)for o in painted];total=sum(areas);ordered=sorted(zip(painted,areas),key=lambda pair:pair[1],reverse=True)
rects=[];x=y=0.;rowh=0.;canvas_w=1.0;scale=.80
for o,area in ordered:
 side=math.sqrt(area/total)*scale;w=max(.025,side*1.5);h=max(.025,side/1.5)
 if x+w>1:x=0;y+=rowh+.008;rowh=0
 rects.append((o,x,y,w,h));x+=w+.008;rowh=max(rowh,h)
height=y+rowh+.008;factor=1/max(1,height);uv_records=[]
for o,x,y,w,h in rects:
 bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
 if not o.data.uv_layers:o.data.uv_layers.new(name='UVMap')
 o.data.uv_layers.active.name='UVMap';bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.025,area_weight=.3,correct_aspect=True,scale_to_bounds=True);bpy.ops.object.mode_set(mode='OBJECT')
 for uv in o.data.uv_layers.active.data:uv.uv=((x+.004+uv.uv.x*(w-.008))*factor,(y+.004+uv.uv.y*(h-.008))*factor)
 o.data.calc_loop_triangles();triangles=[]
 for tri in o.data.loop_triangles:
  poly=o.data.polygons[tri.polygon_index]
  if not o.data.materials[poly.material_index].name.startswith('paint_'):continue
  triangles.append({'uv':[list(o.data.uv_layers.active.data[l].uv)for l in tri.loops],'xyz':[list(o.matrix_world@o.data.vertices[v].co)for v in tri.vertices],'normal':list(o.matrix_world.to_3x3()@tri.normal)})
 uv_records.append({'name':o.name,'rect':[x*factor,y*factor,w*factor,h*factor],'triangles':triangles})
for o in col.objects:
 if o.type=='MESH'and not o.data.uv_layers:o.data.uv_layers.new(name='UVMap')
for a in articulations:a['member_meshes']=[o.name for o in nodes[a['node']].children_recursive if o.type=='MESH']
def worldverts(n):return [nodes[n].matrix_world@v.co for v in nodes[n].data.vertices]
fusel=worldverts('fuselage_core');rotor=worldverts('propeller_rotor');allwv=[v for n in parts for v in worldverts(n)];left=worldverts('wing_left_fixed');right=worldverts('wing_right_fixed');rud=worldverts('rudder')
landmarks={'wingtip_left':list(min(left,key=lambda v:v.x)),'wingtip_right':list(max(right,key=lambda v:v.x)),'spinner_tip':list(max(rotor,key=lambda v:v.y)),'tail_cone_end':list(min(fusel,key=lambda v:v.y)),'rudder_trailing_edge':list(min(rud,key=lambda v:v.y)),'wing_root_leading_edge':[0,0,(min(near,key=lambda v:v.x).z-d0z)*.2],'propeller_hub':list(point((-4.96,0,d0z))),'thrust_axis':[0,1,0],'detail_lenses_and_exhaust_exits':detail_landmarks}
meta={'revision':'g1','master_revision':'R59','master_sha256':master_hash,'blender_version':bpy.app.version_string,'blender_build_hash':bpy.app.build_hash.decode(),'variant':'F4U-1D inspired airframe; preserved three-blade set, shifted 0.17 m forward in the master frame to seat at the current shaft; R49 dome retained','scale_factor':.2,'D0_r59_m':list(D0),'frames':{'blender':{'right':'+X','up':'+Z','nose':'+Y'},'gltf':{'right':'+X','up':'+Y','nose':'-Z'}},'landmarks_blender_m':landmarks,'wheels':wheel_specs,'span_m':max(v.x for v in allwv)-min(v.x for v in allwv),'length_m':max(v.y for v in allwv)-min(v.y for v in allwv),'propeller_diameter_m':2*max(math.hypot(v.x,v.z)for v in rotor),'articulations':articulations,'gear':{'action':'GearRetract','frames':[0,100],'samples':101,'carriers':carriers,'helpers':[n for n in nodes if n.startswith(('gear_compression','gear_spin','gear_steer'))]},'meshes':[],'liveries':[{'id':'midnight','name':'Midnight Blue','description':'Original navy blue, ivory details; default','default':True},{'id':'three_tone','name':'Coastal Three Tone','description':'Original dark blue upper, blue sides and ivory underside','default':False},{'id':'scarlet','name':'Scarlet 308','description':'Original red/ivory racer with fictional number 308; no sponsor logo','default':False}]}
for n in parts:
 o=nodes[n];meta['meshes'].append({'node':n,'section':o['openrc_section'],'triangles':sum(len(p.vertices)-2 for p in o.data.polygons),'surfaces':len(set(p.material_index for p in o.data.polygons))})
meta['triangle_count']=sum(o['triangles']for o in meta['meshes']);meta['surface_count']=sum(o['surfaces']for o in meta['meshes']);meta['material_count']=len(mats);meta['sections']=[{'id':s,'nodes':[o.name for o in col.objects if o.get('openrc_section')==s]}for s in ['core','wing_left','wing_right','wing_center','horizontal_tail','vertical_tail','engine','propeller','gear','canopy']]
mapping=[]
for n in source_names:
 if n in used:mapping.append({'source':n,'status':'simplified','target':used[n],'reason':'evaluated neutral mesh; local reduction, material consolidation and RC/frame conversion'})
 elif n in rig_sources:mapping.append({'source':n,'status':'included','target':rig_sources[n],'reason':'rest frame or sampled rigid transform retained; source drivers/constraints removed'})
 else:mapping.append({'source':n,'status':'excluded','reason':'not in explicit g1 selection: studio/reference/superseded variant/store/internal hardware or subpixel detail'})
(P/'export-map.json').write_text(json.dumps({'master_sha256':master_hash,'objects':mapping},indent=2),encoding='utf8');(P/'metadata.json').write_text(json.dumps(meta,indent=2),encoding='utf8');(P/'source/scripts/uv-layout.json').write_text(json.dumps(uv_records),encoding='utf8');(P/'source/scripts/reference-samples.json').write_text(json.dumps(raw_reference),encoding='utf8');(P/'source/scripts/gear-reference.json').write_text(json.dumps(samples),encoding='utf8')
text=bpy.data.texts.new('READ_ME_g1');text.write('F4U CORSAIR g1 / 1:5\nRoot at D0. Blender +X right, +Y nose, +Z up. All control pivots use local +X.\nRe-export: blender -b source/aircraft_game.blend --python source/scripts/export.py\nGearRetract: frame 0 deployed, 100 retracted. One action with rigid object slots.\nNamed hinges: aileron_left/right_hinge; flap_left/right_1/2/3_hinge; elevator_hinge; rudder_hinge; propeller_spin.\nMaster R59 is not required for re-export.\n')
for o in col.objects:o.select_set(False)
nodes['F4UCorsair'].select_set(True);bpy.context.view_layer.objects.active=nodes['F4UCorsair']
for screen in bpy.data.screens:
 for area in screen.areas:
  if area.type=='VIEW_3D':
   space=area.spaces.active;space.clip_end=100;space.region_3d.view_distance=3.6;space.region_3d.view_location=(0,-.35,-.10);space.region_3d.view_rotation=(Vector((3,4,2.4))-Vector((0,0,0))).to_track_quat('Z','Y');space.shading.type='MATERIAL';space.overlay.show_extras=False
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(P/'source/aircraft_game.blend'));print('G1_DERIVED',meta['triangle_count'],meta['surface_count'],meta['span_m'],flush=True)
