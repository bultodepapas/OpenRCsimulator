# DR-10/11/12/13: strict `openrc-multirotor v1` reader, validator and preparer (FPV engineering contracts §5).
# A document carries quantities {value, unit, kind, source}; `kind` names the provenance class (manufacturer-reported,
# derived, estimated or borrowed) and `source` begins with that class. Every block is closed: unknown keys,
# missing blocks, wrong units/types and non-finite numbers are refused with a field-path error; nothing is clamped
# and nothing defaults silently. The reader recomputes mass, CG and the locked inertia from the mass inventory,
# the rotor clearances, the static hover balance and the k_T fit link, and refuses a document whose generator
# diagnostics disagree beyond DIAGNOSTIC_TOLERANCE (relative).
#
# Frames: body FRD (x forward, y right, z down). Rotor hubs, feet, hull points and the camera mount are given
# from the CG; mass-inventory positions are given from the document's frame datum. Rotor order and spin follow
# multirotor/plant.gd: 1 rear-right, 2 front-right, 3 rear-left, 4 front-left; spin +1 = counter-clockwise viewed
# from above; the only admitted thrust axis is (0, 0, -1). Inertia is stored as the symmetric tensor's matrix
# entries [Jxx, Jyy, Jzz, Jxy, Jxz, Jyz] (rigid_body.gd). 64-bit floats only.
#
# Hover balance: the static quadratic law's wrench rows [1, -y_i, x_i, s_i*kappa] (FPV/03 §2) are solved for the
# four rotor thrusts holding the weight with zero moment; `hover_thrust_per_rotor_n` is the most loaded rotor's
# thrust and `hover_speed_rad_s` its speed. Static motor balance for el-one-quadrant-bus-v1 at command d and supply
# V: Kt*((d*V - w/Kv)/R - I0) = k_Q*w^2, Kt = 1/Kv, evaluated at the open-circuit voltage (no pack sag). Audit A08:
# the electrical hover must also close on the LOADED shared pack at the low-charge point (hover_bus_solution:
# V^2 - B*V + Rp*P = 0, high-voltage root). Audit A09: physical_invariant_errors is the one list of physical bounds a
# prepared model must meet, whether it came from this loader or was built in memory.
# Admission screens a model's internal consistency only; it does not validate the aircraft physically.
extends RefCounted

const FORMAT := "openrc-multirotor v1"
const STATUS := "experimental-estimates"
const KINDS := ["manufacturer-reported", "derived", "estimated", "borrowed"]
const CAPABILITIES := ["multirotor", "acro", "angle", "ground_start", "battery", "replay"]
const ROTOR_LAW := "quadratic-static-v1"
const LAW_ELECTRIC := "el-one-quadrant-bus-v1"
const LAW_LAB := "first-order-lab-v1"
const CONTROLLER_LAW := "openrc-fc-acro-angle-v1"
const START_MODE := "ground_rest"
const SAMPLE_HZ := 240
const GRAVITY := 9.80665
const DIAGNOSTIC_TOLERANCE := 1.0e-9
const UNIT_AXIS_TOLERANCE := 1.0e-9
## Hover must also be reachable at the lowest listed OCV point strictly above this state of charge.
const LOW_CHARGE_SOC := 0.1
## Shaft speed (rad/s) below which the electrical friction torque is viscous (controlled_plant.gd FRICTION_SPEED).
const FRICTION_SPEED := 30.0
## Loaded-bus screen: the smallest discriminant (relative to B^2) that counts as an operating point (a near-double root
## is the maximum-power fold, not a usable hover) and the bus residual tolerance (relative to the open-circuit voltage).
const BUS_DISCRIMINANT_MIN := 1.0e-6
const BUS_RESIDUAL_TOLERANCE := 1.0e-9
const CELL_VOLTS_MIN := 2.5
const CELL_VOLTS_MAX := 4.35
const MAX_COMPONENTS := 64
const MAX_POINTS := 32
## Normalized wrench-matrix determinant below this has no independent yaw (or roll/pitch) authority.
const MIN_AUTHORITY_DETERMINANT := 1.0e-3
## Minimum horizontal triangle area (m²) of three feet to count as non-collinear support.
const MIN_SUPPORT_AREA := 1.0e-6

const TOP_KEYS := ["format", "identity", "capabilities", "provenance", "mass_inventory", "rotors", "rotor_law",
	"airframe", "powertrain", "battery", "controller", "contacts", "camera", "start"]
const SHAPE_TYPES := ["point", "box", "axisymmetric_z"]
## Generator diagnostics: key -> -1 string, 0 number, n array of n numbers.
const DIAGNOSTICS := {
	"fit_method": -1, "fit_kt_n_s2": 0, "fit_kq_n_m_s2": 0, "fit_kq_display_uncertainty_n_m_s2": 0,
	"fit_omega_rad_s": 2, "fit_thrust_reported_n": 2, "fit_thrust_residual_n": 2, "fit_torque_residual_n_m": 2,
	"fit_leave_one_out_thrust_residual_n": 2, "fit_kv_rad_s_per_v": 0, "fit_resistance_ohm": 0,
	"fit_row100_static_speed_model_rad_s": 0, "fit_row100_static_thrust_model_n": 0, "fit_row50_implied_duty": 0,
	"mass_kg": 0, "cg_from_datum_m": 3, "inertia_kg_m2": 6, "effective_yaw_inertia_kg_m2": 0,
	"min_prop_clearance_m": 0, "zero_gap_square_x_diagonal_m": 0,
	"hover_thrusts_n": 4, "hover_thrust_per_rotor_n": 0, "hover_speed_rad_s": 0, "hover_command_full_charge": 0,
	"idle_thrust_full_charge_n": 0, "static_max_speed_rad_s": 0, "static_max_thrust_per_rotor_n": 0,
	"static_max_thrust_low_charge_n": 0, "thrust_to_weight": 0,
	"rest_height_m": 0, "stiffness_per_foot_n_per_m": 0, "damping_per_foot_n_s_per_m": 0,
}


## Read, hash (file bytes) and admit one document. {ok, errors, data (the validated raw document), sha256}.
static func load_file(path: String) -> Dictionary:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return {ok = false, errors = PackedStringArray(["%s: cannot read (error %d)" % [path, FileAccess.get_open_error()]]),
			data = {}, sha256 = ""}
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	var sha: String = ctx.finish().hex_encode()
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK:
		return {ok = false, errors = PackedStringArray(["%s: JSON error at line %d: %s" % [path, json.get_error_line(),
			json.get_error_message()]]), data = {}, sha256 = sha}
	var result := _admit(json.data, path)
	result.sha256 = sha
	return result


## Admit an in-memory document; its identity hashes the canonical (sorted-key, full-precision) JSON. A refused
## document has no identity (sha256 = ""): non-finite values have no canonical JSON form.
static func load_document(raw: Variant, label := "document") -> Dictionary:
	var result := _admit(raw, label)
	result.sha256 = JSON.stringify(raw, "", true, true).sha256_text() if result.ok else ""
	return result


## Build the immutable-by-convention prepared model from an admitted document. Never mutates `data`.
static func prepare(data: Dictionary, sha256: String) -> Dictionary:
	var e := PackedStringArray()
	if sha256.length() != 64 or not _is_hex(sha256):
		e.append("prepare: sha256 must be 64 hexadecimal characters")
	var analysis := _analyze(data, e)
	if not e.is_empty():
		return {ok = false, errors = e, prepared = {}}
	var d: Dictionary = analysis.d
	var r: Dictionary = analysis.results
	var prepared := {
		identity = {schema = FORMAT, family = d.family, variant = d.variant, status = d.status,
			data_sha256 = sha256.to_lower(), experimental = true},
		mass_kg = r.mass,
		inertia_kg_m2 = r.inertia.duplicate(),
		rotors = [],
		rotor_law = {thrust_coefficient_n_s2 = d.k_t, torque_coefficient_n_m_s2 = d.k_q,
			rotor_drag_n_s2_per_m = d.rotor_drag, max_speed_rad_s = d.max_speed},
		airframe = {drag_areas_m2 = d.drag_areas.duplicate()},
		powertrain = d.powertrain.duplicate(true),
		controller = d.controller.duplicate(true),
		contacts = d.contacts.duplicate(true),
		camera = d.camera.duplicate(true),
		start = {rest_height_m = d.rest_height},
		derived = {hover_speed_rad_s = r.hover_speed, hover_thrust_per_rotor_n = r.hover_thrust,
			static_max_thrust_per_rotor_n = r.static_max_thrust, thrust_to_weight = r.thrust_to_weight,
			min_prop_clearance_m = r.clearance, effective_yaw_inertia_kg_m2 = r.effective_yaw,
			kappa_m = d.k_q / d.k_t},
	}
	for rotor: Dictionary in d.rotors:
		prepared.rotors.append({id = rotor.id, hub_frd = rotor.hub_frd.duplicate(), spin = rotor.spin,
			diameter_m = rotor.diameter_m, inertia_kg_m2 = rotor.inertia_kg_m2})
	if d.powertrain.law == LAW_ELECTRIC:
		prepared.battery = d.battery.duplicate(true)
	return {ok = true, errors = e, prepared = prepared}


