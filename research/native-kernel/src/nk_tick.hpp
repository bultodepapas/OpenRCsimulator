// NK-6a: the C++ twin of Simulation.step's legacy joint integration (app/sim/simulation.gd):
// rigid_body.gd `derivative`, integrator.gd `rk4_step_at`, Simulation `_rk4_substeps` and `_locate_substeps`,
// event_step.gd `advance` and event_bracket.gd `propose`. Every operation keeps the GDScript order, literals and
// helper semantics (nk_math.hpp). The stage derivative `f(s, t, out)` returns false once it has recorded a stage
// error: the reference then finishes the tick on zero derivatives without another callback and refuses it with that
// error, so the port stops there (TickStatus::Abort). Event transitions are pure owner callbacks.
#pragma once

#include <algorithm>
#include <array>
#include <cstdint>
#include <string>
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

// ---------------------------------------------------------------------------------------------------------------
// NK-6c: the finite-pack electric step policy (FlightSession._electric_step): electric_battery_step.gd `advance`
// (rotor stop composed with battery-exhaustion localization), electric_stop.gd and electric_contact_step.gd
// `advance` (contact pieces). Failure messages are not ported: every failure makes the policy return [NAN].

// electric_battery_step.gd: TIME_TOL 1e-12, CHARGE_TOL_C 1e-10, LEFT_LIMIT_CHARGE_C 1e-30 (the GDScript spelling,
// nk_math.hpp), MAX_DT_S 60.0, MAX_SEGMENTS 128, MAX_REFINEMENTS 64, MAX_ROOT_TRIALS 128, BODY_RATE_INDEX 10.
constexpr double kBatteryTimeTol = 1e-12;
constexpr double kBatteryChargeTol = 1e-10;
constexpr double kBatteryLeftLimit = kGd1eMinus30;
constexpr double kBatteryMaxDt = 60.0;
constexpr int kBatteryMaxSegments = 128;
constexpr int kBatteryMaxRefinements = 64;
constexpr int kBatteryMaxRootTrials = 128;
// electric_contact_step.gd: MAX_PIECES 16, MAX_EVENTS 128, EVENT_WINDOW_SLACK_S 1e-9, FLOAT64_EPSILON.
constexpr int kContactMaxPieces = 16;
constexpr int kContactMaxEvents = 128;
constexpr double kContactWindowSlack = 1e-9;
constexpr double kFloat64Epsilon = 2.220446049250313e-16;

// One {type, time_s[, charge_residual_c, time_error_bound_s]} event of the battery composition.
struct TickPolicyEvent {
	bool battery = false; // false: "rotor_stop"; true: "battery_exhausted"
	R time_s = 0.0;
	R residual_c = 0.0;
	R time_error_s = 0.0;
};

struct TickBatteryTrial {
	bool ok = false;
	std::vector<R> state;
	std::vector<R> rotor_times;
	R minimum_charge = 0.0;
};

