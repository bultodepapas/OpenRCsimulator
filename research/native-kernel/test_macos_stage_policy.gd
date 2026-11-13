## Portable, loader-free tests for the experimental Mac stage admission policy.
## Mac hardware must separately exercise the real pre-load checks and native oracles.
extends SceneTree

const NativeStage := preload("res://sim/native_stage.gd")
const NativePackage := preload("res://app_state/native_package.gd")
const Flight := preload("res://sim/flight_session.gd")
const Helicopter := preload("res://sim/helicopter_flight_session.gd")
const HEADER := "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" \
	+ "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n" \
	+ "<plist version=\"1.0\"><dict>"
const BUILD := "<key>ProductBuildVersion</key><string>26A434</string>"
const VERSION := "<key>ProductVersion</key><string>27.0.1</string>"
const FOOTER := "</dict></plist>"

var checks := 0
var failures := 0


func check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label)


func _initialize() -> void:
	call_deferred("run_all")


func fixture() -> Dictionary:
	var digest := "a".repeat(64)
	return {
		format = NativeStage.RECEIPT_FORMAT, backend = NativeStage.BACKEND_NATIVE,
		backend_version = NativeStage.BACKEND_VERSION, abi_version = NativeStage.ABI_VERSION,
		platforms = {"macos": {
			platform = "macos", architecture = "arm64", backend = NativeStage.BACKEND_NATIVE,
			backend_version = NativeStage.BACKEND_VERSION, abi_version = NativeStage.ABI_VERSION,
			qualification_scope = NativeStage.MACOS_QUALIFICATION_SCOPE,
			runtime_os_version = "27.0.1", runtime_os_build = "26A434", engine_version = "fixture",
			engine_sha256 = digest, binary_sha256 = digest, source_sha256 = digest, lock_sha256 = digest,
			mirrored_sources = {"app/physics/aero.gd": digest},
		}},
	}


func test_receipt() -> void:
	var good := fixture()
	check("Mac receipt accepted", not NativeStage._platform_row(good, "macos").is_empty())
	var invalid_rows := [
		["platform", "linux"], ["architecture", "x86_64"], ["backend", "reference"],
		["qualification_scope", ""], ["qualification_scope", "other"],
		["runtime_os_version", ""], ["runtime_os_version", 27],
		["runtime_os_build", ""], ["runtime_os_build", null],
		["binary_sha256", "bad"], ["source_sha256", "g".repeat(64)], ["lock_sha256", ""],
		["mirrored_sources", {}], ["mirrored_sources", {"app/../bad.gd": "a".repeat(64)}],
	]
	for pair: Array in invalid_rows:
		var bad := good.duplicate(true)
		bad.platforms.macos[pair[0]] = pair[1]
		check("reject row " + str(pair), NativeStage._platform_row(bad, "macos").is_empty())
	var json_numbers := good.duplicate(true)
	json_numbers.abi_version = 2.0
	json_numbers.platforms.macos.abi_version = 2.0
	check("JSON ABI number accepted", not NativeStage._platform_row(json_numbers, "macos").is_empty())
	json_numbers.platforms.macos.abi_version = 3
	check("different ABI refused", NativeStage._platform_row(json_numbers, "macos").is_empty())
	var package := {ok = true, kind = "macos-arm64-native-bundle-v1", manifest = {native_receipt = good}}
	var row: Dictionary = good.platforms.macos
	check("packaged Mac source boundary accepts admitted row", NativeStage._macos_package_source_error(package, row).is_empty())
	var altered := package.duplicate(true)
	altered.manifest.native_receipt.platforms.macos.binary_sha256 = "b".repeat(64)
	check("packaged Mac source boundary rejects changed row", not NativeStage._macos_package_source_error(altered, row).is_empty())
	altered = package.duplicate(true)
	altered.kind = "macos-reference-bundle-v1"
	check("packaged Mac source boundary rejects reference kind", not NativeStage._macos_package_source_error(altered, row).is_empty())
	check("packaged Mac source boundary rejects failed identity", not NativeStage._macos_package_source_error({ok = false, reason = "fixture"}, row).is_empty())
	check("packaged Mac source boundary rejects missing manifest", not NativeStage._macos_package_source_error({ok = true}, row).is_empty())


