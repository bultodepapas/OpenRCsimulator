extends SceneTree

const Profile := preload("res://physics/glow/profile.gd")
const Source := preload("res://physics/glow/source.gd")
const Lifecycle := preload("res://physics/glow/lifecycle.gd")

var _checks := 0
var _failures := 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL %s%s" % [label, " — " + detail if not detail.is_empty() else ""])


func _initialize() -> void:
	for id: String in ["os_max_55ax_candidate", "os_fs_64v_candidate"]:
		var loaded: Dictionary = Profile.load_file("res://data/glow/" + id + ".json")
		_check(id + " candidate loads", loaded.get("ok", false))
		if not loaded.get("ok", false):
			continue
		var model: Dictionary = loaded.model.duplicate(true)
		var settings: Dictionary = Lifecycle.candidate_settings_for_tests(str(model.family))
		var source_setup: Dictionary = Source.prepare_evaluator(model)
		var lifecycle_setup: Dictionary = Lifecycle.prepare_evaluator(model, settings)
		_check(id + " source evaluator prepares", source_setup.get("ok", false), str(source_setup.get("message", "")))
		_check(id + " lifecycle evaluator prepares", lifecycle_setup.get("ok", false), str(lifecycle_setup.get("message", "")))
		if not source_setup.get("ok", false) or not lifecycle_setup.get("ok", false):
			continue
		var source_evaluator: Source.PreparedEvaluator = source_setup.evaluator
		var lifecycle_evaluator: Lifecycle.PreparedEvaluator = lifecycle_setup.evaluator
		_test_snapshot_is_read_only(id, source_evaluator, lifecycle_evaluator)
		_test_source_parity(id, model, source_evaluator)
		_test_lifecycle_parity(id, model, settings, lifecycle_evaluator)
		_test_dynamic_refusals(id, model, settings, lifecycle_evaluator)
		_test_unsupported_mixture(id, model, settings, source_evaluator, lifecycle_evaluator)
		_test_provenance_rejection(id, model)
		_test_snapshot_detachment(id, model, settings, lifecycle_evaluator)
	print("NITRO prepared evaluator: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _test_snapshot_is_read_only(id: String, source: Source.PreparedEvaluator,
		lifecycle: Lifecycle.PreparedEvaluator) -> void:
	_check(id + " source snapshot root is read-only", source._model.is_read_only())
	_check(id + " source parameters are read-only", source._parameters.is_read_only())
	_check(id + " source provenance dictionary is read-only", source._model.provenance.is_read_only())
	_check(id + " source provenance table array is read-only",
		source._model.provenance.parameters.mechanical_torque_nm.value.is_read_only())
	_check(id + " source provenance table row is read-only",
		source._model.provenance.parameters.mechanical_torque_nm.value[0].is_read_only())
	_check(id + " lifecycle model is read-only", lifecycle._model.is_read_only())
	_check(id + " lifecycle settings are read-only", lifecycle._settings.is_read_only())
	_check(id + " nested thermal settings are read-only", lifecycle._settings.thermal.is_read_only())


