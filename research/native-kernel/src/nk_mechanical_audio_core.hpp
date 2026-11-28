// NK-7e: app/audio/mechanical_audio.gd in accepted-tick mode, with mechanical_motion.gd observe, exact. The core keeps
// the accepted observer and its queued transitions, the render view, the servo and retract motion voices' levels,
// the two event voices (pending cues, release envelopes, priorities, takes) and the gesture variations, and writes
// the players through the engine's method binds. GDScript creates the motion players, which appear lazily in channel
// order: a frame runs in two calls, and between them GDScript makes the players the frame asked for. Presentation
// only: nothing here reaches the simulation.
#pragma once

#include <cstdint>
#include <vector>

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/variant.hpp>

#include "nk_soundscape_core.hpp"

namespace nk {
namespace sound {

constexpr int kMechMaxChannels = 6;      // MechanicalMotion.MAX_CHANNELS
constexpr int kMechMaxMotionVoices = 6;  // MechanicalAudio.MAX_MOTION_VOICES
constexpr int kMechMaxEvents = 64;       // MAX_ACCEPTED_EVENTS
constexpr double kMechMaxRate = 10000.0;
constexpr double kMechMaxDistance = 60.0;
constexpr double kMechStaleLimit = 0.2;
constexpr double kMechMaxInterval = 0.25;

// One MechanicalMotion row (a channel, or the gear with target_down and status).
struct MechRow {
	godot::String id;
	double value = 0.0;
	godot::Vector3 position;
	bool position_valid = false;
	bool has_load = false;
	double load = 0.0;
	bool moving = false;
	double delta = 0.0;
	double speed = 0.0;
	int64_t direction = 0;
	bool target_down = false;
	godot::String status;
};

struct MechState {
	bool present = false;
	int64_t tick = 0;
	std::vector<MechRow> channels;
	bool has_gear = false;
	MechRow gear;
};

struct MechEvent {
	godot::String system, event, id;
	godot::Vector3 position;
	bool position_valid = false;
	double speed = 0.0;
	int64_t direction = 0;
	int64_t accepted_tick = 0;
};

struct MechResult {
	MechState state;
	std::vector<MechEvent> events;
	bool valid = false;
	bool primed = false;
	bool tick_advanced = false;
};

inline bool finite_number(const godot::Variant &value, double &out) {
	if (value.get_type() == godot::Variant::INT) {
		out = double(int64_t(value));
		return true;
	}
	if (value.get_type() == godot::Variant::FLOAT) {
		out = double(value);
		return std::isfinite(out);
	}
	return false;
}

inline bool finite_vector(const godot::Variant &value, godot::Vector3 &out) {
	if (value.get_type() != godot::Variant::VECTOR3) return false;
	out = value;
	return std::isfinite(out.x) && std::isfinite(out.y) && std::isfinite(out.z);
}

// GDScript bool(value) for the kinds the snapshot may hold.
inline bool truthy(const godot::Variant &value) { return value.booleanize(); }

class MechanicalCore {
public:
	MechanicalCore() {
		const char *names[] = {"tick", "tick_rate", "paused", "channels", "gear", "id", "angle_deg", "value", "position",
			"load", "available", "extension", "target_down", "target", "status", "since_tick", "listener", "engine_mask"};
		for (int i = 0; i < kKeyCount; ++i) keys_[i] = godot::String(names[i]);
	}

	// Event voices, motion loops' lengths, takes per role and the profile, as MechanicalAudio configured them, and its
	// counters, which survive resets: [tick samples, events observed, drained, discarded, overflowed, discontinuities,
	// events played, dropped, far-culled events, far-culled motion updates, stale resets, resets, then the five take
	// counters in role order].
	bool bind(const godot::Array &event_players, const godot::Variant &servo_loop, double servo_loop_length,
			const godot::Variant &gear_loop, double gear_loop_length, const godot::Array &takes, double servo_level,
			double profile_pitch, const godot::PackedInt64Array &counters) {
		const EngineBinds &b = engine_binds();
		bound_ = false;
		if (!b.ok || set_stream_method() == nullptr || event_players.size() > 2 || takes.size() != kRoleCount ||
				counters.size() != 12 + kRoleCount) {
			return false;
		}
		int64_t *targets[12] = {&tick_samples_, &events_observed_, &events_drained_, &events_discarded_,
			&events_overflowed_, &discontinuities_, &events_played_, &events_dropped_, &far_culled_events_,
			&far_culled_motion_updates_, &stale_tick_resets_, &reset_count_};
		for (int i = 0; i < 12; ++i) *targets[i] = counters[i];
		for (int i = 0; i < kRoleCount; ++i) take_counters_[i] = counters[12 + i];
		events_voices_.clear();
		for (int64_t i = 0; i < event_players.size(); ++i) {
			EventVoice voice;
			if (!bind_object(event_players[i], b.player_tag, voice.player)) return false;
			events_voices_.push_back(voice);
		}
		servo_loop_ = raw_object(servo_loop);
		gear_loop_ = raw_object(gear_loop);
		servo_loop_length_ = servo_loop_length;
		gear_loop_length_ = gear_loop_length;
		for (int role = 0; role < kRoleCount; ++role) {
			takes_[role].clear();
			const godot::Variant entry = takes[role];
			if (entry.get_type() != godot::Variant::ARRAY) return false;
			const godot::Array list = entry;
			for (int64_t i = 0; i < list.size(); ++i) {
				const GDExtensionObjectPtr stream = raw_object(list[i]);
				if (stream == nullptr) return false;
				takes_[role].push_back(stream);
			}
		}
		servo_level_ = servo_level;
		profile_pitch_ = profile_pitch;
		bound_ = true;
		return true;
	}

	// _ensure_motion_player made a player for this key (it holds the servo or gear loop).
	bool bind_motion_player(const godot::String &key, const godot::Variant &player) {
		if (motion_.size() >= size_t(kMechMaxMotionVoices)) return false;
		MotionVoice voice;
		voice.key = key;
		if (!bind_object(player, engine_binds().player_tag, voice.player)) return false;
		voice.length = key == "gear" ? gear_loop_length_ : servo_loop_length_;
		motion_.push_back(voice);
		return true;
	}

