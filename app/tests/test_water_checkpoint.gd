## LU-27: preserve water-only aftermath across the real paired Main checkpoint boundary.
extends SceneTree

const Main = preload("res://main.gd")
const ImpactSnapshot = preload("res://physics/impact_snapshot.gd")
const VisualCheckpoint = preload("res://app_state/visual_checkpoint.gd")
const LakeWorld = preload("res://render/lake/lake_world.gd")
const WaterEffects = preload("res://render/lake/water_effects.gd")

class TestFlight extends Main:
	pass

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL " + label)


func _run() -> void:
	var flight := TestFlight.new()
	flight.interactive_start = true
	root.add_child(flight)
	flight.set_process(false)
	await process_frame
	if flight.session == null or flight._crash_director == null:
		_check("production Main fixture starts with lake crash director", false)
		flight.free()
		quit(1)
		return
	flight.session.set_physics_process(false)
	flight.session.sim.set_physics_process(false)
	flight.session.input_enabled = false
	_check("Main loaded a configured normalized lake", not flight.session.lake_context().is_empty()
		and flight._crash_director.water_effects._configured)
	var dry_checkpoint: Dictionary = flight.checkpoint()
	_check("ordinary checkpoints keep the original paired schema", dry_checkpoint.get("format", "") == VisualCheckpoint.FORMAT
		and dry_checkpoint.size() == 5)

	var lake_ambience: AudioStreamPlayer3D = LakeWorld.ambience_player(flight._field_node)
	_check("field exposes its single water ambience player", lake_ambience != null)
	if lake_ambience != null and flight._soundscape_audio != null:
		var buses: Variant = flight._soundscape_audio.soundscape.get("_bus_names")
		_check("water ambience uses the scene-local OpenRC Environment mixer bus",
			buses is Array and buses.size() >= 3 and lake_ambience.bus == StringName(buses[2])
				and AudioServer.get_bus_index(lake_ambience.bus) >= 0)
	else:
		_check("soundscape provides an environment bus for the water ambience", false)

	var hit := _water_impact(flight.session)
	flight.session.crash = {"impact": hit, "why": "water checkpoint fixture", "ticks_left": 20}
	flight._crash_director.update(0.0)
	flight._crash_director.update(0.37)
	var water_checkpoint: Dictionary = flight.checkpoint()
	_check("active water aftermath gets a versioned outer envelope",
		water_checkpoint.get("format", "") == "openrc-visual-water-checkpoint v1"
			and water_checkpoint.has("visual") and water_checkpoint.has("water_render"))
	_check("water render state records elapsed effect phase and one emitted splash",
		float(water_checkpoint.get("water_render", {}).get("effects", {}).get("elapsed_s", -1.0)) > 0.2
			and water_checkpoint.water_render.effects.impact_audio_emitted
			and water_checkpoint.water_render.event_count == 1)
	var native_copy: Dictionary = bytes_to_var(var_to_bytes(water_checkpoint))
	_check("water envelope survives native Variant serialization", native_copy == water_checkpoint)

	var before_bad_physics: PackedByteArray = var_to_bytes(flight.session.checkpoint())
	var before_bad_effect: Dictionary = flight._crash_director.water_effects.checkpoint()
	var bad_hash := native_copy.duplicate(true)
	bad_hash.water_render.effects.elapsed_s = 0.5
	_check("tampered water envelope is rejected before physics mutation",
		not flight.restore_checkpoint(bad_hash).get("ok", false)
			and var_to_bytes(flight.session.checkpoint()) == before_bad_physics)
	var bad_effect := native_copy.duplicate(true)
	bad_effect.water_render.effects.elapsed_s = NAN
	bad_effect.payload_sha256 = flight._water_checkpoint_digest(bad_effect.visual, bad_effect.water_render)
	_check("invalid effect phase is rejected transactionally after valid outer rehash",
		not flight.restore_checkpoint(bad_effect).get("ok", false)
			and var_to_bytes(flight.session.checkpoint()) == before_bad_physics
			and flight._crash_director.water_effects.checkpoint() == before_bad_effect)

	flight.session.reset()
	var restored: Dictionary = flight.restore_checkpoint(native_copy)
	_check("real Main restores paired physics plus render-only water aftermath", restored.get("ok", false)
		and flight.session.crash.is_empty() and flight._crash_director.active
		and flight._crash_director._water_active and flight._crash_director._water_checkpoint_latched)
	var restored_effects: WaterEffects = flight._crash_director.water_effects
	var sink_progress := smoothstep(0.0, 1.0, restored_effects._elapsed_s / WaterEffects.SINK_DURATION_S)
	var expected_sink := Transform3D(
		restored_effects._aircraft_base_transform.basis * Basis(Vector3.RIGHT, deg_to_rad(5.0) * sink_progress),
		restored_effects._aircraft_base_transform.origin - Vector3.UP * WaterEffects.SINK_DEPTH_M * sink_progress)
	_check("restore retains local effect phase, sink pose, and impact point",
		flight._crash_director.water_effects.checkpoint().elapsed_s == native_copy.water_render.effects.elapsed_s
			and flight._crash_director.report.contact_point_world == native_copy.water_render.impact_point_world
			and flight._airplane.root.global_transform.is_equal_approx(expected_sink))
	_check("restore never requests or plays a second splash voice",
		flight._crash_director.water_effects._impact_audio_requests_this_event == 0
			and not flight._crash_director.water_effects._impact_voice.playing
			and flight._crash_director.stats().water_event_count == 1)

	var elapsed_before_hold: float = flight._crash_director.water_effects._elapsed_s
	flight.session.hold("water-checkpoint-test")
	flight._process(0.1)
	flight._crash_director.update(0.1)
	_check("user holds pause the restored water effect and localized ambience",
		flight._crash_director.water_effects._elapsed_s == elapsed_before_hold
			and lake_ambience != null and lake_ambience.stream_paused)
	flight.session.release("water-checkpoint-test")
	flight._process(0.1)
	flight._crash_director.update(0.1)
	_check("restored aftermath resumes without replaying the splash",
		flight._crash_director.water_effects._elapsed_s > elapsed_before_hold
			and lake_ambience != null and not lake_ambience.stream_paused
			and flight._crash_director.water_effects._impact_audio_requests_this_event == 0)

	_check("dry checkpoint restore clears water aftermath and restores ordinary paired identity",
		flight.restore_checkpoint(dry_checkpoint).get("ok", false)
			and not flight._crash_director.active and not flight._crash_director.water_effects._has_event
			and flight.checkpoint().get("format", "") == VisualCheckpoint.FORMAT)

	flight._crash_director.update(0.0)
	var dry_hit := _impact(flight.session, "hull_contact", PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, 16.0]))
	flight.session.crash = {"impact": dry_hit, "why": "dry transition fixture", "ticks_left": 20}
	flight._crash_director.update(1.0 / 60.0)
	_check("water checkpoint restore leaves the next dry impact on its normal director path",
		flight._crash_director.active and not flight._crash_director._water_active
			and flight._crash_director.report.get("trigger", "") == "hull_contact"
			and flight._crash_director.wreck.stats().started)

	flight.session.reset()
	flight.recorder.detach()
	if lake_ambience != null:
		lake_ambience.stop()
		lake_ambience.stream = null
	flight.free()
	await process_frame
	await process_frame
	print("LU-27 water checkpoint: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _water_impact(session: Node) -> ImpactSnapshot.Snapshot:
	return _impact(session, "water", PackedFloat64Array([110.0, 125.0, 0.80]),
		PackedFloat64Array([0.0, 0.0, 18.0]))


func _impact(session: Node, trigger: String, point: PackedFloat64Array,
		velocity: PackedFloat64Array) -> ImpactSnapshot.Snapshot:
	var snapshot := ImpactSnapshot.Snapshot.new()
	snapshot.trigger = trigger
	snapshot.tick = int(session.sim.tick) + 1
	snapshot.detected_state = session.sim.state.duplicate()
	snapshot.has_kinematics = true
	snapshot.point_ned = point
	snapshot.velocity_ned = velocity
	snapshot.speed_mps = sqrt(velocity[0] * velocity[0] + velocity[1] * velocity[1] + velocity[2] * velocity[2])
	snapshot.down_speed_mps = velocity[2]
	return snapshot
