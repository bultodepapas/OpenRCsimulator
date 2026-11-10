## BL-19a: Workshop compiler for the `openrc-airship v1` family. Detached and pure: every call rebuilds the candidate
## from the pinned base bytes and a recipe validated by the shared WorkshopParameters contract.
##
## Virtual size is a Froude similarity transform at fixed air and gas density, driven by each quantity's declared unit
## (lengths s, areas s², volumes and masses s³, forces s³, speeds and times √s, rates 1/√s, power s^3.5). Buoyancy,
## gas, envelope and every component mass all scale with s³, so the lift budget, the ballast fraction and the static
## trim (CG under CB) are preserved exactly. Unknown units are refused rather than guessed. Weight multiplies the
## equipment inventory only; the ballast is re-derived for the declared weigh-off, and a build that cannot reach it
## is refused. Power multiplies shaft power and, by momentum theory, static thrust by power^(2/3). Control travel
## multiplies the fin surface throw. Measured component masses replace inventory entries at original scale.
## These are similarity estimates, not measured blimps; the session and its own checks still decide what can fly.
extends RefCounted

const Data := preload("res://physics/airship/airship_data.gd")
const Parameters := preload("res://workshop/parameters.gd")

const FAMILY_FORMAT := "openrc-airship v1"
const COMPILER_VERSION := "openrc-airship-workshop-v1-similarity-1"
const MEASURED_MASS_COMPILER_VERSION := "openrc-airship-workshop-v1-measured-mass-1"
const MIN_SCALE := 0.4
const MAX_SCALE := 2.0
const MAX_FIN_TRAVEL_DEG := 30.0
const REFERENCE_DENSITY_KG_M3 := 1.225
const GRAVITY := 9.80665

## Exponent of the scale factor per declared unit (Froude similarity, fixed densities and voltage).
const UNIT_EXPONENTS := {
	"1": 0.0, "deg": 0.0, "V": 0.0, "kg/m^3": 0.0,
	"m": 1.0, "m^2": 2.0, "m^3": 3.0, "kg": 3.0, "kg/m^2": 1.0, "N": 3.0,
	"m/s": 0.5, "s": 0.5, "deg/s": -0.5, "W": 3.5,
	"N/m": 2.0, "N*s/m": 2.5, "N*m*s": 4.5,
	"A*h": 3.0, "ohm": -3.0,
}


static func is_family(base: Dictionary) -> bool:
	return base.get("format", "") == FAMILY_FORMAT


static func capabilities(base: Dictionary) -> Dictionary:
	var parsed := Data.parse(base.duplicate(true))
	var ok: bool = parsed.ok
	return {
		"vehicle": "airship",
		"scale": ok, "weight": ok, "power": ok, "controls": ok,
		"control_aileron": false, "control_elevator": false, "control_rudder": false,
		"tank_capacity": false, "mass_edits": ok, "mass_policy": false,
		"scale_bounds": [MIN_SCALE, MAX_SCALE],
		"note": "Buoyant similarity: size scales envelope, gas and every mass together; weight scales the equipment, power the motors, travel the fins." \
			if ok else "Base data fails %s validation: %s" % [FAMILY_FORMAT, "; ".join(parsed.errors)],
	}


static func defaults() -> Dictionary:
	return Parameters.defaults()


static func version_for_recipe(recipe: Dictionary) -> String:
	var edits: Variant = recipe.get("mass_edits", [])
	return MEASURED_MASS_COMPILER_VERSION if edits is Array and not edits.is_empty() else COMPILER_VERSION


