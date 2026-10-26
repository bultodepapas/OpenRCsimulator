## CR-09a: owns disposable wreck presentation; never writes aircraft dynamics.
extends Node3D
const Severity = preload("res://render/crash/severity.gd")
const Wreck = preload("res://render/crash/wreck.gd")
const Effects = preload("res://render/crash/effects.gd")
const ShaderWarmup = preload("res://render/crash/shader_warmup.gd")
const CrashAudio = preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp19-hull-scrape/draft/crash_audio.gd")
const Frames = preload("res://render/frames.gd")
const PropBreak = preload("res://render/crash/prop_break.gd")
const AirframeScuffs = preload("res://render/crash/airframe_scuffs.gd")
const RB = preload("res://physics/rigid_body.gd")
const EffectiveMass = preload("res://physics/effective_mass.gd")
const SceneryCollision = preload("res://sim/scenery_collision.gd")
const M = preload("res://physics/math3d.gd")
const SceneryBodies = preload("res://render/landscape_upgrade/scenery_bodies.gd")
const CrashCause = preload("res://render/crash/cause.gd")
const Telemetry = preload("res://render/overlays/telemetry.gd")
const GroundTerrain = preload("res://physics/ground_terrain.gd")
const AirplaneBuilder = preload("res://render/airplane.gd")
const WaterEffects = preload("res://render/lake/water_effects.gd")
const PresentationContext = preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp19-hull-scrape/draft/presentation_context.gd")
const WATER_CHECKPOINT_VERSION := 1
const WATER_CHECKPOINT_FIELDS: Array[String] = ["version", "age_s", "event_count", "impact_point_world", "report", "effects"]
const WATER_REPORT_FIELDS: Array[String] = ["trigger", "surface", "component", "speed_mps", "impact_depth_m", "water_level_down_m", "tick", "contact_point_world", "lake_id", "water_effects_started", "water_audio_enabled"]
const FUEL_SOURCE_KINDS: Array[String] = ["glow_fuel", "gasoline", "kerosene"]
const FUEL_FAMILY_SOURCES := {"glow": "glow_fuel", "gasoline": "gasoline", "kerosene": "kerosene"}

var context: PresentationContext
var wreck: Wreck
var effects: Effects
var audio: CrashAudio
var water_effects: WaterEffects
var active := false
var _water_active := false
var report: Dictionary = {}
var last_update_usec := 0
var impact_usec := 0
var shader_warmup: Dictionary = {}
## Legacy scalar kept for the kerosene fire path; report fuel quantities use `fuel_by_kind_kg`.
var _kerosene_fuel_kg := 0.0
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
var _touch_feedback_tick := -1
## E3d2: the prop strike already shown (its tick); US-V11: what the strike changed on the propeller (PropBreak records).
var _prop_strike_tick := -1
var _broken_propeller: Array = []
## US-V12: scuffs left on the airframe by soft contacts; cleared on restart.
var scuffs := AirframeScuffs.new()
var _water_configured := false
var _water_lake_identity := ""
var _water_event_count := 0
var _water_checkpoint_latched := false
var _water_shadow: MeshInstance3D
var _water_shadow_was_visible := false
var _water_blur: Node3D
var _water_blur_was_processing := false
var _configured := false
var _hull_capture_ready := false
## CR-01e: the last CrashCause.HISTORY_S of flight, sampled every SAMPLE_INTERVAL_S of sim time (oldest first).
var history: Array = []
const TOUCH_TRAIL_S := 0.12
const TOUCH_SLIDE_MPS := 1.5

func configure(next_context: PresentationContext, audio_enabled: bool = true) -> bool:
	if _configured or next_context == null or not next_context.is_valid():
		return false
	context = next_context
	_audio_enabled = audio_enabled
	wreck = Wreck.new()
	add_child(wreck)
	wreck.prepare(context.model_bindings.root)
	scuffs.prepare(context.model_bindings.root)
	wreck.secondary_impact.connect(_secondary)
	effects = Effects.new()
	add_child(effects)
	effects.ground_sampler = _sample_mark_ground
	effects.prepare()
	effects.set_debris_colors(airframe_colors(context.model_bindings.root))
	audio = CrashAudio.new()
	add_child(audio)
	audio.setup()
	audio.set_accepted_hull_observation(_audio_enabled)
	water_effects = WaterEffects.new()
	water_effects.name = "WaterEffects"
	add_child(water_effects)
	_configure_water_effects()
	# Declared inventory state, not a fuel-burn simulation. CR-22b: energy is read from the explicit
	# energy_source tag, never inferred from a name or the propulsion kind.
	var trial: Dictionary = context.workshop_trial
	var raw: Variant = JSON.parse_string(trial.raw_bytes.get_string_from_utf8()) if not trial.is_empty() else JSON.parse_string(FileAccess.get_file_as_string(context.aircraft_data_path))
	var datum: Vector2 = AirplaneBuilder.datum(context.aircraft_id) * float(trial.get("scale", 1.0))
	if raw is Dictionary:
		for item: Dictionary in raw.get("inventory",[]):
			inventory_boxes.append(inventory_box(item, datum))
			var kind := str(item.get("energy_source",""))
			if not kind.is_empty():
				energy_sources[kind] = float(energy_sources.get(kind, 0.0)) + maxf(0.0,float(item.get("mass",{}).get("value",0.0)))
	_kerosene_fuel_kg = float(energy_sources.get("kerosene", 0.0))
	_connect_reset_signal()
	shader_warmup = ShaderWarmup.prepare(self, effects, wreck._shadows[0], context.sun)
	_configured = true
	return true


