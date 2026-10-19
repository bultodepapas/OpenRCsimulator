# SUN-01…04 (docs/plans/sun.md): the sun's optics as numbers, float64 and engine-free so tests can hold them. The
# sky shader (disc, aureole) and the glare shader (veil, corona, afterimage) mirror these formulas; sources and the
# reasoning behind every constant are in docs/research/sun/SUN-00/README.md.
#
# Veil. CIE 146:2002's general disability-glare equation (Vos & van den Berg) gives the eye's straylight: the
# luminance veiling a point θ degrees from a glare source, per unit illuminance that source makes at the eye. With r
# the veil over the luminance behind the target (the clear sky plus the sun's aerosol aureole, which near the sun is
# far brighter than the sky), a target's Weber contrast falls to 1/(1 + r). An alpha mix toward the source's displayed
# colour reproduces that loss with alpha = q / (1 + q), q = KAPPA·r. Only the straylight above its value at
# VEIL_CUT_DEG is added: the wide, nearly uniform remainder is part of the everyday look the day was calibrated with
# (the same convention as FW-MOON-08a's aureole).
#
# The steady veil alone leaves a dark model visible even 1° from the sun (SUN-00 §2: 15–30 % of its contrast). What
# loses it is photobleaching: the sun's retinal image is ~58 times the afterimage threshold, so a glance bleaches the
# patch it falls on within a fraction of a second, and that patch shows no detail (white while the sun is on it, a dark
# violet afterimage after) until the cones recover, seconds later. In the pilot view the camera follows the model, so
# the patch lands where the model is.
extends RefCounted

const Spec := preload("res://spec.gd")
const Ephemeris := preload("res://render/world/ephemeris.gd")

## CIE 146:2002 inputs: observer age (years) and ocular pigmentation (0 very dark eyes, 0.5 brown, 1 blue-green).
## 40 years is an estimate for a club pilot; brown eyes are CIE's middle value.
const OBSERVER_AGE := 40.0
const OBSERVER_PIGMENT := 0.5
## The equation's range of validity, degrees.
const GSF_MIN_DEG := 0.1
const GSF_MAX_DEG := 100.0
## Straylight beyond this angle is left to the calibrated look (see above).
const VEIL_CUT_DEG := 45.0
## The veil scales with E/B: the sun's illuminance at the eye over the luminance of the clear sky around it (aureole
## excluded), both read from the live sky (SkyMirror). The calibrated day gives ≈ 9, noon at the reference field ≈ 14,
## 100 klx against measured clear skies ≈ 12–20; a low sun against the bright horizon of the sky table falls to ≈ 1–3
## at 5–15° and below 0.5 near the horizon, where a red sun can be looked at. Exposure plays no part: the eye's
## straylight and the background it veils are both absolute.
## The day reference for the afterimage dose, which depends on the absolute illuminance (the bleaching threshold is
## absolute): Spec.ATMOSPHERE's sun, see day_illuminance().
## The aureole behind the target, KS91's aerosol term with its core regularised as 6.2·10⁷/(ρ² + ρ0²) (SUN-00 §3.3).
const AUREOLE_BACKGROUND_CORE_DEG := 0.27
## The display value of the background over that of the veil's colour in the contrast mapping (estimate: a sky near
## 0.75 against a white veil).
const KAPPA := 0.75
## Camera lenses (chase, orbit, close-up) scatter less than the eye: their veil is this share of the eye's.
const LENS_VEIL := 0.2

## The sky disc's mean radiance per unit sun illuminance (sky.gdshader: 4·sun_lin/π, the L1a calibration).
const DISC_RADIANCE_FACTOR := 4.0 / PI

## Limb darkening, I(μ)/I(1) = 1 − u·(1 − μ) − v·(1 − μ²), quadratic law near 550 nm (Pierce & Slaughter 1977 via
## Allen's Astrophysical Quantities; SUN-00). The shader divides by the disc mean so the calibrated brightness stays.
const LIMB_U := 0.93
const LIMB_V := -0.23

