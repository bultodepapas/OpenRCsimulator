extends RefCounted
## Converts one Phoenix RC model from the player's own local installation (AC-PX-R2).
##
## Input is the model's `.mod` definition; its sibling `.geo` and the in-folder textures named by the
## GEO materials are read from the same folder. Nothing is fetched elsewhere and stock content never
## leaves the player's machine. The result is an ordinary admitted GLB source (visual only), the
## placement the decoded definition implies, and a read-only summary of the Phoenix flight data.
## Phoenix tuning, inertia factors and airfoil labels are observations, never OpenRC physics.

const R := preload("res://workshop/creator/result.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const CreatorBytes := preload("res://workshop/creator/bytes.gd")
const Importer := preload("res://workshop/creator/source_importer.gd")
const ScriptContainer := preload("res://workshop/creator/phoenix/script_container.gd")
const Geo := preload("res://workshop/creator/phoenix/geo.gd")
const PhoenixTexture := preload("res://workshop/creator/phoenix/texture.gd")
const GlbWriter := preload("res://workshop/creator/phoenix/glb_writer.gd")

const FORMAT := "openrc-phoenix-visual-v1"
const NAMESPACE := "openrc_phoenix"
const STEP := "import"
const MAX_DEFINITION_BYTES := 8 * Limits.MIB
const MAX_FOLDER_ENTRIES := 4096
## Phoenix normalizes the visual span to about 100 GEO units; `Physical.Size` is metres per 100 units.
const UNITS_PER_SIZE := 100.0
const SIZE_MIN := 0.05
const SIZE_MAX := 20.0
## Phoenix GEO space is glTF space: +X left, +Y up, +Z forward.
const NOSE_AXIS := "+z"
const UP_AXIS := "+y"

const NOT_PHOENIX := "\"%s\" is not a Phoenix RC model definition."
const NO_MODEL := "The Phoenix file \"%s\" defines no aircraft model."
const SEVERAL_MODELS := "The Phoenix file \"%s\" defines several models; choose a single model's .mod file."
const NO_SIZE := "The Phoenix model \"%s\" has no usable size, so its real dimensions are unknown."
const NO_GEOMETRY := "The geometry file \"%s\" was not found next to the Phoenix model."
const TEXTURE_SKIPPED := "The texture \"%s\" could not be used; those parts keep their plain colour."
const APPEARANCE_ONLY := "Only the Phoenix appearance is imported. Define and validate its OpenRC flight configuration separately."
const SUMMARY := "Phoenix model %s: %s m wingspan, %s kg. These Phoenix values are shown for reference only."
const PLACED := "Orientation, metres and the wing leading edge were set from the Phoenix model; check them in Orient and size."


## `value` is `{source, receipt, placement, summary}`; `diagnostics` carries non-fatal notes.
static func convert(mod_path: String, cancelled: Callable = Callable()) -> Dictionary:
	var label := mod_path.get_file()
	var mod_bytes := _read(mod_path, MAX_DEFINITION_BYTES)
	if not mod_bytes.ok:
		return mod_bytes
	var script := ScriptContainer.read(mod_bytes.value, cancelled)
	if not script.ok:
		if str(script.diagnostics[0].code) == R.SOURCE_UNSUPPORTED:
			return R.fail(R.SOURCE_UNSUPPORTED, NOT_PHOENIX, "source", STEP, [label])
		return script  # Malformed, over a limit or cancelled: keep the actual reason.
	var definition := _definition(script.value, label)
	if not definition.ok:
		return definition
	var model: Dictionary = definition.value.model
	var model_id: String = definition.value.id
	var size := _number(_dig(model, ["attributes", "Physical", "Size"]))
	if not is_finite(size) or size < SIZE_MIN or size > SIZE_MAX:
		return R.fail(R.SOURCE_INVALID, NO_SIZE, "source", STEP, [str(model.get("name", model_id))])
	if _cancelled(cancelled):
		return _cancel()
	var folder := mod_path.get_base_dir()
	var listing := _folder(folder)
	var geo_name := _resolve(listing, mod_path.get_file().get_basename() + ".geo")
	if geo_name.is_empty():
		return R.fail(R.DEPENDENCY_MISSING, NO_GEOMETRY, "source", STEP, [mod_path.get_file().get_basename() + ".geo"])
	var geo_bytes := _read(folder.path_join(geo_name), Limits.MODEL_SOURCE_BYTES)
	if not geo_bytes.ok:
		return geo_bytes
	var geo := Geo.parse(geo_bytes.value)
	if not geo.ok:
		return geo
	if _cancelled(cancelled):
		return _cancel()
	var notes: Array = []
	var textures := {}
	var texture_hashes := {}
	for material: Dictionary in geo.value.materials:
		var wanted: Variant = material.get("texture")
		if not wanted is String or str(wanted).is_empty() or textures.has(str(wanted).to_lower()):
			continue
		if textures.size() >= Limits.GLB_IMAGES:
			break  # The GLB admits at most this many images; further materials keep their colour.
		var found := _resolve(listing, str(wanted))
		if found.is_empty():
			continue  # Shared simulator textures (glass, white, rotor blur) are not in the model folder.
		var bytes := _read(folder.path_join(found), Limits.PNG_BYTES)
		var decoded := PhoenixTexture.decode(bytes.value) if bytes.ok else bytes
		if decoded.ok:
			textures[str(wanted).to_lower()] = decoded.value
			texture_hashes[found] = decoded.value.sha256
		else:
			notes.append(R.diagnostic(R.SOURCE_UNSUPPORTED, TEXTURE_SKIPPED, "source", STEP, [found], R.SEVERITY_WARNING))
		if _cancelled(cancelled):
			return _cancel()
	var scale := size / UNITS_PER_SIZE
	var receipt := {
		format = FORMAT, model_id = model_id, name = str(model.get("name", model_id)),
		definition = {file = label, sha256 = CreatorBytes.sha256(mod_bytes.value)},
		geometry = {file = geo_name, sha256 = geo.value.sha256},
		textures = texture_hashes, metres_per_unit = scale, size = size,
		coordinate_frame = "gltf: +X left, +Y up, +Z forward", physics_imported = false,
	}
	var glb := GlbWriter.build(geo.value, textures, scale, receipt)
	if not glb.ok:
		return glb
	notes.append_array(glb.diagnostics)
	if _cancelled(cancelled):
		return _cancel()
	# The label is the definition file name: the model name is untrusted text and may hold path characters.
	var admitted: Dictionary = Importer.inspect_bytes(glb.value.bytes, mod_path.get_file().get_basename() + ".glb")
	if not admitted.ok:
		return admitted
	notes.append_array(admitted.diagnostics)
	var summary := summarize(model, scale)
	var placement := _placement(summary)
	notes.append(R.diagnostic(R.UNSUPPORTED_CAPABILITY, APPEARANCE_ONLY, "source", STEP, [], R.SEVERITY_WARNING))
	var main_span := 0.0
	for wing: Dictionary in summary.wings:
		main_span = maxf(main_span, float(wing.span_m) if is_finite(float(wing.span_m)) else 0.0)
	notes.append(R.diagnostic(R.SOURCE_UNSUPPORTED, SUMMARY, "source", STEP,
		[summary.name, String.num(main_span, 2), String.num(float(summary.mass_kg), 2) if is_finite(float(summary.mass_kg)) else "?"],
		R.SEVERITY_INFO))
	if not placement.datum.is_empty():
		notes.append(R.diagnostic(R.SOURCE_UNSUPPORTED, PLACED, "source", STEP, [], R.SEVERITY_INFO))
	return R.ok({source = admitted.value, receipt = receipt, placement = placement, summary = summary}, notes)


## Read-only facts from the decoded definition, in metres, kilograms and degrees where established.
static func summarize(model: Dictionary, scale: float) -> Dictionary:
	var physical: Variant = _dig(model, ["attributes", "Physical"])
	var out := {
		name = str(model.get("name", "")), manufacturer = str(model.get("manufacturer", "")),
		type = str(model.get("type", "")), category = str(model.get("subclass", "")),
		mass_kg = _number(_dig(physical, ["Weight"])), size = _number(_dig(physical, ["Size"])),
		wings = [], propellers = [], turbines = 0, has_gear = model.get("gear") is Dictionary or model.get("gear") is Array,
	}
	var airfoils: Variant = model.get("airfoils")
	if airfoils is Array:
		for airfoil: Variant in airfoils:
			if not airfoil is Dictionary:
				continue
			var attributes: Variant = airfoil.get("attributes")
			var position: Variant = _dig(attributes, ["Position"])
			var length := _number(_dig(attributes, ["Length"]))
			var mirrored := _number(airfoil.get("isMirrored")) == 1.0
			out.wings.append({
				name = str(airfoil.get("name", "")), span_m = length * (2.0 if mirrored else 1.0),
				root_chord_m = _number(_dig(attributes, ["Root_chord"])), tip_chord_m = _number(_dig(attributes, ["Tip_chord"])),
				dihedral_deg = _number(_dig(attributes, ["Dihedral"])), sweep_deg = _number(_dig(attributes, ["Sweep"])),
				leading_edge = _point(position, scale), mirrored = mirrored,
				surfaces = (airfoil.get("controlSurfaces") as Array).size() if airfoil.get("controlSurfaces") is Array else 0,
			})
	var propulsion: Variant = model.get("propulsion")
	if propulsion is Array:
		for unit: Variant in propulsion:
			if not unit is Dictionary:
				continue
			if str(unit.get("type", "")) == "propeller":
				var attributes: Variant = unit.get("attributes")
				out.propellers.append({diameter_m = _number(_dig(attributes, ["Diameter"])),
					pitch_m = _number(_dig(attributes, ["Pitch"])), blades = _number(_dig(attributes, ["Blade_count"])),
					max_rpm = _number(_dig(attributes, ["Max_RPM"]))})
			elif str(unit.get("type", "")) == "turbine":
				out.turbines += 1
	return out


## The main wing is the widest mirrored airfoil; its root leading edge on the centreline is the datum.
static func _placement(summary: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	for wing: Dictionary in summary.wings:
		var edge: Variant = wing.leading_edge
		if wing.mirrored and edge is Array and is_finite(float(wing.span_m)) and (best.is_empty() or float(wing.span_m) > float(best.span_m)):
			best = wing
	var datum: Array = []
	if not best.is_empty():
		datum = [0.0, float(best.leading_edge[1]), float(best.leading_edge[2])]
	return {nose_axis = NOSE_AXIS, up_axis = UP_AXIS, units = "m", datum = datum}


static func _definition(script: Dictionary, label: String) -> Dictionary:
	var found: Array = []
	var assigned: Variant = script.get("assigned")
	if assigned is Dictionary:
		for key: Variant in assigned:
			if str(key).begins_with("modelTypes.") and assigned[key] is Dictionary:
				found.append(key)
	if found.is_empty():
		return R.fail(R.SOURCE_UNSUPPORTED, NO_MODEL, "source", STEP, [label])
	if found.size() > 1:
		return R.fail(R.SOURCE_UNSUPPORTED, SEVERAL_MODELS, "source", STEP, [label])
	return R.ok({id = str(found[0]).trim_prefix("modelTypes."), model = assigned[found[0]]})


static func _read(path: String, ceiling: int) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return R.fail(R.SOURCE_MISSING, "The file \"%s\" cannot be opened.", "source", STEP, [path.get_file()])
	var length: int = file.get_length()
	if length <= 0 or length > ceiling:
		return R.fail(R.SOURCE_LIMIT, "The file \"%s\" is empty or larger than the %s MiB limit.", "source", STEP,
			[path.get_file(), str(ceiling / Limits.MIB)])
	var bytes := file.get_buffer(length)
	if bytes.size() != length or file.get_error() != OK:
		return R.fail(R.SOURCE_INVALID, "The file \"%s\" could not be read completely.", "source", STEP, [path.get_file()])
	return R.ok(bytes)


## Files of the model folder (no recursion, bounded). Lower-case name -> actual names.
static func _folder(folder: String) -> Dictionary:
	var out := {}
	var dir := DirAccess.open(folder)
	if dir == null:
		return out
	var count := 0
	for name: String in dir.get_files():
		count += 1
		if count > MAX_FOLDER_ENTRIES:
			break
		var key := name.to_lower()
		if not out.has(key):
			out[key] = []
		out[key].append(name)
	return out


## An exact name, else a unique case-insensitive match inside the model folder; never a path.
static func _resolve(listing: Dictionary, wanted: String) -> String:
	if wanted.is_empty() or wanted.contains("/") or wanted.contains("\\") or wanted.contains(".."):
		return ""
	var matches: Variant = listing.get(wanted.to_lower())
	if not matches is Array or matches.is_empty():
		return ""
	if wanted in matches:
		return wanted
	return str(matches[0]) if matches.size() == 1 else ""


static func _dig(value: Variant, path: Array) -> Variant:
	var current: Variant = value
	for key: Variant in path:
		if not current is Dictionary or not current.has(key):
			return null
		current = current[key]
	return current


static func _number(value: Variant) -> float:
	if value is int or value is float:
		return float(value)
	return NAN


static func _point(value: Variant, scale: float) -> Variant:
	if not value is Dictionary:
		return null
	var p := [_number(value.get("x")) * scale, _number(value.get("y")) * scale, _number(value.get("z")) * scale]
	for component: float in p:
		if not is_finite(component):
			return null
	return p


static func _cancelled(cancelled: Callable) -> bool:
	return cancelled.is_valid() and bool(cancelled.call())


static func _cancel() -> Dictionary:
	return R.fail(R.SOURCE_INVALID, "The import was cancelled.", "source", STEP)
