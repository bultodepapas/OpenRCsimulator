## A field row with one hidden, field-owned validation explanation.
extends RefCounted

const Widgets := preload("res://ui/widgets.gd")


static func wrap(control: Control) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(control)
	var reason := Widgets.label("", "ErrorLabel", true, false)
	reason.name = "FieldDiagnostic"
	reason.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reason.visible = false
	column.add_child(reason)
	return column


static func find(control: Control) -> Label:
	var ancestor: Node = control
	while ancestor is Control:
		var reason := ancestor.get_node_or_null("FieldDiagnostic") as Label
		if reason != null:
			return reason
		ancestor = ancestor.get_parent()
	return null
