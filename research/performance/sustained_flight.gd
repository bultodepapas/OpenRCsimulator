extends SceneTree
## Bounded unattended player-flight workload for native frame collection.
## The scene owns all physics ticks. No state is repositioned or manually stepped.
## Required: --frametimes=<new absolute JSON> --sustained-receipt=<new absolute JSON>.
## Optional: --warmup=<wall seconds> --t=<wall seconds> --sustained-hash.
## --sustained-observation=off is an ineligible observer-cost control.
## Headless fixed-fps diagnostics may add --sustained-diagnostic-ticks=<1..432000>.
## DT-MAC-03b attribution sweeps may add --sustained-render-scale=<0.25..1> (bilinear
## 3D scale), --sustained-msaa=<0..3> (Viewport.MSAA) and/or --sustained-reconstruction=<Reconstruction
## mode> (MetalFX also needs OPENRC_METALFX_TRIAL=1; refusals fall back to Native); the receipt records them
## as scenario.render_override, so such runs never compare with default captures.
## --sustained-hide-shader=<name>[,<name>] hides geometry drawn with res://**/<name>.gdshader
## (re-applied every 60 frames for streamed chunks). It removes visible work, so the
## checked-runner reconciliation always refuses such runs: GPU attribution only.
## --sustained-shader-param=<shader>.<param>=<number>[,...] forces a float/int/bool shader
## parameter on every material of that shader, every frame (same refusal; attribution only).

const Simulation := preload("res://sim/simulation.gd")
const FlightLog := preload("res://sim/flight_log.gd")
const Reconstruction := preload("res://render/reconstruction.gd")
const CloudShadowMap := preload("res://render/cloud_shadow_map.gd")
const CloudShaderVariants := preload("res://render/cloud_shader_variants.gd")
const FixedWingContactObserver := preload("res://statistics/fixed_wing_adapter.gd")
const ROUTE := "benchmark-input-circuit"
const SEED := 20261021
const PHYSICS_HZ := 240
const MAX_ROWS := 4096
const MAX_DIAGNOSTIC_TICKS := 432000
const CHECKPOINT_TICKS := 6000
const DWELL_USEC := 2_500_000
const AUDIO_RETIRE_TIMEOUT_USEC := 250_000
const FORCED_OPTIONS := {"aircraft": "jensen-das-ugly-stik-60", "start": "airborne",
	"rates": "full", "weather": "calm", "landscape": "club_field", "companions": "0",
	"physics-backend": "gdscript_reference"}
const REJECTED_OPTIONS := ["quick-flight", "scripted", "trace", "capture", "visual_pose", "visual_distance",
	"visual_elevation", "visual_azimuth", "hide_airplane", "experimental-aircraft-data", "electric-demo",
	"weather-file", "wind-speed", "wind-from", "gust-speed", "gust-up", "gust-duration", "gust-period",
	"gust-delay", "alt", "fuel", "flight-log", "shaft-integrator", "failure-seed", "failures",
	"catastrophic", "out-of-trim", "battery", "companions-seed", "native-qualification", "flight-log-cli", "case"]

class Observer extends Node:
	var host: Object
	func _process(_delta: float) -> void:
		if is_instance_valid(host): host.call("_observe_frame")
	func _notification(what: int) -> void:
		if is_instance_valid(host) and what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT]:
			host.call("_focus_lost")


class FocusReadiness extends Node:
	const STABLE_USEC := 500_000
	const TIMEOUT_USEC := 5_000_000
	var deadline_usec := 0
	var stable_since_usec := -1
	var losses := 0
	var observed_losses := 0
	func _notification(what: int) -> void:
		if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT]:
			losses += 1
	func begin(now_usec: int) -> void:
		deadline_usec = now_usec + TIMEOUT_USEC
		stable_since_usec = -1
		observed_losses = losses
	func observe(now_usec: int, focused: bool, drawable: bool) -> int:
		if now_usec > deadline_usec: return -1
		if losses != observed_losses:
			stable_since_usec = -1
			observed_losses = losses
		if not focused or not drawable:
			stable_since_usec = -1
		elif stable_since_usec < 0:
			stable_since_usec = now_usec
		if stable_since_usec >= 0 and now_usec - stable_since_usec >= STABLE_USEC: return 1
		return -1 if now_usec >= deadline_usec else 0

