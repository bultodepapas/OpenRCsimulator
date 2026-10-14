# FW-79: a temporary workshop world must not leave global presentation state pointed at freed nodes.
extends SceneTree

const World := preload("res://render/world/world.gd")
const Conditions := preload("res://render/world/conditions.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const Exposure := preload("res://render/world/exposure.gd")
const ShaderClock := preload("res://render/shader_clock.gd")

var _checks := 0
var _failures := 0


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	var baseline: Dictionary = World.presentation_context()
	var field := {"id": "presentation-context-test", "runway": "", "surfaces": []}
	var previous_owner := Node3D.new()
	previous_owner.name = "PreviousFlowWorld"
	root.add_child(previous_owner)
	var previous_conditions: Dictionary = Conditions.resolve(PackedStringArray([
		"--time_of_day=golden_hour", "--time_scale=20",
	]))
	var previous_built: Dictionary = World.build(previous_owner, field, Callable(self, "_empty_field"), previous_conditions,
		{}, {"field_lighting": "club", "campfire": false})
	var previous_environment: Environment = previous_built.environment
	var previous_sun: DirectionalLight3D = previous_built.sun
	var previous_stars: Node3D = previous_owner.get_node_or_null("Stars") as Node3D
	World.update(previous_environment, 1.5, Vector3(0.5, 0.0, 0.0), Vector3(0.0, 0.0, 0.0))
	var previous_state: Dictionary = Atmosphere.state.duplicate(true)
	var previous_hour := World.flow_hour()
	var previous_exposure := Exposure.last
	var previous_adapt_clock := World._adapt_clock
	var previous_shader_clock := ShaderClock.last_clock
	var previous_shader_wind := ShaderClock.last_wind
	var context: Dictionary = World.presentation_context()
	_check("retained flow context stores weak environment and sun references",
		context.flow.get("environment") is WeakRef and context.flow.get("sun") is WeakRef)
	_check("retained flow world has the expected scene-owned objects",
		previous_environment != null and previous_sun != null and previous_stars != null)

	var trial_owner := Node3D.new()
	trial_owner.name = "TemporaryWorkshopWorld"
	root.add_child(trial_owner)
	var trial_conditions: Dictionary = Conditions.resolve(PackedStringArray([
		"--time_of_day=night", "--time_scale=20",
	]))
	var trial_built: Dictionary = World.build(trial_owner, field, Callable(self, "_empty_field"), trial_conditions,
		{}, {"field_lighting": "off", "campfire": true})
	_check("trial world replaced the active state", not Atmosphere.state.is_empty() and str(Atmosphere.state) != str(previous_state))
	_check("trial flow points to trial environment before teardown", World._flow.get("environment") == trial_built.environment)
	World.update(trial_built.environment, 4.5, Vector3(2.0, 0.0, 0.0))
	trial_owner.free()
	trial_built.clear()
	_check("trial owner has been freed", not is_instance_valid(trial_owner))

	var restored := World.restore_presentation_context(context)
	_check("retained presentation context restores", restored)
	_check("flow hour returns to retained world's step", is_equal_approx(World.flow_hour(), previous_hour))
	_check("atmosphere state returns to retained world", str(Atmosphere.state) == str(previous_state))
	_check("global exposure returns to retained world", is_equal_approx(Exposure.last, previous_exposure))
	_check("eye adaptation clock returns to retained world", is_equal_approx(World._adapt_clock, previous_adapt_clock))
	_check("shader clock and wind return to retained world",
		is_equal_approx(ShaderClock.last_clock, previous_shader_clock) and ShaderClock.last_wind == previous_shader_wind)
	_check("flow references point at retained scene objects",
		World._flow.get("environment") == previous_environment and World._flow.get("sun") == previous_sun
			and World._flow.get("stars") == previous_stars)
	var restored_night: Dictionary = previous_owner.get_meta("night_options", {})
	_check("retained night owner metadata is restored",
		str(restored_night.get("field_lighting", "")) == "club" and not bool(restored_night.get("campfire", true)))
	World.set_night_options("off", false)
	var changed_night: Dictionary = previous_owner.get_meta("night_options", {})
	_check("subsequent night option writes target retained owner",
		str(changed_night.get("field_lighting", "")) == "off")

	var hour_before_update := World.flow_hour()
	World.update(previous_environment, 3.0, Vector3.ZERO, Vector3(0.0, 0.0, 0.0))
	_check("retained flow advances after trial teardown", World.flow_hour() > hour_before_update)
	_check("retained sun follows restored sky state",
		previous_sun.transform.basis.z.distance_to(Atmosphere.sun_direction()) < 1e-4)
	var sky_material: ShaderMaterial = previous_environment.sky.sky_material
	_check("retained environment receives the next sky step",
		sky_material.get_shader_parameter("sun_dir") == Atmosphere.sun_direction())

	previous_owner.free()
	World.restore_presentation_context(baseline)
	Atmosphere.state = {}
	print("world presentation context checks=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _empty_field() -> void:
	pass
