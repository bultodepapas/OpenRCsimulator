## UI-34c: deterministic worker ownership, admission gating, ABA and headless draw seam.
extends SceneTree

const Preparation := preload("res://ui/home_flight_preparation.gd")
const Broker := preload("res://ui/home_preview_resources.gd")
const SceneLoad := preload("res://ui/flight_scene_load.gd")

class Gate extends RefCounted:
	var entered := Semaphore.new()
	var release := Semaphore.new()
	var result: PackedScene
	func load_scene(_path: String, _hint: String) -> Resource:
		entered.post()
		release.wait()
		return result

class Host extends Node:
	var gate: Gate
	var starts := 0
	func _new_flight_scene_load() -> Node:
		starts += 1
		var job := SceneLoad.new()
		job.load_resource = gate.load_scene
		return job

class TrimStub extends RefCounted:
	var active := false
	var complete := false
	var starts := 0
	var abandoned := 0
	func prepare(_path: String, _id: String) -> Dictionary:
		starts += 1
		active = true
		complete = false
		return {kind = "pending"}
	func poll() -> Dictionary:
		return {active = active, complete = complete, adopted = false}
	func abandon() -> void:
		abandoned += 1
		active = false

var _checks := 0
var _failed := 0
var _callbacks: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		printerr("FAIL ", label)
	else:
		print("ok ", label)

func _frames(count := 3) -> void:
	for _frame in count:
		await process_frame

func _ready_callback(_ok: bool, label: String) -> void:
	_callbacks.append(label)

func _new_fixture() -> Dictionary:
	var host := Host.new()
	var broker := Broker.new()
	var surface := Control.new()
	var prep := Preparation.new()
	var gate := Gate.new()
	var scene := PackedScene.new()
	var source := Node.new()
	scene.pack(source)
	source.free()
	gate.result = scene
	host.gate = gate
	root.add_child(host)
	host.add_child(broker)
	host.add_child(surface)
	prep.configure(host, broker)
	prep.mode = "scene"
	prep.delay_msec = 0
	root.add_child(prep)
	prep.observe_home(surface)
	return {host = host, broker = broker, surface = surface, prep = prep, gate = gate}

func _wait_started(gate: Gate) -> bool:
	for _frame in 300:
		if gate.entered.try_wait():
			return true
		await process_frame
	return false

func _wait_drained(prep: Node) -> void:
	for _frame in 300:
		if not is_instance_valid(prep) or prep.is_drained():
			return
		await process_frame

func _run() -> void:
	var f := _new_fixture()
	var prep: Node = f.prep
	var broker: Node = f.broker
	prep.tick(true, false, "A", "A")
	_check("headless Home cannot prepare before explicit draw seam", f.host.starts == 0)
	prep.mark_home_drawn()
	prep.delay_msec = 350
	prep.intent_changed()
	prep.tick(true, false, "A", "A")
	_check("stable intent delay blocks admission", f.host.starts == 0)
	prep.delay_msec = 0
	prep.tick(true, true, "A", "A")
	prep.tick(false, false, "A", "A")
	_check("pending preview and obscured Home block admission", f.host.starts == 0)
	prep.tick(true, false, "A", "A")
	_check("eligible Home starts one scene worker", await _wait_started(f.gate))
	broker.retain_loaded("cached", f.gate.result)
	broker.request("cached", _ready_callback.bind("obsolete cache"))
	broker.request("", _ready_callback.bind("latest procedural"))
	_check("cache and procedural builders are gated while scene worker is active", _callbacks.is_empty() and broker._active_path.is_empty())
	prep.tick(true, false, "B", "B")
	prep.tick(true, false, "A", "A")
	_check("A to B to A reuses one common scene worker", f.host.starts == 1)
	_check("Fly adopts the pending scene before its resource request", prep.adopt())
	broker.request("", _ready_callback.bind("Fly resource"))
	f.gate.release.post()
	await _wait_drained(prep)
	_check("adopted scene drains while latest Fly resource waits", _callbacks == ["Fly resource"] and broker.retained(prep.FLIGHT_SCENE) != null)
	_check("one result shares existing two-resource bound", broker._resources.size() <= 2 and prep.snapshot().scene_completed == 1 and prep.snapshot().scene_adopted == 1)
	prep.shutdown()
	f.host.queue_free()
	await _frames()

	# A raw owner free cannot destroy the thread; paused-tree shutdown still drains.
	f = _new_fixture()
	prep = f.prep
	prep.mark_home_drawn()
	prep.tick(true, false, "A", "A")
	var started := await _wait_started(f.gate)
	var prep_ref: WeakRef = weakref(prep)
	var job_ref: WeakRef = weakref(prep._scene_job)
	f.host.free()
	paused = true
	await _frames()
	_check("raw owner free preserves root-owned scene worker while paused", started and prep_ref.get_ref() != null and job_ref.get_ref() != null)
	f.gate.release.post()
	for _frame in 300:
		if prep_ref.get_ref() == null and job_ref.get_ref() == null:
			break
		await process_frame
	_check("orphan coordinator and worker drain and free in paused tree", prep_ref.get_ref() == null and job_ref.get_ref() == null)
	paused = false

	# Keep a pending A through ABA; replace completed A only after B settles.
	f = _new_fixture()
	prep = f.prep
	prep.mode = "trim"
	var trim := TrimStub.new()
	prep.trim_prepare = trim.prepare
	prep.trim_poll = trim.poll
	prep.trim_abandon = trim.abandon
	prep.mark_home_drawn()
	prep.tick(true, false, "A", "A")
	prep.tick(true, false, "B", "B")
	prep.tick(true, false, "A", "A")
	_check("pending numeric A survives ABA without discard", trim.starts == 1 and trim.abandoned == 0)
	trim.complete = true
	await _frames()
	prep.tick(true, false, "B", "B")
	await _frames()
	prep.tick(true, false, "B", "B")
	_check("settled B replaces completed private A once", trim.starts == 2 and trim.abandoned == 1)
	prep.cancel_launch()
	await _frames()
	prep.observe_home(f.surface)
	prep.tick(true, false, "B", "B")
	_check("cancelled numeric selection can prepare again after drain", trim.starts == 3 and trim.abandoned == 2)
	prep.shutdown()
	await _wait_drained(prep)
	f.host.queue_free()
	await _frames()
	_check("numeric shutdown abandons and drains its slot", not trim.active and trim.abandoned == 3)
	print("Home flight preparation: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed else 0)
