# DR-19d (docs/plans/drone-racing.md §18): the FPV quad's crash presentation. Damage is presented once per prop and
# damage step (a grinding prop reports every tick), touches are paced, a broken prop's blades leave the model and come
# back after a pad restart, a damaged prop wobbles, impacts jolt the camera briefly, and the kit allocates nothing
# before the first event. Presentation only; the dummy audio driver makes the sound layer inert but exercised.
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
	await _activity()
	_camera()
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
	fx.reset()
	_check("a pad restart forgets the presented damage", fx._bands.is_empty() and not fx._crashed)
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
	_check("a broken prop's blades leave the model", visual.rotor_broken(1) and not pivot.visible and not visual.rotor_broken(0))
	var body := PackedFloat64Array([0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	visual.pose(body, PackedFloat64Array([900.0, 900.0, 900.0, 900.0]), 0.004)
	var damaged: Basis = (visual.rotors[2].pivot as Node3D).transform.basis
	var intact: Basis = (visual.rotors[0].pivot as Node3D).transform.basis
	var tilt_damaged := absf(damaged.z.normalized().dot((visual.rotors[2].base as Basis).z.normalized()) - 1.0)
	var tilt_intact := absf(intact.z.normalized().dot((visual.rotors[0].base as Basis).z.normalized()) - 1.0)
	_check("a damaged prop's disc wobbles; an intact one does not", tilt_damaged > tilt_intact and tilt_intact < 1.0e-9,
		str(tilt_damaged) + " vs " + str(tilt_intact))
	visual.set_rotor_health(PackedFloat64Array([1.0, 1.0, 1.0, 1.0]))
	_check("restored health brings the blades back", not visual.rotor_broken(1) and pivot.visible)
	_check("the activity owns a crash presentation that follows the world and sound switches", activity.crash_fx != null
		and not activity.crash_fx.enable_effects and not activity.crash_fx.enable_audio)
	activity._on_impact({type = "prop_damage", rotor = 0, health = 0.85, first = true, point_ned = PackedFloat64Array([0.0, 0.0, 0.0])})
	activity._on_impact({type = "prop_damage", rotor = 0, health = 0.72, first = false, point_ned = PackedFloat64Array([0.0, 0.0, 0.0])})
	_check("only the first damage of a prop is announced", "Prop damaged" in activity.hud.message.text and "85" in activity.hud.message.text,
		activity.hud.message.text)
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
	holder.free()
