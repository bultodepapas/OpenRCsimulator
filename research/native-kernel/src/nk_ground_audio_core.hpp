// NK-7d: app/audio/ground_audio.gd in accepted-tick mode (with ground_audio_motion.gd advance), exact. The core keeps
// the accepted wheel states, queued touchdowns, skipped-tick approaches and each slot's roll levels, and writes the
// slots' roll and touchdown players through the engine's method binds. GDScript creates the slots (players, names,
// offsets) in the order ground_audio.gd would, through ground_core_pending_slots, and keeps the legacy render mode.
// A snapshot ground_audio.gd would refuse is refused the same way. Presentation only: nothing here reaches the
// simulation.
#pragma once

#include <cstdint>
#include <vector>

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

#include "nk_soundscape_core.hpp"

namespace nk {
namespace sound {

constexpr int kGroundMaxContacts = 8;          // GroundAudio.MAX_CONTACTS
constexpr int kGroundMaxEvents = 64;           // GroundAudio.MAX_ACCEPTED_EVENTS
constexpr double kGroundMaxRate = 10000.0;     // GroundAudio.MAX_ACCEPTED_RATE_HZ
constexpr double kGroundMaxEventAge = 0.25;    // GroundAudio.MAX_EVENT_AGE_S
constexpr double kGroundMaxInterval = 0.25;    // GroundAudio.MAX_ACCEPTED_INTERVAL_S
constexpr double kGroundCompressionMargin = 1e-6;

// ground_audio_motion.gd state (a missing dictionary is `present == false`).
struct WheelState {
	bool present = false;
	bool initialized = false;
	bool grounded = false;
	double airborne = 0.0;
	double previous_approach = 0.0;
	double cooldown = 0.0;
};

struct GroundContact {
	godot::String id;
	godot::Vector3 position;
	double normal_force = 0.0;
	double reference_load = 0.0;
	double approach = 0.0;
	double rolling = 0.0;
	godot::String surface;
	bool roll_enabled = true;
};

struct WheelAdvance {
	WheelState state;
	R force = 0.0, reference = 0.0, force_off = 0.0, impact_approach = -1.0;
};

// GroundAudioMotion.advance for a contact that carries normal_force_n (every accepted contact does).
inline WheelAdvance wheel_advance(const GroundContact &contact, WheelState state, R state_delta, bool seed_only,
		bool tick_advanced, R airborne_onset_delta = -1.0) {
	WheelAdvance out;
	R impact_approach = -1.0;
	const R force = maxf(0.0, contact.normal_force);
	const R reference = maxf(1.0, contact.reference_load);
	const R force_on = maxf(3.0, reference * R(0.035));
	const R force_off = maxf(1.0, reference * R(0.018));
	const bool candidate_grounded = force.v >= force_on.v;
	const R approach_now = maxf(0.0, contact.approach);
	bool was_grounded = state.grounded;
	R cooldown = maxf(0.0, R(state.cooldown) - state_delta);
	R airborne = state.airborne;
	R previous_approach = state.previous_approach;
	if (seed_only || !state.initialized) {
		was_grounded = force.v >= force_on.v;
		state.grounded = was_grounded;
		state.airborne = 0.0;
		state.previous_approach = 0.0;
		state.cooldown = 0.0;
		state.initialized = true;
	} else {
		const bool next_grounded = was_grounded ? force.v >= force_off.v : candidate_grounded;
		if (next_grounded && !was_grounded) {
			const R approach = maxf(previous_approach, approach_now);
			if (tick_advanced && !seed_only && airborne.v >= 0.14 && cooldown.v <= 0.0 && approach.v >= 0.2) {
				impact_approach = approach;
				cooldown = 0.65;
			}
			airborne = 0.0;
			previous_approach = 0.0;
		} else if (!next_grounded) {
			airborne = airborne + ((was_grounded && airborne_onset_delta.v >= 0.0) ? minf(state_delta, airborne_onset_delta)
				: state_delta);
			if (tick_advanced) previous_approach = approach_now;
		}
		state.grounded = next_grounded;
		state.airborne = airborne.v;
		state.previous_approach = previous_approach.v;
		state.cooldown = cooldown.v;
		state.initialized = true;
	}
	state.present = true;
	out.state = state;
	out.force = force;
	out.reference = reference;
	out.force_off = force_off;
	out.impact_approach = impact_approach;
	return out;
}

class GroundCore {
public:
	GroundCore() {
		key_since_ = godot::String("since_tick");
		key_tick_ = godot::String("tick");
		key_rate_ = godot::String("tick_rate");
		key_paused_ = godot::String("paused");
		key_contacts_ = godot::String("contacts");
		key_id_ = godot::String("id");
		key_position_ = godot::String("position");
		key_force_ = godot::String("normal_force_n");
		key_reference_ = godot::String("reference_load_n");
		key_approach_ = godot::String("approach_speed_mps");
		key_rolling_ = godot::String("rolling_speed_mps");
		key_surface_ = godot::String("surface");
		key_grounded_ = godot::String("grounded");
		key_roll_ = godot::String("roll_enabled");
	}

