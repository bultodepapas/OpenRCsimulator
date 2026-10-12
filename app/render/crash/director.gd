## CR-09a: owns disposable wreck presentation; never writes aircraft dynamics.
extends Node3D
const Severity = preload("res://render/crash/severity.gd")
const Wreck = preload("res://render/crash/wreck.gd")
const Effects = preload("res://render/crash/effects.gd")
const CrashAudio = preload("res://render/crash/crash_audio.gd")
const Frames = preload("res://render/frames.gd")
const RB = preload("res://physics/rigid_body.gd")
const M = preload("res://physics/math3d.gd")
const SceneryBodies = preload("res://render/landscape_upgrade/scenery_bodies.gd")

var flight: Node3D
var wreck: Wreck
var effects: Effects
var audio: CrashAudio
var active := false
var report: Dictionary = {}
var last_update_usec := 0
var impact_usec := 0
var _fuel_kg := 0.0
var _impact_point := Vector3.ZERO
var _age := 0.0
var _audio_enabled := true
var _scenery_contacts: Node3D

func configure(scene: Node3D, data_path: String, audio_enabled: bool = true) -> void:
	flight = scene
	_audio_enabled = audio_enabled
	wreck = Wreck.new()
	add_child(wreck)
	wreck.prepare(flight._airplane.root)
	wreck.secondary_impact.connect(_secondary)
	effects = Effects.new()
	add_child(effects)
	effects.prepare()
	audio = CrashAudio.new()
	add_child(audio)
	audio.setup()
	# Declared inventory state, not a fuel-burn simulation. Keep source quantity.
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	if raw is Dictionary:
		for item: Dictionary in raw.get("inventory",[]):
			if str(item.get("name","")).begins_with("kerosene +"):
				_fuel_kg += maxf(0.0,float(item.get("mass",{}).get("value",0.0)))
	flight.session.resetting.connect(reset)

func update(delta: float) -> void:
	var began := Time.get_ticks_usec()
	if flight.session.crash.is_empty():
		if active:
			reset()
		return
	if not active:
		_start()
	if not active:
		return
	# Main refreshes the source-airplane shadow each frame before this call.
	# Only the moving wreck's own contact shadows belong in the aftermath.
	flight._shadow.visible = false
	var paused: bool = not flight.session.holds.is_empty()
	wreck.set_paused(paused)
	effects.update(delta,paused)
	audio.update(delta,paused,effects.fire_strength() if _audio_enabled else 0.0)
	if not paused:
		_age += minf(delta,0.1)
	last_update_usec = Time.get_ticks_usec()-began

