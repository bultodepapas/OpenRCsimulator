// NK-1 math identity spike: libm (std::) and Godot UtilityFunctions evaluated in a GDExtension,
// compared bit for bit with GDScript results by the harness in ../project/spike.gd.
// Research only; never installed into app/.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <dlfcn.h>
#include <gnu/libc-version.h>
#include <xmmintrin.h>

#include <algorithm>
#include <cfenv>
#include <cfloat>
#include <chrono>
#include <cinttypes>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <limits>
#include <vector>

namespace {

using godot::UtilityFunctions;

enum Fn : int {
	FN_COPY = 0,
	FN_SIN,
	FN_COS,
	FN_TAN,
	FN_ASIN,
	FN_ACOS,
	FN_ATAN,
	FN_ATAN2,
	FN_SQRT,
	FN_POW,
	FN_EXP,
	FN_LOG,
	FN_SINH,
	FN_COSH,
	FN_TANH,
	FN_FMOD,
	FN_FLOOR,
	FN_COUNT,
};

const char *const FN_NAMES[FN_COUNT] = {
	"copy", "sin", "cos", "tan", "asin", "acos", "atan", "atan2", "sqrt",
	"pow", "exp", "log", "sinh", "cosh", "tanh", "fmod", "floor",
};

// Compiler-transformation probes: literal arguments the optimizer may rewrite.
enum ProbeVariant : int {
	V_SINCOS_SIN = 0, // glibc sincos(); GCC 13 -O3 fuses sin(v)+cos(v) of one value into it under the pinned flags.
	V_SINCOS_COS,
	V_POW_LIT_2, // pow(x, 2.0): GCC 13 -O3 emits x * x (mulsd) even without fast-math.
	V_POW_LIT_HALF, // pow(x, 0.5)
	V_POW_LIT_3_5, // pow(x, 3.5)
	V_POW_LIT_INV_GAMMA, // pow(x, 1.0 / 1.4)
	V_COUNT,
};

const char *const VARIANT_NAMES[V_COUNT] = {
	"sincos_sin", "sincos_cos", "pow_lit_2", "pow_lit_0.5", "pow_lit_3.5", "pow_lit_1/1.4",
};

bool is_binary(int fn) {
	return fn == FN_ATAN2 || fn == FN_POW || fn == FN_FMOD;
}

template <typename Op>
void apply_unary(const double *a, double *out, int64_t n, Op op) {
	for (int64_t i = 0; i < n; ++i) {
		out[i] = op(a[i]);
	}
}

template <typename Op>
void apply_binary(const double *a, const double *b, double *out, int64_t n, Op op) {
	for (int64_t i = 0; i < n; ++i) {
		out[i] = op(a[i], b[i]);
	}
}

void run_std(int fn, const double *a, const double *b, double *out, int64_t n) {
	switch (fn) {
		case FN_COPY: apply_unary(a, out, n, [](double x) { return x; }); break;
		case FN_SIN: apply_unary(a, out, n, [](double x) { return std::sin(x); }); break;
		case FN_COS: apply_unary(a, out, n, [](double x) { return std::cos(x); }); break;
		case FN_TAN: apply_unary(a, out, n, [](double x) { return std::tan(x); }); break;
		case FN_ASIN: apply_unary(a, out, n, [](double x) { return std::asin(x); }); break;
		case FN_ACOS: apply_unary(a, out, n, [](double x) { return std::acos(x); }); break;
		case FN_ATAN: apply_unary(a, out, n, [](double x) { return std::atan(x); }); break;
		case FN_ATAN2: apply_binary(a, b, out, n, [](double y, double x) { return std::atan2(y, x); }); break;
		case FN_SQRT: apply_unary(a, out, n, [](double x) { return std::sqrt(x); }); break;
		case FN_POW: apply_binary(a, b, out, n, [](double x, double y) { return std::pow(x, y); }); break;
		case FN_EXP: apply_unary(a, out, n, [](double x) { return std::exp(x); }); break;
		case FN_LOG: apply_unary(a, out, n, [](double x) { return std::log(x); }); break;
		case FN_SINH: apply_unary(a, out, n, [](double x) { return std::sinh(x); }); break;
		case FN_COSH: apply_unary(a, out, n, [](double x) { return std::cosh(x); }); break;
		case FN_TANH: apply_unary(a, out, n, [](double x) { return std::tanh(x); }); break;
		case FN_FMOD: apply_binary(a, b, out, n, [](double x, double y) { return std::fmod(x, y); }); break;
		case FN_FLOOR: apply_unary(a, out, n, [](double x) { return std::floor(x); }); break;
		default: break;
	}
}

void run_utility(int fn, const double *a, const double *b, double *out, int64_t n) {
	switch (fn) {
		case FN_COPY: apply_unary(a, out, n, [](double x) { return x; }); break;
		case FN_SIN: apply_unary(a, out, n, [](double x) { return UtilityFunctions::sin(x); }); break;
		case FN_COS: apply_unary(a, out, n, [](double x) { return UtilityFunctions::cos(x); }); break;
		case FN_TAN: apply_unary(a, out, n, [](double x) { return UtilityFunctions::tan(x); }); break;
		case FN_ASIN: apply_unary(a, out, n, [](double x) { return UtilityFunctions::asin(x); }); break;
		case FN_ACOS: apply_unary(a, out, n, [](double x) { return UtilityFunctions::acos(x); }); break;
		case FN_ATAN: apply_unary(a, out, n, [](double x) { return UtilityFunctions::atan(x); }); break;
		case FN_ATAN2: apply_binary(a, b, out, n, [](double y, double x) { return UtilityFunctions::atan2(y, x); }); break;
		case FN_SQRT: apply_unary(a, out, n, [](double x) { return UtilityFunctions::sqrt(x); }); break;
		case FN_POW: apply_binary(a, b, out, n, [](double x, double y) { return UtilityFunctions::pow(x, y); }); break;
		case FN_EXP: apply_unary(a, out, n, [](double x) { return UtilityFunctions::exp(x); }); break;
		case FN_LOG: apply_unary(a, out, n, [](double x) { return UtilityFunctions::log(x); }); break;
		case FN_SINH: apply_unary(a, out, n, [](double x) { return UtilityFunctions::sinh(x); }); break;
		case FN_COSH: apply_unary(a, out, n, [](double x) { return UtilityFunctions::cosh(x); }); break;
		case FN_TANH: apply_unary(a, out, n, [](double x) { return UtilityFunctions::tanh(x); }); break;
		case FN_FMOD: apply_binary(a, b, out, n, [](double x, double y) { return UtilityFunctions::fmod(x, y); }); break;
		case FN_FLOOR: apply_unary(a, out, n, [](double x) { return UtilityFunctions::floorf(x); }); break;
		default: break;
	}
}

// Deterministic generator: SplitMix64 with uniform doubles from the top 53 bits.
struct SplitMix64 {
	uint64_t state;
	uint64_t next() {
		uint64_t z = (state += 0x9E3779B97F4A7C15ULL);
		z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
		z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
		return z ^ (z >> 31);
	}
	double unit() { return static_cast<double>(next() >> 11) * 0x1.0p-53; }
	double uniform(double lo, double hi) { return lo + (hi - lo) * unit(); }
};

constexpr double K_PI = 3.141592653589793;
constexpr double K_INF = std::numeric_limits<double>::infinity();
const double K_NAN = std::numeric_limits<double>::quiet_NaN();

std::vector<double> unary_edges() {
	std::vector<double> e = {
		0.0, -0.0, 4.9406564584124654e-324, -4.9406564584124654e-324, 2.2250738585072014e-308,
		1e-300, -1e-300, 1e-16, -1e-16, 1e-8, 0.5, -0.5, 1.0, -1.0, std::nextafter(1.0, 2.0),
		std::nextafter(-1.0, -2.0), std::nextafter(1.0, 0.0), 2.0, -2.0, 6.0, 1e22, -1e22, 1e300,
		-1e300, DBL_MAX, -DBL_MAX, K_INF, -K_INF, K_NAN, -K_NAN, 709.782712893384, 710.0, -745.1332191019411,
		-746.0, 2.0 * K_PI, -2.0 * K_PI, 3.0e5, 1e6 + 0.5,
	};
	for (int k = -16; k <= 16; ++k) {
		const double v = static_cast<double>(k) * (K_PI / 2.0);
		e.push_back(v);
		e.push_back(std::nextafter(v, K_INF));
		e.push_back(std::nextafter(v, -K_INF));
	}
	return e;
}

void binary_edges(std::vector<double> &a, std::vector<double> &b) {
	const double s[] = {0.0, -0.0, 1.0, -1.0, 0.5, 2.0, -2.0, 3.0, 1e-300, 1e300, K_INF, -K_INF, K_NAN, K_PI / 2.0, 2.0 * K_PI, 1024.0};
	for (double x : s) {
		for (double y : s) {
			a.push_back(x);
			b.push_back(y);
		}
	}
}

int64_t ordered(double d) {
	int64_t i;
	std::memcpy(&i, &d, sizeof(i));
	return i < 0 ? std::numeric_limits<int64_t>::min() - i : i;
}

uint64_t bits_of(double d) {
	uint64_t u;
	std::memcpy(&u, &d, sizeof(u));
	return u;
}

godot::String hex_bits(double d) {
	char buffer[32];
	std::snprintf(buffer, sizeof(buffer), "0x%016" PRIx64, bits_of(d));
	return godot::String(buffer);
}

godot::String repr(double d) {
	char buffer[48];
	std::snprintf(buffer, sizeof(buffer), "%.17g", d);
	return godot::String(buffer);
}

volatile double g_sink = 0.0;

double median_of(std::vector<double> values) {
	std::sort(values.begin(), values.end());
	const size_t n = values.size();
	return n % 2 ? values[n / 2] : 0.5 * (values[n / 2 - 1] + values[n / 2]);
}

} // namespace

