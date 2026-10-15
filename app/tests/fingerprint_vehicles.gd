# SF-01/02/03 proof tool, not a test: SHA-256 trajectory fingerprints of scripted sessions for every flyable airplane,
# the research helicopter (hover and pad starts) and the RC ground vehicle, so a kernel change can be shown byte-identical on one host
# and build. Hash input after reset and after every tick: body state, continuous blocks, sampled aux, discrete modes
# and the start-of-tick loads, in native float64 byte order. Inputs follow a fixed schedule; no radio or render.
# Run: godot --headless --path app --script res://tests/fingerprint_vehicles.gd [-- --ticks=960 --heli-ticks=1200
#      --output=/tmp/fingerprints.json --skip-heli --skip-ground --extra-data=res://data/aircraft/a.json,res://data/aircraft/b.json]
# SF-04: every airplane also runs a `<id>/cut` variant (source cut at tick 300: glow_cut() or engine_running=false),
# the helicopter an `airborne-hold` variant (drive hold at tick 300), and --extra-data adds non-catalog fixtures.
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const HelicopterSession := preload("res://sim/helicopter_flight_session.gd")
const AircraftCatalog := preload("res://app_state/aircraft_catalog.gd")
const Field := preload("res://data/field_loader.gd")
const GroundSession := preload("res://sim/ground_vehicle/session.gd")

const FORMAT := "openrc-vehicle-fingerprints v1"

var _ticks: int = 960
var _heli_ticks: int = 1200
var _output: String = ""
var _skip_heli: bool = false
var _skip_ground: bool = false
var _extra_data: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ticks="):
			_ticks = maxi(1, int(arg.trim_prefix("--ticks=")))
		elif arg.begins_with("--heli-ticks="):
			_heli_ticks = maxi(1, int(arg.trim_prefix("--heli-ticks=")))
		elif arg.begins_with("--output="):
			_output = arg.trim_prefix("--output=")
		elif arg == "--skip-heli":
			_skip_heli = true
		elif arg == "--skip-ground":
			_skip_ground = true
		elif arg.begins_with("--extra-data="):
			for item in arg.trim_prefix("--extra-data=").split(",", false):
				_extra_data.append(item)
	_run.call_deferred()


func _run() -> void:
	var report: Dictionary = {
		"format": FORMAT,
		"godot": Engine.get_version_info().string,
		"ticks": _ticks,
		"heli_ticks": _heli_ticks,
		"method": "SHA-256 over state, continuous, aux, var_to_bytes(modes) and last_loads after reset and after every tick; fixed input schedule. Ground vehicle: SHA-256 over state_snapshot() after each accepted tick of a fixed control schedule.",
		"vehicles": [],
	}
	for id in AircraftCatalog.airplane_flyable_ids():
		var entry: Dictionary = AircraftCatalog.entry(id)
		report.vehicles.append(_airplane(id, str(entry.data), -1))
		report.vehicles.append(_airplane(id + "/cut", str(entry.data), 300))
	for path in _extra_data:
		var label: String = path.get_file().get_basename()
		report.vehicles.append(_airplane(label, path, -1))
		report.vehicles.append(_airplane(label + "/cut", path, 300))
	if not _skip_heli:
		report.vehicles.append(_helicopter("airborne", -1))
		report.vehicles.append(_helicopter("airborne-hold", 300))
		report.vehicles.append(_helicopter("ground", -1))
	if not _skip_ground:
		report.vehicles.append(_ground_vehicle())
	for entry in report.vehicles:
		print(entry.id, " ", entry.kind, " inputs=", entry.inputs, " continuous=", entry.continuous, " aux=", entry.aux,
			" ticks=", entry.ticks, " fault=", entry.fault, " events=", entry.get("events", 0), " sha256=", entry.sha256)
	if not _output.is_empty():
		var file: FileAccess = FileAccess.open(_output, FileAccess.WRITE)
		if file == null:
			push_error("cannot write " + _output)
			quit(1)
			return
		file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
		file.close()
		print("wrote ", _output)
	quit()


