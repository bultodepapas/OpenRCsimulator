# D10-R5 (2026-10-19): static roll and yaw due to sideslip about the CG, per regime, against NASA FASER (Ultra Stick 120,
# Owens, Cox, Morelli 2006 Fig. 2b; faser_clb.csv / faser_cnb.csv digitized by d8b-r2/analog/faser_cl.py).
# For each angle of attack it differentiates the body-axis rolling and yawing moments about the CG over beta = +/-1 deg
# (25 m/s, rates and controls zero) in three forms: the small-angle oracle (Aero._global_loads), the local strip law
# (Aero._local_loads) and the production blend (Aero.loads), and prints the blend weight between them. Read-only.
# Run from the repository root, with absolute or res:// paths:
#   godot --headless --path app --script "$PWD/research/flight-dynamics/stik-lateral-directional/roll_regimes.gd" \
#     -- res://data/aircraft/jensen_ugly_stik_60.json [more.json ...] [--csv=<dir>]
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

const ANALOG := "res://../research/flight-robustness/d8b-r2/analog/"
const SPEED := 25.0
const RHO := 1.225
const STEP_DEG := 1.0
const ZERO := {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}
const TABLE_DEG := [0.0, 4.0, 8.0, 10.0, 12.0, 14.0, 16.0, 20.0, 25.0, 30.0]


