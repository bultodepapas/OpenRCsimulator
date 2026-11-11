extends SceneTree
## AC-05/AC-06: Aircraft Creator definition, estimated packages, compiler and accepted candidate.
## Static and loader checks only; flight is in test_creator_flight.gd. Expected values are computed
## outside the compiler (hand arithmetic, the donor record's documented closed forms).
## Run: godot --headless --path . --script res://tests/test_creator_compiler.gd

const Definition := preload("res://workshop/creator/definition.gd")
const Compiler := preload("res://workshop/creator/compiler.gd")
const Packages := preload("res://workshop/creator/packages.gd")
const AcceptedCandidate := preload("res://workshop/creator/accepted_candidate.gd")
const CreatorBytes := preload("res://workshop/creator/bytes.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const R := preload("res://workshop/creator/result.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const RecordLoader := preload("res://workshop/creator/record_loader.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const RB := preload("res://physics/rigid_body.gd")

const DONOR := "res://data/aircraft/synthetic_stik_electric_4s_battery.json"
## Package hardware as plain numbers, typed here independently of the package file: [mass, size].
const HARDWARE := {
	"item_motor_main": [0.2, [0.05, 0.042, 0.042]],
	"item_propeller_main": [0.066, [0.01, 0.305, 0.025]],
	"item_esc_main": [0.065, [0.07, 0.035, 0.015]],
	"item_battery_main": [0.35, [0.135, 0.043, 0.03]],
}

var checks := 0
var failures := 0


func _initialize() -> void:
	_template()
	_loader_seam()
	_mass_properties()
	_aerodynamics()
	_dihedral()
	_installation()
	_refusals()
	_ownership()
	_read_out()
	print("AC-05/06 creator compiler: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label, "  ", detail)


func _compile(definition: Dictionary) -> Dictionary:
	return Compiler.compile_candidate(definition)


func _record(candidate: RefCounted) -> Dictionary:
	return JSON.parse_string(candidate.raw_bytes().get_string_from_utf8())


## True when the result is a refusal that carries `code` at `field`.
func _refused(result: Dictionary, code: String, field: String) -> bool:
	if result.get("ok", true) or result.has("value"):
		return false
	for entry: Dictionary in result.diagnostics:
		if entry.code == code and entry.field == field and entry.severity == R.SEVERITY_ERROR and not str(entry.step).is_empty():
			return true
	return false


func _pairs(result: Dictionary) -> String:
	var out := PackedStringArray()
	for entry: Dictionary in result.get("diagnostics", []):
		out.append("%s@%s" % [entry.code, entry.field])
	return ", ".join(out)


func _close(a: float, b: float, tolerance: float) -> bool:
	return is_finite(a) and absf(a - b) <= tolerance


## Numbers read back from record bytes are compared with a tolerance: the engine's JSON number parser is
## not correctly rounded, so a parsed value can differ from the written one in the last digits.
func _near(a: Variant, b: Variant, tolerance: float = 1e-12) -> bool:
	if a is Array or a is PackedFloat64Array:
		if not (b is Array or b is PackedFloat64Array) or a.size() != b.size():
			return false
		for index: int in a.size():
			if not _near(a[index], b[index], tolerance):
				return false
		return true
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		return _close(float(a), float(b), tolerance)
	return typeof(a) == typeof(b) and a == b


func _template() -> void:
	var template: Dictionary = Definition.template()
	var checked: Dictionary = Definition.validate_complete(template)
	check("template validates", checked.ok, _pairs(checked))
	var first: Dictionary = _compile(template)
	check("template compiles", first.ok and AcceptedCandidate.is_accepted(first.get("value")), _pairs(first))
	if not first.ok:
		return
	var candidate: RefCounted = first.value
	var bytes: PackedByteArray = candidate.raw_bytes()
	var again: Dictionary = _compile(Definition.template())
	check("same definition, byte-identical record", again.ok and again.value.raw_bytes() == bytes
		and again.value.raw_sha256() == candidate.raw_sha256() and again.value.definition_sha256() == candidate.definition_sha256())
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	check("raw_sha256 is the SHA-256 of raw_bytes", candidate.raw_sha256() == hashing.finish().hex_encode())
	check("record ends with one LF and stays under the record limit", bytes[bytes.size() - 1] == 0x0A and bytes.size() <= Limits.RECORD_BYTES)
	check("identity", candidate.aircraft_id() == "user-aircraft-" + Definition.TEMPLATE_UUID
		and candidate.qualification() == "experimental" and CreatorBytes.is_sha256(candidate.definition_sha256()))
	var loaded: Dictionary = RecordLoader.load_bytes(bytes, "candidate")
	check("load_bytes accepts the emitted bytes", loaded.ok and loaded.input_identity.sha256 == candidate.raw_sha256()
		and loaded.input_identity.format == "openrc-aircraft v2", str(loaded.get("errors")))
	var record: Dictionary = _record(candidate)
	var derived: Dictionary = AircraftData.validate_and_derive(record)
	check("validate_and_derive has no errors", derived.ok and derived.errors.is_empty(), str(derived.errors))
	check("template raises no loader warning", derived.warnings.is_empty(), str(derived.warnings))
	check("the template compiles without diagnostics", first.diagnostics.is_empty())
	check("flight_data is the loader result for the bytes", candidate.flight_data().model == loaded.model
		and candidate.flight_data().input_identity == loaded.input_identity)
	check("physical identity is authored", loaded.ok and loaded.model.get("physical_identity", {}).get("status") == "authored"
		and loaded.model.propulsion.id == "propulsion_main")
	check("capabilities of the first slice", record.capabilities == {"controls": "conventional", "gear": "locked_up",
		"propulsion_layout": "single_tractor", "energy": "ocv_resistance", "damage": "terminal_hull", "flaps": "not_simulated"}
		and not record.has("landing_gear"))
	var problems := PackedStringArray()
	_evidence(record, "", problems)
	check("every quantity has a known kind and a source", problems.is_empty(), ", ".join(problems))
	var hull_ids: Array = record.crash_hull_ids
	var unique := {}
	for id: String in hull_ids:
		unique[id] = true
	check("hull points have stable semantic IDs", hull_ids.size() == record.crash_hull.value.size() and unique.size() == hull_ids.size()
		and hull_ids.size() <= Limits.HULL_POINTS and hull_ids.has("probe_spinner_tip") and hull_ids.has("probe_wing_left_tip_le"))
	# Number spelling and key type of the input do not change the identity; item display names are not physical bytes.
	var integers: Dictionary = Definition.template()
	integers["controls"]["aileron_deg"] = 20
	integers["controls"]["rudder_deg"] = 25
	var spelled: Dictionary = _compile(integers)
	check("integer and float inputs give the same identities", spelled.ok and spelled.value.raw_sha256() == candidate.raw_sha256()
		and spelled.value.definition_sha256() == candidate.definition_sha256())
	var from_literal: Dictionary = _compile(_string_names(Definition.template()))
	check("StringName keys of GDScript literals give the same identities", from_literal.ok
		and from_literal.value.raw_sha256() == candidate.raw_sha256()
		and from_literal.value.definition_sha256() == candidate.definition_sha256(), _pairs(from_literal))
	var renamed: Dictionary = Definition.template()
	renamed["inventory"][0]["name"] = "Main wing, repainted"
	var named: Dictionary = _compile(renamed)
	check("an item's display name is not part of the physical bytes", named.ok and named.value.raw_sha256() == candidate.raw_sha256()
		and named.value.definition_sha256() != candidate.definition_sha256())
	# A longer layout draws the loader's pitch-inertia plausibility note: reported as a warning, not hidden.
	var long_tail: Dictionary = Definition.template()
	long_tail["horizontal_tail"]["position"] = [0.75, 0.0, 0.0]
	long_tail["vertical_tail"]["position"] = [0.74, 0.0, 0.02]
	long_tail["fuselage"]["nose_x"] = -0.29
	long_tail["fuselage"]["tail_x"] = 0.94
	long_tail["equipment"]["hub_position"] = [-0.355, 0.0, -0.03]
	long_tail["equipment"]["battery_position"] = [-0.2, 0.0, -0.045]
	long_tail["equipment"]["esc_position"] = [-0.25, 0.0, -0.03]
	long_tail["inventory"] = Definition.propose_airframe_inventory(long_tail)
	var noted: Dictionary = _compile(long_tail)
	check("a loader note is a warning on an accepted candidate", noted.ok and noted.diagnostics.size() == 1
		and noted.diagnostics[0].severity == R.SEVERITY_WARNING and noted.diagnostics[0].code == R.BUILD_INVALID
		and noted.diagnostics[0].field == "inventory" and not R.has_errors(noted.diagnostics)
		and noted.value.summary().loader_warnings.size() == 1, _pairs(noted))
	var tapered: Dictionary = Definition.template()
	tapered["wing"] = {"span": 1.5, "root_chord": 0.35, "tip_chord": 0.25, "dihedral_deg": 5.0}
	var taper: Dictionary = _compile(tapered)
	check("straight taper compiles as a tapered planform", taper.ok and _record(taper.value).reference.planform == "tapered"
		and _near(_record(taper.value).reference.root_chord.value, 0.35) and _record(taper.value).reference.tip_chord.kind == "manual", _pairs(taper))


## The same tree with StringName keys, as a GDScript `{name = value}` literal carries them.
func _string_names(node: Variant) -> Variant:
	if node is Array:
		var items := []
		for item: Variant in node:
			items.append(_string_names(item))
		return items
	if node is Dictionary:
		var fields := {}
		for key: String in node:
			fields[StringName(key)] = _string_names(node[key])
		return fields
	return node


func _evidence(node: Variant, path: String, problems: PackedStringArray) -> void:
	if node is Array:
		for index: int in node.size():
			_evidence(node[index], "%s/%d" % [path, index], problems)
	elif node is Dictionary:
		if node.has("value"):
			if not AircraftData.KINDS.has(node.get("kind")) or str(node.get("source", "")).strip_edges().is_empty() \
					or typeof(node.get("unit")) != TYPE_STRING:
				problems.append(path)
			return
		for key: String in node:
			_evidence(node[key], path + "/" + key, problems)


func _loader_seam() -> void:
	for path: String in [DONOR, "res://data/aircraft/jensen_ugly_stik_60.json"]:
		var from_file: Dictionary = AircraftData.load_file(path)
		var from_bytes: Dictionary = RecordLoader.load_bytes(FileAccess.get_file_as_bytes(path), path)
		check("load_file and load_bytes agree on " + path.get_file(), from_file.ok and from_bytes.ok
			and from_file.input_identity == from_bytes.input_identity
			and var_to_bytes(from_file.model) == var_to_bytes(from_bytes.model)
			and from_file.get("wheel_profile_identity") == from_bytes.get("wheel_profile_identity")
			and from_file.warnings == from_bytes.warnings)
	var broken: Dictionary = RecordLoader.load_bytes("{".to_utf8_buffer(), "label")
	check("load_bytes names its label in a parse error", not broken.ok and broken.model.is_empty()
		and str(broken.errors[0]).begins_with("label: JSON error at line") and not broken.has("input_identity"))
	var listed: Dictionary = RecordLoader.load_bytes("[]".to_utf8_buffer(), "label")
	check("load_bytes refuses a non-object", not listed.ok and listed.errors[0] == "label: top level must be an object")
	check("load_bytes refuses no bytes", not RecordLoader.load_bytes(PackedByteArray(), "label").ok)


## Three asymmetric boxes plus the package hardware. Expected values: mass, CG and the six inertia
## entries computed by hand (box inertia m·(a² + b²)/12 plus parallel axis, body FRD about the CG).
func _mass_properties() -> void:
	var definition: Dictionary = Definition.template()
	definition["inventory"] = [
		{"id": "item_box_a", "name": "Box A", "mass": 0.9, "position": [0.12, 0.02, 0.01], "size": [0.3, 1.4, 0.04], "kind": "measured"},
		{"id": "item_box_b", "name": "Box B", "mass": 0.45, "position": [0.2, -0.01, -0.04], "size": [1.0, 0.1, 0.12], "kind": "manual"},
		{"id": "item_box_c", "name": "Box C", "mass": 0.12, "position": [0.75, 0.03, 0.06], "size": [0.2, 0.5, 0.15], "kind": "estimated"},
	]
	var result: Dictionary = _compile(definition)
	check("box inventory compiles", result.ok, _pairs(result))
	if not result.ok:
		return
	var model: Dictionary = result.value.flight_data().model
	var expected_cg := [0.05754765225476523, 0.007949790794979079, -0.012775453277545326]
	var expected_inertia := [0.1536965474546723, 0.18128389649291027, 0.3292946703597164,
		0.0029759351464435143, -0.010385359483960948, 0.0007944602510460251]
	check("known total mass", _close(model.mass_kg, 2.151, 1e-12), str(model.mass_kg))
	check("known centre of mass", _near(model.cg_le, expected_cg), str(model.cg_le))
	check("known inertia tensor, all six entries", _near(model.inertia, expected_inertia), str(model.inertia))
	var summary: Dictionary = result.value.summary()
	check("summary reports the loader's mass properties", summary.mass_kg == model.mass_kg
		and summary.cg_m == Array(model.cg_le) and summary.inertia_kg_m2 == Array(model.inertia))
	check("the live read-out agrees with the loader", _near(Compiler.summarize(definition).mass_kg, model.mass_kg)
		and _near(Compiler.summarize(definition).cg_m, model.cg_le))
	var record: Dictionary = _record(result.value)
	check("plan_cg is the inventory centre of mass", _near(record.balance.plan_cg.value, model.cg_le))
	# Power-package hardware exactly once, with the package masses.
	var player_mass := 0.9 + 0.45 + 0.12
	var hardware_mass := 0.0
	var seen := {}
	var kinds := {}
	for item: Dictionary in record.inventory:
		seen[item.id] = int(seen.get(item.id, 0)) + 1
		kinds[item.id] = item.mass.kind
		if HARDWARE.has(item.id):
			hardware_mass += float(item.mass.value)
			check(item.id + " carries the package mass and size", _near(item.mass.value, HARDWARE[item.id][0])
				and _near(item.size.value, HARDWARE[item.id][1]) and item.mass.kind == "estimated")
	var once: bool = record.inventory.size() == 7
	for id: String in ["item_box_a", "item_box_b", "item_box_c", "item_motor_main", "item_propeller_main", "item_esc_main", "item_battery_main"]:
		once = once and seen.get(id, 0) == 1
	check("every item, player and package, appears exactly once", once, str(seen))
	check("package mass is counted once", _close(model.mass_kg - player_mass, 0.681, 1e-12) and _close(hardware_mass, 0.681, 1e-12))
	check("items keep their own evidence kind", kinds["item_box_a"] == "measured" and kinds["item_box_b"] == "manual"
		and kinds["item_box_c"] == "estimated")
	check("battery item is the energy source", record.inventory[6].get("energy_source") == "lipo")


func _aerodynamics() -> void:
	# The donor record's documented closed forms, fed with the donor's own geometry and slopes.
	var free_slope := 1.75 / (1.0 - 0.457)
	var area_ratio := 0.0956 / 0.464515
	var arm := (0.8409 - 0.1209) / 0.3048
	check("closed-form CLq reproduces the donor's 3.13", _close(Packages.tail_lift_rate(free_slope, area_ratio, arm), 3.13, 0.005))
	check("closed-form Cmq reproduces the donor's -7.40", _close(Packages.tail_pitch_damping(free_slope, area_ratio, arm), -7.40, 0.005))
	check("closed-form Cnr reproduces the donor's -0.1324",
		_close(Packages.yaw_damping((0.8609 - 0.1209) / 1.524, 0.1214237421962675, 0.0434), -0.1324, 0.00005))
	check("Helmbold slope of an AR 5 wing", _close(Packages.helmbold(5.0), 10.0 * PI / (2.0 + sqrt(29.0)), 1e-12)
		and _close(Packages.helmbold(5.0), 4.254, 0.001))
	check("tail free slope reproduces the donor's 3.17", _close(0.9 * Packages.helmbold(3.27), 3.17, 0.005))
	check("downwash factor reproduces the donor's vortex-lattice 0.457",
		_close(Packages.downwash_gradient(Packages.helmbold(5.0), 5.0, 0.844), 0.457, 0.0005))
	check("rectangular wing keeps the reference roll damping", Packages.roll_damping_taper(1.0) == 1.0
		and Packages.roll_damping_taper(0.6) < 1.0)

	var result: Dictionary = _compile(Definition.template())
	if not result.ok:
		check("template compiles for the aerodynamic checks", false, _pairs(result))
		return
	var record: Dictionary = _record(result.value)
	var c: Dictionary = record.aero.coefficients
	var fin: Dictionary = record.aero.surfaces.vertical
	var tail: Dictionary = record.aero.surfaces.horizontal
	var area: float = record.reference.wing_area.value
	var span: float = record.reference.wing_span.value
	var chord: float = record.reference.mean_chord.value
	var arp: Array = record.reference.aero_reference_point.value
	check("reference geometry from the player's wing", _near(area, 0.45) and _near(span, 1.5) and _near(chord, 0.3) and _near(arp, [0.075, 0.0, 0.0])
		and record.reference.planform == "rectangular" and record.reference.wing_span.kind == "manual"
		and record.reference.wing_area.kind == "derived")
	# The four fin relations the loader enforces, recomputed here from the emitted fin data.
	var fin_force: float = fin.lift_slope.value * fin.area.value / area
	var fin_arm: float = fin.position.value[0] - arp[0]
	var fin_height: float = fin.position.value[2] - arp[2]
	check("CYdr = a_v·S_v/S·tau", _close(c.CYdr.value, fin_force * fin.control_effectiveness.value, 1e-8))
	check("Cndr = -CYdr·l/b", _close(c.Cndr.value, -fin_force * fin.control_effectiveness.value * fin_arm / span, 1e-8))
	check("Cldr = CYdr·(z_v - z_ARP)/b", _close(c.Cldr.value, fin_force * fin.control_effectiveness.value * fin_height / span, 1e-8))
	check("Cnb = a_v·S_v/S·l/b", _close(c.Cnb.value, fin_force * fin_arm / span, 1e-8) and fin_arm > 0.0)
	check("CYb and Clb carry fin plus the declared body terms",
		_close(c.CYb.value, -fin_force + record.aero.surfaces.body_cy_beta.value, 1e-8)
		and _close(c.Clb.value, -fin_force * fin_height / span + record.aero.surfaces.wing_body_cl_beta.value, 1e-8))
	# Pitch set: one tail, used consistently by lift, static stability, damping and elevator.
	var tail_arm: float = (tail.position.value[0] - arp[0]) / chord
	var tail_ratio: float = tail.area.value / area
	var keep: float = 1.0 - tail.downwash_gradient.value
	var wing_slope := 10.0 * PI / (2.0 + sqrt(29.0))
	check("tail geometry from the player's tail", _near(tail.area.value, 0.56 * 0.17)
		and _near(tail.position.value, [0.7 + 0.25 * 0.17, 0.0, 0.0]) and _near(fin.area.value, 0.22 * 0.2)
		and _near(fin.position.value, [0.69 + 0.25 * 0.2, 0.0, 0.02 + 0.11]))
	check("CLa = a_w + a_h·S_h/S", _close(c.CLa.value, wing_slope + tail.lift_slope.value * tail_ratio, 1e-11))
	check("Cma = -a_h·(S_h/S)·(l_h/c)", _close(c.Cma.value, -tail.lift_slope.value * tail_ratio * tail_arm, 1e-11))
	check("Cmq and CLq use the free tail slope", _close(c.CLq.value, 2.0 * tail.lift_slope.value / keep * tail_ratio * tail_arm, 1e-10)
		and _close(c.Cmq.value, -c.CLq.value * tail_arm, 1e-10))
	check("elevator: Cmde = -CLde·l_h/c and control_effectiveness = Cmde/Cma", _close(c.Cmde.value, -c.CLde.value * tail_arm, 1e-11)
		and _close(tail.control_effectiveness.value, c.Cmde.value / c.Cma.value, 1e-11))
	check("Cnr = -2·(l_v/b)·Cnb - CD0/3", _close(c.Cnr.value, -2.0 * fin_arm / span * c.Cnb.value - c.CD0.value / 3.0, 1e-11))
	check("Cm0 = section moment + Cma × tail incidence", _close(c.Cm0.value,
		record.aero.surfaces.wing_section_cm_ac.value + c.Cma.value * tail.incidence.value, 1e-11))
	check("aileron effectiveness follows the donor rule", _close(record.aero.surfaces.wing_aileron_effectiveness.value,
		absf(c.Clda_right.value) / (0.125 * c.CLa.value), 1e-11))
	check("derived values are labelled derived, borrowed values borrowed", c.CLa.kind == "derived" and c.Cmq.kind == "derived"
		and c.Clda_right.kind == "borrowed" and c.CD0.kind == "borrowed" and record.aero.envelope.CL_max.kind == "borrowed")
	var summary: Dictionary = result.value.summary()
	check("neutral point and static margin", _close(summary.neutral_point_x_m, arp[0] - c.Cma.value / c.CLa.value * chord, 1e-11)
		and _close(summary.static_margin, (summary.neutral_point_x_m - summary.cg_m[0]) / chord, 1e-11)
		and summary.static_margin > 0.08 and summary.static_margin < 0.3)
	check("level speed from weight and the package cruise lift", _close(record.start.level_speed.value,
		sqrt(2.0 * summary.mass_kg * 9.80665 / (1.225 * area * 0.44)), 1e-10) and record.start.level_speed.kind == "derived")
	# The power package still carries the donor's electrical data and propeller tables.
	var donor: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DONOR))
	var propulsion: Dictionary = record.propulsion
	var same_tables := true
	for table: String in ["ct_table", "cp_table"]:
		var rows: Array = propulsion.propeller[table].value
		var donor_rows: Array = donor.propulsion.propeller[table].value
		same_tables = same_tables and rows.size() == donor_rows.size()
		for index: int in mini(rows.size(), donor_rows.size()):
			same_tables = same_tables and _near(rows[index], donor_rows[index])
	check("power package matches its cited donor", same_tables
		and _near(propulsion.motor.kv_rpm_per_volt.value, donor.propulsion.motor.kv_rpm_per_volt.value)
		and _near(propulsion.motor.resistance_ohm.value, donor.propulsion.motor.resistance_ohm.value)
		and _near(propulsion.motor.no_load_current_a.value, donor.propulsion.motor.no_load_current_a.value)
		and _near(propulsion.battery.capacity_ah.value, donor.propulsion.battery.capacity_ah.value)
		and _near(propulsion.battery.resistance_ohm.value, donor.propulsion.battery.resistance_ohm.value)
		and _near(propulsion.battery.ocv_points[0].voltage.value, donor.propulsion.battery.ocv_points[0].voltage.value)
		and _near(propulsion.battery.ocv_points[1].voltage.value, donor.propulsion.battery.ocv_points[1].voltage.value)
		and _near(propulsion.propeller.rotating_inertia.value, donor.propulsion.propeller.rotating_inertia.value)
		and _near(propulsion.propeller.diameter.value, donor.propulsion.propeller.diameter.value))
	check("battery charge is the player's", _near(propulsion.battery.initial_soc.value, 0.95) and propulsion.battery.initial_soc.kind == "manual")
	_regimes(result.value.flight_data().model)


