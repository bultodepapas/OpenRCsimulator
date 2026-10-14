## Procedural glow-engine presentation voice. Physics telemetry is read-only input.
## Orders and levels are authored until synchronized recordings and mount data exist.
extends RefCounted

const RATE := 22050.0
const FADE_SECONDS := 0.006
const FAMILY_2T := "glow_2t"
const FAMILY_4T := "glow_4t"
const TAU_VALUE := 2.0 * PI
const HARMONICS_2T: Array[float] = [1.0, 0.48, 0.30, 0.18, 0.11, 0.065, 0.035]
const HARMONICS_4T: Array[float] = [1.0, 0.32, 0.43, 0.17, 0.13, 0.055, 0.025]
const SOURCE_FORCE_PCM_GAIN := 0.0003
const MAX_SOURCE_MECHANICAL_PEAK := 0.12

## The render(rpm, max_rpm, frames) signature matches render/engine_voice.gd.
## Call set_telemetry() before render() to supply the family and combustion telemetry.
var phase := 0.0
var frequency := 0.0
var amplitude := 0.0
var last_family := ""
var last_firing_fraction := 0.0

var _telemetry: Dictionary = {}
var _shaft_phase_cycles := 0.0
var _scheduled_opportunity := -1
var _fraction_accumulator := 0.0
var _opportunity_fires := false
var _combustion_envelope := 0.0
var _has_phase_anchor := false
var _has_physical_anchor := false
var _physical_opportunity_count := -1
var _physical_fire_count := -1
var _suppress_combustion_until_opportunity := false


static func cycle_revolutions(family: String) -> int:
	if family == FAMILY_2T:
		return 1
	if family == FAMILY_4T:
		return 2
	return 0


static func firing_order(family: String) -> float:
	var revolutions: int = cycle_revolutions(family)
	return 1.0 / float(revolutions) if revolutions > 0 else 0.0


static func firing_frequency_hz(family: String, rpm: float, firing_fraction: float = 1.0) -> float:
	if not is_finite(rpm) or not is_finite(firing_fraction):
		return 0.0
	return maxf(rpm, 0.0) / 60.0 * firing_order(family) * clampf(firing_fraction, 0.0, 1.0)


static func blade_pass_frequency_hz(rpm: float, blade_count: int) -> float:
	if not is_finite(rpm):
		return 0.0
	return maxf(rpm, 0.0) / 60.0 * float(maxi(blade_count, 1))


