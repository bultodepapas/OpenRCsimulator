# FIELD-WORLD-PLAN FW-31…FW-34: the field's night lights from app/data/fields/lights.json (openrc-field-lights v1).
# - "flood": a pole, a glowing lamp head and one SpotLight3D without shadows. Compatibility lights at most 8 omni +
#   8 spot lights per mesh and the ground is one mesh, so floods are capped (MAX_FLOODS, with the airplane's landing
#   light the field stays well inside the limit); shadowed positional lights would add passes, so none cast shadows.
# - "stake_row": self-luminous points only (one MultiMesh of light sprites per row): edge, threshold, station lamps.
# Visual only: nothing here touches the simulation. Brightness is physical in scene units (see "conversion").
extends RefCounted

const Frames := preload("res://render/frames.gd")
const Spec := preload("res://spec.gd")
const Exposure := preload("res://render/world/exposure.gd")
const SPRITE_SHADER := preload("res://render/world/light_sprite.gdshader")

const DEFAULT_PATH := "res://data/fields/lights.json"
const FORMAT_V1 := "openrc-field-lights v1"
const FORMAT_V2 := "openrc-field-lights v2"
const FORMAT := FORMAT_V2
const MAX_FLOODS := 4
const MAX_SPOTS := 6 # reserve two Compatibility spots for aircraft with paired landing lamps.
const QUANTITY_KEYS: Array[String] = ["value", "unit", "kind", "source"]
const KINDS: Array[String] = ["measured", "borrowed", "estimated", "derived", "manual", "calculated"]
const FLOOD_UNITS := {north = "m", east = "m", height = "m", aim_north = "m", aim_east = "m", aim_height = "m",
	intensity = "cd", beam_half_angle = "deg", range = "m", color_temperature = "K"}
const FLOOD_REQUIRED: Array[String] = ["north", "east", "height", "aim_north", "aim_east", "intensity", "beam_half_angle", "range", "color_temperature"]
const STAKE_UNITS := {points = "m", height = "m", intensity = "cd", size = "m", color_temperature = "K", color = "srgb"}
const STAKE_REQUIRED: Array[String] = ["points", "height", "intensity", "size"]
const FLOOD_HEAD_SIZE_M := 0.5
const POLE_RADIUS_M := 0.07


## Validates a lights file: {ok, errors, lights}. `lights.fixtures` keep plain values (quantities unwrapped).
static func load_from(path: String = DEFAULT_PATH) -> Dictionary:
	var errors: PackedStringArray = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {ok = false, errors = PackedStringArray(["%s: cannot open" % path]), lights = {}}
	var root: Variant = JSON.parse_string(f.get_as_text())
	return validate(root)


static func validate(root: Variant) -> Dictionary:
	if not (root is Dictionary):
		return {ok = false, errors = PackedStringArray(["lights: not a JSON object"]), lights = {}}
	match str(root.get("format", "")):
		FORMAT_V1:
			return _validate_v1(root)
		FORMAT_V2:
			return _validate_v2(root)
		_:
			return {ok = false, errors = PackedStringArray(["lights.format: expected '%s' or '%s'" % [FORMAT_V1, FORMAT_V2]]), lights = {}}


