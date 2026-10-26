extends SceneTree

const A := preload("res://physics/aircraft_ground_impulse.gd")
const RC := preload("res://physics/rotor_coupling.gd")
const M := preload("res://physics/math3d.gd")
const GC := preload("res://physics/generalized_coordinates.gd")
const RB := preload("res://physics/rigid_body.gd")
const Sim := preload("res://sim/simulation.gd")
const Model := preload("res://sim/vehicle_model.gd")
var _checks := 0
var _failures := 0
var _capture_fixture_spin := .1


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	_analytic_spinup()
	_brake_and_carrier_work()
	_rows()
	_coupled_network()
	_capacity()
	_validation_and_zero_rows()
	_default_sentinel()
	_capture_scalar()
	_capture_network()
	_capture_rejections()
	_capture_checkpoint()
	print("Aircraft ground impulse: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _p(values: Array) -> PackedFloat64Array:
	return PackedFloat64Array(values)


func _default_sentinel() -> void:
	var stage := _stage(_p([30]), _zeros(3))
	var row := A.internal_brake(0, 1)
	var out := A.apply(stage, 2, _zeros(3), row.row, _p([0]), _p([1]), [PackedInt32Array([0])])
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(out))
	_check("empty capture option preserves frozen default output bytes", hash.finish().hex_encode() == "ac7e297c879541e68a81e48e3357cdc4f3ff5df6ddbaeae018c7d4abf6073b16")


