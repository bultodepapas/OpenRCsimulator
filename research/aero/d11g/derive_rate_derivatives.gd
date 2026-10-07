# D11g generator: the Ugly Stik oracle's rate derivatives Cmq, CLq and Cnr, derived from the Stik's own verified local
# model (wing induced-flow map D11d, free tail slope E0a2a, fin and wing yaw damping D11f) at the 15 m/s level trim,
# about the CG, controls neutral, downwash settled (the lag's Cmα̇ is a separate state, E0a2b/D11g). Prints the values
# to write into app/data/aircraft/jensen_ugly_stik_60.json (4 significant digits), their spread over α 0–6°, and
# closed-form cross-checks from the same data: Cmq_t = −2·a_f·(S_t/S)·(l_t/c)², CLq_t = 2·a_f·(S_t/S)·(l_t/c),
# Cnr = −2·(l_v/b)·Cnβ_fin − CD0/3, Cmα̇ = −2·a_f·(S_t/S)·(l_t/c)·(dε/dα)·(l_lag/c) (a_f the free tail slope).
# Run from the repository root: $(app/get-godot.sh) --headless --path app --script "$PWD/research/aero/d11g/derive_rate_derivatives.gd"
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const Trim := preload("res://physics/trim.gd")

const PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const V := 15.0
const RHO := 1.225


func _initialize() -> void:
	var model: Dictionary = AD.load_file(PATH).model
	var t := Trim.solve("level", V, model, 9.80665, model.controls.throw_rad)
	var alpha: float = t.alpha
	print("15 m/s level trim: α %.3f°" % rad_to_deg(alpha))
	var at_trim := _derivatives(model, alpha)
	print("| α° | Cmq | CLq | Cnr |")
	for deg in [0.0, 2.0, 4.0, 6.0]:
		var r := _derivatives(model, deg_to_rad(deg))
		print("| %.0f | %.4f | %.4f | %.5f |" % [deg, r.Cmq, r.CLq, r.Cnr])
	var S: float = model.reference.S
	var b: float = model.reference.b
	var c: float = model.reference.c
	var tail: Dictionary = model.surfaces.horizontal
	var fin: Dictionary = model.surfaces.vertical
	var l_t: float = float(tail.position[0]) - float(model.cg_le[0])
	var l_v: float = float(fin.position[0]) - float(model.cg_le[0])
	var vh: float = float(tail.free_slope) * float(tail.area) / S
	var cnb_fin: float = float(fin.lift_slope) * float(fin.area) / S * l_v / b
	print("closed form: Cmq_tail %.4f, CLq_tail %.4f, Cnr fin + wing profile %.5f, Cmα̇ %.4f"
		% [-2.0 * vh * pow(l_t / c, 2), 2.0 * vh * l_t / c, -2.0 * l_v / b * cnb_fin - float(model.aero.CD0) / 3.0,
		-2.0 * vh * l_t / c * float(tail.downwash_gradient) * float(tail.downwash_lag_length) / c])
	print("derived at the trim α (write these): Cmq %s, CLq %s, Cnr %s"
		% [String.num(at_trim.Cmq, 4 - _digits(at_trim.Cmq)), String.num(at_trim.CLq, 4 - _digits(at_trim.CLq)),
		String.num(at_trim.Cnr, 4 - _digits(at_trim.Cnr))])
	print("borrowed (UltraStick 25e) before D11g: Cmq -13.5664, CLq 6.1639, Cnr -0.1833")
	quit(0)


## Digits before the decimal point (negative for leading zeros after it), for 4 significant digits.
func _digits(x: float) -> int:
	return int(floor(log(absf(x)) / log(10.0))) + 1


## Local-model Cmq, CLq (per q̂ = q·c/2V) and Cnr (per r̂ = r·b/2V), central differences about the CG.
func _derivatives(model: Dictionary, alpha: float) -> Dictionary:
	var S: float = model.reference.S
	var b: float = model.reference.b
	var c: float = model.reference.c
	var qbar := 0.5 * RHO * V * V
	var h := 0.05
	var qp := _local(model, alpha, 1, h)
	var qm := _local(model, alpha, 1, -h)
	var lift_p: float = qp[0] * sin(alpha) - qp[2] * cos(alpha)
	var lift_m: float = qm[0] * sin(alpha) - qm[2] * cos(alpha)
	var rp := _local(model, alpha, 2, h)
	var rm := _local(model, alpha, 2, -h)
	return {
		Cmq = (qp[4] - qm[4]) / (2.0 * h) / (qbar * S * c * c / (2.0 * V)),
		CLq = (lift_p - lift_m) / (2.0 * h) / (qbar * S * c / (2.0 * V)),
		Cnr = (rp[5] - rm[5]) / (2.0 * h) / (qbar * S * b * b / (2.0 * V)),
	}


func _local(model: Dictionary, alpha: float, axis: int, rate: float) -> PackedFloat64Array:
	var s := PackedFloat64Array([0, 0, -100, V * cos(alpha), 0, V * sin(alpha), 1, 0, 0, 0, 0, 0, 0])
	s[10 + axis] = rate
	var d := { elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0 }
	return Aero._local_loads(s, Air.compute(s, PackedFloat64Array([0, 0, 0]), RHO), d, model, RHO)
