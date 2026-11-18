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
	var text := _angle_device(adapter.to_lower())
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


## Mesa radeonsi names carry the chip: "AMD Radeon Graphics (radeonsi, navi23, LLVM …)" → "navi23".
static func mesa_codename(adapter: String) -> String:
	var text := adapter.to_lower()
	var at := text.find("(radeonsi, ")
	if at < 0:
		return ""
	var rest := text.substr(at + "(radeonsi, ".length())
	var end := rest.find(",")
	return (rest.substr(0, end) if end >= 0 else rest.trim_suffix(")")).strip_edges()


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
				result.matched = true
				result.id = str(row.get("id", ""))
				result.rel = float(row.get("rel", 0.0))
				result.vram_gb = int(row.get("vram_gb", 0))
				result["class"] = str(row.get("class", "unknown"))
				return result
	return result


## Scene detail Automatic from capability: weak integrated parts start Low, mid parts Medium, others High.
## Extreme is never automatic. Unknown GPUs return "" so the caller keeps its own fallback.
static func scene_detail_level(adapter: String) -> Dictionary:
	var gpu := lookup(adapter)
	if not bool(gpu.matched):
		return {"level": "", "reason": "", "gpu": gpu}
	var rel := float(gpu.rel)
	var level := "low" if str(gpu["class"]) == "software" or rel < SCENE_LOW_BELOW else (
		"medium" if rel < SCENE_MEDIUM_BELOW else "high")
	return {"level": level, "reason": "%s (estimated %.2f× RTX 3090)" % [gpu.id, rel], "gpu": gpu}


## Extrapolated High-profile GPU milliseconds at `pixels` output pixels for a relative throughput `rel`.
static func predicted_high_ms(rel: float, pixels: int) -> float:
	var anchor: Dictionary = table().get("anchor", {})
	if rel <= 0.0:
		return INF
	var fixed := float(anchor.get("fixed_ms", 0.40))
	var per_megapixel := float(anchor.get("ms_per_megapixel", 0.325))
	return (fixed + per_megapixel * float(maxi(pixels, 0)) / 1.0e6) / rel
