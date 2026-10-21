## L6c research probe: run the normal interactive flight scene with a tick-indexed input tape.
## No simulation state is repositioned or stepped manually. The render and flight loops remain live.
##
## Performance: Godot --path <app> --script <this file> -- --mode=performance --report=<json>
## Temporal: Godot --path <app> --script <this file> --write-movie=<avi> --fixed-fps=24 -- --mode=temporal
extends SceneTree

const FrameSamples := preload("res://render/frame_samples.gd")
const VisualEvidence := preload("res://render/visual_evidence.gd")
const FORMAT := "openrc-tree-flight-quality-v1"
const TEMPORAL_FORMAT := "openrc-tree-temporal-v1"
const PERFORMANCE_ROUTE := "performance-neutral-trim"
const TEMPORAL_ROUTES := [
	"slow-pan",
	"pilot-input-pulse",
	"pilot-bank-reversal",
	"chase-control-pulse",
	"camera-cut",
]

class Observer extends Node:
	var host: Object

	func _process(delta: float) -> void:
		if is_instance_valid(host):
			host.call("_process_observation", delta)


var args: Dictionary = {}
var scene: Node3D
var observer: Observer
var mode := ""
var route := ""
var output_path := ""
var started_utc := ""
var last_usec := 0
var input_reads := 0
var performance_samples: FrameSamples
var input_spec_cache: Dictionary = {}
var fatal_state := ""
var first_camera_mode := ""
var camera_events: Array[Dictionary] = []
var temporal_frames := 0
var temporal_frame_limit := 0
var finalize_pending := false
var temporal_tick_first := -1
var temporal_tick_last := -1
var temporal_time_first := -1.0
var temporal_time_last := -1.0
var input_tick_rate := 0
var temporal_frame_trace: Array[Dictionary] = []


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		args[pair[0]] = pair[1] if pair.size() > 1 else true
	mode = str(args.get("mode", ""))
	route = str(args.get("route", PERFORMANCE_ROUTE if mode == "performance" else ""))
	output_path = str(args.get("report", ""))
	started_utc = Time.get_datetime_string_from_system(true, true)
	if mode not in ["performance", "temporal", "smoke"]:
		_fail("--mode must be performance, temporal or smoke")
		return
	input_tick_rate = Engine.physics_ticks_per_second
	if input_tick_rate < 1:
		_fail("Engine.physics_ticks_per_second must be positive")
		return
	if mode == "temporal" and route not in TEMPORAL_ROUTES:
		_fail("--route must be one of: " + ", ".join(TEMPORAL_ROUTES))
		return
	input_spec_cache = _build_route_input_spec()
	var fps: int = int(args.get("fps", 60 if mode == "performance" else 24))
	if fps < 1 or fps > 240:
		_fail("--fps must be between 1 and 240")
		return
	Engine.max_fps = fps
	_run.call_deferred()