## The emitted set describes one airplane in both runtime regimes: in attached flow the coefficient oracle
## and the local strip/tail law give the same lift and pitching moment about the CG, with and without
## elevator, and the same rudder yaw. Tolerances cover the tail's own drag, which only the local law has.
func _regimes(model: Dictionary) -> void:
	var speed := 12.7
	var pressure: float = 0.5 * 1.225 * speed * speed * float(model.reference.S)
	var worst_lift := 0.0
	var worst_pitch := 0.0
	var worst_yaw := 0.0
	for alpha_deg: float in [-3.0, 0.0, 2.0, 4.0, 6.0]:
		for deflection: Array in [[0.0, 0.0], [0.05, 0.0], [0.0, 0.05]]:
			var alpha := deg_to_rad(alpha_deg)
			var state := PackedFloat64Array()
			state.resize(RB.SIZE)
			state[RB.VEL] = speed * cos(alpha)
			state[RB.VEL + 2] = speed * sin(alpha)
			state[RB.ATT] = 1.0
			var air: Dictionary = Air.compute(state, PackedFloat64Array([0.0, 0.0, 0.0]))
			var surfaces := {elevator = deflection[0], aileron_right = 0.0, aileron_left = 0.0, rudder = deflection[1]}
			var oracle: PackedFloat64Array = Aero._global_loads(state, air, surfaces, model, 1.225)
			var local: PackedFloat64Array = Aero._local_loads(state, air, surfaces, model, 1.225)
			worst_lift = maxf(worst_lift, absf(oracle[2] - local[2]) / pressure)
			worst_pitch = maxf(worst_pitch, absf(oracle[4] - local[4]) / (pressure * float(model.reference.c)))
			worst_yaw = maxf(worst_yaw, absf(oracle[5] - local[5]) / (pressure * float(model.reference.b)))
	print("oracle against local law, attached flow: lift %.5f, pitch %.5f, yaw %.5f (coefficient differences)" % [worst_lift, worst_pitch, worst_yaw])
	check("oracle and local law agree on lift in attached flow", worst_lift < 0.001, str(worst_lift))
	check("oracle and local law agree on pitching moment in attached flow", worst_pitch < 0.002, str(worst_pitch))
	check("oracle and local law agree on rudder yaw", worst_yaw < 0.0002, str(worst_yaw))


