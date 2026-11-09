# HELI-16: complete rotorcraft telemetry; no airplane engine/servo column aliases.
extends RefCounted
const ManualTraceSave=preload("res://sim/manual_trace_save.gd")
const ChunkStore=preload("res://sim/trace_chunk_store.gd")

class FlightRows extends RefCounted:
 const COLUMNS: Array[String]=["tick","t_s","loads_t_s","north_m","east_m","down_m","u_m_s","v_m_s","w_m_s","qw","qx","qy","qz","p_rad_s","q_rad_s","r_rad_s","main_omega_rad_s","a1_rad","b1_rad","vi_m_s","heading_ref_rad","yaw_integrator_rad","Fx_n","Fy_n","Fz_n","Mx_nm","My_nm","Mz_nm","cmd_roll","cmd_pitch","cmd_yaw","cmd_collective","motor_armed","drive_hold","idle_up","drive_scale","main_phase_rad","tail_phase_rad","skid0_z_n_m","skid0_z_e_m","skid1_z_n_m","skid1_z_e_m","skid2_z_n_m","skid2_z_e_m","skid3_z_n_m","skid3_z_e_m"]
 const MAX_CHUNK_BYTES: int=1024*1024
 var meta: Dictionary={}
 var _tail: PackedFloat64Array=PackedFloat64Array()
 # Compatibility access materializes all rows in chunk mode and is unbounded.
 # Normal recording and save use row_count()/row() without this allocation.
 var rows: PackedFloat64Array:
  get:
   if _store==null: return _tail
   var all: PackedFloat64Array=PackedFloat64Array()
   for index: int in _store.row_count():
    var item: PackedFloat64Array=_store.row(index)
    if item.size()!=COLUMNS.size(): return PackedFloat64Array()
    all.append_array(item)
   all.append_array(_tail)
   return all
  set(value):
   if _chunk_enabled:
    push_error("Cannot replace rows during chunk storage")
    return
   _tail=value
 var _last_tick: int=-1
 var _chunk_enabled: bool=false
 var _chunk_rows: int=0
 var _chunk_directory: String=""
 var _store: RefCounted
 var _storage_error: Error=OK
 var _capture_stop_reason: String=""
 var _last_cleanup_error: Error=OK
 var _last_cleanup_path: String=""

 func enable_chunk_storage(directory: String="user://trace_spools",row_limit: int=4096) -> Error:
  if row_limit<=0 or not _tail.is_empty() or _store!=null or _chunk_enabled: return ERR_INVALID_PARAMETER
  _chunk_rows=mini(mini(row_limit,4096),MAX_CHUNK_BYTES/(COLUMNS.size()*8))
  if _chunk_rows<=0: return ERR_INVALID_PARAMETER
  _chunk_directory=directory
  _chunk_enabled=true
  return OK

 func row_count() -> int:
  return (_store.row_count() if _store!=null else 0)+_tail.size()/COLUMNS.size()

 func row(index: int) -> PackedFloat64Array:
  if index<0 or index>=row_count(): return PackedFloat64Array()
  var spooled: int=_store.row_count() if _store!=null else 0
  if index<spooled: return _store.row(index)
  var offset: int=(index-spooled)*COLUMNS.size()
  return _tail.slice(offset,offset+COLUMNS.size())

 func storage_error() -> Error: return _storage_error
 func read_error() -> Error: return _store.read_error() if _store!=null else OK
 func recovery_directory() -> String: return _store.directory_path() if _store!=null else ""
 func last_tick() -> int: return _last_tick
 func capture_incomplete() -> bool: return not _capture_stop_reason.is_empty()
 func last_cleanup_error() -> Error: return _last_cleanup_error
 func last_cleanup_path() -> String: return _last_cleanup_path

 func clear() -> Error:
  if _store!=null:
   var error: Error=_store.discard()
   if error!=OK: return error
   var cleanup_error: Error=_store.cleanup_error()
   if cleanup_error!=OK:
    _last_cleanup_error=cleanup_error
    _last_cleanup_path=_store.cleanup_path()
  _store=null
  _tail.clear()
  _last_tick=-1
  _chunk_enabled=false
  _chunk_rows=0
  _chunk_directory=""
  _storage_error=OK
  _capture_stop_reason=""
  return OK

 func record(tick: int,t: float,body: PackedFloat64Array,loads: PackedFloat64Array,inputs: PackedFloat64Array,continuous: PackedFloat64Array,dt_s: float,controls: PackedFloat64Array=PackedFloat64Array([0,0,0,0,0,0])) -> bool:
  if capture_incomplete(): return false
  if controls.size()!=6: return false
  if _tail.size()%COLUMNS.size()!=0 or body.size()!=13 or loads.size()!=6 or inputs.size()!=4 or continuous.size() not in [6,14] or tick<0 or tick>9007199254740991 or not is_finite(t) or not is_finite(dt_s) or dt_s<=0.0 or t!=tick*dt_s or (_last_tick>=0 and tick!=_last_tick+1): return false
  var next: PackedFloat64Array=PackedFloat64Array([float(tick),t,maxf(0.0,(tick-1)*dt_s)])
  next.append_array(body)
  next.append_array(continuous.slice(0,6))
  next.append_array(loads)
  next.append_array(inputs)
  next.append_array(controls)
  next.append_array(continuous.slice(6) if continuous.size()==14 else PackedFloat64Array([0,0,0,0,0,0,0,0]))
  for value: float in next:
   if not is_finite(value): return false
  if _store!=null:
   var pending_error: Error=_store.write_error()
   if pending_error!=OK:
    _storage_error=pending_error
    _capture_stop_reason="chunk storage error %d before tick %d"%[pending_error,tick]
    return false
  if _chunk_enabled and _tail.size()==_chunk_rows*COLUMNS.size():
   if _store==null: _store=ChunkStore.new(COLUMNS,_chunk_rows,_chunk_directory)
   var error: Error=_store.append_chunk(_tail,_csv_header())
   if error!=OK:
    _storage_error=error
    _capture_stop_reason="chunk storage error %d before tick %d"%[error,tick]
    return false
   _tail=PackedFloat64Array()
  _tail.append_array(next)
  _last_tick=tick
  return true

 func _csv_header() -> String:
  var lines: PackedStringArray=PackedStringArray(["# format: openrc-helicopter-trace v2"])
  var written_meta: Dictionary=meta.duplicate(true)
  if capture_incomplete():
   written_meta["trace_capture_complete"]=false
   written_meta["trace_capture_stop_reason"]=_capture_stop_reason
   written_meta["trace_capture_last_tick"]=_last_tick
  var keys: Array=written_meta.keys()
  keys.sort()
  # Keep the existing sorted, full-precision JSON metadata representation.
  for key: Variant in keys: lines.append("# %s: %s"%[str(key),JSON.stringify(written_meta[key],"",true,true)])
  lines.append(",".join(COLUMNS))
  return "\n".join(lines)+"\n"

 func save(path: String) -> Error:
  if row_count()==0 or _tail.size()%COLUMNS.size()!=0: return ERR_INVALID_DATA
  if _store!=null:
   # Join the writer before reading. Failed queued chunks remain readable; a
   # separate writable destination can still preserve the entire accepted prefix.
   _store.drain()
   if _is_owned_path(path): return ERR_INVALID_PARAMETER
  var parent: String=ProjectSettings.globalize_path(path.get_base_dir())
  var error: Error=DirAccess.make_dir_recursive_absolute(parent)
  if error!=OK and not (error==ERR_ALREADY_EXISTS and DirAccess.dir_exists_absolute(parent)): return error
  var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
  if file==null: return FileAccess.get_open_error()
  var written: bool=file.store_string(_csv_header())
  var read_error: Error=OK
  const BATCH_CHARACTERS: int=65536
  var batch: PackedStringArray=PackedStringArray()
  var characters: int=0
  for index: int in row_count():
   if not written: break
   var values: PackedFloat64Array=row(index)
   if values.size()!=COLUMNS.size():
    read_error=_store.read_error() if _store!=null else ERR_FILE_CORRUPT
    if read_error==OK: read_error=ERR_FILE_CORRUPT
    break
   var fields: PackedStringArray=PackedStringArray()
   for value: float in values: fields.append(JSON.stringify(value,"",true,true))
   var line: String=",".join(fields)
   if characters>0 and characters+line.length()+1>BATCH_CHARACTERS:
    written=file.store_string("\n".join(batch)+"\n")
    batch.clear()
    characters=0
    if not written: break
   batch.append(line)
   characters+=line.length()+1
  if read_error==OK and written and not batch.is_empty():
   written=file.store_string("\n".join(batch)+"\n")
  file.flush()
  var write_error: Error=file.get_error()
  file.close()
  if read_error==OK and written and write_error==OK: return OK
  DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
  if read_error!=OK: return read_error
  return write_error if write_error!=OK else ERR_FILE_CANT_WRITE

 func _is_owned_path(path: String) -> bool:
  var directory: String=recovery_directory()
  if directory.is_empty(): return false
  var owned: String=ProjectSettings.globalize_path(directory).replace("\\","/").simplify_path().trim_suffix("/")
  var destination: String=ProjectSettings.globalize_path(path).replace("\\","/").simplify_path()
  if OS.has_feature("windows"):
   owned=owned.to_lower()
   destination=destination.to_lower()
  return destination==owned or destination.begins_with(owned+"/")

 # Called by the owner only after the destination is fully published.
 func mark_saved() -> void:
  if _store!=null: _store.mark_saved()

