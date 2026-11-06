extends SceneTree
## AE-11-R1: reject the audit F1 combination before any flight start is offered.

const AircraftData := preload("res://physics/aircraft_data.gd")
const Installation := preload("res://physics/glow/installation.gd")
const Trial := preload("res://workshop/trial.gd")
const Compiler := preload("res://workshop/compiler.gd")
const MassEdit := preload("res://workshop/mass_edit.gd")
const EXTRA_PATH := "res://data/aircraft/gp_extra_300s_60.json"
const EXTRA_ID := "gp-extra-300s-60"

var checks := 0
var failures := 0


func _initialize() -> void:
	var bytes := FileAccess.get_file_as_bytes(EXTRA_PATH)
	var raw: Dictionary = JSON.parse_string(bytes.get_string_from_utf8())
	var source_before := var_to_bytes(raw)
	var stock := AircraftData.validate_and_derive(raw)
	_check("stock Extra remains admitted", stock.ok, str(stock.get("errors", [])))
	if not stock.ok:
		quit(1)
		return
	_check("stock Extra needs one contact substep", stock.model.landing_gear.substeps == 1)
	_test_installation_boundary(raw, stock.model)
	# Exact synthetic A6/F1 counterexample; these values are not physical measurements.
	var recipe := {"mass_edits": [
		{"id": "engine_main", "mass_kg": 0.311, "source": "measurement"},
		{"id": "wing_main", "mass_kg": 0.270, "source": "measurement"},
		{"id": "fuselage_rear", "mass_kg": 0.089, "source": "measurement"},
	]}
	var recipe_before := var_to_bytes(recipe)
	var measured := MassEdit.apply_to_validated_base(raw, recipe.mass_edits)
	_check("mass editor refuses the incompatible aircraft", _contact_refusal(measured), str(measured.get("errors", [])))
	var compiled := Compiler.compile(raw, recipe)
	_check("compiler refuses the incompatible aircraft", _contact_refusal(compiled), str(compiled.get("errors", [])))
	var frozen := Trial.freeze({"base_id": EXTRA_ID, "base_bytes": bytes, "recipe": recipe})
	_check("trial refuses F1 before runway or airborne qualification", _contact_refusal(frozen), str(frozen.get("errors", [])))
	_check("refused trial publishes no flight model or identity", not frozen.has("identity")
		and frozen.get("data", {}).get("model", {}).is_empty())
	_check("refusal preserves source and draft", var_to_bytes(raw) == source_before
		and var_to_bytes(recipe) == recipe_before
		and FileAccess.get_file_as_bytes(EXTRA_PATH) == bytes)
	var default_trial := Trial.freeze({"base_id": EXTRA_ID, "base_bytes": bytes, "recipe": {}})
	_check("stock Extra trial still freezes after refusal", default_trial.get("ok", false), str(default_trial.get("errors", [])))
	print("Glow contact admission: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _test_installation_boundary(raw: Dictionary, model: Dictionary) -> void:
	var installation_bytes := FileAccess.get_file_as_bytes(raw.propulsion.engine.glow_installation)
	var installation: Dictionary = JSON.parse_string(installation_bytes.get_string_from_utf8())
	# The shared gate must cover direct attachment and its pure validator, without
	# depending on aircraft ID, Workshop provenance, starting altitude or ground reach.
	for count: int in [1, 2, 3]:
		var candidate := model.duplicate(true)
		candidate.landing_gear.substeps = count
		var before := var_to_bytes(candidate)
		var attached := Installation.attach(raw, candidate)
		var prepared := Installation.prepare_value(installation, raw, candidate, installation_bytes)
		if count == 1:
			_check("one-substep attachment remains available", attached.ok and prepared.ok)
		else:
			_check("attachment refuses %d substeps with a specific reason" % count,
				_contact_refusal(attached, count) and attached.model.is_empty(), str(attached.get("errors", [])))
			_check("pure validator also refuses %d substeps" % count,
				_contact_refusal(prepared, count) and prepared.model.is_empty(), str(prepared.get("errors", [])))
		_check("attachment preserves the supplied model for %d substeps" % count, var_to_bytes(candidate) == before)
	var gearless := model.duplicate(true)
	gearless.landing_gear = {}
	_check("no landing gear introduces no subdivision conflict", Installation.attach(raw, gearless).ok)


func _contact_refusal(result: Dictionary, count := 2) -> bool:
	return not result.get("ok", false) and str(result.get("errors", [])).contains("%d contact substeps" % count)


func _check(label: String, passed: bool, detail := "") -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label, " ", detail)