func _run() -> void:
	if mode == "performance" and output_path.is_empty():
		_fail("--report=<absolute path> is required for performance mode")
		return
	if mode == "temporal":
		output_path = str(args.get("report", ""))
		if output_path.is_empty():
			_fail("--report=<absolute path> is required for temporal mode")
			return
		temporal_frame_limit = int(args.get("frames", 120))
		if temporal_frame_limit < 24 or temporal_frame_limit > 120:
			_fail("--frames must be between 24 and 120 (one to five seconds at 24 fps)")
			return
		if DisplayServer.get_name() == "headless":
			_fail("temporal movie capture requires a native display")
			return
	if mode == "smoke":
		output_path = str(args.get("report", ""))
		if output_path.is_empty():
			_fail("--report=<absolute path> is required for smoke mode")
			return

	scene = load("res://main.tscn").instantiate() as Node3D
	if scene == null:
		_fail("could not instantiate res://main.tscn")
		return
	# A connected desktop gamepad otherwise takes priority over read_raw, silently
	# replacing this probe's tick-indexed tape. Use the normal external-selection
	# seam before _ready; select no device and retain the keyboard command path.
	scene.external_controller_selection = true
	root.add_child(scene)
	# The route owns inputs, including pause/reset/camera shortcuts. Desktop
	# typing must not mutate a timed run. FlightSession input stays enabled and
	# continues through read_raw -> Commands; only live UI events are excluded.
	_disable_live_input(scene)
	if scene.get("session") == null or scene.get("_rig") == null or scene.get("_camera") == null:
		_fail("main scene did not initialize a physics flight, camera rig and camera")
		return
	if bool(scene.get("_scripted")) or not scene.session.physics_enabled:
		_fail("probe requires a live physics flight; scripted or frozen sessions are refused")
		return
	if not scene.session.input_enabled:
		_fail("probe requires the normal session input path to remain enabled")
		return
	if not str(scene.get("startup_error")).is_empty():
		_fail("main scene startup failed: " + str(scene.get("startup_error")))
		return
	var viewport: Viewport = scene.get_viewport()
	# Keep both builds at the project's intended 4x MSAA cost, including older frozen app copies.
	viewport.msaa_3d = Viewport.MSAA_4X
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)

	# This is the same FlightSession.read_raw → Commands.step_commands path used by live keyboard input.
	scene.session.read_raw = Callable(self, "_read_input")
	_set_camera_for_route()
	observer = Observer.new()
	observer.host = self
	root.add_child(observer)
	if mode == "performance":
		var warmup_s: float = float(args.get("probe-warmup", 10.0))
		var sample_s: float = float(args.get("probe-sample", 60.0))
		performance_samples = FrameSamples.new()
		if not performance_samples.configure(warmup_s, sample_s):
			_fail("invalid FrameSamples settings: " + performance_samples.failure)
			return
	if mode == "smoke":
		# Headless parse/start smoke only. It is deliberately not a performance measurement.
		Engine.max_fps = int(args.get("fps", 30))
		performance_samples = FrameSamples.new()
		if not performance_samples.configure(0.0, 1.0):
			_fail("could not initialize smoke sampler")
			return
		# Exercise the production smoke-assignment shortcut, which would pause
		# this aircraft if desktop event isolation were accidentally removed.
		_exercise_desktop_isolation.call_deferred()


func _exercise_desktop_isolation() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_J
	event.keycode = KEY_J
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)


func _disable_live_input(node: Node) -> void:
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false)
	node.set_process_shortcut_input(false)
	for child in node.get_children():
		_disable_live_input(child)


func _process_observation(delta: float) -> void:
	if scene == null or not is_instance_valid(scene):
		return
	if mode == "temporal":
		_update_temporal_camera()
		if not scene.session.input_enabled or not scene.session.physics_enabled:
			fatal_state = "live input or physics was disabled during the temporal route"
		if not scene.session.sim.paused and scene.session.crash.is_empty() and scene.session.sim.fault_reason.is_empty():
			if temporal_tick_first < 0:
				temporal_tick_first = scene.session.sim.tick
				temporal_time_first = scene.session.sim.time()
			temporal_tick_last = scene.session.sim.tick
			temporal_time_last = scene.session.sim.time()
		temporal_frames += 1
		_record_temporal_frame()
		if scene.session.sim.paused or not scene.session.crash.is_empty() or not scene.session.sim.fault_reason.is_empty():
			fatal_state = _session_failure()
		if temporal_frames >= temporal_frame_limit and not finalize_pending:
			finalize_pending = true
			_finish_temporal.call_deferred()
		return

	if scene.session.sim.paused or not scene.session.crash.is_empty() or not scene.session.sim.fault_reason.is_empty():
		fatal_state = _session_failure()
		_write_performance_report(false)
		return
	if not scene.session.input_enabled or not scene.session.physics_enabled:
		fatal_state = "live input or physics was disabled during the route"
		_write_performance_report(false)
		return
	if mode == "smoke":
		_sample_frame(delta)
		if performance_samples.finished:
			_write_performance_report(true)
		return
	_sample_frame(delta)
	if performance_samples.finished:
		_write_performance_report(true)


