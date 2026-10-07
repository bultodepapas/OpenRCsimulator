## SC-19a: plays the synthesised ambience. The ~0.5 M samples are rendered on a worker thread (in GDScript they would
## cost far more than the 150 ms field-load budget); playback starts when they are ready, and the task is always
## waited for before the node leaves the tree, so no thread outlives the scene.
extends AudioStreamPlayer

var _task := -1
var _wav: AudioStreamWAV


func _ready() -> void:
	var seed: int = get_meta("seed", 1253)
	_task = WorkerThreadPool.add_task(_render.bind(seed), false, "scenery ambience")


func _render(seed: int) -> void:
	_wav = load("res://scenery/ambience.gd").stream(seed) # load(), not preload: ambience.gd preloads this script


func _process(_delta: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		stream = _wav
		play()
		set_process(false)


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
