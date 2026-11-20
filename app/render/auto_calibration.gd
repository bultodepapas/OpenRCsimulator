extends Node
## VQ-07h: one measured check of the automatic graphics choice ("recommend using detected hardware and measured
## performance", AGENTS.md). During an eligible flight it waits for WARMUP_S of active flight (sim running, not
## paused, window focused), samples the main viewport's GPU time for SAMPLE_S and stores one verdict per GPU and
## renderer in CALIBRATION_PATH:
## - Automatic Scene detail moves one level down when the GPU p95 uses most of a 60 Hz frame, or one level up
##   when it uses little of it (up only when no SubViewport, such as a planar lake reflection, adds unmeasured
##   GPU work);
## - in Forward+, an automatically chosen High mode is rejected when the p95 misses the frame (the scene offset of
##   that verdict is then 0, so the cheaper Standard renderer is not penalised twice);
## - a CPU-bound frame (see evaluate) never moves up: more detail adds draw calls. GPU verdicts use GPU time only,
##   so a slow CPU never rejects High or lowers detail by itself.
## A verdict applies only to its GPU, renderer and a comparable workload: a similar output size and internal 3D
## size (each within 1.5x pixels) and the same 3D MSAA; otherwise the next flight measures again. It never changes
## an explicit choice and never adapts continuously.
## "Restore graphics defaults" (once kept) deletes all verdicts.

const TimingLease := preload("res://render/render_timing_lease.gd")
const GpuCapability := preload("res://render/gpu_capability.gd")
const AutoGraphicsPolicy := preload("res://render/auto_graphics_policy.gd")
const Reconstruction := preload("res://render/reconstruction.gd")

const CALIBRATION_PATH := "user://graphics_calibration.cfg"
## 3 (VQ-07h-A4): verdicts record the Scene detail level they measured. Older verdicts are discarded and measured
## again once, because Automatic can now start at Extreme and an offset only means something for its own level.
## 4 (audit 2026-11-19 F04/F07): `pixels` is the root viewport's output size in window pixels (format 3 stored the
## logical UI canvas, which hides 1440p/4K behind 1080p), and verdicts add their internal 3D size and 3D MSAA.
## Format 3 sizes cannot be relabelled, so those verdicts are discarded and measured again once.
const FORMAT := 4
const LEVEL_ORDER: Array[String] = ["low", "medium", "high", "extreme"]
const WARMUP_S := 10.0
const SAMPLE_S := 20.0
const MIN_SAMPLES := 300
const FRAME_BUDGET_MS := AutoGraphicsPolicy.CALIBRATION_FRAME_BUDGET_MS
const DOWN_ABOVE := AutoGraphicsPolicy.CALIBRATION_DOWN_ABOVE # lower Automatic Scene detail one level
const UP_BELOW := AutoGraphicsPolicy.CALIBRATION_UP_BELOW # raise it one level (never to Extreme)
const HIGH_REJECT_ABOVE := AutoGraphicsPolicy.CALIBRATION_HIGH_REJECT_ABOVE # reject automatic High
const CPU_BLOCK_UP_ABOVE := AutoGraphicsPolicy.CALIBRATION_CPU_BLOCK_UP_ABOVE # CPU-bound: never raise detail
const INTERVAL_MISS := AutoGraphicsPolicy.CALIBRATION_INTERVAL_MISS
const INTERVAL_MARGIN_MS := AutoGraphicsPolicy.CALIBRATION_INTERVAL_MARGIN_MS
const PIXEL_TOLERANCE := 1.5
const HIGH_METHOD := "forward_plus"
## Under a separate render thread (rendering/driver/threads/thread_model = 2) every RenderingServer timing read is
## a render-thread sync: reading each frame took a 4K RTX 3090 flight from ~320 to 19-73 fps (VQ-07h T5). There
## the GPU/CPU timings are read at most every 50 ms (about 400 samples in SAMPLE_S); frame intervals need no read
## and stay per frame. With the default model (Safe) every frame is read, as before.
const SEPARATE_READ_INTERVAL_USEC := 50000

## Test seam: tests point this at a private file.
static var calibration_path := CALIBRATION_PATH

signal finished(result: Dictionary)

