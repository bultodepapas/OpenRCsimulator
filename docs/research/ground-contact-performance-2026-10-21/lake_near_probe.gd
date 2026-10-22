extends SceneTree
const Flight = preload("res://sim/flight_session.gd")
const Field = preload("res://data/field_loader.gd")
const Lake = preload("res://data/lake_loader.gd")
const Catalog = preload("res://app_state/aircraft_catalog.gd")
const SAMPLES := 40

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var field: Dictionary = Field.load_from().field
	var lake: Dictionary = Lake.load_from().lake
	for id in Catalog.airplane_flyable_ids():
		var session = Flight.new()
		session.input_enabled = false
		session.soft_hull_contacts = true
		session.setup(Catalog.entry(id).data, id)
		session.set_field(field)
		session.set_lake_context(lake)
		session.start_choice = Flight.START_RUNWAY
		root.add_child(session)
		session.reset()
		if session.glow_is_active() and not session.engine_running:
			session.glow_start()
		var sim = session.sim
		if not sim.model.stage.is_valid():
			session.queue_free()
			await process_frame
			continue
		var values: PackedFloat64Array = sim.continuous.duplicate()
		for case in ["runway", "lake_low", "lake_high"]:
			var body: PackedFloat64Array = sim.state.duplicate()
			if case != "runway":
				body[0] = 110.0
				body[1] = 125.0
				body[2] = -0.4 if case == "lake_low" else -30.0
			for i in 5:
				sim.model.stage.call(body, values, 0.0)
			var begin := Time.get_ticks_usec()
			for i in SAMPLES:
				sim.model.stage.call(body, values, 0.0)
			print(JSON.stringify({id=id, case=case, stage_us=float(Time.get_ticks_usec()-begin)/SAMPLES}))
		session.queue_free()
		await process_frame
	quit()