	// observe_accepted.
	bool observe(const godot::Dictionary &snapshot) {
		const godot::Variant tick_value = snapshot.get(keys_[kTick], godot::Variant());
		const godot::Variant rate_value = snapshot.get(keys_[kTickRate], godot::Variant());
		double rate = 0.0;
		if (tick_value.get_type() != godot::Variant::INT || int64_t(tick_value) < 0 ||
				int64_t(tick_value) > 9007199254740991LL || !finite_number(rate_value, rate) || rate < 1.0 ||
				rate > kMechMaxRate || snapshot.get(keys_[kPaused], godot::Variant()).get_type() != godot::Variant::BOOL) {
			clear_accepted();
			++discontinuities_;
			return false;
		}
		const int64_t tick = int64_t(tick_value);
		const bool paused = bool(snapshot[keys_[kPaused]]);
		const int64_t previous_tick = accepted_.present ? accepted_.tick : -1;
		if (accepted_.present && tick == previous_tick && !paused && rate == accepted_rate_) return true;
		bool continued = tick == previous_tick + 1;
		if (snapshot.has(keys_[kSinceTick])) {
			const godot::Variant since = snapshot[keys_[kSinceTick]];
			continued = since.get_type() == godot::Variant::INT && int64_t(since) >= 0 && int64_t(since) == previous_tick &&
				tick > previous_tick && (tick == previous_tick + 1 || double(tick - previous_tick) <= kMechMaxInterval * rate);
		}
		if (accepted_.present && ((tick != previous_tick && !continued) || rate != accepted_rate_)) {
			clear_accepted();
			++discontinuities_;
		}
		if (paused) discard_accepted_events();
		MechResult observed = motion_observe(accepted_, snapshot);
		if (!observed.valid) {
			clear_accepted();
			++discontinuities_;
			return false;
		}
		accepted_ = observed.state;
		accepted_rate_ = rate;
		accepted_primed_ = observed.primed;
		accepted_unrendered_ = accepted_unrendered_ || observed.tick_advanced;
		accepted_stale_tick_ = -1;
		if (tick != previous_tick) ++tick_samples_;
		for (const MechEvent &event : observed.events) {
			++events_observed_;
			if (accepted_events_.size() == size_t(kMechMaxEvents)) {
				accepted_events_.erase(accepted_events_.begin());
				++events_overflowed_;
				++events_discarded_;
			}
			accepted_events_.push_back(event);
			accepted_events_.back().accepted_tick = tick;
		}
		return true;
	}

	// The queued transitions as MechanicalAudio._accepted_events holds them (for inspection).
	godot::Array accepted_events() const {
		godot::Array out;
		for (const MechEvent &event : accepted_events_) {
			godot::Dictionary row;
			row[godot::StringName("system")] = event.system;
			row[godot::StringName("event")] = event.event;
			row[godot::StringName("id")] = event.id;
			row[godot::StringName("position")] = event.position;
			row[godot::StringName("position_valid")] = event.position_valid;
			row[godot::StringName("speed_per_s")] = event.speed;
			row[godot::StringName("direction")] = event.direction;
			row[godot::StringName("accepted_tick")] = event.accepted_tick;
			out.push_back(row);
		}
		return out;
	}

	// update_sound, first call: everything before the motion voices. Returns the motion keys whose players GDScript
	// must make now (in order), or an empty array; done() tells whether the frame already ended.
	godot::Array prepare(const godot::Dictionary &snapshot, double delta) {
		godot::Array need;
		frame_open_ = false;
		frame_done_ = true;
		if (!bound_ || !nodes_valid()) {
			failed_ = true;
			return need;
		}
		failed_ = false;
		const R safe_delta = (std::isfinite(delta) && delta > 0.0) ? R(delta) : R(0.0);
		dt_ = clampf(safe_delta, 0.0, 0.1);
		paused_ = truthy(snapshot.get(keys_[kPaused], false));
		const godot::Variant tick_variant = snapshot.get(keys_[kTick], godot::Variant());
		const int64_t incoming = (tick_variant.get_type() == godot::Variant::INT && int64_t(tick_variant) >= 0)
			? int64_t(tick_variant) : -1;
		if (incoming < 0) {
			clear_accepted();
			render_.present = false;
			stale_ = 0.0;
			fade_motion(dt_, true);
			stop_event_voices();
			targets_ = Targets();
			return need;
		}
		godot::Vector3 listener_value;
		const bool listener_finite = finite_vector(snapshot.get(keys_[kListener], godot::Variant()), listener_value);
		if (!paused_ && all_sources_distant(snapshot, listener_finite, listener_value)) {
			discard_accepted_events();
			render_.present = false;
			stale_ = 0.0;
			engine_mask_ = unit(snapshot.get(keys_[kEngineMask], 1.0), 1.0);
			fade_motion(dt_, false);
			stop_event_voices();
			++far_culled_motion_updates_;
			targets_ = Targets();
			targets_.valid = true;
			targets_.far_culled = true;
			targets_.short_form = true;
			targets_.tick = incoming;
			targets_.engine_mask = engine_mask_.v;
			targets_.listener = snapshot.get(keys_[kListener], godot::Vector3());
			return need;
		}
		if (paused_ || !render_.present) {
			stale_ = 0.0;
		} else if (incoming < render_.tick) {
			stale_ = 0.0;
		} else if (incoming == render_.tick) {
			stale_ = stale_ + dt_;
			if (stale_.v >= kMechStaleLimit) {
				accepted_stale_tick_ = incoming;
				render_.present = false;
				stale_ = 0.0;
				++stale_tick_resets_;
			}
		} else {
			stale_ = 0.0;
		}
		incoming_ = incoming;
		result_ = accepted_result(snapshot, incoming);
		if (!result_.valid) {
			render_.present = false;
			stale_ = 0.0;
			fade_motion(dt_, true);
			stop_event_voices();
			targets_ = Targets();
			return need;
		}
		render_ = result_.state;
		if (result_.tick_advanced || paused_) stale_ = 0.0;
		listener_valid_ = listener_finite;
		listener_ = listener_finite ? listener_value : godot::Vector3();
		engine_mask_ = unit(snapshot.get(keys_[kEngineMask], 1.0), 1.0);
		if (paused_) {
			scene_gain_ = maxf(0.0, scene_gain_ - dt_ / R(0.08));
			for (EventVoice &voice : events_voices_) voice.pending.present = false; // a queued reversal must not start
		} else {
			scene_gain_ = minf(1.0, scene_gain_ + dt_ / R(0.08));
		}
		const bool can_play = !paused_ && !result_.primed && result_.tick_advanced && listener_valid_;
		if (can_play) process_events();
		attack_ = dt_.v > 0.0 ? R(1.0) - R(e_exp((R(-dt_.v) / R(0.035)).v)) : R(0.0);
		release_ = dt_.v > 0.0 ? R(1.0) - R(e_exp((R(-dt_.v) / R(0.085)).v)) : R(0.0);
		pitch_alpha_ = dt_.v > 0.0 ? R(1.0) - R(e_exp((R(-dt_.v) / R(0.04)).v)) : R(1.0);
		// The motion voices' targets; keys without a player that need one are asked for, in order.
		plans_.clear();
		far_culled_ = false;
		for (const MechRow &row : render_.channels) {
			Plan plan;
			plan.key = godot::String("servo:") + row.id;
			plan.source_id = row.id;
			plan_row(row, false, plan);
			plans_.push_back(plan);
		}
		if (render_.has_gear) {
			Plan plan;
			plan.key = godot::String("gear");
			plan.source_id = godot::String("gear");
			plan_row(render_.gear, true, plan);
			plans_.push_back(plan);
		}
		for (const Plan &plan : plans_) {
			const bool has_loop = plan.gear ? gear_loop_ != nullptr : servo_loop_ != nullptr;
			if ((plan.target_gain.v > 0.0001 || motion_index(plan.key) >= 0) && has_loop && motion_index(plan.key) < 0) {
				need.push_back(plan.key);
			}
		}
		frame_open_ = true;
		frame_done_ = false;
		return need;
	}

