"""Compare two complete fixed-environment tree bakes; fail on any artifact drift."""
import hashlib
import json
from pathlib import Path
import sys

def verify(left, right):
    reports = [json.loads((p/'manifest.json').read_text()) for p in (left,right)]
    if reports[0]['inputs_sha256'] != reports[1]['inputs_sha256']:
        raise ValueError('Bake inputs differ; cannot claim a repeat of the same recipe')
    for p, report in zip((left,right),reports):
        for name, digest in report['outputs_sha256'].items():
            if hashlib.sha256((p/name).read_bytes()).hexdigest() != digest:
                raise ValueError(f'Artifact does not match its manifest: {p/name}')
    if reports[0]['outputs_sha256'] != reports[1]['outputs_sha256']:
        raise ValueError('Bake output bytes differ')
    expected = {item['id']+'-'+variant+'.png' for item in reports[0]['bake']['species']
                for variant in ('source_lit','source_albedo','adapted_lit','adapted_albedo')}
    if len(expected) != 12 or any({p.name for p in (folder/'raw').glob('*.png')} != expected
                                  for folder in (left,right)):
        raise ValueError('Expected all twelve raw comparison frames in both bakes')
    for file in (left/'raw').glob('*.png'):
        if file.read_bytes() != (right/'raw'/file.name).read_bytes():
            raise ValueError(f'Raw frame differs: {file.name}')
    return {'format':'openrc-tree-repeatability v1','all_identical':True,
            'artifact_count':len(reports[0]['outputs_sha256']), 'raw_png_count':len(list((left/'raw').glob('*.png'))),
            'adapter':reports[0]['bake']['adapter'],'godot':reports[0]['godot']}

if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('Usage: verify_bakes.py BAKE_A BAKE_B')
    print(json.dumps(verify(Path(sys.argv[1]),Path(sys.argv[2])),indent=2))