static func _validate_v1(root: Dictionary) -> Dictionary:
	var errors: PackedStringArray = []
	var conversion: Variant = _quantity(errors, "lights.conversion", root.get("conversion"), "lux per scene unit")
	if conversion is float and float(conversion) <= 0.0:
		errors.append("lights.conversion: must be positive")
	var fixtures: Array = []
	var floods := 0
	var ids := {}
	var raw: Variant = root.get("fixtures")
	if not (raw is Array) or (raw as Array).is_empty():
		errors.append("lights.fixtures: expected a non-empty array")
		raw = []
	for i in (raw as Array).size():
		var fx: Variant = raw[i]
		var path := "lights.fixtures[%d]" % i
		if not (fx is Dictionary):
			errors.append("%s: not an object" % path)
			continue
		var id := str(fx.get("id", ""))
		if id.is_empty() or id.strip_edges() != id or ids.has(id):
			errors.append("%s.id: missing, padded or duplicate" % path)
		ids[id] = true
		var type := str(fx.get("type", ""))
		var units: Dictionary
		var required: Array[String]
		if type == "flood":
			units = FLOOD_UNITS
			required = FLOOD_REQUIRED
			floods += 1
		elif type == "stake_row":
			units = STAKE_UNITS
			required = STAKE_REQUIRED
		else:
			errors.append("%s.type: unknown '%s' (flood, stake_row)" % [path, type])
			continue
		var legacy_role := "windsock_flood" if id == "windsock_flood" else ("runway_flood" if type == "flood" else _legacy_stake_role(id))
		var out := {id = id, type = type, role = legacy_role,
		distance_attenuation = 1.0, angular_attenuation = 1.0}
		for key: String in fx.keys():
			if key == "id" or key == "type":
				continue
			if not units.has(key):
				errors.append("%s.%s: unknown key" % [path, key])
				continue
			out[key] = _quantity(errors, "%s.%s" % [path, key], fx[key], units[key])
		for key: String in required:
			if not fx.has(key):
				errors.append("%s.%s: required" % [path, key])
		if type == "stake_row" and not fx.has("color") and not fx.has("color_temperature"):
			errors.append("%s: needs color or color_temperature" % path)
		for key: String in ["intensity", "range", "size"]:
			if out.get(key) is float and float(out[key]) <= 0.0:
				errors.append("%s.%s: must be positive" % [path, key])
		if out.get("height") is float and float(out.height) < 0.0:
			errors.append("%s.height: must not be negative" % path)
		if out.get("beam_half_angle") is float and not (float(out.beam_half_angle) > 1.0 and float(out.beam_half_angle) < 80.0):
			errors.append("%s.beam_half_angle: must be within (1, 80) deg" % path)
		if out.get("points") != null:
			var pts: Variant = out.points
			var ok := pts is Array and not (pts as Array).is_empty()
			if ok:
				for p: Variant in pts:
					ok = ok and p is Array and (p as Array).size() == 2 and (p[0] is float or p[0] is int) and (p[1] is float or p[1] is int) \
						and is_finite(float(p[0])) and is_finite(float(p[1]))
			if not ok:
				errors.append("%s.points: expected [[north, east], ...] in metres" % path)
		if out.get("color") != null and not (out.color is String and Color.html_is_valid(out.color)):
			errors.append("%s.color: expected an sRGB hex colour" % path)
		fixtures.append(out)
	if floods > MAX_FLOODS:
		errors.append("lights: %d floods exceed %d (Compatibility lights ≤ 8 spots per mesh; the airplane adds one)" % [floods, MAX_FLOODS])
	return {ok = errors.is_empty(), errors = errors, lights = {version = 1, conversion = conversion,
		fixtures = fixtures, installations = []}}


static func _legacy_stake_role(id: String) -> String:
	match id:
		"runway_edge_stakes": return "runway_edge"
		"threshold_stakes": return "runway_threshold"
		"pilot_station_lamp": return "pilot_station"
		_: return "marker"


