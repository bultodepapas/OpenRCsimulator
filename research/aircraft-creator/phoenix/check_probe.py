#!/usr/bin/env python3
"""Check the research PKG probe using owned synthetic data and optional local samples.

No downloads, aircraft extraction, simulator execution or runtime qualification.
Run from any directory. Real samples remain external and are matched by SHA-256.
"""
import argparse
from contextlib import redirect_stderr, redirect_stdout
from datetime import datetime, timezone
import hashlib
import io
import json
from pathlib import Path
import platform
import struct
import sys
import tempfile
from unittest.mock import patch
import zlib

import inspect_pkg as probe


def u16(value):
    return struct.pack('<H', value)


def u32(value):
    return struct.pack('<I', value)


def string(value):
    return u16(len(value)) + value


def leaf(name=b'fixture.mod', data=b'owned synthetic data', children=0):
    return (b'\x00' + string(name) + string(b'author-local-private-path')
            + u32(len(data)) + data + u16(children))


def tree(record=None, padding=b''):
    return b'\x01\x00\x01\x00' + u16(1) + (leaf() if record is None else record) + padding


def package(body, label=b'1.000000', declared_size=None, compressed=None):
    packed = zlib.compress(body) if compressed is None else compressed
    size = len(body) if declared_size is None else declared_size
    return b'\x00' + string(label) + u16(1) + u32(len(packed)) + u32(size) + packed


def run_synthetic():
    checks = []

    def reject(name, data):
        try:
            probe.inspect(data)
        except probe.FormatError as exc:
            checks.append({'name': name, 'result': 'rejected', 'reason': str(exc)})
        else:
            raise AssertionError(f'accepted invalid fixture: {name}')

    valid = package(tree())
    result = probe.inspect(valid)
    member = result['members'][0]
    assert result['member_count'] == 1 and result['directories'] == 0
    assert member['path_components'] == ['fixture.mod']
    assert member['path_components_raw_hex'] == [b'fixture.mod'.hex()]
    assert member['path_component_display_decodings'] == ['utf-8']
    assert member['bytes'] == 20
    assert member['sha256'] == hashlib.sha256(b'owned synthetic data').hexdigest()
    assert member['body_offset'] == 51
    assert 'author-local-private-path' not in json.dumps(result)
    assert b'author-local-private-path'.hex() not in json.dumps(result)
    checks.append({'name': 'known single-file tree, offset, hash and private-path omission', 'result': 'passed'})

    changed_label = probe.inspect(package(tree(), label=b'9.999999'))
    assert changed_label['pkg_header_numeric_string'] == '9.999999'
    checks.append({'name': 'numeric label is reported without version interpretation', 'result': 'passed'})

    unsafe = probe.inspect(package(tree(leaf(name=b'../outside.mod'))))
    assert unsafe['members'][0]['path_components'] == ['../outside.mod']
    checks.append({'name': 'path-like name stays JSON data; no extraction API exists', 'result': 'passed'})

    aliases = b'\x01\x00\x01\x00' + u16(2) + leaf(name=b'\xc3\xa9.mod') + leaf(name=b'\xe9.mod')
    pair = probe.inspect(package(aliases))['members']
    assert pair[0]['path_components'] == pair[1]['path_components'] == ['é.mod']
    assert pair[0]['path_components_raw_hex'] != pair[1]['path_components_raw_hex']
    assert pair[0]['path_component_display_decodings'] == ['utf-8']
    assert pair[1]['path_component_display_decodings'] == ['latin-1']
    checks.append({'name': 'equal displayed names retain distinct source bytes and decoding', 'result': 'passed'})

    reject('empty input', b'')
    reject('wrong marker', b'\x01' + valid[1:])
    reject('nonnumeric header', package(tree(), label=b'not-a-label'))
    for label in (b'.', b'..', b'1..2'):
        reject('malformed decimal header ' + repr(label), package(tree(), label=label))
    reject('truncated compressed input', valid[:-1])
    reject('zlib checksum corruption', valid[:-1] + bytes([valid[-1] ^ 1]))
    reject('declared inflated size mismatch', package(tree(), declared_size=len(tree()) - 1))
    reject('extra compressed stream', package(tree(), compressed=zlib.compress(tree()) + zlib.compress(b'x')))
    reject('extra package bytes', valid + b'x')
    reject('unknown body prefix', package(b'\x00' + tree()[1:]))
    reject('unknown tree record kind', package(tree(b'\x02' + string(b'unknown'))))
    reject('file with children', package(tree(leaf(children=1))))
    reject('nonzero trailing body byte', package(tree(padding=b'x')))
    reject('padding outside probe profile', package(tree(padding=b'\x00' * (probe.MAX_ZERO_PADDING + 1))))
    reject('oversized name', package(tree(b'\x01' + u16(probe.MAX_TEXT + 1))))
    too_large = b'\x00' + string(b'large') + string(b'') + u32(probe.MAX_MEMBER + 1)
    reject('oversized member before content allocation', package(tree(too_large)))
    nested = u16(0)
    for _ in range(probe.MAX_DEPTH + 2):
        nested = u16(1) + b'\x01' + string(b'd') + nested
    reject('tree depth limit', package(b'\x01\x00\x01\x00' + nested))
    with patch.object(probe, 'MAX_INPUT', len(valid) - 1):
        reject('actual captured input limit', valid)
    with patch.object(probe, 'MAX_BODY', len(tree()) - 1):
        reject('aggregate inflated-body limit', valid)
    with patch.object(probe, 'MAX_MEMBERS', 1):
        reject('entry-count limit', package(b'\x01\x00\x01\x00' + u16(2) + leaf() + leaf()))
    sibling = b'\x01' + string(b'directory') + u16(1) + leaf()
    with patch.object(probe, 'MAX_MEMBERS', 3):
        reject('cumulative entries across sibling lists', package(b'\x01\x00\x01\x00' + u16(2) + sibling + sibling))
    amplified = u16(8) + leaf() * 8
    for _ in range(probe.MAX_DEPTH):
        amplified = u16(1) + b'\x01' + string(b'\xff' * probe.MAX_TEXT) + amplified
    reject('deep long-name output amplification', package(b'\x01\x00\x01\x00' + amplified))
    with patch.object(probe, 'MAX_REPORT_BYTES', 1):
        reject('report metadata output budget', valid)

    with tempfile.TemporaryDirectory(prefix='openrc-px-check-') as directory:
        path = Path(directory) / 'synthetic.pkg'
        path.write_bytes(valid)
        for label, expected_sha, expected_code in [
            ('CLI exact hash', probe.sha(valid), 0),
            ('CLI wrong hash', '0' * 64, 1),
        ]:
            out, err = io.StringIO(), io.StringIO()
            with patch.object(sys, 'argv', ['inspect_pkg.py', str(path), '--sha256', expected_sha]):
                with redirect_stdout(out), redirect_stderr(err):
                    code = probe.main()
            assert code == expected_code, (label, code, err.getvalue())
            if code == 0:
                assert json.loads(out.getvalue()) == result
            else:
                assert 'SHA-256 mismatch' in err.getvalue()
            checks.append({'name': label, 'result': 'passed'})
    return checks


