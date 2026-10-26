extends SceneTree

const Capture := preload("res://../tools/trailer/capture_flight.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Customization := preload("res://render/aircraft_customization.gd")
const LightingProfile := preload("res://render/lighting/lighting_profile.gd")
const Presentation := preload("res://workshop/presentation.gd")
const Trial := preload("res://workshop/trial.gd")
const WorkloadAudit := preload("lighting_workload_audit.gd")

const EXTRA_ID := "gp-extra-300s-60"

var _checks := 0
var _failures := 0
var _temp_dir := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_workload_audit()
	var mix_before := {"start_usec": 1000, "end_usec": 1010, "age_usec": 5000}
	_check("elapsed wall time alone cannot establish an audio mix",
		not Capture.audio_mix_reset_between(mix_before, {"start_usec": 101000, "end_usec": 101010, "age_usec": 105000}))
	_check("query latency cannot be mistaken for an audio mix",
		not Capture.audio_mix_reset_between({"start_usec": 1000, "end_usec": 11000, "age_usec": 5000},
			{"start_usec": 12000, "end_usec": 22000, "age_usec": 6000}))
	_check("small clock jitter cannot establish an audio mix",
		not Capture.audio_mix_reset_between(mix_before, {"start_usec": 2000, "end_usec": 2010, "age_usec": 5000}))
	_check("completed driver mix resets the elapsed audio age",
		Capture.audio_mix_reset_between(mix_before, {"start_usec": 101000, "end_usec": 101010, "age_usec": 1000}))
	_check("multiple fast movie frames can establish a cumulative mix reset",
		Capture.audio_mix_reset_between({"start_usec": 1000, "end_usec": 1010, "age_usec": 100},
			{"start_usec": 5000, "end_usec": 5010, "age_usec": 100}))
	_temp_dir = OS.get_cache_dir().path_join("openrc-lighting-capture-profile-%d" % Time.get_ticks_usec())
	_check("temporary test directory is absolute", _temp_dir.is_absolute_path())
	var mkdir_error := DirAccess.make_dir_recursive_absolute(_temp_dir)
	_check("temporary test directory is created", mkdir_error == OK)
	if mkdir_error != OK:
		_finish()
		return

	var profile := _trail_profile()
	var profile_check: Dictionary = LightingProfile.validate(profile)
	_check("two-cue aerobatics trail profile validates", bool(profile_check.get("ok", false)), str(profile_check.get("errors", [])))
	var valid_path := _temp_dir.path_join("trail-profile.json")
	_check("fixture profile can be written", _write_text(valid_path, JSON.stringify(profile, "\t") + "\n"))
	var loaded: Dictionary = Capture.read_lighting_profile_file(valid_path)
	_check("bounded absolute profile file is admitted and normalized", bool(loaded.get("ok", false)), str(loaded.get("error", "")))
	_check("loader preserves enabled trail cues", bool(loaded.get("ok", false))
		and loaded.profile == profile_check.profile
		and loaded.profile.effects.size() == 2
		and loaded.profile.effects.all(func(effect: Dictionary) -> bool:
			return effect.kind == "trail" and effect.enabled and effect.lifetime_ticks == 480)
		and loaded.profile.sequence.size() == 2
		and loaded.profile.sequence[0].effect_anchor_ids.size() == 2
		and loaded.profile.sequence[1].effect_anchor_ids.is_empty())
	_check("profile SHA-256 covers the exact input bytes", bool(loaded.get("ok", false))
		and str(loaded.get("sha256", "")) == FileAccess.get_sha256(valid_path))

	var ambiguous := Capture.validate_lighting_profile_options({"lighting-profile": valid_path, "lighting-preset": "festival"})
	_check("profile and preset are mutually exclusive", not bool(ambiguous.get("ok", false)))
	var real_time := Capture.validate_lighting_profile_options({"lighting-profile": valid_path, "frametimes": "capture.json"})
	_check("custom profile is rejected from real-time measurement", not bool(real_time.get("ok", false)))
	var profile_only := Capture.validate_lighting_profile_options({"lighting-profile": valid_path})
	_check("offline profile-only mode is accepted", bool(profile_only.get("ok", false)))
	var preset_only := Capture.validate_lighting_profile_options({"lighting-preset": "festival", "frametimes": "capture.json"})
	_check("existing preset real-time mode remains accepted", bool(preset_only.get("ok", false)))
	_check("per-frame workload audit is admitted only as an explicit real-time option",
		Capture.validate_lighting_profile_options({"lighting-preset": "festival", "frametimes": "capture.json", "lighting-workload-audit": "on"}).ok)
	_check("workload audit cannot silently run in offline capture",
		not Capture.validate_lighting_profile_options({"lighting-preset": "festival", "lighting-workload-audit": "on"}).ok)
	for audit_option: Variant in ["yes", "", true, 1]:
		_check("invalid workload audit choice is refused: " + str(audit_option),
			not Capture.validate_lighting_profile_options({"frametimes": "capture.json", "lighting-workload-audit": audit_option}).ok)
	for landscape: String in ["club_field", "green_paradise"]:
		_check("registered capture landscape is admitted: " + landscape,
			Capture.validate_lighting_profile_options({"lighting-preset": "festival", "landscape": landscape}).ok)
	for landscape: Variant in ["unknown", "", true]:
		_check("invalid capture landscape cannot silently fall back: " + str(landscape),
			not Capture.validate_lighting_profile_options({"lighting-preset": "festival", "landscape": landscape}).ok)
	_check("stock smoke is an explicit supported lighting workload",
		Capture.validate_lighting_profile_options({"lighting-preset": "festival", "lighting-smoke": "stock"}).ok)
	_check("unsupported smoke modes are refused",
		not Capture.validate_lighting_profile_options({"lighting-preset": "festival", "lighting-smoke": "dense"}).ok)
	_check("smoke workload cannot silently affect a nonlighting shot",
		not Capture.validate_lighting_profile_options({"lighting-smoke": "stock"}).ok)
	for option: String in ["companions", "companions-seed", "companions-record"]:
		_check("capture refuses unsupported companion option " + option,
			not Capture.validate_lighting_profile_options({"lighting-preset": "festival", option: "3"}).ok)
	for preset: String in ["off", "classic_rc", "night_radian", "neon_rgb", "night_aerobatics", "festival"]:
		_check("normal flight admits immutable preset " + preset,
			Capture.validate_lighting_profile_options({"lighting-flight": "normal", "lighting-preset": preset, "companions": "3"}).ok)
	_check("normal flight refuses custom profile files", not Capture.validate_lighting_profile_options({"lighting-flight": "normal", "lighting-profile": valid_path}).ok)
	_check("normal flight requires explicit preset", not Capture.validate_lighting_profile_options({"lighting-flight": "normal"}).ok)
	_check("normal workload refuses companion recording overhead", not Capture.validate_lighting_profile_options({"lighting-flight": "normal", "lighting-preset": "festival", "companions-record": "capture"}).ok)
	for preset: String in ["custom", "unknown", ""]:
		_check("normal flight refuses unsupported preset " + preset,
			not Capture.validate_lighting_profile_options({"lighting-flight": "normal", "lighting-preset": preset}).ok)
	for bare: String in ["--lighting-flight", "--lighting-workload-audit", "--lighting-smoke"]:
		var parsed := Capture._parse_options(PackedStringArray([bare, "--lighting-preset=festival", "--frametimes=a.json"]))
		_check("bare enum option cannot silently fall back: " + bare, not Capture.validate_lighting_profile_options(parsed).ok)
	_check("default Workshop still rejects bare companion option", not Capture.validate_lighting_profile_options(Capture._parse_options(PackedStringArray(["--companions", "--lighting-preset=festival"]))).ok)
	_check("profile evidence hash retains float64 distinctions", Capture._sha256_json({"brightness": 1.000000001}) != Capture._sha256_json({"brightness": 1.000000002}))
	_check("profile evidence hash ignores dictionary insertion order", Capture._sha256_json({"a": 1, "b": 2}) == Capture._sha256_json({"b": 2, "a": 1}))
	_check("stock-selected disabled smoke is a valid OFF state", not Capture._smoke_evidence_active({"mode": "stock", "disabled": true, "requested": false}))
	var manifest_path := _temp_dir.path_join("manifest.json")
	_check("profile input cannot collide with the output manifest",
		Capture.lighting_profile_collides_with_manifest(manifest_path, _temp_dir))
	if OS.get_name() == "Windows":
		_check("manifest collision check is case-insensitive on Windows",
			Capture.lighting_profile_collides_with_manifest(_temp_dir.to_upper().path_join("MANIFEST.JSON"), _temp_dir))

	var malformed_path := _temp_dir.path_join("malformed.json")
	_check("malformed JSON fixture can be written", _write_text(malformed_path, "{not-json"))
	var malformed := Capture.read_lighting_profile_file(malformed_path)
	_check("malformed JSON is refused", not bool(malformed.get("ok", false)))
	var schema_path := _temp_dir.path_join("invalid-schema.json")
	_check("invalid schema fixture can be written", _write_text(schema_path, "{\"format\":\"wrong\"}"))
	var invalid_schema := Capture.read_lighting_profile_file(schema_path)
	_check("valid JSON with an unsupported schema is refused", not bool(invalid_schema.get("ok", false)))
	var missing := Capture.read_lighting_profile_file(_temp_dir.path_join("missing.json"))
	_check("missing absolute profile is refused", not bool(missing.get("ok", false)))
	var relative := Capture.read_lighting_profile_file("relative-trail-profile.json")
	_check("relative profile path is refused before file access", not bool(relative.get("ok", false)))
	var empty_path := _temp_dir.path_join("empty.json")
	_check("empty profile fixture can be written", _write_text(empty_path, ""))
	var empty := Capture.read_lighting_profile_file(empty_path)
	_check("empty profile is refused", not bool(empty.get("ok", false)))
	var oversized_path := _temp_dir.path_join("oversized.json")
	_check("oversized fixture can be written", _write_bytes(oversized_path, _bytes(LightingProfile.MAX_PROFILE_BYTES + 1)))
	var oversized := Capture.read_lighting_profile_file(oversized_path)
	_check("input larger than LightingProfile.MAX_PROFILE_BYTES is refused", not bool(oversized.get("ok", false))
		and str(oversized.get("error", "")).contains("exceeds"))

	if bool(loaded.get("ok", false)):
		var binding: Dictionary = Customization.describe(EXTRA_ID)
		var presentation := Presentation.defaults(binding.bindings) if bool(binding.get("ok", false)) else {}
		presentation["lighting"] = loaded.profile
		var frozen := Trial.freeze({"base_id": EXTRA_ID,
			"base_bytes": FileAccess.get_file_as_bytes(Catalog.entry(EXTRA_ID).data),
			"recipe": {}, "presentation_profile": presentation})
		_check("validated trail profile freezes as an Extra Workshop trial", bool(frozen.get("ok", false)), str(frozen.get("errors", [])))
		_check("frozen trial retains a bound presentation identity", bool(frozen.get("ok", false))
			and not frozen.get("presentation_identity", {}).is_empty()
			and not str(frozen.presentation_identity.get("sha256", "")).is_empty()
			and frozen.presentation_profile.lighting == loaded.profile)

	_test_smoke_workload()
	var output_path := _option("trail-profile-out")
	if not output_path.is_empty():
		_export_profile(profile, output_path)

	_cleanup_temp()
	_finish()


func _test_smoke_workload() -> void:
	var lighting := LightingProfile.preset("festival")
	var baseline := Capture.freeze_lighting_trial("jensen-das-ugly-stik-60", lighting)
	var smoky := Capture.freeze_lighting_trial("jensen-das-ugly-stik-60", lighting, "stock")
	_check("baseline capture retains an empty smoke selection", baseline.get("ok", false)
		and baseline.get("trial", {}).get("presentation_profile", {}).get("smoke", [null]).is_empty(), str(baseline.get("errors", [])))
	_check("stock smoke freezes through the production Workshop contract", smoky.get("ok", false), str(smoky.get("errors", [])))
	if baseline.get("ok", false) and smoky.get("ok", false):
		_check("stock smoke does not change physical trial identity or compiled data",
			baseline.trial.identity == smoky.trial.identity and baseline.trial.data == smoky.trial.data)
		_check("stock smoke installs both authored outlets and retains lighting",
			smoky.trial.presentation_profile.smoke.size() == 2
			and smoky.trial.presentation_profile.smoke.any(func(entry: Dictionary) -> bool: return entry.slot == "source_exhaust")
			and smoky.trial.presentation_profile.smoke.any(func(entry: Dictionary) -> bool: return entry.slot == "show_exhaust")
			and smoky.trial.presentation_profile.lighting == baseline.trial.presentation_profile.lighting
			and not str(smoky.smoke_preset).is_empty())
		_check("smoke workload changes presentation identity only",
			smoky.trial.presentation_identity.sha256 != baseline.trial.presentation_identity.sha256)
	_check("invalid direct smoke mode is refused", not Capture.freeze_lighting_trial("jensen-das-ugly-stik-60", lighting, "bad").ok)
	var electric := Capture.freeze_lighting_trial("skywalker-x8", lighting, "stock")
	_check("electric aircraft cannot silently substitute missing stock smoke", not electric.get("ok", true)
		and str(electric.get("errors", [])).contains("no supported stock smoke"), str(electric.get("errors", [])))
	var unlit := LightingProfile.defaults()
	unlit.selection = "disabled"
	var smoky_off := Capture.freeze_lighting_trial("jensen-das-ugly-stik-60", unlit, "stock")
	_check("OFF baseline keeps the same smoke workload as Festival", smoky_off.get("ok", false) and smoky.get("ok", false)
		and smoky_off.trial.presentation_profile.smoke == smoky.trial.presentation_profile.smoke
		and smoky_off.trial.identity == smoky.trial.identity)


static func _trail_profile() -> Dictionary:
	var profile: Dictionary = LightingProfile.preset("night_aerobatics")
	profile["selection"] = "custom"
	var cue_pattern: Dictionary = {}
	var zones: Array = profile.zones
	for index in zones.size():
		var zone: Dictionary = zones[index].duplicate(true)
		if str(zone.get("id", "")) in ["strip_left", "strip_right"]:
			if cue_pattern.is_empty():
				cue_pattern = zone.pattern.duplicate(true)
			zone.pattern.id = "sequence"
			zones[index] = zone
	profile["zones"] = zones
	var effects: Array = profile.effects
	for index in effects.size():
		var effect: Dictionary = effects[index].duplicate(true)
		effect["kind"] = "trail"
		effect["enabled"] = true
		effect["intensity"] = 0.6
		effect["lifetime_ticks"] = 480
		effect["required"] = true
		effects[index] = effect
	profile["effects"] = effects
	profile["sequence"] = [
		{"id": "trail_birth", "duration_ticks": 480, "pattern": cue_pattern,
			"zone_ids": ["strip_left", "strip_right"],
			"effect_anchor_ids": ["vfx_tip_left", "vfx_tip_right"]},
		{"id": "trail_fade", "duration_ticks": 960, "pattern": cue_pattern,
			"zone_ids": ["strip_left", "strip_right"], "effect_anchor_ids": []},
	]
	var checked: Dictionary = LightingProfile.validate(profile)
	return checked.profile if bool(checked.get("ok", false)) else profile


func _export_profile(profile: Dictionary, path: String) -> void:
	_check("profile artifact output path is absolute", path.is_absolute_path())
	if not path.is_absolute_path():
		return
	_check("profile artifact output path is new", not FileAccess.file_exists(path))
	if FileAccess.file_exists(path):
		return
	var directory_error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_check("profile artifact directory is created", directory_error == OK)
	if directory_error != OK:
		return
	_check("validated profile artifact is written", _write_text(path, JSON.stringify(profile, "\t") + "\n"))
	var exported: Dictionary = Capture.read_lighting_profile_file(path)
	_check("exported profile artifact round-trips through capture admission", bool(exported.get("ok", false))
		and exported.profile == profile and str(exported.get("sha256", "")) == FileAccess.get_sha256(path),
		str(exported.get("error", "")))
	print("LIGHTING_CAPTURE_PROFILE_ARTIFACT ", path)


func _option(key: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--%s=" % key):
			return argument.trim_prefix("--%s=" % key)
	return ""


func _write_text(path: String, value: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(value)
	file.close()
	return true


func _write_bytes(path: String, value: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(value)
	file.close()
	return true


func _bytes(count: int) -> PackedByteArray:
	var value := PackedByteArray()
	value.resize(count)
	value.fill(120)
	return value


func _cleanup_temp() -> void:
	if _temp_dir.is_empty():
		return
	for filename: String in ["trail-profile.json", "malformed.json", "invalid-schema.json", "empty.json", "oversized.json"]:
		var path := _temp_dir.path_join(filename)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(_temp_dir)


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: ", label, " ", detail)


func _test_workload_audit() -> void:
	var audit := WorkloadAudit.new()
	_check("empty workload audit cannot claim coverage", not audit.report().ok)
	_check("disabled helpers have zero counts", audit.record(_audit_budget(), 10, 0, 0.0))
	_check("brief spark between one-second polls is recorded", audit.record(_audit_budget({"sparks_cpu_live": 32, "sparks_gpu_instance_capacity": 512}), 11, 1, 0.016))
	_check("uncapped presentation may repeat a physics tick", audit.record(_audit_budget(), 11, 2, 0.020))
	_check("second cue is recorded", audit.record(_audit_budget({"sparks_cpu_live": 16}), 12, 3, 0.030))
	var report := audit.report()
	_check("audit retains exact peak and first occurrence", report.metrics.sparks_cpu_live.max == 32
		and report.metrics.sparks_cpu_live.first_peak_frame == 1 and report.metrics.sparks_cpu_live.first_peak_tick == 11)
	_check("brief event frames and separate rising edges survive zero polls", report.metrics.sparks_cpu_live.positive_frames == 2
		and report.metrics.sparks_cpu_live.rising_edges == 2 and report.observed_frames == 4)
	_check("CPU live count and GPU allocation remain distinct", report.metrics.sparks_gpu_capacity.max == 512)
	_check("audit timing is explicitly ineligible", not report.timing_qualification_eligible)
	report.metrics.sparks_cpu_live.max = 999
	_check("exported report cannot mutate audit state", audit.report().metrics.sparks_cpu_live.max == 32)
	_check("rewound ticks are refused", not audit.record(_audit_budget(), 9, 4, 0.04))
	_check("failure is sticky and retains accepted prefix", not audit.record(_audit_budget(), 13, 4, 0.05) and audit.report().observed_frames == 4)
	var gap := WorkloadAudit.new()
	_check("missing initial frame cannot claim complete coverage", not gap.record(_audit_budget(), 1, 1, 0.0))
	var backward_clock := WorkloadAudit.new()
	backward_clock.record(_audit_budget(), 1, 0, 1.0)
	_check("backward wall clock is refused", not backward_clock.record(_audit_budget(), 2, 1, 0.5))
	for bad: Variant in [-1, NAN, INF, "32", true, 0.5, 1e13]:
		var invalid := WorkloadAudit.new()
		_check("invalid metric does not commit a partial frame: " + str(bad),
			not invalid.record(_audit_budget({"sparks_cpu_live": bad}), 1, 0, 0.0) and invalid.report().observed_frames == 0)
	var malformed := WorkloadAudit.new()
	_check("malformed helper parent is refused", not malformed.record({"vfx": 0}, 1, 0, 0.0))
	var missing := WorkloadAudit.new()
	_check("empty budget source is not accepted as zero workload", not missing.record({}, 1, 0, 0.0))
	var partial := WorkloadAudit.new()
	var partial_budget := _audit_budget()
	partial_budget.vfx.effects_allocated = 2
	partial_budget.vfx.erase("sparks_cpu_live")
	_check("active helper must supply every audited metric", not partial.record(partial_budget, 1, 0, 0.0))
	var explicit_disabled := _audit_budget()
	explicit_disabled.vfx = {"effects_allocated": 0}
	explicit_disabled.skins = {"targets": 0}
	_check("explicit absent helper remains a valid zero workload", WorkloadAudit.new().record(explicit_disabled, 1, 0, 0.0))


func _audit_budget(vfx_overrides: Dictionary = {}) -> Dictionary:
	var vfx := {"effects_allocated": 2, "sparks_cpu_live": 0, "trails_cpu_live": 0,
		"sparks_gpu_instance_capacity": 0, "trails_gpu_instance_capacity": 0,
		"gpu_anchors_allocated": 0, "spill_lights_allocated": 0}
	vfx.merge(vfx_overrides, true)
	return {"active": true, "selection": "preset", "frame_parameter_writes": 0,
		"vfx": vfx, "skins": {"targets": 0}}


func _finish() -> void:
	print("Lighting capture profile: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
