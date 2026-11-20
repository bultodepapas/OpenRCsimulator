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
import math
import os
from pathlib import Path
import platform
import py_compile
import re
import stat
import struct
import subprocess
import sys
import tempfile
import types
from unittest.mock import patch
import zlib

MAX_INVENTORY = 2 * 1024 * 1024
MAX_INVENTORY_DEPTH = 64
MAX_EXAMPLES = 32
MAX_CHECK_REPORT_BYTES = 2 * 1024 * 1024


def load_repository_module(filename, name):
    """Execute a captured, fixed repository tool, never a model or user path.

    Loading source explicitly avoids a timestamp-valid stale .pyc while the
    receipt hashes different .py bytes. This is reproducibility, not trust or
    authentication of locally editable tools.
    """
    if filename not in ('inspect_pkg.py', 'inspect_definition.py'):
        raise ValueError('not a fixed repository research module')
    path = Path(__file__).resolve().with_name(filename)
    flags = os.O_RDONLY | getattr(os, 'O_NONBLOCK', 0) | getattr(os, 'O_BINARY', 0)
    with os.fdopen(os.open(path, flags), 'rb') as source:
        if not stat.S_ISREG(os.fstat(source.fileno()).st_mode):
            raise ValueError('repository tool source must be a regular file')
        data = source.read(512 * 1024 + 1)
    if len(data) > 512 * 1024:
        raise ValueError('repository tool source limit exceeded')
    module = types.ModuleType(name)
    module.__file__ = str(path)
    sys.modules[name] = module
    exec(compile(data, str(path), 'exec'), module.__dict__)
    return module, hashlib.sha256(data).hexdigest()


probe, PROBE_SOURCE_SHA256 = load_repository_module('inspect_pkg.py', 'inspect_pkg')


def strict_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise probe.FormatError('duplicate inventory key')
        result[key] = value
    return result


def reject_constant(value):
    raise probe.FormatError('non-finite JSON constant in inventory')


def finite_float(value):
    number = float(value)
    if not math.isfinite(number):
        raise probe.FormatError('non-finite JSON number in inventory')
    return number


def capture_inventory(path):
    data = probe.read_regular_file(path, MAX_INVENTORY)
    depth, quoted, escaped = 0, False, False
    for byte in data:
        if quoted:
            if escaped:
                escaped = False
            elif byte == 92:
                escaped = True
            elif byte == 34:
                quoted = False
        elif byte == 34:
            quoted = True
        elif byte in (91, 123):
            depth += 1
            if depth > MAX_INVENTORY_DEPTH:
                raise probe.FormatError('inventory structural depth limit exceeded')
        elif byte in (93, 125):
            depth -= 1
    try:
        inventory = json.loads(data.decode('utf-8'), object_pairs_hook=strict_object,
                               parse_constant=reject_constant, parse_float=finite_float)
    except RecursionError as exc:
        raise probe.FormatError('inventory nesting exceeds the JSON reader limit') from exc
    return data, inventory


def inventory_examples(inventory):
    if not isinstance(inventory, dict) or not isinstance(inventory.get('examples'), dict):
        raise probe.FormatError('inventory requires an examples object')
    examples = inventory['examples']
    if not 0 < len(examples) <= MAX_EXAMPLES:
        raise probe.FormatError('inventory example count outside research profile')
    for specimen_id, example in examples.items():
        if not re.fullmatch(r'[a-z0-9][a-z0-9_-]{0,79}', specimen_id):
            raise probe.FormatError('unsafe inventory specimen ID')
        if not isinstance(example, dict) or not isinstance(example.get('pkg_probe'), dict):
            raise probe.FormatError('inventory example requires a package result')
        if not re.fullmatch(r'[0-9a-f]{64}', str(example['pkg_probe'].get('input_sha256', ''))):
            raise probe.FormatError('inventory requires an exact lowercase input SHA-256')
    return examples


def open_samples_directory(path):
    # Research corpus verification deliberately requires this OS primitive.
    # The directory can move after opening: every read still uses this handle.
    if (os.open not in os.supports_dir_fd or not hasattr(os, 'O_NOFOLLOW')
            or not hasattr(os, 'O_DIRECTORY')):
        raise probe.FormatError('confined corpus capture needs dir_fd and no-follow support')
    return os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)


def write_new_report(path, output):
    # Exclusive create also refuses symlink/hardlink aliases of existing inputs.
    with path.open('x', encoding='utf-8', newline='\n') as destination:
        destination.write(output)


def serialize_check_report(report):
    output = json.dumps(report, indent=2, ensure_ascii=True, allow_nan=False) + '\n'
    if len(output) > MAX_CHECK_REPORT_BYTES:
        raise probe.FormatError('verification receipt byte limit exceeded')
    return output


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
    if not __debug__:
        raise ValueError('verification requires assertions; optimized Python is unsupported')
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


