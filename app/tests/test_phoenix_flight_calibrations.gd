extends SceneTree

const Library := preload("res://landscapes/phoenix_library.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const GroundStart := preload("res://physics/ground_start.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")
const CameraRig := preload("res://render/camera/camera_rig.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const TEST_ROOT := "user://phoenix-calibration-regression"

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Library.CALIBRATIONS + "calibrations.json"))
	_check(registry.version == 1 and registry.calibrations.size() >= 5, "known profiles available")
	var session := FlightSession.new()
	session.setup_stage_backend("gdscript_reference")
	session.setup("res://data/aircraft/jensen_ugly_stik_60.json", "jensen-das-ugly-stik-60")
	for id: String in registry.calibrations:
		var profile: Dictionary = registry.calibrations[id]
		var checked := FieldLoader.load_from(Library.CALIBRATIONS + str(profile.field))
		_check(checked.ok, "%s field validates" % profile.field)
		if not checked.ok:
			continue
		var start := GroundStart.threshold(checked.field)
		var runway: Dictionary = checked.field.surfaces.back()
		_check(start.ok and is_equal_approx(float(start.heading), PI / 2.0), "%s heading" % profile.field)
		_check(is_equal_approx(start.north, runway.center_north) and
			is_equal_approx(start.east, runway.center_east - runway.length_east_west * 0.5 + GroundStart.LINEUP),
			"%s lineup is inside its calibrated strip" % profile.field)
		var surface_path := Library.CALIBRATIONS + "asphalt-surfaces.json" if profile.surface == "paved" else GroundSurfaces.DEFAULT_PATH
		_check(session.set_field(checked.field, surface_path), "%s installs its contacts" % profile.field)
		var settled := session.try_runway_start(start.north, start.east, start.heading)
		_check(settled.ok, "%s settles the reference airplane: %s" % [profile.field, settled.get("message", "")])
	session.free()
	var asphalt := GroundSurfaces.load_table(Library.CALIBRATIONS + "asphalt-surfaces.json")
	_check(asphalt.ok and asphalt.table.runway.material_id == "qa_dry_asphalt", "paved contact coefficients valid")
	var camera := Camera3D.new()
	var rig := CameraRig.new(camera, 1.52)
	_check(rig.set_view("chase"), "ordinary camera accepts chase")
	rig.set_view("pilot")
	rig.fixed_pilot_eye = true
	_check(not rig.set_view("chase") and rig.view == "pilot", "photograph keeps its pilot eye")
	camera.free()
	_check_binding(registry.calibrations)
	print("Phoenix flight calibrations: %d failed" % failures)
	quit(int(failures != 0))


func _check_binding(profiles: Dictionary) -> void:
	var id := str(profiles.keys()[0])
	var directory := TEST_ROOT.path_join(id)
	DirAccess.make_dir_recursive_absolute(directory)
	for index in 6:
		var file := FileAccess.open(directory.path_join("face-%d.png" % index), FileAccess.WRITE)
		file.store_string("Not the expected face")
	var metadata := {version = 1, id = id, title = "Test", edge = 1024, panorama = true,
		faces = profiles[id].faces.duplicate()}
	_write_meta(directory, metadata)
	_check(not Library.flight_calibration(id, TEST_ROOT).is_empty(), "matching face manifest admits runtime check")
	_check(not str(Library.load_preview(id, func() -> bool: return false, TEST_ROOT).error).is_empty(),
		"launch refuses damaged face bytes")
	metadata.faces[0] = "a".repeat(64)
	_write_meta(directory, metadata)
	_check(Library.flight_calibration(id, TEST_ROOT).is_empty(), "metadata edit cannot borrow a known calibration")
	Library.remove(id, TEST_ROOT)
	DirAccess.remove_absolute(TEST_ROOT)


func _write_meta(directory: String, metadata: Dictionary) -> void:
	var file := FileAccess.open(directory.path_join("site.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(metadata))


func _check(condition: bool, detail: String) -> void:
	if not condition:
		print("FAIL ", detail)
		failures += 1
