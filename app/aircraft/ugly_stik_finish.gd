# Visual recipes only: immutable shared resources; geometry/flight data stay separate.
extends RefCounted

const Geometry := preload("res://aircraft/ugly_stik_geometry.gd")
const Appearance := preload("res://aircraft/ugly_stik_appearance.gd")
const RED := Appearance.RED
const WHITE := Appearance.WHITE
const SVG_PATH := "res://aircraft/livery.svg"
static var _materials: Dictionary = {}
static var _atlas: ImageTexture
static var _normal_map: ImageTexture
static var _grain: ImageTexture
const GRAIN_SIZE := Vector2i(1024, 128)
const GRAIN_PATH := "res://aircraft/ugly_stik_grain.res"
const NORMAL_MAP_SIZE := 1024
# Slopes are stored ×GAIN for 8-bit precision; the material's normal_scale (1/GAIN) restores them (small-angle mix).
const NORMAL_MAP_GAIN := 8.0

static func material(color: Color, profile: String = "skin") -> StandardMaterial3D:
	var key := profile + ":" + color.to_html()
	if _materials.has(key): return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.48
	mat.metallic_specular = 0.5
	match profile:
		"skin":
			# US-V09a: glossy heat-shrink film (dielectric F0 ≈ 0.04), not the earlier matte paint. Roughness is an
			# artistic estimate chosen from matched captures; no measured BRDF.
			mat.roughness = 0.2
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
		"varnished_wood":
			# US-V09d: a sealed, varnished wooden propeller: dielectric gloss over the grain (estimate).
			mat.roughness = 0.26
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

# US-V09b: open bays between the plan-traced ribs and spars (Appearance film_structure) let the film sag inward.
# Returns a tangent-space normal map in the atlas UV layout: wing rows only, everything else flat. Built once.
static func normal_map() -> ImageTexture:
	if _normal_map != null: return _normal_map
	var f: Dictionary = Appearance.DATA.film_structure
	var span := float(Geometry.DATA.wing.span)
	var chord := float(Geometry.DATA.wing.chord)
	var ribs: Array = []
	var false_ribs: Array = []
	for i in f.rib_centres_m.size():
		var c := float(f.rib_centres_m[i])
		var half := float(f.rib_widths_m[i]) / 2.0
		ribs.append([maxf(c - half, 0.0), c + half])
		if i > 0:
			var mid := (c + float(f.rib_centres_m[i - 1])) / 2.0
			false_ribs.append([mid - float(f.false_rib_width_m) / 2.0, mid + float(f.false_rib_width_m) / 2.0])
	var le_supports: Array = ribs + false_ribs
	le_supports.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var main_columns := _bay_profile(ribs, NORMAL_MAP_SIZE, func(col: int) -> float: return ((col + 0.5) / NORMAL_MAP_SIZE - 0.5) * span)
	var le_columns := _bay_profile(le_supports, NORMAL_MAP_SIZE, func(col: int) -> float: return ((col + 0.5) / NORMAL_MAP_SIZE - 0.5) * span)
	# Atlas rows: v = (16 + 224 z / chord) / 1024 (see uv()); chord bays between leading edge, spars and trailing sheet.
	var row_scale := NORMAL_MAP_SIZE / 1024.0
	var chord_bays := [[float(f.leading_edge_fraction), float(f.secondary_spar_fraction[0])],
		[float(f.secondary_spar_fraction[1]), float(f.main_spar_fraction[0])],
		[float(f.main_spar_fraction[1]), float(f.trailing_sheet_front_fraction)]]
	var data := PackedByteArray()
	data.resize(NORMAL_MAP_SIZE * NORMAL_MAP_SIZE * 3)
	for i in range(0, data.size(), 3):
		data[i] = 128
		data[i + 1] = 128
		data[i + 2] = 255
	var depth := float(f.sag.depth_m)
	var reference := float(f.sag.reference_bay_m)
	for row in NORMAL_MAP_SIZE:
		var fraction := ((row + 0.5) / row_scale - 16.0) / 224.0
		var bay := -1
		for k in chord_bays.size():
			if fraction > chord_bays[k][0] and fraction < chord_bays[k][1]: bay = k
		if bay < 0: continue
		var height := (float(chord_bays[bay][1]) - float(chord_bays[bay][0])) * chord
		var b := (fraction - float(chord_bays[bay][0])) / (float(chord_bays[bay][1]) - float(chord_bays[bay][0]))
		var bv := sin(PI * b)
		var bdz := PI / height * cos(PI * b)
		var columns: Array = le_columns if bay == 0 else main_columns
		for col in NORMAL_MAP_SIZE:
			var width: float = columns[col].x
			if width <= 0.0: continue
			var short := minf(width, height) / reference
			var d := depth * short * short
			# Height h = -d·A·B (inward). Tangent space: x along +u (+span x), green toward image-up (−z, OpenGL).
			var tilt := Vector2(d * columns[col].z * bv, -d * columns[col].y * bdz) * NORMAL_MAP_GAIN
			var n := Vector3(tilt.x, tilt.y, sqrt(maxf(0.0, 1.0 - tilt.length_squared())))
			var i := (row * NORMAL_MAP_SIZE + col) * 3
			data[i] = clampi(roundi((n.x * 0.5 + 0.5) * 255.0), 0, 255)
			data[i + 1] = clampi(roundi((n.y * 0.5 + 0.5) * 255.0), 0, 255)
			data[i + 2] = clampi(roundi((n.z * 0.5 + 0.5) * 255.0), 0, 255)
	var image := Image.create_from_data(NORMAL_MAP_SIZE, NORMAL_MAP_SIZE, false, Image.FORMAT_RGB8, data)
	image.generate_mipmaps()
	_normal_map = ImageTexture.create_from_image(image)
	return _normal_map


