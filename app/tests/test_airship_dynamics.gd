# BL-02..BL-05: airship reader and coupled stage law against analytical fixtures (no delivered mesh needed).
# Known answers: Lamb spheroid coefficients, ideal-sphere thrust a = F/(m + rho V / 2), heave with added mass,
# zero-added-mass reduction to the kernel rigid body, datum-shift invariance under rotation, neutral drift with a
# steady wind, drag dissipation and hydrostatic restoring. Software checks only; not physical validation.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Data := preload("res://physics/airship/airship_data.gd")
const Dynamics := preload("res://physics/airship/airship_dynamics.gd")
const RK := preload("res://physics/integrator.gd")

const RHO := 1.225
const G := 9.80665

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


static func q(value: Variant, unit: String) -> Dictionary:
	return {value = value, unit = unit, kind = "design", source = "analytical test fixture"}


## Spheroid hull of length L and diameter D centred on O (offset shifts every authored position by -shift).
static func fixture(length: float, diameter: float, opts := {}) -> Dictionary:
	var shift: PackedFloat64Array = opts.get("shift", PackedFloat64Array([0.0, 0.0, 0.0]))
	var drag: bool = opts.get("drag", false)
	var fins_on: bool = opts.get("fins", false)
	var hull_scale: float = opts.get("hull_scale", 1.0)
	var fin_am: float = opts.get("fin_am", 1.0)
	var cg_z: float = opts.get("cg_z", 0.0)
	var p := func(x: float, y: float, z: float) -> Array: return [x - shift[0], y - shift[1], z - shift[2]]
	var a := 0.5 * length
	var b := 0.5 * diameter
	var profile: Array = []
	for i in 41:
		var x := a - length * float(i) / 40.0
		var f := 1.0 - (x / a) * (x / a)
		profile.append([x - shift[0], b * sqrt(maxf(f, 0.0))])
	var fins: Array = []
	for fin_id: String in ["dorsal", "port", "starboard"]:
		var normal: Array = [0.0, 1.0, 0.0] if fin_id == "dorsal" else [0.0, 0.0, 1.0]
		var span_dir: Array = [0.0, 0.0, -1.0] if fin_id == "dorsal" else ([0.0, -1.0, 0.0] if fin_id == "port" else [0.0, 1.0, 0.0])
		var centroid: Array = p.call(-0.4 * length, 0.0, -0.7 * b) if fin_id == "dorsal" else \
			p.call(-0.4 * length, -0.7 * b if fin_id == "port" else 0.7 * b, 0.0)
		fins.append({id = fin_id, area_fixed = q(0.06 if fins_on else 0.0, "m^2"), area_moving = q(0.04 if fins_on else 0.0, "m^2"),
			centroid = q(centroid, "m"), normal = q(normal, "1"), span_dir = q(span_dir, "1"), span = q(0.3, "m"),
			mean_chord = q(0.33, "m"), te_sign = q(1.0, "1"), travel = q(20.0, "deg"), servo_response_time = q(0.04, "s"),
			servo_max_rate = q(360.0, "deg/s"), lift_slope_scale = q(1.0, "1"), skin_drag_coefficient = q(0.01 if drag else 0.0, "1"),
			crossflow_drag_coefficient = q(1.2 if fins_on else 0.0, "1")})
	var rotors: Array = []
	var rotor_specs := {port = [[0.0, -0.6, 0.0], [1.0, 0.0, 0.0], "port", -1.0], starboard = [[0.0, 0.6, 0.0], [1.0, 0.0, 0.0], "starboard", 1.0],
		stern_axial = [[-0.45 * length, 0.0, 0.0], [1.0, 0.0, 0.0], "stern", 1.0], stern_lateral = [[-0.45 * length, 0.0, 0.0], [0.0, 1.0, 0.0], "", 1.0]}
	for rotor_id: String in rotor_specs:
		var spec: Array = rotor_specs[rotor_id]
		rotors.append({id = rotor_id, vector = spec[2], hub = q(p.call(spec[0][0], spec[0][1], spec[0][2]), "m"), thrust_axis_rest = q(spec[1], "1"),
			radius = q(0.09, "m"), rotation_sense = q(spec[3], "1"), static_thrust_max = q(2.0, "N"), pitch_speed = q(100.0 if not drag else 12.0, "m/s"),
			reverse_efficiency = q(0.7 if rotor_id == "stern_lateral" else 0.0, "1"), torque_ratio = q(float(opts.get("torque", 0.0)), "m"), max_shaft_power = q(25.0, "W"),
			motor_efficiency = q(0.75, "1"), response_time = q(0.15, "s")})
	var vectors: Array = []
	for vector_id: String in ["port", "starboard", "stern"]:
		var pivot: Array = [0.0, -0.6, 0.0] if vector_id == "port" else ([0.0, 0.6, 0.0] if vector_id == "starboard" else [-0.45 * length, 0.0, 0.0])
		# Side axis +y tilts thrust up at +90 deg; stern axis -y tilts it down (tail down, nose up on back stick).
		vectors.append({id = vector_id, pivot = q(p.call(pivot[0], pivot[1], pivot[2]), "m"), axis = q([0.0, -1.0 if vector_id == "stern" else 1.0, 0.0], "1"),
			travel = q([0.0, 120.0 if vector_id != "stern" else 90.0], "deg"), servo_response_time = q(0.08, "s"), servo_max_rate = q(120.0, "deg/s")})
	return {
		format = Data.FORMAT, id = "fixture", name = "Analytical spheroid", status = "experimental",
		envelope = {length = q(length, "m"), max_diameter = q(diameter, "m"), volume = q(PI * length * diameter * diameter / 6.0, "m^3"),
			centroid = q(p.call(0.0, 0.0, 0.0), "m"), surface_area = q(0.8 * PI * length * diameter, "m^2"), areal_mass = q(0.1, "kg/m^2"),
			radius_profile = q(profile, "m")},
		gas = {density = q(0.169, "kg/m^3"), fill_fraction = q(1.0, "1")},
		hull_aero = {axial_drag_coefficient = q(0.03 if drag else 0.0, "1"), crossflow_drag_coefficient = q(1.2 if drag else 0.0, "1"),
			crossflow_efficiency = q(0.6, "1"), linear_damping_force = q([0.0, 0.0, 0.0], "N*s/m"), linear_damping_moment = q([0.0, 0.0, 0.0], "N*m*s")},
		added_mass = {fin_normal_coefficient = q(fin_am, "1"), hull_scale = q(hull_scale, "1")},
		fins = fins,
		gondola = {min = q(p.call(-0.3, -0.1, 0.5 * b), "m"), max = q(p.call(0.3, 0.1, 0.5 * b + 0.15), "m"), drag_coefficient = q(0.6 if drag else 0.0, "1")},
		vectors = vectors, rotors = rotors,
		battery = {cells = q(3, "1"), capacity = q(2.2, "A*h"), internal_resistance = q(0.045, "ohm"), reference_voltage = q(12.0, "V"),
			cutoff_cell_voltage = q(3.2, "V"), cutoff_band = q(0.6, "V"), initial_soc = q(1.0, "1"),
			cell_ocv = q([[0.0, 3.3], [0.1, 3.6], [0.5, 3.82], [1.0, 4.2]], "V")},
		masses = [{id = "gondola", mass = q(0.4, "kg"), position = q(p.call(0.0, 0.0, cg_z), "m")}],
		ballast = {position = q(p.call(0.0, 0.0, cg_z), "m"), max_mass = q(20.0, "kg"), default_heaviness = q(0.0, "kg")},
		contacts = {gear = [{id = "front", point = q(p.call(0.3, 0.0, b + 0.2), "m"), stiffness = q(400.0, "N/m"), damping = q(25.0, "N*s/m"),
			mu_roll = q(0.05, "1"), mu_side = q(0.6, "1")}],
			hull_points = q([p.call(a, 0.0, 0.0), p.call(-a, 0.0, 0.0), p.call(0.0, 0.0, b)], "m"),
			prop_points = q([p.call(0.0, 0.6, 0.1)], "m"), hull_stiffness = q(150.0, "N/m"), hull_damping = q(15.0, "N*s/m"),
			hull_mu = q(0.5, "1"), impact_speed_limit = q(1.5, "m/s")},
		mixer = {differential_thrust = q(0.35, "1"), stern_axial_share = q(0.6, "1"), stern_vector_on_pitch = q(1.0, "1"),
			vector_on_pitch = q(1.0, "1"), lateral_on_yaw = q(1.0, "1")},
	}


