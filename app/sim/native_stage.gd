## Native continuous aircraft stages. Discrete tick, event and collision policies
## remain owned by each session. A source-bound receipt and exact preparation
## guards are required before a native evaluator replaces its reference.
## Linux/Windows x86_64; macOS ARM64 uses a qualified source default or explicit research opt-in.
## The owner retains this helper for the installed callback lifetime.
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
const MacosAdmission := preload("res://sim/native_macos_admission.gd")
const MacosDomain := preload("res://sim/native_macos_domain.gd")

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
## NK-4: the Windows source-tree installation (MinGW-w64 build with the engine's msvcrt/libmingwex math). Its own
## descriptor and receipt live beside the Linux ones, so neither installation can replace the other's identity.
const WINDOWS_EXTENSION_PATH := "res://native/kernel/openrc_native_kernel_windows.gdextension"
const WINDOWS_RECEIPT_PATH := "res://native/kernel/build-receipt-windows.json"
const WINDOWS_LIBRARY_FILE := "openrc_native_kernel.dll"
const EXPECTED_WINDOWS_DESCRIPTOR := (
	"; NK-4 native stage, installed by research/native-kernel/build_windows.py --install-app.\n"
	+ "; .gdignore prevents discovery; app/sim/native_stage.gd loads it after receipt checks.\n"
	+ "[configuration]\n"
	+ "entry_symbol = \"openrc_native_kernel_library_init\"\n"
	+ "compatibility_minimum = \"4.7\"\n"
	+ "reloadable = false\n\n"
	+ "[libraries]\n"
	+ "windows.x86_64 = \"res://native/kernel/openrc_native_kernel.dll\"\n"
)
const MACOS_EXTENSION_PATH := "res://native/kernel/openrc_native_kernel_macos.gdextension"
const MACOS_RECEIPT_PATH := "res://native/kernel/build-receipt-macos.json"
const MACOS_LIBRARY_FILE := "libopenrc_native_kernel.dylib"
const MACOS_QUALIFICATION_SCOPE := "macos-arm64-fixed-wing-experimental-v1"
const MACOS_SYSTEM_VERSION_PATH := "/System/Library/CoreServices/SystemVersion.plist"
const MACOS_SYSTEM_VERSION_MAX_BYTES := 65536
const EXPECTED_MACOS_DESCRIPTOR := (
	"; DT-MAC native stage, installed by research/native-kernel/build_macos.py --install-app.\n"
	+ "; .gdignore prevents discovery; app/sim/native_stage.gd loads it after receipt checks.\n"
	+ "[configuration]\n"
	+ "entry_symbol = \"openrc_native_kernel_library_init\"\n"
	+ "compatibility_minimum = \"4.7\"\n"
	+ "reloadable = false\n\n"
	+ "[libraries]\n"
	+ "macos.arm64 = \"res://native/kernel/libopenrc_native_kernel.dylib\"\n"
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
const EXPECTED_MACOS_PACKAGE_DESCRIPTOR := (
	"; DT-MAC packaged stage; loaded explicitly after embedded identity verification.\n"
	+ "[configuration]\n"
	+ "entry_symbol = \"openrc_native_kernel_library_init\"\n"
	+ "compatibility_minimum = \"4.7\"\n"
	+ "reloadable = false\n\n"
	+ "[libraries]\n"
	+ "macos.arm64 = \"../Frameworks/libopenrc_native_kernel.dylib\"\n"
)

static var _library_checked := false
static var _library_error := ""
static var _receipt_row: Dictionary = {}
static var _macos_loaded_receipt_sha256 := ""

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
var _macos_domain_context: Dictionary = {}
var _macos_automatic_marker: Dictionary = {}



## {ok, reason}: the library is installed, matches its receipt and loaded (checked once per process).
static func library_status(allow_experimental_macos := false) -> Dictionary:
	return _library_status_for_os(OS.get_name(), allow_experimental_macos)


## The opt-in refusal is per request, never a process-wide cached failure or success.
static func _library_status_for_os(os_name: String, allow_experimental_macos: bool) -> Dictionary:
	if os_name == "macOS" and not allow_experimental_macos:
		return {ok = false, reason = "native stage on macOS requires explicit experimental fixed-wing opt-in"}
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


## Once per tick, no native decoding or large-context serialization. Automatic Mac admission
## also checks a bounded start identity and the frozen context's packed leaves. Detect bypassed setters and
## in-place model edits before the prepared native equations can read stale data. Normal setters rebuild once.
func configuration_matches(session: Node) -> bool:
	return owns_stage(session) and _native.weather_guard_matches(session) \
		and _native.configuration_guard_matches(session) and _macos_domain_matches(session)


func _macos_domain_matches(session: Node) -> bool:
	if _macos_domain_context.is_empty(): return true
	return MacosDomain.guard_matches(session, _macos_domain_context.guard) \
		and _native.macos_domain_guard_matches(session._collision_world, session._runway_field)


## A refused start restores the accepted selection as well as the physical endpoint.
func restore_macos_selection_after_refusal(session: Node) -> void:
	if _macos_domain_context.is_empty(): return
	session.start_choice = _macos_domain_context.guard.start_choice
	session.trim_throttle = _macos_domain_context.guard.trim_throttle


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
	_macos_domain_context = {}
	_macos_automatic_marker = {}
	var is_macos := OS.get_name() == "macOS"
	if is_macos:
		var session_error := _macos_session_error(session)
		if not session_error.is_empty(): return _refuse(session_error)
		if not session.experimental_native_macos:
			var marker := MacosAdmission.read_marker()
			_macos_automatic_marker = marker
			var selected := MacosDomain.screen_session(session, true)
			if not MacosAdmission.selection_allowed(marker, selected, session.soft_hull_contacts):
				return _refuse("Mac native default has no qualification for this stock selection")
			_macos_domain_context = MacosDomain.freeze_for_session(session, true)
			if not _macos_domain_context.get("ok", false):
				return _refuse(str(_macos_domain_context.get("reason", "Mac stock context refused")))
		else:
			# Exercise the same context guard in explicitly selected stock research flights.
			# Unsupported experiments retain their explicit research scope, never automatic admission.
			var screened := MacosDomain.screen_session(session, true)
			if screened.get("ok", false):
				_macos_domain_context = MacosDomain.freeze_for_session(session, true)
				if not _macos_domain_context.get("ok", false):
					return _refuse("screened Mac stock context could not be frozen")
	var status := library_status(is_macos)
	if not status.ok: return _refuse(status.reason)
	if not _macos_automatic_marker.is_empty():
		var cached_error := MacosAdmission.loaded_identity_error(_macos_automatic_marker, _macos_loaded_receipt_sha256, _receipt_row)
		if not cached_error.is_empty(): return _refuse(cached_error)
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
	if not _macos_domain_context.is_empty():
		if not _native.has_method("prepare_macos_domain_guard"):
			return _refuse("Mac stock packed context guard is unavailable")
		var domain_guard: Dictionary = _native.prepare_macos_domain_guard(_macos_domain_context.world, _macos_domain_context.field)
		if not domain_guard.get("ok", false):
			return _refuse("Mac stock packed context guard refused")
		_macos_domain_context["native_guard"] = domain_guard.duplicate(true)
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
	if not _macos_domain_context.is_empty():
		session._collision_world = _macos_domain_context.world
		session._runway_field = _macos_domain_context.field
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


## Reject before consulting or populating the process-wide library cache.
static func _macos_session_error(session: Node) -> String:
	if not is_instance_valid(session) or session.get_script() != load("res://sim/flight_session.gd"):
		return "native stage on macOS supports experimental fixed-wing sessions only"
	var opt_in: Variant = session.get("experimental_native_macos")
	if typeof(opt_in) == TYPE_BOOL and opt_in: return ""
	if session.get("automatic_native_macos") == true and not MacosAdmission.read_marker().is_empty(): return ""
	return "Mac native default qualification is unavailable; explicit experimental fixed-wing opt-in remains available"


## Return the supported source/debug process target; unknown targets refuse.
static func _source_platform() -> String:
	return _source_platform_for(OS.get_name(), Engine.get_architecture_name())


static func _source_platform_for(os_name: String, architecture: String) -> String:
	if architecture == "x86_64":
		match os_name:
			"Linux": return "linux"
			"Windows": return "windows"
	if os_name == "macOS" and architecture == "arm64":
		return "macos"
	return ""


static func _load_library() -> String:
	var platform := _source_platform()
	if platform.is_empty():
		return "native stage: Linux/Windows x86_64 or experimental macOS ARM64 source only"
	if OS.has_feature("template_release"):
		if platform == "macos": return _load_macos_package_library()
		return _load_package_library() if platform == "linux" else "native stage packages: Linux x86_64 or experimental macOS ARM64 only"
	var extension_path := EXTENSION_PATH
	var receipt_path := RECEIPT_PATH
	if platform == "windows":
		extension_path = WINDOWS_EXTENSION_PATH
		receipt_path = WINDOWS_RECEIPT_PATH
	elif platform == "macos":
		extension_path = MACOS_EXTENSION_PATH
		receipt_path = MACOS_RECEIPT_PATH
	if not FileAccess.file_exists(extension_path) or not FileAccess.file_exists(receipt_path):
		return "native stage library not installed"
	var receipt := JSON.new()
	if receipt.parse(FileAccess.get_file_as_string(receipt_path)) != OK:
		return "native stage receipt is malformed or for another backend version or ABI"
	var row := _platform_row(receipt.data, platform)
	if row.is_empty():
		return "native stage receipt is malformed or for another backend version or ABI"
	if platform == "macos":
		var os_error := _macos_runtime_os_error(row)
		if not os_error.is_empty(): return os_error
	if row.get("engine_version") != Engine.get_version_info().string \
			or str(row.get("engine_sha256", "")).length() != 64 \
			or FileAccess.get_sha256(OS.get_executable_path()) != row.engine_sha256:
		return "native stage requires the exact verified Godot executable; reinstall after verification"
	var descriptor_error := _descriptor_error(platform)
	if not descriptor_error.is_empty():
		return descriptor_error
	if not _binary_matches(str(row.binary_sha256), platform):
		return "native stage binary does not match its receipt"
	var source_error := _source_error(row)
	if not source_error.is_empty():
		return source_error
	var load_error := _initialize_library(extension_path, row)
	if platform == "macos" and load_error.is_empty():
		_macos_loaded_receipt_sha256 = FileAccess.get_sha256(receipt_path)
	return load_error


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


static func _load_macos_package_library() -> String:
	var package := NativePackage.mac_native_identity(OS.get_executable_path(), Engine.get_architecture_name(),
		OS.get_cmdline_args() + OS.get_cmdline_user_args())
	if not package.get("ok", false): return str(package.get("reason", "Mac native package unavailable"))
	var row := _platform_row(package.manifest.native_receipt, "macos")
	if row.is_empty() or row.get("engine_version") != Engine.get_version_info().string:
		return "Mac native package has no valid verified ARM64 receipt"
	var os_error := _macos_runtime_os_error(row)
	if not os_error.is_empty(): return os_error
	var bundle := OS.get_executable_path().get_base_dir().get_base_dir().get_base_dir()
	var descriptor := bundle.path_join(NativePackage.MAC_NATIVE_DESCRIPTOR)
	var library := bundle.path_join(NativePackage.MAC_NATIVE_LIBRARY)
	if package.descriptor_path != descriptor or package.library_path != library \
			or FileAccess.get_file_as_string(descriptor) != EXPECTED_MACOS_PACKAGE_DESCRIPTOR:
		return "Mac native package descriptor differs from the verified loader contract"
	if FileAccess.get_sha256(library) != row.binary_sha256:
		return "Mac native package binary differs from its embedded identity"
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
static func _descriptor_error(platform := "linux") -> String:
	var path := WINDOWS_EXTENSION_PATH if platform == "windows" else EXTENSION_PATH
	var expected := EXPECTED_WINDOWS_DESCRIPTOR if platform == "windows" else EXPECTED_DESCRIPTOR
	if platform == "macos":
		path = MACOS_EXTENSION_PATH
		expected = EXPECTED_MACOS_DESCRIPTOR
	return "" if FileAccess.get_file_as_string(path) == expected \
			else "native stage descriptor differs from the verified loader contract"


static func _platform_row(value: Variant, platform := "linux") -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY or value.get("format") != RECEIPT_FORMAT or value.get("backend") != BACKEND_NATIVE \
			or value.get("backend_version") != BACKEND_VERSION or not _abi_matches(value.get("abi_version")) \
			or typeof(value.get("platforms")) != TYPE_DICTIONARY:
		return {}
	var row: Variant = value.platforms.get(platform)
	if typeof(row) != TYPE_DICTIONARY or row.get("backend_version") != BACKEND_VERSION \
			or not _abi_matches(row.get("abi_version")) or typeof(row.get("mirrored_sources")) != TYPE_DICTIONARY:
		return {}
	if platform == "windows" and (row.get("platform") != "windows" or row.get("architecture") != "x86_64"):
		return {}
	if platform == "macos" and (row.get("platform") != "macos" or row.get("architecture") != "arm64" \
			or row.get("backend") != BACKEND_NATIVE or row.get("qualification_scope") != MACOS_QUALIFICATION_SCOPE \
			or typeof(row.get("runtime_os_version")) != TYPE_STRING or str(row.runtime_os_version).is_empty() \
			or typeof(row.get("runtime_os_build")) != TYPE_STRING or str(row.runtime_os_build).is_empty()):
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


## The observed SystemVersion.plist is XML. Unknown formats fail closed; no child process is started.
static func _macos_runtime_os_error(row: Dictionary) -> String:
	var file := FileAccess.open(MACOS_SYSTEM_VERSION_PATH, FileAccess.READ)
	if file == null:
		return "native stage cannot read the macOS system version"
	var size := file.get_length()
	if size <= 0 or size > MACOS_SYSTEM_VERSION_MAX_BYTES:
		return "native stage cannot read the macOS system version"
	var bytes := file.get_buffer(size)
	if bytes.size() != size:
		return "native stage cannot read the macOS system version"
	return _macos_os_identity_error(row, _parse_macos_system_version(bytes))


static func _macos_os_identity_error(row: Dictionary, actual: Dictionary) -> String:
	if actual.is_empty():
		return "native stage cannot parse the macOS system version"
	if row.get("runtime_os_version") != actual.get("version") or row.get("runtime_os_build") != actual.get("build"):
		return "native stage requires the exact verified macOS version and build"
	return ""


## Parse only a bounded XML plist with one top-level ProductVersion and ProductBuildVersion string.
## Product values have deliberately narrow ASCII forms; unknown forms require new qualification.
static func _parse_macos_system_version(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty() or bytes.size() > MACOS_SYSTEM_VERSION_MAX_BYTES:
		return {}
	var parser := XMLParser.new()
	if parser.open_buffer(bytes) != OK:
		return {}
	var stack: Array[String] = []
	var root_seen := false
	var dict_seen := false
	var expecting_key := true
	var reading_key := false
	var reading_target := false
	var current_key := ""
	var content := ""
	var targets := {}
	var result := parser.read()
	while result == OK:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				var name := parser.get_node_name()
				if stack.is_empty():
					if root_seen or name != "plist": return {}
					root_seen = true
				elif stack == ["plist"]:
					if dict_seen or name != "dict": return {}
					dict_seen = true
				elif stack == ["plist", "dict"]:
					if expecting_key:
						if name != "key" or parser.is_empty(): return {}
						reading_key = true
						content = ""
					else:
						if name not in ["string", "integer", "real", "true", "false", "data", "date", "array", "dict"]:
							return {}
						if current_key in ["ProductVersion", "ProductBuildVersion"]:
							if name != "string" or parser.is_empty(): return {}
							reading_target = true
							content = ""
						expecting_key = true
				elif reading_key or reading_target:
					return {}
				if parser.is_empty():
					if name == "plist" or (name == "dict" and stack == ["plist"]): return {}
				else:
					stack.append(name)
			XMLParser.NODE_ELEMENT_END:
				var name := parser.get_node_name()
				if stack.is_empty() or stack.back() != name: return {}
				stack.pop_back()
				if reading_key and stack == ["plist", "dict"]:
					reading_key = false
					current_key = content.strip_edges()
					if current_key.is_empty(): return {}
					if current_key in ["ProductVersion", "ProductBuildVersion"] and targets.has(current_key): return {}
					expecting_key = false
				elif reading_target and stack == ["plist", "dict"]:
					reading_target = false
					targets[current_key] = content
			XMLParser.NODE_TEXT, XMLParser.NODE_CDATA:
				var data := parser.get_node_data()
				if reading_key or reading_target:
					content += data
				elif (stack.is_empty() or stack == ["plist"] or stack == ["plist", "dict"]) \
						and not data.strip_edges().is_empty():
					return {}
			XMLParser.NODE_UNKNOWN:
				if root_seen: return {}
		result = parser.read()
	if result != ERR_FILE_EOF or not root_seen or not dict_seen or not stack.is_empty() or not expecting_key \
			or reading_key or reading_target or targets.size() != 2:
		return {}
	var version: String = targets.get("ProductVersion", "")
	var build: String = targets.get("ProductBuildVersion", "")
	var pieces := version.split(".", true)
	if version.length() > 32 or pieces.size() < 2 or pieces.size() > 3 or build.is_empty() or build.length() > 32:
		return {}
	for piece: String in pieces:
		if piece.is_empty() or not _ascii_digits(piece): return {}
	for i in build.length():
		var code := build.unicode_at(i)
		if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122)):
			return {}
	return {version = version, build = build}


