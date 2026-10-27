extends SceneTree

# Samples the spatial wind field on the declared position/time grid of
# tests/fixtures/spatial_wind_mode_grid_before.json, using the configs authored
# in tests/test_spatial_wind_field.gd of the project it runs in. Run it inside a
# project built by reconstruct_preopt.sh; merge_os_capture.py adds the result to
# the fixture. It never edits the fixture itself.
# Usage: godot --headless --path <project> --script res://capture_spatial_wind_mode_grid.gd -- <out.json>

const SpatialField := preload("res://physics/wind_spatial_field.gd")
const FIXTURE_PATH := "res://tests/fixtures/spatial_wind_mode_grid_before.json"
const TEST_PATH := "res://tests/test_spatial_wind_field.gd"
const SOURCES := [
	"res://physics/wind_spatial_field.gd",
	"res://physics/wind_spatial_config.gd",
	"res://physics/wind_thermal_field.gd",
	"res://tests/test_spatial_wind_field.gd",
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or FileAccess.file_exists(args[0]):
		printerr("usage: -- <new-out.json> (existing outputs are refused)")
		quit(2)
		return
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH))
	var test_object: Object = load(TEST_PATH).new()
	var configs: Array = test_object.call("_mode_grid_fixture_configs")
	test_object.free()
	var cases := []
	for item: Dictionary in configs:
		var built: Dictionary = SpatialField.build(item.raw)
		if not built.ok:
			printerr("build failed ", item.id, " ", built.errors)
			quit(3)
			return
		var samples := []
		for time_s: float in fixture.times_s:
			for position: Array in fixture.positions_ned_m:
				var actual: Dictionary = built.field.sample_world(PackedFloat64Array(position), time_s)
				var hex := ""
				if actual.get("ok", false):
					hex = (actual.wind_ned_mps as PackedFloat64Array).to_byte_array().hex_encode()
				samples.append({"position_ned_m": position, "time_s": time_s, "wind_bytes_hex": hex})
		cases.append({"id": item.id, "spatial_hash": built.field.content_hash(),
			"thermal_hash": built.field.thermal_content_hash(), "samples": samples})
	var source_sha := {}
	for path: String in SOURCES:
		source_sha[path.trim_prefix("res://")] = FileAccess.get_sha256(path)
	var version: Dictionary = Engine.get_version_info()
	var report := {
		"format": "openrc-spatial-mode-grid-capture v1",
		"os": OS.get_name(),
		"engine": "%d.%d.%s.%s.%s" % [version.major, version.minor, version.status, version.build,
			str(version.hash).left(9)],
		"source_sha256": source_sha,
		"fixtures": cases,
	}
	var out := FileAccess.open(args[0], FileAccess.WRITE)
	out.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	out.close()
	print("captured ", cases.size(), " cases on ", OS.get_name(), " to ", args[0])
	quit(0)
