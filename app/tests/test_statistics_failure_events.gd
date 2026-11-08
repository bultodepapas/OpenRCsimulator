extends SceneTree
const Session=preload("res://sim/flight_session.gd")
const Service=preload("res://statistics/service.gd")
const Schema=preload("res://statistics/schema.gd")
const RB=preload("res://physics/rigid_body.gd")
const AIRCRAFT="jensen-das-ugly-stik-60"
class FakeClock:
 extends RefCounted
 var tick:=0
class FakeFlight:
 extends Node
 signal failure_changed
 var sim=FakeClock.new()
 var status: Dictionary={}
 func failure_status() -> Dictionary: return status.duplicate(true)
class FakeDetector:
 extends RefCounted
 var flight: Dictionary={}
 var _phase: String="takeoff_pending"
 var _first_unsupported_tick: int=-1
var checks:=0
var failures:=0
func _initialize() -> void:
 Engine.physics_ticks_per_second=240
 _run.call_deferred()
func check(label: String,ok: bool,detail: String="") -> void:
 checks+=1
 if not ok:
  failures+=1
  printerr("FAIL ",label," ",detail)
func record_events(record: Dictionary) -> Array:
 var found: Array=[]
 for event: Dictionary in record.get("metadata",{}).get("events",[]):
  if event.get("type")=="failure_activated": found.append(event)
 return found
func flight_snapshot() -> Dictionary:
 return {airborne_seconds=1.0,outcome="active",start_kind="air_start",full_stops=0,touch_and_go=0,failed_landings=0,unknown_landings=0,max_tas_mps=-1.0,max_groundspeed_mps=-1.0,complete_observation=false}
func start_fixture(service: Node,fake: Node,tick: int,first_unsupported: int) -> void:
 service.detector._first_unsupported_tick=first_unsupported
 service.detector.flight=flight_snapshot()
 service._ingest([{type="started",start_kind="air_start",tick=tick,flight=service.detector.flight.duplicate(true)}])
func fake_service() -> Dictionary:
 var s=Service.new(); root.add_child(s); s.setup("",false)
 var fake=FakeFlight.new(); root.add_child(fake)
 s._session=fake
 s.detector=FakeDetector.new()
 s._generation="test-generation"
 s._aircraft_id="stock:a"
 s._aircraft_name="A"
 s._ensure_session()
 return {service=s,flight=fake}
func fake_free(pair: Dictionary) -> void:
 pair.service._session=null
 pair.service.detector=null
 pair.service.free()
 pair.flight.free()
func set_fake_status(fake: Node,tick: int,id: String="roll_jam",active: bool=true) -> void:
 fake.sim.tick=tick
 fake.status={active=active,event_id=id,activation_tick=tick}
func _pending_and_admission() -> void:
 var pair: Dictionary=fake_service()
 var s: Node=pair.service
 var f: Node=pair.flight
 set_fake_status(f,5)
 s._branch=true
 s._failure_changed()
 check("branch refuses activation before sampling",s._pending_failure.is_empty() and s.data.records.is_empty())
 s._branch=false
 s._suspended=true
 s._failure_changed()
 check("suspension refuses activation",s._pending_failure.is_empty() and s.data.records.is_empty())
 s._suspended=false
 f.status.active=false
 s._failure_changed()
 check("selected but inactive plan never creates evidence",s._pending_failure.is_empty() and s.data.records.is_empty())
 set_fake_status(f,5)
 s._failure_changed()
 s._failure_changed()
 check("accepted notification queues one bounded pending event",s._pending_failure.get("event",{}).get("tick")==5 and s.data.records.is_empty())
 start_fixture(s,f,6,4)
 var recorded: Array=record_events(s._active_record)
 check("same-flight pending event attaches on admission",recorded.size()==1 and recorded[0]=={type="failure_activated",failure_id="roll_jam",tick=5,source="accepted_failure_signal_v1"})
 var timeline: Array=s._active_record.metadata.events
 check("delayed admission preserves accepted event tick order",timeline.size()==2 and timeline[0].type=="failure_activated" and timeline[1].type=="started" and timeline[0].tick<timeline[1].tick)
 check("recorded activation validates in the statistics schema",Schema.validate(s.data).ok)
 fake_free(pair)
 pair=fake_service(); s=pair.service; f=pair.flight
 set_fake_status(f,5)
 s._failure_changed()
 start_fixture(s,f,8,7)
 check("rejected earlier episode cannot contaminate a later flight",record_events(s._active_record).is_empty() and s._pending_failure.is_empty())
 fake_free(pair)
