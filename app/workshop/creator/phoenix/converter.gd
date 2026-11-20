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
const MOVING_PARTS := "%s moving parts were prepared from the Phoenix hinges; check them in Moving parts."
## Alpha textures up to this many pixels (stock glass is 32 x 32) are reduced to their average colour.
const UNIFORM_PIXELS := 64 * 64
const BINDINGS_FORMAT := "openrc-creator-bindings v1"
## Phoenix surface inputs -> Creator control roles (left/right decided by the airfoil side).
const _INPUT_ROLES := {"aileron": "aileron", "left aileron": "aileron", "right aileron": "aileron",
	"elevator": "elevator", "left elevator": "elevator", "right elevator": "elevator", "rudder": "rudder"}
const LAYOUT := "Wing, tail, propeller position and control throws were filled from the Phoenix model as estimates; confirm them before flying."
## Fuselage nose just aft of a tractor hub (the package allows the hub 0 to 0.12 m ahead of the nose).
const HUB_SETBACK_M := 0.03
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
	var shared := _shared_texture_folders(folder)
	var textures := {}
	var texture_hashes := {}
	for material: Dictionary in geo.value.materials:
		var wanted: Variant = material.get("texture")
		if not wanted is String or str(wanted).is_empty() or textures.has(str(wanted).to_lower()):
			continue
		if textures.size() >= Limits.GLB_IMAGES:
			break  # The GLB admits at most this many images; further materials keep their colour.
		# The model folder first, then the installation's shared aircraft textures (glass, rotor discs).
		var found := _resolve(listing, str(wanted))
		var found_dir := folder
		if found.is_empty():
			for shared_dir: String in shared:
				found = _resolve(shared[shared_dir], str(wanted))
				if not found.is_empty():
					found_dir = shared_dir
					break
		if found.is_empty():
			continue
		var bytes := _read(found_dir.path_join(found), Limits.PNG_BYTES)
		var decoded := PhoenixTexture.decode(bytes.value) if bytes.ok else bytes
		if decoded.ok:
			var image: Image = decoded.value.image
			# A small alpha texture is glass: use its average colour rather than a texture of uncertain registration.
			decoded.value.uniform = bool(decoded.value.has_alpha) and image.get_width() * image.get_height() <= UNIFORM_PIXELS
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
	var articulation := articulation_groups(model)
	var glb := GlbWriter.build(geo.value, textures, scale, receipt, articulation)
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
	var bindings := proposed_bindings(glb.value.pivots)
	if not bindings.is_empty():
		notes.append(R.diagnostic(R.SOURCE_UNSUPPORTED, MOVING_PARTS, "source", STEP, [str(glb.value.pivots.size())], R.SEVERITY_INFO))
	var values := definition_values(model, scale, placement.datum)
	if not values.is_empty():
		notes.append(R.diagnostic(R.SOURCE_UNSUPPORTED, LAYOUT, "source", STEP, [], R.SEVERITY_INFO))
	return R.ok({source = admitted.value, receipt = receipt, placement = placement, summary = summary,
		bindings = bindings, values = values}, notes)


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


