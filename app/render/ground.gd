# Textured grass (D7): flat colour gives no height or speed cues; a fine, irregular texture does (motion parallax
# and texture density). Deterministic value noise (seeded), so captures stay byte-identical run to run.
extends RefCounted

const Spec := preload("res://spec.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const GroundTerrain := preload("res://physics/ground_terrain.gd")
const TURF_DETAIL := preload("res://assets/landscape/turf/detail.png")

const SIZE := 256
## DT-11a: one default RGB8 tile including mips (262,143 bytes); never retain scene resources.
static var _default_grass_bytes := PackedByteArray()
## Field surface types as the ground shader's surface_kind (Phase 4).
const SURFACE_KIND: Dictionary = {"rough": 0, "mown": 1, "runway": 2}
# L9c: a bounded shader batch, not a field-format limit. Unsupported layouts keep the legacy planes.
const MAX_SURFACES: int = 32
const HORIZON_FLAT_RADIUS_M: float = 1500.0


## Seamless grass tile: a few octaves of value noise around Spec.GRASS, with mipmaps for distant ground.
static func grass_image(seed := 1253) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var octaves := []
	for cells in [8, 32, 128]: # coarse patches → fine blades
		var grid := PackedFloat32Array()
		grid.resize(cells * cells)
		for k in grid.size():
			grid[k] = rng.randf()
		octaves.append([cells, grid])
	var weights := [0.5, 0.3, 0.2]
	var img := Image.create(SIZE, SIZE, true, Image.FORMAT_RGB8)
	for j in SIZE:
		for i in SIZE:
			var n := 0.0
			for o in octaves.size():
				n += weights[o] * _value_noise(octaves[o][1], octaves[o][0], float(i) / SIZE, float(j) / SIZE)
			var shade := lerpf(1.0 - Spec.GROUND.contrast, 1.0 + Spec.GROUND.contrast, n)
			img.set_pixel(i, j, Color(Spec.GRASS.r * shade, Spec.GRASS.g * shade, Spec.GRASS.b * shade))
	img.generate_mipmaps()
	return img


## Bilinear value noise on a periodic cells × cells grid (periodic → the tile repeats without seams).
static func _value_noise(grid: PackedFloat32Array, cells: int, u: float, v: float) -> float:
	var x := u * cells
	var y := v * cells
	var x0 := int(floor(x))
	var y0 := int(floor(y))
	var fx := x - x0
	var fy := y - y0
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a := grid[posmod(y0, cells) * cells + posmod(x0, cells)]
	var b := grid[posmod(y0, cells) * cells + posmod(x0 + 1, cells)]
	var c := grid[posmod(y0 + 1, cells) * cells + posmod(x0, cells)]
	var d := grid[posmod(y0 + 1, cells) * cells + posmod(x0 + 1, cells)]
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


## The flat-colour runway strip, kept for the frozen VQ-01a atmosphere fixture (production uses surface_material).
static func runway_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Spec.RUNWAY_COLOR
	mat.metallic_specular = 0.0
	mat.roughness = 1.0
	return mat


## Landscape Phase 4: a mown or runway surface drawn by the ground shader over its rectangle (render x/z centre and
## half extents, m). A copy of the build's grass material (same texture, pilot pin and haze), so the mown turf blends
## into the rough grass inside a noisy border with no colour seam; the runway adds mowing stripes and touchdown wear.
static func surface_material(grass: ShaderMaterial, type: String, center: Vector2, half: Vector2) -> ShaderMaterial:
	var mat := grass.duplicate() as ShaderMaterial
	mat.set_shader_parameter("surface_kind", SURFACE_KIND[type])
	mat.set_shader_parameter("rect_center", center)
	mat.set_shader_parameter("rect_half", half)
	return mat


## The grass: texture in world space, matte, with the haze and the rim fade as custom fog (render/ground.gdshader).
static func grass_material(lighting: Dictionary = {}) -> ShaderMaterial:
	var material := Atmosphere.ground_material(ImageTexture.create_from_image(_default_grass_image()), lighting)
	material.set_shader_parameter("turf_detail", TURF_DETAIL)
	material.set_shader_parameter("turf_detail_strength", 1.0)
	return material


## Only the fixed default recipe is cached. Each caller owns its Image/texture/material;
## updating one world's texture cannot alter another world or poison future builds.
static func _default_grass_image() -> Image:
	if _default_grass_bytes.is_empty():
		var image := grass_image()
		_default_grass_bytes = image.get_data()
		return image
	return Image.create_from_data(SIZE, SIZE, true, Image.FORMAT_RGB8, _default_grass_bytes)


## Pack contained, flat surface rectangles into the ground pass. Return false before changing the material
## when the existing field contract needs independent planes (uncontained rectangles, hills, large batches).
static func configure_surfaces(material: ShaderMaterial, surfaces: Array) -> bool:
	var ordered: Array[Dictionary] = []
	for kind: String in ["mown", "runway"]: # Priority is independent of JSON order.
		for surface: Dictionary in surfaces:
			if surface.type == kind:
				ordered.append(surface)
	if ordered.size() > MAX_SURFACES:
		return false
	for surface: Dictionary in ordered:
		var covered: bool = false
		var rect: Rect2 = surface_rect(surface)
		for rough: Dictionary in surfaces:
			if rough.type != "rough":
				continue
			var ground_rect: Rect2 = surface_rect(rough)
			if not ground_rect.encloses(rect):
				continue
			# L7 replaces a 40 km rough plane with relief outside its flat central disk.
			if ground_rect.size == Vector2(40000.0, 40000.0):
				var offset: Vector2 = (rect.get_center() - ground_rect.get_center()).abs() + rect.size / 2.0
				if offset.length() > HORIZON_FLAT_RADIUS_M:
					continue
			covered = true
			break
		if not covered:
			return false
	# Do not mutate either uniform set until every layout/containment check has passed: callers use false
	# as the contract to preserve this material and render the complete legacy plane set instead.
	_configure_terrain_surfaces(material, surfaces)
	var rectangles: PackedVector4Array = PackedVector4Array()
	var kinds: PackedInt32Array = PackedInt32Array()
	rectangles.resize(MAX_SURFACES)
	kinds.resize(MAX_SURFACES)
	var bounds: Rect2 = Rect2()
	for index: int in ordered.size():
		var surface: Dictionary = ordered[index]
		var rect: Rect2 = surface_rect(surface)
		var center: Vector2 = rect.get_center()
		var half: Vector2 = rect.size / 2.0
		rectangles[index] = Vector4(center.x, center.y, half.x, half.y)
		kinds[index] = SURFACE_KIND[surface.type]
		bounds = rect if index == 0 else bounds.merge(rect)
	material.set_shader_parameter("surface_rects", rectangles)
	material.set_shader_parameter("surface_kinds", kinds)
	material.set_shader_parameter("surface_bounds", Vector4(bounds.position.x, bounds.position.y, bounds.end.x, bounds.end.y))
	material.set_shader_parameter("surface_count", ordered.size())
	return true


## Configure the ground shader's analytic normal cue from the same field rectangles and precedence as physics.
## This stays useful for legacy plane layouts, where colour overlays remain separate meshes.
static func _configure_terrain_surfaces(material: ShaderMaterial, surfaces: Array) -> void:
	var ordered: Array[Dictionary] = []
	for kind: String in ["mown", "runway"]:
		for surface: Dictionary in surfaces:
			if surface.get("type", "") == kind:
				ordered.append(surface)
	if ordered.size() > MAX_SURFACES:
		material.set_shader_parameter("terrain_relief_enabled", false)
		material.set_shader_parameter("terrain_surface_count", 0)
		return
	var rectangles: PackedVector4Array = PackedVector4Array()
	var kinds: PackedInt32Array = PackedInt32Array()
	var size: int = ordered.size()
	rectangles.resize(MAX_SURFACES)
	kinds.resize(MAX_SURFACES)
	for index: int in size:
		var surface: Dictionary = ordered[index]
		var rect: Rect2 = surface_rect(surface)
		var center: Vector2 = rect.get_center()
		var half: Vector2 = rect.size / 2.0
		rectangles[index] = Vector4(center.x, center.y, half.x, half.y)
		kinds[index] = SURFACE_KIND[surface.type]
	var profile: Dictionary = GroundTerrain.renderer_profile()
	material.set_shader_parameter("terrain_surface_rects", rectangles)
	material.set_shader_parameter("terrain_surface_kinds", kinds)
	material.set_shader_parameter("terrain_surface_count", size)
	material.set_shader_parameter("terrain_runway_amplitude_m", profile.runway_amplitude_m)
	material.set_shader_parameter("terrain_mown_amplitude_m", profile.mown_amplitude_m)
	material.set_shader_parameter("terrain_rough_amplitude_m", profile.rough_amplitude_m)
	material.set_shader_parameter("terrain_edge_blend_m", profile.edge_blend_m)
	material.set_shader_parameter("terrain_relief_start_m", profile.visibility_start_m)
	material.set_shader_parameter("terrain_relief_end_m", profile.visibility_end_m)
	material.set_shader_parameter("terrain_footprint_start_m", profile.footprint_start_m)
	material.set_shader_parameter("terrain_footprint_end_m", profile.footprint_end_m)
	material.set_shader_parameter("terrain_relief_enabled", true)


## Renderer-only x/z rectangle: east -> x, north -> -z. Input stays in float64 field coordinates.
static func surface_rect(surface: Dictionary) -> Rect2:
	var size: Vector2 = Vector2(surface.length_east_west, surface.width_north_south)
	var center: Vector2 = Vector2(surface.center_east, -float(surface.center_north))
	return Rect2(center - size / 2.0, size)
