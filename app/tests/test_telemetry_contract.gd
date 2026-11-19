# TELEM-02/04: the client wire contract, hardware classification and frame windows against the canonical schema
# and synthetic fixture generated in research/telemetry (generate_contracts.py, generate_examples.py).
# Run: godot --headless --path . --script res://tests/test_telemetry_contract.gd
extends SceneTree

const Contract := preload("res://telemetry/telemetry_contract.gd")
const Hardware := preload("res://telemetry/telemetry_hardware.gd")
const FrameWindow := preload("res://telemetry/telemetry_frame_window.gd")
const VehicleRoster := preload("res://app_state/vehicle_roster.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")

var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	var research := ProjectSettings.globalize_path("res://").path_join("../research/telemetry").simplify_path()
	var schema: Variant = JSON.parse_string(FileAccess.get_file_as_string(research.path_join("contracts/batch.schema.json")))
	var example: Variant = JSON.parse_string(FileAccess.get_file_as_string(research.path_join("examples/batch.json")))
	_check("canonical schema and example are readable", schema is Dictionary and example is Dictionary)
	if schema is Dictionary and example is Dictionary:
		_schema_parity(schema)
		_golden(_integers(example))
	_rejections()
	_releases()
	_hardware()
	_windows()
	print("all telemetry contract checks passed" if _failures == 0 else "%d failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _schema_parity(schema: Dictionary) -> void:
	var properties: Dictionary = schema["properties"]
	var build: Dictionary = properties["build"]["properties"]
	_check("schema and notice versions match", properties["schema_version"]["const"] == Contract.SCHEMA_VERSION
		and properties["notice_version"]["const"] == Contract.NOTICE_VERSION and build["engine_minor"]["const"] == Contract.ENGINE_MINOR)
	var pattern := str(build["release_id"]["pattern"])
	_check("release pattern is the schema pattern", pattern == Contract.RELEASE_PATTERN, pattern)
	var context: Dictionary = properties["context"]["properties"]
	_check("context keys match in order", Array(context.keys()) == Array(Contract.CONTEXT_KEYS), str(context.keys()))
	for key: String in Contract.CONTEXT_KEYS:
		_check("context %s values match" % key, Array(context[key]["enum"]) == Array(Contract.CONTEXT_VALUES[key]))
	var events: Array = properties["events"]["items"]["oneOf"]
	var performance: Dictionary = events[1]["properties"]
	var activity: Dictionary = events[2]["properties"]
	var vehicles: Array = performance["vehicle_id"]["enum"]
	_check("stock vehicle list matches the schema", vehicles.slice(3) == Array(Contract.STOCK_VEHICLES)
		and vehicles.slice(0, 3) == ["none", "custom", "unknown"], str(vehicles))
	_check("performance keys match", Array(performance.keys()) == Array(Contract.PERFORMANCE_KEYS))
	_check("activity keys match", Array(activity.keys()) == Array(Contract.ACTIVITY_KEYS))
	var accepted: Array = events[2]["allOf"][0]["else"]["properties"]["vehicle_id"]["enum"]
	_check("fixed-wing classifier list matches", accepted == Array(Contract.FIXED_WING_VEHICLES))
	_check("error categories match", Array(events[3]["properties"]["category"]["enum"]) == Array(Contract.ERROR_CATEGORIES))
	_check("modes, phases, outcomes match", Array(performance["mode"]["enum"]) == Array(Contract.MODES)
		and Array(performance["phase"]["enum"]) == Array(Contract.PHASES) and Array(activity["outcome"]["enum"]) == Array(Contract.OUTCOMES))
	# A new stock vehicle must reach the schema (and the receiver) before players can fly it with telemetry on.
	var missing := PackedStringArray()
	for id: String in VehicleRoster.ids():
		if not Catalog.canonical_id(id) in Contract.STOCK_VEHICLES:
			missing.append(id)
	_check("every Home-selectable vehicle is a schema stock vehicle", missing.is_empty(), str(missing))


## The fixture rebuilt from the client's own builders must equal the generated example byte for byte (compactly).
func _golden(example: Dictionary) -> void:
	_check("generated example passes the client check", Contract.check_batch(example) == "", Contract.check_batch(example))
	var window := FrameWindow.new()
	for i: int in 1800:
		window.record(16667 if i < 1200 else 16666, 1)
	var event := window.event(1, "flight", Contract.vehicle_id("f4u-corsair-250"), "steady", true)
	var batch := {"schema_version": 1, "notice_version": Contract.NOTICE_VERSION,
		"session_id": "a".repeat(32), "batch_id": "b".repeat(32),
		"build": {"release_id": "v0.2.7", "channel": "stable", "engine_minor": "4.8"},
		"context": Hardware.context({"os": "Windows", "architecture": "x86_64", "cpu": "Intel(R) Core(TM) i7-9700K",
			"threads": 12, "memory_bytes": 17179869184, "gpu": "NVIDIA GeForce RTX 3090", "renderer": "gl_compatibility",
			"driver": "opengl3", "window_size": Vector2i(1920, 1080), "vsync": DisplayServer.VSYNC_ENABLED, "max_fps": 60,
			"graphics_profile": "custom", "input_class": "rc"}),
		"events": [event]}
	_check("client-built batch encodes exactly like the generated example",
		Contract.encode(batch) == Contract.encode(example), Contract.encode(batch).get_string_from_utf8())


func _rejections() -> void:
	var base := _valid()
	_check("valid base batch", Contract.check_batch(base) == "", Contract.check_batch(base))
	var cases := {
		"extra top-level key": func(b: Dictionary) -> void: b["extra"] = 1,
		"missing context key": func(b: Dictionary) -> void: b.context.erase("vsync"),
		"unknown enum": func(b: Dictionary) -> void: b.context.gpu_family = "nvidia_rtx_4090",
		"float seq": func(b: Dictionary) -> void: b.events[0].seq = 1.0,
		"uppercase session id": func(b: Dictionary) -> void: b.session_id = "A".repeat(32),
		"wrong engine": func(b: Dictionary) -> void: b.build.engine_minor = "4.9",
		"no events": func(b: Dictionary) -> void: b.events = [],
		"seventeen events": _seventeen_events,
		"sequence not increasing": func(b: Dictionary) -> void: b.events = [Contract.session_started(2), Contract.session_started(2)],
		"histogram count mismatch": func(b: Dictionary) -> void: b.events[1].interval_histogram[0] += 1,
		"histogram duration impossible": func(b: Dictionary) -> void: b.events[1].interval_sum_us = 1,
		"complete window under 30 s": _short_complete_window,
		"rendered frames with unavailable counter": func(b: Dictionary) -> void: b.events[1].draw_counter_status = "unavailable",
		"gpu value while not measured": func(b: Dictionary) -> void: b.events[1].gpu_ms = 1.5,
		"fixed-wing counts on unsupported": func(b: Dictionary) -> void: b.events[2].classification = "unsupported",
		"fixed-wing classifier on a car": func(b: Dictionary) -> void: b.events[2].vehicle_id = "mt8-bisonte",
		"null counts on accepted fixed wing": func(b: Dictionary) -> void: b.events[2].takeoffs = null,
		"active seconds over the slice": func(b: Dictionary) -> void: b.events[2].active_seconds = 1801,
		"unknown error category": func(b: Dictionary) -> void: b.events[3].category = "segfault",
		"none vehicle in an activity": func(b: Dictionary) -> void: b.events[2].vehicle_id = "none",
	}
	for label: String in cases:
		var candidate := base.duplicate(true)
		(cases[label] as Callable).call(candidate)
		_check("rejects " + label, Contract.check_batch(candidate) != "")
	var unsupported := base.duplicate(true)
	unsupported.events[2].vehicle_id = "mt8-bisonte"
	unsupported.events[2].classification = "unsupported"
	for key: String in ["takeoffs", "landings", "aircraft_crashes"]:
		unsupported.events[2][key] = null
	_check("accepts an unsupported activity with null counts", Contract.check_batch(unsupported) == "")
	var big := base.duplicate(true)
	big.events = []
	for i: int in 16:
		var w: Dictionary = base.events[1].duplicate(true)
		w.seq = i + 1
		big.events.append(w)
	_check("sixteen windows stay under 32 KiB", Contract.check_batch(big) == "" and Contract.encode(big).size() < Contract.MAX_BODY_BYTES)
	_check("vehicle ids: custom wins, unknown for unlisted", Contract.vehicle_id("f4u-corsair-250", true) == "custom"
		and Contract.vehicle_id("my-own-plane") == "unknown" and Contract.vehicle_id("mt8-bisonte") == "mt8-bisonte")
	var id := Contract.random_id()
	_check("random ids are 32 lowercase hex", RegEx.create_from_string(Contract.ID_PATTERN).search(id) != null and id != Contract.random_id())


func _releases() -> void:
	for tag: String in ["v0.2.8", "v0.1.0-rc2", "v0.1.9-beta.1", "v0.2.0-rc.10", "v12.0.3-alpha7"]:
		_check("release %s accepted" % tag, Contract.valid_release(tag))
	for tag: String in ["0.2.8", "v0.2.8+3.gabc1234", "v0.2.8-dirty", "v0.2", "export-manual", "v0.2.8-rc", "v0.2.8\n", "v0.2.8-preview1"]:
		_check("release %s refused" % tag.c_escape(), not Contract.valid_release(tag))


func _hardware() -> void:
	var cases := [
		["cpu", "Intel(R) Core(TM) i7-9700K CPU @ 3.60GHz", "intel_core"],
		["cpu", "AMD Ryzen 9 5950X 16-Core Processor", "amd_ryzen"],
		["cpu", "Apple M1", "apple_silicon"],
		["cpu", "Intel(R) Xeon(R) W-2295", "other"],
		["cpu", "", "unknown"],
		["gpu", "NVIDIA GeForce RTX 3090", "nvidia_rtx"],
		["gpu", "NVIDIA GeForce GTX 1060 6GB", "nvidia_gtx"],
		["gpu", "AMD Radeon RX 6800 XT", "amd_radeon"],
		["gpu", "Intel(R) Arc(TM) A770 Graphics", "intel_arc"],
		["gpu", "Intel(R) UHD Graphics 630", "intel_integrated"],
		["gpu", "Intel(R) Graphics", "intel_integrated"],
		["gpu", "Mesa Intel(R) Xe Graphics (TGL GT2)", "intel_integrated"],
		["gpu", "Intel(R) Arc(TM) Graphics", "intel_arc"],
		["gpu", "AMD Custom GPU 0405 (RADV VANGOGH)", "amd_radeon"],
		["gpu", "AMD Radeon RX 7800 XT (RADV NAVI32)", "amd_radeon"],
		["gpu", "Intel UHD Graphics / NVIDIA GeForce RTX 3060", "other"],
		["gpu", "Apple M2 Pro", "apple_silicon"],
		["gpu", "llvmpipe (LLVM 15.0.7, 256 bits)", "software"],
		["gpu", "NVIDIA GeForce RTX GTX hybrid", "other"],
		["gpu", "Microsoft Basic Render Driver", "other"],
	]
	for c: Array in cases:
		var got := Hardware.family(c[1], c[0])
		_check("%s %s -> %s" % [c[0], c[1], c[2]], got == c[2], got)
	_check("threads buckets", Hardware.threads_bucket(4) == "le4" and Hardware.threads_bucket(8) == "5_8"
		and Hardware.threads_bucket(16) == "9_16" and Hardware.threads_bucket(32) == "17_plus" and Hardware.threads_bucket(0) == "unknown")
	var gib := 1073741824
	_check("memory buckets use usable bytes", Hardware.ram_bucket(16 * gib) == "9_16" and Hardware.ram_bucket(int(15.7 * gib)) == "9_16"
		and Hardware.ram_bucket(int(7.8 * gib)) == "5_8" and Hardware.ram_bucket(32 * gib) == "17_32"
		and Hardware.ram_bucket(4 * gib) == "le4" and Hardware.ram_bucket(128 * gib) == "65_plus" and Hardware.ram_bucket(-1) == "unknown")
	_check("16:9 resolution classes only", Hardware.resolution_class(Vector2i(1920, 1080)) == "1080p"
		and Hardware.resolution_class(Vector2i(2560, 1440)) == "1440p" and Hardware.resolution_class(Vector2i(3840, 2160)) == "2160p"
		and Hardware.resolution_class(Vector2i(1280, 720)) == "below1080p" and Hardware.resolution_class(Vector2i(5120, 2880)) == "above2160p"
		and Hardware.resolution_class(Vector2i(2560, 1080)) == "other" and Hardware.resolution_class(Vector2i(3200, 1800)) == "other"
		and Hardware.resolution_class(Vector2i.ZERO) == "unknown")
	_check("vsync and frame cap", Hardware.vsync(DisplayServer.VSYNC_MAILBOX) == "mailbox" and Hardware.vsync(-1) == "unknown"
		and Hardware.fps_cap(0) == "unlimited" and Hardware.fps_cap(30) == "le30" and Hardware.fps_cap(144) == "121_plus")
	_check("platform names map explicitly", Hardware.os_family("macOS") == "macos" and Hardware.os_family("FreeBSD") == "other"
		and Hardware.architecture("arm64") == "arm64" and Hardware.architecture("x86_32") == "other"
		and Hardware.driver("d3d12") == "d3d12" and Hardware.renderer("dummy") == "unknown")
	var live := Hardware.context()
	_check("the engine context is closed and valid", Contract.check_context(live) == "", str(live))


func _windows() -> void:
	var w := FrameWindow.new()
	_check("10 ms and 50 ms draws", w.record(10000, 1) == FrameWindow.RECORDED and w.record(50000, 1) == FrameWindow.RECORDED
		and w.interval_sum_us == 60000 and w.rendered_frames == 2 and w.histogram == [0, 1, 0, 1, 0, 0, 0, 0])
	_check("an interval over five seconds is excluded, never clamped", w.record(5000001, 1) == FrameWindow.EXCLUDED
		and w.excluded == 1 and w.interval_count == 2)
	_check("exactly five seconds is a hitch, not a gap", w.record(5000000, 1) == FrameWindow.RECORDED and w.histogram[7] == 1)
	_check("bad input is refused", w.record(0, 1) == FrameWindow.INVALID and w.record(10, -2) == FrameWindow.INVALID)
	var full := FrameWindow.new()
	for i: int in 12:
		full.record(5000000, 1)
	var before := full.interval_sum_us
	_check("the 60 s hard bound refuses without changing counters", full.record(1, 1) == FrameWindow.FULL and full.interval_sum_us == before)
	var unknown := FrameWindow.new()
	unknown.record(16000, -1)
	var event := unknown.event(4, "home", "none", "warmup", true)
	_check("an unavailable draw counter sends null, and short windows are never complete", event.rendered_frames == null
		and event.draw_counter_status == "unavailable" and event.window_complete == false and event.seq == 4)
	_check("an empty window has no event", FrameWindow.new().event(1, "home", "none", "steady", false).is_empty())


func _valid() -> Dictionary:
	var window := FrameWindow.new()
	for i: int in 1800:
		window.record(16667 if i < 1200 else 16666, 1)
	return {"schema_version": 1, "notice_version": Contract.NOTICE_VERSION, "session_id": "a".repeat(32),
		"batch_id": "b".repeat(32), "build": {"release_id": "v0.2.8", "channel": "stable", "engine_minor": "4.8"},
		"context": Hardware.context({"os": "Linux", "architecture": "x86_64", "cpu": "AMD Ryzen 7", "threads": 16,
			"memory_bytes": 34359738368, "gpu": "AMD Radeon RX 7800", "renderer": "forward_plus", "driver": "vulkan",
			"window_size": Vector2i(2560, 1440), "vsync": 0, "max_fps": 0}),
		"events": [Contract.session_started(1), window.event(2, "flight", "p51d-mustang-120", "steady", true),
			{"name": "activity_summary", "seq": 3, "vehicle_id": "p51d-mustang-120", "active_seconds": 600,
				"simulated_seconds": 590, "outcome": "returned_home", "complete_observation": true,
				"classification": "accepted_fixed_wing", "takeoffs": 2, "landings": 1, "aircraft_crashes": 1},
			Contract.error_count(4, "asset_load_failed", 2)]}


func _seventeen_events(b: Dictionary) -> void:
	b.events = []
	for i: int in 17:
		b.events.append(Contract.session_started(i + 1))


func _short_complete_window(b: Dictionary) -> void:
	b.events[1].interval_sum_us = 29000000
	b.events[1].interval_histogram = [0, 0, 870, 0, 0, 0, 0, 0]
	b.events[1].interval_count = 870


## JSON.parse_string returns floats; the wire uses integers.
func _integers(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		for key: Variant in value:
			out[key] = _integers(value[key])
		return out
	if value is Array:
		var out := []
		for item: Variant in value:
			out.append(_integers(item))
		return out
	if typeof(value) == TYPE_FLOAT and value == floorf(value) and absf(value) < 9007199254740992.0:
		return int(value)
	return value
