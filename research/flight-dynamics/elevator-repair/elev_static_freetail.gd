# Elevator investigation, script 1b: the candidate repair's static effect. For the three generated aircraft the
# generator's own dε/dα is injected as aero.surfaces.horizontal.downwash_gradient (in memory), the loader derives the
# E0a2 free-tail law, and the oracle-vs-local pitch derivatives, blend weights and elevator sweeps are printed again.
# Run: $(app/get-godot.sh) --headless --path app --script "$PWD/research/flight-dynamics/elevator-repair/elev_static_freetail.gd" (repo root)
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const Trim := preload("res://physics/trim.gd")
const FlightModes := preload("res://physics/flight_modes.gd")
const RB := preload("res://physics/rigid_body.gd")

const AIRCRAFT := {
	"extra": ["res://data/aircraft/gp_extra_300s_60.json", 0.4734],
	"p51": ["res://data/aircraft/p51d_mustang_120.json", 0.4391],
	"avanti": ["res://data/aircraft/sebart_avanti_s_a200.json", 0.5088],
}
const RHO := 1.225
const G := 9.80665


func _initialize() -> void:
	for name in AIRCRAFT:
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AIRCRAFT[name][0]))
		raw.aero.surfaces.horizontal.downwash_gradient = { value = AIRCRAFT[name][1], unit = "1", kind = "estimated",
			source = "investigation variant: the generator's own d(eps)/d(alpha)" }
		var data: Dictionary = AD.validate_and_derive(raw)
		if not data.ok:
			print("## %s freetail: derive failed: %s" % [name, data.errors])
			continue
		_analyze(name, data.model)
	quit(0)


func _state(V: float, alpha: float, q: float) -> PackedFloat64Array:
	return PackedFloat64Array([0, 0, -100, V * cos(alpha), 0, V * sin(alpha), 1, 0, 0, 0, 0, q, 0])


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
	}


func _analyze(name: String, model: Dictionary) -> void:
	var S: float = model.reference.S
	var c: float = model.reference.c
	var tail: Dictionary = model.surfaces.horizontal
	var j: PackedFloat64Array = model.inertia
	var V: float = model.start_speed
	var throws: Dictionary = model.controls.throw_deg
	print("\n## %s + free tail law (dε/dα %.4f)" % [name, tail.downwash_gradient])
	print("free_slope %.3f (was lift_slope %.3f), elevator_tau %.3f (was %.3f), free_incidence %.2f°, downwash_per_cl %.4f, lag length %.3f m; τ·δ_max = %.1f° of tail angle" % [
		tail.free_slope, tail.lift_slope, tail.elevator_tau, tail.control_effectiveness, rad_to_deg(tail.free_incidence), tail.downwash_per_cl, tail.downwash_lag_length,
		float(tail.elevator_tau) * throws.elevator])
	var t := Trim.solve("level", V, model, G, model.controls.throw_rad)
	if not t.ok:
		print("trim failed: %s" % t.message)
		return
	var qbar: float = 0.5 * RHO * V * V
	print("trim %.1f m/s: α %.2f°, elevator %.2f°, throttle %.3f; blend at trim %.3f" % [V, rad_to_deg(t.alpha), rad_to_deg(t.elevator), t.throttle, _blend(model, V, t.alpha, 0.0, t.elevator)])
	for which in ["oracle", "local"]:
		var d := _derivs(model, V, t.alpha, t.elevator, which)
		print("  %-6s at trim: CL %.3f | CLa %.3f Cma %.3f Cmq %.3f CLq %.3f Cmde %.3f CLde %.3f" % [which, d.CL, d.CLa, d.Cma, d.Cmq, d.CLq, d.Cmde, d.CLde])
	var fm := FlightModes.analyze(model, V)
	if fm.ok:
		print("  FlightModes: short period %.2f Hz ζ %.2f, phugoid %.3f Hz ζ %.2f, lag root %.2f" % [fm.short_period.f_hz, fm.short_period.zeta, fm.phugoid.f_hz, fm.phugoid.zeta, fm.downwash_lag_root])
	else:
		print("  FlightModes: %s" % fm.message)
	print("  | α° | blend | Cma_or | Cma_loc | Cmq_or | Cmq_loc | CLa_or | CLa_loc | Cmde_or | Cmde_loc |")
	for deg in [0.0, 4.0, 8.0, 10.0]:
		var al := deg_to_rad(deg)
		var o := _derivs(model, V, al, 0.0, "oracle")
		var lo := _derivs(model, V, al, 0.0, "local")
		print("  | %.0f | %.2f | %.3f | %.3f | %.2f | %.2f | %.2f | %.2f | %.3f | %.3f |" % [deg, _blend(model, V, al, 0.0, 0.0), o.Cma, lo.Cma, o.Cmq, lo.Cmq, o.CLa, lo.CLa, o.Cmde, lo.Cmde])
	print("  elevator sweep at trim α (δ data convention):")
	print("  | δe° | blend | Cm_or | Cm_loc | Cm_blend | q̇ blend °/s² |")
	var full: float = throws.elevator
	for frac in [-1.0, -0.75, -0.5, -0.25, 0.0, 0.25, 0.5, 0.75, 1.0]:
		var de: float = deg_to_rad(frac * full)
		var o := _loads(model, V, t.alpha, 0.0, de, "oracle")
		var lo := _loads(model, V, t.alpha, 0.0, de, "local")
		var bl := _loads(model, V, t.alpha, 0.0, de, "blend")
		print("  | %+.1f | %.2f | %+.3f | %+.3f | %+.3f | %+.0f |" % [frac * full, _blend(model, V, t.alpha, 0.0, de), o[4] / (qbar * S * c), lo[4] / (qbar * S * c), bl[4] / (qbar * S * c), rad_to_deg(bl[4] / j[1])])