	// ground_core_bind_slot: one slot as GroundAudio._slot_for made it.
	bool bind_slot(const godot::String &id, const godot::Array &roll, const godot::Variant &impact, double roll_offset,
			const godot::PackedFloat64Array &stream_lengths) {
		const EngineBinds &b = engine_binds();
		if (!b.ok || roll.size() != 3 || stream_lengths.size() != 3 || slots_.size() >= kGroundMaxContacts) return false;
		Slot slot;
		slot.id = id;
		for (int i = 0; i < 3; ++i) {
			if (!bind_object(roll[i], b.player_tag, slot.roll[i])) return false;
			slot.length[i] = stream_lengths[i];
		}
		if (!bind_object(impact, b.player_tag, slot.impact)) return false;
		slot.offset = roll_offset;
		slots_.push_back(slot);
		return true;
	}

	// observe_accepted. 1 accepted, 0 refused (as ground_audio.gd refuses).
	bool observe(const godot::Dictionary &snapshot) {
		Observation in;
		if (!read_snapshot(snapshot, in)) {
			clear_accepted();
			++refused_;
			return false;
		}
		const int64_t tick = in.tick;
		const double rate = in.rate;
		if (tick == accepted_tick_ && rate == accepted_rate_ && !in.paused) return true;
		const int64_t since = in.has_since ? in.since : tick - 1;
		const bool discontinuity = since < 0 || since != accepted_tick_ || tick <= since ||
			(tick - since > 1 && double(tick - since) > kGroundMaxInterval * rate) || rate != accepted_rate_;
		const bool seed_only = accepted_tick_ < 0 || discontinuity || in.paused || accepted_paused_;
		if (discontinuity || in.paused) clear_accepted();
		std::vector<std::pair<godot::String, WheelState>> next_states;
		for (const GroundContact &contact : in.contacts) {
			WheelState previous = state_for(contact.id);
			if (!seed_only && skipped_tick_ == tick - 1 && skipped_tick_ > since && previous.initialized &&
					!previous.grounded) {
				double approach = 0.0;
				if (skipped_approach(contact.id, approach)) previous.previous_approach = approach;
			}
			const WheelAdvance observed = wheel_advance(contact, previous,
				seed_only ? R(0.0) : R(double(tick - since)) / R(rate), seed_only, !seed_only, R(1.0) / R(rate));
			next_states.emplace_back(contact.id, observed.state);
			if (observed.impact_approach.v >= 0.0) {
				++observed_;
				if (events_.size() == size_t(kGroundMaxEvents)) {
					events_.erase(events_.begin());
					++overflowed_;
					++discarded_;
				}
				events_.push_back({tick, contact, observed.force.v, observed.reference.v, observed.impact_approach.v});
			}
		}
		states_ = next_states;
		contacts_ = in.contacts;
		accepted_tick_ = tick;
		accepted_rate_ = rate;
		accepted_paused_ = in.paused;
		return true;
	}

	bool touchdown_possible() const {
		if (states_.empty()) return true;
		for (const auto &entry : states_) {
			if (!entry.second.grounded) return true;
		}
		return false;
	}

