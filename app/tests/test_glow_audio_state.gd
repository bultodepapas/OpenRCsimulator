extends SceneTree
## F5b: flight audio's glow keys from the accepted state and the native glow stage (GlowAudioState) equal
## GlowFlight.telemetry's on every key the glow voice reads (GlowAudioPump.TELEMETRY_KEYS), bit for bit, through throttle
## steps from the runway and in the air on four glow aircraft. Paused, with a hold, or with the engine stopped the
## builder declines and the caller evaluates telemetry. The shaft-load torques from the native glow stage's blade model
## and from the prepared blade evaluator equal Propulsion's. Skips (passes) without a verified native library.

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const GlowAudioState := preload("res://audio/glow_audio_state.gd")
const GlowAudioPump := preload("res://audio/glow_audio_pump.gd")
const Propulsion := preload("res://physics/propulsion.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	_run.call_deferred()


func _run() -> void:
	var field: Dictionary = FieldLoader.load_from().field
	var lake: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH).lake
	var tested := 0
	for id: String in ["gp-extra-300s-60", "stik-glow-61fx-2t", "stik-glow-55ax-2t", "stik-glow-fs64v-4t"]:
		for start: String in [Flight.START_RUNWAY, Flight.START_AIRBORNE]:
			var s := _session(id, start, field, lake)
			if s == null or s.stage_backend_identity().backend != NativeStage.BACKEND_NATIVE:
				print("GLOW_AUDIO_SKIP %s" % id)
				if s != null:
					s.free()
				continue
			tested += 1
			_compare(id, start, s)
			s.free()
	if tested == 0:
		print("GLOW_AUDIO_SKIP no native glow session")
	print("glow audio state: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _session(id: String, start: String, field: Dictionary, lake: Dictionary) -> Node:
	var s: Node = Flight.new()
	s.input_enabled = true
	s.crash_auto_restart = false
	s.soft_hull_contacts = true
	s.start_choice = start
	s.setup_stage_backend(NativeStage.BACKEND_NATIVE)
	s.setup(Catalog.data_for(id, Catalog.default_battery_mode(id)), id)
	if not s.aircraft.get("ok", false) or not s.glow_is_active():
		s.free()
		return null
	s.set_field(field)
	s.set_lake_context(lake)
	s.reset()
	if not bool(s.glow_state().get("running", false)):
		s.glow_start()
	s.read_raw = func() -> Dictionary:
		var t: int = s.sim.tick
		return {roll = 0.02 if t % 600 < 300 else -0.02, pitch = 0.06 if t > 360 else 0.0, yaw = 0.0,
			throttle = [1.0, 0.25, 0.0, 0.7, 1.0][(t / 240) % 5]}
	return s


func _tick(s: Node) -> void:
	var dt: float = s.sim.dt()
	s._physics_process(dt)
	s.sim._physics_process(dt)


func _compare(id: String, start: String, s: Node) -> void:
	var compared := 0
	var declined := 0
	var mismatches := 0
	var torque_mismatches := 0
	var native_torques := 0
	var detail := ""
	for tick in 2400:
		_tick(s)
		if tick % 3 != 2 or not s.crash.is_empty():
			continue
		var built: Dictionary = GlowAudioState.build(s)
		if built.is_empty():
			declined += 1
			continue
		var reference: Dictionary = s.glow_state()
		compared += 1
		var prop: Dictionary = s.aircraft.model.propulsion
		var air: Dictionary = s.air_data(s.sim.state)
		var rpm: float = s.sim.aux[0]
		var rho: float = s.air_density()
		var expected := PackedFloat64Array([Propulsion.thrust_torque(air.v_air, rpm, prop, rho)[1],
			Propulsion.prop_torque(rpm, 0.0, prop, rho)])
		if var_to_bytes(GlowAudioState.shaft_torques(s, prop, air.v_air, rpm)) != var_to_bytes(expected):
			torque_mismatches += 1
		native_torques += int(s.presented_glow_blade_torques(rpm, 0.0, rho).size() == 2)
		s.native_glow_audio_enabled = false # the prepared GDScript evaluator
		if var_to_bytes(GlowAudioState.shaft_torques(s, prop, air.v_air, rpm)) != var_to_bytes(expected):
			torque_mismatches += 1
		s.native_glow_audio_enabled = true
		for key: String in GlowAudioPump.TELEMETRY_KEYS:
			if built.has(key) != reference.has(key) or (built.has(key) \
					and var_to_bytes(built[key]) != var_to_bytes(reference[key])):
				mismatches += 1
				if detail.is_empty():
					detail = "%s: %s vs %s" % [key, str(built.get(key)), str(reference.get(key))]
	_check("%s %s: audio glow keys equal telemetry's (%d endpoints, %d declined)" % [id, start, compared, declined],
		mismatches == 0 and compared > 500, detail)
	_check("%s %s: shaft-load torques from the prepared evaluator equal Propulsion's" % [id, start],
		torque_mismatches == 0 and s.aircraft.is_read_only() and native_torques == compared,
		"%d mismatched, %d native of %d" % [torque_mismatches, native_torques, compared])
	# Presentation outside the accepted context falls back to telemetry.
	s.sim.set_paused(true)
	_check("%s %s: paused, the builder declines" % [id, start], GlowAudioState.build(s).is_empty())
	s.sim.set_paused(false)
	s.holds["test"] = true
	_check("%s %s: with a hold, the builder declines" % [id, start], GlowAudioState.build(s).is_empty())
	s.holds.erase("test")
	s.engine_running = false
	_check("%s %s: with the engine stopped, the builder declines" % [id, start], GlowAudioState.build(s).is_empty())
	s.engine_running = true
	s.native_glow_audio_enabled = false
	_check("%s %s: the hook declines" % [id, start], GlowAudioState.build(s).is_empty())
	s.native_glow_audio_enabled = true


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
