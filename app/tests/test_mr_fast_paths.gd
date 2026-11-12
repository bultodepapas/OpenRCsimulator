# DR-22/R1: the FPV quad's behaviour-preserving fast paths, each against the code it replaced, bit for bit.
# 1. Obstacle broad phase: the session's indexed obstacle query returns exactly what the former fresh
#    CollisionWorld.nearby query returned on the shipped default field (seeded points over the inventory, around
#    every proxy's box and edges, on index cell borders, several reaches, non-finite input), and is faster.
# 2. Contact loads: the plant's scalar _contact_loads equals the former M.* vector form (kept below verbatim) on
#    seeded states resting, sliding, tumbling and plunging into the default field's terrain, and is faster.
# 3. Contact terrain law: the plant's linearized, memoized terrain is pure (memo and order never change a value)
#    and stays within a hair of the exact field sample.
# 4. Contact substep policy (DR-18-R1, a declared physics change): one piece only for a parked quad, and a contact
#    too stiff for one parked piece is never parked.
# Headless software checks; no physical claim.
extends SceneTree

const Session := preload("res://sim/multirotor/session.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const Catalog := preload("res://vehicles/multirotor/multirotor_catalog.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")
const Terrain := preload("res://physics/ground_terrain.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const Rates := preload("res://physics/multirotor/rates.gd")

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


## The former query (DR-19 obstacle strike), kept here as the reference.
static func _reference(world: Dictionary, reach: float, north: float, east: float, down: float) -> float:
	var nearest := reach
	for proxy: Dictionary in CollisionWorld.nearby(world, north, east, down, reach):
		nearest = minf(nearest, Session._clearance(proxy, north, east, down))
	return nearest


static func _same(a: float, b: float) -> bool:
	return var_to_bytes(a) == var_to_bytes(b)


## The former vector form of ControlledPlant._contact_loads (DR-18…20), verbatim, as the reference.
static func _contact_reference(plant: RefCounted, body: PackedFloat64Array, attitude: PackedFloat64Array,
		velocity: PackedFloat64Array, rates: PackedFloat64Array) -> Dictionary:
	var force: PackedFloat64Array = M.v3(0.0, 0.0, 0.0)
	var moment: PackedFloat64Array = M.v3(0.0, 0.0, 0.0)
	var under: PackedFloat64Array = plant._ground_at(body[RB.POS], body[RB.POS + 1])
	if -body[RB.POS + 2] - under[0] > Plant.CONTACT_REACH:
		return {force = force, moment = moment}
	var contacts: Dictionary = plant.prepared.contacts
	var stiffness: float = contacts.stiffness_n_per_m
	var damping: float = contacts.damping_n_s_per_m
	var friction: float = contacts.friction
	var inverse: PackedFloat64Array = M.q_conj(attitude)
	for point: PackedFloat64Array in plant._points:
		var offset: PackedFloat64Array = M.q_rotate(attitude, point)
		var north: float = body[RB.POS] + offset[0]
		var east: float = body[RB.POS + 1] + offset[1]
		var surface: PackedFloat64Array = plant._ground_at(north, east)
		var depth: float = body[RB.POS + 2] + offset[2] + surface[0]
		if depth <= 0.0:
			continue
		var normal: PackedFloat64Array = Terrain.normal_from_up_slopes(surface[1], surface[2])
		var v_world: PackedFloat64Array = M.q_rotate(attitude, M.add(velocity, M.cross(rates, point)))
		var along: float = M.dot(v_world, normal)
		var load: float = maxf(0.0, stiffness * depth * -normal[2] - damping * along)
		if load <= 0.0:
			continue
		var tangential: PackedFloat64Array = M.sub(v_world, M.scale(normal, along))
		var slip: float = M.norm(tangential)
		var f_world: PackedFloat64Array = M.add(M.scale(normal, load), M.scale(tangential, -friction * load / (slip + Plant.FRICTION_CREEP)))
		var f_body: PackedFloat64Array = M.q_rotate(inverse, f_world)
		force = M.add(force, f_body)
		moment = M.add(moment, M.cross(point, f_body))
	return {force = force, moment = moment}


## 3. The contact terrain law (Session.contact_ground): a pure function of position, whatever its memo holds or the
## query order, and within a hair of the exact field sample (heights 1e-7 m, slopes 1e-3) over the default field.
func _terrain(field: Dictionary) -> void:
	var s: Node = Session.new()
	root.add_child(s)
	if not s.prepare(field, {data_path = Catalog.DATA_PATH, throttle_policy = "absolute", start = "pad"}):
		_check("the shipped quad prepares on the default field", false, str(s.load_error))
		return
	var env: RefCounted = s.environment
	var pad: PackedFloat64Array = s.sim.state
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026_11_12_3
	var points: Array[Vector2] = []
	for i in 3000:
		points.append(Vector2(pad[0] + rng.randf_range(-0.2, 0.2), pad[1] + rng.randf_range(-0.2, 0.2)))
	for i in 3000:
		points.append(Vector2(rng.randf_range(-400.0, 400.0), rng.randf_range(-400.0, 400.0)))
	var a: Callable = Session.contact_ground(env)
	var b: Callable = Session.contact_ground(env)
	# Warm b's memo with unrelated squares and past its bound (it clears), then query in reverse order.
	for i in Session.TERRAIN_MEMO_MAX + 100:
		b.call(rng.randf_range(-300.0, 300.0), rng.randf_range(-300.0, 300.0))
	var forward: Array[PackedFloat64Array] = []
	for p: Vector2 in points:
		forward.append(a.call(p.x, p.y))
	var pure := true
	for i in range(points.size() - 1, -1, -1):
		if var_to_bytes(b.call(points[i].x, points[i].y)) != var_to_bytes(forward[i]):
			pure = false
	_check("the contact terrain law does not depend on its memo or the query order", pure)
	var worst_h := 0.0
	var worst_slope := 0.0
	for i in points.size():
		var exact: PackedFloat64Array = env.ground(points[i].x, points[i].y)
		worst_h = maxf(worst_h, absf(forward[i][0] - exact[0]))
		worst_slope = maxf(worst_slope, maxf(absf(forward[i][1] - exact[1]), absf(forward[i][2] - exact[2])))
	_check("the linearized contact terrain stays within 1e-7 m and 1e-3 of the exact sample", worst_h < 1.0e-7
		and worst_slope < 1.0e-3, "height %s m, slope %s" % [String.num_scientific(worst_h), String.num_scientific(worst_slope)])
	var far: PackedFloat64Array = a.call(2.0e5, 0.0)
	_check("beyond the memo reach and for non-finite input the exact sample is used",
		var_to_bytes(far) == var_to_bytes(env.ground(2.0e5, 0.0)) and is_nan(a.call(NAN, 0.0)[0]))
	s.queue_free()


## 4. DR-18-R1 contact substep policy: one piece only for a parked quad (near the ground, still, rotors stopped),
## four pieces for turning rotors either way, motion, rates or non-finite state, one piece in free flight; and a
## contact too stiff for one parked piece is never parked.
func _substeps(field: Dictionary) -> void:
	var s: Node = Session.new()
	root.add_child(s)
	if not s.prepare(field, {data_path = Catalog.DATA_PATH, throttle_policy = "absolute", start = "pad"}):
		_check("the shipped quad prepares on the default field", false, str(s.load_error))
		return
	var plant: RefCounted = s.plant
	var body: PackedFloat64Array = s.sim.state.duplicate()
	var stopped := PackedFloat64Array(s.sim.continuous)
	for i in 4:
		stopped[i] = 0.0
	var pieces := func(b: PackedFloat64Array, c: PackedFloat64Array) -> int: return plant.substeps(b, c, 0.0)
	_check("the shipped quad's parked contact admits one piece (h|λ| %.2f <= %.1f)" % [plant.parked_one_piece_h_lambda,
		Plant.PARKED_H_LAMBDA_LIMIT], plant.parked_one_piece_h_lambda <= Plant.PARKED_H_LAMBDA_LIMIT)
	var turning := stopped.duplicate()
	turning[2] = 300.0
	var reverse := stopped.duplicate()
	reverse[1] = -300.0
	var sliding := body.duplicate()
	sliding[RB.VEL] = 0.3
	var rolling := body.duplicate()
	rolling[RB.RATE] = 0.6
	var broken := body.duplicate()
	broken[RB.VEL + 2] = NAN
	var lifted := body.duplicate()
	lifted[RB.POS + 2] -= 0.5
	_check("parked on the pad: one piece", pieces.call(body, stopped) == 1)
	_check("armed idle (a rotor turning either way): four pieces", pieces.call(body, turning) == 4
		and pieces.call(body, reverse) == 4)
	_check("sliding, rolling or a non-finite state on the pad: four pieces", pieces.call(sliding, stopped) == 4
		and pieces.call(rolling, stopped) == 4 and pieces.call(broken, stopped) == 4)
	_check("free flight, rotors stopped or turning: one piece", pieces.call(lifted, stopped) == 1
		and pieces.call(lifted, turning) == 1)
	var stiff: Dictionary = s.data.duplicate(true)
	stiff.contacts.friction = 3.0
	var made: Dictionary = Plant.create(stiff, Rates.default_profile(), FC.THROTTLE_ABSOLUTE)
	var flat := body.duplicate()
	flat[RB.POS] = 0.0
	flat[RB.POS + 1] = 0.0
	flat[RB.POS + 2] = -0.03 # flat fixture ground (no terrain callable) at down 0
	_check("a contact too stiff for one parked piece is never parked", made.ok
		and made.plant.parked_one_piece_h_lambda > Plant.PARKED_H_LAMBDA_LIMIT
		and made.plant.substeps(flat, stopped, 0.0) == 4, "h|λ| %s" % [made.plant.parked_one_piece_h_lambda if made.ok else made.errors])
	s.queue_free()


func _contact(field: Dictionary) -> void:
	var s: Node = Session.new()
	root.add_child(s)
	if not s.prepare(field, {data_path = Catalog.DATA_PATH, throttle_policy = "absolute", start = "pad"}):
		_check("the shipped quad prepares on the default field", false, str(s.load_error))
		return
	var plant: RefCounted = s.plant
	var pad: PackedFloat64Array = s.sim.state.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026_11_12_2
	var mismatches := 0
	var first := ""
	var in_contact := 0
	var reference_us := 0
	var scalar_us := 0
	for i in 20000:
		var kind := i % 4
		var body := pad.duplicate()
		var spread: float = [0.0, 0.02, 0.6, 0.15][kind]
		body[RB.POS] += rng.randf_range(-40.0, 40.0) if kind == 2 else rng.randf_range(-spread, spread)
		body[RB.POS + 1] += rng.randf_range(-40.0, 40.0) if kind == 2 else rng.randf_range(-spread, spread)
		body[RB.POS + 2] += rng.randf_range(-0.05, 0.05) if kind != 3 else rng.randf_range(-0.3, 0.12)
		var tilt: float = [1.0e-5, 0.05, 0.6, 3.0][kind]
		var q := M.q_normalized(M.quat(body[RB.ATT] + rng.randf_range(-tilt, tilt), body[RB.ATT + 1] + rng.randf_range(-tilt, tilt),
			body[RB.ATT + 2] + rng.randf_range(-tilt, tilt), body[RB.ATT + 3] + rng.randf_range(-tilt, tilt)))
		var speed: float = [1.0e-6, 0.5, 3.0, 8.0][kind]
		var velocity := M.v3(rng.randf_range(-speed, speed), rng.randf_range(-speed, speed), rng.randf_range(-speed, speed))
		var rate: float = [1.0e-6, 0.3, 4.0, 20.0][kind]
		var rates := M.v3(rng.randf_range(-rate, rate), rng.randf_range(-rate, rate), rng.randf_range(-rate, rate))
		var t0 := Time.get_ticks_usec()
		var expected: Dictionary = _contact_reference(plant, body, q, velocity, rates)
		var t1 := Time.get_ticks_usec()
		var got: Dictionary = plant._contact_loads(body, q, velocity, rates)
		var t2 := Time.get_ticks_usec()
		reference_us += t1 - t0
		scalar_us += t2 - t1
		if M.norm(expected.force) > 0.0:
			in_contact += 1
		if var_to_bytes(expected) != var_to_bytes(got):
			mismatches += 1
			if first.is_empty():
				first = "state %d: %s against %s" % [i, got, expected]
	_check("scalar contact loads equal the vector form bit for bit (20000 states, %d in contact)" % in_contact,
		mismatches == 0 and in_contact > 5000, first)
	_check("scalar contact loads are faster", scalar_us < reference_us, "%d us against %d us" % [scalar_us, reference_us])
	s.queue_free()


func _run() -> void:
	var field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field
	var built: Dictionary = CollisionSetup.build(field)
	_check("the default field's obstacle inventory builds", built.ok and not built.world.proxies.is_empty())
	var world: Dictionary = built.world
	var points: Array[PackedFloat64Array] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026_11_12
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for proxy: Dictionary in world.proxies:
		lo = lo.min(Vector3(proxy.bounds_north_min, proxy.bounds_east_min, proxy.bounds_down_min))
		hi = hi.max(Vector3(proxy.bounds_north_max, proxy.bounds_east_max, proxy.bounds_down_max))
		# Around each box: inside, on the faces and just beyond them (the AABB-sphere decision boundary).
		for k in 6:
			var n := rng.randf_range(float(proxy.bounds_north_min) - 1.5, float(proxy.bounds_north_max) + 1.5)
			var e := rng.randf_range(float(proxy.bounds_east_min) - 1.5, float(proxy.bounds_east_max) + 1.5)
			var d := rng.randf_range(float(proxy.bounds_down_min) - 1.5, float(proxy.bounds_down_max) + 1.5)
			points.append(PackedFloat64Array([n, e, d]))
		points.append(PackedFloat64Array([float(proxy.bounds_north_min), float(proxy.bounds_east_max), float(proxy.bounds_down_min)]))
	for i in 6000:
		points.append(PackedFloat64Array([rng.randf_range(lo.x - 5.0, hi.x + 5.0), rng.randf_range(lo.y - 5.0, hi.y + 5.0),
			rng.randf_range(lo.z - 2.0, hi.z + 2.0)]))
	# Index cell borders (and one ulp either side) near the pad and the pilot station.
	var cell: float = Session.OBSTACLE_INDEX_CELL_M
	for i in 400:
		var n := floorf(rng.randf_range(lo.x, hi.x) / cell) * cell
		var e := floorf(rng.randf_range(lo.y, hi.y) / cell) * cell
		for dn: float in [0.0, 1.0e-12, -1.0e-12]:
			points.append(PackedFloat64Array([n + dn, e - dn, rng.randf_range(-3.0, 0.5)]))
	var mismatches := 0
	var first := ""
	var hits := 0
	var reference_us := 0
	var indexed_us := 0
	for reach: float in [0.05, 0.6608, 1.5, 4.0]:
		var query: Callable = Session._obstacle_query(world, [], reach)
		for p: PackedFloat64Array in points:
			var t0 := Time.get_ticks_usec()
			var expected := _reference(world, reach, p[0], p[1], p[2])
			var t1 := Time.get_ticks_usec()
			var got: float = query.call(p[0], p[1], p[2])
			var t2 := Time.get_ticks_usec()
			reference_us += t1 - t0
			indexed_us += t2 - t1
			if expected < reach:
				hits += 1
			if not _same(expected, got):
				mismatches += 1
				if first.is_empty():
					first = "reach %s at %s: %s against %s" % [reach, p, got, expected]
	_check("the indexed query equals the fresh nearby query bit for bit (%d queries, %d within reach)" % [
		4 * points.size(), hits], mismatches == 0 and hits > 1000, first)
	_check("the indexed query is at least 3x faster", indexed_us * 3 < reference_us,
		"%d us against %d us" % [indexed_us, reference_us])
	var query: Callable = Session._obstacle_query(world, [], 0.6608)
	_check("non-finite input returns the reach, as the fresh query did",
		_same(query.call(NAN, 0.0, 0.0), 0.6608) and _same(query.call(0.0, INF, 0.0), 0.6608)
		and _same(_reference(world, 0.6608, NAN, 0.0, 0.0), 0.6608))
	var empty: Callable = Session._obstacle_query({}, [], 0.6608)
	_check("an empty inventory leaves the reach", _same(empty.call(0.0, 0.0, 0.0), 0.6608))
	_contact(field)
	_terrain(field)
	_substeps(field)
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
