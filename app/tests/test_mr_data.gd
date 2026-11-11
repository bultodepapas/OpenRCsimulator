# DR-10/11/12/13 (DATA-01…08, PHY-03/09 screens): the strict `openrc-multirotor v1` loader on the generated
# experimental openrc-fpv5 x1 candidate. The file loads and prepares; mass, CG and the locked inertia recomputed
# here by an independent about-datum loop agree; locked and effective inertia are positive definite; the 5.1-inch
# prop clears on the 205.32 mm square X while a larger prop on the same hubs is refused; 5.0 and 5.1 inch give the
# FPV/03 §8 clearances; every malformed mutation is refused with a field-path error; prepare never mutates its
# input and returns exactly the declared shape; the lab-law variant prepares; the static maximum thrust is
# screened against the manufacturer 100 % row. Estimated data: none of this validates the aircraft physically.
extends SceneTree

const MD := preload("res://physics/multirotor_data.gd")
const DATA_PATH := "res://data/multirotors/openrc-fpv5-x1.json"
const DIAGONAL_M := 0.20532
const PROP_51_M := 0.12954
const PROP_50_M := 0.127
const ROW100_THRUST_N := 20.9470044 # 2136 g at standard gravity (FPV/03 §6)
const ROW100_VOLTS := 23.28

var _count := 0
var _failures := 0
var _doc: Dictionary = {}


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var loaded: Dictionary = MD.load_file(DATA_PATH)
	_check("DATA-01 generated candidate admits", loaded.ok, str(loaded.errors))
	_check("file identity is a SHA-256 of the bytes", str(loaded.sha256).length() == 64, str(loaded.sha256))
	if not loaded.ok:
		_finish()
		return
	_doc = loaded.data
	var before := JSON.stringify(_doc, "", true, true)
	var prep: Dictionary = MD.prepare(_doc, loaded.sha256)
	_check("DATA-01 generated candidate prepares", prep.ok, str(prep.errors))
	_check("prepare never mutates its input", JSON.stringify(_doc, "", true, true) == before)
	if not prep.ok:
		_finish()
		return
	var p: Dictionary = prep.prepared
	_shape(p, loaded.sha256)
	_mass_properties(p)
	_geometry(p)
	_mutations()
	_lab_law()
	_manufacturer_screen(p)
	_finish()


func _finish() -> void:
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


# --- prepared shape -----------------------------------------------------------------------------------

func _keys_are(label: String, node: Variant, expected: Array) -> void:
	var ok := typeof(node) == TYPE_DICTIONARY
	var got: Array = []
	if ok:
		for key: Variant in node:
			got.append(str(key))
	got.sort()
	var want := expected.duplicate()
	want.sort()
	_check("prepared %s has exactly the declared keys" % label, ok and got == want, str(got))


