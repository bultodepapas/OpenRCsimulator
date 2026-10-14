# HELI-16: strict v2 rotorcraft reader. Invalid quantities or module contexts cannot fly.
extends RefCounted
const Main = preload("res://physics/rotorcraft/main_rotor.gd")
const Tail = preload("res://physics/rotorcraft/tail_rotor.gd")
const Airframe = preload("res://physics/rotorcraft/airframe.gd")
const Flight = preload("res://physics/rotorcraft/flight_dynamics.gd")
const M = preload("res://physics/math3d.gd")
const HX700_ID: String = "hx700-electric-3d-experimental"
const HX700_CAPABILITIES: Array = [
 "main_rotor", "tail_rotor", "governor", "fbl_body_rate", "signed_collective", "skids",
]
const HX700_ACCEPTANCE_BLOCKERS: Array = [
 "identified_fbl_rotor_dynamics", "achieved_servo_states", "freewheel_and_power_off_energy",
 "signed_inversion_envelope", "ground_start_lifecycle", "HX700_flight_response_validation",
]
const UNITS: Dictionary = {
 "rho_kg_m3":"kg/m3", "rotor_radius_m":"m", "main_rotor_radius_m":"m", "tail_rotor_radius_m":"m", "blade_chord_m":"m",
 "rotor_blade_count":"1", "blade_lift_curve_slope_per_rad":"1/rad", "blade_section_cd0":"1", "thrust_coefficient_max":"1",
 "blade_flapping_inertia_kg_m2":"kg*m2", "gamma_flybar":"1", "flapback_k_mu":"1", "omega_nominal_rad_s":"rad/s",
 "cyclic_longitudinal_gain_nominal_rad_per_rad":"1", "cyclic_lateral_gain_nominal_rad_per_rad":"1", "hub_spring_stiffness_nm_per_rad":"N*m/rad",
 "hub_position_body_frd_m":"m", "rotation_sense":"1", "tail_to_main_speed_ratio":"1", "hub_distance_aft_m":"m", "hub_height_above_cg_m":"m",
 "vertical_fin_area_m2":"m2", "trim_collective_rad":"rad", "wake_efficiency":"1", "fuselage_drag_area_body_m2":"m2", "fuselage_cp_body_frd_m":"m",
 "vertical_fin_lift_curve_slope_per_rad":"1/rad", "vertical_fin_cp_body_frd_m":"m", "horizontal_tail_area_m2":"m2",
 "horizontal_tail_lift_curve_slope_per_rad":"1/rad", "horizontal_tail_cp_body_frd_m":"m", "mass_kg":"kg", "inertia_kg_m2":"kg*m2",
 "gravity_m_s2":"m/s2", "speed_ratio":"1", "spin_axis_body_frd":"1", "engine_torque_max_nm":"N*m", "engine_power_max_w":"W",
 "engine_speed_ratio_to_main":"1", "gear_efficiency":"1", "governor_target_main_rad_s":"rad/s", "governor_gain_nm_per_rad_s":"N*m*s/rad",
 "shaft_loss_torque_nm":"N*m", "shaft_viscous_loss_nm_per_rad_s":"N*m*s/rad", "tail_collective_trim_rad":"rad",
 "tail_collective_min_rad":"rad", "tail_collective_max_rad":"rad", "yaw_control_sign":"1", "yaw_deadzone":"1", "yaw_max_rate_rad_s":"rad/s",
 "yaw_heading_gain_per_s":"1/s", "yaw_rate_kp_rad_per_rad_s":"s", "yaw_rate_ki_rad_per_rad":"1", "yaw_integrator_limit_rad":"rad",
 "trainer_max_tilt_rad":"rad", "trainer_roll_attitude_gain_per_s":"1/s", "trainer_pitch_attitude_gain_per_s":"1/s",
 "trainer_roll_rate_limit_rad_s":"rad/s", "trainer_pitch_rate_limit_rad_s":"rad/s", "trainer_roll_cyclic_gain_rad_per_rad_s":"s", "trainer_pitch_cyclic_gain_rad_per_rad_s":"s",
 "body_rate_max_rad_s":"rad/s", "body_rate_roll_cyclic_gain_rad_per_rad_s":"s", "body_rate_pitch_cyclic_gain_rad_per_rad_s":"s",
 "collective_rad_per_unit":"rad", "longitudinal_rad_per_unit":"rad", "lateral_rad_per_unit":"rad", "collective_min_rad":"rad", "collective_max_rad":"rad", "cyclic_max_rad":"rad",
 "pitch":"1", "throttle":"1", "flow_floor_m_s":"m/s", "fin_tail_wake_fraction":"1", "height_over_radius":"1", "inflow_loss":"1", "inflow_instability":"1",
 "points_body_frd_m":"m", "spring_n_m":"N/m", "damping_n_s_m":"N*s/m", "friction":"1", "slip_m_s":"m/s",
}

