extends SceneTree

const Session := preload("res://sim/ground_vehicle/session.gd")
const Vehicle := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const Damage := preload("res://physics/ground_vehicle/vehicle_damage.gd")

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


class SupportedHullScrapeSession extends SideScrapeSession:
	func _make_road(_course_value: Dictionary) -> Callable:
		return func(_north: float, _east: float) -> Dictionary:
			return {"height_m": 0.0, "normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
				"mu": 0.85, "rolling": 1.0, "surface_id": "asphalt", "walls": [
					{"id": "hull-scrape-west", "north_min_m": -100.0, "north_max_m": 100.0,
						"east_min_m": -0.08, "east_max_m": -0.05,
						"bottom_up_m": 0.0, "top_up_m": 1.0, "mu": 0.01},
					{"id": "hull-scrape-east", "north_min_m": -100.0, "north_max_m": 100.0,
						"east_min_m": 0.05, "east_max_m": 0.08,
						"bottom_up_m": 0.0, "top_up_m": 1.0, "mu": 0.01},
				]}


class LateralWheelImpactSession extends SideScrapeSession:
	func _make_road(_course_value: Dictionary) -> Callable:
		return func(_north: float, _east: float) -> Dictionary:
			return {"height_m": 0.0, "normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
				"mu": 0.85, "rolling": 1.0, "surface_id": "asphalt", "walls": [{
					"id": "wheel-side-impact", "north_min_m": -100.0, "north_max_m": 100.0,
					"east_min_m": 0.314, "east_max_m": 0.34,
					"bottom_up_m": 0.0, "top_up_m": 1.0, "mu": 0.5,
				}]}

	func _make_spawn_state(model: Dictionary, _course_value: Dictionary, _pose: Dictionary,
			road: Callable, _pose_up_delta_m: float) -> PackedFloat64Array:
		var initialized: Dictionary = Vehicle.initialize(model, road, 0.0, 0.0)
		if not bool(initialized.get("ok", false)):
			return PackedFloat64Array()
		var candidate: PackedFloat64Array = initialized.state.duplicate()
		candidate[Vehicle.VEL + 1] = 3.0
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
	var model: Dictionary = session.model_snapshot()
	var initial_energy := float(initial_telemetry["total_energy_j"])
	var previous_telemetry := initial_telemetry
	var integrated_wall_friction_work := 0.0
	var hull_seen := false
	var wall_seen := false
	var first_wall_tick := -1
	var failed_tick := -1
	for tick in 480:
		if not session.tick_once(NEUTRAL):
			failed_tick = tick
			break
		var telemetry: Dictionary = session.telemetry_snapshot()
		integrated_wall_friction_work += -0.5 * (
			float(previous_telemetry["wall_friction_power_w"])
			+ float(telemetry["wall_friction_power_w"])) * Session.DT
		previous_telemetry = telemetry
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
		" energy_delta_j=", initial_energy - float(final_telemetry["total_energy_j"]),
		" integrated_wall_friction_work_j=", integrated_wall_friction_work,
		" residual_energy_loss_j=", initial_energy - float(final_telemetry["total_energy_j"])
			- integrated_wall_friction_work)
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
	var no_wear := true
	for index in 10:
		no_wear = no_wear and final_damage[index] == 0.0
	no_wear = no_wear and final_damage[Damage.WALL_EPISODE_ENERGY] == 0.0 \
		and final_damage[Damage.LAST_IMPACT_ENERGY] == 0.0
	if failed_tick >= 0 or not wall_seen or hull_seen or not no_wear:
		printerr("Fixture did not stay in its declared wall-scrape state; failed_tick=", failed_tick)
		quit(1)
		return
	session.free()
	_run_supported_hull_scrape()