func _enter_tree() -> void:
	if _configured:
		_connect_reset_signal()


func _exit_tree() -> void:
	_disconnect_reset_signal()


func _connect_reset_signal() -> void:
	_connect_hull_signals()
	if context != null and is_instance_valid(context.session) and context.session.has_signal("resetting") \
			and not context.session.resetting.is_connected(reset):
		context.session.resetting.connect(reset)


func _disconnect_reset_signal() -> void:
	_disconnect_hull_signals()
	if context != null and is_instance_valid(context.session) and context.session.has_signal("resetting") \
			and context.session.resetting.is_connected(reset):
		context.session.resetting.disconnect(reset)


func _hide_source_shadow() -> void:
	if context != null and is_instance_valid(context.shadow):
		context.shadow.visible = false

func update(delta: float) -> void:
	if not _configured or context == null:
		return
	var began := Time.get_ticks_usec()
	if context.session.crash.is_empty():
		if _water_checkpoint_latched and _water_active:
			var paused: bool = not context.session.holds.is_empty()
			_hide_source_shadow()
			water_effects.update(delta, paused)
			if not paused:
				_age += minf(delta, 0.1)
			if float(water_effects.checkpoint().get("elapsed_s", 0.0)) >= WaterEffects.MAX_EFFECT_DURATION_S:
				reset()
			last_update_usec = Time.get_ticks_usec() - began
			return
		if active:
			reset()
		_record_sample()
		_prop_strike_feedback()
		_touch_feedback()
		audio.update(delta, context.session.sim.paused or not context.session.holds.is_empty(), 0.0)
		return
	if _water_checkpoint_latched:
		# A later replayed collision supersedes the restored render-only aftermath.
		reset()
	audio.cancel_hull_scrape()
	if not active:
		_start()
	if not active:
		return
	var paused: bool = not context.session.holds.is_empty()
	if _water_active:
		# Main refreshes the source shadow each frame; aftermath follows user holds, not the crash physics hold.
		_hide_source_shadow()
		water_effects.update(delta, paused)
		if not paused:
			_age += minf(delta, 0.1)
		last_update_usec = Time.get_ticks_usec()-began
		return
	# Main refreshes the source-airplane shadow each frame before this call.
	# Only the moving wreck's own contact shadows belong in the aftermath.
	_hide_source_shadow()
	wreck.set_paused(paused)
	effects.update(delta,paused)
	audio.update(delta,paused,effects.fire_strength() if _audio_enabled else 0.0)
	if not paused:
		_age += minf(delta,0.1)
	last_update_usec = Time.get_ticks_usec()-began

