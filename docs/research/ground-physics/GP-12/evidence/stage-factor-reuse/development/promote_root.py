from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parents[2]
draft=Path(__file__).resolve().parent
manifest=json.loads((draft/'manifest.json').read_text())
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
targets={
 'app/physics/rotor_coupling.gd':draft/'candidate.gd',
 'app/tests/test_rotor_stage_factor.gd':draft/'test_rotor_stage_factor.gd',
 'app/tests/fixtures/rotor_stage_factor.bin':draft/'returns.bin'}
assert sha(root/'app/physics/rotor_coupling.gd')==manifest['base_sha256']
assert sha(draft/'candidate.gd')==manifest['candidate_sha256']
for path in list(targets)[1:]:assert not (root/path).exists(),path
before={path:sha(root/path) if (root/path).exists() else None for path in targets}
for path,source in targets.items():
 (root/path).parent.mkdir(parents=True,exist_ok=True)
 (root/path).write_bytes(source.read_bytes())
attributes=root/'.gitattributes';data=attributes.read_bytes()
lines=[b'/app/tests/fixtures/rotor_stage_factor.bin -text',
 b'/docs/research/ground-physics/GP-12/evidence/stage-factor-reuse/** -text whitespace=cr-at-eol',
 b'/docs/research/ground-physics/GP-12/evidence/stage-factor-reuse/**/*.log -whitespace']
for line in lines:
 if line not in data.splitlines():data=data.rstrip(b'\r\n')+b'\n'+line+b'\n'
attributes.write_bytes(data)
after={path:sha(root/path) for path in targets}
receipt={'format':'openrc-stage-factor-promotion-v1','before':before,'after':after,'production_checks':'pending'}
(draft/'root-promotion.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps(receipt))
