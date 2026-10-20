## E3d1: soft crash-hull contacts. Each hull point touching the flat field becomes a spring-damper along the ground
## normal with regularized Coulomb friction in the ground plane, so a wingtip brush, a tail touch or a belly slide
## no longer ends the flight. FlightSession decides when a contact is a crash (terminal()). Pure float64.
## Stiffness and damping are numerical contact choices (estimates), not measured airframe or turf compliance.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const EffectiveMass := preload("res://physics/effective_mass.gd")
const LakeSurface := preload("res://physics/lake_surface.gd")

## Contact natural frequency against each point's smallest effective mass: ω·dt = 0.25 at 240 Hz, so no point is
## stiffer than this for RK4 in any attitude. A belly carrying the whole airplane sags g/ω² ≈ 2.7 mm.
const OMEGA_RAD_S := 60.0
const ZETA := 0.7
## Damping grows from zero over this compression so the force does not jump at touchdown (cf. E1b).
const DAMPING_ONSET_M := 0.004
## Airframe on turf or pavement; research 04 §6 estimates 0.3–0.5.
const FRICTION_MU := 0.4
## Below this ground-plane slip speed friction scales linearly (no chatter at rest).
const SLIP_REGULARIZATION_MPS := 0.2
## A contact is a crash when the struck point's normal energy per kilogram of airplane reaches the CR-08b C2 cut
## (surface transfer 1, conservative), or when any point is pushed this deep (a slow crush).
const TERMINAL_J_PER_KG := 2.5
const CRASH_DEPTH_M := 0.08
## E3d2: a turning propeller whose disc reaches the field is a prop strike (engine stops, not a crash). Estimate: any
## rotation a pilot would hear; research 04 §6 proposed 1.5 × idle, but a glow prop at idle also breaks on the ground.
const STRIKE_MIN_RPM := 300.0

## Identity of this contact law and its constants, for checkpoint configuration hashes and trace metadata.
static func law() -> String:
	return "soft-hull-spring-friction-v1 omega=%s zeta=%s onset_m=%s mu=%s slip_reg_mps=%s terminal_j_per_kg=%s crash_depth_m=%s prop_strike_min_rpm=%s flat-ground" % [
		OMEGA_RAD_S, ZETA, DAMPING_ONSET_M, FRICTION_MU, SLIP_REGULARIZATION_MPS, TERMINAL_J_PER_KG, CRASH_DEPTH_M, STRIKE_MIN_RPM]


## E3d2: the propeller disc from the propulsion data: {hub (body FRD about the CG), axis (unit, body FRD), radius};
## {} for a turbine or data without a propeller diameter. Same hub and axis the thrust is applied at (Propulsion).
static func prop_disc(propulsion: Dictionary) -> Dictionary:
	if str(propulsion.get("kind", "")) == "turbine" or not propulsion.has("diameter") or not propulsion.has("offset"):
		return {}
	var r: PackedFloat64Array = propulsion.offset # [x_aft, y_right, z_up] from the CG
	var a: PackedFloat64Array = propulsion.get("axis", PackedFloat64Array([1.0, 0.0, 0.0]))
	var length := M.norm(a)
	var radius := 0.5 * float(propulsion.diameter)
	if not is_finite(length) or length <= 0.0 or not is_finite(radius) or radius <= 0.0:
		return {}
	return {hub = PackedFloat64Array([-r[0], r[1], -r[2]]), axis = M.scale(a, 1.0 / length), radius = radius}


## E3d2: depth (m, positive below the field) of the disc's lowest point at state `s`, and that point in NED. The lowest
## point is the hub plus the radius along the ground-down direction projected onto the disc plane.
static func prop_disc_depth(s: PackedFloat64Array, disc: Dictionary, lake: Dictionary = {}, time_s: float = 0.0) -> Dictionary:
	if disc.is_empty():
		return {depth = -INF, point_ned = PackedFloat64Array()}
	if (not lake.is_empty() and not LakeSurface.is_valid_definition(lake)) or not is_finite(time_s):
		return {depth = NAN, point_ned = PackedFloat64Array()}
	var down := _down_row(s)
	var a: PackedFloat64Array = disc.axis
	var along := down[0] * a[0] + down[1] * a[1] + down[2] * a[2]
	var p := PackedFloat64Array([down[0] - along * a[0], down[1] - along * a[1], down[2] - along * a[2]])
	var p_len := M.norm(p)
	var lowest: PackedFloat64Array = disc.hub.duplicate()
	if p_len > 1.0e-9: # an axis pointing straight down leaves the disc horizontal: every rim point is as deep
		lowest = M.add(lowest, M.scale(p, float(disc.radius) / p_len))
	var depth := s[RB.POS + 2] + down[0] * lowest[0] + down[1] * lowest[1] + down[2] * lowest[2]
	var point_ned: PackedFloat64Array = M.add(RB._slice3(s, RB.POS), M.q_rotate(RB._att(s), lowest))
	if not lake.is_empty():
		var terrain: Dictionary = LakeSurface.sample_covered_terrain_validated(lake, point_ned[0], point_ned[1])
		if bool(terrain.get("covered", false)):
			var surface_down: float = LakeSurface.water_height_down(lake, point_ned[0], point_ned[1], time_s)
			if not is_finite(surface_down):
				surface_down = float(terrain.ground_down_m)
			depth = point_ned[2] - surface_down
	return {depth = depth, point_ned = point_ned}


