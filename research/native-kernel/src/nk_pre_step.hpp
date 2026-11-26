// NK-5g: FlightSession._pre_step (app/sim/flight_session.gd) for the prepared fixed-wing stage: the next tick's aux
// from the committed state, the incoming aux and the inputs. Each piece mirrors its reference in operation order:
// Flaps.advance and the manual elevator mix, Propulsion.rpm_step (or the shaft/turbine-continuous passthrough),
// ControlActuators.rate_limit, ground_wheels.gd anchor_step over the stage's frame and coefficients, the downwash lag
// from air_data/_ground_up/Aero.wing_wake_velocity as the stage evaluates them, _gear_weight_on_wheels with
// RetractableGear.advance, and WindTurbulence.step. The engine's math (exp, log, sin, cos) is supplied by the
// binding, so those results are the engine's own on every platform; WindTurbulence's RandomNumberGenerator is Godot's
// RandomPCG reproduced in integers (PreStepPcg32). Constants whose GDScript spelling the engine might parse
// differently from C++ (the weight-on-wheels threshold, the open uniform's bound and denominator) come from the
// engine-parsed GDScript values in the preparation config.
// Any reference [NAN] result, any branch that is not here, and any doubt refuse: the caller evaluates the reference.
#pragma once

#include <array>
#include <cstdint>
#include <vector>

#include "nk_stage.hpp"

