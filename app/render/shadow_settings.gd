## VQ-04b-S01/S02: one process-wide owner for directional shadow allocation.
## Pure resolution is separate from global commits and per-world light adaptation.
## No simulation, material energy, local-light or contact-shadow changes belong here.
extends RefCounted

const QUALITY: Array[String] = ["current", "low", "medium", "high", "ultra"]
const TECHNIQUES: Array[String] = ["auto", "native", "projected", "off"]
const AIRCRAFT_CUES: Array[String] = ["auto", "sun", "vertical", "off"]
const DISTANCES: Array[String] = ["auto", "near", "field", "far"]
const SOFTNESS: Array[String] = ["auto", "hard", "soft"]
const DEFAULTS := {
	"shadow_quality": "current", "shadow_technique": "auto", "shadow_aircraft_cue": "auto",
	"shadow_distance": "auto", "shadow_softness": "auto",
}
const CHOICES := {
	"shadow_quality": QUALITY, "shadow_technique": TECHNIQUES, "shadow_aircraft_cue": AIRCRAFT_CUES,
	"shadow_distance": DISTANCES, "shadow_softness": SOFTNESS,
}
const DISTANCE_METRES := {"auto": 300.0, "near": 100.0, "field": 300.0, "far": 600.0}
# Candidate allocations are opt-in; Current reproduces the installed renderer profile.
const TIERS := {
	"low": {"atlas_size": 2048, "use_16_bits": true, "cascades": 2, "filter_quality": 1},
	"medium": {"atlas_size": 4096, "use_16_bits": true, "cascades": 2, "filter_quality": 2},
	"high": {"atlas_size": 4096, "use_16_bits": false, "cascades": 4, "filter_quality": 3},
	"ultra": {"atlas_size": 8192, "use_16_bits": false, "cascades": 4, "filter_quality": 4},
}
const ATLAS_SETTING := "rendering/lights_and_shadows/directional_shadow/size"
const DEPTH_SETTING := "rendering/lights_and_shadows/directional_shadow/16_bits"
const FILTER_SETTING := "rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"
const LIGHT_BASE := &"openrc_shadow_base"
const LIGHT_REQUEST := &"openrc_shadow_requested"
const LIGHT_REVISION := &"openrc_shadow_revision"
const LIGHT_DISTANCE_CAP := &"openrc_shadow_distance_cap"

static var revision := 0
static var _requested: Dictionary = DEFAULTS.duplicate(true)
static var _receipt: Dictionary = {}
static var _global_signature: Array = []
static var _lights: Array[WeakRef] = []
static var _lighting_refresh := Callable()


static func normalize(raw: Dictionary) -> Dictionary:
	var result := DEFAULTS.duplicate(true)
	for key: String in DEFAULTS:
		var value: Variant = raw.get(key, DEFAULTS[key])
		if value is String and CHOICES[key].has(value):
			result[key] = value
	return result