static func compile(base: Dictionary, recipe: Dictionary) -> Dictionary:
	var parsed: Dictionary = Parameters.validate(recipe)
	if not parsed.ok:
		return _failure(parsed.errors)
	var values: Dictionary = parsed.values
	var errors := PackedStringArray()
	var base_raw: Dictionary = base.duplicate(true)
	if not is_family(base_raw):
		return _failure(PackedStringArray(["Workshop airship compiler requires %s data." % FAMILY_FORMAT]))
	var base_parse := Data.parse(base_raw.duplicate(true))
	if not base_parse.ok:
		return _failure(base_parse.errors)
	var scale: float = float(values.scale)
	var weight: float = float(values.weight_multiplier)
	var power: float = float(values.power_multiplier)
	var travel: float = float(values.control_multiplier)
	if scale < MIN_SCALE or scale > MAX_SCALE:
		errors.append("scale: the blimp supports %s–%s (%.1f–%.1f m envelope)" % [str(MIN_SCALE), str(MAX_SCALE),
			MIN_SCALE * _length(base_raw), MAX_SCALE * _length(base_raw)])
	for surface: String in Parameters.CONTROL_SURFACES:
		if values.has("control_multiplier_" + surface):
			errors.append("control_multiplier_%s: the blimp's inverted-Y fins have no separate %s surface" % [surface, surface])
	if float(values.tank_capacity_multiplier) != 1.0:
		errors.append("tank_capacity_multiplier: the blimp has no fuel tanks")
	var edits: Array = values.get("mass_edits", [])
	if not edits.is_empty() and (scale != 1.0 or weight != 1.0):
		errors.append("mass_edits: measured components require original size and weight")
	if not errors.is_empty():
		return _failure(errors)
	var candidate: Dictionary = base_raw.duplicate(true)
	for edit: Dictionary in edits:
		var found := false
		for item: Dictionary in candidate.get("masses", []):
			if item.get("id") == edit.id:
				item.mass = {value = float(edit.mass_kg), unit = "kg", kind = "measured", source = str(edit.source)}
				found = true
		if not found:
			errors.append("mass_edits: unknown component '%s'" % edit.id)
	if not errors.is_empty():
		return _failure(errors)
	if scale != 1.0:
		var refused := PackedStringArray()
		for key: String in candidate.keys():
			if key in ["format", "id", "name", "status", "provenance", "presentation"]:
				continue
			candidate[key] = _scaled(candidate[key], scale, key, refused)
		if not refused.is_empty():
			return _failure(refused)
	if weight != 1.0:
		for item: Dictionary in candidate.get("masses", []):
			item.mass.value = float(item.mass.value) * weight
	if power != 1.0:
		for rotor: Dictionary in candidate.get("rotors", []):
			rotor.static_thrust_max.value = float(rotor.static_thrust_max.value) * pow(power, 2.0 / 3.0)
			rotor.max_shaft_power.value = float(rotor.max_shaft_power.value) * power
	if travel != 1.0:
		for fin: Dictionary in candidate.get("fins", []):
			var throw := float(fin.travel.value) * travel
			if throw > MAX_FIN_TRAVEL_DEG:
				errors.append("control_multiplier: fin travel %.1f deg exceeds the %.0f deg linkage limit" % [throw, MAX_FIN_TRAVEL_DEG])
			fin.travel.value = throw
	if not errors.is_empty():
		return _failure(errors)
	if values.has("id"):
		candidate.id = str(values.id)
	var checked := Data.parse(candidate.duplicate(true))
	if not checked.ok:
		return _failure(checked.errors)
	var requested := float(checked.data.ballast.default_heaviness)
	var derived := Data.derive(checked.data, REFERENCE_DENSITY_KG_M3, GRAVITY, requested)
	if not derived.ok:
		return _failure(derived.errors)
	var model: Dictionary = derived.model
	if float(model.heaviness_kg) > requested + 1.0e-6:
		return _failure(PackedStringArray(["weight: the equipment is %.0f g too heavy for the envelope to reach the %.0f g weigh-off without ballast" \
			% [1000.0 * (float(model.heaviness_kg) - requested), 1000.0 * requested]]))
	if float(model.heaviness_kg) < requested - 1.0e-6:
		return _failure(PackedStringArray(["weight: the equipment is too light; the %.0f g weigh-off needs more ballast than the %.0f g keel limit" \
			% [1000.0 * requested, 1000.0 * float(model.ballast.max_mass)]]))
	var base_derived := Data.derive(base_parse.data, REFERENCE_DENSITY_KG_M3, GRAVITY, float(base_parse.data.ballast.default_heaviness))
	var summary := _summary(base_derived.model if base_derived.ok else {}, model, checked.data, values)
	return {ok = true, errors = PackedStringArray(), raw = candidate, data = {ok = true, data = checked.data, model = model},
		summary = summary}


