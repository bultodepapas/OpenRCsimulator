extends SceneTree
const FieldLoader := preload("res://data/field_loader.gd")
const SceneryLoader := preload("res://scenery/scenery_loader.gd")
const ParkedAircraft := preload("res://scenery/parked_aircraft.gd")
const Palette := preload("res://scenery/palette.gd")

const CHAIR_HALF_X := 0.31
const CHAIR_HALF_Z := 0.265
const CHAIR_LOCAL_Z_OFFSET := 0.047
const CHAIR_MIN_UP := 0.10
const CHAIR_MAX_UP := 1.03

var furniture: Array[Dictionary] = []
var aircraft: Array[Dictionary] = []
var reported_supports := 0
var reported_interferences := 0
var compared_part_pairs := 0

func _initialize() -> void:
	var field_result: Dictionary = FieldLoader.load_from()
	var scenery_result: Dictionary = SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, field_result.field)
	if not field_result.ok or not scenery_result.ok:
		printerr("load failed field=%s scenery=%s" % [field_result.get("errors", []), scenery_result.get("errors", [])])
		quit(1)
		return
	var shelters: Array[Dictionary] = []
	for group: Dictionary in scenery_result.scenery.groups:
		if str(group.id) == "pit-shelters":
			for placement: Dictionary in group.placements:
				shelters.append(placement)
		if str(group.type) == "fleet":
			for placement: Dictionary in group.placements:
				var row := placement.duplicate(true)
				row.group_id = str(group.id)
				row.parts = _plane_shapes(placement)
				aircraft.append(row)
	for shelter_index: int in shelters.size():
		_add_shelter_furniture(shelters[shelter_index], shelter_index)
	for plane: Dictionary in aircraft:
		print("AIRCRAFT group=%s id=%s config=%s scale=%.3f elevation=%.3f n=%.3f e=%.3f heading=%.2f parts=%d" % [
			plane.group_id, plane.aircraft, plane.configuration, float(plane.scale), float(plane.elevation),
			float(plane.north), float(plane.east), float(plane.heading), plane.parts.size()])
		for part: Dictionary in plane.parts:
			for prop: Dictionary in furniture:
				var horizontal_depth := _planform_overlap(part, prop)
				var vertical_depth := _vertical_overlap(part, prop)
				if horizontal_depth > 0.001 and vertical_depth > 0.001:
					compared_part_pairs += 1
					var support_kind := _support_contact_kind(plane, prop)
					if not support_kind.is_empty():
						reported_supports += 1
						print("SUPPORT_CONTACT plane=%s/%s part=%s furniture=%s support=%s planform=%.3f vertical=%.3f" % [
							plane.group_id, plane.aircraft, part.part, prop.part, support_kind, horizontal_depth, vertical_depth])
					else:
						reported_interferences += 1
						print("FURNITURE_INTERFERENCE plane=%s/%s part=%s furniture=%s planform=%.3f vertical=%.3f" % [
							plane.group_id, plane.aircraft, part.part, prop.part, horizontal_depth, vertical_depth])
	print("SUMMARY shelters=%d aircraft=%d furniture_boxes=%d part_pairs=%d expected_support_contacts=%d candidate_interferences=%d" % [
		shelters.size(), aircraft.size(), furniture.size(), compared_part_pairs, reported_supports, reported_interferences])
	quit(0)

