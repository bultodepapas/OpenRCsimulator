extends SceneTree

const TraceRecovery := preload("res://ui/trace_recovery.gd")
const AirRecorder := preload("res://sim/recorder.gd")
const HeliRecorder := preload("res://sim/rotorcraft_recorder.gd")


class ManualRecorder extends RefCounted:
	var recording := false
	var recording_generation := 0
	var note := ""
	var stop_calls := 0
	var should_fail := true

	func start() -> void:
		recording_generation += 1
		recording = true

	func stop() -> Error:
		stop_calls += 1
		recording = false
		note = "trace save failed: error %d" % ERR_CANT_CREATE if should_fail else "trace saved: fixture"
		return ERR_CANT_CREATE if should_fail else OK


class LegacyRecorder extends RefCounted:
	var recording := true
	var note := ""
	var stop_calls := 0

	func stop() -> Error:
		stop_calls += 1
		recording = false
		note = "trace save failed: error %d" % ERR_CANT_CREATE
		return ERR_CANT_CREATE


class GroundAdapter extends RefCounted:
	var recording := false
	var recording_generation := 0
	var note := ""
	var unsaved := false
	var should_fail := true
	var allow_discard := false
	var stop_calls := 0
	var discard_calls := 0

	func start() -> void:
		recording_generation += 1
		recording = true
		unsaved = true

	func has_unsaved_recording() -> bool:
		return unsaved

	func stop() -> Error:
		stop_calls += 1
		recording = false
		if should_fail:
			note = "ground save failed"
			return ERR_CANT_CREATE
		unsaved = false
		note = "ground saved"
		return OK

	func discard_unsaved(expected_generation: int) -> bool:
		discard_calls += 1
		if not allow_discard or expected_generation != recording_generation:
			return false
		unsaved = false
		return true


class FakeSimulation extends Node:
	signal stepped(tick: int, time_s: float, state: PackedFloat64Array, loads: PackedFloat64Array, inputs: PackedFloat64Array, aux: PackedFloat64Array)
	var tick := 0
	var state := PackedFloat64Array([0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0])
	var last_loads := PackedFloat64Array([0, 0, 0, 0, 0, 0])
	var inputs := PackedFloat64Array([0, 0, 0, 0])
	var aux := PackedFloat64Array([0, 0, 0, 0])
	var continuous := PackedFloat64Array([0, 0, 0, 0, 0, 0])

	func time() -> float:
		return float(tick) * dt()

	func dt() -> float:
		return 1.0 / 240.0


var checks := 0
var failures := 0


