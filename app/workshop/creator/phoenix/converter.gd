extends RefCounted
## Converts one Phoenix RC model from the player's own local installation (AC-PX-R2).
##
## Input is the model's `.mod` definition; its sibling `.geo` and the in-folder textures named by the
## GEO materials are read from the same folder. Nothing is fetched elsewhere and stock content never
## leaves the player's machine. The result is an ordinary admitted GLB source (visual only), the
## placement the decoded definition implies, a read-only summary of the Phoenix flight data and the
## physics block (`physics.gd`) reduced from the definition and the installation's airfoil polars.
## Phoenix tuning gains and inertia factors stay observations, never OpenRC physics.

const R := preload("res://workshop/creator/result.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const CreatorBytes := preload("res://workshop/creator/bytes.gd")
const Importer := preload("res://workshop/creator/source_importer.gd")
const ScriptContainer := preload("res://workshop/creator/phoenix/script_container.gd")
const Geo := preload("res://workshop/creator/phoenix/geo.gd")
const PhoenixTexture := preload("res://workshop/creator/phoenix/texture.gd")
const GlbWriter := preload("res://workshop/creator/phoenix/glb_writer.gd")
const Installation := preload("res://workshop/creator/source_installation.gd")
const PhoenixPhysics := preload("res://workshop/creator/phoenix/physics.gd")
const PhoenixSetup := preload("res://workshop/creator/phoenix/setup.gd")
const InspectedSource := preload("res://workshop/creator/inspected_source.gd")

const FORMAT := "openrc-phoenix-visual-v1"
const AEROPLANE_TYPES := ["Airplane", "Glider"]
const ROTORCRAFT_TYPES := ["Helicopter", "Multi-rotor"]
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
const ROTORCRAFT := "Phoenix helicopters and multirotors are imported for their appearance only: OpenRC cannot fly them from their Phoenix data yet."
const GEAR_EXTENDED := "The Phoenix landing gear is used for runway starts. Retractable gear stays extended."
const TEXTURES_LIMITED := "This model uses more than %s textures; %s of them were not imported, so those parts keep their plain colour."
const SUMMARY := "Phoenix model %s: %s m wingspan, %s kg."
const MOVING_PARTS := "%s moving parts were prepared from the Phoenix hinges; check them in Moving parts."
## Glass textures up to this many pixels (stock glass is 32 x 32) are reduced to their average colour.
const UNIFORM_PIXELS := 64 * 64
## Stacked wings: a second mirrored airfoil this large and this close fore-and-aft (both relative to the main
## wing span) is another lifting wing, not a tailplane.
const BIPLANE_MIN_SHARE := 0.6
const BIPLANE_STAGGER_SHARE := 0.25
const BINDINGS_FORMAT := "openrc-creator-bindings v1"
## Phoenix surface inputs -> Creator control roles (left/right decided by the airfoil side).
const _INPUT_ROLES := {"aileron": "aileron", "left aileron": "aileron", "right aileron": "aileron",
	"elevator": "elevator", "left elevator": "elevator", "right elevator": "elevator", "rudder": "rudder"}
const LAYOUT := "Use Set up for flight to apply the Phoenix weight, balance, airfoils, wing, tail and propeller; anything else becomes a labelled estimate."
## Fuselage nose just aft of a tractor hub (the package allows the hub 0 to 0.12 m ahead of the nose).
const HUB_SETBACK_M := 0.03
const NO_PHYSICS := "The Phoenix airfoil library was not found next to this model, so its own lift and drag data cannot be used; the estimated OpenRC values apply."
const MAX_AIRFOIL_FILES := 64
const MAX_AIRFOIL_BYTES := 2 * Limits.MIB
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
	var over_limit := {}
	for material: Dictionary in geo.value.materials:
		var wanted: Variant = material.get("texture")
		if not wanted is String or str(wanted).is_empty() or textures.has(str(wanted).to_lower()):
			continue
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
		if textures.size() >= Limits.GLB_IMAGES:
			# The GLB admits at most this many images; further materials keep their colour.
			over_limit[str(wanted).to_lower()] = true
			continue
		var bytes := _read(found_dir.path_join(found), Limits.PNG_BYTES)
		var decoded := PhoenixTexture.decode(bytes.value) if bytes.ok else bytes
		if decoded.ok:
			var image: Image = decoded.value.image
			# A small texture with graded or cut-out alpha is glass or a blur disc, and so is a small glass
			# texture whose alpha is all clear: its average colour gives a consistent, visible canopy tint.
			var alpha := str(decoded.value.alpha)
			decoded.value.uniform = image.get_width() * image.get_height() <= UNIFORM_PIXELS and (bool(decoded.value.has_alpha)
				or (alpha == PhoenixTexture.ALPHA_ZERO and found.to_lower().contains("glass")))
			textures[str(wanted).to_lower()] = decoded.value
			texture_hashes[found] = decoded.value.sha256
		else:
			notes.append(R.diagnostic(R.SOURCE_UNSUPPORTED, TEXTURE_SKIPPED, "source", STEP, [found], R.SEVERITY_WARNING))
		if _cancelled(cancelled):
			return _cancel()
	if not over_limit.is_empty():
		notes.append(R.diagnostic(R.SOURCE_LIMIT, TEXTURES_LIMITED, "source", STEP,
			[str(Limits.GLB_IMAGES), str(over_limit.size())], R.SEVERITY_WARNING))
	var scale := size / UNITS_PER_SIZE
	var summary := summarize(model, scale)
	var placement := _placement(summary)
	var lifting := lifting_wings(summary)
	var values := definition_values(model, scale, placement.datum, lifting)
	var aeroplane := str(model.get("type", "")) in AEROPLANE_TYPES
	var receipt := {
		format = FORMAT, model_id = model_id, name = str(model.get("name", model_id)),
		definition = {file = label, sha256 = CreatorBytes.sha256(mod_bytes.value)},
		geometry = {file = geo_name, sha256 = geo.value.sha256},
		textures = texture_hashes, texture_profile = PhoenixTexture.PROFILE, metres_per_unit = scale, size = size,
		coordinate_frame = "gltf: +X left, +Y up, +Z forward", physics_imported = false,
		model_type = str(model.get("type", "")),
	}
	var main_span := 0.0
	for wing: Dictionary in summary.wings:
		main_span = maxf(main_span, float(wing.span_m) if is_finite(float(wing.span_m)) else 0.0)
	if main_span > 0.0:
		receipt.span_m = main_span
	if is_finite(float(summary.mass_kg)):
		receipt.mass_kg = float(summary.mass_kg)
	var setup := creator_setup(summary, placement, values)
	if not setup.is_empty():
		setup.biplane = lifting.size() >= 2
		# The model's own physics: its airfoil polars from the installation's library, mass, balance,
		# control-surface geometry and propeller (phoenix/physics.gd).
		var picked := layout_surfaces(model, lifting)
		var polars := _airfoil_polars(folder, model, cancelled)
		var physics := PhoenixPhysics.physics_block(model, scale, placement.datum, polars,
			picked.wing if picked.wing is Dictionary else {}, picked.tail, picked.fin)
		var wheels := gear_layout(model, scale, placement.datum)
		if not wheels.is_empty():
			setup.gear = wheels
			if bool(wheels.retractable):
				notes.append(R.diagnostic(R.SOURCE_UNSUPPORTED, GEAR_EXTENDED, "source", STEP, [], R.SEVERITY_INFO))
		if not physics.is_empty():
			setup.physics = physics
		else:
			notes.append(R.diagnostic(R.SOURCE_UNSUPPORTED, NO_PHYSICS, "source", STEP, [], R.SEVERITY_WARNING))
	if aeroplane and not setup.is_empty():
		receipt.creator_setup = setup
	var articulation := articulation_groups(model)
	# Only aeroplanes and gliders with a usable decoded layout join the declared-configuration route.
	var markers: Array = [Installation.PHOENIX_NAMESPACE] if aeroplane and not setup.is_empty() else []
	var glb := GlbWriter.build(geo.value, textures, scale, receipt, articulation, markers)
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
	notes.append_array(_route_notes(receipt, markers))
	notes.append(R.diagnostic(R.SOURCE_UNSUPPORTED, SUMMARY, "source", STEP,
		[summary.name, String.num(main_span, 2), String.num(float(summary.mass_kg), 2) if is_finite(float(summary.mass_kg)) else "?"],
		R.SEVERITY_INFO))
	if not placement.datum.is_empty():
		notes.append(R.diagnostic(R.SOURCE_UNSUPPORTED, PLACED, "source", STEP, [], R.SEVERITY_INFO))
	var bindings := proposed_bindings(glb.value.pivots)
	if not bindings.is_empty():
		notes.append(R.diagnostic(R.SOURCE_UNSUPPORTED, MOVING_PARTS, "source", STEP, [str(glb.value.pivots.size())], R.SEVERITY_INFO))
	return R.ok({source = admitted.value, receipt = receipt, placement = placement, summary = summary,
		bindings = bindings, values = values}, notes)


## What the player can do with the model: set up for flight (aeroplanes with a decoded layout), appearance
## only (rotorcraft, or an aeroplane without a usable layout), and whether its own physics is available.
static func _route_notes(receipt: Dictionary, markers: Array) -> Array:
	var notes: Array = []
	if str(receipt.get("model_type", "")) in ROTORCRAFT_TYPES:
		notes.append(R.diagnostic(R.UNSUPPORTED_CAPABILITY, ROTORCRAFT, "source", STEP, [], R.SEVERITY_WARNING))
	elif markers.is_empty():
		notes.append(R.diagnostic(R.UNSUPPORTED_CAPABILITY, APPEARANCE_ONLY, "source", STEP, [], R.SEVERITY_WARNING))
	else:
		notes.append(R.diagnostic(R.SOURCE_UNSUPPORTED, LAYOUT, "source", STEP, [], R.SEVERITY_INFO))
	return notes


## The import notes of a reopened Phoenix source, rebuilt from its receipt (the installation is not needed);
## [] for any other source.
static func source_notes(source: InspectedSource) -> Array:
	var receipt := PhoenixSetup.receipt(source)
	if receipt.get("format") != FORMAT:
		return []
	var markers: Array = [Installation.PHOENIX_NAMESPACE] if Installation.provider(source) == "phoenix" else []
	var notes := _route_notes(receipt, markers)
	var span: Variant = receipt.get("span_m")
	var mass: Variant = receipt.get("mass_kg")
	if (span is float or span is int) and (mass is float or mass is int):
		notes.append(R.diagnostic(R.SOURCE_UNSUPPORTED, SUMMARY, "source", STEP,
			[str(receipt.get("name", "")).substr(0, Limits.NAME_CHARACTERS), String.num(float(span), 2), String.num(float(mass), 2)],
			R.SEVERITY_INFO))
	if not markers.is_empty() and bool(PhoenixSetup.creator_setup(source).get("gear", {}).get("retractable", false)):
		notes.append(R.diagnostic(R.SOURCE_UNSUPPORTED, GEAR_EXTENDED, "source", STEP, [], R.SEVERITY_INFO))
	if not markers.is_empty() and PhoenixSetup.creator_setup(source).get("physics", {}).is_empty():
		notes.append(R.diagnostic(R.SOURCE_UNSUPPORTED, NO_PHYSICS, "source", STEP, [], R.SEVERITY_WARNING))
	return notes


## The decoded layout for `phoenix/setup.gd`: main-wing half span, chords and dihedral, the datum (GLB
## metres), the source layout without the wing (the setup fits the planform), and the propeller layout.
## {} when the main wing or datum is unusable.
static func creator_setup(summary: Dictionary, placement: Dictionary, values: Dictionary) -> Dictionary:
	var datum: Array = placement.get("datum", [])
	if datum.size() != 3 or not values.has("wing/span") or not values.has("wing/root_chord") or not values.has("wing/tip_chord"):
		return {}
	var layout := {}
	for path: String in values:
		if not path.begins_with("wing/"):
			layout[path] = values[path]
	var propellers: Array = summary.get("propellers", [])
	var hub_aft := float(values.get("equipment/hub_position/0", -1.0))
	return {datum = datum.duplicate(), half_span_m = 0.5 * float(values["wing/span"]),
		root_chord_m = values["wing/root_chord"], tip_chord_m = values["wing/tip_chord"],
		dihedral_deg = float(values.get("wing/dihedral_deg", 0.0)), propeller_found = not propellers.is_empty(),
		pusher = not propellers.is_empty() and hub_aft > 0.0, layout = layout}


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
				surfaces_roles = _surface_roles(airfoil),
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
	var wings := lifting_wings(summary)
	var datum: Array = []
	if not wings.is_empty():
		# One wing: its root leading edge. Stacked wings (biplane, triplane): the mean of their leading edges,
		# where the equivalent single wing of the estimated configuration sits.
		var y := 0.0
		var z := 0.0
		for wing: Dictionary in wings:
			y += float(wing.leading_edge[1])
			z += float(wing.leading_edge[2])
		datum = [0.0, y / wings.size(), z / wings.size()]
	return {nose_axis = NOSE_AXIS, up_axis = UP_AXIS, units = "m", datum = datum}


## The main wing (widest mirrored airfoil with a leading edge) first, then any stacked wings of a
## biplane or triplane: mirrored, at least BIPLANE_MIN_SHARE of its span and close to it fore and aft.
static func lifting_wings(summary: Dictionary) -> Array:
	var main: Dictionary = {}
	for wing: Dictionary in summary.get("wings", []):
		if wing.mirrored and wing.leading_edge is Array and is_finite(float(wing.span_m)) \
				and (main.is_empty() or float(wing.span_m) > float(main.span_m)):
			main = wing
	if main.is_empty():
		return []
	var out: Array = [main]
	for wing: Dictionary in summary.get("wings", []):
		if wing == main or not wing.mirrored or not wing.leading_edge is Array or not is_finite(float(wing.span_m)):
			continue
		if float(wing.span_m) >= BIPLANE_MIN_SHARE * float(main.span_m) \
				and absf(float(wing.leading_edge[2]) - float(main.leading_edge[2])) <= BIPLANE_STAGGER_SHARE * float(main.span_m) \
				and wing.surfaces_roles.find("elevator") < 0:
			out.append(wing)
	return out


## Rigid moving groups for the GLB writer, from decoded control surfaces and the first propeller.
## Phoenix gives the left side's hinge (positive X); a mirrored airfoil's right side is its mirror image.
## Positive Creator deflection turns about the left-span axis (ailerons, elevator), the up axis (rudder)
## or the forward axis (propeller), so the sign follows the hinge direction along that axis.
## Creator layout fields from the decoded airfoils and propeller, in the structural frame
## [aft, right, up] metres from `datum` (GLB metres, the main-wing root leading edge). These are source
## dimensions to be confirmed, applied as estimates; mass, inertia and aerodynamics stay OpenRC's own.
## The airfoils that play the main wing, the tailplane and the fin, and the active control throws.
## Roles come from the surfaces' inputs; stacked wings use the widest wing as the reference.
static func layout_surfaces(model: Dictionary, lifting: Array = []) -> Dictionary:
	var wing: Variant = null
	var tail: Variant = null
	var fin: Variant = null
	var travel := {}
	var airfoils: Variant = model.get("airfoils")
	if not airfoils is Array:
		return {wing = null, tail = null, fin = null, travel = travel}
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
	# Stacked wings: the reference wing is the widest one, as for the datum and the half span.
	if lifting.size() >= 2:
		wing = null
	if wing == null:
		var widest := 0.0
		for airfoil: Variant in airfoils:
			if airfoil is Dictionary and _number(airfoil.get("isMirrored")) == 1.0:
				var length := _number(_dig(airfoil, ["attributes", "Length"]))
				if is_finite(length) and length > widest and airfoil != tail:
					widest = length
					wing = airfoil
	return {wing = wing, tail = tail, fin = fin, travel = travel}


## The decoded landing gear as Creator wheels (AC-21): wheel bottoms (centre minus radius) in the
## leading-edge frame in metres at the source size, mirrored sides expanded, the steered (`isGuide`) wheel
## with its `Guide_travel`. A steered wheel ahead of the others makes a tricycle, behind them a taildragger.
## Retractable gear flies extended. {} without three or four wheels (floats, skids, missing data).
static func gear_layout(model: Dictionary, scale: float, datum: Array) -> Dictionary:
	if datum.size() != 3 or not model.get("gear") is Array:
		return {}
	var wheels: Array = []
	var retractable := false
	for gear: Variant in model.gear:
		if not gear is Dictionary:
			continue
		retractable = retractable or _number(gear.get("isRetractable")) == 1.0
		var guide := _number(gear.get("isGuide")) == 1.0
		var travel := _number(_dig(gear, ["attributes", "Guide_travel"]))
		for wheel: Variant in (gear.get("wheels") if gear.get("wheels") is Array else []):
			if not wheel is Dictionary:
				continue
			var radius := _number(wheel.get("radius"))
			var centre: Variant = wheel.get("pivot")
			if not (is_finite(radius) and radius > 0.0) or not centre is Dictionary:
				continue
			var sides: Array = [1.0, -1.0] if _number(gear.get("mirrored")) == 1.0 and absf(_number(centre.get("x"))) > 1e-6 else [1.0]
			for side: float in sides:
				var bottom := {x = side * _number(centre.get("x")), y = _number(centre.get("y")) - radius, z = _number(centre.get("z"))}
				var p: Variant = _point(bottom, scale)
				if p == null:
					continue
				wheels.append({position = [-(float(p[2]) - float(datum[2])), -float(p[0]), float(p[1]) - float(datum[1])],
					guide = guide, travel = travel if is_finite(travel) else 0.0})
	if wheels.size() < 3 or wheels.size() > 4:
		return {}
	var steered: Array = wheels.filter(func(w: Dictionary) -> bool: return w.guide)
	var centre_line: Array = wheels.filter(func(w: Dictionary) -> bool: return absf(float(w.position[1])) < 1e-3)
	var lead: Array = steered if steered.size() == 1 else centre_line
	if lead.size() != 1:
		return {}
	var others: Array = wheels.filter(func(w: Dictionary) -> bool: return w != lead[0])
	var others_x := 0.0
	for w: Dictionary in others:
		others_x += float(w.position[0]) / others.size()
	var tricycle := float(lead[0].position[0]) < others_x
	var contacts: Array = []
	var extra := 0
	for w: Dictionary in wheels:
		var id := ""
		if w == lead[0]:
			id = "nose" if tricycle else "tail"
		elif others.size() == 2:
			id = "main_right" if float(w.position[1]) > 0.0 else "main_left"
		else:
			extra += 1
			id = "wheel_%d" % extra
		var steering := clampf(float(w.travel), 0.0, 45.0) * (1.0 if tricycle else -1.0) if w.guide else 0.0
		contacts.append({id = id, position = w.position, steering_deg = steering})
	return {layout = "tricycle" if tricycle else "taildragger", contacts = contacts, retractable = retractable}


static func definition_values(model: Dictionary, scale: float, datum: Array, lifting: Array = []) -> Dictionary:
	var values := {}
	if datum.size() != 3 or not model.get("airfoils") is Array:
		return values
	var picked := layout_surfaces(model, lifting)
	var wing: Variant = picked.wing
	var tail: Variant = picked.tail
	var fin: Variant = picked.fin
	var travel: Dictionary = picked.travel
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
	# Stacked wings fly as one equivalent wing: the main wing's span and taper with the total lifting area.
	if lifting.size() >= 2 and values.has("wing/span") and values.has("wing/root_chord") and values.has("wing/tip_chord"):
		var area := 0.0
		var dihedral_sum := 0.0
		for entry: Dictionary in lifting:
			area += float(entry.span_m) * 0.5 * (float(entry.root_chord_m) + float(entry.tip_chord_m))
			dihedral_sum += float(entry.dihedral_deg) if is_finite(float(entry.dihedral_deg)) else 0.0
		var span := float(values["wing/span"])
		var taper := float(values["wing/tip_chord"]) / float(values["wing/root_chord"])
		if area > 0.0 and span > 0.0 and is_finite(taper) and taper > 0.0:
			values["wing/root_chord"] = 2.0 * (area / span) / (1.0 + taper)
			values["wing/tip_chord"] = taper * float(values["wing/root_chord"])
			values["wing/dihedral_deg"] = maxf(0.0, dihedral_sum / lifting.size())
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
	# A ducted fan or turbine (IAQ T4) pushes at its declared Position; a propeller, when present, wins below.
	if propulsion is Array and not propulsion.any(func(u: Variant) -> bool: return u is Dictionary and str(u.get("type", "")) == "propeller"):
		for unit: Variant in propulsion:
			if unit is Dictionary and str(unit.get("type", "")) == "turbine":
				var thrust_point: Array = structural.call(_dig(unit.get("attributes"), ["Position"]))
				if not thrust_point.is_empty():
					values["equipment/hub_position/0"] = thrust_point[0]
					values["equipment/hub_position/1"] = 0.0
					values["equipment/hub_position/2"] = thrust_point[2]
				break
	if propulsion is Array:
		for unit: Variant in propulsion:
			if unit is Dictionary and str(unit.get("type", "")) == "propeller":
				var hub: Array = structural.call(unit.get("pivot"))
				if not hub.is_empty():
					# Creator flies one centreline propeller: an off-centre (twin or offset) hub is centred.
					hub[1] = 0.0
					for axis: int in 3:
						values["equipment/hub_position/%d" % axis] = hub[axis]
					# A tractor hub sits on the fuselage nose: the model box would otherwise put the nose at
					# the spinner tip, ahead of the hub, and centre the fuselage at a template height.
					if float(hub[0]) < 0.0:
						values["fuselage/nose_x"] = float(hub[0]) + HUB_SETBACK_M
						values["fuselage/center_z"] = hub[2]
				# Phoenix thrust-line offsets (degrees; down positive, as in Creator).
				for angle: Array in [["Down_thrust", 0], ["Right_thrust", 1]]:
					var degrees := _number(_dig(unit.get("attributes"), [angle[0]]))
					if is_finite(degrees) and degrees != 0.0:
						values["equipment/thrust_angles_deg/%d" % angle[1]] = degrees
				break
	for role: String in travel:
		values["controls/%s_deg" % role] = travel[role]
	return values


static func _surface_roles(airfoil: Dictionary) -> Array:
	var roles: Array = []
	if airfoil.get("controlSurfaces") is Array:
		for surface: Variant in airfoil.controlSurfaces:
			if surface is Dictionary:
				var role := str(_INPUT_ROLES.get(str(_dig(surface, ["attributes", "Input"])).to_lower(), ""))
				if not role.is_empty():
					roles.append(role)
	return roles


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


## Polars of the airfoils `model` names, from `resources/airfoils/*.sim` of the installation holding
## `folder`: name -> flat [alpha deg, CL, CD] coefficients. Bounded; unreadable files are skipped.
static func _airfoil_polars(folder: String, model: Dictionary, cancelled: Callable = Callable()) -> Dictionary:
	var wanted := {}
	for airfoil: Variant in (model.get("airfoils") if model.get("airfoils") is Array else []):
		if airfoil is Dictionary:
			var name := str(_dig(airfoil, ["attributes", "Airfoil"]))
			if not name.is_empty():
				wanted[name] = true
	var out := {}
	var resources := _resources_folder(folder)
	var library := _sub_folder(resources, ["airfoils"]) if not resources.is_empty() else ""
	if wanted.is_empty() or library.is_empty():
		return out
	var files: PackedStringArray = DirAccess.get_files_at(library)
	files.sort() # the same polars on every platform, whatever the directory order
	var read := 0
	for file: String in files:
		if out.size() == wanted.size() or read >= MAX_AIRFOIL_FILES or _cancelled(cancelled):
			break
		if file.get_extension().to_lower() != "sim":
			continue
		read += 1
		var bytes := _read(library.path_join(file), MAX_AIRFOIL_BYTES)
		if not bytes.ok:
			continue
		var script := ScriptContainer.read(bytes.value)
		if not script.ok or not script.value.get("assigned") is Dictionary:
			continue
		for key: Variant in script.value.assigned:
			var entry: Variant = script.value.assigned[key]
			if entry is Dictionary and wanted.has(str(entry.get("name", ""))) and entry.get("coefficients") is Array:
				out[str(entry.name)] = entry.coefficients
	return out


static func _resources_folder(folder: String) -> String:
	var current := folder
	for _level: int in 8:
		if current.get_file().to_lower() == "resources":
			return current
		var parent := current.get_base_dir()
		if parent == current or parent.is_empty():
			break
		current = parent
	return ""


## `base/<parts…>` with each folder name matched case-insensitively (a copied installation on a
## case-sensitive file system may change case); "" when missing or ambiguous.
static func _sub_folder(base: String, parts: Array) -> String:
	var current := base
	for part: Variant in parts:
		if not DirAccess.dir_exists_absolute(current):
			return ""
		var found_name := ""
		for name: String in DirAccess.get_directories_at(current):
			if name.to_lower() == str(part).to_lower():
				if not found_name.is_empty():
					return "" # case-distinct duplicates: refuse rather than guess
				found_name = name
		if found_name.is_empty():
			return ""
		current = current.path_join(found_name)
	return current


## `resources/textures/aircraft` and `resources/textures/misc` of the installation holding `folder`.
static func _shared_texture_folders(folder: String) -> Dictionary:
	var out := {}
	var current := folder
	for _level: int in 8:
		if current.get_file().to_lower() == "resources":
			for sub: Array in [["textures", "aircraft"], ["textures", "misc"]]:
				var path := _sub_folder(current, sub)
				if not path.is_empty():
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
