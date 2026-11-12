## LENS-02/03 (docs/plans/lens-screen-effects.md): end to end without a renderer. A real FlightSession flies into a
## spectator's collision capsule; the accepted contact event must reach the lens trigger and start the blood
## curtain, and the same event must never be admitted twice. The fixture removes forces (as
## test_aircraft_contact_session.gd does) so the sweep is deterministic.
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const RB := preload("res://physics/rigid_body.gd")
const World := preload("res://scenery/collision_world.gd")
const ImpactTrigger := preload("res://render/lens/impact_trigger.gd")
const LensSettings := preload("res://render/lens/lens_settings.gd")
const LensStack := preload("res://render/lens/lens_stack.gd")

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print(("ok   " if ok else "FAIL ") + label)


func _initialize() -> void:
	await process_frame
	var s := Session.new()
	s.input_enabled = false
	s.setup()
	s.sim.continuous = PackedFloat64Array()
	for field: String in ["step_policy", "stage", "block_loads", "block_derivative", "stage_rotor_momentum", "block_aux"]:
		s.sim.model.set(field, Callable())
	s.sim.gravity = 0.0
	s.sim.model.loads = func(_body: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		return PackedFloat64Array([0, 0, 0, 0, 0, 0])
	s.sim.model.pre_tick = func(aux: PackedFloat64Array, _inputs: PackedFloat64Array, _dt: float) -> PackedFloat64Array:
		return aux
	s.sim.model.rotor_momentum = func(_aux: PackedFloat64Array) -> PackedFloat64Array:
		return PackedFloat64Array()
	root.add_child(s)
	var built: Dictionary = World.build({pilot = {north = -60.0, east = 0.0, down = 0.0}, objects = []},
		{groups = [{id = "spectators", prefab = "person_standing", placements = [{north = 6.0, east = 0.0, heading = 0.0}]}]})
	_check("a spectator capsule installs in the collision world", built.ok and s.set_collision_world(built.world))
	# Chest height (the capsule's centre is 0.89 m up), flying north at 12 m/s into the spectator.
	_check("the flight starts clear of the spectator", s.sim.reset(RB.make_state(PackedFloat64Array([0.0, 0.0, -0.9]),
		PackedFloat64Array([12.0, 0.0, 0.0]), PackedFloat64Array([1, 0, 0, 0]), PackedFloat64Array([0, 0, 0]))))

	var camera := Camera3D.new()
	root.add_child(camera)
	var stack := LensStack.new()
	root.add_child(stack)
	var configured := stack.configure({"settings": LensSettings.resolve({}, true, LensSettings.DEFAULTS), "camera": camera,
		"session": s, "view_provider": func() -> String: return "chase", "mass_kg": float(s.sim.mass), "seed": 5})
	_check("the lens stack configures on a real session", configured)
	s.contact_events_changed.connect(stack.on_contacts)

	var seen := {}
	var person_records: Array[Dictionary] = []
	for i in 240:
		if s.sim.paused:
			break
		s.sim.step()
		for record: Dictionary in ImpactTrigger.admit(s.contact_events(), seen, -1, float(s.sim.mass)):
			if record.kind == "person":
				person_records.append(record)
	_check("the accepted contact names a person", person_records.size() == 1)
	if not person_records.is_empty():
		_check("the strike has a strength and a point", float(person_records[0].strength) > 0.0
			and (person_records[0].point_ned as PackedFloat64Array).size() == 3)
	stack.advance(1.0 / 60.0, 1.0, false)
	var snapshot: Dictionary = stack.snapshot()
	_check("the session event started the blood curtain", bool(snapshot.blood) and bool(snapshot.nodes.film))
	_check("the same event is not admitted again", ImpactTrigger.admit(s.contact_events(), seen, -1, float(s.sim.mass)).is_empty())
	stack.reset(int(s.sim.tick))
	stack.on_contacts()
	_check("a restored checkpoint does not replay old blood", not bool(stack.snapshot().blood))
	stack.queue_free()
	camera.queue_free()
	s.queue_free()
	await process_frame
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)
