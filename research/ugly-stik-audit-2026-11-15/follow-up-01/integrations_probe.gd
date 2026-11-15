## Read-only Electric 6S statistics integration probe, external to the project.
## It does not register a statistics profile or create evidence files.
extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const ContactContract := preload("res://physics/aircraft_contact_contract.gd")
const Profiles := preload("res://statistics/profiles.gd")
const Detector := preload("res://statistics/detector.gd")

const ID := "stik-electric-6s"
const DT := 1.0 / 240.0
const EXPECTED_HASH := {
	"ideal": "830137e2daaf43295c404ad0af6676ac44a8fb0102c2d2b81c2c0b4a395337e6",
	"pack": "fbbfd74512b8e3141adc530296687721c5ca7e3d94a38c384fbaf10f03c2c73e",
}
const REVIEW := {
	"span_m": 1.524,
	"main_ids": ["contact_main_left", "contact_main_right"],
	"stop_ids": ["contact_main_left", "contact_main_right", "contact_nose"],
	"points": {
		"contact_main_left": [-0.0941, -0.18, 0.25778446764371277],
		"contact_main_right": [-0.0941, 0.18, 0.25778446764371277],
		"contact_nose": [0.257176, 0.0, 0.2546094676437128],
	},
}

var failures := 0
var checks := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _sample(tick: int, changes: Dictionary = {}) -> Dictionary:
	var value := {
		"tick": tick, "dt": DT, "supported": false, "intended_support": false,
		"stop_support": false, "clearance_ok": false, "controlled": true,
		"ground_speed_3d": 0.0, "angular_speed": 0.0, "tas": 0.0, "groundspeed": 0.0,
		"position": PackedFloat64Array([0.0, 0.0, 0.0]),
		"velocity_ned": PackedFloat64Array([0.0, 0.0, 0.0]),
		"incident": false, "terminal": false, "ground_contact": false, "valid": true,
	}
	value.merge(changes, true)
	return value


func _events(events: Array[Dictionary], event_type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in events:
		if event.get("type") == event_type:
			result.append(event)
	return result


func _check_detector(label: String, profile: Dictionary, reviewed: bool) -> void:
	# Synthetic detector samples, not a simulated or human-piloted landing. The
	# unsupported profile receives the false support roles its adapter would emit.
	var detector := Detector.new()
	detector.configure(profile)
	var observed: Array[Dictionary] = []
	for tick in range(1, 241):
		observed.append_array(detector.observe(_sample(tick, {"clearance_ok": true})))
	_check(label + " starts synthetic flight", _events(observed, "started").size() == 1)
	for tick in range(241, 902):
		observed.append_array(detector.observe(_sample(tick, {
			"supported": true, "ground_contact": true,
			"intended_support": reviewed, "stop_support": reviewed,
		})))
	var landings := _events(observed, "landing")
	if reviewed:
		_check(label + " candidate synthetic full stop succeeds", landings.size() == 1 \
			and landings[0].get("kind") == "full_stop" and landings[0].get("outcome") == "success", str(landings))
		var closed := _events(observed, "closed")
		_check(label + " candidate closes completed", closed.size() == 1 and closed[0].get("outcome") == "completed", str(closed))
	else:
		_check(label + " unsupported synthetic clean stop stays unresolved", landings.is_empty(), str(landings))
		var ended := detector.end("abandoned")
		landings = _events(ended, "landing")
		_check(label + " unresolved episode ends unknown", landings.size() == 1 \
			and landings[0].get("outcome") == "unknown" \
			and landings[0].get("kind") == "ended_before_resolution", str(landings))


func _initialize() -> void:
	for mode: String in ["ideal", "pack"]:
		var path := Catalog.data_for(ID, mode)
		var loaded: Dictionary = AircraftData.load_file(path)
		_check(mode + " aircraft loads", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
		if not loaded.get("ok", false):
			continue
		var model: Dictionary = loaded.model
		var bindings: Dictionary = ContactContract.describe(model, true)
		var existing: Dictionary = Profiles.resolve(ID, model, bindings)
		var map: Dictionary = Profiles._validated_contact_map(model, bindings, REVIEW)
		var donor: Dictionary = Profiles._PROFILES["jensen-das-ugly-stik-60"]
		_check(mode + " accepted byte hash", loaded.get("input_identity", {}).get("sha256") == EXPECTED_HASH[mode])
		_check(mode + " has matching ID and span", model.id == ID and absf(float(model.reference.b) - REVIEW.span_m) <= 1e-6)
		_check(mode + " physical wheel profile and bindings", model.get("wheel_profile", {}).get("status") == "applied" \
			and model.wheel_profile.get("aircraft_id") == ID and bool(bindings.get("ok", false)), str(bindings.get("errors", [])))
		_check(mode + " currently unreviewed", not existing.get("landing_available", true) \
			and existing.get("reason") == "unreviewed_aircraft_profile", str(existing))
		_check(mode + " candidate support map validates", map.size() == 3, str(map))
		_check(mode + " basic donor geometry is refused", Profiles._validated_contact_map(model, bindings, donor).is_empty())
		if map.size() != 3:
			continue
		var pitch := Profiles._rest_pitch(REVIEW, map)
		var height := Profiles._rest_height(REVIEW, map, pitch)
		_check(mode + " expected rest pitch", absf(pitch - -0.009038230749287) < 1e-11, str(pitch))
		_check(mode + " expected rest height", absf(height - 0.256923452624336) < 1e-11, str(height))
		var candidate := existing.duplicate(true)
		candidate.landing_available = true
		candidate.reason = ""
		candidate.main_ids = REVIEW.main_ids.duplicate()
		candidate.stop_ids = REVIEW.stop_ids.duplicate()
		candidate.main_indices = PackedInt32Array([int(map.contact_main_left.index), int(map.contact_main_right.index)])
		candidate.stop_indices = PackedInt32Array([int(map.contact_main_left.index), int(map.contact_main_right.index), int(map.contact_nose.index)])
		candidate.rest_pitch_rad = pitch
		candidate.rest_height_m = height
		print("AUDIT_FOLLOWUP_SOURCE ", mode, " ", JSON.stringify({"path": path, "hash": loaded.input_identity.sha256,
			"mass_kg": model.mass_kg, "cg_le": Array(model.cg_le), "support_map": map,
			"rest_pitch_rad": pitch, "rest_height_m": height, "clearance_m": existing.clearance_m}, "", true, true))
		_check_detector(mode + " existing", existing, false)
		_check_detector(mode + " hypothetical candidate", candidate, true)
	print("AUDIT_FOLLOWUP_DONE checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