func _run_supported_hull_scrape() -> void:
	var session := SupportedHullScrapeSession.new()
	if not session.prepare_default() or not session.tick_once(NEUTRAL) or not session.resume():
		printerr("Could not prepare the supported hull-scrape fixture: ", session.load_error)
		quit(1)
		return
	var initial_telemetry: Dictionary = session.telemetry_snapshot()
	var initial_energy := float(initial_telemetry["total_energy_j"])
	var previous_telemetry := initial_telemetry
	var integrated_wall_friction_work := 0.0
	var maximum_speed_drop := 0.0
	var hull_wall_seen := false
	var wheel_wall_seen := false
	var wheel_support_seen := false
	var max_hull_wall_load := 0.0
	var max_wheel_wall_load := 0.0
	var failed_tick := -1
	for tick in 240:
		var previous_state: PackedFloat64Array = session.state_snapshot()
		if not session.tick_once(NEUTRAL):
			failed_tick = tick
			break
		var telemetry: Dictionary = session.telemetry_snapshot()
		integrated_wall_friction_work += -0.5 * (
			float(previous_telemetry["wall_friction_power_w"])
			+ float(telemetry["wall_friction_power_w"])) * Session.DT
		previous_telemetry = telemetry
		var next_state: PackedFloat64Array = session.state_snapshot()
		var speed_before := sqrt(previous_state[Vehicle.VEL] * previous_state[Vehicle.VEL]
			+ previous_state[Vehicle.VEL + 1] * previous_state[Vehicle.VEL + 1]
			+ previous_state[Vehicle.VEL + 2] * previous_state[Vehicle.VEL + 2])
		var speed_after := sqrt(next_state[Vehicle.VEL] * next_state[Vehicle.VEL]
			+ next_state[Vehicle.VEL + 1] * next_state[Vehicle.VEL + 1]
			+ next_state[Vehicle.VEL + 2] * next_state[Vehicle.VEL + 2])
		maximum_speed_drop = maxf(maximum_speed_drop, speed_before - speed_after)
		for load in telemetry["hull_wall_load_n"]:
			max_hull_wall_load = maxf(max_hull_wall_load, float(load))
			hull_wall_seen = hull_wall_seen or float(load) > 0.0
		for load in telemetry["wheel_wall_load_n"]:
			max_wheel_wall_load = maxf(max_wheel_wall_load, float(load))
			wheel_wall_seen = wheel_wall_seen or float(load) > 0.0
		for active in telemetry["wheel_in_contact"]:
			wheel_support_seen = wheel_support_seen or active != 0
	var final_damage: PackedFloat64Array = session.damage_snapshot()
	print("supported_hull_scrape_ticks=", session.tick,
		" hull_wall_seen=", hull_wall_seen, " max_hull_wall_load_n=", max_hull_wall_load,
		" wheel_wall_seen=", wheel_wall_seen, " max_wheel_wall_load_n=", max_wheel_wall_load,
		" wheel_support_seen=", wheel_support_seen,
		" energy_delta_j=", initial_energy - float(session.telemetry_snapshot()["total_energy_j"]),
		" integrated_wall_friction_work_j=", integrated_wall_friction_work,
		" maximum_per_tick_speed_drop_m_per_s=", maximum_speed_drop,
		" damage=", final_damage)
	var no_wear := true
	for index in 10:
		no_wear = no_wear and final_damage[index] == 0.0
	if failed_tick >= 0 or not hull_wall_seen or wheel_wall_seen or not wheel_support_seen or not no_wear:
		printerr("Fixture did not stay in its declared supported hull-scrape state; failed_tick=", failed_tick)
		quit(1)
		return
	session.free()
	_run_lateral_wheel_impact()


