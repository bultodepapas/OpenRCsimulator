# SF-04b: the kernel's two event locators, qualified through the real Simulation transaction.
# - physics/event_step.gd (declared VehicleModel event) needs a derivative continuation beyond the boundary.
# - physics/rotorcraft/simulation_step_adapter.gd (step policy) never evaluates a stage beyond zero, because the
#   rotorcraft law refuses Ω < 0 and a refused stage faults the tick.
# Known answer: a shaft with friction and viscous drag, Ω' = −A − B·Ω, stops at t* = ln(1 + B·Ω0/A)/B, and a body
# roll rate driven by p' = C·Ω reaches p* = C·[(Ω0 + A/B)(1 − e^(−B·t*))/B − A·t*/B] and then holds.
# Also: a step policy is never split into contact substeps; the kernel refuses such a tick instead of integrating a
# stiff contact over the full dt, and no catalog airplane that runs a policy derives more than one substep.
# Run: godot --headless --path . --script res://tests/test_sf_event_refinement.gd
extends SceneTree

const Sim := preload("res://sim/simulation.gd")
const VehicleModel := preload("res://sim/vehicle_model.gd")
const RB := preload("res://physics/rigid_body.gd")
const RK := preload("res://physics/integrator.gd")
const M := preload("res://physics/math3d.gd")
const Adapter := preload("res://physics/rotorcraft/simulation_step_adapter.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")

const A := 300.0 # rad/s², constant shaft friction
const B := 8.0 # 1/s, viscous shaft drag
const C := 0.05 # 1/s, roll acceleration per rad/s of shaft speed (unit roll inertia)
const OMEGA0 := 20.0 # rad/s at t = 0
const DURATION_S := 0.25 # the stop (t* ≈ 0.053 s) and about 0.2 s held at rest
const RATES := [240, 480, 960]

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var original_rate: int = Engine.physics_ticks_per_second
	_refinement()
	_far_side_contract()
	_hold_restart_and_replay()
	Engine.physics_ticks_per_second = original_rate
	_policy_substep_guard()
	_fleet_policy_substeps()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


static func stop_time() -> float:
	return log(1.0 + B * OMEGA0 / A) / B


static func roll_at_stop() -> float:
	var ts: float = stop_time()
	return C * ((OMEGA0 + A / B) * (1.0 - exp(-B * ts)) / B - A * ts / B)


static func sci(value: float) -> String:
	if value == 0.0 or not is_finite(value):
		return str(value)
	var exponent: int = int(floor(log(absf(value)) / log(10.0)))
	return "%.2fe%d" % [value / pow(10.0, exponent), exponent]


## One shaft value Ω after the rigid body. `route` is "event_step" (declared event, continuation allowed) or
## "adapter" (rotorcraft step policy). `probe` counts beyond-boundary stage evaluations; with `refuse_far_side` such
## a stage is refused like the rotorcraft law refuses Ω < 0, which faults the tick. `probe.drive` is a shaft torque
## per unit inertia (rad/s²) that may restart the shaft from rest.
func _model(route: String, probe: Dictionary, refuse_far_side: bool) -> VehicleModel:
	var m := VehicleModel.new()
	m.continuous_size = 1
	m.stage = func(_body: PackedFloat64Array, continuous: PackedFloat64Array, _t: float) -> Dictionary:
		var w: float = continuous[0]
		if w < 0.0:
			probe.far_side += 1
			if refuse_far_side:
				return {}
		var acceleration: float = float(probe.drive) - A - B * w
		if w == 0.0:
			acceleration = maxf(acceleration, 0.0) # at rest the shaft only leaves the boundary forwards
		return {loads = PackedFloat64Array([0.0, 0.0, 0.0, C * w, 0.0, 0.0]),
			derivative = PackedFloat64Array([acceleration]), rotor_momentum = PackedFloat64Array([0.0, 0.0, 0.0])}
	if route == "event_step":
		m.events = [{type = "rotor_stop", index = RB.SIZE, transition = func(state: PackedFloat64Array, index: int) -> PackedFloat64Array:
			var out := state.duplicate()
			out[index] = 0.0
			return out}]
	else:
		m.step_policy = Adapter.step
	return m


func _sim(model: VehicleModel, omega: float, record: Array) -> Node:
	var sim: Node = Sim.new()
	root.add_child(sim)
	sim.gravity = 0.0
	sim.set_model(model)
	sim.aux = PackedFloat64Array()
	sim.continuous = PackedFloat64Array([omega])
	sim.reset(RB.make_state(M.v3(0.0, 0.0, -50.0), M.v3(0.0, 0.0, 0.0), M.q_identity(), M.v3(0.0, 0.0, 0.0)))
	sim.events_located.connect(func(tick: int, events: Array[Dictionary]) -> void:
		for event: Dictionary in events:
			record.append({tick = tick, type = event.type, time_s = float(event.time_s)}))
	return sim


