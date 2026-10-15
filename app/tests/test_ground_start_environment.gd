## R04 regression for state-dependent density in runway residuals.
## Run with the pinned Godot binary from the repository root:
##   godot --headless --path app --script res://tests/test_ground_start_environment.gd
extends SceneTree

const RB := preload("res://physics/rigid_body.gd")
const Aero := preload("res://physics/aero.gd")
const Commands := preload("res://input/commands.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const GroundStart := preload("res://physics/ground_start.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")

const AIRCRAFT_PATH := "res://data/aircraft/sebart_avanti_s_a200.json"
const RHO := 1.225
const G := 9.80665

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		_failures += 1


func _min(values: Array) -> float:
	var result := INF
	for value: float in values:
		result = minf(result, value)
	return result


func _max(values: Array) -> float:
	var result := -INF
	for value: float in values:
		result = maxf(result, value)
	return result


func _initialize() -> void:
	var field_result := FieldLoader.load_from()
	var table_result := GroundSurfaces.load_table()
	if not field_result.ok or not table_result.ok:
		printerr("setup failed: field=%s surfaces=%s" % [str(field_result), str(table_result)])
		quit(2)
		return
	var field: Dictionary = field_result.field
	var ground_result := GroundSurfaces.build(table_result.table, field)
	var spot := GroundStart.threshold(field)
	var loaded := AircraftData.load_file(AIRCRAFT_PATH)
	if not ground_result.ok or not spot.ok or not loaded.ok:
		printerr("model/runway setup failed: ground=%s spot=%s aircraft=%s" % [
			str(ground_result), str(spot), str(loaded.errors)])
		quit(2)
		return
	var model: Dictionary = loaded.model
	var gear: Dictionary = model.landing_gear
	var deflections := Aero.deflections_from_surfaces(
		Commands.surface_deflections_deg(Commands.neutral_commands(), model.controls.throw_deg))
	var rpm: float = Propulsion.steady_rpm(0.0, 0.0, model.propulsion, RHO, 1.0)
	var wind := PackedFloat64Array([-1.5, 0.0, 0.0])
	var enhanced: bool = model.get("wheel_profile", {}).get("status") == "applied"
	var observations := {"count": 0, "down": [], "rho": []}
	var environment_at_state: Callable = func(state: PackedFloat64Array) -> Dictionary:
		var down: float = state[RB.POS + 2]
		var density := RHO + 0.2 * (down + 0.22)
		observations["count"] = int(observations["count"]) + 1
		observations["down"].append(down)
		observations["rho"].append(density)
		return {"ok": true, "rho_kgm3": density}
	var dynamic: Dictionary = GroundStart.solve(model, ground_result.rects, float(spot.north), float(spot.east),
		float(spot.heading), deflections, 0.0, rpm, RHO, G, wind, enhanced, environment_at_state)
	var fixed: Dictionary = GroundStart.solve(model, ground_result.rects, float(spot.north), float(spot.east),
		float(spot.heading), deflections, 0.0, rpm, RHO, G, wind, enhanced)
	_check("state-density runway candidate converges", dynamic.ok, str(dynamic.get("message", "")))
	_check("legacy scalar-density candidate converges", fixed.ok, str(fixed.get("message", "")))
	if dynamic.ok and fixed.ok:
		var environment: Dictionary = dynamic.diagnostics.environment
		var sampled_down: Array = observations["down"]
		var sampled_rho: Array = observations["rho"]
		var down_range := _max(sampled_down) - _min(sampled_down) if not sampled_down.is_empty() else 0.0
		var rho_range := _max(sampled_rho) - _min(sampled_rho) if not sampled_rho.is_empty() else 0.0
		_check("callback queried every residual state", int(environment.queries) == int(observations.count),
			"diagnostic %d, observed %d" % [int(environment.queries), int(observations.count)])
		_check("density follows the changing candidate height", down_range > 0.0 and rho_range > 0.0,
			"down span %s m; rho span %s kg/m^3" % [str(down_range), str(rho_range)])
		_check("callback density extrema are recorded",
			is_equal_approx(float(environment.minimum_rho_kgm3), _min(sampled_rho))
			and is_equal_approx(float(environment.maximum_rho_kgm3), _max(sampled_rho)))
		_check("residual evaluation cap holds with environment callback",
			int(dynamic.diagnostics.total_residual_evaluations) <= GroundStart.MAX_RESIDUAL_EVALUATIONS)

		var local_rho := RHO + 0.2 * (float(dynamic.state[RB.POS + 2]) + 0.22)
		var inv := RB.inertia_inverse(model.inertia)
		var local_accels: PackedFloat64Array = GroundStart._accelerations(dynamic.state, model, inv, gear,
			ground_result.rects, deflections, 0.0, rpm, local_rho, G, dynamic.anchors, true, wind, enhanced)
		var fixed_accels: PackedFloat64Array = GroundStart._accelerations(dynamic.state, model, inv, gear,
			ground_result.rects, deflections, 0.0, rpm, RHO, G, dynamic.anchors, true, wind, enhanced)
		_check("accepted fixed point uses the local queried density",
			GroundStart._norm(local_accels) < 1.0e-8 and GroundStart._norm(fixed_accels) > GroundStart._norm(local_accels) + 1.0e-10,
			"local %s, legacy-density %s m/s²/rad/s²" % [str(GroundStart._norm(local_accels)), str(GroundStart._norm(fixed_accels))])

	var rejected_environment: Callable = func(_state: PackedFloat64Array) -> Dictionary:
		return {"ok": false, "errors": ["outside test atmosphere domain"]}
	var rejected: Dictionary = GroundStart.solve(model, ground_result.rects, float(spot.north), float(spot.east),
		float(spot.heading), deflections, 0.0, rpm, RHO, G, wind, enhanced, rejected_environment)
	var rejection_diagnostics: Dictionary = rejected.get("diagnostics", {})
	_check("environment domain error rejects without scalar fallback",
		not rejected.get("ok", false) and str(rejected.get("message", "")).contains("outside test atmosphere domain"),
		str(rejected.get("message", "")))
	_check("environment domain error returns no partial candidate",
		rejected.get("state", PackedFloat64Array()).is_empty()
		and rejected.get("rest_state", PackedFloat64Array()).is_empty()
		and rejected.get("anchors", PackedFloat64Array()).is_empty())
	_check("environment domain error remains within evaluation cap",
		int(rejection_diagnostics.get("total_residual_evaluations", INF)) <= GroundStart.MAX_RESIDUAL_EVALUATIONS)

	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
