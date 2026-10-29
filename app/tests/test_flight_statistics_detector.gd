extends SceneTree

const Detector := preload("res://statistics/detector.gd")
const Profiles := preload("res://statistics/profiles.gd")
const AircraftCatalog := preload("res://app_state/aircraft_catalog.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const ContactContract := preload("res://physics/aircraft_contact_contract.gd")

const DT := 1.0 / 240.0
## Review coverage is explicit: a future catalog addition must receive a support
## review instead of silently inheriting either the wheel or gearless exception.
const REVIEWED_WHEEL_IDS := ["jensen-das-ugly-stik-60", "stik-glow-61fx-2t",
	"stik-glow-55ax-2t", "stik-glow-fs64v-4t", "gp-extra-300s-60",
	"p51d-mustang-120", "f4u-corsair-250", "sebart-avanti-s-a200-p100rx",
	"turbo-lumber-evolution"]
## Developer-only electric Stik routes (main.gd --electric-demo) also carry reviewed wheel metadata.
const ELECTRIC_DEMO_IDS := ["synthetic_stik_electric_4s", "synthetic_stik_electric_4s_battery",
	"synthetic_stik_electric_6s", "synthetic_stik_electric_6s_battery"]
const X8_HULL_IDS := ["probe_nose", "probe_nose_left", "probe_nose_right",
	"probe_nose_left_low", "probe_nose_right_low", "probe_canopy_front", "probe_canopy",
	"probe_belly_front", "probe_belly", "probe_engine", "probe_wing_left_root_le",
	"probe_wing_right_root_le", "probe_wing_left_bottom", "probe_wing_right_bottom",
	"probe_elevon_left_te", "probe_elevon_right_te", "probe_winglet_left_top",
	"probe_winglet_right_top", "probe_winglet_left_outer", "probe_winglet_right_outer",
	"probe_wing_left_tip_le", "probe_wing_right_tip_le", "probe_wing_left_tip_te",
	"probe_wing_right_tip_te", "probe_winglet_right_fill_1", "probe_winglet_left_fill_1",
	"probe_wing_left_fill_2", "probe_wing_right_fill_2"]

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_profiles_for_catalog_fleet()
	_test_takeoff_backfill_and_air_start()
	_test_touch_and_go_then_full_stop()
	_test_incident_and_unresolved_episode()
	_test_duplicate_terminal_and_ground_crash()
	_test_gap_marks_partial_and_freezes_time()
	_test_speed_window_filters_spikes()
	_test_json_safe_snapshot_restore()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _profile() -> Dictionary:
	return {
		"landing_available": true,
		"main_indices": PackedInt32Array([0, 1]),
		"stop_indices": PackedInt32Array([0, 1, 2]),
		"clearance_m": 0.25,
		"rest_height_m": 0.25,
		"rest_pitch_rad": 0.0,
		"speed_cap_mps": 100.0,
		"initial_tick": 0,
	}


func _sample(tick: int, changes := {}) -> Dictionary:
	var value := {
		"tick": tick,
		"dt": DT,
		"supported": false,
		"intended_support": false,
		"stop_support": false,
		"clearance_ok": false,
		"controlled": true,
		"ground_speed_3d": 0.0,
		"angular_speed": 0.0,
		"tas": 0.0,
		"groundspeed": 0.0,
		"position": PackedFloat64Array([0.0, 0.0, 0.0]),
		"velocity_ned": PackedFloat64Array([0.0, 0.0, 0.0]),
		"incident": false,
		"terminal": false,
		"ground_contact": false,
		"valid": true,
	}
	for key: Variant in changes:
		value[key] = changes[key]
	return value


func _start_flight(detector: RefCounted, start_tick := 1) -> Dictionary:
	var events: Array[Dictionary] = []
	for tick in range(start_tick, start_tick + 240):
		var observed: Array[Dictionary] = detector.observe(_sample(tick, {
			"clearance_ok": true,
		}))
		events.append_array(observed)
	return _first_event(events, "started")


func _first_event(events: Array[Dictionary], event_type: String) -> Dictionary:
	for event: Dictionary in events:
		if str(event.get("type", "")) == event_type:
			return event
	return {}


func _events_of(events: Array[Dictionary], event_type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event: Dictionary in events:
		if str(event.get("type", "")) == event_type:
			out.append(event)
	return out


func _test_profiles_for_catalog_fleet() -> void:
	var ids: PackedStringArray = AircraftCatalog.airplane_flyable_ids()
	for reviewed_id: String in REVIEWED_WHEEL_IDS:
		_check("reviewed wheel aircraft remains covered: %s" % reviewed_id, reviewed_id in ids)
	_check("explicit gearless MoonRunner X99 remains covered", "moonrunner-x99" in ids)
	for aircraft_id: String in ids:
		var entry: Dictionary = AircraftCatalog.entry(aircraft_id)
		var loaded: Dictionary = AircraftData.load_file(str(entry.get("data", "")))
		_check("%s data loads for the profile check" % aircraft_id, bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
		if not bool(loaded.get("ok", false)):
			continue
		var model: Dictionary = loaded.model
		var bindings: Dictionary = ContactContract.describe(model, true)
		var profile: Dictionary = Profiles.resolve(aircraft_id, model, bindings)
		_check("%s has valid physical contact bindings" % aircraft_id, bool(bindings.get("ok", false)), str(bindings.get("errors", [])))
		if aircraft_id == "moonrunner-x99":
			_test_moonrunner_unreviewed_hull(str(entry.data), model, bindings, profile)
			var pack_path := str(entry.get("battery_data", ""))
			var pack: Dictionary = AircraftData.load_file(pack_path)
			_check("MoonRunner X99 default finite-pack data loads for support review", bool(pack.get("ok", false)), str(pack.get("errors", [])))
			if bool(pack.get("ok", false)):
				var pack_bindings := ContactContract.describe(pack.model, true)
				_test_moonrunner_unreviewed_hull(pack_path, pack.model, pack_bindings,
					Profiles.resolve(aircraft_id, pack.model, pack_bindings))
			continue
		_check("%s is an explicitly reviewed wheel profile" % aircraft_id, aircraft_id in REVIEWED_WHEEL_IDS)
		if aircraft_id not in REVIEWED_WHEEL_IDS:
			continue
		_check_reviewed_wheel_profile(aircraft_id, aircraft_id, model, bindings, profile)
		# Every finite-pack variant flies the same airframe ID, so it needs the same landing credit.
		var battery_path := str(entry.get("battery_data", ""))
		if not battery_path.is_empty():
			var battery: Dictionary = AircraftData.load_file(battery_path)
			_check("%s finite-pack data loads for the profile check" % aircraft_id, bool(battery.get("ok", false)), str(battery.get("errors", [])))
			if bool(battery.get("ok", false)):
				var battery_bindings: Dictionary = ContactContract.describe(battery.model, true)
				_check_reviewed_wheel_profile("%s finite pack" % aircraft_id, aircraft_id, battery.model, battery_bindings,
					Profiles.resolve(aircraft_id, battery.model, battery_bindings))
		if aircraft_id == "jensen-das-ugly-stik-60":
			var changed_model: Dictionary = model.duplicate(true)
			var gear: Dictionary = changed_model.landing_gear
			var contacts: Array = gear.contacts
			var position: PackedFloat64Array = contacts[0].position.duplicate()
			position[2] += 0.001
			contacts[0].position = position
			gear.contacts = contacts
			changed_model.landing_gear = gear
			var changed_bindings: Dictionary = ContactContract.describe(changed_model, true)
			var changed_profile: Dictionary = Profiles.resolve(aircraft_id, changed_model, changed_bindings)
			_check("changed support geometry disables landing credit", not bool(changed_profile.landing_available))
	for demo_id: String in ELECTRIC_DEMO_IDS:
		var demo: Dictionary = AircraftData.load_file("res://data/aircraft/%s.json" % demo_id)
		_check("%s data loads for the profile check" % demo_id, bool(demo.get("ok", false)), str(demo.get("errors", [])))
		if not bool(demo.get("ok", false)):
			continue
		var demo_bindings: Dictionary = ContactContract.describe(demo.model, true)
		_check("%s has valid physical contact bindings" % demo_id, bool(demo_bindings.get("ok", false)), str(demo_bindings.get("errors", [])))
		_check_reviewed_wheel_profile(demo_id, demo_id, demo.model, demo_bindings,
			Profiles.resolve(demo_id, demo.model, demo_bindings))
	for reviewed_id: Variant in Profiles._PROFILES.keys():
		_check("reviewed wheel metadata has a fleet check: %s" % reviewed_id,
			reviewed_id in REVIEWED_WHEEL_IDS or reviewed_id in ELECTRIC_DEMO_IDS)


func _check_reviewed_wheel_profile(label: String, aircraft_id: String, model: Dictionary, bindings: Dictionary, profile: Dictionary) -> void:
	_check("%s model identity matches its reviewed profile" % label, str(model.get("id", "")) == aircraft_id, str(model.get("id", "")))
	var positions: Array[String] = []
	for contact: Dictionary in model.get("landing_gear", {}).get("contacts", []):
		positions.append("%s=%s" % [str(contact.get("id", "")), var_to_str(contact.get("position"))])
	_check("%s has reviewed landing support metadata" % label,
		bool(profile.get("landing_available", false)), "%s %s" % [str(profile.get("reason", "")), ", ".join(positions)])
	_check("%s maps two main contacts and a three-contact stop set" % label,
		profile.get("main_indices", PackedInt32Array()).size() == 2
			and profile.get("stop_indices", PackedInt32Array()).size() == 3)
	_check("%s derives finite rest geometry and clearance" % label,
		float(profile.get("rest_height_m", -1.0)) > 0.0
			and float(profile.get("clearance_m", -1.0)) >= 0.25
			and is_finite(float(profile.get("rest_pitch_rad", NAN))))


func _test_moonrunner_unreviewed_hull(path: String, model: Dictionary, bindings: Dictionary, profile: Dictionary) -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check("X8 source is readable for authored support coverage: %s" % path, raw is Dictionary)
	if not raw is Dictionary:
		return
	_check("X8 authors locked-up gear with no installed wheels", raw.get("capabilities", {}).get("gear") == "locked_up"
		and not raw.has("landing_gear") and model.get("landing_gear", {}).is_empty())
	_check("X8 landing credit is explicitly unavailable pending support review", profile.get("landing_available") == false
		and profile.get("reason") == "unreviewed_aircraft_profile", str(profile.get("reason")))
	_check("X8 has no fabricated main/stop wheel maps", profile.get("main_indices", []).is_empty()
		and profile.get("stop_indices", []).is_empty() and profile.get("main_ids", []).is_empty()
		and profile.get("stop_ids", []).is_empty() and profile.get("rest_height_m") == -1.0)
	_check("X8 contact contract has zero wheel support bindings", bool(bindings.get("ok", false))
		and bindings.get("support_points", []).is_empty() and model.get("physical_identity", {}).get("support_ids", []).is_empty())
	var bound_ids: Array[String] = []
	var roles_absent := true
	for probe: Dictionary in bindings.get("hull_probes", []):
		bound_ids.append(str(probe.get("id", "")))
		roles_absent = roles_absent and not probe.has("role") and not probe.has("intended_support")
	_check("X8 retains all 28 authored stable hull IDs", X8_HULL_IDS.size() == 28
		and raw.get("crash_hull_ids") == X8_HULL_IDS and bound_ids == X8_HULL_IDS
		and model.get("physical_identity", {}).get("hull_ids") == PackedStringArray(X8_HULL_IDS))
	_check("X8 belly geometry has crash labels without an authored landing role", not raw.has("ground")
		and not raw.has("landing_support") and not raw.get("capabilities", {}).has("landing_support")
		and roles_absent and raw.get("crash_hull_components", [])[7] == "belly"
		and raw.get("crash_hull_components", [])[8] == "belly")


func _test_takeoff_backfill_and_air_start() -> void:
	var detector: RefCounted = Detector.new()
	detector.configure(_profile())
	var events: Array[Dictionary] = []
	for tick in range(1, 31):
		events.append_array(detector.observe(_sample(tick, {"clearance_ok": true})))
	_check("brief unsupported hop does not start a flight", _events_of(events, "started").is_empty())
	events.append_array(detector.observe(_sample(31, {"supported": true})))
	for tick in range(32, 272):
		events.append_array(detector.observe(_sample(tick, {"clearance_ok": true})))
	var started := _first_event(events, "started")
	_check("confirmed departure emits one takeoff start",
		_events_of(events, "started").size() == 1 and started.get("start_kind", "") == "takeoff")
	if not started.is_empty():
		_check("takeoff backfills the full confirmed unsupported run",
			absf(float(started.flight.airborne_seconds) - 1.0) <= DT)
	
	var air_start: RefCounted = Detector.new()
	air_start.configure(_profile(), true)
	var air_event := _start_flight(air_start)
	_check("airborne activation emits a start tagged air_start",
		not air_event.is_empty() and air_event.get("start_kind", "") == "air_start")
	_check("active sortie is represented until its close", not air_start.flight.is_empty())
	var ended: Array[Dictionary] = air_start.end("abandoned")
	var closed := _first_event(ended, "closed")
	_check("end closes active flight as abandoned",
		closed.get("outcome", "") == "abandoned" and closed.flight.outcome == "abandoned")
	_check("flight snapshot clears after close events are built", air_start.flight.is_empty())


func _test_touch_and_go_then_full_stop() -> void:
	var detector: RefCounted = Detector.new()
	detector.configure(_profile())
	var started := _start_flight(detector)
	_check("ground launch starts before contact case", not started.is_empty())
	var tick := 240
	var all_events: Array[Dictionary] = []
	tick += 1
	all_events.append_array(detector.observe(_sample(tick, {
		"supported": true, "intended_support": true, "ground_contact": true,
	})))
	for i in 120:
		tick += 1
		all_events.append_array(detector.observe(_sample(tick, {
			"supported": true, "intended_support": true, "ground_contact": true,
		})))
	for i in 480:
		tick += 1
		all_events.append_array(detector.observe(_sample(tick, {
			"clearance_ok": true,
		})))
	var touch_and_go_events := _events_of(all_events, "landing")
	_check("controlled support and confirmed re-ascent resolve one touch-and-go",
		touch_and_go_events.size() == 1
			and touch_and_go_events[0].get("kind", "") == "touch_and_go"
			and touch_and_go_events[0].get("outcome", "") == "success"
			and int(touch_and_go_events[0].flight.touch_and_go) == 1)

	var stop_events: Array[Dictionary] = []
	tick += 1
	stop_events.append_array(detector.observe(_sample(tick, {
		"supported": true, "intended_support": true, "ground_contact": true,
	})))
	for i in 604:
		tick += 1
		stop_events.append_array(detector.observe(_sample(tick, {
			"supported": true, "intended_support": true, "stop_support": true,
			"ground_contact": true,
		})))
	var stop_landings := _events_of(stop_events, "landing")
	var closed := _first_event(stop_events, "closed")
	_check("stable three-contact full stop completes once",
		stop_landings.size() == 1 and stop_landings[0].get("kind", "") == "full_stop"
			and stop_landings[0].get("outcome", "") == "success"
			and closed.get("outcome", "") == "completed")
	if not closed.is_empty():
		_check("touch-and-go is a subset of a single sortie", int(closed.flight.touch_and_go) == 1
			and int(closed.flight.full_stops) == 1)
	_check("full stop leaves no active flight", detector.flight.is_empty())


func _test_incident_and_unresolved_episode() -> void:
	var detector: RefCounted = Detector.new()
	detector.configure(_profile())
	_start_flight(detector)
	var tick := 240
	detector.observe(_sample(241, {"incident": true}))
	for i in 601:
		tick += 1
		var supported := tick > 241
		var observed: Array[Dictionary] = detector.observe(_sample(tick, {
			"supported": supported,
			"intended_support": supported,
			"stop_support": supported,
			"ground_contact": supported,
		}))
		if not observed.is_empty():
			var close := _first_event(observed, "closed")
			if not close.is_empty():
				var landing := _first_event(observed, "landing")
				_check("incident latch makes later full stop a failed landing",
					landing.get("outcome", "") == "failed" and close.get("outcome", "") == "damaged_stop")
				_check("incident closure preserves one failed count", int(close.flight.failed_landings) == 1)
				break

	var unresolved: RefCounted = Detector.new()
	var unavailable := _profile()
	unavailable.landing_available = false
	unavailable.main_indices = PackedInt32Array()
	unavailable.stop_indices = PackedInt32Array()
	unresolved.configure(unavailable)
	_start_flight(unresolved)
	var events: Array[Dictionary] = []
	events.append_array(unresolved.observe(_sample(241, {
		"supported": true, "ground_contact": true,
	})))
	var ended: Array[Dictionary] = unresolved.end("interrupted")
	var unknown := _first_event(ended, "landing")
	_check("unresolved unmapped contact becomes unknown on end",
		unknown.get("outcome", "") == "unknown" and unknown.flight.unknown_landings == 1)
	_check("unknown contact closes as interrupted", _first_event(ended, "closed").outcome == "interrupted")


func _test_duplicate_terminal_and_ground_crash() -> void:
	var detector: RefCounted = Detector.new()
	detector.configure(_profile())
	_start_flight(detector)
	var before := float(detector.flight.airborne_seconds)
	detector.observe(_sample(241))
	var after_one := float(detector.flight.airborne_seconds)
	detector.observe(_sample(241, {"incident": true}))
	var after_duplicate := float(detector.flight.airborne_seconds)
	_check("duplicate accepted tick does not accumulate flight time twice",
		absf((after_one - before) - DT) < 1e-9 and absf(after_duplicate - after_one) < 1e-12)
	var crash_events: Array[Dictionary] = detector.observe(_sample(242, {"terminal": true, "ground_contact": false}))
	var duplicate_crash: Array[Dictionary] = detector.observe(_sample(242, {"terminal": true, "ground_contact": false}))
	_check("terminal crash emits once per configured generation",
		_events_of(crash_events, "crash").size() == 1 and _events_of(duplicate_crash, "crash").is_empty())
	_check("airborne terminal impact is not classified as a ground crash",
		bool(_first_event(crash_events, "crash").get("ground", true)) == false)
	_check("terminal crash closes the active flight as crashed",
		_first_event(crash_events, "closed").get("outcome", "") == "crashed")

	var ground: RefCounted = Detector.new()
	ground.configure(_profile())
	var ground_events: Array[Dictionary] = ground.observe(_sample(1, {
		"supported": true, "ground_contact": true, "terminal": true,
	}))
	_check("taxi crash counts as one ground crash without a flight start",
		bool(_first_event(ground_events, "crash").get("ground", false))
			and _events_of(ground_events, "started").is_empty())


func _test_gap_marks_partial_and_freezes_time() -> void:
	var detector: RefCounted = Detector.new()
	detector.configure(_profile())
	_start_flight(detector)
	detector.observe(_sample(242))
	var after_gap := float(detector.flight.airborne_seconds)
	detector.observe(_sample(243))
	_check("tick gap marks the active observation partial and freezes duration",
		not bool(detector.flight.complete_observation)
			and absf(float(detector.flight.airborne_seconds) - after_gap) < 1e-12)
	var ended: Array[Dictionary] = detector.end("interrupted")
	var closed := _first_event(ended, "closed")
	_check("interrupted close carries partial-coverage state",
		closed.get("outcome", "") == "interrupted" and not bool(closed.flight.complete_observation))


func _test_speed_window_filters_spikes() -> void:
	var detector: RefCounted = Detector.new()
	detector.configure(_profile())
	for tick in range(1, 241):
		detector.observe(_sample(tick, {"clearance_ok": true}))
	for tick in range(241, 501):
		var tas := 500.0 if tick == 260 else 20.0
		var sample := _sample(tick, {
			"tas": tas,
			"groundspeed": 20.0,
			"ground_speed_3d": 20.0,
			"position": PackedFloat64Array([20.0 * float(tick) * DT, 0.0, 0.0]),
			"velocity_ned": PackedFloat64Array([20.0, 0.0, 0.0]),
		})
		detector.observe(sample)
	_check("sustained speed window accepts valid TAS and horizontal groundspeed",
		absf(float(detector.flight.get("max_tas_mps", -1.0)) - 20.0) < 1e-9
			and absf(float(detector.flight.get("max_groundspeed_mps", -1.0)) - 20.0) < 1e-9)
	_check("one-tick outlier cannot become the maximum", float(detector.flight.max_tas_mps) < 100.0)
	var invalid := _sample(501, {"tas": NAN})
	detector.observe(invalid)
	var encoded := JSON.stringify(detector.snapshot())
	_check("snapshot remains JSON-safe after a non-finite speed sample",
		not encoded.contains("NaN") and typeof(JSON.parse_string(encoded)) == TYPE_DICTIONARY)


func _test_json_safe_snapshot_restore() -> void:
	var original: RefCounted = Detector.new()
	original.configure(_profile())
	_start_flight(original)
	for tick in range(241, 310):
		original.observe(_sample(tick, {
			"tas": 18.0,
			"groundspeed": 18.0,
			"ground_speed_3d": 18.0,
			"position": PackedFloat64Array([18.0 * float(tick) * DT, 0.0, 0.0]),
			"velocity_ned": PackedFloat64Array([18.0, 0.0, 0.0]),
		}))
	var snapshot: Dictionary = original.snapshot()
	var encoded := JSON.stringify(snapshot)
	var decoded: Variant = JSON.parse_string(encoded)
	var restored: RefCounted = Detector.new()
	var restore_ok: bool = typeof(decoded) == TYPE_DICTIONARY and bool(restored.call("restore", decoded))
	_check("JSON-round-tripped active state restores", restore_ok,
		"snapshot validation=%s" % str(restored._valid_snapshot(decoded)) if typeof(decoded) == TYPE_DICTIONARY else "snapshot is not a dictionary")
	var rejected: RefCounted = Detector.new()
	var invalid: Dictionary = decoded.duplicate(true)
	invalid.flight.airborne_seconds = NAN
	_check("restore rejects non-finite snapshot values without partial mutation",
		not rejected.restore(invalid) and rejected.flight.is_empty())
	var next_tick := 310
	var next_sample := _sample(next_tick, {
		"tas": 18.0,
		"groundspeed": 18.0,
		"ground_speed_3d": 18.0,
		"position": PackedFloat64Array([18.0 * float(next_tick) * DT, 0.0, 0.0]),
		"velocity_ned": PackedFloat64Array([18.0, 0.0, 0.0]),
	})
	original.observe(next_sample)
	if restore_ok:
		restored.observe(next_sample)
		_check("restored detector resumes with the same duration and speed state",
			absf(float(original.flight.airborne_seconds) - float(restored.flight.airborne_seconds)) < 1e-12
				and float(original.flight.max_tas_mps) == float(restored.flight.max_tas_mps))
