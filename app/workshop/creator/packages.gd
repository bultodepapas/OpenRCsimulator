extends RefCounted
## Estimated packages of the Aircraft Creator (AC-05): the data under res://data/creator/ and the closed
## forms that turn a player's geometry into one consistent coefficient set for the existing wing-tail law.
##
## Software estimates only: nothing here is calibrated against a real aircraft. Formulas, borrowed values,
## limits and domain: docs/research/aircraft-creator/estimated-trainer-package.md.
## Positions are metres in the leading-edge frame [x_aft, y_right, z_up]; physical math is 64-bit float.

const R := preload("res://workshop/creator/result.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Propulsion := preload("res://physics/propulsion.gd")

const AIRFRAME_FORMAT := "openrc-creator-airframe-package v1"
const POWER_FORMAT := "openrc-creator-power-package v1"
const AIRFRAMES := {
	"conventional-trainer-estimated-v1": "res://data/creator/airframe-conventional-trainer-estimated-v1.json",
	"conventional-parkflyer-estimated-v1": "res://data/creator/airframe-conventional-parkflyer-estimated-v1.json",
}
const POWERS := {
	"electric-4s-800kv-apc12x6-estimated-v1": "res://data/creator/power-electric-4s-800kv-apc12x6-estimated-v1.json",
	"electric-4s-800kv-apc12x6-pusher-estimated-v1": "res://data/creator/power-electric-4s-800kv-apc12x6-pusher-estimated-v1.json",
	"electric-3s-1250kv-9x6-estimated-v1": "res://data/creator/power-electric-3s-1250kv-9x6-estimated-v1.json",
	"electric-3s-1250kv-9x6-pusher-estimated-v1": "res://data/creator/power-electric-3s-1250kv-9x6-pusher-estimated-v1.json",
	"electric-4s-1900kv-6x45-pusher-estimated-v1": "res://data/creator/power-electric-4s-1900kv-6x45-pusher-estimated-v1.json",
	"electric-6s-1200kv-7x5-pusher-estimated-v1": "res://data/creator/power-electric-6s-1200kv-7x5-pusher-estimated-v1.json",
}
const QUALIFICATION := "experimental"
const QUANTITY_KINDS := ["manual", "measured", "borrowed", "estimated", "derived"]
const HARDWARE_MOUNTS := ["hub", "motor", "esc", "battery"]
## Sea-level standard air and standard gravity: the read-outs and the derived start speed use them.
const AIR_DENSITY := 1.225
const GRAVITY := 9.80665
const DERIVED := "derived"
const ESTIMATE_NOTE := " (Aircraft Creator estimate from the player's geometry, not measured)"
## Fixed IDs of the proposed airframe items, in proposal order.
const AIRFRAME_ITEM_IDS := ["item_wing_airframe", "item_fuselage_airframe", "item_stabilizer_elevator",
	"item_fin_rudder", "item_servo_aileron_left", "item_servo_aileron_right", "item_servos_tail",
	"item_receiver_main", "item_control_hardware"]

static var _cache: Dictionary = {}
static var _thrust_cache: Dictionary = {}


## True for a power package whose thrust comes from a ducted fan or turbine (IAQ T4): its optional `jet`
## member {static_thrust, idle_thrust, efflux_speed, idle_rpm, max_rpm, spool_time} replaces the propeller in
## the record by OpenRC's `turbine` law (momentum thrust with ram drag, spool limits, no reaction torque).
static func is_jet(package: Dictionary) -> bool:
	return package.get("jet") is Dictionary and not (package.jet as Dictionary).is_empty()


## True for a pusher power package: its motor and firewall sit ahead of the hub.
static func is_pusher(package: Dictionary) -> bool:
	return str(package.get("layout", "tractor")) == "pusher"


## +1 when installation lengths behind the hub point aft (tractor), -1 when they point forward (pusher).
static func aft_sign(package: Dictionary) -> float:
	return -1.0 if is_pusher(package) else 1.0


## Result envelope; value = a private deep copy of the airframe package data.
static func airframe(id: Variant) -> Dictionary:
	return _resolve(id, AIRFRAMES, AIRFRAME_FORMAT, "airframe_package", "aircraft_layout")


## Result envelope; value = a private deep copy of the power package data.
static func power(id: Variant) -> Dictionary:
	return _resolve(id, POWERS, POWER_FORMAT, "power_package", "power_mount")


## Source-derived packages (Phoenix physics, `phoenix/physics.gd`), registered in-process under
## content-addressed ids. They pass the same package checks as the installed files.
static var _derived_packages: Dictionary = {}


static func register_derived(id: String, package: Dictionary) -> Dictionary:
	var format := AIRFRAME_FORMAT if package.get("format") == AIRFRAME_FORMAT else POWER_FORMAT
	# A derived id is composite ("<source>|…") and never shadows an installed package.
	if not id.contains("|") or AIRFRAMES.has(id) or POWERS.has(id):
		return R.fail(R.DEPENDENCY_MISSING, "Package %s cannot be registered as a derived package.", "airframe_package", "aircraft_layout", [id])
	var problem := _package_problem(package, id, format)
	if not problem.is_empty():
		return R.fail(R.DEPENDENCY_MISSING, "Package %s cannot be used: %s", "airframe_package", "aircraft_layout", [id, problem])
	_derived_packages[id] = package.duplicate(true)
	return R.ok(id)


## A36 O1: snapshot of the derived ids registered now, so an owner can tell which ids it created itself.
static func derived_ids() -> PackedStringArray:
	return PackedStringArray(_derived_packages.keys())


## A36 O1: retire derived packages that their creating owner no longer uses. Only the owner that created an id (it was
## absent from that owner's earlier snapshot) may retire it; ids already present belong to other drafts or history.
## Returns the number of packages removed.
static func retire_derived(ids: Array) -> int:
	var removed := 0
	for id: Variant in ids:
		if typeof(id) == TYPE_STRING and _derived_packages.erase(id):
			removed += 1
	return removed


static func _resolve(id: Variant, table: Dictionary, format: String, field: String, step: String) -> Dictionary:
	if typeof(id) == TYPE_STRING and _derived_packages.has(id) and (_derived_packages[id] as Dictionary).get("format") == format:
		return R.ok((_derived_packages[id] as Dictionary).duplicate(true))
	if typeof(id) != TYPE_STRING or not table.has(id):
		return R.fail(R.DEPENDENCY_MISSING, "Package %s is not installed.", field, step, [str(id)])
	var key: String = id
	if not _cache.has(key):
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(str(table[key]))
		var json := JSON.new()
		var problem := "the package file cannot be read"
		if not bytes.is_empty() and json.parse(bytes.get_string_from_utf8()) == OK:
			problem = _package_problem(json.data, key, format)
		if not problem.is_empty():
			return R.fail(R.DEPENDENCY_MISSING, "Package %s cannot be used: %s", field, step, [key, problem])
		_cache[key] = json.data
	return R.ok((_cache[key] as Dictionary).duplicate(true))


static func _package_problem(data: Variant, id: String, format: String) -> String:
	if typeof(data) != TYPE_DICTIONARY:
		return "the package is not an object"
	var package: Dictionary = data
	if package.get("format") != format or package.get("id") != id or package.get("qualification") != QUALIFICATION:
		return "format, id or qualification do not match"
	if package.has("layout") and package.get("layout") not in ["tractor", "pusher"]:
		return "the layout is not tractor or pusher"
	if package.has("jet"):
		if not is_jet(package):
			return "the jet member is not an object"
		for key: String in JET_KEYS:
			if not (package.jet as Dictionary).has(key):
				return "the jet member lacks " + key
			if not ((package.jet as Dictionary)[key] is Dictionary and typeof(package.jet[key].get("value")) in [TYPE_INT, TYPE_FLOAT]):
				return "the jet member's %s is not a quantity" % key
		var jet: Dictionary = package.jet
		# The loader's turbine bounds: rpm ≤ 300 000, thrust ≤ 5000 N, mass flow (thrust/efflux) ≤ 20 kg/s and
		# spool rate ≤ 10⁶ rpm/s; a package outside them would only fail at the flight loader.
		var thrust := float(jet.static_thrust.value)
		var efflux := float(jet.efflux_speed.value)
		var spool := float(jet.spool_time.value)
		var idle := float(jet.idle_rpm.value)
		var top := float(jet.max_rpm.value)
		if not (thrust > 0.0 and thrust <= JET_MAX_THRUST_N and efflux > 0.0 and thrust / efflux <= JET_MAX_MASS_FLOW
				and spool > 0.0 and idle >= 1000.0 and top > idle and top <= JET_MAX_RPM and (top - idle) / spool <= JET_MAX_SPOOL_RATE
				and float(jet.idle_thrust.value) >= 0.0 and float(jet.idle_thrust.value) < thrust):
			return "the jet member's values are out of range"
	if format == POWER_FORMAT:
		if typeof(package.get("hardware")) != TYPE_ARRAY:
			return "the hardware list is missing"
		for entry: Variant in package.hardware:
			if typeof(entry) != TYPE_DICTIONARY or typeof(entry.get("id")) != TYPE_STRING or not HARDWARE_MOUNTS.has(entry.get("mount")):
				return "a hardware item lacks its ID or mount"
	return _quantity_problem(package, "")


## Every {value, …} object in a package carries unit, kind and a non-blank source, and finite numbers.
static func _quantity_problem(node: Variant, path: String) -> String:
	if typeof(node) == TYPE_ARRAY:
		var items: Array = node
		for index: int in items.size():
			var found := _quantity_problem(items[index], "%s/%d" % [path, index])
			if not found.is_empty():
				return found
		return ""
	if typeof(node) != TYPE_DICTIONARY:
		return ""
	var object: Dictionary = node
	if object.has("value"):
		if typeof(object.get("unit")) != TYPE_STRING or not QUANTITY_KINDS.has(object.get("kind")) \
				or typeof(object.get("source")) != TYPE_STRING or str(object.source).strip_edges().is_empty():
			return path + " lacks unit, kind or source"
		if not _finite_tree(object.value):
			return path + " has a value that is not a finite number"
		return ""
	for key: Variant in object:
		var found := _quantity_problem(object[key], path + "/" + str(key))
		if not found.is_empty():
			return found
	return ""


static func _finite_tree(node: Variant) -> bool:
	if typeof(node) == TYPE_ARRAY:
		for item: Variant in (node as Array):
			if not _finite_tree(item):
				return false
		return not (node as Array).is_empty()
	return typeof(node) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(node))


