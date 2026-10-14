# D6e-R1: the Stik's local horizontal-tail effective incidence for the current aerodynamic reference point.
# The provisional surface model (docs/research/flight-repair-implementation.md) set it to Cm0/Cma: with the ARP at the CG
# the tail was the local model's only pitching moment, so that value gave the oracle's zero-moment angle. With the ARP ahead
# of the CG the local wing strips also carry a moment, so the same requirement is solved directly: the incidence at which
# the local model's static pitching moment equals the oracle's at the 15 m/s level trim (no trim step at the regime switch,
# tests/test_regime_consistency.gd). Every candidate goes through the real loader. Writes nothing; prints the value.
# Run from the repository root:
#   .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script "$PWD/research/flight-dynamics/climb-trim/derive_tail_incidence.gd"
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const Trim := preload("res://physics/trim.gd")

const PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const V := 15.0
const RHO := 1.225


func _initialize() -> void:
	var low := -0.05
	var high := 0.08
	var f_low := _mismatch(low)
	assert(f_low * _mismatch(high) < 0.0, "incidence bracket does not contain a root")
	for i in 60:
		var mid := 0.5 * (low + high)
		var f_mid := _mismatch(mid)
		if f_low * f_mid <= 0.0:
			high = mid
		else:
			low = mid
			f_low = f_mid
	var root := 0.5 * (low + high)
	var written := snappedf(root, 0.00001)
	print("current incidence %.5f rad: local - oracle static Cm at the trim %.5f" % [_current(), _mismatch(_current())])
	print("solved incidence %.7f rad (write %.5f): mismatch %.6f" % [root, written, _mismatch(written)])
	quit(0)


func _current() -> float:
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return float(parsed.aero.surfaces.horizontal.incidence.value)


## Local minus oracle static pitching-moment coefficient about the CG at the oracle's 15 m/s level trim.
func _mismatch(incidence: float) -> float:
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	parsed.aero.surfaces.horizontal.incidence.value = incidence
	var derived: Dictionary = AD.validate_and_derive(parsed)
	assert(derived.ok, str(derived.get("errors", [])))
	var model: Dictionary = derived.model
	var t := Trim.solve("level", V, model, 9.80665, model.controls.throw_rad)
	assert(t.ok, t.message)
	var s := PackedFloat64Array([0, 0, -100, V * cos(t.alpha), 0, V * sin(t.alpha), 1, 0, 0, 0, 0, 0, 0])
	var air := Air.compute(s, PackedFloat64Array([0, 0, 0]), RHO)
	var d := {elevator = t.elevator, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}
	var scale: float = 0.5 * RHO * V * V * model.reference.S * model.reference.c
	return (Aero._local_loads(s, air, d, model, RHO)[4] - Aero._global_loads(s, air, d, model, RHO)[4]) / scale