func _model(raw: Dictionary, heaviness := 0.0) -> Dictionary:
	var parsed := Data.parse(raw)
	if not parsed.ok:
		_check("fixture parses", false, "; ".join(parsed.errors))
		return {}
	var derived := Data.derive(parsed.data, RHO, G, heaviness)
	if not derived.ok:
		_check("fixture derives", false, "; ".join(derived.errors))
		return {}
	return derived.model


static func _body(v := PackedFloat64Array([0.0, 0.0, 0.0]), w := PackedFloat64Array([0.0, 0.0, 0.0]), att := PackedFloat64Array([1.0, 0.0, 0.0, 0.0])) -> PackedFloat64Array:
	return RB.make_state(M.v3(0.0, 0.0, -20.0), v, att, w)


static func _cont(motors := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])) -> PackedFloat64Array:
	var c := PackedFloat64Array()
	c.resize(Data.CONTINUOUS_SIZE)
	for i in 4:
		c[Data.MOTOR + i] = motors[i]
	c[Data.SOC] = 1.0
	return c


static func _zero_inputs() -> PackedFloat64Array:
	return PackedFloat64Array([0.0, 0.0, 0.0, 0.0])


static func _calm() -> PackedFloat64Array:
	return PackedFloat64Array([0.0, 0.0, 0.0])


