extends SceneTree

const AircraftModules := preload("res://physics/aircraft_modules.gd")

var _checks := 0
var _failures := 0
var _parity_rows: Dictionary = {}


func _initialize() -> void:
	_test_sources()
	_test_law_selection()
	_test_rejections()
	print("Aircraft modules: %d checks, %d failures" % [_checks, _failures])
	if OS.get_cmdline_user_args().has("--emit-parity-json"):
		print("AS07_PARITY_JSON=" + JSON.stringify(_parity_rows))
	quit(1 if _failures > 0 else 0)


func _test_sources() -> void:
	var files: PackedStringArray = DirAccess.get_files_at("res://data/aircraft")
	var count := 0
	for file: String in files:
		if not file.ends_with(".json"):
			continue
		var path := "res://data/aircraft/" + file
		var base: Dictionary = _read(path)
		if base.is_empty():
			_check("source parses: " + file, false)
			continue
		# Rotorcraft have their own loader and module contract.
		if base.get("vehicle", "") == "rotorcraft":
			continue
		count += 1
		var result: Dictionary = AircraftModules.classify(base)
		_check("source classification succeeds: " + str(base.get("id", file)), result.ok, str(result.errors))
		if result.ok:
			_parity_rows[str(base.id)] = _parity_projection(result)
			var descriptor_path := "res://data/workshop/" + str(base.id) + ".json"
			if FileAccess.file_exists(descriptor_path):
				var descriptor: Dictionary = _read(descriptor_path)
				_check("legacy descriptor modules remain stable: " + str(base.id),
					result.modules == descriptor.get("modules", []), str(result.modules))
	_check("all checked-in v2 sources classified", count >= 10, str(count))


func _test_law_selection() -> void:
	var p51: Dictionary = _classify_path("res://data/aircraft/p51d_mustang_120.json")
	_check("P-51 identifies the coupled shaft law", p51.ok and p51.laws.has("propulsion.glow_prop.shaft_balance.v1"))
	_check("P-51 normal-force law remains explicit", p51.ok and p51.laws.has("propeller.normal_force.v1"))
	_check("P-51 keeps the legacy shaft module ID", p51.ok and p51.modules.has("propulsion.shaft.v1"))
	_check("shaft law leaves virtual transforms unsupported", p51.ok and not p51.compiler_transforms.scale and not p51.compiler_transforms.power)

	var glow_2t: Dictionary = _classify_path("res://data/aircraft/stik_glow_55ax_2t.json")
	var glow_4t: Dictionary = _classify_path("res://data/aircraft/stik_glow_fs64v_4t.json")
	_check("2T installation is classified as finite glow", glow_2t.ok
		and glow_2t.laws.has("propulsion.glow_prop.finite_glow_installation.v1")
		and glow_2t.modules.has("installation.glow.v1"))
	_check("4T installation uses the same explicit installation law", glow_4t.ok
		and glow_4t.laws.has("propulsion.glow_prop.finite_glow_installation.v1"))

	var fixed: Dictionary = _classify_path("res://data/aircraft/synthetic_stik_electric_4s.json")
	var ocv: Dictionary = _classify_path("res://data/aircraft/synthetic_stik_electric_4s_battery.json")
	_check("fixed voltage selects its distinct battery law", fixed.ok and fixed.laws.has("energy.battery.fixed_voltage.v1"))
	_check("finite battery selects its distinct OCV law", ocv.ok and ocv.laws.has("energy.battery.ocv_resistance.v1"))
	_check("electric propulsion keeps scale and power transforms disabled", fixed.ok
		and not fixed.compiler_transforms.scale and not fixed.compiler_transforms.power)

	var turbine_base: Dictionary = _read("res://data/aircraft/sebart_avanti_s_a200.json")
	var turbine: Dictionary = AircraftModules.classify(turbine_base)
	_check("turbine selects RK4 spool law", turbine.ok and turbine.laws.has("propulsion.turbine.spool.rk4.v1"))
	var sampled_base: Dictionary = turbine_base.duplicate(true)
	sampled_base.propulsion.engine.erase("spool_integrator")
	var sampled: Dictionary = AircraftModules.classify(sampled_base)
	_check("omitted turbine integrator normalizes to sampled law", sampled.ok
		and sampled.laws.has("propulsion.turbine.spool.sampled.v1")
		and sampled.parameters.get("propulsion.engine.spool_integrator") == "sampled")


