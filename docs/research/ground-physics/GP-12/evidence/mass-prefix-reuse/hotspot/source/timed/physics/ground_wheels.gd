# GP-02: dissipative wheel/terrain contact. Rim speeds are RK4 continuous state, m/s.
# Geometry and rigid-body state are float64; no mutable cache or random forcing.
extends RefCounted
const Timing:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/metrics.gd")

const M := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/physics/math3d.gd")
const RB := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/physics/rigid_body.gd")
const Terrain := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/physics/ground_terrain.gd")
const LakeSurface := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/physics/lake_surface.gd")
const REFERENCE_RADIUS := 0.0381
const STRIDE := 6
const STICK_SPEED := 0.02
const SLIP_REFERENCE_SPEED := 1.0 # m/s: converts the load-limited slip slope to N/(m/s).
const ROLLING_LAW := "wheel-positive-terrain-excess-v2"


static func surface_at(table: PackedFloat64Array, north: float, east: float) -> int:
	var at := 0
	while at + STRIDE < table.size():
		if north >= table[at] and north <= table[at + 1] and east >= table[at + 2] and east <= table[at + 3]:
			return at
		at += STRIDE
	return at


static func _damping(contact: Dictionary, compression: float) -> float:
	var onset: float = contact.get("damping_onset", 0.0)
	if compression >= onset:
		return contact.damping
	var x := compression / onset
	return contact.damping * x * (2.0 - x)


# Each frame is evaluated at this RK stage, including terrain slope and contact velocity.
static func frame(s: PackedFloat64Array, c: Dictionary, steer: float, surfaces: PackedFloat64Array,
		rotation := PackedFloat64Array(), surfaces_validated := false, lake: Dictionary = {}) -> Dictionary:
	var a := _rotation(s) if rotation.is_empty() else rotation
	var r: PackedFloat64Array = c.position
	var p := PackedFloat64Array([s[0] + a[0] * r[0] + a[1] * r[1] + a[2] * r[2],
		s[1] + a[3] * r[0] + a[4] * r[1] + a[5] * r[2],
		s[2] + a[6] * r[0] + a[7] * r[1] + a[8] * r[2]])
	var terrain := Terrain.sample_validated(p[0], p[1], surfaces, lake) if surfaces_validated else Terrain.sample(p[0], p[1], surfaces, lake)
	var norm := M.sqrt_(1.0 + terrain[1] * terrain[1] + terrain[2] * terrain[2])
	var normal := Terrain.normal_from_up_slopes(terrain[1], terrain[2])
	if normal.is_empty():
		# Preserve fail-closed propagation to the stage validity guard.
		normal = PackedFloat64Array([NAN, NAN, NAN])
	var compression := (p[2] + terrain[0]) / norm
	var vx := s[3] + s[11] * r[2] - s[12] * r[1]
	var vy := s[4] + s[12] * r[0] - s[10] * r[2]
	var vz := s[5] + s[10] * r[1] - s[11] * r[0]
	var vn := a[0] * vx + a[1] * vy + a[2] * vz
	var ve := a[3] * vx + a[4] * vy + a[5] * vz
	var vd := a[6] * vx + a[7] * vy + a[8] * vz
	var rate := -(normal[0] * vn + normal[1] * ve + normal[2] * vd)
	var load := maxf(0.0, float(c.stiffness) * compression + _damping(c, compression) * rate) if compression > 0.0 else 0.0
	var delta: float = steer * float(c.get("max_steering", 0.0))
	var cosine := M.cos_(delta)
	var sine := M.sin_(delta)
	var hn := a[0] * cosine + a[1] * sine
	var he := a[3] * cosine + a[4] * sine
	var hd := a[6] * cosine + a[7] * sine
	var projection := hn * normal[0] + he * normal[1] + hd * normal[2]
	hn -= normal[0] * projection
	he -= normal[1] * projection
	hd -= normal[2] * projection
	var length := M.sqrt_(hn * hn + he * he + hd * hd)
	var heading := PackedFloat64Array([0.0, 0.0, 0.0])
	if length > 1e-6:
		heading[0] = hn / length
		heading[1] = he / length
		heading[2] = hd / length
	var side := M.cross(heading, normal)
	return {position = p, normal = normal, heading = heading, side = side, compression = compression,
		normal_load = load, long_speed = vn * heading[0] + ve * heading[1] + vd * heading[2],
		side_speed = vn * side[0] + ve * side[1] + vd * side[2], valid_heading = length > 1e-6}


static func _rotation(s: PackedFloat64Array) -> PackedFloat64Array:
	var w := s[6]
	var x := s[7]
	var y := s[8]
	var z := s[9]
	return PackedFloat64Array([1.0 - 2.0 * (y * y + z * z), 2.0 * (x * y - w * z), 2.0 * (x * z + w * y),
		2.0 * (x * y + w * z), 1.0 - 2.0 * (x * x + z * z), 2.0 * (y * z - w * x),
		2.0 * (x * z - w * y), 2.0 * (y * z + w * x), 1.0 - 2.0 * (x * x + y * y)])


