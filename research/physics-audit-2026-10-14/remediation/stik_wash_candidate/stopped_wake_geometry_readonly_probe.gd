## Read-only current-runtime probe for the transported stopped-wake geometry gate.
## Run with Godot --headless --path app --audio-driver Dummy --script <absolute path>.
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const M := preload("res://physics/math3d.gd")
const Slipstream := preload("res://physics/slipstream.gd")

const RHO := 1.225
const BODY_CROSSFLOW := 10.0

var _model: Dictionary = {}


func _initialize() -> void:
	var candidate_path := ProjectSettings.globalize_path(
		"res://../research/physics-audit-2026-10-14/remediation/stik_wash_candidate/aircraft_v2.json")
	var result: Dictionary = AD.load_file(candidate_path)
	if not result.get("ok", false):
		push_error("candidate aircraft load failed: %s" % str(result.get("errors", [])))
		quit(1)
		return
	_model = result.model
	call_deferred("_run")


func _run() -> void:
	var rows: Array[Dictionary] = []
	var transported_dv := PackedFloat64Array([2.0, 2.0, 2.0])
	for vx in [0.999e-6, 1.0e-6, 1.001e-6]:
		var state := PackedFloat64Array([0.0, 0.0, -100.0, vx, BODY_CROSSFLOW, 0.0,
			1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
		var air: Dictionary = Air.compute(state, M.v3(0.0, 0.0, 0.0), RHO)
		var rates := {elevator=0.0, rudder=0.0, aileron_left=0.0, aileron_right=0.0}
		var loads: PackedFloat64Array = Slipstream.loads(state, air, rates, _model, 0.0, RHO,
			NAN, transported_dv)
		var wake: Dictionary = Slipstream.wake(air.v_air, 0.0, 0.0, _model.propulsion, RHO)
		var speed := sqrt(air.v_air[0] * air.v_air[0] + air.v_air[1] * air.v_air[1] + air.v_air[2] * air.v_air[2])
		var load_array := Array(loads)
		rows.append({
			"vx_body_mps": vx,
			"vy_body_mps": BODY_CROSSFLOW,
			"speed_mps": speed,
			"wake_v_s_mps": wake.vs,
			"transported_dv_mps": Array(transported_dv),
			"drift_gate_expected": speed > 1e-6 and float(wake.vs) > 1e-6,
			"slipstream_loads_Fx_Fy_Fz_Mx_My_Mz": load_array,
		})
	var left: Array = rows[0].slipstream_loads_Fx_Fy_Fz_Mx_My_Mz
	var right: Array = rows[2].slipstream_loads_Fx_Fy_Fz_Mx_My_Mz
	var delta := PackedFloat64Array()
	delta.resize(6)
	var force_norm2 := 0.0
	var moment_norm2 := 0.0
	for i in 6:
		delta[i] = float(right[i]) - float(left[i])
		if i < 3:
			force_norm2 += delta[i] * delta[i]
		else:
			moment_norm2 += delta[i] * delta[i]
	print(JSON.stringify({
		"record": "r06_stopped_transported_wake_geometry_threshold_readonly",
		"candidate_id": _model.id,
		"rho_kg_m3": RHO,
		"rpm": 0.0,
		"body_crossflow_mps": BODY_CROSSFLOW,
		"speed_gate_and_wake_speed_gate": "drifts = speed > 1e-6 and wake.vs > 1e-6",
		"samples": rows,
		"plus_minus_threshold_load_delta": Array(delta),
		"plus_minus_threshold_force_delta_norm_n": sqrt(force_norm2),
		"plus_minus_threshold_moment_delta_norm_nm": sqrt(moment_norm2),
		"interpretation_limit": "This isolates the current instantaneous drift predicate with a candidate transported wake held nonzero; it does not model a transported wake center or establish the physically correct reversal law."
	}))
	quit()