## Aureole: Krisciunas & Schaefer's (1991) aerosol scattering, anchored to the sun's own illuminance at the ground
## (B/E = f(ρ)·(1 − 10^(−0.4·k·X))·NL_PER_FC_TO_SR, B in nL and E in fc → sr⁻¹), not to the zenith: this sky's disc
## is ~10⁴ times dimmer than the real one, so the shader then compresses the aureole against the disc
## (aureole / (1 + aureole / (AUREOLE_DISC_SHARE·disc))): below the disc's limb-darkened edge, so a low reddened disc
## stays distinct inside its glow (0.8 dissolved the golden-hour disc in captures).
const NL_PER_FC_TO_SR := 2.957e-7 # 1 nL = 3.183·10⁻⁶ cd/m²; 1 fc = 10.764 lx
const KS91_AEROSOL_NORM := 1412537.5 # 10^6.15: the shader's shape is f(ρ)/10^6.15
const AUREOLE_K := 0.2 # V extinction per airmass (the stars' and the moon aureole's value)
const AUREOLE_DISC_SHARE := 0.4
## Inside this angle the aureole is flat: the dim LDR disc cannot carry KS91's ρ⁻² peak.
const AUREOLE_CORE_DEG := 1.0

## Off screen the depth buffer cannot say whether trees or ridges hide the disc: assume the field's skyline hides a
## sun lower than this apparent elevation (estimate: a 15 m treeline at 300 m subtends ~3°).
const HORIZON_PRIOR_DEG := 3.0

## Afterimage (photostress): the bleached patch of retina where the sun's image fell, as a dose D in [0, 1] driven by the
## sun's illuminance e relative to the calibrated day sun (illuminance_scale): dD/dt = e·(1 − D)/BLEACH_S − D/RECOVER_S,
## on simulation time (the form of Ritschel & Eisemann 2012). Cones half-bleach at ~2·10⁴ td in steady state with
## pigment regeneration τ ≈ 90 s, i.e. ~2·10⁶ td·s per e-fold; the sun's image is ~8·10⁹ td, so it bleaches in
## ~0.2 ms and its ~1° halo of scattered light (~10⁻³ of it) in ~0.2 s (SUN-00 §2). A cell covering disc and halo is
## given 0.05 s (estimate): any passage of the sun's image bleaches its path, a 0.15 s glance leaves an afterimage
## (Ho et al. 2011), and a dimmer sun (sunset, thin cloud) needs proportionally longer. Acuity returns within 5–30 s
## (clinical photostress recovery < 30 s), so masking fades with 8 s (estimate; the minutes-long faint tail is not drawn).
const AFTER_BLEACH_S := 0.05
const AFTER_RECOVER_S := 8.0
## The bleached spot's angular radius (rad): the 0.27° disc plus the ~1° halo of scattered light that is also above the
## afterimage threshold (SUN-00 §2.1).
const AFTER_BASE_RADIUS := 0.02
## The sun only marks the retina inside the eye's field: full up to FIELD_FULL_DEG from the gaze, none past
## FIELD_NONE_DEG (brow and nose; estimates).
const FIELD_FULL_DEG := 50.0
const FIELD_NONE_DEG := 75.0
## How far a fully bleached patch masks the view (display mix of its blurred image), and the tint it takes once the
## sun's light has left it: the negative afterimage of a white sun, darker and violet (a display multiplier). While the
## sun is still on it the patch only loses detail. Masking is drawn by blurring the image over the patch (acuity loss):
## a dark patch alone barely lowers a dark model's Weber contrast (measured: 32 % kept).
const AFTER_MAX_ALPHA := 0.95
const AFTER_TINT := Vector3(0.62, 0.58, 0.80)
## A simulation-clock step longer than this (or backwards) is a restart, a seek or a jump: the eye starts rested.
const AFTER_MAX_STEP_S := 5.0


## L_veil / E_glare (sr⁻¹) at `theta_deg` from the source: CIE 146:2002 general disability-glare equation.
static func glare_spread(theta_deg: float, age := OBSERVER_AGE, pigment := OBSERVER_PIGMENT) -> float:
	var t := clampf(theta_deg, GSF_MIN_DEG, GSF_MAX_DEG)
	return 10.0 / (t * t * t) + (5.0 / (t * t) + 0.1 * pigment / t) * age_factor(age) + 0.0025 * pigment


