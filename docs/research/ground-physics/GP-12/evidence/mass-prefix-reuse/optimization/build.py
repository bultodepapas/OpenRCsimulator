from pathlib import Path
import re,json,hashlib
R=Path.cwd();B=R/'tmp/gp12-mass-prefix-draft';B.mkdir(exist_ok=True)
old=R/'tmp/gp12-hotspot-review/plain';new=B/'optimized'
for p in old.rglob('*.gd'):
 q=new/p.relative_to(old);q.parent.mkdir(parents=True,exist_ok=True)
 q.write_text(p.read_text().replace(old.as_posix()+'/',new.as_posix()+'/'))

p=new/'physics/contact_assembly_resolution.gd';s=p.read_text()
start=s.index('\tfor i in w:\n\t\tfor j in w:\n\t\t\tif mass_matrix[i*w+j]')
end=s.index('\n\tvar response_error :=',start)
prefix=s[start:end]
prefix=prefix.replace('mass_matrix','matrix')
prefix+='\n\treturn {ok=true,inverse=inverse,inverse_residual=inverse_residual,inverse_bound=inverse_bound,spd=spd}\n'
head='''
## Opaque locally prepared proof, owned by the trusted read-only model owner.
## Its private packet is never accepted from an arbitrary caller dictionary.
## There is no global cache. A complete matrix-byte/width mismatch recomputes
## the original prefix; all J/z/A/response arithmetic is always recomputed.
class FixedMassProof extends RefCounted:
\tvar _matrix_bytes:PackedByteArray
\tvar _width:int=0
\tvar _packet:Dictionary={}
\tfunc matches(matrix:PackedFloat64Array,w:int)->bool:
\t\treturn w==_width and matrix.to_byte_array()==_matrix_bytes and _packet.get("ok",false)

static func prepare_mass(matrix:PackedFloat64Array,w:int)->Dictionary:
\tif w<1 or w>70 or matrix.size()!=w*w or not _finite(matrix):return _failure("invalid prepared mass matrix")
\tvar packet:=_mass_prefix(matrix,w)
\tif not packet.ok:return packet
\tvar proof:=FixedMassProof.new()
\tproof._matrix_bytes=matrix.to_byte_array()
\tproof._width=w
\tproof._packet=packet
\treturn {ok=true,proof=proof}

static func _mass_prefix(matrix:PackedFloat64Array,w:int)->Dictionary:
'''+prefix+'\n'
s=s[:start]+'''\tvar mass_packet:Dictionary
\tif proof is FixedMassProof and proof.matches(mass_matrix,w):mass_packet=proof._packet
\telse:mass_packet=_mass_prefix(mass_matrix,w)
\tif not mass_packet.ok:return mass_packet
\tvar inverse:PackedFloat64Array=mass_packet.inverse
\tvar inverse_residual:float=mass_packet.inverse_residual
\tvar inverse_bound:float=mass_packet.inverse_bound
\tvar spd:Dictionary=mass_packet.spd
'''+s[end:]
sig='''static func bounds(a: PackedFloat64Array, v: PackedFloat64Array, mass_matrix: PackedFloat64Array,
\t\tjacobian: PackedFloat64Array, z: PackedFloat64Array, bias: PackedFloat64Array,
\t\tresponses: PackedFloat64Array) -> Dictionary:'''
assert sig in s
s=s.replace(sig,sig+'''
\treturn _bounds_mass(a,v,mass_matrix,jacobian,z,bias,responses,null)

static func _bounds_mass(a:PackedFloat64Array,v:PackedFloat64Array,mass_matrix:PackedFloat64Array,
\t\tjacobian:PackedFloat64Array,z:PackedFloat64Array,bias:PackedFloat64Array,responses:PackedFloat64Array,proof:RefCounted)->Dictionary:''',1)
s=s.replace('var verified:=bounds(a,v,mass,j,z,bias,responses)','var verified:=_bounds_mass(a,v,mass,j,z,bias,responses,memo.get("mass_proof"))')
s+='\n'+head
p.write_text(s)

