extends SceneTree
const Service=preload("res://statistics/service.gd")
const Store=preload("res://statistics/store.gd")
const Reducer=preload("res://statistics/reducer.gd")
const Schema=preload("res://statistics/schema.gd")
class FinalFenceFailure:
 extends "res://statistics/store.gd"
 var fail_completion:=false
 func _write_fence(receipt: Dictionary) -> bool:
  if fail_completion and receipt.get("phase")=="purge_complete": return false
  return super._write_fence(receipt)
class SwappedFence:
 extends "res://statistics/store.gd"
 var substituted:=false
 var phase_to_substitute: String="committed"
 func _read_fence_file(path: String) -> Dictionary:
  var original: Dictionary=super._read_fence_file(path)
  if path.ends_with(FENCE_TEMP) and original.get("ok",false) and original.receipt.get("phase")==phase_to_substitute:
   var altered: Dictionary=original.receipt.duplicate(true)
   altered.targets=["stock:b"]
   var canonical: Dictionary=_schema.canonicalize(altered)
   var wrapper: Dictionary={format=FENCE_FORMAT,version=FENCE_VERSION,checksum_sha256=_sha256(var_to_bytes(canonical)),receipt=canonical}
   var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
   if file!=null:
    file.store_buffer(_frame(FENCE_MAGIC,var_to_bytes(wrapper)))
    file.flush()
    substituted=file.get_error()==OK
    file.close()
    return super._read_fence_file(path)
  return original
class RecoveryFails:
 extends "res://statistics/store.gd"
 func _ensure_both_slots_after_fence(_snapshot: Dictionary) -> bool:
  return false
class LostSurvivor:
 extends "res://statistics/store.gd"
 func _publish_deletion_to_both_slots(_candidate: Dictionary) -> bool:
  DirAccess.remove_absolute(_root_path.path_join(PREPARED_DELETE))
  return false
class AlteredPublish:
 extends "res://statistics/store.gd"
 func _write_snapshot_file(path: String, snapshot: Dictionary) -> Dictionary:
  if not _fence.is_empty() and path.ends_with("snapshot_recovery.tmp"):
   var altered: Dictionary=snapshot.duplicate(true)
   for index: int in range(altered.records.size()-1,-1,-1):
    if altered.records[index].get("aircraft_id")=="stock:b": altered.records.remove_at(index)
   return super._write_snapshot_file(path,altered)
  return super._write_snapshot_file(path,snapshot)
var checks:=0
var failures:=0
var stop_stage: String=""
var active_store: RefCounted
var substituted:=false
var roots: Array[String]=[]
func _initialize() -> void: _run.call_deferred()
func check(label: String,ok: bool,detail: String="") -> void:
 checks+=1
 if not ok:
  failures+=1
  printerr("FAIL ",label," ",detail)
func interrupt(stage: String) -> bool: return stage==stop_stage
func substitute(stage: String) -> bool:
 if stage!="after_delete_prepare_write": return false
 var path: String=active_store._root_path.path_join(Store.PREPARED_DELETE)
 var prepared: Dictionary=active_store._read_snapshot_file(path)
 if not prepared.get("ok",false): return false
 var altered: Dictionary=prepared.data.duplicate(true)
 for index: int in range(altered.records.size()-1,-1,-1):
  if altered.records[index].get("aircraft_id")=="stock:b": altered.records.remove_at(index)
 substituted=bool(Schema.validate(altered).ok) and bool(active_store._write_snapshot_file(path,altered).get("ok",false))
 return false
func flight(id: String,seq: int,aircraft: String,session_id: String="session-fixture") -> Dictionary:
 return {kind="flight",id=id,seq=seq,end_seq=seq+1,session_id=session_id,aircraft_id=aircraft,aircraft_name=aircraft,utc="2026-11-07T10:00:00",account_epoch=0,aircraft_epoch=0,airborne_seconds=20.0,outcome="completed",start_kind="takeoff",full_stops=1,touch_and_go=0,failed_landings=0,unknown_landings=0,max_tas_mps=20.0,max_groundspeed_mps=18.0,complete_observation=true,config_hash="",rules_version="flight-statistics-v1",ended_utc="2026-11-07T10:00:01",metadata={}}
