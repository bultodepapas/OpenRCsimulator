## FUEL-02: liquid-fuel property registry (openrc-fuel-registry v1). One home for fuel densities.
## A blend's density is the volume-weighted sum of its component densities at the blend's reference
## temperature (ideal mixing). Components at another reference temperature need a declared slope.
extends RefCounted
const Timing:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/metrics.gd")

const FORMAT := "openrc-fuel-registry v1"
const DEFAULT_PATH := "res://data/fuels/openrc-fuel-registry.json"
const KINDS := ["manual", "measured", "borrowed", "estimated", "derived"]
const FAMILIES := ["glow", "gasoline", "kerosene"]
const ROOT_KEYS := ["format", "note", "components", "blends"]
const BLEND_KEYS := ["name", "family", "volume_fractions", "reference_temperature", "relative_uncertainty", "use"]
const FRACTION_SUM_TOLERANCE := 1.0e-12
const TEMPERATURE_MATCH_K := 1.0e-9


static func load_file(path: String = DEFAULT_PATH) -> Dictionary:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return _fail("Cannot read fuel registry: " + path)
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK:
		return _fail("Invalid fuel registry JSON: " + json.get_error_message())
	var result: Dictionary = prepare(json.data)
	if result.ok:
		var hashing := HashingContext.new()
		hashing.start(HashingContext.HASH_SHA256)
		hashing.update(bytes)
		result.identity = {format = FORMAT, path = path, sha256 = hashing.finish().hex_encode()}
	return result


