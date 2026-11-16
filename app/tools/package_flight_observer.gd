extends Node
## Fixed release-only direct-flight observer.  It does not own simulation steps.
## An incomplete receipt is never a package-promotion result.

const InputAdapter := preload("res://tools/package_flight_input.gd")
const Simulation := preload("res://sim/simulation.gd")
const FlightLog := preload("res://sim/flight_log.gd")
const NativePackage := preload("res://app_state/native_package.gd")
const ContactObserver := preload("res://statistics/fixed_wing_adapter.gd")
const FORMAT := "openrc-package-live-flight v1"
const ROUTE := "app-root-direct-flight-fixed-circuit"
const SEED := 20261021
const HZ := 240
const WINDOW_TICKS := 6000
const MAX_ROWS := 4096
const MAX_TRANSITIONS := 256
const DWELL_USEC := 2_500_000
const STALL_USEC := 1_000_000
const DRAWABLE_POLL_USEC := 500_000
const DRAWABLE_BOUNDARY_USEC := 1_000_000
const FORBIDDEN := ["scripted", "trace", "capture", "visual_pose", "visual_distance", "visual_elevation",
	"visual_azimuth", "hide_airplane", "hide_treeline", "experimental-aircraft-data", "electric-demo",
	"flight-log-cli", "native-qualification", "sustained-hide-shader", "sustained-shader-param"]

var scene: Node
var session: Node
var adapter: RefCounted
var contact: RefCounted
var frame_path := ""
var receipt_path := ""
var capture_id := ""
var requested_backend := ""
var initial_package: Dictionary = {}
var initial_replay: Dictionary = {}
var backend_identity: Dictionary = {}
var backend_stage: Callable
var backend_native: Object
var native_previous: Dictionary = {}
var native_checked_ticks := 0
var initial_checkpoint_sha256 := ""
var source_scenario: Dictionary = {}
var initial_render_scope: Dictionary = {}
var violations: Dictionary = {tick_discontinuity = 0, nonfinite = 0, input_ownership = 0,
	backend = 0, crash = 0, fault = 0, pause = 0, hold = 0, contact = 0, prop_strike = 0,
	pilot_failure = 0, focus_loss = 0, undrawable = 0, render_scope = 0, observation_overflow = 0}
var failure := ""
var last_tick := 0
var observer_calls := 0
var observer_usec := 0
var started_usec := 0
var last_tick_usec := 0
var sealed_usec := 0
var sealed_tick := 0
var sealed_exit := -1
var sealed_input: Dictionary = {}
var sealed := false
var abort_queued := false
var checkpoint_start := 1
var checkpoint_hash: HashingContext
var checkpoints: Array[Dictionary] = []
var activation_samples: Array[Dictionary] = []
var activation_transitions: Array[Dictionary] = []
var last_activation: Dictionary = {}
var drawable_requested := false
var drawable_pending := false
var drawable_sequence := 0
var drawable_next_usec := 0
var drawable_rid: RID
var drawable_before: Dictionary = {}
var drawable_after: Dictionary = {}
var drawable_reason := "not_requested"
var measured_start_usec := 0
var measured_end_usec := 0
var input_watch_active := false


## Called before Main configures the streaming file, so existing outputs are refused.
func prepare(host: Node) -> Dictionary:
	scene = host
	if not OS.has_feature("template_release") or OS.get_name() != "macOS" \
			or Engine.get_architecture_name() != "arm64":
		return _refuse("requires the signed Mac arm64 release process")
	if not is_instance_valid(scene) or not is_instance_valid(scene.get_parent()) \
			or scene.get_parent().get_script() == null \
			or scene.get_parent().get_script().resource_path != "res://app_root.gd" \
			or scene.get_parent().get("flight") != scene or scene.get("interactive_start") != false:
		return _refuse("requires the actual AppRoot direct-flight route")
	var parsed := _options(scene.user_args)
	if not parsed.ok:
		return parsed
	frame_path = parsed.frame_path
	receipt_path = parsed.receipt_path
	requested_backend = parsed.backend
	capture_id = OS.get_environment("OPENRC_DIAGNOSTIC_CAPTURE_ID")
	if capture_id.is_empty() or capture_id.length() > 128:
		return _refuse("a bounded checked-run capture ID is required")
	if not _safe_output_paths(frame_path, receipt_path, false):
		return _refuse("output paths must be new, distinct and outside the bundle")
	scene.frametimes_auto_quit = false
	scene.frametimes_route = ROUTE
	return {ok = true}