class OpenRCMathSpike : public godot::RefCounted {
	GDCLASS(OpenRCMathSpike, godot::RefCounted)

protected:
	static void _bind_methods() {
		using godot::ClassDB;
		using godot::D_METHOD;
		ClassDB::bind_method(D_METHOD("function_names"), &OpenRCMathSpike::function_names);
		ClassDB::bind_method(D_METHOD("variant_names"), &OpenRCMathSpike::variant_names);
		ClassDB::bind_method(D_METHOD("is_binary_function", "fn"), &OpenRCMathSpike::is_binary_function);
		ClassDB::bind_method(D_METHOD("generate_inputs", "fn", "count", "seed"), &OpenRCMathSpike::generate_inputs);
		ClassDB::bind_method(D_METHOD("eval_std", "fn", "a", "b"), &OpenRCMathSpike::eval_std);
		ClassDB::bind_method(D_METHOD("eval_utility", "fn", "a", "b"), &OpenRCMathSpike::eval_utility);
		ClassDB::bind_method(D_METHOD("eval_variant", "variant", "a"), &OpenRCMathSpike::eval_variant);
		ClassDB::bind_method(D_METHOD("time_route", "route", "fn", "a", "b", "batches"), &OpenRCMathSpike::time_route);
		ClassDB::bind_method(D_METHOD("compare", "reference", "candidate", "a", "b"), &OpenRCMathSpike::compare);
		ClassDB::bind_method(D_METHOD("build_info"), &OpenRCMathSpike::build_info);
	}

public:
	godot::PackedStringArray function_names() const {
		godot::PackedStringArray names;
		for (const char *name : FN_NAMES) {
			names.push_back(name);
		}
		return names;
	}

