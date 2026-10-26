## Pure, deterministic thermal circulation from a pre-resolved cell agenda.
## The balanced streamfunction is a kinematic closure, not a buoyancy PDE or forecast.
class_name WindThermalField
extends RefCounted

const FORMAT := "openrc-thermal-field v1"
const LAW := "balanced-axisymmetric-streamfunction-c2-v1"
const FRAME := "NED"
const DATUM_LAW := "flat-site-ground-plane-v1"
const SEED_ALGORITHM := "resolved-explicit-agenda-v1"
const TAU_F64 := 6.283185307179586476925286766559

const ROOT_KEYS := ["format", "identity", "frame", "datum", "domain", "law", "cells"]
const IDENTITY_KEYS := ["agenda_seed_u32", "world_epoch_id_u32", "epoch_offset_s", "seed_algorithm"]
const DATUM_KEYS := ["law", "ground_down_m"]
const DOMAIN_KEYS := ["half_extent_north_m", "half_extent_east_m", "max_height_agl_m", "time_horizon_s"]
const CELL_KEYS := [
	"id", "birth_s", "duration_s", "center_ne_m", "drift_ne_mps", "radius_m", "top_agl_m", "peak_updraft_mps",
]

var _config: Dictionary = {}
var _content_hash := ""


static func defaults() -> Dictionary:
	return {
		"format": FORMAT,
		"identity": {
			"agenda_seed_u32": 20261025,
			"world_epoch_id_u32": 0,
			"epoch_offset_s": 0.0,
			"seed_algorithm": SEED_ALGORITHM,
		},
		"frame": FRAME,
		"datum": {"law": DATUM_LAW, "ground_down_m": 0.0},
		"domain": {
			"half_extent_north_m": 10000.0,
			"half_extent_east_m": 10000.0,
			"max_height_agl_m": 1200.0,
			"time_horizon_s": 86400.0,
		},
		"law": LAW,
		"cells": [],
	}


