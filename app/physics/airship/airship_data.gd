# BL-02/BL-04: closed `openrc-airship v1` reader and derivation for the generic RC blimp.
# The file carries authored quantities {value, unit, kind, source}; this reader validates every field and derives
# the constant model the stage law reads: displaced volume/CB, helium and component inventory, CG, rigid inertia
# about the fixed datum O, the 6x6 added-mass matrix (Lamb prolate spheroid plus fin plates) and the Cholesky
# factor of the total mass matrix. Invalid data cannot fly: any error returns {ok = false, errors}.
# Frames: body FRD, origin O = the scaled model origin on the hull axis. 64-bit floats only.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const GC := preload("res://physics/generalized_coordinates.gd")

const FORMAT := "openrc-airship v1"
const KINDS := ["measured", "derived", "estimate", "design", "published"]
const ROTOR_IDS := ["port", "starboard", "stern_axial", "stern_lateral"]
const VECTOR_IDS := ["port", "starboard", "stern"]
const FIN_IDS := ["dorsal", "port", "starboard"]
const TOP_LEVEL_KEYS := ["format", "id", "name", "status", "provenance", "envelope", "gas", "hull_aero", "added_mass",
	"fins", "gondola", "vectors", "rotors", "battery", "masses", "ballast", "contacts", "mixer", "presentation"]
const MAX_STATIONS := 64
const MAX_POINTS := 64
const MAX_MASSES := 32
## Continuous layout: 4 motor speeds, 3 vector angles, 3 fin deflections, battery state of charge.
const STATE_LAYOUT := ["n_port", "n_starboard", "n_stern_axial", "n_stern_lateral",
	"vector_port_rad", "vector_starboard_rad", "vector_stern_rad",
	"fin_dorsal_rad", "fin_port_rad", "fin_starboard_rad", "battery_soc"]
const CONTINUOUS_SIZE := 11
const MOTOR := 0
const VECTOR := 4
const FIN := 7
const SOC := 10


static func load_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {ok = false, errors = PackedStringArray(["cannot open airship data: " + path])}
	var text := file.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {ok = false, errors = PackedStringArray(["airship data is not a JSON object: " + path])}
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	var result := parse(parsed)
	result.source_sha256 = ctx.finish().hex_encode()
	result.path = path
	return result


