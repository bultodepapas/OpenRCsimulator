## RCV-water numeric checks. Run with the pinned Godot binary and --headless --path app --script <this file>.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const Data := preload("res://physics/ground_vehicle/vehicle_data.gd")
const Vehicle := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const Wet := preload("res://physics/ground_vehicle/vehicle_environment.gd")
const Damage := preload("res://physics/ground_vehicle/vehicle_damage.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const Course := preload("res://physics/ground_vehicle/airfield_course.gd")

const DT := 1.0 / 240.0
const WATER_UP_M := -0.45
const FULL_DEPTH_M := 5.0
const EXPECTED_DISPLACEMENT_M3 := 4.0 * Wet.BODY_CELL_VOLUME_M3 + 4.0 * Wet.WHEEL_VOLUME_M3

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, passed: bool, detail := "") -> void:
	_checks += 1
	print(("PASS: " if passed else "FAIL: ") + label + ("" if detail.is_empty() else "  " + detail))
	if not passed:
		_failures += 1


func _surface(ground_up_m: float, water_up_m: float, depth_m: float, mud_fraction := 0.0) -> Dictionary:
	return {
		"height_m": ground_up_m,
		"normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
		"mu": 0.85,
		"rolling": 0.025,
		"surface_id": "water-test-bed",
		"wet_zone": true,
		"water_height_m": water_up_m,
		"water_depth_m": depth_m,
		"mud_fraction": mud_fraction,
	}


func _dry_road(_north_m: float, _east_m: float) -> Dictionary:
	return {
		"height_m": 0.0,
		"normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
		"mu": 0.85,
		"rolling": 0.025,
		"surface_id": "dry-test",
	}


func _dry_deep_road(_north_m: float, _east_m: float) -> Dictionary:
	return {
		"height_m": WATER_UP_M - FULL_DEPTH_M,
		"normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
		"mu": 0.85,
		"rolling": 0.025,
		"surface_id": "deep-dry-test-bed",
	}


func _water_road(depth_m: float, water_up_m := WATER_UP_M) -> Callable:
	var ground_up_m := water_up_m - depth_m
	return func(_north_m: float, _east_m: float) -> Dictionary:
		return _surface(ground_up_m, water_up_m, depth_m)


func _lake_road(course: Dictionary) -> Callable:
	return func(north_m: float, east_m: float) -> Dictionary:
		return Course.sample(course, north_m, east_m)


