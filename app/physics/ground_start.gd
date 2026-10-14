# E3b2: a runway start in static equilibrium (pure; 64-bit floats only, guarded).
# Stage 1, engine off: on the gear at a fixed spot and heading, solve height, roll and pitch so the vertical force and
# the moments about the two horizontal axes vanish (every force is vertical: weight and gear springs). The wheels then
# stick where they stand: the anchors (E3b1) go to the wheels' ground points.
# Stage 2, engine idling: with those anchors fixed, solve all six pose values so every body acceleration vanishes at
# zero velocity. The airplane leans on its anchors by the idle thrust's deflection (about 2.4 mm for the Stik), exactly
# as if it had been placed, its wheels had stuck and the engine had then come up to idle slowly.
# Newton's method on a central-difference Jacobian; no state, no RK4. Not a trim of flight: aero at zero airspeed is zero.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const GroundTerrain := preload("res://physics/ground_terrain.gd")
const GroundEffect := preload("res://physics/ground_effect.gd")
const Ground := preload("res://physics/ground_contact.gd")
const RetractableGear := preload("res://physics/retractable_gear.gd")
const Air := preload("res://physics/air_data.gd")

## Residual accelerations (m/s², rad/s²) below which the pose counts as solved.
const TOLERANCE := 1e-11
const MAX_ITERATIONS := 40
## Central-difference step for the Jacobian (m and rad).
const STEP := 1e-6
## E3b2 default line-up: the CG this far inside the runway's end (m, estimated: a few metres, so the tail is on it).
const LINEUP := 3.0


## The start spot at a runway end, facing along the runway. `field` is a loaded field (FieldLoader); east_bound starts
## at the west end heading east. Returns { ok, north, east, heading (rad, 0 = north, π/2 = east), message }.
static func threshold(field: Dictionary, east_bound := true, lineup := LINEUP) -> Dictionary:
	for s in field.get("surfaces", []):
		if s.get("type", "") == "runway":
			var half: float = float(s.length_east_west) / 2.0
			var center_east: float = s.center_east
			return { ok = true, north = float(s.center_north), east = center_east - half + lineup if east_bound else center_east + half - lineup,
				heading = PI / 2.0 if east_bound else -PI / 2.0, message = "" }
	return { ok = false, north = 0.0, east = 0.0, heading = 0.0, message = "field has no runway" }


