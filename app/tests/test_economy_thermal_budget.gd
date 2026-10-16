extends SceneTree

const ThermalBudget = preload("res://economy/thermal_budget.gd")
var _failures := 0
var _checks := 0


func _initialize() -> void:
	_test_no_source_and_no_trigger()
	_test_delayed_ignition_and_depletion()
	_test_allocations_and_remote_component()
	_test_analytic_refinement_and_cooling()
	_test_threshold_basis()
	_test_invalid_inputs_and_ticks()
	_test_duplicate_and_read_only()
	if _failures == 0:
		print("ThermalBudget tests passed: ", _checks, " checks")
		quit(0)
	else:
		push_error("ThermalBudget tests failed: %d of %d checks" % [_failures, _checks])
		quit(1)


func _test_no_source_and_no_trigger() -> void:
	var model := _model([])
	var initial := ThermalBudget.initial_state(model)
	var result := ThermalBudget.advance(model, initial.state, 0, 1.0)
	_check(result.ok, "empty source model advances")
	_check(result.source_used_j.is_empty(), "no source means no energy")
	_check(result.components[0].disposition == "inspect", "unknown threshold stays inspect")
	_check(not result.has("fire"), "budget does not imply fire")
	var dormant := _source("dormant", 100.0, 10.0, null, PackedFloat64Array([1.0]))
	var dormant_model := _model([dormant])
	var state: Variant = ThermalBudget.initial_state(dormant_model).state
	var no_trigger := ThermalBudget.advance(dormant_model, state, 0, 1.0)
	_check(no_trigger.ok, "null ignition tick advances as dormant")
	_check_close(no_trigger.source_used_j[0], 0.0, 0.0, "null ignition releases no energy")
	_check_close(no_trigger.state.temperatures_k[0], 293.15, 0.0, "dormant source leaves temperature unchanged")
	_check_close(no_trigger.state.source_remaining_j[0], 100.0, 0.0, "dormant source retains energy")


func _test_delayed_ignition_and_depletion() -> void:
	var source := _source("delayed", 2.0, 5.0, 2, PackedFloat64Array([1.0]))
	var model := _model([source])
	var state: Variant = ThermalBudget.initial_state(model).state
	for tick in range(2):
		var before := ThermalBudget.advance(model, state, tick, 1.0)
		_check(before.ok, "pre-trigger tick advances")
		_check_close(before.source_used_j[0], 0.0, 0.0, "source waits for explicit ignition tick")
		state = before.state
	var ignition := ThermalBudget.advance(model, state, 2, 1.0)
	_check(ignition.ok, "delayed ignition tick advances")
	_check_close(ignition.source_used_j[0], 2.0, 0.000000001, "source releases only remaining joules")
	_check_close(ignition.state.source_remaining_j[0], 0.0, 0.000000001, "source depletes exactly")
	_check_close(ignition.energy_balance_error_j, 0.0, 0.000001, "depletion tick conserves energy")
	var after := ThermalBudget.advance(model, ignition.state, 3, 1.0)
	_check(after.ok, "post-depletion tick advances")
	_check_close(after.source_used_j[0], 0.0, 0.0, "depleted source releases nothing")


func _test_allocations_and_remote_component() -> void:
	var source := _source("local", 20.0, 10.0, 0, PackedFloat64Array([1.0, 0.0]))
	var model := _model([source], 2, 0.5)
	var initial := ThermalBudget.initial_state(model)
	var result := ThermalBudget.advance(model, initial.state, 0, 0.5)
	_check(result.ok, "allocated source advances")
	_check(result.state.temperatures_k[0] > 293.15, "allocated component warms")
	_check_close(result.state.temperatures_k[1], 293.15, 0.0, "remote zero-share component is unchanged")
	_check_close(result.source_used_j[0], 5.0, 0.000000001, "release is bounded by power times duration")
	_check_close(result.component_input_j[0], 5.0, 0.000000001, "full share reaches allocated component")
	_check_close(result.component_input_j[1], 0.0, 0.0, "zero share delivers no remote heat")
	_check_close(result.energy_balance_error_j, 0.0, 0.000001, "component energy identity balances")
	var partial := _source("partial", 10.0, 4.0, 0, PackedFloat64Array([0.25, 0.25]))
	var partial_model := _model([partial], 2, 0.5)
	var partial_state: Variant = ThermalBudget.initial_state(partial_model).state
	var result_partial := ThermalBudget.advance(partial_model, partial_state, 0, 0.5)
	_check(result_partial.ok, "partial share allocation advances")
	_check_close(result_partial.source_unallocated_j[0], 1.0, 0.000000001, "unallocated energy remains explicit")