func _initialize() -> void:
	_lamb_coefficients()
	_rejections()
	_sphere_thrust()
	_heave_added_mass()
	_rigid_reduction()
	_datum_shift()
	_steady_wind_drift()
	_drag_dissipation()
	_restoring()
	_mixer_signs()
	_discriminating()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _lamb_coefficients() -> void:
	# Lamb (Hydrodynamics §373) / Munk tabulation for prolate spheroids.
	var table := [[4.0, 0.082, 0.860, 0.608], [5.0, 0.059, 0.895, 0.701], [6.0, 0.045, 0.918, 0.764]]
	for row: Array in table:
		var c := Data.spheroid_coefficients(row[0], 1.0)
		_check("Lamb k1/k2/k' at L/D %d" % int(row[0]), absf(c.k1 - row[1]) < 0.002 and absf(c.k2 - row[2]) < 0.003 and absf(c.k_rot - row[3]) < 0.004,
			"%.4f %.4f %.4f" % [c.k1, c.k2, c.k_rot])
	var sphere := Data.spheroid_coefficients(1.0, 0.9999)
	_check("near-sphere limit k1 = k2 = 1/2", absf(sphere.k1 - 0.5) < 1e-3 and absf(sphere.k2 - 0.5) < 1e-3, "%.5f %.5f" % [sphere.k1, sphere.k2])


func _rejections() -> void:
	var good := fixture(5.0, 1.0)
	_check("fixture is admitted", Data.parse(good).ok, "; ".join(Data.parse(good).errors))
	var bad_unit := fixture(5.0, 1.0)
	bad_unit.envelope.volume.unit = "l"
	_check("wrong unit is refused", not Data.parse(bad_unit).ok)
	var no_source := fixture(5.0, 1.0)
	no_source.gas.density.source = " "
	_check("missing source is refused", not Data.parse(no_source).ok)
	var bad_normal := fixture(5.0, 1.0)
	bad_normal.fins[0].normal.value = [0.0, 2.0, 0.0]
	_check("non-unit fin normal is refused", not Data.parse(bad_normal).ok)
	var missing := fixture(5.0, 1.0)
	missing.rotors.pop_back()
	_check("missing rotor is refused", not Data.parse(missing).ok)
	var nan := fixture(5.0, 1.0)
	nan.masses[0].mass.value = NAN
	_check("nonfinite mass is refused", not Data.parse(nan).ok)
	var parsed := Data.parse(good)
	_check("atmosphere outside the domain is refused", not Data.derive(parsed.data, 3.0, G, 0.0).ok)


