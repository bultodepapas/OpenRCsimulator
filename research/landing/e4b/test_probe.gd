# E4b comparator negative controls, executed only in a disposable instrumented app.
extends "probe.gd"
var failures: int = 0
var checks: int = 0


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", label)


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	var session: Node = Session.new()
	session.setup()
	root.add_child(session)
	var expected: Dictionary = sample(session)
	check(measure(session, expected), "finite baseline accepted")
	check(exact_samples == 1, "exact sample counted")
	# A known 1 m position error must consume exactly 1e6 of the 1e-6 m H9 budget.
	session.sim.state[0] = expected.state[0] + 1.0
	check(measure(session, expected), "finite error measured without aborting")
	check(metrics.position.max_absolute == 1.0 and metrics.position.max_ratio == 1e6, "known error magnitude")
	check(metrics.position.first_exceed_tick == session.sim.tick, "first exceed tick recorded")
	check(exact_samples == 1, "different sample not counted exact")
	session.sim.state = expected.state.duplicate()
	# Flags are checked separately; fractional values must not become an anchor-distance error.
	session.sim.aux[Session.AUX_ANCHORS + 2] = 0.5
	check(measure(session, expected), "mode mismatch measured")
	check(discrete_mismatches.size() == 1 and discrete_mismatches[0].block == "anchor_mode", "anchor flag exact")
	check(metrics.anchor.max_absolute == 0.0, "flag excluded from metric distance")
	session.sim.aux = expected.aux.duplicate()
	session.sim.previous[0] = NAN
	check(not measure(session, expected), "nonfinite previous state refused")
	session.sim.previous = expected.previous.duplicate()
	session.sim.last_loads[0] = INF
	check(not measure(session, expected), "nonfinite loads refused")
	session.free()
	print("E4b comparator: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
