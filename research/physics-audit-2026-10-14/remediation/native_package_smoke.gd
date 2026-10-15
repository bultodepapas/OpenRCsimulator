extends SceneTree
## Host-matched packaged GDExtension identity smoke; invoke with an exported --main-pack.
## The executable must have the exact host library beside it for GDExtension path fallback.

const VehicleDynamics := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const NATIVE_CLASS := "OpenRCGroundVehicleNative"
const RECEIPT_PATH := "res://native/ground_vehicle/build-receipt.json"
const IDENTITY_FIELDS := [
	"backend", "backend_version", "abi_version", "solver_version",
	"source_sha256", "toolchain_sha256", "binary_sha256",
]
const PLATFORM_KEYS := ["linux", "windows"]


func _initialize() -> void:
	var report := _inspect_host_package()
	print("R11_NATIVE_PACKAGE_SMOKE ", JSON.stringify(report, "", true, true))
	quit(0 if bool(report.get("passed", false)) else 1)


func _inspect_host_package() -> Dictionary:
	var errors := PackedStringArray()
	var platform := _platform_key()
	if platform.is_empty():
		errors.append("native smoke supports Linux and Windows hosts only")
	var binary_name := "libopenrc_ground_vehicle.so" if platform == "linux" else "openrc_ground_vehicle.dll"
	var executable := OS.get_executable_path()
	var sidecar_path := executable.get_base_dir().path_join(binary_name)
	var sidecar_sha256 := FileAccess.get_sha256(sidecar_path) if FileAccess.file_exists(sidecar_path) else ""

	var receipt: Dictionary = {}
	var receipt_file := FileAccess.open(RECEIPT_PATH, FileAccess.READ)
	if receipt_file == null:
		errors.append("pack does not contain native build receipt")
	else:
		var parsed: Variant = JSON.parse_string(receipt_file.get_as_text())
		receipt_file.close()
		if typeof(parsed) == TYPE_DICTIONARY:
			receipt = parsed
		else:
			errors.append("native build receipt is not a JSON object")

	var expected: Dictionary = {}
	var platforms: Variant = receipt.get("platforms", {})
	if typeof(platforms) == TYPE_DICTIONARY:
		var platform_row: Variant = platforms.get(platform, {})
		if typeof(platform_row) == TYPE_DICTIONARY:
			expected = platform_row
	if expected.is_empty():
		errors.append("receipt has no row for host platform: " + platform)

	var envelope_ok: bool = receipt.get("format", "") == "openrc-ground-vehicle-native-receipt" \
		and receipt.get("backend", "") == "native" \
		and typeof(receipt.get("backend_version")) == TYPE_STRING \
		and not str(receipt.get("backend_version", "")).is_empty() \
		and _abi_version_is_one(receipt.get("abi_version")) \
		and typeof(receipt.get("solver_version")) == TYPE_STRING \
		and not str(receipt.get("solver_version", "")).is_empty()
	if not envelope_ok:
		errors.append("receipt envelope does not identify a supported native ABI and solver")
	var platform_rows_ok := _platform_rows_are_consistent(receipt)
	if not platform_rows_ok:
		errors.append("Linux and Windows receipt rows are absent, malformed, or disagree on source/law identity")
	var row_ok: bool = expected.get("platform", "") == platform \
		and expected.get("architecture", "") == "x86_64" \
		and expected.get("backend", "") == receipt.get("backend", "") \
		and expected.get("backend_version", "") == receipt.get("backend_version", "") \
		and _abi_version_is_one(expected.get("abi_version")) \
		and _abi_version_is_one(receipt.get("abi_version")) \
		and expected.get("solver_version", "") == receipt.get("solver_version", "")
	if not row_ok:
		errors.append("host platform row does not match receipt envelope")

	var class_present := ClassDB.class_exists(NATIVE_CLASS)
	var native_identity: Dictionary = {}
	var abi: Dictionary = {}
	if not class_present:
		errors.append("native ClassDB class is unavailable")
	else:
		var native_object: Object = ClassDB.instantiate(NATIVE_CLASS)
		if native_object == null:
			errors.append("native ClassDB class could not be instantiated")
		else:
			if not native_object.has_method("backend_identity") or not native_object.has_method("abi_info"):
				errors.append("native ClassDB object lacks identity/ABI methods")
			else:
				var identity_value: Variant = native_object.call("backend_identity")
				var abi_value: Variant = native_object.call("abi_info")
				if typeof(identity_value) == TYPE_DICTIONARY:
					native_identity = identity_value
				else:
					errors.append("native backend identity is not a dictionary")
				if typeof(abi_value) == TYPE_DICTIONARY:
					abi = abi_value
				else:
					errors.append("native ABI report is not a dictionary")
			# OpenRCGroundVehicleNative is RefCounted; this local reference releases at scope exit.

	var selected_identity: Dictionary = VehicleDynamics.backend_identity()
	if not _identity_matches_receipt(selected_identity, expected):
		errors.append("VehicleDynamics did not select the exact host-native receipt identity")
	if not _identity_matches_receipt(native_identity, expected):
		errors.append("ClassDB identity does not match the host receipt")
	if native_identity != selected_identity:
		errors.append("VehicleDynamics identity differs from the instantiated native class identity")
	if sidecar_sha256.is_empty() or sidecar_sha256 != str(expected.get("binary_sha256", "")):
		errors.append("executable-adjacent native sidecar is missing or differs from its receipt hash")
	var abi_ok: bool = abi.get("float_bytes", -1) == 8 \
		and abi.get("ieee754", false) == true \
		and _abi_version_is_one(abi.get("abi_version")) \
		and _abi_version_is_one(expected.get("abi_version")) \
		and abi.get("solver", "") == expected.get("backend_version", "") \
		and abi.get("solver_version", "") == expected.get("solver_version", "")
	if not abi_ok:
		errors.append("native ABI report is not the receipt-matched float64 IEEE-754 ABI")

	return {
		"format": "openrc-r11-host-native-package-smoke-v1",
		"scope": "host-matched native package smoke; not cross-platform target execution",
		"godot": Engine.get_version_info().string,
		"host_platform": platform,
		"executable": executable,
		"sidecar_path": sidecar_path,
		"sidecar_sha256": sidecar_sha256,
		"receipt_path": RECEIPT_PATH,
		"receipt_host_row": expected,
		"platform_rows_consistent": platform_rows_ok,
		"class_present": class_present,
		"native_identity": native_identity,
		"selected_identity": selected_identity,
		"abi": abi,
		"abi_is_float64_ieee754": abi_ok,
		"errors": errors,
		"passed": errors.is_empty(),
	}