## Steady shaft speed (rad/s) of one rotor at command u and supply voltage v, from prepared powertrain/rotor_law
## blocks: the electrical static torque balance (nonnegative root; 0 when the motor cannot overcome I0) or the
## lab law's u * full-command speed (v ignored).
static func static_speed(powertrain: Dictionary, rotor_law: Dictionary, u: float, v: float) -> float:
	if powertrain.law == LAW_LAB:
		return maxf(u, 0.0) * float(powertrain.full_command_speed_rad_s)
	return _electric_speed(u, v, float(powertrain.kv_rad_s_per_v), float(powertrain.resistance_ohm),
		float(powertrain.no_load_current_a), float(rotor_law.torque_coefficient_n_m_s2))



## Audit A08: quasi-steady hover operating point on the LOADED shared pack at open-circuit voltage `voc` (charge
## frozen), with the plant's own laws: shaft speed from the rotor law, motor current from the shaft balance with the
## regularized friction (I = I0*clamp(w/FRICTION_SPEED, 0, 1) + Kv*kQ*w^2), drive A_i = d_i*V = w_i/Kv + R*I_i,
## P = sum(A_i*I_i) and the bus V^2 - B*V + Rp*P = 0 with B = voc - Rp*Iaux. The high-voltage root is the branch reached
## from open circuit as the load rises; Rp = 0 gives V = B exactly. Every duty must stay below max_command. Not a
## sustained-hover proof: positive pack current still drains the charge.
## {ok, message, v_bus_v, speeds_rad_s, currents_a, drive_v, duties, power_w, pack_current_a, max_power_w}.
static func hover_bus_solution(pt: Dictionary, battery: Dictionary, k_t: float, k_q: float,
		thrusts: PackedFloat64Array, voc: float) -> Dictionary:
	var kv: float = pt.kv_rad_s_per_v
	var r_motor: float = pt.resistance_ohm
	var i_no_load: float = pt.no_load_current_a
	var top: float = pt.max_command
	var r_pack: float = battery.resistance_ohm
	var i_aux: float = battery.auxiliary_current_a
	var speeds := PackedFloat64Array()
	var currents := PackedFloat64Array()
	var drives := PackedFloat64Array()
	var power := 0.0
	for thrust: float in thrusts:
		if not (thrust > 0.0) or not (k_t > 0.0):
			return {ok = false, message = "hover thrust %s N is not positive" % thrust}
		var w := sqrt(thrust / k_t)
		var current := i_no_load * clampf(w / FRICTION_SPEED, 0.0, 1.0) + kv * k_q * w * w
		var drive := w / kv + r_motor * current
		speeds.append(w)
		currents.append(current)
		drives.append(drive)
		power += drive * current
	var b := voc - r_pack * i_aux
	if not (b > 0.0):
		return {ok = false, message = "the auxiliary load leaves no positive bus voltage (open circuit %s V, pack %s ohm, auxiliary %s A)" % [
			voc, r_pack, i_aux]}
	var v_bus := b
	var p_max := INF
	if r_pack > 0.0:
		p_max = b * b / (4.0 * r_pack)
		var disc := b * b - 4.0 * r_pack * power
		if not (disc > BUS_DISCRIMINANT_MIN * b * b):
			return {ok = false, message = "the loaded pack cannot carry the hover load: %s W at the motor terminals against at most %s W deliverable (open circuit %s V, pack %s ohm, auxiliary %s A)" % [
				power, p_max, voc, r_pack, i_aux]}
		v_bus = 0.5 * (b + sqrt(disc))
	var duties := PackedFloat64Array()
	var pack_current := i_aux
	for i in drives.size():
		duties.append(drives[i] / v_bus)
		pack_current += duties[i] * currents[i]
		if not (duties[i] < top):
			return {ok = false, message = "rotor %d needs duty %s at the loaded bus %s V but max_command is %s" % [i + 1, duties[i], v_bus, top]}
	var residual := absf(v_bus - (voc - r_pack * pack_current))
	if not (residual <= BUS_RESIDUAL_TOLERANCE * maxf(voc, 1.0)):
		return {ok = false, message = "loaded bus residual %s V exceeds the tolerance (ill-conditioned operating point)" % residual}
	return {ok = true, message = "", v_bus_v = v_bus, speeds_rad_s = speeds, currents_a = currents, drive_v = drives,
		duties = duties, power_w = power, pack_current_a = pack_current, max_power_w = p_max}


