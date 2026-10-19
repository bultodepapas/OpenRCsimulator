extends RefCounted

const VERSION := 2
const LEGACY_VERSION := 1

const LOGICAL_CONTROLS_PROFILE := "logical-controls-v1"
const FINITE_GLOW_PROFILE := "finite-glow-v1"
const ELECTRIC_DRIVE_PROFILE := "electric-drive-v1"
const PROFILES: Array[String] = [
	LOGICAL_CONTROLS_PROFILE,
	FINITE_GLOW_PROFILE,
	ELECTRIC_DRIVE_PROFILE,
]

const Propulsion := preload("res://physics/propulsion.gd")

const ORDINARY_IDS: Array[String] = [
	"roll_jam",
	"pitch_jam",
	"yaw_jam",
	"roll_bias",
	"pitch_bias",
	"roll_slow",
	"throttle_limit",
	"throttle_stuck",
]
const CATASTROPHIC_IDS: Array[String] = ["radio_loss"]
const GLOW_POWER_LOSS_IDS: Array[String] = ["glow_fuel_cut"]
const ELECTRIC_POWER_LOSS_IDS: Array[String] = ["electric_drive_loss"]

const DEFINITIONS := {
	"roll_jam": {
		"label": "Ailerons jammed.",
		"source_label": "Training injection: logical roll-axis actuator hold.",
		"hint": "Keep adequate airspeed. Use gentle rudder inputs if effective; plan a wide approach.",
		"severity": "ordinary",
	},
	"pitch_jam": {
		"label": "Elevator jammed.",
		"source_label": "Training injection: logical pitch-axis actuator hold.",
		"hint": "Manage airspeed and flight path with the remaining controls; avoid abrupt inputs.",
		"severity": "ordinary",
	},
	"yaw_jam": {
		"label": "Rudder jammed.",
		"source_label": "Training injection: logical yaw-axis actuator hold.",
		"hint": "Use bank and pitch control to maintain the flight path and plan a gentle landing.",
		"severity": "ordinary",
	},
	"roll_bias": {
		"label": "Aileron trim shifted.",
		"source_label": "Training injection: roll-axis command bias.",
		"hint": "Apply steady opposite control or trim while preserving enough roll authority to land.",
		"severity": "ordinary",
	},
	"pitch_bias": {
		"label": "Elevator trim shifted.",
		"source_label": "Training injection: pitch-axis command bias.",
		"hint": "Apply steady opposite control or trim and keep a safe airspeed margin.",
		"severity": "ordinary",
	},
	"roll_slow": {
		"label": "Aileron servo is slow.",
		"source_label": "Training injection: reduced logical roll-axis servo rate.",
		"hint": "Use small early corrections and allow extra time for the airplane to respond.",
		"severity": "ordinary",
	},
	"throttle_limit": {
		"label": "Throttle response is limited.",
		"source_label": "Training injection: throttle-demand ceiling.",
		"hint": "Expect less climb margin and leave room for a controlled approach.",
		"severity": "ordinary",
	},
	"throttle_stuck": {
		"label": "Throttle is stuck high.",
		"source_label": "Training injection: elevated throttle-demand hold.",
		"hint": "Use an independent engine stop if the aircraft provides one, then plan a controlled landing.",
		"severity": "ordinary",
	},
	"radio_loss": {
		"label": "Radio link lost.",
		"source_label": "Training injection: sustained receiver link-loss profile.",
		"hint": "Receiver holds the last control commands and sets throttle to idle. Stick inputs have no effect.",
		"severity": "catastrophic",
	},
	"glow_fuel_cut": {
		"label": "Engine combustion stopped.",
		"source_label": "Training injection: finite-glow fuel and combustion cutoff.",
		"hint": "The engine cannot restart during this failure. Keep a safe airspeed and plan a glide landing.",
		"severity": "ordinary",
	},
	"electric_drive_loss": {
		"label": "Electric motor power lost.",
		"source_label": "Training injection: electric motor drive disconnected.",
		"hint": "The motor is disconnected, while the propeller can coast or windmill. Keep a safe airspeed and plan a landing.",
		"severity": "ordinary",
	},
}


## Empty profile preserves the original v1 event set for callers creating legacy plans.
static func failure_ids(include_catastrophic: bool, eligibility_profile: String = "") -> Array[String]:
	var result := ORDINARY_IDS.duplicate()
	if eligibility_profile == FINITE_GLOW_PROFILE:
		result.append_array(GLOW_POWER_LOSS_IDS)
	elif eligibility_profile == ELECTRIC_DRIVE_PROFILE:
		result.append_array(ELECTRIC_POWER_LOSS_IDS)
	elif eligibility_profile != "" and eligibility_profile != LOGICAL_CONTROLS_PROFILE:
		return []
	if include_catastrophic:
		result.append_array(CATASTROPHIC_IDS)
	return result


