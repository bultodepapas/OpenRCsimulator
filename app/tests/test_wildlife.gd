extends SceneTree

const WildlifeScript = preload("res://audio/wildlife.gd")
const CLIPS: Dictionary = {
	"bird": [1.8, 2.1, 2.4, 2.0, 2.7, 2.3, 1.9, 2.5, 2.2, 2.6],
	"crow": [1.4, 1.8, 2.0],
	"owl": [2.2, 2.7, 3.0],
	"dog": [1.1, 1.5, 1.9],
}
const STEPS_20_MIN: int = 12000

var _checks: int = 0
var _failures: int = 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if condition else "FAIL ") + label + (" — " + detail if not detail.is_empty() else ""))
	if not condition:
		_failures += 1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_activity_gates()

	# The wildlife scheduler must not advance Godot's global random sequence.
	seed(504112)
	var expected_global: Array[int] = []
	for i: int in range(8):
		expected_global.append(randi())
	seed(504112)

	var day: Dictionary = _snapshot(45.0, 2.0, 16.0)
	var night: Dictionary = _snapshot(-35.0, 2.0, 16.0)
	var day_a: Dictionary = _simulate(86127, day, 5)
	var day_b: Dictionary = _simulate(86127, day, 5)
	var day_other_seed: Dictionary = _simulate(86128, day, 5)
	var night_run: Dictionary = _simulate(86127, night, 5)
	var no_perch_run: Dictionary = _simulate(86127, day, 0)
	var day_events: Array = day_a["events"]
	var night_events: Array = night_run["events"]
	var no_perch_events: Array = no_perch_run["events"]
	var day_counts: Dictionary = _counts(day_events)
	var night_counts: Dictionary = _counts(night_events)
	var no_perch_counts: Dictionary = _counts(no_perch_events)

	_check("20-minute day run emits birds, crows and dogs but no owls",
		int(day_counts.get("bird", 0)) > 0 and int(day_counts.get("crow", 0)) > 0
		and int(day_counts.get("dog", 0)) > 0 and int(day_counts.get("owl", 0)) == 0,
		str(day_counts))
	_check("20-minute night run emits owls and dogs but no birds or crows",
		int(night_counts.get("owl", 0)) > 0 and int(night_counts.get("dog", 0)) > 0
		and int(night_counts.get("bird", 0)) == 0 and int(night_counts.get("crow", 0)) == 0,
		str(night_counts))
	_check("forest calls require at least one perch; dogs remain independent",
		int(no_perch_counts.get("bird", 0)) == 0 and int(no_perch_counts.get("crow", 0)) == 0
		and int(no_perch_counts.get("owl", 0)) == 0 and int(no_perch_counts.get("dog", 0)) > 0,
		str(no_perch_counts))
	_check("same seed reproduces the complete event sequence", day_events == day_b["events"],
		"events=%d" % day_events.size())
	_check("different seed changes the event sequence", day_events != day_other_seed["events"],
		"same=%d different=%d" % [day_events.size(), (day_other_seed["events"] as Array).size()])
	_check("event mix never occupies more than two logical wildlife voices",
		int(day_a["max_active"]) <= 2 and int(night_run["max_active"]) <= 2,
		"day=%d night=%d" % [int(day_a["max_active"]), int(night_run["max_active"])])
	_check("day events have valid species, variant, slot, perch, pitch and serial fields",
		_events_well_formed(day_events, ["bird", "crow", "dog"], 5))
	_check("night events have valid species, variant, slot, perch, pitch and serial fields",
		_events_well_formed(night_events, ["owl", "dog"], 5))
	_check("day calls do not immediately repeat a species variant", _no_adjacent_variant_repeat(day_events))
	_check("night calls do not immediately repeat a species variant", _no_adjacent_variant_repeat(night_events))
	_check("no-perch run contains only well-formed independent dog calls",
		_events_well_formed(no_perch_events, ["dog"], 0))

	_test_pause_freezes_state(day)
	_test_voice_cap(day)
	_test_reply_moves_perch(day)
	_test_disturbance_quiet_period(day)
	_test_long_delta_does_not_burst(day)
	_test_reset_clears_pending_state()

	var observed_global: Array[int] = []
	for i: int in range(8):
		observed_global.append(randi())
	_check("wildlife variation leaves the global RNG untouched", observed_global == expected_global,
		"expected=%s observed=%s" % [expected_global, observed_global])

	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_activity_gates() -> void:
	var day: Dictionary = WildlifeScript.activity(_snapshot(45.0, 0.0, 16.0))
	var night: Dictionary = WildlifeScript.activity(_snapshot(-35.0, 0.0, 16.0))
	var cold_night: Dictionary = WildlifeScript.activity(_snapshot(-35.0, 0.0, 2.0))
	var windy_day: Dictionary = WildlifeScript.activity(_snapshot(45.0, 30.0, 16.0))
	_check("daylight enables birds and crows while suppressing owls and crickets",
		float(day.bird) > 0.9 and float(day.crow) > 0.9 and float(day.owl) == 0.0
		and float(day.cricket) == 0.0 and float(day.dog) > 0.0)
	_check("warm night enables owls, dogs and crickets, but not birds or crows",
		float(night.owl) > 0.9 and float(night.dog) > 0.0 and float(night.cricket) > 0.85
		and float(night.bird) == 0.0 and float(night.crow) == 0.0)
	_check("cold night temperature gates crickets off", float(cold_night.cricket) == 0.0
		and float(cold_night.owl) > 0.9)
	_check("strong wind suppresses wildlife activity", float(windy_day.bird) == 0.0
		and float(windy_day.crow) == 0.0 and float(windy_day.owl) == 0.0
		and float(windy_day.dog) == 0.0 and float(windy_day.cricket) == 0.0)


