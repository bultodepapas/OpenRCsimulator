extends SceneTree

const Config: Script = preload("res://environment/time_of_day_config.gd")
const Timeline: Script = preload("res://environment/visual_timeline.gd")
const Lighting: Script = preload("res://render/time_of_day_lighting.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_check_creation_and_copying()
	_check_profile_identity()
	_check_ordered_evaluation()
	_check_strict_schema()
	_check_ticks()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check_creation_and_copying() -> void:
	var config: Dictionary = Config.defaults()
	var created: Dictionary = Timeline.create(config, 7)
	_check("valid fixed-time timeline is created", bool(created.ok), str(created.errors))
	if not bool(created.ok):
		return
	var timeline: Dictionary = created.timeline
	_check("schema stores explicit format, zero rate, anchor and empty event array",
		timeline.format == "openrc-visual-timeline v1" and timeline.anchor_tick == 7
		and timeline.rate == 0.0 and timeline.events.is_empty())
	_check("initial identity is derived from the normalized config",
		timeline.initial.config == config and timeline.initial.profile == "legacy-spec"
		and timeline.initial.config_sha256 == JSON.stringify(config, "", true, true).sha256_text())
	config["location_name"] = "mutated source"
	_check("create detaches config input", timeline.initial.config.location_name == "Reference field (synthetic)")

	var checked: Dictionary = Timeline.validate(timeline)
	_check("valid schema round-trips through validation", bool(checked.ok) and checked.timeline == timeline, str(checked.errors))
	timeline.initial.config.location_name = "mutated source timeline"
	_check("validate returns a detached copy", checked.timeline.initial.config.location_name == "Reference field (synthetic)")


func _check_profile_identity() -> void:
	var defaults: Dictionary = Config.defaults()
	var legacy_context: Dictionary = Lighting.context(defaults, Lighting.snapshot(defaults))
	_check("legacy profile identity stays aligned with renderer context",
		Timeline.PROFILE_LEGACY == str(legacy_context.profile), str(legacy_context.profile))
	_check("astronomical profile identity stays aligned with renderer curve revision",
		Timeline.PROFILE_ASTRONOMICAL == Lighting.PROFILE, str(Lighting.PROFILE))


func _check_ordered_evaluation() -> void:
	var initial: Dictionary = Timeline.create(Config.defaults(), 5).timeline
	var astro: Dictionary = Config.defaults()
	astro.mode = "astronomical"
	astro.local_seconds = 64800
	var first_edit: Dictionary = Timeline.append_config_edit(initial, 10, astro)
	_check("legacy to astronomical edit is accepted", bool(first_edit.ok), str(first_edit.errors))
	if not bool(first_edit.ok):
		return
	var at_same_tick: Dictionary = Timeline.append_config_edit(first_edit.timeline, 10, Config.defaults())
	_check("same-tick edit is retained for deterministic last-wins ordering", bool(at_same_tick.ok)
		and at_same_tick.timeline.events.size() == 2, str(at_same_tick.errors))
	if not bool(at_same_tick.ok):
		return
	var later: Dictionary = Timeline.append_config_edit(at_same_tick.timeline, 12, astro)
	_check("later config edit is accepted", bool(later.ok) and later.timeline.events.size() == 3, str(later.errors))
	if not bool(later.ok):
		return

	var before: Dictionary = Timeline.evaluate(later.timeline, 9)
	var same_tick: Dictionary = Timeline.evaluate(later.timeline, 10)
	var between: Dictionary = Timeline.evaluate(later.timeline, 11)
	var after: Dictionary = Timeline.evaluate(later.timeline, 12)
	_check("evaluation before the first edit returns the initial context",
		bool(before.ok) and before.config.mode == "legacy" and before.profile == "legacy-spec", str(before.errors))
	_check("ordered same-tick edits resolve to the last appended config",
		bool(same_tick.ok) and same_tick.config.mode == "legacy" and same_tick.profile == "legacy-spec", str(same_tick.errors))
	_check("evaluation between edits holds the last known selection",
		bool(between.ok) and between.config.mode == "legacy" and between.tick == 11, str(between.errors))
	_check("evaluation at the later edit switches profile and config",
		bool(after.ok) and after.config.mode == "astronomical" and after.profile == "openrc-lighting-curves v1"
		and after.anchor_tick == 5 and after.rate == 0.0, str(after.errors))

	var first_state: Dictionary = Timeline.evaluate(later.timeline, 12)
	first_state.config.local_seconds = 0
	var second_state: Dictionary = Timeline.evaluate(later.timeline, 12)
	_check("evaluation config is detached and repeated evaluation is deterministic",
		second_state.config.local_seconds == 64800 and second_state == Timeline.evaluate(later.timeline, 12))
	_check("append leaves the previous timeline unchanged", initial.events.is_empty() and first_edit.timeline.events.size() == 1)

	var before_anchor: Dictionary = Timeline.evaluate(later.timeline, 4)
	_check("evaluation before the anchor reports explicit future context error",
		not bool(before_anchor.ok) and str(before_anchor.errors).contains("precedes timeline.anchor_tick"), str(before_anchor.errors))
	var future_event_eval: Dictionary = Timeline.evaluate(later.timeline, 11)
	_check("future edit events do not contaminate historical evaluation",
		bool(future_event_eval.ok) and future_event_eval.config.mode == "legacy", str(future_event_eval.errors))


func _check_strict_schema() -> void:
	var valid: Dictionary = Timeline.create(Config.defaults(), 0).timeline
	var missing: Dictionary = valid.duplicate(true)
	missing.erase("events")
	_check("missing timeline fields are rejected", not Timeline.validate(missing).ok and str(Timeline.validate(missing).errors).contains("events"))
	var unknown: Dictionary = valid.duplicate(true)
	unknown["future_mode"] = true
	_check("unknown timeline fields are rejected", not Timeline.validate(unknown).ok)
	var wrong_version: Dictionary = valid.duplicate(true)
	wrong_version.format = "openrc-visual-timeline v2"
	_check("unknown timeline version is rejected", not Timeline.validate(wrong_version).ok)
	var moving_rate: Dictionary = valid.duplicate(true)
	moving_rate.rate = 1.0
	_check("v1 rejects a nonzero progression rate", not Timeline.validate(moving_rate).ok and str(Timeline.validate(moving_rate).errors).contains("rate"))
	var bad_hash: Dictionary = valid.duplicate(true)
	bad_hash.initial.config_sha256 = "not-the-config-hash"
	_check("initial config identity tampering is rejected", not Timeline.validate(bad_hash).ok and str(Timeline.validate(bad_hash).errors).contains("config_sha256"))
	var bad_profile: Dictionary = valid.duplicate(true)
	bad_profile.initial.profile = "other-profile"
	_check("initial profile mismatch is rejected", not Timeline.validate(bad_profile).ok and str(Timeline.validate(bad_profile).errors).contains("profile"))
	var changed_config: Dictionary = valid.duplicate(true)
	changed_config.initial.config.mode = "astronomical"
	_check("config edits cannot bypass profile/hash identity", not Timeline.validate(changed_config).ok)
	_check("missing context is explicit during evaluation",
		not Timeline.evaluate(null, 0).ok and not Timeline.evaluate(null, 0).errors.is_empty())
	_check("invalid config prevents timeline creation", not Timeline.create({}, 0).ok)


func _check_ticks() -> void:
	var config: Dictionary = Config.defaults()
	var valid_max: Dictionary = Timeline.create(config, Timeline.MAX_SAFE_TICK)
	_check("largest safe JSON tick is accepted", bool(valid_max.ok) and valid_max.timeline.anchor_tick == Timeline.MAX_SAFE_TICK, str(valid_max.errors))
	_check("zero tick is accepted", bool(Timeline.create(config, 0).ok))
	for invalid_tick: Variant in [true, false, -1, 1.5, NAN, INF, Timeline.MAX_SAFE_TICK + 1]:
		_check("create rejects invalid tick %s" % str(invalid_tick), not Timeline.create(config, invalid_tick).ok)
	var anchor: Dictionary = Timeline.create(config, 8).timeline
	for invalid_tick: Variant in [true, 3.25, NAN, INF, -1, Timeline.MAX_SAFE_TICK + 1]:
		_check("append rejects invalid tick %s" % str(invalid_tick), not Timeline.append_config_edit(anchor, invalid_tick, config).ok)
	_check("append rejects events before anchor", not Timeline.append_config_edit(anchor, 7, config).ok)
	var event_at_10: Dictionary = Timeline.append_config_edit(anchor, 10, config)
	_check("ordered append baseline is valid", bool(event_at_10.ok))
	if bool(event_at_10.ok):
		_check("append rejects events before the latest event", not Timeline.append_config_edit(event_at_10.timeline, 9, config).ok)
	for invalid_tick: Variant in [true, 2.5, NAN, INF, -1, Timeline.MAX_SAFE_TICK + 1]:
		_check("evaluate rejects invalid tick %s" % str(invalid_tick), not Timeline.evaluate(anchor, invalid_tick).ok)
	_check("evaluation accepts maximum safe tick", bool(Timeline.evaluate(anchor, Timeline.MAX_SAFE_TICK).ok))


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])
