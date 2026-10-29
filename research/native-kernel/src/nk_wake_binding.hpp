// Prepare-time adapter and component-only bridge for the unqualified NK-3
// slipstream draft. The caller supplies independently prepared aero/prop models;
// no dictionary, scene object or Godot call is used inside wake_loads itself.
#pragma once

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <array>
#include <vector>

#include "nk_wake.hpp"
#include "nk_weather_binding.hpp" // strict snapshot decoder utilities

namespace nk {

class WakeBinding {
	bool ready_ = false;
	AeroModel aero_;
	PropModel prop_;
	WakeModel wake_;

public:
	bool ready() const { return ready_; }
	const WakeModel &model() const { return wake_; }

	// Input is the exact normalized model.propulsion.slipstream dictionary;
	// an empty dictionary denotes no slipstream. Prepared aero/prop values are
	// copied to keep this component independent of later prepare calls.
	godot::Dictionary prepare_wake(const godot::Dictionary &ss, const AeroModel &aero, const PropModel &prop) {
		ready_ = false;
		WeatherSnapshotDecoder dec;
		WakeModel candidate;
		if (!ss.is_empty() && !decode(dec, ss, aero, prop, candidate)) return failure(dec.error);
		aero_ = aero;
		prop_ = prop;
		wake_ = std::move(candidate);
		ready_ = true;
		godot::Dictionary out;
		out["ok"] = true;
		out["error"] = "";
		return out;
	}

	// Part 0: stage loads. 1: wake [u,w,vs,dv,rs,swirl,core]. 2: wash
	// transport [target,speed]. 3: transport derivative. 4: reverse weight.
	// tq is supplied as [thrust,torque] so the component oracle can independently
	// compare glow-powered wake and the WashTransport surrogate closure.
	godot::PackedFloat64Array wake_component(int64_t part, const godot::PackedFloat64Array &body,
			const godot::PackedFloat64Array &wind, double rho, const godot::PackedFloat64Array &deflections,
			double rpm, const godot::PackedFloat64Array &tq, double downwash,
			const godot::PackedFloat64Array &lagged, const godot::PackedFloat64Array &source_delta) const {
		godot::PackedFloat64Array out;
		if (!ready_ || body.size() != 13 || wind.size() != 3 || (deflections.size() != 4 && deflections.size() != 5) ||
			tq.size() != 2 || (source_delta.size() != 0 && source_delta.size() != 3) ||
			(lagged.size() != 0 && lagged.size() != static_cast<int64_t>(wake_.pieces.size()))) return out;
		R state[13], ned[3], delta[3];
		for (int i = 0; i < 13; ++i) state[i] = body[i];
		for (int i = 0; i < 3; ++i) {
			ned[i] = wind[i];
			delta[i] = source_delta.is_empty() ? R(0.0) : R(source_delta[i]);
		}
		Deflections d;
		d.elevator = deflections[0]; d.aileron_right = deflections[1];
		d.aileron_left = deflections[2]; d.rudder = deflections[3];
		if (deflections.size() == 5) d.flap = deflections[4];
		const Air air = air_compute(state, ned, rho);
		R source[3] = {air.v[0], air.v[1], air.v[2]};
		for (int i = 0; i < 3; ++i) if (!source_delta.is_empty() && delta[i] != 0.0) source[i] += delta[i];
		std::vector<R> values;
		values.reserve(static_cast<std::size_t>(lagged.size()));
		for (int64_t i = 0; i < lagged.size(); ++i) values.push_back(lagged[i]);
		std::vector<R> result;
		if (part == 0) {
			const Loads loads = wake_loads(state, air, d, aero_, prop_, wake_, rpm, rho, tq[0], tq[1], downwash,
				values.empty() ? nullptr : values.data(), source_delta.is_empty() ? nullptr : delta);
			result.assign(loads.begin(), loads.end());
		} else if (part == 1 && wake_.enabled) {
			const WakeState w = wake_state(source, tq[0], tq[1], prop_, wake_, rho);
			result = {w.u, w.w, w.vs, w.dv, w.rs, w.swirl, w.core};
		} else if ((part == 2 || part == 3) && wake_.enabled && wake_.transport) {
			const auto target = wake_transport_target(source, rpm, tq[0], tq[1], prop_, wake_, rho);
			if (part == 2) result.assign(target.begin(), target.end());
			else if (values.size() == wake_.pieces.size()) {
				result.resize(values.size());
				wake_transport_derivative(target, values.data(), wake_, result.data());
			}
		} else if (part == 4 && wake_.enabled && wake_.smooth) {
			result = {wake_reverse_weight(source, rpm, prop_, wake_)};
		}
		out.resize(static_cast<int64_t>(result.size()));
		for (std::size_t i = 0; i < result.size(); ++i) out[static_cast<int64_t>(i)] = result[i].v;
		return out;
	}

private:
	static godot::Dictionary failure(const std::string &message) {
		godot::Dictionary out;
		out["ok"] = false;
		out["error"] = godot::String(message.c_str());
		return out;
	}

