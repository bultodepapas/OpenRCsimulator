## A36 R4-F02: a tail patch carries one washed-minus-free wake load, so it may be declared once. Admission refuses
## duplicated, overlapping or over-area wake pieces and pieces on an undeclared tail; disjoint pieces stay admitted.
extends SceneTree

const Data := preload("res://physics/aircraft_data.gd")
const Contract := preload("res://physics/aircraft_contract.gd")

const F4U := "res://data/aircraft/f4u_corsair_250.json"
const X8 := "res://data/aircraft/moonrunner_x99.json"
const STIK := "res://data/aircraft/jensen_ugly_stik_60.json"
const SOURCE := "A36 R4-F02 synthetic wake-coverage fixture"

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, passed: bool, detail: Variant = "") -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL %s — %s" % [label, str(detail)])


func _raw(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _pieces(raw: Dictionary) -> Array:
	return raw.propulsion.propeller.slipstream.pieces


func _errors(raw: Dictionary) -> String:
	return "\n".join(Data.validate_and_derive(raw).errors)


func _run() -> void:
	var stock := _raw(F4U)
	check("stock F4U wake pieces are admitted", Data.validate_and_derive(stock).ok, _errors(stock))
	for path: String in ["res://data/aircraft/gp_extra_300s_60.json", "res://data/aircraft/p51d_mustang_120.json"]:
		var other := _raw(path)
		check("stock %s wake pieces are admitted" % path.get_file(), Contract.validate(other).is_empty(), Contract.validate(other))
	# R4 witness class: the same vertical patch declared twice.
	var duplicate := _raw(F4U)
	_pieces(duplicate).append(_pieces(duplicate)[0].duplicate(true))
	var duplicate_errors := _errors(duplicate)
	check("a duplicated vertical piece is refused for area and overlap", duplicate_errors.contains("more than its")
		and duplicate_errors.contains("overlaps wake piece 0"), duplicate_errors)
	# Two halves of the same fin piece, end to end: disjoint and the same total area.
	var halves := _raw(F4U)
	var fin: Dictionary = _pieces(halves)[0]
	var span := float(fin.span.value)
	var area := float(fin.area.value)
	var upper: Dictionary = fin.duplicate(true)
	fin.span.value = 0.5 * span
	fin.area.value = 0.5 * area
	upper.span.value = 0.5 * span
	upper.area.value = 0.5 * area
	upper.root.value = [float(fin.root.value[0]), float(fin.root.value[1]), float(fin.root.value[2]) + 0.5 * span]
	for piece: Dictionary in [fin, upper]:
		for key: String in ["span", "area", "root"]:
			piece[key].source = SOURCE
	_pieces(halves).insert(1, upper)
	check("two disjoint halves of the fin piece are admitted", Contract.validate(halves).is_empty(), Contract.validate(halves))
	# Same total area but the halves overlap by a quarter span.
	var overlapping := halves.duplicate(true)
	var shifted: Dictionary = _pieces(overlapping)[1]
	shifted.root.value = [float(fin.root.value[0]), float(fin.root.value[1]), float(fin.root.value[2]) + 0.25 * span]
	var overlap_errors := "\n".join(Contract.validate(overlapping))
	check("overlapping fin pieces within the area total are refused", overlap_errors.contains("overlaps wake piece 0")
		and not overlap_errors.contains("more than its"), overlap_errors)
	# Opposite-direction horizontal halves from the centerline stay disjoint (stock layout); a third copy does not.
	var tripled := _raw(F4U)
	_pieces(tripled).append(_pieces(tripled)[1].duplicate(true))
	var tripled_errors := "\n".join(Contract.validate(tripled))
	check("a repeated horizontal half is refused", tripled_errors.contains("horizontal tail")
		and tripled_errors.contains("overlaps wake piece 1"), tripled_errors)
	# A tailless airframe declares no horizontal tail: a horizontal wake piece has no physical surface.
	var tailless := _raw(X8)
	var stik := _raw(STIK)
	tailless.capabilities.propulsion_layout = "single_tractor"
	tailless.capabilities.energy = "prescribed_fuel"
	tailless.propulsion = stik.propulsion.duplicate(true)
	tailless.propulsion.id = "propulsion_main"
	var q := func(value: Variant, unit: String) -> Dictionary:
		return {value = value, unit = unit, kind = "estimated", source = SOURCE}
	tailless.propulsion.propeller.thrust_angles = q.call([0.0, 0.0], "deg")
	tailless.propulsion.propeller.thrust_line_offset = q.call([-0.435, 0.0, -0.004255534], "m")
	tailless.propulsion.propeller.slipstream = {hub = q.call([0.0, 0.0, 0.0], "m"), wash_factor = q.call([0.8, 1.8], "1"),
		swirl_factor = q.call(0.0, "1"), vertical_drift = q.call(0.5, "1"),
		pieces = [{surface = "horizontal", area = q.call(0.02, "m2"), root = q.call([0.48, 0.0, 0.0], "m"),
			span_dir = q.call([0.0, 1.0, 0.0], "1"), span = q.call(0.1, "m"), chords = q.call([0.2, 0.2], "m")}]}
	var tailless_errors := "\n".join(Contract.validate(tailless))
	check("a horizontal wake piece on a tailless airframe is refused", tailless_errors.contains("does not declare"),
		tailless_errors)
	print("wake coverage: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)
