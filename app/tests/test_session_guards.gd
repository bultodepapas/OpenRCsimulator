# D4-R1: reject untrimmable aircraft transactionally and keep numerical faults out of the flight state.
# Run: godot --headless --path . --script res://tests/test_session_guards.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const Sim := preload("res://sim/simulation.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not ok:
		_failures += 1


func _write_untrimmable_aircraft() -> String:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Scenarios.AIRCRAFT))
	raw.controls.max_throw.elevator.value = 1.0
	var path := "user://session-guard-untrimmable.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(raw))
	file.close()
	return path


func _state() -> PackedFloat64Array:
	return RB.make_state(M.v3(0.0, 0.0, -20.0), M.v3(15.0, 0.0, 0.0), M.q_identity(), M.v3(0.0, 0.0, 0.0))


func _initialize() -> void:
	var bad_aircraft_path := _write_untrimmable_aircraft()
	_check("untrimmable fixture was written", not bad_aircraft_path.is_empty())
	if bad_aircraft_path.is_empty():
		quit(1)
		return

	var session := FlightSession.new()
	session.setup()
	root.add_child(session)
	session.input_enabled = false
	session.reset()
	var old_throw: float = session.aircraft.model.controls.throw_deg.elevator
	var old_start: PackedFloat64Array = session.start.state.duplicate()
	var old_trims: Dictionary = session.trims.duplicate(true)
	var old_state: PackedFloat64Array = session.sim.state.duplicate()
	var old_previous: PackedFloat64Array = session.sim.previous.duplicate()
	var old_tick: int = session.sim.tick
	var old_paused: bool = session.sim.paused
	session.aircraft_path = bad_aircraft_path
	var reload_result := session.reload()
	_check("untrimmable reload is rejected", reload_result.begins_with("reload failed"), reload_result)
	_check("rejected reload preserves the active model", is_equal_approx(session.aircraft.model.controls.throw_deg.elevator, old_throw))
	_check("rejected reload preserves start and trims", session.start.state == old_start and session.trims == old_trims)
	_check("rejected reload preserves current and previous state", session.sim.state == old_state and session.sim.previous == old_previous)
	_check("rejected reload preserves tick and pause status", session.sim.tick == old_tick and session.sim.paused == old_paused)
	session.sim.loads = func(_s: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		return PackedFloat64Array([NAN, 0.0, 0.0, 0.0, 0.0, 0.0])
	session.sim.step()
	_check("session exposes a runtime fault and pauses", session.sim.paused and session.pause_reason.begins_with("simulation fault:"))
	session.resume()
	_check("session resume cannot bypass a runtime fault", session.sim.paused and session.pause_reason.begins_with("simulation fault:"))

	var first_start := FlightSession.new()
	first_start.setup(bad_aircraft_path)
	root.add_child(first_start)
	first_start.input_enabled = false
	first_start.reset()
	var failure_message := first_start.pause_reason
	_check("untrimmable initial aircraft has no accepted start", not first_start.start.get("ok", false))
	_check("untrimmable initial aircraft stays paused", first_start.sim.paused)
	_check("initial failure states the trim problem", failure_message.contains("trim"), failure_message)
	first_start.resume()
	_check("resume cannot bypass an invalid initial trim", first_start.sim.paused and first_start.pause_reason == failure_message)
	var parked_state: PackedFloat64Array = first_start.sim.state.duplicate()
	first_start.sim.set_paused(false)
	first_start.sim.step()
	_check("direct stepping cannot bypass an invalid initial trim", first_start.sim.paused
		and first_start.sim.tick == 0 and first_start.sim.state == parked_state)
	_check("invalid initial start is inert instead of a thrown flight", Sim.state_is_valid(first_start.sim.state)
		and first_start.sim.state[RB.VEL] == 0.0 and first_start.sim.state[RB.RATE] == 0.0)

	var load_sim := Sim.new()
	root.add_child(load_sim)
	var valid_state := _state()
	_check("simulation accepts a valid initial state", load_sim.reset(valid_state))
	var saved_load_state: PackedFloat64Array = load_sim.state.duplicate()
	load_sim.loads = func(_s: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		return PackedFloat64Array([NAN, 0.0, 0.0, 0.0, 0.0, 0.0])
	load_sim.step()
	_check("nonfinite loads pause at the last valid state", load_sim.paused and load_sim.state == saved_load_state)
	_check("nonfinite loads expose a readable fault", load_sim.fault_reason.contains("loads"), load_sim.fault_reason)
	load_sim.set_paused(false)
	_check("numerical fault cannot be resumed without a valid reset", load_sim.paused)
	load_sim.loads = func(_s: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	_check("explicit valid reset clears the simulation fault", load_sim.reset(valid_state) and load_sim.fault_reason.is_empty())
	for failing_stage in [2, 3, 4]:
		var stage_sim := Sim.new()
		root.add_child(stage_sim)
		stage_sim.reset(valid_state)
		var stage_state: PackedFloat64Array = stage_sim.state.duplicate()
		var stage_previous: PackedFloat64Array = stage_sim.previous.duplicate()
		var stage_aux: PackedFloat64Array = stage_sim.aux.duplicate()
		var calls := [0]
		var fail_on_call: int = failing_stage # loads() is called once before RK (H2: that call is also k1), then for k2…k4.
		stage_sim.loads = func(_s: PackedFloat64Array, _t: float) -> PackedFloat64Array:
			calls[0] += 1
			if calls[0] == fail_on_call:
				return PackedFloat64Array([NAN, 0.0, 0.0, 0.0, 0.0, 0.0])
			return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
		stage_sim.step()
		_check("nonfinite k%d loads roll back the full tick" % failing_stage,
			stage_sim.paused and stage_sim.tick == 0 and stage_sim.state == stage_state
			and stage_sim.previous == stage_previous and stage_sim.aux == stage_aux
			and stage_sim.fault_reason.contains("RK stage loads"),
			"calls %d, %s" % [calls[0], stage_sim.fault_reason])

	# H2: a tick evaluates the loads four times, not five (stage 1 reuses the tick's own loads).
	var count_sim := Sim.new()
	root.add_child(count_sim)
	count_sim.reset(valid_state)
	var load_calls := [0]
	count_sim.loads = func(_s: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		load_calls[0] += 1
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	count_sim.step()
	_check("a tick evaluates the loads 4 times (H2: k1 reuses the tick's loads)", load_calls[0] == 4, str(load_calls[0]))

	var aux_sim := Sim.new()
	root.add_child(aux_sim)
	aux_sim.reset(valid_state)
	var saved_aux_state: PackedFloat64Array = aux_sim.state.duplicate()
	aux_sim.aux[0] = NAN
	aux_sim.step()
	_check("nonfinite auxiliary state rolls back and pauses", aux_sim.paused and aux_sim.state == saved_aux_state
		and is_finite(aux_sim.aux[0]) and not aux_sim.fault_reason.is_empty())
	var pre_step_sim := Sim.new()
	root.add_child(pre_step_sim)
	pre_step_sim.reset(valid_state)
	var saved_pre_step_state: PackedFloat64Array = pre_step_sim.state.duplicate()
	pre_step_sim.pre_step = func(_aux: PackedFloat64Array, _inputs: PackedFloat64Array, _dt: float) -> PackedFloat64Array:
		return PackedFloat64Array([NAN])
	pre_step_sim.step()
	_check("nonfinite pre-step auxiliary output rolls back and pauses", pre_step_sim.paused
		and pre_step_sim.state == saved_pre_step_state and pre_step_sim.aux == PackedFloat64Array([0.0]))

	var state_sim := Sim.new()
	root.add_child(state_sim)
	state_sim.reset(valid_state)
	var saved_state: PackedFloat64Array = state_sim.state.duplicate()
	state_sim.state[RB.POS] = INF
	state_sim.step()
	_check("nonfinite current state restores the last valid state", state_sim.paused and state_sim.state == saved_state
		and state_sim.fault_reason.contains("state"))

	var quaternion_sim := Sim.new()
	root.add_child(quaternion_sim)
	quaternion_sim.reset(valid_state)
	var saved_quaternion_state: PackedFloat64Array = quaternion_sim.state.duplicate()
	var degenerate := valid_state.duplicate()
	for i in 4:
		degenerate[RB.ATT + i] = 0.0
	_check("degenerate quaternion reset is rejected", not quaternion_sim.reset(degenerate))
	_check("rejected quaternion reset retains valid state and pauses", quaternion_sim.paused
		and quaternion_sim.state == saved_quaternion_state and quaternion_sim.fault_reason.contains("quaternion"))
	var nonfinite_quaternion := valid_state.duplicate()
	nonfinite_quaternion[RB.ATT + 2] = NAN
	_check("nonfinite quaternion reset is rejected", not quaternion_sim.reset(nonfinite_quaternion))
	_check("nonfinite quaternion keeps the last valid state", quaternion_sim.state == saved_quaternion_state
		and quaternion_sim.fault_reason.contains("quaternion"))

	var acrobatic_sim := Sim.new()
	root.add_child(acrobatic_sim)
	var acrobatic_state := RB.make_state(M.v3(0.0, 0.0, -100.0), M.v3(18.0, 0.0, 0.0),
		M.q_from_euler(PI / 2.0, PI / 2.0, PI), M.v3(30.0, -25.0, 20.0))
	acrobatic_sim.reset(acrobatic_state)
	acrobatic_sim.step()
	_check("inverted flight and high angular rates are not faulted by themselves", not acrobatic_sim.paused
		and acrobatic_sim.fault_reason.is_empty() and Sim.state_is_valid(acrobatic_sim.state))

	var changed_inertia_sim := Sim.new()
	root.add_child(changed_inertia_sim)
	changed_inertia_sim.loads = func(_s: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		return PackedFloat64Array([4.0, 0.0, 0.0, 2.0, 0.0, 0.0])
	changed_inertia_sim.reset(valid_state)
	changed_inertia_sim.mass = 2.0
	changed_inertia_sim.inertia = PackedFloat64Array([2.0, 3.0, 4.0, 0.0, 0.0, 0.0])
	changed_inertia_sim.step()
	_check("valid mass and inertia changes after reset use current values", not changed_inertia_sim.paused
		and absf(changed_inertia_sim.state[RB.VEL] - (valid_state[RB.VEL] + 2.0 * changed_inertia_sim.dt())) < 1e-10
		and absf(changed_inertia_sim.state[RB.RATE] - changed_inertia_sim.dt()) < 1e-10,
		"u %.9f, p %.9f" % [changed_inertia_sim.state[RB.VEL], changed_inertia_sim.state[RB.RATE]])

	print("%d checks, %d failed" % [_count, _failures])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(bad_aircraft_path))
	quit(1 if _failures > 0 else 0)
