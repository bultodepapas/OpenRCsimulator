# G2a-R1: exact cross-revision parity probe for the coupled-stage evaluation slice.
# Run the same file against two app roots with proof.py; no renderer or wall clock enters the flight state.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Wind := preload("res://physics/wind_config.gd")
const WashFixture := preload("res://tests/test_wash_profile.gd")

const PROBE_FORMAT := "openrc-stage-parity-probe v1"
const TOTAL_TICKS := 480
const CHECKPOINT_TICKS := [0, 1, 120, 240, 480]
const P51_ID := "p51d-mustang-120"


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	var output_path: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output_path = argument.substr(6)
	if output_path.is_empty():
		printerr("--out=absolute-report.json required")
		quit(2)
		return

	var case_reports: Array[Dictionary] = []
	for case: Dictionary in _cases():
		var result: Dictionary = _run_case(case)
		if result.is_empty():
			quit(1)
			return
		case_reports.append(result)

	var report: Dictionary = {
		"format": PROBE_FORMAT,
		"engine": Engine.get_version_info().string,
		"tick_hz": Engine.physics_ticks_per_second,
		"ticks": TOTAL_TICKS,
		"checkpoint_ticks": CHECKPOINT_TICKS,
		"cases": case_reports,
	}
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		printerr("cannot write parity report: ", output_path)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	file.close()
	print("G2a-R1 parity probe recorded ", case_reports.size(), " cases through ", TOTAL_TICKS, " ticks.")
	quit(0)


func _cases() -> Array[Dictionary]:
	var cases: Array[Dictionary] = []
	for aircraft_id: String in Catalog.ids():
		cases.append({
			"id": "split-" + aircraft_id,
			"aircraft_id": aircraft_id,
			"shaft_integrator": "split",
			"weather": {},
			"fixture": "catalog default aircraft data and weather",
		})

	var gust: Dictionary = Wind.defaults()
	gust.merge({
		"speed_mps": 3.0,
		"from_deg": 180.0,
		"gust_mps": 4.0,
		"gust_up_mps": 1.0,
		"gust_duration_s": 1.5,
		"gust_period_s": 4.0,
		"gust_delay_s": 0.3,
	}, true)
	var ou_atmosphere: Dictionary = Wind.preset("hot-high")
	ou_atmosphere.turbulence_rms_mps = [0.35, 0.25, 0.20]
	ou_atmosphere.turbulence_tau_s = 1.2
	ou_atmosphere.turbulence_seed = 20261009
	var calm: Dictionary = Wind.defaults()

	cases.append(_p51_case("p51-coupled-calm", calm, "calm weather"))
	cases.append(_p51_case("p51-coupled-gust", gust, "repeating wind and vertical gust"))
	cases.append(_p51_case("p51-coupled-ou-atmosphere", ou_atmosphere,
		"seeded OU turbulence with hot-high custom atmosphere"))
	var wash_case: Dictionary = _p51_case("p51-coupled-transported-wash", calm,
		"P-51 plus validated transported-wash test fixture")
	wash_case.transport_wash = true
	cases.append(wash_case)
	return cases


func _p51_case(case_id: String, weather: Dictionary, fixture: String) -> Dictionary:
	return {
		"id": case_id,
		"aircraft_id": P51_ID,
		"shaft_integrator": "coupled-rk4",
		"weather": weather,
		"fixture": fixture,
		"transport_wash": false,
	}


