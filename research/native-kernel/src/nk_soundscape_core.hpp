// NK-7b: app/audio/soundscape.gd update_sound in the native kernel, exact. NK-7c adds the recorded powertrain bank
// (app/audio/powertrain_audio.gd update_sound). The core owns the propagation-delay
// history and the mix state and writes the soundscape's voices and bus filters through the engine's own method binds
// (GDExtension ptrcall; the library's build profile has no audio classes). The powertrain bank, glow voice, windsock
// fabric and wildlife events stay GDScript callbacks between its two calls per frame. It reads the snapshot
// dictionary itself: a value of a type the reference would not accept (or would convert in another way) refuses the
// frame before any state changes or writes, and the soundscape hands its mix back to the GDScript reference.
// Presentation only: nothing here reaches the simulation.
#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

#include <godot_cpp/core/gdextension_interface_loader.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include "nk_soundscape.hpp"

namespace nk {
namespace sound {

// Dictionary.get's default for a missing key: no snapshot value has this type and value, so a present null (which
// the reference would fail to convert) is told apart from an absent key and refuses.
inline const godot::Vector2i &missing_key() {
	static const godot::Vector2i sentinel(-2147483647, 1000003);
	return sentinel;
}

// soundscape.gd voice layout.
constexpr int kVoices = 14;
constexpr int kEventFirst = 9;
constexpr int kEventCount = 3;
constexpr int kCricketFirst = 12;

// Delayed keys in soundscape.gd _DELAYED_KEYS order: three Vector3, six continuous scalars, three discrete.
enum DelayedKey : int {
	kKeySource,
	kKeySourceVelocity,
	kKeyExhaust,
	kKeyRpm,
	kKeyLoad,
	kKeyThrottle,
	kKeyAirspeed,
	kKeyJetVelocity,
	kKeyJetVelocityMax,
	kKeyRunning,
	kKeyBlades,
	kKeyMaxRpm,
	kDelayedCount
};
constexpr int kVectorKeys = 3;
constexpr int kContinuousKeys = 9;
constexpr const char *kDelayedNames[kDelayedCount] = {"source", "source_velocity", "exhaust_direction", "rpm", "load",
	"throttle", "airspeed", "jet_velocity", "jet_velocity_max", "running", "blades", "max_rpm"};

// The Variant a sample holds, kept so the heard dictionary gets the raw value back; float() and bool() of every
// accepted kind read the double (an int is exact below 2^53).
enum ValueKind : uint8_t { kAbsent = 0, kFloat = 1, kInt = 2, kBool = 3, kVector = 4 };

struct Sample {
	uint8_t kind[kDelayedCount] = {};
	double scalar[kDelayedCount] = {};
	godot::Vector3 vector[kVectorKeys];
	bool has(int key) const { return kind[key] != kAbsent; }
};

// sound_core_frame flags (soundscape.gd _core_flags).
enum FrameFlag : int64_t {
	kFlagPropagationDelay = 1,
	kFlagAirAbsorption = 2,
	kFlagGlowVoice = 4,
	kFlagPowertrain = 8,
	kFlagGasoline = 16,
	kFlagVoiceProfile = 32,
};

// sound_core_frame answer.
enum FrameOut : int {
	kOutStatus,
	kOutGain,
	kOutScreenGain,
	kOutDuck,
	kOutDoppler,
	kOutClock,
	kOutScreened,
	kOutDelay,
	kOutCutoff,
	kOutDisturbed,
	kOutDt,
	kOutPaused,
	kOutTargets, // 10: motor_gain, prop_gain, motor_pitch, prop_pitch, air_gain, wind_low, wind_high, foliage,
	             // bird_activity, exhaust_angle_deg
	kOutPresence = kOutTargets + 10, // bird, crow, owl, dog, cricket
	kOutLevels = kOutPresence + 5,
	// NK-7c, the bank: rpm, accepted_rpm, running, level, distance_gain, paused, primed, started, then three levels and
	// three weights (the first `count` of each are the bank's).
	kOutBank = kOutLevels + kVoices,
	kOutBankLevels = kOutBank + 8,
	kOutBankWeights = kOutBankLevels + 3,
	kOutFrameSize = kOutBankWeights + 3
};

// powertrain_audio.gd families the bank's level law tells apart.
enum BankFamily : int { kBankOther = 0, kBankElectric = 1, kBankRotor = 2, kBankTurbine = 3 };
constexpr int kBankLayers = 3; // PowertrainAudio.MAX_LAYERS

// sound_core_bind / sound_core_state: the soundscape's mix state.
enum StateSlot : int {
	kStateGain,
	kStateClock,
	kStateScreened,
	kStateScreenClock,
	kStateScreenGoal,
	kStateDoppler,
	kStateDelay,
	kStateCutoff,
	kStateAbsorptionTarget,
	kStateAbsorptionClock,
	kStateAbsorptionPrimed,
	kStatePrimed,
	kStatePreviousPaused,
	kStatePreviousSource,
	kStatePreviousListener = kStatePreviousSource + 3,
	kStateLevels = kStatePreviousListener + 3,
	kStatePresence = kStateLevels + kVoices,
	kStateSize = kStatePresence + 5
};

// Engine methods the core calls (hashes from extension_api.json; a missing one leaves the core unbound).
struct EngineBinds {
	GDExtensionMethodBindPtr set_volume_db = nullptr;
	GDExtensionMethodBindPtr set_pitch_scale = nullptr;
	GDExtensionMethodBindPtr get_pitch_scale = nullptr;
	GDExtensionMethodBindPtr set_stream_paused = nullptr;
	GDExtensionMethodBindPtr get_unit_size = nullptr;
	GDExtensionMethodBindPtr set_global_position = nullptr;
	GDExtensionMethodBindPtr get_global_position = nullptr;
	GDExtensionMethodBindPtr set_cutoff = nullptr;
	GDExtensionMethodBindPtr set_gain = nullptr;
	GDExtensionMethodBindPtr play = nullptr;
	void *player_tag = nullptr;
	void *filter_tag = nullptr;
	bool ok = false;
};

inline GDExtensionMethodBindPtr method_bind(const char *class_name, const char *method, GDExtensionInt hash) {
	const godot::StringName c(class_name);
	const godot::StringName m(method);
	return godot::gdextension_interface::classdb_get_method_bind(c._native_ptr(), m._native_ptr(), hash);
}

inline const EngineBinds &engine_binds() {
	static const EngineBinds binds = [] {
		EngineBinds b;
		b.set_volume_db = method_bind("AudioStreamPlayer3D", "set_volume_db", 373806689);
		b.set_pitch_scale = method_bind("AudioStreamPlayer3D", "set_pitch_scale", 373806689);
		b.get_pitch_scale = method_bind("AudioStreamPlayer3D", "get_pitch_scale", 1740695150);
		b.set_stream_paused = method_bind("AudioStreamPlayer3D", "set_stream_paused", 2586408642);
		b.get_unit_size = method_bind("AudioStreamPlayer3D", "get_unit_size", 1740695150);
		b.set_global_position = method_bind("Node3D", "set_global_position", 3460891852);
		b.get_global_position = method_bind("Node3D", "get_global_position", 3360562783);
		b.set_cutoff = method_bind("AudioEffectFilter", "set_cutoff", 373806689);
		b.set_gain = method_bind("AudioEffectFilter", "set_gain", 373806689);
		b.play = method_bind("AudioStreamPlayer3D", "play", 1958160172);
		const godot::StringName player("AudioStreamPlayer3D");
		const godot::StringName filter("AudioEffectFilter");
		b.player_tag = godot::gdextension_interface::classdb_get_class_tag(player._native_ptr());
		b.filter_tag = godot::gdextension_interface::classdb_get_class_tag(filter._native_ptr());
		b.ok = b.set_volume_db && b.set_pitch_scale && b.get_pitch_scale && b.set_stream_paused && b.get_unit_size &&
			b.set_global_position && b.get_global_position && b.set_cutoff && b.set_gain && b.player_tag &&
			b.filter_tag && b.play && engine_angle_method() != nullptr;
		return b;
	}();
	return binds;
}

// One engine object the core writes, revalidated by instance id before every frame.
struct Bound {
	GDExtensionObjectPtr ptr = nullptr;
	GDObjectInstanceID id = 0;
	bool valid() const {
		return ptr != nullptr && godot::gdextension_interface::object_get_instance_from_id(id) == ptr;
	}
};

// The engine object a Variant holds, or null (also for a non-object).
inline GDExtensionObjectPtr raw_object(const godot::Variant &value) {
	if (value.get_type() != godot::Variant::OBJECT) return nullptr;
	GDExtensionObjectPtr ptr = nullptr;
	static const GDExtensionTypeFromVariantConstructorFunc to_object =
		godot::gdextension_interface::get_variant_to_type_constructor(GDEXTENSION_VARIANT_TYPE_OBJECT);
	to_object(&ptr, value._native_ptr());
	return ptr;
}

inline bool bind_object(const godot::Variant &value, void *class_tag, Bound &out) {
	const GDExtensionObjectPtr ptr = raw_object(value);
	if (ptr == nullptr || godot::gdextension_interface::object_cast_to(ptr, class_tag) == nullptr) return false;
	out.ptr = ptr;
	out.id = godot::gdextension_interface::object_get_instance_id(ptr);
	return out.id != 0;
}

// Ptrcall in the engine's encoding: float arguments and results travel as double, bool as GDExtensionBool.
inline void call_set(GDExtensionMethodBindPtr method, const Bound &object, double value) {
	const GDExtensionConstTypePtr args[1] = {&value};
	godot::gdextension_interface::object_method_bind_ptrcall(method, object.ptr, args, nullptr);
}
inline void call_set(GDExtensionMethodBindPtr method, const Bound &object, bool value) {
	const GDExtensionBool encoded = value ? 1 : 0;
	const GDExtensionConstTypePtr args[1] = {&encoded};
	godot::gdextension_interface::object_method_bind_ptrcall(method, object.ptr, args, nullptr);
}
inline void call_set(GDExtensionMethodBindPtr method, const Bound &object, const godot::Vector3 &value) {
	const GDExtensionConstTypePtr args[1] = {&value};
	godot::gdextension_interface::object_method_bind_ptrcall(method, object.ptr, args, nullptr);
}
inline double call_get_double(GDExtensionMethodBindPtr method, const Bound &object) {
	double result = 0.0;
	godot::gdextension_interface::object_method_bind_ptrcall(method, object.ptr, nullptr, &result);
	return result;
}
inline godot::Vector3 call_get_vector3(GDExtensionMethodBindPtr method, const Bound &object) {
	godot::Vector3 result;
	godot::gdextension_interface::object_method_bind_ptrcall(method, object.ptr, nullptr, &result);
	return result;
}

// PowertrainAudio.band_weights: adjacent equal-power bands over the layer reference rpms.
inline void band_weights(R rpm, const R *references, int count, R *weights) {
	for (int i = 0; i < count; ++i) weights[i] = 0.0;
	if (count == 0) return;
	if (rpm.v <= references[0].v) {
		weights[0] = 1.0;
		return;
	}
	for (int index = 0; index < count - 1; ++index) {
		if (rpm.v <= references[index + 1].v) {
			const R fraction = clampf(R(e_log((rpm / references[index]).v)) /
				R(e_log((references[index + 1] / references[index]).v)), 0.0, 1.0);
			const R angle = fraction * R(3.1415926535897932384626433833) * R(0.5); // fraction * PI * 0.5
			weights[index] = godot::UtilityFunctions::cos(angle.v);
			weights[index + 1] = godot::UtilityFunctions::sin(angle.v);
			return;
		}
	}
	weights[count - 1] = 1.0;
}

// float(value) for the kinds GDScript converts the same way here; any other type refuses.
inline bool number(const godot::Variant &value, double &out, uint8_t &kind) {
	switch (value.get_type()) {
		case godot::Variant::FLOAT:
			out = static_cast<double>(value);
			kind = kFloat;
			return true;
		case godot::Variant::INT:
			out = static_cast<double>(static_cast<int64_t>(value));
			kind = kInt;
			return true;
		case godot::Variant::BOOL:
			out = static_cast<bool>(value) ? 1.0 : 0.0;
			kind = kBool;
			return true;
		default:
			return false;
	}
}

class Core {
public:
	Core() {
		for (int k = 0; k < kDelayedCount; ++k) delayed_keys_[k] = godot::String(kDelayedNames[k]);
		key_paused_ = godot::String("paused");
		key_time_ = godot::String("time");
		key_listener_ = godot::String("listener");
		key_sound_speed_ = godot::String("sound_speed");
		key_wind_direction_ = godot::String("wind_direction");
		key_wind_speed_ = godot::String("wind_speed");
		key_sun_ = godot::String("sun_elevation");
		key_temperature_ = godot::String("temperature_c");
		key_pressure_ = godot::String("pressure_pa");
		key_humidity_ = godot::String("humidity_molar_pct");
		missing_ = missing_key();
	}

