extends RefCounted
## VQ-07h-A1 (docs/plans/automatic-graphics.md): the one automatic graphics policy. Every threshold and every
## automatic decision lives here; the older entry points (RendererPreference.auto_profile, SceneDetail.recommend,
## first-launch values) delegate to it. Data and geometry stay in render/gpu_capability.gd, which this file reads
## and never the other way round. The A0 decision snapshot (tests/test_auto_graphics_snapshot.gd) pins the output:
## this consolidation must reproduce it exactly; a policy change regenerates it and is reviewed as a diff.

const GpuCapability := preload("res://render/gpu_capability.gd")

# --- Renderer: Automatic High (Forward+) ---------------------------------------------------------------------
## Extrapolated High GPU time at the screen's resolution (at least 1080p) must stay within this budget: rel 0.25
## at 1080p, leaving more than 3.5x headroom inside a 60 Hz frame for heavier scenes and the estimate's error.
const HIGH_BUDGET_MS := 4.3
const MIN_HIGH_VRAM_GB := 4
const MIN_PIXELS := 1920 * 1080
const AUTO_HIGH_OSES: Array[String] = ["Windows", "Linux"]

# --- Scene detail Automatic -------------------------------------------------------------------------------------
## Estimated throughput tiers (x RTX 3090): below LOW Low, below MEDIUM Medium, else High; Extreme only via extreme().
const SCENE_LOW_BELOW := 0.04
const SCENE_MEDIUM_BELOW := 0.15
const SCENE_FALLBACK := "medium"
## A4 Ultra, step 1: Automatic Extreme (the whole 3D tree ring; Lens effects Automatic follows to Ultra) where
## Automatic also picks High and the worst-case scene still fits the High budget. The worst-case protocol (night
## lights, storm, lens rain, planar lake, Extreme) measured up to 1.25x the base High GPU time on the RTX 3090
## (docs/research/visual-quality-implementation/VQ-07/worst-case-2026-11-18). Extreme's own GPU cost was not
## measurable there; it adds instances and draws, so a CPU-thread floor applies. Both floors are provisional.
const EXTREME_WORST_CASE_FACTOR := 1.25
const EXTREME_MIN_VRAM_GB := 8
const EXTREME_MIN_CPU_THREADS := 8
## Name markers for GPUs missing from the capability table (VQ-06b-R1). Discrete markers precede integrated ones.
const SOFTWARE_MARKERS: Array[String] = ["llvmpipe", "softpipe", "lavapipe", "swiftshader",
	"microsoft basic render", "gdi generic", "software rasterizer"]
const ENTRY_DISCRETE_MARKERS: Array[String] = ["geforce mx", "geforce gt ", "geforce 9", "geforce 8"]
const DISCRETE_MARKERS: Array[String] = ["geforce", "rtx", "quadro", "radeon rx", "radeon pro", "radeon r9",
	"radeon r7", "firepro", "intel(r) arc", "intel arc", "arc(tm)"]
const INTEGRATED_MARKERS: Array[String] = ["intel", "uhd graphics", "iris", "hd graphics", "radeon(tm) graphics",
	"radeon graphics", "radeon vega", "radeon(tm) vega", "apple m"]
const MOBILE_MARKERS: Array[String] = ["adreno", "mali", "powervr", "tegra"]

# --- First-launch display values ---------------------------------------------------------------------------------
## Integrated GPUs below this start without MSAA, others at 2x; dedicated, unknown and tile-based GPUs keep 4x.
const MSAA_OFF_BELOW := 0.10
## Apple GPUs from about M4 Pro class keep 120 Hz on ProMotion panels; slower chips start capped at 60 fps.
const MAC_120HZ_MIN_REL := 0.18

# --- First-flight measured calibration (render/auto_calibration.gd) --------------------------------------------
const CALIBRATION_FRAME_BUDGET_MS := 1000.0 / 60.0
const CALIBRATION_DOWN_ABOVE := 0.85
const CALIBRATION_UP_BELOW := 0.30
const CALIBRATION_HIGH_REJECT_ABOVE := 1.0
## A5: CPU-bound frames never move Scene detail up, because more detail adds draw calls and instances. A frame is
## CPU-bound when the renderer's CPU p95 (root viewport render CPU + frame setup) exceeds this share of the 60 Hz
## budget, or when the real frame interval p95 exceeds CALIBRATION_INTERVAL_MISS × its floor (60 Hz, or a slower
## VSync display or frame cap), and at least CALIBRATION_INTERVAL_MARGIN_MS over it, while the GPU is below the down
## threshold. Provisional: only the Ryzen 9 5900X + RTX 3090 host has measured render CPU so far.
const CALIBRATION_CPU_BLOCK_UP_ABOVE := 0.4
const CALIBRATION_INTERVAL_MISS := 1.1
const CALIBRATION_INTERVAL_MARGIN_MS := 2.0


