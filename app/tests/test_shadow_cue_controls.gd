## VQ-04b: V and saved cue precedence, plus detached projector source lifecycle.
extends SceneTree

const Main := preload("res://main.gd")
const Shadow := preload("res://render/shadow.gd")
const ShadowSettings := preload("res://render/shadow_settings.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error("shadow cue controls: " + label)


func _select(technique: String, cue: String, quality: String = "current") -> void:
	ShadowSettings.apply({"shadow_technique": technique, "shadow_aircraft_cue": cue, "shadow_quality": quality})


func _press_v(flight: Node) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_V
	event.pressed = true
	flight._unhandled_input(event)


func _flight_modes() -> void:
	_select("auto", "sun")
	var flight := Main.new()
	flight.interactive_start = true
	flight._initialize_shadow_mode({})
	_check("interactive flight initializes from the saved cue", flight._shadow_mode == "sun")
	_press_v(flight)
	flight._sync_shadow_preference()
	_check("V selects vertical without the saved Sun overriding it", flight._shadow_mode == "vertical")
	_select("auto", "sun", "low")
	flight._sync_shadow_preference()
	_check("changing quality preserves the V selection", flight._shadow_mode == "vertical")
	_press_v(flight)
	_check("V then selects off", flight._shadow_mode == "off")
	_press_v(flight)
	_check("V cycles back to sun", flight._shadow_mode == "sun")
	_select("auto", "off", "low")
	flight._sync_shadow_preference()
	_check("a changed preference applies to the running flight", flight._shadow_mode == "off")
	_press_v(flight)
	flight._sync_shadow_preference()
	_check("V can enable the cue after a saved Off", flight._shadow_mode == "sun")
	_select("auto", "vertical", "low")
	flight._sync_shadow_preference()
	_check("selecting Vertical updates the local mode", flight._shadow_mode == "vertical")
	_select("auto", "auto", "low")
	flight._sync_shadow_preference()
	_check("selecting Automatic restores the default cue", flight._shadow_mode == "sun")
	flight.free()

	_select("auto", "off")
	var direct := Main.new()
	direct.interactive_start = false
	direct._initialize_shadow_mode({"shadow": "vertical"})
	_check("direct CLI starts with its explicit cue", direct._shadow_mode == "vertical")
	_select("auto", "sun")
	direct._sync_shadow_preference()
	_check("direct CLI ignores saved cue changes", direct._shadow_mode == "vertical")
	_press_v(direct)
	_check("V remains available after an explicit launch cue", direct._shadow_mode == "off")
	direct.free()
	var direct_default := Main.new()
	direct_default.interactive_start = false
	_select("auto", "off")
	direct_default._initialize_shadow_mode({})
	_check("direct launch without a cue ignores interactive preferences", direct_default._shadow_mode == "sun")
	direct_default.free()
	var explicit_interactive := Main.new()
	explicit_interactive.interactive_start = true
	explicit_interactive._initialize_shadow_mode({"shadow": "vertical"})
	_select("auto", "sun")
	explicit_interactive._sync_shadow_preference()
	_check("an explicit launch cue outranks interactive settings", explicit_interactive._shadow_mode == "vertical")
	explicit_interactive.free()


func _model(name: String) -> Node3D:
	var model := Node3D.new()
	model.name = name
	var geometry := MeshInstance3D.new()
	geometry.mesh = BoxMesh.new()
	model.add_child(geometry)
	return model


func _projector_lifecycle() -> void:
	_select("auto", "off")
	var host := Node3D.new()
	root.add_child(host)
	var model := _model("Aircraft")
	host.add_child(model)
	var carrier := Shadow.create(host)
	Shadow.bind_model(carrier, model)
	var projected: Node = carrier.get_node("ProjectedShadow")
	var receiver: MeshInstance3D = projected.get("receiver")
	var viewport: SubViewport = projected.get("viewport")
	var mask: ShaderMaterial = projected.get("mask_material")
	var sun := Vector3(0.4, 0.8, -0.3).normalized()
	Shadow.update(carrier, Basis.IDENTITY, Vector3(1, 3, 2), 2.0, 2.0, sun, 1.0, "sun")
	_check("a flight-local Sun cue overrides saved Off", receiver.visible
		and (mask.get_shader_parameter("light_direction") as Vector3).is_equal_approx(sun))
	Shadow.update(carrier, Basis.IDENTITY, Vector3(1, 3, 2), 2.0, 2.0, sun, 1.0, "vertical")
	_check("flight-local Vertical points straight up", receiver.visible and mask.get_shader_parameter("light_direction") == Vector3.UP)
	_select("auto", "off", "low")
	_check("settings replay retains the flight-local Vertical override", receiver.visible
		and mask.get_shader_parameter("light_direction") == Vector3.UP)
	Shadow.update(carrier, Basis.IDENTITY, Vector3(1, 3, 2), 2.0, 2.0, sun, 1.0, "off")
	_select("auto", "sun", "low")
	_check("flight-local Off remains off through a policy change", not receiver.visible
		and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	Shadow.update(carrier, Basis.IDENTITY, Vector3(1, 3, 2), 2.0, 2.0, sun, 1.0, "sun")
	_select("native", "sun", "low")
	_check("Native suppresses even an explicit flight-local cue", not receiver.visible
		and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	_select("off", "sun", "low")
	_check("master Off also suppresses the flight-local cue", not receiver.visible)
	_select("projected", "off", "low")
	_check("projected route restores the same flight-local cue", receiver.visible
		and (mask.get_shader_parameter("light_direction") as Vector3).is_equal_approx(sun))

	host.remove_child(model)
	_check("detaching a source immediately hides its projector", not receiver.visible
		and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED
		and not bool(projected.get("_last_request")[3]))
	_select("projected", "off", "high")
	model.visible = false
	model.visible = true
	_check("policy and visibility changes cannot revive a detached source", not receiver.visible
		and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED
		and not bool(projected.get("_last_request")[3]))
	host.add_child(model)
	_check("reattaching a source restores the still-requested cue", receiver.visible
		and viewport.render_target_update_mode == SubViewport.UPDATE_ONCE)
	carrier.visible = false
	host.remove_child(model)
	host.add_child(model)
	_check("source reattachment does not revive a hidden carrier", not receiver.visible
		and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	carrier.visible = true
	_check("showing the carrier restores its cue", receiver.visible)
	model.free()
	_select("auto", "sun")
	_check("a freed source cannot be revived by a policy update", not receiver.visible
		and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	host.free()

	var detached := Node3D.new()
	var detached_model := _model("DetachedAircraft")
	detached.add_child(detached_model)
	var detached_carrier := Shadow.create(detached)
	Shadow.bind_model(detached_carrier, detached_model)
	var detached_projected: Node = detached_carrier.get_node("ProjectedShadow")
	Shadow.update(detached_carrier, Basis.IDENTITY, Vector3(0, 2, 0), 2.0, 2.0, sun, 1.0, "sun")
	_check("detached construction still accepts a valid source", (detached_projected.get("receiver") as MeshInstance3D).visible)
	root.add_child(detached)
	_check("a constructed projector stays visible when its scene enters the tree", (detached_projected.get("receiver") as MeshInstance3D).visible)
	detached.free()


func _run() -> void:
	_flight_modes()
	_projector_lifecycle()
	_select("auto", "auto")
	await process_frame
	print("Shadow cue controls: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)
