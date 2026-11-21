# Diagnostic witnesses for the audited baseline, not corrected-behaviour regressions.
# Reuses the existing source test's real airship session and synthetic input fixture.
extends "res://tests/test_controller_audit_vehicle_airship.gd"

const Shell := preload("res://app_root.gd")
const Service := preload("res://input/controller_service.gd")
const Store := preload("res://input/controller_profile_store.gd")
const UiInput := preload("res://ui/ui_input.gd")

var audit_observations: Array = []


func _run() -> void:
	_probe_ui_mapping()
	_probe_busy_recovery()
	print("AUDIT_OBSERVATIONS ", JSON.stringify(audit_observations))
	print("AIRSHIP_AUDIT_COMPLETE %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _probe_ui_mapping() -> void:
	InputMap.load_from_project_settings()
	UiInput.isolate_joypads()
	var shell := Shell.new()
	var service := Service.new()
	var ship := Activity.new()
	shell.controllers = service
	ship.controller_registry = service.registry
	service.registry.update_devices([
		{id = 7, name = "First pad", guid = "first", known = true, kind = "gamepad"},
		{id = 8, name = "Second pad", guid = "second", known = true, kind = "gamepad"},
	])
	service.registry.select_device("ui", 7)
	UiInput.set_gamepad(7)
	var press := InputEventJoypadButton.new()
	press.device = 7
	press.button_index = JOY_BUTTON_A
	press.pressed = true
	check("precondition: selected pad owns native Accept", UiInput.selected_gamepad_id() == 7 and press.is_action_pressed("ui_accept"))
	shell.ground_vehicle = ship
	service.ui_selection_changed.connect(shell._controller_ui_changed)
	service.registry.disconnect_device(7)
	var after_loss := {registry_ui = service.registry.selected_device_id("ui"), native_ui = UiInput.selected_gamepad_id(),
		accept_matches = press.is_action_pressed("ui_accept"), mapping_count = UiInput.joypad_ui_events().size()}
	check("witness: UI role released but old native map remains", after_loss.registry_ui == -1 and after_loss.native_ui == 7 and after_loss.accept_matches)
	service.registry.update_devices([
		{id = 7, name = "Replacement pad", guid = "replacement", known = true, kind = "gamepad"},
		{id = 8, name = "Second pad", guid = "second", known = true, kind = "gamepad"},
	])
	check("witness: replacement handle still matches native Accept without ownership", service.registry.selected_device_id("ui") == -1 and press.is_action_pressed("ui_accept"))
	service.registry.select_device("ui", 8)
	var after_switch := {registry_ui = service.registry.selected_device_id("ui"), native_ui = UiInput.selected_gamepad_id()}
	check("witness: role change to pad 8 leaves native map on pad 7", after_switch.registry_ui == 8 and after_switch.native_ui == 7)
	audit_observations.append({id = "GCA-02", after_loss = after_loss, after_switch = after_switch,
		evidence = "Real registry/service/AppRoot/airship callbacks and InputMap event matching; no rendered HUD or SDL hardware"})
	UiInput.isolate_joypads()
	shell.ground_vehicle = null
	shell.controllers = null
	ship.free()
	service.free()
	shell.free()


func _probe_busy_recovery() -> void:
	axes = {0: 0.0, 1: 0.0, 2: 0.0, 3: 0.0}
	verified = true
	var path := "user://airship_audit_busy_%d.cfg" % OS.get_process_id()
	var service := Service.new()
	service.store = Store.new(path, path + ".legacy")
	var holder := Store.new(path, path + ".legacy")
	service.registry.update_devices([{id = 3, name = "Synthetic pad", guid = "busy-pad", known = true, kind = "gamepad"}])
	service.registry.select_device("flight", 3)
	var activity := _setup()
	activity.controller_registry = service.registry
	activity.controller_profile_for = Callable(service, "profile_for_device")
	activity.controller_confirmation = func(id: int, expected: int, generation: int) -> bool:
		return verified and id == expected and service.registry.selected_device_id("flight") == id \
			and service.registry.connection_generation(id) == generation
	var claim: Dictionary = holder.acquire_write()
	check("precondition: separate store owns lease", bool(claim.ok))
	if not claim.ok:
		_dispose(activity)
		service.free()
		return
	activity._connect_selected_controller()
	check("lock refuses profile and keeps input unarmed", activity.input.radio.connected and not activity.input.sample(DT, false).armed)
	holder.release_write()
	var resolved: Dictionary = service.profile_for_device(3)
	check("resolver is healthy on the same connection after release", not resolved.is_empty() and str(resolved.get("kind", "")) == "gamepad")
	activity._sync_selected_controller()
	activity.handle_action("resume")
	var blocked: bool = activity.session.paused and not activity.input.sample(DT, false).armed
	check("witness: Continue keeps stale unresolved profile after storage recovers", blocked)
	var message: String = activity.hud.last_flash
	check("control: explicit reapply accepts recovered profile", activity.apply_controller_selection(3))
	activity.handle_action("resume")
	var recovered: bool = not activity.session.paused
	check("control: same source resumes after explicit reapply", recovered)
	audit_observations.append({id = "GCA-03", resolver_recovered = not resolved.is_empty(), continue_blocked = blocked,
		explicit_reapply_recovers = recovered, displayed_message = message,
		evidence = "Real profile-store lease and resolver, production airship methods/session, synthetic input"})
	_dispose(activity)
	service.free()