## Explicit arguments allow capability and malformed-input checks without a renderer.
static func resolve(raw: Dictionary, renderer: String, high_profile: bool,
		project_defaults: Dictionary = {}) -> Dictionary:
	var requested := normalize(raw)
	var reasons: Array[String] = []
	var quality: String = requested.shadow_quality
	var allocation: Dictionary = TIERS.get(quality, {}).duplicate(true)
	if quality == "current":
		allocation = {"atlas_size": 8192 if high_profile else int(project_defaults.get("atlas_size", 4096)),
			"use_16_bits": false if high_profile else bool(project_defaults.get("use_16_bits", true)),
			"cascades": 4 if high_profile else 2,
			"filter_quality": 3 if high_profile else int(project_defaults.get("filter_quality", 2))}
	var technique: String = requested.shadow_technique
	var native := technique in ["auto", "native"]
	var projected := technique in ["auto", "projected"]
	if renderer not in ["gl_compatibility", "forward_plus", "mobile"]:
		if technique == "native":
			technique = "projected"
			projected = true
			reasons.append("Native shadows unavailable; using projected shadows.")
		native = false
	var cue: String = requested.shadow_aircraft_cue
	if not projected:
		if cue != "off":
			reasons.append("The selected technique suppresses the planar aircraft cue.")
		cue = "off"
	if technique == "auto":
		reasons.append("Current coverage retains both native and projected shadows.")
	var softness: String = requested.shadow_softness
	if softness == "auto":
		softness = "hard" if int(allocation.filter_quality) == 0 else "soft"
	if softness == "hard":
		allocation.filter_quality = 0
	elif int(allocation.filter_quality) == 0:
		allocation.filter_quality = 2
	# Angular size must also be zero for hard shadows; a Hard filter alone does not disable PCSS.
	var angular_distance := 0.53 if high_profile and softness == "soft" else 0.0
	var filter_technique := "pcss" if angular_distance > 0.0 else ("pcf" if softness == "soft" else "hard")
	if softness == "soft" and not high_profile:
		reasons.append("This profile uses PCF filtering; solar PCSS requires High.")
	if not native:
		reasons.append("Native quality, distance and softness apply when native shadows are enabled.")
	var effective := {"technique": technique, "quality": quality, "native": native, "projected": projected,
		"aircraft_cue": cue, "distance_m": float(DISTANCE_METRES[requested.shadow_distance]),
		"softness": softness, "filter_technique": filter_technique, "angular_distance": angular_distance,
		"renderer": renderer, "high_profile": high_profile, "contact_shadows": false}
	effective.merge(allocation)
	return {"requested": requested, "effective": effective, "reasons": reasons}


static func _high_active() -> bool:
	return OS.get_environment("OPENRC_GRAPHICS_PROFILE").strip_edges().to_lower() in ["", "high"] \
		and RenderingServer.get_current_rendering_method() == "forward_plus" and DisplayServer.get_name() != "headless"


static func _project_defaults() -> Dictionary:
	return {"atlas_size": ProjectSettings.get_setting_with_override(ATLAS_SETTING),
		"use_16_bits": ProjectSettings.get_setting_with_override(DEPTH_SETTING),
		"filter_quality": ProjectSettings.get_setting_with_override(FILTER_SETTING)}


## Only this owner writes global atlas/filter state. World constructors merely ensure initialization.
static func apply(raw: Dictionary) -> Dictionary:
	_requested = normalize(raw)
	_commit(_high_active())
	return describe()


static func ensure_configured(high_profile: bool) -> void:
	if _receipt.is_empty() or bool(_receipt.effective.high_profile) != high_profile:
		_commit(high_profile)


static func _commit(high_profile: bool) -> void:
	var receipt := resolve(_requested, RenderingServer.get_current_rendering_method(), high_profile, _project_defaults())
	receipt["rendering_available"] = DisplayServer.get_name() != "headless"
	if receipt == _receipt:
		return
	var previous_native := bool(_receipt.effective.native) if not _receipt.is_empty() else bool(receipt.effective.native)
	_receipt = receipt
	revision += 1
	var state: Dictionary = _receipt.effective
	var signature: Array = [state.atlas_size, state.use_16_bits, state.filter_quality]
	if signature != _global_signature:
		if DisplayServer.get_name() != "headless":
			RenderingServer.directional_shadow_atlas_set_size(int(state.atlas_size), bool(state.use_16_bits))
			RenderingServer.directional_soft_shadow_filter_set_quality(int(state.filter_quality) as RenderingServer.ShadowQuality)
		_global_signature = signature
	var alive: Array[WeakRef] = []
	for reference in _lights:
		var light := reference.get_ref() as DirectionalLight3D
		if light != null:
			alive.append(reference)
			_apply_light(light, bool(light.get_meta(LIGHT_REQUEST, light.shadow_enabled)))
	_lights = alive
	if previous_native != bool(state.native) and _lighting_refresh.is_valid():
		_lighting_refresh.call(bool(state.native))
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.call_group(&"shadow_policy_consumers", &"apply_shadow_policy")


