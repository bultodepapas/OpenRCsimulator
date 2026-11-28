# Isolated source-build adapter probe. Injects the shared helper's real unresolved
# identity via its process-local source cache; the recording and verifier stay unmodified.
extends SceneTree

const ReplayContainer := preload("res://sim/flight_log.gd")
const FixedCli := preload("res://tools/flight_log_cli.gd")
const Airship := preload("res://sim/airship/session.gd")
const AirshipLog := preload("res://sim/airship/flight_log.gd")
const Multirotor := preload("res://sim/multirotor/session.gd")
const MultirotorLog := preload("res://sim/multirotor/flight_log.gd")
const Field := preload("res://data/field_loader.gd")
const Obstacles := preload("res://scenery/collision_setup.gd")
const Fixtures := preload("res://tests/mr_fixtures.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var directory := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			directory = argument.trim_prefix("--out=")
	if directory.is_empty() or DirAccess.dir_exists_absolute(directory) or DirAccess.make_dir_recursive_absolute(directory) != OK:
		printerr("Provide a new --out directory")
		quit(2)
		return
	var known := ReplayContainer.replay_identity()
	if known.kind != "source-tree-v1":
		printerr("Run in a fresh editor binary, in game mode, with the source project")
		quit(2)
		return
	var field := Field.load_from(Field.DEFAULT_PATH)
	var world := Obstacles.build(field.field)
	if not field.ok or not world.ok:
		printerr("Stock field and world are required")
		quit(2)
		return
	var observed := true
	for unresolved: bool in [false, true]:
		ReplayContainer._solver_identity_cache = "unavailable-export" if unresolved else str(known.sha256)
		var identity := ReplayContainer.replay_identity()
		var control_changed := FixedCli.solver_changed(identity.sha256, identity.sha256, {}, {}, identity.kind, identity.kind)
		for quad: bool in [false, true]:
			var session: Node = Multirotor.new() if quad else Airship.new()
			root.add_child(session)
			var pilot := Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0, 1) if quad else PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
			var family := "multirotor" if quad else "airship"
			var path := directory.path_join(family + ("-unresolved" if unresolved else "-known") + ".orfl")
			var log_owner: RefCounted = MultirotorLog.new(session) if quad else AirshipLog.new(session)
			if not session.set_collision_world(world.world) or not session.prepare(field.field, {}) or not session.resume() or log_owner.start({field_path = Field.DEFAULT_PATH}, path) != OK or not session.tick_once(pilot) or log_owner.stop() != OK:
				printerr("Failed positive live capture setup for " + path)
				ReplayContainer._solver_identity_cache = str(known.sha256)
				quit(2)
				return
			var report := MultirotorLog.verify(path) if quad else AirshipLog.verify(path)
			print("UNRESOLVED_IDENTITY_RECEIPT " + JSON.stringify({family = family, unresolved = unresolved, identity = identity, recorded_identity = log_owner.header.solver_sha256, recorded_kind = log_owner.header.solver_identity_kind, fixed_wing_control_changed = control_changed, report = report}))
			observed = observed and control_changed == unresolved and report.rows == 1 and report.ok and report.complete and report.exact and report.identity_match and not report.solver_changed and log_owner.header.solver_sha256 == identity.sha256 and log_owner.header.solver_identity_kind == identity.kind
			session.free()
	ReplayContainer._solver_identity_cache = str(known.sha256)
	print("UNRESOLVED_ADAPTER_COUNTEREXAMPLE=", observed)
	quit(0 if observed else 1)
