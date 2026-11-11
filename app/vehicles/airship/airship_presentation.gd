## BL-19c: Workshop presentation companion for the RC blimp (paint, markings, lighting layout).
## The authored source (SOURCE_PATH) names per-skin paint targets, envelope markings and light anchors. describe()
## assembles a customization companion v4 that the shared validators accept unchanged:
## AircraftCustomization.validate_bindings/apply and workshop/presentation.gd validate/identity_record.
## The blimp is not a fixed-wing catalog entry, so this file is its customization registry. Rendering only.
extends RefCounted

const Catalog := preload("res://vehicles/airship/airship_catalog.gd")
const Customization := preload("res://render/aircraft_customization.gd")
const Presentation := preload("res://workshop/presentation.gd")
const LightingSkins := preload("res://render/lighting/lighting_skins.gd")

const SOURCE_PATH := "res://data/airships/rc-blimp-5m-presentation.json"
const SOURCE_FORMAT := "openrc-airship-presentation-source"
const SOURCE_KEYS := ["format", "version", "visual_family", "frame", "provenance", "default_skin", "skins", "marking_slots",
	"smoke_slots", "lighting_layout"]
const SKIN_KEYS := ["id", "asset", "light_materials", "paint_slots"]
## The base registry already pins the closed presentation source set; the blimp reuses exactly those pins, so it is
## stale (and fails closed) whenever the fixed-wing registry is stale.
const REGISTRY_PATH := "res://data/aircraft_customization.json"
const MODEL_FORMAT := "openrc-airship-presentation-model v1"
const COMPANION_VERSION := 4
const SOURCE_PROOF_VERSION := 3
const SHA256_RE := "^[0-9a-f]{64}$"

## Development-only GLB byte hashes, keyed by path and file modification time.
static var _glb_hashes: Dictionary = {}


## {ok, visual_family, model_manifest_sha256, bindings, slots_sha256, skin_id, errors}. Empty skin_id = default skin.
## model_manifest_sha256 covers only the skin GLB pin and the data file's articulation bindings (the physical model),
## so editing paint, marking or lighting authoring never strands saved builds; those slots are covered by slots_sha256
## and its existing appearance-review flow, as for fixed-wing companions.
static func describe(skin_id := "") -> Dictionary:
	var loaded := _source()
	if not loaded.ok:
		return loaded
	var source: Dictionary = loaded.source
	var skin := skin_id if not skin_id.is_empty() else str(source.default_skin)
	var record := _skin_record(source, skin)
	if record.is_empty():
		return _failure("blimp presentation has no skin '%s'" % skin)
	var asset: Variant = record.get("asset")
	if not (asset is Dictionary) or not asset.has_all(["path", "sha256"]) or asset.size() != 2 \
			or str(asset.path) != str(Catalog.SKINS[skin].model) or not _matches(SHA256_RE, str(asset.sha256)):
		return _failure("blimp skin asset pin is malformed: " + skin)
	var glb_check := _check_glb(str(asset.path), str(asset.sha256))
	if not glb_check.ok:
		return glb_check
	var sources := _pinned_sources()
	if not sources.ok:
		return sources
	var articulation := _articulation()
	if not articulation.ok:
		return articulation
	var model_hash := _sha256_text(_canonical_json({
		"format": MODEL_FORMAT, "visual_family": Catalog.VISUAL_FAMILY, "skin": skin, "asset": asset,
		"articulation": articulation.presentation}))
	var paint_slots: Array = []
	for slot: Variant in record.paint_slots:
		if not (slot is Dictionary) or not (slot.get("targets") is Array):
			return _failure("blimp paint slot is malformed")
		var targets: Array = []
		for target: Variant in slot.targets:
			if not (target is Dictionary) or not (target.get("material") is String):
				return _failure("blimp paint target must name its expected material")
			var stripped: Dictionary = target.duplicate(true)
			stripped.erase("material")
			targets.append(stripped)
		var copy: Dictionary = slot.duplicate(true)
		copy.targets = targets
		paint_slots.append(copy)
	paint_slots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	var companion := {
		"format": Customization.COMPANION_FORMAT,
		"version": COMPANION_VERSION,
		"source_proof_version": SOURCE_PROOF_VERSION,
		"visual_family": Catalog.VISUAL_FAMILY,
		"model_manifest_sha256": model_hash,
		"paint_slots": paint_slots,
		"marking_slots": (source.marking_slots as Array).duplicate(true),
		"smoke_slots": (source.smoke_slots as Array).duplicate(true),
		"lighting_layout": (source.lighting_layout as Dictionary).duplicate(true),
		"presentation_engine_version": sources.engine_version,
		"presentation_sources": sources.records,
	}
	companion["slots_sha256"] = Presentation.bindings_sha256(companion)
	var checked := Customization.validate_bindings(companion, Catalog.VISUAL_FAMILY, model_hash)
	if not checked.ok:
		return {"ok": false, "errors": checked.errors}
	return {"ok": true, "visual_family": Catalog.VISUAL_FAMILY, "model_manifest_sha256": model_hash,
		"bindings": companion, "slots_sha256": str(companion.slots_sha256), "skin_id": skin, "errors": PackedStringArray()}