func _start() -> void:
	var began := Time.get_ticks_usec()
	var impact: RefCounted = flight.session.crash.get("impact")
	if impact == null:
		return
	var s: PackedFloat64Array = impact.detected_state
	if impact.trigger == "scenery" and impact.has_method("contact_state"):
		s = impact.contact_state()
	var q: PackedFloat64Array = s.slice(RB.ATT,RB.ATT+4)
	var v_ned: PackedFloat64Array = M.q_rotate(q,s.slice(RB.VEL,RB.VEL+3))
	var point_velocity: PackedFloat64Array = impact.velocity_ned if impact.has_kinematics else v_ned
	var point: PackedFloat64Array = s.slice(RB.POS,RB.POS+3)
	if impact.has_kinematics:
		point = impact.point_ned
	if impact.crossing != null and impact.crossing.available:
		point = impact.crossing.point_ned
	_impact_point = Frames.ned_to_render(Array(point))
	if impact.trigger != "scenery":
		_impact_point.y = 0.025
	var normal_speed := maxf(0.0,point_velocity[2])
	var tangent_speed := sqrt(point_velocity[0]*point_velocity[0]+point_velocity[1]*point_velocity[1])
	var component := "unknown"
	if impact.trigger == "gear_limit":
		component = "gear"
	elif not impact.body_point.is_empty():
		# Geometric region estimate; hull indices are not semantic model IDs.
		var b: PackedFloat64Array = impact.body_point
		if absf(b[1]) > float(flight.session.aircraft.model.reference.b)*0.28:
			component = "wing"
		elif b[0] < -float(flight.session.aircraft.model.reference.c):
			component = "tail"
		elif b[0] > float(flight.session.aircraft.model.reference.c):
			component = "engine"
		else:
			component = "fuselage"
	var surface := surface_at(flight.field,point[0],point[1])
	report = Severity.estimate(float(flight.session.sim.mass), normal_speed,tangent_speed,rad_to_deg(atan2(normal_speed,tangent_speed)),surface,component)
	if impact.trigger == "scenery":
		# Preserve the actual obstacle normal and height; ground-only projections would misreport a wall hit.
		surface = str(impact.obstacle_kind)
		report = Severity.estimate_snapshot(impact, float(impact.effective_mass_kg), surface, component)
		report["obstacle_id"] = str(impact.obstacle_id)
		report["response_class"] = str(impact.response_class)
		report["effective_mass_kg"] = float(impact.effective_mass_kg)
		report["mass_basis"] = "rigid-body effective mass at the swept contact; material transfer remains estimated"
		_scenery_contacts = SceneryBodies.build_near(flight.session.collision_world(), point)
		add_child(_scenery_contacts)
	report["trigger"] = impact.trigger
	report["component_is_estimate"] = true
	report["component_basis"] = "gear-limit trigger" if impact.trigger == "gear_limit" else "geometric hull region; not a structural section ID"
	report["kinematics"] = "detected rigid contact point" if impact.has_kinematics else "detected CG proxy; deforming gear velocity unavailable"
	report["kinematics_is_proxy"] = not impact.has_kinematics
	report["sample_time"] = "detected_tick_point" if impact.has_kinematics else "detected_tick_CG_proxy"
	if impact.trigger == "scenery":
		report["kinematics"] = "swept contact at time of impact"
		report["sample_time"] = "tick_fraction_%.9f" % float(impact.time_fraction)
	report["mass_kg"] = float(flight.session.sim.mass)
	report["cg_model"] = flight._cg_model
	report["fuel_kg"] = _fuel_kg
	report["fuel_kind"] = "declared inventory; no flight consumption"
	# Presentation estimate, not a simulated tank/joint failure. A damaged wing
	# alone does not imply a ruptured tank; whole-airframe destruction can.
	report["tank_ruptured"] = int(report["class"]) == 4 or (int(report["class"]) == 3 and component in ["fuselage","engine"] and float(report["estimated_energy_j"]) >= 600.0)
	report["tank_rupture_kind"] = "estimated: C4, or C3 central impact >=600 J; uncalibrated"
	report["tick"] = impact.tick
	var velocity := Frames.ned_to_render(Array(v_ned))
	var angular := Frames.ned_to_render(Array(M.q_rotate(q,s.slice(RB.RATE,RB.RATE+3))))
	var pose: Dictionary = flight._current_pose()
	var root_pose := Frames.root_transform(pose.basis,pose.pos,flight._cg_model)
	wreck.start(root_pose,velocity,angular,report)
	flight._airplane.root.visible = false
	flight._shadow.visible = false
	var turbine: bool = flight.session.aircraft.model.propulsion.get("kind","") == "turbine"
	var hot: bool = turbine and flight.session.engine_running and flight.session.sim.aux[0] > 0
	effects.start(_impact_point,velocity,report,_fuel_kg,hot,flight._render_wind(flight.session.sim.time()))
	if _audio_enabled:
		audio.impact(_impact_point,report,turbine)
	active = true
	_age = 0.0
	impact_usec = Time.get_ticks_usec()-began

static func surface_at(field: Dictionary, north: float, east: float) -> String:
	for kind: String in ["runway","mown","rough"]:
		for surface: Dictionary in field.get("surfaces",[]):
			if surface.get("type","") == kind and absf(north-float(surface.center_north)) <= float(surface.width_north_south)*0.5 and absf(east-float(surface.center_east)) <= float(surface.length_east_west)*0.5:
				return kind
	return "rough"

func _secondary(point: Vector3, strength: float) -> void:
	# Wreck signals estimated contact joules; presentation mix consumes [0,1].
	var normalized := clampf(sqrt(maxf(0,strength)/100.0),0,1)
	effects.secondary(point,normalized)
	if _audio_enabled:
		audio.secondary(point,normalized)

func aim(camera: Camera3D, inspect: bool) -> void:
	if not active:
		return
	var target := _impact_point + Vector3.UP*0.5
	if inspect:
		camera.global_position = _impact_point+Vector3(5,3.2,6)
		camera.fov = 58.0
	else:
		camera.fov = maxf(camera.fov,12.0)
	camera.look_at(target,Vector3.UP)

func description() -> String:
	if not active:
		return ""
	var names := ["Contact","Scrape","Damage","Structural breakup","Destroyed"]
	return "%s\nImpact %.1f m/s · %s\nEstimated %s damage\n\n[R] Restart flight   [C] Change view\n[Esc] Menu" % [names[clampi(int(report.get("class",0)),0,4)],float(report.get("speed_mps",0.0)),str(report.get("surface","ground")),str(report.get("component","airframe"))]

func reset() -> void:
	if is_instance_valid(_scenery_contacts):
		_scenery_contacts.free()
	_scenery_contacts = null
	active = false
	report = {}
	_age = 0
	if wreck != null:
		wreck.reset()
	if effects != null:
		effects.reset()
	if audio != null:
		audio.reset()
	if is_instance_valid(flight) and not flight._airplane.is_empty():
		flight._airplane.root.visible = true

func stats() -> Dictionary:
	return {active=active, impact_usec=impact_usec, update_usec=last_update_usec, effects=effects.stats(), wreck=wreck.stats(), report=report.duplicate(true)}
