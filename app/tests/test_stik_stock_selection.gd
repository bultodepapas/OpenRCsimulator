# EL1e-STIK: visible stock choices must not remove technical fixtures or overwrite old selections.
extends SceneTree

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Preferences := preload("res://app_state/preferences.gd")
const PreferencesFile := preload("res://app_state/preferences_file.gd")
const UiDriver := preload("res://tests/ui_driver.gd")
const Bridge := preload("res://debug/debug_bridge.gd")
const PATH := "user://test_stik_stock_selection.cfg"
const HIDDEN := ["stik-glow-61fx-2t", "stik-glow-55ax-2t", "stik-glow-fs64v-4t"]
var failed := 0


func check(label: String, condition: bool) -> void:
	print("%s %s" % ["FAIL" if not condition else "ok", label])
	if not condition: failed += 1


func _initialize() -> void:
	call_deferred("run")


func config_at(path: String) -> ConfigFile:
	var cfg := ConfigFile.new()
	check("saved config parses", cfg.load(path) == OK)
	return cfg


func run() -> void:
	var visible := Catalog.player_ids()
	check("basic stays first/default", visible[0] == Catalog.DEFAULT_ID)
	check("electric follows basic", Catalog.player_step(Catalog.DEFAULT_ID, 1) == "stik-electric-6s")
	check("backward wrap", Catalog.player_step(visible[0], -1) == visible[-1])
	check("multiple wraps", Catalog.player_step(visible[0], visible.size() * 3) == visible[0])
	check("historical alias canonicalizes", Catalog.is_player_selectable("skywalker-x8")
		and not visible.has("skywalker-x8") and Catalog.player_step("skywalker-x8", 0) == "moonrunner-x99")
	check("rotorcraft remains a stock choice", visible.has("xcell-60-research"))
	check("unknown stock ID is refused", not Catalog.is_player_selectable("missing") and Catalog.player_step("missing", 1).is_empty())
	for id: String in HIDDEN:
		check("hidden retains exact technical lookup: " + id, Catalog.has(id) and Catalog.can_fly(id)
			and not Catalog.is_player_selectable(id) and not visible.has(id)
			and Catalog.player_step(id, 1).is_empty() and Catalog.entry(id).id == id)
		for schema: int in [1, 6, 99]:
			var cfg := ConfigFile.new()
			cfg.set_value("meta", "schema", schema)
			cfg.set_value("flight", "aircraft", id)
			check("legacy fixture saves", cfg.save(PATH) == OK)
			var original := FileAccess.get_file_as_bytes(PATH)
			var prefs := Preferences.load_from(PATH)
			check("Home resolves hidden selection", Preferences.resolve_player_selection(prefs) == Catalog.DEFAULT_ID
				and Preferences.retained_aircraft(prefs) == id)
			check("loading performs no selection write", FileAccess.get_file_as_bytes(PATH) == original)
			prefs.language = "es"
			var error := Preferences.save_to(PATH, prefs)
			if schema > Preferences.SCHEMA:
				check("future schema protected", error == ERR_FILE_NO_PERMISSION
					and FileAccess.get_file_as_bytes(PATH) == original)
			else:
				check("unrelated save retains original ID", error == OK and config_at(PATH).get_value("flight", "aircraft") == id)
				check("restart resolves idempotently", Preferences.resolve_player_selection(Preferences.load_from(PATH)) == Catalog.DEFAULT_ID)
				check("failed explicit save retains marker", Preferences.save_to(PATH + "/missing.cfg", prefs, true) != OK
					and Preferences.retained_aircraft(prefs) == id)
				check("explicit choice commits after save", Preferences.save_to(PATH, prefs, true) == OK
					and Preferences.retained_aircraft(prefs).is_empty()
					and config_at(PATH).get_value("flight", "aircraft") == Catalog.DEFAULT_ID)
	# Deliberate publication failure on a disposable file proves the accepted bytes survive.
	DirAccess.remove_absolute(PATH)
	check("current-schema transaction fixture", Preferences.save_to(PATH, Preferences.DEFAULTS.duplicate(true)) == OK)
	var accepted := FileAccess.get_file_as_bytes(PATH)
	var next := ConfigFile.new()
	next.set_value("meta", "schema", 6)
	check("replacement failure is reported", PreferencesFile.save(PATH, next,
		func(_temporary: String, _destination: String) -> Error: return ERR_FILE_NO_PERMISSION) == ERR_FILE_NO_PERMISSION)
	check("replacement failure preserves bytes", FileAccess.get_file_as_bytes(PATH) == accepted)
	check("failure after destination removal is reported", PreferencesFile.save(PATH, next,
		func(_temporary: String, destination: String) -> Error:
			DirAccess.remove_absolute(destination)
			return ERR_FILE_CANT_WRITE) == ERR_FILE_CANT_WRITE)
	check("destructive Windows-style failure restores accepted bytes", FileAccess.get_file_as_bytes(PATH) == accepted)
	check("interrupted transaction fixture", DirAccess.copy_absolute(PATH, PATH + PreferencesFile.PREVIOUS_SUFFIX) == OK)
	DirAccess.remove_absolute(PATH)
	Preferences.load_from(PATH)
	check("load recovers interrupted publication", FileAccess.get_file_as_bytes(PATH) == accepted
		and not FileAccess.file_exists(PATH + PreferencesFile.PREVIOUS_SUFFIX))
	var partial := FileAccess.open(PATH + ".tmp-interrupted.previous", FileAccess.WRITE)
	partial.store_string("[meta]\nschema=6\n")
	partial.close()
	Preferences.load_from(PATH)
	check("an unpublished partial backup never replaces settings", FileAccess.get_file_as_bytes(PATH) == accepted)
	DirAccess.remove_absolute(PATH + ".tmp-interrupted.previous")
	check("first writer acquires profile lock", PreferencesFile._acquire(PATH) == OK)
	check("second writer cannot publish or recover first writer", PreferencesFile.save(PATH, next) == ERR_BUSY)
	var busy := Preferences.load_from(PATH)
	check("a reader cannot enter an active publication", not busy.writable and FileAccess.get_file_as_bytes(PATH) == accepted)
	PreferencesFile._release(PATH)
	var future := ConfigFile.new()
	future.set_value("meta", "schema", 99)
	future.set_value("ui", "language", "fr")
	check("future-schema recovery fixture", future.save(PATH) == OK)
	var future_bytes := FileAccess.get_file_as_bytes(PATH)
	var previous_file := FileAccess.open(PATH + PreferencesFile.PREVIOUS_SUFFIX, FileAccess.WRITE)
	previous_file.store_buffer(accepted)
	previous_file.close()
	var protected := Preferences.load_from(PATH)
	check("recovery protects newer settings and the prior copy", not protected.writable and protected.language == "fr"
		and FileAccess.get_file_as_bytes(PATH) == future_bytes
		and FileAccess.get_file_as_bytes(PATH + PreferencesFile.PREVIOUS_SUFFIX) == accepted)
	DirAccess.remove_absolute(PATH + PreferencesFile.PREVIOUS_SUFFIX)
	DirAccess.remove_absolute(PATH)
	# Actual shell flow: no programmatic or composed debug request may re-expose hidden stock.
	var seed := Preferences.DEFAULTS.duplicate(true)
	seed.aircraft = HIDDEN[0]
	check("hidden saved selection fixture", Preferences.save_to(PATH, seed) == OK)
	var ui := UiDriver.new(self)
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PATH
	app.update_check_url = ""
	root.add_child(app)
	await ui.settle()
	check("Home fallback is explained", app.home.aircraft_id == Catalog.DEFAULT_ID
		and app.home.stock_selection_notice.visible and app.home.stock_selection_notice.text.contains("61FX"))
	app.set_language("es")
	check("language save retains hidden selection", config_at(PATH).get_value("flight", "aircraft") == HIDDEN[0])
	var before: Dictionary = app.preferences.duplicate(true)
	var bridge := Bridge.new()
	bridge.app = app
	var rejected: Dictionary = bridge._cmd_setup({aircraft = HIDDEN[1], language = "fr", start = "airborne"})
	check("invalid composed setup changes nothing", not rejected.ok and app.preferences == before and app.home.aircraft_id == Catalog.DEFAULT_ID)
	rejected = bridge._cmd_fly({aircraft = HIDDEN[2], start = "airborne"})
	check("hidden Fly cannot launch previous aircraft", not rejected.ok and app.flight == null and app.preferences == before)
	check("programmatic hidden selection refused", not app.set_aircraft(HIDDEN[0]))
	check("explicit visible choice clears fallback after save", app.set_aircraft("stik-electric-6s")
		and Preferences.retained_aircraft(app.preferences).is_empty() and not app.home.stock_selection_notice.visible)
	check("electric defaults to finite pack", app.home.battery_mode == "pack")
	bridge.free()
	app.queue_free()
	await ui.settle()
	for suffix in ["", ".display", ".controllers", ".controllers.rollback", ".legacy_rc"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH + suffix))
	print("Stik stock selection: %d failed" % failed)
	quit(1 if failed else 0)
