# WINGLOSS probe (disposable app copy only; needs strip_mask_probe.patch applied to physics/aero.gd).
# Question: if a wing panel is "removed" by masking strips in the existing law, what do Aero.loads() and the local
# strip law return? Shows (1) the oracle blend at small angles ignores the mask, (2) the masked local law's rolling
# moment and lift centroid, (3) the strip resolution (3 per side).
extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

const RHO := 1.225


func _initialize() -> void:
	for file in ["jensen_ugly_stik_60", "gp_extra_300s_60", "p51d_mustang_120", "turbo_lumber_evolution"]:
		var r: Dictionary = AircraftData.load_file("res://data/aircraft/%s.json" % file)
		if not r.get("ok", false):
			print(file, " load failed: ", r.get("errors"))
			continue
		var model: Dictionary = r.model
		print("\n== %s  stations (m, left tip … right tip) %s" % [file, str(model.envelope.station_ys)])
		var V := 20.0
		for alpha_deg in [2.0, 6.0]:
			var a := deg_to_rad(alpha_deg)
			var s := RB.make_state(M.v3(0.0, 0.0, -100.0), M.v3(V * cos(a), 0.0, V * sin(a)), M.quat(1.0, 0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0))
			var air: Dictionary = Air.compute(s, M.v3(0.0, 0.0, 0.0), RHO)
			var d := {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}
			var cases := {"intact": PackedFloat64Array([1, 1, 1, 1, 1, 1]), "left outer 1/3": PackedFloat64Array([0, 1, 1, 1, 1, 1]),
				"left outer 2/3": PackedFloat64Array([0, 0, 1, 1, 1, 1]), "left panel": PackedFloat64Array([0, 0, 0, 1, 1, 1])}
			for name in cases:
				var m2: Dictionary = model.duplicate(true)
				if name != "intact":
					m2["strip_mask"] = cases[name]
				var blend := Aero.local_flow_weight(s, air, d, m2)
				var full := Aero.loads(s, air, d, m2, RHO)
				var local := Aero._local_loads(s, air, d, m2, RHO)
				var wing_only := Aero._local_loads(s, air, d, m2, RHO, NAN, null, PackedFloat64Array(), PackedFloat64Array(), false)
				# lateral lift centroid of the local loads: Mx = y*Fz  ->  y = Mx/Fz (Fz < 0 for lift)
				var tail_only := Aero._local_loads(s, air, d, m2, RHO, NAN, null, PackedFloat64Array(), PackedFloat64Array(), false)
				var m_notail: Dictionary = m2.duplicate(true)
				var yc: float = local[3] / local[2] if local[2] != 0.0 else NAN
				var rows: Array = Aero.wing_strip_loads(s, air, d, m2, RHO)
				var wing_fz := 0.0
				var wing_mx := 0.0
				for row in rows:
					var f: PackedFloat64Array = row.force_body_n
					wing_fz += f[2]
					wing_mx += float(row.y_m) * f[2]
				print("  α %4.1f° %-15s blend %.3f | loads(): Fz %8.2f N  Mx %+8.3f N·m | local: Fz %8.2f N  Mx %+8.3f N·m | wing strips: Fz %8.2f N  y_c %+.3f m" % [
					alpha_deg, name, blend, full[2], full[3], local[2], local[3], wing_fz, wing_mx / wing_fz if wing_fz != 0.0 else NAN])
	quit()
