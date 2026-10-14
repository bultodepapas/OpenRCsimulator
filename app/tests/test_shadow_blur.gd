## DT-11a: exact row-major blur sums, clamped edges and independent shadow resources.
extends SceneTree

var Shadow: Script
var _checks := 0
var _failed := 0
const SIZE := 128

func _initialize() -> void:
	Shadow = load("res://render/shadow.gd")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shadow="): Shadow = load(arg.trim_prefix("--shadow="))
	var fixtures: Array[PackedFloat32Array] = []
	var zero := PackedFloat32Array()
	zero.resize(SIZE * SIZE)
	fixtures.append(zero)
	var constant := zero.duplicate()
	constant.fill(1.0)
	fixtures.append(constant)
	# Every corner, each edge midpoint and the interior expose clamping mistakes.
	for index: int in [0, SIZE - 1, (SIZE - 1) * SIZE, SIZE * SIZE - 1,
		SIZE / 2, (SIZE / 2) * SIZE, (SIZE / 2) * SIZE + SIZE - 1,
		(SIZE - 1) * SIZE + SIZE / 2, (SIZE / 2) * SIZE + SIZE / 2]:
		var impulse := zero.duplicate()
		impulse[index] = 1.0
		fixtures.append(impulse)
	var random := zero.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = 145712
	for index in random.size(): random[index] = rng.randf_range(-1.0, 1.0)
	fixtures.append(random)
	var dynamic := zero.duplicate()
	for index in dynamic.size(): dynamic[index] = [1e12, 0.0001, -1e12, 0.7, -0.1][index % 5]
	fixtures.append(dynamic)
	for index in fixtures.size():
		var input := fixtures[index]
		var before := input.to_byte_array()
		var expected := _reference_blur(input)
		var actual: PackedFloat32Array = Shadow._blur(input)
		_check("fixture %d complete float32 output equals scalar sum" % index, actual.to_byte_array() == expected.to_byte_array())
		_check("fixture %d second pass remains exact" % index, Shadow._blur(actual).to_byte_array() == _reference_blur(expected).to_byte_array())
		actual[0] = 99.0
		_check("fixture %d input remains isolated" % index, input.to_byte_array() == before)
	var corner := zero.duplicate()
	corner[0] = 1.0
	var blurred: PackedFloat32Array = Shadow._blur(corner)
	_check("corner replication contributes four of nine taps", is_equal_approx(blurred[0], 4.0 / 9.0))
	_check("corner adjacent edge contributes two of nine taps", is_equal_approx(blurred[1], 2.0 / 9.0) and is_equal_approx(blurred[SIZE], 2.0 / 9.0))
	_check("corner interior contributes one of nine taps", is_equal_approx(blurred[SIZE + 1], 1.0 / 9.0) and blurred[SIZE + 2] == 0.0)
	_check("constant field stays constant at every edge", Shadow._blur(constant).to_byte_array() == constant.to_byte_array())
	_test_images_and_carriers()
	print("shadow blur: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed else 0)

func _reference_blur(input: PackedFloat32Array) -> PackedFloat32Array:
	var output := PackedFloat32Array()
	output.resize(input.size())
	for y in SIZE:
		for x in SIZE:
			var sum := 0.0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					sum += input[clampi(y + dy, 0, SIZE - 1) * SIZE + clampi(x + dx, 0, SIZE - 1)]
			output[y * SIZE + x] = sum / 9.0
	return output

func _test_images_and_carriers() -> void:
	var first: Image = Shadow.silhouette()
	var second: Image = Shadow.silhouette()
	var bytes := second.get_data()
	_check("complete RGBA8 mip chain is retained", first.get_format() == Image.FORMAT_RGBA8 and first.get_mipmap_count() == 7 and first.get_data_size() == 87380)
	_check("fresh images preserve exact bytes", first != second and first.get_data() == bytes)
	first.fill(Color.MAGENTA)
	first.clear_mipmaps()
	_check("image edits cannot poison another image or later calls", second.get_data() == bytes and Shadow.silhouette().get_data() == bytes)
	var host := Node3D.new()
	var a: MeshInstance3D = Shadow.create(host)
	var b: MeshInstance3D = Shadow.create(host)
	var am := a.material_override as StandardMaterial3D
	var bm := b.material_override as StandardMaterial3D
	_check("carrier meshes, materials and textures are independent", a.mesh != b.mesh and am != bm and am.albedo_texture != bm.albedo_texture)
	_check("uploaded textures preserve all mip bytes", am.albedo_texture.get_image().get_data() == bytes and bm.albedo_texture.get_image().get_data() == bytes)
	var changed := second.duplicate() as Image
	changed.fill(Color.MAGENTA)
	changed.generate_mipmaps()
	(am.albedo_texture as ImageTexture).update(changed)
	Shadow.update(a, Basis.IDENTITY, Vector3(0, 6, 0), 2.0, 1.0)
	_check("texture and opacity changes do not affect another carrier", bm.albedo_texture.get_image().get_data() == bytes and bm.albedo_color == Color(0, 0, 0, 0.6))
	var c: MeshInstance3D = Shadow.create(host)
	_check("later carriers retain the original texture", (c.material_override as StandardMaterial3D).albedo_texture.get_image().get_data() == bytes)
	host.free()

func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failed += 1
		printerr("FAIL ", label)
