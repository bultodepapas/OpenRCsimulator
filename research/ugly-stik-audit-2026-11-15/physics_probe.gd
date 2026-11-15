# Static production-law diagnostics for the OpenRC Stik physics audit.
# Run using the checked runner from an imported ad210707 checkout:
#   godot --headless --path app --audio-driver Dummy --script /absolute/path/physics_audit_probe.gd
# All states are arbitrary controlled conditions, not trim solutions or flight simulations.
# The caller retains engine/build/input identity and the complete checked output.
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

const RHO := 1.225
const RPM := 10000.0
const PATHS := {
	"basic_stik": "res://data/aircraft/jensen_ugly_stik_60.json",
	"electric_stik_ideal": "res://data/aircraft/stik_electric_6s.json",
	"electric_stik_pack": "res://data/aircraft/battery/stik_electric_6s_pack.json",
	"extra_glow": "res://data/aircraft/gp_extra_300s_60.json",
}
const NEUTRAL := {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}
const RUDDER := {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = -0.17453292519943295}


func _initialize() -> void:
	var models := {}
	var identities := {}
	for name: String in PATHS:
		var loaded: Dictionary = AD.load_file(PATHS[name])
		if not loaded.get("ok", false):
			printerr("AUDIT_PROBE_LOAD_FAILED ", name, ": ", loaded.get("errors", []))
			quit(1)
			return
		models[name] = loaded.model
		identities[name] = loaded.get("input_identity", {})
	var out := {
		"format": "openrc-stik-physics-audit-probe-v1",
		"scope": "instantaneous production equations only; no flight, trim, integration or physical-validation claim",
		"source_identity": identities,
		"rho_kg_m3": RHO,
		"wash_test_description": "Each aircraft at zero body rates, alpha=beta=0 and fixed 10000 RPM, including an arbitrary static and two low-speed states. Rudder = -10 degrees in data convention. Same RPM is not matched thrust or power; Extra is a software-path contrast only. Wake computed quasi-statically, no ground effect.",
		"wash": [],
		"electric_stopped_description": "Ideal and pack JSON share the propeller law; isolated ideal normalized prop queried at 15 m/s axial airspeed, then zero-duty motor torque and propeller shaft derivative. These are static point evaluations, not a starting event or glide run.",
		"electric_stopped": [],
		"lateral_description": "15 m/s, alpha=0, neutral controls and zero rates; body Fy/(q S), not wind-axis CY. Global and local are diagnostics, blended is production, all without propulsion/ground effect. Different airframes are not matched physical measurements.",
		"lateral": [],
	}
	for name: String in models:
		var model: Dictionary = models[name]
		for speed: float in [0.0, 3.0, 10.0]:
			var row := _wash_row(name, model, speed)
			if row.is_empty():
				printerr("AUDIT_PROBE_WASH_FAILED ", name, " speed=", speed)
				quit(1)
				return
			out.wash.append(row)
	var electric: Dictionary = models.electric_stik_ideal.propulsion
	for rpm: float in [0.0, 0.9, 1.0, 100.0, 500.0, 2000.0, 5000.0]:
		var v := M.v3(15.0, 0.0, 0.0)
		var tq := Propulsion.thrust_torque(v, rpm, electric, RHO)
		var load: float = Propulsion.prop_torque(rpm, 15.0, electric, RHO)
		var rate: float = Propulsion.shaft_rate(rpm, 0.0, 15.0, electric, RHO, 1.0, false)
		if not is_finite(load) or not is_finite(rate) or not _all_finite(tq):
			printerr("AUDIT_PROBE_ELECTRIC_FAILED rpm=", rpm)
			quit(1)
			return
		out.electric_stopped.append({"rpm": rpm, "forward_speed_mps": 15.0, "thrust_n": tq[0],
			"prop_torque_nm": load, "advance_ratio_as_returned": tq[2], "zero_duty_disabled_shaft_rate_rpm_s": rate})
	for name: String in ["basic_stik", "extra_glow"]:
		for beta_deg: float in [-25.0, -20.0, -15.0, -10.0, -5.0, 0.0, 5.0, 10.0, 15.0, 20.0, 25.0]:
			var row := _lateral_row(name, models[name], beta_deg)
			if row.is_empty():
				printerr("AUDIT_PROBE_LATERAL_FAILED ", name, " beta=", beta_deg)
				quit(1)
				return
			out.lateral.append(row)
	print("AUDIT_PROBE_JSON ", JSON.stringify(out))
	print("AUDIT_PROBE_COMPLETE")
	quit(0)


