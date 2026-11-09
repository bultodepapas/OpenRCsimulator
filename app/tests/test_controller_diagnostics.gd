extends SceneTree

const Diagnostics := preload("res://input/controller_diagnostics.gd")
const Data := preload("res://input/input_report_data.gd")
const Profile := preload("res://input/controller_profile.gd")
const Actions := preload("res://input/controller_actions.gd")
const BuildInfo := preload("res://app_state/build_info.gd")
const RadioMenu := preload("res://input/radio_menu.gd")
const RcInput := preload("res://input/rc_input.gd")
const TARGET := "user://controller_diagnostics_test.json"

var checks := 0
var failures := 0


func check(label: String, condition: bool, detail := "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func clean() -> void:
	var path := ProjectSettings.globalize_path(TARGET)
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(path + Diagnostics.LOCK_SUFFIX): DirAccess.remove_absolute(path + Diagnostics.LOCK_SUFFIX)
	if FileAccess.file_exists(path + ".samples"): DirAccess.remove_absolute(path + ".samples")


func _initialize() -> void:
	_run()


func _run() -> void:
	clean()
	var info := {"id": 42, "connected": true, "kind": "radio", "known": false,
		"name": "PRIVATE-NAME-654", "raw_name": "C:/private/NAME-RAW-654", "guid": "GUID-SECRET-654",
		"serial_number": "SERIAL-SECRET-654", "vendor_id": "4617", "product_id": "20308",
		"backend": "SDL3", "transport": "USB", "layout": "advanced", "nested": {"serial": "INFO-NESTED-654"}}
	var profile := Profile.defaults("radio", "radio_custom")
	profile.name = "PROFILE-PRIVATE-654"
	profile.association = {"serial_number": "PROFILE-SERIAL-654", "guid": "PROFILE-GUID-654",
		"legacy_device_key": "C:/private/LEGACY-654", "vendor_id": 4617, "product_id": 20308}
	profile.roll["private_data"] = {"value": "CHANNEL-SECRET-654"}
	profile.actions.pause["extra"] = {"serial": "BINDING-SECRET-654"}
	profile["custom"] = {"nested": ["PROFILE-CUSTOM-654"]}
	profile.aux = {"gear": {"type": "switch", "buttons": [100, 101], "invert": false, "label": "SWITCH-654"}}
	check("valid fixture includes arbitrary private extensions", Profile.validate(profile).ok)
	var collector := Data.new()
	collector.connect_device(42, info, 0)
	collector.motion(42, 0, -0.75, 1)
	collector.motion(42, 0, 0.5, 2)
	collector.button_event(42, 100, true, 3)
	collector.button_event(42, 100, false, 4)
	var observed: Dictionary = collector.snapshot()[0]
	observed["private"] = {"path": "OBSERVATION-SECRET-654"}
	var before_info := info.duplicate(true)
	var before_profile := profile.duplicate(true)
	var before_observed := observed.duplicate(true)
	var report := Diagnostics.build(info, profile, observed)
	var json := JSON.stringify(report)
	check("versioned schema and exact running identities", report.format == Diagnostics.FORMAT and report.build == BuildInfo.current() and report.engine.version == Engine.get_version_info().string and report.engine.hash == Engine.get_version_info().hash and report.os.name == OS.get_name() and report.os.version == OS.get_version())
	check("capture is read only", info == before_info and profile == before_profile and observed == before_observed)
	check("same snapshot produces deterministic structure", report == Diagnostics.build(info, profile, observed) and json == JSON.stringify(Diagnostics.build(info, profile, observed)))
	var private_values := ["PRIVATE-NAME-654", "NAME-RAW-654", "GUID-SECRET-654", "SERIAL-SECRET-654", "INFO-NESTED-654", "PROFILE-PRIVATE-654", "PROFILE-SERIAL-654", "PROFILE-GUID-654", "LEGACY-654", "CHANNEL-SECRET-654", "BINDING-SECRET-654", "PROFILE-CUSTOM-654", "SWITCH-654", "OBSERVATION-SECRET-654", str(profile.profile_id)]
	var no_leaks := true
	for value: String in private_values:
		no_leaks = no_leaks and not json.contains(value)
	check("default report omits all identifiers and arbitrary nested data", no_leaks and not report.privacy.identifiers_included)
	check("requested transport and layout use only recognized values", report.device.transport == {"status": "reported", "value": "usb"} and report.device.layout == {"status": "reported", "value": "advanced"})
	check("device IDs are normalized without guessing capabilities", report.device.vendor_id == 4617 and report.device.product_id == 20308 and report.device.physical_axis_count.status == "not_exposed" and report.device.physical_button_count.status == "not_exposed" and report.device.vibration_supported == null)
	check("calibration channels and profile revisions are retained", report.profile.status == "valid" and report.profile.schema_version == 2 and report.profile.preset_revision == profile.preset_revision and report.profile.channels.roll.axis == profile.roll.axis and report.profile.channels.throttle.range_kind == "absolute")
	check("effective bindings use existing action resolver without copying nested metadata", report.profile.effective_actions.bindings.pause == {"type": "key", "physical_keycode": KEY_ESCAPE} and report.profile.effective_actions.status == "without_activity_capabilities" and report.profile.auxiliary.gear.buttons == [100, 101])
	check("F1 axis event observations and untouched axes remain distinct", report.observations.axes[0].status == "observed" and report.observations.axes[0].events == 2 and report.observations.axes[0].min == -0.75 and report.observations.axes[0].max == 0.5 and report.observations.axes[1].status == "unobserved" and report.observations.axes[1].min == null)
	check("F1 button observations contain only bounded aggregate", report.observations.buttons.size() == 1 and report.observations.buttons[0].button == 100 and report.observations.buttons[0].events == 2 and not report.observations.buttons[0].pressed)
	var identified := Diagnostics.build(info, profile, observed, true)
	check("explicit identifiers include documented identity fields", identified.privacy.identifiers_included and identified.device.identifiers.serial_number == info.serial_number and identified.profile.identifiers.legacy_device_key == profile.association.legacy_device_key and identified.profile.identifiers.profile_id == profile.profile_id)
	var identified_json := JSON.stringify(identified)
	check("identifier opt-in never copies arbitrary nested extensions", not identified_json.contains("BINDING-SECRET-654") and not identified_json.contains("PROFILE-CUSTOM-654") and not identified_json.contains("OBSERVATION-SECRET-654"))
	var none := Diagnostics.build({}, {})
	check("no collection or physical layout remains explicitly unknown", none.observations.status == "not_started" and none.observations.axes[0].status == "unobserved" and none.device.transport.status == "not_exposed" and none.device.layout.status == "not_exposed" and none.profile.status == "not_provided")
	check("activity capabilities alone do not imply input observation", Diagnostics.build({}, profile, {"activity_capabilities": {"gear": true}}).observations.status == "not_started")
	check("unconfigured profile is distinguished from corruption", Diagnostics.build({}, Profile.unconfigured()).profile.status == "unconfigured")
	var malformed_info := {"kind": ["radio"], "known": 1, "vendor_id": true, "transport": {"serial": "NO-LEAK-654"}, "layout": "C:/PRIVATE-LAYOUT-654"}
	var malformed_profile := profile.duplicate(true)
	malformed_profile.roll.min = NAN
	malformed_profile.throttle.axis = -1
	var malformed_observation := {"axes": [{"axis": 0, "events": 1, "min": NAN, "max": INF}], "buttons": [{"button": -1, "events": 1}], "button_events": INF}
	var malformed := Diagnostics.build(malformed_info, malformed_profile, malformed_observation)
	var malformed_json := JSON.stringify(malformed)
	check("malformed values do not generate non-JSON numbers or private values", JSON.parse_string(malformed_json) is Dictionary and not malformed_json.contains("NAN") and not malformed_json.contains("INF") and not malformed_json.contains("NO-LEAK-654") and not malformed_json.contains("PRIVATE-LAYOUT-654"))
	check("invalid profile does not resolve guessed action defaults", malformed.profile.status == "invalid" and malformed.profile.effective_actions.status == "not_available" and malformed.profile.effective_actions.bindings.is_empty())
	check("invalid sample never becomes an observation", malformed.observations.axes[0].status == "invalid" and malformed.observations.axes[0].min == null and malformed.observations.buttons.is_empty() and malformed.observations.button_events == null)
	check("invalid transport and layout are not copied", malformed.device.transport.status == "unrecognized" and malformed.device.layout.status == "unrecognized" and malformed.device.transport.value == null and malformed.device.layout.value == null)
	var duplicate_axis := {"axes": [{"axis": 1, "events": 1, "min": 0.0, "max": 0.0}, {"axis": 1, "events": 1, "min": -1.0, "max": 1.0}], "buttons": []}
	check("conflicting duplicate axis summaries are explicitly invalid", Diagnostics.build({}, profile, duplicate_axis).observations.axes[1].status == "invalid")
	var many_buttons: Array = []
	for index in Data.MAX_TRACKED_BUTTONS + 10:
		many_buttons.append({"button": index, "events": 1, "press_events": 1, "release_events": 0, "pressed": true})
	check("untrusted observations cannot exceed the existing button bound", Diagnostics.build({}, profile, {"buttons": many_buttons}).observations.buttons.size() == Data.MAX_TRACKED_BUTTONS)
	check("absent menu evidence reports disabled", report.profile.radio_menu.status == "disabled")
	var menu_candidate := Profile.defaults("radio", "radio_custom")
	menu_candidate.association = {"serial_number": "MENU-FINGERPRINT-SECRET", "guid": "MENU-GUID-SECRET"}
	menu_candidate.actions.accept = {"type": "button", "button": 10}
	menu_candidate.actions.back = {"type": "button", "button": 11}
	menu_candidate.actions.pause = {"type": "button", "button": 12}
	var verified := RadioMenu.verified_profile(menu_candidate)
	check("verified menu fixture is valid", not verified.is_empty() and RadioMenu.is_verified(verified) and Profile.validate(verified).ok)
	var verified_report := Diagnostics.build(info, verified)
	var verified_text := JSON.stringify(verified_report)
	check("menu verification status and selected navigation channels are retained", verified_report.profile.radio_menu == {"status": "verified", "horizontal": "roll", "vertical": "pitch"})
	check("verified menu fingerprints never leak identity data", not verified_text.contains("MENU-FINGERPRINT-SECRET") and not verified_text.contains("MENU-GUID-SECRET") and not verified_text.contains("verified_mapping") and not verified_text.contains("verified_actions"))
	var verified_opt_in := JSON.stringify(Diagnostics.build(info, verified, {}, true))
	check("opt-in includes only named identifiers, never verification fingerprints", verified_opt_in.contains("MENU-FINGERPRINT-SECRET") and not verified_opt_in.contains("verified_mapping") and not verified_opt_in.contains("verified_actions"))
	var stale := verified.duplicate(true)
	stale.roll.min = -0.9
	check("changed calibration is reported as stale", Diagnostics.build(info, stale).profile.radio_menu.status == "stale")
	var disabled := verified.duplicate(true)
	disabled.ui_navigation = {"enabled": false}
	check("explicitly disabled menu navigation remains disabled", Diagnostics.build(info, disabled).profile.radio_menu.status == "disabled")
	var invalid_association := verified.duplicate(true)
	invalid_association.association = 42
	var invalid_menu := Diagnostics.build(info, invalid_association)
	check("malformed association fails closed without copying menu evidence", invalid_menu.profile.status == "invalid" and invalid_menu.profile.radio_menu.status == "stale" and not JSON.stringify(invalid_menu).contains("MENU-FINGERPRINT-SECRET"))

	var calibrated := Profile.defaults("radio", "radio_custom")
	calibrated.roll.min = -0.9
	calibrated.roll.center = 0.1
	calibrated.roll.max = 0.8
	calibrated.roll.invert = true
	calibrated.throttle.min = -0.8
	calibrated.throttle.max = 0.9
	calibrated.throttle.invert = true
	var raw := PackedFloat64Array()
	raw.resize(Data.AXES)
	raw[0] = 0.45
	raw[2] = -0.3
	var seen := PackedByteArray()
	seen.resize(Data.AXES)
	seen[0] = 1
	seen[2] = 1
	var current := Diagnostics.build(info, calibrated, {"current_samples": {"raw_axes": raw, "observed": seen}})
	var live: Dictionary = current.observations.current_samples
	check("current sample reports observed raw values and excludes unseen zero", live.status == "provided" and live.axes[0].status == "observed" and live.axes[0].raw == 0.45 and live.axes[1].status == "unobserved" and live.axes[1].raw == null and live.channels.pitch.normalized == null)
	check("current values use calibrated endpoints and inversion", is_equal_approx(live.channels.roll.normalized, Profile.channel_value(0.45, "roll", calibrated)) and is_equal_approx(live.channels.throttle.normalized, Profile.channel_value(-0.3, "throttle", calibrated)))
	var reader := RcInput.new()
	reader.connect_device(42, info, calibrated)
	reader.on_motion(42, 0, raw[0])
	reader.on_motion(42, 2, raw[2])
	reader.poll(func(_id: int, axis: int) -> float: return raw[axis], 1.0 / 240.0)
	check("diagnostic channel samples match the flight input reader", is_equal_approx(live.channels.roll.normalized, reader.sticks().roll) and is_equal_approx(live.channels.throttle.normalized, reader.throttle_position()))
	var invalid_raw := raw.duplicate()
	invalid_raw[0] = NAN
	invalid_raw[1] = NAN # ignored: this axis has no observed event
	var invalid_live: Dictionary = Diagnostics.build(info, calibrated, {"current_samples": {"raw_axes": invalid_raw, "observed": seen}}).observations.current_samples
	check("invalid observed input cannot become a numeric command", invalid_live.axes[0].status == "invalid" and invalid_live.axes[0].raw == null and invalid_live.channels.roll.normalized == null and invalid_live.axes[1].status == "unobserved" and invalid_live.axes[1].raw == null)
	var invalid_mask := seen.duplicate()
	invalid_mask[0] = 2
	var invalid_mask_live: Dictionary = Diagnostics.build(info, calibrated, {"current_samples": {"raw_axes": raw, "observed": invalid_mask}}).observations.current_samples
	check("mask values other than zero or one cannot certify input", invalid_mask_live.axes[0].status == "invalid" and invalid_mask_live.axes[0].raw == null)
	var malformed_live: Dictionary = Diagnostics.build(info, calibrated, {"current_samples": {"raw_axes": [0.0], "observed": [true]}}).observations.current_samples
	check("wrong-sized sample payload fails closed", malformed_live.status == "invalid" and malformed_live.channels.roll.status == "invalid" and malformed_live.channels.roll.raw == null)
	var invalid_profile_live: Dictionary = Diagnostics.build(info, malformed_profile, {"current_samples": {"raw_axes": raw, "observed": seen}}).observations.current_samples
	check("invalid profile retains raw evidence but never returns a normalized value", invalid_profile_live.channels.roll.status == "invalid_profile" and invalid_profile_live.channels.roll.raw == 0.45 and invalid_profile_live.channels.roll.normalized == null)
	var rate_pad := Profile.defaults("gamepad", "mode2")
	var rate_seen := PackedByteArray()
	rate_seen.resize(Data.AXES)
	rate_seen[rate_pad.throttle.axis] = 1
	raw[rate_pad.throttle.axis] = -0.5
	var rate_live: Dictionary = Diagnostics.build({}, rate_pad, {"current_samples": {"raw_axes": raw, "observed": rate_seen}}).observations.current_samples.channels.throttle
	check("stick-rate sample is labeled as rate, not accumulated throttle", rate_live.status == "observed" and rate_live.meaning == "rate_input_not_accumulated_throttle" and is_equal_approx(rate_live.normalized, Profile.channel_value(raw[rate_pad.throttle.axis], "throttle", rate_pad)))
	check("current samples can be exported as valid JSON", Diagnostics.write_new(TARGET + ".samples", current) == OK and JSON.parse_string(FileAccess.get_file_as_string(TARGET + ".samples")) is Dictionary)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TARGET + ".samples"))
	var pad := Profile.defaults("gamepad", "mode2")
	var with_capabilities := Diagnostics.build({}, pad, {"activity_capabilities": {"gear": true, "flaps": false}})
	var expected := Actions.effective_bindings(pad, {"gear": true, "flaps": false})
	check("supplied flight capability context resolves the actual action map", with_capabilities.profile.effective_actions.status == "resolved" and with_capabilities.profile.effective_actions.activity_capabilities.values == {"gear": true, "flaps": false} and with_capabilities.profile.effective_actions.bindings.gear_toggle == expected.gear_toggle and with_capabilities.profile.effective_actions.bindings.flaps_cycle == expected.flaps_cycle)
	check("new report writes successfully", Diagnostics.write_new(TARGET, report) == OK)
	var written := FileAccess.get_file_as_bytes(TARGET)
	check("written bytes are valid JSON and preserve the report", JSON.parse_string(written.get_string_from_utf8()) is Dictionary and written == (JSON.stringify(report, "\t") + "\n").to_utf8_buffer())
	check("existing file is never replaced", Diagnostics.write_new(TARGET, identified) == ERR_ALREADY_EXISTS and FileAccess.get_file_as_bytes(TARGET) == written)
	var lock := ProjectSettings.globalize_path(TARGET + ".other" + Diagnostics.LOCK_SUFFIX)
	check("competing reservation fixture created", DirAccess.make_dir_absolute(lock) == OK)
	check("competing reservation refuses a write", Diagnostics.write_new(TARGET + ".other", report) != OK and not FileAccess.file_exists(TARGET + ".other"))
	DirAccess.remove_absolute(lock)
	var existing_directory := ProjectSettings.globalize_path(TARGET + ".directory")
	check("existing directory fixture created", DirAccess.make_dir_absolute(existing_directory) == OK)
	check("existing directory is never replaced", Diagnostics.write_new(TARGET + ".directory", report) == ERR_ALREADY_EXISTS and DirAccess.dir_exists_absolute(existing_directory))
	DirAccess.remove_absolute(existing_directory)
	check("invalid report is refused before writing", Diagnostics.write_new(TARGET + ".bad", {"format": Diagnostics.FORMAT, "bad": NAN}) == ERR_INVALID_PARAMETER and not FileAccess.file_exists(TARGET + ".bad"))
	check("missing parent does not create a report", Diagnostics.write_new("user://controller-diagnostics-missing-parent/report.json", report) != OK)
	clean()
	print("Controller diagnostics: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
