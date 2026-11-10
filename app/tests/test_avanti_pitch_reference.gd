# AV-17-R4: the generated pitch-rate derivative is an ARP moment; its stated
# tail-volume build-up is about the authored reference-inventory CG.
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const Flight := preload("res://sim/flight_session.gd")
const LiquidFlight := preload("res://sim/liquid_fuel_flight.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Trim := preload("res://physics/trim.gd")

const DEFAULT_DATA := "res://data/aircraft/sebart_avanti_s_a200.json"
const AIRCRAFT_ID := "sebart-avanti-s-a200-p100rx"
const RHO := 1.225
const SPEED := 45.0
const RATE_STEP := 0.01
# The aircraft generator serializes its surface inputs to six decimals. The
# independent reconstruction consequently cannot reproduce its unrounded tail
# geometry exactly; this tolerance is far below the observed 0.415 datum error.
const TARGET_TOLERANCE := 0.0002
const IDENTITY_TOLERANCE := 1.0e-8

var checks := 0
var failures := 0


func check(label: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	var path := DEFAULT_DATA
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--aircraft="):
			path = arg.trim_prefix("--aircraft=")
	var loaded: Dictionary = AD.load_file(path)
	check("Avanti aircraft loads", loaded.get("ok", false), str(loaded.get("errors", [])))
	if loaded.get("ok", false):
		var model: Dictionary = loaded.model
		var tail: Dictionary = model.surfaces.horizontal
		check("tail carries the free-slope basis", tail.has("free_slope"))
		if tail.has("free_slope"):
			var c: float = model.reference.c
			var arm: float = (float(tail.position[0]) - float(model.cg_le[0])) / c
			# Reconstruct AV-06's stated CG-referenced tail-volume estimate, rather
			# than deriving the expected answer from the Cmq under test. 1.1 is the
			# generator's explicit wing/fuselage allowance, not a measurement.
			var target := -2.0 * float(tail.free_slope) * float(tail.area) / float(model.reference.S) * arm * arm * 1.1
			_reference_checks(model, target)
			_session_checks(path, model, target)
	print("AV-17-R4 pitch reference: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _state(alpha: float, rate: float) -> PackedFloat64Array:
	var s := Trim.state_for(SPEED, alpha, 0.0, 0.0, M.v3(0.0, 0.0, -500.0))
	s[RB.RATE + 1] = rate
	return s


func _neutral() -> Dictionary:
	return {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}


func _moment_derivative(plus: PackedFloat64Array, minus: PackedFloat64Array, model: Dictionary) -> float:
	var c: float = model.reference.c
	var qbar := 0.5 * RHO * SPEED * SPEED
	return (plus[4] - minus[4]) / (2.0 * RATE_STEP) * 2.0 * SPEED / (qbar * float(model.reference.S) * c * c)


func _reference_checks(model: Dictionary, target: float) -> void:
	var c: float = model.reference.c
	var arm_x: float = float(model.cg_le[0]) - float(model.reference.arp_le[0])
	var arm_z: float = float(model.cg_le[2]) - float(model.reference.arp_le[2])
	for alpha_deg: float in [0.0, 4.0, 8.0]:
		var alpha := deg_to_rad(alpha_deg)
		var plus := _state(alpha, RATE_STEP)
		var minus := _state(alpha, -RATE_STEP)
		var air := Air.compute(plus, M.v3(0.0, 0.0, 0.0), RHO)
		var global_plus := Aero._global_loads(plus, air, _neutral(), model, RHO)
		var global_minus := Aero._global_loads(minus, air, _neutral(), model, RHO)
		var global_rate := _moment_derivative(global_plus, global_minus, model)
		var transferred: float = float(model.aero.Cmq) + float(model.aero.CLq) * (arm_x * cos(alpha) + arm_z * sin(alpha)) / c
		check("global ARP-to-reference-CG identity at %.0f degrees" % alpha_deg,
			absf(global_rate - transferred) < IDENTITY_TOLERANCE,
			"measured=%.9f transferred=%.9f" % [global_rate, transferred])
		if alpha_deg == 0.0:
			check("reference-CG damping equals independent tail-volume build-up",
				absf(global_rate - target) < TARGET_TOLERANCE,
				"measured=%.9f target=%.9f" % [global_rate, target])
		# This comparison is diagnostic. Local flow is a separate model with
		# strip/tail geometry and need not equal the global datum identity.
		var local_plus := Aero._local_loads(plus, air, _neutral(), model, RHO)
		var local_minus := Aero._local_loads(minus, air, _neutral(), model, RHO)
		var local_rate := _moment_derivative(local_plus, local_minus, model)
		check("local/global comparison is finite at %.0f degrees" % alpha_deg,
			is_finite(local_rate) and is_finite(global_rate),
			"local=%.9f global=%.9f" % [local_rate, global_rate])


func _session_checks(path: String, model: Dictionary, target: float) -> void:
	var flight := Flight.new()
	flight.input_enabled = false
	flight.setup(path, AIRCRAFT_ID)
	root.add_child(flight)
	flight.set_physics_process(false)
	flight.sim.set_physics_process(false)
	var ready: bool = flight.is_flyable() and flight.liquid_fuel_is_active()
	check("finite-liquid Avanti session prepares", ready)
	if not ready:
		flight.free()
		return
	var index: int = flight._liquid_index()
	var config: Dictionary = flight.aircraft.model.propulsion.liquid_fuel
	var plus := _state(0.0, RATE_STEP)
	var minus := _state(0.0, -RATE_STEP)
	var air := Air.compute(plus, M.v3(0.0, 0.0, 0.0), RHO)
	var d: Dictionary = flight._deflections(flight.sim.aux)
	var global_plus := Aero._global_loads(plus, air, d, model, RHO)
	var global_minus := Aero._global_loads(minus, air, d, model, RHO)
	var global_rate := _moment_derivative(global_plus, global_minus, model)
	check("session probe is in the attached global regime",
		Aero.local_flow_weight(plus, air, d, model) == 0.0 and Aero.local_flow_weight(minus, air, d, model) == 0.0)
	var observed := []
	var shifts := []
	for fraction: float in [1.0, 0.5, 0.0]:
		var values: PackedFloat64Array = flight.sim.continuous.duplicate()
		values[0] = 0.0 # Engine stopped: no turbine thrust contributes to the probe.
		values[index] = fraction * (float(config.capacity_kg) - float(config.unusable_kg))
		values[index + 1] = 0.0
		var properties: Dictionary = LiquidFlight.properties(flight, values)
		var base := values.slice(0, index)
		var before_plus: Dictionary = flight._turbine_evaluate(plus, base, 0.0, properties, false)
		var before_minus: Dictionary = flight._turbine_evaluate(minus, base, 0.0, properties, false)
		var after_plus: Dictionary = LiquidFlight.evaluate(plus, values, 0.0, flight)
		var after_minus: Dictionary = LiquidFlight.evaluate(minus, values, 0.0, flight)
		var valid: bool = properties.get("ok", false) and not before_plus.is_empty() and not before_minus.is_empty() \
			and not after_plus.is_empty() and not after_minus.is_empty()
		check("finite-liquid stage evaluates at %.0f%% usable fuel" % (100.0 * fraction), valid)
		if not valid:
			continue
		var raw_plus: PackedFloat64Array = before_plus.loads
		var raw_minus: PackedFloat64Array = before_minus.loads
		var live_plus: PackedFloat64Array = after_plus.loads
		var live_minus: PackedFloat64Array = after_minus.loads
		var raw_rate := _moment_derivative(raw_plus, raw_minus, model)
		var live_rate := _moment_derivative(live_plus, live_minus, model)
		var force_delta := M.sub(raw_plus.slice(0, 3), raw_minus.slice(0, 3))
		var shift := M.cross(properties.cg_body_m, force_delta)
		var delta := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, -shift[1], 0.0])
		var transfer_rate := _moment_derivative(delta, PackedFloat64Array([0, 0, 0, 0, 0, 0]), model)
		check("live-CG shift transfers the stage force once at %.0f%% fuel" % (100.0 * fraction),
			absf(live_rate - (raw_rate + transfer_rate)) < IDENTITY_TOLERANCE,
			"live=%.9f fixed=%.9f shift=%.9f" % [live_rate, raw_rate, transfer_rate])
		# Other stage terms, including a held downwash state and gear, are
		# measured separately. They are not attributed to the datum correction.
		var other_rate: float = raw_rate - global_rate
		check("live stage retains the independent pitch build-up at %.0f%% fuel" % (100.0 * fraction),
			absf(live_rate - (target + other_rate + transfer_rate)) < TARGET_TOLERANCE,
			"live=%.9f target+other+shift=%.9f other=%.9f" % [live_rate, target + other_rate + transfer_rate, other_rate])
		observed.append(live_rate - other_rate)
		shifts.append(transfer_rate)
	if observed.size() == 3:
		check("fuel shift changes pitch derivative with fixed-datum air state",
			absf(shifts[0] - shifts[2]) > 0.05 and absf(observed[0] - observed[2]) > 0.05,
			"full=%.9f empty=%.9f" % [observed[0], observed[2]])
	flight.free()
