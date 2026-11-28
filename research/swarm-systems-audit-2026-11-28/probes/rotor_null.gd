extends SceneTree

const Aircraft := preload("res://physics/rotorcraft_data.gd")
const Controls := preload("res://physics/rotorcraft/electronics.gd")
const Flight := preload("res://physics/rotorcraft/flight_dynamics.gd")
const Rotor := preload("res://physics/rotorcraft/main_rotor.gd")
const MainStage := preload("res://physics/rotorcraft/main_rotor_stage.gd")
const RB := preload("res://physics/rigid_body.gd")

var failures: int = 0
var checks: int = 0

func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	var aircraft := Aircraft.load_file("res://data/aircraft/xcell_60_research.json")
	check("catalog X-Cell loaded", aircraft.ok)
	if not aircraft.ok:
		quit(1)
		return
	var model: Dictionary = aircraft.context.main_model
	var air := PackedFloat64Array([10.0, 0.0, 0.0])
	var zero := PackedFloat64Array([0.0, 0.0, 0.0])
	var zero_sticks := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var omega: float = model.omega_nominal_rad_s
	var mu: float = air[0] / (omega * model.rotor_radius_m)
	var thrust_limit: float = 2.0 * model.rho_kg_m3 * PI * model.rotor_radius_m ** 2 * (air[0] / 1e6) ** 2
	print("XCell omega=", omega, " mu=", mu, " threshold_N=", String.num_scientific(thrust_limit))
	# Direct component sweep with both thrust signs, exact zero, and larger magnitudes.
	for pitch: float in [-1e-12, -1e-14, 0.0, 1e-14, 1e-12]:
		var isolated := Rotor.evaluate(model, omega, 0.0, air, zero, pitch, 0.0, 0.0, 0.0, 0.0)
		var stage := MainStage.evaluate(model, zero, omega, air, zero, pitch, 0.0, 0.0, 0.1)
		check("isolated rotor admissible", isolated.ok)
		if not isolated.ok:
			continue
		var thrust: float = isolated.thrust_n
		var expected: bool = thrust == 0.0 or absf(thrust) > thrust_limit
		check("signed pitch comparison", stage.ok == expected and isolated.within_identified_advance_ratio)
		print("pitch_rad=", String.num_scientific(pitch), " thrust_N=", String.num_scientific(thrust),
			" main_stage_ok=", stage.ok)

	# Same finite state, zero idle-up sticks. Vary only the dimensional vertical body velocity.
	# This uses the actual stock mixer/linkage and the full 19-state reference RK4 step.
	for vertical: float in [-1e-9, -1e-12, 0.0, 1e-12, 1e-9]:
		var state := PackedFloat64Array()
		state.resize(Flight.STATE_SIZE)
		state[RB.POS + 2] = -50.0
		state[RB.VEL] = air[0]
		state[RB.VEL + 2] = vertical
		state[RB.ATT] = 1.0
		state[Flight.OMEGA] = omega
		var controls := Controls.fast_evaluate(aircraft.context.electronics_model, state,
			zero_sticks, "idle_up", false)
		check("zero sticks produce zero collective", controls.ok and controls.collective_75_rad == 0.0)
		var original := state.to_byte_array()
		var evaluation := Flight.evaluate(state, aircraft.context, zero_sticks, "idle_up", false, false, zero)
		var step := Flight.rk4_step_at(state, 0.0, 1.0 / 240.0, aircraft.context,
			zero_sticks, "idle_up", false, false, zero)
		var expected: bool = vertical == 0.0 or absf(vertical) > 1e-12
		check("stock flight evaluation", evaluation.ok == expected)
		check("240 Hz coupled step", step.ok == expected)
		check("unchanged caller state", state.to_byte_array() == original)
		if not expected:
			check("joint stage fault", step.get("fault", "") == "aerodynamic_stage_refused")
		print("vertical_mps=", String.num_scientific(vertical), " evaluation_ok=", evaluation.ok,
			" step_ok=", step.ok, " fault=", step.get("fault", ""))
	print("ROTATIONAL NULL ", checks, " checks, ", failures, " failed")
	quit(1 if failures > 0 else 0)
