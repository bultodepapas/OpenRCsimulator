// Research component binding for detached finite-liquid sources and mass.
// The actual session owns provenance, fuel events and stage composition.
#pragma once

#include <limits>
#include <vector>
#include "nk_electric_binding.hpp" // strict snapshot scalar/array decoder
#include "nk_liquid_mass.hpp"
#include "nk_liquid_propulsion.hpp"

namespace nk {

class LiquidBinding {
	bool ready_ = false;
	bool gas_ = false;
	LiquidMassModel mass_;
	LiquidGasShaft gas_shaft_;
	LiquidGasConsumption gas_fuel_;
	LiquidTurbine turbine_;
	R capacity_ = 0.0;
	R unusable_ = 0.0;
	int bound_index_ = 0;

	static godot::Dictionary failure(const std::string &reason) {
		godot::Dictionary out;
		out["ok"] = false;
		out["error"] = godot::String(reason.c_str());
		return out;
	}

	static godot::PackedFloat64Array packed(const std::vector<R> &v) {
		godot::PackedFloat64Array out;
		out.resize(static_cast<int64_t>(v.size()));
		for (size_t i = 0; i < v.size(); ++i) out[static_cast<int64_t>(i)] = v[i].v;
		return out;
	}

	static bool table_domain(const std::vector<double> &table, bool strictly_positive) {
		if (!liquid_table_valid(table)) return false;
		for (size_t i = 0; i < table.size(); i += 2) {
			if (table[i] < 0.0 || (strictly_positive ? table[i + 1] <= 0.0 : table[i + 1] < 0.0)) return false;
		}
		return true;
	}

	LiquidMassProperties live(R usable) const {
		if (!ready_ || !is_finite(usable) || usable.v > (capacity_ - unusable_).v) return {};
		std::vector<R> amounts;
		amounts.reserve(mass_.resources.size());
		for (const auto &resource : mass_.resources) amounts.push_back(resource.reference_kg);
		const R onboard = liquid_trial_onboard_mass(usable, unusable_, capacity_);
		amounts[static_cast<size_t>(bound_index_)] = liquid_inventory_usable_mass(onboard, unusable_, capacity_);
		return liquid_mass_evaluate(mass_, amounts.data(), static_cast<int>(amounts.size()));
	}

public:
	bool ready() const { return ready_; }
	bool is_gas() const { return gas_; }
	const LiquidMassModel &mass() const { return mass_; }
	const LiquidGasShaft &gas_shaft() const { return gas_shaft_; }
	const LiquidGasConsumption &gas_fuel() const { return gas_fuel_; }
	const LiquidTurbine &turbine() const { return turbine_; }
	R capacity() const { return capacity_; }
	R unusable() const { return unusable_; }
	int bound_index() const { return bound_index_; }

