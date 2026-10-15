# Deliberate impact fixtures; never used by production or presented as pilot validation.
extends RefCounted
const M=preload("res://physics/math3d.gd")
static func trigger(session: Node, scenario: String) -> bool:
 if not session.reset(): return false
 var height: float=.36
 var pitch: float=0.0
 var roll: float=.7
 var speed: float=4.0
 match scenario:
  "tail": height=.65; pitch=.4; roll=PI; speed=2.5
  "hard": height=.16; pitch=-.06; roll=0.0; speed=9.0
  "nose": height=.50; pitch=-1.2; roll=0.0; speed=4.0
  "severe": height=.8; pitch=-1.55; roll=0.0; speed=32.0
 session.sim.state[0]=6.0; session.sim.state[1]=0.0; session.sim.state[2]=-height
 var q: PackedFloat64Array=M.q_from_euler(0,pitch,roll)
 for i: int in 4: session.sim.state[6+i]=q[i]
 var velocity: PackedFloat64Array=M.q_rotate(M.q_conj(q),PackedFloat64Array([2.0,0.0,speed]))
 for i: int in 3:
  session.sim.state[3+i]=velocity[i]
  session.sim.state[10+i]=0.0
 if scenario in ["nose","severe"]:
  session.sim.continuous[0]=0.0
  session.power.armed=false
  session.zero_drive_hold=true
  session.shaft_phase=PackedFloat64Array([PI/2,0.0])
  session._phase_omega=PackedFloat64Array([0.0,0.0])
 session.sim.previous=session.sim.state.duplicate()
 if scenario=="fence":
  var obstacle: Dictionary={}
  for proxy: Dictionary in session.collision_world().get("proxies",[]):
   if proxy.kind=="fence" and proxy.shape=="box" and proxy.half_down>.25:
    obstacle=proxy; break
  if obstacle.is_empty(): return false
  session.sim.state=PackedFloat64Array([obstacle.bounds_north_min-.75,obstacle.east,obstacle.down,24,0,0,1,0,0,0,0,0,0])
  session.sim.previous=session.sim.state.duplicate()
 for i: int in 30:
  session.sim.step()
  if not session.is_flyable(): return not session.crash.is_empty()
 return false