## Automatic High. facts: {os, arm64, adapter, pixels}. Returns {profile, reason, gpu, predicted_ms}.
static func renderer(facts: Dictionary) -> Dictionary:
	var os_name := str(facts.get("os", ""))
	if os_name not in AUTO_HIGH_OSES or bool(facts.get("arm64", false)):
		return {profile = "standard", reason = "High is chosen automatically only on Windows and Linux x86_64"}
	var gpu := GpuCapability.lookup(str(facts.get("adapter", "")))
	if not bool(gpu.matched):
		return {profile = "standard", reason = "GPU not in the capability table", gpu = gpu}
	if str(gpu["class"]) in ["integrated", "software"]:
		return {profile = "standard", reason = "%s GPU" % gpu["class"], gpu = gpu}
	# Linux: desktop GPUs only. Hybrid laptops usually present their integrated GPU to OpenGL anyway, and
	# Forward+ driver reports on Linux are thinner, so laptop parts keep Standard there.
	if os_name == "Linux" and str(gpu["class"]) != "discrete":
		return {profile = "standard", reason = "Linux laptop GPU", gpu = gpu}
	if int(gpu.vram_gb) < MIN_HIGH_VRAM_GB:
		return {profile = "standard", reason = "less than %d GB of video memory" % MIN_HIGH_VRAM_GB, gpu = gpu}
	var pixels := maxi(int(facts.get("pixels", 0)), MIN_PIXELS)
	var predicted := GpuCapability.predicted_high_ms(float(gpu.rel), pixels)
	var within := predicted <= HIGH_BUDGET_MS
	return {profile = "high" if within else "standard", gpu = gpu, predicted_ms = predicted,
		reason = "%s: estimated High GPU %.1f ms at %.1f MP (budget %.1f ms)" % [gpu.id, predicted,
			float(pixels) / 1.0e6, HIGH_BUDGET_MS]}


## Automatic Extreme. facts: {os, arm64, adapter, pixels, cpu_threads, forward_plus}; `forward_plus` (default
## true) is false at runtime when High is not actually running. Returns {extreme, reason}.
static func extreme(facts: Dictionary) -> Dictionary:
	var high := renderer(facts)
	if str(high.profile) != "high":
		return {extreme = false, reason = "Automatic does not choose High here"}
	if not bool(facts.get("forward_plus", true)):
		return {extreme = false, reason = "High is not running"}
	var gpu: Dictionary = high.gpu
	if int(gpu.vram_gb) < EXTREME_MIN_VRAM_GB:
		return {extreme = false, reason = "less than %d GB of video memory" % EXTREME_MIN_VRAM_GB}
	var threads := int(facts.get("cpu_threads", 0))
	if threads < EXTREME_MIN_CPU_THREADS:
		return {extreme = false, reason = "%d CPU threads (Extreme needs %d)" % [threads, EXTREME_MIN_CPU_THREADS]}
	var worst := float(high.predicted_ms) * EXTREME_WORST_CASE_FACTOR
	return {extreme = worst <= HIGH_BUDGET_MS,
		reason = "estimated worst-case High GPU %.1f ms (budget %.1f ms)" % [worst, HIGH_BUDGET_MS]}


## Scene detail from the capability table only; unknown GPUs return level "" (see scene_detail()).
## `render_pixels` > 1080p (Macs: the native panel after MetalFX) scales the estimate by the extra pixel load.
static func scene_detail_from_capability(adapter: String, render_pixels: int = 0) -> Dictionary:
	var gpu := GpuCapability.lookup(adapter)
	if not bool(gpu.matched):
		return {"level": "", "reason": "", "gpu": gpu}
	var reference := GpuCapability.REFERENCE_PIXELS
	var rel := float(gpu.rel) * minf(1.0, float(reference) / float(maxi(render_pixels, reference)))
	var kind := str(gpu["class"])
	var level := "low" if kind == "software" or rel < SCENE_LOW_BELOW else (
		"medium" if rel < SCENE_MEDIUM_BELOW else "high")
	# `reason` reuses Settings' translated categories; `detail` carries the table entry for logs and tools.
	var reason := "software renderer" if kind == "software" else ("integrated GPU" if kind == "integrated" else (
		"entry-level GPU" if level != "high" else "dedicated GPU"))
	return {"level": level, "reason": reason, "detail": "%s (estimated %.2f× RTX 3090)" % [gpu.id, rel], "gpu": gpu}


