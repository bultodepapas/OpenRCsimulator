## Presentation-only camera and compact event evidence for the storm insert.
## It positions the native pilot camera; it never writes simulation state or weather events.
extends Node

const CAMERA_FOV_DEG := 43.0

var main: Node
var camera_position := Vector3.ZERO
var look_target := Vector3.ZERO
var first_tick := -1
var first_time_s := 0.0
var capture_focus_resumes := 0
var frame_records: Array[Dictionary] = []


func configure(flight_main: Node, event: Dictionary, _duration_s: float, _fps: int, options: Dictionary = {}) -> void:
	main = flight_main
	process_priority = 20
	var channel := _vector3(event.get("channel_world", PackedFloat64Array()))
	var source := _vector3(event.get("source_world", PackedFloat64Array()))
	if str(options.get("camera", "near-channel")) == "distant-tower":
		# Keep the real pilot station and frame the full native storm bank from the field.
		camera_position = main._camera.global_position
		look_target = source
	else:
		# Stand just off the native channel, inside the storm formation. This keeps the actual delayed
		# thunder close enough to arrive in the source handle while the cloud tower remains in view.
		camera_position = channel + Vector3(360.0, 110.0, 0.0)
		look_target = source + Vector3.DOWN * 780.0
	var station: Array[float] = [-camera_position.z, camera_position.x, -camera_position.y]
	main._camera.set_meta("pilot_station", station)
	main._rig.set_view("pilot")
	main._rig.auto_zoom = false
	main._rig.look_height = 0.0
	var direction := (look_target - camera_position).normalized()
	var azimuth := rad_to_deg(atan2(direction.x, -direction.z))
	var elevation := rad_to_deg(asin(clampf(direction.y, -1.0, 1.0)))
	main._rig.look = Vector2(azimuth, elevation)
	main._airplane.root.visible = false
	if main._shadow != null:
		main._shadow.visible = false
	first_tick = int(main.session.sim.tick)
	first_time_s = float(main.session.sim.time())


func _process(_delta: float) -> void:
	if main == null or main._camera == null:
		return
	# This SceneTree driver is an isolated deterministic capture, not an interactive flight. Godot
	# propagates application-focus-out to Simulation and pauses it; resume only that non-fault,
	# non-crashed session here so another capture window cannot freeze the storm timeline.
	if main.session != null and main.session.sim.paused \
			and main.session.sim.fault_reason.is_empty() and main.session.crash.is_empty():
		main.session.sim.set_paused(false)
		capture_focus_resumes += 1
	# PilotCamera.look uses the current weather camera station and direction; restore a narrower lens
	# after the production rig assigns its default each frame.
	main._camera.fov = CAMERA_FOV_DEG
	main._airplane.root.visible = false
	if main._panel != null:
		main._panel.visible = false
	if main._hud != null:
		main._hud.visible = false


func record_presented_frame(frame_index: int) -> void:
	if main == null or frame_index % 5 != 0:
		return
	var storm: Dictionary = main._storm_fx.snapshot() if main._storm_fx != null else {}
	var bank: Dictionary = main.capture_evidence().get("storm_bank", {})
	var audio: Node = main._storm_fx.get("_audio") if main._storm_fx != null else null
	var pending: Array = audio._pending.duplicate(true) if audio != null else []
	var playing := false
	var voices: Array = []
	if audio != null:
		for index: int in audio._players.size():
			var player: AudioStreamPlayer3D = audio._players[index]
			playing = playing or player.playing
			voices.append({playing = player.playing, started_at_s = float(audio._player_started_at[index]), volume_db = float(player.volume_db)})
	frame_records.append({
		frame = frame_index,
		movie_writer_frame_estimate = frame_index + 3,
		sim_tick = int(main.session.sim.tick),
		sim_time_s = float(main.session.sim.time()),
		sim_paused = bool(main.session.sim.paused),
		camera_world_m = _vector_array(main._camera.global_position),
		camera_look_target_m = _vector_array(look_target),
		lightning_event_id = str(storm.get("event_id", "")),
		lightning_level = float(storm.get("level", 0.0)),
		lightning_pending_thunder = int(storm.get("pending_thunder", 0)),
		storm_bank_visible = bool(bank.get("enabled", false)),
		storm_bank_center_m = bank.get("center", []),
		storm_bank_flash = bank.get("flash", {}),
		thunder_pending = pending,
		thunder_voice_playing = playing,
		thunder_voices = voices,
	})


func _vector3(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is PackedFloat64Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


func _vector_array(value: Vector3) -> Array[float]:
	return [float(value.x), float(value.y), float(value.z)]
