from pathlib import Path
root=Path(__file__).resolve().parents[2]
task=Path(__file__).resolve().parent
p=task/'test_shaft_capacity.gd'
s=p.read_text()
old=(root/'app/tests/test_aircraft_ground_electric.gd').read_text()
body=old[old.index('func _runtime_sim('):old.index('func _airborne_runtime(')]
body=body.replace('"synthetic-electric-airborne-capture-checked-SI-v1"','"synthetic-electric-airborne-capture-checked-SI-v1:" + NewCapacity.CAPTURE_LAW + ":" + NewStep.INTEGRATED_CAPACITY_LAW')
body=body.replace('return Step.advance(state, at, dt, f, first, sample, _airborne_certificate, {}, gate)','return NewStep.advance(state, at, dt, f, first, sample, _shaft_certificate, {operator_law = NewStep.INTEGRATED_CAPACITY_LAW}, gate)')
a=s.index('func _runtime_sim(');b=s.index('func _actual_runtime(',a)
s=s[:a]+body+s[b:]
old='\tvar file := FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-shaft-capacity/results.bin", FileAccess.WRITE)\n\tfile.store_var(saved_results)'
new='\tfor arg: String in OS.get_cmdline_user_args():\n\t\tif arg.begins_with("--shaft-evidence="):\n\t\t\tvar file := FileAccess.open(arg.trim_prefix("--shaft-evidence="), FileAccess.WRITE)\n\t\t\tfile.store_var(saved_results)'
if old in s:s=s.replace(old,new)
p.write_text(s)
