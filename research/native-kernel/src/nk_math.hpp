// NK-3 math shim: the C++ twin of app/physics/math3d.gd plus the Godot utility functions the ported laws use.
//
// Scalar type R. Every simulation value in the port is an R: one IEEE-754 double whose + - * / are single SSE2
// instructions with the LEFT operand as the first source (inline asm), so GCC can neither commute, reassociate,
// contract nor fold them. Reason: x86 returns the first source's NaN when both operands are NaN, and the pinned
// engine's GDScript evaluator is left-first on every path (typed, Variant, packed, compound; probed 2026-10-27),
// while GCC freely commutes + and *. Plain doubles would match every finite result but not the sign of a NaN that
// meets another NaN (the malformed-input oracle found such cases). Comparisons and unary minus use the double.
//
// Transcendentals (NK-1 hazards): libm symbols are the ones the engine calls in the same process; asin clamps like
// math3d.asin_; pow never sees a literal exponent. Helpers copy the engine's definitions (core/typedefs.h MIN/MAX/
// CLAMP, core/math/math_funcs.h abs/lerp/wrapf), including NaN and signed-zero behaviour.
#pragma once

#include <cmath>
#include <cstdint>
#include <cstring>
#include <limits>

#if !defined(__GNUC__) || !defined(__x86_64__)
#error "NK-3 research build: the left-first scalar operations are written for GCC on x86_64 (SSE2)."
#endif

namespace nk {

struct R {
	double v;
	R() : v(0.0) {}
	constexpr R(double x) : v(x) {}
	constexpr operator double() const { return v; }
};

#define NK_LEFT_FIRST(OP, INSN)                                         \
	inline R OP(R a, R b) {                                             \
		double x = a.v;                                                 \
		__asm__(INSN " %1, %0" : "+x"(x) : "x"(b.v));                   \
		return R(x);                                                    \
	}                                                                   \
	inline R OP(R a, double b) { return OP(a, R(b)); }                  \
	inline R OP(double a, R b) { return OP(R(a), b); }

NK_LEFT_FIRST(operator+, "addsd")
NK_LEFT_FIRST(operator-, "subsd")
NK_LEFT_FIRST(operator*, "mulsd")
NK_LEFT_FIRST(operator/, "divsd")
#undef NK_LEFT_FIRST

inline R operator-(R a) { return R(-a.v); }
inline R &operator+=(R &a, R b) { return a = a + b; }
inline R &operator-=(R &a, R b) { return a = a - b; }
inline R &operator*=(R &a, R b) { return a = a * b; }
inline R &operator/=(R &a, R b) { return a = a / b; }

constexpr double kPi = 3.1415926535897932384626433833;
constexpr double kNan = std::numeric_limits<double>::quiet_NaN();
constexpr double kInf = std::numeric_limits<double>::infinity();
constexpr double kCmpEpsilon = 0.00001;
// The pinned GDScript parser rounds the spelling `1e-24` one ULP above the C++ literal.
// `1.0e-24` is a distinct spelling with its own oracle entry; do not replace that threshold.
constexpr double kGd1eMinus24 = 0x1.357c299a88ea8p-80;

inline R sin_(R a) { return ::sin(a.v); }
inline R cos_(R a) { return ::cos(a.v); }
inline R atan2_(R y, R x) { return ::atan2(y.v, x.v); }
inline R sqrt_(R a) { return ::sqrt(a.v); }
inline R tanh_(R a) { return ::tanh(a.v); }

inline R pow_(R base, R exponent) {
	double e = exponent.v;
	__asm__("" : "+x"(e)); // opaque to constant propagation: libm pow, never a folded multiply
	return ::pow(base.v, e);
}

inline bool is_finite(R x) { return std::isfinite(x.v); }
inline bool is_nan(R x) { return std::isnan(x.v); }

// Godot MAX/MIN/CLAMP: a > b ? a : b, a < b ? a : b, a < lo ? lo : (a > hi ? hi : a).
inline R maxf(R a, R b) { return a.v > b.v ? a : b; }
inline R minf(R a, R b) { return a.v < b.v ? a : b; }
inline R clampf(R x, R lo, R hi) { return x.v < lo.v ? lo : (x.v > hi.v ? hi : x); }
inline R asin_(R x) { return ::asin(clampf(x, -1.0, 1.0).v); }
// Godot Math::abs(double): +0.0 for either zero, the negated value below zero, else unchanged (a NaN keeps its
// sign bit, unlike fabs; the oracle's math probe checks this against GDScript absf on signed NaNs).
inline R absf(R x) { return x.v == 0 ? R(0.0) : (x.v < 0 ? -x : x); }
// Godot Math::lerp is from + (to - from) * weight, but it is engine C++, not the GDScript evaluator: the pinned
// binary's NaN priority (probed by the oracle) is weight-first for the product and product-first for the sum.
// Finite results are unchanged by this operand order (IEEE + and * commute exactly).
inline R lerpf(R from, R to, R weight) { return weight * (to - from) + from; }

inline bool is_zero_approx(R v) { return absf(v).v < kCmpEpsilon; }
inline bool is_equal_approx(R left, R right) {
	if (left.v == right.v) {
		return true;
	}
	R tolerance = kCmpEpsilon * absf(left);
	if (tolerance.v < kCmpEpsilon) {
		tolerance = kCmpEpsilon;
	}
	return absf(left - right).v < tolerance.v;
}

// Godot Math::wrapf(double).
inline R wrapf(R value, R min, R max) {
	const R range = max - min;
	if (is_zero_approx(range)) {
		return min;
	}
	const R result = value - (range * R(::floor(((value - min) / range).v)));
	if (is_equal_approx(result, max)) {
		return min;
	}
	return result;
}

inline std::uint64_t bits(double x) {
	std::uint64_t out;
	std::memcpy(&out, &x, sizeof(out));
	return out;
}

} // namespace nk
