## RCV-38 native production activity captures for Monster Car 2 lighting.
## Native capture from the repository root:
## .tools/Godot_v4.7.2-stable_win64_console.exe --path app --script
## ../research/rc-monster-truck/monster-car-2/rcv38/capture_lights.gd -- --output=<existing-absolute-directory>
## Parse only with --headless --check-only; this mode creates no Activity or captures.
extends SceneTree

const Activity := preload("res://vehicles/ground/ground_scene.gd")
const LightingConfig := preload("res://environment/time_of_day_config.gd")
const GROUND_SCENE_PATH := "res://vehicles/ground/ground_scene.gd"
const GROUND_EFFECTS_PATH := "res://vehicles/ground/ground_effects.gd"
const NITRO_LIGHTS_PATH := "res://vehicles/ground/monster_car_2_lights.gd"
const NEUTRAL_CONTROLS := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}
const BRAKE_PROBE_CONTROLS := {"throttle": 0.0, "steering": 0.0, "brake": 1.0, "reverse": false, "armed": true}
const OBSERVE_BENCH_RUNS: int = 5
const OBSERVE_BENCH_WARMUP_CALLS: int = 500
const OBSERVE_BENCH_CALLS: int = 4000

var output_directory := ""
var captures: Array[Dictionary] = []
var failure_messages: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	for argument in user_args:
		if argument.begins_with("--output="):
			output_directory = argument.trim_prefix("--output=")
	if output_directory.is_empty() or not DirAccess.dir_exists_absolute(output_directory):
		_fail("Provide --output=<existing absolute directory>")
		return
	TranslationServer.set_locale("en")
	root.size = Vector2i(1440, 900)
	var night_preset: Dictionary = LightingConfig.preset(LightingConfig.defaults(), "night")
	if night_preset.get("ok") != true:
		_fail("Night lighting preset failed: " + str(night_preset.get("errors", [])))
		return
	var night_config: Dictionary = (night_preset.get("config", {}) as Dictionary).duplicate(true)
	var night_activity = _new_activity(night_config)
	await process_frame
	if not _prepare_parked_activity(night_activity, "night"):
		_night_cleanup(night_activity)
		return
	var observer: Variant = _lighting_observer(night_activity)
	if observer == null or not observer is Object or not observer.has_method("observe"):
		_fail("Production NitroLights observer is unavailable")
		_night_cleanup(night_activity)
		return
	if not observer.has_method("diagnostic_snapshot"):
		_fail("Production NitroLights diagnostic_snapshot() is unavailable")
		_night_cleanup(night_activity)
		return

	# The initial production garage state is captured before any presentation controls change.
	if not await _capture(night_activity, "night-garage", "front34", NEUTRAL_CONTROLS, false):
		_night_cleanup(night_activity)
		return
	night_activity.dashboard.set_menu(false)

	if not _set_light_state(night_activity, false, false, false):
		_fail("Could not set every night light off")
		_night_cleanup(night_activity)
		return
	if not await _capture(night_activity, "lamps-all-off", "front34", NEUTRAL_CONTROLS, false):
		_night_cleanup(night_activity)
		return

	if not _set_light_state(night_activity, true, false, false):
		_fail("Could not select low beams without auxiliary lights")
		_night_cleanup(night_activity)
		return
	if not await _capture(night_activity, "lamps-low-beams", "front34", NEUTRAL_CONTROLS, false):
		_night_cleanup(night_activity)
		return

	if not _set_light_state(night_activity, true, true, false):
		_fail("Could not enable auxiliary lights")
		_night_cleanup(night_activity)
		return
	if not await _capture(night_activity, "lamps-auxiliary-on", "front34", NEUTRAL_CONTROLS, false):
		_night_cleanup(night_activity)
		return

	if not _set_light_state(night_activity, false, false, false):
		_fail("Could not isolate the rear stop lights")
		_night_cleanup(night_activity)
		return
	if not await _capture(night_activity, "rear-stop-off", "rear34", NEUTRAL_CONTROLS, false):
		_night_cleanup(night_activity)
		return
	if not await _capture(night_activity, "rear-stop-on", "rear34", BRAKE_PROBE_CONTROLS, true):
		_night_cleanup(night_activity)
		return

	if not await _capture(night_activity, "side-neon-off", "low-side", NEUTRAL_CONTROLS, false):
		_night_cleanup(night_activity)
		return
	if not _set_light_state(night_activity, false, false, true):
		_fail("Could not enable side neon lights")
		_night_cleanup(night_activity)
		return
	if not await _capture(night_activity, "side-neon-on", "low-side", NEUTRAL_CONTROLS, false):
		_night_cleanup(night_activity)
		return

	if not _set_light_state(night_activity, false, false, false):
		_fail("Could not disable lamps for the road-beam overview baseline")
		_night_cleanup(night_activity)
		return
	if not await _capture(night_activity, "road-beam-overview-all-off", "road-overview", NEUTRAL_CONTROLS, false):
		_night_cleanup(night_activity)
		return
	if not _set_light_state(night_activity, true, true, false):
		_fail("Could not enable road beams for the overview")
		_night_cleanup(night_activity)
		return
	if not await _capture(night_activity, "road-beam-overview", "road-overview", NEUTRAL_CONTROLS, false):
		_night_cleanup(night_activity)
		return

	var lighting_benchmark: Dictionary = _benchmark_observer(night_activity)
	# Restore the actual Activity selections after direct stable/toggled observer timings.
	night_activity._last_controls = NEUTRAL_CONTROLS.duplicate(true)
	night_activity._process(0.0)
	if not lighting_benchmark.get("observer_preserves_accepted_body_snapshot", false):
		_fail("Direct lighting observer calls changed accepted physics state")
		_night_cleanup(night_activity)
		return
	var night_effects_snapshot: Dictionary = _safe_dictionary(night_activity._effects.call("diagnostic_snapshot"))
	var night_body_token: Dictionary = _accepted_body_token(night_activity)
	var night_paused: bool = night_activity.session.paused
	var night_tick: int = night_activity.session.tick
	var night_effect_state: Dictionary = _light_state(night_activity)
	var night_observer_diagnostic: Dictionary = _observer_diagnostic(night_activity)
	night_activity.queue_free()
	await process_frame

	var day_preset: Dictionary = LightingConfig.preset(LightingConfig.defaults(), "noon")
	if day_preset.get("ok") != true:
		_fail("Day lighting preset failed: " + str(day_preset.get("errors", [])))
		return
	var day_config: Dictionary = (day_preset.get("config", {}) as Dictionary).duplicate(true)
	var day_activity = _new_activity(day_config)
	await process_frame
	if not _prepare_parked_activity(day_activity, "day"):
		_night_cleanup(day_activity)
		return
	var day_observer: Variant = _lighting_observer(day_activity)
	if day_observer == null or not day_observer is Object or not day_observer.has_method("observe") \
			or not day_observer.has_method("diagnostic_snapshot"):
		_fail("Daytime production NitroLights observer is unavailable")
		_night_cleanup(day_activity)
		return
	day_activity.dashboard.set_menu(false)
	if not _set_light_state(day_activity, true, false, false):
		_fail("Could not set the daytime front comparison")
		_night_cleanup(day_activity)
		return
	if not await _capture(day_activity, "day-front", "front34", NEUTRAL_CONTROLS, false):
		_night_cleanup(day_activity)
		return
	var day_effects_snapshot: Dictionary = _safe_dictionary(day_activity._effects.call("diagnostic_snapshot"))
	var day_body_token: Dictionary = _accepted_body_token(day_activity)
	var day_paused: bool = day_activity.session.paused
	var day_tick: int = day_activity.session.tick
	var day_effect_state: Dictionary = _light_state(day_activity)
	var day_observer_diagnostic: Dictionary = _observer_diagnostic(day_activity)
	day_activity.queue_free()
	await process_frame

	# A sunset view also exposes the body and fixture placement against the sky.
	var dusk_preset: Dictionary = LightingConfig.preset(LightingConfig.defaults(), "sunset")
	if dusk_preset.get("ok") != true:
		_fail("Sunset lighting preset failed")
		return
	var dusk_activity = _new_activity(dusk_preset.config)
	await process_frame
	if not _prepare_parked_activity(dusk_activity, "sunset"):
		_night_cleanup(dusk_activity)
		return
	dusk_activity.dashboard.set_menu(false)
	if not _set_light_state(dusk_activity, true, true, true) \
			or not await _capture(dusk_activity, "sunset-all-lights", "front34", NEUTRAL_CONTROLS, false):
		_night_cleanup(dusk_activity)
		return
	dusk_activity.queue_free()
	await process_frame

	var expected_capture_count: int = 12
	var captures_ok: bool = captures.size() == expected_capture_count
	for capture: Dictionary in captures:
		captures_ok = captures_ok and capture.get("capture_status") == OK \
			and capture.get("observer_preserves_accepted_body_snapshot", false) \
			and capture.get("paused_during_capture", false) \
			and int(capture.get("tick_after", -1)) == 0
	var observer_bench_ok: bool = lighting_benchmark.get("available", false) \
		and lighting_benchmark.get("observer_preserves_accepted_body_snapshot", false) \
		and int(lighting_benchmark.get("session_tick", -1)) == 0 \
		and bool(lighting_benchmark.get("session_paused", false))
	var report := {
		"step": "RCV-38",
		"complete": failure_messages.is_empty() and captures_ok and observer_bench_ok \
			and night_paused and day_paused and night_tick == 0 and day_tick == 0,
		"engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(),
		"video_adapter": RenderingServer.get_video_adapter_name(),
		"processor": OS.get_processor_name(),
		"viewport_size": _json_safe(root.size),
		"vehicle_id": "monster-car-2",
		"capture_count": captures.size(),
		"expected_capture_count": expected_capture_count,
		"night_lighting_config": night_config,
		"day_lighting_config": day_config,
		"sunset_lighting_config": dusk_preset.config,
		"activity_source_sha256": FileAccess.get_sha256(GROUND_SCENE_PATH),
		"effects_source_sha256": FileAccess.get_sha256(GROUND_EFFECTS_PATH),
		"lighting_observer_source_sha256": FileAccess.get_sha256(NITRO_LIGHTS_PATH),
		"physics_was_disabled": true,
		"input_processing_was_disabled": true,
		"audio_was_disabled": true,
		"parked_spawn_id": "track_start",
		"session_paused_for_all_captures": night_paused and day_paused,
		"night_accepted_body_snapshot": _snapshot_summary(night_body_token),
		"night_session_tick": night_tick,
		"night_effects": night_effects_snapshot,
		"night_switches": night_effect_state,
		"night_lighting_observer": night_observer_diagnostic,
		"day_accepted_body_snapshot": _snapshot_summary(day_body_token),
		"day_session_tick": day_tick,
		"day_effects": day_effects_snapshot,
		"day_switches": day_effect_state,
		"day_lighting_observer": day_observer_diagnostic,
		"observer_warm_timing": lighting_benchmark,
		"captures": captures,
		"failures": failure_messages,
		"scope": "Paused parked production presentation captures. The rear-stop brake control is supplied only to the read-only visual observer as a cosmetic probe; it is not accepted into physics and establishes no moving or handling outcome. Vehicle amber running markers are included in the running-light group. Evidence covers native car and road lighting; dashboard text is incidental and does not establish font or layout quality.",
	}
	var receipt := FileAccess.open(output_directory.path_join("capture-receipt.json"), FileAccess.WRITE)
	if receipt == null:
		_fail("Could not write capture receipt (error %d)" % FileAccess.get_open_error())
	else:
		receipt.store_string(JSON.stringify(_json_safe(report), "\t", true, true) + "\n")
		receipt.close()
	print("RCV-38 lighting capture: ", JSON.stringify({
		"complete": report.complete,
		"capture_count": captures.size(),
		"observe_timing": lighting_benchmark,
	}))
	quit(0 if report.complete and failure_messages.is_empty() else 1)