## The CIE age term 1 + (A/62.5)⁴.
static func age_factor(age: float) -> float:
	return 1.0 + pow(maxf(age, 0.0) / 62.5, 4.0)


## The straylight the glare adds above its value at VEIL_CUT_DEG (zero from there out).
static func glare_excess(theta_deg: float, age := OBSERVER_AGE, pigment := OBSERVER_PIGMENT) -> float:
	if theta_deg >= VEIL_CUT_DEG:
		return 0.0
	return glare_spread(theta_deg, age, pigment) - glare_spread(VEIL_CUT_DEG, age, pigment)


## The veil over the luminance behind a target at `theta_deg`. `e_over_b`: the straylight's source, E/B in sr times the
## disc's visible fraction, clouds and the user's strength. `background_e_over_b`: the aureole behind the target, which is
## sky light and does not change when a model covers part of the disc or the strength is lowered (E/B times clouds;
## negative = the same as `e_over_b`). `aureole_coeff`: aureole_background_coeff() for the sun's elevation and the air
## (0 = sky only).
static func veil_ratio(theta_deg: float, e_over_b: float, aureole_coeff := 0.0, background_e_over_b := -1.0) -> float:
	var e := maxf(e_over_b, 0.0) if is_finite(e_over_b) else 0.0
	var b := e if background_e_over_b < 0.0 or not is_finite(background_e_over_b) else background_e_over_b
	return e * glare_excess(theta_deg) / (1.0 + b * aureole_background(theta_deg, aureole_coeff))


## The aureole's luminance per unit sun illuminance (sr⁻¹) at `theta_deg`, above its 45° value: KS91's aerosol shape
## (regularised core) times `coeff`.
static func aureole_background(theta_deg: float, coeff: float) -> float:
	if theta_deg >= 45.0 or not (coeff > 0.0):
		return 0.0
	var rho := maxf(theta_deg, 0.0)
	var far := pow(10.0, 6.15 - rho / 40.0)
	var near := 6.2e7 / (rho * rho + AUREOLE_BACKGROUND_CORE_DEG * AUREOLE_BACKGROUND_CORE_DEG)
	return ((maxf(near, far) if rho < 30.0 else far) - pow(10.0, 6.15 - 45.0 / 40.0)) * coeff


## nL/fc → sr⁻¹ · KS91's path term at the sun's elevation · the air's aerosol factor (Atmosphere.aureole_aerosol_factor).
static func aureole_background_coeff(sun_elevation_deg: float, aerosol_factor: float) -> float:
	if not is_finite(sun_elevation_deg) or not is_finite(aerosol_factor):
		return 0.0
	return NL_PER_FC_TO_SR * aureole_path(sun_elevation_deg) * maxf(aerosol_factor, 0.0)


## The overlay's alpha that lowers displayed contrast by 1/(1 + r).
static func veil_alpha(ratio: float) -> float:
	var q := KAPPA * maxf(ratio, 0.0)
	return q / (1.0 + q)


## Fraction of a target's Weber contrast left under a veil of `ratio`.
static func contrast_left(ratio: float) -> float:
	return 1.0 / (1.0 + maxf(ratio, 0.0))


## The sun's illuminance relative to the calibrated day sun (Spec.ATMOSPHERE): luminance(sun_lin) / the same for the
## day. `sun_lin` is the sky's sun_lin (light colour · energy · π) with any shadow compensation divided out.
static func illuminance_scale(sun_lin: Vector3) -> float:
	var day := day_illuminance()
	if day <= 0.0 or not sun_lin.is_finite():
		return 0.0
	return maxf(luminance(sun_lin) / day, 0.0)


## luminance(sun_lin) of the calibrated day (≈ 2.25 scene units).
static func day_illuminance() -> float:
	var a: Dictionary = Spec.ATMOSPHERE
	var c: Color = (a.sun_color as Color).srgb_to_linear()
	return luminance(Vector3(c.r, c.g, c.b) * float(a.sun_energy) * PI)


## E/B for a sun of `sun_lin` (compensation removed) against a sky background of `background` (scene units).
static func illuminance_over_background(sun_lin: Vector3, background: float) -> float:
	if not sun_lin.is_finite() or not is_finite(background) or background <= 0.0:
		return 0.0
	return maxf(luminance(sun_lin) / background, 0.0)


