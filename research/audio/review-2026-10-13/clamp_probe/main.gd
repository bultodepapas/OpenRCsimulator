extends Node3D
# Each case runs 1 s: [distance_m, volume_db]. unit_size 8, max_db 0 as in app/audio/soundscape.gd.
var cases := [[2.0, -6.0], [2.0, -16.0], [2.0, -26.0], [8.0, -6.0], [8.0, -16.0], [16.0, -16.0], [32.0, -16.0], [100.0, -6.0], [100.0, -16.0], [100.0, -26.0]]
var player: AudioStreamPlayer3D
var frame := 0

func _ready() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 48000
	var data := PackedByteArray()
	data.resize(48000 * 2)
	for i in 48000:
		data.encode_s16(i * 2, int(16000.0 * sin(TAU * 1000.0 * i / 48000.0)))
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = 48000
	player = AudioStreamPlayer3D.new()
	player.stream = wav
	player.unit_size = 8.0
	player.max_db = 0.0
	player.attenuation_filter_db = 0.0
	add_child(player)
	_apply(0)
	player.play()

func _apply(i: int) -> void:
	player.position = Vector3(0, 0, -cases[i][0])
	player.volume_db = cases[i][1]

func _process(_d: float) -> void:
	frame += 1
	var i := frame / 60
	if i >= cases.size():
		get_tree().quit()
	elif frame % 60 == 0:
		_apply(i)
