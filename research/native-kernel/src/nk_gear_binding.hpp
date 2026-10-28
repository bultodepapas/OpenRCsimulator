// Component-only Godot adapter for prepared retractable gear. Actual stage
// evaluation reads RetractableModel/PreparedGear directly without Godot calls.
#pragma once

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

#include "nk_retractable.hpp"
#include "nk_weather_binding.hpp"

namespace nk {

class GearBinding {
	bool ready_ = false;
	GroundContext ground_;
	RetractableModel model_;
	std::vector<R> max_compression_;

public:
	bool ready() const { return ready_; }
	const RetractableModel &model() const { return model_; }

	godot::Dictionary prepare_retractable(const godot::Dictionary &gear, const GroundContext &ground) {
		ready_ = false;
		WeatherSnapshotDecoder dec;
		RetractableModel candidate;
		std::vector<R> maximum;
		if (!decode(dec, gear, ground, candidate, maximum)) return failure(dec.error);
		ground_ = ground;
		model_ = std::move(candidate);
		max_compression_ = std::move(maximum);
		ready_ = true;
		godot::Dictionary out;
		out["ok"] = true; out["error"] = "";
		return out;
	}

	// part 0: each contact's XYZ, stiffness, damping, maximum compression,
	// maximum steer, anchor stiffness/damping; part 1: drag; part 2: actuator.
	godot::PackedFloat64Array gear_component(int64_t part, const godot::PackedFloat64Array &body,
			const godot::PackedFloat64Array &air, double extension, double density,
			const godot::PackedFloat64Array &ambient_delta, double target, double dt) const {
		godot::PackedFloat64Array out;
		if (!ready_) return out;
		std::vector<R> result;
		if (part == 0) {
			PreparedGear pose;
			if (!retractable_pose(ground_.gear, model_, extension, pose)) return out;
			const bool down = !model_.enabled || extension == 1.0;
			for (std::size_t i = 0; i < pose.contacts.size(); ++i) {
				const WheelContact &c = pose.contacts[i];
				for (int axis = 0; axis < 3; ++axis) result.push_back(c.position[axis]);
				result.insert(result.end(), {c.stiffness, c.damping, down ? max_compression_[i] : R(0.0),
					c.max_steering, c.anchor_stiffness, c.anchor_damping});
			}
		} else if (part == 1 && body.size() == 13 && air.size() == 3) {
			R state[13], velocity[3];
			for (int i = 0; i < 13; ++i) state[i] = body[i];
			for (int i = 0; i < 3; ++i) velocity[i] = air[i];
			std::vector<R> delta;
			for (int64_t i = 0; i < ambient_delta.size(); ++i) delta.push_back(ambient_delta[i]);
			result = retractable_drag(state, velocity, model_, extension, density,
				delta.empty() ? nullptr : delta.data(), static_cast<int>(delta.size()));
		} else if (part == 2) {
			result = {retractable_advance(extension, target, dt, model_)};
		}
		out.resize(static_cast<int64_t>(result.size()));
		for (std::size_t i = 0; i < result.size(); ++i) out[static_cast<int64_t>(i)] = result[i].v;
		return out;
	}

	godot::Dictionary gear_wheels_component(const godot::PackedFloat64Array &body, double extension, double steer,
			const godot::PackedFloat64Array &anchors, const godot::PackedFloat64Array &speeds, double brake) const {
		if (!ready_ || body.size() != 13) return failure("invalid gear wheel arguments");
		GroundContext stage = ground_;
		if (!retractable_pose(ground_.gear, model_, extension, stage.gear)) return failure("invalid gear extension");
		R state[13];
		for (int i = 0; i < 13; ++i) state[i] = body[i];
		std::vector<R> loads, rates;
		const bool ok = wheels_evaluate(state, stage, steer, anchors.ptr(), static_cast<int>(anchors.size()), speeds.ptr(),
			static_cast<int>(speeds.size()), brake, loads, rates);
		godot::PackedFloat64Array packed_loads, packed_rates;
		packed_loads.resize(static_cast<int64_t>(loads.size()));
		packed_rates.resize(static_cast<int64_t>(rates.size()));
		for (std::size_t i = 0; i < loads.size(); ++i) packed_loads[static_cast<int64_t>(i)] = loads[i].v;
		for (std::size_t i = 0; i < rates.size(); ++i) packed_rates[static_cast<int64_t>(i)] = rates[i].v;
		godot::Dictionary out;
		out["ok"] = ok;
		out["loads"] = packed_loads;
		out["derivative"] = packed_rates;
		return out;
	}

private:
	static godot::Dictionary failure(const std::string &message) {
		godot::Dictionary out;
		out["ok"] = false; out["error"] = godot::String(message.c_str());
		return out;
	}