func _start() -> void:
	var began := Time.get_ticks_usec()
	var impact: RefCounted = context.session.crash.get("impact")
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
	if impact.trigger != "water" and impact.crossing != null and impact.crossing.available:
		point = impact.crossing.point_ned
	if impact.trigger == "water":
		_start_water(impact, point, point_velocity, began)
		return
	_impact_point = Frames.ned_to_render(Array(point))
	if impact.trigger not in ["scenery", "lake_bank"]:
		_impact_point.y = 0.025
	var normal_speed := maxf(0.0,point_velocity[2])
	var tangent_speed := sqrt(point_velocity[0]*point_velocity[0]+point_velocity[1]*point_velocity[1])
	var model: Dictionary = context.session.aircraft.model
	var named := component_for(str(impact.trigger), int(impact.point_index), impact.body_point,
		model.get("crash_hull_components", PackedStringArray()), float(model.reference.b), float(model.reference.c))
	var component: String = named.component
	var surface := surface_at(context.field,point[0],point[1])
	# Prefer the swept-contact sample used by a dynamic scenery/water response. Its
	# within-step inventory is linearly interpolated and remains an approximation.
	# Static hull/gear snapshots have no sample, so finite-fuel reports use the accepted endpoint.
	var endpoint_live: Dictionary = context.session.mass_properties() if context.session.has_method("mass_properties") else {}
	var selected_mass: Dictionary = _select_mass_sample(impact, endpoint_live)
	var live: Dictionary = selected_mass.get("sample", {})
	var mass_sample_basis := str(selected_mass.get("basis", "unavailable"))
	var mass_is_dynamic := bool(selected_mass.get("dynamic", false))
	var live_ok: bool = live.get("ok", false)
	var mass := float(live.mass_kg) if live_ok else float(context.session.sim.mass)
	# CR-08b: the struck point engages only its effective mass; a gear-limit snapshot has no
	# contact point, so it keeps the whole mass (reported by the estimator's mass_basis).
	var effective_mass := -1.0
	if not impact.body_point.is_empty():
		if live_ok and (mass_is_dynamic or bool(live.get("finite_fuel", false))):
			# The contact arm is measured from the live CG, not the fixed datum (R05-B).
			effective_mass = float(EffectiveMass.at_point_properties(q, impact.body_point, PackedFloat64Array([0.0,0.0,-1.0]), live).effective_mass_kg)
		else:
			effective_mass = EffectiveMass.at_point(q, impact.body_point, PackedFloat64Array([0.0,0.0,-1.0]), mass, context.session.sim.inertia)
	# The CG's own normal velocity bounds the slapdown that follows a first contact off the CG.
	# X8-08: a tolerant airframe (EPO foam) declares its presentation durability; balsa/ply keep 1.
	var durability := float(model.get("crash_tolerance", {}).get("presentation_durability", 1.0))
	report = Severity.estimate(mass, normal_speed,tangent_speed,rad_to_deg(atan2(normal_speed,tangent_speed)),surface,component,effective_mass,durability,v_ned[2])
	if impact.trigger == "scenery":
		# Preserve the actual obstacle normal and height; ground-only projections would misreport a wall hit.
		surface = str(impact.obstacle_kind)
		var cg_normal := -M.dot(v_ned, impact.normal_ned) if impact.normal_ned.size() == 3 else -1.0
		report = Severity.estimate_snapshot(impact, mass, surface, component, PackedFloat64Array(), float(impact.effective_mass_kg), durability, cg_normal)
		report["obstacle_id"] = str(impact.obstacle_id)
		report["response_class"] = str(impact.response_class)
		report["mass_basis"] = "rigid-body effective mass at the swept contact; material transfer remains estimated"
		_scenery_contacts = SceneryBodies.build_near(context.session.collision_world(true), point)
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
	report["cg_model"] = context.cg_model
	report["cg_offset_body_m"] = live.cg_body_m.duplicate() if live_ok else PackedFloat64Array([0.0, 0.0, 0.0])
	report["mass_sample_basis"] = mass_sample_basis
	if live.has("sample_boundary"):
		report["mass_sample_boundary"] = str(live.sample_boundary)
	if live.has("impact_fraction") and typeof(live.impact_fraction) in [TYPE_FLOAT, TYPE_INT] \
			and is_finite(float(live.impact_fraction)):
		report["mass_sample_impact_fraction"] = float(live.impact_fraction)
	if live.has("tick"):
		report["mass_sample_tick"] = int(live.tick)
	else:
		report["mass_sample_tick"] = int(impact.tick)
	if live.has("time_s") and typeof(live.time_s) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(live.time_s)):
		report["mass_sample_time_s"] = float(live.time_s)
	elif impact is SceneryCollision.Event and is_finite(float(impact.time_fraction)) and impact.time_fraction >= 0.0:
		report["mass_sample_tick_fraction"] = float(impact.time_fraction)
	# Contact collision samples may expose mass properties before the canonical store list is available.
	# Keep the typed fuel inventory honest by labeling an accepted endpoint sample in that case.
	var fuel_sample: Dictionary = live.duplicate(true)
	if mass_is_dynamic:
		fuel_sample["finite_fuel"] = true
	var fuel_sample_basis := mass_sample_basis
	if not _sample_has_fuel_inventory(fuel_sample) and endpoint_live.get("ok", false) \
			and bool(endpoint_live.get("finite_fuel", false)):
		fuel_sample = endpoint_live
		fuel_sample_basis = "accepted-endpoint-approximation"
	report["fuel_sample_basis"] = fuel_sample_basis
	var tanks: Array = context.session.aircraft.model.get("fuel_system", {}).get("tanks", [])
	var sources: Dictionary = _energy_sources_at_sample(fuel_sample, energy_sources, tanks)
	var fuel_by_kind_kg: Dictionary = {}
	for kind: String in FUEL_SOURCE_KINDS:
		if sources.has(kind):
			fuel_by_kind_kg[kind] = maxf(0.0, float(sources[kind]))
	report["fuel_by_kind_kg"] = fuel_by_kind_kg
	# Backward-compatible scalar semantics: this is kerosene only, never total onboard fuel.
	report["fuel_kg"] = _kerosene_fuel_kg
	report["fuel_kind"] = "kerosene"
	report["fuel_kg_basis"] = "declared inventory; legacy kerosene-only scalar"
	# Presentation estimate, not a simulated tank/joint failure. A damaged wing
	# alone does not imply a ruptured tank; whole-airframe destruction can.
	# Central = the fuselage/engine/propeller groups, so labelled nose, belly and spinner hits count (CR-01d).
	report["tank_ruptured"] = int(report["class"]) == 4 or (int(report["class"]) == 3 and str(report.get("component_group","")) in ["fuselage","engine","propeller"] and float(report["estimated_energy_j"]) >= 600.0)
	report["tank_rupture_kind"] = "estimated: C4, or C3 central impact >=600 J; uncalibrated"
	report["tick"] = impact.tick
	report["inventory_boxes"] = inventory_boxes
	report["prop_broken"] = not context.session.prop_strike.is_empty()
	# CR-01e: why it happened, from the recorded history (card line and one log line).
	var envelope: Dictionary = context.session.aircraft.model.get("envelope", {})
	report["cause"] = CrashCause.classify(history, {
		trigger = str(impact.trigger), obstacle_kind = str(impact.get("obstacle_kind")) if impact.get("obstacle_kind") != null else "",
		component_group = str(report.get("component_group", "")), speed_mps = float(report.get("speed_mps", 0.0)),
	}, {stall_alpha_deg = rad_to_deg(float(envelope.a1)) if envelope.has("a1") else INF, start_speed = float(context.session.aircraft.model.start_speed)})
	if report.prop_broken:
		(report.cause.factors as Array).append("after a prop strike")
	print("CRASH CAUSE: ", CrashCause.line(report.cause))
	# CR-09b: the wreck releases sections in order of distance from this point (render world space).
	report["contact_point_world"] = _impact_point
	var velocity := Frames.ned_to_render(Array(v_ned))
	var angular := Frames.ned_to_render(Array(M.q_rotate(q,s.slice(RB.RATE,RB.RATE+3))))
	var pose: Dictionary = context.current_pose()
	var root_pose := Frames.root_transform(pose.basis,pose.pos,context.cg_model)
	wreck.start(root_pose,velocity,angular,report)
	context.model_bindings.root.visible = false
	_hide_source_shadow()
	var turbine: bool = context.session.aircraft.model.propulsion.get("kind","") == "turbine"
	var hot: bool = turbine and context.session.engine_running and context.session.sim.aux[0] > 0
	effects.start(_impact_point,velocity,report,_kerosene_fuel_kg,hot,context.render_wind(context.session.sim.time()))
	report["energy"] = Effects.energy_outcome(sources, report, bool(context.session.engine_running), hot)
	report["energy_sources"] = sources.duplicate()
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