func _test_source_parity(id: String, model: Dictionary,
		evaluator: Source.PreparedEvaluator) -> void:
	var operation: Dictionary = model.operation
	for rpm: float in [0.0, 2400.0, float(operation.rated_rpm), float(operation.max_rpm)]:
		for admission: float in [0.0, 1.0]:
			for mixture: float in [0.0, float(operation.nominal_mixture)]:
				for running: bool in [false, true]:
					var direct: Dictionary = Source.evaluate(model, rpm, admission, mixture, 1.225, running, 0.73)
					var prepared: Dictionary = Source.evaluate_prepared(evaluator, rpm, admission, mixture, 1.225, running, 0.73)
					_check(id + " source exact parity %s" % str([rpm, admission, mixture, running]),
						direct == prepared,
						"direct=" + JSON.stringify(direct) + " prepared=" + JSON.stringify(prepared))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261013 if id == "os_max_55ax_candidate" else 20261014
	var rpm_table: PackedFloat64Array = model.parameters.mechanical_torque_nm
	var mixture_table: PackedFloat64Array = model.parameters.combustion_efficiency
	var rpm_min: float = rpm_table[0]
	var rpm_span: float = rpm_table[rpm_table.size() - 2] - rpm_min
	var mixture_min: float = mixture_table[0]
	var mixture_span: float = mixture_table[mixture_table.size() - 2] - mixture_min
	for query_index: int in range(100):
		var rpm: float = rpm_min + rpm_span * (0.01 + 0.98 * rng.randf())
		var admission: float = rng.randf()
		var mixture: float = mixture_min + mixture_span * rng.randf()
		var density: float = 0.45 + 1.35 * rng.randf()
		var running: bool = (query_index % 3) != 0
		var firing_fraction: float = rng.randf()
		var direct: Dictionary = Source.evaluate(model, rpm, admission, mixture, density,
			running, firing_fraction)
		var prepared: Dictionary = Source.evaluate_prepared(evaluator, rpm, admission, mixture,
			density, running, firing_fraction)
		_check(id + " source seeded interior query %d succeeds and matches exactly" % query_index,
			direct.get("ok", false) and prepared.get("ok", false) and direct == prepared,
			"direct=" + JSON.stringify(direct) + " prepared=" + JSON.stringify(prepared))


func _test_lifecycle_parity(id: String, model: Dictionary, settings: Dictionary,
		evaluator: Lifecycle.PreparedEvaluator) -> void:
	var operation: Dictionary = model.operation
	var created: Dictionary = Lifecycle.create(model, settings, 0.02, 390.0, 6000.0, true)
	_check(id + " lifecycle state creates", created.get("ok", false))
	if not created.get("ok", false):
		return
	var initial: Dictionary = created.state
	for rpm: float in [0.0, 6000.0, float(operation.rated_rpm)]:
		for throttle: float in [0.0, 1.0]:
			for command_mixture: float in [0.0, float(operation.nominal_mixture)]:
				for temperature: float in [300.0, 390.0, 560.0]:
					var values: PackedFloat64Array = Lifecycle.pack_state(initial)
					values[1] = temperature
					values[2] = 0.3
					values[3] = 0.4
					values[4] = initial.fuel_transport_kg_s * 0.8
					var stage: Dictionary = Lifecycle.with_continuous_state(initial, values)
					var direct: Dictionary = Lifecycle.evaluate(model, settings, stage, rpm, throttle,
						command_mixture, 1.225, 295.0, 12.0)
					var prepared: Dictionary = Lifecycle.evaluate_prepared(evaluator, stage, rpm, throttle,
						command_mixture, 1.225, 295.0, 12.0)
					_check(id + " lifecycle exact parity %s" % str([rpm, throttle, command_mixture, temperature]),
						direct == prepared,
						"direct=" + JSON.stringify(direct) + " prepared=" + JSON.stringify(prepared))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261023 if id == "os_max_55ax_candidate" else 20261024
	var rpm_table: PackedFloat64Array = model.parameters.mechanical_torque_nm
	var rpm_min: float = rpm_table[0]
	var rpm_span: float = rpm_table[rpm_table.size() - 2] - rpm_min
	for query_index: int in range(100):
		var rpm: float = rpm_min + 1.0 + maxf(0.0, rpm_span - 1.0) * rng.randf()
		var throttle: float = rng.randf()
		var command_mixture: float = 2.5 * rng.randf()
		var baseline_mixture: float = command_mixture if command_mixture > 0.0 else float(operation.nominal_mixture)
		var admission: float = 0.05 + 0.95 * rng.randf()
		var density: float = 0.45 + 1.35 * rng.randf()
		var unit_source: Dictionary = Source.evaluate(model, rpm, admission, baseline_mixture,
			density, true, 1.0)
		if not unit_source.get("ok", false):
			_check(id + " lifecycle seeded target flow %d is supported" % query_index, false,
				str(unit_source.get("message", "unknown source error")))
			continue
		var unit_flow: float = float(unit_source.delivered_fuel_kg_s) / baseline_mixture
		var values: PackedFloat64Array = Lifecycle.pack_state(initial)
		values[0] = 0.005 + 0.025 * rng.randf()
		values[1] = 260.0 + 330.0 * rng.randf()
		values[2] = rng.randf()
		values[3] = admission
		values[4] = unit_flow * (3.0 * rng.randf())
		values[5] = 2.0 * rng.randf()
		var stage: Dictionary = Lifecycle.with_continuous_state(initial, values)
		var ambient: float = 250.0 + 70.0 * rng.randf()
		var cooling_speed: float = 40.0 * rng.randf()
		var direct: Dictionary = Lifecycle.evaluate(model, settings, stage, rpm, throttle,
			command_mixture, density, ambient, cooling_speed)
		var prepared: Dictionary = Lifecycle.evaluate_prepared(evaluator, stage, rpm, throttle,
			command_mixture, density, ambient, cooling_speed)
		_check(id + " lifecycle seeded interior query %d succeeds and matches exactly" % query_index,
			direct.get("ok", false) and prepared.get("ok", false) and direct == prepared,
			"direct=" + JSON.stringify(direct) + " prepared=" + JSON.stringify(prepared))


