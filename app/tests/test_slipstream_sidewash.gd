# P51-26: the legacy slipstream's opt-in piecewise swirl quadrature and Ribner sidewash (propeller_sidewash), on the P-51.
# Checks the allocation-free tail law against Aero's, the segment bookkeeping against the legacy centroid without swirl,
# smooth powered yaw in sideslip (the defect it removes), Ribner's bounds, the zero-flow limit and the loader gates.
# Software verification of the stated law only; no measured slipstream data is claimed.
extends SceneTree
const AD = preload("res://physics/aircraft_data.gd")
const Aero = preload("res://physics/aero.gd")
const Air = preload("res://physics/air_data.gd")
const Slipstream = preload("res://physics/slipstream.gd")
const Propulsion = preload("res://physics/propulsion.gd")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const PATH := "res://data/aircraft/p51d_mustang_120.json"
const RHO: float = 1.225
const D0 := { elevator = -0.03, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.05 }
var _checks: int = 0
var _failed: int = 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	print("%s %s %s" % ["ok" if condition else "FAIL", label, detail])
	if not condition:
		_failed += 1


func _initialize() -> void:
	var loaded: Dictionary = AD.load_file(PATH)
	_check("P-51 loads with the P51-26 slipstream", loaded.ok and loaded.model.propulsion.slipstream.has("propeller_sidewash"), str(loaded.get("errors", "")))
	if not loaded.ok:
		quit(1)
		return
	var model: Dictionary = loaded.model
	_loader_gates()
	_tail_law(model)
	_segments_without_swirl(model)
	_smooth_yaw(model)
	_ribner(model)
	_zero_flow(model)
	print("P51-26 slipstream: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed else 0)


static func _raw() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(PATH))


func _loader_gates() -> void:
	var raw := _raw()
	raw.propulsion.propeller.slipstream.propeller_sidewash.value = 1.5
	var out: Dictionary = AD.validate_and_derive(raw)
	_check("loader rejects a sidewash gain above the published 1", not out.ok and str(out.errors).contains("propeller_sidewash"), str(out.errors))
	raw = _raw()
	raw.propulsion.propeller.slipstream.transport_speed_floor = {value = 1.0, unit = "m/s", kind = "estimated", source = "test"}
	out = AD.validate_and_derive(raw)
	_check("loader rejects it with axial transport", not out.ok and str(out.errors).contains("propeller_sidewash"), str(out.errors))


func _tail_law(model: Dictionary) -> void:
	var worst := 0.0
	var flows: Array = [M.v3(28.0, 1.5, 2.0), M.v3(12.0, -4.0, 6.0), M.v3(5.0, 3.0, -9.0), M.v3(-6.0, 1.0, 2.0),
		M.v3(0.0, 0.0, 3.0), M.v3(0.0, 0.0, 0.0), M.v3(40.0, -0.3, 0.1)]
	for surface: String in ["horizontal", "vertical"]:
		var tail: Dictionary = model.surfaces[surface]
		var vertical := surface == "vertical"
		for wake: float in [0.0, 2.7]:
			var law := Slipstream._tail_law(tail, model.surfaces, D0, vertical, wake, RHO)
			for flow: PackedFloat64Array in flows:
				var arm := M.v3(-1.21, 0.13, -0.24)
				var want := Aero._tail_surface_from_flow(flow, arm, D0, tail, model.surfaces, 0.07, vertical, RHO, wake)
				var got := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
				Slipstream._add_tail_load(got, law, 1.0, flow[0], flow[1], flow[2], arm[0], arm[1], arm[2], 0.07)
				for c in 6:
					worst = maxf(worst, absf(got[c] - want[c]) / maxf(absf(want[c]), 1e-3))
	_check("allocation-free tail law equals Aero._tail_surface_from_flow (relative < 1e-12)", worst < 1e-12, str(worst))


static func _state(V: float, alpha: float, beta: float, rates := PackedFloat64Array([0.0, 0.0, 0.0])) -> PackedFloat64Array:
	return RB.make_state(M.v3(0, 0, -100), M.v3(V * cos(alpha) * cos(beta), V * sin(beta), V * sin(alpha) * cos(beta)),
		M.q_identity(), rates)


static func _loads(model: Dictionary, s: PackedFloat64Array, rpm: float) -> PackedFloat64Array:
	return Slipstream.loads(s, Air.compute(s, M.v3(0, 0, 0), RHO), D0, model, rpm, RHO, 1.5)


func _segments_without_swirl(model: Dictionary) -> void:
	# Without swirl and sidewash, splitting changes only where each part's load acts: forces equal the legacy centroid's.
	var segmented: Dictionary = model.duplicate(true)
	segmented.propulsion.slipstream.swirl_factor = 0.0
	segmented.propulsion.slipstream.propeller_sidewash = 0.0
	var legacy: Dictionary = segmented.duplicate(true)
	legacy.propulsion.slipstream.erase("propeller_sidewash")
	var worst := 0.0
	for V: float in [8.0, 20.0, 32.0]:
		for beta_deg: float in [-4.0, 0.0, 3.0]:
			var s := _state(V, deg_to_rad(5.0), deg_to_rad(beta_deg))
			var a := _loads(segmented, s, 5200.0)
			var b := _loads(legacy, s, 5200.0)
			for c in 3:
				worst = maxf(worst, absf(a[c] - b[c]) / maxf(absf(b[c]), 1e-2))
	_check("no swirl, no sidewash: segmented forces equal the legacy centroid (relative < 1e-9)", worst < 1e-9, str(worst))