## Audit A09: the physical invariants of a PREPARED model (what `prepare` returns, or an in-memory equivalent that a
## test, the Workshop or a candidate replay hands to the session): signs and domains the plant relies on (positive mass,
## coefficients and stiffness; nonnegative drag, resistances, auxiliary load, damping and friction; a positive-definite
## inertia also without the spinning rotors; two rotors spinning each way; a monotone open-circuit table; idle below
## max command) and hover reachability on the loaded pack. Raw-only checks (units, provenance, inventory, sanity upper
## bounds, swept-disc clearance, diagnostics) are not repeated. Precondition: the prepared shape
## (session._prepared_shape_error). Field-path errors; empty = admissible. Nothing is clamped or repaired.
static func physical_invariant_errors(m: Dictionary) -> PackedStringArray:
	var e := PackedStringArray()
	_positive(e, "mass_kg", m.get("mass_kg"))
	var law: Dictionary = m.rotor_law
	_positive(e, "rotor_law.thrust_coefficient_n_s2", law.get("thrust_coefficient_n_s2"))
	_positive(e, "rotor_law.torque_coefficient_n_m_s2", law.get("torque_coefficient_n_m_s2"))
	_nonnegative(e, "rotor_law.rotor_drag_n_s2_per_m", law.get("rotor_drag_n_s2_per_m"))
	_positive(e, "rotor_law.max_speed_rad_s", law.get("max_speed_rad_s"))
	var drag: PackedFloat64Array = m.airframe.drag_areas_m2
	for k in drag.size():
		_nonnegative(e, "airframe.drag_areas_m2[%d]" % k, drag[k])
	var spins := 0
	var rotor_inertia := 0.0
	for i in m.rotors.size():
		var rotor: Dictionary = m.rotors[i]
		var spin := float(rotor.get("spin", 0.0))
		if absf(spin) != 1.0:
			e.append("rotors[%d].spin: must be +1 or -1" % i)
		spins += int(spin)
		_positive(e, "rotors[%d].diameter_m" % i, rotor.get("diameter_m"))
		_positive(e, "rotors[%d].inertia_kg_m2" % i, rotor.get("inertia_kg_m2"))
		rotor_inertia += float(rotor.get("inertia_kg_m2", 0.0))
	if spins != 0:
		e.append("rotors: two must spin each way")
	var pt: Dictionary = m.powertrain
	var electric: bool = pt.get("law") == LAW_ELECTRIC
	if electric:
		_positive(e, "powertrain.kv_rad_s_per_v", pt.get("kv_rad_s_per_v"))
		_positive(e, "powertrain.resistance_ohm", pt.get("resistance_ohm"))
		_nonnegative(e, "powertrain.no_load_current_a", pt.get("no_load_current_a"))
		if str(pt.get("braking", "none")) not in ["none", "damped"]:
			e.append("powertrain.braking: must be 'none' or 'damped'")
	elif pt.get("law") == LAW_LAB:
		_positive(e, "powertrain.full_command_speed_rad_s", pt.get("full_command_speed_rad_s"))
		_positive(e, "powertrain.time_constant_s", pt.get("time_constant_s"))
	else:
		e.append("powertrain.law: unsupported law '%s'" % str(pt.get("law")))
	var idle := float(pt.get("idle_command", NAN))
	var top := float(pt.get("max_command", NAN))
	if not (idle >= 0.0 and idle < top and top <= 1.0):
		e.append("powertrain: need 0 <= idle_command < max_command <= 1 (got %s, %s)" % [idle, top])
	var battery: Dictionary = {}
	if electric:
		battery = m.get("battery", {})
		_positive(e, "battery.capacity_ah", battery.get("capacity_ah"))
		_nonnegative(e, "battery.resistance_ohm", battery.get("resistance_ohm"))
		_nonnegative(e, "battery.auxiliary_current_a", battery.get("auxiliary_current_a"))
		var soc := float(battery.get("initial_soc", NAN))
		if not (soc > 0.0 and soc <= 1.0):
			e.append("battery.initial_soc: must lie in (0, 1], got %s" % soc)
		var ocv: PackedFloat64Array = battery.get("ocv_points", PackedFloat64Array())
		if ocv.size() < 4 or ocv.size() % 2 != 0:
			e.append("battery.ocv_points: needs at least two [soc, volts] rows")
		else:
			for i in range(0, ocv.size(), 2):
				if not (ocv[i + 1] > 0.0):
					e.append("battery.ocv_points[%d]: voltage must be positive" % (i / 2))
				if i > 0 and (not (ocv[i] > ocv[i - 2]) or not (ocv[i + 1] >= ocv[i - 1])):
					e.append("battery.ocv_points[%d]: state of charge must increase and voltage must not decrease" % (i / 2))
	var con: Dictionary = m.contacts
	_positive(e, "contacts.stiffness_n_per_m", con.get("stiffness_n_per_m"))
	_nonnegative(e, "contacts.damping_n_s_per_m", con.get("damping_n_s_per_m"))
	_nonnegative(e, "contacts.friction", con.get("friction"))
	_positive(e, "contacts.crash_speed_mps", con.get("crash_speed_mps"))
	_positive(e, "contacts.rotor_strike_speed_rad_s", con.get("rotor_strike_speed_rad_s"))
	if not e.is_empty():
		return e # the checks below divide by these values
	var j: PackedFloat64Array = m.inertia_kg_m2
	if not _positive_definite(j):
		e.append("inertia_kg_m2: %s is not positive definite" % [j])
	var effective := j.duplicate()
	effective[2] -= rotor_inertia
	if not _positive_definite(effective):
		e.append("rotors: the inertia without the spinning rotors (Jzz %s) is not positive definite" % effective[2])
	var k_t := float(law.thrust_coefficient_n_s2)
	var k_q := float(law.torque_coefficient_n_m_s2)
	var b_rows: Array = [[], [], [], []]
	for rotor: Dictionary in m.rotors:
		b_rows[0].append(1.0)
		b_rows[1].append(-float(rotor.hub_frd[1]))
		b_rows[2].append(float(rotor.hub_frd[0]))
		b_rows[3].append(float(rotor.spin) * k_q / k_t)
	if absf(_determinant4(b_rows)) < 1.0e-12:
		e.append("rotors: the spin/hub arrangement has no independent roll, pitch and yaw authority")
		return e
	var hover := solve4(b_rows, PackedFloat64Array([float(m.mass_kg) * GRAVITY, 0.0, 0.0, 0.0]))
	_powertrain_hover(e, pt, battery, k_t, k_q, float(law.max_speed_rad_s), hover)
	return e

# --- admission ------------------------------------------------------------------------------------

static func _admit(raw: Variant, label: String) -> Dictionary:
	var e := PackedStringArray()
	if typeof(raw) != TYPE_DICTIONARY:
		e.append("%s: top level must be an object" % label)
		return {ok = false, errors = e, data = {}, label = label}
	_analyze(raw, e)
	return {ok = e.is_empty(), errors = e, data = raw.duplicate(true) if e.is_empty() else {}, label = label}


## Structural parse, then (only when it is clean) the semantic checks. Returns {d, results}.
static func _analyze(raw: Variant, e: PackedStringArray) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		e.append("document: top level must be an object")
		return {}
	var d := _parse(raw, e)
	if not e.is_empty():
		return {}
	var results := _semantics(raw, d, e)
	return {d = d, results = results}