## Called synchronously by Main after normal preparation and before its first tick.
func attach() -> Dictionary:
	if not _safe_output_paths(frame_path, receipt_path, true):
		return _refuse("frame stream or output path changed during preparation")
	if Engine.physics_ticks_per_second != HZ or Engine.time_scale != 1.0 \
			or not scene.startup_error.is_empty() or not scene._frametimes_active \
			or scene._frametimes_path != frame_path or scene._frametimes_scripted_fixed:
		return _refuse("normal 240 Hz active frame collection is required")
	session = scene.session
	if not is_instance_valid(session) or not is_instance_valid(session.sim) or session.sim.tick != 0 \
			or not session.is_flyable() or not session.physics_enabled or not session.input_enabled \
			or session.external_driver_enabled or session.radio.connected or not session.holds.is_empty() \
			or session.sim.paused or not session.is_physics_processing() or not session.sim.is_physics_processing():
		return _refuse("requires healthy automatic-input physics at tick zero without radio")
	if not get_window().has_focus() or not get_window().can_draw():
		return _refuse("flight window must be focused and drawable")
	initial_render_scope = _render_scope()
	if initial_render_scope.is_empty(): return _refuse("effective render configuration is unavailable or fell back")
	initial_package = _package_identity(requested_backend)
	initial_replay = FlightLog.replay_identity(requested_backend, true)
	if initial_package.get("ok") != true or not _identity_valid(initial_package, initial_replay, session):
		return _refuse("running package or installed backend identity is unavailable")
	backend_identity = session.stage_backend_identity().duplicate(true)
	backend_stage = session.sim.model.stage
	if requested_backend == "native":
		if session._native_stage == null or session._native_stage._native == null or not _native_guard():
			return _refuse("native stage and domain guard are required")
		backend_native = session._native_stage._native
		native_previous = backend_native.stage_stats().duplicate(true)
		if not _native_stats_valid(native_previous):
			return _refuse("native coverage counters are unavailable")
	elif _native_guard():
		return _refuse("reference backend unexpectedly owns a native domain")
	var initial_checkpoint: Dictionary = session.checkpoint()
	if initial_checkpoint.is_empty() or int(initial_checkpoint.get("simulation", {}).get("tick", -1)) != 0 \
			or str(initial_checkpoint.get("configuration", "")).length() != 64 \
			or str(initial_checkpoint.get("collision_world_identity", "")).length() != 64 \
			or str(initial_checkpoint.get("lake_identity", "")).length() != 64:
		return _refuse("validated tick-zero checkpoint and world identities are required")
	initial_checkpoint_sha256 = _hash(var_to_bytes(initial_checkpoint))
	if initial_checkpoint_sha256.length() != 64: return _refuse("cannot hash tick-zero checkpoint")
	adapter = InputAdapter.new()
	if not adapter.configure(session, scene.field, SEED):
		return _refuse("fixed circuit input refused: " + str(adapter.failure))
	contact = ContactObserver.new()
	contact.session = session
	checkpoint_hash = HashingContext.new()
	if checkpoint_hash.start(HashingContext.HASH_SHA256) != OK:
		return _refuse("cannot initialize checkpoint digest")
	source_scenario = {aircraft_id = scene.aircraft_id, field_id = scene.field.get("id", ""), seed = SEED,
		start_choice = session.start_choice, trim = session.start.duplicate(true), rate_profile = session.rate_profile,
		weather = session.weather_configuration(), collision_world_identity = initial_checkpoint.collision_world_identity,
		lake_identity = initial_checkpoint.lake_identity, configuration = initial_checkpoint.configuration,
		input = "fixed synthetic circuit through rate-limited keyboard callback; no radio",
		frame_generation_requested = OS.get_environment("OPENRC_METALFX_FRAME_GENERATION") == "1",
		display_link_requested = OS.get_environment("OPENRC_METALFX_DISPLAY_LINK") == "1",
		metalfx_trial_requested = OS.get_environment("OPENRC_METALFX_TRIAL") == "1",
		drawable_observation_requested = OS.get_environment("OPENRC_NATIVE_DRAWABLE_OBSERVATION") == "1",
		arguments = Array(scene.user_args)}
	started_usec = Time.get_ticks_usec()
	last_tick_usec = started_usec
	drawable_requested = OS.get_environment("OPENRC_NATIVE_DRAWABLE_OBSERVATION") == "1"
	if drawable_requested:
		drawable_rid = scene.get_viewport().get_viewport_rid()
		drawable_reason = "awaiting_receipt"
		_request_drawable()
	adapter.failed.connect(_pilot_failed)
	session.sim.stepped.connect(_on_stepped)
	session.sim.faulted.connect(_faulted)
	session.sim.paused_changed.connect(_paused)
	scene.frame_time_report_written.connect(_on_sealed)
	get_window().focus_exited.connect(_focus_lost)
	session.read_raw = adapter.read_raw
	_record_activation(0)
	input_watch_active = true
	set_process_input(true)
	set_process(true)
	return {ok = true}


