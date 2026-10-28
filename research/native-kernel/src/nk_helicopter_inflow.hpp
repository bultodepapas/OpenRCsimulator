// Experimental NK-3 helicopter groundwork: operation-ordered mirror of rotorcraft/inflow.gd and
// rotorcraft/dynamic_inflow.gd. These are component helpers only; no production route is admitted by this file.
#pragma once

#include <array>
#include <initializer_list>

#include "nk_math.hpp"

namespace nk {

inline bool heli_inflow_finite(std::initializer_list<R> values) {
	for (const R value : values) {
		if (!is_finite(value)) {
			return false;
		}
	}
	return true;
}

// A pair is [value, derivative with respect to z], matching the reference PackedFloat64Array.
using HeliInflowPair = std::array<R, 2>;

inline R heli_inflow_residual(R v, R z, R x) {
	return v * sqrt_(x * x + (z + v) * (z + v)) - 1.0;
}

inline HeliInflowPair heli_inflow_zero_constant(R z, R a, R b, R va, R da, R vb) {
	const R qa = va / a;
	const R dqa = (da - qa) / a;
	const R h = b - a;
	const R d = (vb / b - qa - dqa * h) / (h * h);
	const R c = dqa - 2.0 * d * a;
	const R linear = qa - c * a - d * a * a;
	return {z * (linear + z * (c + z * d)), linear + z * (2.0 * c + 3.0 * z * d)};
}

inline R heli_inflow_hermite(R z, R a, R b, R va, R vb, R da, R db) {
	const R h = b - a;
	const R t = (z - a) / h;
	const R t2 = t * t;
	const R t3 = t2 * t;
	return (2.0 * t3 - 3.0 * t2 + 1.0) * va + (t3 - 2.0 * t2 + t) * h * da
		+ (-2.0 * t3 + 3.0 * t2) * vb + (t3 - t2) * h * db;
}

inline HeliInflowPair heli_inflow_momentum(R z, R x, bool windmill) {
	if (x == 0.0) {
		R root;
		R slope;
		if (windmill && z < -2.0) {
			const R d = sqrt_(z * z - 4.0);
			root = 2.0 / (-z + d);
			slope = -0.5 - 0.5 * z / d;
		} else {
			const R d = sqrt_(z * z + 4.0);
			root = z >= 0.0 ? 2.0 / (z + d) : 0.5 * (-z + d);
			slope = -0.5 + 0.5 * z / d;
		}
		return {root, slope};
	}
	R lo = 0.0;
	R hi = absf(z) + 2.0;
	hi = minf(hi, 1.0 / x);
	if (z >= 0.0) {
		hi = minf(hi, 1.0 / sqrt_(x * x + z * z));
	}
	if (windmill && z < -2.0) {
		hi = minf(hi, 2.0 / sqrt_(x * x + z * z));
	}
	const R disc = z * z - 8.0 * x * x;
	if (z < 0.0 && disc > 0.0) {
		const R d = sqrt_(disc);
		const R turn_a = (-3.0 * z - d) / 4.0;
		const R turn_b = (-3.0 * z + d) / 4.0;
		if (windmill && heli_inflow_residual(turn_a, z, x) >= 0.0) {
			hi = minf(hi, turn_a);
		} else if (!windmill && heli_inflow_residual(turn_b, z, x) <= 0.0) {
			lo = turn_b;
		}
	}
	R v = lo > 0.0 ? 0.5 * (lo + hi) : minf(hi, 1.0 / sqrt_(1.0 + x * x + z * z));
	bool converged = false;
	for (int pass = 0; pass < 12; ++pass) {
		const R flow = sqrt_(x * x + (z + v) * (z + v));
		const R residual = v * flow - 1.0;
		if (absf(residual) <= 1e-13) {
			converged = true;
			break;
		}
		if (residual > 0.0) {
			hi = v;
		} else {
			lo = v;
		}
		const R gradient = flow + v * (z + v) / flow;
		const R next = gradient > 0.0 ? v - residual / gradient : R(kNan);
		v = is_finite(next) && next > lo && next < hi ? next : 0.5 * (lo + hi);
	}
	if (!converged) {
		for (int pass = 0; pass < 48; ++pass) {
			const R mid = 0.5 * (lo + hi);
			if (heli_inflow_residual(mid, z, x) > 0.0) {
				hi = mid;
			} else {
				lo = mid;
			}
		}
		v = 0.5 * (lo + hi);
	}
	const R den = x * x + (z + v) * (z + 2.0 * v);
	const R slope = -v * (z + v) / den;
	return {v, slope};
}

inline HeliInflowPair heli_inflow_baseline(R z, R x) {
	if (z >= 0.0 || x >= 0.75) {
		return heli_inflow_momentum(z, x, z < -2.0);
	}
	const R u = x / 0.75;
	const R a = -1.5 + 0.2 * u * u;
	R b = -2.1 + 0.2 * u * u;
	if (u > 0.5) {
		b += 0.7 * (a - b) * pow_(2.0 * u - 1.0, 3.0);
	}
	if (z >= a) {
		return heli_inflow_momentum(z, x, false);
	}
	if (z <= b) {
		return heli_inflow_momentum(z, x, true);
	}
	const HeliInflowPair va = heli_inflow_momentum(a, x, false);
	const HeliInflowPair vb = heli_inflow_momentum(b, x, true);
	return heli_inflow_zero_constant(z, a, b, va[0], va[1], vb[0]);
}

struct HeliInflowRatio {
	bool ok = false;
	R ratio = 0.0;
};

inline HeliInflowRatio heli_inflow_normalized(R z, R x, R instability, R loss) {
	if (!heli_inflow_finite({z, x, instability, loss}) || x < 0.0 || absf(z) > 1.0e6 || x > 1.0e6
			|| instability < 0.0 || instability > 1.0 || loss < 1.0) {
		return {};
	}
	const HeliInflowPair base = heli_inflow_baseline(z, x);
	R delta = 0.0;
	if (instability > 0.0 && z < -0.2 && x < 0.95) {
		const R u = x / 0.95;
		const R edge = maxf(0.0, 1.0 - u * u);
		const R n = -0.975 + 0.525 * pow_(edge, 0.2);
		const R peak = -0.975 - 0.525 * pow_(edge, 1.5);
		const R end = -2.0 + (peak + 1.5);
		if (z > end) {
			const R fade = sqrt_(maxf(0.0, 1.0 - pow_(u, 6.0)));
			const HeliInflowPair bn = heli_inflow_baseline(n, x);
			const HeliInflowPair bp = heli_inflow_baseline(peak, x);
			const R dn = (0.85 - (-0.45 + heli_inflow_momentum(-0.45, x, false)[0])) * fade;
			const R dp = (1.25 - (-1.5 + heli_inflow_momentum(-1.5, x, false)[0])) * fade;
			if (z >= n) {
				delta = heli_inflow_hermite(z, n, -0.2, dn, 0.0, -(1.0 + bn[1]), 0.0);
			} else if (z >= peak) {
				delta = heli_inflow_hermite(z, peak, n, dp, dn, -(1.0 + bp[1]), -(1.0 + bn[1]));
			} else {
				delta = heli_inflow_zero_constant(z, peak, end, dp, -(1.0 + bp[1]), 0.0)[0];
			}
		}
	}
	const R value = loss * (base[0] + instability * delta);
	if (!is_finite(value) || value < 0.0) {
		return {};
	}
	return {true, value};
}

inline R heli_inflow_ground_factor(R height_over_radius) {
	if (!is_finite(height_over_radius) || (height_over_radius < 0.0 && height_over_radius != -1.0)) {
		return kNan;
	}
	if (height_over_radius == -1.0) {
		return 1.0;
	}
	const R ratio = 2.0 / maxf(0.5, height_over_radius);
	return 0.9926 / (0.9926 + 0.03794 * ratio * ratio);
}

struct HeliInflowTarget {
	bool ok = false;
	R velocity = 0.0;
	R hover = 0.0;
	R ground_factor = 0.0;
};

inline HeliInflowTarget heli_inflow_target(R thrust, R density, R radius, R climb, R crossflow,
		R height_over_radius, R loss, R instability) {
	if (!heli_inflow_finite({thrust, density, radius, climb, crossflow, height_over_radius, loss, instability})
			|| density <= 0.0 || radius <= 0.0 || crossflow < 0.0 || loss < 1.0 || instability < 0.0
			|| instability > 1.0 || (height_over_radius < 0.0 && height_over_radius != -1.0)) {
		return {};
	}
	const R factor = thrust != 0.0 ? heli_inflow_ground_factor(height_over_radius) : R(1.0);
	if (thrust == 0.0) {
		return {true, 0.0, 0.0, factor};
	}
	const R hover = sqrt_(absf(thrust) / (2.0 * density * kPi * radius * radius));
	if (!is_finite(hover) || hover <= 0.0) {
		return {};
	}
	const R sense = thrust > 0.0 ? R(1.0) : R(-1.0);
	const HeliInflowRatio ratio = heli_inflow_normalized(sense * climb / hover, crossflow / hover, instability, loss);
	if (!ratio.ok) {
		return {};
	}
	const R velocity = sense * hover * ratio.ratio * factor;
	if (!is_finite(velocity)) {
		return {};
	}
	return {true, velocity, hover, factor};
}

struct HeliInflowRate {
	bool ok = false;
	R rate = 0.0;
	R tau = 0.0;
};

inline HeliInflowRate heli_inflow_derivative(R velocity, R target_velocity, R radius, R effective_flow, R flow_floor) {
	if (!heli_inflow_finite({velocity, target_velocity, radius, effective_flow, flow_floor})
			|| radius <= 0.0 || effective_flow < 0.0 || flow_floor <= 0.0) {
		return {};
	}
	// DISC_MASS / 4.0 occurs in the GDScript evaluator before the following multiplications.
	const R tau = (R(0.849) / 4.0) * radius / maxf(effective_flow, flow_floor);
	if (!is_finite(tau) || tau <= 0.0) {
		return {};
	}
	const R rate = (target_velocity - velocity) / tau;
	if (!is_finite(rate)) {
		return {};
	}
	return {true, rate, tau};
}

struct HeliDynamicInflow {
	bool ok = false;
	R rate = 0.0;
	R tau = 0.0;
	R target = 0.0;
	R effective_flow = 0.0;
	R hover = 0.0;
	R ground_factor = 0.0;
};

inline HeliDynamicInflow heli_dynamic_inflow(R velocity, R thrust, R density, R radius, R climb, R crossflow,
		R flow_floor, R height_over_radius, R loss, R instability) {
	if (!is_finite(velocity) || !is_finite(flow_floor) || flow_floor <= 0.0) {
		return {};
	}
	const HeliInflowTarget equilibrium = heli_inflow_target(thrust, density, radius, climb, crossflow,
		height_over_radius, loss, instability);
	if (!equilibrium.ok) {
		return {};
	}
	const R axial_flow = velocity + climb;
	const R effective_flow = sqrt_(crossflow * crossflow + axial_flow * axial_flow);
	const HeliInflowRate response = heli_inflow_derivative(velocity, equilibrium.velocity, radius, effective_flow, flow_floor);
	if (!response.ok) {
		return {};
	}
	return {true, response.rate, response.tau, equilibrium.velocity, effective_flow, equilibrium.hover,
		equilibrium.ground_factor};
}

} // namespace nk