def run_real(inventory_path, samples_directory):
    inventory = json.loads(inventory_path.read_text(encoding='utf-8'))
    results = []
    for specimen_id, example in inventory['examples'].items():
        path = samples_directory / (specimen_id + '.pkg')
        with path.open('rb') as source:
            data = source.read(probe.MAX_INPUT + 1)
        expected = example['pkg_probe']
        if probe.sha(data) != expected['input_sha256']:
            raise AssertionError(f'input identity mismatch: {specimen_id}')
        actual = probe.inspect(data)
        if actual != expected:
            raise AssertionError(f'inventory mismatch: {specimen_id}')
        results.append({'specimen_id': specimen_id, 'input_sha256': actual['input_sha256'],
                        'input_bytes': actual['input_bytes'], 'member_count': actual['member_count'],
                        'result': 'exact inventory match'})
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inventory', type=Path)
    parser.add_argument('--samples-dir', type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    if bool(args.inventory) != bool(args.samples_dir):
        parser.error('--inventory and --samples-dir must be provided together')
    report = {
        'schema': 'openrc-phoenix-research-probe-checks-v1',
        'generated_at_utc': datetime.now(timezone.utc).isoformat(),
        'python': platform.python_version(),
        'zlib_runtime': zlib.ZLIB_RUNTIME_VERSION,
        'probe_sha256': probe.sha(Path(probe.__file__).read_bytes()),
        'checker_sha256': probe.sha(Path(__file__).read_bytes()),
        'scope': 'Research framing/tree inspection only; no mesh, simulator, runtime security or flight qualification.',
        'synthetic_checks': run_synthetic(),
        'real_samples': run_real(args.inventory, args.samples_dir) if args.inventory else [],
    }
    if args.inventory:
        report['inventory_sha256'] = probe.sha(args.inventory.read_bytes())
    output = json.dumps(report, indent=2) + '\n'
    if args.report:
        args.report.write_text(output, encoding='utf-8')
    else:
        print(output, end='')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
