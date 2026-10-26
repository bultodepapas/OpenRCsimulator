# SF-01: the vehicle-model contract that Simulation (sim/simulation.gd) steps.
# A model declares its state layout and supplies read-only stage evaluators. The kernel owns the tick
# transaction: validation, pre-tick, RK4 stages at their stage time, the optional step policy, the post-tick
# filter, commit, checkpoint and fault rollback. The kernel never knows what a wing, a rotor or a tyre is.
#
# Combined state vector: the 13-value rigid body (physics/rigid_body.gd) first, then the model's continuous
# blocks, packed only inside the integrator. Sampled `aux` is advanced once per tick and frozen through the
# stages; discrete `modes` change only at tick boundaries (H8 contract, docs/research/simulation-state/H8).
# Evaluators are pure functions of their arguments: they never advance state, modes or random generators.
# 64-bit floats only (guarded by test.sh); no Vector3/Basis/Quaternion/Transform3D.
extends RefCounted
const Timing:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/metrics.gd")

## Layout. input_size is the sampled command count (> 0). The other sizes keep the H8 rule when -1: the arrays
## supplied at reset fix them for the run. A value >= 0 is enforced at reset and restore.
var input_size: int = 4
var aux_size: int = -1
var modes_size: int = -1
var continuous_size: int = -1
## Free-form law/version identity (strings and numbers). Sessions pin it into their checkpoint envelopes.
var identity: Dictionary = {}
## Optional semantic identity for an explicitly sized, checkpoint-v2 state layout.
## Empty keeps the historical checkpoint/step path. A transition or validator requires it.
var state_layout_identity: String = ""
## Pure endpoint_transition(previous, candidate, context) -> {body, continuous, aux, modes, events}.
## Frames contain exactly body/continuous/aux/modes. Candidate is a detached working copy;
## previous and context are read-only. Context has tick, time_s (endpoint), dt, events and
## body_filtered, plus optional opaque integration_receipt from the accepted step policy.
## A body filter may invalidate the receipt's trajectory; the model must handle/refuse it.
## Events returned here append to existing located events, in model order.
## Every output keeps its declared size. No inputs, mass, inertia or model edits are allowed.
## Runs after the legacy body filter, before final block_aux projection and validation.
var endpoint_transition: Callable = Callable()
## Pure state_validator(frame, context) -> bool, after final projection and at reset/restore.
## Context is {tick, time_s, dt} for the state being validated, including a restored
## checkpoint's clock. Both arguments are detached/read-only; live state is guarded.
var state_validator: Callable = Callable()

## loads(body, t) -> float64[6]: [Fx, Fy, Fz, Mx, My, Mz] in body axes, gravity excluded. Body-only route.
var loads: Callable = func(_body: PackedFloat64Array, _t: float) -> PackedFloat64Array:
	return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
