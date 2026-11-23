## TELEM-03: the telemetry notice. "consent" is the first-launch choice: Enable is visibly recommended, but only
## pressing that telemetry-specific button grants it; Continue without telemetry, Esc/Back and closing all decline.
## Both choices stay disabled until every key/button is released and a short delay has passed, so input held from
## the intro or another menu can never answer. "notice" shows the full privacy notice and "preview" the exact data
## waiting in memory; both only close. Copy: docs/plans/telemetry/consent.md.
extends CanvasLayer

const Screen := preload("res://ui/screen.gd")
const ScreenTheme := preload("res://ui/ui_theme.gd")
const Widgets := preload("res://ui/widgets.gd")
const MenuInput := preload("res://ui/ui_input.gd")

## Consent mode only: true for the Enable button, false for every way of declining.
signal chosen(enabled: bool)
## Consent mode: "notice" or "preview" opened on top of this screen.
signal info_requested(kind: String)
signal closed

const ARM_DELAY_MSEC := 600
const SENT := "If you choose Enable, we will send performance summaries such as FPS and frame-time ranges, broad CPU/GPU and memory categories, operating system, graphics renderer and API, resolution range, VSync/frame-rate cap, whether graphics settings are customized, and the built-in aircraft and activities you use. We also send the broad input method, activity duration and outcome, whether the flight physics ran on the fast native engine or the slower fallback, supported takeoff/landing and model-aircraft crash counts, and fixed categories of software errors. Model-aircraft crash counts are not application crash dumps. We use these reports to find slow configurations and improve the simulator."
const NOT_SENT := "We do not send your name, email, account, device serial number, custom aircraft names, saved flight history, control inputs, files, screenshots or raw logs. A temporary random session code groups reports. It is not saved on this device and a new code is created at launch; the receiving service retains it for at most 48 hours after receipt. Our receiving service processes your IP to receive the connection, but the analytics database does not store it. Hardware and session data can still be distinctive, so we do not promise complete anonymity."
const WHERE := "Reports go to the receiving service operated by %s. Only reviewed summaries may be published on GitHub. You can inspect the data and turn telemetry off at any time in Settings → Interface. The simulator works the same with telemetry off."
const RETENTION := "Pending data stays only in memory, for at most ten minutes. The session code changes at least every four hours and at the UTC day boundary. Raw reports, temporary codes and duplicate-check keys expire within 48 hours of receipt. Summary tables without codes expire within 180 days. Reviewed public summaries on GitHub can remain indefinitely. Any temporary IP-based abuse protection is kept only in memory, for at most 15 minutes. Telemetry is separate from update checks, which you can turn off on the same Settings page."
const OPERATOR := "Operator: %s · Contact: %s · Receiving service: %s"

var mode := "consent"
var enable_button: Button
var decline_button: Button
var close_button: Button
var _screen: Control
var _panel: PanelContainer
var _armed := false
var _opened_msec := 0
var _release: Dictionary
var _pending_data: Label
var _pending_empty: Label
var _texts: Array[Dictionary] = []
var _answered := false
var _notice_scroll: ScrollContainer


## `release` is TelemetryRelease.current() (operator, contact, endpoint); `preview` is the pending data text.
func _init(screen_mode := "consent", release: Dictionary = {}, preview := "") -> void:
	mode = screen_mode if screen_mode in ["consent", "notice", "preview"] else "notice"
	_release = release
	name = "TelemetryConsent" if mode == "consent" else "TelemetryInfo"
	layer = 12
	_screen = Screen.mount(self, "Screen")
	_screen.escape_before_gui = true
	_screen.focus_fallback = _focus_initial
	_screen.close_requested.connect(_on_close_requested)
	_screen.dim(0.6)
	var center: CenterContainer = _screen.center(24.0)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = "Sidebar"
	center.add_child(_panel)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 12)
	_panel.add_child(shell)
	var scroll := ScrollContainer.new()
	scroll.name = "NoticeScroll"
	# The neutral starting focus of the consent notice: Enter/A on the text does nothing, so a reflexive press can
	# neither grant nor decline; the player moves to a choice deliberately.
	scroll.focus_mode = Control.FOCUS_ALL
	_notice_scroll = scroll
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)
	match mode:
		"consent":
			# Everything but the two choices scrolls (title included), so both choices stay on screen and the notice
			# keeps room even at 200 % text in a 960×540 window.
			shell.add_child(scroll)
			body.add_child(_text("Help improve OpenRC Simulator", "TitleLabel"))
			body.add_child(_text("Recommended: share technical telemetry.", ""))
			for source: String in [SENT, NOT_SENT]:
				body.add_child(_text(source, "SecondaryLabel"))
			body.add_child(_text(WHERE, "SecondaryLabel", [_operator()]))
			var links := Widgets.button_row()
			var preview_button := _choice("See exactly what we send", "QuietButton", "TelemetryPreview")
			preview_button.pressed.connect(func() -> void: info_requested.emit("preview"))
			links.add_child(preview_button)
			var notice_button := _choice("Privacy notice", "QuietButton", "TelemetryNotice")
			notice_button.pressed.connect(func() -> void: info_requested.emit("notice"))
			links.add_child(notice_button)
			body.add_child(links)
			var actions := Widgets.button_row()
			decline_button = _choice("Continue without telemetry", "", "TelemetryDecline")
			decline_button.pressed.connect(_answer.bind(false))
			actions.add_child(decline_button)
			enable_button = _choice("Enable telemetry and continue", "SettingsAction", "TelemetryEnable")
			enable_button.pressed.connect(_answer.bind(true))
			actions.add_child(enable_button)
			shell.add_child(actions)
			enable_button.disabled = true
			decline_button.disabled = true
			set_process(true)
		"notice":
			shell.add_child(_text("Privacy notice", "TitleLabel"))
			shell.add_child(scroll)
			for source: String in [SENT, NOT_SENT]:
				body.add_child(_text(source, "SecondaryLabel"))
			body.add_child(_text(WHERE, "SecondaryLabel", [_operator()]))
			body.add_child(_text(RETENTION, "SecondaryLabel"))
			body.add_child(_text(OPERATOR, "SecondaryLabel", [_operator(), str(_release.get("contact", "-")),
				_origin(str(_release.get("endpoint", "")))]))
		"preview":
			shell.add_child(_text("Data waiting to be sent", "TitleLabel"))
			shell.add_child(scroll)
			_pending_empty = _text("Nothing is waiting to be sent. Batches are sealed about once a minute while telemetry is on.", "SecondaryLabel")
			body.add_child(_pending_empty)
			_pending_data = Label.new()
			_pending_data.name = "PendingData"
			_pending_data.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			_pending_data.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
			_pending_data.theme_type_variation = "SecondaryLabel"
			body.add_child(_pending_data)
			set_pending_data(preview)
	if mode != "consent":
		close_button = _choice("Close", "", "Close")
		close_button.pressed.connect(close)
		shell.add_child(close_button)
	_opened_msec = Time.get_ticks_msec()
	_screen.resized.connect(_resize_panel)
	_screen.theme_changed.connect(_resize_panel)



