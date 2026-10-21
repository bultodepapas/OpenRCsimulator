## Bounded worker-side PCM producer for the procedural glow engine voice.
##
## The owner must start the AudioStreamPlayer on the main thread, keep it stream-paused, obtain
## its AudioStreamGeneratorPlayback, and then call start(). Keep it paused until is_primed() is
## true. The worker owns its GlowVoice instance and only receives whitelisted detached telemetry.
## Call stop() and wait for it to join before changing or freeing the player/playback.
extends RefCounted

const GlowVoice := preload("res://audio/glow_voice.gd")

const MAX_QUEUE_SECONDS := 0.05
const MAX_RENDER_CHUNK_FRAMES := 256
const WORKER_SLEEP_USEC := 2000
const TELEMETRY_KEYS: Array[String] = [
	"family", "rpm", "max_rpm", "running", "firing_fraction", "load", "throttle", "blade_count",
	"phase_revolutions", "opportunity_count", "fire_count", "firing_accumulator", "fuel_kg",
	"source_vibration",
]
const PHYSICAL_ANCHOR_KEYS: Array[String] = [
	"phase_revolutions", "opportunity_count", "fire_count", "firing_accumulator", "audio_queue_frames",
]

var _mutex := Mutex.new()
var _thread := Thread.new()
var _playback: AudioStreamGeneratorPlayback
var _fallback_voice: Variant
var _fallback_enabled := false
var _fallback_capacity_frames := 0
var _fallback_last_rendered_revision := -1
var _latest_snapshot: Dictionary = {}
var _published_revision := 0
var _stop_requested := false
var _sample_rate_hz := GlowVoice.RATE
var _target_frames := 0
var _stats: Dictionary = {}


func _init() -> void:
	_stats = _empty_stats()


static func snapshot_for_render(snapshot: Dictionary, revision: int, last_rendered_revision: int,
		queued_frames: int) -> Dictionary:
	## A physical phase anchor belongs to one published accepted-state revision. Reusing it for
	## each block during a main-thread stall would replay that old phase. Repeat blocks instead
	## extrapolate the last accepted RPM over generated audio time.
	var render_snapshot: Dictionary = snapshot.duplicate(true)
	if revision == last_rendered_revision:
		for key: String in PHYSICAL_ANCHOR_KEYS:
			render_snapshot.erase(key)
	else:
		render_snapshot.erase("audio_queue_frames")
		render_snapshot["audio_queue_frames"] = maxi(queued_frames, 0)
	return render_snapshot


func start(playback: AudioStreamGeneratorPlayback, initial_telemetry: Dictionary,
		sample_rate_hz: float = GlowVoice.RATE) -> bool:
	if playback == null or not is_finite(sample_rate_hz) or sample_rate_hz <= 0.0:
		return false
	if _thread.is_started() or is_running():
		return false
	_thread = Thread.new()
	_sample_rate_hz = sample_rate_hz
	_target_frames = maxi(1, int(floor(sample_rate_hz * MAX_QUEUE_SECONDS)))
	_mutex.lock()
	_playback = playback
	_latest_snapshot = _detached_telemetry(initial_telemetry)
	_published_revision += 1
	_stop_requested = false
	_stats = _empty_stats()
	_stats["running"] = true
	_stats["target_frames"] = _target_frames
	_stats["published_revision"] = _published_revision
	_mutex.unlock()
	var start_error: int = _thread.start(Callable(self, "_worker_main"))
	if start_error != OK:
		_mutex.lock()
		_fallback_enabled = true
		_stats["running"] = true
		_stats["fallback"] = true
		_stats["fallback_reason"] = "Thread.start failed with error %d" % int(start_error)
		_mutex.unlock()
		# Fallback takes sole ownership of its voice on the calling thread; no worker started.
		_fallback_voice = GlowVoice.new()
		_fallback_voice.reset()
		_fallback_refill()
	return true


func update_telemetry(snapshot: Dictionary) -> void:
	var detached: Dictionary = _detached_telemetry(snapshot)
	_mutex.lock()
	# Duplicate main-frame updates with unchanged accepted telemetry are not new phase anchors.
	if detached != _latest_snapshot:
		_latest_snapshot = detached
		_published_revision += 1
		_stats["published_revision"] = _published_revision
	var use_fallback: bool = _fallback_enabled
	_mutex.unlock()
	if use_fallback:
		_fallback_refill()


