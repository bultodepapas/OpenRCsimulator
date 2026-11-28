// NK-7a: app/audio/soundscape_model.gd, wildlife.gd activity and powertrain_audio.gd distance_gain, exact.
// Presentation only (flight audio); never read by the stage. GDScript's mixed precision is kept: its floats are
// double, Vector3 is Godot's real_t (float) with Godot's own operators (godot-cpp mirrors them), and every Math
// built-in follows the engine (smoothstep, move_toward, lerp operand order, db conversions). exp, log, pow and
// Vector3.angle_to call the engine's own functions (as NK-5g's pre-step does), so no libm or atan2f difference can
// separate the two paths on any platform. Decimal spellings are in the literal oracle (nk_kernel.cpp literal_table)
// so GDScript's parse is proven equal.
#pragma once

#include <cmath>
#include <cstdint>

#include <godot_cpp/core/gdextension_interface_loader.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include "nk_math.hpp"

namespace nk {
namespace sound {

// The engine's Math::exp, Math::log and Math::pow, through the utility functions GDScript calls.
inline double e_exp(double x) { return godot::UtilityFunctions::exp(x); }
inline double e_log(double x) { return godot::UtilityFunctions::log(x); }
inline R e_pow(R base, R exponent) { return godot::UtilityFunctions::pow(base.v, exponent.v); }

// The engine's Vector3.angle_to (real_t atan2 of the engine's libm, widened to double), or NaN when the engine does
// not expose it (hash from extension_api.json, stable since 4.0).
inline double engine_angle_to(const godot::Vector3 &from, const godot::Vector3 &to) {
	static const GDExtensionPtrBuiltInMethod method = godot::gdextension_interface::variant_get_ptr_builtin_method(
		GDEXTENSION_VARIANT_TYPE_VECTOR3, godot::StringName("angle_to")._native_ptr(), 1047977935);
	if (method == nullptr) return std::nan("");
	godot::Vector3 base = from;
	const GDExtensionConstTypePtr args[1] = {&to};
	double result = 0.0;
	method(&base, args, &result, 1);
	return result;
}

// Godot Math::smoothstep(double).
inline R smoothstep(R from, R to, R s) {
	if (is_equal_approx(from, to)) {
		if (from.v <= to.v) return s.v <= from.v ? R(0.0) : R(1.0);
		return s.v <= to.v ? R(1.0) : R(0.0);
	}
	const R x = clampf((s - from) / (to - from), 0.0, 1.0);
	return x * x * (R(3.0) - R(2.0) * x);
}

// Godot Math::sign(double): +1, -1 or 0 (NaN gives 0).
inline R sign(R x) { return x.v > 0.0 ? R(1.0) : (x.v < 0.0 ? R(-1.0) : R(0.0)); }

// Godot Math::move_toward(double).
inline R move_toward(R from, R to, R delta) {
	return absf(to - from).v <= delta.v ? to : from + sign(to - from) * delta;
}

inline R db_to_linear(R db) { return e_exp((db * R(0.11512925464970228420089957273422)).v); }
inline R linear_to_db(R linear) { return R(e_log(linear.v)) * R(8.6858896380650365530225783783321); }

// SoundscapeModel.doppler.
inline R doppler(const godot::Vector3 &source, const godot::Vector3 &listener, const godot::Vector3 &source_velocity,
		const godot::Vector3 &listener_velocity, R sound_speed) {
	const godot::Vector3 ray = (source - listener).normalized();
	const R c = clampf(sound_speed, 300.0, 380.0);
	return clampf((c + R(double(listener_velocity.dot(ray)))) /
			maxf(c + R(double(source_velocity.dot(ray))), c * R(0.5)), 0.65, 1.5);
}

enum TargetKind : int { kGlowProp = 0, kElectricProp = 1, kTurbine = 2, kOtherKind = 3 };

struct Targets {
	R motor_gain = 0.0, prop_gain = 0.0, motor_pitch = 0.0, prop_pitch = 0.0, air_gain = 0.0, wind_low = 0.0,
		wind_high = 0.0, foliage = 0.0, bird_activity = 0.0, exhaust_angle_deg = 0.0;
};

// SoundscapeModel.table_db over [x0, y0, x1, y1, ...].
inline R table_db(const double *table, int count, R x) {
	if (x.v <= table[0]) return table[1];
	for (int i = 2; i < count; i += 2) {
		if (x.v <= table[i]) return lerpf(table[i - 1], table[i + 1], (x - R(table[i - 2])) / (R(table[i]) - R(table[i - 2])));
	}
	return table[count - 1];
}

constexpr double kRoarDirectivity[12] = {0.0, -4.0, 30.0, 0.0, 60.0, -3.0, 90.0, -7.0, 120.0, -10.0, 180.0, -12.0};
constexpr double kWhineDirectivity[10] = {0.0, -8.0, 30.0, -6.0, 90.0, -2.0, 150.0, 0.0, 180.0, 0.0};

// SoundscapeModel.exhaust_angle_deg.
inline R exhaust_angle_deg(const godot::Vector3 &exhaust, const godot::Vector3 &listener, const godot::Vector3 &source) {
	const godot::Vector3 ray = listener - source;
	if (double(exhaust.length_squared()) < 1e-6 || double(ray.length_squared()) < 1e-6) return 90.0;
	return R(engine_angle_to(exhaust, ray)) * R(180.0 / 3.1415926535897932384626433833); // Math::rad_to_deg(double)
}

// SoundscapeModel.targets (+ turbine_targets): rpm, max_rpm, load, throttle, airspeed, wind_speed, running (as passed,
// before the rpm test), blades, sun_elevation, and for a turbine jet_velocity, jet_velocity_max, exhaust, listener,
// source.
inline Targets targets(R rpm_in, R max_rpm, R load_in, R throttle_in, R airspeed, R wind_speed, bool running_in, R blades,
		R sun_elevation, int kind, R jet_velocity, R jet_velocity_max, const godot::Vector3 &exhaust,
		const godot::Vector3 &listener, const godot::Vector3 &source) {
	const R rpm = maxf(rpm_in, 0.0);
	const R ratio = clampf(rpm / maxf(max_rpm, 1.0), 0.0, 1.4);
	const R load_amount = clampf(load_in, 0.0, 1.0);
	const R throttle = clampf(throttle_in, 0.0, 1.0);
	const R speed = clampf(airspeed, 0.0, 150.0);
	const R wind = clampf(wind_speed, 0.0, 35.0);
	const bool running = running_in && rpm.v > 30.0;
	const R spin = smoothstep(30.0, 1200.0, rpm);
	Targets t;
	t.motor_gain = running ? (R(0.16) + R(0.38) * sqrt_(ratio)) * (R(0.3) + R(0.35) * load_amount + R(0.35) * throttle) : R(0.0);
	t.prop_gain = spin * (R(0.07) + R(0.32) * ratio) * (R(0.55) + R(0.45) * load_amount);
	t.motor_pitch = clampf(rpm / R(6000.0), 0.12, 3.5);
	t.prop_pitch = clampf(rpm / R(6000.0) * blades / R(2.0), 0.12, 3.5);
	t.air_gain = R(0.18) * e_pow(clampf(speed / R(55.0), 0.0, 1.5), 2.0);
	t.wind_low = R(0.20) * e_pow(wind / R(18.0), 1.1);
	t.wind_high = R(0.10) * e_pow(wind / R(20.0), 1.7);
	t.foliage = R(0.008) + R(0.23) * smoothstep(0.0, 14.0, wind);
	t.bird_activity = smoothstep(-6.0, 3.0, sun_elevation) * (R(1.0) - smoothstep(6.0, 18.0, wind));
	if (kind == kElectricProp) {
		t.motor_gain = t.motor_gain * R(0.4);
	} else if (kind == kTurbine) {
		const R n_ratio = clampf(rpm / maxf(max_rpm, 1.0), 0.0, 1.2);
		const R jet_ratio = clampf(jet_velocity / maxf(jet_velocity_max, 1.0), 0.0, 1.5);
		const R theta = exhaust_angle_deg(exhaust, listener, source);
		const R roar = e_pow(jet_ratio, 4.0) + R(0.05) * n_ratio;
		const R whine = e_pow(n_ratio, 0.46);
		t.motor_pitch = rpm / R(82320.0);
		t.motor_gain = running ? R(0.98) * whine * db_to_linear(table_db(kWhineDirectivity, 10, theta)) : R(0.0);
		t.prop_pitch = R(1.40) * jet_ratio;
		t.prop_gain = running ? R(2.28) * roar * db_to_linear(table_db(kRoarDirectivity, 12, theta)) : R(0.0);
		t.exhaust_angle_deg = theta;
	}
	return t;
}

// SoundscapeModel.humidity_molar_pct.
inline R humidity_molar_pct(R relative_humidity_pct, R temperature_k, R pressure_pa) {
	const R saturation_ratio = e_pow(10.0, R(-6.8346) * e_pow(R(273.16) / temperature_k, 1.261) + R(4.6151));
	return clampf(relative_humidity_pct, 0.0, 100.0) * saturation_ratio * R(101325.0) / pressure_pa;
}

inline bool can_skip_humidity_fallback(R temperature_k, R pressure_pa) {
	return temperature_k.v >= 180.0 && temperature_k.v <= 330.0 && pressure_pa.v >= 10000.0 && pressure_pa.v <= 120000.0;
}

// SoundscapeModel.absorption_db_per_m.
inline R absorption_db_per_m(R frequency_hz, R temperature_k, R pressure_pa, R humidity_pct) {
	const R p = pressure_pa / R(101325.0);
	const R t = temperature_k / R(293.15);
	const R h = maxf(humidity_pct, 0.0);
	const R relax_oxygen = p * (R(24.0) + R(4.04e4) * h * (R(0.02) + h) / (R(0.391) + h));
	const R relax_nitrogen = p * e_pow(t, -0.5) *
		(R(9.0) + R(280.0) * h * R(e_exp((R(-4.170) * (e_pow(t, R(-1.0) / R(3.0)) - R(1.0))).v)));
	const R f2 = frequency_hz * frequency_hz;
	return R(8.686) * f2 * (R(1.84e-11) / p * sqrt_(t) + e_pow(t, -2.5) * (
		R(0.01275) * R(e_exp((R(-2239.1) / temperature_k).v)) / (relax_oxygen + f2 / relax_oxygen)
		+ R(0.1068) * R(e_exp((R(-3352.0) / temperature_k).v)) / (relax_nitrogen + f2 / relax_nitrogen)));
}

inline R log_loss_ratio(R log_frequency, R path_m, R temperature_k, R pressure_pa, R humidity_pct) {
	return R(e_log((maxf(absorption_db_per_m(R(e_exp(log_frequency.v)), temperature_k, pressure_pa, humidity_pct) * path_m,
		1e-300) / R(3.0)).v));
}

// SoundscapeModel.absorption_cutoff_hz (bracketed Illinois regula falsi).
inline R absorption_cutoff_hz(R path_m, R temperature_k, R pressure_pa, R humidity_pct) {
	const R path = maxf(path_m, 0.0);
	R low = e_log(20.0);
	R high = e_log(16000.0);
	R g_high = log_loss_ratio(high, path, temperature_k, pressure_pa, humidity_pct);
	if (g_high.v <= 0.0) return 16000.0;
	R g_low = log_loss_ratio(low, path, temperature_k, pressure_pa, humidity_pct);
	if (g_low.v >= 0.0) return 20.0;
	R x = low;
	int side = 0;
	for (int iteration = 0; iteration < 60; ++iteration) {
		x = (low * g_high - high * g_low) / (g_high - g_low);
		const R g = log_loss_ratio(x, path, temperature_k, pressure_pa, humidity_pct);
		if (absf(g).v < 1e-12 || (high - low).v < 1e-12) break;
		if (g.v < 0.0) {
			low = x;
			g_low = g;
			if (side == -1) g_high = g_high * R(0.5);
			side = -1;
		} else {
			high = x;
			g_high = g;
			if (side == 1) g_low = g_low * R(0.5);
			side = 1;
		}
	}
	return e_exp(x.v);
}

// SoundscapeModel.screening over boxes [px, py, pz, sx, sy, sz] (Godot AABB, real_t).
inline R screening(const godot::Vector3 &source, const godot::Vector3 &listener, const float *boxes, int64_t count) {
	int hits = 0;
	for (int64_t i = 0; i < count; ++i) {
		const float *b = boxes + i * 6;
		const godot::AABB canopy(godot::Vector3(b[0], b[1], b[2]), godot::Vector3(b[3], b[4], b[5]));
		if (canopy.intersects_segment(listener, source)) {
			++hits;
			if (hits == 3) break;
		}
	}
	return minf(R(double(hits)) / R(3.0), 1.0);
}

// Wildlife.activity: [bird, crow, owl, dog, cricket].
inline void wildlife_activity(R sun, R wind_speed, R temperature_c, R out[5]) {
	const R wind = maxf(0.0, wind_speed);
	const R day = smoothstep(-5.0, 4.0, sun);
	const R night = R(1.0) - smoothstep(-10.0, -2.0, sun);
	const R shelter = R(1.0) - smoothstep(5.0, 16.0, wind);
	const R warm = smoothstep(8.0, 18.0, temperature_c);
	const R chorus = R(1.0) + R(0.55) * (R(1.0) - smoothstep(4.0, 22.0, absf(sun)));
	out[0] = day * shelter * chorus;
	out[1] = day * shelter;
	out[2] = night * shelter;
	out[3] = (R(0.4) + R(0.6) * day) * (R(1.0) - smoothstep(10.0, 25.0, wind));
	out[4] = night * shelter * warm;
}

// PowertrainAudio.distance_gain.
inline R distance_gain(R distance_m) {
	return R(8.0) / maxf(distance_m, 3.0) * (R(1.0) - smoothstep(1200.0, 1500.0, distance_m));
}

} // namespace sound
} // namespace nk