## Resolve the narrow power-loss adapter from a normalized aircraft model. Unknown,
## legacy and turbine sources retain logical control faults only.
static func profile_for_model(model: Dictionary) -> String:
	var propulsion_value: Variant = model.get("propulsion", {})
	if typeof(propulsion_value) != TYPE_DICTIONARY:
		return LOGICAL_CONTROLS_PROFILE
	var propulsion: Dictionary = propulsion_value
	if Propulsion.is_electric(propulsion) and _electric_drive_is_supported(propulsion):
		return ELECTRIC_DRIVE_PROFILE
	if Propulsion.is_glow(propulsion) and _finite_glow_is_supported(propulsion):
		return FINITE_GLOW_PROFILE
	return LOGICAL_CONTROLS_PROFILE


static func supports_profile(profile: String, model: Dictionary) -> bool:
	return profile in PROFILES and profile_for_model(model) == profile


## UI and CLI callers can show which physical event is eligible and why another
## propulsion family remains control-only.
static func availability(model: Dictionary) -> Dictionary:
	var profile: String = profile_for_model(model)
	var power_loss_ids: Array[String] = []
	if profile == FINITE_GLOW_PROFILE:
		power_loss_ids.append_array(GLOW_POWER_LOSS_IDS)
	elif profile == ELECTRIC_DRIVE_PROFILE:
		power_loss_ids.append_array(ELECTRIC_POWER_LOSS_IDS)
	var reason := ""
	if power_loss_ids.is_empty():
		var propulsion_value: Variant = model.get("propulsion", {})
		var kind: String = "unknown"
		if typeof(propulsion_value) == TYPE_DICTIONARY:
			kind = Propulsion.source_kind(propulsion_value)
		if kind == "turbine":
			reason = "Turbine flameout and rotor rundown are not modeled."
		elif kind == "electric_prop":
			reason = "This electric installation has no supported continuous motor and rotor state."
		elif kind == "glow_prop":
			reason = "Finite-glow lifecycle data is unavailable; the legacy RPM model has no qualified shutdown law."
		else:
			reason = "This propulsion family has no qualified engine shutdown law."
	var ids: Array[String] = ORDINARY_IDS.duplicate()
	ids.append_array(power_loss_ids)
	ids.append_array(CATASTROPHIC_IDS)
	return {
		"eligibility_profile": profile,
		"eligible_ids": ids,
		"power_loss_ids": power_loss_ids,
		"power_loss_supported": not power_loss_ids.is_empty(),
		"exclusion_reason": reason,
	}


static func _finite_glow_is_supported(propulsion: Dictionary) -> bool:
	var install_value: Variant = propulsion.get("glow", {})
	if typeof(install_value) != TYPE_DICTIONARY:
		return false
	var install: Dictionary = install_value
	var profile_value: Variant = install.get("profile", {})
	var settings_value: Variant = install.get("settings", {})
	if typeof(profile_value) != TYPE_DICTIONARY or typeof(settings_value) != TYPE_DICTIONARY:
		return false
	var profile: Dictionary = profile_value
	var settings: Dictionary = settings_value
	var family: String = str(profile.get("family", ""))
	var fuel: Variant = install.get("initial_fuel_kg", null)
	var inertia: Variant = propulsion.get("rotor_inertia", null)
	return family in ["glow_2t", "glow_4t"] and settings.has("fuel_transport_time_constant_s") \
		and typeof(fuel) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(fuel)) and float(fuel) > 0.0 \
		and typeof(inertia) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(inertia)) and float(inertia) > 0.0


static func _electric_drive_is_supported(propulsion: Dictionary) -> bool:
	var motor_value: Variant = propulsion.get("motor", {})
	var battery_value: Variant = propulsion.get("battery", {})
	var esc_value: Variant = propulsion.get("esc", {})
	if typeof(motor_value) != TYPE_DICTIONARY or typeof(battery_value) != TYPE_DICTIONARY \
		or typeof(esc_value) != TYPE_DICTIONARY:
		return false
	var motor: Dictionary = motor_value
	var battery: Dictionary = battery_value
	var esc: Dictionary = esc_value
	var inertia: Variant = propulsion.get("rotor_inertia", null)
	return motor.has("kv_rpm_per_volt") and motor.has("resistance_ohm") \
		and motor.has("no_load_current_a") and battery.get("kind", "") in ["fixed_voltage", "ocv_resistance", "pack_ecm"] \
		and esc.get("kind", "") == "ideal_motoring" and esc.get("command_mapping", "") == "identity" \
		and typeof(inertia) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(inertia)) and float(inertia) > 0.0


static func definition(failure_id: String) -> Dictionary:
	if not DEFINITIONS.has(failure_id):
		return {}
	return DEFINITIONS[failure_id].duplicate(true)