func _identity_matches_receipt(identity: Dictionary, expected: Dictionary) -> bool:
	if identity.is_empty() or expected.is_empty():
		return false
	for key: String in IDENTITY_FIELDS:
		if key == "abi_version":
			if not _abi_version_is_one(identity.get(key)) or not _abi_version_is_one(expected.get(key)):
				return false
			continue
		if identity.get(key) != expected.get(key):
			return false
	return _sha256_is_valid(identity.get("source_sha256")) \
		and _sha256_is_valid(identity.get("toolchain_sha256")) \
		and _sha256_is_valid(identity.get("binary_sha256"))


func _platform_rows_are_consistent(receipt: Dictionary) -> bool:
	var platforms: Variant = receipt.get("platforms", {})
	if typeof(platforms) != TYPE_DICTIONARY:
		return false
	var source_hash := ""
	if receipt.has("source_sha256"):
		var declared_source: Variant = receipt.get("source_sha256")
		if not _sha256_is_valid(declared_source):
			return false
		source_hash = str(declared_source)
	for platform: String in PLATFORM_KEYS:
		var row_value: Variant = platforms.get(platform)
		if typeof(row_value) != TYPE_DICTIONARY:
			return false
		var row: Dictionary = row_value
		if row.get("platform", "") != platform or row.get("architecture", "") != "x86_64" \
				or row.get("backend", "") != receipt.get("backend", "") \
				or row.get("backend_version", "") != receipt.get("backend_version", "") \
				or not _abi_version_is_one(row.get("abi_version")) \
				or not _abi_version_is_one(receipt.get("abi_version")) \
				or row.get("solver_version", "") != receipt.get("solver_version", "") \
				or typeof(row.get("toolchain")) != TYPE_DICTIONARY:
			return false
		var row_source := str(row.get("source_sha256", ""))
		if not _sha256_is_valid(row_source) \
				or not _sha256_is_valid(row.get("toolchain_sha256")) \
				or not _sha256_is_valid(row.get("binary_sha256")):
			return false
		if source_hash.is_empty():
			source_hash = row_source
		elif row_source != source_hash:
			return false
	return true


func _abi_version_is_one(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return int(value) == 1
	if typeof(value) == TYPE_FLOAT:
		var numeric_value := float(value)
		return is_finite(numeric_value) and numeric_value == 1.0
	return false


func _sha256_is_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var digest := str(value)
	if digest.length() != 64 or digest.to_lower() != digest:
		return false
	for character in digest:
		if not str(character) in "0123456789abcdef":
			return false
	return true


func _platform_key() -> String:
	match OS.get_name():
		"Linux":
			return "linux"
		"Windows":
			return "windows"
		_:
			return ""
