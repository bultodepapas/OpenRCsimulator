# RCV-04b: small-angle four-corner rig. Research CLI, not a playable vehicle.
extends SceneTree
const Rig := preload("res://physics/ground_vehicle/four_corner.gd")
const Data := preload("res://physics/ground_vehicle/support_bench_data.gd")
const M := preload("res://physics/math3d.gd")
const CORNERS := ["fl", "fr", "rl", "rr"]
const STATES := ["z_m", "roll_rad", "pitch_rad", "zu_fl_m", "zu_fr_m", "zu_rl_m", "zu_rr_m", "vz_m_per_s", "roll_rate_rad_per_s", "pitch_rate_rad_per_s", "vu_fl_m_per_s", "vu_fr_m_per_s", "vu_rl_m_per_s", "vu_rr_m_per_s"]
const SCENARIOS := ["heave", "roll", "pitch", "front_left_bump", "drop"]
const MAX_ANGLE := 0.1


func _fail(message: String) -> void:
	printerr("RCV support refused: " + message)
	quit(1)


func _path(path: String) -> String:
	path = path.replace("\\", "/")
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path).simplify_path()
	if path.begins_with("/") or (path.length() > 2 and path.substr(1, 1) == ":"):
		return path.simplify_path()
	return ProjectSettings.globalize_path("res://").path_join(path).simplify_path()


func _options() -> Dictionary:
	var options := {"scenario": "heave", "hz": "240", "duration": "2", "out": "", "profile": "../research/rc-monster-truck/support_bench.json", "timing": "false"}
	var seen := {}
	for arg in OS.get_cmdline_user_args():
		var equals := arg.find("=")
		if not arg.begins_with("--") or equals < 3:
			return {"error": "use --name=value options"}
		var key := arg.substr(2, equals - 2)
		var value := arg.substr(equals + 1)
		if not options.has(key) or seen.has(key) or value.strip_edges().is_empty():
			return {"error": "unknown, repeated or empty option: " + key}
		seen[key] = true
		options[key] = value
	if not options.scenario in SCENARIOS:
		return {"error": "unsupported scenario"}
	if not options.hz.is_valid_int() or not int(options.hz) in [240, 480, 960, 1920]:
		return {"error": "hz must be 240, 480, 960 or 1920"}
	if not options.duration.is_valid_float():
		return {"error": "duration must be finite"}
	var duration := float(options.duration)
	var hz := int(options.hz)
	var ticks := duration * hz
	if not is_finite(duration) or duration <= 0 or duration > 30 or ticks < 1.0 - 1e-9 or absf(ticks - roundf(ticks)) > 1e-9:
		return {"error": "duration must be <=30 s and a positive integer number of ticks"}
	if options.out.is_empty() or options.out.get_extension().to_lower() != "csv":
		return {"error": "out must name a CSV file"}
	if not options.timing in ["true", "false"]:
		return {"error": "timing must be true or false"}
	options.hz = hz
	options.duration = duration
	options.ticks = roundi(ticks)
	options.timing = options.timing == "true"
	return options


func _road(t: float, scenario: String) -> PackedFloat64Array:
	var road := PackedFloat64Array([0, 0, 0, 0])
	if scenario == "front_left_bump" and t >= 0.25 and t <= 0.45:
		var wave := M.sin_(PI * (t - 0.25) / 0.2)
		road[0] = 0.005 * wave * wave
	return road


func _finite(values: PackedFloat64Array) -> bool:
	for value in values:
		if not is_finite(value):
			return false
	return true


