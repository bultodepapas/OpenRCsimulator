// Standalone source-order witness for the actual NK-3 math header; no Godot
// dependency or stage qualification. Supply hexadecimal binary64 bit patterns:
//   witness FMA_A FMA_B FMA_C CORPUS...
// FMA_A/B/C must be 3ff0000002000000, 3feffffffc000000, bff0000000000000.
// CORPUS must contain both signed zeros, both signs of subnormal and infinity,
// two distinct quiet NaNs, and a finite nonzero normal value. JSON
// matrices are nested [left_index][right_index], with 16-digit numeric bits.
// Build with the target compiler, C++17, -fno-fast-math and -ffp-contract=off;
// inspect nk_arm64_witness_pow_literal in the optimized binary for a libm call.
#include "src/nk_math.hpp"

#include <array>
#include <cerrno>
#include <cfenv>
#include <cctype>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>
#include <vector>

using U64 = std::uint64_t;

static double from_bits(U64 value) {
	double result;
	std::memcpy(&result, &value, sizeof(result));
	return result;
}

static std::string hex64(U64 value) {
	char text[17];
	std::snprintf(text, sizeof(text), "%016llx", static_cast<unsigned long long>(value));
	return text;
}

static bool parse_hex(const char *text, U64 &value) {
	if (std::strlen(text) != 16) return false;
	for (int i = 0; i < 16; ++i) {
		if (!std::isxdigit(static_cast<unsigned char>(text[i]))) return false;
	}
	errno = 0;
	char *end = nullptr;
	value = static_cast<U64>(std::strtoull(text, &end, 16));
	return errno == 0 && end == text + 16;
}

static U64 fpcr() {
#if defined(NK_MATH_APPLE_ARM64)
	U64 result;
	__asm__ volatile("mrs %0, fpcr" : "=r"(result));
	return result;
#else
	return 0;
#endif
}

// This intentionally passes a literal exponent: disassembly must still show
// the pow call after optimization, rather than a constant-exponent rewrite.
extern "C" __attribute__((noinline)) double nk_arm64_witness_pow_literal(double base) {
	return nk::pow_(nk::R(base), nk::R(2.0)).v;
}

static nk::R operation(int op, nk::R a, nk::R b) {
	switch (op) {
		case 0: return a + b;
		case 1: return a - b;
		case 2: return a * b;
		default: return a / b;
	}
}

static bool overloads_match(int op, double a, double b, U64 expected) {
	nk::R left(a);
	nk::R right(b);
	nk::R mixed_left, mixed_right, compound(a);
	switch (op) {
		case 0: mixed_left = left + b; mixed_right = a + right; compound += right; break;
		case 1: mixed_left = left - b; mixed_right = a - right; compound -= right; break;
		case 2: mixed_left = left * b; mixed_right = a * right; compound *= right; break;
		default: mixed_left = left / b; mixed_right = a / right; compound /= right; break;
	}
	return nk::bits(mixed_left.v) == expected && nk::bits(mixed_right.v) == expected &&
			nk::bits(compound.v) == expected;
}

static void print_list(const std::vector<U64> &values) {
	std::cout << '[';
	for (std::size_t i = 0; i < values.size(); ++i) {
		if (i) std::cout << ',';
		std::cout << '"' << hex64(values[i]) << '"';
	}
	std::cout << ']';
}

static void print_matrix(const std::vector<U64> &values, std::size_t n) {
	std::cout << '[';
	for (std::size_t row = 0; row < n; ++row) {
		if (row) std::cout << ',';
		std::cout << '[';
		for (std::size_t col = 0; col < n; ++col) {
			if (col) std::cout << ',';
			std::cout << '"' << hex64(values[row * n + col]) << '"';
		}
		std::cout << ']';
	}
	std::cout << ']';
}