var scene: Node
var adapter: RefCounted
var observer: Observer
var contact_observer: RefCounted
var frame_path := ""
var receipt_path := ""
var capture_id := ""
var diagnostic_ticks := 0
var hashes_enabled := false
var observation_enabled := true
var render_override: Variant = null
var render_previous: Dictionary = {}
var render_observation: Dictionary = {}
var cloud_previous_generation := -1
var cloud_observation: Dictionary = {}
var bounds_at_construction: Dictionary = {}
var bounds_observation: Dictionary = {}
var hide_shaders: PackedStringArray = []
var hidden_instances := {}
var hide_scan_frames := 0
var shader_params: Array[Dictionary] = []
var param_materials: Array[ShaderMaterial] = []
var failure := ""
var sealed := false
var seal_exit_code := -1
var seal_usec := 0
var last_tick := 0
var sealed_tick := 0
var samples: Array[Dictionary] = []
var checkpoints: Array[Dictionary] = []
var checkpoint_hash: HashingContext
var checkpoint_start_tick := 1
var source_hashes: Dictionary = {}
var input_script_path := ""
var source_digest := ""
var sealed_input: Dictionary = {}
var scenario: Dictionary = {}
var initial_state: Array = []
var min_altitude_m := INF
var observer_usec := 0
var observer_calls := 0
var abort_pending := false
var diagnostic_reached := false
var observation_start_usec := 0
var observation_end_usec := 0
var physics_enabled_throughout := true
var input_enabled_throughout := true
var external_driver_disabled_throughout := true
var automatic_callbacks_throughout := true
var violations := {tick_discontinuity = 0, nonfinite = 0, input_ownership = 0, crash = 0,
	fault = 0, pause = 0, hold = 0, contact = 0, prop_strike = 0, pilot_failure = 0,
	focus_loss = 0, observation_overflow = 0}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var parsed := _options(OS.get_cmdline_user_args())
	if not parsed.ok:
		printerr("Sustained flight refused: ", parsed.reason)
		quit(2)
		return
	frame_path = parsed.frame_path
	receipt_path = parsed.receipt_path
	diagnostic_ticks = parsed.diagnostic_ticks
	hashes_enabled = parsed.hashes_enabled
	observation_enabled = parsed.observation_enabled
	render_override = parsed.render_override
	hide_shaders = parsed.hide_shaders
	shader_params = parsed.shader_params
	if Engine.physics_ticks_per_second != PHYSICS_HZ or Engine.time_scale != 1.0:
		_fail_start("requires the normal 240 Hz and time_scale=1")
		return
	# Godot consumes known engine flags before exposing cmdline args to scripts.
	# The checked-runner command must independently rule out --fixed-fps or
	# other non-normal clocks for a timing claim; do not infer their absence.
	capture_id = OS.get_environment("OPENRC_DIAGNOSTIC_CAPTURE_ID")
	if capture_id.is_empty():
		capture_id = "sustained-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
		OS.set_environment("OPENRC_DIAGNOSTIC_CAPTURE_ID", capture_id)
	var focus_readiness: FocusReadiness
	if DisplayServer.get_name() != "headless":
		focus_readiness = FocusReadiness.new()
		root.add_child(focus_readiness)
		root.grab_focus()
		# Native activation can emit asynchronous focus events. Require a
		# continuous visible, focused interval before Main starts.
		focus_readiness.begin(Time.get_ticks_usec())
		var readiness := focus_readiness.observe(Time.get_ticks_usec(), root.has_focus(), root.can_draw())
		while readiness == 0:
			await process_frame
			readiness = focus_readiness.observe(Time.get_ticks_usec(), root.has_focus(), root.can_draw())
		if readiness < 0:
			focus_readiness.free()
			_fail_start("native window did not remain focused and drawable for startup")
			return
	input_script_path = get_script().resource_path.get_base_dir().path_join("sustained_input.gd")
	var input_script: Script = load(input_script_path)
	if input_script == null:
		_fail_start("cannot load sustained_input.gd")
		return
	adapter = input_script.new()
	source_hashes = _source_hashes(input_script_path)
	for path: String in source_hashes:
		if str(source_hashes[path]).length() != 64:
			_fail_start("source identity unavailable: " + path)
			return
	source_digest = _source_digest(source_hashes)
	var scene_args: PackedStringArray = parsed.scene_args
	scene_args.append("--case=" + ROUTE + "-" + source_digest)
	TranslationServer.set_locale("en")
	var msaa: int = Viewport.MSAA_4X
	if render_override is Dictionary and render_override.has("msaa_3d"): msaa = int(render_override.msaa_3d)
	var reconstruction := "native"
	if render_override is Dictionary and render_override.has("reconstruction"): reconstruction = str(render_override.reconstruction)
	Reconstruction.apply(root, {reconstruction = reconstruction, msaa_3d = msaa})
	# Native keeps bilinear scaling; only the input scale changes. Reconstruction's
	# runtime guard re-applies only FSR/DLSS failures, so this stays for the flight.
	if render_override is Dictionary and render_override.has("scaling_3d_scale"):
		root.scaling_3d_scale = float(render_override.scaling_3d_scale)
	bounds_at_construction = CloudShaderVariants.diagnostics()
	scene = load("res://main.tscn").instantiate()
	if scene == null:
		_fail_start("cannot instantiate the production Main scene")
		return
	scene.external_controller_selection = true
	scene.frametimes_auto_quit = false
	scene.frametimes_route = ROUTE
	scene.accident_archive_path = receipt_path + ".accident.json"
	scene.set_user_args(scene_args)
	# Starts before Main configures FrameSamples; the adapter and observers are
	# bound synchronously before the first automatic physics callback.
	observation_start_usec = Time.get_ticks_usec()
	root.add_child(scene)
	if not scene.startup_complete or not str(scene.startup_error).is_empty() or scene.session == null \
			or scene.session.sim == null or scene.session.sim.tick != 0 or not scene._frametimes_active:
		_fail_start("Main did not finish a valid frame-collecting flight at tick zero: " + str(scene.startup_error))
		return
	var session: Node = scene.session
	contact_observer = FixedWingContactObserver.new()
	contact_observer.session = session
	# This route selects no device; keep even a later accidental profile access
	# inside the run-owned directory instead of the player's calibration path.
	session.profiles_path = receipt_path + ".controls.cfg"
	if session.stage_backend_identity().get("backend") != "gdscript_reference" \
			or not session.sim.is_physics_processing() or not session.is_physics_processing():
		_fail_start("reference backend and automatic physics callbacks are required")
		return
	if not adapter.configure(session, scene.field, SEED):
		_fail_start("input adapter refused launch: " + adapter.failure)
		return
	adapter.failed.connect(_on_input_failure)
	session.read_raw = adapter.read_raw
	# Prevent desktop shortcuts from changing the route, while retaining normal
	# session input processing and the production keyboard sample callback.
	_disable_live_events(scene)
	if observation_enabled: session.sim.stepped.connect(_on_stepped)
	session.sim.faulted.connect(_on_faulted)
	session.sim.paused_changed.connect(_on_paused)
	scene.frame_time_report_written.connect(_on_sealed)
	initial_state = Array(session.sim.state)
	min_altitude_m = -float(session.sim.state[2])
	var initial_checkpoint: Dictionary = session.checkpoint()
	if initial_checkpoint.is_empty() or int(initial_checkpoint.get("simulation", {}).get("tick", -1)) != 0 \
			or str(initial_checkpoint.get("configuration", "")).length() != 64 \
			or str(initial_checkpoint.get("collision_world_identity", "")).length() != 64 \
			or str(initial_checkpoint.get("lake_identity", "")).length() != 64:
		_fail_start("validated tick-zero checkpoint, collision world and lake identities are required")
		return
	scenario = {aircraft_id = scene.aircraft_id, field_id = scene.field.id, seed = SEED,
		start_choice = session.start_choice, trim_speed_m_s = float(session.start.V),
		trim_throttle = float(session.start.throttle), rate_profile = session.rate_profile,
		weather = session.weather_configuration(), stage_backend = session.stage_backend_status(),
		input_semantics = "circuit demands to keyboard targets and rate-throttle; normal session rate limits",
		physics_hz = PHYSICS_HZ, control_update_ticks = 4,
		initial_checkpoint_sha256 = _hash_bytes(var_to_bytes(initial_checkpoint)),
		checkpoint_configuration = initial_checkpoint.configuration,
		collision_world_identity = initial_checkpoint.collision_world_identity,
		lake_identity = initial_checkpoint.lake_identity,
		solver_identity = FlightLog.replay_identity(),
		input_enabled = session.input_enabled, physics_enabled = session.physics_enabled,
		external_driver_enabled = session.external_driver_enabled,
		arguments = Array(scene_args), fixed_fps_diagnostic = diagnostic_ticks > 0,
		engine_clock_scope = "engine fixed-fps flag is not exposed to scripts; verify checked-runner command",
		observation_mode = "on" if observation_enabled else "off",
		state_input_hashing = hashes_enabled,
		settings_scope = "direct technical Main; native reconstruction, 4x MSAA; private accident archive"
			if render_override == null else "direct technical Main; DT-MAC-03b render_override diagnostic; private accident archive",
		render_override = render_override,
		accident_archive_path = scene.accident_archive_path, controller_profile_path = session.profiles_path}
	if absf(float(session.start.V) - 15.0) > 1e-9:
		_fail_start("reference Stik trim must be 15 m/s")
		return
	if not hide_shaders.is_empty():
		_hide_shader_geometry(scene)
		scenario["hidden_shader_geometry"] = {shaders = Array(hide_shaders), instances_at_start = hidden_instances.size()}
	if not shader_params.is_empty():
		_collect_param_materials(scene)
		var before := []
		for entry: Dictionary in shader_params:
			for material: ShaderMaterial in param_materials:
				if _shader_name(material.shader) == entry.shader:
					before.append({target = entry.shader + "." + entry.parameter, value = material.get_shader_parameter(entry.parameter)})
		_apply_shader_params()
		var readback := []
		for entry: Dictionary in shader_params:
			var values := []
			for material: ShaderMaterial in param_materials:
				if _shader_name(material.shader) == entry.shader:
					values.append(material.get_shader_parameter(entry.parameter))
			readback.append({target = entry.shader + "." + entry.parameter, values = values})
		scenario["forced_shader_parameters"] = {parameters = shader_params.duplicate(true),
			materials_at_start = param_materials.size(), before_at_start = before, readback_at_start = readback}
	if hashes_enabled: _new_checkpoint()
	if observation_enabled and not _record_sample(0):
		_fail_start("cannot record initial route health")
		return
	observer = Observer.new()
	observer.host = self
	bounds_at_construction["bound"] = _bound_cloud_density()
	render_previous = _render_snapshot()
	CloudShadowMap.diagnostics() # synchronize settings and prune prior consumers before observation
	cloud_previous_generation = CloudShadowMap.diagnostics_generation()
	root.add_child(observer)
	# Cover the synchronous handoff from settled window to flight observer.
	if focus_readiness != null:
		if focus_readiness.losses != focus_readiness.observed_losses or not root.has_focus() or not root.can_draw():
			focus_readiness.free()
			_fail_start("native window lost focus or visibility during flight startup")
			return
		focus_readiness.free()
	print("SUSTAINED_FLIGHT_READY capture_id=", capture_id, " route=", ROUTE,
		" start=", initial_state.slice(0, 3), " seed=", SEED)


