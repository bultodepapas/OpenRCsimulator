# Home screen (MENU-PLAN §3, steps UI-01a/01c/01d/05): one column over the selected airplane (ui/home_scene.gd).
# Top to bottom: the name and build stage; the aircraft selector and what Fly starts (next to Fly); Fly; Language,
# Help and Quit; how to control. The aircraft come from app_state/aircraft_catalog.gd; a preview can be looked at but
# not flown (Fly is disabled and the card says why).
# Built in code with containers, so it reflows instead of using absolute positions. UI-06d-R1: the column never
# grows wider than its 440 px panel (long button texts wrap or clip) and scrolls when a long aircraft note or a
# translation needs more than the window's height; the first-run Home (Stik, default conditions) fits at 720p.
# Texts are English source
# strings: Labels and Buttons translate themselves when the locale changes (res://i18n/*.po); sentences built at
# runtime use tr() and are rebuilt on NOTIFICATION_TRANSLATION_CHANGED. Proper names are never translated.
extends "res://ui/screen.gd"

const Widgets := preload("res://ui/widgets.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const KeyCap := preload("res://ui/key_cap.gd")
const KeyLabels := preload("res://ui/key_labels.gd")
const Reference := preload("res://ui/controls_reference.gd")
const Preferences := preload("res://app_state/preferences.gd")
const Conditions := preload("res://render/world/conditions.gd")
const WeatherSettings := preload("res://physics/wind_config.gd")
const TimeOfDay := preload("res://environment/time_of_day_config.gd")
const TimeOfDayControls := preload("res://ui/time_of_day_controls.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")
const BuildInfo := preload("res://app_state/build_info.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const UpdateNotice := preload("res://ui/update_notice.gd")

## The Fly button was pressed (emitted once: further presses are ignored while the flight starts).
signal fly_requested
signal ground_vehicle_requested
signal workshop_requested(from: Control)
signal natural_random_requested(from: Control)
signal failures_requested(from: Control)
signal quit_requested
## The player asked for the next interface language (a Preferences.LANGUAGES code).
signal language_requested(code: String)
## The player asked for Help (it returns the focus to `from` when it closes).
signal help_requested(from: Control)
## The player asked to open controller setup (the owner restores focus to `from` when it closes).
signal controls_requested(from: Control)
## The player chose another aircraft (a catalog ID); the owner remembers it and calls set_aircraft().
signal aircraft_requested(id: String)
signal start_requested(choice: String)
## The player asked to edit draft flight conditions; closing the dialog returns focus to `from`.
signal weather_requested(from: Control)
## The player chose another FW Home preset; the owner rebuilds the backdrop and remembers it.
signal time_requested(preset: String)
## UI-16: the player pressed Download on the update notice (a trusted release page URL) or hid it (its tag).
signal update_download_requested(url: String)
signal update_hidden(tag: String)

const SIDEBAR_WIDTH := 440

## The catalog aircraft that Fly starts (set_aircraft() changes it).
var aircraft_id := Catalog.DEFAULT_ID
var start_choice: String = "airborne"
var runway_available: bool = true
var weather_config: Dictionary = WeatherSettings.defaults()
var failure_config: Dictionary = {"probability_percent": 0, "include_catastrophic": false, "notify": true}
var lighting_config: Dictionary = TimeOfDay.defaults()
var sky_config: Dictionary = SkyConfig.defaults()
var time_of_day: String = "day"
var start_button: Button

var fly_button: Button
var ground_vehicle_button: Button
var workshop_button: Button
var natural_random_button: Button
var failures_button: Button
var failure_summary_label: Label
var weather_button: Button
var time_button: Button
var language_button: Button
var help_button: Button
var quit_button: Button
var controls_button: Button
var control_label: Label
var controller_prompt_label: Label
var keys_legend: GridContainer
var note_label: Label
var previous_button: Button
var next_button: Button
var aircraft_count_label: Label
var aircraft_name_label: Label
var aircraft_summary_label: Label
var aircraft_status_label: Label
var aircraft_preview_label: Label
var limits_label: Label
## UI-16: the update card (ui/update_notice.gd), created the first time show_update() is called.
var update_notice: Control
var _fly_sent := false
## UI-06d-R1: frames before the column's scroll follows the keyboard focus (see _process).
var _settle_frames := 3
var _scroll: ScrollContainer
var _flight_device_name := ""
var _menu_device_name := ""
var _controller_state_received := false
var _legend_rows: Array = []


func _init() -> void:
	name = "Home"
	kind = Kind.SIDEBAR
	theme = UiTheme.build() # on this screen's top Control: Window.theme would not reach CanvasLayers
	var sidebar_style: StyleBoxFlat = theme.get_stylebox("panel", "Sidebar") as StyleBoxFlat
	sidebar_style.content_margin_top = 12
	sidebar_style.content_margin_bottom = 8
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sidebar := PanelContainer.new()
	sidebar.name = "Sidebar"
	sidebar.theme_type_variation = "Sidebar"
	sidebar.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	sidebar.custom_minimum_size.x = SIDEBAR_WIDTH
	add_child(sidebar)
	fade(SIDEBAR_WIDTH)
	# The column scrolls (wheel, or following the keyboard focus) when the card and the legend need more height than
	# the window gives; no bar is drawn. With room to spare the column fills the panel and its spacers work as before.
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.follow_focus = false # until the layout settles (_process): see _settle_frames
	sidebar.add_child(scroll)
	_scroll = scroll
	var column := VBoxContainer.new()
	column.name = "Column"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 0)
	scroll.add_child(column)

	var title := _label("OpenRC Simulator", "TitleLabel", false)
	title.add_theme_font_size_override("font_size", 32) # UI-06d-R1: the column's height budget at 720p
	column.add_child(title)
	var stage := HBoxContainer.new()
	stage.add_theme_constant_override("separation", 10)
	var badge := PanelContainer.new()
	badge.theme_type_variation = "Badge"
	badge.add_child(_label("ALPHA", "SectionLabel", false))
	stage.add_child(badge)
	# The build identity (UI-04a): the version an exported build carries, or "development build" from the source tree.
	var build := BuildInfo.current()
	var version_label := _label(build.label if build.source == "export" else "development build", "SecondaryLabel", build.source != "export")
	version_label.name = "Version"
	stage.add_child(version_label)
	column.add_child(stage)
	column.add_child(_spacer())

	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 8)
	var section := _label("NEXT FLIGHT", "SectionLabel")
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading.add_child(section)
	aircraft_count_label = _label("", "SecondaryLabel", false) # built with tr()
	aircraft_count_label.name = "AircraftCount"
	aircraft_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading.add_child(aircraft_count_label)
	previous_button = _arrow_button("PreviousAircraft", "left")
	previous_button.pressed.connect(func() -> void: aircraft_requested.emit(Catalog.step(aircraft_id, -1)))
	heading.add_child(previous_button)
	next_button = _arrow_button("NextAircraft", "right")
	next_button.pressed.connect(func() -> void: aircraft_requested.emit(Catalog.step(aircraft_id, 1)))
	heading.add_child(next_button)
	column.add_child(heading)
	column.add_child(_gap(4))
	var card := PanelContainer.new()
	card.name = "AircraftCard"
	card.theme_type_variation = "Card"
	var card_lines := VBoxContainer.new()
	card_lines.add_theme_constant_override("separation", 2)
	aircraft_name_label = _label("", "CardTitle", false) # a proper name: not auto-translated; set_aircraft() passes it through tr() for the one fictional name with a catalog entry (TT-06)
	aircraft_name_label.name = "AircraftName"
	aircraft_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART # long names and translations wrap, never widen the column
	card_lines.add_child(aircraft_name_label)
	aircraft_summary_label = _label("", "SecondaryLabel")
	aircraft_summary_label.name = "AircraftSummary"
	aircraft_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_lines.add_child(aircraft_summary_label)
	aircraft_status_label = _label("", "SecondaryLabel")
	aircraft_status_label.name = "AircraftStatus"
	aircraft_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_lines.add_child(aircraft_status_label)
	aircraft_preview_label = _label("", "SecondaryLabel")
	aircraft_preview_label.name = "AircraftPreviewState"
	aircraft_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	aircraft_preview_label.visible = false
	card_lines.add_child(aircraft_preview_label)
	card_lines.add_child(_label("Test field · Free flight", "SecondaryLabel"))
	limits_label = _label("Starts in the air. A crash restarts the flight.", "SecondaryLabel")
	limits_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_lines.add_child(limits_label)
	start_button = _button("", "")
	start_button.name = "StartChoice"
	# Long translated launch names wrap inside the card instead of widening the sidebar.
	start_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	start_button.pressed.connect(_cycle_start_choice)
	card_lines.add_child(start_button)
	card.add_child(card_lines)
	column.add_child(card)
	column.add_child(_gap(6))

	fly_button = _button("FLY", "PrimaryButton")
	fly_button.name = "Fly"
	fly_button.custom_minimum_size.y = 66
	fly_button.pressed.connect(_on_fly)
	var fly_row := HBoxContainer.new()
	fly_row.add_theme_constant_override("separation", 12)
	fly_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fly_row.add_child(fly_button)
	weather_button = _button("", "")
	weather_button.name = "Weather"
	weather_button.custom_minimum_size = Vector2(190, 66)
	weather_button.add_theme_font_size_override("font_size", 14) # three lines (title, wind, turbulence) within the Fly row
	# The summary wraps inside the button instead of widening the column (a Button's minimum width follows its text
	# unless it wraps or clips); the tooltip carries the complete conditions.
	weather_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	weather_button.clip_text = true
	weather_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	weather_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # the compact dynamic summary is built with tr()
	weather_button.pressed.connect(func() -> void: weather_requested.emit(weather_button))
	fly_row.add_child(weather_button)
	column.add_child(fly_row)
	workshop_button = _button("Workshop", "")
	workshop_button.name = "Workshop"
	workshop_button.add_theme_font_size_override("font_size", 16)
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var compact: StyleBoxFlat = theme.get_stylebox(state, "Button").duplicate()
		compact.content_margin_top = 2
		compact.content_margin_bottom = 2
		workshop_button.add_theme_stylebox_override(state, compact)
	workshop_button.pressed.connect(func() -> void: workshop_requested.emit(workshop_button))
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 8)
	workshop_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workshop_button.clip_text = true
	mode_row.add_child(workshop_button)
	natural_random_button = _button("Natural Random", "")
	natural_random_button.name = "NaturalRandom"
	natural_random_button.add_theme_font_size_override("font_size", 16)
	natural_random_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	natural_random_button.clip_text = true
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		natural_random_button.add_theme_stylebox_override(state, workshop_button.get_theme_stylebox(state))
	natural_random_button.pressed.connect(func() -> void: natural_random_requested.emit(natural_random_button))
	mode_row.add_child(natural_random_button)
	column.add_child(mode_row)
	var failures_row := HBoxContainer.new()
	failures_row.add_theme_constant_override("separation", 10)
	failures_button = _button("Failures", "")
	failures_button.name = "Failures"
	failures_button.custom_minimum_size.y = 40
	failures_button.pressed.connect(func() -> void: failures_requested.emit(failures_button))
	failures_row.add_child(failures_button)
	failure_summary_label = _label("", "SecondaryLabel", false)
	failure_summary_label.name = "FailureSummary"
	failure_summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	failure_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	failures_row.add_child(failure_summary_label)
	column.add_child(failures_row)
	ground_vehicle_button = _button("RC cars · Bisonte MT8", "")
	ground_vehicle_button.name = "GroundVehicles"
	ground_vehicle_button.add_theme_font_size_override("font_size", 16)
	ground_vehicle_button.custom_minimum_size = Vector2(260, 44)
	ground_vehicle_button.pressed.connect(func() -> void: ground_vehicle_requested.emit())
	# Family entry lives over the preview, so another vehicle does not lengthen the flight settings column.
	ground_vehicle_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ground_vehicle_button.offset_left = -284
	ground_vehicle_button.offset_right = -24
	ground_vehicle_button.offset_top = -68
	ground_vehicle_button.offset_bottom = -24
	add_child(ground_vehicle_button)
	column.add_child(_gap(6))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	language_button = _button("", "")
	language_button.name = "Language"
	language_button.add_theme_font_size_override("font_size", 16)
	language_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # built with tr(); language names stay as they are
	language_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	language_button.clip_text = true # takes what Help and Quit leave; a long language name is trimmed, never the column widened
	language_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	language_button.pressed.connect(func() -> void: language_requested.emit(next_language(current_language())))
	row.add_child(language_button)
	help_button = _button("Help", "")
	help_button.name = "Help"
	help_button.custom_minimum_size.x = 80
	help_button.pressed.connect(func() -> void: help_requested.emit(help_button))
	row.add_child(help_button)
	quit_button = _button("Quit", "")
	quit_button.name = "Quit"
	quit_button.custom_minimum_size.x = 72
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	row.add_child(quit_button)
	controls_button = _button("Controls", "")
	controls_button.name = "ControllerSettings"
	controls_button.custom_minimum_size.x = 78
	controls_button.clip_text = true
	controls_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	controls_button.tooltip_text = tr("Controller settings")
	controls_button.pressed.connect(func() -> void: controls_requested.emit(controls_button))
	row.add_child(controls_button)
	column.add_child(row)
	column.add_child(_gap(6))
	time_button = _button("", "")
	time_button.name = "TimeOfDay"
	time_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # built with tr()
	time_button.add_theme_font_size_override("font_size", 17) # "Hora del día: Atardecer, el tiempo pasa" fits the column
	time_button.clip_text = true
	time_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	time_button.pressed.connect(func() -> void: time_requested.emit(Conditions.next_home_choice(time_of_day)))
	column.add_child(time_button)
	note_label = _label("", "SecondaryLabel", false)
	note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_label.visible = false
	column.add_child(note_label)
	column.add_child(_spacer())

	column.add_child(_label("CONTROLS", "SectionLabel"))
	column.add_child(_gap(4))
	control_label = _label("", "SecondaryLabel", false) # built with tr()
	control_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(control_label)
	controller_prompt_label = _label("", "SecondaryLabel", false)
	controller_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controller_prompt_label.visible = false
	column.add_child(controller_prompt_label)
	column.add_child(_gap(4))
	keys_legend = GridContainer.new()
	keys_legend.columns = 2
	keys_legend.add_theme_constant_override("h_separation", 18)
	keys_legend.add_theme_constant_override("v_separation", 6)
	column.add_child(keys_legend)
	set_aircraft(aircraft_id) # the card is never empty; the owner sets the saved choice before adding Home


