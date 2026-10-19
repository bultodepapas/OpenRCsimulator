extends SceneTree

const FROZEN_ROOT := "C:/DEVELOPMENT/OpenRCsimulator/tmp/godot-audit-r3-20261019/frame"
const FROZEN_APP := FROZEN_ROOT + "/executed_sources/app"
const FREEZE_MANIFEST := FROZEN_ROOT + "/source-freeze.json"
const SAMPLE_LIMIT := 20000

var output_path := ""
var warmup_s := 5.0
var duration_s := 45.0
var app: Node
var initial_route: Dictionary = {}
var initial_control_signature := ""
var initial_sim_state_hash := ""
var initial_radio_axes: Array = []
var route_violations: Array[Dictionary] = []
var recorded_route_violation_kinds: Dictionary = {}
var origin_usec := 0
var last_sample_usec := 0
var samples: Array[Dictionary] = []
var pause_events: Array[Dictionary] = []
var focus_events: Array[Dictionary] = []
var focus_cursor := 0
var last_pause := false
var source_freeze_sha256 := ""
var diagnostic_input_disabled_usec := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--frametimes="):
			output_path = arg.trim_prefix("--frametimes=") + ".trace.json"
		elif arg.begins_with("--warmup="):
			warmup_s = maxf(0.0, float(arg.trim_prefix("--warmup=")))
		elif arg.begins_with("--t="):
			duration_s = maxf(1.0, float(arg.trim_prefix("--t=")))
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	_run.call_deferred()


func _reload_frozen_script(resource_path: String, frozen_path: String) -> bool:
	var script: GDScript = load(resource_path)
	if script == null:
		push_error("FRAME-R3 cannot load script resource: " + resource_path)
		return false
	var source := FileAccess.get_file_as_string(frozen_path)
	if source.is_empty():
		push_error("FRAME-R3 frozen source is empty: " + frozen_path)
		return false
	script.source_code = source
	var err: Error = script.reload(true)
	if err != OK:
		push_error("FRAME-R3 frozen source reload failed (%d): %s" % [err, resource_path])
		return false
	return true


func _control_signature(session: Node) -> String:
	var sim: Node = session.sim
	return JSON.stringify({
		"raw": session.raw,
		"commands": session.commands,
		"trims": session.trims,
		"sim_inputs": Array(sim.inputs),
	}).sha256_text()


func _route_snapshot(session: Node, flight: Node) -> Dictionary:
	var sim: Node = session.sim
	var radio: Node = session.radio
	var state: Array = Array(sim.state)
	return {
		"tick": sim.tick,
		"sim_time_s": sim.time(),
		"sim_paused": sim.paused,
		"fault": sim.fault_reason,
		"focused": DisplayServer.window_is_focused(),
		"physics_enabled": session.physics_enabled,
		"input_enabled": session.input_enabled,
		"radio_connected": radio.connected,
		"radio_device_id": radio.device_id,
		"radio_axes": Array(radio.axes),
		"external_controller_selection": session.external_controller_selection,
		"scripted_flight_mode": bool(flight.get("_scripted")),
		"scripted_frametimes_mode": bool(flight.get("_frametimes_scripted_fixed")),
		"raw": session.raw.duplicate(true),
		"commands": session.commands.duplicate(true),
		"trims": session.trims.duplicate(true),
		"sim_inputs": Array(sim.inputs),
		"sim_state_hash_sha256": JSON.stringify(state).sha256_text(),
		"controls_hash_sha256": _control_signature(session),
	}


