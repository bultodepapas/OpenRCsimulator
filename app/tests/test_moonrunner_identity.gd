extends SceneTree
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Preferences := preload("res://app_state/preferences.gd")
const AppRoot := preload("res://app_root.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_check("only the canonical ID is listed", Catalog.ids().has("moonrunner-x99") and not Catalog.ids().has("skywalker-x8"))
	_check("old stock alias normalizes exactly", Catalog.canonical_id("skywalker-x8") == "moonrunner-x99" and Catalog.has("skywalker-x8"))
	_check("unrelated names are not aliased", not Catalog.has("workshop:skywalker-x8") and not Catalog.has("stock:skywalker-x8") and Catalog.canonical_id("other") == "other")
	var old: Dictionary = Catalog.entry("skywalker-x8")
	_check("historical Workshop lookup retains old visual family", old.get("id", "") == "skywalker-x8" and old.get("visual_family", "") == "skywalker-x8")
	_check("CLI old alias is normalized", AppRoot.aircraft_argument(PackedStringArray(["--aircraft=skywalker-x8"])) == "moonrunner-x99")
	_check("CLI canonical ID remains canonical", AppRoot.aircraft_argument(PackedStringArray(["--aircraft=moonrunner-x99"])) == "moonrunner-x99")
	var path := "user://moonrunner-identity-test-%d.cfg" % Time.get_ticks_usec()
	var config := ConfigFile.new()
	config.set_value("meta", "schema", Preferences.SCHEMA)
	config.set_value("flight", "aircraft", "skywalker-x8")
	config.set_value("liveries", "skywalker-x8", "abisal")
	_check("legacy preferences fixture saves", config.save(path) == OK)
	var before := FileAccess.get_sha256(path)
	var prefs: Dictionary = Preferences.load_from(path)
	_check("legacy stock and paint preferences load as canonical", prefs.aircraft == "moonrunner-x99" and prefs.liveries.get("moonrunner-x99", "") == "abisal")
	_check("loading does not rewrite legacy settings", FileAccess.get_sha256(path) == before)
	config.set_value("liveries", "moonrunner-x99", "bolido")
	config.save(path)
	prefs = Preferences.load_from(path)
	_check("current paint wins when both keys exist", prefs.liveries.get("moonrunner-x99", "") == "bolido")
	_check("conflicting historical paint is retained", prefs.liveries.get("skywalker-x8", "") == "abisal")
	_check("both paint choices can be saved without loss", Preferences.save_to(path, prefs) == OK)
	var persisted := ConfigFile.new()
	_check("saved settings retain both keys", persisted.load(path) == OK and persisted.get_value("liveries", "skywalker-x8", "") == "abisal" and persisted.get_value("liveries", "moonrunner-x99", "") == "bolido")
	config.set_value("liveries", "moonrunner-x99", "invalid id")
	config.save(path)
	prefs = Preferences.load_from(path)
	_check("valid legacy paint survives invalid current key", prefs.liveries.get("moonrunner-x99", "") == "abisal")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("MoonRunner identity: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func _check(name: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", name)
