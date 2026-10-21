extends SceneTree

const FieldLoader := preload("res://data/field_loader.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")


func _initialize() -> void:
	var field_result: Dictionary = FieldLoader.load_from()
	if not bool(field_result.get("ok", false)):
		_fail("field load failed: %s" % str(field_result.get("errors", [])))
		return
	var field: Dictionary = field_result.field
	var surface_table_result: Dictionary = GroundSurfaces.load_table()
	if not bool(surface_table_result.get("ok", false)):
		_fail("surface table load failed: %s" % str(surface_table_result.get("errors", [])))
		return
	var surface_result: Dictionary = GroundSurfaces.build(surface_table_result.table, field)
	if not bool(surface_result.get("ok", false)):
		_fail("surface build failed: %s" % str(surface_result.get("errors", [])))
		return
	var collision_result: Dictionary = CollisionSetup.build(field)
	if not bool(collision_result.get("ok", false)):
		_fail("collision inventory build failed: %s" % str(collision_result.get("errors", [])))
		return
	var aircraft_result: Dictionary = AircraftData.load_file("res://data/aircraft/jensen_ugly_stik_60.json")
	if not bool(aircraft_result.get("ok", false)):
		_fail("aircraft load failed: %s" % str(aircraft_result.get("errors", [])))
		return
	var model: Dictionary = aircraft_result.model
	var runway := _runway_for(field)
	var obstacles: Array[Dictionary] = []
	for proxy_value: Variant in collision_result.world.get("proxies", []):
		if typeof(proxy_value) != TYPE_DICTIONARY:
			continue
		var proxy: Dictionary = proxy_value
		var east_min := float(proxy.get("bounds_east_min", NAN))
		var east_max := float(proxy.get("bounds_east_max", NAN))
		var north_min := float(proxy.get("bounds_north_min", NAN))
		var north_max := float(proxy.get("bounds_north_max", NAN))
		if north_max < 7.0 or north_min > 27.0 or east_max < -56.0 or east_min > 56.0:
			continue
		obstacles.append({
			id = str(proxy.get("id", "")),
			kind = str(proxy.get("kind", "")),
			part = str(proxy.get("part", "")),
			response = str(proxy.get("response_class", "")),
			shape = str(proxy.get("shape", "")),
			north_m = float(proxy.get("north", NAN)),
			east_m = float(proxy.get("east", NAN)),
			radius_m = float(proxy.get("radius", 0.0)),
			half_length_m = float(proxy.get("half_length", 0.0)),
			north_min_m = north_min,
			north_max_m = north_max,
			east_min_m = east_min,
			east_max_m = east_max,
			down_min_m = float(proxy.get("bounds_down_min", NAN)),
			down_max_m = float(proxy.get("bounds_down_max", NAN)),
		})
	var contacts: Array[Dictionary] = []
	for contact_value: Variant in model.landing_gear.get("contacts", []):
		if typeof(contact_value) != TYPE_DICTIONARY:
			continue
		var contact: Dictionary = contact_value
		contacts.append({
			name = str(contact.get("name", "")),
			position_body_m = Array(contact.get("position", PackedFloat64Array())),
			max_steering_rad = float(contact.get("max_steering", 0.0)),
		})
	var hull: Array = []
	var crash_hull: PackedFloat64Array = model.get("crash_hull", PackedFloat64Array())
	for i in range(0, crash_hull.size(), 3):
		hull.append([crash_hull[i], crash_hull[i + 1], crash_hull[i + 2]])
	var surfaces: Array = []
	var rects: PackedFloat64Array = surface_result.rects
	for i in range(0, rects.size(), 6):
		surfaces.append({
			north_min_m = rects[i], north_max_m = rects[i + 1],
			east_min_m = rects[i + 2], east_max_m = rects[i + 3],
			friction_factor = rects[i + 4], rolling_factor = rects[i + 5],
		})
	var result := {
		"format": "AFC09-taxi-exit-area-inspection-v1",
		"field_id": str(field.get("id", "")),
		"collision_identity": str(collision_result.world.get("identity", "")),
		"collision_proxy_count": collision_result.world.get("proxies", []).size(),
		"runway": runway,
		"terrain_rectangles": surfaces,
		"relevant_collision_proxies": obstacles,
		"aircraft_id": str(model.get("id", "")),
		"gear_contacts": contacts,
		"crash_hull_body_points_m": hull,
	}
	var output_path := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output_path = arg.trim_prefix("--out=")
	if output_path.is_empty():
		_fail("missing --out=<fresh external evidence path>")
		return
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		_fail("cannot open output path %s (error %d)" % [output_path, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(result, "\t", false))
	file.close()
	print("AFC09_EXIT_AREA_AUDIT %s" % JSON.stringify({
		"path": output_path,
		"collision_identity": result.collision_identity,
		"proxy_count": result.collision_proxy_count,
		"local_proxy_count": obstacles.size(),
		"contact_count": contacts.size(),
		"hull_point_count": hull.size(),
		"surface_count": surfaces.size(),
	}))
	quit(0)


func _runway_for(field: Dictionary) -> Dictionary:
	for surface_value: Variant in field.get("surfaces", []):
		if typeof(surface_value) != TYPE_DICTIONARY:
			continue
		var surface: Dictionary = surface_value
		if str(surface.get("id", "")) == str(field.get("runway", "")):
			return surface.duplicate(true)
	return {}


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
