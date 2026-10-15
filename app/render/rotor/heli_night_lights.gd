# HELI-30: a removable RC night-flight presentation kit. No simulation writes.
# Model frame +X right, +Y up, -Z nose. Sources/estimates: HELI-30-NIGHT evidence.
extends Node3D
const AircraftLights=preload("res://render/world/aircraft_lights.gd")
const Exposure=preload("res://render/world/exposure.gd")
const Clock=preload("res://render/shader_clock.gd")
const Relative=preload("res://render/propeller_blur.gd")
const RotorProfile=preload("res://render/rotor/heli_rotor_blur.gd")
const NightRotor=preload("res://render/rotor/heli_night_rotor.gd")
const MODES=["auto","all","nav","off"]
const PORT=Color("#ff0800")
const STARBOARD=Color("#00ff18")
const WARM=Color("#ffd399")
const BELLY=Color("#008cff")
const STRIP_WIDTH_M=.012
const STRIP_RADIANCE=.35
var mode: String="auto"
var active_mode: String="off"
var model: Dictionary={}
var _optics: Array[Dictionary]=[]
var _rotors: Array[Dictionary]=[]
var _landing: SpotLight3D
var _frame_fill: OmniLight3D
var _beacon: MeshInstance3D
# Owned optic materials change gain only with the exact dusk factor.
var _last_optic_factor: float=NAN

static func attach(aircraft: Dictionary) -> Node3D:
 if not aircraft.get("root") is Node3D: return null
 var existing: Node=aircraft.root.get_node_or_null("HelicopterNightKit")
 if existing!=null: return existing
 var kit=load("res://render/rotor/heli_night_lights.gd").new()
 kit.name="HelicopterNightKit"
 kit.model=aircraft
 Exposure.register(); Clock.register()
 kit._build()
 aircraft.root.add_child(kit)
 kit.update_visual(45.0,Exposure.last)
 return kit

static func night_factor(sun_elevation_deg: float) -> float:
 return 1.0-smoothstep(-4.0,3.0,sun_elevation_deg) if is_finite(sun_elevation_deg) else 0.0

static func sun_elevation(snapshot: Dictionary, atmosphere: Dictionary={}) -> float:
 if snapshot.get("solar") is Dictionary: return float(snapshot.solar.get("elevation_deg",45.0))
 return float(atmosphere.get("sun_elevation_deg",45.0))

func set_mode(next: String) -> bool:
 if next not in MODES: return false
 mode=next
 set_meta("mode",mode)
 return true

func cycle_mode() -> String:
 set_mode(MODES[(MODES.find(mode)+1)%MODES.size()])
 return mode

func update_visual(sun_deg: float, exposure: float, telemetry: Dictionary={}, main_phase: float=0.0, tail_phase: float=0.0, armed: bool=false) -> void:
 var factor: float=night_factor(sun_deg) if mode=="auto" else 1.0
 active_mode="off" if mode=="off" or factor<=0.0 else ("nav" if mode=="nav" else "all")
 visible=active_mode!="off"
 var safe_exposure: float=maxf(exposure,.001) if is_finite(exposure) else .6
 if factor!=_last_optic_factor:
  for optic: Dictionary in _optics:
   optic.node.visible=active_mode=="all" or (active_mode=="nav" and optic.nav)
   optic.material.set_shader_parameter("radiance",float(optic.radiance)*factor)
   optic.material.set_shader_parameter("display_cap",float(optic.cap)*factor)
  _last_optic_factor=factor
 else:
  for optic: Dictionary in _optics:
   optic.node.visible=active_mode=="all" or (active_mode=="nav" and optic.nav)
 _beacon.visible=active_mode!="off" and armed
 _landing.visible=active_mode=="all"
 _frame_fill.visible=active_mode=="all"
 # Bounded display contribution across both fixed SDR and adapted night worlds.
 # These caps are visual estimates, not a calibrated lumen/photometry model.
 _landing.light_energy=minf(.018,.12/safe_exposure)*factor
 _frame_fill.light_energy=minf(.08,.18/safe_exposure)*factor
 for binding: Dictionary in _rotors:
  var light: Node3D=binding.node
  light.visible=active_mode=="all"
  light.set_gain(factor)
  light.transform=Relative.relative(model.root,binding.mount)
  var main: bool=binding.main
  var omega: float=float(telemetry.get("omega_rad_s" if main else "tail_omega_rad_s",0.0))
  var sign_value: float=float(model.get("main_visual_spin_sign" if main else "tail_visual_spin_sign",-1.0))
  light.update(sign_value*omega,sign_value*(main_phase if main else tail_phase))

