extends SceneTree
## PT1h-R15-S3 (F0): the main-loop phase split sums exactly to the observer interval and rejects incomplete input.

const FramePhases := preload("res://render/frame_phases.gd")

var _checks: int = 0
var _failures: int = 0


class Observer extends Node:
	var probe: RefCounted
	var previous_usec := 0
	var splits: Array[Dictionary] = []
	var intervals := PackedInt64Array()

	func _process(_delta: float) -> void:
		var now := Time.get_ticks_usec()
		if previous_usec > 0:
			splits.append(probe.split(previous_usec, now))
			intervals.append(now - previous_usec)
		previous_usec = now


## The debug bridge releases its lease while its parent is unwinding the tree.
class ExitOwner extends Node:
	var probe: RefCounted
	var brackets_had_exited := false

	func _exit_tree() -> void:
		var bracket: Node = probe._low
		brackets_had_exited = not bracket.is_inside_tree() and bracket.get_parent() == get_parent()
		FramePhases.release(probe)


func _initialize() -> void:
	await _run_checks()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _run_checks() -> void:
	var names := FramePhases.metric_names()
	_check("metric schema has eight durations and seven counts", FramePhases.DURATIONS.size() == 8 and names.size() == 15, str(names))

	# Iteration 10: two physics ticks are not needed; it only provides the previous tail.
	var probe = FramePhases.new()
	_check("a fresh probe returns the full schema as invalid", _schema_ok(probe.split_at(11, 1000, 2000), names)
		and probe.split_at(11, 1000, 2000).phase_valid == 0)
	probe.mark_process_signal_at(10, 900)
	probe.mark_process_low_at(10, 950)
	probe.mark_process_high_at(10, 1200) # observer ran at 1000
	probe.mark_pre_draw_at(10, 1300)
	probe.mark_post_draw_at(10, 4300)
	# Iteration 11: two ticks, then process.
	probe.mark_physics_start_at(11, 5000)
	probe.mark_physics_end_at(11, 5800)
	probe.mark_physics_start_at(11, 6000)
	probe.mark_physics_end_at(11, 7000)
	probe.mark_process_signal_at(11, 7100)
	probe.mark_process_low_at(11, 7400)
	var split: Dictionary = probe.split_at(11, 1000, 9000)
	_check("a drawn iteration with two ticks is valid", split.phase_valid == 1 and split.phase_drawn == 1 and split.phase_ticks == 2, str(split))
	_check("durations land in their phases", split.phase_tail_process_usec == 200 and split.phase_tail_engine_usec == 100
		and split.phase_render_usec == 3000 and split.phase_between_usec == 700 and split.phase_physics_usec == 2000
		and split.phase_after_physics_usec == 100 and split.phase_pre_process_usec == 300 and split.phase_process_usec == 1600, str(split))
	_check("durations sum exactly to the interval", _sum(split) == 8000, str(_sum(split)))
	_check("tick script time sums each tick's callback span", split.phase_tick_scripts_usec == 1800 and split.phase_tick_max_usec == 1000, str(split))
	_check("running totals count every completed tick", probe.totals() == {ticks = 2, tick_scripts_usec = 1800}, str(probe.totals()))
	_check("a valid split keeps the schema", _schema_ok(split, names))
	_check("splitting is read-only", probe.split_at(11, 1000, 9000) == split)

	# Iteration 12: previous iteration (11) did not draw; no physics ticks in 12.
	probe.mark_process_high_at(11, 9500)
	probe.mark_process_signal_at(12, 12000)
	probe.mark_process_low_at(12, 12100)
	var undrawn: Dictionary = probe.split_at(12, 9000, 13000)
	_check("an undrawn previous iteration runs its tail to the next first callback", undrawn.phase_valid == 1
		and undrawn.phase_drawn == 0 and undrawn.phase_render_usec == 0 and undrawn.phase_between_usec == 0
		and undrawn.phase_tail_engine_usec == 2500, str(undrawn))
	_check("zero ticks leave physics phases empty", undrawn.phase_ticks == 0 and undrawn.phase_physics_usec == 0
		and undrawn.phase_after_physics_usec == 0)
	_check("undrawn split still sums to the interval", _sum(undrawn) == 4000, str(_sum(undrawn)))

	_check("a skipped iteration is invalid", probe.split_at(13, 9000, 13000).phase_valid == 0)
	_check("an observer later than the previous last callback is invalid", probe.split_at(12, 9600, 13000).phase_valid == 0)
	_check("an observer that skipped the previous iteration is invalid", probe.split_at(12, 7000, 13000).phase_valid == 0)
	_check("a non-advancing interval is invalid", probe.split_at(12, 13000, 13000).phase_valid == 0)
	var disordered = FramePhases.new()
	disordered.mark_process_signal_at(1, 100)
	disordered.mark_process_low_at(1, 110)
	disordered.mark_process_high_at(1, 300)
	disordered.mark_pre_draw_at(1, 400)
	disordered.mark_post_draw_at(1, 500)
	disordered.mark_physics_start_at(2, 450) # earlier than the previous draw ended
	disordered.mark_physics_end_at(2, 600)
	disordered.mark_process_signal_at(2, 700)
	disordered.mark_process_low_at(2, 710)
	var rejected: Dictionary = disordered.split_at(2, 200, 800)
	_check("out-of-order boundaries are rejected with zeroed values", rejected.phase_valid == 0 and _sum(rejected) == 0, str(rejected))
	var unmatched = FramePhases.new()
	unmatched.mark_physics_end_at(3, 100)
	_check("a tick end without its start is not counted", unmatched._current[FramePhases.TICKS] == 0)

	# Live engine: an observer at priority 0 splits each real iteration. The root enters the tree after _initialize.
	await process_frame
	var live = FramePhases.new()
	var detached := Node.new()
	_check("a root outside the tree is refused", not FramePhases.new().start(detached))
	detached.free()
	_check("probe starts once on a live root", live.start(root) and not live.start(root))
	var observer := Observer.new()
	observer.probe = live
	root.add_child(observer)
	for _i in 40:
		await process_frame
		OS.delay_usec(1500) # give the main loop measurable phases and physics catch-up
	var valid := 0
	var exact := true
	var nonnegative := true
	var ticks := 0
	for index: int in observer.splits.size():
		var row: Dictionary = observer.splits[index]
		if not _schema_ok(row, names):
			exact = false
		if row.phase_valid != 1:
			continue
		valid += 1
		ticks += int(row.phase_ticks)
		exact = exact and _sum(row) == observer.intervals[index]
		for key: String in FramePhases.DURATIONS:
			nonnegative = nonnegative and int(row[key]) >= 0
	_check("live iterations produce valid splits", valid >= 20, "%d of %d" % [valid, observer.splits.size()])
	_check("live valid splits sum exactly to their intervals", exact)
	_check("live durations are non-negative", nonnegative)
	_check("live splits observe physics ticks", ticks > 0, str(ticks))
	_check("brackets sit at the extreme priorities", root.get_node_or_null("FramePhasesFirst") != null
		and root.get_node("FramePhasesFirst").process_priority == FramePhases.MIN_PRIORITY
		and root.get_node("FramePhasesLast").process_physics_priority == FramePhases.MAX_PRIORITY)
	live.stop()
	await process_frame
	await process_frame
	_check("stop removes brackets and signal connections", root.get_node_or_null("FramePhasesFirst") == null
		and root.get_node_or_null("FramePhasesLast") == null and not process_frame.is_connected(live._on_process_frame)
		and not RenderingServer.frame_post_draw.is_connected(live._on_post_draw))
	_check("metadata names the format", live.metadata().format == FramePhases.FORMAT and not live.metadata().started)
	var early = FramePhases.new()
	_check("a probe stopped before its deferred attach adds no node", early.start(root))
	early.stop()
	await process_frame
	_check("no bracket is left behind", root.get_node_or_null("FramePhasesFirst") == null and root.get_node_or_null("FramePhasesLast") == null)
	var first = FramePhases.acquire(root)
	var second = FramePhases.acquire(root)
	_check("observers share one probe", first != null and first == second and first.is_started())
	FramePhases.release(second)
	_check("the shared probe runs until its last user releases it", first.is_started())
	FramePhases.release(first)
	_check("the last release stops the shared probe", not first.is_started())
	var third = FramePhases.acquire(root)
	_check("a later acquire starts a fresh probe", third != null and third != first and third.is_started())
	FramePhases.release(third)
	await process_frame
	observer.queue_free()
	await process_frame
	# Brackets attach after their consumer and exit before it. Directly freeing them
	# from the consumer's exit callback would mutate the parent's active child loop.
	var container := Node.new()
	root.add_child(container)
	var owner_on_exit := ExitOwner.new()
	container.add_child(owner_on_exit)
	owner_on_exit.probe = FramePhases.acquire(container)
	await process_frame
	var first_bracket := container.get_node("FramePhasesFirst")
	var last_bracket := container.get_node("FramePhasesLast")
	root.remove_child(container)
	_check("the last lease releases during parent teardown", owner_on_exit.brackets_had_exited
		and not owner_on_exit.probe.is_started())
	_check("a still-parented bracket is queued for deletion", is_instance_valid(last_bracket)
		and last_bracket.is_queued_for_deletion())
	await process_frame
	await process_frame
	_check("both brackets are retired while the detached parent survives",
		not is_instance_valid(first_bracket) and not is_instance_valid(last_bracket) and is_instance_valid(container))
	container.free()


func _sum(split: Dictionary) -> int:
	var total := 0
	for key: String in FramePhases.DURATIONS:
		total += int(split.get(key, 0))
	return total


func _schema_ok(split: Dictionary, names: Array[String]) -> bool:
	if split.size() != names.size():
		return false
	for key: String in names:
		if not split.has(key):
			return false
		var value: Variant = split[key]
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			return false
	return true


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: %s %s" % [label, detail])
