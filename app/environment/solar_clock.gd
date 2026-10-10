# TOD-09a: deterministic civil solar clock driven only by fixed simulation ticks.
extends RefCounted

const TimeOfDayConfig: Script = preload("res://environment/time_of_day_config.gd")

const FORMAT: String = "openrc-solar-clock v1"
const TICKS_PER_SECOND: int = 240
const MAX_SAFE_TICK: int = 9007199254740991
const MIN_YEAR: int = 2000
const MAX_YEAR: int = 2100
const SECONDS_PER_DAY: int = 86400
const TICKS_PER_DAY: int = SECONDS_PER_DAY * TICKS_PER_SECOND
const MIN_DAY_INDEX: int = 0
const MAX_DAY_INDEX: int = 36889 # 2100-12-31 relative to 2000-01-01, Gregorian calendar.

const CLOCK_FIELDS: Array[String] = [
	"format", "anchor_tick", "ticks_per_second", "rate", "config", "subsecond_ticks",
]


## Create an exact-time anchor. Rate is either 0 or 1; a selected civil second starts at fraction zero.
static func create(config: Variant, anchor_tick: Variant = 0, rate: Variant = 0) -> Dictionary:
	var errors: Array[String] = []
	var parsed_tick: Dictionary = _parse_tick(anchor_tick, "anchor_tick")
	if not bool(parsed_tick.get("ok", false)):
		errors.append(str(parsed_tick.error))
	var checked_rate: Dictionary = _parse_rate(rate)
	if not bool(checked_rate.get("ok", false)):
		errors.append(str(checked_rate.error))
	var checked_config: Dictionary = TimeOfDayConfig.validate(config)
	if not bool(checked_config.get("ok", false)):
		_append_errors(errors, "config", checked_config.get("errors", []))
	elif (int(checked_rate.get("value", 0)) == 1
			and str(checked_config.config.get("mode", "")) != "astronomical"):
		errors.append("rate 1 requires an astronomical lighting config")
	if not errors.is_empty():
		return _clock_failure(errors)

	return validate({
		"format": FORMAT,
		"anchor_tick": int(parsed_tick.value),
		"ticks_per_second": TICKS_PER_SECOND,
		"rate": int(checked_rate.value),
		"config": (checked_config.config as Dictionary).duplicate(true),
		"subsecond_ticks": 0,
	})


## Validate the exact serialized v1 record and return a detached normalized copy.
static func validate(raw: Variant) -> Dictionary:
	var errors: Array[String] = []
	if typeof(raw) != TYPE_DICTIONARY:
		return _clock_failure(["clock must be an object"])
	var source: Dictionary = raw
	_check_keys(source, CLOCK_FIELDS, "clock", errors)

	var format_value: Variant = source.get("format", null)
	if typeof(format_value) != TYPE_STRING or str(format_value) != FORMAT:
		errors.append("clock.format must be '%s'" % FORMAT)

	var parsed_tick: Dictionary = _parse_tick(source.get("anchor_tick", null), "clock.anchor_tick")
	if not bool(parsed_tick.get("ok", false)):
		errors.append(str(parsed_tick.error))

	var ticks_value: Variant = source.get("ticks_per_second", null)
	if not _is_finite_number(ticks_value) or float(ticks_value) != float(TICKS_PER_SECOND):
		errors.append("clock.ticks_per_second must be exactly %d" % TICKS_PER_SECOND)

	var checked_rate: Dictionary = _parse_rate(source.get("rate", null))
	if not bool(checked_rate.get("ok", false)):
		errors.append("clock.%s" % str(checked_rate.error))

	var checked_config: Dictionary = TimeOfDayConfig.validate(source.get("config", null))
	if not bool(checked_config.get("ok", false)):
		_append_errors(errors, "clock.config", checked_config.get("errors", []))
	elif (int(checked_rate.get("value", 0)) == 1
			and str(checked_config.config.get("mode", "")) != "astronomical"):
		errors.append("clock.rate 1 requires an astronomical lighting config")

	var subticks_value: Variant = source.get("subsecond_ticks", null)
	if not _is_integer_in_range(subticks_value, 0, TICKS_PER_SECOND - 1):
		errors.append("clock.subsecond_ticks must be an integer from 0 through %d" % [TICKS_PER_SECOND - 1])

	if not errors.is_empty():
		return _clock_failure(errors)

	var normalized_clock: Dictionary = {
		"format": FORMAT,
		"anchor_tick": int(parsed_tick.value),
		"ticks_per_second": TICKS_PER_SECOND,
		"rate": int(checked_rate.value),
		"config": (checked_config.config as Dictionary).duplicate(true),
		"subsecond_ticks": int(subticks_value),
	}
	return _clock_success(normalized_clock)


