extends SceneTree

const FailureConfig := preload("res://failures/config.gd")
const FailureCatalog := preload("res://failures/catalog.gd")
const FailureRuntime := preload("res://failures/runtime.gd")
const AircraftCatalog := preload("res://app_state/aircraft_catalog.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")

const DT := 1.0 / 60.0
const POWER_LOSS_IDS: Array[String] = ["glow_fuel_cut", "electric_drive_loss"]

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_config_and_catalog_profiles()
	_test_versioned_plans()
	_test_restore_contract()
	print("Failure profile contract: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool, detail: Variant = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s: %s" % [label, str(detail)])


func _config(probability: int, catastrophic := false, notify := true) -> Dictionary:
	return {
		"probability_percent": probability,
		"include_catastrophic": catastrophic,
		"notify": notify,
	}


func _test_config_and_catalog_profiles() -> void:
	var defaults: Dictionary = FailureConfig.defaults()
	_check("failure config defaults keep the three original settings and add EM-29 selection defaults", defaults == {
		"probability_percent": 0,
		"include_catastrophic": false,
		"notify": true,
		"severity": "standard",
		"onset": "standard",
		"excluded_ids": [],
	}, defaults)
	var legacy_upgrade: Dictionary = FailureConfig.validate(_config(0))
	_check("the original three-key request upgrades to the defaults", legacy_upgrade.get("ok", false)
		and legacy_upgrade.get("config", {}) == defaults, legacy_upgrade)
	var normalized: Dictionary = FailureConfig.validate(defaults)
	_check("failure config round-trips through strict validation", normalized.get("ok", false) and normalized.get("config", {}) == defaults)
	_check("failure config rejects future settings", not FailureConfig.validate({
		"probability_percent": 0,
		"include_catastrophic": false,
		"notify": true,
		"future_setting": true,
	}).get("ok", true))

	var model_ids: PackedStringArray = AircraftCatalog.airplane_flyable_ids()
	_check("all current airplane catalog model types are exercised", model_ids.size() >= 8, model_ids)
	var profiles_seen: Dictionary = {}
	var loaded_count := 0
	var elevon_seen := false
	for aircraft_id: String in model_ids:
		var entry: Dictionary = AircraftCatalog.entry(aircraft_id)
		var loaded: Dictionary = AircraftData.load_file(str(entry.get("data", "")))
		_check(aircraft_id + " has a validated normalized model", bool(loaded.get("ok", false)), loaded.get("errors", PackedStringArray()))
		if not bool(loaded.get("ok", false)):
			continue
		loaded_count += 1
		var model: Dictionary = loaded.get("model", {})
		var profile: String = FailureCatalog.profile_for_model(model)
		var available: Dictionary = FailureCatalog.availability(model)
		var expected_power_ids: Array[String] = _power_ids_for(profile)
		_check(aircraft_id + " derives a recognized propulsion profile", profile in FailureCatalog.PROFILES, profile)
		_check(aircraft_id + " availability reports its derived profile", str(available.get("eligibility_profile", "")) == profile)
		_check(aircraft_id + " exposes only its eligible power-loss event", available.get("power_loss_ids", []) == expected_power_ids, available)
		_check(aircraft_id + " availability support flag matches eligible events", bool(available.get("power_loss_supported", false)) == (not expected_power_ids.is_empty()))
		_check(aircraft_id + " includes every eligible power loss", _array_contains_all(available.get("eligible_ids", []), expected_power_ids))
		var elevon: bool = str(model.get("controls", {}).get("layout", "")) == "elevon"
		elevon_seen = elevon_seen or elevon
		var yaw_offered := _array_contains_any(FailureCatalog.YAW_AXIS_IDS, available.get("eligible_ids", []))
		_check(aircraft_id + " offers rudder failures only when it has a rudder", yaw_offered != elevon, available)
		var request: Dictionary = FailureCatalog.request_for_model(FailureConfig.defaults(), model)
		_check(aircraft_id + " resolved request excludes exactly the missing control axis",
			request.excluded_ids == (["yaw_bias", "yaw_jam", "yaw_slow", "yaw_travel_limit"] if elevon else []), request)

		var renamed_model: Dictionary = model.duplicate(true)
		renamed_model["id"] = "unrelated-aircraft-identity"
		_check(aircraft_id + " profile comes from normalized propulsion, not aircraft id",
			FailureCatalog.profile_for_model(renamed_model) == profile
			and FailureCatalog.availability(renamed_model).get("power_loss_ids", []) == expected_power_ids)
		profiles_seen[profile] = true

	_check("every airplane catalog entry loaded for profile derivation", loaded_count == model_ids.size(), loaded_count)
	_check("the fleet includes an elevon aircraft for the rudder exclusion", elevon_seen)
	_check("catalog models exercise control-only eligibility", profiles_seen.has(FailureCatalog.LOGICAL_CONTROLS_PROFILE), profiles_seen)
	_check("catalog models exercise finite-glow eligibility", profiles_seen.has(FailureCatalog.FINITE_GLOW_PROFILE), profiles_seen)
	_check("catalog models exercise electric-drive eligibility", profiles_seen.has(FailureCatalog.ELECTRIC_DRIVE_PROFILE), profiles_seen)

	var logical_ids: Array[String] = FailureCatalog.failure_ids(false, FailureCatalog.LOGICAL_CONTROLS_PROFILE)
	var glow_ids: Array[String] = FailureCatalog.failure_ids(false, FailureCatalog.FINITE_GLOW_PROFILE)
	var electric_ids: Array[String] = FailureCatalog.failure_ids(false, FailureCatalog.ELECTRIC_DRIVE_PROFILE)
	_check("logical-control profile excludes all power-loss events", not _array_contains_any(logical_ids, POWER_LOSS_IDS), logical_ids)
	_check("finite-glow profile includes only glow cutoff", glow_ids.has("glow_fuel_cut") and not glow_ids.has("electric_drive_loss"), glow_ids)
	_check("electric-drive profile includes only motor power loss", electric_ids.has("electric_drive_loss") and not electric_ids.has("glow_fuel_cut"), electric_ids)
	_check("unknown profile has no failure event set", FailureCatalog.failure_ids(false, "future-profile-v9").is_empty())


