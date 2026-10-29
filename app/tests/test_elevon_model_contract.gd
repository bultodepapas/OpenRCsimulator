# X8-02: elevon control roles in the shared model contract. A family declares the four conventional roles or exactly
# both elevons; an elevon renders its side's aileron plus the elevator (trailing edge up positive), the exact inverse of
# the physics decomposition elevator = (eR + eL) / 2, aileron_right = (eR - eL) / 2, aileron_left = (eL - eR) / 2.
extends SceneTree

const Imported := preload("res://aircraft/imported_model.gd")
const Manifest := preload("res://aircraft/model_manifest.gd")
const Registry := preload("res://aircraft/model_registry.gd")
const ELEVON_FAMILY := "moonrunner-x99"
const CONVENTIONAL_FAMILY := "f4u-corsair-250"

var _checks := 0
var _failures := 0


func _initialize() -> void:
	var elevon: Dictionary = Registry.describe(ELEVON_FAMILY)
	var conventional: Dictionary = Registry.describe(CONVENTIONAL_FAMILY)
	_check("the registry accepts the elevon family", elevon.get("ok", false), str(elevon.get("errors", [])))
	_check("the registry still accepts a conventional family", conventional.get("ok", false), str(conventional.get("errors", [])))
	if elevon.get("ok", false) and conventional.get("ok", false):
		_test_role_layouts(elevon.manifest, conventional.manifest)
		_test_role_degrees()
		_test_rendered_elevons(elevon.manifest)
	print("Elevon model contract: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_role_layouts(elevon: Dictionary, conventional: Dictionary) -> void:
	_check("the elevon family binds exactly the two elevon roles", elevon.bindings.controls.keys().size() == 2
		and elevon.bindings.controls.has_all(["elevon_left", "elevon_right"]))
	var with_flaps := elevon.duplicate(true)
	with_flaps.bindings.controls.flap_left = conventional.bindings.controls.flap_left.duplicate(true)
	_check("flap roles stay optional beside elevons", Manifest.validate(with_flaps).ok, str(Manifest.validate(with_flaps).errors))
	var mixed := elevon.duplicate(true)
	mixed.bindings.controls.aileron_left = conventional.bindings.controls.aileron_left.duplicate(true)
	_expect_code("elevons mixed with an aileron are rejected", mixed, "MODEL_CONTROL_LAYOUT_MIXED", "$.bindings.controls.aileron_left")
	for role: String in ["elevator", "rudder"]:
		var other := elevon.duplicate(true)
		other.bindings.controls[role] = conventional.bindings.controls[role].duplicate(true)
		_expect_code("elevons mixed with the %s are rejected" % role, other, "MODEL_CONTROL_LAYOUT_MIXED", "$.bindings.controls." + role)
	for side: String in ["left", "right"]:
		var single := elevon.duplicate(true)
		single.bindings.controls.erase("elevon_" + ("right" if side == "left" else "left"))
		_expect_code("a single %s elevon is rejected" % side, single, "MODEL_CONTROL_MISSING", "$.bindings.controls.elevon_" + ("right" if side == "left" else "left"))
	var none := elevon.duplicate(true)
	none.bindings.controls = {}
	_expect_code("no control roles at all falls back to the conventional requirement", none, "MODEL_CONTROL_MISSING", "$.bindings.controls.rudder")
	var added := conventional.duplicate(true)
	added.bindings.controls.elevon_left = elevon.bindings.controls.elevon_left.duplicate(true)
	_expect_code("a conventional family with an added elevon is rejected", added, "MODEL_CONTROL_LAYOUT_MIXED", "$.bindings.controls.rudder")
	var rudderless := conventional.duplicate(true)
	rudderless.bindings.controls.erase("rudder")
	_expect_code("a conventional family still requires its rudder", rudderless, "MODEL_CONTROL_MISSING", "$.bindings.controls.rudder")
	var unknown := elevon.duplicate(true)
	unknown.bindings.controls.elevon_centre = elevon.bindings.controls.elevon_left.duplicate(true)
	_expect_code("an unknown elevon-like role is rejected", unknown, "MODEL_CONTROL_ROLE_UNKNOWN", "$.bindings.controls.elevon_centre")


func _test_role_degrees() -> void:
	var conventional := {aileron_right = 7.0, aileron_left = -5.0, elevator = 3.0, rudder = -2.0}
	var same := true
	for role: String in conventional:
		same = same and Imported.role_degrees(role, conventional) == conventional[role]
	_check("conventional roles read their own surface angle unchanged", same and Imported.role_degrees("flap_left", conventional) == 0.0)
	var pitch := {aileron_right = 0.0, aileron_left = 0.0, elevator = 12.0, rudder = 0.0}
	_check("pitch only: both elevons equal the elevator", Imported.role_degrees("elevon_left", pitch) == 12.0
		and Imported.role_degrees("elevon_right", pitch) == 12.0)
	var roll := {aileron_right = 9.0, aileron_left = -9.0, elevator = 0.0, rudder = 0.0}
	_check("roll only: the elevons are opposite", Imported.role_degrees("elevon_right", roll) == 9.0
		and Imported.role_degrees("elevon_left", roll) == -9.0)
	# The physics decomposition of saturated physical elevons (eR at the trailing-edge-up stop) renders them exactly.
	var worst := 0.0
	for pair: Array in [[26.76, -6.0], [26.76, 26.76], [-26.85, 26.76], [-26.85, -26.85], [0.25, -0.125]]:
		var surfaces := {elevator = (pair[0] + pair[1]) / 2.0, aileron_right = (pair[0] - pair[1]) / 2.0,
			aileron_left = (pair[1] - pair[0]) / 2.0, rudder = 0.0}
		worst = maxf(worst, maxf(absf(Imported.role_degrees("elevon_right", surfaces) - pair[0]),
			absf(Imported.role_degrees("elevon_left", surfaces) - pair[1])))
	_check("render mapping inverts the physics decomposition, saturation included", worst < 1e-12, str(worst) + " deg")
	_check("an empty surface dictionary renders neutral elevons", Imported.role_degrees("elevon_left", {}) == 0.0
		and Imported.role_degrees("elevon_right", {}) == 0.0)


func _test_rendered_elevons(manifest: Dictionary) -> void:
	var built := Imported.build_checked(manifest.duplicate(true))
	_check("the shared importer builds the elevon family", built.ok, str(built.errors))
	if not built.ok: return
	var model: Dictionary = built.model
	_check("the registry accepts the built elevon model", Registry.validate_derived(manifest, model).ok)
	var left: Dictionary = model.hinges.elevon_left
	var right: Dictionary = model.hinges.elevon_right
	Imported.apply_surfaces(model, {aileron_right = 0.0, aileron_left = 0.0, elevator = 10.0, rudder = 0.0})
	_check("pitch only turns both elevons by the elevator angle", _at(left, 10.0) and _at(right, 10.0))
	Imported.apply_surfaces(model, {aileron_right = 8.0, aileron_left = -8.0, elevator = 0.0, rudder = 0.0})
	_check("roll only turns the elevons in opposite senses", _at(right, 8.0) and _at(left, -8.0))
	Imported.apply_surfaces(model, {aileron_right = 6.0, aileron_left = -6.0, elevator = 4.0, rudder = 0.0})
	_check("pitch and roll add per side", _at(right, 10.0) and _at(left, -2.0))
	Imported.set_visual_surfaces(model, {elevator = 15.0})
	_check("the visual-only path leaves physical elevons alone", _at(right, 10.0) and _at(left, -2.0))
	Imported.apply_surfaces(model, {})
	_check("neutral surfaces restore both imported rest bases", left.node.basis == left.rest and right.node.basis == right.rest)
	model.root.free()


## The hinge turned `app_degrees` (trailing edge up) through its geometry sign about its rest +X.
func _at(hinge: Dictionary, app_degrees: float) -> bool:
	return hinge.node.basis.is_equal_approx(Basis(hinge.axis, deg_to_rad(app_degrees * float(hinge.app_sign))) * hinge.rest)


func _expect_code(label: String, manifest: Dictionary, code: String, path: String) -> void:
	var result := Manifest.validate(manifest)
	var found := false
	for issue: Dictionary in result.diagnostics:
		found = found or (issue.code == code and issue.path == path)
	_check(label, not result.ok and found, str(result.diagnostics))


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])
