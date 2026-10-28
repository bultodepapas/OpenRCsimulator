// Prepared NITRO annular blade-element propeller. Mirrors glow/propeller.gd's
// PreparedEvaluator, including its stopped/windmilling branch and power guard.
#pragma once

#include <array>

#include "nk_prop.hpp"

namespace nk {

struct GlowBladeModel {
	bool valid = false;
	R diameter_m = 0.0;
	R chord_m = 0.0;
	R lift_slope = 0.0;
	R cd0 = 0.0;
	R induced_drag = 0.0;
	R blades = 0.0;
	R zero_lift_angle = 0.0;
	R dr = 0.0;
	std::array<R, 12> radii{};
	std::array<R, 12> pitch_angles{};
};

struct GlowBladePoint {
	bool ok = false;
	R thrust_n = 0.0;
	R torque_nm = 0.0;
	R shaft_power_w = 0.0;
	R thrust_power_w = 0.0;
	R dissipation_w = 0.0;
};

// Construct from normalized installation scalars. Caller checks dictionary types and unknown keys.
inline GlowBladeModel glow_blade_prepare(R diameter_m, R pitch_m, R chord_m, R lift_slope, R cd0,
		R induced_drag, R blades, R zero_lift_angle = 0.0) {
	GlowBladeModel out;
	const R positive[] = {diameter_m, pitch_m, chord_m, lift_slope, cd0, induced_drag, blades};
	for (R value : positive) if (!is_finite(value) || value.v <= 0.0) return out;
	if (!is_finite(zero_lift_angle) || zero_lift_angle.v < -0.3 || zero_lift_angle.v > 0.0) return out;
	out.diameter_m = diameter_m;
	out.chord_m = chord_m;
	out.lift_slope = lift_slope;
	out.cd0 = cd0;
	out.induced_drag = induced_drag;
	out.blades = blades;
	out.zero_lift_angle = zero_lift_angle;
	const R radius = 0.5 * diameter_m;
	out.dr = radius * 0.8 / 12.0;
	for (int i = 0; i < 12; ++i) {
		const R r = radius * 0.2 + (R(static_cast<double>(i)) + 0.5) * out.dr;
		out.radii[i] = r;
		out.pitch_angles[i] = atan2_(pitch_m, kTauConstant * r);
	}
	out.valid = true;
	return out;
}

inline GlowBladePoint glow_blade_evaluate(const GlowBladeModel &model, R rpm, R axial_speed, R rho) {
	GlowBladePoint out;
	if (!model.valid || !is_finite(rpm) || rpm.v < 0.0 || !is_finite(axial_speed) ||
			!is_finite(rho) || rho.v <= 0.0) return out;
	const R omega = rpm * kTauConstant / 60.0;
	if (!is_finite(omega)) return out;
	R thrust = 0.0, torque = 0.0, dissipation = 0.0;
	for (int i = 0; i < 12; ++i) {
		const R r = model.radii[i];
		const R tangential = omega * r;
		const R speed_sq = tangential * tangential + axial_speed * axial_speed;
		if (!is_finite(speed_sq) || speed_sq.v < 0.0) return out;
		if (speed_sq.v == 0.0) continue;
		const R speed = sqrt_(speed_sq);
		if (!is_finite(speed) || speed.v <= 0.0) return out;
		const R phi = atan2_(axial_speed, tangential);
		const R beta = model.pitch_angles[i];
		const R alpha = beta - phi - model.zero_lift_angle;
		R cl = model.lift_slope * sin_(2.0 * alpha) / 2.0;
		cl = clampf(cl, -1.25, 1.25);
		const R cd = model.cd0 + model.induced_drag * cl * cl + 1.2 * pow_(sin_(alpha), 2.0);
		const R area_pressure = 0.5 * rho * speed_sq * model.chord_m * model.dr * model.blades;
		const R lift = area_pressure * cl;
		const R drag = area_pressure * cd;
		if (!is_finite(area_pressure) || !is_finite(lift) || !is_finite(drag)) return out;
		thrust += (lift * tangential - drag * axial_speed) / speed;
		torque += (lift * axial_speed + drag * tangential) * r / speed;
		dissipation += drag * speed;
	}
	const R shaft_power = torque * omega;
	const R thrust_power = thrust * axial_speed;
	if (!is_finite(thrust) || !is_finite(torque) || !is_finite(dissipation) ||
			!is_finite(shaft_power) || !is_finite(thrust_power)) return out;
	if (thrust.v > 0.0 && axial_speed.v >= 0.0) {
		const R disk_area = R(kPi) * model.diameter_m * model.diameter_m / 4.0;
		const R disk_mass_term = rho * disk_area;
		if (!is_finite(disk_area) || disk_area.v <= 0.0 || !is_finite(disk_mass_term) || disk_mass_term.v <= 0.0) return out;
		const R ideal_speed_sq = axial_speed * axial_speed + 2.0 * thrust / disk_mass_term;
		if (!is_finite(ideal_speed_sq) || ideal_speed_sq.v <= 0.0) return out;
		const R ideal_power = 0.5 * thrust * (axial_speed + sqrt_(ideal_speed_sq));
		if (!is_finite(ideal_power) || ideal_power.v <= 0.0) return out;
		const R power_scale = maxf(absf(shaft_power), ideal_power);
		if (shaft_power.v < (ideal_power - 1e-10 * power_scale).v) return out;
	}
	out.ok = true;
	out.thrust_n = thrust;
	out.torque_nm = torque;
	out.shaft_power_w = shaft_power;
	out.thrust_power_w = thrust_power;
	out.dissipation_w = dissipation;
	return out;
}

} // namespace nk
