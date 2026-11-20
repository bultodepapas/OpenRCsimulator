# TELEM-02: who may collect. The admission policy truth table, the interactive-route predicate, release/endpoint
# configuration and the consent file (fail-closed loading, atomic replacement, no restorable older grant).
# Run: godot --headless --path . --script res://tests/test_telemetry_admission.gd
extends SceneTree

const Policy := preload("res://telemetry/telemetry_policy.gd")
const Release := preload("res://telemetry/telemetry_release.gd")
const Store := preload("res://telemetry/telemetry_consent_store.gd")
const Contract := preload("res://telemetry/telemetry_contract.gd")
const BuildInfo := preload("res://app_state/build_info.gd")

const PATH := "user://test_telemetry_consent.cfg"
const RELEASE := {"ok": true, "notice": "2026-11-18", "endpoint": "https://telemetry.example.org/v1/batches"}

var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	_policy()
	_route()
	_release()
	_store()
	print("all telemetry admission checks passed" if _failures == 0 else "%d failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _facts(overrides: Dictionary) -> Dictionary:
	var facts := {"release": RELEASE, "interactive": true, "locale": "en", "choice": "enabled",
		"notice": "2026-11-18", "suspended": false}
	facts.merge(overrides, true)
	return facts


func _policy() -> void:
	var table := [
		[{}, "on", "granted"],
		[{"choice": "unset"}, "ask", "unset"],
		[{"choice": "disabled"}, "off", "declined"],
		[{"choice": "unreadable"}, "off", "unreadable"],
		[{"choice": "maybe"}, "off", "unknown"],
		[{"notice": "2025-01-01"}, "ask", "new_notice"],
		[{"locale": "es"}, "on", "granted"],
		[{"locale": "es_AR"}, "on", "granted"],
		[{"locale": "de"}, "off", "locale"],
		[{"locale": "zh_Hans"}, "off", "locale"],
		[{"locale": 7}, "off", "locale"],
		[{"suspended": true}, "off", "suspended"],
		[{"suspended": null}, "off", "suspended"],
		[{"interactive": false}, "unavailable", "route"],
		[{"interactive": 1}, "unavailable", "route"],
		[{"release": {"ok": false}}, "unavailable", "build"],
		[{"release": {"ok": "true"}}, "unavailable", "build"],
		[{"release": null}, "unavailable", "build"],
	]
	for row: Array in table:
		var got := Policy.evaluate(_facts(row[0]))
		_check("policy %s -> %s/%s" % [str(row[0]), row[1], row[2]], got.state == row[1] and got.reason == row[2], str(got))
	_check("policy refuses a non-dictionary", Policy.evaluate("on").state == Policy.UNAVAILABLE)
	_check("only English and Spanish notices are reviewed", Policy.REVIEWED_NOTICE_LOCALES == ["en", "es"])


func _route() -> void:
	var none := PackedStringArray()
	_check("an ordinary launch is interactive", Policy.interactive_route(true, none, none, "Windows", true, {}))
	_check("Finder's -psn_ argument is ignored", Policy.interactive_route(true, none, PackedStringArray(["-psn_0_12345"]), "macOS", true, {}))
	_check("the renderer guard's Compatibility restart is still the player's session", Policy.interactive_route(true,
		none, PackedStringArray(["--rendering-method", "gl_compatibility"]), "Windows", true, {}))
	_check("a renderer and driver shortcut is still the player's session", Policy.interactive_route(true, none,
		PackedStringArray(["--rendering-driver", "vulkan", "--rendering-method", "forward_plus"]), "Linux", true, {}))
	var refused := [
		["no Home", [false, none, none, "Windows", true, {}]],
		["user arguments", [true, PackedStringArray(["--quick-flight"]), none, "Windows", true, {}]],
		["engine arguments", [true, none, PackedStringArray(["--write-movie", "x.avi"]), "Windows", true, {}]],
		["an unknown renderer", [true, none, PackedStringArray(["--rendering-method", "custom"]), "Windows", true, {}]],
		["a renderer option without a value", [true, none, PackedStringArray(["--rendering-method"]), "Windows", true, {}]],
		["a renderer plus another argument", [true, none, PackedStringArray(["--rendering-method", "mobile", "--headless"]),
			"Windows", true, {}]],
		["a renderer value on its own", [true, none, PackedStringArray(["gl_compatibility"]), "Windows", true, {}]],
		["headless", [true, none, none, "headless", true, {}]],
		["a test settings file", [true, none, none, "Windows", false, {}]],
		["the debug bridge", [true, none, none, "Windows", true, {"OPENRC_DEBUG_BRIDGE": "1"}]],
		["the package probe", [true, none, none, "Windows", true, {"OPENRC_PACKAGE_DEFAULT_PROBE": "1"}]],
		["GOD TEST", [true, none, none, "Windows", true, {"OPENRC_GODTEST_CONFIG": "x"}]],
		["a local force-off", [true, none, none, "Windows", true, {"OPENRC_TELEMETRY_DISABLE": "1"}]],
		["mistyped facts", [1, none, none, "Windows", true, {}]],
	]
	for row: Array in refused:
		var a: Array = row[1]
		_check("route refused: " + row[0], not Policy.interactive_route(a[0], a[1], a[2], a[3], a[4], a[5]))


func _build(describe: String, dirty := false) -> Dictionary:
	return {"source": "export", "dirty": dirty, "parsed": BuildInfo.parse_describe(describe, "0.2.8")}


func _release() -> void:
	var packed := {"format": Release.FORMAT, "endpoint": "https://telemetry.example.org/v1/batches",
		"operator": "OpenRC Simulator project", "contact": "privacy@example.org"}
	var ok := Release.from_export(_build("v0.2.9"), packed, true, "4.8")
	_check("an approved stable release is available", ok.ok and ok.release_id == "v0.2.9" and ok.channel == "stable"
		and ok.notice == Contract.NOTICE_VERSION and ok.endpoint == packed.endpoint, str(ok))
	var preview := Release.from_export(_build("v0.3.0-beta.1"), packed, true, "4.8")
	_check("a prerelease tag is the preview channel", preview.ok and preview.channel == "preview", str(preview))
	var cases := [
		["development", Release.from_export({"source": "development"}, packed, true, "4.8"), "development"],
		["debug template", Release.from_export(_build("v0.2.9"), packed, false, "4.8"), "debug_template"],
		["another engine", Release.from_export(_build("v0.2.9"), packed, true, "4.9"), "engine"],
		["commits after the tag", Release.from_export(_build("v0.2.9-3-gabc1234"), packed, true, "4.8"), "unreleased"],
		["a dirty tree", Release.from_export(_build("v0.2.9-dirty", true), packed, true, "4.8"), "unreleased"],
		["a manual export", Release.from_export(_build("export-manual"), packed, true, "4.8"), "unreleased"],
		["no packed configuration", Release.from_export(_build("v0.2.9"), null, true, "4.8"), "not_configured"],
	]
	for row: Array in cases:
		_check("release refused: " + row[0], row[1].ok == false and row[1].reason == row[2], str(row[1]))
	for field: String in ["endpoint", "operator", "contact"]:
		var broken := packed.duplicate()
		broken[field] = ""
		_check("release refused without " + field, not Release.from_export(_build("v0.2.9"), broken, true, "4.8").ok)
	var endpoints := [
		["https://t.example.org/v1/batches", false, true],
		["https://t.example.org:8443/v1/batches", false, true],
		["http://t.example.org/v1/batches", false, false],
		["https://t.example.org/v1/batches?x=1", false, false],
		["https://user@t.example.org/v1/batches", false, false],
		["https://t.example.org", false, false],
		["https://127.0.0.1/v1/batches", false, false],
		["http://127.0.0.1:8787/v1/batches", true, true],
		["http://localhost:8787/v1/batches", true, true],
		["http://10.0.0.5:8787/v1/batches", true, false],
		["https://127.0.0.1:8787/v1/batches", true, false],
	]
	for row: Array in endpoints:
		_check("endpoint %s (loopback %s) -> %s" % row, Release.valid_endpoint(row[0], row[1]) == row[2])
	var qualification := Release.qualification("http://127.0.0.1:8787/v1/batches", "")
	_check("qualification uses a loopback receiver and a placeholder release", qualification.ok and qualification.qualification
		and qualification.release_id == "v0.0.0" and qualification.channel == "preview", str(qualification))
	_check("qualification refuses a remote origin", not Release.qualification("http://198.51.100.7/v1/batches", "").ok)
	_check("this source run offers no production telemetry", not Release.current().ok or Release.current().qualification == true)


func _store() -> void:
	_remove()
	_check("no file means not asked yet", Store.load_choice(PATH).choice == "unset")
	_check("saving a grant", Store.save_choice("enabled", "2026-11-18", PATH) == OK)
	var loaded := Store.load_choice(PATH)
	_check("the grant reads back with its notice", loaded.choice == "enabled" and loaded.notice == "2026-11-18", str(loaded))
	_check("a decline replaces the grant", Store.save_choice("disabled", "2026-11-18", PATH) == OK
		and Store.load_choice(PATH).choice == "disabled")
	_check("no temporary or backup file remains", not FileAccess.file_exists(PATH + ".tmp")
		and _siblings().size() == 1, str(_siblings()))
	_check("an invalid choice is refused", Store.save_choice("yes", "2026-11-18", PATH) == ERR_INVALID_PARAMETER
		and Store.load_choice(PATH).choice == "disabled")
	var corrupt := [
		"not a config [",
		"[telemetry]\nformat=\"openrc-telemetry-consent v2\"\nchoice=\"enabled\"\nnotice=\"2026-11-18\"\n",
		"[telemetry]\nformat=\"openrc-telemetry-consent v1\"\nchoice=\"enabled\"\nnotice=\"2026-11-18\"\nplayer=\"x\"\n",
		"[telemetry]\nformat=\"openrc-telemetry-consent v1\"\nchoice=true\nnotice=\"2026-11-18\"\n",
		"[telemetry]\nformat=\"openrc-telemetry-consent v1\"\nchoice=\"enabled\"\nnotice=\"2026-11-18\"\n[other]\nx=1\n",
		"",
	]
	for text: String in corrupt:
		var file := FileAccess.open(PATH, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		_check("unreadable file fails closed: %s" % text.substr(0, 40).c_escape(), Store.load_choice(PATH).choice == "unreadable")
	_check("a grant replaces an unreadable file", Store.save_choice("enabled", "2026-11-18", PATH) == OK
		and Store.load_choice(PATH).choice == "enabled")
	# A decline whose new file cannot be written must not leave the earlier grant behind (the next launch asks).
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(PATH + ".tmp")) # the temporary file cannot be created
	_check("a failed decline reports its error", Store.save_choice("disabled", "2026-11-18", PATH) != OK)
	_check("a failed decline never leaves the earlier grant", Store.load_choice(PATH).choice == "unset", str(Store.load_choice(PATH)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH + ".tmp"))
	_check("a grant can be saved again afterwards", Store.save_choice("enabled", "2026-11-18", PATH) == OK)
	var unwritable := "user://no_such_dir_telemetry/consent.cfg"
	_check("an unwritable location reports an error", Store.save_choice("disabled", "2026-11-18", unwritable) != OK
		and Store.load_choice(unwritable).choice == "unset")
	_remove()


func _siblings() -> PackedStringArray:
	var out := PackedStringArray()
	for name: String in DirAccess.get_files_at("user://"):
		if name.begins_with("test_telemetry_consent"):
			out.append(name)
	return out


func _remove() -> void:
	for name: String in _siblings():
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + name))