func _options(arguments: PackedStringArray) -> Dictionary:
	var values := {}
	for argument: String in arguments:
		if not argument.begins_with("--"):
			return _refuse("unexpected non-option argument")
		var part := argument.trim_prefix("--").split("=", true, 1)
		var key: String = part[0]
		if key.is_empty() or values.has(key) or key in FORBIDDEN:
			return _refuse("duplicate, empty or incompatible option: " + key)
		if part.size() == 2:
			values[key] = part[1]
		else:
			values[key] = true
	if not values.get("frametimes") is String or not values.get("package-flight-receipt") is String \
			or values.get("frametimes-stream") != true:
		return _refuse("frame stream and package flight receipt paths are required")
	var backend: Variant = values.get("physics-backend")
	if not backend is String or backend not in ["native", "gdscript_reference"]:
		return _refuse("an explicit physics backend is required")
	return {ok = true, frame_path = values.frametimes, receipt_path = values["package-flight-receipt"], backend = backend}


func _package_identity(backend: String) -> Dictionary:
	var arguments := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	var identity: Dictionary = NativePackage.mac_native_identity(OS.get_executable_path(), Engine.get_architecture_name(), arguments) \
			if backend == "native" else NativePackage.mac_reference_identity(OS.get_executable_path(), Engine.get_architecture_name(), arguments)
	if identity.get("ok") != true:
		return {}
	var reference: Dictionary = identity.get("reference_identity", {}) if backend == "native" else identity
	if not NativePackage.macos_process_reference_error(reference).is_empty():
		return {}
	return identity


func _identity_valid(package: Dictionary, replay: Dictionary, flight_owner: Node) -> bool:
	var status: Dictionary = flight_owner.stage_backend_status()
	var identity: Variant = status.get("identity")
	if status.get("requested") != requested_backend or not str(status.get("reason", "")).is_empty() \
			or not identity is Dictionary or identity.get("backend") != requested_backend \
			or replay.get("sha256") != package.get("sha256") or replay.get("kind") != package.get("kind"):
		return false
	return requested_backend != "native" or replay.get("stage_backend") == identity


func _native_guard() -> bool:
	return is_instance_valid(session._native_stage) and is_instance_valid(session._native_stage._native) \
			and not session._native_stage._macos_domain_context.is_empty() \
			and session._native_stage._macos_domain_matches(session)


func _native_stats_valid(value: Dictionary) -> bool:
	return typeof(value.get("context_calls")) == TYPE_INT and int(value.context_calls) >= 0 \
			and typeof(value.get("stage_calls")) == TYPE_INT and int(value.stage_calls) >= 0 \
			and value.get("timing") == false


func _on_stepped(tick: int, _time: float, state: PackedFloat64Array, _loads: PackedFloat64Array,
		inputs: PackedFloat64Array, aux: PackedFloat64Array) -> void:
	if sealed: return
	var began := Time.get_ticks_usec()
	observer_calls += 1
	if _tick_gap_invalid(last_tick_usec, began): _fail("tick_discontinuity", "automatic physics stalled or its clock regressed")
	if tick != last_tick + 1: _fail("tick_discontinuity", "accepted ticks are not consecutive")
	last_tick = tick
	last_tick_usec = began
	if not Simulation.state_is_valid(state) or not _finite(inputs) or not _finite(aux) \
			or not _finite(session.sim.continuous): _fail("nonfinite", "invalid accepted state")
	if not _ownership_valid(): _fail("input_ownership", "automatic input or physics ownership changed")
	if not _backend_tick(): _fail("backend", "backend identity, guard or per-tick coverage changed")
	if not session.crash.is_empty(): _fail("crash", "flight crashed")
	if not session.sim.fault_reason.is_empty(): _fail("fault", "simulation fault")
	if session.sim.paused or not session.pause_reason.is_empty(): _fail("pause", "simulation paused")
	if not session.holds.is_empty(): _fail("hold", "flight acquired a hold")
	if not session.prop_strike.is_empty(): _fail("prop_strike", "propeller strike")
	var contacts: Dictionary = session.contact_events()
	if not contacts.get("events", []).is_empty() or not contacts.get("active_hull_ids", []).is_empty():
		_fail("contact", "hull, scenery, lake or propeller contact")
	for compression: float in contact._compressions(state):
		if not is_finite(compression): _fail("nonfinite", "invalid gear contact")
		elif compression > 0.0: _fail("contact", "landing gear contact")
	if checkpoint_hash.update(PackedInt64Array([tick]).to_byte_array()) != OK:
		_fail("nonfinite", "checkpoint digest update failed")
	for values: PackedFloat64Array in [state, inputs, aux, session.sim.continuous]:
		if checkpoint_hash.update(values.to_byte_array()) != OK: _fail("nonfinite", "checkpoint digest update failed")
	if checkpoint_hash.update(session.sim.modes.to_byte_array()) != OK: _fail("nonfinite", "checkpoint digest update failed")
	if tick % WINDOW_TICKS == 0:
		_append_checkpoint(tick, false)
		checkpoint_start = tick + 1
		checkpoint_hash = HashingContext.new()
		if checkpoint_hash.start(HashingContext.HASH_SHA256) != OK: _fail("nonfinite", "checkpoint digest could not restart")
	if tick % HZ == 0: _record_activation(tick)
	observer_usec += Time.get_ticks_usec() - began


