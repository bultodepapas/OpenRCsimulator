## Procedural two-stroke Nitro car voice. Accepted physics telemetry is read-only input.
## Harmonic levels are an authored presentation model, not measured acoustics.
extends RefCounted

const RATE: float = 22050.0
const MAX_BLOCK_FRAMES: int = 4096
const MAX_OUTPUT_PEAK: float = 0.82
const MAX_ENGINE_RPM: float = 45000.0
const TAU_VALUE: float = 2.0 * PI
const GATE_FADE_SECONDS: float = 0.006
const TRANSIENT_DECAY_SECONDS: float = 0.055
const EXHAUST_HARMONICS: Array[float] = [1.0, 0.55, 0.37, 0.26, 0.19, 0.13, 0.09, 0.06, 0.04]

var phase_cycles: float = 0.0
var current_rpm: float = 0.0
var last_clutch_level: float = 0.0
var last_skid_level: float = 0.0
var last_transient_level: float = 0.0

var _target_rpm: float = 0.0
var _target_throttle: float = 0.0
var _current_throttle: float = 0.0
var _fuel_flow: float = 0.0
var _fuel_kg: float = 0.0
var _engine_running: bool = false
var _enabled: bool = true
var _paused: bool = false
var _clutch_slip: float = 0.0
var _clutch_engagement: float = 0.0
var _clutch_torque_nm: float = 0.0
var _wheel_drive_torque_nm: float = 0.0
var _grounded_skid: float = 0.0
var _gate: float = 0.0
var _transient: float = 0.0
var _noise_state: int = 2463534242
var _skid_noise: float = 0.0


## Observe a detached simulation telemetry snapshot. This never changes simulation state.
## `nitro` fields may be top-level or in telemetry.nitro for compatibility with both callers.
func observe(telemetry: Dictionary, controls: Dictionary, paused: bool, enabled: bool) -> void:
	var nitro: Dictionary = telemetry
	var nested: Variant = telemetry.get("nitro", null)
	if nested is Dictionary:
		nitro = nested
	var old_rpm: float = _target_rpm
	_target_rpm = clampf(_finite_number(nitro.get("engine_rpm", 0.0), 0.0), 0.0, MAX_ENGINE_RPM)
	_engine_running = nitro.get("engine_running", false) == true
	_fuel_kg = maxf(0.0, _finite_number(nitro.get("fuel_kg", 0.0), 0.0))
	_fuel_flow = maxf(0.0, _finite_number(nitro.get("fuel_flow_kg_per_s", 0.0), 0.0))
	var throttle_value: Variant = nitro.get("throttle_fraction", controls.get("throttle_fraction", controls.get("throttle", 0.0)))
	_target_throttle = clampf(_finite_number(throttle_value, 0.0), 0.0, 1.0)
	_clutch_slip = clampf(_finite_number(nitro.get("clutch_slip", 0.0), 0.0), -1.0, 1.0)
	_clutch_engagement = clampf(_finite_number(nitro.get("clutch_engagement", 0.0), 0.0), 0.0, 1.0)
	_clutch_torque_nm = _finite_number(nitro.get("clutch_torque_nm", 0.0), 0.0)
	_wheel_drive_torque_nm = _finite_number(nitro.get("wheel_drive_torque_nm", 0.0), 0.0)
	_grounded_skid = _grounded_slip_level(telemetry)
	_enabled = enabled
	_paused = paused
	if paused or not enabled:
		# Freeze oscillator phases during pause and discard stale output at the adapter boundary.
		_gate = 0.0
	else:
		if not _is_sound_eligible() or old_rpm <= 0.0:
			_gate = 0.0
		var rpm_delta: float = absf(_target_rpm - old_rpm)
		if _is_sound_eligible() and rpm_delta > 90.0:
			_transient = maxf(_transient, clampf((rpm_delta - 90.0) / 1100.0, 0.0, 1.0))


