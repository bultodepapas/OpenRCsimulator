#!/usr/bin/env python3
"""G1a1 negative controls on disposable copies, with a passing control."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

HERE=Path(__file__).resolve().parent
MUTATIONS={
    'bypass-source-hash':("require(sha(table_raw) == manifest['source_sha256'], 'source SHA-256 mismatch')",'pass # intentional fault','test_hash_binds_exact_bytes_before_parsing'),
    'discard-conflicting-repeat':("require(exact == unique[axis]['exact'], f'line {line_number}: conflicting duplicate coordinate')",'pass # intentional fault','test_conflicting_coordinate_refused_including_decimal_late_digits'),
    'omit-sort':('for axis in sorted(unique):','for axis in unique:','test_sorted_signed_knots_and_duplicate_provenance'),
    'invent-tunnel-rpm':("'rpm': x if kind == 'static' else None","'rpm': x if kind == 'static' else 6000.0",'test_run_label_is_optional_and_never_becomes_measured_coverage'),
    'ignore-axis-collision':("require(numbers[0] not in float_axis, f'line {line_number}: distinct coordinates collapse in float64')",'pass # intentional fault','test_distinct_axes_collapsing_to_same_float_refused'),
}


def main():
    source=(HERE/'import_table.py').read_text();results=[]
    with tempfile.TemporaryDirectory(prefix='openrc-g1a1-mutations-') as d:
        work=Path(d)
        for file in ['import_table.py','test_import.py','example.synthetic.json','example.synthetic.txt']:
            shutil.copy2(HERE/file,work/file)
        for name,mutation in [('control',None),*MUTATIONS.items()]:
            candidate=source
            if mutation:
                old,new,_=mutation
                assert source.count(old)==1,name
                candidate=source.replace(old,new)
            (work/'import_table.py').write_text(candidate)
            shutil.rmtree(work/'__pycache__',ignore_errors=True)
            run=subprocess.run([sys.executable,'-B',str(work/'test_import.py')],capture_output=True,text=True,timeout=30)
            log=run.stdout+run.stderr
            assert run.returncode==(1 if mutation else 0),(name,log)
            if mutation:assert 'FAIL: '+mutation[2] in log and '\nERROR:' not in log,(name,log)
            results.append({'case':name,'exit_code':run.returncode,'intended_assertion':mutation[2] if mutation else None,'log':log})
    assert (HERE/'import_table.py').read_text()==source
    print(json.dumps({'step':'G1a1','results':results},indent=2))


if __name__=='__main__':main()
