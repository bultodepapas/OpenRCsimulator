## CR-09a: owns disposable wreck presentation; never writes aircraft dynamics.
extends Node3D
const Severity = preload("res://render/crash/severity.gd")
const Wreck = preload("res://render/crash/wreck.gd")
const Effects = preload("res://render/crash/effects.gd")
const CrashAudio = preload("res://render/crash/crash_audio.gd")
const Frames = preload("res://render/frames.gd")
const RB = preload("res://physics/rigid_body.gd")
const EffectiveMass = preload("res://physics/effective_mass.gd")
const M = preload("res://physics/math3d.gd")
const SceneryBodies = preload("res://render/landscape_upgrade/scenery_bodies.gd")
const CrashCause = preload("res://render/crash/cause.gd")
const Telemetry = preload("res://render/overlays/telemetry.gd")
const GroundTerrain = preload("res://physics/ground_terrain.gd")
const AirplaneBuilder = preload("res://render/airplane.gd")

var flight: Node3D
var wreck: Wreck
var effects: Effects
var audio: CrashAudio
var active := false
var report: Dictionary = {}
var last_update_usec := 0
var impact_usec := 0
var _fuel_kg := 0.0
## CR-22b: tagged energy per kind (inventory energy_source), kg.
var energy_sources: Dictionary = {}
## CR-09d1: inventory items as model-frame boxes {mass, center, size} for the wreck's section masses.
var inventory_boxes: Array = []
var _impact_point := Vector3.ZERO
var _age := 0.0
var _audio_enabled := true
var _scenery_contacts: Node3D
## E3d1: per-point time of the last skid mark, so a slide leaves a trail without a mark every frame.
var _touch_marks: Dictionary = {}
## E3d2: the prop strike already shown (its tick), and the propeller node hidden because its blades broke.
var _prop_strike_tick := -1
var _hidden_propeller: Node3D
## CR-01e: the last CrashCause.HISTORY_S of flight, sampled every SAMPLE_INTERVAL_S of sim time (oldest first).
var history: Array = []
const TOUCH_TRAIL_S := 0.12
const TOUCH_SLIDE_MPS := 1.5

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
	effects.set_debris_colors(airframe_colors(flight._airplane.root))
	audio = CrashAudio.new()
	add_child(audio)
	audio.setup()
	# Declared inventory state, not a fuel-burn simulation. CR-22b: energy is read from the explicit
	# energy_source tag, never inferred from a name or the propulsion kind.
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	if raw is Dictionary:
		for item: Dictionary in raw.get("inventory",[]):
			inventory_boxes.append(inventory_box(item, AirplaneBuilder.datum(str(flight.get("aircraft_id")))))
			var kind := str(item.get("energy_source",""))
			if not kind.is_empty():
				energy_sources[kind] = float(energy_sources.get(kind, 0.0)) + maxf(0.0,float(item.get("mass",{}).get("value",0.0)))
	_fuel_kg = float(energy_sources.get("kerosene", 0.0))
	flight.session.resetting.connect(reset)

