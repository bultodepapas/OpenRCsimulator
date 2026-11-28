extends SceneTree
## VQ-07h-A0: the automatic graphics decision table, frozen from the code that produced it.
## Every Steam-survey GPU (plus Apple and Mesa names) × platform × resolution must decide exactly as the committed
## snapshot says. A deliberate policy change regenerates it and is reviewed as a diff:
##   <godot> --headless --path app --script res://tests/test_auto_graphics_snapshot.gd -- --write-snapshot

const Report := preload("res://render/auto_graphics_report.gd")
const Policy := preload("res://render/auto_graphics_policy.gd")
const RendererPreference := preload("res://app_state/renderer_preference.gd")
const AutoCalibration := preload("res://render/auto_calibration.gd")
const SceneDetail := preload("res://render/scene_detail.gd")

const SNAPSHOT_PATH := "res://tests/data/auto_graphics_snapshot.json"
const STEAM_PATH := "res://tests/data/steam_gpus_2026_10.json"
const PC_SCREENS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
## Mac panels as Godot reports them (backing store) with their scale and refresh, plus a 1x external display.
const MAC_SCREENS := [[Vector2i(2560, 1600), 2.0, 60.0], [Vector2i(2940, 1912), 2.0, 60.0],
	[Vector2i(3024, 1964), 2.0, 120.0], [Vector2i(3456, 2234), 2.0, 120.0], [Vector2i(1920, 1080), 1.0, 60.0]]
const MAC_ADAPTERS: Array[String] = ["Apple M1 (Apple7)", "Apple M1 Pro (Apple7)", "Apple M1 Max (Apple7)",
	"Apple M2 (Apple8)", "Apple M2 Max (Apple8)", "Apple M3 (Apple9)", "Apple M3 Pro (Apple9)", "Apple M3 Max (Apple9)",
	"Apple M4 (Apple9)", "Apple M4 Pro (Apple9)", "Apple M4 Max (Apple9)", "Apple M5 (Apple10)", "Apple M5 Pro (Apple10)",
	"Apple M5 Max (Apple10)", "Apple M6 (Apple10)", "Apple A18 Pro", "Intel(R) Iris(TM) Plus Graphics 655",
	"AMD Radeon Pro 5500M"]
## The Steam survey's most common desktop CPU class (6 cores / 12 threads); Extreme needs AutoGraphicsPolicy's floor.
const TYPICAL_CPU_THREADS := 12
const LINUX_EXTRA: Array[String] = ["AMD Radeon RX 6600 (radeonsi, navi23, LLVM 17.0.6, DRM 3.57, 6.8.0)",
	"AMD Radeon Graphics (radeonsi, gfx1201, LLVM 19.1.7, DRM 3.61, 6.14.0)",
	"AMD Custom GPU 0405 (radeonsi, vangogh, LLVM 17.0.6, DRM 3.57, 6.8.0)", "Mesa Intel(R) UHD Graphics 620 (WHL GT2)",
	"llvmpipe (LLVM 15.0.7, 256 bits)"]


