// NK-9a: app/statistics/detector.gd's speed window (_collect_speed and its helpers), exact. The detector keeps every
// other rule; this holds the window, the pending candidates, the previous accepted sample and the rejection counts,
// and reproduces the GDScript's arithmetic order. Sorting, maxf and absf call the engine's own functions, so equal
// values and signed zeros order and compare as GDScript's. The snapshot and restore exchange the GDScript's own
// dictionaries (String keys, as its quoted literals make them).
#pragma once

#include <cmath>
#include <cstdint>
#include <initializer_list>
#include <utility>
#include <vector>

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace nk {
namespace stats {

class SpeedWindow {
public:
	// [speed_exclusion_after_activation_s, speed cap, speed_acceleration_limit_mps2, speed_window_s, max_speed_samples,
	//  speed_stability_absolute_mps, speed_stability_fraction], the detector's resolved thresholds and its cap.
	bool bind(const godot::PackedFloat64Array &t) {
		ready_ = false;
		if (t.size() != 7) return false;
		for (int64_t i = 0; i < t.size(); ++i) {
			if (!std::isfinite(t[i])) return false;
		}
		exclusion_ = t[0];
		cap_ = t[1];
		acceleration_ = t[2];
		window_s_limit_ = t[3];
		max_samples_ = static_cast<int64_t>(t[4]);
		stability_absolute_ = t[5];
		stability_fraction_ = t[6];
		clear();
		counts_.clear();
		ready_ = max_samples_ >= 1;
		return ready_;
	}

	bool ready() const { return ready_; }

	// _clear_speed_state
	void clear() {
		window_.clear();
		head_ = 0;
		window_s_ = 0.0;
		pending_.clear();
		pending_head_ = 0;
		has_previous_ = false;
	}

	void clear_counts() { counts_.clear(); }

	// _collect_speed(sample, dt, tick) with the observe clock, the sample's incident and ground_contact flags as the
	// detector reads them, and its flight record (maxima written in place, as the GDScript writes them).
	void collect(const godot::Dictionary &sample, double dt, int64_t tick, double clock_s, bool incident,
			bool ground_contact, godot::Dictionary flight) {
		if (clock_s <= exclusion_ + 1e-12) {
			clear();
			return;
		}
		if (incident || ground_contact) {
			clear();
			return;
		}
		const double tas = finite_nonnegative_value(sample.get(k_tas_, -1.0));
		const double ground_speed = finite_nonnegative_value(sample.get(k_groundspeed_, -1.0));
		double position[3], velocity[3];
		const bool position_ok = vector3(sample.get(k_position_, godot::Array()), position);
		const bool velocity_ok = vector3(sample.get(k_velocity_ned_, godot::Array()), velocity);
		if (tas < 0.0 || ground_speed < 0.0 || !position_ok || !velocity_ok) {
			reject(k_invalid_sample_);
			clear();
			return;
		}
		if (tas > cap_ || ground_speed > cap_) {
			reject(k_speed_cap_);
			clear();
			return;
		}
		if (has_previous_) {
			const double max_delta = acceleration_ * dt + 1e-9;
			if (absf(tas - previous_tas_) > max_delta || absf(ground_speed - previous_gs_) > max_delta) {
				reject(k_acceleration_);
				clear();
				return;
			}
			if (position_discontinuous(position, velocity, dt, ground_speed)) {
				reject(k_position_discontinuity_);
				clear();
				return;
			}
		}
		has_previous_ = true;
		previous_tick_ = tick;
		previous_tas_ = tas;
		previous_gs_ = ground_speed;
		for (int i = 0; i < 3; ++i) {
			previous_position_[i] = position[i];
			previous_velocity_[i] = velocity[i];
		}
		window_.push_back({tick, dt, tas, ground_speed});
		window_s_ += dt;
		trim();
		if (window_s_ + 1e-12 >= window_s_limit_) add_candidate(tick, clock_s, flight);
		commit(clock_s, flight);
	}

	// [effective window, window_s, effective pending, previous speed, rejection counts] as snapshot() reads them.
	godot::Array snapshot() const {
		godot::Array window;
		for (size_t i = head_; i < window_.size(); ++i) {
			godot::Dictionary entry;
			entry[k_tick_] = window_[i].tick;
			entry[k_dt_] = window_[i].dt;
			entry[k_tas_] = window_[i].tas;
			entry[k_groundspeed_] = window_[i].gs;
			window.push_back(entry);
		}
		godot::Array pending;
		for (size_t i = pending_head_; i < pending_.size(); ++i) {
			godot::Dictionary entry;
			entry[k_tick_] = pending_[i].tick;
			entry[k_time_s_] = pending_[i].time_s;
			entry[k_tas_] = pending_[i].tas;
			entry[k_groundspeed_] = pending_[i].gs;
			pending.push_back(entry);
		}
		godot::Dictionary previous;
		if (has_previous_) {
			previous[k_tick_] = previous_tick_;
			previous[k_tas_] = previous_tas_;
			previous[k_groundspeed_] = previous_gs_;
			godot::Array p, v;
			for (int i = 0; i < 3; ++i) {
				p.push_back(previous_position_[i]);
				v.push_back(previous_velocity_[i]);
			}
			previous[k_position_] = p;
			previous[k_velocity_] = v;
		}
		godot::Dictionary counts;
		for (const auto &row : counts_) counts[row.first] = row.second;
		godot::Array out;
		out.push_back(window);
		out.push_back(window_s_);
		out.push_back(pending);
		out.push_back(previous);
		out.push_back(counts);
		return out;
	}

	// The state restore() left in the detector's own fields. Only canonical value types are accepted (int ticks and
	// counts, float numbers); anything else returns false and the detector keeps its GDScript fields.
	bool restore(const godot::Array &window, double window_s, const godot::Array &pending, const godot::Dictionary &previous,
			const godot::Dictionary &counts) {
		clear();
		counts_.clear();
		for (int64_t i = 0; i < window.size(); ++i) {
			if (window[i].get_type() != godot::Variant::DICTIONARY) return fail();
			const godot::Dictionary e = window[i];
			Entry entry;
			if (!keys_are(e, {&k_tick_, &k_dt_, &k_tas_, &k_groundspeed_}) || !integer(e, k_tick_, entry.tick) || !number(e, k_dt_, entry.dt) || !number(e, k_tas_, entry.tas) ||
					!number(e, k_groundspeed_, entry.gs)) {
				return fail();
			}
			window_.push_back(entry);
		}
		window_s_ = window_s;
		for (int64_t i = 0; i < pending.size(); ++i) {
			if (pending[i].get_type() != godot::Variant::DICTIONARY) return fail();
			const godot::Dictionary e = pending[i];
			Pending entry;
			if (!keys_are(e, {&k_tick_, &k_time_s_, &k_tas_, &k_groundspeed_}) || !integer(e, k_tick_, entry.tick) || !number(e, k_time_s_, entry.time_s) || !number(e, k_tas_, entry.tas) ||
					!number(e, k_groundspeed_, entry.gs)) {
				return fail();
			}
			pending_.push_back(entry);
		}
		if (!previous.is_empty()) {
			if (!keys_are(previous, {&k_tick_, &k_tas_, &k_groundspeed_, &k_position_, &k_velocity_}) ||
					!integer(previous, k_tick_, previous_tick_) || !number(previous, k_tas_, previous_tas_) ||
					!number(previous, k_groundspeed_, previous_gs_) || !floats3(previous, k_position_, previous_position_) ||
					!floats3(previous, k_velocity_, previous_velocity_)) {
				return fail();
			}
			has_previous_ = true;
		}
		const godot::Array keys = counts.keys();
		for (int64_t i = 0; i < keys.size(); ++i) {
			const godot::Variant value = counts[keys[i]];
			if (keys[i].get_type() != godot::Variant::STRING || value.get_type() != godot::Variant::INT) return fail();
			counts_.push_back({godot::String(keys[i]), int64_t(value)});
		}
		return true;
	}

private:
	struct Entry {
		int64_t tick = 0;
		double dt = 0.0, tas = 0.0, gs = 0.0;
	};
	struct Pending {
		int64_t tick = 0;
		double time_s = 0.0, tas = 0.0, gs = 0.0;
	};

	static double absf(double x) { return godot::UtilityFunctions::absf(x); }
	static double maxf(double a, double b) { return godot::UtilityFunctions::maxf(a, b); }

	// _finite_nonnegative_value
	static double finite_nonnegative_value(const godot::Variant &value) {
		const godot::Variant::Type type = value.get_type();
		if (type != godot::Variant::INT && type != godot::Variant::FLOAT) return -1.0;
		const double x = double(value);
		return std::isfinite(x) && x >= 0.0 ? x : -1.0;
	}

	// _vector3: an Array or PackedFloat64Array of three finite ints or floats.
	static bool vector3(const godot::Variant &value, double out[3]) {
		if (value.get_type() == godot::Variant::PACKED_FLOAT64_ARRAY) {
			const godot::PackedFloat64Array a = value;
			if (a.size() != 3) return false;
			for (int i = 0; i < 3; ++i) {
				if (!std::isfinite(a[i])) return false;
				out[i] = a[i];
			}
			return true;
		}
		if (value.get_type() != godot::Variant::ARRAY) return false;
		const godot::Array a = value;
		if (a.size() != 3) return false;
		for (int i = 0; i < 3; ++i) {
			const godot::Variant item = a[i];
			if (item.get_type() != godot::Variant::INT && item.get_type() != godot::Variant::FLOAT) return false;
			const double x = double(item);
			if (!std::isfinite(x)) return false;
			out[i] = x;
		}
		return true;
	}

	bool position_discontinuous(const double position[3], const double velocity[3], double dt, double speed) const {
		double error_sq = 0.0;
		for (int i = 0; i < 3; ++i) {
			const double predicted = 0.5 * (previous_velocity_[i] + velocity[i]) * dt;
			const double actual = position[i] - previous_position_[i];
			const double difference = actual - predicted;
			error_sq += difference * difference;
		}
		const double tolerance = maxf(0.05, 0.1 * maxf(speed, previous_gs_) * dt);
		return std::sqrt(error_sq) > tolerance;
	}

	void trim() {
		while (window_.size() - head_ > 1) {
			const Entry &oldest = window_[head_];
			if (window_s_ - oldest.dt + 1e-12 < window_s_limit_) break;
			window_s_ -= oldest.dt;
			++head_;
		}
		while (static_cast<int64_t>(window_.size() - head_) > max_samples_) {
			window_s_ -= window_[head_].dt;
			++head_;
		}
		if (head_ > 32 && head_ * 2 > window_.size()) {
			window_.erase(window_.begin(), window_.begin() + static_cast<std::ptrdiff_t>(head_));
			head_ = 0;
		}
	}

	static double sorted_median(const godot::PackedFloat64Array &sorted) {
		if (sorted.is_empty()) return -1.0;
		const int64_t middle = sorted.size() / 2;
		if (sorted.size() % 2 == 1) return sorted[middle];
		return 0.5 * (sorted[middle - 1] + sorted[middle]);
	}

	bool sorted_near_median(const godot::PackedFloat64Array &sorted, double median) const {
		if (sorted.is_empty()) return false;
		const double tolerance = maxf(stability_absolute_, stability_fraction_ * median);
		return absf(sorted[0] - median) <= tolerance && absf(sorted[sorted.size() - 1] - median) <= tolerance;
	}

	void add_candidate(int64_t tick, double clock_s, godot::Dictionary &flight) {
		godot::PackedFloat64Array tas_values, ground_values;
		const int64_t count = static_cast<int64_t>(window_.size() - head_);
		tas_values.resize(count);
		ground_values.resize(count);
		for (int64_t i = 0; i < count; ++i) {
			tas_values.set(i, window_[head_ + static_cast<size_t>(i)].tas);
			ground_values.set(i, window_[head_ + static_cast<size_t>(i)].gs);
		}
		tas_values.sort(); // the engine's own sort, as PackedFloat64Array.sort() in GDScript
		ground_values.sort();
		const double median_tas = sorted_median(tas_values);
		const double median_ground = sorted_median(ground_values);
		const bool tas_stable = sorted_near_median(tas_values, median_tas);
		const bool ground_stable = sorted_near_median(ground_values, median_ground);
		if (!tas_stable || !ground_stable) reject(k_unsteady_window_);
		pending_.push_back({tick, clock_s, tas_stable ? median_tas : -1.0, ground_stable ? median_ground : -1.0});
		while (static_cast<int64_t>(pending_.size() - pending_head_) > max_samples_) ++pending_head_;
		commit(clock_s, flight);
	}

	void commit(double clock_s, godot::Dictionary &flight) {
		while (pending_head_ < pending_.size()) {
			const Pending &candidate = pending_[pending_head_];
			if (clock_s - candidate.time_s + 1e-12 < window_s_limit_) break;
			if (!flight.is_empty()) {
				if (candidate.tas >= 0.0) flight[k_max_tas_] = maxf(double(flight[k_max_tas_]), candidate.tas);
				if (candidate.gs >= 0.0) flight[k_max_gs_] = maxf(double(flight[k_max_gs_]), candidate.gs);
			}
			++pending_head_;
		}
		if (pending_head_ > 32 && pending_head_ * 2 > pending_.size()) {
			pending_.erase(pending_.begin(), pending_.begin() + static_cast<std::ptrdiff_t>(pending_head_));
			pending_head_ = 0;
		}
	}

	void reject(const godot::String &reason) {
		for (auto &row : counts_) {
			if (row.first == reason) {
				++row.second;
				return;
			}
		}
		counts_.push_back({reason, 1});
	}

	bool fail() {
		clear();
		counts_.clear();
		return false;
	}

	// The dictionary holds exactly these String keys in this order (the snapshot's own; a JSON round trip sorts them).
	static bool keys_are(const godot::Dictionary &d, std::initializer_list<const godot::String *> expected) {
		const godot::Array keys = d.keys();
		if (keys.size() != static_cast<int64_t>(expected.size())) return false;
		int64_t i = 0;
		for (const godot::String *key : expected) {
			if (keys[i].get_type() != godot::Variant::STRING || godot::String(keys[i]) != *key) return false;
			++i;
		}
		return true;
	}

	static bool integer(const godot::Dictionary &d, const godot::String &key, int64_t &out) {
		const godot::Variant v = d.get(key, godot::Variant());
		if (v.get_type() != godot::Variant::INT) return false;
		out = int64_t(v);
		return true;
	}

	static bool number(const godot::Dictionary &d, const godot::String &key, double &out) {
		const godot::Variant v = d.get(key, godot::Variant());
		if (v.get_type() != godot::Variant::FLOAT) return false;
		out = double(v);
		return true;
	}

	static bool floats3(const godot::Dictionary &d, const godot::String &key, double out[3]) {
		const godot::Variant v = d.get(key, godot::Variant());
		if (v.get_type() != godot::Variant::ARRAY) return false;
		const godot::Array a = v;
		if (a.size() != 3) return false;
		for (int i = 0; i < 3; ++i) {
			if (a[i].get_type() != godot::Variant::FLOAT) return false;
			out[i] = double(a[i]);
		}
		return true;
	}

	bool ready_ = false;
	double exclusion_ = 0.0, cap_ = 0.0, acceleration_ = 0.0, window_s_limit_ = 0.0;
	int64_t max_samples_ = 0;
	double stability_absolute_ = 0.0, stability_fraction_ = 0.0;
	std::vector<Entry> window_;
	size_t head_ = 0;
	double window_s_ = 0.0;
	std::vector<Pending> pending_;
	size_t pending_head_ = 0;
	bool has_previous_ = false;
	int64_t previous_tick_ = 0;
	double previous_tas_ = 0.0, previous_gs_ = 0.0;
	double previous_position_[3] = {0.0, 0.0, 0.0}, previous_velocity_[3] = {0.0, 0.0, 0.0};
	std::vector<std::pair<godot::String, int64_t>> counts_;
	// The GDScript's quoted keys are Strings; one set per window, never function-local statics.
	godot::String k_tick_{"tick"}, k_dt_{"dt"}, k_tas_{"tas"}, k_groundspeed_{"groundspeed"}, k_time_s_{"time_s"},
		k_position_{"position"}, k_velocity_{"velocity"}, k_velocity_ned_{"velocity_ned"},
		k_max_tas_{"max_tas_mps"}, k_max_gs_{"max_groundspeed_mps"}, k_invalid_sample_{"invalid_sample"},
		k_speed_cap_{"speed_cap"}, k_acceleration_{"acceleration"}, k_position_discontinuity_{"position_discontinuity"},
		k_unsteady_window_{"unsteady_window"};
};

} // namespace stats
} // namespace nk
