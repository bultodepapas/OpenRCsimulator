## TOD-09c1: fixed and progressing visual timeline schemas, transitions, and replay.
extends SceneTree

const Config: Script = preload("res://environment/time_of_day_config.gd")
const Timeline: Script = preload("res://environment/visual_timeline.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_creation_and_round_trip()
	_midnight_and_leap_day()
	_rate_and_config_transitions()
	_ordering_and_evaluation()
	_strict_v2_validation()
	_same_tick_and_tamper_boundaries()
	_mixed_history_json_round_trip()
	_v1_compatibility_and_promotion()
	print("TOD-09c1 visual timeline: %d checks, %d failed" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check(label: String, valid: bool, detail: String = "") -> void:
	checks += 1
	if not valid:
		failures += 1
		printerr("FAIL " + label + (": " + detail if not detail.is_empty() else ""))


func _astronomical(date: String = "2024-12-31", seconds: int = 86399) -> Dictionary:
	var config: Dictionary = Config.defaults()
	config.mode = "astronomical"
	config.date = date
	config.local_seconds = seconds
	return config


func _creation_and_round_trip() -> void:
	var config: Dictionary = _astronomical("2024-12-31", 86399)
	var created: Dictionary = Timeline.create_progressing(config, 17, 1)
	_check("creates explicit v2 progressing schema", created.ok
		and created.timeline.format == "openrc-visual-timeline v2"
		and created.timeline.anchor_tick == 17
		and created.timeline.ticks_per_second == 240
		and created.timeline.initial.clock.rate == 1
		and created.timeline.initial.clock.subsecond_ticks == 0
		and created.timeline.events.is_empty(), str(created.get("errors", [])))
	if not created.ok:
		return

	var timeline: Dictionary = created.timeline
	config.location_name = "mutated caller input"
	_check("creation detaches the config input",
		timeline.initial.clock.config.location_name == "Reference field (synthetic)")
	var encoded: String = JSON.stringify(timeline, "", true, true)
	var decoded: Variant = JSON.parse_string(encoded)
	var restored: Dictionary = Timeline.validate(decoded)
	_check("v2 survives normalized JSON round trip",
		restored.ok and restored.timeline == timeline, str(restored.get("errors", [])))
	var sample: Dictionary = Timeline.evaluate(restored.timeline, 17)
	_check("evaluation exposes restart config and integer phase",
		sample.ok and sample.config == timeline.initial.clock.config
		and sample.configured_start == timeline.initial.clock.config
		and sample.subsecond_ticks == 0 and sample.rate == 1, str(sample.get("errors", [])))

	var detached: Dictionary = Timeline.validate(timeline)
	timeline.initial.clock.config.location_name = "mutated returned timeline"
	_check("validation returns a detached normalized timeline",
		detached.ok and detached.timeline.initial.clock.config.location_name == "Reference field (synthetic)")


func _midnight_and_leap_day() -> void:
	var year_start: Dictionary = Timeline.create_progressing(_astronomical("2024-12-31", 86399), 9, 1).timeline
	var before_midnight: Dictionary = Timeline.evaluate(year_start, 248)
	var new_year: Dictionary = Timeline.evaluate(year_start, 249)
	_check("subsecond phase remains exact before midnight",
		before_midnight.ok and before_midnight.config.date == "2024-12-31"
		and before_midnight.config.local_seconds == 86399 and before_midnight.subsecond_ticks == 239)
	_check("240 ticks cross midnight and the Gregorian year",
		new_year.ok and new_year.config.date == "2025-01-01"
		and new_year.config.local_seconds == 0 and new_year.subsecond_ticks == 0)

	var leap_day: Dictionary = Timeline.create_progressing(_astronomical("2024-02-28", 86399), 0, 1).timeline
	var leap: Dictionary = Timeline.evaluate(leap_day, 240)
	_check("progression crosses into Gregorian leap day",
		leap.ok and leap.config.date == "2024-02-29" and leap.config.local_seconds == 0)

	var calendar_end: Dictionary = Timeline.create_progressing(_astronomical("2100-12-31", 86399), 0, 1).timeline
	var overflow: Dictionary = Timeline.evaluate(calendar_end, 240)
	_check("calendar exhaustion fails explicitly",
		not overflow.ok and str(overflow.errors).contains("exceeded the supported calendar ending 2100-12-31"))


func _rate_and_config_transitions() -> void:
	var initial_config: Dictionary = _astronomical("2024-12-31", 86399)
	var initial: Dictionary = Timeline.create_progressing(initial_config, 0, 1).timeline
	var source_before: PackedByteArray = var_to_bytes(initial)
	var stopped: Dictionary = Timeline.append_rate_edit(initial, 119, 0)
	_check("rate stop records the exact fractional phase",
		stopped.ok and stopped.timeline.events.size() == 1
		and stopped.timeline.events[0].kind == "rate"
		and stopped.timeline.events[0].clock.subsecond_ticks == 119, str(stopped.get("errors", [])))
	_check("rate append leaves the source immutable", var_to_bytes(initial) == source_before)
	if not stopped.ok:
		return

	var held: Dictionary = Timeline.evaluate(stopped.timeline, 500)
	_check("stopped rate holds seconds and phase at future ticks",
		held.ok and held.rate == 0 and held.config.date == "2024-12-31"
		and held.config.local_seconds == 86399 and held.subsecond_ticks == 119)
	var resumed: Dictionary = Timeline.append_rate_edit(stopped.timeline, 500, 1)
	_check("resume retains the fractional phase",
		resumed.ok and resumed.timeline.events[1].clock.subsecond_ticks == 119, str(resumed.get("errors", [])))
	if not resumed.ok:
		return
	var after_resume: Dictionary = Timeline.evaluate(resumed.timeline, 621)
	_check("resumed progression completes the original second",
		after_resume.ok and after_resume.config.date == "2025-01-01"
		and after_resume.config.local_seconds == 0 and after_resume.subsecond_ticks == 0)

	var selected_start: Dictionary = _astronomical("2024-02-28", 86399)
	selected_start.location_name = "Restart recipe"
	var edited: Dictionary = Timeline.append_config_edit(resumed.timeline, 550, selected_start)
	_check("explicit config edit resets phase and preserves running rate",
		edited.ok and edited.timeline.events.back().kind == "config"
		and edited.timeline.events.back().clock.rate == 1
		and edited.timeline.events.back().clock.subsecond_ticks == 0, str(edited.get("errors", [])))
	if not edited.ok:
		return
	var edited_start: Dictionary = Timeline.evaluate(edited.timeline, 550)
	var edited_later: Dictionary = Timeline.evaluate(edited.timeline, 790)
	_check("configured_start remains the explicit restart recipe",
		edited_start.ok and edited_start.configured_start == selected_start
		and edited_later.configured_start == selected_start)
	_check("selected leap-day recipe progresses from a zero phase",
		edited_later.ok and edited_later.config.date == "2024-02-29"
		and edited_later.config.local_seconds == 0)

	var legacy_edit: Dictionary = Timeline.append_config_edit(edited.timeline, 800, Config.defaults())
	var legacy_sample: Dictionary = Timeline.evaluate(legacy_edit.timeline, 1000) if legacy_edit.ok else {}
	_check("selecting legacy config stops progression and resets phase",
		legacy_edit.ok and legacy_edit.timeline.events.back().clock.rate == 0
		and legacy_edit.timeline.events.back().clock.subsecond_ticks == 0
		and legacy_sample.ok and legacy_sample.rate == 0
		and legacy_sample.config == Config.defaults()
		and legacy_sample.configured_start == Config.defaults(), str(legacy_edit.get("errors", [])))

	var forged: Dictionary = stopped.timeline.duplicate(true)
	forged.events[0].clock.subsecond_ticks = 118
	var forged_check: Dictionary = Timeline.validate(forged)
	_check("rate-event phase forgery is rejected",
		not forged_check.ok and str(forged_check.errors).contains("preserve the prior phase"))


func _ordering_and_evaluation() -> void:
	var initial: Dictionary = Timeline.create_progressing(_astronomical("2024-06-01", 43200), 100, 1).timeline
	var past_append: Dictionary = Timeline.append_rate_edit(initial, 99, 0)
	_check("edits before the anchor are rejected", not past_append.ok)
	var future_config: Dictionary = _astronomical("2025-05-01", 100)
	var future: Dictionary = Timeline.append_config_edit(initial, 1000, future_config)
	_check("future config event is accepted", future.ok, str(future.get("errors", [])))
	if not future.ok:
		return
	var before_event: Dictionary = Timeline.evaluate(future.timeline, 999)
	var at_event: Dictionary = Timeline.evaluate(future.timeline, 1000)
	var before_anchor: Dictionary = Timeline.evaluate(future.timeline, 99)
	_check("future event does not affect earlier evaluation",
		before_event.ok and before_event.configured_start == initial.initial.clock.config
		and before_event.config.date == "2024-06-01")
	_check("event takes effect at its exact tick",
		at_event.ok and at_event.configured_start == future_config
		and at_event.config.date == future_config.date and at_event.subsecond_ticks == 0)
	_check("evaluation before anchor fails explicitly",
		not before_anchor.ok and str(before_anchor.errors).contains("precedes timeline.anchor_tick"))

	var out_of_order: Dictionary = Timeline.append_rate_edit(future.timeline, 999, 0)
	_check("edits earlier than a future event are rejected", not out_of_order.ok)
	var same_tick_first: Dictionary = Timeline.append_config_edit(future.timeline, 1000, _astronomical("2026-01-01", 0))
	var same_tick_last: Dictionary = Timeline.append_config_edit(
		same_tick_first.timeline, 1000, _astronomical("2027-01-01", 0)
	) if same_tick_first.ok else {}
	var last_wins: Dictionary = Timeline.evaluate(same_tick_last.timeline, 1000) if same_tick_last.ok else {}
	_check("equal-tick events retain array order with last selection winning",
		same_tick_first.ok and same_tick_last.ok and same_tick_last.timeline.events.size() == 3
		and last_wins.ok and last_wins.configured_start.date == "2027-01-01")


func _strict_v2_validation() -> void:
	var valid: Dictionary = Timeline.create_progressing(_astronomical(), 0, 1).timeline
	var wrong_frequency: Dictionary = valid.duplicate(true)
	wrong_frequency.ticks_per_second = 120
	_check("wrong timeline frequency is rejected", not Timeline.validate(wrong_frequency).ok)
	var fractional_frequency: Dictionary = valid.duplicate(true)
	fractional_frequency.ticks_per_second = 240.5
	_check("fractional timeline frequency is rejected", not Timeline.validate(fractional_frequency).ok)
	var boolean_frequency: Dictionary = valid.duplicate(true)
	boolean_frequency.ticks_per_second = true
	_check("boolean timeline frequency is rejected", not Timeline.validate(boolean_frequency).ok)
	var inner_frequency: Dictionary = valid.duplicate(true)
	inner_frequency.initial.clock.ticks_per_second = 120
	_check("clock frequency is validated independently", not Timeline.validate(inner_frequency).ok)

	var fractional_anchor: Dictionary = valid.duplicate(true)
	fractional_anchor.initial.clock.subsecond_ticks = 1
	_check("v2 initial anchor must have zero fractional phase", not Timeline.validate(fractional_anchor).ok)
	var unknown_field: Dictionary = valid.duplicate(true)
	unknown_field.extra = true
	_check("unknown v2 fields are rejected", not Timeline.validate(unknown_field).ok)
	var wrong_version: Dictionary = valid.duplicate(true)
	wrong_version.format = "openrc-visual-timeline v3"
	_check("unknown timeline version is rejected", not Timeline.validate(wrong_version).ok)
	var changed_hash: Dictionary = valid.duplicate(true)
	changed_hash.initial.config_sha256 = "forged"
	_check("config identity hash is enforced", not Timeline.validate(changed_hash).ok)
	var changed_profile: Dictionary = valid.duplicate(true)
	changed_profile.initial.profile = "unrecognized"
	_check("profile identity is enforced", not Timeline.validate(changed_profile).ok)
	var null_initial: Dictionary = valid.duplicate(true)
	null_initial.initial = null
	_check("null initial record is rejected", not Timeline.validate(null_initial).ok)
	var missing_initial_clock: Dictionary = valid.duplicate(true)
	missing_initial_clock.initial.erase("clock")
	_check("missing initial clock is rejected", not Timeline.validate(missing_initial_clock).ok)
	var null_events: Dictionary = valid.duplicate(true)
	null_events.events = null
	_check("null events collection is rejected", not Timeline.validate(null_events).ok)

	for malformed: Variant in [null, [], "timeline", true]:
		_check("malformed v2 root is rejected: " + str(malformed), not Timeline.validate(malformed).ok)


func _same_tick_and_tamper_boundaries() -> void:
	var original: Dictionary = Timeline.create_progressing(_astronomical(), 0, 1).timeline
	var selected: Dictionary = _astronomical("2025-03-04", 1200)
	selected.location_name = "same tick selection"

	var config_then_rate: Dictionary = Timeline.append_config_edit(original, 10, selected)
	var config_then_rate_2: Dictionary = Timeline.append_rate_edit(config_then_rate.timeline, 10, 0) if config_then_rate.ok else {}
	var config_then_rate_sample: Dictionary = Timeline.evaluate(config_then_rate_2.timeline, 10) if config_then_rate_2.ok else {}
	_check("same-tick config then rate keeps selected start and resets phase",
		config_then_rate.ok and config_then_rate_2.ok
		and config_then_rate_2.timeline.events.size() == 2
		and config_then_rate_2.timeline.events[0].kind == "config"
		and config_then_rate_2.timeline.events[1].kind == "rate"
		and config_then_rate_sample.ok and config_then_rate_sample.rate == 0
		and config_then_rate_sample.subsecond_ticks == 0
		and config_then_rate_sample.configured_start == selected)

	var rate_then_config: Dictionary = Timeline.append_rate_edit(original, 10, 0)
	var rate_then_config_2: Dictionary = Timeline.append_config_edit(rate_then_config.timeline, 10, selected) if rate_then_config.ok else {}
	var rate_then_config_sample: Dictionary = Timeline.evaluate(rate_then_config_2.timeline, 10) if rate_then_config_2.ok else {}
	_check("same-tick rate then config preserves ordered reset semantics",
		rate_then_config.ok and rate_then_config_2.ok
		and rate_then_config_2.timeline.events.size() == 2
		and rate_then_config_2.timeline.events[0].kind == "rate"
		and rate_then_config_2.timeline.events[1].kind == "config"
		and rate_then_config_sample.ok and rate_then_config_sample.rate == 0
		and rate_then_config_sample.subsecond_ticks == 0
		and rate_then_config_sample.configured_start == selected)

	var config_event: Dictionary = Timeline.append_config_edit(original, 10, selected)
	var missing_event_clock: Dictionary = config_event.timeline.duplicate(true) if config_event.ok else {}
	if not missing_event_clock.is_empty():
		missing_event_clock.events[0].erase("clock")
	_check("missing event clock is rejected",
		not missing_event_clock.is_empty() and not Timeline.validate(missing_event_clock).ok)

	var fractional_config_event: Dictionary = config_event.timeline.duplicate(true) if config_event.ok else {}
	if not fractional_config_event.is_empty():
		fractional_config_event.events[0].clock.subsecond_ticks = 1
	var fractional_config_check: Dictionary = Timeline.validate(fractional_config_event)
	_check("config event cannot retain or forge a fractional phase",
		not fractional_config_check.ok and str(fractional_config_check.errors).contains("reset phase"))

	var rate_forgery: Dictionary = config_event.timeline.duplicate(true) if config_event.ok else {}
	if not rate_forgery.is_empty():
		rate_forgery.events[0].clock.rate = 0
	var rate_forgery_check: Dictionary = Timeline.validate(rate_forgery)
	_check("astronomical config event cannot silently change rate",
		not rate_forgery_check.ok and str(rate_forgery_check.errors).contains("retain the compatible rate"))

	var stopped: Dictionary = Timeline.append_rate_edit(original, 10, 0)
	var civil_jump: Dictionary = stopped.timeline.duplicate(true) if stopped.ok else {}
	if not civil_jump.is_empty():
		civil_jump.events[0].clock.config.local_seconds = 1
		_rehash_event_identity(civil_jump.events[0])
	var civil_jump_check: Dictionary = Timeline.validate(civil_jump)
	_check("rehashing cannot hide a civil-time jump in a rate event",
		not civil_jump_check.ok and str(civil_jump_check.errors).contains("preserve the prior phase")
		and not str(civil_jump_check.errors).contains("config_sha256"))


func _mixed_history_json_round_trip() -> void:
	var start: Dictionary = Timeline.create_progressing(_astronomical("2024-08-01", 1000), 5, 1).timeline
	var changed_config: Dictionary = _astronomical("2024-08-02", 5000)
	var config_event: Dictionary = Timeline.append_config_edit(start, 20, changed_config)
	var stopped: Dictionary = Timeline.append_rate_edit(config_event.timeline, 37, 0) if config_event.ok else {}
	var resumed: Dictionary = Timeline.append_rate_edit(stopped.timeline, 240, 1) if stopped.ok else {}
	_check("mixed config and rate history is built",
		config_event.ok and stopped.ok and resumed.ok
		and resumed.timeline.events.size() == 3
		and resumed.timeline.events[0].kind == "config"
		and resumed.timeline.events[1].kind == "rate"
		and resumed.timeline.events[2].kind == "rate", str(resumed.get("errors", [])))
	if not resumed.ok:
		return

	var parsed: Variant = JSON.parse_string(JSON.stringify(resumed.timeline, "", true, true))
	var restored: Dictionary = Timeline.validate(parsed)
	var before_edit: Dictionary = Timeline.evaluate(resumed.timeline, 19)
	var after_edit: Dictionary = Timeline.evaluate(resumed.timeline, 300)
	var restored_after_edit: Dictionary = Timeline.evaluate(restored.timeline, 300) if restored.ok else {}
	_check("mixed-event v2 schema survives JSON round trip",
		restored.ok and restored.timeline == resumed.timeline, str(restored.get("errors", [])))
	_check("mixed-event JSON replay retains start, rate, and phase",
		after_edit.ok and restored_after_edit == after_edit
		and before_edit.configured_start.date == "2024-08-01"
		and after_edit.configured_start == changed_config
		and after_edit.rate == 1 and after_edit.subsecond_ticks == 77)


func _rehash_event_identity(event: Dictionary) -> void:
	var config: Dictionary = event.clock.config
	event.config_sha256 = JSON.stringify(config, "", true, true).sha256_text()
	event.profile = "legacy-spec" if str(config.mode) == "legacy" else "openrc-lighting-curves v1"


func _v1_compatibility_and_promotion() -> void:
	var fixed_config: Dictionary = Config.defaults()
	var fixed: Dictionary = Timeline.create(fixed_config, 10).timeline
	var astronomical: Dictionary = _astronomical("2025-01-02", 123)
	var first: Dictionary = Timeline.append_config_edit(fixed, 20, astronomical)
	var second: Dictionary = Timeline.append_config_edit(first.timeline, 20, Config.defaults())
	_check("v1 edit API still stores the exact fixed schema",
		first.ok and second.ok and second.timeline.format == "openrc-visual-timeline v1"
		and second.timeline.rate == 0.0 and second.timeline.events.size() == 2
		and not second.timeline.events[0].has("kind"), str(second.get("errors", [])))
	var fixed_sample: Dictionary = Timeline.evaluate(second.timeline, 20)
	_check("v1 evaluation keeps fixed config behavior and adds restart fields",
		fixed_sample.ok and fixed_sample.rate == 0.0 and fixed_sample.subsecond_ticks == 0
		and fixed_sample.config == Config.defaults()
		and fixed_sample.configured_start == Config.defaults())

	var promoted: Dictionary = Timeline.append_rate_edit(second.timeline, 30, 0)
	_check("first v1 rate edit promotes without losing fixed events",
		promoted.ok and promoted.timeline.format == "openrc-visual-timeline v2"
		and promoted.timeline.events.size() == 3
		and promoted.timeline.events[0].tick == 20
		and promoted.timeline.events[0].clock.config == astronomical
		and promoted.timeline.events[1].tick == 20
		and promoted.timeline.events[1].clock.config == Config.defaults()
		and promoted.timeline.events[2].kind == "rate", str(promoted.get("errors", [])))
	if promoted.ok:
		var at_history: Dictionary = Timeline.evaluate(promoted.timeline, 20)
		_check("promoted equal-tick history keeps last-wins behavior",
			at_history.ok and at_history.config == Config.defaults()
			and at_history.configured_start == Config.defaults() and at_history.rate == 0)
