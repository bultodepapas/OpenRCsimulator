extends SceneTree

func _initialize() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 22050.0
	generator.buffer_length = 0.15
	var player := AudioStreamPlayer.new()
	player.stream = generator
	root.add_child(player)
	await process_frame
	player.play()
	await process_frame
	var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
	var writable_empty := playback.get_frames_available()
	var requested_frames := generator.mix_rate * generator.buffer_length
	var capacity := 1
	while capacity < requested_frames:
		capacity *= 2
	var block := PackedVector2Array()
	block.resize(writable_empty)
	block.fill(Vector2.ZERO)
	var pushed := playback.push_buffer(block)
	var writable_full := playback.get_frames_available()
	var effective_capacity := capacity - 1
	print("mix_rate=%.0f buffer_length=%.3f requested_frames=%.1f capacity=%d empty_writable=%d push_ok=%s full_writable=%d queued_frames=%d queued_seconds=%.6f" % [
		generator.mix_rate, generator.buffer_length, requested_frames, capacity, writable_empty, str(pushed), writable_full,
		effective_capacity - writable_full, float(effective_capacity - writable_full) / generator.mix_rate])
	player.stop()
	player.queue_free()
	await create_timer(1.0).timeout
	quit()