const _DIRECTIONS := [
	[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1],
	[1, 1, 0], [1, -1, 0], [-1, 1, 0], [-1, -1, 0], [1, 0, 1], [1, 0, -1], [-1, 0, 1], [-1, 0, -1],
	[0, 1, 1], [0, 1, -1], [0, -1, 1], [0, -1, -1],
	[1, 1, 1], [1, 1, -1], [1, -1, 1], [1, -1, -1], [-1, 1, 1], [-1, 1, -1], [-1, -1, 1], [-1, -1, -1],
]


## Per-point stiffness/damping for `hull` (body FRD about the CG, flattened) from the smallest effective mass over
## 26 body directions. Returns {} when the inputs cannot support a contact (callers then add no hull forces).
static func prepare(hull: PackedFloat64Array, mass: float, inertia: PackedFloat64Array,
		lake: Dictionary = {}) -> Dictionary:
	if hull.is_empty() or hull.size() % 3 != 0 or not is_finite(mass) or mass <= 0.0 \
			or (not lake.is_empty() and not LakeSurface.is_valid_definition(lake)):
		return {}
	var identity := PackedFloat64Array([1.0, 0.0, 0.0, 0.0])
	var k := PackedFloat64Array()
	var c := PackedFloat64Array()
	var reach := 0.0
	for i in range(0, hull.size(), 3):
		var r := hull.slice(i, i + 3)
		var smallest := mass
		for d: Array in _DIRECTIONS:
			var m_eff := EffectiveMass.at_point(identity, r, PackedFloat64Array([float(d[0]), float(d[1]), float(d[2])]), mass, inertia)
			if m_eff <= 0.0:
				return {}
			smallest = minf(smallest, m_eff)
		k.append(smallest * OMEGA_RAD_S * OMEGA_RAD_S)
		c.append(2.0 * ZETA * smallest * OMEGA_RAD_S)
		reach = maxf(reach, M.norm(r))
	var prepared := {points = hull.duplicate(), stiffness = k, damping = c, reach = reach,
		mass = mass, inertia = inertia.duplicate()}
	if not lake.is_empty():
		prepared["lake"] = lake.duplicate(true)
		prepared["lake_bounds_ne_m"] = _polygon_bounds(lake.bank_ne_m)
	return prepared


## Geometry-only preparation for a body whose mass properties change during flight. It deliberately does no
## inertia inversion or contact-coefficient work; the stage path can reject distant hulls before building a
## short-lived coefficient view from its one sampled mass-properties snapshot.
static func prepare_geometry(hull: PackedFloat64Array, lake: Dictionary = {}) -> Dictionary:
	if hull.is_empty() or hull.size() % 3 != 0 or not _finite_array(hull) \
			or (not lake.is_empty() and not LakeSurface.is_valid_definition(lake)):
		return {}
	var reach: float = 0.0
	for i in range(0, hull.size(), 3):
		reach = maxf(reach, M.norm(hull.slice(i, i + 3)))
	var geometry := {points = hull.duplicate(), reach = reach, geometry_only = true}
	if not lake.is_empty():
		geometry["lake"] = lake.duplicate(true)
		geometry["lake_bounds_ne_m"] = _polygon_bounds(lake.bank_ne_m)
	return geometry


