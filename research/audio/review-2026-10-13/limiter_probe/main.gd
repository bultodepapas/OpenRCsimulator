extends Node
# Limiter recovery probe (audio realism plan, F15). Env: FX=hard|hardslow|limiter|compressor, REL=<release s> (hardslow), BURST_DB=<dB>.
# A steady 1 kHz tone plays throughout; at t = 2.0 s a 40 ms 150 Hz burst at BURST_DB plays on the same bus.
var frame := 0
var burst: AudioStreamPlayer

func _ready() -> void:
	AudioServer.add_bus()
	var bus := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus, "lim")
	AudioServer.set_bus_send(bus, &"Master")
	match OS.get_environment("FX"):
		"hard":
			var limiter := AudioEffectHardLimiter.new()
			limiter.ceiling_db = -1.0
			limiter.release = 0.12
			AudioServer.add_bus_effect(bus, limiter)
		"limiter":
			var old_limiter := AudioEffectLimiter.new()
			old_limiter.ceiling_db = -1.0
			old_limiter.threshold_db = -1.0
			AudioServer.add_bus_effect(bus, old_limiter)
		"compressor":
			var comp := AudioEffectCompressor.new()
			comp.threshold = -3.0
			comp.ratio = 20.0
			comp.attack_us = 20.0
			comp.release_ms = 120.0
			AudioServer.add_bus_effect(bus, comp)
		"hardslow":
			var limiter2 := AudioEffectHardLimiter.new()
			limiter2.ceiling_db = -1.0
			limiter2.release = float(OS.get_environment("REL"))
			AudioServer.add_bus_effect(bus, limiter2)
	var tone := _sine(1000.0, 48000, true)
	var p := AudioStreamPlayer.new()
	p.stream = tone
	p.bus = "lim"
	p.volume_db = -20.0 + 3.0 # sine peak -> ~-20 dBFS RMS-ish reference; relative levels matter
	add_child(p)
	p.play()
	burst = AudioStreamPlayer.new()
	burst.stream = _sine(150.0, 1920, false) # 40 ms
	burst.bus = "lim"
	burst.volume_db = float(OS.get_environment("BURST_DB"))
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
	if frame == 120:
		burst.play()
	if frame >= 1260:
		get_tree().quit()
