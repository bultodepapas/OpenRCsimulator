## Authored, deterministic spatial-wind practice scenarios. These are not site measurements.
extends RefCounted

const SpatialConfig := preload("res://physics/wind_spatial_config.gd")
const GUST_AGENDA_STARTS: Array[float] = [
	6.0, 22.0, 51.0, 93.0, 148.0, 220.0, 311.0, 421.0,
	552.0, 630.0, 704.0, 765.0, 813.0, 850.0, 876.0, 890.0,
	1060.0, 1180.0, 1290.0, 1400.0, 1510.0, 1620.0, 1725.0, 1792.0,
]
const GUST_AGENDA_DURATIONS: Array[float] = [
	4.0, 3.5, 5.0, 4.5, 3.0, 4.0, 5.0, 3.5,
	4.5, 3.0, 5.0, 4.0, 3.5, 5.0, 4.0, 3.0,
	4.0, 4.5, 3.5, 5.0, 4.0, 3.0, 4.5, 5.0,
]
const GUST_AGENDA_SPEEDS: Array[float] = [
	1.4, 1.8, 1.5, 2.2, 1.6, 1.9, 1.3, 2.0,
	1.7, 1.5, 2.1, 1.4, 1.9, 1.6, 2.2, 1.5,
	1.8, 1.4, 2.0, 1.6, 2.1, 1.5, 1.9, 1.4,
]
const GUST_AGENDA_FROM: Array[float] = [
	90.0, 75.0, 105.0, 90.0, 120.0, 70.0, 95.0, 110.0,
	80.0, 100.0, 65.0, 115.0, 85.0, 105.0, 75.0, 90.0,
	100.0, 80.0, 110.0, 70.0, 95.0, 120.0, 75.0, 90.0,
]


## Stable IDs are separate from the legacy WindConfig preset namespace.
static func entries() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	output.append(_entry("spatial-realistic-v1", "Realistic · light breeze training",
		"1.5 m/s FROM 075° at 10 m, with 0.08 m/s nominal turbulence and a subdued finite gust agenda. Authored practice conditions, not a site measurement.",
		_realistic()))
	output.append(_entry("spatial-light-breeze-v1", "Light breeze · 2.5 m/s FROM 090°",
		"A steady east wind at the reference height. This does not include terrain flow.",
		_steady(2.5, 90.0)))
	output.append(_entry("spatial-crosswind-v1", "Crosswind training · 5 m/s FROM 000°",
		"A north wind. Headwind and crosswind components depend on the active runway heading.",
		_steady(5.0, 0.0)))
	output.append(_entry("spatial-gusty-v1", "Gusty · finite irregular agenda",
		"A 30-minute training agenda with 24 finite events inside a one-day validity horizon; gusts stop after the last event and the profile remains.",
		_gusty()))
	output.append(_entry("spatial-shear-v1", "Vertical shear training · one smooth layer",
		"A finite-height wind layer adds a smooth direction and speed change above the reference height.",
		_shear()))
	var thermal := _thermal_soaring()
	if not thermal.is_empty():
		output.append(_entry("spatial-thermal-soaring-v2", "Thermal soaring training · finite kinematic cell",
			"One prescribed finite updraft cell; no sun, terrain, or heating evolution is modeled.", thermal))
	else:
		output.append(_unavailable("spatial-thermal-soaring-v2", "Thermal soaring (unavailable)",
			"The spatial provider could not validate the finite thermal practice cell."))
	output.append(_entry("spatial-strong-wind-v1", "Strong wind · 8 m/s FROM 090°",
		"A steady east wind at the reference height. Use only when the selected aircraft and scenario support it.",
		_steady(8.0, 90.0)))
	output.append(_unavailable("spatial-ridge-lift-v1", "Ridge lift (unavailable)",
		"Terrain-driven ridge lift is not represented by the flat-site spatial-wind provider."))
	output.append(_unavailable("spatial-rotor-v1", "Terrain rotor (unavailable)",
		"Terrain-driven rotor flow is not represented by the flat-site spatial-wind provider."))
	output.append(_unavailable("spatial-valley-v1", "Valley channeling (unavailable)",
		"Valley channeling is not represented by the flat-site spatial-wind provider."))
	return output


static func get_preset(preset_id: String) -> Dictionary:
	for entry: Dictionary in entries():
		if str(entry.id) == preset_id:
			return entry.duplicate(true) if bool(entry.available) else {}
	return {}


