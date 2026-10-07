# E0b4: reproducible sensitivity evidence. No aircraft file or simulation default is modified.
extends SceneTree
const Fixture = preload("res://tests/test_wash_profile.gd")
const AD = preload("res://physics/aircraft_data.gd")
const Aero = preload("res://physics/aero.gd")
const Air = preload("res://physics/air_data.gd")
const S = preload("res://physics/slipstream.gd")
const Prop = preload("res://physics/propulsion.gd")
const Trim = preload("res://physics/trim.gd")
const Modes = preload("res://physics/flight_modes.gd")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const RHO: float = 1.225
const G: float = 9.80665
const KS: Array[float] = [0.8, 1.1, 1.4]
const KF: Array[float] = [1.4, 1.7, 1.9]
const EDGES: Array[float] = [0.05, 0.15, 0.30]
const DRIFTS: Array[float] = [0.0, 0.543, 1.0]
var failed: int = 0
var worst_derivative_refinement: float = 0.0

func d_zero() -> Dictionary:
	return {elevator = 0.0, rudder = 0.0, aileron_left = 0.0, aileron_right = 0.0}

func d_trim(t: Dictionary) -> Dictionary:
	return {elevator = t.elevator, rudder = t.rudder, aileron_right = t.aileron, aileron_left = -t.aileron}

func configuration(ks: float, kf: float, edge: float, drift: float) -> Dictionary:
	var raw: Dictionary = Fixture.combined_raw()
	var ss: Dictionary = raw.propulsion.propeller.slipstream
	ss.wash_factor.value = [ks, kf]
	ss.edge_fraction.value = edge
	ss.vertical_drift.value = drift
	var loaded: Dictionary = AD.validate_and_derive(raw)
	if not loaded.ok:
		failed += 1
		printerr("FAIL invalid sweep configuration ", loaded.errors)
	return loaded.get("model", {})

