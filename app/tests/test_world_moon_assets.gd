# FW-MOON-04: the moon textures built by tools/world/moon_texture.py import as lossless, mipmapped textures with the
# documented layout: equirectangular, u = (east lon + 180°) / 360°, v = (90° − lat) / 180°, north up; the normal map
# holds unit (east, north, up) vectors as 0.5 + 0.5·n.
# Run: godot --headless --path . --script res://tests/test_world_moon_assets.gd
extends SceneTree

const ALBEDO_PATH := "res://assets/sky/moon/moon_albedo_2k.jpg"
const NORMAL_PATH := "res://assets/sky/moon/moon_normal_1k.png"

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


## Texel holding (lat, east lon) in an equirectangular image.
func _texel(image: Image, lat_deg: float, lon_deg: float) -> Vector2i:
	var x := clampi(int((lon_deg + 180.0) / 360.0 * image.get_width()), 0, image.get_width() - 1)
	var y := clampi(int((90.0 - lat_deg) / 180.0 * image.get_height()), 0, image.get_height() - 1)
	return Vector2i(x, y)


## Mean of R, G and B over a (2r+1)² box of stored (sRGB-encoded) values.
func _box_mean(image: Image, lat_deg: float, lon_deg: float, r := 2) -> float:
	var c := _texel(image, lat_deg, lon_deg)
	var total := 0.0
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var p := image.get_pixel(c.x + dx, c.y + dy)
			total += (p.r + p.g + p.b) / 3.0
	return total / float((2 * r + 1) * (2 * r + 1))


func _decode(image: Image, x: int, y: int) -> Array:
	var p := image.get_pixel(x, y)
	return [p.r * 2.0 - 1.0, p.g * 2.0 - 1.0, p.b * 2.0 - 1.0]


func _load_image(path: String, width: int, height: int, mip_levels: int) -> Image:
	var texture := load(path) as Texture2D
	_check("%s loads as Texture2D" % path, texture != null)
	if texture == null:
		return null
	_check("%s size" % path, texture.get_width() == width and texture.get_height() == height,
			"%dx%d" % [texture.get_width(), texture.get_height()])
	var image := texture.get_image()
	_check("%s has an image" % path, image != null)
	if image == null:
		return null
	_check("%s has mipmaps" % path, image.has_mipmaps())
	_check("%s full mipmap chain" % path, image.get_mipmap_count() == mip_levels, str(image.get_mipmap_count()))
	_check("%s is lossless RGB8" % path, image.get_format() == Image.FORMAT_RGB8, str(image.get_format()))
	return image


func _albedo() -> void:
	var image := _load_image(ALBEDO_PATH, 2048, 1024, 11)
	if image == null:
		return
	var sum := Vector3.ZERO
	var near := 0.0
	var far := 0.0
	var n := 0
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			var p := image.get_pixel(x, y)
			sum += Vector3(p.r, p.g, p.b)
			var lon := -180.0 + (x + 0.5) * 360.0 / image.get_width()
			if absf(lon) < 90.0:
				near += p.r + p.g + p.b
			else:
				far += p.r + p.g + p.b
			n += 1
	var mean := sum / float(n)
	var grey := (mean.x + mean.y + mean.z) / 3.0
	print("albedo mean (stored sRGB) R %.4f G %.4f B %.4f all %.4f" % [mean.x, mean.y, mean.z, grey])
	# SVS range-adjusted the colour map: a light, near-neutral grey, not the 0.12 physical albedo. The build-time
	# Pillow decode gives 0.7308 on the same 4-texel grid.
	_check("albedo mean is a light mid-grey", grey > 0.72 and grey < 0.74, str(grey))
	_check("albedo is near neutral, slightly red", mean.x >= mean.z and mean.x - mean.z < 0.06, str(mean))
	# Orientation: maria make the near side (|lon| < 90°) darker; Tycho (43.3° S, 11.2° W) is brighter than the
	# point mirrored east-west.
	_check("near side darker than far side", near < far, "%f %f" % [near, far])
	var tycho := _box_mean(image, -43.3, -11.2)
	var mirror := _box_mean(image, -43.3, 11.2)
	_check("Tycho bright at 11.2° W, not at 11.2° E", tycho > mirror + 0.08, "%f %f" % [tycho, mirror])


func _normal() -> void:
	var image := _load_image(NORMAL_PATH, 1024, 512, 10)
	if image == null:
		return
	var worst := 0.0
	var up_sum := 0.0
	var n := 0
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			var v := _decode(image, x, y)
			var length := sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
			worst = maxf(worst, absf(length - 1.0))
			up_sum += v[2]
			n += 1
	var mean_up := up_sum / float(n)
	print("normal mean up %.4f, worst |length - 1| %.4f over %d texels" % [mean_up, worst, n])
	# 8-bit quantisation moves each component by at most 1/255.
	_check("normals decode to unit length", worst < 0.01, str(worst))
	_check("mean up component", mean_up > 0.95, str(mean_up))
	var pole := _decode(image, 0, 0)
	_check("pole rows are straight up", absf(pole[0]) < 0.005 and absf(pole[1]) < 0.005 and pole[2] > 0.99, str(pole))
	# Sign and orientation: Tycho's west inner wall faces east, its east inner wall faces west.
	var radius_deg := rad_to_deg(42.5 / (1737.4 * cos(deg_to_rad(43.3))))
	var west := 0.0
	var east := 0.0
	for f in [0.4, 0.55, 0.7]:
		var w := _texel(image, -43.3, -11.2 - f * radius_deg)
		var e := _texel(image, -43.3, -11.2 + f * radius_deg)
		west += _decode(image, w.x, w.y)[0] / 3.0
		east += _decode(image, e.x, e.y)[0] / 3.0
	_check("Tycho west wall tilts east", west > 0.03, str(west))
	_check("Tycho east wall tilts west", east < -0.03, str(east))


func _initialize() -> void:
	_albedo()
	_normal()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
