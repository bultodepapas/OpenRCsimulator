"""Count libm calls and compare six double bit patterns for the current local_loads vs a branch-only candidate."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

here = Path(__file__).resolve().parent
repo = Path(sys.argv[1]).resolve()
source = repo / 'research/native-kernel/src'
header = (source / 'nk_aero.hpp').read_text()
start = header.index('\t\tif (ge_active) {\n\t\t\tbase +=', header.index('inline Loads local_loads('))
end = header.index('\t\tR flap_profile_drag', start)
block = header[start:end]
legacy_ge = block[block.index('\t\t\tcl ='):block.index('\t\t\tif (m.polar.enabled)')]
second = block[block.index('\t\t} else {'):]
legacy_clean = second[second.index('\t\t\tcl ='):second.index('\t\t\tif (m.polar.enabled)')]
polar_ge = block[block.index('\t\t\t\tconst R progression'):block.index('\n\t\t\t}')]
polar_clean = second[second.index('\t\t\t\tconst R progression'):second.index('\n\t\t\t}')]
candidate = header[:start] + (
    '\t\tif (ge_active) {\n'
    '\t\t\tbase += (1.0 - ge[i]) * (strip_slope * (effective + m.strip_alpha_zero) - base);\n'
    '\t\t\tif (m.polar.enabled) {\n' + polar_ge + '\n\t\t\t} else {\n' + legacy_ge + '\t\t\t}\n'
    '\t\t} else {\n'
    '\t\t\tif (m.polar.enabled) {\n' + polar_clean + '\n\t\t\t} else {\n' + legacy_clean + '\t\t\t}\n'
    '\t\t}\n') + header[end:]
assert len(legacy_ge) > 100 and len(legacy_clean) > 100 and polar_ge != polar_clean
with tempfile.TemporaryDirectory(dir=here) as temp_dir:
    work = Path(temp_dir)
    (work / 'nk_aero.hpp').write_text(candidate)
    flags = ['-std=c++17', '-O2', '-fno-fast-math', '-ffp-contract=off']
    def run(name, candidate_build):
        exe = work / name
        include = [f'-I{work}'] if candidate_build else []
        subprocess.run(['g++', *flags, *include, f'-I{source}', str(here / 'polar_probe.cpp'),
                        '-Wl,--wrap=pow', '-Wl,--wrap=sin', '-o', str(exe)], check=True)
        lines = subprocess.check_output([exe], text=True)
        return [line.split() for line in lines.splitlines()]
    before = run('baseline', False)
    after = run('candidate', True)
    assert len(before) == len(after)
    summary = {'header_sha256': hashlib.sha256(header.encode()).hexdigest(), 'compiler':
               subprocess.check_output(['g++','--version'], text=True).splitlines()[0], 'flags': flags,
               'scope':'Synthetic six-strip local_loads, GNU ld observing emitted calls to sin and pow. No timing.',
               'rows':len(before), 'mismatched_load_words':0,'errno_mismatch':0,'fp_flags_mismatch':0,'groups':{}}
    for b,a in zip(before,after):
        assert b[:5] == a[:5]
        mode = 'polar' if b[0] == '1' else 'no_polar'
        g = summary['groups'].setdefault(mode,{'rows':0, 'baseline_pow':0,'candidate_pow':0, 'baseline_sin':0,'candidate_sin':0})
        g['rows'] += 1
        summary['mismatched_load_words'] += sum(x!=y for x,y in zip(b[5:11],a[5:11]))
        summary['errno_mismatch'] += (b[11]!=a[11])
        summary['fp_flags_mismatch'] += (b[12]!=a[12])
        for name,index in [('pow',13),('sin',14)]:
            g['baseline_'+name] += int(b[index])
            g['candidate_'+name] += int(a[index])
    print(json.dumps(summary, indent=2))
    assert summary['mismatched_load_words'] == summary['errno_mismatch'] == summary['fp_flags_mismatch'] == 0
    assert summary['groups']['polar']['baseline_pow'] > summary['groups']['polar']['candidate_pow']