func _sample_frame(delta: float) -> void:
	var now_usec: int = Time.get_ticks_usec()
	if last_usec == 0:
		last_usec = now_usec
		return
	var wall_delta_usec: int = now_usec - last_usec
	last_usec = now_usec
	var vp: Viewport = scene.get_viewport()
	var vp_rid: RID = vp.get_viewport_rid()
	var visible: int = RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE
	var shadow: int = RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW
	var metrics: Dictionary = {
		sim_time_s = scene.session.sim.time(),
		sim_tick = float(scene.session.sim.tick),
		physics_step_usec = float(scene.session.sim.step_usec),
		fps_monitor = float(Performance.get_monitor(Performance.TIME_FPS)),
		process_time_s = float(Performance.get_monitor(Performance.TIME_PROCESS)),
		physics_process_time_s = float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)),
		object_count = float(Performance.get_monitor(Performance.OBJECT_COUNT)),
		node_count = float(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		draw_calls = float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		primitives = float(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		physics_3d_active_objects = float(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		physics_3d_collision_pairs = float(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)),
		visible_draw_calls = float(RenderingServer.viewport_get_render_info(vp_rid, visible, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)),
		visible_primitives = float(RenderingServer.viewport_get_render_info(vp_rid, visible, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)),
		visible_objects = float(RenderingServer.viewport_get_render_info(vp_rid, visible, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)),
		shadow_draw_calls = float(RenderingServer.viewport_get_render_info(vp_rid, shadow, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)),
		shadow_primitives = float(RenderingServer.viewport_get_render_info(vp_rid, shadow, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)),
		shadow_objects = float(RenderingServer.viewport_get_render_info(vp_rid, shadow, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)),
		video_memory_bytes = float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
		texture_memory_bytes = float(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)),
		buffer_memory_bytes = float(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)),
		cpu_static_memory_bytes = float(Performance.get_monitor(Performance.MEMORY_STATIC)),
		render_cpu_ms = RenderingServer.viewport_get_measured_render_time_cpu(vp_rid),
		render_gpu_ms = RenderingServer.viewport_get_measured_render_time_gpu(vp_rid),
		input_read_calls = float(input_reads),
	}
	if not performance_samples.record_frame(delta, wall_delta_usec, now_usec, metrics):
		fatal_state = "FrameSamples rejected data: " + performance_samples.failure
		_write_performance_report(false)
		return