func _new_activity(config: Dictionary):
	var activity = Activity.new()
	activity.vehicle_id = "monster-car-2"
	activity.lighting_config = config.duplicate(true)
	activity.enable_audio = false
	activity.use_practice_fixture = false
	activity.set_physics_process(false)
	activity.set_process(false)
	activity.set_process_input(false)
	activity.set_process_unhandled_input(false)
	activity.set_process_unhandled_key_input(false)
	root.add_child(activity)
	return activity


func _prepare_parked_activity(activity: Variant, label: String) -> bool:
	if not activity.startup_error.is_empty():
		_fail("%s Activity startup failed: %s" % [label, activity.startup_error])
		return false
	if activity.session == null or not activity.session.reset("track_start"):
		_fail("%s track_start reset failed: %s" % [label, activity.session.load_error if activity.session != null else "missing session"])
		return false
	activity._after_reset()
	activity.session.pause("rcv38-lighting-capture")
	activity.set_physics_process(false)
	activity.set_process(false)
	activity.set_process_input(false)
	activity.set_process_unhandled_input(false)
	activity.set_process_unhandled_key_input(false)
	if activity.session.tick != 0 or not activity.session.paused:
		_fail("%s Activity is not parked and paused after reset" % label)
		return false
	if activity.is_physics_processing() or activity.is_processing_input() \
			or activity.is_processing_unhandled_input() or activity.is_processing_unhandled_key_input():
		_fail("%s Activity still has physics or source input enabled" % label)
		return false
	return true