## Validate a decoded document. Returns {ok, data (plain validated numbers), errors}.
static func parse(raw: Dictionary) -> Dictionary:
	var e := PackedStringArray()
	if raw.get("format") != FORMAT:
		e.append("format must be '%s'" % FORMAT)
		return {ok = false, errors = e}
	for key: Variant in raw.keys():
		if not TOP_LEVEL_KEYS.has(key):
			e.append("unknown top-level key '%s' (closed contract)" % str(key))
	var d := {}
	d.id = _string(raw, "id", e)
	d.name = _string(raw, "name", e)
	d.status = _string(raw, "status", e)
	if d.status != "experimental":
		e.append("status must be 'experimental' until physical validation exists")
	var env: Dictionary = _object(raw, "envelope", e)
	d.envelope = {
		length = _q(env, "length", "m", e, 0.5, 50.0),
		max_diameter = _q(env, "max_diameter", "m", e, 0.05, 20.0),
		volume = _q(env, "volume", "m^3", e, 0.001, 1000.0),
		centroid = _qv(env, "centroid", "m", 3, e),
		surface_area = _q(env, "surface_area", "m^2", e, 0.01, 5000.0),
		areal_mass = _q(env, "areal_mass", "kg/m^2", e, 0.005, 2.0),
		radius_profile = _profile(env, e),
	}
	var gas: Dictionary = _object(raw, "gas", e)
	d.gas = {density = _q(gas, "density", "kg/m^3", e, 0.08, 0.6),
		fill_fraction = _q(gas, "fill_fraction", "1", e, 0.5, 1.0)}
	var hull: Dictionary = _object(raw, "hull_aero", e)
	d.hull_aero = {
		axial_drag = _q(hull, "axial_drag_coefficient", "1", e, 0.0, 1.0),
		crossflow_drag = _q(hull, "crossflow_drag_coefficient", "1", e, 0.0, 3.0),
		crossflow_efficiency = _q(hull, "crossflow_efficiency", "1", e, 0.0, 1.0),
		linear_force = _qv(hull, "linear_damping_force", "N*s/m", 3, e),
		linear_moment = _qv(hull, "linear_damping_moment", "N*m*s", 3, e),
	}
	var added: Dictionary = _object(raw, "added_mass", e)
	d.added_mass = {fin_coefficient = _q(added, "fin_normal_coefficient", "1", e, 0.0, 2.0),
		hull_scale = _q(added, "hull_scale", "1", e, 0.0, 2.0)}
	d.fins = []
	var fins: Array = _array(raw, "fins", e)
	for fin_id: String in FIN_IDS:
		var src: Dictionary = _find(fins, fin_id, "fins", e)
		d.fins.append({
			id = fin_id,
			area_fixed = _q(src, "area_fixed", "m^2", e, 0.0, 100.0),
			area_moving = _q(src, "area_moving", "m^2", e, 0.0, 100.0),
			centroid = _qv(src, "centroid", "m", 3, e),
			normal = _unit(_qv(src, "normal", "1", 3, e), "fin %s normal" % fin_id, e),
			span_dir = _unit(_qv(src, "span_dir", "1", 3, e), "fin %s span_dir" % fin_id, e),
			span = _q(src, "span", "m", e, 0.01, 20.0),
			chord = _q(src, "mean_chord", "m", e, 0.01, 20.0),
			te_sign = _q(src, "te_sign", "1", e, -1.0, 1.0),
			travel = _q(src, "travel", "deg", e, 1.0, 45.0),
			response_time = _q(src, "servo_response_time", "s", e, 0.005, 1.0),
			max_rate = _q(src, "servo_max_rate", "deg/s", e, 10.0, 2000.0),
			lift_slope_scale = _q(src, "lift_slope_scale", "1", e, 0.1, 2.0),
			drag = _q(src, "skin_drag_coefficient", "1", e, 0.0, 0.2),
			crossflow_drag = _q(src, "crossflow_drag_coefficient", "1", e, 0.0, 3.0),
		})
		if absf(float(d.fins[-1].te_sign)) != 1.0:
			e.append("fin %s te_sign must be +1 or -1" % fin_id)
	var gondola: Dictionary = _object(raw, "gondola", e)
	d.gondola = {min = _qv(gondola, "min", "m", 3, e), max = _qv(gondola, "max", "m", 3, e),
		drag = _q(gondola, "drag_coefficient", "1", e, 0.0, 3.0)}
	d.vectors = []
	var vectors: Array = _array(raw, "vectors", e)
	for vector_id: String in VECTOR_IDS:
		var src: Dictionary = _find(vectors, vector_id, "vectors", e)
		var travel: PackedFloat64Array = _qv(src, "travel", "deg", 2, e)
		d.vectors.append({id = vector_id, pivot = _qv(src, "pivot", "m", 3, e),
			axis = _unit(_qv(src, "axis", "1", 3, e), "vector %s axis" % vector_id, e),
			travel = travel, response_time = _q(src, "servo_response_time", "s", e, 0.005, 2.0),
			max_rate = _q(src, "servo_max_rate", "deg/s", e, 5.0, 2000.0)})
		# The rest thrust axis is defined at angle 0, which must be the travel's lower end (mixer neutral).
		if travel.size() == 2 and (travel[0] != 0.0 or not (travel[0] < travel[1])):
			e.append("vector %s travel must be [0, max] with max > 0" % vector_id)
	d.rotors = []
	var rotors: Array = _array(raw, "rotors", e)
	for rotor_id: String in ROTOR_IDS:
		var src: Dictionary = _find(rotors, rotor_id, "rotors", e)
		var vector_id := str(src.get("vector", ""))
		if not vector_id.is_empty() and not VECTOR_IDS.has(vector_id):
			e.append("rotor %s references unknown vector '%s'" % [rotor_id, vector_id])
		d.rotors.append({id = rotor_id, vector = VECTOR_IDS.find(vector_id),
			hub = _qv(src, "hub", "m", 3, e),
			thrust_axis = _unit(_qv(src, "thrust_axis_rest", "1", 3, e), "rotor %s thrust axis" % rotor_id, e),
			radius = _q(src, "radius", "m", e, 0.01, 2.0),
			# +1: the propeller spins right-handed about its thrust axis at positive speed.
			rotation_sense = _q(src, "rotation_sense", "1", e, -1.0, 1.0),
			static_thrust = _q(src, "static_thrust_max", "N", e, 0.01, 200.0),
			pitch_speed = _q(src, "pitch_speed", "m/s", e, 0.5, 100.0),
			reverse_efficiency = _q(src, "reverse_efficiency", "1", e, 0.0, 1.0),
			torque_ratio = _q(src, "torque_ratio", "m", e, 0.0, 1.0),
			shaft_power = _q(src, "max_shaft_power", "W", e, 0.1, 5000.0),
			motor_efficiency = _q(src, "motor_efficiency", "1", e, 0.1, 1.0),
			response_time = _q(src, "response_time", "s", e, 0.01, 2.0)})
		if absf(float(d.rotors[-1].rotation_sense)) != 1.0:
			e.append("rotor %s rotation_sense must be +1 or -1" % rotor_id)
	var battery: Dictionary = _object(raw, "battery", e)
	d.battery = {cells = int(_q(battery, "cells", "1", e, 1.0, 12.0)),
		capacity = _q(battery, "capacity", "A*h", e, 0.05, 50.0),
		resistance = _q(battery, "internal_resistance", "ohm", e, 0.0, 2.0),
		reference_voltage = _q(battery, "reference_voltage", "V", e, 1.0, 60.0),
		cutoff_cell = _q(battery, "cutoff_cell_voltage", "V", e, 2.5, 4.0),
		cutoff_band = _q(battery, "cutoff_band", "V", e, 0.05, 5.0),
		initial_soc = _q(battery, "initial_soc", "1", e, 0.05, 1.0),
		ocv = _ocv_table(battery, e)}
	d.masses = []
	var masses: Array = _array(raw, "masses", e)
	if masses.size() > MAX_MASSES:
		e.append("too many mass items")
	var ids := {}
	for item: Variant in masses:
		if typeof(item) != TYPE_DICTIONARY:
			e.append("mass item must be an object")
			continue
		var id := str(item.get("id", ""))
		if id.is_empty() or ids.has(id):
			e.append("mass item ids must be unique and nonempty")
		ids[id] = true
		d.masses.append({id = id, mass = _q(item, "mass", "kg", e, 0.0, 100.0), position = _qv(item, "position", "m", 3, e)})
	var ballast: Dictionary = _object(raw, "ballast", e)
	d.ballast = {position = _qv(ballast, "position", "m", 3, e),
		max_mass = _q(ballast, "max_mass", "kg", e, 0.0, 50.0),
		default_heaviness = _q(ballast, "default_heaviness", "kg", e, -1.0, 1.0)}
	var contacts: Dictionary = _object(raw, "contacts", e)
	d.contacts = {gear = [], hull_points = PackedFloat64Array(), prop_points = PackedFloat64Array()}
	for gear: Variant in _array(contacts, "gear", e):
		if typeof(gear) != TYPE_DICTIONARY:
			e.append("gear item must be an object")
			continue
		d.contacts.gear.append({id = str(gear.get("id", "")), point = _qv(gear, "point", "m", 3, e),
			stiffness = _q(gear, "stiffness", "N/m", e, 1.0, 1e6), damping = _q(gear, "damping", "N*s/m", e, 0.0, 1e5),
			mu_roll = _q(gear, "mu_roll", "1", e, 0.0, 2.0), mu_side = _q(gear, "mu_side", "1", e, 0.0, 2.0)})
	d.contacts.hull_points = _points(contacts, "hull_points", e)
	d.contacts.prop_points = _points(contacts, "prop_points", e)
	d.contacts.hull_stiffness = _q(contacts, "hull_stiffness", "N/m", e, 1.0, 1e6)
	d.contacts.hull_damping = _q(contacts, "hull_damping", "N*s/m", e, 0.0, 1e5)
	d.contacts.hull_mu = _q(contacts, "hull_mu", "1", e, 0.0, 2.0)
	d.contacts.impact_speed = _q(contacts, "impact_speed_limit", "m/s", e, 0.1, 20.0)
	var mixer: Dictionary = _object(raw, "mixer", e)
	d.mixer = {differential = _q(mixer, "differential_thrust", "1", e, 0.0, 1.0),
		stern_axial_share = _q(mixer, "stern_axial_share", "1", e, 0.0, 1.0),
		stern_vector_sign = _q(mixer, "stern_vector_on_pitch", "1", e, -1.0, 1.0),
		vector_on_pitch = _q(mixer, "vector_on_pitch", "1", e, 0.0, 1.0),
		lateral_on_yaw = _q(mixer, "lateral_on_yaw", "1", e, 0.0, 1.0)}
	if e.is_empty():
		_check_geometry(d, e)
	return {ok = e.is_empty(), data = d if e.is_empty() else {}, errors = e}


