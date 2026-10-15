# P51-19: elevator-for-trim vs nominal CL at the XP-51 test CGs (24.5, 27, 29.2 % MAC) on the runtime trim solver.
# Moves only the CG (and the CG-relative thrust arm). Compare with research/p51/p51-19/naca_xp51_fig10.json. Research only.
# Run: <godot> --headless --path app --audio-driver Dummy --script <abs path>/trim_probe.gd [-- --data=res://...]
extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const Trim := preload("res://physics/trim.gd")

const DATA := "res://data/aircraft/p51d_mustang_120.json"
const G := 9.80665
const RHO := 1.225
const MAC := 0.5088
const MAC_LE := 0.04038


func _initialize() -> void:
	var path := DATA
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--data="):
			path = arg.trim_prefix("--data=")
	var loaded: Dictionary = AircraftData.load_file(path)
	if not loaded.get("ok", false):
		printerr("load failed: ", loaded.get("message", loaded.get("errors", "")))
		quit(1)
		return
	var base: Dictionary = loaded.model
	var throws := {elevator = deg_to_rad(base.controls.throw_deg.elevator), aileron = deg_to_rad(base.controls.throw_deg.aileron),
		rudder = deg_to_rad(base.controls.throw_deg.rudder)}
	print("mass %.3f S %.4f cg_le %s prop_offset %s" % [base.mass_kg, base.reference.S, base.cg_le, base.propulsion.offset])
	var rows := []
	for cg_frac: float in [0.245, 0.27, 0.292]:
		var model: Dictionary = base.duplicate(true)
		var dx: float = MAC_LE + cg_frac * MAC - float(base.cg_le[0])
		var cg: PackedFloat64Array = model.cg_le
		cg[0] += dx
		model.cg_le = cg
		var off: PackedFloat64Array = model.propulsion.offset
		off[0] -= dx
		model.propulsion.offset = off
		for mode: String in ["level", "glide"]:
			for cl: float in [0.25, 0.3, 0.4, 0.55, 0.7, 0.9, 1.1]:
				var v := sqrt(2.0 * model.mass_kg * G / (RHO * model.reference.S * cl))
				var r: Dictionary = Trim.solve(mode, v, model, G, throws, RHO)
				var line := "cg %.3f %s CL %.2f V %.2f ok %s elev_up %.3f deg alpha %.3f thr %.3f rpm %.0f %s" % [cg_frac, mode, cl, v,
					r.ok, -rad_to_deg(r.elevator), rad_to_deg(r.alpha), r.throttle, r.rpm, "" if r.ok else r.message]
				print(line)
	quit(0)
