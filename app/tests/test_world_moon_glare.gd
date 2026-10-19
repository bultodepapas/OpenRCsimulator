# FW-MOON-08: the moon as the eye's glare source. With the sun's disc off, SunGlare.source() returns the moon. Its
# illuminance comes from the disc as drawn and agrees with the engine's moonlight. Its E/B against the live sky is
# below KS91's (conservative) but the same order. It never bleaches the retina. The veil's colour is the CIE veil at
# the limb shown with the disc's γ (below the disc) and kappa is the sky's display level over it. Near the moon a
# model loses contrast, far away it keeps it. Twilight, an eclipse's totality, no moon and halo "off" leave no glare.
# The day keeps the sun's source and SunOptics.KAPPA, and the glare node writes the source's kappa.
# Run: godot --headless --path . --script res://tests/test_world_moon_glare.gd
extends SceneTree

const Conditions := preload("res://render/world/conditions.gd")
const Ephemeris := preload("res://render/world/ephemeris.gd")
const SkyState := preload("res://render/world/sky_state.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const MoonConfig := preload("res://environment/moon_config.gd")
const MoonGlare := preload("res://render/world/moon_glare.gd")
const SunGlare := preload("res://render/landscape_upgrade/sun_glare.gd")
const SunOptics := preload("res://render/sun/sun_optics.gd")
const SkyMirror := preload("res://render/sun/sky_mirror.gd")

## KS91 (PASP 103:1033) constants for the independent E/B: V extinction per airmass, nL and fc in SI, the
## representative dark-site zenith (Crumey 2014; star_limit.py).
const K := 0.2
const NL_TO_CD := 3.183e-6
const LX_PER_FC := 10.764
const DARK_CD := 2.0e-4

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _state(args: Array, config: Dictionary = {}) -> Dictionary:
	return SkyState.state(Ephemeris.sky(Conditions.resolve(PackedStringArray(args)).when), config)


func _source(state: Dictionary) -> Dictionary:
	Atmosphere.state = state
	return SunGlare.source(Atmosphere.sky_material(), Atmosphere.shadow_compensation(), float(state.exposure))


static func _airmass(zenith_deg: float) -> float:
	var s := sin(deg_to_rad(zenith_deg))
	return 1.0 / sqrt(1.0 - 0.96 * s * s)


## KS91's E/B at the moon's own position, without the aureole's forward peak (eqs. 3, 15, 20, 21 at ρ = 0 with the
## aerosol term at its 45° value), against the moonlit plus dark sky.
static func _ks91_e_over_b(moon_elevation_deg: float, phase_deg: float) -> float:
	var z := 90.0 - moon_elevation_deg
	var a := absf(phase_deg)
	var istar := pow(10.0, -0.4 * (3.84 + 0.026 * a + 4e-9 * pow(a, 4.0)))
	var reaching := istar * pow(10.0, -0.4 * K * _airmass(z))
	var f := pow(10.0, 5.36) * 2.06 + pow(10.0, 6.15 - 45.0 / 40.0)
	var x := _airmass(z)
	var b := f * reaching * (1.0 - pow(10.0, -0.4 * K * x)) * NL_TO_CD + DARK_CD * pow(10.0, -0.4 * K * (x - 1.0)) * x
	return reaching * LX_PER_FC / b


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# The Night preset: a 98 % moon 19° up in full darkness.
	var night_args := ["--time_of_day=night"]
	var night := _state(night_args)
	var src := _source(night)
	var mat := Atmosphere.sky_material()
	var moon_dir: Vector3 = mat.get_shader_parameter("moon_dir")
	_check("night: the glare source is the moon", (src.dir as Vector3).is_equal_approx(moon_dir.normalized())
		and float(src.radius) == float(mat.get_shader_parameter("moon_radius")))
	var e_over_b := float(src.e_over_b)
	var phase := float(Ephemeris.sky(Conditions.resolve(PackedStringArray(night_args)).when).moon.phase_angle_deg)
	var ks91 := _ks91_e_over_b(float(night.moon_elevation_deg), phase)
	print("  night preset: E/B %.2f sr (KS91 %.1f), kappa %.3f, illuminance %s of the day sun" % [e_over_b, ks91,
		float(src.kappa), String.num_scientific(float(src.illuminance))])
	_check("night: E/B below KS91's but the same order (the table brightens the sky around a low moon)",
		e_over_b < ks91 and e_over_b > 0.2 * ks91, "%f vs %f" % [e_over_b, ks91])
	# The disc's illuminance against the engine light, which is the moon at night (sky sun_lin, compensation removed).
	var light := SunOptics.luminance((mat.get_shader_parameter("sun_lin") as Vector3) / Atmosphere.shadow_compensation())
	var disc := float(src.illuminance) * SunOptics.day_illuminance()
	_check("night: the disc's illuminance agrees with the moonlight within a factor 1.5 (FW-MOON-03 photometry)",
		disc / light > 0.67 and disc / light < 1.5, str(disc / light))
	# No bleaching: ten seconds staring at the moon.
	var eye := SunOptics.afterimage_rest()
	for i in 100:
		eye = SunOptics.afterimage_step(eye, 0.1, float(src.illuminance), Vector3(0.0, 0.0, -1.0))
	_check("night: the moon never bleaches the retina (10 s stare)", SunOptics.afterimage_dose(eye) < 1e-3,
		str(SunOptics.afterimage_dose(eye)))
	# The veil's colour: the CIE veil at the limb as the disc's γ shows it.
	var gamma := float(mat.get_shader_parameter("moon_display_gamma"))
	var level := MoonGlare.mean_level(mat, moon_dir.normalized())
	var shown_disc := SunOptics.luminance(mat.get_shader_parameter("moon_lin")) * pow(level, gamma) \
		* float(mat.get_shader_parameter("moon_display_scale"))
	var share := MoonGlare.limb_share(float(src.radius))
	_check("the CIE veil at the limb is ~4 % of the disc's radiance", share > 0.03 and share < 0.05, str(share))
	var c: Vector3 = src.disc_lin
	_check("night: the veil is grey (the dark-adapted eye sees the faint glow without colour)", c.x == c.y and c.y == c.z and c.x > 0.0, str(c))
	_check("night: the veil reaches the limb's share of the shown disc (share^γ, ~17 %)",
		absf(SunOptics.luminance(src.disc_lin) / shown_disc - pow(share, gamma)) < 1e-4, "%f vs %f" % [
		SunOptics.luminance(src.disc_lin) / shown_disc, pow(share, gamma)])
	var background := SkyMirror.background_luminance(mat, moon_dir.normalized())
	var exposure := float(night.exposure)
	var display_kappa := MoonGlare.display(background * exposure) / MoonGlare.display(SunOptics.luminance(src.disc_lin) * exposure)
	_check("night: kappa is the sky's display level over the veil colour's (sRGB code values), below 1",
		float(src.kappa) > 0.0 and float(src.kappa) < 1.0 and absf(float(src.kappa) - display_kappa) < 1e-6, "%f vs %f" % [
		float(src.kappa), display_kappa])
	var shader_code: String = (load("res://render/landscape_upgrade/sun_glare.gdshader") as Shader).code
	_check("the glare overlay encodes its colour for the engine (Compatibility linearises ALBEDO)",
		shader_code.contains("engine_srgb.gdshaderinc") and shader_code.contains("ALBEDO = encode_for_engine("))
	# A model near the moon loses contrast; far from it, it keeps it.
	var coeff := SunOptics.aureole_background_coeff(float(night.moon_elevation_deg), Atmosphere.aureole_aerosol_factor())
	var left := []
	for theta: float in [1.0, 2.0, 5.0, 10.0, 20.0, 50.0]:
		left.append(SunOptics.contrast_left(SunOptics.veil_ratio(theta, e_over_b, coeff)))
	print("  contrast left 1° %.2f, 2° %.2f, 5° %.2f, 10° %.2f, 20° %.2f, 50° %.2f" % left)
	_check("night: a model 1° from the moon keeps under 60 % of its contrast", float(left[0]) < 0.6, str(left[0]))
	_check("night: 20° away it keeps over 90 %, and 50° away all of it", float(left[4]) > 0.9 and float(left[5]) == 1.0)
	_check("night: the loss falls off with the angle", left[0] < left[1] and left[1] < left[2] and left[2] < left[3] and left[3] < left[4])
	# A full moon high in the sky veils more.
	var high := _source(_state(["--date=2026-10-25", "--time=23:59"]))
	_check("a high full moon veils more than the low Night preset moon", float(high.e_over_b) > e_over_b, str(high.e_over_b))

	# No glare: twilight, totality, no moon, halo off.
	_check("moonrise in twilight: the bright sky leaves no glare (E/B < 0.05)", float(_source(_state(["--time_of_day=moonrise"])).e_over_b) < 0.05)
	var east := ["--lat=30", "--lon=90", "--utc_offset=0", "--date=2028-12-31"]
	var before := float(_source(_state(east + ["--time=13:30"])).e_over_b)
	var total := float(_source(_state(east + ["--time=16:52"])).e_over_b)
	_check("eclipse: totality leaves 2 % of the glare at most", total < 0.02 * before and before > 1.0, "%f vs %f" % [total, before])
	var off := MoonConfig.defaults()
	off.moon = "off"
	_check("moon off: no glare", float(_source(_state(night_args, off)).e_over_b) == 0.0)
	var no_halo := MoonConfig.defaults()
	no_halo.halo = "off"
	var halo_state := _state(night_args, no_halo)
	_check("halo off: no glare and no aureole", float(_source(halo_state).e_over_b) == 0.0 and halo_state.moon_aureole_lin == Vector3.ZERO
		and night.moon_aureole_lin != Vector3.ZERO)

	# The day keeps the sun.
	var day := _source(_state(["--time_of_day=noon"]))
	var sun_dir: Vector3 = Atmosphere.sky_material().get_shader_parameter("sun_dir")
	_check("day: the source stays the sun, with SunOptics.KAPPA", (day.dir as Vector3).is_equal_approx(sun_dir.normalized())
		and float(day.kappa) == SunOptics.KAPPA and float(day.e_over_b) > 1.0)

	# The glare node toward the Night preset's moon: visible, writes the moon's kappa.
	Atmosphere.state = night
	var env := Environment.new()
	env.sky = Sky.new()
	env.sky.sky_material = Atmosphere.sky_material()
	env.tonemap_exposure = float(night.exposure)
	var camera := Camera3D.new()
	camera.fov = 60.0
	root.add_child(camera)
	camera.current = true
	camera.transform = Transform3D(Basis.looking_at(moon_dir.normalized(), Vector3.UP), Vector3.ZERO)
	var node := SunGlare.attach(root, env)
	await process_frame
	var material := node.material_override as ShaderMaterial
	_check("glare node: the veil shows toward the moon", node.visible and (material.get_shader_parameter("source_dir") as Vector3)
		.is_equal_approx(moon_dir.normalized()), str(node.visible))
	_check("glare node: the material takes the moon's kappa", absf(float(material.get_shader_parameter("kappa")) - float(src.kappa)) < 1e-6,
		str(material.get_shader_parameter("kappa")))
	node.queue_free()
	camera.queue_free()
	Atmosphere.state = {}
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
