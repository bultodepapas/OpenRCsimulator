extends SceneTree
const Step:=preload("res://physics/resource_event_step.gd")
var failures:=0
func ev(index:int,target:float,priority:int) -> Dictionary:
 return {id=["A","B"][index],type="time_boundary",sense="falling",surface_unit="s",priority=priority,
  enabled=func(state:PackedFloat64Array,_at:float)->bool:return state[13+index]==0.0,
  surface=func(_state:PackedFloat64Array,at:float)->float:return target-at,
  transition=func(state:PackedFloat64Array,_at:float)->Dictionary:
   state[13+index]=1.0
   return {ok=true,state=state}}
func run_case(target:float,dt:float,priority_a:int,priority_b:int) -> Dictionary:
 var state:=PackedFloat64Array(); state.resize(15); state[6]=1.0
 var still:=func(values:PackedFloat64Array,_at:float)->PackedFloat64Array:
  var out:=PackedFloat64Array(); out.resize(values.size()); return out
 return Step.advance(state,0.0,dt,still,PackedFloat64Array(),[ev(0,target,priority_a),ev(1,target+0.75e-12,priority_b)])
func _initialize() -> void:
 for target in [0.002]:
  var dt:=4.0e-12 if target<1.0e-10 else 1.0/240.0
  var changed:=run_case(target,dt,20,0)
  print("CASE target=%.6f ps result=%s" % [target/1e-12,JSON.stringify(changed)])
  if not changed.get("ok",false) or changed.events.size()!=2:
   failures+=1; continue
  var a:Dictionary={}
  for event:Dictionary in changed.events:
   if event.id=="A": a=event
  if a.is_empty(): failures+=1; continue
  var error:float=absf(float(a.time_s)-target)
  print("BOUND priority_later_first=%s actual_ps=%.9f reported_ps=%.9f" % [str(changed.events[0].id),error/1e-12,float(a.time_error_bound_s)/1e-12])
  if not error>float(a.time_error_bound_s): failures+=1
  var one_state:=PackedFloat64Array(); one_state.resize(15); one_state[6]=1.0
  var still:=func(values:PackedFloat64Array,_at:float)->PackedFloat64Array:
   var out:=PackedFloat64Array(); out.resize(values.size()); return out
  var one:=Step.advance(one_state,0.0,dt,still,PackedFloat64Array(),[ev(0,target,0)])
  print("SINGLE result=%s" % JSON.stringify(one))
  if not one.get("ok",false) or one.events.size()!=1 or absf(float(one.events[0].time_s)-target)>float(one.events[0].time_error_bound_s): failures+=1
  var control:=run_case(target,dt,0,20)
  print("CONTROL result=%s" % JSON.stringify(control))
  if not control.get("ok",false) or control.events.is_empty() or control.events[0].id!="A": failures+=1
 print("ROOT_BOUND_COMPLETE failures=%d" % failures)
 quit(1 if failures else 0)
