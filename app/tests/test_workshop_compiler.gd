extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const WheelProfiles := preload("res://physics/wheel_profiles.gd")
const Compiler := preload("res://workshop/compiler.gd")
const Session := preload("res://sim/flight_session.gd")
const Trial := preload("res://workshop/trial.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const STIK_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const EXTRA_PATH := "res://data/aircraft/gp_extra_300s_60.json"
const P51_PATH := "res://data/aircraft/p51d_mustang_120.json"

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
		"tank_capacity_multiplier": 1.0,
	}, str(defaults))
	var stik := _read(STIK_PATH)
	var extra := _read(EXTRA_PATH)
	var p51 := _read(P51_PATH)
	_check("Stik fixture loaded", not stik.is_empty())
	_check("Extra fixture loaded", not extra.is_empty())
	_check("finite-liquid P-51 fixture loaded", not p51.is_empty())
	if stik.is_empty() or extra.is_empty() or p51.is_empty():
		quit(1)
		return

	_test_no_op(stik, "Stik")
	_test_no_op(extra, "Extra")
	_test_scale_policies(stik)
	_test_scale_policies(extra)
	_test_tank_and_fill_scaling(stik)
	_test_tank_capacity_frozen_session(p51)
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
			"weight_multiplier", "tank_capacity_multiplier", "mass_ratio", "mass_kg", "wing_area_m2", "wing_span_m",
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
		_check("50% scale keeps the dry build's wing loading (FUEL-11a)",
			is_equal_approx((mini.data.model.mass_kg - _liquid_kg(mini.data.model)) / mini.data.model.reference.S,
				(base_data.model.mass_kg - _liquid_kg(base_data.model)) / base_data.model.reference.S))
		_tank_follows_airframe(base_data.model, mini.data.model, 0.5, "50%")
		_check("mass range scales as a consistency band", is_equal_approx(mini.raw.plausibility.mass_range.value[0], base.plausibility.mass_range.value[0] * 0.25))
		_check("small model gear keeps base heave frequency policy",
			is_equal_approx(mini.data.model.landing_gear.heave_omega, base_data.model.landing_gear.heave_omega))
		# The gear carries the whole airplane: the total mass ratio (dry × 0.25, tank liquid × 0.125; FUEL-11a).
		var small_spring_factor: float = mini.data.model.mass_kg / base_data.model.mass_kg
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
		var fuel: float = _liquid_kg(base_data.model)
		_check("weight multiplier scales the dry build only; the tank liquid follows s³ (FUEL-11a)", fuel > 0.0
			and is_equal_approx(weighted.data.model.mass_kg - _liquid_kg(weighted.data.model), (base_data.model.mass_kg - fuel) * ratio)
			and is_equal_approx(_liquid_kg(weighted.data.model), fuel * pow(1.25, 3.0)))
		var expected: PackedFloat64Array = _inertia_by_law(base, 1.25, ratio)
		_check("inertia follows the per-item law (dry × ratio, liquid × s³, positions and boxes × s)",
			_array_ratio_is(weighted.data.model.inertia, expected, 1.0), "%s vs %s" % [weighted.data.model.inertia, expected])
		_tank_follows_airframe(base_data.model, weighted.data.model, 1.25, "weighted 125%")
	var clipped: Dictionary = Compiler.compile(base, {"scale": 2.01})
	_check("scale above the V1 bound is rejected", not clipped.ok and not clipped.errors.is_empty())