static func number(package: Dictionary, group: String, name: String) -> float:
	return float(package[group][name].value)


## Helmbold lift slope of a finite wing with a 2π section: 2π·AR / (2 + √(AR² + 4)), per radian.
static func helmbold(aspect_ratio: float) -> float:
	return TAU * aspect_ratio / (2.0 + sqrt(aspect_ratio * aspect_ratio + 4.0))


## Wing downwash gradient at the tail: factor × the far-wake value 2·a_w/(π·AR).
static func downwash_gradient(wing_slope: float, aspect_ratio: float, factor: float) -> float:
	return factor * 2.0 * wing_slope / (PI * aspect_ratio)


## Pitch-rate lift of the tail: 2·a_free·(S_t/S)·(l_t/c).
static func tail_lift_rate(free_slope: float, area_ratio: float, arm_over_chord: float) -> float:
	return 2.0 * free_slope * area_ratio * arm_over_chord


## Pitch damping of the tail: −2·a_free·(S_t/S)·(l_t/c)².
static func tail_pitch_damping(free_slope: float, area_ratio: float, arm_over_chord: float) -> float:
	return -2.0 * free_slope * area_ratio * arm_over_chord * arm_over_chord


## IAQ-04 lateral-directional terms (see airframe_aero): the fin-efficiency factor is kept in this range, and
## the loader accepts body_cn_beta in [−0.5, 0]. The Stik donor's own high-wing interference share of its
## wing-body Clβ (D10-R5: z_w −0.0595 m, D 0.1126 m, AR 5, b 1.524 m).
const FIN_FACTOR_RANGE := [0.4, 1.1]
## Jet power packages (IAQ T4): required members and the record's table sampling.
const JET_KEYS := ["static_thrust", "idle_thrust", "efflux_speed", "idle_rpm", "max_rpm", "spool_time"]
const JET_MAX_THRUST_N := 5000.0
const JET_MAX_MASS_FLOW := 20.0
const JET_MAX_RPM := 300000.0
const JET_MAX_SPOOL_RATE := 1.0e6
const JET_TABLE_ROWS := 5
const JET_THROTTLE_POINTS: Array[float] = [0.0, 0.05, 0.1, 0.15, 0.5, 1.0]
const JET_MIN_MASS_FLOW := 1.0e-4
const JET_GOVERNOR_TAU_S := 0.05
const JET_ROTOR_INERTIA := 1.0e-5
const BODY_CN_BETA_RANGE := [-0.5, 0.0]
## The loader's range for aero.surfaces.wing_body_cl_beta.
const WING_BODY_CL_BETA_RANGE := [-0.3, 0.1]
const STIK_DONOR_PATH := "app/data/aircraft/synthetic_stik_electric_4s_battery.json"
const STIK_DONOR_HIGH_WING_CL_BETA := -0.01549


