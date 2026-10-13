## CR-01d: every shipped aircraft names its crash-hull points, the names agree with the geometry, invalid names are
## refused, and crash presentation uses them (docs/plans/crash-realism.md §3.2).
extends SceneTree

const AircraftData = preload("res://physics/aircraft_data.gd")
const Contract = preload("res://physics/aircraft_contract.gd")
const Director = preload("res://render/crash/director.gd")
const Severity = preload("res://render/crash/severity.gd")
const Wreck = preload("res://render/crash/wreck.gd")

const DATA_DIR := "res://data/aircraft/"
const TAIL := ["tail_end", "left_stab_tip", "right_stab_tip", "fin_top"]
const FORWARD := ["spinner", "propeller", "nose"]
const CENTRELINE := ["spinner", "nose", "tail_end", "fin_top", "canopy", "belly"]

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_vocabulary_matches_contract()
	var files := _aircraft_files()
	_check("all aircraft data files are found", files.size() >= 9)
	for path in files:
		_fleet_labels(path)
	_loader_rejects()
	_component_choice()
	_presentation_mapping()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print(("ok   " if ok else "FAIL ") + label)


func _aircraft_files() -> PackedStringArray:
	var out := PackedStringArray()
	for name in DirAccess.get_files_at(DATA_DIR):
		if name.ends_with(".json"):
			out.append(DATA_DIR + name)
	return out


func _vocabulary_matches_contract() -> void:
	var spec: Variant = JSON.parse_string(FileAccess.get_file_as_string(Contract.SPEC_PATH))
	var values: Array = []
	for rule: Dictionary in spec.enum_paths:
		if rule.path == "/crash_hull_components/*":
			values = rule.values
	_check("loader vocabulary equals the contract enum path", values == AircraftData.HULL_COMPONENTS)


func _fleet_labels(path: String) -> void:
	var loaded: Dictionary = AircraftData.load_file(path)
	var id := path.get_file().get_basename()
	_check("%s loads" % id, loaded.ok)
	if not loaded.ok:
		print(loaded.errors)
		return
	var model: Dictionary = loaded.model
	var hull: PackedFloat64Array = model.crash_hull # body FRD about the CG: x fwd, y right, z down
	var names: PackedStringArray = model.crash_hull_components
	_check("%s names every hull point" % id, names.size() == hull.size() / 3 and names.size() >= 4)
	if names.size() != hull.size() / 3:
		return
	var span := float(model.reference.b)
	var sides_ok := true
	var tips_ok := true
	var centre_ok := true
	var fore_aft_ok := true
	var fin_z := INF
	var other_z := INF
	var vertical_ok := true
	var has := {}
	for i in names.size():
		var name := names[i]
		has[name] = true
		var x := hull[3 * i]
		var y := hull[3 * i + 1]
		var z := hull[3 * i + 2]
		if name.begins_with("left_") and y >= 0.0 or name.begins_with("right_") and y <= 0.0:
			sides_ok = false
		if name.ends_with("_wing_tip") and absf(y) < 0.45 * span:
			tips_ok = false
		if CENTRELINE.has(name) and absf(y) > 0.05 * span:
			centre_ok = false
		if TAIL.has(name) and x >= 0.0 or FORWARD.has(name) and x <= 0.0:
			fore_aft_ok = false
		if name == "fin_top":
			fin_z = minf(fin_z, z)
		else:
			other_z = minf(other_z, z)
		# Body z points down: a canopy sits above the CG, a belly below it.
		if name == "canopy" and z >= 0.0 or name == "belly" and z <= 0.0:
			vertical_ok = false
	_check("%s left/right names match the side of the CG" % id, sides_ok)
	_check("%s wing-tip names sit at the span ends" % id, tips_ok)
	_check("%s centreline names sit on the centreline" % id, centre_ok)
	_check("%s tail names are aft and nose names forward of the CG" % id, fore_aft_ok)
	_check("%s fin top is the highest hull point" % id, has.has("fin_top") and fin_z < other_z)
	_check("%s canopy names sit above and belly names below the CG" % id, vertical_ok)
	_check("%s names both wing tips" % id, has.has("left_wing_tip") and has.has("right_wing_tip"))


