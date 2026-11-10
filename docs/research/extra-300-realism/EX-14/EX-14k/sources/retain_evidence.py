"""Audit and retain EX-14k, including the distinct control tapes and exact replays."""
import csv
import gzip
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUN = Path(__file__).resolve().parent
DATA = RUN / 'final'
OUT = ROOT / 'docs/research/extra-300-realism/EX-14/EX-14k'
CASES = ('baseline', 'neutral-rudder', 'ball-rudder', 'release-1s', 'release-2p5s')
EXPECTED_DIVERGENCE = {'neutral-rudder': 2997, 'ball-rudder': 2997, 'release-1s': 3238, 'release-2p5s': 3598}
PROBE = ROOT / 'research/extra-300/ex14/stall_probe.gd'
hash_bytes = lambda value: hashlib.sha256(value).hexdigest()
probe_hash = hash_bytes(PROBE.read_bytes())
old = json.loads((ROOT / 'docs/research/extra-300-realism/EX-14/EX-14j/summary.json').read_text())


def read_csv(path):
    return list(csv.DictReader(line for line in path.read_text().splitlines() if not line.startswith('#')))


def bank(row):
    w, x, y, z = (float(row[k]) for k in ('qw', 'qx', 'qy', 'qz'))
    return math.degrees(math.atan2(2*(w*x+y*z), 1-2*(x*x+y*y)))


def pitch(row):
    w, x, y, z = (float(row[k]) for k in ('qw', 'qx', 'qy', 'qz'))
    return math.asin(max(-1.0, min(1.0, 2*(w*y-z*x))))


audits, reports, rows = {}, {}, {}
for name in CASES:
    report = json.loads((DATA / name / 'normal_hands_off.json').read_text())
    replay = json.loads((DATA / (name + '-exact') / 'replay.json').read_text())
    assert report['probe_sha256'] == probe_hash
    assert report['aircraft_input_sha256'] == old['inputs']['candidate_sha256']
    assert report['solver_sha256'] == old['runtime']['solver_sha256']
    assert replay['complete'] and not replay['solver_changed'] and replay['mode'] == 'exact'
    assert replay['status'] == 'ok' and replay['events_omitted'] == 0
    assert replay['current_solver_sha256'] == report['solver_sha256']
    assert replay['candidate_identity']['sha256'] == report['aircraft_input_sha256']
    events = replay['events']
    stop_tick, release_tick = [item['tick'] for item in events if item['kind'] == 'marker']
    assert stop_tick == report['stop']['tick'] == 2996
    values = read_csv(DATA / (name + '-exact') / 'flight.csv')
    assert len(values) == replay['rows'] and int(values[-1]['tick']) == replay['final_tick']
    assert [int(row['tick']) for row in values] == list(range(len(values)))
    assert all(math.isfinite(float(value)) for row in values for value in row.values())
    release_rows = [row for row in values if int(row['tick']) >= release_tick]
    # Actual surfaces, not raw sticks: neutral cancellation must converge before one second.
    if name == 'neutral-rudder':
        assert max(abs(float(row['srv_yaw'])) for row in values if int(row['tick']) > stop_tick+240) < 1e-10
    reports[name], rows[name] = report, values
    audits[name] = dict(
        exact=True, complete=True, solver_changed=False, ticks=replay['final_tick'], rows=replay['rows'],
        recording_sha256=replay['source_sha256'], stop_tick=stop_tick, release_tick=release_tick,
        requested_hold_s=report['hold_s'], actual_hold_until_release_marker_s=(release_tick-stop_tick)/240,
        max_bank_held_deg=report['max_bank_held_deg'],
        max_bank_during_3s_release_deg=max(abs(bank(row)) for row in release_rows),
        height_lost_held_m=report['height_lost_held_m'], height_lost_release_m=report['height_lost_release_m'],
        endpoint_climb_mps=report['release_end']['climb'], endpoint_alpha_deg=report['release_end']['alpha'],
        max_abs_beta_held_deg=report['max_abs_beta_held_deg'],
        max_abs_lateral_g_held=report['max_abs_lateral_g_held'],
        min_heading_condition_cos_pitch=min(abs(math.cos(pitch(row))) for row in values[:release_tick+1]),
        source='distinct control-input intervention; not an aircraft-data candidate')