func _options(arguments: PackedStringArray) -> Dictionary:
	var seen := {}
	var forwarded := PackedStringArray()
	var path := ""
	var receipt := ""
	var duration := 1800.0
	var warmup := 30.0
	var requested_ticks := 0
	var use_hash := false
	var use_observation := true
	var override := {}
	var hide := PackedStringArray()
	var params: Array[Dictionary] = []
	for arg: String in arguments:
		if not arg.begins_with("--"): return {ok = false, reason = "unexpected positional argument"}
		var pair := arg.trim_prefix("--").split("=", true, 1)
		var key: String = pair[0]
		if seen.has(key): return {ok = false, reason = "duplicate option --" + key}
		seen[key] = true
		var value: String = pair[1] if pair.size() == 2 else ""
		if REJECTED_OPTIONS.has(key): return {ok = false, reason = "unsupported workload option --" + key}
		if FORCED_OPTIONS.has(key):
			if value != str(FORCED_OPTIONS[key]): return {ok = false, reason = "conflicting workload option --" + key}
			continue
		match key:
			"sustained-receipt": receipt = value
			"sustained-diagnostic-ticks":
				if not value.is_valid_int(): return {ok = false, reason = "diagnostic ticks must be an integer"}
				requested_ticks = value.to_int()
				if requested_ticks < 1 or requested_ticks > MAX_DIAGNOSTIC_TICKS:
					return {ok = false, reason = "diagnostic ticks exceed bounds"}
			"sustained-hash":
				if pair.size() != 1: return {ok = false, reason = "--sustained-hash is a flag"}
				use_hash = true
			"sustained-observation":
				if value not in ["on", "off"]: return {ok = false, reason = "observation must be on or off"}
				use_observation = value == "on"
			"frametimes": path = value
			"t":
				if not value.is_valid_float(): return {ok = false, reason = "--t requires finite seconds"}
				duration = value.to_float()
			"warmup":
				if not value.is_valid_float(): return {ok = false, reason = "--warmup requires finite seconds"}
				warmup = value.to_float()
			"frametimes-stream":
				if pair.size() != 1: return {ok = false, reason = "--frametimes-stream is a flag"}
			"sustained-render-scale":
				if not value.is_valid_float() or not is_finite(value.to_float()) \
						or value.to_float() < 0.25 or value.to_float() > 1.0:
					return {ok = false, reason = "--sustained-render-scale requires 0.25..1"}
				override.scaling_3d_scale = value.to_float()
			"sustained-hide-shader":
				var names := value.split(",", false)
				if names.is_empty() or names.size() > 16:
					return {ok = false, reason = "--sustained-hide-shader requires 1..16 shader names"}
				for name: String in names:
					if name.is_empty() or name.length() > 64 or not name.is_valid_ascii_identifier():
						return {ok = false, reason = "--sustained-hide-shader names must be shader basenames"}
				hide = names
			"sustained-shader-param":
				var entries := value.split(",", false)
				if entries.is_empty() or entries.size() > 16:
					return {ok = false, reason = "--sustained-shader-param requires 1..16 entries"}
				for entry: String in entries:
					var assignment := entry.split("=", false, 1)
					var target := assignment[0].split(".", false, 1) if assignment.size() == 2 else PackedStringArray()
					if target.size() != 2 or not target[0].is_valid_ascii_identifier() or not target[1].is_valid_ascii_identifier() \
							or not assignment[1].is_valid_float() or not is_finite(assignment[1].to_float()):
						return {ok = false, reason = "--sustained-shader-param entries are shader.param=number"}
					params.append({shader = target[0], parameter = target[1], value = assignment[1].to_float()})
			"sustained-reconstruction":
				if value != Reconstruction.AUTO and not Reconstruction.MODE_PROVIDERS.has(value):
					return {ok = false, reason = "--sustained-reconstruction requires a Reconstruction mode"}
				override.reconstruction = value
			"sustained-msaa":
				if not value.is_valid_int() or value.to_int() < Viewport.MSAA_DISABLED or value.to_int() > Viewport.MSAA_8X:
					return {ok = false, reason = "--sustained-msaa requires an integer 0..3"}
				override.msaa_3d = value.to_int()
			_: forwarded.append(arg)
	if not path.is_absolute_path() or not receipt.is_absolute_path() or path == receipt \
			or FileAccess.file_exists(path) or FileAccess.file_exists(path + ".frames.jsonl") \
			or FileAccess.file_exists(receipt) or FileAccess.file_exists(receipt + ".accident.json") \
			or FileAccess.file_exists(receipt + ".controls.cfg"):
		return {ok = false, reason = "new, distinct absolute frame and receipt paths are required"}
	if not DirAccess.dir_exists_absolute(path.get_base_dir()) or not DirAccess.dir_exists_absolute(receipt.get_base_dir()):
		return {ok = false, reason = "output directories must already exist"}
	if not is_finite(duration) or duration <= 0.0 or duration > 1800.0 \
			or not is_finite(warmup) or warmup < 0.0 or warmup > 300.0:
		return {ok = false, reason = "duration must be (0,1800] and warmup [0,300] seconds"}
	if not use_observation and (use_hash or requested_ticks > 0):
		return {ok = false, reason = "observer-off control cannot request hashes or diagnostic tick stopping"}
	for key: String in FORCED_OPTIONS: forwarded.append("--%s=%s" % [key, FORCED_OPTIONS[key]])
	forwarded.append("--frametimes=" + path)
	forwarded.append("--frametimes-stream")
	forwarded.append("--t=" + str(duration))
	forwarded.append("--warmup=" + str(warmup))
	return {ok = true, frame_path = path, receipt_path = receipt, scene_args = forwarded,
		diagnostic_ticks = requested_ticks, hashes_enabled = use_hash, observation_enabled = use_observation,
		render_override = override if not override.is_empty() else null, hide_shaders = hide,
		shader_params = params}