func _loader_rejects() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA_DIR + "jensen_ugly_stik_60.json"))
	var absent := raw.duplicate(true)
	absent.erase("crash_hull_components")
	var absent_result: Dictionary = AircraftData.validate_and_derive(absent)
	_check("labels are optional: absent loads with no names", absent_result.ok and absent_result.model.crash_hull_components.is_empty())
	var short := raw.duplicate(true)
	short.crash_hull_components.remove_at(0)
	_check("a label list shorter than the hull is refused", not AircraftData.validate_and_derive(short).ok)
	var unknown := raw.duplicate(true)
	unknown.crash_hull_components[0] = "left_wingtip"
	var unknown_result: Dictionary = AircraftData.validate_and_derive(unknown)
	_check("an unknown name is refused by the contract", not unknown_result.ok and str(unknown_result.errors).contains("crash_hull_components"))
	var typed := raw.duplicate(true)
	typed.crash_hull_components[0] = 3
	_check("a non-string name is refused", not AircraftData.validate_and_derive(typed).ok)
	var shape := raw.duplicate(true)
	shape.crash_hull_components = "belly"
	_check("a non-array value is refused", not AircraftData.validate_and_derive(shape).ok)
	# The v1 research path shares the loader check.
	var legacy := AircraftData.legacy_v1_input(raw)
	legacy.crash_hull_components = ["belly"]
	_check("the legacy path refuses a mismatched list too", not AircraftData.validate_and_derive(legacy).ok)
	# The contract does not run on the legacy path; the loader's own vocabulary check must.
	var legacy_name := AircraftData.legacy_v1_input(raw)
	legacy_name.crash_hull_components[0] = "left_wingtip"
	_check("the legacy path refuses an unknown name", not AircraftData.validate_and_derive(legacy_name).ok)


func _component_choice() -> void:
	var labels := PackedStringArray(["left_wing_tip", "right_wing_tip", "spinner", "belly"])
	var point := PackedFloat64Array([0.1, 0.0, 0.05])
	var named: Dictionary = Director.component_for("hull_contact", 2, point, labels, 1.5, 0.3)
	_check("a labelled struck point names the component", named.component == "spinner" and not named.is_estimate)
	var scenery: Dictionary = Director.component_for("scenery", 0, point, labels, 1.5, 0.3)
	_check("scenery contacts use the same hull label", scenery.component == "left_wing_tip" and not scenery.is_estimate)
	var gear: Dictionary = Director.component_for("gear_limit", 1, point, labels, 1.5, 0.3)
	_check("gear overtravel stays the gear", gear.component == "gear" and gear.is_estimate)
	var unlabelled: Dictionary = Director.component_for("hull_contact", 1, PackedFloat64Array([0.0, 0.7, 0.0]), PackedStringArray(), 1.5, 0.3)
	_check("without labels the geometric estimate remains and is marked", unlabelled.component == "wing" and unlabelled.is_estimate)
	var outside: Variant = Director.component_for("hull_contact", 9, PackedFloat64Array([-0.5, 0.0, 0.0]), labels, 1.5, 0.3)
	_check("an index outside the labels falls back to the estimate", outside is Dictionary and outside.component == "tail" and outside.is_estimate)
	_check("no struck point and no label is unknown", Director.component_for("hull_contact", -1, PackedFloat64Array(), labels, 1.5, 0.3).component == "unknown")


func _presentation_mapping() -> void:
	var groups := {
		"left_wing_tip": "wingtip", "right_wing_tip": "wingtip", "spinner": "propeller", "propeller": "propeller",
		"nose": "fuselage", "belly": "fuselage", "tail_end": "tail", "left_stab_tip": "tail", "right_stab_tip": "tail",
		"fin_top": "tail", "canopy": "canopy",
	}
	_check("the group table covers the whole vocabulary", groups.size() == AircraftData.HULL_COMPONENTS.size())
	for name: String in AircraftData.HULL_COMPONENTS:
		var result: Dictionary = Severity.estimate(3.0, 5.0, 0.0, 90.0, "grass", name)
		_check("%s grades in the %s group" % [name, groups.get(name, "?")], result.component_group == groups.get(name, ""))
	var wreck := Wreck.new()
	_check("wreck releases the left wing first for a left tip", wreck._component_matches("wing_left", "left_wing_tip") and not wreck._component_matches("wing_right", "left_wing_tip"))
	_check("wreck releases the propeller for a spinner hit", wreck._component_matches("propeller", "spinner"))
	_check("wreck releases the tailplane for a stab tip", wreck._component_matches("horizontal_tail", "right_stab_tip"))
	_check("wreck releases the fin for a fin-top hit", wreck._component_matches("vertical_tail", "fin_top"))
	wreck.free()
