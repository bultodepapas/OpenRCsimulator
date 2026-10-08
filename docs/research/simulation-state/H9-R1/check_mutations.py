#!/usr/bin/env python3
"""Remove each H9-R1 guard only in temporary scripts; each probe must fail."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--project', type=Path, default=Path('app'))
parser.add_argument('--godot', type=Path, required=True)
args = parser.parse_args()
project = args.project.resolve()
source = (project / 'tests/golden_flights.gd').read_text()
mutations = {
    'body_finiteness': (
        'if not Simulation.state_is_valid(sim.state):',
        'if sim.state.size() != RB.SIZE:',
        '''\tvar corrupt: Callable = func(tick: int, _t: float, _s: PackedFloat64Array, _l: PackedFloat64Array, _i: PackedFloat64Array, _a: PackedFloat64Array) -> void:
\t\tif tick == int(g.ticks):
\t\t\tflight.sim.state[0] = NAN
\tflight.sim.stepped.connect(corrupt)
\tvar accepted: bool = Golden.replay(flight, g).ok
\tflight.sim.stepped.disconnect(corrupt)'''),
    'clock_bound': (
        'or g.ticks > MAX_EXACT_TICK ', '',
        '''\tg.ticks = 9223372036854775807
\tfor key in ["checkpoints", "aux_checkpoints", "mode_checkpoints"]:
\t\tg[key][-1][0] = g.ticks
\tvar accepted: bool = Golden.replay(flight, g).ok'''),
    'layout_consistency': (
        'if row.size() != g[key][0].size():', 'if false:',
        '''\tg.aux_checkpoints[1].append(0.0)
\tvar accepted: bool = Golden._valid_record(g)'''),
    'checkpoint_alignment': (
        'for key in ["aux_checkpoints", "mode_checkpoints"]:', 'for key in []:',
        '''\tg.aux_checkpoints.remove_at(1)
\tvar accepted: bool = Golden.replay(flight, g).ok'''),
}
results = []
with tempfile.TemporaryDirectory(prefix='openrc-h9r1-mutations-') as temporary:
    folder = Path(temporary)
    for name, (old, new, probe) in mutations.items():
        if source.count(old) != 1:
            raise SystemExit(f'{name}: guard no longer unique; update mutation')
        outputs = []
        for mutated in [False, True]:
            helper = folder / 'golden.gd'
            helper.write_text(source.replace(old, new, 1) if mutated else source)
            script = folder / 'probe.gd'
            script.write_text('''extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const Golden := preload("%s")
func _initialize() -> void:
\tvar flight: Node = Flight.new()
\tflight.setup()
\troot.add_child(flight)
\tvar g: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/roll_15.json"))
%s
\tprint("accepted=", accepted)
\tflight.free()
\tquit(1 if accepted else 0)
''' % (helper.as_posix(), probe))
            run = subprocess.run([str(args.godot.resolve()), '--headless', '--path', str(project), '--script', str(script)], text=True, capture_output=True, timeout=30)
            expected = 1 if mutated else 0
            if run.returncode != expected or 'ERROR:' in run.stdout + run.stderr:
                raise SystemExit(f'{name} mutated={mutated}: unexpected result {run.returncode}\n{run.stdout}{run.stderr}')
            outputs.append({'mutated': mutated, 'exit_code': run.returncode, 'output': run.stdout.strip()})
        results.append({'guard': name, 'detected': True, 'runs': outputs})
print(json.dumps({'mutations': results, 'all_detected': True}, indent=2))