func _run_lateral_wheel_impact() -> void:
	var session := LateralWheelImpactSession.new()
	if not session.prepare_default() or not session.tick_once(NEUTRAL) or not session.resume():
		printerr("Could not prepare the lateral wheel-impact control: ", session.load_error)
		quit(1)
		return
	var positive_impact_telemetry: Dictionary = {}
	var positive_impact_damage := PackedFloat64Array()
	var speed_drop := 0.0
	var energy_drop := 0.0
	var impact_tick := -1
	var failed_tick := -1
	for tick in 120:
		var prior_state: PackedFloat64Array = session.state_snapshot()
		var prior_telemetry: Dictionary = session.telemetry_snapshot()
		if not session.tick_once(NEUTRAL):
			failed_tick = tick
			break
		var telemetry: Dictionary = session.telemetry_snapshot()
		var damage: PackedFloat64Array = session.damage_snapshot()
		if damage[Damage.LAST_IMPACT_ENERGY] > 0.0:
			positive_impact_telemetry = telemetry
			positive_impact_damage = damage
			var prior_speed := sqrt(prior_state[Vehicle.VEL] * prior_state[Vehicle.VEL]
				+ prior_state[Vehicle.VEL + 1] * prior_state[Vehicle.VEL + 1]
				+ prior_state[Vehicle.VEL + 2] * prior_state[Vehicle.VEL + 2])
			var current_state: PackedFloat64Array = session.state_snapshot()
			var current_speed := sqrt(current_state[Vehicle.VEL] * current_state[Vehicle.VEL]
				+ current_state[Vehicle.VEL + 1] * current_state[Vehicle.VEL + 1]
				+ current_state[Vehicle.VEL + 2] * current_state[Vehicle.VEL + 2])
			speed_drop = prior_speed - current_speed
			energy_drop = float(prior_telemetry["total_energy_j"]) - float(telemetry["total_energy_j"])
			impact_tick = tick + 2
			break
	var hull_wall_load := 0.0
	var wheel_wall_load := 0.0
	if not positive_impact_telemetry.is_empty():
		for load in positive_impact_telemetry["hull_wall_load_n"]:
			hull_wall_load += float(load)
		for load in positive_impact_telemetry["wheel_wall_load_n"]:
			wheel_wall_load = maxf(wheel_wall_load, float(load))
	var body_wear := false
	if not positive_impact_damage.is_empty():
		for index in 5:
			body_wear = body_wear or positive_impact_damage[index] > 0.0
	print("lateral_wheel_impact_tick=", impact_tick,
		" hull_wall_load_sum_n=", hull_wall_load,
		" peak_wheel_wall_load_n=", wheel_wall_load,
		" speed_drop_m_per_s=", speed_drop, " total_energy_drop_j=", energy_drop,
		" damage=", positive_impact_damage)
	var suspension_wear := false
	if not positive_impact_damage.is_empty():
		for corner in Damage.CORNER_COUNT:
			suspension_wear = suspension_wear \
				or positive_impact_damage[Damage.SUSPENSION_BASE + corner] > 0.0
	if failed_tick >= 0 or impact_tick < 0 or hull_wall_load != 0.0 \
			or wheel_wall_load <= 0.0 or not suspension_wear or body_wear \
			or positive_impact_damage[Damage.DRIVE] != 0.0:
		printerr("Lateral wheel-impact fixture did not remain wheel-only")
		session.free()
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
	var first_contact_tick := -1
	for tick in 240:
		var prior_telemetry: Dictionary = session.telemetry_snapshot()
		var prior_state: PackedFloat64Array = session.state_snapshot()
		if not session.tick_once(NEUTRAL):
			printerr("Head-on impact control rejected a physics tick")
			quit(1)
			return
		var telemetry: Dictionary = session.telemetry_snapshot()
		if first_contact.is_empty() and int(telemetry["wall_contact_count"]) > 0:
			first_contact = telemetry
			first_contact_tick = tick + 1
			var state: PackedFloat64Array = session.state_snapshot()
			first_contact_speed_delta = absf(state[Vehicle.VEL] - prior_state[Vehicle.VEL])
			first_contact_energy_delta = float(prior_telemetry["total_energy_j"]) \
				- float(telemetry["total_energy_j"])
			first_contact_damage = session.damage_snapshot()
	var final_damage: PackedFloat64Array = session.damage_snapshot()
	print("head_on_first_contact_tick=", first_contact_tick,
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
