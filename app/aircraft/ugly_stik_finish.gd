# Visual recipes only: immutable shared resources; geometry/flight data stay separate.
extends RefCounted

const Geometry := preload("res://aircraft/ugly_stik_geometry.gd")
const Appearance := preload("res://aircraft/ugly_stik_appearance.gd")
const RED := Appearance.RED
const WHITE := Appearance.WHITE
const SVG_PATH := "res://aircraft/livery.svg"
static var _materials: Dictionary = {}
static var _atlas: ImageTexture

static func material(color: Color, profile: String = "skin") -> StandardMaterial3D:
	var key := profile + ":" + color.to_html()
	if _materials.has(key): return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.48
	mat.metallic_specular = 0.16 if profile == "skin" else 0.5
	match profile:
		"aluminum":
			mat.metallic = 0.72
			mat.roughness = 0.48
		"cast_aluminum":
			mat.metallic = 0.70
			mat.roughness = 0.46
		"machined_aluminum":
			mat.metallic = 0.85
			mat.roughness = 0.28
		"anodized_gold":
			mat.metallic = 0.82
			mat.roughness = 0.26
		"steel":
			mat.metallic = 0.82
			mat.roughness = 0.28
		"rubber": mat.roughness = 0.95
		"plastic": mat.roughness = 0.6
		"wood": mat.roughness = 0.64
	mat.resource_name = key
	_materials[key] = mat
	return mat

static func atlas() -> ImageTexture:
	if _atlas != null: return _atlas
	# The compiler embeds the same SVG as livery.svg, just like the geometry data.
	# Godot rasterizes it once; no editor cache or original source file is needed in exports.
	var image := Image.new()
	var source: String = Appearance.SVG_SOURCE
	if source.is_empty():
		push_error("Missing Ugly Stik livery SVG")
		return null
	var error := image.load_svg_from_string(source)
	if error != OK:
		push_error("Invalid Ugly Stik SVG")
		return null
	image.generate_mipmaps()
	_atlas = ImageTexture.create_from_image(image)
	return _atlas

static func covering() -> StandardMaterial3D:
	var key := "classic-covering-v4"
	if _materials.has(key): return _materials[key]
	var mat := material(Color.WHITE, "skin").duplicate() as StandardMaterial3D
	mat.albedo_texture = atlas()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.texture_repeat = false
	mat.resource_name = key
	_materials[key] = mat
	return mat

static func uv(point: Vector3, region: String) -> Vector2:
	match region:
		"wing":
			return Vector2(clampf(point.x / float(Geometry.DATA.wing.span) + 0.5, 0.0, 1.0), (16.0 + 224.0 * point.z / float(Geometry.DATA.wing.chord)) / 1024.0)
		"fin":
			return Vector2((32.0 + 448.0 * (point.z + 0.20) / 0.31) / 1024.0, (976.0 - 432.0 * point.y / 0.215) / 1024.0)
		"dorsal":
			return Vector2((544.0 + 464.0 * clampf((point.x + 0.055) / 0.11, 0, 1)) / 1024.0, (544.0 + 464.0 * clampf((point.z - 0.215) / 0.12, 0, 1)) / 1024.0)
		"white": return Vector2(0.04, 0.54)
	return Vector2(0.5, 0.01)