func _initialize() -> void:
	var paths := PackedStringArray()
	var csv_dir := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--csv="):
			csv_dir = arg.trim_prefix("--csv=")
		else:
			paths.append(arg)
	var faser_clb := _csv(ANALOG + "faser_clb.csv", 2)
	var faser_cnb := _csv(ANALOG + "faser_cnb.csv", 2)
	if paths.is_empty() or faser_clb.is_empty() or faser_cnb.is_empty():
		printerr("usage: -- <aircraft json> [...] [--csv=<dir>]; needs faser_clb.csv and faser_cnb.csv")
		quit(2)
		return
	for path in paths:
		var data := AD.load_file(path)
		if not data.ok:
			printerr(path, ": ", data.errors)
			quit(1)
			return
		var model: Dictionary = data.model
		var a: Dictionary = model.aero
		var b: float = model.reference.b
		var h: float = float(model.reference.arp_le[2]) - float(model.cg_le[2])
		var fin: Dictionary = model.surfaces.vertical
		var fin_cy: float = -float(fin.lift_slope) * float(fin.area) / float(model.reference.S)
		print("\n## %s" % path.get_file())
		print("Oracle: Clb %+.4f about the ARP; side-force transfer CYb·h/b = %+.4f·%.4f/%.4f = %+.4f; Clβ at the CG %+.4f" % [
			a.Clb, a.CYb, h, b, a.CYb * h / b, a.Clb + a.CYb * h / b])
		print("Local: fin CYβ %+.4f at %.4f m above the CG -> Clβ %+.4f; wing-body couple %s" % [
			fin_cy, float(fin.position[2]) - float(model.cg_le[2]), fin_cy * (float(fin.position[2]) - float(model.cg_le[2])) / b,
			"%+.5f" % model.surfaces.wing_body_cl_beta if model.surfaces.has("wing_body_cl_beta") else "none"])
		var response := _dihedral_response(model)
		print("Lifting line through this wing's calibrated induced map: antisymmetric incidence dCl/dδ %+.4f per rad -> geometric dihedral Clβ/Γ %+.5f per rad per deg of Γ" % [
			response, response * deg_to_rad(1.0)])
		print("| α° | blend | Clβ oracle | Clβ local | Clβ production | FASER Clβ | Cnβ oracle | Cnβ local | Cnβ production | FASER Cnβ |")
		print("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
		var lines := PackedStringArray(["alpha_deg,blend,clb_oracle,clb_local,clb_production,cnb_oracle,cnb_local,cnb_production"])
		var k := -4.0
		while k <= 30.0 + 1e-9:
			var row := _derivatives(model, deg_to_rad(k))
			lines.append("%.1f,%.4f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f" % [k, row.blend, row.clb[0], row.clb[1], row.clb[2],
				row.cnb[0], row.cnb[1], row.cnb[2]])
			if k in TABLE_DEG:
				print("| %.0f | %.2f | %+.4f | %+.4f | %+.4f | %+.4f | %+.4f | %+.4f | %+.4f | %+.4f |" % [k, row.blend,
					row.clb[0], row.clb[1], row.clb[2], faser_clb.get(k, NAN), row.cnb[0], row.cnb[1], row.cnb[2],
					faser_cnb.get(k, NAN)])
			k += STEP_DEG
		if not csv_dir.is_empty():
			var out := csv_dir.path_join(path.get_file().get_basename() + "-roll-regimes.csv")
			var f := FileAccess.open(out, FileAccess.WRITE)
			f.store_string("# roll_regimes.gd: body-axis Clbeta, Cnbeta about the CG per rad, 25 m/s, beta +/-1 deg\n")
			f.store_string("\n".join(lines) + "\n")
			f.close()
			print("wrote ", out)
	quit(0)


## {alpha_deg: per-rad value} from a digitized FASER CSV (column `column`).
static func _csv(path: String, column: int) -> Dictionary:
	var text := FileAccess.get_file_as_string(ProjectSettings.globalize_path(path))
	var table := {}
	for line in text.split("\n"):
		if line.is_empty() or line.begins_with("#") or line.begins_with("alpha"):
			continue
		var parts := line.split(",")
		table[float(parts[0])] = float(parts[column])
	return table


static func _state(alpha: float, beta: float) -> PackedFloat64Array:
	var v := M.v3(SPEED * cos(alpha) * cos(beta), SPEED * sin(beta), SPEED * sin(alpha) * cos(beta))
	return RB.make_state(M.v3(0, 0, -300), v, M.q_identity(), M.v3(0, 0, 0))


## [oracle, local, production] Clβ and Cnβ (body axes, about the CG, per rad) and the blend weight at β = 0.
static func _derivatives(model: Dictionary, alpha: float) -> Dictionary:
	var db := deg_to_rad(1.0)
	var qsb: float = 0.5 * RHO * SPEED * SPEED * float(model.reference.S) * float(model.reference.b)
	var plus := _three(model, _state(alpha, db))
	var minus := _three(model, _state(alpha, -db))
	var clb := PackedFloat64Array()
	var cnb := PackedFloat64Array()
	for i in 3:
		clb.append((plus[i][3] - minus[i][3]) / (2.0 * db * qsb))
		cnb.append((plus[i][5] - minus[i][5]) / (2.0 * db * qsb))
	var s0 := _state(alpha, 0.0)
	return {clb = clb, cnb = cnb, blend = Aero.local_flow_weight(s0, Air.compute(s0, M.v3(0, 0, 0)), ZERO, model)}


## Rolling moment per rad of antisymmetric strip incidence (right wing up), the local law's own lifting-line response.
## A dihedral Γ gives each panel Δα = ±β·sinΓ, so Clβ from geometric dihedral is this value times Γ (rad).
static func _dihedral_response(model: Dictionary) -> float:
	var twisted: Dictionary = model.duplicate(true)
	var ys: PackedFloat64Array = model.envelope.station_ys
	var delta := deg_to_rad(0.5)
	var base_incidence: PackedFloat64Array = model.surfaces.get("station_incidence", PackedFloat64Array())
	var incidence := PackedFloat64Array()
	for i in ys.size():
		incidence.append((0.0 if base_incidence.is_empty() else base_incidence[i]) + (delta if ys[i] > 0.0 else -delta))
	twisted.surfaces.station_incidence = incidence
	var s := _state(deg_to_rad(2.0), 0.0)
	var air := Air.compute(s, M.v3(0, 0, 0))
	var qsb: float = 0.5 * RHO * SPEED * SPEED * float(model.reference.S) * float(model.reference.b)
	return (Aero._local_loads(s, air, ZERO, twisted, RHO)[3] - Aero._local_loads(s, air, ZERO, model, RHO)[3]) / (qsb * delta)


static func _three(model: Dictionary, s: PackedFloat64Array) -> Array:
	var air := Air.compute(s, M.v3(0, 0, 0))
	return [Aero._global_loads(s, air, ZERO, model, RHO), Aero._local_loads(s, air, ZERO, model, RHO),
		Aero.loads(s, air, ZERO, model, RHO)]