static func _parse(raw: Dictionary, e: PackedStringArray) -> Dictionary:
	var d := {}
	if raw.get("format") != FORMAT:
		e.append("format: must be '%s'" % FORMAT)
	_closed(e, "", raw, TOP_KEYS)
	# identity
	var identity := _block(e, "", raw, "identity", ["family", "variant", "name", "status"])
	d.family = _ident(e, "identity", identity, "family")
	d.variant = _ident(e, "identity", identity, "variant")
	_text(e, "identity", identity, "name")
	d.status = _text(e, "identity", identity, "status")
	if identity.has("status") and d.status != STATUS:
		e.append("identity.status: must be '%s' (no measured build is admitted yet)" % STATUS)
	if not str(d.family).is_empty() and not str(d.variant).begins_with(str(d.family) + "-"):
		e.append("identity.variant: must begin with the family id '%s-'" % d.family)
	# capabilities
	var capabilities := {}
	var caps: Variant = raw.get("capabilities")
	if typeof(caps) != TYPE_ARRAY:
		e.append("capabilities: missing or not an array")
	else:
		for i in caps.size():
			var cap: Variant = caps[i]
			if typeof(cap) != TYPE_STRING or not CAPABILITIES.has(cap):
				e.append("capabilities[%d]: unsupported capability '%s'" % [i, str(cap)])
			elif capabilities.has(cap):
				e.append("capabilities[%d]: duplicate capability '%s'" % [i, cap])
			else:
				capabilities[cap] = true
		for required: String in ["multirotor", "ground_start"]:
			if not capabilities.has(required):
				e.append("capabilities: must list '%s'" % required)
	d.capabilities = capabilities
	# provenance
	var prov := _block(e, "", raw, "provenance", ["generator", "generator_version", "sources", "sources_sha256",
		"notes", "references", "derived_diagnostics"])
	_text(e, "provenance", prov, "generator")
	_text(e, "provenance", prov, "generator_version")
	_text(e, "provenance", prov, "sources")
	_text(e, "provenance", prov, "notes")
	var sources_sha: String = _text(e, "provenance", prov, "sources_sha256")
	if prov.has("sources_sha256") and (sources_sha.length() != 64 or not _is_hex(sources_sha) or sources_sha != sources_sha.to_lower()):
		e.append("provenance.sources_sha256: must be 64 lowercase hexadecimal characters")
	var refs: Variant = prov.get("references")
	if typeof(refs) != TYPE_DICTIONARY:
		e.append("provenance.references: missing or not an object")
	else:
		for key: Variant in refs:
			if typeof(refs[key]) != TYPE_STRING or str(refs[key]).strip_edges().is_empty():
				e.append("provenance.references.%s: must be a nonempty string" % str(key))
	d.diagnostics = _diagnostics(e, prov)
	# mass inventory
	var inv := _block(e, "", raw, "mass_inventory", ["datum", "components"])
	_text(e, "mass_inventory", inv, "datum")
	d.components = []
	var comps: Variant = inv.get("components")
	if typeof(comps) != TYPE_ARRAY or comps.is_empty() or comps.size() > MAX_COMPONENTS:
		e.append("mass_inventory.components: must be an array of 1..%d components" % MAX_COMPONENTS)
	else:
		var ids := {}
		for i in comps.size():
			var path := "mass_inventory.components[%d]" % i
			var c: Variant = comps[i]
			if typeof(c) != TYPE_DICTIONARY:
				e.append("%s: must be an object" % path)
				continue
			_closed(e, path, c, ["id", "mass", "position", "shape", "rotor_id"])
			var id := _text(e, path, c, "id")
			if ids.has(id):
				e.append("%s.id: duplicate component id '%s'" % [path, id])
			ids[id] = true
			var item := {id = id, mass = _qf(e, path, c, "mass", "kg", 0.0, 20.0, true),
				position = _qa(e, path, c, "position", "m", -2.0, 2.0, 3), rotor_id = 0}
			if c.has("rotor_id"):
				item.rotor_id = _int(e, path, c, "rotor_id", 1, 4)
			item.own = _shape(e, path, c)
			d.components.append(item)
	# rotors
	d.rotors = []
	var rotors: Variant = raw.get("rotors")
	if typeof(rotors) != TYPE_ARRAY or rotors.size() != 4:
		e.append("rotors: must be an array of exactly four rotors")
	else:
		var seen := {}
		var spins := 0
		for i in 4:
			var path := "rotors[%d]" % i
			var src: Variant = rotors[i]
			if typeof(src) != TYPE_DICTIONARY:
				e.append("%s: must be an object" % path)
				continue
			_closed(e, path, src, ["id", "spin", "hub_frd", "axis", "diameter", "inertia", "prop", "motor"])
			var id := _int(e, path, src, "id", 1, 4)
			if seen.has(id):
				e.append("%s.id: duplicate rotor id %d" % [path, id])
			seen[id] = true
			var spin := float(_int(e, path, src, "spin", -1, 1))
			if src.has("spin") and absf(spin) != 1.0:
				e.append("%s.spin: must be +1 or -1" % path)
			spins += int(spin)
			var axis := _qa(e, path, src, "axis", "1", -2.0, 2.0, 3)
			if src.has("axis") and axis.size() == 3:
				var n := sqrt(axis[0] * axis[0] + axis[1] * axis[1] + axis[2] * axis[2])
				if absf(n - 1.0) > UNIT_AXIS_TOLERANCE:
					e.append("%s.axis: must be a unit vector (norm %s)" % [path, n])
				elif not (axis[0] == 0.0 and axis[1] == 0.0 and axis[2] == -1.0):
					e.append("%s.axis: unsupported thrust axis %s; only (0, 0, -1) is admitted" % [path, axis])
			_text(e, path, src, "prop")
			_text(e, path, src, "motor")
			d.rotors.append({id = id, spin = spin, hub_frd = _qa(e, path, src, "hub_frd", "m", -2.0, 2.0, 3),
				diameter_m = _qf(e, path, src, "diameter", "m", 0.0, 2.0, true),
				inertia_kg_m2 = _qf(e, path, src, "inertia", "kg*m^2", 0.0, 1.0, true), index = i})
		if seen.size() == 4 and spins != 0:
			e.append("rotors: spins must be two +1 and two -1")
		var ordered := []
		for id in range(1, 5):
			for rotor: Dictionary in d.rotors:
				if rotor.id == id:
					ordered.append(rotor)
		if ordered.size() == 4:
			d.rotors = ordered
		elif e.is_empty():
			e.append("rotors: ids must be exactly 1, 2, 3 and 4")
	# rotor law and airframe
	var law := _block(e, "", raw, "rotor_law", ["law", "thrust_coefficient", "torque_coefficient", "rotor_drag", "max_speed"])
	if law.get("law") != ROTOR_LAW:
		e.append("rotor_law.law: must be '%s'" % ROTOR_LAW)
	d.k_t = _qf(e, "rotor_law", law, "thrust_coefficient", "N*s^2", 0.0, 1.0, true)
	d.k_q = _qf(e, "rotor_law", law, "torque_coefficient", "N*m*s^2", 0.0, 1.0, true)
	d.rotor_drag = _qf(e, "rotor_law", law, "rotor_drag", "N*s^2/m", 0.0, 1.0)
	d.max_speed = _qf(e, "rotor_law", law, "max_speed", "rad/s", 0.0, 1.0e5, true)
	var airframe := _block(e, "", raw, "airframe", ["drag_areas"])
	d.drag_areas = _qa(e, "airframe", airframe, "drag_areas", "m^2", 0.0, 10.0, 3)
	# powertrain
	var pt_raw: Variant = raw.get("powertrain")
	var pt: Dictionary = pt_raw if typeof(pt_raw) == TYPE_DICTIONARY else {}
	if typeof(pt_raw) != TYPE_DICTIONARY:
		e.append("powertrain: missing block or not an object")
	var pt_law: Variant = pt.get("law")
	d.powertrain = {law = pt_law}
	if pt_law == LAW_ELECTRIC:
		_closed(e, "powertrain", pt, ["law", "kv", "resistance", "no_load_current", "braking", "idle_command", "max_command"])
		# ESC bridge behaviour below the back-EMF: "none" = one-quadrant drive (the shaft coasts), "damped" =
		# complementary switching (signed motor current: active braking, with regeneration into the pack).
		d.powertrain.braking = pt.get("braking")
		if typeof(d.powertrain.braking) != TYPE_STRING or d.powertrain.braking not in ["none", "damped"]:
			e.append("powertrain.braking: must be 'none' or 'damped'")
			d.powertrain.braking = "none"
		d.powertrain.kv_rad_s_per_v = _qf(e, "powertrain", pt, "kv", "rad/s/V", 0.0, 1.0e4, true)
		d.powertrain.resistance_ohm = _qf(e, "powertrain", pt, "resistance", "ohm", 0.0, 100.0, true)
		d.powertrain.no_load_current_a = _qf(e, "powertrain", pt, "no_load_current", "A", 0.0, 100.0)
	elif pt_law == LAW_LAB:
		_closed(e, "powertrain", pt, ["law", "full_command_speed", "time_constant", "idle_command", "max_command"])
		d.powertrain.full_command_speed_rad_s = _qf(e, "powertrain", pt, "full_command_speed", "rad/s", 0.0, 1.0e5, true)
		d.powertrain.time_constant_s = _qf(e, "powertrain", pt, "time_constant", "s", 0.0, 10.0, true)
	elif not pt.is_empty():
		e.append("powertrain.law: unsupported law '%s' (admitted: %s, %s)" % [str(pt_law), LAW_ELECTRIC, LAW_LAB])
	d.powertrain.idle_command = _qf(e, "powertrain", pt, "idle_command", "1", 0.0, 1.0)
	d.powertrain.max_command = _qf(e, "powertrain", pt, "max_command", "1", 0.0, 1.0, true)
	if not (d.powertrain.idle_command < d.powertrain.max_command):
		e.append("powertrain: idle_command must be below max_command")
	# battery: required by and only by the electrical law
	if pt_law == LAW_ELECTRIC and not capabilities.has("battery"):
		e.append("capabilities: the %s law requires 'battery'" % LAW_ELECTRIC)
	if pt_law != LAW_ELECTRIC and capabilities.has("battery"):
		e.append("capabilities: 'battery' is only admitted with the %s law" % LAW_ELECTRIC)
	if pt_law == LAW_ELECTRIC:
		if not raw.has("battery"):
			e.append("battery: missing block (required by the %s law)" % LAW_ELECTRIC)
		else:
			d.battery = _battery(e, raw)
	elif raw.has("battery"):
		e.append("battery: block not allowed with the %s law" % str(pt_law))
	# controller
	d.controller = _controller(e, raw)
	# contacts
	var con := _block(e, "", raw, "contacts", ["feet", "stiffness_per_foot", "damping_per_foot", "friction", "hull",
		"crash_speed", "rotor_strike_speed"])
	d.contacts = {feet_frd = _ql(e, "contacts", con, "feet", "m", -2.0, 2.0, 3, 3, 8),
		stiffness_n_per_m = _qf(e, "contacts", con, "stiffness_per_foot", "N/m", 0.0, 1.0e7, true),
		damping_n_s_per_m = _qf(e, "contacts", con, "damping_per_foot", "N*s/m", 0.0, 1.0e5),
		friction = _qf(e, "contacts", con, "friction", "1", 0.0, 3.0),
		hull_frd = _ql(e, "contacts", con, "hull", "m", -2.0, 2.0, 3, 1, MAX_POINTS),
		crash_speed_mps = _qf(e, "contacts", con, "crash_speed", "m/s", 0.0, 100.0, true),
		rotor_strike_speed_rad_s = _qf(e, "contacts", con, "rotor_strike_speed", "rad/s", 0.0, 1.0e5, true)}
	# camera
	var cam := _block(e, "", raw, "camera", ["mount", "tilt", "hfov"])
	d.camera = {mount_frd = _qa(e, "camera", cam, "mount", "m", -1.0, 1.0, 3),
		tilt_deg = _qf(e, "camera", cam, "tilt", "deg", 0.0, 60.0),
		hfov_deg = _qf(e, "camera", cam, "hfov", "deg", 60.0, 170.0)}
	# start
	var start := _block(e, "", raw, "start", ["mode", "armed", "rest_height"])
	if start.get("mode") != START_MODE:
		e.append("start.mode: only '%s' is admitted" % START_MODE)
	if typeof(start.get("armed")) != TYPE_BOOL or start.get("armed") != false:
		e.append("start.armed: must be false (a session starts disarmed)")
	d.rest_height = _qf(e, "start", start, "rest_height", "m", 0.0, 2.0, true)
	return d


