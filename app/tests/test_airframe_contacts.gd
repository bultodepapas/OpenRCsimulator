# GP-07: the Ugly Stik's airframe meets the ground where it is drawn, slides with the field surface's friction, and
# its contacts behave on the runway strip (research/ground-physics/gp07/, docs/research/ground-physics/GP-07/).
# - GP-07b coverage: over 2000 attitudes the drawn airframe (propeller blades and wheels aside) sinks at most
#   SINK_TOLERANCE_M into flat ground before a hull point or wheel touches, and every hull point is a drawn point.
#   A failure after a model edit means: run research/ground-physics/gp07/derive_stik_hull.py --write.
# - GP-07c friction: the soft hull law takes airframe_friction from the field surface under each point, and its
#   regularization speed keeps the linear friction rate on the point's smallest effective mass bounded.
# - GP-07d presentation: the crash slide table agrees with the physics table; the runway strip is turf.
# - Scenarios on the real tick: an over-rotation on the mains scrapes the tail skid without a crash; an inverted
#   Stik settles on its drawn fin and wing tops.
# Run: godot --headless --path . --script res://tests/test_airframe_contacts.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const HullContact := preload("res://physics/hull_contact.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Airplane := preload("res://render/airplane.gd")
const Severity := preload("res://render/crash/severity.gd")
const EffectiveMass := preload("res://physics/effective_mass.gd")
const Log := preload("res://sim/flight_log.gd")
const Reader := preload("res://tools/flight_log_cli.gd")

## The generator's tolerance (derive_stik_hull.py TOLERANCE_M); 2000 directions find at most what its 6000 find.
const SINK_TOLERANCE_M := 0.012
## RK4's real-axis stability limit is 2.785 per tick; keep the contact velocity dynamics below this with margin.
const RATE_DT_LIMIT := 2.5
## Hull points are drawn convex-hull points rounded to 0.1 mm.
const ON_DRAWING_M := 0.001
const DIRECTIONS := 2000
const EXCLUDED := ["propeller/propeller_blades"]
const GEAR_PARTS := ["wheel_left_pivot", "wheel_right_pivot", "nose_steering_pivot", "main_gear_structure"]

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not ok:
		_failures += 1


func _initialize() -> void:
	var f := FieldLoader.load_from()
	_check("default field loads", f.ok, str(f.get("errors", [])))
	var field: Dictionary = f.field
	var table := GroundSurfaces.load_table()
	_check("surface table loads", table.ok, str(table.errors))
	var session := FlightSession.new()
	session.setup()
	root.add_child(session)
	session.input_enabled = false
	_check("the field installs on the session", session.set_field(field), session.surface_error)
	_coverage(session)
	_surface_friction(session, table.table, field)
	_point_lookup(session, table.table)
	_regularization()
	_contact_rates(session)
	_presentation(table.table)
	_identity(session)
	_tail_skid_strike(session, field)
	_inverted_rest(session, field)
	_soft_log_replay(session, field)
	session.free()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures else 0)


# --- GP-07b: drawn-model coverage -----------------------------------------------------------------------------------