# Per column: Vector3(bay width m, A = sin(pi a), dA/dx). Width 0 = supported (on a rib or outboard of the last rib).
static func _bay_profile(supports: Array, size: int, column_x: Callable) -> Array:
	var result: Array = []
	for col in size:
		var x: float = column_x.call(col)
		var s := absf(x)
		var value := Vector3.ZERO
		for k in supports.size() - 1:
			var lo: float = supports[k][1]
			var hi: float = supports[k + 1][0]
			if s > lo and s < hi:
				var a := (s - lo) / (hi - lo)
				value = Vector3(hi - lo, sin(PI * a), signf(x) * PI / (hi - lo) * cos(PI * a))
		result.append(value)
	return result

# US-V09d: straight-grained propeller blank. U runs tip to tip across both blades (one piece of wood), V across the
# chord. Grain lines follow the blank with slow waviness; values stay in 0.79..1.0 so the blade keeps the albedo the
# propeller blur measures (its disc copies albedo_color). Deterministic hash noise; built once.
static func grain() -> ImageTexture:
	if _grain != null: return _grain
	# Literal load keeps the generated resource in the model manifest's dependency closure.
	var image: Image = load("res://aircraft/ugly_stik_grain.res") as Image if ResourceLoader.exists(GRAIN_PATH) else null
	if image == null or image.get_size() != GRAIN_SIZE or image.get_format() != Image.FORMAT_RGB8 or not image.has_mipmaps():
		image = generate_grain_image()
	_grain = ImageTexture.create_from_image(image)
	return _grain


## DT-11a: authoritative recipe for assets/aircraft/ugly-stik-60/bake_grain.gd.
## Keep the baked image (including mip levels) byte-identical to this procedural fallback.
static func generate_grain_image() -> Image:
	var data := PackedByteArray()
	data.resize(GRAIN_SIZE.x * GRAIN_SIZE.y * 3)
	for y in GRAIN_SIZE.y:
		var v := (y + 0.5) / GRAIN_SIZE.y
		for x in GRAIN_SIZE.x:
			var u := (x + 0.5) / GRAIN_SIZE.x
			# Irregular latewood lines (varying spacing and strength), broad heartwood bands and fine pore streaks.
			var phase := v * 11.0 + 0.8 * _noise(u * 2.5, 1.7) + 0.35 * _noise(v * 6.0, u * 4.0 + 5.0)
			var strength := 0.6 + 0.4 * _noise(floorf(phase) * 0.7, 3.0)
			var line := pow(absf(sin(PI * phase)), 10.0) * strength
			var band := 0.5 + 0.5 * _noise(v * 3.0 + 2.0, u * 1.2)
			var pores := 0.5 + 0.5 * _noise(u * 60.0, v * 25.0 + 11.0)
			var value := clampf(1.0 - 0.10 * line - 0.07 * band - 0.04 * pores, 0.0, 1.0)
			var i := (y * GRAIN_SIZE.x + x) * 3
			data[i] = roundi(255.0 * value)
			data[i + 1] = roundi(255.0 * (value * 0.985))
			data[i + 2] = roundi(255.0 * (value * 0.96))
	var image := Image.create_from_data(GRAIN_SIZE.x, GRAIN_SIZE.y, false, Image.FORMAT_RGB8, data)
	image.generate_mipmaps()
	return image


