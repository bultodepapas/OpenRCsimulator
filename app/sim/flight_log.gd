## FL-02: bounded, opt-in fixed-wing black box. No solver evaluations or input writes.
## Exact Variant packets preserve packed float64 and int64 RNG state. CSV is an offline view.
extends RefCounted

const MAGIC := "ORFL0001"
const FORMAT := "openrc-flight-log v1"
const MAX_PACKET := 16 * 1024 * 1024
const CHUNK_TICKS := 240
const MAX_BYTES := 512 * 1024 * 1024
const MAX_TICKS := 240 * 60 * 60
const BuildInfo := preload("res://app_state/build_info.gd")
const BODY := preload("res://physics/rigid_body.gd")
const Air := preload("res://physics/air_data.gd")

var recording := false
var note := ""
var path := ""
var failure := ""
var header: Dictionary = {}
var rows_written := 0
var observer_usec := 0
var peak_buffer_rows := 0
var _session: Node
var _file: FileAccess
var _rows: Array = []
var _events: Array = []
var _expected: Dictionary = {}
var _pending: Dictionary = {}
var _last_tick := -1
var _start_tick := 0
var _chain := PackedByteArray()
var _stopping := false


func _init(session: Node) -> void:
	_session = session


func start(destination := "") -> Error:
	if recording:
		return ERR_ALREADY_IN_USE
	failure = ""
	var checkpoint: Dictionary = _session.checkpoint()
	if checkpoint.is_empty() or not _session.physics_enabled:
		return _failed("Flight log requires a valid fixed-wing checkpoint.", ERR_INVALID_DATA)
	path = destination
	if path.is_empty():
		path = "user://flight_logs/flight-%s-%d.orfl" % [Time.get_datetime_string_from_system(true).replace(":", "-"), Time.get_ticks_usec()]
	if FileAccess.file_exists(path):
		return _failed("Flight log already exists: " + path, ERR_ALREADY_EXISTS)
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	if err != OK:
		return _failed("Cannot create flight-log directory (%d)." % err, err)
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		return _failed("Cannot open flight log (%d)." % FileAccess.get_open_error(), ERR_CANT_CREATE)
	_rows.clear()
	_events.clear()
	_pending.clear()
	_stopping = false
	_chain.clear()
	rows_written = 0
	observer_usec = 0
	peak_buffer_rows = 0
	_start_tick = _session.sim.tick
	_last_tick = _start_tick
	header = {
		kind = "header", format = FORMAT, created_utc = Time.get_datetime_string_from_system(true),
		dt_s = _session.sim.dt(), engine = Engine.get_version_info().string,
		build = BuildInfo.current(), solver_sha256 = solver_identity(),
		metadata = _session.trace_meta(), checkpoint = checkpoint,
		aircraft = _session.aircraft.duplicate(true), aircraft_path = _session.aircraft_path,
		ground_surfaces = _session.ground_surfaces.duplicate(), ground_field_id = _session.ground_field_id,
		airframe_surfaces = _session.airframe_surfaces.duplicate(),
		collision_world = _session.collision_world(), lake = _session.lake_context(),
		weather = _session.weather_configuration(), shaft_integrator = _session.shaft_integrator(),
		soft_hull_contacts = _session.soft_hull_contacts,
		rates = _session.effective_rate_profile(),
		input_boundary = "post conditioning/rates/trim, before failure and servo; drives interval ending at tick",
		loads_boundary = "RK4 k1, interval start; initial row uses initial loads",
		layout = {state = 13, loads = 6, inputs = _session.sim.inputs.size(), aux = _session.sim.aux.size(),
			continuous = _session.sim.continuous.size(), modes = _session.sim.modes.size(), mass = 4},
		mass_boundary = "FUEL-06: live mass kg and CG offset [x, y, z] m body FRD from the fixed datum O, accepted tick end",
	}
	_file.store_buffer(MAGIC.to_ascii_buffer())
	if not _write_packet(header):
		return ERR_FILE_CANT_WRITE
	recording = true
	_expected = _boundary()
	_rows.append(_sample({}))
	peak_buffer_rows = 1
	_session.sim.before_step.connect(_before_step)
	_session.sim.stepped.connect(_stepped)
	_session.sim.faulted.connect(_faulted)
	_session.sim.paused_changed.connect(_paused)
	_session.resetting.connect(_resetting)
	_session.rate_profile_changed.connect(_rates)
	# Persist the initial snapshot immediately; later blocks flush at most once per simulated second.
	_flush_rows()
	note = "Flight log REC: " + ProjectSettings.globalize_path(path)
	print(note)
	return OK if recording else ERR_FILE_CANT_WRITE