func _set_light_state(activity: Variant, headlights: bool, auxiliary: bool, neon: bool) -> bool:
	var effects: Variant = activity.get("_effects")
	if effects == null:
		return false
	if bool(effects.get("headlights_enabled")) != headlights:
		activity.call("handle_action", "lights")
	if bool(effects.get("auxiliary_enabled")) != auxiliary:
		activity.call("handle_action", "aux_lights")
	if bool(effects.get("neon_enabled")) != neon:
		activity.call("handle_action", "neon")
	var state: Dictionary = _light_state(activity)
	return state.get("headlights_enabled") == headlights \
		and state.get("auxiliary_enabled") == auxiliary and state.get("neon_enabled") == neon


func _light_state(activity: Variant) -> Dictionary:
	var effects: Variant = activity.get("_effects")
	if effects == null:
		return {}
	return {
		"headlights_enabled": bool(effects.get("headlights_enabled")),
		"auxiliary_enabled": bool(effects.get("auxiliary_enabled")),
		"neon_enabled": bool(effects.get("neon_enabled")),
	}


func _capture(activity: Variant, name: String, view: String, controls: Dictionary, cosmetic_probe: bool) -> bool:
	var before: Dictionary = _accepted_body_token(activity)
	var tick_before: int = int(activity.session.tick)
	activity._last_controls = controls.duplicate(true)
	# GroundScene presentation is invoked manually; no physics or process input is allowed.
	activity._process(0.0)
	var camera_record: Dictionary = _set_camera_pose(activity, view)
	for _frame in 2:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var capture_status: Error = image.save_png(output_directory.path_join(name + ".png"))
	var after: Dictionary = _accepted_body_token(activity)
	var preserved: bool = before.get("bytes", PackedByteArray()) == after.get("bytes", PackedByteArray())
	var tick_after: int = int(activity.session.tick)
	var paused: bool = bool(activity.session.paused)
	var effects_snapshot: Dictionary = _safe_dictionary(activity._effects.call("diagnostic_snapshot"))
	var lighting_snapshot: Dictionary = _observer_diagnostic(activity)
	var record := {
		"name": name,
		"image": name + ".png",
		"view": view,
		"camera": camera_record,
		"controls": controls.duplicate(true),
		"cosmetic_brake_probe": cosmetic_probe,
		"effects_switches": _light_state(activity),
		"effects_diagnostic": effects_snapshot,
		"lighting_diagnostic": lighting_snapshot,
		"accepted_body_snapshot_source": before.get("source", "unknown"),
		"accepted_body_snapshot_sha256_before": before.get("sha256", ""),
		"accepted_body_snapshot_sha256_after": after.get("sha256", ""),
		"observer_preserves_accepted_body_snapshot": preserved,
		"tick_before": tick_before,
		"tick_after": tick_after,
		"paused_during_capture": paused,
		"capture_status": capture_status,
	}
	captures.append(record)
	if capture_status != OK:
		_fail("Image capture failed for %s (error %d)" % [name, capture_status])
	if not preserved or tick_after != tick_before or not paused:
		_fail("Visual observer changed accepted physics or pause state for %s" % name)
	return capture_status == OK and preserved and tick_after == tick_before and paused


