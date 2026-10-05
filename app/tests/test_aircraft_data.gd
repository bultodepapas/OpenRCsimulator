# D1: the aircraft physics data: loads, makes physical sense, agrees with the visual geometry,
# and rejects broken data with a specific message.
# Run: godot --headless --path . --script res://tests/test_aircraft_data.gd
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Geometry := preload("res://aircraft/ugly_stik_geometry.gd")
const PATH := "res://data/aircraft/jensen_ugly_stik_60.json"

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _raw() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(PATH))


## Expect the mutated data to fail with an error containing `needle`.
func _rejects(label: String, mutate: Callable, needle: String) -> void:
	var raw := _raw()
	mutate.call(raw)
	var r := AD.validate_and_derive(raw)
	var hit := false
	for e in r.errors:
		hit = hit or needle in e
	_check("rejects: " + label, not r.ok and hit, str(r.errors))


func _initialize() -> void:
	var r := AD.load_file(PATH)
	_check("real file loads", r.ok, str(r.errors))
	if not r.ok:
		quit(1)
		return
	var m: Dictionary = r.model

	# Physical sense
	_check("mass in the Stick .60 range", m.mass_kg > 2.3 and m.mass_kg < 3.4, str(m.mass_kg))
	var j: PackedFloat64Array = m.inertia
	_check("principal moments positive", j[0] > 0 and j[1] > 0 and j[2] > 0, str(j))
	_check("triangle inequalities (a real body)", j[0] + j[1] >= j[2] and j[1] + j[2] >= j[0] and j[0] + j[2] >= j[1], str(j))
	_check("airplane-like ordering Jzz > Jyy > Jxx", j[2] > j[1] and j[1] > j[0], str(j))
	_check("plan CG 4.76 in aft of LE (39 % chord)", absf(m.cg_le[0] - 0.1209) < 1e-9 and absf(m.cg_le[0] / m.reference.c - 0.397) < 0.01)
	_check("balance mismatch is reported, not hidden", r.warnings.size() > 0 and "balance" in r.warnings[0], str(r.warnings))

	# Inertia of a known shape: a 1 kg box 0.3 × 1.5 × 0.04 m about its centre (body axes).
	var box := AD.inertia_about([[1.0, PackedFloat64Array([0, 0, 0]), PackedFloat64Array([0.3, 1.5, 0.04])]], PackedFloat64Array([0, 0, 0]))
	_check("box inertia formula", absf(box[0] - (1.5 * 1.5 + 0.04 * 0.04) / 12.0) < 1e-12 and absf(box[2] - (0.09 + 2.25) / 12.0) < 1e-12, str(box))
	# Parallel axis and product of inertia: 1 kg point 1 m forward (x_aft = -1) and 1 m up → Jxz = -m·x·z = -(1)(-1) = +1.
	var pt := AD.inertia_about([[1.0, PackedFloat64Array([-1, 0, 1]), PackedFloat64Array([0, 0, 0])]], PackedFloat64Array([0, 0, 0]))
	_check("parallel axis + product term", absf(pt[1] - 2.0) < 1e-12 and absf(pt[4] - 1.0) < 1e-12, str(pt))

	# Agreement with the visual geometry (one source of truth per team; numbers must match).
	_check("span matches visual geometry", absf(m.reference.b - Geometry.DATA.wing.span) < 0.001, "%s vs %s" % [m.reference.b, Geometry.DATA.wing.span])
	_check("chord matches visual geometry", absf(m.reference.c - Geometry.DATA.wing.chord) / m.reference.c < 0.01, "%s vs %s" % [m.reference.c, Geometry.DATA.wing.chord])

	# Control throws are aircraft data with provenance (D5.9), in degrees in the file.
	_check("throws loaded (aileron 20°, elevator 20°, rudder 25°)", m.controls.throw_deg.aileron == 20.0 and m.controls.throw_deg.elevator == 20.0 and m.controls.throw_deg.rudder == 25.0, str(m.controls))
	_check("throws also in radians", absf(m.controls.throw_rad.rudder - deg_to_rad(25.0)) < 1e-15)

	# Aero conventions are present, so D3+ cannot guess them.
	for key in ["rates", "elevator", "aileron", "rudder", "drag", "axes"]:
		_check("convention documented: " + key, m.conventions.has(key))

	# Broken data is rejected with a specific message.
	_rejects("wrong format", func(d): d.format = "v0", "format")
	_rejects("mass in grams", func(d): d.inventory[0].mass.unit = "g", "unit 'g'")
	_rejects("unknown evidence kind", func(d): d.inventory[0].mass.kind = "guess", "kind 'guess'")
	_rejects("empty source", func(d): d.reference.wing_span.source = " ", "empty source")
	_rejects("missing unit", func(d): d.reference.wing_area.erase("unit"), "missing 'unit'")
	_rejects("negative mass", func(d): d.inventory[3].mass.value = -0.1, "outside")
	_rejects("position not a 3-vector", func(d): d.inventory[0].position.value = [0.1, 0.2], "3 numbers")
	_rejects("area inconsistent with span × chord", func(d): d.reference.wing_area.value = 0.6, "differs from wing_area")
	_rejects("unstable pitch (Cma > 0)", func(d): d.aero.coefficients.Cma.value = 0.4, "Cma")
	_rejects("reversed elevator (Cmde > 0)", func(d): d.aero.coefficients.Cmde.value = 0.8, "Cmde")
	_rejects("missing coefficient", func(d): d.aero.coefficients.erase("Cnr"), "Cnr")
	_rejects("total mass implausible (kg/g mix-up)", func(d): d.inventory[0].mass.value = 4.9, "plausible range")
	_rejects("missing controls section", func(d): d.erase("controls"), "controls: missing")
	_rejects("throw in radians", func(d): d.controls.max_throw.rudder.unit = "rad", "unit 'rad'")
	_rejects("missing elevator throw", func(d): d.controls.max_throw.erase("elevator"), "controls.max_throw.elevator")
	_rejects("implausible throw", func(d): d.controls.max_throw.aileron.value = 90.0, "outside")
	var bad := AD.validate_and_derive({ format = "nope" })
	_check("rejects garbage", not bad.ok)

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
