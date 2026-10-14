extends SceneTree
const Fixture = preload("res://tests/test_heli_flight.gd")
const Flight = preload("res://physics/rotorcraft/flight_dynamics.gd")
const M = preload("res://physics/math3d.gd")
var checks := 0
var failures := 0
func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)
func _initialize() -> void:
	var prepared: Dictionary = Fixture.make_context()
	check("fixture prepares", prepared.ok)
	if not prepared.ok:
		quit(1)
		return
	var state: PackedFloat64Array = Fixture.state_at_hover()
	state[14] = 0.1
	state[15] = 0.1
	var raw_axis := M.v3(-M.sin_(state[14]), M.sin_(state[15]), -M.cos_(state[14])*M.cos_(state[15]))
	var roll := M.atan2_(-raw_axis[1],-raw_axis[2])
	var rotated_z := M.sin_(roll)*raw_axis[1]+M.cos_(roll)*raw_axis[2]
	var pitch := M.atan2_(raw_axis[0],-rotated_z)
	var attitude := M.q_from_euler(0.0,pitch,roll)
	for index: int in range(4): state[6+index]=attitude[index]
	var unnormalized_projection: float=M.q_rotate(attitude,raw_axis)[2]
	check("regression fixture exposes a nonunit combined-flap axis", unnormalized_projection < -1.000001)
	var unit_axis := M.scale(raw_axis,1.0/M.norm(raw_axis))
	check("physical disc normal aligns with world up", absf(M.q_rotate(attitude,unit_axis)[2]+1.0)<1e-12)
	var result: Dictionary=Flight.evaluate(state,prepared.context,PackedFloat64Array([0,0,0,0]),"normal",true,false,M.v3(0,0,0),true,PackedFloat64Array(),{},3.0)
	check("valid combined flap does not spuriously refuse ground-effect projection",result.ok)
	if result.ok:
		check("fixture remains within the declared small-flap envelope",result.aero.main_rotor.within_small_flap_angle_range)
	print("HELI disc normal audit: %d checks, %d failed" % [checks,failures])
	quit(1 if failures else 0)