## Solve the start. model: AircraftData model with stiction gear; surfaces: the field's surface table; d: aerodynamic
## deflections (radians, Aero convention); steer: the rudder servo position (nose wheel); rpm: the idling engine.
## Returns { ok, state (13), anchors (ANCHOR_STRIDE per contact, all stuck), rest_state (engine off), iterations,
## residual, message }. Requires a structurally valid AircraftData model and GroundSurfaces table.
static func solve(model: Dictionary, surfaces: PackedFloat64Array, north: float, east: float, heading: float,
		d: Dictionary, steer: float, rpm: float, rho: float, g: float,
		wind_ned: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0]), enhanced := false) -> Dictionary:
	if wind_ned.size() != 3:
		return _fail("runway start needs three NED wind components")
	for value: float in wind_ned:
		if not is_finite(value):
			return _fail("runway start needs finite NED wind")
	for value in [north, east, heading, steer, rpm, rho, g]:
		if not is_finite(value):
			return _fail("runway start needs finite position, heading, controls, rpm, density and gravity")
	if rpm < 0.0 or rho < 0.0 or g <= 0.0:
		return _fail("runway start needs nonnegative rpm/density and positive gravity")
	for axis in ["elevator", "aileron_left", "aileron_right", "rudder"]:
		var angle: Variant = d.get(axis)
		if (typeof(angle) != TYPE_FLOAT and typeof(angle) != TYPE_INT) or not is_finite(angle):
			return _fail("runway start needs a finite " + axis + " deflection")
	var gear: Dictionary = model.get("landing_gear", {})
	if gear.is_empty() or not gear.has("breakaway_factor"):
		return _fail("runway start needs landing gear with stiction data (breakaway_factor)")
	var inv := RB.inertia_inverse(model.inertia)
	var free := PackedFloat64Array()
	free.resize(gear.contacts.size() * Ground.ANCHOR_STRIDE)
	# Stage 1: engine off, no tangential force; unknowns down, roll, pitch.
	var lowest := 0.0 # deepest contact below the CG (body z, down)
	var support_pose: Dictionary = _aft_tricycle_support_pose(gear.contacts)
	if support_pose.is_empty():
		# Keep the established seed for nose-wheel aircraft and geometries without a three-point support plane.
		for c in gear.contacts:
			lowest = maxf(lowest, float(c.position[2]))
	else:
		lowest = maxf(0.0, float(support_pose.support_down))
	var pose := PackedFloat64Array([north, east, -(lowest - float(gear.static_sag)), 0.0, 0.0, heading])
	if not support_pose.is_empty():
		pose[3] = float(support_pose.roll)
		pose[4] = float(support_pose.pitch)
	var rest_residual := func(x: PackedFloat64Array) -> PackedFloat64Array:
		var p := PackedFloat64Array([north, east, x[0], x[1], x[2], heading])
		var a := _accelerations(_state(p), model, inv, gear, surfaces, d, steer, 0.0, rho, g, free, false, wind_ned, enhanced)
		# World-frame vertical acceleration and angular accelerations about north and east.
		var q := _quat(p)
		var lin := M.q_rotate(q, M.v3(a[0], a[1], a[2]))
		var ang := M.q_rotate(q, M.v3(a[3], a[4], a[5]))
		return PackedFloat64Array([lin[2], ang[0], ang[1]])
	var rest := _newton(rest_residual, PackedFloat64Array([pose[2], pose[3], pose[4]]))
	if not rest.ok:
		return _fail("engine-off rest pose did not converge (residual %s)" % String.num_scientific(rest.residual))
	pose[2] = rest.x[0]
	pose[3] = rest.x[1]
	pose[4] = rest.x[2]
	var rest_state := _state(pose)
	var anchors := Ground.anchor_step(rest_state, gear, steer, surfaces, free, enhanced)
	for i in gear.contacts.size():
		if anchors[i * Ground.ANCHOR_STRIDE + 2] != 1.0:
			return _fail("contact %d does not touch the ground at rest" % i)
	# Stage 2: engine idling, anchors fixed; all six pose values.
	var idle_residual := func(x: PackedFloat64Array) -> PackedFloat64Array:
		return _accelerations(_state(x), model, inv, gear, surfaces, d, steer, rpm, rho, g, anchors, true, wind_ned, enhanced)
	var idle := _newton(idle_residual, pose)
	if not idle.ok:
		return _fail("idling pose did not converge (residual %s)" % String.num_scientific(idle.residual))
	var state := _state(idle.x)
	if not _finite_size(state, 13) or not _finite_size(rest_state, 13) or not _finite_size(anchors, free.size()):
		return _fail("nonfinite runway start state or anchors")
	if Ground.anchor_step(state, gear, steer, surfaces, anchors, enhanced) != anchors:
		return _fail("idle thrust exceeds the wheels' static hold: the airplane would roll")
	return { ok = true, state = state, anchors = anchors, rest_state = rest_state, iterations = rest.iterations + idle.iterations,
		residual = idle.residual, message = "" }