## Source-force-to-PCM conversion is an authored presentation gain, not a mount/acoustic model.
## Returns constant-speed source order peaks only when the observer snapshot matches this voice.
static func source_vibration_pcm_peaks(source_vibration: Variant, family: String, rpm: float) -> Dictionary:
	if not source_vibration is Dictionary or not is_finite(rpm) or rpm < 0.0:
		return _source_vibration_levels_failure()
	var cycle_revs: int = cycle_revolutions(family)
	if cycle_revs == 0 or source_vibration.get("ok", false) != true or source_vibration.get("family", "") != family:
		return _source_vibration_levels_failure()
	if source_vibration.get("constant_speed_assumption", false) != true:
		return _source_vibration_levels_failure()
	var cycle_value: Variant = source_vibration.get("cycle_revolutions", null)
	var omega_value: Variant = source_vibration.get("omega_rad_s", null)
	var alpha_value: Variant = source_vibration.get("alpha_rad_s2", null)
	var phase_value: Variant = source_vibration.get("phase_rad", null)
	if not _is_number(cycle_value) or not is_finite(float(cycle_value)) or float(cycle_value) != float(cycle_revs) or not _is_number(omega_value):
		return _source_vibration_levels_failure()
	if not _is_number(alpha_value) or not is_finite(float(alpha_value)) or float(alpha_value) != 0.0 \
			or not _is_number(phase_value) or not is_finite(float(phase_value)) \
			or float(phase_value) < 0.0 or float(phase_value) >= TAU_VALUE:
		return _source_vibration_levels_failure()
	var expected_omega: float = rpm * TAU_VALUE / 60.0
	var source_omega: float = float(omega_value)
	if not is_finite(source_omega) or source_omega < 0.0 or absf(source_omega - expected_omega) > maxf(1e-6, expected_omega * 1e-8):
		return _source_vibration_levels_failure()
	var one_value: Variant = source_vibration.get("order_1x_force_peak_n", null)
	var two_value: Variant = source_vibration.get("order_2x_force_peak_n", null)
	var one_cosine_value: Variant = source_vibration.get("order_1x_force_cosine_n", null)
	var one_sine_value: Variant = source_vibration.get("order_1x_force_sine_n", null)
	var two_cosine_value: Variant = source_vibration.get("order_2x_force_cosine_n", null)
	var two_sine_value: Variant = source_vibration.get("order_2x_force_sine_n", null)
	if not _is_number(one_value) or not _is_number(two_value) or not _is_number(one_cosine_value) \
			or not _is_number(one_sine_value) or not _is_number(two_cosine_value) or not _is_number(two_sine_value):
		return _source_vibration_levels_failure()
	var force_one: float = float(one_value)
	var force_two: float = float(two_value)
	var force_one_cosine: float = float(one_cosine_value)
	var force_one_sine: float = float(one_sine_value)
	var force_two_cosine: float = float(two_cosine_value)
	var force_two_sine: float = float(two_sine_value)
	if not is_finite(force_one) or not is_finite(force_two) or force_one < 0.0 or force_two < 0.0 \
			or not is_finite(force_one_cosine) or not is_finite(force_one_sine) \
			or not is_finite(force_two_cosine) or not is_finite(force_two_sine):
		return _source_vibration_levels_failure()
	var component_peak_one: float = sqrt(force_one_cosine * force_one_cosine + force_one_sine * force_one_sine)
	var component_peak_two: float = sqrt(force_two_cosine * force_two_cosine + force_two_sine * force_two_sine)
	if not is_finite(component_peak_one) or not is_finite(component_peak_two) \
			or absf(component_peak_one - force_one) > maxf(1e-8, force_one * 1e-8) \
			or absf(component_peak_two - force_two) > maxf(1e-8, force_two * 1e-8):
		return _source_vibration_levels_failure()
	var one_peak: float = force_one * SOURCE_FORCE_PCM_GAIN
	var two_peak: float = force_two * SOURCE_FORCE_PCM_GAIN
	var total_peak: float = one_peak + two_peak
	if not is_finite(total_peak):
		return _source_vibration_levels_failure()
	var limiter_scale: float = 1.0 if total_peak <= MAX_SOURCE_MECHANICAL_PEAK else MAX_SOURCE_MECHANICAL_PEAK / total_peak
	var result: Dictionary = {
		ok = true,
		order_1x_cosine_pcm = force_one_cosine * SOURCE_FORCE_PCM_GAIN * limiter_scale,
		order_1x_sine_pcm = force_one_sine * SOURCE_FORCE_PCM_GAIN * limiter_scale,
		order_2x_cosine_pcm = force_two_cosine * SOURCE_FORCE_PCM_GAIN * limiter_scale,
		order_2x_sine_pcm = force_two_sine * SOURCE_FORCE_PCM_GAIN * limiter_scale,
		order_1x_peak_pcm = one_peak * limiter_scale,
		order_2x_peak_pcm = two_peak * limiter_scale,
		common_gain_pcm_per_n = SOURCE_FORCE_PCM_GAIN,
		limiter_scale = limiter_scale,
	}
	result.make_read_only()
	return result


func set_telemetry(snapshot: Dictionary) -> void:
	_telemetry = snapshot.duplicate()


## Starts a fresh presentation voice. Engine cut/restart should instead change `running`;
## the shaft and propeller phases then keep moving without a phase reset.
func reset(rpm: float = 0.0, max_rpm: float = 1.0) -> void:
	_shaft_phase_cycles = 0.0
	_scheduled_opportunity = -1
	_fraction_accumulator = 0.0
	_opportunity_fires = false
	_combustion_envelope = 0.0
	_has_phase_anchor = false
	_has_physical_anchor = false
	_physical_opportunity_count = -1
	_physical_fire_count = -1
	_suppress_combustion_until_opportunity = false
	phase = 0.0
	frequency = maxf(rpm, 0.0) / 60.0 if is_finite(rpm) else 0.0
	amplitude = 0.0 if not is_finite(max_rpm) or max_rpm <= 0.0 else clampf(maxf(rpm, 0.0) / max_rpm, 0.0, 1.0)
	last_family = ""
	last_firing_fraction = 0.0


