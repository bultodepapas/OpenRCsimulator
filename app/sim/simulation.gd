# Fixed-step owner of the rigid-body state. 64-bit floats only (guarded by test.sh).
# Steps in _physics_process at the project's fixed tick (240 Hz), independent of rendering.
# Rendering reads interpolated() with Engine.get_physics_interpolation_fraction().
extends Node

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const RK := preload("res://physics/integrator.gd")

signal paused_changed(paused: bool)
## Emitted after every physics step (and once on reset, with tick 0), for recorders and telemetry.
signal stepped(tick: int, t: float, state: PackedFloat64Array, loads: PackedFloat64Array, inputs: PackedFloat64Array, aux: PackedFloat64Array)

var mass := 1.0
var inertia := PackedFloat64Array([1.0, 1.0, 1.0, 0.0, 0.0, 0.0])
var gravity := 9.80665
## loads(state, t) -> PackedFloat64Array [Fx, Fy, Fz, Mx, My, Mz], body axes, gravity excluded.
var loads: Callable = func(_s: PackedFloat64Array, _t: float) -> PackedFloat64Array:
	return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])

## Pilot commands, set by the game each frame: [roll, pitch, yaw, throttle] (−1…1, throttle 0…1).
var inputs := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
## Loads at the start of the latest step (the RK4 k1 evaluation), for traces.
var last_loads := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
## Auxiliary states advanced once per tick, before integration (e.g. [engine_rpm]). Held constant during RK4.
var aux := PackedFloat64Array([0.0])
## pre_step(aux, inputs, dt) -> PackedFloat64Array: new aux values. Runs at the fixed tick, so it stays deterministic.
var pre_step: Callable = func(a: PackedFloat64Array, _inputs: PackedFloat64Array, _dt: float) -> PackedFloat64Array:
	return a

var state := PackedFloat64Array()
var previous := PackedFloat64Array()
var tick := 0
var paused := false
## Stop stepping at this tick (-1 = never). Makes runs end at an exact tick, e.g. for replays.
var stop_at_tick := -1
## Wall-clock cost of a step (µs, smoothed), for the performance overlay. Measured, never fed back into the state.
var step_usec := 0.0
var _inertia_inv := PackedFloat64Array()


func reset(initial: PackedFloat64Array) -> void:
	state = initial.duplicate()
	previous = initial.duplicate()
	tick = 0
	_inertia_inv = RB.inertia_inverse(inertia)
	last_loads = loads.call(state, 0.0)
	stepped.emit(tick, time(), state, last_loads, inputs, aux)


func dt() -> float:
	return 1.0 / Engine.physics_ticks_per_second


func time() -> float:
	return tick * dt()


func set_paused(value: bool) -> void:
	if value != paused:
		paused = value
		paused_changed.emit(paused)


func _notification(what: int) -> void:
	# Losing focus pauses; resuming is an explicit action (set_paused(false)), never automatic.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		set_paused(true)


func step() -> void:
	var started := Time.get_ticks_usec()
	var t := time()
	aux = pre_step.call(aux, inputs, dt())
	last_loads = loads.call(state, t)
	var f := func(s: PackedFloat64Array) -> PackedFloat64Array:
		var l: PackedFloat64Array = loads.call(s, t)
		return RB.derivative(s, mass, inertia, _inertia_inv, M.v3(l[0], l[1], l[2]), M.v3(l[3], l[4], l[5]), gravity)
	previous = state
	state = RK.rk4_step(state, dt(), f)
	tick += 1
	step_usec = lerpf(step_usec, float(Time.get_ticks_usec() - started), 0.05) if step_usec > 0.0 else float(Time.get_ticks_usec() - started)
	stepped.emit(tick, time(), state, last_loads, inputs, aux)


func _physics_process(_delta: float) -> void:
	if paused or state.size() != RB.SIZE or (stop_at_tick >= 0 and tick >= stop_at_tick):
		return
	step()


## State between the previous and current step: position lerp, attitude nlerp (shortest path).
## Only position and attitude are interpolated; rates are taken from the current state.
func interpolated(fraction: float) -> PackedFloat64Array:
	var out := state.duplicate()
	for i in 3:
		out[RB.POS + i] = lerpf(previous[RB.POS + i], state[RB.POS + i], fraction)
	var a := RB.ATT
	var sign := 1.0
	if previous[a] * state[a] + previous[a + 1] * state[a + 1] + previous[a + 2] * state[a + 2] + previous[a + 3] * state[a + 3] < 0.0:
		sign = -1.0
	for i in 4:
		out[a + i] = lerpf(previous[a + i], sign * state[a + i], fraction)
	return RK.normalize_attitude(out)