	bool bind(const godot::Array &voices, const godot::Variant &glow, const godot::Variant &absorption,
			const godot::Variant &screen, const godot::PackedVector3Array &trees, const godot::PackedFloat32Array &canopies,
			int64_t kind, const godot::PackedFloat64Array &state) {
		bound_ = false;
		const EngineBinds &b = engine_binds();
		if (!b.ok || voices.size() != kVoices || state.size() != kStateSize || canopies.size() % 6 != 0) return false;
		for (int i = 0; i < kVoices; ++i) {
			if (!bind_object(voices[i], b.player_tag, voices_[i])) return false;
		}
		if (glow.get_type() != godot::Variant::NIL && glow.get_type() != godot::Variant::OBJECT) return false;
		has_glow_ = raw_object(glow) != nullptr;
		if (has_glow_ && !bind_object(glow, b.player_tag, glow_)) return false;
		if (!bind_object(absorption, b.filter_tag, absorption_) || !bind_object(screen, b.filter_tag, screen_)) return false;
		trees_.assign(trees.ptr(), trees.ptr() + trees.size());
		canopies_.assign(canopies.ptr(), canopies.ptr() + canopies.size());
		kind_ = static_cast<int>(kind);
		const double *s = state.ptr();
		gain_ = s[kStateGain];
		clock_ = s[kStateClock];
		screened_ = s[kStateScreened];
		screen_clock_ = s[kStateScreenClock];
		screen_goal_ = s[kStateScreenGoal];
		doppler_ = s[kStateDoppler];
		delay_ = s[kStateDelay];
		cutoff_ = s[kStateCutoff];
		absorption_target_ = s[kStateAbsorptionTarget];
		absorption_clock_ = s[kStateAbsorptionClock];
		absorption_primed_ = s[kStateAbsorptionPrimed] != 0.0;
		primed_ = s[kStatePrimed] != 0.0;
		previous_paused_ = s[kStatePreviousPaused] != 0.0;
		previous_source_ = godot::Vector3(s[kStatePreviousSource], s[kStatePreviousSource + 1], s[kStatePreviousSource + 2]);
		previous_listener_ =
			godot::Vector3(s[kStatePreviousListener], s[kStatePreviousListener + 1], s[kStatePreviousListener + 2]);
		for (int i = 0; i < kVoices; ++i) levels_[i] = s[kStateLevels + i];
		for (int i = 0; i < 5; ++i) presence_[i] = s[kStatePresence + i];
		clear_history();
		delay_ = s[kStateDelay];
		heard_active_ = false;
		bound_ = true;
		return true;
	}

