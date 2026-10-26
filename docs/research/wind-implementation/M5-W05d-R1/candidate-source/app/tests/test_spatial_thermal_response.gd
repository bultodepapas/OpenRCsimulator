## Same-state real aircraft response to a prescribed balanced thermal, not glider qualification.
extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const Config := preload("res://physics/wind_config.gd")
const Spatial := preload("res://physics/wind_spatial_config.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
var checks := 0
var failures := 0

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	call_deferred("_run")

func _weather(peak: float) -> Dictionary:
	var base := Spatial.defaults()
	base.identity.epoch_offset_s = 120.0
	var config: Dictionary = Spatial.thermal_defaults(base).config
	if peak != 0.0:
		config.thermal_field.cells = [{id = "response_fixture", birth_s = 0.0, duration_s = 240.0,
			center_ne_m = [0.0, 0.0], drift_ne_mps = [0.0, 0.0], radius_m = 40.0,
			top_agl_m = 200.0, peak_updraft_mps = peak}]
	var weather := Config.spatial_defaults()
	weather.spatial_wind = config
	return weather

func _new(path: String, peak: float) -> Node:
	var flight := Flight.new()
	flight.input_enabled = false
	flight.setup(path)
	var accepted: bool = flight.setup_weather(_weather(peak))
	check("response weather accepted: " + flight.weather_error, accepted)
	flight.reset()
	check("response start accepted", flight.is_flyable())
	flight.engine_running = false
	flight.sim.inputs[3] = 0.0
	return flight

func _run() -> void:
	var refinement_body := PackedFloat64Array()
	for path in ["res://data/aircraft/jensen_ugly_stik_60.json", "res://data/aircraft/turbo_lumber_evolution.json"]:
		var baseline := _new(path, 0.0)
		var thermal := _new(path, 1.2)
		var body: PackedFloat64Array = baseline.sim.state.duplicate()
		body[0] = 0.0
		body[1] = 0.0
		body[2] = -100.0
		if refinement_body.is_empty(): refinement_body = body.duplicate()
		check("same ground-relative initial body", baseline.sim.reset(body) and thermal.sim.reset(body)
			and baseline.sim.state == thermal.sim.state)
		var wind: PackedFloat64Array = thermal.wind_at(0.0, body)
		check("analytic thermal core at lifetime/height peak", absf(wind[2] + 1.2) < 1e-12 and wind[0] == 0.0 and wind[1] == 0.0)
		check("updraft changes aerodynamic angle of attack", thermal.air_data(body, 0.0).alpha > baseline.air_data(body, 0.0).alpha)
		baseline.sim.step()
		thermal.sim.step()
		var q: PackedFloat64Array = body.slice(RB.ATT, RB.ATT + 4)
		var base_force := M.q_rotate(q, baseline.sim.last_loads.slice(0, 3))
		var thermal_force := M.q_rotate(q, thermal.sim.last_loads.slice(0, 3))
		check("updraft produces upward aerodynamic load through real stage", thermal_force[2] < base_force[2])
		for _tick in 239:
			baseline.sim.step()
			thermal.sim.step()
		check("both one-second flights complete", baseline.sim.tick == 240 and thermal.sim.tick == 240 and baseline.sim.fault_reason.is_empty() and thermal.sim.fault_reason.is_empty())
		var height_gain: float = baseline.sim.state[2] - thermal.sim.state[2]
		check("thermal aircraft finishes higher from same initial body and controls", height_gain > 0.05)
		print("thermal response ", path, " height_difference_m=", height_gain,
			" initial_upward_force_difference_N=", base_force[2] - thermal_force[2])
		baseline.free()
		thermal.free()
	var original_hz: int = Engine.physics_ticks_per_second
	var states: Array[PackedFloat64Array] = []
	for rate in [240, 480, 960]:
		Engine.physics_ticks_per_second = rate
		var flight := _new("res://data/aircraft/jensen_ugly_stik_60.json", 1.2)
		check("refinement reset", flight.sim.reset(refinement_body))
		for _tick in rate / 2: flight.sim.step()
		check("refinement accepts every tick", flight.sim.tick == rate / 2 and flight.sim.fault_reason.is_empty())
		states.append(flight.sim.state.duplicate())
		flight.free()
	Engine.physics_ticks_per_second = original_hz
	var coarse := _difference(states[0], states[1])
	var fine := _difference(states[1], states[2])
	check("thermal response converges under timestep refinement", fine < coarse and fine < 0.01)
	print("thermal refinement max_body_component_delta 240/480=", coarse, " 480/960=", fine)
	print("spatial thermal response: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _difference(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var result := 0.0
	for i in a.size(): result = maxf(result, absf(a[i] - b[i]))
	return result
