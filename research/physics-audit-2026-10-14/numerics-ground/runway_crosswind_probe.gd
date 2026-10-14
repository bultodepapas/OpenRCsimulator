extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const WindConfig := preload("res://physics/wind_config.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const GroundStart := preload("res://physics/ground_start.gd")

const AIRCRAFT_PATH := "res://data/aircraft/sebart_avanti_s_a200.json"


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	var field_result: Dictionary = FieldLoader.load_from()
	if not field_result.get("ok", false):
		printerr("field load failed: ", field_result.get("errors", []))
		quit(1)
		return
	var field: Dictionary = field_result.field
	var spot: Dictionary = GroundStart.threshold(field)
	if not spot.get("ok", false):
		printerr("runway spot failed: ", spot)
		quit(1)
		return
	print("aircraft=", AIRCRAFT_PATH, " field=", field.get("id", ""), " spot=", spot)
	var failed := 0
	for speed in [0.0, 0.5, 1.0, 1.5]:
		var settings: Dictionary = WindConfig.defaults()
		settings.speed_mps = speed
		settings.from_deg = 0.0
		var session: Node = Session.new()
		if not session.setup_weather(settings):
			printerr("weather setup failed at ", speed, ": ", session.weather_error)
			failed += 1
			session.free()
			continue
		session.setup(AIRCRAFT_PATH)
		root.add_child(session)
		var wind: PackedFloat64Array = session.wind_at(0.0)
		var field_ok: bool = session.set_field(field)
		var accepted: bool = field_ok and session.reset_on_runway(spot.north, spot.east, spot.heading)
		print("crosswind_m_s=", speed, " from_deg=0.0 wind_ned=", wind,
			" field_ok=", field_ok, " runway_accepted=", accepted,
			" start_error=", session.start_error, " fault=", session.sim.fault_reason)
		if not accepted:
			failed += 1
		session.free()
	print("runway crosswind probe: ", failed, " rejected starts of 4")
	quit(1 if failed > 0 else 0)