	// NK-7c: the soundscape's recorded powertrain bank. layers: [has_rpm (1/0), rpm, gain] per player, as GDScript read
	// them; state: [rpm, primed, started, levels...]. False leaves the core without a bank (the soundscape refuses it).
	bool bind_bank(const godot::Array &players, const godot::PackedFloat64Array &layers, int64_t family,
			double profile_max_rpm, double trim_db, const godot::PackedFloat64Array &state) {
		has_bank_ = false;
		const EngineBinds &b = engine_binds();
		const int64_t count = players.size();
		if (!bound_ || count < 1 || count > kBankLayers || layers.size() != count * 3 || state.size() != 3 + count) {
			return false;
		}
		Bank bank;
		bank.count = static_cast<int>(count);
		for (int i = 0; i < bank.count; ++i) {
			if (!bind_object(players[i], b.player_tag, bank.players[i])) return false;
			bank.has_rpm[i] = layers[i * 3] != 0.0;
			bank.rpm_reference[i] = layers[i * 3 + 1];
			bank.gain[i] = layers[i * 3 + 2];
		}
		bank.family = static_cast<int>(family);
		bank.profile_max_rpm = profile_max_rpm;
		bank.trim_db = trim_db;
		bank.rpm = state[0];
		bank.primed = state[1] != 0.0;
		bank.started = state[2] != 0.0;
		for (int i = 0; i < bank.count; ++i) bank.levels[i] = state[3 + i];
		bank_ = bank;
		has_bank_ = true;
		return true;
	}

	godot::PackedFloat64Array state() const {
		godot::PackedFloat64Array out;
		out.resize(kStateSize);
		double *s = out.ptrw();
		s[kStateGain] = gain_.v;
		s[kStateClock] = clock_.v;
		s[kStateScreened] = screened_.v;
		s[kStateScreenClock] = screen_clock_.v;
		s[kStateScreenGoal] = screen_goal_.v;
		s[kStateDoppler] = doppler_.v;
		s[kStateDelay] = delay_.v;
		s[kStateCutoff] = cutoff_.v;
		s[kStateAbsorptionTarget] = absorption_target_.v;
		s[kStateAbsorptionClock] = absorption_clock_.v;
		s[kStateAbsorptionPrimed] = absorption_primed_ ? 1.0 : 0.0;
		s[kStatePrimed] = primed_ ? 1.0 : 0.0;
		s[kStatePreviousPaused] = previous_paused_ ? 1.0 : 0.0;
		for (int a = 0; a < 3; ++a) {
			s[kStatePreviousSource + a] = previous_source_[a];
			s[kStatePreviousListener + a] = previous_listener_[a];
		}
		for (int i = 0; i < kVoices; ++i) s[kStateLevels + i] = levels_[i].v;
		for (int i = 0; i < 5; ++i) s[kStatePresence + i] = presence_[i].v;
		return out;
	}