func _shape(p: Dictionary, sha: String) -> void:
	_keys_are("model", p, ["identity", "mass_kg", "inertia_kg_m2", "rotors", "rotor_law", "airframe", "powertrain",
		"battery", "controller", "contacts", "camera", "start", "derived"])
	_keys_are("identity", p.identity, ["schema", "family", "variant", "status", "data_sha256", "experimental"])
	_keys_are("rotor_law", p.rotor_law, ["thrust_coefficient_n_s2", "torque_coefficient_n_m_s2", "rotor_drag_n_s2_per_m",
		"max_speed_rad_s"])
	_keys_are("airframe", p.airframe, ["drag_areas_m2"])
	_keys_are("powertrain", p.powertrain, ["law", "kv_rad_s_per_v", "resistance_ohm", "no_load_current_a", "braking",
		"idle_command", "max_command"])
	_keys_are("battery", p.battery, ["cells", "capacity_ah", "ocv_points", "resistance_ohm", "auxiliary_current_a",
		"initial_soc"])
	_keys_are("controller", p.controller, ["sample_hz", "kp", "ki", "kd", "i_max", "kaw", "tau_limit", "gyro_lpf_hz",
		"dterm_lpf_hz", "kff", "setpoint_lpf_hz", "angle_max_tilt_rad", "angle_gain_per_s", "angle_rate_limit_rad_s", "arm_low_throttle",
		"allocator_weights", "throttle_rate_per_s"])
	_keys_are("contacts", p.contacts, ["feet_frd", "stiffness_n_per_m", "damping_n_s_per_m", "friction", "hull_frd",
		"crash_speed_mps", "rotor_strike_speed_rad_s"])
	_keys_are("camera", p.camera, ["mount_frd", "tilt_deg", "hfov_deg"])
	_keys_are("start", p.start, ["rest_height_m"])
	_keys_are("derived", p.derived, ["hover_speed_rad_s", "hover_thrust_per_rotor_n", "static_max_thrust_per_rotor_n",
		"thrust_to_weight", "min_prop_clearance_m", "effective_yaw_inertia_kg_m2", "kappa_m"])
	var ids := []
	var rotors_ok: bool = p.rotors.size() == 4
	for rotor: Dictionary in p.rotors:
		var keys: Array = []
		for key: Variant in rotor:
			keys.append(str(key))
		keys.sort()
		rotors_ok = rotors_ok and keys == ["diameter_m", "hub_frd", "id", "inertia_kg_m2", "spin"] \
			and typeof(rotor.id) == TYPE_INT and typeof(rotor.hub_frd) == TYPE_PACKED_FLOAT64_ARRAY and rotor.hub_frd.size() == 3
		ids.append(rotor.id)
	_check("prepared rotors are four {id, hub_frd, spin, diameter_m, inertia_kg_m2} ordered 1..4", rotors_ok and ids == [1, 2, 3, 4], str(ids))
	_check("prepared identity is the experimental openrc-fpv5 x1 variant", p.identity.schema == MD.FORMAT
		and p.identity.family == "openrc-fpv5" and p.identity.variant == "openrc-fpv5-f50-2150-f5146-6s-x1"
		and p.identity.status == "experimental-estimates" and p.identity.experimental == true and p.identity.data_sha256 == sha,
		str(p.identity))
	var typed: bool = typeof(p.inertia_kg_m2) == TYPE_PACKED_FLOAT64_ARRAY and p.inertia_kg_m2.size() == 6 \
		and typeof(p.battery.cells) == TYPE_INT and typeof(p.controller.sample_hz) == TYPE_INT and p.controller.sample_hz == 240 \
		and typeof(p.battery.ocv_points) == TYPE_PACKED_FLOAT64_ARRAY and p.battery.ocv_points.size() == 24 \
		and p.battery.ocv_points[0] == 0.0 and p.battery.ocv_points[22] == 1.0 \
		and typeof(p.controller.allocator_weights) == TYPE_PACKED_FLOAT64_ARRAY and p.controller.allocator_weights.size() == 4 \
		and p.contacts.feet_frd.size() == 4 and p.contacts.hull_frd.size() == 5
	_check("prepared value types are plain float64/int arrays and scalars", typed)
	_check("prepared Angle limits are converted to radians", is_equal_approx(p.controller.angle_max_tilt_rad, deg_to_rad(55.0))
		and is_equal_approx(p.controller.angle_rate_limit_rad_s, deg_to_rad(400.0)))
	print("     kappa %s m, hover %s rad/s at %s N per rotor (most loaded), static max %s N per rotor, T/W %s, clearance %s m" % [
		p.derived.kappa_m, p.derived.hover_speed_rad_s, p.derived.hover_thrust_per_rotor_n,
		p.derived.static_max_thrust_per_rotor_n, p.derived.thrust_to_weight, p.derived.min_prop_clearance_m])


# --- DATA-05: independent mass, CG and inertia ----------------------------------------------------------

func _relative_close(a: PackedFloat64Array, b: PackedFloat64Array, tolerance: float) -> bool:
	var scale := 0.0
	for i in a.size():
		scale = maxf(scale, maxf(absf(a[i]), absf(b[i])))
	for i in a.size():
		if absf(a[i] - b[i]) > tolerance * scale:
			return false
	return a.size() == b.size()


func _leading_minors_positive(j: PackedFloat64Array) -> bool:
	var a := j[0]
	var b := j[1]
	var c := j[2]
	var xy := j[3]
	var xz := j[4]
	var yz := j[5]
	var det3 := a * b * c + 2.0 * xy * yz * xz - a * yz * yz - b * xz * xz - c * xy * xy
	return a > 0.0 and a * b - xy * xy > 0.0 and det3 > 0.0


