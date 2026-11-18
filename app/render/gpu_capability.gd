extends RefCounted
## VQ-07h: estimated GPU capability for Automatic graphics choices, from res://data/gpu/capability.json.
## The table's `rel` values are OpenRC estimates relative to the measured RTX 3090 anchor (see its provenance);
## predicted High cost extrapolates the anchor's fixed + per-megapixel GPU time. Unknown GPUs return no match.

const DATA_PATH := "res://data/gpu/capability.json"
const FORMAT := "openrc-gpu-capability v1"
## Names reported by Godot: GL_RENDERER (without "/PCIe/SSE2") or the Vulkan device name. Vendor/brand words,
## trademark marks and Mesa's "(radeonsi, navi23, LLVM …)" suffix are removed before matching.
const STRIP_TOKENS: Array[String] = ["/pcie/sse2", "(r)", "(tm)", "nvidia corporation", "nvidia", "ati technologies inc.",
	"advanced micro devices, inc.", "amd", "intel", "geforce", "mesa"]

## Scene detail tiers by estimated throughput: below 0.04 (UHD-class iGPUs, Vega iGPUs) Low; below 0.15
## (Iris Xe, 680M/780M, M1/M2, GTX 1050 Ti, MX) Medium; above that High.
const SCENE_LOW_BELOW := 0.04
const SCENE_MEDIUM_BELOW := 0.15
const MSAA_OFF_BELOW := 0.10
const GENERIC_RADEON_ROW := "radeon_graphics_igpu"
const REFERENCE_PIXELS := 1920 * 1080
## Default for mac_render_pixels: render/reconstruction.gd's Automatic MetalFX Spatial Quality (2/3 per axis) when
## its input keeps at least 1000 rows. Runtime callers pass the scale Reconstruction.auto_mode actually selects,
## which is Native (1.0) without MetalFX (Intel/Rosetta Macs, Compatibility, a blocked or unsupported scaler).
const MAC_AUTO_SCALE := 2.0 / 3.0
const MAC_AUTO_MIN_INPUT_ROWS := 1000
## Apple GPUs from about M4 Pro class (rel ≥ 0.18: M4 Pro, M2 Max and newer Max/Ultra/Pro) keep 120 Hz on
## ProMotion panels; slower chips, including M1 Max and M1–M3 Pro, start capped at 60 fps.
const MAC_120HZ_MIN_REL := 0.18


## Pixels the GPU renders for a Mac panel of `screen` pixels; `scale` < 0 assumes Automatic MetalFX.
static func mac_render_pixels(screen: Vector2i, scale: float = -1.0) -> int:
	if screen.x <= 0 or screen.y <= 0:
		return 0
	if scale < 0.0:
		scale = MAC_AUTO_SCALE if float(screen.y) * MAC_AUTO_SCALE >= MAC_AUTO_MIN_INPUT_ROWS else 1.0
	return int(float(screen.x) * scale) * int(float(screen.y) * scale)


## A Retina display (backing scale ≥ 2: every MacBook and iMac panel, Retina external displays) targets its
## native resolution (AGENTS display priorities exception). Godot cannot tell built-in from external panels.
static func mac_native_target(os_name: String, screen_scale: float) -> bool:
	return os_name == "macOS" and screen_scale >= 2.0

static var _table: Dictionary = {}
static var _compiled: Array = []


static func table() -> Dictionary:
	if _table.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary and str(parsed.get("format", "")) == FORMAT and parsed.get("rows") is Array:
			_table = parsed
			for row: Variant in parsed.rows:
				if row is Dictionary and not str(row.get("match", "")).is_empty():
					var regex := RegEx.create_from_string(str(row.match))
					if regex != null and regex.is_valid():
						_compiled.append([regex, row])
		else:
			push_warning("GPU capability table %s is missing or invalid" % DATA_PATH)
			_table = {"rows": [], "anchor": {}}
	return _table


static func normalize(adapter: String) -> String:
	var text := _angle_device(adapter.to_lower()).replace("mesa dri ", "")
	for token: String in STRIP_TOKENS:
		text = text.replace(token, " ")
	var mesa_details := text.find(" (")
	if mesa_details >= 0:
		text = text.substr(0, mesa_details)
	var words := PackedStringArray()
	for word: String in text.replace("\t", " ").split(" ", false):
		words.append(word)
	return " ".join(words)


## ANGLE wraps the device: "ANGLE (NVIDIA, NVIDIA GeForce GTX 1060 Direct3D11 vs_5_0 ps_5_0)" or
## "ANGLE (Apple, ANGLE Metal Renderer: Apple M1, Unspecified Version)". Returns the device part.
static func _angle_device(text: String) -> String:
	if not text.begins_with("angle ("):
		return text
	var inner := text.trim_prefix("angle (").trim_suffix(")")
	var comma := inner.find(", ")
	if comma >= 0:
		inner = inner.substr(comma + 2)
	inner = inner.replace("angle metal renderer: ", "")
	for marker: String in [" direct3d", " (0x", ", unspecified", ", opengl", " vulkan", ", version"]:
		var at := inner.find(marker)
		if at > 0:
			inner = inner.substr(0, at)
	return inner


## Mesa names carry the chip: "AMD Radeon Graphics (radeonsi, navi23, LLVM …)" or, in older Mesa,
## "AMD Radeon RX 5500 (navi14, LLVM …)" → "navi23"/"navi14". Unmatched tokens fall through harmlessly.
static func mesa_codename(adapter: String) -> String:
	var text := adapter.to_lower().replace("(tm)", "").replace("(r)", "")
	var at := text.find(" (")
	if at < 0:
		return ""
	var tokens := text.substr(at + 2).trim_suffix(")").split(",", false)
	if tokens.is_empty():
		return ""
	var first := tokens[0].strip_edges()
	if first == "radeonsi" and tokens.size() > 1:
		first = tokens[1].strip_edges()
	return first


