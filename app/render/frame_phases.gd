extends RefCounted
## PT1h-R15-S3 (F0): splits the wall interval between two observer callbacks into main-loop phases.
##
## Each Godot main-loop iteration runs: physics ticks (`physics_frame`, `_physics_process` callbacks, then deferred
## calls, timers and the physics server step), `process_frame`, `_process` callbacks, deferred calls/timers/tweens,
## RenderingServer draw (`frame_pre_draw` .. `frame_post_draw`, including presentation), then audio, the frame
## limiter and OS events before the next iteration. Two bracket nodes at the extreme process priorities and four
## engine signals mark those boundaries; no simulation or rendering source changes. An observer that runs once per
## iteration at a fixed priority calls `split(previous_usec, now_usec)`; when `phase_valid` is 1 the eight
## `*_usec` durations sum exactly to its interval. Observers share one probe through `acquire`/`release`, so ticks
## carry one set of bracket callbacks however many observers split them.

const FORMAT := "openrc-frame-phases v1"
const MIN_PRIORITY := -2147483648
const MAX_PRIORITY := 2147483647
const DURATIONS: Array[String] = [
	"phase_tail_process_usec", # observer callback -> last `_process` callback of the previous iteration
	"phase_tail_engine_usec", # -> `frame_pre_draw`: deferred calls, timers, tweens, frees, idle callbacks, navigation, RenderingServer sync
	"phase_render_usec", # `frame_pre_draw` -> `frame_post_draw`: CPU render recording, swapchain acquire, submit, present and fence waits
	"phase_between_usec", # -> first callback of this iteration: audio, frame limiter, OS/run-loop events, input flush, physics sync
	"phase_physics_usec", # first `physics_frame` -> last high-priority `_physics_process` of this iteration
	"phase_after_physics_usec", # -> `process_frame`: the last tick's deferred calls, timers, navigation and physics step
	"phase_pre_process_usec", # `process_frame` handlers, resumed coroutines and deferred calls
	"phase_process_usec", # lowest-priority `_process` -> this observer callback
]
const COUNTS: Array[String] = [
	"phase_valid", "phase_drawn", "phase_ticks", "phase_tick_scripts_usec", "phase_tick_max_usec",
	"monitor_process_s", "monitor_physics_process_s",
]
const METADATA := {
	format = FORMAT,
	clock = "godot_ticks_usec",
	iteration_key = "Engine.get_process_frames()",
	invalid_rule = "phase_valid=0 and all phase values 0 unless every boundary of the previous and current iteration was observed in order",
	drawn_rule = "phase_drawn=0 when the previous iteration did not draw; phase_tail_engine_usec then runs to this iteration's first callback",
	tick_scripts_scope = "sum over ticks of physics_frame -> the last _physics_process callback; excludes per-tick deferred calls, timers and the physics server step",
	signal_order_note = "the probe's physics_frame/process_frame handlers run in connection order; handlers and resumed awaits connected earlier land in the preceding phase (after_physics or between)",
	forced_draw_note = "a RenderingServer.force_draw before the last _process callback counts as process work; the last draw of an iteration is the render phase",
	bracket_scope = "brackets order within the default process group and the default (non-separate) render thread model",
	monitor_note = "monitor_* are Godot's TIME_PROCESS/TIME_PHYSICS_PROCESS: per-second maxima, for comparison only",
}

const ID := 0
const PHYSICS_FIRST := 1
const PHYSICS_LAST := 2
const TICKS := 3
const TICK_SCRIPTS := 4
const TICK_MAX := 5
const TICK_OPEN := 6
const PROCESS_SIGNAL := 7
const PROCESS_LOW := 8
const PROCESS_HIGH := 9
const PRE_DRAW := 10
const POST_DRAW := 11
const FIELD_COUNT := 12

var _current := _blank(-1)
var _previous := _blank(-1)
var _tree: SceneTree
var _low: Node
var _high: Node
var _started := false
## A separate render thread defers `frame_post_draw` into a later iteration; splits are then always invalid.
var _separate_render_thread := false
## Running totals since start for long-window per-tick cost (F1 A/Bs through the bridge's `eval`).
var _total_ticks := 0
var _total_tick_scripts_usec := 0
static var _shared: RefCounted = null
static var _shared_users := 0


class LowBracket extends Node:
	var _probe: WeakRef

	func _init(probe: RefCounted, priority: int) -> void:
		_probe = weakref(probe)
		name = "FramePhasesFirst"
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_priority = priority

	func _process(_delta: float) -> void:
		var probe: RefCounted = _probe.get_ref()
		if probe == null:
			queue_free()
			return
		probe.mark_process_low_at(Engine.get_process_frames(), Time.get_ticks_usec())