func _configure_water_effects() -> bool:
	if water_effects == null or context == null or context.session == null:
		return false
	var lake: Dictionary = context.session.lake_context()
	if lake.is_empty():
		_water_configured = false
		_water_lake_identity = ""
		return false
	var identity := str(lake.get("identity", ""))
	if _water_configured and identity == _water_lake_identity:
		return true
	_water_configured = water_effects.configure(lake, _audio_enabled)
	_water_lake_identity = identity if _water_configured else ""
	return _water_configured


func _start_water(impact: RefCounted, point_ned: PackedFloat64Array,
		point_velocity_ned: PackedFloat64Array, began_usec: int) -> void:
	_impact_point = Frames.ned_to_render(Array(point_ned))
	var lake: Dictionary = context.session.lake_context()
	var mean_down := float(lake.get("water_level_down_m", point_ned[2]))
	var depth := maxf(0.0, point_ned[2] - mean_down)
	var speed := sqrt(point_velocity_ned[0] * point_velocity_ned[0]
		+ point_velocity_ned[1] * point_velocity_ned[1] + point_velocity_ned[2] * point_velocity_ned[2])
	var effects_started := _configure_water_effects() and water_effects.begin(impact, context.model_bindings.root)
	if audio != null:
		audio.reset() # water uses its own single licensed splash voice, never dry impact layers
	if effects != null:
		effects.reset()
	if wreck != null:
		wreck.reset()
	_suppress_water_aircraft_presentation()
	report = {
		"trigger": "water",
		"surface": "water",
		"component": "airframe",
		"speed_mps": speed,
		"impact_depth_m": depth,
		"water_level_down_m": mean_down,
		"tick": int(impact.tick),
		"contact_point_world": _impact_point,
		"lake_id": str(lake.get("id", "")),
		"water_effects_started": effects_started,
		"water_audio_enabled": _audio_enabled,
	}
	_water_active = true
	_water_event_count += 1
	active = true
	_age = 0.0
	impact_usec = Time.get_ticks_usec() - began_usec


