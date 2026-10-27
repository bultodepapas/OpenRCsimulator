extends RefCounted

const VERSION := 3
const PROFILE_VERSION := 2
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
## v1/v2 lists above are frozen: they define historical seed mappings. v3 appends (EM-30).
const ADDED_ORDINARY_IDS_V3: Array[String] = [
	"pitch_slow",
	"yaw_slow",
	"yaw_bias",
	"throttle_stuck_low",
	"roll_travel_limit",
	"pitch_travel_limit",
	"yaw_travel_limit",
]
const KNOWN_IDS: Array[String] = [
	"roll_jam", "pitch_jam", "yaw_jam", "roll_bias", "pitch_bias", "roll_slow",
	"throttle_limit", "throttle_stuck",
	"pitch_slow", "yaw_slow", "yaw_bias", "throttle_stuck_low",
	"roll_travel_limit", "pitch_travel_limit", "yaw_travel_limit",
	"glow_fuel_cut", "electric_drive_loss", "radio_loss",
]
## Rudder-axis types; an elevon aircraft has no rudder, so they would be null events there.
const YAW_AXIS_IDS: Array[String] = ["yaw_jam", "yaw_bias", "yaw_slow", "yaw_travel_limit"]
## Player-facing groups and order for the per-type checkboxes.
const GROUPS := [
	# By axis, so rows read coherently in the one- and two-column layouts.
	{"id": "controls", "title": "Control surfaces and servos", "ids": [
		"roll_jam", "roll_bias", "roll_slow", "roll_travel_limit",
		"pitch_jam", "pitch_bias", "pitch_slow", "pitch_travel_limit",
		"yaw_jam", "yaw_bias", "yaw_slow", "yaw_travel_limit",
	]},
	{"id": "power", "title": "Engine and throttle", "ids": [
		"throttle_stuck", "throttle_stuck_low", "throttle_limit", "glow_fuel_cut", "electric_drive_loss",
	]},
	{"id": "radio", "title": "Radio link", "ids": ["radio_loss"]},
]