## Rigid moving groups for the GLB writer, from decoded control surfaces and the first propeller.
## Phoenix gives the left side's hinge (positive X); a mirrored airfoil's right side is its mirror image.
## Positive Creator deflection turns about the left-span axis (ailerons, elevator), the up axis (rudder)
## or the forward axis (propeller), so the sign follows the hinge direction along that axis.
## Creator layout fields from the decoded airfoils and propeller, in the structural frame
## [aft, right, up] metres from `datum` (GLB metres, the main-wing root leading edge). These are source
## dimensions to be confirmed, applied as estimates; mass, inertia and aerodynamics stay OpenRC's own.
static func definition_values(model: Dictionary, scale: float, datum: Array) -> Dictionary:
	var values := {}
	if datum.size() != 3:
		return values
	var wing: Variant = null
	var tail: Variant = null
	var fin: Variant = null
	var travel := {}
	var airfoils: Variant = model.get("airfoils")
	if not airfoils is Array:
		return values
	for airfoil: Variant in airfoils:
		if not airfoil is Dictionary:
			continue
		var roles: Array = []
		for surface: Variant in (airfoil.get("controlSurfaces") if airfoil.get("controlSurfaces") is Array else []):
			if not surface is Dictionary:
				continue
			var role := str(_INPUT_ROLES.get(str(_dig(surface, ["attributes", "Input"])).to_lower(), ""))
			var throw := _number(_dig(surface, ["attributes", "Max_travel"]))
			if not role.is_empty():
				roles.append(role)
				if is_finite(throw) and throw > 0.0 and _number(_dig(surface, ["attributes", "Length"])) > 0.0:
					travel[role] = maxf(float(travel.get(role, 0.0)), throw)
		if "aileron" in roles and wing == null:
			wing = airfoil
		elif "elevator" in roles and tail == null:
			tail = airfoil
		elif "rudder" in roles and fin == null:
			fin = airfoil
	if wing == null:
		var widest := 0.0
		for airfoil: Variant in airfoils:
			if airfoil is Dictionary and _number(airfoil.get("isMirrored")) == 1.0:
				var length := _number(_dig(airfoil, ["attributes", "Length"]))
				if is_finite(length) and length > widest and airfoil != tail:
					widest = length
					wing = airfoil
	var structural := func(point: Variant) -> Array:
		var p: Variant = _point(point, scale)
		if p == null:
			return []
		return [-(float(p[2]) - float(datum[2])), -float(p[0]), float(p[1]) - float(datum[1])]
	if wing is Dictionary:
		var at: Variant = wing.get("attributes")
		var length := _number(_dig(at, ["Length"]))
		if is_finite(length) and length > 0.0:
			values["wing/span"] = 2.0 * length
		_copy(values, "wing/root_chord", _number(_dig(at, ["Root_chord"])))
		_copy(values, "wing/tip_chord", _number(_dig(at, ["Tip_chord"])))
		var dihedral := _number(_dig(at, ["Dihedral"]))
		if is_finite(dihedral) and dihedral >= 0.0:
			values["wing/dihedral_deg"] = dihedral
	if tail is Dictionary:
		var at: Variant = tail.get("attributes")
		var length := _number(_dig(at, ["Length"]))
		if is_finite(length) and length > 0.0:
			values["horizontal_tail/span"] = length * (2.0 if _number(tail.get("isMirrored")) == 1.0 else 1.0)
		_copy(values, "horizontal_tail/chord", (_number(_dig(at, ["Root_chord"])) + _number(_dig(at, ["Tip_chord"]))) / 2.0)
		var place: Array = structural.call(_dig(at, ["Position"]))
		if not place.is_empty():
			values["horizontal_tail/position/0"] = place[0]
			values["horizontal_tail/position/2"] = place[2]
	if fin is Dictionary:
		var at: Variant = fin.get("attributes")
		_copy(values, "vertical_tail/height", _number(_dig(at, ["Length"])))
		_copy(values, "vertical_tail/chord", (_number(_dig(at, ["Root_chord"])) + _number(_dig(at, ["Tip_chord"]))) / 2.0)
		var place: Array = structural.call(_dig(at, ["Position"]))
		if not place.is_empty():
			values["vertical_tail/position/0"] = place[0]
			values["vertical_tail/position/2"] = place[2]
	var propulsion: Variant = model.get("propulsion")
	if propulsion is Array:
		for unit: Variant in propulsion:
			if unit is Dictionary and str(unit.get("type", "")) == "propeller":
				var hub: Array = structural.call(unit.get("pivot"))
				if not hub.is_empty():
					for axis: int in 3:
						values["equipment/hub_position/%d" % axis] = hub[axis]
					# A tractor hub sits on the fuselage nose: the model box would otherwise put the nose at
					# the spinner tip, ahead of the hub, and centre the fuselage at a template height.
					if float(hub[0]) < 0.0:
						values["fuselage/nose_x"] = float(hub[0]) + HUB_SETBACK_M
						values["fuselage/center_z"] = hub[2]
				break
	for role: String in travel:
		values["controls/%s_deg" % role] = travel[role]
	return values


