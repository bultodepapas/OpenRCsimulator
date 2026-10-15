extends SceneTree

const Session := preload("res://sim/ground_vehicle/session.gd")
const Vehicle := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")

const NEUTRAL := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}


class SideScrapeSession extends Session:
	func _make_road(_course_value: Dictionary) -> Callable:
		return func(_north: float, _east: float) -> Dictionary:
			return {"height_m": 0.0, "normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
				"mu": 0.85, "rolling": 1.0, "surface_id": "asphalt", "walls": [
					{"id": "scrape-west", "north_min_m": -100.0, "north_max_m": 100.0,
						"east_min_m": -0.34, "east_max_m": -0.314,
						"bottom_up_m": 0.0, "top_up_m": 1.0, "mu": 0.5},
					{"id": "scrape-east", "north_min_m": -100.0, "north_max_m": 100.0,
						"east_min_m": 0.314, "east_max_m": 0.34,
						"bottom_up_m": 0.0, "top_up_m": 1.0, "mu": 0.5},
				]}

	func _make_spawn_state(model: Dictionary, _course_value: Dictionary, _pose: Dictionary,
			road: Callable, _pose_up_delta_m: float) -> PackedFloat64Array:
		var initialized: Dictionary = Vehicle.initialize(model, road, 0.0, 0.0)
		if not bool(initialized.get("ok", false)):
			return PackedFloat64Array()
		var candidate: PackedFloat64Array = initialized.state.duplicate()
		# Start in a balanced two-wall corridor with velocity tangent to the walls.
		# The near-touching wheels have no velocity into either wall.
		candidate[Vehicle.VEL] = 2.0
		var tire_radius := float(model["tire_radius_m"])
		for corner in 4:
			candidate[Vehicle.WHEEL_SPIN + corner] = 2.0 / tire_radius
		return candidate


class HeadOnImpactSession extends Session:
	func _make_road(_course_value: Dictionary) -> Callable:
		return func(_north: float, _east: float) -> Dictionary:
			return {"height_m": 0.0, "normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
				"mu": 0.85, "rolling": 1.0, "surface_id": "asphalt", "walls": [{
					"id": "head-on", "north_min_m": 4.0, "north_max_m": 4.5,
					"east_min_m": -5.0, "east_max_m": 5.0,
					"bottom_up_m": 0.0, "top_up_m": 1.0, "mu": 0.5,
				}]}

	func _make_spawn_state(model: Dictionary, _course_value: Dictionary, _pose: Dictionary,
			road: Callable, _pose_up_delta_m: float) -> PackedFloat64Array:
		var initialized: Dictionary = Vehicle.initialize(model, road, 0.0, 0.0)
		if not bool(initialized.get("ok", false)):
			return PackedFloat64Array()
		var candidate: PackedFloat64Array = initialized.state.duplicate()
		candidate[Vehicle.VEL] = 8.0
		var tire_radius := float(model["tire_radius_m"])
		for corner in 4:
			candidate[Vehicle.WHEEL_SPIN + corner] = 8.0 / tire_radius
		return candidate


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var session := SideScrapeSession.new()
	if not session.prepare_default() or not session.tick_once(NEUTRAL) or not session.resume():
		printerr("Could not prepare the tangential hull-scrape fixture: ", session.load_error)
		quit(1)
		return
	var initial_telemetry: Dictionary = session.telemetry_snapshot()
	var initial_damage: PackedFloat64Array = session.damage_snapshot()
	var initial_energy := float(initial_telemetry["total_energy_j"])
	var hull_seen := false
	var wall_seen := false
	var first_wall_tick := -1
	var failed_tick := -1
	for tick in 480:
		if not session.tick_once(NEUTRAL):
			failed_tick = tick
			break
		var telemetry: Dictionary = session.telemetry_snapshot()
		for contact in telemetry["hull_in_contact"]:
			hull_seen = hull_seen or contact != 0
		wall_seen = wall_seen or int(telemetry["wall_contact_count"]) > 0
		if first_wall_tick < 0 and int(telemetry["wall_contact_count"]) > 0:
			first_wall_tick = tick + 1
	var final_telemetry: Dictionary = session.telemetry_snapshot()
	var final_damage: PackedFloat64Array = session.damage_snapshot()
	print("fixture_ticks=", session.tick)
	print("initial_hull=", initial_telemetry["hull_in_contact"],
		" final_hull=", final_telemetry["hull_in_contact"],
		" hull_seen=", hull_seen, " wall_seen=", wall_seen)
	print("initial_energy_j=", initial_energy,
		" final_energy_j=", final_telemetry["total_energy_j"],
		" energy_delta_j=", initial_energy - float(final_telemetry["total_energy_j"]))
	print("initial_damage=", initial_damage,
		" final_damage=", final_damage)
	print("damage_projection=", session.damage_visual_state())
	print("initial_wall_count=", initial_telemetry["wall_contact_count"],
		" final_wall_count=", final_telemetry["wall_contact_count"],
		" initial_wall_load_n=", initial_telemetry["wall_normal_load_n"],
		" final_wall_load_n=", final_telemetry["wall_normal_load_n"],
		" initial_wall_friction_power_w=", initial_telemetry["wall_friction_power_w"],
		" final_wall_friction_power_w=", final_telemetry["wall_friction_power_w"],
		" first_wall_tick=", first_wall_tick)
	if failed_tick >= 0 or not wall_seen:
		printerr("Fixture did not stay in its declared wall-scrape state; failed_tick=", failed_tick)
		quit(1)
		return
	session.free()
	_run_head_on_impact()


