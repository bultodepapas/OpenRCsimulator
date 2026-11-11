extends SceneTree
## AC-12 handling probe (research, not a test): dynamic modes at trim and the two upset cases of the
## independent review, for the template and in-domain corners of the estimated trainer package.
##
## 1. Modes: physics/flight_modes.gd linearizes the real equations at the level trim (controls and shaft
##    speed frozen) and reports the 4x4 block projections. The full Jacobian is written to
##    <out>/jacobians.json so the coupled eigenvalues can be computed with an external solver
##    (eigenvalues.py). The projection drops the longitudinal-lateral coupling of the propeller.
## 2. Hand launch at full throttle, hands off, 10 s.
## 3. One-second full-aft pull from the level trim, then hands off for 12 s.
## Cases 2 and 3 are flown three times: as the product flies them; with the propeller reaction torque
## cancelled and the roll and yaw trims (which only balance it) at zero; and with the rotor's gyroscopic
## momentum cancelled as well. The runtime has no such switches and gains none: this script wraps the
## session's stage evaluator IN THE PROBE (thrust and shaft dynamics unchanged).
## A fourth template run changes Clr in the in-memory model as a sensitivity, not a package change.
## Software evidence about an estimated package: it attributes behaviour inside the model, it does not
## show that a real airplane behaves this way.
##
## Run (repository root, pinned engine):
##   <engine> --headless --path app --audio-driver Dummy --script <abs>/research/aircraft-creator/ac12/handling.gd -- --out=<dir> [--only=<text>]