func make_service(label: String, replacement: RefCounted=null) -> Node:
 var root_uri: String="user://audit5_f15_test_%s_%d_%d"%[label,OS.get_process_id(),Time.get_ticks_usec()]
 roots.append(root_uri)
 var service=Service.new(); root.add_child(service)
 check(label+" store opens",service.setup(root_uri,true),service.note)
 if replacement!=null:
  service.store.close()
  check(label+" injected store opens",replacement.open(root_uri),replacement.note)
  service.store=replacement
 var fixture: Dictionary=service.store.data.duplicate(true)
 fixture.sessions=[{id="session-fixture",opened_utc="2026-11-07T09:00:00",closed_utc="",status="open"}]
 fixture.current_session="session-fixture"
 fixture.records=[flight("a-flight",1,"stock:a"),flight("b-flight",3,"stock:b")]
 fixture.sequence=4
 fixture.clean_exit=false
 check(label+" fixture validates",Schema.validate(fixture).ok)
 check(label+" fixture commits",service.store.commit(fixture),service.store.note)
 service.data=service.store.data.duplicate(true)
 return service
func reopen(service: Node) -> Dictionary:
 var uri: String=service.store._root_uri
 service.close(); service.free()
 var store=Store.new()
 var opened: bool=store.open(uri)
 var result: Dictionary={opened=opened,available=not store.data.is_empty(),writable=store.writable,note=store.note}
 if opened and not store.data.is_empty():
  result.a=Reducer.query(store.data,"stock:a","lifetime").completed
  result.b=Reducer.query(store.data,"stock:b","lifetime").completed
  result.all=Reducer.query(store.data,"","lifetime").completed
 store.close()
 return result
func stage_case(stage: String,before_fence: bool,expected_status: String) -> void:
 var service: Node=make_service(stage)
 var old: Dictionary=service.data.duplicate(true)
 var cached: Dictionary=service.query("stock:a","lifetime")
 var cached_hud: Dictionary=service.summary("stock:a","lifetime")
 check(stage+" fixture cached",cached.completed==1 and cached_hud.completed==1)
 var notifications: Array=[0]
 service.changed.connect(func() -> void: notifications[0]+=1)
 var old_revision: int=service.revision
 stop_stage=stage
 service.store.interruption_hook=Callable(self,"interrupt")
 check(stage+" interruption reports false",not service.delete_history("stock:a"))
 check(stage+" receipt classifies durable boundary",service.last_delete_outcome.status==expected_status and service.last_delete_outcome.available)
 check(stage+" publishes change and disables management",notifications[0]==1 and service.revision==old_revision+1 and not service.can_manage())
 var a: Dictionary=service.query("stock:a","lifetime")
 var b: Dictionary=service.query("stock:b","lifetime")
 var all: Dictionary=service.query("","lifetime")
 var hud: Dictionary=service.summary("stock:a","lifetime")
 check(stage+" all queries are available",a.available and b.available and all.available and hud.available)
 check(stage+" cached and fresh results agree",a.completed==(1 if before_fence else 0) and hud.completed==(1 if before_fence else 0) and b.completed==1 and all.completed==(2 if before_fence else 1))
 var ids: Array=service.aircraft_choices().map(func(x: Dictionary) -> String: return x.id)
 check(stage+" only actual recorded aircraft appear",ids.has("stock:b") and ids.has("stock:a")==before_fence)
 check(stage+" writes refused while read-only",not service.store.commit(old) and not service.can_manage())
 if not before_fence:
  check(stage+" clean idle quit is not an unsaved-flight failure",service.finish())
  service._dirty=true
  service.store.writable=false
  check(stage+" dirty idle data still blocks quit",not service.finish())
  service._dirty=false
 var recovered: Dictionary=reopen(service)
 check(stage+" reopen recovers",recovered.opened and recovered.a==(1 if before_fence else 0) and recovered.b==1,str(recovered))
