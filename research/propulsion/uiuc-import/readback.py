#!/usr/bin/env python3
"""Verify four pinned primary files; emit summary only, never redistribute full tables."""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request

import import_table as importer

HERE = Path(__file__).resolve().parent


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--raw-dir',type=Path,required=True)
    parser.add_argument('--fetch',action='store_true',help='download missing pinned sources to the external raw directory')
    args=parser.parse_args()
    raw_dir=args.raw_dir.resolve()
    # Keep third-party raw files outside the repository, including symlink-resolved paths.
    repo=HERE.parents[2]
    if raw_dir==repo or repo in raw_dir.parents:
        raise ValueError('raw directory must be outside the repository')
    raw_dir.mkdir(parents=True,exist_ok=True)
    records=json.loads((HERE/'sources.json').read_bytes())
    summaries=[]
    for manifest in records:
        file=raw_dir/manifest['source_url'].rsplit('/',1)[-1]
        if not file.exists() and args.fetch:
            raw=urllib.request.urlopen(manifest['source_url'],timeout=30).read()
            if importer.sha(raw)!=manifest['source_sha256']:
                raise ValueError('upstream source hash changed; review before rebinding')
            file.write_bytes(raw)
        raw=file.read_bytes()
        result=importer.import_table(json.dumps(manifest,sort_keys=True).encode(),raw)
        # Independent row-by-row readback using physical source lines, without dedup/sort helpers.
        source={n:tuple(map(float,line.split())) for n,line in enumerate(raw.decode('ascii').splitlines(),1) if line.strip() and n>1}
        seen=[]
        axis=[]
        for row in result['knots']:
            x=row['rpm'] if manifest['table_kind']=='static' else row['j']
            values=(x,row['ct'],row['cp']) if manifest['table_kind']=='static' else (x,row['ct'],row['cp'],row['eta'])
            for n in row['source_lines']:
                assert values==source[n],(manifest['id'],n)
                seen.append(n)
            axis.append(x)
        assert sorted(seen)==sorted(source) and len(set(seen))==len(seen)
        assert all(a<b for a,b in zip(axis,axis[1:]))
        assert result['normalization']['unique_rows']==len(set(source.values()))
        if manifest['table_kind']=='tunnel':
            assert result['per_row_rpm_extent'] is None and all(r['rpm'] is None for r in result['knots'])
        summaries.append({'id':manifest['id'],'url':manifest['source_url'],'sha256':importer.sha(raw),
                          'row_readbacks':len(seen),'normalization':result['normalization'],
                          'coordinate_axis':result['coordinate_axis'],'coordinate_extent':result['coordinate_extent'],
                          'per_row_rpm_extent':result['per_row_rpm_extent'],
                          'negative_ct_knots':sum(r['ct']<0 for r in result['knots']),
                          'coefficient_reference_diameter':result['source']['coefficient_reference_diameter']})
    print(json.dumps({'step':'G1a1','source_manifest_sha256':importer.sha((HERE/'sources.json').read_bytes()),
                      'importer_sha256':importer.sha((HERE/'import_table.py').read_bytes()),
                      'readback_sha256':importer.sha(Path(__file__).read_bytes()),'sources':summaries},indent=2))


if __name__=='__main__':main()
