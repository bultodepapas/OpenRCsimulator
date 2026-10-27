extends SceneTree

const Presentation := preload("res://workshop/presentation.gd")
const Store := preload("res://workshop/store.gd")
const Bundle := preload("res://workshop/bundle.gd")
const DraftStore := preload("res://workshop/draft_store.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Customization := preload("res://render/aircraft_customization.gd")
const Compiler := preload("res://workshop/compiler.gd")

var _checks := 0
var _failures := 0
var _directory := ""

func _initialize() -> void:
	_directory = "user://rgb-persistence-%d" % Time.get_ticks_usec()
	var described := Customization.describe(Catalog.DEFAULT_ID)
	_check("current companion resolves", described.get("ok", false), str(described.get("errors", [])))
	if not described.get("ok", false):
		_finish()
		return
	var profile := Presentation.defaults(described.bindings)
	profile.lighting = Presentation.LightingProfile.preset("festival")
	var bytes := FileAccess.get_file_as_bytes(Catalog.entry(Catalog.DEFAULT_ID).data)
	var saved := Store.save_variant("Night show", Catalog.DEFAULT_ID, bytes, Compiler.defaults(), "", _directory, {}, {}, -1, profile)
	_check("RGB build saves through immutable revision store", saved.get("ok", false), str(saved.get("errors", [])))
	if not saved.get("ok", false):
		_finish()
		return
	var loaded := Store.load_variant(saved.variant.id, _directory)
	_check("fresh disk load retains every lighting value", loaded.get("ok", false) and loaded.variant.presentation_profile.lighting == profile.lighting)
	var encoded := Bundle.export_variant(loaded.variant)
	_check("lighting bundle export validates", encoded.get("ok", false), str(encoded.get("errors", [])))
	if encoded.get("ok", false):
		var decoded := Bundle.decode(encoded.bytes)
		_check("bundle decode retains lighting and its profile identity", decoded.get("ok", false)
			and decoded.payload.presentation_profile.lighting == profile.lighting, str(decoded.get("errors", [])))
		var imported := Bundle.import_variant(encoded.bytes, _directory + "-import")
		_check("portable import copies a launchable current profile", imported.get("ok", false), str(imported.get("errors", [])))
	var empty_buffer := {"slot": "", "palette_step": 0, "color_text": "", "marking_slot": "", "marking_text": "", "marking_color": 0}
	var editor := {"page": "lighting", "name": "Night show", "numeric_buffers": {},
		"presentation_buffers": {"appearance": empty_buffer.duplicate(), "smoke": empty_buffer.duplicate(),
			"lighting": {"zone": "strip_left", "zones_open": true, "effects_open": false, "color_text": ["#12"]}}}
	var recovered := DraftStore.save_snapshot(_directory, loaded.variant, editor)
	_check("lighting draft recovery saves accepted data and pending editor separately", recovered.get("ok", false), str(recovered.get("errors", [])))
	var readback := DraftStore.load_snapshot(_directory)
	_check("recovery restores pending color without applying it", readback.get("ok", false)
		and readback.payload.presentation_profile.lighting == profile.lighting
		and readback.editor.presentation_buffers.lighting.color_text == ["#12"], str(readback.get("errors", [])))
	var invalid := profile.duplicate(true)
	invalid.lighting.effects[0].intensity = INF
	var rejected := Store.save_variant("Invalid", Catalog.DEFAULT_ID, bytes, Compiler.defaults(), "", _directory, {}, {}, -1, invalid)
	_check("corrupt nested lighting cannot create a stored revision", not rejected.get("ok", false))
	var unchanged := Store.load_variant(saved.variant.id, _directory)
	_check("failed save preserves previous lighting revision", unchanged.get("ok", false)
		and unchanged.variant.revision == 1 and unchanged.variant.presentation_profile.lighting == profile.lighting)
	_test_revision_one(described.bindings, bytes)
	_finish()


func _test_revision_one(bindings: Dictionary, aircraft_bytes: PackedByteArray) -> void:
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighting/night_radian_r1.json"))
	legacy = Presentation.LightingProfile.validate(legacy).profile
	for selection: String in ["preset", "custom"]:
		var profile := Presentation.defaults(bindings)
		profile.lighting = legacy.duplicate(true)
		profile.lighting.selection = selection
		if selection == "custom":
			profile.lighting.brightness = 0.77
		var before: Dictionary = profile.lighting.duplicate(true)
		var path := _directory.path_join("r1-" + selection)
		var saved := Store.save_variant("Revision 1 " + selection, Catalog.DEFAULT_ID, aircraft_bytes,
			Compiler.defaults(), "", path, {}, {}, -1, profile)
		_check("revision 1 %s saves without changing caller data" % selection, saved.get("ok", false) and profile.lighting == before,
			str(saved.get("errors", [])))
		if not saved.get("ok", false):
			continue
		var loaded := Store.load_variant(saved.variant.id, path)
		_check("revision 1 %s disk load preserves the original pin and all values" % selection,
			loaded.get("ok", false) and loaded.variant.presentation_profile.lighting == before)
		if not loaded.get("ok", false):
			continue
		var encoded := Bundle.export_variant(loaded.variant)
		_check("revision 1 %s exports through the current bundle writer" % selection, encoded.get("ok", false))
		if not encoded.get("ok", false):
			continue
		var decoded := Bundle.decode(encoded.bytes)
		_check("revision 1 %s bundle decode does not upgrade defaults" % selection, decoded.get("ok", false)
			and decoded.payload.presentation_profile.lighting == before)
		var imported := Bundle.import_variant(encoded.bytes, path.path_join("import"))
		_check("revision 1 %s portable import retains the materialized profile" % selection, imported.get("ok", false)
			and imported.variant.presentation_profile.lighting == before, str(imported.get("errors", [])))

func _check(label: String, success: bool, detail: String = "") -> void:
	_checks += 1
	if not success:
		_failures += 1
		printerr("FAIL ", label, " ", detail)

func _finish() -> void:
	_remove_tree(ProjectSettings.globalize_path(_directory))
	_remove_tree(ProjectSettings.globalize_path(_directory + "-import"))
	print("Lighting persistence: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)

func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null: return
	for filename: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(filename))
	for child: String in directory.get_directories():
		_remove_tree(path.path_join(child))
	DirAccess.remove_absolute(path)
