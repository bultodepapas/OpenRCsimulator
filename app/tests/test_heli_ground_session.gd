extends SceneTree
const Session=preload("res://sim/helicopter_flight_session.gd")
const Field=preload("res://data/field_loader.gd")
const M=preload("res://physics/math3d.gd")
const Wind=preload("res://physics/wind_config.gd")
var checks:=0
var failures:=0
var session: Node
func check(label: String,ok: bool) -> void:
	checks+=1
	if not ok: failures+=1; print("FAIL ",label)
func steps(count: int) -> bool:
	for i: int in count:
		session.sim.step()
		if not session.is_flyable(): print("FAULT ",session.pause_reason); return false
	return true
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	session=Session.new()
	session.physics_enabled=false
	session.input_enabled=false
	root.add_child(session)
	var field: Dictionary=Field.load_from(Field.DEFAULT_PATH)
	check("default field loads",field.ok)
	check("selected ground setup",session.setup() and session.set_field(field.field) and session.set_start_choice("ground") and session.reset())
	if not session.is_flyable(): print(session.start_error); session.free(); quit(1); return
	check("pad starts near midpoint off runway",session.sim.state[0]==6.0 and session.sim.state[1]==0.0)
	check("ground rotor and wake start at zero",session.sim.continuous[0]==0.0 and session.sim.continuous[3]==0.0)
	check("zero pitch derives low startup stick",absf(session.commands.throttle-1.0/6.0)<1e-12 and absf(session.collective_pitch())<1e-12)
	check("ground starts disarmed in hold",not session.power.armed and session.zero_drive_hold)
	check("cannot release hold before motor arm",not session.set_drive_hold(false) and session.zero_drive_hold)
	var rest: PackedFloat64Array=session.sim.state.duplicate()
	check("sixty second rotor-off rest stays finite",steps(14400))
	var drift: float=M.norm(M.sub(session.sim.state.slice(0,3),rest.slice(0,3)))
	var qdot: float=0.0
	for i: int in 4: qdot+=session.sim.state[6+i]*rest[6+i]
	qdot=absf(qdot)
	check("rest stays within 1 mm and 0.1 degree",drift<.001 and 2.0*acos(clampf(qdot,-1.0,1.0))<PI/1800.0)
	check("rest cannot self-start",session.sim.continuous[0]==0.0 and not session.power.armed)
	print("GROUND REST drift_m=",drift)
	check("reset retains selected pad and disarmed state",session.reset() and not session.power.armed and session.zero_drive_hold)
	session.commands.throttle=.8
	check("high collective cannot arm",not session.toggle_motor_arm())
	session.commands.throttle=session.startup_collective
	session.sim.inputs[3]=session.commands.throttle
	check("explicit arm keeps hold",session.toggle_motor_arm() and session.power.armed and session.zero_drive_hold)
	check("explicit hold release starts soft ramp",session.set_drive_hold(false) and session.trace_controls()[3]==0.0)
	check("spool starts without fault",steps(480))
	var saved: Dictionary=session.checkpoint()
	check("spooling checkpoint records lifecycle",not saved.is_empty() and saved.power.armed and not saved.zero_drive_hold and saved.start_choice=="ground")
	if saved.is_empty(): session.free(); quit(1); return
	check("spool advances",steps(480))
	var endpoint: PackedByteArray=session.sim.state.to_byte_array()
	var rotor: PackedByteArray=session.sim.continuous.to_byte_array()
	var phase: PackedByteArray=session.shaft_phase.to_byte_array()
	check("restore during spool is paused",session.restore_checkpoint(saved).ok and session.sim.paused)
	check("spool replay advances full ticks",steps(480))
	check("body rotor and phase replay exactly",endpoint==session.sim.state.to_byte_array() and rotor==session.sim.continuous.to_byte_array() and phase==session.shaft_phase.to_byte_array())
	var unchanged: PackedByteArray=var_to_bytes(session.checkpoint())
	var bad: Dictionary=saved.duplicate(true)
	bad.power.spool_start_s=1e20
	check("future ramp state is refused atomically",not session.restore_checkpoint(bad).ok and var_to_bytes(session.checkpoint())==unchanged)
	session.resume()
	check("spool reaches running state",steps(2400) and session.power_phase()=="GOVERNED")
	print("SPOOL RPM=",session.sim.aux[0]," state=",session.sim.state," power=",session.power_phase())
	check("spool keeps pad position within 2 mm",M.norm(M.sub(session.sim.state.slice(0,3),rest.slice(0,3)))<.002)
	check("spool keeps heading within 1.5 degrees",absf(M.q_to_euler(session.sim.state.slice(6,10))[0]-PI/2)<1.5*PI/180.0)
	check("zero pitch does not cause automatic liftoff",-session.sim.state[2]<.2)
	session.set_controller_cut(true)
	session.set_controller_cut(false)
	check("cut release cannot restart motor",session.zero_drive_hold)
	check("held coast-down consumes full ticks",steps(14400))
	print("STOP RPM=",session.sim.aux[0])
	check("coast-down reaches exact zero",session.sim.continuous[0]==0.0)
	check("stopped hold has no drive-induced restart",steps(240) and session.sim.continuous[0]==0.0)
	check("disarm latches hold",session.toggle_motor_arm() and not session.power.armed and session.zero_drive_hold)
	check("new reset still cold",session.reset() and session.sim.continuous[0]==0.0)
	# Real curve change is explicit; no silent movement of the pilot stick.
	session.commands.throttle=.5
	var stick: float=session.commands.throttle
	check("large mode pitch jump needs a second explicit action",not session.request_flight_mode() and session.flight_mode=="normal")
	check("second mode action applies the authored curve",session.request_flight_mode() and session.flight_mode=="idle_up" and session.commands.throttle==stick)
	session.free()
	print("HELI-20 ground session: %d checks, %d failed"%[checks,failures])
	quit(1 if failures else 0)
