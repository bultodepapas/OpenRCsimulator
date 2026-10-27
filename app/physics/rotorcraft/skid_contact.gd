# HELI-16: isotropic spring/damper skid points on the shared float64 terrain.
extends RefCounted
const M = preload("res://physics/math3d.gd")
const Terrain = preload("res://physics/ground_terrain.gd")
const GroundContact = preload("res://physics/ground_contact.gd")
## Unloaded bristles lose their stored strain without applying adhesive force. This 0.2 s
## decay time is a numerical contact-memory proxy, not a measured skid property.
const UNLOADED_BRISTLE_DECAY_TIME_PROXY_S := 0.2
## Reuse the estimated vertical skid coefficients as an isotropic lateral proxy; no independent lateral test exists.
## This bounded relaxation-rate proxy keeps explicit RK stages stable without depending on the selected dt.
const MAX_BRISTLE_RELAXATION_RATE_PROXY_S := 100.0
const ROTORPAD_ROLLING_FACTOR := 0.5
const CONTACT_FORCE_EPSILON_N := 1.0e-8

static func evaluate(state: PackedFloat64Array, cfg: Dictionary, surfaces: PackedFloat64Array,
  diagnostics: bool = false, bristles: PackedFloat64Array = PackedFloat64Array()) -> Dictionary:
 var loads: PackedFloat64Array = PackedFloat64Array([0,0,0,0,0,0])
 var normal_forces: PackedFloat64Array = PackedFloat64Array()
 var compressions: PackedFloat64Array = PackedFloat64Array()
 var bristle_derivative: PackedFloat64Array = PackedFloat64Array()
 var bristle_force_world: PackedFloat64Array = PackedFloat64Array()
 var has_bristles: bool = not bristles.is_empty()
 if has_bristles and bristles.size() != 8: return {ok=false}
 if has_bristles:
  for value: float in bristles:
   if not is_finite(value): return {ok=false}
  bristle_derivative.resize(8)
  if diagnostics: bristle_force_world.resize(8)
 if diagnostics:
  normal_forces.resize(4)
  compressions.resize(4)
 var contact_count: int = 0
 var max_depth: float = 0.0
 if state.size() < 13: return {ok=false}
 if -state[2] > cfg.reach_m+Terrain.max_height_validated(surfaces):
  var no_contact: Dictionary = {ok=true,loads=loads,max_depth_m=0.0}
  if diagnostics:
   no_contact.merge({normal_forces_n=normal_forces,compressions_m=compressions,contact_count=0}, true)
  if has_bristles:
   for index: int in 8: bristle_derivative[index] = -bristles[index] / UNLOADED_BRISTLE_DECAY_TIME_PROXY_S
   no_contact["bristle_derivative"] = bristle_derivative
   if diagnostics: no_contact["bristle_force_world_n"] = bristle_force_world
  return no_contact
 var q: PackedFloat64Array = M.q_normalized(state.slice(6,10))
 var inverse: PackedFloat64Array = M.quat(q[0],-q[1],-q[2],-q[3])
 var points: PackedFloat64Array = cfg.points_body_frd_m
 var point_index: int = 0
 for i: int in range(0,12,3):
  var arm: PackedFloat64Array = points.slice(i,i+3)
  var offset: PackedFloat64Array = M.q_rotate(q,arm)
  var terrain: PackedFloat64Array = Terrain.sample_validated(state[0]+offset[0],state[1]+offset[1],surfaces)
  var norm: float = sqrt(1.0+terrain[1]*terrain[1]+terrain[2]*terrain[2])
  var up: PackedFloat64Array = M.v3(-terrain[1]/norm,-terrain[2]/norm,-1.0/norm)
  var normal: PackedFloat64Array = M.q_rotate(inverse,up)
  var depth: float = (state[2]+offset[2]+terrain[0])/norm
  if diagnostics: compressions[point_index] = maxf(depth, 0.0)
  max_depth=maxf(max_depth,depth)
  if depth <= 0.0:
   if has_bristles:
    _decay_bristle_pair(bristles, bristle_derivative, point_index * 2)
   point_index += 1
   continue
  if diagnostics: contact_count += 1
  var point_velocity: PackedFloat64Array = M.cross(state.slice(10,13),arm)
  for axis: int in 3: point_velocity[axis]+=state[3+axis]
  var v_up: float = M.dot(normal,point_velocity)
  var force_n: float = maxf(0.0,cfg.spring_n_m*depth-cfg.damping_n_s_m*v_up)
  if diagnostics: normal_forces[point_index] = force_n
  var world_north: float = state[0] + offset[0]
  var world_east: float = state[1] + offset[1]
  var flat_rotorpad: bool = has_bristles and _is_flat_rotorpad(surfaces, world_north, world_east, terrain)
  var tangent_force_body := PackedFloat64Array([0.0, 0.0, 0.0])
  if flat_rotorpad and force_n > CONTACT_FORCE_EPSILON_N:
   var surface_index: int = GroundContact.surface_at(surfaces, world_north, world_east)
   var friction_factor: float = surfaces[surface_index + 4]
   var mu: float = float(cfg.friction) * friction_factor
   var stiffness: float = float(cfg.spring_n_m)
   var damping: float = float(cfg.damping_n_s_m)
   var world_velocity: PackedFloat64Array = M.q_rotate(q, point_velocity)
   var speed: float = sqrt(world_velocity[0] * world_velocity[0] + world_velocity[1] * world_velocity[1])
   var capacity: float = mu * force_n
   var z_max: float = capacity / stiffness if stiffness > 0.0 else 0.0
   var z_north: float = bristles[point_index * 2]
   var z_east: float = bristles[point_index * 2 + 1]
   if is_finite(mu) and mu > 0.0 and is_finite(damping) and damping >= 0.0 and z_max > 0.0:
    var raw_north: float = -stiffness * z_north - damping * world_velocity[0]
    var raw_east: float = -stiffness * z_east - damping * world_velocity[1]
    var raw_magnitude: float = sqrt(raw_north * raw_north + raw_east * raw_east)
    var scale: float = minf(1.0, capacity / raw_magnitude) if raw_magnitude > 0.0 else 1.0
    var force_north: float = scale * raw_north
    var force_east: float = scale * raw_east
    var relaxation_rate: float = minf(speed / z_max, MAX_BRISTLE_RELAXATION_RATE_PROXY_S)
    # With alpha = min(1, mu*N/|Fraw|), this yields F·v + d(.5*K*|z|²)/dt
    # = -alpha*C*|v|² - K*beta*|z|² <= 0, including the bounded beta proxy.
    var z_rate_north: float = scale * world_velocity[0] - relaxation_rate * z_north
    var z_rate_east: float = scale * world_velocity[1] - relaxation_rate * z_east
    bristle_derivative[point_index * 2] = z_rate_north
    bristle_derivative[point_index * 2 + 1] = z_rate_east
    if diagnostics:
     bristle_force_world[point_index * 2] = force_north
     bristle_force_world[point_index * 2 + 1] = force_east
    tangent_force_body = M.q_rotate(inverse, M.v3(force_north, force_east, 0.0))
   else:
    _decay_bristle_pair(bristles, bristle_derivative, point_index * 2)
  else:
   if has_bristles:
    _decay_bristle_pair(bristles, bristle_derivative, point_index * 2)
   var tangent: PackedFloat64Array = M.v3(point_velocity[0]-v_up*normal[0],point_velocity[1]-v_up*normal[1],point_velocity[2]-v_up*normal[2])
   var slip: float = M.norm(tangent)
   var drag: float = cfg.friction*force_n/maxf(cfg.slip_m_s,slip)
   tangent_force_body = M.scale(tangent, -drag)
  var force: PackedFloat64Array = M.v3(force_n*normal[0]+tangent_force_body[0],force_n*normal[1]+tangent_force_body[1],force_n*normal[2]+tangent_force_body[2])
  var moment: PackedFloat64Array = M.cross(arm,force)
  for axis: int in 3:
   loads[axis]+=force[axis]
   loads[axis+3]+=moment[axis]
  point_index += 1
 for value: float in loads:
  if not is_finite(value): return {ok=false}
 if has_bristles:
  for value: float in bristle_derivative:
   if not is_finite(value): return {ok=false}
 var result: Dictionary = {ok=true,loads=loads,max_depth_m=max_depth}
 if diagnostics:
  result.merge({normal_forces_n=normal_forces,compressions_m=compressions,contact_count=contact_count}, true)
 if has_bristles:
  result["bristle_derivative"] = bristle_derivative
  if diagnostics: result["bristle_force_world_n"] = bristle_force_world
 return result