func _initialize() -> void:
	var output: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	if output.is_empty():
		printerr("Usage: -- --output=/absolute/path/results.json")
		quit(2)
		return
	var base: Dictionary = AD.load_file("res://data/aircraft/jensen_ugly_stik_60.json").model
	var contexts: Array[Dictionary] = []
	var baseline_modes: Array[Dictionary] = []
	for speed: float in [10.0, 15.0, 25.0]:
		var trim: Dictionary = Trim.solve("level", speed, base, G, base.controls.throw_rad)
		if not trim.ok:
			printerr("FAIL baseline trim ", trim.message)
			quit(1)
			return
		contexts.append({name = "baseline_trim_%d" % speed, speed = speed, state = trim.state, d = d_trim(trim), rpm = trim.rpm, throttle = trim.throttle, alpha = trim.alpha, beta = trim.beta})
		baseline_modes.append(mode_summary(base, speed))
	for speed: float in [0.0, 5.0, 15.0, 25.0]:
		contexts.append({name = "axial_full_%d" % speed, speed = speed,
			state = Trim.state_for(speed, 0.0, 0.0, 0.0, M.v3(0, 0, -100)), d = d_zero(),
			rpm = base.propulsion.max_rpm, throttle = 1.0, alpha = 0.0, beta = 0.0})
	var baseline: Array[Dictionary] = []
	for context: Dictionary in contexts:
		var row: Dictionary = public_context(context)
		if context.speed > 0:
			row.derivatives = derivatives(base, context, 1e-4, false)
		baseline.append(row)
	var cases: Array[Dictionary] = []
	var modes: Array[Dictionary] = []
	for ks: float in KS:
		for kf: float in KF:
			for edge: float in EDGES:
				for drift: float in DRIFTS:
					var model: Dictionary = configuration(ks, kf, edge, drift)
					var entry: Dictionary = {ks = ks, kf = kf, edge = edge, drift = drift, conditions = []}
					for context: Dictionary in contexts:
						var row: Dictionary = diagnose(model, context)
						if context.speed > 0:
							row.derivatives = derivatives(model, context, 1e-4, true)
							var refined: Dictionary = derivatives(model, context, 5e-5, true)
							for key: String in refined:
								worst_derivative_refinement = maxf(worst_derivative_refinement,
									absf(refined[key]-row.derivatives[key])/maxf(1.0, absf(refined[key])))
						entry.conditions.append(row)
					entry.static_controls = static_controls(model)
					entry.static_controls_zero_cl = static_controls(model, 0.0)
					cases.append(entry)
					if edge == 0.15 and drift == 0.543:
						for speed: float in [10.0, 15.0, 25.0]:
							var modal: Dictionary = mode_summary(model, speed)
							modal.ks = ks
							modal.kf = kf
							modes.append(modal)
			print("evaluated wash endpoints ", ks, " / ", kf)
	var ideal_model: Dictionary = configuration(2.0, 2.0, 0.15, 0.543)
	var ideal: Array[Dictionary] = []
	for context: Dictionary in contexts:
		ideal.append(diagnose(ideal_model, context))
	var typical_model: Dictionary = configuration(0.8, 1.8, 0.15, 0.543)
	var typical: Dictionary = {ks = 0.8, kf = 1.8, edge = 0.15, drift = 0.543,
		kind = "approximate figure-read endpoints with estimated geometry regularization", conditions = [], modes = []}
	for context: Dictionary in contexts:
		var row: Dictionary = diagnose(typical_model, context)
		if context.speed > 0:
			row.derivatives = derivatives(typical_model, context, 1e-4, true)
		typical.conditions.append(row)
	for speed: float in [10.0, 15.0, 25.0]:
		typical.modes.append(mode_summary(typical_model, speed))
	var static_air: Dictionary = Air.compute(contexts[3].state, M.v3(0, 0, 0), RHO)
	var static_cl: float = Aero.wing_lift_coefficient(contexts[3].state, static_air, d_zero(), base)
	var tail: Dictionary = base.surfaces.horizontal
	var static_reference: Dictionary = {wing_cl_at_zero_speed = static_cl, wing_cl0 = tail.wing_cl0,
		free_incidence_rad = tail.free_incidence, downwash_per_cl_rad = tail.downwash_per_cl,
		neutral_effective_angle_rad = tail.free_incidence-tail.downwash_per_cl*static_cl,
		forced_zero_cl_angle_rad = tail.free_incidence}
	var hashes: Dictionary = {}
	for path: String in ["physics/aero.gd", "physics/slipstream.gd", "physics/aircraft_data.gd",
		"physics/trim.gd", "physics/flight_modes.gd", "physics/dynamics.gd", "physics/linearize.gd",
		"physics/propulsion.gd", "physics/air_data.gd", "physics/math3d.gd", "physics/rigid_body.gd",
		"tests/test_wash_profile.gd", "tests/fixtures/stik_wash_profile.json", "data/aircraft/jensen_ugly_stik_60.json"]:
		hashes["app/"+path] = FileAccess.get_file_as_string("res://"+path).sha256_text()
	hashes["research/propwash/e0b4/sweep.gd"] = FileAccess.get_file_as_string(get_script().resource_path).sha256_text()
	var result: Dictionary = {
		format = "openrc-e0b4-sensitivity v1", rho_kg_m3 = RHO, gravity_m_s2 = G,
		aircraft_id = base.id, engine = Engine.get_version_info(), parameter_kind = "estimated",
		scope = "Sensitivity grid, not fitted or measured Stik calibration. Swirl zero. No wash transport. Existing wing-downwash lag retained in modes.",
		static_reference = static_reference, source_sha256 = hashes, ideal_speed_reference = ideal, source_typical = typical,
		grid = {ks = KS, kf = KF, edge_fraction = EDGES, vertical_drift = DRIFTS},
		baseline = baseline, baseline_modes = baseline_modes, cases = cases, retrimmed_modes = modes,
		worst_normalized_derivative_refinement = worst_derivative_refinement,
		held_cl_diagnostic_note = "Forcing CL input to zero leaves E0a2 free_incidence unchanged; this perturbs its calibration and is not a corrected physical zero-downwash model.",
		production_slipstream_absent = base.propulsion.get("slipstream", {}).is_empty(),
	}
	if not finite_tree(result) or worst_derivative_refinement > 1e-4:
		failed += 1
		printerr("FAIL nonfinite result or unconverged derivative: ", worst_derivative_refinement)
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		printerr("FAIL cannot open output ", output)
		quit(1)
		return
	file.store_string(JSON.stringify(result, "\t")+"\n")
	file.close()
	print("E0b4: %d configurations, %d conditions, %d retrimmed mode cases; derivative refinement %s; %d failed" %
		[cases.size(), cases.size()*contexts.size(), modes.size(), String.num_scientific(worst_derivative_refinement), failed])
	quit(1 if failed else 0)