func _sphere_thrust() -> void:
	# Near-sphere, neutral, no drag: two symmetric side thrusters F = 2 T0 give a = F / (m + m_A), m_A ~ rho V / 2.
	var model := _model(fixture(2.0, 1.9998))
	if model.is_empty(): return
	var r := Dynamics.evaluate(model, _body(), _cont(PackedFloat64Array([1.0, 1.0, 0.0, 0.0])), _zero_inputs(), _calm(), Callable(), true)
	var volume: float = model.envelope.volume
	var expected := 4.0 / (float(model.mass) + float(model.m_a[0]))
	var lamb := 4.0 / (float(model.mass) + 0.5 * RHO * volume)
	var a: PackedFloat64Array = r.body_derivative
	_check("sphere surge a = F/(m + m_A)", absf(a[3] - expected) < 1e-9, "a=%.6f expected=%.6f" % [a[3], expected])
	_check("sphere added mass is rho V / 2 (oracle)", absf(a[3] - lamb) / lamb < 2e-3, "a=%.6f lamb=%.6f" % [a[3], lamb])
	_check("no spurious heave or rotation", absf(a[5]) < 1e-9 and absf(a[10]) < 1e-9 and absf(a[11]) < 1e-9 and absf(a[12]) < 1e-9)


func _heave_added_mass() -> void:
	var model := _model(fixture(5.0, 1.0, {cg_z = 0.2}), 0.1)
	if model.is_empty(): return
	_check("weigh-off achieves the requested heaviness", absf(float(model.heaviness_kg) - 0.1) < 1e-12, str(model.heaviness_kg))
	var r := Dynamics.evaluate(model, _body(), _cont(), _zero_inputs(), _calm(), Callable(), false)
	var expected := 0.1 * G / (float(model.mass) + float(model.m_a[14]))
	_check("heave a = (W - B)/(m + m_A33)", absf(r.body_derivative[5] - expected) < 1e-9, "%.6f vs %.6f" % [r.body_derivative[5], expected])
	var neutral := _model(fixture(5.0, 1.0, {cg_z = 0.2}), 0.0)
	var n := Dynamics.evaluate(neutral, _body(), _cont(), _zero_inputs(), _calm(), Callable(), false)
	_check("neutral, level, still: no acceleration", absf(n.body_derivative[5]) < 1e-12 and absf(n.body_derivative[11]) < 1e-12)


func _rigid_reduction() -> void:
	# Without added mass and with CG = CB = O the law must equal the kernel rigid body for the same loads.
	var model := _model(fixture(5.0, 1.0, {hull_scale = 0.0, fin_am = 0.0, drag = true, fins = true}), 0.05)
	if model.is_empty(): return
	var body := _body(M.v3(2.0, 0.3, -0.2), M.v3(0.1, -0.2, 0.15), M.q_normalized(M.quat(0.98, 0.05, 0.1, -0.12)))
	var r := Dynamics.evaluate(model, body, _cont(PackedFloat64Array([0.6, 0.4, 0.5, 0.2])), _zero_inputs(), _calm(), Callable(), false)
	var cg: PackedFloat64Array = model.cg
	var j: PackedFloat64Array = model.inertia
	var l: PackedFloat64Array = r.loads
	var reference := RB.derivative(body, model.mass, j, RB.inertia_inverse(j), M.v3(l[0], l[1], l[2]), M.v3(l[3], l[4], l[5]), G)
	var worst := 0.0
	for i in 13:
		worst = maxf(worst, absf(reference[i] - r.body_derivative[i]))
	_check("zero added mass, CG at O: equals RigidBody.derivative", worst < 1e-10 and M.norm(cg) < 1e-12, "max diff %s" % worst)


