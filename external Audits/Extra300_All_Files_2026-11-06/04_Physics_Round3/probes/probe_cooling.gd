extends SceneTree
const Flight = preload("res://sim/flight_session.gd")
const Glow = preload("res://physics/glow/flight.gd")
const Thermal = preload("res://physics/glow/thermal.gd")
const M = preload("res://physics/math3d.gd")
var failures := 0
var checks := 0

func check(label: String, passed: bool, info: Variant = "") -> void:
	checks += 1
	if not passed: failures += 1
	print(("PASS " if passed else "FAIL ") + label + " " + str(info))

func _initialize() -> void:
	call_deferred("run")

func snapshot(f: Node, label: String) -> Dictionary:
	var result: Dictionary = Glow.point(f,f.sim.state,f.sim.continuous,f.sim.time())
	check(label + " stage evaluates",result.get("ok",false),result.get("message",""))
	if not result.get("ok",false): return {}
	var prop: Dictionary = f.aircraft.model.propulsion
	var hub: PackedFloat64Array = result.hub_air_velocity_body_m_s
	var axial: float = M.dot(hub,prop.axis)
	var speed: float = M.norm(hub)
	var rho: float = result.environment.rho_kgm3
	var thrust: float = result.propeller.thrust_n
	var area: float = PI*prop.diameter*prop.diameter/4.0
	if axial<0.0 or thrust<=0.0:
		check(label + " forward positive thrust",false,{axial=axial,thrust=thrust})
		return {}
	check(label + " forward positive thrust",true)
	var vi_static: float = sqrt(thrust/(2.0*rho*area))
	# Comparison only: ideal, aligned actuator disk. This is not an installed cooling model.
	var vi_forward: float = (2.0*vi_static*vi_static)/(sqrt(axial*axial+4.0*vi_static*vi_static)+axial)
	var temp: float = result.state.temperature_k
	var ambient: float = result.environment.temperature_k
	var thermal: Dictionary = prop.glow.settings.thermal
	var modeled_cooling: float = (thermal.cooling_base_w_k + thermal.cooling_airflow_w_s_m_k*(speed+vi_static))*(temp-ambient)
	var alternative: Dictionary = Thermal.evaluate(result.source,temp,ambient,speed+vi_forward,thermal)
	check(label + " current proxy matches cooling",absf(modeled_cooling-result.thermal.cooling_heat_w)<1e-9)
	check(label + " comparison thermal evaluates",alternative.get("ok",false))
	var expected_delta: float = thermal.cooling_airflow_w_s_m_k*(vi_static-vi_forward)*(temp-ambient)/thermal.heat_capacity_j_k
	check(label + " fixed-state rate identity",absf((alternative.temperature_rate_k_s-result.thermal.temperature_rate_k_s)-expected_delta)<1e-12)
	return {label=label,airspeed_m_s=speed,axial_speed_m_s=axial,rpm=f.sim.continuous[0],thrust_n=thrust,
		density_kg_m3=rho,head_k=temp,ambient_k=ambient,vi_static=vi_static,vi_forward_ideal=vi_forward,
		cooling_heat_current_w=result.thermal.cooling_heat_w,cooling_heat_alternative_w=alternative.cooling_heat_w,
		thermal_rate_current_k_s=result.thermal.temperature_rate_k_s,thermal_rate_alternative_k_s=alternative.temperature_rate_k_s,
		thermal_rate_difference_k_s=alternative.temperature_rate_k_s-result.thermal.temperature_rate_k_s}

func run() -> void:
	Engine.physics_ticks_per_second = 240
	var f = Flight.new()
	f.input_enabled=false
	f.setup("res://data/aircraft/gp_extra_300s_60.json","gp-extra-300s-60")
	check("stock Extra starts",f.is_flyable(),f.start_error)
	var samples: Array = []
	if f.is_flyable():
		samples.append(snapshot(f,"trimmed airborne"))
		var t: float = 10.0
		var rho: float = 1.225
		var area: float = PI*pow(f.aircraft.model.propulsion.diameter,2)/4.0
		var static_vi: float = sqrt(t/(2.0*rho*area))
		var ideal_vi: float = 2.0*static_vi*static_vi/sqrt(4.0*static_vi*static_vi)
		check("zero airspeed analytic control",absf(static_vi-ideal_vi)<1e-12)
	var out = {checks=checks,failures=failures,samples=samples,
		interpretation="Stage-local numerical contrast only; ideal axial-flow disk is not a validated cowl-cooling measurement."}
	var file = FileAccess.open("/workspace/scratch/b3c27b2e84ee/extra300_audit/round3/dynamics/cooling_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(out,"  ",true,true)); file.close()
	f.free()
	print("COOLING-PROBE %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
