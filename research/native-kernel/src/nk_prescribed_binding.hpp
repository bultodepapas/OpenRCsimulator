// Decode the complete prescribed-fuel source only at the preparation boundary.
// The source is bit-bound to the validated session model; repeated RK stages
// use the Godot-independent PrescribedModel in nk_prescribed_stage.hpp.
#pragma once

#include "nk_electric_binding.hpp"
#include "nk_prescribed_stage.hpp"
#include "nk_stage_snapshot.hpp"

namespace nk {

class PrescribedBinding {
	PrescribedModel model_;

	static godot::Dictionary failure(const std::string &reason) {
		godot::Dictionary out;
		out["ok"] = false;
		out["error"] = godot::String(reason.c_str());
		return out;
	}

	static bool table(const std::vector<double> &values, bool positive_y) {
		if (!liquid_table_valid(values)) return false;
		for (size_t i = 1; i < values.size(); i += 2) {
			if (positive_y ? values[i] <= 0.0 : values[i] < 0.0) return false;
		}
		return true;
	}

public:
	const PrescribedModel &model() const { return model_; }

	godot::Dictionary prepare_prescribed(const godot::Dictionary &snapshot, const godot::Dictionary &model) {
		model_ = PrescribedModel();
		ElectricSnapshotDecoder dec;
		godot::String format, kind;
		godot::Dictionary source, actual;
		if (!dec.keys(snapshot, "prescribed", {"format", "kind", "source"}) ||
				!dec.string(snapshot, "format", format) || !dec.string(snapshot, "kind", kind) ||
				!dec.dictionary(snapshot, "source", source) || !dec.dictionary(model, "propulsion", actual)) return failure(dec.error);
		if (format != godot::String("openrc-nk3-prescribed-snapshot-v1") || !stage_snapshot_exact(source, actual)) {
			return failure("prescribed source differs from the committed model");
		}
		if (source.has("liquid_fuel") || source.has("glow") || source.has("motor")) return failure("source is not prescribed fuel");
		PrescribedModel next;
		if (kind == godot::String("shaft-split") || kind == godot::String("shaft-coupled")) {
			if ((source.has("kind") && source["kind"] != godot::String("glow_prop")) || !source.has("shaft")) {
				return failure("prescribed shaft source family mismatch");
			}
			if (!dec.keys(source, "prescribed shaft source", {"kind", "id", "max_rpm", "idle_rpm", "lag", "diameter", "offset",
					"ct", "cp", "rotor_inertia", "shaft", "cp_min", "axis", "normal_force", "pfactor_moment", "slipstream"})) return failure(dec.error);
			godot::Dictionary shaft;
			std::vector<double> friction;
			if (!dec.dictionary(source, "shaft", shaft) || !dec.keys(shaft, "prescribed shaft", {"power_curve", "friction", "idle_power", "peak_indicated_power"}) ||
					!dec.packed(shaft, "power_curve", next.shaft.power_curve) ||
					!dec.packed(shaft, "friction", friction) || !dec.number(shaft, "idle_power", next.shaft.idle_power) ||
					!dec.number(shaft, "peak_indicated_power", next.shaft.peak_indicated_power)) return failure(dec.error);
			if (!table(next.shaft.power_curve, false) || next.shaft.power_curve.front() <= 0.0 || friction.size() != 2 ||
					friction[0] < 0.0 || friction[1] < 0.0 || next.shaft.idle_power.v < 0.0 ||
					next.shaft.peak_indicated_power.v <= next.shaft.idle_power.v) return failure("invalid prescribed shaft");
			next.shaft.friction = {R(friction[0]), R(friction[1])};
			next.kind = kind == godot::String("shaft-coupled") ? PrescribedKind::ShaftCoupled : PrescribedKind::ShaftSplit;
		} else if (kind == godot::String("turbine-sampled") || kind == godot::String("turbine-continuous")) {
			if (!source.has("kind") || source["kind"] != godot::String("turbine")) return failure("prescribed turbine source family mismatch");
			if (!dec.keys(source, "prescribed turbine source", {"kind", "id", "idle_rpm", "max_rpm", "static_thrust", "mass_flow",
					"fuel_flow", "throttle_map", "accel_limit", "decel_limit", "installed_factor", "governor_tau", "rotor_inertia",
					"rotor_sense", "offset", "intake_offset", "axis", "spool_integrator", "ram_flow", "ram_jet"})) return failure(dec.error);
			const bool continuous = kind == godot::String("turbine-continuous");
			if ((source.has("spool_integrator") && source["spool_integrator"] != godot::String(continuous ? "rk4" : "sampled")) ||
					(!source.has("spool_integrator") && continuous)) return failure("prescribed turbine integrator mismatch");
			std::vector<double> axis, offset, intake;
			auto &t = next.turbine;
			if (!dec.number(source, "max_rpm", t.max_rpm) || !dec.packed(source, "axis", axis) ||
					!dec.packed(source, "offset", offset) || !dec.packed(source, "intake_offset", intake) ||
					!dec.packed(source, "throttle_map", t.throttle_map) || !dec.packed(source, "accel_limit", t.accel_limit) ||
					!dec.packed(source, "decel_limit", t.decel_limit) || !dec.packed(source, "static_thrust", t.static_thrust) ||
					!dec.packed(source, "mass_flow", t.mass_flow) || !dec.packed(source, "fuel_flow", t.fuel_flow) ||
					!dec.number(source, "governor_tau", t.governor_tau) || !dec.number(source, "installed_factor", t.installed_factor) ||
					!dec.number(source, "rotor_inertia", t.rotor_inertia) || !dec.number(source, "rotor_sense", t.rotor_sense)) return failure(dec.error);
			if (source.has("ram_flow") && !dec.number(source, "ram_flow", t.ram_flow)) return failure(dec.error);
			if (source.has("ram_jet") && !dec.packed(source, "ram_jet", t.ram_jet)) return failure(dec.error);
			if (axis.size() != 3 || offset.size() != 3 || intake.size() != 3 || t.max_rpm.v <= 0.0 || t.governor_tau.v <= 0.0 ||
					t.installed_factor.v <= 0.0 || t.rotor_inertia.v < 0.0 || std::fabs(t.rotor_sense.v) != 1.0 || t.ram_flow.v < 0.0 ||
					!table(t.throttle_map, false) || !table(t.accel_limit, true) || !table(t.decel_limit, true) ||
					!table(t.static_thrust, false) || !table(t.mass_flow, true) || !table(t.fuel_flow, false) ||
					(source.has("ram_jet") && !table(t.ram_jet, false))) return failure("invalid prescribed turbine");
			for (int i = 0; i < 3; ++i) { t.axis[i] = axis[i]; t.offset[i] = offset[i]; t.intake_offset[i] = intake[i]; }
			next.kind = continuous ? PrescribedKind::TurbineContinuous : PrescribedKind::TurbineSampled;
		} else return failure("unsupported prescribed source mode");
		model_ = std::move(next);
		godot::Dictionary out;
		out["ok"] = true;
		out["error"] = "";
		return out;
	}
};

} // namespace nk
