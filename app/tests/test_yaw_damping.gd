# D11f: yaw damping through the oracle/local transition. The local fin's velocity, force and moment arm are consistent:
# its yaw-rate damping equals the invariant −2·(l_v/b)·Cnβ_fin of the same fin data (the data's Cnβ is derived from it
# and checked by the loader). The wing's physical yaw damping is profile drag, −CD0/3·(1 − 1/(4n²)) for n equal strips per
# side (independent Weissinger reference with Kutta–Joukowski forces: the lift-induced part is +0.0004·CL²,
# research/aero/d11f/wing_yaw_damping.py). Acceptance: across α 0–11° the local Cnr is within 7 % of that
# Stik-consistent value (fin invariant + wing profile). The borrowed oracle Cnr (UltraStick 25e) is reported, not
# accepted against: it is inconsistent with the oracle's own fin-derived Cnβ (a DATA decision, see the D11f report).
# Run: godot --headless --path . --script res://tests/test_yaw_damping.gd
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")

const PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const V := 15.0
const RHO := 1.225

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		_failures += 1


func _initialize() -> void:
	var model: Dictionary = AD.load_file(PATH).model
	var no_fin := model.duplicate(true)
	no_fin.surfaces.vertical.area = 0.0
	var S: float = model.reference.S
	var b: float = model.reference.b
	var fin: Dictionary = model.surfaces.vertical
	var arm: float = float(fin.position[0]) - float(model.cg_le[0])
	var cnb_fin: float = float(fin.lift_slope) * float(fin.area) / S * arm / b
	var fin_invariant := -2.0 * arm / b * cnb_fin
	var n: int = model.envelope.station_ys.size() / 2
	var wing_profile: float = -float(model.aero.CD0) / 3.0 * (1.0 - 1.0 / (4.0 * n * n))
	var consistent := fin_invariant + wing_profile
	print("info Stik-consistent Cnr: fin −2(l_v/b)·Cnβ_fin %.4f + wing profile %.4f = %.4f; borrowed oracle Cnr %.4f"
		% [fin_invariant, wing_profile, consistent, model.aero.Cnr])
	var worst_fin := 0.0
	var worst_total := 0.0
	var worst_cnb := 0.0
	for deg in [0.0, 2.0, 4.0, 6.0, 8.0, 10.0, 11.0]:
		var a := deg_to_rad(deg)
		var total := _cnr(model, a)
		var fin_part := total - _cnr(no_fin, a)
		var cnb := _cnb(model, a)
		print("info α %4.1f: local Cnr %.4f (fin %.4f, rest %.4f), local Cnβ %.4f, ×%.2f of the oracle Cnr" % [deg, total, fin_part, total - fin_part,
			cnb, total / float(model.aero.Cnr)])
		worst_fin = maxf(worst_fin, absf(fin_part / fin_invariant - 1.0))
		worst_total = maxf(worst_total, absf(total / consistent - 1.0))
		worst_cnb = maxf(worst_cnb, absf(cnb / float(model.aero.Cnb) - 1.0))
	_check("fin: local yaw-rate damping = −2·(l_v/b)·Cnβ_fin = %.4f within 2 %% at α 0–11° (consistent velocity, force, arm)" % fin_invariant,
		worst_fin < 0.02, "worst %.2f %%" % (100.0 * worst_fin))
	_check("local Cnβ within 3 %% of the data's fin-derived Cnβ %.4f at α 0–11°" % model.aero.Cnb, worst_cnb < 0.03,
		"worst %.2f %%" % (100.0 * worst_cnb))
	_check("local Cnr within 7 %% of the Stik-consistent value %.4f at α 0–11° (wing polar per strip: see the D11f report)" % consistent,
		worst_total < 0.07, "worst %.2f %%" % (100.0 * worst_total))
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _cnr(model: Dictionary, a: float) -> float:
	var h := 0.05
	return (_loads(model, a, 0.0, h)[5] - _loads(model, a, 0.0, -h)[5]) / (2.0 * h) \
		/ (0.5 * RHO * V * V * float(model.reference.S) * pow(float(model.reference.b), 2) / (2.0 * V))


func _cnb(model: Dictionary, a: float) -> float:
	var db := 0.01
	return (_loads(model, a, db, 0.0)[5] - _loads(model, a, -db, 0.0)[5]) / (2.0 * db) \
		/ (0.5 * RHO * V * V * float(model.reference.S) * float(model.reference.b))


func _loads(model: Dictionary, a: float, beta: float, r: float) -> PackedFloat64Array:
	var s := PackedFloat64Array([0, 0, -100, V * cos(a) * cos(beta), V * sin(beta), V * sin(a) * cos(beta), 1, 0, 0, 0, 0, 0, r])
	var d := { elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0 }
	return Aero._local_loads(s, Air.compute(s, PackedFloat64Array([0, 0, 0]), RHO), d, model, RHO)