class HighBracket extends Node:
	var _probe: WeakRef

	func _init(probe: RefCounted, priority: int) -> void:
		_probe = weakref(probe)
		name = "FramePhasesLast"
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_priority = priority
		process_physics_priority = priority

	func _physics_process(_delta: float) -> void:
		var probe: RefCounted = _probe.get_ref()
		if probe != null:
			probe.mark_physics_end_at(Engine.get_process_frames(), Time.get_ticks_usec())

	func _process(_delta: float) -> void:
		var probe: RefCounted = _probe.get_ref()
		if probe == null:
			queue_free()
			return
		probe.mark_process_high_at(Engine.get_process_frames(), Time.get_ticks_usec())


## The process-wide probe, started on first use. Pair every successful call with `release`.
static func acquire(root: Node) -> RefCounted:
	if _shared == null or not _shared.is_started():
		var probe: RefCounted = (load("res://render/frame_phases.gd") as GDScript).new()
		if not probe.start(root):
			return null
		_shared = probe
		_shared_users = 0
	_shared_users += 1
	return _shared


## Stops the shared probe when its last user releases it. Other probes are ignored.
static func release(probe: RefCounted) -> void:
	if probe == null or probe != _shared:
		return
	_shared_users -= 1
	if _shared_users <= 0:
		_shared.stop()
		_shared = null
		_shared_users = 0


static func metric_names() -> Array[String]:
	var names: Array[String] = []
	names.append_array(DURATIONS)
	names.append_array(COUNTS)
	return names


## Adds the bracket nodes on the next idle point and connects the engine signals. Returns false if already
## started or the root is unusable.
func start(root: Node) -> bool:
	if _started or root == null or not root.is_inside_tree():
		return false
	_tree = root.get_tree()
	_separate_render_thread = int(ProjectSettings.get_setting("rendering/driver/threads/thread_model", 1)) == 2
	_low = LowBracket.new(self, MIN_PRIORITY)
	_high = HighBracket.new(self, MAX_PRIORITY)
	_attach.call_deferred(root)
	_tree.physics_frame.connect(_on_physics_frame)
	_tree.process_frame.connect(_on_process_frame)
	RenderingServer.frame_pre_draw.connect(_on_pre_draw)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	_started = true
	return true


## Deferred so a busy root can accept children; a probe stopped before this point adds nothing.
func _attach(root: Node) -> void:
	if not _started or not is_instance_valid(root) or not root.is_inside_tree():
		return
	for node: Variant in [_low, _high]:
		if is_instance_valid(node) and not (node as Node).is_inside_tree():
			root.add_child(node)


func is_started() -> bool:
	return _started


func stop() -> void:
	if not _started:
		return
	_started = false
	if is_instance_valid(_tree):
		if _tree.physics_frame.is_connected(_on_physics_frame):
			_tree.physics_frame.disconnect(_on_physics_frame)
		if _tree.process_frame.is_connected(_on_process_frame):
			_tree.process_frame.disconnect(_on_process_frame)
	if RenderingServer.frame_pre_draw.is_connected(_on_pre_draw):
		RenderingServer.frame_pre_draw.disconnect(_on_pre_draw)
	if RenderingServer.frame_post_draw.is_connected(_on_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_post_draw)
	for node: Variant in [_low, _high]:
		if is_instance_valid(node):
			if (node as Node).is_inside_tree():
				(node as Node).queue_free()
			else:
				(node as Node).free()
	_low = null
	_high = null


## Completed ticks and their summed `physics_frame` -> last `_physics_process` time since the probe was created.
func totals() -> Dictionary:
	return {ticks = _total_ticks, tick_scripts_usec = _total_tick_scripts_usec}


func metadata() -> Dictionary:
	var result: Dictionary = METADATA.duplicate(true)
	result.started = _started
	result.separate_render_thread = _separate_render_thread
	return result


## Splits the interval (previous_usec, now_usec] that ends at the caller's callback in the current iteration.
func split(previous_usec: int, now_usec: int) -> Dictionary:
	return split_at(Engine.get_process_frames(), previous_usec, now_usec)


