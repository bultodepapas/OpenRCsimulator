extends SceneTree

const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const Trim := preload("res://physics/trim.gd")

const SPEED := 15.0
const RHO := 1.225
const STEPS := [0.1, 0.05, 0.025, 0.0125, 0.00625, 0.003125, 0.0015625, 0.00078125]

func _initialize() -> void:
	var loaded: Dictionary = AircraftData.load_file(Scenarios.AIRCRAFT)
	if not loaded.get("ok", false):
		push_error("Stik load failed: %s" % str(loaded.get("errors", [])))
		quit(1)
		return
	var model: Dictionary = loaded.model
	var trim: Dictionary = Trim.solve("level", SPEED, model, 9.80665, model.controls.throw_rad)
	if not trim.get("ok", false):
		push_error("15 m/s trim failed: %s" % str(trim))
		quit(1)
		return
	var alpha: float = trim.alpha
	var S: float = model.reference.S
	var b: float = model.reference.b
	var c: float = model.reference.c
	var qbar := 0.5 * RHO * SPEED * SPEED
	var controls := { elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0 }
	var transfer_x: float = -(float(model.reference.arp_le[0]) - float(model.cg_le[0]))
	var transfer_z: float = -(float(model.reference.arp_le[2]) - float(model.cg_le[2]))
	var transfer_cnr: float = float(model.aero.CYr) * transfer_x / b
	print("trim_speed_mps=%.9f alpha_deg=%.9f rho=%.9f" % [SPEED, rad_to_deg(alpha), RHO])
	print("h_rad,Cmq_CG,CLq,Cnr_CG,Cmq_ARP,Cnr_ARP,default_equals_explicit_wake")
	for h in STEPS:
		var q_plus := _loads(model, controls, _state(alpha, 1, h))
		var q_minus := _loads(model, controls, _state(alpha, 1, -h))
		var qbar_pitch := qbar * S * c * c / (2.0 * SPEED)
		var qbar_lift := qbar * S * c / (2.0 * SPEED)
		var cmq_cg: float = (q_plus.default[4] - q_minus.default[4]) / (2.0 * h) / qbar_pitch
		var clq: float = (_lift(q_plus.default, alpha) - _lift(q_minus.default, alpha)) / (2.0 * h) / qbar_lift
		var r_plus := _loads(model, controls, _state(alpha, 2, h))
		var r_minus := _loads(model, controls, _state(alpha, 2, -h))
		var qbar_yaw := qbar * S * b * b / (2.0 * SPEED)
		var cnr_cg: float = (r_plus.default[5] - r_minus.default[5]) / (2.0 * h) / qbar_yaw
		var cmq_arp := cmq_cg - clq * (transfer_x * cos(alpha) + transfer_z * sin(alpha)) / c
		var cnr_arp := cnr_cg - transfer_cnr
		var equal: bool = q_plus.equal and q_minus.equal and r_plus.equal and r_minus.equal
		print(",".join([String.num(h, 9), String.num(cmq_cg, 12), String.num(clq, 12),
			String.num(cnr_cg, 12), String.num(cmq_arp, 12), String.num(cnr_arp, 12), str(equal)]))
	quit(0)


func _loads(model: Dictionary, controls: Dictionary, s: PackedFloat64Array) -> Dictionary:
	var air: Dictionary = Air.compute(s, PackedFloat64Array([0.0, 0.0, 0.0]), RHO)
	var default_loads: PackedFloat64Array = Aero._local_loads(s, air, controls, model, RHO)
	var settled_wake: float = Aero.wing_wake_velocity(s, air, controls, model)
	var explicit_loads: PackedFloat64Array = Aero._local_loads(s, air, controls, model, RHO, settled_wake)
	return { default = default_loads, equal = default_loads.to_byte_array() == explicit_loads.to_byte_array() }


func _state(alpha: float, axis: int, rate: float) -> PackedFloat64Array:
	var s := PackedFloat64Array([0.0, 0.0, -100.0, SPEED * cos(alpha), 0.0, SPEED * sin(alpha), 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	s[10 + axis] = rate
	return s


func _lift(loads: PackedFloat64Array, alpha: float) -> float:
	return loads[0] * sin(alpha) - loads[2] * cos(alpha)
