# M5-ATM-2: fixed-density trim and explicit engine charge ratio reach their separate physics paths.
extends SceneTree

const M = preload("res://physics/math3d.gd")
const Air = preload("res://physics/air_data.gd")
const AD = preload("res://physics/aircraft_data.gd")
const Trim = preload("res://physics/trim.gd")
const Scenarios = preload("res://sim/scenarios.gd")
const Dynamics = preload("res://physics/dynamics.gd")
const G: float = 9.80665
const AIRCRAFT_PATHS: Array[String] = [
	"res://data/aircraft/jensen_ugly_stik_60.json",
	"res://data/aircraft/gp_extra_300s_60.json",
	"res://data/aircraft/p51d_mustang_120.json",
	"res://data/aircraft/sebart_avanti_s_a200.json",
]

var checks: int = 0
var failures: int = 0


func check(label: String, passed: bool, detail: String = "") -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	for path in AIRCRAFT_PATHS:
		var loaded: Dictionary = AD.load_file(path)
		check(path + " loads", loaded.ok)
		if not loaded.ok:
			continue
		var model: Dictionary = loaded.model
		var speed: float = model.start_speed
		var throws: Dictionary = model.controls.throw_rad
		var implicit_level: Dictionary = Trim.solve("level", speed, model, G, throws)
		var explicit_level: Dictionary = Trim.solve("level", speed, model, G, throws, Air.RHO_SEA_LEVEL, 1.0)
		check(path + " level implicit default matches explicit default bytes", var_to_bytes(implicit_level) == var_to_bytes(explicit_level))
		var implicit_glide: Dictionary = Trim.solve("glide", speed, model, G, throws)
		var explicit_glide: Dictionary = Trim.solve("glide", speed, model, G, throws, Air.RHO_SEA_LEVEL, 1.0)
		check(path + " glide implicit default matches explicit default bytes", var_to_bytes(implicit_glide) == var_to_bytes(explicit_glide))

	var model: Dictionary = AD.load_file("res://data/aircraft/jensen_ugly_stik_60.json").model
	var throws: Dictionary = model.controls.throw_rad
	var custom: Dictionary = Trim.solve("level", 15.0, model, G, throws, 1.0, 1.0)
	check("custom positive density is accepted while requested TAS stays 15 m/s", custom.V == 15.0 and custom.ok, custom.message)
	for bad_rho in [NAN, INF, -INF, 0.0, -1.0]:
		var refused: Dictionary = Trim.solve("level", 15.0, model, G, throws, bad_rho)
		check("invalid density " + str(bad_rho) + " returns numerical failure with reason", not refused.ok and not refused.message.is_empty())
	check("scenario propagates invalid density refusal", not Scenarios.trimmed_level_across_view(model, G, throws, 15.0, 0.0).ok)
	check("scenario propagates invalid engine charge ratio", not Scenarios.trimmed_level_across_view(model, G, throws, 15.0, Air.RHO_SEA_LEVEL, NAN).ok)
	for bad_charge in [NAN, INF, -INF, -1.0]:
		var refused_charge: Dictionary = Trim.solve("level", 15.0, model, G, throws, Air.RHO_SEA_LEVEL, bad_charge)
		check("invalid engine charge ratio " + str(bad_charge) + " returns numerical failure", not refused_charge.ok and not refused_charge.message.is_empty())
	var too_slow: Dictionary = Trim.solve("level", 5.0, model, G, throws, Air.RHO_SEA_LEVEL * 0.78)
	check("below-domain TAS is refused at reduced density", not too_slow.ok and not too_slow.message.is_empty(), too_slow.message)

	var sigma: float = 0.78
	var rho: float = Air.RHO_SEA_LEVEL * sigma
	var base_speed: float = 15.0
	var scaled_speed: float = base_speed / M.sqrt_(sigma)
	var base_glide: Dictionary = Trim.solve("glide", base_speed, model, G, throws)
	var scaled_glide: Dictionary = Trim.solve("glide", scaled_speed, model, G, throws, rho, 1.0)
	check("density-scaled glide converges at true airspeed V/sqrt(sigma)", base_glide.ok and scaled_glide.ok, scaled_glide.message)
	if base_glide.ok and scaled_glide.ok:
		check("equal dynamic pressure preserves trimmed alpha", absf(base_glide.alpha - scaled_glide.alpha) < 1e-8)
		check("equal dynamic pressure preserves glide angle", absf(base_glide.gamma - scaled_glide.gamma) < 1e-8)
		var q_base: float = Air.compute(base_glide.state, M.v3(0.0, 0.0, 0.0)).qbar
		var q_scaled: float = Air.compute(scaled_glide.state, M.v3(0.0, 0.0, 0.0), rho).qbar
		check("scaled TAS and density preserve qbar", absf(q_base - q_scaled) < 1e-10, "%.12f vs %.12f Pa" % [q_base, q_scaled])
		var d: Dictionary = { elevator = base_glide.elevator, aileron_right = base_glide.aileron,
			aileron_left = -base_glide.aileron, rudder = base_glide.rudder }
		var zero_wind: PackedFloat64Array = M.v3(0.0, 0.0, 0.0)
		var force_base: Dictionary = Dynamics.evaluate(base_glide.state, model, d, base_glide.rpm, Air.RHO_SEA_LEVEL, zero_wind, G)
		var force_scaled: Dictionary = Dynamics.evaluate(scaled_glide.state, model, d, scaled_glide.rpm, rho, zero_wind, G)
		var force_error: float = 0.0
		for i in 6:
			force_error = maxf(force_error, absf(force_base.loads[i] - force_scaled.loads[i]))
		check("equal qbar preserves total flight loads", force_error < 1e-8, String.num_scientific(force_error))
		check("both equivalent glides satisfy six-axis residual tolerance", base_glide.residual < 1e-8 and scaled_glide.residual < 1e-8)
		var same_tas_glide: Dictionary = Trim.solve("glide", base_speed, model, G, throws, rho, 1.0)
		check("same-TAS lower-density Stik glide requires a higher alpha", same_tas_glide.ok and same_tas_glide.alpha > base_glide.alpha, same_tas_glide.message)
		var scenario: Dictionary = Scenarios.trimmed_glide_across_view(model, G, throws, scaled_speed, rho, 1.0)
		check("scenario adapter forwards custom density and keeps the requested TAS", scenario.ok and scenario.V == scaled_speed and absf(scenario.alpha - scaled_glide.alpha) < 1e-8, scenario.message)

	var p51: Dictionary = AD.load_file("res://data/aircraft/p51d_mustang_120.json").model
	var p51_throws: Dictionary = p51.controls.throw_rad
	var p51_base: Dictionary = Trim.solve("level", 27.0, p51, G, p51_throws, 1.0, 1.0)
	var p51_low_charge: Dictionary = Trim.solve("level", 27.0, p51, G, p51_throws, 1.0, 0.8)
	check("explicit engine charge ratio changes the P-51 shaft throttle trim", p51_base.ok and p51_low_charge.ok and absf(p51_base.throttle - p51_low_charge.throttle) > 1e-6, p51_low_charge.message)
	var p51_scenario: Dictionary = Scenarios.trimmed_level_across_view(p51, G, p51_throws, 27.0, 1.0, 0.8)
	check("scenario forwards P-51 density and explicit charge ratio", p51_scenario.ok and absf(p51_scenario.rpm - p51_low_charge.rpm) < 1e-8 and absf(p51_scenario.throttle - p51_low_charge.throttle) < 1e-8, p51_scenario.message)

	print("M5-ATM-2 trim density: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