func _write_performance_report(complete: bool) -> void:
	if not performance_samples.finished and complete:
		fatal_state = "requested measurement did not complete"
		complete = false
	var report: Dictionary = performance_samples.report()
	var raw: Dictionary = report.get("raw_metrics", {})
	var ticks: PackedFloat64Array = raw.get("sim_tick", PackedFloat64Array())
	var sim_times: PackedFloat64Array = raw.get("sim_time_s", PackedFloat64Array())
	var elapsed_ticks: int = int(ticks[-1] - ticks[0]) if ticks.size() > 1 else 0
	var measured_wall_s: float = 0.0
	var frame_end_usec: PackedInt64Array = report.get("frame_end_monotonic_usec", PackedInt64Array())
	if frame_end_usec.size() > 1:
		measured_wall_s = float(frame_end_usec[-1] - frame_end_usec[0]) / 1000000.0
	var engine_deltas: PackedFloat64Array = report.get("engine_frame_deltas_s", PackedFloat64Array())
	var measured_engine_s: float = 0.0
	for i: int in range(1, engine_deltas.size()):
		measured_engine_s += engine_deltas[i]
	var simulation_s: float = (sim_times[-1] - sim_times[0]) if sim_times.size() > 1 else 0.0
	var flight_ratio: float = simulation_s / measured_wall_s if measured_wall_s > 0.0 else 0.0
	var video_memory: PackedFloat64Array = raw.get("video_memory_bytes", PackedFloat64Array())
	var texture_memory: PackedFloat64Array = raw.get("texture_memory_bytes", PackedFloat64Array())
	var buffer_memory: PackedFloat64Array = raw.get("buffer_memory_bytes", PackedFloat64Array())
	var cpu_static_memory: PackedFloat64Array = raw.get("cpu_static_memory_bytes", PackedFloat64Array())
	var render_cpu_ms: PackedFloat64Array = raw.get("render_cpu_ms", PackedFloat64Array())
	var render_gpu_ms: PackedFloat64Array = raw.get("render_gpu_ms", PackedFloat64Array())
	var memory_available := {
		cpu_static = _has_positive(cpu_static_memory),
		video = _has_positive(video_memory),
		textures = _has_positive(texture_memory),
		buffers = _has_positive(buffer_memory),
	}
	var memory_reason := "Godot Performance renderer memory monitors returned positive byte counts."
	if not memory_available.cpu_static or not memory_available.video or not memory_available.textures or not memory_available.buffers:
		memory_reason = "One or more renderer memory monitors returned zero; treat that metric as unavailable on this renderer."
	var visible_draw_calls: PackedFloat64Array = raw.get("visible_draw_calls", PackedFloat64Array())
	var shadow_draw_calls: PackedFloat64Array = raw.get("shadow_draw_calls", PackedFloat64Array())
	var visible_primitives: PackedFloat64Array = raw.get("visible_primitives", PackedFloat64Array())
	var shadow_primitives: PackedFloat64Array = raw.get("shadow_primitives", PackedFloat64Array())
	var window_size: Vector2 = scene.get_viewport().get_visible_rect().size
	var render_cpu_available := _has_positive(render_cpu_ms)
	var render_gpu_available := _has_positive(render_gpu_ms)
	var scenario_identity := _scenario_identity(window_size)
	report.merge({
		format = FORMAT,
		measured_clocks = {
			wall_source = "monotonic frame-end microsecond timestamps",
			wall_start_monotonic_usec = frame_end_usec[0] if not frame_end_usec.is_empty() else 0,
			wall_end_monotonic_usec = frame_end_usec[-1] if not frame_end_usec.is_empty() else 0,
			wall_elapsed_s = measured_wall_s,
			engine_source = "Godot process delta samples",
			engine_elapsed_s = measured_engine_s,
		},
		frame_time_source = "FrameSamples monotonic wall intervals; engine delta percentiles remain in engine_frame_ms",
		case_id = str(args.get("case", "tree-flight")),
		route = "live-input-tick-tape",
		route_id = route,
		route_spec = _route_input_spec(),
		input_tape_sha256 = _input_tape_hash(),
		scenario_identity = scenario_identity,
		scenario_sha256 = _scenario_hash(scenario_identity),
		complete = complete and fatal_state.is_empty() and bool(report.get("complete", false)),
		failure = fatal_state,
		started_utc = started_utc,
		finished_utc = Time.get_datetime_string_from_system(true, true),
		build = {
			godot = Engine.get_version_info().string,
			os = OS.get_name(),
			cpu = OS.get_processor_name(),
			logical_processors = OS.get_processor_count(),
			backend = RenderingServer.get_current_rendering_method(),
			adapter = RenderingServer.get_video_adapter_name(),
			api = RenderingServer.get_video_adapter_api_version(),
			viewport_render_timing = {
				cpu = {available = render_cpu_available, reason = "Godot viewport CPU render timer returned zero for every sample." if not render_cpu_available else "Godot viewport CPU render timer returned positive samples."},
				gpu = {available = render_gpu_available, reason = "Godot viewport GPU render timer returned zero for every sample on this renderer/device." if not render_gpu_available else "Godot viewport GPU render timer returned positive samples."},
			},
			render_memory = {available = memory_available, reason = memory_reason},
			frame_samples_sha256 = FileAccess.get_sha256("res://render/frame_samples.gd"),
			main_sha256 = FileAccess.get_sha256("res://main.gd"),
			code_provenance = VisualEvidence.provenance(),
		},
		settings = {
			window = {width = int(window_size.x), height = int(window_size.y)},
			render_settings = {
				msaa_3d = scene.get_viewport().msaa_3d,
				msaa_4x = scene.get_viewport().msaa_3d == Viewport.MSAA_4X,
				screen_space_aa = scene.get_viewport().screen_space_aa,
				scaling_3d_scale = scene.get_viewport().scaling_3d_scale,
			},
			max_fps = Engine.max_fps,
			vsync = DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED,
			weather = scene.session.weather_configuration(),
			lighting = scene.get("lighting_config"),
			sky = scene.get("sky_config"),
			rates = scene.session.rate_profile,
			camera = {
				mode = scene._rig.view,
				auto_zoom = scene._rig.auto_zoom,
				fov_deg = scene._camera.fov,
				transform = VisualEvidence.transform(scene._camera.global_transform),
			},
			aircraft_id = scene.aircraft_id,
			input_enabled = scene.session.input_enabled,
			physics_enabled = scene.session.physics_enabled,
		},
		simulation = {
			start_tick = int(ticks[0]) if not ticks.is_empty() else -1,
			end_tick = int(ticks[-1]) if not ticks.is_empty() else -1,
			ticks = elapsed_ticks,
			start_time_s = sim_times[0] if not sim_times.is_empty() else -1.0,
			end_time_s = sim_times[-1] if not sim_times.is_empty() else -1.0,
			elapsed_time_s = simulation_s,
			measured_wall_s = measured_wall_s,
			measured_engine_s = measured_engine_s,
			wall_ratio = flight_ratio,
			physics_ticks_per_second = Engine.physics_ticks_per_second,
			paused = scene.session.sim.paused,
			fault = scene.session.sim.fault_reason,
			crash = not scene.session.crash.is_empty(),
			read_raw_calls = input_reads,
		},
		measured_render = {
			cpu_render_ms = _percentile_set(render_cpu_ms),
			gpu_render_ms = _percentile_set(render_gpu_ms),
			visible_draw_calls = _percentile_set(visible_draw_calls),
			shadow_draw_calls = _percentile_set(shadow_draw_calls),
			visible_primitives = _percentile_set(visible_primitives),
			shadow_primitives = _percentile_set(shadow_primitives),
		},
		measured_memory = {
			cpu_static_bytes = _percentile_set(cpu_static_memory),
			video_bytes = _percentile_set(video_memory),
			texture_bytes = _percentile_set(texture_memory),
			buffer_bytes = _percentile_set(buffer_memory),
		},
		note = "Active native flight measured with the app FrameSamples collector. Controls enter through FlightSession.read_raw and normal Commands; no simulation-state bypass is used. Godot viewport CPU/GPU render timers are reported as raw frame metrics and marked unavailable only when the renderer returns zero.",
	}, true)
	var write_result: Dictionary = FrameSamples.write_json(output_path, report)
	if not write_result.ok:
		printerr("could not write frame report: ", error_string(int(write_result.error)))
		quit(1)
		return
	print(JSON.stringify({format = FORMAT, complete = report.complete, route = route,
		frames = report.frames, simulation_wall_ratio = flight_ratio, report = output_path}))
	quit(0 if bool(report.complete) else 1)


