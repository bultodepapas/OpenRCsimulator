# GP-03: resolved aircraft geometry, inertia and wheel provenance for review/tuning.
extends SceneTree
const AD := preload("res://physics/aircraft_data.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
func _initialize() -> void:
	var rows: Array = []
	for entry in Catalog.ENTRIES:
		var data: Dictionary = AD.load_file(entry.data)
		if not data.ok:
			printerr(data.errors)
			quit(1)
			return
		var model: Dictionary = data.model
		rows.append({id = entry.id, source = entry.data, input_identity = data.get("input_identity", {}),
			mass_kg = model.mass_kg, inertia_kgm2 = Array(model.inertia), cg_le_m = Array(model.cg_le),
			landing_gear = model.landing_gear, wheel_profile = model.get("wheel_profile", {})})
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			var file := FileAccess.open(arg.trim_prefix("--out="), FileAccess.WRITE)
			if file == null:
				quit(1)
				return
			file.store_string(JSON.stringify({engine = Engine.get_version_info().string, aircraft = rows}, "\t") + "\n")
	print("GP inventory: ", rows.size(), " aircraft")
	quit()
