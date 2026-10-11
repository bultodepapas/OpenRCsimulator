# D8b-R2c: mathematical mass, inertia and input contracts for the Ugly Stik review.
# Run from the repository root with the pinned Windows Godot:
# .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_pullup_invariants.gd
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Keyboard := preload("res://input/keyboard.gd")
const Commands := preload("res://input/commands.gd")
const AIRCRAFT_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _close_array(label: String, got: PackedFloat64Array, want: Array, tolerance := 1e-12) -> void:
	var ok := got.size() == want.size()
	var worst := 0.0
	if ok:
		for i in want.size():
			var error := absf(got[i] - float(want[i]))
			worst = maxf(worst, error)
			ok = ok and error <= tolerance
	_check(label, ok, "got %s, want %s, max error %s" % [got, want, str(worst)])


func _tensor_determinant(j: PackedFloat64Array) -> float:
	return j[0] * (j[1] * j[2] - j[5] * j[5]) \
		- j[3] * (j[3] * j[2] - j[4] * j[5]) \
		+ j[4] * (j[3] * j[5] - j[4] * j[1])


func _audit_quantity(node: Variant, expected_unit: String) -> bool:
	if typeof(node) != TYPE_DICTIONARY:
		return false
	var value: Variant = node.get("value")
	var value_ok := typeof(value) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(value))
	if typeof(value) == TYPE_ARRAY:
		value_ok = not value.is_empty()
		for component in value:
			value_ok = value_ok and typeof(component) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(component))
			if expected_unit == "m":
				value_ok = value_ok and value.size() == 3
	return value_ok \
		and node.get("unit") == expected_unit and AD.KINDS.has(node.get("kind")) \
		and typeof(node.get("source")) == TYPE_STRING and not str(node.get("source")).strip_edges().is_empty()


func _inventory_products(raw: Dictionary, cg: PackedFloat64Array) -> PackedFloat64Array:
	# Independent reduction of the three products from the source inventory.
	# Axis-aligned box dimensions add diagonal inertia only.
	var products := PackedFloat64Array([0.0, 0.0, 0.0])
	for item: Dictionary in raw.inventory:
		var mass := float(item.mass.value)
		var position: Array = item.position.value
		var x := -(float(position[0]) - cg[0])
		var y := float(position[1]) - cg[1]
		var z := -(float(position[2]) - cg[2])
		products[0] -= mass * x * y
		products[1] -= mass * x * z
		products[2] -= mass * y * z
	return products


func _send_key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _key_contract(key: Key, axis: String, expected: float, throws: Dictionary) -> void:
	_send_key(key, true)
	var raw := Keyboard.read_raw()
	var raw_ok: bool = raw.roll == (expected if axis == "roll" else 0.0) \
		and raw.pitch == (expected if axis == "pitch" else 0.0) \
		and raw.yaw == (expected if axis == "yaw" else 0.0) \
		and raw.throttle == (expected if axis == "throttle" else 0.0)
	_check("physical key %s changes only raw %s" % [key, axis], raw_ok, str(raw))

	# Apply the documented 4 command-units/s keyboard slew for 0.25 s: the
	# stick reaches full command while throttle remains a separate, slower axis.
	var command := Commands.step_commands(Commands.neutral_commands(), raw, 0.25)
	var command_ok: bool = command.roll == (expected if axis == "roll" else 0.0) \
		and command.pitch == (expected if axis == "pitch" else 0.0) \
		and command.yaw == (expected if axis == "yaw" else 0.0) \
		and is_equal_approx(command.throttle, 0.5 + (expected * 0.125 if axis == "throttle" else 0.0))
	_check("raw %s remains independent after command shaping" % axis, command_ok, str(command))

	var surfaces := Commands.surface_deflections_deg(command, throws)
	var expected_right := expected * float(throws.aileron) if axis == "roll" else 0.0
	var expected_left := -expected * float(throws.aileron) if axis == "roll" else 0.0
	var expected_elevator := expected * float(throws.elevator) if axis == "pitch" else 0.0
	var expected_rudder := expected * float(throws.rudder) if axis == "yaw" else 0.0
	var surfaces_ok: bool = is_equal_approx(surfaces.aileron_right, expected_right) \
		and is_equal_approx(surfaces.aileron_left, expected_left) \
		and is_equal_approx(surfaces.elevator, expected_elevator) \
		and is_equal_approx(surfaces.rudder, expected_rudder)
	_check("shaped %s reaches only its configured surface" % axis, surfaces_ok, str(surfaces))
	_send_key(key, false)