func _coverage(session: Node) -> void:
	var model: Dictionary = session.aircraft.model
	var visual: Dictionary = Airplane.build(Airplane.STIK_ID)
	_check("the Stik visual model builds", not visual.is_empty() and visual.get("root") is Node3D)
	if visual.is_empty():
		return
	var top: Node3D = visual.root
	var datum: Vector2 = Airplane.datum(Airplane.STIK_ID)
	var cg: PackedFloat64Array = model.cg_le
	var airframe: Array[PackedFloat64Array] = []
	var gear: Array[PackedFloat64Array] = []
	var stack: Array[Node] = [top]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if not (node is MeshInstance3D) or not _visible(node, top) or (node as MeshInstance3D).mesh == null:
			continue
		var path := str(top.get_path_to(node))
		if EXCLUDED.any(func(prefix: String) -> bool: return path.begins_with(prefix)):
			continue
		var shape: ConvexPolygonShape3D = (node as MeshInstance3D).mesh.create_convex_shape(true, false)
		var to_model := _in_model_frame(node as Node3D, top)
		var points := PackedFloat64Array()
		for p: Vector3 in shape.points:
			var m: Vector3 = to_model * p
			points.append_array(PackedFloat64Array([cg[0] - (m.z - datum.x), m.x - cg[1], cg[2] - (m.y - datum.y)]))
		if GEAR_PARTS.any(func(prefix: String) -> bool: return path.begins_with(prefix)):
			gear.append(points)
		else:
			airframe.append(points)
	top.free()
	var hull: PackedFloat64Array = model.crash_hull
	var physics := hull.duplicate()
	for contact: Dictionary in model.landing_gear.contacts:
		physics.append_array(contact.position)
	var worst := 0.0
	var worst_dir := PackedFloat64Array()
	for k in DIRECTIONS:
		var d := _direction(k)
		var drawn := -INF
		for points: PackedFloat64Array in airframe:
			drawn = maxf(drawn, _support(points, d))
		var sink := drawn - _support(physics, d)
		if sink > worst:
			worst = sink
			worst_dir = d
	_check("the drawn airframe sinks at most %.0f mm before a hull point or wheel touches" % (1000.0 * SINK_TOLERANCE_M),
		worst <= SINK_TOLERANCE_M, "worst %.1f mm along body-down %s; regenerate with derive_stik_hull.py" % [1000.0 * worst, str(worst_dir)])
	var all_drawn: Array[PackedFloat64Array] = airframe + gear
	var floating := 0.0
	for i in range(0, hull.size(), 3):
		var nearest := INF
		for points: PackedFloat64Array in all_drawn:
			for j in range(0, points.size(), 3):
				nearest = minf(nearest, M.norm(M.sub(points.slice(j, j + 3), hull.slice(i, i + 3))))
		floating = maxf(floating, nearest)
	_check("every hull point is a drawn point (no phantom fin, no buried tip)", floating <= ON_DRAWING_M,
		"farthest %.2f mm" % (1000.0 * floating))
	var ids := _hull_ids()
	_check("the tail skid and the exposed engine are hull points", ids.has("probe_tail_skid") and ids.has("probe_engine_head"))


## The base Stik's authored hull ids (the loader keeps them in the physical identity, not the model).
func _hull_ids() -> PackedStringArray:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft/jensen_ugly_stik_60.json"))
	return PackedStringArray(raw.get("crash_hull_ids", [])) if raw is Dictionary else PackedStringArray()


func _direction(k: int) -> PackedFloat64Array:
	var phi := acos(1.0 - 2.0 * (float(k) + 0.5) / float(DIRECTIONS))
	var theta := PI * (1.0 + sqrt(5.0)) * (float(k) + 0.5)
	return PackedFloat64Array([cos(theta) * sin(phi), sin(theta) * sin(phi), cos(phi)])


func _support(points: PackedFloat64Array, d: PackedFloat64Array) -> float:
	var best := -INF
	for j in range(0, points.size(), 3):
		best = maxf(best, points[j] * d[0] + points[j + 1] * d[1] + points[j + 2] * d[2])
	return best


func _visible(node: Node, top: Node3D) -> bool:
	var at: Node = node
	while at != null:
		if at is Node3D and not (at as Node3D).visible:
			return false
		if at == top:
			return true
		at = at.get_parent()
	return true


func _in_model_frame(node: Node3D, top: Node3D) -> Transform3D:
	var t: Transform3D = node.transform
	var parent: Node = node.get_parent()
	while parent != null and parent != top:
		if parent is Node3D:
			t = (parent as Node3D).transform * t
		parent = parent.get_parent()
	return t


# --- GP-07c: surface friction and regularization --------------------------------------------------------------------

func _runway(field: Dictionary) -> Dictionary:
	for s: Dictionary in field.surfaces:
		if s.type == "runway":
			return s
	return {}