static func _entry(preset_id: String, label: String, description: String, spatial: Dictionary) -> Dictionary:
	return {
		"id": preset_id,
		"label": label,
		"description": description,
		"available": true,
		"unavailable_reason": "",
		"spatial_wind": spatial,
	}


static func _unavailable(preset_id: String, label: String, reason: String) -> Dictionary:
	return {
		"id": preset_id,
		"label": label,
		"description": reason,
		"available": false,
		"unavailable_reason": reason,
		"spatial_wind": {},
	}


static func _realistic() -> Dictionary:
	var config := _base(1.5, 75.0, 10.0, 0.03)
	config.turbulence.rms_mps = 0.08
	config.identity.seed_u32 = 20261025
	config.gusts.events = _agenda_events(0.2)
	return config


static func _steady(speed_mps: float, from_deg: float) -> Dictionary:
	return _base(speed_mps, from_deg, 10.0, 0.03)


static func _shear() -> Dictionary:
	var config := _base(3.0, 90.0, 10.0, 0.03)
	config.profile.layers = [{
		"id": "training_shear",
		"center_agl_m": 42.0,
		"half_thickness_m": 8.0,
		"delta_wind_ned_mps": [-0.7, 0.35, 0.0],
	}]
	return config


static func _gusty() -> Dictionary:
	var config := _base(3.0, 90.0, 10.0, 0.03)
	config.identity.seed_u32 = 20261026
	config.gusts.events = _agenda_events(1.0)
	return config


static func _agenda_events(amplitude_scale: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for index: int in GUST_AGENDA_STARTS.size():
		events.append({
			"id": "training_gust_%02d" % (index + 1),
			"start_s": GUST_AGENDA_STARTS[index],
			"duration_s": GUST_AGENDA_DURATIONS[index],
			"amplitude_ned_mps": _from_vector(GUST_AGENDA_SPEEDS[index] * amplitude_scale, GUST_AGENDA_FROM[index]),
		})
	return events


static func _thermal_soaring() -> Dictionary:
	var spatial := _base(1.5, 90.0, 10.0, 0.03)
	var thermal_defaults: Dictionary = SpatialConfig.thermal_defaults(spatial)
	if not thermal_defaults.get("ok", false):
		return {}
	var thermal_field: Dictionary = thermal_defaults.config.thermal_field.duplicate(true)
	thermal_field.cells = [{
		"id": "practice_thermal",
		"birth_s": 15.0,
		"duration_s": 360.0,
		"center_ne_m": [220.0, -120.0],
		"drift_ne_mps": [0.25, -0.1],
		"radius_m": 35.0,
		"top_agl_m": 200.0,
		"peak_updraft_mps": 1.2,
	}]
	var upgraded: Dictionary = SpatialConfig.upgrade_thermals(spatial, thermal_field)
	return upgraded.config.duplicate(true) if upgraded.get("ok", false) else {}


static func _base(speed_mps: float, from_deg: float, reference_height_m: float, roughness_m: float) -> Dictionary:
	var config: Dictionary = SpatialConfig.defaults()
	var profile: Dictionary = config.profile
	profile.reference_speed_mps = speed_mps
	profile.reference_from_deg = from_deg
	profile.reference_height_agl_m = reference_height_m
	profile.roughness_length_m = roughness_m
	profile.free_air_wind_ned_mps = _free_air_vector(config, speed_mps, from_deg, reference_height_m, roughness_m)
	return config


static func _free_air_vector(config: Dictionary, speed_mps: float, from_deg: float,
		reference_height_m: float, roughness_m: float) -> Array[float]:
	if speed_mps == 0.0:
		return [0.0, 0.0, 0.0]
	var profile: Dictionary = config.profile
	var displacement := float(profile.displacement_height_m)
	var upper_join_end := float(profile.surface_layer_top_agl_m) + float(profile.free_air_join_height_m)
	var reference_log := log((reference_height_m - displacement) / roughness_m)
	var upper_log := log((upper_join_end - displacement) / roughness_m)
	var upper_speed := speed_mps * upper_log / reference_log
	var radians := deg_to_rad(from_deg)
	return [-upper_speed * cos(radians), -upper_speed * sin(radians), 0.0]


static func _from_vector(speed_mps: float, from_deg: float) -> Array[float]:
	var radians := deg_to_rad(from_deg)
	return [-speed_mps * cos(radians), -speed_mps * sin(radians), 0.0]
