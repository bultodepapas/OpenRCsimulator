extends SceneTree
const Session = preload("res://sim/flight_session.gd")
const Trace = preload("res://sim/trace.gd")
const Catalog = preload("res://app_state/aircraft_catalog.gd")

func _initialize() -> void:
	var session: Node = Session.new()
	session.input_enabled = false
	session.setup()
	root.add_child(session)
	session.aircraft_path = Catalog.entry("stik-glow-55ax-2t").data
	print("RELOAD ", session.reload())
	var m: Dictionary = session.trace_meta()
	for k in ["metadata_schema","propulsion_model","glow_family","continuous_layout","glow_trace_schema","glow_fuel_tank_id","glow_feed_line_inventory_id","glow_fuel_registry_sha256","glow_identity","glow_recording_start","recording_start_continuous","recording_start_aux","recording_start_tick","recording_start_engine_running","dt_s","shaft_integrator","rotor_coupling","wheel_state_layout","launch_continuous","wheel_brakes","wheel_state_model","wheel_profile_status","wheel_profile_sha256","wheel_profile_input_sha256","wheel_profile_hash_convention"]:
		print("META ",k,"=",m.get(k,"<absent>"))
	var trace = Trace.new()
	trace.meta=m.duplicate(true)
	trace._prepare_weather()
	print("WEATHER invalid=",trace._invalid_weather," glow=",trace._glow," columns=",trace.columns())
	quit()