## Capture only the water aftermath, not a general crash/director save format.
## Empty means there is no started water effect worth placing beside a physics replay.
func water_checkpoint() -> Dictionary:
	if not _water_active or water_effects == null:
		return {}
	var effects_state: Dictionary = water_effects.checkpoint()
	if not bool(effects_state.get("has_event", false)):
		return {}
	return {
		"version": WATER_CHECKPOINT_VERSION,
		"age_s": _age,
		"event_count": _water_event_count,
		"impact_point_world": _impact_point,
		"report": report.duplicate(true),
		"effects": effects_state,
	}


## Preflight without changing the live director or the aircraft render root.
func prepare_water_restore(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY or not _water_configured or water_effects == null or not water_effects._configured:
		return {}
	var state: Dictionary = raw
	if not _exact_keys(state, WATER_CHECKPOINT_FIELDS) or state.get("version") != WATER_CHECKPOINT_VERSION:
		return {}
	var age: Variant = state.get("age_s")
	var event_count: Variant = state.get("event_count")
	var point: Variant = state.get("impact_point_world")
	var saved_report: Variant = state.get("report")
	if not _finite_number(age) or float(age) < 0.0 or float(age) > 1.0e12 \
			or typeof(event_count) != TYPE_INT or int(event_count) < 1 or int(event_count) > 2_147_483_647 \
			or typeof(point) != TYPE_VECTOR3 or not _finite_vector3(point) \
			or typeof(saved_report) != TYPE_DICTIONARY or not _exact_keys(saved_report, WATER_REPORT_FIELDS):
		return {}
	var effects_state: Dictionary = water_effects.prepare_restore(state.get("effects"))
	if effects_state.is_empty() or not bool(effects_state.get("has_event", false)):
		return {}
	var point_ned: PackedFloat64Array = effects_state.point_ned
	var expected_point: Vector3 = Frames.ned_to_render(Array(point_ned))
	var lake_id: String = str(water_effects._lake.get("id", ""))
	var saved_contact: Variant = saved_report.get("contact_point_world")
	var speed: Variant = saved_report.get("speed_mps")
	var depth: Variant = saved_report.get("impact_depth_m")
	var water_level: Variant = saved_report.get("water_level_down_m")
	var tick: Variant = saved_report.get("tick")
	if saved_report.get("trigger") != "water" or saved_report.get("surface") != "water" \
			or saved_report.get("component") != "airframe" \
			or not _finite_number(speed) or float(speed) < 0.0 or float(speed) > 1000.0 \
			or not _finite_number(depth) or absf(float(depth) - float(effects_state.impact_depth_m)) > 1.0e-6 \
			or not _finite_number(water_level) or absf(float(water_level) - water_effects._water_level_down_m) > 1.0e-6 \
			or typeof(tick) != TYPE_INT or int(tick) < 0 \
			or typeof(saved_contact) != TYPE_VECTOR3 or not _finite_vector3(saved_contact) \
			or saved_contact.distance_to(expected_point) > 0.001 or point.distance_to(expected_point) > 0.001 \
			or saved_report.get("lake_id") != lake_id \
			or saved_report.get("water_effects_started") != true \
			or typeof(saved_report.get("water_audio_enabled")) != TYPE_BOOL \
			or bool(saved_report.water_audio_enabled) != bool(effects_state.impact_audio_emitted):
		return {}
	return {
		"version": WATER_CHECKPOINT_VERSION,
		"age_s": float(age),
		"event_count": int(event_count),
		"impact_point_world": point,
		"report": saved_report.duplicate(true),
		"effects": effects_state,
	}


## Restore visuals only; WaterEffects.restore deliberately leaves the splash player stopped.
func restore_water_checkpoint(raw: Variant) -> bool:
	var prepared: Dictionary = prepare_water_restore(raw)
	if prepared.is_empty() or context == null or context.model_bindings == null or not context.model_bindings.has_aircraft():
		return false
	reset()
	if not _configure_water_effects():
		return false
	var aircraft_root: Node3D = context.model_bindings.root
	if not water_effects.restore(prepared.effects, aircraft_root):
		return false
	_impact_point = prepared.impact_point_world
	_age = float(prepared.age_s)
	_water_event_count = int(prepared.event_count)
	_water_active = true
	_water_checkpoint_latched = true
	active = true
	report = prepared.report.duplicate(true)
	if audio != null:
		audio.reset()
	if effects != null:
		effects.reset()
	if wreck != null:
		wreck.reset()
	_suppress_water_aircraft_presentation()
	aircraft_root.visible = true
	return true


func _suppress_water_aircraft_presentation() -> void:
	if context != null and is_instance_valid(context.shadow):
		_water_shadow = context.shadow
		_water_shadow_was_visible = _water_shadow.visible
		_water_shadow.visible = false
	_water_blur = context.propeller_blur
	if is_instance_valid(_water_blur) and _water_blur.has_method("update"):
		_water_blur_was_processing = _water_blur.is_processing()
		_water_blur.set_process(false)
		_water_blur.call("update", 0.0)
	else:
		_water_blur = null
		_water_blur_was_processing = false


static func _exact_keys(source: Dictionary, expected: Array[String]) -> bool:
	if source.size() != expected.size():
		return false
	for key: Variant in source.keys():
		if typeof(key) != TYPE_STRING or not expected.has(str(key)):
			return false
	return true


static func _finite_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and is_finite(float(value))


static func _finite_vector3(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z) \
			and absf(value.x) <= 1_100_000.0 and absf(value.y) <= 1_100_000.0 and absf(value.z) <= 1_100_000.0

## E3d2: blade fragments, a crack and the engine dying once per strike; the blades break off (US-V11: stubs remain
## where the model declares them, otherwise the whole propeller disappears).
func _prop_strike_feedback() -> void:
	var strike: Dictionary = context.session.prop_strike
	if strike.is_empty() or int(strike.tick) == _prop_strike_tick:
		return
	_prop_strike_tick = int(strike.tick)
	var point := Frames.ned_to_render(Array(strike.point_ned))
	var velocity := Frames.ned_to_render(Array(strike.velocity_ned))
	effects.prop_break(point, velocity, surface_at(context.field, strike.point_ned[0], strike.point_ned[1]))
	if _audio_enabled:
		audio.prop_strike(point)
	var propeller: Variant = context.model_bindings.propeller
	if propeller is Node3D and is_instance_valid(propeller):
		_broken_propeller = PropBreak.break_blades(propeller)


## CR-01e: one history sample per SAMPLE_INTERVAL_S of sim time, from the HUD's 64-bit telemetry. A restart or a
## rewind (time going backwards) clears the history; a paused session adds nothing.
func _record_sample() -> void:
	var session: Node = context.session
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
	var live: Dictionary = session.mass_properties() if session.has_method("mass_properties") else {}
	var telemetry := Telemetry.compute(s, session.wind_at(t), air, {terrain_up = ground[0], last_loads = session.sim.last_loads,
		mass = float(live.mass_kg) if live.get("ok", false) else session.sim.mass, gravity = session.sim.gravity,
		throttle = session.sim.inputs[3], time_s = t})
	history.append(CrashCause.sample(t, telemetry, s[RB.RATE], s[RB.RATE + 2], session.engine_running))
	while not history.is_empty() and float(history[0].t) < t - CrashCause.HISTORY_S:
		history.pop_front()


static func _select_mass_sample(impact: Variant, endpoint: Dictionary) -> Dictionary:
	if impact is SceneryCollision.Event:
		var contact: Dictionary = impact.contact_mass_properties
		var valid: Dictionary = EffectiveMass.validate_properties(contact)
		if valid.get("ok", false):
			var basis := "impact-contact-approximation"
			if str(contact.get("sample_boundary", "")) == "swept_contact_linear_inventory":
				basis = "swept-contact-linear-inventory-approximation"
			return {sample = contact, basis = basis, dynamic = true}
	if endpoint.get("ok", false):
		var finite: bool = bool(endpoint.get("finite_fuel", false))
		return {sample = endpoint, basis = "accepted-endpoint-approximation" if finite else "constant-build",
			dynamic = finite}
	return {sample = {}, basis = "unavailable", dynamic = false}


static func _sample_has_fuel_inventory(sample: Dictionary) -> bool:
	if not bool(sample.get("finite_fuel", false)):
		return false
	if sample.get("stores") is Array and not sample.stores.is_empty():
		return true
	return sample.get("store_amounts_by_id") is Dictionary or sample.get("remaining_mass_kg_by_id") is Dictionary


static func _energy_sources_at_sample(sample: Dictionary, baseline: Dictionary, tanks: Array) -> Dictionary:
	var sources: Dictionary = baseline.duplicate(true)
	if not bool(sample.get("finite_fuel", false)):
		return sources
	var totals: Dictionary = {}
	var stores: Variant = sample.get("stores")
	if stores is Array:
		for store: Variant in stores:
			if not store is Dictionary:
				continue
			var source: String = str(FUEL_FAMILY_SOURCES.get(str(store.get("family", "")), ""))
			var amount: Variant = store.get("remaining_kg")
			if source.is_empty() or typeof(amount) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(amount)):
				continue
			totals[source] = float(totals.get(source, 0.0)) + maxf(0.0, float(amount))
	else:
		var by_id: Variant = sample.get("store_amounts_by_id", sample.get("remaining_mass_kg_by_id"))
		if not by_id is Dictionary:
			return sources
		for tank: Variant in tanks:
			if not tank is Dictionary:
				continue
			var source: String = str(FUEL_FAMILY_SOURCES.get(str(tank.get("family", "")), ""))
			var amount_value: Variant = by_id.get(str(tank.get("id", "")), NAN)
			if amount_value is Dictionary:
				amount_value = amount_value.get("onboard_kg", amount_value.get("requested_onboard_kg", NAN))
			if source.is_empty() or typeof(amount_value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(amount_value)):
				continue
			totals[source] = float(totals.get(source, 0.0)) + maxf(0.0, float(amount_value))
	for source: String in totals:
		sources[source] = float(totals[source])
	return sources


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
## struck point's normal speed; slides leave a trail paced by TOUCH_TRAIL_S. US-V12: each new touch on the field
## (not the lake: its records carry normal_ned) also scuffs the airframe. Reads the session feed only.
func _touch_feedback() -> void:
	# A render frame is not a new contact observation; holds must not replay its burst/audio.
	if context.session.sim.paused or not context.session.holds.is_empty():
		return
	var contacts: Array = context.session.soft_contacts
	if contacts.is_empty():
		_touch_marks.clear()
		_touch_feedback_tick = -1
		return
	var tick: int = context.session.sim.tick
	if tick == _touch_feedback_tick:
		return
	if tick < _touch_feedback_tick:
		_touch_marks.clear()
	_touch_feedback_tick = tick
	var now := Time.get_ticks_msec() / 1000.0
	for contact: Dictionary in contacts:
		var point := Frames.ned_to_render(Array(contact.point_ned))
		var velocity := Frames.ned_to_render(Array(contact.velocity_ned))
		var surface := surface_at(context.field, contact.point_ned[0], contact.point_ned[1])
		var slide := float(contact.slide_speed_mps)
		if bool(contact.new):
			var strength := clampf(float(contact.normal_speed_mps) / 3.0, 0.1, 1.0)
			effects.touch(point, velocity, strength, surface)
			if not contact.has("normal_ned"):
				scuffs.add(context.model_bindings.root, point, velocity, strength, surface)
			if _audio_enabled and (slide <= TOUCH_SLIDE_MPS or not audio.accepted_hull_observation_enabled()):
				audio.touch(point, strength, slide > TOUCH_SLIDE_MPS, surface)
			_touch_marks[contact.index] = now
		elif slide > TOUCH_SLIDE_MPS and now - float(_touch_marks.get(contact.index, -INF)) >= TOUCH_TRAIL_S:
			effects.mark(Vector3(point.x, 0.0, point.z), velocity, 0.08)
			if _audio_enabled and not audio.accepted_hull_observation_enabled():
				audio.touch(point, clampf(slide / 15.0, 0.05, 0.6), true, surface)
			_touch_marks[contact.index] = now

