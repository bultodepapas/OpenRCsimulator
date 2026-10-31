extends SceneTree

const Settings := preload("res://render/shadow_settings.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const High := preload("res://render/high_graphics_profile.gd")
const Spec := preload("res://spec.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func run() -> void:
	var previous: Dictionary = Settings.describe().requested
	var original_engine := Atmosphere.engine_shadows
	var original_state := Atmosphere.state.duplicate(true)
	var original_spec := Spec.ATMOSPHERE.duplicate(true)
	var standard := Settings.resolve({}, "gl_compatibility", false)
	check("current preserves combined coverage", standard.effective.native and standard.effective.projected and standard.effective.technique == "auto")
	check("current standard preserves allocation", standard.effective.atlas_size == 4096 and standard.effective.cascades == 2 and standard.effective.use_16_bits)
	var high := Settings.resolve({}, "forward_plus", true)
	check("current High preserves allocation and PCSS", high.effective.atlas_size == 8192 and high.effective.cascades == 4 and not high.effective.use_16_bits and high.effective.angular_distance == 0.53)
	check("malformed selections independently fall back", Settings.normalize({shadow_technique = "native", shadow_quality = 99, shadow_distance = "distant", shadow_softness = null}) == {
		shadow_technique = "native", shadow_quality = "current", shadow_distance = "auto", shadow_softness = "auto", shadow_aircraft_cue = "auto"})
	for technique: String in Settings.TECHNIQUES:
		var result: Dictionary = Settings.resolve({shadow_technique = technique}, "forward_plus", true).effective
		check(technique + " native ownership", result.native == (technique in ["auto", "native"]))
		check(technique + " projected ownership", result.projected == (technique in ["auto", "projected"]))
		if not result.projected:
			check(technique + " disables aircraft cue", result.aircraft_cue == "off")
	var unsupported := Settings.resolve({shadow_technique = "native"}, "unknown", false)
	check("unknown renderer refuses native and reports fallback", not unsupported.effective.native and unsupported.effective.technique == "projected" and not unsupported.reasons.is_empty())
	var hard: Dictionary = Settings.resolve({shadow_softness = "hard"}, "forward_plus", true).effective
	check("hard disables PCSS and filtering together", hard.angular_distance == 0.0 and hard.filter_quality == 0)
	for quality: String in Settings.QUALITY:
		var result: Dictionary = Settings.resolve({shadow_quality = quality}, "gl_compatibility", false).effective
		check(quality + " bounds atlas", result.atlas_size in [2048, 4096, 8192])
		check(quality + " never invents Compatibility PCSS", result.angular_distance == 0.0 and result.filter_technique != "pcss")
	Settings.apply({})
	var first_revision := Settings.revision
	Settings.apply({})
	High.configure()
	check("same settings/world initialization is idempotent", Settings.revision == first_revision)
	var receipt := Settings.describe()
	receipt.requested.shadow_quality = "ultra"
	receipt.effective.native = false
	check("diagnostic snapshots cannot mutate live state", Settings.describe().requested.shadow_quality == "current" and Settings.effective().native)
	Atmosphere.state = {}
	Atmosphere.engine_shadows = true
	var holder := Node3D.new()
	root.add_child(holder)
	var sun := Atmosphere.create_sun(holder)
	var base_mode := sun.directional_shadow_mode
	var base_blend := sun.directional_shadow_blend_splits
	var base_distance := sun.directional_shadow_max_distance
	var base_angle := sun.light_angular_distance
	var base_energy := sun.light_energy
	var base_color := sun.light_color
	var base_bias := sun.shadow_bias
	var base_normal_bias := sun.shadow_normal_bias
	Settings.apply({shadow_technique = "native", shadow_quality = "high", shadow_distance = "near", shadow_softness = "hard"})
	check("live existing sun takes near range and four cascades", sun.shadow_enabled and sun.directional_shadow_max_distance == 100.0 and sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	check("hard solar shadow has no angular blur", sun.light_angular_distance == 0.0)
	Atmosphere.update_sun(sun)
	check("time-of-day reapply cannot overwrite preferences", sun.directional_shadow_max_distance == 100.0 and sun.light_angular_distance == 0.0)
	check("policy preserves direct light/color/bias", sun.light_energy == base_energy and sun.light_color == base_color and sun.shadow_bias == base_bias and sun.shadow_normal_bias == base_normal_bias)
	Settings.apply({shadow_technique = "projected"})
	check("projected disables existing native sun", not sun.shadow_enabled and Settings.projected_enabled())
	Atmosphere.update_sun(sun)
	check("lighting update does not reactivate native sun", not sun.shadow_enabled and sun.light_energy == base_energy)
	Settings.apply({shadow_technique = "off"})
	check("off disables both direct routes", not sun.shadow_enabled and not Settings.projected_enabled())
	Settings.apply({})
	check("revert restores original local settings", sun.shadow_enabled and sun.directional_shadow_mode == base_mode and sun.directional_shadow_blend_splits == base_blend and sun.directional_shadow_max_distance == base_distance and sun.light_angular_distance == base_angle)
	Settings.set_distance_cap(sun, 35.0)
	Settings.apply({shadow_distance = "far"})
	Atmosphere.update_sun(sun)
	check("close activity range cap survives live changes and flow", sun.directional_shadow_max_distance == 35.0)
	Atmosphere.engine_shadows = false
	Atmosphere.update_sun(sun)
	Settings.apply({shadow_technique = "native"})
	check("explicit engine-off owner remains authoritative", not sun.shadow_enabled)
	Settings.apply({shadow_quality = "low"})
	var another := Atmosphere.create_sun(holder)
	check("new worlds use selected tier without resetting allocation", another.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS and Settings.effective().atlas_size == 2048)
	holder.free()
	for cycle in 30:
		var temporary := Node3D.new()
		root.add_child(temporary)
		Atmosphere.create_sun(temporary)
		temporary.free()
	check("unchanged-preference world churn keeps weak registry bounded", Settings._lights.size() <= 1)
	Settings.apply({})
	check("destroyed lights are not retained", Settings._lights.is_empty())
	check("atmosphere spec remains byte-identical", Spec.ATMOSPHERE == original_spec)
	Atmosphere.state = original_state
	Atmosphere.engine_shadows = original_engine
	Settings.apply(previous)
	print("Shadow settings: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