var _session: Node
var _adapter := ""
var _level := ""
var _token := 0
var _active_s := 0.0
var _samples: PackedFloat64Array = []
var _cpu_samples: PackedFloat64Array = []
var _interval_samples: PackedFloat64Array = []
var _last_frame_usec := 0
var _separate_render_thread := uses_separate_render_thread()
var _last_read_usec := 0
## SubViewport GPU work is outside the root timing. Activity is checked every sampled frame, not only when the
## sample ends: a view that rendered for part of it still taints it. One tree scan when sampling starts, then
## node_added keeps the short list current, so no frame in the sample pays a whole-tree scan.
var _subviewports_seen := false
var _views: Array[SubViewport] = []
var _tracking_views := false


## `level` is the Scene detail level this flight renders (SceneDetail.level()); the verdict is relative to it.
func _init(session: Node, adapter: String, level: String = "") -> void:
	name = "GraphicsAutoCalibration"
	_session = session
	_adapter = adapter
	_level = level
	process_mode = Node.PROCESS_MODE_ALWAYS


## Leases are taken on every tree entry: the Workshop detaches and re-attaches the flight.
func _enter_tree() -> void:
	if _token == 0:
		_token = TimingLease.acquire(get_viewport(), "graphics_auto_calibration")
	if _token == 0:
		queue_free.call_deferred()


func _exit_tree() -> void:
	_last_frame_usec = 0 # the Workshop detaches the flight; time spent outside the tree is not a frame
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	_tracking_views = false # re-scan on re-entry: views may have come and gone while detached
	if _token != 0:
		TimingLease.release(_token)
		_token = 0


func _process(delta: float) -> void:
	if _token == 0 or not _flight_active():
		_last_frame_usec = 0 # a pause or lost focus must not count as a slow frame
		return
	var now := Time.get_ticks_usec()
	var interval_ms := float(now - _last_frame_usec) / 1000.0 if _last_frame_usec > 0 else 0.0
	_last_frame_usec = now
	_active_s += delta
	if _active_s < WARMUP_S:
		return
	if not _tracking_views:
		_track_views()
	_subviewports_seen = _subviewports_seen or _subviewports_active()
	if reads_timings(_separate_render_thread, now, _last_read_usec):
		_last_read_usec = now
		var rid := get_viewport().get_viewport_rid()
		var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(rid)
		if gpu_ms > 0.0 and is_finite(gpu_ms):
			_samples.append(gpu_ms)
			_cpu_samples.append(render_cpu_ms(rid))
			if interval_ms > 0.0:
				_interval_samples.append(interval_ms)
	elif interval_ms > 0.0:
		_interval_samples.append(interval_ms) # no timing read this frame (separate render thread)
	if _active_s >= WARMUP_S + SAMPLE_S:
		var refresh := DisplayServer.screen_get_refresh_rate()
		var vsync := DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
		var result := evaluate(_samples, not _subviewports_seen, RenderingServer.get_current_rendering_method(),
			_cpu_samples, _interval_samples, interval_floor_ms(refresh, vsync, Engine.max_fps))
		result["refresh_hz"] = refresh
		result["level"] = _level
		result["adapter"] = _adapter
		result["method"] = RenderingServer.get_current_rendering_method()
		result.merge(current_workload(get_viewport()), true)
		save_result(result) # an unmeasurable flight stores a neutral verdict instead of retrying forever
		finished.emit(result)
		set_process(false)
		queue_free()


func _flight_active() -> bool:
	if not is_instance_valid(_session) or get_tree().paused or not get_window().has_focus():
		return false
	var sim: Variant = _session.get("sim")
	return sim is Node and is_instance_valid(sim) and not bool(sim.get("paused")) and int(sim.get("tick")) > 0


static func uses_separate_render_thread() -> bool:
	return int(ProjectSettings.get_setting("rendering/driver/threads/thread_model", 1)) == 2


## Whether this frame reads the RenderingServer timings: always with the default thread model, at most every
## SEPARATE_READ_INTERVAL_USEC with a separate render thread.
static func reads_timings(separate: bool, now_usec: int, last_read_usec: int) -> bool:
	return not separate or last_read_usec == 0 or now_usec - last_read_usec >= SEPARATE_READ_INTERVAL_USEC


func _track_views() -> void:
	_tracking_views = true
	_views.clear()
	for node: Node in get_tree().root.find_children("*", "SubViewport", true, false):
		_views.append(node as SubViewport)
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is SubViewport:
		_views.append(node as SubViewport)