func _ready() -> void:
	# Down from Fly lands on the row's first button (geometry alone picks the middle one, Help). Left and right from
	# Fly reach the aircraft arrows, so changing airplane is two keys away from the start.
	fly_button.focus_neighbor_bottom = fly_button.get_path_to(workshop_button)
	workshop_button.focus_neighbor_top = workshop_button.get_path_to(fly_button)
	workshop_button.focus_neighbor_bottom = workshop_button.get_path_to(language_button)
	workshop_button.focus_neighbor_right = workshop_button.get_path_to(natural_random_button)
	natural_random_button.focus_neighbor_left = natural_random_button.get_path_to(workshop_button)
	natural_random_button.focus_neighbor_top = natural_random_button.get_path_to(weather_button)
	natural_random_button.focus_neighbor_bottom = natural_random_button.get_path_to(failures_button)
	failures_button.focus_neighbor_top = failures_button.get_path_to(natural_random_button)
	failures_button.focus_neighbor_bottom = failures_button.get_path_to(ground_vehicle_button)
	ground_vehicle_button.focus_neighbor_top = ground_vehicle_button.get_path_to(failures_button)
	ground_vehicle_button.focus_neighbor_bottom = ground_vehicle_button.get_path_to(language_button)
	fly_button.focus_neighbor_top = fly_button.get_path_to(start_button)
	start_button.focus_neighbor_bottom = start_button.get_path_to(fly_button)
	fly_button.focus_neighbor_left = fly_button.get_path_to(previous_button)
	fly_button.focus_neighbor_right = fly_button.get_path_to(next_button)
	weather_button.focus_neighbor_top = weather_button.get_path_to(fly_button)
	weather_button.focus_neighbor_bottom = weather_button.get_path_to(language_button)
	for button: Button in [language_button, help_button, quit_button]:
		button.focus_neighbor_top = button.get_path_to(fly_button)
		button.focus_neighbor_bottom = button.get_path_to(time_button)
	# Left and right along the row are explicit too (UI-06d-R1): inside the scrolling column, geometry alone picked the
	# full-width Time of day button as the right neighbour of Language when the window was small.
	language_button.focus_neighbor_right = language_button.get_path_to(help_button)
	help_button.focus_neighbor_left = help_button.get_path_to(language_button)
	help_button.focus_neighbor_right = help_button.get_path_to(quit_button)
	quit_button.focus_neighbor_left = quit_button.get_path_to(help_button)
	controls_button.focus_neighbor_top = controls_button.get_path_to(fly_button)
	controls_button.focus_neighbor_bottom = controls_button.get_path_to(time_button)
	quit_button.focus_neighbor_right = quit_button.get_path_to(controls_button)
	controls_button.focus_neighbor_left = controls_button.get_path_to(quit_button)
	controls_button.focus_neighbor_right = controls_button.get_path_to(language_button)
	time_button.focus_neighbor_top = time_button.get_path_to(language_button)
	_update_texts()
	# Keyboard focus starts on Fly, visible (on the next arrow when the saved aircraft is a preview: Fly is disabled).
	(fly_button if not fly_button.disabled else next_button).grab_focus.call_deferred()
	set_process(true)


