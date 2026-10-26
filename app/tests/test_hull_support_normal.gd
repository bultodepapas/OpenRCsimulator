# GP-10b: independent positive-down plane oracles for hull lake normals.
# Curved-surface signed distance and microrelief migration are outside this fix.
extends SceneTree

const Hull := preload("res://physics/hull_contact.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Lake := preload("res://physics/lake_surface.gd")
const Loader := preload("res://data/lake_loader.gd")

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	_plane_oracles()
	_live_mass_consistency()
	_check("no-lake law identity remains byte-identical", Hull.law().sha256_text() == "03963546ff5efa6a694583c9d9cc19e5ca9d6b24663d6be140aba0544de57291")
	_check("lake correction has an explicit law identity", Hull.LAKE_NORMAL_LAW == "positive-down-bank-gradient-normal-v2")
	_check("invalid north slope rejects instead of flat support", Hull._lake_normal({slope_north = NAN, slope_east = 0.1}).is_empty())
	_check("invalid east slope rejects instead of flat support", Hull._lake_normal({slope_north = 0.1, slope_east = INF}).is_empty())
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _plane_oracles() -> void:
	var q := M.q_from_euler(0.4, -0.3, 0.2)
	var inverse_q := PackedFloat64Array([q[0], -q[1], -q[2], -q[3]])
	var arm := M.v3(0.1, -0.2, 0.3)
	var omega := M.v3(0.7, -0.4, 0.2)
	var prepared := {stiffness = PackedFloat64Array([1000.0]), damping = PackedFloat64Array([50.0])}
	var elastic := {stiffness = PackedFloat64Array([1000.0]), damping = PackedFloat64Array([0.0])}
	var worst_old_closing := 0.0
	for slopes: PackedFloat64Array in [PackedFloat64Array([0.2, 0.0]), PackedFloat64Array([-0.2, 0.0]),
			PackedFloat64Array([0.0, 0.3]), PackedFloat64Array([0.0, -0.3]),
			PackedFloat64Array([0.2, -0.3]), PackedFloat64Array([-0.2, 0.3])]:
		var dn := slopes[0]
		var de := slopes[1]
		var length := sqrt(1.0 + dn * dn + de * de)
		# Exact signed distance to plane D=dn*N+de*E+offset.
		var normal := M.v3(dn / length, de / length, -1.0 / length)
		var terrain := {ground_down_m = 0.7, slope_north = dn, slope_east = de}
		var actual: PackedFloat64Array = Hull._lake_normal(terrain)
		_check("normal matches independent down-plane gradient %s" % slopes, _near(actual, normal, 1e-14))
		var t_n := M.v3(1.0, 0.0, dn)
		var t_e := M.v3(0.0, 1.0, de)
		_check("both independent plane tangents are orthogonal %s" % slopes,
			absf(M.dot(actual, t_n)) < 1e-14 and absf(M.dot(actual, t_e)) < 1e-14 and actual[2] < 0.0)
		var velocity := M.add(t_n, M.scale(t_e, 0.7))
		var point := M.v3(0.0, 0.0, 0.7 + 0.01 * length)
		# Independent central difference of the analytic plane gap along tangent motion.
		var eps := 1e-5
		var plus := M.add(point, M.scale(velocity, eps))
		var minus := M.sub(point, M.scale(velocity, eps))
		var gap_plus: float = (dn * plus[0] + de * plus[1] + 0.7 - plus[2]) / length
		var gap_minus: float = (dn * minus[0] + de * minus[1] + 0.7 - minus[2]) / length
		_check("tangent has zero analytic gap/closing rate %s" % slopes,
			absf((gap_plus - gap_minus) / (2.0 * eps)) < 1e-10 and absf(M.dot(actual, velocity)) < 1e-14)
		var old_normal: PackedFloat64Array = _legacy_normal(terrain)
		worst_old_closing = maxf(worst_old_closing, absf(M.dot(old_normal, velocity)))
		# Nonidentity attitude and body rate: make the contact velocity equal to the prescribed world tangent.
		var body_velocity := M.sub(M.q_rotate(inverse_q, velocity), M.cross(omega, arm))
		var state := RB.make_state(M.sub(point, M.q_rotate(q, arm)), body_velocity, q, omega)
		var with_damper: PackedFloat64Array = Hull._lake_load(state, prepared, 0, arm, point, terrain)
		var no_damper: PackedFloat64Array = Hull._lake_load(state, elastic, 0, arm, point, terrain)
		_check("tangent motion adds no damper reaction %s" % slopes, _near(with_damper, no_damper, 1e-10))
		var force_world := M.q_rotate(q, with_damper.slice(0, 3))
		_check("spring normal load stays k*x for tangential travel %s" % slopes, absf(M.dot(force_world, normal) - 10.0) < 1e-10)
		_check("tangent normal force does no work %s" % slopes, absf(M.dot(force_world, normal) * M.dot(normal, velocity)) < 1e-12)
		var closing := M.scale(normal, -0.4)
		var closing_state := RB.make_state(M.sub(point, M.q_rotate(q, arm)),
			M.sub(M.q_rotate(inverse_q, closing), M.cross(omega, arm)), q, omega)
		var loaded: PackedFloat64Array = Hull._lake_load(closing_state, prepared, 0, arm, point, terrain)
		var load_world := M.q_rotate(q, loaded.slice(0, 3))
		_check("pure approach force follows outward normal %s" % slopes, _near(load_world, M.scale(normal, 30.0), 1e-10))
		_check("normal damper dissipates c*rate^2 %s" % slopes,
			absf(M.dot(M.sub(load_world, M.scale(normal, 10.0)), closing) + 8.0) < 1e-10)
		var record: Dictionary = Hull._lake_contact_record(closing_state, closing_state, prepared, 0, arm,
			point, terrain, q, q)
		_check("contact observation projects approach speed along corrected normal %s" % slopes,
			absf(record.normal_speed_mps - 0.4) < 1e-12 and record.slide_speed_mps < 1e-12)
	var counter := {slope_north = 0.2, slope_east = 0.0}
	var old_closing := -M.dot(_legacy_normal(counter), M.v3(1.0, 0.0, 0.2))
	_check("frozen source reproduces spurious 0.392232 m/s tangent closing", absf(old_closing - 0.4 / sqrt(1.04)) < 1e-14)
	print("GP-10b frozen positive-down plane spurious closing_mps=", old_closing,
		" worst_two_axis_closing_mps=", worst_old_closing)


func _live_mass_consistency() -> void:
	var loaded: Dictionary = Loader.load_from(Loader.DEFAULT_PATH)
	_check("authored lake loads for public hull routes", loaded.ok, str(loaded.get("errors", [])))
	if not loaded.ok:
		return
	var lake: Dictionary = loaded.lake
	var terrain: Dictionary = Lake.sample_terrain_validated(lake, 110.0, 155.0)
	var slope_length := sqrt(1.0 + terrain.slope_north * terrain.slope_north + terrain.slope_east * terrain.slope_east)
	_check("public hull fixture has a nonflat covered bed", terrain.covered and absf(terrain.slope_east) > 0.01)
	var j := PackedFloat64Array([1.0, 1.0, 1.0, 0.0, 0.0, 0.0])
	var hull := PackedFloat64Array([0.0, 0.0, 0.2])
	var prepared: Dictionary = Hull.prepare(hull, 2.0, j, lake)
	var geometry: Dictionary = Hull.prepare_geometry(hull, lake)
	var properties := {mass_kg = 2.0, cg_body_m = M.v3(0.0, 0.0, 0.0), inertia = j, inverse = RB.inertia_inverse(j)}
	var normal := M.v3(terrain.slope_north / slope_length, terrain.slope_east / slope_length, -1.0 / slope_length)
	for velocity: PackedFloat64Array in [M.v3(1.0, 0.0, terrain.slope_north), M.scale(normal, -0.4), M.v3(1.4, -0.3, 0.2)]:
		var state := RB.make_state(M.v3(110.0, 155.0, terrain.ground_down_m + 0.01 * slope_length - 0.2),
			velocity, M.quat(1.0, 0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0))
		var constant: PackedFloat64Array = Hull.loads(state, prepared)
		var dynamic: Dictionary = Hull.loads_at_properties(state, geometry, properties)
		_check("constant/live-mass support agree for zero CG shift %s" % velocity,
			dynamic.ok and constant.size() == 6 and _near(constant, dynamic.loads, 1e-9), str(dynamic))
		var record: Array = Hull.contacts(state, state, prepared)
		_check("public contact record carries the same corrected normal %s" % velocity,
			record.size() == 1 and _near(record[0].normal_ned, normal, 1e-12))
	var approach := M.scale(normal, -3.0)
	var before := RB.make_state(M.v3(110.0, 155.0, terrain.ground_down_m - 0.01 * slope_length - 0.2),
		approach, M.quat(1.0, 0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0))
	var after := before.duplicate()
	after[2] += 0.02 * slope_length
	var terminal: Dictionary = Hull.terminal(before, after, prepared)
	var dynamic_terminal: Dictionary = Hull.terminal_at_properties(before, after, geometry, properties)
	_check("terminal impact projects approach along corrected slope", terminal.index == 0 and terminal.rule == "impact" \
		and absf(terminal.normal_speed_mps - 3.0) < 1e-12, str(terminal))
	_check("live-mass and constant terminal severity agree", dynamic_terminal.ok \
		and dynamic_terminal.event.rule == terminal.rule \
		and absf(dynamic_terminal.event.specific_j_per_kg - terminal.specific_j_per_kg) < 1e-12, str(dynamic_terminal))
	# A flat no-lake contact is outside the corrected branch and remains exact against frozen source.
	var flat := Hull.prepare(hull, 2.0, j)
	var flat_state := RB.make_state(M.v3(0.0, 0.0, -0.19), M.v3(0.4, -0.2, 0.1),
		M.quat(1.0, 0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0))
	# Native float64 Variant bytes captured from b85ce1047a3e7798ab22b330675fc0c9e4bce912.
	_check("no-lake contact force bytes remain unchanged", var_to_bytes(Hull.loads(flat_state, flat)).hex_encode() \
		== "2100000006000000245fcceead6a3dc0245fcceead6a2d40e7388ee3388e54c01d4c70258b8807c01d4c70258b8817c00000000000000000")


# Executable historical expression from hull_contact.gd::_lake_normal at b85ce104.
# Do not inherit it from the covered-query fixture: that fixture inherits current
# production helpers and freezes only prop_disc_depth.
func _legacy_normal(terrain: Dictionary) -> PackedFloat64Array:
	var north: float = terrain.slope_north
	var east: float = terrain.slope_east
	var length: float = M.sqrt_(1.0 + north * north + east * east)
	return PackedFloat64Array([-north / length, -east / length, -1.0 / length])


func _near(a: PackedFloat64Array, b: PackedFloat64Array, tolerance: float) -> bool:
	if a.size() != b.size():
		return false
	for k in a.size():
		if not is_finite(a[k]) or not is_finite(b[k]) or absf(a[k] - b[k]) > tolerance:
			return false
	return true