static func _validate_v2(root: Dictionary) -> Dictionary:
	var errors: PackedStringArray = []
	var conversion: Variant = _quantity(errors, "lights.conversion", root.get("conversion"), "lux per scene unit")
	if conversion is float and (not is_finite(conversion) or float(conversion) <= 0.0):
		errors.append("lights.conversion: must be finite and positive")
	var installations: Array[Dictionary] = []
	var installation_ids := {}
	var raw_installations: Variant = root.get("installations", [])
	if not (raw_installations is Array) or (raw_installations as Array).is_empty():
		errors.append("lights.installations: expected a non-empty array")
		raw_installations = []
	for index: int in (raw_installations as Array).size():
		var raw: Variant = raw_installations[index]
		var path := "lights.installations[%d]" % index
		if not (raw is Dictionary):
			errors.append("%s: not an object" % path)
			continue
		var item: Dictionary = raw
		var id := str(item.get("id", ""))
		var kind := str(item.get("type", ""))
		if id.is_empty() or id.strip_edges() != id or installation_ids.has(id):
			errors.append("%s.id: missing, padded or duplicate" % path)
		installation_ids[id] = true
		if not kind in ["mast", "low_light_mount", "marker_array", "campfire_base"]:
			errors.append("%s.type: expected mast, low_light_mount, marker_array or campfire_base" % path)
		var allowed := ["id", "type", "north", "east", "heading", "height", "collision_radius", "width", "depth"]
		for key: Variant in item.keys():
			if not allowed.has(str(key)):
				errors.append("%s.%s: unknown key" % [path, str(key)])
		var normalized := {"id": id, "type": kind}
		for key: String in ["north", "east", "heading", "height", "collision_radius", "width", "depth"]:
			if item.has(key):
				var unit := "deg" if key == "heading" else "m"
				normalized[key] = _quantity(errors, "%s.%s" % [path, key], item[key], unit)
		if kind in ["mast", "low_light_mount", "campfire_base"]:
			for key: String in ["north", "east", "height"]:
				if not normalized.has(key): errors.append("%s.%s: required" % [path, key])
		if kind == "campfire_base":
			for key: String in ["width", "depth", "collision_radius"]:
				if not normalized.has(key): errors.append("%s.%s: required for campfire proxy" % [path, key])
		for key: String in ["height", "collision_radius", "width", "depth"]:
			if normalized.get(key) is float and (not is_finite(normalized[key]) or float(normalized[key]) <= 0.0):
				errors.append("%s.%s: must be finite and positive" % [path, key])
		installations.append(normalized)
	var mast_count := 0
	for installation: Dictionary in installations:
		if installation.type == "mast": mast_count += 1
	if mast_count != 1:
		errors.append("lights.installations: expected exactly one mast, found %d" % mast_count)
	var fixtures: Array[Dictionary] = []
	var ids := {}
	var raw_emitters: Variant = root.get("emitters", [])
	if not (raw_emitters is Array) or (raw_emitters as Array).is_empty():
		errors.append("lights.emitters: expected a non-empty array")
		raw_emitters = []
	var spot_count := 0
	for index: int in (raw_emitters as Array).size():
		var raw: Variant = raw_emitters[index]
		var path := "lights.emitters[%d]" % index
		if not (raw is Dictionary):
			errors.append("%s: not an object" % path)
			continue
		var source: Dictionary = raw
		var id := str(source.get("id", ""))
		var installation_id := str(source.get("installation_id", ""))
		var role := str(source.get("role", ""))
		if id.is_empty() or id.strip_edges() != id or ids.has(id): errors.append("%s.id: missing, padded or duplicate" % path)
		ids[id] = true
		if not installation_ids.has(installation_id): errors.append("%s.installation_id: unknown installation '%s'" % [path, installation_id])
		if role.is_empty() or role.strip_edges() != role: errors.append("%s.role: required and must not be padded" % path)
		var type := str(source.get("type", ""))
		var normalized: Dictionary = {"id": id, "type": "flood", "installation_id": installation_id, "role": role}
		if type == "spot":
			spot_count += 1
			var units := {"north":"m", "east":"m", "height":"m", "aim_north":"m", "aim_east":"m", "aim_height":"m",
				"intensity":"cd", "beam_half_angle":"deg", "range":"m", "color_temperature":"K",
				"distance_attenuation":"ratio", "angular_attenuation":"ratio"}
			var allowed := ["id", "type", "installation_id", "role"]
			for key: Variant in units.keys(): allowed.append(key)
			for key: Variant in source.keys():
				if not allowed.has(str(key)): errors.append("%s.%s: unknown key" % [path, str(key)])
			for key: String in units.keys():
				if not source.has(key):
					errors.append("%s.%s: required" % [path, key])
				else:
					normalized[key] = _quantity(errors, "%s.%s" % [path, key], source[key], units[key])
			for key: String in ["intensity", "range", "color_temperature", "distance_attenuation", "angular_attenuation", "height"]:
				if normalized.get(key) is float and (not is_finite(normalized[key]) or float(normalized[key]) <= 0.0):
					errors.append("%s.%s: must be finite and positive" % [path, key])
			var angle: Variant = normalized.get("beam_half_angle")
			if angle is float and (not is_finite(angle) or float(angle) <= 1.0 or float(angle) >= 80.0): errors.append("%s.beam_half_angle: must be within (1, 80) deg" % path)
			if normalized.get("color_temperature") is float and (float(normalized.color_temperature) < 1000.0 or float(normalized.color_temperature) > 12000.0):
				errors.append("%s.color_temperature: must be within 1000–12000 K" % path)
			var vector_fields := ["north", "east", "height", "aim_north", "aim_east", "aim_height"]
			var vector_values_valid := true
			for key: String in vector_fields:
				vector_values_valid = vector_values_valid and (normalized.get(key) is float)
			if vector_values_valid:
				var position := Vector3(normalized.north, normalized.east, normalized.height)
				var target := Vector3(normalized.aim_north, normalized.aim_east, normalized.aim_height)
				if position.is_finite() and target.is_finite() and position.distance_to(target) < 0.001:
					errors.append("%s: aim point must differ from emitter position" % path)
		elif type == "stake_row":
			normalized.type = "stake_row"
			for key: String in ["points", "height", "intensity", "size", "color_temperature", "color"]:
				if source.has(key):
					var unit := "m" if key == "points" or key == "height" or key == "size" else ("cd" if key == "intensity" else ("K" if key == "color_temperature" else "srgb"))
					normalized[key] = _quantity(errors, "%s.%s" % [path, key], source[key], unit)
			if not source.has("points") or not source.has("height") or not source.has("intensity") or not source.has("size"):
				errors.append("%s: stake_row needs points, height, intensity and size" % path)
			if not source.has("color") and not source.has("color_temperature"): errors.append("%s: stake_row needs color or color_temperature" % path)
			var points: Variant = normalized.get("points")
			if points is Array:
				for point: Variant in points:
					if not (point is Array) or point.size() != 2 or not _finite_numbers(point): errors.append("%s.points: expected finite [north, east] pairs" % path)
		else:
			errors.append("%s.type: expected spot or stake_row" % path)
		if type == "spot":
			if role not in ["runway_flood", "club_flood", "windsock_flood"]: errors.append("%s.role: unknown spot consumer role '%s'" % [path, role])
			var install: Dictionary = {}
			for candidate: Dictionary in installations:
				if candidate.id == installation_id: install = candidate; break
			if not install.is_empty():
				if install.type not in ["mast", "low_light_mount"]:
					errors.append("%s.installation_id: spot cannot use '%s' installation" % [path, install.type])
				elif normalized.get("north") is float and normalized.get("east") is float and normalized.get("height") is float:
					var horizontal_gap := Vector2(float(normalized.north) - float(install.get("north", NAN)), float(normalized.east) - float(install.get("east", NAN))).length()
					var vertical_gap := float(install.get("height", NAN)) - float(normalized.height)
					if not is_finite(horizontal_gap) or horizontal_gap > 1.2 or not is_finite(vertical_gap) or vertical_gap < -0.01 or vertical_gap > 1.5:
						errors.append("%s: emitter position must lie near the top of installation '%s'" % [path, installation_id])
				if role == "runway_flood" and install.type != "mast": errors.append("%s.role: runway_flood requires a mast" % path)
				if role == "windsock_flood" and install.type != "low_light_mount": errors.append("%s.role: windsock_flood requires a low_light_mount" % path)
		fixtures.append(normalized)
	if spot_count > MAX_SPOTS:
		errors.append("lights.emitters: %d spots exceed Compatibility limit of %d" % [spot_count, MAX_SPOTS])
	var raw_fixtures: Variant = root.get("fixtures", [])
	if not (raw_fixtures is Array): errors.append("lights.fixtures: expected an array"); raw_fixtures = []
	for index: int in (raw_fixtures as Array).size():
		var raw: Variant = raw_fixtures[index]
		var path := "lights.fixtures[%d]" % index
		if not (raw is Dictionary): errors.append("%s: not an object" % path); continue
		var row: Dictionary = raw
		var allowed_row_keys := ["id", "type", "installation_id", "role", "points", "height", "intensity", "size", "color_temperature", "color"]
		for key: Variant in row.keys():
			if not allowed_row_keys.has(str(key)): errors.append("%s.%s: unknown key" % [path, str(key)])
		if str(row.get("type", "")) != "stake_row": errors.append("%s.type: only stake_row fixtures are supported" % path); continue
		var row_id := str(row.get("id", ""))
		var install_id := str(row.get("installation_id", ""))
		var role := str(row.get("role", ""))
		if row_id.is_empty() or row_id.strip_edges() != row_id or ids.has(row_id): errors.append("%s.id: missing, padded or duplicate" % path)
		ids[row_id] = true
		if not installation_ids.has(install_id): errors.append("%s.installation_id: unknown installation '%s'" % [path, install_id])
		if role not in ["runway_edge", "runway_threshold", "pilot_station"]: errors.append("%s.role: unknown stake consumer role '%s'" % [path, role])
		var normalized: Dictionary = {"id": row_id, "type": "stake_row", "installation_id": install_id, "role": role}
		for key: String in ["points", "height", "intensity", "size", "color_temperature", "color"]:
			if row.has(key):
				var unit := "m" if key in ["points", "height", "size"] else ("cd" if key == "intensity" else ("K" if key == "color_temperature" else "srgb"))
				normalized[key] = _quantity(errors, "%s.%s" % [path, key], row[key], unit)
		if not normalized.has("points") or not normalized.has("height") or not normalized.has("intensity") or not normalized.has("size"):
			errors.append("%s: requires points, height, intensity and size" % path)
		if not normalized.has("color") and not normalized.has("color_temperature"): errors.append("%s: requires color or color_temperature" % path)
		var points: Variant = normalized.get("points")
		if points is Array and points.size() > 0:
			for point: Variant in points:
				if not (point is Array) or point.size() != 2 or not _finite_numbers(point): errors.append("%s.points: expected finite [north, east] pairs" % path)
		else:
			errors.append("%s.points: expected a non-empty array" % path)
		for key: String in ["height", "intensity", "size", "color_temperature"]:
			if normalized.get(key) is float and (not is_finite(normalized[key]) or float(normalized[key]) <= 0.0):
				errors.append("%s.%s: must be finite and positive" % [path, key])
		fixtures.append(normalized)
	return {ok = errors.is_empty(), errors = errors,
		lights = {version = 2, conversion = conversion, installations = installations, fixtures = fixtures}}


