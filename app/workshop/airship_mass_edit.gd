## BL-19e: measured component masses for the `openrc-airship v1` family, in the shapes of workshop/mass_edit.gd.
## Components are the stable-ID `masses[]` inventory; positions never change and the keel ballast is re-derived by
## the airship reader for the declared weigh-off. Positions and CG are reported from the model origin O in the
## Workshop's x aft, y right, z up convention (the blimp has no wing leading-edge datum).
extends RefCounted

const Data := preload("res://physics/airship/airship_data.gd")
const Compiler := preload("res://workshop/airship_compiler.gd")

const MIN_MASS_KG := 0.001
const MAX_MASS_KG := 5.0
const MAX_EDITS := 32
const MAX_SOURCE_LENGTH := 256


static func is_family(base: Dictionary) -> bool:
	return Compiler.is_family(base)


static func inspect(base: Dictionary) -> Dictionary:
	var parsed := Data.parse(base.duplicate(true))
	if not parsed.ok:
		return _failure(parsed.errors)
	var derived := Data.derive(parsed.data, Compiler.REFERENCE_DENSITY_KG_M3, Compiler.GRAVITY, float(parsed.data.ballast.default_heaviness))
	if not derived.ok:
		return _failure(derived.errors)
	var rows: Array[Dictionary] = []
	for item: Dictionary in base.get("masses", []):
		var p: Array = item.position.value
		rows.append({"id": str(item.id), "name": str(item.get("name", item.id)).replace("_", " "), "mass_kg": float(item.mass.value),
			"mass_kind": str(item.mass.kind), "mass_source": str(item.mass.source),
			"position_le_m": [-float(p[0]), float(p[1]), -float(p[2])], "editable": true, "reason": ""})
	var cg: PackedFloat64Array = derived.model.cg
	return {"ok": true, "errors": PackedStringArray(), "aircraft_id": str(base.id), "inventory": rows,
		"weighing_state": "as flown with the derived keel ballast", "mass_kg": float(derived.model.mass),
		"cg_le_m": PackedFloat64Array([-cg[0], cg[1], -cg[2]]), "datum_label": "O", "cg_tolerance_m": 0.01, "position_edits_supported": false,
		"mass_bounds_kg": [MIN_MASS_KG, MAX_MASS_KG], "mass_bounds_source": "workshop/airship_mass_edit.gd"}


static func apply_to_validated_base(base: Dictionary, edits: Array) -> Dictionary:
	if edits.size() > MAX_EDITS:
		return _failure(PackedStringArray(["Mass edit has more than %d entries." % MAX_EDITS]))
	var ids := {}
	for item: Dictionary in base.get("masses", []):
		ids[str(item.id)] = true
	var accepted: Array[Dictionary] = []
	var seen := {}
	for edit: Variant in edits:
		if not edit is Dictionary or edit.size() != 3 or not edit.has_all(["id", "mass_kg", "source"]):
			return _failure(PackedStringArray(["Each mass edit must contain exactly id, mass_kg and source."]))
		var id := str(edit.id)
		if seen.has(id) or not ids.has(id):
			return _failure(PackedStringArray(["Mass edit ID '%s' is duplicated or not in the blimp inventory." % id]))
		seen[id] = true
		if typeof(edit.mass_kg) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(edit.mass_kg)) \
				or float(edit.mass_kg) < MIN_MASS_KG or float(edit.mass_kg) > MAX_MASS_KG:
			return _failure(PackedStringArray(["Mass edit ID '%s' mass_kg must lie within [0.001, 5.0] kg." % id]))
		var source := str(edit.source).strip_edges()
		if typeof(edit.source) != TYPE_STRING or source.is_empty() or source.length() > MAX_SOURCE_LENGTH:
			return _failure(PackedStringArray(["Mass edit ID '%s' needs a measurement source of at most %d characters." % [id, MAX_SOURCE_LENGTH]]))
		accepted.append({"id": id, "mass_kg": float(edit.mass_kg), "source": source})
	var recipe := {"mass_edits": accepted.duplicate(true)}
	var compiled: Dictionary = Compiler.compile(base, recipe)
	if not compiled.ok:
		return _failure(compiled.errors)
	var applied := PackedStringArray()
	for edit: Dictionary in accepted:
		applied.append(edit.id)
	return {"ok": true, "errors": PackedStringArray(), "raw": compiled.raw, "data": compiled.data, "applied_ids": applied,
		"edits": accepted.duplicate(true), "mass_kind": "measured"}


static func unsupported(tool: String) -> Dictionary:
	return _failure(PackedStringArray(["%s is a fixed-wing weighing tool; the blimp's balance comes from its derived keel ballast." % tool]))


static func _failure(errors: PackedStringArray) -> Dictionary:
	return {"ok": false, "errors": errors}
