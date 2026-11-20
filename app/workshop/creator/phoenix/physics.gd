extends RefCounted
## Phoenix physics for Creator (IAQ-03b / PX-R5): each converted Phoenix aeroplane flies with packages
## derived from its own decoded physical data instead of the borrowed UltraStick values.
##
## `physics_block` reduces the decoded definition and the installation's airfoil polars to dimensionless
## facts stored in the GLB receipt. `derive` turns them, with a base Creator package of the chosen size
## class, into an airframe and a power package registered under content-addressed ids
## (`phoenix-v1|<base>|<scale>|<hash>`), so a reopened draft re-derives exactly the same packages.
## What Phoenix provides replaces the borrowed value (and is marked "borrowed" with a Phoenix source);
## what it does not (section moment, body side force, cross derivatives' ratios, battery) keeps the base
## package's value. Nothing here is a measurement or a reproduction of the Phoenix flight model.

const R := preload("res://workshop/creator/result.gd")
const Packages := preload("res://workshop/creator/packages.gd")
const CreatorBytes := preload("res://workshop/creator/bytes.gd")

const FORMAT := "openrc-phoenix-physics-v1"
const ID_PREFIX := "phoenix-v1"
## physics.sim (PhoenixRC 6.0.i): `airfoil_efficiency = 0.85`.
const PHOENIX_EFFICIENCY := 0.85
## Finite-wing maximum lift relative to the section peak (strip theory with 3-D relief).
const WING_PEAK_SHARE := 0.9
const SLOPE_WINDOW_DEG := 4.0
const STALL_DEPARTURE := 0.05
const SOURCE := "Phoenix RC stock definition, decoded locally (%s)"
## Borrowed aileron set of the base packages: per-aileron roll power on an AR 5 rectangular wing.
const BASE_CLDA := 0.0823
const FLAT_PLATE_MARGIN := 0.08
const STALL_START_MIN_DEG := 9.0
## Elevator/rudder τ ceiling: the record divides the elevator's by (1 − dε/dα) and accepts at most 1.5.
const MAX_SURFACE_EFFECTIVENESS := 0.6
const NO_LOAD_RPM_SHARE := 0.995
const LOADED_VOLTAGE_SHARE := 0.85
const MOTOR_EFFICIENCY := 0.8
const SUPPLY_DROP := 0.12
const MOTOR_SHARE := 0.6
const FLIGHT_HOURS_AT_FULL := 0.1
## Drag coefficient of the fuselage on Phoenix's projected frontal "drag area": Phoenix's own value
## (fixedWing/airplane.sim, nFuselageDragCoefficient; docs/research/aircraft-creator/phoenix-flight-model-2026-11-20.md).
const BODY_DRAG_COEFFICIENT := 0.75
const THRUST_CAP := 3.0
const THRUST_CAP_ITERATIONS := 5
const MIN_DIAMETER_SHARE := 0.4
const DERIVED_MASS_RANGE := [0.2, 15.0]
const DERIVED_LOADING_RANGE := [1.0, 25.0]
const DERIVED_THRUST_RANGE := [0.3, 3.2]
## Jets and ducted fans (Phoenix `turbine`, `Max_Thrust` in newtons) fly on an equivalent propeller: pitch
## equal to its diameter and this pitch speed at the source size, so its thrust falls off far less with
## airspeed than a model propeller's. Froude-scaled with the flown size.
const JET_PITCH_SPEED_MPS := 70.0
const JET_PITCH_RATIO := 1.0
## A Phoenix glider without propulsion gets an estimated launch motor of this static thrust per weight
## (a motor glider's), so airborne and hand starts exist; its pitch speed at the source size.
const GLIDER_THRUST_SHARE := 0.45
const GLIDER_PITCH_SPEED_MPS := 22.0
const EQUIVALENT_ITERATIONS := 6
const EQUIVALENT_TOLERANCE := 0.02
## Bumped whenever `derive` maps the same physics block to different packages, so an earlier draft's ids
## no longer restore silently onto changed values.
const DERIVATION_VERSION := 16
const KV_CALIBRATION_ITERATIONS := 4
## A static figure of merit at the top of measured small propellers (UIUC data reach about 0.75).
const MAX_FIGURE_OF_MERIT := 0.8
const START_LIFT_SHARE := 0.69
const START_ALPHA_DEG := 7.0
## Phoenix ducted fans and turbines on OpenRC's turbine law (IAQ T4).
const JET_EFFLUX_MPS := 100.0
const JET_DEFAULT_SPOOL_S := 0.5
const JET_MIN_SPOOL_S := 0.05
const JET_MIN_MAX_RPM := 10000.0
## Phoenix's propeller law (airplane.sim): static thrust 0.18·Pitch·D³·n² N (n in rev/s; Pitch·D³·RPM²/20000) ×
## the blade factor, falling linearly to zero at 1.6 × the pitch speed.
const PHOENIX_THRUST_CONSTANT := 0.18
const PHOENIX_ZERO_THRUST := 1.6
const BLADE_FACTORS := {2: 1.0, 3: 1.3, 4: 1.54, 5: 1.85, 6: 2.06}
## Smallest electric drive time constant J·R/Kt² a derived power package may have (propulsion.gd shaft_step
## assumes τ ≈ 0.2 s ≫ dt).
const SHAFT_TIME_CONSTANT_S := 0.2
## Phoenix `Fine_tuning` multipliers applied (percent / 100), kept inside these factors.
const TUNING_KEYS := ["Lift", "Elevator", "Aileron", "Rudder", "Thrust", "Engine"]
const TUNING_RANGE := [0.25, 2.0]
## Roll power kept for declared but inactive ailerons, relative to the base set: the record accepts a wing
## aileron effectiveness of at least 0.01, and the base set is about 0.13.
const INACTIVE_AILERON_SHARE := 0.1
## Advance ratio where a Ct table crosses zero (its last row when it never does).
static func _zero_thrust_advance(rows: Array) -> float:
	for index: int in range(1, rows.size()):
		var a: Array = rows[index - 1]
		var b: Array = rows[index]
		if float(a[1]) > 0.0 and float(b[1]) <= 0.0:
			return float(a[0]) + (float(b[0]) - float(a[0])) * float(a[1]) / (float(a[1]) - float(b[1]))
	return float(rows[-1][0]) if not rows.is_empty() else 0.0


## Pitch/diameter of the propeller behind every base package's Ct/Cp tables (UIUC APC Sport 11×6).
const TABLE_PITCH_RATIO := 6.0 / 11.0


