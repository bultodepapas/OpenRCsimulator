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
## IAQ T3: an airframe's optional wing.start_alpha start keeps its trim elevator inside this share of the travel,
## and its start lift at least this coefficient.
const START_ELEVATOR_SHARE := 0.8
const MIN_START_LIFT := 0.3
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
	# Legacy v2 remains structurally readable for reopening, but cannot silently compile the
	# default electric package from source observations without an explicit new declaration.
	if normal.format == Definition.SOURCE_FORMAT:
		return R.fail(R.UNSUPPORTED_CAPABILITY,Definition.Installation.REQUIRED,"source_installation","import")
	# Review metadata changes definition identity, never the canonical physical v1 inputs/bytes.
	var physical: Dictionary = normal.duplicate(true)
	physical.erase("source_observations")
	physical.erase("source_installation")
	physical.erase("servo_integration")
	physical.format = Definition.FORMAT
	var encoded_definition: Dictionary = CreatorBytes.encode(normal)
	if not encoded_definition.ok:
		return R.fail_all(encoded_definition.diagnostics)
	var study := _study(physical)
	var domain := _domain(study, physical)
	if not study.get("complete", false):
		# A valid definition whose geometry no record can describe (a tail ahead of the wing).
		if domain.is_empty():
			domain.append(R.diagnostic(R.BUILD_INVALID, "The aircraft cannot be described by this package.", "", Definition.STEP_REVIEW))
		return R.fail_all(domain)
	var aircraft := Definition.aircraft_id(str(normal["aircraft_uuid"]))
	var record := _record(physical, study, aircraft)
	if normal.format == Definition.SERVO_FORMAT:
		record.controls.servo_integration = normal.servo_integration
	var written: Dictionary = CreatorBytes.encode(record)
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
	if normal.format == Definition.SERVO_FORMAT:
		read_out["servo_integration"] = normal.servo_integration
	if normal.has("source_installation"):
		read_out["source_installation"] = normal.source_installation.duplicate(true)
	if normal.has("source_observations"):
		read_out["source_observations"] = normal.source_observations.duplicate(true)
		read_out["source_observations_sha256"] = Definition.Observations.digest(normal.source_observations)
		read_out["source_observations_validation"] = "structure_only"
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
			summary["level_speed_mps"] = sqrt(weight / (pressure_area * _start_lift(airframe.value, study, definition)))
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


## The start's lift coefficient: the package's cruise lift, or (an airframe declaring the optional
## wing.start_alpha, IAQ T3) the whole aircraft's linear level trim at that body angle, about the CG with the
## tail's trim load, its elevator inside START_ELEVATOR_SHARE of the travel where an angle at or below
## start_alpha allows it, never above the cruise lift (the package's slowest start). The product's half-throttle
## trim searches upward from this speed.
static func _start_lift(airframe: Dictionary, study: Dictionary, definition: Dictionary) -> float:
	var cruise := Packages.number(airframe, "wing", "cruise_lift")
	var wing: Dictionary = airframe.get("wing", {})
	if not (wing.get("start_alpha") is Dictionary and study.has("aero") and study.has("cg")):
		return cruise
	var q: Dictionary = study.aero.quantities
	var value := func(name: String) -> float: return float(q[name].value) if q.get(name) is Dictionary else float(q.get(name, NAN))
	var arm := (float(study.cg[0]) - float((study.aero.arp as PackedFloat64Array)[0])) / float(study.aero.mean_chord)
	# Cm about the CG = Cm(ARP) + CL·(x_cg − x_arp)/c = 0 gives the elevator δ(α) = −(m0 + mα·α)/mδ.
	var m0: float = value.call("Cm0") + arm * value.call("CL0")
	var m_alpha: float = value.call("Cma") + arm * value.call("CLa")
	var m_delta: float = value.call("Cmde") + arm * value.call("CLde")
	var controls: Variant = definition.get("controls")
	var travel := deg_to_rad(float(controls.get("elevator_deg", NAN))) if controls is Dictionary else NAN
	if not (is_finite(m0) and is_finite(m_alpha) and m_alpha < 0.0 and is_finite(m_delta) and absf(m_delta) > 1e-9 and travel > 0.0):
		return cruise
	var alpha := float(wing.start_alpha.value)
	# The elevator is linear in α, so the travel share holds on one interval of α (either sign of mδ): the largest
	# α ≤ start_alpha inside it. An interval wholly above start_alpha keeps start_alpha (no slower trim is safer).
	var limit := START_ELEVATOR_SHARE * travel
	var ends := [-(limit * m_delta + m0) / m_alpha, -(-limit * m_delta + m0) / m_alpha]
	if minf(ends[0], ends[1]) <= alpha:
		alpha = minf(alpha, maxf(ends[0], ends[1]))
	var elevator := -(m0 + m_alpha * alpha) / m_delta
	var lift: float = value.call("CL0") + value.call("CLa") * alpha + value.call("CLde") * elevator
	return clampf(lift, MIN_START_LIFT, cruise) if is_finite(lift) else cruise