func _test_analytic_refinement_and_cooling() -> void:
	var source := _source("heater", 1000.0, 20.0, 0, PackedFloat64Array([1.0]))
	var model := _model([source])
	model.components[0].cooling_w_per_k = 2.0
	model.components[0].heat_capacity_j_per_k = 10.0
	var initial: Variant = ThermalBudget.initial_state(model).state
	var one := ThermalBudget.advance(model, initial, 0, 1.0)
	var rate := 0.2
	var expected_temp := 293.15 + (20.0 / 2.0) * (1.0 - exp(-rate))
	var expected_dose := (20.0 / 10.0) * (1.0 / rate - (1.0 - exp(-rate)) / (rate * rate))
	_check_close(one.state.temperatures_k[0], expected_temp, 0.000001, "temperature matches closed-form lumped model")
	_check_close(one.state.dose_k_s[0], expected_dose, 0.000001, "dose matches analytic integral")
	var fine_model := _model([source], 1, 0.1)
	fine_model.components[0].cooling_w_per_k = 2.0
	fine_model.components[0].heat_capacity_j_per_k = 10.0
	var fine_state: Variant = ThermalBudget.initial_state(fine_model).state
	for tick in range(10):
		var fine := ThermalBudget.advance(fine_model, fine_state, tick, 0.1)
		_check(fine.ok, "refined tick advances")
		fine_state = fine.state
	_check_close(fine_state.temperatures_k[0], one.state.temperatures_k[0], 0.000001, "10x tick refinement matches analytic temperature")
	_check_close(fine_state.dose_k_s[0], one.state.dose_k_s[0], 0.000001, "10x tick refinement matches analytic dose")
	_check_close(one.energy_balance_error_j, 0.0, 0.000001, "heating conserves energy")

	var cool_model := _model([])
	cool_model.components[0].initial_temperature_k = 400.0
	cool_model.components[0].cooling_w_per_k = 2.0
	cool_model.components[0].heat_capacity_j_per_k = 10.0
	var cool_state: Variant = ThermalBudget.initial_state(cool_model).state
	var cool := ThermalBudget.advance(cool_model, cool_state, 0, 1.0)
	var expected_cool := 293.15 + (400.0 - 293.15) * exp(-0.2)
	_check_close(cool.state.temperatures_k[0], expected_cool, 0.000001, "source-free cooling matches exponential reference")
	_check_close(cool.energy_balance_error_j, 0.0, 0.000001, "source-free cooling energy identity balances")


func _test_threshold_basis() -> void:
	var scenario_source := _source("threshold-source", 100.0, 100.0, 0, PackedFloat64Array([1.0]))
	var model := _model([scenario_source])
	model.components[0].damage_dose_threshold_k_s = 1.0
	model.components[0].damage_threshold_basis = "scenario_assumption"
	model.components[0].damage_threshold_provenance = "unit test branch exercise, not physical evidence"
	model.components[0].damage_disposition = "unrecoverable"
	var state: Variant = ThermalBudget.initial_state(model).state
	var scenario := ThermalBudget.advance(model, state, 0, 1.0)
	_check(scenario.ok and scenario.components[0].threshold_exceeded, "scenario threshold crossing is reported")
	_check(scenario.components[0].disposition == "inspect", "scenario threshold cannot classify unrecoverable")
	_check(scenario.declared_basis == "scenario_assumption", "aggregate basis includes scenario damage thresholds")
	var assumed_independent := _model([_source("qualified", 100.0, 100.0, 0, PackedFloat64Array([1.0]))])
	assumed_independent.components[0].parameter_basis = "independently_validated"
	assumed_independent.components[0].damage_dose_threshold_k_s = 1.0
	assumed_independent.components[0].damage_threshold_basis = "independently_validated"
	assumed_independent.components[0].damage_threshold_provenance = "unit-test API branch exercise only, not evidence"
	assumed_independent.components[0].damage_disposition = "unrecoverable"
	assumed_independent.sources[0].basis = "independently_validated"
	var qualified_state: Variant = ThermalBudget.initial_state(assumed_independent).state
	var qualified := ThermalBudget.advance(assumed_independent, qualified_state, 0, 1.0)
	_check(qualified.ok, "caller-declared qualified branch executes")
	_check(qualified.components[0].disposition == "unrecoverable", "explicit independent caller labels permit classification branch")
	_check(qualified.declared_basis == "independently_validated", "aggregate basis reports caller-declared validated inputs")
	_check(qualified.provenance_is_caller_declared_not_verified, "the module states it does not verify those labels")
	var unknown_model := _model([])
	var unknown := ThermalBudget.advance(unknown_model, ThermalBudget.initial_state(unknown_model).state, 0, 1.0)
	_check(unknown.components[0].disposition == "inspect", "unknown threshold stays inspect")


