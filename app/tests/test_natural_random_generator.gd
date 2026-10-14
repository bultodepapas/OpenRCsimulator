extends SceneTree

const NaturalRandom := preload("res://scenarios/natural_random.gd")
const ScenarioConfig := preload("res://scenarios/scenario_config.gd")

const DISTRIBUTION_SAMPLE_COUNT := 10000
const AIRCRAFT_TOLERANCE_PCT := 2.0
const CATEGORY_TOLERANCE_PCT := 2.0

var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_seed_contract()
	_test_reproducibility()
	_test_distribution()
	_finish()


func _test_seed_contract() -> void:
	for value: int in [0, 1, 2147483647, 4294967295]:
		var result: Dictionary = NaturalRandom.generate(value)
		_check("uint32 seed %d generates a valid scenario" % value,
			bool(result.get("ok", false)), str(result.get("errors", [])))
		if bool(result.get("ok", false)):
			var scenario: Dictionary = result.scenario
			_check("uint32 seed %d is preserved exactly" % value, scenario.seed == value)
			_check("uint32 seed %d uses v3 atmosphere and airborne start" % value,
				scenario.start_choice == "airborne" and scenario.weather_config.format == "openrc-weather v3")
	var below: Dictionary = NaturalRandom.generate(-1)
	var above: Dictionary = NaturalRandom.generate(4294967296)
	_check("negative seed fails with a structured result", not bool(below.get("ok", false)) and not below.get("errors", []).is_empty())
	_check("seed above uint32 fails with a structured result", not bool(above.get("ok", false)) and not above.get("errors", []).is_empty())


func _test_reproducibility() -> void:
	var first: Dictionary = NaturalRandom.generate(20261013)
	var second: Dictionary = NaturalRandom.generate(20261013)
	_check("repeated seed produces the same fully resolved record",
		bool(first.get("ok", false)) and bool(second.get("ok", false))
		and JSON.stringify(first.scenario, "", true, true) == JSON.stringify(second.scenario, "", true, true))
	var another: Dictionary = NaturalRandom.generate(20261014)
	_check("different master seeds resolve to different identities",
		bool(first.get("ok", false)) and bool(another.get("ok", false))
		and first.scenario.identity != another.scenario.identity)
	if not bool(first.get("ok", false)):
		return
	var snapshot: String = JSON.stringify(first.scenario, "", true, true)
	first.scenario.weather_config.speed_mps = 0.0
	_check("returned scenarios are detached from future generator calls",
		JSON.stringify(NaturalRandom.generate(20261013).scenario, "", true, true) == snapshot)


func _test_distribution() -> void:
	var policy: Dictionary = ScenarioConfig.policy_catalog()
	var aircraft_counts: Dictionary = {}
	var recipe_counts: Dictionary = {}
	var daylight_counts: Dictionary = {}
	var joint_counts: Dictionary = {}
	for aircraft_id: String in ScenarioConfig.EXPECTED_AIRCRAFT_IDS:
		aircraft_counts[aircraft_id] = 0
	for recipe_value: Variant in policy.get("recipes", []):
		var recipe: Dictionary = recipe_value
		recipe_counts[str(recipe.get("id", ""))] = 0
		for aircraft_id: String in ScenarioConfig.EXPECTED_AIRCRAFT_IDS:
			joint_counts["%s|%s" % [aircraft_id, recipe.get("id", "")]] = 0
	for daylight_value: Variant in policy.get("daylight", []):
		var daylight: Dictionary = daylight_value
		daylight_counts[str(daylight.get("id", ""))] = 0
	var sample_failures := 0
	for seed: int in range(DISTRIBUTION_SAMPLE_COUNT):
		var result: Dictionary = NaturalRandom.generate(seed)
		if not bool(result.get("ok", false)):
			sample_failures += 1
			continue
		var scenario: Dictionary = result.scenario
		var aircraft_id := str(scenario.get("aircraft_id", ""))
		var recipe_id := str(scenario.get("recipe_id", ""))
		var daylight_id := str(scenario.get("daylight_id", ""))
		aircraft_counts[aircraft_id] = int(aircraft_counts.get(aircraft_id, 0)) + 1
		recipe_counts[recipe_id] = int(recipe_counts.get(recipe_id, 0)) + 1
		daylight_counts[daylight_id] = int(daylight_counts.get(daylight_id, 0)) + 1
		var joint_key := "%s|%s" % [aircraft_id, recipe_id]
		joint_counts[joint_key] = int(joint_counts.get(joint_key, 0)) + 1
	_check("all 10,000 generated scenarios pass strict validation", sample_failures == 0,
		"%d invalid samples" % sample_failures)
	for aircraft_id: String in aircraft_counts:
		_check("aircraft '%s' is approximately uniform" % aircraft_id,
			_within_pct(int(aircraft_counts[aircraft_id]), 20.0, AIRCRAFT_TOLERANCE_PCT), str(aircraft_counts[aircraft_id]))
	for recipe_value: Variant in policy.get("recipes", []):
		var recipe: Dictionary = recipe_value
		var recipe_id := str(recipe.id)
		var weight := float(recipe.weight_pct)
		_check("recipe '%s' is near its exact %d%% target" % [recipe_id, int(weight)],
			_within_pct(int(recipe_counts[recipe_id]), weight, CATEGORY_TOLERANCE_PCT), str(recipe_counts[recipe_id]))
		for aircraft_id: String in ScenarioConfig.EXPECTED_AIRCRAFT_IDS:
			var count := int(joint_counts["%s|%s" % [aircraft_id, recipe_id]])
			_check("aircraft/recipe cell %s × %s shows independent selection" % [aircraft_id, recipe_id],
				absf(float(count) - 500.0) <= 125.0, str(count))
	for daylight_value: Variant in policy.get("daylight", []):
		var daylight: Dictionary = daylight_value
		var daylight_id := str(daylight.id)
		var weight := float(daylight.weight_pct)
		_check("daylight '%s' is near its exact %d%% target" % [daylight_id, int(weight)],
			_within_pct(int(daylight_counts[daylight_id]), weight, CATEGORY_TOLERANCE_PCT), str(daylight_counts[daylight_id]))


func _within_pct(count: int, target_pct: float, tolerance_pct: float) -> bool:
	var expected := float(DISTRIBUTION_SAMPLE_COUNT) * target_pct / 100.0
	var tolerance := float(DISTRIBUTION_SAMPLE_COUNT) * tolerance_pct / 100.0
	return absf(float(count) - expected) <= tolerance


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _finish() -> void:
	print("all Natural Random generator checks passed" if _failures == 0 else "%d Natural Random generator checks failed" % _failures)
	quit(1 if _failures > 0 else 0)
