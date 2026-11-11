extends SceneTree
## Event completion must not relabel interrupted fixed-duration benchmark data.
const Samples := preload("frames.gd")
var failed := 0


func _initialize() -> void:
	var output := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--test-output="): output = argument.trim_prefix("--test-output=")
	if output.is_empty() or DirAccess.dir_exists_absolute(output):
		printerr("Provide a fresh --test-output directory")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var samples := Samples.new()
	_check(samples.configure(0, 60, 100, output.path_join("success.frames.jsonl")), "configure stream")
	_check(samples.record_frame(0.016, 16000, 1000000, {phase_index = 0}), "first frame")
	_check(samples.record_frame(0.020, 20000, 1020000, {phase_index = 1}), "second contiguous frame")
	var report := samples.seal_event(true, "scenario_finished")
	_check(report.complete and report.frames == 2, "complete event-bound stream")
	_check(report.format == "openrc-godtest-frames-v1" and report.collector_format == "openrc-frametimes v3", "distinct consumer contract")
	_check(report.requested_seconds == null and report.collection_bound_seconds == 60, "duration bound is not measured duration")
	_check(report.stream.complete and report.stream.frames == 2 and report.stream.sha256.length() == 64, "sealed stream receipt")
	var interrupted := Samples.new()
	_check(interrupted.configure(0, 60, 100, output.path_join("interrupted.frames.jsonl")), "configure interruption")
	interrupted.record_frame(0.01, 10000, 1000000, {})
	var prefix := interrupted.seal_event(false, "aircraft route abandoned")
	_check(not prefix.complete and not prefix.stream.complete and prefix.frames == 1, "interruption preserves partial frame")
	var bounded := Samples.new()
	bounded.configure(0, 60, 1, output.path_join("bounded.frames.jsonl"))
	bounded.record_frame(0.01, 10000, 1000000, {})
	_check(not bounded.record_frame(0.01, 10000, 1010000, {}), "frame cap refused")
	var capped := bounded.seal_event(true, "cannot repair a failed collector")
	_check(not capped.complete and not capped.stream.complete, "event success cannot promote capped data")
	print("GOD_FRAME_TESTS: ", failed, " failed")
	quit(0 if failed == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failed += 1
		printerr("FAIL: ", message)