## Wing dihedral (AC-12): the strip relation's known answers, its place in the record, the donor's own
## dihedral as the calibration point, the domain bound, and both runtime regimes seeing the same roll
## due to sideslip. Expected values are hand arithmetic from the documented relation.
func _dihedral() -> void:
	var slope := 10.0 * PI / (2.0 + sqrt(29.0)) # Helmbold, AR 5
	var five := deg_to_rad(5.0)
	# Strip theory, rectangular wing: -a_w·Γ/4 = -4.25392·0.0872665/4 = -0.092806; tapered 0.6: ×(2.2/1.6)/1.5.
	check("strip relation, rectangular wing: -a·Γ/4", _close(Packages.dihedral_effect(slope, 1.0, five, 1.0), -slope * five / 4.0, 1e-15)
		and _close(Packages.dihedral_effect(slope, 1.0, five, 1.0), -0.092806, 0.000001))
	check("strip relation, taper 0.6: -a·Γ·(1 + 2λ)/(6·(1 + λ))", _close(Packages.dihedral_effect(slope, 0.6, five, 1.0),
		-slope * five * 2.2 / 9.6, 1e-15) and _close(Packages.dihedral_effect(slope, 0.6, five, 1.0), -0.085072, 0.000001))
	check("the relation is linear in the angle and in the factor", _close(Packages.dihedral_effect(slope, 1.0, 2.0 * five, 0.5),
		Packages.dihedral_effect(slope, 1.0, five, 1.0), 1e-15) and Packages.dihedral_effect(slope, 1.0, 0.0, 1.0) == 0.0)
	var package: Dictionary = Packages.airframe("conventional-trainer-estimated-v1").value
	var factor: float = package.wing.dihedral_factor.value
	check("the package factor reproduces the donor's lifting-line slope of -0.01335 per degree (D10-R5)",
		_close(Packages.dihedral_effect(slope, 1.0, deg_to_rad(1.0), factor), -0.01335, 0.000005)
		and factor > 0.6 and factor < 0.8 and package.wing.dihedral_factor.kind == "derived"
		and _close(float(package.donor.dihedral_deg), 2.86, 1e-12))

	var by_angle := {}
	for angle: float in [0.0, 2.86, 5.0, 8.0]:
		var definition: Dictionary = Definition.template()
		definition["wing"]["dihedral_deg"] = angle
		var result: Dictionary = _compile(definition)
		check("dihedral %s deg compiles" % angle, result.ok, _pairs(result))
		if not result.ok:
			return
		by_angle[angle] = result.value
	check("the template carries 5 degrees of dihedral", Definition.template()["wing"]["dihedral_deg"] == 5.0
		and by_angle[5.0].raw_sha256() == _compile(Definition.template()).value.raw_sha256())
	var records := {}
	for angle: float in by_angle:
		records[angle] = _record(by_angle[angle])
	# The fin's own share, recomputed from the emitted fin data; it does not depend on the dihedral.
	var donor_record: Dictionary = records[2.86]
	var fin: Dictionary = donor_record.aero.surfaces.vertical
	var fin_share: float = -fin.lift_slope.value * fin.area.value / donor_record.reference.wing_area.value \
		* (fin.position.value[2] - donor_record.reference.aero_reference_point.value[2]) / donor_record.reference.wing_span.value
	check("the donor's own dihedral reproduces the borrowed wing-body term and the previous Clb",
		_close(donor_record.aero.surfaces.wing_body_cl_beta.value, -0.0537, 1e-12)
		and _close(donor_record.aero.coefficients.Clb.value, fin_share - 0.0537, 1e-12)
		and _close(donor_record.aero.coefficients.Clb.value, -0.074898, 0.000001), str(donor_record.aero.coefficients.Clb.value))
	# -0.0537 - 0.7192·1.0634808·(Γ - 2.86°) in radians: 0 deg -0.015521, 5 deg -0.082267, 8 deg -0.122315.
	var expected := {0.0: -0.015521, 5.0: -0.082267, 8.0: -0.122315}
	for angle: float in expected:
		var surfaces: Dictionary = records[angle].aero.surfaces
		check("wing-body term at %s deg: donor term moved by the relation" % angle,
			_close(surfaces.wing_body_cl_beta.value, expected[angle], 0.000002)
			and _close(surfaces.wing_body_cl_beta.value, -0.0537 + factor * slope / 4.0 * deg_to_rad(2.86 - angle), 1e-12)
			and _close(records[angle].aero.coefficients.Clb.value, fin_share + surfaces.wing_body_cl_beta.value, 1e-12)
			and surfaces.wing_body_cl_beta.kind == "derived", str(surfaces.wing_body_cl_beta.value))
	check("a flat wing keeps only the donor's interference share (-0.0155, D10-R5)",
		_close(records[0.0].aero.surfaces.wing_body_cl_beta.value, -0.0155, 0.00005))
	check("more dihedral, more negative Clb", records[0.0].aero.coefficients.Clb.value > records[2.86].aero.coefficients.Clb.value
		and records[2.86].aero.coefficients.Clb.value > records[5.0].aero.coefficients.Clb.value
		and records[5.0].aero.coefficients.Clb.value > records[8.0].aero.coefficients.Clb.value)
	# Only the wing-body roll term, its sum Clb and the tip height of the hull change with the angle.
	var same := true
	for name: String in records[0.0].aero.coefficients:
		if name != "Clb":
			same = same and records[0.0].aero.coefficients[name] == records[8.0].aero.coefficients[name]
	var flat_surfaces: Dictionary = records[0.0].aero.surfaces.duplicate(true)
	var steep_surfaces: Dictionary = records[8.0].aero.surfaces.duplicate(true)
	flat_surfaces.erase("wing_body_cl_beta")
	steep_surfaces.erase("wing_body_cl_beta")
	check("dihedral changes no other coefficient, surface, mass or reference value", same and flat_surfaces == steep_surfaces
		and records[0.0].reference == records[8.0].reference and records[0.0].inventory == records[8.0].inventory
		and records[0.0].aero.envelope == records[8.0].aero.envelope)
	var tips := {}
	for index: int in records[5.0].crash_hull_ids.size():
		tips[records[5.0].crash_hull_ids[index]] = [records[0.0].crash_hull.value[index], records[5.0].crash_hull.value[index]]
	check("the hull's wing tips rise by half span × tan(dihedral)", _close(tips["probe_wing_left_tip_le"][1][2], 0.75 * tan(five), 1e-12)
		and _close(tips["probe_wing_right_tip_te"][1][2], 0.065616, 0.000001) and tips["probe_wing_right_tip_te"][0][2] == 0.0
		and tips["probe_fin_top_le"][0] == tips["probe_fin_top_le"][1])

	# A taper and aspect-ratio change move the term through the wing slope and the planform factor.
	var tapered: Dictionary = Definition.template()
	tapered["wing"] = {"span": 1.5, "root_chord": 0.375, "tip_chord": 0.225, "dihedral_deg": 5.0}
	var taper: Dictionary = _compile(tapered)
	check("taper 0.6 at AR 5: the planform factor 2.2/9.6 replaces 1/4", taper.ok
		and _close(_record(taper.value).aero.surfaces.wing_body_cl_beta.value,
			-0.0537 - factor * slope * (five * 2.2 / 9.6 - deg_to_rad(2.86) / 4.0), 1e-12), _pairs(taper))

	# Evidence: the record has no field for the angle; the derived terms name it and who supplied it.
	var typed: String = records[5.0].aero.surfaces.wing_body_cl_beta.source
	check("the derived terms name the stated angle as player-entered", typed.contains("wing dihedral 5.0 deg")
		and typed.contains("wing/dihedral_deg (player-entered)") and str(records[5.0].aero.coefficients.Clb.source).contains("wing dihedral 5.0 deg"))
	var unconfirmed: Dictionary = Definition.template()
	unconfirmed["evidence"] = {"wing/dihedral_deg": "estimated"}
	var estimated: Dictionary = _compile(unconfirmed)
	check("an unconfirmed starting dihedral is named as an estimate", estimated.ok
		and str(_record(estimated.value).aero.surfaces.wing_body_cl_beta.source).contains("not confirmed by the player")
		and _record(estimated.value).aero.surfaces.wing_body_cl_beta.kind == "derived"
		and estimated.value.raw_sha256() != by_angle[5.0].raw_sha256(), _pairs(estimated))

	# Refusals: outside the package domain, outside the sanity range, missing, not a number.
	var cases := [[8.5, R.DOMAIN_REFUSED], [-0.5, R.DOMAIN_REFUSED], [15.5, R.FIELD_INVALID], [-5.5, R.FIELD_INVALID],
		["5", R.FIELD_INVALID], [NAN, R.FIELD_INVALID]]
	for case: Array in cases:
		var definition: Dictionary = Definition.template()
		definition["wing"]["dihedral_deg"] = case[0]
		var refused: Dictionary = _compile(definition)
		check("dihedral %s is refused with %s" % [str(case[0]), case[1]], _refused(refused, case[1], "wing/dihedral_deg"), _pairs(refused))
		if case[1] == R.DOMAIN_REFUSED:
			check("dihedral %s is a valid definition outside the domain" % str(case[0]), Definition.validate_complete(definition).ok)
	var missing: Dictionary = Definition.template()
	missing["wing"].erase("dihedral_deg")
	check("a definition without a dihedral is refused", _refused(_compile(missing), R.FIELD_INVALID, "wing/dihedral_deg"))
	check("the bounds themselves are admitted", _compile(_with_dihedral(0.0)).ok and _compile(_with_dihedral(8.0)).ok)
	var summary: Dictionary = Compiler.summarize(missing)
	check("without a dihedral the wing and mass read-outs remain and the mass proposal still works", summary.has("wing_area_m2")
		and summary.has("mass_kg") and not summary.has("static_margin") and Definition.propose_airframe_inventory(missing).size() == 9)
	_roll_regimes(by_angle[0.0].flight_data().model, by_angle[5.0].flight_data().model, records[5.0].aero.coefficients.Clb.value)