// electric_battery_step.gd `_stop_trial`. `project(in, count, index, out)` returns false when the owner's callback did
// not return a packed float64 array. Its tracker's failures continue the integration as the reference does.
template <class F, class P>
inline TickStatus tick_battery_stop_trial(const R *start, int size, R time_s, R dt, F &f, const R *first, int rpm,
		int charge, P &project, bool connected, TickBatteryTrial &out, TickRk4Scratch &sc) {
	out.ok = false;
	bool tracker_ok = true;
	R minimum = start[charge];
	const bool start_connected = connected && start[charge].v > 0.0;
	if (first != nullptr && first[charge].v > 0.0) return TickStatus::Ok;
	if (first != nullptr && !connected && first[charge].v != 0.0) return TickStatus::Ok;
	std::vector<R> evaluated(static_cast<size_t>(size));
	auto tracked = [&](const R *values, R at, R *rate) -> bool {
		if (!tick_finite(values, size)) {
			tracker_ok = false;
			for (int i = 0; i < size; ++i) rate[i] = 0.0;
			return true;
		}
		minimum = minf(minimum, values[charge]);
		const R *query = values;
		if (start_connected && values[charge].v == 0.0) {
			// OCV(0) connected left-limit for this derivative query only.
			for (int i = 0; i < size; ++i) evaluated[static_cast<size_t>(i)] = values[i];
			evaluated[static_cast<size_t>(charge)] = -R(kBatteryLeftLimit);
			query = evaluated.data();
		}
		if (!f(query, at, rate)) return false;
		if (!tick_finite(rate, size)) {
			tracker_ok = false;
			for (int i = 0; i < size; ++i) rate[i] = 0.0;
			return true;
		}
		if (rate[charge].v > 0.0) tracker_ok = false;
		else if (!connected && rate[charge].v != 0.0) tracker_ok = false;
		return true;
	};
	auto safe_project = [&](const R *values, int count, int index, std::vector<R> &projected) -> bool {
		std::vector<R> raw;
		const bool packed = project(values, count, index, raw);
		bool valid = packed && static_cast<int>(raw.size()) == size && tick_finite(raw.data(), size) && index == rpm;
		for (int i = 0; valid && i < size; ++i) {
			if (i != rpm && (i < kTickRate || i >= kTickRate + 3) && raw[static_cast<size_t>(i)].v != values[i].v) valid = false;
		}
		if (!valid) {
			tracker_ok = false;
			projected.assign(static_cast<size_t>(size), R(0.0));
			return true;
		}
		projected = raw;
		return true;
	};
	bool stopped = false;
	std::vector<R> event_times;
	const TickStatus status = tick_event_advance(start, size, time_s, dt, tracked, first, rpm, safe_project, true, stopped,
		out.state, event_times, sc);
	if (status != TickStatus::Ok) return status;
	if (!tracker_ok || !stopped) return TickStatus::Ok;
	if (static_cast<int>(out.state.size()) != size || !tick_finite(out.state.data(), size) ||
			out.state[static_cast<size_t>(rpm)].v < 0.0) return TickStatus::Ok;
	if (!connected && out.state[static_cast<size_t>(charge)].v != 0.0) return TickStatus::Ok;
	out.rotor_times = event_times;
	out.minimum_charge = minimum;
	out.ok = true;
	return TickStatus::Ok;
}

// electric_battery_step.gd `_append_rotor_events`; `shared_time` NaN means none.
inline void tick_append_rotor_events(std::vector<TickPolicyEvent> &events, const std::vector<R> &times, R shared_time) {
	for (const R at : times) {
		R event_time = at;
		if (is_finite(shared_time) && absf(event_time - shared_time).v <= kBatteryTimeTol) {
			event_time = shared_time;
		} else if (!events.empty() && events.back().battery &&
				absf(event_time - events.back().time_s).v <= kBatteryTimeTol) {
			TickPolicyEvent rotor;
			rotor.time_s = events.back().time_s;
			events.insert(events.end() - 1, rotor);
			continue;
		}
		TickPolicyEvent rotor;
		rotor.time_s = event_time;
		events.push_back(rotor);
	}
}

// electric_battery_step.gd `_append_battery_event`.
inline void tick_append_battery_event(std::vector<TickPolicyEvent> &events, R at, R residual_c, R time_error_s) {
	for (int i = static_cast<int>(events.size()) - 1; i >= 0; --i) {
		TickPolicyEvent &event = events[static_cast<size_t>(i)];
		if (event.battery) break;
		if (absf(event.time_s - at).v <= kBatteryTimeTol) event.time_s = at;
	}
	TickPolicyEvent battery;
	battery.battery = true;
	battery.time_s = at;
	battery.residual_c = residual_c;
	battery.time_error_s = time_error_s;
	events.push_back(battery);
}

// electric_battery_step.gd `_finish_exhausted`.
template <class F, class P>
inline TickStatus tick_battery_finish_exhausted(std::vector<R> state, int size, R time_s, R dt, F &f, int rpm, int charge,
		P &project, std::vector<TickPolicyEvent> &events, bool &ok, std::vector<R> &out, TickRk4Scratch &sc) {
	ok = false;
	if (dt.v <= 0.0) {
		out = state;
		ok = !state.empty();
		return TickStatus::Ok;
	}
	TickBatteryTrial exhausted;
	const TickStatus status = tick_battery_stop_trial(state.data(), size, time_s, dt, f, nullptr, rpm, charge, project,
		false, exhausted, sc);
	if (status != TickStatus::Ok || !exhausted.ok) return status;
	if (exhausted.state[static_cast<size_t>(charge)].v != 0.0) return TickStatus::Ok;
	tick_append_rotor_events(events, exhausted.rotor_times, kNan);
	out = exhausted.state;
	ok = !out.empty();
	return TickStatus::Ok;
}