static func coefficients(gear: Dictionary, c: Dictionary, surfaces: PackedFloat64Array, p: PackedFloat64Array) -> PackedFloat64Array:
	var mu: float = gear.get("side_friction", 0.0)
	var rolling: float = gear.get("rolling_resistance", 0.0)
	var index := -1
	if not surfaces.is_empty():
		index = surface_at(surfaces, p[0], p[1])
		mu *= surfaces[index + 4]
		# The aircraft base Crr already accounts for its main-wheel size. Scale only
		# positive vegetation excess for smaller tires. A smoother surface directly
		# scales Crr; extrapolating a negative excess can create propulsive resistance.
		var radius: float = c.get("wheel_radius", REFERENCE_RADIUS)
		var factor: float = surfaces[index + 5]
		rolling *= factor if factor < 1.0 else 1.0 + (factor - 1.0) * M.sqrt_(float(gear.get("rolling_reference_radius", REFERENCE_RADIUS)) / radius)
	return PackedFloat64Array([mu, rolling, float(index)])


static func evaluate(s: PackedFloat64Array, gear: Dictionary, steer: float, surfaces: PackedFloat64Array,
		anchors: PackedFloat64Array, speeds: PackedFloat64Array, brake := 0.0, diagnostics_enabled := true,
		lake: Dictionary = {}) -> Dictionary:
	var rates := PackedFloat64Array()
	rates.resize(speeds.size())
	var diagnostics: Array = []
	var loads := PackedFloat64Array()
	if gear.is_empty():
		return {loads = loads, derivative = rates, wheels = diagnostics}
	if speeds.size() != gear.contacts.size() or not Terrain.is_valid_surface_table(surfaces) or not _valid_lake(lake):
		return {loads = PackedFloat64Array([NAN]), derivative = PackedFloat64Array([NAN]), wheels = diagnostics}
	# No body arithmetic at all when every wheel is beyond the terrain's height bound.
	if -s[RB.POS + 2] > float(gear.reach) + Terrain.max_height_validated(surfaces):
		return {loads = loads, derivative = rates, wheels = diagnostics}
	var rotation := _rotation(s)
	for i in gear.contacts.size():
		var c: Dictionary = gear.contacts[i]
		var f := frame(s, c, steer, surfaces, rotation, true, lake)
		var cf := coefficients(gear, c, surfaces, f.position)
		var n: float = f.normal_load
		var rim: float = speeds[i]
		var slip: float = f.long_speed - rim
		var rr := 0.0
		var tire := 0.0
		var lateral := 0.0
		var brake_torque := 0.0
		var radius: float = c.get("wheel_radius", REFERENCE_RADIUS)
		var inertia: float = c.get("wheel_inertia", 0.00003)
		var mass := inertia / (radius * radius)
		var relaxation: float = c.get("spin_relaxation", 0.03)
		if n > 0.0 and f.valid_heading and cf[0] > 0.0:
			var limit := cf[0] * n
			var stuck: bool = anchors.size() == gear.contacts.size() * 3 and anchors[i * 3 + 2] == 1.0 and absf(slip) < STICK_SPEED
			if stuck:
				var displacement := M.v3(f.position[0] - anchors[i * 3], f.position[1] - anchors[i * 3 + 1], 0.0)
				var hold: float = gear.get("breakaway_factor", 1.0) * cf[1] * n
				rr = clampf(-float(c.anchor_stiffness) * M.dot(displacement, f.heading) - float(c.anchor_damping) * f.long_speed, -hold, hold)
				lateral = clampf(-float(c.anchor_stiffness) * M.dot(displacement, f.side) - float(c.anchor_damping) * f.side_speed, -limit, limit)
			else:
				rr = -cf[1] * n * clampf(f.long_speed / maxf(0.01, cf[1] * 0.1), -1.0, 1.0)
				lateral = -limit * clampf(f.side_speed / (float(gear.get("tan_peak_slip", 1.0)) * maxf(absf(f.long_speed), 1.0)), -1.0, 1.0)
			# Soft tire slip is an explicit, documented 240-Hz approximation. Its decay
			# eigenvalue never exceeds 1/tau even on a high-load touchdown.
			tire = -minf(limit / SLIP_REFERENCE_SPEED, mass / relaxation) * slip
			var total := M.sqrt_((rr + tire) * (rr + tire) + lateral * lateral)
			if total > limit:
				var scale := limit / total
				rr *= scale
				tire *= scale
				lateral *= scale
			var maximum: float = clampf(brake, 0.0, 1.0) * float(c.get("brake_torque", 0.0))
			brake_torque = clampf(minf(maximum / 0.25, mass * radius / relaxation) * rim, -maximum, maximum)
			rates[i] = (-tire - brake_torque / radius) / mass
		var long_force := rr + tire
		if diagnostics_enabled:
			diagnostics.append({normal_load = n, compression = f.compression, longitudinal_slip = slip,
				longitudinal_force = long_force, lateral_force = lateral, brake_torque = brake_torque,
				rolling_force = rr, slip_force = tire, rim_speed = rim, long_speed = f.long_speed, surface_index = int(cf[2])})
		if n <= 0.0:
			continue
		if loads.is_empty():
			loads.resize(6)
		var fn: float = f.normal[0] * n + f.heading[0] * long_force + f.side[0] * lateral
		var fe: float = f.normal[1] * n + f.heading[1] * long_force + f.side[1] * lateral
		var fd: float = f.normal[2] * n + f.heading[2] * long_force + f.side[2] * lateral
		var fx := rotation[0] * fn + rotation[3] * fe + rotation[6] * fd
		var fy := rotation[1] * fn + rotation[4] * fe + rotation[7] * fd
		var fz := rotation[2] * fn + rotation[5] * fe + rotation[8] * fd
		# Rim speed is positive forward, so wheel angular momentum is along -side.
		# Remove its spin-up share from total external moment (no wheel gyroscopic terms).
		var spin := inertia / radius * rates[i]
		var r: PackedFloat64Array = c.position
		loads[0] += fx
		loads[1] += fy
		loads[2] += fz
		loads[3] += r[1] * fz - r[2] * fy + spin * (rotation[0] * f.side[0] + rotation[3] * f.side[1] + rotation[6] * f.side[2])
		loads[4] += r[2] * fx - r[0] * fz + spin * (rotation[1] * f.side[0] + rotation[4] * f.side[1] + rotation[7] * f.side[2])
		loads[5] += r[0] * fy - r[1] * fx + spin * (rotation[2] * f.side[0] + rotation[5] * f.side[1] + rotation[8] * f.side[2])
	return {loads = loads, derivative = rates, wheels = diagnostics}


