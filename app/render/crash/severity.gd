extends RefCounted
class_name CrashSeverity

# These provisional cuts separate illustrative cases in report 05; they are not
# airframe strength limits or calibrated predictions.
const CLASS_CUTS_J: Array[float] = [1.0, 8.0, 100.0, 2000.0]
const C4_REFERENCE_J: float = 2000.0
const MAX_ACCUMULATED_ENERGY_J: float = 1.0e12

# Surface multipliers and tangential transfer fractions are presentation
# estimates. They are deliberately bounded to avoid creating energy.
const SURFACE_TRANSFER: Dictionary = {
	"grass": 0.78,
	"mown": 0.82,
	"mown_grass": 0.82,
	"rough": 0.88,
	"dirt": 0.88,
	"runway": 0.95,
	"asphalt": 0.96,
	"concrete": 1.0,
	"water": 0.60,
	"unknown": 0.90,
	# LU-05 provisional transfer classes; estimates, not measured failure thresholds.
	"tree_trunk": 0.80,
	"tree_foliage": 0.12,
	"building": 1.0,
	"vehicle": 0.95,
	"lamp": 0.45,
	"parked_aircraft": 0.30,
}
const TANGENTIAL_TRANSFER: Dictionary = {
	"grass": 0.15,
	"mown": 0.18,
	"rough": 0.24,
	"mown_grass": 0.18,
	"dirt": 0.24,
	"runway": 0.28,
	"asphalt": 0.30,
	"concrete": 0.35,
	"water": 0.05,
	"unknown": 0.20,
	"tree_trunk": 0.25,
	"tree_foliage": 0.08,
	"building": 0.30,
	"vehicle": 0.25,
	"lamp": 0.10,
	"parked_aircraft": 0.15,
}

# Relative exposure multipliers only; these are not failure limits.
const COMPONENT_EXPOSURE: Dictionary = {
	"wingtip": 1.20,
	"wing": 1.00,
	"tail": 1.15,
	"gear": 1.25,
	"propeller": 1.35,
	"canopy": 1.25,
	"fuselage": 0.85,
	"engine": 1.30,
	"unknown": 1.00,
}

static func estimate(
	mass_kg: float,
	normal_velocity_mps: float,
	tangential_velocity_mps: float,
	impact_angle_deg: float,
	surface_id: String,
	component_id: String
) -> Dictionary:
	return _estimate_core(
		mass_kg,
		normal_velocity_mps,
		tangential_velocity_mps,
		impact_angle_deg,
		surface_id,
		component_id,
		false,
		"caller supplied component",
		""
	)


# Convenience path when the caller has a scalar point speed and incidence
# angle (0 degrees is grazing; 90 degrees is normal). The primary estimator
# takes decomposed normal/tangential velocities to avoid deriving them twice.
static func estimate_from_speed_angle(
	mass_kg: float,
	speed_mps: float,
	impact_angle_deg: float,
	surface_id: String,
	component_id: String
) -> Dictionary:
	if not is_finite(speed_mps) or speed_mps < 0.0:
		return _invalid_result("speed must be finite and non-negative", surface_id, component_id, impact_angle_deg)
	if not is_finite(impact_angle_deg) or impact_angle_deg < 0.0 or impact_angle_deg > 90.0:
		return _invalid_result("angle must be between 0 and 90 degrees", surface_id, component_id, 0.0)
	var radians: float = deg_to_rad(impact_angle_deg)
	var normal_velocity_mps: float = speed_mps * sin(radians)
	var tangential_velocity_mps: float = speed_mps * cos(radians)
	return estimate(
		mass_kg,
		normal_velocity_mps,
		tangential_velocity_mps,
		impact_angle_deg,
		surface_id,
		component_id
	)


