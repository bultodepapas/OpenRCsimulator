# HELI-16: isotropic spring/damper skid points on the shared float64 terrain.
extends RefCounted
const M = preload("res://physics/math3d.gd")
const Terrain = preload("res://physics/ground_terrain.gd")

static func evaluate(state: PackedFloat64Array, cfg: Dictionary, surfaces: PackedFloat64Array) -> Dictionary:
 var loads: PackedFloat64Array = PackedFloat64Array([0,0,0,0,0,0])
 var max_depth: float = 0.0
 if state.size() < 13: return {ok=false}
 if -state[2] > cfg.reach_m+Terrain.max_height_validated(surfaces): return {ok=true,loads=loads,max_depth_m=0.0}
 var q: PackedFloat64Array = M.q_normalized(state.slice(6,10))
 var inverse: PackedFloat64Array = M.quat(q[0],-q[1],-q[2],-q[3])
 var points: PackedFloat64Array = cfg.points_body_frd_m
 for i: int in range(0,12,3):
  var arm: PackedFloat64Array = points.slice(i,i+3)
  var offset: PackedFloat64Array = M.q_rotate(q,arm)
  var terrain: PackedFloat64Array = Terrain.sample_validated(state[0]+offset[0],state[1]+offset[1],surfaces)
  var norm: float = M.sqrt_(1.0+terrain[1]*terrain[1]+terrain[2]*terrain[2])
  var up: PackedFloat64Array = M.v3(-terrain[1]/norm,-terrain[2]/norm,-1.0/norm)
  var normal: PackedFloat64Array = M.q_rotate(inverse,up)
  var depth: float = (state[2]+offset[2]+terrain[0])/norm
  max_depth=maxf(max_depth,depth)
  if depth <= 0.0: continue
  var point_velocity: PackedFloat64Array = M.cross(state.slice(10,13),arm)
  for axis: int in 3: point_velocity[axis]+=state[3+axis]
  var v_up: float = M.dot(normal,point_velocity)
  var force_n: float = maxf(0.0,cfg.spring_n_m*depth-cfg.damping_n_s_m*v_up)
  var tangent: PackedFloat64Array = M.v3(point_velocity[0]-v_up*normal[0],point_velocity[1]-v_up*normal[1],point_velocity[2]-v_up*normal[2])
  var slip: float = M.norm(tangent)
  var drag: float = cfg.friction*force_n/maxf(cfg.slip_m_s,slip)
  var force: PackedFloat64Array = M.v3(force_n*normal[0]-drag*tangent[0],force_n*normal[1]-drag*tangent[1],force_n*normal[2]-drag*tangent[2])
  var moment: PackedFloat64Array = M.cross(arm,force)
  for axis: int in 3:
   loads[axis]+=force[axis]
   loads[axis+3]+=moment[axis]
 for value: float in loads:
  if not is_finite(value): return {ok=false}
 return {ok=true,loads=loads,max_depth_m=max_depth}

static func strike(state: PackedFloat64Array, main: Dictionary, tail: Dictionary, surfaces: PackedFloat64Array) -> String:
 if -state[2] > main.rotor_radius_m+absf(main.hub_z_m)+.02: return ""
 var q: PackedFloat64Array=state.slice(6,10)
 var main_arm: PackedFloat64Array=M.v3(main.hub_x_m,main.hub_y_m,main.hub_z_m)
 var main_axis: PackedFloat64Array=M.v3(-M.sin_(state[14]),M.sin_(state[15]),-M.cos_(state[14])*M.cos_(state[15]))
 main_axis=M.scale(main_axis,1.0/M.norm(main_axis))
 if _disc_hits(state,q,main_arm,main_axis,main.rotor_radius_m,surfaces): return "main rotor ground strike"
 if _disc_hits(state,q,M.v3(-tail.hub_distance_aft_m,0,-tail.hub_height_above_cg_m),M.v3(0,1,0),tail.tail_rotor_radius_m,surfaces): return "tail rotor ground strike"
 return ""

static func _disc_hits(state: PackedFloat64Array,q: PackedFloat64Array,arm: PackedFloat64Array,axis: PackedFloat64Array,radius: float,surfaces: PackedFloat64Array) -> bool:
 var center: PackedFloat64Array=M.q_rotate(q,arm)
 var normal: PackedFloat64Array=M.q_rotate(q,axis)
 var terrain: PackedFloat64Array=Terrain.sample_validated(state[0]+center[0],state[1]+center[1],surfaces)
 # Instantaneous full-disc envelope over the bounded relief, independent of rendered azimuth.
 var reach: float=radius*M.sqrt_(maxf(0.0,1.0-normal[2]*normal[2]))
 return state[2]+center[2]+reach+maxf(terrain[0],Terrain.max_height_validated(surfaces)) > 0.0