## Seed an aft third contact from the rigid plane through two lateral main contacts and the aft wheel.
## Nose-wheel aircraft retain the original level seed. Positions are AircraftData body-FRD coordinates.
static func _aft_tricycle_support_pose(contacts: Array) -> Dictionary:
	if contacts.size() != 3:
		return {}
	var positions: Array[PackedFloat64Array] = []
	for contact: Dictionary in contacts:
		var value: Variant = contact.get("position")
		if typeof(value) != TYPE_PACKED_FLOAT64_ARRAY or value.size() != 3:
			return {}
		positions.append(value)
	var pair_a := -1
	var pair_b := -1
	var widest := 0.0
	for i in positions.size():
		for j in range(i + 1, positions.size()):
			var lateral_width: float = absf(positions[i][1] - positions[j][1])
			if lateral_width > widest:
				widest = lateral_width
				pair_a = i
				pair_b = j
	if pair_a < 0 or pair_b < 0:
		return {}
	var aft := 3 - pair_a - pair_b
	var axle_x: float = 0.5 * (positions[pair_a][0] + positions[pair_b][0])
	if positions[aft][0] >= axle_x:
		return {} # The lone contact is ahead of the main axle (a nose wheel).
	var lateral_edge: PackedFloat64Array = M.sub(positions[pair_b], positions[pair_a])
	var aft_edge: PackedFloat64Array = M.sub(positions[aft], positions[pair_a])
	var normal: PackedFloat64Array = M.cross(lateral_edge, aft_edge)
	var normal_length: float = M.norm(normal)
	if not is_finite(normal_length) or normal_length <= 1e-9:
		return {}
	normal = M.scale(normal, 1.0 / normal_length)
	if normal[2] < 0.0:
		normal = M.scale(normal, -1.0)
	if normal[2] <= 1e-6:
		return {}
	var pitch: float = M.atan2_(-normal[0], M.sqrt_(normal[1] * normal[1] + normal[2] * normal[2]))
	var roll: float = M.atan2_(normal[1], normal[2])
	var support_down := -INF
	for position: PackedFloat64Array in positions:
		support_down = maxf(support_down, M.dot(normal, position))
	return { pitch = pitch, roll = roll, support_down = support_down }


## Body accelerations [u̇, v̇, ẇ, ṗ, q̇, ṙ] at state s (zero velocity and rates) from aero, propulsion (when running)
## and the gear with the given anchors.
static func _accelerations(s: PackedFloat64Array, model: Dictionary, inv: PackedFloat64Array, gear: Dictionary,
		surfaces: PackedFloat64Array, d: Dictionary, steer: float, rpm: float, rho: float, g: float,
		anchors: PackedFloat64Array, engine: bool,
		wind_ned: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0]), enhanced := false) -> PackedFloat64Array:
	var loads := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	if engine or wind_ned[0] != 0.0 or wind_ned[1] != 0.0 or wind_ned[2] != 0.0:
		# M5-GE-1: on the runway the session evaluates aero with the terrain height under the CG; the static solve must
		# see the same ground (zero airspeed gives zero aero either way; wind does not).
		var ground_up: float = GroundTerrain.sample_validated(s[RB.POS], s[RB.POS + 1], surfaces)[0] \
			if GroundEffect.enabled(model) else NAN
		loads = Dynamics.loads(s, model, d, rpm if engine else 0.0, rho, wind_ned, NAN, PackedFloat64Array(), ground_up)
		if RetractableGear.enabled(gear):
			var drag := RetractableGear.drag_loads(s, Air.compute(s, wind_ned, rho).v_air, gear, 1.0, rho)
			for i in drag.size(): loads[i] += drag[i]
	var wheels := PackedFloat64Array()
	if enhanced:
		wheels.resize(gear.contacts.size())
	var ground := Ground.loads(s, gear, steer, surfaces, anchors, wheels)
	for i in ground.size():
		loads[i] += ground[i]
	var derivative := RB.derivative(s, model.mass_kg, model.inertia, inv, M.v3(loads[0], loads[1], loads[2]),
		M.v3(loads[3], loads[4], loads[5]), g, Dynamics.rotor_momentum(model, rpm) if engine else PackedFloat64Array())
	return PackedFloat64Array([derivative[RB.VEL], derivative[RB.VEL + 1], derivative[RB.VEL + 2],
		derivative[RB.RATE], derivative[RB.RATE + 1], derivative[RB.RATE + 2]])


## Pose [north, east, down, roll, pitch, yaw] → state at rest.
static func _state(p: PackedFloat64Array) -> PackedFloat64Array:
	var q := _quat(p)
	return PackedFloat64Array([p[0], p[1], p[2], 0.0, 0.0, 0.0, q[0], q[1], q[2], q[3], 0.0, 0.0, 0.0])


static func _quat(p: PackedFloat64Array) -> PackedFloat64Array:
	return M.q_from_euler(p[5], p[4], p[3])