func _initialize() -> void:
	var options := _options()
	if options.has("error"):
		_fail(options.error)
		return
	var profile := _path(options.profile)
	var input := FileAccess.open(profile, FileAccess.READ)
	if input == null:
		_fail("cannot read profile")
		return
	var bytes := input.get_buffer(input.get_length())
	var read_error := input.get_error()
	input.close()
	if read_error != OK and read_error != ERR_FILE_EOF:
		_fail("profile read error")
		return
	var loaded := Data.parse_text(bytes.get_string_from_utf8())
	if not loaded.ok:
		_fail(str(loaded.errors))
		return
	var out := _path(options.out)
	var sidecar := out.get_basename() + ".json"
	if out.to_lower() == profile.to_lower() or sidecar.to_lower() == profile.to_lower():
		_fail("output cannot replace the input profile")
		return
	# Fresh paths keep an earlier success summary from accompanying a failed run.
	if FileAccess.file_exists(out) or FileAccess.file_exists(sidecar):
		_fail("output already exists; choose a new output basename")
		return
	var p: Dictionary = loaded.parameters
	var equilibrium := Rig.equilibrium(p)
	if not equilibrium.ok:
		_fail(str(equilibrium.errors))
		return
	var start: PackedFloat64Array = equilibrium.state
	match options.scenario:
		"heave": start[0] += 0.005
		"roll": start[1] += 0.01
		"pitch": start[2] += 0.01
		"drop":
			start[0] += 0.03
			for i in 4:
				start[3 + i] += 0.03
	var road := Callable(self, "_road").bind(options.scenario)
	var dt: float = 1.0 / options.hz
	# Warmup is separate state and sim time; measurement always restarts from start.
	if options.timing:
		var warm := start.duplicate()
		for tick in 240:
			warm = Rig.step(warm, p, float(tick) * dt, dt, road)
	var output := FileAccess.open(out, FileAccess.WRITE)
	if output == null:
		_fail("cannot open CSV output")
		return
	var header := PackedStringArray(["time_s"])
	header.append_array(PackedStringArray(STATES))
	for corner in CORNERS:
		for quantity in ["road_m", "tire_n", "spring_n", "spring_compression_m", "tire_compression_m", "contact"]:
			header.append(corner + "_" + quantity)
	header.append_array(PackedStringArray(["energy_j", "damper_loss_w"]))
	output.store_line(",".join(header))
	var s := start.duplicate()
	var costs := PackedFloat64Array()
	var contact_event_costs := PackedFloat64Array()
	var previous_contact := PackedByteArray([0, 0, 0, 0])
	var pending_cost := 0.0
	var max_roll := 0.0
	var max_pitch := 0.0
	var peaks := PackedFloat64Array([0, 0, 0, 0])
	var contact_counts := PackedInt64Array([0, 0, 0, 0])
	for tick in options.ticks + 1:
		var t := float(tick) * dt
		if not _finite(s) or absf(s[1]) > MAX_ANGLE or absf(s[2]) > MAX_ANGLE:
			output.close()
			_fail("nonfinite state or small-angle envelope exceeded at tick %d" % tick)
			return
		var h := _road(t, options.scenario)
		var f := Rig.loads(s, p, h)
		var energy := Rig.energy(s, p, h)
		if not _finite(f.tire_force_n) or not _finite(f.suspension_force_n) or not _finite(f.damper_loss_w) or not is_finite(energy):
			output.close()
			_fail("nonfinite loads or energy at tick %d" % tick)
			return
		if options.timing and tick > 0 and f.in_contact != previous_contact:
			contact_event_costs.append(pending_cost)
		previous_contact = f.in_contact.duplicate()
		var row := PackedStringArray([String.num(t, 17)])
		for value in s:
			row.append(String.num(value, 17))
		var loss := 0.0
		for i in 4:
			for value in [h[i], f.tire_force_n[i], f.suspension_force_n[i], f.suspension_compression_m[i], f.tire_compression_m[i], f.in_contact[i]]:
				row.append(String.num(float(value), 17))
			loss += f.damper_loss_w[i]
			peaks[i] = maxf(peaks[i], f.tire_force_n[i])
			contact_counts[i] += f.in_contact[i]
		row.append_array(PackedStringArray([String.num(energy, 17), String.num(loss, 17)]))
		output.store_line(",".join(row))
		if output.get_error() != OK:
			output.close()
			_fail("CSV write error")
			return
		max_roll = maxf(max_roll, absf(s[1]))
		max_pitch = maxf(max_pitch, absf(s[2]))
		if tick < options.ticks:
			var begin := Time.get_ticks_usec() if options.timing else 0
			s = Rig.step(s, p, t, dt, road)
			if options.timing:
				pending_cost = float(Time.get_ticks_usec() - begin)
				costs.append(pending_cost)
	output.flush()
	var write_error := output.get_error()
	output.close()
	if write_error != OK:
		_fail("CSV flush error")
		return
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(bytes)
	var summary := {
		"format": "openrc-support-bench-run", "version": 1, "complete": true,
		"model": "linear-seven-dof-unilateral-tires-v1", "state_order": STATES,
		"scope": "Synthetic small-angle vertical rig, not full-vehicle/rollover validation. Peaks are public-tick samples.",
		"scenario": options.scenario, "hz": options.hz, "substeps_per_tick": Rig.SUBSTEPS_PER_TICK,
		"duration_s": options.duration, "sample_count": options.ticks + 1,
		"profile_id": loaded.id, "profile_sha256": hasher.finish().hex_encode(),
		"csv_sha256": FileAccess.get_sha256(out), "max_abs_roll_rad": max_roll, "max_abs_pitch_rad": max_pitch,
		"peak_sampled_tire_load_n": Array(peaks), "contact_sample_counts": Array(contact_counts),
		"timing": _timing(costs, contact_event_costs),
	}
	var meta := FileAccess.open(sidecar, FileAccess.WRITE)
	if meta == null:
		_fail("cannot open JSON summary")
		return
	meta.store_string(JSON.stringify(summary, "  ") + "\n")
	meta.flush()
	write_error = meta.get_error()
	meta.close()
	if write_error != OK:
		_fail("JSON summary write error")
		return
	print("support bench complete: %d samples, %s" % [options.ticks + 1, out])
	quit(0)


func _timing(costs: PackedFloat64Array, events: PackedFloat64Array) -> Dictionary:
	if costs.is_empty():
		return {"enabled": false}
	var ordered := costs.duplicate()
	ordered.sort()
	events.sort()
	return {
		"enabled": true, "unit": "microseconds", "warmup_ticks": 240, "measured_ticks": costs.size(),
		"median": ordered[ceili(0.5 * ordered.size()) - 1], "p95": ordered[ceili(0.95 * ordered.size()) - 1],
		"p99": ordered[ceili(0.99 * ordered.size()) - 1], "max": ordered[-1],
		"public_contact_change_ticks": events.size(), "max_public_contact_change_tick": events[-1] if not events.is_empty() else null,
		"scope": "Rig.step only, both substeps and stage road callbacks; excludes telemetry, CSV, rendering, session, drivetrain and obstacle broadphase. Not full truck performance.",
	}