	godot::PackedStringArray variant_names() const {
		godot::PackedStringArray names;
		for (const char *name : VARIANT_NAMES) {
			names.push_back(name);
		}
		return names;
	}

	bool is_binary_function(int fn) const { return is_binary(fn); }

	// Returns {a, b, random_count, edge_count}; b is empty for unary functions.
	godot::Dictionary generate_inputs(int fn, int64_t count, int64_t seed) const {
		SplitMix64 rng{static_cast<uint64_t>(seed) ^ (0xA24BAED4963EE407ULL * static_cast<uint64_t>(fn + 1))};
		std::vector<double> a;
		std::vector<double> b;
		a.reserve(count + 300);
		b.reserve(is_binary(fn) ? count + 300 : 0);
		const double pow_exponents[] = {1.0 / 1.4, 0.2857142857, 3.5};
		for (int64_t i = 0; i < count; ++i) {
			switch (fn) {
				case FN_SIN: case FN_COS: case FN_TAN: a.push_back(rng.uniform(-4.0 * K_PI, 4.0 * K_PI)); break;
				case FN_ASIN: case FN_ACOS: a.push_back(rng.uniform(-1.0, 1.0)); break;
				case FN_ATAN: a.push_back(rng.uniform(-10.0, 10.0)); break;
				case FN_ATAN2:
					a.push_back(rng.uniform(-50.0, 50.0));
					b.push_back(rng.uniform(-50.0, 50.0));
					break;
				case FN_SQRT: a.push_back(rng.uniform(0.0, 1.0e4)); break;
				case FN_POW: {
					a.push_back(rng.uniform(0.0, 2.0));
					const double pick = rng.unit();
					b.push_back(pick < 0.7 ? rng.uniform(0.0, 4.0) : pow_exponents[static_cast<int>(rng.next() % 3)]);
					break;
				}
				case FN_EXP: a.push_back(rng.uniform(-30.0, 30.0)); break;
				case FN_LOG: a.push_back(std::exp2(rng.uniform(-40.0, 40.0))); break;
				case FN_SINH: case FN_COSH: case FN_TANH: a.push_back(rng.uniform(-20.0, 20.0)); break;
				case FN_FMOD:
					a.push_back(rng.uniform(-100.0, 100.0));
					b.push_back(rng.unit() < 0.5 ? 2.0 * K_PI : rng.uniform(0.5, 10.0));
					break;
				case FN_FLOOR: a.push_back(rng.uniform(-1.0e6, 1.0e6)); break;
				default: a.push_back(rng.uniform(-1.0e3, 1.0e3)); break;
			}
		}
		const size_t before = a.size();
		if (is_binary(fn)) {
			binary_edges(a, b);
		} else {
			const std::vector<double> edges = unary_edges();
			a.insert(a.end(), edges.begin(), edges.end());
		}
		godot::PackedFloat64Array pa;
		pa.resize(static_cast<int64_t>(a.size()));
		std::memcpy(pa.ptrw(), a.data(), a.size() * sizeof(double));
		godot::PackedFloat64Array pb;
		pb.resize(static_cast<int64_t>(b.size()));
		if (!b.empty()) {
			std::memcpy(pb.ptrw(), b.data(), b.size() * sizeof(double));
		}
		godot::Dictionary result;
		result["a"] = pa;
		result["b"] = pb;
		result["random_count"] = static_cast<int64_t>(before);
		result["edge_count"] = static_cast<int64_t>(a.size() - before);
		return result;
	}

