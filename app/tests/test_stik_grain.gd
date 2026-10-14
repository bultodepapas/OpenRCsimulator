## DT-11a: a baked texture must preserve the procedural appearance at every mip level.
extends SceneTree

const Finish := preload("res://aircraft/ugly_stik_finish.gd")
var _failures := 0
var _checks := 0


func _initialize() -> void:
	var baked: Image = load(Finish.GRAIN_PATH) as Image if ResourceLoader.exists(Finish.GRAIN_PATH) else null
	_check("generated grain resource is present", baked != null)
	if baked != null:
		var reference := Finish.generate_grain_image()
		_check("grain dimensions and RGB8 format are preserved",
			baked.get_size() == Finish.GRAIN_SIZE and baked.get_format() == Image.FORMAT_RGB8)
		_check("grain contains the complete procedural mip chain",
			baked.has_mipmaps() and baked.get_mipmap_count() == reference.get_mipmap_count())
		_check("every grain pixel and mip byte equals fresh procedural generation",
			baked.get_data() == reference.get_data())
		var texture := Finish.grain()
		_check("runtime texture retains the baked pixels and mip chain",
			texture.get_image().get_data() == baked.get_data())
		_check("repeated requests reuse the existing texture", Finish.grain() == texture)
		var material := Finish.propeller_wood(Color("a77c51"))
		_check("wood material uses the checked texture and anisotropic mip filtering",
			material.albedo_texture == texture
			and material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC)
	print("%d Stik grain checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _check(label: String, passed: bool) -> void:
	_checks += 1
	print(("ok   " if passed else "FAIL ") + label)
	if not passed:
		_failures += 1
