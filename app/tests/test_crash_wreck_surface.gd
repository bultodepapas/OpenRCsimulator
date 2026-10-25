## CR-09d2: the wreck slides and rebounds on the surface it hit. One friction table (Severity.SLIDE_FRICTION, also the
## abrasion channel) and one restitution table drive the wreck's ground. Real Godot physics frames.
extends SceneTree

const WreckController = preload("res://render/crash/wreck.gd")
const Severity = preload("res://render/crash/severity.gd")
const AirplaneBuilder = preload("res://render/airplane.gd")

var _checks := 0
var _failures := 0
var _wreck: Variant
var _airplane: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_tables()
	_airplane = AirplaneBuilder.build("jensen-das-ugly-stik-60").root
	root.add_child(_airplane)
	_wreck = WreckController.new()
	root.add_child(_wreck)
	await process_frame
	_wreck.prepare(_airplane)
	var grass := await _slide("grass")
	var concrete := await _slide("concrete")
	_check("a wreck slides farther on grass than on concrete", grass > concrete + 0.05, "grass %.2f m, concrete %.2f m" % [grass, concrete])
	var grass_up := await _rebound("grass")
	var concrete_up := await _rebound("concrete")
	_check("a dropped wreck rebounds higher from concrete than from grass", concrete_up > grass_up, "concrete %.3f m/s, grass %.3f m/s" % [concrete_up, grass_up])
	_limiter("concrete")
	_limiter("grass")
	_wreck.free()
	_airplane.free()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print(("ok   " if ok else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))


func _tables() -> void:
	var paving := Severity.surface_contact("asphalt")
	_check("asphalt contact uses the abrasion friction and paving restitution", paving.friction == Severity.SLIDE_FRICTION.asphalt and paving.bounce == Severity.SURFACE_RESTITUTION.asphalt)
	# GP-07d: the field's runway is a mown grass strip: it rebounds like turf.
	_check("the runway strip rebounds like the mown field", Severity.surface_contact("runway").bounce == Severity.surface_contact("mown").bounce)
	_check("turf absorbs more than paving", Severity.surface_contact("grass").bounce < Severity.surface_contact("concrete").bounce)
	_check("an unknown surface uses the explicit fallback", Severity.surface_contact("moon dust").friction == Severity.SLIDE_FRICTION.unknown)
	_check("every friction surface has a restitution", Severity.SLIDE_FRICTION.keys().all(func(k: String) -> bool: return Severity.SURFACE_RESTITUTION.has(k)))


## Horizontal travel of an intact (C1) wreck launched sliding at 12 m/s just above `surface`, after 3 s.
func _slide(surface: String) -> float:
	_wreck.reset()
	_wreck.start(Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 0)), Vector3(12, -0.5, 0), Vector3.ZERO, {"class": 1, "mass_kg": 2.885, "seed": 3, "surface": surface})
	var ground: PhysicsMaterial = _wreck._ground.physics_material_override
	_check("%s sets the wreck ground material" % surface, ground != null and is_equal_approx(ground.friction, Severity.surface_contact(surface).friction)
		and is_equal_approx(ground.bounce, Severity.surface_contact(surface).bounce))
	var start: Vector3 = _wreck._core_body.global_position
	for i in 720:
		await physics_frame
	return Vector2(_wreck._core_body.global_position.x - start.x, _wreck._core_body.global_position.z - start.z).length()


## The rebound limiter returns the surface's share of a part's impact speed.
func _limiter(surface: String) -> void:
	_wreck.reset()
	_wreck.start(Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0)), Vector3(0, -4.0, 0), Vector3.ZERO, {"class": 1, "mass_kg": 2.885, "seed": 5, "surface": surface})
	var core: RigidBody3D = _wreck._core_body
	core.linear_velocity = Vector3(0, -4.0, 0)
	_wreck._limit_ground_rebound(core)
	_check("%s rebound limiter returns its restitution" % surface, is_equal_approx(core.linear_velocity.y, 4.0 * Severity.SURFACE_RESTITUTION[surface]), "%.3f m/s" % core.linear_velocity.y)


## Largest upward speed of an intact wreck dropped flat from 0.6 m onto `surface`.
func _rebound(surface: String) -> float:
	_wreck.reset()
	_wreck.start(Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 0)), Vector3(0, -4.0, 0), Vector3.ZERO, {"class": 1, "mass_kg": 2.885, "seed": 4, "surface": surface})
	var best := 0.0
	for i in 240:
		await physics_frame
		best = maxf(best, _wreck._core_body.linear_velocity.y)
	return best