namespace nk {

struct PreStepModel {
	bool ready = false;
	R servo_rate = 0.0;
	// shaft_is_coupled() or turbine_is_continuous(): the continuous endpoint owns RPM (aux passthrough).
	bool rpm_passthrough = false;
	// A running turbine (Turbine.spool_step) or shaft model (Propulsion.shaft_step) is not native.
	bool rpm_turbine = false, rpm_shaft = false;
	// Propulsion.rpm_step: idle, maximum and lag of the throttle first-order lag.
	bool rpm_lag_ready = false;
	R idle_rpm = 0.0, max_rpm = 0.0, rpm_lag = 0.0;
	bool flaps = false;
	R flap_extension_time = 1.5, flap_retraction_time = 1.5, flap_elevator_mix = 0.0;
	int flap_aux = -1, flap_input = -1;
	bool retractable = false;
	int input_count = 0;
	bool lake_present = false; // a non-empty lake selects ground_wheels.gd anchor_step like wheels do
	R weight_on_wheels_threshold = 0.0; // _gear_weight_on_wheels' `1.0e-5`, as the engine parsed it
	R downwash_length = 0.0;
	bool turbulence = false;
	int turbulence_index = -1;
	std::array<R, 3> turbulence_sigma{};
	R turbulence_tau = 0.0;
	int64_t turbulence_seed = 0;
	// WindTurbulence.UINT53_DENOMINATOR and MAX_OPEN_UNIFORM as the engine parsed them. The pinned x86 parser reads
	// MAX_OPEN_UNIFORM's spelling 0.9999999999999999 as 1.0, one ulp above the C++ literal.
	R turbulence_uniform_denominator = 0.0, turbulence_max_uniform = 0.0;
};

struct PreStepEngine {
	double (*exp)(double) = nullptr;
	double (*log)(double) = nullptr;
	double (*sin)(double) = nullptr;
	double (*cos)(double) = nullptr;
};

// Godot's RandomPCG (thirdparty/misc/pcg.cpp) as WindTurbulence._new_rng drives it: a new RandomNumberGenerator,
// `seed` (pcg32_srandom_r on the default stream: it only fixes the increment, since the state is then replaced), the
// raw `state`, randi() = pcg32_random_r, and `state` read back as the raw 64-bit state.
constexpr uint64_t kPcgDefaultInc = 1442695040888963407ULL; // PCG_DEFAULT_INC_64 = RandomPCG::DEFAULT_INC

struct PreStepPcg32 {
	uint64_t state = 0;
	uint64_t inc = (kPcgDefaultInc << 1u) | 1u;
	explicit PreStepPcg32(int64_t raw_state) : state(static_cast<uint64_t>(raw_state)) {}
	int64_t randi() {
		const uint64_t old = state;
		state = old * 6364136223846793005ULL + (inc | 1u);
		const uint32_t xorshifted = static_cast<uint32_t>(((old >> 18u) ^ old) >> 27u);
		const uint32_t rot = static_cast<uint32_t>(old >> 59u);
		return static_cast<int64_t>((xorshifted >> rot) | (xorshifted << ((0u - rot) & 31u)));
	}
	int64_t raw_state() const { return static_cast<int64_t>(state); }
};

struct PreStepInput {
	const double *aux = nullptr;
	int aux_size = 0;
	const double *inputs = nullptr;
	int input_size = 0;
	R dt = 0.0;
	const double *state = nullptr; // sim.state, committed
	int state_size = 0;
	const double *continuous = nullptr; // sim.continuous (wheel rim speeds)
	int continuous_size = 0;
	R time_now = 0.0; // sim.time()
	bool engine_running = false;
	bool flap_mix_simulator = false; // _flap_mix_owner == "simulator"
	bool has_deflections = false;
	Deflections deflections; // _deflections(aux)
	int64_t rng_state = 0; // sim.modes[1]
};

struct PreStepScratch {
	PreparedGear posed;
	std::vector<R> aux;
	std::vector<R> compressions;
	std::vector<R> ge;
	std::vector<double> anchors;
};

// Simulation.state_is_valid.
inline bool pre_step_state_valid(const R *s) {
	for (int i = 0; i < 13; ++i) {
		if (!is_finite(s[i])) return false;
	}
	const R norm_sq = s[6] * s[6] + s[7] * s[7] + s[8] * s[8] + s[9] * s[9];
	return is_finite(norm_sq) && norm_sq.v > kGd1eMinus24; // Simulation.MIN_QUATERNION_NORM_SQ (GDScript 1e-24)
}

// Godot Math::move_toward: abs(to - from) <= delta ? to : from + SIGN(to - from) * delta.
inline R pre_step_move_toward(R from, R to, R delta) {
	const R difference = to - from;
	if (absf(difference).v <= delta.v) return to;
	const R sign = difference.v == 0.0 ? R(0.0) : (difference.v < 0.0 ? R(-1.0) : R(1.0));
	return from + sign * delta;
}

// Flaps.advance.
inline R pre_step_flaps_advance(R value, R target, R dt, const PreStepModel &p) {
	const R current = is_finite(value) ? clampf(value, 0.0, 1.0) : R(0.0);
	const R requested = is_finite(target) ? clampf(target, 0.0, 1.0) : current;
	if (!is_finite(dt) || dt.v <= 0.0 || current.v == requested.v) return current;
	const R travel = requested.v > current.v ? p.flap_extension_time : p.flap_retraction_time;
	if (!is_finite(travel) || travel.v <= 0.0) return current;
	return pre_step_move_toward(current, requested, dt / travel);
}

// ControlActuators.rate_limit.
inline R pre_step_rate_limit(R value, R target, R rate, R dt) {
	const R max_step = rate * dt;
	return value + clampf(target - value, -max_step, max_step);
}

// WindTurbulence._uniform_open.
inline R pre_step_uniform_open(PreStepPcg32 &rng, const PreStepModel &p) {
	const int64_t high_bits = rng.randi() >> 5;
	const int64_t low_bits = rng.randi() >> 6;
	const int64_t mantissa = high_bits * 67108864 + low_bits;
	const R value = (R(static_cast<double>(mantissa)) + 0.5) / p.turbulence_uniform_denominator;
	return minf(value, p.turbulence_max_uniform);
}

// WindTurbulence.step: an exact OU update, or false where the reference fails.
inline bool pre_step_turbulence(const PreStepModel &p, const R *previous, R dt, int64_t rng_state,
		const PreStepEngine &engine, std::array<R, 3> &values, int64_t &next_state) {
	for (int i = 0; i < 3; ++i) {
		if (!is_finite(previous[i])) return false;
	}
	if (!is_finite(dt) || dt.v <= 0.0) return false;
	PreStepPcg32 rng(rng_state);
	// _active_normals: only as many normal pairs as there are nonzero sigma components.
	std::array<R, 3> normals{0.0, 0.0, 0.0};
	std::array<R, 2> pair{0.0, 0.0};
	int pair_index = 2;
	for (int axis = 0; axis < 3; ++axis) {
		if (p.turbulence_sigma[axis].v == 0.0) continue;
		if (pair_index >= 2) {
			const R u1 = pre_step_uniform_open(rng, p);
			const R u2 = pre_step_uniform_open(rng, p);
			const R radius = sqrt_(R(-2.0) * R(engine.log(u1.v)));
			const R angle = R(kTauConstant) * u2;
			pair = {radius * R(engine.cos(angle.v)), radius * R(engine.sin(angle.v))};
			pair_index = 0;
		}
		normals[axis] = pair[pair_index];
		pair_index += 1;
	}
	const R a = engine.exp(((-dt) / p.turbulence_tau).v);
	const R gain = sqrt_(maxf(R(0.0), R(1.0) - a * a));
	for (int i = 0; i < 3; ++i) {
		values[i] = a * previous[i] + p.turbulence_sigma[i] * gain * normals[i];
		if (!is_finite(values[i])) return false;
	}
	next_state = rng.raw_state();
	return true;
}

// FlightSession.air_data(s) at sim.time() with the incoming aux: the stage's own datum or spatial air.
inline bool pre_step_air(const R *s, R at, const std::vector<R> &aux, const StageModel &m, Air &air) {
	std::array<R, 3> wind{0.0, 0.0, 0.0};
	if (m.has_weather) {
		wind = weather_wind(m.weather, s, at, aux, m.layout.turbulence, m.dt);
	} else if (!is_finite(s[0]) || !is_finite(s[1]) || !is_finite(s[2]) || !is_finite(at) || at.v < 0.0) {
		wind = {kNan, kNan, kNan};
	}
	const WeatherAir atmosphere = weather_air(m.weather, s[2]);
	const R rho = m.has_weather ? atmosphere.density : m.density;
	air = air_compute(s, wind.data(), rho);
	if (m.spatial_weather) {
		StageWindContext wind_context{&m, nullptr, &aux};
		const SpatialWindProvider provider{stage_wind_sample, &wind_context};
		SpatialPointContext point_context;
		const SpatialFlowResult flow = spatial_flow_sample(s, m.aero, m.prop.offset, provider, at, rho, point_context);
		if (!flow.ok) return false; // the reference's NaN air: let it evaluate
		air = flow.air;
	}
	return true;
}

// The next aux (`out`) and sim.modes[1] (`rng_state`) exactly as FlightSession._pre_step returns them; false refuses.
inline bool pre_step(const StageModel &m, const PreStepModel &p, const PreStepInput &in, const PreStepEngine &engine,
		PreStepScratch &scratch, std::vector<double> &out, int64_t &rng_state) {
	out.clear();
	rng_state = in.rng_state;
	const StageLayout &L = m.layout;
	if (!p.ready || in.aux == nullptr || in.inputs == nullptr || in.state == nullptr || in.state_size != 13 ||
			in.aux_size != L.aux_size || in.input_size != p.input_count || in.input_size < 4 ||
			L.rpm != 0 || L.servo != 1 || L.anchors != 4) {
		return false;
	}
	const double *aux = in.aux;
	const double *inputs = in.inputs;
	const R dt = in.dt;
	// Input and layout checks, in the reference's order; each [NAN] result refuses.
	if (p.retractable) {
		const int g = L.gear_aux;
		if (g < 0 || in.aux_size < g + 2 || !retractable_valid_fraction(aux[g]) || (aux[g + 1] != 0.0 && aux[g + 1] != 1.0) ||
				in.input_size < 6 || (inputs[4] != 0.0 && inputs[4] != 1.0) || !retractable_valid_fraction(inputs[5])) {
			return false;
		}
	} else if (L.brake_input >= 0) {
		if (L.brake_input >= in.input_size || !retractable_valid_fraction(inputs[L.brake_input])) return false;
	}
	if (p.flaps) {
		if (p.flap_aux < 0 || p.flap_aux >= in.aux_size || !retractable_valid_fraction(aux[p.flap_aux]) ||
				p.flap_input < 0 || p.flap_input >= in.input_size || !retractable_valid_fraction(inputs[p.flap_input])) {
			return false;
		}
	}
	R demand[4] = {inputs[0], inputs[1], inputs[2], inputs[3]};
	R next_flap = 0.0;
	if (p.flaps) {
		next_flap = pre_step_flaps_advance(aux[p.flap_aux], inputs[p.flap_input], dt, p);
		// Manual down-elevator mix follows slowed flap travel, before the physical servos.
		if (in.flap_mix_simulator) {
			if (!is_finite(p.flap_elevator_mix)) return false; // no authored mix fraction: the reference decides
			demand[1] = clampf(demand[1] - next_flap * p.flap_elevator_mix, -1.0, 1.0);
		}
	}
	R rpm = 0.0;
	if (p.rpm_passthrough) {
		rpm = aux[L.rpm];
	} else if (in.engine_running && (p.rpm_turbine || p.rpm_shaft)) {
		return false;
	} else if (in.engine_running) {
		if (!p.rpm_lag_ready) return false;
		// Propulsion.rpm_step(rpm, throttle, dt, prop): target + (rpm - target) * exp(-dt / lag).
		const R target = p.idle_rpm + clampf(demand[3], 0.0, 1.0) * (p.max_rpm - p.idle_rpm);
		rpm = target + (R(aux[L.rpm]) - target) * R(engine.exp(((-dt) / p.rpm_lag).v));
	}
	out.reserve(static_cast<size_t>(in.aux_size));
	out.push_back(rpm.v);
	for (int k = 0; k < 3; ++k) {
		out.push_back(pre_step_rate_limit(aux[L.servo + k], demand[k], p.servo_rate, dt).v);
	}
	R state[13];
	for (int i = 0; i < 13; ++i) state[i] = in.state[i];
	const int anchors_end = L.anchors + L.anchor_count * 3;
	if (anchors_end > L.anchors) {
		// Ground.anchor_step(enhanced = wheel_count() > 0): ground_wheels.gd anchor_step with wheels or a lake.
		if (L.wheel_count <= 0 && !p.lake_present) return false;
		if (!m.ground.lake_valid || !m.ground.surfaces.valid || anchors_end > in.aux_size) return false;
		// current_landing_gear(aux): the retractable pose of the incoming extension.
		const PreparedGear *gear = &m.ground.gear;
		if (p.retractable) {
			if (!retractable_pose(m.ground.gear, m.retraction, aux[L.gear_aux], scratch.posed)) return false;
			gear = &scratch.posed;
		}
		const int anchor_values = anchors_end - L.anchors;
		const double *anchors = aux + L.anchors;
		scratch.anchors.assign(static_cast<size_t>(anchor_values), 0.0);
		const int contacts = static_cast<int>(gear->contacts.size());
		// sim.continuous.slice(wheel_index(), wheel_index() + wheel_count()), or no speeds without wheels.
		const double *speeds = nullptr;
		int speed_count = 0;
		if (L.wheel_count > 0) {
			const int begin = std::min(std::max(L.wheel_index, 0), in.continuous_size);
			const int end = std::min(std::max(L.wheel_index + L.wheel_count, begin), in.continuous_size);
			speeds = in.continuous + begin;
			speed_count = end - begin;
		}
		if (!gear->empty && anchor_values == contacts * 3 &&
				!((-state[2]).v > (gear->reach + max_height_validated(m.ground.surfaces) + R(0.0)).v)) {
			const R steer = aux[L.servo + 2];
			const Rotation rotation = wheel_rotation(state);
			for (int i = 0; i < contacts; ++i) {
				const WheelContact &c = gear->contacts[static_cast<size_t>(i)];
				const WheelFrame f = wheel_frame(state, c, steer, m.ground, rotation);
				R mu = 0.0, rolling = 0.0, index = 0.0;
				wheel_coefficients(*gear, c, m.ground.surfaces.values, f.position, mu, rolling, index);
				const R n = f.normal_load;
				if (n.v <= 0.0 || mu.v <= 0.0 || !f.valid_heading) continue;
				// A stopped axle with a spinning tire is sliding, not a static contact.
				if (L.wheel_count > 0 && speed_count > 0 && (speed_count != contacts || !is_finite(R(speeds[i])) ||
						absf(f.long_speed - speeds[i]).v >= kStickSpeed)) {
					continue;
				}
				const int at = i * 3;
				if (anchors[at + 2] == 1.0) {
					const Vec3 displacement = {f.position[0] - anchors[at], f.position[1] - anchors[at + 1], 0.0};
					const R long_force = -c.anchor_stiffness * dot3(displacement, f.heading);
					const R side_force = -c.anchor_stiffness * dot3(displacement, f.side);
					const R limit = mu * n;
					if (absf(long_force).v <= (gear->breakaway_factor * rolling * n).v && absf(side_force).v <= limit.v &&
							(long_force * long_force + side_force * side_force).v <= (limit * limit).v) {
						scratch.anchors[static_cast<size_t>(at)] = anchors[at];
						scratch.anchors[static_cast<size_t>(at + 1)] = anchors[at + 1];
						scratch.anchors[static_cast<size_t>(at + 2)] = 1.0;
					}
				} else if (sqrt_(f.long_speed * f.long_speed + f.side_speed * f.side_speed).v < kStickSpeed) {
					scratch.anchors[static_cast<size_t>(at)] = f.position[0].v;
					scratch.anchors[static_cast<size_t>(at + 1)] = f.position[1].v;
					scratch.anchors[static_cast<size_t>(at + 2)] = 1.0;
				}
			}
		}
		out.insert(out.end(), scratch.anchors.begin(), scratch.anchors.end());
	}
	const int lag = L.downwash;
	if (lag >= 0 && lag < in.aux_size) {
		// E0a2b: the tail's downwash follows the wing's lift late; exact first-order lag over the tick.
		if (!in.has_deflections || !is_finite(p.downwash_length)) return false;
		scratch.aux.assign(aux, aux + in.aux_size);
		Air air;
		if (!pre_step_air(state, in.time_now, scratch.aux, m, air)) return false;
		const R ground_up = stage_ground_up(state, m);
		ge_factors(state, m.aero, ground_up, scratch.ge);
		const R cl_now = wing_lift_coefficient_with(state, air, in.deflections, m.aero, scratch.ge, true);
		if (is_nan(cl_now)) return false; // the reference evaluates Aero.wing_wake_velocity
		const R speed = air.V;
		out.push_back((cl_now + (R(aux[lag]) - cl_now) * R(engine.exp(((-dt) * speed / p.downwash_length).v))).v);
	}
	if (p.retractable) {
		const int g = L.gear_aux;
		R target = inputs[4];
		// _gear_weight_on_wheels(aux): fully down, a valid state, and a compressed authored-gear contact.
		if (target.v == 0.0 && aux[g] == 1.0 && pre_step_state_valid(state)) {
			wheels_compressions(state, m.ground, scratch.compressions);
			for (const R &value : scratch.compressions) {
				if (value.v > p.weight_on_wheels_threshold.v) {
					target = 1.0;
					break;
				}
			}
		}
		const R extension = retractable_advance(aux[g], target, dt, m.retraction);
		if (!is_finite(extension)) return false;
		out.push_back(extension.v);
		out.push_back(target.v);
	}
	if (p.flaps) out.push_back(next_flap.v);
	if (p.turbulence) {
		const int t = p.turbulence_index;
		if (t < 0 || static_cast<int>(out.size()) != t || in.aux_size < t + 7) return false;
		const R previous[3] = {aux[t + 3], aux[t + 4], aux[t + 5]};
		std::array<R, 3> values{};
		if (!pre_step_turbulence(p, previous, dt, in.rng_state, engine, values, rng_state)) return false;
		out.insert(out.end(), {aux[t + 3], aux[t + 4], aux[t + 5], values[0].v, values[1].v, values[2].v, in.time_now.v});
	}
	if (static_cast<int>(out.size()) != in.aux_size) return false;
	for (double value : out) {
		if (!std::isfinite(value)) return false; // the reference returns it and the kernel rejects the tick
	}
	return true;
}

} // namespace nk
