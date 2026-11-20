extends SceneTree

const Session := preload("res://sim/airship/session.gd")
const AirshipLog := preload("res://sim/airship/flight_log.gd")
const Orfl := preload("res://sim/flight_log.gd")
const LOG_PATH := "user://round2-valid-airship.orfl"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var changed := OS.get_cmdline_user_args().has("--verify-changed-source")
	if not changed:
		var session := Session.new()
		root.add_child(session)
		assert(session.prepare({}, {altitude_m = 20.0, wind_speed_mps = 1.5}))
		assert(session.resume(PackedFloat64Array([0, 0, 0, 0])))
		for i in 12:
			assert(session.tick_once(PackedFloat64Array([0, 0, 0, 0.2])))
		var recorder := AirshipLog.new(session)
		assert(recorder.start({}, LOG_PATH) == OK)
		for i in 24:
			assert(session.tick_once(PackedFloat64Array([0.1, 0.2, 0.0, 0.3])))
		assert(recorder.stop("bounded audit sample") == OK)
		session.free()
	var report := AirshipLog.verify(LOG_PATH)
	var read := AirshipLog.inspect(LOG_PATH)
	var metadata_cases: Array[Dictionary] = []
	if not changed:
		for kind in ["duplicate_tick", "gap_tick", "reordered_ticks", "footer_bounds"]:
			# Exercise the parsed-record seam without modifying any .orfl bytes.
			# Public inspector behavior is traced separately in the report.
			var candidate: Dictionary = read.duplicate(true)
			match kind:
				"duplicate_tick": candidate.ticks[1] = candidate.ticks[0]
				"gap_tick": candidate.ticks[1] += 100
				"reordered_ticks":
					var first: int = candidate.ticks[0]
					candidate.ticks[0] = candidate.ticks[1]
					candidate.ticks[1] = first
				"footer_bounds":
					candidate.footer.first_tick = -10
					candidate.footer.final_tick = -20
			var session := Session.new()
			var verdict := AirshipLog._replay(session, {}, candidate.header, candidate,
				{ok = false, exact = false, identity_match = false, solver_changed = false, first_mismatch_tick = -1, error = ""})
			session.free()
			metadata_cases.append({case = kind, first_ticks = Array(candidate.ticks.slice(0, 4)),
				footer_first = candidate.footer.first_tick, footer_final = candidate.footer.final_tick, report = verdict})
	var result := {
		mode = "new-process-comment-only-source-change" if changed else "same-source-control",
		report = report, checkpoint_tick = read.header.checkpoint.tick,
		first_recorded_tick = read.ticks[0], final_recorded_tick = read.ticks[-1],
		recorded_solver = read.header.solver_sha256,
		current_solver = Orfl.replay_identity().sha256,
		original_recording_sha256 = FileAccess.get_sha256(LOG_PATH),
		physics_hz = Engine.physics_ticks_per_second,
		parsed_record_metadata_cases = metadata_cases,
	}
	var reproduced: bool = report.ok and report.exact and report.rows == 24 and bool(report.solver_changed) == changed \
		and metadata_cases.all(func(row: Dictionary) -> bool: return row.report.ok and row.report.exact)
	print("REPLAY_JSON ", JSON.stringify(result))
	print("REPLAY_PROBE_COMPLETE expected_observation=", reproduced)
	quit(0 if reproduced else 1)
