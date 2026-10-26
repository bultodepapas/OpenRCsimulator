extends SceneTree

const Dynamics := preload("res://physics/aircraft_ground_dynamics.gd")
const Data := preload("res://physics/aircraft_data.gd")
const Profile := preload("res://physics/aircraft_ground_profile.gd")
const Hardware := preload("res://physics/wheel_profiles.gd")
const Normal := preload("res://physics/normal_compliance.gd")
const Ground := preload("res://physics/ground_support.gd")
const Geometry := preload("res://physics/wheel_geometry.gd")
const Rotor := preload("res://physics/rotor_coupling.gd")
const RB := preload("res://physics/rigid_body.gd")
const FixedDatum := preload("res://physics/fixed_datum_body.gd")
const M := preload("res://physics/math3d.gd")
const Sim := preload("res://sim/simulation.gd")
const VM := preload("res://sim/vehicle_model.gd")
const GRAVITY := 9.80665
const MASS := 2.0
var _checks := 0
var _failures := 0
var _profile: Dictionary
var _selected: Dictionary
var _prepared: Dictionary
var _flat: Dictionary
var _motion: Array


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	_fixture()
	if _failures:
		quit(1)
		return
	_binding_and_invalid()
	_plane_virtual_work()
	_heightfield_and_airborne()
	_kernel_reference()
	print("Aircraft ground dynamics: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _quantity(value: Variant, unit: String) -> Dictionary:
	return {value = value, unit = unit, kind = "estimated", source = "synthetic normal-stage numerical fixture; no measured aircraft claim"}


func _fixture() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft/jensen_ugly_stik_60.json"))
	var derived := Data.validate_and_derive(raw)
	_check("installed authoring base validates", derived.ok, str(derived.get("errors", [])))
	if not derived.ok: return
	var applied := Hardware.apply_to_model(derived.model)
	var parameters := {format = Normal.FORMAT}
	var values := {stiffness = 500.0, compression_damping = 15.0, rebound_damping = 15.0,
		damping_onset = 0.002, stroke = 0.2, stop_stiffness = 0.0,
		stop_scale = 0.01, stop_exponent = 3.0, stop_damping = 0.0}
	for key: String in values: parameters[key] = _quantity(values[key], Normal.SPECS[key][0])
	var supports: Array = []
	var locations := [M.v3(-0.2, -0.2, 0.0), M.v3(-0.2, 0.2, 0.0), M.v3(0.4, 0.0, 0.0)]
	for index in applied.model.landing_gear.contacts.size():
		var contact: Dictionary = applied.model.landing_gear.contacts[index]
		var hub: PackedFloat64Array = locations[index]
		hub[2] = 0.2 - contact.wheel_radius
		var cg: PackedFloat64Array = derived.model.cg_le
		supports.append({contact_id = contact.id, support_type = "wheel", width_model = "zero_width",
			hub_le = _quantity([cg[0] - hub[0], cg[1] + hub[1], cg[2] - hub[2]], "m"),
			axle_le = _quantity([0.0, -1.0, 0.0], "1"), normal_profile_id = "fixture_normal"})
	var authored := {format = Profile.FORMAT, law = Profile.COUPLED_LAW,
		capabilities = {support = "wheels", shape = "thin_ring", normal = "effective_leg_tire"},
		wheel_profile_ref = {format = Hardware.FORMAT, profile_id = raw.id, profile_sha256 = applied.identity.profile_sha256},
		normal_profiles = [{id = "fixture_normal", parameters = parameters}], supports = supports}
	var resolved := Profile.resolve(authored, derived.model)
	_check("synthetic authored supports resolve without launch claim", resolved.ok and not resolved.launch_available, str(resolved.get("errors", [])))
	if not resolved.ok: return
	_profile = resolved.profile
	_selected = resolved.model
	_prepared = Dynamics.prepare(_profile, _selected)
	_check("support stage binds selected hardware", _prepared.ok, str(_prepared))
	_flat = Ground.prepare_legacy(PackedFloat64Array())
	_motion = _motions(_prepared)


func _motions(prepared: Dictionary) -> Array:
	var rows: Array = []
	for support: Dictionary in prepared.supports:
		rows.append({contact_id = support.contact_id, hub_body = support.hub_body.duplicate(), axle_body = support.axle_body.duplicate(),
			carrier_rate_body = M.v3(0.0, 0.0, 0.0), carrier_accel_body = M.v3(0.0, 0.0, 0.0)})
	return rows


func _body(down := -0.19) -> PackedFloat64Array:
	return RB.make_state(M.v3(0.0, 0.0, down), M.v3(0.0, 0.0, 0.0), M.q_identity(), M.v3(0.0, 0.0, 0.0))


func _binding_and_invalid() -> void:
	var before := var_to_bytes([_profile, _selected, _prepared, _motion, _flat])
	var reverse := _profile.duplicate(true)
	reverse.supports.reverse()
	var rebound := Dynamics.prepare(reverse, _selected)
	_check("authored support order cannot rebind hardware", rebound.ok and rebound.identity == _prepared.identity)
	var reversed_motion := _motion.duplicate(true)
	reversed_motion.reverse()
	var result := Dynamics.evaluate(_prepared, _body(), _flat, 0.0, PackedFloat64Array([5.0, -3.0, 1.0]), reversed_motion)
	_check("stage accepts motion by stable ID", result.ok, str(result))
	if result.ok:
		for index in 3:
			_check("stage arrays retain hardware order %d" % index, result.contacts[index].contact_id == _selected.landing_gear.contacts[index].id
				and result.contacts[index].contact_index == index and _prepared.supports[index].radius_m == _selected.landing_gear.contacts[index].wheel_radius)
		_check("stationary spring force points upward", result.loads[2] < 0.0 and absf(result.loads[0]) + absf(result.loads[1]) == 0.0)
	_check("prepare/evaluate leave all source arrays byte-identical", before == var_to_bytes([_profile, _selected, _prepared, _motion, _flat]))
	var invalid := _profile.duplicate(true)
	invalid.wheel_profile_identity.profile_sha256 = "0".repeat(64)
	_check("mismatched selected profile pin rejects", not Dynamics.prepare(invalid, _selected).ok)
	invalid = _profile.duplicate(true)
	invalid.supports[0].contact_id = "other"
	_check("index plus physical contact ID both bind", not Dynamics.prepare(invalid, _selected).ok)
	var hardware := _selected.duplicate(true)
	hardware.landing_gear.contacts[0].wheel_radius += 0.001
	_check("normalized hardware radius must match source quantity", not Dynamics.prepare(_profile, hardware).ok)
	invalid = _profile.duplicate(true)
	invalid.supports[0].normal.values.stiffness *= 2.0
	_check("prepared compliance tampering rejects", not Dynamics.prepare(invalid, _selected).ok)
	var body := _body()
	body[6] = 1.00001
	var nonunit_before := body.duplicate()
	var normalized_stage := Dynamics.evaluate(_prepared, body, _flat, 0.0, PackedFloat64Array([0, 0, 0]), _motion)
	var exact_stage := Dynamics.evaluate(_prepared, _body(), _flat, 0.0, PackedFloat64Array([0, 0, 0]), _motion)
	_check("nonunit RK stage uses local orthonormal geometry without mutation", normalized_stage.ok and normalized_stage.loads == exact_stage.loads and body == nonunit_before)
	body[6] = 0.0
	_check("degenerate quaternion rejects", not Dynamics.evaluate(_prepared, body, _flat, 0.0, PackedFloat64Array([0, 0, 0]), _motion).ok)
	body = _body()
	body[4] = NAN
	_check("nonfinite state rejects", not Dynamics.evaluate(_prepared, body, _flat, 0.0, PackedFloat64Array([0, 0, 0]), _motion).ok)
	_check("spin size rejects", not Dynamics.evaluate(_prepared, _body(), _flat, 0.0, PackedFloat64Array([0, 0]), _motion).ok)
	_check("negative stage time rejects", not Dynamics.evaluate(_prepared, _body(), _flat, -1.0, PackedFloat64Array([0, 0, 0]), _motion).ok)
	var moving := _motion.duplicate(true)
	moving[0].hub_body[0] += 1e-12
	_check("any moving hub rejects explicitly", Dynamics.evaluate(_prepared, _body(), _flat, 0.0, PackedFloat64Array([0, 0, 0]), moving).get("status") == "unsupported_moving_hub")
	moving = _motion.duplicate(true)
	moving[0].carrier_rate_body[0] = INF
	_check("nonfinite prescribed carrier motion rejects", not Dynamics.evaluate(_prepared, _body(), _flat, 0.0, PackedFloat64Array([0, 0, 0]), moving).ok)
	moving = _motion.duplicate(true)
	moving[1].contact_id = moving[0].contact_id
	_check("duplicate motion IDs reject", not Dynamics.evaluate(_prepared, _body(), _flat, 0.0, PackedFloat64Array([0, 0, 0]), moving).ok)
	var provider := _flat.duplicate(true)
	provider.time_rate = 1.0
	_check("time-dependent geometry cannot masquerade as static", not Dynamics.evaluate(_prepared, _body(), provider, 0.0, PackedFloat64Array([0, 0, 0]), _motion).ok)
	provider = _flat.duplicate(true)
	provider.regions.clear()
	_check("malformed provider identity rejects before airborne cull", not Dynamics.evaluate(_prepared, _body(-100.0), provider, 0.0, PackedFloat64Array([0, 0, 0]), _motion).ok)


func _advance(body: PackedFloat64Array, row: Dictionary, dt: float) -> Dictionary:
	# Independent first-order physical pose path, evaluated symmetrically. Axle
	# evolves by nu; body attitude by omega. No dynamics derivative is reused.
	var moved := body.duplicate()
	var q := body.slice(6, 10)
	var omega := body.slice(10, 13)
	var world_velocity := M.q_rotate(q, body.slice(3, 6))
	for k in 3: moved[k] += dt * world_velocity[k]
	moved = _with_quaternion(moved, M.q_mul(q, _rotation(omega, dt)))
	var motion := row.duplicate(true)
	motion.axle_body = M.q_rotate(_rotation(row.carrier_rate_body, dt), row.axle_body)
	return {body = moved, motion = motion}


func _with_quaternion(body: PackedFloat64Array, q: PackedFloat64Array) -> PackedFloat64Array:
	for k in 4: body[6 + k] = q[k]
	return body


func _rotation(rate: PackedFloat64Array, dt: float) -> PackedFloat64Array:
	return M.q_identity() if M.norm(rate) == 0.0 else M.q_from_axis_angle(M.scale(rate, 1.0 / M.norm(rate)), M.norm(rate) * dt)


func _plane_for(body: PackedFloat64Array, row: Dictionary, radius: float, point: PackedFloat64Array, n: PackedFloat64Array) -> Dictionary:
	var q := body.slice(6, 10)
	return Geometry.plane(M.add(body.slice(0, 3), M.q_rotate(q, row.hub_body)), M.q_rotate(q, row.axle_body), radius, point, n)


func _independent_plane_gap(body: PackedFloat64Array, row: Dictionary, radius: float, point: PackedFloat64Array, n: PackedFloat64Array) -> float:
	var q := M.q_normalized(body.slice(6, 10))
	var hub := M.add(body.slice(0, 3), M.q_rotate(q, row.hub_body))
	var a := M.q_rotate(q, row.axle_body)
	return M.dot(M.sub(hub, point), n) - radius * sqrt(1.0 - pow(M.dot(a, n), 2))


func _plane_virtual_work() -> void:
	var worst_rate := 0.0
	var worst_work := 0.0
	var worst_balance := 0.0
	var transverse_seen := false
	for trial in 12:
		var body := _with_quaternion(_body(), M.q_from_euler(0.17 * trial, -0.3 + 0.035 * trial, 0.22 - 0.041 * trial))
		for k in 3:
			body[3 + k] = [0.4, -0.2, 0.06][k]
			body[10 + k] = [-0.13, 0.17, 0.21][k]
		var row: Dictionary = _motion[0].duplicate(true)
		row.carrier_rate_body = M.v3(0.2, -0.11, 0.07)
		var h_n: float = (-1.0 if trial % 2 else 1.0) * (0.1 + 0.01 * trial)
		var h_e: float = (-1.0 if trial % 3 else 1.0) * 0.15
		var n := M.scale(M.v3(-h_n, -h_e, -1.0), 1.0 / sqrt(1.0 + h_n * h_n + h_e * h_e))
		var support: Dictionary = _prepared.supports[0]
		var hub := M.add(body.slice(0, 3), M.q_rotate(body.slice(6, 10), row.hub_body))
		var a := M.q_rotate(body.slice(6, 10), row.axle_body)
		var reach: float = support.radius_m * sqrt(1.0 - pow(M.dot(a, n), 2))
		var point := M.sub(hub, M.scale(n, reach - 0.01))
		var geometry := _plane_for(body, row, support.radius_m, point, n)
		_check("arbitrary attitude and two-axis slope exact plane %d" % trial, geometry.ok)
		if not geometry.ok: continue
		var sample := {environment_identity = "synthetic-plane", geometry_id = "exact-plane-oracle", region_id = "plane", material_id = "unspecified", material_resolved = false}
		var response := Dynamics._normal_contact(support, body, row, 23.0, geometry, sample)
		var epsilon := 1e-6
		var plus := _advance(body, row, epsilon)
		var minus := _advance(body, row, -epsilon)
		var gp := _plane_for(plus.body, plus.motion, support.radius_m, point, n)
		var gm := _plane_for(minus.body, minus.motion, support.radius_m, point, n)
		var fd_rate: float = (_independent_plane_gap(plus.body, plus.motion, support.radius_m, point, n)
			- _independent_plane_gap(minus.body, minus.motion, support.radius_m, point, n)) / (2.0 * epsilon)
		var record: Dictionary = response.record
		worst_rate = maxf(worst_rate, absf(fd_rate - record.gap_rate_mps))
		worst_work = maxf(worst_work, absf(record.virtual_work_residual_w))
		worst_balance = maxf(worst_balance, absf(record.power_balance_residual_w))
		_check("ring normal has zero axial spin work %d" % trial, absf(record.axial_normal_torque_nm) < 1e-14 and absf(record.spin_external_power_w) < 1e-12)
		_check("force is exact gap-normal gradient %d" % trial, M.norm(M.sub(M.q_rotate(body.slice(6, 10), record.force_body_n), M.scale(n, record.normal_load_n))) < 1e-12)
		_check("point velocity includes full carrier and relative spin %d" % trial, absf(M.dot(n, record.point_velocity_ned_mps) - record.gap_rate_mps) < 1e-12)
		transverse_seen = transverse_seen or M.norm(record.rotor_couple_body_nm) > 1e-5
		# Independent spring potential directional difference, including full shape motion.
		var up := Normal.evaluate(support.normal, -gp.signed_gap_m, 0.0)
		var um := Normal.evaluate(support.normal, -gm.signed_gap_m, 0.0)
		_check("potential directional derivative agrees with force geometry %d" % trial, absf((up.potential_j - um.potential_j) / (2.0 * epsilon) - record.potential_rate_w) < 2e-7)
	_check("independent plane envelope rate closes", worst_rate < 2e-9, str(worst_rate))
	_check("normal external power includes transverse carrier work once", transverse_seen and worst_work < 2e-12, str(worst_work))
	_check("unilateral spring and damper energy ledger closes", worst_balance < 2e-12, str(worst_balance))
	print("GP11 plane oracle: gap_rate_error_mps=", worst_rate, " virtual_work_error_W=", worst_work, " normal_balance_W=", worst_balance)
	var support: Dictionary = _prepared.supports[0]
	var row: Dictionary = _motion[0]
	var tangent := _body()
	tangent[3] = 4.0
	tangent[4] = -3.0
	var plane := Geometry.plane(M.add(tangent.slice(0, 3), row.hub_body), row.axle_body, support.radius_m, M.v3(0, 0, 0), M.v3(0, 0, -1))
	var metadata := {environment_identity = "synthetic-plane", geometry_id = "exact-plane-oracle", region_id = "plane", material_id = "unspecified", material_resolved = false}
	var response := Dynamics._normal_contact(support, tangent, row, 50.0, plane, metadata)
	_check("pure tangent motion has no normal damper or spin work", response.ok and response.record.gap_rate_mps == 0.0 and response.record.dissipation_w == 0.0 and response.record.normal_external_power_w == 0.0)
	tangent[5] = -3.0
	response = Dynamics._normal_contact(support, tangent, row, 50.0, plane, metadata)
	_check("rebound force clipping retains exact signed energy loss", response.ok and response.record.clipped and response.record.normal_load_n == 0.0
		and response.record.dissipation_w > 0.0 and absf(response.record.power_balance_residual_w) < 1e-12)


func _heightfield_and_airborne() -> void:
	var tables := PackedFloat64Array([-INF, INF, -INF, INF, 0.8, 1.0])
	var curved := Ground.prepare_explicit(tables, PackedFloat64Array([0.00005]), [{region_id = "curved_synthetic", usage_id = "fixture", material_id = "dry_pavement"}])
	_check("curved static provider prepares", curved.ok, str(curved))
	if not curved.ok: return
	var body := _with_quaternion(_body(-0.18), M.q_from_euler(0.2, 0.04, -0.03))
	body[0] = 0.17
	body[1] = -0.22
	body[3] = 0.3
	body[4] = 0.2
	body[5] = 0.1
	body[10] = 0.12
	body[11] = -0.09
	body[12] = 0.05
	var rows := _motion.duplicate(true)
	for row: Dictionary in rows: row.carrier_rate_body = M.v3(0.08, 0.03, -0.04)
	var result := Dynamics.evaluate(_prepared, body, curved, 0.7, PackedFloat64Array([10.0, -20.0, 30.0]), rows)
	_check("analytic curved support stage converges", result.ok, str(result))
	var worst := 0.0
	if result.ok:
		for index in 3:
			var plus := _advance(body, rows[index], 1e-6)
			var minus := _advance(body, rows[index], -1e-6)
			var support: Dictionary = _prepared.supports[index]
			var qp: PackedFloat64Array = plus.body.slice(6, 10)
			var qm: PackedFloat64Array = minus.body.slice(6, 10)
			var gp := Geometry.heightfield(curved, M.add(plus.body.slice(0, 3), M.q_rotate(qp, support.hub_body)), M.q_rotate(qp, plus.motion.axle_body), support.radius_m, 0.7)
			var gm := Geometry.heightfield(curved, M.add(minus.body.slice(0, 3), M.q_rotate(qm, support.hub_body)), M.q_rotate(qm, minus.motion.axle_body), support.radius_m, 0.7)
			_check("curved directional oracle is independently admissible %d" % index, gp.ok and gm.ok)
			if not gp.ok or not gm.ok: continue
			var record: Dictionary = result.contacts[index]
			worst = maxf(worst, absf((gp.signed_gap_m - gm.signed_gap_m) / 2e-6 - record.gap_rate_mps))
			var sampled := Ground.sample(curved, record.surface_point_ned, M.v3(0, 0, 0), 0.7)
			_check("material metadata belongs to solved footpoint %d" % index, sampled.material_id == record.material_id and sampled.region_id == record.region_id and sampled.environment_identity == record.environment_identity)
			_check("curved normal work closes %d" % index, absf(record.virtual_work_residual_w) < 1e-11 and absf(record.power_balance_residual_w) < 1e-11)
	_check("curved exact envelope Jacobian matches independent pose path", worst < 2e-8, str(worst))
	print("GP11 curved oracle gap_rate_error_mps=", worst)
	var regions := Ground.prepare_explicit(PackedFloat64Array([-100, 100, -100, 0, 0.8, 1.0, -INF, INF, -INF, INF, 0.8, 1.0]),
		PackedFloat64Array([0.0, 0.0]), [{region_id = "left", usage_id = "fixture", material_id = "dry_pavement"},
		{region_id = "outside", usage_id = "fixture", material_id = "unspecified"}])
	var camber := _with_quaternion(_body(-0.1), M.q_from_euler(0.0, 0.0, 0.3))
	var rotated_hub := M.q_rotate(camber.slice(6, 10), _prepared.supports[0].hub_body)
	camber[1] = -rotated_hub[1] + 0.5 * _prepared.supports[0].radius_m * sin(0.3)
	var regional := Dynamics.evaluate(_prepared, camber, regions, 0.0, PackedFloat64Array([0, 0, 0]), _motion)
	_check("material regions independent of identical flat geometry prepare", regional.ok, str(regional))
	if regional.ok:
		var record: Dictionary = regional.contacts[0]
		var wrong_hub_sample := Ground.sample(regions, record.hub_ned, M.v3(0, 0, 0), 0.0)
		_check("material uses solved ring footpoint across a region boundary", record.hub_ned[1] > 0.0 and record.surface_point_ned[1] < 0.0
			and record.region_id == "left" and record.material_resolved and wrong_hub_sample.region_id == "outside" and not wrong_hub_sample.material_resolved)
	# A nearly vertical axle is not a qualified unique contact branch, but a
	# geometric altitude proof makes that irrelevant when no contact is possible.
	var high := _with_quaternion(_body(-100.0), M.q_from_euler(0.6, -0.5, 1.2))
	var vertical := M.q_rotate(M.q_conj(high.slice(6, 10)), M.v3(0, 0, 1))
	var high_rows := _motion.duplicate(true)
	for row: Dictionary in high_rows: row.axle_body = vertical.duplicate()
	var airborne := Dynamics.evaluate(_prepared, high, curved, 0.0, PackedFloat64Array([50, 0, -10]), high_rows)
	_check("100 m high-bank degenerate axle uses certified no-support", airborne.ok and airborne.loads == PackedFloat64Array([0, 0, 0, 0, 0, 0]), str(airborne))
	if airborne.ok:
		for record: Dictionary in airborne.contacts:
			_check("airborne report makes no exact footpoint/normal/gap claim", record.geometry_status == "certified_airborne" and record.gap_lower_bound_m > 99.0
				and not record.has("gap_m") and not record.has("point_ned") and not record.has("normal_ned"))
		_check("airborne rotors retain prescribed axes and zero couples", airborne.axes_body.size() == 9 and M.norm(airborne.external_rotor_couples) == 0.0
			and airborne.potential_j == 0.0 and airborne.dissipation_w == 0.0)
	var near_vertical := Dynamics.evaluate(_prepared, _body(-0.1), _flat, 0.0, PackedFloat64Array([0, 0, 0]), _vertical_motions())
	_check("degenerate axis faults only when support may occur", not near_vertical.ok)
	var pair := ""
	for d in [-0.200000001, -0.2, -0.199999999]:
		var entry := Dynamics.evaluate(_prepared, _body(d), _flat, 0.0, PackedFloat64Array([0, 0, 0]), _motion)
		_check("geometric cull boundary is admissible %s" % d, entry.ok, str(entry))
		if not entry.ok: continue
		if pair.is_empty(): pair = entry.contacts[0].pair_id
		_check("contact pair identity survives broadphase transition", pair == entry.contacts[0].pair_id)
		var expected := maxf(0.0, d + 0.2) * 1500.0
		_check("cull/full-neighbor normal force is continuous and equal to full geometry", absf(entry.loads[2] + expected) < 2e-13, str(entry.loads))
	var malformed := curved.duplicate(true)
	malformed.relief_m[0] = 100.0
	_check("airborne proof cannot bypass malformed relief", not Dynamics.evaluate(_prepared, high, malformed, 0.0, PackedFloat64Array([0, 0, 0]), high_rows).ok)


func _vertical_motions() -> Array:
	var rows := _motion.duplicate(true)
	for row: Dictionary in rows: row.axle_body = M.v3(0, 0, 1)
	return rows


func _inventory() -> Dictionary:
	# A coherent CLOSED synthetic mass inventory: wheel masses are thin solid
	# disks, hubs fixed, rest centroid balances CG exactly at datum O. Intrinsic
	# rotor C is added once; hub orbital inertia remains in the carrier tensor.
	var axial := PackedFloat64Array()
	var transverse := PackedFloat64Array()
	var axes := PackedFloat64Array()
	var masses := PackedFloat64Array()
	var weighted := M.v3(0, 0, 0)
	var rest_mass := MASS - 0.1 # shaft mass at O
	for support: Dictionary in _prepared.supports:
		axial.append(support.axial_inertia_kgm2)
		transverse.append(0.5 * support.axial_inertia_kgm2)
		axes.append_array(support.axle_body)
		var mass: float = 2.0 * support.axial_inertia_kgm2 / pow(support.radius_m, 2)
		masses.append(mass)
		rest_mass -= mass
		weighted = M.add(weighted, M.scale(support.hub_body, mass))
	axial.append(0.01)
	transverse.append(0.005)
	axes.append_array(M.v3(1, 0, 0))
	var carrier := PackedFloat64Array([0.2, 0.3, 0.4, 0, 0, 0])
	_add_orbital(carrier, M.scale(weighted, -1.0 / rest_mass), rest_mass)
	for i in 3: _add_orbital(carrier, _prepared.supports[i].hub_body, masses[i])
	var locked := carrier.duplicate()
	for i in 4:
		var a := axes.slice(3 * i, 3 * i + 3)
		for k in 3: locked[k] += transverse[i] + (axial[i] - transverse[i]) * a[k] * a[k]
		locked[3] += (axial[i] - transverse[i]) * a[0] * a[1]
		locked[4] += (axial[i] - transverse[i]) * a[0] * a[2]
		locked[5] += (axial[i] - transverse[i]) * a[1] * a[2]
	var prepared := Rotor.prepare_system(locked, axial, transverse, axes, {partition_id = "synthetic-closed-drop", reference_pose_id = "fixed-hubs", kind = "estimated", source = "test-only coherent disks/rest inventory"})
	_check("synthetic mass and rotor partition are coherent/physical", rest_mass > 0.0 and prepared.ok)
	return {system = prepared, carrier = carrier, locked = locked, axial = axial, transverse = transverse, axes = axes}


func _add_orbital(tensor: PackedFloat64Array, r: PackedFloat64Array, mass: float) -> void:
	for k in 3: tensor[k] += mass * (M.dot(r, r) - r[k] * r[k])
	tensor[3] -= mass * r[0] * r[1]
	tensor[4] -= mass * r[0] * r[2]
	tensor[5] -= mass * r[1] * r[2]


func _mechanics(inv: Dictionary, body: PackedFloat64Array, local: PackedFloat64Array, contact: Dictionary) -> Dictionary:
	var ext: PackedFloat64Array = contact.external_rotor_couples.duplicate()
	ext.append_array(M.v3(0, 0, 0))
	return Rotor.evaluate_system(inv.system, inv.locked, body.slice(10, 13), local.slice(0, 4), inv.axes,
		PackedFloat64Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), PackedFloat64Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
		contact.loads.slice(3, 6), ext, PackedFloat64Array([0, 0, 0, 0]))


