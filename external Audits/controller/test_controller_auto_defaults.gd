extends SceneTree

const Service = preload("res://input/controller_service.gd")
const Profile = preload("res://input/controller_profile.gd")
const Actions = preload("res://input/controller_actions.gd")
const ShellSlice = preload("res://shell_projection.gd")

class CountingService extends Service:
	var reads := 0
	func profile_for_device(id: int) -> Dictionary:
		reads += 1
		return super.profile_for_device(id)

class CountingShell extends ShellSlice:
	var binding_resolutions := 0
	func _controller_bindings(id: int, flight_context := false) -> Dictionary:
		binding_resolutions += 1
		return super._controller_bindings(id, flight_context)

class CachedShell extends ShellSlice:
	var maps := {}
	func _controller_bindings(id: int, flight_context := false) -> Dictionary:
		var key := str(id) + ":" + str(flight_context)
		if not maps.has(key): maps[key] = super._controller_bindings(id, flight_context)
		return maps[key]

class SessionFixture extends Node:
	var calibration = null
	var cuts := 0
	func set_controller_cut(_held: bool) -> void: cuts += 1

class FlightFixture extends Node:
	var session = SessionFixture.new()
	func controller_capabilities() -> Dictionary: return Actions.AIRPLANE_CAPABILITIES
	func accident_menu_active() -> bool: return false
	func controller_action(_action: String) -> bool: return true

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var service := CountingService.new()
	service.registry.update_devices([{id=7, guid="audit-gamepad", name="Audit gamepad", known=true, kind="gamepad"}])
	service.registry.select_device("flight", 7)
	service.registry.select_device("ui", 7)
	var profile := Profile.defaults()
	service._profiles["7:%d" % service.registry.connection_generation(7)] = profile
	var target := FlightFixture.new()
	var shell := CountingShell.new()
	shell.controllers = service
	shell.flight = target
	var event := InputEventJoypadMotion.new()
	event.device = 7
	event.axis = JOY_AXIS_LEFT_X
	event.axis_value = 0.1
	shell._input(event)
	print("HOTPATH_COUNT ", JSON.stringify({event="selected_gamepad_axis", binding_resolutions=shell.binding_resolutions, profile_deep_copy_requests=service.reads, generic_identities=shell._controller_action_identities.size()}))
	shell.binding_resolutions = 0
	service.reads = 0
	event.device = 12
	shell._input(event)
	print("HOTPATH_COUNT ", JSON.stringify({event="unselected_gamepad_axis", binding_resolutions=shell.binding_resolutions, profile_deep_copy_requests=service.reads, generic_identities=shell._controller_action_identities.size()}))
	if OS.get_cmdline_user_args().has("--measure"):
		var cached := CachedShell.new()
		cached.controllers = service
		cached.flight = target
		event.device = 7
		var output := {engine=Engine.get_version_info().string, os=OS.get_name(), cpu=OS.get_processor_name(), scope="Exact AppRoot methods with inert app fixtures; no renderer, physics, SDL or USB delivery", iterations=2000, rounds=7, production_us_per_event=[], cached_maps_only_us_per_event=[]}
		for warm in 100:
			shell._input(event)
			cached._input(event)
		for round_index in 7:
			for item in ([shell, cached] if round_index % 2 == 0 else [cached, shell]):
				var start := Time.get_ticks_usec()
				for iteration in 2000: item._input(event)
				var elapsed := float(Time.get_ticks_usec() - start) / 2000.0
				if item == shell: output.production_us_per_event.append(elapsed)
				else: output.cached_maps_only_us_per_event.append(elapsed)
		print("HOTPATH_TIMING ", JSON.stringify(output))
		cached.free()
	if shell.binding_resolutions != 7 and not OS.get_cmdline_user_args().has("--measure"):
		printerr("FAIL unexpected production binding-resolution count")
		quit(1)
		return
	shell.free()
	target.session.free()
	target.free()
	service.free()
	print("HOTPATH_AUDIT_COMPLETE")
	quit(0)
