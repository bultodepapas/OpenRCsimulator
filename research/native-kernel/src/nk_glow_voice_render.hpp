// NK-7l: the glow voice's whole render_telemetry (app/audio/glow_voice.gd) from its detached telemetry: the snapshot
// parsing, the family switch, the physical phase anchor and its fire accounting, source_vibration_pcm_peaks and the
// block constants, then NK-6m's per-sample loop (nk_glow_voice.hpp). Doubles follow the GDScript line by line; every
// decimal literal comes from GlowVoice as GDScript parsed it (bind_constants), and engine math (exp, sqrt, absf) from
// the engine. A snapshot value whose GDScript conversion this does not reproduce (a non-bool `running`, a
// non-numeric `blade_count`, a non-bool `ok`) refuses, and GDScript renders that block. Audio only: nothing here
// reaches the simulation.
#pragma once

#include <cmath>
#include <cstdint>
#include <vector>

#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/variant.hpp>

#include "nk_glow_voice.hpp"
#include "nk_math.hpp"

namespace nk {
namespace voice {

// GlowVoice's literals as GDScript parsed them, in the order GlowVoice._RENDER_CONSTANTS packs them.
enum VoiceConstant : int {
	kVcRate,                  // RATE
	kVcFadeSeconds,           // FADE_SECONDS
	kVcTau,                   // TAU_VALUE
	kVcSourceGain,            // SOURCE_FORCE_PCM_GAIN
	kVcMaxSourcePeak,         // MAX_SOURCE_MECHANICAL_PEAK
	kVcEnvelopeFloor,         // _ENVELOPE_FLOOR
	kVcValveSecondWeight,     // _VALVE_SECOND_WEIGHT
	kVcPropellerSecondWeight, // _PROPELLER_SECOND_WEIGHT
	kVcPcmLimit,              // _PCM_LIMIT
	kVcDefaultMaxRpm,         // 12000.0
	kVcDefaultLoad,           // 0.45 (the load and throttle fallback)
	kVcAmplitudeGain,         // 0.34
	kVcAmplitudeBase,         // 0.65
	kVcAmplitudeLoad,         // 0.35
	kVcRatioLimit,            // 1.3
	kVcMechanicalGain,        // 0.055
	kVcMechanicalLoadBase,    // 0.55
	kVcMechanicalLoad,        // 0.45
	kVcMechanicalRatioBase,   // 0.55
	kVcMechanicalRatio,       // 0.45
	kVcValveGain,             // 0.042
	kVcValveBase,             // 0.65
	kVcValveRatio,            // 0.35
	kVcPropellerGain,         // 0.095
	kVcPropellerRatioBase,    // 0.35
	kVcPropellerRatio,        // 0.65
	kVcPropellerLoadBase,     // 0.7
	kVcPropellerLoad,         // 0.3
	kVcMechanicalSecond,      // 0.20
	kVcFireEpsilon,           // 1e-12
	kVcOmegaFloor,            // 1e-6
	kVcRelative,              // 1e-8 (omega and peak relative tolerances)
	kVcPeakFloor,             // 1e-8
	kVcConstantCount
};

// Voice state in and out, in the order GlowVoice._voice_state packs it.
enum VoiceState : int {
	kVsShaft,
	kVsScheduled,
	kVsAccumulator,
	kVsFires,
	kVsEnvelope,
	kVsPhaseAnchor,
	kVsPhysicalAnchor,
	kVsPhysicalOpportunities,
	kVsPhysicalFires,
	kVsSuppress,
	kVsLastFiringFraction,
	kVsFrequency,
	kVsAmplitude,
	kVsPhase,
	kVsCount
};

// The snapshot and source keys, owned by the kernel instance that renders (StringNames must not outlive the engine).
struct RenderKeys {
	godot::StringName family{"family"}, rpm{"rpm"}, max_rpm{"max_rpm"}, firing_fraction{"firing_fraction"},
		load{"load"}, throttle{"throttle"}, blade_count{"blade_count"}, running{"running"},
		source_vibration{"source_vibration"}, phase_revolutions{"phase_revolutions"},
		opportunity_count{"opportunity_count"}, fire_count{"fire_count"}, firing_accumulator{"firing_accumulator"},
		audio_queue_frames{"audio_queue_frames"}, fuel_kg{"fuel_kg"}, ok{"ok"}, constant_speed{"constant_speed_assumption"},
		cycle_revolutions{"cycle_revolutions"}, omega{"omega_rad_s"}, alpha{"alpha_rad_s2"}, phase{"phase_rad"},
		one_peak{"order_1x_force_peak_n"}, two_peak{"order_2x_force_peak_n"}, one_cosine{"order_1x_force_cosine_n"},
		one_sine{"order_1x_force_sine_n"}, two_cosine{"order_2x_force_cosine_n"}, two_sine{"order_2x_force_sine_n"};
	godot::String family_2t{"glow_2t"}, family_4t{"glow_4t"};
};

struct Bound {
	std::vector<double> c;
	std::vector<double> harmonics_2t;
	std::vector<double> harmonics_4t;
	bool ready = false;
};

inline bool is_number(const godot::Variant &v) {
	return v.get_type() == godot::Variant::INT || v.get_type() == godot::Variant::FLOAT;
}

inline double number(const godot::Variant &v) {
	return v.get_type() == godot::Variant::INT ? static_cast<double>(static_cast<int64_t>(v)) : static_cast<double>(v);
}

// GlowVoice._finite_nonnegative.
inline R finite_nonnegative(const godot::Variant &v, R fallback) {
	if (!is_number(v)) return fallback;
	const R value = number(v);
	return is_finite(value) ? maxf(value, R(0.0)) : fallback;
}

// The text of a String or StringName value; false for any other type.
inline bool text(const godot::Variant &v, godot::String &out) {
	if (v.get_type() == godot::Variant::STRING || v.get_type() == godot::Variant::STRING_NAME) {
		out = v;
		return true;
	}
	return false;
}

// source_vibration_pcm_peaks' ok and four order coefficients. -1: refuse (a value whose comparison GDScript makes with a
// different-type operand); 0: the failure result (zeros); 1: ok.
inline int source_peaks(const RenderKeys &k, const Bound &b, const godot::Variant &source, const godot::String &family,
		int cycle_revs, R rpm, R out[4]) {
	out[0] = out[1] = out[2] = out[3] = 0.0;
	if (source.get_type() != godot::Variant::DICTIONARY || !is_finite(rpm) || rpm.v < 0.0) return 0;
	const godot::Dictionary sv = source;
	if (cycle_revs == 0) return 0;
	const godot::Variant ok = sv.get(k.ok, false);
	if (ok.get_type() != godot::Variant::BOOL) return -1;
	if (!static_cast<bool>(ok)) return 0;
	const godot::Variant family_value = sv.get(k.family, godot::String());
	godot::String source_family;
	if (!text(family_value, source_family)) return -1;
	if (source_family != family) return 0;
	const godot::Variant constant = sv.get(k.constant_speed, false);
	if (constant.get_type() != godot::Variant::BOOL) return -1;
	if (!static_cast<bool>(constant)) return 0;
	const double *c = b.c.data();
	const godot::Variant cycle_value = sv.get(k.cycle_revolutions, godot::Variant());
	const godot::Variant omega_value = sv.get(k.omega, godot::Variant());
	const godot::Variant alpha_value = sv.get(k.alpha, godot::Variant());
	const godot::Variant phase_value = sv.get(k.phase, godot::Variant());
	if (!is_number(cycle_value) || !std::isfinite(number(cycle_value)) || number(cycle_value) != static_cast<double>(cycle_revs) ||
			!is_number(omega_value)) {
		return 0;
	}
	if (!is_number(alpha_value) || !std::isfinite(number(alpha_value)) || number(alpha_value) != 0.0 ||
			!is_number(phase_value) || !std::isfinite(number(phase_value)) || number(phase_value) < 0.0 ||
			number(phase_value) >= c[kVcTau]) {
		return 0;
	}
	const R expected_omega = rpm * R(c[kVcTau]) / R(60.0);
	const R source_omega = number(omega_value);
	if (!is_finite(source_omega) || source_omega.v < 0.0 ||
			godot::UtilityFunctions::absf((source_omega - expected_omega).v) >
				maxf(R(c[kVcOmegaFloor]), expected_omega * R(c[kVcRelative])).v) {
		return 0;
	}
	const godot::Variant values[6] = {sv.get(k.one_peak, godot::Variant()), sv.get(k.two_peak, godot::Variant()),
		sv.get(k.one_cosine, godot::Variant()), sv.get(k.one_sine, godot::Variant()), sv.get(k.two_cosine, godot::Variant()),
		sv.get(k.two_sine, godot::Variant())};
	for (const godot::Variant &value : values) {
		if (!is_number(value)) return 0;
	}
	const R force_one = number(values[0]), force_two = number(values[1]);
	const R one_cosine = number(values[2]), one_sine = number(values[3]);
	const R two_cosine = number(values[4]), two_sine = number(values[5]);
	if (!is_finite(force_one) || !is_finite(force_two) || force_one.v < 0.0 || force_two.v < 0.0 || !is_finite(one_cosine) ||
			!is_finite(one_sine) || !is_finite(two_cosine) || !is_finite(two_sine)) {
		return 0;
	}
	const R peak_one = godot::UtilityFunctions::sqrt((one_cosine * one_cosine + one_sine * one_sine).v);
	const R peak_two = godot::UtilityFunctions::sqrt((two_cosine * two_cosine + two_sine * two_sine).v);
	if (!is_finite(peak_one) || !is_finite(peak_two) ||
			godot::UtilityFunctions::absf((peak_one - force_one).v) > maxf(R(c[kVcPeakFloor]), force_one * R(c[kVcRelative])).v ||
			godot::UtilityFunctions::absf((peak_two - force_two).v) > maxf(R(c[kVcPeakFloor]), force_two * R(c[kVcRelative])).v) {
		return 0;
	}
	const R gain = c[kVcSourceGain];
	const R one = force_one * gain;
	const R two = force_two * gain;
	const R total = one + two;
	if (!is_finite(total)) return 0;
	const R limiter = total.v <= c[kVcMaxSourcePeak] ? R(1.0) : R(c[kVcMaxSourcePeak]) / total;
	out[0] = one_cosine * gain * limiter;
	out[1] = one_sine * gain * limiter;
	out[2] = two_cosine * gain * limiter;
	out[3] = two_sine * gain * limiter;
	return 1;
}

// GlowVoice._has_authoritative_cycle_state.
inline bool authoritative(const godot::Variant &phase, const godot::Variant &opportunities, const godot::Variant &fires,
		const godot::Variant &accumulator, int cycle_revs) {
	if (!is_number(phase) || !is_number(opportunities) || !is_number(fires) || !is_number(accumulator)) return false;
	const double p = number(phase), o = number(opportunities), f = number(fires), a = number(accumulator);
	return std::isfinite(p) && p >= 0.0 && p < static_cast<double>(cycle_revs) && std::isfinite(o) && o >= 0.0 &&
		o == std::floor(o) && std::isfinite(f) && f >= 0.0 && f <= o && f == std::floor(f) && std::isfinite(a) && a >= 0.0 &&
		a < 1.0;
}

// render_telemetry for `snapshot` and `frames` from `state` (VoiceState order) and the voice's last family. True with
// `pcm`, `next` and `last_family` set; false to refuse (the caller renders in GDScript, with its state untouched).
inline bool render(const RenderKeys &k, const Bound &b, const godot::Dictionary &snapshot, int64_t frames,
		const double *state, godot::String &last_family, godot::PackedVector2Array &pcm, double next[kVsCount]) {
	if (!b.ready || frames > (int64_t(1) << 20)) return false;
	for (int i = 0; i < kVsCount; ++i) next[i] = state[i];
	const int64_t frame_count = frames > 0 ? frames : 0;
	pcm.resize(frame_count);
	if (frame_count == 0) return true;
	const double *c = b.c.data();
	godot::String family;
	const godot::Variant family_value = snapshot.get(k.family, godot::String());
	const bool named = text(family_value, family);
	const int cycle_revs = !named ? 0 : family == k.family_2t ? 1 : family == k.family_4t ? 2 : 0;
	if (cycle_revs == 0) {
		last_family = godot::String();
		return true;
	}
	const R rpm = finite_nonnegative(snapshot.get(k.rpm, 0.0), R(0.0));
	R maximum = finite_nonnegative(snapshot.get(k.max_rpm, c[kVcDefaultMaxRpm]), R(c[kVcDefaultMaxRpm]));
	if (maximum.v <= 0.0) maximum = c[kVcDefaultMaxRpm];
	const R firing_fraction = clampf(finite_nonnegative(snapshot.get(k.firing_fraction, 1.0), R(1.0)), R(0.0), R(1.0));
	const godot::Variant load_value = snapshot.has(k.load) ? snapshot.get(k.load, godot::Variant())
		: snapshot.get(k.throttle, c[kVcDefaultLoad]);
	const R load = clampf(finite_nonnegative(load_value, R(c[kVcDefaultLoad])), R(0.0), R(1.0));
	const godot::Variant blades_value = snapshot.get(k.blade_count, int64_t(2));
	int64_t blades = 0;
	if (blades_value.get_type() == godot::Variant::INT) {
		blades = blades_value;
	} else if (blades_value.get_type() == godot::Variant::FLOAT && std::isfinite(static_cast<double>(blades_value)) &&
			std::fabs(static_cast<double>(blades_value)) < 9.0e18) {
		blades = static_cast<int64_t>(static_cast<double>(blades_value));
	} else {
		return false;
	}
	const int64_t blade_count = blades < 1 ? 1 : (blades > 8 ? 8 : blades);
	const godot::Variant running_value = snapshot.get(k.running, false);
	if (running_value.get_type() != godot::Variant::BOOL) return false;
	const bool running = running_value;
	R source[4];
	const int source_ok = source_peaks(k, b, snapshot.get(k.source_vibration, godot::Variant()), family, cycle_revs, rpm, source);
	if (source_ok < 0) return false;
	if (family != last_family) {
		next[kVsScheduled] = -1.0;
		next[kVsAccumulator] = 0.0;
		next[kVsFires] = 0.0;
		next[kVsPhysicalAnchor] = 0.0;
		next[kVsPhysicalOpportunities] = -1.0;
		next[kVsPhysicalFires] = -1.0;
		next[kVsSuppress] = 0.0;
		last_family = family;
	}
	next[kVsLastFiringFraction] = firing_fraction.v;
	const R rate = c[kVcRate];
	const R frequency = rpm / R(60.0);
	next[kVsFrequency] = frequency.v;
	const R amplitude = running ? R(c[kVcAmplitudeGain]) * (R(c[kVcAmplitudeBase]) + R(c[kVcAmplitudeLoad]) * load) : R(0.0);
	next[kVsAmplitude] = amplitude.v;
	const R shaft_step = rpm / (R(60.0) * rate);
	const godot::Variant external_phase = snapshot.get(k.phase_revolutions, godot::Variant());
	const godot::Variant opportunity_value = snapshot.get(k.opportunity_count, godot::Variant());
	const godot::Variant fire_value = snapshot.get(k.fire_count, godot::Variant());
	const godot::Variant accumulator_value = snapshot.get(k.firing_accumulator, godot::Variant());
	if (authoritative(external_phase, opportunity_value, fire_value, accumulator_value, cycle_revs)) {
		const int64_t opportunities = static_cast<int64_t>(number(opportunity_value));
		const int64_t fires = static_cast<int64_t>(number(fire_value));
		const R accumulator = number(accumulator_value);
		const R physical_phase = R(static_cast<double>(opportunities)) * R(static_cast<double>(cycle_revs)) + R(number(external_phase));
		const R queued = finite_nonnegative(snapshot.get(k.audio_queue_frames, 0.0), R(0.0));
		next[kVsShaft] = (physical_phase + rpm / R(60.0) * queued / rate).v;
		next[kVsScheduled] = static_cast<double>(opportunities);
		next[kVsAccumulator] = accumulator.v;
		const R firing_limit = finite_nonnegative(snapshot.get(k.firing_fraction, 1.0), R(1.0));
		const bool anchored = next[kVsPhysicalAnchor] != 0.0;
		const int64_t opportunity_delta = anchored ? opportunities - static_cast<int64_t>(next[kVsPhysicalOpportunities]) : 0;
		const int64_t fire_delta = anchored ? fires - static_cast<int64_t>(next[kVsPhysicalFires]) : 0;
		const bool recent = opportunities > 0 && fires > 0 &&
			(accumulator + R(c[kVcFireEpsilon])).v < clampf(firing_limit, R(0.0), R(1.0)).v;
		if (!running) {
			next[kVsFires] = 0.0;
			next[kVsSuppress] = 1.0;
		} else if (next[kVsSuppress] != 0.0) {
			if (opportunity_delta > 0) {
				next[kVsSuppress] = 0.0;
				next[kVsFires] = fire_delta > 0 ? 1.0 : 0.0;
			} else {
				next[kVsFires] = 0.0;
			}
		} else if (opportunity_delta > 0) {
			next[kVsFires] = (opportunity_delta == 1 ? fire_delta > 0 : recent) ? 1.0 : 0.0;
		} else {
			next[kVsFires] = recent ? 1.0 : 0.0;
		}
		next[kVsPhysicalAnchor] = 1.0;
		next[kVsPhysicalOpportunities] = static_cast<double>(opportunities);
		next[kVsPhysicalFires] = static_cast<double>(fires);
		next[kVsPhaseAnchor] = 1.0;
	} else if (next[kVsPhaseAnchor] == 0.0 && is_number(external_phase) && std::isfinite(number(external_phase))) {
		next[kVsShaft] = number(external_phase);
		next[kVsPhaseAnchor] = 1.0;
	}
	const R nyquist = rate * R(0.5);
	const R cycle_frequency = rpm / (R(60.0) * R(static_cast<double>(cycle_revs)));
	// blade_pass_frequency_hz (rpm is finite here).
	const R blade_frequency = maxf(rpm, R(0.0)) / R(60.0) * R(static_cast<double>(blade_count < 1 ? 1 : blade_count));
	const R ratio = clampf(rpm / maximum, R(0.0), R(c[kVcRatioLimit]));
	const R combustion_gain = amplitude;
	const R mechanical_gain = R(c[kVcMechanicalGain]) * (R(c[kVcMechanicalLoadBase]) + R(c[kVcMechanicalLoad]) * load) *
		(R(c[kVcMechanicalRatioBase]) + R(c[kVcMechanicalRatio]) * ratio);
	const R valve_gain = R(c[kVcValveGain]) * (R(c[kVcValveBase]) + R(c[kVcValveRatio]) * ratio);
	const R propeller_gain = R(c[kVcPropellerGain]) * (R(c[kVcPropellerRatioBase]) + R(c[kVcPropellerRatio]) * ratio) *
		(R(c[kVcPropellerLoadBase]) + R(c[kVcPropellerLoad]) * load);
	const R fade_alpha = R(1.0) - R(godot::UtilityFunctions::exp((R(-1.0) / (R(c[kVcFadeSeconds]) * rate)).v));
	const R cycle_revs_f = static_cast<double>(cycle_revs);
	const R opportunity_fraction = running && finite_nonnegative(snapshot.get(k.fuel_kg, 1.0), R(1.0)).v > 0.0
		? firing_fraction : R(0.0);
	const bool combustion_enabled = running && cycle_frequency.v > 0.0;
	const std::vector<double> &weights = family == k.family_2t ? b.harmonics_2t : b.harmonics_4t;
	double angles[64];
	double harmonic_weights[64];
	int64_t harmonic_count = 0;
	for (size_t index = 0; index < weights.size() && index < 64; ++index) {
		const double harmonic = static_cast<double>(index + 1);
		if ((cycle_frequency * R(harmonic)).v >= nyquist.v) break;
		angles[harmonic_count] = (R(c[kVcTau]) * R(harmonic)).v;
		harmonic_weights[harmonic_count] = weights[index];
		++harmonic_count;
	}
	const bool mechanical_enabled = rpm.v > 0.0 && frequency.v < nyquist.v;
	const bool mechanical_second = (frequency * R(2.0)).v < nyquist.v;
	const bool valve_enabled = family == k.family_4t && rpm.v > 0.0 && cycle_frequency.v < nyquist.v;
	const bool valve_second = (cycle_frequency * R(2.0)).v < nyquist.v;
	const bool propeller_enabled = blade_frequency.v > 0.0 && blade_frequency.v < nyquist.v;
	const bool propeller_second = (blade_frequency * R(2.0)).v < nyquist.v;
	const double parameters[kGvParameterCount] = {cycle_revs_f.v, firing_fraction.v, opportunity_fraction.v, fade_alpha.v,
		running ? 1.0 : 0.0, combustion_enabled ? 1.0 : 0.0, combustion_gain.v, c[kVcEnvelopeFloor],
		mechanical_enabled ? 1.0 : 0.0, source_ok > 0 ? 1.0 : 0.0, source[0].v, source[1].v, source[2].v, source[3].v,
		mechanical_second ? 1.0 : 0.0, mechanical_gain.v, (mechanical_gain * R(c[kVcMechanicalSecond])).v,
		valve_enabled ? 1.0 : 0.0, valve_gain.v, valve_second ? 1.0 : 0.0, c[kVcValveSecondWeight],
		propeller_enabled ? 1.0 : 0.0, propeller_gain.v, propeller_second ? 1.0 : 0.0, c[kVcPropellerSecondWeight],
		static_cast<double>(blade_count), shaft_step.v, c[kVcTau], (R(c[kVcTau]) * R(2.0)).v, c[kVcPcmLimit]};
	double loop[kGvStateCount] = {next[kVsShaft], next[kVsEnvelope], next[kVsScheduled], next[kVsAccumulator],
		next[kVsFires]};
	const bool scheduled_any = glow_voice_block(parameters, angles, harmonic_weights, harmonic_count, loop, frame_count,
		reinterpret_cast<float *>(pcm.ptrw()));
	next[kVsShaft] = loop[kGvShaft];
	next[kVsEnvelope] = loop[kGvEnvelope];
	next[kVsScheduled] = static_cast<double>(static_cast<int64_t>(loop[kGvScheduled]));
	next[kVsAccumulator] = loop[kGvAccumulator];
	next[kVsFires] = loop[kGvFires] != 0.0 ? 1.0 : 0.0;
	if (scheduled_any) next[kVsLastFiringFraction] = opportunity_fraction.v;
	next[kVsPhase] = gv_fposmod(R(next[kVsShaft]), R(1.0)).v;
	return true;
}

} // namespace voice
} // namespace nk