func _hide_shader_geometry(node: Node) -> void:
	if node is GeometryInstance3D and node.visible and _uses_hidden_shader(node):
		node.visible = false
		hidden_instances[node.get_instance_id()] = true
	for child: Node in node.get_children():
		_hide_shader_geometry(child)


func _uses_hidden_shader(instance: GeometryInstance3D) -> bool:
	for material: Material in _materials_of(instance):
		while material != null:
			if material is ShaderMaterial and material.shader != null \
					and _shader_name(material.shader) in hide_shaders:
				return true
			material = material.next_pass
	return false


func _collect_param_materials(node: Node) -> void:
	var owned: Array[Material] = []
	if node is GeometryInstance3D:
		owned = _materials_of(node)
	elif node is WorldEnvironment and node.environment != null and node.environment.sky != null:
		owned = [node.environment.sky.sky_material] # e.g. sky.appearance_layer_count
	if not owned.is_empty():
		for material: Material in owned:
			while material != null:
				if material is ShaderMaterial and material.shader != null and not param_materials.has(material):
					var name := _shader_name(material.shader)
					for entry: Dictionary in shader_params:
						if entry.shader == name:
							param_materials.append(material)
							break
				material = material.next_pass
	for child: Node in node.get_children():
		_collect_param_materials(child)


func _apply_shader_params() -> void:
	for material: ShaderMaterial in param_materials:
		var name := _shader_name(material.shader)
		for entry: Dictionary in shader_params:
			if entry.shader != name: continue
			# Keep the declared type: Godot rejects a float written to an int or bool uniform.
			var current: Variant = material.get_shader_parameter(entry.parameter)
			var value: Variant = entry.value
			if typeof(current) == TYPE_INT: value = int(entry.value)
			elif typeof(current) == TYPE_BOOL: value = entry.value != 0.0
			# Write only on change: a redundant sky write would refilter its radiance every frame.
			if current != value:
				material.set_shader_parameter(entry.parameter, value)


func _materials_of(instance: GeometryInstance3D) -> Array[Material]:
	var materials: Array[Material] = [instance.material_override, instance.material_overlay]
	var mesh: Mesh = null
	if instance is MeshInstance3D:
		mesh = instance.mesh
		for surface: int in instance.get_surface_override_material_count():
			materials.append(instance.get_surface_override_material(surface))
	elif instance is MultiMeshInstance3D and instance.multimesh != null:
		mesh = instance.multimesh.mesh
	if mesh != null:
		for surface: int in mesh.get_surface_count():
			materials.append(mesh.surface_get_material(surface))
	return materials


func _shader_name(shader: Shader) -> String:
	return str(shader.get_meta(&"openrc_base_shader_path", shader.resource_path)).get_file().get_basename()