## Binds a built AirshipVisual (`visual.root`, `visual.active_skin`) to its companion and returns the builder-compatible
## dictionary that AircraftCustomization.apply, the lighting rig and the Workshop preview/thumbnail consume.
## Every paint target is checked against the authored material name, so a re-exported GLB that moves surfaces fails.
static func instance(visual: RefCounted, skin_id := "") -> Dictionary:
	var root: Node3D = visual.get("root") as Node3D
	if root == null:
		return _failure("blimp visual is not built")
	var skin := skin_id if not skin_id.is_empty() else str(visual.get("active_skin"))
	var described := describe(skin)
	if not described.ok:
		return described
	var source: Dictionary = _source().source
	var record := _skin_record(source, str(described.skin_id))
	var errors := PackedStringArray()
	for slot: Dictionary in record.paint_slots:
		for target: Dictionary in slot.targets:
			var mesh := root.get_node_or_null(NodePath(str(target.node_path))) as MeshInstance3D
			var surface := int(target.surface)
			if mesh == null or mesh.mesh == null or surface < 0 or surface >= mesh.mesh.get_surface_count():
				errors.append("blimp paint target is missing: %s#%d" % [target.node_path, surface])
				continue
			var material := mesh.get_active_material(surface)
			if not (material is StandardMaterial3D) or str(material.resource_name) != str(target.material):
				errors.append("blimp paint target material changed: %s#%d" % [target.node_path, surface])
	var bindings: Dictionary = described.bindings
	for slot: Dictionary in bindings.marking_slots:
		for target: Dictionary in slot.targets:
			if not (root.get_node_or_null(NodePath(str(target.node_path))) is MeshInstance3D):
				errors.append("blimp marking host is missing: " + str(target.node_path))
	for group: String in ["anchors", "strips"]:
		for row: Dictionary in bindings.lighting_layout[group]:
			if str(row.node_path) != "." and not (root.get_node_or_null(NodePath(str(row.node_path))) is Node3D):
				errors.append("blimp lighting host is missing: " + str(row.node_path))
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	root.set_meta("aircraft_id", Catalog.STOCK_ID)
	root.set_meta("airship_skin", str(described.skin_id))
	root.set_meta("lighting_layout", (bindings.lighting_layout as Dictionary).duplicate(true))
	var projected := LightingSkins.project_bindings(root, bindings)
	root.set_meta("lighting_skin_bindings", projected.bindings)
	root.set_meta("lighting_skin_warnings", projected.warnings)
	# The delivered red top beacon lens follows the strobe group (dark in daylight/OFF, as fixed-wing lenses are).
	root.set_meta("light_material_groups", (record.light_materials as Dictionary).duplicate())
	return {"ok": true, "errors": PackedStringArray(), "root": root, "aircraft_id": Catalog.STOCK_ID,
		"vehicle": Catalog.VEHICLE, "visual_family": Catalog.VISUAL_FAMILY, "livery_id": str(described.skin_id),
		"model_manifest_sha256": str(described.model_manifest_sha256), "customization_bindings": bindings,
		"customization_slots_sha256": str(described.slots_sha256), "physical_propulsion_id": "",
		"physical_propulsion_kind": "", "exhausts": []}


## Skin ids that have authored presentation targets, default first.
static func skin_ids() -> Array:
	var loaded := _source()
	if not loaded.ok:
		return []
	var out: Array = [str(loaded.source.default_skin)]
	for record: Dictionary in loaded.source.skins:
		if not out.has(str(record.id)):
			out.append(str(record.id))
	return out