p=new/'physics/aircraft_ground_impulse.gd';s=p.read_text()
assert s.count('capture: Dictionary = {}, maximum_assembly_resolution_j: float = -1.0) -> Dictionary:')==1
s=s.replace('capture: Dictionary = {}, maximum_assembly_resolution_j: float = -1.0) -> Dictionary:','capture: Dictionary = {}, maximum_assembly_resolution_j: float = -1.0, mass_proof:RefCounted=null) -> Dictionary:')
s=s.replace('var local_evidence:Dictionary={}','var local_evidence:Dictionary={}\n\tif mass_proof!=null:local_evidence.mass_proof=mass_proof',1)
p.write_text(s)

p=new/'physics/aircraft_ground_step.gd';s=p.read_text()
s=s.replace('normal_loss_policy: Callable = Callable()) -> Dictionary:', 'normal_loss_policy: Callable = Callable(),mass_proof:RefCounted=null) -> Dictionary:',1)
s=s.replace('settings,normal_loss_policy,policy_pin)', 'settings,normal_loss_policy,policy_pin,mass_proof)')
s=s.replace('policy_pin:Dictionary={}) -> Dictionary:', 'policy_pin:Dictionary={},mass_proof:RefCounted=null) -> Dictionary:')
s=s.replace('0.5 * h, evaluate, start, settings)', '0.5 * h, evaluate, start, settings,mass_proof)')
# The only remaining Impulse calls are the Lie path and common half impulse.
s=s.replace('settings.maximum_assembly_resolution_j)', 'settings.maximum_assembly_resolution_j,mass_proof)')
at=s.index('static func _half_impulse(');end=s.index(' -> Dictionary:',at)
signature=s[at:end]
assert signature.endswith('settings: Dictionary)')
s=s[:at]+signature[:-1]+',mass_proof:RefCounted=null)'+s[end:]
p.write_text(s)

p=new/'driver.gd';s=p.read_text()
s=s.replace('const ProfileTiming:=', 'const MassAR:=preload("'+(new/'physics/contact_assembly_resolution.gd').as_posix()+'")\nconst ProfileTiming:=',1)
s=s.replace('\tProfileTiming.clear()', '''\tvar at_point:=_sample_policy(raw.state,raw.time_s)
\tvar angular:PackedFloat64Array=at_point.rotor_stage.matrix
\tvar w:int=6+at_point.rotor_stage.axial.size()
\tvar mass:=PackedFloat64Array();mass.resize(w*w)
\tfor i in 3:mass[i*w+i]=at_point.mass_kg
\tfor i in w-3:
\t\tfor j in w-3:mass[(i+3)*w+j+3]=angular[i*(w-3)+j]
\tvar prep_started:=Time.get_ticks_usec()
\tvar prepared_mass:=MassAR.prepare_mass(mass,w)
\tvar prep_elapsed:=Time.get_ticks_usec()-prep_started
\tcheck("fixed mass proof prepares",prepared_mass.ok,str(prepared_mass))
\tProfileTiming.clear()''',1)
s=s.replace('_policy if use_policy else Callable())','_policy if use_policy else Callable(),prepared_mass.proof)',1)
s=s.replace('timings:={case=which,','timings:={mass_prepare_us=prep_elapsed,case=which,',1)
p.write_text(s)

# Retain the direct source transformation, all other imports are retargeted only.
import difflib
patch=[]
for name in ['physics/contact_assembly_resolution.gd','physics/aircraft_ground_impulse.gd','physics/aircraft_ground_step.gd','driver.gd']:
 before=(old/name).read_text();after=(new/name).read_text().replace(new.as_posix()+'/',old.as_posix()+'/')
 patch.extend(difflib.unified_diff(before.splitlines(keepends=True),after.splitlines(keepends=True),fromfile='before/'+name,tofile='after/'+name))
(B/'review.patch').write_text(''.join(patch))
(B/'manifest.json').write_text(json.dumps({'format':'openrc-prepared-mass-prefix-draft-v1','base_hotspot_manifest_sha256':hashlib.sha256((R/'tmp/gp12-hotspot-review/manifest.json').read_bytes()).hexdigest(),'scope':'pure fixed-matrix prefix only; default public bounds API preserved; no QP/Strategy source edits','files':[{'path':p.as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}for p in sorted(new.rglob('*.gd'))]},indent=2)+'\n')
