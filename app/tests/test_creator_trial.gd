extends SceneTree
## AC-09/AC-10: the authoring document, the frozen Creator trial and its start check.
const R := preload("res://workshop/creator/result.gd")
const CreatorBytes := preload("res://workshop/creator/bytes.gd")
const Importer := preload("res://workshop/creator/source_importer.gd")
const Authoring := preload("res://workshop/creator/authoring.gd")
const Definition := preload("res://workshop/creator/definition.gd")
const CreatorTrial := preload("res://workshop/creator/trial.gd")
const Builder := preload("res://workshop/creator/visual_builder.gd")
const RecordLoader := preload("res://workshop/creator/record_loader.gd")
const AcceptedCandidate := preload("res://workshop/creator/accepted_candidate.gd")
const Session := preload("res://sim/flight_session.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Weather := preload("res://physics/wind_config.gd")

var failures := 0


func _initialize() -> void:
	_numbers()
	var document: RefCounted = _document()
	_fields(document)
	_snapshot(document)
	_trial(document)
	print("Creator trial: %d failures" % failures)
	quit(1 if failures else 0)


## A flat 1.5 m span "airplane" drawn in millimetres, nose along +y, up along +z.
func _plane_stl() -> PackedByteArray:
	var triangles: Array = [
		[[0, 500, 0], [-40, -700, 0], [40, -700, 0]],
		[[-750, 100, 0], [750, 100, 0], [0, 200, 0]],
		[[0, -700, 0], [0, -620, 0], [0, -700, 120]],
	]
	var bytes := PackedByteArray()
	bytes.resize(84 + 50 * triangles.size())
	bytes.encode_u32(80, triangles.size())
	var offset := 84
	for triangle: Array in triangles:
		offset += 12
		for vertex: Array in triangle:
			for component: int in 3:
				bytes.encode_float(offset, float(vertex[component]))
				offset += 4
		offset += 2
	return bytes


func _numbers() -> void:
	check("plain number", Authoring.parse_number("1.25") == 1.25)
	check("decimal comma", Authoring.parse_number("1,25") == 1.25)
	check("sign and exponent", Authoring.parse_number("-2.5e-1") == -0.25)
	check("surrounding spaces", Authoring.parse_number("  3  ") == 3.0)
	for bad: String in ["", " ", "1.5abc", "abc", "1,2,3", "1.2,3", "1e999", "nan", "inf", "0x10", "--1", "1 2"]:
		check("refuses \"%s\"" % bad, is_nan(Authoring.parse_number(bad)))
	var first := Authoring.new_uuid()
	check("uuid v4 shape", first.length() == 36 and first[14] == "4" and first[19] in "89ab" and first != Authoring.new_uuid())


func _document() -> RefCounted:
	var document := Authoring.new()
	check("a new document has nothing resolved", document.value("wing/span") == null and document.source() == null
		and document.step_status("import") == Authoring.STATUS_NOT_STARTED)
	check("a new document cannot fly", not document.issues().is_empty())
	var admitted: Dictionary = Importer.inspect_bytes(_plane_stl(), "plane.stl")
	check("fixture admitted", admitted.ok)
	if not admitted.ok:
		return document
	document.set_source(admitted.value)
	check("import complete", document.step_status("import") == Authoring.STATUS_COMPLETE)
	check("placement starts unresolved", not document.placement_result().ok and document.placed_bounds().is_empty()
		and document.step_status("orient_size") == Authoring.STATUS_NOT_STARTED)
	document.set_axis("nose_axis", "+y")
	check("placement in progress", document.step_status("orient_size") == Authoring.STATUS_IN_PROGRESS)
	document.set_axis("up_axis", "+z")
	check("scale from a known wingspan", document.set_scale_from_wingspan(1.5)
		and is_equal_approx(float(document.placement().unit_scale), 0.001))
	document.set_units("mm")
	document.set_datum([0.0, 200.0, 0.0])
	check("placement complete", document.placement_result().ok and document.step_status("orient_size") == Authoring.STATUS_COMPLETE)
	var bounds: Dictionary = document.placed_bounds()
	check("real size", not bounds.is_empty() and is_equal_approx(bounds.max[1] - bounds.min[1], 1.5)
		and is_equal_approx(bounds.min[0], -0.3) and is_equal_approx(bounds.max[0], 0.9))
	return document


func _fields(document: RefCounted) -> void:
	var revision: int = document.revision
	check("invalid text is refused", not document.set_raw("wing/span", "1.5 m"))
	check("invalid text stays visible and flagged", document.raw("wing/span") == "1.5 m" and document.is_invalid("wing/span")
		and document.value("wing/span") == null and document.revision > revision)
	check("valid text commits", document.set_raw("wing/span", "1,5") and document.value("wing/span") == 1.5
		and not document.is_invalid("wing/span"))
	check("invalid text keeps the last accepted value", not document.set_raw("wing/span", "wide")
		and document.value("wing/span") == 1.5 and document.is_invalid("wing/span"))
	check("an invalid field is an issue on its step", _has_issue(document.issues(), R.FIELD_INVALID, "wing/span", "aircraft_layout"))
	check("an invalid field blocks compilation", not document.compile().ok)
	check("empty text returns the field to unresolved", document.set_raw("wing/span", "") and document.value("wing/span") == null
		and not document.is_invalid("wing/span"))
	check("an unresolved field is reported, not defaulted", not document.definition().has("wing")
		and not document.issues().is_empty())

	var values: Dictionary = document.starting_values()
	check("starting values follow the model", is_equal_approx(float(values["wing/span"]), 1.5)
		and is_equal_approx(float(values["fuselage/nose_x"]), -0.3) and is_equal_approx(float(values["fuselage/tail_x"]), 0.9))
	check("starting values cover every field", values.size() == Authoring.FIELDS.size())
	document.apply_values(values, true)
	check("layout complete after starting values", document.step_status("aircraft_layout") != Authoring.STATUS_NOT_STARTED)
	check("no inventory yet", document.inventory().is_empty())
	document.propose_inventory()
	check("airframe proposed", document.inventory().size() >= 3)
	var definition: Dictionary = document.definition()
	check("definition shape", str(definition.format) == Definition.FORMAT and definition.wing.span == 1.5
		and definition.horizontal_tail.position.size() == 3 and definition.horizontal_tail.position[1] == 0.0
		and definition.equipment.thrust_angles_deg.size() == 2)
	var issues: Array = document.issues()
	if not issues.is_empty():
		printerr("issues: ", "\n".join(R.texts({diagnostics = issues})))
	check("the estimated starting document can fly", issues.is_empty())

	# A measured item survives a new proposal untouched.
	var id: String = document.add_item("Camera")
	check("item added", not id.is_empty() and document.set_item_raw(id, "mass", "0,05") and document.set_item_raw(id, "x", "0.1"))
	document.set_item_kind(id, "measured")
	check("bad item number refused", not document.set_item_raw(id, "mass", "heavy"))
	document.propose_inventory()
	var kept := false
	for item: Dictionary in document.inventory():
		if str(item.id) == id:
			kept = item.mass == 0.05 and item.position[0] == 0.1 and str(item.kind) == "measured"
	check("measured item kept by a new proposal", kept)
	document.remove_item(id)
	var summary: Dictionary = document.summary()
	check("live summary", float(summary.get("mass_kg", 0.0)) > 0.5 and summary.has("static_margin"))
	check("compile is cached per revision", document.compile() == document.compile())


## A saved document comes back exactly, through JSON, onto the re-admitted source; nothing in a
## snapshot is trusted, and the dirty state follows the content, not the step.
func _snapshot(document: RefCounted) -> void:
	check("an edited, never saved document has unsaved changes", document.has_unsaved_changes())
	document.name = "Saved plane"
	document.set_appearance({"mode": "solid", "color": "#336699"})
	check("invalid text is carried into the snapshot", not document.set_raw("fuselage/width", "wide"))
	var saved: Dictionary = JSON.parse_string(JSON.stringify(document.snapshot("weight_balance")))
	check("snapshot is plain data with its format", str(saved.format) == Authoring.SNAPSHOT_FORMAT
		and str(saved.source_sha256) == document.source().sha256() and str(saved.step) == "weight_balance")
	document.mark_saved("0".repeat(64))
	check("saving clears the unsaved state", not document.has_unsaved_changes() and document.saved_record_sha256 == "0".repeat(64))
	var reopened := Authoring.new()
	var readmitted: Dictionary = Importer.inspect_bytes(document.source().source_bytes(), "plane.stl")
	var restored: Dictionary = reopened.restore(saved, readmitted.value)
	check("snapshot restores onto the re-admitted source", restored.ok and str(restored.value) == "weight_balance")
	check("restored identity, name and paint", reopened.aircraft_uuid() == document.aircraft_uuid() and reopened.name == "Saved plane"
		and reopened.appearance() == {"mode": "solid", "color": "#336699"})
	check("restored placement", reopened.placement_result().ok and reopened.placement() == document.placement())
	check("restored values, evidence and inventory", reopened.definition() == document.definition()
		and reopened.inventory() == document.inventory() and reopened.is_estimated("wing/root_chord") == document.is_estimated("wing/root_chord"))
	check("restored invalid text stays visible and blocking", reopened.raw("fuselage/width") == "wide" and reopened.is_invalid("fuselage/width")
		and not reopened.compile().ok)
	check("same content, same fingerprint", reopened.fingerprint() == document.fingerprint())
	check("another model is refused for this snapshot", not Authoring.new().restore(saved,
		Importer.inspect_bytes(_other_stl(), "other.stl").value).ok)
	check("a missing model is refused for this snapshot", not Authoring.new().restore(saved, null).ok)
	var foreign: Dictionary = saved.duplicate(true)
	foreign.format = "openrc-creator-document v9"
	check("an unknown snapshot format is refused", not Authoring.new().restore(foreign, readmitted.value).ok)
	var hostile: Dictionary = saved.duplicate(true)
	hostile.values["wing/span"] = "1.5"
	hostile.values["no/such/field"] = 3.0
	hostile.inventory.append({"id": "x", "kind": "certified", "mass": 1.0, "position": [0, 0, 0], "size": [0, 0, 0]})
	hostile.placement.unit_scale = -1.0
	var careful := Authoring.new()
	check("a hostile snapshot still restores", careful.restore(hostile, readmitted.value).ok)
	check("but its untyped, unknown and invalid entries are dropped", careful.value("wing/span") == null
		and careful.value("no/such/field") == null and careful.inventory().size() == document.inventory().size()
		and not careful.placement_result().ok)
	var empty := Authoring.new()
	var blank: Dictionary = JSON.parse_string(JSON.stringify(empty.snapshot()))
	check("a document without a model round-trips", Authoring.new().restore(blank, null).ok and not empty.has_unsaved_changes())
	document.set_raw("fuselage/width", Authoring.format_number(float(document.value("fuselage/width"))))
	check("an edit after saving is an unsaved change", document.has_unsaved_changes())
	document.set_appearance({"mode": "original"})


## A different valid model, to prove a snapshot is bound to its own source.
func _other_stl() -> PackedByteArray:
	var bytes := _plane_stl()
	bytes.encode_float(84 + 12, 1.0)
	return bytes


func _trial(document: RefCounted) -> void:
	var compiled: Dictionary = document.compile()
	check("candidate compiles", compiled.ok)
	if not compiled.ok:
		printerr("\n".join(R.texts(compiled)))
		return
	# Reproducibility across a save: the same document, reopened from its snapshot, is the same aircraft.
	var reopened := Authoring.new()
	reopened.restore(JSON.parse_string(JSON.stringify(document.snapshot())),
		Importer.inspect_bytes(document.source().source_bytes(), "plane.stl").value)
	var recompiled: Dictionary = reopened.compile()
	check("a reopened draft compiles to the same exact bytes", recompiled.ok
		and recompiled.value.raw_sha256() == compiled.value.raw_sha256()
		and recompiled.value.definition_sha256() == compiled.value.definition_sha256())
	_provenance(document)
	_domain_bounds(document)
	compiled = document.compile()
	check("candidate still compiles after the provenance and domain checks", compiled.ok)
	if not compiled.ok:
		printerr("\n".join(R.texts(compiled)))
		return
	var payload := {creator_candidate = compiled.value, creator_source = document.source(),
		creator_placement = document.placement(), creator_name = "Test plane", start_choice = "airborne"}
	check("request recognized", CreatorTrial.is_request(payload) and not CreatorTrial.is_request({base_id = "x"}))
	var trial: Dictionary = CreatorTrial.freeze(payload)
	check("trial freezes", trial.get("ok", false))
	if not trial.get("ok", false):
		printerr(trial.get("errors", []))
		return
	check("trial shape", CreatorTrial.is_trial(trial) and str(trial.identity.trial_id).begins_with("creator-")
		and str(trial.identity.aircraft_id).begins_with("user-aircraft-") and trial.scale == 1.0
		and trial.identity.raw_sha256 == CreatorBytes.sha256(trial.raw_bytes) and trial.identity.experimental)
	check("freezing again gives the same identity", CreatorTrial.freeze(payload).identity == trial.identity)
	check("frozen trial verifies", CreatorTrial.verify(trial).ok)
	check("a deep copy still verifies", CreatorTrial.verify(trial.duplicate(true)).ok)

	# Forged or stale inputs.
	var forged := payload.duplicate()
	forged.creator_candidate = {ok = true, value = "trust me"}
	check("a dictionary is not an accepted candidate", not CreatorTrial.freeze(forged).get("ok", false))
	forged = payload.duplicate()
	forged.creator_source = null
	check("a missing source is refused", not CreatorTrial.freeze(forged).get("ok", false))
	forged = payload.duplicate()
	forged.creator_placement = {nose_axis = "+y", up_axis = "+z"}
	check("an unresolved placement is refused", not CreatorTrial.freeze(forged).get("ok", false))
	var tampered: Dictionary = trial.duplicate(true)
	tampered.raw_bytes[10] = tampered.raw_bytes[10] ^ 1
	check("tampered bytes are refused", not CreatorTrial.verify(tampered).ok)
	tampered = trial.duplicate(true)
	tampered.data.model.id = "user-aircraft-other"
	check("a changed model id is refused", not CreatorTrial.verify(tampered).ok)
	# The identity binds the model that flies, not only hash strings: a copy whose model was edited
	# while its bytes and hashes were left alone is refused, because the bytes are loaded again.
	tampered = trial.duplicate(true)
	tampered.data.model.mass_kg = 0.05
	check("an edited model with untouched hashes is refused", not CreatorTrial.verify(tampered).ok)
	tampered = trial.duplicate(true)
	tampered.creator.placement = {}
	check("an emptied placement is refused", not CreatorTrial.verify(tampered).ok)
	tampered = trial.duplicate(true)
	tampered.creator.placement.datum = [0.0, 250.0, 0.0]
	check("a moved datum is refused", not CreatorTrial.verify(tampered).ok)
	tampered = trial.duplicate(true)
	tampered.identity.trial_id = "creator-000000000000000000000000"
	check("an edited trial id is refused", not CreatorTrial.verify(tampered).ok)
	tampered = trial.duplicate(true)
	tampered.identity.qualification = "qualified"
	check("an edited qualification label is refused", not CreatorTrial.verify(tampered).ok)
	# The frozen model is what the exact bytes load to, whatever the candidate object carries.
	var reloaded: Dictionary = RecordLoader.load_bytes(trial.raw_bytes, str(trial.identity.aircraft_id))
	check("the frozen model is loaded from the exact bytes", reloaded.ok and reloaded.model == trial.data.model)
	var hollow: RefCounted = AcceptedCandidate.new()
	forged = payload.duplicate()
	forged.creator_candidate = hollow
	check("an unsealed candidate object is refused", not CreatorTrial.freeze(forged).get("ok", false))
	var moved := payload.duplicate()
	moved.creator_placement = document.placement()
	moved.creator_placement.datum = [0.0, 210.0, 0.0]
	check("a different placement is a different trial", CreatorTrial.freeze(moved).identity.trial_id != trial.identity.trial_id)

	var field: Dictionary = FieldLoader.load_from().field
	var weather: Dictionary = Weather.defaults()
	var airborne: Dictionary = CreatorTrial.check_start(trial, field, weather, Session.START_AIRBORNE)
	check("airborne start assessed and available", airborne.ok and airborne.available)
	if not (airborne.ok and airborne.available):
		printerr("airborne: ", airborne.get("reason", ""))
	else:
		check("the scratch reset is not a published trial", airborne.diagnostics.physical_reset_committed
			and not airborne.diagnostics.root_trial_published and str(airborne.diagnostics.launch_kind) == "trimmed_airborne")
	var hand: Dictionary = CreatorTrial.check_start(trial, field, weather, Session.START_HAND_LAUNCH)
	check("hand launch assessed", hand.ok)
	if hand.ok:
		print("hand launch: available=%s reason=\"%s\" climb_out=%s" % [str(hand.available), str(hand.reason),
			str(hand.diagnostics.get("climb_out", {}))])
		check("hand launch outcome is explicit", hand.available or not str(hand.reason).is_empty())
		if hand.available:
			check("hand launch climbed clear of the ground", hand.diagnostics.climb_out.clear
				and float(hand.diagnostics.climb_out.min_height_m) > CreatorTrial.CLIMB_OUT_MIN_HEIGHT_M)
	var runway: Dictionary = CreatorTrial.check_start(trial, field, weather, Session.START_RUNWAY)
	check("runway is refused, never substituted", not runway.ok and not runway.available and str(runway.start_choice) == Session.START_RUNWAY)
	check("a tampered trial cannot be checked", not CreatorTrial.check_start(tampered, field, weather, Session.START_AIRBORNE).ok)
	check("an invalid field is refused", not CreatorTrial.check_start(trial, {}, weather, Session.START_AIRBORNE).ok)
	var bad_weather: Dictionary = weather.duplicate(true)
	bad_weather["speed_mps"] = NAN
	check("invalid weather is refused", not CreatorTrial.check_start(trial, field, bad_weather, Session.START_AIRBORNE).available)

	# The flight visual Main receives.
	var visual: Dictionary = Builder.build_flight(trial.creator.source, trial.creator.placement)
	check("flight visual", not visual.is_empty() and visual.root is Node3D and str(visual.root.name) == "airplane"
		and visual.propeller is Node3D and not visual.has_propeller and visual._model_builder.has_method("apply_surfaces"))
	check("no flight visual without a placement", Builder.build_flight(trial.creator.source, {}).is_empty())
	if not visual.is_empty():
		(visual.root as Node3D).free()


## A starting value taken from the model's extent or the reference trainer is an estimate until the
## player types it: the record never calls it the player's own, and a mesh is never a source of physics.
func _provenance(document: RefCounted) -> void:
	check("starting values are flagged as estimates", document.is_estimated("wing/span") and document.is_estimated("controls/aileron_deg"))
	var definition: Dictionary = document.definition()
	check("the definition states the evidence", definition.has("evidence") and str(definition.evidence.get("wing/span", "")) == "estimated"
		and str(definition.evidence.get("equipment/hub_position", "")) == "estimated")
	var record: Dictionary = JSON.parse_string((document.compile().value.raw_bytes() as PackedByteArray).get_string_from_utf8())
	check("an unconfirmed wingspan is recorded as estimated", str(record.reference.wing_span.kind) == "estimated"
		and str(record.reference.wing_span.source).contains("not confirmed by the player"))
	check("unconfirmed control travel is recorded as estimated", str(record.controls.max_throw.aileron.kind) == "estimated"
		and str(record.controls.servo_full_throw_time.kind) == "estimated")
	check("unconfirmed charge and thrust angles are recorded as estimated",
		str(record.propulsion.battery.initial_soc.kind) == "estimated" and str(record.propulsion.propeller.thrust_angles.kind) == "estimated")
	var battery_item: Dictionary = {}
	for item: Dictionary in record.inventory:
		if str(item.get("energy_source", "")) == "lipo":
			battery_item = item
	check("an unconfirmed battery position is recorded as estimated", not battery_item.is_empty()
		and str(battery_item.position.kind) == "estimated")
	check("no record value claims to be measured", not JSON.stringify(record).contains("\"kind\":\"measured\""))

	# Typing a value makes it the player's; one typed component does not confirm a whole vector.
	check("typing confirms a field", document.set_raw("wing/span", "1.5") and not document.is_estimated("wing/span"))
	document.set_raw("equipment/battery_position/0", Authoring.format_number(float(document.value("equipment/battery_position/0"))))
	definition = document.definition()
	check("a typed field leaves the evidence map", not definition.evidence.has("wing/span")
		and str(definition.evidence.get("equipment/battery_position", "")) == "estimated")
	record = JSON.parse_string((document.compile().value.raw_bytes() as PackedByteArray).get_string_from_utf8())
	check("a typed wingspan is recorded as entered by the player", str(record.reference.wing_span.kind) == "manual"
		and str(record.reference.wing_span.source).contains("player-entered"))
	check("evidence is part of the identity", document.compile().ok)
	var forged: Dictionary = document.definition()
	forged.evidence = {"wing/span": "measured by a laboratory"}
	check("an unknown evidence kind is refused", not Definition.validate_complete(forged).ok)
	forged.evidence = {"wing/colour": "estimated"}
	check("an unknown evidence path is refused", not Definition.validate_complete(forged).ok)
	forged.evidence = "estimated"
	check("evidence must be an object", not Definition.validate_complete(forged).ok)


## The borrowed derivatives are linear per radian: the package admits ordinary control travel only.
func _domain_bounds(document: RefCounted) -> void:
	for case: Array in [["controls/aileron_deg", "60", "controls_ground"], ["controls/elevator_deg", "45", "controls_ground"],
			["controls/rudder_deg", "2", "controls_ground"], ["controls/servo_time_s", "0.01", "controls_ground"],
			["equipment/thrust_angles_deg/0", "9", "power_mount"], ["battery/initial_soc", "0.01", "power_mount"]]:
		var path: String = case[0]
		var before: String = document.raw(path)
		check("%s accepts the typed text" % path, document.set_raw(path, case[1]))
		var refused := false
		for entry: Variant in document.issues():
			if entry is Dictionary and str(entry.code) == R.DOMAIN_REFUSED and str(entry.step) == str(case[2]):
				refused = true
		check("%s = %s is outside the package domain" % [path, case[1]], refused and not document.compile().ok)
		document.set_raw(path, before)
	check("the document is back inside the domain", document.issues().is_empty())


func _has_issue(issues: Array, code: String, field: String, step: String) -> bool:
	for entry: Variant in issues:
		if entry is Dictionary and str(entry.code) == code and str(entry.field) == field and str(entry.step) == step:
			return true
	return false


func check(label: String, passed: bool) -> void:
	if not passed:
		failures += 1
		printerr("FAIL: " + label)
