extends SceneTree
## VQ-07h: GPU capability table, adapter-name normalization and High-cost extrapolation.

const GpuCapability := preload("res://render/gpu_capability.gd")
const AutoGraphicsPolicy := preload("res://render/auto_graphics_policy.gd")
const SceneDetail := preload("res://render/scene_detail.gd")
const DisplayPreferences := preload("res://app_state/display_preferences.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_table()
	_test_normalize()
	_test_lookup()
	_test_prediction()
	_test_first_run()
	_test_steam_coverage()
	_test_mac_native()
	_test_extreme()
	print("gpu capability: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(name: String, ok: bool, detail: Variant = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL: %s %s" % [name, str(detail)])


func _test_table() -> void:
	var table := GpuCapability.table()
	_check("table loads with its format", str(table.get("format", "")) == GpuCapability.FORMAT)
	var rows: Array = table.get("rows", [])
	_check("table has the common GPUs", rows.size() >= 100, rows.size())
	var ids := {}
	var valid := true
	for row: Dictionary in rows:
		valid = valid and not ids.has(row.id) and RegEx.create_from_string(str(row.match)).is_valid() \
			and float(row.rel) >= 0.0 and float(row.rel) <= 3.0 and str(row["class"]) in ["discrete", "laptop", "integrated", "software"]
		ids[row.id] = true
	_check("every row has a unique id, a valid pattern, a bounded rel and a class", valid)
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	_check("every export preset ships the table", presets.count("data/gpu/capability.json") == presets.count("include_filter=")
		and presets.count("include_filter=") >= 3)
	var anchor: Dictionary = table.get("anchor", {})
	_check("the anchor is the measured RTX 3090", float(anchor.get("rel", 0.0)) == 1.0
		and str(anchor.get("source", "")).contains("rtx3090-matrix"))


func _test_normalize() -> void:
	var cases := {
		"NVIDIA GeForce RTX 3060/PCIe/SSE2": "rtx 3060",
		"NVIDIA GeForce RTX 4060 Laptop GPU": "rtx 4060 laptop gpu",
		"AMD Radeon RX 6600": "radeon rx 6600",
		"AMD Radeon RX 6600 (radeonsi, navi23, LLVM 17.0.6, DRM 3.57, 6.8.0)": "radeon rx 6600",
		"AMD Radeon(TM) Graphics": "radeon graphics",
		"Intel(R) UHD Graphics 630": "uhd graphics 630",
		"Mesa Intel(R) UHD Graphics 620 (WHL GT2)": "uhd graphics 620",
		"Intel(R) Arc(TM) A770 Graphics": "arc a770 graphics",
		"Intel(R) Iris(R) Xe Graphics": "iris xe graphics",
	}
	for raw: String in cases:
		_check("normalize %s" % raw, GpuCapability.normalize(raw) == cases[raw], GpuCapability.normalize(raw))


func _test_lookup() -> void:
	var cases := {
		"AMD Radeon RX Vega 64": "rx_vega_64", "AMD Radeon RX Vega 56": "rx_vega_56",
		"NVIDIA GeForce RTX 3090": "rtx_3090", "NVIDIA GeForce RTX 3060/PCIe/SSE2": "rtx_3060",
		"NVIDIA GeForce RTX 3060 Ti": "rtx_3060_ti", "NVIDIA GeForce RTX 4060 Laptop GPU": "rtx_4060_laptop",
		"NVIDIA GeForce RTX 4070 Ti SUPER": "rtx_4070_ti_super", "NVIDIA GeForce RTX 4070 SUPER": "rtx_4070_super",
		"NVIDIA GeForce RTX 5070": "rtx_5070", "NVIDIA GeForce RTX 2060 with Max-Q Design": "rtx_2060_laptop",
		"NVIDIA GeForce GTX 1650": "gtx_1650", "NVIDIA GeForce GTX 1660 SUPER": "gtx_1660_super",
		"NVIDIA GeForce GTX 1050 Ti": "gtx_1050_ti", "NVIDIA GeForce MX450": "mx450",
		"NVIDIA RTX A2000": "rtx_workstation", "Quadro RTX 4000": "rtx_workstation",
		"AMD Radeon RX 9070 XT": "rx_9070_xt", "AMD Radeon RX 9070": "rx_9070", "AMD Radeon RX 7900 XTX": "rx_7900_xtx",
		"AMD Radeon RX 6800M": "rx_6800m", "AMD Radeon RX 580 Series": "rx_580", "Radeon RX 580 Series": "rx_580",
		"AMD Radeon 780M Graphics": "radeon_780m", "AMD Radeon(TM) Graphics": "radeon_graphics_igpu",
		"Intel(R) Arc(TM) B580 Graphics": "arc_b580", "Intel(R) Arc(TM) A370M Graphics": "arc_a370m",
		"Intel(R) Arc(TM) Graphics": "arc_igpu", "Intel(R) Arc(TM) 140V GPU (16GB)": "arc_140v_igpu",
		"Intel(R) Iris(R) Xe Graphics": "iris_xe_igpu", "Intel(R) UHD Graphics": "uhd_igpu",
		"NVIDIA GeForce RTX 2050": "rtx_2050", "NVIDIA RTX A1000 Laptop GPU": "rtx_workstation_laptop",
		"NVIDIA GeForce RTX 6060 Laptop GPU": "rtx_unlisted_laptop", "NVIDIA GeForce RTX 6060": "rtx_unlisted",
		"NVIDIA GeForce RTX 3080 Ti Laptop GPU": "rtx_3080_ti_laptop", "AMD Radeon RX 6600 XT": "rx_6600_xt",
		"AMD Radeon RX 7600M": "rx_7600m", "AMD Radeon RX 7600M XT": "rx_7600m_xt", "AMD Radeon RX 6600S": "rx_6600s",
		"AMD Radeon RX 7900 GRE": "rx_7900_gre", "Intel(R) Arc(TM) A750 Graphics": "arc_a750",
		"NVIDIA GeForce RTX 3060 Laptop GPU/PCIe/SSE2": "rtx_3060_laptop",
		"Intel(R) Arc(TM) B390 GPU": "arc_b390_igpu", "Intel(R) Arc(TM) B370 GPU": "arc_b370_igpu",
		"Intel(R) Arc(TM) 140T GPU (16GB)": "arc_140t_igpu", "Intel(R) Arc(TM) 130V GPU (8GB)": "arc_130v_igpu",
		"Intel(R) Graphics": "intel_graphics_igpu", "AMD Radeon(TM) 8060S Graphics": "radeon_8060s",
		"AMD Radeon(TM) 8040S Graphics": "radeon_8040s", "AMD Radeon(TM) 890M Graphics": "radeon_890m",
		"AMD Radeon(TM) 860M Graphics": "radeon_860m", "AMD Radeon(TM) 840M Graphics": "radeon_840m",
		"Qualcomm(R) Adreno(TM) X1-85 GPU": "adreno_x1", "Qualcomm(R) Adreno(TM) X2-90 GPU": "adreno_x2",
		"AMD Radeon RX 9060": "rx_9060", "AMD Radeon RX 9060 XT": "rx_9060_xt",
		"Apple M1": "apple_m1", "Apple M1 Pro": "apple_m1_pro", "Apple M2 Max (Apple8)": "apple_m2_max",
		"Apple M4 Pro (Apple9)": "apple_m4_pro", "Apple M3": "apple_m3", "Apple M9 Ultra (Apple14)": "apple_unlisted",
		"ANGLE (Apple, ANGLE Metal Renderer: Apple M1, Unspecified Version)": "apple_m1",
		"ANGLE (NVIDIA, NVIDIA GeForce GTX 1060 Direct3D11 vs_5_0 ps_5_0)": "gtx_1060",
		"ANGLE (Intel, Intel(R) UHD Graphics 620 Direct3D11 vs_5_0 ps_5_0, D3D11)": "uhd_620_igpu",
		"AMD Radeon RX 6600 (radeonsi, navi23, LLVM 17.0.6, DRM 3.57, 6.8.0)": "rx_6600",
		"AMD Radeon Graphics (radeonsi, gfx1201, LLVM 19.1.7, DRM 3.61, 6.14.0)": "mesa_gfx1201",
		"AMD Radeon 660M (radeonsi, rembrandt, LLVM 20.1.2, DRM 3.64, 6.14.0)": "radeon_660m",
		"AMD Radeon RX 5500 (navi14, LLVM 13.0.0, DRM 3.46, 5.18.7)": "rx_5500",
		"AMD Custom GPU 0405 (radeonsi, vangogh, LLVM 17.0.6, DRM 3.57, 6.8.0)": "steam_deck",
		"AMD Custom GPU 0405": "steam_deck",
		"Mesa DRI Intel(R) HD Graphics 5500 (Broadwell GT2)": "hd_5500_igpu",
		"llvmpipe (LLVM 15.0.7, 256 bits)": "software", "Microsoft Basic Render Driver": "software",
	}
	for raw: String in cases:
		var found := GpuCapability.lookup(raw)
		_check("lookup %s" % raw, found.matched and found.id == cases[raw], found)
	var scene_cases := {"NVIDIA GeForce RTX 3090": ["high", "dedicated GPU"],
		"NVIDIA GeForce GTX 1050 Ti": ["medium", "entry-level GPU"], "Intel(R) Iris(R) Xe Graphics": ["medium", "integrated GPU"],
		"Intel(R) UHD Graphics 620": ["low", "integrated GPU"], "Apple M1 Max (Apple7)": ["high", "integrated GPU"],
		"llvmpipe (LLVM 15.0.7, 256 bits)": ["low", "software renderer"]}
	for raw: String in scene_cases:
		var scene := AutoGraphicsPolicy.scene_detail_from_capability(raw)
		_check("scene detail for %s uses a translated reason" % raw, scene.level == scene_cases[raw][0]
			and scene.reason == scene_cases[raw][1], scene)
	_check("unknown GPUs leave scene detail to the caller", str(AutoGraphicsPolicy.scene_detail_from_capability("Example 9000").level).is_empty())
	_check("an unknown Mesa chip is unknown, not the generic integrated row",
		not GpuCapability.lookup("AMD Radeon Graphics (radeonsi, gfx9999, LLVM 21.0.0, DRM 3.70, 6.20.0)").matched
		and GpuCapability.lookup("AMD Radeon Graphics (radeonsi, navi48, LLVM 21.0.0)").id == "mesa_navi48"
		and GpuCapability.lookup("AMD Radeon(TM) Graphics").id == "radeon_graphics_igpu")
	_check("an unknown accelerator does not match", not GpuCapability.lookup("Example Accelerator 9000").matched)
	_check("an empty name does not match", not GpuCapability.lookup("").matched)
	_check("relative order follows the generations",
		GpuCapability.lookup("NVIDIA GeForce RTX 4090").rel > GpuCapability.lookup("NVIDIA GeForce RTX 3090").rel
		and GpuCapability.lookup("NVIDIA GeForce RTX 3090").rel > GpuCapability.lookup("NVIDIA GeForce RTX 3060").rel
		and GpuCapability.lookup("NVIDIA GeForce RTX 3060").rel > GpuCapability.lookup("NVIDIA GeForce GTX 1650").rel
		and GpuCapability.lookup("NVIDIA GeForce GTX 1650").rel > GpuCapability.lookup("Intel(R) UHD Graphics").rel)


## AGENTS display exception: Retina Macs target the native panel; other systems keep the 1080p reference.
## VQ-07h-A4: Automatic Extreme only where Automatic High has worst-case headroom, enough VRAM and CPU threads.
func _test_extreme() -> void:
	var p1080 := 1920 * 1080
	var p1440 := 2560 * 1440
	var p2160 := 3840 * 2160
	var facts := func(adapter: String, pixels: int, threads: int = 12, os_name: String = "Windows") -> Dictionary:
		return {os = os_name, arm64 = false, adapter = adapter, pixels = pixels, cpu_threads = threads}
	var extreme := func(adapter: String, pixels: int, threads: int = 12, os_name: String = "Windows") -> bool:
		return bool(AutoGraphicsPolicy.extreme(facts.call(adapter, pixels, threads, os_name)).extreme)
	_check("an RTX 5090 runs Extreme at 4K", extreme.call("NVIDIA GeForce RTX 5090", p2160))
	_check("the measured RTX 3090 runs Extreme at 4K", extreme.call("NVIDIA GeForce RTX 3090", p2160))
	_check("an RTX 4070 runs Extreme at 1440p but not at 4K",
		extreme.call("NVIDIA GeForce RTX 4070", p1440) and not extreme.call("NVIDIA GeForce RTX 4070", p2160))
	_check("an RTX 3060 keeps High at 1080p and 1440p",
		not extreme.call("NVIDIA GeForce RTX 3060", p1080) and not extreme.call("NVIDIA GeForce RTX 3060", p1440))
	_check("6 GB cards stay at High", not extreme.call("NVIDIA GeForce GTX 1660 SUPER", p1080)
		and AutoGraphicsPolicy.renderer(facts.call("NVIDIA GeForce GTX 1660 SUPER", p1080)).profile == "high")
	_check("a 4-thread CPU keeps High even with an RTX 5090", not extreme.call("NVIDIA GeForce RTX 5090", p1080, 4))
	_check("the CPU floor is 8 threads", extreme.call("NVIDIA GeForce RTX 5090", p1080, 8)
		and not extreme.call("NVIDIA GeForce RTX 5090", p1080, 7))
	_check("capacity alone cannot qualify a 3070 for Extreme", not extreme.call("NVIDIA GeForce RTX 3070", p1080))
	_check("unknown CPU threads never choose Extreme", not extreme.call("NVIDIA GeForce RTX 5090", p1080, 0))
	_check("integrated GPUs never choose Extreme", not extreme.call("Intel(R) Iris(R) Xe Graphics", p1080)
		and not extreme.call("AMD Radeon 890M", p1080))
	_check("Linux desktop GPUs qualify like Windows", extreme.call("NVIDIA GeForce RTX 4080", p1440, 16, "Linux"))
	_check("Linux laptop GPUs keep Standard and no Extreme",
		not extreme.call("NVIDIA GeForce RTX 4090 Laptop GPU", p1080, 16, "Linux"))
	_check("Macs never choose Extreme automatically", not extreme.call("Apple M5 Max (Apple10)", p1080, 16, "macOS"))
	var not_running: Dictionary = facts.call("NVIDIA GeForce RTX 5090", p1080)
	not_running["forward_plus"] = false
	_check("Extreme needs High actually running", not bool(AutoGraphicsPolicy.extreme(not_running).extreme))
	var scene := AutoGraphicsPolicy.scene_detail("NVIDIA GeForce RTX 5090", "NVIDIA Corporation", 0,
		facts.call("", p2160))
	_check("scene detail reports Extreme with its reason", scene.level == "extreme" and scene.reason == "dedicated GPU"
		and str(scene.detail).contains("worst-case"), scene)
	var standard_saved := AutoGraphicsPolicy.decide({adapter = "NVIDIA GeForce RTX 5090", os = "Windows", arm64 = false,
		screen = Vector2i(3840, 2160), cpu_threads = 16, forward_plus = false})
	_check("the report keeps High while High is not running", standard_saved.scene_detail == "high", standard_saved)
	_check("headless hosts report no Extreme facts", DisplayServer.get_name() != "headless"
		or SceneDetail.extreme_facts().is_empty())
	_check("scene detail without host facts never chooses Extreme",
		AutoGraphicsPolicy.scene_detail("NVIDIA GeForce RTX 5090", "NVIDIA Corporation").level == "high")
	# The 4K boundary: the RTX 3080 (0.87x) still runs High there, but 1.25x its estimate exceeds the budget.
	var rtx_3080_4k := GpuCapability.predicted_high_ms(0.87, p2160)
	_check("an RTX 3080 runs High but just misses Extreme at 4K", rtx_3080_4k <= AutoGraphicsPolicy.HIGH_BUDGET_MS
		and rtx_3080_4k * AutoGraphicsPolicy.EXTREME_WORST_CASE_FACTOR > AutoGraphicsPolicy.HIGH_BUDGET_MS
		and not extreme.call("NVIDIA GeForce RTX 3080", p2160)
		and AutoGraphicsPolicy.renderer(facts.call("NVIDIA GeForce RTX 3080", p2160)).profile == "high")


func _test_mac_native() -> void:
	for raw: String in ["Apple M5 Pro (Apple10)", "Apple M6", "Apple M5 Max (Apple10)", "Apple A18 Pro"]:
		_check("Apple row for %s" % raw, GpuCapability.lookup(raw).id == "apple_" + GpuCapability.normalize(raw)
			.trim_prefix("apple ").replace(" ", "_"), GpuCapability.lookup(raw).id)
	_check("Retina detection needs macOS and a 2x backing scale", GpuCapability.mac_native_target("macOS", 2.0)
		and not GpuCapability.mac_native_target("macOS", 1.0) and not GpuCapability.mac_native_target("Windows", 2.0))
	_check("an Air 13-inch backing store renders through MetalFX at 2/3",
		GpuCapability.mac_render_pixels(Vector2i(2940, 1912)) == int(2940 * 2.0 / 3.0) * int(1912 * 2.0 / 3.0))
	_check("a small panel renders natively", GpuCapability.mac_render_pixels(Vector2i(1440, 900)) == 1440 * 900)
	_check("a base M1 Air starts full screen at its native resolution",
		AutoGraphicsPolicy.first_run("Apple M1 (Apple7)", "macOS", 2.0, 60.0) == {"window_mode": "borderless"})
	_check("a base M5 on a 120 Hz ProMotion panel is capped at 60 fps",
		AutoGraphicsPolicy.first_run("Apple M5 (Apple10)", "macOS", 2.0, 120.0) == {"window_mode": "borderless", "max_fps": 60})
	_check("a Max chip keeps 120 Hz", AutoGraphicsPolicy.first_run("Apple M5 Max (Apple10)", "macOS", 2.0, 120.0)
		== {"window_mode": "borderless"})
	_check("a Mac on a non-Retina external display keeps the windowed defaults",
		AutoGraphicsPolicy.first_run("Apple M1 (Apple7)", "macOS", 1.0, 60.0).is_empty())
	_check("an Intel Mac on a Retina panel keeps the window (no MetalFX, weak GPU)",
		not AutoGraphicsPolicy.first_run("Intel(R) Iris(TM) Plus Graphics 655", "macOS", 2.0, 60.0).has("window_mode"))
	_check("without MetalFX the native panel is rendered in full",
		GpuCapability.mac_render_pixels(Vector2i(2880, 1800), 1.0) == 2880 * 1800
		and GpuCapability.mac_render_pixels(Vector2i(2560, 1440), 0.85) == int(2560 * 0.85) * int(1440 * 0.85))
	_check("Windows never gets the Mac window rule",
		not AutoGraphicsPolicy.first_run("Intel(R) Iris(R) Xe Graphics", "Windows", 2.0, 120.0).has("window_mode"))
	var native := GpuCapability.mac_render_pixels(Vector2i(3024, 1964))
	_check("an M4 Pro is High at 1080p but Medium at a 14-inch native panel",
		AutoGraphicsPolicy.scene_detail_from_capability("Apple M4 Pro (Apple9)").level == "high"
		and AutoGraphicsPolicy.scene_detail_from_capability("Apple M4 Pro (Apple9)", native).level == "medium")
	_check("an M5 Max stays High at its native panel",
		AutoGraphicsPolicy.scene_detail_from_capability("Apple M5 Max (Apple10)", GpuCapability.mac_render_pixels(Vector2i(3456, 2234))).level == "high")
	DisplayPreferences.first_run_defaults = {"window_mode": "borderless", "max_fps": 60}
	var recommended := DisplayPreferences.recommended_defaults()
	_check("first-launch window and frame-cap values are accepted", recommended.window_mode == "borderless"
		and int(recommended.max_fps) == 60)
	DisplayPreferences.first_run_defaults = {"window_mode": "exclusive", "max_fps": 75}
	recommended = DisplayPreferences.recommended_defaults()
	_check("unsupported window or frame-cap values are ignored", recommended.window_mode == DisplayPreferences.DEFAULTS.window_mode
		and int(recommended.max_fps) == int(DisplayPreferences.DEFAULTS.max_fps))
	DisplayPreferences.first_run_defaults = {}


## Every named GPU of the Steam Hardware Survey fixture must resolve to a table row (no "unknown").
func _test_steam_coverage() -> void:
	var survey: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/data/steam_gpus_2026_10.json"))
	_check("the Steam survey fixture loads", survey is Dictionary and (survey as Dictionary).get("rows") is Array)
	if not survey is Dictionary:
		return
	var rows: Array = survey.rows
	var missing: Array[String] = []
	var share := 0.0
	var covered := 0.0
	for row: Dictionary in rows:
		share += float(row.share)
		var gpu := GpuCapability.lookup(str(row.name))
		if bool(gpu.matched) and float(gpu.rel) > 0.0:
			covered += float(row.share)
		else:
			missing.append(str(row.name))
	_check("the fixture holds at least the 100 most popular GPUs", rows.size() >= 100, rows.size())
	_check("every surveyed GPU has a capability row", missing.is_empty(), missing)
	_check("all surveyed share is covered", is_equal_approx(covered, share), "%.2f of %.2f" % [covered, share])
	var spot := {"AMD Radeon RX 5500 XT": "rx_5500_xt", "AMD Radeon RX 5500": "rx_5500",
		"NVIDIA GeForce GTX 1650 Ti": "gtx_1650_ti_unsuffixed", "NVIDIA GeForce RTX 3050 Ti": "rtx_3050_ti_unsuffixed",
		"AMD Radeon RX Vega 11 Graphics": "radeon_vega_11_igpu", "AMD Radeon RX Vega": "rx_vega",
		"AMD Radeon RX 580 2048SP": "rx_580_2048sp", "AMD Radeon RX590 GME": "rx_590_gme",
		"AMD Radeon (TM) Graphics": "radeon_graphics_igpu", "NVIDIA GeForce GTX 960M": "gtx_9xxm",
		"NVIDIA GeForce GT 710": "gt_710", "Intel HD Graphics 4600": "hd_4600_igpu", "Intel UHD Graphics 620": "uhd_620_igpu"}
	for raw: String in spot:
		_check("Steam name %s resolves to %s" % [raw, spot[raw]], GpuCapability.lookup(raw).id == spot[raw],
			GpuCapability.lookup(raw).id)


func _test_first_run() -> void:
	var basic := AutoGraphicsPolicy.BASIC_SETTINGS
	var cases := {"NVIDIA GeForce RTX 3090": {}, "NVIDIA GeForce GTX 1650": {"msaa_3d": Viewport.MSAA_2X, "shadow_quality": "medium"},
		"Example Accelerator 9000": basic, "NVIDIA GeForce RTX 6060": basic, "NVIDIA RTX A2000": basic,
		"Intel(R) UHD Graphics 630": basic, "llvmpipe (LLVM 15.0.7, 256 bits)": basic,
		"Apple M1 (Apple7)": {}, "Qualcomm(R) Adreno(TM) X1-85 GPU": {},
		"AMD Radeon Graphics (radeonsi, gfx9999, LLVM 21.0.0)": basic,
		"AMD Radeon(TM) 890M Graphics": {"msaa_3d": Viewport.MSAA_2X, "shadow_quality": "low"}}
	for raw: String in cases:
		_check("first-run settings for %s" % raw, AutoGraphicsPolicy.first_run(raw) == cases[raw], AutoGraphicsPolicy.first_run(raw))
	var hardware := {adapter = "NVIDIA GeForce RTX 5090", os = "Windows", cpu_threads = 12, screen = Vector2i(3840, 2160)}
	var top := AutoGraphicsPolicy.decide(hardware)
	_check("desktop flagship opens a 1080p window with Extreme, 8x AA and Ultra shadows",
		top.scene_detail == "extreme" and top.first_run.window_resolution == "1920x1080" and
		top.first_run.msaa_3d == Viewport.MSAA_8X and top.first_run.shadow_quality == "ultra", top)
	hardware.output_pixels = 7680 * 4320
	var ultra_hd := AutoGraphicsPolicy.decide(hardware)
	_check("a saved native 8K output is budgeted before applying flagship effects",
		ultra_hd.scene_detail != "extreme" and not ultra_hd.first_run.has("shadow_quality"), ultra_hd)
	hardware.erase("output_pixels")
	hardware.adapter = "NVIDIA GeForce RTX 3060"
	var mid := AutoGraphicsPolicy.decide(hardware)
	_check("the 3060 budgets High for its 1080p window on a 4K desktop", mid.renderer == "high" and
		mid.scene_detail == "high" and mid.first_run.msaa_3d == Viewport.MSAA_2X and mid.first_run.shadow_quality == "medium", mid)
	hardware.adapter = "NVIDIA GeForce RTX 5090 Laptop GPU"
	_check("the laptop flagship does not inherit desktop maximums", not AutoGraphicsPolicy.decide(hardware).first_run.has("shadow_quality"))
	for panel: Vector2i in [Vector2i(1920, 1080), Vector2i(1366, 768)]:
		_check("1080p and smaller panels use their native output", AutoGraphicsPolicy.first_display(panel, false) == {"window_mode": "borderless"})
	_check("a reserved dock leaves a native fullscreen instead of an undersized 1080p window",
		AutoGraphicsPolicy.first_display(Vector2i(2560, 1440), false, Vector2i(2560, 1130)) == {"window_mode": "borderless"})
	_check("Retina on Apple Silicon uses native output", AutoGraphicsPolicy.first_display(Vector2i(3024, 1964), true) == {"window_mode": "borderless"})
	_check("the basic notice describes the active settings", AutoGraphicsPolicy.basic_settings_active(basic, basic)
		and not AutoGraphicsPolicy.basic_settings_active(basic, {"msaa_3d": Viewport.MSAA_8X}))
	var path := "user://test gpu first run display.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DisplayPreferences.first_run_defaults = AutoGraphicsPolicy.first_run("Intel(R) Iris(R) Xe Graphics")
	DisplayPreferences.first_run_applies = false
	_check("an upgrader without a display file keeps the shipped default",
		int(DisplayPreferences.load_from(path).msaa_3d) == DisplayPreferences.DEFAULTS.msaa_3d)
	DisplayPreferences.first_run_applies = true
	_check("a fresh profile starts with the GPU's recommendation",
		int(DisplayPreferences.load_from(path).msaa_3d) == Viewport.MSAA_DISABLED)
	_check("Restore defaults offers the same recommendation",
		int(DisplayPreferences.recommended_defaults().msaa_3d) == Viewport.MSAA_DISABLED)
	var saved := DisplayPreferences.load_from(path)
	saved.erase("writable")
	saved.erase("note")
	saved.msaa_3d = Viewport.MSAA_8X
	_check("a saved file is written", DisplayPreferences.save_to(path, saved) == OK)
	_check("a saved choice always wins over the recommendation", int(DisplayPreferences.load_from(path).msaa_3d) == Viewport.MSAA_8X)
	DisplayPreferences.first_run_defaults = {"msaa_3d": 99, "scene_detail": "extreme"}
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var fresh := DisplayPreferences.load_from(path)
	_check("invalid or unsupported recommendations are ignored", int(fresh.msaa_3d) == DisplayPreferences.DEFAULTS.msaa_3d
		and str(fresh.scene_detail) == DisplayPreferences.DEFAULTS.scene_detail)
	DisplayPreferences.first_run_defaults = {}
	DisplayPreferences.first_run_applies = false
	_check("without a recommendation the defaults are unchanged", DisplayPreferences.recommended_defaults() == DisplayPreferences.DEFAULTS)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_prediction() -> void:
	var p1080 := GpuCapability.predicted_high_ms(1.0, 1920 * 1080)
	var p2160 := GpuCapability.predicted_high_ms(1.0, 3840 * 2160)
	_check("the anchor reproduces its measured 1080p High GPU time", absf(p1080 - 1.07) < 0.05, p1080)
	_check("the anchor reproduces its measured 4K High GPU time", absf(p2160 - 3.09) < 0.05, p2160)
	_check("half the throughput doubles the predicted time",
		is_equal_approx(GpuCapability.predicted_high_ms(0.5, 1920 * 1080), 2.0 * p1080))
	_check("no throughput predicts no frame", is_inf(GpuCapability.predicted_high_ms(0.0, 1920 * 1080)))