	static bool decode(WeatherSnapshotDecoder &dec, const godot::Dictionary &gear, const GroundContext &ground,
			RetractableModel &m, std::vector<R> &maximum) {
		if (!dec.keys(gear, "landing gear", {"contacts", "reach", "heave_omega", "static_sag", "rolling_resistance",
			"side_friction", "tan_peak_slip", "substeps", "breakaway_factor", "rolling_reference_radius",
			"rolling_reference_radius_provenance", "retraction"}) || ground.gear.empty || !ground.surfaces.valid || !ground.lake_valid) {
			return dec.fail("invalid prepared landing gear");
		}
		godot::Dictionary retraction;
		if (!dec.dictionary(gear, "retraction", retraction) || retraction.is_empty() || retraction.size() != 4 ||
			!dec.keys(retraction, "retraction", {"extension_time", "retraction_time", "drag_area", "drag_center"}) ||
			!dec.number(retraction, "extension_time", m.extension_time) || !dec.number(retraction, "retraction_time", m.retraction_time) ||
			!dec.number(retraction, "drag_area", m.drag_area)) return dec.fail("invalid gear retraction parameters");
		std::vector<R> center;
		if (!dec.packed(retraction, "drag_center", center, 3)) return false;
		for (int i = 0; i < 3; ++i) m.drag_center[i] = center[i];
		if (m.extension_time < 0.25 || m.extension_time > 30.0 || m.retraction_time < 0.25 || m.retraction_time > 30.0 ||
			m.drag_area < 0.0 || m.drag_area > 1.0) return dec.fail("gear retraction parameters out of range");
		if (!gear.has("contacts") || gear["contacts"].get_type() != godot::Variant::ARRAY) return dec.fail("missing gear contacts");
		const godot::Array contacts = gear["contacts"];
		if (contacts.size() != static_cast<int64_t>(ground.gear.contacts.size()) || contacts.is_empty()) return dec.fail("gear contact count mismatch");
		int64_t path_size = -1;
		for (int64_t i = 0; i < contacts.size(); ++i) {
			if (contacts[i].get_type() != godot::Variant::DICTIONARY) return dec.fail("gear contact must be a dictionary");
			const godot::Dictionary c = contacts[i];
			if (!dec.keys(c, "gear contact", {"name", "position", "stiffness", "damping", "max_compression", "max_steering",
				"damping_onset", "anchor_stiffness", "anchor_damping", "id", "wheel_radius", "wheel_inertia", "spin_relaxation",
				"brake_torque", "brake_availability", "wheel_provenance", "retraction_path"})) return false;
			std::vector<R> position;
			R stiffness, damping, compression, steer, anchor_k, anchor_c;
			if (!dec.packed(c, "position", position, 3) || !dec.number(c, "stiffness", stiffness) || !dec.number(c, "damping", damping) ||
				!dec.number(c, "max_compression", compression) || !dec.number(c, "max_steering", steer) ||
				!dec.number(c, "anchor_stiffness", anchor_k) || !dec.number(c, "anchor_damping", anchor_c)) return false;
			const WheelContact &base = ground.gear.contacts[static_cast<std::size_t>(i)];
			if (position[0] != base.position[0] || position[1] != base.position[1] || position[2] != base.position[2] ||
				stiffness != base.stiffness || damping != base.damping || steer != base.max_steering ||
				anchor_k != base.anchor_stiffness || anchor_c != base.anchor_damping || compression < 0.0) return dec.fail("prepared wheel disagrees with source gear");
			if (!c.has("retraction_path") || c["retraction_path"].get_type() != godot::Variant::PACKED_FLOAT64_ARRAY) return dec.fail("missing gear path");
			const godot::PackedFloat64Array raw = c["retraction_path"];
			if (raw.size() < 6 || raw.size() > 1539 || raw.size() % 3 != 0 || (path_size >= 0 && raw.size() != path_size)) {
				return dec.fail("invalid gear path dimensions");
			}
			path_size = raw.size();
			std::vector<R> path;
			path.reserve(static_cast<std::size_t>(raw.size()));
			for (int64_t j = 0; j < raw.size(); ++j) {
				if (!std::isfinite(raw[j])) return dec.fail("nonfinite gear path");
				path.push_back(raw[j]);
			}
			m.paths.push_back(std::move(path));
			maximum.push_back(compression);
		}
		m.enabled = true;
		return true;
	}
};

} // namespace nk