// electric_battery_step.gd `_locate_battery_crossing`.
template <class F, class P>
inline TickStatus tick_battery_locate(const R *start, int size, R time_s, R dt, F &f, const R *first, int rpm, int charge,
		P &project, const TickBatteryTrial &high_trial, bool &located, std::vector<R> &high_state,
		std::vector<R> &high_times, R &offset, R &time_error, TickRk4Scratch &sc) {
	located = false;
	R lo = 0.0;
	R hi = dt;
	R low_charge = start[charge];
	bool bisect = false;
	high_state = high_trial.state;
	high_times = high_trial.rotor_times;
	if (high_state[static_cast<size_t>(charge)].v > 0.0) return TickStatus::Ok;
	auto done = [&]() -> bool {
		return (hi - lo).v <= kBatteryTimeTol && absf(high_state[static_cast<size_t>(charge)]).v <= kBatteryChargeTol;
	};
	TickBatteryTrial trial;
	for (int iteration = 0; iteration < kBatteryMaxRootTrials; ++iteration) {
		if (done()) {
			located = true;
			offset = hi;
			time_error = hi - lo;
			return TickStatus::Ok;
		}
		const R old_width = hi - lo;
		const R mid = tick_bracket_propose(lo, hi, low_charge, high_state[static_cast<size_t>(charge)], kBatteryTimeTol, bisect);
		if (!is_finite(mid)) break;
		const TickStatus status = tick_battery_stop_trial(start, size, time_s, mid, f, first, rpm, charge, project, true, trial, sc);
		if (status != TickStatus::Ok || !trial.ok) return status;
		const R q = trial.state[static_cast<size_t>(charge)];
		if (q.v > 0.0) {
			lo = mid;
			low_charge = q;
		} else {
			hi = mid;
			high_state = trial.state;
			high_times = trial.rotor_times;
		}
		bisect = !bisect && (hi - lo).v > (R(0.5) * old_width).v;
		if (done()) {
			located = true;
			offset = hi;
			time_error = hi - lo;
			return TickStatus::Ok;
		}
	}
	if ((hi - lo).v <= kBatteryTimeTol && high_state[static_cast<size_t>(charge)].v <= 0.0 &&
			absf(high_state[static_cast<size_t>(charge)]).v <= kBatteryChargeTol) {
		located = true;
		offset = hi;
		time_error = hi - lo;
	}
	return TickStatus::Ok;
}

// electric_battery_step.gd `advance` (strict_clock false).
template <class F, class P>
inline TickStatus tick_battery_advance(const R *s, int size, R time_s, R dt, F &f, const R *first, int rpm, int charge,
		P &project, bool &ok, std::vector<R> &out, std::vector<TickPolicyEvent> &out_events, TickRk4Scratch &sc) {
	ok = false;
	out_events.clear();
	if (rpm < kTickBody || rpm >= size || charge < kTickBody || charge >= size || charge == rpm || !tick_finite(s, size) ||
			s[rpm].v < 0.0 || s[charge].v < 0.0 || !is_finite(time_s) || !is_finite(dt) || dt.v <= 0.0 ||
			dt.v > kBatteryMaxDt || !is_finite(time_s + dt) || (time_s + dt).v <= time_s.v ||
			(first != nullptr && !tick_finite(first, size))) {
		return TickStatus::Ok;
	}
	if (first != nullptr && first[charge].v > 0.0) return TickStatus::Ok;
	std::vector<R> state(s, s + size);
	std::vector<TickPolicyEvent> &events = out_events;
	R elapsed = 0.0;
	const R *initial = first;
	int accepted_segments = 0;
	if (state[static_cast<size_t>(charge)].v == 0.0) {
		return tick_battery_finish_exhausted(state, size, time_s, dt, f, rpm, charge, project, events, ok, out, sc);
	}
	TickBatteryTrial trial;
	std::vector<R> high_state, high_times;
	while (accepted_segments < kBatteryMaxSegments) {
		const R remaining = dt - elapsed;
		if (remaining.v <= 0.0) {
			out = state;
			ok = !out.empty();
			return TickStatus::Ok;
		}
		R trial_step = remaining;
		bool accepted_piece = false;
		for (int refinement = 0; refinement < kBatteryMaxRefinements; ++refinement) {
			TickStatus status = tick_battery_stop_trial(state.data(), size, time_s + elapsed, trial_step, f, initial, rpm,
				charge, project, true, trial, sc);
			if (status != TickStatus::Ok || !trial.ok) return status;
			const R candidate_charge = trial.state[static_cast<size_t>(charge)];
			if (candidate_charge.v > state[static_cast<size_t>(charge)].v) return TickStatus::Ok;
			if (candidate_charge.v > 0.0) {
				if (trial.minimum_charge.v <= 0.0) {
					// A negative RK stage with a positive endpoint is unresolved, not a safe step.
					trial_step = trial_step * R(0.5);
					if (trial_step.v < kBatteryTimeTol) return TickStatus::Ok;
					continue;
				}
				tick_append_rotor_events(events, trial.rotor_times, kNan);
				state = trial.state;
				elapsed = elapsed + trial_step;
				initial = nullptr;
				accepted_segments += 1;
				accepted_piece = true;
				break;
			}
			bool located = false;
			R offset = 0.0, time_error = 0.0;
			status = tick_battery_locate(state.data(), size, time_s + elapsed, trial_step, f, initial, rpm, charge, project,
				trial, located, high_state, high_times, offset, time_error, sc);
			if (status != TickStatus::Ok || !located) return status;
			std::vector<R> crossing_state = high_state;
			const R residual = crossing_state[static_cast<size_t>(charge)];
			if (residual.v > 0.0 || absf(residual).v > kBatteryChargeTol) return TickStatus::Ok;
			const R event_time = time_s + elapsed + offset;
			tick_append_rotor_events(events, high_times, event_time);
			crossing_state[static_cast<size_t>(charge)] = 0.0;
			tick_append_battery_event(events, event_time, residual, time_error);
			const R after = dt - elapsed - offset;
			if (after.v <= 0.0) {
				out = crossing_state;
				ok = !out.empty();
				return TickStatus::Ok;
			}
			return tick_battery_finish_exhausted(crossing_state, size, event_time, after, f, rpm, charge, project, events,
				ok, out, sc);
		}
		if (!accepted_piece) return TickStatus::Ok;
	}
	return TickStatus::Ok;
}