## Stage loads for live mass properties, returning failure separately from a valid no-contact result.
## Geometry and output torque arms remain about fixed datum O, matching the state integration contract.
static func loads_at_properties(s: PackedFloat64Array, geometry: Dictionary, properties: Dictionary) -> Dictionary:
	var valid: Dictionary = EffectiveMass.validate_properties(properties)
	if not bool(valid.get("ok", false)):
		return {ok = false, loads = PackedFloat64Array(), reason = str(valid.get("reason", "invalid_mass_properties"))}
	if geometry.is_empty() or not bool(geometry.get("geometry_only", false)) \
			or not geometry.has("points") or not geometry.has("reach"):
		return {ok = false, loads = PackedFloat64Array(), reason = "invalid_contact_geometry"}
	if s.size() != RB.SIZE or not _finite_array(s) or -s[RB.POS + 2] > float(geometry.reach):
		if s.size() != RB.SIZE or not _finite_array(s):
			return {ok = false, loads = PackedFloat64Array(), reason = "invalid_rigid_body_state"}
		return {ok = true, loads = PackedFloat64Array(), reason = ""}
	var hull: PackedFloat64Array = geometry.points
	var stiffness := PackedFloat64Array()
	var damping := PackedFloat64Array()
	var identity := PackedFloat64Array([1.0, 0.0, 0.0, 0.0])
	for i in range(0, hull.size(), 3):
		var body_point_o: PackedFloat64Array = hull.slice(i, i + 3)
		var smallest: float = float(properties.mass_kg)
		for d: Array in _DIRECTIONS:
			var effective: Dictionary = EffectiveMass._at_point_properties_validated(identity, body_point_o,
				PackedFloat64Array([float(d[0]), float(d[1]), float(d[2])]), properties)
			if not bool(effective.get("ok", false)):
				return {ok = false, loads = PackedFloat64Array(), reason = str(effective.get("reason", "invalid_effective_mass"))}
			smallest = minf(smallest, float(effective.effective_mass_kg))
		stiffness.append(smallest * OMEGA_RAD_S * OMEGA_RAD_S)
		damping.append(2.0 * ZETA * smallest * OMEGA_RAD_S)
	var prepared := {points = hull, stiffness = stiffness, damping = damping,
		reach = float(geometry.reach), mass = float(properties.mass_kg), inertia = properties.inertia}
	if geometry.has("lake"):
		prepared["lake"] = geometry.lake
		prepared["lake_bounds_ne_m"] = geometry.get("lake_bounds_ne_m", PackedFloat64Array())
	return {ok = true, loads = loads(s, prepared), reason = ""}


## Body loads [Fx, Fy, Fz, Mx, My, Mz] from every touching hull point, or EMPTY when none touches (callers add
## nothing, so flight away from the ground is bit-identical).
static func loads(s: PackedFloat64Array, prepared: Dictionary) -> PackedFloat64Array:
	if prepared.is_empty() or -s[RB.POS + 2] > float(prepared.reach):
		return PackedFloat64Array()
	var hull: PackedFloat64Array = prepared.points
	var rows := _rows(s)
	var north: PackedFloat64Array = rows[0]
	var east: PackedFloat64Array = rows[1]
	var down: PackedFloat64Array = rows[2]
	var out := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var touched := false
	var lake: Dictionary = prepared.get("lake", {})
	for i in range(0, hull.size(), 3):
		var body_point: PackedFloat64Array = hull.slice(i, i + 3)
		if not lake.is_empty():
			var point_ned: PackedFloat64Array = _point_ned(s, body_point)
			var terrain: Dictionary = _lake_sample(prepared, point_ned)
			if bool(terrain.get("covered", false)):
				var lake_load: PackedFloat64Array = _lake_load(s, prepared, i / 3, body_point, point_ned, terrain)
				if not lake_load.is_empty():
					for axis: int in 6:
						out[axis] += lake_load[axis]
					touched = true
				continue
		var rx := hull[i]
		var ry := hull[i + 1]
		var rz := hull[i + 2]
		var depth := s[RB.POS + 2] + down[0] * rx + down[1] * ry + down[2] * rz
		if depth <= 0.0:
			continue
		var vx := s[RB.VEL] + s[RB.RATE + 1] * rz - s[RB.RATE + 2] * ry
		var vy := s[RB.VEL + 1] + s[RB.RATE + 2] * rx - s[RB.RATE] * rz
		var vz := s[RB.VEL + 2] + s[RB.RATE] * ry - s[RB.RATE + 1] * rx
		var rate := down[0] * vx + down[1] * vy + down[2] * vz
		var point := i / 3
		var onset := minf(depth / DAMPING_ONSET_M, 1.0)
		var f_up: float = prepared.stiffness[point] * depth + prepared.damping[point] * onset * rate
		if f_up <= 0.0:
			continue # a damper never pulls the airframe into the ground
		var vn := north[0] * vx + north[1] * vy + north[2] * vz
		var ve := east[0] * vx + east[1] * vy + east[2] * vz
		var slip := M.sqrt_(vn * vn + ve * ve)
		var scale := FRICTION_MU * f_up / maxf(slip, SLIP_REGULARIZATION_MPS)
		var f_n := -scale * vn
		var f_e := -scale * ve
		# NED force (f_n, f_e, −f_up) in body axes.
		var fx := f_n * north[0] + f_e * east[0] - f_up * down[0]
		var fy := f_n * north[1] + f_e * east[1] - f_up * down[1]
		var fz := f_n * north[2] + f_e * east[2] - f_up * down[2]
		out[0] += fx
		out[1] += fy
		out[2] += fz
		out[3] += ry * fz - rz * fy
		out[4] += rz * fx - rx * fz
		out[5] += rx * fy - ry * fx
		touched = true
	return out if touched else PackedFloat64Array()


