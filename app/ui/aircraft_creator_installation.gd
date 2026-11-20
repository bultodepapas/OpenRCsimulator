extends VBoxContainer
## UI intent only: no coefficients are imported. The confirmed configuration flies exactly like an
## STL/GLB Creator aircraft with the same values: experimental, never a ClearView flight model.
signal choice_requested(proposal: Dictionary,revision: int)
## One-click ClearView setup: orientation, estimated datum, values, inventory and this choice.
signal setup_requested(revision: int)
## A ClearView helicopter: test fly its appearance on the X-Cell .60 donor helicopter physics.
signal helicopter_requested(revision: int)
const TITLE := "OpenRC configuration"
const PROPOSAL := "Proposed installation: conventional wing and aft tail, one tractor electric motor, 4S battery and 12×6 propeller."
const RETAINED := "Existing values and inventory are kept. Review dimensions, masses and controls for this model."
const REVIEW := "I have reviewed the retained values for this model."
const CHOOSE := "Create an estimated OpenRC configuration"
const SETUP := "Set up for flight automatically"
const SETUP_HINT := "Uses the ClearView model frame, estimates the wing leading edge and fills every empty value with labelled OpenRC estimates. Nothing you entered is replaced."
const CHOSEN := "Independent estimated OpenRC configuration selected. ClearView flight settings remain source references."
const PHOENIX_SETUP_HINT := "Uses the Phoenix model frame, weight, balance, wing, airfoils, tail and propeller, and fills every other empty value with labelled OpenRC estimates. Nothing you entered is replaced."
const PHOENIX_CHOSEN := "Configuration derived from the Phoenix flight data selected. Values Phoenix does not record stay labelled OpenRC estimates."
const Installation := preload("res://workshop/creator/source_installation.gd")
const HeliDonor := preload("res://workshop/creator/clearview/heli_donor.gd")
var _title: Label
var _proposal_label: Label
var _retained: Label
var _review: CheckButton
var _choose: Button
var _setup: Button
var _setup_hint: Label
var _qualification: Label
var _source_id := 0
var _revision := -1
var _proposal := {}
var _selected := false
var _busy := false
var _helicopter := false
var _provider := "clearview"

func _init() -> void:
	name = "SourceInstallation"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",10)
	_title = _label()
	_proposal_label = _label()
	_setup = Button.new()
	_setup.name = "SetupClearView"
	_setup.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_setup.pressed.connect(func() -> void:
		if _busy:
			return
		if _helicopter:
			helicopter_requested.emit(_revision)
		elif not _selected:
			setup_requested.emit(_revision))
	add_child(_setup)
	_setup_hint = _label()
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

## `helicopter`: the source is a converted ClearView helicopter. The aeroplane configuration does not apply;
## the one action offered is the donor helicopter flight.
func show_state(source_id: int,revision: int,proposal: Dictionary,selected: bool,busy: bool,helicopter := false,
		provider := "clearview") -> void:
	if source_id != _source_id or revision != _revision:
		_review.set_pressed_no_signal(false)
	_source_id = source_id
	_revision = revision
	_proposal = proposal.duplicate(true)
	_selected = selected
	_busy = busy
	_helicopter = helicopter
	_provider = provider
	visible = helicopter or not proposal.is_empty()
	_proposal_label.visible = not helicopter
	_review.visible = not selected and not helicopter
	_setup.visible = not selected or helicopter
	_setup.disabled = busy
	_setup_hint.visible = not selected or helicopter
	_review.disabled = busy
	_retained.visible = not selected and not helicopter
	_choose.visible = not selected and not helicopter
	_qualification.visible = not helicopter
	_choose.disabled = busy or selected or not _review.button_pressed
	_translate()

func focus_target() -> Control:
	return _setup if _setup.visible else (_review if _review.visible else _choose)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_instance_valid(_qualification):
		_translate()

func _translate() -> void:
	_title.text = tr(TITLE)
	_proposal_label.text = tr((PHOENIX_CHOSEN if _provider == "phoenix" else CHOSEN) if _selected else PROPOSAL)
	_retained.text = tr(RETAINED)
	_review.text = tr(REVIEW)
	_choose.text = tr(CHOOSE)
	_setup.text = tr(HeliDonor.OFFER if _helicopter else SETUP)
	_setup_hint.text = tr(HeliDonor.OFFER_HINT if _helicopter else (PHOENIX_SETUP_HINT if _provider == "phoenix" else SETUP_HINT))
	_qualification.text = tr(Installation.PHOENIX_ESTIMATED_FLIGHT if _provider == "phoenix" else Installation.ESTIMATED_FLIGHT)

func _label() -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(label)
	return label