func _test_invalid_inputs_and_ticks() -> void:
	var bad_sum := _model([_source("bad-sum", 1.0, 1.0, 0, PackedFloat64Array([0.75, 0.5]))], 2)
	_check(not ThermalBudget.initial_state(bad_sum).ok, "allocation sum above one is rejected")
	var tiny_excess := _model([_source("tiny-excess", 1.0, 1.0, 0, PackedFloat64Array([0.5, 0.5000000000005]))], 2)
	_check(not ThermalBudget.initial_state(tiny_excess).ok, "any allocation excess above one is rejected")
	var bad_length := _model([_source("bad-length", 1.0, 1.0, 0, PackedFloat64Array([1.0]))], 2)
	_check(not ThermalBudget.initial_state(bad_length).ok, "allocation vector misalignment is rejected")
	var missing_provenance := _model([])
	missing_provenance.components[0].parameter_provenance = ""
	_check(not ThermalBudget.initial_state(missing_provenance).ok, "missing parameter provenance is rejected")
	var base := _model([])
	var state: Variant = ThermalBudget.initial_state(base).state
	_check(not ThermalBudget.advance(base, state, 1, 1.0).ok, "skipped tick is rejected")
	_check(not ThermalBudget.advance(base, state, 0, 1.000001).ok, "duration above bound is rejected")
	_check(not ThermalBudget.advance(base, state, 0, 0.5).ok, "duration differing from fixed model step is rejected")
	var below_ambient := _model([])
	below_ambient.components[0].initial_temperature_k = 290.0
	_check(not ThermalBudget.initial_state(below_ambient).ok, "initial temperature below ambient is rejected")


func _test_duplicate_and_read_only() -> void:
	var model := _model([_source("one-shot", 10.0, 10.0, 0, PackedFloat64Array([1.0]))])
	var serialized_before := JSON.stringify(model, "", true, true)
	var initial: Variant = ThermalBudget.initial_state(model).state
	var initial_temps: PackedFloat64Array = initial.temperatures_k.duplicate()
	var first := ThermalBudget.advance(model, initial, 0, 1.0)
	_check(first.ok, "first tick advances")
	var duplicate := ThermalBudget.advance(model, first.state, 0, 1.0)
	_check(duplicate.ok and duplicate.duplicate_tick, "duplicate tick is idempotent")
	_check(not ThermalBudget.advance(model, first.state, 0, 0.5).ok, "duplicate with different duration is rejected")
	_check_close(duplicate.source_used_j[0], 0.0, 0.0, "duplicate releases no energy")
	_check_close(duplicate.state.source_remaining_j[0], first.state.source_remaining_j[0], 0.0, "duplicate source state is unchanged")
	_check(initial.temperatures_k == initial_temps, "input state remains unchanged")
	_check(JSON.stringify(model, "", true, true) == serialized_before, "input model remains unchanged")
	_check(not ThermalBudget.advance(_model([]), first.state, 1, 1.0).ok, "different model fingerprint is rejected")


func _model(sources: Array, component_count: int = 1, tick_duration_s: float = 1.0) -> Dictionary:
	var components: Array[Dictionary] = []
	for index in range(component_count):
		components.append({
			"id": "part-%d" % index,
			"heat_capacity_j_per_k": 10.0,
			"cooling_w_per_k": 0.0,
			"ambient_k": 293.15,
			"initial_temperature_k": 293.15,
			"parameter_basis": "scenario_assumption",
			"parameter_provenance": "unit test declared lumped parameter, not physical evidence",
			"damage_dose_threshold_k_s": null,
			"damage_threshold_basis": null,
			"damage_threshold_provenance": null,
			"damage_disposition": null
		})
	return {
		"format": "openrc-thermal-budget v1",
		"first_tick": 0,
		"tick_duration_s": tick_duration_s,
		"components": components,
		"sources": sources
	}


func _source(source_id: String, energy_j: float, power_w: float, ignition_tick: Variant, shares: PackedFloat64Array) -> Dictionary:
	return {
		"id": source_id,
		"energy_j": energy_j,
		"power_w": power_w,
		"ignition_tick": ignition_tick,
		"allocation_shares": shares,
		"basis": "scenario_assumption",
		"provenance": "unit test source declaration, not physical evidence"
	}


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + label)


func _check_close(actual: float, expected: float, tolerance: float, label: String) -> void:
	_check(absf(actual - expected) <= tolerance, "%s (actual %.12f expected %.12f)" % [label, actual, expected])