func _run_case(case: Dictionary) -> Dictionary:
	var entry: Dictionary = Catalog.entry(str(case.aircraft_id))
	if entry.is_empty() or not Catalog.can_fly(str(case.aircraft_id)):
		printerr("unknown or non-flyable parity aircraft: ", case.aircraft_id)
		return {}
	var flight: Node = Flight.new()
	flight.physics_enabled = false
	if case.shaft_integrator != "split" and not flight.setup_shaft_integrator(case.shaft_integrator):
		printerr(case.id, ": shaft setup failed: ", flight.shaft_error)
		flight.free()
		return {}
	if not case.weather.is_empty() and not flight.setup_weather(case.weather):
		printerr(case.id, ": weather setup failed: ", flight.weather_error)
		flight.free()
		return {}
	flight.setup(entry.data)
	flight.input_enabled = false
	if not flight.is_flyable():
		printerr(case.id, ": flight setup failed: ", flight.start_error, " ", flight.pause_reason)
		flight.free()
		return {}
	if bool(case.get("transport_wash", false)) and not _apply_transported_wash_fixture(flight, str(case.id)):
		flight.free()
		return {}

	var sim: Node = flight.sim
	var trajectory_hash := HashingContext.new()
	if trajectory_hash.start(HashingContext.HASH_SHA256) != OK:
		printerr("cannot start SHA-256 for trajectory")
		flight.free()
		return {}
	var checkpoint_hashes: Array[Dictionary] = []
	_set_tick_inputs(sim, 0)
	for row_tick: int in TOTAL_TICKS + 1:
		if row_tick > 0:
			_set_tick_inputs(sim, row_tick - 1)
			sim.step()
		if sim.tick != row_tick or not sim.fault_reason.is_empty():
			printerr(case.id, ": stopped at tick ", sim.tick, " while recording row ", row_tick,
				"; fault: ", sim.fault_reason)
			flight.free()
			return {}
		var boundary: Dictionary = flight.checkpoint()
		if boundary.is_empty() or not boundary.has("simulation"):
			printerr(case.id, ": invalid flight checkpoint at tick ", row_tick)
			flight.free()
			return {}
		var encoded: PackedByteArray = var_to_bytes(boundary)
		trajectory_hash.update(encoded)
		if CHECKPOINT_TICKS.has(row_tick):
			checkpoint_hashes.append({"tick": row_tick, "sha256": _sha256(encoded)})

	var result: Dictionary = {
		"id": case.id,
		"aircraft_id": case.aircraft_id,
		"shaft_integrator": case.shaft_integrator,
		"fixture": case.fixture,
		"rows": TOTAL_TICKS + 1,
		"checkpoint_sha256": checkpoint_hashes,
		"trajectory_sha256": trajectory_hash.finish().hex_encode(),
	}
	flight.free()
	print("ok ", case.id, " ", result.trajectory_sha256)
	return result


func _apply_transported_wash_fixture(flight: Node, case_id: String) -> bool:
	var p51_path: String = str(Catalog.entry(P51_ID).data)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(p51_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		printerr(case_id, ": cannot read P-51 source data")
		return false
	var raw: Dictionary = parsed
	var wash_source: Dictionary = WashFixture.combined_raw()
	var wash_raw: Dictionary = wash_source.propulsion.propeller.slipstream.duplicate(true)
	wash_raw.transport_speed_floor = WashFixture.quantity(1.0, "m/s")
	raw.propulsion.propeller.thrust_angles = WashFixture.quantity([0.0, 0.0], "deg")
	raw.propulsion.propeller.slipstream = wash_raw
	var checked: Dictionary = AircraftData.validate_and_derive(raw)
	if not checked.get("ok", false):
		printerr(case_id, ": transported-wash fixture rejected: ", str(checked.get("errors", [])))
		return false
	if not flight._apply(checked):
		printerr(case_id, ": transported-wash fixture could not be applied")
		return false
	flight.reset()
	return flight.is_flyable()


func _set_tick_inputs(sim: Node, tick_index: int) -> void:
	var roll_phase: int = tick_index % 120
	sim.inputs[0] = 0.08 if roll_phase < 40 else (-0.05 if roll_phase < 80 else 0.02)
	sim.inputs[1] = -0.035 if tick_index % 160 < 80 else 0.025
	sim.inputs[2] = 0.02 if tick_index % 96 < 48 else -0.015
	sim.inputs[3] = 0.70 if tick_index < 240 else 0.56


func _sha256(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()