func _datum_shift() -> void:
	# The same physical vehicle described about O and about O' = O + d, rotating and moving: identical kinetic
	# energy, identical angular acceleration and v_dot' = v_dot + omega_dot x d (d fixed in the body).
	var d := PackedFloat64Array([0.7, -0.2, 0.3])
	var a_model := _model(fixture(5.0, 1.0, {cg_z = 0.25, fins = true}), 0.08)
	var b_model := _model(fixture(5.0, 1.0, {cg_z = 0.25, fins = true, shift = d}), 0.08)
	if a_model.is_empty() or b_model.is_empty(): return
	var w := M.v3(0.15, -0.25, 0.3)
	var v_a := M.v3(1.2, -0.4, 0.25)
	var v_b := M.add(v_a, M.cross(w, d))
	var att := M.q_normalized(M.quat(0.97, 0.1, -0.08, 0.2))
	var body_a := _body(v_a, w, att)
	var body_b := _body(v_b, w, att)
	var cont := _cont()
	var ea := Dynamics.kinetic_energy(a_model, body_a)
	var eb := Dynamics.kinetic_energy(b_model, body_b)
	_check("datum shift preserves kinetic energy", absf(ea - eb) < 1e-10 * maxf(ea, 1.0), "%.12f vs %.12f" % [ea, eb])
	var ra := Dynamics.evaluate(a_model, body_a, cont, _zero_inputs(), _calm(), Callable(), false)
	var rb := Dynamics.evaluate(b_model, body_b, cont, _zero_inputs(), _calm(), Callable(), false)
	var wd_a := M.v3(ra.body_derivative[10], ra.body_derivative[11], ra.body_derivative[12])
	var wd_b := M.v3(rb.body_derivative[10], rb.body_derivative[11], rb.body_derivative[12])
	var vd_a := M.v3(ra.body_derivative[3], ra.body_derivative[4], ra.body_derivative[5])
	var vd_b := M.v3(rb.body_derivative[3], rb.body_derivative[4], rb.body_derivative[5])
	var predicted := M.add(vd_a, M.cross(wd_a, d))
	_check("datum shift: same angular acceleration", M.norm(M.sub(wd_a, wd_b)) < 1e-9, str(M.norm(M.sub(wd_a, wd_b))))
	_check("datum shift: v_dot' = v_dot + omega_dot x d", M.norm(M.sub(predicted, vd_b)) < 1e-9, str(M.norm(M.sub(predicted, vd_b))))