func _finish_temporal() -> void:
	await RenderingServer.frame_post_draw
	var report := {
		format = TEMPORAL_FORMAT,
		complete = fatal_state.is_empty() and temporal_frames == temporal_frame_limit,
		failure = fatal_state,
		route = route,
		frames = temporal_frames,
		expected_frames = temporal_frame_limit,
		fps = Engine.max_fps,
		resolution = [scene.get_viewport().get_visible_rect().size.x, scene.get_viewport().get_visible_rect().size.y],
		clip_path = str(args.get("clip", "")),
		started_utc = started_utc,
		finished_utc = Time.get_datetime_string_from_system(true, true),
		input_tape_sha256 = _input_tape_hash(),
		route_spec = _route_input_spec(),
		input_read_calls = input_reads,
		simulation = {
			start_tick = temporal_tick_first,
			end_tick = temporal_tick_last,
			elapsed_ticks = temporal_tick_last - temporal_tick_first if temporal_tick_first >= 0 else 0,
			physics_ticks_per_second = input_tick_rate,
			start_time_s = temporal_time_first,
			end_time_s = temporal_time_last,
			input_enabled = scene.session.input_enabled,
			physics_enabled = scene.session.physics_enabled,
			paused = scene.session.sim.paused,
			fault = scene.session.sim.fault_reason,
			crash = not scene.session.crash.is_empty(),
		},
		camera_events = camera_events,
		frame_trace = temporal_frame_trace,
		window_has_focus = scene.get_window().has_focus(),
		pause_reason = scene.session.pause_reason,
		session_holds = scene.session.holds.keys(),
		final_view = scene._rig.evidence(),
		visual_evidence = scene.capture_evidence(),
		code_provenance = VisualEvidence.provenance(),
		note = "Native AVI movie writer captures the normal rendered flight scene. The route changes only camera controls and tick-indexed flight inputs; it never repositions or manually steps simulation state. Camera and aircraft transforms are recorded for every clip frame.",
	}
	var shutdown := await _cleanup_temporal_scene()
	report["shutdown"] = shutdown
	if not bool(shutdown.audio_released):
		report.complete = false
		report.failure = "audio playback resources did not drain before the shutdown timeout"
	var write_result: Dictionary = FrameSamples.write_json(output_path, report)
	if not write_result.ok:
		printerr("could not write temporal report: ", error_string(int(write_result.error)))
		quit(1)
		return
	print(JSON.stringify({format = TEMPORAL_FORMAT, complete = report.complete,
		route = route, frames = temporal_frames, report = output_path}))
	quit(0 if bool(report.complete) else 1)


