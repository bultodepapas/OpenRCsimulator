// Experimental X-Cell rotorcraft joint-stage composition. This is not integrated or qualified; session-owned
// step policy, event location, reset, lifecycle updates and observers remain in GDScript.
#pragma once

#include <array>

#include "nk_helicopter_aero.hpp"
#include "nk_helicopter_controls.hpp"
#include "nk_helicopter_skids.hpp"

namespace nk {

struct HeliDriveModel {
	R engine_torque_max_nm = 0.0, engine_power_max_w = 0.0, engine_speed_ratio_to_main = 0.0;
	R gear_efficiency = 0.0, governor_target_main_rad_s = 0.0, governor_gain_nm_per_rad_s = 0.0;
	R shaft_loss_torque_nm = 0.0, shaft_viscous_loss_nm_per_rad_s = 0.0;
};

struct HeliDriveResult {
	bool ok = false;
	R net_torque = 0.0, shaft_loss = 0.0;
	const char *message = "";
};

inline HeliDriveResult heli_drive_failure(const char *message) {
	HeliDriveResult result;
	result.message = message;
	return result;
}

inline HeliDriveResult heli_drive(const HeliDriveModel &m, R main_speed, R drive_fraction, bool hold, R drive_scale) {
	if (!heli_inflow_finite({main_speed, drive_fraction, drive_scale}) || main_speed < 0.0
			|| drive_fraction < 0.0 || drive_fraction > 1.0 || drive_scale < 0.0 || drive_scale > 1.0) {
		return heli_drive_failure("invalid drive state, command or prepared context");
	}
	const R ratio = m.engine_speed_ratio_to_main;
	const R engine_speed = ratio * main_speed;
	if (!is_finite(engine_speed)) {
		return heli_drive_failure("engine shaft speed overflowed");
	}
	if (hold) {
		R held_loss = m.shaft_viscous_loss_nm_per_rad_s * main_speed;
		if (main_speed > 0.0) {
			held_loss += m.shaft_loss_torque_nm;
		}
		return {true, -held_loss, held_loss};
	}
	R commanded_torque = drive_fraction * m.engine_torque_max_nm;
	const R governor_error = m.governor_target_main_rad_s - main_speed;
	commanded_torque += m.governor_gain_nm_per_rad_s * governor_error;
	commanded_torque = clampf(commanded_torque, 0.0, m.engine_torque_max_nm);
	R delivered_torque = commanded_torque;
	if (engine_speed > 0.0) {
		const R torque_at_power = m.engine_power_max_w / engine_speed;
		if (torque_at_power < delivered_torque) {
			delivered_torque = torque_at_power;
		}
	}
	if (drive_scale < 1.0) {
		delivered_torque *= drive_scale;
	}
	const R engine_power = delivered_torque * engine_speed;
	const R main_torque = m.gear_efficiency * ratio * delivered_torque;
	const R main_power = main_torque * main_speed;
	R shaft_loss = m.shaft_viscous_loss_nm_per_rad_s * main_speed;
	if (main_speed > 0.0) {
		shaft_loss += m.shaft_loss_torque_nm;
	}
	R net_torque = main_torque - shaft_loss;
	if (main_speed == 0.0) {
		shaft_loss = minf(main_torque, m.shaft_loss_torque_nm);
		net_torque = main_torque - shaft_loss;
	}
	if (!heli_inflow_finite({delivered_torque, engine_power, main_torque, main_power, shaft_loss, net_torque})) {
		return heli_drive_failure("drive output overflowed finite range");
	}
	return {true, net_torque, shaft_loss};
}

inline R heli_dot3(const Vec3 &a, const Vec3 &b) {
	return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

inline Vec3 heli_inertia_mul(const std::array<R, 6> &j, const Vec3 &v) {
	return {j[0] * v[0] + j[3] * v[1] + j[4] * v[2], j[3] * v[0] + j[1] * v[1] + j[5] * v[2],
		j[4] * v[0] + j[5] * v[1] + j[2] * v[2]};
}

struct HeliCouplingResult {
	bool ok = false;
	R spin_acceleration = 0.0;
	Vec3 body_acceleration{}, reaction{}, rotor_momentum{};
	const char *message = "";
};

inline HeliCouplingResult heli_coupling_failure(const char *message) {
	HeliCouplingResult result;
	result.message = message;
	return result;
}

inline HeliCouplingResult heli_geared_coupling(const Vec3 &rates, const Vec3 &moment,
		const std::array<R, 6> &inertia, const std::array<R, 6> &inverse, const Vec3 &b, R spin_inertia,
		R omega, R generalized_torque, R static_friction) {
	for (const R value : inertia) {
		if (!is_finite(value)) return heli_coupling_failure("invalid geared-coupling state or context");
	}
	for (const R value : inverse) {
		if (!is_finite(value)) return heli_coupling_failure("invalid geared-coupling state or context");
	}
	if (!heli_inflow_finite({rates[0], rates[1], rates[2], moment[0], moment[1], moment[2], b[0], b[1], b[2],
			spin_inertia, omega, generalized_torque, static_friction}) || spin_inertia <= 0.0 || omega < 0.0 || static_friction < 0.0) {
		return heli_coupling_failure("invalid geared-coupling state or context");
	}
	const Vec3 inverse_b = heli_inertia_mul(inverse, b);
	const R denominator = 1.0 - heli_dot3(b, inverse_b) / spin_inertia;
	if (!is_finite(denominator) || denominator <= 0.0) {
		return heli_coupling_failure("geared coupling has nonpositive effective carrier inertia");
	}
	const Vec3 body_spin_momentum = heli_inertia_mul(inertia, rates);
	const Vec3 rotor_momentum = {b[0] * omega, b[1] * omega, b[2] * omega};
	const Vec3 total = {body_spin_momentum[0] + rotor_momentum[0], body_spin_momentum[1] + rotor_momentum[1],
		body_spin_momentum[2] + rotor_momentum[2]};
	const Vec3 gyroscopic = cross3(rates, total);
	const Vec3 unreacted = {moment[0] - gyroscopic[0], moment[1] - gyroscopic[1], moment[2] - gyroscopic[2]};
	const Vec3 unreacted_acceleration = heli_inertia_mul(inverse, unreacted);
	const R generalized_demand = generalized_torque - heli_dot3(b, unreacted_acceleration);
	if (omega == 0.0 && generalized_demand <= static_friction) {
		const R generalized_reaction = -generalized_demand;
		if (!is_finite(generalized_reaction)) {
			return heli_coupling_failure("zero-speed shaft reaction is nonfinite");
		}
		return {true, 0.0, unreacted_acceleration, {0.0, 0.0, 0.0}, rotor_momentum};
	}
	R effective_torque = generalized_torque;
	if (omega == 0.0) {
		effective_torque -= static_friction;
	}
	const R spin_acceleration = (effective_torque - heli_dot3(b, unreacted_acceleration)) / (spin_inertia * denominator);
	if (!is_finite(spin_acceleration)) {
		return heli_coupling_failure("geared spin acceleration is nonfinite");
	}
	const Vec3 reaction = {b[0] * -spin_acceleration, b[1] * -spin_acceleration, b[2] * -spin_acceleration};
	const Vec3 body_acceleration = {unreacted_acceleration[0] - inverse_b[0] * spin_acceleration,
		unreacted_acceleration[1] - inverse_b[1] * spin_acceleration,
		unreacted_acceleration[2] - inverse_b[2] * spin_acceleration};
	if (!heli_inflow_finite({reaction[0], reaction[1], reaction[2], body_acceleration[0], body_acceleration[1],
			body_acceleration[2], total[0], total[1], total[2]})) {
		return heli_coupling_failure("geared coupling produced a nonfinite result");
	}
	return {true, spin_acceleration, body_acceleration, reaction, rotor_momentum};
}

struct HeliStageModel {
	HeliAeroModel aero;
	HeliTrainerModel controls;
	HeliDriveModel drive;
	HeliSkidModel skids;
	SurfaceTable surfaces;
	R mass_kg = 0.0, gravity_m_s2 = 0.0, spin_inertia = 0.0;
	std::array<R, 6> inertia{}, inertia_inverse{};
	Vec3 coupling_b{};
};

struct HeliTickContext {
	std::array<R, 4> inputs{}; // roll, pitch, yaw, collective in the session's convention
	bool idle_up = false, trainer = true, hold = false, armed = false, ground_start = false;
	R spool_start_s = 0.0;
	HeliTrim trim;
};

struct HeliStageResult {
	bool ok = false;
	// If nonempty, the owner records the corresponding Flight.evaluate failure as session _stage_failure.
	const char *message = "";
	std::array<R, 6> loads{};
	std::array<R, 13> body_derivative{};
	std::array<R, 14> derivative{};
	int derivative_size = 0;
	Vec3 rotor_momentum{};
};

inline HeliStageResult heli_stage_failure(const char *message) {
	HeliStageResult result;
	result.message = message;
	return result;
}

// wind_ned must be sampled for this exact RK stage time by the caller, not frozen for the tick.
inline HeliStageResult heli_stage(const R *body, const R *continuous, int continuous_size, R time,
		const HeliStageModel &m, const HeliTickContext &tick, const Vec3 &wind_ned) {
	if (continuous_size != 6 && continuous_size != 14) {
		return heli_stage_failure("invalid helicopter evaluation arguments");
	}
	std::array<R, 19> state{};
	for (int i = 0; i < 13; ++i) state[i] = body[i];
	for (int i = 0; i < 6; ++i) state[13 + i] = continuous[i];
	std::array<R, 8> memory{};
	if (continuous_size == 14) {
		for (int i = 0; i < 8; ++i) memory[i] = continuous[6 + i];
	}
	const HeliSkidResult contact = heli_skids(body, m.skids, m.surfaces, continuous_size == 14 ? &memory : nullptr);
	if (!contact.ok) {
		return {};
	}
	const std::array<R, 4> sticks = {-tick.inputs[1], tick.inputs[0], tick.inputs[2], 2.0 * tick.inputs[3] - 1.0};
	const R drive_scale = !tick.armed || tick.hold ? R(0.0)
		: clampf((time - tick.spool_start_s) / 12.0, 0.0, 1.0);
	const R actual_drive_scale = !tick.armed || tick.hold ? R(0.0) : drive_scale * drive_scale * (3.0 - 2.0 * drive_scale);
	if (!is_finite(actual_drive_scale) || actual_drive_scale < 0.0 || actual_drive_scale > 1.0) {
		return heli_stage_failure("invalid helicopter evaluation arguments");
	}
	for (const R value : state) {
		if (!is_finite(value)) return heli_stage_failure("helicopter stage state is nonfinite");
	}
	for (const R value : wind_ned) {
		if (!is_finite(value)) return heli_stage_failure("wind state is nonfinite");
	}
	if (state[13] < 0.0) return heli_stage_failure("main rotor crossed zero speed; locate the stop event");
	// Session height-over-radius uses math3d.q_normalized, whose norm starts with the scalar quaternion term.
	const R hub_qnorm = sqrt_(state[6] * state[6] + state[7] * state[7] + state[8] * state[8] + state[9] * state[9]);
	const R hub_q[4] = {state[6] / hub_qnorm, state[7] / hub_qnorm, state[8] / hub_qnorm, state[9] / hub_qnorm};
	const Vec3 hub = {m.aero.main.hub_x_m, m.aero.main.hub_y_m, m.aero.main.hub_z_m};
	const Vec3 hub_offset = q_rotate3(hub_q, hub.data());
	static const LakeTerrain no_lake;
	const Vec3 ground = terrain_sample_validated(state[0] + hub_offset[0], state[1] + hub_offset[1], m.surfaces, no_lake);
	const R height = (-state[2] - hub_offset[2] - ground[0]) / m.aero.main.rotor_radius_m;
	if (!is_nan(height) && !is_finite(height)) return heli_stage_failure("invalid helicopter evaluation arguments");
	if (!is_nan(height) && height < 0.0 && height != -1.0) {
		return heli_stage_failure("main-rotor hub is below the ground-effect plane");
	}
	// Flight.evaluate normalizes attitude using dot(xyz,xyz) + w*w, not q_normalized's order.
	const R qnorm2 = (state[7] * state[7] + state[8] * state[8] + state[9] * state[9]) + state[6] * state[6];
	if (!is_finite(qnorm2) || qnorm2 <= 1.0e-24) return heli_stage_failure("helicopter stage attitude quaternion is degenerate");
	const R qnorm = sqrt_(qnorm2);
	if (!is_finite(qnorm) || qnorm <= 1.0e-12) return heli_stage_failure("helicopter stage attitude quaternion is degenerate");
	const R attitude[4] = {state[6] / qnorm, state[7] / qnorm, state[8] / qnorm, state[9] / qnorm};
	const HeliControlResult control = heli_trainer_electronics(m.controls, state.data(), sticks, tick.idle_up, tick.trainer, tick.trim);
	if (!control.ok) return heli_stage_failure(control.message);
	const Vec3 velocity_body = {state[3], state[4], state[5]};
	const Vec3 velocity_ned = q_rotate3(attitude, velocity_body.data());
	const Vec3 relative_ned = {velocity_ned[0] - wind_ned[0], velocity_ned[1] - wind_ned[1], velocity_ned[2] - wind_ned[2]};
	const R attitude_inverse[4] = {attitude[0], -attitude[1], -attitude[2], -attitude[3]};
	const Vec3 air = q_rotate3(attitude_inverse, relative_ned.data());
	const Vec3 rates = {state[10], state[11], state[12]};
	if (state[13] != 0.0) {
		const R tip = state[13] * m.aero.main.rotor_radius_m;
		if (!is_finite(tip) || tip <= 0.0) return heli_stage_failure("main-rotor advance ratio exceeds the kernel domain at this speed");
		const Vec3 rate_offset = cross3(rates, hub);
		const Vec3 hub_air = {air[0] + rate_offset[0], air[1] + rate_offset[1], air[2] + rate_offset[2]};
		const R crossflow = sqrt_(hub_air[0] * hub_air[0] + hub_air[1] * hub_air[1]);
		const std::array<R, 2> transition = heli_main_low_rpm_transition(m.aero.main, crossflow);
		if (!(state[13] <= transition[0])) {
			const R mu_x = hub_air[0] / tip;
			const R mu_y = hub_air[1] / tip;
			const R mu2 = mu_x * mu_x + mu_y * mu_y;
			if (!is_finite(mu2) || mu2 >= 2.0) return heli_stage_failure("main-rotor advance ratio exceeds the kernel domain at this speed");
		}
	}
	const std::array<R, 3> rotor_state = {state[14], state[15], state[16]};
	Vec3 thrust_axis = {-sin_(state[14]), sin_(state[15]), -cos_(state[14]) * cos_(state[15])};
	const R inverse_axis_length = 1.0 / sqrt_(heli_dot3(thrust_axis, thrust_axis));
	for (R &value : thrust_axis) value *= inverse_axis_length;
	const R down_axis = q_rotate3(attitude, thrust_axis.data())[2];
	const HeliAeroResult aero = heli_aero_stage(m.aero, rotor_state, state[13], air, rates, control.collective,
		control.cyclic_forward, control.cyclic_right, control.tail_collective, height, down_axis);
	if (!aero.ok) return heli_stage_failure("joint aerodynamic stage refused the flight state");
	const HeliDriveResult drive = heli_drive(m.drive, state[13], control.drive_fraction, tick.hold || !tick.armed, actual_drive_scale);
	if (!drive.ok) return heli_stage_failure(drive.message);
	if (!is_finite(aero.main.torque) || !is_finite(aero.tail.torque)) {
		return heli_stage_failure("aerodynamic shaft torque is absent or nonfinite");
	}
	R generalized_torque = drive.net_torque - aero.main.torque - m.aero.tail.tail_to_main_speed_ratio * aero.tail.torque;
	if (state[13] == 0.0) generalized_torque += drive.shaft_loss;
	if (!is_finite(generalized_torque)) return heli_stage_failure("net geared torque is nonfinite");
	std::array<R, 6> loads = aero.loads;
	for (int i = 0; i < 6; ++i) loads[i] += contact.loads[i];
	const Vec3 moment = {loads[3], loads[4], loads[5]};
	const HeliCouplingResult coupling = heli_geared_coupling(rates, moment, m.inertia, m.inertia_inverse, m.coupling_b,
		m.spin_inertia, state[13], generalized_torque, m.drive.shaft_loss_torque_nm);
	if (!coupling.ok) return heli_stage_failure(coupling.message);
	// RigidBody.derivative translation and quaternion paths, in reference operation order; the geared solve
	// replaces its final three angular accelerations just as Flight.evaluate does.
	const R v0 = state[3], v1 = state[4], v2 = state[5];
	const R q0 = attitude[0], q1 = attitude[1], q2 = attitude[2], q3 = attitude[3];
	const R w0 = rates[0], w1 = rates[1], w2 = rates[2];
	const R t0 = (q2 * v2 - q3 * v1) * 2.0;
	const R t1 = (q3 * v0 - q1 * v2) * 2.0;
	const R t2 = (q1 * v1 - q2 * v0) * 2.0;
	const R pn = (v0 + t0 * q0) + (q2 * t2 - q3 * t1);
	const R pe = (v1 + t1 * q0) + (q3 * t0 - q1 * t2);
	const R pd = (v2 + t2 * q0) + (q1 * t1 - q2 * t0);
	const R n1 = -q1, n2 = -q2, n3 = -q3;
	const R g0 = (n2 * m.gravity_m_s2 - n3 * 0.0) * 2.0;
	const R g1 = (n3 * 0.0 - n1 * m.gravity_m_s2) * 2.0;
	const R g2 = (n1 * 0.0 - n2 * 0.0) * 2.0;
	const R gx = (0.0 + g0 * q0) + (n2 * g2 - n3 * g1);
	const R gy = (0.0 + g1 * q0) + (n3 * g0 - n1 * g2);
	const R gz = (m.gravity_m_s2 + g2 * q0) + (n1 * g1 - n2 * g0);
	const R k = 1.0 / m.mass_kg;
	const R ud = (loads[0] * k + gx) - (w1 * v2 - w2 * v1);
	const R vd = (loads[1] * k + gy) - (w2 * v0 - w0 * v2);
	const R wd = (loads[2] * k + gz) - (w0 * v1 - w1 * v0);
	const R qd0 = (q0 * 0.0 - q1 * w0 - q2 * w1 - q3 * w2) * 0.5;
	const R qd1 = (q0 * w0 + q1 * 0.0 + q2 * w2 - q3 * w1) * 0.5;
	const R qd2 = (q0 * w1 - q1 * w2 + q2 * 0.0 + q3 * w0) * 0.5;
	const R qd3 = (q0 * w2 + q1 * w1 - q2 * w0 + q3 * 0.0) * 0.5;
	HeliStageResult result;
	result.loads = loads;
	result.body_derivative = {pn, pe, pd, ud, vd, wd, qd0 * qnorm, qd1 * qnorm, qd2 * qnorm, qd3 * qnorm,
		coupling.body_acceleration[0], coupling.body_acceleration[1], coupling.body_acceleration[2]};
	result.derivative[0] = coupling.spin_acceleration;
	result.derivative[1] = aero.derivative[0];
	result.derivative[2] = aero.derivative[1];
	result.derivative[3] = aero.derivative[2];
	result.derivative[4] = control.controller_derivative[0];
	result.derivative[5] = tick.ground_start && contact.max_depth > 0.0 ? R(0.0) : control.controller_derivative[1];
	if (continuous_size == 14) {
		for (int i = 0; i < 8; ++i) result.derivative[6 + i] = contact.bristle_derivative[i];
	}
	result.derivative_size = continuous_size;
	result.rotor_momentum = coupling.rotor_momentum;
	for (const R value : result.loads) if (!is_finite(value)) return heli_stage_failure("helicopter equations produced a nonfinite derivative or load");
	for (const R value : result.body_derivative) if (!is_finite(value)) return heli_stage_failure("helicopter equations produced a nonfinite derivative or load");
	for (int i = 0; i < result.derivative_size; ++i) if (!is_finite(result.derivative[i])) return heli_stage_failure("helicopter equations produced a nonfinite derivative or load");
	result.ok = true;
	return result;
}

} // namespace nk