static func _finite_numbers(values: Array) -> bool:
	for value: Variant in values:
		if not (value is float or value is int) or not is_finite(float(value)):
			return false
	return true


## Unwraps {value, unit, kind, source}; records an error and returns null when malformed.
static func _quantity(errors: PackedStringArray, path: String, q: Variant, unit: String) -> Variant:
	if not (q is Dictionary):
		errors.append("%s: expected {value, unit, kind, source}" % path)
		return null
	for key: String in QUANTITY_KEYS:
		if not q.has(key):
			errors.append("%s.%s: required" % [path, key])
			return null
	for key: Variant in q.keys():
		if not QUANTITY_KEYS.has(str(key)):
			errors.append("%s.%s: unknown key" % [path, str(key)])
	if str(q.unit) != unit:
		errors.append("%s.unit: expected '%s'" % [path, unit])
	if not KINDS.has(str(q.kind)):
		errors.append("%s.kind: unknown '%s'" % [path, q.kind])
	if str(q.source).strip_edges().is_empty():
		errors.append("%s.source: required" % path)
	var v: Variant = q.value
	if unit == "srgb":
		if not (v is String) or not Color.html_is_valid(str(v)):
			errors.append("%s.value: expected a valid sRGB colour" % path)
		return v
	if unit == "m" and v is Array:
		return v # points are checked by their fixture validator.
	if not (v is int or v is float):
		errors.append("%s.value: expected a finite number" % path)
		return null
	if not is_finite(float(v)):
		errors.append("%s.value: not finite" % path)
		return null
	return float(v)


