# Textured grass (D7): flat colour gives no height or speed cues; a fine, irregular texture does (motion parallax
# and texture density). Deterministic value noise (seeded), so captures stay byte-identical run to run.
extends RefCounted

const Spec := preload("res://spec.gd")

const SIZE := 256


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


## The mown runway strip: flat colour, matte like the grass.
static func runway_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Spec.RUNWAY_COLOR
	mat.metallic_specular = 0.0
	mat.roughness = 1.0
	return mat


static func grass_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(grass_image())
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.metallic_specular = 0.0 # grass is matte: no sky reflection at grazing angles
	mat.roughness = 1.0
	var tiles := Spec.GROUND_SIZE / Spec.GROUND.tile_m
	mat.uv1_scale = Vector3(tiles, tiles, 1.0)
	return mat
