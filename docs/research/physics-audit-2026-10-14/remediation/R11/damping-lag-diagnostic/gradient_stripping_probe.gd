extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const AircraftCatalog := preload("res://app_state/aircraft_catalog.gd")
const FlightSession := preload("res://sim/flight_session.gd")

func _initialize() -> void:
	for aircraft_id in ["gp-extra-300s-60", "p51d-mustang-120", "sebart-avanti-s-a200-p100rx"]:
		var entry: Dictionary = AircraftCatalog.entry(aircraft_id)
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(entry.data))
		var original: Dictionary = AircraftData.validate_and_derive(raw.duplicate(true))
		raw.aero.surfaces.horizontal.erase("downwash_gradient")
		var stripped: Dictionary = AircraftData.validate_and_derive(raw)
		print("CASE id=%s path=%s" % [aircraft_id, entry.data])
		print("  original_ok=%s original_lag=%s" % [str(original.get("ok", false)), str(original.get("model", {}).get("surfaces", {}).get("horizontal", {}).get("downwash_lag_length", "absent"))])
		print("  stripped_ok=%s stripped_errors=%s" % [str(stripped.get("ok", false)), str(stripped.get("errors", PackedStringArray()))])
		if stripped.get("ok", false):
			print("  stripped_free_slope=%s stripped_lag=%s" % [str(stripped.model.get("surfaces", {}).get("horizontal", {}).get("free_slope", "absent")), str(stripped.model.get("surfaces", {}).get("horizontal", {}).get("downwash_lag_length", "absent"))])
		var session := FlightSession.new()
		session.setup(entry.data)
		root.add_child(session)
		session.expected_aircraft_id = ""
		var applied := session._apply(stripped)
		print("  session_apply=%s active_id=%s lag_index=%s" % [str(applied), str(session.aircraft.get("id", "")), str(session.downwash_index())])
		session.queue_free()
	quit(0)