func _run() -> void:
	if output_path.is_empty():
		push_error("FRAME-R3 requires --frametimes=<new path>")
		quit(2)
		return
	source_freeze_sha256 = FileAccess.get_sha256(FREEZE_MANIFEST)
	if not _reload_frozen_script("res://sim/simulation.gd", FROZEN_APP + "/sim/simulation.gd"):
		quit(2)
		return
	if not _reload_frozen_script("res://main.gd", FROZEN_APP + "/main.gd"):
		quit(2)
		return
	if not _reload_frozen_script("res://app_root.gd", FROZEN_APP + "/app_root.gd"):
		quit(2)
		return
	app = load("res://app_root.tscn").instantiate()
	root.add_child(app)
	var flight: Node = app.get("flight") if is_instance_valid(app) else null
	var session: Node = flight.get("session") if is_instance_valid(flight) else null
	if not is_instance_valid(session):
		push_error("FRAME-R3 could not reach the flight session immediately after adding AppRoot")
		quit(2)
		return
	var sim: Node = session.sim
	var start_tick_before_input_disable: int = sim.tick
	# The established trace/capture input route keeps physics enabled while commands stay at the solved trim.
	session.input_enabled = false
	diagnostic_input_disabled_usec = Time.get_ticks_usec()
	initial_route = _route_snapshot(session, flight)
	initial_route["tick_before_input_disable"] = start_tick_before_input_disable
	initial_route["input_disabled_before_first_physics"] = start_tick_before_input_disable == 0
	initial_control_signature = str(initial_route.get("controls_hash_sha256", ""))
	initial_sim_state_hash = str(initial_route.get("sim_state_hash_sha256", ""))
	initial_radio_axes = Array(initial_route.get("radio_axes", []))
	if start_tick_before_input_disable != 0 or not session.physics_enabled or sim.paused \
			or bool(initial_route.get("scripted_flight_mode", false)) \
			or bool(initial_route.get("scripted_frametimes_mode", false)):
		push_error("FRAME-R3 fixed-trim route requires active physics at tick zero before the first physics callback")
		quit(2)
		return
	origin_usec = Time.get_ticks_usec()
	process_frame.connect(_sample)


func _sample() -> void:
	if samples.size() >= SAMPLE_LIMIT:
		return
	var now_usec := Time.get_ticks_usec()
	if last_sample_usec == 0:
		last_sample_usec = now_usec
		return
	var flight: Node = app.get("flight") if is_instance_valid(app) else null
	var session: Node = flight.get("session") if is_instance_valid(flight) else null
	if not is_instance_valid(session):
		last_sample_usec = now_usec
		return
	var sim: Node = session.sim
	var control_signature := _control_signature(session)
	var recorded_focus: Variant = app.get("_audit_focus_events")
	if recorded_focus is Array:
		while focus_cursor < recorded_focus.size():
			var event: Variant = recorded_focus[focus_cursor]
			if event is Dictionary:
				focus_events.append(event.duplicate(true))
			focus_cursor += 1
	var paused: bool = sim.paused
	if paused != last_pause:
		last_pause = paused
		pause_events.append({
			"usec": now_usec,
			"elapsed_s": float(now_usec - origin_usec) / 1000000.0,
			"paused": paused,
			"tick": sim.tick,
			"holds": session.holds.duplicate(true),
			"crash": session.crash.duplicate(true),
			"fault": sim.fault_reason,
		})
	var main_end_usec: int = int(flight.get("_audit_main_frame_end_usec"))
	var row := {
		"usec": now_usec,
		"elapsed_s": float(now_usec - origin_usec) / 1000000.0,
		"wall_delta_usec": now_usec - last_sample_usec,
		"main_end_usec": main_end_usec,
		"main_end_lag_usec": now_usec - main_end_usec if main_end_usec > 0 else -1,
		"main_total_usec": int(flight.get("_audit_main_total_usec")),
		"main_world_usec": int(flight.get("_audit_main_world_usec")),
		"main_audio_usec": int(flight.get("_audit_main_audio_usec")),
		"main_panel_usec": int(flight.get("_audit_main_panel_usec")),
		"main_pose_usec": int(flight.get("_audit_main_pose_usec")),
		"main_hud_usec": int(flight.get("_audit_main_hud_usec")),
		"main_overlay_usec": int(flight.get("_audit_main_overlay_usec")),
		"main_other_usec": int(flight.get("_audit_main_other_usec")),
		"physics_callbacks": int(sim.get("_audit_step_callbacks")),
		"physics_tick_count": int(sim.get("_audit_step_tick_count")),
		"physics_total_usec": int(sim.get("_audit_step_total_usec")),
		"physics_max_usec": int(sim.get("_audit_step_max_usec")),
		"physics_last_usec": int(sim.get("_audit_step_last_usec")),
		"tick": sim.tick,
		"paused": paused,
		"focused": DisplayServer.window_is_focused(),
		"input_enabled": session.input_enabled,
		"radio_connected": session.radio.connected,
		"radio_axes_match_start": Array(session.radio.axes) == initial_radio_axes,
		"control_state_matches_start": control_signature == initial_control_signature,
		"physics_enabled": session.physics_enabled,
		"crash_active": not session.crash.is_empty(),
		"crash": session.crash.duplicate(true),
		"fault": sim.fault_reason,
		"render_setup_cpu_ms": RenderingServer.get_frame_setup_time_cpu(),
		"render_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),
		"render_gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),
		"process_monitor_usec_lagged": int(Performance.get_monitor(Performance.TIME_PROCESS) * 1000000.0),
		"physics_monitor_usec_lagged": int(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000000.0),
		"draw_calls_monitor": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives_monitor": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"objects_monitor": Performance.get_monitor(Performance.OBJECT_COUNT),
		"nodes_monitor": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"resources_monitor": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"orphans_monitor": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"static_memory_monitor": Performance.get_monitor(Performance.MEMORY_STATIC),
		"video_memory_monitor": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
	}
	samples.append(row)
	if session.input_enabled:
		_record_route_violation("input_reenabled", now_usec, sim.tick)
	if control_signature != initial_control_signature:
		_record_route_violation("commands_inputs_or_trim_changed", now_usec, sim.tick)
	if not session.physics_enabled:
		_record_route_violation("physics_disabled", now_usec, sim.tick)
	# The observer runs at process_frame, before the next Main._process callback.
	# Consume these per-interval counters here so the next row owns the next interval.
	sim.set("_audit_step_callbacks", 0)
	sim.set("_audit_step_tick_count", 0)
	sim.set("_audit_step_total_usec", 0)
	sim.set("_audit_step_max_usec", 0)
	sim.set("_audit_step_last_usec", 0)
	last_sample_usec = now_usec
	if float(now_usec - origin_usec) / 1000000.0 > warmup_s + duration_s + 20.0:
		push_error("FRAME-R3 safety timeout: app did not finish its --frametimes run")
		quit(3)


