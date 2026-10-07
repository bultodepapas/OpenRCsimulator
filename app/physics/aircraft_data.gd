# Loads, validates and derives the physics data of an aircraft (format "openrc-aircraft v1").
# 64-bit floats only (guarded). Errors block use; warnings are data-quality notes to show, not hide.
# Result: { ok: bool, errors: PackedStringArray, warnings: PackedStringArray, model: Dictionary }
# model: mass_kg, inertia (PackedFloat64Array [Jxx Jyy Jzz Jxy Jxz Jyz], body FRD, about the inventory's own
#        centre of mass; configurations whose declared flight CG disagrees are rejected),
#        cg_le / cg_inventory_le (PackedFloat64Array [x_aft, y_right, z_up], m), reference {S, b, c, arp_le},
#        aero {name: float}, conventions {…}, controls {throw_deg, throw_rad: {aileron, elevator, rudder},
#        servo_rate (full throws per second)}, id.
extends RefCounted

const M := preload("res://physics/math3d.gd")

const FORMAT := "openrc-aircraft v1"
const Aero := preload("res://physics/aero.gd")
const Ground := preload("res://physics/ground_contact.gd")
## The full-envelope blend may not start below this |α|: the linear model is the test oracle up to here (D9a).
const ORACLE_ALPHA_DEG := 8.0
## D1-R3 ground_support() tolerances (m, m²): contacts within 1 mm of a facet plane count as on it (data rounding, far
## below the 1–3 cm static sag); smaller triangle areas, near-vertical facets and shorter edges are degenerate.
const SUPPORT_PLANE_TOL := 0.001
const SUPPORT_AREA_MIN := 1e-6
const SUPPORT_UP_MIN := 1e-6
const SUPPORT_EDGE_MIN := 1e-9
const KINDS := ["manual", "measured", "borrowed", "estimated", "derived"]

## Coefficient name → [unit, required sign (+1, -1 or 0 = any)]. Signs encode a statically stable airplane.
const COEFFICIENTS := {
	CL0 = ["1", 0], CLa = ["1/rad", 1], CLadot = ["1/rad", 0], CLq = ["1/rad", 0], CLde = ["1/rad", 1], CLda_each = ["1/rad", 0],
	CD0 = ["1", 1], CL_minD = ["1", 0], k_induced = ["1", 1], CDda_each = ["1/rad", 0], CDdr = ["1/rad", 0], CDde = ["1/rad", 0],
	CYb = ["1/rad", -1], CYp = ["1/rad", 0], CYr = ["1/rad", 0], CYdr = ["1/rad", 0],
	Clb = ["1/rad", -1], Clp = ["1/rad", -1], Clr = ["1/rad", 0], Clda_right = ["1/rad", -1], Clda_left = ["1/rad", 1], Cldr = ["1/rad", 0],
	Cm0 = ["1", 0], Cma = ["1/rad", -1], Cmq = ["1/rad", -1], Cmde = ["1/rad", -1], Cmda_each = ["1/rad", 0],
	Cnb = ["1/rad", 1], Cnp = ["1/rad", 0], Cnr = ["1/rad", -1], Cnda_right = ["1/rad", 0], Cnda_left = ["1/rad", 0], Cndr = ["1/rad", -1],
}


