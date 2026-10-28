// Prepared two- and four-stroke mean-cycle glow sources. Mirrors glow/source.gd,
// two_stroke.gd and four_stroke.gd; lifecycle, fuel feed and events are separate.
#pragma once

#include <vector>

#include "nk_prop.hpp"

namespace nk {

enum class GlowFamily { TwoStroke, FourStroke };

struct GlowSourceModel {
	GlowFamily family = GlowFamily::TwoStroke;
	R max_rpm = 0.0;
	R displacement_m3 = 0.0;
	R oil_fraction = 0.0;
	R stoich_air_fuel_ratio = 0.0;
	R fuel_lhv_j_kg = 0.0;
	R intake_pressure_drop_pa = 0.0; // four-stroke
	std::vector<double> breathing; // delivery_ratio (2T) / volumetric_efficiency (4T)
	std::vector<double> trapping_efficiency; // 2T
	std::vector<double> pumping_pressure; // scavenge_pressure_pa (2T) / pumping_pressure_pa (4T)
	std::vector<double> mechanical_torque_nm;
	std::vector<double> combustion_efficiency;
	std::vector<double> indicated_efficiency;
	std::vector<double> valve_torque_nm; // 4T
};

struct GlowSourcePoint {
	bool ok = false;
	R indicated_torque_nm = 0.0;
	R mechanical_torque_nm = 0.0;
	R pumping_torque_nm = 0.0;
	R valve_torque_nm = 0.0;
	R shaft_torque_nm = 0.0;
	R delivered_fuel_kg_s = 0.0;
	R burned_fuel_kg_s = 0.0;
	R unburned_fuel_kg_s = 0.0;
	R fuel_input_power_w = 0.0;
	R chemical_power_w = 0.0;
	R indicated_power_w = 0.0;
	R mechanical_loss_w = 0.0;
	R pumping_loss_w = 0.0;
	R valve_loss_w = 0.0;
	R cycle_work_j = 0.0;
	R air_charge_kg_cycle = 0.0;
	R cycle_frequency_hz = 0.0;
	R opportunity_frequency_hz = 0.0;
	R firing_frequency_hz = 0.0;
	R brake_power_w = 0.0;
	R unburned_chemical_power_w = 0.0;
};

inline bool glow_source_table_shape_valid(const std::vector<double> &table) {
	if (table.size() < 4 || table.size() % 2 != 0) return false;
	for (size_t i = 0; i < table.size(); i += 2) {
		if (!std::isfinite(table[i]) || !std::isfinite(table[i + 1]) ||
				(i > 0 && table[i] <= table[i - 2])) return false;
	}
	return true;
}

inline bool glow_source_has_pairs(const std::vector<double> &table) {
	return table.size() >= 4 && table.size() % 2 == 0;
}

// The decoder performs the full model validation once. Repeated stages check shapes to
// avoid out-of-range indexing without walking the immutable tables on every RK call.
inline bool glow_source_shapes_valid(const GlowSourceModel &model) {
	if (!glow_source_has_pairs(model.breathing) || !glow_source_has_pairs(model.pumping_pressure) ||
			!glow_source_has_pairs(model.mechanical_torque_nm) || !glow_source_has_pairs(model.combustion_efficiency) ||
			!glow_source_has_pairs(model.indicated_efficiency)) return false;
	if (model.family == GlowFamily::TwoStroke) return glow_source_has_pairs(model.trapping_efficiency);
	return model.family == GlowFamily::FourStroke && glow_source_has_pairs(model.valve_torque_nm);
}

inline bool glow_source_model_valid(const GlowSourceModel &model) {
	if (!is_finite(model.max_rpm) || model.max_rpm.v <= 0.0 ||
			!is_finite(model.displacement_m3) || model.displacement_m3.v <= 0.0 ||
			!is_finite(model.oil_fraction) || model.oil_fraction.v < 0.0 || model.oil_fraction.v >= 1.0 ||
			!is_finite(model.stoich_air_fuel_ratio) || model.stoich_air_fuel_ratio.v <= 0.0 ||
			!is_finite(model.fuel_lhv_j_kg) || model.fuel_lhv_j_kg.v <= 0.0 ||
			!glow_source_table_shape_valid(model.breathing) ||
			!glow_source_table_shape_valid(model.pumping_pressure) ||
			!glow_source_table_shape_valid(model.mechanical_torque_nm) ||
			!glow_source_table_shape_valid(model.combustion_efficiency) ||
			!glow_source_table_shape_valid(model.indicated_efficiency)) return false;
	if (model.family == GlowFamily::TwoStroke) return glow_source_table_shape_valid(model.trapping_efficiency);
	return model.family == GlowFamily::FourStroke && is_finite(model.intake_pressure_drop_pa) &&
			model.intake_pressure_drop_pa.v >= 0.0 && glow_source_table_shape_valid(model.valve_torque_nm);
}

// Unlike the turbine interpolator this is y0 + (y1-y0)*fraction, not Godot lerpf.
inline R glow_source_table_sample(const std::vector<double> &table, R query) {
	for (size_t i = 0; i + 2 < table.size(); i += 2) {
		const R x0 = table[i], y0 = table[i + 1], x1 = table[i + 2], y1 = table[i + 3];
		if (query.v <= x1.v) {
			const R fraction = (query - x0) / (x1 - x0);
			return y0 + (y1 - y0) * fraction;
		}
	}
	return table.back();
}

inline bool glow_source_table_covers(const std::vector<double> &table, R value) {
	return value.v >= table[0] && value.v <= table[table.size() - 2];
}

// Mirrors Source.evaluate_prepared and its source family's prevalidated stage path.
inline GlowSourcePoint glow_source_evaluate(const GlowSourceModel &model, R rpm, R admission,
		R mixture, R dry_density, bool running, R firing_fraction) {
	GlowSourcePoint out;
	if (!glow_source_shapes_valid(model) || !is_finite(rpm) || rpm.v < 0.0 || rpm.v > model.max_rpm.v ||
			!is_finite(admission) || admission.v < 0.0 || admission.v > 1.0 ||
			!is_finite(mixture) || mixture.v < 0.0 || !is_finite(dry_density) || dry_density.v <= 0.0 ||
			!is_finite(firing_fraction) || firing_fraction.v < 0.0 || firing_fraction.v > 1.0 ||
			!glow_source_table_covers(model.breathing, rpm) ||
			!glow_source_table_covers(model.pumping_pressure, rpm) ||
			!glow_source_table_covers(model.mechanical_torque_nm, rpm) ||
			!glow_source_table_covers(model.indicated_efficiency, rpm) ||
			!glow_source_table_covers(model.combustion_efficiency, mixture)) return out;
	const bool two = model.family == GlowFamily::TwoStroke;
	if (two ? !glow_source_table_covers(model.trapping_efficiency, rpm) :
			!glow_source_table_covers(model.valve_torque_nm, rpm)) return out;
	const R cycle_frequency = two ? rpm / 60.0 : rpm / 120.0;
	const R opportunity_frequency = cycle_frequency;
	const R omega = 2.0 * R(kPi) * rpm / 60.0;
	const R breathing = glow_source_table_sample(model.breathing, rpm);
	const R trapping = two ? glow_source_table_sample(model.trapping_efficiency, rpm) : R(1.0);
	const R air_delivered = dry_density * model.displacement_m3 * admission * breathing;
	const R air_charge = two ? air_delivered * trapping : air_delivered;
	R indicated_torque = 0.0, mechanical_torque = 0.0, pumping_torque = 0.0, valve_torque = 0.0;
	R delivered_fuel = 0.0, burned_fuel = 0.0, fuel_input_power = 0.0, chemical_power = 0.0;
	R indicated_power = 0.0, cycle_work = 0.0, firing_frequency = 0.0;
	if (rpm.v > 0.0) {
		mechanical_torque = glow_source_table_sample(model.mechanical_torque_nm, rpm);
		const R pumping_pressure = glow_source_table_sample(model.pumping_pressure, rpm);
		if (two) {
			const R scavenge_work = pumping_pressure * model.displacement_m3 * breathing * admission;
			pumping_torque = scavenge_work / (2.0 * R(kPi));
		} else {
			valve_torque = glow_source_table_sample(model.valve_torque_nm, rpm);
			const R pumping_work = (pumping_pressure + model.intake_pressure_drop_pa * (1.0 - admission)) *
					model.displacement_m3;
			pumping_torque = pumping_work / (4.0 * R(kPi));
		}
		if (running) {
			const R premix_base = two ? air_delivered : air_charge;
			const R gross_premix = premix_base * mixture / model.stoich_air_fuel_ratio / (1.0 - model.oil_fraction);
			const R gross_combustible = gross_premix * (1.0 - model.oil_fraction);
			const R combustible = two ? gross_combustible * trapping : gross_combustible;
			const R oxygen_limit = air_charge / model.stoich_air_fuel_ratio;
			const R efficiency = glow_source_table_sample(model.combustion_efficiency, mixture);
			const R burned = minf(combustible, oxygen_limit) * efficiency * firing_fraction;
			const R indicated_efficiency = glow_source_table_sample(model.indicated_efficiency, rpm);
			delivered_fuel = gross_premix * opportunity_frequency;
			burned_fuel = burned * opportunity_frequency;
			if (burned.v > 0.0) firing_frequency = opportunity_frequency * firing_fraction;
			fuel_input_power = gross_combustible * opportunity_frequency * model.fuel_lhv_j_kg;
			chemical_power = burned_fuel * model.fuel_lhv_j_kg;
			cycle_work = burned * model.fuel_lhv_j_kg * indicated_efficiency;
			indicated_torque = cycle_work / (two ? 2.0 * R(kPi) : 4.0 * R(kPi));
			indicated_power = indicated_torque * omega;
		}
	}
	const R mechanical_loss = mechanical_torque * omega;
	const R pumping_loss = pumping_torque * omega;
	const R valve_loss = two ? R(0.0) : valve_torque * omega;
	const R unburned_fuel = delivered_fuel - burned_fuel;
	R shaft_torque = indicated_torque - mechanical_torque - pumping_torque;
	if (!two) shaft_torque -= valve_torque;
	const R brake_power = shaft_torque * rpm * kTauConstant / 60.0;
	const R unburned_chemical = fuel_input_power - chemical_power;
	const R checked[] = {indicated_torque, mechanical_torque, pumping_torque, valve_torque, shaft_torque,
		delivered_fuel, burned_fuel, unburned_fuel, fuel_input_power, chemical_power, indicated_power,
		mechanical_loss, pumping_loss, valve_loss, cycle_work, air_charge, cycle_frequency,
		opportunity_frequency, firing_frequency, brake_power, unburned_chemical};
	for (R value : checked) if (!is_finite(value)) return out;
	if (unburned_chemical.v < (-1e-10 * maxf(1.0, fuel_input_power)).v) return out;
	out.ok = true;
	out.indicated_torque_nm = indicated_torque; out.mechanical_torque_nm = mechanical_torque;
	out.pumping_torque_nm = pumping_torque; out.valve_torque_nm = valve_torque;
	out.shaft_torque_nm = shaft_torque; out.delivered_fuel_kg_s = delivered_fuel;
	out.burned_fuel_kg_s = burned_fuel; out.unburned_fuel_kg_s = unburned_fuel;
	out.fuel_input_power_w = fuel_input_power; out.chemical_power_w = chemical_power;
	out.indicated_power_w = indicated_power; out.mechanical_loss_w = mechanical_loss;
	out.pumping_loss_w = pumping_loss; out.valve_loss_w = valve_loss;
	out.cycle_work_j = cycle_work; out.air_charge_kg_cycle = air_charge;
	out.cycle_frequency_hz = cycle_frequency; out.opportunity_frequency_hz = opportunity_frequency;
	out.firing_frequency_hz = firing_frequency; out.brake_power_w = brake_power;
	out.unburned_chemical_power_w = unburned_chemical;
	return out;
}

struct GlowUnitFlow { bool ok = false; R kg_s_per_mixture = 0.0; };

// Source.unit_fuel_flow_prepared: the prepared lifecycle deliberately uses this reduced
// arithmetic for transport target, rather than dividing a full source's delivered flow.
inline GlowUnitFlow glow_unit_fuel_flow(const GlowSourceModel &model, R rpm, R admission, R mixture, R dry_density) {
	GlowUnitFlow out;
	if (!glow_source_shapes_valid(model) || !is_finite(rpm) || rpm.v < 0.0 || rpm.v > model.max_rpm.v ||
			!is_finite(admission) || admission.v < 0.0 || admission.v > 1.0 ||
			!is_finite(mixture) || mixture.v < 0.0 || !is_finite(dry_density) || dry_density.v <= 0.0 ||
			!glow_source_table_covers(model.combustion_efficiency, mixture)) return out;
	R unit_flow = 0.0;
	if (rpm.v > 0.0) {
		const R breathing = glow_source_table_sample(model.breathing, rpm);
		const R air_per_cycle = dry_density * model.displacement_m3 * admission * breathing;
		const R frequency = model.family == GlowFamily::TwoStroke ? rpm / 60.0 : rpm / 120.0;
		const R gross_premix = air_per_cycle * mixture / model.stoich_air_fuel_ratio / (1.0 - model.oil_fraction);
		const R delivered = gross_premix * frequency;
		unit_flow = mixture.v > 0.0 ? delivered / mixture : R(0.0);
	}
	if (!is_finite(unit_flow) || unit_flow.v < 0.0) return out;
	out.ok = true;
	out.kg_s_per_mixture = unit_flow;
	return out;
}

} // namespace nk
