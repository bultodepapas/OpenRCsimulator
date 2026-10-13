# CR-09e: hidden fracture detail for the Ugly Stik wreck. Nothing here is visible in flight: each node carries meta
# crash_reveal = the section whose release shows it (render/crash/wreck.gd), and crash_section = the body it rides on.
# Geometry follows the Jensen structure: 1/4 in balsa sides, 1/8 in top and 3/32 in bottom sheet (sheet 1), and the
# wing's spars, leading edge and trailing-edge sheet at the plan-traced chord stations (appearance film_structure).
# Splinter lengths and film tears are seeded estimates, not a fracture simulation.
extends RefCounted

const Geometry := preload("res://aircraft/ugly_stik_geometry.gd")
const Finish := preload("res://aircraft/ugly_stik_finish.gd")
const D: Dictionary = Geometry.DATA
const BALSA := Color("d9c08e")
const SIDE_SHEET_M := 0.00635
const TOP_SHEET_M := 0.003175
const BOTTOM_SHEET_M := 0.0023813


static func build(root: Node3D, break_station: int, wing_frames: Dictionary) -> void:
	var station: Array = D.fuselage_stations[break_station]
	var core := _node(root, "fracture_fuselage_core", "core", "tail_boom")
	_fuselage_break(core, station, -1.0, 7101)
	var boom := _node(root, "fracture_fuselage_boom", "tail_boom", "tail_boom")
	_fuselage_break(boom, station, 1.0, 7202)
	for side in wing_frames:
		var frame: Node3D = wing_frames[side]
		var kind := "wing_" + str(side)
		# Children of the wing frame ride with its section; only the reveal meta is needed.
		var stub := _node(frame, "fracture_wing_root_" + str(side), "", kind)
		_wing_root(stub, -1.0 if str(side) == "right" else 1.0, 7300 + (1 if str(side) == "right" else 2))


static func _node(parent: Node3D, label: String, section: String, reveal: String) -> Node3D:
	var node := Node3D.new()
	node.name = label
	node.visible = false
	if not section.is_empty():
		node.set_meta("crash_section", section)
	node.set_meta("crash_reveal", reveal)
	parent.add_child(node)
	return node


static func _surface(color: Color, profile: String, double_sided := false) -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mat := Finish.material(color, profile)
	if double_sided:
		mat = mat.duplicate() as StandardMaterial3D
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(mat)
	return st


# Clockwise front faces seen from `outward` (Godot), flat normal.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	var n := (c - a).cross(b - a)
	if n.dot(outward) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	n = n.normalized()
	for p in [a, b, c]:
		st.set_normal(n)
		st.add_vertex(p)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3) -> void:
	_tri(st, a, b, c, outward)
	_tri(st, a, c, d, outward)


static func _commit(parent: Node3D, label: String, st: SurfaceTool) -> void:
	var instance := MeshInstance3D.new()
	instance.name = String(parent.name) + "_" + label # node names are unique across the model (verify_model)
	instance.mesh = st.commit()
	parent.add_child(instance)