static func compressions(s: PackedFloat64Array, gear: Dictionary, surfaces: PackedFloat64Array,
		lake: Dictionary = {}) -> PackedFloat64Array:
	var values := PackedFloat64Array()
	if gear.is_empty():
		return values
	if not Terrain.is_valid_surface_table(surfaces) or not _valid_lake(lake):
		return PackedFloat64Array([NAN])
	var a := _rotation(s)
	for contact in gear.contacts:
		var r: PackedFloat64Array = contact.position
		var north := s[0] + a[0] * r[0] + a[1] * r[1] + a[2] * r[2]
		var east := s[1] + a[3] * r[0] + a[4] * r[1] + a[5] * r[2]
		var down := s[2] + a[6] * r[0] + a[7] * r[1] + a[8] * r[2]
		var terrain := Terrain.sample_validated(north, east, surfaces, lake)
		values.append((down + terrain[0]) / M.sqrt_(1.0 + terrain[1] * terrain[1] + terrain[2] * terrain[2]))
	return values


static func anchor_step(s: PackedFloat64Array, gear: Dictionary, steer: float, surfaces: PackedFloat64Array,
		anchors: PackedFloat64Array, speeds := PackedFloat64Array(), lake: Dictionary = {}) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(anchors.size())
	if not _valid_lake(lake):
		return PackedFloat64Array([NAN])
	if gear.is_empty() or anchors.size() != gear.contacts.size() * 3 or -s[RB.POS + 2] > float(gear.reach) + Terrain.max_height(surfaces):
		return out
	for i in gear.contacts.size():
		var c: Dictionary = gear.contacts[i]
		var f := frame(s, c, steer, surfaces, PackedFloat64Array(), false, lake)
		var cf := coefficients(gear, c, surfaces, f.position)
		var n: float = f.normal_load
		if n <= 0.0 or cf[0] <= 0.0 or not f.valid_heading:
			continue
		# A stopped axle with a spinning tire is sliding, not a static contact.
		if not speeds.is_empty() and (speeds.size() != gear.contacts.size() or not is_finite(speeds[i]) or absf(f.long_speed - speeds[i]) >= STICK_SPEED):
			continue
		var at: int = i * 3
		if anchors[at + 2] == 1.0:
			var displacement := M.v3(f.position[0] - anchors[at], f.position[1] - anchors[at + 1], 0.0)
			var long_force := -float(c.anchor_stiffness) * M.dot(displacement, f.heading)
			var side_force := -float(c.anchor_stiffness) * M.dot(displacement, f.side)
			var limit := cf[0] * n
			if absf(long_force) <= float(gear.get("breakaway_factor", 1.0)) * cf[1] * n and absf(side_force) <= limit and long_force * long_force + side_force * side_force <= limit * limit:
				out[at] = anchors[at]
				out[at + 1] = anchors[at + 1]
				out[at + 2] = 1.0
		elif M.sqrt_(f.long_speed * f.long_speed + f.side_speed * f.side_speed) < STICK_SPEED:
			out[at] = f.position[0]
			out[at + 1] = f.position[1]
			out[at + 2] = 1.0
	return out


## Empty means the legacy flat field; nonempty contexts are normalized, immutable LakeLoader output.
static func _valid_lake(lake: Dictionary) -> bool:
	return lake.is_empty() or LakeSurface.is_valid_definition(lake)