## Runs one route at one tick rate through the kernel; returns the located stop and the end state.
func _fly(route: String, hz: int) -> Dictionary:
	Engine.physics_ticks_per_second = hz
	var probe := {far_side = 0, drive = 0.0}
	var record: Array = []
	var sim: Node = _sim(_model(route, probe, route == "adapter"), OMEGA0, record)
	var ticks: int = int(round(DURATION_S * hz))
	var at_rest_after_stop := true
	for i in ticks:
		sim.step()
		if not sim.fault_reason.is_empty():
			break
		if not record.is_empty() and sim.continuous[0] != 0.0:
			at_rest_after_stop = false
	var result := {fault = sim.fault_reason, ticks = sim.tick, expected_ticks = ticks, events = record.duplicate(),
		omega = sim.continuous[0], roll = sim.state[RB.RATE], far_side = probe.far_side, at_rest = at_rest_after_stop}
	sim.free()
	return result


func _refinement() -> void:
	var t_star: float = stop_time()
	var p_star: float = roll_at_stop()
	var errors := {}
	for route: String in ["event_step", "adapter"]:
		errors[route] = {t = [], p = []}
		for hz: int in RATES:
			var run: Dictionary = _fly(route, hz)
			var label := "%s %d Hz" % [route, hz]
			_check(label + ": every tick accepted", run.fault.is_empty() and run.ticks == run.expected_ticks, run.fault)
			_check(label + ": exactly one rotor stop", run.events.size() == 1 and run.events[0].type == "rotor_stop", str(run.events))
			_check(label + ": the shaft rests at exactly zero after the stop", run.omega == 0.0 and run.at_rest)
			if run.events.size() != 1:
				continue
			var t_error: float = float(run.events[0].time_s) - t_star
			var p_error: float = float(run.roll) - p_star
			errors[route].t.append(absf(t_error))
			errors[route].p.append(absf(p_error))
			print("     %s: stop-time error %s s, roll-rate error %s rad/s, beyond-boundary stages %d" % [label, sci(t_error), sci(p_error), run.far_side])
			if route == "adapter":
				_check(label + ": no stage beyond the boundary is evaluated", run.far_side == 0)
			else:
				_check(label + ": the shared locator evaluates the continuation beyond the boundary", run.far_side > 0)
	for route: String in errors:
		var t_list: Array = errors[route].t
		var p_list: Array = errors[route].p
		if t_list.size() != RATES.size():
			continue
		# 2e-9 s at 240 Hz is four times the measured 5.5e-10 s; a third-order method would halve its error by 8.
		_check("%s: stop time within 2e-9 s of the analytic root at 240 Hz" % route, t_list[0] <= 2e-9, sci(t_list[0]))
		_check("%s: roll rate within 4e-9 rad/s of the analytic integral at 240 Hz" % route, p_list[0] <= 4e-9, sci(p_list[0]))
		for i in range(1, RATES.size()):
			var t_ratio: float = t_list[i - 1] / t_list[i]
			var p_ratio: float = p_list[i - 1] / p_list[i]
			_check("%s %d→%d Hz: fourth-order refinement (error ratios %.1f, %.1f ≥ 12)" % [route, RATES[i - 1], RATES[i], t_ratio, p_ratio],
				t_ratio >= 12.0 and p_ratio >= 12.0)
	if errors.event_step.t.size() == RATES.size() and errors.adapter.t.size() == RATES.size():
		# Independent implementations: the same root and the same integral at every rate.
		var worst := 0.0
		for i in RATES.size():
			worst = maxf(worst, absf(errors.event_step.t[i] - errors.adapter.t[i]))
		_check("the two locators agree on the stop within 1e-10 s at every rate", worst <= 1e-10, sci(worst))


## The reason the rotorcraft keeps its own policy: behind the shared locator a law that refuses Ω < 0 faults the
## tick, while the guarded adapter flies the same law through the stop.
func _far_side_contract() -> void:
	Engine.physics_ticks_per_second = 240
	var probe := {far_side = 0, drive = 0.0}
	var record: Array = []
	var sim: Node = _sim(_model("event_step", probe, true), OMEGA0, record)
	for i in int(round(DURATION_S * 240.0)):
		sim.step()
		if not sim.fault_reason.is_empty():
			break
	_check("a law refusing the far side cannot sit behind the shared locator: the stop tick faults",
		not sim.fault_reason.is_empty() and record.is_empty(), sim.fault_reason)
	_check("the faulted tick rolled back to a positive shaft speed", sim.continuous[0] > 0.0)
	sim.free()