## The hull point that makes the step previous → s a crash, or -1. Graded on the point's state in `previous` (just
## before it touched): a point newly below the ground crashes when transfer-free ½·m_eff·v_n²/m reaches
## TERMINAL_J_PER_KG; any point deeper than CRASH_DEPTH_M crashes too. Returns {index, rule, specific_j_per_kg,
## normal_speed_mps, depth_m}.
static func terminal(previous: PackedFloat64Array, s: PackedFloat64Array, prepared: Dictionary) -> Dictionary:
	var none := {index = -1, rule = "", specific_j_per_kg = 0.0, normal_speed_mps = 0.0, depth_m = 0.0}
	# CR-22c: runs every tick; nothing can touch above the hull's reach, and points in the air cost no allocation.
	if prepared.is_empty() or previous.size() != s.size() or -s[RB.POS + 2] > float(prepared.reach):
		return none
	var hull: PackedFloat64Array = prepared.points
	var down_now: PackedFloat64Array = _down_row(s)
	var down_before: PackedFloat64Array = _down_row(previous)
	var q_before := RB._att(previous)
	var worst := none.duplicate()
	for i in range(0, hull.size(), 3):
		var r := hull.slice(i, i + 3)
		var lake: Dictionary = prepared.get("lake", {})
		if not lake.is_empty():
			var point_now: PackedFloat64Array = _point_ned(s, r)
			var terrain_now: Dictionary = _lake_sample(prepared, point_now)
			if bool(terrain_now.get("covered", false)):
				var lake_result: Dictionary = _lake_terminal_candidate(previous, s, prepared, i / 3,
					r, point_now, terrain_now, q_before)
				if str(lake_result.get("rule", "")) == "depth":
					return lake_result
				if not lake_result.is_empty() and float(lake_result.specific_j_per_kg) > float(worst.specific_j_per_kg):
					worst = lake_result
				continue
		var depth := s[RB.POS + 2] + down_now[0] * hull[i] + down_now[1] * hull[i + 1] + down_now[2] * hull[i + 2]
		if depth <= 0.0:
			continue
		if depth > CRASH_DEPTH_M:
			return {index = i / 3, rule = "depth", specific_j_per_kg = 0.0, normal_speed_mps = 0.0, depth_m = depth}
		var depth_before := previous[RB.POS + 2] + down_before[0] * r[0] + down_before[1] * r[1] + down_before[2] * r[2]
		if depth_before > 0.0:
			continue # already in contact: a resting or sliding point is not a new impact
		var v_ned := M.q_rotate(q_before, M.add(RB._slice3(previous, RB.VEL), M.cross(RB._slice3(previous, RB.RATE), r)))
		var v_n := maxf(0.0, v_ned[2])
		var m_eff := EffectiveMass.at_point(q_before, r, PackedFloat64Array([0.0, 0.0, -1.0]), float(prepared.mass), prepared.inertia)
		if m_eff <= 0.0:
			m_eff = float(prepared.mass)
		var specific := 0.5 * m_eff * v_n * v_n / float(prepared.mass)
		if specific >= TERMINAL_J_PER_KG and specific > float(worst.specific_j_per_kg):
			worst = {index = i / 3, rule = "impact", specific_j_per_kg = specific, normal_speed_mps = v_n, depth_m = depth}
	return worst


