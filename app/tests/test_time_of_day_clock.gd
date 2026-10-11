## TOD-09a: independent civil-calendar oracles and tick-only solar clock invariants.
extends SceneTree

const Clock = preload("res://environment/solar_clock.gd")
const Config = preload("res://environment/time_of_day_config.gd")
const Solar = preload("res://environment/solar_position.gd")
const Lighting = preload("res://render/time_of_day_lighting.gd")
const Timeline = preload("res://environment/visual_timeline.gd")

var checks: int = 0
var failures: int = 0

func check(label: String, valid: bool) -> void:
	checks += 1
	if not valid:
		failures += 1
		printerr("FAIL " + label)

func _initialize() -> void:
	check("clock frequency matches production project", Clock.TICKS_PER_SECOND == int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second")))
	_oracles()
	_validation()
	_reanchoring()
	_sampling()
	print("TOD-09a solar clock: %d checks, %d failed" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _config(date: String = "2026-12-31", seconds: int = 86399) -> Dictionary:
	var config: Dictionary = Config.defaults()
	config.mode = "astronomical"
	config.date = date
	config.local_seconds = seconds
	return config

func _oracles() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/time_of_day_clock.json"))
	check("independent oracle schema", fixture.format == "openrc-solar-clock-oracles v1")
	for row: Dictionary in fixture.cases:
		check(row.id + " uses the declared clock frequency", int(row.ticks_per_second) == Clock.TICKS_PER_SECOND)
		var config: Dictionary = _config(row.date, int(row.local_seconds))
		config.utc_offset_minutes = int(row.utc_offset_minutes)
		var built: Dictionary = Clock.create(config, row.anchor_tick, row.rate)
		check(row.id + " creates", built.ok)
		if not built.ok:
			continue
		var before: PackedByteArray = var_to_bytes(built.clock)
		var sample: Dictionary = Clock.evaluate(built.clock, row.tick)
		check(row.id + " evaluates", sample.ok)
		if not sample.ok:
			continue
		check(row.id + " matches Python calendar", sample.config.date == row.expected_date
			and sample.config.local_seconds == int(row.expected_local_seconds)
			and sample.subsecond_ticks == int(row.expected_subsecond_ticks))
		check(row.id + " preserves fixed location and offset", sample.config.utc_offset_minutes == config.utc_offset_minutes
			and sample.config.latitude_deg == config.latitude_deg and sample.config.longitude_deg == config.longitude_deg)
		var solar: Dictionary = Solar.evaluate(sample.config)
		var expected_jd: float = 2440587.5 + float(row.expected_utc_unix_seconds) / 86400.0
		check(row.id + " solar UTC instant", solar.ok and absf(solar.julian_date - expected_jd) < 1e-9)
		check(row.id + " does not mutate anchor", var_to_bytes(built.clock) == before)
		var restored: Dictionary = Clock.validate(JSON.parse_string(JSON.stringify(built.clock, "", true, true)))
		check(row.id + " JSON restores identical sample", restored.ok and Clock.evaluate(restored.clock, row.tick) == sample)

func _validation() -> void:
	var clock: Dictionary = Clock.create(_config(), 120, 1).clock
	var unchanged: PackedByteArray = var_to_bytes(clock)
	for tick: Variant in [-1, 119, 120.5, true, "120", INF, NAN, 9007199254740992]:
		check("invalid evaluation tick " + str(tick), not Clock.evaluate(clock, tick).ok)
	for rate: Variant in [-1, 0.5, 2, 30, true, "1", INF, NAN]:
		check("unsupported create rate " + str(rate), not Clock.create(_config(), 0, rate).ok)
		check("unsupported reanchor rate " + str(rate), not Clock.reanchor(clock, 240, rate).ok)
	for tick: Variant in [-1, 0.5, false, "0", INF, NAN, 9007199254740992]:
		check("invalid anchor tick " + str(tick), not Clock.create(_config(), tick, 1).ok)
	for field: String in clock.keys():
		var incomplete: Dictionary = clock.duplicate(true)
		incomplete.erase(field)
		check("missing serialized field " + field, not Clock.validate(incomplete).ok)
	for mutation: Dictionary in [
		{format = "openrc-solar-clock v99"}, {ticks_per_second = 480}, {ticks_per_second = 0},
		{ticks_per_second = true}, {subsecond_ticks = -1}, {subsecond_ticks = 240},
		{subsecond_ticks = 0.5}, {subsecond_ticks = false}, {rate = 30}, {extra = 1},
		{anchor_tick = -1}, {config = {}},
	]:
		var bad: Dictionary = clock.duplicate(true)
		bad.merge(mutation, true)
		check("invalid serialized mutation " + str(mutation), not Clock.validate(bad).ok)
	for raw: Variant in [null, [], "clock", 0]:
		check("invalid record type " + str(raw), not Clock.validate(raw).ok and not Clock.evaluate(raw, 120).ok)
	check("legacy supports fixed clock", Clock.create(Config.defaults(), 0, 0).ok)
	check("legacy refuses moving Sun", not Clock.create(Config.defaults(), 0, 1).ok)
	check("legacy explicit edit requires stopping first", not Clock.reanchor(clock, 240, 1, Config.defaults()).ok)
	check("rejected operations preserve original", var_to_bytes(clock) == unchanged)
	var end: Dictionary = Clock.create(_config("2100-12-31", 86399), 0, 1).clock
	check("last supported fraction is valid", Clock.evaluate(end, 239).ok)
	check("calendar overflow fails closed", not Clock.evaluate(end, 240).ok)
	check("overflowing reanchor fails closed", not Clock.reanchor(end, 240, 0).ok)
	check("expired clock cannot be reanchored by replacing its config", not Clock.reanchor(end, 240, 1, _config()).ok)
	check("explicit recovery creates a fresh valid anchor", Clock.create(_config(), 240, 1).ok)
	check("huge delta fails without overflow", not Clock.evaluate(end, Clock.MAX_SAFE_TICK).ok)
	var high: Dictionary = Clock.create(_config(), Clock.MAX_SAFE_TICK - 240, 1).clock
	check("safe maximum tick remains exact", Clock.evaluate(high, Clock.MAX_SAFE_TICK).config.date == "2027-01-01")
	var config: Dictionary = _config()
	var detached: Dictionary = Clock.create(config, 0, 1).clock
	config.local_seconds = 0
	check("create owns detached config", detached.config.local_seconds == 86399)
	var sample: Dictionary = Clock.evaluate(detached, 1)
	sample.config.local_seconds = 5
	check("sample does not alias clock", detached.config.local_seconds == 86399)
	var fixed_history: Dictionary = Timeline.create(_config()).timeline
	fixed_history.rate = 1.0
	check("existing timeline v1 still rejects progression", not Timeline.validate(fixed_history).ok)

func _reanchoring() -> void:
	var original: Dictionary = Clock.create(_config(), 0, 1).clock
	var stopped: Dictionary = Clock.reanchor(original, 119, 0).clock
	check("rate-only stop retains fractional tick", stopped.subsecond_ticks == 119)
	var frozen: Dictionary = Clock.evaluate(stopped, 9999)
	check("zero rate freezes whole and fractional time", frozen.config == original.config and frozen.subsecond_ticks == 119)
	var resumed: Dictionary = Clock.reanchor(stopped, 9999, 1).clock
	check("resume retains fractional remainder", Clock.evaluate(resumed, 10120).config.date == "2027-01-01"
		and Clock.evaluate(resumed, 10120).subsecond_ticks == 0)
	var edited: Dictionary = Clock.reanchor(resumed, 10000, 1, _config("2024-02-28", 86399)).clock
	check("explicit civil edit clears old fraction", edited.subsecond_ticks == 0 and edited.anchor_tick == 10000)
	check("edited anchor rolls into leap day", Clock.evaluate(edited, 10240).config.date == "2024-02-29")
	var clock: Dictionary = original.duplicate(true)
	var tick: int = 0
	for _index: int in 100:
		tick += 123
		clock = Clock.reanchor(clock, tick, 0).clock
		tick += 17
		clock = Clock.reanchor(clock, tick, 1).clock
	var repeated: Dictionary = Clock.evaluate(clock, tick)
	var direct: Dictionary = Clock.evaluate(original, 12300)
	check("100 stop/resume cycles accumulate no rounding loss", repeated.config == direct.config
		and repeated.subsecond_ticks == direct.subsecond_ticks)
	var same_tick: Dictionary = Clock.reanchor(original, 119, 0).clock
	same_tick = Clock.reanchor(same_tick, 119, 1).clock
	check("same-tick rate changes are continuous", Clock.evaluate(same_tick, 240).config == Clock.evaluate(original, 240).config)
	var reset: Dictionary = Clock.create(original.config, 0, 1).clock
	check("explicit restart recipe returns configured start", Clock.evaluate(reset, 0).config == original.config
		and Clock.evaluate(reset, 0).subsecond_ticks == 0)

func _sampling() -> void:
	var clock: Dictionary = Clock.create(_config("2026-03-20", 21599), 0, 1).clock
	var reference: Dictionary = Clock.evaluate(clock, 480)
	for fps: int in [30, 60, 144]:
		for frame: int in fps * 2 + 1:
			var tick: int = floori(float(frame) * 240.0 / float(fps))
			Clock.evaluate(clock, tick)
		check("equal-tick clock parity at %d fps" % fps, Clock.evaluate(clock, 480) == reference)
		check("equal-tick lighting parity at %d fps" % fps,
			Lighting.snapshot(Clock.evaluate(clock, 480).config) == Lighting.snapshot(reference.config))
	var held: Dictionary = Clock.evaluate(clock, 119)
	for _frame: int in 100:
		check("unchanged simulation tick freezes time", Clock.evaluate(clock, 119) == held)
	var rewind: Dictionary = Clock.evaluate(clock, 0)
	check("out-of-order pure samples have no accumulated state", rewind.config == clock.config and rewind.subsecond_ticks == 0)