## Lift, drag and stall facts of one decoded polar (`coefficients` = flat [alpha deg, CL, CD] triples).
## `incidence_deg` is the surface's setting angle relative to the fuselage reference.
static func reduce_polar(coefficients: Array, incidence_deg := 0.0) -> Dictionary:
	var rows: Array = []
	var index := 0
	while index + 2 < coefficients.size():
		var a := float(coefficients[index])
		var cl := float(coefficients[index + 1])
		var cd := float(coefficients[index + 2])
		if is_finite(a) and is_finite(cl) and is_finite(cd):
			rows.append([a, cl, cd])
		index += 3
	if rows.size() < 8:
		return {}
	rows.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	# Least-squares slope over the attached window about zero.
	var n := 0
	var sx := 0.0
	var sy := 0.0
	var sxx := 0.0
	var sxy := 0.0
	for row: Array in rows:
		if absf(float(row[0])) <= SLOPE_WINDOW_DEG:
			var x := deg_to_rad(float(row[0]))
			n += 1
			sx += x
			sy += float(row[1])
			sxx += x * x
			sxy += x * float(row[1])
	if n < 3 or absf(n * sxx - sx * sx) < 1e-12:
		return {}
	var slope := (n * sxy - sx * sy) / (n * sxx - sx * sx)
	var intercept := (sy - slope * sx) / n
	if not (slope > 0.5 and slope < 9.0):
		return {}
	var peak := -INF
	var peak_alpha := 0.0
	var trough := INF
	var cd_min := INF
	var cl_at_min := 0.0
	for row: Array in rows:
		var a := float(row[0])
		if a >= 0.0 and a <= 30.0 and float(row[1]) > peak:
			peak = float(row[1])
			peak_alpha = a
		if a <= 0.0 and a >= -30.0 and float(row[1]) < trough:
			trough = float(row[1])
		if absf(a) <= 8.0 and float(row[2]) < cd_min:
			cd_min = float(row[2])
			cl_at_min = float(row[1])
	# Stall blend: from where the lift falls STALL_DEPARTURE below the attached line, up to the peak.
	var departure := peak_alpha
	for row: Array in rows:
		var a := float(row[0])
		if a > 0.0 and a <= peak_alpha:
			var line := intercept + slope * deg_to_rad(a)
			if line > 0.0 and float(row[1]) < (1.0 - STALL_DEPARTURE) * line:
				departure = a
				break
	return {
		slope = slope, cl_zero = intercept, cl_at_incidence = intercept + slope * deg_to_rad(incidence_deg),
		cl_max = peak, alpha_peak_deg = peak_alpha, cl_min = trough, cd_min = cd_min, cl_min_drag = cl_at_min,
		stall_width_deg = clampf(peak_alpha - departure, 2.0, 15.0),
	}


## Plain-flap effectiveness τ for a hinged surface of chord ratio `ratio` (thin-airfoil theory),
## reduced by Phoenix's section efficiency.
static func flap_tau(ratio: float) -> float:
	var r := clampf(ratio, 0.02, 0.98)
	var theta := acos(2.0 * r - 1.0)
	return PHOENIX_EFFICIENCY * (1.0 - (theta - sin(theta)) / PI)


static func helmbold(aspect: float) -> float:
	return TAU * aspect / (2.0 + sqrt(aspect * aspect + 4.0))


## The dimensionless physics block for the receipt, from the decoded model and the polars of its
## airfoils (`polars`: airfoil name -> flat coefficients). `datum` and `scale` as for the layout
## (GLB metres per GEO unit). Returns {} when the main wing's polar is unavailable.
static func physics_block(model: Dictionary, scale: float, datum: Array, polars: Dictionary,
		wing: Dictionary, tail: Variant, fin: Variant) -> Dictionary:
	if wing.is_empty() or datum.size() != 3:
		return {}
	var wing_attributes: Dictionary = wing.get("attributes", {})
	var section := reduce_polar(polars.get(str(wing_attributes.get("Airfoil", "")), []),
		_num(wing_attributes.get("Incidence"), 0.0))
	if section.is_empty():
		return {}
	var half := _num(wing_attributes.get("Length"), 0.0)
	var root := _num(wing_attributes.get("Root_chord"), 0.0)
	var tip := _num(wing_attributes.get("Tip_chord"), 0.0)
	if not (half > 0.0 and root > 0.0 and tip > 0.0):
		return {}
	var span := 2.0 * half
	var area := span * 0.5 * (root + tip)
	var aspect := span * span / area
	var wing_slope := helmbold(aspect)
	var physical: Dictionary = _dict(_dict(model.get("attributes")).get("Physical"))
	var drag_area := _dict(physical.get("Fuselage_drag_area"))
	if not (_num(physical.get("Weight"), 0.0) > 0.0):
		return {}
	var block := {
		format = FORMAT,
		airfoil = str(wing_attributes.get("Airfoil", "")),
		section = section,
		wing_lift_slope = wing_slope,
		aspect_ratio = aspect,
		body_drag_ratio = BODY_DRAG_COEFFICIENT * maxf(0.0, _num(drag_area.get("frontal"), 0.0)) / area,
		mass_kg = _num(physical.get("Weight"), 0.0),
		incidence_deg = _num(wing_attributes.get("Incidence"), 0.0),
		washout_deg = _num(wing_attributes.get("Washout"), 0.0),
	}
	# Centre of gravity: aft of the datum, in metres at the source size.
	var cg := _dict(physical.get("Centre_of_gravity"))
	if cg.has("z") and is_finite(_num(cg.get("z"), NAN)):
		block.cg_aft_m = -(_num(cg.get("z"), 0.0) * scale - float(datum[2]))
	# Control surfaces: elevator and rudder effectiveness relative to their surface's lift slope.
	for pair: Array in [["elevator", tail], ["rudder", fin]]:
		var surface_owner: Variant = pair[1]
		if surface_owner is Dictionary:
			var effectiveness := _surface_effectiveness(surface_owner, str(pair[0]))
			if is_finite(effectiveness):
				block[str(pair[0]) + "_effectiveness"] = effectiveness
	var aileron := _aileron_power(wing, span, root, tip, area, wing_slope)
	if is_finite(aileron):
		block.aileron_roll_power = aileron
	elif _has_inactive_ailerons(wing):
		block.aileron_roll_power = 0.0  # declared but zero-length: the model steers with its rudder
	# Pilot stick expo per channel (Phoenix Controls.*.Expo, percent): input shaping, not aerodynamics.
	var controls := _dict(_dict(model.get("attributes")).get("Controls"))
	for axis: String in ["Aileron", "Elevator", "Rudder"]:
		var expo := _num(_dict(controls.get(axis)).get("Expo"), 0.0)
		if expo > 0.0:
			block["expo_" + axis.to_lower()] = minf(expo, 100.0)
	var tuning := {}
	var fine: Dictionary = _dict(_dict(model.get("attributes")).get("Fine_tuning"))
	for key: String in TUNING_KEYS:
		var percent := _num(fine.get(key), 100.0)
		if percent > 0.0 and percent != 100.0:
			tuning[key.to_lower()] = clampf(percent / 100.0, float(TUNING_RANGE[0]), float(TUNING_RANGE[1]))
	if not tuning.is_empty():
		block.tuning = tuning
	# Propulsion: the first valid propeller and how many there are (twins and four-engine models fly on
	# one equivalent propeller), or the summed jet thrust when the model has no propeller.
	var propulsion: Variant = model.get("propulsion")
	var propellers := 0
	var jet_thrust := 0.0
	var jet_idle_thrust := 0.0
	var jet_spool := 0.0
	var jet_max_rpm := 0.0
	var jet_idle_rpm := 0.0
	if propulsion is Array:
		for unit: Variant in propulsion:
			if not unit is Dictionary:
				continue
			var attributes := _dict(unit.get("attributes"))
			match str(unit.get("type", "")):
				"propeller":
					var diameter := _num(attributes.get("Diameter"), NAN)
					var pitch := _num(attributes.get("Pitch"), NAN)
					var rpm := _num(attributes.get("Max_RPM"), NAN)
					if diameter > 0.0 and pitch > 0.0 and rpm > 0.0:
						propellers += 1
						if propellers == 1:
							block.propeller = {diameter_m = diameter, pitch_m = pitch, max_rpm = rpm,
								blades = int(_num(attributes.get("Blade_count"), 2.0))}
				"turbine":
					var thrust := _num(attributes.get("Max_Thrust"), NAN)
					if thrust > 0.0:
						jet_thrust += thrust
						jet_idle_thrust += maxf(0.0, _num(attributes.get("Idle_Thrust"), 0.0))
						if jet_spool <= 0.0:
							jet_spool = _num(attributes.get("Spool_Time"), 0.0)
							jet_max_rpm = _num(attributes.get("Max_RPM"), 0.0)
							jet_idle_rpm = _num(attributes.get("Idle_RPM"), 0.0)
	if propellers > 1:
		block.propeller.count = propellers
	elif propellers == 0 and jet_thrust > 0.0:
		block.jet_thrust_n = jet_thrust
		block.jet_idle_thrust_n = minf(jet_idle_thrust, 0.5 * jet_thrust)
		block.jet_spool_s = jet_spool if jet_spool > 0.0 else JET_DEFAULT_SPOOL_S
		block.jet_max_rpm = jet_max_rpm
		block.jet_idle_rpm = jet_idle_rpm
	return block