func _bound_cloud_density() -> String:
	if not is_instance_valid(scene) or not is_instance_valid(scene._world_environment) \
			or scene._world_environment.environment == null or scene._world_environment.environment.sky == null:
		return "unknown"
	var material: Variant = scene._world_environment.environment.sky.sky_material
	if not material is ShaderMaterial or material.shader == null or _shader_name(material.shader) != "sky":
		return "unknown"
	return str(material.shader.get_meta(&"openrc_cloud_density_bounds", "off"))


func _disable_live_events(node: Node) -> void:
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false)
	node.set_process_shortcut_input(false)
	for child: Node in node.get_children(): _disable_live_events(child)


func _on_stepped(tick: int, _time: float, state: PackedFloat64Array, _loads: PackedFloat64Array,
		inputs: PackedFloat64Array, aux: PackedFloat64Array) -> void:
	if sealed: return
	var began := Time.get_ticks_usec()
	observer_calls += 1
	if tick != last_tick + 1:
		_mark_failure("tick_discontinuity", "accepted tick discontinuity: %d after %d" % [tick, last_tick])
	last_tick = tick
	var session: Node = scene.session
	if not Simulation.state_is_valid(state) or not _finite(inputs) or not _finite(aux) \
			or not _finite(session.sim.continuous):
		_mark_failure("nonfinite", "nonfinite or invalid accepted state")
	physics_enabled_throughout = physics_enabled_throughout and session.physics_enabled
	input_enabled_throughout = input_enabled_throughout and session.input_enabled
	external_driver_disabled_throughout = external_driver_disabled_throughout and not session.external_driver_enabled
	automatic_callbacks_throughout = automatic_callbacks_throughout \
		and session.is_physics_processing() and session.sim.is_physics_processing()
	if not physics_enabled_throughout or not input_enabled_throughout or not external_driver_disabled_throughout \
			or not automatic_callbacks_throughout or session.radio.connected or session.read_raw != adapter.read_raw:
		_mark_failure("input_ownership", "automatic keyboard input ownership changed")
	if not session.crash.is_empty(): _mark_failure("crash", "flight crashed")
	if not session.sim.fault_reason.is_empty(): _mark_failure("fault", "simulation fault")
	if session.sim.paused or not session.pause_reason.is_empty(): _mark_failure("pause", "simulation paused")
	if not session.holds.is_empty(): _mark_failure("hold", "session acquired a hold")
	if not session.prop_strike.is_empty(): _mark_failure("prop_strike", "propeller strike")
	var contacts: Dictionary = session.contact_events()
	if not contacts.get("events", []).is_empty() or not contacts.get("active_hull_ids", []).is_empty():
		_mark_failure("contact", "accepted hull, scenery, lake or propeller contact")
	# Existing statistics helper preserves each wheel's positive-contact flag;
	# near the terrain envelope it falls back to session.gear_compressions.
	for compression: float in contact_observer._compressions(state):
		if not is_finite(compression): _mark_failure("nonfinite", "invalid gear clearance")
		elif compression > 0.0: _mark_failure("contact", "landing gear touched the ground")
	min_altitude_m = minf(min_altitude_m, -state[2])
	if hashes_enabled: _update_checkpoint(tick, state, inputs, aux, session.sim.continuous, session.sim.modes)
	if tick % PHYSICS_HZ == 0 and not _record_sample(tick):
		_mark_failure("observation_overflow", "bounded health sample limit or observation failed")
	if diagnostic_ticks > 0 and tick >= diagnostic_ticks and not diagnostic_reached:
		diagnostic_reached = true
		_finish_diagnostic.call_deferred()
	observer_usec += Time.get_ticks_usec() - began


func _record_sample(tick: int) -> bool:
	if samples.size() >= MAX_ROWS: return false
	var state: PackedFloat64Array = scene.session.sim.state
	var terrain: PackedFloat64Array = scene.session.environment.ground(state[0], state[1])
	if terrain.is_empty() or not is_finite(terrain[0]): return false
	var clearance := -state[2] - terrain[0]
	if not is_finite(clearance): return false
	var north_error: float = state[0] - float(adapter.pilot.get("_center_north_m"))
	var east_error: float = state[1] - float(adapter.pilot.get("_center_east_m"))
	var radius_error: float = sqrt(north_error * north_error + east_error * east_error) - float(adapter.pilot.get("_radius_m"))
	if not is_finite(radius_error): return false
	samples.append({tick = tick, time_s = scene.session.sim.time(), north_m = state[0], east_m = state[1],
		altitude_m = -state[2], ground_clearance_m = clearance, radius_error_m = radius_error})
	return true


func _finite(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value): return false
	return true


func _new_checkpoint() -> void:
	checkpoint_hash = HashingContext.new()
	checkpoint_hash.start(HashingContext.HASH_SHA256)


func _update_checkpoint(tick: int, state: PackedFloat64Array, inputs: PackedFloat64Array,
		aux: PackedFloat64Array, continuous: PackedFloat64Array, modes: PackedInt64Array) -> void:
	checkpoint_hash.update(PackedInt64Array([tick]).to_byte_array())
	for values: PackedFloat64Array in [state, inputs, aux, continuous]: checkpoint_hash.update(values.to_byte_array())
	checkpoint_hash.update(modes.to_byte_array())
	if tick % CHECKPOINT_TICKS == 0:
		checkpoints.append({start_tick = checkpoint_start_tick, end_tick = tick,
			sha256 = checkpoint_hash.finish().hex_encode()})
		checkpoint_start_tick = tick + 1
		_new_checkpoint()


