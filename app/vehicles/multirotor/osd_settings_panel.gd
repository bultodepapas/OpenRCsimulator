## DR-31c: the FPV quad's OSD settings, opened from the pause menu beside it like a flight controller's OSD tab:
## layout (Off, Race, Freestyle, Full, Custom), units, HD or analog style, crosshair style, and one check per element.
## Switching an element starts the Custom layout from the current set. It only edits the OSD configuration
## (osd_model.gd); the HUD applies and saves it.
extends PanelContainer

const Osd = preload("res://vehicles/multirotor/osd_model.gd")
const UiTheme = preload("res://ui/ui_theme.gd")

signal config_changed(config: Dictionary)
signal closed

var config := Osd.DEFAULTS.duplicate(true)
var title: Label
var layout_button: Button
var units_button: Button
var style_button: Button
var crosshair_button: Button
var elements_label: Label
var close_button: Button
## element id -> CheckBox
var checks := {}


func build(s: float) -> void:
	name = "OsdSettings"
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(round(6.0 * s)))
	add_child(box)
	title = Label.new()
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title.add_theme_font_size_override("font_size", int(round(24.0 * s)))
	box.add_child(title)
	var choices := GridContainer.new()
	choices.columns = 2
	choices.add_theme_constant_override("h_separation", int(round(8.0 * s)))
	choices.add_theme_constant_override("v_separation", int(round(6.0 * s)))
	box.add_child(choices)
	layout_button = _choice(choices, "OsdLayout", func() -> void: _cycle("layout", Osd.LAYOUTS), s)
	units_button = _choice(choices, "OsdUnits", func() -> void: _cycle("units", Osd.UNITS), s)
	style_button = _choice(choices, "OsdStyle", func() -> void: _cycle("style", Osd.STYLES), s)
	crosshair_button = _choice(choices, "OsdCrosshair", func() -> void: _cycle("crosshair", Osd.CROSSHAIRS), s)
	elements_label = Label.new()
	elements_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	elements_label.add_theme_font_size_override("font_size", int(round(16.0 * s)))
	elements_label.add_theme_color_override("font_color", UiTheme.TEXT_2)
	box.add_child(elements_label)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", int(round(14.0 * s)))
	grid.add_theme_constant_override("v_separation", 0)
	box.add_child(grid)
	for element: String in Osd.ELEMENTS:
		var check := CheckBox.new()
		check.name = "Element_" + element
		check.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		check.add_theme_font_size_override("font_size", int(round(15.0 * s)))
		check.toggled.connect(func(on: bool) -> void: _set_config(Osd.toggled(config, element, on)))
		grid.add_child(check)
		checks[element] = check
	close_button = Button.new()
	close_button.name = "Close"
	close_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	close_button.custom_minimum_size.y = 40.0 * s
	close_button.pressed.connect(func() -> void: closed.emit())
	box.add_child(close_button)
	refresh()


func _choice(parent: Container, node_name: String, callback: Callable, s: float) -> Button:
	var button := Button.new()
	button.name = node_name
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	button.custom_minimum_size = Vector2(230.0 * s, 40.0 * s)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _cycle(key: String, values: Array[String]) -> void:
	var next := config.duplicate(true)
	next[key] = Osd.next_in(values, str(config[key]))
	_set_config(next)


func _set_config(next: Dictionary) -> void:
	config = Osd.sanitize(next)
	refresh()
	config_changed.emit(config)


## Show `next` without emitting (the HUD changed it, e.g. with the O key).
func show_config(next: Dictionary) -> void:
	config = Osd.sanitize(next)
	refresh()


func refresh() -> void:
	if title == null:
		return
	title.text = tr("OSD settings")
	layout_button.text = tr("OSD layout: %s") % tr(str(Osd.LAYOUT_NAMES[config.layout]))
	units_button.text = tr("OSD units: %s") % tr(str(Osd.UNIT_NAMES[config.units]))
	style_button.text = tr("OSD style: %s") % tr(str(Osd.STYLE_NAMES[config.style]))
	crosshair_button.text = tr("Crosshair: %s") % tr(str(Osd.CROSSHAIR_NAMES[config.crosshair]))
	elements_label.text = tr("Elements (a change selects the Custom layout)")
	close_button.text = tr("Close")
	var shown := Osd.elements_of(config)
	for element: String in checks:
		var check: CheckBox = checks[element]
		check.text = tr(str(Osd.ELEMENT_NAMES[element]))
		check.set_pressed_no_signal(element in shown)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		refresh()
