from pathlib import Path
task=Path(__file__).resolve().parent
s=(task/'production/app/tests/test_shaft_capacity.gd').read_text()
for name in ('contact_capacity.gd','aircraft_ground_step.gd','aircraft_ground_electric.gd'):
    s=s.replace('res://physics/'+name,(task/'candidate'/name).as_posix())
s=s.replace('res://tests/fixtures/ground_contact_shaft_legacy.bin',(task/'ground_contact_shaft_legacy.bin').as_posix())
(task/'candidate/test_main.gd').write_text(s)