func update(delta: float) -> void:
	var began := Time.get_ticks_usec()
	if flight.session.crash.is_empty():
		if active:
			reset()
		_record_sample()
		_prop_strike_feedback()
		_touch_feedback()
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
	var model: Dictionary = flight.session.aircraft.model
	var named := component_for(str(impact.trigger), int(impact.point_index), impact.body_point,
		model.get("crash_hull_components", PackedStringArray()), float(model.reference.b), float(model.reference.c))
	var component: String = named.component
	var surface := surface_at(flight.field,point[0],point[1])
	var mass := float(flight.session.sim.mass)
	# CR-08b: the struck point engages only its effective mass; a gear-limit snapshot has no
	# contact point, so it keeps the whole mass (reported by the estimator's mass_basis).
	var effective_mass := -1.0
	if not impact.body_point.is_empty():
		effective_mass = EffectiveMass.at_point(q, impact.body_point, PackedFloat64Array([0.0,0.0,-1.0]), mass, flight.session.sim.inertia)
	# The CG's own normal velocity bounds the slapdown that follows a first contact off the CG.
	report = Severity.estimate(mass, normal_speed,tangent_speed,rad_to_deg(atan2(normal_speed,tangent_speed)),surface,component,effective_mass,1.0,v_ned[2])
	if impact.trigger == "scenery":
		# Preserve the actual obstacle normal and height; ground-only projections would misreport a wall hit.
		surface = str(impact.obstacle_kind)
		var cg_normal := -M.dot(v_ned, impact.normal_ned) if impact.normal_ned.size() == 3 else -1.0
		report = Severity.estimate_snapshot(impact, mass, surface, component, PackedFloat64Array(), float(impact.effective_mass_kg), 1.0, cg_normal)
		report["obstacle_id"] = str(impact.obstacle_id)
		report["response_class"] = str(impact.response_class)
		report["mass_basis"] = "rigid-body effective mass at the swept contact; material transfer remains estimated"
		_scenery_contacts = SceneryBodies.build_near(flight.session.collision_world(true), point)
		add_child(_scenery_contacts)
	report["trigger"] = impact.trigger
	# E3d1: the soft-contact rule ends a flight only at C2 energy (transfer-free), so it never shows as a scrape.
	var soft_rule := str(impact.get("soft_rule")) if impact.get("soft_rule") != null else ""
	if not soft_rule.is_empty():
		report["soft_rule"] = soft_rule
		report["class"] = maxi(int(report.get("class", 0)), 2)
	report["component_is_estimate"] = named.is_estimate
	report["component_basis"] = named.basis
	report["kinematics"] = "detected rigid contact point" if impact.has_kinematics else "detected CG proxy; deforming gear velocity unavailable"
	report["kinematics_is_proxy"] = not impact.has_kinematics
	report["sample_time"] = "detected_tick_point" if impact.has_kinematics else "detected_tick_CG_proxy"
	if impact.trigger == "scenery":
		report["kinematics"] = "swept contact at time of impact"
		report["sample_time"] = "tick_fraction_%.9f" % float(impact.time_fraction)
	report["mass_kg"] = mass
	report["cg_model"] = flight._cg_model
	report["fuel_kg"] = _fuel_kg
	report["fuel_kind"] = "declared inventory; no flight consumption"
	# Presentation estimate, not a simulated tank/joint failure. A damaged wing
	# alone does not imply a ruptured tank; whole-airframe destruction can.
	# Central = the fuselage/engine/propeller groups, so labelled nose, belly and spinner hits count (CR-01d).
	report["tank_ruptured"] = int(report["class"]) == 4 or (int(report["class"]) == 3 and str(report.get("component_group","")) in ["fuselage","engine","propeller"] and float(report["estimated_energy_j"]) >= 600.0)
	report["tank_rupture_kind"] = "estimated: C4, or C3 central impact >=600 J; uncalibrated"
	report["tick"] = impact.tick
	report["inventory_boxes"] = inventory_boxes
	report["prop_broken"] = not flight.session.prop_strike.is_empty()
	# CR-01e: why it happened, from the recorded history (card line and one log line).
	var envelope: Dictionary = flight.session.aircraft.model.get("envelope", {})
	report["cause"] = CrashCause.classify(history, {
		trigger = str(impact.trigger), obstacle_kind = str(impact.get("obstacle_kind")) if impact.get("obstacle_kind") != null else "",
		component_group = str(report.get("component_group", "")), speed_mps = float(report.get("speed_mps", 0.0)),
	}, {stall_alpha_deg = rad_to_deg(float(envelope.a1)) if envelope.has("a1") else INF, start_speed = float(flight.session.aircraft.model.start_speed)})
	if report.prop_broken:
		(report.cause.factors as Array).append("after a prop strike")
	print("CRASH CAUSE: ", CrashCause.line(report.cause))
	# CR-09b: the wreck releases sections in order of distance from this point (render world space).
	report["contact_point_world"] = _impact_point
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
	report["energy"] = Effects.energy_outcome(energy_sources, report, bool(flight.session.engine_running), hot)
	report["energy_sources"] = energy_sources.duplicate()
	effects.apply_energy(report.energy)
	if _audio_enabled:
		audio.impact(_impact_point,report,turbine)
	active = true
	_age = 0.0
	impact_usec = Time.get_ticks_usec()-began