func _simulate(seed_value: int, snapshot: Dictionary, perch_count: int, steps: int = STEPS_20_MIN) -> Dictionary:
	var wildlife: Variant = WildlifeScript.new()
	wildlife.configure(CLIPS, seed_value)
	var events: Array[Dictionary] = []
	var max_active: int = 0
	for frame: int in range(steps):
		var event: Dictionary = wildlife.advance(snapshot, 0.1, perch_count)
		if not event.is_empty():
			events.append(event)
		var active: int = 0
		for voice_remaining: float in wildlife.remaining:
			if voice_remaining > 0.0:
				active += 1
		max_active = maxi(max_active, active)
	return {"events": events, "max_active": max_active}


func _events_well_formed(events: Array, allowed_species: Array[String], perch_count: int) -> bool:
	var expected_serial: int = 1
	for event: Dictionary in events:
		for field: String in ["species", "variant", "slot", "perch", "pitch", "answering", "serial"]:
			if not event.has(field):
				return false
		var species: String = str(event["species"])
		if not allowed_species.has(species) or not CLIPS.has(species):
			return false
		var variant_count: int = (CLIPS[species] as Array).size()
		var perch_limit: int = 2 if species == "dog" else perch_count
		if int(event["variant"]) < 0 or int(event["variant"]) >= variant_count:
			return false
		if int(event["slot"]) < 0 or int(event["slot"]) >= 3:
			return false
		if perch_limit <= 0 or int(event["perch"]) < 0 or int(event["perch"]) >= perch_limit:
			return false
		if float(event["pitch"]) < 0.94 or float(event["pitch"]) > 1.06:
			return false
		if typeof(event["answering"]) != TYPE_BOOL or int(event["serial"]) != expected_serial:
			return false
		expected_serial += 1
	return true


func _no_adjacent_variant_repeat(events: Array) -> bool:
	var previous: Dictionary = {}
	for event: Dictionary in events:
		var species: String = str(event["species"])
		var variant: int = int(event["variant"])
		if previous.has(species) and int(previous[species]) == variant:
			return false
		previous[species] = variant
	return true


func _counts(events: Array) -> Dictionary:
	var counts: Dictionary = {}
	for event: Dictionary in events:
		var species: String = str(event["species"])
		counts[species] = int(counts.get(species, 0)) + 1
	return counts


func _test_pause_freezes_state(day: Dictionary) -> void:
	var wildlife: Variant = WildlifeScript.new()
	wildlife.configure(CLIPS, 55991)
	for frame: int in range(500):
		wildlife.advance(day, 0.1, 5)
	wildlife.remaining[0] = 2.75
	wildlife.remaining[1] = 0.5
	wildlife.gap = 1.25
	wildlife.fright = 3.0
	wildlife.reply = {"species": "bird", "perch": 2, "wait": 4.5}
	var rng_before: int = wildlife.rng.state
	var timers_before: Dictionary = wildlife.timers.duplicate(true)
	var remaining_before: Array = wildlife.remaining.duplicate()
	var gap_before: float = float(wildlife.gap)
	var fright_before: float = float(wildlife.fright)
	var reply_before: Dictionary = wildlife.reply.duplicate(true)
	var serial_before: int = int(wildlife.serial)
	var last_event_before: Dictionary = wildlife.last_event.duplicate(true)
	var paused: Dictionary = day.duplicate()
	paused.paused = true
	var stayed_silent: bool = true
	for frame: int in range(10):
		stayed_silent = stayed_silent and wildlife.advance(paused, 30.0, 5, true).is_empty()
	_check("pause returns no wildlife events", stayed_silent)
	_check("pause freezes RNG, timers, voices, gap and pending reply",
		int(wildlife.rng.state) == rng_before and wildlife.timers == timers_before
		and wildlife.remaining == remaining_before and float(wildlife.gap) == gap_before
		and float(wildlife.fright) == fright_before and wildlife.reply == reply_before,
		"serial=%d" % int(wildlife.serial))
	_check("pause also preserves event serial and last event", int(wildlife.serial) == serial_before
		and wildlife.last_event == last_event_before)


