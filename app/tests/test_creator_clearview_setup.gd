extends SceneTree
## Import closeout packet 2: one-click ClearView flight setup. Frame rule, estimated leading edge,
## estimates kept inside the package domain, explicit declaration, and the refusals that stay.
const R := preload("res://workshop/creator/result.gd")
const Setup := preload("res://workshop/creator/clearview/setup.gd")
const Authoring := preload("res://workshop/creator/authoring.gd")
const Installation := preload("res://workshop/creator/source_installation.gd")
const Observations := preload("res://workshop/creator/clearview/observations.gd")
const Importer := preload("res://workshop/creator/source_importer.gd")
const Fixture := preload("res://tests/creator_fixtures.gd")
const AuthoringFixture := preload("res://tests/creator_authoring_fixture.gd")
const Bytes := preload("res://workshop/creator/bytes.gd")
const InstallationFixture := preload("res://tests/test_creator_source_installation.gd")
const CvFixture := preload("res://tests/test_creator_clearview_readers.gd")
const Package := preload("res://workshop/creator/clearview/package.gd")
const Converter := preload("res://workshop/creator/clearview/converter.gd")
const ChoicePanel := preload("res://ui/aircraft_creator_installation.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, good: bool) -> void:
	checks += 1
	if not good:
		failures += 1
		printerr("FAIL: ", label)


func _run() -> void:
	_leading_edge()
	_document()
	_pusher()
	_long_body()
	await _panel()
	print("ClearView setup: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


## A body much longer than its wing (a delta jet) is shown smaller until it fits the definition's reach,
## labelled scaled and placed in the size class that holds the smaller span (corpus: IAF Kfir).
func _long_body() -> void:
	var ac := "AC3Db\nMATERIAL \"m\" rgb 1 1 1 amb 0.2 0.2 0.2 emis 0 0 0 spec 0.5 0.5 0.5 shi 10 trans 0\nOBJECT world\nkids 2\n" \
		+ "OBJECT poly\nname \"wing\"\nnumvert 4\n-0.1 0 -0.8\n0.2 0 -0.8\n0.2 0 0.8\n-0.1 0 0.8\nnumsurf 1\nSURF 0x30\nmat 0\nrefs 4\n0 0 0\n1 1 0\n2 1 1\n3 0 1\nkids 0\n" \
		+ "OBJECT poly\nname \"fuselage\"\nnumvert 3\n-2.5 0 0\n2.5 0 0.02\n2.5 0.1 0\nnumsurf 1\nSURF 0x30\nmat 0\nrefs 3\n0 0 0\n1 1 0\n2 1 1\nkids 0\n"
	var converted: Dictionary = _converted(ac)
	check("long-body fixture converts", converted.ok)
	if not converted.ok:
		return
	var proposed := Setup.propose(converted.value.source, Authoring.span_domain())
	check("a long body is proposed smaller so it fits the reach limit", proposed.ok and proposed.value.scaled
		and float(proposed.value.flown_span_m) < float(proposed.value.source_span_m)
		and float(proposed.value.flown_span_m) * Setup._reach(Setup._points(converted.value.source).value, proposed.value.placement.datum) / float(proposed.value.source_span_m) <= Setup.MAX_REACH_M + 1e-9)
	var classes: Array = Authoring.span_domain()
	check("its size class holds the smaller span", proposed.ok and int(proposed.value.range_index) >= 0
		and float(proposed.value.flown_span_m) >= float(classes[proposed.value.range_index][0])
		and float(proposed.value.flown_span_m) <= float(classes[proposed.value.range_index][1]))


## One straight wing panel pair (both sides) as triangles: root and tip leading/trailing edge x and height.
static func _wing(root_le: float, root_te: float, tip_le: float, tip_te: float, root_y: float, tip_y: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for side: float in [1.0, -1.0]:
		out.append_array([root_le, root_y, 0.0, root_te, root_y, 0.0, tip_le, tip_y, side])
		out.append_array([root_te, root_y, 0.0, tip_te, tip_y, side, tip_le, tip_y, side])
	return out


## Realism batch: the wing planform is measured from the model instead of the template rectangle.
func _planform() -> void:
	var rectangle := Setup.planform(_wing(0.0, 0.3, 0.0, 0.3, 0.0, 0.0), 1.0)
	check("a rectangular wing measures its chord and no dihedral", not rectangle.is_empty()
		and absf(float(rectangle.root_chord_m) - 0.3) < 1e-9 and absf(float(rectangle.tip_chord_m) - 0.3) < 1e-9
		and absf(float(rectangle.dihedral_deg)) < 1e-9 and not rectangle.biplane)
	var tapered := Setup.planform(_wing(0.0, 0.4, 0.1, 0.35, 0.0, tan(deg_to_rad(5.0))), 1.0)
	check("a tapered wing measures root and tip chord and its dihedral", not tapered.is_empty()
		and absf(float(tapered.root_chord_m) - 0.4) < 1e-9 and absf(float(tapered.tip_chord_m) - 0.25) < 1e-9
		and absf(float(tapered.dihedral_deg) - 5.0) < 1e-6)
	var pointed := Setup.planform(_wing(0.0, 0.4, 0.15, 0.25, 0.0, 0.0), 1.0)
	check("a taper outside the package range is clamped", not pointed.is_empty()
		and absf(float(pointed.tip_chord_m) / float(pointed.root_chord_m) - Setup.TAPER_RANGE[0]) < 1e-9)
	var slender := Setup.planform(_wing(0.0, 0.1, 0.0, 0.1, 0.0, 0.0), 1.0)
	check("a glider wing beyond the aspect-ratio range is clamped to it", not slender.is_empty()
		and absf(4.0 / (float(slender.root_chord_m) + float(slender.tip_chord_m)) - Setup.ASPECT_RANGE[1]) < 1e-9)
	var biplane := _wing(0.0, 0.3, 0.0, 0.3, 0.0, 0.0)
	biplane.append_array(_wing(0.05, 0.35, 0.05, 0.35, 0.3, 0.3))
	var stacked := Setup.planform(biplane, 1.0)
	check("a biplane is one equivalent wing with both wings' area (aspect ratio kept in range)", not stacked.is_empty()
		and stacked.biplane and absf(4.0 / (float(stacked.root_chord_m) + float(stacked.tip_chord_m)) - Setup.ASPECT_RANGE[0]) < 1e-9)
	check("a model without wing sections has no measured planform", Setup.planform(PackedFloat64Array(), 1.0).is_empty())
	# A canard (0.15 m chord, out to half the span) ahead of the wing at the same height: two stations cut
	# the canard instead of the wing, so the measurement is refused and the template planform stays.
	var canard := _wing(0.0, 0.3, 0.0, 0.3, 0.0, 0.0)
	for side: float in [0.5, -0.5]:
		canard.append_array([-0.6, 0.0, 0.0, -0.45, 0.0, 0.0, -0.6, 0.0, side])
		canard.append_array([-0.45, 0.0, 0.0, -0.45, 0.0, side, -0.6, 0.0, side])
	check("a canard that hides the wing at two stations gives no measured planform", Setup.planform(canard, 1.0).is_empty())


## A low-polygon swept wing has vertices only at its root and tips: the edges must be cut.
func _leading_edge() -> void:
	var wing := PackedFloat64Array()
	for side: float in [1.0, -1.0]:
		# Root LE x=-0.1, TE 0.2 at z=0; tip LE x=0.0, TE 0.2 at |z|=1.0; height 0.05.
		wing.append_array([-0.1, 0.05, 0.0, 0.2, 0.05, 0.0, 0.0, 0.05, side])
		wing.append_array([0.2, 0.05, 0.0, 0.2, 0.05, side, 0.0, 0.05, side])
	var found := Setup.leading_edge(wing)
	check("swept low-polygon wing gives the root leading edge", found.ok
		and absf(float(found.value.datum[0]) + 0.1) < 1e-9 and absf(float(found.value.datum[1]) - 0.05) < 1e-9
		and float(found.value.datum[2]) == 0.0 and absf(float(found.value.half_span_m) - 1.0) < 1e-9)
	var forward := wing.duplicate()
	# A swept-forward extreme extrapolation is limited to MAX_SWEEP_SHIFT of the half-span.
	for index: int in forward.size() / 3:
		if absf(forward[index * 3 + 2]) == 1.0:
			forward[index * 3] = -5.0
	var limited := Setup.leading_edge(forward)
	# Station 0.35: LE = -0.1 + 0.35 * (-4.9) = -1.815; the root shift is capped at 0.15 m.
	check("sweep extrapolation is bounded", limited.ok and absf(float(limited.value.datum[0]) + 1.665) < 1e-9)
	_planform()
	var tiny := PackedFloat64Array([0.0, 0.0, 0.0, 0.01, 0.0, 0.05, 0.0, 0.0, -0.05])
	check("a model narrower than the minimum half-span is refused", not Setup.leading_edge(tiny).ok)
	check("too few points are refused", not Setup.leading_edge(PackedFloat64Array([0.0, 0.0])).ok)
	var ordinary := Importer.inspect_bytes(Fixture.airplane_glb(), "ordinary.glb")
	check("automatic setup is only for converted ClearView models", ordinary.ok
		and not Setup.propose(ordinary.value).ok and Setup.propose(ordinary.value).diagnostics[0].code == R.SOURCE_UNSUPPORTED)
	# A 3 m wing outside the 0.9-2.2 m package range is proposed as an explicit, smaller configuration.
	var wide := _converted("AC3Db
MATERIAL \"m\" rgb 1 1 1 amb 0.2 0.2 0.2 emis 0 0 0 spec 0.5 0.5 0.5 shi 10 trans 0
OBJECT world
kids 1
OBJECT poly
name \"wing\"
numvert 5
-0.1 0 -1.5
0.2 0 -1.5
0.2 0 1.5
-0.1 0 1.5
0.05 0.08 0
numsurf 2
SURF 0x30
mat 0
refs 4
0 0 0
1 1 0
2 1 1
3 0 1
SURF 0x30
mat 0
refs 3
0 0 0
1 1 0
4 0 1
kids 0
")
	check("wide fixture converts", wide.ok)
	if not wide.ok:
		printerr(wide.diagnostics)
	if wide.ok:
		var kept := Setup.propose(wide.value.source)
		var fitted := Setup.propose(wide.value.source, [0.9, 2.2])
		check("without a range the source size is kept", kept.ok and not kept.value.scaled and kept.value.units == "m"
			and absf(float(kept.value.source_span_m) - 3.0) < 1e-6)
		check("outside the range the size is fitted and labelled", fitted.ok and fitted.value.scaled and fitted.value.units == ""
			and absf(float(fitted.value.flown_span_m) - 2.2 * (1.0 - Setup.FIT_MARGIN)) < 1e-9
			and absf(float(fitted.value.placement.unit_scale) - float(fitted.value.flown_span_m) / 3.0) < 1e-12)
		check("a model without a propeller says so", fitted.ok and not fitted.value.propeller_found)
		# Realism batch: two size classes, the foam park flyer up to SETUP_MIN_SPAN_M and the trainer above it.
		var classes: Array = Authoring.setup_classes()
		check("the setup has a park-flyer and a trainer size class", classes.size() == 2
			and classes[0].airframe == Authoring.PARKFLYER_AIRFRAME and classes[0].tractor == Authoring.SMALL_POWER
			and classes[0].pusher == Authoring.SMALL_PUSHER and classes[1].airframe == Authoring.AIRFRAME_PACKAGE
			and classes[1].tractor == Authoring.POWER_PACKAGE and classes[1].pusher == Authoring.JET_PUSHER
			and float(classes[0].range[1]) == Authoring.SETUP_MIN_SPAN_M and float(classes[1].range[0]) == Authoring.SETUP_MIN_SPAN_M)
		var chosen := Setup.propose(wide.value.source, Authoring.span_domain())
		check("a large model chooses the trainer class", chosen.ok and int(chosen.value.range_index) == 1
			and chosen.value.span_range == classes[1].range)
		var within := Setup.propose(wide.value.source, [[0.5, 2.0], [2.0, 4.0]])
		check("a model inside a class range keeps its size", within.ok and int(within.value.range_index) == 1 and not within.value.scaled)
		# A smaller model flies as a labelled larger version (here a 3 m model below a 3.5 m floor).
		var grown := Setup.propose(wide.value.source, [3.5, 5.0])
		check("a model under the minimum flies as a labelled larger version", grown.ok and grown.value.scaled
			and absf(float(grown.value.flown_span_m) - 3.5 * (1.0 + Setup.FIT_MARGIN)) < 1e-9)
		# Its wingtip is its furthest point (1.5 m from the datum): it grows only until that reaches MAX_REACH_M.
		var capped := Setup.propose(wide.value.source, [5.0, 6.0])
		check("growth stops where the body would leave the definition's lengths", capped.ok and capped.value.scaled
			and absf(float(capped.value.flown_span_m) - Setup.MAX_REACH_M * 3.0 / 1.5) < 1e-6)
	var heli := _converted_with(CvFixture._ac_fixture(), "verNumber 3
modelType 0
")
	check("a ClearView helicopter is refused, not estimated as an aeroplane", heli.ok and not Setup.propose(heli.value.source).ok
		and Setup.propose(heli.value.source).diagnostics[0].message == Setup.HELICOPTER)
	var elevon := _converted(CvFixture._ac_fixture().replace("name \"wing\"", "name \"LElevon\""))
	check("an elevon model is refused with the named capability", elevon.ok and not Setup.propose(elevon.value.source).ok
		and Setup.propose(elevon.value.source).diagnostics[0].message == Setup.ELEVONS)


func _document() -> void:
	var converted: Dictionary = InstallationFixture.convert_fixture()
	check("ClearView fixture converts", converted.ok)
	if not converted.ok:
		return
	var source: RefCounted = converted.value.source
	var doc := Authoring.new()
	doc.set_source(source, Observations.inspect(source).value)
	doc.set_value("wing/span", 1.5)
	var setup := {placement = {nose_axis = "-x", up_axis = "+y", unit_scale = 1.0, datum = [0.0, 0.0, 0.0]}, units = "m"}
	check("a stale dialog cannot apply", not doc.apply_clearview_setup(setup, doc.revision - 1).ok and doc.needs_source_installation())
	check("an incomplete setup cannot apply", not doc.apply_clearview_setup({placement = {}}, doc.revision).ok)
	var applied := doc.apply_clearview_setup(setup, doc.revision)
	check("one action sets up the model and declares the estimate", applied.ok and not doc.needs_source_installation()
		and doc.placement_result().ok and doc.units() == "m" and not doc.inventory().is_empty())
	check("the player's value is kept and not marked estimated", doc.value("wing/span") == 1.5 and not doc.is_estimated("wing/span"))
	check("filled values are labelled estimates", doc.is_estimated("wing/root_chord") and doc.is_estimated("controls/aileron_deg"))
	check("the declaration is the explicit independent estimate", doc.source_installation().mode == Installation.MODE)
	check("no flight-qualification block under the historical law",
		not doc.issues().any(func(d: Dictionary) -> bool: return d.message == Installation.FLIGHT_UNAVAILABLE))
	var placed: Dictionary = doc.placement()
	var again := doc.apply_clearview_setup({placement = {nose_axis = "+z", up_axis = "+x", unit_scale = 2.0, datum = [1.0, 1.0, 1.0]}, units = "cm"}, doc.revision)
	check("a second setup never replaces the resolved placement", again.ok and doc.placement() == placed)
	var ordinary := Authoring.new()
	ordinary.set_source(Importer.inspect_bytes(Fixture.airplane_glb(), "ordinary.glb").value)
	check("an ordinary model has no ClearView setup", not ordinary.apply_clearview_setup(setup, ordinary.revision).ok)
	check("the trainer class stays the default", doc.definition().airframe_package == Authoring.AIRFRAME_PACKAGE
		and doc.definition().power_package == Authoring.POWER_PACKAGE and not doc.snapshot().has("airframe_package"))
	# The park-flyer class: foam airframe and 3S power; a jet in it gets the 3S pusher.
	var small := Authoring.new()
	small.set_source(source, Observations.inspect(source).value)
	var small_setup := setup.duplicate(true)
	small_setup.range_index = 0
	small_setup.propeller_found = false
	check("a small jet is set up as a park flyer with the 3S pusher", small.apply_clearview_setup(small_setup, small.revision).ok
		and small.definition().airframe_package == Authoring.PARKFLYER_AIRFRAME
		and small.definition().power_package == Authoring.SMALL_PUSHER and small.source_installation().airframe_package == Authoring.PARKFLYER_AIRFRAME)
	var reopened := Authoring.new()
	var small_saved: Dictionary = JSON.parse_string(JSON.stringify(small.snapshot()))
	check("the park-flyer class survives save and reopen", small_saved.get("airframe_package") == Authoring.PARKFLYER_AIRFRAME
		and reopened.restore(small_saved, source, Observations.inspect(source).value).ok
		and reopened.definition().airframe_package == Authoring.PARKFLYER_AIRFRAME and reopened.definition().power_package == Authoring.SMALL_PUSHER)
	small_saved.airframe_package = "conventional-unknown-v9"
	check("an unknown airframe package refuses the draft", not Authoring.new().restore(small_saved, source, Observations.inspect(source).value).ok)
	var jet := Authoring.new()
	jet.set_source(source, Observations.inspect(source).value)
	var jet_setup := setup.duplicate(true)
	jet_setup.propeller_found = false
	check("a mid-size jet gets the fast 4S pusher", jet.apply_clearview_setup(jet_setup, jet.revision).ok
		and jet.definition().airframe_package == Authoring.AIRFRAME_PACKAGE and jet.definition().power_package == Authoring.JET_PUSHER)
	var big := Authoring.new()
	big.set_source(source, Observations.inspect(source).value)
	var big_setup := jet_setup.duplicate(true)
	big_setup.flown_span_m = Authoring.LARGE_JET_SPAN_M
	check("a large jet gets the 6S pusher", big.apply_clearview_setup(big_setup, big.revision).ok
		and big.definition().power_package == Authoring.LARGE_JET_PUSHER)


## The pusher variant: same estimated hardware behind the wing, emitted as single_pusher.
func _pusher() -> void:
	var source: RefCounted = Importer.inspect_bytes(Fixture.airplane_glb(), "pusher.glb").value
	var plain: RefCounted = AuthoringFixture.populated(source)
	check("a default document never writes a power package member", not plain.snapshot().has("power_package"))
	var saved: Dictionary = plain.snapshot()
	saved["power_package"] = Authoring.PUSHER_PACKAGE
	var doc := Authoring.new()
	check("a pusher snapshot restores", doc.restore(saved, source).ok and doc.definition().power_package == Authoring.PUSHER_PACKAGE)
	var hub_x := float(doc.value("wing/root_chord")) + Authoring.PUSHER_GAP_M
	doc.set_value("equipment/hub_position/0", hub_x)
	doc.set_value("equipment/esc_position/0", hub_x - 0.12)
	# The motor moved aft: balance it as a builder would, with the battery well forward.
	doc.set_value("equipment/battery_position/0", float(doc.value("fuselage/nose_x")) + 0.03)
	var weight: String = doc.add_item("Nose weight")
	doc.set_item_raw(weight, "mass", "0.6")
	doc.set_item_raw(weight, "x", Authoring.format_number(float(doc.value("fuselage/nose_x")) + 0.03))
	var compiled: Dictionary = doc.compile()
	if not compiled.ok:
		printerr(compiled.diagnostics)
	check("a pusher behind the wing compiles and loads", compiled.ok)
	if compiled.ok:
		var record: Dictionary = Bytes.decode(compiled.value.raw_bytes()).value.data
		var motor := {}
		for item: Dictionary in record.inventory:
			if str(item.get("mount", "")) == "motor" or str(item.get("id", "")).contains("motor"):
				motor = item
		check("the record is a single pusher", record.capabilities.propulsion_layout == "single_pusher")
		check("the propeller sits aft of the balance point", float(record.propulsion.propeller.thrust_line_offset.value[0]) > 0.0)
		check("the firewall sits ahead of the hub", float(record.balance.firewall.value[0]) < hub_x)
		check("the motor sits ahead of the hub", not motor.is_empty() and float(motor.position.value[0]) < hub_x)
	var round_trip := Authoring.new()
	check("the pusher choice survives save and reopen", round_trip.restore(JSON.parse_string(JSON.stringify(doc.snapshot())), source).ok
		and round_trip.definition().power_package == Authoring.PUSHER_PACKAGE)
	var unknown: Dictionary = saved.duplicate(true)
	unknown["power_package"] = "electric-unknown-v9"
	var untouched := Authoring.new()
	check("an unknown power package refuses the draft", not untouched.restore(unknown, source).ok)


func _panel() -> void:
	var converted: Dictionary = InstallationFixture.convert_fixture()
	var panel := ChoicePanel.new()
	root.add_child(panel)
	var requested := []
	panel.setup_requested.connect(func(revision: int) -> void: requested.append(revision))
	var proposal: Dictionary = {format = Installation.FORMAT}
	panel.show_state(1, 7, proposal, false, false)
	check("the setup button is offered first", panel.focus_target() == panel._setup and panel._setup.visible and not panel._setup.disabled)
	panel._setup.pressed.emit()
	check("setup requests carry the shown revision", requested == [7])
	panel.show_state(1, 7, proposal, false, true)
	panel._setup.pressed.emit()
	check("a busy import cannot start setup", panel._setup.disabled and requested == [7])
	panel.show_state(1, 8, proposal, true, false)
	check("a chosen configuration hides setup and states what flies", not panel._setup.visible
		and panel._qualification.text == Installation.ESTIMATED_FLIGHT)
	panel.queue_free()
	await process_frame
	check("fixture used by the panel converts", converted.ok)


static func _converted_with(ac: String, params: String) -> Dictionary:
	var package := Package.inspect_bytes(CvFixture._zip_bytes([["Heli/params.txt", params.to_ascii_buffer()],
		["Heli/data/body.ac", ac.to_ascii_buffer()]]))
	return Converter.convert(package.value, "Heli") if package.ok else package


static func _converted(ac: String) -> Dictionary:
	var params := "verNumber 5\nmodelType 1\nmodelName body.ac\n"
	var package := Package.inspect_bytes(CvFixture._zip_bytes([["Plane/params.txt", params.to_ascii_buffer()],
		["Plane/data/body.ac", ac.to_ascii_buffer()]]))
	return Converter.convert(package.value, "Plane") if package.ok else package
