extends "C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-shaft-capacity/test_shaft_capacity.gd"
func _initialize() -> void:
	_fixture(); _electric_fixture()
	shaft_context = NewElectric.prepare_capacity(electric, provider, "fixed-voltage-synthetic-owner-no-events-v1")
	var s := _runtime_initial()
	var sample := func(v,t): return _airborne_point(v,t)
	for command: float in [.003, .004, .005, .006, .007, .01]:
		runtime_duty = command
		var seen: Array = []
		var strict := func(a,b,ar,br,dt):
			var r := _runtime_error_gate(a,b,ar,br,dt)
			seen.append(r.normalized_error)
			return r
		var result := NewStep.advance(s,0.0,1.0/240.0,_airborne_derivative,PackedFloat64Array(),sample,_shaft_certificate,
			{operator_law=NewStep.INTEGRATED_CAPACITY_LAW},strict)
		print("DIRECT_RESULT ",command," strict ",result.get("status","accepted")," scores ",seen," rpm ",result.get("state",s)[RB.SIZE+electric.rotor_index])
	quit()