## Dynamic terminal test. The sample is specifically for `previous`: existing soft-hull impact energy uses the
## pre-contact pose/velocity and only the candidate state to establish penetration. A deep-crush result is still
## mass-independent, but invalid samples fail closed before any candidate is accepted.
static func terminal_at_properties(previous: PackedFloat64Array, s: PackedFloat64Array,
		geometry: Dictionary, properties_previous: Dictionary) -> Dictionary:
	var none := {index = -1, rule = "", specific_j_per_kg = 0.0, normal_speed_mps = 0.0, depth_m = 0.0}
	var valid: Dictionary = EffectiveMass.validate_properties(properties_previous)
	if not bool(valid.get("ok", false)):
		return {ok = false, event = none, reason = str(valid.get("reason", "invalid_mass_properties"))}
	if geometry.is_empty() or not bool(geometry.get("geometry_only", false)) \
			or previous.size() != RB.SIZE or s.size() != RB.SIZE \
			or not _finite_array(previous) or not _finite_array(s):
		return {ok = false, event = none, reason = "invalid_contact_input"}
	var q_before: PackedFloat64Array = RB._att(previous)
	var previous_q_norm_squared: float = q_before[0] * q_before[0] + q_before[1] * q_before[1] \
		+ q_before[2] * q_before[2] + q_before[3] * q_before[3]
	if not is_finite(previous_q_norm_squared) or absf(previous_q_norm_squared - 1.0) > 1.0e-9:
		return {ok = false, event = none, reason = "invalid_previous_attitude"}
	if -s[RB.POS + 2] > float(geometry.reach):
		return {ok = true, event = none, reason = ""}
	var hull: PackedFloat64Array = geometry.points
	var down_now: PackedFloat64Array = _down_row(s)
	var down_before: PackedFloat64Array = _down_row(previous)
	var worst: Dictionary = none.duplicate()
	var lake: Dictionary = geometry.get("lake", {})
	for i in range(0, hull.size(), 3):
		var r: PackedFloat64Array = hull.slice(i, i + 3)
		if not lake.is_empty():
			var point_now: PackedFloat64Array = _point_ned(s, r)
			var terrain_now: Dictionary = _lake_sample(geometry, point_now)
			if bool(terrain_now.get("covered", false)):
				var lake_event: Dictionary = _lake_terminal_candidate_properties(previous, s, geometry,
					i / 3, r, point_now, terrain_now, q_before, properties_previous)
				if bool(lake_event.get("invalid", false)):
					return {ok = false, event = none, reason = str(lake_event.get("reason", "invalid_effective_mass"))}
				if str(lake_event.get("rule", "")) == "depth":
					return {ok = true, event = lake_event, reason = ""}
				if not lake_event.is_empty() and float(lake_event.specific_j_per_kg) > float(worst.specific_j_per_kg):
					worst = lake_event
				continue
		var depth: float = s[RB.POS + 2] + down_now[0] * r[0] + down_now[1] * r[1] + down_now[2] * r[2]
		if depth <= 0.0:
			continue
		if depth > CRASH_DEPTH_M:
			return {ok = true, event = {index = i / 3, rule = "depth", specific_j_per_kg = 0.0,
				normal_speed_mps = 0.0, depth_m = depth}, reason = ""}
		var depth_before: float = previous[RB.POS + 2] + down_before[0] * r[0] + down_before[1] * r[1] + down_before[2] * r[2]
		if depth_before > 0.0:
			continue
		var velocity_ned: PackedFloat64Array = M.q_rotate(q_before,
			M.add(RB._slice3(previous, RB.VEL), M.cross(RB._slice3(previous, RB.RATE), r)))
		var normal_speed: float = maxf(0.0, velocity_ned[2])
		var effective: Dictionary = EffectiveMass._at_point_properties_validated(q_before, r,
			PackedFloat64Array([0.0, 0.0, -1.0]), properties_previous)
		if not bool(effective.get("ok", false)):
			return {ok = false, event = none, reason = str(effective.get("reason", "invalid_effective_mass"))}
		var specific: float = 0.5 * float(effective.effective_mass_kg) * normal_speed * normal_speed \
			/ float(properties_previous.mass_kg)
		if specific >= TERMINAL_J_PER_KG and specific > float(worst.specific_j_per_kg):
			worst = {index = i / 3, rule = "impact", specific_j_per_kg = specific,
				normal_speed_mps = normal_speed, depth_m = depth}
	return {ok = true, event = worst, reason = ""}


## Presentation feed: every hull point touching after the step previous → s, as {index, new, depth_m,
## normal_speed_mps (into the ground, from `previous`), slide_speed_mps, point_ned}. Empty in the air.
static func contacts(previous: PackedFloat64Array, s: PackedFloat64Array, prepared: Dictionary) -> Array:
	var out: Array = []
	if prepared.is_empty() or previous.size() != s.size() or -s[RB.POS + 2] > float(prepared.reach):
		return out
	var hull: PackedFloat64Array = prepared.points
	var down_now: PackedFloat64Array = _down_row(s)
	var down_before: PackedFloat64Array = _down_row(previous)
	var q := RB._att(s)
	var q_before := RB._att(previous)
	for i in range(0, hull.size(), 3):
		var r := hull.slice(i, i + 3)
		var lake: Dictionary = prepared.get("lake", {})
		if not lake.is_empty():
			var point_now: PackedFloat64Array = _point_ned(s, r)
			var terrain_now: Dictionary = _lake_sample(prepared, point_now)
			if bool(terrain_now.get("covered", false)):
				var lake_contact: Dictionary = _lake_contact_record(previous, s, prepared, i / 3,
					r, point_now, terrain_now, q_before, q)
				if not lake_contact.is_empty():
					out.append(lake_contact)
				continue
		var depth := s[RB.POS + 2] + down_now[0] * hull[i] + down_now[1] * hull[i + 1] + down_now[2] * hull[i + 2]
		if depth <= 0.0:
			continue
		var depth_before := previous[RB.POS + 2] + down_before[0] * r[0] + down_before[1] * r[1] + down_before[2] * r[2]
		var v_before := M.q_rotate(q_before, M.add(RB._slice3(previous, RB.VEL), M.cross(RB._slice3(previous, RB.RATE), r)))
		var v_now := M.q_rotate(q, M.add(RB._slice3(s, RB.VEL), M.cross(RB._slice3(s, RB.RATE), r)))
		out.append({index = i / 3, new = depth_before <= 0.0, depth_m = depth, normal_speed_mps = maxf(0.0, v_before[2]),
			slide_speed_mps = M.sqrt_(v_now[0] * v_now[0] + v_now[1] * v_now[1]),
			point_ned = M.add(RB._slice3(s, RB.POS), M.q_rotate(q, r)), velocity_ned = v_now})
	return out