## {matched, id, rel, vram_gb, class, normalized}. `matched` is false for unknown GPUs.
static func lookup(adapter: String) -> Dictionary:
	table()
	var normalized := normalize(adapter)
	var result := {"matched": false, "id": "", "rel": 0.0, "vram_gb": 0, "class": "unknown", "normalized": normalized}
	var candidates: Array[String] = []
	var codename := mesa_codename(adapter)
	if not codename.is_empty():
		candidates.append("mesa " + codename)
	if not normalized.is_empty():
		candidates.append(normalized)
	for candidate: String in candidates:
		for entry: Array in _compiled:
			if (entry[0] as RegEx).search(candidate) != null:
				var row: Dictionary = entry[1]
				# A Mesa chip we do not know must not fall back to the generic "Radeon Graphics" iGPU row:
				# newer Mesa names discrete cards that way too. Unknown keeps the safe defaults.
				if not codename.is_empty() and str(row.get("id", "")) == GENERIC_RADEON_ROW:
					return result
				result.matched = true
				result.id = str(row.get("id", ""))
				result.rel = float(row.get("rel", 0.0))
				result.vram_gb = int(row.get("vram_gb", 0))
				result["class"] = str(row.get("class", "unknown"))
				return result
	return result


## Scene detail Automatic from capability: weak integrated parts start Low, mid parts Medium, others High.
## Extreme is never automatic. Unknown GPUs return "" so the caller keeps its own fallback.
## `render_pixels` > 1080p (Macs: the native panel after MetalFX, see mac_render_pixels) scales the estimate
## down by the extra pixel load; other systems pass 0 and keep the 1080p reference (AGENTS display priorities).
static func scene_detail_level(adapter: String, render_pixels: int = 0) -> Dictionary:
	var gpu := lookup(adapter)
	if not bool(gpu.matched):
		return {"level": "", "reason": "", "gpu": gpu}
	var rel := float(gpu.rel) * minf(1.0, float(REFERENCE_PIXELS) / float(maxi(render_pixels, REFERENCE_PIXELS)))
	var kind := str(gpu["class"])
	var level := "low" if kind == "software" or rel < SCENE_LOW_BELOW else (
		"medium" if rel < SCENE_MEDIUM_BELOW else "high")
	# `reason` reuses Settings' translated categories; `detail` carries the table entry for logs and tools.
	var reason := "software renderer" if kind == "software" else ("integrated GPU" if kind == "integrated" else (
		"entry-level GPU" if level != "high" else "dedicated GPU"))
	return {"level": level, "reason": reason, "detail": "%s (estimated %.2f× RTX 3090)" % [gpu.id, rel], "gpu": gpu}


## First-launch display defaults for this GPU, applied only before any display settings file exists.
## MSAA evidence (docs/research/visual-quality-implementation/VQ-07/knob-costs-2026-11-18): on the RTX 3090 at 4K,
## turning 4x MSAA off saves 18-24% GPU time in every renderer while 2x costs the same as 4x, so dedicated GPUs
## keep the 4x default. Integrated GPUs share memory bandwidth, where vendors report MSAA cost growing with
## samples: capable ones start at 2x, weak ones (below MSAA_OFF_BELOW) without MSAA. Unknown GPUs get nothing.
## On a Retina Mac (`mac_native_target`) the game also starts full screen, so it renders at the panel's native
## resolution with Automatic MetalFX reconstruction instead of a small point-sized window.
## A ProMotion (120 Hz) panel with a base-class Apple chip is capped at 60 fps: with VSync the GPU would otherwise
## try to draw 120 frames at the native resolution, doubling power for a chip that cannot sustain it.
static func first_run_settings(adapter: String, os_name: String = "", screen_scale: float = 1.0,
		refresh_hz: float = 60.0) -> Dictionary:
	var settings := {}
	var gpu := lookup(adapter)
	# Apple Silicon only: Intel Macs have neither MetalFX nor the GPU for a native Retina frame.
	if mac_native_target(os_name, screen_scale) and str(gpu.id).begins_with("apple_"):
		settings["window_mode"] = "borderless"
		if refresh_hz > 61.0 and float(gpu.rel) < MAC_120HZ_MIN_REL:
			settings["max_fps"] = 60
	if not bool(gpu.matched) or str(gpu["class"]) not in ["integrated", "software"]:
		return settings
	# Tile-based GPUs (Apple, Adreno) resolve MSAA on chip; the shared-bandwidth argument does not apply.
	if str(gpu.id).begins_with("apple_") or str(gpu.id).begins_with("adreno_"):
		return settings
	settings["msaa_3d"] = Viewport.MSAA_DISABLED if str(gpu["class"]) == "software" \
		or float(gpu.rel) < MSAA_OFF_BELOW else Viewport.MSAA_2X
	return settings


## Extrapolated High-profile GPU milliseconds at `pixels` output pixels for a relative throughput `rel`.
static func predicted_high_ms(rel: float, pixels: int) -> float:
	var anchor: Dictionary = table().get("anchor", {})
	if rel <= 0.0:
		return INF
	var fixed := float(anchor.get("fixed_ms", 0.40))
	var per_megapixel := float(anchor.get("ms_per_megapixel", 0.325))
	return (fixed + per_megapixel * float(maxi(pixels, 0)) / 1.0e6) / rel