func _add_shelter_furniture(shelter: Dictionary, shelter_index: int) -> void:
	var seed := int(shelter.seed)
	print("SHELTER index=%d center_n=%.3f center_e=%.3f heading=%.2f normalized_seed=%d" % [
		shelter_index, float(shelter.north), float(shelter.east), float(shelter.heading), seed])
	for i: int in 6:
		var tx := -14.0 + 2.4 + float(i) * 4.6
		var tz := 5.0 * 0.5 - 1.1
		var table_seed := seed * 31 + i
		_add_local_box(shelter, tx, 0.84, tz, 2.4, 0.06, 0.8,
			"shelter:%02d:table:%d:top" % [shelter_index, i], "table_surface")
		for sx: float in [-1.1, 1.1]:
			for sz: float in [-0.32, 0.32]:
				_add_local_box(shelter, tx + sx, 0.1, tz + sz, 0.06, 0.74, 0.06,
					"shelter:%02d:table:%d:leg:%s:%s" % [shelter_index, i, str(sx), str(sz)], "table_leg")
		if Palette.hash01(table_seed, 2) < 0.7:
			for side: float in [-0.5, 0.5]:
				_add_local_box(shelter, tx + side, 0.9, tz, 0.3, 0.22, 0.5,
					"shelter:%02d:table:%d:foam:%s" % [shelter_index, i, str(side)], "foam_support")
		if Palette.hash01(table_seed, 3) < 0.6:
			_add_local_box(shelter, tx + 0.8, 0.9, tz + 0.15, 0.24, 0.1, 0.18,
				"shelter:%02d:table:%d:field_box" % [shelter_index, i], "field_box")
		if Palette.hash01(table_seed, 4) < 0.5:
			_add_local_box(shelter, tx - 0.9, 0.9, tz + 0.2, 0.5, 0.25, 0.3,
				"shelter:%02d:table:%d:tool_box" % [shelter_index, i], "tool_box")
		if i == 1:
			_add_local_box(shelter, tx, 0.9, tz, 0.27, 0.14, 0.22,
				"shelter:%02d:table:%d:charger" % [shelter_index, i], "charger")
			_add_local_box(shelter, tx + 0.235, 0.9, tz + 0.01, 0.14, 0.08, 0.13,
				"shelter:%02d:table:%d:battery_pack" % [shelter_index, i], "charger_pack")
		if i == 4:
			_add_local_box(shelter, tx, 0.98, tz + 0.01, 0.20, 0.36, 0.18,
				"shelter:%02d:table:%d:fuel_jug" % [shelter_index, i], "fuel_jug")
		print("TABLE shelter=%d i=%d local=(%.2f,%.2f) foam=%s field_box=%s tool_box=%s service=%s" % [
			shelter_index, i, tx, tz, str(Palette.hash01(table_seed, 2) < 0.7),
			str(Palette.hash01(table_seed, 3) < 0.6), str(Palette.hash01(table_seed, 4) < 0.5),
			"charger" if i == 1 else "fuel" if i == 4 else "none"])
	for i: int in 5:
		var exists_hash := Palette.hash01(seed, i, 3)
		var x_hash := Palette.hash01(seed, i, 7)
		var z_hash := Palette.hash01(seed, i, 5)
		var yaw_hash := Palette.hash01(seed, i, 9)
		var cx := -14.0 + 4.2 + float(i) * 5.3 + (x_hash - 0.5) * 1.2
		var cz := -0.4 + z_hash * 0.8
		var yaw := yaw_hash * 1.2 - 0.6
		if exists_hash < 0.75:
			var chair_center := _local_to_ne(float(shelter.north), float(shelter.east), float(shelter.heading), cx, cz + CHAIR_LOCAL_Z_OFFSET)
			_add_world_shape(chair_center[0], chair_center[1], float(shelter.heading) - rad_to_deg(yaw),
				CHAIR_HALF_X, CHAIR_HALF_Z, CHAIR_MIN_UP, CHAIR_MAX_UP,
				"shelter:%02d:chair:%d" % [shelter_index, i], "chair")
		print("CHAIR shelter=%d i=%d exists=%s center_local=(%.3f,%.3f) center_n=%.3f center_e=%.3f yaw_local_deg=%.3f hashes=(%.5f,%.5f,%.5f,%.5f)" % [
			shelter_index, i, str(exists_hash < 0.75), cx, cz, float(_local_to_ne(float(shelter.north), float(shelter.east), float(shelter.heading), cx, cz)[0]),
			float(_local_to_ne(float(shelter.north), float(shelter.east), float(shelter.heading), cx, cz)[1]), rad_to_deg(yaw),
			exists_hash, x_hash, z_hash, yaw_hash])
		if Palette.hash01(seed, i, 11) < 0.45:
			_add_local_box(shelter, cx + 1.2, 0.1, 0.9, 0.6, 0.42, 0.38,
				"shelter:%02d:cooler:%d" % [shelter_index, i], "cooler")
			print("COOLER shelter=%d i=%d center_local=(%.3f,0.1,0.9)" % [shelter_index, i, cx + 1.2])
	for i: int in 3:
		var bx := -14.0 + 6.0 + float(i) * 8.5
		_add_local_box(shelter, bx, 0.1, -1.4, 0.75, 0.32, 0.32,
			"shelter:%02d:front_box:%d" % [shelter_index, i], "front_box")
		_add_local_box(shelter, bx + 0.55, 0.1, -1.35, 0.14, 0.3, 0.14,
			"shelter:%02d:front_box:%d:fuel_bottle" % [shelter_index, i], "front_fuel_bottle")

