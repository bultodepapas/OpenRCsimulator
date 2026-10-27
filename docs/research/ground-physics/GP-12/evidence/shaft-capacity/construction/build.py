from pathlib import Path
import hashlib,json,difflib
ROOT=Path(__file__).resolve().parents[2]
TASK=Path(__file__).resolve().parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 out=TASK/'candidate';out.mkdir(exist_ok=True)
 paths=['contact_capacity.gd','aircraft_ground_step.gd','aircraft_ground_electric.gd']
 originals={name:(ROOT/'app/physics'/name).read_bytes() for name in paths}
 (TASK/'before').mkdir(exist_ok=True)
 for name,data in originals.items():(TASK/'before'/name).write_bytes(data)
 capacity=(out/'contact_capacity.gd').as_posix();step=(out/'aircraft_ground_step.gd').as_posix()
 text=originals['contact_capacity.gd'].decode().replace('\r\n','\n')+(TASK/'capacity_addition.gd.txt').read_text()
 (out/'contact_capacity.gd').write_text(text)
 text=originals['aircraft_ground_electric.gd'].decode().replace('\r\n','\n')+(TASK/'electric_addition.gd.txt').read_text().replace('@@CAPACITY@@',capacity)
 text=text.replace('res://physics/aircraft_ground_step.gd',step)
 (out/'aircraft_ground_electric.gd').write_text(text)
 text=originals['aircraft_ground_step.gd'].decode().replace('\r\n','\n').replace('res://physics/contact_capacity.gd',capacity)
 text=text.replace('## This domain initially refuses nonempty capture mappings; existing laws keep\n## their original capture contract. No stock selection or CPU claim is implied.', '## Stable packet capture requires the explicit interval_capture mapping and\n## the same finite independent legacy bearing row. Existing laws keep their\n## original capture contract. No stock selection or CPU claim is implied.')
 text=text.replace('## nonnegative; its row ordinal may change as physical wheel rows load/unload.', '## nonnegative; its row ordinal may change as physical wheel rows load/unload.\n## The integrated law instead requires paired interval_capture={rotor_index:int,\n## row_id:String}, pinned to an independent +e_sigma packet row and source rate.')
 a='\tvar groups: Array = sample.groups\n';assert text.count(a)==1;text=text.replace(a,a+'\tvar capture: Dictionary = sample.get("capture", {})\n',1)
 a='\t\tif not sample.get("capture", {}).is_empty():\n\t\t\treturn _failure("integrated packet capture is not yet qualified", "unsupported_capture")'
 b='\t\tvar mapped := Capacity.capture_mapping(sample, capacity, sample.rotor_state_indices.size())\n\t\tif not mapped.ok: return _failure(str(mapped.reason), "invalid_capture")\n\t\tcapture = mapped.capture'
 assert text.count(a)==1;text=text.replace(a,b,1)
 # Only the halfkick call, leaving the legacy Lie call literally unchanged.
 start=text.index('static func _half_impulse(');head,tail=text[:start],text[start:]
 assert tail.count('\t\tsample.get("capture", {}),')==1;tail=tail.replace('\t\tsample.get("capture", {}),','\t\tcapture,',1);text=head+tail
 a='\t\tvar packet: Dictionary = result.interval_capacity\n';b=a+'\t\tvar mapped := Capacity.capture_mapping(result, packet, result.rotor_state_indices.size())\n\t\tif not mapped.ok:\n\t\t\twork.fatal_capacity_failure = true\n\t\t\treturn mapped\n'
 assert text.count(a)==1;text=text.replace(a,b,1)
 a='\t\t\treturn {ok = false}\n\t\treturn result\n\n\nstatic func _predict_capacity('
 b='\t\t\treturn {ok = false}\n\t\tif not pin.has("capture_binding"):\n\t\t\tpin.capture_binding = mapped.binding.duplicate(true)\n\t\telif var_to_bytes(pin.capture_binding) != var_to_bytes(mapped.binding):\n\t\t\twork.fatal_capacity_failure = true\n\t\t\treturn {ok = false}\n\t\treturn result\n\n\nstatic func _predict_capacity('
 assert text.count(a)==1;text=text.replace(a,b,1)
 a='\t\tresult.integration_receipt.capacity_computation = {\n'
 b='\t\tif not start.get("capture", {}).is_empty():\n\t\t\tresult.integration_receipt.interval_capture = {law = Capacity.CAPTURE_LAW, rotor_index = start.interval_capture.rotor_index, row_id = start.interval_capture.row_id}\n'+a
 assert text.count(a)==1;text=text.replace(a,b,1)
 (out/'aircraft_ground_step.gd').write_text(text)
 rows=[];patch=[]
 for name in paths:
  p=out/name;rows.append({'target':'app/physics/'+name,'prehash':hashlib.sha256(originals[name]).hexdigest(),'draft':p.relative_to(ROOT).as_posix(),'sha256':sha(p)})
  patch.extend(difflib.unified_diff(originals[name].decode().replace('\r\n','\n').splitlines(keepends=True),p.read_text().splitlines(keepends=True),fromfile='app/physics/'+name,tofile='candidate/'+name))
 (TASK/'runtime-identities.json').write_text(json.dumps(rows,indent=2)+'\n');(TASK/'review.patch').write_text(''.join(patch))
 print(json.dumps(rows,indent=2))
if __name__=='__main__':main()
