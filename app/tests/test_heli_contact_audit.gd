extends SceneTree

const Skids = preload("res://physics/rotorcraft/skid_contact.gd")
const M = preload("res://physics/math3d.gd")

var checks: int = 0
var failures: int = 0


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)


func make_state(altitude: float, pitch: float) -> PackedFloat64Array:
	var state: PackedFloat64Array = PackedFloat64Array()
	state.resize(19)
	state[2] = -altitude
	var attitude: PackedFloat64Array = M.q_from_euler(0.0, pitch, 0.0)
	for index: int in range(4):
		state[6 + index] = attitude[index]
	return state


func _initialize() -> void:
	var main: Dictionary = {
		"rotor_radius_m": 0.775,
		"hub_x_m": 0.0,
		"hub_y_m": 0.0,
		"hub_z_m": -0.235,
	}
	var tail: Dictionary = {
		"tail_rotor_radius_m": 0.13,
		"hub_distance_aft_m": 0.91,
		"hub_height_above_cg_m": 0.08,
	}
	var flat: PackedFloat64Array = PackedFloat64Array()
	var tail_arm: PackedFloat64Array = M.v3(-0.91, 0.0, -0.08)
	var tail_axis: PackedFloat64Array = M.v3(0.0, 1.0, 0.0)
	var steep_pitch: float = PI / 2.0
	var flat_state: PackedFloat64Array = make_state(1.035, steep_pitch)
	var flat_q: PackedFloat64Array = flat_state.slice(6, 10)
	check("90-degree pitched tail disc intersects flat ground in the narrowphase",
		Skids._disc_hits(flat_state, flat_q, tail_arm, tail_axis, 0.13, flat))
	check("tail ground strike is not skipped by broadphase",
		Skids.strike(flat_state, main, tail, flat) == "tail rotor ground strike")

	var rough: PackedFloat64Array = PackedFloat64Array([-INF, INF, -INF, INF, 0.8, 20.0])
	var elevated_state: PackedFloat64Array = make_state(1.044, steep_pitch)
	var elevated_q: PackedFloat64Array = elevated_state.slice(6, 10)
	check("positive terrain relief alone reaches the tail disc envelope",
		not Skids._disc_hits(elevated_state, elevated_q, tail_arm, tail_axis, 0.13, flat)
		and Skids._disc_hits(elevated_state, elevated_q, tail_arm, tail_axis, 0.13, rough))
	check("elevated-terrain tail strike is not skipped by broadphase",
		Skids.strike(elevated_state, main, tail, rough) == "tail rotor ground strike")

	var far_state: PackedFloat64Array = make_state(2.0, steep_pitch)
	check("far-field rotor discs remain clear", Skids.strike(far_state, main, tail, flat).is_empty())
	check("invalid state shape fails closed", Skids.strike(PackedFloat64Array([0.0, 0.0, 0.0]), main, tail, flat)
		== "invalid rotor strike input")
	var nonfinite_state: PackedFloat64Array = make_state(2.0, steep_pitch)
	nonfinite_state[0] = NAN
	check("nonfinite state fails closed", Skids.strike(nonfinite_state, main, tail, flat)
		== "invalid rotor strike input")
	check("malformed surface table fails closed", Skids.strike(far_state, main, tail,
		PackedFloat64Array([1.0, 2.0])) == "invalid rotor strike input")
	print("HELI contact audit: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
