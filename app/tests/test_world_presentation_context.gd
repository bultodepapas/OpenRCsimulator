# FW-79: a temporary workshop world must not leave global presentation state pointed at freed nodes.
extends SceneTree

const World := preload("res://render/world/world.gd")
const Conditions := preload("res://render/world/conditions.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const Exposure := preload("res://render/world/exposure.gd")
const ShaderClock := preload("res://render/shader_clock.gd")

var _checks := 0
var _failures := 0
var _native_compatibility := false


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	_native_compatibility = DisplayServer.get_name() != "headless" \
		and RenderingServer.get_current_rendering_method() == "gl_compatibility"
	call_deferred("_run")


func _run() -> void:
	var baseline: Dictionary = World.presentation_context()
	await _test_flow_lifetime()
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


func _lifetime_world() -> Dictionary:
	var owner := Node3D.new()
	var built := World.build(owner, {id = "flow-lifetime-test", runway = "", surfaces = []},
		Callable(self, "_empty_field"), Conditions.resolve(PackedStringArray([
			"--time=21:00", "--date=2026-10-25", "--time_scale=20"])))
	return {owner = owner, environment = weakref(built.environment), sky = weakref(built.environment.sky),
		material = weakref(built.environment.sky.sky_material)}


func _owned_environment(owner: Node) -> WorldEnvironment:
	for child: Node in owner.get_children():
		if child is WorldEnvironment:
			return child as WorldEnvironment
	return null


func _replacement_resources(owner: Node) -> Dictionary:
	var replacement_environment := Environment.new()
	var replacement_sky := Sky.new()
	var replacement_material := ProceduralSkyMaterial.new()
	replacement_sky.sky_material = replacement_material
	replacement_environment.sky = replacement_sky
	replacement_environment.background_mode = Environment.BG_SKY
	replacement_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	replacement_environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var owned := _owned_environment(owner)
	if owned != null:
		owned.environment = replacement_environment
	return {environment = weakref(replacement_environment), sky = weakref(replacement_sky),
		material = weakref(replacement_material)}


func _await_sky_retirement() -> void:
	if _native_compatibility:
		await RenderingServer.frame_post_draw
		# Continue before the next renderer update so a later retirement in this
		# test cannot connect while frame_post_draw is still dispatching.
		await process_frame


func _test_flow_lifetime() -> void:
	var first := _lifetime_world()
	root.add_child(first.owner)
	var alternate_host := Node3D.new()
	root.add_child(alternate_host)
	root.remove_child(first.owner)
	alternate_host.add_child(first.owner)
	_check("reparenting a retained world preserves its flow", World._flow.get("environment") == first.environment.get_ref())
	alternate_host.remove_child(first.owner)
	root.add_child(first.owner)
	alternate_host.free()
	var second := _lifetime_world()
	first.owner.free()
	_check("freeing an older world preserves the active world", World._flow.get("environment") == second.environment.get_ref())
	second.owner.free() # also covers a world that never entered the scene tree
	_check("freeing the active world releases flow references", World._flow.is_empty())
	_check("discarded worlds release environments immediately", first.environment.get_ref() == null and second.environment.get_ref() == null)
	if _native_compatibility:
		_check("retired skies and materials survive until a draw", first.sky.get_ref() != null and first.material.get_ref() != null
			and second.sky.get_ref() != null and second.material.get_ref() != null)
	else:
		_check("headless discards skies and materials immediately", first.sky.get_ref() == null and first.material.get_ref() == null
			and second.sky.get_ref() == null and second.material.get_ref() == null)
	await _await_sky_retirement()
	_check("discarded worlds release skies and materials after draw", first.sky.get_ref() == null and first.material.get_ref() == null
		and second.sky.get_ref() == null and second.material.get_ref() == null)
	var queued := _lifetime_world()
	root.add_child(queued.owner)
	var discarded_context := World.presentation_context()
	queued.owner.queue_free()
	await process_frame
	await process_frame
	_check("queued destruction clears active flow", World._flow.is_empty())
	_check("queued destruction releases its environment immediately", queued.environment.get_ref() == null)
	_check("a discarded world's context cannot restart its flow", not World.restore_presentation_context(discarded_context))
	await _await_sky_retirement()
	_check("queued destruction releases sky and material after draw", queued.sky.get_ref() == null and queued.material.get_ref() == null)
	var replaced := _lifetime_world()
	root.add_child(replaced.owner)
	var replacement := _replacement_resources(replaced.owner)
	replaced.owner.free()
	_check("replacing the owner's resource clears its original flow and environments", World._flow.is_empty()
		and replaced.environment.get_ref() == null and replacement.environment.get_ref() == null)
	if _native_compatibility:
		_check("both distinct skies survive until the same draw", replaced.sky.get_ref() != null and replaced.material.get_ref() != null
			and replacement.sky.get_ref() != null and replacement.material.get_ref() != null)
	else:
		_check("headless releases both replaced skies immediately", replaced.sky.get_ref() == null and replaced.material.get_ref() == null
			and replacement.sky.get_ref() == null and replacement.material.get_ref() == null)
	await _await_sky_retirement()
	_check("both replaced skies and materials release after draw", replaced.sky.get_ref() == null and replaced.material.get_ref() == null
		and replacement.sky.get_ref() == null and replacement.material.get_ref() == null)

	var superseded := _lifetime_world()
	root.add_child(superseded.owner)
	var superseded_replacement := _replacement_resources(superseded.owner)
	var successor := _lifetime_world()
	root.add_child(successor.owner)
	_check("building a successor keeps its flow active", World._flow.get("environment") == successor.environment.get_ref())
	_check("the prior presentation child keeps its Environment alive", superseded.environment.get_ref() != null)
	superseded.owner.free()
	_check("freeing the superseded owner releases both Environments and preserves successor flow",
		World._flow.get("environment") == successor.environment.get_ref() and superseded.environment.get_ref() == null
		and superseded_replacement.environment.get_ref() == null)
	if _native_compatibility:
		_check("the superseded skies survive until draw after owner release",
			superseded.sky.get_ref() != null and superseded.material.get_ref() != null
			and superseded_replacement.sky.get_ref() != null and superseded_replacement.material.get_ref() != null
			and successor.environment.get_ref() != null)
	else:
		_check("headless releases both superseded skies after owner release",
			superseded.sky.get_ref() == null and superseded.material.get_ref() == null
			and superseded_replacement.sky.get_ref() == null and superseded_replacement.material.get_ref() == null)
	await _await_sky_retirement()
	_check("superseded skies release while successor remains live", superseded.sky.get_ref() == null
		and superseded.material.get_ref() == null and superseded_replacement.sky.get_ref() == null
		and superseded_replacement.material.get_ref() == null and successor.sky.get_ref() != null
		and World._flow.get("environment") == successor.environment.get_ref())
	successor.owner.free()
	_check("freeing the successor releases its environment immediately", successor.environment.get_ref() == null and World._flow.is_empty())
	await _await_sky_retirement()
	_check("successor sky and material release after draw", successor.sky.get_ref() == null and successor.material.get_ref() == null)