func _sample_mark_ground(point: Vector3) -> PackedFloat64Array:
	return GroundTerrain.sample(-point.z, point.x, context.session.ground_surfaces, context.session._lake)


static func surface_at(field: Dictionary, north: float, east: float) -> String:
	for kind: String in ["runway","rotorpad","mown","rough"]:
		for surface: Dictionary in field.get("surfaces",[]):
			if surface.get("type","") == kind and absf(north-float(surface.center_north)) <= float(surface.width_north_south)*0.5 and absf(east-float(surface.center_east)) <= float(surface.length_east_west)*0.5:
				return "mown" if kind == "rotorpad" else kind
	return "rough"

func _secondary(point: Vector3, strength: float) -> void:
	# Wreck signals estimated contact joules; presentation mix consumes [0,1].
	var normalized := clampf(sqrt(maxf(0,strength)/100.0),0,1)
	effects.secondary(point,normalized)
	if _audio_enabled:
		audio.secondary(point,normalized)

## CAM-27: where cameras look during the aftermath: the wreck's core once it is simulated (it can slide well clear of
## the impact), else the impact point. Read-only; the rig places non-pilot views around it.
func focus_point() -> Vector3:
	if active and wreck != null:
		var core: Variant = wreck.core_position()
		if core is Vector3:
			return core
	return _impact_point + Vector3.UP * 0.5

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
	if _water_active:
		return "Water impact\nImpact %.1f m/s · %.2f m below mean water\n\n[R] Restart flight   [C] Change view\n[Esc] Menu" % [
			float(report.get("speed_mps", 0.0)), float(report.get("impact_depth_m", 0.0))]
	var names := ["Touch, no damage","Scrape","Damage","Structural breakup","Destroyed"]
	var cause_line := "\nCause: %s" % CrashCause.line(report.cause) if report.has("cause") else ""
	return "%s\nImpact %.1f m/s · %s\nEstimated %s damage%s\n\n[R] Restart flight   [C] Change view\n[Esc] Menu" % [names[clampi(int(report.get("class",0)),0,4)],float(report.get("speed_mps",0.0)),str(report.get("surface","ground")),str(report.get("component","airframe")),cause_line]