## Derive the constant flight model for one release atmosphere (rho, g) and a pilot weigh-off: heaviness_kg is the
## static weight-minus-buoyancy the ballast is trimmed to (positive = heavy). Ballast is clamped to [0, max_mass];
## the achieved heaviness is reported, never hidden.
static func derive(data: Dictionary, rho: float, gravity: float, heaviness_kg: float) -> Dictionary:
	var e := PackedStringArray()
	if not (is_finite(rho) and rho > 0.3 and rho < 1.6) or not (is_finite(gravity) and gravity > 9.0 and gravity < 10.5) \
			or not is_finite(heaviness_kg):
		e.append("release atmosphere or weigh-off is outside the admitted domain")
		return {ok = false, errors = e}
	var env: Dictionary = data.envelope
	var volume: float = env.volume
	var profile: PackedFloat64Array = env.radius_profile
	var stations := profile.size() / 2
	# Solid-of-revolution sums, scaled so the integrated volume equals the declared closed-mesh volume.
	var raw_volume := 0.0
	var raw_x := 0.0
	var shell_length := 0.0
	for i in stations - 1:
		var x0 := profile[2 * i]
		var r0 := profile[2 * i + 1]
		var x1 := profile[2 * i + 2]
		var r1 := profile[2 * i + 3]
		var dx := absf(x1 - x0)
		var area := PI * 0.5 * (r0 * r0 + r1 * r1)
		raw_volume += area * dx
		raw_x += area * dx * 0.5 * (x0 + x1)
		shell_length += 2.0 * PI * 0.5 * (r0 + r1) * sqrt(dx * dx + (r1 - r0) * (r1 - r0))
	if raw_volume <= 0.0 or shell_length <= 0.0:
		e.append("radius profile has no volume")
		return {ok = false, errors = e}
	var cb: PackedFloat64Array = env.centroid
	var gas_mass: float = float(data.gas.density) * volume * float(data.gas.fill_fraction)
	var shell_mass: float = float(env.areal_mass) * float(env.surface_area)
	# Inventory: point masses, shell and gas distributed along the profile, then ballast.
	var mass := 0.0
	var first := PackedFloat64Array([0.0, 0.0, 0.0])
	var inertia := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]) # about O: Jxx Jyy Jzz Jxy Jxz Jyz
	var inventory: Array = []
	for item: Dictionary in data.masses:
		_add_point(item.mass, item.position, inertia, first)
		mass += float(item.mass)
		inventory.append({id = item.id, mass = item.mass})
	var gas_x_shift: float = cb[0] - raw_x / raw_volume
	for i in stations - 1:
		var x0 := profile[2 * i] + gas_x_shift
		var r0 := profile[2 * i + 1]
		var x1 := profile[2 * i + 2] + gas_x_shift
		var r1 := profile[2 * i + 3]
		var dx := absf(x1 - x0)
		var xm := 0.5 * (x0 + x1)
		var rm := 0.5 * (r0 + r1)
		var slice_volume := PI * 0.5 * (r0 * r0 + r1 * r1) * dx
		var gas_piece := gas_mass * slice_volume / raw_volume
		var shell_piece := shell_mass * (2.0 * PI * rm * sqrt(dx * dx + (r1 - r0) * (r1 - r0))) / shell_length
		# Disc (gas) and ring (shell) of radius rm centred on the hull axis at (xm, cb_y, cb_z).
		var offset := PackedFloat64Array([xm, cb[1], cb[2]])
		_add_point(gas_piece + shell_piece, offset, inertia, first)
		var own_axial := gas_piece * rm * rm * 0.5 + shell_piece * rm * rm
		var own_transverse := gas_piece * rm * rm * 0.25 + shell_piece * rm * rm * 0.5
		inertia[0] += own_axial
		inertia[1] += own_transverse
		inertia[2] += own_transverse
		mass += gas_piece + shell_piece
	inventory.append({id = "helium", mass = gas_mass})
	inventory.append({id = "envelope_shell", mass = shell_mass})
	var buoyancy_mass := rho * volume
	var ballast_target: float = buoyancy_mass + heaviness_kg - mass
	var ballast_mass: float = clampf(ballast_target, 0.0, float(data.ballast.max_mass))
	_add_point(ballast_mass, data.ballast.position, inertia, first)
	mass += ballast_mass
	inventory.append({id = "ballast", mass = ballast_mass})
	var cg := PackedFloat64Array([first[0] / mass, first[1] / mass, first[2] / mass])
	# Rigid spatial inertia about O.
	var m_rb := _zero6()
	for i in 3:
		m_rb[i * 6 + i] = mass
	var s := _skew(cg)
	for r in 3:
		for c in 3:
			m_rb[r * 6 + 3 + c] = -mass * s[r * 3 + c]
			m_rb[(3 + r) * 6 + c] = mass * s[r * 3 + c]
	var jfull := _inertia_matrix(inertia)
	for r in 3:
		for c in 3:
			m_rb[(3 + r) * 6 + 3 + c] = jfull[r * 3 + c]
	var m_a := added_mass_matrix(data, rho)
	if m_a.is_empty():
		e.append("added-mass matrix could not be derived")
		return {ok = false, errors = e}
	var total := _zero6()
	for i in 36:
		total[i] = m_rb[i] + m_a[i]
	var factor := GC.cholesky_factor(total, 6)
	if not factor.ok:
		e.append("total mass matrix is not positive definite: " + str(factor.error))
		return {ok = false, errors = e}
	var rb_factor := GC.cholesky_factor(m_rb, 6)
	if not rb_factor.ok:
		e.append("rigid mass matrix is not positive definite: " + str(rb_factor.error))
		return {ok = false, errors = e}
	var model := data.duplicate(true)
	model.rho = rho
	model.gravity = gravity
	model.mass = mass
	model.cg = cg
	model.cb = cb.duplicate()
	model.inertia = inertia
	model.gas_mass = gas_mass
	model.shell_mass = shell_mass
	model.ballast_mass = ballast_mass
	model.buoyancy_n = buoyancy_mass * gravity
	model.weight_n = mass * gravity
	model.heaviness_kg = mass - buoyancy_mass
	model.requested_heaviness_kg = heaviness_kg
	model.inventory = inventory
	model.m_rb = m_rb
	model.m_a = m_a
	model.m_total = total
	model.lower = factor.lower
	model.hull_stations = _hull_stations(profile, float(data.hull_aero.crossflow_drag) * float(data.hull_aero.crossflow_efficiency))
	model.ref_area = pow(volume, 2.0 / 3.0)
	model.bound_radius = _bound_radius(data)
	_prepare_runtime(model)
	return {ok = true, model = model, errors = e}