static func _is_flat_rotorpad(surfaces: PackedFloat64Array, north: float, east: float,
		terrain: PackedFloat64Array) -> bool:
 if surfaces.is_empty() or terrain.size() != 3:
  return false
 var surface_index: int = GroundContact.surface_at(surfaces, north, east)
 return surface_index >= 0 and surface_index + 5 < surfaces.size() \
  and surfaces[surface_index + 5] == ROTORPAD_ROLLING_FACTOR \
  and absf(terrain[1]) <= 1.0e-12 and absf(terrain[2]) <= 1.0e-12


static func _decay_bristle_pair(bristles: PackedFloat64Array, derivative: PackedFloat64Array,
  index: int) -> void:
 derivative[index] = -bristles[index] / UNLOADED_BRISTLE_DECAY_TIME_PROXY_S
 derivative[index + 1] = -bristles[index + 1] / UNLOADED_BRISTLE_DECAY_TIME_PROXY_S

static func strike(state: PackedFloat64Array, main: Dictionary, tail: Dictionary, surfaces: PackedFloat64Array) -> String:
 if not _strike_inputs_valid(state, main, tail, surfaces): return "invalid rotor strike input"
 var main_reach: float=main.rotor_radius_m+sqrt(main.hub_x_m*main.hub_x_m+main.hub_y_m*main.hub_y_m+main.hub_z_m*main.hub_z_m)
 var tail_reach: float=tail.tail_rotor_radius_m+sqrt(tail.hub_distance_aft_m*tail.hub_distance_aft_m+tail.hub_height_above_cg_m*tail.hub_height_above_cg_m)
 var broadphase_reach: float=maxf(main_reach,tail_reach)+Terrain.max_height_validated(surfaces)+.02
 if -state[2] > broadphase_reach: return ""
 var q: PackedFloat64Array=M.q_normalized(state.slice(6,10))
 var main_arm: PackedFloat64Array=M.v3(main.hub_x_m,main.hub_y_m,main.hub_z_m)
 var tail_arm: PackedFloat64Array=M.v3(-tail.hub_distance_aft_m,0,-tail.hub_height_above_cg_m)
 var main_axis: PackedFloat64Array=M.v3(-M.sin_(state[14]),M.sin_(state[15]),-M.cos_(state[14])*M.cos_(state[15]))
 main_axis=M.scale(main_axis,1.0/M.norm(main_axis))
 if _disc_hits(state,q,main_arm,main_axis,main.rotor_radius_m,surfaces): return "main rotor ground strike"
 if _disc_hits(state,q,tail_arm,M.v3(0,1,0),tail.tail_rotor_radius_m,surfaces): return "tail rotor ground strike"
 return ""