func _cleanup_temporal_scene() -> Dictionary:
	const AUDIO_DRAIN_TIMEOUT_USEC := 1_000_000
	var playbacks: Array[WeakRef] = []
	if is_instance_valid(scene):
		_collect_audio_playbacks(scene, playbacks)
	if is_instance_valid(observer):
		observer.host = null
		observer.set_process(false)
		observer.queue_free()
		observer = null
	if is_instance_valid(scene):
		scene.queue_free()
		scene = null
	var begin := Time.get_ticks_usec()
	await process_frame
	await process_frame
	var remaining := _remaining_audio_playbacks(playbacks)
	while remaining > 0 and Time.get_ticks_usec() - begin < AUDIO_DRAIN_TIMEOUT_USEC:
		await process_frame
		remaining = _remaining_audio_playbacks(playbacks)
	return {tracked_playbacks = playbacks.size(), remaining_playbacks = remaining,
		audio_released = remaining == 0, elapsed_usec = Time.get_ticks_usec() - begin,
		timeout_usec = AUDIO_DRAIN_TIMEOUT_USEC}


func _collect_audio_playbacks(node: Node, refs: Array[WeakRef]) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		if node.has_stream_playback():
			refs.append(weakref(node.get_stream_playback()))
	for child in node.get_children():
		_collect_audio_playbacks(child, refs)


func _remaining_audio_playbacks(refs: Array[WeakRef]) -> int:
	var remaining := 0
	for ref in refs:
		if ref.get_ref() != null:
			remaining += 1
	return remaining


func _set_camera_for_route() -> void:
	scene._rig.auto_zoom = false
	scene._rig.look = Vector2(0.0, 5.0)
	scene._rig.look_height = 1.7
	match mode:
		"performance", "smoke":
			scene._rig.set_view("pilot")
		"temporal":
			match route:
				"slow-pan":
					scene._rig.look = Vector2(NAN, NAN)
					scene._rig.set_view("orbit")
				"pilot-input-pulse", "pilot-bank-reversal": scene._rig.set_view("pilot")
				"chase-control-pulse":
					scene._rig.look = Vector2(NAN, NAN)
					scene._rig.set_view("chase")
				"camera-cut":
					scene._rig.look = Vector2(NAN, NAN)
					scene._rig.set_view("pilot")
	first_camera_mode = scene._rig.view


