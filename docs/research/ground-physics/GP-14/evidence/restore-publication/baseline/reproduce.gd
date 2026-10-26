## Reproduce remaining restore publication/owner-guard failures on current source.
extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const Log := preload("res://sim/flight_log.gd")
const Reader := preload("res://tools/flight_log_cli.gd")
var checks := 0
var failed := 0
var output := ""
var observations := []

func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed: failed += 1; printerr("FAIL ", label)

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	Engine.physics_ticks_per_second = 240
	output = ProjectSettings.globalize_path("res://../tmp/gp-restore-transaction/artifacts-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(output)
	for kind: String in ["listener-mutation", "validator-hold", "normal-control"]:
		var f := Flight.new()
		f.input_enabled = false
		f.crash_auto_restart = false
		f.setup()
		if kind == "validator-hold":
			f.sim.model.aux_size = f.sim.aux.size()
			f.sim.model.continuous_size = f.sim.continuous.size()
			f.sim.model.modes_size = f.sim.modes.size()
			f.sim.model.state_layout_identity = "restore-audit-fixture-v1"
			check("endpoint fixture", f.sim.reset(f.sim.state.duplicate()))
		var target: Dictionary = f.checkpoint()
		for i: int in 3: f.sim.step()
		var before: Dictionary = f.checkpoint()
		var signals := [0, 0, 0]
		f.resetting.connect(func(): signals[0] += 1)
		f.sim.paused_changed.connect(func(_p): signals[1] += 1)
		f.sim.stepped.connect(func(_k, _t, _s, _l, _i, _a): signals[2] += 1)
		var writer := Log.new(f)
		var path := output.path_join(kind + ".orfl")
		check(kind + " writer opens", writer.start(path) == OK)
		if kind == "listener-mutation":
			f.resetting.connect(func(): f.sim.mass = 0.0, CONNECT_ONE_SHOT)
		elif kind == "validator-hold":
			f.sim.model.state_validator = func(_frame, context) -> bool:
				if context.tick == 0: f.hold("restore-validator-hold")
				return true
		var accepted: bool = f.restore_checkpoint(target)
		var observed := {case = kind, accepted = accepted, signals = signals.duplicate(),
			tick = f.sim.tick, mass = f.sim.mass, fault = f.sim.fault_reason, recording = writer.recording,
			old_checkpoint_retained = var_to_bytes(before) == var_to_bytes(f.checkpoint()),
			checkpoint_available = not f.checkpoint().is_empty(), holds = f.holds.duplicate(), paused = f.sim.paused}
		observations.append(observed)
		print("RESTORE_AUDIT ", JSON.stringify(observed))
		if kind == "listener-mutation":
			check("late refusal after reset closes old writer and corrupts mass", not accepted and signals == [1, 0, 0]
				and not writer.recording and f.sim.mass == 0.0 and f.checkpoint().is_empty() and f.sim.fault_reason.is_empty())
		elif kind == "validator-hold":
			check("precommit validator refusal leaks normal Session hold", not accepted and signals == [0, 0, 0]
				and writer.recording and f.holds.has("restore-validator-hold"))
		else:
			var inspected: Dictionary = Reader.inspect(path)
			check("normal restore control closes old writer before kernel pause", accepted and signals == [1, 1, 0]
				and not writer.recording and f.sim.tick == 0 and f.sim.paused and inspected.ok
				and var_to_bytes(inspected.footer.checkpoint) == var_to_bytes(before))
		writer.stop("restore audit cleanup")
		f.free()
	var file := FileAccess.open(output.path_join("observations.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({scope = "Assertions reproduce observed defects/normal control, not correctness acceptance", checks = checks, failed = failed, observations = observations}, "\t", true, true))
	file.close()
	print("Restore audit: %d checks, %d failed; %s" % [checks, failed, output])
	quit(1 if failed else 0)
