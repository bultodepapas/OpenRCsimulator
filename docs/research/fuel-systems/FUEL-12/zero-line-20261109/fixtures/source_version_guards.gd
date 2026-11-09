extends SceneTree
const Stage := preload("res://sim/native_stage.gd")
const BASELINE := "9f05a9b8803ff98c833b79e962085340d03887a1c0c0d7ff6b923aeba1dde7a6"
var failures := 0
func check(label: String, condition: bool) -> void:
 print(("ok " if condition else "FAIL "), label)
 if not condition: failures += 1
func _initialize() -> void:
 var path := "app/physics/glow/flight.gd"
 var current := FileAccess.get_sha256("res://physics/glow/flight.gd")
 check("candidate differs from recorded pre-fix source", current.length() == 64 and current != BASELINE)
 check("current source hash accepted", Stage._source_error({mirrored_sources = {path: current}}).is_empty())
 var reason: String = Stage._source_error({mirrored_sources = {path: BASELINE}})
 check("pre-fix mirrored source refused", reason == "mirrored source differs from the verified native build: " + path)
 check("empty mirrored-source roster refused", not Stage._source_error({mirrored_sources = {}}).is_empty())
 var row := {backend_version = Stage.BACKEND_VERSION, abi_version = Stage.ABI_VERSION,
  binary_sha256 = current, source_sha256 = current, lock_sha256 = current, mirrored_sources = {path: current}}
 var receipt := {format = Stage.RECEIPT_FORMAT, backend = Stage.BACKEND_NATIVE,
  backend_version = Stage.BACKEND_VERSION, abi_version = Stage.ABI_VERSION, platforms = {linux = row}}
 check("current backend and ABI admitted", not Stage._platform_row(receipt).is_empty())
 var wrong_version: Dictionary = receipt.duplicate(true)
 wrong_version.backend_version = "old-native-backend"
 check("wrong backend version refused", Stage._platform_row(wrong_version).is_empty())
 var wrong_abi: Dictionary = receipt.duplicate(true)
 wrong_abi.abi_version = Stage.ABI_VERSION + 1
 check("wrong ABI refused", Stage._platform_row(wrong_abi).is_empty())
 print("SOURCE_VERSION_GUARDS checks=7 failures=", failures)
 quit(0 if failures == 0 else 1)