static func _battery(e: PackedStringArray, raw: Dictionary) -> Dictionary:
	var bat := _block(e, "", raw, "battery", ["cells", "capacity", "ocv_points", "resistance", "auxiliary_current", "initial_soc"])
	var cells := _qi(e, "battery", bat, "cells", "1", 1, 14)
	var points := _ql(e, "battery", bat, "ocv_points", "V", 0.0, 100.0, 2, 2, MAX_POINTS)
	var flat := PackedFloat64Array()
	for i in points.size():
		var p: PackedFloat64Array = points[i]
		var path := "battery.ocv_points[%d]" % i
		if i == 0 and p[0] != 0.0:
			e.append("%s: the table must start at state of charge 0" % path)
		if i == points.size() - 1 and p[0] != 1.0:
			e.append("%s: the table must end at state of charge 1" % path)
		if i > 0 and not (p[0] > points[i - 1][0]):
			e.append("%s: state of charge must increase strictly" % path)
		if i > 0 and not (p[1] >= points[i - 1][1]):
			e.append("%s: open-circuit voltage must not decrease" % path)
		if not (p[1] > 0.0):
			e.append("%s: voltage must be positive" % path)
		if cells > 0:
			var per_cell := p[1] / float(cells)
			if per_cell < CELL_VOLTS_MIN or per_cell > CELL_VOLTS_MAX:
				e.append("%s: %s V is %s V per cell for %d cells, outside [%s, %s]" % [path, p[1], per_cell, cells,
					CELL_VOLTS_MIN, CELL_VOLTS_MAX])
		flat.append(p[0])
		flat.append(p[1])
	return {cells = cells, capacity_ah = _qf(e, "battery", bat, "capacity", "A*h", 0.0, 100.0, true), ocv_points = flat,
		resistance_ohm = _qf(e, "battery", bat, "resistance", "ohm", 0.0, 10.0),
		auxiliary_current_a = _qf(e, "battery", bat, "auxiliary_current", "A", 0.0, 100.0),
		initial_soc = _qf(e, "battery", bat, "initial_soc", "1", 0.0, 1.0, true)}


static func _controller(e: PackedStringArray, raw: Dictionary) -> Dictionary:
	var ctl := _block(e, "", raw, "controller", ["law", "sample_rate", "kp", "ki", "kd", "i_max", "kaw", "tau_limit",
		"gyro_lpf", "dterm_lpf", "kff", "setpoint_lpf", "angle", "arm_low_throttle", "allocator_weights", "throttle_rate"])
	if ctl.get("law") != CONTROLLER_LAW:
		e.append("controller.law: must be '%s'" % CONTROLLER_LAW)
	var sample := _qi(e, "controller", ctl, "sample_rate", "Hz", 1, 100000)
	if ctl.has("sample_rate") and sample != SAMPLE_HZ and sample != 0:
		e.append("controller.sample_rate: only %d Hz is admitted, got %d" % [SAMPLE_HZ, sample])
	var nyquist := 0.5 * float(SAMPLE_HZ)
	var out := {sample_hz = sample,
		kp = _qa(e, "controller", ctl, "kp", "N*m*s/rad", 0.0, 100.0, 3),
		ki = _qa(e, "controller", ctl, "ki", "N*m/rad", 0.0, 1000.0, 3),
		kd = _qa(e, "controller", ctl, "kd", "N*m*s^2/rad", 0.0, 10.0, 3),
		i_max = _qa(e, "controller", ctl, "i_max", "N*m", 0.0, 100.0, 3),
		kaw = _qa(e, "controller", ctl, "kaw", "1/s", 0.0, 1.0e4, 3),
		tau_limit = _qa(e, "controller", ctl, "tau_limit", "N*m", 0.0, 100.0, 3),
		gyro_lpf_hz = _qf(e, "controller", ctl, "gyro_lpf", "Hz", 0.0, 1.0e5, true),
		dterm_lpf_hz = _qf(e, "controller", ctl, "dterm_lpf", "Hz", 0.0, 1.0e5, true),
		kff = _qa(e, "controller", ctl, "kff", "N*m*s^2/rad", 0.0, 10.0, 3),
		setpoint_lpf_hz = _qf(e, "controller", ctl, "setpoint_lpf", "Hz", 0.0, 1.0e5, true),
		arm_low_throttle = _qf(e, "controller", ctl, "arm_low_throttle", "1", 0.0, 1.0, true),
		allocator_weights = _qa(e, "controller", ctl, "allocator_weights", "1", 0.0, 1.0e6, 4),
		throttle_rate_per_s = _qf(e, "controller", ctl, "throttle_rate", "1/s", 0.0, 100.0, true)}
	for key: String in ["gyro_lpf", "dterm_lpf", "setpoint_lpf"]:
		var cutoff: float = out[key + "_hz"]
		if ctl.has(key) and cutoff >= nyquist:
			e.append("controller.%s: %s Hz is not below the %s Hz Nyquist frequency of the %d Hz sample rate" % [key,
				cutoff, nyquist, SAMPLE_HZ])
	for i in 3:
		if ctl.has("tau_limit") and not (out.tau_limit[i] > 0.0):
			e.append("controller.tau_limit: every axis limit must be positive")
			break
	for i in 4:
		if ctl.has("allocator_weights") and not (out.allocator_weights[i] > 0.0):
			e.append("controller.allocator_weights: every weight must be positive")
			break
	var angle := _block(e, "controller", ctl, "angle", ["max_tilt", "gain", "rate_limit"])
	out.angle_max_tilt_rad = deg_to_rad(_qf(e, "controller.angle", angle, "max_tilt", "deg", 0.0, 90.0, true))
	out.angle_gain_per_s = _qf(e, "controller.angle", angle, "gain", "1/s", 0.0, 1000.0, true)
	out.angle_rate_limit_rad_s = deg_to_rad(_qf(e, "controller.angle", angle, "rate_limit", "deg/s", 0.0, 5000.0, true))
	return out


static func _shape(e: PackedStringArray, path: String, c: Dictionary) -> PackedFloat64Array:
	var own := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var shape_path := path + ".shape"
	var shape: Variant = c.get("shape")
	if typeof(shape) != TYPE_DICTIONARY:
		e.append("%s: missing or not an object" % shape_path)
		return own
	var type: Variant = shape.get("type")
	var mass := 0.0
	var m: Variant = c.get("mass")
	if typeof(m) == TYPE_DICTIONARY and typeof(m.get("value")) in [TYPE_FLOAT, TYPE_INT]:
		mass = float(m.value)
	if type == "point":
		_closed(e, shape_path, shape, ["type"])
	elif type == "box":
		_closed(e, shape_path, shape, ["type", "size"])
		var s := _qa(e, shape_path, shape, "size", "m", 0.0, 4.0, 3)
		for i in 3:
			if not (s[i] > 0.0) and shape.has("size"):
				e.append("%s.size: every box length must be positive" % shape_path)
				break
		own[0] = mass * (s[1] * s[1] + s[2] * s[2]) / 12.0
		own[1] = mass * (s[0] * s[0] + s[2] * s[2]) / 12.0
		own[2] = mass * (s[0] * s[0] + s[1] * s[1]) / 12.0
	elif type == "axisymmetric_z":
		_closed(e, shape_path, shape, ["type", "axial_inertia", "transverse_inertia"])
		var axial := _qf(e, shape_path, shape, "axial_inertia", "kg*m^2", 0.0, 10.0, true)
		var transverse := _qf(e, shape_path, shape, "transverse_inertia", "kg*m^2", 0.0, 10.0, true)
		if axial > 2.0 * transverse:
			e.append("%s: axial inertia exceeds twice the transverse inertia (not a physical body)" % shape_path)
		own[0] = transverse
		own[1] = transverse
		own[2] = axial
	else:
		e.append("%s.type: unsupported shape '%s' (admitted: %s)" % [shape_path, str(type), SHAPE_TYPES])
	return own


