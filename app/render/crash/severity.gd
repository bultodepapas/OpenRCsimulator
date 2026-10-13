extends RefCounted
class_name CrashSeverity

# CR-08b: classes grade the struck point's normal energy per kilogram of airplane,
# eps = surface_transfer * 0.5 * m_eff * v_n^2 / (m * durability). Dividing by the
# whole mass keeps the grade independent of aircraft size for similar construction.
# These provisional cuts separate the crash-realism plan's example cases; they are
# not airframe strength limits or calibrated predictions.
const CLASS_CUTS_J_PER_KG: Array[float] = [0.5, 2.5, 25.0, 150.0]
const C4_REFERENCE_J_PER_KG: float = 150.0
# Sliding never breaks sections: friction work during the impact can raise a
# contact to C1 (scrape) at most. Estimate, not a measured abrasion limit.
const ABRASION_SCRAPE_J_PER_KG: float = 1.0
const ABRASION_MAX_CLASS: int = 1
const MAX_ACCUMULATED_ENERGY_J: float = 1.0e12

# Surface multipliers on the normal channel are presentation estimates of
# surface compliance. They are deliberately bounded to avoid creating energy.
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
# Airframe-on-surface sliding friction coefficients for the abrasion channel.
# Estimates (not tyre data, not measured); friction work is mu * normal impulse * slide speed.
const SLIDE_FRICTION: Dictionary = {
	"grass": 0.35,
	"mown": 0.35,
	"rough": 0.45,
	"mown_grass": 0.35,
	"dirt": 0.45,
	"runway": 0.55,
	"asphalt": 0.55,
	"concrete": 0.60,
	"water": 0.05,
	"unknown": 0.45,
	"tree_trunk": 0.50,
	"tree_foliage": 0.20,
	"building": 0.60,
	"vehicle": 0.40,
	"lamp": 0.40,
	"parked_aircraft": 0.30,
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
	component_id: String,
	effective_mass_kg: float = -1.0,
	durability: float = 1.0,
	cg_normal_velocity_mps: float = -1.0
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
		"",
		effective_mass_kg,
		durability,
		cg_normal_velocity_mps
	)


