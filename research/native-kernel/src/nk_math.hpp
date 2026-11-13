// NK-3 math shim: the C++ twin of app/physics/math3d.gd plus the Godot utility functions the ported laws use.
//
// Scalar type R. Every simulation value in the port is an IEEE-754 double. The x86 + - * / use single SSE2
// instructions with the LEFT operand as the first source (inline asm), so GCC cannot commute, reassociate,
// contract or fold them. The pinned x86 GDScript evaluator's operand order is covered by the malformed-input
// oracle. Apple ARM64 uses separate scalar instructions with the same explicit source order; its full arithmetic,
// helper and GDExtension parity remain unqualified until tested against the exact ARM64 engine. Comparisons and
// unary minus use the double.
//
// Transcendentals (NK-1 hazards): matching a libm symbol does not by itself prove the engine uses identical code.
// asin clamps like math3d.asin_; pow never sees a literal exponent. Helpers follow the engine's definitions
// (core/typedefs.h MIN/MAX/CLAMP, core/math/math_funcs.h abs/lerp/wrapf); platform parity requires the oracle.
#pragma once

#include <cmath>
#include <cstdint>
#include <cstring>
#include <limits>

#if defined(__GNUC__) && defined(__x86_64__)
#define NK_MATH_X86_64 1
#elif defined(__APPLE__) && defined(__clang__) && (defined(__aarch64__) || defined(__arm64__))
#define NK_MATH_APPLE_ARM64 1
#else
#error "NK-3 research build: left-first scalar operations support GCC-compatible x86_64 or Apple Clang ARM64."
#endif

#if defined(NK_ENGINE_SQRT_SSE2) && !defined(NK_MATH_X86_64)
#error "NK_ENGINE_SQRT_SSE2 requires the x86_64 SSE2 math implementation."
#endif

namespace nk {

struct R {
	double v;
	R() : v(0.0) {}
	constexpr R(double x) : v(x) {}
	constexpr operator double() const { return v; }
};

#if defined(NK_MATH_X86_64)
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
#else
#define NK_LEFT_FIRST(OP, INSN)                                         \
	inline R OP(R a, R b) {                                             \
		double result;                                                  \
		__asm__(INSN " %d0, %d1, %d2" : "=w"(result) : "w"(a.v), "w"(b.v)); \
		return R(result);                                               \
	}                                                                   \
	inline R OP(R a, double b) { return OP(a, R(b)); }                  \
	inline R OP(double a, R b) { return OP(R(a), b); }

NK_LEFT_FIRST(operator+, "fadd")
NK_LEFT_FIRST(operator-, "fsub")
NK_LEFT_FIRST(operator*, "fmul")
NK_LEFT_FIRST(operator/, "fdiv")
#endif
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
// The pinned x86 GDScript parser rounds the spelling `1e-24` one ULP above the C++ literal.
// `1.0e-24` is a distinct spelling with its own oracle entry; do not replace that threshold.
constexpr double kGd1eMinus24 = 0x1.357c299a88ea8p-80;
// The pinned x86 GDScript parser rounds the spelling 1e-30 one ULP below C++; Apple must run the literal oracle.
constexpr double kGd1eMinus30 = 0x1.4484bfeebc29fp-100;

inline R sin_(R a) { return ::sin(a.v); }
inline R cos_(R a) { return ::cos(a.v); }
inline R atan2_(R y, R x) { return ::atan2(y.v, x.v); }
#if defined(NK_ENGINE_SQRT_SSE2)
// NK-4: MinGW-w64 GCC emits out-of-line calls to libmingwex sqrt, which uses x87 fsqrt (extended precision, then a
// second rounding to double): occasionally 1 ulp from the correctly rounded value the engine's GDScript sqrt returns
// (pinned Windows binary). SSE2 sqrtsd is the IEEE-754 correctly rounded square root, including the default NaN for
// a negative operand and quiet propagation of a NaN operand. Defined only by build_windows.py.
inline R sqrt_(R a) {
	double r;
	__asm__("sqrtsd %1, %0" : "=x"(r) : "x"(a.v));
	return r;
}
#else
inline R sqrt_(R a) { return ::sqrt(a.v); }
#endif
inline R tanh_(R a) { return ::tanh(a.v); }

inline R pow_(R base, R exponent) {
	double e = exponent.v;
#if defined(NK_MATH_APPLE_ARM64)
	__asm__("" : "+w"(e)); // opaque to constant propagation: libSystem pow, never a folded multiply
#else
	__asm__("" : "+x"(e)); // opaque to constant propagation: libm pow, never a folded multiply
#endif
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
// Linux binary's NaN priority (probed by the oracle) is weight-first for the product and product-first for the sum.
// The pinned Apple engine's math-shim oracle selects `from` first in the sum
// (the Linux ordering produced 17 NaN-payload mismatches in the initial M1 run).
// Finite results are unchanged by this operand order (IEEE + and * commute exactly).
#if defined(NK_MATH_APPLE_ARM64)
inline R lerpf(R from, R to, R weight) { return from + (to - from) * weight; }
#elif defined(NK_ENGINE_LERP_SOURCE_ORDER)
// NK-4: the pinned Windows (MinGW) engine binary evaluates the product before `from` and keeps `(to - from)`
// left of `weight` (math_shim oracle probe on Windows, two-NaN priority). Defined only by build_windows.py;
// Linux preprocesses unchanged.
inline R lerpf(R from, R to, R weight) { return (to - from) * weight + from; }
#else
inline R lerpf(R from, R to, R weight) { return weight * (to - from) + from; }
#endif

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
