extends SceneTree

const Director := preload("flight_director.gd")
const IDS := ["midnight", "p40", "japan", "luftwaffe", "italy", "scarlet", "thunderbirds",
	"blueangels", "chrome", "carbon", "spectrum", "splash", "three_tone"]

class FlightStub extends Node:
	var _airplane := {}

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# These fixtures exercise the real director's selection and mesh-swap path without loading aircraft assets.
	var flight := FlightStub.new()
	var aircraft := Node3D.new()
	flight.add_child(aircraft)
	var body := MeshInstance3D.new()
	body.name = "body"
	aircraft.add_child(body)
	flight._airplane = {root = aircraft}
	var palette: Array[Dictionary] = []
	for id: String in IDS:
		var source := {mesh = BoxMesh.new(), overrides = [], material_override = StandardMaterial3D.new()}
		palette.append({id = id, meshes = {"body": [source]}})

	var holding := Director.new()
	holding.main = flight
	# No cycle IDs here: test the actual CLI option parser without loading any external scenes.
	holding._load_livery_cycle(PackedStringArray(["--livery-from=0.75", "--livery-every=0.75", "--livery-hold-last"]))
	_check("hold option and existing timing flags are parsed", holding._livery_hold_last
		and holding._livery_from_s == 0.75 and holding._livery_every_s == 0.75)
	holding._liveries = palette
	# Explicit expected identities and cut points are the editorial schedule, not a copy of the selector arithmetic.
	var timeline := [
		[0.0, "midnight"], [0.749, "midnight"], [0.75, "p40"], [1.5, "japan"],
		[2.25, "luftwaffe"], [3.0, "italy"], [3.75, "scarlet"], [4.5, "thunderbirds"],
		[5.25, "blueangels"], [6.0, "chrome"], [6.75, "carbon"], [7.5, "spectrum"],
		[8.25, "splash"], [8.999, "splash"], [9.0, "three_tone"], [9.749, "three_tone"],
		[9.75, "three_tone"], [599.0 / 60.0, "three_tone"], [10.0, "three_tone"],
		[20.0, "three_tone"],
	]
	for sample: Array in timeline:
		_check_selection(holding, body, palette, float(sample[0]), str(sample[1]), "hold")

	var looping := Director.new()
	looping.main = flight
	looping._load_livery_cycle(PackedStringArray(["--livery-from=0.75", "--livery-every=0.75"]))
	_check("looping remains the default", not looping._livery_hold_last)
	looping._liveries = palette
	for sample: Array in [[0.0, "midnight"], [9.0, "three_tone"], [9.75, "midnight"],
			[599.0 / 60.0, "midnight"], [10.5, "p40"]]:
		_check_selection(looping, body, palette, float(sample[0]), str(sample[1]), "loop")

	var empty := Director.new()
	empty._apply_livery_cycle(9.75) # No main node: the empty palette must exit before touching it.
	_check("empty palette is a no-op", empty._livery_active == "" and empty._livery_matched == 0)
	var single := Director.new()
	single.main = flight
	single._livery_hold_last = true
	single._liveries.append(palette[12])
	_check_selection(single, body, palette, 0.0, "three_tone", "single hold")
	_check_selection(single, body, palette, 10.0, "three_tone", "single hold")
	single._livery_hold_last = false
	_check_selection(single, body, palette, 20.0, "three_tone", "single loop")

	holding.free()
	looping.free()
	empty.free()
	single.free()
	flight.free()
	print("TRAILER_LIVERY_SCHEDULE checks=", _checks, " failures=", _failures)
	quit(1 if _failures > 0 else 0)


func _check_selection(director, body: MeshInstance3D, palette: Array[Dictionary], time_s: float,
		expected_id: String, mode: String) -> void:
	director._apply_livery_cycle(time_s)
	var expected: Dictionary = {}
	for record: Dictionary in palette:
		if record.id == expected_id:
			expected = record.meshes["body"][0]
			break
	_check("%s at %.6f s selects %s and its mesh" % [mode, time_s, expected_id],
		not expected.is_empty() and director._livery_active == expected_id and director._livery_matched == 1
		and body.mesh == expected.mesh and body.material_override == expected.material_override)


func _check(label: String, condition: bool) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("TRAILER_LIVERY_SCHEDULE FAIL: " + label)
