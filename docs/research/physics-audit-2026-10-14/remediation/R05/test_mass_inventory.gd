extends SceneTree

const Inventory := preload("res://physics/mass_inventory.gd")
const FuelMass := preload("res://physics/glow/fuel_mass.gd")
const RB := preload("res://physics/rigid_body.gd")

var _failures: int = 0
var _checks: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _close(label: String, got: PackedFloat64Array, want: Array, tolerance: float = 1.0e-11) -> void:
	var ok: bool = got.size() == want.size()
	if ok:
		for i: int in want.size():
			ok = ok and absf(got[i] - float(want[i])) <= tolerance
	_check(label, ok, "got %s want %s" % [got, want])


func _component(id: String, mass: float, center: Array, tensor: Array) -> Dictionary:
	return {id = id, mass_kg = mass, center_body_m = PackedFloat64Array(center),
		inertia_centroid_kgm2 = PackedFloat64Array(tensor)}


func _resource(id: String, capacity: float, center: Array, tensor_at_capacity: Array) -> Dictionary:
	return {id = id, capacity_mass_kg = capacity, center_body_m = PackedFloat64Array(center),
		inertia_centroid_at_capacity_kgm2 = PackedFloat64Array(tensor_at_capacity),
		distribution_model = Inventory.RESOURCE_DISTRIBUTION}


func _fixture(datum_shift: Array = [0.0, 0.0, 0.0]) -> Dictionary:
	var dx: float = datum_shift[0]
	var dy: float = datum_shift[1]
	var dz: float = datum_shift[2]
	var dry := _component("airframe", 10.0, [-dx, -dy, -dz], [10.0, 12.0, 14.0, 0.0, 0.0, 0.0])
	var fuel_a := _resource("fuel-a", 2.0, [1.0 - dx, -dy, -dz], [0.4, 0.5, 0.6, 0.0, 0.0, 0.0])
	# Principal moments 0.2 and 0.5 rotated 45 degrees in XY give Jxy=-0.15.
	var fuel_b := _resource("fuel-b", 1.5, [-dx, 2.0 - dy, 1.0 - dz], [0.35, 0.35, 0.7, -0.15, 0.0, 0.0])
	return Inventory.prepare("airframe-wet-reference", [dry], [fuel_b, fuel_a])