func _mass_properties(p: Dictionary) -> void:
	# About the datum first, then one parallel-axis shift to the CG (the loader sums about the CG directly).
	var mass := 0.0
	var first := PackedFloat64Array([0.0, 0.0, 0.0])
	var about_datum := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var rotor_positions := {}
	for c: Dictionary in _doc.mass_inventory.components:
		var m: float = c.mass.value
		var r: Array = c.position.value
		var x: float = r[0]
		var y: float = r[1]
		var z: float = r[2]
		mass += m
		first[0] += m * x
		first[1] += m * y
		first[2] += m * z
		var own := PackedFloat64Array([0.0, 0.0, 0.0])
		if c.shape.type == "box":
			var s: Array = c.shape.size.value
			own = PackedFloat64Array([m / 12.0 * (s[1] * s[1] + s[2] * s[2]), m / 12.0 * (s[0] * s[0] + s[2] * s[2]),
				m / 12.0 * (s[0] * s[0] + s[1] * s[1])])
		elif c.shape.type == "axisymmetric_z":
			own = PackedFloat64Array([c.shape.transverse_inertia.value, c.shape.transverse_inertia.value, c.shape.axial_inertia.value])
		about_datum[0] += own[0] + m * (y * y + z * z)
		about_datum[1] += own[1] + m * (x * x + z * z)
		about_datum[2] += own[2] + m * (x * x + y * y)
		about_datum[3] -= m * x * y
		about_datum[4] -= m * x * z
		about_datum[5] -= m * y * z
		if c.has("rotor_id"):
			rotor_positions[int(c.rotor_id)] = PackedFloat64Array([x, y, z])
	var cg := PackedFloat64Array([first[0] / mass, first[1] / mass, first[2] / mass])
	var about_cg := PackedFloat64Array([
		about_datum[0] - mass * (cg[1] * cg[1] + cg[2] * cg[2]),
		about_datum[1] - mass * (cg[0] * cg[0] + cg[2] * cg[2]),
		about_datum[2] - mass * (cg[0] * cg[0] + cg[1] * cg[1]),
		about_datum[3] + mass * cg[0] * cg[1],
		about_datum[4] + mass * cg[0] * cg[2],
		about_datum[5] + mass * cg[1] * cg[2],
	])
	_check("DATA-05 mass recomputed independently agrees to 1e-12", absf(mass - p.mass_kg) <= 1e-12 * mass, "%s kg" % mass)
	_check("DATA-05 locked inertia recomputed independently agrees to 1e-12", _relative_close(about_cg, p.inertia_kg_m2, 1e-12),
		"%s vs %s" % [about_cg, p.inertia_kg_m2])
	var cg_ok := rotor_positions.size() == 4
	for rotor: Dictionary in p.rotors:
		var pos: PackedFloat64Array = rotor_positions.get(rotor.id, PackedFloat64Array([NAN, NAN, NAN]))
		var implied := PackedFloat64Array([pos[0] - rotor.hub_frd[0], pos[1] - rotor.hub_frd[1], pos[2] - rotor.hub_frd[2]])
		cg_ok = cg_ok and _relative_close(implied, cg, 1e-12)
	_check("DATA-05 CG recomputed independently agrees with every prepared hub to 1e-12", cg_ok,
		"CG from datum %s mm" % [PackedFloat64Array([cg[0] * 1000.0, cg[1] * 1000.0, cg[2] * 1000.0])])
	_check("DATA-05 CG lies within a few millimetres of the hub-plane centre", sqrt(cg[0] * cg[0] + cg[1] * cg[1] + cg[2] * cg[2]) < 0.006)
	_check("DATA-06 locked inertia is positive definite", _leading_minors_positive(p.inertia_kg_m2))
	var effective: PackedFloat64Array = p.inertia_kg_m2.duplicate()
	for rotor: Dictionary in p.rotors:
		effective[2] -= rotor.inertia_kg_m2
	_check("DATA-06 effective inertia (rotor spin removed) is positive definite and matches the prepared yaw value",
		_leading_minors_positive(effective) and absf(effective[2] - p.derived.effective_yaw_inertia_kg_m2) <= 1e-15,
		"Jzz_eff %s kg m^2" % effective[2])


