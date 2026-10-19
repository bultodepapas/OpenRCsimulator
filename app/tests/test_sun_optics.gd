# SUN-01…04 (docs/plans/sun.md): the sun's optics held in float64. CIE 146:2002 straylight against hand values and the
# SUN-00 research numbers; the overlay's alpha reproduces the contrast loss 1/(1 + r) exactly at the design point; the
# steady veil over sky and aureole stays in the textbook band (a model 1° from the sun keeps 15–45 % of its contrast),
# and photobleaching is what hides it: a 0.15 s glance marks the eye, a 1 s crossing masks it, 30 s restores it; the
# calibrated day is scale 1; limb darkening
# keeps the disc's mean; refraction flattens a low disc like the moon's; the aureole's KS91 shape is continuous and
# ends at 45°; the afterimage integrates exactly (frame-rate independent), recovers, keeps separate patches and
# ignores pauses and bad input; the CPU cloud mirror's 32-bit hash and decks behave like the shader's.
# Run: godot --headless --path . --script res://tests/test_sun_optics.gd
extends SceneTree

const SunOptics := preload("res://render/sun/sun_optics.gd")
const SkyMirror := preload("res://render/sun/sky_mirror.gd")
const SkyState := preload("res://render/world/sky_state.gd")
const SunGlare := preload("res://render/landscape_upgrade/sun_glare.gd")
const SKY_SHADER := preload("res://render/sky.gdshader")
const Spec := preload("res://spec.gd")
const Atmosphere := preload("res://render/atmosphere.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	_glare_spread()
	_veil_mapping()
	_illuminance()
	_disc()
	_aureole()
	_afterimage()
	_clouds()
	_source()
	print("SUN optics: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _glare_spread() -> void:
	# CIE 146:2002 at age 25, p = 0.5, by hand: 10/θ³ + (5/θ² + 0.05/θ)·1.025600 + 0.00125.
	var age25 := 1.0 + pow(25.0 / 62.5, 4.0)
	for theta: float in [1.0, 3.0, 10.0, 30.0]:
		var by_hand := 10.0 / pow(theta, 3.0) + (5.0 / (theta * theta) + 0.05 / theta) * age25 + 0.00125
		_check("CIE spread at %.0f°" % theta, absf(SunOptics.glare_spread(theta, 25.0, 0.5) - by_hand) < 1e-12)
	# Stiles–Holladay (10/θ², 1°–30°) is the classic approximation: the CIE value stays within a factor of two there.
	for theta: float in [2.0, 5.0, 10.0, 20.0]:
		var ratio := SunOptics.glare_spread(theta, 25.0, 0.5) / (10.0 / (theta * theta))
		_check("CIE near Stiles–Holladay at %.0f°" % theta, ratio > 0.5 and ratio < 2.0, str(ratio))
	_check("older eyes scatter more", SunOptics.glare_spread(5.0, 70.0) > SunOptics.glare_spread(5.0, 25.0))
	# SUN-00 §1.2 (A = 40, p = 0.5): Ψ(1°) = 15.9, Ψ(10°) = 0.0755 sr⁻¹.
	_check("SUN-00 Ψ(1°) at 40", absf(SunOptics.glare_spread(1.0) - 15.9) < 0.05, str(SunOptics.glare_spread(1.0)))
	_check("SUN-00 Ψ(10°) at 40", absf(SunOptics.glare_spread(10.0) - 0.0755) < 0.0005, str(SunOptics.glare_spread(10.0)))
	_check("the equation is clamped to its range", SunOptics.glare_spread(0.0) == SunOptics.glare_spread(0.1)
		and SunOptics.glare_spread(180.0) == SunOptics.glare_spread(100.0))
	_check("no straylight added from the cut out", SunOptics.glare_excess(SunOptics.VEIL_CUT_DEG) == 0.0
		and SunOptics.glare_excess(90.0) == 0.0)
	var previous := INF
	var monotonic := true
	for i in 440:
		var theta := 0.1 + i * 0.1
		var e := SunOptics.glare_excess(theta)
		monotonic = monotonic and e < previous and e >= 0.0
		previous = e
	_check("excess straylight falls monotonically to zero", monotonic)


func _veil_mapping() -> void:
	# Weber contrast after an alpha mix toward a source of display value 1 over a background of display value KAPPA:
	# exactly 1/(1 + r) of the original.
	var background := SunOptics.KAPPA
	var target := 0.1 * background # a dark silhouette
	for r: float in [0.0, 0.2, 1.0, 5.0, 40.0]:
		var a := SunOptics.veil_alpha(r)
		var b := background * (1.0 - a) + a
		var t := target * (1.0 - a) + a
		var shown := (t - b) / b
		var original := (target - background) / background
		_check("contrast mapping exact at r=%s" % r, absf(shown / original - SunOptics.contrast_left(r)) < 1e-12)
	_check("alpha stays below 1", SunOptics.veil_alpha(1e9) < 1.0 and SunOptics.veil_alpha(-3.0) == 0.0)
	# The steady veil over sky and aureole for the calibrated day sky (E/B from the live material; 45° sun, default 23 km
	# air): the textbook band of SUN-00 §1.4 (0.16 / 0.30 / 0.44 at 1° / 5° / 10° with KS91's clean air), within its
	# 2–4× uncertainty.
	Atmosphere.state = {}
	var day := SunGlare.source(Atmosphere.sky_material(), Atmosphere.shadow_compensation())
	var e_over_b := float(day.e_over_b)
	_check("the calibrated day's E/B is a clear sky's (7–16 sr)", e_over_b > 7.0 and e_over_b < 16.0, str(e_over_b))
	var coeff := SunOptics.aureole_background_coeff(45.0, Atmosphere.aureole_aerosol_factor())
	var at1 := SunOptics.contrast_left(SunOptics.veil_ratio(1.0, e_over_b, coeff))
	var at5 := SunOptics.contrast_left(SunOptics.veil_ratio(5.0, e_over_b, coeff))
	var at10 := SunOptics.contrast_left(SunOptics.veil_ratio(10.0, e_over_b, coeff))
	_check("1° from the sun the veil leaves 15–45 %", at1 > 0.15 and at1 < 0.45, str(at1))
	_check("5° from the sun the veil leaves 30–70 %", at5 > 0.30 and at5 < 0.70, str(at5))
	_check("10° from the sun the veil leaves 40–85 %", at10 > 0.40 and at10 < 0.85, str(at10))
	_check("contrast recovers away from the sun", at1 < at5 and at5 < at10)
	_check("sky-only background veils more than sky plus aureole", SunOptics.veil_ratio(2.0, e_over_b) > SunOptics.veil_ratio(2.0, e_over_b, coeff))
	_check("a low sun against a bright horizon veils less", SunOptics.veil_ratio(5.0, 1.5, coeff) < SunOptics.veil_ratio(5.0, e_over_b, coeff))
	_check("the aureole background ends at 45°", SunOptics.aureole_background(45.0, coeff) == 0.0
		and SunOptics.aureole_background(44.999, coeff) < 1e-4 * SunOptics.aureole_background(10.0, coeff))
	# The aureole behind the model is sky light: halving the straylight (strength, or a model covering half the disc)
	# with the background unchanged halves the veil ratio exactly.
	_check("strength and occlusion scale the straylight, not the background",
		absf(SunOptics.veil_ratio(1.0, 0.5 * e_over_b, coeff, e_over_b) - 0.5 * SunOptics.veil_ratio(1.0, e_over_b, coeff, e_over_b)) < 1e-12)
	_check("bad E/B veils nothing", SunOptics.veil_ratio(2.0, NAN, coeff) == 0.0 and SunOptics.veil_ratio(2.0, -3.0, coeff) == 0.0)


func _illuminance() -> void:
	var a: Dictionary = Spec.ATMOSPHERE
	var c: Color = (a.sun_color as Color).srgb_to_linear()
	var sun_lin := Vector3(c.r, c.g, c.b) * float(a.sun_energy) * PI
	_check("the calibrated day sun is illuminance 1", absf(SunOptics.illuminance_scale(sun_lin) - 1.0) < 1e-12)
	_check("illuminance is absolute (no exposure)", absf(SunOptics.illuminance_scale(sun_lin * 0.1) - 0.1) < 1e-6) # Vector3 is float32
	_check("bad input gives no light", SunOptics.illuminance_scale(Vector3(NAN, 0, 0)) == 0.0
		and SunOptics.illuminance_scale(-sun_lin) == 0.0 and SunOptics.illuminance_over_background(sun_lin, 0.0) == 0.0)


func _disc() -> void:
	# The limb law's area mean by midpoint integration over r (μ = √(1 − r²), weight 2r dr).
	var total := 0.0
	var n := 20000
	for i in n:
		var r := (i + 0.5) / n
		total += SunOptics.limb(sqrt(1.0 - r * r)) * 2.0 * r / n
	_check("limb mean is 1 − u/3 − v/2", absf(total - SunOptics.limb_mean()) < 1e-6, str(total))
	_check("the limb is darker than the centre", SunOptics.limb(0.0) < 0.5 * SunOptics.limb(1.0))
	# SUN-00 §3.2: I(μ = 0.5)/I(1) = 0.703 (power law at 550 nm); the quadratic law gives 0.7075.
	_check("limb at μ = 0.5 near 0.70", absf(SunOptics.limb(0.5) / SunOptics.limb(1.0) - 0.703) < 0.01)
	_check("no flattening high up", SunOptics.squash(45.0) > 0.999)
	var horizon := SunOptics.squash(0.5)
	_check("a setting disc is flattened like the moon's (~0.85)", horizon > 0.80 and horizon < 0.90, str(horizon))
	_check("flattening grows toward the horizon", SunOptics.squash(0.5) < SunOptics.squash(3.0) and SunOptics.squash(3.0) < SunOptics.squash(10.0))
	# The moon's law takes the true elevation: at 2° apparent (flattening ≈ 7 %) they agree to 0.2 %.
	var apparent := 2.0
	var true_el := apparent - preload("res://render/world/ephemeris.gd").refraction_deg(apparent - 0.25)
	_check("the same law as the moon's", absf(SunOptics.squash(apparent) - SkyState.moon_squash(true_el)) < 2e-3
		and SunOptics.squash(apparent) < 0.95)
	_check("non-finite elevation leaves the disc round", SunOptics.squash(NAN) == 1.0)


func _aureole() -> void:
	_check("aureole off with the disc", SunOptics.aureole_lin(Vector3.ONE, 1.9, 0.0) == Vector3.ZERO)
	_check("aureole scales with the sun", SunOptics.aureole_lin(Vector3.ONE * 2.0, 1.0, 1.0).is_equal_approx(SunOptics.aureole_lin(Vector3.ONE, 1.0, 1.0) * 2.0))
	_check("aureole ends at 45°", SunOptics.aureole_shape(45.0) == 0.0 and absf(SunOptics.aureole_shape(44.999)) < 1e-4)
	_check("aureole flat in its core", SunOptics.aureole_shape(0.2) == SunOptics.aureole_shape(1.0))
	_check("aureole continuous at 30°", absf(SunOptics.aureole_shape(29.9999) - SunOptics.aureole_shape(30.0001)) < 1e-4)
	_check("more path near the horizon", SunOptics.aureole_path(2.0) > SunOptics.aureole_path(45.0))
	# KS91 by hand: B/E at 1° from a 45° sun ≈ 6.2·10⁷ · (1 − 10^(−0.08·√2-ish airmass)) · 2.957·10⁻⁷ ≈ 4 sr⁻¹.
	var b_over_e := SunOptics.aureole_lin(Vector3.ONE, 1.0, 1.0).x * SunOptics.aureole_shape(1.0) * SunOptics.aureole_path(45.0)
	_check("aureole B/E near 4 sr⁻¹ at 1°", b_over_e > 3.0 and b_over_e < 5.0, str(b_over_e))


func _afterimage() -> void:
	var rest := SunOptics.afterimage_rest()
	var ahead := Vector3(0.0, 0.0, -1.0)
	# Exact integration: one 1.5 s step equals 45, 90 or 216 small steps.
	var one := SunOptics.afterimage_step(rest, 1.5, 1.0, ahead)
	for steps: int in [45, 90, 216]:
		var s := rest
		for i in steps:
			s = SunOptics.afterimage_step(s, 1.5 / steps, 1.0, ahead)
		_check("afterimage independent of %d frames" % steps, absf(SunOptics.afterimage_dose(s) - SunOptics.afterimage_dose(one)) < 1e-12)
	var k := 1.0 / SunOptics.AFTER_BLEACH_S + 1.0 / SunOptics.AFTER_RECOVER_S
	var expected := (1.0 / SunOptics.AFTER_BLEACH_S) / k * (1.0 - exp(-k * 1.5))
	_check("afterimage dose by hand", absf(SunOptics.afterimage_dose(one) - expected) < 1e-12)
	var later := SunOptics.afterimage_step(one, SunOptics.AFTER_RECOVER_S * log(2.0), 0.0, ahead)
	_check("afterimage halves in RECOVER·ln2", absf(SunOptics.afterimage_dose(later) * 2.0 - SunOptics.afterimage_dose(one)) < 1e-12)
	_check("a pause holds it", SunOptics.afterimage_step(one, 0.0, 1.0, ahead) == one)
	_check("a backward step holds it", SunOptics.afterimage_step(one, -1.0, 1.0, ahead) == one)
	_check("NaN light adds nothing", SunOptics.afterimage_dose(SunOptics.afterimage_step(one, 1.0, NAN, ahead)) < SunOptics.afterimage_dose(one))
	# Cells: a glance 1° away feeds the same cell; 30° away starts another; a sweep leaves a streak; at most 8 cells.
	var near := SunOptics.afterimage_step(one, 0.5, 1.0, Vector3(sin(deg_to_rad(1.0)), 0.0, -cos(deg_to_rad(1.0))))
	_check("a nearby exposure feeds the same cell", (near.patches as Array).size() == 1
		and float(near.patches[0].dose) > 0.9)
	var far := SunOptics.afterimage_step(one, 0.5, 1.0, Vector3(sin(deg_to_rad(30.0)), 0.0, -cos(deg_to_rad(30.0))))
	_check("a distant exposure starts its own cell", (far.patches as Array).size() == 2
		and (far.patches[0].dir as Vector3).is_equal_approx(ahead))
	var sweep := rest
	for i in 41: # 8° in 1.33 s, the crossing capture's sweep
		var angle := deg_to_rad(-4.0 + 8.0 * i / 40.0)
		sweep = SunOptics.afterimage_step(sweep, 1.0 / 30.0, 1.0, Vector3(sin(angle), 0.0, -cos(angle)))
	var centre := 0.0
	for patch: Dictionary in sweep.patches:
		if (patch.dir as Vector3).angle_to(ahead) < SunOptics.AFTER_BASE_RADIUS:
			centre = maxf(centre, float(patch.dose))
	_check("a sweep bleaches a streak through the centre", (sweep.patches as Array).size() >= 5 and centre > 0.8, str(centre))
	var many := rest
	for i in 12:
		many = SunOptics.afterimage_step(many, 0.3, 1.0, Vector3(sin(i * 0.4), 0.0, -cos(i * 0.4)))
	_check("at most AFTER_PATCHES cells", (many.patches as Array).size() == SunOptics.AFTER_PATCHES)
	var alphas := SunOptics.afterimage_alphas(one)
	_check("alphas padded and bounded", alphas.size() == SunOptics.AFTER_PATCHES and alphas[0] > 0.0
		and alphas[0] <= SunOptics.AFTER_MAX_ALPHA and alphas[1] == 0.0)
	var faded := SunOptics.afterimage_step(one, 200.0, 0.0, ahead)
	_check("a recovered patch is dropped", (faded.patches as Array).is_empty())
	# SUN-00 §2: a 0.15 s glance at the sun leaves an afterimage; a one-second crossing masks the view; 30 s restores it.
	var glance := SunOptics.afterimage_step(rest, 0.15, 1.0, ahead)
	_check("a 0.15 s glance marks the eye", SunOptics.afterimage_alphas(glance)[0] > 0.25, str(SunOptics.afterimage_alphas(glance)[0]))
	var crossing := SunOptics.afterimage_step(rest, 1.0, 1.0, ahead)
	_check("a 1 s crossing masks the view", SunOptics.afterimage_alphas(crossing)[0] > 0.75, str(SunOptics.afterimage_alphas(crossing)[0]))
	var recovered := SunOptics.afterimage_step(crossing, 30.0, 0.0, ahead)
	_check("30 s restores it", SunOptics.afterimage_alphas(recovered)[0] < 0.05)
	var sunset := SunOptics.afterimage_step(rest, 0.15, 0.2, ahead)
	_check("a dim sun marks less", SunOptics.afterimage_dose(sunset) < SunOptics.afterimage_dose(glance))
	_check("the eye's field: full ahead, none behind", SunOptics.field_weight(0.0) == 1.0 and SunOptics.field_weight(PI / 2.0) == 0.0)
	# A patch is "lit" (blur only, no dark tint) while the sun's image is on it, and only while the sun gives light.
	_check("lit while the sun is on the patch", SunOptics.afterimage_lit(ahead, 0.02, ahead, 1.0) == 1.0)
	_check("dark once the sun has moved away", SunOptics.afterimage_lit(ahead, 0.02, Vector3(0.1, 0.0, -1.0).normalized(), 1.0) == 0.0)
	_check("dark when the sun is hidden", SunOptics.afterimage_lit(ahead, 0.02, ahead, 0.0) == 0.0)
	# Screen placement: the vertical half-field for keep-height and keep-width cameras.
	_check("keep-height tan(fov/2)", absf(SunOptics.view_tan_half_height(60.0, false, 16.0 / 9.0) - tan(deg_to_rad(30.0))) < 1e-9)
	_check("keep-width divides by the aspect", absf(SunOptics.view_tan_half_height(60.0, true, 2.0) - tan(deg_to_rad(30.0)) / 2.0) < 1e-9)


func _clouds() -> void:
	_check("mul32 wraps like uint", SkyMirror.mul32(0xFFFFFFFF, 0xFFFFFFFF) == 1
		and SkyMirror.mul32(3812015801, 1597334677) == (3812015801 * 1597334677) % 4294967296)
	var h := SkyMirror.hash2(3, 7, 1)
	_check("hash in [0, 1) and repeatable", h >= 0.0 and h < 1.0 and h == SkyMirror.hash2(3, 7, 1) and h != SkyMirror.hash2(7, 3, 1))
	var cells := Vector2(12.3, 40.7)
	_check("deck noise periodic in 64 cells", absf(SkyMirror.fbm(cells, 1, Vector2.ONE) - SkyMirror.fbm(cells + Vector2(64.0, -64.0), 1, Vector2.ONE)) < 1e-5) # Vector2 is float32
	var sky := ShaderMaterial.new()
	sky.shader = SKY_SHADER
	var up := Vector3(0.2, 0.9, -0.3).normalized()
	sky.set_shader_parameter("cloud_coverage", 0.0)
	_check("a clear sky transmits the disc", SkyMirror.transmission(sky, up) == 1.0)
	sky.set_shader_parameter("cloud_coverage", 1.0)
	_check("overcast hides the disc", SkyMirror.transmission(sky, up) < 0.01, str(SkyMirror.transmission(sky, up)))
	_check("below the horizon the deck is not in the way", SkyMirror.transmission(sky, Vector3(0.0, -0.1, -1.0).normalized()) == 1.0)
	sky.set_shader_parameter("cloud_coverage", 0.5)
	var cleared := 0
	for i in 64:
		var d := Vector3(cos(i * 0.37), 0.6, sin(i * 0.37)).normalized()
		if SkyMirror.transmission(sky, d) > 0.99:
			cleared += 1
	_check("half cover leaves gaps and clouds", cleared > 8 and cleared < 56, str(cleared))
	sky.set_shader_parameter("layered_appearance", true)
	sky.set_shader_parameter("appearance_layer_count", 0)
	_check("layered with no decks is clear", SkyMirror.transmission(sky, up) == 1.0)
	sky.set_shader_parameter("appearance_layer_count", 1)
	sky.set_shader_parameter("appearance_layer_parameters", PackedVector4Array([Vector4(1500.0, 250.0, 1.0, 1.0)]))
	sky.set_shader_parameter("appearance_layer_motion", PackedVector4Array([Vector4(0.0, 0.0, 0.0, 3.0)]))
	sky.set_shader_parameter("appearance_layer_seeds", PackedInt32Array([5]))
	_check("a layered stratus ceiling hides the disc (the LU-04 gap)", SkyMirror.transmission(sky, up) < 0.01, str(SkyMirror.transmission(sky, up)))
	_check("no sky material, no clouds", SkyMirror.transmission(null, up) == 1.0)


func _source() -> void:
	var sky := ShaderMaterial.new()
	sky.shader = SKY_SHADER
	var a: Dictionary = Spec.ATMOSPHERE
	var c: Color = (a.sun_color as Color).srgb_to_linear()
	sky.set_shader_parameter("sun_lin", Vector3(c.r, c.g, c.b) * PI)
	sky.set_shader_parameter("sun_dir", Vector3(0.0, 0.7071, -0.7071))
	sky.set_shader_parameter("sun_disc", 1.0)
	var src: Dictionary = SunGlare.source(sky)
	_check("the glare source is the calibrated day sun", absf(float(src.illuminance) - 1.0) < 1e-6 and (src.dir as Vector3).is_normalized()
		and float(src.e_over_b) > 0.0)
	sky.set_shader_parameter("sun_disc", 0.0)
	_check("no glare when the light is the moon", float(SunGlare.source(sky).e_over_b) == 0.0 and float(SunGlare.source(sky).illuminance) == 0.0)
	# The sky mirror against hand values: straight up, the gradient is exactly the zenith.
	sky.set_shader_parameter("zenith_lin", Vector3(0.1, 0.2, 0.3))
	_check("background straight up is the zenith", absf(SkyMirror.background_luminance(sky, Vector3.UP) - SunOptics.luminance(Vector3(0.1, 0.2, 0.3))) < 1e-6)
	# FW evening: E/B falls with the sun (the bright horizon), the bleaching illuminance stays high to ~15°.
	var when := {year = 2026, month = 6, day = 21, utc_offset_h = 2.0, latitude_deg = 40.0, longitude_deg = -3.7}
	var previous := INF
	var falls := true
	for hour: float in [17.0, 19.0, 20.5, 21.4]:
		when.hour = hour
		Atmosphere.state = SkyState.state(preload("res://render/world/ephemeris.gd").sky(when))
		var evening: Dictionary = SunGlare.source(Atmosphere.sky_material(), Atmosphere.shadow_compensation())
		falls = falls and float(evening.e_over_b) < previous
		previous = float(evening.e_over_b)
	_check("E/B falls toward sunset", falls, str(previous))
	_check("a setting sun can be looked at (E/B < 1)", previous < 1.0, str(previous))
	# The veil's target colour: never below the sky around the source, per channel; the disc's own when the sky is dim.
	var disc_lin := Vector3(3.4, 2.8, 2.3)
	_check("a dim sky leaves the disc's colour", SunOptics.veil_colour(disc_lin, Vector3(0.2, 0.25, 0.35)) == disc_lin)
	var bright_sky := Vector3(1.0, 0.95, 2.4)
	var raised := SunOptics.veil_colour(disc_lin, bright_sky)
	_check("a bright channel raises the veil colour, never lowers it", raised.z > disc_lin.z and raised.x == disc_lin.x
		and raised.z >= bright_sky.z)
	_check("bad sky leaves the disc's colour", SunOptics.veil_colour(disc_lin, Vector3(NAN, 0.0, 0.0)) == disc_lin)
	# sky.gdshader's aureole and halo mirrors: zero without an aureole, below the disc's share, faded at the horizon.
	var sun_lin := disc_lin / SunOptics.DISC_RADIANCE_FACTOR
	var a_lin := SunOptics.aureole_lin(sun_lin, 1.9, 1.0)
	var core := SunOptics.sky_aureole(a_lin, sun_lin, 1.0, 45.0)
	_check("the aureole core stays under its share of the disc", SunOptics.luminance(core) > 0.0
		and SunOptics.luminance(core) < SunOptics.AUREOLE_DISC_SHARE * SunOptics.luminance(disc_lin))
	_check("no aureole without its uniform", SunOptics.sky_aureole(Vector3.ZERO, sun_lin, 1.0, 45.0) == Vector3.ZERO)
	_check("the aureole fades out at the horizon", SunOptics.sky_aureole(a_lin, sun_lin, 1.0, 0.0) == Vector3.ZERO
		and SunOptics.luminance(SunOptics.sky_aureole(a_lin, sun_lin, 1.0, 1.0)) < SunOptics.luminance(SunOptics.sky_aureole(a_lin, sun_lin, 1.0, 3.0)))
	_check("the L1a halo falls with angle", SunOptics.luminance(SunOptics.sky_halo(sun_lin, 1.0)) > SunOptics.luminance(SunOptics.sky_halo(sun_lin, 5.0)))
	Atmosphere.state = {} # the calibrated day
	var mirror_sky := Atmosphere.sky_material()
	var probe_dir := Vector3(0.3, 0.6, -0.5).normalized()
	_check("background radiance and luminance agree", absf(SunOptics.luminance(SkyMirror.background_radiance(mirror_sky, probe_dir))
		- SkyMirror.background_luminance(mirror_sky, probe_dir)) < 1e-6)
	var day_src := SunGlare.source(mirror_sky, Atmosphere.shadow_compensation())
	_check("the calibrated day's veil colour is the disc's", (day_src.veil_lin as Vector3).is_equal_approx(day_src.disc_lin))
	# Atmosphere._set_sun_uniforms: golden hour flattens a little and has an aureole; a moonlit night has none.
	when.hour = 20.9
	Atmosphere.state = SkyState.state(preload("res://render/world/ephemeris.gd").sky(when))
	var golden := Atmosphere.sky_material()
	_check("golden hour: limb on, slight flattening, an aureole", float(golden.get_shader_parameter("sun_limb")) == 1.0
		and float(golden.get_shader_parameter("sun_squash")) < 1.0 and (golden.get_shader_parameter("sun_aureole_lin") as Vector3).x > 0.0)
	when.hour = 23.5
	when.day = 29
	Atmosphere.state = SkyState.state(preload("res://render/world/ephemeris.gd").sky(when))
	var night := Atmosphere.sky_material()
	_check("no sun aureole when the moon lights", Atmosphere.state.light_source == "moon"
		and (night.get_shader_parameter("sun_aureole_lin") as Vector3) == Vector3.ZERO, str(Atmosphere.state.light_source))
	Atmosphere.state = {}
	var calibrated := Atmosphere.sky_material()
	_check("the calibrated day: round disc, limb on, an aureole", float(calibrated.get_shader_parameter("sun_squash")) > 0.999
		and (calibrated.get_shader_parameter("sun_aureole_lin") as Vector3).x > 0.0)
	# The shaders' copies of SunOptics constants.
	var sky_code := FileAccess.get_file_as_string("res://render/sky.gdshader")
	_check("sky.gdshader limb law is SunOptics'", sky_code.contains("SUN_LIMB_U = %s;" % SunOptics.LIMB_U)
		and sky_code.contains("SUN_LIMB_V = %s;" % SunOptics.LIMB_V))
	_check("sky.gdshader aureole share is SunOptics'", sky_code.contains("%s * (4.0 / PI) * dot(sun_lin" % SunOptics.AUREOLE_DISC_SHARE))
	var glare_code := FileAccess.get_file_as_string("res://render/landscape_upgrade/sun_glare.gdshader")
	_check("sun_glare.gdshader 45° aureole value", glare_code.contains("%.1f" % pow(10.0, 6.15 - 45.0 / 40.0)))
	var camera := Camera3D.new()
	camera.fov = 40.0
	_check("veil reaches a view facing the sun", SunGlare.veil_reaches_view(camera, Vector3(0.0, 0.0, -1.0)))
	_check("no veil for a sun behind the camera", not SunGlare.veil_reaches_view(camera, Vector3(0.0, 0.0, 1.0)))
	camera.free()