static func _diagnostics(e: PackedStringArray, prov: Dictionary) -> Dictionary:
	var out := {}
	var path := "provenance.derived_diagnostics"
	var diag: Variant = prov.get("derived_diagnostics")
	if typeof(diag) != TYPE_DICTIONARY:
		e.append("%s: missing or not an object" % path)
		return out
	_closed(e, path, diag, DIAGNOSTICS.keys())
	for key: String in DIAGNOSTICS:
		var size: int = DIAGNOSTICS[key]
		var value: Variant = diag.get(key)
		if not diag.has(key):
			e.append("%s.%s: missing" % [path, key])
		elif size < 0:
			if typeof(value) != TYPE_STRING or str(value).strip_edges().is_empty():
				e.append("%s.%s: must be a nonempty string" % [path, key])
		elif size == 0:
			if not _finite_number(value):
				e.append("%s.%s: must be a finite number" % [path, key])
			else:
				out[key] = float(value)
		else:
			out[key] = _numbers(e, "%s.%s" % [path, key], value, size, -INF, INF)
	return out


# --- semantic checks --------------------------------------------------------------------------------

static func _semantics(raw: Dictionary, d: Dictionary, e: PackedStringArray) -> Dictionary:
	var r := {}
	# Mass, CG from the datum and the locked inertia about the CG.
	var mass := 0.0
	var first := PackedFloat64Array([0.0, 0.0, 0.0])
	for c: Dictionary in d.components:
		mass += c.mass
		for k in 3:
			first[k] += c.mass * c.position[k]
	var cg := PackedFloat64Array([first[0] / mass, first[1] / mass, first[2] / mass])
	var j := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	for c: Dictionary in d.components:
		var m: float = c.mass
		var o: PackedFloat64Array = c.own
		var dx: float = c.position[0] - cg[0]
		var dy: float = c.position[1] - cg[1]
		var dz: float = c.position[2] - cg[2]
		j[0] += o[0] + m * (dy * dy + dz * dz)
		j[1] += o[1] + m * (dx * dx + dz * dz)
		j[2] += o[2] + m * (dx * dx + dy * dy)
		j[3] += o[3] - m * dx * dy
		j[4] += o[4] - m * dx * dz
		j[5] += o[5] - m * dy * dz
	r.mass = mass
	r.cg = cg
	r.inertia = j
	if not _positive_definite(j):
		e.append("mass_inventory: locked inertia %s is not positive definite" % j)
	var rotor_sum := 0.0
	for rotor: Dictionary in d.rotors:
		rotor_sum += rotor.inertia_kg_m2
	var effective := j.duplicate()
	effective[2] -= rotor_sum # sum of J_i a_i a_i^T with a = (0, 0, -1)
	r.effective_yaw = effective[2]
	if not (effective[2] > 0.0) or not _positive_definite(effective):
		e.append("rotors: effective inertia (locked minus rotor spin inertia, Jzz %s) is not positive definite" % effective[2])
	# Each rotor's spinning assembly appears exactly once in the inventory, at its hub.
	for rotor: Dictionary in d.rotors:
		var linked := []
		for i in d.components.size():
			if d.components[i].rotor_id == rotor.id:
				linked.append(i)
		var path := "rotors[%d]" % rotor.index
		if linked.size() != 1:
			e.append("%s: exactly one mass_inventory component must carry rotor_id %d (found %d)" % [path, rotor.id, linked.size()])
			continue
		var c: Dictionary = d.components[linked[0]]
		var cpath := "mass_inventory.components[%d]" % linked[0]
		var shape: Dictionary = raw.mass_inventory.components[linked[0]].shape
		if shape.get("type") != "axisymmetric_z" or not _agrees(c.own[2], rotor.inertia_kg_m2, 0.0, 1.0e-12):
			e.append("%s: the axisymmetric_z axial inertia must equal %s.inertia (no rotor inertia double count)" % [cpath, path])
		var hub := PackedFloat64Array([c.position[0] - cg[0], c.position[1] - cg[1], c.position[2] - cg[2]])
		if not _vector_agrees(hub, rotor.hub_frd):
			e.append("%s.hub_frd: %s disagrees with the inventory position minus the CG %s" % [path, rotor.hub_frd, hub])
	# Full 3D swept-disc separation of every pair.
	var clearance := INF
	for a in 4:
		for b in range(a + 1, 4):
			var ra: Dictionary = d.rotors[a]
			var rb: Dictionary = d.rotors[b]
			var dist := sqrt(_sq(ra.hub_frd[0] - rb.hub_frd[0]) + _sq(ra.hub_frd[1] - rb.hub_frd[1]) + _sq(ra.hub_frd[2] - rb.hub_frd[2]))
			var gap: float = dist - 0.5 * (ra.diameter_m + rb.diameter_m)
			clearance = minf(clearance, gap)
			if gap < 0.0:
				e.append("rotors: rotor %d and rotor %d swept discs overlap (signed clearance %s m)" % [ra.id, rb.id, gap])
	r.clearance = clearance
	# Wrench authority and the static hover balance.
	var kappa: float = d.k_q / d.k_t
	var arm := 0.0
	for rotor: Dictionary in d.rotors:
		arm = maxf(arm, sqrt(_sq(rotor.hub_frd[0]) + _sq(rotor.hub_frd[1])))
	var normalized: Array = [[], [], [], []]
	var b_rows: Array = [[], [], [], []]
	for rotor: Dictionary in d.rotors:
		b_rows[0].append(1.0)
		b_rows[1].append(-rotor.hub_frd[1])
		b_rows[2].append(rotor.hub_frd[0])
		b_rows[3].append(rotor.spin * kappa)
		normalized[0].append(1.0)
		normalized[1].append(-rotor.hub_frd[1] / arm if arm > 0.0 else 0.0)
		normalized[2].append(rotor.hub_frd[0] / arm if arm > 0.0 else 0.0)
		normalized[3].append(rotor.spin)
	var det := _determinant4(normalized)
	r.hover_thrust = 0.0
	r.hover_speed = 0.0
	r.static_max_thrust = 0.0
	r.thrust_to_weight = 0.0
	if absf(det) < MIN_AUTHORITY_DETERMINANT:
		e.append("rotors: spin/hub arrangement has no independent roll, pitch and yaw authority (normalized determinant %s)" % det)
		return r
	var weight := mass * GRAVITY
	var hover := solve4(b_rows, PackedFloat64Array([weight, 0.0, 0.0, 0.0]))
	var hover_min := INF
	var hover_max := -INF
	for t in hover:
		hover_min = minf(hover_min, t)
		hover_max = maxf(hover_max, t)
	r.hover_thrusts = hover
	r.hover_thrust = hover_max
	r.hover_speed = sqrt(maxf(hover_max, 0.0) / d.k_t)
	r.static_max_thrust = _powertrain_hover(e, d.powertrain, d.battery if d.powertrain.law == LAW_ELECTRIC else {},
		d.k_t, d.k_q, d.max_speed, hover)
	r.thrust_to_weight = 4.0 * r.static_max_thrust / weight
	# Feet: at least three non-collinear feet below the CG; the resting height follows from the stiffness.
	var below := []
	var z_low := -INF
	for p: PackedFloat64Array in d.contacts.feet_frd:
		if p[2] > 0.0:
			below.append(p)
		z_low = maxf(z_low, p[2])
	var supported := false
	for a in below.size():
		for b in range(a + 1, below.size()):
			for c in range(b + 1, below.size()):
				var pa: PackedFloat64Array = below[a]
				var pb: PackedFloat64Array = below[b]
				var pc: PackedFloat64Array = below[c]
				var area := 0.5 * absf((pb[0] - pa[0]) * (pc[1] - pa[1]) - (pb[1] - pa[1]) * (pc[0] - pa[0]))
				supported = supported or area > MIN_SUPPORT_AREA
	if not supported:
		e.append("contacts.feet: needs at least three non-collinear feet below the CG")
	var n_low := 0
	for p: PackedFloat64Array in d.contacts.feet_frd:
		if p[2] == z_low:
			n_low += 1
	var rest: float = z_low - weight / (float(n_low) * d.contacts.stiffness_n_per_m)
	if not _agrees(rest, d.rest_height, 0.0, DIAGNOSTIC_TOLERANCE):
		e.append("start.rest_height: %s m disagrees with the static sag on the feet (%s m)" % [d.rest_height, rest])
	if not (rest > 0.0):
		e.append("start.rest_height: the CG would rest at or below the ground (%s m)" % rest)
	# Generator diagnostics must agree with the independent recomputation.
	var diag: Dictionary = d.diagnostics
	var dpath := "provenance.derived_diagnostics"
	_diag_scalar(e, dpath, diag, "mass_kg", mass)
	_diag_vector(e, dpath, diag, "cg_from_datum_m", cg)
	_diag_vector(e, dpath, diag, "inertia_kg_m2", j)
	_diag_scalar(e, dpath, diag, "effective_yaw_inertia_kg_m2", r.effective_yaw)
	_diag_scalar(e, dpath, diag, "min_prop_clearance_m", clearance)
	_diag_scalar(e, dpath, diag, "fit_kt_n_s2", d.k_t)
	_diag_vector(e, dpath, diag, "hover_thrusts_n", hover)
	_diag_scalar(e, dpath, diag, "hover_thrust_per_rotor_n", r.hover_thrust)
	_diag_scalar(e, dpath, diag, "hover_speed_rad_s", r.hover_speed)
	return r