	bool done() const { return frame_done_; }
	bool failed() const { return failed_; }

	// update_sound, second call: the motion voices, event voices and targets.
	bool finish() {
		if (!frame_open_) return !failed_;
		frame_open_ = false;
		frame_done_ = true;
		if (!nodes_valid()) {
			failed_ = true;
			return false;
		}
		const EngineBinds &b = engine_binds();
		int64_t active = 0;
		std::vector<bool> targeted(motion_.size(), false);
		for (const Plan &plan : plans_) {
			const int index = motion_index(plan.key);
			if (index < 0) continue;
			targeted[size_t(index)] = true;
			apply_motion_voice(size_t(index), plan.source_id, plan.position_valid ? plan.position : godot::Vector3(),
				plan.target_gain, plan.target_pitch);
			if (plan.target_gain.v > 0.001 && motion_[size_t(index)].gain > 0.001) ++active;
		}
		for (size_t i = 0; i < motion_.size(); ++i) {
			if (targeted[i]) continue;
			const MotionVoice &voice = motion_[i];
			const godot::String source = voice.key.begins_with("servo:") ? voice.key.trim_prefix("servo:") : godot::String("gear");
			apply_motion_voice(i, source, call_get_vector3(b.get_global_position, voice.player), 0.0, voice.pitch);
		}
		if (far_culled_) ++far_culled_motion_updates_;
		update_event_voices();
		if (scene_gain_.v <= 0.001) stop_event_voices();
		targets_ = Targets();
		targets_.valid = true;
		targets_.tick = incoming_;
		targets_.paused = paused_;
		targets_.engine_mask = engine_mask_.v;
		targets_.listener_valid = listener_valid_;
		targets_.active = active;
		targets_.far_culled = far_culled_;
		targets_.stale = stale_.v;
		targets_.voices = int64_t(motion_.size());
		targets_.listener = listener_;
		return true;
	}

	void reset() {
		const EngineBinds &b = engine_binds();
		clear_accepted();
		render_.present = false;
		scene_gain_ = 1.0;
		engine_mask_ = 1.0;
		stale_ = 0.0;
		gestures_.clear();
		++reset_count_;
		const bool valid = nodes_valid();
		for (MotionVoice &voice : motion_) {
			if (valid) {
				call_set(b.set_volume_db, voice.player, -80.0);
				call_void(b.stop, voice.player);
			}
			voice.gain = 0.0;
			voice.pitch = 1.0;
		}
		if (valid) {
			for (EventVoice &voice : events_voices_) {
				call_set(b.set_volume_db, voice.player, -80.0);
				call_void(b.stop, voice.player);
			}
		}
		clear_event_metadata();
		targets_ = Targets();
		frame_open_ = false;
	}

	// The counters and last targets diagnostics() reports, as a dictionary with its keys.
	godot::Dictionary diagnostics() const {
		godot::Dictionary out;
		out[godot::StringName("accepted_tick_samples")] = tick_samples_;
		out[godot::StringName("accepted_events_observed")] = events_observed_;
		out[godot::StringName("accepted_events_drained")] = events_drained_;
		out[godot::StringName("accepted_pending_event_count")] = int64_t(accepted_events_.size());
		out[godot::StringName("accepted_events_discarded")] = events_discarded_;
		out[godot::StringName("accepted_events_overflowed")] = events_overflowed_;
		out[godot::StringName("accepted_discontinuities")] = discontinuities_;
		int64_t pending = 0;
		for (const EventVoice &voice : events_voices_) pending += voice.pending.present ? 1 : 0;
		out[godot::StringName("pending_event_count")] = pending;
		out[godot::StringName("events_played")] = events_played_;
		out[godot::StringName("events_dropped")] = events_dropped_;
		out[godot::StringName("far_culled_events")] = far_culled_events_;
		out[godot::StringName("far_culled_motion_updates")] = far_culled_motion_updates_;
		out[godot::StringName("stale_tick_resets")] = stale_tick_resets_;
		out[godot::StringName("reset_count")] = reset_count_;
		out[godot::StringName("last_targets")] = last_targets();
		return out;
	}

	// For parity tests: each motion voice [key, gain, pitch, offset] and each event voice [role, source, base gain,
	// envelope, releasing, pending role, pending source], then the scene gain, engine mask and stale time.
	godot::Array state() const {
		godot::Array out;
		godot::Array motion;
		for (const MotionVoice &voice : motion_) {
			godot::Array row;
			row.push_back(voice.key);
			row.push_back(voice.gain);
			row.push_back(voice.pitch);
			row.push_back(voice.offset);
			motion.push_back(row);
		}
		godot::Array events;
		for (const EventVoice &voice : events_voices_) {
			godot::Array row;
			row.push_back(voice.role);
			row.push_back(voice.source);
			row.push_back(voice.base_gain);
			row.push_back(voice.envelope);
			row.push_back(voice.releasing);
			row.push_back(voice.pending.present ? voice.pending.role : godot::String());
			row.push_back(voice.pending.present ? voice.pending.source : godot::String());
			events.push_back(row);
		}
		out.push_back(motion);
		out.push_back(events);
		out.push_back(scene_gain_.v);
		out.push_back(engine_mask_.v);
		out.push_back(stale_.v);
		return out;
	}

private:
	enum Key : int {
		kTick, kTickRate, kPaused, kChannels, kGear, kId, kAngle, kValue, kPosition, kLoad, kAvailable, kExtension,
		kTargetDown, kTarget, kStatus, kSinceTick, kListener, kEngineMask, kKeyCount
	};
	enum Role : int { kServoStart, kServoStop, kGearMove, kGearStart, kGearLock, kRoleCount };

