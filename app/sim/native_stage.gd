## Native continuous aircraft stages. Discrete tick, event and collision policies
## remain owned by each session. A source-bound receipt and exact preparation
## guards are required before a native evaluator replaces its reference.
## Linux x86_64; the owner retains this helper for the installed callback lifetime.
extends RefCounted

const Aero := preload("res://physics/aero.gd")
const Wheels := preload("res://physics/ground_wheels.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const LakeSurface := preload("res://physics/lake_surface.gd")
const Turbine := preload("res://physics/turbine.gd")
const NativeConfiguration := preload("res://sim/native/native_configuration.gd")
const WeatherAdapter := preload("res://sim/native/weather_adapter.gd")
const ElectricAdapter := preload("res://sim/native/electric_stage_adapter.gd")
const LiquidAdapter := preload("res://sim/native/liquid_stage_adapter.gd")
const GlowAdapter := preload("res://sim/native/glow_stage_adapter.gd")
const PrescribedAdapter := preload("res://sim/native/prescribed_stage_adapter.gd")
const HelicopterAdapter := preload("res://sim/native/helicopter_stage_adapter.gd")
const StageConfig := preload("res://sim/native/stage_config.gd")
const NativePackage := preload("res://app_state/native_package.gd")

const EXTENSION_PATH := "res://native/kernel/openrc_native_kernel.gdextension"
const RECEIPT_PATH := "res://native/kernel/build-receipt.json"
const LIBRARY_FILE := "libopenrc_native_kernel.so"
const RECEIPT_FORMAT := "openrc-native-kernel-receipt"
const BACKEND_REFERENCE := "gdscript_reference"
const BACKEND_NATIVE := "native"
const BACKEND_VERSION := "openrc-native-kernel-stage-v2"
const ABI_VERSION := 2
const NATIVE_CLASS := "OpenRCNativeKernel"
const REFERENCE_STAGE_METHOD := &"_wheel_evaluate"
# Match research/native-kernel/build.py: no feature override or dependency may select unchecked code.
const EXPECTED_DESCRIPTOR := (
	"; NK-3 native stage, installed by research/native-kernel/build.py --install-app.\n"
	+ "; .gdignore prevents discovery; app/sim/native_stage.gd loads it after receipt checks.\n"
	+ "[configuration]\n"
	+ "entry_symbol = \"openrc_native_kernel_library_init\"\n"
	+ "compatibility_minimum = \"4.7\"\n"
	+ "reloadable = false\n\n"
	+ "[libraries]\n"
	+ "linux.x86_64 = \"res://native/kernel/libopenrc_native_kernel.so\"\n"
)
const EXPECTED_PACKAGE_DESCRIPTOR := (
	"; NK-3 packaged stage; loaded explicitly after embedded identity verification.\n"
	+ "[configuration]\n"
	+ "entry_symbol = \"openrc_native_kernel_library_init\"\n"
	+ "compatibility_minimum = \"4.7\"\n"
	+ "reloadable = false\n\n"
	+ "[libraries]\n"
	+ "linux.x86_64 = \"libopenrc_native_kernel.so\"\n"
)

static var _library_checked := false
static var _library_error := ""
static var _receipt_row: Dictionary = {}

var reason := "not prepared"
var _native: Object = null
var _prepared := false
var _installed := false
var _reference_stage := Callable()
var _reference_pre_tick := Callable()
var _reference_loads := Callable()
var _reference_rotor := Callable()
var _body_only := false
var _installed_model: RefCounted = null
var _config := {}
var _configuration_identity: RefCounted
var _weather_identity: RefCounted
var _family := ""



## {ok, reason}: the library is installed, matches its receipt and loaded (checked once per process).
static func library_status() -> Dictionary:
	if not _library_checked:
		_library_checked = true
		_library_error = _load_library()
	return {ok = _library_error.is_empty(), reason = _library_error}


static func reference_identity() -> Dictionary:
	return {backend = BACKEND_REFERENCE}


## Session identity of the stage backend: the reference unless this helper has a native stage installed.
func backend_identity() -> Dictionary:
	if not _installed:
		return reference_identity()
	return {backend = BACKEND_NATIVE, backend_version = BACKEND_VERSION, abi_version = ABI_VERSION,
		binary_sha256 = str(_receipt_row.binary_sha256), source_sha256 = str(_receipt_row.source_sha256),
		lock_sha256 = str(_receipt_row.lock_sha256)}


## One-line form for checkpoint configuration hashes and trace metadata.
func identity_text() -> String:
	if not _installed:
		return BACKEND_REFERENCE
	return "%s/%s/abi%d/%s" % [BACKEND_NATIVE, BACKEND_VERSION, ABI_VERSION, str(_receipt_row.binary_sha256)]


func is_installed() -> bool:
	return _installed


func owns_stage(session: Node) -> bool:
	if not _installed or session.sim.model != _installed_model: return false
	if _body_only:
		return not _installed_model.stage.is_valid() and _installed_model.loads == Callable(_native, "body_loads") \
			and _installed_model.rotor_momentum == Callable(_native, "body_rotor")
	return _installed_model.stage == Callable(_native, "stage")


## Detach without changing this helper. A transaction can restore its pointer and original model on refusal.
func restore_reference_callback(session: Node) -> void:
	if owns_stage(session):
		if _body_only:
			_installed_model.loads = _reference_loads
			_installed_model.rotor_momentum = _reference_rotor
		else:
			_installed_model.stage = _reference_stage
		if _reference_pre_tick.is_valid():
			_installed_model.pre_tick = _reference_pre_tick


## Once per tick, no serialization, hashing or native decoding. Detect bypassed configuration setters and
## in-place model edits before the prepared native equations can read stale data. Normal setters rebuild once.
func configuration_matches(session: Node) -> bool:
	return owns_stage(session) and _native.weather_guard_matches(session) \
		and _native.configuration_guard_matches(session)


## A refused transaction may restore equal values into new containers. Rebind
## their identities against the original immutable preparation snapshot; never
## recapture the live values as a new configuration.
func restore_configuration_guard(session: Node) -> bool:
	if not owns_stage(session) or not _native.weather_guard_matches(session):
		return false
	var installed: Callable = _installed_model.stage
	_installed_model.stage = _configuration_identity.reference_stage
	var restored: Dictionary = _native.prepare_configuration_guard(session, _configuration_identity)
	_installed_model.stage = installed
	return restored.get("ok", false) and configuration_matches(session)


func last_failure() -> String:
	if _native == null: return reason
	return str(_native.heli_last_failure()) if _family == "helicopter" else reason


func stage_stats() -> Dictionary:
	return _native.stage_stats() if _native != null else {stage_calls = 0, context_calls = 0}

## Decode the session's committed aircraft, field, lake, hull, layout and weather into the native stage.
## {ok, reason}; a refusal leaves the session untouched and records `reason`.
func prepare(session: Node) -> Dictionary:
	_prepared = false
	if _installed: return _refuse("uninstall before preparing again")
	var status := library_status()
	if not status.ok: return _refuse(status.reason)
	var source_error := _mirrored_source_error()
	if not source_error.is_empty(): return _refuse(source_error)
	if session == null or session.get("sim") == null or not session.aircraft.get("ok", false):
		return _refuse("no committed aircraft and simulation")
	if _native == null: _native = ClassDB.instantiate(NATIVE_CLASS)
	var identity: Dictionary = _native.backend_identity()
	if identity.get("backend_version") != BACKEND_VERSION or identity.get("abi_version") != ABI_VERSION \
			or identity.get("aero_law") != Aero.LOADS_LAW or identity.get("rolling_law") != Wheels.ROLLING_LAW:
		return _refuse("native contract differs from the loaded application")
	var boundary: Dictionary
	var result: Dictionary
	if session.get_script() == load("res://sim/helicopter_flight_session.gd"):
		_family = "helicopter"
		boundary = NativeConfiguration.prepare_helicopter(session)
		if not boundary.get("ok", false): return _refuse(str(boundary.get("reason", "helicopter configuration refused")))
		result = _native.prepare_heli_stage(boundary.snapshot, boundary.weather)
		_config = boundary.snapshot
	elif session.get_script() == load("res://sim/flight_session.gd"):
		var builder: Callable
		if session.glow_is_active():
			_family = "glow"
			builder = GlowAdapter.config_for
		elif session.liquid_fuel_is_active():
			_family = "liquid"
			builder = LiquidAdapter.config_for
		elif Propulsion.is_electric(session.aircraft.model.propulsion):
			_family = "electric"
			builder = ElectricAdapter.config_for
		elif not PrescribedAdapter.kind_for(session).is_empty():
			_family = "prescribed"
			builder = PrescribedAdapter.config_for
		else:
			_family = "wheel"
			builder = WeatherAdapter.config_for
		boundary = NativeConfiguration.prepare(session, builder)
		if not boundary.get("ok", false): return _refuse(str(boundary.get("reason", "aircraft configuration refused")))
		result = _native.prepare_stage(boundary.config)
		_config = boundary.config
	else:
		return _refuse("unsupported session owner")
	if not result.get("ok", false): return _refuse("native stage refused: " + str(result.get("error", "invalid prepared source")))
	_configuration_identity = boundary.identity
	_weather_identity = boundary.weather_identity
	var weather_guard: Dictionary = _native.prepare_weather_guard(session, _weather_identity)
	var configuration_guard: Dictionary = _native.prepare_configuration_guard(session, _configuration_identity)
	if not weather_guard.get("ok", false) or not configuration_guard.get("ok", false):
		return _refuse("native preparation identity changed before installation")
	_prepared = true
	reason = ""
	return {ok = true, reason = ""}

## Swap the session's reference callbacks for the prepared native evaluator. Returns the previous stage Callable,
## which may be empty on a successful body-only/split installation; use is_installed() to check success.
## A session that owns this helper (`session._native_stage == self`) calls tick_context() from `_kernel_pre_step`;
## for any other helper (research, tests, an unpatched session) `pre_tick` is wrapped to hand over the same context.
func install(session: Node) -> Callable:
	if not _prepared or _installed: return Callable()
	var model: RefCounted = session.sim.model
	if model.stage != _configuration_identity.reference_stage \
			or not _native.weather_guard_matches(session) or not _native.configuration_guard_matches(session):
		reason = "prepared reference owner or configuration changed before installation"
		return Callable()
	_reference_stage = model.stage
	_body_only = session.sim.continuous.is_empty()
	_reference_loads = model.loads
	_reference_rotor = model.rotor_momentum
	if session.get("_native_stage") != self:
		_reference_pre_tick = model.pre_tick
		var inner: Callable = _reference_pre_tick
		model.pre_tick = func(aux: PackedFloat64Array, inputs: PackedFloat64Array, dt: float) -> Variant:
			if not configuration_matches(session): return PackedFloat64Array()
			var next: Variant = inner.call(aux, inputs, dt) if inner.is_valid() else aux
			if next is PackedFloat64Array and not tick_context(session, next, inputs): return PackedFloat64Array()
			return next
	if _body_only:
		model.loads = Callable(_native, "body_loads")
		model.rotor_momentum = Callable(_native, "body_rotor")
	if _body_only or _reference_pre_tick.is_valid():
		# Capture every retained callback before the stage swap. Body-only native
		# loads and rotor callbacks replace their reference owners here.
		_configuration_identity.vehicle_values = NativeConfiguration._capture(model, NativeConfiguration.VEHICLE_FIELDS)
		var rebound: Dictionary = _native.prepare_configuration_guard(session, _configuration_identity)
		if not rebound.get("ok", false):
			if _reference_pre_tick.is_valid(): model.pre_tick = _reference_pre_tick
			if _body_only:
				model.loads = _reference_loads
				model.rotor_momentum = _reference_rotor
			_reference_pre_tick = Callable()
			reason = "cannot retain the native tick handoff owner"
			return Callable()
	if not _body_only: model.stage = Callable(_native, "stage")
	_installed_model = model
	_installed = true
	return _reference_stage

## Restore the reference stage (and pre_tick if it was wrapped). Returns the stage Callable that was in place.
func uninstall(session: Node) -> Callable:
	if not _installed:
		return Callable()
	var model: RefCounted = session.sim.model
	var previous: Callable = model.stage
	restore_reference_callback(session)
	_reference_stage = Callable()
	_reference_pre_tick = Callable()
	_reference_loads = Callable()
	_reference_rotor = Callable()
	_body_only = false
	_installed = false
	_prepared = false
	_installed_model = null
	reason = "uninstalled"
	return previous


## Per-tick context, once per kernel tick after the pre-step: the aux the kernel installs, the inputs, the
## session's own deflections for that aux and the tick's time. No-op while the reference stage is in use.
func tick_context(session: Node, aux: PackedFloat64Array, inputs: PackedFloat64Array, time_now := NAN) -> bool:
	if not _installed: return false
	var at: float = session.sim.time() if is_nan(time_now) else time_now
	var accepted := false
	match _family:
		"helicopter": accepted = _native.set_heli_tick_context(HelicopterAdapter.tick(session, inputs))
		"electric": accepted = ElectricAdapter.set_context(session, _native, aux, inputs, at)
		"liquid": accepted = LiquidAdapter.set_context(session, _native, aux, inputs, at)
		"glow": accepted = GlowAdapter.set_context(session, _native, aux, inputs, at)
		"prescribed": accepted = PrescribedAdapter.set_context(session, _native, aux, inputs, at)
		"wheel":
			var d: Dictionary = session._deflections(aux)
			accepted = _native.set_tick_context(aux, inputs,
				PackedFloat64Array([d.elevator, d.aileron_right, d.aileron_left, d.rudder, d.get("flap", 0.0)]), at)
	if not accepted: reason = "native tick context refused"
	return accepted

## prepare_stage() input: committed model, gear, surface table, lake, prepared hull, layout, density and
## ground-effect reach and explicit capability flags; family adapters add their validated source snapshots.
static func config_for(session: Node) -> Dictionary:
	return StageConfig.config_for(session)


func _refuse(why: String) -> Dictionary:
	reason = why
	return {ok = false, reason = why}


static func _load_library() -> String:
	if OS.get_name() != "Linux" or Engine.get_architecture_name() != "x86_64":
		return "native stage: Linux x86_64 only"
	if OS.has_feature("template_release"):
		return _load_package_library()
	if not FileAccess.file_exists(EXTENSION_PATH) or not FileAccess.file_exists(RECEIPT_PATH):
		return "native stage library not installed"
	var receipt := JSON.new()
	if receipt.parse(FileAccess.get_file_as_string(RECEIPT_PATH)) != OK:
		return "native stage receipt is malformed or for another backend version or ABI"
	var row := _platform_row(receipt.data)
	if row.is_empty():
		return "native stage receipt is malformed or for another backend version or ABI"
	if row.get("engine_version") != Engine.get_version_info().string \
			or str(row.get("engine_sha256", "")).length() != 64 \
			or FileAccess.get_sha256(OS.get_executable_path()) != row.engine_sha256:
		return "native stage requires the exact verified Godot executable; reinstall after verification"
	var descriptor_error := _descriptor_error()
	if not descriptor_error.is_empty():
		return descriptor_error
	if not _binary_matches(str(row.binary_sha256)):
		return "native stage binary does not match its receipt"
	var source_error := _source_error(row)
	if not source_error.is_empty():
		return source_error
	return _initialize_library(EXTENSION_PATH, row)


static func _load_package_library() -> String:
	var package := NativePackage.identity()
	if not package.ok:
		return str(package.reason)
	var row := _platform_row(package.manifest.native_receipt)
	if row.is_empty() or row.get("engine_version") != package.manifest.engine_version:
		return "native package has no valid verified Linux receipt"
	var directory := NativePackage.directory()
	var descriptor := directory.path_join("openrc_native_kernel.gdextension")
	var library := directory.path_join(LIBRARY_FILE)
	if not FileAccess.file_exists(descriptor) or FileAccess.get_file_as_string(descriptor) != EXPECTED_PACKAGE_DESCRIPTOR:
		return "native package descriptor differs from the verified loader contract"
	if not FileAccess.file_exists(library) or FileAccess.get_sha256(library) != row.binary_sha256:
		return "native package binary differs from its embedded identity"
	return _initialize_library(descriptor, row)


static func _initialize_library(descriptor: String, row: Dictionary) -> String:
	# An already loaded extension ran initialization before these checks, and Godot does not identify its loaded
	# binary. Do not select it even if the present files match: restart after removing the stale cache registration.
	if GDExtensionManager.is_extension_loaded(descriptor) or ClassDB.class_exists(NATIVE_CLASS):
		return "native stage was loaded before verification; restart after clearing the cached extension registration"
	var status: int = GDExtensionManager.load_extension(descriptor)
	if status != GDExtensionManager.LOAD_STATUS_OK:
		return "native stage library failed to load (status %d)" % status
	if not ClassDB.class_exists(NATIVE_CLASS):
		return "native stage class is missing after loading"
	var identity: Variant = ClassDB.instantiate(NATIVE_CLASS).call("backend_identity")
	if typeof(identity) != TYPE_DICTIONARY or identity.get("backend") != BACKEND_NATIVE \
			or identity.get("backend_version") != BACKEND_VERSION or not _abi_matches(identity.get("abi_version")):
		return "native stage identity does not match its receipt"
	_receipt_row = row
	return ""


## Only the one checked file may be loaded. Extra feature entries or dependencies could select other code.
static func _descriptor_error() -> String:
	return "" if FileAccess.get_file_as_string(EXTENSION_PATH) == EXPECTED_DESCRIPTOR \
			else "native stage descriptor differs from the verified loader contract"


static func _platform_row(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY or value.get("format") != RECEIPT_FORMAT or value.get("backend") != BACKEND_NATIVE \
			or value.get("backend_version") != BACKEND_VERSION or not _abi_matches(value.get("abi_version")) \
			or typeof(value.get("platforms")) != TYPE_DICTIONARY:
		return {}
	var row: Variant = value.platforms.get("linux")
	if typeof(row) != TYPE_DICTIONARY or row.get("backend_version") != BACKEND_VERSION \
			or not _abi_matches(row.get("abi_version")) or typeof(row.get("mirrored_sources")) != TYPE_DICTIONARY:
		return {}
	for key: String in ["binary_sha256", "source_sha256", "lock_sha256"]:
		var digest: String = str(row.get(key, ""))
		if digest.length() != 64 or not digest.is_valid_hex_number():
			return {}
	if row.mirrored_sources.is_empty():
		return {}
	for source: Variant in row.mirrored_sources:
		if typeof(source) != TYPE_STRING or not source.begins_with("app/"):
			return {}
		var relative: String = source.trim_prefix("app/")
		var components := relative.split("/", true)
		var source_digest: Variant = row.mirrored_sources[source]
		if components.has("") or components.has(".") or components.has("..") or "\\" in relative \
				or typeof(source_digest) != TYPE_STRING or source_digest.length() != 64 \
				or not source_digest.is_valid_hex_number():
			return {}
	return row


static func _abi_matches(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and value == ABI_VERSION


static func _binary_matches(expected_sha256: String) -> bool:
	var path := "res://native/kernel/" + LIBRARY_FILE
	return FileAccess.file_exists(path) and FileAccess.get_sha256(path) == expected_sha256


## Every GDScript file the port mirrors must still hash as it did when the oracles verified this binary.
static func _mirrored_source_error() -> String:
	if OS.has_feature("template_release"):
		# The embedded manifest was checked against the oracle-qualified sources at export. Compiled resources
		# are bound by the exact final executable hash, rather than pretending loose .gd files still exist.
		var package := NativePackage.identity()
		return "" if package.ok else str(package.reason)
	return _source_error(_receipt_row)


static func _source_error(row: Dictionary) -> String:
	var sources: Dictionary = row.get("mirrored_sources", {})
	if sources.is_empty():
		return "native stage receipt lists no mirrored sources"
	for name: String in sources:
		var path := "res://" + name.trim_prefix("app/")
		var actual := FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
		if actual != str(sources[name]):
			return "mirrored source differs from the verified native build: " + name
	return ""
