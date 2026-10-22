extends SceneTree
const Flight = preload("res://sim/flight_session.gd")
const Field = preload("res://data/field_loader.gd")
const Catalog = preload("res://app_state/aircraft_catalog.gd")
const Lake = preload("res://data/lake_loader.gd")
const STAGE_SAMPLES := 80
const TICKS := 120

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var field: Dictionary = Field.load_from().field
	var reports: Array = []
	for id in Catalog.airplane_flyable_ids():
		for regime in [Flight.START_RUNWAY, Flight.START_AIRBORNE]:
			for soft in [false, true]:
				var session = Flight.new()
				session.input_enabled = false
				session.crash_auto_restart = false
				session.soft_hull_contacts = soft
				session.setup(Catalog.entry(id).data, id)
				session.set_field(field)
				session.set_lake_context(Lake.load_from().lake)
				session.start_choice = regime
				root.add_child(session)
				session.reset()
				if not session.start_error.is_empty():
					printerr(id, "/", regime, " start: ", session.start_error)
					quit(1)
					return
				if session.glow_is_active() and not session.engine_running:
					session.glow_start()
				var inputs: PackedFloat64Array = session.sim.inputs.duplicate()
				inputs[3] = 1.0
				session.sim.inputs = inputs
				var sim = session.sim
				sim.paused = true
				var hull_points: int = int(session._hull_contact.get("points", PackedFloat64Array()).size() / 3)
				var stage_us: float = -1.0
				if sim.model.stage.is_valid():
					var body: PackedFloat64Array = sim.state.duplicate()
					var values: PackedFloat64Array = sim.continuous.duplicate()
					for i in 5:
						sim.model.stage.call(body, values, 0.0)
					var stage_begin: int = Time.get_ticks_usec()
					for i in STAGE_SAMPLES:
						sim.model.stage.call(body, values, 0.0)
					stage_us = float(Time.get_ticks_usec() - stage_begin) / STAGE_SAMPLES
				var begin: int = Time.get_ticks_usec()
				for i in TICKS:
					sim.step()
					if not sim.fault_reason.is_empty():
						break
				var completed: int = sim.tick
				var tick_us: float = float(Time.get_ticks_usec() - begin) / maxi(1, completed)
				var record := {id=id, regime=regime, soft=soft, stage_us=stage_us,
					tick_us=tick_us, ticks=completed, fault=sim.fault_reason,
					hull_points=hull_points, continuous=sim.continuous.size(),
					end_position=sim.state.slice(0,3), end_speed=sim.state.slice(3,6)}
				reports.append(record)
				print(JSON.stringify(record))
				session.queue_free()
				await process_frame
	var destination := ProjectSettings.globalize_path("res://../tmp/fleet-contact-lake-probe.json")
	var file := FileAccess.open(destination, FileAccess.WRITE)
	file.store_string(JSON.stringify({format="fleet-contact-probe-v1", aircraft=reports}, "\t") + "\n")
	file.close()
	quit()

