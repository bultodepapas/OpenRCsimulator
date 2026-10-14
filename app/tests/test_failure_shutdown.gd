extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const AircraftCatalog := preload("res://app_state/aircraft_catalog.gd")
const FailureConfig := preload("res://failures/config.gd")
const FailureRuntime := preload("res://failures/runtime.gd")
const FailureCatalog := preload("res://failures/catalog.gd")
const RigidBody := preload("res://physics/rigid_body.gd")

const DT := 1.0 / 240.0
const CONFIG := {
	"probability_percent": 100,
	"include_catastrophic": false,
	"notify": true,
}
const AIRCRAFT_CASES := [
	{"id": "stik-glow-55ax-2t", "event": "glow_fuel_cut", "profile": "finite-glow-v1", "kind": "glow"},
	{"id": "stik-glow-fs64v-4t", "event": "glow_fuel_cut", "profile": "finite-glow-v1", "kind": "glow"},
	{"id": "turbo-lumber-evolution", "event": "electric_drive_loss", "profile": "electric-drive-v1", "kind": "electric"},
]
const BATTERY_FIXTURE := "res://data/aircraft/synthetic_stik_electric_4s_battery.json"

var _checks := 0
var _failures := 0


func _initialize() -> void:
	for case: Dictionary in AIRCRAFT_CASES:
		_test_scheduled_shutdown(case)
	_test_dynamic_battery_auxiliary_budget()
	print("Failure power shutdown integration: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool, detail: Variant = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s: %s" % [label, str(detail)])


func _new_flight(id: String) -> Node:
	var entry: Dictionary = AircraftCatalog.entry(id)
	var flight: Node = Flight.new()
	flight.setup(str(entry.get("data", "")), id)
	flight.input_enabled = false
	return flight


func _new_fixture(path: String) -> Node:
	var flight: Node = Flight.new()
	flight.setup(path)
	flight.input_enabled = false
	return flight


func _seed_for(profile: String, event_id: String, dt: float) -> int:
	for seed in 100000:
		var runtime: RefCounted = FailureRuntime.new()
		if not runtime.begin(CONFIG, seed, dt, profile):
			continue
		var plan: Dictionary = runtime.plan()
		if bool(plan.get("selected", false)) and str(plan.get("id", "")) == event_id \
				and int(plan.get("onset_airborne_seconds", -1)) == 20:
			return seed
	return -1


func _position_airborne(flight: Node, label: String) -> bool:
	var state: PackedFloat64Array = flight.sim.state.duplicate()
	state[RigidBody.POS + 2] = -1000.0
	var moved: bool = flight.sim.reset(state)
	var airborne: bool = moved and flight._failure_airborne()
	_check(label + " starts at a qualified airborne altitude", airborne)
	return airborne


