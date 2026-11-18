extends Node
## VQ-07h: one measured check of the automatic graphics choice ("recommend using detected hardware and measured
## performance", AGENTS.md). During an eligible flight it waits for WARMUP_S of active flight (sim running, not
## paused, window focused), samples the main viewport's GPU time for SAMPLE_S and stores one verdict per GPU and
## renderer in CALIBRATION_PATH:
## - Automatic Scene detail moves one level down when the GPU p95 uses most of a 60 Hz frame, or one level up
##   when it uses little of it (up only when no SubViewport, such as a planar lake reflection, adds unmeasured
##   GPU work);
## - in Forward+, an automatically chosen High mode is rejected when the p95 misses the frame (the scene offset of
##   that verdict is then 0, so the cheaper Standard renderer is not penalised twice).
## A verdict applies only to its GPU, renderer and a similar output size (within 1.5x pixels); otherwise the next
## flight measures again. It never changes an explicit choice and never adapts continuously.
## "Restore graphics defaults" (once kept) deletes all verdicts.

const TimingLease := preload("res://render/render_timing_lease.gd")
const GpuCapability := preload("res://render/gpu_capability.gd")

const CALIBRATION_PATH := "user://graphics_calibration.cfg"
const FORMAT := 2
const WARMUP_S := 10.0
const SAMPLE_S := 20.0
const MIN_SAMPLES := 300
const FRAME_BUDGET_MS := 1000.0 / 60.0
const DOWN_ABOVE := 0.85 # GPU p95 above 85% of a 60 Hz frame: lower Automatic Scene detail one level
const UP_BELOW := 0.30 # below 30%: raise it one level (never to Extreme)
const HIGH_REJECT_ABOVE := 1.0 # an automatic High mode whose GPU p95 misses the 60 Hz frame is rejected
const PIXEL_TOLERANCE := 1.5
const HIGH_METHOD := "forward_plus"

## Test seam: tests point this at a private file.
static var calibration_path := CALIBRATION_PATH

signal finished(result: Dictionary)

var _session: Node
var _adapter := ""
var _token := 0
var _active_s := 0.0
var _samples: PackedFloat64Array = []


func _init(session: Node, adapter: String) -> void:
	name = "GraphicsAutoCalibration"
	_session = session
	_adapter = adapter
	process_mode = Node.PROCESS_MODE_ALWAYS


## Leases are taken on every tree entry: the Workshop detaches and re-attaches the flight.
func _enter_tree() -> void:
	if _token == 0:
		_token = TimingLease.acquire(get_viewport(), "graphics_auto_calibration")
	if _token == 0:
		queue_free.call_deferred()


func _exit_tree() -> void:
	if _token != 0:
		TimingLease.release(_token)
		_token = 0


func _process(delta: float) -> void:
	if _token == 0 or not _flight_active():
		return
	_active_s += delta
	if _active_s < WARMUP_S:
		return
	var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	if gpu_ms > 0.0 and is_finite(gpu_ms):
		_samples.append(gpu_ms)
	if _active_s >= WARMUP_S + SAMPLE_S:
		var size := get_viewport().get_visible_rect().size
		var result := evaluate(_samples, not _subviewports_active(), RenderingServer.get_current_rendering_method())
		result["adapter"] = _adapter
		result["method"] = RenderingServer.get_current_rendering_method()
		result["pixels"] = int(size.x) * int(size.y)
		save_result(result) # an unmeasurable flight stores a neutral verdict instead of retrying forever
		finished.emit(result)
		set_process(false)
		queue_free()


func _flight_active() -> bool:
	if not is_instance_valid(_session) or get_tree().paused or not get_window().has_focus():
		return false
	var sim: Variant = _session.get("sim")
	return sim is Node and is_instance_valid(sim) and not bool(sim.get("paused")) and int(sim.get("tick")) > 0


## Planar reflections and other SubViewports render outside the root viewport's GPU time.
func _subviewports_active() -> bool:
	for node: Node in get_tree().root.find_children("*", "SubViewport", true, false):
		if (node as SubViewport).render_target_update_mode != SubViewport.UPDATE_DISABLED:
			return true
	return false