func finite_tree(value: Variant) -> bool:
	if value is float:
		return is_finite(value)
	if value is Dictionary:
		for key: Variant in value:
			if not finite_tree(value[key]):
				return false
	if value is Array or value is PackedFloat64Array:
		for element: Variant in value:
			if not finite_tree(element):
				return false
	return true

func public_context(c: Dictionary) -> Dictionary:
	return {name = c.name, speed_m_s = c.speed, rpm = c.rpm, throttle = c.throttle,
		alpha_deg = rad_to_deg(c.alpha), beta_deg = rad_to_deg(c.beta), controls_rad = c.d}

func diagnose(model: Dictionary, c: Dictionary) -> Dictionary:
	var row: Dictionary = public_context(c)
	var air: Dictionary = Air.compute(c.state, M.v3(0, 0, 0), RHO)
	var prop: Dictionary = model.propulsion
	var tq: PackedFloat64Array = Prop.thrust_torque(air.v_air, c.rpm, prop, RHO)
	var w: Dictionary = S.wake(air.v_air, tq[0], tq[1], prop, RHO)
	var q_free: float = 0.5*RHO*c.speed*c.speed
	var q_added: float = 0.5*RHO*(2*w.u*w.dv+w.dv*w.dv)
	row.thrust_N = tq[0]
	row.induced_m_s = w.w
	row.added_axial_m_s = w.dv
	row.velocity_factor = w.dv/w.w if w.w != 0 else 0.0
	row.wake_radius_m = w.rs
	row.centre_q_Pa = q_free+q_added
	row.centre_q_ratio = (q_free+q_added)/q_free if q_free > 0 else null
	row.wing_cl = Aero.wing_lift_coefficient(c.state, air, c.d, model)
	row.increment = S.loads(c.state, air, c.d, model, c.rpm, RHO)
	var area: Dictionary = {horizontal = 0.0, vertical = 0.0}
	var geometric: Dictionary = {horizontal = 0.0, vertical = 0.0}
	for piece: Dictionary in prop.slipstream.pieces:
		var im: Dictionary = S.immersion(piece, w, prop.slipstream.hub, prop, air.v_air, air.V, model)
		area[piece.surface] += im.area
		geometric[piece.surface] += piece.area
	row.coverage = {}
	for surface: String in ["horizontal", "vertical"]:
		var aero_area: float = model.surfaces[surface].area
		row.coverage[surface] = {weighted_area_m2 = area[surface],
			geometric_area_m2 = geometric[surface], aerodynamic_area_m2 = aero_area,
			geometric_fraction = area[surface]/geometric[surface], aerodynamic_fraction = area[surface]/aero_area,
			mean_q_proxy_Pa = q_free+area[surface]/aero_area*q_added,
			mean_q_proxy_ratio = 1.0+area[surface]/aero_area*q_added/q_free if q_free > 0 else null}
	return row