func _with_dihedral(angle: float) -> Dictionary:
	var definition: Dictionary = Definition.template()
	definition["wing"]["dihedral_deg"] = angle
	return definition


## Roll due to sideslip (per rad, about the CG, central difference over ±1 degree) in the coefficient
## oracle and in the local strip law: the declared wing-body couple must make them one airplane, in
## attached flow and where the local law alone carries the loads (alpha 12 and 16 degrees).
func _roll_regimes(flat: Dictionary, dihedral: Dictionary, declared_clb: float) -> void:
	var speed := 12.7
	var values := {}
	for entry: Array in [["flat", flat], ["dihedral", dihedral]]:
		var model: Dictionary = entry[1]
		var pressure: float = 0.5 * 1.225 * speed * speed * float(model.reference.S) * float(model.reference.b)
		for alpha_deg: float in [0.0, 4.0, 12.0, 16.0]:
			var moments := []
			for beta_deg: float in [1.0, -1.0]:
				var alpha := deg_to_rad(alpha_deg)
				var beta := deg_to_rad(beta_deg)
				var state := PackedFloat64Array()
				state.resize(RB.SIZE)
				state[RB.VEL] = speed * cos(alpha) * cos(beta)
				state[RB.VEL + 1] = speed * sin(beta)
				state[RB.VEL + 2] = speed * sin(alpha) * cos(beta)
				state[RB.ATT] = 1.0
				var air: Dictionary = Air.compute(state, PackedFloat64Array([0.0, 0.0, 0.0]))
				var surfaces := {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}
				moments.append([Aero._global_loads(state, air, surfaces, model, 1.225)[3], Aero._local_loads(state, air, surfaces, model, 1.225)[3]])
			var step := deg_to_rad(2.0)
			values["%s %d" % [entry[0], int(alpha_deg)]] = [(moments[0][0] - moments[1][0]) / (step * pressure),
				(moments[0][1] - moments[1][1]) / (step * pressure)]
	print("roll due to sideslip about the CG, oracle / local law: flat wing alpha 0 %.5f / %.5f, 4 %.5f / %.5f, 12 %.5f / %.5f, 16 %.5f / %.5f; 5 deg dihedral alpha 0 %.5f / %.5f, 4 %.5f / %.5f, 12 %.5f / %.5f, 16 %.5f / %.5f" % [
		values["flat 0"][0], values["flat 0"][1], values["flat 4"][0], values["flat 4"][1], values["flat 12"][0], values["flat 12"][1],
		values["flat 16"][0], values["flat 16"][1], values["dihedral 0"][0], values["dihedral 0"][1], values["dihedral 4"][0], values["dihedral 4"][1],
		values["dihedral 12"][0], values["dihedral 12"][1], values["dihedral 16"][0], values["dihedral 16"][1]])
	check("the oracle's roll due to sideslip is the declared Clb moved to the CG", absf(values["dihedral 0"][0] - declared_clb) < 0.02)
	for key: String in ["flat 0", "flat 4", "dihedral 0", "dihedral 4"]:
		check("oracle and local law agree on roll due to sideslip in attached flow, " + key,
			absf(values[key][0] - values[key][1]) < 0.003, str(values[key]))
	# What the dihedral adds is the same in both regimes, also past the wing's attached range.
	for alpha: int in [0, 4, 12, 16]:
		var oracle_gain: float = values["dihedral %d" % alpha][0] - values["flat %d" % alpha][0]
		var local_gain: float = values["dihedral %d" % alpha][1] - values["flat %d" % alpha][1]
		check("5 degrees of dihedral add the same roll due to sideslip in both regimes at alpha %d" % alpha,
			absf(oracle_gain - local_gain) < 0.004 and local_gain < -0.05, "%s / %s" % [oracle_gain, local_gain])
	check("past the attached range the local law keeps the dihedral airplane's roll stability",
		values["dihedral 12"][1] < 0.75 * values["dihedral 4"][0] and values["dihedral 16"][1] < 0.75 * values["dihedral 4"][0],
		"%s %s" % [values["dihedral 12"][1], values["dihedral 16"][1]])


