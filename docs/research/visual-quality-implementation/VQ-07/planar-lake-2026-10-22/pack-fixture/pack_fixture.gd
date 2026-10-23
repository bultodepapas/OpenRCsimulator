extends Node3D

const LakePlanarReflectionScript: Script = preload("res://render/lake/lake_planar_reflection.gd")
const VendorPlanarReflectorScript: Script = preload("res://render/lake/vendor/smart_planar_reflector/planar_reflector.gd")

func _ready() -> void:
	var helper: Object = LakePlanarReflectionScript.new()
	var vendor: Object = VendorPlanarReflectorScript.new()
	var license_text := FileAccess.get_file_as_string("res://render/lake/vendor/smart_planar_reflector/LICENSE")
	var credits_text := FileAccess.get_file_as_string("res://render/lake/vendor/smart_planar_reflector/CREDITS.md")
	var valid := helper is MeshInstance3D and vendor is MeshInstance3D \
		and not license_text.strip_edges().is_empty() and not credits_text.strip_edges().is_empty()
	if valid:
		print("pack resource load: helper/vendor scripts instantiated; LICENSE and CREDITS present")
	else:
		printerr("FAIL pack resources missing, empty, or not instantiable")
	helper.free()
	vendor.free()
	get_tree().quit(0 if valid else 1)