static func _lake_load(s: PackedFloat64Array, prepared: Dictionary, point_index: int,
	body_point: PackedFloat64Array, point_ned: PackedFloat64Array, terrain: Dictionary) -> PackedFloat64Array:
	var normal: PackedFloat64Array = _lake_normal(terrain)
	if normal.is_empty():
		return PackedFloat64Array()
	var normal_length: float = M.norm(PackedFloat64Array([
		float(terrain.slope_north), float(terrain.slope_east), 1.0]))
	var compression: float = (point_ned[2] - float(terrain.ground_down_m)) / normal_length
	if compression <= 0.0:
		return PackedFloat64Array()
	var q: PackedFloat64Array = RB._att(s)
	var velocity_body: PackedFloat64Array = M.add(RB._slice3(s, RB.VEL),
		M.cross(RB._slice3(s, RB.RATE), body_point))
	var velocity_ned: PackedFloat64Array = M.q_rotate(q, velocity_body)
	var normal_rate: float = -M.dot(velocity_ned, normal)
	var onset: float = minf(compression / DAMPING_ONSET_M, 1.0)
	var f_up: float = float(prepared.stiffness[point_index]) * compression \
		+ float(prepared.damping[point_index]) * onset * normal_rate
	if f_up <= 0.0:
		return PackedFloat64Array()
	var normal_speed: float = M.dot(velocity_ned, normal)
	var tangent_velocity: PackedFloat64Array = M.sub(velocity_ned, M.scale(normal, normal_speed))
	var slip: float = M.norm(tangent_velocity)
	var friction_scale: float = FRICTION_MU * f_up / maxf(slip, SLIP_REGULARIZATION_MPS)
	var force_ned: PackedFloat64Array = M.sub(M.scale(normal, f_up), M.scale(tangent_velocity, friction_scale))
	var q_inverse: PackedFloat64Array = PackedFloat64Array([q[0], -q[1], -q[2], -q[3]])
	var force_body: PackedFloat64Array = M.q_rotate(q_inverse, force_ned)
	return PackedFloat64Array([
		force_body[0], force_body[1], force_body[2],
		body_point[1] * force_body[2] - body_point[2] * force_body[1],
		body_point[2] * force_body[0] - body_point[0] * force_body[2],
		body_point[0] * force_body[1] - body_point[1] * force_body[0],
	])


static func _lake_terminal_candidate(previous: PackedFloat64Array, s: PackedFloat64Array,
	prepared: Dictionary, point_index: int, body_point: PackedFloat64Array, point_now: PackedFloat64Array,
	terrain_now: Dictionary, q_before: PackedFloat64Array) -> Dictionary:
	var normal: PackedFloat64Array = _lake_normal(terrain_now)
	if normal.is_empty():
		return {}
	var normal_length: float = M.norm(PackedFloat64Array([
		float(terrain_now.slope_north), float(terrain_now.slope_east), 1.0]))
	var depth: float = (point_now[2] - float(terrain_now.ground_down_m)) / normal_length
	if depth <= 0.0:
		return {}
	if depth > CRASH_DEPTH_M:
		return {index = point_index, rule = "depth", specific_j_per_kg = 0.0,
			normal_speed_mps = 0.0, depth_m = depth}
	var point_before: PackedFloat64Array = _point_ned(previous, body_point)
	var terrain_before: Dictionary = _lake_sample(prepared, point_before)
	var depth_before: float = 0.0
	if bool(terrain_before.get("covered", false)):
		var before_normal_length: float = M.norm(PackedFloat64Array([
			float(terrain_before.slope_north), float(terrain_before.slope_east), 1.0]))
		depth_before = (point_before[2] - float(terrain_before.ground_down_m)) / before_normal_length
	else:
		var extrapolated_ground_down: float = float(terrain_now.ground_down_m) \
			+ float(terrain_now.slope_north) * (point_before[0] - point_now[0]) \
			+ float(terrain_now.slope_east) * (point_before[1] - point_now[1])
		depth_before = (point_before[2] - extrapolated_ground_down) / normal_length
	if depth_before > 0.0:
		return {} # Resting or sliding bank contact is handled by the spring-damper, not a new impact.
	var velocity_ned: PackedFloat64Array = M.q_rotate(q_before, M.add(RB._slice3(previous, RB.VEL),
		M.cross(RB._slice3(previous, RB.RATE), body_point)))
	var normal_speed: float = maxf(0.0, -M.dot(velocity_ned, normal))
	var effective_mass: float = EffectiveMass.at_point(q_before, body_point, normal,
		float(prepared.mass), prepared.inertia)
	if effective_mass <= 0.0:
		effective_mass = float(prepared.mass)
	var specific: float = 0.5 * effective_mass * normal_speed * normal_speed / float(prepared.mass)
	if specific >= TERMINAL_J_PER_KG:
		return {index = point_index, rule = "impact", specific_j_per_kg = specific,
			normal_speed_mps = normal_speed, depth_m = depth}
	return {}