func _max_physical_difference(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	if a.size() != Vehicle.STATE_SIZE or b.size() != Vehicle.STATE_SIZE:
		return INF
	var maximum := 0.0
	for index in Vehicle.STATE_SIZE:
		# Rotor phase is an accumulated output coordinate; compare the other state
		# channels (position, velocity, attitude/rates, suspension, spin, steering).
		if index >= Vehicle.WHEEL_ANGLE and index < Vehicle.WHEEL_ANGLE + Vehicle.CORNER_COUNT:
			continue
		maximum = maxf(maximum, absf(a[index] - b[index]))
	return maximum


func _generalized_power(rhs: PackedFloat64Array, state: PackedFloat64Array) -> float:
	var power := 0.0
	for axis in 3:
		power += rhs[axis] * state[3 + axis]
		power += rhs[3 + axis] * state[10 + axis]
	for corner in 4:
		power += rhs[6 + corner] * state[17 + corner]
		power += rhs[10 + corner] * state[21 + corner]
	return power


func _state_at_water(model: Dictionary, depth_m := FULL_DEPTH_M) -> PackedFloat64Array:
	var road := _water_road(depth_m)
	var initialized: Dictionary = Vehicle.initialize(model, road, 0.0, 0.0)
	if not bool(initialized.get("ok", false)):
		return PackedFloat64Array()
	var state: PackedFloat64Array = initialized.state
	# Move the supported bed state into the open water column. Dynamics contact
	# remains against the bed several metres below; only the environment sees water.
	state[2] = 1.5
	return state


func _test_course_and_real_lake(model: Dictionary) -> Callable:
	var field_result: Dictionary = FieldLoader.load_from()
	var lake_result: Dictionary = LakeLoader.load_from()
	var built: Dictionary = Course.build(field_result, {}, lake_result.get("lake", {}))
	_check("default field and validated lake build a lake-aware course",
		bool(field_result.get("ok", false)) and bool(lake_result.get("ok", false))
		and bool(built.get("ok", false)), str(built.get("errors", [])))
	if not bool(built.get("ok", false)):
		return Callable()
	var course: Dictionary = built.course
	var shore_spawn: Dictionary = {}
	for spawn_value in course.get("spawns", []):
		if typeof(spawn_value) == TYPE_DICTIONARY and str(spawn_value.get("id", "")) == "lake_shore":
			shore_spawn = spawn_value
	_check("lake shore spawn is a dry, south-facing staging pad",
		not shore_spawn.is_empty()
		and absf(float(shore_spawn.get("north_m", NAN)) - 145.5) < 1.0e-9
		and absf(float(shore_spawn.get("east_m", NAN)) - 125.0) < 1.0e-9
		and absf(float(shore_spawn.get("heading_rad", NAN)) - PI) < 1.0e-9)
	if not shore_spawn.is_empty():
		var road := _lake_road(course)
		var staging: Dictionary = road.call(float(shore_spawn.north_m), float(shore_spawn.east_m))
		var spawn_state := Vehicle.make_terrain_state(model, shore_spawn, road)
		print("lake staging sample %.4f m high, depth %.4f mud %.3f; supported state %d values" % [
			float(staging.get("height_m", NAN)), float(staging.get("water_depth_m", 0.0)),
			float(staging.get("mud_fraction", 0.0)), spawn_state.size(),
		])
		_check("lake shore staging spawn resolves to dry ground and a supported vehicle state",
			float(staging.get("water_depth_m", 0.0)) == 0.0
			and float(staging.get("mud_fraction", 0.0)) == 0.0
			and spawn_state.size() == Vehicle.STATE_SIZE)
	var shallow: Dictionary = Course.sample(course, 138.0, 125.0)
	var deep_edge: Dictionary = Course.sample(course, 137.0, 125.0)
	var center: Dictionary = Course.sample(course, 110.0, 125.0)
	var mud_bank: Dictionary = Course.sample(course, 139.4, 125.0)
	print("lake samples (N,E): staging 145.5,125 depth %.4f mud %.3f; bank 139.4,125 depth %.4f mud %.3f; shallow 138,125 depth %.4f; deeper 137,125 depth %.4f; center 110,125 depth %.4f" % [
		float(Course.sample(course, 145.5, 125.0).get("water_depth_m", NAN)),
		float(Course.sample(course, 145.5, 125.0).get("mud_fraction", NAN)),
		float(mud_bank.get("water_depth_m", NAN)), float(mud_bank.get("mud_fraction", NAN)),
		float(shallow.get("water_depth_m", NAN)), float(deep_edge.get("water_depth_m", NAN)),
		float(center.get("water_depth_m", NAN)),
	])
	_check("lake sampler exposes a shallow wading edge and a deeper basin",
		float(shallow.get("water_depth_m", -1.0)) > 0.0
		and float(deep_edge.get("water_depth_m", -1.0)) > float(shallow.get("water_depth_m", INF))
		and float(center.get("water_depth_m", -1.0)) > float(deep_edge.get("water_depth_m", INF)))
	_check("shoreline blend exposes a nonzero dry mud band",
		float(mud_bank.get("water_depth_m", -1.0)) == 0.0
		and float(mud_bank.get("mud_fraction", 0.0)) > 0.0
		and float(mud_bank.get("mud_fraction", 1.0)) < 1.0)
	return _lake_road(course)


func _test_dry_compatibility(state: PackedFloat64Array, model: Dictionary) -> void:
	var controls: Dictionary = Vehicle.DEFAULT_CONTROLS
	var reference: Dictionary = Vehicle._evaluate(state, model, controls, Callable(self, "_dry_road"), true, true)
	var active: Dictionary = Vehicle._evaluate_active(state, model, controls, Callable(self, "_dry_road"), true, true)
	var reference_accel: PackedFloat64Array = reference.get("generalized_acceleration", PackedFloat64Array())
	var active_accel: PackedFloat64Array = active.get("generalized_acceleration", PackedFloat64Array())
	_check("dry active evaluation is byte-equal to the legacy reference result",
		bool(reference.get("ok", false)) and bool(active.get("ok", false))
		and active_accel == reference_accel
		and active.get("wheel_load_n", PackedFloat64Array()) == reference.get("wheel_load_n", PackedFloat64Array())
		and float(active.get("energy_j", NAN)) == float(reference.get("energy_j", NAN))
		and not active.has("environment"))
	var telemetry: Dictionary = Vehicle.telemetry(state, model, Callable(self, "_dry_road"))
	_check("dry telemetry carries only zero environment defaults",
		bool(telemetry.get("ok", false))
		and float(telemetry.get("environment", {}).get("buoyancy_n", NAN)) == 0.0
		and float(telemetry.get("environment", {}).get("drag_power_w", NAN)) == 0.0)


func _test_shallow_deep_occupancy(model: Dictionary) -> void:
	var shallow_depth := 0.06
	var deep_depth := 0.22
	var shallow_road := _water_road(shallow_depth)
	var deep_road := _water_road(deep_depth)
	var shallow_state_result: Dictionary = Vehicle.initialize(model, shallow_road, 0.0, 0.0)
	var deep_state_result: Dictionary = Vehicle.initialize(model, deep_road, 0.0, 0.0)
	if not bool(shallow_state_result.get("ok", false)) or not bool(deep_state_result.get("ok", false)):
		_check("flat synthetic shallow and deep bed states initialize", false)
		return
	var shallow_state: PackedFloat64Array = shallow_state_result.state
	var deep_state: PackedFloat64Array = deep_state_result.state
	var shallow_geometry: Dictionary = Vehicle._corner_geometry(shallow_state, model, 0.0, 0.0, 0.0)
	var deep_geometry: Dictionary = Vehicle._corner_geometry(deep_state, model, 0.0, 0.0, 0.0)
	var shallow_load: Dictionary = Wet.evaluate(shallow_state, model, shallow_geometry, shallow_road,
		shallow_road.call(0.0, 0.0))
	var deep_load: Dictionary = Wet.evaluate(deep_state, model, deep_geometry, deep_road, deep_road.call(0.0, 0.0))
	var shallow_wheels: PackedFloat64Array = shallow_load.get("wheel_submersion", PackedFloat64Array())
	var deep_wheels: PackedFloat64Array = deep_load.get("wheel_submersion", PackedFloat64Array())
	var shallow_mean := 0.0
	var deep_mean := 0.0
	for corner in 4:
		shallow_mean += shallow_wheels[corner] * 0.25
		deep_mean += deep_wheels[corner] * 0.25
	print("synthetic wheel occupancy: 0.06 m depth %.4f; 0.22 m depth %.4f; body %.4f -> %.4f" % [
		shallow_mean, deep_mean, float(shallow_load.get("body_submersion", NAN)),
		float(deep_load.get("body_submersion", NAN)),
	])
	_check("shallow water wets tire caps and deeper water increases occupancy",
		bool(shallow_load.get("ok", false)) and bool(deep_load.get("ok", false))
		and shallow_mean > 0.0 and deep_mean > shallow_mean
		and float(deep_load.get("body_submersion", 0.0)) >= float(shallow_load.get("body_submersion", INF)))


func _test_buoyancy_and_dissipation(model: Dictionary) -> void:
	var state := _state_at_water(model)
	_check("supported reference state can be moved into the deep-water column", state.size() == Vehicle.STATE_SIZE)
	if state.is_empty():
		return
	var road := _water_road(FULL_DEPTH_M)
	var geometry: Dictionary = Vehicle._corner_geometry(state, model, 0.0, 0.0, 0.0)
	var full: Dictionary = Wet.evaluate(state, model, geometry, road, road.call(state[0], state[1]))
	var expected_lift := Wet.DENSITY_KG_M3 * float(model.gravity_m_per_s2) * EXPECTED_DISPLACEMENT_M3
	var total_mass := float(model.sprung_mass_kg) + 4.0 * float(model.unsprung_mass_kg)
	print("full immersion lift %.9f N; Archimedes %.9f N; truck weight %.9f N; displaced %.6f L" % [
		float(full.get("buoyancy_n", NAN)), expected_lift, total_mass * float(model.gravity_m_per_s2),
		EXPECTED_DISPLACEMENT_M3 * 1000.0,
	])
	_check("open-truck displaced volume produces Archimedes-consistent lift below vehicle weight",
		bool(full.get("ok", false)) and absf(float(full.get("buoyancy_n", NAN)) - expected_lift) < 1.0e-8
		and EXPECTED_DISPLACEMENT_M3 == 0.0026 and expected_lift < total_mass * float(model.gravity_m_per_s2))
	var near_shore_state := state.duplicate()
	near_shore_state[2] = -WATER_UP_M
	var epsilon_road := _water_road(0.00001)
	var epsilon_geometry: Dictionary = Vehicle._corner_geometry(near_shore_state, model, 0.0, 0.0, 0.0)
	var epsilon_load: Dictionary = Wet.evaluate(near_shore_state, model, epsilon_geometry, epsilon_road,
		epsilon_road.call(near_shore_state[0], near_shore_state[1]))
	var buried_state := state.duplicate()
	buried_state[2] = 8.0
	buried_state[3] = 1.0
	for corner in 4:
		buried_state[21 + corner] = 6.0
	var buried_geometry: Dictionary = Vehicle._corner_geometry(buried_state, model, 0.0, 0.0, 0.0)
	var buried_load: Dictionary = Wet.evaluate(buried_state, model, buried_geometry, road,
		road.call(buried_state[0], buried_state[1]))
	_check("water-column clipping makes shore force tend to zero with depth",
		bool(epsilon_load.get("ok", false)) and float(epsilon_load.get("buoyancy_n", INF)) >= 0.0
		and float(epsilon_load.get("buoyancy_n", INF)) < expected_lift * 0.001,
		"10 µm water layer lift %.9f N / full %.9f N" % [float(epsilon_load.get("buoyancy_n", NAN)), expected_lift])
	_check("cells fully below the lake bed receive no fluid lift or drag",
		bool(buried_load.get("ok", false)) and float(buried_load.get("buoyancy_n", INF)) == 0.0
		and float(buried_load.get("drag_power_w", INF)) == 0.0
		and float(buried_load.get("body_submersion", INF)) == 0.0)

	var translation := state.duplicate()
	translation[3] = 1.5
	translation[4] = -0.3
	translation[5] = 0.4
	var rotation := state.duplicate()
	rotation[10] = 1.2
	rotation[11] = -0.7
	rotation[12] = 0.6
	var wheel_spin := state.duplicate()
	for corner in 4:
		wheel_spin[21 + corner] = 8.0 - 3.0 * float(corner)
	for case in [{"name": "translation", "state": translation},
			{"name": "body rotation", "state": rotation}, {"name": "wheel spin", "state": wheel_spin}]:
		var test_state: PackedFloat64Array = case.state
		var test_geometry: Dictionary = Vehicle._corner_geometry(test_state, model, test_state[29], test_state[30], 0.0)
		var load: Dictionary = Wet.evaluate(test_state, model, test_geometry, road, road.call(test_state[0], test_state[1]))
		_check("water drag dissipates " + str(case.name), bool(load.get("ok", false))
			and float(load.get("drag_power_w", 0.0)) < 0.0, "Pdrag %.9f W" % float(load.get("drag_power_w", NAN)))

	var mixed := state.duplicate()
	mixed[3] = 0.7
	mixed[4] = -0.35
	mixed[5] = 0.2
	mixed[10] = 0.4
	mixed[11] = -0.25
	mixed[12] = 0.3
	for corner in 4:
		mixed[17 + corner] = 0.04 * float(1 - corner)
		mixed[21 + corner] = 10.0 - 3.0 * float(corner)
	var mixed_geometry: Dictionary = Vehicle._corner_geometry(mixed, model, mixed[29], mixed[30], 0.0)
	var mixed_load: Dictionary = Wet.evaluate(mixed, model, mixed_geometry, road, road.call(mixed[0], mixed[1]))
	var generalized_power := _generalized_power(mixed_load.get("generalized_force", PackedFloat64Array()), mixed)
	var power_error := absf(generalized_power - float(mixed_load.get("power_w", NAN)))
	_check("reported fluid work equals independent generalized-force power", bool(mixed_load.get("ok", false))
		and power_error <= 1.0e-8 * maxf(1.0, absf(generalized_power)),
		"generalized %.9f W, reported %.9f W, error %.6f W" % [generalized_power,
			float(mixed_load.get("power_w", NAN)), power_error])


func _test_malformed_metadata(model: Dictionary, state: PackedFloat64Array) -> void:
	var malformed := func(_north: float, _east: float) -> Dictionary:
		return {"height_m": 0.0, "normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
			"mu": 0.85, "rolling": 0.025, "wet_zone": true,
			"water_height_m": WATER_UP_M, "water_depth_m": NAN, "mud_fraction": 0.0}
	var invalid_active: Dictionary = Vehicle._evaluate_active(state, model, Vehicle.DEFAULT_CONTROLS, malformed)
	_check("active dynamics rejects nonfinite water depth before force application",
		not bool(invalid_active.get("ok", false)) and str(invalid_active.get("error", "")).contains("Malformed"))
	_check("surface validator rejects absent, negative, and out-of-range wet values",
		not Wet.surface_is_valid({"wet_zone": true, "water_height_m": 0.0, "water_depth_m": 1.0})
		and not Wet.surface_is_valid({"wet_zone": true, "water_height_m": 0.0, "water_depth_m": -0.01, "mud_fraction": 0.0})
		and not Wet.surface_is_valid({"wet_zone": true, "water_height_m": 0.0, "water_depth_m": 0.0, "mud_fraction": 1.01}))


func _run_drop(state: PackedFloat64Array, model: Dictionary, road: Callable, dt: float, duration_s: float) -> PackedFloat64Array:
	var next := state.duplicate()
	var count := roundi(duration_s / dt)
	for tick in count:
		next = Vehicle.step(next, model, Vehicle.DEFAULT_CONTROLS, dt, road)
		if next.is_empty():
			return next
	return next


func _run_internal_rk4(state: PackedFloat64Array, model: Dictionary, road: Callable,
		step_s: float, duration_s: float) -> PackedFloat64Array:
	var next := state.duplicate()
	var count := roundi(duration_s / step_s)
	for tick in count:
		next = Vehicle._rk4_step(next, model, Vehicle.DEFAULT_CONTROLS, road, step_s)
		if next.is_empty():
			return next
	return next


func _test_drop_and_timestep(model: Dictionary) -> void:
	var wet_road := _water_road(FULL_DEPTH_M)
	var start := _state_at_water(model)
	if start.is_empty():
		_check("free-water drop fixture initializes", false)
		return
	start[2] = -WATER_UP_M
	var duration := 0.1
	var wet := _run_drop(start, model, wet_road, 1.0 / 240.0, duration)
	var dry := _run_drop(start, model, Callable(self, "_dry_deep_road"), 1.0 / 240.0, duration)
	print("0.1 s drop: wet down %.6f m/vd %.6f m/s; dry down %.6f m/vd %.6f m/s" % [wet[2], wet[5], dry[2], dry[5]])
	_check("fully immersed open truck sinks under gravity but water slows the drop",
		wet.size() == Vehicle.STATE_SIZE and dry.size() == Vehicle.STATE_SIZE
		and wet[2] > start[2] and wet[5] > 0.0 and dry[5] > wet[5] + 0.01)

	var coarse := _run_internal_rk4(start, model, wet_road, 1.0 / 480.0, duration)
	var medium := _run_internal_rk4(start, model, wet_road, 1.0 / 960.0, duration)
	var fine := _run_internal_rk4(start, model, wet_road, 1.0 / 1920.0, duration)
	var coarse_to_fine := _max_physical_difference(coarse, fine)
	var medium_to_fine := _max_physical_difference(medium, fine)
	print("0.1 s internal RK4 refinement, excluding wheel-angle channels: coarse→fine "
		+ str(coarse_to_fine) + ", medium→fine " + str(medium_to_fine))
	_check("wet reference RK4 state converges as internal step halves",
		coarse.size() == Vehicle.STATE_SIZE and medium.size() == Vehicle.STATE_SIZE
		and fine.size() == Vehicle.STATE_SIZE and coarse_to_fine > 0.0
		and medium_to_fine < coarse_to_fine)


func _test_damage_environment_work(model: Dictionary) -> void:
	var road := _water_road(FULL_DEPTH_M)
	var previous := _state_at_water(model)
	if previous.is_empty():
		_check("wet damage fixture initializes", false)
		return
	for corner in 4:
		previous[21 + corner] = 0.0
	previous[3] = 5.0
	var dt := 1.0 / 960.0
	var previous_telemetry: Dictionary = Vehicle.telemetry(previous, model, road)
	var next_state: PackedFloat64Array = Vehicle.step(previous, model, Vehicle.DEFAULT_CONTROLS, dt, road)
	var next_telemetry: Dictionary = Vehicle.telemetry(next_state, model, road)
	if not bool(previous_telemetry.get("ok", false)) or not bool(next_telemetry.get("ok", false)):
		_check("wet damage fixture telemetry resolves", false)
		return
	var speed_drop := float(previous_telemetry.speed_m_per_s) - float(next_telemetry.speed_m_per_s)
	var power_before := float(previous_telemetry.environment.power_w)
	var power_after := float(next_telemetry.environment.power_w)
	var environment_work := 0.5 * (power_before + power_after) * dt
	# Mark a concurrent hull-contact episode to exercise the damage energy path;
	# actual states and fluid telemetry still come from one wet dynamics tick.
	var previous_contact := previous_telemetry.duplicate(true)
	var next_contact := next_telemetry.duplicate(true)
	var previous_hull: PackedByteArray = previous_contact.hull_in_contact.duplicate()
	var next_hull: PackedByteArray = next_contact.hull_in_contact.duplicate()
	previous_hull[0] = 1
	next_hull[0] = 1
	previous_contact.hull_in_contact = previous_hull
	next_contact.hull_in_contact = next_hull
	next_contact.total_energy_j = float(previous_contact.total_energy_j) + environment_work
	var damage := Damage.new()
	var accepted: bool = damage.advance(previous, next_state, previous_contact, next_contact, model, dt)
	var after: PackedFloat64Array = damage.snapshot()
	var naive_loss := float(previous_contact.total_energy_j) - float(next_contact.total_energy_j)
	var accounted_loss := damage._contact_energy_loss(previous_contact, next_contact, dt)
	var visual: Dictionary = damage.visual_state()
	print("wet damage accounting: speed drop %.6f m/s, drag work %.6f J, naive loss %.6f J, damage energy %.6f J" % [
		speed_drop, environment_work, naive_loss, float(after[Damage.LAST_IMPACT_ENERGY]),
	])
	print("damage fixture accepted=%s, accounted contact loss %.9f J, visual damage %.9f, suspension %.9f, drive %.9f" % [
		str(accepted), accounted_loss, float(visual.body_damage), float(visual.suspension_damage), float(visual.drive_scale),
	])
	var no_visible_damage: bool = float(visual.body_damage) == 0.0 \
		and float(visual.suspension_damage) == 0.0 and float(visual.drive_scale) == 1.0
	var impact_energy_below_damage_threshold := float(visual.last_impact_energy_j) < Damage.MIN_EPISODE_DAMAGE_ENERGY_J
	_check("fluid work above the damage threshold is removed from a marked contact-energy estimate",
		accepted and speed_drop >= Damage.MIN_IMPACT_VELOCITY_CHANGE_M_PER_S
		and float(previous_telemetry.speed_m_per_s) >= Damage.MIN_CONTACT_SPEED_M_PER_S
		and environment_work < -Damage.MIN_EPISODE_DAMAGE_ENERGY_J
		and absf(accounted_loss) < 1.0e-9 and no_visible_damage and impact_energy_below_damage_threshold)


func _run() -> void:
	var loaded: Dictionary = Data.load_default()
	_check("strict MT8 vehicle model loads", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		quit(1)
		return
	var model: Dictionary = loaded.model
	var reference_selected: bool = Vehicle.set_backend_override_for_tests(Vehicle.BACKEND_GDSCRIPT_REFERENCE)
	_check("test process selects the GDScript reference solver", reference_selected)
	var dry_initialized: Dictionary = Vehicle.initialize(model, Callable(self, "_dry_road"), 0.0, 0.0)
	_check("dry static reference state initializes", bool(dry_initialized.get("ok", false)))
	if not bool(dry_initialized.get("ok", false)):
		quit(1)
		return
	var dry_state: PackedFloat64Array = dry_initialized.state
	_test_course_and_real_lake(model)
	_test_dry_compatibility(dry_state, model)
	_test_shallow_deep_occupancy(model)
	_test_buoyancy_and_dissipation(model)
	_test_malformed_metadata(model, dry_state)
	_test_drop_and_timestep(model)
	_test_damage_environment_work(model)
	print("RCV-water numeric test summary: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
