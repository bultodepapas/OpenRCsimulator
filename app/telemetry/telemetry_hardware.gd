## TELEM-04: coarse hardware and display context for telemetry batches. Engine strings (CPU and GPU names) are read
## only after consent, classified here into fixed categories and dropped; an ambiguous or unknown string becomes
## "other"/"unknown", never the string itself. The classifiers mirror research/telemetry/reference.py.
extends RefCounted

const GIB := 1073741824.0
## Usable physical memory is at or a little below the installed size (firmware and integrated-GPU reservations),
## so upper-inclusive power-of-two buckets classify it directly; this only absorbs rounding just above a boundary.
const RAM_ROUNDING_GIB := 0.01


## The batch context. `facts` (all optional, for tests) override what the engine reports.
static func context(facts: Dictionary = {}) -> Dictionary:
	var size: Vector2i = facts.get("window_size", Vector2i.ZERO)
	return {
		"os_family": os_family(str(facts.get("os", OS.get_name()))),
		"architecture": architecture(str(facts.get("architecture", Engine.get_architecture_name()))),
		"cpu_family": family(str(facts.get("cpu", OS.get_processor_name())), "cpu"),
		"logical_threads_bucket": threads_bucket(int(facts.get("threads", OS.get_processor_count()))),
		"ram_gib_bucket": ram_bucket(int(facts.get("memory_bytes", int(OS.get_memory_info().get("physical", -1))))),
		"gpu_family": family(str(facts.get("gpu", RenderingServer.get_video_adapter_name())), "gpu"),
		"renderer": renderer(str(facts.get("renderer", RenderingServer.get_current_rendering_method()))),
		"driver": driver(str(facts.get("driver", RenderingServer.get_current_rendering_driver_name()))),
		"resolution_class": resolution_class(size),
		"resolution_basis": "viewport_coordinates" if size != Vector2i.ZERO else "unknown",
		"vsync": vsync(int(facts.get("vsync", -1))),
		"fps_cap_bucket": fps_cap(int(facts.get("max_fps", Engine.max_fps))),
		"graphics_profile": str(facts.get("graphics_profile", "unknown")),
		"input_class": str(facts.get("input_class", "unknown")),
	}


static func os_family(name: String) -> String:
	match name:
		"Windows": return "windows"
		"macOS": return "macos"
		"Linux": return "linux"
		"": return "unknown"
	return "other"


static func architecture(name: String) -> String:
	match name:
		"x86_64": return "x86_64"
		"arm64": return "arm64"
		"": return "unknown"
	return "other"


## Word-based classification; exactly one recognized family or "other" ("unknown" for an empty string).
static func family(raw: String, kind: String) -> String:
	var value := raw.to_lower()
	if value.strip_edges() == "":
		return "unknown"
	var words := {}
	for word: String in RegEx.create_from_string("[^a-z0-9]+").sub(value, " ", true).split(" ", false):
		words[word] = true
	var matches: Array[String] = []
	if kind == "cpu":
		if words.has("intel") and words.has("core"): matches.append("intel_core")
		if words.has("amd") and words.has("ryzen"): matches.append("amd_ryzen")
		if words.has("apple"): matches.append("apple_silicon")
	elif kind == "gpu":
		if words.has("llvmpipe") or words.has("swiftshader"): matches.append("software")
		if words.has("apple"): matches.append("apple_silicon")
		if words.has("geforce") and words.has("rtx"): matches.append("nvidia_rtx")
		if words.has("geforce") and words.has("gtx"): matches.append("nvidia_gtx")
		# Mesa's RADV names some AMD GPUs without "Radeon" (Steam Deck: "AMD Custom GPU 0405 (RADV VANGOGH)").
		if words.has("radeon") or (words.has("amd") and words.has("radv")): matches.append("amd_radeon")
		if words.has("intel") and words.has("arc"): matches.append("intel_arc")
		# Newer integrated names: "Intel(R) Graphics", "Mesa Intel(R) Xe Graphics (TGL GT2)".
		if words.has("intel") and not words.has("arc") and (words.has("iris") or words.has("uhd") or words.has("hd")
				or words.has("xe") or words.has("graphics")):
			matches.append("intel_integrated")
	return matches[0] if matches.size() == 1 else "other"


static func threads_bucket(threads: int) -> String:
	if threads <= 0: return "unknown"
	if threads <= 4: return "le4"
	if threads <= 8: return "5_8"
	if threads <= 16: return "9_16"
	return "17_plus"


static func ram_bucket(physical_bytes: int) -> String:
	if physical_bytes <= 0:
		return "unknown"
	var gib := physical_bytes / GIB - RAM_ROUNDING_GIB
	if gib <= 4.0: return "le4"
	if gib <= 8.0: return "5_8"
	if gib <= 16.0: return "9_16"
	if gib <= 32.0: return "17_32"
	if gib <= 64.0: return "33_64"
	return "65_plus"


static func renderer(method: String) -> String:
	return method if method in ["gl_compatibility", "mobile", "forward_plus"] else "unknown"


static func driver(name: String) -> String:
	return name if name in ["opengl3", "opengl3_es", "opengl3_angle", "metal", "vulkan", "d3d12"] else "unknown"


## Exact 16:9 sizes only (the pilot rule): 1920x1080 is "1080p"; any other aspect ratio is "other".
static func resolution_class(size: Vector2i) -> String:
	if size.x <= 0 or size.y <= 0:
		return "unknown"
	if size.x * 9 != size.y * 16:
		return "other"
	if size.y < 1080: return "below1080p"
	if size.y == 1080: return "1080p"
	if size.y == 1440: return "1440p"
	if size.y == 2160: return "2160p"
	if size.y > 2160: return "above2160p"
	return "other"


static func vsync(mode: int) -> String:
	match mode:
		DisplayServer.VSYNC_DISABLED: return "off"
		DisplayServer.VSYNC_ENABLED: return "on"
		DisplayServer.VSYNC_ADAPTIVE: return "adaptive"
		DisplayServer.VSYNC_MAILBOX: return "mailbox"
	return "unknown"


static func fps_cap(max_fps: int) -> String:
	if max_fps < 0: return "unknown"
	if max_fps == 0: return "unlimited"
	if max_fps <= 30: return "le30"
	if max_fps <= 60: return "31_60"
	if max_fps <= 120: return "61_120"
	return "121_plus"
