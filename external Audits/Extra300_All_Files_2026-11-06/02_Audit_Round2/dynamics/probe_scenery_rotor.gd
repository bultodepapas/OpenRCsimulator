extends SceneTree
const Session = preload("res://sim/flight_session.gd")
const RB = preload("res://physics/rigid_body.gd")
const M = preload("res://physics/math3d.gd")

func _initialize() -> void:
	call_deferred("run")

func kinetic(s: PackedFloat64Array, props: Dictionary, axis: PackedFloat64Array, inertia: float, rpm: float) -> float:
	var w: PackedFloat64Array = s.slice(RB.RATE, RB.RATE+3)
	var vc: PackedFloat64Array = M.add(s.slice(RB.VEL,RB.VEL+3),M.cross(w,props.cg_body_m))
	var omega: float = rpm*TAU/60.0
	return 0.5*props.mass_kg*M.dot(vc,vc)+0.5*M.dot(w,RB.inertia_mul(props.inertia,w))+inertia*omega*M.dot(axis,w)+0.5*inertia*omega*omega

func point_velocity(s: PackedFloat64Array, point: PackedFloat64Array) -> PackedFloat64Array:
	return M.q_rotate(RB._att(s),M.add(s.slice(RB.VEL,RB.VEL+3),M.cross(s.slice(RB.RATE,RB.RATE+3),point)))

func box_world(point: PackedFloat64Array, pos: PackedFloat64Array, vdown: float, dt: float) -> Dictionary:
	var n: float = pos[0]+point[0]+0.5*15.0*dt
	var e: float = pos[1]+point[1]
	var face: float = pos[2]+point[2]+0.5*vdown*dt
	var down: float = face-0.2
	var proxy := {"id":"audit:crown", "kind":"tree_foliage", "part":"crown", "shape":"box",
		"response_class":"soft_foliage_impulse", "damage_id":"", "damage_profile":"none",
		"north":n, "east":e, "down":down, "radius":0.0, "half_length":0.0,
		"half_x":0.06, "half_down":0.2, "half_z":0.50,
		"sin_heading":0.0, "cos_heading":1.0,
		"bounds_north_min":n-0.5,"bounds_north_max":n+0.5,
		"bounds_east_min":e-0.06,"bounds_east_max":e+0.06,
		"bounds_down_min":down-0.2,"bounds_down_max":down+0.2}
	var bins := {}
	for ni: int in [-1,0]:
		for ei: int in [-1,0]:
			for di: int in [-1,0]:
				bins["%d,%d,%d" % [ni,ei,di]]=PackedInt64Array([0])
	return {"format":"openrc-collision-world v1","identity":"audit-crown-fixture-v1","cell_size_m":32.0,"proxies":[proxy],"bins":bins}