## The column opens at the top. Wrapped labels settle over a few frames; following the first focus during those
## frames scrolled the title away with a long aircraft note (P-51, Avanti), so the scroll follows the focus only
## after they have passed. Then this node stops processing.
func _process(_delta: float) -> void:
	_settle_frames -= 1
	if _settle_frames > 0:
		return
	_scroll.scroll_vertical = 0
	_scroll.follow_focus = true
	set_process(false)


## Shows `id` on the card and enables Fly only for an aircraft that can fly. Unknown IDs fall back to the default
## (a stale preference must never leave Home without a valid airplane).
func set_aircraft(id: String) -> void:
	var entering_rotorcraft: bool=Catalog.is_rotorcraft(id) and not Catalog.is_rotorcraft(aircraft_id)
	aircraft_id = id if Catalog.has(id) else Catalog.DEFAULT_ID
	if entering_rotorcraft: start_choice="runway"
	set_start_choice(start_choice)
	var e := Catalog.entry(aircraft_id)
	var flyable := Catalog.can_fly(aircraft_id)
	var rotorcraft: bool = Catalog.is_rotorcraft(aircraft_id)
	var had_focus := fly_button.has_focus()
	_fill_legend()
	aircraft_name_label.text = tr(e.name) # proper names have no catalog entry and pass through; the Timber's fictional name has one
	aircraft_summary_label.text = e.summary
	aircraft_status_label.text = e.status_note
	limits_label.visible = flyable
	fly_button.disabled = _fly_sent or not flyable
	fly_button.focus_mode = Control.FOCUS_ALL if flyable else Control.FOCUS_NONE
	workshop_button.disabled = rotorcraft
	workshop_button.tooltip_text = tr("Aircraft Workshop is not available for this rotorcraft yet.") if rotorcraft else ""
	natural_random_button.disabled = rotorcraft
	natural_random_button.tooltip_text = tr("Natural Random currently supports airplanes only.") if rotorcraft else ""
	failures_button.disabled = rotorcraft
	failures_button.tooltip_text = tr("Failure practice currently supports airplanes only.") if rotorcraft else ""
	_update_failure_summary()
	if had_focus and not flyable:
		next_button.grab_focus()
	if is_node_ready():
		_update_texts()