var trace: FlightRows=FlightRows.new()
var recording: bool=false
## Monotonic identity for each new manual recording, independent of saved trace data.
var recording_generation: int=0
var note: String=""
var _unsaved: bool=false
var _recording_error: String=""
var _sim: Node
var _controls: Callable
func _init(sim: Node,controls: Callable=Callable()) -> void:
 _sim=sim
 _controls=controls
 sim.stepped.connect(_record)
func start(meta: Dictionary,use_chunks: bool=false) -> void:
 if recording:
  note="recording already in progress"
  return
 if _unsaved and stop()!=OK:
  note+=" (T retries; exit to discard)"
  return
 var error: Error=trace.clear()
 if error!=OK:
  note="helicopter trace cleanup failed: %d"%error
  return
 trace.meta=meta.duplicate(true)
 trace.meta["dt_s"]=_sim.dt()
 if use_chunks:
  error=trace.enable_chunk_storage()
  if error!=OK:
   note="helicopter trace storage setup failed: %d"%error
   return
 recording_generation+=1
 _recording_error=""
 recording=true
 _unsaved=true
 if trace.last_cleanup_error()!=OK:
  note="helicopter trace cleanup pending: %s (error %d)"%[trace.last_cleanup_path(),trace.last_cleanup_error()]
  print(note)
 _record(_sim.tick,_sim.time(),_sim.state,_sim.last_loads,_sim.inputs,_sim.aux)
