"""Measure scalar allocations in a pure native liquid turbine stage with synthetic fixed gear and fuel."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

here = Path(__file__).resolve().parent
includes = Path(sys.argv[1]).resolve() / 'research/native-kernel/src'
header = (includes / 'nk_stage.hpp').read_text()
flags = ['-std=c++17', '-O2', '-fno-fast-math', '-ffp-contract=off']
with tempfile.TemporaryDirectory(dir=here) as tmp:
    tmp = Path(tmp)
    changed = header.replace('const auto result = liquid_stage_finish(', 'auto result = liquid_stage_finish(')
    changed = changed.replace('const auto result = glow_stage_finish(', 'auto result = glow_stage_finish(')
    assert changed.count('out.derivative = result.derivative;') == 2
    changed = changed.replace('out.derivative = result.derivative;', 'out.derivative = std::move(result.derivative);')
    (tmp / 'nk_stage.hpp').write_text(changed)
    runs = []
    for tag in ['baseline', 'candidate']:
        exe = tmp / tag
        dirs = [f'-I{tmp}'] if tag == 'candidate' else []
        subprocess.run(['g++',*flags,*dirs,f'-I{includes}',str(here/'derivative_probe.cpp'),'-o',str(exe)],check=True)
        runs.append([line.split() for line in subprocess.check_output([exe], text=True).splitlines()])
    summary = {'compiler': subprocess.check_output(['g++','--version'], text=True).splitlines()[0],
               'flags':flags,'header_sha256':hashlib.sha256(header.encode()).hexdigest(),
               'accepted':0,'refused':0,'differing_outputs':0,'calls_by_shape':{}}
    for b,a in zip(*runs, strict=True):
        summary['differing_outputs'] += (b[:-2] != a[:-2])
        key = 'accepted' if b[3]=='1' else 'refused'
        summary[key] += 1
        name = b[0]+'-wheel '+key
        counts = summary['calls_by_shape'].setdefault(name, {'rows':0, 'baseline_allocations':0,
            'candidate_allocations':0,'baseline_bytes':0,'candidate_bytes':0})
        counts['rows'] += 1
        for label,row in [('baseline',b),('candidate',a)]:
            counts[label+'_allocations'] += int(row[-2])
            counts[label+'_bytes'] += int(row[-1])
    print(json.dumps(summary,indent=2))
    assert summary['differing_outputs']==0
