extends SceneTree
## F4U-16: selectable liveries. The manifest contract, on-use provenance, builds of every Corsair paint scheme, the
## derived identity check, the per-aircraft preference and Home's paint row. Negative cases use the result-returning
## APIs so this suite prints no engine errors.

const AirplaneBuilder := preload("res://render/airplane.gd")
const Imported := preload("res://aircraft/imported_model.gd")
const Manifest := preload("res://aircraft/model_manifest.gd")
const Registry := preload("res://aircraft/model_registry.gd")
const Preferences := preload("res://app_state/preferences.gd")
const Home := preload("res://ui/home.gd")
const CORSAIR := "f4u-corsair-250"
const STIK := "jensen-das-ugly-stik-60"
const ORDER := ["midnight", "scarlet", "splash", "spectrum", "blueangels"]
const PREFS := "user://test_aircraft_liveries.cfg"

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var described: Dictionary = Registry.describe(CORSAIR)
	_check("the Corsair manifest describes", described.get("ok", false), str(described.get("errors", [])))
	if not described.get("ok", false):
		_finish()
		return
	var manifest: Dictionary = described.manifest
	_test_manifest_contract(manifest)
	_test_registry(manifest)
	_test_builds(manifest)
	_test_preferences()
	await _test_home()
	_finish()


func _test_manifest_contract(manifest: Dictionary) -> void:
	var ids: Array = manifest.liveries.map(func(record: Dictionary) -> String: return record.id)
	_check("five liveries in the author's order, default first", ids == ORDER, str(ids))
	_check("the first livery is the default asset", manifest.liveries[0].path == manifest.asset.path and manifest.liveries[0].sha256 == manifest.asset.sha256)
	var choices: Array = AirplaneBuilder.livery_choices(CORSAIR)
	_check("menus list the five schemes with the author's names", choices.size() == 5 and choices[0].label == "Naval 308 — Midnight"
		and choices[4].label == "Blue Angels Corsair", str(choices))
	_check("a one-paint family lists no schemes", AirplaneBuilder.livery_choices(STIK).is_empty() and AirplaneBuilder.livery_choices("xcell-60-research").is_empty())
	_check("resolve: a non-default scheme stays, default and stale ones are the default paint",
		AirplaneBuilder.resolve_livery(CORSAIR, "scarlet") == "scarlet" and AirplaneBuilder.resolve_livery(CORSAIR, "midnight") == ""
		and AirplaneBuilder.resolve_livery(CORSAIR, "retired") == "" and AirplaneBuilder.resolve_livery(STIK, "scarlet") == "")
	var mutations := {
		"one livery": func(m: Dictionary) -> void: m.liveries.resize(1),
		"nine liveries": func(m: Dictionary) -> void:
			for i in 4: m.liveries.append(m.liveries[1].duplicate()),
		"duplicate id": func(m: Dictionary) -> void: m.liveries[2].id = "scarlet",
		"invalid id": func(m: Dictionary) -> void: m.liveries[1].id = "Blue-Angels",
		"empty label": func(m: Dictionary) -> void: m.liveries[1].label = " ",
		"control character in label": func(m: Dictionary) -> void: m.liveries[1].label = "Scarlet\n57",
		"long label": func(m: Dictionary) -> void: m.liveries[1].label = "x".repeat(49),
		"duplicate path": func(m: Dictionary) -> void: m.liveries[2].path = m.liveries[1].path,
		"path outside aircraft assets": func(m: Dictionary) -> void: m.liveries[1].path = "res://assets/scenery/f4u_corsair_scarlet.glb",
		"parent path": func(m: Dictionary) -> void: m.liveries[1].path = "res://assets/aircraft/../f4u_corsair_scarlet.glb",
		"not a GLB": func(m: Dictionary) -> void: m.liveries[1].path = "res://assets/aircraft/f4u-corsair-250/f4u_corsair_scarlet.tscn",
		"bad hash": func(m: Dictionary) -> void: m.liveries[1].sha256 = "ABC",
		"bad import hash": func(m: Dictionary) -> void: m.liveries[1].import_sha256 = "",
		"unknown field": func(m: Dictionary) -> void: m.liveries[1].texture = "res://x.png",
		"missing field": func(m: Dictionary) -> void: m.liveries[1].erase("import_sha256"),
		"default not first": func(m: Dictionary) -> void:
			var first: Dictionary = m.liveries[0]
			m.liveries[0] = m.liveries[1]
			m.liveries[1] = first,
		"not an array": func(m: Dictionary) -> void: m.liveries = {},
	}
	for label: String in mutations:
		var mutated := manifest.duplicate(true)
		mutations[label].call(mutated)
		_check("manifest rejects liveries with " + label, not Manifest.validate(mutated).ok)
	var stik: Dictionary = Registry.describe(STIK).manifest.duplicate(true)
	stik.liveries = manifest.liveries.duplicate(true)
	_check("a version 1 manifest cannot declare liveries", _has_code(Manifest.validate(stik), "MODEL_FIELD_UNKNOWN"))