	godot::PackedFloat64Array eval_std(int fn, const godot::PackedFloat64Array &a, const godot::PackedFloat64Array &b) const {
		return evaluate(false, fn, a, b);
	}

	godot::PackedFloat64Array eval_utility(int fn, const godot::PackedFloat64Array &a, const godot::PackedFloat64Array &b) const {
		return evaluate(true, fn, a, b);
	}

	// Compiler-rewrite probes; sincos variants return the sin or cos half of one sincos() call.
	godot::PackedFloat64Array eval_variant(int variant, const godot::PackedFloat64Array &a) const {
		const int64_t n = a.size();
		godot::PackedFloat64Array out;
		out.resize(n);
		const double *x = a.ptr();
		double *y = out.ptrw();
		std::vector<double> other(static_cast<size_t>(n));
		switch (variant) {
			case V_SINCOS_SIN:
			case V_SINCOS_COS: {
				double *s = variant == V_SINCOS_SIN ? y : other.data();
				double *c = variant == V_SINCOS_SIN ? other.data() : y;
				for (int64_t i = 0; i < n; ++i) {
					::sincos(x[i], &s[i], &c[i]);
				}
				break;
			}
			case V_POW_LIT_2: apply_unary(x, y, n, [](double v) { return std::pow(v, 2.0); }); break;
			case V_POW_LIT_HALF: apply_unary(x, y, n, [](double v) { return std::pow(v, 0.5); }); break;
			case V_POW_LIT_3_5: apply_unary(x, y, n, [](double v) { return std::pow(v, 3.5); }); break;
			case V_POW_LIT_INV_GAMMA: apply_unary(x, y, n, [](double v) { return std::pow(v, 1.0 / 1.4); }); break;
			default: break;
		}
		return out;
	}