## Planar reflections and other SubViewports render outside the root viewport's GPU time.
func _subviewports_active() -> bool:
	for view: SubViewport in _views:
		if is_instance_valid(view) and view.is_inside_tree() \
				and view.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			return true
	return false


## CPU milliseconds the renderer spent on the last frame: root viewport render CPU plus frame setup (culling,
## instance updates). Both scale with Scene detail and exclude the VSync wait. Performance.TIME_PROCESS is not
## used: Godot publishes it once per second as the maximum, and it includes the draw and VSync wait.
static func render_cpu_ms(viewport_rid: RID) -> float:
	var total := RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid) \
		+ RenderingServer.get_frame_setup_time_cpu()
	return total if is_finite(total) and total >= 0.0 else 0.0


## The shortest frame interval the display or the frame cap allows (ms). A 50 Hz VSync display or a 30 fps cap
## cannot reach 60 fps, which must not count as CPU-bound.
static func interval_floor_ms(refresh_hz: float, vsync: bool, max_fps: int) -> float:
	var floor_ms := FRAME_BUDGET_MS
	if vsync and refresh_hz > 0.0:
		floor_ms = maxf(floor_ms, 1000.0 / refresh_hz)
	if max_fps > 0:
		floor_ms = maxf(floor_ms, 1000.0 / float(max_fps))
	return floor_ms


## The decision quantile: the order statistic at index floor(0.95 * N) of the sorted samples (0-based). This is
## deliberately stricter than the HUD's nearest-rank p95 (index ceil(0.95 * N) - 1): with exactly a 5% slow tail
## it reports the slow value, so such a tail rejects High (test_auto_calibration pins this). The HUD shows a
## different metric and convention; the two numbers are not expected to agree (audit 2026-11-19 F10).
static func _p95(samples: PackedFloat64Array) -> float:
	var sorted := samples.duplicate()
	sorted.sort()
	return sorted[mini(sorted.size() - 1, int(0.95 * sorted.size()))]


## The interval p95 above which a frame misses its floor: INTERVAL_MISS × floor, and at least INTERVAL_MARGIN_MS
## over it, so frame-limiter sleep jitter at a 60 fps cap is not a miss.
static func interval_limit_ms(interval_floor: float) -> float:
	return maxf(INTERVAL_MISS * interval_floor, interval_floor + INTERVAL_MARGIN_MS)


## Pure verdict from GPU frame times (ms), plus render CPU times and real frame intervals when measured.
## `complete` is false when too few GPU frames were measured; too few CPU or interval samples leave that signal
## unclassified. The frame is CPU-bound when the renderer's own CPU p95 is heavy, or when the frame interval p95
## misses its floor (60 Hz, or slower display/cap) while the GPU is not near its budget. The interval clause needs
## `allow_up`: SubViewport GPU work (a planar lake) also slows frames without showing in the root GPU time.
static func evaluate(samples: PackedFloat64Array, allow_up: bool = true, method: String = "",
		cpu_samples: PackedFloat64Array = PackedFloat64Array(), interval_samples: PackedFloat64Array = PackedFloat64Array(),
		interval_floor: float = FRAME_BUDGET_MS) -> Dictionary:
	if samples.size() < MIN_SAMPLES:
		return {"complete": false, "samples": samples.size(), "scene_offset": 0, "reject_high": false, "gpu_p95_ms": 0.0,
			"cpu_p95_ms": 0.0, "interval_p95_ms": 0.0, "cpu_bound": false, "subviewports": not allow_up}
	var p95 := _p95(samples)
	var cpu_p95 := _p95(cpu_samples) if cpu_samples.size() >= MIN_SAMPLES else 0.0
	var interval_p95 := _p95(interval_samples) if interval_samples.size() >= MIN_SAMPLES else 0.0
	var cpu_bound := cpu_p95 > CPU_BLOCK_UP_ABOVE * FRAME_BUDGET_MS or (allow_up
		and interval_p95 > interval_limit_ms(interval_floor) and p95 <= DOWN_ABOVE * FRAME_BUDGET_MS)
	var reject_high := method in ["", HIGH_METHOD] and p95 > HIGH_REJECT_ABOVE * FRAME_BUDGET_MS
	var offset := 0
	if not reject_high:
		if p95 > DOWN_ABOVE * FRAME_BUDGET_MS:
			offset = -1
		elif allow_up and not cpu_bound and p95 < UP_BELOW * FRAME_BUDGET_MS:
			offset = 1
	return {"complete": true, "samples": samples.size(), "gpu_p95_ms": p95, "scene_offset": offset,
		"reject_high": reject_high, "cpu_p95_ms": cpu_p95, "interval_p95_ms": interval_p95, "cpu_bound": cpu_bound,
		"subviewports": not allow_up}


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
	var level := str(cfg.get_value(section, "level", ""))
	return {"adapter": adapter_key(adapter), "method": method, "level": level if level in LEVEL_ORDER else "",
		"scene_offset": clampi(int(cfg.get_value(section, "scene_offset", 0)), -1, 1),
		"reject_high": bool(cfg.get_value(section, "reject_high", false)) and method == HIGH_METHOD,
		"complete": bool(cfg.get_value(section, "complete", false)),
		"pixels": maxi(int(cfg.get_value(section, "pixels", 0)), 0),
		"render_pixels": maxi(int(cfg.get_value(section, "render_pixels", 0)), 0),
		"msaa_3d": int(cfg.get_value(section, "msaa_3d", -1)),
		"gpu_p95_ms": float(cfg.get_value(section, "gpu_p95_ms", 0.0)),
		"cpu_p95_ms": float(cfg.get_value(section, "cpu_p95_ms", 0.0)),
		"interval_p95_ms": float(cfg.get_value(section, "interval_p95_ms", 0.0)),
		"cpu_bound": bool(cfg.get_value(section, "cpu_bound", false)),
		"subviewports": bool(cfg.get_value(section, "subviewports", false)),
		"refresh_hz": float(cfg.get_value(section, "refresh_hz", 0.0))}


