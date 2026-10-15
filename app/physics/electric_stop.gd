# EL1d: bounded RK4 with a unilateral relative-shaft stop.
# SF-04: the algorithm now lives in physics/event_step.gd as the kernel's event locator; this wrapper keeps the
# EL1d contract (event times as a float64 array) for the battery composition (physics/electric_battery_step.gd)
# and the existing tests. Negative trial RPM is a documented continuation used only to locate a crossing.
# Accepted endpoints never cross the boundary; project() preserves locked-body momentum.
extends RefCounted

const EventStep: Script = preload("res://physics/event_step.gd")
const TIME_TOL: float = EventStep.TIME_TOL
const RPM_TOL: float = EventStep.VALUE_TOL
const MAX_SEGMENTS: int = EventStep.MAX_SEGMENTS
const MAX_ROOT_TRIALS: int = EventStep.MAX_ROOT_TRIALS
const MAX_DT_S: float = EventStep.MAX_DT_S


static func advance(s: PackedFloat64Array, time_s: float, dt: float, derivative: Callable,
		first: PackedFloat64Array, index: int, project: Callable) -> Dictionary:
	var located: Dictionary = EventStep.advance(s, time_s, dt, derivative, first, index, project, "rotor_stop")
	if not located.get("ok", false):
		return {ok = false}
	var events: PackedFloat64Array = PackedFloat64Array()
	for event: Dictionary in located.events:
		events.append(float(event.time_s))
	return {ok = true, state = located.state, events = events}