## CR-01d: the struck component. A labelled hull point names it (the nearest hull point, not a structural section);
## without labels, a marked geometric region estimate remains. Gear overtravel is always the gear.
static func component_for(trigger: String, point_index: int, body_point: PackedFloat64Array,
		labels: PackedStringArray, span: float, chord: float) -> Dictionary:
	if trigger == "gear_limit":
		return {component = "gear", is_estimate = true, basis = "gear-limit trigger"}
	if point_index >= 0 and point_index < labels.size():
		return {component = labels[point_index], is_estimate = false,
			basis = "aircraft data crash_hull_components label of the struck hull point; not a structural section ID"}
	if body_point.size() != 3:
		return {component = "unknown", is_estimate = true, basis = "no struck hull point"}
	var component := "fuselage"
	if absf(body_point[1]) > span*0.28:
		component = "wing"
	elif body_point[0] < -chord:
		component = "tail"
	elif body_point[0] > chord:
		component = "engine"
	return {component = component, is_estimate = true, basis = "geometric hull region; crash_hull_components unavailable"}

## E3d2: blade fragments, a crack and the engine dying once per strike; the source blades disappear.
func _prop_strike_feedback() -> void:
	var strike: Dictionary = flight.session.prop_strike
	if strike.is_empty() or int(strike.tick) == _prop_strike_tick:
		return
	_prop_strike_tick = int(strike.tick)
	var point := Frames.ned_to_render(Array(strike.point_ned))
	var velocity := Frames.ned_to_render(Array(strike.velocity_ned))
	effects.prop_break(point, velocity, surface_at(flight.field, strike.point_ned[0], strike.point_ned[1]))
	if _audio_enabled:
		audio.prop_strike(point)
	var propeller: Variant = flight._airplane.get("propeller")
	if propeller is Node3D and is_instance_valid(propeller):
		_hidden_propeller = propeller
		_hidden_propeller.visible = false


## CR-01e: one history sample per SAMPLE_INTERVAL_S of sim time, from the HUD's 64-bit telemetry. A restart or a
## rewind (time going backwards) clears the history; a paused session adds nothing.
func _record_sample() -> void:
	var session: Node = flight.session
	if session.sim == null or not session.aircraft.get("ok", false):
		return
	var t: float = session.sim.time()
	if not history.is_empty():
		var last_t := float(history.back().t)
		if t < last_t:
			history.clear()
		elif t < last_t + CrashCause.SAMPLE_INTERVAL_S:
			return
	var s: PackedFloat64Array = session.sim.state
	var air: Dictionary = session.air_data(s, t)
	var ground: PackedFloat64Array = GroundTerrain.sample(s[0], s[1], session.ground_surfaces)
	var telemetry := Telemetry.compute(s, session.wind_at(t), air, {terrain_up = ground[0], last_loads = session.sim.last_loads,
		mass = session.sim.mass, gravity = session.sim.gravity, throttle = session.sim.inputs[3], time_s = t})
	history.append(CrashCause.sample(t, telemetry, s[RB.RATE], s[RB.RATE + 2], session.engine_running))
	while not history.is_empty() and float(history[0].t) < t - CrashCause.HISTORY_S:
		history.pop_front()