static func save_result(result: Dictionary) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(calibration_path) # keep other GPUs' and renderers' verdicts
	if int(cfg.get_value("meta", "format", FORMAT)) != FORMAT:
		cfg = ConfigFile.new()
	cfg.set_value("meta", "format", FORMAT)
	var section := _section(str(result.get("adapter", "")), str(result.get("method", "")))
	cfg.set_value(section, "scene_offset", clampi(int(result.get("scene_offset", 0)), -1, 1))
	cfg.set_value(section, "level", str(result.get("level", "")))
	cfg.set_value(section, "reject_high", bool(result.get("reject_high", false)))
	cfg.set_value(section, "complete", bool(result.get("complete", false)))
	cfg.set_value(section, "pixels", maxi(int(result.get("pixels", 0)), 0))
	cfg.set_value(section, "render_pixels", maxi(int(result.get("render_pixels", 0)), 0))
	cfg.set_value(section, "msaa_3d", int(result.get("msaa_3d", -1)))
	cfg.set_value(section, "gpu_p95_ms", float(result.get("gpu_p95_ms", 0.0)))
	cfg.set_value(section, "samples", int(result.get("samples", 0)))
	cfg.set_value(section, "cpu_p95_ms", float(result.get("cpu_p95_ms", 0.0)))
	cfg.set_value(section, "interval_p95_ms", float(result.get("interval_p95_ms", 0.0)))
	cfg.set_value(section, "cpu_bound", bool(result.get("cpu_bound", false)))
	cfg.set_value(section, "subviewports", bool(result.get("subviewports", false)))
	cfg.set_value(section, "refresh_hz", float(result.get("refresh_hz", 0.0)))
	return cfg.save(calibration_path) == OK


## Whether `pixels` is within PIXEL_TOLERANCE of the verdict's measured output size (unknown sizes match).
## Both sides are window (output) pixels: the root viewport's render target, also Window.size.
static func size_matches(verdict: Dictionary, pixels: int) -> bool:
	return _pixels_match(int(verdict.get("pixels", 0)), pixels)


static func _pixels_match(measured: int, pixels: int) -> bool:
	if measured <= 0 or pixels <= 0:
		return true
	var ratio := float(maxi(measured, pixels)) / float(mini(measured, pixels))
	return ratio <= PIXEL_TOLERANCE