	bool touchdown_possible_at(const godot::PackedStringArray &identities, const godot::PackedFloat64Array &compressions) const {
		if (states_.empty() || identities.size() != compressions.size()) return true;
		size_t covered = 0;
		for (int64_t index = 0; index < identities.size(); ++index) {
			const WheelState *state = find_state(identities[index]);
			if (state == nullptr) return true;
			++covered;
			if (state->grounded) {
				if (!(compressions[index] > kGroundCompressionMargin)) return true;
			} else if (!(compressions[index] <= -kGroundCompressionMargin)) {
				return true;
			}
		}
		return covered != states_.size() && touchdown_possible();
	}

	void note_skipped_tick(int64_t tick, const godot::PackedStringArray &identities, const godot::PackedFloat64Array &approaches) {
		skipped_tick_ = tick;
		skipped_.clear();
		if (identities.size() != approaches.size()) {
			skipped_tick_ = -1;
			return;
		}
		for (int64_t index = 0; index < identities.size(); ++index) {
			const double approach = approaches[index];
			if (std::isfinite(approach) && approach >= 0.0) set_skipped(identities[index], approach);
		}
	}

	// The (id, fallback index) pairs update_contacts would create, in order; GDScript makes them with _slot_for.
	godot::Array pending_slots(int64_t tick, bool paused) const {
		godot::Array out;
		if (paused) return out;
		std::vector<godot::String> ids;
		for (const Slot &slot : slots_) ids.push_back(slot.id);
		auto need = [&](const godot::String &id, int64_t fallback) {
			for (const godot::String &existing : ids) {
				if (existing == id) return;
			}
			if (ids.size() >= size_t(kGroundMaxContacts)) return;
			ids.push_back(id);
			godot::Array pair;
			pair.push_back(id);
			pair.push_back(fallback);
			out.push_back(pair);
		};
		if (tick == accepted_tick_) {
			for (const Event &event : events_) {
				if (tick < event.tick || double(tick - event.tick) / std::max(accepted_rate_, 1.0) > kGroundMaxEventAge) continue;
				need(event.contact.id, int64_t(ids.size()));
			}
			for (size_t i = 0; i < contacts_.size(); ++i) need(contacts_[i].id, int64_t(i));
		}
		return out;
	}

	// update_contacts in accepted mode, after GDScript's rebind; seed carries GroundAudio._needs_seed.
	// Returns [touchdown_events, was_paused, scene_gain, needs_seed], or empty when a bound player is gone.
	godot::PackedFloat64Array frame(int64_t tick, bool paused, double engine_power, double delta, const godot::Vector3 &listener,
			double tick_rate_hz, bool seed) {
		godot::PackedFloat64Array out;
		if (!nodes_valid()) return out;
		needs_seed_ = seed;
		if (tick < last_tick_) reset_playback();
		const bool current = tick == accepted_tick_;
		if (paused || !current) discard_events();
		const int64_t tick_delta = std::max<int64_t>(tick - last_tick_, 0);
		const bool tick_advanced = tick_delta > 0;
		last_tick_ = tick;
		listener_ = listener;
		const R clamped = clampf(delta, 0.0, 0.1);
		if (paused) {
			if (!was_paused_) needs_seed_ = true;
			was_paused_ = true;
			scene_gain_ = maxf(0.0, scene_gain_ - clamped / R(0.08));
			apply_scene_gain();
			if (scene_gain_.v <= 0.001) {
				const EngineBinds &b = engine_binds();
				for (const Slot &slot : slots_) {
					for (const Bound &player : slot.roll) call_void(b.stop, player);
					call_void(b.stop, slot.impact);
				}
			}
			return answer();
		}
		if (was_paused_) {
			needs_seed_ = true;
			was_paused_ = false;
		}
		scene_gain_ = minf(1.0, scene_gain_ + clamped / R(0.08));
		const R dt = clamped;
		const R target_mask = R(1.0) - R(0.42) * smoothstep(0.12, 0.9, clampf(engine_power, 0.0, 1.0));
		engine_mask_ = engine_mask_ + (target_mask - engine_mask_) * (R(1.0) - R(e_exp((R(-dt.v) / R(0.25)).v)));
		(void)tick_rate_hz; // the accepted path's state delta is unused (GroundAudioMotion.advance gets 0.0)
		(void)tick_advanced;
		drain_events(tick);
		std::vector<bool> active(slots_.size(), false);
		if (current) {
			for (size_t i = 0; i < contacts_.size(); ++i) {
				const int index = slot_index(contacts_[i].id);
				if (index < 0) continue;
				active[size_t(index)] = true;
				update_contact(contacts_[i], slots_[size_t(index)], dt);
			}
		}
		for (size_t i = 0; i < slots_.size(); ++i) {
			if (active[i]) continue;
			set_roll_targets(slots_[i], 0, 0.0, dt, 0.0);
			slots_[i].has_roll_pitch = false; // slot["state"] = {}
		}
		needs_seed_ = false;
		return answer();
	}

