## SC-19a: plays the synthesised ambience. The ~0.5 M samples are rendered on a worker thread (in GDScript they would
## cost far more than the 150 ms field-load budget); playback starts when they are ready, and the task is always
## waited for before the node leaves the tree, so no thread outlives the scene.
extends AudioStreamPlayer

## One completed loop shared between scene builds. Only workers touch the cache;
## synthesis happens outside the lock so an unrelated seed never blocks a scene thread.
static var _cache_mutex := Mutex.new()
static var _cached_seed := 0
static var _cached_wav: AudioStreamWAV

var _task := -1
var _wav: AudioStreamWAV


func _enter_tree() -> void:
	# A detached scene may return after _exit_tree joined its still-pending render.
	# _ready runs only on the first entry, so let _process publish that finished WAV.
	if _task < 0 and _wav != null and stream == null:
		set_process(true)


func _ready() -> void:
	var seed: int = get_meta("seed", 1253)
	_task = WorkerThreadPool.add_task(_render.bind(seed), false, "scenery ambience")


func _render(seed: int) -> void:
	_cache_mutex.lock()
	var source := _cached_wav if _cached_wav != null and _cached_seed == seed else null
	_cache_mutex.unlock()
	if source == null:
		# Concurrent cold requests may both render; neither holds the cache lock while doing so.
		source = _synthesize(seed)
		_cache_mutex.lock()
		_cached_seed = seed
		_cached_wav = source
		_cache_mutex.unlock()
	# A player owns its stream's mutable properties; it cannot alter the cache or another player.
	_wav = source.duplicate() as AudioStreamWAV


func _synthesize(seed: int) -> AudioStreamWAV:
	return load("res://scenery/ambience.gd").stream(seed) # load(), not preload: ambience.gd preloads this script


func _process(_delta: float) -> void:
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	if _wav != null:
		stream = _wav
		play()
		set_process(false)


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