## Kept separate from save/launch errors. Label auto-translation stays live.
func set_preview_state(state: String) -> void:
	aircraft_preview_label.text = "Loading aircraft preview…" if state == "loading" else "Aircraft preview could not be loaded."
	aircraft_preview_label.visible = state != "ready"


func set_start_choice(choice: String) -> void:
	if Catalog.is_rotorcraft(aircraft_id):
		start_choice = "airborne" if choice == "airborne" else "runway"
		start_button.disabled = false
		start_button.text = tr("Start: hover") if start_choice == "airborne" else tr("Start: helicopter pad")
		start_button.tooltip_text = tr("Choose a stopped rotor on the pad or a trimmed practice hover.")
		limits_label.text = tr("Experimental helicopter. On the pad: arm, release hold, wait for RPM, then raise collective.")
		return
	var supported: bool = FlightSession.runway_aircraft_supported(aircraft_id) and runway_available
	var half_power: bool = FlightSession.half_power_start_supported(aircraft_id)
	start_choice = "runway" if supported and choice == "runway" else "airborne"
	if half_power and choice == FlightSession.START_HALF_POWER:
		start_choice = FlightSession.START_HALF_POWER
	start_button.disabled = not supported and not half_power
	start_button.text = "Start: runway (experimental)" if start_choice == "runway" else "Start: in the air"
	limits_label.text = "Starts on the runway. Experimental ground handling." if start_choice == "runway" else "Starts in the air. A crash restarts the flight."
	if start_choice == FlightSession.START_HALF_POWER:
		start_button.text = "Start: in the air at 50% throttle"
		limits_label.text = "Starts in level flight at 50% throttle. Trim stays fixed while you fly."