# One side of the fuselage break. `direction` is −1 for the front piece (it lies forward of the station; its
# splinters reach aft into the gap) and +1 for the boom (it lies aft; its splinters reach forward).
static func _fuselage_break(parent: Node3D, station: Array, direction: float, seed: int) -> void:
	var z: float = station[0]
	var w: float = station[1]
	var top: float = station[2]
	var bottom: float = station[3]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var wood := _surface(BALSA, "wood")
	var film := _surface(Finish.RED, "skin", true)
	# Into the piece = the side the piece lies on; the gap is on the other side.
	var into := direction # boom lies aft (+Z) of the station, the front piece forward (−Z)
	# The inner balsa faces themselves are the fuselage's own inner lining (CR-09f, ugly_stik_model.gd).
	# The cut faces of the sheets (end grain) at the station, facing the gap.
	var gap := Vector3(0, 0, -into)
	_quad(wood, Vector3(w, bottom, z), Vector3(w, top, z), Vector3(w - SIDE_SHEET_M, top, z), Vector3(w - SIDE_SHEET_M, bottom, z), gap)
	_quad(wood, Vector3(-w, top, z), Vector3(-w, bottom, z), Vector3(-w + SIDE_SHEET_M, bottom, z), Vector3(-w + SIDE_SHEET_M, top, z), gap)
	_quad(wood, Vector3(-w, top, z), Vector3(w, top, z), Vector3(w, top - TOP_SHEET_M, z), Vector3(-w, top - TOP_SHEET_M, z), gap)
	_quad(wood, Vector3(w, bottom, z), Vector3(-w, bottom, z), Vector3(-w, bottom + BOTTOM_SHEET_M, z), Vector3(w, bottom + BOTTOM_SHEET_M, z), gap)
	# Splinters: wedges of each sheet reaching across the gap, every ~4.5 mm around the section, seeded lengths.
	var outline := [
		[Vector3(w, bottom, 0), Vector3(w, top, 0), Vector3.RIGHT, SIDE_SHEET_M],
		[Vector3(w, top, 0), Vector3(-w, top, 0), Vector3.UP, TOP_SHEET_M],
		[Vector3(-w, top, 0), Vector3(-w, bottom, 0), Vector3.LEFT, SIDE_SHEET_M],
		[Vector3(-w, bottom, 0), Vector3(w, bottom, 0), Vector3.DOWN, BOTTOM_SHEET_M],
	]
	for edge in outline:
		var a: Vector3 = edge[0]
		var b: Vector3 = edge[1]
		var outward: Vector3 = edge[2]
		var thick: float = edge[3]
		var steps := maxi(2, int((b - a).length() / 0.0045))
		for k in steps:
			if rng.randf() < 0.25: continue # some places break flush
			var t0 := (k + rng.randf_range(0.0, 0.3)) / steps
			var t1 := (k + rng.randf_range(0.7, 1.0)) / steps
			var length := rng.randf_range(0.002, 0.022) * (1.0 if rng.randf() < 0.7 else 0.35)
			var p0 := a.lerp(b, t0) + Vector3(0, 0, z)
			var p1 := a.lerp(b, t1) + Vector3(0, 0, z)
			var tip := a.lerp(b, rng.randf_range(t0, t1)) + Vector3(0, 0, z) + gap * length + outward * rng.randf_range(-0.0015, 0.004)
			var inset := -outward * thick
			_splinter(wood, p0, p1, tip, inset)
			# Film peels back from about a third of the splinters as a torn, curling flap.
			if rng.randf() < 0.33:
				var flap := tip + gap * rng.randf_range(0.0, 0.006) + outward * rng.randf_range(0.002, 0.009)
				_tri(film, p0 + outward * 0.0004, p1 + outward * 0.0004, flap, outward)
	_commit(parent, "broken_balsa", wood)
	_commit(parent, "torn_film", film)


# A balsa sliver: outer face on the skin line, inner face one sheet thickness in, tapering to a sharp tip.
static func _splinter(st: SurfaceTool, p0: Vector3, p1: Vector3, tip: Vector3, inset: Vector3) -> void:
	var q0 := p0 + inset
	var q1 := p1 + inset
	var tip_in := tip + inset * 0.3
	var out := -inset.normalized()
	_tri(st, p0, p1, tip, out)
	_tri(st, q0, q1, tip_in, -out)
	var side := (p1 - p0).normalized()
	_quad(st, p0, tip, tip_in, q0, -side)
	_quad(st, p1, tip, tip_in, q1, side)


