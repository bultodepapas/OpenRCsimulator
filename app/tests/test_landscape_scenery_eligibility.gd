extends SceneTree

const FieldLoader := preload("res://data/field_loader.gd")
const Scenery := preload("res://scenery/scenery.gd")
const SceneryLoader := preload("res://scenery/scenery_loader.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var previous_enabled := OS.get_environment("OPENRC_SCENERY")
	var previous_file := OS.get_environment("OPENRC_SCENERY_FILE")
	var previous_landscape := OS.get_environment("OPENRC_LANDSCAPE_UPGRADE")
	OS.set_environment("OPENRC_SCENERY", "on")
	OS.set_environment("OPENRC_SCENERY_FILE", "")
	OS.set_environment("OPENRC_LANDSCAPE_UPGRADE", "on")
	var loaded: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	_check("default field loads", bool(loaded.get("ok", false)))
	if not loaded.get("ok", false):
		_finish(previous_enabled, previous_file, previous_landscape)
		return
	var field: Dictionary = loaded.field
	var implicit_opts := {file = SceneryLoader.DEFAULT_PATH, file_explicit = false}
	_check("implicit default layout applies to a fresh default field", Scenery.layout_file_applies(field, implicit_opts))
	var custom_field: Dictionary = _custom_field(field)
	_check("same-id custom field remains valid", bool(FieldLoader.validate(_raw_custom_field()).get("ok", false)))
	_check("implicit default scenery is skipped for changed spatial geometry",
		not Scenery.layout_file_applies(custom_field, implicit_opts))
	var visual_root := Node3D.new()
	Scenery.attach(visual_root, custom_field)
	_check("visual builder does not attach misaligned implicit scenery", visual_root.get_node_or_null("Scenery") == null)
	visual_root.free()
	var collision: Dictionary = CollisionSetup.build(custom_field)
	_check("collision setup succeeds without the ineligible implicit layout",
		bool(collision.get("ok", false)), str(collision.get("errors", [])))
	OS.set_environment("OPENRC_SCENERY_FILE", SceneryLoader.DEFAULT_PATH)
	var explicit_collision: Dictionary = CollisionSetup.build(custom_field)
	_check("explicit default-layout request still fails full placement validation",
		not bool(explicit_collision.get("ok", false)) and not (explicit_collision.get("errors", []) as PackedStringArray).is_empty(),
		str(explicit_collision.get("errors", [])))
	_finish(previous_enabled, previous_file, previous_landscape)


func _custom_field(field: Dictionary) -> Dictionary:
	var custom: Dictionary = field.duplicate(true)
	custom.objects = []
	custom.erase("flight_cues")
	custom.pilot.north = 7.25
	custom.pilot.east = -6.5
	custom.pilot.down = 0.25
	custom.pilot.eye_height = 2.4
	for surface: Dictionary in custom.surfaces:
		if surface.id == "runway":
			surface.center_north = 38.5
			surface.center_east = -11.25
			surface.length_east_west = 132.0
			surface.width_north_south = 18.0
	return custom


func _raw_custom_field() -> Dictionary:
	var parser := JSON.new()
	parser.parse(FileAccess.get_file_as_string(FieldLoader.DEFAULT_PATH))
	var raw: Dictionary = parser.data.duplicate(true)
	raw.objects = []
	raw.erase("flight_cues")
	raw.pilot.north.value = 7.25
	raw.pilot.east.value = -6.5
	raw.pilot.down.value = 0.25
	raw.pilot.eye_height.value = 2.4
	for surface: Dictionary in raw.surfaces:
		if surface.id == "runway":
			surface.center_north.value = 38.5
			surface.center_east.value = -11.25
			surface.length_east_west.value = 132.0
			surface.width_north_south.value = 18.0
	return raw


func _check(label: String, valid: bool, detail := "") -> void:
	checks += 1
	if not valid:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _finish(previous_enabled: String, previous_file: String, previous_landscape: String) -> void:
	OS.set_environment("OPENRC_SCENERY", previous_enabled)
	OS.set_environment("OPENRC_SCENERY_FILE", previous_file)
	OS.set_environment("OPENRC_LANDSCAPE_UPGRADE", previous_landscape)
	print("landscape scenery eligibility: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)