static func _source() -> Dictionary:
	if not FileAccess.file_exists(SOURCE_PATH):
		return _failure("blimp presentation source is missing")
	var text := FileAccess.get_file_as_string(SOURCE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary) or not _exact_keys(parsed, SOURCE_KEYS) or parsed.format != SOURCE_FORMAT \
			or not (parsed.version is float or parsed.version is int) or int(parsed.version) != 1 \
			or parsed.visual_family != Catalog.VISUAL_FAMILY or not (parsed.skins is Array) \
			or not (parsed.marking_slots is Array) or not (parsed.smoke_slots is Array) or not (parsed.lighting_layout is Dictionary):
		return _failure("blimp presentation source is malformed")
	var seen := {}
	for record: Variant in parsed.skins:
		if not (record is Dictionary) or not _exact_keys(record, SKIN_KEYS) or not Catalog.contains(str(record.id)) \
				or seen.has(str(record.id)) or not (record.paint_slots is Array) or not (record.light_materials is Dictionary):
			return _failure("blimp presentation skin record is malformed")
		seen[str(record.id)] = true
	if not seen.has(str(parsed.default_skin)) or str(parsed.default_skin) != Catalog.DEFAULT_SKIN:
		return _failure("blimp presentation default skin is not the catalog default")
	return {"ok": true, "source": parsed, "sha256": _sha256_text(text.replace("\r\n", "\n")), "errors": PackedStringArray()}


static func _skin_record(source: Dictionary, skin_id: String) -> Dictionary:
	for record: Dictionary in source.skins:
		if str(record.id) == skin_id:
			return record
	return {}


## The same proof-v3 source pins every base companion carries (they are generated together).
static func _pinned_sources() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REGISTRY_PATH)) if FileAccess.file_exists(REGISTRY_PATH) else null
	if not (parsed is Dictionary) or not (parsed.get("families") is Array):
		return _failure("customization registry is unavailable for presentation source pins")
	var records: Variant = null
	var engine := ""
	for family: Variant in parsed.families:
		if not (family is Dictionary) or int(family.get("source_proof_version", 0)) != SOURCE_PROOF_VERSION:
			continue
		if records == null:
			records = family.get("presentation_sources")
			engine = str(family.get("presentation_engine_version", ""))
		elif family.get("presentation_sources") != records or str(family.get("presentation_engine_version", "")) != engine:
			return _failure("customization registry families disagree on presentation source pins")
	if not (records is Array) or records.is_empty():
		return _failure("customization registry has no proof-v3 presentation source pins")
	return {"ok": true, "records": (records as Array).duplicate(true), "engine_version": engine, "errors": PackedStringArray()}


static func _articulation() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(Catalog.DATA_PATH)) if FileAccess.file_exists(Catalog.DATA_PATH) else null
	if not (parsed is Dictionary) or not (parsed.get("presentation") is Dictionary):
		return _failure("blimp data has no presentation bindings")
	return {"ok": true, "presentation": parsed.presentation, "errors": PackedStringArray()}


## In development the raw GLB is present and must match its pin; an exported build ships only the imported scene and
## relies on the pin (as the fixed-wing model manifests do through their proof package).
static func _check_glb(path: String, pinned: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": true, "errors": PackedStringArray()}
	var modified := FileAccess.get_modified_time(path)
	var cached: Dictionary = _glb_hashes.get(path, {})
	if cached.get("modified", -1) != modified:
		var context := HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		context.update(FileAccess.get_file_as_bytes(path))
		cached = {"modified": modified, "sha256": context.finish().hex_encode()}
		_glb_hashes[path] = cached
	if str(cached.sha256) != pinned:
		return _failure("blimp skin GLB does not match its presentation pin (update %s after a re-export): %s" % [SOURCE_PATH, path])
	return {"ok": true, "errors": PackedStringArray()}


static func _canonical_value(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		var keys: Array = value.keys()
		keys.sort()
		for key: Variant in keys:
			out[key] = _canonical_value(value[key])
		return out
	if value is Array:
		var out: Array = []
		for item: Variant in value:
			out.append(_canonical_value(item))
		return out
	if typeof(value) == TYPE_FLOAT and is_finite(float(value)) and float(value) == floor(float(value)):
		return int(value)
	return value


static func _canonical_json(value: Variant) -> String:
	return JSON.stringify(_canonical_value(value), "", true, true)


static func _sha256_text(text: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(text.to_utf8_buffer())
	return context.finish().hex_encode()


static func _exact_keys(value: Dictionary, keys: Array) -> bool:
	return value.size() == keys.size() and value.has_all(keys)


static func _matches(pattern: String, value: String) -> bool:
	var regex := RegEx.new()
	return regex.compile(pattern) == OK and regex.search(value) != null


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "errors": PackedStringArray([message])}
