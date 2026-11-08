extends SceneTree
const Activity=preload("res://vehicles/ground/ground_scene.gd")
const Dashboard=preload("res://vehicles/ground/ground_dashboard.gd")
const Registry=preload("res://input/controller_registry.gd")
const UiDriver=preload("res://tests/ui_driver.gd")
const NEUTRAL={throttle=0.0,steering=0.0,brake=0.0,reverse=false,armed=true}
class ExportFixture extends "res://sim/ground_vehicle/session.gd":
	var reject_reset := false
	func reset(selected_spawn_id: String = "") -> bool:
		return false if reject_reset else super.reset(selected_spawn_id)
	var allow_export := false
	var attempts := 0
	func export_recording(_name: String) -> Dictionary:
		attempts += 1
		if not allow_export: return {ok=false,error="injected export failure"}
		_recording_exported=true
		return {ok=true,csv_path="memory://run.csv",metadata_path="memory://run.json"}
var checks:=0
var failures:=0
func check(label: String,passed: bool) -> void:
	checks+=1
	if not passed:
		failures+=1
		printerr("FAIL ",label)
	else: print("ok   ",label)
func _initialize() -> void:
	run.call_deferred()
func settle() -> void:
	for _i in 4: await process_frame
func snapshot(s: Node) -> Dictionary:
	return {tick=s.tick,state=s.state_snapshot().to_byte_array(),controls=s.control_tape_snapshot().to_byte_array(),events=s.event_tape_snapshot(),damage=s.damage_snapshot().to_byte_array(),recovery=s.recovery_actions_snapshot(),paused=s.paused,spawn=s.spawn_id,recording=s.recording,generation=s.recording_generation}
func select(a: Node,id: String) -> void:
	a.dashboard.locations.item_selected.emit(a.dashboard.spawn_ids.find(id))