func _observe_frame() -> void:
	if not sealed:
		_observe_render()
	if not shader_params.is_empty() and not sealed:
		if hide_scan_frames % 60 == 0 and is_instance_valid(scene):
			_collect_param_materials(scene)
			scenario.forced_shader_parameters["materials_total"] = param_materials.size()
		_apply_shader_params()
		if hide_shaders.is_empty(): hide_scan_frames += 1
	if not hide_shaders.is_empty() and not sealed:
		hide_scan_frames += 1
		if hide_scan_frames % 60 == 0 and is_instance_valid(scene):
			_hide_shader_geometry(scene)
			scenario.hidden_shader_geometry["instances_total"] = hidden_instances.size()
	if not sealed:
		if not is_instance_valid(scene) or scene.session == null:
			_mark_failure("input_ownership", "flight scene disappeared")
		elif DisplayServer.get_name() != "headless" and not root.has_focus():
			_mark_failure("focus_loss", "native flight window lost focus")
		elif observation_enabled:
			# A disabled physics callback cannot report its own disappearance via
			# stepped; check ownership independently from the render loop as well.
			var session: Node = scene.session
			physics_enabled_throughout = physics_enabled_throughout and session.physics_enabled
			input_enabled_throughout = input_enabled_throughout and session.input_enabled
			external_driver_disabled_throughout = external_driver_disabled_throughout and not session.external_driver_enabled
			automatic_callbacks_throughout = automatic_callbacks_throughout and session.is_physics_processing() \
				and session.sim.is_physics_processing() and session.can_process() and session.sim.can_process()
			if not physics_enabled_throughout or not input_enabled_throughout or not external_driver_disabled_throughout \
					or not automatic_callbacks_throughout or session.radio.connected or session.read_raw != adapter.read_raw \
					or Engine.physics_ticks_per_second != PHYSICS_HZ or Engine.time_scale != 1.0:
				_mark_failure("input_ownership", "automatic physics or keyboard input ownership changed")
	elif Time.get_ticks_usec() - seal_usec >= DWELL_USEC:
		_write_receipt_and_exit()


func _focus_lost() -> void:
	if DisplayServer.get_name() != "headless":
		_mark_failure("focus_loss", "native flight window lost focus")


func _on_input_failure(reason: String) -> void:
	_mark_failure("pilot_failure", "input adapter: " + reason)


func _on_faulted(reason: String) -> void:
	_mark_failure("fault", "simulation fault: " + reason)


func _on_paused(paused: bool) -> void:
	if paused: _mark_failure("pause", "simulation paused during flight")


func _mark_failure(category: String, reason: String) -> void:
	if sealed: return
	violations[category] = int(violations.get(category, 0)) + 1
	if failure.is_empty(): failure = reason
	if not abort_pending:
		abort_pending = true
		_abort_collection.call_deferred()


func _abort_collection() -> void:
	if not sealed and is_instance_valid(scene) and scene._frametimes_active:
		scene._finish_frame_time(1)
	elif not sealed:
		_fail_start(failure)


func _finish_diagnostic() -> void:
	if not sealed and failure.is_empty() and is_instance_valid(scene) and scene._frametimes_active:
		# A deliberately incomplete wall-time stream: this validates trajectory,
		# never native FPS or a complete timed capture.
		scene._finish_frame_time(1)


func _on_sealed(exit_code: int) -> void:
	if sealed: return
	_observe_render(true)
	scenario["effective_render"] = render_observation.duplicate(true)
	scenario["cloud_cache"] = cloud_observation.duplicate(true)
	scenario["cloud_density_bounds"] = bounds_observation.duplicate(true)
	if not observation_enabled:
		last_tick = int(scene.session.sim.tick)
	elif samples.is_empty() or int(samples[-1].tick) != last_tick:
		if not _record_sample(last_tick):
			_mark_failure("observation_overflow", "cannot record final route health")
	observation_end_usec = Time.get_ticks_usec()
	sealed_input = {input_reads = adapter.input_reads, last_read_tick = adapter.last_read_tick,
		pilot_updates = adapter.pilot_updates, pilot_failure = adapter.failure,
		input_elapsed_usec = adapter.input_elapsed_usec, pilot_elapsed_usec = adapter.pilot_elapsed_usec,
		min_ground_clearance_m = adapter.min_clearance_m, max_abs_radius_error_m = adapter.max_abs_radius_error_m}
	sealed = true
	seal_exit_code = exit_code
	sealed_tick = last_tick
	seal_usec = Time.get_ticks_usec()
	if hashes_enabled and checkpoint_start_tick <= sealed_tick:
		checkpoints.append({start_tick = checkpoint_start_tick, end_tick = sealed_tick,
			sha256 = checkpoint_hash.finish().hex_encode(), partial = true})


func _render_snapshot() -> Dictionary:
	var saved: Variant = root.get_meta(&"openrc_reconstruction", {})
	var policy := {}
	for key: String in ["requested", "requested_provider", "selected", "effective", "provider",
			"effective_provider", "execution_status", "provider_available", "fallback", "fallback_reason", "temporal"]:
		policy[key] = saved.get(key) if saved is Dictionary else null
	if policy.requested == Reconstruction.AUTO and saved is Dictionary:
		policy["auto_selected"] = saved.get("auto_selected")
		policy["auto_output_size"] = saved.get("auto_output_size")
	policy["scaling_3d_mode"] = root.scaling_3d_mode
	policy["scale"] = root.scaling_3d_scale
	policy["msaa_3d"] = root.msaa_3d
	var provider := str(policy.get("provider", ""))
	var mode_constant := "SCALING_3D_MODE_BILINEAR" if provider == "native" \
		else "SCALING_3D_MODE_" + provider.to_upper()
	var mode_id: Variant = ClassDB.class_get_integer_constant("Viewport", mode_constant) \
		if ClassDB.class_has_integer_constant("Viewport", mode_constant) else null
	var snapshot := {backend = RenderingServer.get_current_rendering_method(),
		driver = RenderingServer.get_current_rendering_driver_name(), scaling_3d_mode = root.scaling_3d_mode,
		scaling_3d_mode_constant = mode_constant, provider_mode_id = mode_id,
		scaling_3d_scale = root.scaling_3d_scale, msaa_3d = root.msaa_3d, reconstruction = policy}
	if policy.requested == Reconstruction.AUTO:
		# Auto uses Window.size at apply time; keep that property and the visible rect
		# separately. Neither measurement proves physical presentation pixels.
		snapshot["window_size_property"] = [root.size.x, root.size.y]
		var visible := root.get_visible_rect().size
		snapshot["visible_rect_size"] = [visible.x, visible.y]
	return snapshot