# --- DATA-07: clearance, 5.0 versus 5.1 inch --------------------------------------------------------------

func _hub_distance(p: Dictionary, a: int, b: int) -> float:
	var ha: PackedFloat64Array = p.rotors[a].hub_frd
	var hb: PackedFloat64Array = p.rotors[b].hub_frd
	return sqrt((ha[0] - hb[0]) ** 2 + (ha[1] - hb[1]) ** 2 + (ha[2] - hb[2]) ** 2)


func _with_diameter(diameter: float, clearance: Variant) -> Dictionary:
	var copy: Dictionary = _doc.duplicate(true)
	for rotor: Dictionary in copy.rotors:
		rotor.diameter.value = diameter
	if clearance != null:
		copy.provenance.derived_diagnostics.min_prop_clearance_m = clearance
	return copy


func _geometry(p: Dictionary) -> void:
	var diagonal := _hub_distance(p, 0, 3) # rear-right to front-left
	_check("hubs form the 205.32 mm square-X diagonal", absf(diagonal - DIAGONAL_M) < 1e-12 and absf(_hub_distance(p, 1, 2) - DIAGONAL_M) < 1e-12,
		"%s m" % diagonal)
	var adjacent := DIAGONAL_M / sqrt(2.0)
	var expected_51 := adjacent - PROP_51_M
	var expected_50 := adjacent - PROP_50_M
	_check("DATA-07 recorded prop is 5.1 in = 129.54 mm on every rotor", p.rotors.all(func(r: Dictionary) -> bool: return r.diameter_m == PROP_51_M))
	_check("DATA-07 5.1 in clearance is positive and equals L/sqrt(2) - D (FPV/03 §8)",
		p.derived.min_prop_clearance_m > 0.0 and absf(p.derived.min_prop_clearance_m - expected_51) < 1e-12,
		"%s mm" % (p.derived.min_prop_clearance_m * 1000.0))
	_check("FPV/03 §8 zero-gap square-X diagonals: 183.1972248698 mm (5.1 in), 179.6051224214 mm (5.0 in)",
		absf(sqrt(2.0) * PROP_51_M - 0.1831972248698) < 1e-12 and absf(sqrt(2.0) * PROP_50_M - 0.1796051224214) < 1e-12)
	var loaded_50: Dictionary = MD.load_document(_with_diameter(PROP_50_M, expected_50), "5.0 inch")
	var prep_50: Dictionary = MD.prepare(loaded_50.data, loaded_50.sha256) if loaded_50.ok else {ok = false, errors = loaded_50.errors}
	var clearance_50: float = prep_50.prepared.derived.min_prop_clearance_m if prep_50.ok else NAN
	_check("DATA-07 a 5.0 in (127 mm) prop gives the distinct FPV/03 §8 clearance", prep_50.ok
		and absf(clearance_50 - expected_50) < 1e-12 and absf((clearance_50 - p.derived.min_prop_clearance_m) - (PROP_51_M - PROP_50_M)) < 1e-12,
		"%s mm vs %s mm %s" % [clearance_50 * 1000.0, p.derived.min_prop_clearance_m * 1000.0, str(prep_50.errors)])
	var unrecorded: Dictionary = MD.load_document(_with_diameter(PROP_50_M, null), "5.0 inch, 5.1 diagnostics")
	_check("DATA-07 a 5.0 in prop under the 5.1 in diagnostics is refused", not unrecorded.ok
		and _hit(unrecorded.errors, "provenance.derived_diagnostics.min_prop_clearance_m") != "", _hit(unrecorded.errors, "min_prop"))
	var big := 0.160
	var overlapping: Dictionary = MD.load_document(_with_diameter(big, adjacent - big), "overlapping prop")
	var hit := _hit(overlapping.errors, "swept discs overlap (signed clearance")
	_check("DATA-07 a hypothetical 160 mm prop on the same hubs overlaps and is refused", not overlapping.ok and hit != "", hit)


# --- DATA-01…04, 07, 08: malformed mutations ------------------------------------------------------------