func _surface_friction(session: Node, table: Dictionary, field: Dictionary) -> void:
	var built := GroundSurfaces.build_airframe(table, field)
	_check("the airframe friction table builds from the field", built.ok, str(built.errors))
	var rects: PackedFloat64Array = built.rects
	var runway := _runway(field)
	_check("the field has a runway strip", not runway.is_empty())
	if runway.is_empty():
		return
	var rn := float(runway.center_north)
	var re := float(runway.center_east)
	_check("runway strip friction is the table's", HullContact.friction_at(rects, rn, re) == table.runway.airframe_friction)
	_check("beyond every rectangle the ground is rough", HullContact.friction_at(rects, 1.0e5, 1.0e5) == table.rough.airframe_friction)
	_check("without a table the law keeps its default", HullContact.friction_at(PackedFloat64Array(), rn, re) == HullContact.FRICTION_MU)
	_check("uncut grass drags more than the strip", table.rough.airframe_friction > table.runway.airframe_friction)
	_check("the session's prepared hull carries the field's airframe table", session._hull_contact.get("surfaces", PackedFloat64Array()) == rects)
	# A left wing tip sunk 5 mm while sliding at 6 m/s: the friction/normal ratio is the surface's μ (slip ≫ v_reg).
	var prepared: Dictionary = session._hull_contact
	var hull: PackedFloat64Array = session.aircraft.model.crash_hull
	var names: PackedStringArray = session.aircraft.model.crash_hull_components
	var tip := names.find("left_wing_tip")
	for spot: Array in [["runway strip", rn, re, float(table.runway.airframe_friction)],
			["rough grass", 1.0e4, 1.0e4, float(table.rough.airframe_friction)]]:
		var q := M.q_from_euler(0.0, 0.0, deg_to_rad(-60.0))
		var depth := M.q_rotate(q, hull.slice(3 * tip, 3 * tip + 3))[2]
		var s := RB.make_state(M.v3(spot[1], spot[2], -depth + 0.005), M.q_rotate(M.q_conj(q), M.v3(6, 0, 0)), q, M.v3(0, 0, 0))
		var loads: PackedFloat64Array = HullContact.loads(s, prepared)
		var f_ned := M.q_rotate(q, PackedFloat64Array([loads[0], loads[1], loads[2]])) if loads.size() == 6 else PackedFloat64Array([0, 0, 0])
		var ratio := M.sqrt_(f_ned[0] * f_ned[0] + f_ned[1] * f_ned[1]) / maxf(1e-12, -f_ned[2])
		_check("a sliding tip on the %s feels μ %.2f" % [spot[0], spot[3]], absf(ratio - float(spot[3])) < 1e-9,
			"ratio %.12f" % ratio)


## The lookup uses the struck point's ground position, not the CG's, with north and east in order: a synthetic field
## whose surfaces all differ puts the CG on a thin north-south strip and the struck wing tip on the mown band east of
## it. The expected μ comes from this test's own rectangle check.
func _point_lookup(session: Node, table: Dictionary) -> void:
	var synthetic := table.duplicate(true)
	for pair: Array in [["runway", 0.31], ["rotorpad", 0.52], ["mown", 0.47], ["rough", 0.63]]:
		synthetic[pair[0]].airframe_friction = pair[1]
	var field := {surfaces = [
		{id = "strip", type = "runway", center_north = 0.0, center_east = 0.0, width_north_south = 40.0, length_east_west = 0.3},
		{id = "band", type = "mown", center_north = 0.0, center_east = 1.75, width_north_south = 40.0, length_east_west = 3.0},
		{id = "pad", type = "rotorpad", center_north = 0.0, center_east = -1.75, width_north_south = 40.0, length_east_west = 3.0}]}
	var built := GroundSurfaces.build_airframe(synthetic, field)
	_check("a synthetic airframe table builds", built.ok, str(built.errors))
	var prepared := HullContact.prepare(session.aircraft.model.crash_hull, session.sim.mass, session.sim.inertia, {}, built.rects)
	var hull: PackedFloat64Array = session.aircraft.model.crash_hull
	var names: PackedStringArray = session.aircraft.model.crash_hull_components
	for case: Array in [["right", deg_to_rad(60.0)], ["left", deg_to_rad(-60.0)]]:
		var tip := names.find(case[0] + "_wing_tip")
		var q := M.q_from_euler(0.0, 0.0, case[1])
		var lowest := -INF
		for i in range(0, hull.size(), 3):
			lowest = maxf(lowest, M.q_rotate(q, hull.slice(i, i + 3))[2])
		var s := RB.make_state(M.v3(0.0, 0.0, -lowest + 0.005), M.q_rotate(M.q_conj(q), M.v3(6, 0, 0)), q, M.v3(0, 0, 0))
		var touching := 0
		var expected := NAN
		for i in range(0, hull.size(), 3):
			var p := M.add(RB._slice3(s, RB.POS), M.q_rotate(q, hull.slice(i, i + 3)))
			if p[2] > 0.0:
				touching += 1
				expected = 0.31 if absf(p[1]) <= 0.15 else 0.47 if p[1] >= 0.25 and p[1] <= 3.25 else 0.52 if p[1] <= -0.25 and p[1] >= -3.25 else 0.63
		var loads := HullContact.loads(s, prepared)
		var f := M.q_rotate(q, PackedFloat64Array([loads[0], loads[1], loads[2]])) if loads.size() == 6 else PackedFloat64Array([0, 0, 0])
		var ratio := M.sqrt_(f[0] * f[0] + f[1] * f[1]) / maxf(1e-12, -f[2])
		_check("the %s tip over the %s band feels its own surface's μ, not the CG's strip" % [case[0], "mown" if case[0] == "right" else "pad"],
			touching >= 1 and absf(ratio - expected) < 1e-9 and expected == (0.47 if case[0] == "right" else 0.52),
			"%d touching, ratio %.6f, expected %.2f" % [touching, ratio, expected])


