from pathlib import Path
import gzip,hashlib,json,re,shutil
repo=Path(__file__).resolve().parents[1]
root=Path('D:/OpenRCsimulator-scratch/graphics-export-20261021-2463af65')
out=repo/'docs/research/visual-quality-implementation/VQ-01c/loading/package-attribution-2026-10-21'
def sha(data): return hashlib.sha256(data).hexdigest()
# Add the trim validator's exact output and this final integrity recipe.
m=json.loads((out/'evidence-manifest.json').read_text())
for source,relative in [(root/'provenance/trimmed-flight-check.txt','provenance/trimmed-flight-check.txt'),(Path(__file__),'provenance/check_package_loading_evidence.py')]:
    data=source.read_bytes(); (out/relative).write_bytes(data)
    m['files']=[r for r in m['files'] if r['retained']!=relative]
    m['files'].append({'source':str(source),'retained':relative,'raw_sha256':sha(data),'stored_sha256':sha(data)})
(out/'evidence-manifest.json').write_text(json.dumps(m,indent=2)+'\n')
for r in m['files']:
    p=out/r['retained'];data=p.read_bytes()
    assert sha(data)==r['stored_sha256'],p
    assert sha(gzip.decompress(data) if p.suffix=='.gz' else data)==r['raw_sha256'],p
checks=[]
for p in (out/'checks').rglob('report.json'):
    report=json.loads(p.read_text())
    log=p.with_name('engine.log');zipped=log.with_suffix('.log.gz')
    raw=log.read_bytes() if log.is_file() else gzip.decompress(zipped.read_bytes())
    assert sha(raw)==report['log_sha256'],p
    if not report['ok']:
        assert report['label']=='collector-native-01' and report['process_exit']==1,p
    checks.append({'label':report['label'],'ok':report['ok'],'warnings':report['counts']['warning']})
for p in (out/'runs').glob('*.json'):
    r=json.loads(p.read_text());assert r['complete'] and r['shutdown']['audio_released'] and r['shutdown']['settings_removed'],p
    assert len(r['cycles'])==2,p
    if p.stem.startswith('source'): assert r['execution']['editor_feature']
    else: assert not r['execution']['editor_feature'] and not r['execution']['debug_build']
    if p.stem in ('diagnostic-02','diagnostic-03'):
        assert all(not c['paused_at_first_draw'] and c['tick_at_first_draw']==12 for c in r['cycles'])
    if p.stem=='dependency-01': assert len(r['dependency_spans'])==66 and all(d['loaded'] for d in r['dependency_spans'])
for p in [out/'README.md',repo/'docs/plans/advanced-graphics.md',repo/'docs/plans/global-performance-visual-quality.md',repo/'docs/VISUAL-QUALITY-PLAN.md']:
    for link in re.findall(r'\]\(([^)]+)\)',p.read_text(encoding='utf-8')):
        if '://' not in link and not link.startswith('#'):
            assert (p.parent/link.split('#')[0]).exists(),(p,link)
assert sha((out/'provenance/final-export_presets.cfg').read_bytes())==sha((repo/'app/export_presets.cfg').read_bytes())
result={'retained_artifacts_verified':len(m['files']),'checked_reports':checks,'local_links':'passed','execution_identity_and_completion':'passed','preset_unchanged':True}
(out/'verification.json').write_text(json.dumps(result,indent=2)+'\n')
print(f'PASS: {len(m["files"])} artifact hashes, {len(checks)} checked logs, runtime identities, completion, local links and unchanged export preset')
