## Whole Simulation.step() cost with the audited P-51 idle ground fixture.
extends "ground_probe.gd"

const BENCH_TICKS := 2400


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	if not _setup_session():
		printerr(setup_error)
		quit(1)
		return
	var fixture := _parked_fixture()
	if not fixture.get("ok", false):
		printerr("ground benchmark fixture failed: ", fixture)
		quit(1)
		return
	var parked: PackedFloat64Array = fixture.state
	var idle: float = Propulsion.steady_rpm(0.0, 0.0, model.propulsion, density)
	var times := PackedFloat64Array()
	for run in 3:
		# Zero-duration case installs the same complete state as the flight probe.
		var installed := _run_case("benchmark_install", parked, idle, true, 0.0,
			func(_t: float, _s: PackedFloat64Array) -> Dictionary:
				return { roll = 0.0, pitch = 1.0, yaw = 0.0, throttle = 0.0 })
		if not installed.complete:
			printerr("ground benchmark installation failed: ", installed)
			quit(1)
			return
		var started := Time.get_ticks_usec()
		for tick in BENCH_TICKS:
			session.sim.step()
		times.append(float(Time.get_ticks_usec() - started) / BENCH_TICKS)
		if not session.sim.fault_reason.is_empty() or not Sim.state_is_valid(session.sim.state) \
				or absf(session.sim.time() - 10.0) > 1e-8 or _contact_count(session.sim.state) != 3:
			printerr("ground benchmark did not complete ten finite seconds on three contacts")
			quit(1)
			return
	print(JSON.stringify({ "aircraft": model.id, "regime": "parked_idle", "hz": 240,
		"ticks_per_trial": BENCH_TICKS, "microseconds_per_tick": times,
		"best_microseconds_per_tick": minf(times[0], minf(times[1], times[2])),
		"scope": "Simulation.step only; fixture setup and metric reduction excluded" }))
	quit(0)
