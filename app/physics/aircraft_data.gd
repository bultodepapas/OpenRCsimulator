# Loads/derives strict openrc-aircraft v2, with explicit historical v1 compatibility.
# 64-bit floats only (guarded). Errors block use; warnings are data-quality notes to show, not hide.
# Result: { ok: bool, errors: PackedStringArray, warnings: PackedStringArray, model: Dictionary }
# Successful file loads also carry input_identity: {format, sha256 of exact loaded bytes}.
# In-memory validation has no file identity. It is intentionally outside the derived model.
# model: mass_kg, inertia (PackedFloat64Array [Jxx Jyy Jzz Jxy Jxz Jyz], body FRD, about the inventory's own
#        centre of mass; configurations whose declared flight CG disagrees are rejected),
#        cg_le / cg_inventory_le (PackedFloat64Array [x_aft, y_right, z_up], m), reference {S, b, c, arp_le},
#        aero {name: float}, conventions {…}, controls {throw_deg, throw_rad: {aileron, elevator, rudder},
#        servo_rate (full throws per second)}, id.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

const FORMAT := "openrc-aircraft v2"
const LEGACY_FORMAT := "openrc-aircraft v1"
const Contract := preload("res://physics/aircraft_contract.gd")
const PhysicalIdentity := preload("res://physics/physical_identity.gd")
const Aero := preload("res://physics/aero.gd")
const WingPolar := preload("res://physics/wing_polar.gd")
const Ground := preload("res://physics/ground_contact.gd")
const WheelProfiles := preload("res://physics/wheel_profiles.gd")
const GlowInstallation := preload("res://physics/glow/installation.gd")
## The full-envelope blend may not start below this |α|: the linear model is the test oracle up to here (D9a).
const ORACLE_ALPHA_DEG := 8.0
## CR-01d: names a crash-hull point may carry (crash_hull_components). Same list as the contract's enum path;
## test_crash_hull_labels.gd keeps them equal. Left/right follow y_right in the le frame.
const HULL_COMPONENTS := ["left_wing_tip", "right_wing_tip", "spinner", "propeller", "nose", "tail_end",
	"left_stab_tip", "right_stab_tip", "fin_top", "canopy", "belly"]
