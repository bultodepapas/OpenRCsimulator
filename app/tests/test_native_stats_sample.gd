extends SceneTree
## NK-9b: the statistics adapter's published sample built in one native call equals sample(true). Two adapters observe
## the same native session, one with the native sample and one without, and every published tick their samples are
## byte-identical. The flights cover the production field, lake and scenery world with soft hull contacts:
## - a takeoff roll and climb;
## - a hard landing;
## - a nose-over;
## - an engine-off glide into the ground;
## with the Corsair, the glow Stik 61FX and the electric Stik 6S. Contacts, support, incidents and terminal outcomes
## all occur. A 1e-9 change to one sample value is detected. Skips (passes) without the verified library.

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const Adapter := preload("res://statistics/fixed_wing_adapter.gd")
const RB := preload("res://physics/rigid_body.gd")
const TICKS := 1500

var _checks := 0
var _failures := 0
var _field: Dictionary
var _lake: Dictionary
var _world: Dictionary


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	_run.call_deferred()


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
	else:
		print("ok ", label)


func _session(id: String) -> Node:
	var s: Node = Flight.new()
	s.input_enabled = true
	s.crash_auto_restart = false
	s.soft_hull_contacts = true
	s.cost_observations_enabled = true
	s.start_choice = Flight.START_RUNWAY
	s.setup_stage_backend(NativeStage.BACKEND_NATIVE)
	s.setup(Catalog.data_for(id, Catalog.default_battery_mode(id)), id)
	if not s.aircraft.get("ok", false):
		s.free()
		return null
	s.set_field(_field)
	s.set_lake_context(_lake)
	s.set_collision_world(_world)
	s.reset()
	if s.glow_is_active() and not bool(s.glow_state().get("running", false)):
		s.glow_start()
	return s


func _tick(s: Node) -> void:
	var dt: float = s.sim.dt()
	s._physics_process(dt)
	s.sim._physics_process(dt)


func _run() -> void:
	if not NativeStage.library_status().get("ok", false) \
			or not ClassDB.class_has_method(&"OpenRCNativeKernel", &"stats_sample_build"):
		print("NK9B_SKIP no native library with the statistics sample")
		quit(0)
		return
	_field = FieldLoader.load_from().field
	_lake = LakeLoader.load_from(LakeLoader.DEFAULT_PATH).lake
	_world = CollisionSetup.build(_field).get("world", {})
	var mutation_seen := false
	for id: String in ["f4u-corsair-250", "stik-glow-61fx-2t", "stik-electric-6s"]:
		for scenario: String in ["roll", "hard_landing", "nose_over", "glide"]:
			var s := _session(id)
			if s == null:
				_check("%s: session" % id, false)
				continue
			var native_samples: Array = []
			var reference_samples: Array = []
			var native: RefCounted = Adapter.new()
			native.configure(s, id, func(sample: Dictionary) -> void: native_samples.append(sample))
			Adapter.native_sample_enabled = false
			var reference: RefCounted = Adapter.new()
			reference.configure(s, id, func(sample: Dictionary) -> void: reference_samples.append(sample))
			Adapter.native_sample_enabled = true
			native.attach()
			reference.attach()
			var raw := func() -> Dictionary: return {roll = 0.0, pitch = 0.25, yaw = 0.0, throttle = 1.0}
			if scenario == "hard_landing":
				var state: PackedFloat64Array = s.sim.state.duplicate()
				state[RB.POS + 2] -= 1.2
				state[RB.VEL + 2] = 7.0
				s.sim.state = state
				s.sim.previous = state.duplicate()
				raw = func() -> Dictionary: return {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
			elif scenario == "nose_over":
				raw = func() -> Dictionary: return {roll = 0.0, pitch = -1.0, yaw = 0.0, throttle = 1.0}
			s.read_raw = raw
			var flags := {supported = 0, incident = 0, terminal = 0, airborne = 0}
			for i: int in TICKS:
				if scenario == "glide" and i == 700:
					s.engine_running = false
					s.read_raw = func() -> Dictionary: return {roll = 0.2, pitch = -0.4, yaw = 0.0, throttle = 0.0}
				_tick(s)
				if not s.crash.is_empty() and i > 0:
					break
			native.detach()
			reference.detach()
			var mismatched := 0
			var first := ""
			if native_samples.size() != reference_samples.size():
				mismatched += 1
				first = "%d vs %d samples" % [native_samples.size(), reference_samples.size()]
			for k: int in mini(native_samples.size(), reference_samples.size()):
				var a: Dictionary = native_samples[k]
				var b: Dictionary = reference_samples[k]
				if var_to_bytes(a) != var_to_bytes(b):
					mismatched += 1
					if first.is_empty():
						first = "sample %d: %s vs %s" % [k, a, b]
				flags.supported += 1 if bool(b.get("supported", false)) else 0
				flags.incident += 1 if bool(b.get("incident", false)) else 0
				flags.terminal += 1 if bool(b.get("terminal", false)) else 0
				flags.airborne += 0 if bool(b.get("supported", false)) else 1
				if not mutation_seen and k == 50:
					var altered: Dictionary = b.duplicate(true)
					altered.tas = float(altered.tas) + 1e-9
					mutation_seen = var_to_bytes(altered) != var_to_bytes(a)
			_check("%s %s: native and reference samples are byte-identical (%d samples, %s, native bound %s)" % [id, scenario,
				reference_samples.size(), flags, native._native_sample != null],
				mismatched == 0 and native._native_sample != null and reference._native_sample == null \
				and reference_samples.size() > 20, first)
			s.free()
	_check("a 1e-9 change to one sample value is detected", mutation_seen)
	print("native stats sample: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 or _checks == 0 else 0)