## Elevator or rudder τ × spanwise coverage of its decoded control surface on `airfoil`.
static func _surface_effectiveness(airfoil: Dictionary, role: String) -> float:
	var at := _dict(airfoil.get("attributes"))
	var chord := 0.5 * (_num(at.get("Root_chord"), 0.0) + _num(at.get("Tip_chord"), 0.0))
	var length := _num(at.get("Length"), 0.0)
	if not (chord > 0.0 and length > 0.0):
		return NAN
	for surface: Variant in (airfoil.get("controlSurfaces") if airfoil.get("controlSurfaces") is Array else []):
		if not surface is Dictionary:
			continue
		var sat := _dict(surface.get("attributes"))
		if not str(sat.get("Input", "")).to_lower().contains(role):
			continue
		var surface_chord := 0.5 * (_num(sat.get("Root_chord"), 0.0) + _num(sat.get("Tip_chord"), 0.0))
		var surface_length := _num(sat.get("Length"), 0.0)
		if surface_chord > 0.0 and surface_length > 0.0:
			return flap_tau(surface_chord / chord) * clampf(surface_length / length, 0.0, 1.0)
	return NAN


## Roll power of one aileron, strip theory: τ·a_w·∫ c(y)·y dy / (S·b) over its span.
static func _aileron_power(wing: Dictionary, span: float, root: float, tip: float, area: float, slope: float) -> float:
	var half := 0.5 * span
	for surface: Variant in (wing.get("controlSurfaces") if wing.get("controlSurfaces") is Array else []):
		if not surface is Dictionary:
			continue
		var sat := _dict(surface.get("attributes"))
		if not str(sat.get("Input", "")).to_lower().contains("aileron"):
			continue
		var length := _num(sat.get("Length"), 0.0)
		var from_tip := maxf(0.0, _num(sat.get("Tip_distance"), 0.0))
		var surface_chord := 0.5 * (_num(sat.get("Root_chord"), 0.0) + _num(sat.get("Tip_chord"), 0.0))
		if not (length > 0.0 and surface_chord > 0.0):
			continue # a disabled (zero-length) or chordless entry; a later aileron may be usable
		var outer := clampf(half - from_tip, 0.0, half)
		var inner := clampf(outer - length, 0.0, outer)
		var middle := 0.5 * (inner + outer)
		var local_chord := root + (tip - root) * middle / half
		var tau := flap_tau(surface_chord / maxf(local_chord, 1e-6))
		# ∫ c(y) y dy for the linear chord c(y) = root + (tip − root)·y/half.
		var k := (tip - root) / half
		var integral := root * (outer * outer - inner * inner) / 2.0 + k * (pow(outer, 3) - pow(inner, 3)) / 3.0
		return tau * slope * integral / (area * span)
	return NAN


## Registers the derived packages for `block` on the given base packages at `scale` (unit scale of the
## placement: metres per GLB metre). Returns {airframe, power} ids, or {} when a base is unavailable.
## `flying_mass_kg` is the mass the aircraft actually flies at when it differs from the source mass at
## that scale (the estimated equipment of a small replica cannot always be made as light as the scaled
## source): the thrust targets (cap, jet thrust, glider launch motor) then refer to that weight.
static func derive(block: Dictionary, airframe_base: String, power_base: String, flown_scale: float,
		flying_mass_kg := NAN) -> Dictionary:
	if not valid_block(block) or not (flown_scale > 0.0):
		return {}
	# The id carries the scale with six decimals and the flying mass with three; the packages use exactly
	# those values, so a reopened draft re-derives identical packages from its id.
	var scale := String.num(flown_scale, 6).to_float()
	var mass_text := String.num(flying_mass_kg, 3) if flying_mass_kg > 0.0 and is_finite(flying_mass_kg) else "-"
	var flying_mass := mass_text.to_float() if mass_text != "-" else float(block.mass_kg) * pow(scale, 3)
	var base_airframe := Packages.airframe(airframe_base)
	var base_power := Packages.power(power_base)
	if not base_airframe.ok or not base_power.ok:
		return {}
	var tag := _tag(block, base_airframe.value, base_power.value, scale, mass_text)
	var airframe_id := "%s|%s|%s|%s|airframe|%s" % [ID_PREFIX, airframe_base, String.num(scale, 6), mass_text, tag]
	var power_id := "%s|%s|%s|%s|power|%s" % [ID_PREFIX, power_base, String.num(scale, 6), mass_text, tag]
	var registered_airframe: Dictionary = Packages.register_derived(airframe_id, _airframe(base_airframe.value, block, airframe_id))
	var registered_power: Dictionary = Packages.register_derived(power_id,
		_power(base_power.value, block, power_id, scale, flying_mass * Packages.GRAVITY))
	if not registered_airframe.ok or not registered_power.ok:
		return {}
	return {airframe = airframe_id, power = power_id}