func _set_camera_pose(activity: Variant, view: String) -> Dictionary:
	var vehicle_root: Node3D = activity.visual.get("root") as Node3D
	var camera: Camera3D = activity.get("camera") as Camera3D
	var origin: Vector3 = vehicle_root.global_position
	var basis: Basis = vehicle_root.global_basis
	var forward: Vector3 = (-basis.z).normalized()
	var right: Vector3 = basis.x.normalized()
	var target: Vector3 = origin + Vector3.UP * 0.14
	var camera_position: Vector3
	var look_target: Vector3 = target
	var fov: float = 48.0
	match view:
		"front34":
			camera_position = target + forward * 1.4 + right * 1.0 + Vector3.UP * 0.6
		"rear34":
			camera_position = target - forward * 1.3 + right * 1.1 + Vector3.UP * 0.55
		"low-side":
			camera_position = target + right * 1.6 + forward * 0.08 + Vector3.UP * 0.28
		"road-overview":
			look_target = target + forward * 5.2
			camera_position = target - forward * 3.7 + right * 2.2 + Vector3.UP * 3.0
			fov = 58.0
		_:
			camera_position = target + forward * 1.9 + right * 1.5 + Vector3.UP * 0.95
	camera.global_position = camera_position
	camera.look_at(look_target, Vector3.UP)
	camera.fov = fov
	camera.make_current()
	return {
		"position_world_m": _vector_array(camera_position),
		"target_world_m": _vector_array(look_target),
		"fov_deg": fov,
	}