## Approximate light colour of a colour temperature (Tanner Helland's blackbody fit), normalised to a 1.0 peak.
static func kelvin_color(kelvin: float) -> Color:
	var t := kelvin / 100.0
	var r := 1.0 if t <= 66.0 else clampf(1.292936 * pow(t - 60.0, -0.1332047592), 0.0, 1.0)
	var g := clampf(0.3900816 * log(t) - 0.6318414, 0.0, 1.0) if t <= 66.0 else clampf(1.1298909 * pow(t - 60.0, -0.0755148492), 0.0, 1.0)
	var b := 1.0 if t >= 66.0 else (0.0 if t <= 19.0 else clampf(0.5432068 * log(t - 10.0) - 1.1962541, 0.0, 1.0))
	return Color(r, g, b)


static func _color(fx: Dictionary) -> Color:
	return Color(fx.color) if fx.has("color") else kelvin_color(fx.color_temperature)


## Scene radiance of a lamp's face: luminance I / (π r²) cd/m², with a white surface under `conversion` lux as
## ~1 scene unit (luminance conversion / π) → radiance = I / (r² · conversion).
static func lamp_radiance(intensity_cd: float, size_m: float, conversion: float) -> float:
	var r := size_m / 2.0
	return intensity_cd / (r * r * conversion)