func _backend_tick() -> bool:
	var status: Dictionary = session.stage_backend_status()
	if status.get("requested") != requested_backend or status.get("identity") != backend_identity \
			or not str(status.get("reason", "")).is_empty() or session.sim.model.stage != backend_stage:
		return false
	if _native_guard() != (requested_backend == "native"): return false
	if requested_backend != "native": return true
	if not is_instance_valid(backend_native) or session._native_stage._native != backend_native: return false
	var current: Dictionary = backend_native.stage_stats()
	if not _native_stats_valid(current) or int(current.context_calls) - int(native_previous.context_calls) < 1 \
			or int(current.stage_calls) - int(native_previous.stage_calls) < 4: return false
	native_previous = current.duplicate(true)
	native_checked_ticks += 1
	return true


func _input_watch_valid() -> bool:
	return input_watch_active and is_processing_input()


func _ownership_valid() -> bool:
	return _input_watch_valid() \
			and session.physics_enabled and session.input_enabled and not session.external_driver_enabled \
			and not session.radio.connected and session.read_raw == adapter.read_raw \
			and session.can_process() and session.sim.can_process() \
			and session.is_physics_processing() and session.sim.is_physics_processing() \
			and Engine.physics_ticks_per_second == HZ and Engine.time_scale == 1.0


## This route owns synthetic input. Do not consume real input; invalidate the
## collection if it arrives, including changes restored before the next frame.
func _input(event: InputEvent) -> void:
	if input_watch_active and not sealed and _changes_live_input(event):
		_fail("input_ownership", "external input received during synthetic flight")


static func _changes_live_input(event: InputEvent) -> bool:
	# Plain cursor motion does not affect this route; dragging and all other
	# event kinds can alter controls, cameras, rendering, or UI.
	return not (event is InputEventMouseMotion and event.button_mask == 0)


func _observe_render_scope(value: Dictionary) -> void:
	if value != initial_render_scope:
		_fail("render_scope", "render configuration or window extent changed")


func _process(_delta: float) -> void:
	if drawable_requested:
		_update_measurement_start()
		if not drawable_pending and (not sealed or drawable_after.is_empty()) \
				and Time.get_ticks_usec() >= drawable_next_usec:
			_request_drawable()
	if sealed:
		if Time.get_ticks_usec() - sealed_usec >= DWELL_USEC: _finish()
		return
	if not is_instance_valid(scene) or not is_instance_valid(session) or not is_instance_valid(session.sim):
		_fail("input_ownership", "flight scene disappeared")
	elif not _ownership_valid(): _fail("input_ownership", "automatic input or physics ownership changed")
	elif _tick_gap_invalid(last_tick_usec, Time.get_ticks_usec()): _fail("tick_discontinuity", "automatic physics stopped or its clock regressed")
	if is_instance_valid(session) and is_instance_valid(session.sim):
		if session.sim.paused or not session.pause_reason.is_empty(): _fail("pause", "simulation paused")
		if not session.holds.is_empty(): _fail("hold", "flight acquired a hold")
		if not session.crash.is_empty(): _fail("crash", "flight crashed")
		if not session.sim.fault_reason.is_empty(): _fail("fault", "simulation fault")
		if not session.prop_strike.is_empty(): _fail("prop_strike", "propeller strike")
	if is_instance_valid(adapter) and not adapter.failure.is_empty(): _fail("pilot_failure", adapter.failure)
	_observe_render_scope(_render_scope())
	if not get_window().has_focus(): _fail("focus_loss", "window lost focus")
	if not get_window().can_draw(): _fail("undrawable", "window cannot draw")


