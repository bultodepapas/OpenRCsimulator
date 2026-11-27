// NK-5d: conservative contact reach for the session's accepted tick (post_tick contact resolution).
// It never finds a contact. It only proves that none can exist this tick, so the GDScript sweep would
// return "no hit": every box the GDScript sweeps test lies inside one superset box around the tick's
// centre-of-gravity motion, widened by three times a reach radius at least the GDScript one (radius plus a
// rotational chord of at most twice the radius) and by explicit rounding margins.
#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <unordered_map>
#include <vector>

namespace nk {

class ContactReach {
public:
	static constexpr double kCell = 32.0;
	static constexpr int64_t kMaxProxies = 1 << 22;
	static constexpr int64_t kMaxCellsPerProxy = 64;
	static constexpr int64_t kMaxQueryCells = 256;
	static constexpr double kMaxGridCoordinate = 1.0e12; // keeps cell indices far from integer overflow
	static constexpr int kSceneryClear = 1;
	static constexpr int kLakeClear = 2;

	void clear() {
		ready_ = false;
		bounds_.clear();
		grid_.clear();
		large_.clear();
	}

	// bounds: six values per proxy (north min/max, east min/max, down min/max), all finite with min <= max.
	bool prepare(const std::vector<double> &bounds) {
		clear();
		if (bounds.empty() || bounds.size() % 6 != 0 || static_cast<int64_t>(bounds.size() / 6) > kMaxProxies) return false;
		for (double value : bounds) if (!std::isfinite(value)) return false;
		const int32_t count = static_cast<int32_t>(bounds.size() / 6);
		for (int32_t i = 0; i < count; ++i) {
			const double *b = bounds.data() + static_cast<size_t>(i) * 6;
			if (!(b[0] <= b[1]) || !(b[2] <= b[3]) || !(b[4] <= b[5])) return false;
			if (std::fabs(b[0]) > kMaxGridCoordinate || std::fabs(b[1]) > kMaxGridCoordinate ||
					std::fabs(b[2]) > kMaxGridCoordinate || std::fabs(b[3]) > kMaxGridCoordinate) {
				large_.push_back(i); // checked on every query
				continue;
			}
			const int64_t n0 = cell(b[0]), n1 = cell(b[1]), e0 = cell(b[2]), e1 = cell(b[3]);
			// Compare each span before multiplying, so the product cannot overflow.
			if (n1 - n0 >= kMaxCellsPerProxy || e1 - e0 >= kMaxCellsPerProxy || (n1 - n0 + 1) * (e1 - e0 + 1) > kMaxCellsPerProxy) {
				large_.push_back(i);
				continue;
			}
			for (int64_t n = n0; n <= n1; ++n) for (int64_t e = e0; e <= e1; ++e) grid_[key(n, e)].push_back(i);
		}
		bounds_ = bounds;
		ready_ = true;
		return true;
	}

	bool ready() const { return ready_; }

