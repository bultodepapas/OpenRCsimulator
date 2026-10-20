## Frozen LU-25-R1 structural validator excerpt for cache-parity checks.
## Frozen on 2026-10-19 from physics/lake_surface.gd, SHA-256:
## dd9e3c3690eb2a71ad0928aee206d0fedcc4399a4b6cc41b542c1282e06a04a1
## Keep independent of the optimized guard; this is a behavior-preservation oracle.
extends RefCounted

const CONTACT_EPSILON_M: float = 0.0000001
const WAVE_PARAMETER_KEYS: Array[String] = ["amplitude_m", "wavelength_m", "period_s", "heading_rad", "phase_rad"]


static func is_valid_definition(lake: Dictionary) -> bool:
	if lake.get("format") != "openrc-lake v1" or typeof(lake.get("id")) != TYPE_STRING \
		or typeof(lake.get("identity")) != TYPE_STRING or String(lake.identity).is_empty():
		return false
	if typeof(lake.get("water_level_down_m")) != TYPE_FLOAT and typeof(lake.get("water_level_down_m")) != TYPE_INT:
		return false
	if not is_finite(float(lake.water_level_down_m)) or float(lake.water_level_down_m) < 0.05 \
		or float(lake.water_level_down_m) > 2.0 or String(lake.id).is_empty():
		return false
	var shoreline: Variant = lake.get("shoreline_ne_m")
	var bank: Variant = lake.get("bank_ne_m")
	var profile: Variant = lake.get("bed_profile")
	var bounds: Variant = lake.get("wave_bounds")
	var waves: Variant = lake.get("waves")
	if typeof(shoreline) != TYPE_PACKED_FLOAT64_ARRAY or typeof(bank) != TYPE_PACKED_FLOAT64_ARRAY \
		or typeof(profile) != TYPE_ARRAY or typeof(waves) != TYPE_ARRAY or typeof(bounds) != TYPE_DICTIONARY:
		return false
	if shoreline.size() < 16 or shoreline.size() % 2 != 0 or bank.size() < 16 or bank.size() % 2 != 0 \
		or profile.size() < 2 or profile.size() > 8 or waves.size() > 2:
		return false
	for coordinate: float in shoreline:
		if not is_finite(coordinate):
			return false
	for coordinate: float in bank:
		if not is_finite(coordinate):
			return false
	for row_value: Variant in profile:
		if typeof(row_value) != TYPE_DICTIONARY:
			return false
		var row: Dictionary = row_value
		if not _finite_number(row.get("inset_m")) or not _finite_number(row.get("depth_m")):
			return false
	for index: int in range(1, profile.size()):
		var previous: Dictionary = profile[index - 1]
		var current: Dictionary = profile[index]
		if float(current.inset_m) <= float(previous.inset_m) or float(current.depth_m) <= float(previous.depth_m):
			return false
	var first_profile_point: Dictionary = profile[0]
	if absf(float(first_profile_point.inset_m)) > CONTACT_EPSILON_M \
		or absf(float(first_profile_point.depth_m)) > CONTACT_EPSILON_M:
		return false
	for key: String in ["max_amplitude_m", "min_wavelength_m", "max_wavelength_m", "min_period_s", "max_period_s", "shore_fade_m"]:
		if not _finite_number(bounds.get(key)):
			return false
	if float(bounds.max_amplitude_m) < 0.0 or float(bounds.min_wavelength_m) <= 0.0 \
		or float(bounds.max_wavelength_m) < float(bounds.min_wavelength_m) \
		or float(bounds.min_period_s) <= 0.0 or float(bounds.max_period_s) < float(bounds.min_period_s) \
		or float(bounds.shore_fade_m) <= 0.0:
		return false
	for wave_value: Variant in waves:
		if typeof(wave_value) != TYPE_DICTIONARY:
			return false
		var wave: Dictionary = wave_value
		for key: String in WAVE_PARAMETER_KEYS:
			if not _finite_number(wave.get(key)):
				return false
	return true


static func _finite_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and is_finite(float(value))
