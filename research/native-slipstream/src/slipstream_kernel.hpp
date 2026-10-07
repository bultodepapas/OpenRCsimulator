#pragma once

#include <array>
#include <cstddef>
#include <limits>

namespace openrc::slipstream {

static_assert(sizeof(double) == 8, "native slipstream requires 64-bit double");
static_assert(std::numeric_limits<double>::is_iec559, "native slipstream requires IEEE-754 double");

using Vec3 = std::array<double, 3>;
using State13 = std::array<double, 13>;
using Pair = std::array<double, 2>;
using Loads6 = std::array<double, 6>;

inline constexpr std::size_t kMaxPieces = 16;

struct Piece {
	// 0 = horizontal tail, 1 = vertical tail.
	std::size_t surface = 0;
	double area = 0.0;
	Vec3 root{};
	Vec3 span_dir{};
	double span = 0.0;
	Pair chords{};
};

struct TailSurface {
	Vec3 position{};
	double lift_slope = 0.0;
	double control_effectiveness = 0.0;
	double incidence = 0.0;
};

struct Model {
	double propeller_diameter = 0.0;
	Vec3 shaft_axis{};
	Vec3 hub{};
	Pair wash_factor{};
	double swirl_factor = 0.0;
	double vertical_drift = 0.0;
	Vec3 cg_le{};
	std::array<TailSurface, 2> tails{};
	double tail_local_limit = 0.0;
	double tail_stall_end = 0.0;
	double tail_cd0 = 0.0;
	double tail_k = 0.0;
	double tail_cd90 = 0.0;
	std::array<Piece, kMaxPieces> pieces{};
	std::size_t piece_count = 0;
};

// Evaluates only the slipstream increment on the tail surfaces. `thrust_torque`
// is [thrust N, shaft torque N m], already resolved by the GDScript caller.
// Returns false for an invalid or non-finite input/result; output is then zeroed.
bool tail_loads(const State13 &state, const Vec3 &velocity, const Pair &deflections,
		const Model &model, const Pair &thrust_torque, double rho, Loads6 &output);

} // namespace openrc::slipstream
