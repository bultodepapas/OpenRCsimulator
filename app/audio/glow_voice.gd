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
## `running`, `firing_fraction`, `load`, `throttle`, `blade_count`, and monotonic unwrapped
## `phase_revolutions` (crankshaft revolutions). Missing family is silent; legacy `glow_prop`
## never selects a cycle family.
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
	if family != last_family:
		_scheduled_opportunity = -1
		_fraction_accumulator = 0.0
		_opportunity_fires = false
		last_family = family
	last_firing_fraction = firing_fraction
	frequency = rpm / 60.0
	amplitude = 0.34 * (0.65 + 0.35 * load) if running else 0.0
	var shaft_step: float = rpm / (60.0 * RATE)
	var external_phase: Variant = snapshot.get("phase_revolutions", null)
	if not _has_phase_anchor and _is_number(external_phase) and is_finite(float(external_phase)):
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
			_schedule_opportunity(firing_fraction)
			_scheduled_opportunity += 1
		var cycle_phase: float = fposmod(_shaft_phase_cycles / float(cycle_revs), 1.0)
		var target_envelope: float = 1.0 if running else 0.0
		_combustion_envelope += fade_alpha * (target_envelope - _combustion_envelope)
		var combustion: float = 0.0
		if _opportunity_fires and _combustion_envelope > 0.000001 and cycle_frequency > 0.0:
			combustion = _exhaust_wave(family, cycle_phase, cycle_frequency, nyquist) * combustion_gain * _combustion_envelope
		var crank_phase: float = fposmod(_shaft_phase_cycles, 1.0)
		var mechanical: float = 0.0
		if rpm > 0.0 and frequency < nyquist:
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