func check(label: String, condition: bool) -> void:
	checks += 1
	print(("ok   " if condition else "FAIL ") + label)
	if not condition:
		failures += 1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_manual_generations()
	_ground_generations()
	_legacy_and_weak_refs()
	_real_generations()
	print("Trace departure generations: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _manual_generations() -> void:
	var recovery := TraceRecovery.new()
	var recorder := ManualRecorder.new()
	recorder.start()
	var first: Dictionary = recovery.save_if_recording(recorder)
	check("first recording save failure is pending", not first.ok and first.generation == 1 and recovery.has_pending(recorder) and recorder.stop_calls == 1)
	check("same generation is not auto-retried", not recovery.save_if_recording(recorder).ok and recorder.stop_calls == 1)
	check("explicit discard resolves the first generation", recovery.discard(recorder, 1) and recovery.pending_count() == 0 and recovery.discarded_count() == 1)
	recorder.start()
	recorder.stop() # A manually stopped new recording has the same failure note.
	var second: Dictionary = recovery.save_if_recording(recorder)
	check("new manually failed recording is not hidden by the old discard", not second.ok and second.generation == 2 and recovery.has_pending(recorder))
	check("a stale dialog cannot discard or retry the new failure", not recovery.discard(recorder, 1) and not recovery.retry(recorder, 1).ok and recovery.has_pending(recorder))
	check("new generation discard is explicit", recovery.discard(recorder, 2))
	recorder.start()
	var third: Dictionary = recovery.save_if_recording(recorder)
	check("new active recording is stopped independently", not third.ok and third.generation == 3 and recorder.stop_calls == 3)
	recorder.should_fail = false
	recorder.stop() # The pilot manually saved after choosing Stay.
	var count_after_manual := recorder.stop_calls
	check("manual save after Stay reconciles pending without retry", recovery.save_if_recording(recorder).ok and not recovery.has_pending(recorder) and recorder.stop_calls == count_after_manual)

	var replaced := ManualRecorder.new()
	replaced.start()
	recovery.save_if_recording(replaced)
	replaced.start()
	replaced.stop()
	var new_pending: Dictionary = recovery.save_if_recording(replaced)
	check("a new generation supersedes old pending identity", not new_pending.ok and new_pending.generation == 2 and recovery.pending_count() == 1)
	check("stale pending actions refuse the replacement generation", not recovery.discard(replaced, 1) and not recovery.retry(replaced, 1).ok and recovery.has_pending(replaced))


func _ground_generations() -> void:
	var recovery := TraceRecovery.new()
	var adapter := GroundAdapter.new()
	adapter.start()
	adapter.recording = false # Existing stopped/unexported recording.
	var first: Dictionary = recovery.save_if_recording(adapter)
	check("stopped unexported adapter is saved once", not first.ok and first.generation == 1 and adapter.stop_calls == 1)
	check("pending adapter does not auto-retry", not recovery.save_if_recording(adapter).ok and adapter.stop_calls == 1)
	check("failed explicit retry retains pending and data", not recovery.retry(adapter, 1).ok and adapter.stop_calls == 2 and adapter.unsaved and recovery.has_pending(adapter))
	check("adapter discard refusal retains pending and data", not recovery.discard(adapter, 1) and adapter.unsaved and recovery.has_pending(adapter) and adapter.discard_calls == 1)
	adapter.allow_discard = true
	check("adapter discard accepts only its captured generation", recovery.discard(adapter, 1) and not adapter.unsaved and not recovery.has_pending(adapter))
	adapter.start()
	adapter.recording = false
	var second: Dictionary = recovery.save_if_recording(adapter)
	check("new stopped adapter generation remains independently pending", not second.ok and second.generation == 2 and adapter.unsaved)
	check("stale adapter discard does not touch replacement data", not recovery.discard(adapter, 1) and adapter.unsaved and recovery.has_pending(adapter))
	adapter.should_fail = false
	adapter.stop()
	var calls_after_manual := adapter.stop_calls
	check("manual ground export reconciles pending without re-export", recovery.save_if_recording(adapter).ok and adapter.stop_calls == calls_after_manual and not recovery.has_pending(adapter))

	adapter.start()
	adapter.should_fail = true
	recovery.save_if_recording(adapter)
	adapter.should_fail = false
	adapter.stop()
	calls_after_manual = adapter.stop_calls
	check("Retry after an external save does not save twice", recovery.retry(adapter, 3).ok and adapter.stop_calls == calls_after_manual and recovery.pending_count() == 0)


func _legacy_and_weak_refs() -> void:
	var recovery := TraceRecovery.new()
	var legacy := LegacyRecorder.new()
	check("legacy recorder failure remains supported", not recovery.save_if_recording(legacy).ok and recovery.generation_of(legacy) == -1)
	check("legacy recorder failure remains pending without automatic retry", not recovery.save_if_recording(legacy).ok and legacy.stop_calls == 1)
	check("legacy recorder can still be discarded", recovery.discard(legacy) and recovery.discarded_count() == 1)
	legacy.recording = true
	check("legacy active recording clears the object-scoped discard", not recovery.save_if_recording(legacy).ok and legacy.stop_calls == 2)
	recovery.discard(legacy)
	var weak: WeakRef = weakref(legacy)
	legacy = null
	check("discard marker does not retain its recorder", weak.get_ref() == null and recovery.discarded_count() == 0)


func _real_generations() -> void:
	var sim := FakeSimulation.new()
	root.add_child(sim)
	var airplane := AirRecorder.new(sim)
	var helicopter := HeliRecorder.new(sim)
	check("real recorders begin at generation zero", airplane.recording_generation == 0 and helicopter.recording_generation == 0)
	airplane.start({})
	helicopter.start({})
	check("real recorder starts increment the generation", airplane.recording_generation == 1 and helicopter.recording_generation == 1)
	airplane.start({})
	helicopter.start({})
	check("active generations cannot be replaced", airplane.recording_generation == 1 and helicopter.recording_generation == 1)
	airplane.detach()
	helicopter.detach()
	sim.free()