## Validate and derive. Returns {ok, components: {id: {...}}, blends: {id: {density_kg_m3, ...}}} or {ok=false, message}.
static func prepare(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not _exact_keys(raw, ROOT_KEYS, []) or raw.format != FORMAT:
		return _fail("Fuel registry root must hold exactly format, note, components and blends with format " + FORMAT)
	if not raw.components is Dictionary or raw.components.is_empty() or not raw.blends is Dictionary or raw.blends.is_empty():
		return _fail("Fuel registry needs at least one component and one blend")
	var components: Dictionary = {}
	for id: Variant in raw.components:
		var component: Dictionary = _component(id, raw.components[id])
		if not component.ok:
			return component
		components[id] = component.value
	var blends: Dictionary = {}
	for id: Variant in raw.blends:
		var blend: Dictionary = _blend(id, raw.blends[id], components)
		if not blend.ok:
			return blend
		blends[id] = blend.value
	return {ok = true, components = components, blends = blends}


## Density of a prepared blend at temperature_k (NAN = its reference temperature).
static func blend_density(prepared: Dictionary, blend_id: String, temperature_k: float = NAN) -> Dictionary:
	if not prepared.get("ok", false) or not prepared.blends.has(blend_id):
		return _fail("Unknown fuel blend: " + blend_id)
	var blend: Dictionary = prepared.blends[blend_id]
	if is_nan(temperature_k) or absf(temperature_k - blend.reference_temperature_k) <= TEMPERATURE_MATCH_K:
		return {ok = true, density_kg_m3 = blend.density_kg_m3}
	if not is_finite(temperature_k) or temperature_k < 200.0 or temperature_k > 400.0:
		return _fail("Fuel temperature must be finite and within [200, 400] K")
	if is_nan(blend.density_slope_kg_m3_k):
		return _fail("Blend %s has a component without a density slope; only its reference temperature is supported" % blend_id)
	var density: float = blend.density_kg_m3 + blend.density_slope_kg_m3_k * (temperature_k - blend.reference_temperature_k)
	if not is_finite(density) or density <= 0.0:
		return _fail("Blend density is not physical at this temperature")
	return {ok = true, density_kg_m3 = density}


static func _component(id: Variant, raw: Variant) -> Dictionary:
	if not id is String or id.strip_edges().is_empty():
		return _fail("Fuel component id must be a nonempty string")
	if not raw is Dictionary or not _exact_keys(raw, ["name", "density", "reference_temperature"], ["density_slope"]):
		return _fail("Fuel component %s must hold name, density, reference_temperature and optional density_slope" % id)
	if not raw.name is String or raw.name.strip_edges().is_empty():
		return _fail("Fuel component %s needs a name" % id)
	var density: Dictionary = _quantity(raw.density, "kg/m3", 100.0, 2000.0)
	var temperature: Dictionary = _quantity(raw.reference_temperature, "K", 200.0, 400.0)
	if not density.ok or not temperature.ok:
		return _fail("Fuel component %s density/reference temperature: %s" % [id, density.get("message", temperature.get("message", ""))])
	var slope: float = NAN
	if raw.has("density_slope"):
		var slope_quantity: Dictionary = _quantity(raw.density_slope, "kg/m3/K", -5.0, 0.0)
		if not slope_quantity.ok:
			return _fail("Fuel component %s density slope: %s" % [id, slope_quantity.message])
		slope = slope_quantity.value
	return {ok = true, value = {name = raw.name, density_kg_m3 = density.value,
		reference_temperature_k = temperature.value, density_slope_kg_m3_k = slope}}


static func _blend(id: Variant, raw: Variant, components: Dictionary) -> Dictionary:
	if not id is String or id.strip_edges().is_empty():
		return _fail("Fuel blend id must be a nonempty string")
	if not raw is Dictionary or not _exact_keys(raw, BLEND_KEYS, []):
		return _fail("Fuel blend %s must hold exactly %s" % [id, ", ".join(BLEND_KEYS)])
	if not raw.family in FAMILIES or not raw.name is String or raw.name.strip_edges().is_empty() \
			or not raw.use is String or raw.use.strip_edges().is_empty():
		return _fail("Fuel blend %s needs a name, a use and a family in %s" % [id, str(FAMILIES)])
	var temperature: Dictionary = _quantity(raw.reference_temperature, "K", 200.0, 400.0)
	var uncertainty: Dictionary = _quantity(raw.relative_uncertainty, "1", 0.0, 0.2)
	if not temperature.ok or not uncertainty.ok:
		return _fail("Fuel blend %s reference temperature/uncertainty is invalid" % id)
	if not raw.volume_fractions is Dictionary or raw.volume_fractions.is_empty():
		return _fail("Fuel blend %s needs volume fractions" % id)
	var total: float = 0.0
	var density: float = 0.0
	var slope: float = 0.0
	for component_id: Variant in raw.volume_fractions:
		var fraction: Variant = raw.volume_fractions[component_id]
		if not components.has(component_id):
			return _fail("Fuel blend %s names an unknown component %s" % [id, str(component_id)])
		if typeof(fraction) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(fraction)) or float(fraction) <= 0.0 or float(fraction) > 1.0:
			return _fail("Fuel blend %s fraction of %s must be in (0, 1]" % [id, component_id])
		var component: Dictionary = components[component_id]
		var component_density: float = component.density_kg_m3
		var offset: float = temperature.value - component.reference_temperature_k
		if absf(offset) > TEMPERATURE_MATCH_K:
			if is_nan(component.density_slope_kg_m3_k):
				return _fail("Fuel blend %s: component %s is referenced at another temperature and has no density slope" % [id, component_id])
			component_density += component.density_slope_kg_m3_k * offset
		total += float(fraction)
		density += float(fraction) * component_density
		slope += float(fraction) * component.density_slope_kg_m3_k  # NAN propagates when a slope is missing
	if absf(total - 1.0) > FRACTION_SUM_TOLERANCE:
		return _fail("Fuel blend %s volume fractions sum to %.15f, not 1" % [id, total])
	if not is_finite(density) or density <= 0.0:
		return _fail("Fuel blend %s density is not physical" % id)
	return {ok = true, value = {name = raw.name, family = raw.family, density_kg_m3 = density,
		reference_temperature_k = temperature.value, density_slope_kg_m3_k = slope,
		relative_uncertainty = uncertainty.value, volume_fractions = raw.volume_fractions.duplicate()}}


static func _quantity(raw: Variant, unit: String, low: float, high: float) -> Dictionary:
	if not raw is Dictionary or not _exact_keys(raw, ["value", "unit", "kind", "source"], []):
		return _fail("quantity must hold exactly value, unit, kind and source")
	if raw.unit != unit or not raw.kind in KINDS or not raw.source is String or raw.source.strip_edges().is_empty():
		return _fail("quantity needs unit %s, a known kind and a source" % unit)
	if typeof(raw.value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(raw.value)):
		return _fail("quantity value must be a finite number")
	var value: float = float(raw.value)
	if value < low or value > high:
		return _fail("quantity %s %s is outside [%s, %s]" % [str(value), unit, str(low), str(high)])
	return {ok = true, value = value}


static func _exact_keys(value: Dictionary, required: Array, optional: Array) -> bool:
	for key: Variant in required:
		if not value.has(key):
			return false
	for key: Variant in value:
		if not key in required and not key in optional:
			return false
	return true


static func _fail(message: String) -> Dictionary:
	return {ok = false, message = message}
