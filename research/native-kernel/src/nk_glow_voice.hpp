// NK-6m: the glow voice's per-sample loop (app/audio/glow_voice.gd render_telemetry) in its operand order. The voice
// resolves every block constant, including its literals, and passes them in; this returns the PCM and the loop state.
// Audio only: nothing here reaches the simulation.
#pragma once

#include <cmath>
#include <cstdint>

#include "nk_math.hpp"

namespace nk {

// Block constants, in the order GlowVoice.native_block_parameters packs them.
enum GlowVoiceParameter : int {
	kGvCycleRevolutions,
	kGvFiringFraction,
	kGvOpportunityFraction,
	kGvFadeAlpha,
	kGvTargetEnvelope,
	kGvCombustionEnabled,
	kGvCombustionGain,
	kGvEnvelopeFloor,
	kGvMechanicalEnabled,
	kGvSourceOk,
	kGvSourceC1,
	kGvSourceS1,
	kGvSourceC2,
	kGvSourceS2,
	kGvMechanicalSecond,
	kGvMechanicalGain,
	kGvMechanicalSecondGain,
	kGvValveEnabled,
	kGvValveGain,
	kGvValveSecond,
	kGvValveSecondWeight,
	kGvPropellerEnabled,
	kGvPropellerGain,
	kGvPropellerSecond,
	kGvPropellerSecondWeight,
	kGvBladeCount,
	kGvShaftStep,
	kGvTau,
	kGvTauSecond,
	kGvClampLimit,
	kGvParameterCount
};

// Loop state in and out: shaft phase (cycles), combustion envelope, scheduled opportunity, firing accumulator, whether
// the scheduled opportunity fires (1/0); out also whether any opportunity was scheduled in the block (1/0).
enum GlowVoiceState : int { kGvShaft, kGvEnvelope, kGvScheduled, kGvAccumulator, kGvFires, kGvStateCount };

// Godot Math::fposmod(double, double).
inline R gv_fposmod(R x, R y) {
	double value = std::fmod(x.v, y.v);
	if ((value < 0.0 && y.v > 0.0) || (value > 0.0 && y.v < 0.0)) value = (R(value) + y).v;
	return R(value) + 0.0;
}

// out receives 2 * frames floats (left, right). Returns whether any opportunity was scheduled.
inline bool glow_voice_block(const double *p, const double *angles, const double *weights, int64_t harmonic_count,
		double *state, int64_t frames, float *out) {
	const R cycle_revs = p[kGvCycleRevolutions];
	const R firing_fraction = p[kGvFiringFraction];
	const R opportunity_fraction = p[kGvOpportunityFraction];
	const R fade_alpha = p[kGvFadeAlpha];
	const R target_envelope = p[kGvTargetEnvelope];
	const bool combustion_enabled = p[kGvCombustionEnabled] != 0.0;
	const R combustion_gain = p[kGvCombustionGain];
	const double envelope_floor = p[kGvEnvelopeFloor];
	const bool mechanical_enabled = p[kGvMechanicalEnabled] != 0.0;
	const bool source_ok = p[kGvSourceOk] != 0.0;
	const R c1 = p[kGvSourceC1], s1 = p[kGvSourceS1], c2 = p[kGvSourceC2], s2 = p[kGvSourceS2];
	const bool mechanical_second = p[kGvMechanicalSecond] != 0.0;
	const R mechanical_gain = p[kGvMechanicalGain];
	const R mechanical_second_gain = p[kGvMechanicalSecondGain];
	const bool valve_enabled = p[kGvValveEnabled] != 0.0;
	const R valve_gain = p[kGvValveGain];
	const bool valve_second = p[kGvValveSecond] != 0.0;
	const R valve_second_weight = p[kGvValveSecondWeight];
	const bool propeller_enabled = p[kGvPropellerEnabled] != 0.0;
	const R propeller_gain = p[kGvPropellerGain];
	const bool propeller_second = p[kGvPropellerSecond] != 0.0;
	const R propeller_second_weight = p[kGvPropellerSecondWeight];
	const R blade_count = p[kGvBladeCount];
	const R shaft_step = p[kGvShaftStep];
	const R tau = p[kGvTau];
	const R tau_second = p[kGvTauSecond];
	const R limit = p[kGvClampLimit];
	R shaft = state[kGvShaft];
	R envelope = state[kGvEnvelope];
	int64_t scheduled = static_cast<int64_t>(state[kGvScheduled]);
	R accumulator = state[kGvAccumulator];
	bool fires = state[kGvFires] != 0.0;
	bool scheduled_any = false;
	for (int64_t i = 0; i < frames; ++i) {
		const R cycle_position = shaft / cycle_revs;
		const int64_t opportunity = static_cast<int64_t>(std::floor(cycle_position.v));
		if (scheduled < 0) {
			accumulator = gv_fposmod(R(1.0) - firing_fraction, 1.0);
			scheduled = opportunity - 1;
		}
		while (scheduled < opportunity) {
			accumulator = accumulator + opportunity_fraction;
			fires = accumulator.v >= 1.0;
			if (fires) accumulator = accumulator - 1.0;
			scheduled_any = true;
			scheduled += 1;
		}
		const R cycle_phase = gv_fposmod(cycle_position, 1.0);
		envelope = envelope + fade_alpha * (target_envelope - envelope);
		R combustion = 0.0;
		if (combustion_enabled && fires && envelope.v > envelope_floor) {
			R wave = 0.0;
			for (int64_t k = 0; k < harmonic_count; ++k) wave = wave + R(weights[k]) * sin_(R(angles[k]) * cycle_phase);
			combustion = wave * combustion_gain * envelope;
		}
		R mechanical = 0.0;
		if (mechanical_enabled) {
			const R crank_phase = gv_fposmod(shaft, 1.0);
			if (source_ok) {
				const R crank_angle = tau * crank_phase;
				mechanical = c1 * cos_(crank_angle) + s1 * sin_(crank_angle);
				if (mechanical_second) {
					mechanical = mechanical + (c2 * cos_(R(2.0) * crank_angle) + s2 * sin_(R(2.0) * crank_angle));
				}
			} else {
				mechanical = mechanical_gain * sin_(tau * crank_phase);
				if (mechanical_second) mechanical = mechanical + mechanical_second_gain * sin_(tau_second * crank_phase);
			}
		}
		R valve = 0.0;
		if (valve_enabled) {
			const R second = valve_second ? sin_(tau_second * cycle_phase) : R(0.0);
			valve = valve_gain * (sin_(tau * cycle_phase) + valve_second_weight * second);
		}
		R propeller = 0.0;
		if (propeller_enabled) {
			const R blade_phase = gv_fposmod(shaft * blade_count, 1.0);
			const R second = propeller_second ? sin_(tau_second * blade_phase) : R(0.0);
			propeller = propeller_gain * (sin_(tau * blade_phase) + propeller_second_weight * second);
		}
		const R sample = clampf(combustion + mechanical + valve + propeller, -limit, limit);
		out[2 * i] = static_cast<float>(sample.v);
		out[2 * i + 1] = static_cast<float>(sample.v);
		shaft = shaft + shaft_step;
	}
	state[kGvShaft] = shaft.v;
	state[kGvEnvelope] = envelope.v;
	state[kGvScheduled] = static_cast<double>(scheduled);
	state[kGvAccumulator] = accumulator.v;
	state[kGvFires] = fires ? 1.0 : 0.0;
	return scheduled_any;
}

} // namespace nk