func _test_tank_and_fill_scaling(base: Dictionary) -> void:
	var authored := base.duplicate(true)
	authored.fuel_system.tanks[0].reserve = {
		"value": 0.05,
		"unit": "l",
		"kind": "manual",
		"source": "Workshop FUEL-11 authored-reserve regression",
	}
	var base_data: Dictionary = AircraftData.validate_and_derive(authored)
	_check("authored-reserve fixture validates", base_data.ok, str(base_data.errors))
	if not base_data.ok:
		return
	var compiled: Dictionary = Compiler.compile(authored, {"scale": 0.5, "weight_multiplier": 1.5})
	_check("scaled tank with authored reserve compiles", compiled.ok, str(compiled.errors))
	if not compiled.ok:
		return
	var s := 0.5
	var tank_ratio := pow(s, 3.0)
	var dry_ratio := pow(s, 2.0) * 1.5
	var base_tank: Dictionary = base_data.model.fuel_system.tanks[0]
	var tank: Dictionary = compiled.data.model.fuel_system.tanks[0]
	var raw_tank: Dictionary = compiled.raw.fuel_system.tanks[0]
	_check("capacity, unusable volume and authored reserve scale together by s³",
		is_equal_approx(raw_tank.capacity.value, authored.fuel_system.tanks[0].capacity.value * tank_ratio)
		and is_equal_approx(raw_tank.unusable.value, authored.fuel_system.tanks[0].unusable.value * tank_ratio)
		and is_equal_approx(raw_tank.reserve.value, authored.fuel_system.tanks[0].reserve.value * tank_ratio))
	_check("tank sizing stays independent of dry weight multiplier",
		is_equal_approx(tank.capacity_m3, base_tank.capacity_m3 * tank_ratio)
		and is_equal_approx(tank.reserve_fraction, base_tank.reserve_fraction))
	_check("fill and blend density remain unchanged by Workshop scaling",
		is_equal_approx(tank.start_fill, base_tank.start_fill)
		and is_equal_approx(tank.density_kg_m3, base_tank.density_kg_m3)
		and is_equal_approx(tank.capacity_kg / tank.capacity_m3, base_tank.density_kg_m3))
	_check("fuel mass follows tank volume while dry mass follows selected mass policy",
		is_equal_approx(tank.liquid_mass_kg, base_tank.liquid_mass_kg * tank_ratio)
		and is_equal_approx(compiled.data.model.mass_kg - tank.liquid_mass_kg,
			(base_data.model.mass_kg - base_tank.liquid_mass_kg) * dry_ratio))
	_check("authored reserve provenance becomes derived with scaled units",
		raw_tank.reserve.kind == "derived" and str(raw_tank.reserve.source).contains("reserve volume × s³"))
	var resized: Dictionary = Compiler.compile(authored, {
		"scale": 0.5,
		"weight_multiplier": 1.5,
		"tank_capacity_multiplier": 1.5,
	})
	_check("independent tank-size recipe compiles", resized.ok, str(resized.errors))
	if not resized.ok:
		return
	var tank_multiplier := 1.5
	var combined_tank_ratio := tank_ratio * tank_multiplier
	var tank_linear_ratio := s * pow(tank_multiplier, 1.0 / 3.0)
	var resized_tank: Dictionary = resized.data.model.fuel_system.tanks[0]
	var resized_raw_tank: Dictionary = resized.raw.fuel_system.tanks[0]
	var liquid_id: String = str(base_tank.liquid_inventory_id)
	var shell_id: String = str(base_tank.shell_inventory_id)
	var resized_liquid: Dictionary = _inventory_by_id(resized.raw.inventory, liquid_id)
	var authored_liquid: Dictionary = _inventory_by_id(authored.inventory, liquid_id)
	var resized_shell: Dictionary = _inventory_by_id(resized.raw.inventory, shell_id)
	var authored_shell: Dictionary = _inventory_by_id(authored.inventory, shell_id)
	_check("tank capacity, unusable and reserve use airframe s³ × independent capacity ratio",
		is_equal_approx(resized_raw_tank.capacity.value, authored.fuel_system.tanks[0].capacity.value * combined_tank_ratio)
		and is_equal_approx(resized_raw_tank.unusable.value, authored.fuel_system.tanks[0].unusable.value * combined_tank_ratio)
		and is_equal_approx(resized_raw_tank.reserve.value, authored.fuel_system.tanks[0].reserve.value * combined_tank_ratio))
	_check("capacity change leaves authored fill fraction and density unchanged",
		is_equal_approx(resized_tank.start_fill, base_tank.start_fill)
		and is_equal_approx(resized_tank.density_kg_m3, base_tank.density_kg_m3)
		and is_equal_approx(resized_tank.capacity_kg / resized_tank.capacity_m3, base_tank.density_kg_m3))
	_check("liquid mass follows new capacity while dry inventory follows only mass policy",
		is_equal_approx(resized_tank.liquid_mass_kg, base_tank.liquid_mass_kg * combined_tank_ratio)
		and is_equal_approx(float(resized_shell.mass.value), float(authored_shell.mass.value) * dry_ratio)
		and is_equal_approx(resized.data.model.mass_kg - resized_tank.liquid_mass_kg,
			(base_data.model.mass_kg - base_tank.liquid_mass_kg) * dry_ratio))
	_check("tank liquid and shell boxes scale by s × cube-root of capacity ratio",
		resized_liquid.size.value == authored_liquid.size.value.map(func(value: float) -> float: return value * tank_linear_ratio)
		and resized_shell.size.value == authored_shell.size.value.map(func(value: float) -> float: return value * tank_linear_ratio))
	_check("compiled summary reports estimated tank sizing and physical capacity",
		is_equal_approx(float(resized.summary.tank_capacity_multiplier), tank_multiplier)
		and is_equal_approx(float(resized.summary.fuel_capacity_l), float(base_tank.capacity_m3) * combined_tank_ratio * 1000.0))


