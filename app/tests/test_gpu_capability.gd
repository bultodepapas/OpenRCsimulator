extends SceneTree
## VQ-07h: GPU capability table, adapter-name normalization and High-cost extrapolation.

const GpuCapability := preload("res://render/gpu_capability.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_table()
	_test_normalize()
	_test_lookup()
	_test_prediction()
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
		"NVIDIA GeForce RTX 3090": "rtx_3090", "NVIDIA GeForce RTX 3060/PCIe/SSE2": "rtx_3060",
		"NVIDIA GeForce RTX 3060 Ti": "rtx_3060_ti", "NVIDIA GeForce RTX 4060 Laptop GPU": "rtx_4060_laptop",
		"NVIDIA GeForce RTX 4070 Ti SUPER": "rtx_4070_ti_super", "NVIDIA GeForce RTX 4070 SUPER": "rtx_4070_super",
		"NVIDIA GeForce RTX 5070": "rtx_5070", "NVIDIA GeForce RTX 2060 with Max-Q Design": "rtx_2060_laptop",
		"NVIDIA GeForce GTX 1650": "gtx_1650", "NVIDIA GeForce GTX 1660 SUPER": "gtx_1660_super",
		"NVIDIA GeForce GTX 1050 Ti": "gtx_1050_ti", "NVIDIA GeForce MX450": "mx_series",
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
		"llvmpipe (LLVM 15.0.7, 256 bits)": "software", "Microsoft Basic Render Driver": "software",
	}
	for raw: String in cases:
		var found := GpuCapability.lookup(raw)
		_check("lookup %s" % raw, found.matched and found.id == cases[raw], found)
	_check("an unknown accelerator does not match", not GpuCapability.lookup("Example Accelerator 9000").matched)
	_check("an empty name does not match", not GpuCapability.lookup("").matched)
	_check("relative order follows the generations",
		GpuCapability.lookup("NVIDIA GeForce RTX 4090").rel > GpuCapability.lookup("NVIDIA GeForce RTX 3090").rel
		and GpuCapability.lookup("NVIDIA GeForce RTX 3090").rel > GpuCapability.lookup("NVIDIA GeForce RTX 3060").rel
		and GpuCapability.lookup("NVIDIA GeForce RTX 3060").rel > GpuCapability.lookup("NVIDIA GeForce GTX 1650").rel
		and GpuCapability.lookup("NVIDIA GeForce GTX 1650").rel > GpuCapability.lookup("Intel(R) UHD Graphics").rel)


func _test_prediction() -> void:
	var p1080 := GpuCapability.predicted_high_ms(1.0, 1920 * 1080)
	var p2160 := GpuCapability.predicted_high_ms(1.0, 3840 * 2160)
	_check("the anchor reproduces its measured 1080p High GPU time", absf(p1080 - 1.07) < 0.05, p1080)
	_check("the anchor reproduces its measured 4K High GPU time", absf(p2160 - 3.09) < 0.05, p2160)
	_check("half the throughput doubles the predicted time",
		is_equal_approx(GpuCapability.predicted_high_ms(0.5, 1920 * 1080), 2.0 * p1080))
	_check("no throughput predicts no frame", is_inf(GpuCapability.predicted_high_ms(0.0, 1920 * 1080)))
