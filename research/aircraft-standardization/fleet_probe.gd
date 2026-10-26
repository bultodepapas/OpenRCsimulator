extends SceneTree
## AS-06: exact same-platform flight fingerprints. Does not update golden flights.
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Flight := preload("res://sim/flight_session.gd")
const TICKS := 240
const REPLAY_START := 120

func digest(value: Variant) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(value))
	return hash.finish().hex_encode()

func snapshot(f: Node) -> Array:
	return [f.sim.state, f.sim.previous, f.sim.continuous, f.sim.aux, f.sim.modes,
		f.sim.inputs, f.sim.last_loads, f.sim.mass, f.sim.inertia, f.sim.tick]

func exercise(entry: Dictionary, battery_mode: String, soft: bool) -> Dictionary:
	var data_path := Catalog.data_for(entry.id, battery_mode)
	var report := {"ok": false, "complete": false, "id": entry.id,
		"battery_mode": battery_mode, "data_path": data_path, "soft_hull": soft,
		"completed_ticks": 0, "replay_ticks": 0, "replay_exact": false}
	var f := Flight.new()
	f.soft_hull_contacts = soft
	f.setup(data_path, entry.id)
	f.input_enabled = false
	if not f.is_flyable() or f.sim.tick != 0:
		report.error = f.pause_reason if not f.is_flyable() else "Initial tick is not zero."
		f.free()
		return report
	report.merge({"model_sha256": digest(f.aircraft.model), "initial_sha256": digest(snapshot(f)),
		"checkpoint_format": f.checkpoint().get("format", ""), "samples": []})
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	var checkpoint: Dictionary = {}
	var replay_expected: Array[String] = []
	for tick in TICKS:
		f.sim.inputs[0] = 0.08 if tick >= 60 and tick < 180 else 0.0
		f.sim.inputs[1] = -0.04 if tick >= 120 else 0.0
		f.sim.inputs[2] = 0.03 if tick >= 180 else 0.0
		f.sim.step()
		if not f.sim.fault_reason.is_empty() or f.sim.tick != tick + 1:
			report.error = f.sim.fault_reason if not f.sim.fault_reason.is_empty() else "Incomplete forward tick."
			break
		report.completed_ticks = tick + 1
		hash.update(var_to_bytes(snapshot(f)))
		if tick >= REPLAY_START:
			replay_expected.append(digest(snapshot(f)))
		if (tick + 1) % 60 == 0:
			report.samples.append({"tick": tick + 1, "sha256": digest(snapshot(f))})
		if tick == REPLAY_START - 1:
			checkpoint = f.checkpoint()
	report.trajectory_sha256 = hash.finish().hex_encode()
	if report.completed_ticks == TICKS and not checkpoint.is_empty():
		report.replay_exact = f.restore_checkpoint(checkpoint)
		if report.replay_exact and f.sim.tick != REPLAY_START:
			report.replay_exact = false
		for tick in range(REPLAY_START, TICKS):
			if not report.replay_exact:
				break
			f.sim.inputs[0] = 0.08 if tick < 180 else 0.0
			f.sim.inputs[1] = -0.04
			f.sim.inputs[2] = 0.03 if tick >= 180 else 0.0
			f.sim.step()
			report.replay_exact = f.sim.fault_reason.is_empty() and f.sim.tick == tick + 1 \
				and digest(snapshot(f)) == replay_expected[tick - REPLAY_START]
			if report.replay_exact:
				report.replay_ticks += 1
	report.complete = report.completed_ticks == TICKS and report.replay_ticks == TICKS - REPLAY_START
	report.ok = report.complete and report.replay_exact
	f.free()
	return report

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		printerr("usage: fleet_probe.gd -- <output.json>")
		quit(2)
		return
	var rows: Array = []
	var ok := true
	var expected_cases := 0
	for entry: Dictionary in Catalog.airplane_flyable_entries():
		for battery_mode: String in Catalog.BATTERY_MODES:
			if not Catalog.has_battery_mode(entry.id, battery_mode):
				continue
			for soft in [false, true]:
				expected_cases += 1
				var result := exercise(entry, battery_mode, soft)
				rows.append(result)
				ok = ok and result.ok
				print("AS fleet ", entry.id, " battery=", battery_mode, " soft=", soft, " ", "PASS" if result.ok else "FAIL")
	ok = ok and expected_cases > 0 and rows.size() == expected_cases
	var file := FileAccess.open(args[0], FileAccess.WRITE)
	if file == null:
		printerr("Cannot write fleet report: ", FileAccess.get_open_error())
		quit(2)
		return
	file.store_string(JSON.stringify({"format": "openrc-as-fleet-probe v2", "ok": ok, "complete": ok,
		"godot": Engine.get_version_info().string, "hz": Engine.physics_ticks_per_second,
		"ticks_per_case": TICKS, "replay_start_tick": REPLAY_START,
		"expected_cases": expected_cases, "cases": rows}, "\t") + "\n")
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		printerr("Cannot flush fleet report: ", write_error)
		quit(2)
		return
	quit(0 if ok else 1)
