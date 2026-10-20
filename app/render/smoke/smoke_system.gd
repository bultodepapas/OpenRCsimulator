extends "res://render/smoke/profile_smoke.gd"
## Common presentation boundary for every vehicle. The renderer accepts immutable
## accepted-source observations; it never changes fuel, engine or vehicle state.

const Source := preload("res://physics/propulsion.gd")
const SOURCE_ROLE := "$propulsion"


## Emissions appearance is distinct from the solver's source kind. In particular,
## the gasoline P-51 retains glow_prop in its physical installation contract.
static func emissions_family(propulsion: Dictionary) -> String:
	match Source.source_kind(propulsion):
		"electric_prop": return "electric_clear"
		"turbine": return "turbine_clear"
		"glow_prop":
			if str(propulsion.get("liquid_fuel", {}).get("law", "")) == "gasoline_bsfc_v1":
				return "gasoline_light"
			var glow: Dictionary = propulsion.get("glow", {})
			return "glow_four_stroke" if str(glow.get("family", "")) == "glow_4t" else "glow_oil"
	return "unsupported"


## Bounded visual load proxy, not an emissions mass-flow or temperature model.
## Call with accepted RPM/latch only. Missing combustion detail uses a conservative
## RPM/load envelope. Finite-glow firing fraction is optional accepted telemetry.
static func source_observation(propulsion: Dictionary, rpm: float, throttle: float,
		running: bool, firing_fraction: float = 1.0) -> Dictionary:
	var kind := Source.source_kind(propulsion)
	var valid := is_finite(rpm) and is_finite(throttle) and is_finite(firing_fraction)
	var accepted := running and valid and kind != "unsupported"
	var maximum := maxf(float(propulsion.get("max_rpm", 1.0)), 1.0)
	var idle := maxf(float(propulsion.get("idle_rpm", 0.0)), 0.0)
	var load := clampf(rpm / maximum, 0.0, 1.0) if valid else 0.0
	var firing := smoothstep(0.25 * idle, maxf(0.85 * idle, 1.0), maxf(rpm, 0.0)) if valid else 0.0
	var level := firing * lerpf(0.35, 1.0, load) * clampf(firing_fraction, 0.0, 1.0) if accepted else 0.0
	return {"kind": kind, "running": accepted, "level": level,
		"source_id": str(propulsion.get("id", SOURCE_ROLE)), "emissions_family": emissions_family(propulsion),
		"pump_ready": accepted and firing > 0.0 and throttle >= 0.08}


## A source may feed several outlets. The role alias and installation ID refer to
## the same accepted observation, never separate simulated engines.
static func source_map(observation: Dictionary) -> Dictionary:
	var result := {SOURCE_ROLE: observation}
	var installation := str(observation.get("source_id", ""))
	if not installation.is_empty() and installation != SOURCE_ROLE:
		result[installation] = observation
	return result


## Empty capability is explicit for an aircraft whose engine/model pairing has no
## verified outlets. This same record is usable by fixed-wing and rotorcraft hosts.
static func capabilities(bindings: Dictionary, unavailable_reason: String = "") -> Dictionary:
	var source_outlets := PackedStringArray()
	var show_outlets := PackedStringArray()
	for slot: Dictionary in bindings.get("smoke_slots", []):
		if str(slot.get("kind", "")) == "source":
			source_outlets.append(str(slot.id))
		elif str(slot.get("kind", "")) == "show":
			show_outlets.append(str(slot.id))
	return {"contract": "openrc-smoke-capabilities v1", "source_outlets": source_outlets,
		"show_outlets": show_outlets, "source_available": not source_outlets.is_empty(),
		"show_available": not show_outlets.is_empty(), "reason": unavailable_reason}
