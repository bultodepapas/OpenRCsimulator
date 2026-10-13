extends SceneTree
## AS-06: exact same-platform flight fingerprints. Does not update golden flights.
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Flight := preload("res://sim/flight_session.gd")

func digest(value: Variant) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(value))
	return hash.finish().hex_encode()

func snapshot(f: Node) -> Array:
	return [f.sim.state, f.sim.previous, f.sim.continuous, f.sim.aux, f.sim.modes,
		f.sim.inputs, f.sim.last_loads, f.sim.mass, f.sim.inertia, f.sim.tick]

func exercise(entry: Dictionary, soft: bool) -> Dictionary:
	var f := Flight.new()
	f.soft_hull_contacts = soft
	f.setup(entry.data, entry.id)
	f.input_enabled = false
	if not f.is_flyable():
		var failed := {"ok": false, "id": entry.id, "soft_hull": soft, "error": f.pause_reason}
		f.free()
		return failed
	var report := {"ok": true, "id": entry.id, "soft_hull": soft,
		"model_sha256": digest(f.aircraft.model), "initial_sha256": digest(snapshot(f)),
		"checkpoint_format": f.checkpoint().get("format", ""), "samples": []}
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	var checkpoint: Dictionary = {}
	for tick in 240:
		f.sim.inputs[0] = 0.08 if tick >= 60 and tick < 180 else 0.0
		f.sim.inputs[1] = -0.04 if tick >= 120 else 0.0
		f.sim.inputs[2] = 0.03 if tick >= 180 else 0.0
		f.sim.step()
		if not f.sim.fault_reason.is_empty() or f.sim.tick != tick + 1:
			report.ok = false
			report.error = f.sim.fault_reason
			break
		hash.update(var_to_bytes(snapshot(f)))
		if (tick + 1) % 60 == 0:
			report.samples.append({"tick": tick + 1, "sha256": digest(snapshot(f))})
		if tick == 119:
			checkpoint = f.checkpoint()
	report.trajectory_sha256 = hash.finish().hex_encode()
	var final_digest := digest(snapshot(f))
	if not checkpoint.is_empty():
		report.replay_exact = f.restore_checkpoint(checkpoint)
		for tick in range(120, 240):
			f.sim.inputs[0] = 0.08 if tick < 180 else 0.0
			f.sim.inputs[1] = -0.04
			f.sim.inputs[2] = 0.03 if tick >= 180 else 0.0
			f.sim.step()
		report.replay_exact = report.replay_exact and digest(snapshot(f)) == final_digest
		report.ok = report.ok and report.replay_exact
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
	for entry: Dictionary in Catalog.flyable_entries():
		for soft in [false, true]:
			var result := exercise(entry, soft)
			rows.append(result)
			ok = ok and result.ok
			print("AS fleet ", entry.id, " soft=", soft, " ", "PASS" if result.ok else "FAIL")
	var file := FileAccess.open(args[0], FileAccess.WRITE)
	if file == null:
		printerr("Cannot write fleet report: ", FileAccess.get_open_error())
		quit(2)
		return
	file.store_string(JSON.stringify({"format": "openrc-as-fleet-probe v1", "ok": ok,
		"godot": Engine.get_version_info().string, "hz": Engine.physics_ticks_per_second,
		"ticks_per_case": 240, "cases": rows}, "\t") + "\n")
	file.close()
	quit(0 if ok else 1)
