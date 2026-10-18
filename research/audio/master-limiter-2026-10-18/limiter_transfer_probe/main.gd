extends Node
# AUD-12 limiter transfer probe. A 1 kHz tone ramps from -12 to +6 dBFS (pre-effect) over 6 s, then holds -20 dBFS
# for 4 s (recovery). FX selects the bus effect: none | limiter | hard | compressor. Measure with measure_transfer.py.
const RATE: int = 48000
const RAMP_S: float = 6.0
const HOLD_S: float = 4.0
var frame: int = 0


func _ready() -> void:
	AudioServer.add_bus()
	var bus: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus, "probe")
	AudioServer.set_bus_send(bus, &"Master")
	match OS.get_environment("FX"):
		"limiter": # as the soundscape bus since AUD-07d
			var limiter := AudioEffectLimiter.new()
			limiter.ceiling_db = -1.0
			limiter.threshold_db = -1.0
			AudioServer.add_bus_effect(bus, limiter)
		"hard":
			var hard := AudioEffectHardLimiter.new()
			hard.ceiling_db = -1.0
			hard.release = 0.1
			AudioServer.add_bus_effect(bus, hard)
		"compressor":
			var compressor := AudioEffectCompressor.new()
			compressor.threshold = -6.0
			compressor.ratio = 20.0
			compressor.attack_us = 20.0
			compressor.release_ms = 100.0
			AudioServer.add_bus_effect(bus, compressor)
	var player := AudioStreamPlayer.new()
	player.stream = _ramp()
	player.bus = "probe"
	player.volume_db = 12.0
	add_child(player)
	player.play()


func _ramp() -> AudioStreamWAV:
	var frames: int = int((RAMP_S + HOLD_S) * RATE)
	var data := PackedByteArray()
	data.resize(frames * 4) # 16-bit stereo; the ramp needs headroom above 0 dBFS, so it plays at -12 dB below
	for i in frames:
		var t: float = float(i) / RATE
		var level_db: float = lerpf(-12.0, 6.0, t / RAMP_S) if t < RAMP_S else -20.0
		# Source peaks at level_db - 12 dBFS; the player's +12 dB volume restores level_db before the bus effect.
		var sample: int = int(32767.0 * db_to_linear(level_db - 12.0) * sin(TAU * 1000.0 * t))
		data.encode_s16(i * 4, sample)
		data.encode_s16(i * 4 + 2, sample)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = true
	wav.data = data
	return wav


func _process(_delta: float) -> void:
	frame += 1
	if frame >= int((RAMP_S + HOLD_S) * 60.0) + 30:
		get_tree().quit()
