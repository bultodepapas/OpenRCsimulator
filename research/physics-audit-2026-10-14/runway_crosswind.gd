## Lead reproduction of runway start failure; production model and field, no tuning.
extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const GroundStart := preload("res://physics/ground_start.gd")
const WindConfig := preload("res://physics/wind_config.gd")

var output := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	if output.is_empty():
		quit(1)
		return
	call_deferred("_run")

func _run() -> void:
	var field := FieldLoader.load_from()
	if not field.ok:
		printerr("FIELD_LOAD_FAILED ", field)
		quit(1)
		return
	var spot := GroundStart.threshold(field.field)
	var report := {method = "Default field eastbound threshold, 240Hz, current production aircraft. Each case starts a new FlightSession. Observe reset_on_runway result; no physical coefficient changes.", spot = spot, cases = []}
	for path in ["res://data/aircraft/jensen_ugly_stik_60.json", "res://data/aircraft/sebart_avanti_s_a200.json"]:
		for pair in [[0.0,0.0],[1.5,0.0],[1.5,0.001],[1.5,359.999],[1.5,1.0],[1.5,359.0],[1.5,90.0]]:
			var weather := WindConfig.defaults()
			weather.speed_mps = pair[0]
			weather.from_deg = pair[1]
			var session := Flight.new()
			var weather_ok: bool = session.setup_weather(weather)
			session.setup(path)
			root.add_child(session)
			session.set_physics_process(false)
			session.sim.set_physics_process(false)
			session.input_enabled = true
			var field_ok: bool = session.set_field(field.field)
			var prerequisites: bool = weather_ok and session.aircraft.get("ok", false) and field_ok and spot.ok
			var accepted: bool = session.reset_on_runway(spot.north, spot.east, spot.heading) if prerequisites else false
			var row := {path = path, speed_mps = pair[0], from_deg = pair[1], prerequisites_ok = prerequisites,
				runway_start_accepted = accepted, input_sha256 = session.aircraft.get("input_identity", {}).get("sha256", ""),
				launch = session._launch_metadata.duplicate(true), state = Array(session.sim.state)}
			report.cases.append(row)
			print("RUNWAY_CASE ", JSON.stringify(row))
			session.free()
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t", true, true))
	file.close()
	print("RUNWAY_PROBE_COMPLETE observations=", report.cases.size())
	quit(0)