## Yaw damping: fin −2·(l_v/b)·Cnb_fin plus the wing profile term −CD0/3.
static func yaw_damping(arm_over_span: float, fin_cnb: float, profile_drag: float) -> float:
	return -2.0 * arm_over_span * fin_cnb - profile_drag / 3.0


## Strip-theory planform factor of roll damping for straight taper λ, 1 for a rectangular wing.
static func roll_damping_taper(taper: float) -> float:
	return (1.0 + 3.0 * taper) / (2.0 * (1.0 + taper))


## Geometric dihedral's share of Clβ (per rad of sideslip) for full-span dihedral Γ (rad) on a wing of
## straight taper λ: strip theory, −(a_w·Γ/6)·(1 + 2λ)/(1 + λ) (−a_w·Γ/4 for a rectangular wing),
## times `factor`, the share of that value left by the induced flow of an antisymmetric loading.
static func dihedral_effect(wing_slope: float, taper: float, dihedral_rad: float, factor: float) -> float:
	return -factor * wing_slope * dihedral_rad * (1.0 + 2.0 * taper) / (6.0 * (1.0 + taper))


## The player's lifting geometry as plain numbers, or {} when a value is missing or not usable.
## `definition` may be incomplete: every access is checked. `dihedral_deg` is NAN while it is missing:
## the mass proposal does not need it, the aerodynamic derivation does.
static func geometry(definition: Dictionary) -> Dictionary:
	var wing: Dictionary = _dictionary(definition.get("wing"))
	var tail: Dictionary = _dictionary(definition.get("horizontal_tail"))
	var fin: Dictionary = _dictionary(definition.get("vertical_tail"))
	var out := {
		span = positive(wing.get("span")), root_chord = positive(wing.get("root_chord")),
		tip_chord = positive(wing.get("tip_chord")),
		h_span = positive(tail.get("span")), h_chord = positive(tail.get("chord")),
		v_height = positive(fin.get("height")), v_chord = positive(fin.get("chord")),
	}
	for key: Variant in out:
		if is_nan(float(out[key])):
			return {}
	var h_position := vector(tail.get("position"), 3)
	var v_position := vector(fin.get("position"), 3)
	if h_position.is_empty() or v_position.is_empty() or out.tip_chord > out.root_chord:
		return {}
	out.h_position = h_position
	out.v_position = v_position
	out.dihedral_deg = finite(wing.get("dihedral_deg"))
	# The box fuselage, for the directional and wing-body terms (IAQ-04): optional, absent while incomplete.
	var fuselage: Dictionary = _dictionary(definition.get("fuselage"))
	var body := {length = finite(fuselage.get("tail_x")) - finite(fuselage.get("nose_x")), width = positive(fuselage.get("width")),
		height = positive(fuselage.get("height")), center_z = finite(fuselage.get("center_z"))}
	if is_finite(float(body.length)) and float(body.length) > 0.0 and is_finite(float(body.width)) \
			and is_finite(float(body.height)) and is_finite(float(body.center_z)):
		out.fuselage = body
	return out


