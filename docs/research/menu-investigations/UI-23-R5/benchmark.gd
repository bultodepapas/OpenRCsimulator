extends SceneTree
const Preferences = preload("res://app_state/preferences.gd")
const DisplayPreferences = preload("res://app_state/display_preferences.gd")
const UiTheme = preload("res://ui/ui_theme.gd")
var theme_events := 0
var gradient_events := 0
var font_events := 0
var app: Node
var output := ""
func _initialize() -> void: run.call_deferred()
func settle(frames := 4) -> void:
	for frame in frames: await process_frame
func run() -> void:
	var baseline := "--baseline" in OS.get_cmdline_user_args()
	output = ProjectSettings.globalize_path("res://../tmp/menu-optimization/" + ("baseline" if baseline else "candidate") + ".json")
	root.size = Vector2i(1280,720)
	var prefs := Preferences.DEFAULTS.duplicate(true)
	prefs.first_flight_hint_seen = true
	var prefs_path := "user://test_menu_optimization.cfg"
	Preferences.save_to(prefs_path,prefs)
	DisplayPreferences.save_to(prefs_path + ".display",DisplayPreferences.DEFAULTS)
	app = load("res://../tmp/menu-optimization/baseline_root.gd" if baseline else "res://app_root.gd").new()
	app.user_args = PackedStringArray()
	app.preferences_path = prefs_path
	root.add_child(app)
	await settle(12)
	app.open_settings(app.home.settings_button)
	await settle(8)
	var settings: Node = app.screens.top()
	settings._show_category(2)
	await settle()
	app.home.theme_changed.connect(on_theme)
	settings._surface.theme_changed.connect(on_theme)
	var samples: Array = []
	for sample in 60:
		var started := Time.get_ticks_usec()
		settings._volume_slider.value = float(sample % 11) / 10.0
		samples.append(Time.get_ticks_usec() - started)
		await settle(2)
	var result := {"variant":"baseline" if baseline else "candidate","volume_handler_us":samples,"volume_theme_events":theme_events}
	app.queue_free()
	await settle(6)
	# Separate layout-only fixture: no preview/render workload is attributed to Home reflow.
	var home: Control = load("res://../tmp/menu-optimization/baseline_home.gd" if baseline else "res://ui/home.gd").new()
	root.add_child(home)
	await settle(8)
	for rect: TextureRect in [home._rail_scrim,home._top_scrim]:
		(rect.texture as GradientTexture2D).gradient.changed.connect(on_gradient)
	home.fly_button.theme_changed.connect(on_font)
	home._nav_buttons[0].theme_changed.connect(on_font)
	samples = []
	for sample in 60:
		var started := Time.get_ticks_usec()
		home._apply_responsive_layout()
		samples.append(Time.get_ticks_usec() - started)
		await settle(2)
	result.home_layout_handler_us = samples
	result.home_gradient_events = gradient_events
	result.home_font_events = font_events
	home.queue_free()
	await settle(6)
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("BENCH ",output," volume themes=",theme_events," gradient updates=",gradient_events," font updates=",font_events)
	quit()
func on_theme() -> void: theme_events += 1
func on_gradient() -> void: gradient_events += 1
func on_font() -> void: font_events += 1