func _test_scheduled_shutdown(case: Dictionary) -> void:
	var aircraft_id: String = str(case.id)
	var label: String = aircraft_id + " " + str(case.event)
	var flight: Node = _new_flight(aircraft_id)
	if not flight.is_flyable():
		_check(label + " fixture flies", false, flight.aircraft.get("message", ""))
		flight.free()
		return
	if not _position_airborne(flight, label):
		flight.free()
		return

	var dt: float = flight.sim.dt()
	_check(label + " uses the expected 240 Hz timestep", is_equal_approx(dt, DT), dt)
	var expected_profile: String = str(case.profile)
	_check(label + " model resolves the expected failure profile",
		FailureCatalog.profile_for_model(flight.aircraft.model) == expected_profile)
	var seed: int = _seed_for(expected_profile, str(case.event), dt)
	_check(label + " finds a deterministic 20 second event seed", seed >= 0, seed)
	if seed < 0:
		flight.free()
		return
	_check(label + " configures one failure episode", flight.setup_failures(CONFIG, seed), flight.failure_error)
	var plan: Dictionary = flight._failures.plan()
	var onset: int = int(plan.get("onset_airborne_ticks", -1))
	_check(label + " resolves the requested shutdown at 20 seconds",
		str(plan.get("id", "")) == str(case.event)
		and int(plan.get("onset_airborne_seconds", -1)) == 20
		and onset == int(ceili(20.0 / dt)), plan)
	if onset < 2:
		flight.free()
		return

	for _tick in range(onset - 1):
		var previous_tick: int = flight.sim.tick
		flight.sim.step()
		if flight.sim.tick != previous_tick + 1:
			break
	_check(label + " reaches the accepted tick before onset",
		flight.sim.tick == onset - 1 and int(flight._failures.snapshot().airborne_ticks) == onset - 1,
		{"tick": flight.sim.tick, "runtime": flight._failures.snapshot()})
	_check(label + " remains a powered source before onset", flight.propulsion_power_enabled())
	if str(case.kind) == "glow":
		var before_glow: Dictionary = flight.glow_state()
		_check(label + " has burned fuel and recorded real combustion before onset",
			float(before_glow.get("fuel_kg", 0.0)) < float(flight.aircraft.model.propulsion.glow.initial_fuel_kg)
			and int(before_glow.get("fire_count", 0)) > 0
			and float(before_glow.get("chemical_power_w", 0.0)) > 0.0, before_glow)
	else:
		var before_electric: Dictionary = flight.electrical_state()
		_check(label + " has real motor demand before onset", before_electric.get("ok", false)
			and float(before_electric.get("motor_current_a", 0.0)) > 0.0
			and float(before_electric.get("shaft_torque_nm", 0.0)) > 0.0, before_electric)

	# Full raw throttle is recorded on the exact candidate tick; the fault acts on the source behind it.
	flight.sim.inputs = PackedFloat64Array([0.0, 0.0, 0.0, 1.0])
	var pre_onset_checkpoint: Dictionary = flight.checkpoint()
	_check(label + " pre-onset checkpoint retains an inactive profile plan",
		pre_onset_checkpoint.get("format", "") == "openrc-flight-checkpoint v10"
		and not bool(pre_onset_checkpoint.get("failure_state", {}).get("active", true)))
	var change_count: Array[int] = [0]
	var notice: Callable = func() -> void: change_count[0] += 1
	flight.failure_changed.connect(notice)

	var rejected: Node = _new_flight(aircraft_id)
	var rejected_change_count: Array[int] = [0]
	var rejected_notice: Callable = func() -> void: rejected_change_count[0] += 1
	rejected.failure_changed.connect(rejected_notice)
	_check(label + " restores the pre-onset checkpoint into an isolated session",
		rejected.restore_checkpoint(pre_onset_checkpoint))
	var rollback_before: PackedByteArray = _rollback_bytes(rejected.sim)
	var runtime_before: Dictionary = rejected._failures.snapshot()
	var rejected_tick: int = rejected.sim.tick
	var original_post_step: Callable = rejected.sim.post_step
	rejected.sim.post_step = func(previous: PackedFloat64Array, candidate: PackedFloat64Array,
			accepted_tick: int) -> PackedFloat64Array:
		if original_post_step.is_valid():
			original_post_step.call(previous, candidate, accepted_tick)
		return PackedFloat64Array([NAN])
	rejected.sim.step()
	_check(label + " rejects the fully evaluated onset candidate", rejected.sim.tick == rejected_tick
		and not rejected.sim.fault_reason.is_empty())
	_check(label + " onset rejection rolls back physics, modes and source state",
		_rollback_bytes(rejected.sim) == rollback_before and rejected.engine_running
		and rejected.propulsion_power_enabled() and not rejected.failure_power_cut_active())
	_check(label + " onset rejection rolls back the staged runtime and emits no notice",
		rejected._failures.snapshot() == runtime_before and rejected_change_count[0] == 0)
	rejected.sim.post_step = original_post_step
	_check(label + " explicit recovery restores the valid pre-onset boundary",
		rejected.restore_checkpoint(pre_onset_checkpoint))

	var reference: Node = _new_flight(aircraft_id)
	var physics_reference: Dictionary = _strip_failure_wrapper(pre_onset_checkpoint)
	_check(label + " loads a matching no-failure physical reference",
		reference.restore_checkpoint(physics_reference))
	var reference_stopped: bool
	if str(case.kind) == "glow":
		reference_stopped = reference.glow_cut()
	else:
		reference.engine_running = false
		reference_stopped = not reference.propulsion_power_enabled()
	_check(label + " manual source-off reference is established", reference_stopped)

	var pre_cut_rpm: float = float(flight.sim.continuous[0] if str(case.kind) == "glow" else flight.sim.aux[Flight.AUX_RPM])
	flight.sim.step()
	rejected.sim.step()
	reference.sim.step()
	var status: Dictionary = flight.failure_status()
	_check(label + " accepted onset activates the persistent cut once",
		bool(status.get("active", false)) and str(status.get("event_id", "")) == str(case.event)
		and flight.failure_power_cut_active() and not flight.propulsion_power_enabled()
		and not flight.engine_running and change_count[0] == 1, status)
	_check(label + " accepted replay matches the original physics boundary",
		var_to_bytes(flight.sim.checkpoint()) == var_to_bytes(rejected.sim.checkpoint()))
	_check(label + " staged failure matches its family-specific stopped reference",
		var_to_bytes(flight.sim.checkpoint()) == var_to_bytes(reference.sim.checkpoint()))
	_check(label + " raw pilot throttle remains at full demand", flight.sim.inputs[3] == 1.0)
	var active_checkpoint: Dictionary = flight.checkpoint()
	_check(label + " active failure checkpoint preserves profile and event",
		active_checkpoint.get("format", "") == "openrc-flight-checkpoint v10"
		and bool(active_checkpoint.get("failure_state", {}).get("active", false))
		and str(active_checkpoint.get("failure_state", {}).get("plan", {}).get("eligibility_profile", "")) == expected_profile)
	_check(label + " first shutdown tick preserves continuous rotor speed",
		pre_cut_rpm > 0.0 and _rpm(flight, str(case.kind)) > 0.0
		and absf(_rpm(flight, str(case.kind)) - pre_cut_rpm) < maxf(1.0, pre_cut_rpm * 0.10),
		{"before": pre_cut_rpm, "after": _rpm(flight, str(case.kind))})
	if str(case.kind) == "glow":
		var cut_glow: Dictionary = flight.glow_state()
		_check(label + " accepted cutoff stops combustion and transport immediately",
			not bool(cut_glow.get("running", true))
			and float(cut_glow.get("chemical_power_w", NAN)) == 0.0
			and float(cut_glow.get("fuel_transport_kg_s", NAN)) == 0.0
			and int(cut_glow.get("fire_count", -1)) == int(pre_onset_checkpoint.simulation.continuous[10]), cut_glow)
	else:
		var cut_electric: Dictionary = flight.electrical_state()
		_check(label + " accepted cutoff disconnects motor current and shaft torque",
			not bool(cut_electric.get("enabled", true))
			and float(cut_electric.get("motor_current_a", NAN)) == 0.0
			and float(cut_electric.get("shaft_torque_nm", NAN)) <= 0.0, cut_electric)

	# Reject the first tick after activation on the original flight. The active
	# checkpoint below is only used to recover after verifying the transaction.
	var post_cut_checkpoint: Dictionary = flight.checkpoint()
	var post_cut_physics: PackedByteArray = _rollback_bytes(flight.sim)
	var post_cut_runtime: Dictionary = flight._failures.snapshot()
	var post_cut_tick: int = flight.sim.tick
	var post_cut_notice_count: int = change_count[0]
	var original_post_cut_callback: Callable = flight.sim.post_step
	flight.sim.post_step = func(previous: PackedFloat64Array, candidate: PackedFloat64Array,
			accepted_tick: int) -> PackedFloat64Array:
		if original_post_cut_callback.is_valid():
			original_post_cut_callback.call(previous, candidate, accepted_tick)
		return PackedFloat64Array([NAN])
	flight.sim.step()
	_check(label + " post-cut candidate rejection leaves tick and physics unchanged",
		flight.sim.tick == post_cut_tick and not flight.sim.fault_reason.is_empty()
		and _rollback_bytes(flight.sim) == post_cut_physics)
	_check(label + " post-cut rejection preserves accepted engine-off mode and active runtime",
		flight.sim.modes[0] == 0 and not flight.engine_running
		and flight.failure_power_cut_active() and not flight.propulsion_power_enabled()
		and flight._failures.snapshot() == post_cut_runtime, flight.failure_status())
	_check(label + " post-cut rejection emits no duplicate event and retains a complete active checkpoint",
		change_count[0] == post_cut_notice_count
		and bool(post_cut_checkpoint.get("failure_state", {}).get("active", false))
		and flight.checkpoint() == post_cut_checkpoint)
	flight.sim.post_step = original_post_cut_callback
	_check(label + " post-cut rejection recovers at the exact active checkpoint",
		flight.restore_checkpoint(post_cut_checkpoint)
		and var_to_bytes(flight.checkpoint()) == var_to_bytes(post_cut_checkpoint)
		and change_count[0] == post_cut_notice_count)

	var replay: Node = _new_flight(aircraft_id)
	var replay_changes: Array[int] = [0]
	var replay_notice: Callable = func() -> void: replay_changes[0] += 1
	replay.failure_changed.connect(replay_notice)
	_check(label + " restores an active cut into a fresh session", replay.restore_checkpoint(active_checkpoint))
	_check(label + " active restore is byte exact and does not repeat the event",
		var_to_bytes(replay.checkpoint()) == var_to_bytes(active_checkpoint) and replay_changes[0] == 0)
	_check_active_checkpoint_guards(flight, replay, active_checkpoint, label, str(case.kind))
	_check_wrong_profile_restore(flight, replay, active_checkpoint, expected_profile, dt, label)

	var stopped_fuel: float = 0.0
	var stopped_chemical_work: float = 0.0
	var stopped_fire_count: int = -1
	if str(case.kind) == "glow":
		stopped_fuel = float(flight.sim.continuous[1])
		stopped_chemical_work = float(flight.sim.continuous[16])
		stopped_fire_count = int(flight.glow_state().get("fire_count", -1))
	var roll_command: float = -0.7 if flight.sim.aux[Flight.AUX_SERVO] >= 0.0 else 0.7
	for peer: Node in [flight, rejected, reference, replay]:
		peer.sim.inputs = PackedFloat64Array([roll_command, 0.0, 0.0, 1.0])
	var servo_before: float = float(flight.sim.aux[Flight.AUX_SERVO])
	flight.sim.step()
	rejected.sim.step()
	reference.sim.step()
	var first_post_cut_checkpoint: Dictionary = flight.checkpoint()
	_check(label + " first tick after shutdown retains an active, disabled source and raw pilot demand",
		int(flight.sim.tick) == int(active_checkpoint.simulation.tick) + 1
		and flight.failure_power_cut_active() and not flight.engine_running
		and not flight.propulsion_power_enabled() and flight.sim.modes[0] == 0
		and flight.sim.inputs[3] == 1.0, flight.failure_status())
	_check(label + " first post-cut checkpoint is complete and restores without another notice",
		first_post_cut_checkpoint.get("format", "") == "openrc-flight-checkpoint v10"
		and bool(first_post_cut_checkpoint.get("failure_state", {}).get("active", false))
		and replay.restore_checkpoint(first_post_cut_checkpoint)
		and var_to_bytes(replay.checkpoint()) == var_to_bytes(first_post_cut_checkpoint)
		and replay_changes[0] == 0)
	_check(label + " first post-cut tick has no duplicate notice and matches stopped peers",
		change_count[0] == 1
		and var_to_bytes(flight.sim.checkpoint()) == var_to_bytes(rejected.sim.checkpoint())
		and var_to_bytes(flight.sim.checkpoint()) == var_to_bytes(reference.sim.checkpoint()))
	for _tick in 11:
		flight.sim.step()
		rejected.sim.step()
		reference.sim.step()
		replay.sim.step()
	_check(label + " usable roll control still moves the servo while raw throttle stays high",
		absf(float(flight.sim.aux[Flight.AUX_SERVO]) - servo_before) > 0.0
		and flight.sim.inputs[0] == roll_command and flight.sim.inputs[3] == 1.0)
	_check(label + " source-off reference and active checkpoint replay remain physically exact",
		var_to_bytes(flight.sim.checkpoint()) == var_to_bytes(reference.sim.checkpoint())
		and var_to_bytes(flight.sim.checkpoint()) == var_to_bytes(replay.sim.checkpoint()))
	_check(label + " no repeated failure notice occurs after onset", change_count[0] == 1 and replay_changes[0] == 0)
	if str(case.kind) == "glow":
		var final_glow: Dictionary = flight.glow_state()
		_check(label + " stopped reference holds fuel, chemical work and fire count",
			flight.sim.continuous[1] == stopped_fuel
			and flight.sim.continuous[16] == stopped_chemical_work
			and int(final_glow.get("fire_count", -1)) == stopped_fire_count
			and float(final_glow.get("chemical_power_w", NAN)) == 0.0, final_glow)
	else:
		var final_electric: Dictionary = flight.electrical_state()
		_check(label + " stopped reference remains electrically disconnected",
			not bool(final_electric.get("enabled", true))
			and float(final_electric.get("motor_current_a", NAN)) == 0.0
			and float(final_electric.get("shaft_torque_nm", NAN)) <= 0.0, final_electric)

	var plan_before_reset: Dictionary = flight._failures.plan()
	flight.reset()
	var after_reset: Dictionary = flight.failure_status()
	_check(label + " repeat reset reuses the resolved plan and clears the active cut",
		flight._failures.plan() == plan_before_reset
		and not bool(after_reset.get("active", true))
		and int(after_reset.get("airborne_ticks", -1)) == 0
		and not flight.failure_power_cut_active())
	_check(label + " reset does not emit a duplicate failure notice", change_count[0] == 1)

	replay.free()
	reference.free()
	rejected.free()
	flight.free()


