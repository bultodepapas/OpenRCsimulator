## Bounded level trim at a caller-selected throttle, plus independent dynamics and rollout checks.
## Run: godot --headless --path . --script res://tests/test_cruise_trim.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const RK := preload("res://physics/integrator.gd")
const Air := preload("res://physics/air_data.gd")
const AD := preload("res://physics/aircraft_data.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const CruiseTrim := preload("res://physics/cruise_trim.gd")

const G := 9.80665
const REFERENCE_SPEED_MPS := 15.0
const TARGET_THROTTLE := 0.5
const MAX_SPEED_MPS := 30.0
const THROWS := { elevator = deg_to_rad(20.0), aileron = deg_to_rad(20.0), rudder = deg_to_rad(25.0) }

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print("%s %s%s" % ["ok   " if ok else "FAIL ", label, "" if detail.is_empty() else "  " + detail])
	if not ok:
		_failures += 1


func _solve(model: Dictionary, speed := REFERENCE_SPEED_MPS, throttle := TARGET_THROTTLE,
		max_speed := MAX_SPEED_MPS, max_alpha := CruiseTrim.DEFAULT_MAX_ALPHA_RAD) -> Dictionary:
	return CruiseTrim.solve_level_at_throttle(speed, throttle, max_speed, model, G, THROWS,
		Air.RHO_SEA_LEVEL, 1.0, max_alpha)


func _initialize() -> void:
	var loaded: Dictionary = AD.load_file("res://data/aircraft/jensen_ugly_stik_60.json")
	_check("Ugly Stik loader model is valid", loaded.get("ok", false), str(loaded.get("message", "")))
	if not loaded.get("ok", false):
		quit(1)
		return
	var model: Dictionary = loaded.model

	var trim := _solve(model)
	_check("50% throttle level trim solves", trim.ok, trim.message)
	if trim.ok:
		_check("search stays above reference and within bound", trim.V > REFERENCE_SPEED_MPS and trim.V <= MAX_SPEED_MPS,
			"V %.5f m/s" % trim.V)
		_check("selected throttle reached within 1e-7", absf(trim.throttle - TARGET_THROTTLE) <= 1.0e-7,
			"throttle %.10f" % trim.throttle)
		_check("solution remains on attached branch", absf(trim.alpha) <= CruiseTrim.DEFAULT_MAX_ALPHA_RAD,
			"alpha %.3f deg" % rad_to_deg(trim.alpha))
		_check("trim residual remains small", trim.residual < 1.0e-8,
			"residual %s" % String.num_scientific(trim.residual))
		_check("result retains Trim fields and request metadata", trim.has("state") and trim.state.size() == RB.SIZE
			and trim.reference_speed_mps == REFERENCE_SPEED_MPS and trim.requested_throttle == TARGET_THROTTLE)

		var deflections := {
			elevator = trim.elevator,
			aileron_right = trim.aileron,
			aileron_left = -trim.aileron,
			rudder = trim.rudder,
		}
		var evaluation := Dynamics.evaluate(trim.state, model, deflections, trim.rpm,
			Air.RHO_SEA_LEVEL, M.v3(0.0, 0.0, 0.0), G)
		var derivative: PackedFloat64Array = evaluation.derivative
		var six_axes := PackedFloat64Array([
			derivative[RB.VEL], derivative[RB.VEL + 1], derivative[RB.VEL + 2],
			derivative[RB.RATE], derivative[RB.RATE + 1], derivative[RB.RATE + 2],
		])
		var max_residual := 0.0
		for residual in six_axes:
			max_residual = maxf(max_residual, absf(residual))
		_check("independent six-axis dynamics residual is below 1e-8", max_residual < 1.0e-8,
			"max |acceleration/rate derivative| %s" % String.num_scientific(max_residual))

		var state: PackedFloat64Array = trim.state.duplicate()
		var rhs := func(current: PackedFloat64Array) -> PackedFloat64Array:
			return Dynamics.evaluate(current, model, deflections, trim.rpm, Air.RHO_SEA_LEVEL,
				M.v3(0.0, 0.0, 0.0), G).derivative
		for _step in 5 * 240:
			state = RK.rk4_step(state, 1.0 / 240.0, rhs)
		var position_drift := absf(state[RB.POS + 2] - trim.state[RB.POS + 2])
		var start_speed := M.norm(M.v3(trim.state[RB.VEL], trim.state[RB.VEL + 1], trim.state[RB.VEL + 2]))
		var end_speed := M.norm(M.v3(state[RB.VEL], state[RB.VEL + 1], state[RB.VEL + 2]))
		var rate_drift := 0.0
		for axis in 3:
			rate_drift = maxf(rate_drift, absf(state[RB.RATE + axis]))
		_check("fixed-surface level rollout remains near equilibrium for 5 s",
			position_drift < 0.05 and absf(end_speed - start_speed) < 0.02 and rate_drift < 1.0e-3,
			"altitude drift %.5f m, speed drift %.5f m/s, max rate %s rad/s" % [position_drift, absf(end_speed - start_speed), String.num_scientific(rate_drift)])

	_check("rejects throttle above one", not _solve(model, REFERENCE_SPEED_MPS, 1.01).ok)
	_check("rejects nonfinite throttle", not _solve(model, REFERENCE_SPEED_MPS, NAN).ok)
	_check("rejects nonpositive reference speed", not _solve(model, 0.0).ok)
	_check("rejects maximum speed below reference", not _solve(model, REFERENCE_SPEED_MPS, TARGET_THROTTLE, 14.0).ok)
	_check("rejects maximum speed above hard bound", not _solve(model, REFERENCE_SPEED_MPS, TARGET_THROTTLE, 81.0).ok)
	_check("rejects nonfinite gravity", not CruiseTrim.solve_level_at_throttle(15.0, 0.5, 30.0,
		model, NAN, THROWS).ok)
	_check("rejects nonfinite density", not CruiseTrim.solve_level_at_throttle(15.0, 0.5, 30.0,
		model, G, THROWS, NAN).ok)
	_check("rejects missing trim throws", not CruiseTrim.solve_level_at_throttle(15.0, 0.5, 30.0,
		model, G, { elevator = THROWS.elevator, aileron = THROWS.aileron }).ok)
	_check("rejects an empty model", not CruiseTrim.solve_level_at_throttle(15.0, 0.5, 30.0,
		{}, G, THROWS).ok)

	var too_much_power := _solve(model, REFERENCE_SPEED_MPS, 0.2)
	_check("fails explicitly if reference trim already exceeds target throttle",
		not too_much_power.ok and too_much_power.message.contains("already requires more"), too_much_power.message)
	var too_high_alpha := _solve(model, REFERENCE_SPEED_MPS, TARGET_THROTTLE,
		MAX_SPEED_MPS, deg_to_rad(3.0))
	_check("rejects a trim above the attached-flow alpha limit",
		not too_high_alpha.ok and too_high_alpha.message.contains("angle limit"), too_high_alpha.message)
	var unavailable := _solve(model, 5.0, TARGET_THROTTLE, 10.0)
	_check("propagates unavailable slow-speed trim failure", not unavailable.ok and not unavailable.message.is_empty(), unavailable.message)
	var unbracketed := _solve(model, REFERENCE_SPEED_MPS, 0.99, 20.0)
	_check("fails when maximum speed cannot reach requested throttle",
		not unbracketed.ok and unbracketed.message.contains("not bracketed"), unbracketed.message)

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
