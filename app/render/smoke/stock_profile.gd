## Stock presentation choices, using the same authored mounts and bounded renderer as Workshop.
extends RefCounted

const Presentation := preload("res://workshop/presentation.gd")
const AVANTI_FAMILY := "sebart-avanti-s-a200-p100rx"
const SLOT_ID := "show_tailpipe"
const PRESET_ID := "avanti-white-tailpipe-v2"
const SmokeSystem := preload("res://render/smoke/smoke_system.gd")


## Fleet stock defaults use only verified registered outlets. No source outlet is
## invented from a wingtip or the aircraft origin. A silent source remains silent.
static func for_aircraft(bindings: Dictionary, propulsion: Dictionary) -> Dictionary:
	if str(bindings.get("visual_family", "")) == AVANTI_FAMILY:
		return profile(bindings)
	var slots: Dictionary = {}
	for slot: Dictionary in bindings.get("smoke_slots", []):
		slots[str(slot.id)] = slot
	if not slots.has("source_exhaust") or not slots.has("show_exhaust"):
		return {}
	var family := SmokeSystem.emissions_family(propulsion)
	if family in ["electric_clear", "turbine_clear", "unsupported"]:
		return {}
	var result := Presentation.defaults(bindings)
	result.visual_seed = 6103
	var natural := _entry("source_exhaust", 0.22, 1.25)
	natural["density"] = 0.08 if family == "gasoline_light" else 0.28
	natural["emission_rate_hz"] = 48.0
	natural["dispersion_m2_s"] = 0.018
	natural["jet_speed_mps"] = 2.0
	natural["buoyancy_mps"] = 0.18
	var show := _entry("show_exhaust", 1.4, 6.0)
	show["emission_rate_hz"] = 112.0
	show["dispersion_m2_s"] = 0.12
	show["jet_speed_mps"] = 3.0
	show["density"] = 1.0
	result.smoke = [natural, show]
	var checked := Presentation.validate(result, bindings)
	if not bool(checked.get("ok", false)):
		push_warning("Stock exhaust profile unavailable: " + str(checked.get("errors", [])))
		return {}
	return checked.profile


static func _entry(slot: String, width: float, lifetime: float) -> Dictionary:
	return {"slot": slot, "enabled": true, "color": "#EEF2F5FF", "amount": 1.0,
		"width_m": width, "lifetime_s": lifetime, "shape": "ribbon", "mode": "hold",
		"burst_s": 0.0, "pulse_period_s": 0.0, "pulse_duty": 0.0, "palette": [], "step_s": 0.0}


static func profile(bindings: Dictionary) -> Dictionary:
	if str(bindings.get("visual_family", "")) != AVANTI_FAMILY:
		return {}
	var available := false
	for slot: Dictionary in bindings.get("smoke_slots", []):
		if str(slot.get("id", "")) == SLOT_ID and str(slot.get("kind", "")) == "show":
			available = true
	if not available:
		return {}
	var result := Presentation.defaults(bindings)
	result.visual_seed = 6103
	result.smoke = [{
		"slot": SLOT_ID, "enabled": true, "color": "#F0F2F5FF", "amount": 1.0,
		"width_m": 2.0, "lifetime_s": 3.0, "shape": "ribbon", "mode": "hold",
		"burst_s": 0.0, "pulse_period_s": 0.0, "pulse_duty": 0.0, "palette": [], "step_s": 0.0,
		"emission_rate_hz": 240.0, "density": 0.4, "dispersion_m2_s": 0.28,
	}]
	var checked := Presentation.validate(result, bindings)
	if not bool(checked.get("ok", false)):
		push_warning("Stock smoke profile unavailable: " + str(checked.get("errors", [])))
		return {}
	return result


static func preset_id(bindings: Dictionary, propulsion: Dictionary) -> String:
	if str(bindings.get("visual_family", "")) == AVANTI_FAMILY: return PRESET_ID
	return "stock-" + SmokeSystem.emissions_family(propulsion) + "-v2"