## Pure verdict from GPU frame times (ms). `complete` is false when too few frames were measured.
static func evaluate(samples: PackedFloat64Array, allow_up: bool = true, method: String = "") -> Dictionary:
	if samples.size() < MIN_SAMPLES:
		return {"complete": false, "samples": samples.size(), "scene_offset": 0, "reject_high": false, "gpu_p95_ms": 0.0}
	var sorted := samples.duplicate()
	sorted.sort()
	var p95 := sorted[mini(sorted.size() - 1, int(0.95 * sorted.size()))]
	var reject_high := method in ["", HIGH_METHOD] and p95 > HIGH_REJECT_ABOVE * FRAME_BUDGET_MS
	var offset := 0
	if not reject_high:
		if p95 > DOWN_ABOVE * FRAME_BUDGET_MS:
			offset = -1
		elif allow_up and p95 < UP_BELOW * FRAME_BUDGET_MS:
			offset = 1
	return {"complete": true, "samples": samples.size(), "gpu_p95_ms": p95, "scene_offset": offset,
		"reject_high": reject_high}


## GPUs are keyed by their normalized name: OpenGL and Vulkan report the same GPU differently
## (e.g. Vulkan's "(KBL GT2)" suffix), and a verdict must survive a renderer change it caused.
static func adapter_key(adapter: String) -> String:
	var key := GpuCapability.normalize(adapter)
	return key if not key.is_empty() else adapter.strip_edges().to_lower()


static func _section(adapter: String, method: String) -> String:
	return "gpu %s | %s" % [adapter_key(adapter), method]


## The stored verdict for this GPU and renderer, or {} when there is none.
static func load_result(adapter: String, method: String) -> Dictionary:
	var cfg := ConfigFile.new()
	if adapter.is_empty() or cfg.load(calibration_path) != OK or int(cfg.get_value("meta", "format", 0)) != FORMAT:
		return {}
	var section := _section(adapter, method)
	if not cfg.has_section(section):
		return {}
	return {"adapter": adapter_key(adapter), "method": method,
		"scene_offset": clampi(int(cfg.get_value(section, "scene_offset", 0)), -1, 1),
		"reject_high": bool(cfg.get_value(section, "reject_high", false)) and method == HIGH_METHOD,
		"complete": bool(cfg.get_value(section, "complete", false)),
		"pixels": maxi(int(cfg.get_value(section, "pixels", 0)), 0),
		"gpu_p95_ms": float(cfg.get_value(section, "gpu_p95_ms", 0.0))}


static func save_result(result: Dictionary) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(calibration_path) # keep other GPUs' and renderers' verdicts
	if int(cfg.get_value("meta", "format", FORMAT)) != FORMAT:
		cfg = ConfigFile.new()
	cfg.set_value("meta", "format", FORMAT)
	var section := _section(str(result.get("adapter", "")), str(result.get("method", "")))
	cfg.set_value(section, "scene_offset", clampi(int(result.get("scene_offset", 0)), -1, 1))
	cfg.set_value(section, "reject_high", bool(result.get("reject_high", false)))
	cfg.set_value(section, "complete", bool(result.get("complete", false)))
	cfg.set_value(section, "pixels", maxi(int(result.get("pixels", 0)), 0))
	cfg.set_value(section, "gpu_p95_ms", float(result.get("gpu_p95_ms", 0.0)))
	cfg.set_value(section, "samples", int(result.get("samples", 0)))
	return cfg.save(calibration_path) == OK


## Whether `pixels` is within PIXEL_TOLERANCE of the verdict's measured output size (unknown sizes match).
static func size_matches(verdict: Dictionary, pixels: int) -> bool:
	var measured := int(verdict.get("pixels", 0))
	if measured <= 0 or pixels <= 0:
		return true
	var ratio := float(maxi(measured, pixels)) / float(mini(measured, pixels))
	return ratio <= PIXEL_TOLERANCE


## Whether a flight on this GPU and renderer at `pixels` should be measured.
static func needed(adapter: String, method: String, pixels: int = 0) -> bool:
	if adapter.is_empty():
		return false
	var verdict := load_result(adapter, method)
	return verdict.is_empty() or not size_matches(verdict, pixels)


## Deletes every verdict ("Restore graphics defaults").
static func clear() -> void:
	if FileAccess.file_exists(calibration_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(calibration_path))


## Applies a stored offset to an Automatic level: Low ↔ Medium ↔ High, never Extreme.
static func shifted_level(level: String, offset: int) -> String:
	var order: Array[String] = ["low", "medium", "high"]
	var index := order.find(level)
	if index < 0 or offset == 0:
		return level
	return order[clampi(index + offset, 0, order.size() - 1)]