func _test_tank_capacity_frozen_session(base: Dictionary) -> void:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(P51_PATH)
	var payload := {
		"base_id": str(base.get("id", "")),
		"base_bytes": bytes,
		"recipe": {"tank_capacity_multiplier": 1.25},
	}
	var frozen: Dictionary = Trial.freeze(payload)
	_check("tank capacity edit compiles, validates and freezes a trial", frozen.get("ok", false), str(frozen.get("errors", [])))
	if not frozen.get("ok", false):
		return
	var base_data: Dictionary = AircraftData.validate_and_derive(base)
	var expected_tank: Dictionary = base_data.model.fuel_system.tanks[0]
	var frozen_tank: Dictionary = frozen.data.model.fuel_system.tanks[0]
	_check("frozen model carries the selected tank capacity independently of dry mass",
		is_equal_approx(frozen_tank.capacity_m3, expected_tank.capacity_m3 * 1.25)
		and is_equal_approx(frozen_tank.start_fill, expected_tank.start_fill)
		and is_equal_approx(frozen_tank.density_kg_m3, expected_tank.density_kg_m3))
	var session: Node = Session.new()
	session.physics_enabled = false
	session.setup("", str(frozen.data.model.id), frozen.data)
	_check("frozen capacity recipe passes Session setup, trim and flyable gates",
		session.aircraft.get("ok", false) and session.start.get("ok", false) and session.is_flyable(),
		str(session.start.get("message", "")))
	if session.aircraft.get("ok", false) and session.is_flyable():
		var sample: Dictionary = session.mass_properties()
		_check("accepted frozen finite-fuel session reports edited capacity and selected launch fill",
			sample.get("ok", false) and sample.get("finite_fuel", false) and sample.get("stores", []).size() == 1
			and is_equal_approx(float(sample.stores[0].capacity_kg), frozen_tank.capacity_kg)
			and is_equal_approx(float(sample.stores[0].fill_fraction), session.fuel_start_fill)
			and is_equal_approx(float(sample.fuel_remaining_kg), frozen_tank.capacity_kg * session.fuel_start_fill),
			str({sample = sample, session_fill = session.fuel_start_fill,
				tank_capacity = frozen_tank.capacity_kg, start = session.start}))
	session.free()


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
		if synthetic.balance.has("cg_range"):
			synthetic.balance.cg_range.forward.value += offset
			synthetic.balance.cg_range.aft.value += offset
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
			# FUEL-11a: the dry (empty-tank) CG scales with the airframe; the tank keeps its fill, so the datum may not.
			_check("shifted dry CG scales from each unfamiliar base %02d" % index,
				is_equal_approx(_dry_cg_x(compiled.raw), _dry_cg_x(synthetic) * scale)
				and is_equal_approx(compiled.raw.balance.plan_cg.value[0], synthetic.balance.plan_cg.value[0] * scale))
	_check("twenty unfamiliar IDs compile through the generic path", successful == 20, str(successful))


