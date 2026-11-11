# DR-08 / DR-15: versioned stick-to-rate-setpoint mapping and a bounded Betaflight CLI rate-profile importer.
# Law source pin: Betaflight 4.5.2, commit 024f8e13d4e642eb6a380308685b9ea3aa3ef1a2, src/main/fc/rc.c, as restated
# mathematically in FPV/03_FLIGHT_DYNAMICS_AND_RESEARCH.md §1 (an independent implementation of that specification,
# not a source port). Two families: ACTUAL and BETAFLIGHT. Curve math only: receiver processing, deadband,
# smoothing, feedforward, PID and motor behaviour are outside this file, and curve agreement is not firmware
# flight-feel equivalence. Pure static functions, 64-bit floats, no file I/O, no mutable state.
extends RefCounted

const FORMAT := "openrc-rates v1"
const FAMILY_ACTUAL := "ACTUAL"
const FAMILY_BETAFLIGHT := "BETAFLIGHT"
const SOURCE_FIRMWARE := "betaflight"
const SOURCE_VERSION := "4.5.2"
const SOURCE_COMMIT := "024f8e13d4e642eb6a380308685b9ea3aa3ef1a2"

## Rate families Betaflight's `rates_type` can name that this file does not implement (FPV/07 SET-01 evidence).
const UNSUPPORTED_FAMILIES := ["RACEFLIGHT", "KISS", "QUICK"]
const AXIS_NAMES := ["roll", "pitch", "yaw"]
const FIELD_NAMES := ["rc_rate", "srate", "expo", "rate_limit"]
const DEG_TO_RAD := PI / 180.0

## Import bounds. 256 KiB and 20 000 lines are this slice's product limits; 4096 bytes per line is the starting
## per-line limit proposed in FPV/08 §5 step 1. Reviewable limits, not firmware properties.
const IMPORT_MAX_BYTES := 262144
const IMPORT_MAX_LINES := 20000
const IMPORT_MAX_LINE_BYTES := 4096
const INT_MAX_DIGITS := 9
## OpenRC parser bound for a `rateprofile N` index. The FPV documents state the profile count only for the current
## (2026.6.2) source, not for the 4.5.2 pin, so this is a sanity bound, not a firmware claim.
const PROFILE_INDEX_MAX := 255
## `source.profile_index` value marking a profile that did not come from a firmware rate profile.
const PROFILE_INDEX_NONE := -1

## Betaflight 4.5.2 reset values usable to complete a `diff`. Empty on purpose: the FPV documents pin rate defaults
## only for BF 2026.6.2 (FPV/07 SET-01, "Reset Actual values are 7, 0, 67 and 1998"), never for 4.5.2, and FPV/08
## §5 step 7 allows reconstruction only from an exact default manifest. A diff that omits a field is refused.
const PINNED_DEFAULTS := {}

## Raw-field domains per family: [min, max]; max -1 means no stated upper bound.
## ACTUAL: rc_rate and srate up to 200, expo up to 100 (FPV/03 §1). The lower bound 0 is an OpenRC domain (a
## negative raw rate has no meaning in the curve). rate_limit: the FPV documents give 200..1998 only for BF 2026.6.2
## (FPV/07 SET-01), not for the 4.5.2 pin, so only rate_limit >= 1 is enforced (a zero cap would null the axis).
## BETAFLIGHT: the FPV documents state no 4.5.2 field constraints for this family, so only the same OpenRC
## non-negative domain and rate_limit >= 1 are enforced; rc_rate above 200 (r > 2) is legal input to the law.
const FIELD_DOMAINS := {
	"ACTUAL": {rc_rate = [0, 200], srate = [0, 200], expo = [0, 100], rate_limit = [1, -1]},
	"BETAFLIGHT": {rc_rate = [0, -1], srate = [0, -1], expo = [0, -1], rate_limit = [1, -1]},
}

## Betaflight family constants (FPV/03 §1): r_eff = r + 14.54*(r - 2) above r = 2; denominator clamped to [0.01, 1].
const BF_RATE_INCREMENT := 14.54
const BF_DENOMINATOR_MIN := 0.01