	// stop(): every player stopped, roll levels zeroed, roll pitch 0.85.
	void stop() {
		const EngineBinds &b = engine_binds();
		if (!nodes_valid()) return;
		for (Slot &slot : slots_) {
			for (const Bound &player : slot.roll) call_void(b.stop, player);
			call_void(b.stop, slot.impact);
			for (double &gain : slot.layer) gain = 0.0;
			slot.has_roll_pitch = true;
			slot.roll_pitch = 0.85;
		}
	}

	// reset(): the accepted observation, its counters and playback.
	void reset() {
		clear_accepted();
		observed_ = drained_ = discarded_ = overflowed_ = refused_ = 0;
		reset_playback();
	}

	// _on_buses_releasing.
	void release_buses() {
		clear_accepted();
		stop();
	}

	void clear_accepted() {
		discard_events();
		states_.clear();
		contacts_.clear();
		accepted_tick_ = -1;
		accepted_rate_ = 0.0;
		accepted_paused_ = true;
		skipped_tick_ = -1;
		skipped_.clear();
	}

	int64_t accepted_tick() const { return accepted_tick_; }

	godot::Dictionary diagnostics() const {
		// GDScript's {law = ...} literal: StringName keys, in this order.
		godot::Dictionary out;
		out[godot::StringName("law")] = godot::String("accepted-tick-ground-audio-v1");
		out[godot::StringName("tick")] = accepted_tick_;
		out[godot::StringName("states")] = int64_t(states_.size());
		out[godot::StringName("queued")] = int64_t(events_.size());
		out[godot::StringName("observed")] = observed_;
		out[godot::StringName("drained")] = drained_;
		out[godot::StringName("discarded")] = discarded_;
		out[godot::StringName("overflowed")] = overflowed_;
		out[godot::StringName("refused")] = refused_;
		return out;
	}

	// For parity tests: accepted states [id, initialized, grounded, airborne, previous approach, cooldown] and slot
	// state [id, layer gains x3, impact gain, has roll pitch, roll pitch].
	godot::Array state() const {
		godot::Array out;
		godot::Array states;
		for (const auto &entry : states_) {
			godot::Array row;
			row.push_back(entry.first);
			row.push_back(entry.second.initialized);
			row.push_back(entry.second.grounded);
			row.push_back(entry.second.airborne);
			row.push_back(entry.second.previous_approach);
			row.push_back(entry.second.cooldown);
			states.push_back(row);
		}
		godot::Array slots;
		for (const Slot &slot : slots_) {
			godot::Array row;
			row.push_back(slot.id);
			for (double gain : slot.layer) row.push_back(gain);
			row.push_back(slot.impact_gain);
			row.push_back(slot.has_roll_pitch);
			row.push_back(slot.roll_pitch);
			slots.push_back(row);
		}
		out.push_back(states);
		out.push_back(slots);
		out.push_back(engine_mask_.v);
		out.push_back(last_tick_);
		return out;
	}

private:
	struct Slot {
		godot::String id;
		Bound roll[3];
		Bound impact;
		double length[3] = {};
		double offset = 0.0;
		double layer[3] = {};
		double impact_gain = 0.0;
		bool has_roll_pitch = false;
		double roll_pitch = 0.0;
	};
	struct Event {
		int64_t tick;
		GroundContact contact;
		double force, reference, approach;
	};
	struct Observation {
		int64_t tick = 0;
		double rate = 0.0;
		bool paused = false;
		bool has_since = false;
		int64_t since = 0;
		std::vector<GroundContact> contacts;
	};