func _energy(inv: Dictionary, body: PackedFloat64Array, local: PackedFloat64Array) -> Dictionary:
	var contact := Dynamics.evaluate(_prepared, body, _flat, 0.0, local.slice(0, 3), _motion)
	if not contact.ok: return {ok = false}
	var mechanics := _mechanics(inv, body, local, contact)
	if not mechanics.ok: return {ok = false}
	return {ok = true, energy = 0.5 * MASS * M.dot(body.slice(3, 6), body.slice(3, 6)) + mechanics.kinetic_energy
		+ contact.potential_j - MASS * GRAVITY * body[2] + local[4], momentum = M.q_rotate(body.slice(6, 10), mechanics.angular_momentum)}


func _kernel_reference() -> void:
	var original_rate := Engine.physics_ticks_per_second
	var inv := _inventory()
	if not inv.system.ok: return
	var inverse := RB.inertia_inverse(inv.locked)
	var properties := {mass_kg = MASS, cg_body_m = M.v3(0, 0, 0), inertia = inv.locked, inverse = inverse}
	var sag := MASS * GRAVITY / 1500.0
	var equilibrium := Dynamics.evaluate(_prepared, _body(-0.2 + sag), _flat, 0.0, PackedFloat64Array([0, 0, 0]), _motion)
	_check("analytic gravity sag balances weight and moment", equilibrium.ok and absf(equilibrium.loads[2] + MASS * GRAVITY) < 1e-12 and M.norm(equilibrium.loads.slice(3, 6)) < 1e-12)
	var previous_energy := INF
	var previous_h := INF
	for sag_only in [true, false]:
		previous_energy = INF
		previous_h = INF
		for rate in ([240] if sag_only else [120, 240, 480]):
			Engine.physics_ticks_per_second = rate
			var sim := Sim.new()
			sim.mass = MASS
			sim.inertia = inv.locked
			sim.gravity = GRAVITY
			sim.continuous = PackedFloat64Array([4.0, -3.0, 2.0, 20.0, 0.0, 0.0, 0.0, 0.0]) # 4 relative spins, heat, world angular impulse
			var model := VM.new()
			model.continuous_size = 8
			model.identity = {law = Dynamics.LAW, fixture = "synthetic-coherent-fixed-hub-closed-rotors"}
			model.stage = func(body: PackedFloat64Array, values: PackedFloat64Array, time: float) -> Dictionary:
				var contact := Dynamics.evaluate(_prepared, body, _flat, time, values.slice(0, 3), _motion)
				if not contact.ok: return {loads = PackedFloat64Array()}
				var mechanics := _mechanics(inv, body, values, contact)
				if not mechanics.ok: return {loads = PackedFloat64Array()}
				# ONE common rotor solve supplies final alpha. The shared datum
				# adapter composes translation/gravity with the same local-q extension.
				var derivative := FixedDatum.derivative_with_angular_acceleration(body, properties, contact.loads.slice(0, 3), GRAVITY, mechanics.angular_acceleration)
				var local: PackedFloat64Array = mechanics.spin_acceleration.duplicate()
				local.append(contact.dissipation_w)
				local.append_array(M.q_rotate(body.slice(6, 10), contact.loads.slice(3, 6)))
				return {loads = contact.loads, derivative = local, body_derivative = derivative, rotor_momentum = M.v3(0, 0, 0)}
			var initial := _body(-0.2 + sag if sag_only else -0.24)
			if not sag_only:
				initial = _with_quaternion(initial, M.q_from_euler(0.05, -0.02, 0.03))
				initial[3] = 0.2
				initial[4] = -0.1
				initial[10] = 0.04
				initial[11] = -0.03
				initial[12] = 0.02
			var installed := sim.set_model(model) and sim.reset(initial)
			_check("actual kernel normal plus simultaneous rotor fixture installs %s/%d" % [sag_only, rate], installed, sim.fault_reason)
			if not installed:
				sim.free()
				continue
			var start := _energy(inv, initial, sim.continuous)
			var max_energy := 0.0
			var max_h := 0.0
			var monotone := true
			var last_heat := 0.0
			for tick in rate:
				sim.step()
				if not sim.fault_reason.is_empty(): break
				var now := _energy(inv, sim.state, sim.continuous)
				if not now.ok: break
				max_energy = maxf(max_energy, absf(now.energy - start.energy))
				max_h = maxf(max_h, M.norm(M.sub(M.sub(now.momentum, start.momentum), sim.continuous.slice(5, 8))))
				monotone = monotone and sim.continuous[4] >= last_heat - 1e-13
				last_heat = sim.continuous[4]
			_check("same-kernel sag/drop completes %s/%d" % [sag_only, rate], sim.tick == rate and sim.fault_reason.is_empty(), sim.fault_reason)
			_check("normal damper heat is monotone %s/%d" % [sag_only, rate], monotone and (last_heat > 0.01 if not sag_only else last_heat < 1e-20), str(last_heat))
			if sag_only:
				_check("gravity sag remains at analytic equilibrium through kernel", M.norm(M.sub(sim.state.slice(0, 3), initial.slice(0, 3))) < 1e-12 and M.norm(sim.state.slice(10, 13)) < 1e-12)
			else:
				_check("energy plus heat is bounded %d" % rate, max_energy < 0.005, str(max_energy))
				_check("total world angular momentum minus external impulse closes %d" % rate, max_h < 2e-7, str(max_h))
				_check("energy ledger converges under refinement %d" % rate, max_energy < previous_energy, str(max_energy))
				_check("world momentum ledger converges under refinement %d" % rate, max_h < previous_h, str(max_h))
				previous_energy = max_energy
				previous_h = max_h
			print("GP11 kernel sag=", sag_only, " rate_Hz=", rate, " energy_heat_error_J=", max_energy, " H_impulse_error_Nms=", max_h, " damper_heat_J=", last_heat)
			sim.free()
	Engine.physics_ticks_per_second = original_rate
