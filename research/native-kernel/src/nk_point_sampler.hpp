// Native lifetime owner for a detached spatial-stage preview. Queries stay in
// C++; a retained preview never borrows an RK stack frame or mutable session.
#pragma once

#include <memory>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include "nk_wake_spatial_flow.hpp"
#include "nk_spatial_weather.hpp"

class OpenRCNativePointSampler : public godot::RefCounted {
	GDCLASS(OpenRCNativePointSampler, godot::RefCounted)
	std::shared_ptr<const nk::SpatialWeather> weather_;
	nk::SpatialPointContext point_;

	static bool wind(void *context, const nk::R *position, nk::R at, nk::R *out) {
		const auto &self = *static_cast<OpenRCNativePointSampler *>(context);
		if (!self.weather_) return false;
		const auto sampled = nk::spatial_weather_wind(*self.weather_, position, at);
		for (int i = 0; i < 3; ++i) out[i] = sampled[i];
		return nk::spatial_flow_finite3(out);
	}

protected:
	static void _bind_methods() {
		godot::ClassDB::bind_method(godot::D_METHOD("delta_at", "arm"), &OpenRCNativePointSampler::delta_at);
	}

public:
	void prepare(std::shared_ptr<const nk::SpatialWeather> weather, const nk::SpatialPointContext &point) {
		weather_ = std::move(weather);
		point_ = point;
		point_.provider = {wind, this};
	}
	godot::PackedFloat64Array delta_at(const godot::PackedFloat64Array &arm) {
		nk::R delta[3] = {nk::kNan, nk::kNan, nk::kNan};
		if (arm.size() == 3) {
			const nk::R position[3] = {arm[0], arm[1], arm[2]};
			if (!nk::spatial_point_delta(&point_, position, delta))
				for (auto &value : delta) value = nk::kNan;
		}
		godot::PackedFloat64Array out;
		out.resize(3);
		for (int i = 0; i < 3; ++i) out[i] = delta[i].v;
		return out;
	}
};
