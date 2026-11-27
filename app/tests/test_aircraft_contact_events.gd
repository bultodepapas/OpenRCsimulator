## AS13: event normalization, identity, reference and snapshot validation checks.
extends SceneTree

const EventNormalizer := preload("res://sim/aircraft_contact_events.gd")
const HullContact := preload("res://physics/hull_contact.gd")
const ImpactSnapshot := preload("res://physics/impact_snapshot.gd")
const HullCrossing := preload("res://physics/hull_crossing.gd")
const HullContactLaw := preload("res://physics/hull_contact.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const SceneryCollision := preload("res://sim/scenery_collision.gd")
const LakeCollision := preload("res://sim/lake_collision.gd")

var _count: int = 0
var _failures: int = 0


func _check(label: String, passed: bool) -> void:
	_count += 1
	if not passed:
		_failures += 1
	print(("ok   " if passed else "FAIL ") + label)


func _bindings() -> Dictionary:
	return {
		"hull_probes": [
			{"id": "hull_point_000"},
			{"id": "hull_point_001"},
	],
		"support_points": [{"id": "main_left"}],
		"rotor_disc": {"hub": PackedFloat64Array([0.0, 0.0, 0.0]), "radius": 0.2},
	}


## CR-AUD-04: the flattened event must say which point owns crossing_fraction.
func _staggered_snapshot(late_first: bool) -> Dictionary:
	# Two rigid points enter within one interpolated interval: one at fraction 0.2 (lateral -0.1), a faster
	# one at 0.8 (lateral +0.1). The terminal policy selects the faster point; the typed snapshot keeps the
	# earliest whole-hull crossing separately.
	var q_after := M.q_from_euler(0.0, 0.0, 0.04)
	var v_world := M.v3(0.0, 0.0, 12.0)
	var rate := M.v3(9.6, 0.0, 0.0)
	var before := RB.make_state(M.v3(0.0, 0.0, -0.02), v_world, M.q_identity(), rate)
	var after := RB.make_state(M.v3(0.0, 0.0, 0.03), M.q_rotate(M.q_conj(q_after), v_world), q_after, rate)
	var early := PackedFloat64Array([0.0, -0.1, _depth_r_for_crossing(0.2, -0.1)])
	var late := PackedFloat64Array([0.0, 0.1, _depth_r_for_crossing(0.8, 0.1)])
	var hull: PackedFloat64Array = (late + early) if late_first else (early + late)
	var prepared: Dictionary = HullContactLaw.prepare(hull, 1.0, PackedFloat64Array([1.0, 1.0, 1.0, 0.0, 0.0, 0.0]))
	var hit: Dictionary = HullContactLaw.terminal(before, after, prepared)
	var snapshot := ImpactSnapshot.hull_point(after, 1, hull, int(hit.index), before, str(hit.rule))
	return {"snapshot": snapshot, "hit": hit}


func _depth_r_for_crossing(fraction: float, lateral: float) -> float:
	var half_theta := 0.02
	var roll := 2.0 * atan2(fraction * sin(half_theta), 1.0 - fraction + fraction * cos(half_theta))
	return -((-0.02 + 0.05 * fraction) + sin(roll) * lateral) / cos(roll)


func _test_staggered_crossings() -> void:
	var bindings := {"hull_probes": [{"id": "probe_a"}, {"id": "probe_b"}]}
	for late_first: bool in [false, true]:
		var label := "reversed order" if late_first else "early point first"
		var staged := _staggered_snapshot(late_first)
		var snapshot: ImpactSnapshot.Snapshot = staged.snapshot
		var selected_index := 0 if late_first else 1
		var witness_index := 1 if late_first else 0
		_check("staggered fixture (%s) selects the faster late point" % label, int(staged.hit.index) == selected_index
			and snapshot.point_index == selected_index and snapshot.crossing.available
			and snapshot.crossing.point_index == witness_index and absf(snapshot.crossing.fraction - 0.2) < 1e-9)
		var event := EventNormalizer.impact_event(snapshot, bindings, HullContactLaw.law())
		_check("staggered event (%s) serializes and validates" % label,
			not event.is_empty() and EventNormalizer.validate_events([event], snapshot.tick, bindings))
		_check("staggered event (%s) keeps the selected identity" % label, event.get("point_index", -1) == selected_index
			and event.get("contact_id", "") == bindings.hull_probes[selected_index].id)
		_check("staggered event (%s) names the earliest crossing witness with its 0.2 fraction" % label,
			event.get("format", "") == EventNormalizer.FORMAT_V2
			and event.get("crossing_point_index", -1) == witness_index
			and event.get("crossing_probe_id", "") == bindings.hull_probes[witness_index].id
			and absf(float(event.get("crossing_fraction", -1.0)) - 0.2) < 1e-9
			and event.get("crossing_is_selected", true) == false)
		_check("staggered event (%s) does not claim the selected point's own crossing" % label,
			not event.has("selected_crossing_fraction"))
		var mislabeled: Dictionary = event.duplicate(true)
		mislabeled["crossing_is_selected"] = true
		_check("staggered event (%s) cannot claim the selected point is the witness" % label,
			not EventNormalizer.validate_events([mislabeled], snapshot.tick, bindings))
		var swapped: Dictionary = event.duplicate(true)
		swapped["crossing_probe_id"] = event.contact_id
		_check("staggered event (%s) cannot name the selected probe as the witness" % label,
			not EventNormalizer.validate_events([swapped], snapshot.tick, bindings))


func _test_crossing_witness_validation(v2_event: Dictionary, bindings: Dictionary) -> void:
	var legacy: Dictionary = v2_event.duplicate(true)
	legacy["format"] = EventNormalizer.FORMAT
	for key: String in ["crossing_point_index", "crossing_probe_id", "crossing_is_selected", "selected_crossing_fraction"]:
		legacy.erase(key)
	_check("legacy v1 impact event with crossing_fraction still validates",
		EventNormalizer.validate_events([legacy], 11, bindings))
	var v1_with_witness: Dictionary = v2_event.duplicate(true)
	v1_with_witness["format"] = EventNormalizer.FORMAT
	_check("closed v1 rejects the witness keys", not EventNormalizer.validate_events([v1_with_witness], 11, bindings))
	for key: String in ["crossing_point_index", "crossing_probe_id", "crossing_is_selected", "crossing_fraction"]:
		var missing: Dictionary = v2_event.duplicate(true)
		missing.erase(key)
		_check("v2 requires %s" % key, not EventNormalizer.validate_events([missing], 11, bindings))
	var wrong_probe: Dictionary = v2_event.duplicate(true)
	wrong_probe["crossing_probe_id"] = "hull_point_001"
	_check("v2 witness probe must match the bound index", not EventNormalizer.validate_events([wrong_probe], 11, bindings))
	var drifted: Dictionary = v2_event.duplicate(true)
	drifted["selected_crossing_fraction"] = 0.5
	_check("selected witness fraction must equal crossing_fraction", not EventNormalizer.validate_events([drifted], 11, bindings))
	var bad_type: Dictionary = v2_event.duplicate(true)
	bad_type["crossing_point_index"] = "0"
	_check("witness index must be an integer", not EventNormalizer.validate_events([bad_type], 11, bindings))


func _test_unidentified_crossing_is_withheld(selected: ImpactSnapshot.Snapshot, bindings: Dictionary) -> void:
	var unidentified := HullCrossing.Result.new()
	unidentified.available = true
	unidentified.fraction = 0.4 # point_index stays -1: nobody to attribute the fraction to
	var original: HullCrossing.Result = selected.crossing
	selected.crossing = unidentified
	var event := EventNormalizer.impact_event(selected, bindings, "legacy-terminal-hull-v1")
	selected.crossing = original
	_check("an unidentifiable crossing is withheld, not exported ambiguously", not event.is_empty()
		and event.get("format", "") == EventNormalizer.FORMAT and not event.has("crossing_fraction")
		and not event.has("crossing_point_index") and EventNormalizer.validate_events([event], selected.tick, bindings))


func _initialize() -> void:
	_check("event format is versioned", EventNormalizer.FORMAT == "openrc-aircraft-contact-events v1")
	var bindings := _bindings()
	var authored_bindings: Dictionary = bindings.duplicate(true)
	authored_bindings["rotor_id"] = "propeller/engine/main"
	var records: Array = [{
		"index": 0,
		"new": true,
		"depth_m": 0.025,
		"normal_speed_mps": 1.5,
		"slide_speed_mps": 4.0,
		"point_ned": PackedFloat64Array([3.0, 4.0, 0.025]),
		"velocity_ned": PackedFloat64Array([4.0, 0.0, 1.5]),
	}]
	var saved_records: Array = records.duplicate(true)
	var saved_bindings: Dictionary = bindings.duplicate(true)
	var normalized: Dictionary = EventNormalizer.hull_events(records, bindings, PackedStringArray(), 7)
	_check("active hull contact normalizes", normalized.ok and normalized.events.size() == 1)
	var contact: Dictionary = normalized.events[0] if normalized.ok else {}
	_check("hull identity and lifecycle use bound point ID", contact.get("contact_id", "") == "hull_point_000"
		and contact.get("source", "") == "hull" and contact.get("lifecycle", "") == "new")
	_check("hull record carries law, response, tick and measures", contact.get("policy", "") == HullContact.law()
		and contact.get("response", "") == "contact" and contact.get("tick", -1) == 7
		and contact.get("measure", {}).get("depth_m", -1.0) == 0.025
		and contact.get("measure", {}).get("normal_speed_mps", -1.0) == 1.5)
	_check("normalized hull event array validates", EventNormalizer.validate_events(normalized.events, 7, bindings))
	_check("hull normalization leaves source records and bindings unchanged", records == saved_records and bindings == saved_bindings)
	if normalized.ok:
		normalized.events[0].measure.depth_m = 9.0
		_check("event measurements do not alias source records", records[0].depth_m == 0.025)

	var persistent := EventNormalizer.hull_events(records, bindings, PackedStringArray(["hull_point_000"]), 8)
	_check("prior contact becomes persistent", persistent.ok and persistent.events[0].lifecycle == "persistent")
	var ended := EventNormalizer.hull_events([], bindings, PackedStringArray(["hull_point_000"]), 9)
	_check("missing prior contact emits an ended lifecycle", ended.ok and ended.events.size() == 1
		and ended.events[0].lifecycle == "ended" and ended.active_ids.is_empty())

	var bad_record: Array = [{"index": 0, "new": "yes"}]
	_check("malformed source lifecycle is rejected", not EventNormalizer.hull_events(
		bad_record, bindings, PackedStringArray(), 10).ok)
	var nan_record: Array = [{"index": 0, "new": true, "depth_m": NAN}]
	_check("NaN scalar measurement is rejected", not EventNormalizer.hull_events(
		nan_record, bindings, PackedStringArray(), 10).ok)
	var short_vector: Array = [{"index": 0, "new": true, "point_ned": PackedFloat64Array([0.0, 1.0])}]
	_check("malformed vector is rejected", not EventNormalizer.hull_events(
		short_vector, bindings, PackedStringArray(), 10).ok)

	var hull_impact := ImpactSnapshot.Snapshot.new()
	hull_impact.trigger = "hull_contact"
	hull_impact.tick = 11
	hull_impact.point_index = 0
	hull_impact.soft_rule = "impact"
	hull_impact.has_kinematics = true
	hull_impact.point_ned = PackedFloat64Array([0.0, 1.0, 0.0])
	hull_impact.velocity_ned = PackedFloat64Array([2.0, 0.0, 1.0])
	hull_impact.normal_ned = PackedFloat64Array([0.0, 0.0, -1.0])
	hull_impact.speed_mps = sqrt(5.0)
	hull_impact.down_speed_mps = 1.0
	var crossing := HullCrossing.Result.new()
	crossing.available = true
	crossing.fraction = 0.4
	crossing.point_index = 0
	hull_impact.crossing = crossing
	var impact_record: Dictionary = EventNormalizer.impact_event(hull_impact, bindings, "legacy-terminal-hull-v1")
	_check("hull impact resolves its stable binding and observed tick", impact_record.get("source", "") == "hull"
		and impact_record.get("contact_id", "") == "hull_point_000" and impact_record.get("tick", -1) == 11)
	_check("hull impact keeps optional crossing and available kinematics", impact_record.get("crossing_fraction", -1.0) == 0.4
		and impact_record.has("point_ned") and impact_record.has("velocity_ned")
		and impact_record.get("measure", {}).get("speed_mps", -1.0) > 2.0)
	_check("impact snapshot arrays are copied", impact_record.point_ned[0] == hull_impact.point_ned[0])
	impact_record.point_ned[0] = 100.0
	_check("serialized impact vectors do not alias snapshot", hull_impact.point_ned[0] == 0.0)
	_check("hull impact validates", EventNormalizer.validate_events([impact_record], 11, bindings))
	_check("hull impact names its crossing witness in v2", impact_record.get("format", "") == EventNormalizer.FORMAT_V2
		and impact_record.get("crossing_point_index", -1) == 0 and impact_record.get("crossing_probe_id", "") == "hull_point_000"
		and impact_record.get("crossing_is_selected", false) == true
		and impact_record.get("selected_crossing_fraction", -1.0) == 0.4)
	_test_crossing_witness_validation(impact_record, bindings)
	_test_unidentified_crossing_is_withheld(hull_impact, bindings)
	_test_staggered_crossings()

	var gear_impact := ImpactSnapshot.Snapshot.new()
	gear_impact.trigger = "gear_limit"
	gear_impact.tick = 12
	gear_impact.point_index = 0
	gear_impact.component_name = "main_left"
	gear_impact.has_compression = true
	gear_impact.compression_m = 0.12
	gear_impact.travel_limit_m = 0.10
	var gear_record := EventNormalizer.impact_event(gear_impact, bindings, "gear-overtravel-terminal-v1")
	_check("gear impact uses support ID and measured compression", gear_record.get("source", "") == "gear"
		and gear_record.get("contact_id", "") == "main_left"
		and gear_record.get("measure", {}).get("compression_m", -1.0) == 0.12
		and gear_record.get("measure", {}).get("travel_limit_m", -1.0) == 0.10)
	_check("gear snapshot invents no impulse", not gear_record.get("measure", {}).has("impulse_n_s")
		and not gear_record.has("impulse_n_s"))

	var scenery := SceneryCollision.Event.new()
	scenery.tick = 13
	scenery.point_index = 1
	scenery.obstacle_id = "tree:oak:trunk"
	scenery.obstacle_kind = "tree"
	scenery.obstacle_part = "trunk"
	scenery.response_class = "light_airframe"
	scenery.response_status = "impulse_pending"
	scenery.time_fraction = 0.25
	scenery.normal_speed_mps = 4.0
	scenery.effective_mass_kg = 1.2
	scenery.impact_energy_j = 9.6
	scenery.terminal = false
	scenery.has_kinematics = true
	scenery.point_ned = PackedFloat64Array([0.0, 2.0, 1.0])
	scenery.velocity_ned = PackedFloat64Array([4.0, 0.0, 0.0])
	scenery.normal_ned = PackedFloat64Array([0.0, -1.0, 0.0])
	_check("pending scenery response cannot claim a dissipative impulse", EventNormalizer.impact_event(
		scenery, bindings, "scenery-response-v1:fixture").is_empty())
	scenery.response_status = "dissipative_impulse"
	var scenery_record := EventNormalizer.impact_event(scenery, bindings, "scenery-response-v1:fixture")
	_check("scenery contact links its hull probe and sub-tick timing", scenery_record.get("source", "") == "scenery"
		and scenery_record.get("probe_id", "") == "hull_point_001"
		and scenery_record.get("time_fraction", -1.0) == 0.25)
	_check("scenery soft contact records dissipative response and real measurements", scenery_record.get("response", "") == "dissipative_impulse"
		and scenery_record.get("measure", {}).get("effective_mass_kg", -1.0) == 1.2
		and scenery_record.get("measure", {}).get("impact_energy_j", -1.0) == 9.6)
	var conflicting: Dictionary = scenery_record.duplicate(true)
	conflicting.response_status = "terminal"
	_check("conflicting response status is rejected", not EventNormalizer.validate_events([conflicting], 13, bindings))
	conflicting = scenery_record.duplicate(true)
	conflicting.erase("time_fraction")
	_check("swept events require their observed contact fraction", not EventNormalizer.validate_events([conflicting], 13, bindings))
	scenery.response_status = "response_failed_terminal"
	var failed_response := EventNormalizer.impact_event(scenery, bindings, "scenery-response-v1:fixture")
	_check("failed scenery response is terminal", failed_response.get("response", "") == "terminal"
		and failed_response.get("response_status", "") == "response_failed_terminal")

	var water := LakeCollision.WaterEvent.new()
	water.tick = 14
	water.trigger = "water"
	water.point_index = -1
	water.obstacle_id = "lake:pond:water"
	water.lake_id = "pond"
	water.material = "water"
	water.probe_kind = "propeller"
	water.time_fraction = 0.6
	water.depth_m = 0.03
	water.normal_speed_mps = 2.0
	water.specific_j_per_kg = 2.0
	water.has_kinematics = true
	water.point_ned = PackedFloat64Array([0.0, 0.0, 0.03])
	water.velocity_ned = PackedFloat64Array([1.0, 0.0, 2.0])
	water.normal_ned = PackedFloat64Array([0.0, 0.0, -1.0])
	var water_record := EventNormalizer.impact_event(water, bindings, "lake-contact-v1:fixture")
	_check("lake propeller probe uses its single-rotor binding at index minus one", water_record.get("source", "") == "lake"
		and water_record.get("probe_source", "") == "propeller"
		and water_record.get("probe_id", "") == "propeller/single"
		and water_record.get("point_index", 0) == -1)
	_check("water event uses authoritative time fraction and terminal response", water_record.get("time_fraction", -1.0) == 0.6
		and water_record.get("response", "") == "terminal"
		and EventNormalizer.validate_events([water_record], 14, bindings))
	var authored_water_record := EventNormalizer.impact_event(water, authored_bindings, "lake-contact-v1:fixture")
	_check("lake propeller probe carries the authored rotor ID",
		authored_water_record.get("probe_id", "") == "propeller/engine/main"
		and EventNormalizer.validate_events([authored_water_record], 14, authored_bindings))

	var gear_water := LakeCollision.WaterEvent.new()
	gear_water.tick = 15
	gear_water.trigger = "lake_bank"
	gear_water.point_index = 0
	gear_water.obstacle_id = "lake:pond:bank_ground"
	gear_water.lake_id = "pond"
	gear_water.material = "bank_ground"
	gear_water.probe_kind = "gear"
	gear_water.time_fraction = 1.0
	var gear_water_record := EventNormalizer.impact_event(gear_water, bindings, "lake-contact-v1:fixture")
	_check("lake gear probe resolves support binding", gear_water_record.get("probe_source", "") == "gear"
		and gear_water_record.get("probe_id", "") == "main_left"
		and EventNormalizer.validate_events([gear_water_record], 15, bindings))

	var strike_input := {
		"tick": 16,
		"rpm": 850.0,
		"point_ned": PackedFloat64Array([1.0, 2.0, 0.0]),
		"velocity_ned": PackedFloat64Array([10.0, 0.0, 0.0]),
	}
	var saved_strike_input: Dictionary = strike_input.duplicate(true)
	var strike := EventNormalizer.strike_event(strike_input, 16, "soft-hull-propeller-strike-v1")
	_check("single propeller strike is engine-stop-and-continue", strike.get("source", "") == "propeller"
		and strike.get("contact_id", "") == "propeller/single"
		and strike.get("response", "") == "engine_stop_continue"
		and strike.get("tick", -1) == 16 and strike.get("measure", {}).get("rpm", -1.0) == 850.0)
	_check("propeller strike validates against rotor-disc binding", EventNormalizer.validate_events([strike], 16, bindings))
	_check("strike normalization leaves source record unchanged", strike_input == saved_strike_input)
	var authored_strike := EventNormalizer.strike_event(strike_input, 16,
		"soft-hull-propeller-strike-v1", authored_bindings)
	_check("authored rotor ID is carried into strike event and validates",
		authored_strike.get("contact_id", "") == "propeller/engine/main"
		and EventNormalizer.validate_events([authored_strike], 16, authored_bindings))
	var mismatched_rotor: Dictionary = authored_strike.duplicate(true)
	mismatched_rotor["contact_id"] = "propeller/single"
	mismatched_rotor["event_id"] = "as13:strike:propeller:16:new:%d:%s" % [mismatched_rotor.contact_id.length(), mismatched_rotor.contact_id]
	_check("legacy rotor ID cannot satisfy an authored rotor binding",
		not EventNormalizer.validate_events([mismatched_rotor], 16, authored_bindings))
	var malformed_rotor_bindings: Dictionary = bindings.duplicate(true)
	malformed_rotor_bindings["rotor_id"] = ""
	_check("empty rotor binding cannot serialize a strike", EventNormalizer.strike_event(strike_input,
		16, "soft-hull-propeller-strike-v1", malformed_rotor_bindings).is_empty())
	_check("malformed strike vector is rejected", EventNormalizer.strike_event({
		"tick": 16,
		"rpm": 850.0,
		"point_ned": PackedFloat64Array([1.0, 2.0]),
	}, 16, "soft-hull-propeller-strike-v1").is_empty())
	_check("strike without its authoritative tick or measurements is rejected", EventNormalizer.strike_event(
		{"rpm": 850.0}, 16, "soft-hull-propeller-strike-v1").is_empty())
	_check("strike payload tick must match serializer tick", EventNormalizer.strike_event({
		"tick": 15,
		"rpm": 850.0,
		"point_ned": PackedFloat64Array([1.0, 2.0, 0.0]),
		"velocity_ned": PackedFloat64Array([10.0, 0.0, 0.0]),
	}, 16, "soft-hull-propeller-strike-v1").is_empty())
	var incomplete_strike: Dictionary = strike.duplicate(true)
	incomplete_strike["measure"].erase("rpm")
	_check("event validation requires strike rpm and kinematics", not EventNormalizer.validate_events(
		[incomplete_strike], 16, bindings))
	incomplete_strike = strike.duplicate(true)
	incomplete_strike.erase("velocity_ned")
	_check("event validation rejects missing strike velocity", not EventNormalizer.validate_events(
		[incomplete_strike], 16, bindings))

	if normalized.ok:
		var duplicate_events: Array[Dictionary] = [normalized.events[0].duplicate(true), normalized.events[0].duplicate(true)]
		_check("duplicate event IDs are rejected", not EventNormalizer.validate_events(duplicate_events, 7, bindings))
		var same_contact: Dictionary = normalized.events[0].duplicate(true)
		same_contact.event_type = "impact"
		same_contact.response = "terminal"
		same_contact.lifecycle = "new"
		same_contact.event_id = "as13:impact:hull:7:new:%d:%s" % [same_contact.contact_id.length(), same_contact.contact_id]
		_check("a terminal contact replaces rather than duplicates its hull observation", not EventNormalizer.validate_events(
			[normalized.events[0], same_contact], 7, bindings))
		var dangling: Dictionary = normalized.events[0].duplicate(true)
		dangling["point_index"] = 1
		_check("contact ID pointing at the wrong source binding is rejected", not EventNormalizer.validate_events([dangling], 7, bindings))
		var wrong_source: Dictionary = normalized.events[0].duplicate(true)
		wrong_source["source"] = "gear"
		_check("source and response combinations are checked", not EventNormalizer.validate_events([wrong_source], 7, bindings))
		var bad_response: Dictionary = normalized.events[0].duplicate(true)
		bad_response["response"] = "invented_impulse"
		_check("unknown response is rejected", not EventNormalizer.validate_events([bad_response], 7, bindings))
		var bad_lifecycle: Dictionary = normalized.events[0].duplicate(true)
		bad_lifecycle["lifecycle"] = "forever"
		_check("unknown lifecycle is rejected", not EventNormalizer.validate_events([bad_lifecycle], 7, bindings))
		var bad_measure: Dictionary = normalized.events[0].duplicate(true)
		bad_measure["measure"]["depth_m"] = NAN
		_check("nonfinite event scalar is rejected", not EventNormalizer.validate_events([bad_measure], 7, bindings))
		var bad_vector: Dictionary = normalized.events[0].duplicate(true)
		bad_vector["point_ned"] = PackedFloat64Array([0.0, INF, 0.0])
		_check("nonfinite event vector is rejected", not EventNormalizer.validate_events([bad_vector], 7, bindings))
		var object_value: Dictionary = normalized.events[0].duplicate(true)
		object_value["point_ned"] = ImpactSnapshot.Snapshot.new()
		_check("Object values are rejected from snapshots", not EventNormalizer.validate_events([object_value], 7, bindings))

	_test_support_events_valid_by_construction()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures else 0)


