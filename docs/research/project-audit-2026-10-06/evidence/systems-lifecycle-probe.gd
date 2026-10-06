extends SceneTree

const UiDriver := preload("res://tests/ui_driver.gd")
const PREFS := "user://audit_lifecycle_probe.cfg"
var app: Node
var ui: RefCounted
var playback_ids: Array[int] = []

func _alive_count() -> int:
	var alive := 0
	for playback_id in playback_ids:
		if is_instance_valid(instance_from_id(playback_id)):
			alive += 1
	return alive

func _initialize() -> void:
	ui = UiDriver.new(self)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	app = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	for i in 5:
		app.start_flight()
		await ui.settle()
		var player: AudioStreamPlayer3D = app.flight.get("_engine_audio")
		var playback: AudioStreamGeneratorPlayback = player.get_stream_playback()
		playback_ids.append(playback.get_instance_id())
		app.open_pause()
		await ui.settle()
		app.end_flight()
		await ui.settle()
		print("cycle=%d node_count=%d playback_instances_alive=%d/%d" % [i + 1,
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT), _alive_count(), playback_ids.size()])
	await create_timer(1.0).timeout
	print("one_second_idle playback_instances_alive=%d/%d node_count=%d" % [_alive_count(), playback_ids.size(),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	app.queue_free()
	await ui.settle()
	print("after_app_cleanup node_count=%d playback_instances_alive=%d/%d" % [Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		_alive_count(), playback_ids.size()])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	quit()
