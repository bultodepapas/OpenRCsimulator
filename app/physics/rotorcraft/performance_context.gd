# HELI-09: immutable, validated model bundle for repeated joint-stage queries.
# Runtime state is never stored here; every call supplies its own RK-stage data.
extends RefCounted

const MainRotor = preload("res://physics/rotorcraft/main_rotor.gd")
const TailRotor = preload("res://physics/rotorcraft/tail_rotor.gd")
const Airframe = preload("res://physics/rotorcraft/airframe.gd")
const LAW: String = "openrc-helicopter-aero-performance-context-v1"
const KEYS: Array = ["law", "main_model", "tail_model", "airframe_model", "flow_floor_m_s",
	"fin_tail_wake_fraction", "height_over_radius", "loss", "instability"]


static func prepare(main_model: Dictionary, tail_model: Dictionary, airframe_model: Dictionary,
		flow_floor_m_s: float, fin_tail_wake_fraction: float, height_over_radius: float = -1.0,
		loss: float = 1.0, instability: float = 1.0) -> Dictionary:
	if not MainRotor._prepared(main_model) or not TailRotor._prepared(tail_model) \
		or not Airframe._prepared(airframe_model):
		return {"ok": false}
	if not _finite([flow_floor_m_s, fin_tail_wake_fraction, height_over_radius, loss, instability]) \
		or flow_floor_m_s <= 0.0 or fin_tail_wake_fraction < 0.0 or fin_tail_wake_fraction > 1.0 \
		or (height_over_radius < 0.0 and height_over_radius != -1.0) \
		or loss < 1.0 or instability < 0.0 or instability > 1.0:
		return {"ok": false}
	# Preserve the joint stage's exact compatibility rules for atmospheric
	# density, main radius and fin blockage/loading geometry.
	if main_model.rho_kg_m3 != tail_model.rho_kg_m3 \
		or main_model.rho_kg_m3 != airframe_model.rho_kg_m3 \
		or main_model.rotor_radius_m != tail_model.main_rotor_radius_m \
		or tail_model.vertical_fin_area_m2 != airframe_model.vertical_fin_area_m2:
		return {"ok": false}
	var context: Dictionary = {
		"law": LAW,
		"main_model": main_model,
		"tail_model": tail_model,
		"airframe_model": airframe_model,
		"flow_floor_m_s": flow_floor_m_s,
		"fin_tail_wake_fraction": fin_tail_wake_fraction,
		"height_over_radius": height_over_radius,
		"loss": loss,
		"instability": instability,
	}
	context.make_read_only()
	return {"ok": true, "context": context}


# Per-stage check is deliberately structural. Component contexts were fully
# checked at preparation and are detached, flat, read-only scalar dictionaries.
static func has_valid_header(context: Dictionary) -> bool:
	if not context.is_read_only() or context.get("law") != LAW or context.size() != KEYS.size() \
		or not context.has_all(KEYS):
		return false
	var main_model: Variant = context.main_model
	var tail_model: Variant = context.tail_model
	var airframe_model: Variant = context.airframe_model
	if typeof(main_model) != TYPE_DICTIONARY or typeof(tail_model) != TYPE_DICTIONARY \
		or typeof(airframe_model) != TYPE_DICTIONARY \
		or not MainRotor._prepared_header(main_model) or not TailRotor._prepared_header(tail_model) \
		or not Airframe._prepared_header(airframe_model):
		return false
	for key: String in ["flow_floor_m_s", "fin_tail_wake_fraction", "height_over_radius", "loss", "instability"]:
		if typeof(context[key]) != TYPE_FLOAT or not is_finite(context[key]):
			return false
	return true


static func _finite(values: Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true