func _regularization() -> void:
	var bounded := true
	for mu: float in [0.4, 0.55, 1.2]:
		for f: float in [0.01, 1.0, 10.0, 100.0, 1000.0]:
			for m: float in [0.05, 0.2, 1.0, 3.0]:
				var v := HullContact.slip_regularization(mu, f, m)
				bounded = bounded and v >= HullContact.SLIP_REGULARIZATION_MIN_MPS \
					and mu * f / (v * m) <= HullContact.FRICTION_RATE_MAX * (1.0 + 1e-12)
	_check("linear friction never decays faster than FRICTION_RATE_MAX on the point's mass", bounded)
	_check("the rate bound is RK4-safe at 240 Hz (λ·dt ≤ 0.5)", HullContact.FRICTION_RATE_MAX / 240.0 <= 0.5)
	# A wing tip carrying 5 N at rest (smallest effective mass about 0.2 kg) holds closer to Coulomb than E3d1's 0.2 m/s.
	_check("a lightly loaded resting tip creeps less than with the fixed E3d1 band",
		HullContact.slip_regularization(0.4, 5.0, 0.2) < 0.2, "%.3f m/s" % HullContact.slip_regularization(0.4, 5.0, 0.2))


## Largest |eigenvalue| of the contact velocity dynamics, M⁻¹·∂(contact loads)/∂(body velocity, rates), at rest in a
## pose: the rate RK4 must resolve. Central differences on the real loads(); power iteration (real spectrum: damping
## and regularized friction are dissipative and symmetric at zero slip).
func _contact_rate(prepared: Dictionary, s: PackedFloat64Array, mass: float, inertia: PackedFloat64Array) -> float:
	var j_inv := EffectiveMass._inverse_or_empty(inertia)
	var columns: Array[PackedFloat64Array] = []
	var step := 1.0e-5
	for k in 6:
		var plus := s.duplicate()
		var minus := s.duplicate()
		var index: int = RB.VEL + k if k < 3 else RB.RATE + k - 3
		plus[index] += step
		minus[index] -= step
		var lp := HullContact.loads(plus, prepared)
		var lm := HullContact.loads(minus, prepared)
		var column := PackedFloat64Array([0, 0, 0, 0, 0, 0])
		if lp.size() == 6 and lm.size() == 6:
			for r in 6:
				column[r] = (lp[r] - lm[r]) / (2.0 * step)
		var force := M.scale(column.slice(0, 3), 1.0 / mass)
		var moment := RB.inertia_mul(j_inv, column.slice(3, 6))
		columns.append(PackedFloat64Array([force[0], force[1], force[2], moment[0], moment[1], moment[2]]))
	var x := PackedFloat64Array([1.0, 0.7, 0.4, 0.9, 0.3, 0.6])
	var radius := 0.0
	for iteration in 300:
		var y := PackedFloat64Array([0, 0, 0, 0, 0, 0])
		for k in 6:
			for r in 6:
				y[r] += columns[k][r] * x[k]
		var norm := 0.0
		for v: float in y:
			norm += v * v
		norm = M.sqrt_(norm)
		if norm <= 0.0:
			return 0.0
		var x_norm := 0.0
		for v: float in x:
			x_norm += v * v
		radius = norm / M.sqrt_(x_norm)
		for r in 6:
			x[r] = y[r] / norm
	return radius