func _cycle_start_choice() -> void:
	if Catalog.is_rotorcraft(aircraft_id):
		start_requested.emit("runway" if start_choice == "airborne" else "airborne")
		return
	var choices: Array[String] = ["airborne"]
	if FlightSession.runway_aircraft_supported(aircraft_id) and runway_available:
		choices.append("runway")
	if FlightSession.half_power_start_supported(aircraft_id):
		choices.append(FlightSession.START_HALF_POWER)
	start_requested.emit(choices[(choices.find(start_choice) + 1) % choices.size()])


## Keeps only a complete validated config. A corrupt preference can never stop Home from opening.
func set_weather_config(raw: Variant) -> void:
	var checked := WeatherSettings.validate(raw)
	weather_config = checked.config.duplicate(true) if checked.ok else WeatherSettings.defaults()
	if is_node_ready():
		_update_weather_text()


## Keeps a complete validated lighting selection for the Home summary and flight handoff.
func set_sky_config(raw: Variant) -> void:
	var checked: Dictionary = SkyConfig.validate(raw)
	sky_config = checked.config if checked.ok else SkyConfig.defaults()
	if is_node_ready():
		_update_weather_text()


func set_lighting_config(raw: Variant) -> void:
	var checked: Dictionary = TimeOfDay.validate(raw)
	lighting_config = checked.config.duplicate(true) if checked.get("ok", false) else TimeOfDay.defaults()
	if is_node_ready():
		_update_weather_text()


