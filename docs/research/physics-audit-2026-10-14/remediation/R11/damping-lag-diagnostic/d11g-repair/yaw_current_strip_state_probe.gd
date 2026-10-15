extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")

const AIRCRAFT := "res://data/aircraft/jensen_ugly_stik_60.json"
const SPEED := 15.0
const RHO := 1.225


func _initialize() -> void:
	var loaded: Dictionary = AD.load_file(AIRCRAFT)
	if not bool(loaded.get("ok", false)):
		push_error("aircraft load failed: %s" % str(loaded.get("errors", [])))
		quit(2)
		return
	var model: Dictionary = loaded.model
	var controls := {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}
	print("aircraft=%s law=%s input=%s" % [model.id, Aero.LOADS_LAW, JSON.stringify(loaded.input_identity)])
	print("S=%.9f b=%.9f AR=%.9f CL0=%.9f CLa=%.9f strip_slope=%.9f CD0=%.9f k_induced=%.9f CL_minD=%.9f" % [
		model.reference.S, model.reference.b, pow(model.reference.b, 2) / model.reference.S,
		model.aero.CL0, model.aero.CLa, model.envelope.strip_slope,
		model.aero.CD0, model.aero.k_induced, model.aero.CL_minD])
	print("columns=alpha_deg,mean_CL,mean_VpCL_mps,mean_CD,mean_effective_alpha_deg,strip_CL,strip_CL0,strip_alpha_effective_deg")
	for deg in [0.0, 10.0, 11.0]:
		var alpha := deg_to_rad(deg)
		var state := PackedFloat64Array([0, 0, -100, SPEED * cos(alpha), 0.0, SPEED * sin(alpha), 1, 0, 0, 0, 0, 0, 0])
		var air: Dictionary = Air.compute(state, PackedFloat64Array([0.0, 0.0, 0.0]), RHO)
		var rows: Array = Aero.wing_strip_loads(state, air, controls, model, RHO)
		var mean_cl := 0.0
		var mean_vpcl := 0.0
		var mean_cd := 0.0
		var mean_alpha_effective := 0.0
		var cls := PackedFloat64Array()
		var cl0s: PackedFloat64Array = model.envelope.strip_cl0
		var alpha_effectives := PackedFloat64Array()
		for i in rows.size():
			var row: Dictionary = rows[i]
			mean_cl += float(row.cl) / rows.size()
			mean_vpcl += float(row.lift_velocity_mps) / rows.size()
			mean_cd += float(row.cd) / rows.size()
			mean_alpha_effective += float(row.alpha_effective_rad) / rows.size()
			cls.append(float(row.cl))
			alpha_effectives.append(rad_to_deg(float(row.alpha_effective_rad)))
		print("%.1f,%.12f,%.12f,%.12f,%.12f,%s,%s,%s" % [
			deg, mean_cl, mean_vpcl, mean_cd, rad_to_deg(mean_alpha_effective),
			JSON.stringify(cls), JSON.stringify(cl0s), JSON.stringify(alpha_effectives)])
	quit(0)
