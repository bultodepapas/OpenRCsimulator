extends "res://tests/test_glow_counter_edges.gd"

func _initialize() -> void:
	var loaded: Dictionary = AircraftData.load_file("res://data/aircraft/stik_glow_55ax_2t.json")
	if not loaded.ok:
		printerr("fixture failed: ", loaded.errors)
		quit(1)
		return
	var model: Dictionary = _line_model(loaded.model, 0.25, false, true)
	var owner: FlightOwner = _owner(model, 6000.0, true, 0.75)
	owner.start_fuel_override_kg = 0.25
	var body := _body(PackedFloat64Array([15.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))
	var values: PackedFloat64Array = Flight.initial(owner, PackedFloat64Array([6000.0]), body)
	values[Flight.SOURCE_MODE_INDEX] = float(Flight.MODE_FEED_LINE)
	for x: float in [1.0e-12, 0.0, -1.0e-12]:
		values[1] = x
		values[Flight.LINE_FUEL_INDEX] = x
		var p: Dictionary = Flight.point(owner, body, values, 0.0)
		print("WITNESS mass=", x, " ok=", p.get("ok", false), " fuel_rate=", p.get("rates", {}).get("fuel_kg"), " chemical_w=", p.get("source", {}).get("chemical_power_w"), " firing=", p.get("firing_fraction"))
	values[1] = 0.0
	values[Flight.LINE_FUEL_INDEX] = 0.0
	var ordinary: Dictionary = Flight.point(owner, body, values, 0.0)
	var connected: Dictionary = Flight.point(owner, body, values, 0.0, false, true)
	owner.engine_running = false
	var cut: Dictionary = Flight.point(owner, body, values, 0.0)
	owner.engine_running = true
	values[7] = 0.0
	values[Flight.SOURCE_MODE_INDEX] = float(Flight.MODE_STARVED)
	var stopped: Dictionary = Flight.point(owner, body, values, 0.0)
	var ok: bool = ordinary.ok and connected.ok and cut.ok and stopped.ok and ordinary.rates.fuel_kg == 0.0 and connected.rates.fuel_kg < 0.0 and cut.rates.fuel_kg == 0.0 and stopped.rates.fuel_kg == 0.0
	print("WITNESS stopped/cut=", cut.rates.fuel_kg, "/", stopped.rates.fuel_kg, " baseline_bug_observed=", ok)
	owner.free()
	print("FUEL_ZERO_BASELINE_COMPLETE=", ok)
	quit(0 if ok else 1)
