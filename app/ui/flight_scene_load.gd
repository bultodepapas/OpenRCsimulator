## UI-34c: one ordinary ResourceLoader call outside the WorkerThreadPool.
## A root-owned job outlives a departing AppRoot and joins only after the worker stops.
extends Node

## Test seam: production binds only ResourceLoader.load, without accessing Nodes from the worker.
var load_resource: Callable = ResourceLoader.load
var complete := false
var _thread: Thread
var _scene: PackedScene
var _abandoned := false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func start(path: String) -> Error:
	_thread = Thread.new()
	var error := _thread.start(load_resource.bind(path, "PackedScene"))
	if error != OK:
		_thread = null
		complete = true
		return error
	set_process(true)
	return OK


func _process(_delta: float) -> void:
	if _thread == null:
		set_process(false)
		return
	if _thread.is_alive():
		return
	# ResourceLoader may wait for main-thread deferred work: never join a live worker.
	_scene = _thread.wait_to_finish() as PackedScene
	_thread = null
	complete = true
	set_process(false)
	if _abandoned:
		_scene = null
		queue_free()


func take_scene() -> PackedScene:
	if not complete:
		return null
	var scene := _scene
	_scene = null
	queue_free()
	return scene


func abandon() -> void:
	_abandoned = true
	_scene = null
	if complete:
		queue_free()
