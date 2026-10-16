# UI-21: sole owner of menu membership, top-screen input, focus return and the named session hold.
# Screens remain direct children of app_root so existing paths, CanvasLayers and captures stay unchanged.
extends RefCounted

const Screen := preload("res://ui/screen.gd")
signal surface_opened(surface: Control, id: String)
signal surface_closed(id: String, restoring_focus: bool)
var _host: Node
var _entries: Array[Dictionary] = []
var _session: Node


func _init(host: Node) -> void:
	_host = host


func get_screen(id: String) -> Node:
	for entry: Dictionary in _entries:
		if entry.id == id:
			return entry.node
	return null


func top() -> Node:
	return _entries.back().node if not _entries.is_empty() else null


func size() -> int:
	return _entries.size()


func is_top(id: String) -> bool:
	return top() != null and get_screen(id) == top()


func set_session(session: Node) -> void:
	if is_instance_valid(_session):
		_session.release("menu")
	_session = session
	_sync_hold()


func push(id: String, node: Node, from: Control = null) -> bool:
	if not is_instance_valid(node) or node.is_queued_for_deletion() or node.get_parent() != null \
		or get_screen(id) != null:
		return false # caller retains ownership of a rejected node
	var surface: Control = _surface(node)
	if surface == null or surface.kind == Screen.Kind.TOAST:
		return false # nonblocking overlays (FirstFlightHint, future toasts) live outside navigation
	if top() is CanvasLayer and not node is CanvasLayer:
		return false # overlays need a CanvasLayer wrapper to draw above the paused flight/menu
	if top() is CanvasLayer and node is CanvasLayer:
		node.layer = maxi(node.layer, top().layer + 1)
	if from == null and _host.is_inside_tree():
		from = _host.get_viewport().gui_get_focus_owner()
	if not _entries.is_empty():
		_entries.back().surface.set_active(false)
	_entries.append({id = id, node = node, surface = surface})
	_sync_hold() # a pause screen holds the flight before it enters the tree
	_host.add_child(node)
	surface.open(from)
	surface_opened.emit(surface, id)
	return true


## Pop only the top. `dispose=false` suspends Home for the synchronous Fly/rejected-start handoff.
func pop(dispose := true, restore_focus := true) -> Node:
	if _entries.is_empty():
		return null
	var entry: Dictionary = _entries.pop_back()
	if entry.node.is_inside_tree():
		_host.remove_child(entry.node)
	if not _entries.is_empty():
		_entries.back().surface.set_active(true)
	entry.surface.close(restore_focus)
	_sync_hold()
	surface_closed.emit(str(entry.id), restore_focus)
	if dispose:
		entry.node.queue_free()
	return entry.node


func clear() -> void:
	while not _entries.is_empty():
		pop(true, false)


func _sync_hold() -> void:
	if not is_instance_valid(_session):
		return
	# Home has no flight session. Any blocking screen over a flight holds it; toasts do not.
	for entry: Dictionary in _entries:
		if entry.surface.kind != Screen.Kind.TOAST:
			_session.hold("menu")
			return
	_session.release("menu") # release alone never resumes a session


static func _surface(node: Node) -> Control:
	if node is Screen:
		return node
	for child: Node in node.get_children():
		if child is Screen:
			return child
	return null
