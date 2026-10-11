# FIELD-WORLD-PLAN FW-31…FW-34: the field's night lights from app/data/fields/lights.json (openrc-field-lights v1).
# - "flood": a pole, a glowing lamp head and one SpotLight3D without shadows. Compatibility lights at most 8 omni +
#   8 spot lights per mesh and the ground is one mesh, so floods are capped (MAX_FLOODS, with the airplane's landing
#   light the field stays well inside the limit); shadowed positional lights would add passes, so none cast shadows.
# - "stake_row": self-luminous points only (one MultiMesh of light sprites per row): edge, threshold, station lamps.
# Visual only: nothing here touches the simulation. Brightness is physical in scene units (see "conversion").
extends RefCounted

const Frames := preload("res://render/frames.gd")
const Spec := preload("res://spec.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const SPRITE_SHADER := preload("res://render/world/light_sprite.gdshader")

const DEFAULT_PATH := "res://data/fields/lights.json"
const FORMAT := "openrc-field-lights v1"
const MAX_FLOODS := 4
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
	var errors: PackedStringArray = []
	if not (root is Dictionary):
		return {ok = false, errors = PackedStringArray(["lights: not a JSON object"]), lights = {}}
	if root.get("format", "") != FORMAT:
		errors.append("lights.format: expected '%s'" % FORMAT)
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
		var out := {id = id, type = type}
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
	return {ok = errors.is_empty(), errors = errors, lights = {conversion = conversion, fixtures = fixtures}}


## Unwraps {value, unit, kind, source}; records an error and returns null when malformed.
static func _quantity(errors: PackedStringArray, path: String, q: Variant, unit: String) -> Variant:
	if not (q is Dictionary):
		errors.append("%s: expected {value, unit, kind, source}" % path)
		return null
	for key: String in QUANTITY_KEYS:
		if not q.has(key):
			errors.append("%s.%s: required" % [path, key])
			return null
	if str(q.unit) != unit:
		errors.append("%s.unit: expected '%s'" % [path, unit])
	if not KINDS.has(str(q.kind)):
		errors.append("%s.kind: unknown '%s'" % [path, q.kind])
	if str(q.source).strip_edges().is_empty():
		errors.append("%s.source: required" % path)
	var v: Variant = q.value
	if v is int:
		return float(v)
	if v is float:
		if not is_finite(v):
			errors.append("%s.value: not finite" % path)
		return v
	return v


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
	var m := ShaderMaterial.new()
	m.shader = SPRITE_SHADER
	m.set_shader_parameter("light_color", color)
	m.set_shader_parameter("radiance", radiance)
	m.set_shader_parameter("size_m", size_m)
	m.set_shader_parameter("min_px", min_px)
	m.set_shader_parameter("display_cap", display_cap)
	m.set_shader_parameter("rad_per_px", deg_to_rad(Spec.CAMERA.fov_deg) / 720.0)
	m.set_shader_parameter("exposure", Atmosphere.state.get("exposure", Spec.ATMOSPHERE.exposure))
	return m


static func _render(north: float, east: float, up: float) -> Vector3:
	return Frames.ned_to_render([north, east, -up])


## Horizontal illuminance (scene units) the floods put on a ground point (NED north, east): inverse square, the cosine
## of incidence, the cone and Godot's range window. Used to adapt the exposure to a lit field.
static func illuminance_at(lights: Dictionary, north: float, east: float) -> float:
	var total := 0.0
	var point := _render(north, east, 0.0)
	for fx: Dictionary in lights.fixtures:
		if fx.type != "flood":
			continue
		var pos := _render(fx.north, fx.east, fx.height)
		var aim := (_render(fx.aim_north, fx.aim_east, float(fx.get("aim_height", 0.0))) - pos).normalized()
		var to_point := point - pos
		var d := to_point.length()
		if d <= 0.0 or d >= float(fx.range):
			continue
		if rad_to_deg(aim.angle_to(to_point)) > float(fx.beam_half_angle):
			continue
		var window := pow(maxf(1.0 - pow(d / float(fx.range), 4.0), 0.0), 2.0)
		total += float(fx.intensity) / float(lights.conversion) * maxf(-to_point.normalized().y, 0.0) / (d * d) * window
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
			light.shadow_enabled = false
			root.add_child(light)
			spots += 1
			var pole := MeshInstance3D.new()
			pole.name = fx.id + "_pole"
			var cyl := CylinderMesh.new()
			cyl.top_radius = POLE_RADIUS_M * 0.7
			cyl.bottom_radius = POLE_RADIUS_M
			cyl.height = fx.height
			cyl.radial_segments = 8
			cyl.material = pole_material
			pole.mesh = cyl
			pole.position = _render(fx.north, fx.east, float(fx.height) / 2.0)
			root.add_child(pole)
			var head := MeshInstance3D.new()
			head.name = fx.id + "_lamp"
			var quad := QuadMesh.new()
			quad.size = Vector2.ONE
			quad.material = _sprite_material(kelvin_color(fx.color_temperature),
				lamp_radiance(fx.intensity, FLOOD_HEAD_SIZE_M, conversion), FLOOD_HEAD_SIZE_M, 3.0, 4.0)
			head.mesh = quad
			head.position = pos + forward * 0.3
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
	return root