func _final_fence_failure() -> void:
 var replacement=FinalFenceFailure.new()
 var s: Node=make_service("completion_failure",replacement)
 var old: Dictionary=s.data.duplicate(true)
 s.query("stock:a","lifetime"); s.summary("stock:a","lifetime")
 replacement.fail_completion=true
 check("final receipt failure reports incomplete",not s.delete_history(""))
 check("final receipt remains committed and read-only",s.last_delete_outcome.status=="committed_pending" and s.last_delete_outcome.available and not s.store.writable and not s.can_manage())
 check("final receipt failure publishes deletion to all counters",s.query("","lifetime").completed==0 and s.summary("stock:a","lifetime").completed==0 and s.aircraft_choices().is_empty())
 check("stale full snapshot cannot be flushed or committed",not s.flush(false) and not s.store.commit(old) and s.query("","lifetime").completed==0)
 var recovered: Dictionary=reopen(s)
 check("final receipt failure recovers deletion",recovered.opened and recovered.a==0 and recovered.b==0,str(recovered))
func _lost_survivor(replacement: RefCounted,label: String) -> void:
 var s: Node=make_service(label,replacement)
 var old: Dictionary=s.data.duplicate(true)
 s.query("stock:a","lifetime"); s.summary("stock:a","lifetime")
 var notifications: Array=[0]
 s.changed.connect(func() -> void: notifications[0]+=1)
 check(label+" interruption after fence fails",not s.delete_history("stock:a"))
 check(label+" unavailable outcome is explicit",s.last_delete_outcome.status=="committed_pending" and not s.last_delete_outcome.available and not s.can_manage() and s.data.is_empty() and notifications[0]==1)
 var a: Dictionary=s.query("stock:a","lifetime")
 var all: Dictionary=s.query("","lifetime")
 var hud: Dictionary=s.summary("stock:a","lifetime")
 check(label+" cached, fresh and HUD queries cannot leak stale rows",not a.available and not all.available and not hud.available and a.history.is_empty() and all.history.is_empty() and s.aircraft_choices().is_empty())
 check(label+" cannot publish stale data",not s.flush(false) and not s.store.commit(old))
 check(label+" unknown retained session cannot claim a clean exit",not s.finish() and s._deletion_session_close_needed)
 s._dirty=true
 check(label+" dirty data still blocks quit",not s.finish())
 s._dirty=false
 var recovered: Dictionary=reopen(s)
 check(label+" reopens protected rather than resurrecting",not recovered.opened and not recovered.available and not recovered.writable,str(recovered))
func _altered_publication() -> void:
 var replacement=AlteredPublish.new()
 var s: Node=make_service("altered publication",replacement)
 check("altered published snapshot is rejected",not s.delete_history("stock:a"))
 check("original prepared survivor stays available",s.last_delete_outcome.status=="committed_pending" and s.last_delete_outcome.available and not s.can_manage() and s.query("stock:a","lifetime").completed==0 and s.query("stock:b","lifetime").completed==1)
 var recovered: Dictionary=reopen(s)
 check("unaltered survivor recovers after rejected publication",recovered.opened and recovered.a==0 and recovered.b==1,str(recovered))
func _no_open_session_unavailable_exit() -> void:
 var replacement=LostSurvivor.new()
 var s: Node=make_service("no_open_session",replacement)
 s.data.clean_exit=true
 check("clean session fixture commits",s.store.commit(s.data))
 s.data=s.store.data.duplicate(true)
 check("clean session scoped deletion becomes unavailable",not s.delete_history("stock:a") and not s.last_delete_outcome.available)
 check("known clean session permits exit despite unavailable survivors",s.finish() and not s._deletion_session_close_needed)
 s.close(); s.free()
func _clean_session_recovery() -> void:
 var s: Node=make_service("clean_session_recovery")
 var uri: String=s.store._root_uri
 var original_id: String=s.data.current_session
 stop_stage="after_deletion_fence_publish"
 s.store.interruption_hook=Callable(self,"interrupt")
 check("session fixture remains open before deletion",not s.data.clean_exit and not original_id.is_empty())
 check("scoped deletion is committed with cleanup pending",not s.delete_history("stock:a") and s.last_delete_outcome.status=="committed_pending")
 check("quit recovers deletion and durably closes session",s.finish() and s.data.clean_exit and s.store.writable and s.last_delete_outcome.status=="completed")
 s.close(); s.free()
 var resumed=Service.new(); root.add_child(resumed)
 check("clean relaunch opens statistics",resumed.setup(uri,true),resumed.note)
 check("clean relaunch has no previous this-session counts",resumed.data.current_session.is_empty() and resumed.query("","session").completed==0)
 resumed._ensure_session()
 check("clean relaunch allocates a new session",resumed.data.current_session!=original_id)
 resumed.close(); resumed.free()
