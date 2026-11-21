## A36 R4-F01: a tailless tractor with an admitted vertical-only propwash piece has no horizontal surface key.
## Wake and swirl loads must evaluate the vertical piece without touching the absent tail, and the normal
## FlightSession setup must trim and accept a reference tick. Fixture: stock X8 airframe numbers with the Stik
## glow tractor and one central vertical wake piece (a synthetic numerical domain witness, not a real installation).
extends SceneTree

const Data := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const Wake := preload("res://physics/slipstream.gd")
const Swirl := preload("res://physics/swirl_loads.gd")
const Flight := preload("res://sim/flight_session.gd")
const Propulsion := preload("res://physics/propulsion.gd")

const X8 := "res://data/aircraft/moonrunner_x99.json"
const STIK := "res://data/aircraft/jensen_ugly_stik_60.json"
const SOURCE := "A36 R4-F01 synthetic tractor/vertical-wake test fixture; not measured aircraft geometry"

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, passed: bool, detail: Variant = "") -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL %s%s" % [label, " — " + str(detail) if str(detail) != "" else ""])


func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _quantity(value: Variant, unit: String) -> Dictionary:
	return {value = value, unit = unit, kind = "estimated", source = SOURCE}


func _candidate(swirl: float, with_wake := true) -> Dictionary:
	var raw: Dictionary = _json(X8)
	var stik: Dictionary = _json(STIK)
	raw.id = "a36-tailless-tractor-test"
	raw.capabilities.propulsion_layout = "single_tractor"
	raw.capabilities.energy = "prescribed_fuel"
	raw.propulsion = stik.propulsion.duplicate(true)
	raw.propulsion.id = "propulsion_main"
	var prop: Dictionary = raw.propulsion.propeller
	prop.thrust_angles = _quantity([0.0, 0.0], "deg")
	prop.thrust_line_offset = _quantity([-0.435, 0.0, -0.004255534], "m")
	if with_wake:
		prop.slipstream = {
			hub = _quantity([0.0, 0.0, 0.0], "m"),
			wash_factor = _quantity([0.8, 1.8], "1"),
			swirl_factor = _quantity(swirl, "1"),
			vertical_drift = _quantity(0.5, "1"),
			pieces = [{surface = "vertical", area = _quantity(0.020, "m2"),
				root = _quantity([0.4851627273, 0.0, 0.0], "m"), span_dir = _quantity([0.0, 0.0, 1.0], "1"),
				span = _quantity(0.10, "m")}],
		}
		if swirl > 0.0:
			# E0b3b smooth profile: its distributed swirl increment has the second horizontal-tail lookup.
			prop.slipstream.edge_fraction = _quantity(0.2, "1")
			prop.slipstream.reverse_fade = _quantity([0.05, 0.2], "1")
			prop.slipstream.pieces[0].profile = _quantity([[0.0, 0.10, 0.20, 0.20]], "m")
		else:
			prop.slipstream.pieces[0].chords = _quantity([0.20, 0.20], "m")
	else:
		prop.erase("slipstream")
	for item: Dictionary in raw.inventory:
		if item.id in ["motor_main", "propeller_main", "motor_mount", "esc_main", "battery_main"]:
			for key: String in item:
				var value: Variant = item[key]
				if value is Dictionary and value.has_all(["value", "unit", "kind", "source"]):
					value.kind = "estimated"
					value.source = SOURCE
	return raw


func _finite(values: PackedFloat64Array) -> bool:
	for value in values:
		if not is_finite(value):
			return false
	return true


func _norm(values: PackedFloat64Array) -> float:
	var total := 0.0
	for value in values:
		total += value * value
	return sqrt(total)


func _run() -> void:
	var state := PackedFloat64Array([0.0, 0.0, -20.0, 12.0, 0.5, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var air: Dictionary = Air.compute(state, PackedFloat64Array([0.0, 0.0, 0.0]), 1.225)
	var d := {elevator = 0.0, aileron_left = 0.0, aileron_right = 0.0, rudder = 0.0}
	for swirl: float in [0.0, 0.6]:
		var label := "swirl %.1f" % swirl
		var result: Dictionary = Data.validate_and_derive(_candidate(swirl))
		check("%s tailless vertical-wake tractor is admitted" % label, result.ok, result.errors)
		if not result.ok:
			continue
		var model: Dictionary = result.model
		check("%s derived surfaces omit the horizontal tail" % label,
			model.surfaces.has("tailless") and model.surfaces.has("vertical") and not model.surfaces.has("horizontal"))
		var powered: PackedFloat64Array = Wake.stage_loads(state, air, d, model, 5000.0, 1.225, NAN,
			PackedFloat64Array(), 1, PackedFloat64Array())
		check("%s powered wake returns six finite loads" % label, powered.size() == 6 and _finite(powered), powered)
		check("%s powered vertical piece loads the fin" % label, powered.size() == 6 and _norm(powered) > 1.0e-6, powered)
		var stopped: PackedFloat64Array = Wake.stage_loads(state, air, d, model, 0.0, 1.225, NAN,
			PackedFloat64Array(), 1, PackedFloat64Array())
		check("%s stopped propeller has zero wake loads" % label, stopped.size() == 6 and _norm(stopped) == 0.0, stopped)
		if swirl > 0.0:
			var tq: PackedFloat64Array = Propulsion.thrust_torque(air.v_air, 5000.0, model.propulsion, 1.225)
			var wake: Dictionary = Wake.wake(air.v_air, tq[0], tq[1], model.propulsion, 1.225)
			check("%s wake carries swirl" % label, float(wake.get("swirl", 0.0)) != 0.0, wake)
			var correction: PackedFloat64Array = Swirl.correction(state, air, d, model, wake, 1.0, 1.225)
			check("%s swirl correction is finite and nonzero without a horizontal tail" % label,
				correction.size() == 6 and _finite(correction) and _norm(correction) > 0.0, correction)
	_session_check()
	print("tailless vertical wake: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _session_check() -> void:
	var dir := "user://a36-tailless-wake"
	DirAccess.make_dir_recursive_absolute(dir)
	for wake: bool in [false, true]:
		var raw := _candidate(0.0, wake)
		raw.id = "a36-tailless-tractor-%s" % ("wake" if wake else "control")
		var path := "%s/%s.json" % [dir, raw.id]
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(raw, "  "))
		file.close()
		var flight: Node = Flight.new()
		var selected: bool = flight.setup_stage_backend("gdscript_reference")
		check("%s reference backend selected" % raw.id, selected)
		flight.setup(path, raw.id)
		check("%s setup trims a flyable start" % raw.id, flight.is_flyable(), flight.start_error)
		if flight.is_flyable():
			var before: int = flight.sim.tick
			flight.sim.step()
			check("%s accepts one reference tick" % raw.id, flight.sim.tick == before + 1 and flight.sim.fault_reason == "",
				flight.sim.fault_reason)
		flight.free()