func _check_active_checkpoint_guards(source: Node, restored: Node, active: Dictionary,
		label: String, kind: String) -> void:
	var before: PackedByteArray = var_to_bytes(restored.checkpoint())
	var invalid: Dictionary = active.duplicate(true)
	invalid.simulation.modes[0] = 1
	_check(label + " refuses an active-cut checkpoint with source mode enabled atomically",
		not restored.restore_checkpoint(invalid) and var_to_bytes(restored.checkpoint()) == before)
	if kind == "glow":
		for defect: String in ["running", "reason", "fuel_transport"]:
			invalid = active.duplicate(true)
			match defect:
				"running": invalid.simulation.continuous[7] = 1.0
				"reason": invalid.simulation.continuous[8] = 1.0
				"fuel_transport": invalid.simulation.continuous[5] = 0.01
			_check(label + " refuses a mismatched active glow " + defect + " snapshot atomically",
				not restored.restore_checkpoint(invalid) and var_to_bytes(restored.checkpoint()) == before)
	_check(label + " guard fixture leaves the accepted active source untouched",
		source.failure_power_cut_active() and restored.failure_power_cut_active())


func _check_wrong_profile_restore(source: Node, restored: Node, active: Dictionary,
		expected_profile: String, dt: float, label: String) -> void:
	var wrong_snapshot: Dictionary = _active_logical_snapshot(int(active.simulation.tick), dt)
	_check(label + " builds a valid active snapshot for the wrong eligibility profile",
		bool(wrong_snapshot.get("active", false))
		and int(wrong_snapshot.get("tick", -1)) == int(active.simulation.tick)
		and str(wrong_snapshot.get("plan", {}).get("eligibility_profile", "")) == FailureCatalog.LOGICAL_CONTROLS_PROFILE)
	if wrong_snapshot.is_empty():
		return
	var wrong_profile: Dictionary = active.duplicate(true)
	wrong_profile.failure_state = wrong_snapshot
	var before: PackedByteArray = var_to_bytes(restored.checkpoint())
	_check(label + " rejects a valid active checkpoint from another failure profile atomically",
		expected_profile != FailureCatalog.LOGICAL_CONTROLS_PROFILE
		and not restored.restore_checkpoint(wrong_profile)
		and var_to_bytes(restored.checkpoint()) == before)
	_check(label + " wrong-profile rejection leaves the source runtime unchanged",
		source.failure_power_cut_active())