func _hit(errors: PackedStringArray, needle: String) -> String:
	for err: String in errors:
		if err.contains(needle):
			return err
	return ""


func _refused(label: String, mutate: Callable, needle: String, base: Dictionary = {}) -> void:
	var copy: Dictionary = (base if not base.is_empty() else _doc).duplicate(true)
	mutate.call(copy)
	var result: Dictionary = MD.load_document(copy, label)
	var hit := _hit(result.errors, needle)
	_check("refuses %s" % label, not result.ok and hit != "", hit if hit != "" else str(result.errors))
	if result.ok:
		return
	# The same mutation must also fail prepare (an unadmitted document never yields a model).
	var prep: Dictionary = MD.prepare(copy, "0".repeat(64))
	if prep.ok:
		_check("prepare also refuses %s" % label, false)


func _set_battery_mass(d: Dictionary, kg: float) -> void:
	for c: Dictionary in d.mass_inventory.components:
		if c.id == "battery":
			c.mass.value = kg


func _mutations() -> void:
	_refused("wrong format", func(d: Dictionary) -> void: d.format = "openrc-multirotor v2", "format: must be")
	_refused("unknown top-level key", func(d: Dictionary) -> void: d.race = {}, "race: unknown key")
	_refused("unknown key at depth 3 (controller.angle)", func(d: Dictionary) -> void: d.controller.angle.expo = 1, "controller.angle.expo: unknown key")
	_refused("unknown key inside a quantity", func(d: Dictionary) -> void: d.rotors[0].hub_frd.note = "x", "rotors[0].hub_frd.note: unknown key")
	_refused("unknown key inside an inventory shape", func(d: Dictionary) -> void: d.mass_inventory.components[0].shape.density = 1,
		"mass_inventory.components[0].shape.density: unknown key")
	_refused("missing block", func(d: Dictionary) -> void: d.erase("controller"), "controller: missing block")
	_refused("missing quantity field", func(d: Dictionary) -> void: d.camera.tilt.erase("source"), "camera.tilt.source: missing")
	_refused("wrong unit", func(d: Dictionary) -> void: d.rotors[0].diameter.unit = "in", "rotors[0].diameter.unit")
	_refused("wrong type", func(d: Dictionary) -> void: d.mass_inventory.components[0].mass.value = "0.095",
		"mass_inventory.components[0].mass.value: must be a number")
	_refused("wrong block type", func(d: Dictionary) -> void: d.rotors = {}, "rotors: must be an array of exactly four")
	_refused("NaN", func(d: Dictionary) -> void: d.rotor_law.thrust_coefficient.value = NAN, "rotor_law.thrust_coefficient.value: value nan is not finite")
	_refused("infinity", func(d: Dictionary) -> void: d.contacts.feet.value[0][2] = INF, "contacts.feet.value[0][2]: value inf is not finite")
	_refused("estimate presented as measured", func(d: Dictionary) -> void: d.contacts.friction.kind = "measured", "contacts.friction.kind")
	_refused("source not stating its class", func(d: Dictionary) -> void: d.contacts.friction.source = "typical value", "contacts.friction.source")
	_refused("bad source hash", func(d: Dictionary) -> void: d.provenance.sources_sha256 = "abc", "provenance.sources_sha256")
	_refused("duplicate rotor id", func(d: Dictionary) -> void: d.rotors[3].id = 1, "rotors[3].id: duplicate rotor id 1")
	_refused("missing rotor", func(d: Dictionary) -> void: d.rotors.remove_at(3), "rotors: must be an array of exactly four")
	_refused("three rotors with the same spin", func(d: Dictionary) -> void: d.rotors[0].spin = 1, "rotors: spins must be two +1 and two -1")
	_refused("spin that is not +-1", func(d: Dictionary) -> void: d.rotors[0].spin = 0, "rotors[0].spin: must be +1 or -1")
	_refused("adjacent same-spin arrangement without yaw authority", func(d: Dictionary) -> void: _swap_spins(d, 0, 1),
		"no independent roll, pitch and yaw authority")
	_refused("non-unit thrust axis", func(d: Dictionary) -> void: d.rotors[0].axis.value = [0.0, 0.0, -2.0], "rotors[0].axis: must be a unit vector")
	_refused("tilted unit thrust axis", func(d: Dictionary) -> void: d.rotors[0].axis.value = [0.0, 0.6, -0.8], "rotors[0].axis: unsupported thrust axis")
	_refused("nonpositive rotor inertia", func(d: Dictionary) -> void: d.rotors[0].inertia.value = 0.0, "rotors[0].inertia.value: value 0")
	_refused("nonpositive component mass", func(d: Dictionary) -> void: d.mass_inventory.components[0].mass.value = -0.095,
		"mass_inventory.components[0].mass.value")
	_refused("rotor inertia not matching its inventory assembly (double count)", func(d: Dictionary) -> void: d.rotors[1].inertia.value = 1.4e-5,
		"no rotor inertia double count")
	_refused("unreachable hover (9 kg battery)", func(d: Dictionary) -> void: _set_battery_mass(d, 9.0), "hover: unreachable")
	_refused("pack voltage inconsistent with cells", func(d: Dictionary) -> void: d.battery.cells.value = 4, "V per cell for 4 cells")
	_refused("non-monotonic OCV table", func(d: Dictionary) -> void: d.battery.ocv_points.value[5][1] = 20.0, "battery.ocv_points[5]: open-circuit voltage must not decrease")
	_refused("idle command at the maximum", func(d: Dictionary) -> void: d.powertrain.idle_command.value = 1.0, "powertrain: idle_command must be below")
	_refused("gyro filter at Nyquist (120 Hz)", func(d: Dictionary) -> void: d.controller.gyro_lpf.value = 120.0, "controller.gyro_lpf: 120")
	_refused("D-term filter above Nyquist", func(d: Dictionary) -> void: d.controller.dterm_lpf.value = 150.0, "controller.dterm_lpf: 150")
	_refused("sample_hz 480", func(d: Dictionary) -> void: d.controller.sample_rate.value = 480, "controller.sample_rate: only 240 Hz")
	_refused("negative gain", func(d: Dictionary) -> void: d.controller.kp.value[1] = -0.01, "controller.kp.value[1]")
	_refused("unsupported capability race", func(d: Dictionary) -> void: d.capabilities.append("race"), "unsupported capability 'race'")
	_refused("unsupported capability propwash", func(d: Dictionary) -> void: d.capabilities.append("propwash"), "unsupported capability 'propwash'")
	_refused("camera tilt above 60 deg", func(d: Dictionary) -> void: d.camera.tilt.value = 70.0, "camera.tilt.value")
	_refused("camera FOV below 60 deg", func(d: Dictionary) -> void: d.camera.hfov.value = 40.0, "camera.hfov.value")
	_refused("feet above the CG", func(d: Dictionary) -> void: _raise_feet(d), "contacts.feet: needs at least three non-collinear feet below the CG")
	_refused("armed start", func(d: Dictionary) -> void: d.start.armed = true, "start.armed")
	_refused("rest height not matching the sag", func(d: Dictionary) -> void: d.start.rest_height.value = 0.03, "start.rest_height")
	_refused("missing battery with the electrical law", func(d: Dictionary) -> void: d.erase("battery"), "battery: missing block")
	_refused("battery block with the lab law", func(d: Dictionary) -> void: d.battery = _doc.battery.duplicate(true),
		"battery: block not allowed with the first-order-lab-v1 law", _lab_variant())
	_refused("battery capability with the lab law", func(d: Dictionary) -> void: d.capabilities.append("battery"),
		"capabilities: 'battery' is only admitted", _lab_variant())
	_refused("tampered mass diagnostic", func(d: Dictionary) -> void: d.provenance.derived_diagnostics.mass_kg *= 1.000001,
		"provenance.derived_diagnostics.mass_kg: recorded")
	_refused("tampered inertia diagnostic", func(d: Dictionary) -> void: d.provenance.derived_diagnostics.inertia_kg_m2[2] *= 1.000001,
		"provenance.derived_diagnostics.inertia_kg_m2: recorded")
	_refused("tampered hover diagnostic", func(d: Dictionary) -> void: d.provenance.derived_diagnostics.hover_speed_rad_s += 1.0,
		"provenance.derived_diagnostics.hover_speed_rad_s: recorded")
	_refused("hub not matching the inventory and CG", func(d: Dictionary) -> void: d.rotors[2].hub_frd.value[0] -= 0.001,
		"rotors[2].hub_frd:")
	var bad_sha: Dictionary = MD.prepare(_doc, "not-a-hash")
	_check("prepare refuses a malformed data hash", not bad_sha.ok and _hit(bad_sha.errors, "sha256") != "", str(bad_sha.errors))
	var not_object: Dictionary = MD.load_document([1, 2], "array")
	_check("refuses a non-object document", not not_object.ok and _hit(not_object.errors, "array: top level") != "", str(not_object.errors))


