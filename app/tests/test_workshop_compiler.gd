extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const WheelProfiles := preload("res://physics/wheel_profiles.gd")
const Compiler := preload("res://workshop/compiler.gd")
const Session := preload("res://sim/flight_session.gd")
const STIK_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const EXTRA_PATH := "res://data/aircraft/gp_extra_300s_60.json"

var _checks := 0
var _failures := 0


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _read(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _initialize() -> void:
	var defaults: Dictionary = Compiler.defaults()
	_check("defaults preserve exact physical no-op", defaults == {
		"scale": 1.0,
		"mass_policy": "constant_wing_loading",
		"weight_multiplier": 1.0,
		"power_multiplier": 1.0,
		"control_multiplier": 1.0,
	}, str(defaults))
	var stik := _read(STIK_PATH)
	var extra := _read(EXTRA_PATH)
	_check("Stik fixture loaded", not stik.is_empty())
	_check("Extra fixture loaded", not extra.is_empty())
	if stik.is_empty() or extra.is_empty():
		quit(1)
		return

	_test_no_op(stik, "Stik")
	_test_no_op(extra, "Extra")
	_test_scale_policies(stik)
	_test_scale_policies(extra)
	_test_power_and_controls(stik)
	_test_unfamiliar_identity(stik)
	_test_catalog_registry()
	_test_recipe_validation(stik)
	_test_noop_trajectory(stik, STIK_PATH, "Stik")
	_test_noop_trajectory(extra, EXTRA_PATH, "Extra")
	_test_scaled_flight(stik, "Stik")
	_test_scaled_flight(extra, "Extra")
	print("Workshop compiler: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_no_op(base: Dictionary, label: String) -> void:
	var original: Dictionary = base.duplicate(true)
	var expected: Dictionary = AircraftData.validate_and_derive(base)
	var result: Dictionary = Compiler.compile(base, {})
	_check("%s no-op compiles" % label, result.ok, str(result.errors))
	_check("%s no-op raw is detached and exact" % label, result.ok and result.raw == original)
	_check("%s no-op does not mutate base" % label, base == original)
	_check("%s data keeps full validator envelope" % label,
		result.data is Dictionary and result.data.get("ok", false) and result.data.has("warnings") and result.data.has("model"))
	_check("%s no-op data matches full validator physics" % label,
		result.ok and result.data.model.mass_kg == expected.model.mass_kg and result.data.model.inertia == expected.model.inertia)
	var profiled_expected: Dictionary = WheelProfiles.apply_to_model(expected.model)
	_check("%s no-op derived physics model is unchanged apart from identity/provenance" % label,
		result.ok and profiled_expected.ok
		and _physics_projection(result.data.model) == _physics_projection(profiled_expected.model))
	_check("%s no-op inherits base wheel profile" % label,
		result.ok and result.data.model.get("wheel_profile", {}).get("base_aircraft_id", "") == base.id
		and result.data.model.get("wheel_profile", {}).get("inheritance", "") == "base_profile")
	_check("%s summary exposes stable UI metrics" % label,
		result.summary.has_all(["base_aircraft_id", "effective_model_id", "name", "scale", "mass_policy",
			"weight_multiplier", "mass_ratio", "mass_kg", "wing_area_m2", "wing_span_m",
			"wing_loading_kg_m2", "power_multiplier", "control_multiplier", "capabilities", "compiler_version"]))


func _test_scale_policies(base: Dictionary) -> void:
	var base_data: Dictionary = AircraftData.validate_and_derive(base)
	var base_profiled: Dictionary = WheelProfiles.apply_to_model(base_data.model)
	var mini: Dictionary = Compiler.compile(base, {"scale": 0.5})
	_check("50% constant-wing-loading recipe validates", mini.ok, str(mini.errors))
	if mini.ok:
		_check("50% scale transforms span/chord and area by geometric dimensions",
			is_equal_approx(mini.raw.reference.wing_span.value, base.reference.wing_span.value * 0.5)
			and is_equal_approx(mini.raw.reference.mean_chord.value, base.reference.mean_chord.value * 0.5)
			and is_equal_approx(mini.raw.reference.wing_area.value, base.reference.wing_area.value * 0.25))
		if base.reference.has("root_chord"):
			_check("tapered Extra root/tip chords scale independently from area",
				is_equal_approx(mini.raw.reference.root_chord.value, base.reference.root_chord.value * 0.5)
				and is_equal_approx(mini.raw.reference.tip_chord.value, base.reference.tip_chord.value * 0.5))
		_check("aerodynamic and balance datum positions scale componentwise",
			mini.raw.reference.aero_reference_point.value == base.reference.aero_reference_point.value.map(func(v: float) -> float: return v * 0.5)
			and mini.raw.balance.plan_cg.value == base.balance.plan_cg.value.map(func(v: float) -> float: return v * 0.5)
			and mini.raw.balance.firewall.value == base.balance.firewall.value.map(func(v: float) -> float: return v * 0.5))
		_check("50% scale keeps wing loading", is_equal_approx(mini.data.model.mass_kg / mini.data.model.reference.S,
			base_data.model.mass_kg / base_data.model.reference.S))
		_check("mass range scales as a consistency band", is_equal_approx(mini.raw.plausibility.mass_range.value[0], base.plausibility.mass_range.value[0] * 0.25))
		_check("small model gear keeps base heave frequency policy",
			is_equal_approx(mini.data.model.landing_gear.heave_omega, base_data.model.landing_gear.heave_omega))
		var small_spring_factor := 0.25
		var small_contact: Dictionary = mini.raw.landing_gear.contacts[0]
		var base_contact: Dictionary = base.landing_gear.contacts[0]
		_check("small-model suspension applies the documented spring, damping and travel policy",
			is_equal_approx(small_contact.stiffness.value, base_contact.stiffness.value * small_spring_factor)
			and is_equal_approx(small_contact.damping.value, base_contact.damping.value * small_spring_factor)
			and is_equal_approx(small_contact.max_compression.value, base_contact.max_compression.value))
		_check("wheel radius scales while spin relaxation is retained",
			is_equal_approx(mini.data.model.landing_gear.contacts[0].wheel_radius,
				base_profiled.model.landing_gear.contacts[0].wheel_radius * 0.5)
			and mini.data.model.landing_gear.contacts[0].spin_relaxation == base_profiled.model.landing_gear.contacts[0].spin_relaxation)
		_check("crash hull vertices scale and retain derived provenance",
			mini.raw.crash_hull.value[0] == base.crash_hull.value[0].map(func(v: float) -> float: return v * 0.5)
			and mini.raw.crash_hull.kind == "derived")
		_check("rotor geometry and inertia use their separate similarity dimensions",
			is_equal_approx(mini.raw.propulsion.propeller.diameter.value, base.propulsion.propeller.diameter.value * 0.5)
			and is_equal_approx(mini.raw.propulsion.propeller.rotating_inertia.value,
				base.propulsion.propeller.rotating_inertia.value * 0.0625))
		_check("contact coordinates scale with the airframe",
			small_contact.position.value == base_contact.position.value.map(func(v: float) -> float: return v * 0.5))
		_check("donor inertia comparison remains unchanged evidence",
			mini.raw.plausibility.inertia_reference == base.plausibility.inertia_reference)
		_check("nondimensional ground-effect coefficients remain unchanged",
			mini.raw.aero.get("ground_effect", {}) == base.aero.get("ground_effect", {}))
		_check("changed inventory evidence is derived", mini.raw.inventory[0].mass.kind == "derived"
			and "Workshop compiler v1" in mini.raw.inventory[0].mass.source)
	var geometric: Dictionary = Compiler.compile(base, {"scale": 1.5, "mass_policy": "geometric"})
	_check("150% geometric recipe validates", geometric.ok, str(geometric.errors))
	if geometric.ok:
		var geometric_scale := 1.5
		var expected_ratio := pow(geometric_scale, 3.0)
		var expected_inertia_ratio := expected_ratio * geometric_scale * geometric_scale
		_check("geometric mass ratio is s cubed", is_equal_approx(geometric.data.model.mass_kg / base_data.model.mass_kg, expected_ratio))
		_check("geometric area and inertia use their own dimensions",
			is_equal_approx(geometric.data.model.reference.S / base_data.model.reference.S, geometric_scale * geometric_scale)
			and _array_ratio_is(geometric.data.model.inertia, base_data.model.inertia, expected_inertia_ratio))
		_check("geometric propeller rotor inertia follows mass times s squared",
			is_equal_approx(geometric.raw.propulsion.propeller.rotating_inertia.value /
				base.propulsion.propeller.rotating_inertia.value, expected_inertia_ratio))
		_check("geometric start speed and gear dimensions follow declared policy",
			is_equal_approx(geometric.raw.start.level_speed.value / base.start.level_speed.value,
				sqrt(expected_ratio) / geometric_scale)
			and is_equal_approx(geometric.raw.landing_gear.contacts[0].stiffness.value /
				base.landing_gear.contacts[0].stiffness.value, expected_ratio / geometric_scale)
			and is_equal_approx(geometric.raw.landing_gear.contacts[0].damping.value /
				base.landing_gear.contacts[0].damping.value, expected_ratio / sqrt(geometric_scale))
			and is_equal_approx(geometric.raw.landing_gear.contacts[0].max_compression.value /
				base.landing_gear.contacts[0].max_compression.value, geometric_scale))
		_check("changed level-speed provenance names the generic similarity transform",
			geometric.raw.start.level_speed.kind == "derived"
			and "sqrt(mass_ratio)/s" in geometric.raw.start.level_speed.source)
		_check("mass range remains inside original loader domain",
			geometric.raw.plausibility.mass_range.value[0] >= 0.01
			and geometric.raw.plausibility.mass_range.value[1] <= 100.0)
	var oversized_geometric: Dictionary = Compiler.compile(base, {"scale": 2.0, "mass_policy": "geometric"})
	if oversized_geometric.ok:
		_check("200% geometric result preserves the declared s-cubed mass law",
			is_equal_approx(oversized_geometric.data.model.mass_kg / base_data.model.mass_kg, 8.0))
	else:
		_check("200% geometric result reports the source v2 quantity bound",
			str(oversized_geometric.errors).contains("inventory")
			or str(oversized_geometric.errors).contains("mass_range"), str(oversized_geometric.errors))


func _test_power_and_controls(base: Dictionary) -> void:
	var base_data: Dictionary = AircraftData.validate_and_derive(base)
	var powered: Dictionary = Compiler.compile(base, {"power_multiplier": 2.0, "control_multiplier": 1.25})
	_check("prescribed-RPM power and control recipe validates", powered.ok, str(powered.errors))
	if powered.ok:
		var rpm_factor := pow(2.0, 1.0 / 3.0)
		_check("power multiplier changes actual solver max RPM", is_equal_approx(
			powered.data.model.propulsion.max_rpm / base_data.model.propulsion.max_rpm, rpm_factor))
		_check("power multiplier preserves idle RPM", powered.data.model.propulsion.idle_rpm == base_data.model.propulsion.idle_rpm)
		_check("power summary uses changed RPM coefficient law", is_equal_approx(
			powered.summary.static_power_w / _static_power(base_data.model), 2.0))
		_check("control multiplier changes all maximum throws", is_equal_approx(
			powered.data.model.controls.throw_deg.aileron, base_data.model.controls.throw_deg.aileron * 1.25)
			and is_equal_approx(powered.data.model.controls.throw_deg.elevator, base_data.model.controls.throw_deg.elevator * 1.25)
			and is_equal_approx(powered.data.model.controls.throw_deg.rudder, base_data.model.controls.throw_deg.rudder * 1.25))
		_check("control rate timing stays unchanged", powered.data.model.controls.servo_rate == base_data.model.controls.servo_rate)
		_check("power proposal leaves rating evidence and nondimensional prop tables intact",
			powered.raw.propulsion.engine.peak_power == base.propulsion.engine.peak_power
			and powered.raw.propulsion.engine.peak_power_rpm == base.propulsion.engine.peak_power_rpm
			and powered.raw.propulsion.propeller.ct_table == base.propulsion.propeller.ct_table
			and powered.raw.propulsion.propeller.cp_table == base.propulsion.propeller.cp_table)
	var weighted: Dictionary = Compiler.compile(base, {"scale": 1.25, "weight_multiplier": 1.5})
	_check("uniform weight multiplier composes with constant-wing-loading scale", weighted.ok, str(weighted.errors))
	if weighted.ok:
		var ratio := pow(1.25, 2.0) * 1.5
		_check("weight multiplier scales model mass and all inertia entries", is_equal_approx(
			weighted.data.model.mass_kg / base_data.model.mass_kg, ratio)
			and _array_ratio_is(weighted.data.model.inertia, base_data.model.inertia, ratio * 1.25 * 1.25))
	var clipped: Dictionary = Compiler.compile(base, {"scale": 2.01})
	_check("scale above the V1 bound is rejected", not clipped.ok and not clipped.errors.is_empty())


func _test_unfamiliar_identity(base: Dictionary) -> void:
	var extra := _read(EXTRA_PATH)
	var successful := 0
	for index: int in 20:
		var source: Dictionary = base if index % 2 == 0 else extra
		var synthetic: Dictionary = source.duplicate(true)
		var offset := 0.001 * float(index + 1)
		synthetic.id = "unfamiliar-aircraft-%02d" % index
		for component_variant: Variant in synthetic.inventory:
			var position: Array = component_variant.position.value
			position[0] += offset
		synthetic.inventory.reverse()
		synthetic.balance.plan_cg.value[0] += offset
		synthetic.balance.firewall.value[0] += offset
		synthetic.reference.aero_reference_point.value[0] += offset
		for surface_key: String in ["horizontal", "vertical"]:
			synthetic.aero.surfaces[surface_key].position.value[0] += offset
		for point: Array in synthetic.crash_hull.value:
			point[0] += offset
		for contact: Dictionary in synthetic.landing_gear.contacts:
			contact.position.value[0] += offset
		var candidate_check: Dictionary = AircraftData.validate_and_derive(synthetic)
		_check("unfamiliar base %02d validates after shifted datum/order" % index, candidate_check.ok, str(candidate_check.errors))
		if not candidate_check.ok:
			continue
		var scale := 0.5 + float(index % 16) * 0.1
		var trial_id := "variant-unfamiliar-output-%02d" % index
		var compiled: Dictionary = Compiler.compile(synthetic, {"id": trial_id, "scale": scale})
		_check("module-shape transform compiles unfamiliar identity %02d" % index, compiled.ok, str(compiled.errors))
		if compiled.ok:
			successful += 1
			_check("effective trial identity is independent of base ID %02d" % index,
				compiled.raw.id == trial_id and compiled.data.model.id == trial_id)
			_check("shifted CG scales from each unfamiliar base %02d" % index,
				is_equal_approx(compiled.data.model.cg_le[0], candidate_check.model.cg_le[0] * scale))
	_check("twenty unfamiliar IDs compile through the generic path", successful == 20, str(successful))


func _test_catalog_registry() -> void:
	var files: PackedStringArray = DirAccess.get_files_at("res://data/aircraft")
	var count := 0
	var probes := {
		"scale": {"scale": 1.1},
		"weight": {"weight_multiplier": 1.1},
		"power": {"power_multiplier": 1.1},
		"controls": {"control_multiplier": 1.1},
	}
	for file: String in files:
		if not file.ends_with(".json"):
			continue
		var raw: Dictionary = _read("res://data/aircraft/" + file)
		if raw.is_empty():
			continue
		count += 1
		var support: Dictionary = Compiler.capabilities(raw)
		_check("catalog capability record %s has four flags and a note" % raw.get("id", file),
			support.has_all(["scale", "weight", "power", "controls", "note"]))
		for flag: String in ["scale", "weight", "power", "controls"]:
			_check("catalog capability %s is boolean for %s" % [flag, raw.get("id", file)], typeof(support.get(flag)) == TYPE_BOOL)
		var custom_id := "workshop-catalog-probe-%02d" % count
		var renamed: Dictionary = raw.duplicate(true)
		renamed.id = custom_id
		var renamed_support: Dictionary = Compiler.capabilities(renamed)
		_check("capability selection is unchanged when catalog ID changes %s" % raw.get("id", file),
			_support_flags_equal(support, renamed_support))
		var no_op: Dictionary = Compiler.compile(raw, {"id": custom_id})
		_check("catalog no-op works with a trial identity %s" % raw.get("id", file), no_op.ok, str(no_op.errors))
		if no_op.ok:
			_check("catalog no-op effective model identity %s" % raw.get("id", file), no_op.data.model.id == custom_id)
			var base_data: Dictionary = AircraftData.validate_and_derive(raw)
			var profiled_base: Dictionary = WheelProfiles.apply_to_model(base_data.model)
			_check("catalog no-op physics matches base for %s" % raw.get("id", file),
				profiled_base.ok and _physics_projection(no_op.data.model) == _physics_projection(profiled_base.model))
			_check("catalog no-op preserves base wheel runtime status for %s" % raw.get("id", file),
				no_op.data.model.get("wheel_profile", {}).get("status", "") == profiled_base.model.get("wheel_profile", {}).get("status", "")
				and no_op.data.model.get("wheel_profile", {}).get("base_aircraft_id", "") == str(raw.get("id", "")))
		for capability: String in probes:
			if support[capability]:
				continue
			var refused: Dictionary = Compiler.compile(raw, probes[capability])
			_check("unsupported %s recipe refuses clearly for %s" % [capability, raw.get("id", file)],
				not refused.ok and str(refused.errors).contains(capability))
	_check("catalog registry inspected current aircraft files", count >= 7, str(count))


func _test_recipe_validation(base: Dictionary) -> void:
	var unknown: Dictionary = Compiler.compile(base, {"magic": 1.0})
	_check("unknown recipe keys are rejected", not unknown.ok and str(unknown.errors).contains("unknown key"))
	var nonfinite: Dictionary = Compiler.compile(base, {"scale": NAN})
	_check("nonfinite recipe values are rejected", not nonfinite.ok and str(nonfinite.errors).contains("finite"))
	var widened_base: Dictionary = base.duplicate(true)
	widened_base.plausibility.mass_range.value = [2.0, 8.0]
	var widened_check: Dictionary = AircraftData.validate_and_derive(widened_base)
	_check("mass-domain boundary fixture stays valid before transformation", widened_check.ok, str(widened_check.errors))
	var outside_domain: Dictionary = Compiler.compile(widened_base,
		{"scale": 2.0, "mass_policy": "geometric", "weight_multiplier": 2.0})
	_check("transformed mass range is rejected rather than clipped when outside loader domain",
		not outside_domain.ok and str(outside_domain.errors).contains("mass_range"))


func _test_scaled_flight(base: Dictionary, label: String) -> void:
	for scale_value: float in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]:
		var built: Dictionary = Compiler.compile(base, {"scale": scale_value})
		_check("%s %.0f%% candidate compiles for flight" % [label, scale_value * 100.0], built.ok, str(built.errors))
		if not built.ok:
			continue
		var frozen: Dictionary = built.data.duplicate(true)
		frozen["input_identity"] = {
			"format": AircraftData.FORMAT,
			"sha256": JSON.stringify(built.raw, "", true).sha256_text(),
		}
		var session: Node = Session.new()
		session.physics_enabled = false
		session.setup("", str(built.raw.id), frozen)
		_check("%s %.0f%% session validates aircraft and trim" % [label, scale_value * 100.0],
			session.aircraft.get("ok", false) and session.start.get("ok", false),
			str(session.start.get("message", "")))
		_check("%s %.0f%% session reports flyable before stepping" % [label, scale_value * 100.0],
			session.is_flyable(), str(session.start.get("message", "")))
		if session.aircraft.get("ok", false) and session.start.get("ok", false) and session.is_flyable():
			var finite_state: bool = not session.sim.state.is_empty()
			for tick: int in 240:
				session.sim.step()
				for value: float in session.sim.state:
					finite_state = finite_state and is_finite(value)
			_check("%s %.0f%% remains finite for 240 steps" % [label, scale_value * 100.0],
				finite_state and session.sim.tick == 240 and session.sim.fault_reason.is_empty(),
				"tick=%d fault=%s" % [session.sim.tick, session.sim.fault_reason])
		session.free()


func _test_noop_trajectory(base: Dictionary, path: String, label: String) -> void:
	var built: Dictionary = Compiler.compile(base, {})
	_check("%s no-op candidate compiles for trajectory comparison" % label, built.ok, str(built.errors))
	if not built.ok:
		return
	var base_session: Node = Session.new()
	var compiled_session: Node = Session.new()
	base_session.physics_enabled = false
	compiled_session.physics_enabled = false
	base_session.setup(path, str(base.id))
	var frozen: Dictionary = built.data.duplicate(true)
	frozen["input_identity"] = {
		"format": AircraftData.FORMAT,
		"sha256": JSON.stringify(built.raw, "", true).sha256_text(),
	}
	compiled_session.setup("", str(built.raw.id), frozen)
	var both_start: bool = base_session.aircraft.get("ok", false) and base_session.start.get("ok", false) \
		and compiled_session.aircraft.get("ok", false) and compiled_session.start.get("ok", false) \
		and base_session.is_flyable() and compiled_session.is_flyable()
	_check("%s base and compiled no-op both trim and fly" % label, both_start,
		"base=%s compiled=%s" % [base_session.start.get("message", ""), compiled_session.start.get("message", "")])
	_check("%s base and compiled no-op activate identical wheel dynamics" % label,
		base_session.wheel_count() == compiled_session.wheel_count(),
		"base=%d compiled=%d" % [base_session.wheel_count(), compiled_session.wheel_count()])
	if both_start:
		var exact: bool = base_session.sim.state == compiled_session.sim.state \
			and base_session.sim.aux == compiled_session.sim.aux \
			and base_session.sim.continuous == compiled_session.sim.continuous \
			and base_session.sim.inputs == compiled_session.sim.inputs
		var first_mismatch := -1
		for tick: int in 240:
			base_session.sim.step()
			compiled_session.sim.step()
			var tick_matches: bool = base_session.sim.state == compiled_session.sim.state \
				and base_session.sim.aux == compiled_session.sim.aux \
				and base_session.sim.continuous == compiled_session.sim.continuous
			if not tick_matches and first_mismatch < 0:
				first_mismatch = tick + 1
			exact = exact and tick_matches
		_check("%s no-op trajectory exactly matches base for 240 committed ticks" % label,
			exact and base_session.sim.tick == 240 and compiled_session.sim.tick == 240 \
			and base_session.sim.fault_reason.is_empty() and compiled_session.sim.fault_reason.is_empty(),
			"first_mismatch=%d base_tick=%d compiled_tick=%d" % [first_mismatch, base_session.sim.tick, compiled_session.sim.tick])
	base_session.free()
	compiled_session.free()


func _static_power(model: Dictionary) -> float:
	var prop: Dictionary = model.propulsion
	var rpm: float = float(prop.max_rpm) / 60.0
	var cp: PackedFloat64Array = prop.cp
	return float(cp[1]) * 1.225 * pow(rpm, 3.0) * pow(float(prop.diameter), 5.0)


func _array_ratio_is(actual: PackedFloat64Array, base: PackedFloat64Array, ratio: float) -> bool:
	if actual.size() != base.size():
		return false
	for index: int in actual.size():
		if not is_equal_approx(actual[index], base[index] * ratio):
			return false
	return true


func _support_flags_equal(left: Dictionary, right: Dictionary) -> bool:
	for flag: String in ["scale", "weight", "power", "controls"]:
		if left.get(flag) != right.get(flag):
			return false
	return true


func _physics_projection(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value.keys():
			var name := str(key)
			if name == "id" or name == "data_sha256" or name == "wheel_profile" or name == "wheel_provenance" \
					or name.ends_with("_provenance"):
				continue
			result[key] = _physics_projection(value[key])
		return result
	if value is Array:
		var result: Array = []
		for element: Variant in value:
			result.append(_physics_projection(element))
		return result
	return value
