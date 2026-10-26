from pathlib import Path
import json,hashlib,shutil,difflib
ROOT=Path(__file__).resolve().parents[3]
TASK=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 source=ROOT/'app/tests/test_traction_capacity.gd'
 before=source.read_bytes();assert sha(source)=='b0fbad5997d871e29561fee4add200baa2182d1f73c73c1e0718f48f90ed14fd'
 fixtures=TASK/'production/app/tests/fixtures'
 rows=fixtures/'ground_contact_capacity_legacy_rows.bin';steps=fixtures/'ground_contact_capacity_legacy_steps.bin'
 assert rows.is_file() and sha(steps)=='ffc52cf1a57e4a7a07e4d57851238acc3961dd7409ceade70dcd4a879237de18'
 text=before.decode('utf-8').replace('\r\n','\n');helpers=(TASK/'helpers.gd.txt').read_text().replace('@@ROWS_HASH@@',sha(rows))
 index=text.index('\n\nfunc _capacity_sample');text=text[:index]+'\n\n'+helpers.rstrip()+text[index:]
 start=text.index('func _legacy_rows()');end=text.index('func _legacy_steps()',start)
 text=text[:start]+(TASK/'legacy_rows.gd.txt').read_text()+text[end:]
 start=text.index('func _legacy_steps()');end=text.index('func _real_steps()',start)
 text=text[:start]+(TASK/'legacy_steps.gd.txt').read_text()+text[end:]
 production=TASK/'production/app/tests/test_traction_capacity.gd';production.write_text(text)
 (TASK/'main-before.gd').write_bytes(before)
 (TASK/'review.patch').write_text(''.join(difflib.unified_diff(before.decode('utf-8').splitlines(keepends=True),text.splitlines(keepends=True),fromfile='app/tests/test_traction_capacity.gd',tofile='app/tests/test_traction_capacity.gd')))
 validation=TASK/'validation';validation.mkdir(exist_ok=True)
 tested=text
 for fixture in [rows,steps]:tested=tested.replace('res://tests/fixtures/'+fixture.name,fixture.as_posix())
 (validation/'test_traction_capacity.gd').write_text(tested)
 # Deliberate independent regression mutations; never touch app sources.
 traction=(ROOT/'app/physics/aircraft_ground_traction.gd').read_text()
 needle='rates.append(record.normal_load_n * coefficients.longitudinal_friction if tangent_index == 0 else record.normal_load_n * coefficients.lateral_friction)'
 assert traction.count(needle)==1
 mutant=traction.replace(needle,'rates.append(1.01 * (record.normal_load_n * coefficients.longitudinal_friction if tangent_index == 0 else record.normal_load_n * coefficients.lateral_friction))')
 (validation/'mutant_traction.gd').write_text(mutant)
 (validation/'test_mutant_traction.gd').write_text(tested.replace('res://physics/aircraft_ground_traction.gd',(validation/'mutant_traction.gd').as_posix()))
 step=(ROOT/'app/physics/aircraft_ground_step.gd').read_text();needle='absolute_impulse_sum = impulse_absolute_sum';assert step.count(needle)==2
 (validation/'mutant_step.gd').write_text(step.replace(needle,needle+' + 0.125'))
 (validation/'test_mutant_step.gd').write_text(tested.replace('res://physics/aircraft_ground_step.gd',(validation/'mutant_step.gd').as_posix()))
 refusal='return {ok = false, status = status, reason = reason, law = LAW}';assert step.count(refusal)==1
 (validation/'mutant_step_refusal.gd').write_text(step.replace(refusal,'return {ok = false, status = status, reason = reason + " (oracle negative control)", law = LAW}'))
 (validation/'test_mutant_step_refusal.gd').write_text(tested.replace('res://physics/aircraft_ground_step.gd',(validation/'mutant_step_refusal.gd').as_posix()))
 manifest={'format':'openrc-traction-capacity-legacy-oracle-promotion-v1','main_test_prehash':sha(source),'payload':[{'target':str(p.relative_to(TASK/'production')).replace('\\','/'),'path':p.relative_to(ROOT).as_posix(),'sha256':sha(p),'bytes':p.stat().st_size} for p in [production,rows,steps]],'validation_transform':'Only two fixture res paths retargeted; runtime imports remain installed implementations.','fixture_attributes':'Both basenames match existing /app/tests/fixtures/ground_contact_*.bin -text; no attribute edit needed.','mutations':{'traction':'Only the legacy row force-rate result multiplied by1.01; no expected data changed.','step':'Only reported absolute_impulse_sum offset by0.125; catches two accepted gentle outcomes.','step_refusal':'Only actual failure reason text suffixed; catches two refused hard outcomes. No expected data changed.'}}
 (TASK/'promotion-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
 print(json.dumps(manifest,indent=2))
if __name__=='__main__':main()