def run_real(inventory, samples_directory):
    examples = inventory_examples(inventory)
    results = []
    directory_fd = open_samples_directory(samples_directory)
    try:
        for specimen_id, example in examples.items():
            data = probe.read_regular_file(specimen_id + '.pkg', probe.MAX_INPUT,
                                           dir_fd=directory_fd, nofollow=True)
            expected = example['pkg_probe']
            if probe.sha(data) != expected['input_sha256']:
                raise AssertionError(f'input identity mismatch: {specimen_id}')
            actual = probe.inspect(data)
            if actual != expected:
                raise AssertionError(f'inventory mismatch: {specimen_id}')
            results.append({'specimen_id': specimen_id, 'input_sha256': actual['input_sha256'],
                            'input_bytes': actual['input_bytes'], 'member_count': actual['member_count'],
                            'result': 'exact inventory match'})
    finally:
        os.close(directory_fd)
    return results


def run_capture_checks():
    if not __debug__:
        raise ValueError('verification requires assertions; optimized Python is unsupported')
    checks = []

    def refusal(name, action):
        try:
            action()
        except (probe.FormatError, OSError, ValueError):
            checks.append({'name': name, 'result': 'rejected'})
        else:
            raise AssertionError('missing capture refusal: ' + name)

    data = package(tree())
    expected = probe.inspect(data)
    inventory = {'examples': {'owned': {'pkg_probe': expected}}}
    with tempfile.TemporaryDirectory(prefix='openrc-px-capture-') as temporary:
        directory = Path(temporary)
        sample = directory / 'owned.pkg'
        sample.write_bytes(data)
        optimized = subprocess.run([sys.executable, '-O', str(Path(__file__).resolve())],
                                   capture_output=True, text=True, timeout=5)
        assert optimized.returncode == 1 and 'optimized Python' in optimized.stderr
        checks.append({'name': 'optimized Python cannot emit passing verification receipts', 'result': 'passed'})
        inventory_path = directory / 'inventory.json'
        inventory_path.write_text(json.dumps(inventory), encoding='utf-8')
        captured, parsed = capture_inventory(inventory_path)
        inventory_path.write_bytes(b'changed after capture')
        assert parsed == inventory and probe.sha(captured) != probe.sha(inventory_path.read_bytes())
        checks.append({'name': 'inventory parse and identity use the same captured bytes', 'result': 'passed'})
        refusal('bounded regular capture', lambda: probe.read_regular_file(sample, len(data) - 1))
        refusal('directory is not a regular file', lambda: probe.read_regular_file(directory, 128))
        for specimen_id in ('../outside', '/absolute', 'a/b', 'a\\b', '.', 'C:drive'):
            refusal('unsafe inventory ID ' + repr(specimen_id),
                    lambda specimen_id=specimen_id: inventory_examples(
                        {'examples': {specimen_id: {'pkg_probe': expected}}}))
        inventory_path.write_bytes(b'{"examples":{},"examples":{}}')
        refusal('duplicate inventory keys', lambda: capture_inventory(inventory_path))
        inventory_path.write_bytes(b'{"examples":NaN}')
        refusal('non-finite inventory value', lambda: capture_inventory(inventory_path))
        inventory_path.write_bytes(b'{"examples":{},"metadata":1e9999}')
        refusal('overflowing JSON exponent is not a finite inventory number', lambda: capture_inventory(inventory_path))
        inventory_path.write_bytes(b'[' * 1500 + b'0' + b']' * 1500)
        refusal('excessive inventory nesting has a controlled refusal', lambda: capture_inventory(inventory_path))
        refusal('empty inventory', lambda: inventory_examples({'examples': {}}))
        with patch.dict(serialize_check_report.__globals__, {'MAX_CHECK_REPORT_BYTES': 16}):
            refusal('verification receipt output budget', lambda: serialize_check_report({'value': 'x' * 32}))
        assert probe.classify(b'\xff\xd8\xff')['kind'] == 'JPEG signature'
        assert PROBE_SOURCE_SHA256 == probe.sha(probe.read_regular_file(Path(probe.__file__), 512 * 1024))
        checks.append({'name': 'executed probe source capture has recorded hash', 'result': 'passed'})
        cache_case = directory / 'source-identity'
        cache_case.mkdir()
        probe_path = cache_case / 'inspect_pkg.py'
        current_source = probe.read_regular_file(Path(probe.__file__), 512 * 1024)
        old_source = current_source.replace(b'JPEG signature', b'JPEK signature')
        assert len(old_source) == len(current_source) and old_source != current_source
        probe_path.write_bytes(old_source)
        py_compile.compile(str(probe_path), doraise=True,
                           invalidation_mode=py_compile.PycInvalidationMode.TIMESTAMP)
        original_stat = probe_path.stat()
        probe_path.write_bytes(current_source)
        os.utime(probe_path, ns=(original_stat.st_atime_ns, original_stat.st_mtime_ns))
        (cache_case / 'check_probe.py').write_bytes(probe.read_regular_file(Path(__file__), 512 * 1024))
        script = ('import check_probe as c; '
                  'assert c.probe.classify(bytes([255,216,255]))["kind"] == "JPEG signature"; '
                  'assert c.PROBE_SOURCE_SHA256 == c.probe.sha(open("inspect_pkg.py","rb").read())')
        result = subprocess.run([sys.executable, '-c', script], cwd=cache_case,
                                capture_output=True, text=True, timeout=5)
        assert result.returncode == 0, result.stderr
        checks.append({'name': 'stale equal-size timestamp pyc cannot replace captured probe source', 'result': 'passed'})
        refusal('report cannot replace a source file', lambda: write_new_report(sample, 'report'))
        assert sample.read_bytes() == data
        if os.open in os.supports_dir_fd and hasattr(os, 'O_NOFOLLOW') and hasattr(os, 'O_DIRECTORY'):
            assert run_real(parsed, directory)[0]['input_sha256'] == probe.sha(data)
            checks.append({'name': 'confined exact sample capture', 'result': 'passed'})
            inventory_path.write_text(json.dumps(inventory), encoding='utf-8')
            original_inventory = inventory_path.read_bytes()
            real_capture = capture_inventory

            def change_after_capture(path):
                captured_result = real_capture(path)
                path.write_bytes(b'changed during verification')
                return captured_result

            out, err = io.StringIO(), io.StringIO()
            with patch.object(sys, 'argv', ['check_probe.py', '--inventory', str(inventory_path),
                                           '--samples-dir', str(directory)]):
                with patch.dict(main.__globals__, {'capture_inventory': change_after_capture,
                                                   'run_synthetic': lambda: [], 'run_capture_checks': lambda: []}):
                    with redirect_stdout(out), redirect_stderr(err):
                        code = main()
            assert code == 0, err.getvalue()
            assert json.loads(out.getvalue())['inventory_sha256'] == probe.sha(original_inventory)
            checks.append({'name': 'CLI receipt keeps inventory capture hash after on-disk mutation', 'result': 'passed'})
            link = directory / 'alias.pkg'
            link.symlink_to(sample)
            refusal('sample symlink is refused', lambda: run_real(
                {'examples': {'alias': {'pkg_probe': expected}}}, directory))
            refusal('report symlink cannot overwrite source', lambda: write_new_report(link, 'report'))
            hardlink = directory / 'hardlink.pkg'
            os.link(sample, hardlink)
            refusal('report hardlink cannot overwrite source', lambda: write_new_report(hardlink, 'report'))
            assert sample.read_bytes() == data
        else:
            checks.append({'name': 'confined sample and alias checks', 'result': 'not run: OS primitive unavailable'})
        if hasattr(os, 'mkfifo') and hasattr(os, 'O_NONBLOCK'):
            fifo = directory / 'fifo.pkg'
            os.mkfifo(fifo)
            result = subprocess.run([sys.executable, probe.__file__, str(fifo), '--sha256', '0' * 64],
                                    capture_output=True, text=True, timeout=3)
            assert result.returncode == 1 and 'only regular files' in result.stderr
            checks.append({'name': 'FIFO rejected without waiting for a writer', 'result': 'passed'})
            probe_path.unlink()
            os.mkfifo(probe_path)
            result = subprocess.run([sys.executable, '-c', 'import check_probe'], cwd=cache_case,
                                    capture_output=True, text=True, timeout=3)
            assert result.returncode != 0 and 'regular file' in result.stderr
            checks.append({'name': 'fixed repository tool source also refuses FIFO capture', 'result': 'passed'})
        else:
            checks.append({'name': 'FIFO rejection', 'result': 'not run: OS primitive unavailable'})
    return checks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inventory', type=Path)
    parser.add_argument('--samples-dir', type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    if not __debug__:
        print('probe checks failed: optimized Python disables required assertions', file=sys.stderr)
        return 1
    if bool(args.inventory) != bool(args.samples_dir):
        parser.error('--inventory and --samples-dir must be provided together')
    try:
        inventory_bytes, inventory = capture_inventory(args.inventory) if args.inventory else (None, None)
        report = {
        'schema': 'openrc-phoenix-research-probe-checks-v2',
        'generated_at_utc': datetime.now(timezone.utc).isoformat(),
        'python': platform.python_version(),
        'python_optimization': sys.flags.optimize,
        'zlib_runtime': zlib.ZLIB_RUNTIME_VERSION,
        'probe_source_sha256': PROBE_SOURCE_SHA256,
        'checker_on_disk_sha256': probe.sha(probe.read_regular_file(Path(__file__), 512 * 1024)),
        'identity_scope': 'In-process probe source is captured before execution; checker hash observes its on-disk file. Subprocess checks use on-disk tool files. Neither authenticates local tools.',
        'scope': 'Research framing/tree inspection only; no mesh, simulator, runtime security or flight qualification.',
        'synthetic_checks': run_synthetic(),
        'capture_checks': run_capture_checks(),
        'real_samples': run_real(inventory, args.samples_dir) if inventory is not None else [],
        }
        if inventory_bytes is not None:
            report['inventory_sha256'] = probe.sha(inventory_bytes)
        output = serialize_check_report(report)
        if args.report:
            write_new_report(args.report, output)
        else:
            print(output, end='')
    except (probe.FormatError, OSError, ValueError, AssertionError) as exc:
        print(f'probe checks failed: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
