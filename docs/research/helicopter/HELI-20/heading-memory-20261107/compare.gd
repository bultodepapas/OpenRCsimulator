extends SceneTree
const Session=preload("res://sim/helicopter_flight_session.gd")
const Field=preload("res://data/field_loader.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
 var report: Dictionary={format="helicopter baseline/candidate tape comparison v1", cases={}}
 var all_ok: bool=true
 for name: String in ["positive","negative"]:
  var baseline_file: FileAccess=FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/audit2-20261107-heli-baseline/"+name+".tape",FileAccess.READ)
  var candidate_file: FileAccess=FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/audit2-20261107-heli-candidate/"+name+".tape",FileAccess.READ)
  var baseline: Dictionary=baseline_file.get_var()
  var candidate: Dictionary=candidate_file.get_var()
  var session=Session.new()
  session.physics_enabled=false; session.input_enabled=false; root.add_child(session)
  var ready: bool=session.setup() and session.set_field(Field.load_from().field) and session.set_start_choice("ground") and session.reset()
  var old: Dictionary=session.restore_checkpoint(baseline.initial)
  var saved: Dictionary=session.restore_checkpoint(candidate.initial)
  var equal: bool=var_to_bytes(baseline.inputs)==var_to_bytes(candidate.inputs)
  var ok: bool=ready and equal and not old.ok and str(old.errors).contains("heading-memory law") and saved.ok
  report.cases[name]={input_bytes_identical=equal,ticks=baseline.inputs.size(),old_format=baseline.initial.format,old_refusal=old.errors,new_format=candidate.initial.format,new_law=candidate.initial.heading_memory_law,new_restore=saved.ok,ok=ok}
  print("TAPE COMPARISON ",name," identical_inputs=",equal," old_refused=",not old.ok," new_restored=",saved.ok)
  all_ok=all_ok and ok
  session.free()
 report.ok=all_ok
 var out: FileAccess=FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/audit2-20261107-heli-candidate/comparison.json",FileAccess.WRITE)
 out.store_string(JSON.stringify(report,"\t",true,true)); out.close()
 quit(0 if all_ok else 1)
