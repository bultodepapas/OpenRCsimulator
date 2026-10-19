# FW-MOON-08a: the moon's aureole. Krisciunas & Schaefer's (1991) aerosol scattering, anchored to the sky's own
# moonlit zenith: the coefficient follows their eqs. 19/21; it is zero by day, without a moon and with the moon
# below the horizon; the air's aerosols scale it (visibility, weather haze); flowing skies write it, snapshots clear
# it; the shader's angular shape is continuous and falls off as KS91's, and the eye-adapted brightening stays a
# glow (a few times the sky within 5°, a few percent at 90°).
# Run: godot --headless --path . --script res://tests/test_world_moon_aureole.gd
extends SceneTree

const Conditions := preload("res://render/world/conditions.gd")
const Ephemeris := preload("res://render/world/ephemeris.gd")
const SkyState := preload("res://render/world/sky_state.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const MoonConfig := preload("res://environment/moon_config.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


static func _lum(v: Vector3) -> float:
	return 0.2126 * v.x + 0.7152 * v.y + 0.0722 * v.z


func _state(args: Array, config: Dictionary = {}) -> Dictionary:
	return SkyState.state(Ephemeris.sky(Conditions.resolve(PackedStringArray(args)).when), config)


## KS91 eq. 21 with eq. 19 within 10°, independently written (ρ in degrees).
static func _f_ks91(rho: float) -> float:
	var c := cos(deg_to_rad(rho))
	return pow(10.0, 5.36) * (1.06 + c * c) + (pow(10.0, 6.15 - rho / 40.0) if rho >= 10.0 else 6.2e7 / (rho * rho))


## KS91's aerosol shape relative to 10^6.15 (eq. 19 near the moon, eq. 21 beyond, joined where they meet).
static func _ks91_shape(rho: float) -> float:
	var far := pow(10.0, -rho / 40.0)
	return maxf(6.2e7 / pow(10.0, 6.15) / (rho * rho), far) if rho < 30.0 else far


## The shader's added shape (sky.gdshader moon_aureole): the forward peak above KS91's value at 45°.
static func _shape(rho: float) -> float:
	return _ks91_shape(rho) - pow(10.0, -45.0 / 40.0) if rho < 45.0 else 0.0


func _initialize() -> void:
	# The coefficient: moon_zenith · 10^6.15 / f(Z_moon).
	var z := Vector3(1.0, 2.0, 3.0) * 1e-6
	for el: float in [60.0, 30.0, 85.0]:
		var got := SkyState.moon_aureole(z, el)
		var want := z * pow(10.0, 6.15) / _f_ks91(90.0 - el)
		_check("coefficient follows KS91 at a %d° moon" % el, (got - want).length() < 1e-9 * want.length(), "%s vs %s" % [got, want])

	# Real skies at the reference field.
	var night := _state(["--time_of_day=night"]) # 98 % moon 19° up
	var full_high := _state(["--time=00:00", "--date=2026-12-24"])
	var noon := _state(["--time=14:00", "--date=2026-09-26"])
	var below := _state(["--time=19:30", "--date=2026-09-26"]) # the Harvest Moon still below the horizon
	var off_config := MoonConfig.defaults()
	off_config.moon = "off"
	var off := _state(["--time_of_day=night"], off_config)
	_check("a moonlit night has an aureole", _lum(night.moon_aureole_lin) > 0.0)
	_check("day: no aureole (dropped below the floor), so day skies stay identical", noon.moon_aureole_lin == Vector3.ZERO)
	_check("a moon below the horizon has no aureole", below.moon_aureole_lin == Vector3.ZERO, str(below.moon_elevation_deg))
	_check("no moon, no aureole", off.moon_aureole_lin == Vector3.ZERO)
	_check("a high full moon has an aureole too", _lum(full_high.moon_aureole_lin) > 0.0)

	# Aerosols: the default air, the weather profiles' haze, the clamp.
	var factor := Atmosphere.aureole_aerosol_factor()
	_check("default air: 1.9× KS91's clean-site aerosols", absf(factor - 1.9) < 0.05, str(factor))
	var factors := {}
	for preset: String in ["clear", "classic", "electrical_storm"]:
		Atmosphere.configure_appearance(Atmosphere.SkyConfig.for_preset(preset))
		factors[preset] = Atmosphere.aureole_aerosol_factor()
	Atmosphere.configure_appearance(Atmosphere.SkyConfig.for_preset("classic"))
	_check("hazier weather, brighter aureole", factors.clear < factors.classic and factors.classic < factors.electrical_storm, str(factors))
	_check("the factor stays within [0.25, 4]", factors.electrical_storm <= 4.0 and factors.clear >= 0.25, str(factors))

	# The shader's shape: continuous (the two KS91 forms meet at 8.4°), falling with angle, KS91's forms on each side.
	var monotonic := true
	var worst_jump := 0.0
	var rho := 0.3 # the shader starts at the disc's edge (~0.26°)
	while rho < 180.0:
		var next := rho * 1.005
		monotonic = monotonic and _ks91_shape(next) < _ks91_shape(rho) and _shape(next) <= _shape(rho)
		worst_jump = maxf(worst_jump, absf(log(_ks91_shape(next) / _ks91_shape(rho))))
		rho = next
	_check("the angular shape falls monotonically from the disc to 180°", monotonic)
	_check("no step in the KS91 shape (largest change per 0.5 % of angle under 6 %)", worst_jump < 0.06, "%.4f" % worst_jump)
	_check("near the moon it is KS91 eq. 19, far from it eq. 21", absf(_ks91_shape(2.0) - 6.2e7 / pow(10.0, 6.15) / 4.0) < 1e-12
		and absf(_ks91_shape(40.0) - pow(10.0, -1.0)) < 1e-12)
	_check("only the forward peak is added: nothing from 45° on, continuously", _shape(45.0) == 0.0 and _shape(44.9) < 1e-3
		and _shape(90.0) == 0.0)
	_check("within 10° the added peak is over 85 % of KS91's aerosol term", _shape(10.0) / _ks91_shape(10.0) > 0.85)
	_check("the two forms meet between 8° and 9°", 6.2e7 / pow(10.0, 6.15) / 64.0 > pow(10.0, -0.2) and 6.2e7 / pow(10.0, 6.15) / 81.0 < pow(10.0, -0.225))

	# What the eye sees: the brightening over the sky, for the night preset's moon (γ = its display gamma).
	var gamma: float = night.moon_display_gamma
	var r_zen := _lum(night.moon_aureole_lin) * factor / _lum(night.zenith_lin)
	var at := func(rho: float) -> float:
		var r := r_zen * _shape(rho)
		return pow(1.0 + r, gamma) - 1.0
	_check("night: the eye adapted to the moon (γ < 1)", gamma < 1.0, str(gamma))
	var b1: float = at.call(1.0)
	var b5: float = at.call(5.0)
	var b20: float = at.call(20.0)
	var b90: float = at.call(90.0)
	print("  brightening over the zenith sky (night preset): 1° ×%.1f, 5° ×%.2f, 20° ×%.2f, 90° +%.1f %% (γ %.2f, r_zen %.3f)" % [
		1.0 + b1, 1.0 + b5, 1.0 + b20, 100.0 * b90, gamma, r_zen])
	_check("a glow, not a white blob: under 60× the sky at 1°", b1 < 60.0, str(b1))
	_check("clearly brighter within 5°", b5 > 1.0, str(b5))
	_check("from 45° on the sky is left as it was (no double counting with the table's moonlit sky)", b90 == 0.0, str(b90))

	# Uniforms: flowing skies write it (with the aerosols), snapshots clear it.
	Atmosphere.state = night
	var mat := Atmosphere.sky_material()
	_check("flow sky: the aureole is written with the aerosols", (mat.get_shader_parameter("moon_aureole_lin") as Vector3).is_equal_approx(
		(night.moon_aureole_lin as Vector3) * Atmosphere.aureole_aerosol_factor()))
	Atmosphere.state = {}
	Atmosphere.update_sky_material(mat, Atmosphere.Spec.ATMOSPHERE.duplicate(true))
	_check("snapshot sky: no aureole", mat.get_shader_parameter("moon_aureole_lin") == Vector3.ZERO)
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