## Constant per-fin, per-rotor and mixer quantities the stage law reads without recomputing them every RK stage.
static func _prepare_runtime(model: Dictionary) -> void:
	var max_nz := 0.0
	var max_ny := 0.0
	for fin: Dictionary in model.fins:
		var n: PackedFloat64Array = fin.normal
		var s: PackedFloat64Array = fin.span_dir
		# Aft chord direction: the body's -x projected into the fin plane.
		var aft := PackedFloat64Array([-1.0, 0.0, 0.0])
		var t := M.sub(M.sub(aft, M.scale(n, M.dot(aft, n))), M.scale(s, M.dot(aft, s)))
		fin.aft = M.scale(t, 1.0 / M.norm(t))
		var area: float = float(fin.area_fixed) + float(fin.area_moving)
		fin.area = area
		fin.lift_slope = 0.0
		fin.flap_tau = 0.0
		if area > 0.0:
			var aspect: float = 2.0 * float(fin.span) * float(fin.span) / area # hull acts as a reflection plane
			fin.lift_slope = float(fin.lift_slope_scale) * TAU * aspect / (2.0 + sqrt(aspect * aspect + 4.0))
			fin.flap_tau = minf(sqrt(float(fin.area_moving) / area), 0.8)
		max_nz = maxf(max_nz, absf(n[2]))
		max_ny = maxf(max_ny, absf(n[1]))
	model.fin_pitch_norm = 1.0 / max_nz if max_nz > 1e-6 else 0.0
	model.fin_yaw_norm = 1.0 / max_ny if max_ny > 1e-6 else 0.0
	# Each propeller collision witness follows the vector pivot of its nearest rotor hub.
	var props: PackedFloat64Array = model.contacts.prop_points
	var assign := PackedInt64Array()
	for i in props.size() / 3:
		var p := props.slice(3 * i, 3 * i + 3)
		var best := -1
		var best_distance := INF
		for rotor: Dictionary in model.rotors:
			var distance := M.norm(M.sub(p, rotor.hub))
			if distance < best_distance:
				best_distance = distance
				best = int(rotor.vector)
		assign.append(best)
	model.prop_vector = assign
	var lateral: Dictionary = model.rotors[3]
	model.lateral_sign = 1.0 if -float(lateral.thrust_axis[1]) >= 0.0 else -1.0
	var gmin: PackedFloat64Array = model.gondola.min
	var gmax: PackedFloat64Array = model.gondola.max
	model.gondola.center = PackedFloat64Array([0.5 * (gmin[0] + gmax[0]), 0.5 * (gmin[1] + gmax[1]), 0.5 * (gmin[2] + gmax[2])])
	var dx := gmax[0] - gmin[0]
	var dy := gmax[1] - gmin[1]
	var dz := gmax[2] - gmin[2]
	model.gondola.areas = PackedFloat64Array([dy * dz, dx * dz, dx * dy])