// electric_contact_step.gd `_append_ordered`.
inline bool tick_append_ordered(std::vector<TickPolicyEvent> &events, TickPolicyEvent copy, int piece_index, R tolerance) {
	if (!events.empty()) {
		const TickPolicyEvent &previous = events.back();
		R difference = copy.time_s - previous.time_s;
		if (difference.v < 0.0 && (piece_index > 0 || difference.v < (-tolerance).v)) return false;
		if (piece_index == 0 && difference.v < 0.0) {
			copy.time_s = previous.time_s;
			difference = 0.0;
		}
		if (piece_index == 0 && difference.v == 0.0 && previous.battery && !copy.battery) {
			events.insert(events.end() - 1, copy);
			return true;
		}
	}
	events.push_back(copy);
	return true;
}

// electric_contact_step.gd `advance`: `pieces` uniform contact pieces of the battery step.
template <class F, class P>
inline TickStatus tick_contact_advance(const R *combined, int size, R at, R dt, F &f, const R *first, int rpm, int charge,
		P &project, int pieces, bool &ok, std::vector<R> &out, std::vector<TickPolicyEvent> &events, TickRk4Scratch &sc) {
	ok = false;
	events.clear();
	if (pieces < 1 || pieces > kContactMaxPieces || !is_finite(at) || !is_finite(dt) || dt.v <= 0.0) return TickStatus::Ok;
	if (pieces == 1) return tick_battery_advance(combined, size, at, dt, f, first, rpm, charge, project, ok, out, events, sc);
	std::vector<R> state(combined, combined + size);
	const R clock_tolerance = minf(R(kContactWindowSlack), maxf(R(kBatteryTimeTol),
		R(2.0) * R(kFloat64Epsilon) * maxf(absf(at), absf(at + dt))));
	std::vector<R> piece_state;
	std::vector<TickPolicyEvent> piece_events;
	for (int i = 0; i < pieces; ++i) {
		const R begin = dt * R(static_cast<double>(i)) / R(static_cast<double>(pieces));
		const R end = dt * R(static_cast<double>(i + 1)) / R(static_cast<double>(pieces));
		bool piece_ok = false;
		const TickStatus status = tick_battery_advance(state.data(), size, at + begin, end - begin, f, i == 0 ? first : nullptr,
			rpm, charge, project, piece_ok, piece_state, piece_events, sc);
		if (status != TickStatus::Ok || !piece_ok) return status;
		int piece_event_index = 0;
		for (const TickPolicyEvent &event : piece_events) {
			if (!is_finite(event.time_s) || event.time_s.v < (at + begin - R(kContactWindowSlack)).v ||
					event.time_s.v > (at + end + R(kContactWindowSlack)).v || static_cast<int>(events.size()) >= kContactMaxEvents) {
				return TickStatus::Ok;
			}
			if (!tick_append_ordered(events, event, piece_event_index, clock_tolerance)) return TickStatus::Ok;
			piece_event_index += 1;
		}
		state = piece_state;
	}
	out = state;
	ok = true;
	return TickStatus::Ok;
}