static func _strike_inputs_valid(state: PackedFloat64Array, main: Dictionary, tail: Dictionary,
  surfaces: PackedFloat64Array) -> bool:
 if state.size() < 16 or not Terrain.is_valid_surface_table(surfaces) \
  or not main.has_all(["rotor_radius_m", "hub_x_m", "hub_y_m", "hub_z_m"]) \
  or not tail.has_all(["tail_rotor_radius_m", "hub_distance_aft_m", "hub_height_above_cg_m"]):
  return false
 if not is_finite(state[0]) or not is_finite(state[1]) or not is_finite(state[2]) \
  or not is_finite(state[6]) or not is_finite(state[7]) or not is_finite(state[8]) or not is_finite(state[9]) \
  or not is_finite(state[14]) or not is_finite(state[15]):
  return false
 var qnorm2: float=state[6]*state[6]+state[7]*state[7]+state[8]*state[8]+state[9]*state[9]
 if not is_finite(qnorm2) or qnorm2 <= 1.0e-24:
  return false
 if typeof(main.rotor_radius_m) != TYPE_FLOAT or typeof(main.hub_x_m) != TYPE_FLOAT \
  or typeof(main.hub_y_m) != TYPE_FLOAT or typeof(main.hub_z_m) != TYPE_FLOAT \
  or typeof(tail.tail_rotor_radius_m) != TYPE_FLOAT or typeof(tail.hub_distance_aft_m) != TYPE_FLOAT \
  or typeof(tail.hub_height_above_cg_m) != TYPE_FLOAT:
  return false
 if not is_finite(main.rotor_radius_m) or main.rotor_radius_m <= 0.0 \
  or not is_finite(main.hub_x_m) or not is_finite(main.hub_y_m) or not is_finite(main.hub_z_m) \
  or not is_finite(tail.tail_rotor_radius_m) or tail.tail_rotor_radius_m <= 0.0 \
  or not is_finite(tail.hub_distance_aft_m) or tail.hub_distance_aft_m <= 0.0 \
  or not is_finite(tail.hub_height_above_cg_m) or tail.hub_height_above_cg_m <= 0.0:
  return false
 return true

static func _disc_hits(state: PackedFloat64Array,q: PackedFloat64Array,arm: PackedFloat64Array,axis: PackedFloat64Array,radius: float,surfaces: PackedFloat64Array) -> bool:
 var center: PackedFloat64Array=M.q_rotate(q,arm)
 var normal: PackedFloat64Array=M.q_rotate(q,axis)
 var terrain: PackedFloat64Array=Terrain.sample_validated(state[0]+center[0],state[1]+center[1],surfaces)
 if terrain.size() != 3 or not is_finite(terrain[0]): return true
 # Instantaneous full-disc envelope over the bounded relief, independent of rendered azimuth.
 var reach: float=radius*sqrt(maxf(0.0,1.0-normal[2]*normal[2]))
 return state[2]+center[2]+reach+maxf(terrain[0],Terrain.max_height_validated(surfaces)) > 0.0