func reset() -> void:
	_touch_feedback_tick = -1
	_touch_marks.clear()
	history.clear()
	_prop_strike_tick = -1
	PropBreak.restore(_broken_propeller)
	_broken_propeller = []
	scuffs.clear()
	if is_instance_valid(_scenery_contacts):
		_scenery_contacts.free()
	_scenery_contacts = null
	active = false
	_water_active = false
	_water_checkpoint_latched = false
	report = {}
	_age = 0
	if wreck != null:
		wreck.reset()
	if effects != null:
		effects.reset()
	if audio != null:
		audio.reset()
	if water_effects != null:
		water_effects.clear()
	if is_instance_valid(_water_shadow):
		_water_shadow.visible = _water_shadow_was_visible
	_water_shadow = null
	_water_shadow_was_visible = false
	if is_instance_valid(_water_blur):
		_water_blur.set_process(_water_blur_was_processing)
		if _water_blur.has_method("update") and context != null and is_instance_valid(context.session) \
				and context.session.sim != null:
			_water_blur.call("update", float(context.session.sim.aux[0]))
	_water_blur = null
	_water_blur_was_processing = false
	if context != null and context.model_bindings != null and context.model_bindings.has_aircraft():
		context.model_bindings.root.visible = true

func stats() -> Dictionary:
	var water_state: Dictionary = water_effects.checkpoint() if water_effects != null else {}
	water_state["rings_visible"] = _visible_water_rings()
	water_state["droplet_pool_size"] = water_effects._droplet_multimesh.instance_count \
		if water_effects != null and water_effects._droplet_multimesh != null else 0
	return {active=active, water_active=_water_active, water_event_count=_water_event_count,
		impact_usec=impact_usec, update_usec=last_update_usec,
		effects=effects.stats() if is_instance_valid(effects) else {},
		wreck=wreck.stats() if is_instance_valid(wreck) else {},
		shader_warmup=shader_warmup.duplicate(),
		water=water_state, report=report.duplicate(true)}