## CR-09d1: one inventory item (le frame [x_aft, y_right, z_up] from the datum) as a model-frame box (+x right, +y up,
## −z nose), with the same datum conversion as the CG (Frames.cg_in_model_frame).
static func inventory_box(item: Dictionary, datum: Vector2) -> Dictionary:
	var p: Array = item.get("position", {}).get("value", [0.0, 0.0, 0.0])
	var size: Array = item.get("size", {}).get("value", [0.0, 0.0, 0.0])
	return {mass = maxf(0.0, float(item.get("mass", {}).get("value", 0.0))),
		center = Frames.cg_in_model_frame(PackedFloat64Array([float(p[0]), float(p[1]), float(p[2])]), datum.x, datum.y),
		size = Vector3(absf(float(size[1])), absf(float(size[2])), absf(float(size[0])))}


## CR-03b: up to six distinct albedo colours of the airplane's own materials, most-used first, so crash chips look
## like its covering. Dark and transparent materials (tyres, hardware, canopy glass) are skipped.
const CHIP_MIN_LUMINANCE := 0.12
static func airframe_colors(root: Node) -> Array:
	var counts := {}
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_active_material(surface) as BaseMaterial3D
			if material == null or material.albedo_color.a < 0.9:
				continue
			var key := Color(snappedf(material.albedo_color.r, 0.05), snappedf(material.albedo_color.g, 0.05), snappedf(material.albedo_color.b, 0.05))
			if key.get_luminance() < CHIP_MIN_LUMINANCE:
				continue
			counts[key] = int(counts.get(key, 0)) + 1
	var colors: Array = counts.keys()
	colors.sort_custom(func(a: Color, b: Color) -> bool: return counts[a] > counts[b] or (counts[a] == counts[b] and a.to_html() < b.to_html()))
	return colors.slice(0, 6)


## E3d1: marks, puffs and sounds for soft hull contacts while the flight continues. New touches are sized by the
## struck point's normal speed; slides leave a trail paced by TOUCH_TRAIL_S. Reads the session feed only.
func _touch_feedback() -> void:
	var contacts: Array = flight.session.soft_contacts
	if contacts.is_empty():
		_touch_marks.clear()
		return
	var now := Time.get_ticks_msec() / 1000.0
	for contact: Dictionary in contacts:
		var point := Frames.ned_to_render(Array(contact.point_ned))
		var velocity := Frames.ned_to_render(Array(contact.velocity_ned))
		var surface := surface_at(flight.field, contact.point_ned[0], contact.point_ned[1])
		var slide := float(contact.slide_speed_mps)
		if bool(contact.new):
			var strength := clampf(float(contact.normal_speed_mps) / 3.0, 0.1, 1.0)
			effects.touch(point, velocity, strength, surface)
			if _audio_enabled:
				audio.touch(point, strength, slide > TOUCH_SLIDE_MPS, surface)
			_touch_marks[contact.index] = now
		elif slide > TOUCH_SLIDE_MPS and now - float(_touch_marks.get(contact.index, -INF)) >= TOUCH_TRAIL_S:
			effects.mark(Vector3(point.x, 0.0, point.z), velocity, 0.08)
			if _audio_enabled:
				audio.touch(point, clampf(slide / 15.0, 0.05, 0.6), true, surface)
			_touch_marks[contact.index] = now

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
	var names := ["Touch, no damage","Scrape","Damage","Structural breakup","Destroyed"]
	var cause_line := "\nCause: %s" % CrashCause.line(report.cause) if report.has("cause") else ""
	return "%s\nImpact %.1f m/s · %s\nEstimated %s damage%s\n\n[R] Restart flight   [C] Change view\n[Esc] Menu" % [names[clampi(int(report.get("class",0)),0,4)],float(report.get("speed_mps",0.0)),str(report.get("surface","ground")),str(report.get("component","airframe")),cause_line]

func reset() -> void:
	history.clear()
	_prop_strike_tick = -1
	if is_instance_valid(_hidden_propeller):
		_hidden_propeller.visible = true
	_hidden_propeller = null
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