func seconds() -> float:
	return (_last_tick - _start_tick) * _session.sim.dt()


func mark(label := "pilot marker") -> void:
	if recording:
		_event("marker", label.left(160))


func stop(reason := "stopped") -> Error:
	if not recording:
		return OK if failure.is_empty() else ERR_FILE_CANT_WRITE
	_stopping = true
	_event("stop", reason)
	_flush_rows()
	if recording:
		var footer := {kind = "footer", rows = rows_written, final_tick = _last_tick,
			reason = reason, chain_sha256 = _chain.hex_encode(), observer_usec = observer_usec,
			peak_buffer_rows = peak_buffer_rows, checkpoint = _session.checkpoint()}
		_write_packet(footer)
	_disconnect()
	recording = false
	if _file != null:
		_file.close()
		_file = null
	if failure.is_empty():
		note = "Flight log saved: %s (%d ticks)" % [ProjectSettings.globalize_path(path), rows_written - 1]
		print(note)
	return OK if failure.is_empty() else ERR_FILE_CANT_WRITE


func _disconnect() -> void:
	for pair in [[_session.sim.before_step, _before_step], [_session.sim.stepped, _stepped],
		[_session.sim.faulted, _faulted], [_session.sim.paused_changed, _paused], [_session.resetting, _resetting],
		[_session.rate_profile_changed, _rates]]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])


func _boundary() -> Dictionary:
	var result := {}
	for key in ["state", "previous", "aux", "continuous", "modes"]:
		result[key] = _session.sim.get(key).duplicate()
	return result


func _before_step(_tick: int) -> void:
	if not recording:
		return
	var started := Time.get_ticks_usec()
	_pending = {}
	# Starter, engine cut and other out-of-tick edits are sparse interventions, never lost inputs.
	for key in _expected:
		var current: Variant = _session.sim.get(key)
		if current.to_byte_array() != _expected[key].to_byte_array():
			_pending[key] = current.duplicate()
	observer_usec += Time.get_ticks_usec() - started


func _sample(intervention: Dictionary) -> Dictionary:
	var sample := _boundary()
	sample.erase("previous")
	sample.kind = "sample"
	sample.tick = _session.sim.tick
	sample.inputs = _session.sim.inputs.duplicate()
	sample.loads = _session.sim.last_loads.duplicate()
	sample.intervention = intervention.duplicate(true)
	sample.raw = _controls(_session.raw)
	sample.sticks = _controls(_session.commands)
	# Existing cheap air transform; no extra force, derivative or RK evaluation.
	var wind: PackedFloat64Array = _session.wind_at(_session.sim.time())
	var air: Dictionary = Air.compute(_session.sim.state, wind, _session.air_density(_session.sim.state))
	sample.air = PackedFloat64Array([air.V, air.alpha, air.beta, wind[0], wind[1], wind[2]])
	# FUEL-06: the live mass sample (read-only kernel evaluation; finite fuel changes it every tick).
	var live: Dictionary = _session.mass_properties() if _session.has_method("mass_properties") else {}
	sample.mass = PackedFloat64Array([live.mass_kg, live.cg_body_m[0], live.cg_body_m[1], live.cg_body_m[2]]) \
		if live.get("ok", false) else PackedFloat64Array([_session.sim.mass, 0.0, 0.0, 0.0])
	return sample


static func _controls(value: Dictionary) -> PackedFloat64Array:
	return PackedFloat64Array([value.get("roll", 0.0), value.get("pitch", 0.0), value.get("yaw", 0.0), value.get("throttle", 0.0)])


func _stepped(tick: int, _t: float, _s: PackedFloat64Array, _l: PackedFloat64Array, _i: PackedFloat64Array, _a: PackedFloat64Array) -> void:
	if not recording:
		return
	var started := Time.get_ticks_usec()
	if tick != _last_tick + 1:
		_failed("Flight log stopped: nonconsecutive simulation ticks.", ERR_INVALID_DATA)
		_disconnect()
		return
	_rows.append(_sample(_pending))
	_expected = _boundary()
	_last_tick = tick
	peak_buffer_rows = maxi(peak_buffer_rows, _rows.size())
	if _rows.size() >= CHUNK_TICKS:
		_flush_rows()
	observer_usec += Time.get_ticks_usec() - started
	if tick - _start_tick >= MAX_TICKS or (_file != null and _file.get_position() >= MAX_BYTES):
		stop("recording limit reached")


