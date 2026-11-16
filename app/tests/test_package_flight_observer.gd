extends SceneTree

const Observer := preload("res://tools/package_flight_observer.gd")
const Flight := preload("res://sim/flight_session.gd")

class FakeRig extends RefCounted:
	var auto_zoom := true

class FakeRadio extends RefCounted:
	var connected := false

class FakePilot extends RefCounted:
	func read_raw() -> Dictionary: return {}

class FakeSession extends Node:
	var physics_enabled := true
	var input_enabled := true
	var external_driver_enabled := false
	var radio := FakeRadio.new()
	var sim: Node
	var read_raw: Callable
	var external_controller_selection := false
	func weather_configuration() -> Dictionary: return {}

class FakeScene extends Node:
	var _rig := FakeRig.new()
	var _shadow_mode := "sun"
	var _engine_audio: AudioStreamPlayer3D
	var _lake_ambience: AudioStreamPlayer3D
	var companions: Node
	var _soundscape_audio: Node
	var _lens: Node
	var _lens_args: Dictionary = {}
	var companion_config: Dictionary = {}
	var watch: Node
	var input_actions := 0
	var invalidated_before_action := 0
	func _view_name() -> String: return "pilot"
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.physical_keycode not in [KEY_V, KEY_Z]: return
			input_actions += 1
			if is_instance_valid(watch) and watch.violations.input_ownership > 0:
				invalidated_before_action += 1
			if event.physical_keycode == KEY_V: _shadow_mode = "off" if _shadow_mode == "sun" else "sun"
			else: _rig.auto_zoom = not _rig.auto_zoom

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(not Observer._tick_gap_invalid(100, 100), "same clock value is valid")
	_check(not Observer._tick_gap_invalid(100, 1_000_100), "one second is the inclusive limit")
	_check(Observer._tick_gap_invalid(100, 1_000_101), "a longer gap fails")
	_check(Observer._tick_gap_invalid(100, 99), "a backward clock fails")
	_check(Observer._tick_gap_invalid(0, 100), "missing earlier clock fails")
	var previous := 100
	var catch_up_tick := 1_000_101
	var step_saw_gap: bool = Observer._tick_gap_invalid(previous, catch_up_tick)
	previous = catch_up_tick
	var process_saw_gap: bool = Observer._tick_gap_invalid(previous, catch_up_tick)
	_check(step_saw_gap and not process_saw_gap, "catch-up step checks before overwriting the previous clock")
	_check_activation_metadata()
	_check_drawable_boundaries()
	_check_flight_local_scope_and_input()
	_check_screened_scope()
	_check_neutral_checkpoint()
	print("PACKAGE_FLIGHT_CLOCK_TEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check_activation_metadata() -> void:
	var fake := FakeScene.new()
	get_root().add_child(fake)
	var fake_session := FakeSession.new()
	fake.add_child(fake_session)
	var probe: Node = Observer.new()
	fake.add_child(probe)
	probe.set_process(false)
	probe.scene = fake
	probe.session = fake_session
	var viewport := probe.get_viewport()
	_check(not viewport.has_meta(&"openrc_frame_generation_status"), "disabled frame generation has no metadata")
	probe._record_activation(0)
	_check(probe.activation_samples[-1].frame_generation_status == null,
			"absent frame-generation metadata records null without engine diagnostics")
	var status := {requested = false, state = "disabled", reason = "test", observer_requested = false,
		frame_producer_requested = false, attempt_renderer_gated_composition = false}
	viewport.set_meta(&"openrc_frame_generation_status", status)
	probe._record_activation(240)
	_check(probe.activation_samples[-1].frame_generation_status == status,
			"published frame-generation status keeps the existing projection")
	viewport.remove_meta(&"openrc_frame_generation_status")
	probe._record_activation(480)
	_check(probe.activation_samples[-1].frame_generation_status == null,
			"retired frame-generation metadata returns to null")
	probe.sealed = true
	fake.free()


func _check_drawable_boundaries() -> void:
	var probe: Node = Observer.new()
	var before: Dictionary = {status = "observed", owner = "ordinary", evidence = "acquired_framebuffer_texture_not_scanout",
		scope = 3, attempts = 10, observed = 10, missed = 0, changes = 0, width = 1920, height = 1080,
		pixel_format = 80, query_before_usec = 150, query_after_usec = 160}
	var after: Dictionary = before.duplicate(true)
	after.attempts = 60
	after.observed = 60
	after.query_before_usec = 910
	after.query_after_usec = 920
	probe.drawable_requested = true
	probe.measured_start_usec = 200
	probe.measured_end_usec = 900
	probe.drawable_before = before
	probe.drawable_after = after
	_check(probe._drawable_status_valid(before), "typed ordinary acquisition status is valid")
	_check(probe._drawable_receipt().status == "observed", "matching boundaries observe the acquired texture")
	after.scope = 4
	probe.drawable_after = after
	_check(probe._drawable_receipt().status == "not_observed", "recreated surface is refused")
	after.scope = 3
	after.changes = 1
	probe.drawable_after = after
	_check(probe._drawable_receipt().status == "not_observed", "intervening extent change is refused")
	after.changes = 0
	after.query_before_usec = 899
	probe.drawable_after = after
	_check(probe._drawable_receipt().status == "not_observed", "post-snapshot must follow the sample")
	after.query_before_usec = 910
	after.pixel_format = 0
	_check(not probe._drawable_status_valid(after), "invalid texture format is refused")
	probe.drawable_requested = false
	_check(probe._drawable_receipt().status == "not_observed", "off observation cannot claim a drawable")
	probe.free()


func _check_flight_local_scope_and_input() -> void:
	var fake := FakeScene.new()
	get_root().add_child(fake)
	get_root().set_meta(&"openrc_reconstruction", {fallback = false, requested = "native", selected = "native", provider = "native"})
	var motion := InputEventMouseMotion.new()
	_check(not Observer._changes_live_input(motion), "passive pointer motion is allowed")
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	_check(Observer._changes_live_input(motion), "camera drag invalidates the synthetic run")
	_check(Observer._changes_live_input(InputEventJoypadMotion.new()), "controller input invalidates the synthetic run")
	for changed: String in ["shadow_mode", "auto_zoom"]:
		var probe: Node = Observer.new()
		fake.add_child(probe)
		probe.set_process(false)
		probe.scene = fake
		var original: Dictionary = probe._render_scope()
		_check(original.get("shadow_mode") == "sun" and original.get("auto_zoom") == true,
				"flight-local shadow and camera scope is captured")
		probe.initial_render_scope = original.duplicate(true)
		if changed == "shadow_mode": fake._shadow_mode = "off"
		else: fake._rig.auto_zoom = false
		probe._observe_render_scope(probe._render_scope())
		fake._shadow_mode = "sun"
		fake._rig.auto_zoom = true
		probe._observe_render_scope(probe._render_scope())
		_check(probe.violations.render_scope == 1 and not probe.failure.is_empty(),
				changed + " change stays failed after a later sampled restore")
		probe.sealed = true
		probe.free()
	for changed: String in ["shadow_mode", "auto_zoom"]:
		var probe: Node = Observer.new()
		fake.add_child(probe)
		probe.set_process(false)
		probe.scene = fake
		probe.initial_render_scope = probe._render_scope()
		probe.input_watch_active = true
		probe.set_process_input(true)
		fake.watch = probe
		fake.input_actions = 0
		fake.invalidated_before_action = 0
		var key := InputEventKey.new()
		key.physical_keycode = KEY_V if changed == "shadow_mode" else KEY_Z
		key.keycode = key.physical_keycode
		key.pressed = true
		get_root().push_input(key, true)
		get_root().push_input(key, true)
		probe._observe_render_scope(probe._render_scope())
		_check(probe.violations.input_ownership >= 1 and probe.violations.render_scope == 0
				and not probe.failure.is_empty(), changed + " input restored before sampling still fails")
		_check(fake.input_actions == 2 and fake.invalidated_before_action == 2
				and fake._shadow_mode == "sun" and fake._rig.auto_zoom,
				changed + " was delivered twice after the observer and restored")
		_check(probe._input_watch_valid(), "live input watch remains registered")
		probe.set_process_input(false)
		_check(not probe._input_watch_valid(), "disabled input watch is refused")
		probe.sealed = true
		probe.free()
	var disabled_probe: Node = Observer.new()
	fake.add_child(disabled_probe)
	disabled_probe.set_process(false)
	var fake_session := FakeSession.new()
	fake.add_child(fake_session)
	var fake_sim := Node.new()
	fake_session.add_child(fake_sim)
	fake_session.sim = fake_sim
	fake_session.set_physics_process(true)
	fake_sim.set_physics_process(true)
	var fake_pilot := FakePilot.new()
	fake_session.read_raw = fake_pilot.read_raw
	disabled_probe.session = fake_session
	disabled_probe.adapter = fake_pilot
	disabled_probe.input_watch_active = true
	disabled_probe.set_process_input(true)
	var old_tick_rate: int = Engine.physics_ticks_per_second
	var old_time_scale: float = Engine.time_scale
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 1.0
	_check(disabled_probe._ownership_valid(), "synthetic tick ownership accepts the active input watch")
	disabled_probe.set_process_input(false)
	fake.watch = disabled_probe
	fake.input_actions = 0
	var disabled_key := InputEventKey.new()
	disabled_key.physical_keycode = KEY_V
	disabled_key.keycode = KEY_V
	disabled_key.pressed = true
	get_root().push_input(disabled_key, true)
	get_root().push_input(disabled_key, true)
	_check(fake.input_actions == 2 and disabled_probe.violations.input_ownership == 0
			and not disabled_probe._ownership_valid(), "disabled watch misses dispatch and fails tick ownership")
	Engine.physics_ticks_per_second = old_tick_rate
	Engine.time_scale = old_time_scale
	disabled_probe.sealed = true
	disabled_probe.free()
	get_root().remove_meta(&"openrc_reconstruction")
	fake.free()


func _check_screened_scope() -> void:
	var selection := {ok = true, reason = "", profile = "production", aircraft = "jensen-das-ugly-stik-60",
		battery = "ideal", start = "airborne", weather = "calm", start_sha256 = "a".repeat(64)}
	var branches := {soft_hull = true, flap_mix_owner = "simulator", shaft_integrator = "coupled-rk4",
		wheel_count = 3, wheel_layout = "test", gear_retractable = false, wheel_brake = false,
		flaps = false, battery_dynamic = false, battery_pack = false, electric_law = "test",
		turbine_continuous = false, glow = false, liquid = false, weather_calm = true,
		weather_atmosphere = false, weather_spatial = false, weather_vertical = false}
	var scope: Dictionary = Observer._screened_scope(selection, branches)
	_check(not scope.is_empty(), "the fixed stock production selection is admitted for comparison")
	for key: String in ["shaft_integrator", "wheel_layout", "electric_law"]:
		var changed: Dictionary = branches.duplicate(true)
		changed[key] = "different"
		_check(var_to_bytes(Observer._screened_scope(selection, changed)) != var_to_bytes(scope),
				"changed " + key + " changes the screened witness")
	var changed: Dictionary = branches.duplicate(true)
	changed.soft_hull = false
	_check(Observer._screened_scope(selection, changed).is_empty(), "non-target contact mode is refused")
	changed = branches.duplicate(true)
	changed.flap_mix_owner = "transmitter"
	_check(Observer._screened_scope(selection, changed).is_empty(), "different flap mix owner is refused")
	changed = branches.duplicate(true)
	changed.weather_calm = false
	_check(var_to_bytes(Observer._screened_scope(selection, changed)) != var_to_bytes(scope),
			"a changed effective weather branch changes the witness")
	changed = selection.duplicate(true)
	changed.start_sha256 = "b".repeat(64)
	_check(var_to_bytes(Observer._screened_scope(changed, branches)) != var_to_bytes(scope),
			"a changed actual start changes the witness")
	changed = selection.duplicate(true)
	changed.weather = "gusty"
	_check(Observer._screened_scope(changed, branches).is_empty(), "an out-of-scope weather selection is refused")
	changed = branches.duplicate(true)
	changed.wheel_count = "three"
	_check(Observer._screened_scope(selection, changed).is_empty(), "malformed branch facts are refused")


func _check_neutral_checkpoint() -> void:
	var common := "a".repeat(64)
	var native_config := "b".repeat(64)
	var reference := {format = "openrc-flight-checkpoint v7", configuration = common,
		simulation = {tick = 0, state = PackedFloat64Array([1.0, 2.0])}, world = "field"}
	var native: Dictionary = reference.duplicate(true)
	native.configuration = native_config
	native.stage_physics_format = native.format
	native.format = Flight.NATIVE_CHECKPOINT_FORMAT
	var native_identity := {backend = "native", binary_sha256 = "c".repeat(64)}
	native.stage_backend = native_identity.duplicate(true)
	var original_ref := var_to_bytes(reference)
	var original_native := var_to_bytes(native)
	var ref_witness: Dictionary = Observer._neutral_checkpoint(reference, {backend = "gdscript_reference"}, common, common)
	var native_witness: Dictionary = Observer._neutral_checkpoint(native, native_identity, native_config, common)
	_check(not ref_witness.is_empty() and var_to_bytes(ref_witness) == var_to_bytes(native_witness),
			"equivalent native wrapper and reference produce the same detached witness")
	_check(var_to_bytes(reference) == original_ref and var_to_bytes(native) == original_native,
			"the actual saved checkpoints remain byte-for-byte unchanged")
	var changed: Dictionary = native.duplicate(true)
	changed.simulation.state = PackedFloat64Array([1.0, 3.0])
	_check(var_to_bytes(Observer._neutral_checkpoint(changed, native_identity, native_config, common)) != var_to_bytes(ref_witness),
			"a changed physical state changes the witness")
	changed = native.duplicate(true)
	changed.world = "different field"
	_check(var_to_bytes(Observer._neutral_checkpoint(changed, native_identity, native_config, common)) != var_to_bytes(ref_witness),
			"a changed world remains in the witness")
	changed = native.duplicate(true)
	changed.stage_backend.binary_sha256 = "d".repeat(64)
	_check(Observer._neutral_checkpoint(changed, native_identity, native_config, common).is_empty(),
			"a mismatched recorded native identity is refused")
	changed = native.duplicate(true)
	changed.erase("stage_physics_format")
	_check(Observer._neutral_checkpoint(changed, native_identity, native_config, common).is_empty(),
			"a missing native wrapper field is refused")
	changed = native.duplicate(true)
	changed.stage_physics_format = Flight.NATIVE_CHECKPOINT_FORMAT
	_check(Observer._neutral_checkpoint(changed, native_identity, native_config, common).is_empty(),
			"a recursive native wrapper is refused")
	changed = reference.duplicate(true)
	changed.stage_backend = native_identity
	_check(Observer._neutral_checkpoint(changed, {backend = "gdscript_reference"}, common, common).is_empty(),
			"native wrapper data on a reference checkpoint is refused")
	_check(var_to_bytes(Observer._neutral_checkpoint(reference, {backend = "gdscript_reference"}, common, "d".repeat(64))) != var_to_bytes(ref_witness)
			and Observer._neutral_checkpoint(native, native_identity, common, common).is_empty()
			and Observer._neutral_checkpoint(native, native_identity, native_config, "A".repeat(64)).is_empty(),
			"configuration mismatch and malformed digests are refused")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("PACKAGE_FLIGHT_CLOCK_TEST failure: ", label)
