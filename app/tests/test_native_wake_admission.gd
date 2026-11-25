extends SceneTree
## NK-5a: the session pre-step evaluates its tail-downwash wing wake through the prepared native stage only inside the
## configuration-guarded _kernel_pre_step. On every flown tick the guarded native pre-step must return the same bytes as
## the reference _pre_step, the admission flag must be clear outside that call, and a reference session ignores it.
## Skips (passes) when no verified native library is installed for this platform.

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const Aero := preload("res://physics/aero.gd")

const TICKS := 360
var _checks := 0
var _failures := 0
var field: Dictionary
var lake: Dictionary


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	_run.call_deferred()


func _run() -> void:
	var loaded_field: Dictionary = FieldLoader.load_from()
	var loaded_lake: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	_check("field and lake load", loaded_field.ok and loaded_lake.ok)
	field = loaded_field.field
	lake = loaded_lake.lake
	for id: String in ["f4u-corsair-250", "jensen-das-ugly-stik-60"]:
		_case(id)
	var reference := _session(NativeStage.BACKEND_REFERENCE, "f4u-corsair-250")
	var aux: PackedFloat64Array = reference.sim.aux.duplicate()
	var guarded: PackedFloat64Array = reference._kernel_pre_step(aux, reference.sim.inputs, reference.sim.dt())
	var direct: PackedFloat64Array = reference._pre_step(aux, reference.sim.inputs, reference.sim.dt())
	_check("a reference session has no native stage and keeps its pre-step", reference._native_stage == null
		and not reference._native_wake_admitted and guarded == direct)
	reference.free()
	print("native wake admission: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _case(id: String) -> void:
	var session := _session(NativeStage.BACKEND_NATIVE, id)
	if session.stage_backend_identity().backend != NativeStage.BACKEND_NATIVE:
		print("NK5A_NATIVE_WAKE_SKIP %s: native unavailable or stale: %s" % [id, str(session.stage_backend_status())])
		session.free()
		return
	_check(id + " flies a tail downwash lag", session.downwash_index() >= 0)
	var identical := true
	var flag_clear := true
	var native_used := 0
	var mismatch := ""
	for tick: int in TICKS:
		var aux: PackedFloat64Array = session.sim.aux.duplicate()
		var inputs: PackedFloat64Array = session.sim.inputs.duplicate()
		var modes: PackedInt64Array = session.sim.modes.duplicate()
		var dt: float = session.sim.dt()
		var native_next: PackedFloat64Array = session._kernel_pre_step(aux, inputs, dt)
		flag_clear = flag_clear and not session._native_wake_admitted
		session.sim.modes = modes.duplicate() # a turbulence draw advances the RNG: replay it for the reference
		var reference_next: PackedFloat64Array = session._pre_step(aux, inputs, dt)
		session.sim.modes = modes
		if var_to_bytes(native_next) != var_to_bytes(reference_next):
			identical = false
			if mismatch.is_empty():
				mismatch = "tick %d: %s vs %s" % [session.sim.tick, native_next, reference_next]
		var s: PackedFloat64Array = session.sim.state
		var air: Dictionary = session.air_data(s)
		var deflections: Dictionary = session._deflections(aux)
		var up: float = session._ground_up(s)
		var native_wake: float = session._native_stage.wing_wake(s, air, deflections, up)
		if not is_nan(native_wake):
			native_used += 1
			identical = identical and var_to_bytes(native_wake) == var_to_bytes(Aero.wing_wake_velocity(s, air, deflections,
				session.aircraft.model, up))
		var before: int = session.sim.tick
		session._physics_process(dt)
		session.sim._physics_process(dt)
		if session.sim.tick != before + 1:
			break
	_check(id + " flew the requested ticks on the native backend", session.sim.tick >= TICKS - 1
		and session.stage_backend_identity().backend == NativeStage.BACKEND_NATIVE, str(session.sim.fault_reason))
	_check(id + " guarded native pre-step equals the reference pre-step bit for bit", identical, mismatch)
	_check(id + " the admission flag is clear outside the guarded call", flag_clear and not session._native_wake_admitted)
	_check(id + " the native wing wake was evaluated, not only the NaN fallback", native_used >= TICKS - 1, str(native_used))
	session.free()


func _session(backend: String, id: String) -> Node:
	var session: Node = Flight.new()
	session.input_enabled = true
	session.crash_auto_restart = false
	session.soft_hull_contacts = true
	_check("select " + backend, session.setup_stage_backend(backend))
	session.setup(str(Catalog.entry(id).data), id)
	_check(id + " is flyable", session.is_flyable(), str(session.pause_reason))
	_check(id + " field and lake install", session.set_field(field) and session.set_lake_context(lake))
	session.reset()
	session.read_raw = func() -> Dictionary:
		var tick: int = session.sim.tick
		return {roll = 0.15 if tick >= 120 and tick < 160 else 0.0, pitch = 0.05, yaw = 0.0,
			throttle = 0.6}
	return session


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])
