extends SceneTree
## Import closeout packet 6: donor configurations. An elevon flying wing is proposed on the stock
## Skywalker X8 physics with its appearance fitted to the donor span; others are refused or routed elsewhere.
const R := preload("res://workshop/creator/result.gd")
const Donor := preload("res://workshop/creator/clearview/donor.gd")
const Setup := preload("res://workshop/creator/clearview/setup.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Importer := preload("res://workshop/creator/source_importer.gd")
const Fixture := preload("res://tests/creator_fixtures.gd")
const SetupTest := preload("res://tests/test_creator_clearview_setup.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	var wing := "AC3Db\nMATERIAL \"m\" rgb 1 1 1 amb 0.2 0.2 0.2 emis 0 0 0 spec 0.5 0.5 0.5 shi 10 trans 0\nOBJECT world\nkids 1\nOBJECT poly\nname \"LElevon\"\nnumvert 5\n-0.1 0 -0.8\n0.2 0 -0.8\n0.2 0 0.8\n-0.1 0 0.8\n0.05 0.08 0\nnumsurf 2\nSURF 0x30\nmat 0\nrefs 4\n0 0 0\n1 1 0\n2 1 1\n3 0 1\nSURF 0x30\nmat 0\nrefs 3\n0 0 0\n1 1 0\n4 0 1\nkids 0\n"
	var converted: Dictionary = SetupTest._converted(wing)
	check("flying-wing fixture converts", converted.ok)
	if converted.ok:
		var proposed := Donor.propose(converted.value.source)
		check("an elevon flying wing gets the X8 donor", proposed.ok and proposed.value.donor_id == Donor.FLYING_WING_DONOR
			and Catalog.can_fly(proposed.value.donor_id))
		check("its appearance is fitted to the donor span", proposed.ok and absf(float(proposed.value.source_span_m) - 1.6) < 1e-6
			and absf(float(proposed.value.placement.unit_scale) * float(proposed.value.source_span_m) - Donor.FLYING_WING_SPAN_M) < 1e-9
			and proposed.value.placement.nose_axis == "-x" and proposed.value.placement.up_axis == "+y")
	var plain: Dictionary = SetupTest._converted(wing.replace("LElevon", "wing"))
	check("a conventional model has no donor", plain.ok and not Donor.propose(plain.value.source).ok)
	var heli: Dictionary = SetupTest._converted_with(wing, "verNumber 3\nmodelType 0\n")
	check("a helicopter is not a fixed-wing donor", heli.ok and not Donor.propose(heli.value.source).ok)
	var ordinary := Importer.inspect_bytes(Fixture.airplane_glb(), "ordinary.glb")
	check("an ordinary model has no donor", ordinary.ok and not Donor.propose(ordinary.value).ok)
	print("ClearView donor: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func check(label: String, good: bool) -> void:
	checks += 1
	if not good:
		failures += 1
		printerr("FAIL: ", label)