func _test_dynamic_refusals(id: String, model: Dictionary, settings: Dictionary,
		evaluator: Lifecycle.PreparedEvaluator) -> void:
	var created: Dictionary = Lifecycle.create(model, settings, 0.02, 390.0, 6000.0, true)
	if not created.get("ok", false):
		return
	var state: Dictionary = created.state
	var invalid_throttle: Dictionary = Lifecycle.evaluate_prepared(evaluator, state,
		6000.0, -0.01, 1.15, 1.225, 295.0, 10.0)
	var invalid_mixture: Dictionary = Lifecycle.evaluate_prepared(evaluator, state,
		6000.0, 0.5, INF, 1.225, 295.0, 10.0)
	var outside_rpm: Dictionary = Lifecycle.evaluate_prepared(evaluator, state,
		float(model.operation.max_rpm) + 1.0, 0.5, 1.15, 1.225, 295.0, 10.0)
	var invalid_temperature: Dictionary = Lifecycle.evaluate_prepared(evaluator, state,
		6000.0, 0.5, 1.15, 1.225, 0.0, 10.0)
	_check(id + " rejects negative throttle", not invalid_throttle.get("ok", false))
	_check(id + " rejects nonfinite mixture", not invalid_mixture.get("ok", false))
	_check(id + " rejects out-of-envelope RPM", not outside_rpm.get("ok", false))
	_check(id + " rejects invalid ambient temperature", not invalid_temperature.get("ok", false))