	godot::Dictionary prepare_liquid(const godot::Dictionary &snapshot) {
		ready_ = false;
		ElectricSnapshotDecoder dec;
		godot::String format, family;
		godot::Dictionary mass, store, source;
		if (!dec.keys(snapshot, "liquid", {"format", "family", "mass", "store", "source"}) ||
				!dec.string(snapshot, "format", format) || !dec.string(snapshot, "family", family) ||
				!dec.dictionary(snapshot, "mass", mass) || !dec.dictionary(snapshot, "store", store) ||
				!dec.dictionary(snapshot, "source", source)) return failure(dec.error);
		if (format != godot::String("openrc-nk3-liquid-component-v1")) return failure("unknown liquid component format");
		const bool gas = family == godot::String("gas");
		if (!gas && family != godot::String("turbine")) return failure("unsupported liquid source family");
		LiquidMassModel decoded_mass;
		std::vector<double> inertia, references, capacities;
		std::vector<std::vector<double>> centers, tensors;
		if (!dec.keys(mass, "mass", {"reference_mass_kg", "reference_inertia_kgm2", "references", "capacities", "centers", "tensors"}) ||
				!dec.number(mass, "reference_mass_kg", decoded_mass.reference_mass_kg) ||
				!dec.packed(mass, "reference_inertia_kgm2", inertia) || !dec.packed(mass, "references", references) ||
				!dec.packed(mass, "capacities", capacities)) return failure(dec.error);
		if (inertia.size() != 6 || references.empty() || references.size() != capacities.size() ||
				references.size() > static_cast<size_t>(std::numeric_limits<int>::max())) return failure("invalid liquid inventory shape");
		const int count = static_cast<int>(references.size());
		if (!dec.packed_rows(mass, "centers", count, centers) || !dec.packed_rows(mass, "tensors", count, tensors)) return failure(dec.error);
		for (int k = 0; k < 6; ++k) decoded_mass.reference_inertia[k] = inertia[static_cast<size_t>(k)];
		R total = 0.0;
		for (int i = 0; i < count; ++i) {
			const size_t j = static_cast<size_t>(i);
			if (references[j] < 0.0 || capacities[j] <= 0.0 || capacities[j] < references[j] ||
					centers[j].size() != 3 || tensors[j].size() != 6) return failure("invalid liquid resource");
			LiquidMassResource resource;
			resource.reference_kg = references[j]; resource.capacity_kg = capacities[j];
			for (int k = 0; k < 3; ++k) resource.center[k] = centers[j][static_cast<size_t>(k)];
			for (int k = 0; k < 6; ++k) resource.tensor_per_kg[k] = tensors[j][static_cast<size_t>(k)];
			total += resource.reference_kg;
			decoded_mass.resources.push_back(resource);
		}
		if (decoded_mass.reference_mass_kg.v <= total.v) return failure("reference mass must exceed resources");
		R capacity, unusable;
		int index = 0;
		if (!dec.keys(store, "store", {"capacity_kg", "unusable_kg", "bound_index"}) ||
				!dec.number(store, "capacity_kg", capacity) || !dec.number(store, "unusable_kg", unusable) ||
				!dec.integer(store, "bound_index", index, 0, count - 1)) return failure(dec.error);
		if (capacity.v <= 0.0 || unusable.v < 0.0 || unusable.v >= capacity.v ||
				(capacity - unusable).v != capacities[static_cast<size_t>(index)]) return failure("invalid bound liquid store");
		LiquidGasShaft shaft;
		LiquidGasConsumption fuel;
		LiquidTurbine turbine;
		if (gas) {
			std::vector<double> friction;
			if (!dec.keys(source, "gas source", {"power_curve", "friction", "idle_power", "peak_indicated_power", "bsfc_kg_kwh", "idle_flow_kg_s"}) ||
					!dec.packed(source, "power_curve", shaft.power_curve) || !dec.packed(source, "friction", friction) ||
					!dec.number(source, "idle_power", shaft.idle_power) || !dec.number(source, "peak_indicated_power", shaft.peak_indicated_power) ||
					!dec.number(source, "bsfc_kg_kwh", fuel.bsfc_kg_kwh) || !dec.number(source, "idle_flow_kg_s", fuel.idle_flow_kg_s)) return failure(dec.error);
			if (!table_domain(shaft.power_curve, false) || shaft.power_curve.front() <= 0.0 || friction.size() != 2 ||
					friction[0] < 0.0 || friction[1] < 0.0 || shaft.idle_power.v < 0.0 ||
					shaft.peak_indicated_power.v <= shaft.idle_power.v || fuel.bsfc_kg_kwh.v <= 0.0 || fuel.idle_flow_kg_s.v < 0.0) return failure("invalid gas shaft or fuel model");
			shaft.friction = {R(friction[0]), R(friction[1])};
			fuel.idle_power_w = shaft.idle_power;
		} else {
			std::vector<double> axis, offset, intake;
			if (!dec.keys(source, "turbine source", {"max_rpm", "axis", "offset", "intake_offset", "throttle_map", "accel_limit", "decel_limit",
					"static_thrust", "mass_flow", "fuel_flow", "ram_jet", "governor_tau", "installed_factor", "ram_flow", "rotor_inertia", "rotor_sense"}) ||
					!dec.number(source, "max_rpm", turbine.max_rpm) || !dec.packed(source, "axis", axis) || !dec.packed(source, "offset", offset) ||
					!dec.packed(source, "intake_offset", intake) || !dec.packed(source, "throttle_map", turbine.throttle_map) ||
					!dec.packed(source, "accel_limit", turbine.accel_limit) || !dec.packed(source, "decel_limit", turbine.decel_limit) ||
					!dec.packed(source, "static_thrust", turbine.static_thrust) || !dec.packed(source, "mass_flow", turbine.mass_flow) ||
					!dec.packed(source, "fuel_flow", turbine.fuel_flow) || !dec.number(source, "governor_tau", turbine.governor_tau) ||
					!dec.number(source, "installed_factor", turbine.installed_factor) || !dec.number(source, "rotor_inertia", turbine.rotor_inertia) ||
					!dec.number(source, "rotor_sense", turbine.rotor_sense)) return failure(dec.error);
			if (source.has("ram_flow") && !dec.number(source, "ram_flow", turbine.ram_flow)) return failure(dec.error);
			if (source.has("ram_jet") && !dec.packed(source, "ram_jet", turbine.ram_jet)) return failure(dec.error);
			if (axis.size() != 3 || offset.size() != 3 || intake.size() != 3 || turbine.max_rpm.v <= 0.0 || turbine.governor_tau.v <= 0.0 ||
					turbine.installed_factor.v <= 0.0 || turbine.rotor_inertia.v < 0.0 || std::fabs(turbine.rotor_sense.v) != 1.0 ||
					turbine.ram_flow.v < 0.0 || !table_domain(turbine.throttle_map, false) ||
					!table_domain(turbine.accel_limit, true) || !table_domain(turbine.decel_limit, true) ||
					!table_domain(turbine.static_thrust, false) || !table_domain(turbine.mass_flow, true) ||
					!table_domain(turbine.fuel_flow, false) || (!turbine.ram_jet.empty() && !table_domain(turbine.ram_jet, false))) return failure("invalid turbine model");
			for (int k = 0; k < 3; ++k) { turbine.axis[k] = axis[static_cast<size_t>(k)]; turbine.offset[k] = offset[static_cast<size_t>(k)]; turbine.intake_offset[k] = intake[static_cast<size_t>(k)]; }
			if (absf(turbine.axis[0] * turbine.axis[0] + turbine.axis[1] * turbine.axis[1] + turbine.axis[2] * turbine.axis[2] - 1.0).v > 1e-12) return failure("invalid turbine axis");
		}
		mass_ = std::move(decoded_mass); gas_ = gas; gas_shaft_ = std::move(shaft); gas_fuel_ = fuel;
		turbine_ = std::move(turbine); capacity_ = capacity; unusable_ = unusable; bound_index_ = index;
		ready_ = true;
		godot::Dictionary out;
		out["ok"] = true;
		out["error"] = "";
		return out;
	}

