# Entry point (MENU-PLAN §8/§9, steps UI-01a/01b/01d). It decides the route before loading any menu:
# - user arguments after `--` (--trace, --capture, --frametimes, --scripted, --inspect, --quick-flight, ...):
#   the flight scene starts at once, exactly as before, in English, without reading or writing preferences;
# - no user arguments: the Home screen in the saved language (English by default, whatever the OS locale);
#   Fly creates the flight scene, Quit closes the app.
# The flight lives under this node, so later steps (UI-03) can free it and show Home again.
extends Node

const Home := preload("res://ui/home.gd")
const UiInput := preload("res://ui/ui_input.gd")
const Preferences := preload("res://app_state/preferences.gd")
const FLIGHT_SCENE := "res://main.tscn"

## Set before adding the node to change the route or the settings file (tests never touch the player's files).
var user_args: PackedStringArray = OS.get_cmdline_user_args()
var preferences_path := Preferences.DEFAULT_PATH
var preferences := {}
var home: Control
var flight: Node


func _ready() -> void:
	UiInput.isolate_joypads() # before any menu exists (UI-01b): radio sticks never move the focus
	if wants_direct_flight(user_args):
		# The engine starts in the OS locale (es_ES on a Spanish system): automation is always English.
		TranslationServer.set_locale("en")
		start_flight()
		return
	preferences = Preferences.load_from(preferences_path)
	if preferences.note != "":
		print("settings: ", preferences.note)
	TranslationServer.set_locale(preferences.language)
	show_home()


## Any user argument selects the technical/direct route (`-- --quick-flight` is the documented shortcut).
static func wants_direct_flight(args: PackedStringArray) -> bool:
	return not args.is_empty()


func show_home() -> void:
	home = Home.new()
	home.fly_requested.connect(start_flight)
	home.quit_requested.connect(func() -> void: get_tree().quit())
	home.language_requested.connect(set_language)
	add_child(home)


## Applies a language at once and remembers it. A failed save keeps the language for this session and says so.
func set_language(code: String) -> void:
	if not Preferences.LANGUAGES.has(code):
		return
	TranslationServer.set_locale(code)
	preferences.language = code
	var err := Preferences.save_to(preferences_path, preferences)
	if home != null:
		home.set_note("" if err == OK else tr("Could not save settings (error %d).") % err)


## Creates the flight scene in this same frame (captures and traces stay frame-for-frame identical) and frees Home.
func start_flight() -> void:
	if flight != null:
		return
	if home != null:
		home.queue_free()
		home = null
	flight = load(FLIGHT_SCENE).instantiate()
	add_child(flight)