func _update_temporal_camera() -> void:
	var time_s: float = float(scene.session.sim.tick) / float(input_tick_rate)
	match route:
		"slow-pan":
			# CameraRig.drag is the same orbit interaction path used by the live camera.
			scene._rig.drag(Vector2(0.28, 0.06))
		"pilot-input-pulse":
			if scene._rig.view != "pilot":
				_change_camera("pilot")
		"pilot-bank-reversal":
			if scene._rig.view != "pilot":
				_change_camera("pilot")
		"chase-control-pulse":
			if scene._rig.view != "chase":
				_change_camera("chase")
		"camera-cut":
			var wanted := "pilot"
			if time_s >= 4.0: wanted = "closeup"
			elif time_s >= 3.0: wanted = "orbit"
			elif time_s >= 2.0: wanted = "chase"
			elif time_s >= 1.0: wanted = "pilot"
			if scene._rig.view != wanted:
				_change_camera(wanted)
	if camera_events.is_empty():
		_record_camera_event()


func _change_camera(view: String) -> void:
	if scene._rig.set_view(view):
		_record_camera_event()


func _record_camera_event() -> void:
	var tick: int = scene.session.sim.tick
	camera_events.append({
		tick = tick,
		time_s = float(tick) / float(input_tick_rate),
		view = scene._rig.view,
		transform = VisualEvidence.transform(scene._camera.global_transform),
	})


func _record_temporal_frame() -> void:
	var camera: Camera3D = scene._camera
	var aircraft: Node3D = scene._airplane.root
	var tick: int = scene.session.sim.tick
	temporal_frame_trace.append({
		frame = temporal_frames - 1,
		monotonic_usec = Time.get_ticks_usec(),
		simulation_tick = tick,
		simulation_time_s = float(tick) / float(input_tick_rate),
		camera_view = scene._rig.view,
		camera_fov_deg = camera.fov,
		camera_transform = VisualEvidence.transform(camera.global_transform),
		aircraft_transform = VisualEvidence.transform(aircraft.global_transform),
		aircraft_position = VisualEvidence.vector(aircraft.global_position),
	})


func _read_input() -> Dictionary:
	input_reads += 1
	if not is_instance_valid(scene):
		return {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
	if route == PERFORMANCE_ROUTE or route in ["slow-pan", "camera-cut"]:
		return {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
	var tick: int = scene.session.sim.tick
	var raw := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
	for segment: Dictionary in input_spec_cache.get("segments", []):
		var start_tick: int = int(segment.get("start_tick", 0))
		var end_tick: int = int(segment.get("end_tick", 2147483647))
		if tick >= start_tick and tick <= end_tick:
			return segment.get("raw", raw).duplicate()
	return raw


func _route_input_spec() -> Dictionary:
	if input_spec_cache.is_empty():
		input_spec_cache = _build_route_input_spec()
	return input_spec_cache


func _build_route_input_spec() -> Dictionary:
	match route:
		"pilot-input-pulse":
			return {name = route, tick_rate = input_tick_rate, segments = [
				{start_tick = 0, end_tick = _ticks(0.5) - 1, raw = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}},
				{start_tick = _ticks(0.5), end_tick = _ticks(2.5) - 1, raw = {roll = 0.10, pitch = 0.025, yaw = 0.0, throttle = 0.35}},
				{start_tick = _ticks(2.5), end_tick = _ticks(4.0) - 1, raw = {roll = -0.10, pitch = -0.015, yaw = 0.0, throttle = -0.20}},
				{start_tick = _ticks(4.0), end_tick = 2147483647, raw = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}},
			]}
		"pilot-bank-reversal":
			return {name = route, tick_rate = input_tick_rate, segments = [
				{start_tick = 0, end_tick = _ticks(0.5) - 1, raw = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}},
				{start_tick = _ticks(0.5), end_tick = _ticks(2.5) - 1, raw = {roll = 0.18, pitch = 0.01, yaw = 0.0, throttle = 0.0}},
				{start_tick = _ticks(2.5), end_tick = _ticks(4.0) - 1, raw = {roll = -0.18, pitch = -0.01, yaw = 0.0, throttle = 0.0}},
				{start_tick = _ticks(4.0), end_tick = 2147483647, raw = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}},
			]}
		"chase-control-pulse":
			return {name = route, tick_rate = input_tick_rate, segments = [
				{start_tick = 0, end_tick = _ticks(0.5) - 1, raw = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}},
				{start_tick = _ticks(0.5), end_tick = _ticks(3.0) - 1, raw = {roll = 0.0, pitch = 0.025, yaw = 0.0, throttle = 1.0}},
				{start_tick = _ticks(3.0), end_tick = 2147483647, raw = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}},
			]}
		_:
			return {name = route if not route.is_empty() else PERFORMANCE_ROUTE, tick_rate = input_tick_rate, segments = [
				{start_tick = 0, end_tick = 2147483647, raw = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}},
			]}


