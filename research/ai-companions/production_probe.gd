## Two-minute production manager check, including Club scenery collision and lake context.
## Detached nodes let the ordinary player callbacks run without wall-clock pacing.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Manager := preload("res://ai/companions/manager.gd")
const Config := preload("res://ai/companions/config.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const TICKS := 28800

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var output := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): output = argument.trim_prefix("--out=")
	if output.is_empty() or FileAccess.file_exists(output):
		printerr("Supply --out=<new JSON file>.")
		quit(2)
		return
	var field: Dictionary = FieldLoader.load_from()
	var lake: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	if not field.ok or not lake.ok:
		printerr("Field/lake fixture failed.")
		quit(1)
		return
	var collision: Dictionary = CollisionSetup.build(field.field)
	if not collision.ok:
		printerr("Collision fixture failed.")
		quit(1)
		return
	var player := Flight.new()
	player.input_enabled = false
	player.crash_auto_restart = false
	player.setup(Catalog.entry(Catalog.DEFAULT_ID).data, Catalog.DEFAULT_ID)
	player.set_field(field.field)
	player.set_collision_world(collision.world)
	player.set_lake_context(lake.lake)
	player.reset()
	var fleet := Manager.new()
	var config: Dictionary = Config.defaults()
	config.enabled = true
	config.count = 3
	config.seed = 1 # Odd seed also exercises the opposite circuit direction to the matrix.
	var configured: Dictionary = fleet.configure(player, field.field, "club_field", config, false, false)
	var failure := "" if configured.ok else str(configured.errors)
	var completed := 0
	var min_clearance := INF
	if failure.is_empty():
		for tick in TICKS:
			player._physics_process(player.sim.dt())
			player.sim._physics_process(player.sim.dt())
			if player.sim.tick != tick + 1 or not player.sim.fault_reason.is_empty() or not player.crash.is_empty():
				failure = "Player stopped at tick %d." % tick
				break
			for agent: Node in fleet.agents:
				if agent.session.sim.tick != tick + 1 or not agent.failure.is_empty() or not agent.session.crash.is_empty():
					failure = "%s stopped at tick %d: %s %s" % [agent.name, tick, agent.failure, str(agent.session.crash)]
					break
				var state: PackedFloat64Array = agent.session.sim.state
				var clearance: float = -state[2] - float(agent.session.environment.ground(state[0], state[1])[0])
				min_clearance = minf(min_clearance, clearance)
				if clearance < 20.0:
					failure = "%s fell below 20 m clearance at tick %d." % [agent.name, tick]
					break
			if not failure.is_empty(): break
			completed += 1
	var report := {format = "openrc-companions-production v1", complete = completed == TICKS and failure.is_empty(),
		failure = failure, ticks = completed, requested_ticks = TICKS, physics_hz = 240,
		count = 3, seed = 1, weather = "calm", min_clearance_m = min_clearance if is_finite(min_clearance) else null,
		engine = Engine.get_version_info().string,
		scope = "Full production manager/session callbacks, Club collision inventory and lake context. No rendering/audio or long-session resource-soak claim."}
	fleet.free()
	player.free()
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write report.")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print(JSON.stringify(report))
	print("COMPANION PRODUCTION CHECK COMPLETE")
	quit(0 if report.complete else 1)