## The preceding process-frame observation brackets the first retained frame. Observe
## every subsequent frame, including the synchronous final report/seal callback.
func _observe_render(final := false) -> void:
	var current := _render_snapshot()
	var generation := CloudShadowMap.diagnostics_generation()
	var bounds := CloudShaderVariants.diagnostics()
	bounds["bound"] = _bound_cloud_density()
	if is_instance_valid(scene) and scene._frametime_samples != null \
			and int(scene._frametime_samples._actual_sample_start_usec) >= 0:
		if render_observation.is_empty():
			render_observation = {start = render_previous.duplicate(true), end = current,
				stable = render_previous == current, samples = 2}
		else:
			render_observation.stable = bool(render_observation.stable) and current == render_observation.start
			render_observation.end = current
			render_observation.samples += 1
		if cloud_observation.is_empty():
			var cloud := CloudShadowMap.diagnostics()
			var first_stable := cloud_previous_generation == generation and generation == int(cloud.generation)
			cloud_observation = {start = cloud, end = {},
				stable = first_stable,
				initial_generations = {previous_frame = cloud_previous_generation, before_snapshot = generation,
					after_snapshot = int(cloud.generation)},
				first_change = null if first_stable else {phase = "sample_start", observed_usec = Time.get_ticks_usec(),
					previous_frame = cloud_previous_generation, before_snapshot = generation, after_snapshot = int(cloud.generation)}}
			bounds_observation = {start = bounds_at_construction.duplicate(true), end = bounds,
				stable = bounds == bounds_at_construction}
		else:
			if generation != int(cloud_observation.start.generation) and cloud_observation.first_change == null:
				cloud_observation.first_change = {phase = "sample", observed_usec = Time.get_ticks_usec(),
					previous_frame = cloud_previous_generation, current = generation}
			cloud_observation.stable = bool(cloud_observation.stable) \
				and generation == int(cloud_observation.start.generation)
			bounds_observation.stable = bool(bounds_observation.stable) and bounds == bounds_observation.start
			bounds_observation.end = bounds
		if final:
			var cloud := CloudShadowMap.diagnostics()
			cloud_observation.end = cloud
			cloud_observation["final_generations"] = {before_snapshot = generation, after_snapshot = int(cloud.generation)}
			if (generation != int(cloud.generation) or cloud != cloud_observation.start) \
					and cloud_observation.first_change == null:
				cloud_observation.first_change = {phase = "seal_snapshot", observed_usec = Time.get_ticks_usec(),
					before_snapshot = generation, after_snapshot = int(cloud.generation)}
			cloud_observation.stable = bool(cloud_observation.stable) \
				and generation == int(cloud.generation) and cloud == cloud_observation.start
	render_previous = current
	cloud_previous_generation = CloudShadowMap.diagnostics_generation()


func _source_hashes(input_path: String) -> Dictionary:
	# Include the visible application resource tree, including rendering scripts,
	# shaders, authored assets, import recipes and project settings. Hidden engine
	# caches are separate evidence and are deliberately not treated as source.
	var out := {}
	var pending: Array[String] = ["res://"]
	while not pending.is_empty():
		var base: String = pending.pop_back()
		var dir := DirAccess.open(base)
		if dir == null or dir.list_dir_begin() != OK:
			out[base] = "" # fail closed if the tree cannot be read
			break
		var name := dir.get_next()
		while not name.is_empty():
			if name.begins_with("."):
				name = dir.get_next()
				continue
			var path := base.path_join(name)
			if dir.is_link(name):
				out[path] = "" # never silently omit a linked input
			elif dir.current_is_dir():
				pending.append(path)
			else:
				out[path] = FileAccess.get_sha256(path)
			if out.size() > 8190:
				out["source-limit-exceeded"] = ""
				break
			name = dir.get_next()
		dir.list_dir_end()
		if out.has("source-limit-exceeded"): break
	out["research/performance/sustained_input.gd"] = FileAccess.get_sha256(input_path)
	out["research/performance/sustained_flight.gd"] = FileAccess.get_sha256(get_script().resource_path)
	return out


