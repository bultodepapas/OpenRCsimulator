extends SceneTree

const Airplane := preload("res://render/airplane.gd")
const Registry := preload("res://aircraft/model_registry.gd")
const Overlays := preload("res://aircraft/model_overlay_registry.gd")
const Companions := preload("res://aircraft/customization_overlay.gd")
const Customization := preload("res://render/aircraft_customization.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const HullContact := preload("res://physics/hull_contact.gd")
const BASIC := "jensen-das-ugly-stik-60"
const ELECTRIC := "stik-electric-6s"
var checks := 0
var failures := 0

func _initialize() -> void:
	_check("closed family list", Overlays.FAMILIES == ["moonrunner-x99", ELECTRIC])
	_check("model and overlay registries use the same closed set", Registry.OVERLAY_FAMILIES == Overlays.FAMILIES)
	_check("unknown model is refused", not Overlays.describe("unknown").get("ok", false))
	var model: Dictionary = Registry.describe(ELECTRIC)
	var companion: Dictionary = Companions.describe(ELECTRIC)
	_check("electric model and its proof validate", model.get("ok", false), str(model.get("errors", [])))
	_check("electric companion validates", companion.get("ok", false), str(companion.get("errors", [])))
	if model.get("ok", false) and companion.get("ok", false):
		_check("wrong model hash is rejected", not Companions.describe_for_model(ELECTRIC, "0".repeat(64)).get("ok", false))
		for slot: Dictionary in companion.bindings.smoke_slots:
			_check("electric smoke has no combustion outlet", slot.get("role") != "exhaust" and not slot.has("source_kind"))
	_test_exact_overlay_directories()
	_test_instances()
	print("Electric Stik overlay: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _test_exact_overlay_directories() -> void:
	# Substitute only the directory in disposable copies; the real resolvers
	# still enforce the family set, identity and source proofs.
	var root := "user://stik_overlay_set_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	for spec: Dictionary in [
		{script = "res://aircraft/model_overlay_registry.gd", directory = "res://data/aircraft_model_overlays"},
		{script = "res://aircraft/customization_overlay.gd", directory = "res://data/aircraft_customization_overlays"},
	]:
		var directory: String = root.path_join(str(spec.script).get_file().get_basename())
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
		for family: String in Overlays.FAMILIES:
			var output := FileAccess.open(directory.path_join(family + ".json"), FileAccess.WRITE)
			output.store_buffer(FileAccess.get_file_as_bytes(str(spec.directory).path_join(family + ".json")))
			output.close()
		var source := FileAccess.get_file_as_string(str(spec.script))
		var script_path := root.path_join(str(spec.script).get_file())
		var script_file := FileAccess.open(script_path, FileAccess.WRITE)
		script_file.store_string(source.replace(str(spec.directory), directory))
		script_file.close()
		var resolver: Script = load(script_path)
		_check("disposable resolver compiles", resolver != null, str(spec.script))
		if resolver != null:
			_check("complete registered set resolves", resolver.describe("moonrunner-x99").get("ok", false), str(spec.script))
			var electric_path := directory.path_join(ELECTRIC + ".json")
			var electric_bytes := FileAccess.get_file_as_bytes(electric_path)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(electric_path))
			_check("missing registered family blocks either resolution", not resolver.describe("moonrunner-x99").get("ok", false), str(spec.script))
			var restored := FileAccess.open(electric_path, FileAccess.WRITE)
			restored.store_buffer(electric_bytes)
			restored.close()
			var unexpected := FileAccess.open(directory.path_join("unregistered.json"), FileAccess.WRITE)
			unexpected.store_string("{}")
			unexpected.close()
			_check("unregistered family blocks resolution", not resolver.describe(ELECTRIC).get("ok", false), str(spec.script))
			DirAccess.remove_absolute(ProjectSettings.globalize_path(directory.path_join("unregistered.json")))
		for family: String in Overlays.FAMILIES:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(directory.path_join(family + ".json")))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(script_path))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root))


func _test_instances() -> void:
	var basic_before: Dictionary = Airplane.build(BASIC)
	var electric: Dictionary = Airplane.build(ELECTRIC)
	var electric_other: Dictionary = Airplane.build(ELECTRIC)
	var basic_after: Dictionary = Airplane.build(BASIC)
	_check("basic and electric build in either order and concurrently", not basic_before.is_empty() and not electric.is_empty() and not electric_other.is_empty() and not basic_after.is_empty())
	if basic_before.is_empty() or electric.is_empty() or electric_other.is_empty() or basic_after.is_empty():
		for item: Dictionary in [basic_before, electric, electric_other, basic_after]:
			if item.get("root") is Node: item.root.free()
		return
	_check("basic retains its engine before and after electric", basic_before.root.find_child("engine_assembly", true, false) != null and basic_after.root.find_child("engine_assembly", true, false) != null)
	_check("electric has a motor and no combustion installation", electric.root.find_child("electric_motor", true, false) != null and electric.root.find_child("engine_assembly", true, false) == null and electric.root.find_child("carburetor_throttle_arm_hinge", true, false) == null)
	_check("electric has no throttle linkage or exhaust", not electric.controls.mechanisms.has("throttle") and electric.root.get_meta("exhausts", []).is_empty())
	_check("electric surface linkages remain available", electric.controls.get("ok", false) and electric.controls.mechanisms.size() == 4)
	var painted := Customization.apply(electric, {"paint": [{"slot": "body", "color": "#327DE8FF", "pattern": "solid", "accent": "none"}], "markings": []})
	_check("electric Workshop paint applies", painted.get("ok", false), str(painted.get("errors", [])))
	var painted_mesh := electric.root.get_node("fuselage") as MeshInstance3D
	var other_mesh := electric_other.root.get_node("fuselage") as MeshInstance3D
	var basic_mesh := basic_after.root.get_node("fuselage") as MeshInstance3D
	_check("paint remains per instance", painted_mesh.get_active_material(0) != other_mesh.get_active_material(0) and painted_mesh.get_active_material(0) != basic_mesh.get_active_material(0))
	var blades := electric.propeller.get_node("propeller_blades") as MeshInstance3D
	var visual_diameter: float = blades.mesh.get_aabb().size.y * electric.propeller.scale.y
	for path: String in ["res://data/aircraft/stik_electric_6s.json", "res://data/aircraft/battery/stik_electric_6s_pack.json"]:
		var loaded: Dictionary = AircraftData.load_file(path)
		_check("electric data loads: " + path, loaded.get("ok", false), str(loaded.get("errors", [])))
		if loaded.get("ok", false):
			var disc: Dictionary = HullContact.prop_disc(loaded.model.propulsion)
			_check("physical strike disc matches visual: " + path, not disc.is_empty() and absf(2.0 * float(disc.radius) - visual_diameter) < 0.00001)
	var original: float = electric.propeller_diameter_m
	_check("propeller can be reapplied without cumulative scaling", Airplane.apply_propeller_diameter(electric, original * 0.9) and Airplane.apply_propeller_diameter(electric, original) and absf(electric.propeller.scale.y - 1.0) < 0.00001)
	for item: Dictionary in [basic_before, electric, electric_other, basic_after]: item.root.free()


func _check(name: String, passed: bool, detail: String = "") -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", name, ": ", detail)
