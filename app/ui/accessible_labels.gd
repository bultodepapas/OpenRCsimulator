# PT1h-R12 (game findings #12): accessible names for value controls, app-wide.
# A Label placed immediately before a value control in the same container labels it: the usual row and grid layout
# ("Window resolution" | [OptionButton]). An OptionButton alone shows only its current value ("Automatic"), so a
# screen reader (Godot's AccessKit) or an agent could not tell what it sets. Linking the Label node through
# accessibility_labeled_by_nodes, instead of copying its text, keeps the name right after a language change.
# Explicit names win: a control that already has an accessibility_name or labelled-by link is left alone.
extends Node


func _enter_tree() -> void:
	name = "AccessibleLabels"
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)


## Controls already in the tree when this node arrives.
func _ready() -> void:
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Control:
			link(node)
		stack.append_array(node.get_children())


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is Control:
		link(node)


## Link `control` to the Label just before it, when the rule applies. Returns whether a link was made.
static func link(control: Control) -> bool:
	if not _value_control(control):
		return false
	if not str(control.accessibility_name).is_empty() or not control.accessibility_labeled_by_nodes.is_empty():
		return false
	var parent := control.get_parent()
	if not parent is Container:
		return false
	# Public children only: an internal node (a ScrollContainer's scroll bar is a Range) is an implementation part,
	# and get_index() on it is an engine error.
	var siblings: Array[Node] = parent.get_children()
	var index := siblings.find(control)
	if index <= 0:
		return false
	var before := siblings[index - 1]
	if not before is Label or str(before.text).strip_edges().is_empty():
		return false
	control.accessibility_labeled_by_nodes = [control.get_path_to(before)]
	return true


## Controls that show a value rather than naming themselves. Buttons and labelled check boxes carry their own text.
static func _value_control(control: Control) -> bool:
	if control is OptionButton or control is Range or control is LineEdit or control is TextEdit or control is ItemList:
		return true
	return (control is CheckBox or control is CheckButton) and str(control.text).strip_edges().is_empty()