# Broken wing root: spar, leading-edge and trailing-edge-sheet stubs splintering past the root rib toward `toward`
# (−X for the right half, +X for the left), at the plan-traced chord stations, plus torn film along the root.
static func _wing_root(parent: Node3D, toward: float, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var chord: float = D.wing.chord
	var f: Dictionary = Finish.Appearance.DATA.film_structure
	var section: Array = D.wing.section
	var wood := _surface(BALSA, "wood")
	var film := _surface(Finish.RED, "skin", true)
	var stubs := [
		# [chord fraction from, to, top skin?] main spar top and bottom, secondary spar top and bottom, LE, TE sheet.
		[float(f.main_spar_fraction[0]), float(f.main_spar_fraction[1]), true],
		[float(f.main_spar_fraction[0]), float(f.main_spar_fraction[1]), false],
		[float(f.secondary_spar_fraction[0]), float(f.secondary_spar_fraction[1]), true],
		[float(f.secondary_spar_fraction[0]), float(f.secondary_spar_fraction[1]), false],
		[0.0, float(f.leading_edge_fraction), true],
		[float(f.trailing_sheet_front_fraction), 0.86, true],
	]
	for stub in stubs:
		var z0: float = float(stub[0]) * chord
		var z1: float = float(stub[1]) * chord
		var y_skin := _skin_height(section, 0.5 * (float(stub[0]) + float(stub[1])), bool(stub[2])) * chord
		var depth := 0.0063 if float(stub[1]) - float(stub[0]) > 0.015 else 0.0048
		var y0 := y_skin - (depth if bool(stub[2]) else -depth)
		var length := rng.randf_range(0.008, 0.030)
		var x := 0.0
		var tip_x := toward * length
		var lo := minf(y0, y_skin)
		var hi := maxf(y0, y_skin)
		# A spar stub: a box out of the root that ends in two staggered splinters.
		var mid_x := toward * length * rng.randf_range(0.35, 0.6)
		var box := [Vector3(x, lo, z0), Vector3(x, hi, z0), Vector3(x, hi, z1), Vector3(x, lo, z1)]
		var end := []
		for p: Vector3 in box: end.append(p + Vector3(mid_x, 0, 0))
		var faces := [[0, 1, Vector3(0, 0, -1)], [1, 2, Vector3.UP], [2, 3, Vector3(0, 0, 1)], [3, 0, Vector3.DOWN]]
		for face in faces:
			var i: int = face[0]
			var j: int = face[1]
			_quad(wood, box[i], box[j], end[j], end[i], face[2])
		var tip_a := Vector3(tip_x, lerpf(lo, hi, rng.randf_range(0.2, 0.8)), lerpf(z0, z1, rng.randf_range(0.0, 0.5)))
		var tip_b := Vector3(tip_x * rng.randf_range(0.6, 0.9), lerpf(lo, hi, rng.randf_range(0.2, 0.8)), lerpf(z0, z1, rng.randf_range(0.5, 1.0)))
		var out := Vector3(toward, 0, 0)
		_tri(wood, end[0], end[1], tip_a, out)
		_tri(wood, end[1], end[2], tip_b, out)
		_tri(wood, end[2], end[3], tip_b, out)
		_tri(wood, end[3], end[0], tip_a, out)
		_tri(wood, end[0], tip_a, tip_b, out)
	# Torn film hanging off the root along both skins.
	for top in [true, false]:
		var u := 0.03
		while u < 0.95:
			var u1 := minf(u + rng.randf_range(0.04, 0.09), 0.97)
			var y_a := _skin_height(section, u, top) * chord
			var y_b := _skin_height(section, u1, top) * chord
			var hang := Vector3(toward * rng.randf_range(0.002, 0.009), (-1.0 if top else 1.0) * rng.randf_range(0.0, 0.004), 0)
			_tri(film, Vector3(0, y_a, u * chord), Vector3(0, y_b, u1 * chord), Vector3(0, 0.5 * (y_a + y_b), 0.5 * (u + u1) * chord) + hang, Vector3(toward, 0, 0))
			u = u1 + rng.randf_range(0.05, 0.20)
	_commit(parent, "root_splinters", wood)
	_commit(parent, "root_torn_film", film)


# Height (in chords) of the traced section's upper or lower skin at chord fraction u.
static func _skin_height(section: Array, u: float, upper: bool) -> float:
	var best := 0.0
	var best_d := INF
	for i in section.size():
		var p: Array = section[i]
		var on_upper := i <= section.size() / 2
		if on_upper != upper: continue
		var d := absf(float(p[0]) - u)
		if d < best_d:
			best_d = d
			best = float(p[1])
	return best