func _record_activation(tick: int) -> void:
	if activation_samples.size() >= MAX_ROWS:
		_fail("observation_overflow", "activation sample bound reached")
		return
	var audio: AudioStreamPlayer3D = scene._engine_audio
	var lake: AudioStreamPlayer3D = scene._lake_ambience
	var companions: Node = scene.companions
	var manager_status: Dictionary = companions.status() if is_instance_valid(companions) else {}
	var manager_state := {active = manager_status.get("active"), airborne = manager_status.get("airborne"),
		requested = manager_status.get("requested"), faulted = manager_status.get("faulted"),
		crashed = manager_status.get("crashed"), removed = manager_status.get("removed")}
	var engine_playing: Variant = null
	var engine_paused: Variant = null
	var lake_playing: Variant = null
	var companion_status: Variant = null
	if is_instance_valid(audio):
		engine_playing = audio.playing
		engine_paused = audio.stream_paused
	if is_instance_valid(lake): lake_playing = lake.playing
	if is_instance_valid(companions): companion_status = manager_state
	var value := {radio_connected = session.radio.connected,
		controller_service_selected = session.external_controller_selection,
		soundscape_installed = is_instance_valid(scene._soundscape_audio),
		engine_audio_installed = is_instance_valid(audio), engine_audio_playing = engine_playing,
		engine_audio_paused = engine_paused,
		lake_audio_installed = is_instance_valid(lake), lake_audio_playing = lake_playing,
		lens_installed = is_instance_valid(scene._lens), lens_options = scene._lens_args.duplicate(true),
		companion_config = scene.companion_config.duplicate(true), companion_manager_installed = is_instance_valid(companions),
		companion_status = companion_status,
		weather = session.weather_configuration()}
	var fg: Variant = get_viewport().get_meta(&"openrc_frame_generation_status", null)
	var fg_status: Variant = null
	if fg is Dictionary:
		fg_status = {requested = fg.get("requested"), state = fg.get("state"), reason = fg.get("reason"),
			observer_requested = fg.get("observer_requested"), frame_producer_requested = fg.get("frame_producer_requested"),
			attempt_renderer_gated_composition = fg.get("attempt_renderer_gated_composition")}
	activation_samples.append({tick = tick, monotonic_usec = Time.get_ticks_usec(), value = value,
		companion_accepted_ticks = manager_status.get("ticks") if is_instance_valid(companions) else null,
		frame_generation_status = fg_status})
	if value != last_activation:
		if activation_transitions.size() >= MAX_TRANSITIONS:
			_fail("observation_overflow", "activation transition bound reached")
			return
		activation_transitions.append({tick = tick, monotonic_usec = Time.get_ticks_usec(), value = value.duplicate(true)})
		last_activation = value.duplicate(true)


func _append_checkpoint(tick: int, partial: bool) -> void:
	if checkpoints.size() >= MAX_ROWS:
		_fail("observation_overflow", "checkpoint bound reached")
		return
	var digest := checkpoint_hash.finish()
	if digest.size() != 32:
		_fail("nonfinite", "checkpoint digest could not finish")
		return
	checkpoints.append({start_tick = checkpoint_start, end_tick = tick, sha256 = digest.hex_encode(), partial = partial})


func _on_sealed(exit_code: int) -> void:
	if sealed: return
	_observe_render_scope(_render_scope())
	sealed_tick = last_tick
	sealed_exit = exit_code
	sealed_input = {input_reads = adapter.input_reads, last_read_tick = adapter.last_read_tick,
		pilot_updates = adapter.pilot_updates, pilot_failure = adapter.failure,
		input_usec = adapter.input_elapsed_usec, pilot_usec = adapter.pilot_elapsed_usec}
	if checkpoint_start <= sealed_tick: _append_checkpoint(sealed_tick, true)
	sealed_usec = Time.get_ticks_usec()
	sealed = true
	if drawable_requested:
		var file := FileAccess.open(frame_path, FileAccess.READ)
		var value: Variant = JSON.parse_string(file.get_as_text()) if file != null \
				and file.get_length() > 0 and file.get_length() <= 8 * 1024 * 1024 else null
		if value is Dictionary and typeof(value.get("actual_sample_start_monotonic_usec")) == TYPE_INT \
				and typeof(value.get("actual_sample_end_monotonic_usec")) == TYPE_INT:
			measured_start_usec = int(value.actual_sample_start_monotonic_usec)
			measured_end_usec = int(value.actual_sample_end_monotonic_usec)
		if not drawable_pending:
			drawable_next_usec = 0
			_request_drawable()


