"""Retain this dated triage campaign without rewriting raw measurements."""
from pathlib import Path
import gzip
import hashlib
import json
import math
import statistics
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
BASE = Path(__file__).resolve().parent
OUT = ROOT / 'docs/research/visual-quality-implementation/VQ-01c/baseline-2026-10-21'
sys.path.insert(0, str(ROOT))
from research.performance.native_summary import summarize_run, DEFAULT_POLICY

def digest(data):
    return hashlib.sha256(data).hexdigest()

def write(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')

manifest = json.loads((BASE/'source-manifest.json').read_text())
changed = {}
for name, original in manifest['source_sha256'].items():
    path = ROOT/name
    final = digest(path.read_bytes()) if path.is_file() else None
    if final != original:
        changed[name] = {'initial': original, 'final': final}
assert not any(name.startswith(('app/', 'assets/aircraft/')) for name in changed), changed
write(BASE/'source-verification.json', {
    'initial_head': manifest['head'],
    'retention_head': subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
    'checked_file_count': len(manifest['source_sha256']),
    'changed_files': changed,
    'runtime_and_aircraft_sources_unchanged': True,
    'scope': 'Tracked source bytes; imported caches and external background activity are not frozen.'})

native = []
for label in ('stik-live-01','stik-live-02','stik-live-03','stik-focused-smoke','pause-probe','stik-diagnostic-01'):
    raw = BASE/'native'/f'{label}.json'
    if not raw.exists():
        continue
    checked = list((BASE/'native').glob(f'{label}-*/report.json'))
    assert len(checked) == 1, (label, checked)
    log = checked[0].with_name('engine.log')
    raw.with_suffix('.log').write_bytes(log.read_bytes())
    reduced = summarize_run(raw, DEFAULT_POLICY)
    reduced['checked_report'] = checked[0].relative_to(BASE).as_posix()
    reduced['group'] = ('standard' if label.startswith('stik-live-') else 'diagnostic_or_smoke')
    native.append(reduced)
write(BASE/'native-summary.json', {'runs':native, 'baseline_qualified':False,
    'scope':'Individual reductions only. Different durations, startup routes and observer modes are not pooled.'})

rows = []
for path in sorted((BASE/'loading').glob('loading-fixed-*.json')):
    data = json.loads(path.read_text())
    assert data['complete'] and len(data['cycles']) == 2
    first, warm = data['cycles']
    rows.append({'run':path.stem,
        'home_engine_s':data['home_first_draw_engine_elapsed_usec']/1e6,
        'home_from_load_s':data['home_first_draw_from_load_usec']/1e6,
        'first_fly_ready_s':first['fly_ready_usec']/1e6,
        'first_fly_draw_s':first['fly_first_draw_usec']/1e6,
        'warm_fly_draw_s':warm['fly_first_draw_usec']/1e6,
        'first_draw_paused':first['paused_at_first_draw'],
        'warm_draw_paused':warm['paused_at_first_draw'],
        'return_draw_s':[c['return_first_draw_usec']/1e6 for c in data['cycles']],
        'orphan_nodes':[c['orphan_nodes'] for c in data['cycles']],
        'nodes_at_home':[c['nodes_at_home'] for c in data['cycles']],
        'shutdown':data['shutdown']})
stats = {}
for key in ('home_engine_s','home_from_load_s','first_fly_ready_s','first_fly_draw_s','warm_fly_draw_s'):
    values = [r[key] for r in rows]
    stats[key] = {'n':len(values),'min':min(values),'median':statistics.median(values),'max':max(values)}
write(BASE/'loading-summary.json', {'rows':rows,'statistics':stats,
    'attempts_after_repair':6,'successful_processes':len(rows),
    'unexpected_exit':'loading-fixed-02: 3221226525, no timing report; isolated settings sidecar remained',
    'interpretation':'Observed draw timing; paused draws do not establish interactive readiness. Fresh process is not cold OS/import/driver cache.'})

diagnostic = json.loads((BASE/'native/stik-diagnostic-01.json').read_text())
monitor_stats = {}
for key in ('render_cpu_ms','render_gpu_ms','frame_setup_cpu_ms','observer_poll_usec','physics_step_usec','process_time_s','physics_process_time_s'):
    values = sorted(diagnostic['raw_metrics'][key])
    monitor_stats[key] = {'n':len(values), 'p50':values[math.ceil(len(values)*0.5)-1],
        'p95':values[math.ceil(len(values)*0.95)-1], 'max':values[-1]}
write(BASE/'diagnostic-shape.json', {
    'raw_metrics_keys':list(diagnostic['raw_metrics']) if isinstance(diagnostic['raw_metrics'],dict) else str(type(diagnostic['raw_metrics'])),
    'simulation':diagnostic['simulation'], 'measured_simulation':diagnostic['measured_simulation'],
    'monitor_nearest_rank':monitor_stats,
    'scope':'Frame-sampled diagnostics; viewport GPU/CPU timings do not equal complete-frame cost or establish causality.'})

OUT.mkdir(parents=True, exist_ok=True)
artifacts = []
for source in sorted(BASE.rglob('*')):
    if not source.is_file() or '__pycache__' in source.parts:
        continue
    relative = source.relative_to(BASE)
    data = source.read_bytes()
    compressed = source.suffix == '.json' and len(data) > 128_000
    target = OUT/relative
    if compressed:
        target = target.with_suffix(target.suffix+'.gz')
    target.parent.mkdir(parents=True, exist_ok=True)
    assert not target.exists(), target
    retained = gzip.compress(data, mtime=0) if compressed else data
    target.write_bytes(retained)
    artifacts.append({'original':relative.as_posix(),'retained':target.relative_to(OUT).as_posix(),
        'raw_sha256':digest(data),'retained_sha256':digest(retained),'bytes':len(data),'gzip':compressed})
write(OUT/'evidence-manifest.json', {'format':'openrc-phase1-evidence v1',
    'source_manifest':'source-manifest.json.gz' if (OUT/'source-manifest.json.gz').exists() else 'source-manifest.json',
    'artifacts':artifacts})
print(json.dumps({'native':[{k:r[k] for k in ('report','active_flight_qualifier','metrics','performance_pass')} for r in native],
    'loading':stats,'changed_sources':changed,'artifacts':len(artifacts)},indent=2))
