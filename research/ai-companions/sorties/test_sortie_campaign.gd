## AFC-09 campaign and admission design tests; no simulation is run.
extends SceneTree

const Campaign := preload("res://../research/ai-companions/sorties/sortie_campaign.gd")
const WindConfig := preload("res://physics/wind_config.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	var cases: Array[Dictionary] = Campaign.build_cases()
	_assert(cases.size() == 50, "campaign contains two calm controls plus 48 wind sorties", str(cases.size()))
	var ids := {}
	var seeds := {}
	var profile_counts := {}
	var direction_profile_counts := {}
	for case: Dictionary in cases:
		var case_id: String = str(case.case_id)
		_assert(not ids.has(case_id), "case IDs are unique", case_id)
		ids[case_id] = true
		if str(case.profile) == "calm":
			_assert(int(case.seed) == 0 and str(case.diversity_class) == "deterministic_control",
				"calm cases are visibly identified as deterministic controls", case_id)
		else:
			var seed := int(case.seed)
			_assert(not seeds.has(seed), "every wind weather seed is unique", str(seed))
			seeds[seed] = true
			_assert(str(case.diversity_class) == "mild_wind_realization", "wind cases are labelled as realizations", case_id)
			_assert(str(case.profile) != "tailwind", "tailwind is never scheduled as a physical sortie", case_id)
		var profile: String = str(case.profile)
		var direction: String = str(case.direction)
		profile_counts[profile] = int(profile_counts.get(profile, 0)) + 1
		var key := direction + ":" + profile
		direction_profile_counts[key] = int(direction_profile_counts.get(key, 0)) + 1
		var checked: Dictionary = WindConfig.validate(case.weather)
		_assert(bool(checked.ok) and bool(case.weather_valid), "campaign weather validates", case_id + " " + str(checked.get("errors", [])))
		_assert(bool(case.admission.admitted), "every planned physical sortie is admitted by its stated envelope", case_id + " " + str(case.admission))
		if profile == "calm":
			_assert(float(case.weather.speed_mps) == 0.0 and float(case.weather.gust_mps) == 0.0,
				"calm controls have zero wind and gust", case_id)
		else:
			_assert(int(case.weather.turbulence_seed) == int(case.seed), "weather carries the unique case seed", case_id)
			if profile == "headwind":
				var expected_from := 90.0 if direction == "east" else 270.0
				_assert(float(case.weather.speed_mps) == 1.5 and float(case.weather.gust_mps) == 0.6
					and float(case.weather.gust_up_mps) == 0.15 and case.weather.turbulence_rms_mps == [0.15, 0.15, 0.08]
					and float(case.weather.from_deg) == expected_from,
					"headwind profile retains the authored Gentle Practice envelope into the selected direction", case_id)
				_assert(absf(float(case.admission.headwind_mps) - 1.5) <= 1.0e-9
					and float(case.admission.mean_crosswind_mps) <= Campaign.ADMISSION_MAX_MEAN_CROSSWIND_MPS,
					"headwind case stays within the declared runway wind envelope", case_id)
			else:
				var expected_from := 0.0 if profile == "north_crosswind" else 180.0
				_assert(float(case.weather.speed_mps) == 0.5 and float(case.weather.gust_mps) == 0.2
					and float(case.weather.gust_up_mps) == 0.05 and case.weather.turbulence_rms_mps == [0.05, 0.05, 0.03]
					and float(case.weather.from_deg) == expected_from,
					"crosswind profile is bounded to the unqualified 0.5 m/s probe envelope", case_id)
				_assert(absf(float(case.admission.mean_crosswind_mps) - 0.5) <= 1.0e-9,
					"crosswind case remains below the declared 0.75 m/s admission ceiling", case_id)
	_assert(seeds.size() == 48, "all 48 wind sorties use independent turbulence seeds", str(seeds.size()))
	_assert(int(profile_counts.get("calm", 0)) == 2, "campaign has two calm directional controls")
	for profile: String in Campaign.WIND_PROFILES:
		_assert(int(profile_counts.get(profile, 0)) == 16, "each admitted wind profile has 16 cases", profile)
		for direction: String in ["east", "west"]:
			var key := direction + ":" + profile
			_assert(int(direction_profile_counts.get(key, 0)) == 8, "each direction-profile cell has eight realizations", key)
	var sample: Array[Dictionary] = Campaign.select_cases(cases, 10)
	var sample_directions := {}
	var sample_profiles := {}
	for case: Dictionary in sample:
		sample_directions[case.direction] = true
		sample_profiles[case.profile] = true
	_assert(sample.size() == 10 and sample_directions.size() == 2 and sample_profiles.size() == 4,
		"ten-case smoke selection spans both directions, calm, and both crosswind sectors", str([sample.size(), sample_directions.keys(), sample_profiles.keys()]))
	_assert(Campaign.select_cases(cases, 0).is_empty() and Campaign.select_cases(cases, 51).is_empty(),
		"selection refuses limits outside the campaign matrix")
	_check_admission_refusals()
	for failure: String in failures:
		printerr("FAIL " + failure)
	print("AFC-09 campaign design: %d checks, %d failed" % [checks, failures.size()])
	quit(1 if not failures.is_empty() else 0)


func _check_admission_refusals() -> void:
	var refusals: Array[Dictionary] = Campaign.build_admission_refusal_cases()
	_assert(refusals.size() == 6, "tailwind/crosswind/gust negatives are separate from the 50 physical sorties", str(refusals.size()))
	var ids := {}
	for case: Dictionary in refusals:
		var case_id: String = str(case.case_id)
		_assert(not ids.has(case_id), "negative admission IDs are distinct", case_id)
		ids[case_id] = true
		_assert(not bool(case.sortie_run), "a refused admission never starts or counts a flight", case_id)
		_assert(not bool(case.result.admitted) and str(case.result.reason) == str(case.expected_reason),
			"negative admission returns its explicit expected reason", case_id + " " + str(case.result))
	for direction: String in ["east", "west"]:
		var tailwind: Dictionary = refusals.filter(func(c: Dictionary) -> bool: return c.case_id == "tailwind-" + direction)[0]
		_assert(float(tailwind.result.headwind_mps) <= -1.0,
			"a tailwind of coordinator-reversal scale is explicitly refused", direction)
	_assert(not Campaign.evaluate_weather_admission(true, {format = "invalid"}).admitted,
		"malformed weather cannot pass preflight admission")


func _assert(condition: bool, label: String, detail: String = "") -> void:
	checks += 1
	if not condition:
		failures.append(label + (" — " + detail if not detail.is_empty() else ""))
