## UI-34c: one optional Home preparation owner. Survives a departed AppRoot until workers drain.
extends Node

const FLIGHT_SCENE := "res://main.tscn"
var _app: WeakRef
var _broker: WeakRef
var _home: WeakRef
var _home_id := 0
var _drawn := false
var _stable_since_msec := 0
var _intent := ""
var _scene_job: Node
var _scene_attempted := false
var _launching := false
var _stopping := false
var _trim_attempted := ""
var _trim_owned := false
var _trim_complete := false
var _trim_intent := ""
var mode := "off"
var delay_msec := 350
var trim_prepare := Callable()
var trim_poll := Callable()
var trim_abandon := Callable()
var _stats := {scene_started = 0, scene_completed = 0, scene_adopted = 0,
	trim_started = 0, trim_completed = 0, scene_failed = 0}


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func configure(app: Node, broker: Node) -> void:
	_app = weakref(app)
	_broker = weakref(broker)


func observe_home(surface: Control) -> void:
	_launching = false
	if surface.get_instance_id() == _home_id:
		if not _drawn and DisplayServer.get_name() != "headless" and not RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
			RenderingServer.frame_post_draw.connect(_on_frame_post_draw, CONNECT_ONE_SHOT)
		return
	_home = weakref(surface)
	_home_id = surface.get_instance_id()
	_drawn = false
	_launching = false
	_scene_attempted = false
	intent_changed()
	if DisplayServer.get_name() != "headless" and not RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.connect(_on_frame_post_draw, CONNECT_ONE_SHOT)


func _on_frame_post_draw() -> void:
	var app: Node = _app.get_ref() if _app != null else null
	var surface: Control = _home.get_ref() if _home != null else null
	if is_instance_valid(app) and is_instance_valid(surface) and app.home == surface and app.screens.is_top("home"):
		mark_home_drawn()


## Explicit headless-test seam. Production calls this only after frame_post_draw.
func mark_home_drawn() -> void:
	_drawn = true


func intent_changed() -> void:
	_stable_since_msec = Time.get_ticks_msec()


func tick(eligible: bool, preview_pending: bool, path: String, aircraft_id: String) -> void:
	if _stopping or _launching:
		return
	var intent := path + "|" + aircraft_id
	if intent != _intent:
		_intent = intent
		intent_changed()
	var broker: Node = _broker.get_ref() if _broker != null else null
	# Keep the common scene recent within the broker's existing two entries while
	# selected aircraft previews replace one another. No second scene cache is held here.
	if _scene_attempted and is_instance_valid(broker):
		broker.retained(FLIGHT_SCENE)
	if not eligible or not _drawn or preview_pending or Time.get_ticks_msec() - _stable_since_msec < delay_msec:
		return
	var app: Node = _app.get_ref() if _app != null else null
	if not is_instance_valid(broker) or not is_instance_valid(app) or broker.is_busy() or scene_busy():
		return
	if mode in ["scene", "scene_trim"] and not _scene_attempted:
		_scene_attempted = true
		var retained: PackedScene = broker.retained(FLIGHT_SCENE)
		if retained == null:
			broker.set_admissions_paused(true)
			_scene_job = app._new_flight_scene_load()
			get_tree().root.add_child(_scene_job)
			var error: Error = _scene_job.start(FLIGHT_SCENE)
			if error != OK:
				_stats.scene_failed += 1
				_scene_job.abandon()
				_scene_job = null
				broker.set_admissions_paused(false)
			else:
				_stats.scene_started += 1
			return
	if mode in ["trim", "scene_trim"] and not path.is_empty() and _trim_attempted != intent \
			and trim_prepare.is_valid():
		if _trim_owned:
			# Keep a pending A through A -> B -> A. A settled B may replace a completed private A.
			if _trim_complete and _trim_intent != intent and trim_abandon.is_valid():
				trim_abandon.call()
			return
		_trim_attempted = intent
		var result: Dictionary = trim_prepare.call(path, aircraft_id)
		_trim_owned = result.get("kind", "") == "pending"
		if _trim_owned:
			_trim_complete = false
			_trim_intent = intent
			_stats.trim_started += 1


## Ownership stays here while Fly waits for its selected GLB; completion releases the broker gate.
func adopt() -> bool:
	_launching = true
	if scene_busy():
		_stats.scene_adopted += 1
		return true
	return false


func cancel_launch() -> void:
	if _trim_owned and trim_abandon.is_valid():
		trim_abandon.call()


func scene_busy() -> bool:
	return is_instance_valid(_scene_job)


func is_drained() -> bool:
	return not scene_busy() and not _trim_owned


func snapshot() -> Dictionary:
	var result := _stats.duplicate()
	result.merge({mode = mode, scene_active = scene_busy(), trim_active = _trim_owned, trim_ready = _trim_complete,
		drawn = _drawn, stopping = _stopping, drained = is_drained()}, true)
	return result


func shutdown() -> void:
	_stopping = true
	if _trim_owned and trim_abandon.is_valid():
		trim_abandon.call()
	var broker: Node = _broker.get_ref() if _broker != null else null
	if is_instance_valid(broker):
		broker.discard_queued_request()


func _process(_delta: float) -> void:
	if _app == null or _app.get_ref() == null:
		shutdown()
	if scene_busy() and _scene_job.complete:
		var scene: PackedScene = _scene_job.take_scene()
		_scene_job = null
		var broker: Node = _broker.get_ref() if _broker != null else null
		if scene != null and scene.can_instantiate():
			_stats.scene_completed += 1
			if not _stopping and is_instance_valid(broker):
				broker.retain_loaded(FLIGHT_SCENE, scene)
		else:
			_stats.scene_failed += 1
		if is_instance_valid(broker):
			broker.set_admissions_paused(false)
	if _trim_owned and trim_poll.is_valid():
		var status: Dictionary = trim_poll.call()
		if bool(status.get("complete", false)) and not _trim_complete:
			_trim_complete = true
			_stats.trim_completed += 1
		if not bool(status.get("active", false)):
			_trim_owned = false
			_trim_complete = false
			_trim_attempted = ""
	if _stopping and is_drained():
		queue_free()