func _build() -> void:
 var root: Node3D=model.root
 var canopy: MeshInstance3D=root.find_child("Carenado",true,false) as MeshInstance3D
 if canopy!=null:
  var triangles: PackedVector3Array=_triangles(root,canopy)
  var lines: Array=_canopy_lines(triangles,[[-1.0,.43],[-1.0,.83],[1.0,.43],[1.0,.83]])
  for side: float in [-1.0,1.0]:
   var line_index: int=0 if side<0 else 2
   var side_name: String="port" if side<0 else "starboard"
   var line: PackedVector3Array=lines[line_index]
   _add_strip("canopy_"+side_name,line,PORT if side<0 else STARBOARD,Vector3(side,0,0))
   _add_strip("canopy_crown_"+side_name,lines[line_index+1],WARM,Vector3(side,.6,0).normalized(),.006)
 _add_strip("skid_port",PackedVector3Array([Vector3(-.096,.01,-.205),Vector3(-.096,.01,.185)]),BELLY,Vector3(-1,-.3,0).normalized())
 _add_strip("skid_starboard",PackedVector3Array([Vector3(.096,.01,-.205),Vector3(.096,.01,.185)]),BELLY,Vector3(1,-.3,0).normalized())
 for side: float in [-1.0,1.0]:
  _add_strip("boom_"+str(int(side)),PackedVector3Array([Vector3(side*.016,.199,.145),Vector3(side*.016,.199,.895)]),WARM,Vector3(side,0,0),.006)
  _add_strip("fin_"+str(int(side)),PackedVector3Array([Vector3(side*.0035,.055,.964),Vector3(side*.0035,.15,.98),Vector3(side*.0035,.25,.938)]),BELLY,Vector3(side,0,0),.006)
 _add_sprite("nav_port",PORT,Vector3(-.086,.17,-.13),.014,true)
 _add_sprite("nav_starboard",STARBOARD,Vector3(.086,.17,-.13),.014,true)
 _add_sprite("nav_tail",Color.WHITE,Vector3(0,.19,.99),.012,true)
 _add_sprite("nose_lamp",WARM,Vector3(0,.109,-.265),.016,false)
 _beacon=_add_sprite("nav_beacon",PORT,Vector3(0,.215,.30),.012,true,Vector4(1.0,.078125,0,1))
 _landing=SpotLight3D.new()
 _landing.name="LandingLamp"
 _landing.position=Vector3(0,.105,-.265)
 _landing.rotation.x=deg_to_rad(-40.0)
 _landing.light_color=Color("#fff0d8")
 _landing.spot_range=12.0
 _landing.spot_angle=32.0
 _landing.spot_angle_attenuation=1.0
 _landing.shadow_enabled=false
 add_child(_landing)
 _frame_fill=OmniLight3D.new()
 _frame_fill.name="FrameLedSpill"
 _frame_fill.position=Vector3(0,.34,-.35)
 _frame_fill.light_color=WARM
 _frame_fill.omni_range=.65
 _frame_fill.shadow_enabled=false
 add_child(_frame_fill)
 for key: String in ["main_rotor_mount","tail_rotor"]:
  var mount: Node3D=model.get(key)
  if mount==null: continue
  var profile: Dictionary=RotorProfile.measured_profile(mount,root)
  if profile.is_empty(): continue
  var main: bool=key=="main_rotor_mount"
  var light: Node3D=NightRotor.attach(mount,float(profile.radius),float(profile.plane_z),Color("#ff6900") if main else WARM,BELLY)
  if light==null: continue
  mount.remove_child(light)
  add_child(light)
  light.name="MainBladeLeds" if main else "TailBladeLeds"
  _rotors.append({node=light,mount=mount,main=main})
 for child: Node in get_children(): child.set_meta("crash_no_bounds",true)
 set_meta("lighting_identity","openrc-heli-night-kit v1")
 set_meta("mode",mode)

func _add_sprite(label: String,color: Color,point: Vector3,size_m: float,nav: bool,flash: Vector4=Vector4(1,0,0,0)) -> MeshInstance3D:
 var node: MeshInstance3D=AircraftLights.sprite(label,color,point,size_m,1.2,flash,3.5,1.4)
 add_child(node)
 _last_optic_factor=NAN
 _optics.append({node=node,material=node.mesh.material,nav=nav,radiance=1.2,cap=.65})
 return node

