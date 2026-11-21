extends SceneTree
## Geometric counterexamples: heading turns and disconnected excursions are not runway laps.
const Circuit := preload("runway_circuit.gd")
const FIELD := {center_north = 15.0, center_east = -30.0, length_east_west = 100.0, width_north_south = 12.0}
var failures := 0


func _initialize() -> void:
	var circuit := _new_circuit()
	_check(circuit.inner_radius_m > sqrt(50.0 * 50.0 + 6.0 * 6.0), "corridor encloses every runway corner")
	_circle(circuit, 0, 360)
	if not circuit.complete: print("Exact-circle diagnostic: ", JSON.stringify(circuit.receipt()))
	_check(circuit.complete, "one continuous clockwise position lap passes about a non-origin runway")
	_check(circuit.quadrants == 15 and absf(circuit.sweep_rad - TAU) <= 1.0e-9, "completion retains four quadrants and full signed winding within floating-point roundoff")
	_check(circuit.receipt().minimum_agl_m == 65.0, "altitude evidence is retained")
	circuit = _new_circuit()
	_circle(circuit, 0, 355)
	_check(not circuit.complete, "355 degrees cannot be credited as a full lap")
	circuit = _new_circuit()
	_circle(circuit, 0, 359)
	var incomplete_angle := deg_to_rad(359.999)
	circuit.observe(15.0 + circuit.radius_m * cos(incomplete_angle), -30.0 + circuit.radius_m * sin(incomplete_angle), 65.0, 1440, 36.0)
	_check(not circuit.complete, "359.999 degrees is still an incomplete circuit")
	circuit = _new_circuit()
	_circle(circuit, 0, 360, -1.0)
	_check(not circuit.complete, "counterclockwise progress does not satisfy a right circuit")
	circuit = _new_circuit()
	for i: int in 400:
		circuit.observe(15.0 + circuit.radius_m, -30.0, 65.0, i * 4, float(i) / 10.0)
	_check(not circuit.complete, "stationary position cannot pass regardless of aircraft heading")
	circuit = _new_circuit()
	for i: int in 361:
		var angle := deg_to_rad(float(i))
		circuit.observe(15.0 + 10.0 * cos(angle), -30.0 + 10.0 * sin(angle), 65.0, i * 4, float(i) / 10.0)
	_check(not circuit.complete, "a small circle inside the runway is not a circuit around it")
	circuit = _new_circuit()
	_circle(circuit, 0, 200)
	circuit.observe(15.0, -30.0, 65.0, 804, 20.1)
	_circle(circuit, 202, 400)
	_check(not circuit.complete and circuit.resets == 1, "two partial arcs separated by a corridor excursion cannot combine")
	circuit = _new_circuit()
	_circle(circuit, 0, 200)
	var angle := deg_to_rad(201.0)
	circuit.observe(15.0 + circuit.radius_m * cos(angle), -30.0 + circuit.radius_m * sin(angle), 10.0, 804, 20.1)
	_circle(circuit, 202, 400)
	_check(not circuit.complete and circuit.resets == 1, "low-altitude excursion invalidates accumulated lap credit")
	circuit = _new_circuit()
	circuit.observe(15.0 + circuit.radius_m, -30.0, 65.0, 0, 0.0)
	circuit.observe(15.0 - circuit.radius_m, -30.0, 65.0, 4, 0.1)
	_check(circuit.failed and not circuit.complete, "teleported position cannot create angular progress")
	circuit = _new_circuit()
	circuit.observe(15.0 + circuit.radius_m, -30.0, 65.0, 4, 0.1)
	circuit.observe(15.0 + circuit.radius_m, -30.0, 65.0, 4, 0.1)
	_check(circuit.failed, "duplicate physical sample is refused")
	circuit = _new_circuit()
	circuit.observe(NAN, 0.0, 65.0, 0, 0.0)
	_check(circuit.failed, "nonfinite position is refused")
	var invalid := Circuit.new()
	_check(not invalid.configure({center_north = NAN}, 20.0).ok, "malformed runway data is refused")
	var fast := Circuit.new()
	_check(fast.configure(FIELD, 55.0).ok and fast.radius_m > _new_circuit().radius_m, "jet trim speed expands the orbit without changing aircraft laws")
	print("GOD_RUNWAY_CIRCUIT_TESTS: ", failures, " failed")
	quit(0 if failures == 0 else 1)


func _new_circuit() -> RefCounted:
	var result := Circuit.new()
	_check(result.configure(FIELD, 18.0).ok, "normalized runway accepted")
	return result


func _circle(circuit: RefCounted, first: int, last: int, direction := 1.0) -> void:
	for i: int in range(first, last + 1):
		var angle := deg_to_rad(float(i)) * direction
		circuit.observe(15.0 + circuit.radius_m * cos(angle), -30.0 + circuit.radius_m * sin(angle), 65.0, i * 4, float(i) / 10.0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", message)
