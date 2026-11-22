## A36 R2-F01: FPV rotor thrust, aerodynamic torque and in-plane rotor drag follow the stage's own air density
## (T = rho n^2 D^4 C_T at a fixed advance ratio) relative to the 1.225 kg/m3 bench reference; rotor inertia does not.
## At the reference density the ratio is exactly 1, so default-weather flights are unchanged bit for bit.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Fixtures := preload("res://tests/mr_fixtures.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const Rates := preload("res://physics/multirotor/rates.gd")
const Rotor := preload("res://physics/multirotor/rotor.gd")

## ISA troposphere at 500 m (the highest admitted air start): rho/rho0 = (1 - 0.0065*500/288.15)^4.255876.
const ISA_500M_RATIO := 0.952872

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, passed: bool, detail: Variant = "") -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL %s — %s" % [label, str(detail)])


func _near(a: float, b: float, tolerance := 1.0e-12) -> bool:
	return absf(a - b) <= tolerance * maxf(1.0, absf(b))


func _run() -> void:
	var ratio := pow(1.0 - 0.0065 * 500.0 / 288.15, 9.80665 / (287.05287 * 0.0065) - 1.0)
	check("independent ISA density ratio at 500 m", absf(ratio - ISA_500M_RATIO) < 1.0e-6, ratio)
	check("the reference density gives a ratio of exactly one", 1.225 / Rotor.REFERENCE_DENSITY == 1.0)
	_component(ratio)
	_plant("electric", Fixtures.electric(), ratio)
	_plant("laboratory", Fixtures.lab(), ratio)
	print("multirotor rotor density: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _component(ratio: float) -> void:
	var rotor := {thrust_coefficient_n_s2 = 2.0e-6, torque_coefficient_n_m_s2 = 3.0e-8, rotor_drag_n_s2_per_m = 4.0e-6,
		inertia_kg_m2 = 2.0e-6}
	var hub := M.v3(0.08, -0.08, 0.0)
	var v_air := M.v3(6.0, -2.0, 1.0)
	var rates := M.v3(0.3, -0.2, 0.5)
	var sea: Dictionary = Rotor.loads(2500.0, 1.0, hub, v_air, rates, 0.0, rotor)
	var high: Dictionary = Rotor.loads(2500.0, 1.0, hub, v_air, rates, 0.0, rotor, ratio)
	check("thrust and aerodynamic torque scale with density", _near(high.thrust, ratio * sea.thrust)
		and _near(high.torque, ratio * sea.torque), [high.thrust, sea.thrust])
	var scaled := true
	for i in 3:
		scaled = scaled and _near(high.force[i], ratio * sea.force[i]) and _near(high.moment[i], ratio * sea.moment[i])
	check("in-plane rotor drag and every rotor moment scale with density", scaled, [high.force, sea.force])
	var spin_up: Dictionary = Rotor.loads(0.0, 1.0, hub, v_air, rates, 400.0, rotor, ratio)
	check("the rotor's inertial reaction does not scale with density", spin_up.moment[2] == 2.0e-6 * 400.0,
		spin_up.moment[2])


## Hovering shafts, body at rest at 80 m (no airframe drag, no contact): every rotor force and its moments scale by the
## density ratio when only the plant's air density changes.
func _plant(label: String, data: Dictionary, ratio: float) -> void:
	var made: Dictionary = Plant.create(data, Rates.default_profile(), FC.THROTTLE_ABSOLUTE)
	if not made.get("ok", false):
		check("%s plant prepares" % label, false, made.get("message", ""))
		return
	var plant: RefCounted = made.plant
	var body: PackedFloat64Array = RB.make_state(M.v3(0.0, 0.0, -80.0), M.v3(0.0, 0.0, 0.0), M.q_identity(), M.v3(0.0, 0.0, 0.0))
	var frame: Dictionary = plant.initial_frame(body)
	frame.modes[FC.MODE_MOTOR] = FC.MOTOR_ARMED
	for i in 4:
		frame.continuous[i] = 1800.0 + 50.0 * i
		frame.aux[FC.AUX_COMMAND + i] = 0.4
	plant.rho = Rotor.REFERENCE_DENSITY
	var sea: Dictionary = plant._evaluate(frame.body, frame.continuous, 0.0, frame.aux, frame.modes)
	plant.rho = Rotor.REFERENCE_DENSITY * ratio
	var high: Dictionary = plant._evaluate(frame.body, frame.continuous, 0.0, frame.aux, frame.modes)
	var sea_loads: PackedFloat64Array = sea.loads
	var high_loads: PackedFloat64Array = high.loads
	check("%s plant: rotor thrust scales with stage density (500 m ISA)" % label,
		sea_loads[2] < 0.0 and _near(high_loads[2], ratio * sea_loads[2]), [high_loads[2], sea_loads[2]])
	check("%s plant: thrust moments scale with stage density" % label,
		_near(high_loads[3], ratio * sea_loads[3], 1.0e-11) and _near(high_loads[4], ratio * sea_loads[4], 1.0e-11),
		[high_loads, sea_loads])
	check("%s plant identity names the rotor density law" % label,
		str(plant.build().identity.get("rotor_density", "")) == Rotor.DENSITY_LAW)