func _test_catalog_registry() -> void:
	var entries: Array = Catalog.airplane_flyable_entries()
	var count := 0
	var probes := {
		"scale": {"scale": 1.1},
		"weight": {"weight_multiplier": 1.1},
		"power": {"power_multiplier": 1.1},
		"controls": {"control_multiplier": 1.1},
		"tank_capacity": {"tank_capacity_multiplier": 1.1},
	}
	for entry: Dictionary in entries:
		var aircraft_id := str(entry.get("id", ""))
		var raw: Dictionary = _read(str(entry.get("data", "")))
		if raw.is_empty():
			continue
		count += 1
		var support: Dictionary = Compiler.capabilities(raw)
		_check("catalog capability record %s has adjustment flags and a note" % aircraft_id,
			support.has_all(["scale", "weight", "power", "controls", "tank_capacity", "note"]))
		for flag: String in ["scale", "weight", "power", "controls", "tank_capacity"]:
			_check("catalog capability %s is boolean for %s" % [flag, aircraft_id], typeof(support.get(flag)) == TYPE_BOOL)
		var custom_id := "workshop-catalog-probe-%02d" % count
		var renamed: Dictionary = raw.duplicate(true)
		renamed.id = custom_id
		var renamed_support: Dictionary = Compiler.capabilities(renamed)
		_check("capability selection is unchanged when catalog ID changes %s" % aircraft_id,
			_support_flags_equal(support, renamed_support))
		var no_op: Dictionary = Compiler.compile(raw, {"id": custom_id})
		_check("catalog no-op works with a trial identity %s" % aircraft_id, no_op.ok, str(no_op.errors))
		if no_op.ok:
			_check("catalog no-op effective model identity %s" % aircraft_id, no_op.data.model.id == custom_id)
			var base_data: Dictionary = AircraftData.validate_and_derive(raw)
			var profiled_base: Dictionary = WheelProfiles.apply_to_model(base_data.model)
			_check("catalog no-op physics matches base for %s" % aircraft_id,
				profiled_base.ok and _physics_projection(no_op.data.model) == _physics_projection(profiled_base.model))
			_check("catalog no-op preserves base wheel runtime status for %s" % aircraft_id,
				no_op.data.model.get("wheel_profile", {}).get("status", "") == profiled_base.model.get("wheel_profile", {}).get("status", "")
				and no_op.data.model.get("wheel_profile", {}).get("base_aircraft_id", "") == str(raw.get("id", "")))
		for capability: String in probes:
			if support[capability]:
				continue
			var refused: Dictionary = Compiler.compile(raw, probes[capability])
			_check("unsupported %s recipe refuses clearly for %s" % [capability, aircraft_id],
				not refused.ok and str(refused.errors).contains(capability))
	_check("catalog registry inspected every fixed-wing flyable aircraft", count == entries.size(), str(count))


func _test_recipe_validation(base: Dictionary) -> void:
	var unknown: Dictionary = Compiler.compile(base, {"magic": 1.0})
	_check("unknown recipe keys are rejected", not unknown.ok and str(unknown.errors).contains("unknown key"))
	var nonfinite: Dictionary = Compiler.compile(base, {"scale": NAN})
	_check("nonfinite recipe values are rejected", not nonfinite.ok and str(nonfinite.errors).contains("finite"))
	var tank_capacity_bounds: Dictionary = Compiler.compile(base, {"tank_capacity_multiplier": 2.01})
	_check("tank capacity multiplier above the explicit estimate range is rejected",
		not tank_capacity_bounds.ok and str(tank_capacity_bounds.errors).contains("tank_capacity_multiplier"))
	var omitted_capacity: Dictionary = Compiler.defaults()
	omitted_capacity.erase("tank_capacity_multiplier")
	var defaulted_capacity: Dictionary = Compiler.compile(base, omitted_capacity)
	_check("legacy recipe without optional tank capacity keeps the exact no-op model",
		defaulted_capacity.ok and defaulted_capacity.data.model.mass_kg == AircraftData.validate_and_derive(base).model.mass_kg)
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