## Re-registers the derived packages of a saved draft from its source's physics block. True only when
## both ids re-derive exactly (same bases, scale and content tag).
static func restore(block: Dictionary, airframe_id: String, power_id: String) -> bool:
	var airframe := parse_id(airframe_id)
	var power := parse_id(power_id)
	if airframe.is_empty() or power.is_empty() or airframe.kind != "airframe" or power.kind != "power" \
			or airframe.tag != power.tag or not is_equal_approx(float(airframe.scale), float(power.scale)) \
			or airframe.mass != power.mass:
		return false
	var derived := derive(block, str(airframe.base), str(power.base), float(airframe.scale),
		float(airframe.mass) if airframe.mass != "-" else NAN)
	return derived.get("airframe") == airframe_id and derived.get("power") == power_id


## The block's required facts are present and physically plausible (it arrives through an imported GLB
## receipt, so it is untrusted).
static func valid_block(block: Variant) -> bool:
	if not block is Dictionary or block.get("format") != FORMAT:
		return false
	var section: Variant = block.get("section")
	if not section is Dictionary:
		return false
	for key: String in ["slope", "cl_zero", "cl_at_incidence", "cl_max", "cl_min", "cd_min", "cl_min_drag", "stall_width_deg"]:
		if not _finite_number(section.get(key)):
			return false
	if not (_in(section.slope, 0.5, 9.0) and _in(section.cd_min, 0.0, 0.5) and _in(section.stall_width_deg, 0.0, 30.0)
			and _in(section.cl_max, -1.0, 4.0) and _in(section.cl_min, -4.0, 1.0)):
		return false
	if not (_in(block.get("wing_lift_slope"), 0.5, 9.0) and _in(block.get("aspect_ratio"), 0.5, 40.0)
			and _in(block.get("body_drag_ratio"), 0.0, 1.0) and _in(block.get("mass_kg"), 0.01, 1000.0)):
		return false
	for key: String in ["expo_aileron", "expo_elevator", "expo_rudder"]:
		if block.has(key) and not _in(block[key], 0.0, 100.0):
			return false
	for key: String in ["cg_aft_m", "elevator_effectiveness", "rudder_effectiveness", "aileron_roll_power", "jet_thrust_n",
			"jet_idle_thrust_n", "jet_spool_s", "jet_max_rpm", "jet_idle_rpm"]:
		if block.has(key) and not _in(block[key], -100.0, 1.0e6):
			return false
	var tuning: Variant = block.get("tuning", {})
	if not tuning is Dictionary:
		return false
	for key: Variant in tuning:
		if str(key) != str(key).to_lower() or str(key).capitalize() not in TUNING_KEYS \
				or not _in(tuning[key], float(TUNING_RANGE[0]), float(TUNING_RANGE[1])):
			return false
	var prop: Variant = block.get("propeller", {})
	if not prop is Dictionary:
		return false
	if not (prop as Dictionary).is_empty() and not (_in(prop.get("diameter_m"), 0.01, 10.0) and _in(prop.get("pitch_m"), 0.005, 10.0)
			and _in(prop.get("max_rpm"), 100.0, 200000.0) and _in(prop.get("count", 1), 1.0, 16.0)):
		return false
	return true


static func _finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


static func _in(value: Variant, low: float, high: float) -> bool:
	return _finite_number(value) and float(value) >= low and float(value) <= high


static func is_derived(id: String) -> bool:
	return id.begins_with(ID_PREFIX + "|")


## Base package id, scale and flying mass ("-" when it is the source mass) encoded in a derived id, so a
## reopened draft can re-derive it.
static func parse_id(id: String) -> Dictionary:
	var parts := id.split("|")
	if parts.size() != 6 or parts[0] != ID_PREFIX or not parts[2].is_valid_float() \
			or not (parts[3] == "-" or parts[3].is_valid_float()):
		return {}
	return {base = parts[1], scale = parts[2].to_float(), mass = parts[3], kind = parts[4], tag = parts[5]}


## Content tag: the block, both base packages' full content, the scale and the derivation version, so a
## changed base package or derivation re-derives under a new id and an older draft no longer restores.
static func _tag(block: Dictionary, airframe_base: Dictionary, power_base: Dictionary, scale: float, mass_text: String) -> String:
	var encoded := CreatorBytes.encode({block = block, airframe = airframe_base, power = power_base,
		scale = String.num(scale, 6), mass = mass_text, version = DERIVATION_VERSION})
	return str(encoded.value.sha256).substr(0, 16) if encoded.ok else "unencodable"


static func _quantity(value: float, unit: String, kind: String, note: String) -> Dictionary:
	return {value = value, unit = unit, kind = kind, source = note}