func _test_registry(manifest: Dictionary) -> void:
	var default: Dictionary = Registry.livery(manifest)
	_check("no id selects the default asset", default.ok and default.livery.id == "midnight" and default.livery.path == manifest.asset.path)
	var scarlet: Dictionary = Registry.livery(manifest, "scarlet")
	_check("a delivered livery verifies on use", scarlet.ok and scarlet.livery.sha256 == manifest.liveries[1].sha256, str(scarlet.get("errors", [])))
	_check("an unknown livery is refused", _has_code(Registry.livery(manifest, "retired"), "MODEL_LIVERY_UNKNOWN"))
	_check("a one-paint model refuses any livery", _has_code(Registry.livery(Registry.describe(STIK).manifest, "scarlet"), "MODEL_LIVERY_UNKNOWN"))
	var tampered := manifest.duplicate(true)
	tampered.liveries[1].sha256 = "0".repeat(64)
	_check("a GLB that differs from its pin is refused", _has_code(Registry.livery(tampered, "scarlet"), "MODEL_HASH_MISMATCH"))
	tampered = manifest.duplicate(true)
	tampered.liveries[1].import_sha256 = "0".repeat(64)
	_check("an import sidecar that differs from its pin is refused", _has_code(Registry.livery(tampered, "scarlet"), "MODEL_HASH_MISMATCH"))


func _test_builds(manifest: Dictionary) -> void:
	var default_image := 0
	var default_hinges: Array = []
	for livery: String in [""] + ORDER:
		var airplane: Dictionary = AirplaneBuilder.build(CORSAIR, NAN, {}, livery)
		var name := livery if not livery.is_empty() else "(no id)"
		_check("%s builds through the production adapter" % name, not airplane.is_empty())
		if airplane.is_empty():
			continue
		var expected: Dictionary = manifest.liveries[maxi(ORDER.find(livery), 0)]
		var root: Node3D = airplane.root
		_check("%s carries its livery and GLB identity" % name, root.get_meta("livery") == expected.id and airplane.get("livery") == expected.id
			and root.get_meta("asset_sha256") == expected.sha256)
		_check("%s keeps every binding: hinges, gear rig, folds, propeller" % name, airplane.folds.size() == 2 and not airplane.gear_retraction.is_empty()
			and airplane.propeller is Node3D and (default_hinges.is_empty() or airplane.hinges.keys() == default_hinges))
		_check("%s passes the derived model check" % name, Registry.validate_derived(manifest, airplane).ok)
		var image := _fuselage_image_hash(root)
		if livery.is_empty():
			default_image = image
			default_hinges = airplane.hinges.keys()
		elif livery == "midnight":
			_check("the explicit default paints like no id", image == default_image)
		else:
			_check("%s paints the fuselage differently from the default" % name, image != 0 and image != default_image)
		if livery == "blueangels":
			root.set_meta("livery", "retired")
			_check("a root naming an unknown livery fails the derived check", _has_code(Registry.validate_derived(manifest, airplane), "MODEL_BUILD_LIVERY_UNKNOWN"))
			root.set_meta("livery", "scarlet")
			_check("a root whose GLB is not its livery's fails the derived check", _has_code(Registry.validate_derived(manifest, airplane), "MODEL_BUILD_ASSET_HASH_MISMATCH"))
		root.free()
	var refused: Dictionary = Imported.build_checked(manifest.duplicate(true), "retired")
	_check("the importer refuses an unknown livery", not refused.ok and str(refused.errors).contains("retired"))