## Hover reachability under the powertrain: the hover thrusts lie strictly between the idle and the static maximum
## thrust at full charge and at the lowest listed state of charge above LOW_CHARGE_SOC (open circuit), and (audit A08)
## the electrical law carries that load on the shared pack at the low-charge point. Appends field errors; returns the
## static maximum thrust per rotor at full charge.
static func _powertrain_hover(e: PackedStringArray, pt: Dictionary, battery: Dictionary, k_t: float, k_q: float,
		max_speed: float, hover: PackedFloat64Array) -> float:
	var hover_min := INF
	var hover_max := -INF
	for t in hover:
		hover_min = minf(hover_min, t)
		hover_max = maxf(hover_max, t)
	var rotor_law := {torque_coefficient_n_m_s2 = k_q}
	var top: float = pt.max_command
	var static_max := 0.0
	var checks := [] # [label, idle thrust, maximum thrust]
	if pt.law == LAW_ELECTRIC:
		var ocv: PackedFloat64Array = battery.ocv_points
		var v_full := ocv[ocv.size() - 1]
		var v_low := NAN
		for i in range(0, ocv.size(), 2):
			if ocv[i] > LOW_CHARGE_SOC:
				v_low = ocv[i + 1]
				break
		var idle_speed := static_speed(pt, rotor_law, pt.idle_command, v_full)
		var w_full := static_speed(pt, rotor_law, top, v_full)
		var idle_thrust: float = k_t * idle_speed * idle_speed
		static_max = k_t * w_full * w_full
		checks.append(["full charge %s V" % v_full, idle_thrust, static_max])
		if is_nan(v_low):
			e.append("battery.ocv_points: no point above state of charge %s for the low-charge hover check" % LOW_CHARGE_SOC)
		else:
			var w_low := static_speed(pt, rotor_law, top, v_low)
			checks.append(["low charge %s V" % v_low, idle_thrust, k_t * w_low * w_low])
			if hover_min > 0.0:
				var loaded := hover_bus_solution(pt, battery, k_t, k_q, hover, v_low)
				if not loaded.ok:
					e.append("hover: %s (low charge %s V)" % [loaded.message, v_low])
		if w_full > max_speed:
			e.append("rotor_law.max_speed: static full-command speed %s rad/s exceeds the declared %s rad/s" % [w_full, max_speed])
	else:
		var full: float = pt.full_command_speed_rad_s
		static_max = k_t * _sq(top * full)
		checks.append(["lab law", k_t * _sq(float(pt.idle_command) * full), static_max])
		if top * full > max_speed:
			e.append("rotor_law.max_speed: max_command * full_command_speed %s rad/s exceeds the declared %s rad/s" % [top * full, max_speed])
	for check: Array in checks:
		if not (hover_min > check[1] and hover_max < check[2]):
			e.append("hover: unreachable at %s; rotor thrusts %s N must lie strictly between idle %s N and static maximum %s N" % [
				check[0], hover, check[1], check[2]])
	return static_max


static func _positive(e: PackedStringArray, path: String, value: Variant) -> void:
	if not (typeof(value) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(value)) and float(value) > 0.0):
		e.append("%s: must be positive, got %s" % [path, value])


static func _nonnegative(e: PackedStringArray, path: String, value: Variant) -> void:
	if not (typeof(value) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(value)) and float(value) >= 0.0):
		e.append("%s: must not be negative, got %s" % [path, value])

static func _diag_scalar(e: PackedStringArray, path: String, diag: Dictionary, key: String, value: float) -> void:
	if diag.has(key) and not _agrees(float(diag[key]), value, 0.0, DIAGNOSTIC_TOLERANCE):
		e.append("%s.%s: recorded %s disagrees with the recomputed %s" % [path, key, diag[key], value])


static func _diag_vector(e: PackedStringArray, path: String, diag: Dictionary, key: String, value: PackedFloat64Array) -> void:
	if diag.has(key) and not _vector_agrees(diag[key], value):
		e.append("%s.%s: recorded %s disagrees with the recomputed %s" % [path, key, diag[key], value])


# --- numerics ----------------------------------------------------------------------------------------

## Electrical static torque balance; nonnegative root of k_Q*w^2 + Kt/(Kv*R)*w - Kt*(u*V/R - I0) = 0.
static func _electric_speed(u: float, v: float, kv: float, resistance: float, no_load: float, k_q: float) -> float:
	var kt := 1.0 / kv
	var b := kt / (kv * resistance)
	var c := kt * (u * v / resistance - no_load)
	if c <= 0.0:
		return 0.0
	return (-b + sqrt(b * b + 4.0 * k_q * c)) / (2.0 * k_q)


## Solve the 4x4 system a x = rhs by Gaussian elimination with partial pivoting (rows: Array of 4 Arrays).
static func solve4(a: Array, rhs: PackedFloat64Array) -> PackedFloat64Array:
	var m: Array = []
	for row in 4:
		var line := PackedFloat64Array()
		for col in 4:
			line.append(float(a[row][col]))
		line.append(rhs[row])
		m.append(line)
	for col in 4:
		var p := col
		for row in range(col + 1, 4):
			if absf(m[row][col]) > absf(m[p][col]):
				p = row
		var swap: PackedFloat64Array = m[col]
		m[col] = m[p]
		m[p] = swap
		for row in range(col + 1, 4):
			var pivot_row: PackedFloat64Array = m[col]
			var target: PackedFloat64Array = m[row]
			var f: float = target[col] / pivot_row[col]
			for k in range(col, 5):
				target[k] -= f * pivot_row[k]
			m[row] = target
	var x := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	for row in range(3, -1, -1):
		var line: PackedFloat64Array = m[row]
		var s: float = line[4]
		for k in range(row + 1, 4):
			s -= line[k] * x[k]
		x[row] = s / line[row]
	return x


static func _determinant4(a: Array) -> float:
	var m: Array = []
	for row in 4:
		m.append(PackedFloat64Array(a[row]))
	var det := 1.0
	for col in 4:
		var p := col
		for row in range(col + 1, 4):
			if absf(m[row][col]) > absf(m[p][col]):
				p = row
		if m[p][col] == 0.0:
			return 0.0
		if p != col:
			var swap: PackedFloat64Array = m[col]
			m[col] = m[p]
			m[p] = swap
			det = -det
		var pivot_row: PackedFloat64Array = m[col]
		det *= pivot_row[col]
		for row in range(col + 1, 4):
			var target: PackedFloat64Array = m[row]
			var f: float = target[col] / pivot_row[col]
			for k in range(col, 4):
				target[k] -= f * pivot_row[k]
			m[row] = target
	return det