static func _lake_terminal_candidate_properties(previous: PackedFloat64Array, s: PackedFloat64Array,
		geometry: Dictionary, point_index: int, body_point_o: PackedFloat64Array,
		point_now: PackedFloat64Array, terrain_now: Dictionary, q_before: PackedFloat64Array,
		properties_previous: Dictionary) -> Dictionary:
	var normal: PackedFloat64Array = _lake_normal(terrain_now)
	if normal.is_empty():
		return {}
	var normal_length: float = M.norm(PackedFloat64Array([
		float(terrain_now.slope_north), float(terrain_now.slope_east), 1.0]))
	var depth: float = (point_now[2] - float(terrain_now.ground_down_m)) / normal_length
	if depth <= 0.0:
		return {}
	if depth > CRASH_DEPTH_M:
		return {index = point_index, rule = "depth", specific_j_per_kg = 0.0,
			normal_speed_mps = 0.0, depth_m = depth}
	var point_before: PackedFloat64Array = _point_ned(previous, body_point_o)
	var terrain_before: Dictionary = _lake_sample(geometry, point_before)
	var depth_before: float
	if bool(terrain_before.get("covered", false)):
		var before_normal_length: float = M.norm(PackedFloat64Array([
			float(terrain_before.slope_north), float(terrain_before.slope_east), 1.0]))
		depth_before = (point_before[2] - float(terrain_before.ground_down_m)) / before_normal_length
	else:
		var extrapolated_ground_down: float = float(terrain_now.ground_down_m) \
			+ float(terrain_now.slope_north) * (point_before[0] - point_now[0]) \
			+ float(terrain_now.slope_east) * (point_before[1] - point_now[1])
		depth_before = (point_before[2] - extrapolated_ground_down) / normal_length
	if depth_before > 0.0:
		return {}
	var velocity_ned: PackedFloat64Array = M.q_rotate(q_before, M.add(RB._slice3(previous, RB.VEL),
		M.cross(RB._slice3(previous, RB.RATE), body_point_o)))
	var normal_speed: float = maxf(0.0, -M.dot(velocity_ned, normal))
	var effective: Dictionary = EffectiveMass._at_point_properties_validated(q_before, body_point_o, normal, properties_previous)
	if not bool(effective.get("ok", false)):
		return {invalid = true, reason = str(effective.get("reason", "invalid_effective_mass"))}
	var specific: float = 0.5 * float(effective.effective_mass_kg) * normal_speed * normal_speed \
		/ float(properties_previous.mass_kg)
	if specific >= TERMINAL_J_PER_KG:
		return {index = point_index, rule = "impact", specific_j_per_kg = specific,
			normal_speed_mps = normal_speed, depth_m = depth}
	return {}


