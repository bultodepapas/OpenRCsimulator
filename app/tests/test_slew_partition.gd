extends SceneTree
const Slew := preload("res://physics/slew_interval.gd")
const Actuators := preload("res://physics/control_actuators.gd")
const Step := preload("res://sim/electric_contact_step.gd")
var checks := 0
var failures := 0
var target := 0.2
var origin := 0.0
var speed := 1.0
var clock := 0.0
var forcing := "servo"
var fail_after := INF
var times: Array[float] = []

func check(label: String,ok: bool) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)

func state(rpm:=1000.0,charge:=1000.0) -> PackedFloat64Array:
	var s := PackedFloat64Array()
	s.resize(17)
	s[6]=1.0
	s[13]=rpm
	s[14]=charge
	return s

func rate(s: PackedFloat64Array,at: float) -> PackedFloat64Array:
	times.append(at)
	var out := PackedFloat64Array()
	out.resize(17)
	if at>fail_after:
		out[0]=NAN
	elif forcing=="servo":
		out[0]=Actuators.rate_limit(origin,target,speed,at-clock)
	elif forcing=="linear":
		out[0]=1.0
	else:
		if s[14]!=0.0:out[14]=-1.0
		if s[13]!=0.0:out[13]=-100.0
	return out

func project(s: PackedFloat64Array,index: int) -> PackedFloat64Array:
	var out := s.duplicate()
	out[index]=0.0
	return out

func advance(s: PackedFloat64Array,at: float,dt: float,pieces: int,cuts: PackedFloat64Array,
		first:=PackedFloat64Array()) -> Dictionary:
	return Step.advance_at_offsets(s,at,dt,rate,first,13,14,project,pieces,cuts)

func _initialize() -> void:
	var a := PackedFloat64Array([0.0,0.5,-0.5])
	var b := PackedFloat64Array([0.25,-0.5,0.5])
	var r := PackedFloat64Array([1.0,2.0,4.0])
	var before := var_to_bytes([a,b,r])
	var plan := Slew.prepare(a,b,r,1.0)
	check("sorted exact simultaneous-arrival union",plan.ok and plan.offsets==PackedFloat64Array([0.25,0.5]))
	check("original endpoint arithmetic preserved",plan.ok and plan.endpoint.to_byte_array()==Actuators.step_normalized(a,b,r,1.0).to_byte_array())
	check("planner is read-only",var_to_bytes([a,b,r])==before)
	var held := Slew.prepare(a,b,r,0.25,PackedFloat64Array([0.0,0.0,1.0]))
	check("jams and boundary arrivals do not split",held.ok and held.offsets.is_empty())
	check("zero motion does not split",Slew.prepare(a,a,r,1.0).offsets.is_empty())
	for dt: float in [0.0,-1.0,NAN,INF]:
		check("invalid duration refused",not Slew.prepare(a,b,r,dt).ok)
	check("wrong vector lengths refused",not Slew.prepare(a,PackedFloat64Array([0.0]),r,1.0).ok)
	check("nonfinite actuator refused",not Slew.prepare(PackedFloat64Array([NAN]),PackedFloat64Array([0.0]),PackedFloat64Array([1.0]),1.0).ok)
	check("unrepresentable arrival refused",not Slew.prepare(PackedFloat64Array([0.0]),PackedFloat64Array([1e-300]),PackedFloat64Array([1e308]),1.0).ok)
	var many := PackedFloat64Array()
	many.resize(Slew.MAX_CHANNELS+1)
	check("bounded channel count",not Slew.prepare(many,many,many,1.0).ok)
	var close := Slew.prepare(PackedFloat64Array([0.0,0.0]),PackedFloat64Array([0.25,0.25+5.551115123125783e-17]),PackedFloat64Array([1.0,1.0]),1.0)
	check("distinct arrivals are not epsilon merged",close.ok and close.offsets.size()==2)
	for fraction: float in [0.08,0.16,0.32,0.64,0.28]:
		for sign: float in [1.0,-1.0]:
			origin=0.0
			target=sign*fraction
			speed=1.0
			var analytic := sign*(fraction-0.5*fraction*fraction)
			var split := advance(state(),0.0,1.0,1,PackedFloat64Array([fraction]))
			var unsplit := Step.advance(state(),0.0,1.0,rate,PackedFloat64Array(),13,14,project,1)
			check("split ramp quadrature matches independent integral",split.ok and absf(split.state[0]-analytic)<3e-15)
			check("unsplit quadrature exposes kink error",unsplit.ok and absf(unsplit.state[0]-analytic)>1e-6)
	forcing="linear"
	var initial := state()
	var first := rate(initial,0.0)
	var old := Step.advance(initial,0.0,1.0,rate,first,13,14,project,2)
	check("empty partition keeps legacy bits",var_to_bytes(advance(initial,0.0,1.0,2,PackedFloat64Array(),first))==var_to_bytes(old))
	check("coincident partition keeps legacy bits",var_to_bytes(advance(initial,0.0,1.0,2,PackedFloat64Array([0.5,0.5]),first))==var_to_bytes(old))
	times.clear()
	var merged := advance(initial,0.0,1.0,16,PackedFloat64Array([0.01,0.02,0.03]),first)
	check("sixteen contact pieces plus three cuts admitted",merged.ok and absf(merged.state[0]-1.0)<3e-15)
	check("later pieces refresh first derivative",not times.has(0.0) and times.count(0.01)>=2)
	for cuts: PackedFloat64Array in [PackedFloat64Array([0.0]),PackedFloat64Array([1.0]),PackedFloat64Array([NAN]),PackedFloat64Array([INF]),PackedFloat64Array([0.1,0.2,0.3,0.4])]:
		check("invalid explicit cut refused",not advance(initial,0.0,1.0,1,cuts).ok)
	times.clear()
	check("absolute-clock collapse rejected before evaluation",not advance(initial,65536.0,1.0/240.0,1,PackedFloat64Array([1e-20])).ok and times.is_empty())
	times.clear()
	check("large-clock piece gap rejected before evaluation",not advance(initial,4503599627370496.0,4.0,1,PackedFloat64Array([0.51,2.49])).ok and times.is_empty())
	times.clear()
	var ulp := pow(2.0,-36.0)
	check("pieces too close to clock resolution refused",not advance(initial,65536.0,4.0*ulp,1,PackedFloat64Array([0.51*ulp,2.49*ulp])).ok and times.is_empty())
	var saved := initial.to_byte_array()
	fail_after=0.5
	var failed := advance(initial,0.0,1.0,1,PackedFloat64Array([0.3]))
	check("later failure is atomic",not failed.ok and not failed.has("state") and not failed.has("events") and initial.to_byte_array()==saved)
	fail_after=INF
	forcing="events"
	var events := advance(state(100.0,1.0),4.0,2.0,2,PackedFloat64Array([0.3,0.7]))
	check("merged-cut simultaneous events stay ordered",events.ok and events.events.size()==2 and events.events[0].type=="rotor_stop" and events.events[1].type=="battery_exhausted" and absf(events.events[0].time_s-5.0)<1e-10)
	var late := advance(state(0.0,1.0/240.0),65536.0,1.0/240.0,1,PackedFloat64Array([1.0/480.0]))
	check("late-clock exhaustion remains bounded",late.ok and late.events.size()==1 and absf(late.events[0].time_s-(65536.0+1.0/240.0))<1e-9)
	print("SLEW_PARTITION_TEST %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
