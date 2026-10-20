## AFC-02: static clearance checks for the nominal launch circuit corridor.
## Geometry fixtures are derived from real collision proxies; the sampled oracle is
## independent of Airspace's analytic annulus/AABB implementation.
extends SceneTree

const ProfileLoader := preload("res://ai/companions/profile_loader.gd")
const Airspace := preload("res://ai/companions/airspace.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const SceneryLoader := preload("res://scenery/scenery_loader.gd")
const FieldLights := preload("res://render/world/field_lights.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")
const GroundTerrain := preload("res://physics/ground_terrain.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const ContactContract := preload("res://physics/aircraft_contact_contract.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")

const AIRCRAFT_ID := "jensen-das-ugly-stik-60"
const AIRCRAFT_DATA_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const TAU := 6.2831853071795864769
const ORACLE_ANGLE_SAMPLES := 720

var _checks := 0
var _failures := 0
var _field: Dictionary = {}
var _field_profile: Dictionary = {}
var _model: Dictionary = {}
var _surfaces := PackedFloat64Array()
var _lake: Dictionary = {}
var _world: Dictionary = {}
var _box_template: Dictionary = {}
var _capsule_template: Dictionary = {}
var _production_report: Dictionary = {}
var _center_north := 0.0
var _center_east := 0.0
var _pilot_down := 0.0
var _route_radius := 0.0


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if passed else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not passed:
		_failures += 1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var loaded_field: Dictionary = FieldLoader.load_from()
	_check("default Club field normalizes", loaded_field.get("ok", false), str(loaded_field.get("errors", [])))
	var loaded_aircraft: Dictionary = AircraftData.load_file(AIRCRAFT_DATA_PATH)
	_check("qualified Stik model loads", loaded_aircraft.get("ok", false), str(loaded_aircraft.get("errors", [])))
	var loaded_surfaces: Dictionary = GroundSurfaces.load_table()
	_check("ground surface table normalizes", loaded_surfaces.get("ok", false), str(loaded_surfaces.get("errors", [])))
	var loaded_lake: Dictionary = LakeLoader.load_from()
	_check("default bounded lake terrain normalizes", loaded_lake.get("ok", false), str(loaded_lake.get("errors", [])))
	if not loaded_field.get("ok", false) or not loaded_aircraft.get("ok", false) \
			or not loaded_surfaces.get("ok", false) or not loaded_lake.get("ok", false):
		_finish()
		return

	_field = loaded_field.field.duplicate(true)
	_model = loaded_aircraft.model.duplicate(true)
	_lake = loaded_lake.lake.duplicate(true)
	var surface_build: Dictionary = GroundSurfaces.build(loaded_surfaces.table, _field)
	_check("physics surface rectangles build from the normalized field", surface_build.get("ok", false), str(surface_build.get("errors", [])))
	if not surface_build.get("ok", false):
		_finish()
		return
	_surfaces = surface_build.rects

	var profile_pair: Dictionary = ProfileLoader.load_profile(AIRCRAFT_ID, loaded_aircraft.input_identity, _field)
	_check("accepted aircraft and field profile pair loads", profile_pair.get("ok", false), str(profile_pair.get("errors", [])))
	if not profile_pair.get("ok", false):
		_finish()
		return
	_field_profile = profile_pair.field_profile.duplicate(true)
	_center_north = float(_field_profile.circuit.center_north.value)
	_center_east = float(_field_profile.circuit.center_east.value)
	_pilot_down = float(_field.pilot.down)
	_route_radius = float(_field_profile.circuit.radius.value)

	var loaded_scenery: Dictionary = SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, _field)
	_check("complete default scenery normalizes", loaded_scenery.get("ok", false), str(loaded_scenery.get("errors", [])))
	var loaded_lights: Dictionary = FieldLights.load_from()
	_check("default field lights normalize", loaded_lights.get("ok", false), str(loaded_lights.get("errors", [])))
	if not loaded_scenery.get("ok", false) or not loaded_lights.get("ok", false):
		_finish()
		return
	var built: Dictionary = CollisionWorld.build(_field, loaded_scenery.scenery, loaded_lights.lights)
	_check("complete field scenery and lights build a collision world", built.get("ok", false), str(built.get("errors", [])))
	if not built.get("ok", false):
		_finish()
		return
	_world = built.world.duplicate(true)
	_box_template = _proxy_template("box")
	_capsule_template = _proxy_template("capsule")
	_check("production world supplies box and capsule proxy templates", not _box_template.is_empty() and not _capsule_template.is_empty())
	if _box_template.is_empty() or _capsule_template.is_empty():
		_finish()
		return

	_test_real_world_admission()
	_test_corridor_geometry()
	_test_protected_exclusions()
	_test_malformed_inventory()
	_test_input_corruption()
	_test_geometry_fingerprint()
	_test_sampled_oracle()
	_write_production_report(_requested_output_path())
	_finish()


func _test_real_world_admission() -> void:
	var result: Dictionary = _validate(_world, _field, _field_profile, _surfaces, _lake, _model, 1)
	_check("real default field, lake, aircraft and full scenery pass launch clearance", result.get("ok", false), str(result.get("errors", [])))
	if result.get("ok", false):
		var expected_ground := maxf(GroundTerrain.max_height(_surfaces),
			-float(_lake.water_level_down_m) + float(_lake.wave_bounds.max_amplitude_m))
		_check("report bounds terrain and worst allowed lake wave height",
			is_equal_approx(float(result.report.ground_upper_m), expected_ground))
		_check("actual normalized proxy geometry is fingerprinted separately from world identity",
			str(result.report.geometry_sha256).length() == 64
			and result.report.geometry_sha256 != str(_world.identity))
		_check("launch report records one nominal corridor", result.report.corridors.size() == 1
			and is_equal_approx(float(result.report.corridors[0].center_height_m), 35.0 - _pilot_down))
	var three: Dictionary = _validate(_world, _field, _field_profile, _surfaces, _lake, _model, 3)
	_check("all three qualified altitude slots pass the default static world", three.get("ok", false), str(three.get("errors", [])))
	if three.get("ok", false):
		_production_report = three.report.duplicate(true)
		_check("slot reports preserve 20 m vertical spacing and separate bands",
			three.report.corridors.size() == 3
			and is_equal_approx(float(three.report.corridors[1].center_height_m) - float(three.report.corridors[0].center_height_m), 20.0)
			and is_equal_approx(float(three.report.corridors[2].center_height_m) - float(three.report.corridors[1].center_height_m), 20.0)
			and float(three.report.corridors[0].max_height_m) < float(three.report.corridors[1].min_height_m))
	var no_collision: Dictionary = _validate({}, _field, _field_profile, _surfaces, _lake, _model, 1)
	_check("an explicitly empty collision world remains an allowed disabled-collision fixture",
		no_collision.get("ok", false) and not bool(no_collision.report.collision_enabled))
	var bad_count: Dictionary = _validate({}, _field, _field_profile, _surfaces, _lake, _model, 0)
	_check("zero companion slots are refused", not bad_count.get("ok", false))


func _test_corridor_geometry() -> void:
	var base_height := float(_field_profile.circuit.base_agl.value) - _pilot_down
	var outer_radius := _expected_radius() + 12.0 + _route_radius
	var path_north := _center_north + _route_radius
	var path_east := _center_east
	var path_down := _pilot_down - float(_field_profile.circuit.base_agl.value)

	var on_circle: Dictionary = _box(path_north, path_east, path_down, 0.4, 0.4, 0.4, 45.0, "circle-35m")
	_check_refused("an obstacle on the nominal 35 m circuit is refused", _world_for(on_circle))

	var low_object: Dictionary = _box(path_north, path_east, _pilot_down, 0.4, 0.6, 0.4, 0.0, "low-object")
	var low_result := _validate(_world_for(low_object), _field, _field_profile, _surfaces, _lake, _model, 1)
	_check("a low object below the route's vertical corridor remains available", low_result.get("ok", false), str(low_result.get("errors", [])))

	var between_slots_height := base_height + 10.0
	var between_slots: Dictionary = _box(path_north, path_east, -between_slots_height, 0.4, 0.2, 0.4, 0.0, "between-slots")
	var gap_result := _validate(_world_for(between_slots), _field, _field_profile, _surfaces, _lake, _model, 2)
	_check("exact per-slot height checks leave the inter-slot gap available", gap_result.get("ok", false), str(gap_result.get("errors", [])))

	var tangent_height := base_height - (2.0 + _expected_radius() + 2.0)
	var half_down := 0.5
	var vertical_tangent: Dictionary = _box(path_north, path_east, half_down - tangent_height,
		0.4, 2.0 * half_down, 0.4, 0.0, "vertical-tangent")
	_check_refused("vertical tangency with the clearance band counts as contact", _world_for(vertical_tangent))

	var radial_tangent: Dictionary = _box(_center_north + outer_radius + 0.5, _center_east,
		path_down, 1.0, 0.5, 1.0, 0.0, "radial-tangent")
	_check_refused("radial tangency with the annular corridor counts as contact", _world_for(radial_tangent))

	var capsule: Dictionary = _capsule(path_north, path_east, path_down, 0.2, 0.5, "capsule-on-route")
	_check_refused("a valid capsule proxy on the route is refused", _world_for(capsule))

	var center_hole: Dictionary = _box(_center_north, _center_east, path_down, 0.4, 0.4, 0.4, 0.0, "inside-circle-hole")
	var hole_result := _validate(_world_for(center_hole), _field, _field_profile, _surfaces, _lake, _model, 1)
	_check("a small object inside the circuit's center hole remains available", hole_result.get("ok", false), str(hole_result.get("errors", [])))

	var enclosing_circle: Dictionary = _box(_center_north, _center_east, path_down,
		2.0 * outer_radius, 0.4, 2.0 * outer_radius, 0.0, "aabb-enclosing-whole-circle")
	_check_refused("an AABB enclosing the full circle is conservatively refused", _world_for(enclosing_circle))

	var between_angle := deg_to_rad(0.5)
	var thin_diagonal: Dictionary = _box(_center_north + _route_radius * cos(between_angle),
		_center_east + _route_radius * sin(between_angle), path_down, 0.10, 0.10, 0.10, 33.0, "thin-diagonal-between-samples")
	_check("the thin diagonal lies between one-degree centerline samples", not _coarse_centerline_sample_hits(thin_diagonal))
	_check_refused("the analytic corridor still catches a thin diagonal between angle samples", _world_for(thin_diagonal))


func _test_protected_exclusions() -> void:
	var shifted_field: Dictionary = _field.duplicate(true)
	shifted_field.pilot.north = _center_north + _route_radius
	shifted_field.pilot.east = _center_east
	var pilot_result := _validate({}, shifted_field, _field_profile, _surfaces, _lake, _model, 1)
	_check("pilot-station disc exclusion is refused even with collision disabled", not pilot_result.get("ok", false))

	var person: Dictionary = _box(_center_north + _route_radius, _center_east,
		_pilot_down - 250.0, 0.2, 0.2, 0.2, 0.0, "person-overflight")
	person.kind = "person"
	person.part = "body"
	_check_refused("a person remains protected at any overflight altitude", _world_for(person))

	for part: String in ["shelter_roof", "pavilion_roof"]:
		var protected_building: Dictionary = _box(_center_north + _route_radius, _center_east,
			_pilot_down - 250.0, 0.2, 0.2, 0.2, 0.0, part + "-overflight")
		protected_building.kind = "building"
		protected_building.part = part
		_check_refused("%s is protected from overflight at every height" % part, _world_for(protected_building))


func _test_malformed_inventory() -> void:
	var unknown_shape: Dictionary = _box(_center_north, _center_east, _pilot_down - 35.0, 1.0, 1.0, 1.0, 0.0, "unknown-shape")
	unknown_shape.shape = "mesh"
	_check_refused("unknown proxy shapes fail closed", _world_for(unknown_shape))

	var inverted_bounds: Dictionary = _box(_center_north, _center_east, _pilot_down - 35.0, 1.0, 1.0, 1.0, 0.0, "inverted-bounds")
	inverted_bounds.bounds_north_min = float(inverted_bounds.bounds_north_max) + 1.0
	_check_refused("inverted cached AABBs fail closed", _world_for(inverted_bounds))

	var undersized_bounds: Dictionary = _box(_center_north, _center_east, _pilot_down - 35.0, 1.0, 1.0, 1.0, 0.0, "undersized-bounds")
	undersized_bounds.bounds_east_min = float(undersized_bounds.bounds_east_min) + 0.01
	_check_refused("cached AABBs must enclose reconstructed proxy bounds", _world_for(undersized_bounds))

	var nonfinite_bounds: Dictionary = _box(_center_north, _center_east, _pilot_down - 35.0, 1.0, 1.0, 1.0, 0.0, "nan-bounds")
	nonfinite_bounds.bounds_down_max = NAN
	_check_refused("non-finite cached geometry fails closed", _world_for(nonfinite_bounds))

	var bad_dimensions: Dictionary = _capsule(_center_north, _center_east, _pilot_down - 35.0, 0.0, 0.5, "zero-radius")
	_check_refused("degenerate capsule dimensions fail closed", _world_for(bad_dimensions))

	var missing_response: Dictionary = _box(_center_north, _center_east, _pilot_down - 35.0, 1.0, 1.0, 1.0, 0.0, "missing-response-class")
	missing_response.erase("response_class")
	_check_refused("collision proxies require a nonempty response class", _world_for(missing_response))

	var bad_world: Dictionary = _world.duplicate(true)
	bad_world.erase("bins")
	_check_refused("a malformed nonempty world header is refused", bad_world)

	var too_many: Dictionary = _world.duplicate(true)
	var repeated: Dictionary = _box_template.duplicate(true)
	var proxies: Array = []
	for index: int in 10001:
		var copy: Dictionary = repeated.duplicate(true)
		copy.id = "over-limit-%05d" % index
		proxies.append(copy)
	too_many.proxies = proxies
	_check_refused("proxy inventories above the explicit 10,000-proxy budget fail closed", too_many)


func _test_input_corruption() -> void:
	var bad_profile: Dictionary = _field_profile.duplicate(true)
	bad_profile.circuit.radius.value = NAN
	var bad_profile_result := _validate(_world_for(_box(_center_north + _route_radius, _center_east, _pilot_down - 35.0,
		0.4, 0.4, 0.4, 0.0, "corrupt-input-route-obstacle")),
		_field, bad_profile, _surfaces, _lake, _model, 1)
	_check("non-finite profile geometry rejects before collision checks",
		not bad_profile_result.get("ok", false) and _error_contains(bad_profile_result, "Circuit quantity 'radius' is invalid."),
		str(bad_profile_result.get("errors", [])))

	var bad_field: Dictionary = _field.duplicate(true)
	bad_field.pilot.down = NAN
	var bad_field_result := _validate({}, bad_field, _field_profile, _surfaces, _lake, _model, 1)
	_check("non-finite pilot coordinates reject before collision checks",
		not bad_field_result.get("ok", false) and _error_contains(bad_field_result, "Pilot station coordinates are invalid."),
		str(bad_field_result.get("errors", [])))

	var bad_surfaces := PackedFloat64Array([NAN])
	var bad_surface_result := _validate({}, _field, _field_profile, bad_surfaces, {}, _model, 1)
	_check("malformed terrain surface tables reject before geometry checks",
		not bad_surface_result.get("ok", false) and _error_contains(bad_surface_result, "Terrain surface table is invalid."),
		str(bad_surface_result.get("errors", [])))

	var bad_lake: Dictionary = _lake.duplicate(true)
	bad_lake.identity = "0000000000000000000000000000000000000000000000000000000000000000"
	var bad_lake_result := _validate({}, _field, _field_profile, _surfaces, bad_lake, _model, 1)
	_check("lake geometry identity corruption rejects before geometry checks",
		not bad_lake_result.get("ok", false) and _error_contains(bad_lake_result, "Lake geometry or identity is invalid."),
		str(bad_lake_result.get("errors", [])))

	var bad_model: Dictionary = _model.duplicate(true)
	var hull: PackedFloat64Array = bad_model.crash_hull
	if not hull.is_empty():
		hull[0] = NAN
		bad_model.crash_hull = hull
	var bad_model_result := _validate({}, _field, _field_profile, _surfaces, {}, bad_model, 1)
	_check("non-finite aircraft contact geometry rejects before corridor checks",
		not bad_model_result.get("ok", false) and _error_contains(bad_model_result, "Aircraft contact geometry is invalid:"),
		str(bad_model_result.get("errors", [])))


func _test_geometry_fingerprint() -> void:
	var original: Dictionary = _validate(_world, _field, _field_profile, _surfaces, _lake, _model, 1)
	var moved_world: Dictionary = _world.duplicate(true)
	var changed_proxies: Array = moved_world.proxies
	var changed: Dictionary = changed_proxies[0].duplicate(true)
	changed.north = float(changed.north) + 0.5
	_rebuild_bounds(changed)
	changed_proxies[0] = changed
	moved_world.proxies = changed_proxies
	# Keep the builder's original identity to prove the report hashes actual geometry.
	var moved: Dictionary = _validate(moved_world, _field, _field_profile, _surfaces, _lake, _model, 1)
	_check("geometry mutation preserves the caller-supplied collision identity", moved_world.identity == _world.identity)
	_check("report geometry fingerprint changes when normalized bounds change under the same identity",
		original.get("report", {}).get("geometry_sha256", "") != moved.get("report", {}).get("geometry_sha256", "")
		and str(original.get("report", {}).get("geometry_sha256", "")).length() == 64
		and str(moved.get("report", {}).get("geometry_sha256", "")).length() == 64,
		"original=%s changed=%s" % [original.get("report", {}).get("geometry_sha256", ""), moved.get("report", {}).get("geometry_sha256", "")])


func _test_sampled_oracle() -> void:
	var oracle_checks := 0
	var misses := 0
	var height := float(_field_profile.circuit.base_agl.value) - _pilot_down
	var down := _pilot_down - float(_field_profile.circuit.base_agl.value)
	for index: int in ORACLE_ANGLE_SAMPLES:
		var angle := TAU * float(index) / float(ORACLE_ANGLE_SAMPLES)
		var north := _center_north + _route_radius * cos(angle)
		var east := _center_east + _route_radius * sin(angle)
		var heading := rad_to_deg(angle * 0.37)
		var proxy: Dictionary = _box(north, east, down, 0.12, 0.12, 0.12, heading, "sample-oracle-%04d" % index)
		if not _oriented_box_contains(proxy, north, east):
			continue
		oracle_checks += 1
		var result := _validate(_world_for(proxy), _field, _field_profile, _surfaces, {}, _model, 1)
		if result.get("ok", false):
			misses += 1
	_check("independent %d-angle oracle found no sampled corridor contact that escaped refusal" % ORACLE_ANGLE_SAMPLES,
		oracle_checks == ORACLE_ANGLE_SAMPLES and misses == 0,
		"sampled=%d escaped=%d height=%.3f" % [oracle_checks, misses, height])


func _validate(world: Dictionary, field: Dictionary, field_profile: Dictionary,
		surfaces: PackedFloat64Array, lake: Dictionary, model: Dictionary, count: int) -> Dictionary:
	return Airspace.validate(field_profile, field, world, surfaces, lake, model, count)


func _check_refused(label: String, world: Dictionary) -> void:
	var result: Dictionary = _validate(world, _field, _field_profile, _surfaces, {}, _model, 1)
	_check(label, not result.get("ok", false), str(result.get("errors", [])))


func _error_contains(result: Dictionary, needle: String) -> bool:
	for error: Variant in result.get("errors", PackedStringArray()):
		if needle in str(error):
			return true
	return false


func _proxy_template(shape: String) -> Dictionary:
	for value: Variant in _world.get("proxies", []):
		if typeof(value) == TYPE_DICTIONARY and str(value.get("shape", "")) == shape:
			return (value as Dictionary).duplicate(true)
	return {}


func _box(north: float, east: float, down: float, width: float, height: float,
		length: float, heading_deg: float, proxy_id: String) -> Dictionary:
	var proxy: Dictionary = _box_template.duplicate(true)
	proxy.id = proxy_id
	proxy.kind = "test_obstacle"
	proxy.part = "test_box"
	proxy.shape = "box"
	proxy.north = north
	proxy.east = east
	proxy.down = down
	proxy.radius = 0.0
	proxy.half_length = 0.0
	proxy.half_x = width * 0.5
	proxy.half_down = height * 0.5
	proxy.half_z = length * 0.5
	proxy.sin_heading = sin(deg_to_rad(heading_deg))
	proxy.cos_heading = cos(deg_to_rad(heading_deg))
	_rebuild_bounds(proxy)
	return proxy


func _capsule(north: float, east: float, down: float, radius: float,
		half_length: float, proxy_id: String) -> Dictionary:
	var proxy: Dictionary = _capsule_template.duplicate(true)
	proxy.id = proxy_id
	proxy.kind = "test_obstacle"
	proxy.part = "test_capsule"
	proxy.shape = "capsule"
	proxy.north = north
	proxy.east = east
	proxy.down = down
	proxy.radius = radius
	proxy.half_length = half_length
	proxy.half_x = 0.0
	proxy.half_down = 0.0
	proxy.half_z = 0.0
	proxy.sin_heading = 0.0
	proxy.cos_heading = 1.0
	_rebuild_bounds(proxy)
	return proxy


func _rebuild_bounds(proxy: Dictionary) -> void:
	var north_extent := 0.0
	var east_extent := 0.0
	var down_extent := 0.0
	if str(proxy.shape) == "box":
		north_extent = absf(float(proxy.sin_heading)) * float(proxy.half_x) + absf(float(proxy.cos_heading)) * float(proxy.half_z)
		east_extent = absf(float(proxy.cos_heading)) * float(proxy.half_x) + absf(float(proxy.sin_heading)) * float(proxy.half_z)
		down_extent = float(proxy.half_down)
	else:
		north_extent = float(proxy.radius)
		east_extent = float(proxy.radius)
		down_extent = float(proxy.radius) + float(proxy.half_length)
	proxy.bounds_north_min = float(proxy.north) - north_extent
	proxy.bounds_north_max = float(proxy.north) + north_extent
	proxy.bounds_east_min = float(proxy.east) - east_extent
	proxy.bounds_east_max = float(proxy.east) + east_extent
	proxy.bounds_down_min = float(proxy.down) - down_extent
	proxy.bounds_down_max = float(proxy.down) + down_extent


func _world_for(proxy: Dictionary) -> Dictionary:
	return {
		"format": str(_world.get("format", "")),
		"identity": str(_world.get("identity", "")),
		"cell_size_m": float(_world.get("cell_size_m", 32.0)),
		"proxies": [proxy.duplicate(true)],
		"bins": {},
	}


func _expected_radius() -> float:
	var description: Dictionary = ContactContract.describe(_model, false)
	if not description.get("ok", false):
		return NAN
	var radius := 0.0
	for point: Dictionary in description.hull_probes + description.support_points:
		radius = maxf(radius, sqrt(point.position[0] * point.position[0]
			+ point.position[1] * point.position[1] + point.position[2] * point.position[2]))
	var disc: Dictionary = description.rotor_disc
	if not disc.is_empty():
		var hub: PackedFloat64Array = disc.hub
		radius = maxf(radius, sqrt(hub[0] * hub[0] + hub[1] * hub[1] + hub[2] * hub[2]) + float(disc.radius))
	return radius


func _coarse_centerline_sample_hits(proxy: Dictionary) -> bool:
	for sample: int in 360:
		var angle := TAU * float(sample) / 360.0
		var north := _center_north + _route_radius * cos(angle)
		var east := _center_east + _route_radius * sin(angle)
		if north >= float(proxy.bounds_north_min) and north <= float(proxy.bounds_north_max) \
				and east >= float(proxy.bounds_east_min) and east <= float(proxy.bounds_east_max):
			return true
	return false


func _oriented_box_contains(proxy: Dictionary, north: float, east: float) -> bool:
	var delta_n := north - float(proxy.north)
	var delta_e := east - float(proxy.east)
	var local_x := -float(proxy.sin_heading) * delta_n + float(proxy.cos_heading) * delta_e
	var local_z := -float(proxy.cos_heading) * delta_n - float(proxy.sin_heading) * delta_e
	return absf(local_x) <= float(proxy.half_x) and absf(local_z) <= float(proxy.half_z)


func _finish() -> void:
	print("AFC-02 static airspace validation: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _requested_output_path() -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in args.size():
		if args[index] == "--out" and index + 1 < args.size():
			return args[index + 1]
		if args[index].begins_with("--out="):
			return args[index].substr(6)
	return ""


func _write_production_report(path: String) -> void:
	if path.is_empty():
		return
	if _production_report.is_empty():
		_check("production report is available before writing evidence", false)
		return
	if FileAccess.file_exists(path):
		_check("production evidence output does not overwrite an existing file", false, path)
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check("production evidence report opens for a new write", false, "error %d: %s" % [FileAccess.get_open_error(), path])
		return
	var report_file := {format = "openrc-ai-static-airspace-report v1", report = _production_report}
	file.store_string(JSON.stringify(report_file, "\t") + "\n")
	file.close()
	_check("production report with real radius, gap, proxy count and hashes is written", FileAccess.file_exists(path), path)