	// route 0 = std::, 1 = UtilityFunctions. Median and minimum ns per call over batches after one warmup pass.
	godot::Dictionary time_route(int route, int fn, const godot::PackedFloat64Array &a, const godot::PackedFloat64Array &b, int batches) const {
		const int64_t n = a.size();
		std::vector<double> out(static_cast<size_t>(n));
		const double *pa = a.ptr();
		const double *pb = is_binary(fn) ? b.ptr() : pa;
		auto run = [&]() {
			if (route == 0) {
				run_std(fn, pa, pb, out.data(), n);
			} else {
				run_utility(fn, pa, pb, out.data(), n);
			}
		};
		run();
		std::vector<double> samples;
		for (int k = 0; k < std::max(1, batches); ++k) {
			const auto t0 = std::chrono::steady_clock::now();
			run();
			const auto t1 = std::chrono::steady_clock::now();
			samples.push_back(std::chrono::duration<double, std::nano>(t1 - t0).count() / static_cast<double>(n));
			double checksum = 0.0;
			for (double v : out) {
				checksum += v;
			}
			g_sink = g_sink + checksum;
		}
		godot::Dictionary result;
		result["median_ns"] = median_of(samples);
		result["min_ns"] = *std::min_element(samples.begin(), samples.end());
		result["batches"] = static_cast<int64_t>(samples.size());
		return result;
	}

	// Bitwise comparison; reference is the GDScript result.
	godot::Dictionary compare(const godot::PackedFloat64Array &reference, const godot::PackedFloat64Array &candidate,
			const godot::PackedFloat64Array &a, const godot::PackedFloat64Array &b) const {
		godot::Dictionary result;
		const int64_t n = reference.size();
		if (candidate.size() != n) {
			result["error"] = "size mismatch";
			return result;
		}
		int64_t identical = 0;
		int64_t nan_bits = 0;
		int64_t zero_sign = 0;
		int64_t class_mismatch = 0;
		int64_t finite_diff = 0;
		uint64_t max_ulp = 0;
		godot::Array examples;
		const double *r = reference.ptr();
		const double *c = candidate.ptr();
		for (int64_t i = 0; i < n; ++i) {
			if (bits_of(r[i]) == bits_of(c[i])) {
				++identical;
				continue;
			}
			uint64_t ulp = 0;
			if (std::isnan(r[i]) && std::isnan(c[i])) {
				++nan_bits;
			} else if (std::isnan(r[i]) != std::isnan(c[i]) || std::isinf(r[i]) != std::isinf(c[i])) {
				++class_mismatch;
			} else if (r[i] == c[i]) {
				++zero_sign;
			} else {
				++finite_diff;
				const int64_t x = ordered(r[i]);
				const int64_t y = ordered(c[i]);
				ulp = x > y ? static_cast<uint64_t>(x) - static_cast<uint64_t>(y) : static_cast<uint64_t>(y) - static_cast<uint64_t>(x);
				max_ulp = std::max(max_ulp, ulp);
			}
			if (examples.size() < 4) {
				godot::Dictionary example;
				example["index"] = i;
				example["a"] = i < a.size() ? repr(a[i]) : godot::String();
				example["b"] = i < b.size() ? repr(b[i]) : godot::String();
				example["reference"] = repr(r[i]) + " " + hex_bits(r[i]);
				example["candidate"] = repr(c[i]) + " " + hex_bits(c[i]);
				example["ulp"] = static_cast<int64_t>(ulp);
				examples.push_back(example);
			}
		}
		result["count"] = n;
		result["identical"] = identical;
		result["nan_payload_only"] = nan_bits;
		result["zero_sign_only"] = zero_sign;
		result["class_mismatch"] = class_mismatch;
		result["finite_diff"] = finite_diff;
		result["max_ulp"] = static_cast<int64_t>(max_ulp);
		result["examples"] = examples;
		return result;
	}