## Recursively scales every {value, unit} quantity of a data block by s^exponent(unit).
static func _scaled(node: Variant, scale: float, path: String, refused: PackedStringArray) -> Variant:
	if node is Dictionary:
		if node.has("value") and node.has("unit"):
			var unit := str(node.unit)
			if not UNIT_EXPONENTS.has(unit):
				refused.append("%s: unit '%s' has no similarity rule; size change refused" % [path, unit])
				return node
			var factor := pow(scale, float(UNIT_EXPONENTS[unit]))
			var out: Dictionary = node.duplicate(true)
			out.value = _times(node.value, factor)
			return out
		var copy := {}
		for key: Variant in node.keys():
			copy[key] = _scaled(node[key], scale, path + "." + str(key), refused)
		return copy
	if node is Array:
		var items: Array = []
		for i in node.size():
			items.append(_scaled(node[i], scale, "%s[%d]" % [path, i], refused))
		return items
	return node


static func _times(value: Variant, factor: float) -> Variant:
	if value is Array:
		var out: Array = []
		for item: Variant in value:
			out.append(_times(item, factor))
		return out
	if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
		return float(value) * factor
	return value


static func _length(raw: Dictionary) -> float:
	return float(raw.get("envelope", {}).get("length", {}).get("value", 5.0))


static func _summary(base_model: Dictionary, model: Dictionary, data: Dictionary, values: Dictionary) -> Dictionary:
	var thrust := 0.0
	var shaft := 0.0
	for rotor: Dictionary in data.rotors:
		thrust += float(rotor.static_thrust) if rotor.id != "stern_lateral" else 0.0
		shaft += float(rotor.shaft_power)
	var cg: PackedFloat64Array = model.cg
	var cb: PackedFloat64Array = model.cb
	# Static hang: the pendulum settles with the CG straight below the CB.
	var trim_deg := rad_to_deg(atan2(cg[0] - cb[0], cg[2] - cb[2]))
	var base_mass := float(base_model.get("mass", model.mass))
	return {
		"vehicle": "airship",
		"base_aircraft_id": str(base_model.get("id", data.id)),
		"effective_model_id": str(data.id),
		"name": str(values.get("name", data.id)),
		"scale": float(values.scale),
		"mass_policy": "buoyant_geometric",
		"weight_multiplier": float(values.weight_multiplier),
		"mass_ratio": float(model.mass) / base_mass if base_mass > 0.0 else 1.0,
		"mass_kg": float(model.mass),
		"envelope_length_m": float(data.envelope.length),
		"envelope_diameter_m": float(data.envelope.max_diameter),
		"envelope_volume_m3": float(data.envelope.volume),
		"buoyancy_n": float(model.buoyancy_n),
		"ballast_kg": float(model.ballast_mass),
		"weigh_off_kg": float(model.heaviness_kg),
		"static_trim_deg": trim_deg,
		"power_multiplier": float(values.power_multiplier),
		"static_thrust_n": thrust,
		"static_power_w": shaft,
		"propulsion_family": "airship_rotors",
		"control_multiplier": float(values.control_multiplier),
		"fin_travel_deg": float(data.fins[0].travel) if not data.fins.is_empty() else 0.0,
		"tank_capacity_multiplier": 1.0,
		"capabilities": capabilities_from_values(),
		"compiler_version": version_for_recipe(values),
		"power_reference_note": "Static thrust and shaft power of the side and stern motors at 1.225 kg/m³; similarity estimate, not a measured motor rating.",
	}


static func capabilities_from_values() -> Dictionary:
	return {"vehicle": "airship", "scale": true, "weight": true, "power": true, "controls": true,
		"control_aileron": false, "control_elevator": false, "control_rudder": false, "tank_capacity": false,
		"mass_edits": true, "mass_policy": false, "scale_bounds": [MIN_SCALE, MAX_SCALE]}


static func _failure(errors: PackedStringArray) -> Dictionary:
	return {ok = false, errors = errors, raw = {}, data = {ok = false, errors = errors.duplicate(), model = {}}, summary = {}}
