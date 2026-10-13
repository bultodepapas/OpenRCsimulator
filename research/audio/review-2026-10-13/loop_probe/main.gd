extends Node3D
## Loop-wrap probe (audio realism plan, F14). Plays app/assets/audio/soundscape/motor_combustion.wav, 4 s per case:
## A recipe as before AUD-07a (loop_end = source frames), pitch 1.0; B same, pitch 0.87;
## C guard tail (first 64 frames copied after loop_end), pitch 1.0; D guard tail, pitch 0.87.
var players: Array = []
var frame := 0

func _ready() -> void:
	add_child(Camera3D.new())
	var path := ProjectSettings.globalize_path("res://").path_join("../../../../app/assets/audio/soundscape/motor_combustion.wav").simplify_path()
	var src := AudioStreamWAV.load_from_file(path)
	var frames: int = src.data.size() / 2
	for i in 4:
		var wav: AudioStreamWAV = src.duplicate()
		if i >= 2:
			var bytes: PackedByteArray = src.data.duplicate()
			bytes.append_array(src.data.slice(0, 64 * 2))
			wav.data = bytes
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = frames
		var p := AudioStreamPlayer.new()
		p.stream = wav
		p.pitch_scale = 0.87 if i % 2 == 1 else 1.0
		add_child(p)
		players.append(p)

func _process(_d: float) -> void:
	if frame % 240 == 0:
		var i := frame / 240
		for p in players:
			p.stop()
		if i >= players.size():
			get_tree().quit()
			return
		players[i].play()
	frame += 1