const DEFINITIONS := {
	"roll_jam": {
		"name": "Aileron jam",
		"label": "Ailerons jammed.",
		"source_label": "Training injection: logical roll-axis actuator hold.",
		"hint": "Keep adequate airspeed. Use gentle rudder inputs if effective; plan a wide approach.",
		"severity": "ordinary",
		"scaled_by_severity": false,
	},
	"pitch_jam": {
		"name": "Elevator jam",
		"label": "Elevator jammed.",
		"source_label": "Training injection: logical pitch-axis actuator hold.",
		"hint": "Manage airspeed and flight path with the remaining controls; avoid abrupt inputs.",
		"severity": "ordinary",
		"scaled_by_severity": false,
	},
	"yaw_jam": {
		"name": "Rudder jam",
		"label": "Rudder jammed.",
		"source_label": "Training injection: logical yaw-axis actuator hold.",
		"hint": "Use bank and pitch control to maintain the flight path and plan a gentle landing.",
		"severity": "ordinary",
		"scaled_by_severity": false,
	},
	"roll_bias": {
		"name": "Aileron trim shift",
		"label": "Aileron trim shifted.",
		"source_label": "Training injection: roll-axis command bias.",
		"hint": "Apply steady opposite control or trim while preserving enough roll authority to land.",
		"severity": "ordinary",
		"scaled_by_severity": true,
	},
	"pitch_bias": {
		"name": "Elevator trim shift",
		"label": "Elevator trim shifted.",
		"source_label": "Training injection: pitch-axis command bias.",
		"hint": "Apply steady opposite control or trim and keep a safe airspeed margin.",
		"severity": "ordinary",
		"scaled_by_severity": true,
	},
	"roll_slow": {
		"name": "Slow aileron servo",
		"label": "Aileron servo is slow.",
		"source_label": "Training injection: reduced logical roll-axis servo rate.",
		"hint": "Use small early corrections and allow extra time for the airplane to respond.",
		"severity": "ordinary",
		"scaled_by_severity": true,
	},
	"throttle_limit": {
		"name": "Limited throttle",
		"label": "Throttle response is limited.",
		"source_label": "Training injection: throttle-demand ceiling.",
		"hint": "Expect less climb margin and leave room for a controlled approach.",
		"severity": "ordinary",
		"scaled_by_severity": true,
	},
	"throttle_stuck": {
		"name": "Throttle stuck high",
		"label": "Throttle is stuck high.",
		"source_label": "Training injection: elevated throttle-demand hold.",
		"hint": "Use an independent engine stop if the aircraft provides one, then plan a controlled landing.",
		"severity": "ordinary",
		"scaled_by_severity": true,
	},
	"pitch_slow": {
		"name": "Slow elevator servo",
		"label": "Elevator servo is slow.",
		"source_label": "Training injection: reduced logical pitch-axis servo rate.",
		"hint": "Make small early pitch corrections and start the flare sooner.",
		"severity": "ordinary",
		"scaled_by_severity": true,
	},
	"yaw_slow": {
		"name": "Slow rudder servo",
		"label": "Rudder servo is slow.",
		"source_label": "Training injection: reduced logical yaw-axis servo rate.",
		"hint": "Lead rudder corrections early, especially during takeoff and landing.",
		"severity": "ordinary",
		"scaled_by_severity": true,
	},
	"yaw_bias": {
		"name": "Rudder trim shift",
		"label": "Rudder trim shifted.",
		"source_label": "Training injection: yaw-axis command bias.",
		"hint": "Hold steady opposite rudder or trim; expect the airplane to skid in turns.",
		"severity": "ordinary",
		"scaled_by_severity": true,
	},
	"throttle_stuck_low": {
		"name": "Throttle stuck low",
		"label": "Throttle is stuck low.",
		"source_label": "Training injection: reduced throttle-demand hold.",
		"hint": "Keep a safe airspeed, choose a landing area within gliding range and avoid a go-around.",
		"severity": "ordinary",
		"scaled_by_severity": true,
	},
	"roll_travel_limit": {
		"name": "Restricted aileron travel",
		"label": "Aileron travel is restricted.",
		"source_label": "Training injection: restricted logical roll-axis travel.",
		"hint": "Expect slower rolls; avoid steep banks near the ground and plan wider turns.",
		"severity": "ordinary",
		"scaled_by_severity": true,
	},
	"pitch_travel_limit": {
		"name": "Restricted elevator travel",
		"label": "Elevator travel is restricted.",
		"source_label": "Training injection: restricted logical pitch-axis travel.",
		"hint": "Keep extra airspeed; the flare and stall recovery have less authority.",
		"severity": "ordinary",
		"scaled_by_severity": true,
	},
	"yaw_travel_limit": {
		"name": "Restricted rudder travel",
		"label": "Rudder travel is restricted.",
		"source_label": "Training injection: restricted logical yaw-axis travel.",
		"hint": "Correct crosswind early; rudder authority is reduced during takeoff and landing.",
		"severity": "ordinary",
		"scaled_by_severity": true,
	},
	"radio_loss": {
		"name": "Radio link loss",
		"label": "Radio link lost.",
		"source_label": "Training injection: sustained receiver link-loss profile.",
		"hint": "Receiver holds the last control commands and sets throttle to idle. Stick inputs have no effect.",
		"severity": "catastrophic",
		"scaled_by_severity": false,
	},
	"glow_fuel_cut": {
		"name": "Engine stops (glow)",
		"label": "Engine combustion stopped.",
		"source_label": "Training injection: finite-glow fuel and combustion cutoff.",
		"hint": "The engine cannot restart during this failure. Keep a safe airspeed and plan a glide landing.",
		"severity": "ordinary",
		"scaled_by_severity": false,
	},
	"electric_drive_loss": {
		"name": "Motor power loss (electric)",
		"label": "Electric motor power lost.",
		"source_label": "Training injection: electric motor drive disconnected.",
		"hint": "The motor is disconnected, while the propeller can coast or windmill. Keep a safe airspeed and plan a landing.",
		"severity": "ordinary",
		"scaled_by_severity": false,
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


## Current (v3) pool: the frozen v2 set plus the EM-30 additions, minus player exclusions.
## Unknown profiles have no event set; empty means nothing eligible remains.
static func failure_ids_v3(include_catastrophic: bool, eligibility_profile: String,
		excluded_ids: Array = []) -> Array[String]:
	if eligibility_profile not in PROFILES:
		return []
	var candidates := ORDINARY_IDS.duplicate()
	candidates.append_array(ADDED_ORDINARY_IDS_V3)
	if eligibility_profile == FINITE_GLOW_PROFILE:
		candidates.append_array(GLOW_POWER_LOSS_IDS)
	elif eligibility_profile == ELECTRIC_DRIVE_PROFILE:
		candidates.append_array(ELECTRIC_POWER_LOSS_IDS)
	if include_catastrophic:
		candidates.append_array(CATASTROPHIC_IDS)
	var result: Array[String] = []
	for failure_id: String in candidates:
		if not excluded_ids.has(failure_id):
			result.append(failure_id)
	return result


## Control-axis types this aircraft physically lacks (EM-30). Elevons mix roll and pitch only;
## the rudder stays at zero, so a rudder failure would change nothing.
static func unsupported_ids(model: Dictionary) -> Array[String]:
	var controls_value: Variant = model.get("controls", {})
	if typeof(controls_value) == TYPE_DICTIONARY and str(controls_value.get("layout", "")) == "elevon":
		return YAW_AXIS_IDS.duplicate()
	return []


## The player's request for this aircraft: its missing control axes join the exclusions, so the
## resolved v3 plan records exactly what could be drawn and replays without the model.
static func request_for_model(config: Dictionary, model: Dictionary) -> Dictionary:
	var request: Dictionary = config.duplicate(true)
	var excluded: Array[String] = []
	for failure_id: Variant in config.get("excluded_ids", []):
		excluded.append(str(failure_id))
	for failure_id: String in unsupported_ids(model):
		if not excluded.has(failure_id):
			excluded.append(failure_id)
	excluded.sort()
	request["excluded_ids"] = excluded
	return request


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
	var unsupported: Array[String] = unsupported_ids(model)
	var ids: Array[String] = []
	for failure_id: String in ORDINARY_IDS + ADDED_ORDINARY_IDS_V3 + power_loss_ids + CATASTROPHIC_IDS:
		if not unsupported.has(failure_id):
			ids.append(failure_id)
	return {
		"eligibility_profile": profile,
		"eligible_ids": ids,
		"power_loss_ids": power_loss_ids,
		"power_loss_supported": not power_loss_ids.is_empty(),
		"exclusion_reason": reason,
		"unsupported_ids": unsupported,
		"control_exclusion_reason": "This aircraft has no rudder, so rudder failures cannot occur." \
			if not unsupported.is_empty() else "",
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
