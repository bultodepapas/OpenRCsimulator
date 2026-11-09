extends CanvasLayer
## UI-12-GP-02: prove menu controls on one connection without saving or changing roles.

const Screen := preload("res://ui/screen.gd")
const Widgets := preload("res://ui/widgets.gd")
const RadioMenu := preload("res://input/radio_menu.gd")

signal completed(profile: Dictionary)
signal cancelled(reason: String)

var read_axis: Callable = Input.get_joy_axis
var read_button: Callable = Input.is_joy_button_pressed
var use_button: Button
var _registry: Object
var _device_id := -1
var _generation := 0
var _profile: Dictionary = {}
var _challenge: RefCounted
var _surface: Control
var _prompt: Label
var _progress: Label
var _error: Label
var _done := false
var _finished := false

func _init() -> void:
	name = "RadioMenuSetup"
	layer = 13
	_surface = Screen.mount(self)
	_surface.escape_before_gui = true
	_surface.close_requested.connect(request_close)
	_surface.dim(0.45)
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	card.custom_minimum_size.x = 640.0
	_surface.center(24.0).add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	card.add_child(column)
	column.add_child(Widgets.label("Verify radio menus", "TitleLabel"))
	column.add_child(Widgets.label("Use the calibrated roll and pitch controls for menus. Throttle never moves the menu. Follow each step, then Save controller settings to enable the radio.", "SecondaryLabel", true))
	_progress = Widgets.label("", "SectionLabel", true)
	column.add_child(_progress)
	_prompt = Widgets.label("", "", true)
	_prompt.custom_minimum_size.x = 560.0
	column.add_child(_prompt)
	_error = Widgets.label("", "ErrorLabel", true)
	column.add_child(_error)
	var row := Widgets.button_row()
	column.add_child(row)
	var cancel := Widgets.button("Cancel", "QuietButton", "CancelRadioMenus")
	cancel.pressed.connect(request_close)
	row.add_child(cancel)
	use_button = Widgets.button("Use verified menu controls", "PrimaryButton", "UseRadioMenus")
	use_button.disabled = true
	use_button.pressed.connect(_use_verified)
	row.add_child(use_button)

func configure(registry: Object, id: int, profile: Dictionary) -> bool:
	_registry = registry
	_device_id = id
	_generation = int(registry.connection_generation(id))
	_profile = profile.duplicate(true)
	if not _connection_current() or not RadioMenu.is_verified(RadioMenu.verified_profile(profile)):
		return false
	_challenge = RadioMenu.verification(profile)
	_prompt.text = tr(_challenge.instruction())
	return true

func _ready() -> void:
	_registry.devices_changed.connect(_check_connection)
	use_button.get_parent().get_child(0).grab_focus()

func _connection_current() -> bool:
	return _registry != null and _device_id >= 0 and _generation > 0 \
		and bool(_registry.device_for_id(_device_id).get("connected", false)) \
		and int(_registry.connection_generation(_device_id)) == _generation

func _check_connection() -> bool:
	if _finished: return false
	if _connection_current(): return true
	_cancel(tr("The radio connection changed. Menu verification was cancelled; the draft is unchanged."))
	return false

func owns_controller_event(event: InputEvent) -> bool:
	return not _finished and (event is InputEventJoypadButton or event is InputEventJoypadMotion) and event.device == _device_id

func _input(event: InputEvent) -> void:
	if owns_controller_event(event): get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if is_inside_tree() and what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		_cancel(tr("Menu verification was cancelled because the application lost focus. The draft is unchanged."))

func _process(delta: float) -> void:
	if _finished or _done or not _check_connection(): return
	var axes := PackedFloat64Array()
	for axis: int in RadioMenu.AXES:
		var value: Variant = read_axis.call(_device_id, axis)
		if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value)) or absf(float(value)) > 1.0:
			_cancel(tr("The radio returned invalid input. Menu verification was cancelled; the draft is unchanged."))
			return
		axes.append(float(value))
	var buttons := {}
	for action: String in RadioMenu.COMMANDS:
		var binding: Dictionary = _profile.actions[action]
		if binding.get("type", "") == "button":
			var value: Variant = read_button.call(_device_id, int(binding.button))
			if typeof(value) != TYPE_BOOL:
				_cancel(tr("The radio returned invalid input. Menu verification was cancelled; the draft is unchanged."))
				return
			buttons[int(binding.button)] = value
	var result: Dictionary = _challenge.sample(axes, buttons, delta)
	if not str(result.get("error", "")).is_empty():
		_cancel(tr(str(result.error)))
		return
	_progress.text = tr("Step %d of %d") % [int(result.get("index", 0)) + 1, int(result.get("total", 1))]
	_prompt.text = tr(_challenge.instruction())
	_done = bool(result.get("done", false))
	use_button.disabled = not _done
	if _done:
		_progress.text = tr("Radio menu controls verified")
		_prompt.text = tr("Choose Use verified menu controls, then Save. Cancel keeps your previous controller settings.")
		use_button.grab_focus()

func _use_verified() -> void:
	if not _done or not _check_connection(): return
	if not _challenge.matches(_profile): return
	var candidate := RadioMenu.verified_profile(_profile)
	if candidate.is_empty(): return
	_finished = true
	completed.emit(candidate)

func request_close() -> void:
	_cancel(tr("Menu verification cancelled. The draft is unchanged."))

func _cancel(reason: String) -> void:
	if _finished: return
	_finished = true
	cancelled.emit(reason)
