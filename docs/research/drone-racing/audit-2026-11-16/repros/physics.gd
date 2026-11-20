# Audit observation probe for cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b.
# Run only in an isolated checkout with the repository's checked Godot runner.
# The checks assert that the observed defect reproduces; they are not passing product tests.
extends SceneTree

const Data := preload("res://physics/multirotor_data.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const Rates := preload("res://physics/multirotor/rates.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Fixtures := preload("res://tests/mr_fixtures.gd")
const Session := preload("res://sim/multirotor/session.gd")

const DATA_PATH := "res://data/multirotors/openrc-fpv5-x1.json"
var _failures := 0
var _checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, result: bool, detail: String = "") -> void:
	_checks += 1
	if not result:
		_failures += 1
	print("%s %s %s" % ["OBSERVED" if result else "NOT OBSERVED", label, detail])


func _body(height: float) -> PackedFloat64Array:
	return RB.make_state(M.v3(0.0, 0.0, -height), M.v3(0.0, 0.0, 0.0), M.q_identity(), M.v3(0.0, 0.0, 0.0))


func _run() -> void:
	var loaded: Dictionary = Data.load_file(DATA_PATH)
	_check("shipped data loads", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not loaded.get("ok", false):
		_finish()
		return
	var made: Dictionary = Data.prepare(loaded.data, str(loaded.sha256))
	_check("shipped data prepares", bool(made.get("ok", false)), str(made.get("errors", [])))
	if not made.get("ok", false):
		_finish()
		return
	var doc: Dictionary = made.prepared
	_slope_strike(doc)
	_full_pack_regen(doc)
	_impossible_hover(loaded.data)
	_prepared_drag(doc)
	_finish()


func _finish() -> void:
	print("%d observations, %d not reproduced" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _slope_strike(doc: Dictionary) -> void:
	var made: Dictionary = Plant.create(doc, Rates.default_profile(), FC.THROTTLE_ABSOLUTE)
	if not made.get("ok", false):
		_check("slope plant prepared", false, str(made.get("errors", [])))
		return
	var p: RefCounted = made.plant
	# A planar height field h(n,e)=0.5*n, slopes supplied by the production contract.
	p.ground = func(n: float, _e: float) -> PackedFloat64Array: return PackedFloat64Array([0.5 * n, 0.5, 0.0])
	var rotor: Dictionary = doc.rotors[1] # front-right
	var hub: PackedFloat64Array = rotor.hub_frd
	var radius: float = float(rotor.diameter_m) / 2.0
	# Hub is 2 cm above local terrain; the north rim is below it.
	var cg_height: float = 0.5 * hub[0] + hub[2] + 0.020
	var body: PackedFloat64Array = _body(cg_height)
	var frame: Dictionary = p.initial_frame(body)
	for i in 4:
		frame.continuous[i] = 1000.0
	var rim_depth: float = body[RB.POS + 2] + hub[2] + 0.5 * (hub[0] + radius)
	var reason: String = p.crash_reason(body, body, frame.continuous)
	_check("level rotor intersects sloped terrain at endpoint but no strike", p.state_validator(frame, {}) and rim_depth > 0.0 and reason.is_empty(),
		"rim depth %.9f m; reason '%s'; CG height %.9f m" % [rim_depth, reason, cg_height])


func _full_pack_regen(doc: Dictionary) -> void:
	var h: Dictionary = Fixtures.install(root, doc)
	if not h.get("ok", false):
		_check("regen plant prepared", false, str(h.get("errors", [])))
		return
	var p: RefCounted = h.plant
	var sim: Node = h.sim
	var frame: Dictionary = p.initial_frame(_body(20.0), 0, 1.0)
	for i in 4:
		frame.continuous[i] = 3000.0
		frame.aux[FC.AUX_COMMAND + i] = 0.4
	frame.modes[FC.MODE_MOTOR] = FC.MOTOR_ARMED
	frame.modes[FC.MODE_PREVIOUS_ARM] = 1
	frame.modes[FC.MODE_OFF_OBSERVED] = 1
	frame.modes[FC.MODE_ARM_BLOCK] = FC.BLOCK_NONE
	var evaluation: Dictionary = p._evaluate(frame.body, frame.continuous, 0.0, frame.aux, frame.modes)
	var initial_q: float = frame.continuous[Plant.C_CHARGE]
	var dq: float = evaluation.derivative[Plant.C_CHARGE]
	var pilot: PackedFloat64Array = FC.neutral_input()
	pilot[FC.IN_ARM] = 1.0
	# At zero rate error this produces approximately 0.4 command per motor.
	pilot[FC.IN_THROTTLE] = (0.4 - 0.055) / (1.0 - 0.055)
	var message: String = Fixtures.reset(sim, frame, pilot)
	_check("full-pack armed frame is in declared domain and charges above capacity", p.state_validator(frame, {}) and message.is_empty() and dq > 0.0,
		"Q %.3f C, dQ/dt %.6f A, Vbus %.6f V, Ipack %.6f A; reset '%s'" % [initial_q, dq,
		float(evaluation.bus.get("v_bus", 0.0)), float(evaluation.bus.get("i_pack", 0.0)), message])
	if message.is_empty():
		var stepped: bool = Fixtures.run(sim, pilot, 1)
		var q_after: float = sim.continuous[Plant.C_CHARGE]
		var accepted: Dictionary = {body = sim.state, continuous = sim.continuous, aux = sim.aux, modes = sim.modes}
		var telemetry: Dictionary = p.telemetry(accepted)
		_check("one accepted tick stores over-capacity charge while SOC is clamped", stepped and q_after > initial_q and p.state_validator(accepted, {}) \
			and float(telemetry.soc) == 1.0 and float(telemetry.consumed_mah) < 0.0,
			"Q %.9f -> %.9f C; SOC %.9f; consumed %.9f mAh; fault '%s'" % [initial_q, q_after,
			float(telemetry.soc), float(telemetry.consumed_mah), sim.fault_reason])
	sim.free()


func _impossible_hover(raw: Dictionary) -> void:
	var changed: Dictionary = raw.duplicate(true)
	changed.battery.resistance.value = 10.0
	var admitted: Dictionary = Data.load_document(changed, "high pack resistance")
	if not admitted.get("ok", false):
		_check("high-resistance battery admitted despite impossible hover", false, str(admitted.get("errors", [])))
		return
	var made: Dictionary = Data.prepare(admitted.data, str(admitted.sha256))
	if not made.get("ok", false):
		_check("high-resistance battery prepares", false, str(made.get("errors", [])))
		return
	var d: Dictionary = made.prepared
	var pt: Dictionary = d.powertrain
	var kv: float = float(pt.kv_rad_s_per_v)
	var motor_resistance: float = float(pt.resistance_ohm)
	var k_t: float = float(d.rotor_law.thrust_coefficient_n_s2)
	var k_q: float = float(d.rotor_law.torque_coefficient_n_m_s2)
	var min_power := 0.0
	for thrust: Variant in raw.provenance.derived_diagnostics.hover_thrusts_n:
		var speed: float = sqrt(float(thrust) / k_t)
		var current: float = k_q * speed * speed * kv + float(pt.no_load_current_a)
		min_power += (speed / kv + motor_resistance * current) * current
	var ocv: PackedFloat64Array = d.battery.ocv_points
	var voc: float = ocv[ocv.size() - 1]
	var max_terminal_power: float = voc * voc / (4.0 * float(d.battery.resistance_ohm))
	_check("high-resistance battery admitted despite impossible hover", min_power > max_terminal_power,
		"required motor power %.6f W > ideal pack maximum %.6f W, before auxiliary load" % [min_power, max_terminal_power])


func _prepared_drag(doc: Dictionary) -> void:
	var changed: Dictionary = doc.duplicate(true)
	changed.airframe.drag_areas_m2 = PackedFloat64Array([-1.0, 0.012, 0.020])
	var s: Node = Session.new()
	root.add_child(s)
	var admitted: bool = s.prepare({}, {prepared_data = changed, start = "air", altitude_m = 20.0})
	if not admitted:
		_check("negative prepared drag is admitted", false, str(s.load_error))
		s.free()
		return
	var body: PackedFloat64Array = _body(20.0)
	body[RB.VEL] = 10.0
	var frame: Dictionary = s.plant.initial_frame(body)
	var evaluation: Dictionary = s.plant._evaluate(frame.body, frame.continuous, 0.0, frame.aux, frame.modes)
	var force_x: float = evaluation.loads[0]
	_check("negative prepared drag is admitted and accelerates a disarmed craft", force_x > 0.0,
		"u = 10 m/s, Fx = %.6f N, power = %.6f W" % [force_x, force_x * body[RB.VEL]])
	s.free()
