# Placeholder engine timbre (D5), now using the G3b low-latency audio adapter.
# Source acoustics and physical propagation remain separate G3 steps.
extends RefCounted

const Voice := preload("res://render/engine_voice.gd")
const Audio := preload("res://render/engine_audio.gd")
const MIX_RATE := Voice.RATE
const HARMONICS := Voice.HARMONICS


static func firing_frequency(rpm: float) -> float:
	return maxf(rpm, 0.0) / 60.0


static func synthesize(phase: float, freq: float, amp: float, frames: int, rate := MIX_RATE) -> Array:
	return Voice.synthesize(phase, freq, amp, frames, rate)


## Positional source with an optional read-only accepted-tick observer.
static func create(parent: Node3D, simulation: Node = null, max_rpm := 1.0) -> AudioStreamPlayer3D:
	Voice.prepare()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = Audio.BUFFER_SECONDS
	var player := Audio.new()
	player.name = "engine_sound"
	player.stream = gen
	player.unit_size = 8.0
	player.max_db = 0.0
	if simulation != null:
		player.observe(simulation, max_rpm)
	parent.add_child(player)
	player.begin_voice()
	return player


## Compatibility entry point; phase belongs to the player, never a global oscillator.
static func update(player: AudioStreamPlayer3D, _phase: float, rpm: float, max_rpm: float) -> float:
	return player.refill(rpm, max_rpm)


static func restart(player: AudioStreamPlayer3D) -> void:
	player.restart_voice()