func _run_head_on_impact() -> void:
	var session := HeadOnImpactSession.new()
	if not session.prepare_default() or not session.tick_once(NEUTRAL) or not session.resume():
		printerr("Could not prepare the positive head-on impact control: ", session.load_error)
		quit(1)
		return
	var first_contact: Dictionary = {}
	var first_contact_speed_delta := 0.0
	var first_contact_energy_delta := 0.0
	var first_contact_damage := PackedFloat64Array()
	for _tick in 240:
		var prior_telemetry: Dictionary = session.telemetry_snapshot()
		var prior_state: PackedFloat64Array = session.state_snapshot()
		if not session.tick_once(NEUTRAL):
			printerr("Head-on impact control rejected a physics tick")
			quit(1)
			return
		var telemetry: Dictionary = session.telemetry_snapshot()
		if first_contact.is_empty() and int(telemetry["wall_contact_count"]) > 0:
			first_contact = telemetry
			var state: PackedFloat64Array = session.state_snapshot()
			first_contact_speed_delta = absf(state[Vehicle.VEL] - prior_state[Vehicle.VEL])
			first_contact_energy_delta = float(prior_telemetry["total_energy_j"]) \
				- float(telemetry["total_energy_j"])
			first_contact_damage = session.damage_snapshot()
	var final_damage: PackedFloat64Array = session.damage_snapshot()
	print("head_on_first_contact_tick=", session.tick if first_contact.is_empty() else "observed",
		" hull_wall_load_n=", first_contact.get("hull_wall_load_n", PackedFloat64Array()),
		" wheel_wall_load_n=", first_contact.get("wheel_wall_load_n", PackedFloat64Array()),
		" first_step_speed_drop_m_per_s=", first_contact_speed_delta,
		" first_step_energy_drop_j=", first_contact_energy_delta,
		" damage_at_contact=", first_contact_damage,
		" final_damage=", final_damage,
		" projection=", session.damage_visual_state())
	if first_contact.is_empty() or float(session.damage_visual_state()["body_damage"]) <= 0.0:
		printerr("Positive head-on wall impact did not produce body damage")
		quit(1)
		return
	session.free()
	quit(0)