func _active_logical_snapshot(target_tick: int, dt: float) -> Dictionary:
	var seed: int = _seed_for(FailureCatalog.LOGICAL_CONTROLS_PROFILE, "roll_jam", dt)
	if seed < 0:
		return {}
	var runtime: RefCounted = FailureRuntime.new()
	if not runtime.begin(CONFIG, seed, dt, FailureCatalog.LOGICAL_CONTROLS_PROFILE):
		return {}
	var plan: Dictionary = runtime.plan()
	if int(plan.get("onset_airborne_ticks", -1)) != 4800 or target_tick < int(plan.onset_airborne_ticks):
		return {}
	var inputs := PackedFloat64Array([0.0, 0.0, 0.0, 1.0])
	var servos := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	for tick in range(1, target_tick + 1):
		var prepared: Dictionary = runtime.prepare(inputs, servos, true)
		if not bool(prepared.get("ok", false)):
			return {}
		runtime.commit(tick)
	return runtime.snapshot()


func _test_dynamic_battery_auxiliary_budget() -> void:
	const LABEL := "dynamic electric pack source-off budget"
	var flight: Node = _new_fixture(BATTERY_FIXTURE)
	_check(LABEL + " loads a dynamic-battery electric aircraft", flight.is_flyable()
		and flight.battery_is_dynamic() and flight.shaft_is_coupled())
	if not flight.is_flyable() or not flight.battery_is_dynamic():
		flight.free()
		return
	var pack: Dictionary = flight.aircraft.model.propulsion.battery
	var charge_index: int = flight._rotor_index() + 1
	flight.sim.inputs[3] = 1.0
	_check(LABEL + " starts with source power enabled", flight.propulsion_power_enabled())
	for _tick in 12:
		flight.sim.step()
	var powered: Dictionary = flight.electrical_state()
	_check(LABEL + " begins with real motor current", powered.get("ok", false)
		and float(powered.get("motor_current_a", 0.0)) > 0.0)
	var charge_before: float = flight.sim.continuous[charge_index]
	var energy_before: float = flight.sim.continuous[charge_index + 1]
	var heat_before: float = flight.sim.continuous[charge_index + 2]
	var rpm_before: float = flight.sim.aux[Flight.AUX_RPM]
	flight.engine_running = false
	flight.sim.step()
	var rpm_after: float = flight.sim.aux[Flight.AUX_RPM]
	_check(LABEL + " manual stopped reference coasts from its prior RPM",
		rpm_after > 0.0 and absf(rpm_after - rpm_before) < maxf(1.0, rpm_before * 0.10),
		{"before": rpm_before, "after": rpm_after})
	var duration: float = 121.0 * flight.sim.dt()
	for _tick in 120:
		flight.sim.step()
	var stopped: Dictionary = flight.electrical_state()
	var auxiliary_current: float = float(pack.auxiliary_current_a)
	var expected_charge: float = charge_before - auxiliary_current * duration
	var expected_heat: float = heat_before + float(pack.resistance_ohm) * auxiliary_current * auxiliary_current * duration
	var expected_terminal_delta: float = _chemical_energy(pack, charge_before, expected_charge) \
		- float(pack.resistance_ohm) * auxiliary_current * auxiliary_current * duration
	_check(LABEL + " stops motor current and positive drive torque while retaining only auxiliary pack current",
		stopped.get("ok", false) and float(stopped.get("motor_current_a", NAN)) == 0.0
		and float(stopped.get("shaft_torque_nm", NAN)) <= 0.0
		and float(stopped.get("pack_current_a", NAN)) == auxiliary_current
		and float(stopped.get("battery_current_a", NAN)) == auxiliary_current, stopped)
	_check(LABEL + " matches independent auxiliary charge, heat and terminal-energy budgets",
		absf(flight.sim.continuous[charge_index] - expected_charge) < 2e-9
		and absf(flight.sim.continuous[charge_index + 2] - expected_heat) < 1e-11
		and absf(flight.sim.continuous[charge_index + 1] - energy_before - expected_terminal_delta) < 5e-8,
		{"charge": flight.sim.continuous[charge_index], "expected_charge": expected_charge,
			"heat": flight.sim.continuous[charge_index + 2], "expected_heat": expected_heat,
			"energy_delta": flight.sim.continuous[charge_index + 1] - energy_before,
			"expected_energy_delta": expected_terminal_delta})
	_check(LABEL + " keeps raw throttle available to the pilot", flight.sim.inputs[3] == 1.0)
	flight.free()


