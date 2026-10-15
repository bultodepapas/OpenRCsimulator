## Optional, symmetric hinged trailing-edge flap actuator and aerodynamic law identity.
## Runtime state and requests are normalized over the authored maximum deflection [0, 1].
extends RefCounted

const LAW := "controls.flaps.hinged_trailing_edge.v1"


static func enabled(model: Dictionary) -> bool:
	return str(model.get("capabilities", {}).get("flaps", "not_simulated")) == "simulated" \
		and model.get("flaps", {}) is Dictionary \
		and not model.get("flaps", {}).is_empty()


## Advance normalized position toward a normalized request. Extension/retraction times
## describe the effective installed system's full-scale travel, not naked servo speed.
static func advance(value: float, target: float, dt: float, config: Dictionary) -> float:
	var current := clampf(value, 0.0, 1.0) if is_finite(value) else 0.0
	var requested := clampf(target, 0.0, 1.0) if is_finite(target) else current
	if not is_finite(dt) or dt <= 0.0 or current == requested:
		return current
	var key := "extension_time" if requested > current else "retraction_time"
	var travel_time := float(config.get(key, 1.5))
	if not is_finite(travel_time) or travel_time <= 0.0:
		return current
	return move_toward(current, requested, dt / travel_time)
