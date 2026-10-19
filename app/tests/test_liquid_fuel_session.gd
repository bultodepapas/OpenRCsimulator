## FUEL-08 real-session state, exhaustion and exact continuation gates.
extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const LiquidFlight := preload("res://sim/liquid_fuel_flight.gd")
const RB := preload("res://physics/rigid_body.gd")
var checks := 0
var failures := 0


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
	print(("ok " if passed else "FAIL ") + label)


func _initialize() -> void:
	for path: String in ["res://data/aircraft/p51d_mustang_120.json", "res://data/aircraft/sebart_avanti_s_a200.json"]:
		var flight: Node = Flight.new()
		flight.input_enabled = false
		flight.setup(path)
		check(path + " finite aircraft admits", flight.is_flyable() and flight.liquid_fuel_is_active())
		if not flight.is_flyable() or not flight.liquid_fuel_is_active():
			flight.free()
			continue
		var index: int = flight._liquid_index()
		var config: Dictionary = flight.aircraft.model.propulsion.liquid_fuel
		check("full capacity distinct from reference", is_equal_approx(flight.mass_properties().fuel_remaining_kg, config.capacity_kg))
		check("half fill selects", flight.set_fuel_start_fill(0.5))
		flight.reset()
		var before: Dictionary = flight.mass_properties()
		var bytes: PackedByteArray = var_to_bytes(flight.sim.checkpoint())
		var detached: Dictionary = flight.mass_properties()
		detached.cg_body_m[0] += 100.0
		check("sample is detached and read only", var_to_bytes(flight.sim.checkpoint()) == bytes and flight.mass_properties().cg_body_m != detached.cg_body_m)
		for tick: int in 120:
			flight.sim.step()
		var after: Dictionary = flight.mass_properties()
		check("finite flight burns fuel and total mass", flight.sim.fault_reason.is_empty() and after.ok and after.fuel_remaining_kg < before.fuel_remaining_kg and after.mass_kg < before.mass_kg)
		var destination: Node = Flight.new()
		destination.input_enabled = false
		destination.setup(path)
		check("v11 JSON checkpoint restores selection and bits", destination.restore_checkpoint_json(flight.checkpoint_json()) and destination.fuel_start_fill == 0.5 and var_to_bytes(destination.sim.checkpoint()) == var_to_bytes(flight.sim.checkpoint()))
		for tick: int in 20:
			flight.sim.step()
			destination.sim.step()
		check("restored continuation exact", var_to_bytes(destination.sim.checkpoint()) == var_to_bytes(flight.sim.checkpoint()))
		var invalid: Dictionary = flight.checkpoint()
		var original: PackedByteArray = var_to_bytes(destination.checkpoint())
		invalid.simulation.continuous[index] = -0.1
		check("negative fuel restore refuses transactionally", not destination.restore_checkpoint(invalid) and original == var_to_bytes(destination.checkpoint()))
		# A small positive usable inventory locates exhaustion inside this tick.
		flight.sim.continuous[index] = 1e-9
		flight.sim.continuous[index + 1] = 1.0
		flight.sim.step()
		var events: Array = flight.sim.last_events
		check("exhaustion located and source latches off", flight.sim.fault_reason.is_empty() and flight.sim.continuous[index] == 0.0 and flight.sim.continuous[index + 1] == 0.0 and events.size() == 1 and events[0].type == "fuel_exhausted")
		var residue: Dictionary = flight.mass_properties()
		check("unusable residue remains onboard", residue.ok and is_equal_approx(residue.fuel_remaining_kg, config.unusable_kg) and residue.fuel_usable_kg == 0.0)
		for tick: int in 20:
			flight.sim.step()
		check("post exhaustion coasts without negative fuel", flight.sim.fault_reason.is_empty() and flight.sim.continuous[index] == 0.0 and flight.sim.continuous[index + 1] == 0.0)
		flight.reset()
		check("reset restores selected fuel and source", is_equal_approx(flight.mass_properties().fuel_remaining_kg, 0.5 * config.capacity_kg) and flight.sim.continuous[index + 1] == 1.0)
		flight.free()
		destination.free()
	print("FUEL-08 session: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