## Aerodynamic derivation for one geometry (see geometry()). Returns {} when the tail does not sit aft of
## the wing's quarter chord or the dihedral is missing. All coefficient values are estimates; `quantities`
## carries kind and source.
static func airframe_aero(package: Dictionary, shape: Dictionary) -> Dictionary:
	if shape.is_empty() or is_nan(float(shape.get("dihedral_deg", NAN))):
		return {}
	var span: float = shape.span
	var root: float = shape.root_chord
	var tip: float = shape.tip_chord
	var area: float = span * (root + tip) / 2.0
	var chord: float = area / span
	var aspect: float = span * span / area
	var taper: float = tip / root
	var mac: float = 2.0 / 3.0 * root * (1.0 + taper + taper * taper) / (1.0 + taper)
	# Package assumption: unswept quarter-chord line; the reference point stays at the wing root, z = 0
	# (the rise of a dihedral wing's panels above the root is neglected).
	var arp := PackedFloat64Array([0.25 * root, 0.0, 0.0])
	var h_position: PackedFloat64Array = shape.h_position
	var v_position: PackedFloat64Array = shape.v_position
	var h_area: float = float(shape.h_span) * float(shape.h_chord)
	var v_area: float = float(shape.v_height) * float(shape.v_chord)
	var h_aspect: float = float(shape.h_span) / float(shape.h_chord)
	var v_aspect: float = float(shape.v_height) / float(shape.v_chord)
	var h_point := PackedFloat64Array([h_position[0] + 0.25 * float(shape.h_chord), 0.0, h_position[2]])
	var v_point := PackedFloat64Array([v_position[0] + 0.25 * float(shape.v_chord), 0.0,
		v_position[2] + 0.5 * float(shape.v_height)])
	var h_arm: float = h_point[0] - arp[0]
	var v_arm: float = v_point[0] - arp[0]
	if h_arm <= 0.0 or v_arm <= 0.0:
		return {}

	var efficiency := number(package, "tail", "efficiency")
	var wing_slope := helmbold(aspect)
	var gradient := downwash_gradient(wing_slope, aspect, number(package, "wing", "downwash_factor"))
	var keep := 1.0 - gradient
	var h_free := efficiency * helmbold(h_aspect)
	var h_slope := h_free * keep
	var v_slope := efficiency * helmbold(number(package, "tail", "fin_aspect_ratio_factor") * v_aspect)
	var h_ratio := h_area / area
	var tail_share := h_ratio * h_slope
	var cla := wing_slope + tail_share
	var cma := -tail_share * h_arm / chord
	var elevator_tau := number(package, "tail", "elevator_effectiveness")
	var clde := h_free * elevator_tau * h_ratio
	var cmde := -clde * h_arm / chord
	var wing_cl0 := number(package, "wing", "zero_alpha_lift")
	# Tail lift at zero body angle of attack is h_slope × incidence: geometric incidence less the wing's zero-alpha downwash.
	var incidence := (number(package, "tail", "geometric_incidence") - gradient * wing_cl0 / wing_slope) / keep
	var cl0 := wing_cl0 + tail_share * incidence
	var section_moment := number(package, "wing", "section_moment")
	var cm0 := section_moment * mac / chord + cma * incidence
	var cd0 := number(package, "wing", "profile_drag")
	var body_drag: Variant = package.wing.get("body_drag_area")
	if body_drag != null:
		if not body_drag is Dictionary:
			return {}
		var drag_value: Variant = body_drag.get("value")
		if typeof(drag_value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(drag_value)) or float(drag_value) < 0.0:
			return {}
		# A source-derived dimensional body drag area is independent of the chosen wing reference.
		# Evaluate against the current wing, including fitted/stacked geometry or a later player edit.
		cd0 += float(drag_value) / area
	var k_induced := 1.0 / (PI * number(package, "wing", "oswald_efficiency") * aspect)
	var clq := tail_lift_rate(h_free, h_ratio, h_arm / chord)
	var cmq := tail_pitch_damping(h_free, h_ratio, h_arm / chord)
	# The four fin relations in the loader's own operation order (aircraft_data.gd _surfaces).
	var rudder_tau := number(package, "tail", "rudder_effectiveness")
	var fin_height: float = v_point[2] - arp[2]
	var cy_rudder: float = v_slope * v_area / area * rudder_tau
	var cnb: float = v_slope * v_area / area * v_arm / span
	var body_cy := number(package, "body", "side_force")
	var donor: Dictionary = package.donor
	# Wing-body Clβ: the donor's term belongs to the donor's wing at the donor's dihedral; the player's
	# wing and dihedral move it by the difference of the same dihedral relation (zero for the donor's own).
	var dihedral_factor := number(package, "wing", "dihedral_factor")
	var dihedral_term := dihedral_effect(wing_slope, taper, deg_to_rad(float(shape.dihedral_deg)), dihedral_factor)
	var donor_dihedral_term := dihedral_effect(helmbold(float(donor.aspect_ratio)), float(donor.taper_ratio),
		deg_to_rad(float(donor.dihedral_deg)), dihedral_factor)
	var wing_body_cl := number(package, "body", "dihedral_effect") + (dihedral_term - donor_dihedral_term)
	# IAQ-04: the directional and wing-body terms of the Stik study (D10-R2/R5, research/flight-dynamics/
	# stik-lateral-directional/directional_prediction.py) on the player's box fuselage: the DATCOM fin efficiency
	# η_v(1 + dσ/dβ) relative to the package's η already in the fin slope, Raymer's fuselage Cnβ, and the
	# high-wing interference rescaled from the donor's. Without them the isolated fin overstates Cnβ and the
	# spiral mode diverges on most Creator aircraft.
	var body_cn := 0.0
	var high_wing := 0.0
	var fin_factor := 1.0
	var clamped := PackedStringArray()
	if shape.has("fuselage"):
		var body: Dictionary = shape.fuselage
		var z_w: float = float(body.center_z) # the wing root (z = 0) below the fuselage centreline, positive down
		# Wing position within the fuselage depth; a wing far outside the box is treated as at its edge.
		var position := clampf(z_w / float(body.height), -1.0, 1.0)
		if position != z_w / float(body.height):
			clamped.append("wing height")
		var total := 0.724 + 3.06 * (v_area / area) / 2.0 + 0.4 * position + 0.009 * aspect
		fin_factor = clampf(total / efficiency, FIN_FACTOR_RANGE[0], FIN_FACTOR_RANGE[1])
		if fin_factor != total / efficiency:
			clamped.append("fin efficiency")
		# The box volume times the package's fuselage taper share (a shell-mass share, reused as the volume share).
		var volume: float = float(body.length) * float(body.width) * float(body.height) \
			* number(package, "mass_proposal", "fuselage_taper_factor")
		var raymer := -1.3 * volume / (area * span) * sqrt(clampf(float(body.height) / float(body.width), 0.25, 4.0))
		var unbounded := (fin_factor - 1.0) * cnb + raymer
		body_cn = clampf(unbounded, BODY_CN_BETA_RANGE[0], BODY_CN_BETA_RANGE[1])
		if body_cn != unbounded:
			clamped.append("body Cnβ")
		if str(donor.path) == STIK_DONOR_PATH:
			var d_eq := sqrt(4.0 * float(body.width) * float(body.height) / PI)
			high_wing = 1.2 * sqrt(aspect) * (z_w / span) * (2.0 * d_eq / span) - STIK_DONOR_HIGH_WING_CL_BETA
			var bounded := clampf(wing_body_cl + high_wing, WING_BODY_CL_BETA_RANGE[0], WING_BODY_CL_BETA_RANGE[1])
			if bounded != wing_body_cl + high_wing:
				clamped.append("wing-body Clβ")
			wing_body_cl = bounded
	var clamp_note := "" if clamped.is_empty() else "; limited to the loader's range: " + ", ".join(clamped)
	var clp := number(package, "wing", "roll_damping_reference") * wing_slope / helmbold(float(donor.aspect_ratio)) \
		* roll_damping_taper(taper) / roll_damping_taper(float(donor.taper_ratio))
	var borrowed: Dictionary = package.borrowed_coefficients
	var roll_power: float = absf(float(borrowed.Clda_right.value))

	var quantities := {}
	for name: String in borrowed:
		quantities[name] = _copy_quantity(borrowed[name])
	quantities.CD0 = _copy_quantity(package.wing.profile_drag) if body_drag == null else _quantity(
		_derived(cd0, "source section CD0 + source body drag area / current wing reference area"), "1")
	quantities.CL_minD = _copy_quantity(package.wing.minimum_drag_lift)
	quantities.CL0 = _derived(cl0, "wing zero-alpha lift + (S_h/S)·a_h·i_h, i_h the tail's effective incidence under the wing's zero-alpha downwash")
	quantities.CLa = _derived(cla, "a_w + a_h·S_h/S; a_w = Helmbold(AR) = 2π·AR/(2 + √(AR² + 4)), a_h = η·Helmbold(AR_h)·(1 − dε/dα)")
	quantities.CLq = _derived(clq, "2·a_h,free·(S_h/S)·(l_h/c), arm from the aero reference point")
	quantities.CLde = _derived(clde, "a_h,free·τ_e·S_h/S")
	quantities.k_induced = _derived(k_induced, "1/(π·e·AR) with the package's Oswald factor")
	quantities.CYb = _derived(-v_slope * v_area / area + body_cy, "−a_v·S_v/S + the package's body side force")
	quantities.CYdr = _derived(cy_rudder, "a_v·S_v/S·τ_r")
	quantities.Clb = _derived(-v_slope * v_area / area * fin_height / span + wing_body_cl,
		"−a_v·(S_v/S)·(z_v − z_ARP)/b + the wing-body term declared as aero.surfaces.wing_body_cl_beta (donor value moved by the player's wing dihedral)")
	quantities.Clp = _derived(clp, "donor Clp × Helmbold(AR)/Helmbold(5) × strip-theory taper factor (1 + 3λ)/(2·(1 + λ))")
	quantities.Cldr = _derived(cy_rudder * fin_height / span, "CYdr·(z_v − z_ARP)/b")
	quantities.Cm0 = _derived(cm0, "wing section moment × MAC/c + Cma × tail effective incidence")
	quantities.Cma = _derived(cma, "−a_h·(S_h/S)·(l_h/c) about the wing quarter chord; fuselage and propeller contributions neglected")
	quantities.Cmq = _derived(cmq, "−2·a_h,free·(S_h/S)·(l_h/c)², arm from the aero reference point")
	quantities.Cmde = _derived(cmde, "−CLde·l_h/c")
	quantities.Cnb = _derived(cnb + body_cn, "a_v·(S_v/S)·(l_v/b) + body_cn_beta: (fin efficiency %s − 1)·fin term + Raymer fuselage term (DATCOM η_v(1 + dσ/dβ) over the package η, Raymer eq. 16.50 on the box fuselage)%s" % [String.num(fin_factor, 3), clamp_note])
	quantities.Cnr = _derived(yaw_damping(v_arm / span, cnb, cd0), "−2·(l_v/b)·Cnb_fin − CD0/3, Cnb_fin the isolated fin's term (the fin efficiency and fuselage terms of Cnb are not applied, as in the Stik study)")
	quantities.Cndr = _derived(-cy_rudder * v_arm / span, "−CYdr·l_v/b")
	return {
		wing_area = area, mean_chord = chord, aspect_ratio = aspect, taper_ratio = taper,
		mean_aerodynamic_chord = mac, arp = arp,
		wing_slope = wing_slope, downwash_gradient = gradient, tail_free_slope = h_free, tail_slope = h_slope,
		fin_slope = v_slope, tail_area = h_area, fin_area = v_area, tail_point = h_point, fin_point = v_point,
		tail_arm = h_arm, fin_arm = v_arm, tail_aspect_ratio = h_aspect, fin_aspect_ratio = v_aspect,
		tail_volume_h = h_ratio * h_arm / chord, tail_volume_v = v_area / area * v_arm / span,
		tail_incidence = incidence, tail_control_effectiveness = elevator_tau / keep,
		wing_aileron_effectiveness = roll_power / (0.125 * cla),
		wing_body_cl_beta = _derived(wing_body_cl,
			"donor wing-body term at the donor's %s deg dihedral + κ·[D(player wing, player dihedral) − D(donor wing, donor dihedral)], D = −a_w·Γ·(1 + 2λ)/(6·(1 + λ)) (strip theory), κ the package's antisymmetric-loading factor; plus the high-wing interference 1.2·√AR·(z_w/b)·(2D/b) of the player's box fuselage less the donor's (%s)" % [
				str(donor.dihedral_deg), String.num(high_wing, 4)]),
		body_cn_beta = _derived(body_cn, "(fin efficiency %s − 1) × the isolated fin's Cnβ + Raymer −1.3·Vol/(S·b)·√(h/w) on the box fuselage (Vol × the package's fuselage taper factor); the Stik study's terms (D10-R2), with the DATCOM factor divided by the package η already in the fin slope%s" % [String.num(fin_factor, 3), clamp_note]),
		dihedral_term = dihedral_term,
		neutral_point_x = arp[0] - cma / cla * chord,
		flat_plate_drag = number(package, "envelope", "flat_plate_base")
			+ number(package, "envelope", "flat_plate_per_aspect_ratio") * aspect,
		lift_rate_reference = _derived(clq * gradient, "CLq × dε/dα; reference only, the runtime carries the downwash lag as a state"),
		quantities = quantities,
	}