## GP-07c: whatever points touch, the contact damping and friction stay inside RK4's stable rate at the 240 Hz tick:
## a tip edge, the inverted fin and wing tops, a nose-in cluster, a tail-down cluster and the generator's worst
## direction, at the damping onset and deeper.
func _contact_rates(session: Node) -> void:
	var prepared: Dictionary = session._hull_contact
	var hull: PackedFloat64Array = session.aircraft.model.crash_hull
	var worst := 0.0
	var worst_case := ""
	var worst_friction := 0.0
	var friction_case := ""
	for pose: Array in [["left tip edge", 0.0, deg_to_rad(-75.0)], ["inverted", 0.0, PI], ["nose-in", deg_to_rad(-80.0), 0.0],
			["tail-down", deg_to_rad(70.0), 0.0], ["tip leading edge", deg_to_rad(-20.0), deg_to_rad(68.0)],
			["inverted nose-down", deg_to_rad(-15.0), PI]]:
		var q := M.q_from_euler(0.0, pose[1], pose[2])
		var lowest := -INF
		for i in range(0, hull.size(), 3):
			lowest = maxf(lowest, M.q_rotate(q, hull.slice(i, i + 3))[2])
		for depth: float in [0.002, 0.006, 0.02]:
			var s := RB.make_state(M.v3(0, 0, -lowest + depth), M.v3(0, 0, 0), q, M.v3(0, 0, 0))
			var rate := _contact_rate(prepared, s, session.sim.mass, session.sim.inertia)
			if rate > worst:
				worst = rate
				worst_case = "%s, %.0f mm" % [pose[0], 1000.0 * depth]
			# Friction alone: a horizontal (NED north) velocity change moves no point vertically, so only friction
			# answers; its rate on the whole mass is what several sliding points share.
			var step := 1.0e-5
			var plus := s.duplicate()
			var minus := s.duplicate()
			var dv := M.q_rotate(M.q_conj(q), M.v3(step, 0, 0))
			for axis in 3:
				plus[RB.VEL + axis] += dv[axis]
				minus[RB.VEL + axis] -= dv[axis]
			var lp := HullContact.loads(plus, prepared)
			var lm := HullContact.loads(minus, prepared)
			if lp.size() == 6 and lm.size() == 6:
				var df := M.q_rotate(q, PackedFloat64Array([lp[0] - lm[0], lp[1] - lm[1], lp[2] - lm[2]]))
				var friction_rate: float = absf(df[0]) / (2.0 * step * float(session.sim.mass))
				if friction_rate > worst_friction:
					worst_friction = friction_rate
					friction_case = "%s, %.0f mm" % [pose[0], 1000.0 * depth]
	_check("sliding points share the friction rate bound on the whole mass", worst_friction <= HullContact.FRICTION_RATE_MAX * (1.0 + 1e-6),
		"worst %.1f s⁻¹ (%s)" % [worst_friction, friction_case])
	_check("contact damping and friction stay inside RK4's stable rate (λ·dt ≤ %.1f) in every tested pose" % RATE_DT_LIMIT,
		worst * session.sim.dt() <= RATE_DT_LIMIT, "worst λ·dt %.2f (%s)" % [worst * session.sim.dt(), worst_case])


# --- GP-07d: presentation agrees -------------------------------------------------------------------------------------

