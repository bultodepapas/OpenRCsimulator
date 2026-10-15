extends SceneTree

const Session = preload("res://sim/ground_vehicle/session.gd")
const VehicleDynamics = preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const Damage = preload("res://physics/ground_vehicle/vehicle_damage.gd")
const NEUTRAL := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}

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
	if restored_original and restored_changed:
		var same := true
		var first_difference_tick := -1
		var original_wall_power := float(reference.last_telemetry.get("wall_friction_power_w", 0.0))
		var altered_wall_power := float(altered.last_telemetry.get("wall_friction_power_w", 0.0))
		for i in 120:
			var control := {"throttle": 0.8, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}
			if not reference.tick_once(control) or not altered.tick_once(control):
				same = false
				first_difference_tick = i
				break
			if reference.damage_snapshot().to_byte_array() != altered.damage_snapshot().to_byte_array():
				same = false
				first_difference_tick = i + 1
				break
		_report("wall_friction_power_restored", [original_wall_power, altered_wall_power])
		_report("damage_identical_after_120_ticks", same)
		_report("first_damage_difference_after_checkpoint_ticks", first_difference_tick)
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
	_report("fault_recording_export_status_before_fix", [faulted_metadata.get("run_valid"), faulted_metadata.get("events"),
		faulted_metadata.get("recorded_tick_count"), faulted_metadata.get("sample_count")])
	recording_session.free()
	var recovered = Session.new()
	var recovered_ok := recovered.prepare_default() and recovered.tick_once(NEUTRAL) and recovered.manual_recovery()
	var recovered_checkpoint: Dictionary = recovered.checkpoint() if recovered_ok else {}
	var relabeled_checkpoint := recovered_checkpoint.duplicate(true)
	relabeled_checkpoint.run_valid = true
	relabeled_checkpoint.checkpoint_sha256 = recovered._checkpoint_hash(relabeled_checkpoint)
	_report("recovery_checkpoint_provenance", [recovered_ok, recovered_checkpoint.get("run_valid"),
		recovered_checkpoint.get("recovery_actions", []), recovered.can_restore_checkpoint(relabeled_checkpoint)])
	recovered.free()
	quit(0)
