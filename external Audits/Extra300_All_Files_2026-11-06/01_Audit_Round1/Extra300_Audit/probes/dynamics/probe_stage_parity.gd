extends SceneTree
const Session = preload("res://sim/flight_session.gd")
const Flight = preload("res://physics/glow/flight.gd")
const RB = preload("res://physics/rigid_body.gd")
const M = preload("res://physics/math3d.gd")
const FieldLoader = preload("res://data/field_loader.gd")

func _initialize() -> void:
	call_deferred("run")

func digest(v: Variant) -> String:
	return var_to_bytes(v).hex_encode().sha256_text()

func make_session() -> Node:
	var s = Session.new()
	s.input_enabled = false
	s.soft_hull_contacts = true
	s.crash_auto_restart = false
	s.setup("res://data/aircraft/gp_extra_300s_60.json", "gp-extra-300s-60")
	return s

func tick_fingerprint(s: Node) -> Dictionary:
	return {tick=s.sim.tick, fault=s.sim.fault_reason, digest=digest([s.sim.state,s.sim.aux,s.sim.continuous,s.sim.modes,s.sim.last_events]), events=s.sim.last_events.duplicate(true)}

func run() -> void:
	var s = make_session()
	if not s.is_flyable():
		printerr("setup failed ",s.start_error)
		quit(1)
		return
	var cap: float = s.aircraft.model.propulsion.glow.capacity_fuel_kg
	var floor_mass: float = s.aircraft.model.propulsion.glow.unusable_fuel_kg
	var fuels: Array = [0.0, floor_mass - 1e-12, floor_mass, floor_mass + 1e-12, 0.5*cap, cap, cap+1e-9, -1e-9, NAN, INF]
	var stage_digests: Array = []
	var point_digests: Array = []
	var ok_stages := 0
	var refused_stages := 0
	for fi in fuels.size():
		for vi in 3:
			for ri in 3:
				var body: PackedFloat64Array = s.sim.state.duplicate()
				body[RB.POS+2] = -20.0 if vi == 0 else -0.20
				body[RB.VEL] = [0.0, 12.0, 25.0][vi]
				body[RB.VEL+1] = 0.3 if vi == 2 else 0.0
				body[RB.RATE] = 0.1 * vi
				body[RB.RATE+1] = -0.05 * vi
				var v: PackedFloat64Array = s.sim.continuous.duplicate()
				v[0] = [3000.0, 7500.0, 12000.0][ri]
				v[1] = fuels[fi]
				var sample: Dictionary = Flight.evaluate(body, v, 0.0, s)
				if sample.is_empty(): refused_stages += 1
				else: ok_stages += 1
				stage_digests.append(digest(sample))
				var public_point: Dictionary = Flight.point(s, body, v, 0.0)
				point_digests.append(digest(public_point))
	var trajectory: Array = [tick_fingerprint(s)]
	for i in 24:
		s.sim.step()
		trajectory.append(tick_fingerprint(s))
	if not s.glow_cut():
		printerr("cut failed")
		quit(1)
		return
	for i in 24:
		s.sim.step()
		trajectory.append(tick_fingerprint(s))
	var air_tick: int = s.sim.tick
	var air_fault: String = s.sim.fault_reason
	s.free()
	var runway = make_session()
	var field: Dictionary = FieldLoader.load_from()
	if not field.get("ok",false) or not runway.set_field(field.field):
		printerr("field failed")
		quit(1)
		return
	runway.start_choice = Session.START_RUNWAY
	runway.reset()
	if not runway.is_flyable() or not runway.start_error.is_empty() or not runway.glow_start():
		printerr("runway setup failed ",runway.start_error)
		quit(1)
		return
	var ground: Array = [tick_fingerprint(runway)]
	for i in 16:
		runway.sim.step()
		ground.append(tick_fingerprint(runway))
	var ground_tick: int = runway.sim.tick
	var ground_fault: String = runway.sim.fault_reason
	runway.free()
	var event_session = make_session()
	if not event_session.set_fuel_start_fill((floor_mass+1e-7)/cap):
		printerr("fill refused")
		quit(1)
		return
	event_session.reset()
	if not event_session.is_flyable():
		printerr("fuel reset failed ",event_session.start_error)
		quit(1)
		return
	var event_rows: Array = [tick_fingerprint(event_session)]
	var event_count := 0
	for i in 4:
		event_session.sim.step()
		event_rows.append(tick_fingerprint(event_session))
		event_count += event_session.sim.last_events.size()
	var event_tick: int = event_session.sim.tick
	var event_fault: String = event_session.sim.fault_reason
	event_session.free()
	var result: Dictionary = {stage_cases=stage_digests.size(),ok_stages=ok_stages,refused_stages=refused_stages,stage_digest=digest(stage_digests),public_point_digest=digest(point_digests),air_ticks=air_tick,air_fault=air_fault,air_digest=digest(trajectory),ground_ticks=ground_tick,ground_fault=ground_fault,ground_digest=digest(ground),event_ticks=event_tick,event_count=event_count,event_fault=event_fault,event_digest=digest(event_rows),event_rows=event_rows}
	print("STAGE_PARITY_RESULT ",JSON.stringify(result))
	var good: bool = ok_stages > 0 and refused_stages > 0 and air_tick == 48 and ground_tick == 16 and event_tick == 4 and event_count > 0 and air_fault.is_empty() and ground_fault.is_empty() and event_fault.is_empty()
	print("STAGE_PARITY_PROBE ","PASS" if good else "FAIL")
	quit(0 if good else 1)
