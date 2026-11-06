extends SceneTree
const Variants := preload("res://render/cloud_shader_variants.gd")
var checks := 0
var failures := 0


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func _initialize() -> void:
	var original := OS.get_environment(Variants.ENVIRONMENT_KEY)
	for mode: String in ["", "off", "bad", "three", "two_three"]:
		OS.set_environment(Variants.ENVIRONMENT_KEY, mode)
		var shader := Variants.sky_shader()
		var candidate := mode in ["three", "two_three"]
		check("default and unknown preserve base " + mode, (shader == Variants.BASE) == not candidate)
		check("resources reused " + mode, shader == Variants.sky_shader())
		if candidate:
			check("explicit compile variant " + mode, shader.code.begins_with(
				"#define OPENRC_CLOUD_BOUNDS %d\n" % (2 if mode == "two_three" else 3)))
		check("effective mode is honest " + mode, Variants.diagnostics().effective == (mode if candidate else "off"))
	check("bounded variant resource count", Variants._variants.size() == 2)
	OS.set_environment(Variants.ENVIRONMENT_KEY, original)
	print("cloud shader variants: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