static func load_file(path: String, density: float = 1.225) -> Dictionary:
 var bytes: PackedByteArray=FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
 var raw: Variant=JSON.parse_string(bytes.get_string_from_utf8()) if not bytes.is_empty() else null
 var loaded: Dictionary=validate(raw,density)
 if loaded.ok:
  var hash: HashingContext=HashingContext.new()
  hash.start(HashingContext.HASH_SHA256)
  hash.update(bytes)
  loaded.input_identity={format="openrc-aircraft v2",sha256=hash.finish().hex_encode()}
 return loaded

static func validate(raw: Variant, density: float = 1.225) -> Dictionary:
 var errors: PackedStringArray = PackedStringArray()
 if not raw is Dictionary or raw.get("format") != "openrc-aircraft v2" or raw.get("vehicle") != "rotorcraft":
  return {ok=false, errors=["expected openrc-aircraft v2 with vehicle rotorcraft"]}
 var profile_id: String = str(raw.get("id", ""))
 var expected_capabilities: Array
 if profile_id == "xcell-60-research":
  expected_capabilities = ["main_rotor", "tail_rotor", "governor", "trainer", "skids"]
 elif profile_id == HX700_ID:
  expected_capabilities = HX700_CAPABILITIES
  if raw.get("release_state") != "laboratory_only":
   return {ok=false, errors=["HX-700 3D profile cannot claim an accepted release state"]}
 else:
  return {ok=false, errors=["unsupported rotorcraft identity"]}
 if raw.get("capabilities") != expected_capabilities:
  return {ok=false, errors=["unsupported identity or capabilities"]}
 var expected: Array=["format","vehicle","id","name","capabilities","qualification","main_rotor","tail_rotor","airframe","body","gravity_m_s2","shaft_elements","drive","electronics","integration","skids"]
 if profile_id == HX700_ID:
  expected.append("release_state")
 if raw.size()!=expected.size() or not raw.has_all(expected) or not raw.name is String or not raw.qualification is String or raw.qualification.is_empty():
  return {ok=false,errors=["malformed rotorcraft header or unknown top-level field"]}
 var parts: Dictionary = {}
 for key: String in ["main_rotor", "tail_rotor", "airframe", "body", "drive", "electronics", "integration", "skids"]:
  parts[key] = _unpack(raw.get(key), key, errors)
 var shafts: Array = []
 if not raw.get("shaft_elements") is Array:
  errors.append("shaft_elements missing")
 else:
  for item: Variant in raw.shaft_elements:
   shafts.append(_unpack(item, "shaft_elements", errors))
 var gravity: Variant = _quantity(raw.get("gravity_m_s2"), "gravity_m_s2", errors)
 if not is_finite(density) or density <= 0.0: errors.append("invalid atmosphere density")
 if not errors.is_empty(): return {ok=false,errors=errors}
 for key: String in ["main_rotor", "tail_rotor", "airframe"]:
  if not parts[key].get("rho_kg_m3") is float or parts[key].rho_kg_m3<=0.0:
   return {ok=false,errors=["nominal air density must be positive in "+key]}
  parts[key].rho_kg_m3 = density
 var main: Dictionary = Main.prepare(parts.main_rotor)
 var tail: Dictionary = Tail.prepare(parts.tail_rotor)
 var airframe: Dictionary = Airframe.prepare(parts.airframe)
 if not main.ok or not tail.ok or not airframe.ok:
  return {ok=false,errors=["invalid rotor or airframe module"]}
 if shafts.size()!=2 or shafts[0].get("speed_ratio")!=1.0 or shafts[1].get("speed_ratio")!=tail.model.tail_to_main_speed_ratio or shafts[0].get("spin_axis_body_frd")!=PackedFloat64Array([0,0,main.model.rotation_sense]) or shafts[1].get("spin_axis_body_frd")!=PackedFloat64Array([0,tail.model.rotation_sense,0]):
  return {ok=false,errors=["shaft gearing and signed axes must match the main/tail aerodynamic modules"]}
 var cfg: Dictionary = parts.integration.duplicate()
 cfg.merge(parts.body)
 cfg["inertia_body_kg_m2"]=cfg.inertia_kg_m2
 cfg.erase("inertia_kg_m2")
 cfg.merge({"gravity_m_s2":gravity, "main_model":main.model, "tail_model":tail.model, "airframe_model":airframe.model,
  "shaft_elements":shafts, "drive":parts.drive, "electronics":parts.electronics})
 var prepared: Dictionary = Flight.prepare(cfg)
 if not prepared.ok: return {ok=false,errors=["invalid coupled flight configuration: "+str(prepared.get("message","unknown module failure"))]}
 if profile_id == "xcell-60-research" \
   and prepared.context.electronics_model.get("law") != "openrc-four-stick-electronics-v1":
  return {ok=false,errors=["X-Cell trainer identity cannot use an alternate controller law"]}
 if profile_id == HX700_ID and not _hx700_identity_is_consistent(raw, prepared.context):
  return {ok=false,errors=["HX-700 data mixes an unsupported identity, source, ratio or controller law"]}
 var skids: Dictionary = parts.skids
 if skids.size() != 5 or not skids.get("points_body_frd_m") is PackedFloat64Array or skids.points_body_frd_m.size() != 12:
  return {ok=false,errors=["skids require four FRD contact points"]}
 for key: String in ["spring_n_m", "damping_n_s_m", "friction", "slip_m_s"]:
  if not skids.has(key) or not skids[key] is float or skids[key] <= 0.0: return {ok=false,errors=["invalid skid parameter: "+key]}
 var reach: float = 0.0
 for i: int in range(0,12,3):
  var p: PackedFloat64Array=skids.points_body_frd_m.slice(i,i+3)
  reach=maxf(reach,M.norm(p))
 if not is_finite(reach) or reach<=0.0 or M.sqrt_(4.0*skids.spring_n_m/cfg.mass_kg)/Engine.physics_ticks_per_second>.5 or 4.0*skids.damping_n_s_m/(cfg.mass_kg*Engine.physics_ticks_per_second)>1.0:
  return {ok=false,errors=["skid geometry or fixed-step stiffness exceeds the supported envelope"]}
 skids.reach_m=reach
 skids.make_read_only()
 var loaded: Dictionary = {ok=true,errors=errors,id=raw.id,context=prepared.context,skids=skids,
  qualification=raw.qualification,raw=raw.duplicate(true),
  controller_law=prepared.context.electronics_model.law}
 if profile_id == HX700_ID:
  loaded["release_gate"] = {
   "state": "laboratory_only",
   "flight_qualified": false,
   "missing_capabilities": HX700_ACCEPTANCE_BLOCKERS.duplicate(),
  }
 return loaded

