## FUEL-08 real-session state, exhaustion and exact continuation gates.
extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const LiquidFlight := preload("res://sim/liquid_fuel_flight.gd")
const RB := preload("res://physics/rigid_body.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const CheckpointJson := preload("res://sim/checkpoint_json.gd")
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
		var legacy: Dictionary = flight.checkpoint()
		legacy.erase("fuel_session")
		check("legacy liquid checkpoint retains destination selection as unknown",
			destination.restore_checkpoint(legacy) and destination.fuel_start_fill == 0.5
			and destination.trace_meta().get("fuel_start_fill_known", true) == false
			and destination.sim.continuous == flight.sim.continuous)
		var unknown_checkpoint: Dictionary = destination.checkpoint()
		var unknown_json: String = destination.checkpoint_json()
		var malformed_unknown: Dictionary = unknown_checkpoint.duplicate(true)
		malformed_unknown.fuel_session.start_fill = "0.5"
		var native_before: PackedByteArray = var_to_bytes(destination.checkpoint())
		check("malformed unknown liquid selection refuses native restore transactionally",
			not destination.restore_checkpoint(malformed_unknown)
			and var_to_bytes(destination.checkpoint()) == native_before)
		var native_destination: Node = Flight.new()
		native_destination.input_enabled = false
		native_destination.setup(path)
		native_destination.set_fuel_start_fill(0.75)
		check("chained native liquid checkpoint preserves receiving selection and exact state",
			native_destination.restore_checkpoint(unknown_checkpoint)
			and native_destination.fuel_start_fill == 0.75
			and native_destination.trace_meta().get("fuel_start_fill_known", true) == false
			and native_destination.sim.continuous == destination.sim.continuous
			and var_to_bytes(native_destination.sim.checkpoint()) == var_to_bytes(destination.sim.checkpoint()))
		native_destination.reset()
		check("native unknown liquid selection resets to receiving preference",
			native_destination.fuel_start_fill == 0.75
			and is_equal_approx(native_destination.mass_properties().fuel_remaining_kg, 0.75 * float(config.capacity_kg)))
		native_destination.free()
		var decoded_unknown: Dictionary = CheckpointJson.decode(unknown_json)
		var malformed_json_snapshot: Dictionary = decoded_unknown.snapshot.duplicate(true)
		malformed_json_snapshot.fuel_session.start_fill = true
		var malformed_unknown_json: String = CheckpointJson.encode(malformed_json_snapshot)
		var json_destination: Node = Flight.new()
		json_destination.input_enabled = false
		json_destination.setup(path)
		json_destination.set_fuel_start_fill(0.25)
		check("chained JSON liquid checkpoint preserves receiving selection and exact state",
			json_destination.restore_checkpoint_json(unknown_json)
			and json_destination.fuel_start_fill == 0.25
			and json_destination.trace_meta().get("fuel_start_fill_known", true) == false
			and json_destination.sim.continuous == destination.sim.continuous
			and var_to_bytes(json_destination.sim.checkpoint()) == var_to_bytes(destination.sim.checkpoint()))
		var json_before: PackedByteArray = var_to_bytes(json_destination.checkpoint())
		check("malformed unknown liquid selection refuses JSON restore transactionally",
			not json_destination.restore_checkpoint_json(malformed_unknown_json)
			and var_to_bytes(json_destination.checkpoint()) == json_before
			and json_destination.fuel_start_fill == 0.25)
		json_destination.reset()
		check("JSON unknown liquid selection resets to receiving preference",
			json_destination.fuel_start_fill == 0.25
			and is_equal_approx(json_destination.mass_properties().fuel_remaining_kg, 0.25 * float(config.capacity_kg)))
		json_destination.free()
		var invalid: Dictionary = flight.checkpoint()
		var original: PackedByteArray = var_to_bytes(destination.checkpoint())
		invalid.simulation.continuous[index] = -0.1
		check("negative fuel restore refuses transactionally", not destination.restore_checkpoint(invalid) and original == var_to_bytes(destination.checkpoint()))
		var bad_latch: Dictionary = flight.checkpoint()
		bad_latch.simulation.continuous[index + 1] = 2.0
		check("unsupported finite-source latch refuses transactionally",
			not destination.restore_checkpoint(bad_latch) and original == var_to_bytes(destination.checkpoint()))
		var bad_layout: Dictionary = flight.checkpoint()
		bad_layout.simulation.continuous.append(0.0)
		check("wrong finite-fuel continuous layout refuses transactionally",
			not destination.restore_checkpoint(bad_layout) and original == var_to_bytes(destination.checkpoint()))
		# A small positive usable inventory locates exhaustion inside this tick.
		flight.sim.state[RB.POS + 2] = -1000.0 # rundown remains clear of ground contacts
		flight.sim.continuous[index] = 1e-9
		flight.sim.continuous[index + 1] = 1.0
		flight.sim.step()
		var events: Array = flight.sim.last_events
		check("exhaustion located and source latches off", flight.sim.fault_reason.is_empty() and flight.sim.continuous[index] == 0.0 and flight.sim.continuous[index + 1] == 0.0 and events.size() == 1 and events[0].type == "fuel_exhausted")
		var residue: Dictionary = flight.mass_properties()
		check("unusable residue remains onboard", residue.ok and is_equal_approx(residue.fuel_remaining_kg, config.unusable_kg) and residue.fuel_usable_kg == 0.0)
		for tick: int in 2400:
			flight.sim.step()
		check("ten second exhaustion coast retains nonnegative fuel and accepted stopped source", flight.sim.fault_reason.is_empty() and flight.sim.continuous[index] == 0.0 and flight.sim.continuous[index + 1] == 0.0 and not flight.propulsion_source_running())
		flight.reset()
		check("reset restores selected fuel and source", is_equal_approx(flight.mass_properties().fuel_remaining_kg, 0.5 * config.capacity_kg) and flight.sim.continuous[index + 1] == 1.0 and flight.trace_meta().get("fuel_start_fill_known", false))
		flight.free()
		destination.free()
	_nonzero_residue()
	print("FUEL-08 session: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _nonzero_residue() -> void:
	var path := "res://data/aircraft/p51d_mustang_120.json"
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	raw.fuel_system.tanks[0].unusable = {value=0.1,unit="l",kind="estimated",source="synthetic positive-residue integration fixture"}
	var fixture: Dictionary = AircraftData.validate_and_derive(raw)
	check("positive unusable volume normalizes", fixture.ok)
	if not fixture.ok:
		return
	# load_file resolves wing-polar and wheel assets; the authored change only
	# affects normalized fuel records, so retain those resolved external modules.
	var normalized_fuel: Dictionary = fixture.model.fuel_system
	var normalized_adapter: Dictionary = fixture.model.propulsion.liquid_fuel
	var semantic_sha: String = fixture.model.data_sha256
	fixture.model = AircraftData.load_file(path).model.duplicate(true)
	fixture.model.fuel_system = normalized_fuel
	fixture.model.propulsion.liquid_fuel = normalized_adapter
	fixture.model.data_sha256 = semantic_sha
	fixture.input_identity = {format=AircraftData.FORMAT,sha256=JSON.stringify(raw,"",true,true).sha256_text()}
	var flight: Node = Flight.new()
	flight.input_enabled = false
	flight.setup("synthetic://positive-residue", "", fixture)
	check("positive-residue full launch admits", flight.is_flyable())
	if not flight.is_flyable():
		print("positive residue refusal: ", flight.start.get("message", ""), "; ", flight.sim.fault_reason)
		flight.free()
		return
	check("launch below unusable amount is refused without preference mutation", not flight.set_fuel_start_fill(0.05) and flight.fuel_start_fill == 1.0)
	var before: PackedByteArray = var_to_bytes(flight.checkpoint())
	var invalid: Dictionary = flight.checkpoint()
	invalid.fuel_session.start_fill = 0.05
	check("restored impossible launch fill is refused transactionally", not flight.restore_checkpoint(invalid) and before == var_to_bytes(flight.checkpoint()))
	var unknown_invalid: Dictionary = flight.checkpoint()
	unknown_invalid.fuel_session.start_fill = 0.05
	unknown_invalid.fuel_session.selection_known = false
	check("impossible serialized fill is rejected even when its provenance is unknown",
		not flight.restore_checkpoint(unknown_invalid) and before == var_to_bytes(flight.checkpoint()))
	var index: int = flight._liquid_index()
	flight.sim.state[RB.POS + 2] = -1000.0
	flight.sim.continuous[index] = 1e-9
	flight.sim.step()
	var sample: Dictionary = flight.mass_properties()
	var expected: float = flight.aircraft.model.propulsion.liquid_fuel.unusable_kg
	check("positive residue survives located exhaustion as onboard mass", flight.sim.fault_reason.is_empty() and sample.ok and expected > 0.0 and is_equal_approx(sample.fuel_remaining_kg,expected) and is_equal_approx(sample.volume_ml,100.0) and sample.fuel_usable_kg == 0.0)
	flight.free()
