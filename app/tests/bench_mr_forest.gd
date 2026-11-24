## Paired CPU cost of the production quad scenery callback with and without its shared solid rejection.
extends SceneTree

const Session := preload("res://sim/multirotor/session.gd")
const Field := preload("res://data/field_loader.gd")
const World := preload("res://scenery/collision_world.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const DT := 1.0 / 240.0
const REPEATS := 8
const SAMPLES := 40


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var field := Field.load_from()
	var s := Session.new()
	root.add_child(s)
	var ok := false
	if field.ok:
		var built := World.build(field.field, {groups = []}, {})
		ok = built.ok and s.set_collision_world(built.world) and s.prepare(field.field, {start = "air", crash_model = "graded"})
	if ok:
		var trunk: Dictionary = s._obstacles.solids[0]
		var continuous: PackedFloat64Array = s.sim.continuous.duplicate()
		for i in 4:
			continuous[i] = 1000.0
		var n := float(trunk.north) - float(trunk.radius) - 0.14
		ok = _pair(s.plant, "open field", M.v3(0, 0, -30), continuous, false)
		ok = _pair(s.plant, "over grove", M.v3(n, trunk.east, trunk.down - 50.0), continuous, false) and ok
		ok = _pair(s.plant, "wood approach", M.v3(n, trunk.east, trunk.down), continuous, true) and ok
		ok = _pair(s.plant, "wood approach pitching 20 to 21 degrees", M.v3(n, trunk.east, trunk.down),
			continuous, true, 20.0, 21.0) and ok
	s.free()
	if ok:
		print("FPV forest CPU benchmark complete")
	else:
		push_error("FPV forest benchmark setup or paired output differs")
	quit(0 if ok else 1)


func _pair(plant: RefCounted, label: String, pos: PackedFloat64Array, shafts: PackedFloat64Array, near: bool,
		start_pitch := 0.0, end_pitch := 0.0) -> bool:
	var velocity := M.v3(40, 0, 0)
	var previous := RB.make_state(pos, velocity, M.q_from_euler(0, deg_to_rad(start_pitch), 0), M.v3(0, 0, 0))
	var next := RB.make_state(M.add(pos, M.v3(40.0 * DT, 0, 0)), velocity,
		M.q_from_euler(0, deg_to_rad(end_pitch), 0), M.v3(0, 0, 0))
	var guard: Callable = plant.solids_near
	if bool(guard.call(previous, next)) != near:
		return false
	var times: Array[PackedFloat64Array] = [PackedFloat64Array(), PackedFloat64Array()]
	var witness := PackedByteArray()
	for sample in SAMPLES + 2:
		for order in 2:
			var mode := (order + sample) % 2
			plant.solids_near = guard if mode == 1 else Callable()
			var start := Time.get_ticks_usec()
			for i in REPEATS:
				var c := shafts.duplicate()
				var arrival: Dictionary = plant._scenery_arrival(previous, next, c, DT)
				if sample == 0 and i == 0:
					var bytes := var_to_bytes([arrival, c])
					if mode == 0:
						witness = bytes
					elif bytes != witness:
						plant.solids_near = guard
						return false
			if sample >= 2:
				times[mode].append(float(Time.get_ticks_usec() - start) / REPEATS)
	plant.solids_near = guard
	for mode in 2:
		var values := times[mode]
		values.sort()
		print("%s, %s, CPU us/call (batches of %d): median %.2f, p95 %.2f" % [label,
			"shared guard" if mode == 1 else "individual sweeps", REPEATS,
			values[floori(SAMPLES * 0.5)], values[ceili(SAMPLES * 0.95) - 1]])
	return true