## Shows the FW preset that Home and the next flight will use; unknown values fall back to the fixed daytime world.
func set_time_of_day(preset: String) -> void:
	time_of_day = preset if Conditions.HOME_CHOICES.has(preset) else "day"
	if is_node_ready():
		_update_texts()


## A rejected launch leaves the same usable Home, including keyboard focus.
func reject_start(message: String) -> void:
	_fly_sent = false
	set_aircraft(aircraft_id)
	set_note(message)
	fly_button.grab_focus()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		set_start_choice(start_choice) # Rotorcraft launch labels are translated when assigned.
		_update_texts()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and is_node_ready():
		_fill_legend() # the player may have switched keyboard layout meanwhile (no engine signal for it, research 25)


## The keyboard legend from the shared table (ui/controls_reference.gd), keys named as the current layout prints them.
func _fill_legend(mapper := Callable()) -> void:
	# Resolve physical labels on every request, including focus regain after a layout change.
	# Keep only strings, never a mapper or detached controls. Translation of action Labels stays live.
	var rows: Array = []
	var vehicle_type := Reference.ROTORCRAFT if Catalog.is_rotorcraft(aircraft_id) else Reference.AIRPLANE
	for entry in Reference.flight_table(vehicle_type):
		var keys := PackedStringArray()
		for key in entry[0]:
			keys.append(KeyCap.ARROW_KEYS[key] if KeyCap.ARROW_KEYS.has(key) else KeyLabels.label(key, mapper))
		rows.append([keys, entry[1]])
	if rows == _legend_rows:
		return
	_legend_rows = rows
	for c in keys_legend.get_children():
		keys_legend.remove_child(c)
		c.queue_free()
	for row in rows:
		var caps := HBoxContainer.new()
		caps.add_theme_constant_override("separation", 4)
		for key: String in row[0]:
			caps.add_child(KeyCap.make(key))
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 10)
		pair.add_child(caps)
		pair.add_child(_label(row[1], "SecondaryLabel"))
		keys_legend.add_child(pair)


## A one-line message under the buttons (e.g. a settings file that could not be saved); "" hides it.
func set_note(text: String) -> void:
	note_label.text = text
	note_label.visible = text != ""


## Displays the explicitly selected flight and menu devices. Empty names mean keyboard/no controller.
func set_controller_devices(flight_name: String, menu_name: String) -> void:
	_flight_device_name = flight_name.strip_edges()
	_menu_device_name = menu_name.strip_edges()
	_controller_state_received = true
	_update_control()


## Shows the completed flight's failure outcome independently of the in-flight notification preference.
func set_failure_debrief(status: Dictionary) -> void:
	var message := failure_debrief_text(status)
	if message.is_empty():
		return
	if not note_label.text.is_empty():
		message = note_label.text + " · " + message
	set_note(message)


func failure_debrief_text(status: Dictionary) -> String:
	if bool(status.get("active", false)):
		var label := str(status.get("label", ""))
		return tr("Last flight: %s") % tr(label) if not label.is_empty() else tr("Last flight: a failure activated.")
	if bool(status.get("selected", false)):
		return tr("Flight ended before the scheduled failure.")
	if bool(status.get("enabled", false)):
		return tr("No failure was assigned to the last flight.")
	return ""


## The checked next-flight preference is shown beside the Home entry; it never changes the active flight.
func set_failure_config(config: Dictionary) -> void:
	failure_config = config.duplicate(true)
	if is_node_ready():
		_update_failure_summary()


func _update_failure_summary() -> void:
	if failure_summary_label == null:
		return
	if Catalog.is_rotorcraft(aircraft_id):
		failure_summary_label.text = tr("Airplanes only")
		return
	var probability := clampi(int(failure_config.get("probability_percent", 0)), 0, 100)
	if probability == 0:
		failure_summary_label.text = tr("Off")
	elif bool(failure_config.get("include_catastrophic", false)):
		failure_summary_label.text = tr("%d%% · Catastrophic enabled") % probability
	else:
		failure_summary_label.text = tr("%d%% · Standard") % probability