static func _sprite_material(color: Color, radiance: float, size_m: float, min_px: float, display_cap: float) -> ShaderMaterial:
	Exposure.register() # before the shader compiles
	var m := ShaderMaterial.new()
	m.shader = SPRITE_SHADER
	m.set_shader_parameter("light_color", color)
	m.set_shader_parameter("radiance", radiance)
	m.set_shader_parameter("size_m", size_m)
	m.set_shader_parameter("min_px", min_px)
	m.set_shader_parameter("display_cap", display_cap)
	return m


static func _render(north: float, east: float, up: float) -> Vector3:
	return Frames.ned_to_render([north, east, -up])


## Pinned GLES3 point-light radial window: max(1 - (d/R)^4, 0)^2 / d^decay.
static func radial_transport(distance_m: float, range_m: float, decay: float) -> float:
	if not is_finite(distance_m) or not is_finite(range_m) or not is_finite(decay) or distance_m < 0.0 or range_m <= 0.0 or decay < 0.0:
		return 0.0
	var normalized_distance := distance_m / range_m
	var window := pow(maxf(1.0 - pow(normalized_distance, 4.0), 0.0), 2.0)
	return window / pow(maxf(distance_m, 0.0001), decay)


## Pinned GLES3 spot-cone edge law; angle_attenuation is the authored spot angle attenuation.
static func angular_transport(cos_angle: float, half_angle_deg: float, angle_attenuation: float) -> float:
	if not is_finite(cos_angle) or not is_finite(half_angle_deg) or not is_finite(angle_attenuation) or angle_attenuation <= 0.0:
		return 0.0
	var edge_cos := cos(deg_to_rad(half_angle_deg))
	var scos := maxf(cos_angle, edge_cos)
	var rim := maxf(0.0001, (1.0 - scos) / maxf(1.0 - edge_cos, 0.000001))
	return 1.0 - pow(rim, 1.0 / angle_attenuation)


## Illuminance (scene units) at a render-space point, using the pinned engine's radial/cone transport.
static func illuminance_point(lights: Dictionary, point: Vector3) -> float:
	return _illuminance(lights, point, Vector3.ZERO)


## Lambertian plane irradiance in scene units at a render-space point (used for analytic runway coverage).
static func illuminance_surface(lights: Dictionary, point: Vector3, normal: Vector3) -> float:
	return _illuminance(lights, point, normal.normalized())


static func _illuminance(lights: Dictionary, point: Vector3, normal: Vector3) -> float:
	var total := 0.0
	for fx: Dictionary in lights.get("fixtures", []):
		if fx.type != "flood":
			continue
		var pos := _render(fx.north, fx.east, fx.height)
		var aim := (_render(fx.aim_north, fx.aim_east, float(fx.get("aim_height", 0.0))) - pos).normalized()
		var to_point := point - pos
		var d := to_point.length()
		if d <= 0.0:
			continue
		var angle := angular_transport(aim.dot(to_point / d), float(fx.beam_half_angle), float(fx.get("angular_attenuation", 1.0)))
		var radial := radial_transport(d, float(fx.range), float(fx.get("distance_attenuation", 1.0)))
		var incidence := 1.0 if normal.is_zero_approx() else maxf(normal.dot(-to_point / d), 0.0)
		total += float(fx.intensity) / float(lights.conversion) * radial * angle * incidence
	return total


