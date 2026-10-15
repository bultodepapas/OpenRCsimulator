# P51-20: P-51 ground-effect increments on the runtime Aero.loads at fixed alpha, as the CG descends to the
# main-wheel contact height (level attitude). Approach trim at 1.3 Vs. Research only.
# Run: <godot> --headless --path app --audio-driver Dummy --script <abs path>/ge_probe.gd [-- --data=res://...]
extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const Trim := preload("res://physics/trim.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const GroundEffect := preload("res://physics/ground_effect.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

const DATA := "res://data/aircraft/p51d_mustang_120.json"
const G := 9.80665
const RHO := 1.225
const ZERO_WIND := [0.0, 0.0, 0.0]


func _wind_axes(loads: PackedFloat64Array, alpha: float) -> Dictionary:
	var ca := M.cos_(alpha)
	var sa := M.sin_(alpha)
	return {L = -loads[2] * ca + loads[0] * sa, D = -loads[0] * ca - loads[2] * sa, My = loads[4]}


func _state_at(s0: PackedFloat64Array, h: float, alpha: float, alpha0: float) -> PackedFloat64Array:
	var V := M.norm(M.v3(s0[RB.VEL], s0[RB.VEL + 1], s0[RB.VEL + 2]))
	var euler := M.q_to_euler(M.quat(s0[RB.ATT], s0[RB.ATT + 1], s0[RB.ATT + 2], s0[RB.ATT + 3]))
	var s := s0.duplicate()
	s[RB.POS + 2] = -h
	s[RB.VEL] = V * M.cos_(alpha)
	s[RB.VEL + 1] = 0.0
	s[RB.VEL + 2] = V * M.sin_(alpha)
	var q := M.q_from_euler(euler[0], euler[1] - alpha0 + alpha, 0.0)
	for k in 4:
		s[RB.ATT + k] = q[k]
	return s


func _initialize() -> void:
	var path := DATA
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--data="):
			path = arg.trim_prefix("--data=")
	var loaded: Dictionary = AircraftData.load_file(path)
	if not loaded.get("ok", false):
		printerr("load failed: ", loaded)
		quit(1)
		return
	var model: Dictionary = loaded.model
	var throws := {elevator = model.controls.throw_rad.elevator, aileron = model.controls.throw_rad.aileron, rudder = model.controls.throw_rad.rudder}
	var vs := sqrt(2.0 * model.mass_kg * G / (RHO * model.reference.S * model.envelope.CL_max))
	var trim: Dictionary = Trim.solve("level", 1.3 * vs, model, G, throws, RHO)
	if not trim.ok:
		printerr("trim failed: ", trim.message)
		quit(1)
		return
	var d := {elevator = trim.elevator, aileron_right = trim.aileron, aileron_left = -trim.aileron, rudder = trim.rudder}
	var s0: PackedFloat64Array = trim.state
	var air: Dictionary = Air.compute(s0, ZERO_WIND, RHO)
	var free := _wind_axes(Aero.loads(s0, air, d, model, RHO), air.alpha)
	var b: float = model.reference.b
	var qSc: float = air.qbar * model.reference.S * model.reference.c
	var arp_below_cg: float = -(model.reference.arp_le[2] - model.cg_le[2])
	var wheel_cg: float = model.landing_gear.contacts[0].position[2] # body FRD about the CG: CG height on the uncompressed main wheels
	print("module %s, V %.2f m/s (1.3 Vs), alpha %.2f deg, CL %.3f, wheel CG height %.3f m (ARP x %.3f)" % [GroundEffect.enabled(model), air.V,
		rad_to_deg(air.alpha), free.L / (air.qbar * model.reference.S), wheel_cg, (wheel_cg - arp_below_cg) / b])
	for h: float in [6.0, 4.0, 3.0, 2.0, 1.5, 1.0, 0.75, 0.6, 0.5, wheel_cg]:
		var s := s0.duplicate()
		s[RB.POS + 2] = -h
		var f := GroundEffect.factors(s, model, 0.0)
		var w := _wind_axes(Aero.loads(s, air, d, model, RHO, NAN, 0.0), air.alpha)
		var dcm: float = (w.My - free.My) / qSc
		print("CG %.3f m  x %.3f  sigma_mean %.4f  sigma_tail %.4f  L/Linf %.4f  D/Dinf %.4f  dCm %+.4f  = %+.2f deg elevator (+ TE down)" % [h,
			(h - arp_below_cg) / b, f[f.size() - 2] if not f.is_empty() else 1.0, f[f.size() - 1] if not f.is_empty() else 1.0,
			w.L / free.L, w.D / free.D, dcm, rad_to_deg(-dcm / float(model.aero.Cmde))])
	# Same lift at wheel height: lower alpha by bisection until L equals the free-air lift.
	var lo: float = air.alpha - deg_to_rad(6.0)
	var hi: float = air.alpha
	var same := {}
	for i in 80:
		var alpha := 0.5 * (lo + hi)
		var s := _state_at(s0, wheel_cg, alpha, air.alpha)
		var a2 := Air.compute(s, ZERO_WIND, RHO)
		var w := _wind_axes(Aero.loads(s, a2, d, model, RHO, NAN, 0.0), a2.alpha)
		if w.L > free.L:
			hi = alpha
		else:
			lo = alpha
		same = {L = w.L, D = w.D, alpha = alpha}
	print("same lift at the wheels: alpha %.2f -> %.2f deg, D/Dinf %.4f" % [rad_to_deg(air.alpha), rad_to_deg(same.alpha), same.D / free.D])
	quit(0)
