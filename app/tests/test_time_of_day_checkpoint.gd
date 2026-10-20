## TOD-08a: real Main restores paired light/physics atomically; no input or replay UI.
extends SceneTree

const Main = preload("res://main.gd")
const WeatherConfig = preload("res://physics/wind_config.gd")
const Config = preload("res://environment/time_of_day_config.gd")
const Timeline = preload("res://environment/visual_timeline.gd")
const Envelope = preload("res://app_state/visual_checkpoint.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
const Lighting = preload("res://render/time_of_day_lighting.gd")

class TestFlight extends Main:
	var refuse_preparation: bool = false
	func _prepare_checkpoint_lighting(config: Dictionary) -> Dictionary:
		if refuse_preparation:
			return {ok = false}
		return super._prepare_checkpoint_lighting(config)

class MemoryRecorder extends "res://sim/recorder.gd":
	var stops: int = 0
	func stop(_path: String = "") -> Error:
		recording = false
		stops += 1
		return OK

var checks: int = 0
var failures: int = 0

func check(label: String, valid: bool) -> void:
	checks += 1
	if not valid:
		failures += 1
		printerr("FAIL " + label)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var flight: TestFlight = TestFlight.new()
	flight.interactive_start = true
	root.add_child(flight)
	flight.set_process(false)
	flight.session.physics_enabled = false
	flight.session.input_enabled = false
	flight.recorder.detach()
	flight.recorder = MemoryRecorder.new(flight.session.sim)
	var sim: Node = flight.session.sim
	for _tick: int in 24:
		sim.step()
	sim.set_paused(true)
	var original: Dictionary = flight.checkpoint()
	check("production Main emits a paired checkpoint", original.get("format") == "openrc-visual-checkpoint v1")
	var night: Dictionary = Config.defaults()
	night.mode = "astronomical"
	night.local_seconds = 0
	var timeline: Dictionary = Timeline.create(Config.defaults()).timeline
	timeline = Timeline.append_config_edit(timeline, 12, night).timeline
	var edited: Dictionary = Envelope.make(original.physics, timeline, flight._field_identity()).checkpoint
	flight.recorder.start(flight._trace_meta())
	flight.session.input_enabled = true
	ShaderClock.update(123.25, Vector3(1.0, 2.0, 3.0))
	Atmosphere.update_clouds(flight._env, 123.25)
	var before: Dictionary = _observed(flight)
	# A valid future-format payload must not silently become a fixed-time flight.
	# Even rate zero can carry fractional phase and a distinct restart selection.
	for rate: int in [0, 1]:
		var progressing: Dictionary = Timeline.create_progressing(night, 0, rate)
		var future_pair: Dictionary = Envelope.make(original.physics, progressing.timeline, flight._field_identity())
		check("v2 fixture is valid at rate %d" % rate, future_pair.ok
			and Envelope.read(future_pair.checkpoint, flight._field_identity()).ok)
		var refused: Dictionary = flight.restore_checkpoint(future_pair.checkpoint)
		check("unsupported v2 restore is atomic at rate %d" % rate, not refused.ok
			and str(refused.errors).contains("solar progression controller") and _observed(flight) == before)
	for defect: String in ["missing_visual", "future_format", "wrong_hash", "wrong_field", "invalid_config", "invalid_physics"]:
		var bad: Dictionary = edited.duplicate(true)
		match defect:
			"missing_visual": bad.erase("timeline")
			"future_format": bad.format = "openrc-visual-checkpoint v99"
			"wrong_hash": bad.payload_sha256 = "bad"
			"wrong_field": bad.field_identity = "other field"
			"invalid_config": bad.timeline.initial.config.date = "bad"
			"invalid_physics":
				bad.physics.simulation.mass *= 2.0
				bad.payload_sha256 = _binding(bad)
		var rejected: Dictionary = flight.restore_checkpoint(bad)
		check("atomic rejection: " + defect, not rejected.ok and _observed(flight) == before)
	flight.refuse_preparation = true
	check("resource preparation failure preserves recording and live world", not flight.restore_checkpoint(edited).ok and _observed(flight) == before)
	flight.refuse_preparation = false
	var restored: Dictionary = flight.restore_checkpoint(bytes_to_var(var_to_bytes(edited)))
	check("valid paired restoration succeeds", restored.ok)
	check("physics bits unchanged by paired restoration", var_to_bytes(flight.session.checkpoint()) == var_to_bytes(original.physics))
	check("restoration is paused recorded-input replay", sim.paused and not flight.session.input_enabled)
	check("valid restore closes prior recording exactly once", not flight.recorder.recording and flight.recorder.stops == 1)
	check("historical event selects night at checkpoint tick", flight.lighting_config == night and flight._lighting.sun_energy == 0.0)
	check("actual light/environment and aircraft shadow are night", flight._sun.light_energy == 0.0 and flight._world_environment.environment == flight._env and not flight._shadow.visible)
	var material: ShaderMaterial = flight.get_node("Field/rough").material_override
	check("field material receives selected solar values", material.get_shader_parameter("sun_lin") == Atmosphere.sun_linear(flight._lighting))
	check("cloud and shader clocks restored immediately", ShaderClock.last_clock == ShaderClock.value(sim.time()) and Atmosphere.last_cloud_offset == Atmosphere.cloud_offset(sim.time()))
	check("history survives checkpoint emission", flight.checkpoint().timeline == timeline)
	var recorded_history: Variant = JSON.parse_string(flight._trace_meta().get("visual_timeline", ""))
	check("restored trace embeds the ordered history", Timeline.validate(recorded_history).ok and Timeline.evaluate(recorded_history, sim.tick).config == night)
	check("replacement keeps scene child count stable", flight.get_child_count() == before.children)
	flight.lighting_config.local_seconds = 123
	check("checkpoint refuses unrecorded config edits", flight.checkpoint().is_empty())
	flight.lighting_config.local_seconds = 0
	edited.timeline.events[0].config.local_seconds = 43200
	check("restore owns detached visual data", flight.lighting_config.local_seconds == 0 and flight.checkpoint().timeline == timeline)
	for _tick: int in 6:
		sim.step()
	var continued: Dictionary = flight.session.checkpoint()
	check("physical owner can restore same original independently", flight.session.restore_checkpoint(original.physics))
	for _tick: int in 6:
		sim.step()
	check("paired and physics-only continuation agree exactly", var_to_bytes(continued) == var_to_bytes(flight.session.checkpoint()))
	var missing: Dictionary = flight.restore_checkpoint(original.physics)
	check("old physics-only checkpoint explicitly reports missing visuals", missing.ok and missing.context_status == "legacy_missing_visual")
	check("old checkpoint uses explicit legacy light", flight.lighting_config == Config.defaults() and flight._lighting == Lighting.snapshot(Config.defaults()))
	check("legacy fallback is marked in trace metadata", flight._trace_meta().get("visual_context_status") == "legacy_missing_visual" and flight._trace_meta().has("visual_context"))
	check("new paired context is isolated from returned dictionaries", original.physics.simulation.tick == 24)
	flight.restore_checkpoint(Envelope.make(original.physics, timeline, flight._field_identity()).checkpoint)
	flight.session.reset()
	check("restart retains selected start light and starts new history", sim.tick == 0 and flight.lighting_config == night and flight.checkpoint().timeline.events.is_empty())
	for condition: String in ["steady", "turbulent", "hot-high"]:
		flight.session.reset()
		check("configure replay variant " + condition, flight.session.setup_weather(WeatherConfig.preset(condition)))
		flight.session.reset()
		for _tick: int in 12:
			sim.step()
		var weather_saved: Dictionary = flight.checkpoint()
		var expected_format: String = "openrc-flight-checkpoint v3" if condition == "hot-high" else "openrc-flight-checkpoint v2"
		check("real physical format " + condition, weather_saved.physics.format == "openrc-flight-checkpoint v7"
			and weather_saved.physics.physics_format == expected_format)
		check("paired weather restore " + condition, flight.restore_checkpoint(weather_saved).ok
			and var_to_bytes(flight.session.checkpoint()) == var_to_bytes(weather_saved.physics))
		check("bare weather fallback " + condition, flight.restore_checkpoint(weather_saved.physics).get("context_status") == "legacy_missing_visual"
			and var_to_bytes(flight.session.checkpoint()) == var_to_bytes(weather_saved.physics))
	flight.recorder.detach()
	if flight._engine_audio != null:
		flight._engine_audio.stop()
		flight._engine_audio.stream = null
	flight.free()
	await process_frame
	var shaft_flight: TestFlight = TestFlight.new()
	shaft_flight.interactive_start = true
	shaft_flight.aircraft_id = "p51d-mustang-120"
	root.add_child(shaft_flight)
	shaft_flight.set_process(false)
	shaft_flight.session.physics_enabled = false
	check("configure actual coupled shaft model", shaft_flight.session.setup_shaft_integrator("coupled-rk4"))
	shaft_flight.session.reset()
	for _tick: int in 12:
		shaft_flight.session.sim.step()
	var shaft_saved: Dictionary = shaft_flight.checkpoint()
	check("finite-fuel coupled shaft emits a visual checkpoint", not shaft_saved.is_empty())
	if shaft_saved.is_empty():
		shaft_flight.free()
		quit(1)
		return
	check("real finite-fuel v11 physical checkpoint", shaft_saved.physics.format == "openrc-flight-checkpoint v7"
		and shaft_saved.physics.physics_format == "openrc-flight-checkpoint v11"
		and shaft_saved.physics.liquid_physics_format == "openrc-flight-checkpoint v4")
	check("coupled shaft paired restoration exact", shaft_flight.restore_checkpoint(shaft_saved).ok
		and var_to_bytes(shaft_flight.session.checkpoint()) == var_to_bytes(shaft_saved.physics))
	check("coupled shaft bare fallback exact", shaft_flight.restore_checkpoint(shaft_saved.physics).get("context_status") == "legacy_missing_visual"
		and var_to_bytes(shaft_flight.session.checkpoint()) == var_to_bytes(shaft_saved.physics))
	shaft_flight.recorder.detach()
	if shaft_flight._engine_audio != null:
		shaft_flight._engine_audio.stop()
		shaft_flight._engine_audio.stream = null
	shaft_flight.free()
	await process_frame
	print("TOD-08a Main: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func _binding(candidate: Dictionary) -> String:
	var hashing: HashingContext = HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(var_to_bytes([candidate.physics, candidate.timeline, candidate.field_identity]))
	return hashing.finish().hex_encode()

func _observed(flight: TestFlight) -> Dictionary:
	return {
		physics = var_to_bytes(flight.session.checkpoint()),
		paused = flight.session.sim.paused, input_enabled = flight.session.input_enabled,
		pause_reason = flight.session.pause_reason, holds = flight.session.holds.duplicate(true),
		config = flight.lighting_config.duplicate(true), timeline = flight._visual_timeline.duplicate(true),
		field_id = flight.get_node("Field").get_instance_id(), sun_id = flight._sun.get_instance_id(),
		environment_id = flight._env.get_instance_id(), light = var_to_bytes(flight._lighting),
		clock = ShaderClock.last_clock, wind = ShaderClock.last_wind, clouds = Atmosphere.last_cloud_offset,
		children = flight.get_child_count(),
		recording = flight.recorder.recording, stops = flight.recorder.stops,
	}
