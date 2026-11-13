## DT-MAC: explicit launch parsing and the session's immutable admission choice.
extends SceneTree

const Main := preload("res://main.gd")
const Session := preload("res://sim/flight_session.gd")
const Simulation := preload("res://sim/simulation.gd")
const Qualification := preload("res://tools/native_qualification.gd")
const Reader := preload("res://tools/flight_log_cli.gd")
const StageHarness := preload("res://tests/test_native_stage.gd")
const SessionHarness := preload("res://tests/test_native_session.gd")
const ReplayHarness := preload("res://tests/test_native_replay.gd")

var checks := 0
var failures := 0


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)


func _initialize() -> void:
	var absent := Main._experimental_native_macos_option({})
	check("ordinary launch stays disabled", absent.ok and not absent.enabled)
	for value: Variant in [true, false, "true", "false"]:
		var result := Main._experimental_native_macos_option({"experimental-native-macos": value})
		var expected: bool = value if typeof(value) == TYPE_BOOL else value == "true"
		check("explicit valid value %s" % str(value), result.ok and result.enabled == expected)
	for value: Variant in [null, 1, "yes", "1", "", [], {}]:
		var result := Main._experimental_native_macos_option({"experimental-native-macos": value})
		check("malformed value %s" % str(value), not result.ok and not result.enabled)
	var session := Session.new()
	check("low-level session default disabled", not session.experimental_native_macos)
	check("low-level automatic default disabled", not session.automatic_native_macos)
	session.automatic_native_macos = true
	check("automatic choice before setup", session.automatic_native_macos)
	session.experimental_native_macos = true
	check("explicit choice before setup", session.experimental_native_macos)
	var sim := Simulation.new()
	session.sim = sim
	session.experimental_native_macos = false
	check("live session cannot change admission", session.experimental_native_macos)
	session.automatic_native_macos = false
	check("live session cannot change automatic choice", session.automatic_native_macos)
	session.sim = null
	sim.free()
	session.free()
	test_qualification_options()
	test_replay_options()
	test_harness_setters()
	print("MAC_LAUNCH_POLICY %d checks, %d failed" % [checks, failures])
	quit(0 if failures == 0 else 1)


func test_qualification_options() -> void:
	for mode: String in ["session", "stage", "lifecycle", "replay"]:
		var args := PackedStringArray(["--native-qualification=" + mode])
		if mode == "session":
			args.append_array(PackedStringArray(["--physics-backend=native", "--output=/tmp/report.json"]))
		var absent := Qualification._parse_options(args, "macOS")
		check(mode + " defaults to no opt-in", absent.ok and not absent.experimental_native_macos)
		for value: String in ["true", "false"]:
			var with_flag := args.duplicate()
			with_flag.append("--experimental-native-macos=" + value)
			var parsed := Qualification._parse_options(with_flag, "macOS")
			check(mode + " explicit " + value, parsed.ok and parsed.experimental_native_macos == (value == "true"))
		for value: String in ["", "1", "yes", "TRUE"]:
			var invalid := args.duplicate()
			invalid.append("--experimental-native-macos=" + value)
			check(mode + " rejects invalid " + value, not Qualification._parse_options(invalid, "macOS").ok)
		var duplicate := args.duplicate()
		duplicate.append_array(PackedStringArray(["--experimental-native-macos=true", "--experimental-native-macos=false"]))
		check(mode + " rejects duplicate option", not Qualification._parse_options(duplicate, "macOS").ok)
		var extra := args.duplicate()
		extra.append("--script=other.gd")
		check(mode + " rejects arbitrary script", not Qualification._parse_options(extra, "macOS").ok)
	for mode: String in ["helicopter", "helicopter-radio"]:
		var args := PackedStringArray(["--native-qualification=" + mode])
		check(mode + " explicitly refused on Mac", not Qualification._parse_options(args, "macOS").ok)
		check(mode + " still permitted on Linux", Qualification._parse_options(args, "Linux").ok)
		args.append("--experimental-native-macos=true")
		check(mode + " rejects fixed-wing option on Linux", not Qualification._parse_options(args, "Linux").ok)
	check("qualification requires session backend and output", not Qualification._parse_options(
		PackedStringArray(["--native-qualification=session"]), "macOS").ok)
	check("qualification rejects malformed bare option", not Qualification._parse_options(
		PackedStringArray(["--native-qualification=stage", "--experimental-native-macos"]), "macOS").ok)


func test_replay_options() -> void:
	var absent := Reader._experimental_native_macos_option(PackedStringArray())
	check("replay defaults to no opt-in", absent.ok and not absent.enabled and not absent.present)
	for value: String in ["true", "false"]:
		var parsed := Reader._experimental_native_macos_option(PackedStringArray(["--experimental-native-macos=" + value]))
		check("replay explicit " + value, parsed.ok and parsed.present and parsed.enabled == (value == "true"))
	for invalid: PackedStringArray in [PackedStringArray(["--experimental-native-macos"]),
			PackedStringArray(["--experimental-native-macos=1"]),
			PackedStringArray(["experimental-native-macos=true"]),
			PackedStringArray(["--experimental-native-macos=true", "--experimental-native-macos=false"])]:
		check("replay rejects malformed opt-in " + str(invalid), not Reader._experimental_native_macos_option(invalid).ok)


func test_harness_setters() -> void:
	for script: Script in [StageHarness, SessionHarness, ReplayHarness]:
		var harness: Object = script.new()
		check("qualification harness defaults off", harness.get("_experimental_native_macos") == false)
		harness.call("set_experimental_native_macos", true)
		check("qualification harness accepts opt-in before initialize", harness.get("_experimental_native_macos") == true)
		harness.call("set_experimental_native_macos", false)
		check("qualification harness accepts explicit false", harness.get("_experimental_native_macos") == false)
		harness.call("set_experimental_native_macos", true)
		harness.set("_initialization_started", true)
		harness.call("set_experimental_native_macos", false)
		check("qualification harness freezes choice at initialize", harness.get("_experimental_native_macos") == true)
		harness.free()
