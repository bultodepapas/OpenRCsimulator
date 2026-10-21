extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var app = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray(["--quick-flight", "--start=airborne", "--battery=ideal"])
	root.add_child(app)
	await create_timer(1.0).timeout
	var player = app.flight._soundscape_audio.soundscape.glow_player
	var source_ref = weakref(player.stream)
	var playback_ref = weakref(player.get_stream_playback())
	app.free()
	print("audio immediately after owner free: source=", source_ref.get_ref() != null, " playback=", playback_ref.get_ref() != null)
	await create_timer(0.2).timeout
	print("audio after mixer retirement: source=", source_ref.get_ref() != null, " playback=", playback_ref.get_ref() != null)
	quit()