	// reset_observer (absorption true) and _enter_tree (false): the core's share of each.
	void reset(bool absorption) {
		primed_ = false;
		if (absorption) absorption_primed_ = false;
		clear_history();
		gain_ = 0.0;
		for (R &level : levels_) level = 0.0;
		// Both callers also reset the bank (reset_observer directly, _enter_tree through its rebind).
		bank_.rpm = 0.0;
		bank_.primed = false;
		bank_.started = false;
		for (R &level : bank_.levels) level = 0.0;
	}

	// update_sound up to wildlife.advance; empty when refused (nothing changed).
	godot::PackedFloat64Array frame(const godot::Dictionary &snapshot, double delta, int64_t flags) {
		godot::PackedFloat64Array out;
		if (!bound_ || !nodes_valid()) return out;
		Input in;
		if (!read(snapshot, in)) return out;
		const EngineBinds &b = engine_binds();
		const R dt = clampf(delta, 0.0, 0.1);
		const bool paused = in.paused;
		hear(in, (flags & kFlagPropagationDelay) != 0);
		const godot::Vector3 source = heard_.has(kKeySource) ? heard_.vector[kKeySource] : godot::Vector3();
		const godot::Vector3 listener = in.listener;
		if (paused != previous_paused_) primed_ = false;
		previous_paused_ = paused;
		godot::Vector3 source_velocity;
		godot::Vector3 listener_velocity;
		if (primed_ && delta > 0.0 && delta < 0.2) {
			listener_velocity = (listener - previous_listener_) / static_cast<float>(delta);
			// AUD-07b: a camera cut is a jump, not motion.
			if (double(length(listener_velocity)) > 150.0) listener_velocity = godot::Vector3();
			if (heard_.has(kKeySourceVelocity)) {
				source_velocity = heard_.vector[kKeySourceVelocity];
			} else if (double(distance(source, previous_source_)) < 30.0) {
				source_velocity = (source - previous_source_) / static_cast<float>(delta);
			}
		}
		previous_source_ = source;
		previous_listener_ = listener;
		primed_ = !paused;
		doppler_ = doppler(source, listener, source_velocity, listener_velocity, in.sound_speed);
		const R mix_target = paused ? 0.0 : 1.0;
		gain_ = move_toward(gain_, mix_target, dt / R(paused ? 0.08 : 0.35));
		const bool stream_paused = paused && gain_.v <= 0.0;
		for (const Bound &voice : voices_) call_set(b.set_stream_paused, voice, stream_paused);
		if (!paused) clock_ = clock_ + dt;
		screen_clock_ = screen_clock_ - dt;
		if (screen_clock_.v <= 0.0) {
			screen_clock_ = 0.1;
			screen_goal_ = screening(source, listener, canopies_.data(), int64_t(canopies_.size() / 6));
		}
		screened_ = lerpf(screened_, screen_goal_, R(1.0) - R(e_exp((R(-dt.v) / R(0.25)).v)));
		const Sample &h = heard_;
		const R load = h.has(kKeyLoad) ? R(h.scalar[kKeyLoad]) : R(0.0);
		const R heard_airspeed = h.has(kKeyAirspeed) ? R(h.scalar[kKeyAirspeed]) : R(0.0);
		targets_ = targets(h.has(kKeyRpm) ? R(h.scalar[kKeyRpm]) : R(0.0),
			h.has(kKeyMaxRpm) ? R(h.scalar[kKeyMaxRpm]) : R(12000.0), load,
			h.has(kKeyThrottle) ? R(h.scalar[kKeyThrottle]) : clampf(load, 0.0, 1.0), heard_airspeed, in.wind_speed,
			h.has(kKeyRunning) ? h.scalar[kKeyRunning] != 0.0 : true,
			h.has(kKeyBlades) ? R(h.scalar[kKeyBlades]) : R(2.0), in.sun, kind_,
			h.has(kKeyMaxRpm) ? R(h.scalar[kKeyMaxRpm]) : R(1.0),
			h.has(kKeyJetVelocity) ? R(h.scalar[kKeyJetVelocity]) : R(0.0),
			h.has(kKeyJetVelocityMax) ? R(h.scalar[kKeyJetVelocityMax]) : R(1.0),
			h.has(kKeyExhaust) ? h.vector[kKeyExhaust] : godot::Vector3(), listener, source);
		const Targets &t = targets_;
		duck_ = R(1.0) - R(0.22) * (R(1.0) - smoothstep(12.0, 90.0, R(double(distance(source, listener))))) * t.motor_gain;
		for (int i = 0; i < 3; ++i) call_set(b.set_global_position, voices_[i], source);
		const R pitch_alpha = R(1.0) - R(e_exp((R(-dt.v) / R(0.04)).v));
		if (has_glow_) {
			call_set(b.set_global_position, glow_, source);
			call_set(b.set_pitch_scale, glow_,
				lerpf(call_get_double(b.get_pitch_scale, glow_), clampf(doppler_, 0.1, 4.0), pitch_alpha).v);
		}
		path_filters(in, source, listener, dt, (flags & kFlagAirAbsorption) != 0);
		screen_gain_ = db_to_linear(R(-7.0) * screened_);
		level_alpha_ = R(1.0) - R(e_exp((R(-dt.v) / R(0.09)).v));
		profile_ = (flags & kFlagVoiceProfile) != 0;
		if ((flags & kFlagPowertrain) != 0) {
			level(0, 0.0);
			const bool running = h.has(kKeyRunning) ? h.scalar[kKeyRunning] != 0.0 : false;
			const bool coast = (flags & kFlagGasoline) != 0 && !running;
			level(1, coast ? t.prop_gain * screen_gain_ * R(0.65) : R(0.0));
			if (has_bank_) bank_update(source, listener, dt, gain_ * screen_gain_, paused);
		} else if ((flags & kFlagGlowVoice) != 0) {
			level(0, 0.0);
			level(1, 0.0);
		} else {
			level(0, t.motor_gain * screen_gain_);
			level(1, t.prop_gain * screen_gain_);
		}
		level(2, t.air_gain * screen_gain_);
		pitch(0, t.motor_pitch * doppler_, pitch_alpha);
		pitch(1, t.prop_pitch * doppler_, pitch_alpha);
		pitch(2, doppler_ * (R(0.8) + R(0.005) * heard_airspeed), pitch_alpha);
		godot::Vector3 direction = in.wind_direction;
		direction.y = 0.0f;
		if (double(length_squared(direction)) < 0.001) direction = godot::Vector3(1.0f, 0.0f, 0.0f);
		direction = normalized(direction);
		call_set(b.set_global_position, voices_[3], listener - direction * 7.0f);
		call_set(b.set_global_position, voices_[4],
			listener + normalized(direction.cross(godot::Vector3(0.0f, 1.0f, 0.0f))) * 5.0f);
		level(3, t.wind_low * duck_);
		level(4, t.wind_high * duck_);
		for (int i = 0; i < 4; ++i) {
			if (trees_.empty()) {
				level(5 + i, 0.0);
			} else {
				call_set(b.set_global_position, voices_[5 + i], trees_[(size_t(i) * 2) % trees_.size()]);
				const R n = double(i);
				const R variation = R(0.75) + R(0.25) * R(godot::UtilityFunctions::sin(
					(clock_ * (R(0.31) + n * R(0.07)) + n * R(1.7)).v));
				level(5 + i, t.foliage * variation * duck_);
			}
		}
		R activity[5];
		wildlife_activity(in.sun, in.wind_speed, in.temperature_c, activity);
		const R presence_alpha = R(1.0) - R(e_exp((R(-dt.v) / R(4.0)).v));
		for (int i = 0; i < 5; ++i) presence_[i] = lerpf(presence_[i], activity[i], presence_alpha);
		bool disturbed = false;
		if (t.motor_gain.v > 0.20 && heard_airspeed.v > 12.0) {
			for (const godot::Vector3 &perch : trees_) {
				if (double(distance_squared(in.source, perch)) < 1225.0) { // 35.0 * 35.0
					disturbed = true;
					break;
				}
			}
		}
		framed_ = true;
		out.resize(kOutFrameSize);
		double *o = out.ptrw();
		o[kOutStatus] = 1.0;
		o[kOutGain] = gain_.v;
		o[kOutScreenGain] = screen_gain_.v;
		o[kOutDuck] = duck_.v;
		o[kOutDoppler] = doppler_.v;
		o[kOutClock] = clock_.v;
		o[kOutScreened] = screened_.v;
		o[kOutDelay] = delay_.v;
		o[kOutCutoff] = cutoff_.v;
		o[kOutDisturbed] = disturbed ? 1.0 : 0.0;
		o[kOutDt] = dt.v;
		o[kOutPaused] = paused ? 1.0 : 0.0;
		const R target_values[10] = {t.motor_gain, t.prop_gain, t.motor_pitch, t.prop_pitch, t.air_gain, t.wind_low,
			t.wind_high, t.foliage, t.bird_activity, t.exhaust_angle_deg};
		for (int i = 0; i < 10; ++i) o[kOutTargets + i] = target_values[i].v;
		for (int i = 0; i < 5; ++i) o[kOutPresence + i] = presence_[i].v;
		for (int i = 0; i < kVoices; ++i) o[kOutLevels + i] = levels_[i].v;
		const Bank &k = bank_;
		o[kOutBank] = k.rpm.v;
		o[kOutBank + 1] = k.accepted_rpm.v;
		o[kOutBank + 2] = k.running ? 1.0 : 0.0;
		o[kOutBank + 3] = k.level.v;
		o[kOutBank + 4] = k.distance_gain.v;
		o[kOutBank + 5] = k.paused ? 1.0 : 0.0;
		o[kOutBank + 6] = k.primed ? 1.0 : 0.0;
		o[kOutBank + 7] = k.started ? 1.0 : 0.0;
		for (int i = 0; i < kBankLayers; ++i) {
			o[kOutBankLevels + i] = k.levels[i].v;
			o[kOutBankWeights + i] = k.weights[i].v;
		}
		return out;
	}

