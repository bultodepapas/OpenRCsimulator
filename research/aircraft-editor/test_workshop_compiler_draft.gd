extends SceneTree

const AircraftData := preload("../../app/physics/aircraft_data.gd")
const Compiler := preload("compiler.gd")
const Session := preload("../../app/sim/flight_session.gd")
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
	_test_power_and_controls(stik)
	_test_unfamiliar_identity(stik)
	_test_catalog_registry()
	_test_scaled_flight(stik, "Stik")
	_test_scaled_flight(extra, "Extra")
	print("Workshop compiler draft: %d checks, %d failures" % [_checks, _failures])
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
	_check("%s no-op inherits base wheel profile" % label,
		result.ok and result.data.model.get("wheel_profile", {}).get("base_aircraft_id", "") == base.id)


func _test_scale_policies(base: Dictionary) -> void:
	var base_data: Dictionary = AircraftData.validate_and_derive(base)
	var mini: Dictionary = Compiler.compile(base, {"scale": 0.5})
	_check("50% constant-wing-loading recipe validates", mini.ok, str(mini.errors))
	if mini.ok:
		_check("50% scale multiplies lengths by 0.5", is_equal_approx(mini.raw.reference.wing_span.value, base.reference.wing_span.value * 0.5))
		_check("50% scale multiplies area by 0.25", is_equal_approx(mini.raw.reference.wing_area.value, base.reference.wing_area.value * 0.25))
		_check("50% scale keeps wing loading", is_equal_approx(mini.data.model.mass_kg / mini.data.model.reference.S,
			base_data.model.mass_kg / base_data.model.reference.S))
		_check("mass range scales as a consistency band", is_equal_approx(mini.raw.plausibility.mass_range.value[0], base.plausibility.mass_range.value[0] * 0.25))
		_check("small model gear keeps base heave frequency policy",
			is_equal_approx(mini.data.model.landing_gear.heave_omega, base_data.model.landing_gear.heave_omega))
		_check("wheel radius scales while spin relaxation is retained",
			is_equal_approx(mini.data.model.landing_gear.contacts[0].wheel_radius,
				base_data.model.landing_gear.contacts[0].wheel_radius * 0.5)
			and mini.data.model.landing_gear.contacts[0].spin_relaxation == base_data.model.landing_gear.contacts[0].spin_relaxation)
		_check("changed inventory evidence is derived", mini.raw.inventory[0].mass.kind == "derived"
			and "Workshop compiler v1" in mini.raw.inventory[0].mass.source)
	var geometric: Dictionary = Compiler.compile(base, {"scale": 2.0, "mass_policy": "geometric"})
	_check("200% geometric recipe validates", geometric.ok, str(geometric.errors))
	if geometric.ok:
		var expected_ratio := 8.0
		_check("geometric mass ratio is s cubed", is_equal_approx(geometric.data.model.mass_kg / base_data.model.mass_kg, expected_ratio))
		_check("geometric area and inertia use their own dimensions",
			is_equal_approx(geometric.data.model.reference.S / base_data.model.reference.S, 4.0)
			and is_equal_approx(geometric.data.model.inertia[0] / base_data.model.inertia[0], 32.0))
		_check("mass range remains inside original loader domain",
			geometric.raw.plausibility.mass_range.value[0] >= 0.01
			and geometric.raw.plausibility.mass_range.value[1] <= 100.0)


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
	var clipped: Dictionary = Compiler.compile(base, {"scale": 2.01})
	_check("scale above the V1 bound is rejected", not clipped.ok and not clipped.errors.is_empty())


func _test_unfamiliar_identity(base: Dictionary) -> void:
	var pre_scaled: Dictionary = Compiler.compile(base, {"scale": 1.1})
	_check("synthetic dimension seed compiles", pre_scaled.ok, str(pre_scaled.errors))
	if not pre_scaled.ok:
		return
	var synthetic: Dictionary = pre_scaled.raw.duplicate(true)
	synthetic.id = "unfamiliar-aircraft-7f20"
	for component_variant: Variant in synthetic.inventory:
		var position: Array = component_variant.position.value
		position[0] += 0.007
	synthetic.inventory.reverse()
	synthetic.balance.plan_cg.value[0] += 0.007
	synthetic.balance.firewall.value[0] += 0.007
	synthetic.reference.aero_reference_point.value[0] += 0.007
	for surface_key: String in ["horizontal", "vertical"]:
		synthetic.aero.surfaces[surface_key].position.value[0] += 0.007
	for point: Array in synthetic.crash_hull.value:
		point[0] += 0.007
	for contact: Dictionary in synthetic.landing_gear.contacts:
		contact.position.value[0] += 0.007
	var candidate_check: Dictionary = AircraftData.validate_and_derive(synthetic)
	_check("unfamiliar-base fixture is valid after CG/datum and inventory-order change", candidate_check.ok, str(candidate_check.errors))
	var compiled: Dictionary = Compiler.compile(synthetic, {"id": "variant-unfamiliar-output", "scale": 1.25})
	_check("compiler uses module shape for unfamiliar IDs", compiled.ok, str(compiled.errors))
	if compiled.ok:
		_check("effective ID is carried by raw and derived model", compiled.raw.id == "variant-unfamiliar-output"
			and compiled.data.model.id == "variant-unfamiliar-output")
		_check("new CG is scaled from the unfamiliar base", is_equal_approx(
			compiled.data.model.cg_le[0], candidate_check.model.cg_le[0] * 1.25))
		_check("inventory ordering does not select an aircraft branch", compiled.data.model.mass_kg > 0.0)


func _test_catalog_registry() -> void:
	var files: PackedStringArray = DirAccess.get_files_at("res://data/aircraft")
	var count := 0
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
		var no_op: Dictionary = Compiler.compile(raw, {"id": custom_id})
		_check("catalog no-op works with a trial identity %s" % raw.get("id", file), no_op.ok, str(no_op.errors))
		if no_op.ok:
			_check("catalog no-op effective model identity %s" % raw.get("id", file), no_op.data.model.id == custom_id)
	_check("catalog registry inspected current aircraft files", count >= 7, str(count))


func _test_scaled_flight(base: Dictionary, label: String) -> void:
	for scale_value: float in [0.5, 1.0, 2.0]:
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
		_check("%s %.0f%% session prepares a trim" % [label, scale_value * 100.0], session.aircraft.get("ok", false),
			str(session.start.get("message", "")))
		if session.aircraft.get("ok", false):
			var finite_state := true
			for tick: int in 240:
				session.sim.step()
				for value: float in session.sim.state:
					finite_state = finite_state and is_finite(value)
			_check("%s %.0f%% remains finite for 240 steps" % [label, scale_value * 100.0], finite_state)
		session.free()


func _static_power(model: Dictionary) -> float:
	var prop: Dictionary = model.propulsion
	var rpm: float = float(prop.max_rpm) / 60.0
	var cp: PackedFloat64Array = prop.cp
	return float(cp[1]) * 1.225 * pow(rpm, 3.0) * pow(float(prop.diameter), 5.0)