func _integrate(model: Dictionary, body: PackedFloat64Array, cont: PackedFloat64Array, wind: PackedFloat64Array, seconds: float,
		inputs := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])) -> PackedFloat64Array:
	var dt := 1.0 / 240.0
	var state := body.duplicate()
	state.append_array(cont)
	var f := func(s: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		var r := Dynamics.evaluate(model, s.slice(0, 13), s.slice(13), inputs, wind, Callable(), false)
		var out: PackedFloat64Array = r.body_derivative
		out.append_array(r.derivative)
		return out
	for i in int(seconds * 240.0):
		state = RK.rk4_step_at(state, i * dt, dt, f, f.call(state, i * dt))
	return state


func _steady_wind_drift() -> void:
	# Neutral blimp released at rest relative to a steady 2 m/s wind: zero air-relative velocity persists and the
	# ground velocity equals the wind (no invented "wind push" beyond the modelled airflow forces).
	var model := _model(fixture(5.0, 1.0, {cg_z = 0.2, drag = true, fins = true}), 0.0)
	if model.is_empty(): return
	var wind := M.v3(0.0, 2.0, 0.0)
	var end := _integrate(model, _body(wind), _cont(), wind, 5.0)
	var v_ned := M.q_rotate(end.slice(6, 10), end.slice(3, 6))
	_check("drifts with the wind", absf(v_ned[1] - 2.0) < 1e-9 and absf(v_ned[0]) < 1e-9, str(v_ned))
	# Released at rest over the ground in the same wind: it accelerates toward the wind speed, not beyond it.
	var accel := _integrate(model, _body(), _cont(), wind, 20.0)
	var v2 := M.q_rotate(accel.slice(6, 10), accel.slice(3, 6))
	_check("crosswind accelerates the hull toward, not past, the wind", v2[1] > 0.5 and v2[1] < 2.0 + 1e-6, str(v2))


func _drag_dissipation() -> void:
	var model := _model(fixture(5.0, 1.0, {cg_z = 0.2, drag = true, fins = true}), 0.0)
	if model.is_empty(): return
	var state := _body(M.v3(3.0, 0.5, 0.2), M.v3(0.05, 0.1, 0.2))
	var e0 := Dynamics.kinetic_energy(model, state)
	var e_prev := e0
	var monotone := true
	var cont := _cont()
	for k in 5:
		var next := _integrate(model, state, cont, _calm(), 1.0)
		state = next.slice(0, 13)
		cont = next.slice(13)
		# Potential energy enters through pitch/roll; compare only while the attitude stays near level.
		var e := Dynamics.kinetic_energy(model, state)
		monotone = monotone and e < e_prev
		e_prev = e
	_check("coast-down dissipates kinetic energy", monotone and e_prev < 0.6 * e0, "%.4f -> %.4f J" % [e0, e_prev])


func _restoring() -> void:
	var model := _model(fixture(5.0, 1.0, {cg_z = 0.25, drag = true, fins = true}), 0.0)
	if model.is_empty(): return
	var att := M.q_from_euler(0.0, deg_to_rad(8.0), 0.0)
	var end := _integrate(model, _body(M.v3(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0), att), _cont(), _calm(), 40.0)
	var euler := M.q_to_euler(end.slice(6, 10))
	_check("pitch disturbance decays (CB above CG)", absf(rad_to_deg(euler[1])) < 4.0, "pitch %.2f deg after 40 s" % rad_to_deg(euler[1]))
	var all_finite := true
	for value in end:
		all_finite = all_finite and is_finite(value)
	_check("long integration stays finite", all_finite)


func _mixer_signs() -> void:
	var model := _model(fixture(5.0, 1.0, {fins = true}), 0.0)
	if model.is_empty(): return
	var climb := Dynamics.mixer_targets(model, PackedFloat64Array([0.0, 1.0, 0.0, 0.5]))
	_check("full back stick vectors the side props to full travel", absf(climb[4] - deg_to_rad(120.0)) < 1e-12 and absf(climb[5] - deg_to_rad(120.0)) < 1e-12)
	var forward := Dynamics.mixer_targets(model, PackedFloat64Array([0.0, -1.0, 0.0, 0.5]))
	_check("forward stick keeps side thrust horizontal", forward[4] == 0.0 and forward[5] == 0.0)
	var yaw := Dynamics.mixer_targets(model, PackedFloat64Array([0.0, 0.0, 1.0, 0.0]))
	# Lateral thruster thrust direction (0, 1, 0) in the fixture; right yaw needs tail force toward -y.
	_check("right yaw drives the stern thruster toward port", yaw[3] < 0.0, str(yaw[3]))
	var c := _cont(PackedFloat64Array([0.0, 0.0, 0.0, yaw[3]]))
	var r := Dynamics.evaluate(model, _body(), c, _zero_inputs(), _calm(), Callable(), true)
	_check("stern thruster on right yaw makes a nose-right moment", r.loads[5] > 0.0, str(r.loads[5]))
	var diff := Dynamics.mixer_targets(model, PackedFloat64Array([1.0, 0.0, 0.0, 0.5]))
	_check("right roll stick adds port thrust (nose right)", diff[0] > diff[1])
	# Fins: right yaw must make the dorsal fin push the tail toward -y at forward speed.
	var fin_c := _cont()
	for i in 3:
		fin_c[Data.FIN + i] = yaw[7 + i]
	var moving := Dynamics.evaluate(model, _body(M.v3(3.0, 0.0, 0.0)), fin_c, _zero_inputs(), _calm(), Callable(), true)
	var straight := Dynamics.evaluate(model, _body(M.v3(3.0, 0.0, 0.0)), _cont(), _zero_inputs(), _calm(), Callable(), true)
	_check("rudder deflection on right yaw adds nose-right moment", moving.loads[5] > straight.loads[5], "%.4f vs %.4f" % [moving.loads[5], straight.loads[5]])
	var pitch := Dynamics.mixer_targets(model, PackedFloat64Array([0.0, 1.0, 0.0, 0.0]))
	var pitch_c := _cont()
	for i in 3:
		pitch_c[Data.FIN + i] = pitch[7 + i]
	var nose_up := Dynamics.evaluate(model, _body(M.v3(3.0, 0.0, 0.0)), pitch_c, _zero_inputs(), _calm(), Callable(), true)
	_check("back stick fins add nose-up moment", nose_up.loads[4] > straight.loads[4], "%.4f vs %.4f" % [nose_up.loads[4], straight.loads[4]])


func _flat(n: float, e: float) -> PackedFloat64Array:
	return PackedFloat64Array([0.0, 0.0, 0.0])


## Checks designed to fail for the sign/omission mutants found in review (transport, Munk, fin sign, torque,
## lapse, battery, contact plane).
func _discriminating() -> void:
	# Steady wind while rotating: same air-relative state => omega_dot equal, v_dot differs by -omega x w_b.
	var model := _model(fixture(5.0, 1.0, {cg_z = 0.2, drag = true, fins = true}), 0.03)
	if model.is_empty(): return
	var att := M.q_normalized(M.quat(0.95, 0.12, -0.2, 0.18))
	var w := M.v3(0.2, -0.15, 0.25)
	var v_rel := M.v3(1.5, 0.3, -0.2)
	var wind := M.v3(1.2, -2.0, 0.3)
	var w_b := M.q_rotate(M.q_conj(att), wind)
	var calm := Dynamics.evaluate(model, _body(v_rel, w, att), _cont(), _zero_inputs(), _calm(), Callable(), false)
	var windy := Dynamics.evaluate(model, _body(M.add(v_rel, w_b), w, att), _cont(), _zero_inputs(), wind, Callable(), false)
	var a_c: PackedFloat64Array = calm.body_derivative
	var a_w: PackedFloat64Array = windy.body_derivative
	var expected := M.sub(M.v3(a_c[3], a_c[4], a_c[5]), M.cross(w, w_b))
	var err := M.norm(M.sub(expected, M.v3(a_w[3], a_w[4], a_w[5]))) + M.norm(M.sub(M.v3(a_c[10], a_c[11], a_c[12]), M.v3(a_w[10], a_w[11], a_w[12])))
	_check("rotating in steady wind = rotating in calm air (Galilean)", err < 1e-9, str(err))
	# Munk moment of the ideal spheroid: q_dot = u w (m33 - m11) / (Iyy + m55), destabilizing.
	var ideal := _model(fixture(5.0, 1.0), 0.0)
	var u := 3.0
	var ww := 0.4
	var munk := Dynamics.evaluate(ideal, _body(M.v3(u, 0.0, ww)), _cont(), _zero_inputs(), _calm(), Callable(), false)
	var c := Data.spheroid_coefficients(2.5, sqrt(3.0 * float(ideal.envelope.volume) / (4.0 * PI * 2.5)))
	var rho_v := RHO * float(ideal.envelope.volume)
	var q_dot: float = u * ww * (c.k2 - c.k1) * rho_v / (float(ideal.inertia[1]) + c.k_rot * rho_v * (6.25 + 3.0 * float(ideal.envelope.volume) / (4.0 * PI * 2.5)) / 5.0)
	_check("Munk moment: nose-up for w > 0 with Lamb magnitude", munk.body_derivative[11] > 0.0 and absf(munk.body_derivative[11] - q_dot) < 1e-6 * absf(q_dot) + 1e-12,
		"%s vs %s" % [munk.body_derivative[11], q_dot])
	# Fin weathervane: sideslip from the right and flow from below turn the nose into the relative wind.
	var bare := _model(fixture(5.0, 1.0, {fins = false}), 0.0)
	var finned := _model(fixture(5.0, 1.0, {fins = true}), 0.0)
	var slip := M.v3(3.0, 0.5, 0.5)
	var lb: PackedFloat64Array = Dynamics.evaluate(bare, _body(slip), _cont(), _zero_inputs(), _calm(), Callable(), false).loads
	var lf: PackedFloat64Array = Dynamics.evaluate(finned, _body(slip), _cont(), _zero_inputs(), _calm(), Callable(), false).loads
	_check("fins weathervane in yaw (nose toward sideslip)", lf[5] - lb[5] > 0.0, str(lf[5] - lb[5]))
	_check("fins stabilize in pitch (nose down for w > 0)", lf[4] - lb[4] < 0.0, str(lf[4] - lb[4]))
	# Torque reaction: port prop, sense -1 about +x thrust, kappa 0.01 m, T0 2 N => +0.02 N m roll.
	var torqued := _model(fixture(5.0, 1.0, {torque = 0.01}), 0.0)
	var tr := Dynamics.evaluate(torqued, _body(), _cont(PackedFloat64Array([1.0, 0.0, 0.0, 0.0])), _zero_inputs(), _calm(), Callable(), false)
	_check("propeller torque reaction sign and size", absf(tr.loads[3] - 0.02) < 1e-12, str(tr.loads[3]))
	# Thrust lapse: T = T0 (n|n| - |n| V_in / V_p) = 2 (1 - 6/12) = 1 N at 6 m/s.
	var lapse := _model(fixture(5.0, 1.0, {drag = true}), 0.0)
	var lr := Dynamics.evaluate(lapse, _body(M.v3(6.0, 0.0, 0.0)), _cont(PackedFloat64Array([1.0, 0.0, 0.0, 0.0])), _zero_inputs(), _calm(), Callable(), true)
	_check("propeller thrust lapse with inflow", absf(float(lr.info.thrust_n[0]) - 1.0) < 1e-12, str(lr.info.thrust_n[0]))
	# Battery bus: one terminal voltage for all motors.
	var all_on := Dynamics.evaluate(lapse, _body(), _cont(PackedFloat64Array([1.0, 1.0, 1.0, 1.0])), _zero_inputs(), _calm(), Callable(), true)
	var power := 4.0 * 25.0 / 0.75
	var ocv := 3.0 * 4.2
	var volts := 0.5 * (ocv + sqrt(ocv * ocv - 4.0 * power * 0.045))
	_check("battery terminal voltage of the shared bus", absf(float(all_on.info.battery.volts) - volts) < 1e-12, "%s vs %s" % [all_on.info.battery.volts, volts])
	# Gear contact: static support k*depth, never pulling, friction in the ground plane (no normal component).
	var geared := _model(fixture(5.0, 1.0), 0.0)
	var gear_z: float = geared.contacts.gear[0].point[2]
	var depth := 0.01
	var rest := _body()
	rest[2] = -gear_z + depth
	var gc := Dynamics.evaluate(geared, rest, _cont(), _zero_inputs(), _calm(), _flat, true)
	_check("gear static support = k * depth", absf(float(gc.info.contact.gear_load_n) - 400.0 * depth) < 1e-9, str(gc.info.contact.gear_load_n))
	var lifting := rest.duplicate()
	lifting[5] = -5.0
	var gl := Dynamics.evaluate(geared, lifting, _cont(), _zero_inputs(), _calm(), _flat, true)
	_check("contact never pulls", float(gl.info.contact.gear_load_n) >= 0.0)
	var pitched := RB.make_state(M.v3(0.0, 0.0, 0.0), M.v3(1.0, 0.3, 0.0), M.q_from_euler(0.3, deg_to_rad(5.0), 0.0), M.v3(0.0, 0.0, 0.0))
	var gp: PackedFloat64Array = geared.contacts.gear[0].point
	var world_down := M.q_rotate(pitched.slice(6, 10), gp)[2]
	pitched[2] = -world_down + depth
	var sliding := Dynamics.evaluate(geared, pitched, _cont(), _zero_inputs(), _calm(), _flat, true)
	var hull_only := geared.duplicate(true)
	hull_only.contacts.hull_points = PackedFloat64Array()
	var g_only := Dynamics.evaluate(hull_only, pitched, _cont(), _zero_inputs(), _calm(), _flat, true)
	var no_ground := Dynamics.evaluate(hull_only, pitched, _cont(), _zero_inputs(), _calm(), Callable(), true)
	var df := M.q_rotate(pitched.slice(6, 10), M.sub(g_only.loads.slice(0, 3), no_ground.loads.slice(0, 3)))
	_check("tilted sliding wheel: vertical force equals the normal load", absf(-df[2] - float(g_only.info.contact.gear_load_n)) < 1e-9,
		"%s vs %s" % [-df[2], g_only.info.contact.gear_load_n])
	_check("sliding wheel friction opposes motion", M.dot(M.v3(df[0], df[1], 0.0), M.q_rotate(pitched.slice(6, 10), pitched.slice(3, 6))) < 0.0)
	var touch := _body(M.v3(0.0, 0.0, 1.0))
	touch[2] = -gear_z + 1e-4
	var first := Dynamics.evaluate(geared, touch, _cont(), _zero_inputs(), _calm(), _flat, true)
	# Undamped jump would be c * |vn| = 25 N; the depth-ramped damping gives k d + c (d / 5 mm) |vn| = 0.54 N.
	_check("first touch starts without a damping jump", float(first.info.contact.gear_load_n) < 1.0 and sliding.loads.size() == 6, str(first.info.contact.gear_load_n))