	godot::Dictionary liquid_mass_component(double usable) const {
		godot::Dictionary out;
		const auto properties = live(usable);
		out["ok"] = properties.ok;
		if (!properties.ok) return out;
		std::vector<R> values{properties.mass_kg};
		values.insert(values.end(), properties.cg.begin(), properties.cg.end());
		values.insert(values.end(), properties.inertia.begin(), properties.inertia.end());
		values.insert(values.end(), properties.inverse.begin(), properties.inverse.end());
		values.insert(values.end(), properties.inertia_origin.begin(), properties.inertia_origin.end());
		const R onboard = liquid_trial_onboard_mass(usable, unusable_, capacity_);
		values.push_back(onboard);
		values.push_back(liquid_inventory_usable_mass(onboard, unusable_, capacity_));
		out["values"] = packed(values);
		return out;
	}

	godot::Dictionary liquid_gas_laws_component(const PropModel &prop, double rpm, double throttle, double axial,
			double rho, double charge, double shaft_power, bool running) const {
		godot::Dictionary out;
		out["ok"] = ready_ && gas_;
		if (!ready_ || !gas_) return out;
		out["values"] = packed({liquid_gas_engine_torque(rpm, throttle, gas_shaft_, charge),
			liquid_gas_shaft_rate(rpm, throttle, axial, gas_shaft_, prop, rho, charge, running),
			liquid_gas_fuel_flow(gas_fuel_, running, shaft_power)});
		return out;
	}

