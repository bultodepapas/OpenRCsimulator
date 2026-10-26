extends "res://tests/test_aircraft_ground_electric.gd"

func _initialize() -> void:
	_fixture()
	_electric_fixture()
	if failed:
		quit(1)
		return
	print("FIXED_PREPARED_HEX_SHA256 ", var_to_bytes(electric).hex_encode().sha256_text())
	for rpm: float in [0.0, 3000.0, 8000.0]:
		var body := _body(-2.0)
		var values := _values(rpm)
		var air := Air.compute(body, M.v3(1.0, -2.0, .3), 1.18)
		var result := Electric.evaluate(electric, body, values, 0.0, air, 1.18, defs, .4, true, provider,
			9.80665, PackedFloat64Array([0.0, 0.0, 0.0]), NAN, 0.0)
		check("before fixed stage valid", result.ok)
		print("FIXED_RESULT_HEX_SHA256 ", rpm, " ", var_to_bytes(result).hex_encode().sha256_text())
	print("Fixed before capture complete")
	quit(1 if failed else 0)
