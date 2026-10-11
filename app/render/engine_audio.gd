# G3b: target-fill adapter and detached post-tick RPM observation.
extends AudioStreamPlayer3D

const Voice := preload("res://render/engine_voice.gd")
const TARGET_SECONDS := 0.05
const FAST_TARGET_SECONDS := 0.035
# Spare capacity is not a latency target. The adapter never fills this whole ring.
const BUFFER_SECONDS := 0.15

var voice := Voice.new()
var capacity := 0
var queued_frames := 0
var pushed_frames := 0
var target_frames := ceili(TARGET_SECONDS * Voice.RATE)
var snapshot_tick := -1
var snapshot_time := 0.0
var snapshot_rpm := 0.0
var snapshot_max_rpm := 1.0
var _simulation: WeakRef
var _playback_id := 0
var _was_paused := false
var _mix_period := 0.0
var _last_refill_usec := 0


func begin_voice() -> void:
	play()
	var playback := get_stream_playback() as AudioStreamGeneratorPlayback
	if playback != null:
		# Godot 4.7.2's generator playback keeps a raw pointer to its stream. The
		# audio server can finish a fade after this node is freed; pin that source
		# to the playback itself, without retaining this node or forming a cycle.
		playback.set_meta("openrc_generator_source", stream)


func restart_voice() -> void:
	stop()
	begin_voice()


func observe(simulation: Node, max_rpm: float) -> void:
	_simulation = weakref(simulation)
	snapshot_max_rpm = max_rpm
	simulation.stepped.connect(_accepted_tick)
	simulation.paused_changed.connect(_paused_changed)


func _paused_changed(paused: bool) -> void:
	if paused:
		_was_paused = true


func _accepted_tick(tick: int, t: float, _state: PackedFloat64Array, _loads: PackedFloat64Array,
		_inputs: PackedFloat64Array, aux: PackedFloat64Array) -> void:
	snapshot_tick = tick
	snapshot_time = t
	snapshot_rpm = aux[0]
	if tick == 0:
		voice.reset(snapshot_rpm, snapshot_max_rpm)


## The simulation is observed only; the generator and oscillator belong to this player.
func refill(rpm: float, max_rpm: float) -> float:
	if _simulation != null:
		var sim: Node = _simulation.get_ref()
		if sim == null:
			return voice.phase
		# Restore does not emit stepped. A changed paused state must not retain old audio.
		if sim.paused or stream_paused:
			_was_paused = true
			return voice.phase
		if _was_paused:
			restart_voice()
			voice.reset(sim.aux[0], max_rpm)
			_was_paused = false
			snapshot_tick = sim.tick
			snapshot_time = sim.time()
			snapshot_rpm = sim.aux[0]
		rpm = snapshot_rpm
	if stream_paused:
		return voice.phase
	var playback := get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return voice.phase
	if playback.get_instance_id() != _playback_id:
		# Retain identity only. Keeping a playback Ref across frames leaks on SceneTree.quit().
		_playback_id = playback.get_instance_id()
		capacity = playback.get_frames_available()
		# Dummy consumes 4096 output frames in one burst (92.9 ms at 44.1 kHz),
		# regardless of output-latency settings. Also cover unusually large device periods.
		# Normal real-device periods retain the 50 ms target. Reserve one resampler block.
		_mix_period = maxf(0.0, AudioServer.get_time_since_last_mix() + AudioServer.get_time_to_next_mix())
		_last_refill_usec = 0
		voice.reset(rpm, max_rpm)
	var now := Time.get_ticks_usec()
	var gap := float(now - _last_refill_usec) / 1000000.0 if _last_refill_usec > 0 else TARGET_SECONDS
	_last_refill_usec = now
	# At 60+ FPS the old queue can be shorter. Keep enough for the render interval,
	# a complete driver burst and the resampler; a slow frame returns to the safe target.
	var seconds := FAST_TARGET_SECONDS if gap <= 0.018 else TARGET_SECONDS
	var reserve := _mix_period if _mix_period >= gap else minf(gap, 0.034) + _mix_period
	target_frames = mini(capacity, maxi(ceili(seconds * Voice.RATE), ceili(reserve * Voice.RATE) + 128))
	var available := playback.get_frames_available()
	var frames := clampi(target_frames - (capacity - available), 0, available)
	queued_frames = capacity - available
	if frames <= 0:
		return voice.phase
	var buffer := voice.render(rpm, max_rpm, frames)
	if playback.push_buffer(buffer):
		pushed_frames += frames
		queued_frames += frames
	return voice.phase