static func luminance(v: Vector3) -> float:
	return 0.2126 * v.x + 0.7152 * v.y + 0.0722 * v.z


## Limb darkening at μ = cos(emission angle), relative to the disc centre.
static func limb(mu: float) -> float:
	var m := clampf(mu, 0.0, 1.0)
	return 1.0 - LIMB_U * (1.0 - m) - LIMB_V * (1.0 - m * m)


## The law's mean over the disc's area, 1 − u/3 − v/2: the shader divides by it so the mean radiance is unchanged.
static func limb_mean() -> float:
	return 1.0 - LIMB_U / 3.0 - LIMB_V / 2.0


## Apparent / true vertical size of the disc whose centre is at `apparent_elevation_deg` (refraction flattens a low
## sun; 1 above ~10°), the same law as SkyState.moon_squash, which takes the true elevation.
static func squash(apparent_elevation_deg: float) -> float:
	if not is_finite(apparent_elevation_deg):
		return 1.0
	# Two fixed-point steps from apparent to true elevation (refraction is < 0.7° and slowly varying).
	var true_el := apparent_elevation_deg
	for i in 2:
		true_el = apparent_elevation_deg - Ephemeris.refraction_deg(true_el)
	if true_el < -1.0:
		return 1.0
	var h := 0.01
	return clampf(1.0 + (Ephemeris.refraction_deg(true_el + h) - Ephemeris.refraction_deg(true_el - h)) / (2.0 * h), 0.5, 1.0)


## The aureole's coefficient for the sky shader: sun_lin · 10^6.15 · NL_PER_FC_TO_SR · the air's aerosol factor
## (Atmosphere.aureole_aerosol_factor). Zero when the disc is off (the light is the moon).
static func aureole_lin(sun_lin: Vector3, aerosol_factor: float, sun_disc: float) -> Vector3:
	if sun_disc <= 0.0 or not sun_lin.is_finite() or not is_finite(aerosol_factor):
		return Vector3.ZERO
	return sun_lin * (KS91_AEROSOL_NORM * NL_PER_FC_TO_SR * maxf(aerosol_factor, 0.0) * minf(sun_disc, 1.0))


## KS91's aerosol shape f(ρ)/10^6.15 above its 45° value (the shader's sun_aureole), ρ in degrees.
static func aureole_shape(rho_deg: float) -> float:
	var rho := maxf(rho_deg, AUREOLE_CORE_DEG)
	if rho >= 45.0:
		return 0.0
	var far := pow(10.0, -rho / 40.0)
	return (maxf(43.80 / (rho * rho), far) if rho < 30.0 else far) - pow(10.0, -45.0 / 40.0)


## KS91's path term 1 − 10^(−0.4·k·X), X = (1 − 0.96·sin²Z)^−½, for a sky point at elevation `elevation_deg`.
static func aureole_path(elevation_deg: float) -> float:
	var sin_z := minf(cos(deg_to_rad(maxf(elevation_deg, 0.0))), 1.0)
	var airmass := 1.0 / sqrt(1.0 - 0.96 * sin_z * sin_z)
	return 1.0 - pow(10.0, -0.4 * AUREOLE_K * airmass)


## sky.gdshader sun_aureole() at `rho_deg` from the sun for a sky point at `elevation_deg`: KS91's shape and path
## term, compressed below AUREOLE_DISC_SHARE of the disc, faded over the last 2° above the horizon. `aureole_lin` and
## `sun_lin` are the sky's uniforms.
static func sky_aureole(aureole_lin: Vector3, sun_lin: Vector3, rho_deg: float, elevation_deg: float) -> Vector3:
	var shape := aureole_shape(rho_deg)
	if shape <= 0.0 or not aureole_lin.is_finite() or aureole_lin.x + aureole_lin.y + aureole_lin.z <= 0.0:
		return Vector3.ZERO
	var a := aureole_lin * shape * aureole_path(elevation_deg)
	var disc := AUREOLE_DISC_SHARE * DISC_RADIANCE_FACTOR * luminance(sun_lin)
	return a / (1.0 + luminance(a) / maxf(disc, 1e-12)) * smoothstep(0.0, 0.035, sin(deg_to_rad(elevation_deg)))


