extends SceneTree
## F4U-16: selectable liveries. The manifest contract, on-use provenance, builds of every Corsair paint scheme, the
## derived identity check, the per-aircraft preference and Home's paint row. Negative cases use the result-returning
## APIs so this suite prints no engine errors.
## F4U-19: when the Corsair ships one paint, the contract and on-use checks run on a synthetic manifest of the ORDER
## ids and the shipped Corsair is checked as a one-paint aircraft. F4U-20: g2.2 ships all thirteen schemes.

const AirplaneBuilder := preload("res://render/airplane.gd")
const Imported := preload("res://aircraft/imported_model.gd")
const Manifest := preload("res://aircraft/model_manifest.gd")
const Registry := preload("res://aircraft/model_registry.gd")
const Preferences := preload("res://app_state/preferences.gd")
const Home := preload("res://ui/home.gd")
const CORSAIR := "f4u-corsair-250"
const STIK := "jensen-das-ugly-stik-60"
const ORDER := ["midnight", "three_tone", "scarlet", "splash", "spectrum", "blueangels", "thunderbirds", "chrome", "p40",
	"japan", "luftwaffe", "italy", "carbon"]
## The non-default scheme the registry checks pick.
const PICK := "scarlet"
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
	if manifest.has("liveries"):
		_test_manifest_contract(manifest)
		_test_registry(manifest)
		_test_builds(manifest)
		_test_preferences()
		await _test_home()
	else:
		print("note: the Corsair ships one paint (F4U-19); livery mechanics run on a synthetic manifest")
		_test_one_paint_corsair(manifest)
		var synthetic := _synthetic(manifest)
		_check("a synthetic manifest of every scheme validates", Manifest.validate(synthetic).ok, str(Manifest.validate(synthetic).get("errors", [])))
		_test_mutations(synthetic)
		_test_registry(_aliased(synthetic, manifest))
		_test_preferences()
		await _test_one_paint_home()
	_finish()


## The shipped manifest with liveries in ORDER: the default asset first, then unique paths with placeholder pins.
func _synthetic(manifest: Dictionary) -> Dictionary:
	var synthetic := manifest.duplicate(true)
	synthetic.liveries = []
	for id: String in ORDER:
		var default := id == ORDER[0]
		synthetic.liveries.append({"id": id, "label": id.capitalize(),
			"path": manifest.asset.path if default else "res://assets/aircraft/f4u-corsair-250/f4u_corsair_%s.glb" % id,
			"sha256": manifest.asset.sha256 if default else "a".repeat(64),
			"import_sha256": _default_import_sha256(manifest) if default else "b".repeat(64)})
	return synthetic


## The synthetic manifest with PICK aliasing the real default GLB and sidecar, so on-use verification hashes actual
## files. Built for Registry.livery() only: validate() refuses the duplicate path.
func _aliased(synthetic: Dictionary, manifest: Dictionary) -> Dictionary:
	var aliased := synthetic.duplicate(true)
	var pick: Dictionary = aliased.liveries[ORDER.find(PICK)]
	pick.path = manifest.asset.path
	pick.sha256 = manifest.asset.sha256
	pick.import_sha256 = _default_import_sha256(manifest)
	return aliased


func _default_import_sha256(manifest: Dictionary) -> String:
	for record: Dictionary in manifest.dependencies:
		if record.path == manifest.asset.path + ".import": return record.sha256
	return ""


func _test_one_paint_corsair(manifest: Dictionary) -> void:
	_check("the one-paint Corsair lists no schemes", AirplaneBuilder.livery_choices(CORSAIR).is_empty())
	_check("every saved scheme resolves to its default paint", AirplaneBuilder.resolve_livery(CORSAIR, "scarlet") == ""
		and AirplaneBuilder.resolve_livery(CORSAIR, "midnight") == "")
	_check("the registry refuses any livery id", _has_code(Registry.livery(manifest, "scarlet"), "MODEL_LIVERY_UNKNOWN"))
	var airplane: Dictionary = AirplaneBuilder.build(CORSAIR)
	_check("the default paint builds through the production adapter", not airplane.is_empty())
	if not airplane.is_empty():
		_check("it keeps every binding: hinges, gear rig, folds, propeller", airplane.folds.size() == 2
			and not airplane.gear_retraction.is_empty() and airplane.propeller is Node3D and airplane.hinges.size() == 10)
		_check("it passes the derived model check", Registry.validate_derived(manifest, airplane).ok)
		airplane.root.free()
	var refused: Dictionary = Imported.build_checked(manifest.duplicate(true), "retired")
	_check("the importer refuses a livery id", not refused.ok and str(refused.errors).contains("retired"))


