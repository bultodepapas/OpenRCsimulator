"""Diagnostic adaptation of gp12-local-reuse/profile_tick.py; no production edits."""
from pathlib import Path
import re, json, hashlib

ROOT=Path.cwd()
B=ROOT/'tmp/gp12-hotspot-review'
B.mkdir(exist_ok=True)
PREFIX=ROOT.as_posix()+'/'
payload=json.loads((ROOT/'tmp/gp12-unloaded-policy/manifest.json').read_text())
overrides={x['target'][4:]:ROOT/x['path'] for x in payload['payload'] if x['target'].endswith('.gd')}
owner=(ROOT/'tmp/gp12-unloaded-policy/production/app/tests/test_aircraft_ground_unloaded.gd').read_text()
owner=owner.replace('res://tests/fixtures/','C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-unloaded-policy/production/app/tests/fixtures/')
sources={'owner.gd':owner}
pending=['tests/test_aircraft_ground_stage.gd']
pending += re.findall(r'res://([^"\n]+\.gd)',owner)
while pending:
    name=pending.pop()
    if name in sources:continue
    p=overrides.get(name,ROOT/'app'/name)
    text=p.read_text()
    sources[name]=text
    pending += re.findall(r'res://([^"\n]+\.gd)',text)

selected={
'owner.gd':['_snapshot','_derivative','_certificate','_sample_policy','_policy','_config','_gate'],
'physics/aircraft_ground_step.gd':['advance','_attempt_two_sided','_sample','_loss_policy','_half_impulse'],
'physics/aircraft_ground_unloaded.gd':['prepare','qualify','_reference','_identity'],
'physics/aircraft_ground_accuracy.gd':['diagnose','_receipt'],
'physics/aircraft_ground_stage.gd':['evaluate','_prepared_shape'],
'physics/aircraft_ground_dynamics.gd':['evaluate','_static_provider','_normal_contact'],
'physics/aircraft_ground_traction.gd':['evaluate','_prepared'],
'physics/aircraft_ground_impulse.gd':['apply','_stage','_mass_residual'],
'physics/ground_traction.gd':['_solve_for_assembly_with_work','_solve','_range_proposal','_work_candidate','_certificate','_validate_psd'],
'physics/contact_assembly_resolution.gd':['bounds','_solve_core','_memo_bounds','_slip_verified','_work_verified','_spd_margin'],
'physics/rotor_coupling.gd':['evaluate_system','_validate_stage','_rotors_valid','_evaluate_carrier','_assemble','_ledger'],
'physics/wheel_geometry.gd':['heightfield','plane','_evaluate','_interval_bounds'],
'physics/ground_support.gd':['sample','prepare_legacy'],
'physics/normal_compliance.gd':['prepare','evaluate','bounds','bounds_interval'],
'physics/generalized_coordinates.gd':['cholesky_factor','solve_cholesky','factor_body_local','solve_body_local','invert'],
'physics/wheel_coupling.gd':['transport_assembly'],
}

METRICS='''extends RefCounted
static var stack:Array=[]
static var totals:Dictionary={}
static var counts:Dictionary={}
static var exclusive:Dictionary={}
static var serial_bytes:Dictionary={}
static func enter(label:String)->void:
\tstack.append({label=label,start=Time.get_ticks_usec(),child=0})
static func leave()->void:
\tvar row:Dictionary=stack.pop_back()
\tvar elapsed:int=Time.get_ticks_usec()-row.start
\ttotals[row.label]=int(totals.get(row.label,0))+elapsed
\texclusive[row.label]=int(exclusive.get(row.label,0))+elapsed-int(row.child)
\tcounts[row.label]=int(counts.get(row.label,0))+1
\tif not stack.is_empty():stack[-1].child+=elapsed
static func serialize(value:Variant)->PackedByteArray:
\tvar caller:String=stack[-1].label if not stack.is_empty() else "outside"
\tvar label:="serialize@"+caller
\tenter(label)
\tvar bytes:=var_to_bytes(value)
\tleave()
\tserial_bytes[label]=int(serial_bytes.get(label,0))+bytes.size()
\treturn bytes
static func clear()->void:
\tstack.clear();totals.clear();exclusive.clear();counts.clear();serial_bytes.clear()
'''

def split_args(text):
    out=[];part='';depth=0;quote=None
    for ch in text:
        if quote:
            if ch==quote:quote=None
        elif ch in ['"',"'"]:quote=ch
        elif ch in '([{':depth+=1
        elif ch in ')]}':depth-=1
        if ch==',' and depth==0:out.append(part);part=''
        else:part+=ch
    if part.strip():out.append(part)
    return [x.split(':')[0].split('=')[0].strip() for x in out]

def wrap(text,names,tag):
    for name in names:
        pat=r'^(static )?func '+re.escape(name)+r'\((.*?)\)(\s*->\s*[^:\n]+):\n'
        m=re.search(pat,text,re.S|re.M)
        if not m:
            print('skip missing',tag,name)
            continue
        static=m[1] or '';args=m[2];ret=m[3]
        assert ret.strip()!='-> void',(tag,name)
        text=text[:m.start()]+text[m.start():].replace('func '+name+'(','func _profiled_'+name+'(',1)
        text+='\n'+static+'func '+name+'('+args+')'+ret+':\n'
        text+='\tTiming.enter("'+tag+'.'+name+'")\n'
        text+='\tvar measured:=_profiled_'+name+'('+','.join(split_args(args))+')\n'
        text+='\tTiming.leave()\n\treturn measured\n'
    return text

