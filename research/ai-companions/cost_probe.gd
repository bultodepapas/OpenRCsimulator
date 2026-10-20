## Complete player + fleet callback cost; no rendering, audio or real-time FPS claim.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Manager := preload("res://ai/companions/manager.gd")
const Config := preload("res://ai/companions/config.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")

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
	var field_result: Dictionary = FieldLoader.load_from()
	var collision: Dictionary = CollisionSetup.build(field_result.field)
	var lake: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	if not field_result.ok or not collision.ok or not lake.ok:
		printerr("Field fixture failed.")
		quit(1)
		return
	var rows: Array = []
	var complete := true
	for count in [0, 1, 3]:
		var player := Flight.new()
		player.input_enabled = false
		player.crash_auto_restart = false
		player.setup(Catalog.entry(Catalog.DEFAULT_ID).data, Catalog.DEFAULT_ID)
		player.set_field(field_result.field)
		player.set_collision_world(collision.world)
		player.set_lake_context(lake.lake)
		player.reset()
		var fleet := Manager.new()
		var config: Dictionary = Config.defaults()
		config.enabled = count > 0
		config.count = count
		config.seed = 20261020
		var prepared: Dictionary = fleet.configure(player, field_result.field, "club_field", config, false, false)
		var costs := PackedInt64Array()
		var finished := 0
		var failure := ""
		if not prepared.ok:
			failure = str(prepared.errors)
		else:
			for tick in 2640:
				var started := Time.get_ticks_usec()
				player._physics_process(player.sim.dt())
				player.sim._physics_process(player.sim.dt())
				var elapsed := Time.get_ticks_usec() - started
				if tick >= 240: costs.append(elapsed)
				if player.sim.tick != tick + 1 or not player.sim.fault_reason.is_empty():
					failure = "Player failed at tick %d." % tick
					break
				for agent: Node in fleet.agents:
					if agent.session.sim.tick != tick + 1 or not agent.failure.is_empty() or not agent.session.crash.is_empty():
						failure = "Companion failed at tick %d: %s" % [tick, agent.failure]
				if not failure.is_empty(): break
				finished += 1
		costs.sort()
		var mean := 0.0
		for cost in costs: mean += float(cost)
		if not costs.is_empty(): mean /= costs.size()
		rows.append({count = count, finished_ticks = finished, failure = failure,
			samples = costs.size(), mean_usec = mean,
			p50_usec = costs[costs.size() / 2] if not costs.is_empty() else 0,
			p95_usec = costs[mini(costs.size() - 1, ceili(costs.size() * 0.95))] if not costs.is_empty() else 0,
			max_usec = costs[-1] if not costs.is_empty() else 0})
		complete = complete and failure.is_empty()
		fleet.free()
		player.free()
	var report := {format = "openrc-companions-cost v1", complete = complete,
		engine = Engine.get_version_info().string, processor = OS.get_processor_name(),
		warmup_ticks = 240, measured_ticks = 2400, physics_hz = 240,
		note = "Headless complete callbacks with production Club collision inventory; excludes rendering and audio. A local preliminary measurement, not target-hardware qualification.",
		results = rows}
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write report.")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print(JSON.stringify(report))
	quit(0 if complete else 1)