	struct Cue {
		bool present = false;
		godot::String role, source;
		int role_index = 0;
		GDExtensionObjectPtr stream = nullptr;
		godot::Vector3 position;
		double pitch = 1.0, gain = 0.0;
	};
	struct EventVoice {
		Bound player;
		godot::String role, source;
		double base_gain = 0.0, envelope = 1.0;
		bool releasing = false;
		Cue pending;
	};
	struct MotionVoice {
		godot::String key;
		Bound player;
		double length = 0.0;
		double gain = 0.0, pitch = 1.0, offset = 0.0;
	};
	struct Gesture {
		godot::String id;
		int64_t serial = 0;
		bool has_variation = false;
		double pitch = 1.0, phase = 0.0;
	};
	struct Plan {
		godot::String key, source_id;
		bool gear = false;
		godot::Vector3 position;
		bool position_valid = false;
		R target_gain = 0.0, target_pitch = 1.0;
	};
	struct Targets {
		bool valid = false, short_form = false, paused = false, listener_valid = false, far_culled = false;
		int64_t tick = 0, active = 0, voices = 0;
		double engine_mask = 1.0, stale = 0.0;
		godot::Vector3 listener;
	};

	static GDExtensionMethodBindPtr set_stream_method() {
		static const GDExtensionMethodBindPtr method = method_bind("AudioStreamPlayer3D", "set_stream", 2210767741);
		return method;
	}

	void set_stream(const Bound &player, GDExtensionObjectPtr stream) const {
		const GDExtensionConstTypePtr args[1] = {&stream};
		godot::gdextension_interface::object_method_bind_ptrcall(set_stream_method(), player.ptr, args, nullptr);
	}

	bool nodes_valid() const {
		for (const EventVoice &voice : events_voices_) {
			if (!voice.player.valid()) return false;
		}
		for (const MotionVoice &voice : motion_) {
			if (!voice.player.valid()) return false;
		}
		return true;
	}

	int motion_index(const godot::String &key) const {
		for (size_t i = 0; i < motion_.size(); ++i) {
			if (motion_[i].key == key) return int(i);
		}
		return -1;
	}

	static R unit(const godot::Variant &value, double fallback) {
		double x = 0.0;
		if (!finite_number(value, x)) return fallback;
		return clampf(x, 0.0, 1.0);
	}

	// MechanicalMotion._read_channels.
	std::vector<MechRow> read_channels(const godot::Variant &value) const {
		std::vector<MechRow> rows;
		if (value.get_type() != godot::Variant::ARRAY) return rows;
		const godot::Array items = value;
		for (int64_t i = 0; i < items.size(); ++i) {
			if (rows.size() >= size_t(kMechMaxChannels)) break;
			const godot::Variant item_value = items[i];
			if (item_value.get_type() != godot::Variant::DICTIONARY) continue;
			const godot::Dictionary item = item_value;
			const godot::String identity = godot::UtilityFunctions::str(item.get(keys_[kId], godot::String())).strip_edges();
			const godot::Variant angle = item.has(keys_[kAngle]) ? item[keys_[kAngle]] : item.get(keys_[kValue], godot::Variant());
			double angle_value = 0.0;
			bool seen = false;
			for (const MechRow &row : rows) seen = seen || row.id == identity;
			if (identity.is_empty() || seen || !finite_number(angle, angle_value)) continue;
			MechRow row;
			row.id = identity;
			row.value = angle_value;
			godot::Vector3 position;
			row.position_valid = finite_vector(item.get(keys_[kPosition], godot::Vector3()), position);
			row.position = row.position_valid ? position : godot::Vector3();
			double load = 0.0;
			if (finite_number(item.get(keys_[kLoad], godot::Variant()), load)) {
				row.has_load = true;
				row.load = clampf(load, 0.0, 1.0).v;
			}
			rows.push_back(row);
		}
		return rows;
	}

	// MechanicalMotion._read_gear; false for {}.
	bool read_gear(const godot::Variant &value, MechRow &row) const {
		if (value.get_type() != godot::Variant::DICTIONARY) return false;
		const godot::Dictionary gear = value;
		if (!truthy(gear.get(keys_[kAvailable], true))) return false;
		double extension = 0.0;
		if (!finite_number(gear.get(keys_[kExtension], godot::Variant()), extension)) return false;
		const godot::Variant target = gear.has(keys_[kTargetDown]) ? gear[keys_[kTargetDown]]
			: gear.get(keys_[kTarget], godot::Variant());
		bool target_down = false;
		double number = 0.0;
		if (target.get_type() == godot::Variant::BOOL) {
			target_down = bool(target);
		} else if (finite_number(target, number)) {
			target_down = number >= 0.5;
		} else if (target.get_type() == godot::Variant::STRING) {
			const godot::String lower = godot::String(target).to_lower();
			target_down = lower == "down" || lower == "extend" || lower == "extending";
		}
		godot::Vector3 position;
		row = MechRow();
		row.id = godot::String("gear");
		row.value = clampf(extension, 0.0, 1.0).v;
		row.target_down = target_down;
		row.position_valid = finite_vector(gear.get(keys_[kPosition], godot::Vector3()), position);
		row.position = row.position_valid ? position : godot::Vector3();
		row.status = godot::UtilityFunctions::str(gear.get(keys_[kStatus], godot::String()));
		return true;
	}

	static void set_stationary(MechRow &row) {
		row.moving = false;
		row.delta = 0.0;
		row.speed = 0.0;
		row.direction = 0;
	}

	// MechanicalMotion._measure_row.
	static void measure_row(MechRow &row, double previous_value, int64_t tick_delta, double rate, double epsilon) {
		const R travel = R(row.value) - R(previous_value);
		const bool moving = absf(travel).v > epsilon;
		row.delta = travel.v;
		row.speed = (absf(travel) * R(rate) / R(double(tick_delta))).v;
		row.direction = moving ? int64_t(travel.v > 0.0 ? 1 : (travel.v < 0.0 ? -1 : 0)) : 0;
		row.moving = moving;
	}