func _finish() -> void:
	set_process(false)
	var final_package := _package_identity(requested_backend)
	var final_replay := FlightLog.replay_identity(requested_backend, true)
	var final_status: Dictionary = session.stage_backend_status()
	var frame_file := FileAccess.open(frame_path, FileAccess.READ)
	var frame_bytes := PackedByteArray()
	if frame_file != null and frame_file.get_length() > 0 and frame_file.get_length() <= 8 * 1024 * 1024:
		frame_bytes = frame_file.get_buffer(frame_file.get_length())
	var frame_text := frame_bytes.get_string_from_utf8()
	var read: Variant = JSON.parse_string(frame_text) if not frame_bytes.is_empty() \
			and frame_text.to_utf8_buffer() == frame_bytes else null
	var frame_digest := _hash(frame_bytes) if not frame_bytes.is_empty() else ""
	var frame: Dictionary = read if read is Dictionary else {}
	var stream: Variant = frame.get("stream")
	var complete: bool = failure.is_empty() and sealed_exit == 0 and frame.get("complete") == true \
			and frame.get("capture_id") == capture_id and stream is Dictionary \
			and stream.get("complete") == true and stream.get("file") == (frame_path + ".frames.jsonl").get_file() \
			and str(stream.get("sha256", "")).length() == 64 \
			and FileAccess.get_sha256(frame_path + ".frames.jsonl") == stream.get("sha256") \
			and frame_digest.length() == 64 and FileAccess.get_sha256(frame_path) == frame_digest \
			and initial_package == final_package \
			and initial_replay == final_replay and _identity_valid(final_package, final_replay, session) \
			and final_status.get("identity") == backend_identity and session.sim.model.stage == backend_stage \
			and sealed_tick > 0 and observer_calls == sealed_tick and sealed_input.input_reads == sealed_tick \
			and sealed_input.last_read_tick == sealed_tick - 1 and sealed_input.pilot_failure.is_empty() \
			and (requested_backend != "native" or native_checked_ticks == sealed_tick)
	var result := {format = FORMAT, route = ROUTE, complete = complete, failure = failure,
		capture_id = capture_id, pid = OS.get_process_id(), frame_report = frame_path,
		frame_report_sha256 = frame_digest, frame_stream_sha256 = stream.get("sha256", "") if stream is Dictionary else "",
		frame_exit_code = sealed_exit, scenario = source_scenario, initial_checkpoint_sha256 = initial_checkpoint_sha256,
		package_before = initial_package, package_after = final_package, replay_before = initial_replay, replay_after = final_replay,
		backend_identity = backend_identity, native_checked_ticks = native_checked_ticks,
		render_scope = initial_render_scope,
		observation = {start_usec = started_usec, end_usec = sealed_usec, start_tick = 0, end_tick = sealed_tick,
			observer_calls = observer_calls, observer_usec = observer_usec, input_reads = sealed_input.input_reads,
			last_read_tick = sealed_input.last_read_tick, pilot_updates = sealed_input.pilot_updates,
			pilot_failure = sealed_input.pilot_failure, input_usec = sealed_input.input_usec, pilot_usec = sealed_input.pilot_usec,
			dwell_usec = Time.get_ticks_usec() - sealed_usec},
		violations = violations, checkpoints = checkpoints, activation_samples = activation_samples,
		activation_transitions = activation_transitions,
		activation_scope = "sampled at tick zero and each 240 accepted ticks; audio properties are not audible-output proof",
		drawable = _drawable_receipt(),
		real_gpu_completion = {status = "not_observed", scope = "not a completed-real-frame pacing receipt"},
		promotion_eligible = false}
	if not _write_new_json(receipt_path, result):
		printerr("PACKAGE_FLIGHT verdict=fail: cannot write new receipt")
		get_tree().quit(1)
		return
	print("PACKAGE_FLIGHT verdict=%s capture_id=%s" % ["collected" if complete else "fail", capture_id])
	get_tree().quit(0 if complete else 1)


func _write_new_json(path: String, value: Dictionary) -> bool:
	if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path): return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(value) + "\n")
	file.flush()
	var error := file.get_error()
	file.close()
	return error == OK