## Native-generator-compatible method. `max_rpm` only scales the authored layer levels.
func render(rpm: float, max_rpm: float, frames: int) -> PackedVector2Array:
	var snapshot: Dictionary = _telemetry.duplicate()
	snapshot["rpm"] = rpm
	snapshot["max_rpm"] = max_rpm
	return render_telemetry(snapshot, frames)


## Render detached accepted-state telemetry to mono-as-stereo PCM for AudioStreamGeneratorPlayback.
## Required fields: `family` (`glow_2t`/`glow_4t`) and `rpm`; optional fields are `max_rpm`,
## `running`, `firing_fraction`, `load`, `throttle`, and `blade_count`. Physical sessions also
## supply normalized `phase_revolutions`, cumulative `opportunity_count`/`fire_count`, and
## `firing_accumulator`; `audio_queue_frames` estimates the already queued phase lead. Without
## counters, `phase_revolutions` keeps the older unwrapped-phase adapter behavior. Missing family
## is silent; legacy `glow_prop` never selects a cycle family.
func render_telemetry(snapshot: Dictionary, frames: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var frame_count: int = maxi(frames, 0)
	out.resize(frame_count)
	if frame_count == 0:
		return out
	var family: String = str(snapshot.get("family", ""))
	var cycle_revs: int = cycle_revolutions(family)
	if cycle_revs == 0:
		last_family = ""
		return out
	var rpm: float = _finite_nonnegative(snapshot.get("rpm", 0.0), 0.0)
	var maximum: float = _finite_nonnegative(snapshot.get("max_rpm", 12000.0), 12000.0)
	if maximum <= 0.0:
		maximum = 12000.0
	var firing_fraction: float = clampf(_finite_nonnegative(snapshot.get("firing_fraction", 1.0), 1.0), 0.0, 1.0)
	var load: float = clampf(_finite_nonnegative(snapshot.get("load", snapshot.get("throttle", 0.45)), 0.45), 0.0, 1.0)
	var blade_count: int = clampi(int(snapshot.get("blade_count", 2)), 1, 8)
	var running: bool = bool(snapshot.get("running", false))
	var source_mechanical: Dictionary = source_vibration_pcm_peaks(snapshot.get("source_vibration", null), family, rpm)
	if family != last_family:
		_scheduled_opportunity = -1
		_fraction_accumulator = 0.0
		_opportunity_fires = false
		_has_physical_anchor = false
		_physical_opportunity_count = -1
		_physical_fire_count = -1
		_suppress_combustion_until_opportunity = false
		last_family = family
	last_firing_fraction = firing_fraction
	frequency = rpm / 60.0
	amplitude = 0.34 * (0.65 + 0.35 * load) if running else 0.0
	var shaft_step: float = rpm / (60.0 * RATE)
	var external_phase: Variant = snapshot.get("phase_revolutions", null)
	var physical_phase: float = 0.0
	var physical_opportunities: int = -1
	var physical_fire_count: int = -1
	var physical_accumulator: float = NAN
	if _has_authoritative_cycle_state(snapshot, cycle_revs):
		physical_opportunities = int(snapshot.opportunity_count)
		physical_fire_count = int(snapshot.fire_count)
		physical_accumulator = float(snapshot.firing_accumulator)
		physical_phase = float(physical_opportunities) * float(cycle_revs) + float(snapshot.phase_revolutions)
		var queued_frames: float = _finite_nonnegative(snapshot.get("audio_queue_frames", 0.0), 0.0)
		# Generator playback trails the accepted simulation by its queued duration. Anchor the
		# next block at the end of those samples so phase corrections do not replay queued audio.
		_shaft_phase_cycles = physical_phase + rpm / 60.0 * queued_frames / RATE
		_scheduled_opportunity = physical_opportunities
		_fraction_accumulator = physical_accumulator
		var firing_limit: float = _finite_nonnegative(snapshot.get("firing_fraction", 1.0), 1.0)
		var opportunity_delta: int = physical_opportunities - _physical_opportunity_count if _has_physical_anchor else 0
		var fire_delta: int = physical_fire_count - _physical_fire_count if _has_physical_anchor else 0
		var has_recent_fire: bool = physical_opportunities > 0 and physical_fire_count > 0 \
			and physical_accumulator + 1e-12 < clampf(firing_limit, 0.0, 1.0)
		if not running:
			_opportunity_fires = false
			_suppress_combustion_until_opportunity = true
		elif _suppress_combustion_until_opportunity:
			if opportunity_delta > 0:
				_suppress_combustion_until_opportunity = false
				_opportunity_fires = fire_delta > 0
			else:
				_opportunity_fires = false
		elif opportunity_delta > 0:
			# Accepted event counts identify the last event exactly for the normal one-opportunity
			# tick. At larger skips, fall back to the accumulator-derived current-cycle state.
			_opportunity_fires = fire_delta > 0 if opportunity_delta == 1 else has_recent_fire
		else:
			_opportunity_fires = has_recent_fire
		_has_physical_anchor = true
		_physical_opportunity_count = physical_opportunities
		_physical_fire_count = physical_fire_count
		_has_phase_anchor = true
	elif not _has_phase_anchor and _is_number(external_phase) and is_finite(float(external_phase)):
		_shaft_phase_cycles = float(external_phase)
		_has_phase_anchor = true
	var nyquist: float = RATE * 0.5
	var cycle_frequency: float = rpm / (60.0 * float(cycle_revs))
	var blade_frequency: float = blade_pass_frequency_hz(rpm, blade_count)
	var ratio: float = clampf(rpm / maximum, 0.0, 1.3)
	var combustion_gain: float = amplitude
	var mechanical_gain: float = 0.055 * (0.55 + 0.45 * load) * (0.55 + 0.45 * ratio)
	var valve_gain: float = 0.042 * (0.65 + 0.35 * ratio)
	var propeller_gain: float = 0.095 * (0.35 + 0.65 * ratio) * (0.7 + 0.3 * load)
	var fade_alpha: float = 1.0 - exp(-1.0 / (FADE_SECONDS * RATE))
	for i: int in frame_count:
		var opportunity: int = floori(_shaft_phase_cycles / float(cycle_revs))
		if _scheduled_opportunity < 0:
			_fraction_accumulator = fposmod(1.0 - firing_fraction, 1.0)
			_scheduled_opportunity = opportunity - 1
		while _scheduled_opportunity < opportunity:
			_schedule_opportunity(firing_fraction if running and _finite_nonnegative(snapshot.get("fuel_kg", 1.0), 1.0) > 0.0 else 0.0)
			_scheduled_opportunity += 1
		var cycle_phase: float = fposmod(_shaft_phase_cycles / float(cycle_revs), 1.0)
		var target_envelope: float = 1.0 if running else 0.0
		_combustion_envelope += fade_alpha * (target_envelope - _combustion_envelope)
		var combustion: float = 0.0
		if running and _opportunity_fires and _combustion_envelope > 0.000001 and cycle_frequency > 0.0:
			combustion = _exhaust_wave(family, cycle_phase, cycle_frequency, nyquist) * combustion_gain * _combustion_envelope
		var crank_phase: float = fposmod(_shaft_phase_cycles, 1.0)
		var mechanical: float = 0.0
		if rpm > 0.0 and frequency < nyquist:
			if source_mechanical.ok:
				var crank_angle: float = TAU_VALUE * crank_phase
				mechanical = source_mechanical.order_1x_cosine_pcm * cos(crank_angle) \
					+ source_mechanical.order_1x_sine_pcm * sin(crank_angle)
				if frequency * 2.0 < nyquist:
					mechanical += source_mechanical.order_2x_cosine_pcm * cos(2.0 * crank_angle) \
						+ source_mechanical.order_2x_sine_pcm * sin(2.0 * crank_angle)
			else:
				mechanical = mechanical_gain * sin(TAU_VALUE * crank_phase)
				if frequency * 2.0 < nyquist:
					mechanical += mechanical_gain * 0.20 * sin(TAU_VALUE * 2.0 * crank_phase)
		var valve: float = 0.0
		if family == FAMILY_4T and rpm > 0.0 and cycle_frequency < nyquist:
			valve = valve_gain * (sin(TAU_VALUE * cycle_phase) + 0.28 * _bandlimited_sine(cycle_phase, 2, cycle_frequency, nyquist))
		var propeller: float = 0.0
		if blade_frequency > 0.0 and blade_frequency < nyquist:
			var blade_phase: float = fposmod(_shaft_phase_cycles * float(blade_count), 1.0)
			propeller = propeller_gain * (sin(TAU_VALUE * blade_phase) + 0.15 * _bandlimited_sine(blade_phase, 2, blade_frequency, nyquist))
		var sample: float = clampf(combustion + mechanical + valve + propeller, -0.98, 0.98)
		out[i] = Vector2(sample, sample)
		_shaft_phase_cycles += shaft_step
	phase = fposmod(_shaft_phase_cycles, 1.0)
	return out


func _has_authoritative_cycle_state(snapshot: Dictionary, cycle_revs: int) -> bool:
	if not _is_number(snapshot.get("phase_revolutions")) \
			or not _is_number(snapshot.get("opportunity_count")) \
			or not _is_number(snapshot.get("fire_count")) \
			or not _is_number(snapshot.get("firing_accumulator")):
		return false
	var phase_value: float = float(snapshot.phase_revolutions)
	var opportunity_value: float = float(snapshot.opportunity_count)
	var fire_value: float = float(snapshot.fire_count)
	var accumulator: float = float(snapshot.firing_accumulator)
	return is_finite(phase_value) and phase_value >= 0.0 and phase_value < float(cycle_revs) \
		and is_finite(opportunity_value) and opportunity_value >= 0.0 and opportunity_value == floor(opportunity_value) \
		and is_finite(fire_value) and fire_value >= 0.0 and fire_value <= opportunity_value and fire_value == floor(fire_value) \
		and is_finite(accumulator) and accumulator >= 0.0 and accumulator < 1.0


func _schedule_opportunity(firing_fraction: float) -> void:
	_fraction_accumulator += firing_fraction
	_opportunity_fires = _fraction_accumulator >= 1.0
	if _opportunity_fires:
		_fraction_accumulator -= 1.0
	last_firing_fraction = firing_fraction


func _exhaust_wave(family: String, cycle_phase: float, base_frequency: float, nyquist: float) -> float:
	# These compact, band-limited harmonic envelopes are authored timbres, not recorded spectra.
	# The 2T branch emphasizes a sharper port/exhaust pulse; 4T has a rounder exhaust and adds
	# its independent cam/valve layer at half crank order in render_telemetry().
	var weights: Array[float] = HARMONICS_2T if family == FAMILY_2T else HARMONICS_4T
	var result: float = 0.0
	for index: int in weights.size():
		var harmonic: int = index + 1
		if base_frequency * float(harmonic) >= nyquist:
			break
		result += weights[index] * sin(TAU_VALUE * float(harmonic) * cycle_phase)
	return result


func _bandlimited_sine(cycles: float, harmonic: int, base_frequency: float, nyquist: float) -> float:
	if base_frequency * float(harmonic) >= nyquist:
		return 0.0
	return sin(TAU_VALUE * float(harmonic) * cycles)


static func _finite_nonnegative(value: Variant, fallback: float) -> float:
	if not _is_number(value):
		return fallback
	var number: float = float(value)
	return maxf(number, 0.0) if is_finite(number) else fallback


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _source_vibration_levels_failure() -> Dictionary:
	var result: Dictionary = {ok = false, order_1x_cosine_pcm = 0.0, order_1x_sine_pcm = 0.0,
		order_2x_cosine_pcm = 0.0, order_2x_sine_pcm = 0.0, order_1x_peak_pcm = 0.0, order_2x_peak_pcm = 0.0,
		common_gain_pcm_per_n = SOURCE_FORCE_PCM_GAIN, limiter_scale = 0.0}
	result.make_read_only()
	return result
