extends SceneTree
## VQ-01c / graphics audit F02: shared ownership of per-viewport GPU render-time measurement.
## A recording fake replaces the RenderingServer write, so ownership is proven without a GPU.

const TimingLease := preload("res://render/render_timing_lease.gd")
const Probe := preload("res://debug/render_probe.gd")
const FrameDiagnostics := preload("res://render/frame_diagnostics.gd")

var _checks := 0
var _failures := 0
var _writes: Array = [] # [rid, enabled]
var _state: Dictionary = {} # rid -> last written value


func _initialize() -> void:
	await _run()
	TimingLease.reset_for_tests()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _record(rid: RID, enabled: bool) -> void:
	_writes.append([rid, enabled])
	_state[rid] = enabled


func _fresh() -> void:
	TimingLease.reset_for_tests()
	TimingLease.set_setter_for_tests(_record)
	_writes.clear()
	_state.clear()


func _on(viewport: Viewport) -> bool:
	return bool(_state.get(viewport.get_viewport_rid(), false))


func _run() -> void:
	var a := SubViewport.new()
	var b := SubViewport.new()
	root.add_child(a)
	root.add_child(b)
	await process_frame
	_check("headless SubViewports have render RIDs", a.get_viewport_rid().is_valid() and b.get_viewport_rid().is_valid())

	# Both stop orders: the first consumer to stop never disables the second.
	for order: String in ["first-in-first-out", "last-in-first-out"]:
		_fresh()
		var first := TimingLease.acquire(a, "frame_diagnostics")
		var second := TimingLease.acquire(a, "render_probe")
		_check("%s: tokens are distinct and positive" % order, first > 0 and second > 0 and first != second)
		_check("%s: only the first lease writes the flag" % order, _writes.size() == 1 and _on(a))
		var stop_first := first if order == "first-in-first-out" else second
		var stop_last := second if order == "first-in-first-out" else first
		TimingLease.release(stop_first)
		_check("%s: measurement survives the first stop" % order, _on(a) and _writes.size() == 1 and TimingLease.holders(a) == 1)
		TimingLease.release(stop_last)
		_check("%s: the last stop disables measurement" % order, not _on(a) and _writes.size() == 2 and TimingLease.holders(a) == 0)

	# Duplicate and unknown releases are inert.
	_fresh()
	var token := TimingLease.acquire(a, "x")
	_check("first release is live", TimingLease.release(token))
	var writes_after := _writes.size()
	_check("repeated release reports dead and writes nothing", not TimingLease.release(token) and _writes.size() == writes_after)
	_check("unknown and zero tokens are inert", not TimingLease.release(0) and not TimingLease.release(987654) and _writes.size() == writes_after)
	_check("invalid viewport cannot be leased", TimingLease.acquire(null, "x") == 0)

	# Viewports are independent.
	_fresh()
	var on_a := TimingLease.acquire(a, "x")
	var on_b := TimingLease.acquire(b, "y")
	TimingLease.release(on_a)
	_check("releasing one viewport leaves the other measured", not _on(a) and _on(b))
	_check("owners are reported per viewport", TimingLease.owners(b) == ["y"] and TimingLease.owners(a).is_empty())
	TimingLease.release(on_b)

	# A detached but live SubViewport is still switched off on release.
	_fresh()
	var detached := SubViewport.new()
	root.add_child(detached)
	await process_frame
	var detached_token := TimingLease.acquire(detached, "x")
	root.remove_child(detached)
	TimingLease.release(detached_token)
	_check("detached live viewport is switched off", not _on(detached) and _writes.size() == 2)
	detached.free()

	# A freed viewport is retired without writing to its stale RID.
	_fresh()
	var doomed := SubViewport.new()
	root.add_child(doomed)
	await process_frame
	var doomed_rid := doomed.get_viewport_rid()
	var doomed_token := TimingLease.acquire(doomed, "x")
	doomed.free()
	_check("freed viewport lease is no longer held", not TimingLease.is_held(doomed_token))
	TimingLease.release(doomed_token)
	var stale_writes := 0
	for write: Array in _writes:
		if write[0] == doomed_rid and not write[1]:
			stale_writes += 1
	_check("freed viewport RID is never written on release", stale_writes == 0 and _writes.size() == 1)
	var after_prune := TimingLease.acquire(a, "x")
	_check("a later acquire prunes the freed entry and still works", after_prune > 0 and _on(a))
	TimingLease.release(after_prune)

	# RenderProbe: turning the probe off keeps another consumer's lease, and departed SubViewports are released.
	_fresh()
	var probe := Probe.new(a)
	var nested := SubViewport.new()
	a.add_child(nested)
	await process_frame
	var diagnostics_lease := TimingLease.acquire(a, "frame_diagnostics")
	probe.measuring = true # available() is false headless; drive the lease path directly.
	probe._hold(a)
	probe.sample()
	_check("probe holds the root and its SubViewport", TimingLease.holders(a) == 2 and _on(nested) and TimingLease.holders(nested) == 1)
	probe._hold(a)
	probe.sample()
	_check("repeated probe holds are idempotent", TimingLease.holders(a) == 2 and TimingLease.holders(nested) == 1)
	a.remove_child(nested)
	probe.sample()
	_check("a SubViewport leaving the probed tree is released", not _on(nested) and TimingLease.holders(nested) == 0)
	a.add_child(nested)
	probe.sample()
	_check("a returning SubViewport is measured again", _on(nested))
	probe.set_measure(false)
	_check("probe off keeps the diagnostics observer measuring", _on(a) and TimingLease.holders(a) == 1 and not _on(nested))
	TimingLease.release(diagnostics_lease)
	_check("the last observer turns the root off", not _on(a))
	nested.free()

	# FrameDiagnostics releases through the lease and never writes after its viewport is freed.
	_fresh()
	var observed := SubViewport.new()
	root.add_child(observed)
	await process_frame
	var observer = FrameDiagnostics.new()
	observer.start(observed)
	var probe_lease := TimingLease.acquire(observed, "render_probe")
	observer.stop()
	_check("diagnostics stop leaves a probe's lease measuring", TimingLease.holders(observed) == 1 and _on(observed))
	TimingLease.release(probe_lease)
	observer.stop()
	_check("diagnostics stop is idempotent through the lease", not _on(observed))
	observed.free()

	a.free()
	b.free()


func _check(label: String, success: bool, detail: String = "") -> void:
	_checks += 1
	if success:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
