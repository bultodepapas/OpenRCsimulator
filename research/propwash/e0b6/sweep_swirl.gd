# E0b6 uncertainty envelope. All factors are exploratory priors, not measured Stik calibration.
extends SceneTree
const Fixture = preload("res://tests/test_wash_profile.gd")
const AD = preload("res://physics/aircraft_data.gd")
const S = preload("res://physics/slipstream.gd")
const Prop = preload("res://physics/propulsion.gd")
const Air = preload("res://physics/air_data.gd")

func _initialize() -> void:
	var rows: Array = []
	for speed: float in [0.0, 5.0, 15.0, 25.0]:
		for endpoints: Array in [[0.8,1.8], [1.0,1.4], [1.4,1.8]]:
			for factor: float in [0.0,0.2,0.4,0.7,1.0]:
				var raw: Dictionary = Fixture.combined_raw()
				raw.propulsion.propeller.slipstream.wash_factor = Fixture.quantity(endpoints, "1")
				raw.propulsion.propeller.slipstream.swirl_factor = Fixture.quantity(factor, "1")
				var loaded: Dictionary = AD.validate_and_derive(raw)
				if not loaded.ok:
					push_error(str(loaded.errors))
					quit(1)
					return
				var model: Dictionary = loaded.model
				var prop: Dictionary = model.propulsion
				var state: PackedFloat64Array = PackedFloat64Array([0,0,-100,speed,0,0,1,0,0,0,0,0,0])
				var air: Dictionary = Air.compute(state, PackedFloat64Array([0,0,0]), 1.225)
				var controls: Dictionary = {elevator=0.0,rudder=0.0,aileron_left=0.0,aileron_right=0.0}
				var tq: PackedFloat64Array = Prop.thrust_torque(air.v_air, prop.max_rpm, prop, 1.225)
				var wake: Dictionary = S.wake(air.v_air, tq[0], tq[1], prop, 1.225)
				var loads: PackedFloat64Array = S.loads(state, air, controls, model, prop.max_rpm, 1.225, 0.3)
				prop.slipstream.swirl_factor = 0.0
				var axial: PackedFloat64Array = S.loads(state, air, controls, model, prop.max_rpm, 1.225, 0.3)
				var delta: Array[float] = []
				for component: int in 6:
					delta.append(loads[component]-axial[component])
					if not is_finite(delta[component]):
						push_error("Nonfinite swirl sweep")
						quit(1)
						return
				var kw: float = wake.dv/wake.w
				var core_factor: float = 1.0-pow(wake.core/wake.rs,2)/2.0
				rows.append({speed_mps=speed, rpm=prop.max_rpm, wash_endpoints=endpoints, swirl_factor=factor,
					loads_Fx_Fy_Fz_Mx_My_Mz=Array(loads), axial_loads_Fx_Fy_Fz_Mx_My_Mz=Array(axial),
					shaft_torque_Nm=tq[1], strength_m2ps=wake.swirl, radius_m=wake.rs, core_m=wake.core,
					nominal_far_cylinder_torque_ratio=factor*kw/2.0*core_factor,
					local_speed_cylinder_torque_ratio=factor*kw/2.0*core_factor*(wake.u+wake.dv)/wake.vs,
					swirl_delta_Fx_Fy_Fz_Mx_My_Mz=delta,
					tail_roll_to_shaft_torque_ratio=delta[3]/tq[1], yaw_Nm=delta[5]})
	var output: FileAccess = FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	output.store_string(JSON.stringify({format="openrc-e0b6-swirl-sensitivity v1",
		note="60 fixed-rpm level-body cases; estimated priors, not confidence bounds or held-out field validation; CL held at 0.3; no wing/fuselage recovery",
		rows=rows}, "\t", true, true)+"\n")
	print("E0b6: %d finite sensitivity cases" % rows.size())
	quit()