# Convenience path when the caller has a scalar point speed and incidence
# angle (0 degrees is grazing; 90 degrees is normal). The primary estimator
# takes decomposed normal/tangential velocities to avoid deriving them twice.
static func estimate_from_speed_angle(
	mass_kg: float,
	speed_mps: float,
	impact_angle_deg: float,
	surface_id: String,
	component_id: String,
	effective_mass_kg: float = -1.0,
	durability: float = 1.0,
	cg_normal_velocity_mps: float = -1.0
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
		component_id,
		effective_mass_kg,
		durability,
		cg_normal_velocity_mps
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
	cg_velocity_proxy_ned: PackedFloat64Array = PackedFloat64Array(),
	effective_mass_kg: float = -1.0,
	durability: float = 1.0,
	cg_normal_velocity_mps: float = -1.0
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
		trigger,
		effective_mass_kg,
		durability,
		cg_normal_velocity_mps
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
	var previous_specific: float = _bounded_nonnegative(state.get("accumulated_specific_energy_j_per_kg", 0.0))
	var previous_severity: float = _unit_value(state.get("severity", 0.0))
	var previous_class: int = clampi(int(state.get("class", 0)), 0, 4)
	var event_count: int = maxi(0, int(state.get("event_count", 0)))
	var output: Dictionary = {
		"valid": true,
		"class": previous_class,
		"severity": previous_severity,
		"accumulated_energy_j": previous_energy,
		"accumulated_specific_energy_j_per_kg": previous_specific,
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
	var accumulated_specific: float = minf(MAX_ACCUMULATED_ENERGY_J, previous_specific + _bounded_nonnegative(impact.get("specific_energy_j_per_kg", 0.0)))
	var event_class: int = clampi(int(impact.get("class", 0)), 0, 4)
	output["class"] = maxi(maxi(previous_class, event_class), _class_for_specific_energy(accumulated_specific))
	output["severity"] = maxf(previous_severity, clampf(accumulated_specific / C4_REFERENCE_J_PER_KG, 0.0, 1.0))
	output["accumulated_energy_j"] = accumulated_energy
	output["accumulated_specific_energy_j_per_kg"] = accumulated_specific
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
	trigger: String,
	effective_mass_kg: float = -1.0,
	durability: float = 1.0,
	cg_normal_velocity_mps: float = -1.0
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
	if not is_finite(durability) or durability <= 0.0:
		return _invalid_result("durability must be finite and positive", surface, component, impact_angle_deg, trigger)
	if not is_finite(cg_normal_velocity_mps):
		return _invalid_result("CG normal velocity must be finite", surface, component, impact_angle_deg, trigger)
	var participating_mass: float = mass_kg
	var mass_basis: String = "whole aircraft mass; contact point effective mass not supplied"
	if effective_mass_kg >= 0.0 or not is_finite(effective_mass_kg):
		if not is_finite(effective_mass_kg) or effective_mass_kg <= 0.0 or effective_mass_kg > mass_kg * (1.0 + 1.0e-9):
			return _invalid_result("effective mass must be finite, positive and at most the aircraft mass", surface, component, impact_angle_deg, trigger)
		participating_mass = minf(effective_mass_kg, mass_kg)
		mass_basis = "rigid-body effective mass at the contact point"

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
	var friction: float = float(SLIDE_FRICTION.get(surface, SLIDE_FRICTION["unknown"]))
	# Normal channel: the energy the struck part must absorb.
	var normal_energy: float = 0.5 * participating_mass * normal_squared
	var estimated_energy: float = normal_energy * transfer_factor
	# Abrasion channel: friction work during the impact, mu * (m_eff * v_n) * v_t, bounded by
	# the struck point's tangential energy. Sliding after the impact is not simulated.
	var friction_work: float = minf(friction * participating_mass * normal_velocity_mps * tangential_velocity_mps,
		0.5 * participating_mass * tangential_squared)
	var capacity_kg: float = mass_kg * durability
	var specific_energy: float = estimated_energy / capacity_kg
	var abrasion: float = friction_work / capacity_kg
	if not is_finite(estimated_energy) or not is_finite(friction_work) or not is_finite(specific_energy) or not is_finite(abrasion):
		return _invalid_result("surface estimate overflowed", surface, component, impact_angle_deg, trigger)
	# Slapdown: a plastic first contact removes 0.5*m_eff*v_n^2; what the CG still carries into the
	# surface reaches it through a second contact (the nose stops, the belly slams). Upper bound with
	# rates ignored; negative input means "not supplied" and disables the term.
	var slapdown_energy: float = 0.0
	if cg_normal_velocity_mps > 0.0:
		slapdown_energy = maxf(0.0, 0.5 * mass_kg * cg_normal_velocity_mps * cg_normal_velocity_mps - normal_energy) * transfer_factor
	var slapdown: float = slapdown_energy / capacity_kg
	if not is_finite(slapdown):
		return _invalid_result("slapdown estimate overflowed", surface, component, impact_angle_deg, trigger)
	var slapdown_class: int = _class_for_specific_energy(slapdown) if slapdown_energy > 0.0 else 0
	var normal_class: int = _class_for_specific_energy(specific_energy)
	var abrasion_class: int = ABRASION_MAX_CLASS if abrasion >= ABRASION_SCRAPE_J_PER_KG else 0
	var severity: float = clampf(maxf(specific_energy, slapdown) / C4_REFERENCE_J_PER_KG, 0.0, 1.0)
	var component_group: String = _component_group(component)
	var exposure_factor: float = float(COMPONENT_EXPOSURE.get(component_group, COMPONENT_EXPOSURE["unknown"]))
	var component_damage: float = clampf(severity * exposure_factor, 0.0, 1.0)
	var result: Dictionary = {
		"valid": true,
		"class": maxi(maxi(normal_class, abrasion_class), slapdown_class),
		"normal_class": normal_class,
		"abrasion_class": abrasion_class,
		"slapdown_class": slapdown_class,
		"slapdown_energy_j": slapdown_energy,
		"slapdown_j_per_kg": slapdown,
		"severity": severity,
		"energy_j": energy,
		"mass_kg": mass_kg,
		"effective_mass_kg": participating_mass,
		"mass_basis": mass_basis,
		"durability": durability,
		"normal_energy_j": normal_energy,
		"estimated_energy_j": estimated_energy,
		"specific_energy_j_per_kg": specific_energy,
		"friction_work_j": friction_work,
		"abrasion_j_per_kg": abrasion,
		"component_damage": component_damage,
		"component": component,
		"component_group": component_group,
		"component_is_estimate": component_is_estimate,
		"component_basis": component_basis,
		"surface": surface,
		"impact_angle_deg": impact_angle_deg,
		"speed_mps": sqrt(speed_squared),
		"tangential_speed_mps": tangential_velocity_mps,
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


static func _class_for_specific_energy(energy_j_per_kg: float) -> int:
	for index in range(CLASS_CUTS_J_PER_KG.size()):
		if energy_j_per_kg <= CLASS_CUTS_J_PER_KG[index]:
			return index
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
		"normal_class": 0,
		"abrasion_class": 0,
		"slapdown_class": 0,
		"slapdown_energy_j": 0.0,
		"slapdown_j_per_kg": 0.0,
		"severity": 0.0,
		"energy_j": 0.0,
		"mass_kg": 0.0,
		"effective_mass_kg": 0.0,
		"mass_basis": "unavailable",
		"durability": 0.0,
		"normal_energy_j": 0.0,
		"estimated_energy_j": 0.0,
		"specific_energy_j_per_kg": 0.0,
		"friction_work_j": 0.0,
		"abrasion_j_per_kg": 0.0,
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





