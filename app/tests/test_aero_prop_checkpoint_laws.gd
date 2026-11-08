# The flap and propeller continuations change solver behavior: old checkpoints must not resume silently.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Aero := preload("res://physics/aero.gd")
const Wheels := preload("res://physics/ground_wheels.gd")
const Propulsion := preload("res://physics/propulsion.gd")

var checks := 0
var failures := 0


func check(label: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func digest(parts: Array) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(parts))
	return context.finish().hex_encode()


func configuration_parts(flight: Node, aero_law: String, include_lookup: bool) -> Array:
	# This deliberately constructs the exact identity for the asserted, fixed Stik fixture.
	var parts: Array = [flight.aircraft.model, flight.ground_surfaces,
		aero_law + "; " + Aero.WAKE_STATE_UNIT]
	if include_lookup:
		parts.append(Propulsion.COEFFICIENT_LAW)
	parts.append("wheel-state-layout:" + flight.wheel_state_layout())
	parts.append(Wheels.ROLLING_LAW)
	return parts


func _initialize() -> void:
	var flight := Flight.new()
	flight.setup("res://data/aircraft/jensen_ugly_stik_60.json")
	flight.input_enabled = false
	var fixture_ok: bool = flight.is_flyable() and flight.weather_is_calm() and flight.atmosphere_is_reference() \
		and not flight.soft_hull_contacts and not flight.gear_is_retractable() and not flight.wheel_brake_available() \
		and flight.wheel_count() == 3 and not flight.flaps_available() and not flight.shaft_is_coupled() \
		and not flight.glow_is_active() and not flight.liquid_fuel_is_active() and not flight.turbine_is_continuous() \
		and not flight.aircraft.model.get("envelope", {}).is_empty() \
		and flight.stage_backend_identity().backend == "gdscript_reference"
	check("bounded three-wheel legacy Stik fixture", fixture_ok)
	if not fixture_ok:
		flight.free()
		print("Aero and lookup checkpoint laws: %d checks, %d failed" % [checks, failures])
		quit(1)
		return
	var snapshot: Dictionary = flight.checkpoint()
	var current := digest(configuration_parts(flight, Aero.LOADS_LAW, true))
	var old_lookup := digest(configuration_parts(flight, Aero.LOADS_LAW, false))
	var old_aero := digest(configuration_parts(flight, "section-plane-source-weighted-wake-velocity-v2", true))
	check("fixture checkpoint and independently reconstructed current configuration", not snapshot.is_empty() \
		and snapshot.get("configuration", "") == current,
		"actual %s expected %s" % [snapshot.get("configuration", ""), current])
	check("historical identities differ individually from current and each other", current != old_lookup \
		and current != old_aero and old_lookup != old_aero)
	flight.sim.step()
	check("fixture advanced before restoring", flight.sim.tick == 1)
	check("current checkpoint restores", flight.restore_checkpoint(snapshot) and flight.sim.tick == 0 \
		and var_to_bytes(flight.sim.checkpoint()) == var_to_bytes(snapshot.simulation))
	var before: PackedByteArray = var_to_bytes(flight.checkpoint())
	var was_paused: bool = flight.sim.paused
	var was_input_enabled: bool = flight.input_enabled
	var was_pause_reason: String = flight.pause_reason
	var stage: Callable = flight.sim.model.stage
	var pre_tick: Callable = flight.sim.model.pre_tick
	for change in ["lookup", "aero configuration", "aero field"]:
		var old: Dictionary = snapshot.duplicate(true)
		match change:
			"lookup": old.configuration = old_lookup
			"aero configuration": old.configuration = old_aero
			"aero field": old.aero_loads_law = "section-plane-source-weighted-wake-velocity-v2"
		var rejected: bool = not flight.restore_checkpoint(old)
		check("historical %s rejected with session state preserved" % change, rejected \
			and var_to_bytes(flight.checkpoint()) == before and flight.sim.paused == was_paused \
			and flight.input_enabled == was_input_enabled and flight.pause_reason == was_pause_reason \
			and flight.sim.model.stage == stage and flight.sim.model.pre_tick == pre_tick)
	flight.free()
	print("Aero and lookup checkpoint laws: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