## Render at most MAX_BLOCK_FRAMES. Oversized requests are capped before allocating output.
func render(frames: int) -> PackedVector2Array:
	var frame_count: int = clampi(frames, 0, MAX_BLOCK_FRAMES)
	var output := PackedVector2Array()
	output.resize(frame_count)
	last_clutch_level = 0.0
	last_skid_level = 0.0
	last_transient_level = 0.0
	if frame_count == 0 or _paused or not _enabled:
		return output
	var fade_step: float = 1.0 / maxf(1.0, RATE * GATE_FADE_SECONDS)
	var rpm_alpha: float = 1.0 - exp(-1.0 / (RATE * 0.012))
	var throttle_alpha: float = 1.0 - exp(-1.0 / (RATE * 0.018))
	var transient_decay: float = exp(-1.0 / (RATE * TRANSIENT_DECAY_SECONDS))
	var nyquist: float = RATE * 0.5
	# These inputs are snapshots and cannot change during one render call.
	var sound_eligible: bool = _is_sound_eligible()
	var flow_fraction: float = clampf(_fuel_flow / 0.0005, 0.0, 1.0)
	var clutch_level: float = 0.0
	if absf(_clutch_slip) > 0.02 and (_clutch_engagement > 0.0 or _clutch_torque_nm != 0.0):
		var torque_factor: float = clampf(maxf(absf(_clutch_torque_nm), absf(_wheel_drive_torque_nm) * 0.1), 0.0, 1.0)
		clutch_level = absf(_clutch_slip) * maxf(0.12, _clutch_engagement) * (0.012 + 0.024 * torque_factor)
	for frame in frame_count:
		var target_gate: float = 1.0 if sound_eligible else 0.0
		_gate = move_toward(_gate, target_gate, fade_step)
		current_rpm += (_target_rpm - current_rpm) * rpm_alpha
		_current_throttle += (_target_throttle - _current_throttle) * throttle_alpha
		var throttle: float = _current_throttle
		# The accepted fuel-flow telemetry contributes to combustion texture alongside throttle.
		var load: float = clampf(maxf(throttle * 0.72, flow_fraction * 0.58), 0.0, 1.0)
		var rpm_fraction: float = clampf(current_rpm / MAX_ENGINE_RPM, 0.0, 1.0)
		var crank_frequency: float = current_rpm / 60.0
		var exhaust: float = 0.0
		if current_rpm > 0.0:
			var harmonic_sum: float = 0.0
			var weight_sum: float = 0.0
			for harmonic_index in EXHAUST_HARMONICS.size():
				var harmonic: int = harmonic_index + 1
				if crank_frequency * float(harmonic) >= nyquist:
					break
				var weight: float = EXHAUST_HARMONICS[harmonic_index]
				harmonic_sum += weight * sin(TAU_VALUE * float(harmonic) * phase_cycles)
				weight_sum += weight
			if weight_sum > 0.0:
				# One exhaust event per crank revolution gives the two-stroke firing cadence.
				var sharpness: float = 1.0 + 0.12 * load
				exhaust = harmonic_sum / weight_sum * sharpness
		var engine_gain: float = (0.17 + 0.11 * load + 0.025 * flow_fraction) * (0.72 + 0.28 * sqrt(rpm_fraction))
		var crank_rattle: float = 0.0
		if current_rpm > 0.0:
			crank_rattle = (sin(TAU_VALUE * 2.0 * phase_cycles) + 0.28 * sin(TAU_VALUE * 5.0 * phase_cycles)) * (0.035 + 0.025 * load)
		var clutch_layer: float = 0.0
		if clutch_level > 0.0 and current_rpm > 0.0:
			if crank_frequency * 11.0 < nyquist:
				clutch_layer += clutch_level * sin(TAU_VALUE * 11.0 * phase_cycles)
			if crank_frequency * 17.0 < nyquist:
				clutch_layer += clutch_level * 0.32 * sin(TAU_VALUE * 17.0 * phase_cycles)
		var skid_layer: float = 0.0
		if _grounded_skid > 0.0:
			_skid_noise += 0.55 * (_next_noise() - _skid_noise)
			skid_layer = _grounded_skid * 0.065 * _skid_noise
		var transient_layer: float = 0.0
		if _transient > 0.0001 and current_rpm > 0.0:
			transient_layer = _transient * (0.055 * sin(TAU_VALUE * 7.0 * phase_cycles) + 0.045 * _next_noise())
		var sample: float = exhaust * engine_gain + crank_rattle + clutch_layer + skid_layer + transient_layer
		sample *= _gate
		sample = clampf(sample, -MAX_OUTPUT_PEAK, MAX_OUTPUT_PEAK)
		output[frame] = Vector2(sample, sample)
		last_clutch_level = maxf(last_clutch_level, absf(clutch_layer * _gate))
		last_skid_level = maxf(last_skid_level, absf(skid_layer * _gate))
		last_transient_level = maxf(last_transient_level, absf(transient_layer * _gate))
		if current_rpm > 0.0 and _gate > 0.0:
			phase_cycles = fposmod(phase_cycles + current_rpm / (60.0 * RATE), 1.0)
		_transient *= transient_decay
	return output


func is_sound_eligible() -> bool:
	return _is_sound_eligible()


## Restart output at silence without resetting the engine's oscillator phase.
func reset_output_fade() -> void:
	_gate = 0.0
	_transient = 0.0


func _is_sound_eligible() -> bool:
	return _engine_running and _fuel_kg > 0.0 and _target_rpm > 0.0 and _enabled and not _paused


func _grounded_slip_level(telemetry: Dictionary) -> float:
	var contact_value: Variant = telemetry.get("wheel_in_contact", null)
	var slip_speed_value: Variant = telemetry.get("wheel_slip_speed_m_per_s", null)
	var slip_ratio_value: Variant = telemetry.get("wheel_slip_ratio", null)
	if not contact_value is PackedByteArray:
		return 0.0
	var contacts: PackedByteArray = contact_value
	var slip_speeds: PackedFloat64Array = slip_speed_value if slip_speed_value is PackedFloat64Array else PackedFloat64Array()
	var slip_ratios: PackedFloat64Array = slip_ratio_value if slip_ratio_value is PackedFloat64Array else PackedFloat64Array()
	var count: int = contacts.size()
	var level: float = 0.0
	for wheel in count:
		if contacts[wheel] == 0:
			continue
		var speed_slip: float = 0.0
		var ratio_slip: float = 0.0
		if wheel < slip_speeds.size() and is_finite(slip_speeds[wheel]):
			speed_slip = clampf((absf(slip_speeds[wheel]) - 0.35) / 4.0, 0.0, 1.0)
		if wheel < slip_ratios.size() and is_finite(slip_ratios[wheel]):
			ratio_slip = clampf((absf(slip_ratios[wheel]) - 0.12) / 0.8, 0.0, 1.0)
		level = maxf(level, maxf(speed_slip, ratio_slip))
	return level


func _next_noise() -> float:
	_noise_state = int((_noise_state * 1103515245 + 12345) & 0x7fffffff)
	return float(_noise_state) / 1073741823.5 - 1.0


static func _finite_number(value: Variant, fallback: float) -> float:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return fallback
	var number: float = float(value)
	return number if is_finite(number) else fallback
