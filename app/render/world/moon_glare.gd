## FW-MOON-08: the moon as the eye's glare source. SunGlare.source() returns this while the sun's disc is off, and the
## pilot view draws the same CIE 146 veil as for the sun (render/sun/sun_optics.gd, sun_glare.gdshader).
## Its illuminance comes from the disc as drawn, read from the live sky: E = mean radiance × solid angle, the mean
## being moon_lin × phase flux × eclipse dimming (FW-MOON-03, -10). E/B is taken against the sky around the moon, as
## for the sun. E is ~10⁻⁶ of the day sun's, so the moon veils a dark-adapted view but never bleaches the retina.
## The veil mixes toward the level it reaches at the limb as the eye-adapted display shows it, in grey (the dark-adapted
## eye sees the faint glow without colour). CIE straylight there is limb_share() ≈ 4 % of the disc's radiance; the
## disc's own γ shows that at ~17 % of the displayed disc at night, so the glow stays below the disc. `kappa`, the background's display level over that colour, has the meaning of
## SunOptics.KAPPA but comes from the live sky and exposure: the overlay blends in sRGB code values, so both are
## encoded (the engine's sRGB curve; AgX's toe is not mirrored, which keeps kappa within ~10 % at night).
## MoonConfig halo "off" removes it, with the aureole.
extends RefCounted

const SkyState := preload("res://render/world/sky_state.gd")
const SunOptics := preload("res://render/sun/sun_optics.gd")
const SkyMirror := preload("res://render/sun/sky_mirror.gd")
const Atmosphere := preload("res://render/atmosphere.gd")


## {dir, radius, disc_lin, illuminance, e_over_b, kappa}, the keys of SunGlare.source(); zeros without a moon.
## `exposure`: the environment's tonemap exposure, for kappa.
static func source(sky: ShaderMaterial, exposure := 1.0) -> Dictionary:
	var none := {dir = Vector3.UP, radius = 0.0, disc_lin = Vector3.ZERO, illuminance = 0.0, e_over_b = 0.0,
		kappa = SunOptics.KAPPA}
	if sky == null or not enabled():
		return none
	var moon_lin: Variant = sky.get_shader_parameter("moon_lin")
	var dir: Variant = sky.get_shader_parameter("moon_dir")
	var radius: Variant = sky.get_shader_parameter("moon_radius")
	if not moon_lin is Vector3 or not dir is Vector3 or radius == null or (dir as Vector3).length_squared() < 1e-12 \
			or SunOptics.luminance(moon_lin) <= 0.0:
		return none
	var toward := (dir as Vector3).normalized()
	var r := float(radius)
	var level := mean_level(sky, toward)
	var e: Vector3 = (moon_lin as Vector3) * level * TAU * (1.0 - cos(r))
	var background := SkyMirror.background_luminance(sky, toward)
	var gamma: Variant = sky.get_shader_parameter("moon_display_gamma")
	var display_scale: Variant = sky.get_shader_parameter("moon_display_scale")
	# The veil at the limb, shown as moon_disc.gdshaderinc shows a disc level: level^γ × display scale.
	var veil_lin: Vector3 = (moon_lin as Vector3) * pow(limb_share(r) * level, float(gamma) if gamma != null else 1.0) \
		* (float(display_scale) if display_scale != null else 1.0)
	var veil := SunOptics.luminance(veil_lin)
	if veil <= 0.0 or background <= 0.0 or level <= 0.0:
		return none
	# A veil colour below the background would darken it: the cap is never under the sky (contrast loss only).
	# Neutral: the glow is seen by dark-adapted, colour-blind rods (moonlight's warm chroma turns brown at this level).
	return {dir = toward, radius = r, disc_lin = Vector3.ONE * maxf(veil, background),
		illuminance = SunOptics.illuminance_scale(e), e_over_b = SunOptics.illuminance_over_background(e, background),
		kappa = minf(display(background * exposure) / display(veil * exposure), 1.0)}


## The disc's mean radiance over moon_lin: the phase law's flux (SkyState.moon_phase_flux, the phase angle from the
## moon_sun_dir uniform) times the eclipse's dimming (moon_eclipse_dim).
static func mean_level(sky: ShaderMaterial, toward: Vector3) -> float:
	var sun_dir: Variant = sky.get_shader_parameter("moon_sun_dir")
	var phase := 0.0
	if sun_dir is Vector3 and (sun_dir as Vector3).length_squared() > 1e-12:
		phase = rad_to_deg(acos(clampf((sun_dir as Vector3).normalized().dot(-toward), -1.0, 1.0)))
	var dim: Variant = sky.get_shader_parameter("moon_eclipse_dim")
	return SkyState.moon_phase_flux(phase) * (float(dim) if dim != null else 1.0)


## CIE straylight at the limb over the disc's mean radiance: glare_excess(θ_limb) × the disc's solid angle (~0.04).
static func limb_share(radius_rad: float) -> float:
	return SunOptics.glare_excess(rad_to_deg(radius_rad)) * TAU * (1.0 - cos(radius_rad))


## A linear display value as the sRGB code value the overlay blends in.
static func display(x: float) -> float:
	var c := maxf(x, 0.0)
	return 12.92 * c if c < 0.0031308 else 1.055 * pow(c, 1.0 / 2.4) - 0.055


## MoonConfig's halo choice: "off" removes the moon's aureole and glare.
static func enabled() -> bool:
	var config: Dictionary = Atmosphere.state.get("moon_config", {})
	return str(config.get("halo", "auto")) != "off"