	godot::Dictionary build_info() const {
		godot::Dictionary info;
		info["compiler"] = godot::String(__VERSION__);
#ifdef __OPTIMIZE__
		info["optimize"] = true;
#else
		info["optimize"] = false;
#endif
#ifdef __FAST_MATH__
		info["fast_math"] = true;
#else
		info["fast_math"] = false;
#endif
#ifdef __FP_FAST_FMA
		info["fp_fast_fma"] = true;
#else
		info["fp_fast_fma"] = false;
#endif
		info["flt_eval_method"] = static_cast<int64_t>(FLT_EVAL_METHOD);
		info["math_errhandling"] = static_cast<int64_t>(math_errhandling);
		info["iec559"] = std::numeric_limits<double>::is_iec559;
		info["glibc_compile"] = godot::String::num_int64(__GLIBC__) + "." + godot::String::num_int64(__GLIBC_MINOR__);
		info["glibc_runtime"] = godot::String(gnu_get_libc_version());
		info["fe_round_to_nearest"] = std::fegetround() == FE_TONEAREST;
		char mxcsr[16];
		std::snprintf(mxcsr, sizeof(mxcsr), "0x%04x", _mm_getcsr());
		info["mxcsr"] = godot::String(mxcsr);
		Dl_info dl{};
		double (*sin_ptr)(double) = &::sin;
		if (dladdr(reinterpret_cast<void *>(sin_ptr), &dl) && dl.dli_fname) {
			info["sin_resolved_in"] = godot::String(dl.dli_fname);
		}
		return info;
	}

private:
	godot::PackedFloat64Array evaluate(bool utility, int fn, const godot::PackedFloat64Array &a, const godot::PackedFloat64Array &b) const {
		const int64_t n = a.size();
		godot::PackedFloat64Array out;
		out.resize(n);
		const double *pb = is_binary(fn) ? b.ptr() : a.ptr();
		if (utility) {
			run_utility(fn, a.ptr(), pb, out.ptrw(), n);
		} else {
			run_std(fn, a.ptr(), pb, out.ptrw(), n);
		}
		return out;
	}
};

void initialize_openrc_math_spike(godot::ModuleInitializationLevel level) {
	if (level == godot::MODULE_INITIALIZATION_LEVEL_SCENE) {
		godot::ClassDB::register_class<OpenRCMathSpike>();
	}
}

void uninitialize_openrc_math_spike(godot::ModuleInitializationLevel) {}

extern "C" GDExtensionBool GDE_EXPORT openrc_math_spike_library_init(
		GDExtensionInterfaceGetProcAddress get_proc_address, GDExtensionClassLibraryPtr library,
		GDExtensionInitialization *initialization) {
	godot::GDExtensionBinding::InitObject init_object(get_proc_address, library, initialization);
	init_object.register_initializer(initialize_openrc_math_spike);
	init_object.register_terminator(uninitialize_openrc_math_spike);
	init_object.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_object.init();
}