# Adapt the existing diagnostic snapshot without changing its authority.
# Hull kinematics use the recorded point velocity at the detected tick. Gear
# snapshots currently lack point velocity, so callers may supply CG velocity as
# an explicitly marked proxy for a display estimate.
static func estimate_snapshot(
	snapshot: Object,
	mass_kg: float,
	surface_id: String,
	component_override: String = "",
	cg_velocity_proxy_ned: PackedFloat64Array = PackedFloat64Array()
) -> Dictionary:
	if snapshot == null or not is_instance_valid(snapshot):
		return _invalid_result("snapshot unavailable", surface_id, component_override, 0.0)
	var trigger: String = str(snapshot.get("trigger"))
	var has_kinematics: bool = bool(snapshot.get("has_kinematics"))
	var velocity: PackedFloat64Array = PackedFloat64Array()
	var is_proxy: bool = false
	if has_kinematics:
		var velocity_value: Variant = snapshot.get("velocity_ned")
		if not velocity_value is PackedFloat64Array:
			return _invalid_result("snapshot velocity unavailable", surface_id, component_override, 0.0)
		velocity = velocity_value
	elif cg_velocity_proxy_ned.size() == 3:
		velocity = cg_velocity_proxy_ned
		is_proxy = true
	else:
		return _invalid_result("impact velocity unavailable", surface_id, component_override, 0.0)

	var normal: PackedFloat64Array = PackedFloat64Array()
	var normal_value: Variant = snapshot.get("normal_ned")
	if normal_value is PackedFloat64Array:
		var candidate_normal: PackedFloat64Array = normal_value
		if candidate_normal.size() == 3:
			normal = candidate_normal
		else:
			normal = PackedFloat64Array([0.0, 0.0, -1.0])
	else:
		normal = PackedFloat64Array([0.0, 0.0, -1.0])
	if velocity.size() != 3:
		return _invalid_result("velocity must have three finite components", surface_id, component_override, 0.0)
	var normal_length_squared: float = 0.0
	var velocity_squared: float = 0.0
	var dot: float = 0.0
	for index in range(3):
		if not is_finite(velocity[index]) or not is_finite(normal[index]):
			return _invalid_result("velocity and normal must be finite", surface_id, component_override, 0.0)
		normal_length_squared += normal[index] * normal[index]
		velocity_squared += velocity[index] * velocity[index]
		dot += velocity[index] * normal[index]
	if not is_finite(normal_length_squared) or normal_length_squared <= 0.0 or not is_finite(velocity_squared) or not is_finite(dot):
		return _invalid_result("snapshot kinematics overflowed", surface_id, component_override, 0.0)
	var normal_length: float = sqrt(normal_length_squared)
	var signed_normal_speed: float = -dot / normal_length
	var normal_speed: float = maxf(0.0, signed_normal_speed)
	var tangent_squared: float = 0.0
	if signed_normal_speed >= 0.0:
		tangent_squared = maxf(0.0, velocity_squared - normal_speed * normal_speed)
	var tangent_speed: float = sqrt(tangent_squared)
	var speed: float = sqrt(velocity_squared)
	var angle: float = rad_to_deg(atan2(normal_speed, tangent_speed))

	var component: String = component_override.strip_edges().to_lower()
	var component_is_estimate: bool = false
	var component_basis: String = "caller supplied component"
	if component.is_empty():
		var snapshot_component: String = str(snapshot.get("component_name")).strip_edges().to_lower()
		if trigger == "gear_limit":
			if not snapshot_component.is_empty():
				component = "gear_" + snapshot_component
				component_basis = "snapshot gear name"
			else:
				component = "gear_estimate"
				component_is_estimate = true
				component_basis = "unnamed gear fallback"
		elif not snapshot_component.is_empty():
			component = snapshot_component
			component_basis = "snapshot component label"
		else:
			component = "fuselage_estimate"
			component_is_estimate = true
			component_basis = "fuselage fallback; hull component label unavailable"

	var result: Dictionary = _estimate_core(
		mass_kg,
		normal_speed,
		tangent_speed,
		angle,
		surface_id,
		component,
		component_is_estimate,
		component_basis,
		trigger
	)
	result["speed_mps"] = speed
	result["kinematics_is_proxy"] = is_proxy
	result["sample_time"] = "cg_proxy" if is_proxy else "detected_tick_point"
	return result


