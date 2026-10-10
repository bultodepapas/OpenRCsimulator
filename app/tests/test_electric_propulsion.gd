# EL1c: electric source dispatch, stable steady torque roots and trim on the shared propeller loads.
# Run: godot --headless --path . --script res://tests/test_electric_propulsion.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const AD := preload("res://physics/aircraft_data.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Trim := preload("res://physics/trim.gd")

const G := 9.80665
const RHO := 1.225
const THROWS := { elevator = 0.35, aileron = 0.35, rudder = 0.44 }

var _failures: int = 0
var _count: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_count += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])
	if not ok:
		_failures += 1


func _electric_prop() -> Dictionary:
	return {
		kind = "electric_prop",
		motor = { kv_rpm_per_volt = 1000.0, resistance_ohm = 0.1, no_load_current_a = 1.0 },
		battery = { kind = "fixed_voltage", voltage_v = 12.0 },
		esc = { kind = "ideal_motoring", command_mapping = "identity" },
		diameter = 0.2,
		offset = M.v3(0.0, 0.0, 0.0),
		rotor_inertia = 0.002,
		axis = M.v3(1.0, 0.0, 0.0),
		max_rpm = 12000.0, # descriptive Kv × V reference only
		ct = PackedFloat64Array([0.0, 0.12, 0.4, 0.08, 0.9, 0.02]),
		cp = PackedFloat64Array([0.0, 0.05, 1.0, 0.05]),
		cp_min = 0.0,
	}


