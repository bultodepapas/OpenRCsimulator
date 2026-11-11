extends RefCounted
## Runtime compiler of the Aircraft Creator (AC-06): a complete authoring definition becomes one closed
## `openrc-aircraft v2` record and a trusted AcceptedCandidate that the existing FlightSession can fly.
##
## First slice only: conventional wing and aft tail, single tractor electric motor, finite battery, no
## landing gear, estimated aerodynamics (packages.gd). The compiler adds no vehicle branch and no physics:
## it writes data for the shared fixed-wing law, serializes it once and reads those exact bytes back
## through the flight loader. Invalid input is refused, never clamped. Positions are metres in the
## leading-edge frame [x_aft, y_right, z_up]; all physical math is 64-bit float.

const R := preload("res://workshop/creator/result.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const Definition := preload("res://workshop/creator/definition.gd")
const Packages := preload("res://workshop/creator/packages.gd")
const CreatorBytes := preload("res://workshop/creator/bytes.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const RecordLoader := preload("res://workshop/creator/record_loader.gd")
const AcceptedCandidate := preload("res://workshop/creator/accepted_candidate.gd")

const PROPULSION_ID := "propulsion_main"
const SURFACE_IDS := {
	"aileron_left": "surface_aileron_left", "aileron_right": "surface_aileron_right",
	"elevator": "surface_elevator", "rudder": "surface_rudder",
}
const BALANCE_CONFIGURATION := "creator-inventory-v1"
## plan_cg is emitted as the inventory's own centre of mass; the tolerance only covers rounding.
const CG_TOLERANCE_M := 0.000001
const KIND_SOURCES := {
	"measured": "Aircraft Creator definition: player-measured value",
	"manual": "Aircraft Creator definition: player-entered value",
	"estimated": "Aircraft Creator definition: estimate (the player's, or the airframe package's mass proposal)",
}
## Player fields that place the power package's hardware: mount -> definition path.
const MOUNT_FIELDS := {"hub": "equipment/hub_position", "esc": "equipment/esc_position", "battery": "equipment/battery_position"}
## Package domain bounds: key in the airframe package's `domain` → [field, step, message].
const DOMAIN_FIELDS := {
	"wing_span_m": ["wing/span", "aircraft_layout", "The wing span is %s m; this package supports %s to %s m."],
	"aspect_ratio": ["wing/span", "aircraft_layout", "The wing aspect ratio is %s; this package supports %s to %s."],
	"taper_ratio": ["wing/tip_chord", "aircraft_layout", "The tip-to-root chord ratio is %s; this package supports %s to %s."],
	"wing_dihedral_deg": ["wing/dihedral_deg", "aircraft_layout", "The wing dihedral is %s degrees; this package supports %s to %s degrees."],
	"mass_kg": ["inventory", "weight_balance", "The flying mass is %s kg; this package supports %s to %s kg."],
	"wing_loading_kg_m2": ["inventory", "weight_balance", "The wing loading is %s kg/m²; this package supports %s to %s kg/m²."],
	"tail_aspect_ratio": ["horizontal_tail/span", "aircraft_layout", "The horizontal tail aspect ratio is %s; this package supports %s to %s."],
	"fin_aspect_ratio": ["vertical_tail/height", "aircraft_layout", "The vertical tail height-to-chord ratio is %s; this package supports %s to %s."],
	"tail_volume_h": ["horizontal_tail/position", "aircraft_layout", "The horizontal tail volume is %s; this package supports %s to %s."],
	"tail_volume_v": ["vertical_tail/position", "aircraft_layout", "The vertical tail volume is %s; this package supports %s to %s."],
	"static_margin": ["equipment/battery_position", "weight_balance", "The static margin is %s of the mean chord; this package supports %s to %s."],
	"thrust_to_weight": ["inventory", "weight_balance", "The static thrust is %s times the weight; this package supports %s to %s."],
	"hub_ahead_of_nose_m": ["equipment/hub_position", "power_mount", "The propeller hub is %s m ahead of the fuselage nose; this package supports %s to %s m."],
	"aileron_travel_deg": ["controls/aileron_deg", "controls_ground", "The aileron travel is %s degrees; this package supports %s to %s degrees."],
	"elevator_travel_deg": ["controls/elevator_deg", "controls_ground", "The elevator travel is %s degrees; this package supports %s to %s degrees."],
	"rudder_travel_deg": ["controls/rudder_deg", "controls_ground", "The rudder travel is %s degrees; this package supports %s to %s degrees."],
	"servo_time_s": ["controls/servo_time_s", "controls_ground", "The neutral-to-full command time is %s s; this package supports %s to %s s."],
	"down_thrust_deg": ["equipment/thrust_angles_deg", "power_mount", "The down thrust is %s degrees; this package supports %s to %s degrees."],
	"right_thrust_deg": ["equipment/thrust_angles_deg", "power_mount", "The right thrust is %s degrees; this package supports %s to %s degrees."],
	"initial_charge": ["battery/initial_soc", "power_mount", "The starting charge is %s; this package supports %s to %s."],
}


## Result envelope; value = AcceptedCandidate. Order: validate, resolve packages, assemble the inventory
## once, derive, emit, encode once, load those bytes, check identity, admit to the package domain.
static func compile_candidate(definition: Dictionary) -> Dictionary:
	var checked: Dictionary = Definition.validate_complete(definition)
	if not checked.ok:
		return R.fail_all(checked.diagnostics)
	var normal: Dictionary = checked.value
	var encoded_definition: Dictionary = CreatorBytes.encode(normal)
	if not encoded_definition.ok:
		return R.fail_all(encoded_definition.diagnostics)
	var study := _study(normal)
	var domain := _domain(study, normal)
	if not study.get("complete", false):
		# A valid definition whose geometry no record can describe (a tail ahead of the wing).
		if domain.is_empty():
			domain.append(R.diagnostic(R.BUILD_INVALID, "The aircraft cannot be described by this package.", "", Definition.STEP_REVIEW))
		return R.fail_all(domain)
	var aircraft := Definition.aircraft_id(str(normal["aircraft_uuid"]))
	var written: Dictionary = CreatorBytes.encode(_record(normal, study, aircraft))
	if not written.ok:
		return R.fail_all(written.diagnostics)
	var bytes: PackedByteArray = written.value.bytes
	var loaded: Dictionary = RecordLoader.load_bytes(bytes, aircraft)
	if not loaded.get("ok", false):
		var refused := _loader_diagnostics(loaded.get("errors", PackedStringArray()), (normal["inventory"] as Array).size())
		refused.append_array(domain)
		return R.fail_all(refused)
	if loaded.model.get("id") != aircraft:
		return R.fail(R.IDENTITY_MISMATCH, "The loaded record does not carry the aircraft identity.", "aircraft_uuid", Definition.STEP_REVIEW)
	if not domain.is_empty():
		return R.fail_all(domain)
	var read_out: Dictionary = (study.summary as Dictionary).duplicate(true)
	read_out["issues"] = []
	# Mass properties as the loader derived them from the emitted bytes: those values fly.
	read_out["mass_kg"] = float(loaded.model.mass_kg)
	read_out["cg_m"] = Array(loaded.model.cg_le as PackedFloat64Array)
	read_out["inertia_kg_m2"] = Array(loaded.model.inertia as PackedFloat64Array)
	read_out["qualification"] = Packages.QUALIFICATION
	read_out["loader_warnings"] = Array(loaded.get("warnings", PackedStringArray()))
	read_out["identities"] = {
		"aircraft_id": aircraft,
		"raw_sha256": str(written.value.sha256),
		"definition_sha256": str(encoded_definition.value.sha256),
		"model_data_sha256": str(loaded.model.get("data_sha256", "")),
		"airframe_package": str(normal["airframe_package"]),
		"power_package": str(normal["power_package"]),
	}
	var candidate := AcceptedCandidate.new()
	if not candidate._seal(aircraft, bytes, str(encoded_definition.value.sha256), loaded, read_out):
		return R.fail(R.BUILD_INVALID, "The compiled aircraft could not be sealed.", "", Definition.STEP_REVIEW)
	# Loader data-quality notes travel with the accepted candidate as warnings; they never block.
	return R.ok(candidate, _loader_diagnostics(loaded.get("warnings", PackedStringArray()),
		(normal["inventory"] as Array).size(), R.SEVERITY_WARNING))


## Live read-out for the wizard, also for an incomplete or out-of-domain definition; never throws.
## Keys are present only when computable: mass_kg, cg_m, wing_area_m2, mean_chord_m, aspect_ratio,
## neutral_point_x_m, static_margin, wing_loading_kg_m2, level_speed_mps, stall_speed_mps, tail_volume_h,
## tail_volume_v, static_thrust_n, thrust_to_weight; `issues` lists validation and domain diagnostics.
## All values are estimates of the selected packages.
static func summarize(definition: Dictionary) -> Dictionary:
	var study := _study(definition)
	var summary: Dictionary = (study.summary as Dictionary).duplicate(true)
	var issues: Array = []
	var checked: Dictionary = Definition.validate_complete(definition)
	if not checked.ok:
		issues.append_array(checked.diagnostics)
	issues.append_array(_domain(study, definition))
	summary["issues"] = issues
	return summary


## Everything computable from a possibly incomplete definition. `complete` is true when a record can be
## emitted: packages resolved, inventory usable, aerodynamics derived.
static func _study(definition: Dictionary) -> Dictionary:
	var summary := {}
	var study := {summary = summary, complete = false}
	var airframe: Dictionary = Packages.airframe(definition.get("airframe_package"))
	var power: Dictionary = Packages.power(definition.get("power_package"))
	if airframe.ok:
		study.airframe = airframe.value
	if power.ok:
		study.power = power.value
	var wing: Variant = definition.get("wing")
	var span := NAN
	var root := NAN
	var tip := NAN
	if typeof(wing) == TYPE_DICTIONARY:
		span = Packages.positive(wing.get("span"))
		root = Packages.positive(wing.get("root_chord"))
		tip = Packages.positive(wing.get("tip_chord"))
	var area := NAN
	if not is_nan(span) and not is_nan(root) and not is_nan(tip):
		area = span * (root + tip) / 2.0
		summary["wing_area_m2"] = area
		summary["mean_chord_m"] = area / span
		summary["aspect_ratio"] = span * span / area
		study.wing_span = span
		study.taper_ratio = tip / root
	var shape: Dictionary = Packages.geometry(definition)
	study.shape = shape
	if airframe.ok and not shape.is_empty():
		var aero: Dictionary = Packages.airframe_aero(airframe.value, shape)
		if not aero.is_empty():
			study.aero = aero
			summary["neutral_point_x_m"] = float(aero.neutral_point_x)
			summary["tail_volume_h"] = float(aero.tail_volume_h)
			summary["tail_volume_v"] = float(aero.tail_volume_v)
	var mounts := _mounts(definition)
	if power.ok and not mounts.is_empty():
		study.mounts = mounts
		var entries := _inventory_entries(definition, power.value, mounts)
		if not entries.is_empty():
			study.entries = entries
			var mass := 0.0
			var moment := PackedFloat64Array([0.0, 0.0, 0.0])
			# Same left-to-right sums as the loader, so plan_cg equals its inventory CG.
			for entry: Dictionary in entries:
				mass += float(entry.mass)
				for axis: int in 3:
					moment[axis] += float(entry.mass) * float(entry.position[axis])
			var cg := PackedFloat64Array([moment[0] / mass, moment[1] / mass, moment[2] / mass])
			study.mass = mass
			study.cg = cg
			summary["mass_kg"] = mass
			summary["cg_m"] = Array(cg)
	if study.has("mass") and not is_nan(area):
		summary["wing_loading_kg_m2"] = float(study.mass) / area
		if airframe.ok:
			var weight: float = float(study.mass) * Packages.GRAVITY
			var pressure_area: float = 0.5 * Packages.AIR_DENSITY * area
			summary["level_speed_mps"] = sqrt(weight / (pressure_area * Packages.number(airframe.value, "wing", "cruise_lift")))
			summary["stall_speed_mps"] = sqrt(weight / (pressure_area * float(airframe.value.envelope.CL_max.value)))
	if study.has("aero") and study.has("cg"):
		summary["static_margin"] = (float(study.aero.neutral_point_x) - float(study.cg[0])) / float(study.aero.mean_chord)
	var battery: Variant = definition.get("battery")
	if power.ok and typeof(battery) == TYPE_DICTIONARY:
		var charge := Packages.positive(battery.get("initial_soc"))
		if not is_nan(charge) and charge <= 1.0:
			study.initial_soc = charge
			var thrust: Dictionary = Packages.static_thrust(power.value, charge)
			if thrust.ok:
				summary["static_thrust_n"] = float(thrust.thrust_n)
				if study.has("mass"):
					summary["thrust_to_weight"] = float(thrust.thrust_n) / (float(study.mass) * Packages.GRAVITY)
	study.complete = study.has("aero") and study.has("entries") and study.has("initial_soc") \
		and summary.has("level_speed_mps")
	return study


## Hub, battery and ESC positions, or {} while one is missing.
static func _mounts(definition: Dictionary) -> Dictionary:
	var equipment: Variant = definition.get("equipment")
	if typeof(equipment) != TYPE_DICTIONARY:
		return {}
	var hub := Packages.vector(equipment.get("hub_position"), 3)
	var battery := Packages.vector(equipment.get("battery_position"), 3)
	var esc := Packages.vector(equipment.get("esc_position"), 3)
	if hub.is_empty() or battery.is_empty() or esc.is_empty():
		return {}
	return {hub = hub, battery = battery, esc = esc}


## The physical inventory, each item exactly once: the player's items in their order, then the power
## package's hardware. Returns [] while any player item is unusable.
static func _inventory_entries(definition: Dictionary, power: Dictionary, mounts: Dictionary) -> Array:
	var listed: Variant = definition.get("inventory")
	if typeof(listed) != TYPE_ARRAY:
		return []
	var entries := []
	for item: Variant in (listed as Array):
		if typeof(item) != TYPE_DICTIONARY:
			return []
		var mass := Packages.positive(item.get("mass"))
		var position := Packages.vector(item.get("position"), 3)
		var size := Packages.vector(item.get("size"), 3)
		var kind: Variant = item.get("kind")
		if is_nan(mass) or position.is_empty() or size.is_empty() or typeof(item.get("id")) != TYPE_STRING \
				or typeof(kind) != TYPE_STRING or not KIND_SOURCES.has(kind):
			return []
		var source: String = KIND_SOURCES[kind]
		entries.append({
			id = str(item.get("id")), mass = mass, position = position, size = size,
			mass_quantity = {value = mass, unit = "kg", kind = kind, source = source},
			size_quantity = {value = Array(size), unit = "m", kind = kind, source = source},
			position_kind = kind, position_source = source,
		})
	for item: Dictionary in Packages.hardware_items(power, mounts):
		var stated_path := str(MOUNT_FIELDS.get(str(item.get("mount", "")), ""))
		if not stated_path.is_empty():
			item["position_kind"] = Definition.evidence_kind(definition, stated_path)
			item["position_source"] = Definition.evidence_source(definition, stated_path)
		entries.append(item)
	return entries


## Package domain admission: one DOMAIN_REFUSED diagnostic per bound that a computable value breaks.
static func _domain(study: Dictionary, definition: Dictionary) -> Array:
	var out: Array = []
	if not study.has("airframe"):
		return out
	var summary: Dictionary = study.summary
	var values := {}
	for key: String in ["aspect_ratio", "wing_loading_kg_m2", "tail_volume_h", "tail_volume_v", "static_margin",
			"thrust_to_weight", "mass_kg"]:
		if summary.has(key):
			values[key] = summary[key]
	if study.has("wing_span"):
		values["wing_span_m"] = study.wing_span
		values["taper_ratio"] = study.taper_ratio
	var wing: Variant = definition.get("wing")
	if typeof(wing) == TYPE_DICTIONARY and not is_nan(Packages.finite(wing.get("dihedral_deg"))):
		values["wing_dihedral_deg"] = Packages.finite(wing.get("dihedral_deg"))
	if study.has("aero"):
		values["tail_aspect_ratio"] = study.aero.tail_aspect_ratio
		values["fin_aspect_ratio"] = study.aero.fin_aspect_ratio
	elif not (study.shape as Dictionary).is_empty():
		out.append(R.diagnostic(R.DOMAIN_REFUSED, "The tail surfaces must sit behind the wing's quarter chord.",
			"horizontal_tail/position", Definition.STEP_LAYOUT))
	var fuselage: Variant = definition.get("fuselage")
	if study.has("mounts") and typeof(fuselage) == TYPE_DICTIONARY:
		var hub: PackedFloat64Array = study.mounts.hub
		var nose := Packages.finite(fuselage.get("nose_x"))
		var width := Packages.positive(fuselage.get("width"))
		var height := Packages.positive(fuselage.get("height"))
		var center := Packages.finite(fuselage.get("center_z"))
		if not is_nan(nose):
			values["hub_ahead_of_nose_m"] = nose - hub[0]
		if not is_nan(width) and not is_nan(height) and not is_nan(center) \
				and (absf(hub[1]) > 0.5 * width or absf(hub[2] - center) > 0.5 * height):
			out.append(R.diagnostic(R.DOMAIN_REFUSED, "The propeller hub must sit on the fuselage nose, inside its width and height.",
				"equipment/hub_position", Definition.STEP_POWER))
	# Player inputs the borrowed linear derivatives and the installation model only cover in a band.
	for entry: Array in [["controls", "aileron_deg", "aileron_travel_deg"], ["controls", "elevator_deg", "elevator_travel_deg"],
			["controls", "rudder_deg", "rudder_travel_deg"], ["controls", "servo_time_s", "servo_time_s"],
			["battery", "initial_soc", "initial_charge"]]:
		var group: Variant = definition.get(entry[0])
		if typeof(group) == TYPE_DICTIONARY and not is_nan(Packages.finite(group.get(entry[1]))):
			values[entry[2]] = Packages.finite(group.get(entry[1]))
	var equipment: Variant = definition.get("equipment")
	var angles: Variant = equipment.get("thrust_angles_deg") if typeof(equipment) == TYPE_DICTIONARY else null
	if angles is Array and (angles as Array).size() == 2:
		for index: int in 2:
			var angle := Packages.finite((angles as Array)[index])
			if not is_nan(angle):
				values["down_thrust_deg" if index == 0 else "right_thrust_deg"] = angle
	var bounds: Dictionary = study.airframe.domain
	for key: String in DOMAIN_FIELDS:
		if not values.has(key) or not bounds.has(key):
			continue
		var value: float = values[key]
		var low: float = bounds[key]["min"]
		var high: float = bounds[key]["max"]
		if value < low or value > high:
			var target: Array = DOMAIN_FIELDS[key]
			out.append(R.diagnostic(R.DOMAIN_REFUSED, str(target[2]), str(target[0]), str(target[1]), [value, low, high]))
	return out


## The closed openrc-aircraft v2 record. Every quantity carries its honest kind and source: player
## geometry `manual`, inventory items their own kind, computed values `derived` with the formula named,
## package constants as the package labels them. Inventory `name` is the stable ID: display text is not
## part of the physical bytes.
static func _record(definition: Dictionary, study: Dictionary, aircraft: String) -> Dictionary:
	var airframe: Dictionary = study.airframe
	var power: Dictionary = study.power
	var aero: Dictionary = study.aero
	var shape: Dictionary = study.shape
	var cg: PackedFloat64Array = study.cg
	var mounts: Dictionary = study.mounts
	var hub: PackedFloat64Array = mounts.hub
	var summary: Dictionary = study.summary
	var controls: Dictionary = definition["controls"]
	var tapered: bool = float(shape.tip_chord) < float(shape.root_chord)
	var reference := {
		wing_area = {value = float(aero.wing_area), unit = "m2", kind = Packages.DERIVED,
			source = "wing/span × (root_chord + tip_chord)/2 of the player's wing"},
		wing_span = _stated(float(shape.span), "m", definition, "wing/span"),
		mean_chord = {value = float(aero.mean_chord), unit = "m", kind = Packages.DERIVED,
			source = "wing_area / wing_span: the coefficient reference chord S/b"},
		aero_reference_point = {value = Array(aero.arp as PackedFloat64Array), unit = "m", kind = Packages.DERIVED,
			source = "package assumption: unswept quarter-chord line, x = 0.25 × root_chord, z = 0 at the wing root; the rise of a dihedral wing's panels is neglected"},
		planform = "tapered" if tapered else "rectangular",
	}
	if tapered:
		reference["root_chord"] = _stated(float(shape.root_chord), "m", definition, "wing/root_chord")
		reference["tip_chord"] = _stated(float(shape.tip_chord), "m", definition, "wing/tip_chord")
	var inventory := []
	for entry: Dictionary in study.entries:
		var item := {
			id = entry.id, name = entry.id, mass = entry.mass_quantity,
			position = {value = Array(entry.position as PackedFloat64Array), unit = "m", kind = entry.position_kind,
				source = entry.position_source},
			size = entry.size_quantity,
		}
		if entry.has("energy_source"):
			item["energy_source"] = entry.energy_source
		inventory.append(item)
	var hull := _hull(definition, shape, hub, Packages.number(power, "installation", "spinner_length"))
	var hull_points := []
	var hull_components := []
	var hull_ids := []
	for point: Array in hull:
		hull_ids.append(point[0])
		hull_components.append(point[1])
		hull_points.append(point[2])
	var mass_bounds: Dictionary = airframe.domain.mass_kg
	var angles := Packages.vector(definition["equipment"]["thrust_angles_deg"], 2)
	return {
		format = AircraftData.FORMAT,
		id = aircraft,
		description = "Compiled by the Aircraft Creator from an openrc-creator-definition v1. Airframe package %s, power package %s: estimated and experimental, not calibrated against a real aircraft." % [airframe.id, power.id],
		frames = {
			le_frame = "positions in metres from the wing leading edge at the fuselage centreline: [x_aft, y_right, z_up]; z = 0 at the wing root chord",
			body = "simulation body axes FRD about the CG: x forward = -x_aft, y right, z down = -z_up",
		},
		convention_id = "openrc-le-frd-v1",
		capabilities = {
			controls = "conventional", gear = "locked_up", propulsion_layout = "single_tractor",
			energy = "ocv_resistance", damage = "terminal_hull", flaps = "not_simulated",
		},
		physical_identity_version = 1,
		reference = reference,
		start = {level_speed = {value = float(summary["level_speed_mps"]), unit = "m/s", kind = Packages.DERIVED,
			source = "level flight at the package's cruise lift coefficient: √(2·m·g/(ρ·S·CL)), ρ 1.225 kg/m3, g 9.80665 m/s²"}},
		balance = {
			plan_cg = {value = Array(cg), unit = "m", kind = Packages.DERIVED,
				source = "centre of mass of the inventory below: Σ m·r / Σ m"},
			firewall = {value = [hub[0] + Packages.number(power, "installation", "firewall_behind_hub"), hub[1], hub[2]],
				unit = "m", kind = Packages.DERIVED, source = "equipment/hub_position plus the power package's motor length behind the hub"},
			configuration = BALANCE_CONFIGURATION,
			cg_tolerance = {value = CG_TOLERANCE_M, unit = "m", kind = Packages.DERIVED,
				source = "plan_cg is computed from this inventory; the tolerance only covers rounding"},
		},
		inventory = inventory,
		crash_hull = {value = hull_points, unit = "m", kind = Packages.DERIVED,
			source = "Aircraft Creator: extreme points of the player's stated geometry (wing outline with its tips raised by the stated dihedral, flat tail outlines, box fuselage, spinner); an estimate of where the airframe meets the ground, not read from the 3D model"},
		crash_hull_components = hull_components,
		crash_hull_ids = hull_ids,
		plausibility = {
			mass_range = {value = [float(mass_bounds["min"]), float(mass_bounds["max"])], unit = "kg", kind = "estimated",
				source = "mass domain of airframe package %s" % airframe.id},
			inertia_reference = airframe.plausibility.inertia_reference,
		},
		controls = {
			max_throw = {
				aileron = _stated(float(controls["aileron_deg"]), "deg", definition, "controls/aileron_deg"),
				elevator = _stated(float(controls["elevator_deg"]), "deg", definition, "controls/elevator_deg"),
				rudder = _stated(float(controls["rudder_deg"]), "deg", definition, "controls/rudder_deg"),
			},
			servo_full_throw_time = _stated(float(controls["servo_time_s"]), "s", definition, "controls/servo_time_s"),
			surface_ids = SURFACE_IDS.duplicate(),
		},
		aero = _stated_dihedral(Packages.aero_block(airframe, aero), definition),
		propulsion = _stated_propulsion(Packages.propulsion_block(power, PROPULSION_ID, float(study.initial_soc),
			PackedFloat64Array([hub[0] - cg[0], hub[1] - cg[1], hub[2] - cg[2]]), angles), definition),
	}


## One player-supplied quantity with the evidence the definition states for it: `manual` when the
## player typed it, `measured` when they say so, `estimated` for an unconfirmed starting value.
static func _stated(value: Variant, unit: String, definition: Dictionary, path: String) -> Dictionary:
	return {value = value, unit = unit, kind = Definition.evidence_kind(definition, path),
		source = Definition.evidence_source(definition, path)}


## The record has no field for the dihedral angle itself: it acts only through the derived wing-body
## Clβ and the Clb that contains it. Their sources name the stated angle and who supplied it.
static func _stated_dihedral(aero: Dictionary, definition: Dictionary) -> Dictionary:
	var note := "; wing dihedral %s deg from %s" % [str(float(definition["wing"]["dihedral_deg"])),
		Definition.evidence_source(definition, "wing/dihedral_deg")]
	for target: Dictionary in [aero.surfaces.wing_body_cl_beta, aero.coefficients.Clb]:
		target["source"] = str(target["source"]) + note
	return aero


## The package writes the two player-supplied propulsion quantities; restate their evidence here.
static func _stated_propulsion(propulsion: Dictionary, definition: Dictionary) -> Dictionary:
	for target: Array in [[propulsion.battery.initial_soc, "battery/initial_soc"],
			[propulsion.propeller.thrust_angles, "equipment/thrust_angles_deg"]]:
		(target[0] as Dictionary)["kind"] = Definition.evidence_kind(definition, str(target[1]))
		(target[0] as Dictionary)["source"] = Definition.evidence_source(definition, str(target[1]))
	return propulsion


## Crash-hull points [id, component, [x, y, z]] from the stated geometry. IDs are fixed semantic names.
static func _hull(definition: Dictionary, shape: Dictionary, hub: PackedFloat64Array, spinner: float) -> Array:
	var fuselage: Dictionary = definition["fuselage"]
	var root: float = shape.root_chord
	var tip: float = shape.tip_chord
	var half: float = 0.5 * float(shape.span)
	var tip_front: float = 0.25 * root - 0.25 * tip
	var tip_back: float = 0.25 * root + 0.75 * tip
	# Each panel rises from the root by its dihedral: the tips sit above the root plane.
	var tip_up: float = half * tan(deg_to_rad(float(shape.dihedral_deg)))
	var h_position: PackedFloat64Array = shape.h_position
	var h_half: float = 0.5 * float(shape.h_span)
	var h_back: float = h_position[0] + float(shape.h_chord)
	var v_position: PackedFloat64Array = shape.v_position
	var v_top: float = v_position[2] + float(shape.v_height)
	var nose: float = fuselage["nose_x"]
	var tail_end: float = fuselage["tail_x"]
	var side: float = 0.5 * float(fuselage["width"])
	var bottom: float = float(fuselage["center_z"]) - 0.5 * float(fuselage["height"])
	var top: float = float(fuselage["center_z"]) + 0.5 * float(fuselage["height"])
	return [
		["probe_wing_left_tip_le", "left_wing_tip", [tip_front, -half, tip_up]],
		["probe_wing_left_tip_te", "left_wing_tip", [tip_back, -half, tip_up]],
		["probe_wing_right_tip_le", "right_wing_tip", [tip_front, half, tip_up]],
		["probe_wing_right_tip_te", "right_wing_tip", [tip_back, half, tip_up]],
		["probe_stabilizer_left_tip_le", "left_stab_tip", [h_position[0], -h_half, h_position[2]]],
		["probe_stabilizer_left_tip_te", "left_stab_tip", [h_back, -h_half, h_position[2]]],
		["probe_stabilizer_right_tip_le", "right_stab_tip", [h_position[0], h_half, h_position[2]]],
		["probe_stabilizer_right_tip_te", "right_stab_tip", [h_back, h_half, h_position[2]]],
		["probe_fin_top_le", "fin_top", [v_position[0], 0.0, v_top]],
		["probe_fin_top_te", "fin_top", [v_position[0] + float(shape.v_chord), 0.0, v_top]],
		["probe_spinner_tip", "spinner", [hub[0] - spinner, hub[1], hub[2]]],
		["probe_nose_top_left", "nose", [nose, -side, top]],
		["probe_nose_top_right", "nose", [nose, side, top]],
		["probe_nose_bottom_left", "nose", [nose, -side, bottom]],
		["probe_nose_bottom_right", "nose", [nose, side, bottom]],
		["probe_belly_front_left", "belly", [0.0, -side, bottom]],
		["probe_belly_front_right", "belly", [0.0, side, bottom]],
		["probe_belly_rear_left", "belly", [root, -side, bottom]],
		["probe_belly_rear_right", "belly", [root, side, bottom]],
		["probe_fuselage_top_front", "canopy", [0.0, 0.0, top]],
		["probe_fuselage_top_rear", "canopy", [root, 0.0, top]],
		["probe_tail_end_top", "tail_end", [tail_end, 0.0, top]],
		["probe_tail_end_bottom", "tail_end", [tail_end, 0.0, bottom]],
	]


## Flight-loader refusals (or, as warnings, its data-quality notes) as diagnostics. The loader text is kept
## as the argument; field and step are mapped from the record path it names, where that path has one
## authoring field.
static func _loader_diagnostics(errors: Variant, player_items: int, severity: String = R.SEVERITY_ERROR) -> Array:
	var out: Array = []
	for entry: Variant in errors:
		var text := str(entry)
		var field := ""
		var step: String = Definition.STEP_REVIEW
		if text.begins_with("inventory[") or text.begins_with("/inventory/"):
			var index := _leading_integer(text.substr(10 if text.begins_with("inventory[") else 11))
			field = "inventory/%d" % index if index < player_items else "power_package"
			step = Definition.STEP_BALANCE if index < player_items else Definition.STEP_POWER
		elif text.begins_with("total mass") or text.begins_with("balance") or text.begins_with("inertia"):
			field = "inventory"
			step = Definition.STEP_BALANCE
		elif text.begins_with("reference") or text.begins_with("aero.envelope") or text.begins_with("aero.coefficients") \
				or text.begins_with("start"):
			field = "wing/span"
			step = Definition.STEP_LAYOUT
		elif text.begins_with("aero.surfaces.vertical"):
			field = "vertical_tail/position"
			step = Definition.STEP_LAYOUT
		elif text.begins_with("aero.surfaces"):
			field = "horizontal_tail/position"
			step = Definition.STEP_LAYOUT
		elif text.begins_with("crash_hull"):
			field = "fuselage/tail_x"
			step = Definition.STEP_LAYOUT
		elif text.begins_with("propulsion.propeller.thrust_line_offset"):
			field = "equipment/hub_position"
			step = Definition.STEP_POWER
		elif text.begins_with("propulsion.battery.initial_soc"):
			field = "battery/initial_soc"
			step = Definition.STEP_POWER
		elif text.begins_with("propulsion"):
			field = "power_package"
			step = Definition.STEP_POWER
		elif text.begins_with("controls"):
			field = "controls/aileron_deg"
			step = Definition.STEP_CONTROLS
		out.append(R.diagnostic(R.BUILD_INVALID, "The flight loader refused the compiled aircraft: %s" if severity == R.SEVERITY_ERROR
			else "The flight loader notes: %s", field, step, [text], severity))
	return out


## The decimal digits a text starts with, as an integer; a very large value when it starts with none.
static func _leading_integer(text: String) -> int:
	var count := 0
	while count < text.length() and text[count] >= "0" and text[count] <= "9":
		count += 1
	return text.substr(0, count).to_int() if count > 0 else Limits.INVENTORY_ITEMS