## The record's `aero` node for a derivation from airframe_aero().
static func aero_block(package: Dictionary, aero: Dictionary) -> Dictionary:
	var coefficients := {}
	for name: String in AircraftData.COEFFICIENTS:
		if name == "CLadot":
			continue
		coefficients[name] = _quantity(aero.quantities[name], str(AircraftData.COEFFICIENTS[name][0]))
	var tail: Dictionary = package.tail
	var envelope: Dictionary = package.envelope
	var block := {
		source = "Aircraft Creator package %s: closed forms on the player's geometry plus coefficients borrowed from %s (OpenFlightSim UltraStick25e set); estimated, not calibrated against a real aircraft" % [package.id, package.donor.path],
		conventions = {
			alpha_beta = "rad",
			rates = "p_hat = p·b/(2V), q_hat = q·c/(2V), r_hat = r·b/(2V)",
			elevator = "per radian, positive = trailing edge DOWN (dCm/dElev < 0)",
			aileron = "per radian per surface, positive = trailing edge DOWN; right and left listed separately",
			rudder = "per radian, positive = trailing edge LEFT (dCn/dRud < 0)",
			drag = "CD = CD0 + k·(CL - CL_minD)² + sum |dCD/dδ·δ|",
			axes = "lift, drag, side force in wind axes; roll, pitch, yaw moments in body axes about the aero reference point",
		},
		coefficients = coefficients,
		reference_coefficients = {CLadot = _quantity(aero.lift_rate_reference, "1/rad")},
		envelope = {
			CL_max = _copy_quantity(envelope.CL_max),
			CL_min = _copy_quantity(envelope.CL_min),
			stall_blend_width = _copy_quantity(envelope.stall_blend_width),
			CD90 = _quantity(_derived(aero.flat_plate_drag, "Viterna 1.11 + 0.018·AR (NASA CR-1983)"), "1"),
			sideslip_blend = _copy_quantity(envelope.sideslip_blend),
		},
		surfaces = {
			wing_aileron_effectiveness = _quantity(_derived(aero.wing_aileron_effectiveness,
				"|Clda_right|/(0.125·CLa), the donor's strip rule"), "1"),
			wing_section_cm_ac = _copy_quantity(package.wing.section_moment),
			body_cy_beta = _copy_quantity(package.body.side_force),
			body_cn_beta = _quantity(aero.body_cn_beta, "1/rad"),
			wing_body_cl_beta = _quantity(aero.wing_body_cl_beta, "1/rad"),
			attached_limit = _copy_quantity(tail.attached_limit),
			tail_local_limit = _copy_quantity(tail.local_limit),
			tail_stall_end = _copy_quantity(tail.stall_end),
			tail_CD0 = _copy_quantity(tail.profile_drag),
			tail_k = _copy_quantity(tail.induced_drag),
			tail_CD90 = _copy_quantity(tail.flat_plate_drag),
			horizontal = {
				area = _quantity(_derived(aero.tail_area, "span × chord of the player's horizontal tail"), "m2"),
				position = _quantity(_derived(Array(aero.tail_point as PackedFloat64Array),
					"quarter chord of the player's horizontal tail at the centreline"), "m"),
				lift_slope = _quantity(_derived(aero.tail_slope, "η·Helmbold(AR_h)·(1 − dε/dα), the effective downwash-reduced slope"), "1/rad"),
				control_effectiveness = _quantity(_derived(aero.tail_control_effectiveness, "τ_e/(1 − dε/dα) = Cmde/Cma"), "1"),
				incidence = _quantity(_derived(aero.tail_incidence,
					"(geometric incidence − dε/dα·CL0_wing/a_w)/(1 − dε/dα): effective incidence of a tail parallel to the wing chord"), "rad"),
				downwash_gradient = _quantity(_derived(aero.downwash_gradient,
					"package factor × 2·a_w/(π·AR), the factor anchored on the donor's vortex-lattice value"), "1"),
			},
			vertical = {
				area = _quantity(_derived(aero.fin_area, "height × chord of the player's vertical tail"), "m2"),
				position = _quantity(_derived(Array(aero.fin_point as PackedFloat64Array),
					"quarter chord at mid height of the player's vertical tail"), "m"),
				lift_slope = _quantity(_derived(aero.fin_slope, "η·Helmbold(2·h²/S_v), fuselage as a reflection plane"), "1/rad"),
				control_effectiveness = _copy_quantity(tail.rudder_effectiveness),
				incidence = _copy_quantity(tail.fin_incidence),
			},
		},
	}
	# Optional member (IAQ T6): only a package declaring ground_effect emits it; other records are unchanged.
	if package.get("ground_effect") is Dictionary:
		var ground := {}
		for key: String in ["induced_coefficient", "induced_exponent", "downwash_coefficient", "downwash_exponent"]:
			ground[key] = _copy_quantity(package.ground_effect[key])
		block["ground_effect"] = ground
	return block