	// MechanicalMotion._transition_kind.
	static const char *transition(const MechRow &old, const MechRow &row, bool endpoint_locked) {
		if (row.moving) {
			if (old.moving && row.direction != old.direction) return "reverse";
			if (!old.moving) return "start";
			return "";
		}
		if (old.moving) return endpoint_locked ? "lock" : "stop";
		return "";
	}

	static const MechRow *find_row(const std::vector<MechRow> &rows, const godot::String &id) {
		for (const MechRow &row : rows) {
			if (row.id == id) return &row;
		}
		return nullptr;
	}

	// MechanicalMotion._refresh_motion.
	static void refresh_motion(MechRow &row, const MechRow *old) {
		if (old == nullptr) {
			set_stationary(row);
			return;
		}
		row.value = old->value;
		row.delta = old->delta;
		row.speed = old->speed;
		row.moving = old->moving;
		row.direction = old->direction;
		row.has_load = old->has_load;
		row.load = old->load;
	}

	static MechEvent make_event(const char *system, const char *kind, const MechRow &row) {
		MechEvent event;
		event.system = godot::String(system);
		event.event = godot::String(kind);
		event.id = row.id;
		event.position = row.position;
		event.position_valid = row.position_valid;
		event.speed = row.speed;
		event.direction = row.direction;
		return event;
	}

	// MechanicalMotion.observe.
	MechResult motion_observe(const MechState &previous, const godot::Dictionary &snapshot) const {
		MechResult out;
		const godot::Variant tick_value = snapshot.get(keys_[kTick], godot::Variant());
		double tick_number = 0.0;
		if (!finite_number(tick_value, tick_number) || tick_number < 0.0) {
			out.state = previous;
			return out;
		}
		const int64_t tick = tick_value.get_type() == godot::Variant::INT ? int64_t(tick_value) : int64_t(tick_number);
		double rate_number = 0.0;
		const double rate = (finite_number(snapshot.get(keys_[kTickRate], 240.0), rate_number) && rate_number > 0.0)
			? std::max(1.0, rate_number) : 240.0;
		const bool paused = truthy(snapshot.get(keys_[kPaused], false));
		std::vector<MechRow> rows = read_channels(snapshot.get(keys_[kChannels], godot::Array()));
		MechRow gear;
		const bool has_gear = read_gear(snapshot.get(keys_[kGear], godot::Dictionary()), gear);
		const int64_t old_tick = previous.present ? previous.tick : -1;
		out.valid = true;
		if (!previous.present || old_tick < 0 || tick < old_tick || paused) {
			for (MechRow &row : rows) set_stationary(row);
			if (has_gear) set_stationary(gear);
			out.state.present = true;
			out.state.tick = tick;
			out.state.channels = rows;
			out.state.has_gear = has_gear;
			out.state.gear = gear;
			out.primed = true;
			return out;
		}
		const int64_t tick_delta = tick - old_tick;
		if (tick_delta == 0) {
			for (MechRow &row : rows) refresh_motion(row, find_row(previous.channels, row.id));
			if (has_gear) refresh_motion(gear, previous.has_gear ? &previous.gear : nullptr);
			out.state.present = true;
			out.state.tick = previous.tick;
			out.state.channels = rows;
			out.state.has_gear = has_gear;
			out.state.gear = gear;
			return out;
		}
		const double angular_floor = (R(0.2) * R(double(tick_delta)) / R(rate)).v; // SERVO_SPEED_FLOOR_DEG_S
		for (MechRow &row : rows) {
			const MechRow *old = find_row(previous.channels, row.id);
			const char *kind = "";
			if (old == nullptr) {
				set_stationary(row);
			} else {
				measure_row(row, old->value, tick_delta, rate, angular_floor);
				kind = transition(*old, row, false);
			}
			if (kind[0] != '\0') out.events.push_back(make_event("servo", kind, row));
		}
		if (has_gear) {
			const char *kind = "";
			if (!previous.has_gear) {
				set_stationary(gear);
			} else {
				measure_row(gear, previous.gear.value, tick_delta, rate, 0.000001); // EXTENSION_EPSILON
				const bool locked = std::isfinite(gear.value) &&
					(gear.target_down ? absf(R(gear.value) - R(1.0)).v <= 0.000001 : absf(gear.value).v <= 0.000001);
				kind = transition(previous.gear, gear, locked);
			}
			if (kind[0] != '\0') out.events.push_back(make_event("gear", kind, gear));
		}
		out.state.present = true;
		out.state.tick = tick;
		out.state.channels = rows;
		out.state.has_gear = has_gear;
		out.state.gear = gear;
		out.tick_advanced = true;
		return out;
	}

	void discard_accepted_events() {
		events_discarded_ += int64_t(accepted_events_.size());
		accepted_events_.clear();
		accepted_unrendered_ = false;
	}

	void clear_accepted() {
		discard_accepted_events();
		accepted_ = MechState();
		accepted_rate_ = 0.0;
		accepted_primed_ = true;
		accepted_stale_tick_ = -1;
	}

	// _accepted_result.
	MechResult accepted_result(const godot::Dictionary &snapshot, int64_t tick) {
		MechResult out;
		if (!accepted_.present || tick != accepted_.tick) {
			clear_accepted();
			return out;
		}
		if (truthy(snapshot.get(keys_[kPaused], false))) {
			discard_accepted_events();
			MechResult primed = motion_observe(MechState(), snapshot);
			accepted_ = primed.state;
			accepted_primed_ = true;
			return primed;
		}
		if (accepted_stale_tick_ == tick) {
			discard_accepted_events();
			return motion_observe(MechState(), snapshot);
		}
		out = motion_observe(accepted_, snapshot);
		out.events = accepted_events_;
		out.primed = accepted_primed_;
		out.tick_advanced = accepted_unrendered_;
		events_drained_ += int64_t(accepted_events_.size());
		accepted_events_.clear();
		accepted_unrendered_ = false;
		return out;
	}