func _test_one_paint_home() -> void:
	var home: Control = Home.new()
	root.add_child(home)
	await process_frame
	home.set_livery_preferences({CORSAIR: "spectrum"})
	home.set_aircraft(CORSAIR)
	_check("Home shows no paint row for the one-paint Corsair, whatever was saved", not home.livery_button.visible and home.livery_id == "")
	home.set_aircraft(STIK)
	_check("Home shows no paint row for the Stik", not home.livery_button.visible and home.livery_id == "")
	home.queue_free()
	await process_frame


func _test_manifest_contract(manifest: Dictionary) -> void:
	var ids: Array = manifest.liveries.map(func(record: Dictionary) -> String: return record.id)
	_check("%d liveries in the author's order, default first" % ORDER.size(), ids == ORDER, str(ids))
	_check("the first livery is the default asset", manifest.liveries[0].path == manifest.asset.path and manifest.liveries[0].sha256 == manifest.asset.sha256)
	var choices: Array = AirplaneBuilder.livery_choices(CORSAIR)
	_check("menus list every scheme with the author's names", choices.size() == ORDER.size() and choices[0].label == "Naval 308 — Midnight"
		and choices.back().label == "Carbon 12 / Aero Sport", str(choices))
	_check("a one-paint family lists no schemes", AirplaneBuilder.livery_choices(STIK).is_empty() and AirplaneBuilder.livery_choices("xcell-60-research").is_empty())
	_check("resolve: a non-default scheme stays, default and stale ones are the default paint",
		AirplaneBuilder.resolve_livery(CORSAIR, "scarlet") == "scarlet" and AirplaneBuilder.resolve_livery(CORSAIR, "midnight") == ""
		and AirplaneBuilder.resolve_livery(CORSAIR, "retired") == "" and AirplaneBuilder.resolve_livery(STIK, "scarlet") == "")
	_test_mutations(manifest)


## Manifest rules on a `liveries` list in ORDER (shipped or synthetic).
func _test_mutations(manifest: Dictionary) -> void:
	var mutations := {
		"one livery": func(m: Dictionary) -> void: m.liveries.resize(1),
		"more liveries than the limit": func(m: Dictionary) -> void:
			while m.liveries.size() <= Manifest.LIVERY_LIMIT:
				var extra: Dictionary = m.liveries[1].duplicate()
				extra.id = "extra%d" % m.liveries.size()
				extra.path = "res://assets/aircraft/f4u-corsair-250/f4u_corsair_%s.glb" % extra.id
				m.liveries.append(extra),
		"duplicate id": func(m: Dictionary) -> void: m.liveries[2].id = m.liveries[1].id,
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
	var index := ORDER.find(PICK)
	var picked: Dictionary = Registry.livery(manifest, PICK)
	_check("a delivered livery verifies on use", picked.ok and picked.livery.sha256 == manifest.liveries[index].sha256, str(picked.get("errors", [])))
	_check("an unknown livery is refused", _has_code(Registry.livery(manifest, "retired"), "MODEL_LIVERY_UNKNOWN"))
	_check("a one-paint model refuses any livery", _has_code(Registry.livery(Registry.describe(STIK).manifest, "scarlet"), "MODEL_LIVERY_UNKNOWN"))
	var tampered := manifest.duplicate(true)
	tampered.liveries[index].sha256 = "0".repeat(64)
	_check("a GLB that differs from its pin is refused", _has_code(Registry.livery(tampered, PICK), "MODEL_HASH_MISMATCH"))
	tampered = manifest.duplicate(true)
	tampered.liveries[index].import_sha256 = "0".repeat(64)
	_check("an import sidecar that differs from its pin is refused", _has_code(Registry.livery(tampered, PICK), "MODEL_HASH_MISMATCH"))


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
	home.set_livery(ORDER.back())
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