## Sylvester's criterion on [Jxx, Jyy, Jzz, Jxy, Jxz, Jyz].
static func _positive_definite(j: PackedFloat64Array) -> bool:
	var m1 := j[0]
	var m2 := j[0] * j[1] - j[3] * j[3]
	var m3 := j[0] * (j[1] * j[2] - j[5] * j[5]) - j[3] * (j[3] * j[2] - j[5] * j[4]) + j[4] * (j[3] * j[5] - j[1] * j[4])
	return m1 > 0.0 and m2 > 0.0 and m3 > 0.0


static func _agrees(a: float, b: float, scale: float, tolerance: float) -> bool:
	return absf(a - b) <= tolerance * maxf(maxf(absf(a), absf(b)), scale)


## Entry-wise agreement relative to the largest magnitude in either vector.
static func _vector_agrees(a: PackedFloat64Array, b: PackedFloat64Array) -> bool:
	if a.size() != b.size():
		return false
	var scale := 0.0
	for i in a.size():
		scale = maxf(scale, maxf(absf(a[i]), absf(b[i])))
	for i in a.size():
		if absf(a[i] - b[i]) > DIAGNOSTIC_TOLERANCE * scale:
			return false
	return true


static func _sq(x: float) -> float:
	return x * x


# --- field readers (every error carries its field path) --------------------------------------------

static func _join(path: String, key: String) -> String:
	return key if path.is_empty() else path + "." + key


static func _closed(e: PackedStringArray, path: String, node: Dictionary, allowed: Array) -> void:
	for key: Variant in node:
		if not allowed.has(key):
			e.append("%s: unknown key" % _join(path, str(key)))


static func _block(e: PackedStringArray, path: String, holder: Dictionary, key: String, allowed: Array) -> Dictionary:
	var node: Variant = holder.get(key)
	if typeof(node) != TYPE_DICTIONARY:
		e.append("%s: missing block or not an object" % _join(path, key))
		return {}
	_closed(e, _join(path, key), node, allowed)
	return node


static func _text(e: PackedStringArray, path: String, holder: Dictionary, key: String) -> String:
	var value: Variant = holder.get(key)
	if typeof(value) != TYPE_STRING or str(value).strip_edges().is_empty():
		e.append("%s: must be a nonempty string" % _join(path, key))
		return ""
	return value


## Bounded identifier: lowercase letters, digits and '-', 1..64 characters.
static func _ident(e: PackedStringArray, path: String, holder: Dictionary, key: String) -> String:
	var value := _text(e, path, holder, key)
	if value.is_empty():
		return value
	var ok := value.length() <= 64
	for ch in value:
		ok = ok and ((ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "-")
	if not ok:
		e.append("%s: '%s' is not a bounded identifier [a-z0-9-]{1,64}" % [_join(path, key), value])
	return value


static func _int(e: PackedStringArray, path: String, holder: Dictionary, key: String, lo: int, hi: int) -> int:
	var value: Variant = holder.get(key)
	if not holder.has(key):
		e.append("%s: missing" % _join(path, key))
		return 0
	if not _finite_number(value) or float(value) != floorf(float(value)) or float(value) < lo or float(value) > hi:
		e.append("%s: must be an integer in [%d, %d], got %s" % [_join(path, key), lo, hi, str(value)])
		return 0
	return int(value)


static func _finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(value))


## Quantity header: exactly {value, unit, kind, source}; returns the value or null after recording errors.
static func _quantity(e: PackedStringArray, path: String, holder: Dictionary, key: String, unit: String) -> Variant:
	var full := _join(path, key)
	var node: Variant = holder.get(key)
	if not holder.has(key):
		e.append("%s: missing" % full)
		return null
	if typeof(node) != TYPE_DICTIONARY:
		e.append("%s: must be a quantity {value, unit, kind, source}" % full)
		return null
	var ok := true
	_closed(e, full, node, ["value", "unit", "kind", "source"])
	for field: String in ["value", "unit", "kind", "source"]:
		if not node.has(field):
			e.append("%s.%s: missing" % [full, field])
			ok = false
	if not ok:
		return null
	if node.unit != unit:
		e.append("%s.unit: '%s' is not the required '%s'" % [full, str(node.unit), unit])
		ok = false
	if not KINDS.has(node.kind):
		e.append("%s.kind: '%s' is not one of %s" % [full, str(node.kind), KINDS])
		ok = false
	elif typeof(node.source) != TYPE_STRING or not str(node.source).begins_with(str(node.kind) + ": ") \
			or str(node.source).length() <= str(node.kind).length() + 2:
		e.append("%s.source: must begin with its provenance class '%s: ' and state the source" % [full, node.kind])
		ok = false
	return node.value if ok else null


static func _range_error(e: PackedStringArray, path: String, x: float, lo: float, hi: float, positive: bool) -> bool:
	if not is_finite(x):
		e.append("%s: value %s is not finite" % [path, x])
		return true
	if x < lo or x > hi or (positive and not (x > 0.0)):
		e.append("%s: value %s outside %s%s, %s]" % [path, x, "(" if positive and lo == 0.0 else "[", lo, hi])
		return true
	return false


static func _qf(e: PackedStringArray, path: String, holder: Dictionary, key: String, unit: String, lo: float, hi: float,
		positive := false) -> float:
	var value: Variant = _quantity(e, path, holder, key, unit)
	if value == null:
		return 0.0
	var full := _join(path, key) + ".value"
	if typeof(value) not in [TYPE_FLOAT, TYPE_INT]:
		e.append("%s: must be a number" % full)
		return 0.0
	if _range_error(e, full, float(value), lo, hi, positive):
		return 0.0
	return float(value)


static func _qi(e: PackedStringArray, path: String, holder: Dictionary, key: String, unit: String, lo: int, hi: int) -> int:
	var value: Variant = _quantity(e, path, holder, key, unit)
	if value == null:
		return 0
	var full := _join(path, key) + ".value"
	if not _finite_number(value) or float(value) != floorf(float(value)) or float(value) < lo or float(value) > hi:
		e.append("%s: must be an integer in [%d, %d], got %s" % [full, lo, hi, str(value)])
		return 0
	return int(value)


static func _qa(e: PackedStringArray, path: String, holder: Dictionary, key: String, unit: String, lo: float, hi: float,
		size: int) -> PackedFloat64Array:
	var value: Variant = _quantity(e, path, holder, key, unit)
	if value == null:
		return _zeros(size)
	return _numbers(e, _join(path, key) + ".value", value, size, lo, hi)


## List of fixed-width rows (points, tables).
static func _ql(e: PackedStringArray, path: String, holder: Dictionary, key: String, unit: String, lo: float, hi: float,
		width: int, min_count: int, max_count: int) -> Array:
	var out: Array = []
	var value: Variant = _quantity(e, path, holder, key, unit)
	if value == null:
		return out
	var full := _join(path, key) + ".value"
	if typeof(value) != TYPE_ARRAY or value.size() < min_count or value.size() > max_count:
		e.append("%s: must be an array of %d..%d rows" % [full, min_count, max_count])
		return out
	for i in value.size():
		out.append(_numbers(e, "%s[%d]" % [full, i], value[i], width, lo, hi))
	return out


static func _numbers(e: PackedStringArray, path: String, value: Variant, size: int, lo: float, hi: float) -> PackedFloat64Array:
	if typeof(value) != TYPE_ARRAY or value.size() != size:
		e.append("%s: must be an array of %d numbers" % [path, size])
		return _zeros(size)
	var out := PackedFloat64Array()
	for i in size:
		var x: Variant = value[i]
		if typeof(x) not in [TYPE_FLOAT, TYPE_INT]:
			e.append("%s[%d]: must be a number" % [path, i])
			return _zeros(size)
		if _range_error(e, "%s[%d]" % [path, i], float(x), lo, hi, false):
			return _zeros(size)
		out.append(float(x))
	return out


static func _zeros(size: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(size)
	return out


static func _is_hex(text: String) -> bool:
	for ch in text:
		if not ((ch >= "0" and ch <= "9") or (ch >= "a" and ch <= "f") or (ch >= "A" and ch <= "F")):
			return false
	return true