## stage(body, continuous, t) -> {loads: float64[6], derivative: float64[continuous], rotor_momentum: float64[3]
## [, body_derivative: float64[13]][, stage_context: Dictionary]}: one joint evaluation per RK stage.
## `stage_context` is opaque to the kernel and is passed only to `substeps_joint` for this tick's k1 result.
## A body_derivative replaces RigidBody.derivative with a qualified stage law: finite fuel mass/CG, or the
## fixed-axis body/wheel reference tested by test_wheel_coupling. Moving axes and dynamic shafts require further qualification.
## Requires a nonempty continuous block at reset/restore/step; body-only models use `loads`.
var stage: Callable
## Split route when `stage` is unset and continuous state exists:
## block_loads(body, continuous, t) -> float64[6]; block_derivative(body, continuous, t) -> float64[continuous].
var block_loads: Callable
var block_derivative: Callable
## stage_rotor_momentum(body, continuous, t) -> float64[3]: stage-local spinning momentum (split route only).
var stage_rotor_momentum: Callable
## rotor_momentum(aux) -> float64[3] or empty: sampled spinning momentum, frozen through the stages.
var rotor_momentum: Callable = func(_aux: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array()
## pre_tick(aux, inputs, dt) -> aux: advances sampled state once per tick, before k1.
var pre_tick: Callable = func(aux: PackedFloat64Array, _inputs: PackedFloat64Array, _dt: float) -> PackedFloat64Array:
	return aux
## post_tick(previous_body, candidate_body, next_tick) -> accepted body: deterministic tick-boundary contact
## filter on the rigid body only. Empty = none.
var post_tick: Callable = Callable()
## post_tick_joint(previous_body, candidate_body, next_tick, previous_continuous, candidate_continuous) -> body:
## the same filter for state-dependent mass. A model selects at most one of post_tick / post_tick_joint.
var post_tick_joint: Callable = Callable()
## block_aux(continuous, aux) -> aux: pure endpoint projection of continuous state into sampled telemetry.
var block_aux: Callable
## step_policy(combined, t, dt, f, k1) -> combined or {state: combined, events: [{type, time_s, ...}]}: optional
## bounded integration/event policy for the whole tick (composed boundaries, the rotorcraft stop predictor).
## f(combined, stage_t) is the kernel's validated stage derivative. Located events are recorded by the kernel.
## An opt-in endpoint owner may also return integration_receipt:Dictionary, a bounded
## finite detached payload describing ONLY the accepted integration path. It passes
## to endpoint_transition, never observers/checkpoints as a second state or fake event.
## The kernel validates transport, not the physical truth of a model's receipt. Trial
## stages, abandoned subdivisions and filtered body paths must not establish damage.
var step_policy: Callable
## SF-04: declared tick events for the kernel's locator (physics/event_step.gd): [{type: String, index: int,
## transition: Callable}]. `index` addresses a continuous value (combined index at or beyond the body) held at or
## above zero; `transition(state, index) -> state` applies the discrete change at the located boundary. The kernel
## runs the locator when no step_policy is set and exactly one event is declared; a model composing several
## boundaries keeps its own step_policy and reports its events through it.
## SF-04b: the locator evaluates RK stages beyond the boundary while it brackets a crossing, so the stage law must
## continue smoothly there (as the electric shaft does). A law that refuses the far side (the rotorcraft law faults
## for Ω < 0) needs a domain-guarded step_policy instead: physics/rotorcraft/simulation_step_adapter.gd never
## evaluates a stage beyond zero. Both are fourth order and agree to 1e-10 s (tests/test_sf_event_refinement.gd).
var events: Array[Dictionary] = []
## SF-05: substeps(body, continuous, t) -> int in 1..Simulation.MAX_SUBSTEPS, evaluated once per tick. The kernel
## integrates its own RK4 and the declared-event locator in that many substeps of dt/n (stiff contacts within
## reach). A step_policy owns the whole tick and is never split: a tick that asks for more than one substep under a
## policy is refused (SF-04b). Unset = 1.
var substeps: Callable
## Optional joint-stage form: substeps_joint(body, continuous, t, current_joint) -> int. The kernel passes the
## validated k1 joint result from this same tick; `stage_context` remains opaque and is owned by the vehicle law.
## The callback must treat current_joint and its arrays as read-only because the kernel reuses k1 after this call.
## Set this or `substeps`, never both. Existing three-argument substeps callbacks remain unchanged.
var substeps_joint: Callable = Callable()


## Static shape of the contract. Checks that depend on the live state (continuous size, array finiteness)
## stay in Simulation. Returns {ok, message}.
static func validate(candidate: Variant) -> Dictionary:
	if candidate == null or not (candidate is RefCounted) or not candidate.has_method("uses_joint_stage"):
		return {ok = false, message = "vehicle model must be a sim/vehicle_model.gd instance"}
	if typeof(candidate.input_size) != TYPE_INT or candidate.input_size <= 0:
		return {ok = false, message = "vehicle model input_size must be a positive integer"}
	for field: String in ["aux_size", "modes_size", "continuous_size"]:
		var size: Variant = candidate.get(field)
		if typeof(size) != TYPE_INT or size < -1:
			return {ok = false, message = "vehicle model %s must be -1 (fixed at reset) or a non-negative integer" % field}
	if typeof(candidate.identity) != TYPE_DICTIONARY:
		return {ok = false, message = "vehicle model identity must be a dictionary"}
	if typeof(candidate.state_layout_identity) != TYPE_STRING or candidate.state_layout_identity.length() > 256 \
		or candidate.state_layout_identity != candidate.state_layout_identity.strip_edges():
		return {ok = false, message = "vehicle model state layout identity must be a bounded string without edge whitespace"}
	if not candidate.state_layout_identity.is_empty():
		for field: String in ["aux_size", "modes_size", "continuous_size"]:
			if candidate.get(field) < 0:
				return {ok = false, message = "vehicle model endpoint layout requires explicit %s" % field}
	for field: String in ["loads", "stage", "block_loads", "block_derivative", "stage_rotor_momentum",
			"rotor_momentum", "pre_tick", "post_tick", "post_tick_joint", "block_aux", "step_policy", "substeps", "substeps_joint",
			"endpoint_transition", "state_validator"]:
		if typeof(candidate.get(field)) != TYPE_CALLABLE:
			return {ok = false, message = "vehicle model %s must be a Callable" % field}
	if candidate.endpoint_transition.is_valid() or candidate.state_validator.is_valid():
		if candidate.state_layout_identity.is_empty():
			return {ok = false, message = "vehicle model endpoint callbacks require a state layout identity"}
	if candidate.post_tick.is_valid() and candidate.post_tick_joint.is_valid():
		return {ok = false, message = "vehicle model selects at most one of post_tick and post_tick_joint"}
	if candidate.substeps.is_valid() and candidate.substeps_joint.is_valid():
		return {ok = false, message = "vehicle model selects at most one of substeps and substeps_joint"}
	if candidate.substeps_joint.is_valid() and not candidate.stage.is_valid():
		return {ok = false, message = "vehicle model substeps_joint requires a joint stage evaluator"}
	if not candidate.loads.is_valid() and not candidate.stage.is_valid() \
			and not (candidate.block_loads.is_valid() and candidate.block_derivative.is_valid()):
		return {ok = false, message = "vehicle model supplies loads, stage, or block_loads and block_derivative"}
	if not candidate.pre_tick.is_valid() or not candidate.rotor_momentum.is_valid():
		return {ok = false, message = "vehicle model pre_tick and rotor_momentum must be valid Callables"}
	if typeof(candidate.events) != TYPE_ARRAY:
		return {ok = false, message = "vehicle model events must be an array of declarations"}
	if candidate.events.size() > 1:
		return {ok = false, message = "vehicle model declares at most one kernel-located event; compose more in a step_policy"}
	for declared: Variant in candidate.events:
		if typeof(declared) != TYPE_DICTIONARY or typeof(declared.get("type")) != TYPE_STRING or str(declared.type).is_empty() \
				or typeof(declared.get("index")) != TYPE_INT or int(declared.index) < 13 \
				or typeof(declared.get("transition")) != TYPE_CALLABLE or not declared.transition.is_valid():
			return {ok = false, message = "vehicle model event needs a type, a continuous index and a valid transition"}
		if candidate.step_policy.is_valid():
			return {ok = false, message = "vehicle model cannot declare a kernel event and a step_policy together"}
	return {ok = true, message = ""}


## True when the model integrates continuous blocks through the joint `stage` route.
func uses_joint_stage() -> bool:
	return stage.is_valid()