func _initialize() -> void:
	var table := build_table()
	if "--write-snapshot" in OS.get_cmdline_user_args():
		var file := FileAccess.open(SNAPSHOT_PATH, FileAccess.WRITE)
		file.store_string(JSON.stringify({"format": "openrc-auto-graphics-snapshot v1", "decisions": table}, "\t", true) + "\n")
		file.close()
		print("auto graphics snapshot: wrote %d decisions" % table.size())
		quit(0)
		return
	var stored: Variant = JSON.parse_string(FileAccess.get_file_as_string(SNAPSHOT_PATH))
	var failures := 0
	var checks := 0
	if not stored is Dictionary or not (stored as Dictionary).get("decisions") is Dictionary:
		printerr("FAIL: snapshot missing or invalid: %s" % SNAPSHOT_PATH)
		quit(1)
		return
	var expected: Dictionary = stored.decisions
	for key: String in table:
		checks += 1
		if str(expected.get(key, "<missing>")) != str(table[key]):
			failures += 1
			if failures <= 40:
				printerr("FAIL: %s: snapshot %s, now %s" % [key, expected.get(key, "<missing>"), table[key]])
	for key: String in expected:
		if not table.has(key):
			checks += 1
			failures += 1
			printerr("FAIL: %s is in the snapshot but no longer generated" % key)
	var report := Report.runtime()
	for key: String in ["format", "inputs", "decisions", "applied"]:
		checks += 1
		if not report.has(key):
			failures += 1
			printerr("FAIL: runtime report lacks %s" % key)
	checks += 1
	if not (report.inputs as Dictionary).has("cpu_threads") or not (report.decisions as Dictionary).has("reasons"):
		failures += 1
		printerr("FAIL: runtime report lacks hardware inputs or reasons: %s" % report)
	# A1: one home for thresholds. Older names must alias the policy, never hold their own copies.
	var aliases := [[RendererPreference.HIGH_BUDGET_MS, Policy.HIGH_BUDGET_MS],
		[RendererPreference.MIN_HIGH_VRAM_GB, Policy.MIN_HIGH_VRAM_GB], [RendererPreference.MIN_PIXELS, Policy.MIN_PIXELS],
		[AutoCalibration.DOWN_ABOVE, Policy.CALIBRATION_DOWN_ABOVE], [AutoCalibration.UP_BELOW, Policy.CALIBRATION_UP_BELOW],
		[AutoCalibration.HIGH_REJECT_ABOVE, Policy.CALIBRATION_HIGH_REJECT_ABOVE],
		[AutoCalibration.CPU_BLOCK_UP_ABOVE, Policy.CALIBRATION_CPU_BLOCK_UP_ABOVE],
		[AutoCalibration.INTERVAL_MISS, Policy.CALIBRATION_INTERVAL_MISS],
		[AutoCalibration.INTERVAL_MARGIN_MS, Policy.CALIBRATION_INTERVAL_MARGIN_MS]]
	for pair: Array in aliases:
		checks += 1
		if pair[0] != pair[1]:
			failures += 1
			printerr("FAIL: a threshold drifted from the policy: %s != %s" % [pair[0], pair[1]])
	for source: String in ["res://render/gpu_capability.gd", "res://render/scene_detail.gd", "res://app_state/renderer_preference.gd"]:
		checks += 1
		var text := FileAccess.get_file_as_string(source)
		if text.contains("SCENE_LOW_BELOW := 0") or text.contains("MSAA_OFF_BELOW := 0") or text.contains("HIGH_BUDGET_MS := 4"):
			failures += 1
			printerr("FAIL: %s holds its own copy of a policy threshold" % source)
	# A7: the player-facing summary Settings shows.
	var measured_report := {"inputs": {"gpu": {"matched": true, "provenance": "measured: lab"}},
		"decisions": {"renderer": "high", "scene_detail": "extreme"},
		"applied": {"scene_detail_automatic": {"level": "high"}, "calibration": {"complete": true, "gpu_p95_ms": 9.25}}}
	var cases := [
		[Report.player_summary(measured_report), {"mode": "high", "scene_detail": "high", "estimate": "measured",
			"measured_p95_ms": 9.25}],
		[Report.player_summary({"inputs": {"gpu": {"matched": false, "provenance": "unknown"}},
			"decisions": {"renderer": "standard", "scene_detail": "medium"}, "applied": {}}),
			{"mode": "standard", "scene_detail": "medium", "estimate": "unknown", "measured_p95_ms": 0.0}],
		[Report.player_summary({"inputs": {"gpu": {"matched": true, "provenance": "measured-circular: m1"}},
			"decisions": {"renderer": "standard", "scene_detail": "medium"},
			"applied": {"calibration": {"complete": false, "gpu_p95_ms": 30.0}}}),
			{"mode": "standard", "scene_detail": "medium", "estimate": "extrapolated", "measured_p95_ms": 0.0}],
		[Report.player_summary({"inputs": {"gpu": {"matched": true, "provenance": "benchmark-derived"}},
			"decisions": {"renderer": "standard", "scene_detail": "high"}, "applied": {}}),
			{"mode": "standard", "scene_detail": "high", "estimate": "benchmarks", "measured_p95_ms": 0.0}],
	]
	for pair: Array in cases:
		checks += 1
		if pair[0] != pair[1]:
			failures += 1
			printerr("FAIL: player summary %s != %s" % [pair[0], pair[1]])
	# GFX-IGPU-01: only recognized weak shared-memory GPUs start below full 3D resolution.
	var scale_cases := [
		["Mesa Intel(R) UHD Graphics 630 (CFL GT2)", Policy.LOW_GPU_RENDER_SCALE],
		["Intel(R) UHD Graphics 630 (CML GT2)", Policy.LOW_GPU_RENDER_SCALE],
		["NVIDIA GeForce RTX 3090", "-"],
		["Unknown Example GPU 9000", "-"],
	]
	for scale_case: Array in scale_cases:
		checks += 1
		var first_run := Policy.first_run(str(scale_case[0]), "Linux", 1.0, 60.0, {screen = Vector2i(1920, 1080)})
		if first_run.get("render_scale", "-") != scale_case[1]:
			failures += 1
			printerr("FAIL: first-run render scale for %s: %s, expected %s" % [scale_case[0],
				first_run.get("render_scale", "-"), scale_case[1]])
	checks += 1
	if table.size() < 1500:
		failures += 1
		printerr("FAIL: only %d decisions generated" % table.size())
	print("auto graphics snapshot: %d checks, %d failed (%d decisions)" % [checks, failures, table.size()])
	quit(1 if failures > 0 else 0)


static func build_table() -> Dictionary:
	var survey: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(STEAM_PATH))
	var pc_adapters: Array[String] = []
	for row: Dictionary in survey.rows:
		pc_adapters.append(str(row.name))
	var table := {}
	for os_name: String in ["Windows", "Linux"]:
		var adapters := pc_adapters.duplicate()
		if os_name == "Linux":
			adapters.append_array(LINUX_EXTRA)
		for adapter: String in adapters:
			for screen: Vector2i in PC_SCREENS:
				var decision := Report.decide({adapter = adapter, os = os_name, arm64 = false, screen = screen,
					scale = 1.0, refresh = 60.0, cpu_threads = TYPICAL_CPU_THREADS})
				table["%s|%dx%d|%s" % [os_name, screen.x, screen.y, adapter]] = Report.compact(decision)
	for adapter: String in MAC_ADAPTERS:
		var arm := adapter.begins_with("Apple")
		for entry: Array in MAC_SCREENS:
			var screen: Vector2i = entry[0]
			var decision := Report.decide({adapter = adapter, os = "macOS", arm64 = arm, screen = screen,
				scale = entry[1], refresh = entry[2], cpu_threads = TYPICAL_CPU_THREADS})
			table["macOS|%dx%d@%dx%dHz|%s" % [screen.x, screen.y, int(entry[1]), int(entry[2]), adapter]] = Report.compact(decision)
	return table