func _installation() -> void:
	var base: Dictionary = _compile(Definition.template())
	if not base.ok:
		check("template compiles for the installation checks", false, _pairs(base))
		return
	var record: Dictionary = _record(base.value)
	var offset: Array = record.propulsion.propeller.thrust_line_offset.value
	var cg: Array = record.balance.plan_cg.value
	check("thrust line offset is hub minus CG; a tractor sits ahead", offset[0] < 0.0 and _near(offset[0], -0.34 - cg[0])
		and _near(offset[2], -0.03 - cg[2]))

	# Moving only the battery: balance and installation change, aerodynamics do not.
	var moved: Dictionary = Definition.template()
	moved["equipment"]["battery_position"] = [-0.15, 0.0, -0.045]
	var battery: Dictionary = _compile(moved)
	check("battery move compiles", battery.ok, _pairs(battery))
	if battery.ok:
		var other: Dictionary = _record(battery.value)
		var shift: float = 0.35 * 0.04 / base.value.summary().mass_kg
		check("battery move shifts CG and plan_cg", _close(other.balance.plan_cg.value[0] - cg[0], shift, 1e-12)
			and _close(battery.value.flight_data().model.cg_le[0] - cg[0], shift, 1e-12))
		check("battery move shifts the thrust line offset", _close(other.propulsion.propeller.thrust_line_offset.value[0] - offset[0], -shift, 1e-12))
		check("battery move keeps the aero reference point and every aero number", other.reference == record.reference
			and other.aero == record.aero and other.crash_hull == record.crash_hull and other.start == record.start)
		check("battery move keeps mass and changes the bytes", battery.value.summary().mass_kg == base.value.summary().mass_kg
			and battery.value.raw_sha256() != base.value.raw_sha256())

	# Moving the hub: thrust line and the motor and propeller items follow.
	var forward: Dictionary = Definition.template()
	forward["equipment"]["hub_position"] = [-0.33, 0.0, -0.03]
	var hub: Dictionary = _compile(forward)
	check("hub move compiles", hub.ok, _pairs(hub))
	if hub.ok:
		var other: Dictionary = _record(hub.value)
		var places := {}
		for item: Dictionary in other.inventory:
			places[item.id] = item.position.value
		check("propeller item sits at the hub, the motor a package distance behind", _near(places["item_propeller_main"], [-0.33, 0.0, -0.03])
			and _near(places["item_motor_main"], [-0.33 + 0.04, 0.0, -0.03]))
		check("hub move changes the thrust line offset", _near(other.propulsion.propeller.thrust_line_offset.value[0],
			-0.33 - other.balance.plan_cg.value[0]) and absf(other.propulsion.propeller.thrust_line_offset.value[0] - offset[0]) > 0.005)
		check("hub move keeps the aerodynamics", other.aero == record.aero and other.reference == record.reference)
	var angled: Dictionary = Definition.template()
	angled["equipment"]["thrust_angles_deg"] = [2.0, 1.5]
	var tilted: Dictionary = _compile(angled)
	check("thrust angles reach the propeller", tilted.ok and _near(_record(tilted.value).propulsion.propeller.thrust_angles.value, [2.0, 1.5])
		and tilted.value.flight_data().model.propulsion.axis[2] > 0.0, _pairs(tilted))