## x of the inventory CG without the declared tanks' liquid.
func _dry_cg_x(raw: Dictionary) -> float:
	var liquid := {}
	for tank: Dictionary in raw.get("fuel_system", {}).get("tanks", []):
		liquid[tank.liquid_inventory_id] = true
	var mass := 0.0
	var first := 0.0
	for item: Dictionary in raw.inventory:
		if not liquid.has(item.get("id", "")):
			mass += float(item.mass.value)
			first += float(item.mass.value) * float(item.position.value[0])
	return first / mass


## Total liquid of the declared tanks (0 without a fuel system).
func _liquid_kg(model: Dictionary) -> float:
	var total := 0.0
	for tank: Dictionary in model.get("fuel_system", {}).get("tanks", []):
		total += float(tank.liquid_mass_kg)
	return total


## FUEL-11a: the tank volume and residue scale by s³ and keep their fill; the propeller hub stays structural (× s)
## about whatever datum the scaled inventory produces.
func _tank_follows_airframe(base_model: Dictionary, model: Dictionary, s: float, label: String) -> void:
	var base_tank: Dictionary = base_model.fuel_system.tanks[0]
	var tank: Dictionary = model.fuel_system.tanks[0]
	_check("%s: the tank scales by s³ and keeps its fill" % label,
		is_equal_approx(tank.capacity_m3, base_tank.capacity_m3 * s * s * s)
		and is_equal_approx(tank.unusable_kg, base_tank.unusable_kg * s * s * s)
		and is_equal_approx(tank.start_fill, base_tank.start_fill), "%s vs %s" % [tank.start_fill, base_tank.start_fill])
	var hub_ok := true
	for k in 3:
		var base_hub: float = base_model.cg_le[k] + base_model.propulsion.offset[k]
		hub_ok = hub_ok and absf(model.cg_le[k] + model.propulsion.offset[k] - s * base_hub) < 1e-12
	_check("%s: the propeller hub is structural geometry × s, re-referenced to the compiled datum" % label, hub_ok)


## Independent inertia of the FUEL-11a law: every inventory box about the compiled CG.
func _inertia_by_law(base: Dictionary, s: float, ratio: float) -> PackedFloat64Array:
	var liquid := {}
	for tank: Dictionary in base.fuel_system.tanks:
		liquid[tank.liquid_inventory_id] = true
	var parts: Array = []
	var mass := 0.0
	var first := PackedFloat64Array([0.0, 0.0, 0.0])
	for item: Dictionary in base.inventory:
		var m: float = float(item.mass.value) * (s * s * s if liquid.has(item.id) else ratio)
		var position := PackedFloat64Array()
		var size := PackedFloat64Array()
		for k in 3:
			position.append(float(item.position.value[k]) * s)
			size.append(float(item.get("size", {}).get("value", [0.0, 0.0, 0.0])[k]) * s)
		parts.append([m, position, size])
		mass += m
		for k in 3:
			first[k] += m * position[k]
	return AircraftData.inertia_about(parts, PackedFloat64Array([first[0] / mass, first[1] / mass, first[2] / mass]))


func _array_ratio_is(actual: PackedFloat64Array, base: PackedFloat64Array, ratio: float) -> bool:
	if actual.size() != base.size():
		return false
	for index: int in actual.size():
		if not is_equal_approx(actual[index], base[index] * ratio):
			return false
	return true


func _inventory_by_id(inventory: Array, item_id: String) -> Dictionary:
	for item: Variant in inventory:
		if item is Dictionary and str(item.get("id", "")) == item_id:
			return item
	return {}


func _support_flags_equal(left: Dictionary, right: Dictionary) -> bool:
	for flag: String in ["scale", "weight", "power", "controls", "tank_capacity"]:
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
