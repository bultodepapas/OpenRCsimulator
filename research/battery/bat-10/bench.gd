# BAT-10 paired per-tick cost: EL2a synthetic OCV/resistance pack, Timber ideal (fixed bus) and Timber pack_ecm.
# Software cost only. Batches are interleaved (A, B, C, A, B, C…) from each case's own warm checkpoint so host
# drift affects every case alike. Run from the repository root:
#   "$(app/get-godot.sh)" --headless --path app --script "$PWD/research/battery/bat-10/bench.gd" -- --out=/tmp/bat10.json
extends SceneTree

const FlightSession: Script = preload("res://sim/flight_session.gd")
const Catalog: Script = preload("res://app_state/aircraft_catalog.gd")

const WARMUP_TICKS: int = 240
const TICKS_PER_BATCH: int = 120
const BATCHES: int = 15
const THROTTLE: float = 0.8

var _out: String = ""


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	var cases: Array[Dictionary] = [
		{"id": "el2a_synthetic_4s_battery", "path": "res://data/aircraft/synthetic_stik_electric_4s_battery.json", "expected": ""},
		{"id": "timber_ideal_fixed_bus", "path": Catalog.data_for("turbo-lumber-evolution", "ideal"), "expected": "turbo-lumber-evolution"},
		{"id": "timber_pack_ecm", "path": Catalog.data_for("turbo-lumber-evolution", "pack"), "expected": "turbo-lumber-evolution"},
	]
	var sessions: Array[Node] = []
	var warm: Array[Dictionary] = []
	for case: Dictionary in cases:
		var session: Node = FlightSession.new()
		session.setup(case.path, case.expected)
		session.input_enabled = false
		session.engine_running = true
		session.sim.inputs[3] = THROTTLE
		for _i: int in WARMUP_TICKS:
			session.sim.step()
		if not session.sim.fault_reason.is_empty() or not session.is_flyable():
			push_error("case %s cannot run: %s" % [case.id, session.sim.fault_reason])
			quit(1)
			return
		sessions.append(session)
		warm.append(session.checkpoint())
	var samples: Array = [[], [], []]
	for _batch: int in BATCHES:
		for index: int in cases.size():
			var session: Node = sessions[index]
			if not session.restore_checkpoint(bytes_to_var(var_to_bytes(warm[index]))):
				push_error("restore failed for " + str(cases[index].id))
				quit(1)
				return
			session.sim.inputs[3] = THROTTLE
			var started: int = Time.get_ticks_usec()
			for _tick: int in TICKS_PER_BATCH:
				session.sim.step()
			samples[index].append(float(Time.get_ticks_usec() - started) / TICKS_PER_BATCH)
	var report: Dictionary = {"format": "openrc-bat10-pack-cost-v1", "throttle": THROTTLE, "ticks_per_batch": TICKS_PER_BATCH,
		"batches": BATCHES, "processor": OS.get_processor_name(), "logical_cpus": OS.get_processor_count(),
		"godot": Engine.get_version_info().string, "cases": []}
	for index: int in cases.size():
		var values: Array = samples[index]
		values.sort()
		var median: float = values[values.size() / 2]
		var p95: float = values[int(ceil(0.95 * values.size())) - 1]
		report.cases.append({"id": cases[index].id, "median_us_per_tick": median, "p95_us_per_tick": p95, "batches_us": values})
		print("%s: median %.1f µs/tick, p95 %.1f" % [cases[index].id, median, p95])
	for session: Node in sessions:
		session.free()
	if not _out.is_empty():
		var file := FileAccess.open(_out, FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "  ") + "\n")
	quit(0)
