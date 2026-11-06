## HUD-09-R1: priorities, critical/category isolation, accepted fuel and coaching lifecycle.
extends SceneTree

const Policy := preload("res://render/overlays/alert_policy.gd")
const Manager := preload("res://render/overlays/overlay_manager.gd")

var _checks := 0
var _failed := 0


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		printerr("FAIL " + label)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var muted := {warning_energy = false, warning_navigation = false, warning_status = false, warning_training = false}
	var raw := PackedStringArray(["experimental", "far", "stall", "battery", "low", "stall", "safe", "battery_critical", "fuel_reserve"])
	_check("critical conditions survive every advisory switch in canonical order",
		Policy.select_codes(raw, muted) == PackedStringArray(["stall", "low", "battery_critical"]))
	_check("duplicates and redundant battery reminders are removed",
		Policy.select_codes(raw, {}) == PackedStringArray(["stall", "low", "battery_critical", "fuel_reserve", "far", "safe", "experimental"]))
	_check("empty energy and terrain states replace subordinate reminders",
		Policy.select_codes(PackedStringArray(["battery_empty", "battery_critical", "battery_lvc", "battery", "fuel_empty", "fuel_reserve_estimated", "low", "sink_rate"]), {warning_training = true})
		== PackedStringArray(["low", "battery_empty", "fuel_empty"]))
	_check("lost controller replaces radio and arming notices",
		Policy.select_codes(PackedStringArray(["safe", "failsafe", "controller_lost"]), {}) == PackedStringArray(["controller_lost"]))
	var snap := {telemetry = {time_s = 0.0, height_agl = 30.0, airspeed = 20.0, vertical_speed = -7.0, bank_deg = 80.0, load_factor = -5.0}}
	var pristine := snap.duplicate(true)
	_check("training cues are opt-in", Policy.additional_codes(snap, {}).is_empty())
	_check("all three coaching conditions use existing finite fields",
		Policy.additional_codes(snap, {warning_training = true}) == PackedStringArray(["sink_rate", "high_load", "steep_bank"]))
	_check("presentation leaves the accepted snapshot unchanged", snap == pristine)
	for bad: Variant in [null, "0", NAN, INF, -1.0]:
		var invalid := {mass_sample = {ok = true, finite_fuel = true, fuel_usable_kg = bad}}
		_check("invalid usable fuel cannot invent an empty warning: " + str(bad), Policy.additional_codes(invalid, {}).is_empty())
	_check("empty fuel comes from accepted finite usable mass",
		Policy.additional_codes({mass_sample = {ok = true, finite_fuel = true, fuel_usable_kg = 0.0}}, {}) == PackedStringArray(["fuel_empty"]))
	_check("unaccepted fuel sample cannot raise empty", Policy.additional_codes({mass_sample = {ok = false, finite_fuel = true, fuel_usable_kg = 0.0}}, {}).is_empty())
	_check("missing battery alarms never infer a battery warning from model SOC",
		Policy.additional_codes({battery = {ok = true, battery_kind = "pack_ecm", soc = 0.0}}, {}).is_empty())
	var policy := Policy.new()
	var enabled := {warning_training = true}
	_check("training starts a dwell window", policy.update(snap, enabled).is_empty())
	snap.telemetry.time_s = 0.5
	_check("brief excursions stay quiet", policy.update(snap, enabled).is_empty())
	snap.telemetry.time_s = 0.6
	_check("sustained cues appear after accepted time advances", policy.update(snap, enabled).size() == 3)
	snap.telemetry.bank_deg = 0.0
	snap.telemetry.load_factor = 1.0
	snap.telemetry.vertical_speed = 0.0
	_check("clear grace starts without rebuilding cues", policy.update(snap, enabled).size() == 3)
	snap.telemetry.time_s = 0.9
	_check("pause or short clear gap cannot flicker a cue", policy.update(snap, enabled).size() == 3)
	snap.telemetry.time_s = 1.0
	_check("clear conditions retire coaching cues", policy.update(snap, enabled).is_empty())
	snap.telemetry = pristine.telemetry.duplicate(true)
	snap.telemetry.time_s = 2.0
	policy.update(snap, enabled)
	snap.telemetry.time_s = 2.6
	_check("coaching rearms", policy.update(snap, enabled).size() == 3)
	snap.telemetry.bank_deg = NAN
	_check("unavailable input clears only its held cue without advancing time",
		policy.update(snap, enabled) == PackedStringArray(["sink_rate", "high_load"]))
	snap.telemetry.bank_deg = 80.0
	snap.telemetry.time_s = 0.0
	_check("rewind discards held and pending cues", policy.update(snap, enabled).is_empty())
	snap.telemetry.time_s = 0.6
	policy.update(snap, enabled)
	snap.telemetry.height_agl = 0.0
	_check("ground state clears cues immediately", policy.update(snap, enabled).is_empty())
	snap.telemetry.height_agl = 30.0
	snap.telemetry.bank_deg = NAN
	snap.telemetry.load_factor = INF
	snap.telemetry.vertical_speed = NAN
	_check("missing or nonfinite flight fields remain silent", Policy.additional_codes(snap, enabled).is_empty())
	await process_frame
	root.size = Vector2i(1920, 1080)
	var manager := Manager.new({preset = "player"}, "en")
	root.add_child(manager)
	var live := {telemetry = pristine.telemetry.duplicate(true), warnings = PackedStringArray(["far", "stall"])}
	manager.refresh_numbers(live)
	_check("manager prioritizes sampled urgent warnings", manager.frames.warnings.codes == PackedStringArray(["stall", "far"]))
	manager.set_warning_option("warning_navigation", false)
	_check("menu filter changes apply immediately", manager.frames.warnings.codes == PackedStringArray(["stall"]))
	manager.set_warning_option("warning_detail", false)
	manager.refresh_numbers({warnings = PackedStringArray(["fuel_reserve_estimated"])})
	_check("compact alerts preserve estimated reserve provenance",
		manager.frames.warnings.chips.get_child(0).find_child("Headline", true, false).text == "FUEL RESERVE · ESTIMATED"
		and not manager.frames.warnings.chips.get_child(0).find_child("Detail", true, false).visible)
	manager.set_warning_option("warning_training", true)
	manager.refresh_numbers(live)
	live.telemetry.time_s = 0.6
	manager.refresh_numbers(live)
	_check("manager adds sustained training cues", manager.frames.warnings.codes.has("high_load"))
	manager.set_warning_option("warning_training", false)
	_check("disabling coaching clears its visible state immediately", not manager.frames.warnings.codes.has("high_load"))
	manager.reset_flight()
	_check("reset clears stale warnings before a new snapshot", manager.frames.warnings.codes.is_empty() and not manager.frames.warnings.visible)
	manager.refresh_numbers({})
	_check("absent snapshot stays empty", not manager.frames.warnings.visible)
	manager.queue_free()
	await process_frame
	await create_timer(0.25).timeout # drain stopped shared-alert playback before engine shutdown
	print("alert policy: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed else 0)