int main(int argc, char **argv) {
	constexpr std::size_t MAX_CORPUS = 64;
	if (argc < 6 || argc > static_cast<int>(4 + MAX_CORPUS)) {
		std::cerr << "usage: witness FMA_A FMA_B FMA_C CORPUS... (16 hex digits each)\n";
		return 2;
	}
	std::vector<U64> args(static_cast<std::size_t>(argc - 1));
	for (int i = 1; i < argc; ++i) {
		if (!parse_hex(argv[i], args[static_cast<std::size_t>(i - 1)])) {
			std::cerr << "invalid 16-digit hexadecimal argument at position " << i << '\n';
			return 2;
		}
	}
	if (args[0] != 0x3ff0000002000000ULL || args[1] != 0x3feffffffc000000ULL ||
			args[2] != 0xbff0000000000000ULL) {
		std::cerr << "FMA operands must match the documented discriminating witness\n";
		return 2;
	}
	const std::vector<U64> corpus(args.begin() + 3, args.end());
	bool zeros[2] = {}, subnormals[2] = {}, infinities[2] = {}, normal = false;
	bool saw_qnan = false, distinct_qnan = false;
	U64 first_qnan = 0;
	for (U64 bits : corpus) {
		const std::size_t sign = static_cast<std::size_t>(bits >> 63);
		const U64 exponent = bits & 0x7ff0000000000000ULL;
		const U64 fraction = bits & 0x000fffffffffffffULL;
		if (exponent == 0 && fraction == 0) zeros[sign] = true;
		else if (exponent == 0) subnormals[sign] = true;
		else if (exponent != 0x7ff0000000000000ULL) normal = true;
		else if (fraction == 0) infinities[sign] = true;
		else if ((fraction & 0x0008000000000000ULL) != 0) {
			if (!saw_qnan) { first_qnan = bits; saw_qnan = true; }
			else if (bits != first_qnan) distinct_qnan = true;
		}
	}
	if (!(zeros[0] && zeros[1] && subnormals[0] && subnormals[1] &&
			infinities[0] && infinities[1] && normal && distinct_qnan)) {
		std::cerr << "corpus lacks required signed boundary or distinct quiet-NaN values\n";
		return 2;
	}
	const std::size_t n = corpus.size();
	const U64 before = fpcr();
	const int rounding = std::fegetround();
	const nk::R a(from_bits(args[0])), b(from_bits(args[1])), c(from_bits(args[2]));
	const U64 separate = nk::bits(((a * b) + c).v);
	const U64 fused = nk::bits(std::fma(a.v, b.v, c.v));
	const bool fma_ok = rounding == FE_TONEAREST && separate == 0 && fused == 0xbc90000000000000ULL;
	std::array<std::vector<U64>, 6> matrices;
	for (auto &matrix : matrices) matrix.resize(n * n);
	std::size_t overload_mismatches = 0, helper_mismatches = 0;
	for (std::size_t i = 0; i < n; ++i) {
		for (std::size_t j = 0; j < n; ++j) {
			const double left = from_bits(corpus[i]), right = from_bits(corpus[j]);
			for (int op = 0; op < 4; ++op) {
				const U64 result = nk::bits(operation(op, nk::R(left), nk::R(right)).v);
				matrices[static_cast<std::size_t>(op)][i * n + j] = result;
				if (!overloads_match(op, left, right, result)) ++overload_mismatches;
			}
			matrices[4][i * n + j] = nk::bits(nk::maxf(nk::R(left), nk::R(right)).v);
			matrices[5][i * n + j] = nk::bits(nk::minf(nk::R(left), nk::R(right)).v);
			if (matrices[4][i * n + j] != nk::bits(left > right ? left : right) ||
					matrices[5][i * n + j] != nk::bits(left < right ? left : right)) ++helper_mismatches;
		}
	}
	std::vector<U64> pow_literal, pow_runtime;
	const double runtime_two = from_bits(0x4000000000000000ULL);
	for (U64 value : corpus) {
		const double base = from_bits(value);
		pow_literal.push_back(nk::bits(nk_arm64_witness_pow_literal(base)));
		pow_runtime.push_back(nk::bits(nk::pow_(nk::R(base), nk::R(runtime_two)).v));
	}
	const U64 after = fpcr();
	const bool ok = fma_ok && overload_mismatches == 0 && helper_mismatches == 0 &&
			pow_literal == pow_runtime && before == after;
	const char *names[] = {"add_bits", "sub_bits", "mul_bits", "div_bits", "max_bits", "min_bits"};
	std::cout << "{\"format\":\"openrc-nk3-ordered-math-witness-v1\","
			<< "\"scope\":\"standalone actual header; Godot and native evaluator parity not established\","
#if defined(NK_MATH_APPLE_ARM64)
			<< "\"architecture\":\"apple-arm64\",\"fpcr_before\":\"" << hex64(before)
			<< "\",\"fpcr_after\":\"" << hex64(after) << "\",";
#else
			<< "\"architecture\":\"x86_64\",\"fpcr_before\":null,\"fpcr_after\":null,";
#endif
	std::cout << "\"round_to_nearest\":" << (rounding == FE_TONEAREST ? "true" : "false")
			<< ",\"fma_separate_bits\":\"" << hex64(separate) << "\",\"fma_fused_bits\":\""
			<< hex64(fused) << "\",\"fma_witness_ok\":" << (fma_ok ? "true" : "false")
			<< ",\"overload_mismatches\":" << overload_mismatches
			<< ",\"helper_mismatches\":" << helper_mismatches << ",\"corpus_bits\":";
	print_list(corpus);
	for (std::size_t index = 0; index < matrices.size(); ++index) {
		std::cout << ",\"" << names[index] << "\":";
		print_matrix(matrices[index], n);
	}
	std::cout << ",\"pow_literal_two_bits\":"; print_list(pow_literal);
	std::cout << ",\"pow_runtime_two_bits\":"; print_list(pow_runtime);
	std::cout << ",\"self_test_ok\":" << (ok ? "true" : "false") << "}\n";
	return ok ? 0 : 1;
}
