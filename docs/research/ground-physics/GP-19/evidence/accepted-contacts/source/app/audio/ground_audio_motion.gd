## GP-19: shared deterministic classifier for legacy render and accepted tick capture.
## Thresholds describe sound triggering, never physical support or landing statistics.
## Updates its caller-owned presentation state only; no engine/player/physics calls.
extends RefCounted

const TOUCHDOWN_MIN_AIRBORNE_S := 0.14
const TOUCHDOWN_MIN_APPROACH_MPS := 0.2
const TOUCHDOWN_DEBOUNCE_S := 0.65


static func advance(contact: Dictionary, state: Dictionary, state_delta: float,
		seed_only: bool, tick_advanced: bool) -> Dictionary:
	var impact_approach := -1.0
	var force: float = maxf(0.0, float(contact.get("normal_force_n", contact.get("normal_force", 0.0))))
	var reference: float = maxf(1.0, float(contact.get("reference_load_n", maxf(force, 100.0))))
	var force_on: float = maxf(3.0, reference * 0.035)
	var force_off: float = maxf(1.0, reference * 0.018)
	var candidate_grounded: bool = bool(contact.get("grounded", force >= force_on)) if not contact.has("normal_force_n") else force >= force_on
	var approach_now: float = maxf(0.0, float(contact.get("approach_speed_mps", 0.0)))
	var was_grounded: bool = bool(state.get("grounded", false))
	var cooldown: float = maxf(0.0, float(state.get("cooldown_s", 0.0)) - state_delta)
	var airborne: float = float(state.get("airborne_s", 0.0))
	var previous_approach: float = float(state.get("previous_approach_mps", 0.0))
	if seed_only or not bool(state.get("initialized", false)):
		was_grounded = force >= force_on if contact.has("normal_force_n") else candidate_grounded
		state["grounded"] = was_grounded
		state["airborne_s"] = 0.0
		state["previous_approach_mps"] = 0.0
		state["cooldown_s"] = 0.0
		state["initialized"] = true
	else:
		var next_grounded: bool = force >= force_off if was_grounded else candidate_grounded
		if next_grounded and not was_grounded:
			# The accepted contact state may already be rebounding. Retain only the last
			# airborne sample, never a descent peak from an earlier part of the flight.
			var approach: float = maxf(previous_approach, approach_now)
			if tick_advanced and not seed_only and airborne >= TOUCHDOWN_MIN_AIRBORNE_S and cooldown <= 0.0 and approach >= TOUCHDOWN_MIN_APPROACH_MPS:
				impact_approach = approach
				cooldown = TOUCHDOWN_DEBOUNCE_S
			airborne = 0.0
			previous_approach = 0.0
		elif not next_grounded:
			airborne += state_delta
			if tick_advanced:
				previous_approach = approach_now
		state["grounded"] = next_grounded
		state["airborne_s"] = airborne
		state["previous_approach_mps"] = previous_approach
		state["cooldown_s"] = cooldown
		state["initialized"] = true
	return {state = state, force = force, reference = reference, force_off = force_off, impact_approach = impact_approach}