	static bool finite_number(const godot::Variant &value, double &out) {
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

	// GroundAudio._valid_accepted_snapshot plus the reads observe_accepted makes.
	bool read_snapshot(const godot::Dictionary &snapshot, Observation &in) const {
		const godot::Variant &kSince = key_since_;
		const godot::Variant &kTick = key_tick_;
		const godot::Variant &kRate = key_rate_;
		const godot::Variant &kPaused = key_paused_;
		const godot::Variant &kContacts = key_contacts_;
		if (snapshot.has(kSince)) {
			const godot::Variant since = snapshot[kSince];
			if (since.get_type() != godot::Variant::INT || int64_t(since) < -1) return false;
			in.has_since = true;
			in.since = int64_t(since);
		}
		const godot::Variant tick = snapshot.get(kTick, godot::Variant());
		if (tick.get_type() != godot::Variant::INT || int64_t(tick) < 0 || int64_t(tick) > 9007199254740991LL) return false;
		in.tick = int64_t(tick);
		const godot::Variant rate = snapshot.get(kRate, godot::Variant());
		double r = 0.0;
		if (!finite_number(rate, r) || r < 1.0 || r > kGroundMaxRate) return false;
		in.rate = r;
		const godot::Variant paused = snapshot.get(kPaused, godot::Variant());
		if (paused.get_type() != godot::Variant::BOOL) return false;
		in.paused = bool(paused);
		const godot::Variant contacts_value = snapshot.get(kContacts, godot::Variant());
		if (contacts_value.get_type() != godot::Variant::ARRAY) return false;
		const godot::Array contacts = contacts_value;
		if (contacts.size() > kGroundMaxContacts) return false;
		for (int64_t i = 0; i < contacts.size(); ++i) {
			const godot::Variant item = contacts[i];
			if (item.get_type() != godot::Variant::DICTIONARY) return false;
			const godot::Dictionary contact = item;
			GroundContact row;
			if (!read_contact(contact, row)) return false;
			for (const GroundContact &seen : in.contacts) {
				if (seen.id == row.id) return false;
			}
			in.contacts.push_back(row);
		}
		return true;
	}

	bool read_contact(const godot::Dictionary &contact, GroundContact &row) const {
		const godot::Variant &kId = key_id_;
		const godot::Variant &kPosition = key_position_;
		const godot::Variant &kForce = key_force_;
		const godot::Variant &kReference = key_reference_;
		const godot::Variant &kApproach = key_approach_;
		const godot::Variant &kRolling = key_rolling_;
		const godot::Variant &kSurface = key_surface_;
		const godot::Variant &kGrounded = key_grounded_;
		const godot::Variant &kRoll = key_roll_;
		const godot::Variant id = contact.get(kId, godot::Variant());
		if (id.get_type() != godot::Variant::STRING) return false;
		row.id = id;
		if (row.id.is_empty() || row.id.length() > 128) return false;
		double *values[4] = {&row.normal_force, &row.reference_load, &row.approach, &row.rolling};
		const godot::Variant *keys[4] = {&kForce, &kReference, &kApproach, &kRolling};
		for (int k = 0; k < 4; ++k) {
			if (!finite_number(contact.get(*keys[k], godot::Variant()), *values[k]) || *values[k] < 0.0) return false;
		}
		const godot::Variant position = contact.get(kPosition, godot::Variant());
		if (position.get_type() != godot::Variant::VECTOR3) return false;
		row.position = position;
		if (!std::isfinite(row.position.x) || !std::isfinite(row.position.y) || !std::isfinite(row.position.z)) return false;
		const godot::Variant surface = contact.get(kSurface, godot::Variant());
		if (surface.get_type() != godot::Variant::STRING) return false;
		row.surface = surface;
		if (row.surface.length() > 64) return false;
		if (contact.has(kGrounded) && contact[kGrounded].get_type() != godot::Variant::BOOL) return false;
		if (contact.has(kRoll)) {
			if (contact[kRoll].get_type() != godot::Variant::BOOL) return false;
			row.roll_enabled = bool(contact[kRoll]);
		}
		return true;
	}

	const WheelState *find_state(const godot::String &id) const {
		for (const auto &entry : states_) {
			if (entry.first == id) return &entry.second;
		}
		return nullptr;
	}

	WheelState state_for(const godot::String &id) const {
		const WheelState *state = find_state(id);
		return state != nullptr ? *state : WheelState();
	}

	bool skipped_approach(const godot::String &id, double &out) const {
		for (const auto &entry : skipped_) {
			if (entry.first == id) {
				out = entry.second;
				return true;
			}
		}
		return false;
	}

	void set_skipped(const godot::String &id, double approach) {
		for (auto &entry : skipped_) {
			if (entry.first == id) {
				entry.second = approach;
				return;
			}
		}
		skipped_.emplace_back(id, approach);
	}

	int slot_index(const godot::String &id) const {
		for (size_t i = 0; i < slots_.size(); ++i) {
			if (slots_[i].id == id) return int(i);
		}
		return -1;
	}

	bool nodes_valid() const {
		for (const Slot &slot : slots_) {
			for (const Bound &player : slot.roll) {
				if (!player.valid()) return false;
			}
			if (!slot.impact.valid()) return false;
		}
		return true;
	}

	godot::PackedFloat64Array answer() const {
		godot::PackedFloat64Array out;
		out.resize(4);
		out[0] = double(touchdown_events_);
		out[1] = was_paused_ ? 1.0 : 0.0;
		out[2] = scene_gain_.v;
		out[3] = needs_seed_ ? 1.0 : 0.0;
		return out;
	}

	void discard_events() {
		discarded_ += int64_t(events_.size());
		events_.clear();
	}

	// _reset_playback.
	void reset_playback() {
		stop();
		last_tick_ = -1;
		needs_seed_ = true;
		engine_mask_ = 1.0;
		scene_gain_ = 1.0;
		was_paused_ = false;
		touchdown_events_ = 0;
		for (Slot &slot : slots_) slot.has_roll_pitch = false;
	}

	R path_gain(const Bound &player) const {
		const godot::Vector3 position = call_get_vector3(engine_binds().get_global_position, player);
		return distance_gain(R(double(distance(position, listener_))));
	}

	// _apply_scene_gain.
	void apply_scene_gain() {
		const EngineBinds &b = engine_binds();
		for (Slot &slot : slots_) {
			for (int i = 0; i < 3; ++i) {
				const R audible = R(slot.layer[i]) * scene_gain_ * path_gain(slot.roll[i]);
				call_set(b.set_volume_db, slot.roll[i], (linear_to_db(maxf(audible, 0.0001)) - R(12.0)).v);
			}
			if (call_get_bool(b.is_playing, slot.impact)) {
				const R gain = R(slot.impact_gain) * scene_gain_ * path_gain(slot.impact);
				call_set(b.set_volume_db, slot.impact, (linear_to_db(maxf(gain, 0.0001)) - R(12.0)).v);
			}
		}
	}

	// _drain_accepted_events.
	void drain_events(int64_t tick) {
		for (const Event &event : events_) {
			if (tick < event.tick || double(tick - event.tick) / std::max(accepted_rate_, 1.0) > kGroundMaxEventAge) {
				++discarded_;
				continue;
			}
			const int index = slot_index(event.contact.id);
			if (index < 0) {
				++discarded_;
				continue;
			}
			play_touchdown(event.contact, event.force, event.reference, event.approach, slots_[size_t(index)]);
			++drained_;
		}
		events_.clear();
	}

	// _play_touchdown.
	void play_touchdown(const GroundContact &contact, R force, R reference, R approach, Slot &slot) {
		const EngineBinds &b = engine_binds();
		if (call_get_bool(b.is_playing, slot.impact)) return;
		const R load_mix = clampf(force / reference, 0.0, 2.0);
		const R impact_mix = clampf(R(0.45) * approach / R(4.0) + R(0.18) * load_mix, 0.2, 1.0);
		slot.impact_gain = (R(0.22) + R(0.34) * impact_mix).v;
		call_set(b.set_pitch_scale, slot.impact, clampf(R(0.94) + approach * R(0.018), 0.94, 1.12).v);
		call_set(b.set_global_position, slot.impact, contact.position);
		const R gain = (R(0.22) + R(0.34) * impact_mix) * scene_gain_ * path_gain(slot.impact);
		call_set(b.set_volume_db, slot.impact, (linear_to_db(maxf(gain, 0.0001)) - R(12.0)).v);
		call_set(b.play, slot.impact, 0.0);
		++touchdown_events_;
	}

	// _update_contact in accepted mode.
	void update_contact(const GroundContact &contact, Slot &slot, R dt) {
		const EngineBinds &b = engine_binds();
		for (const Bound &player : slot.roll) call_set(b.set_global_position, player, contact.position);
		const WheelAdvance observed = wheel_advance(contact, state_for(contact.id), 0.0, false, false);
		const R load_ratio = clampf(observed.force / observed.reference, 0.0, 1.5);
		const R rolling = maxf(0.0, contact.rolling);
		const bool can_roll = contact.roll_enabled && observed.state.grounded && observed.force.v >= observed.force_off.v &&
			rolling.v >= 0.35;
		R target = 0.0;
		if (can_roll) {
			// A gentle onset, then sublinear energy growth (ground_audio.gd).
			const R speed_mix = smoothstep(0.35, 1.5, rolling) * e_pow(clampf(rolling / R(12.0), 0.0, 1.0), 0.6);
			const R load_mix = clampf(sqrt_(load_ratio), 0.0, 1.0);
			target = R(0.42) * speed_mix * load_mix * engine_mask_;
		}
		const godot::String &surface = contact.surface;
		const int selected = (surface == "grass" || surface == "mown") ? 1 : ((surface == "gravel" || surface == "rough") ? 2 : 0);
		set_roll_targets(slot, selected, target, dt, rolling);
		if (call_get_bool(b.is_playing, slot.impact)) {
			const R gain = maxf(0.0001, R(slot.impact_gain) * scene_gain_ * path_gain(slot.impact));
			call_set(b.set_volume_db, slot.impact, (linear_to_db(gain) - R(12.0)).v);
		}
	}

	// _set_roll_targets.
	void set_roll_targets(Slot &slot, int selected, R gain, R delta, R rolling_speed) {
		const EngineBinds &b = engine_binds();
		static const double kFactors[3] = {1.0, 1.35, 0.86};
		const R alpha = delta.v > 0.0 ? R(1.0) - R(e_exp((R(-delta.v) / R(0.12)).v)) : R(0.0);
		const R target_pitch = clampf(R(0.85) + R(0.025) * sqrt_(maxf(rolling_speed, 0.0)), 0.85, 1.18);
		const R old_pitch = slot.has_roll_pitch ? R(slot.roll_pitch) : target_pitch;
		const R pitch = lerpf(old_pitch, target_pitch, alpha);
		slot.has_roll_pitch = true;
		slot.roll_pitch = pitch.v;
		for (int layer = 0; layer < 3; ++layer) {
			const R target = layer == selected ? gain * R(kFactors[layer]) : R(0.0);
			slot.layer[layer] = (R(slot.layer[layer]) + (target - R(slot.layer[layer])) * alpha).v;
			const Bound &player = slot.roll[layer];
			const R audible = R(slot.layer[layer]) * scene_gain_ * path_gain(player);
			call_set(b.set_volume_db, player, (linear_to_db(maxf(audible, 0.0001)) - R(12.0)).v);
			call_set(b.set_pitch_scale, player, pitch.v);
			if (audible.v > 0.0001) {
				if (!call_get_bool(b.is_playing, player)) call_set(b.play, player, (R(slot.offset) * R(slot.length[layer])).v);
			} else {
				call_void(b.stop, player);
			}
		}
	}

	godot::Variant key_since_, key_tick_, key_rate_, key_paused_, key_contacts_, key_id_, key_position_, key_force_,
		key_reference_, key_approach_, key_rolling_, key_surface_, key_grounded_, key_roll_;
	std::vector<Slot> slots_;
	std::vector<std::pair<godot::String, WheelState>> states_;
	std::vector<GroundContact> contacts_;
	std::vector<Event> events_;
	std::vector<std::pair<godot::String, double>> skipped_;
	int64_t accepted_tick_ = -1;
	double accepted_rate_ = 0.0;
	bool accepted_paused_ = true;
	int64_t skipped_tick_ = -1;
	int64_t observed_ = 0, drained_ = 0, discarded_ = 0, overflowed_ = 0, refused_ = 0;
	int64_t last_tick_ = -1;
	bool needs_seed_ = true;
	R engine_mask_ = 1.0;
	R scene_gain_ = 1.0;
	bool was_paused_ = false;
	godot::Vector3 listener_;
	int64_t touchdown_events_ = 0;
};

} // namespace sound
} // namespace nk