func _hash_bytes(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _source_digest(hashes: Dictionary) -> String:
	var names: Array = hashes.keys()
	names.sort()
	var canonical := ""
	for path: String in names:
		canonical += path + ":" + str(hashes[path]) + "\n"
	return _hash_bytes(canonical.to_utf8_buffer())


func _write_receipt_and_exit() -> void:
	var frame: Variant = JSON.parse_string(FileAccess.get_file_as_string(frame_path)) if FileAccess.file_exists(frame_path) else null
	var report_valid: bool = frame is Dictionary and frame.get("capture_id") == capture_id \
		and frame.get("route") == ROUTE and frame.get("case_id") == ROUTE + "-" + source_digest
	var frame_collection_complete: bool = report_valid and bool(frame.get("complete", false)) and seal_exit_code == 0 and diagnostic_ticks == 0
	var timing_complete: bool = frame_collection_complete and observation_enabled
	var diagnostic_complete: bool = diagnostic_ticks > 0 and diagnostic_reached and sealed_tick >= diagnostic_ticks \
			and report_valid and not bool(frame.get("complete", true))
	var input_coverage_ok: bool = int(sealed_input.get("input_reads", -1)) == sealed_tick \
		and int(sealed_input.get("last_read_tick", -1)) == sealed_tick - 1 and observation_start_usec > 0 \
		and observation_end_usec >= observation_start_usec
	var coverage_ok: bool = observation_enabled and observer_calls == sealed_tick and input_coverage_ok
	var source_unchanged: bool = _source_hashes(input_script_path) == source_hashes
	var valid: bool = failure.is_empty() and coverage_ok and source_unchanged and (timing_complete or diagnostic_complete)
	var control_complete: bool = not observation_enabled and frame_collection_complete and input_coverage_ok \
		and source_unchanged and failure.is_empty()
	var report := {format = "openrc-benchmark-health v1", capture_id = capture_id, route = ROUTE,
		complete = valid, timing_complete = timing_complete, diagnostic_complete = diagnostic_complete,
		frame_collection_complete = frame_collection_complete, observer_off_control_complete = control_complete,
		timing_eligible = valid and timing_complete and DisplayServer.get_name() != "headless",
		timing_eligibility_scope = "fixture checks only; checked runner must separately establish the engine command and normal clocks",
		failure = failure if not failure.is_empty() else ("incomplete tick observation" if not coverage_ok and not control_complete else ("source changed" if not source_unchanged else "")),
		report = frame_path.get_file(), report_sha256 = FileAccess.get_sha256(frame_path),
		frame_report = frame_path, frame_report_sha256 = FileAccess.get_sha256(frame_path),
		frame_stream_sha256 = str(frame.get("stream", {}).get("sha256", "")) if frame is Dictionary else "",
		frame_capture_id_matches = report_valid, frame_exit_code = seal_exit_code,
		scenario = scenario, source_sha256 = source_hashes, source_digest = source_digest,
		source_scope = "application-visible-tree-v1",
		source_unchanged = source_unchanged, initial_state = initial_state,
		observation = {start_monotonic_usec = observation_start_usec, end_monotonic_usec = observation_end_usec,
			start_tick = 0, end_tick = sealed_tick, accepted_ticks = sealed_tick, input_reads = sealed_input.input_reads,
			observer_calls = observer_calls, physics_enabled_throughout = observation_enabled and physics_enabled_throughout,
			input_enabled_throughout = observation_enabled and input_enabled_throughout,
			external_driver_disabled_throughout = observation_enabled and external_driver_disabled_throughout,
			automatic_callbacks_throughout = observation_enabled and automatic_callbacks_throughout},
		violations = violations,
		health = {scope = "accepted endpoints through frame seal; ground clearance and radial error sampled at 60 Hz",
			accepted_ticks = sealed_tick, last_read_tick = sealed_input.last_read_tick, input_reads = sealed_input.input_reads,
			pilot_updates = sealed_input.pilot_updates, pilot_failure = sealed_input.pilot_failure,
			input_elapsed_usec = sealed_input.input_elapsed_usec, pilot_elapsed_usec = sealed_input.pilot_elapsed_usec,
			input_timing_scope = "whole read_raw callback including its nested pilot; no cost subtraction",
			min_altitude_m = min_altitude_m if is_finite(min_altitude_m) else null,
			min_ground_clearance_m = sealed_input.min_ground_clearance_m if is_finite(sealed_input.min_ground_clearance_m) else null,
			max_abs_radius_error_m = sealed_input.max_abs_radius_error_m, samples_1hz = samples,
			observer_calls = observer_calls, observer_usec = observer_usec,
			observer_scope = "accepted-tick health checks and optional state/input hashing; excludes input adapter and receipt finalization"},
		checkpoints = checkpoints, hash_scope = "independent 6000-tick accepted state/input/aux/mode windows" if hashes_enabled else "disabled",
		dwell_after_frame_seal_s = float(Time.get_ticks_usec() - seal_usec) / 1000000.0,
		note = "Rate-limited synthetic keyboard input; complete physics flight is not physical validation. Compare observer overhead separately."}
	if FileAccess.file_exists(receipt_path):
		printerr("Sustained receipt appeared during capture; refusing overwrite")
		quit(1)
		return
	var file := FileAccess.open(receipt_path, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write sustained receipt: ", receipt_path)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	file.flush()
	var error := file.get_error()
	file.close()
	print("SUSTAINED_FLIGHT_COMPLETE complete=", valid, " timing=", timing_complete, " observer_off_control=", control_complete,
		" ticks=", sealed_tick, " receipt=", receipt_path)
	var exit_code := 0 if (valid or control_complete) and error == OK else 1
	if is_instance_valid(observer):
		observer.set_process(false) # The receipt is sealed; do not finalize it again.
	call_deferred("_retire_flight_and_quit", exit_code)


## Observe currently exposed player playbacks without extending their lifetime.
## A player may own other server-side playbacks, so this is not a leak census.
func _collect_audio_playbacks(node: Node, playbacks: Array[WeakRef]) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		if bool(node.call("has_stream_playback")):
			var playback: Variant = node.call("get_stream_playback")
			if playback is AudioStreamPlayback:
				playbacks.append(weakref(playback))
	for child: Node in node.get_children():
		_collect_audio_playbacks(child, playbacks)


func _remaining_audio_playbacks(playbacks: Array[WeakRef]) -> int:
	var remaining := 0
	for playback: WeakRef in playbacks:
		if playback.get_ref() != null:
			remaining += 1
	return remaining


## Retire the flight only after its frame and health receipts are finalized.
## The wall-time bound is checked once per process frame and can overshoot if
## frame delivery stalls. Preserve the capture's original exit code.
func _retire_flight_and_quit(exit_code: int) -> void:
	var playbacks: Array[WeakRef] = []
	if is_instance_valid(scene):
		_collect_audio_playbacks(scene, playbacks)
		if scene.get_parent() == root:
			root.remove_child(scene) # Runs the production flight/audio exit hooks.
		scene.queue_free()
		scene = null
	if is_instance_valid(observer):
		observer.queue_free()
		observer = null
	var started := Time.get_ticks_usec()
	await process_frame # Allow queued scene and observer frees even without playbacks.
	var remaining := _remaining_audio_playbacks(playbacks)
	while remaining > 0 and Time.get_ticks_usec() - started < AUDIO_RETIRE_TIMEOUT_USEC:
		await process_frame
		remaining = _remaining_audio_playbacks(playbacks)
	var elapsed := Time.get_ticks_usec() - started
	var status := "timeout" if remaining > 0 else "observed_released"
	print("SUSTAINED_FLIGHT_AUDIO_TEARDOWN status=", status, " driver=", AudioServer.get_driver_name(),
		" tracked=", playbacks.size(), " pending=", remaining, " elapsed_usec=", elapsed,
		" timeout_usec=", AUDIO_RETIRE_TIMEOUT_USEC)
	if remaining > 0:
		push_warning("Sustained flight audio teardown timed out with %d observed playback(s) pending" % remaining)
	quit(exit_code)


func _fail_start(reason: String) -> void:
	printerr("Sustained flight failed: ", reason)
	quit(1)