func _plane_shapes(plane: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var info: Dictionary = ParkedAircraft.info(str(plane.aircraft), str(plane.configuration))
	var scale := float(plane.scale)
	for part_value: Variant in info.get("collision_parts", []):
		var part: Dictionary = part_value
		var center: Array = part.center
		var size: Array = part.size
		var world_center := _local_to_ne(float(plane.north), float(plane.east), float(plane.heading),
			float(center[0]) * scale, float(center[2]) * scale)
		var half_up := float(size[1]) * scale * 0.5
		out.append(_shape(world_center[0], world_center[1], float(plane.heading),
			float(size[0]) * scale * 0.5, float(size[2]) * scale * 0.5,
			float(plane.elevation) + float(center[1]) * scale - half_up,
			float(plane.elevation) + float(center[1]) * scale + half_up, str(part.part), "aircraft"))
	return out

func _add_local_box(shelter: Dictionary, x: float, y: float, z: float,
		size_x: float, size_y: float, size_z: float, name: String, category: String) -> void:
	var center := _local_to_ne(float(shelter.north), float(shelter.east), float(shelter.heading), x, z)
	_add_world_shape(center[0], center[1], float(shelter.heading), size_x * 0.5, size_z * 0.5,
		y - size_y * 0.5, y + size_y * 0.5, name, category)

func _add_world_shape(north: float, east: float, heading: float, half_x: float, half_z: float,
		up_min: float, up_max: float, name: String, category: String) -> void:
	furniture.append(_shape(north, east, heading, half_x, half_z, up_min, up_max, name, category))

func _shape(north: float, east: float, heading: float, half_x: float, half_z: float,
		up_min: float, up_max: float, part: String, category: String) -> Dictionary:
	return {"north": north, "east": east, "heading": heading, "half_x": half_x, "half_z": half_z,
		"up_min": up_min, "up_max": up_max, "part": part, "category": category}

func _support_contact_kind(plane: Dictionary, prop: Dictionary) -> String:
	var group_id := str(plane.group_id)
	var category := str(prop.category)
	if category == "table_surface" and group_id in ["fleet-micro-bench", "fleet-sport-bench", "fleet-service"]:
		return "table surface under designated bench aircraft"
	if category == "foam_support" and group_id in ["fleet-micro-bench", "fleet-sport-bench", "fleet-service"]:
		return "foam cradle on designated bench aircraft"
	return ""

func _local_to_ne(north: float, east: float, heading_deg: float, local_x: float, local_z: float) -> Array[float]:
	var h := deg_to_rad(heading_deg)
	return [north - sin(h) * local_x - cos(h) * local_z,
		east + cos(h) * local_x - sin(h) * local_z]

func _axes(shape: Dictionary) -> Array[Vector2]:
	var h := deg_to_rad(float(shape.heading))
	return [Vector2(-sin(h), cos(h)), Vector2(-cos(h), -sin(h))]

func _project_radius(shape: Dictionary, axis: Vector2) -> float:
	var axes := _axes(shape)
	return float(shape.half_x) * absf(axes[0].dot(axis)) + float(shape.half_z) * absf(axes[1].dot(axis))

func _planform_overlap(a: Dictionary, b: Dictionary) -> float:
	var minimum := INF
	var delta_vec := Vector2(float(b.north) - float(a.north), float(b.east) - float(a.east))
	for axis in _axes(a) + _axes(b):
		var delta := delta_vec.dot(axis)
		var depth := _project_radius(a, axis) + _project_radius(b, axis) - absf(delta)
		minimum = minf(minimum, depth)
	return minimum

func _vertical_overlap(a: Dictionary, b: Dictionary) -> float:
	return minf(float(a.up_max), float(b.up_max)) - maxf(float(a.up_min), float(b.up_min))