func _accepted_body_token(activity: Variant) -> Dictionary:
	var session: Variant = activity.get("session")
	var source: String = "state_snapshot"
	var bytes := PackedByteArray()
	if session.has_method("accepted_body_snapshot"):
		var accepted: Variant = session.call("accepted_body_snapshot")
		source = "accepted_body_snapshot"
		if typeof(accepted) == TYPE_PACKED_FLOAT64_ARRAY:
			var accepted_state: PackedFloat64Array = accepted
			bytes = accepted_state.to_byte_array()
		elif typeof(accepted) == TYPE_PACKED_BYTE_ARRAY:
			bytes = accepted.duplicate()
		else:
			bytes = var_to_bytes(accepted)
	else:
		var fallback_state: PackedFloat64Array = session.state_snapshot()
		bytes = fallback_state.to_byte_array()
	return {"source": source, "bytes": bytes, "sha256": _sha256(bytes), "byte_count": bytes.size()}


func _snapshot_summary(token: Dictionary) -> Dictionary:
	return {
		"source": token.get("source", "unknown"),
		"sha256": token.get("sha256", ""),
		"byte_count": token.get("byte_count", 0),
	}


func _lighting_observer(activity: Variant) -> Variant:
	var effects: Variant = activity.get("_effects")
	return effects.get("_nitro_lights") if effects != null else null


func _observer_diagnostic(activity: Variant) -> Dictionary:
	var observer: Variant = _lighting_observer(activity)
	if observer is Object and observer.has_method("diagnostic_snapshot"):
		return _safe_dictionary(observer.call("diagnostic_snapshot"))
	return {}


func _benchmark_observer(activity: Variant) -> Dictionary:
	var observer: Variant = _lighting_observer(activity)
	if not observer is Object or not observer.has_method("observe"):
		return {"available": false, "reason": "NitroLights.observe unavailable"}
	var selected: Dictionary = _light_state(activity)
	var night_weight: float = _activity_night_weight(activity)
	var stable_controls: Dictionary = NEUTRAL_CONTROLS.duplicate(true)
	var brake_controls: Dictionary = BRAKE_PROBE_CONTROLS.duplicate(true)
	var before_body: Dictionary = _accepted_body_token(activity)
	var diagnostic_before: Dictionary = _observer_diagnostic(activity)
	var stable_times: Array[int] = []
	var toggled_times: Array[int] = []
	for run_index in OBSERVE_BENCH_RUNS:
		for _warm in OBSERVE_BENCH_WARMUP_CALLS:
			observer.call("observe", stable_controls, night_weight,
				selected.headlights_enabled, selected.auxiliary_enabled, selected.neon_enabled)
		var stable_elapsed: int
		var toggled_elapsed: int
		if run_index % 2 == 0:
			stable_elapsed = _time_observe_stable(observer, stable_controls, night_weight, selected)
			toggled_elapsed = _time_observe_toggled(observer, stable_controls, brake_controls, night_weight, selected)
		else:
			toggled_elapsed = _time_observe_toggled(observer, stable_controls, brake_controls, night_weight, selected)
			stable_elapsed = _time_observe_stable(observer, stable_controls, night_weight, selected)
		stable_times.append(stable_elapsed)
		toggled_times.append(toggled_elapsed)
	var diagnostic_after_timing: Dictionary = _observer_diagnostic(activity)
	# Re-establish the selected Activity state before reading the final diagnostics.
	activity._last_controls = stable_controls.duplicate(true)
	activity._process(0.0)
	var diagnostic_after_restore: Dictionary = _observer_diagnostic(activity)
	var after_body: Dictionary = _accepted_body_token(activity)
	var tick_after: int = int(activity.session.tick)
	var paused_after: bool = bool(activity.session.paused)
	return {
		"available": true,
		"observer_preserves_accepted_body_snapshot": before_body.get("bytes", PackedByteArray()) == after_body.get("bytes", PackedByteArray()) \
			and tick_after == 0 and paused_after,
		"accepted_body_sha256_before": before_body.get("sha256", ""),
		"accepted_body_sha256_after": after_body.get("sha256", ""),
		"session_tick": tick_after,
		"session_paused": paused_after,
		"runs": OBSERVE_BENCH_RUNS,
		"warmup_calls_per_run": OBSERVE_BENCH_WARMUP_CALLS,
		"timed_calls_per_run": OBSERVE_BENCH_CALLS,
		"stable_input_median_total_usec": _median(stable_times),
		"toggled_input_median_total_usec": _median(toggled_times),
		"stable_input_median_usec_per_call": _median(stable_times) / float(OBSERVE_BENCH_CALLS),
		"toggled_input_median_usec_per_call": _median(toggled_times) / float(OBSERVE_BENCH_CALLS),
		"stable_diagnostic_before": diagnostic_before,
		"toggled_diagnostic_after": diagnostic_after_timing,
		"restored_diagnostic_after": diagnostic_after_restore,
		"call_count_diagnostics_before": _call_counter_fields(diagnostic_before),
		"call_count_diagnostics_after": _call_counter_fields(diagnostic_after_timing),
		"timing_scope": "Direct NitroLights.observe calls after warmup; stable switches versus alternating controls/night/headlight/aux/neon inputs; excludes rendering and capture.",
	}


