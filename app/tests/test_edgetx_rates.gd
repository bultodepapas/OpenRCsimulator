# D6-ETX-05…08 (docs/plans/edgetx-airplane-controls.md), phases 2 and 3. Phase 2: one EdgeTX profile may share a
# physical control between a quad channel and an airplane channel, never within one vehicle. Phase 3: `rates_owner`
# decides who shapes a radio's sticks: the radio (default; OpenRC passes the sticks through) or OpenRC, which applies
# the flown aircraft's manual rates chosen by the profile's rates switch (low normal, middle sport, high full) or by
# the Dual rates action when no switch is bound. Synthetic radio samples; the session runs without physics steps.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Profile := preload("res://input/controller_profile.gd")
const Actions := preload("res://input/controller_actions.gd")
const RcInput := preload("res://input/rc_input.gd")
const Commands := preload("res://input/commands.gd")
const AIRCRAFT := "res://data/aircraft/p51d_mustang_120.json"
const INFO := {guid = "etx-rates", name = "RadioMaster TX16S Joystick", vendor_id = 0x1209, product_id = 0x4f54}
const DEVICE := 42
const DT := 1.0 / 240.0

var checks := 0
var failures := 0
var _axes := {}


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _run() -> void:
	_sharing()
	_ownership_field()
	_switch_bands()
	_session()
	print("edgetx rates: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _axis(axis: int, off := -1.0, on := 1.0) -> Dictionary:
	return {"type": "axis", "axis": axis, "invert": on < off, "off": off, "on": on}


func _sharing() -> void:
	var p: Dictionary = Profile.defaults("radio", Profile.EDGETX_AIRPLANE_PRESET)
	p.aux = {"gear": _axis(4), "arm": _axis(4, 0.0, 1.0), "flaps": _axis(5), "flight_mode": _axis(5)}
	var report: Dictionary = Actions.validate_profile_bindings(p)
	check("gear+arm and flaps+mode may share CH5/CH6", Profile.validate(p).ok and report.ok, str(report.errors))
	check("and validate for the quad too", Actions.validate_profile_bindings(p, Actions.MULTIROTOR_CAPABILITIES).ok)
	for pair: Array in [["gear", "smoke"], ["gear", "flaps"], ["arm", "flight_mode"], ["rates", "gear"]]:
		var q: Dictionary = Profile.defaults("radio", Profile.EDGETX_AIRPLANE_PRESET)
		q.aux = {pair[0]: _axis(6), pair[1]: _axis(6)}
		check("same-vehicle channels still conflict: %s + %s" % pair, not Actions.validate_profile_bindings(q).ok)
	var action: Dictionary = Profile.defaults("radio", Profile.EDGETX_AIRPLANE_PRESET)
	action.aux = {"gear": {"type": "button", "button": 3, "mode": "level"}}
	action.actions.camera_cycle = {"type": "button", "button": 3}
	check("an action on an AUX control still conflicts", not Actions.validate_profile_bindings(action).ok)
	var rates_action: Dictionary = Profile.defaults("radio", Profile.EDGETX_AIRPLANE_PRESET)
	rates_action.aux = {"rates": _axis(6)}
	rates_action.actions.rates_toggle = {"type": "button", "button": 5}
	check("a rates switch and the Dual rates action are one function", not Actions.validate_profile_bindings(rates_action).ok)
	check("vehicle families", not Actions.aux_channels_share_vehicle("gear", "arm") and Actions.aux_channels_share_vehicle("gear", "rates")
		and Actions.aux_channels_share_vehicle("arm", "flight_mode"))


func _ownership_field() -> void:
	var radio: Dictionary = Profile.defaults("radio", "radio_custom")
	check("a radio's rates stay on the radio by default", Profile.rates_owner(radio) == "transmitter" and not radio.has("rates_owner"))
	check("a joystick and a gamepad keep simulator rates", Profile.rates_owner(Profile.defaults("joystick", "radio_custom")) == "simulator"
		and Profile.rates_owner(Profile.defaults("gamepad", "mode2")) == "simulator")
	radio["rates_owner"] = "simulator"
	check("simulated rates validate on a radio", Profile.validate(radio).ok and Profile.rates_owner(radio) == "simulator")
	radio["rates_owner"] = "both"
	check("an unknown owner is rejected", not Profile.validate(radio).ok)
	var pad: Dictionary = Profile.defaults("gamepad", "mode2")
	pad["rates_owner"] = "transmitter"
	check("a gamepad cannot name an owner", not Profile.validate(pad).ok)
	var upgraded := Profile.upgrade_legacy(Profile.defaults("radio", "radio_custom"))
	check("upgrade keeps a missing field missing (radio default)", not upgraded.has("rates_owner") and Profile.rates_owner(upgraded) == "transmitter")


func _radio(profile: Dictionary) -> RcInput:
	var radio := RcInput.new()
	radio.connect_device(DEVICE, INFO, profile)
	return radio


func _poll(radio: RcInput, values: Dictionary) -> void:
	_axes = {2: -1.0}
	_axes.merge(values, true)
	radio.poll(func(_d: int, axis: int) -> float: return float(_axes.get(axis, 0.0)), DT, func(_d: int, _b: int) -> bool: return false)


func _switch_bands() -> void:
	var p: Dictionary = Profile.defaults("radio", Profile.EDGETX_AIRPLANE_PRESET)
	p.rates_owner = "simulator"
	p.aux = {"rates": _axis(6)}
	var radio := _radio(p)
	check("a bound rate switch is reported", radio.has_rate_switch())
	_poll(radio, {6: 1.0})
	check("no command before the switch is seen at OFF", radio.rate_switch_profile() == "")
	radio.on_motion(DEVICE, 6, -1.0)
	_poll(radio, {6: -1.0})
	check("low = normal", radio.rate_switch_profile() == "normal")
	_poll(radio, {6: 0.0})
	check("middle = sport", radio.rate_switch_profile() == "sport")
	_poll(radio, {6: 1.0})
	check("high = full", radio.rate_switch_profile() == "full")
	check("no switch, no request", _radio(Profile.defaults("radio", Profile.EDGETX_AIRPLANE_PRESET)).rate_switch_profile() == ""
		and not _radio(Profile.defaults("radio", Profile.EDGETX_AIRPLANE_PRESET)).has_rate_switch())


func _session() -> void:
	var f := Flight.new()
	f.physics_enabled = false
	f.setup(AIRCRAFT)
	check("P-51 has manual rates", f.aircraft.ok and f.aircraft.model.controls.has("rates"))
	f.rate_profile = "sport"
	var transmitter: Dictionary = Profile.defaults("radio", Profile.EDGETX_AIRPLANE_PRESET)
	f.radio.connect_device(DEVICE, INFO, transmitter)
	check("radio-owned rates: OpenRC applies none", not f.rate_profile_available() and f.effective_rate_profile() == "full"
		and not f.toggle_rate_profile())
	f.commands = {roll = 1.0, pitch = 0.5, yaw = 0.0, throttle = 0.0}
	f.trims = {roll = 0.0, pitch = 0.0, yaw = 0.0}
	check("radio-owned sticks pass through", is_equal_approx(float(f.flown_commands().roll), 1.0)
		and is_equal_approx(float(f.flown_commands().pitch), 0.5))

	var simulated := transmitter.duplicate(true)
	simulated.rates_owner = "simulator"
	f.radio.connect_device(DEVICE, INFO, simulated)
	f.rate_profile = "normal"
	check("simulated rates are available on a radio", f.rate_profile_available() and f.rates_active())
	var normal: Dictionary = f.aircraft.model.controls.rates.normal
	var expected: Dictionary = Commands.shape_sticks(f.commands, normal, true)
	check("normal rates shape the radio sticks with the aircraft expo", is_equal_approx(float(f.flown_commands().pitch), float(expected.pitch))
		and is_equal_approx(float(f.flown_commands().roll), float(expected.roll)), "%s vs %s" % [f.flown_commands(), expected])
	check("without a switch the Dual rates action toggles", f.toggle_rate_profile() and f.rate_profile != "normal")

	var switched := simulated.duplicate(true)
	switched.aux = {"rates": _axis(6)}
	f.radio.connect_device(DEVICE, INFO, switched)
	f.rate_profile = "sport"
	var changes: Array = []
	f.rate_profile_changed.connect(func(active: bool) -> void: changes.append(active))
	check("a bound switch owns the choice: the toggle is refused", not f.toggle_rate_profile())
	_poll(f.radio, {6: 1.0})
	f._apply_rate_switch()
	check("a switch never seen at OFF keeps the current profile", f.rate_profile == "sport" and changes.is_empty())
	f.radio.on_motion(DEVICE, 6, -1.0)
	_poll(f.radio, {6: -1.0})
	f._apply_rate_switch()
	check("switch low selects normal and reports it once", f.rate_profile == "normal" and changes == [true], str(changes))
	_poll(f.radio, {6: 1.0})
	f._apply_rate_switch()
	f._apply_rate_switch()
	check("switch high selects full (raw sticks), one change", f.rate_profile == "full" and f.effective_rate_profile() == "full"
		and changes == [true, false] and is_equal_approx(float(f.flown_commands().roll), 1.0), str(changes))
	_poll(f.radio, {6: 0.0})
	f._apply_rate_switch()
	check("switch middle selects sport", f.rate_profile == "sport" and f.rate_profile_label() == "Rates: sport")
	f.sim.paused = true
	_poll(f.radio, {6: -1.0})
	f._apply_rate_switch()
	check("a paused flight ignores the switch", f.rate_profile == "sport")
	f.sim.paused = false
	f.radio.connect_device(DEVICE, INFO, transmitter)
	_poll(f.radio, {6: -1.0})
	f._apply_rate_switch()
	check("back on radio-owned rates the switch is not read", f.rate_profile == "sport" and not f.rates_active())
	f.free()
