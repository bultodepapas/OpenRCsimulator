extends VBoxContainer
## UI intent only: no coefficients are imported and this choice never qualifies a flight.
signal choice_requested(proposal: Dictionary,revision: int)
const TITLE := "OpenRC configuration"
const PROPOSAL := "Proposed installation: conventional wing and aft tail, one tractor electric motor, 4S battery and 12×6 propeller."
const RETAINED := "Existing values and inventory are kept. Review dimensions, masses and controls for this model."
const REVIEW := "I have reviewed the retained values for this model."
const CHOOSE := "Create an estimated OpenRC configuration"
const CHOSEN := "Independent estimated OpenRC configuration selected. ClearView flight settings remain source references."
const Installation := preload("res://workshop/creator/source_installation.gd")
var _title: Label
var _proposal_label: Label
var _retained: Label
var _review: CheckButton
var _choose: Button
var _qualification: Label
var _source_id := 0
var _revision := -1
var _proposal := {}
var _selected := false
var _busy := false

func _init() -> void:
	name = "SourceInstallation"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",10)
	_title = _label()
	_proposal_label = _label()
	_retained = _label()
	_review = CheckButton.new()
	_review.name = "ReviewSourceInstallation"
	_review.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_review.toggled.connect(func(_on: bool) -> void: _choose.disabled = _busy or _selected or not _review.button_pressed)
	add_child(_review)
	_choose = Button.new()
	_choose.name = "ChooseSourceInstallation"
	_choose.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_choose.pressed.connect(func() -> void:
		if not _busy and not _selected and _review.button_pressed:
			choice_requested.emit(_proposal.duplicate(true),_revision))
	add_child(_choose)
	_qualification = _label()
	_translate()
	visible = false

func show_state(source_id: int,revision: int,proposal: Dictionary,selected: bool,busy: bool) -> void:
	if source_id != _source_id or revision != _revision:
		_review.set_pressed_no_signal(false)
	_source_id = source_id
	_revision = revision
	_proposal = proposal.duplicate(true)
	_selected = selected
	_busy = busy
	visible = not proposal.is_empty()
	_review.visible = not selected
	_review.disabled = busy
	_retained.visible = not selected
	_choose.visible = not selected
	_choose.disabled = busy or selected or not _review.button_pressed
	_translate()

func focus_target() -> Control:
	return _review if _review.visible else _choose

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_instance_valid(_qualification):
		_translate()

func _translate() -> void:
	_title.text = tr(TITLE)
	_proposal_label.text = tr(CHOSEN if _selected else PROPOSAL)
	_retained.text = tr(RETAINED)
	_review.text = tr(REVIEW)
	_choose.text = tr(CHOOSE)
	_qualification.text = tr(Installation.FLIGHT_UNAVAILABLE)

func _label() -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(label)
	return label