	// update_sound after wildlife.advance: the event and cricket levels. species_levels: the three event species
	// (bird 0, crow 1, owl 2, dog 3) then their levels. Returns the fourteen levels; empty when refused.
	godot::PackedFloat64Array events(const godot::PackedFloat64Array &species_levels) {
		godot::PackedFloat64Array out;
		if (!bound_ || !framed_ || species_levels.size() != 2 * kEventCount || !nodes_valid()) return out;
		const double *e = species_levels.ptr();
		for (int i = 0; i < kEventCount; ++i) {
			if (!(e[i] == 0.0 || e[i] == 1.0 || e[i] == 2.0 || e[i] == 3.0)) return out;
		}
		static const double kBase[4] = {0.26, 0.21, 0.30, 0.26};
		for (int i = 0; i < kEventCount; ++i) {
			const int species = static_cast<int>(e[i]);
			level(kEventFirst + i, R(kBase[species]) * minf(1.0, presence_[species]) * R(e[kEventCount + i]) * duck_);
		}
		for (int i = 0; i < 2; ++i) {
			const R n = double(i);
			const R breathing = R(0.78) + R(0.22) * R(godot::UtilityFunctions::sin(
				(clock_ * (R(0.11) + R(0.03) * n) + R(2.2) * n).v));
			level(kCricketFirst + i, R(0.11) * presence_[4] * breathing * duck_);
		}
		framed_ = false;
		out.resize(kVoices);
		for (int i = 0; i < kVoices; ++i) out[i] = levels_[i].v;
		return out;
	}