func _initialize() -> void:
	_test_full_half_empty()
	_test_offcenter_rotation_and_inverse()
	_test_reference_shift()
	_test_validation()
	_test_glow_kernel_byte_parity()
	print("R05-A mass inventory geometry: %d checks, %d failed" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_full_half_empty() -> void:
	var prepared: Dictionary = _fixture()
	_check("fixture prepares", prepared.get("ok", false), str(prepared))
	_check("resource ids are stable sorted", prepared.get("resource_ids", PackedStringArray()) == PackedStringArray(["fuel-a", "fuel-b"]))
	var full: Dictionary = Inventory.evaluate(prepared, {"fuel-a": 2.0, "fuel-b": 1.5})
	_check("full inventory evaluates", full.get("ok", false), str(full))
	_check("full mass", is_equal_approx(full.mass_kg, 13.5))
	_close("full first moment", full.first_moment_kg_m, [2.0, 3.0, 1.5])
	_close("full datum tensor", full.inertia_datum_kgm2, [18.25, 16.35, 23.3, -0.15, 0.0, -3.0])
	_close("full CG", full.cg_body_m, [2.0 / 13.5, 3.0 / 13.5, 1.5 / 13.5])
	_close("full CG tensor", full.inertia_cg_kgm2,
		[17.4166666666667, 15.8870370370370, 22.3370370370370, 0.2944444444444, 0.2222222222222, -2.6666666666667], 2.0e-11)

	var half: Dictionary = Inventory.evaluate(prepared, {"fuel-a": 1.0, "fuel-b": 0.75})
	_check("half inventory evaluates", half.get("ok", false), str(half))
	_check("half mass", is_equal_approx(half.mass_kg, 11.75))
	_close("half first moment", half.first_moment_kg_m, [1.0, 1.5, 0.75])
	_close("half datum tensor", half.inertia_datum_kgm2, [14.125, 14.175, 18.65, -0.075, 0.0, -1.5])
	_close("half CG tensor", half.inertia_cg_kgm2,
		[13.8856382978723, 14.0420212765957, 18.3734042553191, 0.0526595744681, 0.0638297872340, -1.4042553191489], 2.0e-11)

	var empty: Dictionary = Inventory.evaluate(prepared, {"fuel-a": 0.0, "fuel-b": 0.0})
	_check("empty inventory evaluates", empty.get("ok", false), str(empty))
	_check("empty mass", is_equal_approx(empty.mass_kg, 10.0))
	_close("empty first moment", empty.first_moment_kg_m, [0.0, 0.0, 0.0])
	_close("empty datum tensor", empty.inertia_datum_kgm2, [10.0, 12.0, 14.0, 0.0, 0.0, 0.0])
	_close("empty CG tensor", empty.inertia_cg_kgm2, [10.0, 12.0, 14.0, 0.0, 0.0, 0.0])
	_close("empty inverse", empty.inverse_inertia_cg_kgm2, [0.1, 1.0 / 12.0, 1.0 / 14.0, 0.0, 0.0, 0.0])


func _test_offcenter_rotation_and_inverse() -> void:
	var prepared: Dictionary = _fixture()
	var full: Dictionary = Inventory.evaluate(prepared, {"fuel-a": 2.0, "fuel-b": 1.5})
	_check("off-center resources move CG", absf(full.cg_body_m[0]) > 0.1 and full.cg_body_m[1] > 0.2)
	_check("rotated resource contributes product of inertia", is_equal_approx(full.inertia_datum_kgm2[3], -0.15))
	_check("off-center yz parallel-axis product retained", is_equal_approx(full.inertia_datum_kgm2[5], -3.0))
	var identity_x: PackedFloat64Array = RB.inertia_mul(full.inertia_cg_kgm2, PackedFloat64Array([full.inverse_inertia_cg_kgm2[0], full.inverse_inertia_cg_kgm2[3], full.inverse_inertia_cg_kgm2[4]]))
	var identity_y: PackedFloat64Array = RB.inertia_mul(full.inertia_cg_kgm2, PackedFloat64Array([full.inverse_inertia_cg_kgm2[3], full.inverse_inertia_cg_kgm2[1], full.inverse_inertia_cg_kgm2[5]]))
	var identity_z: PackedFloat64Array = RB.inertia_mul(full.inertia_cg_kgm2, PackedFloat64Array([full.inverse_inertia_cg_kgm2[4], full.inverse_inertia_cg_kgm2[5], full.inverse_inertia_cg_kgm2[2]]))
	_close("inverse first column", identity_x, [1.0, 0.0, 0.0], 2.0e-12)
	_close("inverse second column", identity_y, [0.0, 1.0, 0.0], 2.0e-12)
	_close("inverse third column", identity_z, [0.0, 0.0, 1.0], 2.0e-12)


func _test_reference_shift() -> void:
	var original: Dictionary = Inventory.evaluate(_fixture(), {"fuel-a": 1.0, "fuel-b": 0.75})
	var shift := PackedFloat64Array([0.7, -1.1, 0.4])
	var moved: Dictionary = Inventory.evaluate(_fixture([shift[0], shift[1], shift[2]]), {"fuel-a": 1.0, "fuel-b": 0.75})
	_check("translated-datum fixture evaluates", moved.get("ok", false), str(moved))
	_check("reference translation preserves mass", is_equal_approx(moved.mass_kg, original.mass_kg))
	_close("reference translation shifts first moment", moved.first_moment_kg_m,
		[original.first_moment_kg_m[0] - original.mass_kg * shift[0], original.first_moment_kg_m[1] - original.mass_kg * shift[1], original.first_moment_kg_m[2] - original.mass_kg * shift[2]])
	_close("reference translation shifts CG", moved.cg_body_m,
		[original.cg_body_m[0] - shift[0], original.cg_body_m[1] - shift[1], original.cg_body_m[2] - shift[2]])
	_close("reference translation preserves central tensor", moved.inertia_cg_kgm2, original.inertia_cg_kgm2)
	var moved_pa: PackedFloat64Array = Inventory.parallel_axis_per_kg(moved.cg_body_m)
	var expected_origin: PackedFloat64Array = original.inertia_cg_kgm2.duplicate()
	for i: int in 6:
		expected_origin[i] += moved.mass_kg * moved_pa[i]
	_close("translated datum tensor matches independent parallel-axis reconstruction", moved.inertia_datum_kgm2, expected_origin)


func _test_validation() -> void:
	var prepared: Dictionary = _fixture()
	_check("reject missing resource", not Inventory.evaluate(prepared, {"fuel-a": 1.0}).ok)
	_check("reject extra resource", not Inventory.evaluate(prepared, {"fuel-a": 1.0, "fuel-b": 1.0, "other": 0.0}).ok)
	_check("reject negative resource mass", not Inventory.evaluate(prepared, {"fuel-a": -0.1, "fuel-b": 0.0}).ok)
	_check("reject over-capacity resource mass", not Inventory.evaluate(prepared, {"fuel-a": 2.1, "fuel-b": 0.0}).ok)
	_check("reject unknown distribution", not Inventory.prepare("datum", [_component("dry", 2.0, [0.0, 0.0, 0.0], [1.0, 1.0, 1.0, 0.0, 0.0, 0.0])],
		[{id = "resource", capacity_mass_kg = 1.0, center_body_m = PackedFloat64Array([0.0, 0.0, 0.0]),
			inertia_centroid_at_capacity_kgm2 = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]), distribution_model = "unspecified"}]).ok)
	_check("reject duplicate stable id", not Inventory.prepare("datum", [_component("same", 2.0, [0.0, 0.0, 0.0], [1.0, 1.0, 1.0, 0.0, 0.0, 0.0])],
		[_resource("same", 1.0, [1.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0, 0.0, 0.0])]).ok)
	_check("reject non-SPD central aircraft tensor at evaluation", not Inventory.evaluate(
		Inventory.prepare("datum", [_component("line-mass", 1.0, [0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0, 0.0, 0.0])], []), {}).ok)
	_check("reject non-PSD component tensor", not Inventory.prepare("datum",
		[_component("bad", 1.0, [0.0, 0.0, 0.0], [-1.0, 1.0, 1.0, 0.0, 0.0, 0.0])], []).ok)
	_check("reject empty model", not Inventory.prepare("datum", [], []).ok)