func _swap_spins(d: Dictionary, a: int, b: int) -> void:
	var spin: Variant = d.rotors[a].spin
	d.rotors[a].spin = d.rotors[b].spin
	d.rotors[b].spin = spin


func _raise_feet(d: Dictionary) -> void:
	for point: Array in d.contacts.feet.value:
		point[2] = -0.01


# --- lab law and the manufacturer screen ----------------------------------------------------------------

func _lab_variant() -> Dictionary:
	var lab: Dictionary = _doc.duplicate(true)
	lab.erase("battery")
	lab.capabilities.erase("battery")
	lab.powertrain = {
		law = MD.LAW_LAB,
		full_command_speed = {value = 3140.0, unit = "rad/s", kind = "borrowed", source = "borrowed: lab fixture Plant.research_quad() full-duty speed"},
		time_constant = {value = 0.0391, unit = "s", kind = "borrowed", source = "borrowed: lab fixture Plant.research_quad() motor time constant"},
		idle_command = _doc.powertrain.idle_command.duplicate(true),
		max_command = _doc.powertrain.max_command.duplicate(true),
	}
	return lab


func _lab_law() -> void:
	var lab := _lab_variant()
	var loaded: Dictionary = MD.load_document(lab, "lab-law variant")
	var prep: Dictionary = MD.prepare(loaded.data, loaded.sha256) if loaded.ok else {ok = false, errors = loaded.errors}
	_check("the first-order-lab-v1 variant admits and prepares", prep.ok, str(prep.errors))
	if not prep.ok:
		return
	var p: Dictionary = prep.prepared
	var k_t: float = p.rotor_law.thrust_coefficient_n_s2
	var expected := k_t * (1.0 * 3140.0) ** 2
	_check("lab-law prepared powertrain has its own keys and no battery", not p.has("battery")
		and p.powertrain.keys().size() == 5 and p.powertrain.law == MD.LAW_LAB and p.powertrain.has("full_command_speed_rad_s")
		and p.powertrain.has("time_constant_s"))
	_check("lab-law static maximum is k_T (max_command full_command_speed)^2", absf(p.derived.static_max_thrust_per_rotor_n - expected) <= 1e-12 * expected,
		"%s N" % p.derived.static_max_thrust_per_rotor_n)


func _manufacturer_screen(p: Dictionary) -> void:
	var w: float = MD.static_speed(p.powertrain, p.rotor_law, 1.0, ROW100_VOLTS)
	var thrust: float = p.rotor_law.thrust_coefficient_n_s2 * w * w
	var deviation := (thrust - ROW100_THRUST_N) / ROW100_THRUST_N
	print("     PHY-09 screen: modelled static thrust at %s V, full command: %s N (%s rad/s); manufacturer 100%% row %s N (3669.59 rad/s); deviation %s %%" % [
		ROW100_VOLTS, thrust, w, ROW100_THRUST_N, deviation * 100.0])
	_check("PHY-09 fit consistency screen: modelled 100 % row thrust within 15 % (not validation)", absf(deviation) < 0.15)
	var w_full: float = MD.static_speed(p.powertrain, p.rotor_law, 1.0, p.battery.ocv_points[23])
	_check("prepared static maximum is the full-charge OCV static balance", absf(p.rotor_law.thrust_coefficient_n_s2 * w_full * w_full
		- p.derived.static_max_thrust_per_rotor_n) <= 1e-12 * p.derived.static_max_thrust_per_rotor_n)
