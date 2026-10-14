# HELI-16: complete rotorcraft telemetry; no airplane engine/servo column aliases.
extends RefCounted
class FlightRows extends RefCounted:
 const COLUMNS: Array[String]=["tick","t_s","loads_t_s","north_m","east_m","down_m","u_m_s","v_m_s","w_m_s","qw","qx","qy","qz","p_rad_s","q_rad_s","r_rad_s","main_omega_rad_s","a1_rad","b1_rad","vi_m_s","heading_ref_rad","yaw_integrator_rad","Fx_n","Fy_n","Fz_n","Mx_nm","My_nm","Mz_nm","cmd_roll","cmd_pitch","cmd_yaw","cmd_collective","motor_armed","drive_hold","idle_up","drive_scale","main_phase_rad","tail_phase_rad","skid0_z_n_m","skid0_z_e_m","skid1_z_n_m","skid1_z_e_m","skid2_z_n_m","skid2_z_e_m","skid3_z_n_m","skid3_z_e_m"]
 var meta: Dictionary={}
 var rows: PackedFloat64Array=PackedFloat64Array()
 var _last_tick: int=-1
 func row_count() -> int: return rows.size()/COLUMNS.size()
 func clear() -> void: rows.clear(); _last_tick=-1
 func record(tick: int,t: float,body: PackedFloat64Array,loads: PackedFloat64Array,inputs: PackedFloat64Array,continuous: PackedFloat64Array,dt_s: float,controls: PackedFloat64Array=PackedFloat64Array([0,0,0,0,0,0])) -> bool:
  if controls.size()!=6: return false
  if rows.size()%COLUMNS.size()!=0 or body.size()!=13 or loads.size()!=6 or inputs.size()!=4 or continuous.size() not in [6,14] or tick<0 or tick>9007199254740991 or not is_finite(t) or not is_finite(dt_s) or dt_s<=0.0 or t!=tick*dt_s or (_last_tick>=0 and tick!=_last_tick+1): return false
  var row: PackedFloat64Array=PackedFloat64Array([float(tick),t,maxf(0.0,(tick-1)*dt_s)])
  row.append_array(body)
  row.append_array(continuous.slice(0,6))
  row.append_array(loads)
  row.append_array(inputs)
  row.append_array(controls)
  row.append_array(continuous.slice(6) if continuous.size()==14 else PackedFloat64Array([0,0,0,0,0,0,0,0]))
  for value: float in row:
   if not is_finite(value): return false
  rows.append_array(row)
  _last_tick=tick
  return true
 func save(path: String) -> Error:
  if rows.is_empty() or rows.size()%COLUMNS.size()!=0: return ERR_INVALID_DATA
  var parent: String=ProjectSettings.globalize_path(path.get_base_dir())
  var error: Error=DirAccess.make_dir_recursive_absolute(parent)
  if error!=OK: return error
  var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
  if file==null: return FileAccess.get_open_error()
  file.store_line("# format: openrc-helicopter-trace v2")
  var keys: Array=meta.keys()
  keys.sort()
  for key: Variant in keys: file.store_line("# %s: %s"%[str(key),JSON.stringify(meta[key])])
  file.store_line(",".join(COLUMNS))
  for offset: int in range(0,rows.size(),COLUMNS.size()):
   var fields: PackedStringArray=PackedStringArray()
   for index: int in COLUMNS.size(): fields.append(JSON.stringify(rows[offset+index],"",true,true))
   file.store_line(",".join(fields))
  file.flush()
  return file.get_error()

var trace: FlightRows=FlightRows.new()
var recording: bool=false
var note: String=""
var _recording_error: String=""
var _sim: Node
var _controls: Callable
func _init(sim: Node,controls: Callable=Callable()) -> void:
 _sim=sim
 _controls=controls
 sim.stepped.connect(_record)
func start(meta: Dictionary) -> void:
 _recording_error=""
 trace.clear()
 trace.meta=meta.duplicate(true)
 trace.meta["dt_s"]=_sim.dt()
 recording=true
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
 if path.is_empty(): path="user://traces/helicopter-%s.csv"%Time.get_datetime_string_from_system(true).replace(":","-")
 var error: Error=trace.save(path)
 note="helicopter trace saved: %s (%d rows)"%[path,trace.row_count()] if error==OK else "helicopter trace save failed: %d"%error
 print(note)
 return error
func detach() -> void:
 recording=false
 if _sim.stepped.is_connected(_record): _sim.stepped.disconnect(_record)
func seconds() -> float: return maxi(0,trace.row_count()-1)*_sim.dt()
func _record(tick: int,t: float,body: PackedFloat64Array,loads: PackedFloat64Array,inputs: PackedFloat64Array,_aux: PackedFloat64Array) -> void:
 if not recording: return
 var controls: PackedFloat64Array=_controls.call() if _controls.is_valid() else PackedFloat64Array([0,0,0,0,0,0])
 if recording and not trace.record(tick,t,body,loads,inputs,_sim.continuous,_sim.dt(),controls):
  recording=false
  _recording_error="malformed telemetry at tick %d"%tick
  note="helicopter recording stopped: "+_recording_error