func split_at(frame: int, previous_usec: int, now_usec: int) -> Dictionary:
	var result := _empty()
	var current := _current
	var previous := _previous
	if _separate_render_thread or previous_usec <= 0 or now_usec <= previous_usec or current[ID] != frame or previous[ID] != frame - 1:
		return result
	var previous_high: int = previous[PROCESS_HIGH]
	var process_signal: int = current[PROCESS_SIGNAL]
	var process_low: int = current[PROCESS_LOW]
	# The observer's previous callback must lie inside the previous iteration's `_process` brackets; an observer that
	# skipped an iteration would otherwise lump a whole iteration into the tail.
	if previous[PROCESS_LOW] < 0 or previous_usec < previous[PROCESS_LOW] or previous_high < previous_usec \
			or process_signal < 0 or process_low < 0:
		return result
	var ticks: int = current[TICKS]
	var first: int = current[PHYSICS_FIRST] if ticks > 0 else process_signal
	var drawn: bool = previous[PRE_DRAW] >= previous_high and previous[POST_DRAW] >= previous[PRE_DRAW]
	var values := PackedInt64Array([previous_high - previous_usec, 0, 0, 0, 0, 0,
		process_low - process_signal, now_usec - process_low])
	if drawn:
		values[1] = previous[PRE_DRAW] - previous_high
		values[2] = previous[POST_DRAW] - previous[PRE_DRAW]
		values[3] = first - previous[POST_DRAW]
	else:
		values[1] = first - previous_high
	if ticks > 0:
		values[4] = current[PHYSICS_LAST] - current[PHYSICS_FIRST]
		values[5] = process_signal - current[PHYSICS_LAST]
	for value: int in values:
		if value < 0:
			return result
	for index: int in DURATIONS.size():
		result[DURATIONS[index]] = values[index]
	result.phase_valid = 1
	result.phase_drawn = int(drawn)
	result.phase_ticks = ticks
	result.phase_tick_scripts_usec = current[TICK_SCRIPTS]
	result.phase_tick_max_usec = current[TICK_MAX]
	return result


func mark_physics_start_at(frame: int, usec: int) -> void:
	_enter(frame)
	if _current[PHYSICS_FIRST] < 0:
		_current[PHYSICS_FIRST] = usec
	_current[TICK_OPEN] = usec


func mark_physics_end_at(frame: int, usec: int) -> void:
	_enter(frame)
	var opened: int = _current[TICK_OPEN]
	if opened < 0 or usec < opened:
		return
	var span: int = usec - opened
	_current[TICKS] += 1
	_current[TICK_SCRIPTS] += span
	_current[TICK_MAX] = maxi(_current[TICK_MAX], span)
	_current[TICK_OPEN] = -1
	_current[PHYSICS_LAST] = usec
	_total_ticks += 1
	_total_tick_scripts_usec += span


func mark_process_signal_at(frame: int, usec: int) -> void:
	_enter(frame)
	if _current[PROCESS_SIGNAL] < 0:
		_current[PROCESS_SIGNAL] = usec


func mark_process_low_at(frame: int, usec: int) -> void:
	_enter(frame)
	if _current[PROCESS_LOW] < 0:
		_current[PROCESS_LOW] = usec


func mark_process_high_at(frame: int, usec: int) -> void:
	_enter(frame)
	_current[PROCESS_HIGH] = usec


## The main draw is the last one in an iteration; an earlier forced draw is replaced.
func mark_pre_draw_at(frame: int, usec: int) -> void:
	_enter(frame)
	_current[PRE_DRAW] = usec


func mark_post_draw_at(frame: int, usec: int) -> void:
	_enter(frame)
	_current[POST_DRAW] = usec


func _on_physics_frame() -> void:
	mark_physics_start_at(Engine.get_process_frames(), Time.get_ticks_usec())


func _on_process_frame() -> void:
	mark_process_signal_at(Engine.get_process_frames(), Time.get_ticks_usec())


func _on_pre_draw() -> void:
	mark_pre_draw_at(Engine.get_process_frames(), Time.get_ticks_usec())


func _on_post_draw() -> void:
	mark_post_draw_at(Engine.get_process_frames(), Time.get_ticks_usec())


func _enter(frame: int) -> void:
	if _current[ID] != frame:
		_previous = _current
		_current = _blank(frame)


func _empty() -> Dictionary:
	var result := {}
	for key: String in DURATIONS:
		result[key] = 0
	for key: String in COUNTS:
		result[key] = 0
	result.monitor_process_s = Performance.get_monitor(Performance.TIME_PROCESS)
	result.monitor_physics_process_s = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	return result


static func _blank(frame: int) -> PackedInt64Array:
	var fields := PackedInt64Array()
	fields.resize(FIELD_COUNT)
	fields.fill(-1)
	fields[ID] = frame
	fields[TICKS] = 0
	fields[TICK_SCRIPTS] = 0
	fields[TICK_MAX] = 0
	return fields
