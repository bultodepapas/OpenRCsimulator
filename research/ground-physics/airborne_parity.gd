extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Weather := preload("res://physics/wind_config.gd")
const Fields := preload("res://data/field_loader.gd")


func _initialize() -> void:
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	var rows: Array = []
	for aircraft in Catalog.ENTRIES:
		for windy in [false, true]:
			var session := Session.new()
			session.setup(aircraft.data)
			root.add_child(session)
			session.input_enabled = false
			var weather := Weather.defaults()
			weather.speed_mps = 5.0 if windy else 0.0
			weather.from_deg = 0.0
			if not session.setup_weather(weather) or not session.set_field(Fields.load_from().field):
				quit(1)
				return
			session.reset()
			var digest := HashingContext.new()
			digest.start(HashingContext.HASH_SHA256)
			var initial: PackedFloat64Array = session.sim.inputs.duplicate()
			var lowest := INF
			for tick in 1200:
				session.sim.inputs = initial.duplicate()
				if tick >= 240 and tick < 360:
					session.sim.inputs[0] = 0.15
				if tick >= 600 and tick < 720:
					session.sim.inputs[2] = -0.1
				session.sim.step()
				if not session.sim.fault_reason.is_empty():
					printerr(session.sim.fault_reason)
					quit(1)
					return
				for values in [session.sim.state, session.sim.aux, session.sim.last_loads, session.sim.inputs]:
					digest.update(values.to_byte_array())
				lowest = minf(lowest, -session.sim.state[2])
			rows.append({aircraft = aircraft.id, windy = windy, ticks = session.sim.tick,
				minimum_altitude_m = lowest, body_aux_loads_inputs_sha256 = digest.finish().hex_encode()})
			session.free()
	var report := {engine = Engine.get_version_info().string, cases = rows}
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	print("GP parity: ", rows.size(), " airborne cases written")
	quit()