## The legacy L1a halo the sky draws around the disc at `rho_deg` (sky.gdshader: (sun_lin/π)·0.35·e^(−18·ρ)).
static func sky_halo(sun_lin: Vector3, rho_deg: float) -> Vector3:
	return sun_lin / PI * 0.35 * exp(-18.0 * deg_to_rad(maxf(rho_deg, 0.0)))


## The veil's target colour (pre-exposure): the disc's, raised per channel to VEIL_SKY_MARGIN times the sky around the
## source. Straylight only adds light, so the overlay's mix toward this colour must never darken that sky (a mix toward
## the disc alone darkened a bright golden-hour sky by up to 15 levels).
const VEIL_SKY_MARGIN := 1.1


static func veil_colour(disc_lin: Vector3, sky_around: Vector3) -> Vector3:
	if not sky_around.is_finite():
		return disc_lin
	return disc_lin.max(sky_around * VEIL_SKY_MARGIN)


## SUN-06 eyewear. A cap brim shades the eye from a source more than BRIM_CUT_DEG above the line of sight (a 7 cm brim
## 3 cm above the eye: atan(3/7) ≈ 23°, estimate 25°), over BRIM_SOFT_DEG; it moves with the head, so looking up at a
## model near the sun it does not help. Light-brown sunglasses (Model Aviation's advice for model flying) pass
## SUNGLASSES_TRANSMISSION of the light: the veil's ratio is unchanged (sun and sky both dimmed) but the retina's
## bleaching dose falls with it.
const BRIM_CUT_DEG := 25.0
const BRIM_SOFT_DEG := 3.0
const SUNGLASSES_TRANSMISSION := 0.25


## How much of a source at `source_view` (unit, view space: −z ahead, +y up) the brim lets reach the eye.
static func brim_transmission(source_view: Vector3) -> float:
	if not source_view.is_finite() or source_view.length_squared() == 0.0:
		return 1.0
	var v := source_view.normalized()
	if v.z > 0.2:
		return 1.0 # well behind the face: the brim is not between it and the eye (nor is the eye's field)
	var above := rad_to_deg(asin(clampf(v.y, -1.0, 1.0)))
	return 1.0 - smoothstep(BRIM_CUT_DEG - BRIM_SOFT_DEG, BRIM_CUT_DEG + BRIM_SOFT_DEG, above)


## The eyewear's factors for one frame: {veil, dose}. `eyewear`: {cap, sunglasses} (Options.pilot_eyewear()).
static func eyewear_factors(eyewear: Dictionary, source_view: Vector3) -> Dictionary:
	var brim := brim_transmission(source_view) if eyewear.get("cap", false) else 1.0
	var glasses := SUNGLASSES_TRANSMISSION if eyewear.get("sunglasses", false) else 1.0
	return {veil = brim, dose = brim * glasses}


## Visibility of a disc at `elevation_rad` (apparent) when the depth buffer cannot tell: the skyline prior.
static func horizon_prior(elevation_rad: float) -> float:
	if not is_finite(elevation_rad):
		return 0.0
	return smoothstep(0.0, deg_to_rad(HORIZON_PRIOR_DEG), elevation_rad)


## The share of the eye's field a source `gaze_angle_rad` from the gaze falls in (1 well inside, 0 behind the brow).
static func field_weight(gaze_angle_rad: float) -> float:
	return 1.0 - smoothstep(deg_to_rad(FIELD_FULL_DEG), deg_to_rad(FIELD_NONE_DEG), gaze_angle_rad)


## The bleached retina as fixed cells of AFTER_BASE_RADIUS (view space, fixed to the gaze). The sun's image adds dose
## to every cell near it, weighted by a Gaussian of its distance; where no cell lies within AFTER_MERGE_RAD a new one
## starts, so a sun sweeping across the view leaves a chain of cells (a streak) and a steady one saturates a single
## cell. At most AFTER_PATCHES cells; when all are visible a longer sweep stops leaving new ones.
const AFTER_PATCHES := 8
const AFTER_MERGE_RAD := 0.02
## Below this dose a cell's masking is under ~5 %: it may give its place to a new one.
const AFTER_EVICT_DOSE := 0.05


