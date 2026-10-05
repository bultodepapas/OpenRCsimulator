# Research 19: what the real app's engine sound does while the simulation is paused, and what
# stream_paused / stop()+play() / bus volume do to the AudioStreamGenerator queue. Headless, no sound card:
# it reads ring-buffer fill and the Master bus peak meter fed by the Dummy driver's mixing thread.
# It never judges anything audible. Run from the repo root (does not modify app/):
#   .tools/Godot_v4.7.2-stable_linux.x86_64 --headless --audio-driver Dummy --path app \
#     --script "$PWD/docs/research/menu-investigations/probes/19-audio-pause-probe.gd"
extends SceneTree


func _peak() -> float:
	return AudioServer.get_bus_peak_volume_left_db(0, 0)


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _pb(main: Node) -> AudioStreamGeneratorPlayback:
	return main._engine_audio.get_stream_playback() as AudioStreamGeneratorPlayback


func _row(label: String, main: Node) -> void:
	var sim: Node = main.session.sim
	var pb := _pb(main) if main._engine_audio.has_stream_playback() else null
	print("%-34s tick=%5d rpm=%7.1f prop=%7.2f rad peak=%7.1f dB free=%s skips=%s stream_paused=%s" % [
		label, sim.tick, sim.aux[0], main._prop_angle, _peak(),
		pb.get_frames_available() if pb else "-", pb.get_skips() if pb else "-", main._engine_audio.stream_paused])


func _initialize() -> void:
	await process_frame
	print("driver=", AudioServer.get_driver_name(), " mix_rate=", AudioServer.get_mix_rate())
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _wait(0.6)
	_row("flying 0.6 s", main)

	# Today's pause path (radio failsafe / focus / crash all call sim.set_paused(true)).
	main.session._failsafe("probe")
	await _wait(0.6)
	_row("failsafe pause +0.6 s (today)", main)
	await _wait(0.6)
	_row("failsafe pause +1.2 s (today)", main)

	# Candidate: stream_paused while the session is paused (main keeps calling update()).
	main._engine_audio.stream_paused = true
	await _wait(0.4)
	_row("stream_paused=true +0.4 s", main)
	# Candidate: resume with a fresh, empty generator queue.
	main._engine_audio.stop()
	main._engine_audio.play()
	_row("stop()+play() (fresh queue)", main)
	main.session.resume()
	await _wait(0.4)
	_row("resumed +0.4 s", main)

	# Master volume and mute (post-fader peak).
	var before := _peak()
	AudioServer.set_bus_volume_linear(0, 0.5)
	await _wait(0.3)
	print("Master linear 0.5: peak %.1f -> %.1f dB" % [before, _peak()])
	AudioServer.set_bus_volume_linear(0, 1.0)
	AudioServer.set_bus_mute(0, true)
	await _wait(0.3)
	_row("Master muted +0.3 s", main)
	AudioServer.set_bus_mute(0, false)

	# Home -> Fly -> Home cycles: free the flight scene and build it again.
	for c in 5:
		main.queue_free()
		await process_frame
		main = load("res://main.tscn").instantiate()
		root.add_child(main)
		await _wait(0.2)
	print("after 5 cycles: AudioStreamPlayer3D in tree=", root.find_children("*", "AudioStreamPlayer3D", true, false).size())
	_row("cycle 5 flying", main)
	quit(0)
