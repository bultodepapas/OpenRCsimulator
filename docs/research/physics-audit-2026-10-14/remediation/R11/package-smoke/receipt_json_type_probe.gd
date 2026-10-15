extends SceneTree

const RECEIPT_PATH := "/mnt/c/DEVELOPMENT/OpenRCsimulator/app/native/ground_vehicle/build-receipt.json"


func _initialize() -> void:
	var receipt_text := FileAccess.get_file_as_string(RECEIPT_PATH)
	var receipt: Variant = JSON.parse_string(receipt_text)
	if typeof(receipt) != TYPE_DICTIONARY:
		push_error("Merged native receipt did not parse as a Dictionary")
		quit(1)
		return
	var platforms: Variant = receipt.get("platforms", {})
	var linux_row: Variant = platforms.get("linux", {}) if typeof(platforms) == TYPE_DICTIONARY else {}
	var windows_row: Variant = platforms.get("windows", {}) if typeof(platforms) == TYPE_DICTIONARY else {}
	var result := {
		"receipt_path": RECEIPT_PATH,
		"receipt_sha256": FileAccess.get_sha256(RECEIPT_PATH),
		"root_abi_value": receipt.get("abi_version"),
		"root_abi_typeof": typeof(receipt.get("abi_version")),
		"linux_abi_value": linux_row.get("abi_version") if typeof(linux_row) == TYPE_DICTIONARY else null,
		"linux_abi_typeof": typeof(linux_row.get("abi_version")) if typeof(linux_row) == TYPE_DICTIONARY else -1,
		"windows_abi_value": windows_row.get("abi_version") if typeof(windows_row) == TYPE_DICTIONARY else null,
		"windows_abi_typeof": typeof(windows_row.get("abi_version")) if typeof(windows_row) == TYPE_DICTIONARY else -1,
		"type_int": TYPE_INT,
		"type_float": TYPE_FLOAT,
	}
	print("R11_RECEIPT_JSON_TYPE ", JSON.stringify(result, "", true, true))
	quit(0)