// ---------------------------------------------------------------------------------------------------------------
// NK-6d: resource_event_step.gd `advance` for GlowFlight.step. The stock glow surfaces are evaluated here (rotor
// stop, main tank unusable, feed line empty); transitions stay with the owner's recording callbacks. Every failure
// makes the policy return [NAN], so failure messages are not ported.

// resource_event_step.gd: TIME_TOL 1e-12, MAX_SEGMENTS 256, MAX_ROOT_TRIALS 128, MAX_DT_S 60.0, SURFACE_TOL 1e-10.
constexpr double kResourceTimeTol = 1e-12;
constexpr int kResourceMaxSegments = 256;
constexpr int kResourceMaxRootTrials = 128;
constexpr double kResourceMaxDt = 60.0;
constexpr double kResourceSurfaceTol = 1e-10;
constexpr int kResourceBudget = 200000; // advance's default max_surface_evaluations

enum class ResourceSense { Falling, Rising, Either };
enum class ResourceSurface { RotorStop, MainTankUnusable, FeedLineEmpty };

struct ResourceEvent {
	ResourceSurface surface = ResourceSurface::RotorStop;
	ResourceSense sense = ResourceSense::Falling;
	int priority = 100;
	R tolerance = kResourceSurfaceTol;
	bool has_enabled = false;
	int index = 0; // its position in the owner's event list (transition callback)
	std::string id; // ordering key of _event_before
	std::string type, unit; // the report's `type` and `surface_unit` (UTF-8)
};

// Glow layout (glow/flight.gd): rpm at the continuous block's start, fuel kg next, feed-line liquid at 17, the
// source mode at 18 (0 starved, 1 main tank, 2 pre-primed line).
struct ResourceGlowLayout {
	int body = kTickBody;
	R unusable_fuel_kg = 0.0;
};

struct ResourceSample {
	bool ok = false;
	bool enabled = true;
	R value = 1.0;
};

// resource_event_step.gd `_surface_sample` with the stock glow closures.
inline ResourceSample resource_surface_sample(const ResourceEvent &event, const R *state, const ResourceGlowLayout &glow,
		int64_t remaining, int64_t &evaluations) {
	ResourceSample out;
	if (remaining <= 0) return out;
	evaluations += 1;
	const int g = glow.body;
	if (event.has_enabled) {
		const int64_t mode = static_cast<int64_t>(state[g + 18].v);
		out.enabled = event.surface == ResourceSurface::MainTankUnusable ? mode == 1 :
			event.surface == ResourceSurface::FeedLineEmpty ? mode == 2 : true;
	}
	if (!out.enabled) {
		out.ok = true;
		out.value = 1.0;
		return out;
	}
	switch (event.surface) {
		case ResourceSurface::RotorStop: out.value = state[g]; break;
		case ResourceSurface::MainTankUnusable: out.value = state[g + 1] - state[g + 17] - glow.unusable_fuel_kg; break;
		case ResourceSurface::FeedLineEmpty: out.value = state[g + 17]; break;
	}
	if (!is_finite(out.value)) return out;
	out.ok = true;
	return out;
}

inline bool resource_crossed(R start_value, R end_value, ResourceSense sense) {
	switch (sense) {
		case ResourceSense::Falling: return start_value.v > 0.0 && end_value.v <= 0.0;
		case ResourceSense::Rising: return start_value.v < 0.0 && end_value.v >= 0.0;
		case ResourceSense::Either:
			return (start_value.v > 0.0 && end_value.v <= 0.0) || (start_value.v < 0.0 && end_value.v >= 0.0);
	}
	return false;
}

inline bool resource_crossed_extrema(R start_value, R minimum, R maximum, ResourceSense sense) {
	switch (sense) {
		case ResourceSense::Falling: return start_value.v > 0.0 && minimum.v <= 0.0;
		case ResourceSense::Rising: return start_value.v < 0.0 && maximum.v >= 0.0;
		case ResourceSense::Either:
			return (start_value.v > 0.0 && minimum.v <= 0.0) || (start_value.v < 0.0 && maximum.v >= 0.0);
	}
	return false;
}

// resource_event_step.gd `_event_before`: priority, then id (String <, code-point order for these ASCII ids).
inline bool resource_event_before(const ResourceEvent &a, const ResourceEvent &b) {
	if (a.priority != b.priority) return a.priority < b.priority;
	return a.id < b.id;
}

