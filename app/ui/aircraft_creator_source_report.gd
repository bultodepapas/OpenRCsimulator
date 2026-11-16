extends VBoxContainer
## Bounded, read-only declarations. Rebuilding is keyed by validated content, not UI refresh count.
const Observations := preload("res://workshop/creator/clearview/observations.gd")
const TITLE := "Inspect source declarations"
const CAUTION := "Source declarations are references, not measurements. They do not change the flight configuration."
const INTEGRITY := "Parameter contents checked. ZIP membership is declared; physical values are unverified."
const DOCUMENTED := "Unit documented for ClearView v5"
const INFERRED := "Unit inferred; confirm independently"
const UNKNOWN := "Unit or meaning unresolved"
const DUPLICATE := "Repeated declaration; no value selected"
const TRUNCATED := "Declaration shortened for display"
const OMITTED := "Some declarations are omitted from this view. The original parameters are retained with the model."
const MEMBER := "Parameter file: %s"
const HASH := "Parameter SHA-256: %s"
const POSITION := "%s · line %s"

var _context := {}
var _toggle: Button
var _body: VBoxContainer

func _init() -> void:
	name = "SourceDeclarations"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toggle = Button.new()
	_toggle.name = "InspectSourceDeclarations"
	_toggle.text = tr(TITLE)
	_toggle.toggle_mode = true
	_toggle.toggled.connect(func(on: bool) -> void: _body.visible = on)
	add_child(_toggle)
	_body = VBoxContainer.new()
	_body.name = "SourceDeclarationDetails"
	_body.visible = false
	_body.add_theme_constant_override("separation",12)
	add_child(_body)
	visible = false

func show_context(value: Dictionary) -> void:
	if value == _context:
		return
	var checked := Observations.validate(value)
	_context = checked.value if checked.ok else {}
	visible = not _context.is_empty()
	_rebuild()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_instance_valid(_body):
		_toggle.text = tr(TITLE)
		_rebuild()

func _rebuild() -> void:
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	if _context.is_empty():
		return
	_text(tr(CAUTION))
	_text(tr(INTEGRITY))
	_text(tr(MEMBER) % _context.parameters_member)
	_text(tr(HASH) % _context.parameters_sha256)
	for row: Dictionary in _context.observations:
		var path: String = row.section+"/"+row.key if not row.section.is_empty() else row.key
		_text(tr(POSITION) % [path,row.line])
		_text(row.raw)
		var basis := UNKNOWN
		if row.unit_basis == "documented_v5":
			basis = DOCUMENTED
		elif str(row.unit_basis).begins_with("inferred_"):
			basis = INFERRED
		var caption := tr(basis)
		if not row.unit.is_empty():
			caption = row.unit+" · "+caption
		if row.disposition == "duplicate":
			caption += " · "+tr(DUPLICATE)
		elif row.truncated:
			caption += " · "+tr(TRUNCATED)
		elif row.value.is_empty() and basis != UNKNOWN:
			caption += " · "+tr(UNKNOWN)
		_text(caption)
	if _context.omitted != "0":
		_text(tr(OMITTED))

func _text(value: String) -> void:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(label)