## UI-16: a small card at the top right over the backdrop (outside the column, so nothing moves) saying that the
## release in `info` (app_state/update_check.gd notice) is published. It never takes the focus from Fly.
func show_update(info: Dictionary) -> void:
	if update_notice == null:
		update_notice = UpdateNotice.new()
		update_notice.download_requested.connect(func(url: String) -> void: update_download_requested.emit(url))
		update_notice.hide_requested.connect(_on_update_hidden)
		add_child(update_notice)
	update_notice.show_release(info)


func hide_update() -> void:
	if update_notice != null:
		update_notice.visible = false


## Hide leaves no focused control behind: the keyboard goes back to Fly (or the next arrow for a preview).
func _on_update_hidden(tag: String) -> void:
	update_hidden.emit(tag)
	(fly_button if not fly_button.disabled else next_button).grab_focus()


## The interface language in use, as a Preferences.LANGUAGES code ("en" when the locale is not one of ours).
static func current_language() -> String:
	var code := TranslationServer.get_locale().get_slice("_", 0)
	return code if Preferences.LANGUAGES.has(code) else "en"


static func next_language(code: String) -> String:
	var codes: Array = Preferences.LANGUAGES.keys()
	return codes[(codes.find(code) + 1) % codes.size()]


func _update_texts() -> void:
	language_button.text = tr("Language: %s") % Preferences.LANGUAGES[current_language()]
	time_button.text = tr("Time of day: %s") % tr(Conditions.HOME_LABELS[time_of_day])
	aircraft_count_label.text = tr("Aircraft %d of %d") % [Catalog.ids().find(aircraft_id) + 1, Catalog.ids().size()]
	previous_button.tooltip_text = tr("Previous aircraft")
	next_button.tooltip_text = tr("Next aircraft")
	_update_weather_text()
	_update_failure_summary()
	_update_control()