## The record's `propulsion` node. `offset` is hub minus inventory CG, `angles` [down, right] degrees.
static func propulsion_block(package: Dictionary, propulsion_id: String, initial_soc: float,
		offset: PackedFloat64Array, angles: PackedFloat64Array) -> Dictionary:
	if is_jet(package):
		return _jet_block(package, propulsion_id, offset, angles)
	var motor: Dictionary = package.motor
	var battery: Dictionary = package.battery
	var propeller: Dictionary = package.propeller
	var knots := []
	for row: Array in battery.ocv_points.value:
		knots.append({
			soc = {value = float(row[0]), unit = "1", kind = battery.ocv_points.kind, source = battery.ocv_points.source},
			voltage = {value = float(row[1]), unit = "V", kind = battery.ocv_points.kind, source = battery.ocv_points.source},
		})
	return {
		kind = "electric_prop",
		id = propulsion_id,
		motor = {
			kv_rpm_per_volt = _copy_quantity(motor.kv_rpm_per_volt),
			resistance_ohm = _copy_quantity(motor.resistance_ohm),
			resistance_scope = "motor_winding_equivalent",
			no_load_current_a = _copy_quantity(motor.no_load_current_a),
			no_load_context = {
				voltage_v = _copy_quantity(motor.no_load_voltage_v),
				rpm = _copy_quantity(motor.no_load_rpm),
				temperature_c = _copy_quantity(motor.no_load_temperature_c),
			},
		},
		battery = {
			kind = "ocv_resistance",
			capacity_ah = _copy_quantity(battery.capacity_ah),
			resistance_ohm = _copy_quantity(battery.resistance_ohm),
			auxiliary_current_a = _copy_quantity(battery.auxiliary_current_a),
			initial_soc = {value = initial_soc, unit = "1", kind = "manual",
				source = "Aircraft Creator definition: battery/initial_soc (player-entered)"},
			ocv_points = knots,
		},
		esc = {kind = "ideal_motoring", command_mapping = "identity"},
		propeller = {
			name = str(propeller.name),
			diameter = _copy_quantity(propeller.diameter),
			thrust_line_offset = {value = Array(offset), unit = "m", kind = DERIVED,
				source = "equipment/hub_position minus the inventory centre of mass, [aft, right, up]"},
			rotating_inertia = _copy_quantity(propeller.rotating_inertia),
			ct_table = _copy_quantity(propeller.ct_table),
			cp_table = _copy_quantity(propeller.cp_table),
			thrust_angles = {value = Array(angles), unit = "deg", kind = "manual",
				source = "Aircraft Creator definition: equipment/thrust_angles_deg [down, right] (player-entered)"},
		},
	}


