# H8: exact, bounded physics checkpoints; no live radio/UI serialization.
extends SceneTree

const Sim := preload("res://sim/simulation.gd")
const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const RB := preload("res://physics/rigid_body.gd")
const RK := preload("res://physics/integrator.gd")
const M := preload("res://physics/math3d.gd")
var checks := 0
var failures := 0

class ResetFailureFlight extends "res://sim/flight_session.gd":
	var reject_reset := false
	func _loads(s: PackedFloat64Array, t: float) -> PackedFloat64Array:
		if reject_reset:
			return PackedFloat64Array([NAN, 0, 0, 0, 0, 0])
		return super._loads(s, t)


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func initial() -> PackedFloat64Array:
	return RB.make_state(M.v3(0, 0, -100), M.v3(15, 0, 0), M.q_identity(), M.v3(0, 0, 0))


func matches_snapshot(sim: Node, cp: Dictionary) -> bool:
	for key in ["state", "previous", "aux", "inputs", "modes", "last_loads", "tick", "stop_at_tick", "mass", "gravity", "inertia"]:
		if var_to_bytes(sim.get(key)) != var_to_bytes(cp[key]):
			return false
	return true


func kernel_contract() -> void:
	var sim := Sim.new()
	sim.modes = PackedInt64Array([1, 0])
	sim.aux = PackedFloat64Array([1200, 0.125])
	sim.reset(initial())
	sim.step()
	var cp: Dictionary = sim.checkpoint()
	var detached: Dictionary = sim.checkpoint()
	detached.aux[0] = 42.0
	detached.modes[0] = 0
	check("checkpoint detached from owner", sim.aux[0] == 1200 and sim.modes[0] == 1)
	var decoded: Dictionary = bytes_to_var(var_to_bytes(cp))
	check("native Variant encoding preserves all bits", var_to_bytes(decoded) == var_to_bytes(cp))
	for field in ["state", "previous", "aux", "inputs", "last_loads"]:
		var bad: Dictionary = cp.duplicate(true)
		bad[field][0] = NAN
		check("reject nonfinite " + field, not sim.restore_checkpoint(bad) and matches_snapshot(sim, cp))
	for field in cp:
		var bad: Dictionary = cp.duplicate(true)
		bad.erase(field)
		check("reject missing " + field, not sim.restore_checkpoint(bad) and matches_snapshot(sim, cp))
	for entry in [["format", 42], ["gravity", NAN], ["state", []], ["tick", -1], ["tick", 1.5], ["stop_at_tick", -2], ["dt", 0.1], ["mass", 2.0], ["modes", PackedInt64Array([1])], ["aux", PackedFloat64Array()]]:
		var bad: Dictionary = cp.duplicate(true)
		bad[entry[0]] = entry[1]
		check("reject malformed or incompatible " + str(entry[0]), not sim.restore_checkpoint(bad) and matches_snapshot(sim, cp))
	var bad_attitude: Dictionary = cp.duplicate(true)
	bad_attitude.state[RB.ATT] = 2.0
	check("checkpoint quaternion must already be normalized", not sim.restore_checkpoint(bad_attitude))
	for fail_at in [0, 1, 2, 3, 4]:
		sim.restore_checkpoint(cp)
		var calls := [0]
		sim.pre_step = func(a: PackedFloat64Array, _i: PackedFloat64Array, _dt: float) -> PackedFloat64Array:
			sim.modes[0] = 0
			sim.stop_at_tick = 200
			return PackedFloat64Array([NAN, 0.0]) if fail_at == 0 else a
		sim.loads = func(_s: PackedFloat64Array, _t: float) -> PackedFloat64Array:
			calls[0] += 1
			return PackedFloat64Array([NAN if calls[0] == fail_at else 0.0, 0, 0, 0, 0, 0])
		sim.step()
		check("failure %d restores every dynamic entry" % fail_at, matches_snapshot(sim, cp) and sim.paused and not sim.fault_reason.is_empty())
	sim.restore_checkpoint(cp)
	sim.mass = -1
	sim.tick = 900
	sim.modes[1] = 5
	check("invalid reset refused", not sim.reset(PackedFloat64Array()))
	check("invalid reset restores clock modes and configuration", matches_snapshot(sim, cp))
	sim.restore_checkpoint(cp)
	check("restoration clears fault and pauses", sim.fault_reason.is_empty() and sim.paused)
	var old_hz := Engine.physics_ticks_per_second
	var old_time: float = sim.time()
	Engine.physics_ticks_per_second = old_hz * 2
	sim.step()
	check("changing global tick rate cannot reinterpret committed time", sim.time() == old_time and matches_snapshot(sim, cp) and not sim.fault_reason.is_empty())
	check("checkpoint refuses a changed engine tick rate", not sim.restore_checkpoint(cp))
	Engine.physics_ticks_per_second = old_hz
	check("restoration works after configuration correction", sim.restore_checkpoint(cp))
	sim.free()
	var plain := Sim.new()
	var unused := Sim.new()
	unused.aux.append(123.5)
	unused.modes.append(7)
	plain.reset(initial())
	unused.reset(initial())
	for i in 240:
		plain.step()
		unused.step()
	check("unused sampled/discrete entries change no trajectory", plain.state.to_byte_array() == unused.state.to_byte_array() and unused.aux[1] == 123.5 and unused.modes[0] == 7)
	plain.free()
	unused.free()
	var body := initial()
	var extended := body.duplicate()
	extended.append(123.0)
	var derivative := func(s: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		var d := PackedFloat64Array()
		d.resize(s.size())
		d[RB.POS] = s[RB.VEL]
		d[RB.VEL] = 1.0
		return d
	for i in 100:
		body = RK.rk4_step_at(body, i / 240.0, 1.0 / 240.0, derivative)
		extended = RK.rk4_step_at(extended, i / 240.0, 1.0 / 240.0, derivative)
	check("unused continuous kernel entry changes no trajectory", extended.slice(0, RB.SIZE).to_byte_array() == body.to_byte_array() and extended[-1] == 123.0)


func replay_aircraft(id: String) -> void:
	var flight := Flight.new()
	flight.setup(Catalog.entry(id).data)
	flight.input_enabled = false
	for i in 50:
		flight.sim.inputs[0] = 0.1
		flight.sim.inputs[3] = 0.6
		flight.sim.step()
	flight.engine_running = false
	flight.sim.step() # commit a non-default discrete state and decaying/slewed auxiliary state
	var cp: Dictionary = flight.checkpoint()
	check(id + " complete boundary captured", not cp.is_empty() and cp.simulation.tick == 51 and cp.simulation.modes[0] == 0)
	for i in 80:
		flight.sim.inputs[1] = -0.1
		flight.sim.step()
	var expected: Dictionary = flight.sim.checkpoint()
	flight.reset()
	check(id + " reset restores initial state and engine mode", flight.sim.tick == 0 and flight.engine_running and flight.sim.state == flight.start.state)
	check(id + " restore after reset", flight.restore_checkpoint(bytes_to_var(var_to_bytes(cp))))
	check(id + " restore disables live sampling", not flight.input_enabled and flight.sim.paused and not flight.engine_running)
	for i in 80:
		flight.sim.inputs[1] = -0.1
		flight.sim.step()
	check(id + " midflight replay exact", matches_snapshot(flight.sim, expected))
	var bad: Dictionary = cp.duplicate(true)
	bad.simulation.modes[0] = 9
	check(id + " invalid engine mode rejected atomically", not flight.restore_checkpoint(bad) and matches_snapshot(flight.sim, expected))
	var valid_modes: PackedInt64Array = flight.sim.modes.duplicate()
	for invalid_modes in [PackedInt64Array(), PackedInt64Array([0, 1]), PackedInt64Array([9])]:
		flight.sim.modes = invalid_modes
		check(id + " invalid current mode cannot produce a checkpoint", flight.checkpoint().is_empty())
	flight.sim.modes = valid_modes
	flight.ground_surfaces = PackedFloat64Array([1.0])
	check(id + " changed ground configuration rejected", not flight.restore_checkpoint(cp) and matches_snapshot(flight.sim, expected))
	flight.ground_surfaces = PackedFloat64Array()
	var reloaded := flight.reload()
	check(id + " reload resets sampled and discrete state", reloaded.begins_with("aircraft reloaded") and flight.sim.tick == 0 and flight.engine_running and flight.sim.aux[0] == flight.start.rpm)
	flight.free()


func reload_failure() -> void:
	var flight := ResetFailureFlight.new()
	flight.setup()
	flight.input_enabled = false
	flight.sim.step()
	var old: Dictionary = flight.sim.checkpoint()
	flight.reject_reset = true
	var result := flight.reload()
	check("late reload reset failure retains all physics state", result.begins_with("reload failed; previous aircraft") and matches_snapshot(flight.sim, old))
	flight.reject_reset = false
	flight.sim.step()
	check("retained flight can advance after rejected reload", flight.sim.tick == old.tick + 1 and flight.sim.fault_reason.is_empty())
	flight.free()


func _initialize() -> void:
	kernel_contract()
	for id in ["jensen-das-ugly-stik-60", "gp-extra-300s-60", "p51d-mustang-120", "sebart-avanti-s-a200-p100rx"]:
		replay_aircraft(id)
	reload_failure()
	print("H8 checkpoints: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