	// heard_snapshot's answer for the last frame: the snapshot itself without a delay, else a copy whose delayed keys
	// hold the heard values.
	godot::Dictionary heard(const godot::Dictionary &snapshot) const {
		if (!heard_active_) return snapshot;
		godot::Dictionary out = snapshot.duplicate();
		for (int k = 0; k < kDelayedCount; ++k) {
			if (!applied_[k]) continue;
			switch (heard_.kind[k]) {
				case kVector: out[delayed_keys_[k]] = heard_.vector[k]; break;
				case kFloat: out[delayed_keys_[k]] = heard_.scalar[k]; break;
				case kInt: out[delayed_keys_[k]] = static_cast<int64_t>(heard_.scalar[k]); break;
				case kBool: out[delayed_keys_[k]] = heard_.scalar[k] != 0.0; break;
				default: break;
			}
		}
		return out;
	}

	int64_t history_size() const { return int64_t(times_.size()) - int64_t(start_); }

private:
	struct Input {
		bool paused = false;
		bool has_time = false;
		double time = 0.0;
		godot::Vector3 source;
		godot::Vector3 listener;
		R sound_speed = 343.0;
		godot::Vector3 wind_direction = godot::Vector3(1.0f, 0.0f, 0.0f);
		R wind_speed = 0.0;
		R sun = 45.0;
		R temperature_c = 15.0;
		R pressure_pa = 101325.0;
		bool has_humidity = false;
		R humidity = 0.0;
		Sample sample;
	};

	bool nodes_valid() const {
		for (const Bound &voice : voices_) {
			if (!voice.valid()) return false;
		}
		if (has_bank_) {
			for (int i = 0; i < bank_.count; ++i) {
				if (!bank_.players[i].valid()) return false;
			}
		}
		return (!has_glow_ || glow_.valid()) && absorption_.valid() && screen_.valid();
	}

	// The key's value, or NIL when the key is missing. A present null comes back as the sentinel, which no reader
	// accepts, so the frame refuses where the reference would fail to convert it.
	godot::Variant lookup(const godot::Dictionary &snapshot, const godot::Variant &key) const {
		godot::Variant value = snapshot.get(key, missing_);
		if (value.get_type() == godot::Variant::VECTOR2I && godot::Vector2i(value) == missing_key()) return godot::Variant();
		if (value.get_type() == godot::Variant::NIL) return missing_key(); // present null: refused by every reader
		return value;
	}

	bool optional_number(const godot::Dictionary &snapshot, const godot::Variant &key, R &out) const {
		const godot::Variant value = lookup(snapshot, key);
		if (value.get_type() == godot::Variant::NIL) return true;
		double x = 0.0;
		uint8_t kind = kAbsent;
		if (!number(value, x, kind)) return false;
		out = x;
		return true;
	}

	bool optional_vector(const godot::Dictionary &snapshot, const godot::Variant &key, godot::Vector3 &out) const {
		const godot::Variant value = lookup(snapshot, key);
		if (value.get_type() == godot::Variant::NIL) return true;
		if (value.get_type() != godot::Variant::VECTOR3) return false;
		out = value;
		return true;
	}

	bool read(const godot::Dictionary &snapshot, Input &in) const {
		double x = 0.0;
		uint8_t kind = kAbsent;
		const godot::Variant paused = lookup(snapshot, key_paused_);
		if (paused.get_type() != godot::Variant::NIL) {
			if (!number(paused, x, kind)) return false;
			in.paused = x != 0.0;
		}
		const godot::Variant time = lookup(snapshot, key_time_);
		if (time.get_type() != godot::Variant::NIL) {
			if (!number(time, in.time, kind)) return false;
			in.has_time = true;
		}
		for (int k = 0; k < kDelayedCount; ++k) {
			const godot::Variant value = lookup(snapshot, delayed_keys_[k]);
			if (value.get_type() == godot::Variant::NIL) continue;
			if (k < kVectorKeys) {
				if (value.get_type() != godot::Variant::VECTOR3) return false;
				in.sample.vector[k] = value;
				in.sample.kind[k] = kVector;
			} else if (!number(value, in.sample.scalar[k], in.sample.kind[k])) {
				return false;
			}
		}
		if (in.sample.has(kKeySource)) in.source = in.sample.vector[kKeySource];
		if (!optional_vector(snapshot, key_listener_, in.listener)) return false;
		if (!optional_number(snapshot, key_sound_speed_, in.sound_speed)) return false;
		if (!optional_vector(snapshot, key_wind_direction_, in.wind_direction)) return false;
		if (!optional_number(snapshot, key_wind_speed_, in.wind_speed)) return false;
		if (!optional_number(snapshot, key_sun_, in.sun)) return false;
		if (!optional_number(snapshot, key_temperature_, in.temperature_c)) return false;
		if (!optional_number(snapshot, key_pressure_, in.pressure_pa)) return false;
		const godot::Variant humidity = lookup(snapshot, key_humidity_);
		if (humidity.get_type() != godot::Variant::NIL) {
			if (!number(humidity, x, kind)) return false;
			in.has_humidity = true;
			in.humidity = x;
		}
		return true;
	}

	void clear_history() {
		times_.clear();
		positions_.clear();
		samples_.clear();
		start_ = 0;
		delay_ = 0.0;
	}