## Newton's method with a central-difference Jacobian and partial-pivot elimination.
static func _newton(residual: Callable, x0: PackedFloat64Array) -> Dictionary:
	var x := x0.duplicate()
	var n := x.size()
	var iterations := 0
	if n == 0 or not _finite_size(x, n):
		return { ok = false, x = x, residual = INF, iterations = iterations }
	var r: PackedFloat64Array = residual.call(x)
	var norm := _norm(r) if r.size() == n else INF
	while is_finite(norm) and norm > TOLERANCE and iterations < MAX_ITERATIONS:
		var jacobian := PackedFloat64Array()
		jacobian.resize(n * n)
		for j in n:
			var plus := x.duplicate()
			var minus := x.duplicate()
			plus[j] += STEP
			minus[j] -= STEP
			var rp: PackedFloat64Array = residual.call(plus)
			var rm: PackedFloat64Array = residual.call(minus)
			if not _finite_size(rp, n) or not _finite_size(rm, n):
				return { ok = false, x = x, residual = INF, iterations = iterations }
			for i in n:
				jacobian[i * n + j] = (rp[i] - rm[i]) / (2.0 * STEP)
		var dx := _linear_solve(jacobian, r, n)
		if dx.is_empty():
			break
		for i in n:
			x[i] -= dx[i]
		if not _finite_size(x, n):
			return { ok = false, x = x, residual = INF, iterations = iterations }
		r = residual.call(x)
		norm = _norm(r) if r.size() == n else INF
		iterations += 1
	return { ok = is_finite(norm) and norm <= TOLERANCE, x = x, residual = norm, iterations = iterations }


static func _finite_size(values: PackedFloat64Array, size: int) -> bool:
	if values.size() != size:
		return false
	for value in values:
		if not is_finite(value):
			return false
	return true


static func _norm(v: PackedFloat64Array) -> float:
	if v.is_empty():
		return INF
	var worst := 0.0
	for value in v:
		if not is_finite(value):
			return INF
		worst = maxf(worst, absf(value))
	return worst


## Solve A·x = b (A row-major n×n). Empty for malformed, singular or nonfinite systems, including overflow.
static func _linear_solve(a_in: PackedFloat64Array, b_in: PackedFloat64Array, n: int) -> PackedFloat64Array:
	if n <= 0 or n > a_in.size() or a_in.size() != n * n or not _finite_size(a_in, a_in.size()) or not _finite_size(b_in, n):
		return PackedFloat64Array()
	var a := a_in.duplicate()
	var b := b_in.duplicate()
	for col in n:
		var pivot := col
		for row in range(col + 1, n):
			if absf(a[row * n + col]) > absf(a[pivot * n + col]):
				pivot = row
		if absf(a[pivot * n + col]) < 1e-300:
			return PackedFloat64Array()
		if pivot != col:
			for k in n:
				var t := a[col * n + k]
				a[col * n + k] = a[pivot * n + k]
				a[pivot * n + k] = t
			var tb := b[col]
			b[col] = b[pivot]
			b[pivot] = tb
		for row in range(col + 1, n):
			var f := a[row * n + col] / a[col * n + col]
			if not is_finite(f):
				return PackedFloat64Array()
			for k in range(col, n):
				a[row * n + k] -= f * a[col * n + k]
				if not is_finite(a[row * n + k]):
					return PackedFloat64Array()
			b[row] -= f * b[col]
			if not is_finite(b[row]):
				return PackedFloat64Array()
	var x := PackedFloat64Array()
	x.resize(n)
	for row in range(n - 1, -1, -1):
		var acc := b[row]
		for k in range(row + 1, n):
			acc -= a[row * n + k] * x[k]
			if not is_finite(acc):
				return PackedFloat64Array()
		x[row] = acc / a[row * n + row]
		if not is_finite(x[row]):
			return PackedFloat64Array()
	return x


static func _fail(message: String) -> Dictionary:
	return { ok = false, state = PackedFloat64Array(), anchors = PackedFloat64Array(), rest_state = PackedFloat64Array(),
		iterations = 0, residual = INF, message = message }
