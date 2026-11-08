## Disk export bounds row-text serialization; metadata has a separate lifetime.
extends SceneTree

const Trace := preload("res://sim/trace.gd")

class DiskOnlyTrace extends Trace:
	var whole_csv_calls := 0
	func to_csv() -> String:
		whole_csv_calls += 1
		return "whole-record serialization must not be used by save"

var _failures := 0
var _checks := 0


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL " + label)


func _initialize() -> void:
	var path := "user://test-traces/streaming-%d.csv" % OS.get_process_id()
	var source := Trace.new()
	source.meta = {scenario = "streaming", visual_context = "árbol — 飛行", dt_s = 1.0 / 240.0}
	var body := PackedFloat64Array([10, -20, -30, 15, 0, 0, 1, 0, 0, 0, 0, 0, 0])
	var loads := PackedFloat64Array([0, 0, 0, 0, 0, 0])
	var controls := PackedFloat64Array([0.125, -0.25, 0, 0.75])
	# Empty, singleton, multiple batches and final partial batch use the same bytes.
	for count in [0, 1, 150, 1201]:
		source.clear()
		for tick in count:
			source.record(tick, tick / 240.0, body, loads, controls)
		var expected := source.to_csv().to_utf8_buffer()
		_check("save %d rows" % count, source.save(path) == OK)
		_check("exact UTF-8 and LF for %d rows" % count, FileAccess.get_file_as_bytes(path) == expected)
		_check("save retains %d rows" % count, source.row_count() == count)
	var disk_only := DiskOnlyTrace.new()
	disk_only.meta = source.meta.duplicate(true)
	disk_only._rows = source._rows.duplicate()
	_check("disk export succeeds without whole CSV", disk_only.save(path) == OK)
	_check("disk export never calls to_csv", disk_only.whole_csv_calls == 0)
	_check("disk-only output matches reference", FileAccess.get_file_as_bytes(path) == source.to_csv().to_utf8_buffer())
	# Refusal must happen before opening/truncating an existing destination.
	var before := FileAccess.get_file_as_bytes(path)
	disk_only._invalid_weather = true
	_check("malformed trace rejected", disk_only.save(path) == ERR_INVALID_DATA)
	_check("invalid trace preserves destination", FileAccess.get_file_as_bytes(path) == before)
	disk_only._invalid_weather = false
	_check("unwritable parent reports failure", disk_only.save(path.path_join("child.csv")) != OK)
	_check("failed save retains all samples", disk_only.row_count() == source.row_count())
	_check("retry succeeds", disk_only.save(path) == OK)
	_check("retry preserves all bytes", FileAccess.get_file_as_bytes(path) == before)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("trace streaming: %d checks, %d failed" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