	// heard_snapshot: records the accepted source sample and leaves heard_ holding the snapshot's values with the
	// source-side keys at the retarded time.
	void hear(const Input &in, bool propagation) {
		heard_ = in.sample;
		for (bool &applied : applied_) applied = false;
		heard_active_ = false;
		if (!propagation || !in.has_time) {
			delay_ = 0.0;
			return;
		}
		heard_active_ = true;
		const double now = in.time;
		if (!times_.empty() && (now < times_.back() || now - times_.back() > 0.5)) clear_history();
		if (!times_.empty() && now == times_.back()) {
			// Paused or the same accepted tick: the newest values replace the sample.
			samples_.back() = in.sample;
			positions_.back() = in.source;
		} else {
			times_.push_back(now);
			positions_.push_back(in.source);
			samples_.push_back(in.sample);
		}
		while (start_ + 1 < times_.size() && times_[start_ + 1] < now - 5.5) ++start_;
		if (start_ >= 128 && start_ * 2 >= times_.size()) {
			times_.erase(times_.begin(), times_.begin() + std::ptrdiff_t(start_));
			positions_.erase(positions_.begin(), positions_.begin() + std::ptrdiff_t(start_));
			samples_.erase(samples_.begin(), samples_.begin() + std::ptrdiff_t(start_));
			start_ = 0;
		}
		Emission e = retarded_emission(times_.data(), positions_.data(), int64_t(times_.size()), in.listener, now,
			double(in.sound_speed), int64_t(start_));
		if (e.index < int64_t(start_)) {
			e.index = int64_t(start_);
			e.alpha = 0.0;
			e.delay = now - times_[start_];
		}
		delay_ = e.delay;
		const double alpha = e.alpha;
		const Sample &older = samples_[size_t(e.index)];
		const Sample &newer = samples_[std::min(size_t(e.index) + 1, samples_.size() - 1)];
		for (int k = 0; k < kContinuousKeys; ++k) {
			if (older.has(k) && newer.has(k)) {
				applied_[k] = true;
				if (k < kVectorKeys) {
					heard_.kind[k] = kVector;
					heard_.vector[k] = older.vector[k].lerp(newer.vector[k], static_cast<float>(alpha));
				} else {
					heard_.kind[k] = kFloat;
					heard_.scalar[k] = lerpf(older.scalar[k], newer.scalar[k], alpha).v;
				}
			} else if (older.has(k)) {
				applied_[k] = true;
				heard_.kind[k] = older.kind[k];
				if (k < kVectorKeys) heard_.vector[k] = older.vector[k];
				heard_.scalar[k] = older.scalar[k];
			}
		}
		const Sample &nearest = alpha >= 0.5 ? newer : older;
		for (int k = kContinuousKeys; k < kDelayedCount; ++k) {
			if (nearest.has(k)) {
				applied_[k] = true;
				heard_.kind[k] = nearest.kind[k];
				heard_.scalar[k] = nearest.scalar[k];
			}
		}
	}

	// _update_path_filters.
	void path_filters(const Input &in, const godot::Vector3 &source, const godot::Vector3 &listener, R dt,
			bool air_absorption) {
		const EngineBinds &b = engine_binds();
		const R temperature_k = in.temperature_c + R(273.15);
		const R pressure_pa = in.pressure_pa;
		const R humidity = in.has_humidity ? in.humidity : humidity_molar_pct(50.0, temperature_k, pressure_pa);
		const bool primed = absorption_primed_ && cutoff_.v > 0.0;
		absorption_clock_ = absorption_clock_ - dt;
		if (!primed || absorption_clock_.v <= 0.0) {
			absorption_clock_ = 0.1;
			absorption_target_ = air_absorption
				? absorption_cutoff_hz(R(double(distance(source, listener))), temperature_k, pressure_pa, humidity)
				: R(16000.0);
		}
		// Log-frequency smoothing: a camera cut or history restart must not step the coefficients (a step clicks).
		if (!primed) {
			cutoff_ = absorption_target_;
			absorption_primed_ = true;
		} else {
			cutoff_ = e_exp(lerpf(R(e_log(cutoff_.v)), R(e_log(absorption_target_.v)),
				R(1.0) - R(e_exp((R(-dt.v) / R(0.15)).v))).v);
		}
		call_set(b.set_cutoff, absorption_, cutoff_.v);
		call_set(b.set_cutoff, screen_, lerpf(6500.0, 1500.0, screened_).v);
		call_set(b.set_gain, screen_, db_to_linear(R(-12.0) * screened_).v); // 0.5 * SCREEN_SHELF_DB: gain squared
	}

