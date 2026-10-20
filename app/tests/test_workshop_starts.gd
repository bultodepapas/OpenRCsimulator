extends SceneTree
## AE-11: assess only authentic frozen models through FlightSession's selected start.

const Qualification := preload("res://workshop/start_qualification.gd")
const Trial := preload("res://workshop/trial.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Field := preload("res://data/field_loader.gd")
const Weather := preload("res://physics/wind_config.gd")

const STIK_ID := "jensen-das-ugly-stik-60"
const STIK_SCALE_VARIANTS := [0.35, 0.5, 0.75, 1.25, 1.5, 2.0, 2.25]

var checks := 0
var failures := 0


func _initialize() -> void:
	var loaded_field: Dictionary = Field.load_from()
	_check("default field fixture loads", loaded_field.get("ok", false))
	if not loaded_field.get("ok", false):
		_finish()
		return
	var field: Dictionary = loaded_field.field
	var weather: Dictionary = Weather.defaults()
	var frozen_variants: Array[Dictionary] = []
	for entry: Dictionary in Catalog.airplane_flyable_entries():
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(str(entry.data))
		var recipes: Array[Dictionary] = [{}]
		if str(entry.id) == STIK_ID:
			for scale_value: float in STIK_SCALE_VARIANTS:
				recipes.append({"scale": scale_value})
		for recipe: Dictionary in recipes:
			var frozen: Dictionary = Trial.freeze({"base_id": str(entry.id), "base_bytes": bytes, "recipe": recipe})
			_check("authentic trial freezes for %s %s" % [entry.id, recipe], frozen.get("ok", false),
				str(frozen.get("errors", [])))
			if frozen.get("ok", false):
				frozen_variants.append({"id": str(entry.id), "recipe": recipe.duplicate(true), "frozen": frozen})
	for variant: Dictionary in frozen_variants:
		var frozen: Dictionary = variant.frozen
		var original_model: Dictionary = frozen.data.model.duplicate(true)
		for choice: String in ["runway", "airborne", "airborne_half_power"]:
			var expected: bool = choice != "airborne_half_power"
			if choice == "runway" and str(variant.id) == STIK_ID:
				var scale_value: float = float(variant.recipe.get("scale", 1.0))
				expected = scale_value >= 0.5 and scale_value <= 1.25
			var result: Dictionary = Qualification.qualify(frozen, field, weather, choice)
			var label: String = "%s %s %s" % [variant.id, variant.recipe, choice]
			_check(label + " is assessed", result.get("ok", false), str(result.get("reason", "")))
			_check(label + " matches physical availability", result.get("available", false) == expected,
				str(result.get("reason", "")))
			if not expected:
				_check(label + " refusal never reports the requested route as committed",
					not result.get("available", false)
					and str(result.get("diagnostics", {}).get("launch_choice", "")) != choice)
			_check(label + " returns bounded runtime", float(result.get("duration_ms", INF)) >= 0.0
				and float(result.duration_ms) <= 16000.0
				and int(result.get("diagnostics", {}).get("runtime_budget_usec", 0)) == 16_000_000,
				str(result.get("duration_ms", "missing")))
			_check(label + " leaves frozen source model unchanged", frozen.data.model == original_model)
			if result.get("available", false):
				_check(label + " reports exact selected route and field",
					str(result.diagnostics.get("start_choice", "")) == choice
					and str(result.diagnostics.get("launch_field_id", "")) == (field.id if choice == "runway" else "")
					and int(result.diagnostics.get("tick", -1)) == 0)
			if choice == "runway" and expected and result.get("available", false):
				_test_runway_support(label, result.diagnostics)
	var first_frozen: Dictionary = frozen_variants[0].frozen if not frozen_variants.is_empty() else {}
	if not first_frozen.is_empty():
		_test_rejections(first_frozen, field, weather)
	print("Workshop starts: %d checks, %d failed, %d frozen variants" % [checks, failures, frozen_variants.size()])
	_finish()


func _test_runway_support(label: String, diagnostics: Dictionary) -> void:
	var runway: Dictionary = diagnostics.get("runway_diagnostics", {})
	_check(label + " has converged runway equilibrium", diagnostics.get("runway_status", "") == "converged"
		and is_finite(float(diagnostics.get("runway_scaled_residual", INF)))
		and float(diagnostics.get("runway_scaled_residual", INF)) <= 1.0e-9)
	_check(label + " stays within the solver evaluation budget",
		int(runway.get("total_residual_evaluations", -1)) >= 0
		and int(runway.get("total_residual_evaluations", 999999)) <= int(runway.get("residual_evaluation_budget", 0)))
	var contacts: Array = runway.get("contact_summary", [])
	_check(label + " reports each stiction gear support", contacts.size() == int(diagnostics.get("stiction_anchor_count", -1))
		and contacts.size() == int(diagnostics.get("gear_contact_count", -2)))
	for contact: Dictionary in contacts:
		_check(label + " contact remains within compression and anchor bounds " + str(contact.get("name", "")),
			bool(contact.get("loaded", false)) and bool(contact.get("heading_valid", false))
			and bool(contact.get("anchor_stuck", false))
			and float(contact.get("compression_m", 0.0)) > 0.0
			and float(contact.get("compression_m", INF)) <= float(contact.get("max_compression_m", -1.0))
			and float(contact.get("normal_load_n", 0.0)) > 0.0)
	var shift: PackedFloat64Array = runway.get("achieved_minus_requested", PackedFloat64Array())
	_check(label + " remains inside authored placement bounds", shift.size() == 4
		and sqrt(shift[0] * shift[0] + shift[1] * shift[1]) <= 0.010000001
		and absf(shift[3]) <= 0.001745339)


func _test_rejections(frozen: Dictionary, field: Dictionary, weather: Dictionary) -> void:
	var stale_model: Dictionary = frozen.duplicate(true)
	stale_model.data.model.mass_kg = float(stale_model.data.model.mass_kg) * 1.001
	var stale: Dictionary = Qualification.qualify(stale_model, field, weather, "airborne")
	_check("stale frozen model hash is rejected before session creation", not stale.get("ok", false)
		and not stale.get("available", false) and str(stale.get("reason", "")).contains("model hash"))
	var probe_identity: Dictionary = frozen.duplicate(true)
	probe_identity.data.input_identity.sha256 = "probe"
	var probe: Dictionary = Qualification.qualify(probe_identity, field, weather, "airborne")
	_check("placeholder input identity is rejected", not probe.get("ok", false)
		and str(probe.get("reason", "")).contains("input identity"))
	var missing_runway: Dictionary = field.duplicate(true)
	missing_runway.surfaces = missing_runway.surfaces.filter(func(surface: Dictionary) -> bool:
		return str(surface.get("type", "")) != "runway")
	var missing: Dictionary = Qualification.qualify(frozen, missing_runway, weather, "runway")
	_check("missing runway refuses only the selected runway route", missing.get("ok", false)
		and not missing.get("available", false) and not str(missing.get("reason", "")).is_empty()
		and str(missing.get("reason", "")).contains("no runway"))
	_check("missing runway assessment preserves the caller field", field.has("surfaces")
		and field.surfaces.any(func(surface: Dictionary) -> bool: return str(surface.get("type", "")) == "runway"))
	var invalid_weather: Dictionary = Qualification.qualify(frozen, field, {"format": "invalid"}, "airborne")
	_check("invalid weather is refused before a live candidate can be accepted", not invalid_weather.get("ok", false)
		and not invalid_weather.get("available", false))
	var invalid_choice: Dictionary = Qualification.qualify(frozen, field, weather, "unlisted")
	_check("unregistered start choice is refused", not invalid_choice.get("ok", false)
		and not invalid_choice.get("available", false))


func _check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _finish() -> void:
	quit(1 if failures else 0)