func _record_route_violation(kind: String, now_usec: int, tick: int) -> void:
	if recorded_route_violation_kinds.has(kind):
		return
	recorded_route_violation_kinds[kind] = true
	route_violations.append({
		"kind": kind,
		"usec": now_usec,
		"elapsed_s": float(now_usec - origin_usec) / 1000000.0,
		"tick": tick,
	})


func _finalize() -> void:
	if output_path.is_empty():
		return
	var final_route: Dictionary = {}
	if is_instance_valid(app):
		var value: Variant = app.get("_audit_focus_events")
		if value is Array:
			while focus_cursor < value.size():
				var event: Variant = value[focus_cursor]
				if event is Dictionary:
					focus_events.append(event.duplicate(true))
				focus_cursor += 1
		var final_flight: Node = app.get("flight")
		var final_session: Node = final_flight.get("session") if is_instance_valid(final_flight) else null
		if is_instance_valid(final_session):
			final_route = _route_snapshot(final_session, final_flight)
	var payload := {
		"format": "openrc-frame-stall-trace v1",
		"scope": "Diagnostic instrumented fixed-trim-input route. Runtime spans/counters are diagnostic; input_enabled=false holds the solved start commands while physics continues. Timestamps use Time.get_ticks_usec and align to the app frame report's monotonic frame_end values.",
		"process_id": OS.get_process_id(),
		"godot": Engine.get_version_info().string,
		"source_freeze_sha256": source_freeze_sha256,
		"observer_origin_usec": origin_usec,
		"diagnostic_input_enabled": false,
		"diagnostic_input_disabled_usec": diagnostic_input_disabled_usec,
		"initial_route": initial_route,
		"initial_sim_state_hash_sha256": initial_sim_state_hash,
		"initial_control_signature_sha256": initial_control_signature,
		"final_route": final_route,
		"route_violations": route_violations,
		"warmup_s": warmup_s,
		"duration_s": duration_s,
		"samples": samples,
		"pause_events": pause_events,
		"focus_events": focus_events,
		"monitor_note": "TIME_PROCESS, TIME_PHYSICS_PROCESS and Performance monitor counts may lag; use direct physics spans, Main spans, and RenderingServer last-frame timings for frame attribution.",
	}
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(payload))
		file.flush()
