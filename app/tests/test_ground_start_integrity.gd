# E3b2-R1: numerical failure must never become a usable runway start.
extends SceneTree
const GS = preload("res://physics/ground_start.gd")
const AD = preload("res://physics/aircraft_data.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const Surfaces = preload("res://physics/ground_surfaces.gd")
const Session = preload("res://sim/flight_session.gd")
const Scenarios = preload("res://sim/scenarios.gd")
var checks: int = 0
var failures: int = 0

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func refused(label: String, result: Dictionary) -> void:
	check(label + " refuses with reason", not result.ok and not result.message.is_empty())
	check(label + " exposes no candidate state", result.state.is_empty() and result.rest_state.is_empty() and result.anchors.is_empty())
	check(label + " retains failure diagnostics", result.get("iterations", -1) == 0 and result.get("residual", NAN) == INF)

func newton_checks() -> void:
	check("norm finite maximum", GS._norm(PackedFloat64Array([-3, 2, 1])) == 3)
	check("empty norm is not convergence", GS._norm(PackedFloat64Array()) == INF)
	for bad in [NAN, INF, -INF]:
		for index in 3:
			var r: PackedFloat64Array = PackedFloat64Array([0, 0, 0])
			r[index] = bad
			check("norm nonfinite component " + str(index), GS._norm(r) == INF)
			var result: Dictionary = GS._newton(func(_x: PackedFloat64Array) -> PackedFloat64Array: return r, PackedFloat64Array([0, 0, 0]))
			check("nonfinite initial residual never converges", not result.ok)
	for size in [0, 1, 3]:
		var r: PackedFloat64Array = PackedFloat64Array()
		r.resize(size)
		check("residual dimension " + str(size), not GS._newton(func(_x: PackedFloat64Array) -> PackedFloat64Array: return r, PackedFloat64Array([0, 0])).ok)
	var calls: Array[int] = [0]
	var zero := func(_x: PackedFloat64Array) -> PackedFloat64Array:
		calls[0] += 1
		return PackedFloat64Array([0])
	for bad in [NAN, INF, -INF]:
		check("initial iterate refused before callback", not GS._newton(zero, PackedFloat64Array([bad])).ok and calls[0] == 0)
	check("empty initial iterate refused before callback", not GS._newton(zero, PackedFloat64Array()).ok and calls[0] == 0)
	var initial: PackedFloat64Array = PackedFloat64Array([0, 0])
	var linear := func(x: PackedFloat64Array) -> PackedFloat64Array: return PackedFloat64Array([2*x[1]-4, 3*x[0]+x[1]-5])
	var solved: Dictionary = GS._newton(linear, initial)
	check("known pivoted root", solved.ok and absf(solved.x[0]-1) < 1e-12 and absf(solved.x[1]-2) < 1e-12)
	check("initial iterate unchanged", initial == PackedFloat64Array([0, 0]))
	check("initial root needs zero iterations", GS._newton(linear, PackedFloat64Array([1, 2])).iterations == 0)
	var constant := func(_x: PackedFloat64Array) -> PackedFloat64Array: return PackedFloat64Array([1])
	check("singular Jacobian refuses", not GS._newton(constant, PackedFloat64Array([0])).ok)
	for bad_size in [true, false]:
		var perturbation := func(x: PackedFloat64Array) -> PackedFloat64Array:
			if x[0] != 0:
				return PackedFloat64Array() if bad_size else PackedFloat64Array([NAN])
			return PackedFloat64Array([1])
		check("invalid perturbation refuses cleanly", not GS._newton(perturbation, PackedFloat64Array([0])).ok)
		var after_step := func(x: PackedFloat64Array) -> PackedFloat64Array:
			if x[0] > .9:
				return PackedFloat64Array() if bad_size else PackedFloat64Array([NAN])
			return PackedFloat64Array([x[0]-1])
		check("invalid iterated residual refuses cleanly", not GS._newton(after_step, PackedFloat64Array([0])).ok)
	var jump := func(x: PackedFloat64Array) -> PackedFloat64Array:
		return PackedFloat64Array([1e308 if x[0] > 0 else -1e308 if x[0] < 0 else 1])
	check("finite residuals overflowing Jacobian refuse", not GS._newton(jump, PackedFloat64Array([0])).ok)
	# Fault-injected callback: finite samples create a -1 Jacobian and a step that overflows x.
	calls[0] = 0
	var overflow := func(_x: PackedFloat64Array) -> PackedFloat64Array:
		calls[0] += 1
		return PackedFloat64Array([1e308 if calls[0] == 1 else -1e-6 if calls[0] == 2 else 1e-6])
	check("overflowing iterate is not evaluated", not GS._newton(overflow, PackedFloat64Array([1e308])).ok and calls[0] == 3)
	# x^2 + 1 has no real root; nonconvergence must remain bounded.
	var impossible := func(x: PackedFloat64Array) -> PackedFloat64Array: return PackedFloat64Array([x[0]*x[0]+1])
	var failed: Dictionary = GS._newton(impossible, PackedFloat64Array([2]))
	check("no real root refuses within iteration budget", not failed.ok and failed.iterations == GS.MAX_ITERATIONS)

func linear_checks() -> void:
	var a: PackedFloat64Array = PackedFloat64Array([0, 2, 3, 1])
	var b: PackedFloat64Array = PackedFloat64Array([4, 5])
	var before: PackedByteArray = var_to_bytes([a, b])
	check("pivoted linear known answer", GS._linear_solve(a, b, 2) == PackedFloat64Array([1, 2]))
	check("linear inputs unchanged", var_to_bytes([a, b]) == before)
	for n in [-1, 0, 1, 3, 9223372036854775807]:
		check("invalid matrix dimension " + str(n), GS._linear_solve(a, b, n).is_empty())
	check("wrong RHS width", GS._linear_solve(a, PackedFloat64Array([4]), 2).is_empty())
	check("trailing matrix entry", GS._linear_solve(PackedFloat64Array([0, 2, 3, 1, 7]), b, 2).is_empty())
	for bad in [NAN, INF, -INF]:
		for index in a.size():
			var invalid: PackedFloat64Array = a.duplicate()
			invalid[index] = bad
			check("nonfinite matrix element", GS._linear_solve(invalid, b, 2).is_empty())
		for index in b.size():
			var invalid: PackedFloat64Array = b.duplicate()
			invalid[index] = bad
			check("nonfinite RHS element", GS._linear_solve(a, invalid, 2).is_empty())
	check("singular system", GS._linear_solve(PackedFloat64Array([1, 2, 2, 4]), b, 2).is_empty())
	check("overflow in elimination", GS._linear_solve(PackedFloat64Array([1, 1, 1, -1]), PackedFloat64Array([1e308, -1e308]), 2).is_empty())
	check("overflow in matrix update", GS._linear_solve(PackedFloat64Array([1, 1e308, -1, 1e308]), b, 2).is_empty())
	check("overflow in final division", GS._linear_solve(PackedFloat64Array([1e-299]), PackedFloat64Array([1e308]), 1).is_empty())
	check("overflow in back substitution", GS._linear_solve(PackedFloat64Array([1, 2, 0, 1]), PackedFloat64Array([0, 1e308]), 2).is_empty())

func public_checks() -> void:
	var model: Dictionary = AD.load_file(Scenarios.AIRCRAFT).model
	var field: Dictionary = FieldLoader.load_from().field
	var surfaces: PackedFloat64Array = Surfaces.build(Surfaces.load_table().table, field).rects
	var d: Dictionary = {elevator=0.0, aileron_left=0.0, aileron_right=0.0, rudder=0.0}
	var args: Array = [model, surfaces, 15.0, -47.0, PI/2, d, 0.0, 2500.0, 1.225, 9.80665]
	var before: PackedByteArray = var_to_bytes(args)
	var control: Dictionary = GS.solve.callv(args)
	check("valid loaded-model ground start", control.ok and is_finite(control.residual) and control.residual <= GS.TOLERANCE)
	if not control.ok:
		printerr(control.message)
		return
	for key in ["state", "rest_state", "anchors"]:
		var expected_size: int = 3 * model.landing_gear.contacts.size() if key == "anchors" else 13
		check("successful result width " + key, control[key].size() == expected_size)
		var finite: bool = true
		for value in control[key]:
			finite = finite and is_finite(value)
		check("successful result finite " + key, finite)
	for index in model.landing_gear.contacts.size():
		check("successful result wheel stays stuck", control.anchors[index * 3 + 2] == 1.0)
	for index in [2, 3, 4, 6, 7, 8, 9]:
		for bad in [NAN, INF, -INF]:
			var invalid: Array = args.duplicate()
			invalid[index] = bad
			refused("nonfinite solve argument " + str(index), GS.solve.callv(invalid))
	for index in [7, 8, 9]:
		var invalid: Array = args.duplicate()
		invalid[index] = -1.0
		refused("negative physical input " + str(index), GS.solve.callv(invalid))
	var no_gravity: Array = args.duplicate()
	no_gravity[9] = 0.0
	refused("no weight to support on gear", GS.solve.callv(no_gravity))
	for axis in d:
		for bad in [NAN, INF, -INF, "0.0", true, null]:
			var invalid: Array = args.duplicate(true)
			invalid[5][axis] = bad
			refused("invalid deflection " + str(axis), GS.solve.callv(invalid))
		var missing: Array = args.duplicate(true)
		missing[5].erase(axis)
		refused("missing deflection " + str(axis), GS.solve.callv(missing))
	var overflow: Array = args.duplicate()
	overflow[7] = 1e160
	refused("finite RPM overflows propulsion", GS.solve.callv(overflow))
	var vacuum: Array = args.duplicate()
	vacuum[8] = 0.0
	check("zero density remains a valid engine-off-load limit", GS.solve.callv(vacuum).ok)
	var stopped: Array = args.duplicate()
	stopped[7] = 0.0
	check("zero RPM remains a valid stopped-engine limit", GS.solve.callv(stopped).ok)
	check("solve arguments unchanged after refusals", var_to_bytes(args) == before)
	check("valid solve repeats exactly after refusals", var_to_bytes(GS.solve.callv(args)) == var_to_bytes(control))
	var session: Node = Session.new()
	session.setup()
	root.add_child(session)
	session.input_enabled = false
	check("session field configured", session.set_field(field))
	for coordinates in [[NAN, -47.0, PI/2], [15.0, INF, PI/2], [15.0, -47.0, NAN]]:
		check("session propagates invalid runway refusal", not session.reset_on_runway(coordinates[0], coordinates[1], coordinates[2]))
		check("session fallback retains normal airborne start", session.sim.state == session.start.state and session.sim.fault_reason.is_empty())
	check("valid runway reset after refusals", session.reset_on_runway(15, -47, PI/2))
	session.free()

func _initialize() -> void:
	newton_checks()
	linear_checks()
	public_checks()
	print("E3b2-R1: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