func _chemical_energy(pack: Dictionary, initial: float, final_charge: float) -> float:
	var curve: PackedFloat64Array = pack.ocv_points
	return curve[1] * (initial - final_charge) \
		+ (curve[3] - curve[1]) / (7200.0 * float(pack.capacity_ah)) \
		* (initial * initial - final_charge * final_charge)


func _strip_failure_wrapper(checkpoint: Dictionary) -> Dictionary:
	var physics: Dictionary = checkpoint.duplicate(true)
	if physics.get("format", "") != "openrc-flight-checkpoint v10":
		return physics
	physics.format = physics.failure_physics_format
	physics.erase("failure_physics_format")
	physics.erase("failure_state")
	return physics


func _rpm(flight: Node, kind: String) -> float:
	return float(flight.sim.continuous[0]) if kind == "glow" else float(flight.sim.aux[Flight.AUX_RPM])


func _rollback_bytes(sim: Object) -> PackedByteArray:
	var committed: Array = []
	for field: String in [
		"state", "previous", "continuous", "aux", "inputs", "modes", "last_loads",
		"tick", "stop_at_tick", "mass", "gravity", "inertia", "_inertia_inv", "_inertia_cache",
		"_last_valid_state", "_last_valid_previous", "_last_valid_continuous", "_last_valid_aux",
		"_last_valid_inputs", "_last_valid_modes", "_last_valid_loads", "_last_valid_tick",
		"_last_valid_stop", "_last_valid_mass", "_last_valid_gravity", "_last_valid_inertia",
	]:
		committed.append(sim.get(field))
	return var_to_bytes(committed)