## Lamb's prolate-spheroid added mass for the volume-equivalent spheroid of the hull's length, at the hull centroid,
## transported to O, plus each fin's flat-plate normal added mass at its centroid. Symmetric positive semidefinite.
static func added_mass_matrix(data: Dictionary, rho: float) -> PackedFloat64Array:
	var a: float = 0.5 * float(data.envelope.length)
	var volume: float = data.envelope.volume
	var b: float = sqrt(3.0 * volume / (4.0 * PI * a))
	if not (b > 0.0 and b < a):
		return PackedFloat64Array()
	var c := spheroid_coefficients(a, b)
	var displaced := rho * volume * float(data.added_mass.hull_scale)
	var i_prime := displaced * (a * a + b * b) / 5.0
	var local := _zero6()
	local[0] = c.k1 * displaced
	local[7] = c.k2 * displaced
	local[14] = c.k2 * displaced
	local[28] = c.k_rot * i_prime
	local[35] = c.k_rot * i_prime
	# Transport from the hull centre C to O: nu_C = T nu_O with T = [[I, -S(r_c)], [0, I]].
	var r_c: PackedFloat64Array = data.envelope.centroid
	var t := _zero6()
	for i in 6:
		t[i * 6 + i] = 1.0
	var s := _skew(r_c)
	for r in 3:
		for col in 3:
			t[r * 6 + 3 + col] = -s[r * 3 + col]
	var result := _congruence(local, t)
	for fin: Dictionary in data.fins:
		# Strip-theory flat plate: rho * pi * (c/2)^2 per unit span, i.e. rho * pi * c * area / 4.
		var area: float = float(fin.area_fixed) + float(fin.area_moving)
		var plate := float(data.added_mass.fin_coefficient) * rho * PI * 0.25 * float(fin.chord) * area
		var n: PackedFloat64Array = fin.normal
		var rn := M.cross(fin.centroid, n)
		var j := PackedFloat64Array([n[0], n[1], n[2], rn[0], rn[1], rn[2]])
		for r in 6:
			for col in 6:
				result[r * 6 + col] += plate * j[r] * j[col]
	return result


