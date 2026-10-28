// Finite liquid-fuel propulsion components: the inherited combustion shaft and model-jet turbine.
// Mirrors propulsion.gd, turbine.gd and liquid_fuel.gd. Stage assembly, air/ground loads and
// resource events stay with their owner. All arrays and tables are detached prepared values.
#pragma once

#include <array>
#include <vector>

#include "nk_prop.hpp"
#include "nk_rotor_coupling.hpp"

namespace nk {

struct LiquidGasShaft {
	std::vector<double> power_curve; // [rpm, brake power W, ...]
	std::array<R, 2> friction{};
	R idle_power = 0.0;
	R peak_indicated_power = 0.0;
};

struct LiquidTurbine {
	R max_rpm = 0.0;
	R axis[3] = {1.0, 0.0, 0.0};
	R offset[3] = {0.0, 0.0, 0.0};
	R intake_offset[3] = {0.0, 0.0, 0.0};
	std::vector<double> throttle_map;
	std::vector<double> accel_limit;
	std::vector<double> decel_limit;
	std::vector<double> static_thrust;
	std::vector<double> mass_flow;
	std::vector<double> ram_jet; // absent = zero correction
	std::vector<double> fuel_flow;
	R governor_tau = 0.0;
	R installed_factor = 0.0;
	R ram_flow = 0.0;
	R rotor_inertia = 0.0;
	R rotor_sense = 0.0;
};

struct LiquidGasConsumption {
	R bsfc_kg_kwh = 0.0;
	R idle_power_w = 0.0;
	R idle_flow_kg_s = 0.0;
};

// Prepared table checks are separate from evaluation so a caller can fail closed at decode.
inline bool liquid_table_valid(const std::vector<double> &table) {
	if (table.size() < 4 || table.size() % 2 != 0) return false;
	for (size_t i = 0; i < table.size(); i += 2) {
		if (!std::isfinite(table[i]) || !std::isfinite(table[i + 1]) ||
				(i > 0 && table[i] <= table[i - 2])) return false;
	}
	return true;
}

inline R liquid_turbine_table(const std::vector<double> &table, R x) {
	const int n = static_cast<int>(table.size()) / 2;
	if (x.v <= table[0]) return table[1];
	for (int i = 1; i < n; ++i) {
		if (x.v <= table[2 * i]) {
			const R x0 = table[2 * i - 2];
			return lerpf(table[2 * i - 1], table[2 * i + 1], (x - x0) / (R(table[2 * i]) - x0));
		}
	}
	return table[2 * n - 1];
}

inline R liquid_turbine_table_extrapolated(const std::vector<double> &table, R x) {
	const int n = static_cast<int>(table.size()) / 2;
	if (x.v < table[0]) {
		return R(table[1]) + (R(table[3]) - table[1]) / (R(table[2]) - table[0]) * (x - table[0]);
	}
	if (x.v > table[2 * n - 2]) {
		return R(table[2 * n - 1]) + (R(table[2 * n - 1]) - table[2 * n - 3]) /
				(R(table[2 * n - 2]) - table[2 * n - 4]) * (x - table[2 * n - 2]);
	}
	return liquid_turbine_table(table, x);
}

inline R liquid_gas_engine_torque(R rpm, R throttle, const LiquidGasShaft &shaft, R charge_ratio) {
	if (!is_finite(charge_ratio) || charge_ratio.v < 0.0) return kNan;
	const R omega = maxf(rpm, 0.0) * kTauConstant / 60.0;
	const R friction = shaft.friction[0] + shaft.friction[1] * rpm / 1000.0;
	R brake_full;
	if (rpm.v <= shaft.power_curve[0]) {
		brake_full = R(shaft.power_curve[1]) / (R(shaft.power_curve[0]) * kTauConstant / 60.0);
	} else {
		brake_full = prop_coefficient(shaft.power_curve, rpm, 0.0) / omega;
	}
	const R admitted = shaft.idle_power + clampf(throttle, 0.0, 1.0) *
			(shaft.peak_indicated_power - shaft.idle_power);
	R indicated = minf(brake_full + friction, admitted / maxf(omega, 1.0));
	if (charge_ratio.v != 1.0) indicated *= charge_ratio;
	return indicated - friction;
}

// Propulsion.shaft_rate's non-electric, non-glow route. A stopped source retains the
// authored friction and windmilling prop torque; below STOPPED_RPM it cannot reverse.
inline R liquid_gas_shaft_rate(R rpm, R throttle, R axial_speed, const LiquidGasShaft &shaft,
		const PropModel &prop, R rho, R charge_ratio, bool running) {
	if (!is_finite(rpm) || rpm.v < 0.0 || !is_finite(throttle) || !is_finite(axial_speed) ||
			!is_finite(rho) || rho.v <= 0.0 || !is_finite(charge_ratio) || charge_ratio.v < 0.0 ||
			!is_finite(prop.rotor_inertia) || prop.rotor_inertia.v <= 0.0) return kNan;
	const R engine = running ? liquid_gas_engine_torque(rpm, throttle, shaft, charge_ratio) :
			-shaft.friction[0] - shaft.friction[1] * rpm / 1000.0;
	const R net = engine - prop_torque(rpm, axial_speed, prop, rho);
	if (rpm.v <= kStoppedRpm && net.v < 0.0) return 0.0;
	return net / prop.rotor_inertia * 60.0 / kTauConstant;
}

inline R liquid_gas_fuel_flow(const LiquidGasConsumption &fuel, bool running, R shaft_power_w) {
	if (!running) return 0.0;
	if (!is_finite(shaft_power_w) || !is_finite(fuel.bsfc_kg_kwh) || !is_finite(fuel.idle_power_w) ||
			!is_finite(fuel.idle_flow_kg_s) || fuel.bsfc_kg_kwh.v <= 0.0 || fuel.idle_power_w.v < 0.0 ||
			fuel.idle_flow_kg_s.v < 0.0) return kNan;
	const R result = fuel.idle_flow_kg_s + maxf(shaft_power_w - fuel.idle_power_w, 0.0) * fuel.bsfc_kg_kwh / 3600000.0;
	return is_finite(result) && result.v >= 0.0 ? result : R(kNan);
}

struct LiquidGasStage {
	bool ok = false;
	std::array<R, 6> loads{}; // about live CG, including rotor reaction
	std::array<R, 3> rotor{};
	R rpm_rate = 0.0;
	R fuel_rate = 0.0;
};

// FlightSession._coupled_response for a finite-fuel combustion propeller. `external` already
// contains this stage's aero/propulsion/ground loads shifted once from datum to live CG. The
// explicit_air flag records the stage-air key: at the stopped-friction boundary the old law
// uses prop_air for that key but datum_air otherwise. The caller owns wash/wheel derivatives.
inline LiquidGasStage liquid_gas_coupled_stage(const R *body, const R *external, const R *prop_air,
		const R *datum_air, bool explicit_air, R rpm, R throttle, R rho, R charge_ratio, bool running,
		const LiquidGasShaft &shaft, const PropModel &prop, const LiquidGasConsumption &fuel,
		const R *inertia, const R *inverse) {
	LiquidGasStage out;
	if (body == nullptr || external == nullptr || prop_air == nullptr || datum_air == nullptr ||
			inertia == nullptr || inverse == nullptr) return out;
	R axis[3] = {1.0, 0.0, 0.0};
	if (prop.has_axis) for (int i = 0; i < 3; ++i) axis[i] = prop.axis[i];
	const R axial = prop_air[0] * axis[0] + prop_air[1] * axis[1] + prop_air[2] * axis[2];
	R rate = liquid_gas_shaft_rate(rpm, throttle, axial, shaft, prop, rho, charge_ratio, running);
	if (!is_finite(rate)) return out;
	bool locked = false;
	if (!running && rpm.v <= kStoppedRpm && rate.v == 0.0) {
		const R friction = shaft.friction[0];
		const R w0 = body[10], w1 = body[11], w2 = body[12];
		const R body_h0 = inertia[0] * w0 + inertia[3] * w1 + inertia[4] * w2;
		const R body_h1 = inertia[3] * w0 + inertia[1] * w1 + inertia[5] * w2;
		const R body_h2 = inertia[4] * w0 + inertia[5] * w1 + inertia[2] * w2;
		const std::array<R, 3> rotor_h = prop_rotor_momentum(prop, rpm);
		const R h0 = body_h0 + rotor_h[0], h1 = body_h1 + rotor_h[1], h2 = body_h2 + rotor_h[2];
		const R m0 = external[3] - (w1 * h2 - w2 * h1);
		const R m1 = external[4] - (w2 * h0 - w0 * h2);
		const R m2 = external[5] - (w0 * h1 - w1 * h0);
		const R free0 = inverse[0] * m0 + inverse[3] * m1 + inverse[4] * m2;
		const R free1 = inverse[3] * m0 + inverse[1] * m1 + inverse[5] * m2;
		const R free2 = inverse[4] * m0 + inverse[5] * m1 + inverse[2] * m2;
		const R required = prop.rotor_inertia * (axis[0] * free0 + axis[1] * free1 + axis[2] * free2);
		const R *drive_air = explicit_air ? prop_air : datum_air;
		const R drive_u = drive_air[0] * axis[0] + drive_air[1] * axis[1] + drive_air[2] * axis[2];
		const R drive = -prop_torque(rpm, drive_u, prop, rho);
		if (!is_finite(friction) || friction.v < 0.0 || !is_finite(required) || !is_finite(drive)) return out;
		if (absf(drive - required).v <= friction.v) {
			locked = true;
			rate = required / prop.rotor_inertia * 60.0 / kTauConstant;
		} else if ((drive - required).v < (-friction).v) {
			return out; // reverse breakaway remains outside the authored law
		} else {
			rate = (drive - friction) / prop.rotor_inertia * 60.0 / kTauConstant;
		}
	}
	const R moments[3] = {external[3], external[4], external[5]};
	RotorCouplingResult coupled = rotor_coupling_response(body + 10, moments, inertia, inverse, axis,
			prop.rotor_inertia, rpm * kTauConstant / 60.0, rate * prop.rotor_inertia * kTauConstant / 60.0);
	if (!coupled.ok) return out;
	if (locked) {
		coupled.spin_acceleration = 0.0;
		coupled.reaction = {0.0, 0.0, 0.0};
	}
	for (int i = 0; i < 6; ++i) out.loads[i] = external[i];
	for (int i = 0; i < 3; ++i) out.loads[3 + i] += coupled.reaction[i];
	out.rpm_rate = coupled.spin_acceleration * 60.0 / kTauConstant;
	out.rotor = prop_rotor_momentum(prop, rpm);
	const R shaft_power = running ? maxf(0.0, liquid_gas_engine_torque(rpm, throttle, shaft, charge_ratio) *
			rpm * kTauConstant / 60.0) : R(0.0);
	out.fuel_rate = liquid_gas_fuel_flow(fuel, running, shaft_power);
	if (!is_finite(out.fuel_rate) || out.fuel_rate.v < 0.0) return LiquidGasStage{};
	out.ok = true;
	return out;
}

inline R liquid_turbine_demand_rpm(R throttle, const LiquidTurbine &turbine) {
	return liquid_turbine_table(turbine.throttle_map, clampf(throttle, 0.0, 1.0));
}

inline R liquid_turbine_spool_rate(R rpm, R demand, const LiquidTurbine &turbine) {
	const R governed = (demand - rpm) / turbine.governor_tau;
	return clampf(governed, -liquid_turbine_table(turbine.decel_limit, rpm),
			liquid_turbine_table(turbine.accel_limit, rpm));
}

inline R liquid_turbine_mass_flow(R rpm, const LiquidTurbine &turbine, R rho, R u) {
	if (rpm.v < kStoppedRpm) return 0.0;
	const R uu = maxf(u, 0.0);
	return liquid_turbine_table_extrapolated(turbine.mass_flow, rpm) * rho / 1.225 *
			(1.0 + turbine.ram_flow * uu * uu);
}

inline R liquid_turbine_gross_thrust(R rpm, const LiquidTurbine &turbine, R rho, R u) {
	if (rpm.v < kStoppedRpm) return 0.0;
	const R static_gross = turbine.installed_factor * liquid_turbine_table_extrapolated(turbine.static_thrust, rpm);
	const R flow0 = liquid_turbine_table_extrapolated(turbine.mass_flow, rpm);
	const R vj0 = static_gross / flow0;
	const R uu = maxf(u, 0.0);
	const R k_jet = turbine.ram_jet.empty() ? R(0.0) : liquid_turbine_table(turbine.ram_jet, rpm);
	return liquid_turbine_mass_flow(rpm, turbine, rho, uu) * sqrt_(vj0 * vj0 + k_jet * uu * uu);
}

inline R liquid_turbine_fuel_flow(R rpm, const LiquidTurbine &turbine, bool running) {
	if (!running) return 0.0;
	if (!is_finite(rpm) || rpm.v < 0.0 || turbine.fuel_flow.size() < 4) return kNan;
	for (double value : turbine.fuel_flow) if (!std::isfinite(value) || value < 0.0) return kNan;
	const R result = rpm.v < kStoppedRpm ? R(0.0) : liquid_turbine_table(turbine.fuel_flow, rpm);
	return is_finite(result) && result.v >= 0.0 ? result : R(kNan);
}

// Explicit velocity is already at the intake; otherwise retain turbine's grouped
// datum + (omega cross intake offset), which differs from the propeller hub expression.
inline PropAir liquid_turbine_stage_air_velocity(const R *body, const R *datum_air,
		const LiquidTurbine &turbine, const R *explicit_air = nullptr) {
	PropAir out;
	if (explicit_air != nullptr) {
		for (int i = 0; i < 3; ++i) {
			if (!is_finite(explicit_air[i])) return out;
			out.velocity[i] = explicit_air[i];
		}
		out.ok = true;
		return out;
	}
	if (body == nullptr || datum_air == nullptr) return out;
	for (int i = 0; i < 3; ++i) if (!is_finite(datum_air[i])) return out;
	const R x = -turbine.intake_offset[0], y = turbine.intake_offset[1], z = -turbine.intake_offset[2];
	const R p = body[10], q = body[11], r = body[12];
	out.velocity = {datum_air[0] + (q * z - r * y), datum_air[1] + (r * x - p * z),
		datum_air[2] + (p * y - q * x)};
	for (R value : out.velocity) if (!is_finite(value)) return PropAir{};
	out.ok = true;
	return out;
}

inline std::array<R, 6> liquid_turbine_loads(const R *inlet_air, R rpm, const LiquidTurbine &turbine, R rho) {
	if (rpm.v < kStoppedRpm) return {0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
	const R u = inlet_air[0] * turbine.axis[0] + inlet_air[1] * turbine.axis[1] + inlet_air[2] * turbine.axis[2];
	const R gross = liquid_turbine_gross_thrust(rpm, turbine, rho, u);
	const R f0 = turbine.axis[0] * gross, f1 = turbine.axis[1] * gross, f2 = turbine.axis[2] * gross;
	const R inlet_scale = -liquid_turbine_mass_flow(rpm, turbine, rho, u);
	const R c0 = inlet_air[0] * inlet_scale, c1 = inlet_air[1] * inlet_scale, c2 = inlet_air[2] * inlet_scale;
	const R x = -turbine.offset[0], y = turbine.offset[1], z = -turbine.offset[2];
	const R ix = -turbine.intake_offset[0], iy = turbine.intake_offset[1], iz = -turbine.intake_offset[2];
	return {f0 + c0, f1 + c1, f2 + c2,
		(y * f2 - z * f1) + (iy * c2 - iz * c1),
		(z * f0 - x * f2) + (iz * c0 - ix * c2),
		(x * f1 - y * f0) + (ix * c1 - iy * c0)};
}

inline std::array<R, 3> liquid_turbine_rotor_momentum(R rpm, const LiquidTurbine &turbine) {
	const R h = turbine.rotor_inertia * turbine.rotor_sense * rpm * kTauConstant / 60.0;
	return {turbine.axis[0] * h, turbine.axis[1] * h, turbine.axis[2] * h};
}

struct LiquidTurbineStage {
	bool ok = false;
	std::array<R, 6> loads{};
	std::array<R, 3> rotor{};
	R rpm_rate = 0.0;
	R fuel_rate = 0.0;
};

// The full session adds aero, gear and hull loads; it supplies the stage-local intake
// and source latch. Fuel rate is zero while disabled; spool continues toward zero.
inline LiquidTurbineStage liquid_turbine_stage(const R *inlet_air, R rpm, R throttle,
		const LiquidTurbine &turbine, R rho, bool source_enabled) {
	LiquidTurbineStage out;
	if (inlet_air == nullptr || !is_finite(rpm) || rpm.v < 0.0 || rpm.v > turbine.max_rpm.v) return out;
	if (source_enabled) out.loads = liquid_turbine_loads(inlet_air, rpm, turbine, rho);
	out.rotor = liquid_turbine_rotor_momentum(rpm, turbine);
	const R demand = source_enabled ? liquid_turbine_demand_rpm(throttle, turbine) : R(0.0);
	out.rpm_rate = liquid_turbine_spool_rate(rpm, demand, turbine);
	out.fuel_rate = liquid_turbine_fuel_flow(rpm, turbine, source_enabled);
	if (!is_finite(out.fuel_rate) || out.fuel_rate.v < 0.0) return LiquidTurbineStage{};
	out.ok = true;
	return out;
}

} // namespace nk