func test_system_version() -> void:
	var valid := HEADER + BUILD + "<key>ProductName</key><string>macOS</string>" + VERSION + FOOTER
	var actual := NativeStage._parse_macos_system_version(valid.to_utf8_buffer())
	check("observed XML shape parses", actual == {version = "27.0.1", build = "26A434"})
	var row: Dictionary = fixture().platforms.macos
	check("matching OS version and build accepted", NativeStage._macos_os_identity_error(row, actual).is_empty())
	var changed := row.duplicate()
	changed.runtime_os_build = "26A435"
	check("different OS build refused", not NativeStage._macos_os_identity_error(changed, actual).is_empty())
	changed = row.duplicate()
	changed.runtime_os_version = "27.0.2"
	check("different OS version refused", not NativeStage._macos_os_identity_error(changed, actual).is_empty())
	var invalid := [
		"", "bplist00random", HEADER + BUILD + FOOTER, HEADER + VERSION + FOOTER,
		HEADER + BUILD + BUILD + VERSION + FOOTER,
		HEADER + BUILD + "<key>ProductVersion</key><integer>27</integer>" + FOOTER,
		HEADER + BUILD + "<key>ProductVersion</key><string>27.bad</string>" + FOOTER,
		HEADER + BUILD + VERSION + "</dict>",
		HEADER + BUILD + VERSION + "</plist></dict>",
		HEADER + BUILD + VERSION + "<key>orphan</key>" + FOOTER,
		"x".repeat(NativeStage.MACOS_SYSTEM_VERSION_MAX_BYTES + 1),
	]
	for text: String in invalid:
		check("refuse invalid XML " + str(text.length()), NativeStage._parse_macos_system_version(text.to_utf8_buffer()).is_empty())
	check("empty parsed identity refused", not NativeStage._macos_os_identity_error(row, {}).is_empty())


func test_platform_and_sessions() -> void:
	check("Linux target retained", NativeStage._source_platform_for("Linux", "x86_64") == "linux")
	check("Windows target retained", NativeStage._source_platform_for("Windows", "x86_64") == "windows")
	check("Mac ARM64 target", NativeStage._source_platform_for("macOS", "arm64") == "macos")
	check("Mac x86 refused", NativeStage._source_platform_for("macOS", "x86_64").is_empty())
	check("unknown ARM refused", NativeStage._source_platform_for("Linux", "arm64").is_empty())
	check("null session refused", not NativeStage._macos_session_error(null).is_empty())
	var other := Node.new()
	check("other session refused", not NativeStage._macos_session_error(other).is_empty())
	other.free()
	var helicopter: Node = Helicopter.new()
	check("helicopter refused", not NativeStage._macos_session_error(helicopter).is_empty())
	helicopter.free()
	var fixed: Node = Flight.new()
	check("fixed wing defaults off", not NativeStage._macos_session_error(fixed).is_empty())
	fixed.experimental_native_macos = true
	check("explicit fixed-wing opt-in accepted", NativeStage._macos_session_error(fixed).is_empty())
	fixed.free()


func test_packaged_descriptor() -> void:
	var bundle := "/fixture/OpenRC.app"
	var descriptor := bundle.path_join(NativePackage.MAC_NATIVE_DESCRIPTOR)
	var library := bundle.path_join(NativePackage.MAC_NATIVE_LIBRARY)
	var relative := "../Frameworks/libopenrc_native_kernel.dylib"
	check("packaged descriptor is an app resource", NativePackage.MAC_NATIVE_DESCRIPTOR ==
		"Contents/Resources/openrc_native_kernel_macos.gdextension")
	check("packaged descriptor selects the verified Frameworks library",
		descriptor.get_base_dir().path_join(relative).simplify_path() == library
		and NativeStage.EXPECTED_MACOS_PACKAGE_DESCRIPTOR.contains('macos.arm64 = "' + relative + '"'))
	check("source descriptor keeps its existing resource library path",
		NativeStage.EXPECTED_MACOS_DESCRIPTOR.contains('macos.arm64 = "res://native/kernel/libopenrc_native_kernel.dylib"'))


func test_cache_gate() -> void:
	NativeStage._library_checked = false
	NativeStage._library_error = ""
	var denied := NativeStage._library_status_for_os("macOS", false)
	check("default diagnostics refused before load", not denied.ok and not NativeStage._library_checked)
	# Model a successfully qualified load without instantiating the native class.
	NativeStage._library_checked = true
	NativeStage._library_error = ""
	check("explicit call sees cached success", NativeStage._library_status_for_os("macOS", true).ok)
	check("default call still refuses after success", not NativeStage._library_status_for_os("macOS", false).ok)
	check("default refusal did not poison success", NativeStage._library_status_for_os("macOS", true).ok)
	NativeStage._library_error = "fixture failure"
	check("default denial independent of cached failure", not NativeStage._library_status_for_os("macOS", false).ok)
	check("cached failure preserved", NativeStage._library_status_for_os("macOS", true).reason == "fixture failure")
	NativeStage._library_checked = false
	NativeStage._library_error = ""


func run_all() -> void:
	test_receipt()
	test_system_version()
	test_platform_and_sessions()
	test_packaged_descriptor()
	test_cache_gate()
	if failures:
		printerr("Mac native stage policy: %d/%d checks failed" % [failures, checks])
		quit(1)
	else:
		print("Mac native stage policy: %d checks passed" % checks)
		quit(0)