func _airplane(id: String, data_path: String, cut_tick: int) -> Dictionary:
	var session: Node = FlightSession.new()
	session.input_enabled = false
	session.physics_enabled = false
	session.setup(data_path)
	root.add_child(session)
	var result: Dictionary = {"id": id, "kind": "fixed-wing", "inputs": 0, "continuous": 0, "aux": 0, "ticks": 0, "fault": "", "events": 0, "sha256": ""}
	if not session.is_flyable():
		result.fault = "setup: " + str(session.pause_reason)
		session.free()
		return result
	session.reset()
	var sim: Node = session.sim
	var base: PackedFloat64Array = sim.inputs.duplicate()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	_absorb(ctx, sim)
	for tick in _ticks:
		var inputs: PackedFloat64Array = base.duplicate()
		if tick >= 100 and tick < 220:
			inputs[1] = clampf(base[1] + 0.3, -1.0, 1.0)
		if tick >= 300 and tick < 400:
			inputs[0] = clampf(base[0] + 0.4, -1.0, 1.0)
		if tick >= 500 and tick < 600:
			inputs[2] = clampf(base[2] + 0.3, -1.0, 1.0)
		if tick >= 650 and tick < 900:
			inputs[3] = clampf(base[3] + 0.3, 0.0, 1.0)
		if tick == cut_tick:
			if session.has_method("glow_is_active") and session.glow_is_active():
				session.glow_cut()
			else:
				session.engine_running = false
		if cut_tick >= 0 and tick >= cut_tick:
			inputs[3] = 0.0
		sim.inputs = inputs
		sim.step()
		result.ticks = tick + 1
		if not sim.fault_reason.is_empty():
			result.fault = "tick %d: %s" % [tick, sim.fault_reason]
			break
		_absorb(ctx, sim)
		result.events += _event_count(sim)
	result.inputs = sim.input_size
	result.continuous = sim.continuous.size()
	result.aux = sim.aux.size()
	result.sha256 = ctx.finish().hex_encode()
	session.free()
	return result


func _helicopter(start: String, hold_tick: int) -> Dictionary:
	var session: Node = HelicopterSession.new()
	session.input_enabled = false
	session.physics_enabled = false
	root.add_child(session)
	var result: Dictionary = {"id": "helicopter/" + start, "kind": "rotorcraft", "inputs": 0, "continuous": 0, "aux": 0, "ticks": 0, "fault": "", "events": 0, "sha256": ""}
	var ok: bool = session.setup()
	if ok and start == "ground":
		var field: Dictionary = Field.load_from(Field.DEFAULT_PATH)
		ok = field.ok and session.set_field(field.field) and session.set_start_choice("ground")
	if not ok or not session.reset():
		result.fault = "setup: " + str(session.start_error) + " " + str(session.pause_reason)
		session.free()
		return result
	var sim: Node = session.sim
	var hover_throttle: float = session.commands.throttle
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	_absorb(ctx, sim)
	for tick in _heli_ticks:
		var inputs: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, hover_throttle])
		if tick >= 200 and tick < 500:
			inputs[3] = clampf(hover_throttle + 0.04, 0.0, 1.0)
		if tick >= 600 and tick < 700:
			inputs[0] = 0.3
		if tick >= 800 and tick < 900:
			inputs[2] = 0.2
		if tick >= 950 and tick < 1050:
			inputs[1] = -0.25
		if tick == hold_tick:
			session.set_drive_hold(true)
		sim.inputs = inputs
		sim.step()
		result.ticks = tick + 1
		if not sim.fault_reason.is_empty():
			result.fault = "tick %d: %s" % [tick, sim.fault_reason]
			break
		_absorb(ctx, sim)
		result.events += _event_count(sim)
	result.inputs = sim.input_size
	result.continuous = sim.continuous.size()
	result.aux = sim.aux.size()
	result.sha256 = ctx.finish().hex_encode()
	session.free()
	return result


## The ground vehicle is driven through its public session API only, so the same run works on trees before SF-03.
func _ground_vehicle() -> Dictionary:
	var session: Node = GroundSession.new()
	root.add_child(session)
	var result: Dictionary = {"id": "ground-vehicle/default", "kind": "ground-vehicle", "inputs": 4,
		"continuous": GroundSession.STATE_SIZE - 13, "aux": 0, "ticks": 0, "fault": "", "sha256": ""}
	if not session.prepare_default():
		result.fault = "setup: " + str(session.load_error)
		session.free()
		return result
	var neutral: Dictionary = {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}
	if not session.tick_once(neutral) or not session.resume():
		result.fault = "arming: " + str(session.load_error) + " " + str(session.fault_reason)
		session.free()
		return result
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(session.state_snapshot().to_byte_array())
	for tick in _ticks:
		var sample: Dictionary = neutral.duplicate()
		if tick < 400:
			sample.throttle = 0.6
		if tick >= 150 and tick < 300:
			sample.steering = 0.5
		if tick >= 450 and tick < 550:
			sample.brake = 1.0
		if tick >= 600 and tick < 800:
			sample.throttle = 0.3
			sample.reverse = true
		if not session.tick_once(sample):
			result.fault = "tick %d: %s" % [tick, session.fault_reason]
			break
		result.ticks = tick + 1
		ctx.update(session.state_snapshot().to_byte_array())
	result.sha256 = ctx.finish().hex_encode()
	session.free()
	return result


## Located events per tick (SF-04 kernels); zero on trees whose kernel has no event record.
func _event_count(sim: Node) -> int:
	var record: Variant = sim.get("last_events")
	return record.size() if record is Array else 0


func _absorb(ctx: HashingContext, sim: Node) -> void:
	ctx.update(sim.state.to_byte_array())
	ctx.update(sim.continuous.to_byte_array())
	ctx.update(sim.aux.to_byte_array())
	ctx.update(var_to_bytes(sim.modes))
	ctx.update(sim.last_loads.to_byte_array())