## Resolve a clock at an authoritative simulation tick. No wall clock, rendering state, or float time is read.
static func evaluate(raw: Variant, tick: Variant) -> Dictionary:
	var errors: Array[String] = []
	var checked_clock: Dictionary = validate(raw)
	if not bool(checked_clock.get("ok", false)):
		_append_errors(errors, "clock", checked_clock.get("errors", []))
	var parsed_tick: Dictionary = _parse_tick(tick, "evaluation tick")
	if not bool(parsed_tick.get("ok", false)):
		errors.append(str(parsed_tick.error))
	if not errors.is_empty():
		return _evaluation_failure(errors)

	var clock: Dictionary = checked_clock.clock
	var current_tick: int = int(parsed_tick.value)
	var anchor_tick: int = int(clock.anchor_tick)
	if current_tick < anchor_tick:
		return _evaluation_failure(
			["evaluation tick precedes clock.anchor_tick"],
			anchor_tick,
			current_tick
		)

	var resolved_config: Dictionary = (clock.config as Dictionary).duplicate(true)
	var resolved_subticks: int = int(clock.subsecond_ticks)
	var elapsed_ticks: int = current_tick - anchor_tick
	if int(clock.rate) == 1 and elapsed_ticks > 0:
		var initial_day: int = _day_index(str(resolved_config.date))
		if initial_day < MIN_DAY_INDEX:
			return _evaluation_failure(["clock.config.date is outside the supported calendar"], anchor_tick, current_tick)

		# Split the potentially large delta before adding the small within-day phase.
		# The quotient helper is integer-only, including for the safe-JSON tick limit.
		var elapsed_days: int = _integer_quotient(elapsed_ticks, TICKS_PER_DAY)
		var remaining_ticks: int = elapsed_ticks - elapsed_days * TICKS_PER_DAY
		var within_day_ticks: int = int(resolved_config.local_seconds) * TICKS_PER_SECOND
		within_day_ticks += resolved_subticks + remaining_ticks
		var carried_days: int = _integer_quotient(within_day_ticks, TICKS_PER_DAY)
		var clock_ticks_in_day: int = within_day_ticks - carried_days * TICKS_PER_DAY
		var resolved_day: int = initial_day + elapsed_days + carried_days
		if resolved_day > MAX_DAY_INDEX:
			return _evaluation_failure(
				["solar clock exceeded the supported calendar ending 2100-12-31"],
				anchor_tick,
				current_tick
			)
		var date_parts: Dictionary = _date_from_day_index(resolved_day)
		if date_parts.is_empty():
			return _evaluation_failure(
				["solar clock could not resolve its Gregorian calendar day"],
				anchor_tick,
				current_tick
			)
		resolved_config.date = "%04d-%02d-%02d" % [date_parts.year, date_parts.month, date_parts.day]
		resolved_config.local_seconds = _integer_quotient(clock_ticks_in_day, TICKS_PER_SECOND)
		resolved_subticks = clock_ticks_in_day % TICKS_PER_SECOND

	return {
		"ok": true,
		"config": resolved_config,
		"subsecond_ticks": resolved_subticks,
		"rate": int(clock.rate),
		"tick": current_tick,
		"anchor_tick": anchor_tick,
		"ticks_per_second": TICKS_PER_SECOND,
		"errors": [] as Array[String],
	}


## Reanchor at a known tick. Omitting config preserves the exact fractional phase; an explicit selection starts at .000 s.
static func reanchor(raw: Variant, tick: Variant, rate: Variant, config: Variant = null) -> Dictionary:
	var errors: Array[String] = []
	var current: Dictionary = evaluate(raw, tick)
	if not bool(current.get("ok", false)):
		_append_errors(errors, "clock evaluation", current.get("errors", []))
	var checked_rate: Dictionary = _parse_rate(rate)
	if not bool(checked_rate.get("ok", false)):
		errors.append(str(checked_rate.error))

	var next_config: Dictionary = {}
	var next_subticks: int = 0
	if config == null:
		if current.get("ok", false):
			next_config = (current.config as Dictionary).duplicate(true)
			next_subticks = int(current.subsecond_ticks)
	else:
		var checked_config: Dictionary = TimeOfDayConfig.validate(config)
		if not bool(checked_config.get("ok", false)):
			_append_errors(errors, "config", checked_config.get("errors", []))
		else:
			next_config = (checked_config.config as Dictionary).duplicate(true)

	if (not next_config.is_empty() and int(checked_rate.get("value", 0)) == 1
			and str(next_config.get("mode", "")) != "astronomical"):
		errors.append("rate 1 requires an astronomical lighting config")
	if not errors.is_empty():
		return _clock_failure(errors)

	var parsed_tick: Dictionary = _parse_tick(tick, "anchor_tick")
	if not bool(parsed_tick.get("ok", false)):
		return _clock_failure([str(parsed_tick.error)])
	return validate({
		"format": FORMAT,
		"anchor_tick": int(parsed_tick.value),
		"ticks_per_second": TICKS_PER_SECOND,
		"rate": int(checked_rate.value),
		"config": next_config,
		"subsecond_ticks": next_subticks,
	})


