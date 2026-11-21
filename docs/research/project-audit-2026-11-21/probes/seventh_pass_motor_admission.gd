# R7: admitted custom motor response versus the production 240-Hz plant policy.
# This witness changes only a new custom file's motor resistance/provenance. The
# stock document remains untouched. Forced pieces are diagnostic plant refinement;
# the controller still samples once per 240-Hz tick. No proposed runtime fix.
extends SceneTree
const MD := preload("res://physics/multirotor_data.gd")
const Session := preload("res://sim/multirotor/session.gd")
const Fixtures := preload("res://tests/mr_fixtures.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const DT := 1.0 / 240.0
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("ok " if ok else "FAIL ") + label)

func _run() -> void:
	var path := "res://r7_custom_motor.json"
	var rows := {}
	for name: String in ["stock", "custom"]:
		rows[name] = {}
		for pieces: int in [0, 4, 8, 16]:
			rows[name][pieces] = _case(name, Session.DEFAULT_DATA if name == "stock" else path, pieces)
		var d8: float = _difference(rows[name][4].omega, rows[name][8].omega)
		var d16: float = _difference(rows[name][8].omega, rows[name][16].omega)
		print("R7_MOTOR_REFINEMENT " + JSON.stringify({name = name, omega_delta_4_8 = d8, omega_delta_8_16 = d16}))
		_check(name + " refined arming endpoints converge with the same two controller samples", d16 < d8 and d16 < 0.05
			and rows[name][4].candidate_commands == rows[name][8].candidate_commands
			and rows[name][8].candidate_commands == rows[name][16].candidate_commands
			and rows[name][0].before_frame_hex_sha256 == rows[name][16].before_frame_hex_sha256)
	print("R7 motor admission: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func _difference(a: Array, b: Array) -> float:
	var result := 0.0
	for i in 4:
		result = maxf(result, absf(float(a[i]) - float(b[i])))
	return result

func _case(name: String, path: String, pieces: int) -> Dictionary:
	var loaded: Dictionary = MD.load_file(path)
	_check(name + " full raw-file loader admits", loaded.ok and loaded.errors.is_empty())
	var s: Node = Session.new()
	root.add_child(s)
	var admitted: bool = s.prepare({}, {data_path = path, initial_soc = 0.5})
	_check(name + " normal pad session prepares", admitted)
	if not admitted:
		print(s.load_error)
		s.free()
		return {omega = [0.0, 0.0, 0.0, 0.0]}
	var row := {name = name, forced_plant_pieces = pieces, loader_ok = loaded.ok, loader_errors = Array(loaded.errors),
		data_sha256 = loaded.sha256, prepared = admitted, resistance_ohm = s.data.powertrain.resistance_ohm,
		parked_pieces = s.plant.parked_pieces, fixed_hz = 240, initial_soc = 0.5, start = "pad", native_execution = false}
	_check(name + " resumes and accepts OFF", s.resume() and s.tick_once(Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0, FC.FLIGHT_ANGLE)))
	if pieces > 0:
		s.sim.model.substeps = func(_b: PackedFloat64Array, _c: PackedFloat64Array, _t: float) -> int: return pieces
	var before: PackedByteArray = var_to_bytes(s.plant_frame())
	row.before_frame_hex_sha256 = before.hex_encode().sha256_text()
	var sampled: Dictionary = s.plant.sample_tick(s.plant_frame(), Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1, FC.FLIGHT_ANGLE),
		{tick = s.sim.tick, time_s = s.sim.time(), dt = DT})
	row.candidate_commands = Array(sampled.aux.slice(FC.AUX_COMMAND, FC.AUX_COMMAND + 4))
	var tape: PackedFloat64Array = s.tape()
	row.accepted_arm_tick = s.tick_once(Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1, FC.FLIGHT_ANGLE))
	row.tick = s.sim.tick
	row.fault = s.fault_reason
	row.crash = s.crash
	row.motor_state = s.sim.modes[FC.MODE_MOTOR]
	row.controller_samples = s.sim.modes[FC.MODE_SAMPLES]
	row.omega = Array(s.sim.continuous.slice(0, 4))
	row.body = Array(s.sim.state)
	row.charge_c = s.sim.continuous[s.plant.C_CHARGE]
	row.commands = Array(s.sim.aux.slice(FC.AUX_COMMAND, FC.AUX_COMMAND + 4))
	row.rollback_preserved = before == var_to_bytes(s.plant_frame()) and tape == s.tape()
	if name == "custom" and pieces == 0:
		_check("custom production policy refuses arm without committing a broken frame", not row.accepted_arm_tick
			and row.tick == 1 and row.motor_state == FC.MOTOR_DISARMED and row.rollback_preserved
			and "RK joint stage evaluation is nonfinite or malformed" in row.fault)
	else:
		_check(name + " arm accepts with one control sample per tick", row.accepted_arm_tick and row.tick == 2
			and row.motor_state == FC.MOTOR_ARMED and row.controller_samples == 2 and row.fault.is_empty())
	print("R7_MOTOR_ADMISSION " + JSON.stringify(row))
	if pieces == 0:
		_differential_mode(s, name)
	s.free()
	return row

# Separate local derivative diagnostic: perturb a same-spin pair oppositely, so
# its first-order common-bus voltage and axial reaction contributions cancel.
# This is not the exact trajectory of the zero-speed pad-arming witness above.
func _differential_mode(s: Node, name: String) -> void:
	var frame: Dictionary = s.plant.initial_frame(Fixtures.body(20.0), 0, 0.5)
	var w := 929.268985
	for i in 4:
		frame.continuous[i] = w
		frame.aux[FC.AUX_COMMAND + i] = 0.3
	frame.modes[FC.MODE_MOTOR] = FC.MOTOR_ARMED
	var epsilon := 0.001
	frame.continuous[1] += epsilon
	frame.continuous[2] -= epsilon
	var ev: Dictionary = s.plant._evaluate(frame.body, frame.continuous, 0.0, frame.aux, frame.modes)
	var measured: float = (ev.derivative[1] - ev.derivative[2]) / (2.0 * epsilon)
	var kv: float = s.data.powertrain.kv_rad_s_per_v
	var r: float = s.data.powertrain.resistance_ohm
	var j: float = s.data.rotors[1].inertia_kg_m2
	var kq: float = s.data.rotor_law.torque_coefficient_n_m_s2
	var expected := -(1.0 / (r * kv * kv) + 2.0 * kq * w) / j
	_check(name + " differential mode matches independent motor/drag derivative", ev.bus.ok and ev.bus.i_motor[0] > 0.0 and ev.bus.i_motor[1] > 0.0
		and ev.bus.i_motor[2] > 0.0 and ev.bus.i_motor[3] > 0.0 and absf(measured - expected) < 1.0e-5)
	print("R7_MOTOR_MODE " + JSON.stringify({name = name, omega_rad_s = w, epsilon_rad_s = epsilon,
		kv_rad_s_per_v = kv, motor_resistance_ohm = r, rotor_inertia_kg_m2 = j, kq_n_m_s2 = kq,
		measured_lambda_s_inv = measured, expected_lambda_s_inv = expected, h_lambda = DT * expected,
		duty = 0.3, motor_current_a = Array(ev.bus.i_motor), bus_voltage_v = ev.bus.v_bus,
		body_rates = Array(frame.body.slice(RB.RATE, RB.RATE + 3)), spin_pair = [s.data.rotors[1].spin, s.data.rotors[2].spin]}))