static func _airframe(base: Dictionary, block: Dictionary, id: String) -> Dictionary:
	var package := base.duplicate(true)
	var section: Dictionary = block.section
	var note := SOURCE % str(block.get("airfoil", ""))
	package.id = id
	package.description = "Phoenix-derived airframe: %s polar, Phoenix section efficiency, body drag area, control-surface geometry; other values from %s." % [
		str(block.get("airfoil", "")), str(base.get("id", ""))]
	# Lift: the wing's section lift at its setting angle, carried to the finite wing by the lift-slope ratio.
	var ratio := float(block.wing_lift_slope) / float(section.slope)
	# Phoenix `Fine_tuning.Lift` scales the zero-angle lift and the lift limits; the lift slope follows the
	# geometry in the compiler and is not tuned.
	var lift := _tuning(block, "lift")
	var tuned := "" if lift == 1.0 else ", × Phoenix lift tuning %s" % String.num(lift, 2)
	package.wing.zero_alpha_lift = _quantity(float(section.cl_at_incidence) * ratio * lift, "1", "borrowed",
		note + ": section CL at the wing incidence × finite/section lift-slope ratio" + tuned)
	package.wing.minimum_drag_lift = _quantity(float(section.cl_min_drag) * ratio, "1", "borrowed", note + ": CL at minimum section drag")
	package.wing.profile_drag = _quantity(float(section.cd_min) + float(block.body_drag_ratio), "1", "borrowed",
		note + ": minimum section CD plus %s × the fuselage frontal area over the wing area" % String.num(BODY_DRAG_COEFFICIENT, 2))
	package.wing.oswald_efficiency = _quantity(PHOENIX_EFFICIENCY, "1", "borrowed", "Phoenix physics.sim airfoil_efficiency")
	# The record's validity rules: both lift limits beyond the flat-plate lift CD90/2, and the stall blend
	# starting outside the ±8° linear region. The section values are kept when they satisfy them.
	var aspect := float(block.get("aspect_ratio", 5.0))
	var cd90 := float(package.envelope.flat_plate_base.value) + float(package.envelope.flat_plate_per_aspect_ratio.value) * aspect
	var floor_lift := 0.5 * cd90 + FLAT_PLATE_MARGIN
	var wing_slope := float(block.wing_lift_slope)
	var zero_lift := float(package.wing.zero_alpha_lift.value)
	var width := float(section.stall_width_deg)
	var cl_max := maxf(WING_PEAK_SHARE * float(section.cl_max) * lift, floor_lift)
	var cl_min := minf(WING_PEAK_SHARE * float(section.cl_min) * lift, -floor_lift)
	# Linear-line angle of each limit; the blend (half its width before the limit) must start beyond 8°.
	cl_max = maxf(cl_max, zero_lift + wing_slope * deg_to_rad(STALL_START_MIN_DEG + 0.5 * width))
	cl_min = minf(cl_min, zero_lift - wing_slope * deg_to_rad(STALL_START_MIN_DEG + 0.5 * width))
	package.envelope.CL_max = _quantity(clampf(cl_max, 0.4, 2.5), "1", "borrowed",
		note + ": section peak lift × %s, kept above the flat-plate lift and the linear region" % String.num(WING_PEAK_SHARE, 2) + tuned)
	package.envelope.CL_min = _quantity(clampf(cl_min, -2.5, -0.3), "1", "borrowed",
		note + ": section negative peak × %s, kept beyond the flat-plate lift and the linear region" % String.num(WING_PEAK_SHARE, 2))
	# The airborne start's reference speed, where the product's half-throttle trim begins its upward search: the
	# aircraft trimmed level at about START_ALPHA_DEG of body angle (inside the trim's 8° attached-flow limit), never
	# slower than about 1.2 × the stall speed (CL ≤ START_LIFT_SHARE × CL_max). Phoenix's own law levels many models
	# at half throttle only between 1.05 and 1.6 × the stall speed (phoenix_reference.py), so a faster reference
	# skips that band.
	# The compiler trims the whole aircraft (tail load about the CG) at start_alpha; cruise_lift caps it.
	package.wing.cruise_lift = _quantity(clampf(START_LIFT_SHARE * float(package.envelope.CL_max.value), 0.3, 1.0), "1", "derived",
		"%s × CL_max (about 1.2 × the stall speed): the slowest airborne start reference" % String.num(START_LIFT_SHARE, 2))
	package.wing.start_alpha = _quantity(deg_to_rad(START_ALPHA_DEG), "rad", "derived",
		"Body angle of the airborne start's reference speed, inside the trim's 8° attached-flow limit (IAQ T3)")
	package.envelope.stall_blend_width = _quantity(width, "deg", "borrowed",
		note + ": angle from attached-line departure to the lift peak")
	# With the model's own mass, lift and drag the package no longer leans on a 2-3 kg donor for these;
	# the borrowed cross derivatives still bound the shape (span, aspect ratio, taper) as before.
	package.domain.mass_kg = {min = DERIVED_MASS_RANGE[0], max = DERIVED_MASS_RANGE[1],
		reason = "Phoenix-derived mass, lift and drag; item masses stay below the loader's 5 kg"}
	package.domain.wing_loading_kg_m2 = {min = DERIVED_LOADING_RANGE[0], max = DERIVED_LOADING_RANGE[1],
		reason = "Phoenix-derived mass and wing; light foam to heavy scale models"}
	package.domain.thrust_to_weight = {min = DERIVED_THRUST_RANGE[0], max = DERIVED_THRUST_RANGE[1],
		reason = "Phoenix-derived propeller; heavy scale models fly from an airborne start below 0.5, extreme 3D electrics reach about 3"}
	# Phoenix stick expo as OpenRC dual-rate shaping (controls.rates): full travel, expo e of (1 − e)·x + e·x³ fitted
	# by least squares to Phoenix's |x|^(1 + 2E/100) over the stick range.
	if block.has("expo_aileron") or block.has("expo_elevator") or block.has("expo_rudder"):
		var normal := {}
		for axis: String in ["aileron", "elevator", "rudder"]:
			var expo := float(block.get("expo_" + axis, 0.0))
			normal[axis] = _quantity(1.0, "1", "borrowed", SOURCE % "controls" + ": full travel (Phoenix's high rate)")
			normal[axis + "_expo"] = _quantity(expo_fit(expo), "1", "derived",
				SOURCE % "controls" + ": Expo %s %% fitted to OpenRC's (1 − e)·x + e·x³" % String.num(expo, 0))
		package.rates = {normal = normal}
	# Control power: the surface geometry, times Phoenix's elevator/rudder/aileron tuning.
	for pair: Array in [["elevator_effectiveness", "elevator"], ["rudder_effectiveness", "rudder"]]:
		var key: String = pair[0]
		var power := _tuning(block, pair[1])
		var base_value := float(block[key]) if block.has(key) and float(block[key]) > 0.05 else float(package.tail[key].value)
		if (block.has(key) and float(block[key]) > 0.05) or power != 1.0:
			package.tail[key] = _quantity(clampf(base_value * power, 0.15, MAX_SURFACE_EFFECTIVENESS), "1", "borrowed",
				SOURCE % "control surface" + ": plain-flap τ × span coverage" + ("" if power == 1.0 else
				" × Phoenix %s tuning %s" % [pair[1], String.num(power, 2)]))
	var roll := _tuning(block, "aileron")
	var factor := roll
	var reason := "Phoenix aileron tuning %s on the base ailerons" % String.num(roll, 2)
	if block.has("aileron_roll_power"):
		# Declared zero-length ailerons (a rudder-steered model) keep a token roll power the record accepts.
		factor *= maxf(float(block.aileron_roll_power) / BASE_CLDA, INACTIVE_AILERON_SHARE)
		reason = "strip roll power τ·a·∫c·y dy/(S·b), base ratios kept" if float(block.aileron_roll_power) > 1e-4 \
			else "the Phoenix ailerons are inactive (zero length); token roll power only"
		if roll != 1.0:
			reason += ", × Phoenix aileron tuning %s" % String.num(roll, 2)
	if factor != 1.0 or block.has("aileron_roll_power"):
		var borrowed: Dictionary = package.borrowed_coefficients
		for key: String in ["Clda_left", "Clda_right", "CLda_each", "CDda_each", "Cmda_each", "Cnda_left", "Cnda_right"]:
			if borrowed.has(key):
				var entry: Dictionary = borrowed[key]
				entry.value = float(entry.value) * factor
				entry.kind = "derived"
				entry.source = SOURCE % "aileron geometry" + ": " + reason
	return package