func _test_glow_kernel_byte_parity() -> void:
	var cases: Array[Dictionary] = [
		{center = PackedFloat64Array([0.173, -0.241, 0.417]), size = PackedFloat64Array([0.383, 0.255, 0.149])},
		{center = PackedFloat64Array([-0.5, 0.0, 0.125]), size = PackedFloat64Array([0.25, 0.1, 0.05])},
		{center = PackedFloat64Array([0.0, 0.0, 0.0]), size = PackedFloat64Array([0.0, 0.0, 0.0])},
	]
	for index: int in cases.size():
		var item: Dictionary = cases[index]
		var expected: PackedFloat64Array = _legacy_glow_tensor_per_kg(item.center, item.size)
		var got: PackedFloat64Array = FuelMass.tensor_per_kg(item.center, item.size)
		_check("Glow kernel exact byte parity case %d" % index, expected.to_byte_array() == got.to_byte_array(),
			"legacy=%s shared=%s" % [expected, got])


## Frozen formula copied from the pre-delegation Glow helper for exact-output comparison.
func _legacy_glow_tensor_per_kg(position: PackedFloat64Array, size: PackedFloat64Array) -> PackedFloat64Array:
	var x: float = position[0]
	var y: float = position[1]
	var z: float = position[2]
	return PackedFloat64Array([(size[1] * size[1] + size[2] * size[2]) / 12.0 + y * y + z * z,
		(size[0] * size[0] + size[2] * size[2]) / 12.0 + x * x + z * z,
		(size[0] * size[0] + size[1] * size[1]) / 12.0 + x * x + y * y,
		-x * y, -x * z, -y * z])
