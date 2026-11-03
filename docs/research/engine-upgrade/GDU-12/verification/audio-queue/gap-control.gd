extends SceneTree
const Sound := preload("res://render/engine_sound.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var player: AudioStreamPlayer3D = Sound.create(holder)
	Sound.update(player, 0.0, 6000.0, 12000.0)
	var reproduced := false
	for attempt in 8:
		OS.delay_msec(ceili(player._mix_period * 1000.0) + 50)
		Sound.update(player, 0.0, 6000.0, 12000.0)
		var previous_target: int = player.target_frames
		var previous_queue: int = player.queued_frames
		var previous_pushed: int = player.pushed_frames
		var previous_time: int = player._last_refill_usec
		Sound.update(player, 0.0, 6000.0, 12000.0)
		var row := {"engine": Engine.get_version_info().string, "attempt": attempt, "mix_period": player._mix_period,
			"capacity": player.capacity, "previous_target": previous_target, "previous_queue": previous_queue,
			"target": player.target_frames, "queue": player.queued_frames,
			"pushed_delta": player.pushed_frames - previous_pushed,
			"gap_usec": player._last_refill_usec - previous_time}
		print("AUDIO_QUEUE_GAP ", JSON.stringify(row))
		if previous_target > player.target_frames and player.queued_frames > player.target_frames and player.pushed_frames == previous_pushed:
			reproduced = true
			break
	holder.free()
	quit(0 if reproduced else 1)