func set_pending_data(preview: String) -> void:
	_pending_data.text = preview
	_pending_data.visible = not preview.is_empty()
	_pending_empty.visible = preview.is_empty()


func _ready() -> void:
	_resize_panel()
	_screen.ensure_focus.call_deferred()


func _process(_delta: float) -> void:
	if _armed or mode != "consent":
		set_process(false)
		return
	# Arm only after a quiet moment with nothing held: an intro skip or menu press can never answer this notice.
	if Input.is_anything_pressed():
		_opened_msec = Time.get_ticks_msec()
		return
	if Time.get_ticks_msec() - _opened_msec < ARM_DELAY_MSEC:
		return
	_armed = true
	enable_button.disabled = false
	decline_button.disabled = false
	set_process(false)
	_focus_initial()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		for entry: Dictionary in _texts:
			var control: Control = entry.control
			var text := tr(str(entry.source))
			if not (entry.args as Array).is_empty():
				text = text % entry.args
			control.set("text", text)


## Whether the choice buttons accept input yet (tests and the debug bridge read it).
func is_armed() -> bool:
	return _armed


func close() -> void:
	closed.emit()


func _answer(enabled: bool) -> void:
	if _answered or (enabled and not _armed):
		return
	_answered = true
	chosen.emit(enabled)


## Esc/Back or a window close: in consent mode this declines (never enables); otherwise it closes.
func _on_close_requested() -> void:
	if mode == "consent":
		_answer(false)
	else:
		close()


func _unhandled_input(event: InputEvent) -> void:
	if not _screen._active or not event.is_action_pressed("ui_cancel"):
		return
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if MenuInput.selected_gamepad_id() < 0 or event.device != MenuInput.selected_gamepad_id():
			return
	get_viewport().set_input_as_handled()
	_on_close_requested()


func _focus_initial() -> void:
	if not is_inside_tree() or not _screen._active:
		return
	var initial: Control = close_button if mode != "consent" else _notice_scroll
	if initial != null and Screen.can_focus(initial):
		initial.grab_focus()


func _operator() -> String:
	var operator := str(_release.get("operator", "")).strip_edges()
	return operator if operator != "" else "-"


## Only the scheme and host: the notice names where data goes, not an internal path.
static func _origin(endpoint: String) -> String:
	var scheme_end := endpoint.find("://")
	if scheme_end < 0:
		return "-"
	return endpoint.substr(0, endpoint.find("/", scheme_end + 3)) if endpoint.find("/", scheme_end + 3) > 0 else endpoint


func _text(source: String, variation: String, args: Array = []) -> Label:
	var label := Widgets.label("", variation, true, false)
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = tr(source) % args if not args.is_empty() else tr(source)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_texts.append({"control": label, "source": source, "args": args})
	return label


func _choice(source: String, variation: String, node_name: String) -> Button:
	var button := Widgets.button(tr(source), variation, node_name)
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A wrapping button needs a width share: in a row without one it wraps word by word, grows taller than the
	# window and collapses the notice text. Both buttons of a row get equal, equally visible halves.
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_texts.append({"control": button, "source": source, "args": []})
	return button


func _resize_panel() -> void:
	if not is_inside_tree():
		return
	var area := get_viewport().get_visible_rect().size
	var scale := clampf(ScreenTheme.text_scale, 1.0, 2.0)
	_panel.custom_minimum_size = Vector2(minf(820.0 * scale, maxf(1.0, area.x - 48.0)),
		minf(760.0 * scale, maxf(1.0, area.y - 48.0)))