static func describe() -> Dictionary:
	ensure_configured(_high_active())
	var result := _receipt.duplicate(true)
	# Research tools may explicitly enable this outside the user settings; report the actual state.
	result.effective.contact_shadows = _high_active() and bool(ProjectSettings.get_setting(
		"rendering/lights_and_shadows/contact_shadow/enabled", false))
	return result


static func effective() -> Dictionary:
	ensure_configured(_high_active())
	return _receipt.effective.duplicate(true)


## Atmosphere registers the owner of existing light/fog/material compensation.
static func set_lighting_refresh(callback: Callable) -> void:
	_lighting_refresh = callback


static func native_enabled() -> bool:
	if _receipt.is_empty():
		ensure_configured(_high_active())
	return bool(_receipt.effective.native)


static func projected_enabled() -> bool:
	if _receipt.is_empty():
		ensure_configured(_high_active())
	return bool(_receipt.effective.projected)


static func aircraft_cue() -> String:
	if _receipt.is_empty():
		ensure_configured(_high_active())
	return str(_receipt.effective.aircraft_cue)


## Called after the atmosphere/profile has established its original per-light values.
static func apply_sun(light: DirectionalLight3D, source_enabled: bool) -> void:
	ensure_configured(_high_active())
	if not light.has_meta(LIGHT_BASE):
		# World churn must remain bounded even when the user never changes a setting.
		var alive: Array[WeakRef] = []
		for reference in _lights:
			if reference.get_ref() != null:
				alive.append(reference)
		_lights = alive
		light.set_meta(LIGHT_BASE, {"mode": light.directional_shadow_mode,
			"blend": light.directional_shadow_blend_splits, "split_1": light.directional_shadow_split_1,
			"split_2": light.directional_shadow_split_2, "split_3": light.directional_shadow_split_3,
			"distance": light.directional_shadow_max_distance, "angular_distance": light.light_angular_distance})
		_lights.append(weakref(light))
	light.set_meta(LIGHT_REQUEST, source_enabled)
	_apply_light(light, source_enabled)


## A close activity can cap its own shadow range without changing global allocation.
static func set_distance_cap(light: DirectionalLight3D, metres: float) -> void:
	if is_finite(metres) and metres > 0.0:
		light.set_meta(LIGHT_DISTANCE_CAP, metres)
		light.remove_meta(LIGHT_REVISION)
		if light.has_meta(LIGHT_BASE):
			_apply_light(light, bool(light.get_meta(LIGHT_REQUEST, light.shadow_enabled)))


static func _apply_light(light: DirectionalLight3D, source_enabled: bool) -> void:
	var state: Dictionary = _receipt.effective
	light.shadow_enabled = source_enabled and bool(state.native)
	# High's adapter reapplies its values during time flow, so restore this local policy too.
	var base: Dictionary = light.get_meta(LIGHT_BASE)
	if state.quality == "current":
		light.directional_shadow_mode = int(base.mode) as DirectionalLight3D.ShadowMode
		light.directional_shadow_blend_splits = bool(base.blend)
		light.directional_shadow_split_1 = float(base.split_1)
		light.directional_shadow_split_2 = float(base.split_2)
		light.directional_shadow_split_3 = float(base.split_3)
	else:
		light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if int(state.cascades) == 4 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		light.directional_shadow_blend_splits = int(state.cascades) == 4
		light.directional_shadow_split_1 = 0.06 if int(state.cascades) == 4 else 0.1
		light.directional_shadow_split_2 = 0.20
		light.directional_shadow_split_3 = 0.50
	var distance: float = float(base.distance) if _requested.shadow_distance == "auto" else float(state.distance_m)
	light.directional_shadow_max_distance = minf(distance, float(light.get_meta(LIGHT_DISTANCE_CAP, INF)))
	light.light_angular_distance = float(base.angular_distance) if _requested.shadow_softness == "auto" else float(state.angular_distance)
	if _requested.shadow_softness == "hard":
		light.light_angular_distance = 0.0
	light.set_meta(LIGHT_REVISION, revision)