	static bool decode(WeatherSnapshotDecoder &dec, const godot::Dictionary &ss, const AeroModel &aero,
			const PropModel &prop, WakeModel &out) {
		if (!dec.keys(ss, "slipstream", {"hub", "wash_factor", "swirl_factor", "vertical_drift", "pieces",
			"edge_fraction", "reverse_fade", "transport_speed_floor", "propeller_sidewash"})) return false;
		std::vector<R> hub, factors, fade;
		if (!dec.packed(ss, "hub", hub, 3) || !dec.packed(ss, "wash_factor", factors, 2) ||
			!dec.number(ss, "swirl_factor", out.swirl_factor) || !dec.number(ss, "vertical_drift", out.vertical_drift)) return false;
		if (!aero.horizontal.present || !aero.vertical.present || !is_finite(prop.diameter) || prop.diameter <= 0.0 || prop.ct.size() < 4) {
			return dec.fail("wake requires prepared horizontal and vertical tails and a valid propeller");
		}
		for (double value : prop.ct) if (!std::isfinite(value)) return dec.fail("nonfinite propeller thrust table");
		for (double value : prop.normal_force) if (!std::isfinite(value)) return dec.fail("nonfinite normal-force table");
		if ((!prop.normal_force.empty() && (prop.normal_force.size() < 4 || prop.normal_force.size() % 2 != 0)) ||
			prop.ct.size() % 2 != 0) return dec.fail("invalid propeller table shape");
		const auto axis = wake_axis(prop);
		if (!is_finite(axis[0]) || !is_finite(axis[1]) || !is_finite(axis[2]) || axis[0] == 0.0) return dec.fail("invalid propeller axis");
		for (int i = 0; i < 3; ++i) out.hub[i] = hub[i];
		out.wash_factor[0] = factors[0]; out.wash_factor[1] = factors[1];
		if (out.swirl_factor < 0.0 || out.swirl_factor > 1.0 || out.vertical_drift < 0.0 || out.vertical_drift > 1.0 ||
			factors[0] < 0.0 || factors[0] > 2.0 || factors[1] < 0.0 || factors[1] > 2.0) return dec.fail("wake factor out of range");
		out.smooth = ss.has("edge_fraction");
		out.transport = ss.has("transport_speed_floor");
		out.segmented = ss.has("propeller_sidewash");
		if (out.smooth) {
			if (!dec.number(ss, "edge_fraction", out.edge_fraction) || !dec.packed(ss, "reverse_fade", fade, 2)) return false;
			out.reverse_fade[0] = fade[0]; out.reverse_fade[1] = fade[1];
			if (out.edge_fraction < 0.01 || out.edge_fraction > 0.5 || fade[0] < 0.01 || fade[1] > 0.5 || fade[0] >= fade[1] ||
				axis[0] != 1.0 || axis[1] != 0.0 || axis[2] != 0.0 || prop.ct[1] <= 0.0) return dec.fail("invalid smooth wake geometry or fade");
		} else if (ss.has("reverse_fade")) return dec.fail("reverse fade requires smooth wake");
		if (out.transport && (!out.smooth || out.swirl_factor != 0.0 ||
			!dec.number(ss, "transport_speed_floor", out.transport_speed_floor) || out.transport_speed_floor < 0.1 || out.transport_speed_floor > 5.0)) {
			return dec.fail("invalid wake transport law");
		}
		if (out.segmented && (out.smooth || out.transport || !dec.number(ss, "propeller_sidewash", out.sidewash_gain) ||
			out.sidewash_gain < 0.0 || out.sidewash_gain > 1.0)) return dec.fail("invalid segmented sidewash law");
		if (!ss.has("pieces") || ss["pieces"].get_type() != godot::Variant::ARRAY) return dec.fail("missing or non-array wake pieces");
		const godot::Array pieces = ss["pieces"];
		if (out.smooth && (pieces.is_empty() || pieces.size() > 8)) return dec.fail("invalid wake piece count");
		for (int64_t i = 0; i < pieces.size(); ++i) {
			if (pieces[i].get_type() != godot::Variant::DICTIONARY) return dec.fail("wake piece is not a dictionary");
			const godot::Dictionary piece = pieces[i];
			if (!dec.keys(piece, "wake piece", {"surface", "area", "root", "span_dir", "span", "chords", "profile"})) return false;
			godot::String surface;
			std::vector<R> root, direction, chords;
			WakePiece prepared;
			if (!dec.string(piece, "surface", surface) || !dec.number(piece, "area", prepared.area) ||
				!dec.number(piece, "span", prepared.span) || !dec.packed(piece, "root", root, 3) ||
				!dec.packed(piece, "span_dir", direction, 3)) return false;
			if (surface != godot::String("horizontal") && surface != godot::String("vertical")) return dec.fail("unsupported wake surface");
			prepared.vertical = surface == godot::String("vertical");
			for (int j = 0; j < 3; ++j) { prepared.root[j] = root[j]; prepared.span_dir[j] = direction[j]; }
			const R direction_norm = sqrt_(direction[0] * direction[0] + direction[1] * direction[1] + direction[2] * direction[2]);
			// AircraftData has already validated these dimensional quantities. A
			// Workshop virtual-size model may scale their source bounds; here retain
			// the law's positive/finite requirements without imposing unscaled bounds.
			if (prepared.area <= 0.0 || prepared.span <= 0.0 ||
				absf(direction_norm - 1.0) > 1e-6) return dec.fail("invalid wake piece geometry");
			if (out.smooth) {
				if (piece.has("chords") || !dec.packed(piece, "profile", prepared.profile) || prepared.profile.empty() ||
					prepared.profile.size() > 64 * 4 || prepared.profile.size() % 4 != 0 || prepared.span_dir[0] != 0.0 ||
					(prepared.vertical ? prepared.span_dir[1] != 0.0 : prepared.span_dir[2] != 0.0) || prepared.root[0] <= out.hub[0]) {
					return dec.fail("invalid smooth wake piece");
				}
				R previous = 0.0, area = 0.0;
				for (std::size_t j = 0; j < prepared.profile.size(); j += 4) {
					const R start = prepared.profile[j], end = prepared.profile[j + 1];
					const R c0 = prepared.profile[j + 2], c1 = prepared.profile[j + 3];
					if (start < previous || end <= start || end > prepared.span + 1e-10 || c0 < 0.0 || c1 < 0.0 || c0 + c1 <= 0.0) return dec.fail("invalid wake profile interval");
					area += 0.5 * (c0 + c1) * (end - start);
					previous = end;
				}
				if (absf(area - prepared.area) > 1e-8) return dec.fail("wake profile area mismatch");
			} else {
				if (piece.has("profile") || !dec.packed(piece, "chords", chords, 2)) return dec.fail("legacy wake needs chords");
				if (chords[0] <= 0.0 || chords[1] <= 0.0) return dec.fail("invalid wake chords");
				prepared.chords[0] = chords[0]; prepared.chords[1] = chords[1];
			}
			out.pieces.push_back(std::move(prepared));
		}
		out.enabled = true;
		return true;
	}
};

} // namespace nk