## Builds every fixture. Returns a Node3D named "FieldLights" (meta "spots": the SpotLight3D count).
static func build(lights: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "FieldLights"
	var conversion: float = lights.conversion
	var spots := 0
	var pole_material := StandardMaterial3D.new()
	pole_material.albedo_color = Color("#5b5f63")
	pole_material.roughness = 0.8
	var version := int(lights.get("version", 1))
	if version >= 2:
		for installation: Dictionary in lights.get("installations", []):
			if installation.type not in ["mast", "low_light_mount"]:
				continue
			_add_pole(root, "field_mast_pole" if installation.type == "mast" else str(installation.id) + "_pole",
				float(installation.get("north", 0.0)), float(installation.get("east", 0.0)),
				float(installation.get("height", 0.0)), float(installation.get("collision_radius", POLE_RADIUS_M)), pole_material)
	for fx: Dictionary in lights.fixtures:
		if fx.type == "flood":
			var pos := _render(fx.north, fx.east, fx.height)
			var target := _render(fx.aim_north, fx.aim_east, float(fx.get("aim_height", 0.0)))
			var light := SpotLight3D.new()
			light.name = fx.id
			var forward := (target - pos).normalized()
			light.transform = Transform3D(Basis.looking_at(forward, Vector3.UP if absf(forward.y) < 0.99 else Vector3.FORWARD), pos)
			light.light_energy = float(fx.intensity) / conversion
			light.light_color = kelvin_color(fx.color_temperature)
			light.spot_angle = fx.beam_half_angle
			light.spot_range = fx.range
			light.spot_attenuation = float(fx.get("distance_attenuation", 1.0))
			light.spot_angle_attenuation = float(fx.get("angular_attenuation", 1.0))
			light.shadow_enabled = false
			light.set_meta("role", str(fx.get("role", "")))
			light.set_meta("installation_id", str(fx.get("installation_id", "")))
			root.add_child(light)
			spots += 1
			if version < 2:
				_add_pole(root, fx.id + "_pole", float(fx.north), float(fx.east), float(fx.height), POLE_RADIUS_M, pole_material)
			var head := MeshInstance3D.new()
			head.name = fx.id + "_lamp"
			var quad := QuadMesh.new()
			quad.size = Vector2.ONE
			quad.material = _sprite_material(kelvin_color(fx.color_temperature),
				lamp_radiance(fx.intensity, FLOOD_HEAD_SIZE_M, conversion), FLOOD_HEAD_SIZE_M, 3.0, 4.0)
			head.mesh = quad
			head.transform = Transform3D(light.transform.basis, pos + forward * 0.04)
			head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			head.extra_cull_margin = 16.0
			root.add_child(head)
		else:
			var quad := QuadMesh.new()
			quad.size = Vector2.ONE
			quad.material = _sprite_material(_color(fx), lamp_radiance(fx.intensity, fx.size, conversion), fx.size, 2.5, 2.0)
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = quad
			mm.instance_count = (fx.points as Array).size()
			for i in mm.instance_count:
				var p: Array = fx.points[i]
				mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, _render(float(p[0]), float(p[1]), fx.height)))
			var node := MultiMeshInstance3D.new()
			node.name = fx.id
			node.multimesh = mm
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.extra_cull_margin = 16.0
			root.add_child(node)
	root.set_meta("spots", spots)
	root.set_meta("installation_count", lights.get("installations", []).size())
	return root


static func _add_pole(root: Node3D, node_name: String, north: float, east: float, height: float,
		radius: float, material: Material) -> void:
	var pole := MeshInstance3D.new()
	pole.name = node_name
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius * 0.7
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = 8
	cylinder.material = material
	pole.mesh = cylinder
	pole.position = _render(north, east, height * 0.5)
	root.add_child(pole)