## The GPU workload identity of `viewport` (the root viewport by default): output pixels, the internal 3D pixels
## after the applied 3D scale (the selected reconstruction after any fallback) and the 3D MSAA. {} when unknown.
static func current_workload(viewport: Viewport = null) -> Dictionary:
	if viewport == null:
		var tree := Engine.get_main_loop() as SceneTree
		viewport = tree.root if tree != null else null
	if not is_instance_valid(viewport):
		return {}
	var output := Reconstruction.viewport_output_size(viewport)
	if (output.x <= 0 or output.y <= 0) and viewport is Window:
		output = (viewport as Window).size
	if output.x <= 0 or output.y <= 0:
		return {}
	var internal := Reconstruction.nominal_input_size(output, viewport.scaling_3d_scale)
	return {"pixels": output.x * output.y, "render_pixels": internal.x * internal.y, "msaa_3d": int(viewport.msaa_3d)}


## Whether a verdict's internal 3D size and 3D MSAA describe `workload` (unknown values on either side match).
## The output size is compared separately (size_matches): callers pass it from their own boundary.
static func workload_matches(verdict: Dictionary, workload: Dictionary) -> bool:
	if not _pixels_match(int(verdict.get("render_pixels", 0)), int(workload.get("render_pixels", 0))):
		return false
	var measured_msaa := int(verdict.get("msaa_3d", -1))
	var msaa := int(workload.get("msaa_3d", -1))
	return measured_msaa < 0 or msaa < 0 or measured_msaa == msaa


## Whether a complete stored measurement rejects automatic High for an output of up to `pixels` (the screen, the
## largest output a launch can open) on this GPU. One-sided: a High miss at a smaller or similar output also
## holds for a larger one (a 1080p window on a 4K screen keeps its veto), while a miss measured at a materially
## larger output (4K) says nothing about a smaller screen (1080p). Unknown sizes keep the veto.
static func rejects_high(adapter: String, pixels: int) -> bool:
	var verdict := load_result(adapter, HIGH_METHOD)
	var measured := int(verdict.get("pixels", 0))
	return bool(verdict.get("reject_high", false)) and bool(verdict.get("complete", false)) \
		and (measured <= 0 or pixels <= 0 or float(measured) <= PIXEL_TOLERANCE * float(pixels))


## Whether a flight on this GPU and renderer at `pixels` should be measured. `automatic_level` is the uncalibrated
## Automatic Scene detail when Automatic decides it: a verdict measured below it, without a "down" result that
## already caps it, leaves that level unmeasured (for example after a policy update starts Automatic at Extreme).
## `workload` defaults to the root viewport's current_workload(); a changed 3D scale or MSAA measures again.
static func needed(adapter: String, method: String, pixels: int = 0, automatic_level: String = "",
		workload: Dictionary = {}) -> bool:
	if adapter.is_empty():
		return false
	var verdict := load_result(adapter, method)
	if verdict.is_empty() or not size_matches(verdict, pixels) \
			or not workload_matches(verdict, workload if not workload.is_empty() else current_workload()):
		return true
	var measured := LEVEL_ORDER.find(str(verdict.get("level", "")))
	return LEVEL_ORDER.find(automatic_level) > measured and int(verdict.get("scene_offset", 0)) >= 0


## The level a stored verdict leaves of an uncalibrated Automatic `level`. A "down" verdict caps every level at or
## above the one it measured; a "up" verdict raises only the level it measured (never to Extreme); a verdict
## for another level changes nothing else.
static func apply_verdict(level: String, verdict: Dictionary) -> String:
	var offset := int(verdict.get("scene_offset", 0))
	var measured := str(verdict.get("level", ""))
	if offset == 0:
		return level
	if measured == level:
		return shifted_level(level, offset)
	if offset < 0 and LEVEL_ORDER.has(measured) and LEVEL_ORDER.find(level) >= LEVEL_ORDER.find(measured):
		return shifted_level(measured, offset)
	return level


## Deletes every verdict ("Restore graphics defaults").
static func clear() -> void:
	if FileAccess.file_exists(calibration_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(calibration_path))


## Applies a stored offset to an Automatic level: Low ↔ Medium ↔ High. A measurement never raises a level to
## Extreme; an Automatic Extreme (VQ-07h-A4) that misses the frame drops to High.
static func shifted_level(level: String, offset: int) -> String:
	if level == "extreme":
		return "high" if offset < 0 else level
	var order: Array[String] = ["low", "medium", "high"]
	var index := order.find(level)
	if index < 0 or offset == 0:
		return level
	return order[clampi(index + offset, 0, order.size() - 1)]
