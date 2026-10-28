// NK-3: one joint RK stage for the fixed-wing "wheel" route, mirroring FlightSession._wheel_evaluate for an aircraft
// without wash pieces (rotor index 0): air_data (calm, non-spatial weather), Dynamics.loads_from_air (aero +
// untilted legacy propeller, no slipstream), _ground_up, _ground_evaluation (soft hull + GP-02 wheels, fixed gear,
// no glow/live mass) and rotor_momentum. The per-tick context (aux after pre_tick, inputs, the session's own
// deflections, sim time) is set once per tick by the caller; stage() then reads only packed scalars.
#pragma once

#include <array>
#include <memory>
#include <utility>
#include <vector>

#include "nk_aero.hpp"
#include "nk_hull.hpp"
#include "nk_prop.hpp"
#include "nk_wheels.hpp"
#include "nk_weather.hpp"
#include "nk_spatial_weather.hpp"
#include "nk_wake_spatial_flow.hpp"
#include "nk_wake_spatial_aero.hpp"
#include "nk_electric_stage.hpp"
#include "nk_electric_coupling.hpp"
#include "nk_retractable.hpp"
#include "nk_liquid_stage.hpp"
#include "nk_prescribed_stage.hpp"
#include "nk_legacy_ground.hpp"
#include "nk_glow_stage.hpp"