	// previous/candidate: 13-value rigid-body states (position first). hull: body points, three per point.
	// extra_reach: any further probe distance from the centre of gravity (gear contacts, propeller disc).
	// lake_threshold: the GDScript lake reject's highest possible water "down" minus its contact epsilon,
	// or NaN for no lake. lake_bank (NK-6g, optional): LakeCollision._polygon_bounds of the bank, north min/max then
	// east min/max; the sweep's horizontal reject tests its swept probe box against it. Returns
	// kSceneryClear | kLakeClear bits that are proven; 0 on any doubt.
	int reach_clear(const double *previous, const double *candidate, const double *hull, int64_t hull_size,
			double extra_reach, double lake_threshold, const double *lake_bank = nullptr) const {
		if (previous == nullptr || candidate == nullptr || hull == nullptr || hull_size <= 0 || hull_size % 3 != 0) return 0;
		if (!std::isfinite(extra_reach) || extra_reach < 0.0) return 0;
		double radius = extra_reach;
		for (int64_t i = 0; i < hull_size; i += 3) {
			const double r = std::sqrt(hull[i] * hull[i] + hull[i + 1] * hull[i + 1] + hull[i + 2] * hull[i + 2]);
			if (!std::isfinite(r)) return 0;
			radius = std::max(radius, r);
		}
		// At least the GDScript radius, then radius + rotational chord (<= 2 radius + 1e-9) + slack.
		const double reach = radius * (1.0 + 1.0e-9) + 1.0e-6;
		const double pad = 3.0 * reach + 1.0e-6;
		double lo[3], hi[3];
		for (int axis = 0; axis < 3; ++axis) {
			const double a = previous[axis], b = candidate[axis];
			if (!std::isfinite(a) || !std::isfinite(b)) return 0;
			lo[axis] = std::min(a, b) - pad;
			hi[axis] = std::max(a, b) + pad;
			const double slack = 1.0e-9 * (std::fabs(lo[axis]) + std::fabs(hi[axis]) + 1.0);
			lo[axis] -= slack;
			hi[axis] += slack;
			if (!std::isfinite(lo[axis]) || !std::isfinite(hi[axis])) return 0;
		}
		int mask = 0;
		if (ready_ && scenery_clear(lo, hi)) mask |= kSceneryClear;
		if (std::isfinite(lake_threshold) && hi[2] < lake_threshold) mask |= kLakeClear;
		// NK-6g: the sweep's box (CG path widened by its radius) lies inside lo/hi; missing the bank box misses it too.
		if (std::isfinite(lake_threshold) && lake_bank != nullptr && std::isfinite(lake_bank[0]) &&
				std::isfinite(lake_bank[1]) && std::isfinite(lake_bank[2]) && std::isfinite(lake_bank[3]) &&
				(lake_bank[1] < lo[0] || lake_bank[0] > hi[0] || lake_bank[3] < lo[1] || lake_bank[2] > hi[1])) {
			mask |= kLakeClear;
		}
		return mask;
	}

private:
	bool ready_ = false;
	std::vector<double> bounds_;
	std::unordered_map<int64_t, std::vector<int32_t>> grid_;
	std::vector<int32_t> large_;

	static int64_t cell(double value) { return static_cast<int64_t>(std::floor(value / kCell)); }
	// Distinct cells may share a key only far outside the grid range; a shared bucket adds checks, never hides one.
	static int64_t key(int64_t n, int64_t e) {
		return static_cast<int64_t>((static_cast<uint64_t>(n) << 32) ^ static_cast<uint64_t>(static_cast<uint32_t>(e)));
	}

	bool overlaps(int32_t index, const double *lo, const double *hi) const {
		const double *b = bounds_.data() + static_cast<size_t>(index) * 6;
		return b[1] >= lo[0] && b[0] <= hi[0] && b[3] >= lo[1] && b[2] <= hi[1] && b[5] >= lo[2] && b[4] <= hi[2];
	}

	bool scenery_clear(const double *lo, const double *hi) const {
		for (int32_t index : large_) if (overlaps(index, lo, hi)) return false;
		for (int axis = 0; axis < 2; ++axis) {
			if (std::fabs(lo[axis]) > kMaxGridCoordinate || std::fabs(hi[axis]) > kMaxGridCoordinate) return false;
		}
		const int64_t n0 = cell(lo[0]), n1 = cell(hi[0]), e0 = cell(lo[1]), e1 = cell(hi[1]);
		if (n1 < n0 || e1 < e0 || n1 - n0 >= kMaxQueryCells || e1 - e0 >= kMaxQueryCells ||
				(n1 - n0 + 1) * (e1 - e0 + 1) > kMaxQueryCells) return false;
		for (int64_t n = n0; n <= n1; ++n) {
			for (int64_t e = e0; e <= e1; ++e) {
				const auto found = grid_.find(key(n, e));
				if (found == grid_.end()) continue;
				for (int32_t index : found->second) if (overlaps(index, lo, hi)) return false;
			}
		}
		return true;
	}
};

} // namespace nk