## The record's `turbine` propulsion for a jet package. Thrust is linear in the fan speed between the idle
## and full thrust (as the source declares it), the mass flow is thrust/efflux speed (so the net thrust falls
## by ṁ·u, the momentum law), the throttle maps linearly to the fan speed with the source's cubic shaping below
## 15 %, and the spool slews the full range in the source's spool time. The intake sits at the CG station on
## the thrust line's height (the source gives no intake position). No fuel is consumed: an electric fan's
## battery is not modelled on this path.
static func _jet_block(package: Dictionary, propulsion_id: String, offset: PackedFloat64Array,
		angles: PackedFloat64Array) -> Dictionary:
	var jet: Dictionary = package.jet
	var idle := float(jet.idle_rpm.value)
	var top := float(jet.max_rpm.value)
	var thrust_max := float(jet.static_thrust.value)
	var thrust_idle := float(jet.idle_thrust.value)
	var efflux := float(jet.efflux_speed.value)
	var rate := (top - idle) / float(jet.spool_time.value)
	var thrust_rows: Array = []
	var flow_rows: Array = []
	var fuel_rows: Array = []
	for step: int in JET_TABLE_ROWS:
		var share := float(step) / float(JET_TABLE_ROWS - 1)
		var rpm := idle + share * (top - idle)
		var thrust := thrust_idle + share * (thrust_max - thrust_idle)
		thrust_rows.append([rpm, thrust])
		flow_rows.append([rpm, maxf(JET_MIN_MASS_FLOW, thrust / efflux)])
		fuel_rows.append([rpm, 0.0])
	var throttle_rows: Array = []
	for command: float in JET_THROTTLE_POINTS:
		var shaped := command if command >= 0.15 else 0.15 * pow(command / 0.15, 3)
		throttle_rows.append([command, idle + shaped * (top - idle)])
	var source := str(jet.static_thrust.source)
	return {
		kind = "turbine",
		id = propulsion_id,
		description = "Aircraft Creator jet: %s N static thrust, %s m/s efflux (momentum law with ram drag), %s s spool; %s" % [
			String.num(thrust_max, 1), String.num(efflux, 0), String.num(float(jet.spool_time.value), 2), source],
		engine = {
			name = str(jet.get("name", "Ducted fan")),
			idle_rpm = _copy_quantity(jet.idle_rpm),
			max_rpm = _copy_quantity(jet.max_rpm),
			static_thrust = {value = thrust_rows, unit = "rpm, N", kind = "derived",
				source = "Linear from the idle to the full static thrust over the fan speed: " + source},
			mass_flow = {value = flow_rows, unit = "rpm, kg/s", kind = "derived",
				source = "Static thrust / efflux speed %s m/s: net thrust T − ṁ·u, %s" % [String.num(efflux, 0), str(jet.efflux_speed.source)]},
			fuel_flow = {value = fuel_rows, unit = "rpm, kg/s", kind = "estimated",
				source = "No fuel: the energy of an electric fan is not modelled on the jet path"},
			throttle_map = {value = throttle_rows, unit = "1, rpm", kind = "derived",
				source = "Linear throttle to fan speed with a cubic shaping below 15 % (as the source)"},
			accel_limit = {value = [[idle, rate], [top, rate]], unit = "rpm, rpm/s", kind = "derived",
				source = "The full speed range in the spool time: " + str(jet.spool_time.source)},
			decel_limit = {value = [[idle, rate], [top, rate]], unit = "rpm, rpm/s", kind = "derived",
				source = "The full speed range in the spool time: " + str(jet.spool_time.source)},
			installed_factor = {value = 1.0, unit = "1", kind = "estimated", source = "The source's thrust is the installed thrust"},
			governor_tau = {value = JET_GOVERNOR_TAU_S, unit = "s", kind = "estimated", source = "Short speed-controller lag; the spool limit dominates"},
			rotor_inertia = {value = JET_ROTOR_INERTIA, unit = "kg·m2", kind = "estimated", source = "Small fan rotor: negligible gyroscopic coupling"},
			rotor_sense = {value = 1, unit = "1", kind = "estimated", source = "Fan rotation sense not declared by the source"},
		},
		thrust_line_offset = {value = Array(offset), unit = "m", kind = DERIVED,
			source = "equipment/hub_position (the fan's thrust point) minus the inventory centre of mass, [aft, right, up]"},
		intake_offset = {value = [0.0, 0.0, offset[2]], unit = "m", kind = "estimated",
			source = "Intake at the CG station on the thrust line's height: the source declares no intake position"},
		thrust_angles = {value = Array(angles), unit = "deg", kind = "manual",
			source = "Aircraft Creator definition: equipment/thrust_angles_deg [down, right] (player-entered)"},
	}


## Static full-throttle operating point of the power package at `initial_soc` in standard air, solved by
## the runtime's own electric torque balance. Returns {ok, thrust_n, rpm}.
static func static_thrust(package: Dictionary, initial_soc: float) -> Dictionary:
	if is_jet(package):
		return {ok = true, thrust_n = float(package.jet.static_thrust.value), rpm = float(package.jet.max_rpm.value)}
	var key := "%s|%s" % [package.id, var_to_str(initial_soc)]
	if not _thrust_cache.has(key):
		if _thrust_cache.size() >= 64:
			_thrust_cache.clear() # a charge slider visits many values; keep the cache small
		var result := {ok = false}
		var model := _runtime_propulsion(package, initial_soc)
		var point: Dictionary = Propulsion.steady_operating_point(1.0, 0.0, model, AIR_DENSITY)
		if point.get("ok", false):
			var loads: PackedFloat64Array = Propulsion.thrust_torque(PackedFloat64Array([0.0, 0.0, 0.0]),
				float(point.rpm), model, AIR_DENSITY)
			if loads.size() == 3 and is_finite(loads[0]):
				result = {ok = true, thrust_n = loads[0], rpm = float(point.rpm)}
		_thrust_cache[key] = result
	return (_thrust_cache[key] as Dictionary).duplicate()


## The normalized propulsion model the loader derives from propulsion_block(), without an installation:
## axial shaft at the reference point. Only for the static read-out above.
static func _runtime_propulsion(package: Dictionary, initial_soc: float) -> Dictionary:
	var motor: Dictionary = package.motor
	var battery: Dictionary = package.battery
	var propeller: Dictionary = package.propeller
	var knots := PackedFloat64Array()
	var top := 0.0
	for row: Array in battery.ocv_points.value:
		knots.append(float(row[0]))
		knots.append(float(row[1]))
		top = maxf(top, float(row[1]))
	return {
		kind = "electric_prop",
		motor = {kv_rpm_per_volt = float(motor.kv_rpm_per_volt.value), resistance_ohm = float(motor.resistance_ohm.value),
			no_load_current_a = float(motor.no_load_current_a.value)},
		battery = {"kind": "ocv_resistance", "capacity_ah": float(battery.capacity_ah.value),
			"resistance_ohm": float(battery.resistance_ohm.value),
			"auxiliary_current_a": float(battery.auxiliary_current_a.value),
			"initial_soc": initial_soc, "ocv_points": knots},
		esc = {kind = "ideal_motoring", command_mapping = "identity"},
		max_rpm = float(motor.kv_rpm_per_volt.value) * top,
		diameter = float(propeller.diameter.value),
		offset = PackedFloat64Array([0.0, 0.0, 0.0]),
		rotor_inertia = float(propeller.rotating_inertia.value),
		ct = _flat_table(propeller.ct_table.value),
		cp = _flat_table(propeller.cp_table.value),
		axis = PackedFloat64Array([1.0, 0.0, 0.0]),
	}