## The record's `flaps` from an airframe package's flap member: span fractions become metres of the player's half
## span and the limit-speed advisory a multiple of the derived stall speed.
static func _flaps_block(flaps: Dictionary, span: float, stall: float) -> Dictionary:
	var out := {}
	for key: String in ["max_angle_deg", "takeoff_angle_deg", "hinge_fraction", "extension_time", "retraction_time",
			"elevator_mix_per_flap_fraction", "effective_angle_limit_deg", "profile_drag_coefficient", "aerodynamic_gain",
			"stall_shift_fraction"]:
		if flaps.get(key) is Dictionary:
			out[key] = (flaps[key] as Dictionary).duplicate(true)
	for pair: Array in [["inner_span_m", "inner_span_fraction"], ["outer_span_m", "outer_span_fraction"]]:
		var fraction: Dictionary = flaps[pair[1]]
		out[pair[0]] = {value = float(fraction.value) * 0.5 * span, unit = "m", kind = Packages.DERIVED,
			source = str(fraction.source) + ", × the half span"}
	var ratio := float(flaps.max_speed_stall_ratio.value)
	out["max_speed_mps"] = {value = clampf(ratio * stall, 5.0, 100.0) if is_finite(stall) else 20.0, unit = "m/s",
		kind = Packages.DERIVED, source = "%s × the derived stall speed (advisory)" % String.num(ratio, 2)}
	return out


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
		if not is_nan(nose) and not (study.has("power") and Packages.is_pusher(study.power)):
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