func _closed_same_tick() -> void:
 var pair: Dictionary=fake_service()
 var s: Node=pair.service
 var f: Node=pair.flight
 start_fixture(s,f,1,1)
 var id: String=s._active_record.id
 var closed: Dictionary=s.detector.flight.duplicate(true)
 s._ingest([{type="closed",outcome="interrupted",tick=5,flight=closed}])
 s.detector.flight={}
 s.detector._phase="terminal"
 set_fake_status(f,5)
 s._failure_changed()
 s._failure_changed()
 var events: Array=record_events(s.data.records[0])
 check("same-tick closed flight receives actual activation once",s.data.records[0].id==id and events.size()==1 and events[0].tick==5 and events[0].source=="accepted_failure_signal_v1")
 s.detector._phase="takeoff_pending"
 start_fixture(s,f,10,9)
 check("same-tick closed event never leaks to a later flight",record_events(s._active_record).is_empty())
 check("terminal record schema remains valid",Schema.validate(s.data).ok)
 fake_free(pair)
 pair=fake_service(); s=pair.service; f=pair.flight
 start_fixture(s,f,1,1)
 var prior_id: String=s._active_record.id
 s._ingest([{type="closed",outcome="interrupted",tick=5,flight=s.detector.flight.duplicate(true)}])
 start_fixture(s,f,5,5)
 set_fake_status(f,5)
 s._failure_changed()
 check("same-tick next flight cannot steal closed-flight activation",s.data.records[0].id==prior_id and record_events(s.data.records[0]).size()==1 and record_events(s._active_record).is_empty())
 fake_free(pair)
func _bounds() -> void:
 var pair: Dictionary=fake_service()
 var s: Node=pair.service
 var f: Node=pair.flight
 start_fixture(s,f,1,1)
 var events: Array=[]
 for i: int in 128: events.append({type="other",tick=i})
 s._active_record.metadata.events=events
 s._active_record.metadata.events_omitted=0
 set_fake_status(f,5)
 s._failure_changed()
 check("activation respects 128-event limit and increments omission",s._active_record.metadata.events.size()==128 and s._active_record.metadata.events_omitted==1 and record_events(s._active_record).is_empty())
 check("bounded omission is persisted",s.data.records[0].metadata.events_omitted==1 and Schema.validate(s.data).ok)
 fake_free(pair)
 pair=fake_service(); s=pair.service; f=pair.flight
 start_fixture(s,f,1,1)
 for i: int in 16: s._active_record.metadata["padding_%d"%i]="x".repeat(4000)
 var needed: int=Schema.MAX_METADATA_BYTES-330-var_to_bytes(s._active_record.metadata).size()-24
 if needed>0 and needed<=4096: s._active_record.metadata.padding_tail="x".repeat(needed)
 var initial_size: int=var_to_bytes(s._active_record.metadata).size()
 set_fake_status(f,5)
 s._failure_changed()
 check("activation respects metadata byte budget",initial_size<=Schema.MAX_METADATA_BYTES and s._active_record.metadata.get("events_omitted",0)==1 and record_events(s._active_record).is_empty(),str(initial_size))
 check("byte-budget omission remains schema-valid",Schema.validate(s.data).ok)
 fake_free(pair)
func _new_flight() -> Node:
 var f=Session.new()
 f.input_enabled=false
 f.setup()
 var initial: PackedFloat64Array=f.sim.state.duplicate()
 initial[RB.POS+2]=-1000.0
 check("real flight starts airborne",f.sim.reset(initial) and f._failure_airborne())
 var config: Dictionary={probability_percent=100,include_catastrophic=false,notify=true}
 check("real failure plan prepared",f.setup_failures(config,2063),f.failure_error)
 return f