func _test_rejections() -> void:
	var valid: Dictionary = _read("res://data/aircraft/jensen_ugly_stik_60.json")
	var wrong_version: Dictionary = valid.duplicate(true)
	wrong_version.format = "openrc-aircraft v99"
	_assert_rejected(wrong_version, "unknown aircraft version", "module.source.version")
	_record_parity("invalid:version", wrong_version)

	var unknown_capability: Dictionary = valid.duplicate(true)
	unknown_capability.capabilities.gear = "retractable"
	_assert_rejected(unknown_capability, "unknown capability value", "module.capability.unknown")
	_record_parity("invalid:capability_value", unknown_capability)
	var unknown_capability_field: Dictionary = valid.duplicate(true)
	unknown_capability_field.capabilities.extra = "enabled"
	_assert_rejected(unknown_capability_field, "unknown capability field", "module.capability.unknown_field")
	var typed_capability: Dictionary = valid.duplicate(true)
	typed_capability.capabilities.energy = true
	_assert_rejected(typed_capability, "capability selector is not coerced from bool", "module.capability.type")

	var unknown_family: Dictionary = valid.duplicate(true)
	unknown_family.propulsion.kind = "hybrid_prop"
	_assert_rejected(unknown_family, "unknown propulsion module", "module.propulsion.kind.unknown")
	var unknown_module_field: Dictionary = valid.duplicate(true)
	unknown_module_field.propulsion.engine.future_module = {}
	_assert_rejected(unknown_module_field, "unknown propulsion module field", "module.field.unknown")
	_record_parity("invalid:module_field", unknown_module_field)

	var glow_energy_mismatch: Dictionary = valid.duplicate(true)
	glow_energy_mismatch.capabilities.energy = "finite_glow_fuel"
	_assert_rejected(glow_energy_mismatch, "finite glow requires installation data", "module.relation.invalid")
	var shaft_and_install: Dictionary = valid.duplicate(true)
	shaft_and_install.propulsion.engine.shaft = {"friction_torque": {}}
	shaft_and_install.propulsion.engine.glow_installation = "res://data/glow/example.json"
	shaft_and_install.capabilities.energy = "finite_glow_fuel"
	_assert_rejected(shaft_and_install, "shaft and glow installation cannot be combined", "module.relation.invalid")

	var fixed_battery_mismatch: Dictionary = _read("res://data/aircraft/synthetic_stik_electric_4s.json")
	fixed_battery_mismatch.capabilities.energy = "ocv_resistance"
	_assert_rejected(fixed_battery_mismatch, "battery and energy capability must agree", "module.relation.battery_energy")
	_record_parity("invalid:battery_relation", fixed_battery_mismatch)
	var unknown_integrator: Dictionary = _read("res://data/aircraft/sebart_avanti_s_a200.json")
	unknown_integrator.propulsion.engine.spool_integrator = "semi_implicit"
	_assert_rejected(unknown_integrator, "unknown turbine integrator", "module.turbine.integrator.unknown")
	_record_parity("invalid:turbine_integrator", unknown_integrator)
	var missing_contacts: Dictionary = _read("res://data/aircraft/sebart_avanti_s_a200.json")
	missing_contacts.capabilities.gear = "fixed_tricycle"
	_assert_rejected(missing_contacts, "deployed gear capability requires contact data", "module.capability.relation")
	_record_parity("invalid:gear_relation", missing_contacts)


func _classify_path(path: String) -> Dictionary:
	return AircraftModules.classify(_read(path))


func _read(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _assert_rejected(base: Dictionary, label: String, code: String) -> void:
	var result: Dictionary = AircraftModules.classify(base)
	_check(label + " is rejected", not result.ok, str(result.errors))
	_check(label + " returns its diagnostic", _has_diagnostic(result.diagnostics, code), str(result.diagnostics))
	_check(label + " returns no partial classifications", result.modules.is_empty() and result.laws.is_empty())


func _has_diagnostic(diagnostics: Array, code: String) -> bool:
	for diagnostic_variant: Variant in diagnostics:
		if typeof(diagnostic_variant) == TYPE_DICTIONARY and diagnostic_variant.get("code") == code:
			return true
	return false


func _parity_projection(result: Dictionary) -> Dictionary:
	return {
		"ok": result.ok,
		"errors": result.errors,
		"diagnostics": result.diagnostics,
		"modules": result.modules,
		"laws": result.laws,
		"parameters": result.parameters,
		"compiler_transforms": result.compiler_transforms,
		"compiler_transform_reasons": result.compiler_transform_reasons,
	}


func _record_parity(key: String, base: Dictionary) -> void:
	_parity_rows[key] = _parity_projection(AircraftModules.classify(base))


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])