struct ResourceTrial {
	bool ok = false;
	std::vector<R> state;
	std::vector<R> minimum, maximum; // per event
};

// resource_event_step.gd `_trial`. `values` are the events' start values (by event position).
template <class F>
inline TickStatus resource_trial(const R *state, int size, R time_s, R dt, F &f, const R *first,
		const std::vector<const ResourceEvent *> &events, const std::vector<R> &values, const ResourceGlowLayout &glow,
		int64_t remaining, int64_t &evaluations, ResourceTrial &out, TickRk4Scratch &sc) {
	out.ok = false;
	if (remaining <= 0) return TickStatus::Ok;
	const size_t count = events.size();
	out.minimum = values;
	out.maximum = values;
	bool tracker_ok = true;
	int64_t used = 0;
	std::vector<R> initial_buffer;
	const R *initial = first;
	if (initial == nullptr) {
		initial_buffer.resize(static_cast<size_t>(size));
		if (!f(state, time_s, initial_buffer.data())) return TickStatus::Abort;
		initial = initial_buffer.data();
	}
	if (!tick_finite(initial, size)) return TickStatus::Ok;
	auto tracked = [&](const R *stage, R at, R *rate) -> bool {
		if (!tick_finite(stage, size)) {
			tracker_ok = false;
			for (int i = 0; i < size; ++i) rate[i] = 0.0;
			return true;
		}
		for (size_t e = 0; e < count; ++e) {
			const ResourceSample sample = resource_surface_sample(*events[e], stage, glow, remaining - used, used);
			if (!sample.ok) {
				tracker_ok = false;
				for (int i = 0; i < size; ++i) rate[i] = 0.0;
				return true;
			}
			if (sample.enabled) {
				out.minimum[e] = minf(out.minimum[e], sample.value);
				out.maximum[e] = maxf(out.maximum[e], sample.value);
			}
		}
		if (!f(stage, at, rate)) return false;
		if (!tick_finite(rate, size)) {
			tracker_ok = false;
			for (int i = 0; i < size; ++i) rate[i] = 0.0;
		}
		return true;
	};
	out.state.resize(static_cast<size_t>(size));
	const TickStatus status = tick_rk4_step_at(state, size, time_s, dt, tracked, initial, out.state.data(), sc);
	if (status != TickStatus::Ok) return status;
	if (!tracker_ok || !tick_finite(out.state.data(), size)) {
		evaluations += used;
		return TickStatus::Ok;
	}
	for (size_t e = 0; e < count; ++e) {
		const ResourceSample sample = resource_surface_sample(*events[e], out.state.data(), glow, remaining - used, used);
		if (!sample.ok) {
			evaluations += used;
			return TickStatus::Ok;
		}
		if (sample.enabled) {
			out.minimum[e] = minf(out.minimum[e], sample.value);
			out.maximum[e] = maxf(out.maximum[e], sample.value);
		}
	}
	evaluations += used;
	out.ok = true;
	return TickStatus::Ok;
}

struct ResourceRoot {
	bool ok = false;
	std::vector<R> state;
	R offset = 0.0, residual = 0.0, time_error = 0.0;
};

