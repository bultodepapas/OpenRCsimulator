extends SceneTree
## X8-06 probe: load the generated X8 data through AircraftData, print the tailless law the loader derived, the trims
## and the strip model against the oracle at small angles (the regime-consistency quantities). Read-only.
##   "$(app/get-godot.sh)" --headless --path app --script research/skywalker-x8/X8-06/probe.gd

const AircraftData := preload("res://physics/aircraft_data.gd")
const Aero := preload("res://physics/aero.gd")
const Trim := preload("res://physics/trim.gd")
const Air := preload("res://physics/air_data.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

const FILES := ["res://data/aircraft/moonrunner_x99.json", "res://data/aircraft/battery/moonrunner_x99_6s_pack.json"]


func _init() -> void:
	for path in FILES:
		var loaded := AircraftData.load_file(path)
		print("== ", path, " ok=", loaded.ok)
		for e in loaded.errors:
			print("  ERROR ", e)
		for w in loaded.warnings:
			print("  warning ", w)
		if not loaded.ok:
			continue
		var model: Dictionary = loaded.model
		print("  mass %.4f kg  cg_le %s  inertia %s" % [model.mass_kg, model.cg_le, model.inertia])
		var tl: Dictionary = model.surfaces.tailless
		print("  tailless: tau %.4f  shift %.4f m  km %.4f  cm_ac %.4f  station_x %s" % [tl.tau, tl.station_shift,
			tl.moment_per_rad, model.surfaces.wing_cm_ac, tl.station_x])
		print("  a0 %.4f  throws %s" % [model.envelope.strip_slope, model.controls.throw_deg])
		print("  envelope a1 %.2f° n1 %.2f°" % [rad_to_deg(model.envelope.a1), rad_to_deg(model.envelope.n1)])
		_compare(model)
		for v in [model.start_speed, 15.0, 18.0, 22.0]:
			var t := Trim.solve("level", v, model, 9.80665, model.controls.throw_rad)
			print("  trim %.1f m/s ok=%s %s α %.2f° δe %.2f° δa %.3f° bank %.3f° β %.3f° throttle %.3f rpm %.0f thrust %.2f N" % [
				v, t.ok, t.message, rad_to_deg(t.alpha), rad_to_deg(t.elevator), rad_to_deg(t.aileron),
				rad_to_deg(float(t.get("bank", 0.0))), rad_to_deg(t.beta), t.throttle, t.rpm, t.thrust])
		var glide := Trim.solve("glide", 12.0, model, 9.80665, model.controls.throw_rad)
		print("  glide 12 m/s ok=%s γ %.2f° (L/D %.1f) α %.2f°" % [glide.ok, rad_to_deg(glide.gamma), -1.0 / tan(glide.gamma) if glide.ok else NAN, rad_to_deg(glide.alpha)])
	quit()


## Coefficients of the local strip model and the oracle from symmetric finite differences at a level state.
func _compare(model: Dictionary) -> void:
	var V := 15.0
	var rho := Air.RHO_SEA_LEVEL
	var qbar := 0.5 * rho * V * V
	var S: float = model.reference.S
	var b: float = model.reference.b
	var c: float = model.reference.c
	var zero := {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}
	var rows := []
	for item in [["CLa", "alpha", 0.02], ["Cma", "alpha", 0.02], ["CLde", "elevator", 0.02], ["Cmde", "elevator", 0.02],
			["Clda", "aileron", 0.02], ["Cmq", "q", 0.2], ["Clp", "p", 0.2], ["Cnr", "r", 0.2], ["Cnb", "beta", 0.02],
			["Clb", "beta", 0.02], ["CYb", "beta", 0.02]]:
		var key: String = item[1]
		var h: float = item[2]
		var out := []
		for local in [false, true]:
			var plus := _coeffs(model, V, rho, key, h, local)
			var minus := _coeffs(model, V, rho, key, -h, local)
			var name: String = item[0]
			var idx: int = {"CL": 0, "Cm": 1, "Cl": 2, "Cn": 3, "CY": 4}[name.substr(0, 2)]
			var scale := 1.0
			if key == "q":
				scale = 2.0 * V / c
			elif key in ["p", "r"]:
				scale = 2.0 * V / b
			out.append((plus[idx] - minus[idx]) / (2.0 * h) * scale)
		rows.append("%s oracle %.4f local %.4f" % [item[0], out[0], out[1]])
	print("  regimes @15 m/s: ", " | ".join(rows))


func _coeffs(model: Dictionary, V: float, rho: float, key: String, h: float, local: bool) -> Array:
	var alpha := 0.03 + (h if key == "alpha" else 0.0)
	var beta := h if key == "beta" else 0.0
	var rates := M.v3(h if key == "p" else 0.0, h if key == "q" else 0.0, h if key == "r" else 0.0)
	var s := RB.make_state(M.v3(0, 0, -100), M.v3(V * cos(alpha) * cos(beta), V * sin(beta), V * sin(alpha) * cos(beta)),
		M.q_from_euler(0, alpha, 0), rates)
	var d := {elevator = h if key == "elevator" else 0.0, aileron_right = h if key == "aileron" else 0.0,
		aileron_left = -h if key == "aileron" else 0.0, rudder = 0.0}
	var air: Dictionary = Air.compute(s, M.v3(0, 0, 0), rho)
	var loads: PackedFloat64Array = Aero._local_loads(s, air, d, model, rho) if local else Aero._global_loads(s, air, d, model, rho)
	var qbar: float = 0.5 * rho * V * V
	var S: float = model.reference.S
	var b: float = model.reference.b
	var c: float = model.reference.c
	# Body forces to lift (wind axes, small sideslip), moments about the CG normalised.
	var ca := cos(alpha)
	var sa := sin(alpha)
	var lift := -(loads[2] * ca - loads[0] * sa)
	return [lift / (qbar * S), loads[4] / (qbar * S * c), loads[3] / (qbar * S * b), loads[5] / (qbar * S * b), loads[1] / (qbar * S)]

