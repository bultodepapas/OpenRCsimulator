# UI-28-R3 native mixer capture. No microphone or user audio input.
extends SceneTree
const MenuSounds = preload("res://ui/menu_audio.gd")
var out := ProjectSettings.globalize_path("res://../tmp/menu-direction/r3-audio")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	var host := Node.new()
	root.add_child(host)
	var service := MenuSounds.attach(host, func() -> Control: return null)
	var recorder := AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(0, recorder)
	await create_timer(0.25).timeout
	service.set_volume(0.35)
	recorder.set_recording_active(true)
	await create_timer(0.2).timeout
	for cue: StringName in [&"focus", &"press", &"select", &"change", &"accept", &"back", &"reject"]:
		print("AUDIO cue=",cue," accepted=",service.play(cue))
		await create_timer(0.7).timeout
	recorder.set_recording_active(false)
	var sample: AudioStreamWAV = recorder.get_recording()
	print("AUDIO recording=",sample.save_to_wav(out.path_join("menu-cues.wav"))," bytes=",sample.data.size()," mix_rate=",sample.mix_rate)
	service.set_volume(0.0)
	recorder.set_recording_active(true)
	service.play(&"accept")
	await create_timer(0.7).timeout
	recorder.set_recording_active(false)
	sample = recorder.get_recording()
	print("AUDIO mute=",sample.save_to_wav(out.path_join("muted.wav"))," bytes=",sample.data.size())
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0)-1)
	host.queue_free()
	await process_frame
	quit()