func _initialize() -> void:
	# A single off-axis point mass has a closed-form tensor in body FRD axes.
	# LE-frame displacement (.3, .4, .15) maps to body displacement (-.3, .4, -.15).
	var point_tensor := AD.inertia_about([
		[2.0, PackedFloat64Array([0.4, 0.3, 0.2]), PackedFloat64Array([0.0, 0.0, 0.0])],
	], PackedFloat64Array([0.1, -0.1, 0.05]))
	_close_array("analytic point mass gives all six tensor entries in body FRD order", point_tensor,
		[0.365, 0.225, 0.5, 0.24, -0.09, 0.12])

	# Intrinsic rectangular-box inertia is about its own centre; its cross terms vanish.
	var box := AD.inertia_about([
		[2.0, PackedFloat64Array([0.0, 0.0, 0.0]), PackedFloat64Array([0.3, 1.5, 0.04])],
	], PackedFloat64Array([0.0, 0.0, 0.0]))
	_close_array("analytic box inertia includes intrinsic diagonal terms", box,
		[2.0 * (1.5 * 1.5 + 0.04 * 0.04) / 12.0,
		2.0 * (0.3 * 0.3 + 0.04 * 0.04) / 12.0,
		2.0 * (0.3 * 0.3 + 1.5 * 1.5) / 12.0, 0.0, 0.0, 0.0])

	# A mirrored pair cancels Jxy and Jyz while retaining the real, even Jxz term.
	var reflected := AD.inertia_about([
		[1.25, PackedFloat64Array([0.2, 0.3, 0.1]), PackedFloat64Array([0.0, 0.0, 0.0])],
		[1.25, PackedFloat64Array([0.2, -0.3, 0.1]), PackedFloat64Array([0.0, 0.0, 0.0])],
	], PackedFloat64Array([0.0, 0.0, 0.0]))
	_close_array("reflection cancels odd products and preserves the even product", reflected,
		[0.25, 0.125, 0.325, 0.0, -0.05, 0.0])

	# Positive-definite full tensor with all products nonzero; determinant and inverse are independent references.
	var tensor := PackedFloat64Array([5.0, 7.0, 4.0, 0.8, 1.0, -2.0])
	var minor2 := tensor[0] * tensor[1] - tensor[3] * tensor[3]
	var determinant := _tensor_determinant(tensor)
	_check("full tensor is positive definite by Sylvester's leading minors",
		tensor[0] > 0.0 and minor2 > 0.0 and determinant > 0.0,
		"Jxx %s, leading minor %s, determinant %s" % [str(tensor[0]), str(minor2), str(determinant)])
	var inverse := RB.inertia_inverse(tensor)
	var inverse_ok := true
	for axis in 3:
		var basis := M.v3(1.0 if axis == 0 else 0.0, 1.0 if axis == 1 else 0.0, 1.0 if axis == 2 else 0.0)
		var recovered := RB.inertia_mul(tensor, RB.inertia_mul(inverse, basis))
		for component in 3:
			inverse_ok = inverse_ok and absf(recovered[component] - basis[component]) < 1e-12
	_check("full-tensor inverse recovers all three basis vectors", inverse_ok, str(inverse))

	# With zero body rate, the pure-pitch moment has the analytic J^-1 column; coupling is expected.
	var state := RB.make_state(M.v3(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0), M.q_identity(), M.v3(0.0, 0.0, 0.0))
	var derivative := RB.derivative(state, 2.0, tensor, inverse, M.v3(0.0, 0.0, 0.0),
		M.v3(0.0, 3.0, 0.0), 0.0)
	_close_array("pure pitch moment produces analytically coupled angular acceleration",
		derivative.slice(RB.RATE, RB.RATE + 3), [-5.2 * 3.0 / determinant, 19.0 * 3.0 / determinant, 10.8 * 3.0 / determinant])

	var loaded := AD.load_file(AIRCRAFT_PATH)
	_check("current Jensen source inventory loads", loaded.ok, str(loaded.get("errors", [])))
	if not loaded.ok:
		print("D8b-R2c: %d checks, %d failed" % [_checks, _failures])
		quit(1)
		return
	var model: Dictionary = loaded.model
	var raw_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(AIRCRAFT_PATH))
	_check("aircraft source JSON parses", typeof(raw_value) == TYPE_DICTIONARY)
	if typeof(raw_value) != TYPE_DICTIONARY:
		print("D8b-R2c: %d checks, %d failed" % [_checks, _failures])
		quit(1)
		return
	var raw: Dictionary = raw_value

	# Audit the extant inventory evidence without assigning unmeasured tolerances.
	var total_mass := 0.0
	var first_moment := PackedFloat64Array([0.0, 0.0, 0.0])
	var inventory_evidence_ok: bool = not raw.inventory.is_empty()
	for item: Dictionary in raw.inventory:
		inventory_evidence_ok = inventory_evidence_ok and typeof(item.get("name")) == TYPE_STRING and not str(item.get("name", "")).is_empty()
		inventory_evidence_ok = inventory_evidence_ok and _audit_quantity(item.get("mass"), "kg")
		inventory_evidence_ok = inventory_evidence_ok and _audit_quantity(item.get("position"), "m")
		if item.has("size"):
			inventory_evidence_ok = inventory_evidence_ok and _audit_quantity(item.get("size"), "m")
		var mass := float(item.mass.value)
		var position: Array = item.position.value
		total_mass += mass
		for axis in 3:
			first_moment[axis] += mass * float(position[axis])
	var inventory_cg := PackedFloat64Array([first_moment[0] / total_mass, first_moment[1] / total_mass, first_moment[2] / total_mass])
	_check("every current inventory mass and location has unit, evidence kind and source", inventory_evidence_ok)
	_check("loaded mass and CG are the source inventory totals",
		absf(model.mass_kg - total_mass) < 1e-12 and M.norm(M.sub(model.cg_le, inventory_cg)) < 1e-12,
		"loaded mass %s / source sum %s; CG %s / source CG %s" % [str(model.mass_kg), str(total_mass), model.cg_le, inventory_cg])
	var products := _inventory_products(raw, inventory_cg)
	_close_array("current asymmetric inventory products are retained without zeroing", PackedFloat64Array(model.inertia.slice(3, 6)),
		[products[0], products[1], products[2]])

	var actual_j: PackedFloat64Array = model.inertia
	var actual_minor2 := actual_j[0] * actual_j[1] - actual_j[3] * actual_j[3]
	var actual_det := _tensor_determinant(actual_j)
	var actual_finite: bool = model.mass_kg > 0.0 and is_finite(model.mass_kg) and actual_j.size() == 6
	for value in actual_j:
		actual_finite = actual_finite and is_finite(value)
	_check("loaded aircraft inertia is finite, nonsingular and positive definite",
		actual_finite and actual_j[0] > 0.0 and actual_minor2 > 0.0 and actual_det > 0.0,
		"inertia %s; minor %s; determinant %s" % [actual_j, str(actual_minor2), str(actual_det)])
	var actual_inverse := RB.inertia_inverse(actual_j)
	var actual_inverse_ok := true
	for axis in 3:
		var basis := M.v3(1.0 if axis == 0 else 0.0, 1.0 if axis == 1 else 0.0, 1.0 if axis == 2 else 0.0)
		var recovered := RB.inertia_mul(actual_j, RB.inertia_mul(actual_inverse, basis))
		for component in 3:
			actual_inverse_ok = actual_inverse_ok and absf(recovered[component] - basis[component]) < 1e-11
	_check("loaded aircraft full-inertia inverse recovers all axes", actual_inverse_ok, str(actual_inverse))

	# Verify provenance and conversion without pinning a future data file to today's evidence kind.
	var raw_controls: Dictionary = raw.controls
	var throw_nodes: Dictionary = raw_controls.max_throw
	var control_evidence_ok := true
	for surface in ["aileron", "elevator", "rudder"]:
		control_evidence_ok = control_evidence_ok and _audit_quantity(throw_nodes[surface], "deg")
	var servo_time: Dictionary = raw_controls.servo_full_throw_time
	control_evidence_ok = control_evidence_ok and _audit_quantity(servo_time, "s")
	_check("control throws and servo time carry recognized provenance", control_evidence_ok)
	var throws: Dictionary = model.controls.throw_deg
	var throw_conversion_ok: bool = true
	for surface in ["aileron", "elevator", "rudder"]:
		throw_conversion_ok = throw_conversion_ok and throws[surface] == float(throw_nodes[surface].value) \
			and absf(model.controls.throw_rad[surface] - deg_to_rad(throws[surface])) < 1e-15
	_check("loaded degree and radian throws agree with the source values", throw_conversion_ok, str(model.controls.throw_deg))
	_check("servo slew rate follows the sourced full-throw time",
		absf(model.controls.servo_rate - 1.0 / float(servo_time.value)) < 1e-12,
		"rate %s/s; source time %s s" % [str(model.controls.servo_rate), str(servo_time.value)])

	# Exercise Godot's physical-key state and the production keyboard adapter, then carry
	# each raw axis through the actual command shaper and aircraft throw data.
	for entry: Dictionary in [
		{key = KEY_LEFT, axis = "roll", value = -1.0},
		{key = KEY_RIGHT, axis = "roll", value = 1.0},
		{key = KEY_UP, axis = "pitch", value = -1.0},
		{key = KEY_DOWN, axis = "pitch", value = 1.0},
		{key = KEY_A, axis = "yaw", value = -1.0},
		{key = KEY_D, axis = "yaw", value = 1.0},
		{key = KEY_S, axis = "throttle", value = -1.0},
		{key = KEY_W, axis = "throttle", value = 1.0},
	]:
		_key_contract(entry.key, entry.axis, entry.value, throws)
	_check("all keyboard keys released after the synthetic input cases",
		Keyboard.read_raw() == {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}, str(Keyboard.read_raw()))

	print("source inventory: %d parts, mass %s kg, CG LE %s m" % [raw.inventory.size(), str(model.mass_kg), model.cg_le])
	print("source inertia [Jxx,Jyy,Jzz,Jxy,Jxz,Jyz] kg m^2: %s" % [model.inertia])
	print("control throws %s deg (kinds %s); full-throw time %s s (%s)" % [
		model.controls.throw_deg,
		[throw_nodes.aileron.kind, throw_nodes.elevator.kind, throw_nodes.rudder.kind],
		str(servo_time.value),
	servo_time.kind,
	])
	print("D8b-R2c: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
