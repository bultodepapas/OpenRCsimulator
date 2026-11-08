## Interpret only verifiable context from schema-v1 flight metadata.
extends RefCounted

const FailureConfig := preload("res://failures/config.gd")
const ScenarioConfig := preload("res://scenarios/scenario_config.gd")
const AircraftIdentity := preload("res://statistics/aircraft_identity.gd")
const CONTEXT_FORMAT := "openrc-statistics-launch-context-v1"
const UINT32_MAX := 4294967295


static func from_record(record: Dictionary) -> Dictionary:
	var metadata_value: Variant = record.get("metadata", {})
	var metadata: Dictionary = metadata_value if metadata_value is Dictionary else {}
	var marked: bool = metadata.get("launch_context_format", "") == CONTEXT_FORMAT
	var scenario_kind := "unknown"
	var scenario := {}
	var raw_scenario: Variant = metadata.get("scenario", null)
	if raw_scenario is Dictionary and not raw_scenario.is_empty():
		var checked_scenario := ScenarioConfig.validate(raw_scenario)
		if checked_scenario.ok:
			var candidate: Dictionary = checked_scenario.scenario
			var recorded_id := str(record.get("aircraft_id", ""))
			var recorded_hash := str(record.get("config_hash", ""))
			var metadata_hash := str(metadata.get("config_hash", ""))
			if not recorded_id.is_empty() and AircraftIdentity.matches(recorded_id, str(candidate.aircraft_id)) \
					and (recorded_hash.is_empty() or recorded_hash == str(candidate.aircraft_identity)) \
					and (metadata_hash.is_empty() or metadata_hash == str(candidate.aircraft_identity)):
				scenario = candidate.duplicate(true)
				scenario_kind = "natural_random"
	elif marked and raw_scenario is Dictionary and raw_scenario.is_empty():
		scenario_kind = "ordinary"
	var practice := {}
	var seed: Variant = metadata.get("failure_seed", null)
	if marked and typeof(seed) == TYPE_INT and int(seed) >= 0 and int(seed) <= UINT32_MAX:
		var checked_practice := FailureConfig.validate(metadata.get("failure_config", null))
		if checked_practice.ok:
			practice = checked_practice.config.duplicate(true)
	var failures: Array[Dictionary] = []
	var observed: Variant = metadata.get("events", [])
	if observed is Array:
		for event: Variant in observed:
			if not event is Dictionary or str(event.get("type", "")) != "failure_activated" \
					or str(event.get("source", "")) != "accepted_failure_signal_v1": continue
			var failure_id: Variant = event.get("failure_id", null)
			var tick: Variant = event.get("tick", null)
			if typeof(failure_id) != TYPE_STRING or str(failure_id).is_empty() \
					or typeof(tick) != TYPE_INT or int(tick) < 0:
				continue
			failures.append({"failure_id": str(failure_id), "tick": int(tick)})
	return {"scenario_kind": scenario_kind, "scenario": scenario,
		"practice_known": not practice.is_empty(), "practice": practice,
		"practice_seed": int(seed) if not practice.is_empty() else -1,
		"failure_events": failures}