## Lamb's inertia coefficients for a prolate spheroid with semi-axes a > b (axial, transverse, transverse rotation).
static func spheroid_coefficients(a: float, b: float) -> Dictionary:
	var ecc := sqrt(1.0 - (b * b) / (a * a))
	var log_term := M.log_((1.0 + ecc) / (1.0 - ecc))
	var e2 := ecc * ecc
	var e3 := e2 * ecc
	var alpha0 := 2.0 * (1.0 - e2) / e3 * (0.5 * log_term - ecc)
	var beta0 := 1.0 / e2 - (1.0 - e2) / (2.0 * e3) * log_term
	var k1 := alpha0 / (2.0 - alpha0)
	var k2 := beta0 / (2.0 - beta0)
	var k_rot := e2 * e2 * (beta0 - alpha0) / ((2.0 - e2) * (2.0 * e2 - (2.0 - e2) * (beta0 - alpha0)))
	return {k1 = k1, k2 = k2, k_rot = k_rot, eccentricity = ecc}


# --- helpers ---------------------------------------------------------------------------------

static func _hull_stations(profile: PackedFloat64Array, crossflow: float) -> PackedFloat64Array:
	# [x, 2*R*dx*Cdc_eff] per interior strip: the crossflow drag weight of each slice.
	var out := PackedFloat64Array()
	var stations := profile.size() / 2
	for i in stations - 1:
		var dx := absf(profile[2 * i + 2] - profile[2 * i])
		var r := 0.5 * (profile[2 * i + 1] + profile[2 * i + 3])
		out.append(0.5 * (profile[2 * i] + profile[2 * i + 2]))
		out.append(2.0 * r * dx * crossflow)
	return out