static func _parse_rate(value: Variant) -> Dictionary:
	if not _is_finite_number(value):
		return {"ok": false, "error": "rate must be exactly 0 or 1"}
	var numeric_rate: float = float(value)
	if numeric_rate != 0.0 and numeric_rate != 1.0:
		return {"ok": false, "error": "rate must be exactly 0 or 1"}
	return {"ok": true, "value": int(numeric_rate)}


static func _parse_tick(value: Variant, label: String) -> Dictionary:
	if not _is_finite_number(value):
		return {"ok": false, "error": "%s must be an integer from 0 through %d" % [label, MAX_SAFE_TICK]}
	var numeric_tick: float = float(value)
	if numeric_tick < 0.0 or numeric_tick > float(MAX_SAFE_TICK):
		return {"ok": false, "error": "%s must be from 0 through %d" % [label, MAX_SAFE_TICK]}
	if floor(numeric_tick) != numeric_tick:
		return {"ok": false, "error": "%s must be an integer" % label}
	return {"ok": true, "value": int(numeric_tick)}


static func _date_from_day_index(day_index: int) -> Dictionary:
	if day_index < MIN_DAY_INDEX or day_index > MAX_DAY_INDEX:
		return {}
	var low_year: int = MIN_YEAR
	var high_year: int = MAX_YEAR + 1
	while low_year + 1 < high_year:
		var middle_year: int = _integer_quotient(low_year + high_year, 2)
		if _days_before_year(middle_year) <= day_index:
			low_year = middle_year
		else:
			high_year = middle_year
	var year: int = low_year
	var day_of_year: int = day_index - _days_before_year(year)
	var month: int = 1
	while month <= 12:
		var month_days: int = _days_in_month(year, month)
		if day_of_year < month_days:
			return {"year": year, "month": month, "day": day_of_year + 1}
		day_of_year -= month_days
		month += 1
	return {}


static func _day_index(date: String) -> int:
	if date.length() != 10:
		return -1
	var year: int = int(date.substr(0, 4))
	var month: int = int(date.substr(5, 2))
	var day: int = int(date.substr(8, 2))
	if year < MIN_YEAR or year > MAX_YEAR or month < 1 or month > 12:
		return -1
	var month_days: int = _days_in_month(year, month)
	if day < 1 or day > month_days:
		return -1
	var day_index: int = _days_before_year(year)
	for month_index: int in range(1, month):
		day_index += _days_in_month(year, month_index)
	return day_index + day - 1


static func _days_before_year(year: int) -> int:
	var prior: int = year - 1
	var base: int = MIN_YEAR - 1
	var leaps: int = _integer_quotient(prior, 4) - _integer_quotient(base, 4)
	leaps -= _integer_quotient(prior, 100) - _integer_quotient(base, 100)
	leaps += _integer_quotient(prior, 400) - _integer_quotient(base, 400)
	return (year - MIN_YEAR) * 365 + leaps


static func _integer_quotient(numerator: int, denominator: int) -> int:
	@warning_ignore("integer_division")
	return numerator / denominator


static func _days_in_month(year: int, month: int) -> int:
	match month:
		1, 3, 5, 7, 8, 10, 12:
			return 31
		4, 6, 9, 11:
			return 30
		2:
			return 29 if _is_leap_year(year) else 28
	return 0


static func _is_leap_year(year: int) -> bool:
	return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)


static func _is_integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	if not _is_finite_number(value):
		return false
	var numeric_value: float = float(value)
	return (numeric_value >= float(minimum) and numeric_value <= float(maximum)
		and floor(numeric_value) == numeric_value)


static func _is_finite_number(value: Variant) -> bool:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return false
	return is_finite(float(value))


static func _check_keys(source: Dictionary, fields: Array[String], context: String, errors: Array[String]) -> void:
	for field: String in fields:
		if not source.has(field):
			errors.append("%s is missing required field '%s'" % [context, field])
	for key: Variant in source.keys():
		if typeof(key) != TYPE_STRING or not fields.has(str(key)):
			errors.append("%s has unknown field '%s'" % [context, str(key)])


static func _append_errors(target: Array[String], context: String, source: Variant) -> void:
	if typeof(source) != TYPE_ARRAY:
		target.append("%s validation failed" % context)
		return
	for error_value: Variant in source:
		target.append("%s: %s" % [context, str(error_value)])


static func _clock_success(clock: Dictionary) -> Dictionary:
	return {"ok": true, "clock": clock.duplicate(true), "errors": [] as Array[String]}


static func _clock_failure(errors: Array[String]) -> Dictionary:
	return {"ok": false, "clock": {}, "errors": errors.duplicate()}


static func _evaluation_failure(errors: Array[String], anchor_tick: int = -1, tick: int = -1) -> Dictionary:
	return {
		"ok": false,
		"config": {},
		"subsecond_ticks": -1,
		"rate": -1,
		"tick": tick,
		"anchor_tick": anchor_tick,
		"ticks_per_second": TICKS_PER_SECOND,
		"errors": errors.duplicate(),
	}
