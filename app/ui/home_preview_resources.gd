# UI-05: selected-resource loading. Owned by AppRoot, so departing Home cannot
# abandon an engine request. Nodes, validation and GPU presentation stay on main.
extends Node

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const HX700 := preload("res://aircraft/hx700_model.gd")
const RESOURCE_LIMIT := 2
var _active_path := ""
var _active_callback := Callable()
var _queued_path := ""
var _queued_callback := Callable()
var _resources: Dictionary = {}
var _order: Array[String] = []

func _init() -> void:
	set_process(false)

## Only a loading hint. The normal builder still checks all provenance and data.
## `livery` names a non-default paint scheme (F4U-16); its own GLB is preloaded instead of the default asset.
static func path_for(id: String, livery := "") -> String:
	if Catalog.is_rotorcraft(id):
		return HX700.SCENE_PATH if id == "xcell-60-research" else ""
	var family := Catalog.visual_family(id)
	if family.is_empty(): return ""
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft_models/" + family + ".json"))
	if not parsed is Dictionary: return ""
	var asset: Variant = parsed.get("asset", {})
	if not asset is Dictionary or asset.get("kind") != "imported_glb": return ""
	var path: String = str(asset.get("path", ""))
	if not livery.is_empty():
		path = ""
		for record: Variant in parsed.get("liveries", []):
			if record is Dictionary and record.get("id") == livery: path = str(record.get("path", ""))
	return path if path == path.simplify_path() and path.begins_with("res://assets/aircraft/") and path.ends_with(".glb") else ""

func request(path: String, callback: Callable) -> void:
	# Every new intent supersedes callbacks, including a cache hit or procedural model.
	_active_callback = Callable()
	_queued_callback = Callable()
	_queued_path = ""
	if path.is_empty() or _resources.has(path):
		if _resources.has(path):
			_order.erase(path)
			_order.append(path)
		if callback.is_valid(): callback.call(true)
	elif path == _active_path:
		_active_callback = callback
	elif not _active_path.is_empty():
		_queued_path = path
		_queued_callback = callback
	else:
		_start(path, callback)

func _start(path: String, callback: Callable) -> void:
	var error := ResourceLoader.load_threaded_request(path, "PackedScene", false)
	if error != OK:
		if callback.is_valid(): callback.call(false)
		return
	_active_path = path
	_active_callback = callback
	set_process(true)

func _process(_delta: float) -> void:
	if _active_path.is_empty():
		set_process(false)
		return
	var status := ResourceLoader.load_threaded_get_status(_active_path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS: return
	var path := _active_path
	var callback := _active_callback
	_active_path = ""
	_active_callback = Callable()
	var resource: Resource
	if status == ResourceLoader.THREAD_LOAD_LOADED or status == ResourceLoader.THREAD_LOAD_FAILED:
		resource = ResourceLoader.load_threaded_get(path)
	var ok := resource is PackedScene
	# Obsolete completions are drained, not retained or applied.
	if ok and callback.is_valid():
		_resources[path] = resource
		_order.erase(path)
		_order.append(path)
		while _order.size() > RESOURCE_LIMIT:
			_resources.erase(_order.pop_front())
	var next_path := _queued_path
	var next_callback := _queued_callback
	_queued_path = ""
	_queued_callback = Callable()
	if callback.is_valid(): callback.call(ok)
	if not next_path.is_empty() and next_callback.is_valid():
		request(next_path, next_callback)
	set_process(not _active_path.is_empty())

func cancel_for(owner: Object, release_resources := true) -> void:
	if _active_callback.get_object_id() == owner.get_instance_id(): _active_callback = Callable()
	if _queued_callback.get_object_id() == owner.get_instance_id():
		_queued_callback = Callable()
		_queued_path = ""
	if release_resources:
		_resources.clear()
		_order.clear()

func _exit_tree() -> void:
	_active_callback = Callable()
	_queued_callback = Callable()
	# App shutdown only: ResourceLoader has no cancellation API. Drain ownership
	# before releasing the broker; ordinary Home replacement never waits here.
	if not _active_path.is_empty():
		ResourceLoader.load_threaded_get(_active_path)
	_active_path = ""
	_queued_path = ""
	_resources.clear()
	_order.clear()
