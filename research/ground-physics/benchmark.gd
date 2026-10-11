# GP-05: run alone. Reports individual evaluation/tick timings, not batch-percentile latency.
extends SceneTree
const Session := preload("res://sim/flight_session.gd")
const AD := preload("res://physics/aircraft_data.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Ground := preload("res://physics/ground_contact.gd")
const Fields := preload("res://data/field_loader.gd")
const Surfaces := preload("res://physics/ground_surfaces.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

func _stats(values: Array) -> Dictionary:
	var raw := values.duplicate()
	values.sort()
	return {median_us = values[values.size() / 2], p95_us = values[int(values.size() * 0.95)], samples = values.size(), individual_us = raw}

func _initialize() -> void:
	var support_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--support="): support_path = arg.trim_prefix("--support=")
	var support_report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(support_path))
	var supports: Dictionary = {}
	for item in support_report.aircraft: supports[item.id] = PackedFloat64Array(item.support.runway_east_state)
	var report: Dictionary = {engine = Engine.get_version_info().string, host = OS.get_name(), cpu = OS.get_processor_name(), stages = [], ticks = []}
	var surfaces: PackedFloat64Array = Surfaces.build(Surfaces.load_table().table, Fields.load_from().field).rects
	for entry in Catalog.ENTRIES:
		var model: Dictionary = AD.load_file(entry.data).model
		if model.landing_gear.is_empty():
			continue
		var gear: Dictionary = model.landing_gear
		var lowest := 0.0
		for contact in gear.contacts:
			lowest = maxf(lowest, contact.position[2])
		var s := RB.make_state(M.v3(15, 0, -lowest + 0.02), M.v3(5, 0, 0), M.q_from_euler(0, 0, 0), M.v3(0, 0, 0))
		var rims := PackedFloat64Array()
		rims.resize(gear.contacts.size())
		rims.fill(5.0)
		var times: Array = []
		for i in 2200:
			var at := Time.get_ticks_usec()
			Ground.evaluate(s, gear, 0.0, surfaces, PackedFloat64Array(), rims, 0.0, false)
			if i >= 200:
				times.append(Time.get_ticks_usec() - at)
		report.stages.append({aircraft = entry.id, regime = "fixed state, wheels in grass contact", stats = _stats(times)})
	for entry in Catalog.ENTRIES:
		var session := Session.new()
		session.setup(entry.data)
		root.add_child(session)
		session.input_enabled = false
		session.set_field(Fields.load_from().field)
		for regime in ["airborne", "idle_runway", "takeoff"]:
			if regime != "airborne" and session.aircraft.model.landing_gear.is_empty():
				continue
			var start_pose: PackedFloat64Array = PackedFloat64Array() if regime == "airborne" else supports[entry.id]
			_start(session, regime, start_pose)
			var times: Array = []
			for i in 1200:
				# Repeated half-second takeoff blocks avoid timing a crashed/uncontrolled taildragger.
				if regime == "takeoff" and i > 0 and i % 120 == 0:
					_start(session, regime, start_pose)
				var at := Time.get_ticks_usec()
				session.sim.step()
				if i >= 200:
					times.append(Time.get_ticks_usec() - at)
				if not session.sim.fault_reason.is_empty():
					quit(1)
					return
			report.ticks.append({aircraft = session.aircraft.model.id, regime = regime, stats = _stats(times)})
		session.free()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			var file := FileAccess.open(arg.trim_prefix("--out="), FileAccess.WRITE)
			file.store_string(JSON.stringify(report, "\t") + "\n")
	print("GP_BENCH_JSON ", JSON.stringify(report))
	quit()

func _start(session: Node, regime: String, pose: PackedFloat64Array) -> void:
	session.reset()
	if regime == "airborne": return
	session.sim.inputs = PackedFloat64Array([0.0, 0.0, 0.0, 1.0 if regime == "takeoff" else 0.0])
	for i in 4: session.sim.aux[i] = 0.0
	session.sim.aux[0] = session.aircraft.model.propulsion.idle_rpm
	session.sim.reset(pose)
	session.sim.set_paused(false)
