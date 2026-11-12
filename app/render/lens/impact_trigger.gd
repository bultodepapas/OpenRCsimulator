## LENS-02 (docs/plans/lens-screen-effects.md §5.1, §7.2): pure admission of accepted contact events for the lens
## effects. It reads the detached session.contact_events() records only; it never reads solver internals and never
## writes anything back. Every admitted record keeps the event's tick and id, so a replay admits the same records.
extends RefCounted

## Contact energy (J) at which a person strike reaches full strength: about 1.5 kg at 9 m/s. Art constant.
const FULL_STRENGTH_J := 60.0
## Below this a person contact is a brush: a red edge pulse, no curtain.
const BRUSH_STRENGTH := 0.08
const PROPELLER_BONUS := 0.25
## Ground and obstacle contacts slower than this leave no grime.
const GRIME_MIN_SPEED_MPS := 2.5
const MAX_SEEN := 512


## One event → {kind, strength, speed_mps, point_ned, tick, id} or {} when it means nothing to the lens.
## kind: "person", "ground", "water", "mud", "foliage", "obstacle".
static func classify(event: Dictionary, mass_kg: float) -> Dictionary:
	if str(event.get("lifecycle", "")) != "new":
		return {}
	var point: Variant = event.get("point_ned")
	if typeof(point) != TYPE_PACKED_FLOAT64_ARRAY or (point as PackedFloat64Array).size() != 3:
		return {}
	var source := str(event.get("source", ""))
	var measure: Dictionary = event.get("measure", {}) if typeof(event.get("measure")) == TYPE_DICTIONARY else {}
	var speed := maxf(_finite(measure.get("speed_mps", 0.0)), 0.0)
	var energy := 0.5 * maxf(mass_kg, 0.0) * speed * speed
	if measure.has("impact_energy_j"):
		energy = maxf(_finite(measure.get("impact_energy_j")), 0.0)
	var kind := ""
	match source:
		"scenery":
			var obstacle := str(event.get("obstacle_kind", ""))
			if obstacle == "person":
				kind = "person"
			elif obstacle.begins_with("tree") or obstacle in ["bush", "hedge", "crop"]:
				kind = "foliage"
			else:
				kind = "obstacle"
		"hull":
			if str(event.get("event_type", "")) not in ["impact", "hull_contact"]:
				return {}
			kind = "ground"
		"lake":
			kind = "water" if str(event.get("material", "")) == "water" else "mud"
		_:
			return {}
	if kind != "person" and speed < GRIME_MIN_SPEED_MPS:
		return {}
	var strength := 0.0
	if kind == "person":
		strength = person_strength(energy, str(event.get("probe_source", "")) == "propeller")
	else:
		strength = clampf(speed / 20.0, 0.0, 1.0)
	return {
		"kind": kind,
		"strength": strength,
		"speed_mps": speed,
		"energy_j": energy,
		"point_ned": (point as PackedFloat64Array).duplicate(),
		"tick": int(event.get("tick", 0)),
		"id": str(event.get("event_id", "")),
	}


static func person_strength(energy_j: float, propeller: bool) -> float:
	var s := clampf(maxf(energy_j, 0.0) / FULL_STRENGTH_J, 0.0, 1.0)
	# A square root keeps a 10 J strike visible (≈ 0.4) while 60 J and more saturate.
	s = sqrt(s)
	if propeller:
		s += PROPELLER_BONUS
	return clampf(s, 0.0, 1.0)


## How much of the screen a strike paints, by view and distance to the camera. The player's own strike is full.
## The pilot view is an eye far from most strikes; the other cameras are near the aircraft that struck.
static func view_factor(view: String, distance_m: float, player: bool) -> float:
	if player:
		return 1.0
	var d := maxf(distance_m, 0.0)
	if view == "pilot":
		return clampf(1.5 - d / 60.0, 0.35, 1.0)
	return clampf(1.4 - d / 50.0, 0.35, 1.0)


## New admissible records from a contact snapshot, in event order. `seen` (event id → tick) is updated and bounded;
## events at or before `floor_tick` (a reset or restored checkpoint) are ignored.
static func admit(snapshot: Dictionary, seen: Dictionary, floor_tick: int, mass_kg: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var events: Variant = snapshot.get("events", [])
	if typeof(events) != TYPE_ARRAY:
		return out
	for raw: Variant in events:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = raw
		var id := str(event.get("event_id", ""))
		var tick := int(event.get("tick", 0))
		if id.is_empty() or tick <= floor_tick or seen.has(id):
			continue
		seen[id] = tick
		var record := classify(event, mass_kg)
		if not record.is_empty():
			out.append(record)
	if seen.size() > MAX_SEEN:
		var oldest: Array = seen.keys()
		oldest.sort_custom(func(a: Variant, b: Variant) -> bool: return int(seen[a]) < int(seen[b]))
		for index in seen.size() - MAX_SEEN:
			seen.erase(oldest[index])
	return out


static func _finite(value: Variant) -> float:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return 0.0
	var f := float(value)
	return f if is_finite(f) else 0.0