for mode in ['plain','timed']:
    dest=B/mode
    dest.mkdir(exist_ok=True)
    (dest/'metrics.gd').write_text(METRICS)
    for name,text in sources.items():
        text=re.sub(r'^class_name .*\n','',text,flags=re.M)
        text=re.sub(r'res://([^"\n]+\.gd)',lambda m:(dest/m[1]).as_posix() if m[1] in sources else m[0],text)
        if mode=='timed':
            lines=text.splitlines(keepends=True)
            i=next(i for i,l in enumerate(lines) if l.startswith('extends '))
            if name!='owner.gd':
                lines.insert(i+1,'const Timing:=preload("'+(dest/'metrics.gd').as_posix()+'")\n')
            text=''.join(lines).replace('var_to_bytes(','Timing.serialize(')
            text=wrap(text,selected.get(name,[]),Path(name).stem)
        p=dest/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
    driver='''extends "OWNER"
const ProfileTiming:=preload("METRICS")
func _initialize()->void:
\t_fixture();_prepare_composition();_prepare_quality()
\tvar which:="rest6"
\tvar use_policy:=true
\tfor argument:String in OS.get_cmdline_user_args():
\t\tif argument.begins_with("--case="):which=argument.trim_prefix("--case=")
\t\tif argument=="--no-policy":use_policy=false
\tvar raw:Dictionary
\tif which.begins_with("rest"):
\t\tvar suffix:="6s" if which=="rest6" else "10s"
\t\tvar f:=FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-local-reuse/checkpoint-"+suffix+".bin",FileAccess.READ)
\t\tvar cp:Dictionary=bytes_to_var(f.get_buffer(f.get_length()));f.close()
\t\tvar values:PackedFloat64Array=cp.state.duplicate();values.append_array(cp.continuous)
\t\traw={state=values,time_s=cp.tick*cp.dt,dt=cp.dt,options=_options()}
\t\tlift_ratio=0.0;brake_start=100.0;_bind()
\telse:
\t\traw=_read("ground_unloaded_gentle.bin" if which=="gentle" else "ground_unloaded_hard.bin")
\tProfileTiming.clear()
\tvar started:=Time.get_ticks_usec()
\tvar result:=Candidate.advance(raw.state,raw.time_s,raw.dt,_derivative,PackedFloat64Array(),_sample_policy,_certificate,raw.options,_gate,_policy if use_policy else Callable())
\tvar elapsed:=Time.get_ticks_usec()-started
\tvar timings:={case=which,policy=use_policy,elapsed_us=elapsed,inclusive_us=ProfileTiming.totals.duplicate(),exclusive_us=ProfileTiming.exclusive.duplicate(),calls=ProfileTiming.counts.duplicate(),serialized_bytes=ProfileTiming.serial_bytes.duplicate(),ok=result.ok,status=result.get("status"),accepted_substeps=result.get("integration_receipt",{}).get("accepted_substeps"),reason=result.get("reason"),note="Diagnostic wrapper timings include overhead; no native or performance qualification"}
\tvar suffix:=which+("-policy" if use_policy else "-default")
\tvar f:=FileAccess.open("DEST/"+suffix+".result.bin",FileAccess.WRITE);f.store_buffer(var_to_bytes(result));f.close()
\tf=FileAccess.open("DEST/"+suffix+".timings.json",FileAccess.WRITE);f.store_string(JSON.stringify(timings,"\\t",true,true));f.close()
\tprint("PROFILE_RESULT ",JSON.stringify(timings,"",true,true))
\tprint("Hotspot snapshot completed: %d fixture checks, %d failed"%[checks,failed])
\tquit(1 if failed else 0)
'''.replace('OWNER',(dest/'owner.gd').as_posix()).replace('METRICS',(dest/'metrics.gd').as_posix()).replace('DEST',dest.as_posix())
    (dest/'driver.gd').write_text(driver)

manifest={'format':'openrc-ground-hotspot-source-v1','method':'Timing-wrapper adaptation of tmp/gp12-local-reuse/profile_tick.py; inclusive/exclusive and serialization bytes; exact complete output comparison required','heat_payload_manifest_sha256':hashlib.sha256((ROOT/'tmp/gp12-unloaded-policy/manifest.json').read_bytes()).hexdigest(),'sources':[],'inputs':[],'generated':[]}
for name,text in sources.items():
    path=overrides.get(name,ROOT/'app'/name) if name!='owner.gd' else ROOT/'tmp/gp12-unloaded-policy/production/app/tests/test_aircraft_ground_unloaded.gd'
    manifest['sources'].append({'key':name,'origin':path.as_posix(),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
for path in [ROOT/'tmp/gp12-local-reuse/checkpoint-6s.bin',ROOT/'tmp/gp12-local-reuse/checkpoint-10s.bin']+[ROOT/x['path'] for x in payload['payload'] if x['target'].endswith('.bin')]:
    manifest['inputs'].append({'path':path.as_posix(),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
for path in sorted(B.rglob('*.gd')):
    manifest['generated'].append({'path':path.as_posix(),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
(B/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('Snapshot scripts:',len(sources))