# Smooth value noise in [-1, 1] from an integer hash (no RandomNumberGenerator state, identical on every run).
static func _noise(x: float, y: float) -> float:
	var ix := floori(x)
	var iy := floori(y)
	var fx := x - ix
	var fy := y - iy
	var sx := fx * fx * (3.0 - 2.0 * fx)
	var sy := fy * fy * (3.0 - 2.0 * fy)
	var a := lerpf(_hash(ix, iy), _hash(ix + 1, iy), sx)
	var b := lerpf(_hash(ix, iy + 1), _hash(ix + 1, iy + 1), sx)
	return lerpf(a, b, sy) * 2.0 - 1.0


static func _hash(x: int, y: int) -> float:
	var h := (x * 374761393 + y * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h ^ (h >> 16)) / float(0x7fffffff)


static func propeller_wood(color: Color) -> StandardMaterial3D:
	var key := "propeller-varnished-wood:" + color.to_html()
	if _materials.has(key): return _materials[key]
	var mat := material(color, "varnished_wood").duplicate() as StandardMaterial3D
	mat.albedo_texture = grain()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.resource_name = key
	_materials[key] = mat
	return mat


static func covering() -> StandardMaterial3D:
	var key := "classic-covering-v4"
	if _materials.has(key): return _materials[key]
	var mat := material(Color.WHITE, "skin").duplicate() as StandardMaterial3D
	mat.albedo_texture = atlas()
	mat.normal_enabled = true
	mat.normal_texture = normal_map()
	mat.normal_scale = 1.0 / NORMAL_MAP_GAIN
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.texture_repeat = false
	mat.resource_name = key
	_materials[key] = mat
	return mat

# Hinge-gap faces: same atlas colour, darkened and without specular reflection (a narrow slot sees little sky).
static func hinge_gap() -> StandardMaterial3D:
	var key := "classic-covering-gap-v1"
	if _materials.has(key): return _materials[key]
	var mat := covering().duplicate() as StandardMaterial3D
	# Below the crash director's chip luminance threshold (CR-03b), so gaps never become a debris colour.
	mat.albedo_color = Color(0.1, 0.1, 0.1)
	mat.roughness = 1.0
	mat.metallic_specular = 0.0
	mat.normal_enabled = false
	mat.normal_texture = null
	mat.resource_name = key
	_materials[key] = mat
	return mat


# US-V09e: fuselage sides and belly. z along the fuselage, s = skin arc length from the belly centre line (+X positive).
static func fuselage_uv(z: float, arc_s: float) -> Vector2:
	var f: Dictionary = Appearance.DATA.fuselage_unwrap
	var x := lerpf(float(f.x_px[0]), float(f.x_px[1]), (z - float(f.z_m[0])) / (float(f.z_m[1]) - float(f.z_m[0])))
	var y := lerpf(float(f.y_px[0]), float(f.y_px[1]), 0.5 + arc_s / float(f.perimeter_m))
	return Vector2(x, y) / 1024.0


static func uv(point: Vector3, region: String) -> Vector2:
	match region:
		"wing":
			return Vector2(clampf(point.x / float(Geometry.DATA.wing.span) + 0.5, 0.0, 1.0), (16.0 + 224.0 * point.z / float(Geometry.DATA.wing.chord)) / 1024.0)
		"fin":
			return Vector2((32.0 + 448.0 * (point.z + 0.20) / 0.31) / 1024.0, (976.0 - 432.0 * point.y / 0.215) / 1024.0)
		"dorsal":
			return Vector2((544.0 + 464.0 * clampf((point.x + 0.055) / 0.11, 0, 1)) / 1024.0, (544.0 + 464.0 * clampf((point.z - 0.215) / 0.12, 0, 1)) / 1024.0)
		"white": return Vector2(0.04, 0.54)
		"hatch":
			# US-V09g: flat top of the 1/4 in sheet hatch between the fuselage front and station 1.
			var h: Dictionary = Appearance.DATA.hatch
			return Vector2(lerpf(float(h.x_px[0]), float(h.x_px[1]), inverse_lerp(-float(h.half_width_m), float(h.half_width_m), point.x)),
				lerpf(float(h.y_px[0]), float(h.y_px[1]), inverse_lerp(float(h.z_m[0]), float(h.z_m[1]), point.z))) / 1024.0
		"stab_under":
			# US-V09f: prism-local stabiliser/elevator underside (x span, z from the elevator hinge).
			var f: Dictionary = Appearance.DATA.stab_unwrap
			return Vector2(lerpf(float(f.x_px[0]), float(f.x_px[1]), inverse_lerp(float(f.x_m[0]), float(f.x_m[1]), point.x)),
				lerpf(float(f.y_px[0]), float(f.y_px[1]), inverse_lerp(float(f.z_m[0]), float(f.z_m[1]), point.z))) / 1024.0
	return Vector2(0.5, 0.01)