func _time_observe_stable(observer: Object, controls: Dictionary, night_weight: float, switches: Dictionary) -> int:
	var started: int = Time.get_ticks_usec()
	for _call_index in OBSERVE_BENCH_CALLS:
		observer.call("observe", controls, night_weight,
			switches.headlights_enabled, switches.auxiliary_enabled, switches.neon_enabled)
	return Time.get_ticks_usec() - started


func _time_observe_toggled(observer: Object, stable_controls: Dictionary, brake_controls: Dictionary, night_weight: float, switches: Dictionary) -> int:
	var started: int = Time.get_ticks_usec()
	for call_index in OBSERVE_BENCH_CALLS:
		var alternate: bool = call_index % 2 == 0
		var controls: Dictionary = brake_controls if alternate else stable_controls
		observer.call("observe", controls, night_weight if alternate else 1.0 - night_weight,
			not switches.headlights_enabled if alternate else switches.headlights_enabled,
			not switches.auxiliary_enabled if alternate else switches.auxiliary_enabled,
			not switches.neon_enabled if alternate else switches.neon_enabled)
	return Time.get_ticks_usec() - started


func _call_counter_fields(diagnostic: Dictionary) -> Dictionary:
	return {"update_count": diagnostic.get("update_count", 0),
		"material_writes": diagnostic.get("material_writes", 0)}


func _activity_night_weight(activity: Variant) -> float:
	var lighting: Dictionary = activity.get("_lighting")
	return 1.0 - smoothstep(0.05, 0.75, float(lighting.get("sun_energy", 1.0)))


func _median(values: Array[int]) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array[int] = values.duplicate()
	sorted.sort()
	return float(sorted[sorted.size() / 2])


func _safe_dictionary(value: Variant) -> Dictionary:
	return _json_safe(value) as Dictionary if typeof(value) == TYPE_DICTIONARY else {}


func _json_safe(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var dictionary_result := {}
			for key: Variant in value:
				dictionary_result[str(key)] = _json_safe(value[key])
			return dictionary_result
		TYPE_ARRAY:
			var array_result: Array = []
			for item: Variant in value:
				array_result.append(_json_safe(item))
			return array_result
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			var packed_result: Array = []
			for item: Variant in value:
				packed_result.append(_json_safe(item))
			return packed_result
		TYPE_VECTOR2:
			return [value.x, value.y]
		TYPE_VECTOR3:
			return [value.x, value.y, value.z]
		TYPE_COLOR:
			return [value.r, value.g, value.b, value.a]
		TYPE_OBJECT:
			return str(value)
		_:
			return value


func _vector_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _night_cleanup(activity: Variant) -> void:
	if activity != null and is_instance_valid(activity):
		activity.queue_free()
	quit(1)


func _fail(message: String) -> void:
	failure_messages.append(message)
	printerr(message)