// resource_event_step.gd `_locate`.
template <class F>
inline TickStatus resource_locate(const R *start, int size, R time_s, R dt, F &f, const R *first, const ResourceEvent &event,
		R start_value, R end_value, const ResourceGlowLayout &glow, int64_t remaining, int64_t &evaluations,
		ResourceRoot &out, TickRk4Scratch &sc) {
	out.ok = false;
	const R sign = event.sense == ResourceSense::Rising || (event.sense == ResourceSense::Either && start_value.v < 0.0) ?
		R(-1.0) : R(1.0);
	R lo = 0.0;
	R hi = dt;
	R low_value = sign * start_value;
	R high_value = sign * end_value;
	bool bisect = false;
	int64_t used = 0;
	if (low_value.v <= 0.0 || high_value.v > 0.0) return TickStatus::Ok;
	const std::vector<const ResourceEvent *> one = {&event};
	const std::vector<R> one_value = {start_value};
	ResourceTrial trial;
	TickStatus status = resource_trial(start, size, time_s, dt, f, first, one, one_value, glow, remaining, used, trial, sc);
	if (status != TickStatus::Ok) return status;
	if (!trial.ok) {
		evaluations += used;
		return TickStatus::Ok;
	}
	std::vector<R> high_state = trial.state;
	ResourceSample high_sample = resource_surface_sample(event, high_state.data(), glow, remaining - used, used);
	if (!high_sample.ok) {
		evaluations += used;
		return TickStatus::Ok;
	}
	high_value = sign * high_sample.value;
	if (high_value.v > 0.0) {
		evaluations += used;
		return TickStatus::Ok;
	}
	auto settled = [&]() {
		return (hi - lo).v <= kResourceTimeTol && absf(high_value).v <= event.tolerance.v;
	};
	for (int iteration = 0; iteration < kResourceMaxRootTrials; ++iteration) {
		if (settled()) {
			evaluations += used;
			out.ok = true;
			out.state = high_state;
			out.offset = hi;
			out.residual = high_sample.value;
			out.time_error = hi - lo;
			return TickStatus::Ok;
		}
		const R old_width = hi - lo;
		const R next = tick_bracket_propose(lo, hi, low_value, high_value, kResourceTimeTol, bisect);
		if (!is_finite(next)) break;
		status = resource_trial(start, size, time_s, next, f, first, one, one_value, glow, remaining - used, used, trial, sc);
		if (status != TickStatus::Ok) return status;
		if (!trial.ok) {
			evaluations += used;
			return TickStatus::Ok;
		}
		const ResourceSample sample = resource_surface_sample(event, trial.state.data(), glow, remaining - used, used);
		if (!sample.ok) {
			evaluations += used;
			return TickStatus::Ok;
		}
		const R residual = sign * sample.value;
		if (residual.v > 0.0) {
			lo = next;
			low_value = residual;
		} else {
			hi = next;
			high_value = residual;
			high_state = trial.state;
			high_sample = sample;
		}
		bisect = (hi - lo).v > (R(0.5) * old_width).v;
	}
	evaluations += used;
	if (settled()) {
		out.ok = true;
		out.state = high_state;
		out.offset = hi;
		out.residual = high_sample.value;
		out.time_error = hi - lo;
	}
	return TickStatus::Ok;
}

// One applied event of the step: the report fields; the owner adds its transition details.
struct ResourceReport {
	const ResourceEvent *event = nullptr;
	R time_s = 0.0, residual = 0.0, time_error = 0.0;
	int details = -1; // index into the transition results kept by the caller
};

