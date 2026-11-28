## Counterexample probe: actual stock-plant impulse, independently evaluated complete kinetic energy.
## This invokes the production contact response at a prescribed frame-only contact; no piloted flight is claimed.
extends SceneTree

const Data := preload("res://physics/multirotor_data.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")
const Rates := preload("res://physics/multirotor/rates.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

var checks := 0
var failures := 0


func check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL " + label)


func energy(body: PackedFloat64Array, shafts: PackedFloat64Array, data: Dictionary) -> float:
	var j: PackedFloat64Array = data.inertia_kg_m2
	var p: float = body[10]
	var q: float = body[11]
	var r: float = body[12]
	var total: float = 0.5 * float(data.mass_kg) * (body[3]*body[3]+body[4]*body[4]+body[5]*body[5])
	total += 0.5 * (j[0]*p*p+j[1]*q*q+j[2]*r*r+2.0*j[3]*p*q+2.0*j[4]*p*r+2.0*j[5]*q*r)
	for i in 4:
		var inertia: float = data.rotors[i].inertia_kg_m2
		var spin: float = data.rotors[i].spin
		total += 0.5 * inertia * shafts[i] * shafts[i] - r * spin * inertia * shafts[i]
	return total


func _initialize() -> void:
	var loaded: Dictionary = Data.load_file("res://data/multirotors/openrc-fpv5-x1.json")
	check("stock data admitted", loaded.ok)
	if not loaded.ok:
		quit(1)
		return
	var prepared: Dictionary = Data.prepare(loaded.data, loaded.sha256)
	check("stock physical data prepared", prepared.ok)
	if not prepared.ok:
		quit(1)
		return
	var created: Dictionary = Plant.create(prepared.prepared, Rates.default_profile(), FC.THROTTLE_ABSOLUTE)
	check("stock electric plant created", created.ok)
	if not created.ok:
		quit(1)
		return
	var plant: RefCounted = created.plant
	var data: Dictionary = prepared.prepared
	var normal: PackedFloat64Array = M.v3(-cos(deg_to_rad(10.0)), -sin(deg_to_rad(10.0)), 0)
	var body: PackedFloat64Array = RB.make_state(M.v3(0, 0, -3), M.scale(normal, -0.2),
		PackedFloat64Array([1, 0, 0, 0]), M.v3(0, 0, 0))
	var top := INF
	for point: PackedFloat64Array in data.contacts.hull_frd:
		top = minf(top, point[2])
	var hub: PackedFloat64Array = data.rotors[1].hub_frd
	var contact: PackedFloat64Array = M.v3(hub[0], hub[1], (top + 2.0 * (-0.021 + 1.0e-6)) / 3.0)
	var frame: Dictionary = plant.initial_frame(body)
	var shafts := PackedFloat64Array([1600, 600, 600, 1600])
	for i in 4:
		frame.continuous[i] = shafts[i]
	check("prescribed frame satisfies stock state validator", plant.state_validator(frame, {}))
	var after: PackedFloat64Array = plant._bounce(body, contact, normal, 0.2, Plant.SOLID_RESPONSE, 0.4)
	var body_delta: float = plant._kinetic_energy(after) - plant._kinetic_energy(body)
	var complete_delta: float = energy(after, shafts, data) - energy(body, shafts, data)
	var zero := PackedFloat64Array([0, 0, 0, 0])
	var zero_delta: float = energy(after, zero, data) - energy(body, zero, data)
	print("DRONE-03 production _bounce: rigid_delta_j=%.12f complete_delta_j=%.12f zero_shaft_control_delta_j=%.12f free_axial_jump_rad_s=%.12f" % [
		body_delta, complete_delta, zero_delta, absf(after[12] - body[12])])
	check("body-only guard sees energy loss", body_delta < -0.006)
	check("current stock impulse increases full energy for imbalanced spin", complete_delta > 0.010)
	check("zero-shaft energy control remains dissipative", zero_delta < 0.0)
	check("untouched free axial angular speed jumps", absf(after[12] - body[12]) > 1.0)
	print("DRONE_FRAME_ENERGY_COUNTEREXAMPLE: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