## The simulator's own shipped starting profile: ACTUAL 20/67/58/1998 on every axis (200 deg/s centre, 670 deg/s
## full stick). An OpenRC product starting point, not a Betaflight default: `source` names the pinned curve law and
## profile_index = PROFILE_INDEX_NONE says it was not read from a firmware rate profile.
static func default_profile() -> Dictionary:
	var axes := {}
	for axis_name in AXIS_NAMES:
		axes[axis_name] = {rc_rate = 20, srate = 67, expo = 58, rate_limit = 1998}
	return {
		format = FORMAT,
		family = FAMILY_ACTUAL,
		source = {firmware = SOURCE_FIRMWARE, version = SOURCE_VERSION, commit = SOURCE_COMMIT,
			profile_index = PROFILE_INDEX_NONE},
		axes = axes,
	}


## Strict validation: {ok, errors}. Unknown or missing keys, wrong types (a float where an int is required, even an
## integral one), out-of-domain values, unknown family, format, firmware, version or commit all refuse. Never clamps.
static func validate(profile: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(profile) != TYPE_DICTIONARY:
		errors.append("profile: expected a Dictionary, got %s" % type_string(typeof(profile)))
		return {ok = false, errors = errors}
	var top: Dictionary = _view(profile, "profile", ["format", "family", "source", "axes"], errors)
	if top.has("format") and not _is_text(top.format, FORMAT):
		errors.append("format: expected '%s'" % FORMAT)
	var family := ""
	if top.has("family"):
		if typeof(top.family) == TYPE_STRING and FIELD_DOMAINS.has(top.family):
			family = top.family
		else:
			errors.append("family: unknown rate family %s (supported: ACTUAL, BETAFLIGHT)" % _show(top.family))
	if top.has("source"):
		_validate_source(top.source, errors)
	if top.has("axes"):
		if typeof(top.axes) != TYPE_DICTIONARY:
			errors.append("axes: expected a Dictionary")
		else:
			var axes: Dictionary = _view(top.axes, "axes", AXIS_NAMES, errors)
			for axis_name in AXIS_NAMES:
				if axes.has(axis_name):
					_validate_axis(axes[axis_name], "axes.%s" % axis_name, family, errors)
	return {ok = errors.is_empty(), errors = errors}


## {ok, errors, prepared}. `prepared` is a read-only flat dictionary with per-axis constants precomputed in deg/s and
## `identity`, the SHA-256 hex of the canonical serialization of the profile. On failure `prepared` is {}.
static func prepare(profile: Dictionary) -> Dictionary:
	var check: Dictionary = validate(profile)
	if not check.ok:
		return {ok = false, errors = check.errors, prepared = {}}
	var top: Dictionary = _view(profile, "", [], PackedStringArray())
	var family: String = top.family
	var source: Dictionary = _view(top.source, "", [], PackedStringArray())
	var axes: Dictionary = _view(top.axes, "", [], PackedStringArray())
	var center := PackedFloat64Array([0.0, 0.0, 0.0])
	var extra := PackedFloat64Array([0.0, 0.0, 0.0])
	var rate_eff := PackedFloat64Array([0.0, 0.0, 0.0])
	var super_rate := PackedFloat64Array([0.0, 0.0, 0.0])
	var expo := PackedFloat64Array([0.0, 0.0, 0.0])
	var limit := PackedFloat64Array([0.0, 0.0, 0.0])
	for i in 3:
		var fields: Dictionary = _view(axes[AXIS_NAMES[i]], "", [], PackedStringArray())
		var rc_rate: float = float(fields.rc_rate)
		var srate: float = float(fields.srate)
		expo[i] = float(fields.expo) / 100.0
		limit[i] = float(fields.rate_limit)
		if family == FAMILY_ACTUAL:
			# C = 10*rc_rate deg/s centre slope; a = max(0, M - C) with M = 10*srate.
			center[i] = 10.0 * rc_rate
			extra[i] = maxf(0.0, 10.0 * srate - center[i])
		else:
			var r: float = rc_rate / 100.0
			rate_eff[i] = r + BF_RATE_INCREMENT * (r - 2.0) if r > 2.0 else r
			super_rate[i] = srate / 100.0
	var profile_index: int = int(source.profile_index)
	var prepared := {
		format = FORMAT,
		family = family,
		family_code = 0 if family == FAMILY_ACTUAL else 1,
		origin = "openrc_product_default" if profile_index == PROFILE_INDEX_NONE else "betaflight_cli_rateprofile",
		profile_index = profile_index,
		identity = canonical_text(profile).sha256_text(),
		center_dps = center,
		extra_dps = extra,
		rate_eff = rate_eff,
		super_rate = super_rate,
		expo = expo,
		limit_dps = limit,
	}
	prepared.make_read_only()
	return {ok = true, errors = PackedStringArray(), prepared = prepared}


## Canonical serialization of a valid profile: fixed key order, raw integers, LF line ends. Hashed into `identity`.
static func canonical_text(profile: Dictionary) -> String:
	var top: Dictionary = _view(profile, "", [], PackedStringArray())
	var source: Dictionary = _view(top.source, "", [], PackedStringArray())
	var axes: Dictionary = _view(top.axes, "", [], PackedStringArray())
	var lines := PackedStringArray([
		"format=%s" % top.format,
		"family=%s" % top.family,
		"source.firmware=%s" % source.firmware,
		"source.version=%s" % source.version,
		"source.commit=%s" % source.commit,
		"source.profile_index=%d" % int(source.profile_index),
	])
	for axis_name in AXIS_NAMES:
		var fields: Dictionary = _view(axes[axis_name], "", [], PackedStringArray())
		for field in FIELD_NAMES:
			lines.append("axes.%s.%s=%d" % [axis_name, field, int(fields[field])])
	return "\n".join(lines) + "\n"


## Rate setpoint in deg/s for one axis (0 roll, 1 pitch, 2 yaw) at calibrated, deadbanded stick x in [-1, 1].
## Returns NAN for x outside [-1, 1], non-finite x, an unknown axis or an unprepared dictionary; x is never clamped.
## The per-axis rate_limit cap is part of the law and clamps the curve output.
static func setpoint_dps(prepared: Dictionary, axis: int, x: float) -> float:
	if axis < 0 or axis > 2 or not is_finite(x) or x < -1.0 or x > 1.0:
		return NAN
	var code: int = int(prepared.get("family_code", -1))
	var curve: float
	if code == 0:
		# ACTUAL: C*x + a*|x|*(e*x^5 + (1 - e)*x).
		var e: float = prepared.expo[axis]
		var x2: float = x * x
		curve = prepared.center_dps[axis] * x + prepared.extra_dps[axis] * absf(x) * (e * x2 * x2 * x + (1.0 - e) * x)
	elif code == 1:
		# BETAFLIGHT: 200*r_eff*x_expo / clamp(1 - |x|*s, 0.01, 1), with the denominator on the unshaped |x|.
		var e: float = prepared.expo[axis]
		var b: float = absf(x)
		var x_expo: float = x * b * b * b * e + x * (1.0 - e)
		var denominator: float = clampf(1.0 - b * float(prepared.super_rate[axis]), BF_DENOMINATOR_MIN, 1.0)
		curve = 200.0 * float(prepared.rate_eff[axis]) * x_expo / denominator
	else:
		return NAN
	var cap: float = prepared.limit_dps[axis]
	return clampf(curve, -cap, cap)


## Roll, pitch, yaw setpoints in rad/s for three sticks; NAN entries where a stick is invalid. A stick array that
## is not exactly three long yields three NANs.
static func setpoints_rad_s(prepared: Dictionary, sticks: PackedFloat64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array([NAN, NAN, NAN])
	if sticks.size() != 3:
		return out
	for i in 3:
		out[i] = setpoint_dps(prepared, i, sticks[i]) * DEG_TO_RAD
	return out


## Parse Betaflight CLI `dump`/`diff` text as inert data (nothing is executed) into a complete validated profile.
## Returns {ok, profile, report, errors}; report = {firmware_version, selected_profile, accepted, ignored, refused,
## defaults_used}. Only firmware 4.5.2 is supported. `requested_profile` >= 0 selects a `rateprofile` block; -1
## uses the trailing restoration selector of a `diff all`, else the single block present, else fails as unresolved.
## Fields inside other blocks never apply. Non-rate `set` lines and other commands are listed as ignored. A malformed
## or out-of-scope value for a supported field is refused and fails the whole import.
static func import_cli(text: String, requested_profile := -1) -> Dictionary:
	var accepted := PackedStringArray()
	var ignored := PackedStringArray()
	var refused := PackedStringArray()
	var defaults_used := PackedStringArray()
	var errors := PackedStringArray()
	var version := ""
	var selected := -1
	if requested_profile < -1 or requested_profile > PROFILE_INDEX_MAX:
		errors.append("requested_profile %d outside [-1, %d]" % [requested_profile, PROFILE_INDEX_MAX])
		return _import_result(null, version, selected, accepted, ignored, refused, defaults_used, errors)
	var byte_count: int = text.to_utf8_buffer().size()
	if byte_count > IMPORT_MAX_BYTES:
		errors.append("input is %d bytes; the limit is %d" % [byte_count, IMPORT_MAX_BYTES])
		return _import_result(null, version, selected, accepted, ignored, refused, defaults_used, errors)
	var lines: PackedStringArray = text.split("\n")
	var line_count: int = lines.size() - (1 if text.ends_with("\n") else 0)
	if line_count > IMPORT_MAX_LINES:
		errors.append("input has %d lines; the limit is %d" % [line_count, IMPORT_MAX_LINES])
		return _import_result(null, version, selected, accepted, ignored, refused, defaults_used, errors)

	var blocks := {}  # rateprofile index -> {cli key: [value, line]}
	var block_sets := {}  # rateprofile index -> number of `set` lines inside the block
	var current := -1
	var last_selector := -1
	var set_after_selector := false
	var revision := ""
	for i in lines.size():
		var number: int = i + 1
		var raw: String = lines[i]
		if raw.length() * 4 > IMPORT_MAX_LINE_BYTES and raw.to_utf8_buffer().size() > IMPORT_MAX_LINE_BYTES:
			errors.append("line %d is longer than %d bytes" % [number, IMPORT_MAX_LINE_BYTES])
			return _import_result(null, version, selected, accepted, ignored, refused, defaults_used, errors)
		var line: String = raw.strip_edges()
		if line.is_empty():
			continue
		if line.begins_with("#"):
			var header: PackedStringArray = _parse_header(line)
			if header.is_empty():
				continue
			if not version.is_empty() and header[0] != version:
				errors.append("line %d: conflicting firmware version headers (%s, then %s)" % [number, version, header[0]])
				return _import_result(null, version, selected, accepted, ignored, refused, defaults_used, errors)
			version = header[0]
			revision = header[1]
			continue
		var words: PackedStringArray = line.split(" ", false, 1)
		var command: String = words[0].to_lower()
		var rest: String = words[1].strip_edges() if words.size() > 1 else ""
		if command == "set":
			if last_selector >= 0:
				set_after_selector = true
			if current >= 0:
				block_sets[current] = int(block_sets.get(current, 0)) + 1
			var eq: int = rest.find("=")
			var key: String = (rest.substr(0, eq) if eq >= 0 else rest).strip_edges().to_lower()
			if not _is_rate_key(key):
				ignored.append("line %d: set %s (not a supported rate field; not applied)" % [number, _clip(key)])
				continue
			if eq < 0:
				refused.append("line %d: set %s has no value" % [number, key])
				continue
			if current < 0:
				refused.append("line %d: %s outside any rateprofile block; its profile scope is unknown" % [number, key])
				continue
			var value: Variant = _parse_value(key, rest.substr(eq + 1).strip_edges())
			if value == null:
				refused.append("line %d: rateprofile %d %s has malformed value '%s'" % [number, current,
					key, _clip(rest.substr(eq + 1).strip_edges())])
				continue
			var block: Dictionary = blocks.get(current, {})
			block[key] = [value, number]
			blocks[current] = block
		elif command == "rateprofile":
			if rest.is_empty():
				ignored.append("line %d: rateprofile (query; not executed)" % number)
				continue
			var index: Variant = _parse_cli_int(rest)
			if index == null or int(index) < 0 or int(index) > PROFILE_INDEX_MAX:
				refused.append("line %d: malformed rateprofile index '%s'" % [number, _clip(rest)])
				current = -1
				continue
			current = int(index)
			last_selector = current
			set_after_selector = false
		elif command == "defaults":
			# A reset marker with an unpinned 4.5.2 baseline: earlier staged rate data cannot survive it (FPV/08 §5.4).
			var note := "inert; not executed"
			if not blocks.is_empty() or last_selector >= 0:
				note = "inert; earlier rate-profile assignments and selections discarded (4.5.2 baseline not pinned)"
			blocks.clear()
			block_sets.clear()
			current = -1
			last_selector = -1
			set_after_selector = false
			ignored.append("line %d: %s (%s)" % [number, _clip(line), note])
		else:
			ignored.append("line %d: %s (not executed)" % [number, _clip(line)])

	if version.is_empty():
		errors.append("unsupported firmware version: no '# Betaflight / ...' version header (only %s is supported)" % SOURCE_VERSION)
	elif version != SOURCE_VERSION:
		errors.append("unsupported firmware version: %s (only %s is supported)" % [version, SOURCE_VERSION])
	else:
		accepted.append("firmware header: Betaflight %s%s" % [version, " (revision %s)" % revision if not revision.is_empty() else ""])
	if not refused.is_empty():
		errors.append("%d malformed or out-of-scope rate-profile values refused" % refused.size())

	# Selection: explicit request; else the trailing restoration selector (a final `rateprofile N` with no `set`
	# after it); else the only block with settings; else unresolved (FPV/07 SET-33-D).
	var with_sets: Array = []
	for index in block_sets.keys():
		if int(block_sets[index]) > 0:
			with_sets.append(int(index))
	with_sets.sort()
	if requested_profile >= 0:
		selected = requested_profile
	elif last_selector >= 0 and not set_after_selector:
		selected = last_selector
	elif with_sets.size() == 1:
		selected = with_sets[0]
	elif with_sets.is_empty():
		errors.append("no rateprofile block with settings found")
	else:
		errors.append("active rate profile unresolved: blocks %s and no final restoration selector; pass requested_profile" % str(with_sets))
	if selected >= 0 and not with_sets.has(selected):
		errors.append("rateprofile %d has no settings in the input" % selected)
		selected = -1
	if selected < 0:
		return _import_result(null, version, selected, accepted, ignored, refused, defaults_used, errors)

	# Rate fields of non-selected blocks are reported, never applied.
	for index in blocks.keys():
		if int(index) == selected:
			continue
		var other: Dictionary = blocks[index]
		for key in other.keys():
			ignored.append("line %d: rateprofile %d %s (not the selected profile; not applied)" % [other[key][1], int(index), key])

	var chosen: Dictionary = blocks.get(selected, {})
	var missing := PackedStringArray()
	var family := ""
	if chosen.has("rates_type"):
		family = chosen.rates_type[0]
		accepted.append("line %d: rateprofile %d rates_type = %s" % [chosen.rates_type[1], selected, family])
		if UNSUPPORTED_FAMILIES.has(family) or not FIELD_DOMAINS.has(family):
			errors.append("unsupported rates_type %s in rateprofile %d (supported: ACTUAL, BETAFLIGHT)" % [family, selected])
	elif PINNED_DEFAULTS.has("rates_type"):
		family = str(PINNED_DEFAULTS.get("rates_type", ""))
		defaults_used.append("rates_type")
	else:
		missing.append("rates_type")
	var axes := {}
	for axis_name in AXIS_NAMES:
		var fields := {}
		for field in FIELD_NAMES:
			var key: String = "%s_%s" % [axis_name, field]
			if chosen.has(key):
				fields[field] = chosen[key][0]
				accepted.append("line %d: rateprofile %d %s = %d" % [chosen[key][1], selected, key, chosen[key][0]])
			elif PINNED_DEFAULTS.has(key):
				fields[field] = PINNED_DEFAULTS.get(key)
				defaults_used.append(key)
			else:
				missing.append(key)
		axes[axis_name] = fields
	if not missing.is_empty():
		errors.append("incomplete rateprofile %d: missing %s; no Betaflight %s default is pinned in the FPV documents, so omitted fields are not reconstructed" % [
			selected, ", ".join(missing), SOURCE_VERSION])
	if not errors.is_empty():
		return _import_result(null, version, selected, accepted, ignored, refused, defaults_used, errors)

	var profile := {
		format = FORMAT,
		family = family,
		source = {firmware = SOURCE_FIRMWARE, version = SOURCE_VERSION, commit = SOURCE_COMMIT, profile_index = selected},
		axes = axes,
	}
	var check: Dictionary = validate(profile)
	if not check.ok:
		for message in check.errors:
			refused.append("rateprofile %d: %s" % [selected, message])
			errors.append(message)
		return _import_result(null, version, selected, accepted, ignored, refused, defaults_used, errors)
	return _import_result(profile, version, selected, accepted, ignored, refused, defaults_used, errors)


static func _import_result(profile: Variant, version: String, selected: int, accepted: PackedStringArray,
		ignored: PackedStringArray, refused: PackedStringArray, defaults_used: PackedStringArray,
		errors: PackedStringArray) -> Dictionary:
	var ok: bool = profile != null and errors.is_empty()
	return {
		ok = ok,
		profile = profile if ok else {},
		report = {firmware_version = version, selected_profile = selected, accepted = accepted, ignored = ignored,
			refused = refused, defaults_used = defaults_used},
		errors = errors,
	}


## [version, revision] from a "# Betaflight / TARGET (ID) X.Y.Z date / time (rev) MSP API: a.b" header, else [].
static func _parse_header(line: String) -> PackedStringArray:
	var body: String = line.substr(1).strip_edges()
	if not body.begins_with("Betaflight /"):
		return PackedStringArray()
	var version := ""
	var revision := ""
	for word in body.split(" ", false):
		if version.is_empty() and _is_dotted_version(word):
			version = word
		elif word.length() > 2 and word.begins_with("(") and word.ends_with(")") and word.substr(1, word.length() - 2).is_valid_hex_number():
			revision = word.substr(1, word.length() - 2).to_lower()
	if version.is_empty():
		version = "unrecognized"
	return PackedStringArray([version, revision])


static func _is_dotted_version(word: String) -> bool:
	var parts: PackedStringArray = word.split(".")
	if parts.size() != 3:
		return false
	for part in parts:
		if part.is_empty() or part.length() > 4 or not _all_digits(part):
			return false
	return true


static func _is_rate_key(key: String) -> bool:
	if key == "rates_type":
		return true
	for axis_name in AXIS_NAMES:
		for field in FIELD_NAMES:
			if key == "%s_%s" % [axis_name, field]:
				return true
	return false


## The parsed value of a supported field, or null when malformed. rates_type: an identifier, upper-cased; every
## other supported field: a decimal integer of at most INT_MAX_DIGITS digits (range checks happen in validate).
static func _parse_value(key: String, text: String) -> Variant:
	if key == "rates_type":
		if text.is_empty() or text.length() > 32:
			return null
		for c in text:
			if not (c == "_" or (c >= "A" and c <= "Z") or (c >= "a" and c <= "z") or (c >= "0" and c <= "9")):
				return null
		return text.to_upper()
	return _parse_cli_int(text)


static func _parse_cli_int(text: String) -> Variant:
	var digits: String = text.substr(1) if text.begins_with("-") else text
	if digits.is_empty() or digits.length() > INT_MAX_DIGITS or not _all_digits(digits):
		return null
	return text.to_int()


static func _all_digits(text: String) -> bool:
	for c in text:
		if c < "0" or c > "9":
			return false
	return true


static func _clip(text: String) -> String:
	return text if text.length() <= 80 else text.substr(0, 77) + "..."


static func _show(value: Variant) -> String:
	return "'%s'" % value if typeof(value) == TYPE_STRING else type_string(typeof(value))


static func _is_text(value: Variant, expected: String) -> bool:
	return typeof(value) == TYPE_STRING and value == expected


## A {name: value} view of a dictionary keyed by String or StringName. With `allowed` non-empty, unknown, duplicate,
## non-text and missing keys are reported into `errors`; with `allowed` empty the view is built without checks.
static func _view(source: Dictionary, where: String, allowed: Array, errors: PackedStringArray) -> Dictionary:
	var out := {}
	for key in source.keys():
		var kind: int = typeof(key)
		if kind != TYPE_STRING and kind != TYPE_STRING_NAME:
			if not allowed.is_empty():
				errors.append("%s: non-text key of type %s" % [where, type_string(kind)])
			continue
		var name: String = String(key)
		if not allowed.is_empty() and not allowed.has(name):
			errors.append("%s: unknown key '%s'" % [where, name])
			continue
		if out.has(name):
			errors.append("%s: duplicate key '%s'" % [where, name])
			continue
		out[name] = source[key]
	for name in allowed:
		if not out.has(name):
			errors.append("%s: missing key '%s'" % [where, name])
	return out


static func _validate_source(value: Variant, errors: PackedStringArray) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("source: expected a Dictionary")
		return
	var source: Dictionary = _view(value, "source", ["firmware", "version", "commit", "profile_index"], errors)
	if source.has("firmware") and not _is_text(source.firmware, SOURCE_FIRMWARE):
		errors.append("source.firmware: expected '%s', got %s" % [SOURCE_FIRMWARE, _show(source.firmware)])
	if source.has("version") and not _is_text(source.version, SOURCE_VERSION):
		errors.append("source.version: unsupported firmware version %s (only %s)" % [_show(source.version), SOURCE_VERSION])
	if source.has("commit") and not _is_text(source.commit, SOURCE_COMMIT):
		errors.append("source.commit: expected the pinned commit %s" % SOURCE_COMMIT)
	if source.has("profile_index"):
		if typeof(source.profile_index) != TYPE_INT:
			errors.append("source.profile_index: expected an int, got %s" % type_string(typeof(source.profile_index)))
		elif int(source.profile_index) < PROFILE_INDEX_NONE or int(source.profile_index) > PROFILE_INDEX_MAX:
			errors.append("source.profile_index: %d outside [%d, %d]" % [source.profile_index, PROFILE_INDEX_NONE, PROFILE_INDEX_MAX])


static func _validate_axis(value: Variant, where: String, family: String, errors: PackedStringArray) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s: expected a Dictionary" % where)
		return
	var fields: Dictionary = _view(value, where, FIELD_NAMES, errors)
	for field in FIELD_NAMES:
		if not fields.has(field):
			continue
		var raw: Variant = fields[field]
		if typeof(raw) != TYPE_INT:
			errors.append("%s.%s: expected an int (raw CLI integer), got %s" % [where, field, type_string(typeof(raw))])
			continue
		if family.is_empty():
			continue
		var domain: Array = FIELD_DOMAINS[family][field]
		var low: int = domain[0]
		var high: int = domain[1]
		if int(raw) < low or (high >= 0 and int(raw) > high):
			var upper: String = str(high) if high >= 0 else "unbounded"
			errors.append("%s.%s: %d outside the %s domain [%d, %s]" % [where, field, raw, family, low, upper])