// resource_event_step.gd `advance`. `transition(event, in, at, out, details_index)` calls the owner's transition and
// returns false unless it gave {ok: true, state: finite packed array of this size}.
template <class F, class T>
inline TickStatus resource_advance(const R *s, int size, R time_s, R dt, F &f, const R *first,
		const std::vector<ResourceEvent> &event_list, const ResourceGlowLayout &glow, T &transition, bool &ok,
		std::vector<R> &out, std::vector<ResourceReport> &reported, TickRk4Scratch &sc) {
	ok = false;
	reported.clear();
	if (size < kTickBody || !tick_finite(s, size) || !is_finite(time_s) || !is_finite(dt) || dt.v <= 0.0 ||
			dt.v > kResourceMaxDt || !is_finite(time_s + dt) || (time_s + dt).v <= time_s.v ||
			(first != nullptr && !tick_finite(first, size)) || event_list.empty()) {
		return TickStatus::Ok;
	}
	std::vector<const ResourceEvent *> events;
	for (const ResourceEvent &event : event_list) events.push_back(&event);
	const size_t count = events.size();
	const int64_t budget = kResourceBudget;
	std::vector<R> accepted(s, s + size);
	R elapsed = 0.0;
	R step = dt;
	const R *initial = first;
	int64_t evaluations = 0;
	std::vector<R> start_values(count), end_values(count);
	std::vector<char> start_enabled(count);
	ResourceTrial trial;
	for (int segment = 0; segment < kResourceMaxSegments; ++segment) {
		// _surface_values
		if (budget - evaluations <= 0) return TickStatus::Ok;
		for (size_t e = 0; e < count; ++e) {
			const ResourceSample sample = resource_surface_sample(*events[e], accepted.data(), glow, budget - evaluations,
				evaluations);
			if (!sample.ok) return TickStatus::Ok;
			start_values[e] = sample.enabled ? sample.value : R(1.0);
			start_enabled[e] = sample.enabled ? 1 : 0;
		}
		TickStatus status = resource_trial(accepted.data(), size, time_s + elapsed, step, f, initial, events, start_values,
			glow, budget - evaluations, evaluations, trial, sc);
		if (status != TickStatus::Ok) return status;
		if (!trial.ok) return TickStatus::Ok;
		const std::vector<R> endpoint = trial.state;
		std::vector<size_t> crossings;
		bool internal_crossing = false;
		for (size_t e = 0; e < count; ++e) {
			const ResourceSample end_sample = resource_surface_sample(*events[e], endpoint.data(), glow,
				budget - evaluations, evaluations);
			if (!end_sample.ok) return TickStatus::Ok;
			if (!end_sample.enabled) continue;
			end_values[e] = end_sample.value;
			const bool crossed_end = resource_crossed(start_values[e], end_sample.value, events[e]->sense);
			const bool crossed_inside = resource_crossed_extrema(start_values[e], trial.minimum[e], trial.maximum[e],
				events[e]->sense);
			if (crossed_end) crossings.push_back(e);
			else if (crossed_inside) internal_crossing = true;
		}
		if (internal_crossing) {
			step = step * R(0.5);
			if (step.v < kResourceTimeTol) return TickStatus::Ok;
			continue;
		}
		if (!crossings.empty()) {
			struct Located { size_t event; ResourceRoot root; };
			std::vector<Located> located;
			for (const size_t e : crossings) {
				Located entry{e, ResourceRoot()};
				status = resource_locate(accepted.data(), size, time_s + elapsed, step, f, initial, *events[e], start_values[e],
					end_values[e], glow, budget - evaluations, evaluations, entry.root, sc);
				if (status != TickStatus::Ok) return status;
				if (!entry.root.ok) return TickStatus::Ok;
				located.push_back(entry);
			}
			std::sort(located.begin(), located.end(), [&](const Located &a, const Located &b) {
				if (a.root.offset.v != b.root.offset.v) return a.root.offset.v < b.root.offset.v;
				return resource_event_before(*events[a.event], *events[b.event]);
			});
			const R earliest = located[0].root.offset;
			std::vector<Located> tied;
			for (const Located &candidate : located) {
				if ((candidate.root.offset - earliest).v <= kResourceTimeTol) tied.push_back(candidate);
				else break;
			}
			std::sort(tied.begin(), tied.end(), [&](const Located &a, const Located &b) {
				return resource_event_before(*events[a.event], *events[b.event]);
			});
			const R boundary = tied[0].root.offset;
			// _crossed_before
			bool missed = false;
			for (size_t e = 0; e < count && !missed; ++e) {
				if (!start_enabled[e]) continue;
				const ResourceSample sample = resource_surface_sample(*events[e], tied[0].root.state.data(), glow,
					budget - evaluations, evaluations);
				if (!sample.ok) return TickStatus::Ok;
				if (sample.enabled && absf(sample.value).v > events[e]->tolerance.v &&
						resource_crossed(start_values[e], sample.value, events[e]->sense)) missed = true;
			}
			if (missed) {
				if (earliest.v > 0.0 && earliest.v < step.v) {
					step = earliest;
				} else {
					step = step * R(0.5);
					if (step.v < kResourceTimeTol) return TickStatus::Ok;
				}
				continue;
			}
			std::vector<R> root_state = tied[0].root.state;
			int applied = 0;
			const R at = time_s + elapsed + boundary;
			for (const Located &candidate : tied) {
				const ResourceEvent &event = *events[candidate.event];
				const ResourceSample at_root = resource_surface_sample(event, root_state.data(), glow, budget - evaluations,
					evaluations);
				if (!at_root.ok) return TickStatus::Ok;
				if (!at_root.enabled || absf(at_root.value).v > event.tolerance.v) continue;
				std::vector<R> next;
				int details = -1;
				if (!transition(event, root_state, at, next, details) || static_cast<int>(next.size()) != size ||
						!tick_finite(next.data(), size)) {
					return TickStatus::Ok;
				}
				root_state = next;
				applied += 1;
				ResourceReport report;
				report.event = &event;
				report.time_s = at;
				report.residual = at_root.value;
				report.time_error = candidate.root.time_error;
				report.details = details;
				reported.push_back(report);
			}
			if (applied == 0) return TickStatus::Ok;
			if (!tick_finite(root_state.data(), size)) return TickStatus::Ok;
			accepted = root_state;
			elapsed = elapsed + boundary;
			if (elapsed.v >= dt.v) {
				out = accepted;
				ok = true;
				return TickStatus::Ok;
			}
			step = dt - elapsed;
			initial = nullptr;
			continue;
		}
		accepted = endpoint;
		elapsed = elapsed + step;
		if (elapsed.v >= dt.v) {
			out = accepted;
			ok = true;
			return TickStatus::Ok;
		}
		step = dt - elapsed;
		initial = nullptr;
	}
	return TickStatus::Ok;
}

} // namespace nk