static func load_file(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return _fail("cannot read %s (error %d)" % [path, FileAccess.get_open_error()])
	var json := JSON.new()
	if json.parse(text) != OK:
		return _fail("%s: JSON error at line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _fail("%s: top level must be an object" % path)
	return validate_and_derive(json.data)


static func _fail(message: String) -> Dictionary:
	return { ok = false, errors = PackedStringArray([message]), warnings = PackedStringArray(), model = {} }


static func _dictionary(errors: PackedStringArray, path: String, node: Variant) -> Dictionary:
	if typeof(node) != TYPE_DICTIONARY:
		errors.append("%s: expected an object" % path)
		return {}
	return node


static func _array(errors: PackedStringArray, path: String, node: Variant) -> Array:
	if typeof(node) != TYPE_ARRAY:
		errors.append("%s: expected an array" % path)
		return []
	return node


## Checks one quantity { value, unit, kind, source }. size: 0 = scalar, n = array of n numbers.
static func _q(errors: PackedStringArray, path: String, node: Variant, unit: String, lo: float, hi: float, size := 0) -> Variant:
	if typeof(node) != TYPE_DICTIONARY:
		errors.append("%s: missing or not an object" % path)
		return null
	for key in ["value", "unit", "kind", "source"]:
		if not node.has(key):
			errors.append("%s: missing '%s'" % [path, key])
			return null
	if node.unit != unit:
		errors.append("%s: unit '%s', expected '%s'" % [path, node.unit, unit])
	if not (node.kind in KINDS):
		errors.append("%s: kind '%s' is not one of %s" % [path, node.kind, KINDS])
	if typeof(node.source) != TYPE_STRING or node.source.strip_edges() == "":
		errors.append("%s: empty source" % path)
	var values: Array = node.value if size > 0 and typeof(node.value) == TYPE_ARRAY else [node.value]
	if (size > 0 and (typeof(node.value) != TYPE_ARRAY or values.size() != size)) or (size == 0 and typeof(node.value) == TYPE_ARRAY):
		errors.append("%s: expected %s" % [path, "a number" if size == 0 else "%d numbers" % size])
		return null
	for x in values:
		if typeof(x) != TYPE_FLOAT and typeof(x) != TYPE_INT:
			errors.append("%s: '%s' is not a number" % [path, x])
			return null
		if not is_finite(x) or x < lo or x > hi:
			errors.append("%s: %s outside [%s, %s] %s" % [path, x, lo, hi, unit])
	return PackedFloat64Array(values) if size > 0 else float(node.value)


static func validate_and_derive(raw: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	if raw.get("format") != FORMAT:
		errors.append("format must be '%s', got '%s'" % [FORMAT, raw.get("format")])
		return { ok = false, errors = errors, warnings = warnings, model = {} }

	var ref := _dictionary(errors, "reference", raw.get("reference", {}))
	var area = _q(errors, "reference.wing_area", ref.get("wing_area"), "m2", 0.05, 3.0)
	var span = _q(errors, "reference.wing_span", ref.get("wing_span"), "m", 0.3, 4.0)
	var chord = _q(errors, "reference.mean_chord", ref.get("mean_chord"), "m", 0.05, 1.0)
	var arp = _q(errors, "reference.aero_reference_point", ref.get("aero_reference_point"), "m", -2.0, 2.0, 3)
	# mean_chord is the coefficient reference length S/b for every planform (v1 contract); a tapered wing declares its
	# MAC separately in the evidence, never in this field.
	if area != null and span != null and chord != null and absf(span * chord - area) / area > 0.01:
		errors.append("reference: span × mean_chord = %.4f m2 differs from wing_area %.4f m2 by more than 1 %%" % [span * chord, area])
	var planform: Variant = ref.get("planform", "rectangular")
	var chords := PackedFloat64Array() # [root, tip] for a tapered wing; empty = rectangular
	if planform == "tapered":
		var root = _q(errors, "reference.root_chord", ref.get("root_chord"), "m", 0.05, 1.0)
		var tip = _q(errors, "reference.tip_chord", ref.get("tip_chord"), "m", 0.02, 1.0)
		if root != null and tip != null:
			if tip > root:
				errors.append("reference: tip_chord %s must not exceed root_chord %s" % [tip, root])
			elif area != null and span != null and absf(span * (root + tip) / 2.0 - area) / area > 0.01:
				errors.append("reference: trapezoid span × (root + tip) / 2 = %.4f m2 differs from wing_area %.4f m2 by more than 1 %%" % [span * (root + tip) / 2.0, area])
			chords = PackedFloat64Array([root, tip])
	elif planform != "rectangular":
		errors.append("reference.planform: '%s' is not 'rectangular' or 'tapered'" % planform)
	var start_speed := 15.0 # the Stik's validated start (D5); other aircraft declare theirs
	if raw.has("start"):
		var start_node := _dictionary(errors, "start", raw.get("start"))
		var v = _q(errors, "start.level_speed", start_node.get("level_speed"), "m/s", 5.0, 60.0)
		if v != null:
			start_speed = v
	var bal := _dictionary(errors, "balance", raw.get("balance", {}))
	var plan_cg = _q(errors, "balance.plan_cg", bal.get("plan_cg"), "m", -2.0, 2.0, 3)
	_q(errors, "balance.firewall", bal.get("firewall"), "m", -2.0, 2.0, 3)
	var cg_tolerance = _q(errors, "balance.cg_tolerance", bal.get("cg_tolerance"), "m", 0.000001, 0.005)

	var inventory := _array(errors, "inventory", raw.get("inventory", []))
	if inventory.is_empty():
		errors.append("inventory: empty")
	var parts := []
	for i in inventory.size():
		var c: Dictionary = inventory[i] if typeof(inventory[i]) == TYPE_DICTIONARY else {}
		var label := "inventory[%d] %s" % [i, c.get("name", "?")]
		if typeof(c.get("name")) != TYPE_STRING or c.name == "":
			errors.append("inventory[%d]: missing name" % i)
		var m = _q(errors, label + ".mass", c.get("mass"), "kg", 0.001, 5.0)
		var p = _q(errors, label + ".position", c.get("position"), "m", -2.0, 2.0, 3)
		var s = _q(errors, label + ".size", c.get("size"), "m", 0.0, 4.0, 3) if c.has("size") else PackedFloat64Array([0.0, 0.0, 0.0])
		parts.append([m, p, s])

	var plaus := _dictionary(errors, "plausibility", raw.get("plausibility", {}))
	var mass_range = _q(errors, "plausibility.mass_range", plaus.get("mass_range"), "kg", 0.01, 100.0, 2)
	var inertia_ref = _q(errors, "plausibility.inertia_reference", plaus.get("inertia_reference"), "kg·m2", 0.0, 100.0, 3)

	var aero := {}
	var aero_node := _dictionary(errors, "aero", raw.get("aero", {}))
	var conventions := _dictionary(errors, "aero.conventions", aero_node.get("conventions", {}))
	var coeffs := _dictionary(errors, "aero.coefficients", aero_node.get("coefficients", {}))
	for name in COEFFICIENTS:
		var spec: Array = COEFFICIENTS[name]
		var x = _q(errors, "aero.coefficients." + name, coeffs.get(name), spec[0], -100.0, 100.0)
		if x != null:
			aero[name] = x
			if spec[1] != 0 and signf(x) != float(spec[1]):
				errors.append("aero.coefficients.%s = %s: sign must be %s for a statically stable airplane" % [name, x, "positive" if spec[1] > 0 else "negative"])
	for name in coeffs:
		if not COEFFICIENTS.has(name):
			warnings.append("aero.coefficients.%s: unknown coefficient, ignored" % name)

	var envelope := _envelope(errors, aero_node.get("envelope"), aero) if errors.is_empty() else {}
	if not envelope.is_empty():
		envelope.station_ys = station_ys(span, chords)
	var surfaces := _surfaces(errors, aero_node.get("surfaces"), aero, area, span, arp, envelope)
	if errors.is_empty() and not envelope.is_empty() and not surfaces.is_empty():
		_induced_map(envelope, surfaces, aero, area, span, chords)
	var prop := _propulsion(errors, raw.get("propulsion"))
	if not surfaces.is_empty() and surfaces.horizontal.has("downwash_gradient") and not prop.get("slipstream", {}).is_empty():
		errors.append("aero.surfaces.horizontal.downwash_gradient: not yet combined with a propeller slipstream (E0a2 first slice)")
	var hull := _crash_hull(errors, raw.get("crash_hull"))
	var controls := _controls(errors, raw.get("controls"))

	if not errors.is_empty():
		return { ok = false, errors = errors, warnings = warnings, model = {} }

	# Mass, inventory CG (le frame), inertia about the inventory CG (body FRD).
	var mass := 0.0
	var moment := PackedFloat64Array([0.0, 0.0, 0.0])
	for part in parts:
		mass += part[0]
		for k in 3:
			moment[k] += part[0] * part[1][k]
	var cg_inv := PackedFloat64Array([moment[0] / mass, moment[1] / mass, moment[2] / mass])
	var j := inertia_about(parts, cg_inv)

	if mass < mass_range[0] or mass > mass_range[1]:
		errors.append("total mass %.3f kg outside the plausible range %s kg (unit mistake?)" % [mass, mass_range])
	for axis in 3:
		if absf(cg_inv[axis]-plan_cg[axis]) > cg_tolerance:
			errors.append("balance: inventory CG axis %d disagrees with flight CG by %.4f m (tolerance %.4f m); reconcile the build before flying" % [axis, absf(cg_inv[axis]-plan_cg[axis]), cg_tolerance])
	var scale: float = (mass / 1.959) * M.pow_(span / 1.27, 2)
	var names := ["Jxx", "Jyy", "Jzz"]
	for k in 3:
		var ratio: float = j[k] / (inertia_ref[k] * scale)
		if ratio < 0.5 or ratio > 2.0:
			warnings.append("inertia: %s = %.4f kg·m2 is %.2f× the scaled UltraStick25e value" % [names[k], j[k], ratio])

	var gear := _landing_gear(errors, raw.get("landing_gear"), cg_inv, mass)

	var model := {
		id = raw.get("id", ""),
		data_sha256 = JSON.stringify(raw, "", true).sha256_text(),
		configuration = bal.get("configuration", "unspecified"),
		mass_kg = mass,
		inertia = j,
		cg_le = cg_inv,
		cg_inventory_le = cg_inv,
		reference = { S = area, b = span, c = chord, geometric_chord = area/span, arp_le = arp, planform = planform, chords = chords },
		start_speed = start_speed,
		aero = aero,
		envelope = envelope,
		surfaces = surfaces,
		conventions = conventions,
		propulsion = prop,
		controls = controls,
		crash_hull = _hull_body(hull, cg_inv),
		landing_gear = gear,
	}
	return { ok = errors.is_empty(), errors = errors, warnings = warnings, model = model }


## Landing gear (E1): optional. Without it every hull point, wheels included, is a crash (D9d). With it, each contact
## is a spring-damper on its compression; the wheel points must then be absent from the crash hull.
## Rules: at least 3 contacts, on both sides, with the CG inside their footprint (the airplane stands on its wheels);
## the heave frequency ω = sqrt(Σk / m) must satisfy ω·dt < 0.1 at the project's physics tick (ROADMAP E1: an
## explicit integrator resolves the spring instead of exciting it); each damping ratio ζ = c / (2·sqrt(k·m/n)) in
## 0.05–2 (a wire leg and a tyre, not a shock absorber, and never negative).
## E2: tyre friction is required with the gear (a gear without it slides forever): rolling_resistance C_rr (0–0.3),
## side_friction μ (0.1–1.5), peak_slip_angle (1–30°), and per contact an optional max_steering (−45–45°, default 0;
## negative for a tail wheel, which turns against the rudder's trailing edge: right rudder points its front left).
## The side force's low-speed damping rate must satisfy μ·g·dt / (tan α_peak · SLIP_FLOOR) ≤ SIDE_LAMBDA_DT_MAX.
## Returns { contacts: [{ name, position (body FRD about the CG), stiffness, damping, max_compression, max_steering
## (rad) }], reach, heave_omega, static_sag, rolling_resistance, side_friction, tan_peak_slip } or {} when absent.
static func _landing_gear(errors: PackedStringArray, node: Variant, cg: PackedFloat64Array, mass: float) -> Dictionary:
	if node == null:
		return {}
	var gear := _dictionary(errors, "landing_gear", node)
	if gear.is_empty():
		return {}
	var raw_contacts := _array(errors, "landing_gear.contacts", gear.get("contacts"))
	if raw_contacts.size() < 3:
		errors.append("landing_gear.contacts: fewer than 3 contacts")
		return {}
	var contacts := []
	var total_k := 0.0
	var reach := 0.0
	for i in raw_contacts.size():
		var label := "landing_gear.contacts[%d]" % i
		var c := _dictionary(errors, label, raw_contacts[i])
		var position = _q(errors, label + ".position", c.get("position"), "m", -3.0, 3.0, 3)
		var k = _q(errors, label + ".stiffness", c.get("stiffness"), "N/m", 1.0, 1.0e6)
		var damping = _q(errors, label + ".damping", c.get("damping"), "N·s/m", 0.0, 1.0e4)
		var travel = _q(errors, label + ".max_compression", c.get("max_compression"), "m", 0.005, 0.5)
		var steering = 0.0 if c.get("max_steering") == null else _q(errors, label + ".max_steering", c.get("max_steering"), "deg", -45.0, 45.0)
		if position == null or k == null or damping == null or travel == null or steering == null:
			continue
		if typeof(c.get("name")) != TYPE_STRING or str(c.name).strip_edges().is_empty():
			errors.append("%s: missing name" % label)
			continue
		var n := float(raw_contacts.size())
		var zeta: float = damping / (2.0 * M.sqrt_(k * mass / n))
		if zeta < 0.05 or zeta > 2.0:
			errors.append("%s.damping: ratio ζ = %.2f outside 0.05–2 (with m/%d per contact)" % [label, zeta, int(n)])
		var body := PackedFloat64Array([-(position[0] - cg[0]), position[1] - cg[1], -(position[2] - cg[2])])
		reach = maxf(reach, M.sqrt_(body[0] * body[0] + body[1] * body[1] + body[2] * body[2]))
		total_k += k
		contacts.append({ name = str(c.name), position = body, stiffness = float(k), damping = float(damping), max_compression = float(travel), max_steering = deg_to_rad(steering) })
	if not errors.is_empty() or contacts.size() < 3:
		return {}
	# D1-R3: a gear section claims the airplane stands on it, so the CG must project inside a resting facet.
	var points := []
	for i in raw_contacts.size():
		points.append(PackedFloat64Array(raw_contacts[i].position.value))
	var rest := ground_support(points, cg)
	var static_shares: PackedFloat64Array = rest.shares
	if rest.facet.is_empty():
		errors.append("landing_gear: the contacts form no support plane under the CG (collinear, vertical or above it); the airplane cannot stand on its wheels")
	elif not rest.supported:
		errors.append("landing_gear: the CG projects %.3f m outside the support polygon of contacts %s (resting %.1f° from level); the airplane cannot stand on its wheels"
			% [-float(rest.margin), str(rest.facet), rad_to_deg(rest.tilt)])
	var dt := 1.0 / float(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60))
	var omega := M.sqrt_(total_k / mass)
	if omega * dt >= 0.1:
		errors.append("landing_gear: heave ω·dt = %.3f (ω %.1f rad/s at %.0f Hz) is not < 0.1; soften the gear or raise the tick" % [omega * dt, omega, 1.0 / dt])
	var c_rr = _q(errors, "landing_gear.rolling_resistance", gear.get("rolling_resistance"), "1", 0.0, 0.3)
	var mu = _q(errors, "landing_gear.side_friction", gear.get("side_friction"), "1", 0.1, 1.5)
	var peak = _q(errors, "landing_gear.peak_slip_angle", gear.get("peak_slip_angle"), "deg", 1.0, 30.0)
	# E3b1 (optional): static ÷ rolling resistance of a wheel at rest; present = per-wheel stiction anchors.
	var breakaway = null
	if gear.get("breakaway_factor") != null:
		breakaway = _q(errors, "landing_gear.breakaway_factor", gear.get("breakaway_factor"), "1", 1.0, 2.0)
	if not errors.is_empty():
		return {}
	var tan_peak := M.tan_(deg_to_rad(peak))
	var side_lambda_dt: float = mu * 9.80665 * dt / (tan_peak * Ground.SLIP_FLOOR)
	if side_lambda_dt > Ground.SIDE_LAMBDA_DT_MAX:
		errors.append("landing_gear: side-force damping λ·dt = %.2f (μ·g / (tan α_peak · %.1f m/s) at %.0f Hz) is above %.1f; raise peak_slip_angle or the tick" % [side_lambda_dt, Ground.SLIP_FLOOR, 1.0 / dt, Ground.SIDE_LAMBDA_DT_MAX])
		return {}
	var derived := { contacts = contacts, reach = reach, heave_omega = omega, static_sag = mass * 9.80665 / total_k,
		rolling_resistance = float(c_rr), side_friction = float(mu), tan_peak_slip = tan_peak }
	if breakaway != null:
		# Numerical anchor springs at a fixed frequency (ground_contact.gd ANCHOR_OMEGA), not tyre data.
		if Ground.ANCHOR_OMEGA * dt >= 0.1:
			errors.append("landing_gear: stiction anchors ω·dt = %.3f at %.0f Hz is not < 0.1; raise the tick" % [Ground.ANCHOR_OMEGA * dt, 1.0 / dt])
			return {}
		# Each wheel's spring follows its static load share, like its hold (∝ N): all wheels reach their hold at
		# the same deflection and break away together. Shares from the resting facet (equal if not determinate).
		var shares := PackedFloat64Array()
		shares.resize(contacts.size())
		if rest.facet.size() == 3 and static_shares.size() == 3:
			for v in 3:
				shares[rest.facet[v]] = static_shares[v]
		else:
			for v in rest.facet:
				shares[v] = 1.0 / float(rest.facet.size())
		for i in contacts.size():
			var k_i: float = mass * Ground.ANCHOR_OMEGA * Ground.ANCHOR_OMEGA * shares[i]
			contacts[i].anchor_stiffness = k_i
			contacts[i].anchor_damping = 2.0 * Ground.ANCHOR_ZETA * M.sqrt_(k_i * mass * shares[i])
		derived.breakaway_factor = float(breakaway)
	return derived


## D1-R3: static support of rigid gear contacts. `points` are contact positions [x_aft, y_right, z_up] (m, LE frame) and
## `cg` the CG in the same frame. An airplane at rest sits on a lower facet of its contacts' convex hull (a plane through
## three contacts with every other contact on or above it); gravity then acts along that facet's normal. It stands when
## the CG lies above the facet and projects inside the facet polygon (all contacts within SUPPORT_PLANE_TOL of its plane),
## so a taildragger is judged at its nose-up resting attitude, not in body axes. Returns the facet with the largest
## margin: { supported, margin (m, CG projection to the nearest polygon edge, + inside), facet (contact indices),
## tilt (rad, facet normal from body up), height (m, CG above the facet), shares (static load fraction per facet
## contact: the CG projection's barycentric coordinates when three contacts carry it, statically determinate; empty
## for four or more) }; facet empty = no resting plane.
static func ground_support(points: Array, cg: PackedFloat64Array) -> Dictionary:
	var best := { supported = false, margin = -INF, facet = PackedInt32Array(), tilt = 0.0, height = 0.0,
		shares = PackedFloat64Array() }
	var n := points.size()
	for i in n:
		for j in range(i + 1, n):
			for k in range(j + 1, n):
				var a: PackedFloat64Array = points[i]
				var b: PackedFloat64Array = points[j]
				var c: PackedFloat64Array = points[k]
				var e1 := M.sub(b, a)
				var e2 := M.sub(c, a)
				var normal := M.cross(e1, e2)
				var area2 := M.norm(normal)
				if area2 < SUPPORT_AREA_MIN:
					continue # collinear triple
				if normal[2] < 0.0:
					normal = M.scale(normal, -1.0)
				var up := M.scale(normal, 1.0 / area2)
				if up[2] < SUPPORT_UP_MIN:
					continue # a vertical plane cannot be rested on
				var facet := PackedInt32Array()
				var lower := true
				for m in n:
					var height_m := M.dot(M.sub(points[m], a), up)
					if height_m < -SUPPORT_PLANE_TOL:
						lower = false
						break
					if height_m <= SUPPORT_PLANE_TOL:
						facet.append(m)
				if not lower:
					continue
				var height := M.dot(M.sub(cg, a), up)
				var q := M.sub(cg, M.scale(up, height)) # the CG projected along gravity onto the facet
				var margin := INF
				for u_index in facet.size():
					for v_index in facet.size():
						if u_index == v_index:
							continue
						var u: PackedFloat64Array = points[facet[u_index]]
						var edge := M.sub(points[facet[v_index]], u)
						var inward := M.cross(up, edge)
						var length := M.norm(inward)
						if length < SUPPORT_EDGE_MIN:
							continue
						inward = M.scale(inward, 1.0 / length)
						var hull_edge := true
						for w in facet:
							if M.dot(M.sub(points[w], u), inward) < -SUPPORT_PLANE_TOL:
								hull_edge = false
								break
						if hull_edge:
							margin = minf(margin, M.dot(M.sub(q, u), inward))
				if height <= 0.0:
					margin = minf(margin, height) # a CG on or under the wheels is not held up by them
				if margin > best.margin:
					var shares := PackedFloat64Array()
					if facet.size() == 3:
						# Barycentric weights of q: each contact's share of the weight (moment balance on the facet).
						var whole := M.dot(M.cross(M.sub(points[facet[1]], points[facet[0]]), M.sub(points[facet[2]], points[facet[0]])), up)
						for v in 3:
							var b2: PackedFloat64Array = points[facet[(v + 1) % 3]]
							var c2: PackedFloat64Array = points[facet[(v + 2) % 3]]
							shares.append(M.dot(M.cross(M.sub(b2, q), M.sub(c2, q)), up) / whole)
					best = { supported = margin > 0.0, margin = margin, facet = facet, tilt = M.acos_(clampf(up[2], -1.0, 1.0)),
						height = height, shares = shares }
	return best


## Spanwise positions (m, ±) of the equal-area wing strips for the asymmetric stall (D9b), left side first.
## chords = [root, tip] (linear taper to the tip) or empty (rectangular). Each strip carries S / (2n) and its load
## acts at the strip's area centroid, so the strips' rolling moments add up to the wing's. Rectangular: ±(k + ½)/n.
static func station_ys(span: float, chords: PackedFloat64Array) -> PackedFloat64Array:
	var n: int = Aero.WING_STATIONS_PER_SIDE
	var h := span / 2.0
	var centres := PackedFloat64Array()
	if chords.is_empty() or is_equal_approx(chords[0], chords[1]):
		for k in n:
			centres.append((k + 0.5) / n * h)
	else:
		var cr := chords[0]
		var slope := (chords[1] - cr) / h # chord change per metre of semi-span
		var area := func(y: float) -> float: return cr * y + slope * y * y / 2.0
		var moment := func(y: float) -> float: return cr * y * y / 2.0 + slope * y * y * y / 3.0
		var total: float = area.call(h)
		var y0 := 0.0
		for k in n:
			# Strip edge where the area from the root reaches (k + 1)/n of the semi-span's: slope/2·y² + cr·y − A = 0.
			var target := total * (k + 1) / n
			var y1 := h if k == n - 1 else (-cr + M.sqrt_(cr * cr + 2.0 * slope * target)) / slope
			centres.append((moment.call(y1) - moment.call(y0)) / (area.call(y1) - area.call(y0)))
			y0 = y1
	var ys := PackedFloat64Array()
	for k in range(n - 1, -1, -1):
		ys.append(-centres[k])
	ys.append_array(centres)
	return ys


## D11d: strip edges (m, left tip … right tip, 2n + 1 values) with the same equal-area split as station_ys().
static func station_edges(span: float, chords: PackedFloat64Array) -> PackedFloat64Array:
	var n: int = Aero.WING_STATIONS_PER_SIDE
	var h := span / 2.0
	var right := PackedFloat64Array([0.0])
	if chords.is_empty() or is_equal_approx(chords[0], chords[1]):
		for k in n:
			right.append((k + 1.0) / n * h)
	else:
		var cr := chords[0]
		var slope := (chords[1] - cr) / h
		var total := cr * h + slope * h * h / 2.0
		for k in n:
			var target := total * (k + 1) / n
			right.append(h if k == n - 1 else (-cr + M.sqrt_(cr * cr + 2.0 * slope * target)) / slope)
	var edges := PackedFloat64Array()
	for k in range(n, 0, -1):
		edges.append(-right[k])
	edges.append_array(right)
	return edges


## D11d: induced-flow coupling of the wing strips (Weissinger: bound vortex at the quarter chord, control point at
## three-quarter chord, planar and unswept, trailing legs straight aft). K[i][j] is the induced angle at strip i per unit
## section lift coefficient on strip j, without strip i's own 2-D bound-vortex term (the section slope a0 carries it;
## a0 = 2π reproduces Weissinger exactly). Lift is then Cl = a0·(E·α), E = (I + a0·K)⁻¹: an antisymmetric (rolling)
## load induces more downwash than a symmetric one, which strip theory without induced flow misses (Clp ≈ −a/6).
## Consistency with the oracle, solved here: a0 makes the local wing + horizontal tail lift slope equal aero.CLa, and the
## per-strip offset strip_cl0 makes their CL at α 0 equal aero.CL0 (the same airplane in two models, not a fit to
## flight data). Clp is then a prediction. Stores envelope.strip_slope (a0), strip_cl0 (per strip), induced_map (E).
static func _induced_map(envelope: Dictionary, surfaces: Dictionary, aero: Dictionary, area: float, span: float,
		chords: PackedFloat64Array) -> void:
	var edges := station_edges(span, chords)
	var ys: PackedFloat64Array = envelope.station_ys
	var n := ys.size()
	var h := span / 2.0
	var chord := PackedFloat64Array()
	for j in n:
		var y: float = absf(ys[j])
		chord.append(area / span if chords.is_empty() else chords[0] + (chords[1] - chords[0]) * y / h)
	var k_map := strip_influence(edges, ys, chord)
	var horizontal: Dictionary = surfaces.horizontal
	var tail_share: float = float(horizontal.area) / area * float(horizontal.lift_slope)
	var target: float = float(aero.CLa) - tail_share
	# wsum(a0) = area-weighted Σ E·1 rises with a0 slower than 1/a0 falls: a0·wsum(a0) is monotonic; bisection.
	var lo := 0.1
	var hi := 50.0
	var e_map := PackedFloat64Array()
	for iteration in 80:
		var a0 := 0.5 * (lo + hi)
		e_map = effective_angle_map(k_map, a0, n)
		if a0 * _row_mean(e_map, n) < target:
			lo = a0
		else:
			hi = a0
	var a0 := 0.5 * (lo + hi)
	e_map = effective_angle_map(k_map, a0, n)
	var wsum := _row_mean(e_map, n)
	var twist: PackedFloat64Array = surfaces.get("station_incidence", PackedFloat64Array())
	var twist_lift := 0.0
	for i in n:
		for k in n:
			twist_lift += e_map[i * n + k] * (twist[k] if not twist.is_empty() else 0.0)
	twist_lift *= a0 / float(n)
	var alpha_s: float = (float(aero.CL0) - tail_share * float(horizontal.incidence) - twist_lift) / (a0 * wsum)
	var cl0 := PackedFloat64Array()
	for i in n:
		var row := 0.0
		for k in n:
			row += e_map[i * n + k]
		cl0.append(a0 * alpha_s * row)
	envelope.strip_slope = a0
	envelope.strip_cl0 = cl0
	envelope.induced_map = e_map
	if horizontal.has("downwash_gradient"):
		# E0a2: free tail law. Static tail lift is unchanged: free_slope·((1 − dε/dα)·α − k_ε·CL_w0 + i_free) equals
		# lift_slope·(α + incidence), with CL_w = CLα_w·α + CL_w0 the local wing (D11d) and k_ε = (dε/dα)/CLα_w. The
		# elevator's τ = control_effectiveness·(1 − dε/dα) keeps Cmde; pitch rate now acts on the free slope.
		var gradient: float = horizontal.downwash_gradient
		var keep := 1.0 - gradient
		var wing_cl0 := twist_lift
		for i in n:
			wing_cl0 += cl0[i] / float(n)
		var per_cl := gradient / target
		horizontal.free_slope = float(horizontal.lift_slope) / keep
		horizontal.elevator_tau = float(horizontal.control_effectiveness) * keep
		horizontal.downwash_per_cl = per_cl
		horizontal.free_incidence = keep * float(horizontal.incidence) + per_cl * wing_cl0
		horizontal.wing_cl0 = wing_cl0
		# E0a2b: the wake travels from the wing's quarter chord to the tail's pressure centre (le frame, x aft).
		horizontal.downwash_lag_length = float(horizontal.position[0]) - 0.25 * area / span


## D11d: Weissinger influence matrix K (row-major n×n) for strips with the given edges (2n + 1), control-point y and
## chords: induced angle at strip i's three-quarter-chord point per unit lift coefficient on strip j, minus strip i's
## own 2-D bound-vortex term 1/2π.
static func strip_influence(edges: PackedFloat64Array, ys: PackedFloat64Array, chord: PackedFloat64Array) -> PackedFloat64Array:
	var n := ys.size()
	var k_map := PackedFloat64Array()
	k_map.resize(n * n)
	for i in n:
		var px: float = chord[i] / 2.0
		var py: float = ys[i]
		for j in n:
			var a: float = edges[j]
			var b: float = edges[j + 1]
			var w: float = _vortex_z(px, py, 1e5, a, 0.0, a) + _vortex_z(px, py, 0.0, a, 0.0, b) + _vortex_z(px, py, 0.0, b, 1e5, b)
			k_map[i * n + j] = -w * 0.5 * chord[j] - (1.0 / TAU if i == j else 0.0)
	return k_map


## (I + a0·K)⁻¹ by Gauss–Jordan with partial pivoting (row-major n×n).
static func effective_angle_map(k_map: PackedFloat64Array, a0: float, n: int) -> PackedFloat64Array:
	var a := PackedFloat64Array()
	var inv := PackedFloat64Array()
	a.resize(n * n)
	inv.resize(n * n)
	for i in n:
		for j in n:
			a[i * n + j] = (1.0 if i == j else 0.0) + a0 * k_map[i * n + j]
		inv[i * n + i] = 1.0
	for col in n:
		var pivot := col
		for r in range(col + 1, n):
			if absf(a[r * n + col]) > absf(a[pivot * n + col]):
				pivot = r
		for k in n:
			var t := a[col * n + k]
			a[col * n + k] = a[pivot * n + k]
			a[pivot * n + k] = t
			t = inv[col * n + k]
			inv[col * n + k] = inv[pivot * n + k]
			inv[pivot * n + k] = t
		var d := a[col * n + col]
		for k in n:
			a[col * n + k] /= d
			inv[col * n + k] /= d
		for r in n:
			if r != col:
				var f := a[r * n + col]
				for k in n:
					a[r * n + k] -= f * a[col * n + k]
					inv[r * n + k] -= f * inv[col * n + k]
	return inv


## Mean row sum of a row-major n×n map (equal-area strips: the area-weighted lift per unit α, divided by a0).
static func _row_mean(e_map: PackedFloat64Array, n: int) -> float:
	var total := 0.0
	for v in e_map:
		total += v
	return total / float(n)


## z-velocity (up) at planar point (px, py) from a unit vortex segment (x1, y1) → (x2, y2) in the wing plane.
static func _vortex_z(px: float, py: float, x1: float, y1: float, x2: float, y2: float) -> float:
	var r1x := px - x1
	var r1y := py - y1
	var r2x := px - x2
	var r2y := py - y2
	var cross := r1x * r2y - r1y * r2x
	if absf(cross) < 1e-14:
		return 0.0
	var n1 := M.sqrt_(r1x * r1x + r1y * r1y)
	var n2 := M.sqrt_(r2x * r2x + r2y * r2y)
	var dot := (x2 - x1) * (r1x / n1 - r2x / n2) + (y2 - y1) * (r1y / n1 - r2y / n2)
	return dot / (4.0 * PI * cross)


## Inertia tensor entries [Jxx Jyy Jzz Jxy Jxz Jyz] in body FRD about `point` (le frame).
## Each part: [mass, position (le frame), box size [along x_aft, y, z_up]]: box intrinsic inertia + parallel axis.
static func inertia_about(parts: Array, point: PackedFloat64Array) -> PackedFloat64Array:
	var j := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	for part in parts:
		var m: float = part[0]
		var p: PackedFloat64Array = part[1]
		var s: PackedFloat64Array = part[2]
		# le frame [x_aft, y_right, z_up] → body FRD [x fwd, y right, z down]
		var x := -(p[0] - point[0])
		var y := p[1] - point[1]
		var z := -(p[2] - point[2])
		j[0] += m * (y * y + z * z) + m * (s[1] * s[1] + s[2] * s[2]) / 12.0
		j[1] += m * (x * x + z * z) + m * (s[0] * s[0] + s[2] * s[2]) / 12.0
		j[2] += m * (x * x + y * y) + m * (s[0] * s[0] + s[1] * s[1]) / 12.0
		j[3] -= m * x * y
		j[4] -= m * x * z
		j[5] -= m * y * z
	return j


## A coefficient table: [[J, value], …] with J strictly increasing from 0. Returns [J0, v0, J1, v1, …].
static func _table(errors: PackedStringArray, path: String, node: Variant, lo: float, hi: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	if typeof(node) != TYPE_DICTIONARY or not node.has("value") or typeof(node.value) != TYPE_ARRAY:
		errors.append("%s: missing table" % path)
		return out
	for key in ["unit", "kind", "source"]:
		if not node.has(key):
			errors.append("%s: missing '%s'" % [path, key])
	if node.get("unit") != "1":
		errors.append("%s: unit '%s', expected '1'" % [path, node.get("unit")])
	if not (node.get("kind") in KINDS):
		errors.append("%s: kind '%s' is not one of %s" % [path, node.get("kind"), KINDS])
	if typeof(node.get("source")) != TYPE_STRING or str(node.get("source")).strip_edges().is_empty():
		errors.append("%s: empty source" % path)
	var rows: Array = node.value
	if rows.size() < 2:
		errors.append("%s: needs at least 2 rows" % path)
		return out
	for i in rows.size():
		var row = rows[i]
		if typeof(row) != TYPE_ARRAY or row.size() != 2:
			errors.append("%s[%d]: expected [J, value]" % [path, i])
			return PackedFloat64Array()
		for value in row:
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
				errors.append("%s[%d]: J and value must be finite numbers" % [path, i])
				return PackedFloat64Array()
		var j_value := float(row[0])
		var coefficient := float(row[1])
		if i == 0 and j_value != 0.0:
			errors.append("%s: first row must be J = 0" % path)
		if i > 0 and j_value <= float(rows[i - 1][0]):
			errors.append("%s[%d]: J must increase" % [path, i])
		if coefficient < lo or coefficient > hi:
			errors.append("%s[%d]: %s outside [%s, %s]" % [path, i, coefficient, lo, hi])
		out.append(j_value)
		out.append(coefficient)
	return out


static func _propulsion(errors: PackedStringArray, node: Variant) -> Dictionary:
	if typeof(node) != TYPE_DICTIONARY:
		errors.append("propulsion: missing")
		return {}
	# AV-05: `kind` selects the branch; absent = the glow engine and propeller (every file before AV-05).
	var kind: Variant = node.get("kind", "glow_prop")
	if kind == "turbine":
		return _turbine(errors, node)
	if kind != "glow_prop":
		errors.append("propulsion.kind: '%s' is not 'glow_prop' or 'turbine'" % kind)
		return {}
	var e := _dictionary(errors, "propulsion.engine", node.get("engine", {}))
	var pr := _dictionary(errors, "propulsion.propeller", node.get("propeller", {}))
	var max_rpm = _q(errors, "propulsion.engine.max_rpm_static", e.get("max_rpm_static"), "rpm", 1000.0, 50000.0)
	var idle = _q(errors, "propulsion.engine.idle_rpm", e.get("idle_rpm"), "rpm", 0.0, 20000.0)
	var lag = _q(errors, "propulsion.engine.lag_time_constant", e.get("lag_time_constant"), "s", 0.01, 5.0)
	_q(errors, "propulsion.engine.peak_power", e.get("peak_power"), "W", 10.0, 20000.0)
	_q(errors, "propulsion.engine.peak_power_rpm", e.get("peak_power_rpm"), "rpm", 1000.0, 50000.0)
	var diameter = _q(errors, "propulsion.propeller.diameter", pr.get("diameter"), "m", 0.05, 2.0)
	var offset = _q(errors, "propulsion.propeller.thrust_line_offset", pr.get("thrust_line_offset"), "m", -1.0, 1.0, 3)
	var rotor = _q(errors, "propulsion.propeller.rotating_inertia", pr.get("rotating_inertia"), "kg·m2", 0.0, 0.1)
	var ct := _table(errors, "propulsion.propeller.ct_table", pr.get("ct_table"), -0.5, 0.5)
	# Cp below 0 = the windmilling branch (the air drives the propeller); only a shaft model may use it.
	var cp := _table(errors, "propulsion.propeller.cp_table", pr.get("cp_table"), -0.3 if e.has("shaft") else 0.0, 0.5)
	if max_rpm != null and idle != null and idle >= max_rpm:
		errors.append("propulsion.engine: idle_rpm %s must be below max_rpm_static %s" % [idle, max_rpm])
	if not ct.is_empty() and ct[1] <= 0.0:
		errors.append("propulsion.propeller.ct_table: static Ct must be positive (a propeller that pushes)")
	if not cp.is_empty() and cp[1] <= 0.0:
		errors.append("propulsion.propeller.cp_table: static Cp must be positive (a propeller that absorbs power)")
	var out := { max_rpm = max_rpm, idle_rpm = idle, lag = lag, diameter = diameter, offset = offset, ct = ct, cp = cp, rotor_inertia = rotor }
	# Optional (P51-06/12): each absent key leaves the D5 behaviour bit for bit.
	if e.has("shaft"):
		out.shaft = _shaft(errors, e.get("shaft"), rotor)
		var cp_min := 0.0
		for i in range(1, cp.size(), 2):
			cp_min = minf(cp_min, cp[i])
		out.cp_min = cp_min
	if pr.has("thrust_angles"):
		var angles = _q(errors, "propulsion.propeller.thrust_angles", pr.get("thrust_angles"), "deg", -10.0, 10.0, 2)
		if angles != null:
			var down := deg_to_rad(angles[0])
			var right := deg_to_rad(angles[1])
			out.axis = PackedFloat64Array([M.cos_(down) * M.cos_(right), M.cos_(down) * M.sin_(right), M.sin_(down)])
	if pr.has("normal_force"):
		if not out.has("axis"):
			errors.append("propulsion.propeller.normal_force: needs thrust_angles (give [0, 0] for an axial shaft)")
		out.normal_force = _table(errors, "propulsion.propeller.normal_force", pr.get("normal_force"), 0.0, 1.0)
	if pr.has("pfactor_moment"):
		if not out.has("axis"):
			errors.append("propulsion.propeller.pfactor_moment: needs thrust_angles (give [0, 0] for an axial shaft)")
		out.pfactor_moment = _table(errors, "propulsion.propeller.pfactor_moment", pr.get("pfactor_moment"), 0.0, 1.0)
	if pr.has("slipstream"):
		if not out.has("axis"):
			errors.append("propulsion.propeller.slipstream: needs thrust_angles (give [0, 0] for an axial shaft)")
		out.slipstream = _slipstream(errors, pr.get("slipstream"))
	return out


## Shaft balance (G2 first slice, P51-06): { power_curve [rpm0, W0, …] (full-throttle brake power), friction
## [N·m, N·m per 1000 rpm], idle_power and peak_indicated_power (W, admitted by the closed and the open throttle) }.
static func _shaft(errors: PackedStringArray, node: Variant, rotor: Variant) -> Dictionary:
	var sh := _dictionary(errors, "propulsion.engine.shaft", node)
	var path := "propulsion.engine.shaft.power_curve"
	var curve := _xy_table(errors, path, sh.get("power_curve"), "rpm, W", 0.0, INF)
	# The shared table validator checks types, finiteness, order and provenance.
	# Shaft samples additionally require strictly positive RPM and brake power.
	for i in range(0, curve.size(), 2):
		if curve[i] <= 0.0 or curve[i + 1] <= 0.0:
			errors.append("%s[%d]: RPM and power must be > 0" % [path, i / 2])
	var friction = _q(errors, "propulsion.engine.shaft.friction_torque", sh.get("friction_torque"), "N·m, N·m/krpm", 0.0, 20.0, 2)
	var idle = _q(errors, "propulsion.engine.shaft.idle_power", sh.get("idle_power"), "W", 0.0, 20000.0)
	var peak = _q(errors, "propulsion.engine.shaft.peak_indicated_power", sh.get("peak_indicated_power"), "W", 10.0, 30000.0)
	if rotor != null and rotor <= 0.0:
		errors.append("propulsion.propeller.rotating_inertia: a shaft model needs a positive rotating inertia")
	if not errors.is_empty():
		return {}
	if idle >= peak:
		errors.append("propulsion.engine.shaft: idle_power must be below peak_indicated_power")
	return { power_curve = curve, friction = friction, idle_power = idle, peak_indicated_power = peak }


## Tail slipstream (E0b first slice, P51-12): { hub (le), wash_factor [static, forward] (× disc induced velocity), swirl_factor, vertical_drift, pieces: [{ surface
## ("horizontal"/"vertical"), area (m2), root (le), span_dir (le unit vector), span (m), chords [root, tip] (m) }] }.
static func _slipstream(errors: PackedStringArray, node: Variant) -> Dictionary:
	var ss := _dictionary(errors, "propulsion.propeller.slipstream", node)
	var out := {
		hub = _q(errors, "propulsion.propeller.slipstream.hub", ss.get("hub"), "m", -2.0, 2.0, 3),
		wash_factor = _q(errors, "propulsion.propeller.slipstream.wash_factor", ss.get("wash_factor"), "1", 0.0, 2.0, 2),
		swirl_factor = _q(errors, "propulsion.propeller.slipstream.swirl_factor", ss.get("swirl_factor"), "1", 0.0, 1.0),
		vertical_drift = _q(errors, "propulsion.propeller.slipstream.vertical_drift", ss.get("vertical_drift"), "1", 0.0, 1.0),
		pieces = [],
	}
	var raw := _array(errors, "propulsion.propeller.slipstream.pieces", ss.get("pieces"))
	for i in raw.size():
		var label := "propulsion.propeller.slipstream.pieces[%d]" % i
		var pc := _dictionary(errors, label, raw[i])
		var surface: Variant = pc.get("surface")
		if not (surface in ["horizontal", "vertical"]):
			errors.append("%s.surface: '%s' is not 'horizontal' or 'vertical'" % [label, surface])
		var piece := {
			surface = str(surface),
			area = _q(errors, label + ".area", pc.get("area"), "m2", 0.001, 1.0),
			root = _q(errors, label + ".root", pc.get("root"), "m", -3.0, 3.0, 3),
			span_dir = _q(errors, label + ".span_dir", pc.get("span_dir"), "1", -1.0, 1.0, 3),
			span = _q(errors, label + ".span", pc.get("span"), "m", 0.01, 2.0),
			chords = _q(errors, label + ".chords", pc.get("chords"), "m", 0.005, 1.0, 2),
		}
		if piece.span_dir != null and absf(M.sqrt_(piece.span_dir[0] ** 2 + piece.span_dir[1] ** 2 + piece.span_dir[2] ** 2) - 1.0) > 1e-6:
			errors.append("%s.span_dir: must be a unit vector" % label)
		out.pieces.append(piece)
	return out if errors.is_empty() else {}


## Turbojet (AV-05, physics/turbine.gd). engine: idle_rpm < max_rpm; tables as {value: [[x, y], …], unit "<x>, <y>",
## kind, source} with x strictly increasing: static_thrust ("rpm, N", bench at STP, ≥ 0), mass_flow ("rpm, kg/s",
## > 0), fuel_flow ("rpm, kg/s", ≥ 0), throttle_map ("1, rpm": throttle 0 → idle_rpm, 1 → max_rpm, rpm increasing),
## accel_limit / decel_limit ("rpm, rpm/s", > 0); installed_factor (0.5–1), governor_tau (s), rotor_inertia (kg·m2),
## rotor_sense (+1 clockwise from behind, −1 counter-clockwise). thrust_line_offset and intake_offset (centroid of the
## intakes), [x_aft, y_right, z_up] from the CG; optional thrust_angles ([down, right] deg) as for a propeller. Returns the model dict Turbine reads, with max_rpm/idle_rpm for telemetry.
static func _turbine(errors: PackedStringArray, node: Dictionary) -> Dictionary:
	var e := _dictionary(errors, "propulsion.engine", node.get("engine", {}))
	var p := "propulsion.engine."
	var idle = _q(errors, p + "idle_rpm", e.get("idle_rpm"), "rpm", 1000.0, 300000.0)
	var max_rpm = _q(errors, p + "max_rpm", e.get("max_rpm"), "rpm", 1000.0, 300000.0)
	var out := {
		kind = "turbine",
		idle_rpm = idle,
		max_rpm = max_rpm,
		static_thrust = _xy_table(errors, p + "static_thrust", e.get("static_thrust"), "rpm, N", 0.0, 5000.0),
		mass_flow = _xy_table(errors, p + "mass_flow", e.get("mass_flow"), "rpm, kg/s", 1e-4, 20.0),
		fuel_flow = _xy_table(errors, p + "fuel_flow", e.get("fuel_flow"), "rpm, kg/s", 0.0, 1.0),
		throttle_map = _xy_table(errors, p + "throttle_map", e.get("throttle_map"), "1, rpm", 0.0, 300000.0),
		accel_limit = _xy_table(errors, p + "accel_limit", e.get("accel_limit"), "rpm, rpm/s", 1.0, 1.0e6),
		decel_limit = _xy_table(errors, p + "decel_limit", e.get("decel_limit"), "rpm, rpm/s", 1.0, 1.0e6),
		installed_factor = _q(errors, p + "installed_factor", e.get("installed_factor"), "1", 0.5, 1.0),
		governor_tau = _q(errors, p + "governor_tau", e.get("governor_tau"), "s", 0.02, 2.0),
		rotor_inertia = _q(errors, p + "rotor_inertia", e.get("rotor_inertia"), "kg·m2", 0.0, 0.01),
		rotor_sense = _q(errors, p + "rotor_sense", e.get("rotor_sense"), "1", -1.0, 1.0),
		offset = _q(errors, "propulsion.thrust_line_offset", node.get("thrust_line_offset"), "m", -1.0, 1.0, 3),
		intake_offset = _q(errors, "propulsion.intake_offset", node.get("intake_offset"), "m", -1.0, 1.0, 3),
		axis = PackedFloat64Array([1.0, 0.0, 0.0]),
	}
	# Optional ram recovery (fitted to a cycle model): ṁ grows by (1 + ram_flow·u²), V_jet² by ram_jet(N)·u².
	if e.has("ram_flow"):
		out.ram_flow = _q(errors, p + "ram_flow", e.get("ram_flow"), "s2/m2", 0.0, 1e-3)
	if e.has("ram_jet"):
		out.ram_jet = _xy_table(errors, p + "ram_jet", e.get("ram_jet"), "rpm, 1", 0.0, 10.0)
	for key in ["propeller", "diameter", "ct_table", "cp_table", "shaft", "slipstream"]:
		if node.has(key) or e.has(key):
			errors.append("propulsion: '%s' does not apply to a turbine" % key)
	if node.has("thrust_angles"):
		var angles = _q(errors, "propulsion.thrust_angles", node.get("thrust_angles"), "deg", -10.0, 10.0, 2)
		if angles != null:
			var down := deg_to_rad(angles[0])
			var right := deg_to_rad(angles[1])
			out.axis = PackedFloat64Array([M.cos_(down) * M.cos_(right), M.cos_(down) * M.sin_(right), M.sin_(down)])
	if not errors.is_empty():
		return {}
	if idle >= max_rpm:
		errors.append("propulsion.engine: idle_rpm %s must be below max_rpm %s" % [idle, max_rpm])
	var tm: PackedFloat64Array = out.throttle_map
	if tm[0] != 0.0 or tm[tm.size() - 2] != 1.0 or absf(tm[1] - idle) > 1.0 or absf(tm[tm.size() - 1] - max_rpm) > 1.0:
		errors.append("propulsion.engine.throttle_map: must run from [0, idle_rpm] to [1, max_rpm]")
	for i in range(3, tm.size(), 2):
		if tm[i] <= tm[i - 2]:
			errors.append("propulsion.engine.throttle_map: rpm must increase with throttle")
			break
	if absf(out.rotor_sense) != 1.0:
		errors.append("propulsion.engine.rotor_sense: must be +1 or -1")
	return out if errors.is_empty() else {}


## A data table {value: [[x, y], …] (2+ rows, x strictly increasing), unit, kind, source} → [x0, y0, x1, y1, …].
static func _xy_table(errors: PackedStringArray, path: String, node: Variant, unit: String, lo: float, hi: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	if typeof(node) != TYPE_DICTIONARY or typeof(node.get("value")) != TYPE_ARRAY or (node.value as Array).size() < 2:
		errors.append("%s: expected {value: [[x, y], …] (2+ rows), unit, kind, source}" % path)
		return out
	if typeof(node.get("unit")) != TYPE_STRING or node.get("unit") != unit:
		errors.append("%s: unit '%s', expected '%s'" % [path, node.get("unit"), unit])
	if not (node.get("kind") in KINDS) or typeof(node.get("source")) != TYPE_STRING or str(node.get("source")).strip_edges().is_empty():
		errors.append("%s: invalid evidence kind or empty source" % path)
	for row in node.value:
		if typeof(row) != TYPE_ARRAY or row.size() != 2 or typeof(row[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(row[1]) not in [TYPE_INT, TYPE_FLOAT] \
				or not is_finite(float(row[0])) or not is_finite(float(row[1])):
			errors.append("%s: each row must be two finite numbers" % path)
			return PackedFloat64Array()
		if out.size() > 0 and float(row[0]) <= out[out.size() - 2]:
			errors.append("%s: x must increase strictly" % path)
			return PackedFloat64Array()
		if float(row[1]) < lo or float(row[1]) > hi:
			errors.append("%s: %s outside [%s, %s]" % [path, row[1], lo, hi])
		out.append(float(row[0]))
		out.append(float(row[1]))
	return out


## Maximum surface throws (each surface's deflection at full stick), degrees in the file.
static func _controls(errors: PackedStringArray, node: Variant) -> Dictionary:
	if typeof(node) != TYPE_DICTIONARY:
		errors.append("controls: missing")
		return {}
	var throws := _dictionary(errors, "controls.max_throw", node.get("max_throw", {}))
	var deg := {}
	var rad := {}
	for surface in ["aileron", "elevator", "rudder"]:
		var x = _q(errors, "controls.max_throw." + surface, throws.get(surface), "deg", 1.0, 60.0)
		if x != null:
			deg[surface] = x
			rad[surface] = deg_to_rad(x)
	# Optional (AV-06): differential ailerons, the down-going aileron's maximum (≤ the up throw, `aileron`).
	if throws.has("aileron_down"):
		var down = _q(errors, "controls.max_throw.aileron_down", throws.get("aileron_down"), "deg", 1.0, 60.0)
		if down != null and deg.has("aileron") and down > deg.aileron:
			errors.append("controls.max_throw.aileron_down %s exceeds the up throw %s (a differential throws less down)" % [down, deg.aileron])
		elif down != null:
			deg.aileron_down = down
			rad.aileron_down = deg_to_rad(down)
	var t = _q(errors, "controls.servo_full_throw_time", node.get("servo_full_throw_time"), "s", 0.01, 2.0)
	return { throw_deg = deg, throw_rad = rad, servo_rate = 1.0 / t if t != null else 0.0 }


## Full-envelope parameters (D9a). The stall start angles are SOLVED so that the blended lift curve peaks exactly at
## CL_max (positive) and CL_min (negative) for the given blend width. Returns
## { a1, a2, n1, n2, b1, b2 (rad), CD90, CL_max, CL_min }, or {} with errors.
static func _envelope(errors: PackedStringArray, node: Variant, aero: Dictionary) -> Dictionary:
	if typeof(node) != TYPE_DICTIONARY:
		errors.append("aero.envelope: missing")
		return {}
	var cl_max = _q(errors, "aero.envelope.CL_max", node.get("CL_max"), "1", 0.3, 3.0)
	var cl_min = _q(errors, "aero.envelope.CL_min", node.get("CL_min"), "1", -3.0, -0.1)
	var width = _q(errors, "aero.envelope.stall_blend_width", node.get("stall_blend_width"), "deg", 1.0, 30.0)
	var cd90 = _q(errors, "aero.envelope.CD90", node.get("CD90"), "1", 0.5, 2.5)
	var sb = _q(errors, "aero.envelope.sideslip_blend", node.get("sideslip_blend"), "deg", 1.0, 89.0, 2)
	if not errors.is_empty():
		return {}
	if sb[0] >= sb[1]:
		errors.append("aero.envelope.sideslip_blend: start %s must be below end %s" % [sb[0], sb[1]])
	if cd90 / 2.0 >= cl_max or cd90 / 2.0 >= -cl_min:
		errors.append("aero.envelope.CD90 = %s: the flat plate (peak CD90/2) must lift less than the stall limits" % cd90)
	var w := deg_to_rad(width)
	var a1 := _solve_stall_start(aero, cd90, w, cl_max, 1.0)
	var n1 := _solve_stall_start(aero, cd90, w, cl_min, -1.0)
	var oracle := deg_to_rad(ORACLE_ALPHA_DEG)
	if a1 < oracle or n1 < oracle:
		errors.append("aero.envelope: the stall blend would start at %+.1f° / %+.1f°, inside the ±%.0f° linear-oracle region (raise CL_max / CL_min or narrow the blend)" % [rad_to_deg(a1), -rad_to_deg(n1), ORACLE_ALPHA_DEG])
	return { a1 = a1, a2 = a1 + w, n1 = n1, n2 = n1 + w, b1 = deg_to_rad(sb[0]), b2 = deg_to_rad(sb[1]), CD90 = cd90, CL_max = cl_max, CL_min = cl_min }


## Stall start (rad, magnitude) on one side (sign +1 / −1) such that the blended lift's extreme equals `target`.
## Bisection: a later start keeps the linear rise longer, so the peak grows monotonically with the start.
static func _solve_stall_start(aero: Dictionary, cd90: float, width: float, target: float, sign: float) -> float:
	var lo := 0.0
	var hi := (target - float(aero.CL0)) / float(aero.CLa) * sign # where the linear lift alone reaches the target
	for i in 60:
		var mid := 0.5 * (lo + hi)
		if _blend_extreme(aero, cd90, width, mid, sign) * sign < target * sign:
			lo = mid
		else:
			hi = mid
	return 0.5 * (lo + hi)


static func _blend_extreme(aero: Dictionary, cd90: float, width: float, start: float, sign: float) -> float:
	var env := { a1 = start, a2 = start + width, n1 = start, n2 = start + width, b1 = 1.0, b2 = 2.0, CD90 = cd90 }
	var best := 0.0
	for k in 801: # 0.01·width steps across the blend, plus its edges
		var alpha := sign * (start + width * (float(k) / 800.0) * 1.25)
		var cl := Aero.lift_alpha(alpha, aero, env)
		if cl * sign > best * sign:
			best = cl
	return best


## Crash hull (D9d): points [x_aft, y_right, z_up] (le frame) that touch the ground first. Returns them flattened.
static func _crash_hull(errors: PackedStringArray, node: Variant) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	if typeof(node) != TYPE_DICTIONARY or typeof(node.get("value")) != TYPE_ARRAY or (node.value as Array).size() < 4:
		errors.append("crash_hull: missing or fewer than 4 points")
		return out
	for key in ["unit", "kind", "source"]:
		if not node.has(key):
			errors.append("crash_hull: missing '%s'" % key)
	if node.get("kind") not in KINDS or typeof(node.get("source")) != TYPE_STRING or str(node.get("source")).strip_edges().is_empty():
		errors.append("crash_hull: invalid evidence kind or empty source")
	if node.get("unit") != "m":
		errors.append("crash_hull: unit '%s', expected 'm'" % node.get("unit"))
	for p in node.value:
		if typeof(p) != TYPE_ARRAY or p.size() != 3:
			errors.append("crash_hull: each point needs 3 numbers")
			return PackedFloat64Array()
		for x in p:
			if typeof(x) not in [TYPE_INT, TYPE_FLOAT]:
				errors.append("crash_hull: %s is not a numeric point within 3 m" % [p])
				return PackedFloat64Array()
			var coordinate := float(x)
			if not is_finite(coordinate) or absf(coordinate) > 3.0:
				errors.append("crash_hull: %s is not a finite point within 3 m" % [p])
				return PackedFloat64Array()
			out.append(coordinate)
	return out


## Hull points converted to body FRD about the CG: [x fwd, y right, z down], flattened.
static func _hull_body(hull: PackedFloat64Array, cg: Variant) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	if cg == null:
		return out
	for i in range(0, hull.size(), 3):
		out.append_array(PackedFloat64Array([-(hull[i] - cg[0]), hull[i + 1] - cg[1], -(hull[i + 2] - cg[2])]))
	return out


## Local-surface data has explicit evidence like the reference derivatives. Linked rudder
## derivatives are about ARP, not CG; the final load transfer supplies the remaining arm.
static func _surfaces(errors: PackedStringArray, node: Variant, aero: Dictionary,
		area: Variant, span: Variant, arp: Variant, env: Dictionary) -> Dictionary:
	if typeof(node) != TYPE_DICTIONARY:
		errors.append("aero.surfaces: expected an object")
		return {}
	if not errors.is_empty():
		return {}
	if env.is_empty():
		errors.append("aero.surfaces: envelope is empty or invalid")
		return {}
	var out := {}
	var specs := {
		wing_aileron_effectiveness = ["1", 0.01, 1.0],
		attached_limit = ["deg", 1.0, 8.0], tail_local_limit = ["deg", 9.0, 30.0],
		tail_stall_end = ["deg", 10.0, 60.0], tail_CD0 = ["1", 0.001, 0.2],
		tail_k = ["1", 0.0, 2.0], tail_CD90 = ["1", 0.5, 2.5],
	}
	for key in specs:
		var spec: Array = specs[key]
		var value = _q(errors, "aero.surfaces." + key, node.get(key), spec[0], spec[1], spec[2])
		if value != null:
			out[key] = deg_to_rad(value) if spec[0] == "deg" else value
	# Optional (P51-12): per-strip angle offsets root → tip (rad, equal-area strips, zero mean so the attached lift and
	# the linear oracle are unchanged): washout and the spanwise stall margin decide which strip stalls first.
	if node.has("wing_station_incidence"):
		var n: int = Aero.WING_STATIONS_PER_SIDE
		var inc = _q(errors, "aero.surfaces.wing_station_incidence", node.get("wing_station_incidence"), "rad", -0.2, 0.2, n)
		if inc != null:
			var mean := 0.0
			for x in inc:
				mean += x / n
			if absf(mean) > 1e-6:
				errors.append("aero.surfaces.wing_station_incidence: mean %.2e rad must be 0 (equal-area strips; CL0 carries the mean)" % mean)
			var per_station := PackedFloat64Array()
			for k in range(n - 1, -1, -1):
				per_station.append(inc[k]) # station_ys: left tip … left root, then right root … right tip
			for k in n:
				per_station.append(inc[k])
			out.station_incidence = per_station
	for name in ["horizontal", "vertical"]:
		var tail := _dictionary(errors, "aero.surfaces." + name, node.get(name, {}))
		var label: String = "aero.surfaces." + name
		out[name] = {
			area = _q(errors, label + ".area", tail.get("area"), "m2", 0.001, 1.0),
			position = _q(errors, label + ".position", tail.get("position"), "m", -2.0, 2.0, 3),
			lift_slope = _q(errors, label + ".lift_slope", tail.get("lift_slope"), "1/rad", 0.1, 6.3),
			control_effectiveness = _q(errors, label + ".control_effectiveness", tail.get("control_effectiveness"), "1", 0.01, 1.5),
			incidence = _q(errors, label + ".incidence", tail.get("incidence"), "rad", -0.2, 0.2),
		}
	# E0a2 (optional): the wing's downwash gradient at the horizontal tail. With it, lift_slope, control_effectiveness
	# and incidence keep their meaning (the effective, downwash-reduced static values the oracle was matched with) and
	# _induced_map derives the free tail law: downwash follows the wing's lift, pitch rate and elevator do not.
	var horizontal_raw := _dictionary(errors, "aero.surfaces.horizontal", node.get("horizontal", {}))
	if horizontal_raw.get("downwash_gradient") != null:
		var gradient = _q(errors, "aero.surfaces.horizontal.downwash_gradient", horizontal_raw.get("downwash_gradient"), "1", 0.0, 0.9)
		if gradient != null:
			out.horizontal.downwash_gradient = float(gradient)
	if not errors.is_empty():
		return {}
	if out.tail_stall_end <= out.tail_local_limit or out.tail_local_limit <= out.attached_limit 			or minf(env.a1, env.n1) <= out.attached_limit:
		errors.append("aero.surfaces: attached/local/stall limits must be strictly ordered")
	var fin: Dictionary = out.vertical
	var arm: float = fin.position[0] - arp[0]
	if arm <= 0.0:
		errors.append("aero.surfaces.vertical: tail must be aft of the aerodynamic reference")
	var cy: float = fin.lift_slope*fin.area/area*fin.control_effectiveness
	var expected := {CYdr = cy, Cndr = -cy*arm/span, Cldr = cy*(fin.position[2]-arp[2])/span,
		Cnb = fin.lift_slope*fin.area/area*arm/span}
	for key in expected:
		if absf(aero[key]-expected[key]) > 1e-8:
			errors.append("aero.coefficients.%s: inconsistent with vertical surface force/arm (expected %.8f)" % [key, expected[key]])
	return out