func _smooth_yaw(model: Dictionary) -> void:
	# The defect: one swirl sample per piece put the powered slipstream Cnβ off a converged integral by up to ×2 and made it
	# erratic in speed. The segmented law converges at second order: within 1.5 % of 64 subdivisions per segment (1.05 %
	# measured at 18 m/s, 0.2 % at 45 m/s) and at least 2.5x closer with two subdivisions.
	var legacy: Dictionary = model.duplicate(true)
	legacy.propulsion.slipstream.erase("propeller_sidewash")
	var worst := 0.0
	var worst_legacy := 0.0
	var converging := true
	var step := deg_to_rad(0.5)
	for V: float in [18.0, 22.0, 25.7, 28.6, 35.0, 45.0]:
		var s0 := _state(V, deg_to_rad(4.0), 0.0)
		var air0 := Air.compute(s0, M.v3(0, 0, 0), RHO)
		var rpm := Propulsion.steady_rpm(0.6, M.dot(air0.v_air, Propulsion.axis(model.propulsion)), model.propulsion, RHO, 1.0)
		var sp := _state(V, deg_to_rad(4.0), step)
		var sm := _state(V, deg_to_rad(4.0), -step)
		var cn := _yaw(model, sp, sm, rpm, 1)
		var dense := _yaw(model, sp, sm, rpm, 64)
		var centroid := _yaw(legacy, sp, sm, rpm, 1)
		worst = maxf(worst, absf(cn - dense) / absf(dense))
		converging = converging and absf(_yaw(model, sp, sm, rpm, 2) - dense) * 2.5 <= absf(cn - dense)
		worst_legacy = maxf(worst_legacy, absf(centroid - dense) / absf(dense))
	print("info slipstream yaw per sideslip against 64 subdivisions: segmented %.4f, legacy centroid %.4f (relative)" % [worst, worst_legacy])
	_check("powered slipstream yaw per sideslip within 1.5 % of the dense integral and converging, 18-45 m/s", worst < 0.015 and converging,
		"%s, converging %s" % [worst, converging])


static func _yaw(model: Dictionary, sp: PackedFloat64Array, sm: PackedFloat64Array, rpm: float, subdivisions: int) -> float:
	var plus := Slipstream.loads(sp, Air.compute(sp, M.v3(0, 0, 0), RHO), D0, model, rpm, RHO, 1.5, PackedFloat64Array(), subdivisions)
	var minus := Slipstream.loads(sm, Air.compute(sm, M.v3(0, 0, 0), RHO), D0, model, rpm, RHO, 1.5, PackedFloat64Array(), subdivisions)
	return plus[5] - minus[5]


func _ribner(model: Dictionary) -> void:
	var prop: Dictionary = model.propulsion
	var ax := Propulsion.axis(prop)
	var axial := M.scale(ax, 22.0)
	var rpm := Propulsion.steady_rpm(1.0, 22.0, prop, RHO, 1.0)
	var tq := Propulsion.thrust_torque(axial, rpm, prop, RHO)
	var w := Slipstream.wake(axial, tq[0], tq[1], prop, RHO)
	var along := Slipstream.sidewash(axial, rpm, prop, w, ax, RHO, 1.0)
	_check("Ribner sidewash vanishes without crossflow", M.norm(along) < 1e-12, str(M.norm(along)))
	var bounded := true
	for inflow: float in [0.0, 0.05, 0.3, 1.0, 5.0, 50.0]:
		var k := 1.0 + 2.0 * inflow
		var g := 2.0 * (1.0 + inflow) * k / (1.0 + k * k)
		var h := k * (2.0 + 2.0 * inflow) / (1.0 + k * k)
		bounded = bounded and g >= 1.0 - 1e-12 and g <= 1.21 and h >= 1.0 - 1e-12 and h <= 1.21
	_check("Ribner's g(a) and h(a) stay within 1.0-1.21 for a = 0-50", bounded)
	var worst := 0.0
	for V: float in [0.0, 1e-6, 0.5, 3.0]:
		var v := M.v3(V * 0.8, V * 0.6, 0.0)
		var rpm0 := Propulsion.steady_rpm(1.0, M.dot(v, ax), prop, RHO, 1.0)
		var t0 := Propulsion.thrust_torque(v, rpm0, prop, RHO)
		var w0 := Slipstream.wake(v, t0[0], t0[1], prop, RHO)
		worst = maxf(worst, M.norm(Slipstream.sidewash(v, rpm0, prop, w0, ax, RHO, 1.0)) / maxf(V, 1e-9))
	_check("Ribner sidewash stays below the crossflow scale at static thrust (|Δv| < 1.5 V)", worst < 1.5, str(worst))


func _zero_flow(model: Dictionary) -> void:
	var rpm := Propulsion.steady_rpm(1.0, 0.0, model.propulsion, RHO, 1.0)
	var rest := _loads(model, RB.make_state(M.v3(0, 0, -100), M.v3(0, 0, 0), M.q_identity(), M.v3(0, 0, 0)), rpm)
	var worst := 0.0
	for direction: PackedFloat64Array in [M.v3(1, 0, 0), M.v3(-1, 0, 0), M.v3(0, 0, 1), M.v3(0, 0, -1), M.v3(0, 1, 0),
			M.v3(0.6, 0.0, 0.8), M.v3(-0.6, 0.0, 0.8), M.v3(0.577, -0.577, 0.577)]:
		var near := _loads(model, RB.make_state(M.v3(0, 0, -100), M.scale(direction, 1e-8), M.q_identity(), M.v3(0, 0, 0)), rpm)
		for c in 6:
			worst = maxf(worst, absf(near[c] - rest[c]))
	_check("full-power zero-flow limit is unique from every direction (|Δ| < 1e-6 N, N·m)", worst < 1e-6, str(worst))
