extends SceneTree
const Flight=preload("res://sim/flight_session.gd")
const Adapter=preload("res://physics/glow/flight.gd")
const RB=preload("res://physics/rigid_body.gd")
var checks:=0
var failures:=0
func check(label: String,ok: bool):
	checks+=1
	if not ok:
		failures+=1
		print("FAIL ",label)
func advance(f: Node,count: int) -> bool:
	var tick: int=f.sim.tick
	for _i in count:
		f.sim.step()
		if not f.sim.fault_reason.is_empty():
			print(f.sim.fault_reason)
			return false
	return f.sim.tick==tick+count
func make(id: String) -> Node:
	var f=Flight.new()
	f.setup("res://data/aircraft/stik_glow_"+id+".json")
	f.input_enabled=false
	return f
func _initialize():
	for id in ["55ax_2t","fs64v_4t"]:
		var f=make(id)
		check(id+" loads coupled",f.is_flyable() and f.glow_is_active() and f.shaft_is_coupled())
		if not f.is_flyable():f.free();continue
		var init: PackedFloat64Array=f.sim.continuous.duplicate()
		check(id+" trim flight advances",advance(f,120))
		check(id+" finite fuel and phase",f.sim.continuous[1]<init[1] and f.sim.continuous[9]>0. and f.sim.continuous[10]>0.)
		var snapshot: Dictionary=f.checkpoint()
		check(id+" explicit checkpoint",snapshot.get("format")=="openrc-flight-checkpoint v9")
		f.sim.inputs[3]=1.
		check(id+" throttle response",advance(f,180) and f.sim.continuous[0]>init[0])
		var expected: PackedByteArray=var_to_bytes([f.sim.state,f.sim.continuous,f.sim.aux,f.sim.modes])
		check(id+" restore",f.restore_checkpoint(snapshot))
		f.sim.inputs[3]=1.
		check(id+" deterministic replay",advance(f,180) and var_to_bytes([f.sim.state,f.sim.continuous,f.sim.aux,f.sim.modes])==expected)
		var invalid: Dictionary=snapshot.duplicate(true)
		invalid.simulation.continuous[1]=-1.
		check(id+" negative tank checkpoint rejected",not f.restore_checkpoint(invalid))
		invalid=snapshot.duplicate(true);invalid.simulation.continuous[10]=.5
		check(id+" fractional event count rejected",not f.restore_checkpoint(invalid))
		check(id+" cut command",f.glow_cut())
		var fuel: float=f.sim.continuous[1]
		var cutrpm: float=f.sim.continuous[0]
		check(id+" cut coasts",advance(f,120) and f.sim.continuous[0]<cutrpm and f.sim.continuous[0]>0.)
		check(id+" cut cannot resurrect and burns no fuel",f.sim.continuous[1]==fuel and not f.glow_state().running and f.glow_state().chemical_power_w==0.)
		check(id+" explicit starter restart",f.glow_start())
		check(id+" restart advances",advance(f,120) and f.glow_state().running and f.sim.continuous[1]<fuel)
		var before: Dictionary=f.sim.checkpoint()
		f.sim.continuous[2]=NAN
		f.sim.step()
		check(id+" failed step rollback",not f.sim.fault_reason.is_empty() and f.sim.continuous==before.continuous and f.sim.state==before.state)
		f.reset()
		check(id+" reset restores all engine state",f.is_flyable() and f.sim.continuous==init)
		# Exhaust in the next tick from a positive left limit, then continue coasting.
		f.sim.continuous[1]=1e-8
		check(id+" exact exhaustion event",advance(f,2) and f.sim.continuous[1]==0. and f.glow_state().stop_reason=="fuel_exhausted")
		check(id+" exhausted engine cannot start",not f.glow_start())
		check(id+" exhausted coast",advance(f,40) and f.sim.continuous[1]==0.)
		f.reset()
		check(id+" runway pose",f.reset_on_runway(0.,0.,0.))
		check(id+" sustained warm idle",advance(f,240) and f.glow_state().running)
		f.sim.inputs[3]=1.
		check(id+" takeoff acceleration",advance(f,720) and f.sim.state[RB.VEL]>5.)
		print(id," runway at3s ",f.sim.state.slice(0,6)," rpm ",f.sim.continuous[0])
		f.free()
	print("Glow session: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