static func _lake_contact_record(previous: PackedFloat64Array, s: PackedFloat64Array,
	prepared: Dictionary, point_index: int, body_point: PackedFloat64Array, point_now: PackedFloat64Array,
	terrain_now: Dictionary, q_before: PackedFloat64Array, q_now: PackedFloat64Array) -> Dictionary:
	var normal: PackedFloat64Array = _lake_normal(terrain_now)
	if normal.is_empty():
		return {}
	var normal_length: float = M.norm(PackedFloat64Array([
		float(terrain_now.slope_north), float(terrain_now.slope_east), 1.0]))
	var depth: float = (point_now[2] - float(terrain_now.ground_down_m)) / normal_length
	if depth <= 0.0:
		return {}
	var point_before: PackedFloat64Array = _point_ned(previous, body_point)
	var terrain_before: Dictionary = _lake_sample(prepared, point_before)
	var depth_before: float
	if bool(terrain_before.get("covered", false)):
		var before_normal_length: float = M.norm(PackedFloat64Array([
			float(terrain_before.slope_north), float(terrain_before.slope_east), 1.0]))
		depth_before = (point_before[2] - float(terrain_before.ground_down_m)) / before_normal_length
	else:
		var extrapolated_ground_down: float = float(terrain_now.ground_down_m) \
			+ float(terrain_now.slope_north) * (point_before[0] - point_now[0]) \
			+ float(terrain_now.slope_east) * (point_before[1] - point_now[1])
		depth_before = (point_before[2] - extrapolated_ground_down) / normal_length
	var velocity_before: PackedFloat64Array = M.q_rotate(q_before, M.add(RB._slice3(previous, RB.VEL),
		M.cross(RB._slice3(previous, RB.RATE), body_point)))
	var velocity_now: PackedFloat64Array = M.q_rotate(q_now, M.add(RB._slice3(s, RB.VEL),
		M.cross(RB._slice3(s, RB.RATE), body_point)))
	var normal_rate: float = maxf(0.0, -M.dot(velocity_before, normal))
	var tangent_now: PackedFloat64Array = M.sub(velocity_now, M.scale(normal, M.dot(velocity_now, normal)))
	return {index = point_index, new = depth_before <= 0.0, depth_m = depth,
		normal_speed_mps = normal_rate, slide_speed_mps = M.norm(tangent_now),
		point_ned = point_now, velocity_ned = velocity_now, normal_ned = normal}


static func _point_ned(s: PackedFloat64Array, body_point: PackedFloat64Array) -> PackedFloat64Array:
	return M.add(RB._slice3(s, RB.POS), M.q_rotate(RB._att(s), body_point))


static func _lake_sample(prepared: Dictionary, point_ned: PackedFloat64Array) -> Dictionary:
	var lake_value: Variant = prepared.get("lake", {})
	if typeof(lake_value) != TYPE_DICTIONARY or lake_value.is_empty() or point_ned.size() != 3:
		return {covered = false}
	var lake: Dictionary = lake_value
	var bounds_value: Variant = prepared.get("lake_bounds_ne_m", PackedFloat64Array())
	if typeof(bounds_value) == TYPE_PACKED_FLOAT64_ARRAY and bounds_value.size() == 4:
		var bounds: PackedFloat64Array = bounds_value
		if point_ned[0] < bounds[0] or point_ned[0] > bounds[1] \
				or point_ned[1] < bounds[2] or point_ned[1] > bounds[3]:
			return {covered = false}
	return LakeSurface.sample_terrain_validated(lake, point_ned[0], point_ned[1])


static func _lake_normal(terrain: Dictionary) -> PackedFloat64Array:
	var slope_north: float = float(terrain.get("slope_north", NAN))
	var slope_east: float = float(terrain.get("slope_east", NAN))
	if not is_finite(slope_north) or not is_finite(slope_east):
		return PackedFloat64Array()
	var length: float = M.sqrt_(1.0 + slope_north * slope_north + slope_east * slope_east)
	return PackedFloat64Array([-slope_north / length, -slope_east / length, -1.0 / length])


static func _polygon_bounds(polygon: PackedFloat64Array) -> PackedFloat64Array:
	var north_min: float = INF
	var north_max: float = -INF
	var east_min: float = INF
	var east_max: float = -INF
	for index: int in range(0, polygon.size(), 2):
		north_min = minf(north_min, polygon[index])
		north_max = maxf(north_max, polygon[index])
		east_min = minf(east_min, polygon[index + 1])
		east_max = maxf(east_max, polygon[index + 1])
	return PackedFloat64Array([north_min, north_max, east_min, east_max])


static func _rows(s: PackedFloat64Array) -> Array:
	var w := s[RB.ATT]
	var x := s[RB.ATT + 1]
	var y := s[RB.ATT + 2]
	var z := s[RB.ATT + 3]
	return [
		PackedFloat64Array([1.0 - 2.0 * (y * y + z * z), 2.0 * (x * y - w * z), 2.0 * (x * z + w * y)]),
		PackedFloat64Array([2.0 * (x * y + w * z), 1.0 - 2.0 * (x * x + z * z), 2.0 * (y * z - w * x)]),
		_down_row(s),
	]


static func _down_row(s: PackedFloat64Array) -> PackedFloat64Array:
	var w := s[RB.ATT]
	var x := s[RB.ATT + 1]
	var y := s[RB.ATT + 2]
	var z := s[RB.ATT + 3]
	return PackedFloat64Array([2.0 * (x * z - w * y), 2.0 * (y * z + w * x), 1.0 - 2.0 * (x * x + y * y)])


static func _finite_array(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true