func _presentation(table: Dictionary) -> void:
	for type: String in ["runway", "mown", "rough"]:
		_check("crash slide friction on %s equals the physics table" % type,
			Severity.SLIDE_FRICTION[type] == table[type].airframe_friction)
	_check("the grass aliases slide like the mown field", Severity.SLIDE_FRICTION.grass == table.mown.airframe_friction
		and Severity.SLIDE_FRICTION.mown_grass == table.mown.airframe_friction)
	_check("the runway strip is turf for impact transfer and rebound",
		Severity.SURFACE_TRANSFER.runway == Severity.SURFACE_TRANSFER.mown and Severity.SURFACE_RESTITUTION.runway == Severity.SURFACE_RESTITUTION.mown)


func _identity(session: Node) -> void:
	session.soft_hull_contacts = false
	session.reset()
	var legacy: String = session._checkpoint_configuration()
	var table: PackedFloat64Array = session.airframe_surfaces
	session.airframe_surfaces = PackedFloat64Array()
	_check("the airframe table stays out of the legacy configuration", session._checkpoint_configuration() == legacy)
	session.soft_hull_contacts = true
	var bare: String = session._checkpoint_configuration()
	session.airframe_surfaces = table
	_check("soft contacts hash the airframe table", session._checkpoint_configuration() != bare)
	_check("the soft law names the field friction and the rate bound", HullContact.law().contains("field-airframe-friction")
		and HullContact.law().contains("friction_rate_max=120"))
	session.soft_hull_contacts = false
	session.reset()


# --- Scenarios on the real tick --------------------------------------------------------------------------------------

## Body points (hull and wheels) of the session's airplane, flattened.
func _all_points(session: Node) -> PackedFloat64Array:
	var points: PackedFloat64Array = session.aircraft.model.crash_hull.duplicate()
	for contact: Dictionary in session.aircraft.model.landing_gear.contacts:
		points.append_array(contact.position)
	return points


func _place(session: Node, north: float, east: float, clearance: float, pitch: float, roll: float,
		v_ned: PackedFloat64Array) -> PackedFloat64Array:
	var q := M.q_from_euler(0.0, pitch, roll)
	var points := _all_points(session)
	var lowest := -INF
	for i in range(0, points.size(), 3):
		lowest = maxf(lowest, M.q_rotate(q, points.slice(i, i + 3))[2])
	return RB.make_state(M.v3(north, east, -(lowest + clearance)), M.q_rotate(M.q_conj(q), v_ned), q, M.v3(0, 0, 0))


func _run(session: Node, s: PackedFloat64Array, ticks: int) -> Dictionary:
	session.soft_hull_contacts = true
	session.reset()
	session.sim.reset(s)
	session.sim.set_paused(false)
	var touched: Dictionary = {}
	var first := -1
	var crashed := -1
	for t in ticks:
		session._physics_process(session.sim.dt())
		if not session.crash.is_empty():
			crashed = t
			break
		for contact: Dictionary in HullContact.contacts(session.sim.previous, session.sim.state, session._hull_contact):
			if first < 0:
				first = int(contact.index)
			touched[int(contact.index)] = true
		session.sim.step()
	return {first = first, crashed = crashed, touched = touched, state = session.sim.state.duplicate()}


func _tail_skid_strike(session: Node, field: Dictionary) -> void:
	# Over-rotation on the takeoff roll: mains on the strip, 16° nose-up (the skid touches beyond 13.3°), 12 m/s.
	var runway := _runway(field)
	var s := _place(session, float(runway.center_north), float(runway.center_east), 0.003, deg_to_rad(16.0), 0.0,
		M.v3(12, 0, 0.3))
	var run := _run(session, s, 96)
	var ids := _hull_ids()
	var names: PackedStringArray = session.aircraft.model.crash_hull_components
	var first_name: String = names[run.first] if run.first >= 0 else "none"
	_check("an over-rotated Stik scrapes its tail skid first", run.first >= 0 and first_name == "tail_end", first_name)
	_check("a tail-skid scrape is not a crash", run.crashed < 0, "crashed at tick %d" % run.crashed)
	session.soft_hull_contacts = false
	session.reset()
	_check("the first touch is the tail skid point", run.first >= 0 and run.first < ids.size() and ids[run.first] == "probe_tail_skid",
		ids[run.first] if run.first >= 0 and run.first < ids.size() else "none")