## A rested eye's afterimage state: cells of {dose, dir (unit, view space; camera −z forward)}.
static func afterimage_rest() -> Dictionary:
	return {patches = []}


## Advances the afterimage by `dt` seconds of a constant sun of illuminance `e` (relative to the day sun, already
## weighted by visibility, clouds and the eye's field) whose image falls at `sun_view` (unit, view space). Exact for
## constant input, so the result does not depend on the frame rate. Returns a new state.
static func afterimage_step(state: Dictionary, dt: float, e: float, sun_view: Vector3) -> Dictionary:
	var patches: Array = (state.get("patches", []) as Array).duplicate(true)
	if not (dt > 0.0) or not is_finite(dt):
		return {patches = patches}
	var exposing := is_finite(e) and e > 0.0 and sun_view.is_finite() and sun_view.length_squared() > 0.0
	var s := sun_view.normalized() if exposing else Vector3(0.0, 0.0, -1.0)
	if exposing:
		var nearest := INF
		for patch: Dictionary in patches:
			nearest = minf(nearest, (patch.dir as Vector3).angle_to(s))
		if nearest > AFTER_MERGE_RAD:
			# A full eye only gives up a cell that no longer shows: a visible patch never vanishes mid-sweep.
			if patches.size() >= AFTER_PATCHES:
				var weakest := 0
				for i in patches.size():
					if float(patches[i].dose) < float(patches[weakest].dose):
						weakest = i
				if float(patches[weakest].dose) < AFTER_EVICT_DOSE:
					patches.remove_at(weakest)
			if patches.size() < AFTER_PATCHES:
				patches.append({dose = 0.0, dir = s})
	var kept: Array = []
	for patch: Dictionary in patches:
		var weight := 0.0
		if exposing:
			var x := (patch.dir as Vector3).angle_to(s) / AFTER_BASE_RADIUS
			weight = exp(-x * x)
		var out := patch.duplicate()
		out.dose = bleach(float(patch.dose), dt, e * weight)
		if float(out.dose) > 1e-4 or weight > 0.5:
			kept.append(out)
	return {patches = kept}


## One cell's dose after `dt` seconds of constant illuminance `e`: the exact solution of
## dD/dt = e·(1 − D)/AFTER_BLEACH_S − D/AFTER_RECOVER_S.
static func bleach(dose: float, dt: float, e: float) -> float:
	var rate_in := maxf(e, 0.0) / AFTER_BLEACH_S
	var k := rate_in + 1.0 / AFTER_RECOVER_S
	var target := rate_in / k
	return clampf(target + (dose - target) * exp(-k * dt), 0.0, 1.0)


## The masking alpha of each patch (AFTER_PATCHES entries, zero-padded).
static func afterimage_alphas(state: Dictionary) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(AFTER_PATCHES)
	var patches: Array = state.get("patches", [])
	for i in mini(patches.size(), AFTER_PATCHES):
		out[i] = AFTER_MAX_ALPHA * clampf(float(patches[i].dose), 0.0, 1.0)
	return out


static func afterimage_dose(state: Dictionary) -> float:
	var total := 0.0
	for patch: Dictionary in state.get("patches", []):
		total = maxf(total, float(patch.dose))
	return total


## Whether the sun's image still falls on a patch at `dir` of `radius` (rad): 1 on it, 0 from twice its radius out or
## when the sun gives no light (`dose`, the illuminance reaching the eye).
static func afterimage_lit(dir: Vector3, radius: float, sun_view: Vector3, dose: float) -> float:
	if not (dose > 0.0) or not sun_view.is_finite() or not dir.is_finite() or dir.length_squared() == 0.0:
		return 0.0
	var r := maxf(radius, 1e-4)
	return 1.0 - smoothstep(r, 2.0 * r, dir.normalized().angle_to(sun_view.normalized()))


## tan(half the vertical field of view) of a perspective camera of `fov_deg` (vertical, or horizontal when
## `keep_width`) on a viewport of `aspect` = width / height.
static func view_tan_half_height(fov_deg: float, keep_width: bool, aspect: float) -> float:
	var t := tan(deg_to_rad(clampf(fov_deg, 0.01, 179.0)) * 0.5)
	return t / maxf(aspect, 1e-6) if keep_width else t

