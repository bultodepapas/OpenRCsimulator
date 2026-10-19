# FW-MOON-06: the light through twilight, step by step (30 s of sky, as World.flow_to). The setting sun's apparent
# elevation never drops more than its own pace (continuous refraction); the sun's shadows fade as its disc crosses
# the horizon, so the light passes between sun and moon with no shadow on either side; the sky's cloud lighting and
# horizon lobes take both sources, so nothing in the sky flips when the brighter source changes; flowing steps drive
# the engine shadows' switch and opacity, while the calibrated day and explicit snapshots keep full opacity.
# Run: godot --headless --path . --script res://tests/test_world_moon_light.gd
extends SceneTree

const Conditions := preload("res://render/world/conditions.gd")
const Ephemeris := preload("res://render/world/ephemeris.gd")
const SkyState := preload("res://render/world/sky_state.gd")
const Atmosphere := preload("res://render/atmosphere.gd")

const STEP_H := 30.0 / 3600.0
## [date, start time, hours] at the reference field: the Moonrise preset's evening (sun and moon opposite), a waxing
## crescent after sunset (same side) and a gibbous moon setting while the sun rises (the light handed back).
const EVENINGS := {
	harvest = ["2026-09-26", "19:00", 3.0],
	crescent = ["2026-06-18", "21:00", 3.0],
	dawn = ["2026-10-29", "06:00", 3.0],
}

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


## The sky shader's lobe term on the horizon toward `azimuth_deg` (sky.gdshader lobe_term at d.y = 0), both lobes.
static func _horizon_lobes(st: Dictionary, azimuth_deg: float) -> float:
	var d := SkyState.direction(azimuth_deg, 0.0)
	var total := 0.0
	for lobe: Array in [[st.lobe_lin, st.lobe_dir, st.lobe_k], [st.sky_lobe2_lin, st.sky_lobe2_dir, st.sky_lobe2_k]]:
		var dir: Vector3 = lobe[1]
		var az := maxf(Vector2(d.x, d.z).normalized().dot(Vector2(dir.x, dir.z).normalized()), 0.0)
		var lin: Vector3 = lobe[0]
		total += (0.2126 * lin.x + 0.7152 * lin.y + 0.0722 * lin.z) * pow(az, float(lobe[2]))
	return total


## The clouds' directional shading as the shader weights it: the light's direction and the second source's.
static func _cloud_light(st: Dictionary) -> Vector3:
	return (st.light_dir as Vector3) * float(st.cloud_light1_weight) + (st.cloud_light2_dir as Vector3) * float(st.cloud_light2_weight)


func _evening(id: String) -> void:
	var e: Array = EVENINGS[id]
	var c := Conditions.resolve(PackedStringArray(["--date=" + str(e[0]), "--time=" + str(e[1])]))
	var previous := {}
	var swaps := 0
	var worst_drop := 0.0
	var worst_shadow := 0.0
	var worst_cloud := 0.0
	var worst_lobe := 0.0
	var swap_shadow := 0.0
	var sun_az := 0.0
	for k in int(float(e[2]) / STEP_H) + 1:
		var when: Dictionary = c.when.duplicate()
		when.hour = float(when.hour) + k * STEP_H
		var sky := Ephemeris.sky(when)
		var st := SkyState.state(sky)
		if not previous.is_empty():
			worst_drop = maxf(worst_drop, absf(float(previous.sun_elevation_deg) - float(st.sun_elevation_deg)))
			worst_shadow = maxf(worst_shadow, absf(float(previous.shadow_strength) - float(st.shadow_strength)))
			worst_cloud = maxf(worst_cloud, (_cloud_light(previous) - _cloud_light(st)).length())
			var a := _horizon_lobes(previous, sun_az)
			var b := _horizon_lobes(st, float(sky.sun.azimuth_deg))
			var haze: Vector3 = previous.haze_lin
			if a > 0.05 * (0.2126 * haze.x + 0.7152 * haze.y + 0.0722 * haze.z): # a glow that shows against the haze
				worst_lobe = maxf(worst_lobe, 1.0 - b / a)
			if previous.light_source != st.light_source:
				swaps += 1
				swap_shadow = maxf(swap_shadow, maxf(float(previous.shadow_strength), float(st.shadow_strength)))
		previous = st
		sun_az = float(sky.sun.azimuth_deg)
	_check("%s: the light changes source once" % id, swaps == 1, str(swaps))
	_check("%s: the sun's apparent elevation never jumps (≤ 0.15° per step)" % id, worst_drop <= 0.15, "%.3f°" % worst_drop)
	_check("%s: shadows hand over with ≤ 0.1 strength on either side" % id, swap_shadow <= 0.1, "%.3f" % swap_shadow)
	_check("%s: shadow strength moves ≤ 0.15 per step" % id, worst_shadow <= 0.15, "%.3f" % worst_shadow)
	# A flip between opposite sources moves this vector by about twice the weight (≥ 1 at twilight); the sky table's
	# own fall of sunlight off the deck moves it ≤ 0.2 per step.
	_check("%s: the clouds' directional shading moves ≤ 0.25 per step" % id, worst_cloud <= 0.25, "%.4f" % worst_cloud)
	_check("%s: the sun-side horizon glow never loses more than 40 %% in one step" % id, worst_lobe <= 0.4, "%.3f" % worst_lobe)


