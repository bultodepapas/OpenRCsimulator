## NK-3 research adapter: installs the native joint stage on a live FlightSession without editing app/.
## It replaces exactly one evaluator boundary (`sim.model.stage`, SF-08) and wraps `sim.model.pre_tick` only to hand
## the native side the tick context the reference stage reads (the aux the kernel installs, the inputs, the session's
## own `_deflections(aux)` and `sim.time()`). The tick transaction, pre-step, collision and observers stay GDScript.
## D6: any capability or data the native stage does not port is refused and the reference stage stays installed.
extends RefCounted

const NativeStage := preload("res://sim/native_stage.gd")


static func deflection_array(d: Dictionary) -> PackedFloat64Array:
	return PackedFloat64Array([d.elevator, d.aileron_right, d.aileron_left, d.rudder])


## prepare_stage() input: one home, app/sim/native_stage.gd (the research harnesses use the app's D6 flags).
static func config_for(session: Node) -> Dictionary:
	return NativeStage.config_for(session)


## Prepare and swap. Returns {ok, error, restore: Callable}; on refusal nothing on the session changes.
static func install(session: Node, native: Object) -> Dictionary:
	var sim: Node = session.sim
	var prepared: Dictionary = native.prepare_stage(config_for(session))
	if not prepared.ok:
		return {ok = false, error = prepared.error}
	var original_stage: Callable = sim.model.stage
	var original_pre_tick: Callable = sim.model.pre_tick
	var wrapped := func(aux: PackedFloat64Array, inputs: PackedFloat64Array, dt: float) -> Variant:
		var next: Variant = original_pre_tick.call(aux, inputs, dt)
		if next is PackedFloat64Array and next.size() == aux.size():
			native.set_tick_context(next, inputs, deflection_array(session._deflections(next)), sim.time())
		return next
	sim.model.pre_tick = wrapped
	sim.model.stage = Callable(native, "stage")
	var restore := func() -> void:
		sim.model.stage = original_stage
		sim.model.pre_tick = original_pre_tick
	return {ok = true, error = "", restore = restore}


## True while the session still runs the native boundary (a reset or restore may reinstall callbacks).
static func installed(session: Node, native: Object) -> bool:
	return session.sim.model.stage.get_object() == native and session.sim.model.stage.get_method() == &"stage"
