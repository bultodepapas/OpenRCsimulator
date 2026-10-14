extends RefCounted

const VERSION := 1

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
}


static func failure_ids(include_catastrophic: bool) -> Array[String]:
	var result := ORDINARY_IDS.duplicate()
	if include_catastrophic:
		result.append_array(CATASTROPHIC_IDS)
	return result


static func definition(failure_id: String) -> Dictionary:
	if not DEFINITIONS.has(failure_id):
		return {}
	return DEFINITIONS[failure_id].duplicate(true)
