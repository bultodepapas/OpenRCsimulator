extends SceneTree

const Session = preload("res://sim/ground_vehicle/session.gd")
const VehicleDynamics = preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const Damage = preload("res://physics/ground_vehicle/vehicle_damage.gd")
const NEUTRAL := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}
var failures := 0

class ImpactSession extends Session:
	var entry_speed := 8.0
	func _make_road(_course_value: Dictionary) -> Callable:
		return func(_north: float, _east: float) -> Dictionary:
			return {"height_m": 0.0, "normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
				"mu": 0.85, "rolling": 1.0, "surface_id": "asphalt", "walls": [{
					"id": "impact-fixture", "north_min_m": 4.0, "north_max_m": 4.5,
					"east_min_m": -5.0, "east_max_m": 5.0, "bottom_up_m": 0.0,
					"top_up_m": 1.0, "mu": 0.5}]}
	func _make_spawn_state(model: Dictionary, _course_value: Dictionary, _pose: Dictionary,
			road: Callable, _pose_up_delta_m: float) -> PackedFloat64Array:
		var initialized: Dictionary = VehicleDynamics.initialize(model, road, 0.0, 0.0)
		if not initialized.ok:
			return PackedFloat64Array()
		var value: PackedFloat64Array = initialized.state
		value[VehicleDynamics.VEL] = entry_speed
		for i in 4:
			value[VehicleDynamics.WHEEL_SPIN + i] = entry_speed / float(model.tire_radius_m)
		return value

func _initialize() -> void:
	call_deferred("_run")

func _report(label: String, value: Variant) -> void:
	print(label, ": ", value)

func _check(label: String, passed: bool) -> void:
	print(("PASS: " if passed else "FAIL: ") + label)
	if not passed:
		failures += 1

func _run() -> void:
	var source = ImpactSession.new()
	if not source.prepare_default() or not source.tick_once(NEUTRAL) or not source.resume():
		_report("setup", "failed")
		quit(1)
		return
	var checkpoint: Dictionary = {}
	for _index in 240:
		if not source.tick_once(NEUTRAL):
			break
		var telemetry: Dictionary = source.telemetry_snapshot()
		if int(telemetry.get("wall_contact_count", 0)) > 0 and source.damage_visual_state().body_damage > 0.0:
			var requested := NEUTRAL.duplicate()
			requested.throttle = 0.8
			if source.tick_once(requested):
				checkpoint = source.checkpoint()
			break
	if checkpoint.is_empty():
		_report("setup", "no damaged wall-contact checkpoint")
		quit(1)
		return
	var original_applied: PackedFloat64Array = source._decode_float64_blob(checkpoint.applied_controls_f64_base64, 4)
	var changed := checkpoint.duplicate(true)
	var changed_applied: PackedFloat64Array = original_applied.duplicate()
	changed_applied[0] = 0.0
	changed.applied_controls_f64_base64 = source._base64_bytes(changed_applied.to_byte_array())
	changed.checkpoint_sha256 = source._checkpoint_hash(changed)
	var reference = ImpactSession.new()
	var altered = ImpactSession.new()
	var prepared := reference.prepare_default() and altered.prepare_default()
	var restored_original := prepared and reference.restore_checkpoint(checkpoint)
	var accepts_changed := prepared and altered.can_restore_checkpoint(changed)
	var restored_changed := accepts_changed and altered.restore_checkpoint(changed)
	_report("tick", checkpoint.get("tick", -1))
	_report("damage", checkpoint.get("damage_state", []))
	_report("requested", checkpoint.get("last_controls", {}))
	_report("original_applied", original_applied)
	_report("tampered_applied", changed_applied)
	_report("restore_original_and_tampered", [restored_original, accepts_changed, restored_changed])
	_check("original checkpoint restores while rehashed under-bound throttle is rejected",
		restored_original and not accepts_changed and not restored_changed)
	reference.free()
	altered.free()
	source.free()
	var recording_session = Session.new()
	var recording_prepared := recording_session.prepare_default() and recording_session.start_recording()
	var armed := recording_prepared and recording_session.tick_once(NEUTRAL) and recording_session.resume()
	var invalid_sample := {"throttle": NAN, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}
	var rejected := armed and not recording_session.tick_once(invalid_sample)
	var remains_recording: bool = recording_session.recording
	var faulted_metadata: Dictionary = recording_session._recording_metadata()
	_report("fault_recording_setup_rejected_sample_active", [recording_prepared, armed, rejected, remains_recording])
	_report("fault_interrupted_prefix", [faulted_metadata.get("run_valid"), faulted_metadata.get("events"),
		faulted_metadata.get("recorded_tick_count"), faulted_metadata.get("sample_count")])
	var events: Variant = faulted_metadata.get("events", [])
	var interrupted := false
	for event: Variant in events:
		if typeof(event) == TYPE_DICTIONARY and event.get("type") == "recording_interrupted":
			interrupted = true
	_check("fail-safe stops recording and preserves an invalid interrupted prefix",
		recording_prepared and armed and rejected and not remains_recording
		and not bool(faulted_metadata.get("run_valid", true))
		and int(faulted_metadata.get("recorded_tick_count", -1)) == 0
		and int(faulted_metadata.get("sample_count", 0)) == 1 and interrupted)
	recording_session.free()
	var recovered = Session.new()
	var recovered_ok := recovered.prepare_default() and recovered.tick_once(NEUTRAL) and recovered.manual_recovery()
	var recovered_checkpoint: Dictionary = recovered.checkpoint() if recovered_ok else {}
	var relabeled_checkpoint := recovered_checkpoint.duplicate(true)
	relabeled_checkpoint.run_valid = true
	relabeled_checkpoint.checkpoint_sha256 = recovered._checkpoint_hash(relabeled_checkpoint)
	_report("recovery_checkpoint_provenance", [recovered_ok, recovered_checkpoint.get("run_valid"),
		recovered_checkpoint.get("recovery_actions", []), recovered.can_restore_checkpoint(relabeled_checkpoint)])
	_check("manual recovery cannot be relabeled as a valid run",
		recovered_ok and not recovered.can_restore_checkpoint(relabeled_checkpoint))
	var missing_event := recovered_checkpoint.duplicate(true)
	missing_event.event_tape = []
	missing_event.event_tape_sha256 = recovered._hash_variant([])
	missing_event.checkpoint_sha256 = recovered._checkpoint_hash(missing_event)
	_check("manual recovery action must remain in checkpoint history",
		recovered_ok and not recovered.can_restore_checkpoint(missing_event))
	recovered.free()
	_report("checks", [3 - failures, 3])
	quit(1 if failures else 0)