func _unrecoverable_session_exit() -> void:
 var replacement=RecoveryFails.new()
 var s: Node=make_service("unrecoverable_session_exit",replacement)
 stop_stage="after_deletion_fence_publish"
 s.store.interruption_hook=Callable(self,"interrupt")
 check("unrecoverable fixture commits its fence",not s.delete_history("stock:a") and s.last_delete_outcome.status=="committed_pending")
 check("failed forward recovery refuses false clean-exit claim",not s.finish() and not s.store.writable and not s.data.clean_exit and not s.data.current_session.is_empty())
 s.close(); s.free()
func _older_fence_then_refusal() -> void:
 var s: Node=make_service("older_fence_then_refusal")
 check("first scoped deletion completes",s.delete_history("stock:a") and s.last_delete_outcome.status=="completed")
 stop_stage="after_delete_prepare_write"
 s.store.interruption_hook=Callable(self,"interrupt")
 check("second deletion refuses before its fence",not s.delete_history("stock:b") and s.last_delete_outcome.status=="refused" and not s.store.writable)
 check("old completed fence cannot relabel refused deletion on quit",not s.finish() and s.last_delete_outcome.status=="refused")
 var recovered: Dictionary=reopen(s)
 check("refused second deletion retains its aircraft",recovered.opened and recovered.a==0 and recovered.b==1,str(recovered))
func _already_read_only_exit() -> void:
 var writer: Node=make_service("already_read_only")
 var reader=Service.new(); root.add_child(reader)
 check("second process-equivalent opens read-only",not reader.setup(writer.store._root_uri,true) and reader._opened_read_only and not reader.store.writable and not reader._dirty)
 check("read-only delete refusal is explicit",not reader.delete_history("stock:a") and reader.last_delete_outcome.status=="refused")
 check("read-only service with no owned activity can quit",reader.finish())
 reader.close(); reader.free()
 var recovered: Dictionary=reopen(writer)
 check("read-only refusal preserves writer history",recovered.opened and recovered.a==1 and recovered.b==1,str(recovered))
func _precommit_substitution() -> void:
 var s: Node=make_service("precommit_substitution")
 active_store=s.store
 substituted=false
 s.store.interruption_hook=Callable(self,"substitute")
 var original: Dictionary=s.data.duplicate(true)
 check("self-checksummed survivor substitution refuses",not s.delete_history("stock:a") and substituted)
 check("substituted prepared bytes never publish a fence",s.last_delete_outcome.status=="refused" and s.store._fence.is_empty() and s.can_manage() and s.data==original)
 var recovered: Dictionary=reopen(s)
 check("substitution retains all old records on reopen",recovered.opened and recovered.a==1 and recovered.b==1,str(recovered))
func _fence_substitution() -> void:
 var replacement=SwappedFence.new()
 var s: Node=make_service("fence_substitution",replacement)
 var old: Dictionary=s.data.duplicate(true)
 check("same-revision substituted fence refuses deletion",not s.delete_history("stock:a") and replacement.substituted)
 check("substituted receipt never publishes a fence",s.last_delete_outcome.status=="refused" and s.store._fence.is_empty() and s.can_manage() and s.data==old)
 var recovered: Dictionary=reopen(s)
 check("substituted receipt preserves both histories on reopen",recovered.opened and recovered.a==1 and recovered.b==1,str(recovered))
func _completion_fence_substitution() -> void:
 var replacement=SwappedFence.new()
 replacement.phase_to_substitute="purge_complete"
 var s: Node=make_service("completion_fence_substitution",replacement)
 check("same-revision final receipt substitution is refused",not s.delete_history("stock:a") and replacement.substituted)
 check("earlier committed fence and survivors remain protected",s.last_delete_outcome.status=="committed_pending" and s.last_delete_outcome.available and not s.store.writable and s.query("stock:a","lifetime").completed==0 and s.query("stock:b","lifetime").completed==1)
 var recovered: Dictionary=reopen(s)
 check("final receipt substitution recovers intended survivors",recovered.opened and recovered.a==0 and recovered.b==1,str(recovered))
