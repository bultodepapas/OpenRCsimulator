#pragma once

#include <array>
#include <cstddef>
#include <limits>
#include <vector>

namespace openrc::smooth_wake {

static_assert(sizeof(double) == 8, "smooth wake requires 64-bit double");
static_assert(std::numeric_limits<double>::is_iec559, "smooth wake requires IEEE-754 double");

using Vec3 = std::array<double, 3>;
using Pair = std::array<double, 2>;
using State13 = std::array<double, 13>;
using Loads6 = std::array<double, 6>;

inline constexpr std::size_t kMaxPieces = 16;
inline constexpr std::size_t kMaxProfileIntervals = 64;

struct ProfileInterval {
	double start = 0.0;
	double end = 0.0;
	double chord_start = 0.0;
	double chord_end = 0.0;
};

struct Piece {
	// 0 = horizontal tail, 1 = vertical tail.
	std::size_t surface = 0;
	double area = 0.0;
	double span = 0.0;
	Vec3 root{};
	Vec3 span_dir{};
	std::array<ProfileInterval, kMaxProfileIntervals> profile{};
	std::size_t profile_count = 0;
};

struct TailSurface {
	Vec3 position{};
	double lift_slope = 0.0;
	double free_slope = 0.0;
	bool has_free_slope = false;
	double control_effectiveness = 0.0;
	double incidence = 0.0;
	double downwash_per_cl = 0.0;
	double elevator_tau = 0.0;
	double free_incidence = 0.0;
};

struct Model {
	double propeller_diameter = 0.0;
	Vec3 shaft_axis{};
	Vec3 hub{};
	Pair wash_factor{};
	double swirl_factor = 0.0;
	double vertical_drift = 0.0;
	double edge_fraction = 0.0;
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

// Evaluates the complete E0b6p smooth-profile slipstream increment: the exact
// profile occupancy centroid baseline and its fixed GL5 distributed-swirl correction.
// `thrust_torque` is [shaft thrust N, shaft torque N m], already resolved by GDScript.
// `fade` is Slipstream.reverse_weight, including its stopped transported-wake override.
// `transported_dv` is either empty or one axial increment per piece.
// Returns false and zeroes output for invalid input or a non-finite result.
bool loads(const State13 &state, const Vec3 &velocity, const Pair &deflections, const Model &model,
		const Pair &thrust_torque, double rho, double fade, double downwash_cl,
		const std::vector<double> &transported_dv, Loads6 &output);

} // namespace openrc::smooth_wake