func _inverted_rest(session: Node, field: Dictionary) -> void:
	# A Stik dropped 1 cm upside down rests on its drawn fin and wing tops: no phantom fin, no creep.
	var runway := _runway(field)
	var s := _place(session, float(runway.center_north), float(runway.center_east), 0.01, 0.0, PI, M.v3(0, 0, 0))
	var run := _run(session, s, 720)
	_check("an inverted 1 cm drop is not a crash", run.crashed < 0, "crashed at tick %d" % run.crashed)
	var names: PackedStringArray = session.aircraft.model.crash_hull_components
	var labels := {}
	for index: int in run.touched:
		labels[names[index]] = true
	_check("it rests on the fin and both wing tips", labels.has("fin_top") and labels.has("left_wing_tip") and labels.has("right_wing_tip"),
		str(labels.keys()))
	var final: PackedFloat64Array = run.state
	var speed := M.norm(RB._slice3(final, RB.VEL))
	var rate := M.norm(RB._slice3(final, RB.RATE))
	_check("it settles (speed < 2 cm/s, rate < 0.05 rad/s after 3 s)", speed < 0.02 and rate < 0.05,
		"speed %.4f m/s, rate %.4f rad/s" % [speed, rate])
	var fin := names.find("fin_top")
	var hull: PackedFloat64Array = session.aircraft.model.crash_hull
	var fin_depth: float = final[RB.POS + 2] + M.q_rotate(RB._att(final), hull.slice(3 * fin, 3 * fin + 3))[2]
	_check("the drawn fin top is at the ground (within the contact's sag)", fin_depth > -0.002 and fin_depth < 0.01,
		"%.1f mm" % (1000.0 * fin_depth))
	session.soft_hull_contacts = false
	session.reset()


## GP-07c: a soft-contact flight on the field, logged and replayed exactly from its own header (the airframe table
## travels in the log; a replay without it is refused by the configuration identity).
func _soft_log_replay(session: Node, field: Dictionary) -> void:
	var runway := _runway(field)
	var s := _place(session, float(runway.center_north), float(runway.center_east), 0.004, 0.0, deg_to_rad(-62.0),
		M.v3(9, 0, 0.4))
	session.soft_hull_contacts = true
	session.reset()
	session.sim.reset(s)
	var path := ProjectSettings.globalize_path("res://../tmp/gp07-soft-log-%d.orfl" % Time.get_ticks_usec())
	var logger := Log.new(session)
	_check("a soft-contact log starts on the field", logger.start(path) == OK)
	var touched := false
	for tick in 120:
		session.sim.step()
		touched = touched or not HullContact.contacts(session.sim.previous, session.sim.state, session._hull_contact).is_empty()
	_check("the logged flight scrapes the strip", touched)
	_check("the log stops", logger.stop() == OK)
	var read: Dictionary = Reader.inspect(path)
	_check("the soft log is accepted", read.get("ok", false), str(read.get("error", "")))
	if not read.get("ok", false):
		return
	_check("the header carries the airframe table", read.header.get("airframe_surfaces", PackedFloat64Array()) == session.airframe_surfaces
		and not session.airframe_surfaces.is_empty())
	var replay: Dictionary = Reader.prepare_replay(read.header)
	_check("exact replay of a soft-contact field log prepares", replay.get("ok", false), str(replay.get("error", "")))
	if replay.get("ok", false):
		var stream := FileAccess.open(path, FileAccess.READ)
		stream.seek(8)
		Log.read_packet(stream)
		var first := true
		var observer := Log.new(replay.flight)
		var exact := true
		var rows := 0
		while stream.get_position() < stream.get_length():
			var block: Dictionary = Log.read_packet(stream).value
			if block.kind == "footer":
				break
			for row: Dictionary in block.rows:
				if first:
					first = false
					continue
				for key in row.intervention:
					replay.flight.sim.set(key, row.intervention[key].duplicate())
				replay.flight.sim.inputs = row.inputs.duplicate()
				replay.flight.sim.step()
				exact = exact and Reader.disagreement(row, observer._sample({})).is_empty()
				rows += 1
		stream.close()
		_check("the soft-contact field log replays exactly", exact and rows == 120, "%d rows" % rows)
		replay.flight.free()
	DirAccess.remove_absolute(path)
	session.soft_hull_contacts = false
	session.reset()