## OpenRC's expo e (shape (1 − e)·x + e·x³) closest in least squares on [0, 1] to Phoenix's stick curve
## x^(1 + 2·percent/100): e = ∫(x^p − x)(x³ − x) / ∫(x³ − x)² = 105/8·(1/(p+4) − 1/(p+2) + 2/15).
static func expo_fit(percent: float) -> float:
	if not (percent > 0.0):
		return 0.0
	var p := 1.0 + 2.0 * percent / 100.0
	return clampf(105.0 / 8.0 * (1.0 / (p + 4.0) - 1.0 / (p + 2.0) + 2.0 / 15.0), 0.0, 0.9)


## A Phoenix `Fine_tuning` factor of the block (1 when untuned).
static func _tuning(block: Dictionary, key: String) -> float:
	var tuning: Variant = block.get("tuning", {})
	return float(tuning.get(key, 1.0)) if tuning is Dictionary else 1.0


## True when the wing declares ailerons and every one has an explicit zero length (Phoenix disables a
## surface that way). Ailerons with missing data are unknown, not inactive: the base set then stays.
static func _has_inactive_ailerons(wing: Dictionary) -> bool:
	var found := false
	for surface: Variant in (wing.get("controlSurfaces") if wing.get("controlSurfaces") is Array else []):
		if surface is Dictionary and str(_dict(surface.get("attributes")).get("Input", "")).to_lower().contains("aileron"):
			var length := _num(_dict(surface.get("attributes")).get("Length"), NAN)
			if not (is_finite(length) and length <= 0.0):
				return false
			found = true
	return found


## The power package for the Phoenix propeller. Phoenix specifies some aerobatic models with very large
## propellers at high RPM (static thrust up to five times the weight); real extreme 3D electrics reach about
## three times their weight, and OpenRC has no propeller-wash model for the hover authority beyond. The
## Phoenix RPM and pitch (hence the pitch speed) are
## kept and the physical propeller's diameter is reduced until the runtime's own full-pack static thrust is
## THRUST_CAP times the weight (thrust ∝ D⁴). The visual propeller is unchanged.
static func _power(base: Dictionary, block: Dictionary, id: String, scale: float, weight: float) -> Dictionary:
	if block.get("propeller", {}).is_empty():
		if not (is_finite(weight) and weight > 0.0):
			return _power_at(base, block, id, scale, 1.0)
		var jet := float(block.get("jet_thrust_n", 0.0))
		if jet > 0.0:
			return _jet_power(base, block, id, scale, weight)
		return _equivalent_power(base, block, id, scale, GLIDER_THRUST_SHARE * weight, GLIDER_PITCH_SPEED_MPS,
			TABLE_PITCH_RATIO, false)
	var share := 1.0
	var package := _power_at(base, block, id, scale, share)
	if not (is_finite(weight) and weight > 0.0):
		return package
	for iteration: int in THRUST_CAP_ITERATIONS:
		var probe := package.duplicate(true)
		probe.id = "%s#thrust-cap-%d" % [id, iteration]
		var point: Dictionary = Packages.static_thrust(probe, 1.0)
		if not point.get("ok", false) or float(point.thrust_n) <= THRUST_CAP * weight * 1.01:
			break
		share *= pow(THRUST_CAP * weight / float(point.thrust_n), 1.0 / 3.0) # Phoenix law: T ∝ P·D³
		share = maxf(share, MIN_DIAMETER_SHARE)
		package = _power_at(base, block, id, scale, share)
		if share <= MIN_DIAMETER_SHARE:
			break
	return package