## D1-R3 ground_support() tolerances (m, m²): contacts within 1 mm of a facet plane count as on it (data rounding, far
## below the 1–3 cm static sag); smaller triangle areas, near-vertical facets and shorter edges are degenerate.
const SUPPORT_PLANE_TOL := 0.001
const SUPPORT_AREA_MIN := 1e-6
const SUPPORT_UP_MIN := 1e-6
const SUPPORT_EDGE_MIN := 1e-9
const KINDS := ["manual", "measured", "borrowed", "estimated", "derived"]
const MAX_FINITE := 1.7976931348623157e308

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
	# Hash and parse one read: never fingerprint a later revision of the file.
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return _fail("cannot read %s (error %d)" % [path, FileAccess.get_open_error()])
	var text: String = bytes.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(text) != OK:
		return _fail("%s: JSON error at line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _fail("%s: top level must be an object" % path)
	var result: Dictionary = validate_and_derive(json.data)
	if result.ok:
		# Aircraft files remain the generated/source-owned physics record. Ground wheel spin parameters come from a
		# separate provenance-bearing profile, applied only at the file boundary (never to in-memory fixtures).
		var profiled: Dictionary = WheelProfiles.apply_to_model(result.model)
		if not profiled.ok:
			result.ok = false
			result.errors.append_array(profiled.errors)
			result.model = {}
			return result
		result.model = profiled.model
		result.wheel_profile_identity = profiled.identity
		var digest: HashingContext = HashingContext.new()
		digest.start(HashingContext.HASH_SHA256)
		digest.update(bytes)
		# Source identity is outside the derived model/checkpoint fingerprint.
		# In-memory validate_and_derive() calls cannot claim an input file identity.
		result.input_identity = {format = str(json.data.format), sha256 = digest.finish().hex_encode()}
	return result


static func _fail(message: String) -> Dictionary:
	return { ok = false, errors = PackedStringArray([message]), warnings = PackedStringArray(), model = {} }


static func _dictionary(errors: PackedStringArray, path: String, node: Variant) -> Dictionary:
	if typeof(node) != TYPE_DICTIONARY:
		errors.append("%s: expected an object" % path)
		return {}
	return node


## New data branches can be closed without changing the permissive legacy v1 objects.
static func _reject_unknown_keys(errors: PackedStringArray, path: String, node: Dictionary, allowed: Array) -> void:
	for key: String in node:
		if not allowed.has(key):
			errors.append("%s: unsupported field '%s'" % [path, key])


## Electric evidence uses a closed v1 quantity object without tightening legacy data.
static func _electric_q(errors: PackedStringArray, path: String, node: Variant, unit: String, lo: float, hi: float, size := 0) -> Variant:
	if typeof(node) == TYPE_DICTIONARY:
		_reject_unknown_keys(errors, path, node, ["value", "unit", "kind", "source"])
	return _q(errors, path, node, unit, lo, hi, size)


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
	if raw.get("format") == LEGACY_FORMAT:
		return _validate_legacy(raw)
	if raw.get("format") != FORMAT:
		return _fail("format must be '%s' or explicit legacy '%s'" % [FORMAT, LEGACY_FORMAT])
	var structural: PackedStringArray = Contract.validate(raw)
	if not structural.is_empty():
		return {ok = false, errors = structural, warnings = PackedStringArray(), model = {}}
	var result: Dictionary = _validate_legacy(legacy_v1_input(raw))
	if result.ok:
		# Identity describes authored v2, never the internal compatibility representation.
		result.model.data_sha256 = JSON.stringify(raw, "", true).sha256_text()
		result.model.capabilities = raw.capabilities.duplicate(true)
		result.model.convention_id = raw.convention_id
		if raw.has("flaps"):
			var flap_errors := PackedStringArray()
			var flap_model := _flaps(flap_errors, raw.get("flaps"), result.model.reference, result.model.envelope)
			if not flap_errors.is_empty():
				return {ok=false,errors=flap_errors,warnings=result.warnings,model={}}
			result.model.flaps = flap_model
		if raw.propulsion.get("engine", {}).has("glow_installation"):
			var installed: Dictionary = GlowInstallation.attach(raw, result.model)
			if not installed.ok:
				return {ok=false,errors=installed.errors,warnings=result.warnings,model={}}
			result.model = installed.model
			result.warnings.append("Experimental glow installation: inferred torque/propeller, transport and thermal data; physical/pilot validation pending")
		var identities := PhysicalIdentity.describe(raw)
		if not identities.is_empty():
			result.model.physical_identity = identities
			result.model.propulsion.id = identities.propulsion_id
			result.model.controls.surface_ids = identities.surface_ids.duplicate(true)
			for i in identities.support_ids.size():
				result.model.landing_gear.contacts[i].id = identities.support_ids[i]
	return result


## AV-09 hinged trailing-edge flap module. Raw inputs remain evidence-bearing quantities;
## the simulation receives normalized coefficients and a spanwise strip coverage map.
static func _flaps(errors: PackedStringArray, node: Variant, reference: Dictionary, envelope: Dictionary) -> Dictionary:
	var strip_ys: PackedFloat64Array = envelope.get("station_ys", PackedFloat64Array())
	if envelope.is_empty() or strip_ys.size() != Aero.WING_STATIONS_PER_SIDE * 2:
		errors.append("flaps: simulated flap law requires the validated local wing-strip envelope")
		return {}
	if typeof(node) == TYPE_DICTIONARY:
		_reject_unknown_keys(errors, "flaps", node, ["max_angle_deg", "takeoff_angle_deg", "inner_span_m", "outer_span_m",
			"hinge_fraction", "extension_time", "retraction_time", "max_speed_mps", "elevator_mix_per_flap_fraction",
			"effective_angle_limit_deg", "profile_drag_coefficient", "aerodynamic_gain",
			"stall_shift_fraction", "lift_reference_offset_m"])
	var data := _dictionary(errors, "flaps", node)
	var max_angle = _q(errors, "flaps.max_angle_deg", data.get("max_angle_deg"), "deg", 5.0, 60.0)
	var takeoff_angle = _q(errors, "flaps.takeoff_angle_deg", data.get("takeoff_angle_deg"), "deg", 0.0, 60.0)
	var inner = _q(errors, "flaps.inner_span_m", data.get("inner_span_m"), "m", 0.0, float(reference.b) / 2.0)
	var outer = _q(errors, "flaps.outer_span_m", data.get("outer_span_m"), "m", 0.0, float(reference.b) / 2.0)
	var hinge = _q(errors, "flaps.hinge_fraction", data.get("hinge_fraction"), "1", 0.5, 0.95)
	var extension = _q(errors, "flaps.extension_time", data.get("extension_time"), "s", 0.25, 30.0)
	var retraction = _q(errors, "flaps.retraction_time", data.get("retraction_time"), "s", 0.25, 30.0)
	var max_speed = _q(errors, "flaps.max_speed_mps", data.get("max_speed_mps"), "m/s", 5.0, 100.0)
	var elevator_mix = _q(errors, "flaps.elevator_mix_per_flap_fraction", data.get("elevator_mix_per_flap_fraction"), "1", 0.0, 0.5)
	var angle_limit = _q(errors, "flaps.effective_angle_limit_deg", data.get("effective_angle_limit_deg"), "deg", 5.0, 30.0)
	var profile_drag = _q(errors, "flaps.profile_drag_coefficient", data.get("profile_drag_coefficient"), "1", 0.0, 1.0)
	var aerodynamic_gain = _q(errors, "flaps.aerodynamic_gain", data.get("aerodynamic_gain"), "1", 0.0, 1.0)
	# P51-11a (optional): a flapped strip's stall onset moves by this fraction of its camber shift (absent = 1, the whole
	# shift); flap camber lift acts this far aft (m, body x) of the strip force point (absent = 0, at the ARP).
	var stall_shift = null
	if data.has("stall_shift_fraction"):
		stall_shift = _q(errors, "flaps.stall_shift_fraction", data.get("stall_shift_fraction"), "1", 0.0, 1.0)
		if stall_shift != null and not envelope.get("wing_polar", {}).is_empty():
			errors.append("flaps.stall_shift_fraction: applies to the strip stall blend only; a tabulated aero.wing_polar sets its own stall")
	var lift_offset = null
	if data.has("lift_reference_offset_m"):
		lift_offset = _q(errors, "flaps.lift_reference_offset_m", data.get("lift_reference_offset_m"), "m", -0.5, 0.5)
	if max_angle == null or takeoff_angle == null or inner == null or outer == null or hinge == null \
			or extension == null or retraction == null or max_speed == null or elevator_mix == null or angle_limit == null \
			or profile_drag == null or aerodynamic_gain == null:
		return {}
	if max_angle <= 0.0 or takeoff_angle > max_angle:
		errors.append("flaps: takeoff_angle_deg must be between zero and max_angle_deg")
	if inner >= outer:
		errors.append("flaps: inner_span_m must be less than outer_span_m")
	if errors.size() > 0 or (data.has("stall_shift_fraction") and stall_shift == null) or (data.has("lift_reference_offset_m") and lift_offset == null):
		return {}
	var cf: float = 1.0 - float(hinge)
	var theta := M.acos_(2.0 * cf - 1.0)
	var effectiveness := 1.0 - (theta - M.sin_(theta)) / PI
	# Glauert thin-airfoil plain-flap relation, applied below to the actual bounded ΔCL.
	var moment_per_lift := 0.25 * (M.sin_(2.0 * theta) - 2.0 * M.sin_(theta)) / (2.0 * PI * effectiveness)
	var edges := station_edges(float(reference.b), reference.chords)
	if edges.size() != strip_ys.size() + 1:
		errors.append("flaps: local wing-strip edge/centre topology is inconsistent")
		return {}
	var coverage := PackedFloat64Array()
	var root_chord: float = float(reference.S) / float(reference.b) if reference.chords.is_empty() else float(reference.chords[0])
	var tip_chord: float = root_chord if reference.chords.is_empty() else float(reference.chords[1])
	var half_span: float = float(reference.b) / 2.0
	var chord_slope: float = (tip_chord - root_chord) / half_span
	var chord_area := func(y: float) -> float:
		return root_chord * y + chord_slope * y * y / 2.0
	for i in range(edges.size() - 1):
		var lo: float = minf(absf(edges[i]), absf(edges[i + 1]))
		var hi: float = maxf(absf(edges[i]), absf(edges[i + 1]))
		var strip_area: float = float(chord_area.call(hi)) - float(chord_area.call(lo))
		var flap_lo: float = maxf(lo, float(inner))
		var flap_hi: float = minf(hi, float(outer))
		var flap_area: float = float(chord_area.call(flap_hi)) - float(chord_area.call(flap_lo)) if flap_hi > flap_lo else 0.0
		coverage.append(clampf(flap_area / strip_area, 0.0, 1.0) if strip_area > 0.0 else 0.0)
	var flap_out := {
		max_angle_deg = float(max_angle),
		takeoff_angle_deg = float(takeoff_angle),
		takeoff_fraction = float(takeoff_angle) / float(max_angle),
		inner_span_m = float(inner), outer_span_m = float(outer),
		hinge_fraction = float(hinge), chord_fraction = cf,
		lift_effectiveness = effectiveness,
		thin_airfoil_moment_per_cl = moment_per_lift,
		extension_time = float(extension), retraction_time = float(retraction),
		max_speed_mps = float(max_speed),
		elevator_mix_per_flap_fraction = float(elevator_mix),
		effective_angle_limit_deg = float(angle_limit),
		profile_drag_coefficient = float(profile_drag),
		aerodynamic_gain = float(aerodynamic_gain),
		station_coverage = coverage,
	}
	if stall_shift != null:
		flap_out.stall_shift_fraction = float(stall_shift)
	if lift_offset != null:
		flap_out.lift_reference_offset_m = float(lift_offset)
	return flap_out


## Explicit adapter for the shared numerical derivation and historical v1 research fixtures.
## It does not validate or authorize a v2 file; production must use validate_and_derive/load_file.
static func legacy_v1_input(raw: Dictionary) -> Dictionary:
	var out: Dictionary = raw.duplicate(true)
	out.format = LEGACY_FORMAT
	out.erase("capabilities")
	out.erase("convention_id")
	out.erase("flaps")
	# Identity metadata belongs to v2; the shared historical numerical parser
	# keeps its closed propulsion shape and receives only its original inputs.
	out.erase("physical_identity_version")
	out.erase("crash_hull_ids")
	if out.get("inventory") is Array:
		for item in out.inventory:
			if item is Dictionary:
				item.erase("id")
	if out.get("landing_gear") is Dictionary and out.landing_gear.get("contacts") is Array:
		for contact in out.landing_gear.contacts:
			if contact is Dictionary:
				contact.erase("id")
	if out.get("propulsion") is Dictionary:
		out.propulsion.erase("id")
	if out.get("controls") is Dictionary:
		out.controls.erase("surface_ids")
	if typeof(out.get("aero")) == TYPE_DICTIONARY:
		var reference: Variant = out.aero.get("reference_coefficients")
		if typeof(reference) == TYPE_DICTIONARY and reference.has("CLadot") and typeof(out.aero.get("coefficients")) == TYPE_DICTIONARY:
			out.aero.coefficients.CLadot = reference.CLadot
		out.aero.erase("reference_coefficients")
	return out


static func _validate_legacy(raw: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	if raw.get("format") != LEGACY_FORMAT:
		errors.append("format must be '%s', got '%s'" % [LEGACY_FORMAT, raw.get("format")])
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
		if not _induced_map(envelope, surfaces, aero, area, span, chords):
			errors.append("aero.surfaces: induced wing calibration cannot reproduce CLa with a finite positive section slope in [0.1, 50] 1/rad")
	if errors.is_empty() and aero_node.has("wing_polar"):
		var polar := _wing_polar(errors, aero_node.wing_polar, envelope, aero)
		if not polar.is_empty():
			envelope.wing_polar = polar
			warnings.append("Experimental tabulated wing polar: provenance and aircraft-specific post-stall validation must be reviewed")
	if errors.is_empty() and aero_node.has("ground_effect"):
		var ground_effect := _ground_effect(errors, aero_node.ground_effect, envelope, surfaces)
		if not ground_effect.is_empty():
			envelope.ground_effect = ground_effect
	var prop := _propulsion(errors, raw.get("propulsion"))
	var hull := _crash_hull(errors, raw.get("crash_hull"))
	var hull_components := _crash_hull_components(errors, raw.get("crash_hull_components"), hull.size() / 3)
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
	if prop.get("kind") == "electric_prop":
		_validate_electric_rotor_carrier(errors, prop, j)
	var scale: float = (mass / 1.959) * M.pow_(span / 1.27, 2)
	var names := ["Jxx", "Jyy", "Jzz"]
	for k in 3:
		var ratio: float = j[k] / (inertia_ref[k] * scale)
		if ratio < 0.5 or ratio > 2.0:
			warnings.append("inertia: %s = %.4f kg·m2 is %.2f× the scaled UltraStick25e value" % [names[k], j[k], ratio])

	var gear := _landing_gear(errors, raw.get("landing_gear"), cg_inv, mass)

	var model := {
		id = raw.get("id", ""),
		# Legacy rounded semantic hash; retained for checkpoint compatibility, NOT file bytes.
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
		crash_hull_components = hull_components,
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
	# E1b: each contact's damping ramps in over DAMPING_ONSET_FRACTION of its static compression (ground_contact.gd
	# damping()): the resting load share of m·g over its spring. A contact outside the resting facet uses an equal share.
	for i in contacts.size():
		var share := 1.0 / float(contacts.size())
		if rest.facet.size() == 3 and static_shares.size() == 3 and rest.facet.has(i):
			share = static_shares[rest.facet.find(i)]
		contacts[i].damping_onset = Ground.DAMPING_ONSET_FRACTION * share * mass * 9.80665 / float(contacts[i].stiffness)
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
	if gear.has("retraction"):
		_derive_retraction(errors, gear, derived, cg)
	return derived if errors.is_empty() else {}


## Explicit opt-in actuator and measured presentation contact paths. Positions
## are converted once from LE coordinates to CG-relative body FRD.
static func _derive_retraction(errors: PackedStringArray, raw: Dictionary, gear: Dictionary, cg: PackedFloat64Array) -> void:
	var spec := _dictionary(errors, "landing_gear.retraction", raw.retraction)
	var extend = _q(errors, "landing_gear.retraction.extension_time", spec.get("extension_time"), "s", 0.25, 30.0)
	var retract = _q(errors, "landing_gear.retraction.retraction_time", spec.get("retraction_time"), "s", 0.25, 30.0)
	var area = _q(errors, "landing_gear.retraction.drag_area", spec.get("drag_area"), "m²", 0.0, 1.0)
	var center = _q(errors, "landing_gear.retraction.drag_center", spec.get("drag_center"), "m", -3.0, 3.0, 3)
	if not errors.is_empty():
		return
	var samples := -1
	for i in raw.contacts.size():
		var label := "landing_gear.contacts[%d].retraction_path" % i
		var path_spec: Variant = raw.contacts[i].get("retraction_path")
		var values: Variant = path_spec.get("value") if path_spec is Dictionary else null
		if not values is Array or values.size() < 6 or values.size() > 1539 or values.size() % 3 != 0:
			errors.append(label + ": expected 2..513 uniformly spaced LE points in a flat XYZ array")
			continue
		var path = _q(errors, label, path_spec, "m", -3.0, 3.0, values.size())
		if path == null:
			continue
		if samples != -1 and samples != path.size():
			errors.append(label + ": all contacts must use the same sample count")
		samples = path.size()
		var body := PackedFloat64Array()
		for offset in range(0, path.size(), 3):
			var point := PackedFloat64Array([-(path[offset] - cg[0]), path[offset + 1] - cg[1], -(path[offset + 2] - cg[2])])
			body.append_array(point)
			gear.reach = maxf(gear.reach, M.norm(point))
		for axis in 3:
			if absf(body[body.size() - 3 + axis] - gear.contacts[i].position[axis]) > 1.0e-6:
				errors.append(label + ": last point must equal the declared down contact")
		gear.contacts[i].retraction_path = body
	gear.retraction = {extension_time = float(extend), retraction_time = float(retract), drag_area = float(area),
		drag_center = PackedFloat64Array([-(center[0] - cg[0]), center[1] - cg[1], -(center[2] - cg[2])])}


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
## Returns false if the target cannot be reproduced; publish derived fields only after a finite solve.
static func _induced_map(envelope: Dictionary, surfaces: Dictionary, aero: Dictionary, area: float, span: float,
		chords: PackedFloat64Array) -> bool:
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
	if not is_finite(target) or target <= 0.0:
		return false
	# wsum(a0) = area-weighted Σ E·1 rises with a0 slower than 1/a0 falls: a0·wsum(a0) is monotonic; bisection.
	var lo := 0.1
	var hi := 50.0
	var e_map := PackedFloat64Array()
	for iteration in 80:
		var a0 := 0.5 * (lo + hi)
		if a0 == lo or a0 == hi:
			break # Rounded midpoint cannot change; remaining inverse evaluations would repeat.
		e_map = effective_angle_map(k_map, a0, n)
		if a0 * _row_mean(e_map, n) < target:
			lo = a0
		else:
			hi = a0
	var a0 := 0.5 * (lo + hi)
	e_map = effective_angle_map(k_map, a0, n)
	var wsum := _row_mean(e_map, n)
	# D1-R5: stagnation is not convergence. Reject saturated endpoints and nonfinite solves before
	# deriving offsets/downwash. This is a numerical tolerance, not an aerodynamic uncertainty band.
	for value in e_map:
		if not is_finite(value):
			return false
	var solved: float = a0 * wsum
	if not is_finite(solved) or absf(solved - target) > 1e-10 * maxf(1.0, absf(target)):
		return false
	var twist: PackedFloat64Array = surfaces.get("station_incidence", PackedFloat64Array())
	var twist_lift := 0.0
	for i in n:
		for k in n:
			twist_lift += e_map[i * n + k] * (twist[k] if not twist.is_empty() else 0.0)
	twist_lift *= a0 / float(n)
	var alpha_s: float = (float(aero.CL0) - tail_share * float(horizontal.incidence) - twist_lift) / (a0 * wsum)
	if not is_finite(alpha_s):
		return false
	var cl0 := PackedFloat64Array()
	var row_sums := PackedFloat64Array()
	for i in n:
		var row := 0.0
		for k in n:
			row += e_map[i * n + k]
		var offset := a0 * alpha_s * row
		if not is_finite(offset):
			return false
		cl0.append(offset)
		row_sums.append(row)
	envelope.strip_slope = a0
	envelope.strip_cl0 = cl0
	envelope.induced_map = e_map
	# M5-GE-1: the strips' zero-lift shift and map row sums; strip i's induced angle at uniform α is
	# (α + strip_alpha_zero)·(1 − strip_row_sum[i]). Derived bookkeeping, not additional aircraft data.
	envelope.strip_alpha_zero = alpha_s
	envelope.strip_row_sum = row_sums
	envelope.station_chords = chord # D11j: the strips' local chords (station order) for the section pitching moment
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
	return true


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
	if kind == "electric_prop":
		return _electric_propulsion(errors, node)
	if kind == "turbine":
		return _turbine(errors, node)
	if kind != "glow_prop":
		errors.append("propulsion.kind: '%s' is not 'glow_prop', 'turbine', or 'electric_prop'" % kind)
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
		if out.slipstream.has("edge_fraction") and out.get("axis") != PackedFloat64Array([1.0, 0.0, 0.0]):
			errors.append("propulsion.propeller.slipstream: smooth profile currently requires an axial shaft")
	return out


## EL1b: a strict three-constant equivalent motor, prescribed bus and direct-drive propeller.
## The raw resistance is motor-winding equivalent only; ESC and wiring losses are outside this law.
## Positive RPM is direct-drive rotation about the propeller axis (+1 sense); gears and reverse sense are unsupported.
static func _electric_propulsion(errors: PackedStringArray, node: Dictionary) -> Dictionary:
	_reject_unknown_keys(errors, "propulsion", node, ["kind", "motor", "battery", "esc", "propeller"])
	var motor_raw := _dictionary(errors, "propulsion.motor", node.get("motor", {}))
	_reject_unknown_keys(errors, "propulsion.motor", motor_raw, [
		"kv_rpm_per_volt", "resistance_ohm", "resistance_scope", "no_load_current_a", "no_load_context",
	])
	var context_raw := _dictionary(errors, "propulsion.motor.no_load_context", motor_raw.get("no_load_context", {}))
	_reject_unknown_keys(errors, "propulsion.motor.no_load_context", context_raw, ["voltage_v", "rpm", "temperature_c"])
	var kv = _electric_q(errors, "propulsion.motor.kv_rpm_per_volt", motor_raw.get("kv_rpm_per_volt"), "rpm/V", 1.0, 10000.0)
	var resistance = _electric_q(errors, "propulsion.motor.resistance_ohm", motor_raw.get("resistance_ohm"), "ohm", 1e-5, 10.0)
	var idle_current = _electric_q(errors, "propulsion.motor.no_load_current_a", motor_raw.get("no_load_current_a"), "A", 0.0, 200.0)
	if motor_raw.get("resistance_scope") != "motor_winding_equivalent":
		errors.append("propulsion.motor.resistance_scope: must be 'motor_winding_equivalent' (ESC and wiring losses are excluded)")
	var context_voltage = _electric_q(errors, "propulsion.motor.no_load_context.voltage_v", context_raw.get("voltage_v"), "V", 0.1, 1000.0)
	var context_rpm = _electric_q(errors, "propulsion.motor.no_load_context.rpm", context_raw.get("rpm"), "rpm", 1.0, 1.0e7)
	_electric_q(errors, "propulsion.motor.no_load_context.temperature_c", context_raw.get("temperature_c"), "°C", -100.0, 300.0)
	var battery_raw := _dictionary(errors, "propulsion.battery", node.get("battery", {}))
	var battery_result: Dictionary = _electric_battery(errors, battery_raw)
	var battery: Dictionary = battery_result.get("battery", {})
	var reference_voltage: float = float(battery_result.get("reference_voltage", 0.0))
	var esc_raw := _dictionary(errors, "propulsion.esc", node.get("esc", {}))
	_reject_unknown_keys(errors, "propulsion.esc", esc_raw, ["kind", "command_mapping"])
	if esc_raw.get("kind") != "ideal_motoring":
		errors.append("propulsion.esc.kind: only 'ideal_motoring' is supported")
	if esc_raw.get("command_mapping") != "identity":
		errors.append("propulsion.esc.command_mapping: only 'identity' is supported")
	var prop_raw := _dictionary(errors, "propulsion.propeller", node.get("propeller", {}))
	_reject_unknown_keys(errors, "propulsion.propeller", prop_raw, [
		"name", "diameter", "thrust_line_offset", "rotating_inertia", "ct_table", "cp_table", "thrust_angles",
	])
	if prop_raw.has("name") and typeof(prop_raw.name) != TYPE_STRING:
		errors.append("propulsion.propeller.name: expected a string")
	var diameter = _electric_q(errors, "propulsion.propeller.diameter", prop_raw.get("diameter"), "m", 0.05, 2.0)
	var offset = _electric_q(errors, "propulsion.propeller.thrust_line_offset", prop_raw.get("thrust_line_offset"), "m", -1.0, 1.0, 3)
	var rotor = _electric_q(errors, "propulsion.propeller.rotating_inertia", prop_raw.get("rotating_inertia"), "kg·m2", 0.0, 0.1)
	var ct_node: Variant = prop_raw.get("ct_table")
	var cp_node: Variant = prop_raw.get("cp_table")
	var ct := _table(errors, "propulsion.propeller.ct_table", ct_node, -0.5, 0.5)
	var cp := _table(errors, "propulsion.propeller.cp_table", cp_node, -0.3, 0.5)
	if typeof(ct_node) == TYPE_DICTIONARY:
		_reject_unknown_keys(errors, "propulsion.propeller.ct_table", ct_node, ["value", "unit", "kind", "source"])
	if typeof(cp_node) == TYPE_DICTIONARY:
		_reject_unknown_keys(errors, "propulsion.propeller.cp_table", cp_node, ["value", "unit", "kind", "source"])
	var angles: Variant = null
	if prop_raw.has("thrust_angles"):
		angles = _electric_q(errors, "propulsion.propeller.thrust_angles", prop_raw.get("thrust_angles"), "deg", -10.0, 10.0, 2)
	if not errors.is_empty():
		return {}
	# Cross-field checks and derived values only run after every raw quantity is known finite and in range.
	if context_rpm > kv * context_voltage:
		errors.append("propulsion.motor.no_load_context.rpm: must not exceed Kv × test voltage")
	if rotor <= 0.0:
		errors.append("propulsion.propeller.rotating_inertia: electric rotor inertia must be positive")
	if ct[1] <= 0.0:
		errors.append("propulsion.propeller.ct_table: static Ct must be positive (a propeller that pushes)")
	if cp[1] <= 0.0:
		errors.append("propulsion.propeller.cp_table: static Cp must be positive (a propeller that absorbs power)")
	if not errors.is_empty():
		return {}
	var axis := PackedFloat64Array([1.0, 0.0, 0.0])
	if angles != null:
		var down := deg_to_rad(angles[0])
		var right := deg_to_rad(angles[1])
		axis = PackedFloat64Array([M.cos_(down) * M.cos_(right), M.cos_(down) * M.sin_(right), M.sin_(down)])
	var max_rpm: float = kv * reference_voltage
	if not is_finite(max_rpm) or max_rpm <= 0.0:
		if battery_raw.get("kind") == "fixed_voltage":
			errors.append("propulsion: derived Kv × fixed voltage reference RPM is nonfinite or nonpositive")
		else:
			errors.append("propulsion: derived Kv × maximum OCV reference RPM is nonfinite or nonpositive")
	if not errors.is_empty():
		return {}
	var out := {
		kind = "electric_prop",
		motor = {kv_rpm_per_volt = kv, resistance_ohm = resistance, no_load_current_a = idle_current},
		battery = battery,
		esc = {kind = "ideal_motoring", command_mapping = "identity"},
		max_rpm = max_rpm,
		diameter = diameter,
		offset = offset,
		rotor_inertia = rotor,
		ct = ct,
		cp = cp,
		axis = axis,
	}
	var cp_min: float = 0.0
	for i in range(1, cp.size(), 2):
		cp_min = minf(cp_min, cp[i])
	if cp_min < 0.0:
		out.cp_min = cp_min
	return out


## Parse one closed battery branch. Fixed-voltage normalization stays unchanged for EL1b callers.
static func _electric_battery(errors: PackedStringArray, battery_raw: Dictionary) -> Dictionary:
	var battery_kind: Variant = battery_raw.get("kind")
	if battery_kind == "fixed_voltage":
		_reject_unknown_keys(errors, "propulsion.battery", battery_raw, ["kind", "voltage_v"])
		var bus_voltage: Variant = _electric_q(errors, "propulsion.battery.voltage_v", battery_raw.get("voltage_v"), "V", 0.1, 1000.0)
		if not errors.is_empty():
			return {}
		# Preserve StringName keys: native model bytes identify existing v5 checkpoints.
		return {"battery": {kind = "fixed_voltage", voltage_v = bus_voltage}, "reference_voltage": float(bus_voltage)}
	if battery_kind != "ocv_resistance":
		errors.append("propulsion.battery.kind: must be 'fixed_voltage' or 'ocv_resistance'")
		return {}

	_reject_unknown_keys(errors, "propulsion.battery", battery_raw, [
		"kind", "capacity_ah", "resistance_ohm", "auxiliary_current_a", "initial_soc", "ocv_points",
	])
	var capacity_ah: Variant = _electric_q(errors, "propulsion.battery.capacity_ah", battery_raw.get("capacity_ah"), "Ah", 0.0, MAX_FINITE)
	var resistance_ohm: Variant = _electric_q(errors, "propulsion.battery.resistance_ohm", battery_raw.get("resistance_ohm"), "ohm", 0.0, MAX_FINITE)
	var auxiliary_current_a: Variant = _electric_q(errors, "propulsion.battery.auxiliary_current_a", battery_raw.get("auxiliary_current_a"), "A", 0.0, MAX_FINITE)
	var initial_soc: Variant = _electric_q(errors, "propulsion.battery.initial_soc", battery_raw.get("initial_soc"), "1", 0.0, 1.0)
	var raw_points: Array = _array(errors, "propulsion.battery.ocv_points", battery_raw.get("ocv_points"))
	var ocv_points: PackedFloat64Array = PackedFloat64Array()
	for index: int in raw_points.size():
		var point_path: String = "propulsion.battery.ocv_points[%d]" % index
		var point_raw: Dictionary = _dictionary(errors, point_path, raw_points[index])
		_reject_unknown_keys(errors, point_path, point_raw, ["soc", "voltage"])
		var knot_soc: Variant = _electric_q(errors, point_path + ".soc", point_raw.get("soc"), "1", 0.0, 1.0)
		var knot_voltage: Variant = _electric_q(errors, point_path + ".voltage", point_raw.get("voltage"), "V", 0.0, MAX_FINITE)
		if knot_soc == null or knot_voltage == null:
			continue
		if not ocv_points.is_empty():
			var previous_soc: float = ocv_points[ocv_points.size() - 2]
			var previous_voltage: float = ocv_points[ocv_points.size() - 1]
			if float(knot_soc) <= previous_soc:
				errors.append("%s.soc: knots must be strictly increasing" % point_path)
			if float(knot_voltage) < previous_voltage:
				errors.append("%s.voltage: OCV must be nondecreasing with SOC" % point_path)
		ocv_points.append(float(knot_soc))
		ocv_points.append(float(knot_voltage))
	if raw_points.size() < 2 or ocv_points.size() < 4:
		errors.append("propulsion.battery.ocv_points: needs at least two valid SOC/voltage pairs")
	if not ocv_points.is_empty() and ocv_points[0] != 0.0:
		errors.append("propulsion.battery.ocv_points: first SOC knot must be 0")
	if ocv_points.size() >= 2 and ocv_points[ocv_points.size() - 2] != 1.0:
		errors.append("propulsion.battery.ocv_points: last SOC knot must be 1")
	if not errors.is_empty():
		return {}
	if float(capacity_ah) <= 0.0:
		errors.append("propulsion.battery.capacity_ah: must be > 0")
	if float(initial_soc) <= 0.0:
		errors.append("propulsion.battery.initial_soc: must be in (0, 1]")
	var capacity_coulombs: float = 3600.0 * float(capacity_ah)
	if not is_finite(capacity_coulombs) or capacity_coulombs <= 0.0:
		errors.append("propulsion.battery.capacity_ah: 3600 × capacity must be finite and > 0 C")
	var initial_charge_coulombs: float = capacity_coulombs * float(initial_soc)
	if not is_finite(initial_charge_coulombs) or initial_charge_coulombs <= 0.0:
		errors.append("propulsion.battery.initial_soc: initial charge must be finite and > 0 C")
	var minimum_ocv: float = ocv_points[1]
	var maximum_ocv: float = ocv_points[ocv_points.size() - 1]
	if minimum_ocv <= 0.0:
		errors.append("propulsion.battery.ocv_points: voltages must be positive")
	for index: int in range(0, ocv_points.size() - 2, 2):
		var soc_width: float = ocv_points[index + 2] - ocv_points[index]
		var voltage_rise: float = ocv_points[index + 3] - ocv_points[index + 1]
		var ocv_slope: float = voltage_rise / soc_width if soc_width > 0.0 else INF
		if not is_finite(soc_width) or soc_width <= 0.0:
			errors.append("propulsion.battery.ocv_points: SOC segment widths must be finite and > 0")
		if not is_finite(ocv_slope) or ocv_slope < 0.0:
			errors.append("propulsion.battery.ocv_points: OCV segment slope must be finite and >= 0 V/SOC")
	var auxiliary_voltage_drop_v: float = float(resistance_ohm) * float(auxiliary_current_a)
	if not is_finite(auxiliary_voltage_drop_v):
		errors.append("propulsion.battery: resistance × auxiliary current is nonfinite")
	elif auxiliary_voltage_drop_v >= minimum_ocv:
		errors.append("propulsion.battery: auxiliary load leaves no positive feasible bus at minimum OCV")
	if not errors.is_empty():
		return {}
	return {
		"battery": {
			"kind": "ocv_resistance",
			"capacity_ah": float(capacity_ah),
			"resistance_ohm": float(resistance_ohm),
			"auxiliary_current_a": float(auxiliary_current_a),
			"initial_soc": float(initial_soc),
			"ocv_points": ocv_points,
		},
		"reference_voltage": maximum_ocv,
	}


## Removing the rotor's axial spin inertia must leave a positive definite locked carrier tensor.
static func _validate_electric_rotor_carrier(errors: PackedStringArray, prop: Dictionary, inertia: PackedFloat64Array) -> void:
	if not _inertia_is_positive_definite(inertia):
		errors.append("propulsion.propeller.rotating_inertia: aircraft inertia tensor must be positive definite")
		return
	var inverse := RB.inertia_inverse(inertia)
	var axis: PackedFloat64Array = prop.axis
	var projected_inverse := M.dot(axis, RB.inertia_mul(inverse, axis))
	var carrier_factor: float = 1.0 - float(prop.rotor_inertia) * projected_inverse
	if not is_finite(carrier_factor) or carrier_factor <= 0.0:
		errors.append("propulsion.propeller.rotating_inertia: subtracting the rotor leaves a nonpositive carrier inertia along its axis")


static func _inertia_is_positive_definite(inertia: PackedFloat64Array) -> bool:
	if inertia.size() != 6:
		return false
	for value: float in inertia:
		if not is_finite(value):
			return false
	var a: float = inertia[0]
	var b: float = inertia[1]
	var c: float = inertia[2]
	var d: float = inertia[3]
	var e: float = inertia[4]
	var f: float = inertia[5]
	var minor2: float = a * b - d * d
	var determinant: float = a * (b * c - f * f) + d * (e * f - d * c) + e * (d * f - b * e)
	return a > 0.0 and minor2 > 0.0 and is_finite(minor2) and determinant > 0.0 and is_finite(determinant)


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
## E0b3b opt-in: edge_fraction + reverse_fade replace each piece's chords with a provenanced profile table.
## Only axial shafts/transverse spans are supported; profile occupancy is distinct from a radial velocity law.
static func _slipstream(errors: PackedStringArray, node: Variant) -> Dictionary:
	var ss := _dictionary(errors, "propulsion.propeller.slipstream", node)
	var out := {
		hub = _q(errors, "propulsion.propeller.slipstream.hub", ss.get("hub"), "m", -2.0, 2.0, 3),
		wash_factor = _q(errors, "propulsion.propeller.slipstream.wash_factor", ss.get("wash_factor"), "1", 0.0, 2.0, 2),
		swirl_factor = _q(errors, "propulsion.propeller.slipstream.swirl_factor", ss.get("swirl_factor"), "1", 0.0, 1.0),
		vertical_drift = _q(errors, "propulsion.propeller.slipstream.vertical_drift", ss.get("vertical_drift"), "1", 0.0, 1.0),
		pieces = [],
	}
	# E0b3b: explicit opt-in; legacy pieces and arithmetic remain unchanged.
	var smooth: bool = ss.has("edge_fraction")
	if smooth:
		out.edge_fraction = _q(errors, "slipstream.edge_fraction", ss.get("edge_fraction"), "1", 0.01, 0.5)
		out.reverse_fade = _q(errors, "slipstream.reverse_fade", ss.get("reverse_fade"), "1", 0.01, 0.5, 2)
		if out.reverse_fade != null and out.reverse_fade[0] >= out.reverse_fade[1]:
			errors.append("slipstream.reverse_fade: positive onset must be below cutoff")
	elif ss.has("reverse_fade"):
		errors.append("slipstream.reverse_fade: requires edge_fraction")
	if ss.has("transport_speed_floor"):
		out.transport_speed_floor = _q(errors, "slipstream.transport_speed_floor", ss.get("transport_speed_floor"), "m/s", 0.1, 5.0)
		if not smooth or out.swirl_factor != 0.0:
			errors.append("slipstream.transport_speed_floor: axial transport requires smooth profiles and zero swirl (E0b5)")
	var raw := _array(errors, "propulsion.propeller.slipstream.pieces", ss.get("pieces"))
	if smooth and (raw.is_empty() or raw.size() > 8):
		errors.append("slipstream.pieces: smooth profile needs 1..8 pieces")
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
		}
		if piece.span_dir != null and absf(M.sqrt_(piece.span_dir[0] ** 2 + piece.span_dir[1] ** 2 + piece.span_dir[2] ** 2) - 1.0) > 1e-6:
			errors.append("%s.span_dir: must be a unit vector" % label)
		if smooth:
			piece.profile = _wash_profile(errors, label + ".profile", pc.get("profile"), piece.span, piece.area)
			if pc.has("chords"):
				errors.append(label + ": profile replaces chords; do not declare both")
			if piece.span_dir != null:
				var axis_ok: bool = piece.span_dir[0] == 0.0
				axis_ok = axis_ok and (piece.span_dir[2] == 0.0 if surface == "horizontal" else piece.span_dir[1] == 0.0)
				if not axis_ok:
					errors.append(label + ".span_dir: smooth profile requires transverse horizontal/vertical span")
			if piece.root != null and out.hub != null and piece.root[0] <= out.hub[0]:
				errors.append(label + ".root: must be behind hub")
		else:
			piece.chords = _q(errors, label + ".chords", pc.get("chords"), "m", 0.005, 1.0, 2)
			if pc.has("profile"):
				errors.append(label + ".profile: requires edge_fraction")
		out.pieces.append(piece)
	return out if errors.is_empty() else {}


## Piecewise-linear neutral chord widths, including discontinuities/gaps: [a,b,c(a),c(b)], all metres.
static func _wash_profile(errors: PackedStringArray, path: String, node: Variant, span: Variant, area: Variant) -> PackedFloat64Array:
	var quantity: Dictionary = _dictionary(errors, path, node)
	var rows: Array = _array(errors, path + ".value", quantity.get("value"))
	var flat: PackedFloat64Array = PackedFloat64Array()
	if rows.is_empty() or rows.size() > 64:
		errors.append(path + ": needs 1..64 intervals")
		return flat
	var previous: float = 0.0
	var total: float = 0.0
	for i in rows.size():
		var row_quantity: Dictionary = quantity.duplicate()
		row_quantity.value = rows[i]
		var row: Variant = _q(errors, path + "[%d]" % i, row_quantity, "m", 0.0, 3.0, 4)
		if row == null:
			continue
		if row[0] < previous or row[1] <= row[0] or (span != null and row[1] > span + 1e-10):
			errors.append(path + ": intervals must be ordered, disjoint and within span")
		if row[2] + row[3] <= 0.0:
			errors.append(path + ": each interval needs positive chord area")
		total += 0.5 * (row[2] + row[3]) * (row[1] - row[0])
		previous = row[1]
		flat.append_array(row)
	if area != null and absf(total - area) > 1e-8:
		errors.append(path + ": integrated area disagrees with piece area")
	return flat


## Turbojet (AV-05, physics/turbine.gd). engine: idle_rpm < max_rpm; tables as {value: [[x, y], …], unit "<x>, <y>",
## kind, source} with x strictly increasing: static_thrust ("rpm, N", bench at STP, ≥ 0), mass_flow ("rpm, kg/s",
## > 0), fuel_flow ("rpm, kg/s", ≥ 0), throttle_map ("1, rpm": throttle 0 → idle_rpm, 1 → max_rpm, rpm increasing),
## accel_limit / decel_limit ("rpm, rpm/s", > 0); installed_factor (0.5–1), governor_tau (s), rotor_inertia (kg·m2),
## rotor_sense (+1 clockwise from behind, −1 counter-clockwise). thrust_line_offset and intake_offset (centroid of the
## intakes), [x_aft, y_right, z_up] from the CG; optional thrust_angles ([down, right] deg) as for a propeller. Returns the model dict Turbine reads, with max_rpm/idle_rpm for telemetry.
static func _turbine(errors: PackedStringArray, node: Dictionary) -> Dictionary:
	var e := _dictionary(errors, "propulsion.engine", node.get("engine", {}))
	var p := "propulsion.engine."
	if e.has("spool_integrator") and (typeof(e.spool_integrator) != TYPE_STRING or e.spool_integrator not in ["sampled", "rk4"]):
		errors.append(p + "spool_integrator: must be sampled or rk4")
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
	if e.has("spool_integrator"):
		out.spool_integrator = e.spool_integrator
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
	var out := { throw_deg = deg, throw_rad = rad, servo_rate = 1.0 / t if t != null else 0.0 }
	# Optional (D6e): the manual's normal-flight dual rates and expo as stick shaping (travel fraction of the maximum
	# throw per axis, expo per axis). Absent = the maximum throws with no expo. Never an aerodynamic quantity.
	if node.has("rates"):
		var rates := _dictionary(errors, "controls.rates", node.get("rates"))
		var normal := _dictionary(errors, "controls.rates.normal", rates.get("normal"))
		var profile := {}
		for axis in ["aileron", "elevator", "rudder"]:
			var travel = _q(errors, "controls.rates.normal." + axis, normal.get(axis), "1", 0.05, 1.0)
			var expo = _q(errors, "controls.rates.normal." + axis + "_expo", normal.get(axis + "_expo"), "1", 0.0, 0.9)
			if travel != null:
				profile[axis] = float(travel)
			if expo != null:
				profile[axis + "_expo"] = float(expo)
		if profile.size() == 6:
			out.rates = { normal = profile }
	# Optional device response, never a servo or aerodynamic coefficient. Full/radio modes bypass it.
	if node.has("keyboard"):
		var keyboard := _dictionary(errors, "controls.keyboard", node.get("keyboard"))
		var response := {}
		for key in ["pitch_press_time", "pitch_release_time"]:
			var seconds = _q(errors, "controls.keyboard." + key, keyboard.get(key), "s", 0.05, 5.0)
			if seconds != null:
				response[key] = float(seconds)
		if not node.has("rates"):
			errors.append("controls.keyboard: requires controls.rates.normal")
		if response.size() == 2:
			out.keyboard = response
	if node.has("gamepad"):
		var gamepad := _dictionary(errors, "controls.gamepad", node.get("gamepad"))
		var scale = _q(errors, "controls.gamepad.pitch_scale", gamepad.get("pitch_scale"), "1", 0.05, 1.0)
		if not node.has("rates"):
			errors.append("controls.gamepad: requires controls.rates.normal")
		if scale != null:
			out.gamepad = {pitch_scale = float(scale)}
		if gamepad.has("yaw_scale"):
			var yaw_scale = _q(errors, "controls.gamepad.yaw_scale", gamepad.get("yaw_scale"), "1", 0.05, 1.0)
			if yaw_scale != null and out.has("gamepad"):
				out.gamepad.yaw_scale = float(yaw_scale)
		if gamepad.has("yaw_response_time"):
			var yaw_time = _q(errors, "controls.gamepad.yaw_response_time", gamepad.get("yaw_response_time"), "s", 0.02, 0.5)
			if yaw_time != null and out.has("gamepad"):
				out.gamepad.yaw_response_time = float(yaw_time)
	return out


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
	if not errors.is_empty():
		return {}
	# A convex blend cannot exceed both its linear and flat-plate branches.
	# Check reachability before division by CLa (a finite tiny slope can overflow the bracket).
	for side: float in [1.0, -1.0]:
		var target: float = cl_max if side > 0.0 else -cl_min
		var upper: float = maxf(side * float(aero.CL0) + float(aero.CLa) * PI / 2.0, cd90 / 2.0)
		if target > upper:
			errors.append("aero.envelope: %s stall limit is unreachable before 90 degrees" % ("positive" if side > 0.0 else "negative"))
		else:
			var bracket: float = (target - side * float(aero.CL0)) / float(aero.CLa)
			if not is_finite(bracket) or bracket <= 0.0:
				errors.append("aero.envelope: stall search bracket must be finite and positive")
	if not errors.is_empty():
		return {}
	var w := deg_to_rad(width)
	var a1 := _solve_stall_start(aero, cd90, w, cl_max, 1.0)
	var n1 := _solve_stall_start(aero, cd90, w, cl_min, -1.0)
	var oracle := deg_to_rad(ORACLE_ALPHA_DEG)
	if a1 < oracle or n1 < oracle:
		errors.append("aero.envelope: the stall blend would start at %+.1f° / %+.1f°, inside the ±%.0f° linear-oracle region (raise CL_max / CL_min or narrow the blend)" % [rad_to_deg(a1), -rad_to_deg(n1), ORACLE_ALPHA_DEG])
	# CD90 describes the separated flat plate: both transitions must finish by +/-90 degrees.
	# D1-R4: a finite input alone does not guarantee an ordered or realizable solved envelope.
	for side: float in [1.0, -1.0]:
		var start: float = a1 if side > 0.0 else n1
		var end: float = start + w
		var target: float = cl_max if side > 0.0 else cl_min
		var label: String = "positive" if side > 0.0 else "negative"
		if not is_finite(start) or not is_finite(end) or end <= start or end > PI / 2.0:
			errors.append("aero.envelope: %s stall transition must be finite, ordered and finish by 90 degrees" % label)
		else:
			var peak: float = _blend_extreme(aero, cd90, w, start, side)
			if not is_finite(peak) or absf(peak - target) > 1e-9:
				errors.append("aero.envelope: %s sampled stall peak does not reach the requested lift limit" % label)
	if not errors.is_empty():
		return {}
	return { a1 = a1, a2 = a1 + w, n1 = n1, n2 = n1 + w, b1 = deg_to_rad(sb[0]), b2 = deg_to_rad(sb[1]), CD90 = cd90, CL_max = cl_max, CL_min = cl_min }


## M5-GE-1 (optional): aero.ground_effect, the wing's image-vortex correction near the ground (physics/ground_effect.gd):
## σ = c·(h/b)^e / (1 + c·(h/b)^e) frees (1 − σ) of each strip's induced angle and scales its induced drag; a second
## law of the same form scales the wing's downwash at the horizontal tail. The four constants are fitted law
## coefficients with their own provenance, not force gains. Requires the coupled strip map (an induced angle to free)
## and the E0a2 free tail law (a downwash to reduce); absence of the module adds nothing anywhere.
static func _ground_effect(errors: PackedStringArray, node: Variant, envelope: Dictionary, surfaces: Dictionary) -> Dictionary:
	var path := "aero.ground_effect"
	var raw := _dictionary(errors, path, node)
	var specs := {
		induced_coefficient = [1.0, 1000.0],
		induced_exponent = [0.5, 4.0],
		downwash_coefficient = [1.0, 1000.0],
		downwash_exponent = [0.5, 4.0],
	}
	var out := {}
	for key in specs:
		var bounds: Array = specs[key]
		var value = _q(errors, path + "." + key, raw.get(key), "1", bounds[0], bounds[1])
		if value != null:
			out[key] = float(value)
	for key in raw:
		if not specs.has(key):
			errors.append("%s.%s: unknown field" % [path, key])
	if not envelope.has("induced_map"):
		errors.append("%s: requires the calibrated local wing (aero.envelope and the strip induced map)" % path)
	if not surfaces.get("horizontal", {}).has("free_slope"):
		errors.append("%s: requires aero.surfaces.horizontal.downwash_gradient (the free tail law whose downwash it reduces)" % path)
	if out.size() != specs.size() or not errors.is_empty():
		return {}
	return out


## D8b-R2d: a closed, optional branch; legacy aircraft and their exact arithmetic remain unchanged.
static func _wing_polar(errors: PackedStringArray, node: Variant, envelope: Dictionary, aero: Dictionary) -> Dictionary:
	var path := "aero.wing_polar"
	var raw := _dictionary(errors, path, node)
	_reject_unknown_keys(errors, path, raw, ["method", "basis", "positive", "negative"])
	if raw.get("method") != WingPolar.METHOD or raw.get("basis") != "finite-wing-strip-reference":
		errors.append(path + ": expected tabulated-wing-v1 and finite-wing-strip-reference basis")
	if not envelope.has("induced_map"):
		errors.append(path + ": requires a calibrated local wing map")
	if not errors.is_empty():
		return {}
	var slope: float = float(envelope.strip_slope)*_row_mean(envelope.induced_map, envelope.station_ys.size())
	var offset := 0.0
	for value: float in envelope.strip_cl0:
		offset += value / float(envelope.strip_cl0.size())
	var polar := {slope = slope, offset = offset, cd0 = aero.CD0, cd90 = envelope.CD90}
	for name in ["positive", "negative"]:
		var quantity: Variant = raw.get(name)
		if typeof(quantity) != TYPE_DICTIONARY or typeof(quantity.get("value")) != TYPE_ARRAY:
			errors.append(path + "." + name + ": expected a quantity with flat four-column samples")
			continue
		var count: int = quantity.value.size()
		if count < 16 or count > 256 or count % 4 != 0:
			errors.append(path + "." + name + ": expected 4..64 four-column rows")
			continue
		var samples: Variant = _electric_q(errors, path + "." + name, quantity, "deg, 1, 1, 1", 0.0, 90.0, count)
		if not errors.is_empty() or samples == null:
			continue
		polar[name] = WingPolar.prepare(samples, 1.0 if name == "positive" else -1.0,
			slope, offset, aero.CD0, envelope.CD90, errors, path + "." + name)
	return polar if errors.is_empty() else {}


## Stall start (rad, magnitude) on one side (sign +1 / −1) such that the blended lift's extreme equals `target`.
## Bisection: a later start keeps the linear rise longer, so the peak grows monotonically with the start.
static func _solve_stall_start(aero: Dictionary, cd90: float, width: float, target: float, sign: float) -> float:
	var lo := 0.0
	var hi := (target - float(aero.CL0)) / float(aero.CLa) * sign # where the linear lift alone reaches the target
	for i in 60:
		var mid := 0.5 * (lo + hi)
		if mid == lo or mid == hi:
			break # The rounded midpoint cannot change in any remaining iteration.
		if _blend_extreme(aero, cd90, width, mid, sign) * sign < target * sign:
			lo = mid
		else:
			hi = mid
	return 0.5 * (lo + hi)


## DATA-2a: same 801-point peak, pruned by a curvature/chord upper bound.
## Proof, rounding margin and fallback: docs/research/aircraft-validation/DATA-2a/README.md.
static func _blend_extreme(aero: Dictionary, cd90: float, width: float, start: float, sign: float) -> float:
	var env: Dictionary = { a1 = start, a2 = start + width, n1 = start, n2 = start + width, b1 = 1.0, b2 = 2.0, CD90 = cd90 }
	var best: float = 0.0
	var end: float = start + width * 1.25
	if start < 0.0 or end > PI / 2.0 or width <= 0.0 or float(aero.CLa) <= 0.0 or cd90 <= 0.0:
		for k in 801:
			var alpha: float = sign * (start + width * (float(k) / 800.0) * 1.25)
			var cl: float = Aero.lift_alpha(alpha, aero, env)
			if cl * sign > best * sign:
				best = cl
		return best
	# Coarse samples seed a lower bound; the interval proof still covers all 801 indices.
	for k in [160, 320, 480, 640]:
		var sample: float = Aero.lift_alpha(sign * (start + width * (float(k) / 800.0) * 1.25), aero, env)
		if sample * sign > best * sign:
			best = sample
	var cl0: float = aero.CL0
	var cla: float = aero.CLa
	var blend_range: float = (start + width) - start
	# |f''| <= |P''| + 2|w'||P'-B'| + |w''||P-B|.
	var base_lo: float = sign * cl0 + cla * start
	var base_hi: float = sign * cl0 + cla * end
	var plate_left: float = 0.5 * cd90 * M.sin_(2.0 * start)
	var plate_right: float = 0.5 * cd90 * M.sin_(2.0 * end)
	var plate_lo: float = minf(plate_left, plate_right)
	var plate_hi: float = maxf(plate_left, plate_right)
	if start <= PI / 4.0 and end >= PI / 4.0:
		plate_hi = 0.5 * cd90
	var value_gap: float = maxf(absf(plate_lo - base_hi), absf(plate_hi - base_lo))
	var slope_gap: float = maxf(absf(cd90 * M.cos_(2.0 * start) - cla), absf(cd90 * M.cos_(2.0 * end) - cla))
	var curvature: float = 2.0 * cd90 + 3.0 * slope_gap / blend_range + 6.0 * value_gap / (blend_range * blend_range)
	var fl: float = Aero.lift_alpha(sign * start, aero, env)
	var fr: float = Aero.lift_alpha(sign * end, aero, env)
	if fl * sign > best * sign:
		best = fl
	if fr * sign > best * sign:
		best = fr
	# Depth-first bisection of 801 indices needs at most 11 pending intervals.
	var indices: PackedInt32Array = PackedInt32Array()
	var values: PackedFloat64Array = PackedFloat64Array()
	indices.resize(24)
	values.resize(24)
	indices[0] = 0
	indices[1] = 800
	values[0] = fl
	values[1] = fr
	var cursor: int = 2
	while cursor > 0:
		cursor -= 2
		var lo: int = indices[cursor]
		var hi: int = indices[cursor + 1]
		var flo: float = values[cursor]
		var fhi: float = values[cursor + 1]
		var xlo: float = start + width * (float(lo) / 800.0) * 1.25
		var xhi: float = start + width * (float(hi) / 800.0) * 1.25
		var span: float = xhi - xlo
		# A C1 function with |f''| <= curvature lies below its chord + M*span²/8.
		var bound: float = maxf(flo * sign, fhi * sign) + curvature * span * span / 8.0
		if hi - lo <= 1 or bound + 1e-12 * maxf(1.0, absf(bound)) < best * sign:
			continue
		@warning_ignore("integer_division")
		var mid: int = (lo + hi) / 2
		var fm: float = Aero.lift_alpha(sign * (start + width * (float(mid) / 800.0) * 1.25), aero, env)
		if fm * sign > best * sign:
			best = fm
		indices[cursor] = mid
		indices[cursor + 1] = hi
		values[cursor] = fm
		values[cursor + 1] = fhi
		indices[cursor + 2] = lo
		indices[cursor + 3] = mid
		values[cursor + 2] = flo
		values[cursor + 3] = fm
		cursor += 4
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


## CR-01d: optional semantic name per crash-hull point, in hull order. Empty when absent (crash presentation then
## falls back to a marked geometric estimate). Presentation-only: no force or detector reads it.
static func _crash_hull_components(errors: PackedStringArray, node: Variant, point_count: int) -> PackedStringArray:
	var out := PackedStringArray()
	if node == null:
		return out
	if typeof(node) != TYPE_ARRAY:
		errors.append("crash_hull_components: must be an array of names")
		return out
	if (node as Array).size() != point_count:
		errors.append("crash_hull_components: %d names for %d crash_hull points" % [(node as Array).size(), point_count])
		return PackedStringArray()
	for name in node:
		if typeof(name) != TYPE_STRING or not HULL_COMPONENTS.has(name):
			errors.append("crash_hull_components: '%s' is not one of %s" % [str(name), str(HULL_COMPONENTS)])
			return PackedStringArray()
		out.append(name)
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
				errors.append("aero.surfaces.wing_station_incidence: mean %s rad must be 0 (equal-area strips; CL0 carries the mean)" % mean)
			var per_station := PackedFloat64Array()
			for k in range(n - 1, -1, -1):
				per_station.append(inc[k]) # station_ys: left tip … left root, then right root … right tip
			for k in n:
				per_station.append(inc[k])
			out.station_incidence = per_station
	# Optional (D11j): the wing section's pitching moment about its aerodynamic centre, a pure couple on every strip of
	# the local wing (Aero._local_loads). The oracle's Cm0 carries the same camber moment, so with it the two regimes
	# agree statically; absent = 0 = no couple (symmetric sections, or a Cm0 folded into the tail incidence).
	if node.has("wing_section_cm_ac"):
		var cm_ac = _q(errors, "aero.surfaces.wing_section_cm_ac", node.get("wing_section_cm_ac"), "1", -0.3, 0.1)
		if cm_ac != null:
			out.wing_cm_ac = float(cm_ac)
	# Optional (P51-25): the fuselage's destabilizing yaw derivative about the ARP, a Munk-type pure couple in the local
	# model (Aero._local_loads). The oracle's Cnb then carries fin + body; absent = 0 = no couple, byte-identical.
	if node.has("body_cn_beta"):
		var body_cn = _q(errors, "aero.surfaces.body_cn_beta", node.get("body_cn_beta"), "1/rad", -0.5, 0.0)
		if body_cn != null:
			out.body_cn_beta = float(body_cn)
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
		Cnb = fin.lift_slope*fin.area/area*arm/span + float(out.get("body_cn_beta", 0.0))}
	for key in expected:
		if absf(aero[key]-expected[key]) > 1e-8:
			errors.append("aero.coefficients.%s: inconsistent with vertical surface force/arm and body_cn_beta (expected %.8f)" % [key, expected[key]])
	return out
