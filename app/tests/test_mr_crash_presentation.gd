# DR-19d (docs/plans/drone-racing.md §18): the FPV quad's crash presentation. Damage is presented once per prop and
# damage step (a grinding prop reports every tick), touches are paced, a broken prop's blades leave the model and come
# back after a pad restart, a damaged prop wobbles, impacts jolt the camera briefly, and the kit allocates nothing
# before the first event or the activity's warm-up (only its enabled parts). Presentation only; the dummy audio driver makes the sound layer inert but exercised.
extends SceneTree

const Fx := preload("res://vehicles/multirotor/quad_crash_fx.gd")
const Visual := preload("res://vehicles/multirotor/multirotor_visual.gd")
const Cam := preload("res://vehicles/multirotor/multirotor_camera.gd")
const Activity := preload("res://vehicles/multirotor/multirotor_scene.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")
const RB := preload("res://physics/rigid_body.gd")

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_pacing()
	_mix()
	await _activity()
	await _camera()
	print("crash presentation: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _pacing() -> void:
	_check("damage bands: intact, damaged, badly damaged, broken", Fx.band_of(1.0) == 0 and Fx.band_of(0.85) == 1
		and Fx.band_of(0.5) == 2 and Fx.band_of(0.0) == 3)
	var fx: Node3D = Fx.new()
	fx.enable_audio = false
	root.add_child(fx)
	_check("nothing is allocated before the first event", fx.effects == null and fx.audio == null)
	for health: float in [0.8, 0.64, 0.51, 0.41]:
		fx.prop_damage({rotor = 1, health = health, point_ned = PackedFloat64Array([0.0, 0.0, -0.1])}, Vector3.ZERO)
	_check("a grinding prop is presented once per damage step (2 of 4 reports here)", int(fx._bands.get(1, 0)) == 2
		and fx.effects != null)
	fx.impact({surface = "ground", normal_speed_mps = 8.0, point_ned = PackedFloat64Array([0.0, 0.0, 0.0])}, Vector3.ZERO)
	var cooled: bool = fx._touch_cooldown > 0.0
	fx.update(Fx.TOUCH_INTERVAL_S + 0.01, false)
	_check("touches are paced and the pause freezes the pacing clock", cooled and fx._touch_cooldown == 0.0)
	# DR-19f: a graze or skid is a paced scrape (one grain per SCRAPE_INTERVAL_S), its strength sqrt(v / 15).
	var scrape := {type = "scrape", surface = "ground", slip_speed_mps = 15.0, point_ned = PackedFloat64Array([0.0, 0.0, 0.0])}
	fx.scrape(scrape, Vector3.ZERO)
	var paced: bool = fx._scrape_cooldown == Fx.SCRAPE_INTERVAL_S
	fx.update(0.05, false)
	fx.scrape(scrape, Vector3.ZERO)
	_check("scrapes are paced (a sliding contact reports every tick)", paced and is_equal_approx(fx._scrape_cooldown, Fx.SCRAPE_INTERVAL_S - 0.05))
	_check("scrape strength: sqrt(v / 15), floored at 0.1 and saturated at 1", is_equal_approx(Fx.scrape_strength(15.0), 1.0)
		and is_equal_approx(Fx.scrape_strength(3.75), 0.5) and Fx.scrape_strength(0.0) == 0.1 and Fx.scrape_strength(60.0) == 1.0)
	fx.reset()
	_check("a pad restart forgets the presented damage", fx._bands.is_empty() and not fx._crashed and fx._scrape_cooldown == 0.0)
	fx.free()
	# Audit: on rolling terrain an earlier scuff mark stays where it was drawn when a later touch lands higher.
	var hill: Node3D = Fx.new()
	hill.enable_audio = false
	hill.ground_height = func(x: float, _z: float) -> float: return 0.1 * x
	root.add_child(hill)
	hill.impact({surface = "ground", normal_speed_mps = 6.0, point_ned = PackedFloat64Array([0.0, 0.0, 0.0])}, Vector3.ZERO)
	var first: MeshInstance3D = hill.effects.marks[0]
	var drawn_y: float = first.global_position.y
	hill.update(Fx.TOUCH_INTERVAL_S + 0.01, false)
	# NED east 10 m is render +x 10 m: ground 1 m higher there.
	hill.impact({surface = "ground", normal_speed_mps = 6.0, point_ned = PackedFloat64Array([0.0, 10.0, -1.0])}, Vector3.ZERO)
	_check("an earlier scuff mark stays put when a later touch lands on higher ground", first.visible
		and is_equal_approx(first.global_position.y, drawn_y) and absf(hill.effects.position.y - 1.0) < 1.0e-6,
		"%.4f -> %.4f (frame %.3f)" % [drawn_y, first.global_position.y, hill.effects.position.y])
	hill.free()


## DR-19e (§19.3): the touch curve rises with impact speed and saturates at FULL_TOUCH_SPEED_MPS, and the kit's
## voices take the quad motor loop's distance law (the crash-to-motor balance does not change with the view).
func _mix() -> void:
	var s3 := Fx.touch_strength(3.0)
	var s6 := Fx.touch_strength(6.0)
	_check("the touch curve: (v / 12)^0.6, floored at 0.05 and saturated at 1", absf(s3 - pow(0.25, 0.6)) < 1.0e-12
		and s6 > s3 and Fx.touch_strength(12.0) == 1.0 and Fx.touch_strength(30.0) == 1.0 and Fx.touch_strength(0.0) == 0.05)
	var fx: Node3D = Fx.new()
	fx.enable_effects = false
	root.add_child(fx)
	fx.impact({surface = "ground", normal_speed_mps = 4.0, point_ned = PackedFloat64Array([0.0, 0.0, 0.0])}, Vector3.ZERO)
	var voices := 0
	var matched := 0
	for voice in fx.audio.get_children():
		if voice is AudioStreamPlayer3D:
			voices += 1
			if voice.unit_size == Fx.VOICE_UNIT_SIZE_M and voice.max_distance == Fx.VOICE_MAX_DISTANCE_M:
				matched += 1
	_check("every crash voice uses the motor loop's distance law (2 m unit size)", voices > 0 and matched == voices, "%d/%d" % [matched, voices])
	fx.free()


func _activity() -> void:
	var activity: Node3D = Activity.new()
	activity.enable_world = false
	activity.enable_audio = false
	activity.departure_managed = true
	activity.race_track = ""
	root.add_child(activity)
	await process_frame
	var visual: RefCounted = activity.visual
	var health := PackedFloat64Array([1.0, 0.0, 0.6, 1.0])
	visual.set_rotor_health(health)
	var pivot: Node3D = visual.rotors[1].pivot
	var blades: Node3D = pivot.find_child("*blades*", true, false)
	var bell: Node3D = pivot.find_child("*bell*", true, false)
	_check("a broken prop's blades leave the model and its motor bell stays", visual.rotor_broken(1) and pivot.visible
		and blades != null and not blades.visible and bell != null and bell.visible and not visual.rotor_broken(0))
	var body := PackedFloat64Array([0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	visual.pose(body, PackedFloat64Array([900.0, 900.0, 900.0, 900.0]), 0.004)
	var damaged: Basis = (visual.rotors[2].pivot as Node3D).transform.basis
	var intact: Basis = (visual.rotors[0].pivot as Node3D).transform.basis
	var tilt_damaged := absf(damaged.z.normalized().dot((visual.rotors[2].base as Basis).z.normalized()) - 1.0)
	var tilt_intact := absf(intact.z.normalized().dot((visual.rotors[0].base as Basis).z.normalized()) - 1.0)
	_check("a damaged prop's disc wobbles; an intact one does not", tilt_damaged > tilt_intact and tilt_intact < 1.0e-9,
		str(tilt_damaged) + " vs " + str(tilt_intact))
	visual.set_rotor_health(PackedFloat64Array([1.0, 1.0, 1.0, 1.0]))
	_check("restored health brings the blades back", not visual.rotor_broken(1) and pivot.visible and blades.visible)
	_check("the activity owns a crash presentation that follows the world and sound switches", activity.crash_fx != null
		and not activity.crash_fx.enable_effects and not activity.crash_fx.enable_audio
		and activity.crash_fx.effects == null and activity.crash_fx.audio == null)
	activity._on_impact({type = "prop_damage", rotor = 0, health = 0.85, first = true, point_ned = PackedFloat64Array([0.0, 0.0, 0.0])})
	activity._on_impact({type = "prop_damage", rotor = 0, health = 0.72, first = false, point_ned = PackedFloat64Array([0.0, 0.0, 0.0])})
	_check("only the first damage of a prop is announced", "Prop damaged" in activity.hud.message.text and "85" in activity.hud.message.text,
		activity.hud.message.text)
	# Audit: an unresolved crossing of the next gate is announced once; a new attempt starts from its own count.
	activity.hud.flash("")
	activity._notice_unresolved({attempt = 2, unresolved = 3, phase = "RACING"})
	var quiet_start: bool = activity.hud.message.text.is_empty()
	activity._notice_unresolved({attempt = 2, unresolved = 4, phase = "RACING"})
	var told: bool = "Gate not counted" in activity.hud.message.text
	activity.hud.flash("")
	activity._notice_unresolved({attempt = 2, unresolved = 4, phase = "RACING"})
	_check("an unresolved gate crossing is announced once, not at a new attempt's start", quiet_start and told
		and activity.hud.message.text.is_empty())
	activity.free()


func _camera() -> void:
	var cam: RefCounted = Cam.new()
	var holder := Node3D.new()
	root.add_child(holder)
	cam.build(holder, 500.0)
	var pose := PackedFloat64Array([0.0, 0.0, -2.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	cam.update(pose, PackedFloat64Array([0.05, 0.0, -0.02]), 0.016, Callable())
	var still: Basis = cam.camera.global_transform.basis
	cam.shake(1.0)
	cam.update(pose, PackedFloat64Array([0.05, 0.0, -0.02]), 0.016, Callable())
	var shaken: Basis = cam.camera.global_transform.basis
	_check("an impact jolts the camera", not shaken.is_equal_approx(still))
	for i in 60:
		cam.update(pose, PackedFloat64Array([0.05, 0.0, -0.02]), 0.016, Callable())
	_check("the jolt fades within a second", cam._shake == 0.0 and cam.camera.global_transform.basis.is_equal_approx(still))
	# Audit: the pilot's eye on the field does not shake with the quad's impacts.
	cam.view = Cam.VIEWS.find("pilot")
	cam.update(pose, PackedFloat64Array([0.05, 0.0, -0.02]), 0.016, Callable())
	var pilot_still: Basis = cam.camera.global_transform.basis
	cam.shake(1.0)
	cam.update(pose, PackedFloat64Array([0.05, 0.0, -0.02]), 0.016, Callable())
	_check("the pilot view does not shake", cam._shake == 0.0 and cam.camera.global_transform.basis.is_equal_approx(pilot_still))
	holder.free()
	await _rattle()


## Audit: the damaged-prop rattle stops with the motors (pause, crash menu, stopped rotors).
func _rattle() -> void:
	var activity: Node3D = Activity.new()
	activity.enable_world = false
	activity.enable_audio = true
	activity.departure_managed = true
	activity.race_track = ""
	root.add_child(activity)
	await process_frame
	_check("with sound on, the crash voices are built while loading (no first-touch hitch)", activity.crash_fx.audio != null
		and activity.crash_fx.effects == null)
	var rattle: AudioStreamPlayer3D = activity.get_node_or_null("MotorRattle")
	if rattle == null:
		_check("the activity builds a rattle player with sound on", false)
		activity.free()
		return
	var hover: float = activity._hover_speed
	var flying := {rotor_speed_rad_s = PackedFloat64Array([hover, hover, hover, hover]),
		rotor_health = PackedFloat64Array([0.0, 1.0, 1.0, 1.0])}
	activity.session.resume()
	activity._update_audio(flying, 0.5)
	var playing: bool = not rattle.stream_paused
	activity.session.pause()
	activity._update_audio(flying, 0.5)
	_check("a broken prop rattles in flight and the rattle stops with the motors on pause", playing and rattle.stream_paused)
	activity.free()
