// NK-6n: GlowFlight.finish (app/physics/glow/flight.gd) for a steady tick: the bounded ResourceStep result carries no
// events and no transitions, the engine command holds, no failure is injected and the prepared lifecycle evaluator
// decides. Then finish only accepts the integrated candidate (lifecycle.gd _accepted_validated and
// count_opportunities): two fractions clamped, the phase wrapped, opportunities counted, the lifecycle mode kept.
// Every check that would fail, stop the engine or need another branch returns false, and the caller runs finish.
#pragma once

#include <cmath>
#include <cstdint>
#include <vector>

#include "nk_glow_voice.hpp"
#include "nk_math.hpp"

namespace nk {

// The plan's steady terms, as GDScript parses them (FlightSession._native_glow_finish_terms).
enum GlowFinishTerm : int {
	kGfIdentityCycle,
	kGfFamilyCycle,
	kGfMaxRpm,
	kGfStallRpm,
	kGfHotZeroK,
	kGfFuelRise, // _accepted_validated's 1.0e-14
	kGfFraction, // its servo and air bound, 1.0e-12
	kGfPhaseTolerance,
	kGfFireTolerance,
	kGfTermCount
};

constexpr int kGlowValuesSize = 19; // GlowFlight.SIZE
constexpr int kGlowReasonCount = 7; // GlowFlight.REASONS

// start and end: the combined start state and the bounded end state (body, then the glow values and any wheels).
// firing: the endpoint's firing fraction (GlowFlight._firing_sample). Writes finish's state to out.
inline bool glow_steady_finish(const std::vector<R> &start, const std::vector<R> &end, int body_size, double dt,
		const double *terms, double firing, std::vector<R> &out) {
	const size_t n = start.size();
	if (end.size() != n || n < static_cast<size_t>(body_size + kGlowValuesSize)) return false;
	const double cycle = terms[kGfFamilyCycle];
	if (!(cycle == 1.0 || cycle == 2.0) || terms[kGfIdentityCycle] != cycle) return false;
	for (int i = kGfMaxRpm; i < kGfTermCount; ++i) {
		if (!std::isfinite(terms[i])) return false;
	}
	// GlowFlight.unpack of both stores: every value finite, a binary running flag and a known stop reason.
	for (size_t i = static_cast<size_t>(body_size); i < n; ++i) {
		if (!is_finite(start[i]) || !is_finite(end[i])) return false;
	}
	const R *b = start.data() + body_size;
	const R *c = end.data() + body_size;
	auto flags = [](const R *v) {
		return (v[7].v == 0.0 || v[7].v == 1.0) && v[8].v == std::floor(v[8].v) && v[8].v >= 0.0 &&
			v[8].v < static_cast<double>(kGlowReasonCount);
	};
	if (!flags(b) || !flags(c)) return false;
	auto counter = [](double v, int64_t &out) {
		if (!(std::fabs(v) < 4.0e18)) return false;
		out = static_cast<int64_t>(v); // GDScript int(float) truncates toward zero
		return true;
	};
	int64_t before_opportunities = 0, before_fires = 0, after_opportunities = 0, after_fires = 0;
	if (!counter(b[9].v, before_opportunities) || !counter(b[10].v, before_fires) ||
			!counter(c[9].v, after_opportunities) || !counter(c[10].v, after_fires)) return false;
	// lifecycle.gd _state_error: before as an accepted state, the candidate with its stage allowances.
	auto common = [](const R *v, int64_t opportunities, int64_t fires) {
		return opportunities >= 0 && fires >= 0 && fires <= opportunities && v[11].v >= 0.0 && v[11].v < 1.0 &&
			v[2].v > 0.0 && v[6].v >= 0.0;
	};
	if (!common(b, before_opportunities, before_fires) || !common(c, after_opportunities, after_fires)) return false;
	if (b[1].v < 0.0 || b[5].v < 0.0) return false;
	// _accepted_validated's argument and candidate checks (finish passes no unusable reserve).
	if (!std::isfinite(dt) || dt < 0.0) return false;
	const double max_rpm = terms[kGfMaxRpm];
	const double rpm_before = b[0].v;
	const double rpm_after = c[0].v;
	if (rpm_before < 0.0 || rpm_after < 0.0 || rpm_before > max_rpm || rpm_after > max_rpm) return false;
	if (!std::isfinite(firing) || firing < 0.0 || firing > 1.0) return false;
	if (c[1].v < minf(R(0.0), b[1]).v) return false;
	if (c[1].v > (b[1] + terms[kGfFuelRise]).v) return false;
	if (c[2].v <= 0.0 || c[5].v < 0.0) return false;
	const double low = -terms[kGfFraction];
	const double high = (R(1.0) + terms[kGfFraction]).v;
	if (c[3].v < low || c[3].v > high || c[4].v < low || c[4].v > high) return false;
	if (c[6].v < (b[6] - terms[kGfPhaseTolerance]).v) return false;
	const bool running = b[7].v == 1.0;
	// Each lifecycle stop the reference would decide (fuel exhausted, overheat, stall) stays with it.
	if (running && (b[1].v <= 0.0 || c[1].v == 0.0 || c[2].v >= terms[kGfHotZeroK] || rpm_after <= terms[kGfStallRpm])) {
		return false;
	}
	// count_opportunities over (before phase, candidate phase].
	const double probability = running && b[1].v > 0.0 ? firing : 0.0;
	const double start_turn = std::floor(((b[6] + terms[kGfPhaseTolerance]) / cycle).v);
	const double end_turn = std::floor(((c[6] + terms[kGfPhaseTolerance]) / cycle).v);
	if (!(std::fabs(start_turn) < 4.0e18) || !(std::fabs(end_turn) < 4.0e18)) return false;
	const int64_t delta = static_cast<int64_t>(end_turn) - static_cast<int64_t>(start_turn);
	if (delta < 0 || delta > 64) return false;
	const double fire_at = (R(1.0) - terms[kGfFireTolerance]).v;
	R accumulator = b[11];
	int64_t fires = 0;
	for (int64_t k = 0; k < delta; ++k) {
		accumulator = accumulator + probability;
		if (probability > 0.0 && accumulator.v >= fire_at) {
			accumulator = maxf(R(0.0), accumulator - 1.0);
			++fires;
		}
	}
	// GlowFlight.put_state of the accepted state into the end values; the body and every other value are the end's.
	out = end;
	R *o = out.data() + body_size;
	o[3] = clampf(c[3], 0.0, 1.0);
	o[4] = clampf(c[4], 0.0, 1.0);
	o[6] = gv_fposmod(c[6], cycle);
	o[7] = running ? 1.0 : 0.0;
	o[8] = static_cast<double>(static_cast<int64_t>(b[8].v));
	o[9] = static_cast<double>(before_opportunities + delta);
	o[10] = static_cast<double>(before_fires + fires);
	o[11] = accumulator;
	return true;
}

} // namespace nk
