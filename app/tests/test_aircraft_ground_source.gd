extends SceneTree
const Source := preload("res://physics/aircraft_ground_source.gd")
const Data := preload("res://physics/aircraft_data.gd")
const Prop := preload("res://physics/propulsion.gd")
const M := preload("res://physics/math3d.gd")
var checks := 0
var failures := 0


func check(label: String, passed: bool, detail := "") -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	var loaded := Data.load_file("res://data/aircraft/synthetic_stik_electric_4s.json")
	check("existing fixed-voltage electric fixture loads", loaded.ok, str(loaded.get("errors", [])))
	if not loaded.ok:
		quit(1)
		return
	var prop: Dictionary = loaded.model.propulsion
	var axis := Prop.axis(prop)
	var kt: float = 60.0 / TAU / prop.motor.kv_rpm_per_volt
	var capacity: float = kt * prop.motor.no_load_current_a
	for rpm: float in [0.0, 500.0, 3500.0, 15000.0]:
		for duty: float in [0.0, 0.3, 1.0]:
			for enabled: bool in [false, true]:
				var inflow := M.v3(15.0, -2.0, 3.0)
				var loads := Prop.loads(inflow, rpm, prop, 1.18)
				var before := var_to_bytes([prop, loads])
				var result := Source.electric_fixed_voltage(prop, rpm, duty, enabled, loads)
				check("valid closed source torque split evaluates", result.ok, str(result))
				if not result.ok: continue
				var point := Prop.electric_source_state(rpm, duty, prop, enabled)
				check("drive uses existing electromagnetic current and friction keeps full finite capacity", result.internal_drive_torque_nm == kt * point.motor_current_a
					and result.shaft_friction_capacity_nm == capacity)
				var expected_net: float = result.internal_drive_torque_nm - (minf(capacity, result.internal_drive_torque_nm) if rpm == 0.0 else capacity)
				check("moving-side decomposition reproduces the old isolated motor torque", absf(expected_net - point.shaft_torque_nm) < 1e-13)
				var physical_q := Prop.prop_torque(rpm, M.dot(inflow, axis), prop, 1.18)
				check("shaft axial external torque agrees with the existing propeller map once", absf(M.dot(result.shaft_external_couple_body_nm, axis) + physical_q) < 1e-10)
				check("electrical input closes against copper plus electromagnetic conversion", absf(result.electrical_balance_residual_w) < 1e-10)
				check("source decomposition never mutates aircraft or external force data", before == var_to_bytes([prop, loads]))
	var stopped := Source.electric_fixed_voltage(prop, 0.0, 0.0, false, _zero())
	check("stopped unpowered shaft retains authored static friction capacity", stopped.ok and stopped.internal_drive_torque_nm == 0.0
		and stopped.shaft_friction_capacity_nm > 0.0 and not stopped.trial_extension_only)
	var trial := Source.electric_fixed_voltage(prop, -0.1, 0.0, false, _zero(), true)
	check("explicit negative algebraic extension uses zero source map without authorizing reverse", trial.ok and trial.trial_extension_only and trial.stage_map_rpm == 0.0
		and trial.accepted_spin_domain == "nonnegative_relative_shaft_rpm")
	check("negative accepted shaft speed refuses", not Source.electric_fixed_voltage(prop, -0.1, 0.0, false, _zero()).ok)
	# Include a transverse local couple and a force at a nonzero three-axis hub.
	var offset_prop := prop.duplicate(true)
	offset_prop.offset = M.v3(-0.4, 0.2, -0.1)
	var force := M.v3(3.0, -2.0, 4.0)
	var local_couple := M.v3(-0.2, 0.03, -0.07)
	var full_moment := M.add(M.cross(M.v3(0.4, 0.2, 0.1), force), local_couple)
	var full := force.duplicate()
	full.append_array(full_moment)
	var separated := Source.electric_fixed_voltage(offset_prop, 1400.0, 0.2, true, full)
	check("complete local propeller couple excludes hub force moment once", separated.ok and M.norm(M.sub(separated.shaft_external_couple_body_nm, local_couple)) < 1e-14)
	check("couple extraction does not apply a live-CG shift", separated.ok and separated.propeller_hub_body_m == M.v3(0.4, 0.2, 0.1))
	for kind: String in ["finite_pack", "missing_motor", "bad_motor", "bad_axis", "bad_offset", "not_dynamic"]:
		var bad := prop.duplicate(true)
		match kind:
			"finite_pack": bad.battery.kind = "ocv_resistance"
			"missing_motor": bad.erase("motor")
			"bad_motor": bad.motor.no_load_current_a = NAN
			"bad_axis": bad.axis = M.v3(2.0, 0.0, 0.0)
			"bad_offset": bad.offset = M.v3(0.0, NAN, 0.0)
			"not_dynamic": bad.erase("rotor_inertia")
		check("unsupported or malformed source refuses: " + kind, not Source.electric_fixed_voltage(bad, 1000.0, 0.2, true, _zero()).ok)
	for rpm: float in [NAN, INF]: check("nonfinite source RPM refuses", not Source.electric_fixed_voltage(prop, rpm, 0.2, true, _zero()).ok)
	for duty: float in [NAN, -0.1, 1.1]: check("invalid source duty refuses", not Source.electric_fixed_voltage(prop, 1000.0, duty, true, _zero()).ok)
	check("malformed supplied propeller wrench refuses", not Source.electric_fixed_voltage(prop, 1000.0, 0.2, true, PackedFloat64Array([0.0])).ok)
	print("Aircraft ground source: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _zero() -> PackedFloat64Array:
	return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
