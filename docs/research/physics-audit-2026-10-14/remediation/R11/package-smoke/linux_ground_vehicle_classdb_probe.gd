extends SceneTree

const NATIVE_CLASS := "OpenRCGroundVehicleNative"
const RECEIPT_PATH := "res://native/ground_vehicle/build-receipt.json"


func _initialize() -> void:
	var class_present := ClassDB.class_exists(NATIVE_CLASS)
	if not class_present:
		printerr("R11_NATIVE_CLASSDB class_present=false class=", NATIVE_CLASS)
		quit(11)
		return

	var native_object: Object = ClassDB.instantiate(NATIVE_CLASS)
	if native_object == null:
		printerr("R11_NATIVE_CLASSDB class_present=true instantiate=false class=", NATIVE_CLASS)
		quit(12)
		return

	var identity: Variant = native_object.call("backend_identity")
	var abi: Variant = native_object.call("abi_info")
	var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(RECEIPT_PATH)) \
		if FileAccess.file_exists(RECEIPT_PATH) else null
	var expected_linux: Dictionary = {}
	if typeof(receipt) == TYPE_DICTIONARY:
		expected_linux = receipt.get("platforms", {}).get("linux", {})
	var binary_path := OS.get_executable_path().get_base_dir().path_join("libopenrc_ground_vehicle.so")
	var binary_sha256 := FileAccess.get_sha256(binary_path) if FileAccess.file_exists(binary_path) else ""
	var identity_ok: bool = (
		typeof(identity) == TYPE_DICTIONARY
		and identity.get("backend", "") == "native"
		and identity.get("backend_version", "") == expected_linux.get("backend_version", "")
		and identity.get("abi_version", -1) == expected_linux.get("abi_version", -2)
		and identity.get("solver_version", "") == expected_linux.get("solver_version", "")
		and identity.get("binary_sha256", "") == expected_linux.get("binary_sha256", "")
		and identity.get("binary_sha256", "") == binary_sha256
	)
	var abi_ok: bool = (
		typeof(abi) == TYPE_DICTIONARY
		and abi.get("float_bytes", -1) == 8
		and abi.get("ieee754", false) == true
		and abi.get("solver", "") == expected_linux.get("backend_version", "")
	)
	var report := {
		"class_present": class_present,
		"class_name": NATIVE_CLASS,
		"executable": OS.get_executable_path(),
		"binary_path": binary_path,
		"binary_sha256": binary_sha256,
		"identity": identity,
		"abi": abi,
		"receipt_linux": expected_linux,
		"identity_matches_receipt_and_sidecar": identity_ok,
		"abi_is_float64_ieee754": abi_ok,
		"passed": identity_ok and abi_ok,
	}
	print("R11_NATIVE_CLASSDB ", JSON.stringify(report, "", true, true))
	quit(0 if report.passed else 13)