func _visible_water_rings() -> int:
	if water_effects == null:
		return 0
	var visible := 0
	for ring: MeshInstance3D in water_effects._rings:
		if is_instance_valid(ring) and ring.visible:
			visible += 1
	return visible


## Session owns the earlier stepped connection and commits contact IDs first.
func _connect_hull_signals() -> void:
	_hull_capture_ready = false
	if context == null or not is_instance_valid(context.session) or context.session.sim == null:
		return
	var session := context.session
	if not session.sim.stepped.is_connected(_on_accepted_hull_tick):
		session.sim.stepped.connect(_on_accepted_hull_tick)
	if not session.sim.paused_changed.is_connected(_on_hull_pause):
		session.sim.paused_changed.connect(_on_hull_pause)
	if not session.statistics_lifecycle.is_connected(_on_hull_lifecycle):
		session.statistics_lifecycle.connect(_on_hull_lifecycle)
	# Reattach creates the audio bus after children enter. Prime after that reset;
	# the interval before this single settle-prime is deliberately silent.
	call_deferred("_settle_hull_observer")


func _disconnect_hull_signals() -> void:
	_hull_capture_ready = false
	if context == null or not is_instance_valid(context.session) or context.session.sim == null:
		return
	var session := context.session
	if session.sim.stepped.is_connected(_on_accepted_hull_tick):
		session.sim.stepped.disconnect(_on_accepted_hull_tick)
	if session.sim.paused_changed.is_connected(_on_hull_pause):
		session.sim.paused_changed.disconnect(_on_hull_pause)
	if session.statistics_lifecycle.is_connected(_on_hull_lifecycle):
		session.statistics_lifecycle.disconnect(_on_hull_lifecycle)


func _settle_hull_observer() -> void:
	if not is_inside_tree() or not _configured or audio == null:
		return
	audio.setup()
	_hull_capture_ready = true
	_observe_hull_endpoint()


func _on_accepted_hull_tick(_tick: int, _time_s: float, _state: PackedFloat64Array,
		_loads: PackedFloat64Array, _inputs: PackedFloat64Array, _aux: PackedFloat64Array) -> void:
	_observe_hull_endpoint()


func _on_hull_pause(_paused: bool) -> void:
	_observe_hull_endpoint()


func _on_hull_lifecycle(receipt: Dictionary) -> void:
	if receipt.get("success", false) and audio != null:
		audio.reset()
		_observe_hull_endpoint()


func _observe_hull_endpoint() -> void:
	if not _hull_capture_ready or not _audio_enabled or context == null or audio == null:
		return
	var session := context.session
	if not is_instance_valid(session) or session.sim == null:
		return
	if not session.crash.is_empty():
		audio.request_hull_scrape_cancel()
		return
	audio.observe_accepted({observation = session.hull_scrape_observation(),
		tick_rate = 1.0 / session.sim.dt(), paused = session.sim.paused or not session.holds.is_empty(), terminal = false})