func _update_weather_text() -> void:
	if weather_button == null:
		return
	var parts := PackedStringArray()
	var speed := float(weather_config.speed_mps)
	var gust := float(weather_config.gust_mps)
	var gust_up := float(weather_config.gust_up_mps)
	var turbulence := WeatherSettings.has_turbulence(weather_config)
	var summary := tr("Calm")
	if speed > 0.0:
		var wind_text := tr("%s m/s from %03.0f°") % [String.num(speed, 1), float(weather_config.from_deg)]
		parts.append(wind_text)
		summary = tr("%s m/s · %03.0f°") % [String.num(speed, 1), float(weather_config.from_deg)]
	if gust > 0.0:
		parts.append(tr("gust %s m/s") % String.num(gust, 1))
		if speed == 0.0:
			summary = tr("Gust %s m/s") % String.num(gust, 1)
		else:
			summary += " +%s" % String.num(gust, 1)
	if gust_up != 0.0:
		parts.append(tr("up %s m/s") % String.num(gust_up, 1))
		if speed == 0.0 and gust == 0.0:
			if gust_up > 0.0:
				summary = tr("Updraft %s m/s") % String.num(gust_up, 1)
			else:
				summary = tr("Downdraft %s m/s") % String.num(absf(gust_up), 1)
	if turbulence:
		var rms: Array = weather_config.turbulence_rms_mps
		parts.append(tr("Turbulence RMS N/E/Up: %s / %s / %s m/s; tau %s s; seed %s") % [
			String.num(float(rms[0]), 1), String.num(float(rms[1]), 1), String.num(float(rms[2]), 1),
			String.num(float(weather_config.turbulence_tau_s), 1), str(int(weather_config.turbulence_seed)),
		])
		if speed == 0.0 and gust == 0.0 and gust_up == 0.0:
			summary = tr("Turbulence")
		else:
			summary += " + " + tr("Turbulence")
	if weather_config.get("format", "") in [WeatherSettings.ATMOSPHERE_FORMAT, WeatherSettings.COLUMN_FORMAT]:
		if WeatherSettings.has_vertical_atmosphere(weather_config):
			var column_air: Dictionary = WeatherSettings.atmosphere(weather_config)
			if column_air.get("ok", false):
				var atmosphere_summary: String = tr("Standard atmosphere")
				parts.append(tr("Standard ISA at field %s m · density %s kg/m³") % [
					String.num(float(weather_config.field_elevation_m), 1),
					String.num(float(column_air.rho_kgm3), 3),
				])
				if speed == 0.0 and gust == 0.0 and gust_up == 0.0 and not turbulence:
					summary = atmosphere_summary
				else:
					summary += " + " + atmosphere_summary
		elif WeatherSettings.has_atmosphere(weather_config):
			var air: Dictionary = WeatherSettings.atmosphere(weather_config)
			if air.get("ok", false):
				var atmosphere_summary: String = tr("Thin air") if float(air.rho_kgm3) < 1.225 else tr("Custom air")
				parts.append(tr("Field %s m · %s °C · QNH %s hPa · RH %s%% · density %s kg/m³ · density altitude %s m") % [
					String.num(float(weather_config.field_elevation_m), 1),
					String.num(float(weather_config.temperature_c), 1),
					String.num(float(weather_config.qnh_hpa), 1),
					String.num(float(weather_config.relative_humidity_pct), 0),
					String.num(float(air.rho_kgm3), 3),
					String.num(float(air.density_altitude_m), 0),
				])
				if speed == 0.0 and gust == 0.0 and gust_up == 0.0 and not turbulence:
					summary = atmosphere_summary
				else:
					summary += " + " + atmosphere_summary
		else:
			parts.append(tr("Reference air · fixed density 1.225 kg/m³"))
			if speed == 0.0 and gust == 0.0 and gust_up == 0.0 and not turbulence:
				summary = tr("Reference air")
			else:
				summary += " + " + tr("Reference air")
	var lighting_summary: String = TimeOfDayControls.summary_text(lighting_config)
	var lighting_brief: String = TimeOfDayControls.compact_summary_text(lighting_config)
	if lighting_config.mode == "legacy":
		lighting_summary = tr(Conditions.HOME_LABELS[time_of_day])
		lighting_brief = "" # the Time of day button right below says it; repeating it only widened the column
	var sky_label: String = tr(SkyConfig.summary(sky_config))
	weather_button.text = "%s · %s\n%s" % [tr("Weather"), sky_label, summary if lighting_brief == "" else "%s · %s" % [summary, lighting_brief]]
	weather_button.clip_text = true
	var weather_help: String = tr("Uniform wind and repeating gusts with optional seeded turbulence. Field atmosphere sets modeled air density.")
	var standard_column_active: bool = WeatherSettings.has_vertical_atmosphere(weather_config)
	if standard_column_active:
		weather_help += "\n" + tr("Standard dry ISA density varies with geometric altitude from −500 to 11,000 m. This is a reference profile, not measured weather.")
	var helicopter_weather_eligible: bool = not turbulence and not standard_column_active
	if Catalog.is_rotorcraft(aircraft_id):
		if not helicopter_weather_eligible:
			var unsupported: PackedStringArray = []
			if turbulence:
				unsupported.append(tr("Turbulence"))
			if standard_column_active:
				unsupported.append(tr("Standard atmosphere by altitude"))
			weather_help = tr("Helicopter weather does not support %s. Use steady wind and repeating gusts.") % ", ".join(unsupported)
		else:
			weather_help = tr("Helicopter weather uses steady wind and repeating gusts. Turbulence and altitude-varying atmosphere are not integrated yet.")
	weather_button.tooltip_text = "%s\n%s\n%s" % [
		weather_help,
		" · ".join(parts) if not parts.is_empty() else tr("Calm"),
		"%s · %s" % [sky_label, lighting_summary],
	]


## Show the explicit flight selection. A connected device alone never takes control.
func _update_control() -> void:
	keys_legend.visible = _flight_device_name.is_empty()
	if _flight_device_name.is_empty():
		control_label.text = tr("Flight: keyboard (no controller selected).")
	else:
		control_label.text = tr("Flight controller: %s. Follow the arming prompt.") % _flight_device_name
	if _menu_device_name.is_empty():
		controller_prompt_label.text = tr("Press A / Cross to claim gamepad menu controls.")
	else:
		controller_prompt_label.text = tr("Menu controller: %s") % _menu_device_name
	controller_prompt_label.visible = _controller_state_received


func _on_fly() -> void:
	if _fly_sent or not Catalog.can_fly(aircraft_id):
		return
	_fly_sent = true
	fly_button.disabled = true
	fly_requested.emit()


static func _label(text: String, variation: String, translate := true) -> Label:
	return Widgets.label(text, variation, false, translate)


static func _button(text: String, variation: String) -> Button:
	return Widgets.button(text, variation)


## A small square button with a drawn arrow (the default font has no arrow glyphs, see ui/key_cap.gd).
static func _arrow_button(button_name: String, direction: String) -> Button:
	var b := _button("", "")
	b.name = button_name
	b.custom_minimum_size = Vector2(44, 36)
	var arrow: Control = KeyCap.Arrow.new()
	arrow.direction = direction
	arrow.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(arrow)
	return b


static func _gap(height: int) -> Control:
	return Widgets.gap(height)


static func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c