func telemetry_snapshot() -> Dictionary:
	_mutex.lock()
	var result: Dictionary = _latest_snapshot.duplicate(true)
	_mutex.unlock()
	return result


func stats() -> Dictionary:
	_mutex.lock()
	var result: Dictionary = _stats.duplicate(true)
	_mutex.unlock()
	return result


func is_running() -> bool:
	_mutex.lock()
	var result: bool = bool(_stats.get("running", false))
	_mutex.unlock()
	return result


func is_primed() -> bool:
	_mutex.lock()
	var result: bool = bool(_stats.get("primed", false))
	_mutex.unlock()
	return result


func stop() -> void:
	if _thread.is_started():
		_mutex.lock()
		_stop_requested = true
		_mutex.unlock()
		# Never hold _mutex or AudioServer's lock while joining. Worker sleeps are bounded to 2 ms.
		_thread.wait_to_finish()
	_fallback_voice = null
	_fallback_enabled = false
	_fallback_capacity_frames = 0
	_fallback_last_rendered_revision = -1
	_mutex.lock()
	_playback = null
	_stop_requested = false
	_stats["running"] = false
	_stats["primed"] = false
	_mutex.unlock()
	_thread = Thread.new()


func reset() -> void:
	stop()
	_mutex.lock()
	_latest_snapshot.clear()
	_published_revision = 0
	_stats = _empty_stats()
	_mutex.unlock()


func _worker_main() -> void:
	# This instance is created, used, and destroyed only by the producer thread.
	var voice: Variant = GlowVoice.new()
	voice.reset()
	var capacity_frames := 0
	var last_rendered_revision := -1
	while true:
		var snapshot: Dictionary
		var revision: int
		_mutex.lock()
		if _stop_requested:
			_mutex.unlock()
			break
		snapshot = _latest_snapshot.duplicate(true)
		revision = _published_revision
		_mutex.unlock()

		# AudioStreamGeneratorPlayback's ring indices are plain integers in Godot 4.7. The
		# documented AudioServer lock serializes this short access with the WASAPI mix callback.
		AudioServer.lock()
		var available_frames: int = _playback.get_frames_available()
		var skipped_blocks: int = _playback.get_skips()
		AudioServer.unlock()
		if capacity_frames == 0:
			capacity_frames = available_frames
		if capacity_frames <= 0:
			_set_worker_error("AudioStreamGeneratorPlayback has no writable frames")
			break

		var queued_frames: int = maxi(capacity_frames - available_frames, 0)
		var target_frames: int = mini(_target_frames, capacity_frames)
		_set_queue_status(queued_frames, available_frames, capacity_frames, target_frames, skipped_blocks)
		if queued_frames >= target_frames:
			OS.delay_usec(WORKER_SLEEP_USEC)
			continue

		var render_frames: int = mini(MAX_RENDER_CHUNK_FRAMES,
			mini(target_frames - queued_frames, available_frames))
		if render_frames <= 0:
			OS.delay_usec(WORKER_SLEEP_USEC)
			continue
		var render_snapshot: Dictionary = snapshot_for_render(snapshot, revision,
			last_rendered_revision, queued_frames)
		var pcm: PackedVector2Array = voice.render_telemetry(render_snapshot, render_frames)

		# Synthesis stays outside the server lock. With one producer and no playback lifecycle
		# changes until join, the mixer can only increase the writable space while we render.
		AudioServer.lock()
		var push_available: int = _playback.get_frames_available()
		var pushed: bool = false
		if push_available >= pcm.size():
			pushed = _playback.push_buffer(pcm)
		var remaining_frames: int = _playback.get_frames_available()
		skipped_blocks = _playback.get_skips()
		AudioServer.unlock()
		if not pushed:
			_set_worker_error("AudioStreamGeneratorPlayback rejected a bounded PCM chunk")
			break
		last_rendered_revision = revision
		_set_render_status(voice.phase, render_frames, revision, remaining_frames,
			capacity_frames, target_frames, skipped_blocks)
	_mutex.lock()
	_stats["running"] = false
	_stats["primed"] = false
	_mutex.unlock()