func _initialize() -> void:
	# 06a: refraction keeps Saemundsson above −1° and reaches zero at −3° continuously.
	_check("refraction unchanged above −1°", is_equal_approx(Ephemeris.refraction_deg(0.0),
		1.02 / tan(deg_to_rad(10.3 / 5.11)) / 60.0))
	_check("no refraction at −3°", Ephemeris.refraction_deg(-3.0) == 0.0)

	# 06b: the sun's shadow strength across the horizon.
	_check("sun shadows full from 0.5° up", SkyState.sun_shadow_strength(0.5) == 1.0 and SkyState.sun_shadow_strength(6.0) == 1.0
		and SkyState.sun_shadow_strength(45.0) == 1.0)
	var at_horizon := SkyState.sun_shadow_strength(0.0)
	_check("sun shadows partial with the disc on the horizon", at_horizon > 0.2 and at_horizon < 0.8, str(at_horizon))
	_check("no sun shadows once the beam is gone", SkyState.sun_shadow_strength(-0.5) == 0.0 and SkyState.sun_shadow_strength(-10.0) == 0.0)
	var monotonic := true
	for i in 40:
		monotonic = monotonic and SkyState.sun_shadow_strength(-1.0 + 0.05 * (i + 1)) >= SkyState.sun_shadow_strength(-1.0 + 0.05 * i)
	_check("sun shadow strength rises monotonically through the horizon", monotonic)

	for id: String in EVENINGS:
		_evening(id)

	# The day sky gets nothing from the moon's second light.
	var noon := SkyState.state(Ephemeris.sky(Conditions.resolve(PackedStringArray(["--date=2026-09-26", "--time=14:00"])).when))
	_check("day: full sun shadows, clouds shaded by the sun alone, exactly", float(noon.shadow_strength) == 1.0
		and float(noon.cloud_light1_weight) == 1.0 and float(noon.cloud_light2_weight) == 0.0, "%s %s" % [noon.cloud_light1_weight, noon.cloud_light2_weight])
	for hm: String in ["06:00", "19:30", "20:00"]: # high summer noon, golden hour and sunset (the disc still up) on 2026-06-21
		var st := SkyState.state(Ephemeris.sky(Conditions.resolve(PackedStringArray(["--date=2026-06-21", "--time=" + hm])).when))
		if float(st.sun_elevation_deg) >= SkyState.SUN_SHADOW_FULL_DEG:
			_check("sun up at %s: clouds and shadows exactly as before" % hm, float(st.cloud_light1_weight) == 1.0
				and float(st.cloud_light2_weight) == 0.0 and float(st.shadow_strength) == 1.0, str(st.sun_elevation_deg))

	# Engine shadows: flow steps apply the switch and the opacity; the calibrated day and snapshots keep full opacity.
	var engine := Atmosphere.engine_shadows
	Atmosphere.engine_shadows = true
	var light := DirectionalLight3D.new()
	var dusk := SkyState.state(Ephemeris.sky(Conditions.resolve(PackedStringArray(["--date=2026-09-26", "--time=20:05"])).when))
	Atmosphere.state = dusk
	Atmosphere.apply_light(light)
	_check("flow step: engine shadow opacity is the strength", is_equal_approx(light.shadow_opacity, float(dusk.shadow_strength))
		and light.shadow_enabled == (float(dusk.shadow_strength) > 0.0), "%f / %f" % [light.shadow_opacity, dusk.shadow_strength])
	var night := SkyState.state(Ephemeris.sky(Conditions.resolve(PackedStringArray(["--date=2026-09-26", "--time=20:40"])).when))
	Atmosphere.state = night
	Atmosphere.apply_light(light)
	_check("flow step: a moon too low for shadows switches the engine shadows off", not light.shadow_enabled
		and float(night.shadow_strength) == 0.0, str(night.shadow_strength))
	Atmosphere.state = {}
	Atmosphere.update_sun(light)
	_check("calibrated day: full engine shadows", light.shadow_enabled and light.shadow_opacity == 1.0)
	var snapshot: Dictionary = Atmosphere.Spec.ATMOSPHERE.duplicate(true)
	snapshot.shadow_strength = 0.4
	Atmosphere.update_sun(light, snapshot)
	_check("explicit snapshot: switch only, full opacity", light.shadow_enabled and light.shadow_opacity == 1.0)
	light.free()
	Atmosphere.engine_shadows = engine

	# Sky uniforms: the flow state writes the second lobe and cloud light; a snapshot clears them.
	Atmosphere.state = night
	var mat := Atmosphere.sky_material()
	_check("flow sky: second lobe and cloud light written", mat.get_shader_parameter("lobe2_lin") == night.sky_lobe2_lin
		and float(mat.get_shader_parameter("light1_weight")) == float(night.cloud_light1_weight)
		and float(mat.get_shader_parameter("light2_weight")) == float(night.cloud_light2_weight))
	Atmosphere.state = {}
	Atmosphere.update_sky_material(mat, snapshot)
	_check("snapshot sky: the twilight terms are cleared", mat.get_shader_parameter("lobe2_lin") == Vector3.ZERO
		and float(mat.get_shader_parameter("light1_weight")) == 1.0 and float(mat.get_shader_parameter("light2_weight")) == 0.0)
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
