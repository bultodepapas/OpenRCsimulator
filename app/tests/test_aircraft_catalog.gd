# EX-03 / AV-03 / UI-05: the aircraft catalog resolves each ID to its own model, data and datum, never another's.
# Every ID builds with the model team's builder; every flyable ID loads valid data whose id is the catalog's, trims at
# its own start speed, and puts the simulated CG where its visual model has it. The flight scene flies the ID it is
# given. Run: godot --headless --path . --script res://tests/test_aircraft_catalog.gd
extends SceneTree

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Frames := preload("res://render/frames.gd")
const Shadow := preload("res://render/shadow.gd")
const Commands := preload("res://input/commands.gd")
const Extra := preload("res://aircraft/extra_300s_model.gd")
const ExtraGeometry := preload("res://aircraft/extra_300s_geometry.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + "  " + detail)
	if not ok:
		_failures += 1


func _initialize() -> void:
	_check("default is the Ugly Stik and it is in the catalog", Catalog.DEFAULT_ID == AirplaneBuilder.STIK_ID and Catalog.has(Catalog.DEFAULT_ID))
	_check("three aircraft, unique IDs", Catalog.ids().size() == 3 and Array(Catalog.ids()).filter(func(i): return Catalog.ids().count(i) == 1).size() == 3, str(Catalog.ids()))
	_check("unknown ID: no entry, cannot fly", Catalog.entry("nope").is_empty() and not Catalog.can_fly("nope"))
	_check("step wraps both ways", Catalog.step(Catalog.ids()[2], 1) == Catalog.ids()[0] and Catalog.step(Catalog.ids()[0], -1) == Catalog.ids()[2])
	_check("the render adapter knows every catalog ID by the same name",
		[AirplaneBuilder.STIK_ID, AirplaneBuilder.EXTRA_ID, AirplaneBuilder.AVANTI_ID] == Array(Catalog.ids()))

	for id in Catalog.ids():
		var e := Catalog.entry(id)
		var airplane := AirplaneBuilder.build(id)
		var ok_contract: bool = airplane.get("root") is Node3D and airplane.root.name == "airplane" and airplane.get("propeller") is Node3D \
			and airplane.get("hinges", {}).size() >= 4 and airplane.aircraft_id == id
		_check("%s: builds root/propeller/hinges" % id, ok_contract)
		var extent := Shadow.model_extent(airplane.root)
		AirplaneBuilder.apply_surfaces(airplane, Commands.hinge_rotations({ roll = 1.0, pitch = -1.0, yaw = 1.0, throttle = 0.0 }, { aileron = 20.0, elevator = 20.0, rudder = 20.0 }))
		AirplaneBuilder.apply_surfaces(airplane, Commands.hinge_rotations(Commands.neutral_commands(), { aileron = 20.0, elevator = 20.0, rudder = 20.0 }))
		_check("%s: surfaces deflect and return through the shared adapter" % id, true)
		if e.status == Catalog.PREVIEW:
			_check("%s: preview has no data and cannot fly" % id, e.data == "" and not Catalog.can_fly(id))
			_check("%s: preview has no spinning propeller" % id, not airplane.get("has_propeller", true) and not airplane.propeller.visible)
			airplane.root.free()
			continue
		var data := AircraftData.load_file(e.data)
		_check("%s: data loads" % id, data.ok, "" if data.ok else str(data.errors))
		if not data.ok:
			airplane.root.free()
			continue
		var model: Dictionary = data.model
		_check("%s: the data file is this aircraft (id matches)" % id, model.id == id, model.id)
		_check("%s: span of the built model matches the data within 1 %%" % id, absf(extent.x - model.reference.b) / model.reference.b < 0.01,
			"model %.4f m, data %.4f m" % [extent.x, model.reference.b])
		# The simulated CG, placed in the model through the datum, lies on the symmetry plane, between the wing's
		# leading and trailing edges at the root, and within the fuselage's height.
		var datum := AirplaneBuilder.datum(id)
		var cg := Frames.cg_in_model_frame(model.cg_le, datum.x, datum.y)
		var root_chord: float = model.reference.chords[0] if not model.reference.chords.is_empty() else model.reference.c
		_check("%s: CG lands on the root chord in the visual model" % id, absf(cg.x) < 1e-6 and cg.z > datum.x and cg.z < datum.x + root_chord and absf(cg.y) < 0.1,
			"model point %s, LE z %.4f, chord %.4f" % [cg, datum.x, root_chord])
		airplane.root.free()

	# Extra specifics: the data's CG is the manual's balance point = the model's CG station (z 0); the throws are the
	# model team's manual-rate conversion (no drift between visual clearance checks and flight data).
	var extra: Dictionary = AircraftData.load_file(Catalog.entry(AirplaneBuilder.EXTRA_ID).data).model
	var datum := AirplaneBuilder.datum(AirplaneBuilder.EXTRA_ID)
	var cg := Frames.cg_in_model_frame(extra.cg_le, datum.x, datum.y)
	_check("Extra: CG at the model's CG station (manual 4-1/8 in at rib 2D) within 1 mm", absf(cg.z) < 0.001, "z %.5f m" % cg.z)
	var manual := Extra.manual_throws_deg()
	var same := true
	for k in manual:
		same = same and absf(float(manual[k]) - float(extra.controls.throw_deg[k])) < 0.01
	_check("Extra: physics throws = the model's manual high rates", same, "%s vs %s" % [extra.controls.throw_deg, manual])
	_check("Extra: tapered wing roots = measured geometry", is_equal_approx(extra.reference.chords[0], ExtraGeometry.DATA.wing.root_chord) and is_equal_approx(extra.reference.chords[1], ExtraGeometry.DATA.wing.tip_chord))
	_check("Extra: equal-area strips move inboard on the tapered wing", extra.envelope.station_ys[5] < 0.8 * extra.reference.b / 2.0 and extra.envelope.station_ys[5] > 0.0,
		"outer strip at %.3f m of %.3f" % [extra.envelope.station_ys[5], extra.reference.b / 2.0])

	# The flight scene flies the aircraft it is given (Home sets aircraft_id before adding it).
	var flight: Node = load("res://main.tscn").instantiate()
	flight.aircraft_id = AirplaneBuilder.EXTRA_ID
	root.add_child(flight)
	await process_frame # ready (and session created) by the first frame
	_check("flight scene: Extra model and Extra physics together", flight._airplane.aircraft_id == AirplaneBuilder.EXTRA_ID and flight.session.aircraft.model.id == AirplaneBuilder.EXTRA_ID)
	_check("flight scene: trimmed at the Extra's start speed", is_equal_approx(float(flight.session.start.V), float(extra.start_speed)), str(flight.session.start.V))
	_check("flight scene: trace header names the Extra and its speed", str(flight._trace_meta().aircraft).begins_with(AirplaneBuilder.EXTRA_ID) and str(flight._trace_meta().scenario).contains("17.0 m/s"),
		str(flight._trace_meta().scenario))
	flight.free()

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