func run_case(stopped: bool) -> Dictionary:
	var s = Session.new()
	s.input_enabled = false
	s.soft_hull_contacts = true
	s.crash_auto_restart = false
	s.setup("res://data/aircraft/gp_extra_300s_60.json","gp-extra-300s-60")
	if not s.is_flyable():
		printerr("not flyable ",s.start_error)
		return {}
	var p: PackedFloat64Array = s.aircraft.model.crash_hull.slice(3,6)
	var pos := M.v3(0.0,0.0,-10.0)
	var down_speed := -0.15
	var world := box_world(p,pos,down_speed,s.sim.dt())
	if not s.set_collision_world(world):
		printerr("world refused")
		return {}
	if stopped:
		if not s.glow_cut():
			printerr("cut refused")
			return {}
		s.sim.continuous[0]=0.0
		s.sim.aux[Session.AUX_RPM]=0.0
	var initial := RB.make_state(pos,M.v3(0.0 if stopped else 15.0,0.0,down_speed),M.q_identity(),M.v3(0.0,0.0,0.0))
	if not s.sim.reset(initial):
		printerr("reset failed ",s.sim.fault_reason)
		return {}
	var rpm_start: float = s.sim.continuous[0]
	s.sim.step()
	var event = s.last_scenery_event()
	if event==null or event.terminal or s.sim.tick!=1 or not s.sim.fault_reason.is_empty():
		print("NO_EVENT stopped=",stopped," tick=",s.sim.tick," fault=",s.sim.fault_reason," crash=",s.crash)
		s.free()
		return {}
	var before: PackedFloat64Array=event.contact_state()
	var after: PackedFloat64Array=s.sim.state
	var props: Dictionary=event.contact_mass_properties
	var axis: PackedFloat64Array=s.aircraft.model.propulsion.axis
	var j: float=s.aircraft.model.propulsion.rotor_inertia
	var rpm_end: float=s.sim.continuous[0]
	var w0: PackedFloat64Array=before.slice(RB.RATE,RB.RATE+3)
	var w1: PackedFloat64Array=after.slice(RB.RATE,RB.RATE+3)
	var dw: PackedFloat64Array=M.sub(w1,w0)
	var v0: PackedFloat64Array=M.add(before.slice(RB.VEL,RB.VEL+3),M.cross(w0,props.cg_body_m))
	var v1: PackedFloat64Array=M.add(after.slice(RB.VEL,RB.VEL+3),M.cross(w1,props.cg_body_m))
	var impulse_body: PackedFloat64Array=M.scale(M.sub(v1,v0),props.mass_kg)
	var impulse_ned: PackedFloat64Array=M.q_rotate(RB._att(before),impulse_body)
	var vp0: PackedFloat64Array=point_velocity(before,event.body_point)
	var vp1: PackedFloat64Array=point_velocity(after,event.body_point)
	var impulse_work: float=0.5*M.dot(impulse_ned,M.add(vp0,vp1))
	var arm: PackedFloat64Array=M.sub(event.body_point,props.cg_body_m)
	var angular_impulse: PackedFloat64Array=M.cross(arm,impulse_body)
	var delta_h: PackedFloat64Array=RB.inertia_mul(props.inertia,dw) # relative spin did not change inside filter
	var h_error: float=M.norm(M.sub(delta_h,angular_impulse))
	var energy_delta: float=kinetic(after,props,axis,j,rpm_end)-kinetic(before,props,axis,j,rpm_end)
	var energy_zero: float=kinetic(after,props,axis,j,0.0)-kinetic(before,props,axis,j,0.0)
	var cross_term: float=j*(rpm_end*TAU/60.0)*M.dot(axis,dw)
	var result := {stopped=stopped, tick=s.sim.tick, fraction=event.time_fraction, point=event.body_point, normal=event.normal_ned,
		normal_speed=event.normal_speed_mps, rpm_start=rpm_start, rpm_end=rpm_end,
		status=event.response_status, terminal=event.terminal, crash=s.crash, fault=s.sim.fault_reason,
		mass=props.mass_kg, cg=props.cg_body_m, inertia=props.inertia, shaft_inertia=j, shaft_axis=axis,
		delta_omega=dw, impulse=impulse_body, normal_work=impulse_work, body_only_delta=energy_zero,
		full_delta=energy_delta, cross_term=cross_term, balance_residual=energy_delta-impulse_work-cross_term,
		angular_momentum_residual=h_error, reported_dissipation=event.dissipated_energy_j,
		wheel_speeds=s.sim.continuous.slice(s.wheel_index(),s.wheel_index()+s.wheel_count())}
	print("RESULT ",JSON.stringify(result))
	s.free()
	return result

func run() -> void:
	var spinning: Dictionary=run_case(false)
	var stopped: Dictionary=run_case(true)
	var valid: bool=not spinning.is_empty() and not stopped.is_empty()
	if valid:
		valid=spinning.full_delta>0.0 and spinning.normal_work<0.0 and spinning.body_only_delta<0.0 and spinning.rpm_end>300.0 and absf(spinning.balance_residual)<1e-8 and spinning.angular_momentum_residual<1e-8 and absf(stopped.rpm_end)<1.0 and stopped.full_delta<0.0
	print("SCENERY_ROTOR_REPRO ","PASS" if valid else "FAIL")
	quit(0 if valid else 1)