func _completed_and_fence_guard() -> void:
 var s: Node=make_service("completed")
 var stale: Dictionary=s.data.duplicate(true)
 check("full deletion completes",s.delete_history("") and s.last_delete_outcome.status=="completed" and s.last_delete_outcome.available and s.can_manage())
 check("completed deletion removes all rows",s.query("","lifetime").history_count==0 and s.summary("","lifetime").completed==0)
 var token: int=s.last_delete_outcome.revision
 check("subsequent reset succeeds without changing deletion token",s.reset_counters("account") and s.last_delete_outcome.revision==token and s.revision>token)
 check("completed fence refuses stale full history",not s.store.commit(stale) and s.store.note.contains("restore deleted"))
 var future: Dictionary=s.store.data.duplicate(true)
 future.sessions=[{id="new-session",opened_utc="2026-11-07T11:00:00",closed_utc="",status="open"}]
 future.current_session="new-session"
 future.records=[flight("new-flight",5,"stock:a","new-session")]
 future.sequence=6
 check("future post-fence records remain allowed",Schema.validate(future).ok and s.store.commit(future) and Reducer.query(s.store.data,"","lifetime").completed==1)
 var recovered: Dictionary=reopen(s)
 check("new records reopen without resurrecting old history",recovered.opened and recovered.a==1 and recovered.b==0,str(recovered))
func _writer_join() -> void:
 var s: Node=make_service("writer_join")
 s._write_revision=s.revision
 s._write_time=0.0
 s._write_tick=0
 check("background writer starts",s._writer.start(s.store,s._write_snapshot()))
 check("management unavailable while writer is unjoined",s._writer.pending() and not s.can_manage())
 check("deletion joins worker before committing",s.delete_history("stock:a") and not s._writer.pending() and s.query("stock:a","lifetime").completed==0)
 var recovered: Dictionary=reopen(s)
 check("worker cannot resurrect a deleted row",recovered.opened and recovered.a==0 and recovered.b==1,str(recovered))
func _cleanup_fixture(uri: String) -> void:
 var base: String=ProjectSettings.globalize_path("user://").simplify_path().trim_suffix("/")
 var path: String=ProjectSettings.globalize_path(uri).simplify_path().trim_suffix("/")
 if path.get_base_dir()!=base or not path.get_file().begins_with("audit5_f15_test_"):
  check("fixture cleanup stays in owned user directory",false,path)
  return
 var directory: DirAccess=DirAccess.open(path)
 if directory==null: return
 if not directory.get_directories().is_empty():
  check("fixture cleanup leaves unexpected subdirectories untouched",false,path)
  return
 for name: String in directory.get_files():
  if DirAccess.remove_absolute(path.path_join(name))!=OK: check("fixture file cleanup",false,name)
 directory=null
 if DirAccess.remove_absolute(path)!=OK: check("fixture directory cleanup",false,path)
func _run() -> void:
 for stage: String in ["after_delete_prepare_write","after_delete_prepare_readback"]: stage_case(stage,true,"refused")
 for stage: String in ["after_deletion_fence_publish","after_delete_first_snapshot_publish","after_delete_second_snapshot_publish","before_delete_purge","after_delete_purge"]: stage_case(stage,false,"committed_pending")
 stage_case("after_deletion_fence_complete",false,"completed")
 _final_fence_failure()
 _lost_survivor(LostSurvivor.new(),"missing survivor")
 _altered_publication()
 _no_open_session_unavailable_exit()
 _clean_session_recovery()
 _unrecoverable_session_exit()
 _older_fence_then_refusal()
 _already_read_only_exit()
 _precommit_substitution()
 _fence_substitution()
 _completion_fence_substitution()
 _completed_and_fence_guard()
 _writer_join()
 for uri: String in roots: _cleanup_fixture(uri)
 print("F15 deletion boundary: %d checks, %d failures"%[checks,failures])
 quit(1 if failures else 0)