static func _bound_radius(data: Dictionary) -> float:
	var radius := 0.0
	for key: String in ["hull_points", "prop_points"]:
		var pts: PackedFloat64Array = data.contacts[key]
		for i in pts.size() / 3:
			radius = maxf(radius, M.norm(pts.slice(3 * i, 3 * i + 3)))
	for gear: Dictionary in data.contacts.gear:
		radius = maxf(radius, M.norm(gear.point))
	return radius


static func _add_point(mass: float, r: PackedFloat64Array, inertia: PackedFloat64Array, first: PackedFloat64Array) -> void:
	first[0] += mass * r[0]
	first[1] += mass * r[1]
	first[2] += mass * r[2]
	inertia[0] += mass * (r[1] * r[1] + r[2] * r[2])
	inertia[1] += mass * (r[0] * r[0] + r[2] * r[2])
	inertia[2] += mass * (r[0] * r[0] + r[1] * r[1])
	inertia[3] -= mass * r[0] * r[1]
	inertia[4] -= mass * r[0] * r[2]
	inertia[5] -= mass * r[1] * r[2]


static func _inertia_matrix(j: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([j[0], j[3], j[4], j[3], j[1], j[5], j[4], j[5], j[2]])


static func _skew(a: PackedFloat64Array) -> PackedFloat64Array:
	# S(a) b = a x b, row-major 3x3.
	return PackedFloat64Array([0.0, -a[2], a[1], a[2], 0.0, -a[0], -a[1], a[0], 0.0])


static func _zero6() -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(36)
	return out


static func _congruence(a: PackedFloat64Array, t: PackedFloat64Array) -> PackedFloat64Array:
	# T^T A T for 6x6 row-major matrices.
	var at := _zero6()
	for r in 6:
		for c in 6:
			var v := 0.0
			for k in 6:
				v += a[r * 6 + k] * t[k * 6 + c]
			at[r * 6 + c] = v
	var out := _zero6()
	for r in 6:
		for c in 6:
			var v := 0.0
			for k in 6:
				v += t[k * 6 + r] * at[k * 6 + c]
			out[r * 6 + c] = v
	return out


static func _check_geometry(d: Dictionary, e: PackedStringArray) -> void:
	var profile: PackedFloat64Array = d.envelope.radius_profile
	for i in profile.size() / 2 - 1:
		if not (profile[2 * i + 2] < profile[2 * i]):
			e.append("radius profile x must decrease monotonically from nose to tail")
			return
	if absf(profile[0] - profile[profile.size() - 2] - float(d.envelope.length)) > 0.02 * float(d.envelope.length):
		e.append("radius profile length disagrees with envelope length")
	for fin: Dictionary in d.fins:
		if absf(M.dot(fin.normal, fin.span_dir)) > 0.05:
			e.append("fin %s normal is not perpendicular to its span" % fin.id)
	for i in 3:
		if not (d.gondola.min[i] < d.gondola.max[i]):
			e.append("gondola bounds are inverted")
	var ocv: PackedFloat64Array = d.battery.ocv
	if ocv.size() < 4 or ocv[0] != 0.0 or ocv[ocv.size() - 2] != 1.0:
		e.append("battery OCV table must span state of charge 0..1")
	for i in ocv.size() / 2 - 1:
		if not (ocv[2 * i + 2] > ocv[2 * i]) or not (ocv[2 * i + 3] >= ocv[2 * i + 1]):
			e.append("battery OCV table must be increasing")
			return


static func _q(src: Dictionary, key: String, unit: String, e: PackedStringArray, lo: float, hi: float) -> float:
	var item: Variant = src.get(key)
	if not _quantity_header(item, key, unit, e):
		return 0.0
	var value: Variant = item.value
	if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value)) or float(value) < lo or float(value) > hi:
		e.append("%s must be a finite number in [%s, %s] %s" % [key, lo, hi, unit])
		return 0.0
	return float(value)


static func _qv(src: Dictionary, key: String, unit: String, size: int, e: PackedStringArray) -> PackedFloat64Array:
	var item: Variant = src.get(key)
	if not _quantity_header(item, key, unit, e):
		return _zeros(size)
	return _numbers(item.value, key, size, e)