func _refusals() -> void:
	var cases := [
		["unknown top-level key", func(d: Dictionary) -> void: d["colour"] = "red", R.FIELD_INVALID, "colour"],
		["unknown nested key", func(d: Dictionary) -> void: d["wing"]["sweep_deg"] = 5.0, R.FIELD_INVALID, "wing/sweep_deg"],
		["missing field", func(d: Dictionary) -> void: d["wing"].erase("span"), R.FIELD_INVALID, "wing/span"],
		["missing section", func(d: Dictionary) -> void: d.erase("controls"), R.FIELD_INVALID, "controls"],
		["not a number", func(d: Dictionary) -> void: d["wing"]["span"] = NAN, R.FIELD_INVALID, "wing/span"],
		["infinite number", func(d: Dictionary) -> void: d["fuselage"]["width"] = INF, R.FIELD_INVALID, "fuselage/width"],
		["text for a number", func(d: Dictionary) -> void: d["controls"]["elevator_deg"] = "20", R.FIELD_INVALID, "controls/elevator_deg"],
		["boolean for a number", func(d: Dictionary) -> void: d["battery"]["initial_soc"] = true, R.FIELD_INVALID, "battery/initial_soc"],
		["empty battery", func(d: Dictionary) -> void: d["battery"]["initial_soc"] = 0.0, R.FIELD_INVALID, "battery/initial_soc"],
		["negative mass", func(d: Dictionary) -> void: d["inventory"][0]["mass"] = -0.5, R.FIELD_INVALID, "inventory/0/mass"],
		["zero mass", func(d: Dictionary) -> void: d["inventory"][2]["mass"] = 0.0, R.FIELD_INVALID, "inventory/2/mass"],
		["duplicate id", func(d: Dictionary) -> void: d["inventory"][1]["id"] = d["inventory"][0]["id"], R.FIELD_INVALID, "inventory/1/id"],
		["bad id grammar", func(d: Dictionary) -> void: d["inventory"][0]["id"] = "Item-1", R.FIELD_INVALID, "inventory/0/id"],
		["battery under a package ID", func(d: Dictionary) -> void: d["inventory"][3]["id"] = "item_battery_main", R.FIELD_INVALID, "inventory/3/id"],
		["motor under a package ID", func(d: Dictionary) -> void: d["inventory"].append({"id": "item_motor_main", "name": "Second motor",
			"mass": 0.2, "position": [-0.3, 0.0, 0.0], "size": [0.0, 0.0, 0.0], "kind": "measured"}), R.FIELD_INVALID, "inventory/9/id"],
		["compiler-owned ID prefix", func(d: Dictionary) -> void: d["inventory"][0]["id"] = "probe_wing_left_tip_le", R.FIELD_INVALID, "inventory/0/id"],
		["unknown item kind", func(d: Dictionary) -> void: d["inventory"][0]["kind"] = "derived", R.FIELD_INVALID, "inventory/0/kind"],
		["short position", func(d: Dictionary) -> void: d["inventory"][0]["position"] = [0.1, 0.0], R.FIELD_INVALID, "inventory/0/position"],
		["tip wider than root", func(d: Dictionary) -> void: d["wing"]["tip_chord"] = 0.4, R.FIELD_INVALID, "wing/tip_chord"],
		["tail off the centreline", func(d: Dictionary) -> void: d["horizontal_tail"]["position"] = [0.7, 0.1, 0.0], R.FIELD_INVALID, "horizontal_tail/position"],
		["nose behind the datum", func(d: Dictionary) -> void: d["fuselage"]["nose_x"] = 0.1, R.FIELD_INVALID, "fuselage/nose_x"],
		["wrong format", func(d: Dictionary) -> void: d["format"] = "openrc-creator-definition v2", R.FIELD_INVALID, "format"],
		["upper-case uuid", func(d: Dictionary) -> void: d["aircraft_uuid"] = "00000000-0000-4000-8000-00000000000A", R.FIELD_INVALID, "aircraft_uuid"],
		["unknown airframe package", func(d: Dictionary) -> void: d["airframe_package"] = "delta-wing-v1", R.DEPENDENCY_MISSING, "airframe_package"],
		["unknown power package", func(d: Dictionary) -> void: d["power_package"] = "glow-46-v1", R.DEPENDENCY_MISSING, "power_package"],
		["aft centre of mass", func(d: Dictionary) -> void: d["equipment"]["battery_position"] = [0.3, 0.0, -0.045], R.DOMAIN_REFUSED, "equipment/battery_position"],
		["nose-heavy centre of mass", func(d: Dictionary) -> void: d["inventory"].append({"id": "item_nose_weight", "name": "Lead",
			"mass": 0.6, "position": [-0.25, 0.0, -0.03], "size": [0.0, 0.0, 0.0], "kind": "measured"}), R.DOMAIN_REFUSED, "equipment/battery_position"],
		["slender wing", func(d: Dictionary) -> void: d["wing"] = {"span": 2.1, "root_chord": 0.2, "tip_chord": 0.2, "dihedral_deg": 5.0}, R.DOMAIN_REFUSED, "wing/span"],
		["strong taper", func(d: Dictionary) -> void: d["wing"]["tip_chord"] = 0.12, R.DOMAIN_REFUSED, "wing/tip_chord"],
		["small tail", func(d: Dictionary) -> void: d["horizontal_tail"]["chord"] = 0.1, R.DOMAIN_REFUSED, "horizontal_tail/position"],
		["tail ahead of the wing", func(d: Dictionary) -> void: d["horizontal_tail"]["position"] = [-0.2, 0.0, 0.0], R.DOMAIN_REFUSED, "horizontal_tail/position"],
		["overweight", func(d: Dictionary) -> void: d["inventory"].append({"id": "item_payload", "name": "Payload",
			"mass": 2.5, "position": [0.09, 0.0, 0.0], "size": [0.0, 0.0, 0.0], "kind": "manual"}), R.DOMAIN_REFUSED, "inventory"],
		["propeller inside the fuselage", func(d: Dictionary) -> void: d["equipment"]["hub_position"] = [-0.2, 0.0, -0.03], R.DOMAIN_REFUSED, "equipment/hub_position"],
		["propeller beside the fuselage", func(d: Dictionary) -> void: d["equipment"]["hub_position"] = [-0.34, 0.2, -0.03], R.DOMAIN_REFUSED, "equipment/hub_position"],
	]
	for case: Array in cases:
		var definition: Dictionary = Definition.template()
		(case[1] as Callable).call(definition)
		var result: Dictionary = _compile(definition)
		check("refused: " + str(case[0]), _refused(result, case[2], case[3]), _pairs(result))
		if case[2] == R.DOMAIN_REFUSED:
			check("a domain refusal is a valid definition: " + str(case[0]), Definition.validate_complete(definition).ok)

	# Inventory count: the power package's four items share the physical limit.
	var room: int = Limits.INVENTORY_ITEMS - HARDWARE.size()
	for count: int in [room - 1, room, room + 1]:
		var definition: Dictionary = Definition.template()
		while definition["inventory"].size() < count:
			definition["inventory"].append({"id": "item_small_%d" % definition["inventory"].size(), "name": "Small part",
				"mass": 0.001, "position": [0.09, 0.0, 0.0], "size": [0.0, 0.0, 0.0], "kind": "estimated"})
		var checked: Dictionary = Definition.validate_complete(definition)
		if count <= room:
			check("inventory of %d items is accepted" % count, checked.ok, _pairs(checked))
		else:
			check("inventory of %d items is refused" % count, _refused(checked, R.FIELD_INVALID, "inventory")
				and _refused(_compile(definition), R.FIELD_INVALID, "inventory"), _pairs(checked))
	var full: Dictionary = Definition.template()
	while full["inventory"].size() < room:
		full["inventory"].append({"id": "item_small_%d" % full["inventory"].size(), "name": "Small part",
			"mass": 0.001, "position": [0.09, 0.0, 0.0], "size": [0.0, 0.0, 0.0], "kind": "estimated"})
	var largest: Dictionary = _compile(full)
	check("a full inventory compiles to the physical limit", largest.ok
		and _record(largest.value).inventory.size() == Limits.INVENTORY_ITEMS, _pairs(largest))

	# Several problems are all reported, each at its own field.
	var many: Dictionary = Definition.template()
	many["wing"]["span"] = -1.0
	many["controls"]["rudder_deg"] = 90.0
	many["inventory"][0]["mass"] = NAN
	var reported: Dictionary = Definition.validate_complete(many)
	check("every problem is reported at its field", _refused(reported, R.FIELD_INVALID, "wing/span")
		and _refused(reported, R.FIELD_INVALID, "controls/rudder_deg") and _refused(reported, R.FIELD_INVALID, "inventory/0/mass"), _pairs(reported))
	# Loader refusals come back as diagnostics with a mapped field.
	var mapped: Array = Compiler._loader_diagnostics(PackedStringArray([
		"inventory[2] item_x1.mass: 9 outside [0.001, 5] kg", "inventory[12] item_motor_main.mass: bad",
		"total mass 9.000 kg outside the plausible range", "aero.surfaces.vertical: tail must be aft of the aerodynamic reference",
		"something new"]), 9)
	check("loader refusals keep their text and get a field", mapped.size() == 5 and mapped[0].code == R.BUILD_INVALID
		and mapped[0].severity == R.SEVERITY_ERROR
		and mapped[0].field == "inventory/2" and mapped[1].field == "power_package" and mapped[2].field == "inventory"
		and mapped[3].field == "vertical_tail/position" and mapped[4].field == "" and mapped[4].arguments == ["something new"])