func run() -> void:
	root.size=Vector2i(1920,1080)
	var ui=UiDriver.new(self)
	for locale in ["en","es"]:
		TranslationServer.set_locale(locale)
		var a=Activity.new()
		a.enable_audio=false
		a.enable_course_visual=false
		a.enable_vehicle_effects=false
		root.add_child(a)
		a.set_process(false)
		a.set_physics_process(false)
		await settle()
		check("activity prepared",a.startup_error.is_empty())
		select(a,"runway_end")
		check("untouched initial start uses fast path",a.session.spawn_id=="runway_end" and a._pending_spawn_id.is_empty() and not a.dashboard.spawn_proposal.visible)
		a.session.tick_once(NEUTRAL)
		a.handle_action("resume")
		for _i in 14: a.session.tick_once(NEUTRAL)
		a.open_garage()
		var before=snapshot(a.session)
		select(a,"track_rollers")
		check("browsing preserves full accepted run",snapshot(a.session)==before and a._pending_spawn_id=="track_rollers" and a.dashboard.spawn_proposal.is_visible_in_tree())
		await settle()
		check("garage proposal stays inside native target bounds",a.dashboard.panel.get_global_rect().end.x<=1920 and a.dashboard.panel.get_global_rect().end.y<=1080)
		check("explicit action names the pending destination",a.dashboard.restart_at_button.text==a.dashboard.tr("Restart at %s")%a.dashboard.locations.get_item_text(a.dashboard.spawn_ids.find("track_rollers")))
		a.dashboard.keep_run_button.grab_focus()
		await settle()
		await ui.tap(KEY_ENTER)
		await settle()
		check("Keep current run cancels without resetting and restores picker focus",snapshot(a.session)==before and a._pending_spawn_id.is_empty() and a.dashboard.locations.has_focus() and a.dashboard.locations.selected==a.dashboard.spawn_ids.find(before.spawn))
		select(a,"track_technical")
		await ui.tap(KEY_ESCAPE)
		check("Back discards only proposed destination",snapshot(a.session)==before and a._pending_spawn_id.is_empty())
		select(a,"track_technical")
		a.handle_action("resume")
		check("Drive resumes current run without accepting destination",a.session.spawn_id==before.spawn and a.session.tick==before.tick and a._pending_spawn_id.is_empty())
		a.open_garage()
		select(a,"track_rollers")
		a.dashboard.restart_at_button.grab_focus()
		await settle()
		await ui.tap(KEY_ENTER)
		await settle()
		check("explicit restart replaces run and synchronizes picker",a.session.tick==0 and a.session.spawn_id=="track_rollers" and a.session.control_tape_snapshot().is_empty() and a.session.paused and a._pending_spawn_id.is_empty() and a.dashboard.locations.selected==a.dashboard.spawn_ids.find("track_rollers"))
		var accepted=snapshot(a.session)
		a._process(0.0)
		var garage_pose=a.camera.transform
		a.handle_action("camera")
		a._process(0.0)
		check("Pilot stand choice explains deferred garage view",a.camera_rig.mode==1 and a.camera.transform==garage_pose and a.dashboard.camera_button.text.contains(a.dashboard.tr("Pilot stand")) and a.dashboard.camera_status.text==a.dashboard.tr("Used when you select Drive."))
		a.handle_action("camera")
		check("Orbit is named",a.camera_rig.mode==2 and a.dashboard.camera_button.text.contains(a.dashboard.tr("Orbit")))
		a.handle_action("track_view")
		a._process(0.0)
		check("overview has immediate selected feedback",a.camera_rig.mode==3 and a.camera.transform!=garage_pose and a.dashboard.overview_button.text==a.dashboard.tr("Return to Chase"))
		a.handle_action("track_view")
		check("overview return names actual Chase destination",a.camera_rig.mode==0 and a.dashboard.camera_button.text.contains(a.dashboard.tr("Chase")))
		check("camera changes did not mutate physical state",snapshot(a.session)==accepted)
		a.handle_action("track_view")
		a.handle_action("reset")
		check("reset reconciles overview label and mode",a.camera_rig.mode==0 and a.dashboard.camera_button.text.contains(a.dashboard.tr("Chase")))

		a.handle_action("recover")
		var recovered=snapshot(a.session)
		select(a,"runway_end" if a.session.spawn_id!="runway_end" else "start")
		check("tick-zero manual recovery cannot take initial fast path",snapshot(a.session)==recovered and not a._pending_spawn_id.is_empty())
		a.handle_action("reset")
		check("Reset clears stale proposed start",a._pending_spawn_id.is_empty() and not a.dashboard.spawn_proposal.visible)
		a._checkpoint=a.session.checkpoint()
		a.handle_action("restore")
		var restored=snapshot(a.session)
		select(a,"runway_end" if a.session.spawn_id!="runway_end" else "start")
		check("restored tick-zero run needs explicit restart",snapshot(a.session)==restored and not a._pending_spawn_id.is_empty())
		a.handle_action("reset")
		a.free()
		await settle()
	TranslationServer.set_locale("en")
	var a=Activity.new()
	var s=ExportFixture.new()
	check("recording fixture prepared",s.prepare_default())
	var dashboard=Dashboard.new()
	root.add_child(dashboard)
	a.session=s
	a.dashboard=dashboard
	a.add_child(s)
	dashboard.spawn_selected.connect(a._select_spawn)
	a._capture_initial_spawn()
	await settle()
	check("recording at tick zero starts",s.start_recording())
	var before=snapshot(s)
	select(a,"jump_start")
	check("tick-zero recording forces a proposal and is not stopped",snapshot(s)==before and s.recording and a._pending_spawn_id=="jump_start" and s.attempts==0)
	a.handle_action("cancel_spawn")
	select(a,s.spawn_id)
	check("same start and Cancel never finalize recording",snapshot(s)==before and s.attempts==0 and a._pending_spawn_id.is_empty())
	s.tick_once(NEUTRAL)
	s.release_pause_hold("garage")
	s.resume()
	for _i in 14: s.tick_once(NEUTRAL)
	a.open_garage()
	select(a,"jump_start")
	var old=snapshot(s)
	a.handle_action("restart_at_spawn")
	check("failed recording export vetoes restart and retains proposal",s.tick==old.tick and s.spawn_id==old.spawn and s.state_snapshot().to_byte_array()==old.state and s.control_tape_snapshot().to_byte_array()==old.controls and s.has_unexported_recording() and a._pending_spawn_id=="jump_start" and s.attempts==1)
	s.allow_export=true
	a.handle_action("restart_at_spawn")
	check("Retry exports then restarts once",s.attempts==2 and s.tick==0 and s.spawn_id=="jump_start" and not s.has_unexported_recording() and a._pending_spawn_id.is_empty())

	select(a,"bump_lane")
	var refused=snapshot(s)
	s.reject_reset=true
	a.handle_action("restart_at_spawn")
	check("reset refusal preserves accepted run and pending destination",snapshot(s)==refused and a._pending_spawn_id=="bump_lane")
	s.reject_reset=false
	a.handle_action("reset")
	check("Reset reconciles pending start after refusal",a._pending_spawn_id.is_empty() and dashboard.locations.selected==dashboard.spawn_ids.find(s.spawn_id))
	a.free()
	dashboard.free()

	var nitro=Activity.new()
	var nitro_session=ExportFixture.new()
	var nitro_dashboard=Dashboard.new()
	root.add_child(nitro_dashboard)
	nitro.session=nitro_session
	nitro.dashboard=nitro_dashboard
	nitro.add_child(nitro_session)
	nitro_dashboard.spawn_selected.connect(nitro._select_spawn)
	check("nitro fixture prepared",nitro_session.prepare_default({},"monster-car-2"))
	nitro._capture_initial_spawn()
	check("tick-zero engine service accepted",nitro_session.service_nitro("stop"))
	var serviced=snapshot(nitro_session)
	select(nitro,"jump_start")
	check("engine service prevents initial fast path",snapshot(nitro_session)==serviced and nitro._pending_spawn_id=="jump_start")
	nitro.free()
	nitro_dashboard.free()
	await settle()
	var source=Registry.new()
	source.update_devices([{id=15,name="Test gamepad",guid="audit5-pad",known=true,kind="gamepad"}])
	source.select_device("flight",15)
	source.select_device("ui",15)
	var pad=Activity.new()
	pad.enable_audio=false
	pad.enable_course_visual=false
	pad.enable_vehicle_effects=false
	pad.use_practice_fixture=true
	pad.controller_registry=source
	pad.joy_axis_reader=func(_id: int,_axis: JoyAxis) -> float: return 0.0
	pad.joy_button_reader=func(_id: int,_button: JoyButton) -> bool: return false
	root.add_child(pad)
	pad.set_process(false)
	pad.set_physics_process(false)
	await settle()
	for _i in 4: pad._physics_process(1.0/240.0)
	pad.handle_action("resume")
	for _i in 14: pad.session.tick_once(NEUTRAL)
	pad.open_garage()
	var pad_before=snapshot(pad.session)
	select(pad,"jump_start")
	pad.dashboard.keep_run_button.grab_focus()
	await settle()
	await ui.joy_button(JOY_BUTTON_A)
	check("selected gamepad activates Keep without resuming",snapshot(pad.session)==pad_before and pad._pending_spawn_id.is_empty() and pad.dashboard.locations.has_focus())
	select(pad,"jump_start")
	var foreign=InputEventJoypadButton.new()
	foreign.device=14
	foreign.button_index=JOY_BUTTON_B
	foreign.pressed=true
	Input.parse_input_event(foreign)
	await settle()
	foreign=foreign.duplicate()
	foreign.pressed=false
	Input.parse_input_event(foreign)
	await settle()
	check("unselected pad cannot cancel pending start",pad._pending_spawn_id=="jump_start" and snapshot(pad.session)==pad_before)
	await ui.joy_button(JOY_BUTTON_B)
	check("selected gamepad Back cancels only destination",pad._pending_spawn_id.is_empty() and snapshot(pad.session)==pad_before)
	pad.free()
	await settle()
	print("RCV start intent: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