static func _quantity_header(item: Variant, key: String, unit: String, e: PackedStringArray) -> bool:
	if typeof(item) != TYPE_DICTIONARY or not item.has_all(["value", "unit", "kind", "source"]) or item.size() != 4:
		e.append("%s must be a quantity {value, unit, kind, source}" % key)
		return false
	if item.unit != unit:
		e.append("%s unit must be '%s'" % [key, unit])
		return false
	if not KINDS.has(item.kind) or typeof(item.source) != TYPE_STRING or str(item.source).strip_edges().is_empty():
		e.append("%s needs a known kind and a source" % key)
		return false
	return true


static func _numbers(value: Variant, key: String, size: int, e: PackedStringArray) -> PackedFloat64Array:
	if typeof(value) != TYPE_ARRAY or value.size() != size:
		e.append("%s must hold %d numbers" % [key, size])
		return _zeros(size)
	var out := PackedFloat64Array()
	for v: Variant in value:
		if typeof(v) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(v)) or absf(float(v)) > 1000.0:
			e.append("%s holds a nonfinite or out-of-range number" % key)
			return _zeros(size)
		out.append(float(v))
	return out


static func _profile(src: Dictionary, e: PackedStringArray) -> PackedFloat64Array:
	var item: Variant = src.get("radius_profile")
	if not _quantity_header(item, "radius_profile", "m", e):
		return PackedFloat64Array()
	var out := PackedFloat64Array()
	if typeof(item.value) != TYPE_ARRAY or item.value.size() < 9 or item.value.size() > MAX_STATIONS:
		e.append("radius_profile needs 9..%d [x, r] stations" % MAX_STATIONS)
		return out
	for pair: Variant in item.value:
		var p := _numbers(pair, "radius_profile station", 2, e)
		if p[1] < 0.0:
			e.append("radius_profile radius must be nonnegative")
		out.append_array(p)
	return out


static func _ocv_table(src: Dictionary, e: PackedStringArray) -> PackedFloat64Array:
	var item: Variant = src.get("cell_ocv")
	if not _quantity_header(item, "cell_ocv", "V", e):
		return PackedFloat64Array()
	var out := PackedFloat64Array()
	if typeof(item.value) != TYPE_ARRAY or item.value.size() < 2 or item.value.size() > 32:
		e.append("cell_ocv needs 2..32 [soc, volts] rows")
		return out
	for pair: Variant in item.value:
		out.append_array(_numbers(pair, "cell_ocv row", 2, e))
	return out


static func _points(src: Dictionary, key: String, e: PackedStringArray) -> PackedFloat64Array:
	var item: Variant = src.get(key)
	if not _quantity_header(item, key, "m", e):
		return PackedFloat64Array()
	var out := PackedFloat64Array()
	if typeof(item.value) != TYPE_ARRAY or item.value.is_empty() or item.value.size() > MAX_POINTS:
		e.append("%s needs 1..%d points" % [key, MAX_POINTS])
		return out
	for p: Variant in item.value:
		out.append_array(_numbers(p, key, 3, e))
	return out


static func _unit(v: PackedFloat64Array, label: String, e: PackedStringArray) -> PackedFloat64Array:
	var n := M.norm(v)
	if absf(n - 1.0) > 1e-3:
		e.append(label + " must be a unit vector")
		return v
	return M.scale(v, 1.0 / n)


static func _zeros(size: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(size)
	return out


static func _string(src: Dictionary, key: String, e: PackedStringArray) -> String:
	var value: Variant = src.get(key)
	if typeof(value) != TYPE_STRING or str(value).strip_edges().is_empty():
		e.append("%s must be a nonempty string" % key)
		return ""
	return str(value)


static func _object(src: Dictionary, key: String, e: PackedStringArray) -> Dictionary:
	var value: Variant = src.get(key)
	if typeof(value) != TYPE_DICTIONARY:
		e.append("%s must be an object" % key)
		return {}
	return value


static func _array(src: Dictionary, key: String, e: PackedStringArray) -> Array:
	var value: Variant = src.get(key)
	if typeof(value) != TYPE_ARRAY:
		e.append("%s must be an array" % key)
		return []
	return value


static func _find(items: Array, id: String, label: String, e: PackedStringArray) -> Dictionary:
	var found: Dictionary = {}
	for item: Variant in items:
		if typeof(item) == TYPE_DICTIONARY and item.get("id") == id:
			if not found.is_empty():
				e.append("%s id '%s' is duplicated" % [label, id])
			found = item
	if found.is_empty():
		e.append("%s must declare '%s'" % [label, id])
	return found