func _ownership() -> void:
	var result: Dictionary = _compile(Definition.template())
	if not result.ok:
		check("template compiles for the ownership checks", false, _pairs(result))
		return
	var candidate: RefCounted = result.value
	var sha: String = candidate.raw_sha256()
	var bytes: PackedByteArray = candidate.raw_bytes()
	bytes[0] = 0
	bytes.append(1)
	check("raw_bytes returns a copy", candidate.raw_bytes()[0] == 0x7B and CreatorBytes.sha256(candidate.raw_bytes()) == sha)
	var data: Dictionary = candidate.flight_data()
	var mass: float = data.model.mass_kg
	data.model.mass_kg = 99.0
	data.model.inertia[0] = -1.0
	data.model.aero.CLa = 0.0
	data.input_identity.sha256 = "tampered"
	data.erase("ok")
	var fresh: Dictionary = candidate.flight_data()
	check("flight_data returns a deep copy", fresh.ok and fresh.model.mass_kg == mass and fresh.model.inertia[0] > 0.0
		and fresh.model.aero.CLa > 0.0 and fresh.input_identity.sha256 == sha)
	var summary: Dictionary = candidate.summary()
	summary.cg_m[0] = 5.0
	summary.identities.raw_sha256 = "tampered"
	summary.erase("mass_kg")
	check("summary returns a deep copy", candidate.summary().cg_m[0] < 1.0 and candidate.summary().identities.raw_sha256 == sha
		and candidate.summary().has("mass_kg"))
	check("a compiled candidate is accepted", AcceptedCandidate.is_accepted(candidate))
	check("a dictionary with ok = true is not a candidate", not AcceptedCandidate.is_accepted({ok = true, value = candidate})
		and not AcceptedCandidate.is_accepted({"ok": true}) and not AcceptedCandidate.is_accepted(null)
		and not AcceptedCandidate.is_accepted(RefCounted.new()) and not AcceptedCandidate.is_accepted(result))
	var blank := AcceptedCandidate.new()
	check("an unsealed instance is empty and not accepted", not AcceptedCandidate.is_accepted(blank) and blank.raw_bytes().is_empty()
		and blank.flight_data().is_empty() and blank.aircraft_id() == "" and blank.qualification() == "")
	var forged := AcceptedCandidate.new()
	var other_bytes: PackedByteArray = candidate.raw_bytes()
	other_bytes.append(0x0A)
	check("sealing refuses bytes that do not match the loaded identity",
		not forged._seal(candidate.aircraft_id(), other_bytes, candidate.definition_sha256(), candidate.flight_data(), {})
		and not forged._seal("user-aircraft-other", candidate.raw_bytes(), candidate.definition_sha256(), candidate.flight_data(), {})
		and not forged._seal(candidate.aircraft_id(), candidate.raw_bytes(), candidate.definition_sha256(), {"ok": true}, {})
		and not AcceptedCandidate.is_accepted(forged))
	check("a sealed candidate cannot be sealed again", not candidate._seal(candidate.aircraft_id(), candidate.raw_bytes(),
		candidate.definition_sha256(), candidate.flight_data(), {}) and candidate.raw_sha256() == sha)