## No chatter at rest, a clean restart, and exact replay of the stop from a checkpoint (both routes).
func _hold_restart_and_replay() -> void:
	Engine.physics_ticks_per_second = 240
	for route: String in ["event_step", "adapter"]:
		var probe := {far_side = 0, drive = 0.0}
		var record: Array = []
		var sim: Node = _sim(_model(route, probe, route == "adapter"), OMEGA0, record)
		for i in 10: # 41.7 ms, before the 53.4 ms stop
			sim.step()
		var saved: Dictionary = sim.checkpoint()
		for i in 230: # through the stop and about 0.9 s held at rest
			sim.step()
		_check("%s: one stop and no chatter while held at rest for 0.9 s" % route,
			sim.fault_reason.is_empty() and record.size() == 1 and sim.continuous[0] == 0.0, str(record.size()))
		var bytes: PackedByteArray = sim.state.to_byte_array() + sim.continuous.to_byte_array()
		var first_event: Dictionary = record[0] if record.size() == 1 else {}
		record.clear()
		_check("%s: checkpoint restores" % route, sim.restore_checkpoint(saved))
		for i in 230:
			sim.step()
		_check("%s: replay from the checkpoint reproduces the bytes and the event" % route,
			sim.state.to_byte_array() + sim.continuous.to_byte_array() == bytes and record.size() == 1
			and not first_event.is_empty() and record[0].tick == first_event.tick and record[0].time_s == first_event.time_s)
		probe.drive = 400.0 # above friction: the shaft leaves the boundary forwards
		record.clear()
		for i in 24:
			sim.step()
		# Ω' = 100 − 8Ω from rest: Ω(0.1 s) = 12.5·(1 − e^(−0.8)).
		var expected: float = 12.5 * (1.0 - exp(-0.8))
		# RK4 global truncation ≈ 24 · (B·dt)⁵/120 · 12.5 · e^(−0.8) ≈ 4.6e-8; the bound is twice that.
		_check("%s: restart from rest without an event, Ω(0.1 s) within 1e-7 of the analytic %.6f" % [route, expected],
			sim.fault_reason.is_empty() and record.is_empty() and absf(sim.continuous[0] - expected) <= 1e-7,
			sci(sim.continuous[0] - expected))
		sim.free()


## A step policy owns the tick. The kernel never splits it and refuses a tick that asks for contact substeps.
func _policy_substep_guard() -> void:
	var requested := {n = 2}
	var m := VehicleModel.new()
	m.continuous_size = 1
	m.block_loads = func(_b: PackedFloat64Array, _c: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	m.block_derivative = func(_b: PackedFloat64Array, _c: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		return PackedFloat64Array([-1.0])
	m.step_policy = func(combined: PackedFloat64Array, t: float, dt: float, f: Callable, k1: PackedFloat64Array) -> Variant:
		return RK.rk4_step_at(combined, t, dt, f, k1)
	m.substeps = func(_b: PackedFloat64Array, _c: PackedFloat64Array, _t: float) -> int:
		return int(requested.n)
	var sim: Node = Sim.new()
	root.add_child(sim)
	sim.set_model(m)
	sim.aux = PackedFloat64Array()
	sim.continuous = PackedFloat64Array([10.0])
	sim.reset(RB.make_state(M.v3(0.0, 0.0, -50.0), M.v3(15.0, 0.0, 0.0), M.q_identity(), M.v3(0.0, 0.0, 0.0)))
	var before: PackedByteArray = sim.state.to_byte_array() + sim.continuous.to_byte_array()
	sim.step()
	_check("a policy tick asking for 2 contact substeps is refused, not integrated over the full dt",
		sim.fault_reason.contains("cannot honour 2 contact substeps"), sim.fault_reason)
	_check("the refused tick rolled back", sim.tick == 0 and sim.state.to_byte_array() + sim.continuous.to_byte_array() == before)
	requested.n = 1
	_check("the policy model resets", sim.reset(RB.make_state(M.v3(0.0, 0.0, -50.0), M.v3(15.0, 0.0, 0.0), M.q_identity(), M.v3(0.0, 0.0, 0.0))))
	sim.step()
	_check("one substep under a policy is accepted", sim.fault_reason.is_empty() and sim.tick == 1, sim.fault_reason)
	sim.free()


## The guard is byte-neutral for the fleet: every catalog airplane that runs a step policy derives one gear substep.
## A stiffer gear on such an airplane fails here, before any flight could fault near the ground.
func _fleet_policy_substeps() -> void:
	var policies := 0
	for id: String in Catalog.airplane_flyable_ids():
		var session := FlightSession.new()
		session.input_enabled = false
		session.setup(Catalog.entry(id).data, id)
		if session.is_flyable() and session.sim.model.step_policy.is_valid():
			policies += 1
			var gear: Variant = session.aircraft.model.get("landing_gear")
			var count: int = int(gear.get("substeps", 1)) if gear is Dictionary else 1
			_check("%s runs a step policy with %d derived gear substep(s); the kernel allows 1" % [id, count], count == 1)
		session.free()
	_check("the catalog inventory found the policy airplanes (glow Stiks)", policies >= 1, str(policies))