func _ticks(seconds: float) -> int:
	return roundi(seconds * float(input_tick_rate))


func _input_tape_hash() -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(_route_input_spec(), "", true).to_utf8_buffer())
	return context.finish().hex_encode()


func _scenario_identity(window_size: Vector2) -> Dictionary:
	var viewport: Viewport = scene.get_viewport()
	return {
		"aircraft_id": scene.aircraft_id,
		"weather": scene.session.weather_configuration(),
		"lighting": scene.get("lighting_config"),
		"sky": scene.get("sky_config"),
		"rates": str(scene.session.rate_profile),
		"camera": {
			"mode": scene._rig.view,
			"auto_zoom": scene._rig.auto_zoom,
			"fov_deg": scene._camera.fov,
			"look": [scene._rig.look.x, scene._rig.look.y],
			"look_height": scene._rig.look_height,
		},
		"window": [int(window_size.x), int(window_size.y)],
		"max_fps": Engine.max_fps,
		"vsync": DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED,
		"render_settings": {
			"msaa_3d": viewport.msaa_3d,
			"screen_space_aa": viewport.screen_space_aa,
			"scaling_3d_scale": viewport.scaling_3d_scale,
		},
		"route_spec": _route_input_spec(),
		"input_tape_sha256": _input_tape_hash(),
	}


func _scenario_hash(identity: Dictionary) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(identity, "", true).to_utf8_buffer())
	return context.finish().hex_encode()


func _session_failure() -> String:
	if scene.session.sim.paused:
		return "flight paused during quality route; reason=%s; focus=%s; holds=%s" % [
			str(scene.session.pause_reason), str(scene.get_window().has_focus()), str(scene.session.holds.keys())]
	if not scene.session.crash.is_empty():
		return "flight crashed during quality route"
	if not scene.session.sim.fault_reason.is_empty():
		return "simulation fault during quality route: " + str(scene.session.sim.fault_reason)
	return "flight session became unavailable"


func _percentile_set(values: PackedFloat64Array) -> Dictionary:
	if values.is_empty():
		return {p50 = 0.0, p95 = 0.0, p99 = 0.0, max = 0.0}
	var sorted := values.duplicate()
	sorted.sort()
	return {
		p50 = sorted[int((sorted.size() - 1) * 0.50)],
		p95 = sorted[int((sorted.size() - 1) * 0.95)],
		p99 = sorted[int((sorted.size() - 1) * 0.99)],
		max = sorted[-1],
	}


func _has_positive(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if value > 0.0:
			return true
	return false


func _fail(message: String) -> void:
	push_error("flight quality probe: " + message)
	quit(2)