func _set_queue_status(queued: int, available: int, capacity: int, target: int, skips: int) -> void:
	_mutex.lock()
	_stats["queue_frames"] = queued
	_stats["available_frames"] = available
	_stats["capacity_frames"] = capacity
	_stats["target_frames"] = target
	_stats["skips"] = skips
	if queued >= target:
		_stats["primed"] = true
	_mutex.unlock()


func _set_render_status(phase_cycles: float, frames: int, revision: int, available: int,
		capacity: int, target: int, skips: int) -> void:
	_mutex.lock()
	_stats["queue_frames"] = maxi(capacity - available, 0)
	_stats["available_frames"] = available
	_stats["capacity_frames"] = capacity
	_stats["target_frames"] = target
	_stats["skips"] = skips
	if int(_stats["queue_frames"]) >= target:
		_stats["primed"] = true
	_stats["rendered_blocks"] = int(_stats["rendered_blocks"]) + 1
	_stats["rendered_frames"] = int(_stats["rendered_frames"]) + frames
	_stats["rendered_revision"] = revision
	_stats["phase_cycles"] = phase_cycles
	_mutex.unlock()


func _set_worker_error(message: String) -> void:
	_mutex.lock()
	_stats["worker_error"] = message
	_stats["primed"] = false
	_mutex.unlock()


static func _detached_telemetry(snapshot: Dictionary) -> Dictionary:
	var detached: Dictionary = {}
	for key: String in TELEMETRY_KEYS:
		if snapshot.has(key):
			var value: Variant = snapshot[key]
			if key == "source_vibration" and value is Dictionary:
				detached[key] = value.duplicate(true)
			else:
				detached[key] = value
	return detached


static func _empty_stats() -> Dictionary:
	return {
		"running": false,
		"fallback": false,
		"primed": false,
		"queue_frames": 0,
		"available_frames": 0,
		"capacity_frames": 0,
		"target_frames": 0,
		"skips": 0,
		"rendered_blocks": 0,
		"rendered_frames": 0,
		"published_revision": 0,
		"rendered_revision": -1,
		"phase_cycles": 0.0,
		"worker_error": "",
		"fallback_reason": "",
	}


func _fallback_refill() -> void:
	if not _fallback_enabled or _fallback_voice == null or _playback == null:
		return
	var snapshot: Dictionary
	var revision: int
	var rendered_this_update := 0
	_mutex.lock()
	snapshot = _latest_snapshot.duplicate(true)
	revision = _published_revision
	_mutex.unlock()
	while rendered_this_update < _target_frames:
		AudioServer.lock()
		var available_frames: int = _playback.get_frames_available()
		var skipped_blocks: int = _playback.get_skips()
		AudioServer.unlock()
		if _fallback_capacity_frames == 0:
			_fallback_capacity_frames = available_frames
		if _fallback_capacity_frames <= 0:
			_set_worker_error("AudioStreamGeneratorPlayback has no writable frames")
			return
		var queued_frames: int = maxi(_fallback_capacity_frames - available_frames, 0)
		var target_frames: int = mini(_target_frames, _fallback_capacity_frames)
		_set_queue_status(queued_frames, available_frames, _fallback_capacity_frames, target_frames, skipped_blocks)
		if queued_frames >= target_frames:
			return
		var render_frames: int = mini(MAX_RENDER_CHUNK_FRAMES,
		mini(target_frames - queued_frames,
			mini(available_frames, _target_frames - rendered_this_update)))
		if render_frames <= 0:
			return
		var render_snapshot: Dictionary = snapshot_for_render(snapshot, revision,
			_fallback_last_rendered_revision, queued_frames)
		var pcm: PackedVector2Array = _fallback_voice.render_telemetry(render_snapshot, render_frames)
		AudioServer.lock()
		var push_available: int = _playback.get_frames_available()
		var pushed: bool = false
		if push_available >= pcm.size():
			pushed = _playback.push_buffer(pcm)
		var remaining_frames: int = _playback.get_frames_available()
		skipped_blocks = _playback.get_skips()
		AudioServer.unlock()
		if not pushed:
			_set_worker_error("AudioStreamGeneratorPlayback rejected a bounded PCM chunk")
			return
		_fallback_last_rendered_revision = revision
		rendered_this_update += render_frames
		_set_render_status(_fallback_voice.phase, render_frames, revision, remaining_frames,
			_fallback_capacity_frames, target_frames, skipped_blocks)
