## Scratch characterization of helicopter crash presentation attribution.
##
## Run inside the current app project using the repository's checked runner, e.g. with this
## absolute script path. This deliberately invokes helicopter_main.gd's real _lens_crash()
## with a prescribed crash dictionary, a real LensStack and a real CollisionWorld. It does NOT
## integrate an accepted helicopter flight or prove any particular trajectory is reachable.
## LensStack has no on_helicopter_crash method: _lens_crash -> strike_from_crash is the
## actual production route. The desired-behavior assertion is expected to fail on the audited
## source: a nearby, separate spectator is treated as the struck person on a terrain crash.
extends SceneTree

const HeliMain := preload("res://helicopter_main.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const LensStack := preload("res://render/lens/lens_stack.gd")
const LensSettings := preload("res://render/lens/lens_settings.gd")

class PrescribedSession extends Node:
	var crash: Dictionary = {}

var checks := 0
var failures := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("ok   " if ok else "FAIL ") + label + (" " + detail if not detail.is_empty() else ""))


func _initialize() -> void:
	call_deferred("_run")


func _world(person_north: float) -> Dictionary:
	var field := {"pilot": {"north": -60.0, "east": 0.0, "down": 0.0}, "objects": []}
	var scenery := {"groups": [{"id": "spectators", "prefab": "person_standing", "placements": [
		{"north": person_north, "east": 0.0, "heading": 0.0}
	]}]}
	return CollisionWorld.build(field, scenery)


## Independent signed distance from a point to the builder's vertical capsule, in metres.
## Positive means geometric separation. The production nearby() query uses the proxy AABB.
func _capsule_signed_distance(point: PackedFloat64Array, proxy: Dictionary) -> float:
	var dn := point[0] - float(proxy.north)
	var de := point[1] - float(proxy.east)
	var dz := maxf(absf(point[2] - float(proxy.down)) - float(proxy.half_length), 0.0)
	return sqrt(dn * dn + de * de + dz * dz) - float(proxy.radius)


func _first_person(world: Dictionary) -> Dictionary:
	for proxy: Dictionary in world.proxies:
		if str(proxy.kind) == "person":
			return proxy
	return {}


func _terrain_crash(point: PackedFloat64Array, tick: int) -> Dictionary:
	return {"tick": tick, "reason": "fuselage ground strike", "surface": "terrain",
		"surface_detail": {"kind": "terrain"}, "point_world_ned": point.duplicate(),
		"normal_speed_mps": 14.0, "body": PackedFloat64Array()}


func _run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var camera := Camera3D.new()
	holder.add_child(camera)
	var stack := LensStack.new()
	holder.add_child(stack)
	var settings: Dictionary = LensSettings.resolve({}, true, LensSettings.DEFAULTS)
	var configured := stack.configure({"settings": settings, "camera": camera,
		"view_provider": func() -> String: return "chase", "station": PackedFloat64Array([-60.0, 0.0, 0.0]),
		"eye_height": 1.7, "mass_kg": 1.0, "seed": 3})
	_check("default interactive lens setup is configured", configured and settings.impact == "curtain")
	if not configured:
		_finish(holder, null, null)
		return

	# Keep HelicopterMain detached: adding it to the tree would launch its _ready() route.
	# Inject only the prescribed crash owner, as _lens_crash reads no other session state.
	var heli := HeliMain.new()
	var session := PrescribedSession.new()
	heli.session = session
	heli._lens = stack
	var calls := [0, 0]
	stack.person_struck.connect(func(player: bool) -> void: calls[1 if player else 0] += 1)

	var close_build := _world(1.3)
	var far_build := _world(3.0)
	var actual_build := _world(0.0)
	_check("the three real collision worlds build", close_build.ok and far_build.ok and actual_build.ok)
	if not close_build.ok or not far_build.ok or not actual_build.ok:
		_finish(holder, heli, session)
		return

	var ground_point := PackedFloat64Array([0.0, 0.0, 0.0])
	var close_person := _first_person(close_build.world)
	var close_near := CollisionWorld.nearby(close_build.world, ground_point[0], ground_point[1], ground_point[2], 1.2)
	_check("separate spectator is selected by the production 1.2 m AABB query", not close_person.is_empty()
		and close_near.size() == 1 and str(close_near[0].kind) == "person")
	if close_person.is_empty():
		_finish(holder, heli, session)
		return
	var separation := _capsule_signed_distance(ground_point, close_person)
	_check("prescribed terrain impact point is outside the spectator capsule", separation > 0.9,
		"signed_clearance_m=%.6f" % separation)
	stack.reset()
	calls[0] = 0
	calls[1] = 0
	session.crash = _terrain_crash(ground_point, 1)
	heli._camera_obstacles = close_build.world
	heli._lens_crash()
	_check("characterization: nearby spectator is presented as struck by the ground impact",
		calls[0] == 1 and calls[1] == 0 and bool(stack.snapshot().blood),
		"person_events=%d blood=%s" % [calls[0], str(stack.snapshot().blood)])
	_check("desired: terrain-only impact does not announce a separate spectator", calls[0] == 0 and not bool(stack.snapshot().blood))

	stack.reset()
	calls[0] = 0
	calls[1] = 0
	session.crash = _terrain_crash(ground_point, 2)
	heli._camera_obstacles = far_build.world
	heli._lens_crash()
	_check("far spectator control produces no person event or blood", calls[0] == 0 and calls[1] == 0
		and not bool(stack.snapshot().blood))

	var person_point := PackedFloat64Array([0.0, 0.0, -0.9])
	var actual_person := _first_person(actual_build.world)
	_check("positive control point lies inside the person capsule", not actual_person.is_empty()
		and _capsule_signed_distance(person_point, actual_person) < 0.0)
	stack.reset()
	calls[0] = 0
	calls[1] = 0
	session.crash = {"tick": 3, "reason": "fuselage scenery impact (person)", "surface": "person",
		"surface_detail": {"kind": "person", "id": str(actual_person.get("id", ""))},
		"obstacle_kind": "person", "obstacle_id": str(actual_person.get("id", "")),
		"point_world_ned": person_point, "normal_speed_mps": 14.0, "body": PackedFloat64Array()}
	heli._camera_obstacles = actual_build.world
	heli._lens_crash()
	_check("prescribed actual-person impact produces one spectator event and blood", calls[0] == 1
		and calls[1] == 0 and bool(stack.snapshot().blood))
	_finish(holder, heli, session)


func _finish(holder: Node, heli: Node, session: Node) -> void:
	print("helicopter person attribution: %d checks, %d failed; prescribed presentation input only" % [checks, failures])
	if heli != null:
		heli.free()
	if session != null:
		session.free()
	holder.queue_free()
	quit(1 if failures > 0 else 0)