func _state(u: float, v: float) -> PackedFloat64Array:
	return RB.make_state(M.v3(0.0, 0.0, -300.0), M.v3(u, v, 0.0), M.q_identity(), M.v3(0.0, 0.0, 0.0))


func _wash_row(name: String, model: Dictionary, speed: float) -> Dictionary:
	var s := _state(speed, 0.0)
	var wind := M.v3(0.0, 0.0, 0.0)
	var air := Air.compute(s, wind, RHO)
	var hub: Dictionary = Propulsion.stage_air_velocity(s, air, model.propulsion)
	if not hub.get("ok", false):
		return {}
	var prop: PackedFloat64Array = Propulsion.loads(hub.velocity_body, RPM, model.propulsion, RHO)
	var tq: PackedFloat64Array = Propulsion.thrust_torque(hub.velocity_body, RPM, model.propulsion, RHO)
	var total0: PackedFloat64Array = Dynamics.loads_from_air(s, model, NEUTRAL, RPM, RHO, air)
	var total1: PackedFloat64Array = Dynamics.loads_from_air(s, model, RUDDER, RPM, RHO, air)
	var aero0: PackedFloat64Array = Aero.loads(s, air, NEUTRAL, model, RHO)
	var aero1: PackedFloat64Array = Aero.loads(s, air, RUDDER, model, RHO)
	if not _all_finite(prop) or not _all_finite(tq) or not _all_finite(total0) or not _all_finite(total1) or not _all_finite(aero0) or not _all_finite(aero1):
		return {}
	var wash0 := PackedFloat64Array()
	var wash1 := PackedFloat64Array()
	var rudder_delta := PackedFloat64Array()
	for i in 6:
		wash0.append(total0[i] - aero0[i] - prop[i])
		wash1.append(total1[i] - aero1[i] - prop[i])
		rudder_delta.append(total1[i] - total0[i])
	return {"aircraft": name, "speed_mps": speed, "rpm": RPM,
		"has_slipstream": not model.propulsion.get("slipstream", {}).is_empty(),
		"propeller_thrust_n": tq[0], "propeller_torque_nm": tq[1],
		"wash_neutral_fx_fy_fz_mx_my_mz": Array(wash0),
		"wash_rudder_fx_fy_fz_mx_my_mz": Array(wash1),
		"total_rudder_minus_neutral_fx_fy_fz_mx_my_mz": Array(rudder_delta)}


func _lateral_row(name: String, model: Dictionary, beta_deg: float) -> Dictionary:
	var beta := deg_to_rad(beta_deg)
	var speed := 15.0
	var s := _state(speed * cos(beta), speed * sin(beta))
	var air := Air.compute(s, M.v3(0.0, 0.0, 0.0), RHO)
	var gl: PackedFloat64Array = Aero._global_loads(s, air, NEUTRAL, model, RHO)
	var lo: PackedFloat64Array = Aero._local_loads(s, air, NEUTRAL, model, RHO)
	var blended: PackedFloat64Array = Aero.loads(s, air, NEUTRAL, model, RHO)
	var blend: float = Aero.local_flow_weight(s, air, NEUTRAL, model)
	var qs: float = 0.5 * RHO * speed * speed * float(model.reference.S)
	if not _all_finite(gl) or not _all_finite(lo) or not _all_finite(blended) or not is_finite(blend) or qs <= 0.0:
		return {}
	return {"aircraft": name, "beta_deg": beta_deg, "local_weight": blend,
		"body_side_coefficient_global": gl[1] / qs, "body_side_coefficient_local": lo[1] / qs,
		"body_side_coefficient_production": blended[1] / qs,
		"body_cy_beta_declared": model.surfaces.has("body_cy_beta"),
		"body_crossflow_area_declared": model.surfaces.has("body_crossflow_area")}


func _all_finite(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true
