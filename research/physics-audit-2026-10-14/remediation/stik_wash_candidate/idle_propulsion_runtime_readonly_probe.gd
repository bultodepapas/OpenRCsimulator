## Calls current production propulsion/wake APIs on the isolated R06 candidate.
## Run with Godot --headless --path app --audio-driver Dummy --script <absolute path>.
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Slipstream := preload("res://physics/slipstream.gd")

const RHO := 1.225
const IDLE_RPM := 2800.0


func _initialize() -> void:
	var candidate_path := ProjectSettings.globalize_path(
		"res://../research/physics-audit-2026-10-14/remediation/stik_wash_candidate/aircraft_v2.json")
	var result: Dictionary = AD.load_file(candidate_path)
	if not result.get("ok", false):
		push_error("candidate aircraft load failed: %s" % str(result.get("errors", [])))
		quit(1)
		return
	var model: Dictionary = result.model
	var propulsion: Dictionary = model.propulsion
	var prop: Dictionary = propulsion
	var ct_floor := -0.1
	var cp_floor := minf(0.0, float(prop.get("cp_min", 0.0)))
	var rows: Array[Dictionary] = []
	for speed in [15.0, 29.0]:
		var velocity := PackedFloat64Array([speed, 0.0, 0.0])
		var tq: PackedFloat64Array = Propulsion.thrust_torque(velocity, IDLE_RPM, prop, RHO)
		var J: float = tq[2]
		var ct_raw: float = Propulsion.coefficient(prop.ct, J, -INF)
		var cp_raw: float = Propulsion.coefficient(prop.cp, J, -INF)
		var ct_used: float = Propulsion.coefficient(prop.ct, J, ct_floor)
		var cp_used: float = Propulsion.coefficient(prop.cp, J, cp_floor)
		var wake: Dictionary = Slipstream.wake(velocity, tq[0], tq[1], prop, RHO)
		rows.append({
			"speed_mps": speed,
			"rho_kg_m3": RHO,
			"rpm": IDLE_RPM,
			"advance_ratio_J": J,
			"ct_raw_linear_extrapolation": ct_raw,
			"ct_used_after_production_floor": ct_used,
			"cp_raw_linear_extrapolation": cp_raw,
			"cp_used_after_production_floor": cp_used,
			"thrust_n": tq[0],
			"shaft_torque_nm": tq[1],
			"wake_u_mps": wake.u,
			"wake_w_mps": wake.w,
			"wake_kw_factor_at_negative_induced_flow": prop.slipstream.wash_factor[1],
			"tail_wash_increment_dv_mps": wake.dv,
		})
	print(JSON.stringify({
		"record": "r06_current_production_idle_propulsion_runtime",
		"candidate_id": model.id,
		"table_max_J": maxf(float(prop.ct[prop.ct.size() - 2]), float(prop.cp[prop.cp.size() - 2])),
		"source_contract": "direct calls to current Propulsion.thrust_torque/coefficient and Slipstream.wake",
		"rows": rows,
		"interpretation_limit": "The high-J values are table extrapolations; CP flooring to zero means this is not a power-balanced windmilling prediction."
	}))
	quit()
