## Read actual flight/environment integration under the supplied CLI settings.
extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var off: bool = args.has("--soundscape=off")
	var legacy: bool = args.has("--soundscape=legacy")
	var okay: bool = true
	var report: Dictionary = {arguments = args}
	if off:
		okay = scene._soundscape_audio == null and scene._engine_audio == null
	elif legacy:
		okay = scene._soundscape_audio == null and scene._engine_audio != null
	else:
		okay = scene._soundscape_audio != null
		if okay:
			var snapshot: Dictionary = scene._soundscape_audio.snapshot()
			report.sun_elevation = snapshot.sun_elevation
			report.wind_speed = snapshot.wind_speed
			var accepted_wind: PackedFloat64Array = scene.session.wind_at(scene.session.sim.time())
			var expected_speed: float = sqrt(accepted_wind[0] * accepted_wind[0] + accepted_wind[1] * accepted_wind[1] + accepted_wind[2] * accepted_wind[2])
			okay = okay and is_equal_approx(float(snapshot.wind_speed), expected_speed)
			var cues: Array = scene._field_node.get_meta("wind_cues", [])
			report.fabric_sources = 0 if scene._soundscape_audio.soundscape.fabric_audio == null else 1
			if not cues.is_empty():
				var sock: Node3D = cues[0]
				var centres: PackedVector3Array = sock.get_node("Fabric").get_meta("centreline")
				var expected_source: Vector3 = sock.global_transform * centres[8]
				okay = okay and report.fabric_sources == 1 and snapshot.has("fabric_source")
				if snapshot.has("fabric_source"):
					okay = okay and (snapshot.fabric_source as Vector3).is_equal_approx(expected_source)
					okay = okay and is_equal_approx(float(snapshot.windsock_inflation), float(sock.get_meta("windsock_motion").inflation))
				report.fabric_tracks_visual = okay
			if args.has("--time-of-day=23:00"):
				okay = okay and float(snapshot.sun_elevation) < 0.0
			if args.has("--weather=gusty"):
				okay = okay and float(snapshot.wind_speed) > 0.0
	var beds: Array[Node] = scene.find_children("Ambience", "AudioStreamPlayer", true, false)
	report.legacy_bed_count = beds.size()
	if args.has("--scenery=on"):
		okay = okay and not beds.is_empty()
	for bed: AudioStreamPlayer in beds:
		if not legacy:
			okay = okay and not bed.playing and bed.process_mode == Node.PROCESS_MODE_DISABLED
	report.passed = okay
	print(JSON.stringify(report))
	if legacy and scene._engine_audio != null:
		scene.set_process(false)
		scene._engine_audio.stop()
		scene._engine_audio.stream = null
		await create_timer(0.2).timeout
	scene.free()
	await process_frame
	quit(0 if okay else 1)