static func _copy(values: Dictionary, path: String, number: float) -> void:
	if is_finite(number) and number > 0.0:
		values[path] = number


static func articulation_groups(model: Dictionary) -> Array:
	var groups: Array = []
	var airfoils: Variant = model.get("airfoils")
	if airfoils is Array:
		for airfoil: Variant in airfoils:
			if not airfoil is Dictionary or not airfoil.get("controlSurfaces") is Array:
				continue
			var mirrored := _number(airfoil.get("isMirrored")) == 1.0
			for surface: Variant in airfoil.controlSurfaces:
				if not surface is Dictionary:
					continue
				var role := str(_INPUT_ROLES.get(str(_dig(surface, ["attributes", "Input"])).to_lower(), ""))
				var root: Variant = _point(surface.get("root_pivot"), 1.0)
				var tip: Variant = _point(surface.get("tip_pivot"), 1.0)
				var sides: Variant = surface.get("sides")
				if role.is_empty() or root == null or tip == null or not sides is Array:
					continue
				for side: int in (sides as Array).size():
					var names: Variant = sides[side]
					if not names is Array or (names as Array).is_empty():
						continue
					var a: Array = root
					var b: Array = tip
					if side == 1:
						if not mirrored:
							continue
						a = [-float(root[0]), root[1], root[2]]
						b = [-float(tip[0]), tip[1], tip[2]]
					var hinge := [float(b[0]) - float(a[0]), float(b[1]) - float(a[1]), float(b[2]) - float(a[2])]
					var along: float = hinge[1] if role == "rudder" else hinge[0]
					var named := role
					if role == "aileron":
						named = "aileron_left" if side == 0 else "aileron_right"
					groups.append({role = named, nodes = (names as Array).map(func(n: Variant) -> String: return str(n)),
						origin = a, hinge = hinge, axis = "x", sign = 1 if along >= 0.0 else -1})
	var propulsion: Variant = model.get("propulsion")
	if propulsion is Array:
		for unit: Variant in propulsion:
			if not unit is Dictionary or str(unit.get("type", "")) != "propeller":
				continue
			var pivot: Variant = _point(unit.get("pivot"), 1.0)
			var names: Array = []
			for key: String in ["spinGeometry", "blurGeometry"]:
				if unit.get(key) is Array:
					for name: Variant in unit[key]:
						if not str(name) in names:
							names.append(str(name))
			if pivot != null and not names.is_empty():
				groups.append({role = "propeller", nodes = names, origin = pivot, hinge = [], axis = "z",
					sign = -1 if _number(unit.get("spinDirection")) == -1.0 else 1})
			break  # Creator binds one propeller.
	return groups


## Creator bindings for the built pivots: up to two parts per control role, one propeller.
static func proposed_bindings(pivots: Array) -> Dictionary:
	var controls := {}
	var propeller: Variant = null
	for pivot: Dictionary in pivots:
		var entry := {node = int(pivot.node), axis = str(pivot.axis), sign = int(pivot.sign)}
		if pivot.role == "propeller":
			if propeller == null:
				propeller = entry
			continue
		if not controls.has(pivot.role):
			controls[pivot.role] = []
		if (controls[pivot.role] as Array).size() < 2:
			controls[pivot.role].append(entry)
	if controls.is_empty() and propeller == null:
		return {}
	var out := {format = BINDINGS_FORMAT, controls = controls}
	if propeller != null:
		out.propeller = propeller
	return out


## `resources/textures/aircraft` and `resources/textures/misc` of the installation holding `folder`.
static func _shared_texture_folders(folder: String) -> Dictionary:
	var out := {}
	var current := folder
	for _level: int in 8:
		if current.get_file().to_lower() == "resources":
			for sub: String in ["textures/aircraft", "textures/misc"]:
				var path := current.path_join(sub)
				if DirAccess.dir_exists_absolute(path):
					out[path] = _folder(path)
			break
		var parent := current.get_base_dir()
		if parent == current or parent.is_empty():
			break
		current = parent
	return out


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
