extends Node
# AUD-12 repeated-overload probe: a -20 dBFS 1 kHz tone with five 40 ms 150 Hz bursts at BURST_DB (default +12),
# at 2, 4, 6, 8 and 10 s, through AudioEffectHardLimiter (ceiling CEIL dB, release REL s). Ends at 16 s.
# Measure the tone level before the first burst and 1.5 s after each with measure_bursts.py.
var frame: int = 0
var burst: AudioStreamPlayer


func _ready() -> void:
	AudioServer.add_bus()
	var bus: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus, "lim")
	AudioServer.set_bus_send(bus, &"Master")
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = float(OS.get_environment("CEIL")) if OS.has_environment("CEIL") else -1.0
	limiter.release = float(OS.get_environment("REL")) if OS.has_environment("REL") else 0.12
	AudioServer.add_bus_effect(bus, limiter)
	var tone := AudioStreamPlayer.new()
	tone.stream = _sine(1000.0, 48000, true)
	tone.bus = "lim"
	tone.volume_db = -20.0 + 0.27 # 32000/32767 peak scale
	add_child(tone)
	tone.play()
	burst = AudioStreamPlayer.new()
	burst.stream = _sine(150.0, 1920, false)
	burst.bus = "lim"
	burst.volume_db = float(OS.get_environment("BURST_DB")) if OS.has_environment("BURST_DB") else 12.0
	add_child(burst)


func _sine(freq: float, frames: int, loop: bool) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 48000
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		data.encode_s16(i * 2, int(32000.0 * sin(TAU * freq * i / 48000.0)))
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = frames
	return wav


func _process(_d: float) -> void:
	frame += 1
	if frame in [120, 240, 360, 480, 600]:
		burst.play()
	if frame >= 960:
		get_tree().quit()