	godot::Dictionary liquid_gas_component(const PropModel &prop, const godot::PackedFloat64Array &body,
			const godot::PackedFloat64Array &external, const godot::PackedFloat64Array &prop_air,
			const godot::PackedFloat64Array &datum_air, bool explicit_air, const godot::PackedFloat64Array &stage,
			bool running, double gravity) const {
		godot::Dictionary out;
		out["ok"] = false;
		if (!ready_ || !gas_ || body.size() != 13 || external.size() != 6 || prop_air.size() != 3 ||
				datum_air.size() != 3 || stage.size() != 5) return out;
		R s[13], loads[6], local[3], datum[3];
		for (int i = 0; i < 13; ++i) s[i] = body[i];
		for (int i = 0; i < 6; ++i) loads[i] = external[i];
		for (int i = 0; i < 3; ++i) {
			local[i] = prop_air[i]; datum[i] = datum_air[i];
			if (!is_finite(local[i]) || (!explicit_air && !is_finite(datum[i]))) return out;
		}
		const auto properties = live(stage[0]);
		if (!properties.ok) return out;
		const auto point = liquid_gas_coupled_stage(s, loads, local, datum, explicit_air, stage[1], stage[2],
				stage[3], stage[4], running, gas_shaft_, prop, gas_fuel_, properties.inertia.data(), properties.inverse.data());
		out["ok"] = point.ok;
		if (!point.ok) return out;
		std::vector<R> values;
		values.insert(values.end(), point.loads.begin(), point.loads.end());
		values.insert(values.end(), point.rotor.begin(), point.rotor.end());
		values.push_back(point.rpm_rate); values.push_back(point.fuel_rate);
		out["values"] = packed(values);
		const auto body_rate = liquid_fixed_datum_derivative(s, properties, point.loads.data(), point.loads.data() + 3,
				gravity, point.rotor.data());
		out["body_derivative"] = packed(std::vector<R>(body_rate.begin(), body_rate.end()));
		return out;
	}

	godot::Dictionary liquid_turbine_component(const godot::PackedFloat64Array &body,
			const godot::PackedFloat64Array &datum_air, const godot::PackedFloat64Array &explicit_air,
			const godot::PackedFloat64Array &stage, bool running) const {
		godot::Dictionary out;
		out["ok"] = false;
		if (!ready_ || gas_ || body.size() != 13 || datum_air.size() != 3 ||
				(!explicit_air.is_empty() && explicit_air.size() != 3) || stage.size() != 3) return out;
		R s[13], datum[3], explicit_values[3];
		for (int i = 0; i < 13; ++i) s[i] = body[i];
		for (int i = 0; i < 3; ++i) { datum[i] = datum_air[i]; if (!explicit_air.is_empty()) explicit_values[i] = explicit_air[i]; }
		const PropAir air = liquid_turbine_stage_air_velocity(s, datum, turbine_, explicit_air.is_empty() ? nullptr : explicit_values);
		if (!air.ok) return out;
		const auto point = liquid_turbine_stage(air.velocity.data(), stage[0], stage[1], turbine_, stage[2], running);
		out["ok"] = point.ok;
		if (!point.ok) return out;
		std::vector<R> values;
		values.insert(values.end(), air.velocity.begin(), air.velocity.end());
		values.insert(values.end(), point.loads.begin(), point.loads.end());
		values.insert(values.end(), point.rotor.begin(), point.rotor.end());
		values.push_back(point.rpm_rate); values.push_back(point.fuel_rate);
		out["values"] = packed(values);
		return out;
	}
};

} // namespace nk