static func _power_at(base: Dictionary, block: Dictionary, id: String, scale: float, share: float) -> Dictionary:
	var package := base.duplicate(true)
	package.id = id
	var prop: Dictionary = block.get("propeller", {})
	if prop.is_empty():
		package.description = "Phoenix model without a decoded propeller: %s unchanged." % str(base.get("id", ""))
		return package
	# N identical propellers at the same RPM and pitch: one of diameter D·N^¼ gives their summed thrust.
	var count := maxi(1, int(prop.get("count", 1)))
	var diameter := float(prop.diameter_m) * scale * share * pow(count, 0.25)
	var base_diameter := float(package.propeller.diameter.value)
	var note := ": Diameter at the flown size" if absf(share - 1.0) < 0.001 else \
		": Diameter at the flown size × %s (Phoenix thrust tuning, then a static-thrust limit of %s × the weight)" % [
			String.num(share, 3), String.num(THRUST_CAP, 1)]
	if count > 1:
		note += "; one propeller of %s propellers' combined thrust (D·N^¼)" % count
	package.propeller.diameter = _quantity(diameter, "m", "borrowed", SOURCE % "propeller" + note)
	package.propeller.name = "Phoenix %s × %s m propeller" % [String.num(float(prop.diameter_m), 3), String.num(float(prop.pitch_m), 3)]
	# Rotor inertia ∝ D⁴ for a geometrically similar blade.
	var inertia: Dictionary = package.propeller.rotating_inertia
	inertia.value = float(inertia.value) * pow(diameter / base_diameter, 4)
	inertia.kind = "derived"
	# Phoenix's propeller law on the base table's shape: static Ct = 0.18·(P/D)·blade factor·thrust tuning/ρ
	# (thrust 0.18·P·D³·n²) and zero thrust at J = 1.6·P/D. The power coefficient follows Ct·J, so the
	# propeller's efficiency curve keeps the base table's shape.
	var ratio := float(prop.pitch_m) * scale / diameter
	var ct_rows: Array = package.propeller.ct_table.value
	if ratio > 0.0 and not ct_rows.is_empty():
		var blades := int(prop.get("blades", 2))
		# Measured propeller data (UIUC APC Sport 11×6, pitch ratio 6/11): the advance-ratio axis stretches with the
		# pitch ratio and the static coefficient with its square root, the measured family's mild trend. Phoenix's
		# own static law (0.18·P/D) sits 20–30 % below such data and starves part-throttle cruise, so only its
		# blade factor and thrust tuning are kept (docs/research/aircraft-creator/phoenix-flight-model-2026-11-20.md).
		var stretch := clampf(ratio / TABLE_PITCH_RATIO, 0.5, 2.5)
		var k_ct := sqrt(stretch) * float(BLADE_FACTORS.get(blades, 1.0)) * _tuning(block, "thrust")
		var k_j := stretch
		# The static figure of merit Ct^1.5/(Cp·√(2/π)) scales by √k_ct/k_j; many blades, a high thrust tuning or a
		# low pitch would push it past what real propellers reach, so the power coefficient then rises with it.
		var k_cp := k_ct * k_j
		var cp_rows0: Array = package.propeller.cp_table.value
		if not cp_rows0.is_empty() and float(cp_rows0[0][1]) > 0.0 and float(ct_rows[0][1]) > 0.0:
			var merit := pow(float(ct_rows[0][1]) * k_ct, 1.5) / (float(cp_rows0[0][1]) * k_cp * sqrt(2.0 / PI))
			k_cp *= maxf(1.0, merit / MAX_FIGURE_OF_MERIT)
		for pair: Array in [["ct_table", k_ct], ["cp_table", k_cp]]:
			var table: Dictionary = package.propeller[pair[0]]
			var rows: Array = []
			for row: Variant in table.value:
				rows.append([float(row[0]) * k_j, float(row[1]) * float(pair[1])])
			table.value = rows
			table.kind = "derived"
			table.source = SOURCE % "propeller" + ": the measured base table, advance ratio × pitch-ratio stretch %s, coefficient × √stretch × Phoenix blade factor and thrust tuning" % String.num(stretch, 3)
	# Phoenix drives its propeller at the model's maximum RPM. Froude similarity keeps the advance ratio of a
	# resized model: n·D ∝ √s, so the flown RPM is Max_RPM·s^-½. The installation is sized to deliver the
	# static shaft power P = Cp(0)·ρ·n³·D⁵ there: Kv for that RPM at LOADED_VOLTAGE_SHARE of the pack voltage,
	# and motor plus battery resistance for SUPPLY_DROP of the voltage at that current.
	var voltage := float(package.motor.no_load_voltage_v.value)
	var rpm := float(prop.max_rpm) / sqrt(scale)
	var cp_rows: Array = package.propeller.cp_table.value
	var cp0 := float(cp_rows[0][1]) if not cp_rows.is_empty() else 0.04
	var shaft_power := cp0 * Packages.AIR_DENSITY * pow(rpm / 60.0, 3) * pow(diameter, 5)
	if voltage > 0.0 and rpm > 0.0 and shaft_power > 0.0:
		var kv := rpm / (LOADED_VOLTAGE_SHARE * voltage)
		var current := shaft_power / (MOTOR_EFFICIENCY * LOADED_VOLTAGE_SHARE * voltage)
		var supply := SUPPLY_DROP * voltage / current
		package.motor.kv_rpm_per_volt = _quantity(kv, "rpm/V", "derived",
			SOURCE % "propeller" + ": Max_RPM (Froude-scaled to the flown size) at %s of the pack voltage" % String.num(LOADED_VOLTAGE_SHARE, 2))
		package.motor.no_load_rpm = _quantity(kv * voltage * NO_LOAD_RPM_SHARE, "rpm", "derived", "Kv × no-load voltage, less 0.5 % of rounding margin")
		package.motor.resistance_ohm = _quantity(MOTOR_SHARE * supply, "ohm", "derived",
			"Sized so the static shaft power Cp(0)·ρ·n³·D⁵ = %s W at the Phoenix RPM costs %s of the pack voltage" % [
				String.num(shaft_power, 0), String.num(SUPPLY_DROP, 2)])
		package.battery.resistance_ohm = _quantity((1.0 - MOTOR_SHARE) * supply, "ohm", "derived",
			"Share of the supply resistance sized for the Phoenix propeller power")
		package.battery.capacity_ah = _quantity(maxf(float(package.battery.capacity_ah.value), current * FLIGHT_HOURS_AT_FULL),
			"Ah", "derived", "At least %s minutes at the static current" % String.num(FLIGHT_HOURS_AT_FULL * 60.0, 0))
		# The runtime steps the shaft explicitly and assumes its time constant is far above the tick: a small fast
		# rotor (a ducted-fan equivalent) would otherwise make it diverge. J·R/Kt² is the electric drive's time
		# constant; the rotor inertia is raised to keep it at SHAFT_TIME_CONSTANT_S.
		# The nominal-voltage estimate misses the full pack's higher voltage: correct Kv until the runtime's own
		# static full-throttle RPM is Phoenix's (Phoenix holds its RPM at Max_RPM).
		var calibrated := false
		for iteration: int in KV_CALIBRATION_ITERATIONS:
			var probe := package.duplicate(true)
			probe.id = "%s#kv-%d-%s" % [id, iteration, String.num(diameter, 9)]
			var point: Dictionary = Packages.static_thrust(probe, 1.0)
			if not point.get("ok", false) or not (float(point.rpm) > 0.0):
				break
			if absf(float(point.rpm) / rpm - 1.0) < 0.01:
				calibrated = true
				break
			kv *= rpm / float(point.rpm)
			package.motor.kv_rpm_per_volt.value = kv
			package.motor.no_load_rpm.value = kv * voltage * NO_LOAD_RPM_SHARE
		package.motor.kv_rpm_per_volt.source = SOURCE % "propeller" + (": calibrated so the runtime's static full-throttle RPM on a full pack is Max_RPM (Froude-scaled to the flown size)"
			if calibrated else ": corrected toward the runtime's static full-throttle RPM of Max_RPM (Froude-scaled), not within 1 %% after %d steps" % KV_CALIBRATION_ITERATIONS)
		var kt := 60.0 / (TAU * kv)
		var floor_inertia := SHAFT_TIME_CONSTANT_S * kt * kt / supply
		if float(inertia.value) < floor_inertia:
			inertia.value = floor_inertia
			inertia.source = "Raised so the motor-propeller time constant J·R/Kt² is %s s, the runtime's explicit shaft step assumption (the D⁴-scaled rotor was %s kg·m²)" % [
				String.num(SHAFT_TIME_CONSTANT_S, 2), String.num(float(base.propeller.rotating_inertia.value) * pow(diameter / base_diameter, 4), 9)]
	package.description = "Phoenix-derived power: %s m propeller, pitch ratio %s, %s rpm; motor resistance, battery and ESC from %s." % [
		String.num(diameter, 3), String.num(ratio, 2), String.num(float(prop.max_rpm), 0), str(base.get("id", ""))]
	return package


