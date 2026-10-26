extends SceneTree

const Rig := preload("res://render/lighting/aircraft_lighting_rig_3d.gd")
const Profile := preload("res://render/lighting/lighting_profile.gd")
const AircraftLights := preload("res://render/world/aircraft_lights.gd")
const LightingPolicy := preload("res://render/lighting/lighting_policy.gd")
const SceneBudget := preload("res://render/lighting/lighting_scene_budget.gd")
const Magnifier := preload("res://render/camera/magnifier.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var saved_quality: String = LightingPolicy.quality
	var saved_reduced_flashes: bool = LightingPolicy.reduced_flashes
	var saved_show_vfx: bool = LightingPolicy.show_vfx
	LightingPolicy.quality = "high"
	LightingPolicy.reduced_flashes = false
	LightingPolicy.show_vfx = true

	var world := World3D.new()
	var viewport := SubViewport.new()
	viewport.name = "LightingVfxLodViewport"
	viewport.size = Vector2i(1920, 1080)
	viewport.world_3d = world
	root.add_child(viewport)
	var stage := Node3D.new()
	stage.name = "LightingVfxLodStage"
	viewport.add_child(stage)
	var camera := Camera3D.new()
	camera.name = "PerspectiveCamera"
	camera.current = true
	stage.add_child(camera)
	var aircraft := _make_aircraft(stage)
	var rig := Rig.new()
	rig.name = "LightingVfxLodRig"
	stage.add_child(rig)
	var profile: Dictionary = Profile.preset("festival")
	profile.effects[0].kind = "trail"
	var configured: Dictionary = rig.configure(aircraft, profile)
	_check("real NightKit configures one spark and one trail pool", bool(configured.get("ok", false))
		and rig._vfx._effects.size() == 2
		and rig._vfx._effects.any(func(pool: Dictionary) -> bool: return str(pool.get("kind", "")) == "trail")
		and rig._vfx._effects.any(func(pool: Dictionary) -> bool: return str(pool.get("kind", "")) == "spark"))
	var magnifier := Magnifier.new()
	magnifier.mode = "on"
	viewport.add_child(magnifier)
	await process_frame
	var vfx: Variant = rig._vfx
	var spark_pool: Dictionary = _pool_for_kind(vfx, "spark")
	var trail_pool: Dictionary = _pool_for_kind(vfx, "trail")
	_check("idle LOD rig keeps its configured CPU pools without GPU instance buffers",
		int(vfx.budget_info().effects_cpu_allocated) == 2
			and int(vfx.budget_info().gpu_anchors_allocated) == 0
			and int(spark_pool.instance.multimesh.instance_count) == 0
			and int(trail_pool.instance.multimesh.instance_count) == 0)
	var synthetic_particle := {
		"origin": Vector3.ZERO,
		"velocity": Vector3.RIGHT,
		"size": 0.025,
		"start": 0.0,
		"life": 2.0,
		"color": Color.WHITE,
	}
	spark_pool["particles"] = [synthetic_particle]
	var writes_before_denied_update := int(spark_pool.get("gpu_instance_writes", 0))
	vfx._update_sparks(spark_pool, 0.25, 1.0, 1.0)
	var denied_origin: Vector3 = spark_pool.visual_transforms[0].origin
	vfx._update_sparks(spark_pool, 0.5, 1.0, 1.0)
	_check("unallocated spark buffer tracks and ages bounded CPU particles without instance writes",
		int(spark_pool.get("live_visual_count", 0)) == 1
			and denied_origin.distance_to(spark_pool.visual_transforms[0].origin) > 0.1
			and int(spark_pool.instance.multimesh.instance_count) == 0
			and int(spark_pool.instance.multimesh.visible_instance_count) == 0
			and int(spark_pool.get("gpu_instance_writes", 0)) == writes_before_denied_update
			and int(vfx.budget_info().sparks_allocated) == 0
			and int(vfx.budget_info().sparks_cpu_live) == 1)
	spark_pool["particles"] = []
	vfx._update_sparks(spark_pool, 0.6, 1.0, 1.0)

	var perspective: Dictionary = vfx._measure_projected_view()
	_check("perspective projection measures the actual viewport span",
		bool(perspective.get("ok", false)) and bool(perspective.get("visible", false))
			and is_finite(float(perspective.get("span_px", NAN))) and float(perspective.span_px) > 0.0)
	var perspective_span := float(perspective.get("span_px", 0.0))
	camera.fov = 35.0
	var perspective_zoomed: Dictionary = vfx._measure_projected_view()
	_check("perspective FOV zoom increases projected span", float(perspective_zoomed.span_px) > perspective_span * 1.5)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.0
	var orthographic: Dictionary = vfx._measure_projected_view()
	var orthographic_span := float(orthographic.span_px)
	camera.size = 8.0
	var orthographic_zoomed_out: Dictionary = vfx._measure_projected_view()
	_check("orthographic size affects the measured pixel span", orthographic_span > float(orthographic_zoomed_out.span_px) * 1.8)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 70.0

	_test_lod_hysteresis(vfx)
	_test_quality_density(vfx, spark_pool)

	# A second active camera resets only LOD history; displayed time and VFX event state stay intact.
	rig.advance(1.0, _telemetry(10.0, 0.5))
	var clock_before: float = vfx._last_seconds
	var cue_before: String = vfx._last_cue_key
	var event_before := int(spark_pool.get("event_count", 0))
	var second_camera := Camera3D.new()
	second_camera.name = "SecondCamera"
	second_camera.fov = 55.0
	stage.add_child(second_camera)
	second_camera.make_current()
	vfx._update_projected_lod()
	_check("camera change refreshes only projected tier history",
		vfx._lod_camera_id == second_camera.get_instance_id() and vfx._last_seconds == clock_before
			and vfx._last_cue_key == cue_before and int(spark_pool.get("event_count", 0)) == event_before)
	camera.current = true
	vfx._update_projected_lod()
	_check("switching back to the first camera does not restart displayed clocks",
		vfx._lod_camera_id == camera.get_instance_id() and vfx._last_seconds == clock_before
			and vfx._last_cue_key == cue_before)

	# Samples are finite and follow live world-space trail and spark points away from the aircraft.
	rig.advance(1.05, _telemetry(10.0, 0.5))
	aircraft.position.x = 2.0
	rig.advance(1.15, _telemetry(10.0, 0.5))
	rig.advance(1.16, _telemetry(10.0, 0.5))
	var trail_samples: Array = trail_pool.get("samples", [])
	var trail_instance: MultiMeshInstance3D = trail_pool.get("instance")
	var trail_bounds: AABB = trail_instance.custom_aabb
	_check("live trail bounds enclose both world-space samples away from the aircraft",
		trail_samples.size() >= 2 and trail_instance.multimesh.visible_instance_count > 0
			and trail_bounds.is_finite() and trail_bounds.has_point(trail_samples[0].position)
			and trail_bounds.has_point(trail_samples[-1].position)
			and trail_instance.multimesh.custom_aabb == trail_bounds)
	_check("budget reports the actual allocated trail capacity and separate CPU samples",
		int(vfx.budget_info().trails_allocated) == trail_instance.multimesh.instance_count
			and int(vfx.budget_info().trails_cpu_live) == trail_samples.size()
			and int(vfx.budget_info().gpu_anchors_allocated) == 1)

	rig.advance(1.6, _telemetry(10.0, 1.0))
	rig.advance(1.61, _telemetry(10.0, 1.0))
	_check("spark pool has active residual particles", spark_pool.particles.size() > 0
		and int(spark_pool.instance.multimesh.visible_instance_count) > 0)
	var particles: Array = spark_pool.particles
	var first_particle: Dictionary = particles[0]
	first_particle.velocity = Vector3(80.0, 0.0, 0.0)
	particles[0] = first_particle
	spark_pool.particles = particles
	rig.advance(1.7, _telemetry(10.0, 1.0))
	var residual_age := 1.7 - float(first_particle.get("start", 1.7))
	var residual_point: Vector3 = first_particle.origin + first_particle.velocity * residual_age \
		+ Vector3.DOWN * (0.5 * 1.4 * residual_age * residual_age)
	var spark_instance: MultiMeshInstance3D = spark_pool.get("instance")
	var spark_bounds: AABB = spark_instance.custom_aabb
	_check("spark culling bounds follow residual points that move away from aircraft bounds",
		spark_instance.multimesh.visible_instance_count > 0 and spark_bounds.is_finite()
			and spark_bounds.has_point(residual_point) and spark_instance.multimesh.custom_aabb == spark_bounds
			and spark_bounds.size.length() < 100.0)

	# Offscreen aircraft suppresses new births only. Existing world particles keep aging and stay in finite bounds.
	var events_before_offscreen := int(spark_pool.get("event_count", 0))
	var existing_particle_count: int = spark_pool.particles.size()
	aircraft.position.x = 1000.0
	rig.advance(1.8, _telemetry(10.0, 0.0))
	spark_pool["last_event_time"] = -INF # Exclude the cooldown as a reason for a skipped birth.
	rig.advance(1.9, _telemetry(10.0, 1.0))
	_check("offscreen aircraft does not emit new sparks or hide live residuals",
		not vfx._aircraft_in_view and vfx._lod_birth_density == 0.0
			and int(spark_pool.get("event_count", 0)) == events_before_offscreen
			and spark_pool.particles.size() == existing_particle_count
			and spark_instance.multimesh.visible_instance_count > 0 and spark_instance.visible
			and spark_instance.custom_aabb.is_finite())
	rig.advance(3.0, _telemetry(10.0, 0.0))
	_check("expired residuals clear visible count and custom culling bounds",
		spark_instance.multimesh.visible_instance_count == 0 and spark_instance.custom_aabb == AABB()
			and spark_instance.multimesh.custom_aabb == AABB())

	# A visible inset is an additional aircraft-specific view for projected LOD and VFX distance fade.
	magnifier.update(camera, aircraft.global_position, 1.0, aircraft, true)
	await process_frame
	magnifier.update(camera, aircraft.global_position, 1.0, aircraft, true)
	vfx._update_projected_lod()
	var main_offscreen: Dictionary = vfx._measure_projected_view()
	_check("the main camera is outside the aircraft while the inset camera shares its world",
		not bool(main_offscreen.get("visible", true)) and magnifier.camera.get_world_3d() == aircraft.get_world_3d())
	_check("a visible inset preserves useful projected LOD when the main view is outside",
		vfx._lod_camera_id == magnifier.camera.get_instance_id() and vfx._aircraft_in_view
			and vfx._lod_birth_density > 0.0 and bool(vfx._inset_projection.get("visible", false)))
	_check("detached VFX meshes join the inset render layer only while it is shown",
		(spark_pool.instance.layers & Magnifier.LAYER) != 0)
	aircraft.position = Vector3(0.0, 0.0, -500.0)
	magnifier.update(camera, aircraft.global_position, 1.0, aircraft, true)
	vfx._update_projected_lod()
	var tiny_main: Dictionary = vfx._measure_projected_view()
	_check("main-view Tiny aircraft still gets useful inset LOD and projection",
		bool(tiny_main.get("visible", false)) and float(tiny_main.get("span_px", INF)) < 12.0
			and vfx._lod_camera_id == magnifier.camera.get_instance_id()
			and vfx._aircraft_in_view and vfx._lod_birth_density > 0.0,
		"main=%s inset=%s selected=%d/%d tier=%s density=%.2f" % [str(tiny_main), str(vfx._inset_projection),
			vfx._lod_camera_id, magnifier.camera.get_instance_id(), vfx._lod_tier, vfx._lod_birth_density])
	aircraft.position = Vector3(1000.0, 0.0, -10.0)
	magnifier.update(camera, aircraft.global_position, 1.0, aircraft, true)
	vfx.reset()
	vfx.set_mode("all")
	rig.advance(4.0, _telemetry(500.0, 1.0))
	_check("useful inset distance keeps distant-main-view VFX births active without changing spill range",
		vfx._distance_fade > 0.0 and spark_pool.particles.size() > 0
			and vfx._spill_fade == 0.0 and int(vfx.budget_info().spill_light_limit) == 2)
	var old_world_vfx: Node3D = vfx._world_root
	var reconfigured_live: Dictionary = rig.configure(aircraft, profile)
	vfx = rig._vfx
	var spark_pool_reconfigured := _pool_for_kind(vfx, "spark")
	magnifier.update(camera, aircraft.global_position, 1.0, aircraft, true)
	_check("live VFX reconfigure replaces detached roots and refreshes inset layers without toggling it",
		bool(reconfigured_live.get("ok", false)) and magnifier.shown and not is_instance_valid(old_world_vfx)
			and is_instance_valid(vfx._world_root) and not spark_pool_reconfigured.is_empty()
			and (spark_pool_reconfigured.instance.layers & Magnifier.LAYER) != 0,
		"configured=%s vfx_root=%s pool_count=%d" % [str(reconfigured_live), str(is_instance_valid(vfx._world_root)), spark_pool_reconfigured.size()])
	spark_pool = spark_pool_reconfigured

	var aircraft_two := _make_aircraft(stage)
	aircraft_two.position = Vector3(-1000.0, 0.0, -10.0)
	var rig_two := Rig.new()
	rig_two.name = "LightingVfxLodRigTwo"
	stage.add_child(rig_two)
	var configured_two: Dictionary = rig_two.configure(aircraft_two, profile)
	var vfx_two: Variant = rig_two._vfx
	var spark_pool_two := _pool_for_kind(vfx_two, "spark")
	_check("second aircraft keeps its own detached VFX root", bool(configured_two.get("ok", false))
		and is_instance_valid(vfx_two._world_root) and vfx_two._root != vfx._root,
		"configured=%s effects=%d" % [str(configured_two), vfx_two._effects.size()])
	# Main-camera changes do not merge either aircraft's LOD eligibility into the other actor.
	magnifier.update(camera, aircraft.global_position, 1.0, aircraft, true)
	vfx._update_projected_lod()
	vfx_two._update_projected_lod()
	_check("inset eligibility stays per aircraft while targeting the first model",
		vfx._aircraft_in_view and vfx._lod_birth_density > 0.0
			and not vfx_two._aircraft_in_view and vfx_two._lod_birth_density == 0.0
			and (spark_pool.instance.layers & Magnifier.LAYER) != 0
			and not spark_pool_two.is_empty() and (spark_pool_two.instance.layers & Magnifier.LAYER) == 0,
		"first=%s density=%s second=%s pools=%d" % [str(vfx._aircraft_in_view), str(vfx._lod_birth_density), str(vfx_two._aircraft_in_view), spark_pool_two.size()])
	magnifier.update(camera, aircraft_two.global_position, 1.0, aircraft_two, true)
	vfx._update_projected_lod()
	vfx_two._update_projected_lod()
	_check("switching the inset target transfers projection and detached VFX eligibility",
		not vfx._aircraft_in_view and vfx._lod_birth_density == 0.0
			and vfx_two._aircraft_in_view and vfx_two._lod_birth_density > 0.0
			and (spark_pool.instance.layers & Magnifier.LAYER) == 0
			and not spark_pool_two.is_empty() and (spark_pool_two.instance.layers & Magnifier.LAYER) != 0)
	magnifier.mode = "off"
	magnifier.update(camera, aircraft_two.global_position, 1.0, aircraft_two, true)
	vfx_two._update_projected_lod()
	_check("hidden inset falls back to the main camera and clears detached VFX layer",
		vfx_two._lod_camera_id == camera.get_instance_id() and not vfx_two._aircraft_in_view
			and vfx_two._lod_birth_density == 0.0 and Magnifier.camera_for_actor(aircraft_two) == null
			and not spark_pool_two.is_empty() and (spark_pool_two.instance.layers & Magnifier.LAYER) == 0)
	magnifier.mode = "on"
	magnifier.update(camera, aircraft_two.global_position, 1.0, aircraft_two, true)
	var freed_inset_camera := magnifier.camera
	freed_inset_camera.free()
	vfx_two._update_projected_lod()
	_check("freed inset falls back to the main camera without affecting the view clock",
		vfx_two._lod_camera_id == camera.get_instance_id() and not vfx_two._aircraft_in_view
			and vfx_two._lod_birth_density == 0.0 and vfx_two._last_seconds == -1.0)
	magnifier.free()
	rig_two.dispose()
	rig_two.free()
	aircraft_two.free()
	var last_live_time: float = vfx._last_seconds
	var last_cue_key: String = vfx._last_cue_key
	camera.free()
	second_camera.free()
	vfx._update_projected_lod()
	_check("missing-camera fallback uses legacy near density without restarting time",
		vfx._lod_tier == "near" and vfx._lod_birth_density == 1.0 and vfx._aircraft_in_view
			and vfx._last_seconds == last_live_time and vfx._last_cue_key == last_cue_key)

	rig.dispose()
	rig.free()
	viewport.free()
	world = null
	SceneBudget._prune_world_registry()
	LightingPolicy.quality = saved_quality
	LightingPolicy.reduced_flashes = saved_reduced_flashes
	LightingPolicy.show_vfx = saved_show_vfx
	print("lighting VFX LOD checks=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_lod_hysteresis(vfx: Variant) -> void:
	vfx._apply_projected_view(181.0, true, 1001)
	_check("projected span above 180 px starts in Near tier", vfx._lod_tier == "near")
	vfx._apply_projected_view(170.0, true, 1001)
	_check("Near tier hysteresis holds through its exit band", vfx._lod_tier == "near")
	vfx._apply_projected_view(161.0, true, 1001)
	_check("Near tier exits below its hysteresis band", vfx._lod_tier == "medium")
	vfx._apply_projected_view(55.0, true, 1001)
	_check("Medium tier holds above its lower exit threshold", vfx._lod_tier == "medium")
	vfx._apply_projected_view(53.0, true, 1001)
	_check("Medium tier steps down to Far below its exit threshold", vfx._lod_tier == "far")
	vfx._apply_projected_view(10.0, true, 1001)
	_check("Far tier steps down to Tiny", vfx._lod_tier == "tiny" and vfx._lod_birth_density == 0.0)
	vfx._apply_projected_view(13.0, true, 1001)
	_check("Tiny tier holds within its entry band", vfx._lod_tier == "tiny")
	vfx._apply_projected_view(14.0, true, 1001)
	_check("Tiny tier restores Far only beyond hysteresis", vfx._lod_tier == "far")
	vfx._apply_projected_view(100.0, true, 2002)
	_check("new camera ID classifies immediately rather than reusing old hysteresis", vfx._lod_tier == "medium")
	vfx._apply_projected_view(100.0, true, -2002)
	_check("negative engine camera instance IDs remain valid projection sources", vfx._lod_camera_id == -2002 and vfx._lod_tier == "medium")


func _test_quality_density(vfx: Variant, spark_pool: Dictionary) -> void:
	var saved_quality: String = LightingPolicy.quality
	LightingPolicy.quality = "standard"
	vfx._apply_projected_view(100.0, true, 3003)
	spark_pool["last_event_time"] = -INF
	vfx._trigger_sparks(spark_pool, 4.0, 4.0, false, 1.0)
	_check("Standard quality times Medium LOD produces one quarter of near High births",
		spark_pool.particles.size() == 5 and vfx._lod_birth_density == 0.5)
	LightingPolicy.quality = "high"
	vfx._apply_projected_view(220.0, true, 3003)
	spark_pool["last_event_time"] = -INF
	vfx._trigger_sparks(spark_pool, 5.0, 5.0, false, 1.0)
	_check("High quality Near tier keeps full spark birth density", spark_pool.particles.size() == 20)
	LightingPolicy.quality = "standard"
	vfx._apply_projected_view(30.0, true, 3004)
	spark_pool["last_event_time"] = -INF
	vfx._trigger_sparks(spark_pool, 6.0, 6.0, false, 1.0)
	_check("Standard quality Far tier reduces spark births again", spark_pool.particles.size() == 3)
	spark_pool["particles"] = []
	spark_pool["event_count"] = 0
	spark_pool["last_event_time"] = -INF
	vfx._event_serial = 0
	LightingPolicy.quality = saved_quality


func _make_aircraft(parent: Node3D) -> Node3D:
	var aircraft := Node3D.new()
	aircraft.name = "LightingVfxLodAircraft"
	aircraft.position = Vector3(0.0, 0.0, -10.0)
	parent.add_child(aircraft)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.12, 0.9)
	body.mesh = box
	aircraft.add_child(body)
	AircraftLights.attach(aircraft)
	return aircraft


func _pool_for_kind(vfx: Variant, kind: String) -> Dictionary:
	for pool: Dictionary in vfx._effects:
		if str(pool.get("kind", "")) == kind:
			return pool
	return {}


func _telemetry(distance_m: float, maneuver: float) -> Dictionary:
	return {"distance_m": distance_m, "maneuver": maneuver, "effects_allowed": true, "exposure": 1.0}


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])