static func _flat_table(rows: Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for row: Array in rows:
		out.append(float(row[0]))
		out.append(float(row[1]))
	return out


## The power package's inventory items, each exactly once: [{id, mass, position, size, …quantities}].
## `mounts` gives hub, battery and esc positions; the motor sits a package distance behind the hub.
static func hardware_items(package: Dictionary, mounts: Dictionary) -> Array:
	var hub: PackedFloat64Array = mounts.hub
	var places := {
		hub = hub,
		motor = PackedFloat64Array([hub[0] + aft_sign(package) * number(package, "installation", "motor_behind_hub"), hub[1], hub[2]]),
		esc = mounts.esc,
		battery = mounts.battery,
	}
	var sources := {
		hub = "Aircraft Creator definition: equipment/hub_position (player-entered)",
		motor = "equipment/hub_position plus the package's motor distance behind the hub",
		esc = "Aircraft Creator definition: equipment/esc_position (player-entered)",
		battery = "Aircraft Creator definition: equipment/battery_position (player-entered)",
	}
	var out := []
	for entry: Dictionary in package.hardware:
		var mount: String = entry.mount
		var item := {
			id = str(entry.id),
			mount = mount,
			mass = float(entry.mass.value),
			position = places[mount],
			size = PackedFloat64Array([float(entry.size.value[0]), float(entry.size.value[1]), float(entry.size.value[2])]),
			mass_quantity = _copy_quantity(entry.mass),
			size_quantity = _copy_quantity(entry.size),
			position_kind = DERIVED if mount == "motor" else "manual",
			position_source = str(sources[mount]),
		}
		if entry.has("energy_source"):
			item.energy_source = str(entry.energy_source)
		out.append(item)
	return out


static func hardware_ids(package: Dictionary) -> PackedStringArray:
	var ids := PackedStringArray()
	for entry: Dictionary in package.hardware:
		ids.append(str(entry.id))
	return ids


## Estimated airframe items for a geometry and fuselage box, in the definition's item shape with kind
## "estimated". Densities and unit masses come from the package's mass_proposal group.
static func airframe_items(package: Dictionary, shape: Dictionary, fuselage: Dictionary) -> Array:
	if shape.is_empty():
		return []
	var nose := finite(fuselage.get("nose_x"))
	var tail_end := finite(fuselage.get("tail_x"))
	var width := positive(fuselage.get("width"))
	var height := positive(fuselage.get("height"))
	var center_z := finite(fuselage.get("center_z"))
	if is_nan(nose) or is_nan(tail_end) or is_nan(width) or is_nan(height) or is_nan(center_z) or tail_end <= nose:
		return []
	var span: float = shape.span
	var root: float = shape.root_chord
	var tip: float = shape.tip_chord
	var area: float = span * (root + tip) / 2.0
	var chord: float = area / span
	var taper: float = tip / root
	var mac: float = 2.0 / 3.0 * root * (1.0 + taper + taper * taper) / (1.0 + taper)
	var h_position: PackedFloat64Array = shape.h_position
	var v_position: PackedFloat64Array = shape.v_position
	var h_chord: float = shape.h_chord
	var v_chord: float = shape.v_chord
	var thickness := number(package, "mass_proposal", "tail_thickness")
	var servo := number(package, "mass_proposal", "servo_mass")
	var length := tail_end - nose
	var shell := 2.0 * (width + height) * length * number(package, "mass_proposal", "fuselage_taper_factor")
	var rod_start := root
	var rod_length := maxf(h_position[0] - rod_start, 0.0)
	return [
		_item(AIRFRAME_ITEM_IDS[0], "Wing with ailerons", area * number(package, "mass_proposal", "wing_areal_density"),
			[0.25 * root + (number(package, "mass_proposal", "wing_centroid_chord_fraction") - 0.25) * mac, 0.0, 0.0],
			[chord, span, number(package, "mass_proposal", "wing_thickness_ratio") * chord]),
		_item(AIRFRAME_ITEM_IDS[1], "Fuselage", shell * number(package, "mass_proposal", "fuselage_shell_density"),
			[nose + number(package, "mass_proposal", "fuselage_centroid_fraction") * length, 0.0, center_z],
			[length, width, height]),
		_item(AIRFRAME_ITEM_IDS[2], "Stabilizer and elevator",
			float(shape.h_span) * h_chord * number(package, "mass_proposal", "tail_areal_density"),
			[h_position[0] + 0.5 * h_chord, 0.0, h_position[2]], [h_chord, float(shape.h_span), thickness]),
		_item(AIRFRAME_ITEM_IDS[3], "Fin and rudder",
			float(shape.v_height) * v_chord * number(package, "mass_proposal", "tail_areal_density"),
			[v_position[0] + 0.5 * v_chord, 0.0, v_position[2] + 0.5 * float(shape.v_height)],
			[v_chord, thickness, float(shape.v_height)]),
		_item(AIRFRAME_ITEM_IDS[4], "Left aileron servo", servo, [0.25 * root + 0.25 * chord, -0.25 * span, 0.0], [0.04, 0.02, 0.04]),
		_item(AIRFRAME_ITEM_IDS[5], "Right aileron servo", servo, [0.25 * root + 0.25 * chord, 0.25 * span, 0.0], [0.04, 0.02, 0.04]),
		_item(AIRFRAME_ITEM_IDS[6], "Elevator and rudder servos", 2.0 * servo, [root, 0.0, center_z], [0.04, 0.04, 0.04]),
		_item(AIRFRAME_ITEM_IDS[7], "Receiver", number(package, "mass_proposal", "receiver_mass"), [0.5 * root, 0.0, center_z], [0.05, 0.035, 0.015]),
		_item(AIRFRAME_ITEM_IDS[8], "Pushrods, horns and wiring", number(package, "mass_proposal", "hardware_mass"),
			[rod_start + 0.5 * rod_length, 0.0, center_z], [rod_length, 0.0, 0.0]),
	]


static func _item(id: String, name: String, mass: float, position: Array, size: Array) -> Dictionary:
	return {"id": id, "name": name, "mass": mass, "position": position, "size": size, "kind": "estimated"}


static func _derived(value: Variant, formula: String) -> Dictionary:
	return {value = value, kind = DERIVED, source = formula + ESTIMATE_NOTE}


static func _quantity(entry: Dictionary, unit: String) -> Dictionary:
	return {value = entry.value, unit = unit, kind = entry.kind, source = entry.source}


static func _copy_quantity(entry: Dictionary) -> Dictionary:
	var value: Variant = entry.value
	if typeof(value) == TYPE_ARRAY:
		value = (value as Array).duplicate(true)
	return {value = value, unit = entry.unit, kind = entry.kind, source = entry.source}


static func _dictionary(node: Variant) -> Dictionary:
	if typeof(node) == TYPE_DICTIONARY:
		return node
	return {}


## The number as float, or NAN when it is not a finite int or float.
static func finite(node: Variant) -> float:
	if typeof(node) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(node)):
		return float(node)
	return NAN


## The number as float, or NAN unless it is finite and greater than zero.
static func positive(node: Variant) -> float:
	var value := finite(node)
	return value if value > 0.0 else NAN


## `count` finite numbers as a packed float64 array, or an empty array.
static func vector(node: Variant, count: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	if typeof(node) != TYPE_ARRAY or (node as Array).size() != count:
		return out
	for item: Variant in (node as Array):
		var value := finite(item)
		if is_nan(value):
			return PackedFloat64Array()
		out.append(value)
	return out
