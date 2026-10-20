from pathlib import Path
import re, json
base=Path('tmp/perf-pass2-20261019/profile/app').resolve()
# Rename selected methods and wrap calls, preserving their signatures and values.
selected={
'sim/flight_session.gd':['._none'],
'sim/simulation.gd':['step','_stage_loads','_remember_valid_state'],
'sim/scenery_collision.gd':['contacts'],
'sim/lake_collision.gd':['first_hit','first_hit_sampled'],
'physics/hull_contact.gd':['contacts','terminal','loads','prop_disc_depth'],
'physics/dynamics.gd':['loads','loads_from_air'],
'physics/slipstream.gd':['loads','_segmented_increment','profile_moments','wake'],
'physics/swirl_loads.gd':['correction'],
'physics/propulsion.gd':['thrust_torque'],
'physics/ground_wheels.gd':['evaluate'],
'physics/lake_surface.gd':['is_valid_definition'],
'physics/mass_inventory.gd':['evaluate_reference','evaluate','is_physical_tensor'],
'physics/fixed_datum_body.gd':['derivative'],
'sim/liquid_fuel_flight.gd':['evaluate','properties','valid','step'],
'physics/aero.gd':['loads','_global_loads','_local_loads','local_flow_weight','_wing_flow'],
'physics/ground_contact.gd':['evaluate','anchor_step','loads','collapsed','compressions'],
}
selected['sim/flight_session.gd']=['_wheel_evaluate','_ground_evaluation','_coupled_response','_turbine_evaluate','_physics_process','_resolve_collision_step','_scenery_hit','_on_sim_stepped','_pre_step','_loads','_wash_loads','_wheel_stage','_coupled_stage','_continuous_stage']
selected['sim/flight_session.gd'] += ['wheel_count', 'wheel_index', 'anchor_count', 'gear_is_retractable', 'glow_is_active', 'shaft_is_coupled', 'battery_is_dynamic', 'battery_is_pack', '_rotor_index', 'current_landing_gear', 'downwash_index', 'turbine_is_continuous', '_liquid_index']
prof='''extends RefCounted
static var enabled := false
static var rows: Dictionary = {}
static var stack: Array = []
static func begin() -> void:
\tstack.append([Time.get_ticks_usec(), 0])
static func end(label: String) -> void:
\tvar frame: Array = stack.pop_back()
\tvar elapsed: int = Time.get_ticks_usec() - frame[0]
\tif not stack.is_empty(): stack[-1][1] += elapsed
\tif not enabled: return
\tif not rows.has(label): rows[label] = {calls = 0, inclusive_usec = 0, self_usec = 0}
\trows[label].calls += 1
\trows[label].inclusive_usec += elapsed
\trows[label].self_usec += elapsed - frame[1]
'''
(base/'perf_clock.gd').write_text(prof)
manifest={}
for rel,names in selected.items():
 p=base/rel; source=p.read_text(); wrappers=[]
 pattern=re.compile(r'^(static )?func (\w+)\((.*?)\)\s*->\s*([^:\n]+):',re.M|re.S)
 def change(m):
  static,name,args,ret=m.groups()
  if name not in names: return m.group(0)
  params=[]; depth=0; current=''
  for c in args+',':
   if c in '([{': depth+=1
   if c in ')]}': depth-=1
   if c==',' and depth==0:
    if current.strip(): params.append(current.strip().split(':')[0].split('=')[0].strip())
    current=''
   else: current+=c
  signature=m.group(0); call='_perf_original_'+name+'('+', '.join(params)+')'
  body='\n\tPerfClock.begin()\n'
  body+=('\t'+call+'\n') if ret.strip()=='void' else ('\tvar perf_result: '+ret.strip()+' = '+call+'\n')
  body+='\tPerfClock.end("'+rel+':'+name+'")\n'
  if ret.strip()!='void': body+='\treturn perf_result\n'
  wrappers.append(signature+body)
  return signature.replace('func '+name+'(', 'func _perf_original_'+name+'(',1)
 source=pattern.sub(change,source)
 if wrappers:
  source+='\nconst PerfClock = preload("res://perf_clock.gd")\n\n'+'\n'.join(wrappers)
  p.write_text(source)
 manifest[rel]=len(wrappers)
probe=Path('research/performance/session_probe.gd').read_text()
probe=probe.replace('var started: int = Time.get_ticks_usec()\n\t\t\tfor index in _samples:', 'PerfClock.enabled = true\n\t\t\tvar started: int = Time.get_ticks_usec()\n\t\t\tfor index in _samples:')
probe=probe.replace('var report := {','var report := {\n\t\tprofile = PerfClock.rows,')
probe+='\nconst PerfClock = preload("res://perf_clock.gd")\n'
(base/'profile_probe.gd').write_text(probe)
print(manifest)