## support_event returns its event without re-validating it: every event it builds must pass
## _support_event_is_valid, and validate_events must accept it, for each lifecycle, edge value and binding.
func _test_support_events_valid_by_construction() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4421
	var bindings := {"support_points": [{"id": "main_left"}, {"id": "main_right"}, {"id": " tail "}, {"id": ""}, {}]}
	var values := [0.0, -0.0, 1.0e-300, -1.0e-300, 0.002, -0.004, 0.05, 1.0e9, NAN, INF, -INF]
	var built := 0
	var invalid := 0
	var lifecycles := {}
	for i in 4000:
		var index: int = rng.randi_range(-1, 5)
		var compression: float = values[rng.randi_range(0, values.size() - 1)] if i % 3 == 0 else rng.randf_range(-0.01, 0.03)
		var previous: float = values[rng.randi_range(0, values.size() - 1)] if i % 5 == 0 else rng.randf_range(-0.01, 0.03)
		var travel: float = values[rng.randi_range(0, values.size() - 1)] if i % 7 == 0 else rng.randf_range(0.001, 0.05)
		var tick: int = [0, 1, 2, 977, -3][rng.randi_range(0, 4)]
		var event: Dictionary = EventNormalizer.support_event(index, compression, previous, travel, tick, bindings)
		if event.is_empty():
			continue
		built += 1
		lifecycles[event.lifecycle] = true
		if not EventNormalizer._support_event_is_valid(event, tick, bindings) \
				or not EventNormalizer.validate_events([event], tick, bindings):
			invalid += 1
	_check("every support event built is valid by construction (%d built, %d invalid)" % [built, invalid],
		invalid == 0 and built > 500)
	_check("support events cover every lifecycle", lifecycles.size() == 3)
