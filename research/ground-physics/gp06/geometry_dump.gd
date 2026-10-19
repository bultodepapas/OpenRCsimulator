# GP-06 geometry audit, step 1: dump what the production loader derives for every geared catalog airplane (mass, CG,
# inertia, landing-gear contacts in body FRD about the CG with their profiled wheel radii, crash hull and labels,
# propeller disc, wing reference and stall envelope). geometry_audit.py turns the dump into the landing-gear table.
# Run: godot --headless --path app --script "$PWD/research/ground-physics/gp06/geometry_dump.gd" -- --out=<file.json>
extends SceneTree

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")


func _initialize() -> void:
	var out_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
	var result := {format = "openrc-gp06-geometry-dump v1", aircraft = {}}
	for entry: Dictionary in Catalog.airplane_flyable_entries():
		var loaded: Dictionary = AircraftData.load_file(str(entry.data))
		if not loaded.ok or loaded.model.get("landing_gear", {}).is_empty():
			continue
		var m: Dictionary = loaded.model
		var envelope := {}
		for key in m.envelope:
			if typeof(m.envelope[key]) in [TYPE_FLOAT, TYPE_INT]:
				envelope[key] = m.envelope[key]
		var aero := {}
		for key in ["CL0", "CLa"]:
			aero[key] = m.aero.get(key, NAN)
		var propeller := {}
		for key in ["kind", "offset", "diameter", "axis"]:
			if m.propulsion.has(key):
				propeller[key] = m.propulsion[key]
		var contacts := []
		for c: Dictionary in m.landing_gear.contacts:
			contacts.append({name = c.name, position = Array(c.position), stiffness = c.stiffness, damping = c.damping,
				max_compression = c.max_compression, max_steering_deg = rad_to_deg(float(c.get("max_steering", 0.0))),
				wheel_radius = c.get("wheel_radius", null)})
		result.aircraft[entry.id] = {mass_kg = m.mass_kg, cg_le = Array(m.cg_le), inertia = Array(m.inertia),
			span_m = m.reference.b, area_m2 = m.reference.S, contacts = contacts, hull = Array(m.crash_hull),
			hull_components = Array(m.crash_hull_components), propeller = propeller, envelope = envelope, aero = aero,
			wheel_profile = str(m.get("wheel_profile", {}).get("status", ""))}
	var text := JSON.stringify(result, "  ", false) + "\n"
	if out_path.is_empty():
		print(text)
	else:
		var file := FileAccess.open(out_path, FileAccess.WRITE)
		file.store_string(text)
		file.close()
	quit(0)
