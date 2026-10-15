## Self-contained player for the Nitro-specific procedural voice.
## The accepted telemetry observer is read-only and never touches shared aircraft/Bisonte audio.
extends AudioStreamPlayer3D
class_name NitroEngineAudio

const Voice := preload("res://audio/nitro_voice.gd")
const TARGET_SECONDS: float = 0.05
const BUFFER_SECONDS: float = 0.15

var voice
var capacity_frames: int = 0
var queued_frames: int = 0
var pushed_frames: int = 0
var _generator: AudioStreamGenerator
var _paused_or_disabled: bool = false
var _last_sound_eligible: bool = false
var _playback_id: int = 0


## Create and attach an isolated spatial Nitro audio node.
static func create(parent: Node) -> NitroEngineAudio:
	if parent == null or not is_instance_valid(parent):
		return null
	var player := NitroEngineAudio.new()
	player.name = "NitroEngineAudio"
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.volume_db = -4.0
	player.max_distance = 70.0
	player.unit_size = 6.0
	player.voice = Voice.new()
	player._generator = AudioStreamGenerator.new()
	player._generator.mix_rate = Voice.RATE
	player._generator.buffer_length = BUFFER_SECONDS
	player.stream = player._generator
	parent.add_child(player)
	if player.is_inside_tree() and not player.playing:
		player._begin_playback()
	return player


## Feed one accepted telemetry snapshot. Callers may also invoke refill() explicitly.
func observe(telemetry: Dictionary, controls: Dictionary, paused: bool, enabled: bool) -> void:
	if voice == null:
		return
	voice.observe(telemetry, controls, paused, enabled)
	if paused or not enabled:
		if not _paused_or_disabled:
			stop()
			_playback_id = 0
			capacity_frames = 0
			queued_frames = 0
		_paused_or_disabled = true
		_last_sound_eligible = false
		return
	var eligible: bool = voice.is_sound_eligible()
	if _paused_or_disabled:
		_restart_playback()
		_paused_or_disabled = false
		voice.reset_output_fade()
		_last_sound_eligible = eligible
		return
	if eligible != _last_sound_eligible:
		# Flush up to 50 ms of stale running/stopped sound at the state boundary.
		_restart_playback()
		voice.reset_output_fade()
	_last_sound_eligible = eligible


## Bounded target-fill operation. Returns the frames that may safely be pushed now.
static func bounded_refill_frames(capacity: int, available: int, target: int, max_block: int = Voice.MAX_BLOCK_FRAMES) -> int:
	if capacity <= 0 or available <= 0 or target <= 0 or max_block <= 0:
		return 0
	var free_frames: int = mini(capacity, available)
	var queued: int = maxi(0, capacity - free_frames)
	return clampi(target - queued, 0, mini(free_frames, max_block))


func refill() -> int:
	if voice == null or _paused_or_disabled or not playing:
		return 0
	var playback := get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return 0
	if playback.get_instance_id() != _playback_id:
		_playback_id = playback.get_instance_id()
		capacity_frames = playback.get_frames_available()
		queued_frames = 0
	var available: int = playback.get_frames_available()
	queued_frames = maxi(0, capacity_frames - available)
	var target_frames: int = ceili(TARGET_SECONDS * Voice.RATE)
	var frame_count: int = bounded_refill_frames(capacity_frames, available, target_frames)
	if frame_count <= 0:
		return 0
	var pcm: PackedVector2Array = voice.render(frame_count)
	if playback.push_buffer(pcm):
		pushed_frames += frame_count
		queued_frames += frame_count
		return frame_count
	return 0


func _ready() -> void:
	if voice == null:
		voice = Voice.new()
	if _generator == null:
		_generator = AudioStreamGenerator.new()
		_generator.mix_rate = Voice.RATE
		_generator.buffer_length = BUFFER_SECONDS
		stream = _generator
	if not playing:
		_begin_playback()


func _exit_tree() -> void:
	stop()


func _begin_playback() -> void:
	play()
	_pin_generator_to_playback()


func _restart_playback() -> void:
	stop()
	play()
	_playback_id = 0
	capacity_frames = 0
	queued_frames = 0
	_pin_generator_to_playback()


func _pin_generator_to_playback() -> void:
	var playback := get_stream_playback() as AudioStreamGeneratorPlayback
	if playback != null:
		# Godot generator playback can outlive this node during a fade. Keep its source alive,
		# matching the lifetime protection used by the existing shared generator adapters.
		playback.set_meta("openrc_generator_source", stream)