	bool all_sources_distant(const godot::Dictionary &snapshot, bool listener_finite, const godot::Vector3 &listener) const {
		if (!listener_finite) return false;
		const godot::Variant channels = snapshot.get(keys_[kChannels], godot::Array());
		if (channels.get_type() == godot::Variant::ARRAY) {
			const godot::Array items = channels;
			for (int64_t i = 0; i < items.size(); ++i) {
				const godot::Variant item = items[i];
				if (item.get_type() != godot::Variant::DICTIONARY) continue;
				godot::Vector3 position;
				if (finite_vector(godot::Dictionary(item).get(keys_[kPosition], godot::Variant()), position) &&
						double(distance_squared(position, listener)) < kMechMaxDistance * kMechMaxDistance) {
					return false;
				}
			}
		}
		const godot::Variant gear = snapshot.get(keys_[kGear], godot::Dictionary());
		if (gear.get_type() == godot::Variant::DICTIONARY) {
			const godot::Dictionary g = gear;
			godot::Vector3 position;
			if (truthy(g.get(keys_[kAvailable], true)) && finite_vector(g.get(keys_[kPosition], godot::Variant()), position) &&
					double(distance_squared(position, listener)) < kMechMaxDistance * kMechMaxDistance) {
				return false;
			}
		}
		return true;
	}

	static R mech_distance_gain(double d) {
		if (!std::isfinite(d) || d < 0.0 || d >= kMechMaxDistance) return 0.0;
		const R model = R(2.0) / maxf(d, 2.0);
		const R fade = R(1.0) - smoothstep(39.0, 60.0, d);
		return model * fade;
	}

	R servo_gain(R speed) const {
		const R mix = sqrt_(clampf(speed / R(180.0), 0.0, 1.0));
		return R(0.16) * clampf(servo_level_, 0.0, 1.0) * (R(0.2) + R(0.8) * mix);
	}
	R servo_pitch(R speed) const {
		const R mix = sqrt_(clampf(speed / R(180.0), 0.0, 1.0));
		return clampf((R(0.78) + R(0.48) * mix) * R(profile_pitch_), 0.55, 1.35);
	}
	static R gear_gain(R speed) {
		const R mix = sqrt_(clampf(speed / R(0.6), 0.0, 1.0));
		return R(0.22) * (R(0.25) + R(0.75) * mix);
	}
	static R gear_pitch(R speed) {
		const R mix = sqrt_(clampf(speed / R(0.6), 0.0, 1.0));
		return clampf(R(0.82) + R(0.36) * mix, 0.7, 1.35);
	}

	void plan_row(const MechRow &row, bool gear, Plan &plan) {
		plan.gear = gear;
		const bool source_valid = row.position_valid; // rows hold validated positions
		plan.position = row.position;
		plan.position_valid = source_valid;
		const double distance_m = (source_valid && listener_valid_) ? double(distance(row.position, listener_))
			: std::numeric_limits<double>::infinity();
		const bool near = source_valid && listener_valid_ && distance_m < kMechMaxDistance;
		plan.target_gain = 0.0;
		plan.target_pitch = 1.0;
		const bool can_move = gear ? gear_loop_ != nullptr : true;
		if (near && !paused_ && row.moving && can_move) {
			if (gear) {
				plan.target_gain = gear_gain(row.speed) * engine_mask_ * mech_distance_gain(distance_m);
				plan.target_pitch = gear_pitch(row.speed);
			} else {
				plan.target_gain = servo_gain(row.speed) * engine_mask_ * mech_distance_gain(distance_m);
				plan.target_pitch = servo_pitch(row.speed);
			}
		} else if (source_valid && !near) {
			far_culled_ = true;
		}
	}

	const Gesture *find_gesture(const godot::String &id) const {
		for (const Gesture &gesture : gestures_) {
			if (gesture.id == id) return &gesture;
		}
		return nullptr;
	}

	// _advance_gesture.
	void advance_gesture(const godot::String &id) {
		Gesture *gesture = nullptr;
		for (Gesture &g : gestures_) {
			if (g.id == id) gesture = &g;
		}
		if (gesture == nullptr) {
			gestures_.push_back(Gesture());
			gesture = &gestures_.back();
			gesture->id = id;
		}
		gesture->serial += 1;
		const int64_t stable = id.hash() & 0x7fffffff;
		const int64_t pitch_index = (stable + gesture->serial * 313) % 1001;
		const int64_t phase_index = (stable + gesture->serial * 577) % 997;
		gesture->has_variation = true;
		gesture->pitch = (R(0.98) + R(0.04) * R(double(pitch_index)) / R(1000.0)).v;
		gesture->phase = (R(double(phase_index)) / R(997.0)).v;
	}

	double variation_pitch(const godot::String &id) const {
		const Gesture *g = find_gesture(id);
		return (g != nullptr && g->has_variation) ? g->pitch : 1.0;
	}

	// _apply_motion_voice.
	void apply_motion_voice(size_t index, const godot::String &source_id, const godot::Vector3 &position, R target_gain,
			R target_pitch) {
		const EngineBinds &b = engine_binds();
		MotionVoice &voice = motion_[index];
		R current = voice.gain;
		if (target_gain.v <= 0.0001 && current.v <= 0.0002 && !call_get_bool(b.is_playing, voice.player)) return;
		call_set(b.set_global_position, voice.player, position);
		const R alpha = target_gain.v > current.v ? attack_ : release_;
		current = lerpf(current, clampf(target_gain, 0.0, 1.0), alpha);
		const Gesture *g = find_gesture(source_id);
		const R variation_pitch_value = (g != nullptr && g->has_variation) ? R(g->pitch) : R(1.0);
		const R variation_phase = (g != nullptr && g->has_variation) ? R(g->phase) : R(0.0);
		const R varied_pitch = target_pitch * variation_pitch_value;
		const R pitch = lerpf(voice.pitch, varied_pitch, pitch_alpha_);
		voice.gain = current.v;
		voice.pitch = pitch.v;
		call_set(b.set_volume_db, voice.player, linear_to_db(maxf(current * scene_gain_, 0.00001)).v);
		call_set(b.set_pitch_scale, voice.player, pitch.v);
		if (target_gain.v > 0.0001 && !call_get_bool(b.is_playing, voice.player)) {
			const R length = maxf(voice.length, 0.001);
			voice.offset = (length * clampf(variation_phase, 0.0, 0.999)).v;
			call_set(b.play, voice.player, voice.offset);
		} else if ((current.v <= 0.0002 || scene_gain_.v <= 0.001) && target_gain.v <= 0.0001 &&
				call_get_bool(b.is_playing, voice.player)) {
			stop_motion_player(index);
		}
	}

	void stop_motion_player(size_t index) {
		const EngineBinds &b = engine_binds();
		call_set(b.set_volume_db, motion_[index].player, -80.0);
		call_void(b.stop, motion_[index].player);
		motion_[index].gain = 0.0;
	}

