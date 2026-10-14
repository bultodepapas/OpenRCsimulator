## DT-11a: exact default pixels/mips and isolation across image/material consumers.
extends SceneTree

const Ground = preload("res://render/ground.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
const Lighting = preload("res://render/time_of_day_lighting.gd")
const LightingConfig = preload("res://environment/time_of_day_config.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	ShaderClock.register()
	var expected := Ground.grass_image()
	var cold := Ground._default_grass_image()
	_check("cold default pixels and every mip equal the original recipe", _same_image(cold, expected))
	var warm := Ground._default_grass_image()
	_check("warm default pixels and every mip equal the original recipe", _same_image(warm, expected))
	_check("each image has independent identity", cold != warm)
	_check("one complete 256-square RGB8 mip chain", expected.get_data_size() == 262143 and expected.get_mipmap_count() == 8)
	cold.fill(Color.MAGENTA)
	cold.clear_mipmaps()
	_check("cold image edits do not mutate a live warm image", _same_image(warm, expected))
	warm.resize(8, 8)
	_check("warm image edits do not poison a subsequent image", _same_image(Ground._default_grass_image(), expected))
	var other := Ground.grass_image(1254)
	_check("explicit seed still controls the uncached recipe", not _same_image(other, expected) and _same_image(other, Ground.grass_image(1254)))
	_check("explicit seeds do not replace the default", _same_image(Ground._default_grass_image(), expected))
	_check("cached bytes stay bounded to one default tile", Ground._default_grass_bytes.size() == expected.get_data_size())
	_test_materials(expected)
	print("ground image cache: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _test_materials(expected: Image) -> void:
	var first := Ground.grass_material()
	var second := Ground.grass_material()
	var first_texture: ImageTexture = first.get_shader_parameter("grass")
	var second_texture: ImageTexture = second.get_shader_parameter("grass")
	_check("scene materials and textures remain independent", first != second and first_texture != second_texture)
	_check("both uploaded textures preserve all image bytes", _same_image(first_texture.get_image(), expected) and _same_image(second_texture.get_image(), expected))
	first.set_shader_parameter("pilot_xz", Vector2(11.0, 17.0))
	_check("pilot-specific uniforms remain independent", second.get_shader_parameter("pilot_xz") != Vector2(11.0, 17.0))
	var changed := expected.duplicate() as Image
	changed.fill(Color.MAGENTA)
	changed.generate_mipmaps()
	first_texture.update(changed)
	var third := Ground.grass_material()
	var third_texture: ImageTexture = third.get_shader_parameter("grass")
	_check("texture update preserves another live scene", _same_image(second_texture.get_image(), expected))
	_check("texture update preserves future scenes", _same_image(third_texture.get_image(), expected))
	var snapshot: Dictionary = Lighting.snapshot(LightingConfig.defaults())
	var lit := Ground.grass_material(snapshot)
	var reference: ShaderMaterial = load("res://render/atmosphere.gd").ground_material(ImageTexture.create_from_image(expected), snapshot)
	var uniforms_equal := true
	for uniform: Dictionary in RenderingServer.get_shader_parameter_list(reference.shader.get_rid()):
		var key := str(uniform.name)
		if key in ["grass", "turf_detail", "turf_detail_strength"]:
			continue
		uniforms_equal = uniforms_equal and lit.get_shader_parameter(key) == reference.get_shader_parameter(key)
	_check("lighting and all existing ground uniforms remain unchanged", uniforms_equal and lit.shader == reference.shader)
	_check("turf detail binding and strength remain unchanged", lit.get_shader_parameter("turf_detail") == Ground.TURF_DETAIL and lit.get_shader_parameter("turf_detail_strength") == 1.0)


func _same_image(actual: Image, expected: Image) -> bool:
	return actual != null and actual.get_size() == expected.get_size() and actual.get_format() == expected.get_format() \
		and actual.has_mipmaps() == expected.has_mipmaps() and actual.get_data() == expected.get_data()


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL ", label)
