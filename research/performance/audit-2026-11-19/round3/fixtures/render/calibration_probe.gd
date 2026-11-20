extends SceneTree
const AC := preload("res://render/auto_calibration.gd")
const TestNode := preload("res://calibration_test_node.gd")
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	AC.calibration_path = "user://mixed_workload_probe.cfg"
	AC.clear()
	root.size = Vector2i(3840, 2160)
	root.scaling_3d_scale = 1.0
	root.msaa_3d = Viewport.MSAA_4X
	var before := AC.current_workload(root)
	var session := Node.new()
	root.add_child(session)
	var test := TestNode.new(session, "Synthetic GPU", "high")
	root.add_child(test)
	test.set_process(false)
	test._active_s = AC.WARMUP_S + AC.SAMPLE_S - 0.1
	for i in AC.MIN_SAMPLES:
		test._samples.append(20.0)
		test._cpu_samples.append(1.0)
		test._interval_samples.append(16.0)
	root.size = Vector2i(1920, 1080)
	root.msaa_3d = Viewport.MSAA_DISABLED
	var after := AC.current_workload(root)
	var observed := {}
	test.finished.connect(func(value: Dictionary) -> void: observed.merge(value, true))
	test._process(0.2)
	var stored := AC.load_result("Synthetic GPU", RenderingServer.get_current_rendering_method())
	var needs_final := AC.needed("Synthetic GPU", RenderingServer.get_current_rendering_method(), int(after.get("pixels", 0)), "high", after)
	var matching_before := AC.size_matches(stored, int(before.get("pixels", 0))) and AC.workload_matches(stored, before)
	var matching_after := AC.size_matches(stored, int(after.get("pixels", 0))) and AC.workload_matches(stored, after)
	print("OBS before=", before, " final=", after, " stored=", stored, " needed_final=", needs_final, " matches_before=", matching_before, " matches_final=", matching_after)
	var ok: bool = before.pixels != after.pixels and before.msaa_3d != after.msaa_3d and bool(stored.get("complete", false)) and int(observed.get("samples", 0)) == AC.MIN_SAMPLES and not needs_final and not matching_before and matching_after
	print("mixed workload probe: 1 check, ", 0 if ok else 1, " failed")
	AC.clear()
	session.free()
	quit(0 if ok else 1)
