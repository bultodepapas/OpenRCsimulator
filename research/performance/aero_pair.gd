## H18: bitwise parity of the aerodynamic oracle and strip laws, an explicit prior aero.gd (reference, extracted
## outside app/) versus the working tree (candidate), over random states near and away from the ground (ground effect
## on and off), random servo/flap deflections, rates and downwash-lag values for several catalog aircraft.
## Research-only. See research/performance/README.md#aero-oracle-reuse-h18.
extends SceneTree

const Candidate := preload("res://physics/aero.gd")
const Session := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const RB := preload("res://physics/rigid_body.gd")
const AIRCRAFT := ["jensen-das-ugly-stik-60", "stik-glow-61fx-2t", "gp-extra-300s-60", "p51d-mustang-120",
	"skywalker-x8", "sebart-avanti-s-a200-p100rx", "turbo-lumber-evolution"]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ref_path := ""
	var per_aircraft := 3000
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--reference="): ref_path = arg.trim_prefix("--reference=")
		if arg.begins_with("--states="): per_aircraft = arg.trim_prefix("--states=").to_int()
	var reference := GDScript.new()
	reference.source_code = FileAccess.get_file_as_string(ref_path)
	if reference.source_code.is_empty() or reference.reload() != OK:
		push_error("reference script failed to load: " + ref_path)
		quit(2)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261027
	var mismatches := 0
	var calls := 0
	var in_ground_effect := 0
	for id: String in AIRCRAFT:
		var session: Node = Session.new()
		session.setup(str(Catalog.entry(id).data), id)
		if not session.is_flyable():
			printerr("not flyable: ", id)
			mismatches += 1
			continue
		var model: Dictionary = session.aircraft.model
		var base_state: PackedFloat64Array = session.start.state.duplicate()
		var base_aux: PackedFloat64Array = session.sim.aux.duplicate()
		var rho: float = session.air_density()
		for k: int in per_aircraft:
			var s := base_state.duplicate()
			# Height: half the states within 3 m of the ground (ground effect), half at the trim height.
			if k % 2 == 0:
				s[RB.POS + 2] = -rng.randf_range(0.15, 3.0)
			for axis: int in 3:
				s[RB.VEL + axis] += rng.randf_range(-6.0, 6.0)
				s[RB.RATE + axis] = rng.randf_range(-3.0, 3.0)
			var q := PackedFloat64Array([1.0, rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4)])
			var norm := sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3])
			for axis: int in 4: s[RB.ATT + axis] = q[axis] / norm
			var aux := base_aux.duplicate()
			for servo: int in 3: aux[1 + servo] = rng.randf_range(-1.0, 1.0)
			if session.flaps_available(): aux[session.flap_aux_index()] = [0.0, 0.0, rng.randf(), 1.0][k % 4]
			var d: Dictionary = session._deflections(aux)
			var air: Dictionary = session.air_data(s, 0.0)
			var ground_up: float = session._ground_up(s)
			if not is_nan(ground_up): in_ground_effect += 1
			# The session passes a lag value only for aircraft with the downwash-lag state, else NAN.
			var lag: float = NAN if k % 3 == 0 or session.downwash_index() < 0 else rng.randf_range(-5.0, 25.0)
			var a := var_to_bytes([reference.loads(s, air, d, model, rho, lag, ground_up), reference._wing_flow(s, air, d, model),
				reference.wing_wake_velocity(s, air, d, model, ground_up), reference.local_flow_weight(s, air, d, model, lag)])
			var b := var_to_bytes([Candidate.loads(s, air, d, model, rho, lag, ground_up), Candidate._wing_flow(s, air, d, model),
				Candidate.wing_wake_velocity(s, air, d, model, ground_up), Candidate.local_flow_weight(s, air, d, model, lag)])
			calls += 1
			if a != b:
				mismatches += 1
				if mismatches <= 5: printerr("MISMATCH %s k=%d" % [id, k])
		session.free()
	print("AERO_PARITY states=%d in_ground_effect=%d mismatches=%d" % [calls, in_ground_effect, mismatches])
	quit(1 if mismatches else 0)
