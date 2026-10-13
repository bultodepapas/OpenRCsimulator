# Elevator investigation, script 1: static pitch derivatives of the oracle vs the local regime, trims, blend
# weights, inertia and gyroscopic coupling for the four aircraft. Read-only: nothing in app/ is modified.
# Run: $(app/get-godot.sh) --headless --path app --script "$PWD/research/flight-dynamics/elevator-repair/elev_static.gd" (repo root)
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const Trim := preload("res://physics/trim.gd")
const FlightModes := preload("res://physics/flight_modes.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Propulsion := preload("res://physics/propulsion.gd")

const AIRCRAFT := {
	"ugly": "res://data/aircraft/jensen_ugly_stik_60.json",
	"extra": "res://data/aircraft/gp_extra_300s_60.json",
	"p51": "res://data/aircraft/p51d_mustang_120.json",
	"avanti": "res://data/aircraft/sebart_avanti_s_a200.json",
}
const RHO := 1.225
const G := 9.80665


func _initialize() -> void:
	for name in AIRCRAFT:
		_analyze(name, AIRCRAFT[name])
	quit(0)


func _state(V: float, alpha: float, q: float) -> PackedFloat64Array:
	return PackedFloat64Array([0, 0, -100, V * cos(alpha), 0, V * sin(alpha), 1, 0, 0, 0, 0, q, 0])


## which: "oracle" (attached empirical model, settled downwash), "local" (strip wing + local tails), "blend" (production).
func _loads(model: Dictionary, V: float, alpha: float, q: float, de: float, which: String) -> PackedFloat64Array:
	var s := _state(V, alpha, q)
	var air := Air.compute(s, PackedFloat64Array([0, 0, 0]), RHO)
	var d := { elevator = de, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0 }
	match which:
		"oracle":
			return Aero._global_loads(s, air, d, model, RHO)
		"local":
			return Aero._local_loads(s, air, d, model, RHO)
	return Aero.loads(s, air, d, model, RHO)


func _blend(model: Dictionary, V: float, alpha: float, q: float, de: float) -> float:
	var s := _state(V, alpha, q)
	var air := Air.compute(s, PackedFloat64Array([0, 0, 0]), RHO)
	var d := { elevator = de, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0 }
	return Aero.local_flow_weight(s, air, d, model)


func _cl(l: PackedFloat64Array, alpha: float, qbar: float, S: float) -> float:
	return (l[0] * sin(alpha) - l[2] * cos(alpha)) / (qbar * S)


## Nondimensional pitch derivatives by central differences at (V, alpha, de), rates zero.
func _derivs(model: Dictionary, V: float, alpha: float, de: float, which: String) -> Dictionary:
	var S: float = model.reference.S
	var c: float = model.reference.c
	var qbar := 0.5 * RHO * V * V
	var ha := deg_to_rad(0.25)
	var hq := 0.02
	var l0 := _loads(model, V, alpha, 0.0, de, which)
	var ap := _loads(model, V, alpha + ha, 0.0, de, which)
	var am := _loads(model, V, alpha - ha, 0.0, de, which)
	var ep := _loads(model, V, alpha, 0.0, de + ha, which)
	var em := _loads(model, V, alpha, 0.0, de - ha, which)
	var qp := _loads(model, V, alpha, hq, de, which)
	var qm := _loads(model, V, alpha, -hq, de, which)
	var cm := func(l: PackedFloat64Array) -> float: return l[4] / (qbar * S * c)
	return {
		Cm = cm.call(l0), CL = _cl(l0, alpha, qbar, S),
		Cma = (cm.call(ap) - cm.call(am)) / (2.0 * ha),
		CLa = (_cl(ap, alpha + ha, qbar, S) - _cl(am, alpha - ha, qbar, S)) / (2.0 * ha),
		Cmde = (cm.call(ep) - cm.call(em)) / (2.0 * ha),
		CLde = (_cl(ep, alpha, qbar, S) - _cl(em, alpha, qbar, S)) / (2.0 * ha),
		Cmq = (cm.call(qp) - cm.call(qm)) / (2.0 * hq) / (c / (2.0 * V)),
		CLq = (_cl(qp, alpha, qbar, S) - _cl(qm, alpha, qbar, S)) / (2.0 * hq) / (c / (2.0 * V)),
		Cmz = l0[4],
	}


## Classical two-degree-of-freedom short-period approximation from the derivatives (Cmadot optional).
func _short_period(model: Dictionary, V: float, d: Dictionary, cmadot := 0.0) -> Dictionary:
	var S: float = model.reference.S
	var c: float = model.reference.c
	var m: float = model.mass_kg
	var jyy: float = model.inertia[1]
	var qbar := 0.5 * RHO * V * V
	var zw: float = -qbar * S * d.CLa / (m * V)
	var mw: float = qbar * S * c * d.Cma / (jyy * V)
	var mq: float = qbar * S * c * c * d.Cmq / (2.0 * V * jyy)
	var mwd: float = qbar * S * c * c * cmadot / (2.0 * V * jyy) / V # per (m/s per s)
	var wn2: float = zw * mq - V * mw
	var two_zeta_wn: float = -(zw + mq + V * mwd)
	var wn := sqrt(maxf(wn2, 0.0))
	return { wn = wn, f_hz = wn / TAU, zeta = two_zeta_wn / (2.0 * wn) if wn > 0.0 else NAN,
		zw = zw, mw = mw, mq = mq, mq_per_s = mq, alpha_per_de = -d.Cmde / d.Cma }


func _analyze(name: String, path: String) -> void:
	var loaded := AD.load_file(path)
	if not loaded.ok:
		print("## %s: load failed: %s" % [name, loaded.errors])
		return
	var model: Dictionary = loaded.model
	var S: float = model.reference.S
	var b: float = model.reference.b
	var c: float = model.reference.c
	var cg: PackedFloat64Array = model.cg_le
	var arp: PackedFloat64Array = model.reference.arp_le
	var tail: Dictionary = model.surfaces.horizontal
	var j: PackedFloat64Array = model.inertia
	var V: float = model.start_speed
	print("\n## %s (%s)" % [name, model.id])
	print("mass %.3f kg; cg_le [%.4f %.4f %.4f]; arp_le [%.4f %.4f %.4f]; S %.4f b %.3f c %.4f; CG aft of ARP %.1f %% c, above ARP %.1f %% c" % [
		model.mass_kg, cg[0], cg[1], cg[2], arp[0], arp[1], arp[2], S, b, c, 100.0 * (cg[0] - arp[0]) / c, 100.0 * (cg[2] - arp[2]) / c])
	print("inertia Jxx %.4f Jyy %.4f Jzz %.4f Jxy %.5f Jxz %.5f Jyz %.5f kg·m2; k_y/c %.2f; pitch-rate-squared roll moment Jyz %.5f N·m per (rad/s)^2" % [
		j[0], j[1], j[2], j[3], j[4], j[5], sqrt(j[1] / model.mass_kg) / c, j[5]])
	var l_t: float = float(tail.position[0]) - cg[0]
	var vh: float = float(tail.area) / S * l_t / c
	print("tail: S_t %.4f m2 (%.1f %% S), l_t %.4f m from CG (%.2f c), V_H %.3f, lift_slope %.3f, control_effectiveness %.3f, incidence %.2f°, downwash_gradient %s, free_slope %s, elevator_tau %s" % [
		tail.area, 100.0 * float(tail.area) / S, l_t, l_t / c, vh, tail.lift_slope, tail.control_effectiveness, rad_to_deg(tail.incidence),
		str(tail.get("downwash_gradient", "none")), str(tail.get("free_slope", "none")), str(tail.get("elevator_tau", "none"))])
	var a_free: float = float(tail.get("free_slope", tail.lift_slope))
	print("closed form tail-only: Cma_t %.3f, Cmq_t(lift_slope) %.3f, Cmq_t(free or same) %.3f, Cmde_t %.3f, CLde_t %.3f; oracle data: Cma %.3f Cmq %.3f Cmde %.3f CLde %.3f CLadot(ref) %s" % [
		-float(tail.area) / S * l_t / c * float(tail.lift_slope),
		-2.0 * float(tail.area) / S * pow(l_t / c, 2) * float(tail.lift_slope),
		-2.0 * float(tail.area) / S * pow(l_t / c, 2) * a_free,
		-float(tail.area) / S * l_t / c * float(tail.lift_slope) * float(tail.control_effectiveness),
		float(tail.area) / S * float(tail.lift_slope) * float(tail.control_effectiveness),
		model.aero.Cma, model.aero.Cmq, model.aero.Cmde, model.aero.CLde, str(model.aero.get("CLadot", "none"))])
	var throws: Dictionary = model.controls.throw_deg
	print("throws: elevator %.2f° aileron %.2f° rudder %.2f°; servo_rate %.2f throws/s; τ·δ_max = %.1f° of tail angle (limits: attached %.0f°, tail local %.0f°, tail stall end %.0f°)" % [
		throws.elevator, throws.aileron, throws.rudder, model.controls.servo_rate,
		float(tail.get("elevator_tau", tail.control_effectiveness)) * throws.elevator,
		rad_to_deg(model.surfaces.attached_limit), rad_to_deg(model.surfaces.tail_local_limit), rad_to_deg(model.surfaces.tail_stall_end)])
	print("envelope: a1 %.2f° a2 %.2f° n1 %.2f° n2 %.2f°, CL_max %.2f" % [rad_to_deg(model.envelope.a1), rad_to_deg(model.envelope.a2), rad_to_deg(model.envelope.n1), rad_to_deg(model.envelope.n2), model.envelope.CL_max])

	# Trim at the start speed and at 1.4× it.
	for speed in [V, 1.4 * V]:
		var t := Trim.solve("level", speed, model, G, model.controls.throw_rad)
		if not t.ok:
			print("trim %.1f m/s failed: %s" % [speed, t.message])
			continue
		var blend_trim := _blend(model, speed, t.alpha, 0.0, t.elevator)
		var qbar: float = 0.5 * RHO * speed * speed
		print("trim %.1f m/s: α %.2f°, elevator %.2f° (data, +TE down) = pitch command %.3f, throttle %.3f, rpm %.0f, thrust %.1f N; local blend weight at trim %.3f" % [
			speed, rad_to_deg(t.alpha), rad_to_deg(t.elevator), t.pitch_command, t.throttle, t.rpm, t.thrust, blend_trim])
		var h: PackedFloat64Array = Dynamics.rotor_momentum(model, t.rpm)
		var cnb: float = model.aero.Cnb
		print("  rotor momentum %.4f N·m·s: yaw moment per rad/s of pitch rate %.3f N·m; aero yaw stiffness qbar·S·b·Cnβ %.2f N·m/rad → steady β per rad/s of q: %.2f°" % [
			h[0], h[0], qbar * S * b * cnb, rad_to_deg(h[0] / (qbar * S * b * cnb))])
		for which in ["oracle", "local", "blend"]:
			var d := _derivs(model, speed, t.alpha, t.elevator, which)
			var sp := _short_period(model, speed, d)
			print("  %-6s at trim: CL %.3f Cm %.4f | CLa %.3f Cma %.3f Cmq %.3f CLq %.3f Cmde %.3f CLde %.3f | SP approx %.2f Hz ζ %.2f | α per δe %.2f" % [
				which, d.CL, d.Cm, d.CLa, d.Cma, d.Cmq, d.CLq, d.Cmde, d.CLde, sp.f_hz, sp.zeta, sp.alpha_per_de])
		var fm := FlightModes.analyze(model, speed)
		if fm.ok:
			print("  FlightModes (full Jacobian at trim): short period %.2f Hz ζ %.2f, phugoid %.3f Hz ζ %.2f, lag root %s" % [
				fm.short_period.f_hz, fm.short_period.zeta, fm.phugoid.f_hz, fm.phugoid.zeta, str(fm.downwash_lag_root)])
		else:
			print("  FlightModes: %s" % fm.message)
		# Pitch derivatives in the local regime over α (elevator neutral) to show the regime dependence.
		print("  | α° | blend | Cma_or | Cma_loc | Cmq_or | Cmq_loc | CLa_or | CLa_loc | Cmde_or | Cmde_loc |")
		for deg in [0.0, 4.0, 8.0, 10.0, 12.0]:
			var al := deg_to_rad(deg)
			var o := _derivs(model, speed, al, 0.0, "oracle")
			var lo := _derivs(model, speed, al, 0.0, "local")
			print("  | %.0f | %.2f | %.3f | %.3f | %.2f | %.2f | %.2f | %.2f | %.3f | %.3f |" % [deg, _blend(model, speed, al, 0.0, 0.0), o.Cma, lo.Cma, o.Cmq, lo.Cmq, o.CLa, lo.CLa, o.Cmde, lo.Cmde])
		# Elevator sweep at the trim α: blended pitching moment, regime weight, instantaneous pitch acceleration.
		print("  elevator sweep at trim α %.2f° (δ data convention, + TE down; pilot nose-up = negative δ):" % rad_to_deg(t.alpha))
		print("  | δe° | blend | Cm_or | Cm_loc | Cm_blend | q̇ blend °/s² | tail angle° |")
		var full: float = throws.elevator
		for frac in [-1.0, -0.75, -0.5, -0.25, 0.0, 0.25, 0.5, 0.75, 1.0]:
			var de: float = deg_to_rad(frac * full)
			var o := _loads(model, speed, t.alpha, 0.0, de, "oracle")
			var lo := _loads(model, speed, t.alpha, 0.0, de, "local")
			var bl := _loads(model, speed, t.alpha, 0.0, de, "blend")
			var tail_angle: float = t.alpha + float(tail.get("elevator_tau", tail.control_effectiveness)) * de + float(tail.get("free_incidence", tail.incidence))
			if tail.has("downwash_per_cl"):
				tail_angle -= float(tail.downwash_per_cl) * Aero.wing_lift_coefficient(_state(speed, t.alpha, 0.0), Air.compute(_state(speed, t.alpha, 0.0), PackedFloat64Array([0, 0, 0]), RHO), { elevator = de, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0 }, model)
			print("  | %+.1f | %.2f | %+.3f | %+.3f | %+.3f | %+.0f | %+.1f |" % [frac * full, _blend(model, speed, t.alpha, 0.0, de), o[4] / (qbar * S * c), lo[4] / (qbar * S * c), bl[4] / (qbar * S * c), rad_to_deg(bl[4] / j[1]), rad_to_deg(tail_angle)])