func stop(path: String="") -> Error:
 recording=false
 if not _recording_error.is_empty():
  note="helicopter trace rejected: %s"%_recording_error
  print(note)
  return ERR_INVALID_DATA
 if trace.row_count()==0:
  note="helicopter trace rejected: no valid samples"
  print(note)
  return ERR_INVALID_DATA
 var error: Error
 if path.is_empty():
  var result: Dictionary=_save_automatic()
  error=result.error
  path=result.path
 else:
  error=trace.save(path)
 if error==OK:
  trace.mark_saved()
  _unsaved=false
  if trace.capture_incomplete():
   note="INCOMPLETE helicopter trace prefix saved: %s (%d rows; last tick %d)"%[path,trace.row_count(),trace.last_tick()]
  else:
   note="helicopter trace saved: %s (%d rows)"%[path,trace.row_count()]
 else:
  note="helicopter trace save failed: %d"%error
  if trace.capture_incomplete(): note+=" (INCOMPLETE prefix retained)"
 print(note)
 return error
func _save_automatic() -> Dictionary: return ManualTraceSave.save(trace,"helicopter")
func has_unsaved_recording() -> bool: return _unsaved
func discard_unsaved(expected_generation: int) -> bool:
 if recording or not _unsaved or expected_generation!=recording_generation: return false
 var error: Error=trace.clear()
 if error!=OK:
  note="helicopter trace discard failed: %d"%error
  return false
 _unsaved=false
 _recording_error=""
 note="helicopter trace discarded"
 if trace.last_cleanup_error()!=OK:
  note+="; cleanup pending: %s (error %d)"%[trace.last_cleanup_path(),trace.last_cleanup_error()]
  print(note)
 return true
func detach() -> void:
 recording=false
 if _sim.stepped.is_connected(_record): _sim.stepped.disconnect(_record)
func seconds() -> float: return maxi(0,trace.row_count()-1)*_sim.dt()
func _record(tick: int,t: float,body: PackedFloat64Array,loads: PackedFloat64Array,inputs: PackedFloat64Array,_aux: PackedFloat64Array) -> void:
 if not recording: return
 var controls: PackedFloat64Array=_controls.call() if _controls.is_valid() else PackedFloat64Array([0,0,0,0,0,0])
 if recording and not trace.record(tick,t,body,loads,inputs,_sim.continuous,_sim.dt(),controls):
  recording=false
  if trace.storage_error()!=OK:
   note="helicopter recording INCOMPLETE: storage error %d; last tick %d"%[trace.storage_error(),trace.last_tick()]
  else:
   _recording_error="malformed telemetry at tick %d"%tick
   note="helicopter recording stopped: "+_recording_error