func _test_reply_moves_perch(day: Dictionary) -> void:
	var wildlife: Variant = WildlifeScript.new()
	wildlife.configure(CLIPS, 7139)
	wildlife.remaining.fill(0.0)
	wildlife.gap = 0.0
	wildlife.reply = {"species": "bird", "perch": 2, "wait": 0.05}
	var answer: Dictionary = wildlife.advance(day, 0.1, 5)
	_check("answering call moves to a different perch", not answer.is_empty()
		and bool(answer.get("answering", false)) and int(answer.get("perch", 2)) != 2
		and int(answer.get("perch", -1)) >= 0 and int(answer.get("perch", 5)) < 5,
		str(answer))


func _test_voice_cap(day: Dictionary) -> void:
	var wildlife: Variant = WildlifeScript.new()
	wildlife.configure(CLIPS, 9117)
	wildlife.remaining[0] = 3.0
	wildlife.remaining[1] = 4.0
	wildlife.timers = {"bird": 0.0, "crow": 0.0, "owl": 100.0, "dog": 0.0}
	wildlife.gap = 0.0
	var event: Dictionary = wildlife.advance(day, 0.1, 5)
	var active: int = 0
	for voice_remaining: float in wildlife.remaining:
		if voice_remaining > 0.0:
			active += 1
	_check("two occupied slots block a third simultaneous wildlife call", event.is_empty()
		and active == 2 and int(wildlife.serial) == 0,
		"active=%d event=%s" % [active, event])


func _test_disturbance_quiet_period(day: Dictionary) -> void:
	var wildlife: Variant = WildlifeScript.new()
	wildlife.configure(CLIPS, 71531)
	wildlife.remaining.fill(0.0)
	wildlife.reply.clear()
	wildlife.gap = 0.0
	wildlife.fright = 0.0
	wildlife.timers = {"bird": 0.0, "crow": 100.0, "owl": 100.0, "dog": 100.0}
	var first: Dictionary = wildlife.advance(day, 0.1, 5, true)
	var quiet: bool = first.is_empty()
	for frame: int in range(59):
		var event: Dictionary = wildlife.advance(day, 0.1, 5)
		quiet = quiet and (event.is_empty() or str(event.get("species", "")) == "dog")
	var fright_before_release: float = float(wildlife.fright)
	var resumed: Dictionary = {}
	for frame: int in range(2):
		var event: Dictionary = wildlife.advance(day, 0.1, 5)
		if not event.is_empty():
			resumed = event
			break
	_check("disturbance keeps forest calls quiet through the six-second fright window",
		quiet and fright_before_release > 0.0 and fright_before_release <= 0.11,
		"fright=%.3f" % fright_before_release)
	_check("eligible bird calls resume after the quiet window expires",
		str(resumed.get("species", "")) == "bird" and float(wildlife.fright) == 0.0,
		"fright=%.6f event=%s" % [float(wildlife.fright), resumed])


func _test_long_delta_does_not_burst(day: Dictionary) -> void:
	var wildlife: Variant = WildlifeScript.new()
	wildlife.configure(CLIPS, 4242)
	wildlife.remaining.fill(0.0)
	wildlife.reply.clear()
	wildlife.gap = 0.0
	wildlife.fright = 0.0
	wildlife.timers = {"bird": 0.0, "crow": 0.0, "owl": 100.0, "dog": 0.0}
	var first: Dictionary = wildlife.advance(day, 3600.0, 5)
	var serial_after_first: int = int(wildlife.serial)
	var second: Dictionary = wildlife.advance(day, 3600.0, 5)
	_check("long delta schedules at most one call and does not catch up in a burst",
		not first.is_empty() and serial_after_first == 1 and second.is_empty()
		and int(wildlife.serial) == 1,
		"first=%s second=%s gap=%.2f" % [first.get("species", "none"), second, float(wildlife.gap)])


func _test_reset_clears_pending_state() -> void:
	var wildlife: Variant = WildlifeScript.new()
	wildlife.configure(CLIPS, 5199)
	wildlife.remaining[0] = 2.0
	wildlife.remaining[1] = 1.0
	wildlife.reply = {"species": "owl", "perch": 0, "wait": 2.5}
	wildlife.gap = 1.0
	wildlife.fright = 3.0
	wildlife.reset()
	var voices_clear: bool = true
	for voice_remaining: float in wildlife.remaining:
		voices_clear = voices_clear and voice_remaining == 0.0
	_check("reset clears all logical voice tails and pending reply", voices_clear and wildlife.reply.is_empty())
	_check("reset clears fright and restarts the inter-event gap", float(wildlife.fright) == 0.0
		and float(wildlife.gap) == 3.0)


func _snapshot(sun_elevation: float, wind_speed: float, temperature_c: float) -> Dictionary:
	return {"sun_elevation": sun_elevation, "wind_speed": wind_speed, "temperature_c": temperature_c, "paused": false}