func _initialize() -> void:
	var prop: Dictionary = _electric_prop()
	_check("electric identity is a rotor-dynamics capability, not a combustion shaft layout",
		Propulsion.source_kind(prop) == "electric_prop" and Propulsion.is_electric(prop)
		and Propulsion.has_rotor_dynamics(prop) and not Propulsion.has_shaft(prop))

	# Static, constant-Cp balance: source torque is linear in RPM and prop torque is quadratic.
	var duty: float = 0.8
	var diameter: float = float(prop.diameter)
	var kv: float = float(prop.motor.kv_rpm_per_volt)
	var resistance: float = float(prop.motor.resistance_ohm)
	var no_load_current: float = float(prop.motor.no_load_current_a)
	var kt: float = 60.0 / TAU / kv
	var cp_static: float = 0.05
	var a: float = cp_static * RHO * M.pow_(diameter, 5) / (TAU * 3600.0)
	var b: float = kt / (resistance * kv)
	var c: float = kt * (duty * float(prop.battery.voltage_v) / resistance - no_load_current)
	var expected_rpm: float = (-b + M.sqrt_(b * b + 4.0 * a * c)) / (2.0 * a)
	var operating: Dictionary = Propulsion.steady_operating_point(duty, 0.0, prop, RHO)
	_check("analytic static quadratic gives a stable equilibrium", operating.ok, str(operating))
	_check("equilibrium matches independently solved quadratic", operating.ok and absf(float(operating.rpm) - expected_rpm) < 0.01,
		"%.6f rpm vs %.6f rpm" % [float(operating.get("rpm", NAN)), expected_rpm])
	_check("equilibrium residual and restoring slopes are checked", operating.ok and absf(float(operating.residual)) < 1e-10
		and float(operating.stability_slope) < 0.0, str(operating.get("stability_slope", NAN)))
	_check("legacy float steady_rpm wrapper uses the same electric source", operating.ok
		and absf(Propulsion.steady_rpm(duty, 0.0, prop, RHO) - float(operating.rpm)) < 1e-10)

	var dense_air: Dictionary = Propulsion.steady_operating_point(duty, 0.0, prop, 1.3)
	var thin_air: Dictionary = Propulsion.steady_operating_point(duty, 0.0, prop, 0.9)
	_check("density changes propeller load and equilibrium RPM", dense_air.ok and thin_air.ok
		and float(dense_air.rpm) < float(thin_air.rpm))
	var source_at_root: Dictionary = Propulsion.electric_source_state(float(operating.rpm), duty, prop)
	_check("motor constants and source output remain independent of density", source_at_root.ok
		and absf(float(source_at_root.motor_current_a) - float(Propulsion.electric_source_state(float(operating.rpm), duty, prop).motor_current_a)) < 1e-12)

	# At high advance ratio the propeller drives the shaft above Kv × V. That reference must not be a cap.
	var windmill: Dictionary = _electric_prop()
	windmill["cp"] = PackedFloat64Array([0.0, 0.07, 0.4, 0.05, 0.6, -0.03, 1.0, -0.1])
	var overspeed: Dictionary = Propulsion.steady_operating_point(1.0, 30.0, windmill, RHO)
	var overspeed_source: Dictionary = Propulsion.electric_source_state(float(overspeed.get("rpm", NAN)), 1.0, windmill) if overspeed.ok else {}
	_check("windmilling prop can establish a stable root above Kv × V", overspeed.ok
		and float(overspeed.rpm) > float(windmill.max_rpm)
		and float(overspeed_source.get("motor_current_a", NAN)) == 0.0,
		"status=%s rpm=%s reference=%s" % [overspeed.status, String.num_scientific(float(overspeed.get("rpm", NAN))), windmill.max_rpm])

	var no_root: Dictionary = Propulsion.steady_operating_point(0.0, 0.0, prop, RHO)
	_check("unbracketed zero-duty static case fails explicitly", not no_root.ok and no_root.status == "unbracketed", str(no_root.get("message", "")))
	var cutoff_duty: float = (resistance * (no_load_current + Propulsion.prop_torque(1.0, 0.0, prop, RHO) / kt) + 1.0 / kv) / float(prop.battery.voltage_v)
	var cutoff: Dictionary = Propulsion.steady_operating_point(cutoff_duty, 0.0, prop, RHO)
	_check("stopped-prop cutoff zero is not reported as a steady root", not cutoff.ok and cutoff.status == "stopped_cutoff", str(cutoff.get("message", "")))
	var unstable_prop: Dictionary = _electric_prop()
	unstable_prop["cp"] = PackedFloat64Array([0.0, -0.05, 1.0, -0.05])
	unstable_prop["cp_min"] = -0.05
	var unstable: Dictionary = Propulsion.steady_operating_point(0.0, 0.0, unstable_prop, RHO)
	_check("mathematical negative-Cp control detects an unstable-only root", not unstable.ok and unstable.status == "unstable", str(unstable.get("message", "")))

	var invalid_rpm: Dictionary = Propulsion.electric_source_state(-1.0, duty, prop)
	var invalid_duty: Dictionary = Propulsion.electric_source_state(1000.0, 1.1, prop)
	_check("pure source rejects negative RPM and invalid duty", not invalid_rpm.ok and not invalid_duty.ok)
	_check("steady solver reports invalid duty as an input failure", not Propulsion.steady_operating_point(1.1, 0.0, prop, RHO).ok
		and Propulsion.steady_operating_point(1.1, 0.0, prop, RHO).status == "invalid")

	var coast: Dictionary = Propulsion.electric_source_state(1000.0, 1.0, prop, false)
	var coast_rate: float = Propulsion.shaft_rate(1000.0, 1.0, 0.0, prop, RHO, 1.0, false)
	var coast_expected: float = (-kt * no_load_current - Propulsion.prop_torque(1000.0, 0.0, prop, RHO)) \
		/ float(prop.rotor_inertia) * 60.0 / TAU
	_check("source-off coasts with motor loss, no current or combustion friction", coast.ok
		and coast.motor_current_a == 0.0 and coast.shaft_torque_nm < 0.0
		and absf(coast_rate - coast_expected) < 1e-12, "%s rpm/s" % String.num_scientific(coast_rate))
	_check("electric coast below prop cutoff still approaches the physical rest boundary", Propulsion.shaft_rate(0.5, 0.0, 0.0, prop, RHO, 1.0, false) < 0.0)
	var rest: Dictionary = Propulsion.electric_source_state(0.0, 0.0, prop, false)
	_check("source-off at exact rest does not initiate reverse rotation", rest.ok and rest.shaft_torque_nm == 0.0)
	_check("motor can provide breakaway torque at rest", Propulsion.shaft_rate(0.0, 1.0, 0.0, prop, RHO) > 0.0)
	_check("electric torque dispatch does not require shaft.power_curve",
		absf(Propulsion.engine_torque(float(operating.rpm), duty, prop) - float(source_at_root.shaft_torque_nm)) < 1e-12)

	# Keep the Stik's existing airframe/aerodynamics while substituting only the synthetic EL1c source/prop block.
	var loaded: Dictionary = AD.load_file("res://data/aircraft/jensen_ugly_stik_60.json").model
	var model: Dictionary = loaded.duplicate(true)
	var trim_prop: Dictionary = _electric_prop()
	trim_prop["rotor_inertia"] = 0.001
	model["propulsion"] = trim_prop
	var trim: Dictionary = Trim.solve("level", 15.0, model, G, THROWS, RHO)
	_check("powered electric in-air trim uses the same stable source equilibrium", trim.ok, trim.message)
	_check("electric trim reports an in-range duty, positive RPM and small residual", trim.ok
		and float(trim.throttle) >= 0.0 and float(trim.throttle) <= 1.0 and float(trim.rpm) > 0.0
		and float(trim.residual) < 1e-8, "duty=%.4f rpm=%.2f residual=%s" % [float(trim.get("throttle", NAN)), float(trim.get("rpm", NAN)), String.num_scientific(float(trim.get("residual", NAN)))])

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
