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
const Creator := preload("res://ui/aircraft_creator.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const CvFixture := preload("res://tests/test_creator_clearview_readers.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
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
	if plain.ok:
		# Last resort: any aeroplane the estimate cannot fly gets the stock electric trainer, fitted to it.
		var trainer := Donor.propose(plain.value.source, true)
		check("the fallback offers the stock trainer", trainer.ok and trainer.value.donor_id == Donor.TRAINER_DONOR
			and Catalog.can_fly(trainer.value.donor_id) and not Catalog.is_rotorcraft(trainer.value.donor_id)
			and trainer.value.message == Donor.TRAINER and Donor.TRAINER_DONOR in Donor.DONORS)
		check("the trainer fits the larger of span and length to its own span", trainer.ok
			and absf(float(trainer.value.placement.unit_scale) * float(trainer.value.source_span_m) - Donor.TRAINER_SPAN_M) < 1e-9
			and float(trainer.value.source_span_m) >= 1.6 - 1e-9)
	if converted.ok:
		var elevons := Donor.propose(converted.value.source, true)
		check("a flying wing keeps the X8 even as a fallback", elevons.ok and elevons.value.donor_id == Donor.FLYING_WING_DONOR)
	var heli: Dictionary = SetupTest._converted_with(wing, "verNumber 3\nmodelType 0\n")
	check("a helicopter is not a fixed-wing donor", heli.ok and not Donor.propose(heli.value.source).ok
		and not Donor.propose(heli.value.source, true).ok)
	var ordinary := Importer.inspect_bytes(Fixture.airplane_glb(), "ordinary.glb")
	check("an ordinary model has no donor", ordinary.ok and not Donor.propose(ordinary.value).ok
		and not Donor.propose(ordinary.value, true).ok)
	await _offer(wing.replace("LElevon", "wing"))
	print("ClearView donor: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func check(label: String, good: bool) -> void:
	checks += 1
	if not good:
		failures += 1
		printerr("FAIL: ", label)


## The Creator offers the trainer as a last resort, says why, and requests an airborne donor flight.
func _offer(ac: String) -> void:
	var directory := "user://clearview-donor-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := directory + "/plane.zip"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(CvFixture._zip_bytes([["Plane/params.txt", "verNumber 5\nmodelType 1\nmodelName body.ac\n".to_ascii_buffer()],
		["Plane/data/body.ac", ac.to_ascii_buffer()]]))
	file.close()
	var wizard := Creator.new()
	wizard.store_root = directory + "/library"
	wizard.theme = UiTheme.build()
	root.add_child(wizard)
	await process_frame
	wizard.request_import(path)
	var deadline := Time.get_ticks_msec() + 30000
	while (wizard.import_state().state == "inspecting" or wizard.save_state().opening) and Time.get_ticks_msec() < deadline:
		await process_frame
	var requests := []
	wizard.test_fly_requested.connect(func(payload: Dictionary) -> void: requests.append(payload))
	wizard.call("_offer_trainer", "Reason for the fallback")
	var dialog: ConfirmationDialog = wizard.get("_confirm")
	var text: Label = wizard.get("_confirm_text")
	check("the trainer offer names its reason and the stock physics", wizard.import_state().state == "imported" and dialog.visible
		and dialog.ok_button_text == Donor.TRAINER_BUTTON and text.text.contains("Reason for the fallback") and text.text.contains("Ugly Stick"))
	dialog.hide()
	wizard.call("_on_confirmed")
	check("confirming requests an airborne trainer donor flight", requests.size() == 1 and requests[0].has("creator_donor")
		and requests[0].creator_donor.donor_id == Donor.TRAINER_DONOR and requests[0].start_choice == "airborne"
		and requests[0].creator_donor.source == wizard.document().source())
	wizard.queue_free()
	await process_frame
