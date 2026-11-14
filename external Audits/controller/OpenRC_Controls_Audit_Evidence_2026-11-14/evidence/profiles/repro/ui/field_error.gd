# L5: no fallback field and no flight on invalid data. Automation must fail, interactive users get a reason.
extends CanvasLayer

const UiTheme = preload("res://ui/ui_theme.gd")

var quit_button: Button


static func report(parent: Node, errors: PackedStringArray) -> void:
	parent.set_process(false)
	parent.set_process_unhandled_input(false)
	printerr("FIELD DATA INVALID: ", "; ".join(errors))
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().is_empty():
		parent.get_tree().quit(1)
	else:
		parent.add_child(new(errors))


func _init(errors: PackedStringArray = PackedStringArray()) -> void:
	name = "FieldError"
	layer = 20
	var screen: PanelContainer = PanelContainer.new()
	screen.theme = UiTheme.build()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	screen.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	var title: Label = Label.new()
	title.text = "The field could not be loaded."
	title.theme_type_variation = "TitleLabel"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title)
	var explanation: Label = Label.new()
	explanation.text = "Flight is unavailable. Restore the field data and restart the simulator."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(explanation)
	var details: TextEdit = TextEdit.new()
	details.name = "Details"
	details.text = "\n".join(errors)
	details.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	details.editable = false
	details.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(details)
	quit_button = Button.new()
	quit_button.name = "Quit"
	quit_button.text = "Quit"
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	column.add_child(quit_button)


func _ready() -> void:
	quit_button.grab_focus.call_deferred()