	// _fade_motion.
	void fade_motion(R delta, bool immediate) {
		const EngineBinds &b = engine_binds();
		const R clamped = clampf(delta, 0.0, 0.1);
		scene_gain_ = immediate ? R(0.0) : maxf(0.0, scene_gain_ - clamped / R(0.08));
		const R alpha = R(1.0) - R(e_exp((R(-clamped.v) / R(0.08)).v));
		for (size_t i = 0; i < motion_.size(); ++i) {
			MotionVoice &voice = motion_[i];
			if (!call_get_bool(b.is_playing, voice.player) && voice.gain <= 0.0002) continue;
			const R gain = immediate ? R(0.0) : lerpf(voice.gain, 0.0, alpha);
			voice.gain = gain.v;
			call_set(b.set_volume_db, voice.player, linear_to_db(maxf(gain * scene_gain_, 0.00001)).v);
			if (immediate || scene_gain_.v <= 0.001 || gain.v <= 0.0002) stop_motion_player(i);
		}
		if (immediate || scene_gain_.v <= 0.001) stop_event_voices();
	}

	void clear_event_metadata() {
		for (EventVoice &voice : events_voices_) {
			voice.role = godot::String();
			voice.source = godot::String();
			voice.base_gain = 0.0;
			voice.envelope = 1.0;
			voice.releasing = false;
			voice.pending.present = false;
		}
	}

	void stop_event_voices() {
		const EngineBinds &b = engine_binds();
		for (EventVoice &voice : events_voices_) {
			if (call_get_bool(b.is_playing, voice.player)) {
				call_set(b.set_volume_db, voice.player, -80.0);
				call_void(b.stop, voice.player);
			}
		}
		clear_event_metadata();
	}

	static int priority(const godot::String &role) {
		return role == "gear_lock" ? 3 : (role.begins_with("gear_") ? 2 : (role == "servo_start" ? 1 : 0));
	}

	static int role_index(const godot::String &role) {
		if (role == "servo_start") return kServoStart;
		if (role == "servo_stop") return kServoStop;
		if (role == "gear_move") return kGearMove;
		if (role == "gear_start") return kGearStart;
		return kGearLock;
	}

	// _next_event_take.
	GDExtensionObjectPtr next_take(int role) {
		if (takes_[role].empty()) return nullptr;
		const int64_t index = take_counters_[role];
		take_counters_[role] = index + 1;
		return takes_[role][size_t(index % int64_t(takes_[role].size()))];
	}

	const MechRow *source_row(const godot::String &id) const {
		if (id == "gear" && render_.has_gear) {
			// _source_positions: channel rows first, then the gear under "gear" (it replaces a channel named "gear").
			return &render_.gear;
		}
		return find_row(render_.channels, id);
	}

	// _process_events.
	void process_events() {
		for (const MechEvent &event : result_.events) {
			const godot::String source_id = event.id;
			const MechRow *source = source_row(source_id);
			if (source == nullptr || !source->position_valid) continue;
			const godot::Vector3 position = source->position;
			const R path = mech_distance_gain(double(distance(position, listener_)));
			if (path.v <= 0.0001) {
				++far_culled_events_;
				continue;
			}
			const R speed = event.speed;
			R gain = 0.0;
			R pitch = 1.0;
			godot::String role;
			if (event.system == "servo") {
				if (event.event == "start" || event.event == "reverse") {
					advance_gesture(source_id);
					role = godot::String("servo_start");
				} else if (event.event == "stop") {
					role = godot::String("servo_stop");
				}
				gain = servo_gain(speed);
				pitch = servo_pitch(speed) * R(variation_pitch(source_id));
			} else {
				if (event.event == "stop") cancel_source_events(source_id);
				gain = gear_gain(speed);
				pitch = gear_pitch(speed);
				if (event.event == "start" || event.event == "reverse") {
					advance_gesture(godot::String("gear"));
					pitch = pitch * R(variation_pitch(godot::String("gear")));
					if (gear_loop_ != nullptr) {
						role = godot::String("gear_start");
					} else if (!takes_[kGearMove].empty()) {
						role = godot::String("gear_move");
					} else {
						role = godot::String("gear_start");
					}
				} else if (event.event == "lock") {
					role = godot::String("gear_lock");
				}
			}
			if (!role.is_empty()) play_event(role, source_id, position, gain, pitch);
		}
	}

	void cancel_source_events(const godot::String &source_id) {
		for (EventVoice &voice : events_voices_) {
			if (voice.pending.present && voice.pending.source == source_id) voice.pending.present = false;
			if (voice.source == source_id) voice.releasing = true;
		}
	}

	// _play_event.
	void play_event(const godot::String &role, const godot::String &source_id, const godot::Vector3 &position, R gain, R pitch) {
		const EngineBinds &b = engine_binds();
		if (events_voices_.empty() || gain.v <= 0.0001) return;
		const R effective = gain * engine_mask_ * mech_distance_gain(double(distance(position, listener_))) * scene_gain_;
		if (effective.v <= 0.0001) return;
		int chosen = -1;
		for (size_t i = 0; i < events_voices_.size(); ++i) {
			const EventVoice &voice = events_voices_[i];
			if ((voice.pending.present && voice.pending.source == source_id) || (!voice.pending.present && voice.source == source_id)) {
				chosen = int(i);
				break;
			}
		}
		if (chosen < 0) {
			for (size_t i = 0; i < events_voices_.size(); ++i) {
				if (!call_get_bool(b.is_playing, events_voices_[i].player) && !events_voices_[i].pending.present) {
					chosen = int(i);
					break;
				}
			}
		}
		if (chosen < 0) {
			int lowest = priority(role);
			for (size_t i = 0; i < events_voices_.size(); ++i) {
				const EventVoice &voice = events_voices_[i];
				const int p = priority(voice.pending.present ? voice.pending.role : voice.role);
				if (p < lowest) {
					lowest = p;
					chosen = int(i);
				}
			}
		}
		if (chosen < 0) {
			++events_dropped_;
			return;
		}
		const int index = role_index(role);
		const GDExtensionObjectPtr stream = next_take(index);
		if (stream == nullptr) return;
		Cue cue;
		cue.present = true;
		cue.role = role;
		cue.role_index = index;
		cue.source = source_id;
		cue.stream = stream;
		cue.position = position;
		cue.pitch = pitch.v;
		cue.gain = gain.v;
		EventVoice &voice = events_voices_[size_t(chosen)];
		if (call_get_bool(b.is_playing, voice.player)) {
			// Retire the previous cue before replacing it: bounded voices, no hard waveform cut.
			voice.pending = cue;
			voice.releasing = true;
		} else {
			begin_event(voice, cue, effective);
		}
	}