func _fail(category: String, reason: String) -> void:
	if sealed: return
	violations[category] = int(violations.get(category, 0)) + 1
	if failure.is_empty(): failure = reason
	if not abort_queued:
		abort_queued = true
		_abort.call_deferred()


func _abort() -> void:
	if not sealed and is_instance_valid(scene) and scene._frametimes_active: scene._finish_frame_time(1)
	elif not sealed: get_tree().quit(1)


func _pilot_failed(reason: String) -> void: _fail("pilot_failure", reason)
func _faulted(reason: String) -> void: _fail("fault", reason)
func _paused(paused: bool) -> void:
	if paused: _fail("pause", "simulation paused")
func _focus_lost() -> void: _fail("focus_loss", "window lost focus")
static func _tick_gap_invalid(previous_usec: int, now_usec: int) -> bool:
	return previous_usec <= 0 or now_usec < previous_usec or now_usec - previous_usec > STALL_USEC
func _refuse(reason: String) -> Dictionary: return {ok = false, reason = reason}
func _finite(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value): return false
	return true
func _hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK or context.update(bytes) != OK: return ""
	var digest := context.finish()
	return digest.hex_encode() if digest.size() == 32 else ""


func _update_measurement_start() -> void:
	if measured_start_usec > 0 or not is_instance_valid(scene) or scene._frametime_samples == null: return
	var collector: RefCounted = scene._frametime_samples
	var relative: Variant = collector.get("_actual_sample_start_usec")
	var origin: Variant = collector.get("_clock_origin_usec")
	if typeof(relative) == TYPE_INT and int(relative) >= 0 and typeof(origin) == TYPE_INT and int(origin) > 0:
		measured_start_usec = int(origin) + int(relative)


## The render-thread lambda captures only a prebuilt Callable, never the Node.
func _request_drawable() -> void:
	if drawable_pending or not drawable_requested: return
	drawable_pending = true
	drawable_sequence += 1
	drawable_next_usec = Time.get_ticks_usec() + DRAWABLE_POLL_USEC
	var reply: Callable = Callable(self, "_drawable_delivered").bind(drawable_sequence, drawable_rid)
	var request: Callable = func() -> void:
		var rd := RenderingServer.get_rendering_device()
		var status: Variant = rd.call("openrc_drawable_observation") if rd != null \
				and rd.has_method("openrc_drawable_observation") else {"status": "api_unavailable"}
		reply.call_deferred(status)
	RenderingServer.call_on_render_thread(request)


func _drawable_delivered(value: Variant, sequence: int, rid: RID) -> void:
	if not drawable_pending or sequence != drawable_sequence: return
	drawable_pending = false
	if not is_instance_valid(scene) or not scene.is_inside_tree() or not rid.is_valid() \
			or not is_instance_valid(scene.get_viewport()) or scene.get_viewport().get_viewport_rid() != rid:
		drawable_reason = "viewport_changed"
		if not sealed: _fail("render_scope", "viewport changed during drawable observation")
		return
	_update_measurement_start()
	if not value is Dictionary or not _drawable_status_valid(value):
		drawable_reason = str(value.get("status", "invalid_status")) if value is Dictionary else "invalid_status"
		return
	if measured_start_usec <= 0 or int(value.query_after_usec) <= measured_start_usec:
		if drawable_before.is_empty() or int(value.query_after_usec) > int(drawable_before.query_after_usec):
			drawable_before = value.duplicate(true)
	if sealed and measured_end_usec > 0 and int(value.query_before_usec) >= measured_end_usec:
		drawable_after = value.duplicate(true)
		drawable_reason = "observed"


func _drawable_status_valid(value: Dictionary) -> bool:
	if value.get("status") != "observed" or value.get("owner") != "ordinary" \
			or value.get("evidence") != "acquired_framebuffer_texture_not_scanout": return false
	for key: String in ["scope", "attempts", "observed", "missed", "changes", "width", "height", "pixel_format",
			"query_before_usec", "query_after_usec"]:
		if typeof(value.get(key)) != TYPE_INT or int(value[key]) < 0: return false
	return int(value.scope) > 0 and int(value.observed) > 0 and int(value.width) > 0 and int(value.height) > 0 \
			and int(value.pixel_format) > 0 and int(value.observed) <= int(value.attempts) \
			and int(value.missed) == int(value.attempts) - int(value.observed) \
			and int(value.changes) < int(value.observed) and int(value.query_before_usec) > 0 \
			and int(value.query_before_usec) <= int(value.query_after_usec)


