from pathlib import Path
import difflib
import hashlib
import json

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
OUT = HERE / 'payload'
BASE = json.loads((HERE/'prehash.json').read_text())

def write(path, text):
    target = OUT/path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text if text.endswith('\n') else text + '\n', encoding='utf-8', newline='\n')

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

for path, before in BASE.items():
    assert digest(ROOT/path) == before, f'base changed: {path}'
    source = (HERE/Path(path).name).read_text(encoding='utf-8')
    source = source.replace('C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-fixed-brake-session/flight_session.gd', 'res://sim/flight_session.gd')
    write(path, source)

test = (HERE/'test_fixed_brake.gd').read_text(encoding='utf-8')
test = test.replace('C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-fixed-brake-session/flight_session.gd', 'res://sim/flight_session.gd')
test = test.replace('C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-fixed-brake-session/trace.gd', 'res://sim/trace.gd')
test = test.replace('C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-fixed-brake-session/main_input_fixture.gd', 'res://tests/fixtures/fixed_brake_main_input.gd')
test = test.replace('const OldFlight := preload("res://sim/flight_session.gd")\n', '')
test = test.replace('const OldTrace := preload("res://sim/trace.gd")\n', '')
start = test.index('\t\tvar old_refusal := OldTrace.new()')
end = test.index('\tcheck("Trace brake column', start)
test = test[:start] + '\t\tcheck("historically unsupported fixed turbine-wheel Trace stays refused", trace.row_count() == 0)\n' + test[end:]
test = test.replace('var baseline_outputs: Dictionary = {}\n', '')
a = test.index('\tvar baseline := FileAccess.open(')
b = test.index('\tprint("Fixed brake candidate:', a)
test = test[:a] + test[b:]
test = test.replace('func run_all() -> void:\n', 'func run_all() -> void:\n\tDirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../tmp/gp12-fixed-brake-session"))\n')
a = test.index('func legacy() -> void:')
test = test[:a] + '''func legacy() -> void:
	var frozen: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/fixed_brake_legacy_outputs.json"))
	for id: String in frozen.outputs:
		var expected: Dictionary = frozen.outputs[id]
		var f := Flight.new()
		f.setup(Catalog.entry(id).data)
		check("frozen legacy checkpoint/metadata exact " + id,
			Engine.get_version_info().string == frozen.engine and Engine.physics_ticks_per_second == frozen.physics_hz
			and digest(f.checkpoint()) == expected.checkpoint and digest(legacy_metadata(f)) == expected.metadata)
		var trace := Trace.new()
		trace.meta = legacy_metadata(f)
		record(trace, f)
		check("frozen legacy CSV exact " + id, trace.row_count() == 1 and trace.to_csv().sha256_text() == expected.trace_csv)
		step(f, 3)
		check("frozen legacy continuation exact " + id, digest(f.sim.checkpoint()) == expected.after_three_ticks)
		f.free()
'''
write('app/tests/test_fixed_gear_brake_input.gd', test)
write('app/tests/fixtures/fixed_brake_main_input.gd', (HERE/'main_input_fixture.gd').read_text().replace('C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-fixed-brake-session/main.gd','res://main.gd'))
write('app/tests/fixtures/fixed_brake_legacy_outputs.json', (HERE/'legacy-outputs.json').read_text())
write('app/tests/fixed_brake_trace_contract.py', (HERE/'trace_role_contract.py').read_text())
py_test = (HERE/'test_trace_role_contract.py').read_text().replace('from trace_role_contract import inspect', 'from fixed_brake_trace_contract import inspect')
py_test = py_test.replace("ROOT = Path(__file__).resolve().parent", "ROOT = Path(__file__).resolve().parent / 'fixtures'")
py_test = py_test.replace('trace-false.csv', 'fixed_brake_trace_stik.csv')
py_test = py_test.replace("[('false', 5), ('true', 6)]", "[('stik', 5), ('flaps', 6)]")
py_test = py_test.replace("f'trace-{suffix}.csv'", "f'fixed_brake_trace_{suffix}.csv'")
write('app/tests/test_fixed_brake_trace_contract.py', py_test)
write('app/tests/fixtures/fixed_brake_trace_stik.csv', (HERE/'trace-false.csv').read_text())
write('app/tests/fixtures/fixed_brake_trace_flaps.csv', (HERE/'trace-true.csv').read_text())

# Execute the production test projection against the exact detached runtime,
# without introducing tmp dependencies into the proposed installed test.
projection = test.replace('res://sim/flight_session.gd', str(HERE/'flight_session.gd').replace('\\','/'))
projection = projection.replace('res://sim/trace.gd', str(HERE/'trace.gd').replace('\\','/'))
projection = projection.replace('res://tests/fixtures/fixed_brake_main_input.gd', str(HERE/'main_input_fixture.gd').replace('\\','/'))
projection = projection.replace('res://tests/fixtures/fixed_brake_legacy_outputs.json', str(OUT/'app/tests/fixtures/fixed_brake_legacy_outputs.json').replace('\\','/'))
(HERE/'test_projection.gd').write_text(projection, encoding='utf-8', newline='\n')

patch = []
entries = []
for file in sorted(OUT.rglob('*')):
    if not file.is_file() or '__pycache__' in file.parts: continue
    path = file.relative_to(OUT).as_posix()
    current = ROOT/path
    before = current.read_text(encoding='utf-8') if current.exists() else ''
    after = file.read_text(encoding='utf-8')
    patch.extend(difflib.unified_diff(before.splitlines(True), after.splitlines(True),
        fromfile='a/'+path if current.exists() else '/dev/null', tofile='b/'+path))
    entries.append(dict(path=path, base_sha256=digest(current) if current.exists() else None,
                        payload_sha256=digest(file)))
(HERE/'review.patch').write_text(''.join(patch), encoding='utf-8', newline='\n')
(HERE/'promotion-manifest.json').write_text(json.dumps(dict(scope='draft-only, not promoted', files=entries), indent=2)+'\n')
print(json.dumps(entries,indent=2))