func _power_ids_for(profile: String) -> Array[String]:
	if profile == FailureCatalog.FINITE_GLOW_PROFILE:
		return FailureCatalog.GLOW_POWER_LOSS_IDS.duplicate()
	if profile == FailureCatalog.ELECTRIC_DRIVE_PROFILE:
		return FailureCatalog.ELECTRIC_POWER_LOSS_IDS.duplicate()
	return []


func _array_contains_all(source_value: Variant, expected: Array[String]) -> bool:
	if typeof(source_value) != TYPE_ARRAY:
		return false
	var source: Array = source_value
	for value: String in expected:
		if not source.has(value):
			return false
	return true


func _array_contains_any(source: Array[String], candidates: Array[String]) -> bool:
	for value: String in candidates:
		if source.has(value):
			return true
	return false


func _test_versioned_plans() -> void:
	var legacy := FailureRuntime.new()
	_check("legacy three-argument begin remains valid", legacy.begin(_config(100), 1751, DT))
	var legacy_plan: Dictionary = legacy.plan()
	_check("legacy call retains the original v1 plan format and catalog", legacy_plan.get("format", "") == "openrc-failure-plan v1" and int(legacy_plan.get("catalog_version", -1)) == 1, legacy_plan)
	_check("legacy plan has no physical eligibility field", not legacy_plan.has("eligibility_profile"), legacy_plan)
	_check("legacy seeded event remains roll jam", str(legacy_plan.get("id", "")) == "roll_jam", legacy_plan)
	_check("legacy event set cannot select a power-loss event", not POWER_LOSS_IDS.has(str(legacy_plan.get("id", ""))))

	for profile: String in FailureCatalog.PROFILES:
		var historical := FailureRuntime.new()
		_check(profile + " recreates a historical v2 plan on request",
			historical.begin(_config(100), 1751, DT, profile, FailureRuntime.PLAN_FORMAT_V2))
		var historical_plan: Dictionary = historical.plan()
		_check(profile + " historical plan keeps the v2 format, catalog and three-key config",
			historical_plan.get("format", "") == "openrc-failure-plan v2" and int(historical_plan.get("catalog_version", -1)) == 2
			and historical_plan.get("config", {}).size() == 3, historical_plan)
		_check(profile + " historical plan chooses only from the frozen v2 event set",
			FailureCatalog.failure_ids(false, profile).has(str(historical_plan.get("id", ""))), historical_plan)
		var runtime := FailureRuntime.new()
		_check(profile + " starts a profile-bound plan", runtime.begin(_config(100), 1751, DT, profile))
		var plan: Dictionary = runtime.plan()
		_check(profile + " writes the v3 plan and catalog versions", plan.get("format", "") == "openrc-failure-plan v3" and int(plan.get("catalog_version", -1)) == 3, plan)
		_check(profile + " plan binds the exact eligibility profile", str(plan.get("eligibility_profile", "")) == profile)
		_check(profile + " guarantees occurrence at 100 percent", bool(plan.get("selected", false)), plan)
		_check(profile + " chooses only from the profile event set",
			FailureCatalog.failure_ids_v3(false, profile).has(str(plan.get("id", ""))), plan)
		_check(profile + " accepts its own profile", runtime.accepts_profile(profile))
		for other_profile: String in FailureCatalog.PROFILES:
			if other_profile != profile:
				_check(profile + " refuses family mismatch " + other_profile, not runtime.accepts_profile(other_profile))

	var disabled := FailureRuntime.new()
	_check("zero probability configures a v3 plan", disabled.begin(_config(0, false, false), 2001, DT, FailureCatalog.LOGICAL_CONTROLS_PROFILE))
	var disabled_plan: Dictionary = disabled.plan()
	_check("zero probability never selects a failure", not bool(disabled_plan.get("selected", true)) and str(disabled_plan.get("id", "")) == "", disabled_plan)
	_check("zero-probability plan preserves notification preference", disabled.status().get("notify", true) == false and disabled_plan.config.notify == false)

	var notices_on := FailureRuntime.new()
	var notices_off := FailureRuntime.new()
	_check("100-percent plan configures with notices on", notices_on.begin(_config(100, false, true), 2002, DT, FailureCatalog.FINITE_GLOW_PROFILE))
	_check("same 100-percent plan configures with notices off", notices_off.begin(_config(100, false, false), 2002, DT, FailureCatalog.FINITE_GLOW_PROFILE))
	var on_plan: Dictionary = notices_on.plan()
	var off_plan: Dictionary = notices_off.plan()
	_check("100 percent selects regardless of notice setting", bool(on_plan.selected) and bool(off_plan.selected))
	_check("notice setting is recorded in status", bool(notices_on.status().notify) and not bool(notices_off.status().notify))
	_check("notice preference remains stored outside physical plan identity", bool(on_plan.config.notify) and not bool(off_plan.config.notify))
	_check("notice setting changes presentation without changing physical plan identity", str(on_plan.identity) == str(off_plan.identity))
	var on_snapshot: Dictionary = notices_on.snapshot()
	_check("unknown profile is rejected without changing a live plan",
		not notices_on.begin(_config(0), 1, DT, "future-profile-v9")
		and notices_on.plan() == on_plan and notices_on.snapshot() == on_snapshot)


