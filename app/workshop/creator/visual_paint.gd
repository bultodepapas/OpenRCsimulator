extends RefCounted
## Paint of a player-imported model (AC-15 foundation): the model's own materials or one solid colour.
##
## Appearance is presentation only and has a fixed shape:
##   {"mode": "original"}                       the GLB's own materials, or the neutral material of an STL
##   {"mode": "solid", "color": "#rrggbb"}      lowercase hex, sRGB
## `apply` only ever writes materials created here onto meshes built for one visual, so nothing is
## shared between two builds or written back into the admitted source.

const R := preload("res://workshop/creator/result.gd")

const STEP := "paint_skins"
const MODE_ORIGINAL := "original"
const MODE_SOLID := "solid"
const SOLID_ROUGHNESS := 0.62
const _UNREADABLE := "The paint settings cannot be read. Choose the paint again."


static func original() -> Dictionary:
	return {"mode": MODE_ORIGINAL}


## Checks an appearance. `value` is a normalized copy. An empty dictionary means "original".
static func validate(appearance: Dictionary) -> Dictionary:
	if appearance.is_empty():
		return R.ok(original())
	var mode: Variant = appearance.get("mode")
	if typeof(mode) != TYPE_STRING and typeof(mode) != TYPE_STRING_NAME:
		return R.fail(R.FIELD_INVALID, _UNREADABLE, "appearance/mode", STEP)
	var allowed: Array = ["mode", "color"] if str(mode) == MODE_SOLID else ["mode"]
	for key: Variant in appearance:
		if not (key is String or key is StringName) or str(key) not in allowed:
			return R.fail(R.FIELD_INVALID, _UNREADABLE, "appearance/" + str(key), STEP)
	if str(mode) == MODE_ORIGINAL:
		return R.ok(original())
	if str(mode) != MODE_SOLID:
		return R.fail(R.FIELD_INVALID, "Choose the original look of the model or one solid colour.", "appearance/mode", STEP)
	var color: Variant = appearance.get("color")
	if typeof(color) != TYPE_STRING or not _is_color(color):
		return R.fail(R.FIELD_INVALID, "\"%s\" is not a colour. Choose the paint colour again.", "appearance/color", STEP,
			[str(color) if typeof(color) == TYPE_STRING else ""])
	return R.ok({"mode": MODE_SOLID, "color": str(color)})


## Paints every mesh surface under `content` (the node itself included) for a validated appearance.
## Solid: one opaque, untextured material of the colour per face-culling mode found, so a surface
## that was double-sided stays double-sided and a thin panel does not vanish from one side.
## Transparency is not kept: paint is opaque. Original: nothing is touched.
static func apply(content: Node3D, appearance: Dictionary) -> void:
	if str(appearance.get("mode", MODE_ORIGINAL)) != MODE_SOLID:
		return
	var color := Color.html(str(appearance.color))
	var by_culling := {}
	var instances: Array[Node] = content.find_children("*", "MeshInstance3D", true, false)
	if content is MeshInstance3D:
		instances.push_front(content)
	for item: Node in instances:
		var instance := item as MeshInstance3D
		if instance.mesh == null:
			continue
		for surface: int in instance.mesh.get_surface_count():
			var current := instance.get_active_material(surface) as BaseMaterial3D
			var culling: int = current.cull_mode if current != null else BaseMaterial3D.CULL_BACK
			if not by_culling.has(culling):
				by_culling[culling] = _solid(color, culling)
			instance.mesh.surface_set_material(surface, by_culling[culling])
			instance.set_surface_override_material(surface, null)
		instance.material_override = null


static func _solid(color: Color, culling: int) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = "creator_solid"
	material.albedo_color = Color(color.r, color.g, color.b, 1.0)
	material.roughness = SOLID_ROUGHNESS
	material.cull_mode = culling as BaseMaterial3D.CullMode
	return material


## Exactly "#" and six lowercase hexadecimal digits.
static func _is_color(text: String) -> bool:
	if text.length() != 7 or text[0] != "#":
		return false
	for index: int in range(1, 7):
		if text[index] not in "0123456789abcdef":
			return false
	return true