	// _begin_event.
	void begin_event(EventVoice &voice, const Cue &cue, R effective_gain) {
		const EngineBinds &b = engine_binds();
		set_stream(voice.player, cue.stream);
		call_set(b.set_global_position, voice.player, cue.position);
		call_set(b.set_pitch_scale, voice.player, clampf(cue.pitch, 0.55, 1.5).v);
		call_set(b.set_volume_db, voice.player, linear_to_db(maxf(effective_gain, 0.00001)).v);
		voice.role = cue.role;
		voice.source = cue.source;
		voice.base_gain = cue.gain;
		voice.envelope = 1.0;
		voice.releasing = false;
		voice.pending.present = false;
		call_set(b.play, voice.player, 0.0);
		++events_played_;
	}

	void silence(EventVoice &voice) {
		voice.role = godot::String();
		voice.source = godot::String();
		voice.base_gain = 0.0;
	}

	// _update_event_voices.
	void update_event_voices() {
		const EngineBinds &b = engine_binds();
		for (EventVoice &voice : events_voices_) {
			if (voice.role.is_empty() && !voice.pending.present && !call_get_bool(b.is_playing, voice.player)) continue;
			if (voice.releasing) {
				voice.envelope = maxf(0.0, R(voice.envelope) - dt_ / R(0.02)).v; // EVENT_RELEASE_S
				if (voice.envelope <= 0.0) {
					call_set(b.set_volume_db, voice.player, -80.0);
					call_void(b.stop, voice.player);
				}
			}
			if (!call_get_bool(b.is_playing, voice.player) && voice.pending.present) {
				Cue cue = voice.pending;
				voice.pending.present = false;
				const MechRow *pending_source = source_row(cue.source);
				if (listener_valid_ && pending_source != nullptr && pending_source->position_valid && scene_gain_.v > 0.001) {
					cue.position = pending_source->position;
					const R pending_gain = R(cue.gain) * engine_mask_ * scene_gain_ *
						mech_distance_gain(double(distance(cue.position, listener_)));
					if (pending_gain.v > 0.0001) begin_event(voice, cue, pending_gain);
				}
			}
			if (!call_get_bool(b.is_playing, voice.player)) {
				silence(voice);
				voice.releasing = false;
				call_set(b.set_volume_db, voice.player, -80.0);
				continue;
			}
			const MechRow *source = source_row(voice.source);
			if (!listener_valid_ || source == nullptr || !source->position_valid) {
				call_set(b.set_volume_db, voice.player, -80.0);
				call_void(b.stop, voice.player);
				silence(voice);
				continue;
			}
			const godot::Vector3 position = source->position;
			call_set(b.set_global_position, voice.player, position);
			const R path = mech_distance_gain(double(distance(position, listener_)));
			if (path.v <= 0.0001) {
				call_set(b.set_volume_db, voice.player, -80.0);
				call_void(b.stop, voice.player);
				silence(voice);
				continue;
			}
			const R audible = R(voice.base_gain) * R(voice.envelope) * engine_mask_ * path * scene_gain_;
			call_set(b.set_volume_db, voice.player, linear_to_db(maxf(audible, 0.00001)).v);
		}
	}

	godot::Dictionary last_targets() const {
		godot::Dictionary out;
		if (!targets_.valid) {
			out[godot::StringName("valid")] = false;
			out[godot::StringName("active_motion_voices")] = int64_t(0);
			return out;
		}
		out[godot::StringName("valid")] = true;
		out[godot::StringName("tick")] = targets_.tick;
		if (targets_.short_form) {
			out[godot::StringName("paused")] = false;
			out[godot::StringName("far_culled")] = true;
			out[godot::StringName("engine_mask")] = targets_.engine_mask;
			out[godot::StringName("active_motion_voices")] = int64_t(0);
			out[godot::StringName("listener")] = targets_.listener;
			return out;
		}
		out[godot::StringName("paused")] = targets_.paused;
		out[godot::StringName("engine_mask")] = targets_.engine_mask;
		out[godot::StringName("listener_valid")] = targets_.listener_valid;
		out[godot::StringName("active_motion_voices")] = targets_.active;
		out[godot::StringName("far_culled")] = targets_.far_culled;
		out[godot::StringName("stale_tick_s")] = targets_.stale;
		out[godot::StringName("motion_voice_count")] = targets_.voices;
		out[godot::StringName("listener")] = targets_.listener;
		return out;
	}

	godot::Variant keys_[kKeyCount];
	bool bound_ = false;
	std::vector<EventVoice> events_voices_;
	std::vector<MotionVoice> motion_;
	GDExtensionObjectPtr servo_loop_ = nullptr, gear_loop_ = nullptr;
	double servo_loop_length_ = 0.0, gear_loop_length_ = 0.0;
	std::vector<GDExtensionObjectPtr> takes_[kRoleCount];
	int64_t take_counters_[kRoleCount] = {};
	double servo_level_ = 1.0, profile_pitch_ = 1.0;
	std::vector<Gesture> gestures_;

	MechState accepted_;
	std::vector<MechEvent> accepted_events_;
	double accepted_rate_ = 0.0;
	bool accepted_primed_ = true, accepted_unrendered_ = false;
	int64_t accepted_stale_tick_ = -1;
	int64_t tick_samples_ = 0, events_observed_ = 0, events_drained_ = 0, events_discarded_ = 0, events_overflowed_ = 0;
	int64_t discontinuities_ = 0;

	MechState render_;
	MechResult result_;
	std::vector<Plan> plans_;
	R dt_ = 0.0, stale_ = 0.0, scene_gain_ = 1.0, engine_mask_ = 1.0, attack_ = 0.0, release_ = 0.0, pitch_alpha_ = 0.0;
	bool paused_ = false, listener_valid_ = false, far_culled_ = false;
	godot::Vector3 listener_;
	bool frame_open_ = false, frame_done_ = true, failed_ = false;
	int64_t incoming_ = 0;
	Targets targets_;
	int64_t events_played_ = 0, events_dropped_ = 0, far_culled_events_ = 0, far_culled_motion_updates_ = 0;
	int64_t stale_tick_resets_ = 0, reset_count_ = 0;
};

} // namespace sound
} // namespace nk