# Returns a new cumulative state. Damage values compose monotonically per
# component; estimated event energies sum as an exposure index, not as remaining
# physical crash energy.
static func accumulate_damage(state: Dictionary, impact: Dictionary) -> Dictionary:
	var components: Dictionary = {}
	var raw_components: Variant = state.get("damage_by_component", {})
	if raw_components is Dictionary:
		components = raw_components.duplicate(true)
	var previous_energy: float = _bounded_nonnegative(state.get("accumulated_energy_j", 0.0))
	var previous_severity: float = _unit_value(state.get("severity", 0.0))
	var previous_class: int = clampi(int(state.get("class", 0)), 0, 4)
	var event_count: int = maxi(0, int(state.get("event_count", 0)))
	var output: Dictionary = {
		"valid": true,
		"class": previous_class,
		"severity": previous_severity,
		"accumulated_energy_j": previous_energy,
		"event_count": event_count,
		"damage_by_component": components,
	}
	if not bool(impact.get("valid", false)):
		return output
	var component: String = str(impact.get("component", "unknown")).strip_edges().to_lower()
	if component.is_empty():
		component = "unknown"
	var increment: float = _unit_value(impact.get("component_damage", 0.0))
	var old_component_damage: float = _unit_value(components.get(component, 0.0))
	components[component] = 1.0 - (1.0 - old_component_damage) * (1.0 - increment)
	var event_energy: float = _bounded_nonnegative(impact.get("estimated_energy_j", impact.get("energy_j", 0.0)))
	var accumulated_energy: float = minf(MAX_ACCUMULATED_ENERGY_J, previous_energy + event_energy)
	var event_class: int = clampi(int(impact.get("class", 0)), 0, 4)
	output["class"] = maxi(maxi(previous_class, event_class), _class_for_energy(accumulated_energy))
	output["severity"] = maxf(previous_severity, clampf(accumulated_energy / C4_REFERENCE_J, 0.0, 1.0))
	output["accumulated_energy_j"] = accumulated_energy
	output["event_count"] = event_count + 1
	output["damage_by_component"] = components
	return output


static func _estimate_core(
	mass_kg: float,
	normal_velocity_mps: float,
	tangential_velocity_mps: float,
	impact_angle_deg: float,
	surface_id: String,
	component_id: String,
	component_is_estimate: bool,
	component_basis: String,
	trigger: String
) -> Dictionary:
	var surface: String = surface_id.strip_edges().to_lower()
	if surface.is_empty():
		surface = "unknown"
	var component: String = component_id.strip_edges().to_lower()
	if component.is_empty():
		component = "unknown"
	if not is_finite(mass_kg) or mass_kg <= 0.0:
		return _invalid_result("mass must be finite and positive", surface, component, impact_angle_deg, trigger)
	if not is_finite(normal_velocity_mps) or normal_velocity_mps < 0.0:
		return _invalid_result("normal velocity must be finite and non-negative", surface, component, impact_angle_deg, trigger)
	if not is_finite(tangential_velocity_mps) or tangential_velocity_mps < 0.0:
		return _invalid_result("tangential velocity must be finite and non-negative", surface, component, impact_angle_deg, trigger)
	if not is_finite(impact_angle_deg) or impact_angle_deg < 0.0 or impact_angle_deg > 90.0:
		return _invalid_result("angle must be between 0 and 90 degrees", surface, component, 0.0, trigger)

	var normal_squared: float = normal_velocity_mps * normal_velocity_mps
	var tangential_squared: float = tangential_velocity_mps * tangential_velocity_mps
	var speed_squared: float = normal_squared + tangential_squared
	if not is_finite(speed_squared):
		return _invalid_result("velocity magnitude overflowed", surface, component, impact_angle_deg, trigger)
	if speed_squared > 0.0:
		var kinematic_angle_deg: float = rad_to_deg(atan2(normal_velocity_mps, tangential_velocity_mps))
		if absf(impact_angle_deg - kinematic_angle_deg) > 1.0:
			return _invalid_result("angle disagrees with velocity decomposition", surface, component, impact_angle_deg, trigger)
	var energy: float = 0.5 * mass_kg * speed_squared
	if not is_finite(energy):
		return _invalid_result("kinetic energy overflowed", surface, component, impact_angle_deg, trigger)
	var transfer_factor: float = float(SURFACE_TRANSFER.get(surface, SURFACE_TRANSFER["unknown"]))
	var tangential_factor: float = float(TANGENTIAL_TRANSFER.get(surface, TANGENTIAL_TRANSFER["unknown"]))
	var normal_energy: float = 0.5 * mass_kg * normal_squared
	var tangential_energy: float = 0.5 * mass_kg * tangential_squared * tangential_factor
	var estimated_energy: float = (normal_energy + tangential_energy) * transfer_factor
	if not is_finite(estimated_energy):
		return _invalid_result("surface estimate overflowed", surface, component, impact_angle_deg, trigger)
	var severity: float = clampf(estimated_energy / C4_REFERENCE_J, 0.0, 1.0)
	var component_group: String = _component_group(component)
	var exposure_factor: float = float(COMPONENT_EXPOSURE.get(component_group, COMPONENT_EXPOSURE["unknown"]))
	var component_damage: float = clampf(severity * exposure_factor, 0.0, 1.0)
	var result: Dictionary = {
		"valid": true,
		"class": _class_for_energy(estimated_energy),
		"severity": severity,
		"energy_j": energy,
		"mass_basis": "caller-supplied; participating mass not identified",
		"estimated_energy_j": estimated_energy,
		"component_damage": component_damage,
		"component": component,
		"component_group": component_group,
		"component_is_estimate": component_is_estimate,
		"component_basis": component_basis,
		"surface": surface,
		"impact_angle_deg": impact_angle_deg,
		"speed_mps": sqrt(speed_squared),
		"trigger": trigger,
		"kinematics_is_proxy": false,
		"sample_time": "supplied",
		"error": "",
	}
	return result