## Resolve a complete explicit agenda. Random seeds identify its provenance only; queries never generate cells.
static func resolve(raw: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(raw) != TYPE_DICTIONARY:
		return _failure("thermal configuration must be an object")
	var source: Dictionary = raw
	_check_keys(source, ROOT_KEYS, "thermal", errors)
	if source.get("format") != FORMAT:
		errors.append("thermal.format must be '%s'" % FORMAT)
	if source.get("frame") != FRAME:
		errors.append("thermal.frame must be 'NED'")
	if source.get("law") != LAW:
		errors.append("thermal.law must be '%s'" % LAW)

	var identity: Dictionary = {}
	var identity_raw: Variant = source.get("identity")
	if typeof(identity_raw) != TYPE_DICTIONARY:
		errors.append("thermal.identity must be an object")
	else:
		var identity_source: Dictionary = identity_raw
		_check_keys(identity_source, IDENTITY_KEYS, "thermal.identity", errors)
		identity = {
			"agenda_seed_u32": _uint32(identity_source.get("agenda_seed_u32"), "identity.agenda_seed_u32", errors),
			"world_epoch_id_u32": _uint32(identity_source.get("world_epoch_id_u32"), "identity.world_epoch_id_u32", errors),
			"epoch_offset_s": _number(identity_source.get("epoch_offset_s"), "identity.epoch_offset_s", 0.0, 86400.0, errors),
			"seed_algorithm": SEED_ALGORITHM,
		}
		if identity_source.get("seed_algorithm") != SEED_ALGORITHM:
			errors.append("identity.seed_algorithm must be '%s'" % SEED_ALGORITHM)

	var datum: Dictionary = {}
	var datum_raw: Variant = source.get("datum")
	if typeof(datum_raw) != TYPE_DICTIONARY:
		errors.append("thermal.datum must be an object")
	else:
		var datum_source: Dictionary = datum_raw
		_check_keys(datum_source, DATUM_KEYS, "thermal.datum", errors)
		if datum_source.get("law") != DATUM_LAW:
			errors.append("datum.law must be '%s'" % DATUM_LAW)
		datum = {
			"law": DATUM_LAW,
			"ground_down_m": _number(datum_source.get("ground_down_m"), "datum.ground_down_m", 0.0, 0.0, errors),
		}

	var domain: Dictionary = {}
	var domain_raw: Variant = source.get("domain")
	if typeof(domain_raw) != TYPE_DICTIONARY:
		errors.append("thermal.domain must be an object")
	else:
		var domain_source: Dictionary = domain_raw
		_check_keys(domain_source, DOMAIN_KEYS, "thermal.domain", errors)
		domain = {
			"half_extent_north_m": _number(domain_source.get("half_extent_north_m"), "domain.half_extent_north_m", 100.0, 10000.0, errors),
			"half_extent_east_m": _number(domain_source.get("half_extent_east_m"), "domain.half_extent_east_m", 100.0, 10000.0, errors),
			"max_height_agl_m": _number(domain_source.get("max_height_agl_m"), "domain.max_height_agl_m", 200.0, 1200.0, errors),
			"time_horizon_s": _number(domain_source.get("time_horizon_s"), "domain.time_horizon_s", 120.0, 86400.0, errors),
		}

	var cells: Array[Dictionary] = []
	var cells_raw: Variant = source.get("cells")
	if typeof(cells_raw) != TYPE_ARRAY:
		errors.append("thermal.cells must be an array")
	else:
		if cells_raw.size() > 16:
			errors.append("thermal.cells may contain at most 16 entries")
		var previous_birth := -INF
		var previous_id := ""
		var ids := {}
		for index: int in cells_raw.size():
			var cell_raw: Variant = cells_raw[index]
			if typeof(cell_raw) != TYPE_DICTIONARY:
				errors.append("thermal.cells[%d] must be an object" % index)
				continue
			var cell_source: Dictionary = cell_raw
			var label := "thermal.cells[%d]" % index
			_check_keys(cell_source, CELL_KEYS, label, errors)
			var cell_id := _identifier(cell_source.get("id"), "%s.id" % label, errors)
			var birth := _number(cell_source.get("birth_s"), "%s.birth_s" % label, 0.0, 86400.0, errors)
			var duration := _number(cell_source.get("duration_s"), "%s.duration_s" % label, 120.0, 720.0, errors)
			var center := _vector2(cell_source.get("center_ne_m"), "%s.center_ne_m" % label, 10000.0, errors)
			var drift := _vector2(cell_source.get("drift_ne_mps"), "%s.drift_ne_mps" % label, 20.0, errors)
			var radius := _number(cell_source.get("radius_m"), "%s.radius_m" % label, 10.0, 80.0, errors)
			var top := _number(cell_source.get("top_agl_m"), "%s.top_agl_m" % label, 200.0, 1200.0, errors)
			var peak := _number(cell_source.get("peak_updraft_mps"), "%s.peak_updraft_mps" % label, -3.0, 3.0, errors)
			if ids.has(cell_id):
				errors.append("thermal.cells[%d].id must be unique" % index)
			ids[cell_id] = true
			if birth < previous_birth or (birth == previous_birth and cell_id < previous_id):
				errors.append("thermal.cells must be sorted by birth_s and then id")
			previous_birth = birth
			previous_id = cell_id
			cells.append({
				"id": cell_id,
				"birth_s": birth,
				"duration_s": duration,
				"center_ne_m": center,
				"drift_ne_mps": drift,
				"radius_m": radius,
				"top_agl_m": top,
				"peak_updraft_mps": peak,
			})

	if not errors.is_empty():
		return {"ok": false, "config": {}, "content_hash": "", "errors": errors}
	_validate_cells(cells, identity, domain, errors)
	if not errors.is_empty():
		return {"ok": false, "config": {}, "content_hash": "", "errors": errors}

	var canonical := {
		"format": FORMAT,
		"identity": identity,
		"frame": FRAME,
		"datum": datum,
		"domain": domain,
		"law": LAW,
		"cells": cells,
	}
	return {
		"ok": true,
		"config": canonical,
		"content_hash": _hash_canonical(canonical),
		"errors": PackedStringArray(),
	}


static func build(raw: Variant) -> Dictionary:
	var checked: Dictionary = resolve(raw)
	if not checked.ok:
		return {"ok": false, "field": null, "errors": checked.errors}
	var script: Script = load("res://physics/wind_thermal_field.gd")
	var field: Variant = script.new()
	field.call("_apply_config", checked.config, checked.content_hash)
	return {"ok": true, "field": field, "errors": PackedStringArray()}


func _apply_config(config: Dictionary, content_hash: String) -> void:
	_config = config.duplicate(true)
	_content_hash = content_hash


func configuration() -> Dictionary:
	return _config.duplicate(true)


func identity() -> Dictionary:
	return _config.identity.duplicate(true)


func content_hash() -> String:
	return _content_hash


func absolute_speed_bound_mps() -> float:
	var maximum_active_peak := 0.0
	for origin: Dictionary in _config.cells:
		var active_peak := 0.0
		var time := float(origin.birth_s)
		for candidate: Dictionary in _config.cells:
			var start := float(candidate.birth_s)
			var end := start + float(candidate.duration_s)
			if start <= time and time < end:
				active_peak += absf(float(candidate.peak_updraft_mps))
		maximum_active_peak = maxf(maximum_active_peak, active_peak)
	return 2.0 * maximum_active_peak


func sample_world(position_ned: PackedFloat64Array, simulation_time_s: float) -> Dictionary:
	if position_ned.size() != 3:
		return _failure_sample("position_ned must contain exactly three NED components")
	for component: float in position_ned:
		if not is_finite(component):
			return _failure_sample("position_ned must contain only finite numbers")
	if not is_finite(simulation_time_s) or simulation_time_s < 0.0:
		return _failure_sample("simulation_time_s must be finite and nonnegative")
	var domain: Dictionary = _config.domain
	if absf(position_ned[0]) > float(domain.half_extent_north_m):
		return _failure_sample("north position is outside the declared thermal domain")
	if absf(position_ned[1]) > float(domain.half_extent_east_m):
		return _failure_sample("east position is outside the declared thermal domain")
	var height_agl := -position_ned[2]
	if height_agl < 0.0:
		return _failure_sample("position is below the flat-site ground plane")
	if height_agl > float(domain.max_height_agl_m):
		return _failure_sample("position is above the declared thermal domain")
	if simulation_time_s > float(domain.time_horizon_s):
		return _failure_sample("simulation time is outside the declared thermal horizon")
	var epoch_time := simulation_time_s + float(_config.identity.epoch_offset_s)
	if not is_finite(epoch_time) or epoch_time > float(domain.time_horizon_s):
		return _failure_sample("world epoch time is outside the declared thermal horizon")
	if height_agl == 0.0:
		return _success_sample(PackedFloat64Array([0.0, 0.0, 0.0]))

	var result := PackedFloat64Array([0.0, 0.0, 0.0])
	for cell: Dictionary in _config.cells:
		var cell_wind := _cell_velocity(cell, position_ned[0], position_ned[1], height_agl, epoch_time)
		for axis: int in 3:
			result[axis] += cell_wind[axis]
			if not is_finite(result[axis]):
				return _failure_sample("thermal field evaluation overflowed")
	return _success_sample(result)


func _cell_velocity(cell: Dictionary, north_m: float, east_m: float, height_agl: float, epoch_time: float) -> PackedFloat64Array:
	var zero := PackedFloat64Array([0.0, 0.0, 0.0])
	var top := float(cell.top_agl_m)
	if height_agl <= 0.0 or height_agl >= top:
		return zero
	var birth := float(cell.birth_s)
	var duration := float(cell.duration_s)
	var age := epoch_time - birth
	if age < 0.0 or age >= duration:
		return zero
	var time_fraction := age / duration
	var remainder := 1.0 - time_fraction
	var lifecycle := 64.0 * time_fraction * time_fraction * time_fraction * remainder * remainder * remainder
	var center: Array = cell.center_ne_m
	var drift: Array = cell.drift_ne_mps
	var relative_time := age
	var center_north := float(center[0]) + float(drift[0]) * relative_time
	var center_east := float(center[1]) + float(drift[1]) * relative_time
	var offset_north := north_m - center_north
	var offset_east := east_m - center_east
	var radius := float(cell.radius_m)
	var radius_squared := radius * radius
	var radial_squared := offset_north * offset_north + offset_east * offset_east
	var radial_distance := sqrt(radial_squared)
	if radial_distance >= 5.0 * radius:
		return zero

	var taper := 1.0
	var taper_derivative := 0.0
	var radial_ratio := radial_distance / radius
	if radial_ratio > 4.0:
		var taper_fraction := radial_ratio - 4.0
		taper = 1.0 - _smooth5(taper_fraction)
		taper_derivative = -_smooth5_derivative(taper_fraction) / radius

	var peak := float(cell.peak_updraft_mps)
	var vertical_wave := 3.1415926535897932384626433832795 * height_agl / top
	var vertical_value := peak * sin(vertical_wave) * sin(vertical_wave)
	var vertical_derivative := peak * 3.1415926535897932384626433832795 / top * sin(2.0 * vertical_wave)
	var exponential := exp(-radial_squared / radius_squared)
	var radial_velocity := -0.5 * lifecycle * vertical_derivative * radial_distance * exponential * taper
	var vertical_up_velocity := 0.0
	if radial_distance == 0.0:
		# The analytic r->0 limit of (1/r) d(Psi)/dr is A(t) * w(z).
		vertical_up_velocity = lifecycle * vertical_value
	else:
		var radial_derivative := exponential * (
			2.0 * radial_distance * (1.0 - radial_squared / radius_squared) * taper
			+ radial_squared * taper_derivative
		)
		vertical_up_velocity = 0.5 * lifecycle * vertical_value * radial_derivative / radial_distance
	var north_velocity := 0.0
	var east_velocity := 0.0
	if radial_distance > 0.0:
		north_velocity = radial_velocity * offset_north / radial_distance
		east_velocity = radial_velocity * offset_east / radial_distance
	return PackedFloat64Array([north_velocity, east_velocity, -vertical_up_velocity])


func _smooth5(value: float) -> float:
	var x := clampf(value, 0.0, 1.0)
	return x * x * x * (10.0 + x * (-15.0 + 6.0 * x))


func _smooth5_derivative(value: float) -> float:
	var x := clampf(value, 0.0, 1.0)
	return 30.0 * x * x * (1.0 - x) * (1.0 - x)


static func _validate_cells(cells: Array[Dictionary], identity: Dictionary, domain: Dictionary, errors: PackedStringArray) -> void:
	var horizon := float(domain.time_horizon_s)
	if float(identity.epoch_offset_s) > horizon:
		errors.append("identity.epoch_offset_s must not exceed domain.time_horizon_s")
	for index: int in cells.size():
		var cell: Dictionary = cells[index]
		var birth := float(cell.birth_s)
		var duration := float(cell.duration_s)
		var radius := float(cell.radius_m)
		var top := float(cell.top_agl_m)
		var center: Array = cell.center_ne_m
		var drift: Array = cell.drift_ne_mps
		if birth + duration > horizon:
			errors.append("cells[%d] lifetime exceeds domain.time_horizon_s" % index)
		if top > float(domain.max_height_agl_m):
			errors.append("cells[%d].top_agl_m exceeds domain.max_height_agl_m" % index)
		if radius > 0.5 * top:
			errors.append("cells[%d].radius_m must not exceed half its top_agl_m" % index)
		if absf(float(center[0])) + absf(float(drift[0])) * duration + 5.0 * radius > float(domain.half_extent_north_m):
			errors.append("cells[%d] radial support and drift exceed the north domain" % index)
		if absf(float(center[1])) + absf(float(drift[1])) * duration + 5.0 * radius > float(domain.half_extent_east_m):
			errors.append("cells[%d] radial support and drift exceed the east domain" % index)
	var max_overlap := 0
	var max_peak_sum := 0.0
	for origin: Dictionary in cells:
		var active_count := 0
		var active_peak_sum := 0.0
		var origin_time := float(origin.birth_s)
		for candidate: Dictionary in cells:
			var start := float(candidate.birth_s)
			var end := start + float(candidate.duration_s)
			if start <= origin_time and origin_time < end:
				active_count += 1
				active_peak_sum += absf(float(candidate.peak_updraft_mps))
		max_overlap = maxi(max_overlap, active_count)
		max_peak_sum = maxf(max_peak_sum, active_peak_sum)
	if max_overlap > 4:
		errors.append("thermal agenda allows at most four overlapping cells")
	if max_peak_sum > 6.0:
		errors.append("overlapping absolute peak updrafts must sum to at most 6 m/s")


static func _vector2(raw: Variant, label: String, maximum_component: float, errors: PackedStringArray) -> Array:
	if typeof(raw) != TYPE_ARRAY or raw.size() != 2:
		errors.append("%s must be an array of two finite numbers" % label)
		return [NAN, NAN]
	return [
		_number(raw[0], "%s[0]" % label, -maximum_component, maximum_component, errors),
		_number(raw[1], "%s[1]" % label, -maximum_component, maximum_component, errors),
	]


static func _check_keys(source: Dictionary, required: Array, label: String, errors: PackedStringArray) -> void:
	for key: String in required:
		if not source.has(key):
			errors.append("%s is missing required field '%s'" % [label, key])
	for key: Variant in source:
		if key not in required:
			errors.append("%s has unknown field '%s'" % [label, str(key)])


static func _number(value: Variant, label: String, minimum: float, maximum: float, errors: PackedStringArray) -> float:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		errors.append("%s must be a finite number" % label)
		return NAN
	var number := float(value)
	if not is_finite(number):
		errors.append("%s must be a finite number" % label)
		return NAN
	if number < minimum or number > maximum:
		errors.append("%s must be in [%s, %s]" % [label, minimum, maximum])
	return number


static func _uint32(value: Variant, label: String, errors: PackedStringArray) -> int:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		errors.append("%s must be an integer in [0, 4294967295]" % label)
		return 0
	var number := float(value)
	if not is_finite(number) or number < 0.0 or number > 4294967295.0 or number != floor(number):
		errors.append("%s must be an integer in [0, 4294967295]" % label)
		return 0
	return int(number)


static func _identifier(value: Variant, label: String, errors: PackedStringArray) -> String:
	if typeof(value) != TYPE_STRING or str(value).is_empty() or str(value).length() > 64:
		errors.append("%s must be a nonempty string of at most 64 characters" % label)
		return ""
	return str(value)


static func _hash_canonical(config: Dictionary) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(JSON.stringify(config, "", true, true).to_utf8_buffer())
	return context.finish().hex_encode()


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "config": {}, "content_hash": "", "errors": PackedStringArray([message])}


func _success_sample(wind: PackedFloat64Array) -> Dictionary:
	return {"ok": true, "wind_ned_mps": wind, "error": ""}


func _failure_sample(message: String) -> Dictionary:
	return {"ok": false, "wind_ned_mps": PackedFloat64Array(), "error": message}
