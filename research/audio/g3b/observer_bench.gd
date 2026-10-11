# G3b: paired evolving flight ticks with/without the accepted-state audio observer.
# No audio refill in timed loops. The observer's work remains in the physics signal path.
extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const Sound := preload("res://render/engine_sound.gd")
const MODELS := ["res://data/aircraft/jensen_ugly_stik_60.json", "res://data/aircraft/gp_extra_300s_60.json",
	"res://data/aircraft/p51d_mustang_120.json", "res://data/aircraft/sebart_avanti_s_a200.json"]
const TICKS := 960
var rows: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _measure(path: String, observed: bool) -> Dictionary:
	var session := Flight.new()
	session.setup(path)
	root.add_child(session)
	session.input_enabled = false
	session.set_physics_process(false)
	session.sim.set_physics_process(false)
	var parent := Node3D.new()
	root.add_child(parent)
	if observed:
		Sound.create(parent, session.sim, session.aircraft.model.propulsion.max_rpm)
	session.reset()
	for i in 240:
		session.sim.step()
	var before := Time.get_ticks_usec()
	for i in TICKS:
		session.sim.step()
	var elapsed := Time.get_ticks_usec() - before
	var endpoint := var_to_bytes(session.sim.checkpoint()).hex_encode().sha256_text()
	var valid: bool = session.sim.tick == 240 + TICKS and session.sim.fault_reason.is_empty()
	parent.free()
	session.free()
	return {"elapsed_usec_per_tick": float(elapsed) / TICKS, "endpoint_sha256": endpoint, "valid": valid}

func _run() -> void:
	for path in MODELS:
		for pair in 5:
			var quiet: Dictionary
			var observed: Dictionary
			if pair % 2 == 0:
				quiet = _measure(path, false)
				observed = _measure(path, true)
			else:
				observed = _measure(path, true)
				quiet = _measure(path, false)
			if not quiet.valid or not observed.valid or quiet.endpoint_sha256 != observed.endpoint_sha256:
				printerr("FAIL observer benchmark state preservation")
				quit(1)
				return
			rows.append({"aircraft": path.get_file(), "pair": pair, "quiet": quiet, "observed": observed})
	var report := {"godot": Engine.get_version_info().string, "timed_ticks": TICKS,
		"measurement": "Elapsed wall time; five alternating pairs, no refill, same-build complete checkpoint identity.", "rows": rows}
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	if out.is_empty():
		print(JSON.stringify(report, "\t"))
	else:
		var file := FileAccess.open(out, FileAccess.WRITE)
		if file == null:
			quit(1)
			return
		file.store_string(JSON.stringify(report, "\t") + "\n")
	quit(0)