func _drawable_receipt() -> Dictionary:
	var scope := "acquired framebuffer texture; no encoder, draw or scanout proof"
	if not drawable_requested:
		return {status = "not_observed", scope = scope, reason = "not_requested"}
	if drawable_before.is_empty() or drawable_after.is_empty() or measured_start_usec <= 0 or measured_end_usec <= measured_start_usec:
		return {status = "not_observed", scope = scope, reason = drawable_reason}
	var a: Dictionary = drawable_before
	var b: Dictionary = drawable_after
	if int(a.query_after_usec) > measured_start_usec or int(b.query_before_usec) < measured_end_usec \
			or measured_start_usec - int(a.query_after_usec) > DRAWABLE_BOUNDARY_USEC \
			or int(b.query_before_usec) - measured_end_usec > DRAWABLE_BOUNDARY_USEC \
			or a.scope != b.scope or int(b.observed) <= int(a.observed) or b.missed != a.missed \
			or b.changes != a.changes or b.width != a.width or b.height != a.height or b.pixel_format != a.pixel_format \
			or int(b.attempts) - int(a.attempts) != int(b.observed) - int(a.observed):
		return {status = "not_observed", scope = scope, reason = "inconsistent_or_changed"}
	return {status = "observed", scope = scope, before = a.duplicate(true), after = b.duplicate(true)}


## CPU-visible policy/viewport properties only; SDK execution and drawable are separate evidence.
func _render_scope() -> Dictionary:
	var root: Viewport = get_viewport()
	if not is_instance_valid(root) or not root.has_meta(&"openrc_reconstruction") \
			or not is_instance_valid(scene) or not is_instance_valid(scene._rig): return {}
	var policy: Variant = root.get_meta(&"openrc_reconstruction")
	if not policy is Dictionary or policy.get("fallback") != false \
			or not policy.get("requested") is String or not policy.get("selected") is String \
			or not policy.get("provider") is String or typeof(scene._shadow_mode) != TYPE_STRING \
			or scene._shadow_mode not in ["sun", "vertical", "off"] \
			or typeof(scene._rig.auto_zoom) != TYPE_BOOL: return {}
	var logical := root.get_visible_rect().size
	var window := DisplayServer.window_get_size()
	return {backend = RenderingServer.get_current_rendering_method(), driver = RenderingServer.get_current_rendering_driver_name(),
		requested = policy.requested, selected = policy.selected, provider = policy.provider, fallback = policy.fallback,
		scaling_3d_mode = root.scaling_3d_mode, scaling_3d_scale = root.scaling_3d_scale,
		msaa_3d = root.msaa_3d, screen_space_aa = root.screen_space_aa, use_hdr_2d = root.use_hdr_2d,
		logical_size = [logical.x, logical.y], window_size = [window.x, window.y],
		max_fps = Engine.max_fps, vsync_mode = DisplayServer.window_get_vsync_mode(), camera_view = scene._view_name(),
		shadow_mode = scene._shadow_mode, auto_zoom = scene._rig.auto_zoom}


func _safe_output_paths(frame: String, receipt: String, stream_created: bool) -> bool:
	if not frame.is_absolute_path() or not receipt.is_absolute_path(): return false
	if receipt.get_base_dir() != frame.get_base_dir() or receipt.get_file() != "health-" + frame.get_file(): return false
	var bundle := OS.get_executable_path().get_base_dir().get_base_dir().get_base_dir().replace("\\", "/").simplify_path()
	if not _unlinked_directory(bundle): return false
	var unique := {}
	for target: String in [frame, frame + ".frames.jsonl", receipt]:
		var absolute := target.replace("\\", "/")
		if absolute != absolute.simplify_path() or not absolute.is_absolute_path(): return false
		var key := absolute.to_lower()
		if key == bundle.to_lower() or key.begins_with(bundle.to_lower() + "/") or unique.has(key): return false
		unique[key] = true
		var directory := absolute.get_base_dir()
		if not _unlinked_directory(directory): return false
		var parent := DirAccess.open(directory)
		if parent == null or parent.is_link(absolute) or DirAccess.dir_exists_absolute(absolute): return false
		if absolute == frame + ".frames.jsonl" and stream_created:
			if not FileAccess.file_exists(absolute): return false
		elif FileAccess.file_exists(absolute): return false
	return true


func _unlinked_directory(directory: String) -> bool:
	if not directory.is_absolute_path() or not DirAccess.dir_exists_absolute(directory): return false
	var current := directory
	while not current.is_empty():
		var parent := current.get_base_dir()
		if parent == current: return true
		if parent.is_empty(): return false
		var access := DirAccess.open(parent)
		if access == null or access.is_link(current): return false
		current = parent
	return false