func _add_strip(label: String,line: PackedVector3Array,color: Color,face: Vector3,width: float=STRIP_WIDTH_M) -> void:
 if line.size()<2: return
 var surface: SurfaceTool=SurfaceTool.new()
 surface.begin(Mesh.PRIMITIVE_TRIANGLES)
 for i: int in line.size()-1:
  var a: Vector3=line[i]
  var b: Vector3=line[i+1]
  var across: Vector3=(b-a).cross(face).normalized()
  for corner: Array in [[a,-1.0],[b,-1.0],[b,1.0],[a,-1.0],[b,1.0],[a,1.0]]:
   surface.set_normal(across); surface.set_uv(Vector2(corner[1],0)); surface.add_vertex(corner[0])
 var material: ShaderMaterial=ShaderMaterial.new()
 material.shader=AircraftLights.STRIP_SHADER
 material.set_shader_parameter("light_color",color)
 material.set_shader_parameter("face_dir",face)
 material.set_shader_parameter("width_m",width)
 material.set_shader_parameter("min_px",2.2)
 material.set_shader_parameter("radiance",STRIP_RADIANCE)
 material.set_shader_parameter("display_cap",.65)
 var mesh: ArrayMesh=surface.commit()
 mesh.surface_set_material(0,material)
 var node: MeshInstance3D=MeshInstance3D.new()
 node.name=label; node.mesh=mesh
 node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 node.extra_cull_margin=.15
 add_child(node)
 _last_optic_factor=NAN
 _optics.append({node=node,material=material,nav=false,radiance=STRIP_RADIANCE,cap=.65})

static func _triangles(root: Node3D,node: MeshInstance3D) -> PackedVector3Array:
 var result: PackedVector3Array=[]
 var transform_value: Transform3D=Relative.relative(root,node)
 for s: int in node.mesh.get_surface_count():
  var arrays: Array=node.mesh.surface_get_arrays(s)
  var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
  var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
  # Transform each source vertex once in native code, then preserve face order.
  var transformed: PackedVector3Array=transform_value*vertices
  if indices.is_empty():
   result.append_array(transformed)
  else:
   for index: int in indices: result.append(transformed[index])
 return result

## Slice actual canopy triangles; no floating outline based on its bounding box.
static func canopy_line(triangles: PackedVector3Array,side: float,height_fraction: float) -> PackedVector3Array:
 return _canopy_lines(triangles,[[side,height_fraction]])[0]

## Each profile is [side, height_fraction]. Share station intersections only within
## this call; preserve float64 profile values and independent packed output lines.
static func _canopy_lines(triangles: PackedVector3Array,profiles: Array) -> Array:
 var lines: Array=[]
 for profile: Array in profiles: lines.append(PackedVector3Array())
 var stations: PackedFloat64Array=[]
 for station: int in 17: stations.append(lerpf(-.355,.045,float(station)/16.0))
 var sections: Array=_canopy_sections(triangles,stations)
 for station: int in stations.size():
  var z: float=stations[station]
  var section: Dictionary=sections[station]
  var segments: Array=section.segments
  var lo: float=section.lo
  var hi: float=section.hi
  if segments.is_empty(): continue
  for index: int in profiles.size():
   var side: float=profiles[index][0]
   var height_fraction: float=profiles[index][1]
   var y: float=lerpf(lo,hi,height_fraction)
   var x: float=-INF
   for segment: PackedVector3Array in segments:
    var a: Vector3=segment[0]
    var b: Vector3=segment[1]
    if (a.y-y)*(b.y-y)>0 or absf(a.y-b.y)<1e-8: continue
    x=maxf(x,side*lerpf(a.x,b.x,(y-a.y)/(b.y-a.y)))
   if is_finite(x):
    var line: PackedVector3Array=lines[index]
    line.append(Vector3(side*(x+.002),y,z))
    lines[index]=line
 return lines


## Stations are the sorted float64 planes generated by _canopy_lines. Visit only
## planes inside each triangle's closed Z interval; retain the original traversal
## for non-finite vertices, for which binary-search bounds would be unreliable.
static func _canopy_sections(triangles: PackedVector3Array,stations: PackedFloat64Array) -> Array:
 var sections: Array=[]
 for z: float in stations: sections.append({segments=[],lo=INF,hi=-INF})
 for i: int in range(0,triangles.size()-2,3):
  var az: float=triangles[i].z
  var bz: float=triangles[i+1].z
  var cz: float=triangles[i+2].z
  var first: int=0
  var stop: int=stations.size()
  if is_finite(az) and is_finite(bz) and is_finite(cz):
   first=stations.bsearch(minf(az,minf(bz,cz)))
   stop=stations.bsearch(maxf(az,maxf(bz,cz)),false)
  for station: int in range(first,stop):
   var z: float=stations[station]
   if (az<z and bz<z and cz<z) or (az>z and bz>z and cz>z): continue
   var section: Dictionary=sections[station]
   var lo: float=section.lo
   var hi: float=section.hi
   var points: PackedVector3Array=[]
   for edge: int in 3:
    var a: Vector3=triangles[i+edge]
    var b: Vector3=triangles[i+(edge+1)%3]
    if (a.z-z)*(b.z-z)>0 or absf(a.z-b.z)<1e-8: continue
    var p: Vector3=a.lerp(b,(z-a.z)/(b.z-a.z))
    points.append(p); lo=minf(lo,p.y); hi=maxf(hi,p.y)
   section.lo=lo; section.hi=hi
   if points.size()>=2: section.segments.append(points)
 return sections