## The power package of a Phoenix ducted fan or turbine (IAQ T4): the base package's hardware and the
## `jet` member Packages compiles into OpenRC's turbine law. Phoenix's law (airplane.sim) is thrust = idle +
## speed fraction × (Max_Thrust − idle), × (1 − 0.01 × airspeed in m/s): the momentum law with a 100 m/s
## efflux. The Phoenix thrust-to-weight ratio is kept at the flying weight (thrust and weight both scale with
## the cube of the size), within the cap; the spool time scales with √s (Froude).
static func _jet_power(base: Dictionary, block: Dictionary, id: String, scale: float, weight: float) -> Dictionary:
	var package := base.duplicate(true)
	package.id = id
	var share := minf(float(block.jet_thrust_n) / (float(block.mass_kg) * Packages.GRAVITY) * _tuning(block, "thrust"), THRUST_CAP)
	var thrust := share * weight
	var idle_share := float(block.get("jet_idle_thrust_n", 0.0)) / float(block.jet_thrust_n)
	var top := clampf(float(block.get("jet_max_rpm", 0.0)), JET_MIN_MAX_RPM, Packages.JET_MAX_RPM)
	var idle := clampf(float(block.get("jet_idle_rpm", 0.0)), 1000.0, top - 1000.0)
	var source := SOURCE % "propulsion"
	package.jet = {
		name = "Phoenix turbine" if float(block.get("jet_idle_rpm", 0.0)) >= 10000.0 else "Phoenix ducted fan",
		static_thrust = _quantity(thrust, "N", "borrowed", source + ": Max_Thrust %s N × thrust tuning at the flying weight (thrust-to-weight %s)" % [
			String.num(float(block.jet_thrust_n), 1), String.num(share, 2)]),
		idle_thrust = _quantity(thrust * idle_share, "N", "borrowed", source + ": Idle_Thrust in the same proportion"),
		efflux_speed = _quantity(JET_EFFLUX_MPS, "m/s", "derived",
			"Phoenix's turbine law loses 1 % of thrust per m/s: the momentum law T − ṁ·u with a %s m/s efflux" % String.num(JET_EFFLUX_MPS, 0)),
		idle_rpm = _quantity(idle, "rpm", "borrowed", source + ": Idle_RPM (at least 1000 rpm, the runtime's floor)"),
		max_rpm = _quantity(top, "rpm", "borrowed", source + ": Max_RPM"),
		spool_time = _quantity(maxf(maxf(JET_MIN_SPOOL_S, (top - idle) / Packages.JET_MAX_SPOOL_RATE),
			float(block.get("jet_spool_s", JET_DEFAULT_SPOOL_S)) * sqrt(scale)), "s", "borrowed",
			source + ": Spool_Time (the full speed range), × √s for the flown size"),
	}
	package.description = "Phoenix-derived %s: %s N static thrust, momentum law with ram drag; hardware masses from %s." % [
		str(package.jet.name).to_lower().trim_prefix("phoenix "), String.num(thrust, 1), str(base.get("id", ""))]
	return package


## The power package for a model without a decoded propeller: an equivalent propeller of the given pitch
## ratio and pitch speed (at the source size), its diameter iterated until the runtime's full-pack static
## thrust is `target_n` (thrust ∝ D² at a fixed pitch speed). `jet` labels it as the Phoenix jet thrust;
## otherwise it is an estimated launch motor for a glider.
static func _equivalent_power(base: Dictionary, block: Dictionary, id: String, scale: float, target_n: float,
		pitch_speed_mps: float, ratio: float, jet: bool) -> Dictionary:
	var speed := pitch_speed_mps * sqrt(scale)
	# Static thrust Ct·ρ·n²·D⁴ with n = V/(ratio·D): first guess D = ratio·√(T/(Ct·ρ))/V.
	var diameter := ratio * sqrt(target_n / (_base_static_ct(base) * Packages.AIR_DENSITY)) / speed
	var package: Dictionary = {}
	for iteration: int in EQUIVALENT_ITERATIONS:
		var source := block.duplicate(true)
		source.erase("tuning") # the target thrust already holds the Phoenix thrust and engine tuning
		source.propeller = {diameter_m = diameter / scale, pitch_m = ratio * diameter / scale,
			max_rpm = 60.0 * speed / (ratio * diameter) * sqrt(scale), blades = 2}
		package = _power_at(base, source, id, scale, 1.0)
		var probe := package.duplicate(true)
		probe.id = "%s#equivalent-%d" % [id, iteration]
		var point: Dictionary = Packages.static_thrust(probe, 1.0)
		if not point.get("ok", false) or not (float(point.thrust_n) > 0.0):
			break
		var error := target_n / float(point.thrust_n)
		if absf(error - 1.0) <= EQUIVALENT_TOLERANCE:
			break
		diameter *= sqrt(error)
	var what := "jet thrust equivalent" if jet else "estimated launch motor"
	var reason := ""
	if jet:
		reason = SOURCE % "propulsion" + ": propeller equivalent to Max_Thrust %s N (%s N at the flying weight, same thrust-to-weight), pitch speed %s m/s" % [
			String.num(float(block.get("jet_thrust_n", 0.0)), 1), String.num(target_n, 1), String.num(speed, 1)]
	else:
		reason = "The Phoenix glider has no motor; %s × weight static thrust so airborne and hand starts exist" % String.num(GLIDER_THRUST_SHARE, 2)
	package.propeller.name = "Phoenix %s" % what
	package.propeller.diameter = _quantity(float(package.propeller.diameter.value), "m", "borrowed" if jet else "estimated", reason)
	package.description = "Phoenix-derived power (%s): %s m propeller, pitch ratio %s; motor resistance, battery and ESC from %s." % [
		what, String.num(float(package.propeller.diameter.value), 3), String.num(ratio, 2), str(base.get("id", ""))]
	return package


## Static thrust coefficient of a base propeller (its Ct table at zero advance ratio).
static func _base_static_ct(package: Dictionary) -> float:
	var rows: Array = package.propeller.ct_table.value
	return maxf(0.03, float(rows[0][1])) if not rows.is_empty() else 0.1


static func _num(value: Variant, fallback: float) -> float:
	return float(value) if (value is float or value is int) and is_finite(float(value)) else fallback


static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}