namespace nk {

struct StageLayout {
	int aux_size = 0;
	int rpm = 0;          // FlightSession.AUX_RPM
	int servo = 1;        // FlightSession.AUX_SERVO (steer = aux[servo + 2])
	int anchors = 4;      // FlightSession.AUX_ANCHORS
	int anchor_count = 0;
	int downwash = -1;    // downwash_index()
	int wheel_count = 0;
	int rotor_index = 0;  // _rotor_index(): continuous wash pieces before the wheels (0 here)
	int wheel_index = 0;  // wheel_index()
	int brake_input = -1; // wheel_brake_input_index()
	int input_count = 0;
	int turbulence = -1;
	int battery_size = 0;
	int gear_aux = -1;
	int liquid_index = -1;
};

struct StageModel {
	AeroModel aero;
	PropModel prop;
	GroundContext ground;
	RetractableModel retraction;
	HullPrepared hull;
	bool soft_hull = false;
	StageLayout layout;
	R density = 0.0;            // weather.air_density(): uniform field, no vertical column
	R ground_effect_reach = 0.0; // FlightSession._ground_effect_reach
	bool has_weather = false;
	WeatherModel weather;
	bool spatial_weather = false;
	SpatialWeather spatial;
	std::shared_ptr<const SpatialWeather> spatial_identity;
	WakeModel wake;
	bool electric = false;
	LiquidStageModel liquid;
	PrescribedModel prescribed;
	GlowStageModel glow;
	R gravity = 0.0;
	ElectricPreparedSource electric_source;
	std::array<R, 6> inertia{}, inverse{};
	R dt = 0.0;
};

struct TickContext {
	bool ready = false;
	std::vector<R> aux;
	R brake = 0.0;
	Deflections deflections;
	R time_now = 0.0;
	bool power_ready = false, power_enabled = false;
	bool injected_cut = false;
	R throttle = 0.0;
	GroundContext posed_ground;
	bool capture_preview = false;
	std::array<R, 13> preview_body{};
	std::vector<R> preview_values;
};

struct StageResult {
	bool shaped = false; // false: the reference returns {} (kernel rejects the stage)
	std::array<R, 6> loads{};
	std::vector<R> derivative;
	std::array<R, 3> rotor{};
	bool has_body_derivative = false;
	std::array<R, 13> body_derivative{};
	bool has_preview = false, preview_spatial = false;
	Air preview_air;
	R preview_time = 0.0, preview_rho = 0.0;
	SpatialFlowResult preview_flow;
	SpatialPointContext preview_point;
	std::array<R, 6> pre_reaction{};
	std::vector<R> preview_wheel_rates;
};

// A callback into immutable native weather only. Its context is local to one RK stage.
struct StageWindContext {
	const StageModel *model;
	const TickContext *tick;
};

inline bool stage_wind_sample(void *opaque, const R *position, R time, R *wind) {
	const auto &context = *static_cast<const StageWindContext *>(opaque);
	const StageModel &m = *context.model;
	const auto sample = m.spatial_weather ? spatial_weather_wind(m.spatial, position, time) :
		weather_wind(m.weather, position, time, context.tick->aux, m.layout.turbulence, m.dt);
	for (int i = 0; i < 3; ++i) wind[i] = sample[i];
	return spatial_flow_finite3(wind);
}

// FlightSession._ground_up.
inline R stage_ground_up(const R *s, const StageModel &m) {
	if (m.ground_effect_reach.v <= 0.0) {
		return kNan;
	}
	if ((-s[2]).v >= (m.ground_effect_reach + max_height_validated(m.ground.surfaces)).v) {
		return kNan;
	}
	static const LakeTerrain kNoLake;
	return terrain_sample_validated(s[0], s[1], m.ground.surfaces, kNoLake)[0];
}

// FlightSession._ground_evaluation for fixed gear: false = {ok: false}.
inline bool stage_ground(const R *s, const StageModel &m, const TickContext &ctx, const R *values, int value_count,
		std::array<R, 6> &loads, bool &has_loads, std::vector<R> &rates,
		const Air *air = nullptr, SpatialPointContext *point = nullptr, R rho = 0.0,
		const LiquidMassProperties *live = nullptr) {
	const StageLayout &L = m.layout;
	const GroundContext &ground = m.retraction.enabled ? ctx.posed_ground : m.ground;
	const R steer = ctx.aux[L.servo + 2];
	const R brake = ctx.brake;
	// Valid legacy gear can carry more contacts than the stock wheel profiles.
	// Reuse storage across stages; prepared layout validation bounds this copy.
	static thread_local std::vector<double> anchors;
	anchors.resize(static_cast<size_t>(L.anchor_count) * 3);
	const int anchor_values = static_cast<int>(anchors.size());
	for (int i = 0; i < anchor_values; ++i) anchors[static_cast<size_t>(i)] = ctx.aux[L.anchors + i].v;
	std::array<R, 6> hull{};
	bool has_hull = false;
	if (m.soft_hull) {
		if (live != nullptr) {
			if (!m.hull.present) return false;
			// FlightSession avoids live contact evaluation entirely above geometry reach.
			if (-s[2] <= m.hull.reach) {
				const auto sampled = hull_loads_at_properties(s, m.hull, *live);
				if (!sampled.ok) return false;
				has_hull = sampled.touched;
				hull = sampled.loads;
			}
		} else {
			has_hull = hull_loads(s, m.hull, hull);
		}
		if (has_hull) {
			for (const R &value : hull) {
				if (!is_finite(value)) {
					return false;
				}
			}
		}
	}
	if (m.retraction.enabled) {
		if (air == nullptr || L.gear_aux < 0) return false;
		const R extension = ctx.aux[L.gear_aux];
		R delta[3];
		const R *delta_ptr = nullptr;
		if (point != nullptr && extension > 0.0) {
			if (!spatial_point_delta(point, m.retraction.drag_center.data(), delta)) return false;
			delta_ptr = delta;
		}
		const auto drag = retractable_drag(s, air->v, m.retraction, extension, rho, delta_ptr, delta_ptr ? 3 : 0);
		if (!drag.empty()) {
			if (drag.size() != 6) return false;
			for (int i = 0; i < 6; ++i) {
				if (!is_finite(drag[i])) return false;
				hull[i] = has_hull ? hull[i] + drag[i] : drag[i];
			}
			has_hull = true;
		}
	}
	if (L.wheel_count == 0) {
		if (value_count != L.wheel_index) return false;
		std::vector<R> legacy;
		if (!legacy_ground_loads(s, ground, steer, anchors.data(), anchor_values, legacy) ||
				(!legacy.empty() && legacy.size() != 6)) return false;
		has_loads = !legacy.empty() || has_hull;
		for (int i = 0; i < 6 && has_loads; ++i) {
			loads[i] = legacy.empty() ? hull[i] : (has_hull ? legacy[i] + hull[i] : legacy[i]);
		}
		rates.clear();
		return true;
	}
	if (value_count != L.wheel_index + L.wheel_count) {
		return false;
	}
	double speeds[16];
	for (int i = 0; i < L.wheel_count; ++i) {
		speeds[i] = values[L.wheel_index + i].v;
		if (!std::isfinite(speeds[i])) {
			return false;
		}
	}
	static thread_local std::vector<R> wheel_loads;
	wheels_evaluate(s, ground, steer, anchors.data(), anchor_values, speeds, L.wheel_count, brake, wheel_loads, rates);
	if ((!wheel_loads.empty() && wheel_loads.size() != 6) || static_cast<int>(rates.size()) != L.wheel_count) {
		return false;
	}
	for (const R &value : wheel_loads) {
		if (!is_finite(value)) {
			return false;
		}
	}
	for (const R &value : rates) {
		if (!is_finite(value)) {
			return false;
		}
	}
	// _add_loads(wheels, hull)
	if (!has_hull) {
		has_loads = !wheel_loads.empty();
		for (int i = 0; i < 6 && has_loads; ++i) {
			loads[i] = wheel_loads[i];
		}
	} else if (wheel_loads.empty()) {
		has_loads = true;
		loads = hull;
	} else {
		has_loads = true;
		for (int i = 0; i < 6; ++i) {
			loads[i] = wheel_loads[i] + hull[i];
		}
	}
	return true;
}

// FlightSession._wheel_evaluate.
inline StageResult stage_evaluate(const R *s, const R *values, int value_count, R stage_time, const StageModel &m,
		const TickContext &ctx, GlowStageRejection *rejection = nullptr) {
	if (rejection != nullptr) rejection->code = GlowRejectionCode::None;
	StageResult out;
	const StageLayout &L = m.layout;
	const int expected = L.rotor_index;
	if (value_count != L.wheel_index + L.wheel_count + (m.liquid.ready ? 2 : 0) || !ctx.ready ||
			((m.electric || m.liquid.ready || m.glow.ready || m.prescribed.ready()) && !ctx.power_ready)) {
		return out;
	}
	const LiquidStageLayout liquid_layout{L.rotor_index, L.wheel_index, L.wheel_count};
	const auto liquid_trial = m.liquid.ready ? liquid_trial_properties(m.liquid, liquid_layout, values, value_count, ctx.power_enabled) : LiquidStageTrial{};
	if (m.liquid.ready && !liquid_trial.ok) return out;
	const bool turbine = (m.liquid.ready && !m.liquid.gas) || m.prescribed.is_turbine();
	const bool prescribed_joint = m.prescribed.coupled() || m.prescribed.continuous_turbine();
	const LiquidTurbine &turbine_model = m.liquid.ready ? m.liquid.turbine : m.prescribed.turbine;
	const std::vector<R> &a = ctx.aux;
	const R trial_rpm = (m.electric || m.liquid.ready || m.glow.ready || prescribed_joint) ? values[L.rotor_index] : a[L.rpm];
	if (m.electric && !is_finite(trial_rpm)) return out;
	const R rpm = (m.electric || m.glow.ready) ? maxf(0.0, trial_rpm) : trial_rpm;
	const int lag = L.downwash;
	const R downwash_cl = lag >= 0 && lag < static_cast<int>(a.size()) ? a[lag] : R(kNan);
	// Each trial pose/time samples its own atmosphere and point flow; no sampled endpoint reuse.
	const R at = is_nan(stage_time) ? ctx.time_now : stage_time;
	std::array<R, 3> wind{0.0, 0.0, 0.0};
	if (m.has_weather) {
		wind = weather_wind(m.weather, s, at, ctx.aux, L.turbulence, m.dt);
	} else if (!is_finite(s[0]) || !is_finite(s[1]) || !is_finite(s[2]) || !is_finite(at) || at.v < 0.0) {
		wind = {kNan, kNan, kNan};
	}
	const WeatherAir atmosphere = weather_air(m.weather, s[2]);
	const R rho = m.has_weather ? atmosphere.density : m.density;
	Air air = air_compute(s, wind.data(), rho);
	StageWindContext wind_context{&m, &ctx};
	SpatialPointContext point_context;
	SpatialFlowResult spatial_flow;
	if (m.spatial_weather) {
		const SpatialWindProvider provider{stage_wind_sample, &wind_context};
		spatial_flow = spatial_flow_sample(s, m.aero, m.prop.offset, provider, at, rho, point_context);
		if (spatial_flow.ok) {
			air = spatial_flow.air;
		} else {
			// FlightSession.air_data's rejected point field becomes invalid datum air, not calm flow.
			const R invalid_wind[3] = {kNan, kNan, kNan};
			air = air_compute(s, invalid_wind, rho);
		}
	}
	const R ground_up = stage_ground_up(s, m);
	// Dynamics.loads_from_air: Aero.loads, then the propeller at its stage inflow.
	Loads aero;
	bool aero_valid = true;
	if (m.spatial_weather && spatial_flow.ok) {
		const auto evaluated = spatial_aero_loads(s, air, ctx.deflections, m.aero, rho, spatial_flow.aero_deltas.data(),
			spatial_flow.aero_deltas.size(), downwash_cl, ground_up, true);
		aero_valid = evaluated.ok;
		aero = evaluated.loads;
	} else {
		aero = aero_loads(s, air, ctx.deflections, m.aero, rho, downwash_cl, ground_up);
	}
	std::array<R, 6> total;
	const R *explicit_air = m.spatial_weather && spatial_flow.ok ? spatial_flow.propulsion_air.data() : nullptr;
	const PropAir prop_air = turbine ? liquid_turbine_stage_air_velocity(s, air.v, turbine_model, explicit_air) :
		prop_stage_air_velocity(s, air.v, m.prop, m.electric || m.glow.ready, explicit_air);
	if ((m.electric || m.liquid.ready || m.glow.ready || prescribed_joint) && !prop_air.ok) return out;
	const auto turbine_point = (m.liquid.ready && turbine) ? liquid_turbine_stage(prop_air.velocity.data(), rpm, ctx.throttle,
		m.liquid.turbine, rho, liquid_trial.running) : LiquidTurbineStage{};
	const auto prescribed_turbine = m.prescribed.is_turbine() ? prescribed_turbine_stage(prop_air.velocity.data(), rpm,
		ctx.throttle, turbine_model, rho, ctx.power_enabled, m.prescribed.continuous_turbine()) : PrescribedTurbineStage{};
	if ((m.liquid.ready && turbine && !turbine_point.ok) || (m.prescribed.is_turbine() && !prescribed_turbine.ok)) return out;
	const auto glow_trial = m.glow.ready ? glow_stage_prepare(m.glow, m.prop, s, values, value_count, L.wheel_count,
		prop_air.velocity.data(), rho, atmosphere.engine_charge_ratio,
		spatial_flow_finite3(s) ? atmosphere.temperature_k : R(kNan), ctx.power_enabled, ctx.injected_cut) : GlowStageTrial{};
	if (m.glow.ready && !glow_trial.ok) return out;
	if (!aero_valid || !prop_air.ok) {
		total = {kNan, kNan, kNan, kNan, kNan, kNan}; // Propulsion.stage_air_velocity refuses: _invalid_components
	} else {
		const auto local_tq = !turbine && !m.glow.ready && m.spatial_weather && m.wake.enabled ?
			prop_thrust_torque(prop_air.velocity.data(), rpm, m.prop, rho) : std::array<R, 3>{};
		const std::array<R, 6> propulsion = m.prescribed.is_turbine() ? prescribed_turbine.loads : turbine ? turbine_point.loads : m.glow.ready ? glow_trial.blade_loads :
			(m.spatial_weather && m.wake.enabled ? prop_loads_from_thrust_torque(prop_air.velocity.data(), rpm, m.prop, rho,
				local_tq[0], local_tq[1]) : prop_loads(prop_air.velocity.data(), rpm, m.prop, rho));
		total = aero;
		for (int i = 0; i < 6; ++i) {
			total[i] += propulsion[i];
		}
		if (m.wake.enabled) {
			// Uniform Slipstream reads datum flow unless the stage explicitly supplies local propulsion air.
			const auto tq = m.glow.ready ? std::array<R, 3>{glow_trial.blade.thrust_n, glow_trial.blade.torque_nm, 0.0} :
				prop_thrust_torque(m.spatial_weather ? prop_air.velocity.data() : air.v, rpm, m.prop, rho);
			const WakePointSampler sampler = spatial_wake_sampler(point_context);
			const auto wash = wake_loads(s, air, ctx.deflections, m.aero, m.prop, m.wake, rpm, rho,
				tq[0], tq[1], downwash_cl, expected > 0 ? values : nullptr,
				m.spatial_weather ? spatial_flow.wake_source_delta.data() : nullptr, m.spatial_weather ? &sampler : nullptr);
			for (int i = 0; i < 6; ++i) total[i] += wash[i];
		}
	}
	std::array<R, 6> ground_loads{};
	bool has_ground_loads = false;
	std::vector<R> rates;
	if (!stage_ground(s, m, ctx, values, value_count - (m.liquid.ready ? 2 : 0), ground_loads, has_ground_loads, rates, &air,
			m.spatial_weather && spatial_flow.ok ? &point_context : nullptr, rho, m.liquid.ready ? &liquid_trial.mass : (m.glow.ready ? &glow_trial.raw_mass : nullptr))) {
		return out;
	}
	if (has_ground_loads) {
		for (int i = 0; i < 6; ++i) {
			total[i] += ground_loads[i];
		}
	}
	if (m.glow.ready) {
		const auto result = glow_stage_finish(m.glow, glow_trial, m.prop, s, values, total.data(), rates.data(),
			static_cast<int>(rates.size()), ctx.throttle, m.gravity, rejection);
		if (!result.ok) return out;
		out.shaped = true;
		out.loads = result.loads;
		out.derivative = result.derivative;
		out.rotor = result.rotor;
		out.has_body_derivative = true;
		out.body_derivative = result.body_derivative;
		return out;
	}
	ElectricStagePoint source;
	ElectricCouplingResult coupling;
	if (m.electric) {
		const bool dynamic = m.electric_source.kind != ElectricBatteryKind::FixedVoltage;
		const R ambient = spatial_flow_finite3(s) ? atmosphere.temperature_k : R(kNan);
		const R cooling = m.electric_source.kind == ElectricBatteryKind::PackEcm ?
			m.electric_source.pack.cooling_airflow_fraction * sqrt_(air.v[0] * air.v[0] + air.v[1] * air.v[1] + air.v[2] * air.v[2]) : R(0.0);
		source = m.electric_source.evaluate(rpm, ctx.throttle, values + L.rotor_index + 1, L.battery_size,
			ctx.power_enabled, ambient, cooling);
		const ElectricCouplingSource drive{source.ok, source.values[0], source.values[1]};
		coupling = electric_coupled_response(s, trial_rpm, m.prop, m.electric_source.motor, m.inertia.data(), m.inverse.data(),
			prop_air.velocity.data(), rho, atmosphere.engine_charge_ratio, ctx.throttle, dynamic, drive, total.data());
		if (!coupling.ok) return out;
		total = coupling.loads;
	}
	if (expected == 0 && !m.electric && !m.liquid.ready && !prescribed_joint) {
		out.derivative = std::move(rates);
	} else if (expected > 0) {
		R source[3] = {air.v[0], air.v[1], air.v[2]};
		if (m.spatial_weather && spatial_flow.ok) {
			for (int i = 0; i < 3; ++i) if (spatial_flow.wake_source_delta[i] != 0.0) source[i] += spatial_flow.wake_source_delta[i];
		}
		// Nonspatial WashTransport reads datum air; spatial transport shares the explicit propeller point.
		const auto tq = prop_thrust_torque(m.spatial_weather && spatial_flow.ok ? prop_air.velocity.data() : air.v,
			rpm, m.prop, rho);
		const auto target = wake_transport_target(source, rpm, tq[0], tq[1], m.prop, m.wake, rho);
		// A refused spatial sample becomes ordinary NaN datum air in
		// FlightSession.air_data; WashTransport then follows its legacy branch.
		// Only a valid explicit point field applies the stricter target check.
		if (m.spatial_weather && spatial_flow.ok && (!is_finite(target[0]) || !is_finite(target[1]))) return out;
		out.derivative.resize(expected);
		wake_transport_derivative(target, values, m.wake, out.derivative.data());
	}
	if (m.liquid.ready) {
		bool capture = ctx.capture_preview && m.liquid.gas && stage_time == ctx.time_now &&
			static_cast<int>(ctx.preview_values.size()) == value_count;
		for (int i = 0; i < 13 && capture; ++i) capture = s[i] == ctx.preview_body[i];
		for (int i = 0; i < value_count && capture; ++i) capture = values[i] == ctx.preview_values[i];
		const auto result = liquid_stage_finish(m.liquid, liquid_layout, liquid_trial, s, total.data(), prop_air.velocity.data(),
			air.v, explicit_air != nullptr, m.prop, ctx.throttle, rho, atmosphere.engine_charge_ratio, m.gravity,
			out.derivative.data(), expected, rates.data(), static_cast<int>(rates.size()), turbine ? &turbine_point : nullptr, capture);
		if (!result.ok) return out;
		out.shaped = true;
		out.loads = result.loads;
		out.derivative = result.derivative;
		out.rotor = result.rotor;
		out.has_body_derivative = true;
		out.body_derivative = result.body_derivative;
		if (result.has_pre_reaction) {
			out.has_preview = true;
			out.pre_reaction = result.pre_reaction;
			out.preview_air = air;
			out.preview_time = at;
			out.preview_rho = rho;
			out.preview_spatial = m.spatial_weather && spatial_flow.ok;
			out.preview_flow = spatial_flow;
			out.preview_point = point_context;
			out.preview_point.provider = {}; // stack-owned provider must never escape
			out.preview_wheel_rates = rates;
		}
		return out;
	}
	if (m.electric) {
		out.derivative.push_back(coupling.rpm_rate);
		out.derivative.insert(out.derivative.end(), source.rates.begin(), source.rates.end());
	}
	if (m.prescribed.coupled()) {
		const auto before = total;
		const auto gas = prescribed_gas_coupled_stage(s, total.data(), prop_air.velocity.data(), air.v,
			explicit_air != nullptr, rpm, ctx.throttle, rho, atmosphere.engine_charge_ratio, ctx.power_enabled,
			m.prescribed.shaft, m.prop, m.inertia.data(), m.inverse.data());
		if (!gas.ok) return out;
		total = gas.loads;
		out.derivative.push_back(gas.rpm_rate);
		bool capture = ctx.capture_preview && stage_time == ctx.time_now &&
			static_cast<int>(ctx.preview_values.size()) == value_count;
		for (int i = 0; i < 13 && capture; ++i) capture = s[i] == ctx.preview_body[i];
		for (int i = 0; i < value_count && capture; ++i) capture = values[i] == ctx.preview_values[i];
		if (capture) {
			out.has_preview = true;
			out.pre_reaction = before;
			out.preview_air = air;
			out.preview_time = at;
			out.preview_rho = rho;
			out.preview_spatial = m.spatial_weather && spatial_flow.ok;
			out.preview_flow = spatial_flow;
			out.preview_point = point_context;
			out.preview_point.provider = {};
			out.preview_wheel_rates = rates;
		}
	} else if (m.prescribed.continuous_turbine()) {
		out.derivative.push_back(prescribed_turbine.rpm_rate);
	}
	if (expected > 0 || m.electric || prescribed_joint) out.derivative.insert(out.derivative.end(), rates.begin(), rates.end());
	if (static_cast<int>(out.derivative.size()) != value_count) {
		return out;
	}
	out.shaped = true;
	out.loads = total;
	out.rotor = m.prescribed.is_turbine() ? prescribed_turbine.rotor : prop_rotor_momentum(m.prop, rpm);
	return out;
}

} // namespace nk
