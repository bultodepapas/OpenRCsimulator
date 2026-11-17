# D6-ETX / UI-15-ETX / HUD-ETX phase 1 (docs/plans/edgetx-airplane-controls.md): EdgeTX radios are classified by
# their USB pair (never a known gamepad, never by a broad family name alone); the EdgeTX airplane preset is an
# intent table whose gear, flaps and smoke come only from the switch check; optional AUX metadata names the radio
# channel and switch without changing a value; a flaps switch can snap to the flown aircraft's detents; the Setup
# assistant lists the layout's functions; the control guide names "CH5 · SD"; F1 is in the keyboard reference.
# Synthetic devices and samples only: no physical radio, OS joystick mapping or rendered-layout claim.
extends SceneTree

const Profile := preload("res://input/controller_profile.gd")
const Actions := preload("res://input/controller_actions.gd")
const SmokeAux := preload("res://input/smoke_aux.gd")
const RcInput := preload("res://input/rc_input.gd")
const EdgeTx := preload("res://input/edgetx_radio.gd")
const Assistant := preload("res://ui/controls/setup_assistant.gd")
const Guide := preload("res://render/overlays/controls_guide.gd")
const Reference := preload("res://ui/controls_reference.gd")
const DT := 1.0 / 240.0
const DEVICE_ID := 7
## 0x1209 / 0x4F54 as Godot reports them (decimal strings).
const PAIR := {"vendor_id": "4617", "product_id": "20308"}

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_identity()
	_preset()
	_layout()
	_metadata()
	_detents()
	_runtime_detents()
	_assistant()
	_guide()
	print("edgetx airplane: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _info(extra: Dictionary) -> Dictionary:
	var info := PAIR.duplicate()
	info.merge(extra, true)
	return info


func _identity() -> void:
	_check("any EdgeTX maker classifies as a radio by the USB pair (decimal-string IDs)",
		EdgeTx.classifies_as_radio(_info({name = "Fatfish F16 Joystick"})))
	_check("hexadecimal and integer IDs classify the same way",
		EdgeTx.classifies_as_radio({vendor_id = "0x1209", product_id = "0x4f54"}) and EdgeTx.classifies_as_radio({vendor_id = 0x1209, product_id = 0x4F54}))
	_check("a known gamepad with the pair is not reclassified (Linux Classic needs F1-ETX-01 evidence)",
		not EdgeTx.classifies_as_radio(_info({name = "RadioMaster TX16S Joystick", known = true})))
	_check("a family name alone never classifies a device",
		not EdgeTx.classifies_as_radio({name = "8BitDo Pocket Gamepad"}) and not EdgeTx.classifies_as_radio({name = "RadioMaster Boxer Joystick"}))
	_check("a JETI identity claim is never EdgeTX", not EdgeTx.classifies_as_radio(_info({name = "JETI DC-16"})))
	_check("family names still select the EdgeTX draft (unchanged matcher)", EdgeTx.matches({name = "RadioMaster Boxer Joystick"}))
	var radio := RcInput.new()
	radio.connect_device(DEVICE_ID, _info({name = "Fatfish F16 Joystick"}))
	_check("rc_input treats the pair as a radio that needs calibration", str(radio.profile.get("kind", "")) == "radio"
		and radio.profile_source == "unconfigured")
	var known := RcInput.new()
	known.connect_device(DEVICE_ID, _info({name = "Fatfish F16 Joystick", known = true}))
	_check("a known gamepad keeps the gamepad starter profile", str(known.profile.get("kind", "")) == "gamepad")


func _preset() -> void:
	var p: Dictionary = Profile.defaults("radio", Profile.EDGETX_AIRPLANE_PRESET)
	_check("the EdgeTX airplane preset validates", not p.is_empty() and Profile.validate(p).ok
		and Actions.validate_profile_bindings(p).ok, str(Profile.validate(p).get("errors", [])))
	_check("named, AETR on axes 0-3 like every radio preset", str(p.get("name", "")) == "EdgeTX airplane"
		and int(p.roll.axis) == 0 and int(p.pitch.axis) == 1 and int(p.throttle.axis) == 2 and int(p.yaw.axis) == 3)
	_check("restart on CH9 (button 0), as the quad", p.actions.restart_flight == {"type": "button", "button": 0})
	_check("intent only: no AUX index is trusted before the switch check", p.get("aux", {}).is_empty())
	_check("rates and the flap mix keep their radio defaults", Profile.flap_elevator_mix_owner(p) == "simulator"
		and not p.has("rates_owner"))
	_check("other kinds refuse the preset", Profile.defaults("gamepad", Profile.EDGETX_AIRPLANE_PRESET).is_empty()
		and Profile.defaults("joystick", Profile.EDGETX_AIRPLANE_PRESET).is_empty())


func _layout() -> void:
	var by_id := {}
	for entry: Dictionary in EdgeTx.AIRPLANE_LAYOUT:
		by_id[str(entry.id)] = entry
	_check("layout: gear CH5, flaps CH6, restart CH9, smoke CH10", int(by_id["aux:gear"].channel) == 5
		and int(by_id["aux:flaps"].channel) == 6 and int(by_id["restart_flight"].channel) == 9 and int(by_id["aux:smoke"].channel) == 10)
	var fragile := false
	for entry: Dictionary in EdgeTx.AIRPLANE_LAYOUT:
		fragile = fragile or int(entry.channel) in [7, 8]
	_check("nothing on the CH7/CH8 pair", not fragile)
	_check("Classic channel of raw axes and buttons", EdgeTx.classic_channel({type = "axis", axis = 4}) == 5
		and EdgeTx.classic_channel({type = "button", button = 0}) == 9 and EdgeTx.classic_channel({type = "button", button = 1}) == 10
		and EdgeTx.classic_channel({type = "axis", axis = 8}) == 0 and EdgeTx.classic_channel({type = "switch"}) == 0)
	_check("layout lookup", int(EdgeTx.layout_entry("aux:flaps").get("channel", 0)) == 6 and EdgeTx.layout_entry("aux:arm").is_empty())


func _metadata() -> void:
	var axis := {"type": "axis", "axis": 4, "invert": false, "off": -1.0, "on": 1.0}
	var named := axis.duplicate()
	named.merge({"channel": 5, "label": "SD"})
	_check("channel and label are valid on an axis AUX", SmokeAux.valid_binding(named))
	var button := {"type": "button", "button": 1, "mode": "level", "channel": 10, "label": "SE"}
	_check("channel and label are valid on a button AUX", SmokeAux.valid_binding(button))
	for bad: Dictionary in [{"channel": 0}, {"channel": 33}, {"channel": "5"}, {"label": ""}, {"label": "x".repeat(25)},
			{"label": 5}, {"detents": "keyboard"}, {"detents": true}]:
		var candidate := axis.duplicate()
		candidate.merge(bad, true)
		_check("invalid metadata is rejected: %s" % str(bad), not SmokeAux.valid_binding(candidate))
	var flaps := axis.duplicate()
	flaps["axis"] = 5
	flaps["detents"] = "aircraft"
	_check("detents: aircraft is valid", SmokeAux.valid_binding(flaps))
	var same := true
	for value: float in [-1.0, -0.4, 0.0, 0.33, 1.0]:
		same = same and SmokeAux.axis_amount(value, axis) == SmokeAux.axis_amount(value, named)
	_check("metadata never changes an axis amount", same)
	var profile: Dictionary = Profile.defaults("radio", Profile.EDGETX_AIRPLANE_PRESET)
	profile.aux = {"gear": named, "flaps": flaps, "smoke": button}
	_check("a profile with named AUX and flap detents validates", Profile.validate(profile).ok
		and Actions.validate_profile_bindings(profile).ok, str(Profile.validate(profile).get("errors", [])))


func _detents() -> void:
	var p51 := [0.0, 1.0 / 3.0, 1.0]
	_check("3-position switch on P-51 detents", SmokeAux.snap_to_detents(0.0, p51) == 0.0
		and SmokeAux.snap_to_detents(0.5, p51) == 1.0 / 3.0 and SmokeAux.snap_to_detents(1.0, p51) == 1.0)
	_check("bands are equal thirds", SmokeAux.snap_to_detents(0.32, p51) == 0.0 and SmokeAux.snap_to_detents(0.34, p51) == 1.0 / 3.0
		and SmokeAux.snap_to_detents(0.67, p51) == 1.0)
	_check("two detents: up / full", SmokeAux.snap_to_detents(0.49, [0.0, 1.0]) == 0.0 and SmokeAux.snap_to_detents(0.5, [0.0, 1.0]) == 1.0)
	_check("fewer than two detents leave the amount", SmokeAux.snap_to_detents(0.5, []) == 0.5 and SmokeAux.snap_to_detents(0.5, [1.0]) == 0.5)


func _runtime_detents() -> void:
	var axis := {"type": "axis", "axis": 5, "invert": false, "off": -1.0, "on": 1.0}
	var snapped_binding := axis.duplicate()
	snapped_binding["detents"] = "aircraft"
	var snapped := _armed_flaps(snapped_binding)
	snapped.set_flap_detents([0.0, 0.4, 1.0])
	_poll(snapped, {5: 0.0})
	_check("Vantage: a 3-position middle requests the take-off detent", snapped.auxiliary_amount("flaps") == 0.4,
		str(snapped.auxiliary_amount("flaps")))
	_poll(snapped, {5: 1.0})
	_check("the high position requests full flaps", snapped.auxiliary_amount("flaps") == 1.0)
	_poll(snapped, {5: -1.0})
	_check("the low position requests flaps up", snapped.auxiliary_amount("flaps") == 0.0)
	snapped.set_flap_detents([])
	_poll(snapped, {5: 0.0})
	_check("without aircraft detents the amount stays linear", snapped.auxiliary_amount("flaps") == 0.5)
	var linear := _armed_flaps(axis)
	linear.set_flap_detents([0.0, 0.4, 1.0])
	_poll(linear, {5: 0.0})
	_check("a binding without detents keeps today's linear 0.5", linear.auxiliary_amount("flaps") == 0.5)
	_check("detents are kept sorted and clamped", Array(_detents_of([1.0, 2.0, 0.0, -1.0, NAN])) == [0.0, 0.0, 1.0, 1.0])


func _detents_of(values: Array) -> Array[float]:
	var radio := RcInput.new()
	radio.set_flap_detents(values)
	return radio.flap_detents()


func _armed_flaps(binding: Dictionary) -> RcInput:
	var profile: Dictionary = Profile.defaults("radio", Profile.EDGETX_AIRPLANE_PRESET)
	profile.aux = {"flaps": binding}
	var radio := RcInput.new()
	radio.connect_device(DEVICE_ID, _info({name = "RadioMaster TX16S Joystick"}), profile)
	radio.on_motion(DEVICE_ID, 5, -1.0) # OFF evidence arms the channel
	_poll(radio, {5: -1.0})
	return radio


func _poll(radio: RcInput, values: Dictionary) -> void:
	var axes := {2: -1.0}
	axes.merge(values, true)
	radio.poll(func(_device: int, axis: int) -> float: return float(axes.get(axis, 0.0)), DT,
		func(_device: int, _button: int) -> bool: return false)


func _assistant() -> void:
	var airplane := Actions.AIRPLANE_CAPABILITIES.duplicate()
	var rows := Assistant.essentials_for(airplane, "edgetx_airplane")
	_check("the switch check lists gear, flaps, smoke and restart, then Pause",
		rows == PackedStringArray(["aux:gear", "aux:flaps", "aux:smoke", "restart_flight", "pause"]), str(rows))
	airplane.gear = false
	airplane.smoke = false
	rows = Assistant.essentials_for(airplane, "edgetx_airplane")
	_check("functions the aircraft lacks are left out", not rows.has("aux:gear") and not rows.has("aux:smoke") and rows.has("aux:flaps"))
	_check("other presets keep the press-action essentials", Assistant.essentials_for(Actions.AIRPLANE_CAPABILITIES, "radio_custom").has("gear_toggle"))
	_check("the quad keeps its own essentials", Assistant.essentials_for(Actions.MULTIROTOR_CAPABILITIES, "edgetx_airplane")
		== PackedStringArray(["aux:arm", "aux:flight_mode", "pause"]))
	var hint := Assistant.layout_hint("aux:gear", "edgetx_airplane")
	_check("each row names its suggested channel, switch and OFF position", hint.contains("CH5") and hint.contains("SD") and hint.contains("DOWN"), hint)
	_check("no hint outside the EdgeTX airplane preset", Assistant.layout_hint("aux:gear", "radio_custom").is_empty())
	_check("AUX rows have titles", Assistant.item_title("aux:gear") == "Landing gear" and Assistant.item_title("aux:smoke") == "Smoke")


func _guide() -> void:
	_check("guide names the radio channel and switch", Guide.radio_control_text({type = "axis", axis = 4, channel = 5, label = "SD"}, "Axis 4") == "CH5 · SD")
	_check("channel without label", Guide.radio_control_text({type = "button", button = 1, channel = 10}, "Button 1") == "CH10")
	_check("label only keeps the control", Guide.radio_control_text({type = "axis", axis = 4, label = "SD"}, "Axis 4") == "SD · Axis 4")
	_check("no metadata keeps today's text", Guide.radio_control_text({type = "axis", axis = 4}, "Axis 4") == "Axis 4")
	var f1_listed := false
	for row: Array in Reference.SHORTCUTS:
		f1_listed = f1_listed or (row[0] as Array).has(KEY_F1)
	_check("F1 is in the keyboard reference", f1_listed)
