extends SceneTree

const FlightLog := preload("res://sim/flight_log.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var options := _options(OS.get_cmdline_user_args())
	var log_path := str(options.get("orfl", ""))
	var output_path := str(options.get("out", ""))
	if log_path.is_empty() or output_path.is_empty():
		_fail("expected --orfl=PATH and --out=PATH")
		return
	var file := FileAccess.open(log_path, FileAccess.READ)
	if file == null:
		_fail("cannot open ORFL: %s" % FileAccess.get_open_error())
		return
	if file.get_length() < 8 or file.get_buffer(8).get_string_from_ascii() != FlightLog.MAGIC:
		_fail("ORFL magic mismatch")
		return
	var packet: Dictionary = FlightLog.read_packet(file)
	if not bool(packet.get("ok", false)):
		_fail("ORFL header packet failed validation: %s" % str(packet.get("error", "unknown")))
		return
	var header: Dictionary = packet.value
	if str(header.get("kind", "")) != "header" or str(header.get("format", "")) != FlightLog.FORMAT:
		_fail("ORFL first packet is not the expected header")
		return
	var world: Dictionary = header.get("collision_world", {})
	var checkpoint_value: Variant = header.get("checkpoint", null)
	if typeof(checkpoint_value) != TYPE_DICTIONARY:
		_fail("ORFL header has no initial checkpoint")
		return
	var checkpoint: Dictionary = checkpoint_value
	var initial_scenery_damage: Dictionary = checkpoint.get("scenery_damage", {})
	var aircraft: Dictionary = header.get("aircraft", {})
	var model: Dictionary = aircraft.get("model", {})
	var gear: Dictionary = model.get("landing_gear", {})
	var contacts: Array = gear.get("contacts", [])
	var hull: PackedFloat64Array = model.get("crash_hull", PackedFloat64Array())
	var hull_components: PackedStringArray = model.get("crash_hull_components", PackedStringArray())
	var proxies: Array = world.get("proxies", [])
	if str(world.get("format", "")) != "openrc-collision-world v1" or proxies.is_empty():
		_fail("ORFL header has no expected collision world")
		return
	if hull.is_empty() or hull.size() % 3 != 0 or contacts.size() < 3:
		_fail("loaded aircraft hull or gear geometry is missing")
		return
	var proxy_rows: Array[Dictionary] = []
	for proxy_value: Variant in proxies:
		if typeof(proxy_value) != TYPE_DICTIONARY:
			_fail("collision proxy is not a dictionary")
			return
		var proxy: Dictionary = proxy_value
		var shape := str(proxy.get("shape", ""))
		if shape == "box":
			proxy_rows.append({
				"id": str(proxy.get("id", "")), "shape": shape,
				"north": float(proxy.north), "east": float(proxy.east), "down": float(proxy.down),
				"sin_heading": float(proxy.sin_heading), "cos_heading": float(proxy.cos_heading),
				"half_x": float(proxy.half_x), "half_down": float(proxy.half_down), "half_z": float(proxy.half_z),
				"bounds": [float(proxy.bounds_north_min), float(proxy.bounds_north_max),
					float(proxy.bounds_east_min), float(proxy.bounds_east_max),
					float(proxy.bounds_down_min), float(proxy.bounds_down_max)],
			})
		elif shape == "capsule":
			proxy_rows.append({
				"id": str(proxy.get("id", "")), "shape": shape,
				"north": float(proxy.north), "east": float(proxy.east), "down": float(proxy.down),
				"radius": float(proxy.radius), "half_length": float(proxy.half_length),
				"bounds": [float(proxy.bounds_north_min), float(proxy.bounds_north_max),
					float(proxy.bounds_east_min), float(proxy.bounds_east_max),
					float(proxy.bounds_down_min), float(proxy.bounds_down_max)],
			})
		else:
			_fail("unsupported collision proxy shape: %s" % shape)
			return
	var gear_positions: Array = []
	for contact_value: Variant in contacts:
		if typeof(contact_value) != TYPE_DICTIONARY or not contact_value.get("position") is PackedFloat64Array:
			_fail("loaded gear contact position has an unexpected type")
			return
		var contact: Dictionary = contact_value
		gear_positions.append({"name": str(contact.get("name", "")), "position_body_frd": contact.position})
	var aircraft_identity: Dictionary = aircraft.get("input_identity", {})
	var payload := {
		"format": "afc08-recorded-clearance-inputs-v1",
		"orfl_path": log_path,
		"orfl_sha256": FlightLog.sha256(FileAccess.get_file_as_bytes(log_path)).hex_encode(),
		"solver_sha256": str(header.get("solver_sha256", "")),
		"collision_world": {
			"format": str(world.format), "identity": str(world.identity),
			"proxy_count": proxies.size(), "proxies": proxy_rows,
			"scan_scope": "all proxies from the exact ORFL header; bins are deliberately not used",
		},
		"initial_checkpoint": {"scenery_damage": initial_scenery_damage},
		"aircraft": {
			"input_sha256": str(aircraft_identity.get("sha256", "")),
			"crash_hull_probe_points_body_frd": hull,
			"crash_hull_component_names": hull_components,
			"landing_gear_contact_points": gear_positions,
			"prop_disc_geometry_present": typeof(model.get("propulsion", {})) == TYPE_DICTIONARY
				and model.get("propulsion", {}).has("diameter") and model.get("propulsion", {}).has("offset"),
			"prop_disc_clearance_status": "not_measured; no exact scenery-proxy distance method is present",
		},
	}
	var output := FileAccess.open(output_path, FileAccess.WRITE)
	if output == null:
		_fail("cannot write clearance input export: %s" % FileAccess.get_open_error())
		return
	output.store_string(JSON.stringify(payload, "\t", true, true) + "\n")
	output.close()
	print("AFC08 clearance geometry exported: %d proxies, %d hull probes, %d gear points" % [
		proxies.size(), hull.size() / 3, gear_positions.size()])
	quit(0)


func _options(args: PackedStringArray) -> Dictionary:
	var out := {}
	for arg: String in args:
		if not arg.begins_with("--") or not arg.contains("="):
			continue
		var split := arg.trim_prefix("--").split("=", false, 1)
		out[split[0]] = split[1]
	return out


func _fail(reason: String) -> void:
	push_error("AFC08 clearance export: " + reason)
	quit(1)
