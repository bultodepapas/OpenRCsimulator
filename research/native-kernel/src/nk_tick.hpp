// NK-6a: the C++ twin of Simulation.step's legacy joint integration (app/sim/simulation.gd):
// rigid_body.gd `derivative`, integrator.gd `rk4_step_at`, Simulation `_rk4_substeps` and `_locate_substeps`,
// event_step.gd `advance` and event_bracket.gd `propose`. Every operation keeps the GDScript order, literals and
// helper semantics (nk_math.hpp). The stage derivative `f(s, t, out)` returns false once it has recorded a stage
// error: the reference then finishes the tick on zero derivatives without another callback and refuses it with that
// error, so the port stops there (TickStatus::Abort). Event transitions are pure owner callbacks.
#pragma once

#include <array>
#include <cstdint>
#include <vector>

#include "nk_math.hpp"

namespace nk {

constexpr int kTickBody = 13;
constexpr int kTickVel = 3;
constexpr int kTickAtt = 6;
constexpr int kTickRate = 10;
// simulation.gd MIN_QUATERNION_NORM_SQ := 1e-24 (the GDScript spelling, nk_math.hpp), EVENT_TIME_SLACK_S := 1e-9,
// MAX_SUBSTEPS := 16.
constexpr double kTickMinQuaternionNormSq = kGd1eMinus24;
constexpr double kTickEventTimeSlack = 1e-9;
constexpr int kTickMaxSubsteps = 16;
// event_step.gd
constexpr double kEventTimeTol = 1e-12;
constexpr double kEventValueTol = 1e-7;
constexpr int kEventMaxSegments = 128;
constexpr int kEventMaxRootTrials = 128;
constexpr double kEventMaxDt = 60.0;

enum class TickStatus { Ok, Fail, Abort };

inline bool tick_finite(const R *values, int count) {
	for (int i = 0; i < count; ++i) {
		if (!is_finite(values[i])) return false;
	}
	return true;
}

// Simulation.state_is_valid on 13 values.
inline bool tick_body_valid(const R *s) {
	if (!tick_finite(s, kTickBody)) return false;
	const int a = kTickAtt;
	const R norm_sq = s[a] * s[a] + s[a + 1] * s[a + 1] + s[a + 2] * s[a + 2] + s[a + 3] * s[a + 3];
	return is_finite(norm_sq) && norm_sq.v > kTickMinQuaternionNormSq;
}

// rigid_body.gd `derivative` (H3 scalars). `l` holds the six loads; `h_rotor` may be null (empty).
inline void tick_rb_derivative(const R *s, R mass, const R *j, const R *j_inv, const R *l, R g, const R *h_rotor,
		R *out) {
	const R v0 = s[kTickVel], v1 = s[kTickVel + 1], v2 = s[kTickVel + 2];
	const R q0 = s[kTickAtt], q1 = s[kTickAtt + 1], q2 = s[kTickAtt + 2], q3 = s[kTickAtt + 3];
	const R w0 = s[kTickRate], w1 = s[kTickRate + 1], w2 = s[kTickRate + 2];

	const R t0 = (q2 * v2 - q3 * v1) * R(2.0);
	const R t1 = (q3 * v0 - q1 * v2) * R(2.0);
	const R t2 = (q1 * v1 - q2 * v0) * R(2.0);
	const R pn = (v0 + t0 * q0) + (q2 * t2 - q3 * t1);
	const R pe = (v1 + t1 * q0) + (q3 * t0 - q1 * t2);
	const R pd = (v2 + t2 * q0) + (q1 * t1 - q2 * t0);

	const R n1 = -q1;
	const R n2 = -q2;
	const R n3 = -q3;
	const R g0 = (n2 * g - n3 * R(0.0)) * R(2.0);
	const R g1 = (n3 * R(0.0) - n1 * g) * R(2.0);
	const R g2 = (n1 * R(0.0) - n2 * R(0.0)) * R(2.0);
	const R gx = (R(0.0) + g0 * q0) + (n2 * g2 - n3 * g1);
	const R gy = (R(0.0) + g1 * q0) + (n3 * g0 - n1 * g2);
	const R gz = (g + g2 * q0) + (n1 * g1 - n2 * g0);

	const R k = R(1.0) / mass;
	const R ud = (l[0] * k + gx) - (w1 * v2 - w2 * v1);
	const R vd = (l[1] * k + gy) - (w2 * v0 - w0 * v2);
	const R wd = (l[2] * k + gz) - (w0 * v1 - w1 * v0);

	const R qd0 = (q0 * R(0.0) - q1 * w0 - q2 * w1 - q3 * w2) * R(0.5);
	const R qd1 = (q0 * w0 + q1 * R(0.0) + q2 * w2 - q3 * w1) * R(0.5);
	const R qd2 = (q0 * w1 - q1 * w2 + q2 * R(0.0) + q3 * w0) * R(0.5);
	const R qd3 = (q0 * w2 + q1 * w1 - q2 * w0 + q3 * R(0.0)) * R(0.5);

	R h0 = j[0] * w0 + j[3] * w1 + j[4] * w2;
	R h1 = j[3] * w0 + j[1] * w1 + j[5] * w2;
	R h2 = j[4] * w0 + j[5] * w1 + j[2] * w2;
	if (h_rotor != nullptr) {
		h0 = h0 + h_rotor[0];
		h1 = h1 + h_rotor[1];
		h2 = h2 + h_rotor[2];
	}
	const R m0 = l[3] - (w1 * h2 - w2 * h1);
	const R m1 = l[4] - (w2 * h0 - w0 * h2);
	const R m2 = l[5] - (w0 * h1 - w1 * h0);

	out[0] = pn;
	out[1] = pe;
	out[2] = pd;
	out[3] = ud;
	out[4] = vd;
	out[5] = wd;
	out[6] = qd0;
	out[7] = qd1;
	out[8] = qd2;
	out[9] = qd3;
	out[10] = j_inv[0] * m0 + j_inv[3] * m1 + j_inv[4] * m2;
	out[11] = j_inv[3] * m0 + j_inv[1] * m1 + j_inv[5] * m2;
	out[12] = j_inv[4] * m0 + j_inv[5] * m1 + j_inv[2] * m2;
}

// Buffers for one RK4 step over n values; a step never nests inside another.
struct TickRk4Scratch {
	std::vector<R> k1, k2, k3, k4, trial;
	void size(int n) {
		k1.resize(static_cast<size_t>(n));
		k2.resize(static_cast<size_t>(n));
		k3.resize(static_cast<size_t>(n));
		k4.resize(static_cast<size_t>(n));
		trial.resize(static_cast<size_t>(n));
	}
};

// integrator.gd `rk4_step_at` with its axpy, _finish_step and normalize_attitude. `k1_given` may be null.
// `out` may alias `s` only after every stage has read it, so it must not; callers pass distinct buffers.
template <class F>
inline TickStatus tick_rk4_step_at(const R *s, int n, R t, R dt, F &f, const R *k1_given, R *out,
		TickRk4Scratch &sc) {
	const R *k1 = k1_given;
	if (k1 == nullptr) {
		if (!f(s, t, sc.k1.data())) return TickStatus::Abort;
		k1 = sc.k1.data();
	}
	const R half = dt / R(2.0);
	for (int i = 0; i < n; ++i) sc.trial[static_cast<size_t>(i)] = s[i] + half * k1[i];
	if (!f(sc.trial.data(), t + dt / R(2.0), sc.k2.data())) return TickStatus::Abort;
	const R half_again = dt / R(2.0);
	for (int i = 0; i < n; ++i) sc.trial[static_cast<size_t>(i)] = s[i] + half_again * sc.k2[static_cast<size_t>(i)];
	if (!f(sc.trial.data(), t + dt / R(2.0), sc.k3.data())) return TickStatus::Abort;
	for (int i = 0; i < n; ++i) sc.trial[static_cast<size_t>(i)] = s[i] + dt * sc.k3[static_cast<size_t>(i)];
	if (!f(sc.trial.data(), t + dt, sc.k4.data())) return TickStatus::Abort;
	for (int i = 0; i < n; ++i) {
		const size_t u = static_cast<size_t>(i);
		out[i] = s[i] + dt / R(6.0) * (k1[i] + R(2.0) * sc.k2[u] + R(2.0) * sc.k3[u] + sc.k4[u]);
	}
	const int a = kTickAtt;
	const R norm = sqrt_(out[a] * out[a] + out[a + 1] * out[a + 1] + out[a + 2] * out[a + 2] + out[a + 3] * out[a + 3]);
	for (int i = 0; i < 4; ++i) out[a + i] = out[a + i] / norm;
	return TickStatus::Ok;
}

// Simulation `_rk4_substeps`: n full RK4 pieces of dt/n; the first reuses the tick's k1. `out` holds the result.
template <class F>
inline TickStatus tick_rk4_substeps(const R *combined, int size, R t, R dt_tick, F &f, const R *first, int pieces,
		std::vector<R> &out, TickRk4Scratch &sc) {
	std::vector<R> current(combined, combined + size);
	std::vector<R> k1(static_cast<size_t>(size));
	const R piece = dt_tick / R(static_cast<double>(pieces));
	R elapsed = 0.0;
	out.resize(static_cast<size_t>(size));
	for (int i = 0; i < pieces; ++i) {
		const R *given = first;
		if (i != 0) {
			if (!f(current.data(), t + elapsed, k1.data())) return TickStatus::Abort;
			given = k1.data();
		}
		const TickStatus status = tick_rk4_step_at(current.data(), size, t + elapsed, piece, f, given, out.data(), sc);
		if (status != TickStatus::Ok) return status;
		current = out;
		elapsed = elapsed + piece;
	}
	return TickStatus::Ok;
}

// event_bracket.gd `propose`.
inline R tick_bracket_propose(R lo, R hi, R value_lo, R value_hi, R time_tolerance, bool bisect) {
	if (!is_finite(lo) || !is_finite(hi) || lo.v < 0.0 || hi.v <= lo.v || !is_finite(value_lo) || value_lo.v <= 0.0 ||
			!is_finite(value_hi) || value_hi.v > 0.0 || !is_finite(time_tolerance) || time_tolerance.v <= 0.0) {
		return kNan;
	}
	const R width = hi - lo;
	const R midpoint = lo + R(0.5) * width;
	if (midpoint.v <= lo.v || midpoint.v >= hi.v) return kNan;
	if (bisect) return midpoint;
	const R scale = maxf(value_lo, -value_hi);
	const R positive = value_lo / scale;
	const R negative = -value_hi / scale;
	const R fraction = positive / (positive + negative);
	const R gap = minf(R(0.5) * time_tolerance, R(0.25) * width);
	const R proposed = clampf(lo + fraction * width, lo + gap, hi - gap);
	return is_finite(proposed) && proposed.v > lo.v && proposed.v < hi.v ? proposed : midpoint;
}

// One event_step.gd `_trial`: an RK4 step through the tracked derivative.
struct TickEventTrial {
	std::vector<R> state;
	R minimum = 0.0;
	R max_rate = 0.0;
	bool ok = false;
};

template <class F>
inline TickStatus tick_event_trial(const R *s, int size, R t, R h, F &f, const R *first, int index,
		TickEventTrial &result, TickRk4Scratch &sc) {
	std::vector<R> initial_buffer;
	const R *initial = first;
	if (initial == nullptr) {
		initial_buffer.resize(static_cast<size_t>(size));
		if (!f(s, t, initial_buffer.data())) return TickStatus::Abort;
		initial = initial_buffer.data();
	}
	if (!tick_finite(initial, size)) {
		result.ok = false;
		return TickStatus::Ok;
	}
	R minimum = s[index];
	R max_rate = initial[index];
	bool valid = true;
	std::vector<R> evaluation(static_cast<size_t>(size));
	auto tracked = [&](const R *values, R at, R *rate) -> bool {
		minimum = minf(minimum, values[index]);
		const R *query = values;
		if (s[index].v > 0.0 && values[index].v == 0.0) {
			// Use the moving-side limit when a trial lands exactly on the boundary (a derivative query only).
			for (int i = 0; i < size; ++i) evaluation[static_cast<size_t>(i)] = values[i];
			evaluation[static_cast<size_t>(index)] = R(kEventValueTol) * R(0.01);
			query = evaluation.data();
		}
		if (!f(query, at, rate)) return false;
		if (!tick_finite(rate, size)) {
			valid = false;
			for (int i = 0; i < size; ++i) rate[i] = 0.0;
		}
		max_rate = maxf(max_rate, rate[index]);
		return true;
	};
	result.state.resize(static_cast<size_t>(size));
	const TickStatus status = tick_rk4_step_at(s, size, t, h, tracked, initial, result.state.data(), sc);
	if (status != TickStatus::Ok) return status;
	result.ok = valid && tick_finite(result.state.data(), size);
	result.minimum = minf(minimum, result.state[static_cast<size_t>(index)]);
	result.max_rate = max_rate;
	return TickStatus::Ok;
}

// event_step.gd `_locate_crossing`. On Ok with `located`, `high` and `offset` hold the located state and time.
template <class F>
inline TickStatus tick_event_locate_crossing(const R *start, int size, R time_s, R dt, F &f, const R *first,
		int index, const std::vector<R> &high_state, bool &located, std::vector<R> &high, R &offset,
		TickRk4Scratch &sc) {
	located = false;
	R lo = 0.0;
	R hi = dt;
	R low_value = start[index];
	high = high_state;
	bool bisect = false;
	TickEventTrial trial;
	for (int iteration = 0; iteration < kEventMaxRootTrials; ++iteration) {
		if ((hi - lo).v <= kEventTimeTol && high[static_cast<size_t>(index)].v <= 0.0 &&
				absf(high[static_cast<size_t>(index)]).v <= kEventValueTol) {
			located = true;
			offset = hi;
			return TickStatus::Ok;
		}
		const R old_width = hi - lo;
		const R mid = tick_bracket_propose(lo, hi, low_value, high[static_cast<size_t>(index)], kEventTimeTol, bisect);
		if (!is_finite(mid)) break;
		const TickStatus status = tick_event_trial(start, size, time_s, mid, f, first, index, trial, sc);
		if (status != TickStatus::Ok) return status;
		if (!trial.ok) return TickStatus::Ok;
		const R value = trial.state[static_cast<size_t>(index)];
		if (value.v > 0.0) {
			lo = mid;
			low_value = value;
		} else {
			hi = mid;
			high = trial.state;
		}
		bisect = !bisect && (hi - lo).v > (R(0.5) * old_width).v;
	}
	if ((hi - lo).v <= kEventTimeTol && high[static_cast<size_t>(index)].v <= 0.0 &&
			absf(high[static_cast<size_t>(index)]).v <= kEventValueTol) {
		located = true;
		offset = hi;
	}
	return TickStatus::Ok;
}

// event_step.gd `advance` (strict_clock false). `transition(in, index, out)` returns false when the owner's
// callback did not return a packed float64 array; `out` may have any size. On Ok, `ok` reports the locator's
// own verdict; `state` and `event_times` hold its result.
template <class F, class T>
inline TickStatus tick_event_advance(const R *s, int size, R time_s, R dt, F &f, const R *first, int index,
		T &transition, bool transition_valid, bool &ok, std::vector<R> &state, std::vector<R> &event_times,
		TickRk4Scratch &sc) {
	ok = false;
	if (index < kTickBody || index >= size || !tick_finite(s, size) || s[index].v < 0.0 || !is_finite(time_s) ||
			!is_finite(dt) || dt.v <= 0.0 || dt.v > kEventMaxDt || !is_finite(time_s + dt) || !transition_valid ||
			(first != nullptr && !tick_finite(first, size))) {
		return TickStatus::Ok;
	}
	state.assign(s, s + size);
	R elapsed = 0.0;
	R step = dt;
	const R *initial = first;
	TickEventTrial probe;
	std::vector<R> projected, high;
	for (int segment = 0; segment < kEventMaxSegments; ++segment) {
		TickStatus status = tick_event_trial(state.data(), size, time_s + elapsed, step, f, initial, index, probe, sc);
		if (status != TickStatus::Ok) return status;
		if (!probe.ok) return TickStatus::Ok;
		const std::vector<R> &candidate = probe.state;
		const R state_value = state[static_cast<size_t>(index)];
		const R candidate_value = candidate[static_cast<size_t>(index)];
		if (candidate_value.v == 0.0 && state_value.v > 0.0 && probe.max_rate.v <= 0.0) {
			if (!transition(candidate.data(), size, index, projected)) return TickStatus::Ok;
			if (static_cast<int>(projected.size()) != size || !tick_finite(projected.data(), size) ||
					projected[static_cast<size_t>(index)].v != 0.0) {
				return TickStatus::Ok;
			}
			state = projected;
			elapsed = elapsed + step;
			event_times.push_back(time_s + elapsed);
			if (elapsed.v >= dt.v) {
				ok = true;
				return TickStatus::Ok;
			}
			step = dt - elapsed;
			initial = nullptr;
			continue;
		}
		if (candidate_value.v <= 0.0 && state_value.v > 0.0 && probe.max_rate.v <= 0.0) {
			bool located = false;
			R crossing = 0.0;
			const std::vector<R> candidate_copy = candidate;
			status = tick_event_locate_crossing(state.data(), size, time_s + elapsed, step, f, initial, index,
				candidate_copy, located, high, crossing, sc);
			if (status != TickStatus::Ok) return status;
			if (!located) return TickStatus::Ok;
			if (!transition(high.data(), size, index, projected)) return TickStatus::Ok;
			if (static_cast<int>(projected.size()) != size || !tick_finite(projected.data(), size) ||
					projected[static_cast<size_t>(index)].v != 0.0) {
				return TickStatus::Ok;
			}
			state = projected;
			elapsed = elapsed + crossing;
			event_times.push_back(time_s + elapsed);
		} else if (probe.minimum.v < 0.0) {
			// An internal crossing without a negative endpoint needs a smaller trial.
			step = step * R(0.5);
			if (step.v < kEventTimeTol) return TickStatus::Ok;
			continue;
		} else {
			state = candidate;
			elapsed = elapsed + step;
		}
		if (elapsed.v >= dt.v) {
			ok = true;
			return TickStatus::Ok;
		}
		step = dt - elapsed;
		initial = nullptr;
	}
	return TickStatus::Ok;
}

// Simulation `_locate_substeps`: the declared-event locator over n pieces of dt/n; events keep absolute times.
template <class F, class T>
inline TickStatus tick_locate_substeps(const R *combined, int size, R t, R dt_tick, F &f, const R *first, int index,
		T &transition, bool transition_valid, int pieces, bool &ok, std::vector<R> &out,
		std::vector<R> &event_times, TickRk4Scratch &sc) {
	ok = false;
	std::vector<R> current(combined, combined + size);
	std::vector<R> located;
	const R piece = dt_tick / R(static_cast<double>(pieces));
	R elapsed = 0.0;
	for (int i = 0; i < pieces; ++i) {
		bool piece_ok = false;
		const TickStatus status = tick_event_advance(current.data(), size, t + elapsed, piece, f,
			i == 0 ? first : nullptr, index, transition, transition_valid, piece_ok, located, event_times, sc);
		if (status != TickStatus::Ok) return status;
		if (!piece_ok) return TickStatus::Ok;
		current = located;
		elapsed = elapsed + piece;
	}
	out = current;
	ok = true;
	return TickStatus::Ok;
}

} // namespace nk