func _zeros(n: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(n)
	return out


func _stage(spin: PackedFloat64Array, rates: PackedFloat64Array, omega := PackedFloat64Array([0.0, 0.0, 0.0]), holds: Array = []) -> Dictionary:
	var count := spin.size()
	var axial := _p([.01]) if count == 1 else _p([.03, .04, .01, .06])
	var transverse := _p([.02]) if count == 1 else _p([.02, .025, .007, .04])
	var axes := _p([0, -1, 0]) if count == 1 else _p([0, -1, 0, 0, -1, 0, .6, -.8, 0, 1, 0, 0])
	var locked := _p([1, 1, 1, 0, 0, 0])
	if count > 1:
		locked = _p([1.2, 1.5, 1.8, .02, -.03, .04])
		for i in count:
			var a := axes.slice(3 * i, 3 * i + 3)
			var d := axial[i] - transverse[i]
			locked[0] += transverse[i] + d * a[0] * a[0]
			locked[1] += transverse[i] + d * a[1] * a[1]
			locked[2] += transverse[i] + d * a[2] * a[2]
			locked[3] += d * a[0] * a[1]
			locked[4] += d * a[0] * a[2]
			locked[5] += d * a[1] * a[2]
	var partition := {partition_id = "ground-impulse-fixture", reference_pose_id = "fixed-centers",
		kind = "estimated", source = "analytical fixture, not stock inventory or a measured component split"}
	var prepared := RC.prepare_system(locked, axial, transverse, axes, partition)
	_check("reference rotor system prepares", prepared.ok)
	if not prepared.ok: return {}
	var out := RC.evaluate_system(prepared, locked, omega, spin, axes, rates, _zeros(3 * count),
		_zeros(3), _zeros(3 * count), _zeros(count), holds)
	_check("reference rotor stage evaluates", out.ok, str(out))
	return out.get("stage", {})


func _energy(stage: Dictionary, v: PackedFloat64Array, omega: PackedFloat64Array, spin: PackedFloat64Array, mass: float) -> float:
	# Independent component kinetic energy, not the adapter's mass-work ledger.
	var value := 0.5 * mass * M.dot(v, v) + 0.5 * M.dot(omega, RB.inertia_mul(stage.carrier, omega))
	for i in spin.size():
		var a: PackedFloat64Array = stage.axes.slice(3 * i, 3 * i + 3)
		var absolute := M.add(M.add(omega, stage.carrier_rates.slice(3 * i, 3 * i + 3)), M.scale(a, spin[i]))
		var axial := M.dot(a, absolute)
		value += 0.5 * stage.transverse[i] * M.dot(absolute, absolute) + 0.5 * (stage.axial[i] - stage.transverse[i]) * axial * axial
	return value


func _momentum(stage: Dictionary, omega: PackedFloat64Array, spin: PackedFloat64Array) -> PackedFloat64Array:
	var value := RB.inertia_mul(stage.carrier, omega)
	for i in spin.size():
		var a: PackedFloat64Array = stage.axes.slice(3 * i, 3 * i + 3)
		var absolute := M.add(M.add(omega, stage.carrier_rates.slice(3 * i, 3 * i + 3)), M.scale(a, spin[i]))
		value = M.add(value, M.add(M.scale(absolute, stage.transverse[i]), M.scale(a, (stage.axial[i] - stage.transverse[i]) * M.dot(a, absolute))))
	return value


func _verify(label: String, stage: Dictionary, before_v: PackedFloat64Array, mass: float, out: Dictionary) -> void:
	_check(label + " accepts certified impulse", out.get("ok", false), str(out))
	if not out.get("ok", false): return
	var before := _energy(stage, before_v, stage.velocity.slice(0, 3), stage.velocity.slice(3), mass)
	var after := _energy(stage, out.velocity_cm_body, out.omega, out.spin, mass)
	_check(label + " independent kinetic totals agree", absf(before - out.kinetic_energy_before) < 1e-10 and absf(after - out.kinetic_energy_after) < 1e-10)
	_check(label + " relative loss and prescribed work close physical energy", absf(after - before + out.dissipated_energy - out.total_prescribed_work) < 1e-10
		and absf(out.energy_balance_residual) < 1e-10 and out.dissipated_energy >= 0)
	_check(label + " incremental and total changes agree", absf(after - before - out.kinetic_energy_change) < 1e-10)
	_check(label + " CM impulse is applied exactly once", M.norm(M.sub(M.scale(M.sub(out.velocity_cm_body, before_v), mass), out.generalized_impulse.slice(0, 3))) < 1e-11)
	var delta_h := M.sub(_momentum(stage, out.omega, out.spin), _momentum(stage, stage.velocity.slice(0, 3), stage.velocity.slice(3)))
	_check(label + " coupled wheel/shaft angular momentum matches external impulse", M.norm(M.sub(delta_h, out.generalized_impulse.slice(3, 6))) < 1e-11)
	_check(label + " all spins and frame limitations retained", out.spin.size() == stage.axial.size() and out.delta_spin.size() == stage.axial.size()
		and out.fixed_centers and out.frozen_pose and out.factor_rebuilt)


func _analytic_spinup() -> void:
	var stage := _stage(_p([0]), _zeros(3))
	var row := A.point_tangent(_p([0, 0, .1]), _p([0, 0, .1]), _p([0, -1, 0]), 0, _p([1, 0, 0]), 1)
	var before := var_to_bytes(stage)
	var out := A.apply(stage, 2.0, _p([3, 0, 0]), row.row, _p([row.bias]), _p([10]), [PackedInt32Array([0])])
	_verify("analytic wheel spinup", stage, _p([3, 0, 0]), 2.0, out)
	_check("spinup leaves input stage unchanged", before == var_to_bytes(stage))
	_check("independent spinup answer p=-2, V=2, sigma=20, loss=3", out.get("ok", false)
		and absf(out.impulse[0] + 2) < 1e-12 and absf(out.velocity_cm_body[0] - 2) < 1e-12
		and M.norm(out.omega) < 1e-12 and absf(out.spin[0] - 20) < 1e-11 and absf(out.dissipated_energy - 3) < 1e-12)


func _brake_and_carrier_work() -> void:
	var stage := _stage(_p([30]), _zeros(3))
	var row := A.internal_brake(0, 1)
	var out := A.apply(stage, 2, _zeros(3), row.row, _p([0]), _p([1]), [PackedInt32Array([0])])
	_verify("airborne internal brake", stage, _zeros(3), 2, out)
	_check("brake conserves total angular momentum while wheel and body exchange energy", out.get("ok", false)
		and absf(out.spin[0]) < 1e-11 and absf(out.omega[1] + .3) < 1e-12 and absf(out.dissipated_energy - 4.455) < 1e-11)
	stage = _stage(_p([-2]), _p([0, -10, 0]))
	out = A.apply(stage, 2, _zeros(3), row.row, _p([0]), _p([.005]), [PackedInt32Array([0])])
	_verify("prescribed carrier work", stage, _zeros(3), 2, out)
	_check("carrier actuator can pay a positive kinetic change despite positive dissipation", out.get("ok", false)
		and out.kinetic_energy_change > 0 and out.dissipated_energy > 0
		and out.affine_carrier_work > out.dissipated_energy and out.prescribed_row_work == 0)
	stage = _stage(_p([0]), _zeros(3))
	row = A.point_tangent(_p([0, 0, .1]), _p([0, 0, .1]), _p([0, -1, 0]), 0, _p([1, 0, 0]), 1, _zeros(3), _p([5, 0, 0]))
	out = A.apply(stage, 2, _zeros(3), row.row, _p([row.bias]), _p([.4]), [PackedInt32Array([0])])
	_verify("moving ground work", stage, _zeros(3), 2, out)
	_check("moving support powers body/rotor gain and relative loss", out.get("ok", false) and out.kinetic_energy_change > 0
		and absf(out.total_prescribed_work - 5 * out.impulse[0]) < 1e-12 and out.affine_carrier_work == 0)


func _rows() -> void:
	var contact := _p([1, 2, 3])
	var rho := _p([.1, .2, .3])
	var axis := _p([0, -1, 0])
	var tangent := _p([1, 0, 0])
	var nu := _p([.2, -.3, .4])
	var ground := _p([2, -1, .5])
	var velocity := _p([3, 2, 1])
	var omega := _p([.4, -.2, .3])
	var sigma := 5.0
	var row := A.point_tangent(contact, rho, axis, 0, tangent, 1, nu, ground)
	var z := velocity.duplicate()
	z.append_array(omega)
	z.append(sigma)
	var actual := M.sub(M.add(M.add(M.add(velocity, M.cross(omega, contact)), M.cross(nu, rho)), M.scale(M.cross(axis, rho), sigma)), ground)
	_check("point row matches independent material-point kinematics", row.ok and absf(GC.dot(row.row, z, 7) + row.bias - M.dot(actual, tangent)) < 1e-13)
	_check("contact arm already contains rho and is not counted twice", row.row[4] == 3.0 and row.row[5] == -2.0 and absf(row.row[6] + .3) < 1e-15)
	var brake := A.internal_brake(0, 1)
	_check("internal brake row carries only relative spin work", brake.ok and GC.dot(brake.row, z, 7) == sigma and brake.bias == 0)
	var rolling := A.external_rolling(axis, 0, 1, nu)
	_check("external rolling row uses absolute axle rate including prescribed carrier", rolling.ok
		and absf(GC.dot(rolling.row, z, 7) + rolling.bias - M.dot(axis, M.add(M.add(omega, nu), M.scale(axis, sigma)))) < 1e-13)
	_check("nonunit tangent row is rejected", not A.point_tangent(contact, rho, axis, 0, _p([2, 0, 0]), 1).ok)
	_check("invalid rotor index rejected", not A.internal_brake(1, 1).ok)
	_check("nonunit rolling axis rejected", not A.external_rolling(_p([0, -2, 0]), 0, 1).ok)


func _coupled_network() -> void:
	var rates := _p([.1, 0, .2, 0, 0, 0, 0, 0, .3, 0, 0, 0])
	var stage := _stage(_p([8, -5, 3, 40]), rates, _p([.4, -.3, .2]))
	var jac := PackedFloat64Array()
	var bias := PackedFloat64Array()
	var limits := PackedFloat64Array()
	var groups: Array = []
	var arms := [_p([.1, -.3, .2]), _p([.1, .3, .2]), _p([-.5, 0, .15])]
	for i in 3:
		var axis: PackedFloat64Array = stage.axes.slice(3 * i, 3 * i + 3)
		var tangent := M.cross(axis, _p([0, 0, -1]))
		var side := M.cross(tangent, _p([0, 0, -1]))
		for direction: PackedFloat64Array in [tangent, side]:
			var row := A.point_tangent(arms[i], _p([0, 0, .1 if i < 2 else .08]), axis, i, direction, 4,
				rates.slice(3 * i, 3 * i + 3), _p([.4, -.2, 0]))
			jac.append_array(row.row)
			bias.append(row.bias)
		limits.append_array(_p([.2, .15]))
		groups.append(PackedInt32Array([2 * i, 2 * i + 1]))
	for i in 3:
		var row := A.internal_brake(i, 4)
		jac.append_array(row.row)
		bias.append(row.bias)
		limits.append(.003)
		groups.append(PackedInt32Array([6 + i]))
	for i in 3:
		var row := A.external_rolling(stage.axes.slice(3 * i, 3 * i + 3), i, 4, rates.slice(3 * i, 3 * i + 3))
		jac.append_array(row.row)
		bias.append(row.bias)
		limits.append(.0004)
		groups.append(PackedInt32Array([9 + i]))
	var out := A.apply(stage, 3, _p([2, -.4, .1]), jac, bias, limits, groups)
	_verify("three wheels plus dynamic shaft", stage, _p([2, -.4, .1]), 3, out)
	_check("coupled response updates all four relative spins", out.get("ok", false) and absf(out.delta_spin[3]) > 1e-8)
	_check("coupled/redundant contact mobility remains numerically PSD", out.get("ok", false) and out.qp.psd_rank <= 10 and out.mobility.size() == 144)
	var exhausted := A.apply(stage, 3, _p([2, -.4, .1]), jac, bias, limits, groups, 1)
	_check("exhausted traction cannot publish partial generalized velocities", not exhausted.ok
		and exhausted.status == "traction_nonconverged" and not exhausted.has("impulse") and not exhausted.has("velocity_cm_body"))
	if out.get("ok", false):
		for i in 3:
			var ellipse: float = (out.impulse[2 * i] / .2) * (out.impulse[2 * i] / .2) + (out.impulse[2 * i + 1] / .15) * (out.impulse[2 * i + 1] / .15)
			_check("combined tire ellipse is shared, not two full grip limits", ellipse <= 1.0 + 1e-14)
		_check("full coupled result is deterministic", var_to_bytes(out) == var_to_bytes(A.apply(stage, 3, _p([2, -.4, .1]), jac, bias, limits, groups)))


func _capacity() -> void:
	# 65 redundant brake rows are a rank-one Gram mobility, not 65 added masses.
	var stage := _stage(_p([30]), _zeros(3))
	var row := A.internal_brake(0, 1)
	var jac := PackedFloat64Array()
	var groups: Array = []
	var limits := _zeros(65)
	for i in 65:
		jac.append_array(row.row)
		groups.append(PackedInt32Array([i]))
		limits[i] = .001
	var out := A.apply(stage, 2, _zeros(3), jac, _zeros(65), limits, groups)
	_verify("65-row rank-one redundant impulse capacity", stage, _zeros(3), 2, out)
	_check("65-row compact bound solution equals independent aggregate brake", out.get("ok", false)
		and out.impulse.size() == 65 and absf(out.generalized_impulse[6] + .065) < 1e-13
		and absf(out.spin[0] - (30.0 - .065 / .0099)) < 1e-10 and out.qp.psd_rank == 1 and A.MAX_ROWS == 128)


func _validation_and_zero_rows() -> void:
	var stage := _stage(_p([5]), _zeros(3), _p([-0.0, 0.0, -0.0]))
	var cm := _p([-0.0, .2, -0.0])
	var input := var_to_bytes(stage)
	var zero := A.apply(stage, 2, cm, _zeros(0), _zeros(0), _zeros(0), [])
	_check("zero rows preserve CM and angular/spin bytes exactly", zero.get("ok", false)
		and zero.velocity_cm_body.to_byte_array() == cm.to_byte_array()
		and zero.omega.to_byte_array() == stage.velocity.slice(0, 3).to_byte_array()
		and zero.spin.to_byte_array() == stage.velocity.slice(3).to_byte_array())
	_check("zero rows leave caller stage unchanged", input == var_to_bytes(stage))
	var row := A.internal_brake(0, 1)
	var correct := A.apply(stage, 2, cm, row.row, _p([0]), _p([.01]), [PackedInt32Array([0])])
	var forged := stage.duplicate(true)
	forged.factor = {body_lower = _p([NAN]), coupling = _p([1e10]), local_mass = _p([-1])}
	var rebuilt := A.apply(forged, 2, cm, row.row, _p([0]), _p([.01]), [PackedInt32Array([0])])
	_check("forged factor is ignored and rederived from certified inventory", correct.get("ok", false) and rebuilt.get("ok", false)
		and correct.spin.to_byte_array() == rebuilt.spin.to_byte_array() and rebuilt.factor_rebuilt)
	for bad_key: String in ["matrix", "affine_momentum", "velocity", "axes"]:
		var bad := stage.duplicate(true)
		bad[bad_key][0] += .1 if bad_key != "velocity" else NAN
		var out := A.apply(bad, 2, cm, row.row, _p([0]), _p([.01]), [PackedInt32Array([0])])
		_check("malformed stage cannot publish velocity/impulse: " + bad_key, not out.ok and not out.has("spin") and not out.has("impulse"))
	var held := stage.duplicate(true)
	held.hold_indices = PackedInt64Array([0])
	_check("static holds cannot be silently broken", A.apply(held, 2, cm, row.row, _p([0]), _p([.01]), [PackedInt32Array([0])]).status == "unsupported_holds")
	held.erase("hold_indices")
	_check("missing hold declaration cannot bypass joint-policy validation", not A.apply(held, 2, cm, row.row, _p([0]), _p([.01]), [PackedInt32Array([0])]).ok)
	for mass: float in [0, -1, NAN, INF]:
		_check("invalid CM mass rejected", not A.apply(stage, mass, cm, row.row, _p([0]), _p([.01]), [PackedInt32Array([0])]).ok)
	_check("bad Jacobian layout rejected", not A.apply(stage, 2, cm, _p([1]), _p([0]), _p([.01]), [PackedInt32Array([0])]).ok)
	_check("nonfinite prescribed slip rejected", not A.apply(stage, 2, cm, row.row, _p([NAN]), _p([.01]), [PackedInt32Array([0])]).ok)
	var oversized_stage := stage.duplicate(true)
	oversized_stage.axial.resize(A.MAX_ROTORS + 1)
	_check("rotor dimensions have a bounded admission limit", not A.apply(oversized_stage, 2, cm, _zeros(0), _zeros(0), _zeros(0), []).ok)
	_check("zero-row fast path still validates the stage inventory", not A.apply(held, 2, cm, _zeros(0), _zeros(0), _zeros(0), []).ok)
	_check("129 rows rejected before allocating contact mobility", not A.apply(stage, 2, cm, _zeros(129 * 7), _zeros(129), _zeros(129), []).ok)


func _capture_scalar() -> void:
	var polished_count := 0
	var negative_roundoff_count := 0
	var row := A.internal_brake(0, 1)
	for spin: float in [.1, .2, .3, 1, 2, 3, 7, 11, 13, 17, 30, 100, 1e-8]:
		var stage := _stage(_p([spin]), _zeros(3))
		var raw := A.apply(stage, 2, _zeros(3), row.row, _p([0]), _p([2]), [PackedInt32Array([0])])
		var input_bytes := var_to_bytes([stage, row])
		var out := A.apply(stage, 2, _zeros(3), row.row, _p([0]), _p([2]), [PackedInt32Array([0])],
			1024, {rotor_index = 0, impulse_row = 0})
		_verify("finite scalar capture " + str(spin), stage, _zeros(3), 2, out)
		_check("captured sigma is EXACT zero with analytic impulse/body reaction", out.get("ok", false) and out.spin[0] == 0.0
			and out.delta_spin[0] == -spin and absf(out.impulse[0] + .0099 * spin) < 1e-12
			and absf(out.omega[1] + .01 * spin) < 1e-12)
		_check("capture leaves caller stage and row unchanged", input_bytes == var_to_bytes([stage, row]))
		if out.get("ok", false) and out.capture.polished:
			polished_count += 1
			_check("polish refreshes QP impulse/work/post and certificates", out.qp.impulse == out.impulse
				and out.qp.group_impulses[0][0] == out.impulse[0] and out.qp.method.contains("finite_capture")
				and out.qp.kkt_residual_scaled <= out.qp.kkt_tolerance_scaled and out.qp.feasibility_residual <= 1e-12
				and absf(out.qp.dissipation - out.dissipated_energy) < 1e-20
				and absf(out.qp.linear_work + out.qp.mobility_work + out.qp.dissipation) < 1e-14)
		if raw.get("ok", false) and raw.spin[0] < 0:
			negative_roundoff_count += 1
			_capture_fixture_spin = spin
	_check("independent scalar fixtures exercise actual roundoff polishing", polished_count > 0)
	_check("fixture reproduces negative-roundoff shaft-domain failure", negative_roundoff_count > 0)
	for values: Array in [[1.0, .005], [1.0, 0.0], [1000.0, 1.0]]:
		var stage := _stage(_p([values[0]]), _zeros(3))
		var moving := A.apply(stage, 2, _zeros(3), row.row, _p([0]), _p([values[1]]), [PackedInt32Array([0])])
		var selected := A.apply(stage, 2, _zeros(3), row.row, _p([0]), _p([values[1]]), [PackedInt32Array([0])], 1024, {rotor_index = 0, impulse_row = 0})
		_check("exhausted/zero friction preserves positive motion byte-exactly", selected.ok and not selected.capture.polished and selected.spin.to_byte_array() == moving.spin.to_byte_array()
			and selected.impulse.to_byte_array() == moving.impulse.to_byte_array() and selected.omega.to_byte_array() == moving.omega.to_byte_array())
	for values: Array in [[-1.0, .005], [-1e-30, 0.0], [-1000.0, 1.0]]:
		var stage := _stage(_p([values[0]]), _zeros(3))
		var out := A.apply(stage, 2, _zeros(3), row.row, _p([0]), _p([values[1]]), [PackedInt32Array([0])], 1024, {rotor_index = 0, impulse_row = 0})
		_check("real reverse breakaway cannot be clamped into static capture", not out.ok and out.status == "unsupported_reverse" and not out.has("spin") and not out.has("impulse"))
	var tiny := _stage(_p([-1e-12]), _zeros(3))
	var small := A.apply(tiny, 2, _zeros(3), row.row, _p([0]), _p([1e-14]), [PackedInt32Array([0])], 1024, {rotor_index = 0, impulse_row = 0})
	_check("finite small-budget capture uses relative scale, no absolute speed clamp", small.ok and small.spin[0] == 0.0 and absf(small.impulse[0]) <= 1e-14, str(small))
	var rest := _stage(_p([0]), _zeros(3))
	var zero := A.apply(rest, 2, _zeros(3), row.row, _p([0]), _p([0]), [PackedInt32Array([0])], 1024, {rotor_index = 0, impulse_row = 0})
	_check("exact rest with zero authority invents no friction impulse", zero.ok and zero.spin[0] == 0.0 and zero.impulse[0] == 0 and not zero.capture.polished)


func _capture_network() -> void:
	# Dense coupled three-wheel + shaft Gram problem with a selected interior
	# shaft row. Other impulse rows remain fixed while all coordinates respond.
	var stage := _stage(_p([.3, 4, -3, 7]), _zeros(12), _p([.2, -.1, .3]))
	var rows := [A.point_tangent(_p([.3, -.2, .2]), _p([0, 0, .1]), _p([0, -1, 0]), 1, _p([1, 0, 0]), 4),
		A.point_tangent(_p([.3, -.2, .2]), _p([0, 0, .1]), _p([0, -1, 0]), 1, _p([0, 1, 0]), 4),
		A.internal_brake(2, 4), A.external_rolling(_p([1, 0, 0]), 3, 4), A.internal_brake(0, 4)]
	var jac := PackedFloat64Array()
	for row: Dictionary in rows: jac.append_array(row.row)
	var limits := _p([.03, .02, .002, .001, 1.0])
	var groups := [PackedInt32Array([0, 1]), PackedInt32Array([2]), PackedInt32Array([3]), PackedInt32Array([4])]
	var raw := A.apply(stage, 3, _p([2, -.4, .1]), jac, _zeros(5), limits, groups)
	var out := A.apply(stage, 3, _p([2, -.4, .1]), jac, _zeros(5), limits, groups, 1024, {rotor_index = 0, impulse_row = 4})
	var exhausted := A.apply(stage, 3, _p([2, -.4, .1]), jac, _zeros(5), limits, groups, 1, {rotor_index = 0, impulse_row = 4})
	_check("capture cannot override an exhausted global QP iteration budget", not exhausted.ok and not exhausted.has("impulse") and not exhausted.has("spin"))
	_verify("dense coupled finite shaft capture", stage, _p([2, -.4, .1]), 3, out)
	_check("dense capture preserves every wheel and exact shaft constraint", out.get("ok", false) and out.spin[0] == 0.0 and out.spin.size() == 4, str(out))
	if out.get("ok", false):
		_check("dense fixture exercises constrained free-coordinate polish", out.capture.polished)
		for i in 4:
			_check("polish changes only selected finite impulse row", out.impulse[i] == raw.impulse[i])
		var before_h := _momentum(stage, stage.velocity.slice(0, 3), stage.velocity.slice(3))
		var after_h := _momentum(stage, out.omega, out.spin)
		var q := M.q_from_euler(.4, -.3, .7)
		var origin_arm := _p([10, -3, 2])
		var before_world := M.add(M.q_rotate(q, before_h), M.cross(origin_arm, M.q_rotate(q, M.scale(_p([2, -.4, .1]), 3))))
		var after_world := M.add(M.q_rotate(q, after_h), M.cross(origin_arm, M.q_rotate(q, M.scale(out.velocity_cm_body, 3))))
		var external_world := M.add(M.q_rotate(q, out.generalized_impulse.slice(3, 6)), M.cross(origin_arm, M.q_rotate(q, out.generalized_impulse.slice(0, 3))))
		_check("all world angular momentum about an offset origin reconciles", M.norm(M.sub(M.sub(after_world, before_world), external_world)) < 1e-11)
		for i in 4:
			var axis: PackedFloat64Array = stage.axes.slice(3 * i, 3 * i + 3)
			var canonical_change: float = stage.axial[i] * (M.dot(axis, out.delta_omega) + out.delta_spin[i])
			_check("all wheel/shaft canonical momenta reconcile", absf(canonical_change - out.generalized_impulse[6 + i]) < 1e-12)
		_check("dense capture is deterministic with current KKT diagnostics", var_to_bytes(out) == var_to_bytes(A.apply(stage, 3, _p([2, -.4, .1]), jac, _zeros(5), limits, groups, 1024, {rotor_index = 0, impulse_row = 4})))


func _capture_rejections() -> void:
	var stage := _stage(_p([.1]), _zeros(3))
	var row := A.internal_brake(0, 1)
	for mapping: Dictionary in [{rotor_index = 0}, {rotor_index = true, impulse_row = 0}, {rotor_index = 1, impulse_row = 0},
		{rotor_index = 0, impulse_row = 1}, {rotor_index = 0, impulse_row = 0, tolerance = 1.0}]:
		_check("malformed capture mapping rejects", not A.apply(stage, 2, _zeros(3), row.row, _p([0]), _p([1]), [PackedInt32Array([0])], 1024, mapping).ok)
	for key: String in ["body_force", "other_rate", "scaled", "negative", "bias", "disk"]:
		var jac: PackedFloat64Array = row.row.duplicate()
		var bias := _p([0])
		var limits := _p([1])
		var groups := [PackedInt32Array([0])]
		match key:
			"body_force": jac[0] = 1.0
			"other_rate": jac[3] = 1.0
			"scaled": jac[6] = 2.0
			"negative": jac[6] = -1.0
			"bias": bias[0] = .1
			"disk":
				jac.append_array(row.row)
				bias.append(0)
				limits.append(1)
				groups = [PackedInt32Array([0, 1])]
		var out := A.apply(stage, 2, _zeros(3), jac, bias, limits, groups, 1024, {rotor_index = 0, impulse_row = 0})
		_check("capture cannot masquerade as body-force clamp or noncanonical row: " + key, not out.ok and out.status == "invalid_capture" and not out.has("impulse"))


func _capture_checkpoint() -> void:
	var sim := Sim.new()
	sim.mass = 2.0
	sim.gravity = 0
	sim.aux = PackedFloat64Array()
	sim.continuous = _p([_capture_fixture_spin])
	var model := Model.new()
	model.aux_size = 0
	model.modes_size = 0
	model.continuous_size = 1
	model.state_layout_identity = "finite-capture-nonnegative-shaft-fixture-v1"
	model.stage = func(_body, _values, _t): return {loads = _zeros(6), derivative = _zeros(1), rotor_momentum = _zeros(3)}
	model.state_validator = func(frame, _context): return frame.continuous[0] >= 0.0
	model.step_policy = func(s, _t, _h, _f, _k1):
		var stage := _stage(_p([s[13]]), _zeros(3), s.slice(RB.RATE, RB.RATE + 3))
		var row := A.internal_brake(0, 1)
		var out := A.apply(stage, 2, s.slice(RB.VEL, RB.VEL + 3), row.row, _p([0]), _p([2]), [PackedInt32Array([0])],
			1024, {rotor_index = 0, impulse_row = 0})
		if not out.ok: return out
		var next: PackedFloat64Array = s.duplicate()
		for i in 3: next[RB.RATE + i] = out.omega[i]
		next[13] = out.spin[0]
		return {state = next, events = []}
	_check("strict nonnegative shaft kernel model installs", sim.set_model(model))
	_check("finite friction checkpoint fixture resets", sim.reset(RB.make_state(_zeros(3), _zeros(3), M.q_identity(), _zeros(3))))
	sim.step()
	_check("rounded-negative capture admits exact-zero kernel endpoint", sim.tick == 1 and sim.fault_reason.is_empty() and sim.continuous[0] == 0.0, sim.fault_reason)
	var checkpoint: Dictionary = sim.checkpoint()
	_check("exact nonnegative capture exports valid v2 checkpoint", checkpoint.get("format", "") == Sim.ENDPOINT_CHECKPOINT_FORMAT and checkpoint.continuous[0] == 0.0)
	sim.step()
	var expected := var_to_bytes(sim.checkpoint())
	_check("finite-capture checkpoint restores", sim.restore_checkpoint(checkpoint))
	sim.step()
	_check("exact-zero captured continuation replays byte-exactly", expected == var_to_bytes(sim.checkpoint()) and sim.tick == 2)
	sim.free()

