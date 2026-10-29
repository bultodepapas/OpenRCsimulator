# D11i: the two aerodynamic regimes of every catalog aircraft must describe one airplane. At the start-speed level trim
# the attached empirical oracle (Aero._global_loads) and the local strip/tail model (Aero._local_loads) are compared by
# central differences: pitch stiffness Cmα, pitch damping Cmq, elevator power Cmδe, lift slope CLα and the static
# pitching moment itself; Cmq is also compared at α 0, 4 and 8° with neutral elevator. Any input can move the flight
# between the regimes (the blend follows wing and tail angles, elevator included), so a mismatch is a change of
# dynamics the pilot did not command. Investigation and bands: docs/research/flight-dynamics/elevator-repair-2026-10-13.md.
# CLq is reported, not checked: the strips sit on the aerodynamic reference line and cannot carry the oracle's wing term.
# Run: godot --headless --path . --script res://tests/test_regime_consistency.gd
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const Trim := preload("res://physics/trim.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")

const RHO := 1.225
const G := 9.80665
## Relative bands on the oracle's value (Cmq, CLα, Cmδe) and absolute bands (Cmα in 1/rad, static Cm).
const CMQ_REL := 0.12
const CLA_REL := 0.10
const CMDE_REL := 0.08
const CMA_ABS := 0.20 # the oracle's borrowed/derived Cmα carries fuselage and wing-body terms the strips do not model
const CM_ABS := 0.012 # about half a degree of elevator on these aircraft
## Documented exceptions (aircraft id → { derivative: band }). The Stik's oracle Cmδe is the borrowed UltraStick 25e value
## (−0.8488) while its local tail, calibrated as Cmδe/Cmα of the whole airplane, gives −0.99 about the plan CG: a 16 %
## elevator-power step between regimes that only a Stik data revision (its JSON is authored, not generated) can close.
## The glow variants fly the same Stik airframe and inherit the same oracle. FUEL-05a/f: the Stik family now balances
## at the plan CG with the tank empty and flies its fuel ahead of it (base half tank 11.5 mm, glow full tanks 16–24 mm).
## The longer local tail arm gives −1.01…−1.03 while the borrowed constant barely moves: a 20–22 % step, hence 0.25.
## X8-04: the X8's oracle Cmq is the 2026 flight identification (−0.80); its swept strips predict −0.87…−0.91 from
## geometry (α 0–8°), inside the published spread (2024–25 flight −1.6, XFLR5 −1.30, CFD −2.0) but 12.3 % off at α 8°.
const EXCEPTIONS := {
	"moonrunner-x99": { Cmq = 0.15 },
	"jensen-das-ugly-stik-60": { Cmde = 0.25 },
	"stik-glow-55ax-2t": { Cmde = 0.25 },
	"stik-glow-fs64v-4t": { Cmde = 0.25 },
	"stik-glow-61fx-2t": { Cmde = 0.25 },
}

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		_failures += 1