static func _ascii_digits(value: String) -> bool:
	for i in value.length():
		var code := value.unicode_at(i)
		if code < 48 or code > 57: return false
	return true


static func _binary_matches(expected_sha256: String, platform := "linux") -> bool:
	var filename := WINDOWS_LIBRARY_FILE if platform == "windows" else LIBRARY_FILE
	if platform == "macos": filename = MACOS_LIBRARY_FILE
	var path := "res://native/kernel/" + filename
	return FileAccess.file_exists(path) and FileAccess.get_sha256(path) == expected_sha256


## Every GDScript file the port mirrors must still hash as it did when the oracles verified this binary.
static func _mirrored_source_error() -> String:
	if OS.has_feature("template_release"):
		# The embedded manifest was checked against the oracle-qualified sources at export. Compiled resources
		# are bound by the exact final executable hash, rather than pretending loose .gd files still exist.
		if OS.get_name() == "macOS":
			var mac_package := NativePackage.mac_native_identity(OS.get_executable_path(), Engine.get_architecture_name(),
				OS.get_cmdline_args() + OS.get_cmdline_user_args())
			return _macos_package_source_error(mac_package, _receipt_row)
		var package := NativePackage.identity()
		return "" if package.ok else str(package.reason)
	return _source_error(_receipt_row)


## Revalidate the exact admitted row at a packaged reset/restore boundary.
static func _macos_package_source_error(package: Dictionary, expected: Dictionary) -> String:
	if typeof(package.get("ok")) != TYPE_BOOL or not package.ok:
		return str(package.get("reason", "Mac native package identity unavailable"))
	if package.get("kind") != NativePackage.MAC_NATIVE_IDENTITY_KIND or typeof(package.get("manifest")) != TYPE_DICTIONARY:
		return "Mac native package identity kind or manifest differs"
	var row := _platform_row(package.manifest.get("native_receipt"), "macos")
	return "" if not row.is_empty() and row == expected else "Mac native package receipt changed after admission"


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