## Landing-gear constants (AC-21): see `_landing_gear`.
const GEAR_OMEGA_RAD_S := 23.0
const GEAR_DAMPING_RATIO := 0.4
const GEAR_TRAVEL_PER_SAG := 6.5
const GEAR_TRAVEL_RANGE := [0.05, 0.25]
## No wheel group carries less than this share of the weight (a CG almost over one axle).
const GEAR_MIN_SHARE := 0.05
## Nose-up rotation a tricycle's tail must clear about its main wheels, and the hull's clearance above the
## gear's ground lines.
const GEAR_ROTATION_DEG := 12.0
## Extra nose-up pitch a taildragger's aft hull points must clear beyond the three-point line.
const GEAR_PITCH_MARGIN_DEG := 5.0
const HULL_GEAR_CLEARANCE_M := 0.01


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
	# A signed length: ahead of a tractor hub, behind a pusher hub.
	var hull := _hull(definition, shape, hub, Packages.aft_sign(power) * Packages.number(power, "installation", "spinner_length"))
	var hull_note := ""
	if definition.has("landing_gear"):
		hull_note = _clear_hull_for_gear(hull, definition["landing_gear"])
	var hull_points := []
	var hull_components := []
	var hull_ids := []
	for point: Array in hull:
		hull_ids.append(point[0])
		hull_components.append(point[1])
		hull_points.append(point[2])
	var mass_bounds: Dictionary = airframe.domain.mass_kg
	var angles := Packages.vector(definition["equipment"]["thrust_angles_deg"], 2)
	var gear: Dictionary = _landing_gear(definition, study) if definition.has("landing_gear") else {}
	var record := {
		format = AircraftData.FORMAT,
		id = aircraft,
		description = "Compiled by the Aircraft Creator from an openrc-creator-definition v1. Airframe package %s, power package %s: estimated and experimental, not calibrated against a real aircraft." % [airframe.id, power.id],
		frames = {
			le_frame = "positions in metres from the wing leading edge at the fuselage centreline: [x_aft, y_right, z_up]; z = 0 at the wing root chord",
			body = "simulation body axes FRD about the CG: x forward = -x_aft, y right, z down = -z_up",
		},
		convention_id = "openrc-le-frd-v1",
		capabilities = {
			controls = "conventional", gear = "fixed_" + str(definition["landing_gear"]["layout"]) if not gear.is_empty() else "locked_up",
			propulsion_layout = "single_centerline_jet" if Packages.is_jet(power) else ("single_pusher" if Packages.is_pusher(power) else "single_tractor"),
			energy = "prescribed_fuel" if Packages.is_jet(power) else "ocv_resistance", damage = "terminal_hull", flaps = "not_simulated",
		},
		physical_identity_version = 1,
		reference = reference,
		start = {level_speed = {value = float(summary["level_speed_mps"]), unit = "m/s", kind = Packages.DERIVED,
			source = "level flight at the package's cruise lift coefficient: √(2·m·g/(ρ·S·CL)), ρ 1.225 kg/m3, g 9.80665 m/s²"}},
		balance = {
			plan_cg = {value = Array(cg), unit = "m", kind = Packages.DERIVED,
				source = "centre of mass of the inventory below: Σ m·r / Σ m"},
			firewall = {value = [hub[0] + Packages.aft_sign(power) * Packages.number(power, "installation", "firewall_behind_hub"), hub[1], hub[2]],
				unit = "m", kind = Packages.DERIVED, source = "equipment/hub_position plus the power package's motor length behind the hub"},
			configuration = BALANCE_CONFIGURATION,
			cg_tolerance = {value = CG_TOLERANCE_M, unit = "m", kind = Packages.DERIVED,
				source = "plan_cg is computed from this inventory; the tolerance only covers rounding"},
		},
		inventory = inventory,
		crash_hull = {value = hull_points, unit = "m", kind = Packages.DERIVED,
			source = "Aircraft Creator: extreme points of the player's stated geometry (wing outline with its tips raised by the stated dihedral, flat tail outlines, box fuselage, spinner); an estimate of where the airframe meets the ground, not read from the 3D model" + hull_note},
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
	# Optional member (AC-21): a definition without landing gear compiles to exactly the record it always did.
	if not gear.is_empty():
		record["landing_gear"] = gear
	# Optional trailing-edge flaps a source-derived airframe package carries (IAQ T7: Phoenix flaps); absent otherwise.
	if airframe.get("flaps") is Dictionary:
		record["flaps"] = _flaps_block(airframe.flaps, float(shape.span), float(summary.get("stall_speed_mps", NAN)))
		record.capabilities.flaps = "simulated"
	# Optional stick shaping a source-derived airframe package carries (IAQ T5: Phoenix expo); absent otherwise.
	if airframe.get("rates") is Dictionary:
		record.controls["rates"] = (airframe.rates as Dictionary).duplicate(true)
	return record


## Fixed landing gear from the definition's wheel bottoms (AC-21). The spring and damper are not the
## model's: total stiffness m·ω² with ω = GEAR_OMEGA_RAD_S (the Stik's E1 rule ω·dt < 0.1 at 240 Hz),
## split by each wheel's static load so the aircraft rests level, damping ratio GEAR_DAMPING_RATIO, and the
## Stik's tyre coefficients.
static func _landing_gear(definition: Dictionary, study: Dictionary) -> Dictionary:
	var gear: Dictionary = definition["landing_gear"]
	var mass := float(study.mass)
	var cg: PackedFloat64Array = study.cg
	var contacts: Array = gear["contacts"]
	# Static load shares: the wheels ahead of the CG against those behind it (lever rule along x).
	var ahead: Array = []
	var behind: Array = []
	for contact: Dictionary in contacts:
		(ahead if float(contact["position"][0]) < cg[0] else behind).append(contact)
	var shares := {}
	if ahead.is_empty() or behind.is_empty():
		for contact: Dictionary in contacts:
			shares[contact["id"]] = 1.0 / contacts.size()
	else:
		var x_ahead := 0.0
		var x_behind := 0.0
		for contact: Dictionary in ahead:
			x_ahead += float(contact["position"][0]) / ahead.size()
		for contact: Dictionary in behind:
			x_behind += float(contact["position"][0]) / behind.size()
		var front := clampf((x_behind - cg[0]) / maxf(x_behind - x_ahead, 1e-6), GEAR_MIN_SHARE, 1.0 - GEAR_MIN_SHARE)
		for contact: Dictionary in ahead:
			shares[contact["id"]] = front / ahead.size()
		for contact: Dictionary in behind:
			shares[contact["id"]] = (1.0 - front) / behind.size()
	var total_k := mass * GEAR_OMEGA_RAD_S * GEAR_OMEGA_RAD_S
	var sag := Packages.GRAVITY / (GEAR_OMEGA_RAD_S * GEAR_OMEGA_RAD_S)
	var travel := clampf(GEAR_TRAVEL_PER_SAG * sag, GEAR_TRAVEL_RANGE[0], GEAR_TRAVEL_RANGE[1])
	var out_contacts: Array = []
	for contact: Dictionary in contacts:
		var share: float = shares[contact["id"]]
		var k := total_k * share
		out_contacts.append({
			name = str(contact["id"]),
			position = _stated(Array(contact["position"]), "m", definition, "landing_gear"),
			stiffness = {value = k, unit = "N/m", kind = "estimated",
				source = "Aircraft Creator: m·ω² with ω %s rad/s (the Stik's ω·dt < 0.1 rule at 240 Hz), times this wheel's static load share %s (lever rule about the CG), so the aircraft rests level; not measured" % [
					String.num(GEAR_OMEGA_RAD_S, 1), String.num(share, 3)]},
			damping = {value = 2.0 * GEAR_DAMPING_RATIO * sqrt(k * mass * share), unit = "N·s/m", kind = "estimated",
				source = "damping ratio %s of this wheel's load share: c = 2ζ·sqrt(k·m·share); not measured" % String.num(GEAR_DAMPING_RATIO, 2)},
			max_compression = {value = travel, unit = "m", kind = "estimated",
				source = "%s × the static sag g/ω² (%s m), inside %s–%s m; not measured" % [String.num(GEAR_TRAVEL_PER_SAG, 1),
					String.num(sag, 4), String.num(GEAR_TRAVEL_RANGE[0], 2), String.num(GEAR_TRAVEL_RANGE[1], 2)]},
			max_steering = _stated(float(contact["steering_deg"]), "deg", definition, "landing_gear"),
			id = "contact_" + str(contact["id"]),
		})
	return {
		description = "Aircraft Creator fixed landing gear (AC-21): spring-damper wheels at the stated wheel bottoms, tyre forces from the Stik's dry-pavement coefficients; brakes none. Estimated, not measured.",
		contacts = out_contacts,
		rolling_resistance = {value = 0.04, unit = "1", kind = "borrowed",
			source = "Jensen Ugly Stik 60 record: rolling resistance of a small RC wheel on dry pavement"},
		side_friction = {value = 0.8, unit = "1", kind = "borrowed",
			source = "Jensen Ugly Stik 60 record: peak tyre friction on dry pavement (JSBSim c172x)"},
		peak_slip_angle = {value = 6.0, unit = "deg", kind = "borrowed",
			source = "Jensen Ugly Stik 60 record: slip angle of the peak side force (JSBSim FGLGear)"},
		breakaway_factor = {value = 1.25, unit = "1", kind = "borrowed",
			source = "Jensen Ugly Stik 60 record: static over rolling resistance of a wheel at rest"},
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
	var stated: Array = [[propulsion.thrust_angles, "equipment/thrust_angles_deg"]] if propulsion.get("kind") == "turbine" else \
		[[propulsion.battery.initial_soc, "battery/initial_soc"], [propulsion.propeller.thrust_angles, "equipment/thrust_angles_deg"]]
	for target: Array in stated:
		(target[0] as Dictionary)["kind"] = Definition.evidence_kind(definition, str(target[1]))
		(target[0] as Dictionary)["source"] = Definition.evidence_source(definition, str(target[1]))
	return propulsion


## With landing gear the box-fuselage estimate must not reach below the gear's ground lines, or the aircraft
## would "crash" standing still: the resting line through the main wheels and the nose or tail wheel, the
## tail-up rolling line of a taildragger (level at the main wheels) and a tricycle's rotation line
## (GEAR_ROTATION_DEG nose-up about the main wheels); a taildragger's aft points also clear the three-point
## line pitched GEAR_PITCH_MARGIN_DEG further. Hull points below them are raised to
## the clearance above: HULL_GEAR_CLEARANCE_M plus twice the static sag of the wheels. Returns the note for the hull's source text ("" when nothing moved).
static func _clear_hull_for_gear(hull: Array, gear: Dictionary) -> String:
	var contacts: Array = gear["contacts"]
	var tricycle := str(gear["layout"]) == "tricycle"
	var lead: Dictionary = contacts[0]
	for contact: Dictionary in contacts:
		var better: bool = float(contact["position"][0]) < float(lead["position"][0]) if tricycle \
			else float(contact["position"][0]) > float(lead["position"][0])
		if better:
			lead = contact
	var x_main := 0.0
	var z_main := 0.0
	var mains := 0
	for contact: Dictionary in contacts:
		if contact != lead:
			x_main += float(contact["position"][0])
			z_main += float(contact["position"][2])
			mains += 1
	x_main /= mains
	z_main /= mains
	var x_lead := float(lead["position"][0])
	var z_lead := float(lead["position"][2])
	var slope := (z_lead - z_main) / (x_lead - x_main) if absf(x_lead - x_main) > 1e-6 else 0.0
	var rotation := tan(deg_to_rad(GEAR_ROTATION_DEG))
	var clearance := HULL_GEAR_CLEARANCE_M + 2.0 * Packages.GRAVITY / (GEAR_OMEGA_RAD_S * GEAR_OMEGA_RAD_S)
	var raised := 0
	for point: Array in hull:
		var at: Array = point[2]
		var x := float(at[0])
		var ground := z_main + slope * (x - x_main)
		if not tricycle:
			ground = maxf(ground, z_main)
			if x > x_main:
				# The tail may sit a little lower than the geometric three-point line (tyre and leg sag).
				ground = maxf(ground, z_main + tan(atan(slope) + deg_to_rad(GEAR_PITCH_MARGIN_DEG)) * (x - x_main))
		elif x > x_main:
			ground = maxf(ground, z_main + rotation * (x - x_main))
		if float(at[2]) < ground + clearance:
			at[2] = ground + clearance
			raised += 1
	if raised == 0:
		return ""
	return "; %d points raised to %s m above the landing gear's resting, rolling and rotation lines so the box estimate never touches the ground on its wheels" % [
		raised, String.num(clearance, 3)]


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