func _event(kind: String, detail: String) -> void:
	_events.append({tick = _session.sim.tick, kind = kind, detail = detail})
	if _events.size() >= CHUNK_TICKS:
		_flush_rows()


func _paused(value: bool) -> void:
	if recording:
		_event("pause" if value else "resume", _session.pause_reason.left(160))
		_flush_rows()


## D6e-R2: the rate switch takes effect at the next tick's input sample, which the recorded inputs already carry.
func _rates(_active: bool) -> void:
	if recording:
		_event("rates", _session.effective_rate_profile())


func _faulted(reason: String) -> void:
	if recording:
		stop("simulation fault: " + reason)


func _resetting() -> void:
	stop("session reset or configuration change")


func _flush_rows() -> void:
	if not recording or (_rows.is_empty() and _events.is_empty()):
		return
	var count := _rows.size()
	if _write_packet({kind = "block", rows = _rows, events = _events}):
		rows_written += count
	_rows.clear()
	_events.clear()
	if recording and not _stopping and _file.get_position() >= MAX_BYTES - 2 * MAX_PACKET:
		stop("recording byte limit reached")


func _write_packet(value: Dictionary) -> bool:
	var payload := var_to_bytes(value)
	if payload.is_empty() or payload.size() > MAX_PACKET:
		_failed("Flight log packet exceeds bounded format.", ERR_INVALID_DATA)
		return false
	# Applies to marker/pause-only streams too. Never grow an unbounded file without simulation ticks.
	if _file.get_position() + payload.size() + 36 > MAX_BYTES:
		_failed("Flight log byte limit exceeded; file is incomplete.", ERR_FILE_CANT_WRITE)
		return false
	var digest := sha256(payload)
	_file.store_32(payload.size())
	_file.store_buffer(digest)
	_file.store_buffer(payload)
	_file.flush()
	if _file.get_error() != OK:
		_failed("Flight log disk write failed; file is incomplete.", ERR_FILE_CANT_WRITE)
		return false
	_chain = sha256(_chain + digest)
	return true


func _failed(message: String, code: Error) -> Error:
	failure = message
	note = message
	recording = false
	_disconnect()
	if _file != null:
		_file.close()
		_file = null
	printerr(message)
	return code


static func sha256(bytes: PackedByteArray) -> PackedByteArray:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish()


## No object decoding. Bounds and checksum are checked before decoding a packet.
static func read_packet(file: FileAccess) -> Dictionary:
	var remaining := file.get_length() - file.get_position()
	if remaining < 36:
		return {ok = false, error = "Missing footer or truncated packet header."}
	var size := file.get_32()
	if size <= 0 or size > MAX_PACKET or size > remaining - 36:
		return {ok = false, error = "Invalid or truncated packet length."}
	var digest := file.get_buffer(32)
	var bytes := file.get_buffer(size)
	if sha256(bytes) != digest:
		return {ok = false, error = "Packet checksum mismatch."}
	var value: Variant = bytes_to_var(bytes)
	if not value is Dictionary:
		return {ok = false, error = "Packet is not a dictionary."}
	return {ok = true, value = value, digest = digest}


## Fingerprint actual source where present. Export build identity is also retained in the header.
static func solver_identity() -> String:
	var paths: Array[String] = []
	for directory in ["res://physics", "res://sim", "res://failures"]:
		_source_paths(directory, paths)
	paths.sort()
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	for source in paths:
		hash.update(source.to_utf8_buffer())
		hash.update(FileAccess.get_file_as_bytes(source))
	return hash.finish().hex_encode() if not paths.is_empty() else "unavailable-export"


static func _source_paths(directory: String, paths: Array[String]) -> void:
	for file in DirAccess.get_files_at(directory):
		if file.ends_with(".gd"):
			paths.append(directory.path_join(file))
	for child in DirAccess.get_directories_at(directory):
		_source_paths(directory.path_join(child), paths)