func _initialize() -> void:
	for entry in Catalog.airplane_flyable_entries():
		if String(entry.data).is_empty():
			continue
		var loaded: Dictionary = AD.load_file(entry.data)
		_check("%s: aircraft data loads" % entry.id, loaded.ok, str(loaded.get("errors", [])))
		if loaded.ok:
			_aircraft(entry.id, loaded.model)
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _aircraft(id: String, model: Dictionary) -> void:
	var V: float = model.start_speed
	var t := Trim.solve("level", V, model, G, model.controls.throw_rad)
	_check("%s: level trim at %.0f m/s" % [id, V], t.ok, t.message)
	if not t.ok:
		return
	var bands: Dictionary = EXCEPTIONS.get(id, {})
	var o := _derivatives(model, V, t.alpha, t.elevator, "oracle")
	var l := _derivatives(model, V, t.alpha, t.elevator, "local")
	print("%s at the %.0f m/s trim (α %.2f°, δe %.2f°): oracle CLα %.3f Cmα %.3f Cmq %.2f CLq %.2f Cmδe %.3f Cm %.4f | local CLα %.3f Cmα %.3f Cmq %.2f CLq %.2f Cmδe %.3f Cm %.4f"
		% [id, V, rad_to_deg(t.alpha), rad_to_deg(t.elevator), o.CLa, o.Cma, o.Cmq, o.CLq, o.Cmde, o.Cm, l.CLa, l.Cma, l.Cmq, l.CLq, l.Cmde, l.Cm])
	var cmq_band: float = bands.get("Cmq", CMQ_REL)
	_check("%s: local Cmq %.2f within %.0f %% of the oracle's %.2f" % [id, l.Cmq, 100.0 * cmq_band, o.Cmq], _within_rel(l.Cmq, o.Cmq, cmq_band))
	_check("%s: local CLα %.3f within %.0f %% of the oracle's %.3f" % [id, l.CLa, 100.0 * CLA_REL, o.CLa], _within_rel(l.CLa, o.CLa, CLA_REL))
	var cmde_band: float = bands.get("Cmde", CMDE_REL)
	_check("%s: local Cmδe %.3f within %.0f %% of the oracle's %.3f" % [id, l.Cmde, 100.0 * cmde_band, o.Cmde], _within_rel(l.Cmde, o.Cmde, cmde_band))
	_check("%s: local Cmα %.3f within %.2f of the oracle's %.3f" % [id, l.Cma, CMA_ABS, o.Cma], absf(l.Cma - o.Cma) <= CMA_ABS)
	_check("%s: static Cm at the trim: local %.4f within %.3f of the oracle's %.4f (no trim step at the regime switch)" % [id, l.Cm, CM_ABS, o.Cm],
		absf(l.Cm - o.Cm) <= CM_ABS)
	for deg in [0.0, 4.0, 8.0]:
		var oa := _derivatives(model, V, deg_to_rad(deg), 0.0, "oracle")
		var la := _derivatives(model, V, deg_to_rad(deg), 0.0, "local")
		_check("%s: α %.0f°, neutral elevator: local Cmq %.2f within %.0f %% of the oracle's %.2f" % [id, deg, la.Cmq, 100.0 * cmq_band, oa.Cmq],
			_within_rel(la.Cmq, oa.Cmq, cmq_band))


func _within_rel(value: float, reference: float, band: float) -> bool:
	return absf(value - reference) <= band * absf(reference)


func _state(V: float, alpha: float, q: float) -> PackedFloat64Array:
	return PackedFloat64Array([0, 0, -100, V * cos(alpha), 0, V * sin(alpha), 1, 0, 0, 0, 0, q, 0])


func _loads(model: Dictionary, V: float, alpha: float, q: float, de: float, which: String) -> PackedFloat64Array:
	var s := _state(V, alpha, q)
	var air := Air.compute(s, PackedFloat64Array([0, 0, 0]), RHO)
	var d := { elevator = de, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0 }
	if which == "oracle":
		return Aero._global_loads(s, air, d, model, RHO)
	return Aero._local_loads(s, air, d, model, RHO)


func _cl(l: PackedFloat64Array, alpha: float, qbar: float, S: float) -> float:
	return (l[0] * sin(alpha) - l[2] * cos(alpha)) / (qbar * S)


## Nondimensional pitch derivatives by central differences at (V, α, δe), body rates zero except for the q probes.
func _derivatives(model: Dictionary, V: float, alpha: float, de: float, which: String) -> Dictionary:
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
		Cm = cm.call(l0),
		Cma = (cm.call(ap) - cm.call(am)) / (2.0 * ha),
		CLa = (_cl(ap, alpha + ha, qbar, S) - _cl(am, alpha - ha, qbar, S)) / (2.0 * ha),
		Cmde = (cm.call(ep) - cm.call(em)) / (2.0 * ha),
		Cmq = (cm.call(qp) - cm.call(qm)) / (2.0 * hq) / (c / (2.0 * V)),
		CLq = (_cl(qp, alpha, qbar, S) - _cl(qm, alpha, qbar, S)) / (2.0 * hq) / (c / (2.0 * V)),
	}