const Definition := preload("res://workshop/creator/definition.gd")
const Compiler := preload("res://workshop/creator/compiler.gd")
const R := preload("res://workshop/creator/result.gd")
const FlightModes := preload("res://physics/flight_modes.gd")
const Session := preload("res://sim/flight_session.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Weather := preload("res://physics/wind_config.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

const RATE := 240
const LAUNCH_S := 10.0
const PULL_S := 1.0
const AFTER_PULL_S := 12.0
const LEVELS: PackedStringArray = ["as flown", "no reaction torque, roll and yaw trim zero", "no reaction torque, no gyroscopic momentum, trims zero"]
## Clr of a rectangular wing is about CL/4 (strip theory); the package borrows the value of the level
## speed (CL 0.44). 0.045 is CL/4 at the 19-20 m/s of the spiral dive after the pull.
const DIVE_CLR := 0.045

var Variants: GDScript
var _field: Dictionary = {}


func _initialize() -> void:
	Variants = load((get_script() as Script).resource_path.get_base_dir().path_join("variants.gd"))
	var out := ""
	var only := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out = argument.substr(6)
		if argument.begins_with("--only="):
			only = argument.substr(7)
	_field = FieldLoader.load_from().field
	var template: Dictionary = Definition.template()
	var margin: float = float(Compiler.summarize(template).static_margin)
	# Every corner carries the template's dihedral; the template is also flown flat, with the donor's
	# 2.86 degrees (the package before the dihedral input: the reviewed configuration) and at the bound.
	var cases := {}
	cases["template (dihedral 5)"] = template
	cases["template, dihedral 0"] = _dihedral(template, 0.0)
	cases["template, dihedral 2.86 (reviewed)"] = _dihedral(template, 2.86)
	cases["template, dihedral 8"] = _dihedral(template, 8.0)
	cases["static margin 0.29"] = Variants.balanced(template, 0.29)
	cases["static margin 0.085"] = Variants.balanced(template, 0.085)
	cases["aspect ratio 4"] = Variants.balanced(Variants.aspect(4.0), margin)
	cases["aspect ratio 7"] = Variants.balanced(Variants.aspect(7.0), margin)
	cases["span 1.0 m"] = Variants.balanced(Variants.scaled(1.0 / 1.5), margin)
	cases["span 2.0 m"] = Variants.balanced(Variants.scaled(2.0 / 1.5), margin)
	cases["span 1.0 m, dihedral 2.86 (reviewed)"] = _dihedral(cases["span 1.0 m"], 2.86)
	var jacobians := {}
	for name: String in cases:
		if not only.is_empty() and not name.contains(only):
			continue
		var definition: Dictionary = cases[name]
		if definition.is_empty():
			print("## %s: no balance found" % name)
			continue
		var compiled: Dictionary = Compiler.compile_candidate(definition)
		if not compiled.ok:
			print("## %s: refused: %s" % [name, str(R.texts(compiled))])
			continue
		var candidate: RefCounted = compiled.value
		var summary: Dictionary = candidate.summary()
		var data: Dictionary = candidate.flight_data()
		var model: Dictionary = data.model
		print("## %s: mass %.3f kg, span %.3f m, AR %.2f, static margin %.3f, wing loading %.2f kg/m2, level speed %.2f m/s, T/W %.2f, Jxx %.4f kg m2" % [
			name, summary.mass_kg, float(definition["wing"]["span"]), summary.aspect_ratio, summary.static_margin, summary.wing_loading_kg_m2,
			summary.level_speed_mps, summary.thrust_to_weight, model.inertia[0]])
		print("   Clb %.5f (wing-body %.5f), Clp %.4f, Clr %.4f, Cnb %.4f, Cnr %.4f; spiral criterion Clb*Cnr - Cnb*Clr = %.5f (stable when positive)" % [
			model.aero.Clb, model.surfaces.get("wing_body_cl_beta", 0.0), model.aero.Clp, model.aero.Clr, model.aero.Cnb, model.aero.Cnr,
			model.aero.Clb * model.aero.Cnr - model.aero.Cnb * model.aero.Clr])
		var modes: Dictionary = FlightModes.analyze(model, float(summary.level_speed_mps))
		if modes.ok:
			print("   modes (4x4 projections): short period %.3f Hz zeta %.3f%s; phugoid %.4f Hz zeta %.3f; roll tau %.4f s; dutch roll %.3f Hz zeta %.3f; spiral root %+.4f 1/s; trim alpha %.2f deg, %.0f rpm" % [
				modes.short_period.f_hz, modes.short_period.zeta, " (two real roots)" if modes.short_period_overdamped else "",
				modes.phugoid.f_hz, modes.phugoid.zeta, modes.roll_tau, modes.dutch_roll.f_hz, modes.dutch_roll.zeta, -1.0 / modes.spiral_tau,
				rad_to_deg(modes.trim.alpha), modes.trim.rpm])
			var rows := []
			for row: PackedFloat64Array in modes.full_jacobian:
				rows.append(Array(row))
			jacobians[name] = {jacobian = rows, speed = float(summary.level_speed_mps)}
		else:
			print("   modes: ", modes.message)
		for level: int in LEVELS.size():
			_hand_launch(candidate.aircraft_id(), data, level)
		for level: int in LEVELS.size():
			_pull(candidate.aircraft_id(), data, level, "")
		if name.begins_with("template (") or name.contains("dihedral 8"):
			var changed: Dictionary = data.duplicate(true)
			changed.model.aero.Clr = DIVE_CLR
			_pull(candidate.aircraft_id(), changed, 0, "SENSITIVITY Clr %.3f instead of %.4f: " % [DIVE_CLR, model.aero.Clr])
	if not out.is_empty():
		DirAccess.make_dir_recursive_absolute(out)
		var file := FileAccess.open(out.path_join("jacobians.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(jacobians))
		file.close()
		print("jacobians written to ", out.path_join("jacobians.json"))
	quit(0)


func _dihedral(definition: Dictionary, degrees: float) -> Dictionary:
	var d: Dictionary = definition.duplicate(true)
	d["wing"]["dihedral_deg"] = degrees
	return d


## Probe-only counterfactual. Level 1 adds the shaft torque back to the body moment of every stage
## evaluation; level 2 also removes the rotor's spinning momentum from the rigid-body equations.
func _cancel_propeller_asymmetry(session: Node, level: int) -> void:
	if level == 0:
		return
	var original: Callable = session.sim.model.stage
	var prop: Dictionary = session.aircraft.model.propulsion
	var slot: int = session._rotor_index()
	session.sim.model.stage = func(body: PackedFloat64Array, values: PackedFloat64Array, t: float) -> Dictionary:
		var result: Dictionary = original.call(body, values, t)
		if result.is_empty():
			return result
		var air: Dictionary = session.air_data(body, t)
		var loads: PackedFloat64Array = (result.loads as PackedFloat64Array).duplicate()
		var torque: float = Propulsion.thrust_torque(air.v_air, values[slot], prop, session.air_density(body))[1]
		var axis: PackedFloat64Array = prop.get("axis", PackedFloat64Array([1.0, 0.0, 0.0]))
		for index: int in 3:
			loads[3 + index] += axis[index] * torque
		result.loads = loads
		if level >= 2:
			result.rotor_momentum = PackedFloat64Array([0.0, 0.0, 0.0])
		return result


## [bank of the wing against the horizon in degrees (any pitch), euler roll in degrees, euler pitch in degrees].
func _attitude(s: PackedFloat64Array) -> PackedFloat64Array:
	var q := M.quat(s[RB.ATT], s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3])
	var right: PackedFloat64Array = M.q_rotate(q, M.v3(0.0, 1.0, 0.0))
	var euler := M.q_to_euler(q)
	return PackedFloat64Array([rad_to_deg(asin(clampf(right[2], -1.0, 1.0))), rad_to_deg(euler[2]), rad_to_deg(euler[1])])


## Roll budget at the current state: [shaft torque N·m, full-aileron roll moment N·m, steady roll rate the
## torque alone would give against roll damping in deg/s, airspeed m/s].
func _roll_budget(session: Node) -> PackedFloat64Array:
	var s: PackedFloat64Array = session.sim.state
	var model: Dictionary = session.aircraft.model
	var air: Dictionary = session.air_data(s)
	var speed: float = air.V
	var pressure: float = 0.5 * session.air_density(s) * speed * speed * float(model.reference.S) * float(model.reference.b)
	var torque: float = Propulsion.thrust_torque(air.v_air, session.sim.aux[Session.AUX_RPM], model.propulsion, session.air_density(s))[1]
	var authority: float = pressure * (absf(model.aero.Clda_right) + absf(model.aero.Clda_left)) * float(model.controls.throw_rad.aileron)
	var damping: float = pressure * absf(model.aero.Clp) * float(model.reference.b) / (2.0 * speed)
	return PackedFloat64Array([torque, authority, rad_to_deg(torque / damping), speed])


func _hand_launch(aircraft_id: String, data: Dictionary, level: int) -> void:
	var session: Node = Session.new()
	session.start_choice = Session.START_HAND_LAUNCH
	session.input_enabled = false
	session.crash_auto_restart = false
	session.setup("", aircraft_id, data)
	root.add_child(session)
	session.set_field(_field)
	session.setup_weather(Weather.defaults())
	session.reset()
	if not session.is_flyable() or not str(session.start_error).is_empty():
		print("   hand launch refused: ", session.start_error)
		session.free()
		return
	var held: PackedFloat64Array = session.sim.inputs.duplicate()
	_cancel_propeller_asymmetry(session, level)
	if level > 0:
		# The roll trim only balanced the torque that is now cancelled, the yaw trim that aileron's adverse yaw.
		held[0] = 0.0
		held[2] = 0.0
		session.sim.inputs = held
	var ground: float = session.environment.terrain(session.sim.state[RB.POS], session.sim.state[RB.POS + 1])[0]
	var release := _roll_budget(session)
	var worst := 0.0
	var worst_wing := 0.0
	var first_90 := -1.0
	var pitch_at_90 := 0.0
	var steepest := 0.0
	var samples := PackedStringArray()
	var crashed := -1.0
	for tick: int in int(LAUNCH_S * RATE):
		if not session._session_after_input():
			crashed = float(tick) / RATE
			break
		session.sim.step()
		var s: PackedFloat64Array = session.sim.state
		var attitude := _attitude(s)
		worst = maxf(worst, absf(attitude[1]))
		worst_wing = maxf(worst_wing, absf(attitude[0]))
		steepest = maxf(steepest, attitude[2])
		var time: float = float(tick + 1) / RATE
		if first_90 < 0.0 and absf(attitude[1]) >= 90.0:
			first_90 = time
			pitch_at_90 = attitude[2]
		if (tick + 1) % RATE == 0:
			samples.append("%.0fs h%.0f V%.0f p%+.0f e%+.0f w%+.0f" % [time, -s[RB.POS + 2] - ground, float(session.air_data(s).V),
				attitude[2], attitude[1], attitude[0]])
	print("   hand launch, full throttle, hands off %.0f s [%s]: steepest pitch %+.0f deg; euler roll max %.0f deg, first 90 deg at %.2f s with pitch %+.0f deg; wing bank against the horizon max %.0f deg; crash at %.2f s (-1 = none)" % [
		LAUNCH_S, LEVELS[level], steepest, worst, first_90, pitch_at_90, worst_wing, crashed])
	print("      t, height m, airspeed m/s, pitch, euler roll, wing bank deg: ", " | ".join(samples))
	if level == 0:
		print("      at release (%.1f m/s): shaft torque %.3f N m, full-aileron roll moment %.2f N m (torque = %.0f %% of it), torque-only steady roll rate %.0f deg/s" % [
			release[3], release[0], release[1], 100.0 * release[0] / release[1], release[2]])
	session.free()


func _pull(aircraft_id: String, data: Dictionary, level: int, note: String) -> void:
	var session: Node = Session.new()
	session.physics_enabled = true
	session.input_enabled = false
	session.rate_profile = "full"
	session.crash_auto_restart = false
	session.start_choice = Session.START_AIRBORNE
	session.setup("", aircraft_id, data)
	if not session.is_flyable():
		print("   pull: start refused: ", session.start_error)
		session.free()
		return
	_cancel_propeller_asymmetry(session, level)
	var trimmed: PackedFloat64Array = session.sim.inputs.duplicate()
	if level > 0:
		# The roll trim only balanced the torque that is now cancelled, the yaw trim that aileron's adverse yaw.
		trimmed[0] = 0.0
		trimmed[2] = 0.0
	var start: PackedFloat64Array = session.sim.state.duplicate()
	var trim_speed: float = session.air_data(start).V
	var worst := 0.0
	var worst_alpha := 0.0
	var lowest := 0.0
	var highest := 0.0
	var slowest := INF
	var samples := PackedStringArray()
	var total: int = int((PULL_S + AFTER_PULL_S) * RATE)
	for tick: int in total:
		var inputs: PackedFloat64Array = trimmed.duplicate()
		if float(tick) / RATE < PULL_S:
			inputs[1] = 1.0
		session.sim.inputs = inputs
		session.sim.step()
		if not session.sim.fault_reason.is_empty():
			break
		var s: PackedFloat64Array = session.sim.state
		var attitude := _attitude(s)
		var air: Dictionary = session.air_data(s)
		worst = maxf(worst, absf(attitude[1]))
		worst_alpha = maxf(worst_alpha, rad_to_deg(float(air.alpha)))
		var height: float = -(s[RB.POS + 2] - start[RB.POS + 2])
		lowest = minf(lowest, height)
		highest = maxf(highest, height)
		slowest = minf(slowest, float(air.V))
		if (tick + 1) % (2 * RATE) == 0 or tick + 1 == total:
			samples.append("%.0fs h%+.0f V%.0f b%+.0f p%+.0f" % [float(tick + 1) / RATE, height, float(air.V), attitude[1], attitude[2]])
	var s_end: PackedFloat64Array = session.sim.state
	print("   %sfull-aft pull %.0f s, then hands off %.0f s [%s]: largest angle of attack %.0f deg; end height %+.1f m (range %+.1f..%+.1f), airspeed %.1f m/s (trim %.1f, slowest %.1f), euler roll end %+.0f deg (max %.0f) %s" % [
		note, PULL_S, AFTER_PULL_S, LEVELS[level], worst_alpha, -(s_end[RB.POS + 2] - start[RB.POS + 2]), lowest, highest,
		float(session.air_data(s_end).V), trim_speed, slowest, _attitude(s_end)[1], worst, session.sim.fault_reason])
	print("      t, height m, airspeed m/s, bank deg, pitch deg: ", " | ".join(samples))
	session.free()