func _integrated() -> void:
 var player: Node=_new_flight()
 var reference: Node=_new_flight()
 var onset: int=int(player._failures.plan().onset_airborne_ticks)
 check("fixture selects known roll-jam onset",onset==4800 and player._failures.plan().id=="roll_jam")
 var service=Service.new(); root.add_child(service); service.setup("",false)
 var metadata: Dictionary={launch_context_format="test-v1",scenario={kind="random"},failure_config={probability_percent=100},failure_seed=2063}
 service.begin_activity(player,AIRCRAFT,"Ugly Stick",metadata)
 var terminal=Service.new(); root.add_child(terminal); terminal.setup("",false)
 var synthetic_closed: Array=[false]
 player.contact_events_changed.connect(func() -> void:
  if player.sim.tick==onset and bool(player.failure_status().get("active",false)) and not terminal._active_record.is_empty():
   var frame: Dictionary=terminal.detector.flight.duplicate(true)
   terminal._ingest([{type="closed",outcome="interrupted",tick=onset,flight=frame}])
   terminal.detector.flight={}
   terminal.detector._phase="terminal"
   synthetic_closed[0]=true)
 terminal.begin_activity(player,AIRCRAFT,"Ugly Stick",metadata)
 check("failure observer is connected once",player.failure_changed.is_connected(Callable(service,"_failure_changed")) and player.failure_changed.is_connected(Callable(terminal,"_failure_changed")))
 var valid:=true
 var physical:=true
 for i: int in range(onset-1):
  player.sim.step(); reference.sim.step()
  if not player.is_flyable() or not reference.is_flyable(): valid=false; break
  physical=physical and var_to_bytes(player.sim.checkpoint())==var_to_bytes(reference.sim.checkpoint())
 check("pre-onset accepted flight reaches boundary",valid and player.sim.tick==onset-1 and not player.failure_status().active and not service._active_record.is_empty())
 check("enabled but inactive plan was not recorded",record_events(service._active_record).is_empty())
 var checkpoint: Dictionary=player.checkpoint()
 player.sim.step(); reference.sim.step()
 physical=physical and var_to_bytes(player.sim.checkpoint())==var_to_bytes(reference.sim.checkpoint())
 var status: Dictionary=player.failure_status()
 var active_events: Array=record_events(service._active_record)
 check("real accepted activation records its ID and tick",status.active and status.activation_tick==onset and active_events.size()==1 and active_events[0]=={type="failure_activated",failure_id="roll_jam",tick=onset,source="accepted_failure_signal_v1"})
 check("observation preserves paired physical checkpoints",physical)
 var closed_events: Array=[]
 for record: Dictionary in terminal.data.records:
  if record.kind=="flight": closed_events.append_array(record_events(record))
 check("synthetic same-tick terminal ordering records the accepted failure",synthetic_closed[0] and closed_events.size()==1 and closed_events[0].tick==onset)
 player.failure_changed.emit()
 check("duplicate same-tick notice cannot duplicate event",record_events(service._active_record).size()==1)
 var after_duplicate:=0
 for record: Dictionary in terminal.data.records:
  if record.kind=="flight": after_duplicate+=record_events(record).size()
 check("duplicate notice cannot duplicate just-closed record",after_duplicate==1)
 var original_scenario: Variant=service._active_record.metadata.get("scenario")
 service.invalidate_launch_context(true)
 check("scenario invalidation keeps current flight and known failure context",not service._metadata.has("scenario") and service._metadata.has("failure_config") and service._active_record.metadata.get("scenario")==original_scenario)
 var generation: String=service._generation
 check("pre-onset checkpoint restore succeeds",player.restore_checkpoint(checkpoint))
 check("restore branches and forgets future launch provenance",service._branch and not service._metadata.has("scenario") and not service._metadata.has("launch_context_format") and not service._metadata.has("failure_config") and not service._metadata.has("failure_seed"))
 var retained: int=0
 for record: Dictionary in service.data.records:
  if record.kind=="flight": retained+=record_events(record).size()
 check("accepted activation survives the closing restore",retained==1)
 player.reset()
 check("restart changes generation and reenables observation",not service._branch and service._generation!=generation and player.failure_changed.is_connected(Callable(service,"_failure_changed")))
 service.suspend_activity()
 check("trial suspension disconnects failure listener",not player.failure_changed.is_connected(Callable(service,"_failure_changed")))
 service.resume_activity()
 service.resume_activity()
 check("resume reconnects failure listener exactly once",player.failure_changed.is_connected(Callable(service,"_failure_changed")) and player.failure_changed.get_connections().filter(func(c: Dictionary) -> bool: return c.callable==Callable(service,"_failure_changed")).size()==1)
 service.persistent=true
 service.store.writable=false
 check("failed final save retains failure subscription",not service.end_activity() and player.failure_changed.is_connected(Callable(service,"_failure_changed")))
 service.persistent=false
 check("successful end detaches failure listener",service.end_activity() and not player.failure_changed.is_connected(Callable(service,"_failure_changed")))
 terminal.end_activity()
 terminal.free(); service.free(); player.free(); reference.free()
func _run() -> void:
 _pending_and_admission()
 _closed_same_tick()
 _bounds()
 _integrated()
 print("F16 accepted failure events: %d checks, %d failures"%[checks,failures])
 quit(1 if failures else 0)