func _read_out() -> void:
	var template: Dictionary = Definition.template()
	var summary: Dictionary = Compiler.summarize(template)
	var keys := ["mass_kg", "cg_m", "wing_area_m2", "mean_chord_m", "aspect_ratio", "neutral_point_x_m", "static_margin",
		"wing_loading_kg_m2", "level_speed_mps", "stall_speed_mps", "tail_volume_h", "tail_volume_v", "static_thrust_n",
		"thrust_to_weight", "issues"]
	var complete := true
	for key: String in keys:
		complete = complete and summary.has(key)
	check("summarize reports every read-out for the template", complete and summary.issues.is_empty(), str(summary.keys()))
	check("template is about 1.5 m and 2 kg", _near(summary.wing_area_m2, 0.45) and _near(summary.aspect_ratio, 5.0)
		and summary.mass_kg > 1.8 and summary.mass_kg < 2.3 and _close(summary.wing_loading_kg_m2, summary.mass_kg / 0.45, 1e-12))
	check("stall speed below level speed", summary.stall_speed_mps < summary.level_speed_mps
		and _close(summary.stall_speed_mps, sqrt(2.0 * summary.mass_kg * 9.80665 / (1.225 * 0.45 * 1.1)), 1e-12))
	var result: Dictionary = _compile(template)
	if result.ok:
		var model: Dictionary = result.value.flight_data().model
		var accepted: Dictionary = result.value.summary()
		var same := true
		for key: String in keys:
			same = same and _near(accepted[key], summary[key])
		check("the candidate summary equals the live read-out", same)
		# Static thrust: the runtime's torque balance on the loader's own propulsion model.
		var point: Dictionary = Propulsion.steady_operating_point(1.0, 0.0, model.propulsion, 1.225)
		var thrust: float = Propulsion.thrust_torque(PackedFloat64Array([0.0, 0.0, 0.0]), point.rpm, model.propulsion, 1.225)[0]
		check("static thrust equals the loaded model's full-throttle thrust", point.ok and _close(summary.static_thrust_n, thrust, 1e-9)
			and _close(summary.thrust_to_weight, thrust / (model.mass_kg * 9.80665), 1e-12), "%s vs %s" % [summary.static_thrust_n, thrust])
		check("candidate summary adds inertia and identities", accepted.inertia_kg_m2.size() == 6
			and accepted.identities.aircraft_id == result.value.aircraft_id() and accepted.identities.raw_sha256 == result.value.raw_sha256()
			and accepted.identities.definition_sha256 == result.value.definition_sha256() and accepted.qualification == "experimental")

	# Incomplete and broken definitions: no exception, only what can be computed.
	var empty: Dictionary = Compiler.summarize({})
	check("an empty definition gives issues and no numbers", empty.size() == 1 and not empty.issues.is_empty())
	var wing_only: Dictionary = Compiler.summarize({"wing": {"span": 1.2, "root_chord": 0.25, "tip_chord": 0.25}})
	check("a wing alone gives the wing numbers", _close(wing_only.wing_area_m2, 0.3, 1e-15) and _close(wing_only.aspect_ratio, 4.8, 1e-12)
		and not wing_only.has("mass_kg") and not wing_only.has("static_margin"))
	var no_inventory: Dictionary = Definition.template()
	no_inventory.erase("inventory")
	var partial: Dictionary = Compiler.summarize(no_inventory)
	check("without an inventory the aerodynamic read-outs remain", partial.has("neutral_point_x_m") and partial.has("static_thrust_n")
		and not partial.has("mass_kg") and not partial.has("thrust_to_weight") and not partial.issues.is_empty())
	var garbage: Dictionary = Compiler.summarize({"wing": "big", "inventory": [1, "x", null], "equipment": [], "battery": {"initial_soc": "full"},
		"horizontal_tail": {"span": NAN}, "airframe_package": 7, "power_package": null, "fuselage": 3})
	check("wrong types are tolerated", garbage.has("issues") and not garbage.has("mass_kg") and not garbage.has("wing_area_m2"))
	var aft: Dictionary = Definition.template()
	aft["equipment"]["battery_position"] = [0.3, 0.0, -0.045]
	var out_of_domain: Dictionary = Compiler.summarize(aft)
	var flagged := false
	for issue: Dictionary in out_of_domain.issues:
		flagged = flagged or (issue.code == R.DOMAIN_REFUSED and issue.field == "equipment/battery_position")
	check("an out-of-domain definition still reports its numbers and the reason", flagged and out_of_domain.static_margin < 0.08
		and out_of_domain.has("mass_kg"))

	# Airframe mass proposal: estimated items from the geometry; measured items are left alone.
	var proposed: Array = Definition.propose_airframe_inventory(template)
	var estimated := true
	for item: Dictionary in proposed:
		estimated = estimated and item["kind"] == "estimated" and Packages.AIRFRAME_ITEM_IDS.has(item["id"])
	check("the proposal is nine estimated airframe items", proposed.size() == 9 and estimated and proposed == template["inventory"])
	check("the wing item follows the areal density", _near(proposed[0]["mass"], 0.45 * 1.12) and proposed[0]["size"][1] == 1.5)
	var weighed: Dictionary = Definition.template()
	weighed["inventory"][0] = {"id": "item_wing_airframe", "name": "Wing, weighed", "mass": 0.61, "position": [0.13, 0.0, 0.0],
		"size": [0.3, 1.5, 0.036], "kind": "measured"}
	weighed["inventory"][1]["mass"] = 9.0
	weighed["inventory"].append({"id": "item_camera", "name": "Camera", "mass": 0.05, "position": [0.0, 0.0, 0.0], "size": [0.0, 0.0, 0.0], "kind": "manual"})
	weighed["inventory"].remove_at(3)
	var merged: Array = Definition.propose_airframe_inventory(weighed)
	check("a measured item keeps its place and values", merged[0] == weighed["inventory"][0])
	check("an earlier estimate is refreshed in place", merged[1] == proposed[1])
	check("the player's own item stays and the missing proposal item is appended", merged.size() == 10 and merged[8]["id"] == "item_camera"
		and merged[9] == proposed[3])
	check("the proposal does not edit the definition", weighed["inventory"].size() == 9 and weighed["inventory"][1]["mass"] == 9.0)
	check("no geometry, no proposal", Definition.propose_airframe_inventory({}).is_empty()
		and Definition.propose_airframe_inventory({"inventory": [{"id": "item_x"}]}) == [{"id": "item_x"}])
