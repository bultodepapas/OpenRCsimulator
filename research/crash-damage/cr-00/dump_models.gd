# CR-00: dumps each flyable aircraft's mass, inertia (body FRD about the CG) and crash-hull points (body FRD about the
# CG) as one JSON line, read through the app's own loader. Research only: never saved into app/.
# Run from the repository root:
#   $(app/get-godot.sh) --headless --path app --script "$PWD/research/crash-damage/cr-00/dump_models.gd" \
#     | grep '^JSON:' | sed 's/^JSON://' > research/crash-damage/cr-00/models.json
extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const FILES := ["jensen_ugly_stik_60", "gp_extra_300s_60", "p51d_mustang_120", "sebart_avanti_s_a200"]


func _initialize() -> void:
	var out := {}
	for f in FILES:
		var d := AircraftData.load_file("res://data/aircraft/%s.json" % f)
		if not d.ok:
			out[f] = { error = str(d.errors) }
			continue
		var m: Dictionary = d.model
		out[f] = { mass = m.mass_kg, inertia = Array(m.inertia), hull = Array(m.crash_hull) }
	print("JSON:" + JSON.stringify(out))
	quit()