func _fuselage_image_hash(root: Node3D) -> int:
	var mesh := root.find_child("fuselage_core", true, false) as MeshInstance3D
	var material := mesh.get_active_material(0) as StandardMaterial3D if mesh != null else null
	var image: Image = material.albedo_texture.get_image() if material != null and material.albedo_texture != null else null
	return hash(image.get_data()) if image != null else 0


func _test_preferences() -> void:
	var path := ProjectSettings.globalize_path(PREFS)
	DirAccess.remove_absolute(path)
	var prefs: Dictionary = Preferences.load_from(path)
	_check("fresh preferences choose no paint scheme", prefs.liveries.is_empty())
	prefs.liveries = {CORSAIR: "blueangels"}
	_check("a paint scheme saves", Preferences.save_to(path, prefs) == OK)
	_check("and loads back for its aircraft", Preferences.load_from(path).liveries == {CORSAIR: "blueangels"})
	for bad: Dictionary in [{"unknown-aircraft": "scarlet"}, {CORSAIR: "Blue Angels"}, {CORSAIR: 3}]:
		prefs.liveries = bad
		_check("save refuses %s" % str(bad), Preferences.save_to(path, prefs) == ERR_INVALID_DATA)
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("liveries", "unknown-aircraft", "scarlet")
	cfg.set_value("liveries", STIK, "Blue Angels")
	cfg.save(path)
	_check("load drops unknown aircraft and malformed IDs", Preferences.load_from(path).liveries == {CORSAIR: "blueangels"})
	DirAccess.remove_absolute(path)


func _test_home() -> void:
	var home: Control = Home.new()
	root.add_child(home)
	await process_frame
	home.set_livery_preferences({CORSAIR: "spectrum"})
	home.set_aircraft(STIK)
	_check("Home shows no paint row for a one-paint aircraft", not home.livery_button.visible and home.livery_id == "")
	home.set_aircraft(CORSAIR)
	_check("Home shows the Corsair's saved scheme", home.livery_button.visible and home.livery_id == "spectrum"
		and home.livery_button.text.contains("Spectrum Wings"), home.livery_button.text)
	var requested: Array[String] = []
	home.livery_requested.connect(func(livery: String) -> void: requested.append(livery))
	home.livery_button.pressed.emit()
	_check("the row requests the next scheme", requested == ["blueangels"], str(requested))
	home.set_livery("blueangels")
	home.livery_button.pressed.emit()
	_check("the last scheme cycles back to the default paint", requested.back() == "midnight")
	home.set_livery("midnight")
	_check("choosing the default shows it with no livery ID", home.livery_id == "" and home.livery_button.text.contains("Naval 308"))
	home.set_livery_preferences({CORSAIR: "retired"})
	_check("a stale saved scheme shows the default paint", home.livery_id == "")
	home.queue_free()
	await process_frame


func _has_code(result: Dictionary, code: String) -> bool:
	if result.get("ok", true): return false
	for diagnostic: Variant in result.get("diagnostics", []):
		if diagnostic is Dictionary and diagnostic.get("code") == code: return true
	return false


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if not condition: _failures += 1
	print(("ok   " if condition else "FAIL ") + label + ("" if condition or detail.is_empty() else " (" + detail + ")"))


func _finish() -> void:
	print("Aircraft liveries: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
