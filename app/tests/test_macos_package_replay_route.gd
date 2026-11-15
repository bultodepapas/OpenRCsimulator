## Portable routing checks. Admission itself remains in the real stage loader.
extends SceneTree

const Reader := preload("res://tools/flight_log_cli.gd")
const PackageAdmission := preload("res://sim/native_macos_package_admission.gd")
var checks := 0
var failures := 0


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("MAC_PACKAGE_REPLAY_ROUTE failed: " + label)


func _initialize() -> void:
	var route := Reader._macos_native_replay_route
	check(route.call("macOS", "arm64", true, "", "macos-arm64-native-bundle-v1", "native"),
		"packaged native identity selects automatic admission path")
	check(route.call("macOS", "arm64", false, "", "source-tree-v1", "native"),
		"source-editor native path remains selected")
	for values: Array in [
		["macOS", "arm64", true, "", "source-tree-v1", "native"],
		["macOS", "arm64", false, "", "macos-arm64-native-bundle-v1", "native"],
		["macOS", "arm64", true, "", "macos-reference-bundle-v1", "gdscript_reference"],
		["macOS", "arm64", true, "candidate.json", "macos-arm64-native-bundle-v1", "native"],
		["macOS", "x86_64", true, "", "macos-arm64-native-bundle-v1", "native"],
		["Linux", "arm64", true, "", "macos-arm64-native-bundle-v1", "native"],
		["macOS", "arm64", true, "", "macos-arm64-native-bundle-v1", "gdscript_reference"]]:
		check(not route.callv(values), "other route is not automatic: " + str(values))
	check(not PackageAdmission.ENABLED, "route selection cannot enable package admission")
	print("MAC_PACKAGE_REPLAY_ROUTE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