## Scene detail Automatic before measured calibration: the capability table, then name markers, then Medium.
## High becomes Extreme only when `extreme_facts` (see extreme()) are given and qualify.
static func scene_detail(adapter: String, vendor: String, render_pixels: int = 0,
		extreme_facts: Dictionary = {}) -> Dictionary:
	var gpu := (adapter + " " + vendor).strip_edges().to_lower()
	if gpu.is_empty():
		return {level = SCENE_FALLBACK, reason = "no GPU reported"}
	var capable := scene_detail_from_capability(adapter, render_pixels)
	if not str(capable.level).is_empty():
		if str(capable.level) == "high" and not extreme_facts.is_empty():
			var facts := extreme_facts.duplicate()
			facts["adapter"] = adapter
			var top := extreme(facts)
			if bool(top.extreme):
				return {level = "extreme", reason = capable.reason, detail = "%s; Extreme: %s" % [capable.detail, top.reason]}
		return {level = capable.level, reason = capable.reason, detail = capable.detail}
	for rule: Array in [[SOFTWARE_MARKERS, "low", "software renderer"], [MOBILE_MARKERS, "low", "mobile GPU"],
			[ENTRY_DISCRETE_MARKERS, "medium", "entry-level GPU"], [DISCRETE_MARKERS, "high", "dedicated GPU"],
			[INTEGRATED_MARKERS, "medium", "integrated GPU"]]:
		for marker: String in rule[0]:
			if gpu.contains(marker):
				return {level = rule[1], reason = rule[2]}
	return {level = SCENE_FALLBACK, reason = "unrecognized GPU"}


## First-launch display values, applied only on a fresh install (DisplayPreferences). Evidence:
## docs/research/visual-quality-implementation/VQ-07/knob-costs-2026-11-18 (MSAA) and the AGENTS Mac exception.
static func first_run(adapter: String, os_name: String = "", screen_scale: float = 1.0, refresh_hz: float = 60.0) -> Dictionary:
	var settings := {}
	var gpu := GpuCapability.lookup(adapter)
	# Apple Silicon only: Intel Macs have neither MetalFX nor the GPU for a native Retina frame.
	if GpuCapability.mac_native_target(os_name, screen_scale) and str(gpu.id).begins_with("apple_"):
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


## The complete automatic bundle for given hardware inputs: {adapter, os, arm64, screen: Vector2i, scale, refresh,
## cpu_threads, forward_plus}. Returns {renderer, scene_detail, first_run, reasons}. Measured calibration is applied
## by its consumers. Without cpu_threads, Extreme is never chosen; `forward_plus` false (High not running, e.g. a
## saved Standard mode) keeps it at High.
static func decide(inputs: Dictionary) -> Dictionary:
	var adapter := str(inputs.get("adapter", ""))
	var os_name := str(inputs.get("os", ""))
	var screen: Vector2i = inputs.get("screen", Vector2i.ZERO)
	var scale := float(inputs.get("scale", 1.0))
	var arm64 := bool(inputs.get("arm64", false))
	var facts := {os = os_name, arm64 = arm64, adapter = adapter, pixels = screen.x * screen.y,
		cpu_threads = int(inputs.get("cpu_threads", 0)), forward_plus = bool(inputs.get("forward_plus", true))}
	var chosen_renderer := renderer(facts)
	# Retina Macs judge Scene detail at the pixels rendered under Automatic MetalFX (AGENTS display exception).
	var render_pixels := GpuCapability.mac_render_pixels(screen) \
		if GpuCapability.mac_native_target(os_name, scale) and arm64 else 0
	var scene := scene_detail(adapter, "", render_pixels, facts)
	return {"renderer": str(chosen_renderer.profile), "scene_detail": str(scene.level),
		"first_run": first_run(adapter, os_name, scale, float(inputs.get("refresh", 60.0))),
		"reasons": {"renderer": str(chosen_renderer.reason), "scene_detail": str(scene.get("detail", scene.reason))}}