	// NK-7c: PowertrainAudio.update_sound(heard snapshot, dt, mix_gain, doppler), as the soundscape calls it.
	void bank_update(const godot::Vector3 &source, const godot::Vector3 &listener, R dt, R mix_gain, bool paused) {
		const EngineBinds &b = engine_binds();
		const Sample &h = heard_;
		Bank &k = bank_;
		const R accepted = maxf(h.has(kKeyRpm) ? R(h.scalar[kKeyRpm]) : R(0.0), 0.0);
		const R maximum = maxf(h.has(kKeyMaxRpm) ? R(h.scalar[kKeyMaxRpm]) : k.profile_max_rpm, 1.0);
		const bool running = h.has(kKeyRunning) ? h.scalar[kKeyRunning] != 0.0 : false;
		if (!k.primed) {
			k.rpm = accepted;
			k.primed = true;
		}
		if (!paused) k.rpm = lerpf(k.rpm, accepted, R(1.0) - R(e_exp((R(-dt.v) / R(0.055)).v)));
		const R ratio = clampf(k.rpm / maximum, 0.0, 1.3);
		const R throttle = clampf(h.has(kKeyThrottle) ? R(h.scalar[kKeyThrottle]) : R(0.0), 0.0, 1.0);
		const R load = clampf(h.has(kKeyLoad) ? R(h.scalar[kKeyLoad]) : throttle, 0.0, 1.0);
		const R spin = smoothstep(25.0, k.family == kBankTurbine ? 18000.0 : 450.0, accepted);
		// Running combustion depends on power, not windmilling RPM alone. Electric has no combustion idle.
		const R drive = (R(0.24) + R(0.76) * sqrt_(ratio)) * (R(0.28) + R(0.42) * throttle + R(0.30) * load);
		R level = running ? R(0.5) * drive * spin : R(0.0);
		if (k.family == kBankElectric) {
			level = R(0.30) * e_pow(ratio, 1.25) * (R(0.45) + R(0.55) * load) * spin;
		} else if (k.family == kBankRotor) {
			level = R(0.40) * e_pow(ratio, 1.5) * (R(0.35) + R(0.65) * load) * spin;
		} else if (k.family == kBankTurbine) {
			level = running ? R(0.7) * (R(0.015) + R(0.985) * e_pow(minf(ratio, 1.0), 2.6)) * spin : R(0.0);
			const godot::Vector3 exhaust = h.has(kKeyExhaust) ? h.vector[kKeyExhaust] : godot::Vector3();
			level = level * db_to_linear(table_db(kRoarDirectivity, 12, exhaust_angle_deg(exhaust, listener, source)) * R(0.45));
		}
		R references[kBankLayers];
		for (int i = 0; i < k.count; ++i) references[i] = k.has_rpm[i] ? k.rpm_reference[i] : maximum * R(0.65);
		band_weights(maxf(k.rpm, 1.0), references, k.count, k.weights);
		const R path_gain = distance_gain(R(double(distance(source, listener))));
		level = level * (db_to_linear(k.trim_db) * path_gain); // level *= db_to_linear(trim_db) * path_gain
		const R scene_gain = clampf(mix_gain, 0.0, 1.0);
		const R pitch_alpha = R(1.0) - R(e_exp((R(-dt.v) / R(0.035)).v));
		const bool stream_paused = paused && mix_gain.v <= 0.001;
		for (int i = 0; i < k.count; ++i) {
			const Bound &player = k.players[i];
			call_set(b.set_global_position, player, source);
			const R target = level * k.weights[i] * k.gain[i];
			k.levels[i] = lerpf(k.levels[i], target,
				R(1.0) - R(e_exp((R(-dt.v) / R(target.v > k.levels[i].v ? 0.08 : 0.12)).v)));
			call_set(b.set_volume_db, player, (linear_to_db(maxf(k.levels[i] * scene_gain, 0.00001)) - R(12.0)).v);
			const R pitch = clampf(k.rpm / references[i], 0.35, 2.5) * clampf(doppler_, 0.65, 1.5);
			call_set(b.set_pitch_scale, player,
				k.started ? lerpf(call_get_double(b.get_pitch_scale, player), pitch, pitch_alpha).v : pitch.v);
			if (!k.started && !paused) call_set(b.play, player, (R(double(i)) * R(0.173)).v);
			call_set(b.set_stream_paused, player, stream_paused);
		}
		if (!paused) k.started = true;
		k.accepted_rpm = accepted;
		k.running = running;
		k.level = level;
		k.distance_gain = path_gain;
		k.paused = paused;
	}

	// _level.
	void level(int index, R target) {
		const EngineBinds &b = engine_binds();
		levels_[index] = lerpf(levels_[index], target, level_alpha_);
		const R trim = index < 3 ? 12.0 : 0.0;
		R path_gain = 1.0;
		if (index < 3 && profile_) {
			const godot::Vector3 position = call_get_vector3(b.get_global_position, voices_[index]);
			path_gain = distance_gain(R(double(distance(position, previous_listener_)))) *
				R(call_get_double(b.get_unit_size, voices_[index])) / R(8.0);
		}
		call_set(b.set_volume_db, voices_[index], (linear_to_db(maxf(levels_[index] * gain_ * path_gain, 0.0001)) - trim).v);
	}

	// _pitch.
	void pitch(int index, R target, R alpha) {
		const EngineBinds &b = engine_binds();
		call_set(b.set_pitch_scale, voices_[index],
			lerpf(call_get_double(b.get_pitch_scale, voices_[index]), clampf(target, 0.1, 4.0), alpha).v);
	}

	bool bound_ = false;
	bool framed_ = false;
	Bound voices_[kVoices];
	Bound glow_;
	bool has_glow_ = false;
	Bound absorption_;
	Bound screen_;
	std::vector<godot::Vector3> trees_;
	std::vector<float> canopies_;
	int kind_ = kOtherKind;
	godot::Variant delayed_keys_[kDelayedCount];
	godot::Variant key_paused_, key_time_, key_listener_, key_sound_speed_, key_wind_direction_, key_wind_speed_, key_sun_,
		key_temperature_, key_pressure_, key_humidity_;
	godot::Variant missing_;

	std::vector<double> times_;
	std::vector<godot::Vector3> positions_;
	std::vector<Sample> samples_;
	size_t start_ = 0;
	Sample heard_;
	bool applied_[kDelayedCount] = {};
	bool heard_active_ = false;

	R gain_ = 0.0, clock_ = 0.0, screened_ = 0.0, screen_clock_ = 0.0, screen_goal_ = 0.0, doppler_ = 1.0, delay_ = 0.0;
	R cutoff_ = 0.0, absorption_target_ = 0.0, absorption_clock_ = 0.0;
	bool absorption_primed_ = false, primed_ = false, previous_paused_ = false;
	godot::Vector3 previous_source_, previous_listener_;
	R levels_[kVoices] = {};
	R presence_[5] = {};
	Targets targets_;
	R duck_ = 1.0, screen_gain_ = 1.0, level_alpha_ = 0.0;
	bool profile_ = false;

	struct Bank {
		Bound players[kBankLayers];
		int count = 0;
		bool has_rpm[kBankLayers] = {};
		R rpm_reference[kBankLayers] = {};
		R gain[kBankLayers] = {};
		int family = kBankOther;
		R profile_max_rpm = 12000.0;
		R trim_db = 0.0;
		R rpm = 0.0;
		bool primed = false;
		bool started = false;
		R levels[kBankLayers] = {};
		R weights[kBankLayers] = {};
		R accepted_rpm = 0.0;
		bool running = false;
		R level = 0.0;
		R distance_gain = 0.0;
		bool paused = false;
	};
	Bank bank_;
	bool has_bank_ = false;
};

} // namespace sound
} // namespace nk
