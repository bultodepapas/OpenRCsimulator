extends SceneTree

const Rig := preload("res://render/lighting/aircraft_lighting_rig_3d.gd")
const Profile := preload("res://render/lighting/lighting_profile.gd")
const StockAircraftBuilder := preload("res://render/airplane.gd")

func _initialize() -> void:
	call_deferred("_run")

func _step_sequence(rig: Node, advancing: bool) -> Dictionary:
	var total_writes := 0
	var frames_with_writes := 0
	var max_visible := 0
	var total_bindings := 0
	var telemetry := {"effects_allowed":true, "exposure":1.0, "throttle":0.5, "airspeed":20.0, "distance_m":10.0}
	rig.advance(1.0, telemetry)
	for frame in range(1, 61):
		rig.advance(1.0 + frame / 60.0 if advancing else 1.0, telemetry)
		var this_frame := int(rig.budget_info().frame_parameter_writes)
		total_writes += this_frame
		if this_frame > 0: frames_with_writes += 1
		var visible := 0
		total_bindings = 0
		for binding: Dictionary in rig._materials:
			if binding.kind not in ["steady", "strip"]: continue
			total_bindings += 1
			if binding.node.is_visible_in_tree(): visible += 1
		max_visible = maxi(max_visible, visible)
	return {"calls":60, "writes":total_writes, "active_write_frames":frames_with_writes,
		"lamp_and_strip_bindings":total_bindings, "max_visible_bindings":max_visible}

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var plane := StockAircraftBuilder.build(StockAircraftBuilder.STIK_ID)
	if plane.is_empty():
		printerr("Stock aircraft failed to build")
		quit(1)
		return
	stage.add_child(plane.root)
	var rig := Rig.new()
	stage.add_child(rig)
	var configured := rig.configure(plane.root, Profile.preset("festival"))
	if not configured.ok:
		printerr("Festival profile refused ", configured)
		quit(1)
		return
	rig.set_mode("off", 1.0)
	var same := _step_sequence(rig, false)
	var moving := _step_sequence(rig, true)
	rig.set_mode("all", 1.0)
	var enabled := _step_sequence(rig, true)
	var profile := Profile.defaults()
	profile.selection = "disabled"
	var disabled_config := rig.configure(plane.root, profile)
	var disabled := _step_sequence(rig, true)
	print("RGB_OFF_OBSERVATION ", JSON.stringify({"aircraft":StockAircraftBuilder.STIK_ID,"festival_off_paused":same,
		"festival_off_advancing":moving,"festival_all_advancing":enabled,"profile_disabled_advancing":disabled}))
	var ok: bool = configured.ok and disabled_config.ok and same.writes == 0 and moving.writes > 0 \
		and moving.active_write_frames == 60 and moving.max_visible_bindings == 0 \
		and enabled.max_visible_bindings > 0 and disabled.writes == 0
	rig.dispose()
	stage.free()
	if ok: print("HIDDEN_RGB_SHADER_WRITES_CONFIRMED")
	quit(0 if ok else 1)