historical = read_csv(ROOT / 'tmp/extra300-roll-continuity-20261109/candidate-exact/flight.csv')
assert rows['baseline'] == historical, 'Instrumented default changed a recorded numeric column'
for name in CASES[1:]:
    first = next(i for i, (a, b) in enumerate(zip(rows['baseline'], rows[name])) if a != b)
    assert first == EXPECTED_DIVERGENCE[name]
    assert reports[name]['stop'] == reports['baseline']['stop']
    assert reports[name]['entry_trims'] == reports['baseline']['entry_trims']
    audits[name]['first_different_tick'] = first
    audits[name]['same_stop_checkpoint_and_input_prefix'] = True

assert not (OUT / 'manifest.json').exists(), 'Completed evidence is immutable'
OUT.mkdir(exist_ok=True)
files = []


def put(raw, target, source, compress=False):
    original = raw
    if compress:
        raw, target = gzip.compress(raw, mtime=0), target + '.gz'
    path = OUT / target
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        assert path.read_bytes() == raw
    else:
        path.write_bytes(raw)
    files.append(dict(path=target, bytes=len(raw), sha256=hash_bytes(raw), source=source,
                      original_bytes=len(original), original_sha256=hash_bytes(original),
                      compression='gzip' if compress else 'none'))


def keep(path, target):
    put(path.read_bytes(), target, path.relative_to(ROOT).as_posix(), path.suffix in ('.csv', '.orfl'))


for name in CASES:
    for filename in ('normal_hands_off.json', 'normal_hands_off.orfl'):
        keep(DATA / name / filename, name + '/' + filename)
    for filename in ('replay.json', 'flight.csv', 'godot.log'):
        keep(DATA / (name+'-exact') / filename, name + '/exact/' + filename)
for path in sorted((RUN / 'final-checks').rglob('*')):
    if path.is_file():
        if path.name == 'report.json':
            assert json.loads(path.read_text())['ok']
        keep(path, path.relative_to(RUN).as_posix())
for path in (DATA / 'integrated-high-rate').iterdir():
    if path.is_file():
        keep(path, 'integrated-high-rate/' + path.name)
for source in ('research/extra-300/ex14/stall_probe.gd', 'research/extra-300/ex14/test_stall_probe.py',
               'research/flight-test/pilot.gd', 'research/flight-robustness/d8b-r2/analog/post_stall_sweep.gd',
               'research/flight-robustness/d8b-r2/analog/faser_cl.csv',
               'research/flight-robustness/d8b-r2/analog/faser_clp.csv'):
    keep(ROOT / source, 'sources/' + source)
keep(RUN / 'cli-tests.txt', 'cli-tests.txt')
keep(RUN / 'post-stall-sweep-qualified.txt', 'post-stall-sweep.txt')
keep(Path(__file__).resolve(), 'sources/retain_evidence.py')
summary = dict(format='openrc-extra-evidence-ex14k-v1', date='2026-11-09',
    purpose='Stall protocol timing/coordination sensitivity; no aircraft-data or force-law retune.',
    probe_sha256=probe_hash, aircraft_input_sha256=old['inputs']['candidate_sha256'],
    solver_sha256=old['runtime']['solver_sha256'], runtime_reconstruction='../EX-14j/summary.json',
    base_source_patch='../EX-14j/sources/frozen-baseline.patch',
    engine='4.8.beta2.official.cafc17a19', engine_sha256=old['runtime']['engine_sha256'],
    backend='gdscript_reference', dt_s=1/240,
    unchanged_default=dict(previous_case='../EX-14j/candidate-exact/flight.csv.gz',
                           numeric_rows_identical=True, rows=4917, comparison='all CSV columns; metadata text may differ'),
    arms=audits, total_exact_ticks=sum(v['ticks'] for v in audits.values()),
    cli_tests=dict(tests=3, invalid_invocations=8, result='pass; no output directory created'),
    limits=['Distinct input tapes, not same-input aircraft candidates.',
            'Different hold windows and total durations; post-release window is 3 s in each arm.',
            'Both early-release endpoints are still descending; no level-flight recovery claim.',
            'P.ball intervention is bounded feedback; not perfectly coordinated flight.',
            'Qualitative reports do not specify this protocol or validate its five-second behavior.',
            'Frozen-reference causality does not qualify concurrent main-tree or native changes.'])
put((json.dumps(summary, indent=2)+'\n').encode(), 'summary.json', 'source and complete CSV audit')
(OUT / 'manifest.json').write_text(json.dumps(dict(format='openrc-extra-evidence-ex14k-v1', complete=True,
    files=files, note='Deterministic gzip; all originals remain in ignored tmp/. No images.'), indent=2)+'\n', encoding='utf-8')
print(json.dumps(dict(payloads=len(files), retained_mib=round(sum(x['bytes'] for x in files)/1048576,2),
    exact_ticks=summary['total_exact_ticks'], results=audits), indent=2))