static func _component_group(component: String) -> String:
	if component.contains("wingtip") or component.contains("wing_tip"):
		return "wingtip"
	if component.begins_with("gear") or component.contains("_gear"):
		return "gear"
	if component.contains("prop") or component.contains("spinner"):
		return "propeller"
	if component.contains("engine") or component.contains("motor"):
		return "engine"
	if component.contains("canopy") or component.contains("hatch"):
		return "canopy"
	if component.contains("stab") or component.contains("tail") or component.contains("fin"):
		return "tail"
	if component.contains("fuselage") or component.contains("nose") or component.contains("belly"):
		return "fuselage"
	if component.begins_with("wing"):
		return "wing"
	return "unknown"


static func _class_for_energy(energy_j: float) -> int:
	if energy_j <= CLASS_CUTS_J[0]:
		return 0
	if energy_j <= CLASS_CUTS_J[1]:
		return 1
	if energy_j <= CLASS_CUTS_J[2]:
		return 2
	if energy_j <= CLASS_CUTS_J[3]:
		return 3
	return 4


static func _invalid_result(
	reason: String,
	surface_id: String,
	component_id: String,
	angle_deg: float,
	trigger: String = ""
) -> Dictionary:
	var surface: String = surface_id.strip_edges().to_lower()
	if surface.is_empty():
		surface = "unknown"
	var component: String = component_id.strip_edges().to_lower()
	if component.is_empty():
		component = "unknown"
	return {
		"valid": false,
		"class": 0,
		"severity": 0.0,
		"energy_j": 0.0,
		"mass_basis": "unavailable",
		"estimated_energy_j": 0.0,
		"component_damage": 0.0,
		"component": component,
		"component_group": _component_group(component),
		"component_is_estimate": component.ends_with("_estimate"),
		"component_basis": "",
		"surface": surface,
		"impact_angle_deg": angle_deg if is_finite(angle_deg) else 0.0,
		"speed_mps": 0.0,
		"trigger": trigger,
		"kinematics_is_proxy": false,
		"sample_time": "unavailable",
		"error": reason,
	}


static func _bounded_nonnegative(value: Variant) -> float:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return 0.0
	var number: float = float(value)
	if not is_finite(number):
		return 0.0
	return clampf(number, 0.0, MAX_ACCUMULATED_ENERGY_J)


static func _unit_value(value: Variant) -> float:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return 0.0
	var number: float = float(value)
	if not is_finite(number):
		return 0.0
	return clampf(number, 0.0, 1.0)





