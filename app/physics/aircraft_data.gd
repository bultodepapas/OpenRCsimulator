# Loads, validates and derives the physics data of an aircraft (format "openrc-aircraft v1").
# 64-bit floats only (guarded). Errors block use; warnings are data-quality notes to show, not hide.
# Result: { ok: bool, errors: PackedStringArray, warnings: PackedStringArray, model: Dictionary }
# model: mass_kg, inertia (PackedFloat64Array [Jxx Jyy Jzz Jxy Jxz Jyz], body FRD, about the inventory's own
#        centre of mass; configurations whose declared flight CG disagrees are rejected),
#        cg_le / cg_inventory_le (PackedFloat64Array [x_aft, y_right, z_up], m), reference {S, b, c, arp_le},
#        aero {name: float}, conventions {…}, controls {throw_deg, throw_rad: {aileron, elevator, rudder},
#        servo_rate (full throws per second)}, id.
extends RefCounted

const FORMAT := "openrc-aircraft v1"
const Aero := preload("res://physics/aero.gd")
## The full-envelope blend may not start below this |α|: the linear model is the test oracle up to here (D9a).
const ORACLE_ALPHA_DEG := 8.0
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
	var prop := _propulsion(errors, raw.get("propulsion"))
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
	var scale: float = (mass / 1.959) * pow(span / 1.27, 2)
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
## Returns { contacts: [{ name, position (body FRD about the CG), stiffness, damping, max_compression }],
## reach, heave_omega, static_sag } or {} when absent.
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
	var x_min := INF
	var x_max := -INF
	var y_min := INF
	var y_max := -INF
	for i in raw_contacts.size():
		var label := "landing_gear.contacts[%d]" % i
		var c := _dictionary(errors, label, raw_contacts[i])
		var position = _q(errors, label + ".position", c.get("position"), "m", -3.0, 3.0, 3)
		var k = _q(errors, label + ".stiffness", c.get("stiffness"), "N/m", 1.0, 1.0e6)
		var damping = _q(errors, label + ".damping", c.get("damping"), "N·s/m", 0.0, 1.0e4)
		var travel = _q(errors, label + ".max_compression", c.get("max_compression"), "m", 0.005, 0.5)
		if position == null or k == null or damping == null or travel == null:
			continue
		if typeof(c.get("name")) != TYPE_STRING or str(c.name).strip_edges().is_empty():
			errors.append("%s: missing name" % label)
			continue
		var n := float(raw_contacts.size())
		var zeta: float = damping / (2.0 * sqrt(k * mass / n))
		if zeta < 0.05 or zeta > 2.0:
			errors.append("%s.damping: ratio ζ = %.2f outside 0.05–2 (with m/%d per contact)" % [label, zeta, int(n)])
		x_min = minf(x_min, position[0])
		x_max = maxf(x_max, position[0])
		y_min = minf(y_min, position[1])
		y_max = maxf(y_max, position[1])
		var body := PackedFloat64Array([-(position[0] - cg[0]), position[1] - cg[1], -(position[2] - cg[2])])
		reach = maxf(reach, sqrt(body[0] * body[0] + body[1] * body[1] + body[2] * body[2]))
		total_k += k
		contacts.append({ name = str(c.name), position = body, stiffness = float(k), damping = float(damping), max_compression = float(travel) })
	if not errors.is_empty() or contacts.size() < 3:
		return {}
	if not (x_min < cg[0] and cg[0] < x_max):
		errors.append("landing_gear: the CG (x_aft %.3f m) is outside the wheelbase %.3f–%.3f m; the airplane cannot stand on its wheels" % [cg[0], x_min, x_max])
	if not (y_min < cg[1] and cg[1] < y_max):
		errors.append("landing_gear: no contact on each side of the CG (y %.3f–%.3f m)" % [y_min, y_max])
	var dt := 1.0 / float(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60))
	var omega := sqrt(total_k / mass)
	if omega * dt >= 0.1:
		errors.append("landing_gear: heave ω·dt = %.3f (ω %.1f rad/s at %.0f Hz) is not < 0.1; soften the gear or raise the tick" % [omega * dt, omega, 1.0 / dt])
	if not errors.is_empty():
		return {}
	return { contacts = contacts, reach = reach, heave_omega = omega, static_sag = mass * 9.80665 / total_k }


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
			var y1 := h if k == n - 1 else (-cr + sqrt(cr * cr + 2.0 * slope * target)) / slope
			centres.append((moment.call(y1) - moment.call(y0)) / (area.call(y1) - area.call(y0)))
			y0 = y1
	var ys := PackedFloat64Array()
	for k in range(n - 1, -1, -1):
		ys.append(-centres[k])
	ys.append_array(centres)
	return ys


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
	var cp := _table(errors, "propulsion.propeller.cp_table", pr.get("cp_table"), 0.0, 0.5)
	if max_rpm != null and idle != null and idle >= max_rpm:
		errors.append("propulsion.engine: idle_rpm %s must be below max_rpm_static %s" % [idle, max_rpm])
	if not ct.is_empty() and ct[1] <= 0.0:
		errors.append("propulsion.propeller.ct_table: static Ct must be positive (a propeller that pushes)")
	return { max_rpm = max_rpm, idle_rpm = idle, lag = lag, diameter = diameter, offset = offset, ct = ct, cp = cp, rotor_inertia = rotor }


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