# Same state/controls/rpm for on/off; alpha/beta quasi-static derivatives recompute wing downwash.
# Rate and control derivatives freeze the settled downwash lag-state input; global Aero retains its current-minus-lag correction.
func derivatives(model: Dictionary, c: Dictionary, h: float, wash: bool) -> Dictionary:
	var out: Dictionary = {}
	var state: PackedFloat64Array = c.state
	var air: Dictionary = Air.compute(state, M.v3(0, 0, 0), RHO)
	var held_cl: float = Aero.wing_lift_coefficient(state, air, c.d, model)
	for key: String in ["Cma", "Cma_held", "Cmq", "Cnb", "Cnr", "Cmde", "Cndr"]:
		var plus: PackedFloat64Array = state.duplicate()
		var minus: PackedFloat64Array = state.duplicate()
		var dp: Dictionary = c.d.duplicate()
		var dm: Dictionary = c.d.duplicate()
		var cl: float = held_cl
		if key in ["Cma", "Cma_held", "Cnb"]:
			var da: float = h if key != "Cnb" else 0.0
			var db: float = h if key == "Cnb" else 0.0
			plus = Trim.state_for(c.speed, c.alpha+da, 0.0, 0.0, M.v3(0, 0, -100), c.beta+db)
			minus = Trim.state_for(c.speed, c.alpha-da, 0.0, 0.0, M.v3(0, 0, -100), c.beta-db)
			if key != "Cma_held":
				cl = NAN
		elif key in ["Cmq", "Cnr"]:
			var rate: int = RB.RATE+1 if key == "Cmq" else RB.RATE+2
			var length: float = model.reference.c if key == "Cmq" else model.reference.b
			plus[rate] += h*2*c.speed/length
			minus[rate] -= h*2*c.speed/length
		else:
			var control: String = "elevator" if key == "Cmde" else "rudder"
			dp[control] += h
			dm[control] -= h
		var lp: PackedFloat64Array = aero_wash(plus, dp, model, c.rpm, cl, wash)
		var lm: PackedFloat64Array = aero_wash(minus, dm, model, c.rpm, cl, wash)
		var pitch: bool = key.begins_with("Cm")
		var denominator: float = 0.5*RHO*c.speed*c.speed*model.reference.S*(model.reference.c if pitch else model.reference.b)
		out[key] = (lp[4 if pitch else 5]-lm[4 if pitch else 5])/(2*h*denominator)
	return out

func aero_wash(state: PackedFloat64Array, d: Dictionary, model: Dictionary, rpm: float, cl: float, wash: bool) -> PackedFloat64Array:
	var air: Dictionary = Air.compute(state, M.v3(0, 0, 0), RHO)
	var loads: PackedFloat64Array = Aero.loads(state, air, d, model, RHO, cl)
	if wash:
		var increment: PackedFloat64Array = S.loads(state, air, d, model, rpm, RHO, cl)
		for i in 6:
			loads[i] += increment[i]
	return loads

func static_controls(model: Dictionary, held_cl: float = NAN) -> Dictionary:
	var state: PackedFloat64Array = Trim.state_for(0.0, 0.0, 0.0, 0.0, M.v3(0, 0, -100))
	var air: Dictionary = Air.compute(state, M.v3(0, 0, 0), RHO)
	var result: Dictionary = {}
	for control: String in ["elevator", "rudder"]:
		var moment: int = 4 if control == "elevator" else 5
		var samples: Array[Dictionary] = []
		for i in 17:
			var deflection: float = float(model.controls.throw_rad[control])*(i-8)/8.0
			var d: Dictionary = d_zero()
			d[control] = deflection
			var loads: PackedFloat64Array = S.loads(state, air, d, model, model.propulsion.max_rpm, RHO, held_cl)
			samples.append({deflection_rad = deflection, moment_Nm = loads[moment]})
		result[control] = samples
	return result

func mode_summary(model: Dictionary, speed: float) -> Dictionary:
	var r: Dictionary = Modes.analyze(model, speed)
	var out: Dictionary = {speed_m_s = speed, ok = r.ok, message = r.message}
	if not r.ok:
		failed += 1
		printerr("FAIL mode solve at ", speed, ": ", r.message)
		return out
	for key: String in ["short_period", "phugoid", "dutch_roll", "roll_tau", "spiral_tau", "downwash_lag_root"]:
		out[key] = r[key]
	out.trim = {alpha_deg = rad_to_deg(r.trim.alpha), beta_deg = rad_to_deg(r.trim.beta),
		rpm = r.trim.rpm, throttle = r.trim.throttle, controls_rad = d_trim(r.trim), residual = r.trim.residual}
	return out