static func _unpack(raw: Variant, path: String, errors: PackedStringArray) -> Dictionary:
 var out: Dictionary = {}
 if not raw is Dictionary:
  errors.append(path+": missing object")
  return out
 for key: String in raw:
  if UNITS.has(key): out[key] = _quantity(raw[key], key, errors)
  elif key == "controller_law": out[key] = raw[key]
  elif key in ["linkage", "curves_by_mode", "normal", "idle_up", "3d"]: out[key] = _unpack(raw[key], path+"."+key, errors)
  else: errors.append(path+"."+key+": unknown field")
 return out

static func _quantity(node: Variant, key: String, errors: PackedStringArray) -> Variant:
 if not node is Dictionary or node.size() != 4 or not node.has_all(["value", "unit", "kind", "source"]):
  errors.append(key+": requires value, unit, kind, source")
  return null
 if node.unit != UNITS[key] or node.kind not in ["manual", "measured", "borrowed", "derived", "estimated"] or not node.source is String or node.source.strip_edges().is_empty():
  errors.append(key+": invalid units or evidence")
  return null
 if node.value is Array:
  var vector: PackedFloat64Array = PackedFloat64Array()
  for value: Variant in node.value:
   if not _number(value): errors.append(key+": nonfinite vector"); return null
   vector.append(float(value))
  return vector
 if not _number(node.value): errors.append(key+": nonfinite number"); return null
 return float(node.value)

static func _number(value: Variant) -> bool:
 return typeof(value) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(value))

static func _hx700_identity_is_consistent(raw: Dictionary, context: Dictionary) -> bool:
 if raw.get("release_state") != "laboratory_only" or raw.get("capabilities") != HX700_CAPABILITIES:
  return false
 if context.electronics_model.get("law") != "openrc-fbl-body-rate-electronics-v1":
  return false
 if absf(float(context.mass_kg) - 5.2) > 1.0e-9 \
   or absf(float(context.main_model.omega_nominal_rad_s) - 219.9114857512855) > 1.0e-9 \
   or absf(float(context.tail_model.tail_to_main_speed_ratio) - 4.92307710647583) > 1.0e-9 \
   or absf(float(context.drive_model.engine_speed_ratio_to_main) - 9.636364) > 1.0e-9:
  return false
 if raw.body.mass_kg.kind != "estimated" or not str(raw.body.mass_kg.source).contains("HELI-25b") \
   or raw.main_rotor.omega_nominal_rad_s.kind != "derived" \
   or not str(raw.main_rotor.omega_nominal_rad_s.source).contains("2100 rpm") \
   or raw.tail_rotor.tail_to_main_speed_ratio.kind != "estimated" \
   or not str(raw.tail_rotor.tail_to_main_speed_ratio.source).contains("HELI-25b"):
  return false
 return _has_independent_hx700_sources(raw)

static func _has_independent_hx700_sources(node: Variant) -> bool:
 if node is Dictionary:
  if node.size() == 4 and node.has_all(["value", "unit", "kind", "source"]):
   var source: String = str(node.source).to_lower()
   return node.kind not in ["borrowed", "measured"] and not source.contains("xcell") \
    and not source.contains("x-cell") and not source.contains("gavrilets")
  for value: Variant in node.values():
   if not _has_independent_hx700_sources(value):
    return false
 elif node is Array:
  for value: Variant in node:
   if not _has_independent_hx700_sources(value):
    return false
 return true