func _test_unsupported_mixture(id: String, model: Dictionary, settings: Dictionary,
		source_evaluator: Source.PreparedEvaluator,
		lifecycle_evaluator: Lifecycle.PreparedEvaluator) -> void:
	var mixture_table: PackedFloat64Array = model.parameters.combustion_efficiency
	var unsupported_mixture: float = mixture_table[mixture_table.size() - 2] + 1.0
	var density: float = float(model.operation.reference_dry_density_kg_m3)
	var direct_source: Dictionary = Source.evaluate(model, 6000.0, 0.7, unsupported_mixture,
		density, true, 1.0)
	var prepared_source: Dictionary = Source.evaluate_prepared(source_evaluator, 6000.0, 0.7,
		unsupported_mixture, density, true, 1.0)
	_check(id + " direct and prepared source reject unsupported mixture",
		not direct_source.get("ok", false) and not prepared_source.get("ok", false))
	var created: Dictionary = Lifecycle.create(model, settings, 0.02, 390.0, 6000.0, true)
	if not created.get("ok", false):
		_check(id + " unsupported lifecycle mixture fixture creates", false)
		return
	var direct_lifecycle: Dictionary = Lifecycle.evaluate(model, settings, created.state,
		6000.0, 0.7, unsupported_mixture, density, 295.0, 10.0)
	var prepared_lifecycle: Dictionary = Lifecycle.evaluate_prepared(lifecycle_evaluator,
		created.state, 6000.0, 0.7, unsupported_mixture, density, 295.0, 10.0)
	_check(id + " direct and prepared lifecycle reject unsupported mixture",
		not direct_lifecycle.get("ok", false) and not prepared_lifecycle.get("ok", false),
		"direct=" + JSON.stringify(direct_lifecycle) + " prepared=" + JSON.stringify(prepared_lifecycle))
	var extreme_values: PackedFloat64Array = Lifecycle.pack_state(created.state)
	extreme_values[3] = 1.0e-8
	extreme_values[4] = 1.0e-3
	var extreme_state: Dictionary = Lifecycle.with_continuous_state(created.state, extreme_values)
	var extreme_direct: Dictionary = Lifecycle.evaluate(model, settings, extreme_state,
		6000.0, 0.7, float(model.operation.nominal_mixture), density, 295.0, 10.0)
	var extreme_prepared: Dictionary = Lifecycle.evaluate_prepared(lifecycle_evaluator,
		extreme_state, 6000.0, 0.7, float(model.operation.nominal_mixture), density, 295.0, 10.0)
	_check(id + " direct and prepared reject a rich actual mixture at near-closed air",
		not extreme_direct.get("ok", false) and not extreme_prepared.get("ok", false)
			and str(extreme_direct.get("message", "")).contains("combustion_efficiency")
			and str(extreme_prepared.get("message", "")).contains("combustion_efficiency"),
		"direct=" + JSON.stringify(extreme_direct) + " prepared=" + JSON.stringify(extreme_prepared))


func _test_snapshot_detachment(id: String, model: Dictionary, settings: Dictionary,
		evaluator: Lifecycle.PreparedEvaluator) -> void:
	var created: Dictionary = Lifecycle.create(model, settings, 0.02, 390.0, 6000.0, true)
	if not created.get("ok", false):
		return
	var state: Dictionary = created.state
	var reference: Dictionary = Lifecycle.evaluate(model, settings, state, 6000.0, 0.5,
		float(model.operation.nominal_mixture), 1.225, 295.0, 10.0)
	model.parameters.displacement_m3 = float(model.parameters.displacement_m3) * 1.25
	settings.thermal.heat_capacity_j_k = float(settings.thermal.heat_capacity_j_k) * 1.5
	var detached: Dictionary = Lifecycle.evaluate_prepared(evaluator, state, 6000.0, 0.5,
		float(evaluator._model.operation.nominal_mixture), 1.225, 295.0, 10.0)
	_check(id + " prepared snapshot detaches profile and settings inputs",
		reference.get("ok", false) and reference == detached,
		"reference=" + JSON.stringify(reference) + " detached=" + JSON.stringify(detached))


func _test_provenance_rejection(id: String, model: Dictionary) -> void:
	var changed_normalized: Dictionary = model.duplicate(true)
	changed_normalized.parameters.displacement_m3 = float(changed_normalized.parameters.displacement_m3) * 1.1
	var normalized_result: Dictionary = Source.prepare_evaluator(changed_normalized)
	_check(id + " rejects normalized data changed outside provenance", not normalized_result.get("ok", false))
	var changed_provenance: Dictionary = model.duplicate(true)
	changed_provenance.provenance.parameters.displacement_m3.value = float(changed_provenance.provenance.parameters.displacement_m3.value) * 1.1
	var provenance_result: Dictionary = Source.prepare_evaluator(changed_provenance)
	_check(id + " rejects provenance changed after normalization", not provenance_result.get("ok", false))
