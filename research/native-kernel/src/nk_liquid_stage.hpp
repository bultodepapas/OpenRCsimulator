// Godot-independent finite-liquid joint-stage composition. It splits the
// stage-local inventory sample from the response so the shared C++ airframe and
// ground evaluators can use the live mass before producing the datum wrench.
// The session continues to own exhaustion/stop events and endpoint policies.
#pragma once

#include <array>
#include <vector>

#include "nk_liquid_mass.hpp"
#include "nk_liquid_propulsion.hpp"

namespace nk {

struct LiquidStageModel {
	bool ready = false;
	bool gas = false;
	LiquidMassModel mass;
	LiquidGasShaft gas_shaft;
	LiquidGasConsumption gas_fuel;
	LiquidTurbine turbine;
	R capacity_kg = 0.0;
	R unusable_kg = 0.0;
	int bound_index = 0;
};

struct LiquidStageLayout {
	int rotor_index = 0; // leading wash states; turbine always has zero
	int wheel_index = 0; // rotor index + one continuous shaft RPM
	int wheel_count = 0;
};

struct LiquidStageTrial {
	bool ok = false;
	LiquidMassProperties mass;
	R rpm = 0.0;
	R onboard_kg = 0.0;
	R inventory_usable_kg = 0.0;
	bool running = false;
};

struct LiquidStageResult {
	bool ok = false;
	std::array<R, 6> loads{}; // complete external+reaction wrench at the live CG
	std::vector<R> derivative; // wash, rpm, wheels, usable fuel, source latch
	std::array<R, 3> rotor{};
	std::array<R, 13> body_derivative{};
	bool has_pre_reaction = false;
	std::array<R, 6> pre_reaction{}; // live-CG gas wrench for an optional stage context
};

// Equivalent to LiquidFlight.valid(..., true) and properties(..., true).
// A negative fuel trial is allowed for event localization, but all entries
// (including wheel, wash, and latch slots) must remain finite and the source
// latch must be exactly 0 or 1. Mass preserves residue-rounding twice.
inline LiquidStageTrial liquid_trial_properties(const LiquidStageModel &model, const LiquidStageLayout &layout,
		const R *values, int count, bool power_enabled) {
	LiquidStageTrial out;
	if (!model.ready || values == nullptr || layout.rotor_index < 0 || layout.wheel_count < 0 ||
			layout.wheel_index != layout.rotor_index + 1 || (!model.gas && layout.rotor_index != 0) ||
			layout.wheel_index > count || layout.wheel_count > count - layout.wheel_index ||
			layout.wheel_index + layout.wheel_count != count - 2 || model.mass.resources.empty() ||
			model.mass.resources.size() > static_cast<size_t>(std::numeric_limits<int>::max()) ||
			model.bound_index < 0 || static_cast<size_t>(model.bound_index) >= model.mass.resources.size()) return out;
	for (int i = 0; i < count; ++i) if (!is_finite(values[i])) return out;
	const int liquid_index = layout.wheel_index + layout.wheel_count;
	const R usable = values[liquid_index];
	const R latch = values[liquid_index + 1];
	if ((latch.v != 0.0 && latch.v != 1.0) || usable.v > (model.capacity_kg - model.unusable_kg).v) return out;
	const R rpm = values[layout.rotor_index];
	if (rpm.v < 0.0 || (!model.gas && rpm.v > model.turbine.max_rpm.v)) return out;
	const R onboard = liquid_trial_onboard_mass(usable, model.unusable_kg, model.capacity_kg);
	const R inventory_usable = liquid_inventory_usable_mass(onboard, model.unusable_kg, model.capacity_kg);
	const size_t resource_count = model.mass.resources.size();
	std::array<R, 16> local{};
	static thread_local std::vector<R> overflow;
	R *amounts = local.data();
	if (resource_count > local.size()) {
		overflow.resize(resource_count);
		amounts = overflow.data();
	}
	for (size_t i = 0; i < resource_count; ++i) amounts[i] = model.mass.resources[i].reference_kg;
	amounts[static_cast<size_t>(model.bound_index)] = inventory_usable;
	const auto properties = liquid_mass_evaluate(model.mass, amounts, static_cast<int>(resource_count));
	if (!properties.ok) return out;
	out.ok = true;
	out.mass = properties;
	out.rpm = rpm;
	out.onboard_kg = onboard;
	out.inventory_usable_kg = inventory_usable;
	out.running = latch.v == 1.0 && power_enabled;
	return out;
}

// `external` contains the complete same-stage aero/propulsion/ground wrench
// about the fixed datum O, and must include the turbine point's propulsion
// loads when the source is a turbine. The caller computes gas wash and wheel
// rates with the very same trial and air, and passes empty wash for turbines.
// For a turbine, pass the point produced before evaluating its airframe loads
// by liquid_turbine_stage(inlet_air, trial.rpm, throttle, model.turbine, rho,
// trial.running). For gas pass a null turbine_point. Input pointers are borrowed.
inline LiquidStageResult liquid_stage_finish(const LiquidStageModel &model, const LiquidStageLayout &layout,
		const LiquidStageTrial &trial, const R *body, const R *external, const R *prop_air,
		const R *datum_air, bool explicit_air, const PropModel &prop, R throttle, R rho, R charge_ratio, R gravity,
		const R *wash_rates, int wash_count, const R *wheel_rates, int wheel_count,
		const LiquidTurbineStage *turbine_point, bool capture_pre_reaction = false) {
	LiquidStageResult out;
	if (!model.ready || !trial.ok || body == nullptr || external == nullptr || wheel_count != layout.wheel_count ||
			wash_count != layout.rotor_index || wheel_count < 0 || wash_count < 0 ||
			(wheel_count > 0 && wheel_rates == nullptr) || (wash_count > 0 && wash_rates == nullptr)) return out;
	const auto &cg = trial.mass.cg;
	const R shift[3] = {cg[1] * external[2] - cg[2] * external[1],
			cg[2] * external[0] - cg[0] * external[2], cg[0] * external[1] - cg[1] * external[0]};
	R cg_loads[6] = {external[0], external[1], external[2], external[3] - shift[0],
			external[4] - shift[1], external[5] - shift[2]};
	R rpm_rate, fuel_rate;
	if (model.gas) {
		if (prop_air == nullptr || datum_air == nullptr) return out;
		const LiquidGasStage source = liquid_gas_coupled_stage(body, cg_loads, prop_air, datum_air, explicit_air,
				trial.rpm, throttle, rho, charge_ratio, trial.running, model.gas_shaft, prop, model.gas_fuel,
				trial.mass.inertia.data(), trial.mass.inverse.data());
		if (!source.ok) return out;
		out.loads = source.loads;
		out.rotor = source.rotor;
		rpm_rate = source.rpm_rate;
		fuel_rate = source.fuel_rate;
		if (capture_pre_reaction) {
			out.has_pre_reaction = true;
			for (int i = 0; i < 6; ++i) out.pre_reaction[i] = cg_loads[i];
		}
	} else {
		if (turbine_point == nullptr || !turbine_point->ok || wash_count != 0) return out;
		for (int i = 0; i < 6; ++i) out.loads[i] = cg_loads[i];
		out.rotor = turbine_point->rotor;
		rpm_rate = turbine_point->rpm_rate;
		fuel_rate = turbine_point->fuel_rate;
	}
	if (!is_finite(fuel_rate) || fuel_rate.v < 0.0) return LiquidStageResult{};
	out.derivative.reserve(static_cast<size_t>(wash_count + wheel_count + 3));
	for (int i = 0; i < wash_count; ++i) out.derivative.push_back(wash_rates[i]);
	out.derivative.push_back(rpm_rate);
	for (int i = 0; i < wheel_count; ++i) out.derivative.push_back(wheel_rates[i]);
	out.derivative.push_back(-fuel_rate);
	out.derivative.push_back(0.0);
	out.body_derivative = liquid_fixed_datum_derivative(body, trial.mass, out.loads.data(), out.loads.data() + 3,
			gravity, out.rotor.data());
	out.ok = true;
	return out;
}

} // namespace nk
