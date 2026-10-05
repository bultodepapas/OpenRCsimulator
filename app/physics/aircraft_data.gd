# Loads, validates and derives the physics data of an aircraft (format "openrc-aircraft v1").
# 64-bit floats only (guarded). Errors block use; warnings are data-quality notes to show, not hide.
# Result: { ok: bool, errors: PackedStringArray, warnings: PackedStringArray, model: Dictionary }
# model: mass_kg, inertia (PackedFloat64Array [Jxx Jyy Jzz Jxy Jxz Jyz], body FRD, about the inventory's own
#        centre of mass: the honest estimate of the mass distribution; flight uses the plan CG, see warnings),
#        cg_le / cg_inventory_le (PackedFloat64Array [x_aft, y_right, z_up], m), reference {S, b, c, arp_le},
#        aero {name: float}, conventions {…}, id.
extends RefCounted

const FORMAT := "openrc-aircraft v1"
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

	var ref: Dictionary = raw.get("reference", {})
	var area = _q(errors, "reference.wing_area", ref.get("wing_area"), "m2", 0.05, 3.0)
	var span = _q(errors, "reference.wing_span", ref.get("wing_span"), "m", 0.3, 4.0)
	var chord = _q(errors, "reference.mean_chord", ref.get("mean_chord"), "m", 0.05, 1.0)
	var arp = _q(errors, "reference.aero_reference_point", ref.get("aero_reference_point"), "m", -2.0, 2.0, 3)
	if area != null and span != null and chord != null and absf(span * chord - area) / area > 0.01:
		errors.append("reference: span × mean_chord = %.4f m2 differs from wing_area %.4f m2 by more than 1 %%" % [span * chord, area])

	var bal: Dictionary = raw.get("balance", {})
	var plan_cg = _q(errors, "balance.plan_cg", bal.get("plan_cg"), "m", -2.0, 2.0, 3)
	_q(errors, "balance.firewall", bal.get("firewall"), "m", -2.0, 2.0, 3)
	var mismatch_limit = _q(errors, "balance.mismatch_warning_mac", bal.get("mismatch_warning_mac"), "1", 0.0, 1.0)

	var inventory: Array = raw.get("inventory", [])
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

	var plaus: Dictionary = raw.get("plausibility", {})
	var mass_range = _q(errors, "plausibility.mass_range", plaus.get("mass_range"), "kg", 0.01, 100.0, 2)
	var inertia_ref = _q(errors, "plausibility.inertia_reference", plaus.get("inertia_reference"), "kg·m2", 0.0, 100.0, 3)

	var aero := {}
	var coeffs: Dictionary = raw.get("aero", {}).get("coefficients", {})
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
	var mismatch: float = absf(cg_inv[0] - plan_cg[0]) / chord
	if mismatch > mismatch_limit:
		warnings.append("balance: inventory CG is %.3f m %s of the plan CG (%.0f %% of the mean chord). A real build would move the battery or add ballast; the simulation flies at the plan CG." % [absf(cg_inv[0] - plan_cg[0]), "ahead" if cg_inv[0] < plan_cg[0] else "behind", mismatch * 100.0])
	var scale: float = (mass / 1.959) * pow(span / 1.27, 2)
	var names := ["Jxx", "Jyy", "Jzz"]
	for k in 3:
		var ratio: float = j[k] / (inertia_ref[k] * scale)
		if ratio < 0.5 or ratio > 2.0:
			warnings.append("inertia: %s = %.4f kg·m2 is %.2f× the scaled UltraStick25e value" % [names[k], j[k], ratio])

	var model := {
		id = raw.get("id", ""),
		mass_kg = mass,
		inertia = j,
		cg_le = plan_cg,
		cg_inventory_le = cg_inv,
		reference = { S = area, b = span, c = chord, arp_le = arp },
		aero = aero,
		conventions = raw.get("aero", {}).get("conventions", {}),
	}
	return { ok = errors.is_empty(), errors = errors, warnings = warnings, model = model }


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
