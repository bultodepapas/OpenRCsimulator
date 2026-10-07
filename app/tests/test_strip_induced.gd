# D11d: the wing strips' induced-flow map (AircraftData.strip_influence / effective_angle_map / _induced_map).
# Known answers at a0 = 2π: an elliptic AR 50 wing reaches Prandtl's a0/(1 + a0/(π·AR)); an AR 5 rectangular wing with 3, 5 and 8 equal
# strips per side reproduces an independent Weissinger implementation (research/aero/d11d/lifting_line.py), which also
# matches the knowledge base's VLM (02-aerodynamics-rc-scale.md: 4.32/4.17/4.08, Clp −0.481/−0.449/−0.427). For every
# catalog aircraft the calibration is exact (local wing + tail CLα = aero.CLa, CL(0) = aero.CL0), the section slope is
# physically plausible and the map is mirror-symmetric.
# Run: godot --headless --path . --script res://tests/test_strip_induced.gd
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")

## Independent Weissinger reference (research/aero/d11d/lifting_line.py), AR 5 rectangular, a0 = 2π:
## strips per side → [CLα, Clp].
const REFERENCE := { 3: [4.3171, -0.4814], 5: [4.1699, -0.4494], 8: [4.0789, -0.4274] }

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		_failures += 1


func _initialize() -> void:
	var b := 1.524
	var c := 0.3048
	var S := b * c
	# Elliptic planforms, 200 equal-span strips per side. Weissinger is a lifting-surface method: at AR 50 it must reach
	# Prandtl's lifting line a0/(1 + a0/πAR); at AR 5 it sits lower (4.0920, the independent implementation's value).
	for case in [[50.0, -1.0], [5.0, 4.0920]]:
		var ar: float = case[0]
		var span := 1.0
		var area := span * span / ar
		var wing := _strips(span, 200, func(y: float) -> float: return 4.0 * area / (PI * span) * sqrt(maxf(1e-12, 1.0 - pow(2.0 * y / span, 2.0))))
		var strip_area := 0.0
		for j in wing.ys.size():
			strip_area += wing.chord[j] * (wing.edges[j + 1] - wing.edges[j])
		var ell := _responses(wing, TAU, strip_area, span)
		if case[1] < 0.0:
			var prandtl := TAU / (1.0 + TAU / (PI * ar))
			_check("elliptic AR 50: CLα %.4f reaches Prandtl's lifting line %.4f within 0.5 %%" % [ell.CLa, prandtl], absf(ell.CLa / prandtl - 1.0) < 0.005)
		else:
			_check("elliptic AR 5: CLα %.4f matches the independent Weissinger %.4f" % [ell.CLa, case[1]], absf(ell.CLa - case[1]) < 1e-3)
	for n in REFERENCE:
		var r := _responses(_strips(b, n, func(_y: float) -> float: return c), TAU, S, b)
		var ref: Array = REFERENCE[n]
		_check("AR 5 rectangular, %d strips per side: CLα %.4f, Clp %.4f match the independent Weissinger %.4f, %.4f" % [n, r.CLa, r.Clp, ref[0], ref[1]],
			absf(r.CLa - ref[0]) < 1e-3 and absf(r.Clp - ref[1]) < 1e-3)
	for id in Catalog.ids():
		_aircraft(id)
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _aircraft(id: String) -> void:
	var r := AD.validate_and_derive(JSON.parse_string(FileAccess.get_file_as_string(Catalog.entry(id).data)))
	if not r.ok:
		_check("%s loads" % id, false, str(r.errors))
		return
	var m: Dictionary = r.model
	var env: Dictionary = m.envelope
	var e: PackedFloat64Array = env.induced_map
	var n: int = env.station_ys.size()
	var a0: float = env.strip_slope
	var horizontal: Dictionary = m.surfaces.horizontal
	var tail_share: float = float(horizontal.area) / float(m.reference.S) * float(horizontal.lift_slope)
	var row_mean := 0.0
	for v in e:
		row_mean += v
	row_mean /= float(n)
	var twist: PackedFloat64Array = m.surfaces.get("station_incidence", PackedFloat64Array())
	var cl_zero := tail_share * float(horizontal.incidence)
	for i in n:
		var mapped := 0.0
		for k in n:
			mapped += e[i * n + k] * (twist[k] if not twist.is_empty() else 0.0)
		cl_zero += (env.strip_cl0[i] + a0 * mapped) / float(n)
	_check("%s: local wing + tail CLα = aero.CLa %.4f (a0 %.3f/rad)" % [id, m.aero.CLa, a0], absf(a0 * row_mean + tail_share - float(m.aero.CLa)) < 1e-9)
	_check("%s: local CL at α 0 = aero.CL0 %.4f" % [id, m.aero.CL0], absf(cl_zero - float(m.aero.CL0)) < 1e-9, "%.9f" % cl_zero)
	_check("%s: section slope a0 %.2f within 0.75–1.10 × 2π" % [id, a0], a0 > 0.75 * TAU and a0 < 1.10 * TAU)
	var mirror := true
	for i in n:
		for k in n:
			mirror = mirror and absf(e[i * n + k] - e[(n - 1 - i) * n + (n - 1 - k)]) < 1e-12
	_check("%s: the map is mirror-symmetric" % id, mirror)


## Equal-span strips (both sides), control points at mid-span of each strip.
func _strips(span: float, per_side: int, chord_at: Callable) -> Dictionary:
	var h := span / 2.0
	var edges := PackedFloat64Array()
	for k in range(per_side, 0, -1):
		edges.append(-h * k / per_side)
	for k in per_side + 1:
		edges.append(h * k / per_side)
	var ys := PackedFloat64Array()
	var chord := PackedFloat64Array()
	for j in 2 * per_side:
		var y := 0.5 * (edges[j] + edges[j + 1])
		ys.append(y)
		chord.append(chord_at.call(absf(y)))
	return { edges = edges, ys = ys, chord = chord }


## Wing CLα and Clp (per p̂ = pb/2V) from the map at section slope a0.
func _responses(wing: Dictionary, a0: float, S: float, span: float) -> Dictionary:
	var n: int = wing.ys.size()
	var e := AD.effective_angle_map(AD.strip_influence(wing.edges, wing.ys, wing.chord), a0, n)
	var cla := 0.0
	var clp := 0.0
	for i in n:
		var sym := 0.0
		var anti := 0.0
		for k in n:
			sym += e[i * n + k]
			anti += e[i * n + k] * 2.0 * wing.ys[k] / span
		var strip_area: float = wing.chord[i] * (wing.edges[i + 1] - wing.edges[i])
		cla += strip_area * a0 * sym
		clp -= strip_area * a0 * anti * wing.ys[i]
	return { CLa = cla / S, Clp = clp / (S * span) }