func _test_restore_contract() -> void:
	var legacy_source := FailureRuntime.new()
	_check("legacy source creates a restorable v1 plan", legacy_source.begin(_config(100), 1751, DT))
	var legacy_snapshot: Dictionary = legacy_source.snapshot()
	var legacy_target := FailureRuntime.new()
	_check("legacy v1 snapshot restores", legacy_target.restore(legacy_snapshot, int(legacy_snapshot.get("tick", -1))))
	_check("restored v1 plan accepts every known aircraft profile",
		bool(legacy_target.accepts_profile(FailureCatalog.LOGICAL_CONTROLS_PROFILE))
		and bool(legacy_target.accepts_profile(FailureCatalog.FINITE_GLOW_PROFILE))
		and bool(legacy_target.accepts_profile(FailureCatalog.ELECTRIC_DRIVE_PROFILE)))

	var v2_source := FailureRuntime.new()
	_check("v2 source creates a finite-glow plan", v2_source.begin(_config(100), 751, DT, FailureCatalog.FINITE_GLOW_PROFILE,
		FailureRuntime.PLAN_FORMAT_V2))
	var v2_snapshot: Dictionary = v2_source.snapshot()
	var v2_target := FailureRuntime.new()
	_check("v2 snapshot restores with its profile", v2_target.restore(v2_snapshot, int(v2_snapshot.get("tick", -1))))
	_check("restored v2 plan still enforces its family", v2_target.accepts_profile(FailureCatalog.FINITE_GLOW_PROFILE)
		and not v2_target.accepts_profile(FailureCatalog.ELECTRIC_DRIVE_PROFILE))

	var good_live := FailureRuntime.new()
	_check("atomic restore target has a live plan", good_live.begin(_config(0), 455, DT, FailureCatalog.LOGICAL_CONTROLS_PROFILE))
	var live_before: PackedByteArray = var_to_bytes(good_live.snapshot())
	var unknown_profile: Dictionary = v2_snapshot.duplicate(true)
	unknown_profile.plan.eligibility_profile = "future-profile-v9"
	_check_restore_refused_atomically("unknown profile is rejected", good_live, unknown_profile, live_before)
	var missing_profile: Dictionary = v2_snapshot.duplicate(true)
	missing_profile.plan.erase("eligibility_profile")
	_check_restore_refused_atomically("malformed profile field is rejected", good_live, missing_profile, live_before)
	var relabelled_plan: Dictionary = v2_snapshot.duplicate(true)
	relabelled_plan.plan.format = "openrc-failure-plan v3"
	_check_restore_refused_atomically("v2 plan relabelled as v3 is rejected", good_live, relabelled_plan, live_before)
	var future_plan: Dictionary = v2_snapshot.duplicate(true)
	future_plan.plan.format = "openrc-failure-plan v4"
	_check_restore_refused_atomically("future plan version is rejected", good_live, future_plan, live_before)
	var v3_source := FailureRuntime.new()
	_check("v3 source creates a finite-glow plan", v3_source.begin(_config(100), 751, DT, FailureCatalog.FINITE_GLOW_PROFILE))
	var v3_snapshot: Dictionary = v3_source.snapshot()
	var v3_target := FailureRuntime.new()
	_check("v3 snapshot restores with its profile", v3_target.restore(v3_snapshot, int(v3_snapshot.get("tick", -1)))
		and v3_target.accepts_profile(FailureCatalog.FINITE_GLOW_PROFILE)
		and not v3_target.accepts_profile(FailureCatalog.ELECTRIC_DRIVE_PROFILE))
	var downgraded_plan: Dictionary = v3_snapshot.duplicate(true)
	downgraded_plan.plan.format = "openrc-failure-plan v2"
	_check_restore_refused_atomically("v3 plan relabelled as v2 is rejected", good_live, downgraded_plan, live_before)
	var profile_mismatch: Dictionary = v2_snapshot.duplicate(true)
	profile_mismatch.plan.eligibility_profile = FailureCatalog.ELECTRIC_DRIVE_PROFILE
	_check_restore_refused_atomically("corrupted supported profile is rejected", good_live, profile_mismatch, live_before)
	_check("unknown profile begin leaves the live runtime unchanged",
		not good_live.begin(_config(100), 11, DT, "future-profile-v9")
		and var_to_bytes(good_live.snapshot()) == live_before)



func _check_restore_refused_atomically(label: String, runtime: FailureRuntime, snapshot: Dictionary, live_before: PackedByteArray) -> void:
	var accepted: bool = runtime.restore(snapshot, int(snapshot.get("tick", 0)))
	_check(label, not accepted and var_to_bytes(runtime.snapshot()) == live_before,
		{"accepted": accepted, "unchanged": var_to_bytes(runtime.snapshot()) == live_before})
